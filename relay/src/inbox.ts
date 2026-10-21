// VELSTRIA のフレンド用の受信箱（Durable Object FriendInbox。仕様は README.md「フレンドの受信箱」）。
//
// フレンドコード 1 つ = 受信箱 1 つ。アプリが開いている間だけ WebSocket で繋ぎ、フレンドからの招待・フレンド申請を受け取る。
// 中身（m）は解釈せずに運ぶ JSON。差出人（from）は中継が接続のコードから付けるので、なりすませない。
// 保存するのは「コードの持ち主を縛る鍵のハッシュ」と最後に繋いだ日時、相手が不在の時の申請（queue 指定のもの。最大 20 通・
// 受け付けから 14 日）だけ。持ち主は本人の鍵で受信箱を消せる（erase。アプリの「全データを削除」など）。1 年繋がなければ自動で消す。
// 消した受信箱のコードは「消した印」だけを残し、二度と使えない（他人が同じコードを名乗ってフレンドの申請・招待を受け取らないように）。
// 運営が利用を止めたコード（Env.SUSPENDED_FRIEND_CODES）は、受信箱へ繋げない・送れない（index.ts と webSocketMessage で確かめる）。
// 在席（オンラインか）は、コードを知っている相手が問い合わせられる（コードは本人が自分で配るので、知っている = フレンド候補）。

import { DurableObject } from "cloudflare:workers";
import type { Env } from "./index";

/** フレンドコード: 部屋コードと同じ 31 文字で 8 桁 */
export const FRIEND_CODE = /^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{8}$/;
/** 受信箱の鍵（URL の key）。端末が最初に乱数で作る。16〜64 文字の英数・_・- */
export const INBOX_KEY = /^[A-Za-z0-9_-]{16,64}$/;
/** 1 メッセージの上限（バイト）。招待・申請は小さなもの */
const MAX_INBOX_MESSAGE_BYTES = 4 * 1024;
/** 不在の相手のために預かる申請の上限・期限 */
const MAX_QUEUED = 20;
const DAY_MS = 24 * 60 * 60 * 1000;
/** 預かりの期限（受け付けた時から。同じ申請が届き直しても延ばさない）。期限の時刻に目覚ましで消す */
export const QUEUE_TTL_MS = 14 * DAY_MS;
/** 持ち主がこの期間まったく繋がなければ、受信箱を消して「消した印」にする */
export const OWNER_IDLE_TTL_MS = 365 * DAY_MS;
/** 在席の問い合わせの 1 回の上限 */
const MAX_PRESENCE_CODES = 100;
/** 1 接続あたりの送信の上限（1 分あたり）。迷惑行為の歯止め */
const MAX_SENDS_PER_MINUTE = 40;
const WS_OPEN = 1;

export const INBOX_CLOSE = {
  taken: [4012, "inbox_taken"],
  suspended: [4013, "inbox_suspended"],
  erased: [4014, "inbox_erased"],
  replaced: [4011, "host_replaced"],
  relayVersion: [4010, "relay_version"],
  malformed: [1003, "malformed"],
  tooBig: [1009, "message_too_big"],
} as const satisfies Record<string, readonly [number, string]>;

export type DeliverResult = "delivered" | "queued" | "offline";
/** erase の結果: erased = 消した（消し済みを含む）/ none = 受信箱が無かった / forbidden = 鍵が持ち主のものでない */
export type EraseResult = "erased" | "none" | "forbidden";

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

    const sql = this.schema();
    // 消した受信箱のコードは二度と使えない（アプリは新しいコードを作り直す）
    if (this.isErased()) return rejectSocket(INBOX_CLOSE.erased);
    // コードの持ち主は最初に繋いだ鍵で決まる（以後は同じ鍵でしか繋げない）
    const hash = await sha256Hex(key);
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
    this.touch();
    await this.scheduleAlarm();
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
      // 運営が利用を止めたコード（配備・秘密の更新で接続は切れるので、ここへ来るのは行き違いだけ）
      if (isSuspended(this.env, attachment.code)) {
        markClosed(ws);
        closeQuietly(ws, INBOX_CLOSE.suspended[0], INBOX_CLOSE.suspended[1]);
        return;
      }
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
    this.touchIfOwned();
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    markClosed(ws);
    this.touchIfOwned();
  }

  /** 期限切れの預かりを捨て、長く繋がない持ち主の受信箱を消す。次の期限に目覚ましを掛け直す */
  async alarm(): Promise<void> {
    const sql = this.schema();
    if (this.isErased()) return;
    const now = Date.now();
    sql.exec("DELETE FROM queue WHERE at <= ?", now - QUEUE_TTL_MS);
    if (!this.hasOwner() && !this.hasQueue()) {
      // 持ち主のいない受信箱（宛先の打ち間違いなど）の預かりが期限で消えた: 何も残さない
      await this.ctx.storage.deleteAlarm();
      await this.ctx.storage.deleteAll();
      return;
    }
    if (this.hasOwner() && !this.openSocket()) {
      const seen = this.lastSeen();
      if (seen === undefined) {
        // 最後に繋いだ日時の記録より前からある受信箱: 今から数える
        this.touch();
      } else if (seen <= now - OWNER_IDLE_TTL_MS) {
        await this.eraseAll();
        return;
      }
    }
    await this.scheduleAlarm();
  }

  // MARK: 名刺・ランク（index.ts）から呼ばれる

  /**
   * 書き込みの鍵の照合（受信箱の持ち主と同じ鍵か）。持ち主がまだいなければ、この鍵を持ち主にする（コード 1 つに持ち主は 1 人:
   * 受信箱・ランク・名刺のどれを先に使っても同じ鍵に縛る。アプリは登録を済ませてからコードを見せる）。消したコードは使えない。
   */
  async claimOrMatch(keyHash: string): Promise<"ok" | "forbidden" | "erased"> {
    const sql = this.schema();
    if (this.isErased()) return "erased";
    const row = sql.exec<{ key_hash: string }>("SELECT key_hash FROM owner WHERE k = 1").toArray()[0];
    if (!row) {
      sql.exec("INSERT INTO owner (k, key_hash) VALUES (1, ?)", keyHash);
      this.touch();
      await this.scheduleAlarm();
      return "ok";
    }
    return row.key_hash === keyHash ? "ok" : "forbidden";
  }

  /** 最後に繋いだ日時（ミリ秒。繋いでいる間は今。名刺の「最終ログイン」）。持ち主がいなければ null */
  async lastSeenAt(): Promise<number | null> {
    this.schema();
    if (this.isErased() || !this.hasOwner()) return null;
    if (this.openSocket()) return Date.now();
    return this.lastSeen() ?? null;
  }

  // MARK: Worker（index.ts の消去の要求）から呼ばれる

  /**
   * 持ち主の鍵（のハッシュ）で受信箱を消す: 鍵のハッシュ・最後に繋いだ日時・預かった申請をすべて消し、繋がっている接続を 4014 で閉じ、
   * 「消した印」だけを残す（このコードは二度と使えない）。受信箱が無ければ何も作らずに none。
   */
  async erase(keyHash: string): Promise<EraseResult> {
    const sql = this.schema();
    if (this.isErased()) return "erased";
    const row = sql.exec<{ key_hash: string }>("SELECT key_hash FROM owner WHERE k = 1").toArray()[0];
    if (!row) {
      // 持ち主のいない受信箱（繋いだことのないコード。宛先の打ち間違いで預かった申請だけがあることもある）は、持ち主を確かめられないので触らない
      if (!this.hasQueue()) await this.ctx.storage.deleteAll();
      return "none";
    }
    if (row.key_hash !== keyHash) return "forbidden";
    await this.eraseAll();
    return "erased";
  }

  // MARK: 他の受信箱（RPC）から呼ばれる

  /** from からの m を、繋がっていれば渡す。不在で queue 指定なら預かる。消した受信箱へは渡さない */
  async deliver(from: string, m: object, queue: boolean): Promise<DeliverResult> {
    const open = this.openSocket();
    if (open) {
      sendJson(open, { t: "msg", from, m });
      return "delivered";
    }
    if (!queue) return "offline";
    const sql = this.schema();
    if (this.isErased()) return "offline";
    // 同じ差出人の同じ内容は 1 通にまとめる（連打で埋まらないように）。期限は最初に受け付けた時から数え、届き直しても延ばさない
    const body = JSON.stringify(m);
    const same = sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM queue WHERE sender = ? AND body = ?", from, body).one().n;
    if (same > 0) return "queued";
    const count = sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM queue").one().n;
    if (count >= MAX_QUEUED) sql.exec("DELETE FROM queue WHERE id = (SELECT MIN(id) FROM queue)");
    sql.exec("INSERT INTO queue (at, sender, body) VALUES (?, ?, ?)", Date.now(), from, body);
    await this.scheduleAlarm();
    return "queued";
  }

  async isOnline(): Promise<boolean> {
    return this.openSocket() !== undefined;
  }

  // MARK: 内部

  /** 表を用意して SQL を返す（owner: 鍵のハッシュ / seen: 最後に繋いだ日時 / queue: 預かり / erased: 消した印） */
  private schema(): SqlStorage {
    const sql = this.ctx.storage.sql;
    sql.exec("CREATE TABLE IF NOT EXISTS owner (k INTEGER PRIMARY KEY CHECK (k = 1), key_hash TEXT NOT NULL)");
    sql.exec("CREATE TABLE IF NOT EXISTS seen (k INTEGER PRIMARY KEY CHECK (k = 1), at INTEGER NOT NULL)");
    sql.exec("CREATE TABLE IF NOT EXISTS queue (id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER NOT NULL, sender TEXT NOT NULL, body TEXT NOT NULL)");
    sql.exec("CREATE TABLE IF NOT EXISTS erased (k INTEGER PRIMARY KEY CHECK (k = 1))");
    return sql;
  }

  private isErased(): boolean {
    return this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM erased").one().n > 0;
  }

  private hasOwner(): boolean {
    return this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM owner").one().n > 0;
  }

  private hasQueue(): boolean {
    return this.ctx.storage.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM queue").one().n > 0;
  }

  private lastSeen(): number | undefined {
    return this.ctx.storage.sql.exec<{ at: number }>("SELECT at FROM seen WHERE k = 1").toArray()[0]?.at;
  }

  /** 最後に繋いだ日時を今にする（繋いだ時・切れた時） */
  private touch(): void {
    this.ctx.storage.sql.exec("INSERT INTO seen (k, at) VALUES (1, ?) ON CONFLICT (k) DO UPDATE SET at = excluded.at", Date.now());
  }

  private touchIfOwned(): void {
    this.schema();
    if (!this.isErased() && this.hasOwner()) this.touch();
  }

  /** すべて消して「消した印」だけを残す。繋がっている接続は 4014 で閉じる */
  private async eraseAll(): Promise<void> {
    for (const ws of this.ctx.getWebSockets("inbox")) {
      markClosed(ws);
      closeQuietly(ws, INBOX_CLOSE.erased[0], INBOX_CLOSE.erased[1]);
    }
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
    this.schema().exec("INSERT OR IGNORE INTO erased (k) VALUES (1)");
  }

  /**
   * 次の期限に目覚ましを掛ける: 最も古い預かりの期限と、持ち主の放置の期限（繋いでいる間は今から 1 年後）の早い方。
   * どちらも無ければ目覚ましを外す。
   */
  private async scheduleAlarm(): Promise<void> {
    const sql = this.ctx.storage.sql;
    const now = Date.now();
    const due: number[] = [];
    const oldest = sql.exec<{ at: number | null }>("SELECT MIN(at) AS at FROM queue").one().at;
    if (oldest !== null) due.push(oldest + QUEUE_TTL_MS);
    if (this.hasOwner()) due.push(this.openSocket() ? now + OWNER_IDLE_TTL_MS : (this.lastSeen() ?? now) + OWNER_IDLE_TTL_MS);
    if (due.length === 0) {
      await this.ctx.storage.deleteAlarm();
      return;
    }
    await this.ctx.storage.setAlarm(Math.max(Math.min(...due), now + 1000));
  }

  private flushQueue(ws: WebSocket): void {
    const sql = this.ctx.storage.sql;
    const rows = sql.exec<{ sender: string; body: string }>("SELECT sender, body FROM queue WHERE at > ? ORDER BY id", Date.now() - QUEUE_TTL_MS).toArray();
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

/** 運営が利用を止めたフレンドコードか（Env.SUSPENDED_FRIEND_CODES。空白・カンマ区切り。秘密として設定し、リポジトリには書かない） */
export function isSuspended(env: Env, code: string): boolean {
  const list = env.SUSPENDED_FRIEND_CODES;
  if (!list) return false;
  return list.split(/[\s,]+/).some((c) => c.trim().toUpperCase() === code);
}

function isPlainObject(v: unknown): v is object {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

export async function sha256Hex(text: string): Promise<string> {
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
