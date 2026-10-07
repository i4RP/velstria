// VELSTRIA のインターネット対戦用の中継（仕様 v1。詳細は README.md）。
//
// 中身を解釈しない土管: ホストの iPhone（権威シミュレーション）と参加者の間で、部屋コードごとにバイト列を流すだけ。
// ゲームの手順（アプリの OnlineMessage / OnlineFramer の長さ区切り JSON）はそのまま運ぶ。何も保存しない（参加者番号の採番だけ）。
// 部屋コード 1 つ = Durable Object（RelayRoom）1 つ。WebSocket Hibernation API で、通信の無い間は DO を眠らせる。

import { DurableObject } from "cloudflare:workers";
import { FRIEND_CODE, FriendInbox } from "./inbox";

export { FriendInbox };

export interface Env {
  RELAY_ROOM: DurableObjectNamespace<RelayRoom>;
  FRIEND_INBOX: DurableObjectNamespace<FriendInbox>;
}

/** 中継の版数（URL の rv と /v1/health の relay）。形式を変えたら上げる */
const RELAY_VERSION = 1;
/** 部屋コード: 英大文字と数字から紛らわしい I L O 0 1 を除いた 31 文字で 6 桁 */
const ROOM_CODE = /^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$/;
const ROOM_PATH = /^\/v1\/rooms\/([^/]*)$/;
const INBOX_PATH = /^\/v1\/inbox\/([^/]*)$/;
/** 1 メッセージの上限（超えたら 1009 で閉じる）。アプリは 64 KiB 以下に分けて送る */
const MAX_MESSAGE_BYTES = 256 * 1024;
/** 1 部屋の参加者（ホストを除く）の上限 */
const MAX_GUESTS = 32;
/** ホストが去ってから部屋の記録（参加者番号の採番）を消すまでの猶予。この間に同じコードで戻れば番号は続きから */
const ROOM_GRACE_MS = 10 * 60 * 1000;
/** 枠の見出し: [u8 種類][u32 guestId]（ビッグエンディアン） */
const HEADER_BYTES = 5;
/** ホストの再接続の鍵（URL の hk）。ホストの端末が部屋ごとに乱数で作る。16〜64 文字の英数・_・- */
const RESUME_KEY = /^[A-Za-z0-9_-]{16,64}$/;
/** WebSocket.readyState の OPEN */
const WS_OPEN = 1;

// サーバー → ホスト
const GUEST_OPEN = 0x10;
const GUEST_DATA = 0x11;
const GUEST_CLOSE = 0x12;
// ホスト → サーバー
const SEND = 0x21;
const KICK = 0x22;

/** close コードと理由（アプリはこの組で利用者向けの文言を選ぶ） */
const CLOSE = {
  hostLeft: [4001, "host_left"],
  closedByHost: [4002, "closed_by_host"],
  noRoom: [4004, "no_room"],
  roomFull: [4008, "room_full"],
  roomTaken: [4009, "room_taken"],
  relayVersion: [4010, "relay_version"],
  hostReplaced: [4011, "host_replaced"],
  malformed: [1003, "malformed"],
  tooBig: [1009, "message_too_big"],
} as const satisfies Record<string, readonly [number, string]>;

type CloseSpec = (typeof CLOSE)[keyof typeof CLOSE];

/**
 * 接続ごとの状態（serializeAttachment でハイバネーションをまたぐ）。
 * hostKey はホストの接続 1 本ごとの識別子。ホストが入れ替わった（去って同じコードで戻った）時に、
 * 前のホストの参加者を新しいホストへ混ぜないために使う。closed は中継側で後始末を済ませた印（二重の通知を防ぐ）。
 * resumeKey はホストの端末が持つ再接続の鍵（URL の hk。参加者には渡らない）。
 */
type Attachment =
  | { role: "host"; hostKey: string; resumeKey?: string; closed?: true }
  | { role: "guest"; id: number; hostKey: string; closed?: true };

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/v1/health") {
      if (request.method !== "GET" && request.method !== "HEAD") return plain(405, "method_not_allowed");
      return Response.json({ ok: true, relay: RELAY_VERSION }, { headers: { "cache-control": "no-store" } });
    }
    const inbox = INBOX_PATH.exec(url.pathname);
    if (inbox) {
      if (request.method !== "GET") return plain(405, "method_not_allowed");
      const code = inbox[1];
      if (!FRIEND_CODE.test(code)) return plain(400, "bad_friend_code");
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return plain(426, "websocket_required", { Upgrade: "websocket" });
      }
      if (url.searchParams.get("rv") !== String(RELAY_VERSION)) return rejectSocket(CLOSE.relayVersion);
      // DO には code を query で渡す（DO の fetch は URL のパスを見ない）
      url.searchParams.set("code", code);
      return env.FRIEND_INBOX.getByName(code).fetch(new Request(url, request));
    }
    const match = ROOM_PATH.exec(url.pathname);
    if (!match) return plain(404, "not_found");
    if (request.method !== "GET") return plain(405, "method_not_allowed");
    const code = match[1];
    if (!ROOM_CODE.test(code)) return plain(400, "bad_room_code");
    const role = url.searchParams.get("role");
    if (role !== "host" && role !== "guest") return plain(400, "bad_role");
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return plain(426, "websocket_required", { Upgrade: "websocket" });
    }
    // 版数違いは受け入れてから閉じる（アプリが close コードで「アプリを更新してください」を出せるように）。DO は起こさない
    if (url.searchParams.get("rv") !== String(RELAY_VERSION)) return rejectSocket(CLOSE.relayVersion);
    return env.RELAY_ROOM.getByName(code).fetch(request);
  },
} satisfies ExportedHandler<Env>;

/** 部屋 1 つ。ホスト 1 本と参加者（最大 32）の WebSocket を持ち、枠を付け外しして中継する */
export class RelayRoom extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    // テキストの ping には DO を起こさずに pong を返す（携帯回線の NAT のタイムアウト対策の生存確認）
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }

  async fetch(request: Request): Promise<Response> {
    const role = new URL(request.url).searchParams.get("role");
    const host = this.currentHost();
    if (role === "host") {
      // ホストは 1 部屋に 1 人。同じ鍵（hk）で戻ってきたホストは、切れたのに中継がまだ気づいていない前の接続と入れ替える
      // （前の接続の参加者は host_left で閉じる。参加者は同じコードで入り直す）。鍵が無い・違うなら 4009 で、ホストはコードを作り直して再試行する
      const given = new URL(request.url).searchParams.get("hk");
      const resumeKey = given !== null && RESUME_KEY.test(given) ? given : undefined;
      if (host) {
        if (!resumeKey || host.attachment.resumeKey !== resumeKey) return rejectSocket(CLOSE.roomTaken);
        await this.finish(host.ws, host.attachment, CLOSE.hostReplaced);
      }
      const [client, server] = Object.values(new WebSocketPair());
      const attachment: Attachment = { role: "host", hostKey: crypto.randomUUID(), ...(resumeKey && { resumeKey }) };
      this.ctx.acceptWebSocket(server, ["host"]);
      server.serializeAttachment(attachment);
      return new Response(null, { status: 101, webSocket: client });
    }

    if (!host) return rejectSocket(CLOSE.noRoom);
    if (this.openGuests().length >= MAX_GUESTS) return rejectSocket(CLOSE.roomFull);
    const id = this.nextGuestId();
    if (id > 0xffffffff) return rejectSocket(CLOSE.roomFull);
    const [client, server] = Object.values(new WebSocketPair());
    const attachment: Attachment = { role: "guest", id, hostKey: host.attachment.hostKey };
    this.ctx.acceptWebSocket(server, ["guest", guestTag(id)]);
    server.serializeAttachment(attachment);
    // 受け入れたことをホストへ（この後に届く GUEST_DATA より必ず先に着く）
    sendQuietly(host.ws, frame(GUEST_OPEN, id));
    await this.scheduleCleanup(false);
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const attachment = readAttachment(ws);
    if (!attachment || attachment.closed) return;
    const size = typeof message === "string" ? message.length : message.byteLength;
    if (size > MAX_MESSAGE_BYTES) {
      await this.finish(ws, attachment, CLOSE.tooBig);
      return;
    }
    // ping 以外のテキストは無視する（ping は自動応答で、ここへは来ない）
    if (typeof message === "string") return;

    if (attachment.role === "guest") {
      // 参加者 → ホスト: そのまま GUEST_DATA に包む。前のホストの参加者（入れ替わり直後）の分は捨てる
      if (message.byteLength === 0) return;
      const host = this.currentHost();
      if (host && host.attachment.hostKey === attachment.hostKey) {
        sendQuietly(host.ws, frame(GUEST_DATA, attachment.id, new Uint8Array(message)));
      }
      return;
    }

    // ホスト → サーバー: [u8 種類][u32 guestId][payload...]
    if (message.byteLength < HEADER_BYTES) {
      await this.finish(ws, attachment, CLOSE.malformed);
      return;
    }
    const bytes = new Uint8Array(message);
    const guestId = new DataView(message).getUint32(1, false);
    // 宛先はこのホストの参加者だけ。いなければ捨てる（行き違いで去った直後など）
    const guest = this.openGuest(guestId);
    const target = guest && guest.attachment.hostKey === attachment.hostKey ? guest : undefined;
    switch (bytes[0]) {
      case SEND:
        if (target && bytes.byteLength > HEADER_BYTES) sendQuietly(target.ws, bytes.subarray(HEADER_BYTES));
        return;
      case KICK:
        if (target) await this.finish(target.ws, target.attachment, CLOSE.closedByHost);
        return;
      default:
        await this.finish(ws, attachment, CLOSE.malformed);
    }
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    const attachment = readAttachment(ws);
    // 相手からの close に応える（既に応答済み・閉じ済みなら何もしない）
    closeQuietly(ws, code, reason);
    if (attachment) await this.finish(ws, attachment);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    const attachment = readAttachment(ws);
    if (attachment) await this.finish(ws, attachment);
  }

  /** 部屋の記録の後始末: 誰も繋がっていなければ消し、まだ居れば後でもう一度確かめる */
  async alarm(): Promise<void> {
    if (this.ctx.getWebSockets().some((ws) => ws.readyState === WS_OPEN)) {
      await this.ctx.storage.setAlarm(Date.now() + ROOM_GRACE_MS);
      return;
    }
    await this.ctx.storage.deleteAll();
  }

  /**
   * 接続 1 本の終わり（相手が閉じた・切れた、または中継が閉じる）。接続ごとに 1 回だけ後始末する。
   * ホストなら、そのホストの参加者を全員 host_left で閉じる。参加者なら、ホストへ GUEST_CLOSE を送る
   * （KICK・上限超えで中継が閉じた時も送る。ホストが去った時は送らない）。
   */
  private async finish(ws: WebSocket, attachment: Attachment, close?: CloseSpec): Promise<void> {
    if (attachment.closed) return;
    markClosed(ws, attachment);
    if (close) closeQuietly(ws, close[0], close[1]);

    if (attachment.role === "guest") {
      const host = this.currentHost();
      if (host && host.attachment.hostKey === attachment.hostKey) sendQuietly(host.ws, frame(GUEST_CLOSE, attachment.id));
      return;
    }
    for (const guest of this.openGuests()) {
      if (guest.attachment.hostKey !== attachment.hostKey) continue;
      markClosed(guest.ws, guest.attachment);
      closeQuietly(guest.ws, CLOSE.hostLeft[0], CLOSE.hostLeft[1]);
    }
    await this.scheduleCleanup(true);
  }

  /** 今のホスト（開いていて、後始末の済んでいない host の接続） */
  private currentHost(): { ws: WebSocket; attachment: Extract<Attachment, { role: "host" }> } | undefined {
    for (const ws of this.ctx.getWebSockets("host")) {
      const attachment = readAttachment(ws);
      if (ws.readyState === WS_OPEN && attachment?.role === "host" && !attachment.closed) return { ws, attachment };
    }
    return undefined;
  }

  private openGuests(): { ws: WebSocket; attachment: Extract<Attachment, { role: "guest" }> }[] {
    return this.ctx.getWebSockets("guest").flatMap((ws) => {
      const attachment = readAttachment(ws);
      return ws.readyState === WS_OPEN && attachment?.role === "guest" && !attachment.closed ? [{ ws, attachment }] : [];
    });
  }

  private openGuest(id: number): { ws: WebSocket; attachment: Extract<Attachment, { role: "guest" }> } | undefined {
    for (const ws of this.ctx.getWebSockets(guestTag(id))) {
      const attachment = readAttachment(ws);
      if (ws.readyState === WS_OPEN && attachment?.role === "guest" && !attachment.closed) return { ws, attachment };
    }
    return undefined;
  }

  /** 部屋内で一意の参加者番号（1 から。部屋の寿命の間は再利用しない。眠ってもまたげるよう storage に置く） */
  private nextGuestId(): number {
    const sql = this.ctx.storage.sql;
    sql.exec("CREATE TABLE IF NOT EXISTS room (k INTEGER PRIMARY KEY CHECK (k = 1), next_guest_id INTEGER NOT NULL)");
    return sql
      .exec<{ id: number }>(
        "INSERT INTO room (k, next_guest_id) VALUES (1, 1) " +
          "ON CONFLICT (k) DO UPDATE SET next_guest_id = next_guest_id + 1 RETURNING next_guest_id AS id",
      )
      .one().id;
  }

  /**
   * 記録を消す目覚ましを掛ける。ホストが去った時は猶予の後に掛け直す（同じコードで戻れば番号は続きから）。
   * 参加者を受け入れた時は、目覚ましが無ければ掛ける（記録が残ったまま忘れられないように）。
   */
  private async scheduleCleanup(replace: boolean): Promise<void> {
    const storage = this.ctx.storage;
    if (!replace && (await storage.getAlarm()) !== null) return;
    await storage.setAlarm(Date.now() + ROOM_GRACE_MS);
  }
}

function guestTag(id: number): string {
  return `g:${id}`;
}

/** [u8 種類][u32 guestId][payload...] を組む */
function frame(type: number, guestId: number, payload?: Uint8Array): Uint8Array {
  const out = new Uint8Array(HEADER_BYTES + (payload?.byteLength ?? 0));
  out[0] = type;
  new DataView(out.buffer).setUint32(1, guestId, false);
  if (payload) out.set(payload, HEADER_BYTES);
  return out;
}

/** 受け入れてからすぐ閉じる（アプリが close コードで理由を知れるように。WebSocket の握手前に断ると理由が届かない） */
function rejectSocket([code, reason]: CloseSpec): Response {
  const [client, server] = Object.values(new WebSocketPair());
  server.accept();
  server.close(code, reason);
  return new Response(null, { status: 101, webSocket: client });
}

function plain(status: number, body: string, headers: Record<string, string> = {}): Response {
  return new Response(`${body}\n`, { status, headers: { "content-type": "text/plain; charset=utf-8", ...headers } });
}

function readAttachment(ws: WebSocket): Attachment | null {
  try {
    return ws.deserializeAttachment() as Attachment | null;
  } catch {
    return null;
  }
}

function markClosed(ws: WebSocket, attachment: Attachment): void {
  attachment.closed = true;
  try {
    ws.serializeAttachment(attachment);
  } catch {
    // 既に閉じた接続には書けない（その接続にはもう出来事が届かないので構わない）
  }
}

/** 送り先が閉じかけていても例外で処理を止めない（行き違いは捨てる） */
function sendQuietly(ws: WebSocket, data: Uint8Array): void {
  try {
    ws.send(data);
  } catch {
    // 閉じた接続への送信は捨てる
  }
}

/** close できない番号（1005 / 1006 / 1015 など、相手から届くだけのもの）は 1000 に置き換える */
function closeQuietly(ws: WebSocket, code: number, reason: string): void {
  const sendable =
    (code >= 1000 && code <= 1014 && code !== 1004 && code !== 1005 && code !== 1006) || (code >= 3000 && code <= 4999);
  try {
    ws.close(sendable ? code : 1000, sendable ? reason : "");
  } catch {
    // 既に閉じている
  }
}
