// VELSTRIA のフレンド用の受信箱（Durable Object FriendInbox。仕様は README.md「フレンドの受信箱」）。
//
// フレンドコード 1 つ = 受信箱 1 つ。アプリが開いている間だけ WebSocket で繋ぎ、フレンドからの招待・フレンド申請を受け取る。
// 中身（m）は解釈せずに運ぶ JSON。差出人（from）は中継が接続のコードから付けるので、なりすませない。
// 保存するのは「コードの持ち主を縛る鍵のハッシュ」と、相手が不在の時の申請（queue 指定のもの。最大 20 通・14 日）だけ。
// 在席（オンラインか）は、コードを知っている相手が問い合わせられる（コードは本人が自分で配るので、知っている = フレンド候補）。

import { DurableObject } from "cloudflare:workers";
import type { Env } from "./index";

/** フレンドコード: 部屋コードと同じ 31 文字で 8 桁 */
export const FRIEND_CODE = /^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{8}$/;
/** 受信箱の鍵（URL の key）。端末が最初に乱数で作る。16〜64 文字の英数・_・- */
const INBOX_KEY = /^[A-Za-z0-9_-]{16,64}$/;
/** 1 メッセージの上限（バイト）。招待・申請は小さなもの */
const MAX_INBOX_MESSAGE_BYTES = 4 * 1024;
/** 不在の相手のために預かる申請の上限・期限 */
const MAX_QUEUED = 20;
const QUEUE_TTL_MS = 14 * 24 * 60 * 60 * 1000;
/** 在席の問い合わせの 1 回の上限 */
const MAX_PRESENCE_CODES = 100;
/** 1 接続あたりの送信の上限（1 分あたり）。迷惑行為の歯止め */
const MAX_SENDS_PER_MINUTE = 40;
const WS_OPEN = 1;

export const INBOX_CLOSE = {
  taken: [4012, "inbox_taken"],
  replaced: [4011, "host_replaced"],
  relayVersion: [4010, "relay_version"],
  malformed: [1003, "malformed"],
  tooBig: [1009, "message_too_big"],
} as const satisfies Record<string, readonly [number, string]>;

export type DeliverResult = "delivered" | "queued" | "offline";

type Attachment = { code: string; closed?: true };

export class FriendInbox extends DurableObject<Env> {
  /** 送信の数え（ハイバネーションで消えるが、歯止めなので構わない） */
  private sends: number[] = [];

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const code = url.searchParams.get("code") ?? "";
    const key = url.searchParams.get("key") ?? "";
    if (!FRIEND_CODE.test(code) || !INBOX_KEY.test(key)) return rejectSocket(INBOX_CLOSE.malformed);

    // コードの持ち主は最初に繋いだ鍵で決まる（以後は同じ鍵でしか繋げない）
    const hash = await sha256Hex(key);
    const sql = this.ctx.storage.sql;
    sql.exec("CREATE TABLE IF NOT EXISTS owner (k INTEGER PRIMARY KEY CHECK (k = 1), key_hash TEXT NOT NULL)");
    const row = sql.exec<{ key_hash: string }>("SELECT key_hash FROM owner WHERE k = 1").toArray()[0];
    if (!row) sql.exec("INSERT INTO owner (k, key_hash) VALUES (1, ?)", hash);
    else if (row.key_hash !== hash) return rejectSocket(INBOX_CLOSE.taken);

    // 同じ持ち主の古い接続は入れ替える（アプリの再接続・別端末）
    for (const ws of this.ctx.getWebSockets("inbox")) {
      markClosed(ws);
      closeQuietly(ws, INBOX_CLOSE.replaced[0], INBOX_CLOSE.replaced[1]);
    }
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server, ["inbox"]);
    server.serializeAttachment({ code } satisfies Attachment);
    sendJson(server, { t: "hello", code });
    this.flushQueue(server);
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const attachment = readAttachment(ws);
    if (!attachment || attachment.closed) return;
    const size = typeof message === "string" ? message.length : message.byteLength;
    if (size > MAX_INBOX_MESSAGE_BYTES) {
      markClosed(ws);
      closeQuietly(ws, INBOX_CLOSE.tooBig[0], INBOX_CLOSE.tooBig[1]);
      return;
    }
    if (typeof message !== "string") return;
    let data: unknown;
    try {
      data = JSON.parse(message);
    } catch {
      return;
    }
    if (typeof data !== "object" || data === null) return;
    const req = data as Record<string, unknown>;

    if (req.t === "send") {
      const to = req.to;
      const id = typeof req.id === "number" ? req.id : 0;
      if (typeof to !== "string" || !FRIEND_CODE.test(to) || to === attachment.code || !isPlainObject(req.m)) return;
      if (!this.allowSend()) {
        sendJson(ws, { t: "ack", id, result: "offline" });
        return;
      }
      const result = await this.env.FRIEND_INBOX.getByName(to).deliver(attachment.code, req.m, req.queue === true);
      sendJson(ws, { t: "ack", id, result });
    } else if (req.t === "presence") {
      const codes = Array.isArray(req.codes) ? req.codes : [];
      const valid = [...new Set(codes.filter((c): c is string => typeof c === "string" && FRIEND_CODE.test(c)))].slice(
        0,
        MAX_PRESENCE_CODES,
      );
      const states = await Promise.all(valid.map((c) => this.env.FRIEND_INBOX.getByName(c).isOnline()));
      sendJson(ws, { t: "presence", online: valid.filter((_, i) => states[i]) });
    }
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    markClosed(ws);
    closeQuietly(ws, code, reason);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    markClosed(ws);
  }

  /** 期限切れの預かりを捨てる（残りがあれば再び目覚ましを掛ける） */
  async alarm(): Promise<void> {
    const sql = this.ctx.storage.sql;
    sql.exec("CREATE TABLE IF NOT EXISTS queue (id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL, sender TEXT NOT NULL, body TEXT NOT NULL)");
    sql.exec("DELETE FROM queue WHERE at < ?", Date.now() - QUEUE_TTL_MS);
    const left = sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM queue").one().n;
    if (left > 0) await this.ctx.storage.setAlarm(Date.now() + QUEUE_TTL_MS / 2);
  }

  // MARK: 他の受信箱（RPC）から呼ばれる

  /** from からの m を、繋がっていれば渡す。不在で queue 指定なら預かる */
  async deliver(from: string, m: object, queue: boolean): Promise<DeliverResult> {
    const open = this.openSocket();
    if (open) {
      sendJson(open, { t: "msg", from, m });
      return "delivered";
    }
    if (!queue) return "offline";
    const sql = this.ctx.storage.sql;
    sql.exec("CREATE TABLE IF NOT EXISTS queue (id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL, sender TEXT NOT NULL, body TEXT NOT NULL)");
    // 同じ差出人の同じ種類は 1 通にまとめる（連打で埋まらないように）
    const body = JSON.stringify(m);
    sql.exec("DELETE FROM queue WHERE sender = ? AND body = ?", from, body);
    const count = sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM queue").one().n;
    if (count >= MAX_QUEUED) sql.exec("DELETE FROM queue WHERE id = (SELECT MIN(id) FROM queue)");
    sql.exec("INSERT INTO queue (at, sender, body) VALUES (?, ?, ?)", Date.now(), from, body);
    if ((await this.ctx.storage.getAlarm()) === null) await this.ctx.storage.setAlarm(Date.now() + QUEUE_TTL_MS);
    return "queued";
  }

  async isOnline(): Promise<boolean> {
    return this.openSocket() !== undefined;
  }

  // MARK: 内部

  private flushQueue(ws: WebSocket): void {
    const sql = this.ctx.storage.sql;
    sql.exec("CREATE TABLE IF NOT EXISTS queue (id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL, sender TEXT NOT NULL, body TEXT NOT NULL)");
    const rows = sql.exec<{ sender: string; body: string }>("SELECT sender, body FROM queue WHERE at >= ? ORDER BY id", Date.now() - QUEUE_TTL_MS).toArray();
    for (const r of rows) {
      try {
        sendJson(ws, { t: "msg", from: r.sender, m: JSON.parse(r.body) });
      } catch {
        // 壊れた預かりは捨てる
      }
    }
    sql.exec("DELETE FROM queue");
  }

  private openSocket(): WebSocket | undefined {
    for (const ws of this.ctx.getWebSockets("inbox")) {
      const a = readAttachment(ws);
      if (ws.readyState === WS_OPEN && a && !a.closed) return ws;
    }
    return undefined;
  }

  private allowSend(): boolean {
    const now = Date.now();
    this.sends = this.sends.filter((t) => now - t < 60_000);
    if (this.sends.length >= MAX_SENDS_PER_MINUTE) return false;
    this.sends.push(now);
    return true;
  }
}

function isPlainObject(v: unknown): v is object {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function sendJson(ws: WebSocket, value: unknown): void {
  try {
    ws.send(JSON.stringify(value));
  } catch {
    // 閉じた接続への送信は捨てる
  }
}

function readAttachment(ws: WebSocket): Attachment | null {
  try {
    return ws.deserializeAttachment() as Attachment | null;
  } catch {
    return null;
  }
}

function markClosed(ws: WebSocket): void {
  const a = readAttachment(ws);
  if (!a) return;
  a.closed = true;
  try {
    ws.serializeAttachment(a);
  } catch {
    // 既に閉じた接続には書けない
  }
}

function closeQuietly(ws: WebSocket, code: number, reason: string): void {
  const sendable =
    (code >= 1000 && code <= 1014 && code !== 1004 && code !== 1005 && code !== 1006) || (code >= 3000 && code <= 4999);
  try {
    ws.close(sendable ? code : 1000, sendable ? reason : "");
  } catch {
    // 既に閉じている
  }
}

function rejectSocket([code, reason]: readonly [number, string]): Response {
  const [client, server] = Object.values(new WebSocketPair());
  server.accept();
  server.close(code, reason);
  return new Response(null, { status: 101, webSocket: client });
}
