// VELSTRIA のアカウント（Durable Object CloudAccount と GameCenterIndex。仕様は README.md「アカウント」）。
//
// フレンドコード 1 つ = アカウント 1 つ（アカウント ID はフレンドコード）。持ち主は受信箱と同じ鍵（Worker が FriendInbox.claimOrMatch で確かめる）。
// - クラウド保存: 端末のプロフィール（zlib で縮めた JSON）を預かる。別の端末で「ID + パスワード」か「Game Center」で取り出すと、
//   プロフィールに入っているフレンドコードと鍵ごとアカウントが移る（MLBB のアカウント切替）。
// - パスワード: 端末が PBKDF2（10 万回）で作った照合値（64 桁の 16 進）を受け取り、塩を付けた SHA-256 だけを保存する。
//   5 回続けて違えば 15 分ロックする。
// - Game Center: 端末の本人確認の署名（GKLocalPlayer.fetchItems(forIdentityVerificationSignature:)）を Apple の公開鍵で確かめ、
//   teamPlayerID → フレンドコード の索引（GameCenterIndex。teamPlayerID 1 つ = DO 1 つ）を作る。

import { DurableObject } from "cloudflare:workers";
import type { Env } from "./index";
import { sha256Hex } from "./inbox";

/** 照合値（端末の PBKDF2 の出力。64 桁の 16 進） */
export const VERIFIER = /^[0-9a-f]{64}$/;
/** 預かるプロフィールの上限（縮めた後のバイト数） */
export const MAX_BLOB_BYTES = 4 * 1024 * 1024;
/** 保存の 1 区切り（SQLite の DO の値は鍵と合わせて 2 MB まで。余裕を持って分ける） */
const CHUNK_BYTES = 512 * 1024;
/** パスワードを続けて違えた回数の上限と、超えた時のロックの長さ */
export const MAX_FAILURES = 5;
export const LOCK_MS = 15 * 60 * 1000;

/** アカウントの状態（アプリへ返す形） */
export interface AccountInfo {
  /** パスワードを設定した */
  password: boolean;
  /** 最後にクラウドへ保存した日時（端末の時計。ミリ秒）。無ければ null */
  savedAt: number | null;
  /** 預かっているプロフィールの大きさ（バイト） */
  size: number;
  /** Game Center と連携している */
  gameCenter: boolean;
}

interface Meta {
  salt?: string;
  passwordHash?: string;
  failures: number;
  lockedUntil: number;
  savedAt: number | null;
  size: number;
  chunks: number;
  gameCenter: string | null;
}

export type LoginResult =
  | { ok: true; data: ArrayBuffer; info: AccountInfo }
  | { ok: false; status: number; error: string; retryAfter?: number };

export class CloudAccount extends DurableObject<Env> {
  private meta(): Meta {
    return this.ctx.storage.kv.get<Meta>("meta") ?? { failures: 0, lockedUntil: 0, savedAt: null, size: 0, chunks: 0, gameCenter: null };
  }

  private static info(m: Meta): AccountInfo {
    return { password: !!m.passwordHash, savedAt: m.savedAt, size: m.size, gameCenter: !!m.gameCenter };
  }

  private readBlob(m: Meta): ArrayBuffer | null {
    if (m.chunks <= 0) return null;
    const parts: ArrayBuffer[] = [];
    let total = 0;
    for (let i = 0; i < m.chunks; i++) {
      const part = this.ctx.storage.kv.get<ArrayBuffer>(`blob:${i}`);
      if (!part) return null;
      parts.push(part);
      total += part.byteLength;
    }
    const out = new Uint8Array(total);
    let at = 0;
    for (const part of parts) {
      out.set(new Uint8Array(part), at);
      at += part.byteLength;
    }
    return out.buffer;
  }

  async info(): Promise<AccountInfo> {
    return CloudAccount.info(this.meta());
  }

  /** パスワード（の照合値）を設定し直す。持ち主の鍵で呼ぶので、前のパスワードは要らない */
  async setPassword(verifier: string): Promise<AccountInfo> {
    const m = this.meta();
    const salt = [...crypto.getRandomValues(new Uint8Array(16))].map((b) => b.toString(16).padStart(2, "0")).join("");
    m.salt = salt;
    m.passwordHash = await sha256Hex(salt + verifier);
    m.failures = 0;
    m.lockedUntil = 0;
    this.ctx.storage.kv.put("meta", m);
    return CloudAccount.info(m);
  }

  /** プロフィールを預かる（前の物は置き換える） */
  async save(data: ArrayBuffer, savedAt: number): Promise<AccountInfo> {
    const m = this.meta();
    const kv = this.ctx.storage.kv;
    const chunks = Math.ceil(data.byteLength / CHUNK_BYTES);
    for (let i = 0; i < chunks; i++) kv.put(`blob:${i}`, data.slice(i * CHUNK_BYTES, (i + 1) * CHUNK_BYTES));
    for (let i = chunks; i < m.chunks; i++) kv.delete(`blob:${i}`);
    m.chunks = chunks;
    m.size = data.byteLength;
    m.savedAt = savedAt;
    kv.put("meta", m);
    return CloudAccount.info(m);
  }

  /** ID + パスワードで取り出す（別の端末から。鍵は要らない） */
  async login(verifier: string, now: number): Promise<LoginResult> {
    const m = this.meta();
    if (!m.passwordHash || !m.salt) return { ok: false, status: 404, error: "no_password" };
    if (m.lockedUntil > now) return { ok: false, status: 429, error: "locked", retryAfter: Math.ceil((m.lockedUntil - now) / 1000) };
    if ((await sha256Hex(m.salt + verifier)) !== m.passwordHash) {
      m.failures += 1;
      if (m.failures >= MAX_FAILURES) {
        m.failures = 0;
        m.lockedUntil = now + LOCK_MS;
      }
      this.ctx.storage.kv.put("meta", m);
      return { ok: false, status: 403, error: "wrong_password" };
    }
    if (m.failures !== 0 || m.lockedUntil !== 0) {
      m.failures = 0;
      m.lockedUntil = 0;
      this.ctx.storage.kv.put("meta", m);
    }
    const data = this.readBlob(m);
    if (!data) return { ok: false, status: 404, error: "no_data" };
    return { ok: true, data, info: CloudAccount.info(m) };
  }

  /** Game Center で取り出す（Worker が署名を確かめ、索引からこのコードを引いた後。連携が今も同じ人か確かめる） */
  async loginGameCenter(playerId: string): Promise<LoginResult> {
    const m = this.meta();
    if (m.gameCenter !== playerId) return { ok: false, status: 404, error: "not_linked" };
    const data = this.readBlob(m);
    if (!data) return { ok: false, status: 404, error: "no_data" };
    return { ok: true, data, info: CloudAccount.info(m) };
  }

  /** Game Center と連携する。前に連携していた人（索引から外す）を返す */
  async linkGameCenter(playerId: string): Promise<string | null> {
    const m = this.meta();
    const previous = m.gameCenter;
    m.gameCenter = playerId;
    this.ctx.storage.kv.put("meta", m);
    return previous && previous !== playerId ? previous : null;
  }

  async unlinkGameCenter(): Promise<string | null> {
    const m = this.meta();
    const previous = m.gameCenter;
    if (!previous) return null;
    m.gameCenter = null;
    this.ctx.storage.kv.put("meta", m);
    return previous;
  }

  /** アカウントを消す（預かったプロフィール・パスワード・Game Center の連携）。連携していた人を返す */
  async erase(): Promise<string | null> {
    const previous = this.meta().gameCenter;
    await this.ctx.storage.deleteAll();
    return previous;
  }
}

/** Game Center の teamPlayerID → フレンドコード（teamPlayerID 1 つ = DO 1 つ。getByName("gc:<id>")） */
export class GameCenterIndex extends DurableObject<Env> {
  async code(): Promise<string | null> {
    return this.ctx.storage.kv.get<string>("code") ?? null;
  }

  /** このコードに結ぶ。別のコードに結ばれていれば taken */
  async claim(code: string): Promise<"ok" | "taken"> {
    const cur = this.ctx.storage.kv.get<string>("code");
    if (cur && cur !== code) return "taken";
    this.ctx.storage.kv.put("code", code);
    return "ok";
  }

  /** このコードに結ばれていれば外す */
  async release(code: string): Promise<void> {
    if (this.ctx.storage.kv.get<string>("code") === code) await this.ctx.storage.deleteAll();
  }
}

// MARK: Game Center の本人確認（Apple の「Verifying a player's identity」）

/** 署名の元: teamPlayerID・bundle ID・時刻（ビッグエンディアンの u64）・塩 を続けたバイト列を、公開鍵の URL の証明書の鍵で RSA-SHA256 */
export interface GameCenterProof {
  playerId: string;
  bundleId: string;
  publicKeyUrl: string;
  signature: string;
  salt: string;
  timestamp: number;
}

/** アプリの bundle ID（project.yml の PRODUCT_BUNDLE_IDENTIFIER） */
export const GAME_CENTER_BUNDLE_ID = "com.bitcoinpay.velstria";
/** 署名の時刻のずれの許容 */
export const GAME_CENTER_MAX_SKEW_MS = 60 * 60 * 1000;
const PLAYER_ID = /^[A-Za-z0-9:._-]{3,128}$/;
const MAX_SIGNATURE_BYTES = 2048;
const MAX_SALT_BYTES = 256;

/** 公開鍵の URL → 取り込んだ鍵（同じ Worker の中で 1 日使い回す） */
const keyCache = new Map<string, { key: CryptoKey; at: number }>();
const KEY_CACHE_MS = 24 * 60 * 60 * 1000;

export type GameCenterVerdict = { ok: true; playerId: string } | { ok: false; status: number; error: string };

function base64Bytes(s: unknown, max: number): Uint8Array | null {
  if (typeof s !== "string" || s.length === 0 || s.length > Math.ceil(max / 3) * 4 + 4) return null;
  try {
    const bin = atob(s);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out.length > 0 && out.length <= max ? out : null;
  } catch {
    return null;
  }
}

/** 公開鍵の URL として受け付けるか: https の *.apple.com（テストの Worker だけ GAME_CENTER_TEST_KEY_ORIGIN の下も） */
export function allowedKeyUrl(raw: string, testOrigin?: string): boolean {
  if (testOrigin && raw.startsWith(testOrigin)) return true;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return false;
  }
  return url.protocol === "https:" && url.hostname.endsWith(".apple.com") && !url.username && !url.password;
}

/** DER の 1 要素（タグ・中身の範囲） */
function derElement(buf: Uint8Array, at: number): { tag: number; start: number; end: number } | null {
  if (at + 2 > buf.length) return null;
  const tag = buf[at];
  let len = buf[at + 1];
  let start = at + 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n === 0 || n > 4 || start + n > buf.length) return null;
    len = 0;
    for (let i = 0; i < n; i++) len = len * 256 + buf[start + i];
    start += n;
  }
  const end = start + len;
  return end <= buf.length ? { tag, start, end } : null;
}

/** X.509 証明書（DER）から SubjectPublicKeyInfo を切り出す（証明書の署名は見ない。取り寄せ先を apple.com に限ることで信頼する） */
export function spkiFromCertificate(der: Uint8Array): Uint8Array | null {
  const cert = derElement(der, 0);
  if (!cert || cert.tag !== 0x30) return null;
  const tbs = derElement(der, cert.start);
  if (!tbs || tbs.tag !== 0x30) return null;
  let at = tbs.start;
  const first = derElement(der, at);
  if (!first) return null;
  if (first.tag === 0xa0) at = first.end; // version [0]
  // serialNumber・signature・issuer・validity・subject
  for (let i = 0; i < 5; i++) {
    const e = derElement(der, at);
    if (!e || e.end > tbs.end) return null;
    at = e.end;
  }
  const spki = derElement(der, at);
  if (!spki || spki.tag !== 0x30 || spki.end > tbs.end) return null;
  return der.slice(at, spki.end);
}

/** PEM なら中身の DER に直す */
function certificateBytes(raw: ArrayBuffer): Uint8Array {
  const bytes = new Uint8Array(raw);
  const head = new TextDecoder().decode(bytes.subarray(0, 32));
  if (!head.includes("-----BEGIN")) return bytes;
  const body = new TextDecoder().decode(bytes).replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return base64Bytes(body, 64 * 1024) ?? new Uint8Array(0);
}

async function publicKey(url: string, now: number): Promise<CryptoKey | null> {
  const cached = keyCache.get(url);
  if (cached && now - cached.at < KEY_CACHE_MS) return cached.key;
  let res: Response;
  try {
    res = await fetch(url, { cf: { cacheTtl: 86400, cacheEverything: true } } as RequestInit);
  } catch {
    return null;
  }
  if (!res.ok) return null;
  const spki = spkiFromCertificate(certificateBytes(await res.arrayBuffer()));
  if (!spki) return null;
  try {
    const key = await crypto.subtle.importKey("spki", spki, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
    keyCache.set(url, { key, at: now });
    return key;
  } catch {
    return null;
  }
}

/** 署名の元のバイト列 */
export function gameCenterPayload(playerId: string, bundleId: string, timestamp: number, salt: Uint8Array): Uint8Array {
  const enc = new TextEncoder();
  const pid = enc.encode(playerId);
  const bid = enc.encode(bundleId);
  const out = new Uint8Array(pid.length + bid.length + 8 + salt.length);
  out.set(pid, 0);
  out.set(bid, pid.length);
  new DataView(out.buffer).setBigUint64(pid.length + bid.length, BigInt(timestamp), false);
  out.set(salt, pid.length + bid.length + 8);
  return out;
}

/** 端末から届いた本人確認の署名を確かめる */
export async function verifyGameCenter(raw: unknown, env: Env, now = Date.now()): Promise<GameCenterVerdict> {
  if (!raw || typeof raw !== "object") return { ok: false, status: 400, error: "bad_gamecenter" };
  const p = raw as Partial<GameCenterProof>;
  if (typeof p.playerId !== "string" || !PLAYER_ID.test(p.playerId)) return { ok: false, status: 400, error: "bad_gamecenter" };
  if (p.bundleId !== GAME_CENTER_BUNDLE_ID) return { ok: false, status: 400, error: "bad_gamecenter" };
  if (typeof p.publicKeyUrl !== "string" || !allowedKeyUrl(p.publicKeyUrl, env.GAME_CENTER_TEST_KEY_ORIGIN)) {
    return { ok: false, status: 400, error: "bad_gamecenter" };
  }
  if (typeof p.timestamp !== "number" || !Number.isSafeInteger(p.timestamp) || p.timestamp <= 0) {
    return { ok: false, status: 400, error: "bad_gamecenter" };
  }
  if (Math.abs(now - p.timestamp) > GAME_CENTER_MAX_SKEW_MS) return { ok: false, status: 403, error: "gamecenter_expired" };
  const signature = base64Bytes(p.signature, MAX_SIGNATURE_BYTES);
  const salt = base64Bytes(p.salt, MAX_SALT_BYTES);
  if (!signature || !salt) return { ok: false, status: 400, error: "bad_gamecenter" };
  const key = await publicKey(p.publicKeyUrl, now);
  if (!key) return { ok: false, status: 502, error: "gamecenter_key_unavailable" };
  const valid = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, gameCenterPayload(p.playerId, p.bundleId, p.timestamp, salt));
  return valid ? { ok: true, playerId: p.playerId } : { ok: false, status: 403, error: "gamecenter_invalid" };
}
