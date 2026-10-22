// VELSTRIA のインターネット対戦用の中継（仕様 v1。詳細は README.md）。
//
// 中身を解釈しない土管: ホストの iPhone（権威シミュレーション）と参加者の間で、部屋コードごとにバイト列を流すだけ。
// ゲームの手順（アプリの OnlineMessage / OnlineFramer の長さ区切り JSON）はそのまま運ぶ。部屋については何も保存しない（参加者番号の採番だけ）。
// 部屋コード 1 つ = Durable Object（RelayRoom）1 つ。WebSocket Hibernation API で、通信の無い間は DO を眠らせる。

import { DurableObject } from "cloudflare:workers";
import { FRIEND_CODE, FriendInbox, INBOX_CLOSE, INBOX_KEY, isSuspended, sha256Hex } from "./inbox";

import { RankAccount, type MatchInput, type RankCallResult } from "./rank";
import { Directory, MAX_BATCH_CODES, MAX_FRIEND_CODES, parseCard, parseMail, type RankingScope } from "./directory";
import { CloudAccount, GameCenterIndex, MAX_BLOB_BYTES, VERIFIER, verifyGameCenter, type AccountInfo, type LoginResult } from "./account";

export { CloudAccount, Directory, FriendInbox, GameCenterIndex, RankAccount };

export interface Env {
  RELAY_ROOM: DurableObjectNamespace<RelayRoom>;
  FRIEND_INBOX: DurableObjectNamespace<FriendInbox>;
  RANK_ACCOUNT: DurableObjectNamespace<RankAccount>;
  /** 公開の名刺・ランキング・運営からのメール（全体で 1 つ。getByName("global")） */
  DIRECTORY: DurableObjectNamespace<Directory>;
  /** アカウント（フレンドコード 1 つ = 1 つ。クラウド保存・パスワード・Game Center の連携） */
  CLOUD_ACCOUNT: DurableObjectNamespace<CloudAccount>;
  /** Game Center の teamPlayerID → フレンドコード（getByName("gc:<id>")） */
  GAME_CENTER_INDEX: DurableObjectNamespace<GameCenterIndex>;
  /** テストの Worker だけ: Game Center の公開鍵をこの origin の下からも取り寄せる（配備では設定しない） */
  GAME_CENTER_TEST_KEY_ORIGIN?: string;
  /** 運営のメールの登録・削除の鍵（「wrangler secret put OPS_MAIL_KEY」。公開リポジトリには書かない）。無ければ登録できない */
  OPS_MAIL_KEY?: string;
  /**
   * 運営が利用を止めたフレンドコード（空白・カンマ区切り）。通報を受けて規約違反を確かめた時に `wrangler secret put` で設定する
   * （公開リポジトリには書かない）。止めたコードは受信箱へ繋げず（4013 inbox_suspended）、申請・招待を送れない。
   */
  SUSPENDED_FRIEND_CODES?: string;
}

/** 中継の版数（URL の rv と /v1/health の relay）。形式を変えたら上げる */
const RELAY_VERSION = 1;
/** 部屋コード: 英大文字と数字から紛らわしい I L O 0 1 を除いた 31 文字で 6 桁 */
const ROOM_CODE = /^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{6}$/;
const ROOM_PATH = /^\/v1\/rooms\/([^/]*)$/;
const INBOX_PATH = /^\/v1\/inbox\/([^/]*)$/;
/** 受信箱の消去（POST。本文 {"key":"…"}）。持ち主の鍵で、中継に保存した受信箱の情報をすべて消す */
const INBOX_ERASE_PATH = /^\/v1\/inbox\/([^/]*)\/erase$/;
/** 消去の要求の本文の上限（バイト） */
const MAX_ERASE_BODY_BYTES = 1024;
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
  inboxSuspended: INBOX_CLOSE.suspended,
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
    const rank = RANK_PATH.exec(url.pathname);
    if (rank) return rankCall(request, env, rank[1], rank[2]);
    if (url.pathname === "/v1/account/login") return accountLogin(request, env);
    if (url.pathname === "/v1/account/login-gamecenter") return accountLoginGameCenter(request, env);
    const account = ACCOUNT_PATH.exec(url.pathname);
    if (account) return accountCall(request, env, account[1], account[2]);
    const profile = PROFILE_PATH.exec(url.pathname);
    if (profile) return profileCall(request, env, profile[1], profile[2]);
    if (url.pathname === "/v1/profiles") return profilesCall(request, env);
    if (url.pathname === "/v1/ranking") return rankingCall(request, env);
    if (url.pathname === "/v1/mail") return mailList(request, env);
    const mail = MAIL_PATH.exec(url.pathname);
    if (mail) return mailCall(request, env, mail[1]);
    const erase = INBOX_ERASE_PATH.exec(url.pathname);
    if (erase) return eraseInbox(request, env, erase[1]);
    const inbox = INBOX_PATH.exec(url.pathname);
    if (inbox) {
      if (request.method !== "GET") return plain(405, "method_not_allowed");
      const code = inbox[1];
      if (!FRIEND_CODE.test(code)) return plain(400, "bad_friend_code");
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return plain(426, "websocket_required", { Upgrade: "websocket" });
      }
      if (url.searchParams.get("rv") !== String(RELAY_VERSION)) return rejectSocket(CLOSE.relayVersion);
      // 運営が利用を止めたコード（DO は起こさない）
      if (isSuspended(env, code)) return rejectSocket(CLOSE.inboxSuspended);
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

/** ランク: `POST /v1/rank/<FRIENDCODE>/(get|seed|match|erase)`、本文 `{"key":"…", …}`（README.md「ランク」） */
const RANK_PATH = /^\/v1\/rank\/([^/]*)\/(get|seed|match|erase)$/;
const MAX_RANK_BODY_BYTES = 4 * 1024;

async function rankCall(request: Request, env: Env, code: string, op: string): Promise<Response> {
  if (request.method !== "POST") return plain(405, "method_not_allowed", { Allow: "POST" });
  if (!FRIEND_CODE.test(code)) return plain(400, "bad_friend_code");
  // 運営が利用を止めたコードでも消去はできる（本人の削除の求めには応じる。受信箱の消去と同じ）
  if (op !== "erase" && isSuspended(env, code)) return plain(403, "suspended");
  const text = await request.text();
  if (text.length > MAX_RANK_BODY_BYTES) return plain(400, "bad_request");
  let body: { key?: unknown; state?: unknown; match?: MatchInput };
  try {
    body = JSON.parse(text) ?? {};
  } catch {
    return plain(400, "bad_request");
  }
  if (typeof body.key !== "string" || !INBOX_KEY.test(body.key)) return plain(400, "bad_key");
  const hash = await sha256Hex(body.key);
  // 持ち主は受信箱と同じ鍵（先に使った鍵がコードの持ち主。名刺・ランク・受信箱で同じ）。消去は鍵が合えば受信箱を作らない
  if (op !== "erase") {
    const claim = await env.FRIEND_INBOX.getByName(code).claimOrMatch(hash);
    if (claim !== "ok") return plain(403, claim === "erased" ? "erased" : "forbidden");
  }
  const stub = env.RANK_ACCOUNT.getByName(code);
  let res: RankCallResult;
  switch (op) {
    case "get": res = await stub.get(hash); break;
    case "seed": res = await stub.seed(hash, body.state); break;
    case "match":
      if (!body.match || typeof body.match !== "object") return plain(400, "bad_request");
      res = await stub.match(hash, body.match);
      break;
    default: res = await stub.erase(hash);
  }
  if (!res.ok) return plain(res.error === "forbidden" ? 403 : res.error === "not_seeded" ? 409 : 400, res.error);
  // ランキングの表へ（今のランク・今シーズンの最高・勝敗）。消去なら名刺ごと消す
  const directory = env.DIRECTORY.getByName("global");
  if (op === "erase") await directory.erase(code);
  else await directory.updateRank(code, res.state);
  return Response.json(res, { headers: { "cache-control": "no-store" } });
}

// MARK: アカウント（README.md「アカウント」）

/** 持ち主の操作: 「POST /v1/account/<FRIENDCODE>/<op>」、本文 「{"key":"…",…}」（save だけ本文がプロフィールのバイト列で、鍵は見出し x-velsia-key） */
const ACCOUNT_PATH = /^\/v1\/account\/([^/]*)\/(status|password|save|gamecenter|unlink-gamecenter|erase)$/;
const MAX_ACCOUNT_BODY_BYTES = 8 * 1024;

const accountJson = (info: AccountInfo) => json({ ok: true, account: info });

/** 取り出したプロフィール（バイト列）。アカウントの状態は見出しに載せる */
function accountData(code: string, r: Extract<LoginResult, { ok: true }>): Response {
  return new Response(r.data, {
    headers: {
      "content-type": "application/octet-stream",
      "cache-control": "no-store",
      "x-velsia-code": code,
      "x-velsia-saved-at": String(r.info.savedAt ?? 0),
      "x-velsia-password": r.info.password ? "1" : "0",
      "x-velsia-gamecenter": r.info.gameCenter ? "1" : "0",
    },
  });
}

function loginFailure(r: Extract<LoginResult, { ok: false }>): Response {
  return plain(r.status, r.error, r.retryAfter ? { "retry-after": String(r.retryAfter) } : {});
}

async function accountCall(request: Request, env: Env, code: string, op: string): Promise<Response> {
  if (request.method !== "POST") return plain(405, "method_not_allowed", { Allow: "POST" });
  if (!FRIEND_CODE.test(code)) return plain(400, "bad_friend_code");
  // 運営が利用を止めたコードでも消去はできる（本人の削除の求めには応じる）
  if (op !== "erase" && isSuspended(env, code)) return plain(403, "suspended");
  let key: unknown;
  let body: Record<string, unknown> | null = null;
  let data: ArrayBuffer | null = null;
  if (op === "save") {
    key = request.headers.get("x-velsia-key");
    if (Number(request.headers.get("content-length") ?? "0") > MAX_BLOB_BYTES) return plain(413, "too_large");
    data = await request.arrayBuffer();
    if (data.byteLength > MAX_BLOB_BYTES) return plain(413, "too_large");
    if (data.byteLength === 0) return plain(400, "bad_request");
  } else {
    body = await readJson(request, MAX_ACCOUNT_BODY_BYTES);
    if (!body) return plain(400, "bad_request");
    key = body.key;
  }
  if (typeof key !== "string" || !INBOX_KEY.test(key)) return plain(400, "bad_key");
  const hash = await sha256Hex(key);
  const claim = await env.FRIEND_INBOX.getByName(code).claimOrMatch(hash);
  if (op === "erase" ? claim === "forbidden" : claim !== "ok") return plain(403, claim === "erased" ? "erased" : "forbidden");
  const account = env.CLOUD_ACCOUNT.getByName(code);
  const release = async (playerId: string | null) => {
    if (playerId) await env.GAME_CENTER_INDEX.getByName(`gc:${playerId}`).release(code);
  };
  switch (op) {
    case "status":
      return accountJson(await account.info());
    case "password":
      if (typeof body!.verifier !== "string" || !VERIFIER.test(body!.verifier)) return plain(400, "bad_verifier");
      return accountJson(await account.setPassword(body!.verifier));
    case "save": {
      const savedAt = Number(request.headers.get("x-velsia-saved-at"));
      return accountJson(await account.save(data!, Number.isSafeInteger(savedAt) && savedAt > 0 ? savedAt : Date.now()));
    }
    case "gamecenter": {
      const v = await verifyGameCenter(body!.gc, env);
      if (!v.ok) return plain(v.status, v.error);
      if ((await env.GAME_CENTER_INDEX.getByName(`gc:${v.playerId}`).claim(code)) !== "ok") return plain(409, "gamecenter_taken");
      await release(await account.linkGameCenter(v.playerId));
      return accountJson(await account.info());
    }
    case "unlink-gamecenter":
      await release(await account.unlinkGameCenter());
      return accountJson(await account.info());
    default:
      await release(await account.erase());
      return json({ ok: true, result: "erased" });
  }
}

/** ID + パスワードで取り出す: 「POST /v1/account/login」、本文 「{"code":"…","verifier":"<64 桁の 16 進>"}」 */
async function accountLogin(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") return plain(405, "method_not_allowed", { Allow: "POST" });
  const body = await readJson(request, MAX_ACCOUNT_BODY_BYTES);
  if (!body) return plain(400, "bad_request");
  const code = body.code;
  if (typeof code !== "string" || !FRIEND_CODE.test(code)) return plain(400, "bad_friend_code");
  if (typeof body.verifier !== "string" || !VERIFIER.test(body.verifier)) return plain(400, "bad_verifier");
  if (isSuspended(env, code)) return plain(403, "suspended");
  const r = await env.CLOUD_ACCOUNT.getByName(code).login(body.verifier, Date.now());
  return r.ok ? accountData(code, r) : loginFailure(r);
}

/** Game Center で取り出す: 「POST /v1/account/login-gamecenter」、本文 「{"gc":{…本人確認の署名…}}」 */
async function accountLoginGameCenter(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") return plain(405, "method_not_allowed", { Allow: "POST" });
  const body = await readJson(request, MAX_ACCOUNT_BODY_BYTES);
  if (!body) return plain(400, "bad_request");
  const v = await verifyGameCenter(body.gc, env);
  if (!v.ok) return plain(v.status, v.error);
  const code = await env.GAME_CENTER_INDEX.getByName(`gc:${v.playerId}`).code();
  if (!code) return plain(404, "not_linked");
  if (isSuspended(env, code)) return plain(403, "suspended");
  const r = await env.CLOUD_ACCOUNT.getByName(code).loginGameCenter(v.playerId);
  return r.ok ? accountData(code, r) : loginFailure(r);
}

// MARK: 名刺・ランキング・運営からのメール（README.md「名刺・ランキング・メール」）

/** 名刺: 「POST /v1/profile/<FRIENDCODE>/put|erase」、本文 「{"key":"…","profile":{…}}」 */
const PROFILE_PATH = /^\/v1\/profile\/([^/]*)\/(put|erase)$/;
/** 運営のメール: 「POST /v1/mail/publish|delete」、本文 「{"key":"<OPS_MAIL_KEY>","mail":{…}}」 / 「{"key":"…","id":"…"}」 */
const MAIL_PATH = /^\/v1\/mail\/(publish|delete)$/;
const MAX_PROFILE_BODY_BYTES = 4 * 1024;
const MAX_LIST_BODY_BYTES = 8 * 1024;
const MAX_MAIL_BODY_BYTES = 16 * 1024;

/** POST の本文を JSON として読む（大きすぎる・読めない時は null） */
async function readJson(request: Request, max: number): Promise<Record<string, unknown> | null> {
  const text = await request.text();
  if (text.length > max) return null;
  try {
    const v = JSON.parse(text);
    return typeof v === "object" && v !== null && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

const json = (v: unknown) => Response.json(v, { headers: { "cache-control": "no-store" } });

async function profileCall(request: Request, env: Env, code: string, op: string): Promise<Response> {
  if (request.method !== "POST") return plain(405, "method_not_allowed", { Allow: "POST" });
  if (!FRIEND_CODE.test(code)) return plain(400, "bad_friend_code");
  if (op === "put" && isSuspended(env, code)) return plain(403, "suspended");
  const body = await readJson(request, MAX_PROFILE_BODY_BYTES);
  if (!body) return plain(400, "bad_request");
  if (typeof body.key !== "string" || !INBOX_KEY.test(body.key)) return plain(400, "bad_key");
  const hash = await sha256Hex(body.key);
  const directory = env.DIRECTORY.getByName("global");
  if (op === "erase") {
    // 消去は鍵が合う時だけ（持ち主のいないコードは、名刺も無いので何もしない）
    const claim = await env.FRIEND_INBOX.getByName(code).claimOrMatch(hash);
    if (claim === "forbidden") return plain(403, "forbidden");
    return json({ ok: true, result: (await directory.erase(code)) ? "erased" : "none" });
  }
  const card = parseCard(body.profile);
  if (!card) return plain(400, "bad_profile");
  const claim = await env.FRIEND_INBOX.getByName(code).claimOrMatch(hash);
  if (claim !== "ok") return plain(403, claim === "erased" ? "erased" : "forbidden");
  return json({ ok: true, profile: await directory.putCard(code, card) });
}

/** 名刺をまとめて読む: 「POST /v1/profiles」、本文 「{"codes":[…]}」（最大 100。名刺のある物だけ返す） */
async function profilesCall(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") return plain(405, "method_not_allowed", { Allow: "POST" });
  const body = await readJson(request, MAX_LIST_BODY_BYTES);
  if (!body || !Array.isArray(body.codes) || body.codes.length > MAX_BATCH_CODES) return plain(400, "bad_request");
  const codes = body.codes.filter((c): c is string => typeof c === "string" && FRIEND_CODE.test(c));
  const directory = env.DIRECTORY.getByName("global");
  const profiles = await directory.profiles(codes);
  // 最終ログイン（受信箱に最後に繋いだ日時）。名刺のある人だけ
  const seen = await Promise.all(profiles.map((p) => env.FRIEND_INBOX.getByName(p.code).lastSeenAt()));
  return json({
    ok: true,
    profiles: profiles.map((p, i) => (seen[i] === null ? p : { ...p, lastSeen: new Date(seen[i] as number).toISOString() })),
  });
}

/**
 * ランキング: 「POST /v1/ranking」、本文 「{"scope":"global"|"country"|"friends","country":"JP","codes":[…],"me":"<FRIENDCODE>"}」。
 * 今シーズンの最高ランクの順に上位 100 人と、me の行（範囲の中に居なければ null = ランク外）
 */
async function rankingCall(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") return plain(405, "method_not_allowed", { Allow: "POST" });
  const body = await readJson(request, MAX_LIST_BODY_BYTES);
  if (!body) return plain(400, "bad_request");
  const scope = body.scope as RankingScope;
  if (scope !== "global" && scope !== "country" && scope !== "friends") return plain(400, "bad_scope");
  const codes = Array.isArray(body.codes) ? body.codes.filter((c): c is string => typeof c === "string") : [];
  if (codes.length > MAX_FRIEND_CODES) return plain(400, "bad_request");
  const me = typeof body.me === "string" && FRIEND_CODE.test(body.me) ? body.me : null;
  const country = typeof body.country === "string" ? body.country : null;
  const result = await env.DIRECTORY.getByName("global").ranking(scope, country, codes, me);
  return json({ ok: true, ...result });
}

/** 今公開中の運営のメール: 「GET /v1/mail」 */
async function mailList(request: Request, env: Env): Promise<Response> {
  if (request.method !== "GET") return plain(405, "method_not_allowed", { Allow: "GET" });
  return json({ ok: true, mail: await env.DIRECTORY.getByName("global").activeMail() });
}

/** 運営のメールの登録・削除（秘密の鍵 OPS_MAIL_KEY。鍵は時間の揺れの出ない比べ方で照合する） */
async function mailCall(request: Request, env: Env, op: string): Promise<Response> {
  if (request.method !== "POST") return plain(405, "method_not_allowed", { Allow: "POST" });
  const body = await readJson(request, MAX_MAIL_BODY_BYTES);
  if (!body) return plain(400, "bad_request");
  if (!env.OPS_MAIL_KEY || typeof body.key !== "string" || !(await sameSecret(body.key, env.OPS_MAIL_KEY))) {
    return plain(403, "forbidden");
  }
  const directory = env.DIRECTORY.getByName("global");
  if (op === "delete") {
    if (typeof body.id !== "string") return plain(400, "bad_request");
    return json({ ok: true, result: (await directory.deleteMail(body.id)) ? "deleted" : "none" });
  }
  const mail = parseMail(body.mail, Date.now());
  if (!mail) return plain(400, "bad_mail");
  await directory.publishMail(mail);
  return json({ ok: true, id: mail.id });
}

/** 秘密の照合（ハッシュどうしを全桁比べる。長さ・一致の位置で時間が変わらない） */
async function sameSecret(given: string, secret: string): Promise<boolean> {
  const [a, b] = await Promise.all([sha256Hex(given), sha256Hex(secret)]);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * 受信箱の消去: `POST /v1/inbox/<FRIENDCODE>/erase`、本文 `{"key":"<KEY>"}`（鍵は URL に載せない）。
 * 200 `{"ok":true,"result":"erased"|"none"}`（消した・消し済み / 受信箱が無かった）、403 `inbox_taken`（鍵が違う）、
 * 400（コード・鍵・本文の誤り）、405（POST 以外）。運営が利用を止めたコードでも消せる（本人の削除の求めには応じる）。
 */
async function eraseInbox(request: Request, env: Env, code: string): Promise<Response> {
  if (request.method !== "POST") return plain(405, "method_not_allowed", { Allow: "POST" });
  if (!FRIEND_CODE.test(code)) return plain(400, "bad_friend_code");
  const text = await request.text();
  if (text.length > MAX_ERASE_BODY_BYTES) return plain(400, "bad_request");
  let key: unknown;
  try {
    key = (JSON.parse(text) as { key?: unknown } | null)?.key;
  } catch {
    return plain(400, "bad_request");
  }
  if (typeof key !== "string" || !INBOX_KEY.test(key)) return plain(400, "bad_key");
  const result = await env.FRIEND_INBOX.getByName(code).erase(await sha256Hex(key));
  if (result === "forbidden") return plain(403, "inbox_taken");
  return Response.json({ ok: true, result }, { headers: { "cache-control": "no-store" } });
}

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
