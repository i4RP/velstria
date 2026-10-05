#!/usr/bin/env node
// Meshy API の小さなクライアント（依存なし。Node 20+ の標準 fetch）。tools/tripo.mjs の代替経路で、
// - heroes: Tripo が作ったヒーローのコンセプト画像（build/tripo/heroes/<id>/concept.png）から Meshy で 3D モデル → 自動リグを作り、
//   リグ付きファイルを build/tripo/heroes/<id>/rigged.{glb,fbx} へ置く。
// - props: assets.json の props[].prompt（style.propPrefix / propSuffix / propNegative）から Text to Image でコンセプト画像 →
//   Image to 3D（Smart Topology meshy-t2）で静的メッシュを作り、build/tripo/props/<kind>/model.glb へ置く。Meshy の GLB は
//   正面（画像で見る側）が glTF +Z（Tripo は +X）なので、同じフォルダの source.json に provider / front を書き、
//   tools/tripo.mjs import props が model.glb の sha256 が一致するときだけその front で正規化する。
// 取り込み（Blender 正規化 + 検査）は node tools/tripo.mjs import <heroes|props> <id> がそのまま行う。
// 進捗は tools/meshy/state.json（自動生成。task_id・状態・消費クレジット・ハッシュ・ローカルパスのみで秘密は含まない）、
// ダウンロード物は build/meshy/<heroes|props>/<id>/（git 管理外）。
//
// 環境変数:
//   MESHY_API_KEY      API キー（省略時 ~/.config/meshy/api_key）。リポジトリ・ログ・state.json には決して書かない
//   MESHY_API_BASE     既定 https://api.meshy.ai（モックのサーバへ向けて試せる）
//   MESHY_CONCURRENCY  同時に進めるアセット数（既定 3。--concurrency でも指定可）
//   MESHY_RESERVE      残高の下限（既定 0。--reserve でも指定可。有料 POST の後にこれを下回る見込みなら送らない）
//   MESHY_STATE_DIR    state.json（とロック）の置き場所（既定 tools/meshy/）
//   MESHY_BUILD_DIR    ダウンロード物（既定 build/meshy/）
//   TRIPO_BUILD_DIR    ヒーローのコンセプト画像の読み元・リグ付きファイル / Prop の model.glb の置き先（既定 build/tripo/。tools/tripo.mjs と同じ）
//
// usage（VELSTRIA/ で実行）:
//   node tools/meshy.mjs balance                                   残高（無料 API）
//   node tools/meshy.mjs estimate [heroes|props] [ids...|--all]    見積り（残高と比較）
//   node tools/meshy.mjs run heroes [H001 ...|--all] [--until model|rig] [--faces N] [--source glb|fbx] [--replace-tripo]
//   node tools/meshy.mjs run props [<kind> ...|--all] [--until concept|model] [--faces N] [--replace-tripo]
//       共通: [--dry-run] [--max-credits N] [--reserve N] [--force <stage>[,<stage>]|all] [--concurrency N] [--allow-partial]
//   node tools/meshy.mjs status                                    アセット × 段階の状態・消費・置いたファイル
//   node tools/meshy.mjs task <concept|model|rig> <task_id>        タスクの JSON（署名付き URL は伏せる）
//
// 安全策（tripo.mjs と同じ）: 有料 POST は再送しない（受け付け前の 429 だけ、待ってから残高・下限を確かめ直して再送）。送信結果が不明な段階
// （submitting / unknown、408 など拒否と確定できない 4xx も含む）は --force なしでは再送しない。state.json は排他ロック
// （落ちたプロセスの残骸は rename で退けてから消す）+ 一時ファイルからの rename。有料 POST の直前ごとに残高・--reserve と
// --max-credits（結果不明の送信も課金済みとして数える）を確かめる。署名付き URL は保存も表示もしない（期限切れは GET し直す）。
// --force: 既存の結果を履歴へ移すのは送信の直前。実行中（PENDING / IN_PROGRESS）の段階は作り直さない。--all と一緒なら
// --max-credits 必須。置き先に Meshy 以外の rigged.* / model.glb があるアセットは --replace-tripo なしでは送信前に外す。
// props の --all は任意（optional）と体に付ける装着物（bodyWorn）を除く（ID を名指ししたときだけ対象）。
// --dry-run は送信予定のリクエスト本文（画像の data URI は長さとハッシュに置き換え）と出力先を表示するだけ。
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MANIFEST_PATH = path.join(ROOT, "tools", "tripo", "assets.json");
const envDir = (k, def) => (process.env[k] ? path.resolve(process.env[k]) : def);
const STATE_PATH = path.join(envDir("MESHY_STATE_DIR", path.join(ROOT, "tools", "meshy")), "state.json");
const BUILD_DIR = envDir("MESHY_BUILD_DIR", path.join(ROOT, "build", "meshy"));
const TRIPO_BUILD_DIR = envDir("TRIPO_BUILD_DIR", path.join(ROOT, "build", "tripo"));
const API = (process.env.MESHY_API_BASE || "https://api.meshy.ai").replace(/\/+$/, "");
const KEY_FILE = path.join(os.homedir(), ".config", "meshy", "api_key");
const PURCHASE_URL = "https://www.meshy.ai/settings/subscription";

// 見積り用クレジット（docs.meshy.ai/api/pricing、2026-10 時点）。実際の消費は各タスクの consumed_credits を記録する。
// 失敗したタスクは返金される（consumed_credits 0）
const CATS = {
  heroes: {
    stages: ["model", "rig"],
    credits: {
      model: 30, // Image to 3D meshy-7.1（latest）+ 2K テクスチャ（PBR・リメッシュは追加なし）
      rig: 5, // Auto-Rigging
    },
    faces: [100, 300000], // should_remesh の target_polycount
    defaultFaces: 10000,
  },
  props: {
    stages: ["concept", "model"],
    credits: {
      concept: 6, // Text to Image nano-banana-2
      model: 15, // Image to 3D Smart Topology meshy-t2 + 2K テクスチャ
    },
    faces: [100, 15000], // Smart Topology の target_polycount
    defaultFaces: 2500, // tools/tripo.mjs の props と同じ
  },
};
const ALL_STAGES = ["concept", "model", "rig"];
const stagesOf = (a) => CATS[a.cat].stages;
const credit = (a, stage) => CATS[a.cat].credits[stage];
const ENDPOINTS = { concept: "/openapi/v1/text-to-image", model: "/openapi/v1/image-to-3d", rig: "/openapi/v1/rigging" };
const KIND_ALIASES = { concept: "concept", "text-to-image": "concept", model: "model", "image-to-3d": "model", rig: "rig", rigging: "rig" };
const RIG_HEIGHT_M = 1.7;
// Prop のコンセプト画像: nano-banana（3）は縦長の単体・無地の背景の指示に従いにくいので 1 段上の nano-banana-2（6）。
// 3:4 は縦置きの武器・盾に合う縦長で、nano-banana 系が受け付ける比
const PROP_IMAGE_MODEL = "nano-banana-2";
const PROP_ASPECT = "3:4";
// Meshy の Image to 3D の GLB は画像の正面が glTF +Z（normalize_prop.py --front）
const PROP_FRONT = "+z";
// tools/tripo.mjs import heroes へ渡す既定の形式。H002 で両方を取り込んで比べた結果 GLB: 骨・ウェイト・レスト・向きは同じで、
// FBX は base color しか持たない（GLB は metallicRoughness・normal も持ち、取り込み後も 3 枚残る）
const DEFAULT_SOURCE = "glb";
// 段階ごとに保存するファイル（[出力の取り出し方, ファイル名, 種類, 必須]）
const STAGE_FILES = {
  concept: [
    [(t) => t?.image_urls?.[0], "concept.png", "image", true],
  ],
  model: [
    [(t) => t?.model_urls?.glb, "model.glb", "model", true],
    [(t) => t?.thumbnail_url, "preview.png", "image", false],
  ],
  rig: [
    [(t) => t?.result?.rigged_character_glb_url, "rigged.glb", "model", true],
    [(t) => t?.result?.rigged_character_fbx_url, "rigged.fbx", "fbx", true],
  ],
};
const ACTIVE = new Set(["PENDING", "IN_PROGRESS"]);
const UNSURE = new Set(["submitting", "unknown"]);
const TERMINAL_FAIL = new Set(["FAILED", "CANCELED", "failed"]); // 小文字の failed は送信時に拒否が確定したもの
const resumable = (st) => !!(st?.task_id && (ACTIVE.has(st.status) || st.status === "unknown"));
const NOT_FOUND_GRACE_MS = 60_000;
const NOT_FOUND_MIN_TRIES = 3;
const POLL_DEFAULT_MS = 5000;
const POLL_TIMEOUT_MS = 60 * 60 * 1000;
const MAX_ATTEMPTS = 6; // 通信エラー・5xx（無料の GET のみ）
const MAX_ATTEMPTS_429 = 12;
const QUEUE_WAIT_SEC = 30; // 429 NoMorePendingTasks（同時実行の上限。Retry-After なし）の待ち
// 有料 POST が「タスクを作らずに拒否された」と確定できる 4xx（JSON の理由付き）。408・409・499 などは途中で作られている
// 可能性があるので unknown 扱い（再送しない）
const DEFINITE_REJECT = new Set([400, 401, 402, 403, 404, 413, 415, 422, 429]);
// 入力画像の上限（docs.meshy.ai の画像入力の記載: 各辺 32px 以上・復号後 20,000,000 bytes 以下。data URI は約 4/3 倍の本文になる）
const IMAGE_MAX_BYTES = 20_000_000;
const IMAGE_MIN_SIDE = 32;

let DRY = false;
let apiKeyCache = null;

function fail(msg) {
  console.error(`error: ${scrub(msg)}`);
  process.exit(1);
}

function log(msg) {
  console.log(scrub(msg));
}

// 念のため、出力に API キーと署名付き URL が紛れ込まないようにする
function scrub(s) {
  let t = String(s);
  if (apiKeyCache) t = t.split(apiKeyCache).join("***");
  return t.replace(/https?:\/\/[^\s"'<>]*[?&](Expires|Signature|X-Amz-[A-Za-z]+|Key-Pair-Id)=[^\s"'<>]*/g, "<署名付き URL>");
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const now = () => new Date().toISOString();
const rel = (p) => {
  const r = path.relative(ROOT, p);
  return r.startsWith("..") || path.isAbsolute(r) ? p : r;
};
const num = (v) => (v === null || v === undefined || v === "" || Number.isNaN(Number(v)) ? null : Number(v));
const fmtCredits = (c) => (c === null || c === undefined ? "-" : Number.isInteger(c) ? String(c) : c.toFixed(2));
const fmtBytes = (n) => (n >= 1 << 20 ? `${(n / (1 << 20)).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`);
const sha256 = (buf) => crypto.createHash("sha256").update(buf).digest("hex");
const sha256File = (file) => sha256(fs.readFileSync(file));
const msIso = (ms) => (num(ms) > 0 ? new Date(Number(ms)).toISOString() : null);

function elapsed(t0) {
  const s = Math.round((Date.now() - t0) / 1000);
  return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m${String(s % 60).padStart(2, "0")}s`;
}

function dispWidth(s) {
  let w = 0;
  for (const ch of String(s)) {
    const c = ch.codePointAt(0);
    const wide = c >= 0x1100 && (c <= 0x115f || (c >= 0x2e80 && c <= 0xa4cf) || (c >= 0xac00 && c <= 0xd7a3)
      || (c >= 0xf900 && c <= 0xfaff) || (c >= 0xfe30 && c <= 0xfe4f) || (c >= 0xff00 && c <= 0xff60) || (c >= 0xffe0 && c <= 0xffe6));
    w += wide ? 2 : 1;
  }
  return w;
}
const pad = (s, n) => String(s) + " ".repeat(Math.max(0, n - dispWidth(s)));

function table(rows, indent = "  ") {
  const widths = [];
  for (const r of rows) r.forEach((c, i) => { widths[i] = Math.max(widths[i] || 0, dispWidth(c)); });
  for (const r of rows) log(indent + r.map((c, i) => (i === r.length - 1 ? String(c) : pad(c, widths[i]))).join("  ").trimEnd());
}

class Semaphore {
  constructor(n) { this.n = n; this.q = []; }
  async acquire() {
    if (this.n > 0) { this.n--; return; }
    await new Promise((r) => this.q.push(r));
  }
  release() {
    const next = this.q.shift();
    if (next) next(); else this.n++;
  }
}

// MARK: - 引数

const VALUE_FLAGS = new Set(["until", "faces", "max-credits", "reserve", "force", "concurrency", "source"]);
const BOOL_FLAGS = new Set(["all", "dry-run", "allow-partial", "replace-tripo", "help"]);

function parseArgs(argv) {
  const pos = [];
  const flags = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) { pos.push(a); continue; }
    const eq = a.indexOf("=");
    const k = eq < 0 ? a.slice(2) : a.slice(2, eq);
    let v = eq < 0 ? undefined : a.slice(eq + 1);
    if (VALUE_FLAGS.has(k)) {
      if (v === undefined) v = argv[++i];
      if (v === undefined || v.startsWith("--")) fail(`--${k} に値が必要です`);
      if (k === "force") flags.force = [...(flags.force || []), ...v.split(",").map((s) => s.trim()).filter(Boolean)];
      else flags[k] = v;
    } else if (BOOL_FLAGS.has(k)) {
      if (v !== undefined) fail(`--${k} は値を取りません`);
      flags[k] = true;
    } else {
      fail(`不明なオプション: --${k}（node tools/meshy.mjs で使い方を表示）`);
    }
  }
  const intFlag = (k, min, max) => {
    if (flags[k] === undefined) return undefined;
    const n = Number(flags[k]);
    if (!Number.isInteger(n) || n < min || n > max) fail(`--${k} は ${min}〜${max} の整数: ${flags[k]}`);
    return n;
  };
  if (flags.source !== undefined && !["glb", "fbx"].includes(flags.source)) fail(`--source は glb | fbx: ${flags.source}`);
  // 段階名はカテゴリごとに cmdRun で確かめ直す（heroes: model | rig、props: concept | model）
  if (flags.until !== undefined && !ALL_STAGES.includes(flags.until)) fail(`--until は ${ALL_STAGES.join(" | ")}: ${flags.until}`);
  for (const f of flags.force || []) if (f !== "all" && !ALL_STAGES.includes(f)) fail(`--force は ${ALL_STAGES.join(" | ")} | all: ${f}`);
  const envConc = process.env.MESHY_CONCURRENCY ? Number(process.env.MESHY_CONCURRENCY) : 3;
  return {
    pos,
    all: !!flags.all,
    dry: !!flags["dry-run"],
    allowPartial: !!flags["allow-partial"],
    replaceTripo: !!flags["replace-tripo"],
    help: !!flags.help,
    until: flags.until,
    faces: intFlag("faces", 1, 1_000_000), // 範囲はカテゴリごとに cmdRun で確かめる
    source: flags.source ?? DEFAULT_SOURCE,
    maxCredits: flags["max-credits"] === undefined ? undefined : (() => {
      const n = Number(flags["max-credits"]);
      if (!(n >= 0)) fail(`--max-credits は 0 以上の数: ${flags["max-credits"]}`);
      return n;
    })(),
    reserve: (() => {
      const v = flags.reserve ?? process.env.MESHY_RESERVE;
      if (v === undefined || v === "") return 0;
      const n = Number(v);
      if (!(n >= 0)) fail(`--reserve（MESHY_RESERVE）は 0 以上の数: ${v}`);
      return n;
    })(),
    force: new Set(flags.force || []),
    concurrency: intFlag("concurrency", 1, 10) ?? (Number.isInteger(envConc) && envConc >= 1 ? Math.min(envConc, 10) : 3),
  };
}

// MARK: - API

class MeshyError extends Error {
  constructor(method, p, status, json, text) {
    const msg = json?.message || (text ? text.slice(0, 200) : "");
    super(`${method} ${p} → HTTP ${status}: ${msg}`);
    this.status = status;
    this.json = json;
  }
  // 402、または残高切れのときの 429 NoMoreConcurrentTasks
  get insufficientCredits() {
    return this.status === 402 || (this.status === 429 && /NoMoreConcurrentTasks/i.test(this.json?.message || ""));
  }
}

function apiKey() {
  if (apiKeyCache) return apiKeyCache;
  let k = (process.env.MESHY_API_KEY || "").trim();
  if (!k && fs.existsSync(KEY_FILE)) k = fs.readFileSync(KEY_FILE, "utf8").trim();
  if (!k) fail(`API キーがありません: MESHY_API_KEY を設定するか ${KEY_FILE} に保存してください（リポジトリには置かない）`);
  apiKeyCache = k;
  return k;
}

const hasApiKey = () => !!(process.env.MESHY_API_KEY || "").trim() || fs.existsSync(KEY_FILE);
const backoffSec = (attempt) => Math.min(32, 2 ** (attempt - 1));

// Retry-After（秒）。無ければ X-RateLimit-Reset（「満たされるまでの秒数」）
function retryAfterSec(res) {
  const ra = Number(res.headers.get("retry-after"));
  if (ra > 0) return Math.min(ra, 120);
  const reset = Number(res.headers.get("x-ratelimit-reset"));
  if (reset > 0) return Math.min(Math.ceil(reset), 120);
  return null;
}

// 通信エラー・HTTP 429・5xx は指数バックオフで再試行する（4xx の業務エラーは再試行しない）。
// paid（タスクを作る有料 POST）はここでは一切再試行しない: タイムアウト・通信エラー・5xx はサーバ側でタスク作成と課金が
// 済んでいることがあり、再送すると二重課金になる。429（受け付け前の拒否）の待ち・再送は Runner.submit が、送り直す前に
// 残高・--reserve・--max-credits を確かめ直してから行う（待つ間に共有アカウントの別の作業が残高を使うことがある）。
// 429 NoMoreConcurrentTasks は残高切れなので再試行しない。返り値は { json, res }
async function api(method, p, body, { paid = false } = {}) {
  for (let attempt = 1; ; attempt++) {
    let res;
    let text;
    try {
      const headers = { Authorization: `Bearer ${apiKey()}` };
      let payload;
      if (body !== undefined) { headers["Content-Type"] = "application/json"; payload = JSON.stringify(body); }
      res = await fetch(API + p, { method, headers, body: payload, signal: AbortSignal.timeout(120_000) });
      text = await res.text();
    } catch (e) {
      const why = e.cause?.code || e.name || e.message;
      if (paid || attempt >= MAX_ATTEMPTS) {
        const err = new Error(`${method} ${p}: 通信エラー（${why}）${paid ? "（課金 POST は再試行しません）" : "が続いたため中止"}`);
        err.network = true;
        throw err;
      }
      const wait = backoffSec(attempt);
      console.error(`  通信エラーのため ${wait}s 後に再試行（${attempt}/${MAX_ATTEMPTS - 1}）: ${method} ${p} ${why}`);
      await sleep(wait * 1000);
      continue;
    }
    let json = null;
    try { json = text ? JSON.parse(text) : {}; } catch { json = null; }
    const outOfCredits = res.status === 429 && /NoMoreConcurrentTasks/i.test(json?.message || "");
    const queue = res.status === 429 && /NoMorePendingTasks/i.test(json?.message || "");
    const limit = paid ? 1 : res.status === 429 ? MAX_ATTEMPTS_429 : MAX_ATTEMPTS;
    if (((res.status === 429 && !outOfCredits) || res.status >= 500) && attempt < limit) {
      const wait = res.status === 429 ? (queue ? QUEUE_WAIT_SEC : retryAfterSec(res) ?? backoffSec(attempt)) : backoffSec(attempt);
      const what = res.status === 429 ? (queue ? "同時実行数の上限" : "レート制限") : `HTTP ${res.status} `;
      console.error(`  ${what}のため ${wait}s 後に再試行（${attempt}/${limit - 1}）: ${method} ${p}`);
      await sleep(wait * 1000);
      continue;
    }
    if (!res.ok || !json) {
      const err = new MeshyError(method, p, res.status, json, text);
      if (res.status === 429) err.retryAfter = queue ? QUEUE_WAIT_SEC : retryAfterSec(res);
      throw err;
    }
    return { json, res };
  }
}

async function getBalance() {
  const { json } = await api("GET", "/openapi/v1/balance");
  const b = num(json?.balance);
  if (b === null) throw new Error("残高の応答に balance がありません");
  return b;
}

const getTask = async (stage, tid) => api("GET", `${ENDPOINTS[stage]}/${encodeURIComponent(tid)}`);

function shortageText(need, bal) {
  return [
    `クレジット不足: 残高 ${fmtCredits(bal)}、必要 約 ${fmtCredits(need)} credits、不足 ${fmtCredits(Math.max(0, need - bal))} credits`,
    `  購入: ${PURCHASE_URL}（API キーは https://www.meshy.ai/developers/keys）`,
  ].join("\n");
}

// MARK: - ファイル

function sniffMime(buf) {
  if (buf.length >= 4 && buf.toString("latin1", 0, 4) === "glTF") return "model/gltf-binary";
  if (buf.length >= 8 && buf[0] === 0x89 && buf.toString("latin1", 1, 4) === "PNG") return "image/png";
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return "image/jpeg";
  if (buf.length >= 12 && buf.toString("latin1", 0, 4) === "RIFF" && buf.toString("latin1", 8, 12) === "WEBP") return "image/webp";
  if (buf.length >= 18 && buf.toString("latin1", 0, 18) === "Kaydara FBX Binary") return "model/fbx";
  return "application/octet-stream";
}

function readHead(file, n = 32) {
  const fd = fs.openSync(file, "r");
  try {
    const buf = Buffer.alloc(n);
    const read = fs.readSync(fd, buf, 0, n, 0);
    return buf.subarray(0, read);
  } finally { fs.closeSync(fd); }
}

// 中身の検査（GLB は 'glTF'、FBX はバイナリ FBX、画像は PNG/JPEG/WebP）。問題なければ null、あれば理由
function badContent(file, kind) {
  if (!fs.existsSync(file)) return "ファイルがありません";
  if (fs.statSync(file).size === 0) return "空のファイル";
  const mime = sniffMime(readHead(file));
  if (kind === "model") return mime === "model/gltf-binary" ? null : "GLB ではありません（先頭が glTF でない）";
  if (kind === "fbx") return mime === "model/fbx" ? null : "バイナリ FBX ではありません";
  return mime.startsWith("image/") ? null : "画像ではありません";
}

class HttpStatusError extends Error {
  constructor(status) { super(`HTTP ${status}`); this.status = status; }
}

// 一時ファイルへストリーム保存 → 検査 → rename。URL（署名付き）はログに出さない
async function download(url, dest, kind) {
  const tmp = `${dest}.part`;
  for (let attempt = 1; ; attempt++) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(15 * 60_000) });
      if (!res.ok || !res.body) throw new HttpStatusError(res.status);
      await pipeline(Readable.fromWeb(res.body), fs.createWriteStream(tmp));
      const bad = badContent(tmp, kind);
      if (bad) throw Object.assign(new Error(bad), { permanent: true });
      fs.renameSync(tmp, dest);
      return fs.statSync(dest).size;
    } catch (e) {
      fs.rmSync(tmp, { force: true });
      const retryable = !e.permanent && (!(e instanceof HttpStatusError) || e.status === 429 || e.status >= 500);
      if (!retryable || attempt >= 5) {
        throw Object.assign(new Error(`ダウンロード失敗 ${rel(dest)}: ${e.cause?.code || e.message}`), { status: e.status });
      }
      await sleep(backoffSec(attempt) * 1000);
    }
  }
}

// 画像の縦横（PNG の IHDR / JPEG の SOF）。分からなければ null
function imageSize(buf) {
  if (buf.length >= 24 && buf[0] === 0x89 && buf.toString("latin1", 1, 4) === "PNG") return [buf.readUInt32BE(16), buf.readUInt32BE(20)];
  if (buf.length >= 4 && buf[0] === 0xff && buf[1] === 0xd8) {
    let i = 2;
    while (i + 9 < buf.length) {
      if (buf[i] !== 0xff) { i++; continue; }
      const m = buf[i + 1];
      if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) return [buf.readUInt16BE(i + 7), buf.readUInt16BE(i + 5)];
      if (m === 0xd8 || m === 0x01 || (m >= 0xd0 && m <= 0xd7)) { i += 2; continue; }
      i += 2 + buf.readUInt16BE(i + 2);
    }
  }
  return null;
}

// GLB の概要（三角形数・骨名・テクスチャの大きさ）。JSON チャンクと画像の bufferView だけ読む
function glbInfo(file) {
  const buf = fs.readFileSync(file);
  if (buf.length < 20 || buf.toString("latin1", 0, 4) !== "glTF") return null;
  const jsonLen = buf.readUInt32LE(12);
  const g = JSON.parse(buf.toString("utf8", 20, 20 + jsonLen));
  const binStart = 20 + jsonLen + 8;
  let tris = 0;
  for (const m of g.meshes || []) {
    for (const p of m.primitives || []) {
      if ((p.mode ?? 4) !== 4) continue;
      const acc = g.accessors?.[p.indices ?? p.attributes?.POSITION];
      if (acc) tris += Math.floor(acc.count / 3);
    }
  }
  const joints = (g.skins || []).map((s) => (s.joints || []).map((j) => g.nodes?.[j]?.name ?? `#${j}`));
  const textures = (g.images || []).map((img) => {
    const bv = g.bufferViews?.[img.bufferView];
    if (!bv) return { mime: img.mimeType, size: null };
    const off = binStart + (bv.byteOffset || 0);
    return { mime: img.mimeType, size: imageSize(buf.subarray(off, off + Math.min(bv.byteLength, 1 << 16))), bytes: bv.byteLength };
  });
  return { tris, skins: joints.length, joints: joints[0] || [], textures, materials: (g.materials || []).length, animations: (g.animations || []).length };
}

// MARK: - マニフェスト・状態

function loadManifest() {
  let m;
  try { m = JSON.parse(fs.readFileSync(MANIFEST_PATH, "utf8")); } catch (e) { fail(`マニフェストを読めません: ${rel(MANIFEST_PATH)}: ${e.message}`); }
  if (!Array.isArray(m.heroes)) fail("マニフェストに heroes がありません");
  if (!Array.isArray(m.props)) fail("マニフェストに props がありません");
  // 同じ ID（大文字小文字違いも。select が大文字小文字を無視して引く）が 2 件あると、同じ state キーへ 2 本送ってしまう
  for (const [cat, list, k] of [["heroes", m.heroes, "id"], ["props", m.props, "kind"]]) {
    const seen = new Set();
    for (const e of list) {
      const id = String(e?.[k] ?? "");
      if (!id || seen.has(id.toLowerCase())) fail(`マニフェストの ${cat} の ${k} が空か重複しています: ${id || "(空)"}`);
      seen.add(id.toLowerCase());
    }
  }
  return {
    style: m.style || {},
    heroes: m.heroes.map((e) => ({ cat: "heroes", id: e.id, key: `heroes/${e.id}`, label: e.name_ja || e.id, entry: e })),
    props: m.props.map((e) => ({ cat: "props", id: e.kind, key: `props/${e.kind}`, label: (e.heroes || []).join(","), entry: e })),
  };
}

const MANIFEST = loadManifest();
// ヒーローは tools/tripo.mjs のコンセプト画像、Prop はこのツールの concept 段が作った画像
const conceptPath = (a) => (a.cat === "heroes" ? path.join(TRIPO_BUILD_DIR, "heroes", a.id, "concept.png") : path.join(assetDir(a), "concept.png"));
const assetDir = (a) => path.join(BUILD_DIR, a.cat, a.id);
const tripoDir = (a) => path.join(TRIPO_BUILD_DIR, a.cat, a.id);
// --all の対象外（Prop の任意・体に付ける装着物）。名指ししたときだけ対象
const skipByDefault = (a) => a.cat === "props" && (!!a.entry.optional || !!a.entry.bodyWorn);

// ids 指定 → その資産（重複・大文字小文字違いは 1 件にまとめる＝同じ段階を 2 本送らない）、--all → 全件（Prop は任意・装着物を除く）
function select(cat, ids, o, defaultAll = false) {
  const list = MANIFEST[cat];
  const names = () => list.map((h) => h.id).join(" ");
  if (ids.length) {
    const found = ids.map((id) => list.find((h) => h.id === id) || list.find((h) => h.id.toLowerCase() === id.toLowerCase())
      || fail(`${cat} に ${id} はありません（候補: ${names()}）`));
    return [...new Set(found)];
  }
  if (!o.all && !defaultAll) fail(`対象を指定してください（ID を並べるか --all）。候補: ${names()}`);
  return list.filter((a) => !skipByDefault(a));
}

// Prop のコンセプト画像のプロンプト。Text to Image に否定のプロンプトの項目は無いので、末尾の文に畳み込む
function propPrompt(a) {
  const s = MANIFEST.style;
  const neg = [s.propNegative, a.entry.negative].filter(Boolean).join(", ");
  return [s.propPrefix, a.entry.prompt, s.propSuffix, neg ? `Avoid: ${neg}.` : ""].filter(Boolean).join(" ");
}

function loadState() {
  if (!fs.existsSync(STATE_PATH)) return { version: 1, assets: {} };
  try {
    const s = JSON.parse(fs.readFileSync(STATE_PATH, "utf8"));
    s.assets ||= {};
    return s;
  } catch (e) {
    return fail(`state.json を読めません: ${e.message}（壊れている場合は退避してから再実行）`);
  }
}

let state = loadState();

// run は state.json 全体を書き戻すので、並行するもう 1 本が相手の task_id を消してしまう → 排他ロック
const LOCK_PATH = `${STATE_PATH}.lock`;
function lockState() {
  fs.mkdirSync(path.dirname(LOCK_PATH), { recursive: true });
  for (let i = 0; i < 3; i++) {
    let fd;
    try {
      fd = fs.openSync(LOCK_PATH, "wx");
    } catch (e) {
      if (e.code !== "EEXIST") throw e;
      let raw = null;
      try { raw = fs.readFileSync(LOCK_PATH, "utf8"); } catch { continue; } // 消えた → 取り直す
      const pid = Number.parseInt(raw, 10);
      let alive = false;
      if (Number.isInteger(pid) && pid > 0) {
        try { process.kill(pid, 0); alive = true; } catch (k) { alive = k.code === "EPERM"; }
      } else {
        try { alive = Date.now() - fs.statSync(LOCK_PATH).mtimeMs < 10_000; } catch { continue; }
      }
      if (alive) fail(`別の tools/meshy.mjs（PID ${Number.isInteger(pid) ? pid : "?"}）が state.json を更新中です。終わってから実行してください`);
      // 落ちたプロセスの残骸を退ける。読んでから消すまでの間に別プロセスが残骸を消して取り直していると、そのロックを
      // 消して 2 本とも走ってしまう → rename で脇へ退けてから中身が読んだものと同じか確かめ、違えば戻して中止する
      const aside = `${STATE_PATH}.${process.pid}.lockstale.tmp`; // .gitignore の state.json.*.tmp に入る名前
      try { fs.renameSync(LOCK_PATH, aside); } catch { continue; }
      let moved = null;
      try { moved = fs.readFileSync(aside, "utf8"); } catch { /* 読めない → 別物とみなす */ }
      if (moved !== raw) {
        try { fs.linkSync(aside, LOCK_PATH); } catch { /* 既に別のロックがある */ }
        fs.rmSync(aside, { force: true });
        fail("別の tools/meshy.mjs が同時に起動しました。終わってから実行してください");
      }
      fs.rmSync(aside, { force: true });
      continue;
    }
    fs.writeSync(fd, String(process.pid));
    fs.closeSync(fd);
    process.on("exit", () => {
      try { if (fs.readFileSync(LOCK_PATH, "utf8") === String(process.pid)) fs.unlinkSync(LOCK_PATH); } catch { /* 無視 */ }
    });
    state = loadState();
    return;
  }
  fail(`${rel(LOCK_PATH)} を取得できません`);
}

function saveState() {
  if (DRY) throw new Error("内部エラー: dry-run 中に state.json を書こうとしました");
  state.note = "tools/meshy.mjs が自動生成。task_id・状態・消費クレジット・ハッシュ・ローカルパスのみ（秘密情報なし）";
  state.updated_at = now();
  fs.mkdirSync(path.dirname(STATE_PATH), { recursive: true });
  const tmp = `${STATE_PATH}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(state, null, 2) + "\n");
  fs.renameSync(tmp, STATE_PATH);
}

const getStage = (a, stage) => state.assets[a.key]?.stages?.[stage];

function setStage(a, stage, patch) {
  const as = (state.assets[a.key] ||= { stages: {} });
  as.stages ||= {};
  as.stages[stage] = { ...(as.stages[stage] || {}), ...patch, updated_at: now() };
  saveState();
  return as.stages[stage];
}

function setAsset(a, patch) {
  const as = (state.assets[a.key] ||= { stages: {} });
  Object.assign(as, patch);
  saveState();
}

const tag = (a, stage) => `${a.key} ${stage}`;

// --force: 指定段階以降を履歴へ移す（rig は model の task_id に、Prop の model は concept の画像に依存するため）。送信の直前（予算と残高を確かめた後）に呼ぶ。
// 実行中（PENDING / IN_PROGRESS）のタスクは課金済みで完了まで進むので、履歴へ移して作り直すと二重の課金になる → 拒む
// （中断後に同じ --force 付きのコマンドを打ち直したときに起きやすい）
const stagesFrom = (a, stage) => stagesOf(a).slice(stagesOf(a).indexOf(stage));
const busyFrom = (a, stage) => stagesFrom(a, stage).filter((s) => ACTIVE.has(getStage(a, s)?.status));
function archiveFrom(a, stage) {
  const as = state.assets[a.key];
  if (!as?.stages) return;
  const busy = busyFrom(a, stage);
  if (busy.length) throw new Error(`内部エラー: 実行中の ${busy.join(", ")} を履歴へ移そうとしました`);
  let changed = false;
  for (const s of stagesFrom(a, stage)) {
    const st = as.stages[s];
    if (!st) continue;
    (as.history ||= []).push({ stage: s, archived_at: now(), ...st });
    delete as.stages[s];
    changed = true;
  }
  if (changed) saveState();
}

// 出力の控え（URL は期限付きの署名付きなので保存せず、URL のあるキーの一覧とスカラー値だけ残す）
function urlKeys(obj, prefix = "") {
  const out = [];
  if (!obj || typeof obj !== "object") return out;
  for (const [k, v] of Object.entries(obj)) {
    const key = Array.isArray(obj) ? `${prefix}[${k}]` : prefix ? `${prefix}.${k}` : k;
    if (typeof v === "string" && /^https?:\/\//.test(v)) out.push(key);
    else if (v && typeof v === "object") out.push(...urlKeys(v, key));
  }
  return out;
}

// task コマンドの表示用: 署名付き URL を伏せる
function redactUrls(v) {
  if (typeof v === "string") return /^https?:\/\//.test(v) ? "<署名付き URL>" : v;
  if (Array.isArray(v)) return v.map(redactUrls);
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, redactUrls(x)]));
  return v;
}

// MARK: - リクエスト本文

// コンセプト画像を送れない理由（無い・PNG/JPEG でない・大きすぎ/小さすぎ）。送れるなら null
function imageProblem(buf) {
  const mime = sniffMime(buf);
  if (mime !== "image/png" && mime !== "image/jpeg") return `${mime}（Meshy は PNG / JPEG のみ）`;
  if (buf.length > IMAGE_MAX_BYTES) return `${fmtBytes(buf.length)}（上限 ${IMAGE_MAX_BYTES} bytes）`;
  const dim = imageSize(buf);
  if (dim && Math.min(...dim) < IMAGE_MIN_SIDE) return `${dim.join("x")}（各辺 ${IMAGE_MIN_SIDE}px 以上）`;
  return null;
}

function conceptProblem(a) {
  const file = conceptPath(a);
  if (badContent(file, "image")) return "ありません";
  return imageProblem(fs.readFileSync(file));
}

// コンセプト画像の data URI（拡張子でなく中身から MIME を決める: Tripo は .png に JPEG を書く）。
// 読んだ時点の中身で検査し直す（tools/tripo.mjs が並行して作り直していることがある）
function conceptInput(a) {
  const file = conceptPath(a);
  if (badContent(file, "image")) return null;
  const buf = fs.readFileSync(file);
  const bad = imageProblem(buf);
  if (bad) throw new Error(`${rel(file)} は送れません: ${bad}`);
  const mime = sniffMime(buf);
  return { file, mime, bytes: buf.length, sha256: sha256(buf), dataUri: `data:${mime};base64,${buf.toString("base64")}` };
}

// 表示・保存用の image_url（data URI 本体は残さない）
const conceptLabel = (c) => `data:${c.mime};base64,<${rel(c.file)} ${c.bytes} bytes sha256 ${c.sha256.slice(0, 16)}…>`;

// Image to 3D の本文。docs.meshy.ai/api/image-to-3d（2026-10）で確かめた項目だけ送る:
//   remove_lighting は meshy-6 専用（latest = meshy-7.1 では使えない）、origin_at は auto_size: true のときだけ有効
//   （寸法と原点は取り込み時に normalize_hero.py が合わせる）なので送らない
function modelBody(a, imageUrl, o) {
  if (a.cat === "props") return propModelBody(imageUrl, o);
  return {
    image_url: imageUrl,
    ai_model: "latest",
    should_texture: true,
    enable_pbr: true,
    texture_resolution: "2k",
    should_remesh: true,
    topology: "triangle",
    target_polycount: o.faces ?? CATS.heroes.defaultFaces,
    pose_mode: "t-pose",
  };
}

// Prop の Image to 3D（Smart Topology）。topology / should_remesh は smart-topology では無視される（三角形のみ）ので送らない。
// image_enhancement は meshy-6 / 7.1 専用、pose_mode は人型用なので送らない。使うのは GLB だけなので target_formats で絞る
function propModelBody(imageUrl, o) {
  return {
    image_url: imageUrl,
    model_type: "smart-topology",
    ai_model: "meshy-t2",
    target_polycount: o.faces ?? CATS.props.defaultFaces,
    should_texture: true,
    enable_pbr: true,
    texture_resolution: "2k",
    target_formats: ["glb"],
  };
}

// Prop のコンセプト画像（docs.meshy.ai/api/text-to-image）。negative_prompt の項目は無い（propPrompt が本文に畳み込む）。
// remove_background は使わない（無地の背景のまま Image to 3D へ渡す。目で確かめやすい）
const conceptBody = (a) => ({ ai_model: PROP_IMAGE_MODEL, prompt: propPrompt(a), aspect_ratio: PROP_ASPECT });

const rigBody = (inputTaskId) => ({ input_task_id: inputTaskId, height_meters: RIG_HEIGHT_M });

// MARK: - 実行

const forceIndex = (a, o) => (o.force.has("all") ? 0
  : Math.min(...[...o.force].map((f) => stagesOf(a).indexOf(f)).filter((i) => i >= 0), Infinity));
const untilList = (a, o) => (o.until ? stagesOf(a).slice(0, stagesOf(a).indexOf(o.until) + 1) : stagesOf(a));

function planStages(a, o) {
  const all = stagesOf(a);
  const fi = forceIndex(a, o);
  const busy = fi < all.length && busyFrom(a, all[fi]).length > 0;
  const plan = untilList(a, o).map((stage, i) => {
    const st = getStage(a, stage);
    if (i >= fi && busy) return { stage, action: "busy", st };
    if (i >= fi) return { stage, action: "submit", st, forced: !!st };
    if (!st) return { stage, action: "submit" };
    if (st.status === "SUCCEEDED") return { stage, action: "done", st };
    if (resumable(st)) return { stage, action: "resume", st };
    if (UNSURE.has(st.status)) return { stage, action: "blocked", st };
    return { stage, action: "submit", st };
  });
  // 前段が結果不明で止まっていれば後段も送らない（見積りにも数えない）
  const stop = plan.findIndex((p) => p.action === "blocked");
  return stop < 0 ? plan : plan.map((p, i) => (i > stop && p.action === "submit" ? { ...p, action: "waits" } : p));
}

const planCost = (a, plan) => plan.reduce((sum, p) => sum + (p.action === "submit" ? credit(a, p.stage) : 0), 0);
// 手元のコンセプト画像が要るか（ヒーローの model 段。Prop は同じランの concept 段が作る場合があるので、concept が済みのときだけ）
const needsConcept = (a, plan) => plan.some((p) => p.stage === "model" && p.action === "submit")
  && (a.cat === "heroes" || plan.find((p) => p.stage === "concept")?.action === "done");

class Runner {
  constructor(o) {
    this.o = o;
    this.submitLock = new Semaphore(1);
    this.halted = null;
    this.committed = 0; // このランで確保した見積り（完了したものは実績に置き換え）
    this.pending = new Map();
    this.placed = new Set(); // build/tripo/<cat>/<id>/ に Meshy の結果が置かれているアセットの key（今回置いた・置き済み）
    this.stats = { submitted: 0, success: 0, failed: 0, consumed: 0, delivered: 0 };
  }

  halt(msg) {
    if (this.halted) return;
    this.halted = msg;
    log(`\n${msg}\n  新しいタスクの送信を止めました（実行中のタスクは完了まで待ちます）`);
  }

  async runAsset(a) {
    // --force の段階（以降）を履歴へ移すのは、その段階を実際に送る直前（submit 内で予算・残高を確かめた後）。
    // 先に移すと、予算切れで送れなかったヒーローの結果だけが消える
    const all = stagesOf(a);
    const fi = forceIndex(a, this.o);
    let forcePending = fi < all.length;
    if (forcePending && busyFrom(a, all[fi]).length) {
      log(`  ${a.key}: ${busyFrom(a, all[fi]).map((s) => `${s} ${getStage(a, s).status}（${getStage(a, s).task_id}）`).join("、")} が実行中です。`
        + `課金済みなので作り直さず --force なしで完了させてください（作り直すならその後で --force）`);
      process.exitCode = 1;
      return;
    }
    for (const [i, stage] of untilList(a, this.o).entries()) {
      const forced = forcePending && i >= fi;
      if (this.halted && (forced || (getStage(a, stage)?.status !== "SUCCEEDED" && !resumable(getStage(a, stage))))) return;
      let ok;
      try {
        ok = await this.ensureStage(a, stage, forced);
      } catch (e) {
        log(`  ${tag(a, stage)} エラー: ${e.message}`);
        process.exitCode = 1;
        ok = false;
      }
      if (forced) forcePending = false; // 後の段階は archiveFrom が一緒に履歴へ移した
      if (!ok) return;
    }
    // 最後の段階（heroes: rig、props: model）まで済んだら tools/tripo.mjs import の入力として置く
    if (getStage(a, all[all.length - 1])?.status === "SUCCEEDED") {
      try {
        if ((a.cat === "props" ? deliverProp : deliver)(a, this.o)) this.stats.delivered++;
        this.placed.add(a.key);
      } catch (e) {
        log(`  ${a.key} 配置エラー: ${e.message}`);
        process.exitCode = 1;
      }
    }
  }

  // forced: --force で作り直す段階（既存の結果は送信の直前に履歴へ移す）
  async ensureStage(a, stage, forced = false) {
    const st = getStage(a, stage);
    if (!forced) {
      if (st?.status === "SUCCEEDED") return this.finish(a, stage, null);
      if (st && UNSURE.has(st.status) && !resumable(st)) {
        log(`  ${tag(a, stage)} 前回の送信結果が不明です（課金済みの可能性）。Meshy の利用履歴を確認し、作り直すなら --force ${stage}`);
        return false;
      }
    }
    let tid = !forced && resumable(st) ? st.task_id : null;
    if (tid) {
      log(`  ${tag(a, stage)} 実行中のタスクを再開: ${tid}`);
    } else {
      if (this.halted) return false;
      if (st && TERMINAL_FAIL.has(st.status) && !forced) log(`  ${tag(a, stage)} 前回 ${st.status} → 再送します`);
      tid = await this.submitStage(a, stage, forced);
      if (!tid) return false;
    }
    const task = await this.poll(a, stage, tid);
    if (!task) return false;
    const key = `${a.key}:${stage}`;
    const est = this.pending.get(key);
    this.pending.delete(key);
    if (task.status !== "SUCCEEDED") {
      if (est !== undefined) this.committed -= est; // 失敗・取消は返金される
      this.stats.failed++;
      return false;
    }
    const actual = num(task.consumed_credits);
    if (est !== undefined) this.committed += (actual ?? est) - est;
    this.stats.success++;
    if (est !== undefined) this.stats.consumed += actual ?? 0;
    setStage(a, stage, {
      status: "SUCCEEDED", progress: 100, credits_consumed: actual, completed_at: msIso(task.finished_at) || now(),
      expires_at: msIso(task.expires_at), outputs: urlKeys(task), error: null,
    });
    return this.finish(a, stage, task);
  }

  async submitStage(a, stage, forced) {
    let body;
    let record;
    if (stage === "concept") {
      body = conceptBody(a);
      record = { request: body };
    } else if (stage === "model") {
      const c = conceptInput(a);
      if (!c) {
        log(`  ${tag(a, stage)} ${rel(conceptPath(a))} がありません → スキップ（先に `
          + `${a.cat === "heroes" ? `tools/tripo.mjs run heroes ${a.id}` : `tools/meshy.mjs run props ${a.id}`} --until concept）`);
        return null;
      }
      body = modelBody(a, c.dataUri, this.o);
      record = { request: { ...body, image_url: conceptLabel(c) }, input_sha256: c.sha256 };
    } else {
      const m = getStage(a, "model");
      if (!(m?.status === "SUCCEEDED" && m.task_id)) { log(`  ${tag(a, stage)} 前段 model が未完了のため送信しません`); return null; }
      body = rigBody(m.task_id);
      record = { request: body, input: m.task_id };
    }
    return this.submit(a, stage, body, record, forced);
  }

  // 予算確認 → 送信（残高の確認と送信が並行で食い違わないよう 1 本ずつ）。Meshy は作成時に残高から引く（pilot の
  // balance_before が 255 → 249 → 243 → 228 と送信ごとに減っている）ので、直前の残高に実行中の分は含まれている。
  // 429（受け付け前の拒否）は待ってから、予算・残高・下限を確かめ直して送り直す（ロックは持ったまま＝他の送信も待つ）
  async submit(a, stage, body, record, forced = false) {
    await this.submitLock.acquire();
    try {
      const need = credit(a, stage);
      let archived = !forced;
      for (let attempt = 1; ; attempt++) {
        if (this.halted) return null;
        if (this.o.maxCredits !== undefined && this.committed + need > this.o.maxCredits) {
          this.halt(`--max-credits ${this.o.maxCredits} に達するため停止（このランの見積り ${fmtCredits(this.committed)} + 次の ${need}）`);
          return null;
        }
        const bal = await getBalance();
        if (bal < need) {
          this.halt(shortageText(need, bal));
          return null;
        }
        // 残高の下限（共有アカウントの別の作業の取り置き）。送った後の見込みが下回るなら送らない
        if (bal - need < this.o.reserve) {
          this.halt(`--reserve ${fmtCredits(this.o.reserve)} を下回るため停止（残高 ${fmtCredits(bal)} - 次の ${need} = ${fmtCredits(bal - need)}）`);
          return null;
        }
        if (!archived) { archiveFrom(a, stage); archived = true; }
        // 送信してよいのは未送信か失敗が確定した段階だけ（実行中・成功・結果不明の段階へ二重に課金しない）
        const cur = getStage(a, stage);
        if (cur && !TERMINAL_FAIL.has(cur.status)) {
          log(`  ${tag(a, stage)} 既に ${cur.status}${cur.task_id ? `（${cur.task_id}）` : ""} のため送信しません`);
          return null;
        }
        setStage(a, stage, {
          status: "submitting", task_id: null, input: null, input_sha256: null, ...record, estimate: need, balance_before: bal,
          submitted_at: now(), completed_at: null, progress: 0, credits_consumed: null, outputs: null, files: {}, error: null,
        });
        let json;
        try {
          ({ json } = await api("POST", ENDPOINTS[stage], body, { paid: true }));
        } catch (e) {
          // 「failed」（次回は再送）にするのは JSON の理由を伴う 4xx だけ（429 は受け付け前の拒否）。
          // 5xx・通信エラー・タイムアウト・JSON でない応答はタスクが作られて課金済みの可能性があるので「unknown」にして、
          // 次回は --force なしでは再送しない
          const definite = e instanceof MeshyError && DEFINITE_REJECT.has(e.status) && !!e.json;
          if (definite) {
            // 待つ間に落ちても次回は再送してよい（拒否が確定）ので、待つ前に failed にしておく
            setStage(a, stage, { status: "failed", error: scrub(e.message) });
            if (e.insufficientCredits) { this.halt(shortageText(need, await getBalance().catch(() => 0))); return null; }
            if (e.status === 429 && attempt < MAX_ATTEMPTS_429) {
              const wait = e.retryAfter ?? backoffSec(attempt);
              console.error(`  ${tag(a, stage)} HTTP 429（受け付け前の拒否）のため ${wait}s 後に残高を確かめ直して再送（${attempt}/${MAX_ATTEMPTS_429 - 1}）`);
              await sleep(wait * 1000);
              continue;
            }
          } else {
            // 課金済みかもしれないので --max-credits の勘定に入れる（返金の確認はできない）。通信・サーバの不調が
            // 続くと結果不明の送信が重なるので、このランの新しい送信は止める
            this.committed += need;
            setStage(a, stage, { status: "unknown", error: scrub(e.message) });
            this.halt(`${tag(a, stage)} 送信結果が不明です（タスクが作られ課金済みの可能性）。Meshy の利用履歴を確認してください`);
          }
          throw e;
        }
        const tid = typeof json?.result === "string" ? json.result : null;
        if (!tid) {
          this.committed += need;
          setStage(a, stage, { status: "unknown", error: "応答に result（task_id）がありません" });
          this.halt(`${tag(a, stage)} 応答に task_id がありません（タスクが作られ課金済みの可能性）。Meshy の利用履歴を確認してください`);
          throw new Error(`${ENDPOINTS[stage]} の応答に result がありません`);
        }
        return this.accepted(a, stage, tid, need, bal);
      }
    } finally {
      this.submitLock.release();
    }
  }

  accepted(a, stage, tid, need, bal) {
    setStage(a, stage, { status: "PENDING", task_id: tid });
    this.committed += need;
    this.pending.set(`${a.key}:${stage}`, need);
    this.stats.submitted++;
    log(`  ${tag(a, stage)} 送信: ${tid}（見積り ${need} credits、送信前の残高 ${fmtCredits(bal)}）`);
    return tid;
  }

  // Retry-After（無ければ 5 秒）ごとに状態を確認。表示は状態か進捗（10% 刻み）が変わったときと 1 分ごと
  async poll(a, stage, tid) {
    const t0 = Date.now();
    const submittedAt = Date.parse(getStage(a, stage)?.submitted_at ?? "") || t0;
    let lastLine = "";
    let lastPrint = 0;
    let notFound = 0;
    for (;;) {
      let task;
      let res;
      try {
        ({ json: task, res } = await getTask(stage, tid));
      } catch (e) {
        if (e instanceof MeshyError && e.status === 404) {
          notFound++;
          if (Date.now() - submittedAt < NOT_FOUND_GRACE_MS || notFound < NOT_FOUND_MIN_TRIES) {
            await sleep(Math.min(POLL_DEFAULT_MS * notFound, 15_000));
            continue;
          }
          // task_id は残す（次回の run で問い合わせ直す。--force だと再課金になる）
          setStage(a, stage, { status: "unknown", error: "タスクが見つかりません（404）" });
          log(`  ${tag(a, stage)} タスク ${tid} が見つかりません（404）。次回の run で問い合わせ直します。`
            + `Meshy の利用履歴でタスクが無いことを確かめてから --force ${stage} で作り直してください（作り直しは再課金）`);
          return null;
        }
        throw e;
      }
      notFound = 0;
      const status = task?.status || "unknown";
      const progress = num(task?.progress) ?? 0;
      const line = `${status} ${Math.floor(progress / 10)}`;
      if (line !== lastLine || Date.now() - lastPrint > 60_000) {
        const q = status === "PENDING" && num(task?.preceding_tasks) ? `  待ち ${task.preceding_tasks}` : "";
        log(`  ${pad(tag(a, stage), 18)} ${pad(status, 11)} ${String(progress).padStart(3)}%  ${pad(elapsed(t0), 7)} ${tid}${q}`);
        lastLine = line;
        lastPrint = Date.now();
      }
      if (status === "SUCCEEDED") return task;
      if (TERMINAL_FAIL.has(status)) {
        const te = task.task_error || {};
        const err = [te.type, te.code, te.message].filter((x) => x !== undefined && x !== null && x !== "").join(" ") || null;
        setStage(a, stage, { status, error: err, credits_consumed: num(task.consumed_credits), completed_at: msIso(task.finished_at) || now() });
        log(`  ${tag(a, stage)} ${status}${err ? `: ${err}` : ""}（失敗は返金。consumed_credits ${fmtCredits(num(task.consumed_credits))}）`);
        return task;
      }
      const st = getStage(a, stage);
      if (st?.status !== status && ACTIVE.has(status)) setStage(a, stage, { status, progress, credits_consumed: num(task.consumed_credits) });
      if (Date.now() - t0 > POLL_TIMEOUT_MS) {
        log(`  ${tag(a, stage)} ${Math.round(POLL_TIMEOUT_MS / 60000)} 分待っても完了しません。後で同じコマンドを実行すると続きから待ちます`);
        return null;
      }
      const ra = Number(res?.headers?.get("retry-after"));
      await sleep(ra > 0 ? Math.min(Math.max(ra * 1000, 2000), 30_000) : POLL_DEFAULT_MS);
    }
  }

  // 完了後: ダウンロード（URL は期限付きなので必要ならタスクを取り直す）と概要の表示
  async finish(a, stage, task) {
    const st = getStage(a, stage);
    const dir = assetDir(a);
    fs.mkdirSync(dir, { recursive: true });
    const files = { ...(st.files || {}) };
    let fresh = task;
    let refetched = false;
    let changed = false;
    for (const [pick, name, kind, required] of STAGE_FILES[stage]) {
      const dest = path.join(dir, name);
      if (files[name]?.path === rel(dest) && !badContent(dest, kind) && files[name].sha256 === sha256File(dest)) continue;
      if (!required && name in files && files[name] === null) continue; // 出力に無かった任意のファイル
      if (!fresh) {
        try {
          fresh = (await getTask(stage, st.task_id)).json;
        } catch (e) {
          // 結果の保持は 3 日。任意のファイルのためだけに取り直せなくても先へ進む
          if (required) throw e;
          log(`  ${tag(a, stage)} ${name} を取得できないため省略: ${e.message}`);
          continue;
        }
      }
      const url = pick(fresh);
      if (!url) {
        const keys = urlKeys(fresh).join(", ") || "なし";
        if (required) {
          log(`  ${tag(a, stage)} 出力に ${name} の URL がありません（URL のあるキー: ${keys}）。node tools/meshy.mjs task ${stage} ${st.task_id} で確認`);
          return false;
        }
        log(`  ${tag(a, stage)} ${name} は出力に無いため省略（URL のあるキー: ${keys}）`);
        files[name] = null;
        changed = true;
        continue;
      }
      let size;
      try {
        try {
          size = await download(url, dest, kind);
        } catch (e) {
          // 署名付き URL は期限付き（並行ダウンロードの待ちなどで切れることがある）→ タスクを GET し直して 1 回だけ再試行（再送はしない）
          if (refetched || ![400, 401, 403, 404, 410].includes(e.status)) throw e;
          fresh = (await getTask(stage, st.task_id)).json;
          refetched = true;
          const url2 = pick(fresh);
          if (!url2) throw e;
          log(`  ${tag(a, stage)} ${name}: ダウンロード URL の期限切れとみなしタスクを取り直して再試行`);
          size = await download(url2, dest, kind);
        }
      } catch (e) {
        if (required) throw e;
        log(`  ${tag(a, stage)} ${name} を取得できないため省略: ${e.message}`);
        continue;
      }
      files[name] = { path: rel(dest), bytes: size, sha256: sha256File(dest) };
      changed = true;
      const dim = kind === "image" ? imageSize(readHead(dest, 1 << 16)) : null;
      log(`  ${tag(a, stage)} 保存: ${rel(dest)}（${fmtBytes(size)}${dim ? `、${dim.join("x")}` : ""}）`);
      if (kind === "model") {
        const info = glbInfo(dest);
        if (info) {
          files[name].info = { tris: info.tris, joints: info.joints.length, textures: info.textures.map((t) => (t.size ? t.size.join("x") : "?")) };
          log(`    三角形 ${info.tris}、マテリアル ${info.materials}、テクスチャ ${info.textures.map((t) => `${t.size ? t.size.join("x") : "?"} ${t.mime || ""}`.trim()).join(" / ") || "なし"}`
            + `${info.animations ? `、アニメーション ${info.animations}` : ""}`);
          if (info.joints.length) log(`    骨 ${info.joints.length} 本: ${info.joints.join(" ")}`);
        }
      }
    }
    if (changed) setStage(a, stage, { files });
    return true;
  }
}

// MARK: - tools/tripo.mjs import への受け渡し

// Prop の受け渡し: build/meshy/props/<kind>/model.glb を build/tripo/props/<kind>/model.glb へ写し、同じフォルダの
// source.json に出どころと正面の向き（PROP_FRONT）を書く。tools/tripo.mjs import props は source.json の sha256 が
// model.glb と一致するときだけその front で正規化する（Tripo が model.glb を作り直せば外れて Tripo の +X に戻る）。
// 置き先の model.glb が Meshy 以外（state の delivered と sha256 が合わない）なら --replace-tripo のときだけ
// model.tripo.glb（既にあれば日時付き）へ退避してから置き換える。
const SOURCE_JSON = "source.json";

function foreignModel(a) {
  const file = path.join(tripoDir(a), "model.glb");
  if (!fs.existsSync(file)) return [];
  const h = sha256File(file);
  const ours = state.assets[a.key]?.delivered?.glb?.sha256 === h;
  const same = (() => { const src = path.join(assetDir(a), "model.glb"); return fs.existsSync(src) && sha256File(src) === h; })();
  return ours || same ? [] : [file];
}

// 置き先に Meshy 以外の結果があるか（run の送信前の確認用）
const foreignOutputs = (a) => (a.cat === "props" ? foreignModel(a) : foreignRigged(a));

function deliverProp(a, o) {
  const src = path.join(assetDir(a), "model.glb");
  const bad = badContent(src, "model");
  if (bad) throw new Error(`${rel(src)}: ${bad}`);
  const dir = tripoDir(a);
  fs.mkdirSync(dir, { recursive: true });
  const dest = path.join(dir, "model.glb");
  const srcHash = sha256File(src);
  const conflicts = foreignModel(a);
  if (conflicts.length && !o.replaceTripo) {
    throw new Error(`${rel(dest)} は Meshy 以外（Tripo など）のファイルです。置き換えるなら --replace-tripo（model.tripo.glb へ退避）`);
  }
  for (const file of conflicts) {
    let backup = path.join(dir, "model.tripo.glb");
    if (fs.existsSync(backup)) backup = backup.replace(/(\.[^.]+)$/, `.${now().replace(/[:.]/g, "-")}$1`);
    fs.renameSync(file, backup);
    log(`  ${a.key} 退避: ${rel(file)} → ${rel(backup)}`);
  }
  let changed = true;
  if (fs.existsSync(dest) && sha256File(dest) === srcHash) {
    changed = false;
  } else {
    const tmp = path.join(dir, `.model.glb.${process.pid}.part`);
    fs.copyFileSync(src, tmp);
    fs.renameSync(tmp, dest);
  }
  // 出どころの控え（秘密・署名付き URL は含めない）。model.glb より後に置く（途中で落ちても sha256 が合わず無視される）
  const sidecar = {
    note: "tools/meshy.mjs が自動生成。tools/tripo.mjs import props は sha256 が model.glb と一致するときだけ front を使う",
    provider: "meshy",
    front: PROP_FRONT,
    sha256: srcHash,
    from: rel(src),
    task_id: getStage(a, "model")?.task_id ?? null,
    concept_task_id: getStage(a, "concept")?.task_id ?? null,
    at: now(),
  };
  const sideFile = path.join(dir, SOURCE_JSON);
  let sideSame = false;
  try { const cur = JSON.parse(fs.readFileSync(sideFile, "utf8")); sideSame = cur.sha256 === srcHash && cur.front === PROP_FRONT && cur.provider === "meshy"; } catch { /* 無い */ }
  if (!sideSame) {
    const tmp = path.join(dir, `.${SOURCE_JSON}.${process.pid}.part`);
    fs.writeFileSync(tmp, JSON.stringify(sidecar, null, 2) + "\n");
    fs.renameSync(tmp, sideFile);
    changed = true;
  }
  setAsset(a, { delivered: { glb: { path: rel(dest), sha256: srcHash, from: rel(src), front: PROP_FRONT, at: now() } } });
  log(`  ${a.key} ${changed ? "配置" : "配置済み"}: ${rel(dest)}（正面 ${PROP_FRONT}、${rel(sideFile)}）→ 取り込み: node tools/tripo.mjs import props ${a.id}`);
  return changed;
}

// build/meshy/heroes/<id>/rigged.<source> を build/tripo/heroes/<id>/rigged.<source> へ写す。tripo.mjs import は rigged.fbx が
// あれば rigged.glb より優先するので、glb を渡すときは置き先の rigged.fbx が邪魔になる。置き先にある rigged.* のうち
// このツールが置いたもの（state の delivered と sha256 が一致）は上書き・削除してよいが、それ以外（Tripo のリグなど）は
// --replace-tripo のときだけ rigged.tripo.<ext>（既にあれば日時付き）へ退避してから置き換える。
// 置き先にある Meshy 以外（state の delivered と sha256 が合わない）の rigged.glb / rigged.fbx。run の前の確認用
function foreignRigged(a) {
  const prev = state.assets[a.key]?.delivered || {};
  return ["glb", "fbx"].map((ext) => [path.join(tripoDir(a), `rigged.${ext}`), ext])
    .filter(([file, ext]) => fs.existsSync(file) && prev[ext]?.sha256 !== sha256File(file)).map(([file]) => file);
}

function deliver(a, o) {
  const src = path.join(assetDir(a), `rigged.${o.source}`);
  const bad = badContent(src, o.source === "glb" ? "model" : "fbx");
  if (bad) throw new Error(`${rel(src)}: ${bad}`);
  const dir = tripoDir(a);
  fs.mkdirSync(dir, { recursive: true });
  const prev = state.assets[a.key]?.delivered || {};
  const other = o.source === "glb" ? "fbx" : "glb";
  const dest = path.join(dir, `rigged.${o.source}`);
  const srcHash = sha256File(src);
  const ours = (file, ext) => fs.existsSync(file) && prev[ext]?.sha256 === sha256File(file);
  const conflicts = [];
  // 上書きする同じ形式のファイルと、glb を置くときの rigged.fbx（import で glb より優先されるので残すと Meshy の glb が
  // 使われない）。fbx を置くときの rigged.glb は import が読まないのでそのまま残す
  const check = [[dest, o.source], ...(o.source === "glb" ? [[path.join(dir, "rigged.fbx"), "fbx"]] : [])];
  for (const [file, ext] of check) {
    if (!fs.existsSync(file) || ours(file, ext)) continue;
    if (file === dest && sha256File(file) === srcHash) continue; // 中身が同じ
    conflicts.push(file);
  }
  if (conflicts.length && !o.replaceTripo) {
    throw new Error(`${conflicts.map(rel).join(", ")} は Meshy 以外（Tripo など）のファイルです。置き換えるなら --replace-tripo（rigged.tripo.* へ退避）`);
  }
  for (const file of conflicts) {
    let backup = path.join(dir, path.basename(file).replace(/^rigged\./, "rigged.tripo."));
    if (fs.existsSync(backup)) backup = backup.replace(/(\.[^.]+)$/, `.${now().replace(/[:.]/g, "-")}$1`);
    fs.renameSync(file, backup);
    log(`  ${a.key} 退避: ${rel(file)} → ${rel(backup)}`);
  }
  // 自分が前に置いた反対側の形式は消す（import が取り違えないように）
  const otherFile = path.join(dir, `rigged.${other}`);
  if (ours(otherFile, other)) { fs.rmSync(otherFile); log(`  ${a.key} 削除: ${rel(otherFile)}（前回 Meshy が置いた ${other}）`); }
  let changed = true;
  if (fs.existsSync(dest) && sha256File(dest) === srcHash) {
    changed = false;
  } else {
    const tmp = path.join(dir, `.rigged.${o.source}.${process.pid}.part`);
    fs.copyFileSync(src, tmp);
    fs.renameSync(tmp, dest);
  }
  setAsset(a, { delivered: { [o.source]: { path: rel(dest), sha256: srcHash, from: rel(src), at: now() } } });
  log(`  ${a.key} ${changed ? "配置" : "配置済み"}: ${rel(dest)} → 取り込み: node tools/tripo.mjs import heroes ${a.id}`);
  return changed;
}

// MARK: - dry-run・run

function printJSONIndented(obj, indent) {
  for (const line of JSON.stringify(obj, null, 2).split("\n")) log(indent + line);
}

function dryRun(plans, o) {
  let total = 0;
  for (const { a, plan } of plans) {
    const extra = a.cat === "props" ? `（${a.label}、grip ${a.entry.grip}${a.entry.optional ? "、任意" : ""}${a.entry.bodyWorn ? "、bodyWorn: 取り込みはしない" : ""}）` : a.label;
    log(`\n${a.key}  ${extra}`);
    let c = null;
    try { c = needsConcept(a, plan) ? conceptInput(a) : null; } catch (e) { log(`  ${e.message} → スキップ`); continue; }
    if (needsConcept(a, plan) && !c && a.cat === "heroes") { log(`  ${rel(conceptPath(a))} がありません → スキップ`); continue; }
    const planned = new Set();
    for (const p of plan) {
      const head = `  ${pad(p.stage, 8)}`;
      if (p.action === "done") { log(`${head}済み（${p.st.task_id}）→ スキップ`); continue; }
      if (p.action === "resume") { log(`${head}${p.st.status === "unknown" ? "前回 404 だったタスク" : "実行中"}（${p.st.task_id}, ${p.st.status}）→ ポーリングを再開`); continue; }
      if (p.action === "blocked") { log(`${head}前回の送信結果が不明（${p.st.status}）→ 送信しない。作り直すなら --force ${p.stage}`); continue; }
      if (p.action === "waits") { log(`${head}前段の結果が不明なので送信しない`); continue; }
      if (p.action === "busy") { log(`${head}${p.st ? `${p.st.status}（${p.st.task_id}）` : "後段が実行中"} → --force でも作り直さない（実行中は課金済み。--force なしで完了させる）`); continue; }
      let body;
      if (p.stage === "concept") body = conceptBody(a);
      else if (p.stage === "model") {
        // Prop は同じランの concept 段の出力（まだ無い）を送る
        const label = c ? conceptLabel(c) : `data:image/png;base64,<${rel(conceptPath(a))}（concept 段の出力）>`;
        body = modelBody(a, label, o);
      } else {
        const m = getStage(a, "model");
        body = rigBody(planned.has("model") || !(m?.status === "SUCCEEDED") ? `<${a.key} model の task_id>` : m.task_id);
      }
      planned.add(p.stage);
      total += credit(a, p.stage);
      const note = p.forced ? "（--force: 既存の結果を履歴へ移して再送）" : p.st ? `（前回 ${p.st.status} → 再送）` : "";
      log(`${head}POST ${API}${ENDPOINTS[p.stage]}  見積り ${credit(a, p.stage)} credits${note}`);
      printJSONIndented(body, "    ");
      log(`    → ${STAGE_FILES[p.stage].map(([, name]) => rel(path.join(assetDir(a), name))).join(", ")}`);
    }
    const last = stagesOf(a)[stagesOf(a).length - 1];
    if (o.until && o.until !== last) continue;
    if (a.cat === "props") {
      log(`  配置    ${rel(path.join(assetDir(a), "model.glb"))} → ${rel(path.join(tripoDir(a), "model.glb"))} + ${rel(path.join(tripoDir(a), SOURCE_JSON))}`
        + `（front ${PROP_FRONT}。Meshy 以外の model.glb があれば${o.replaceTripo ? " model.tripo.glb へ退避" : "中止。--replace-tripo で退避して置き換え"}）`);
    } else {
      log(`  配置    ${rel(path.join(assetDir(a), `rigged.${o.source}`))} → ${rel(path.join(tripoDir(a), `rigged.${o.source}`))}`
        + `（Meshy 以外の rigged.* があれば${o.replaceTripo ? " rigged.tripo.* へ退避" : "中止。--replace-tripo で退避して置き換え"}）`);
    }
  }
  return total;
}

async function cmdRun(cat, ids, o) {
  if (!CATS[cat]) fail(`run の対象は ${Object.keys(CATS).join(" | ")}`);
  const stages = CATS[cat].stages;
  if (o.until && !stages.includes(o.until)) fail(`run ${cat} の --until は ${stages.join(" | ")}: ${o.until}`);
  for (const f of o.force) if (f !== "all" && !stages.includes(f)) fail(`run ${cat} の --force は ${stages.join(" | ")} | all: ${f}`);
  if (o.until && [...o.force].some((f) => f !== "all" && stages.indexOf(f) > stages.indexOf(o.until))) {
    fail(`--force は --until ${o.until} より後の段階を含みます（送信せずに既存の結果を履歴へ移すことになるため中止）`);
  }
  const [fmin, fmax] = CATS[cat].faces;
  if (o.faces !== undefined && (o.faces < fmin || o.faces > fmax)) fail(`run ${cat} の --faces は ${fmin}〜${fmax}: ${o.faces}`);
  if (cat === "props" && o.source !== DEFAULT_SOURCE) fail("--source は heroes のみ");
  // --all に --force を付けると全件を作り直す（ヒーロー 24 体なら 840 credits）→ 打ち間違いで使い切らないよう上限を必須にする
  if (!ids.length && o.force.size && o.maxCredits === undefined && !o.dry) {
    fail("--all と --force を一緒に使うときは --max-credits N も指定してください（全件の作り直し＝再課金になるため）");
  }
  const chosen = select(cat, ids, o);
  for (const a of chosen.filter((x) => x.entry.bodyWorn)) {
    log(`  ${a.key}: 体に付ける装着物（bodyWorn）。名指しされたので作るが、tools/tripo.mjs import は取り込まない（本体のメッシュに含める）`);
  }
  // コンセプト画像の無い・送れないヒーローは model を送れないので外す（Prop は concept 段が作る）
  const missing = chosen.filter((a) => a.cat === "heroes" && needsConcept(a, planStages(a, o)) && conceptProblem(a));
  for (const a of missing) {
    const why = conceptProblem(a);
    log(`  ${a.key}: ${rel(conceptPath(a))} ${why === "ありません" ? `がありません → スキップ（先に node tools/tripo.mjs run heroes ${a.id} --until concept）` : `は送れません: ${why} → スキップ`}`);
  }
  // 置き先に Tripo などの結果が既にあるアセットは、課金してから配置で断られないよう送信前に外す（--replace-tripo で置き換え）
  // （--until で最後の段階まで行かないランは配置しないので見ない）
  const delivers = !o.until || o.until === stages[stages.length - 1];
  const foreign = o.replaceTripo || !delivers ? [] : chosen.filter((a) => !missing.includes(a) && planCost(a, planStages(a, o)) > 0 && foreignOutputs(a).length);
  for (const a of foreign) {
    log(`  ${a.key}: ${foreignOutputs(a).map(rel).join(", ")} は Meshy 以外のファイルです → スキップ（置き換えるなら --replace-tripo）`);
  }
  const assets = chosen.filter((a) => !missing.includes(a) && !foreign.includes(a));
  if ((missing.length || foreign.length) && ids.length) process.exitCode = 1;
  const plans = assets.map((a) => ({ a, plan: planStages(a, o) }));
  const total = plans.reduce((sum, p) => sum + planCost(p.a, p.plan), 0);
  const limits = (o.maxCredits !== undefined ? `、上限 --max-credits ${o.maxCredits}` : "") + (o.reserve ? `、下限 --reserve ${fmtCredits(o.reserve)}` : "");

  if (o.dry) {
    DRY = true;
    log(`[dry-run] run ${cat}: ${assets.length} 件。有料 API は呼ばず、state.json もファイルも変更しません`);
    const t = dryRun(plans, o);
    log(`\n[dry-run] 新規送信の見積り合計: ${t} credits${limits}`);
    if (hasApiKey()) {
      try {
        const bal = await getBalance();
        const need = Math.min(t, o.maxCredits ?? Infinity) + o.reserve;
        log(`[dry-run] 残高 ${fmtCredits(bal)}${bal < need ? ` → 不足 ${fmtCredits(need - bal)}（見積り${o.reserve ? ` + 下限 ${fmtCredits(o.reserve)}` : ""}）。購入: ${PURCHASE_URL}` : ` → 送信後の見込み ${fmtCredits(bal - Math.min(t, o.maxCredits ?? Infinity))}`}`);
      } catch (e) {
        log(`[dry-run] 残高を取得できません: ${e.message}`);
      }
    }
    return;
  }

  const bal = await getBalance();
  log(`run ${cat}: ${assets.length} 件、新規送信の見積り ${total} credits、残高 ${fmtCredits(bal)}${limits}`);
  const needNow = Math.min(total, o.maxCredits ?? Infinity);
  if (needNow > 0 && bal - needNow < o.reserve && !o.allowPartial) {
    fail(`${o.reserve ? `残高 ${fmtCredits(bal)} - 見積り ${fmtCredits(needNow)} が下限 --reserve ${fmtCredits(o.reserve)} を下回ります\n` : ""}`
      + `${shortageText(needNow + o.reserve, bal)}\n  途中まででよければ --allow-partial（残高・下限に達した時点で送信を止めます）か --max-credits N`);
  }
  if (!assets.length) return;

  const runner = new Runner(o);
  process.on("SIGINT", () => {
    console.error("\n中断しました。送信済みのタスクは Meshy 側で続行し、次回の run で続きから再開します"
      + (o.force.size ? "（--force は外して再実行。付けたままだと作り直し＝再課金）" : ""));
    process.exit(130);
  });
  let next = 0;
  const worker = async () => { while (next < assets.length) await runner.runAsset(assets[next++]); };
  await Promise.all(Array.from({ length: Math.min(o.concurrency, assets.length) }, worker));

  const s = runner.stats;
  let after = null;
  try { after = await getBalance(); } catch { /* 表示だけ */ }
  log(`\n完了: 送信 ${s.submitted}、成功 ${s.success}、失敗 ${s.failed}、消費 ${fmtCredits(s.consumed)} credits、配置 ${s.delivered}`
    + (after !== null ? `、残高 ${fmtCredits(bal)} → ${fmtCredits(after)}` : ""));
  if (runner.halted) log(`停止理由: ${runner.halted.split("\n")[0]}`);
  const lastAll = stages[stages.length - 1];
  const last = o.until ?? lastAll;
  const done = assets.filter((a) => getStage(a, last)?.status === "SUCCEEDED");
  const placed = done.filter((a) => runner.placed.has(a.key) && !a.entry.bodyWorn);
  if (placed.length && last === lastAll) log(`取り込み: node tools/tripo.mjs import ${cat} ${placed.map((a) => a.id).join(" ")}`);
  if (cat === "props" && last === "concept" && done.length) {
    log(`コンセプト画像: ${done.map((a) => rel(conceptPath(a))).join(" ")}（確かめてから --until なしで model へ。作り直しは --force concept）`);
  }
  const incomplete = assets.filter((a) => !done.includes(a));
  if (incomplete.length) log(`未完了: ${incomplete.map((a) => a.id).join(" ")}（node tools/meshy.mjs status で確認）`);
  if (incomplete.length || runner.halted) process.exitCode = 1;
}

// MARK: - 見積り・状態

async function cmdEstimate(catArg, ids, o) {
  const cats = catArg ? [catArg] : Object.keys(CATS);
  if (cats.some((c) => !CATS[c])) fail(`estimate の対象は ${Object.keys(CATS).join(" | ")}`);
  if (ids.length && cats.length > 1) fail("ID を指定するときは heroes | props も指定してください");
  log(`見積り（docs.meshy.ai/api/pricing 2026-10 時点。失敗は返金。作り直しの余裕は含まない）`);
  const rows = [["", "件数", "1 件あたり", "合計", "未完了分（state 基準）"]];
  let remAll = 0;
  const notes = [];
  for (const cat of cats) {
    const list = select(cat, ids, o, true);
    const { stages, credits } = CATS[cat];
    const per = stages.reduce((s, st) => s + credits[st], 0);
    const rem = list.reduce((s, a) => s + planCost(a, planStages(a, { ...o, until: undefined, force: new Set() })), 0);
    remAll += rem;
    rows.push([cat, String(list.length), `${per}（${stages.map((st) => `${st} ${credits[st]}`).join(" + ")}）`, String(per * list.length), String(rem)]);
    if (cat === "heroes") {
      const noConcept = list.filter((a) => badContent(conceptPath(a), "image"));
      if (noConcept.length) notes.push(`heroes: コンセプト画像なし ${noConcept.length} 件（run では飛ばす）: ${noConcept.map((a) => a.id).join(" ")}`);
    } else if (!ids.length) {
      const skipped = MANIFEST.props.filter(skipByDefault);
      if (skipped.length) notes.push(`props: 任意・装着物の ${skipped.map((a) => a.id).join(" / ")} を除く（名指ししたときだけ対象）`);
    }
  }
  table(rows);
  for (const n of notes) log(`  ${n}`);
  if (!hasApiKey()) { log("  残高: API キーが無いため未取得"); return; }
  let bal;
  try { bal = await getBalance(); } catch (e) { log(`  残高を取得できません: ${e.message}`); process.exitCode = 1; return; }
  const need = remAll + o.reserve;
  log(`  残高 ${fmtCredits(bal)} credits${o.reserve ? `（下限 --reserve ${fmtCredits(o.reserve)}）` : ""}`
    + (bal >= need ? ` → 足ります（未完了分の後 ${fmtCredits(bal - remAll)}）` : ` → 不足 ${fmtCredits(need - bal)} credits。購入: ${PURCHASE_URL}`));
}

function cellFor(a, stage) {
  const st = getStage(a, stage);
  if (!st) return "-";
  if (st.status === "SUCCEEDED") {
    const stale = stage === "model" && st.input_sha256 && fs.existsSync(conceptPath(a)) && sha256File(conceptPath(a)) !== st.input_sha256 ? " 古い" : "";
    return `ok ${fmtCredits(st.credits_consumed)}${stale}`;
  }
  if (ACTIVE.has(st.status)) return `${st.status} ${st.progress ?? 0}%`;
  return st.status;
}

function cmdStatus() {
  let consumed = 0;
  let active = 0;
  let failed = 0;
  for (const as of Object.values(state.assets)) {
    for (const st of Object.values(as.stages || {})) {
      if (st.status === "SUCCEEDED" || ACTIVE.has(st.status)) consumed += num(st.credits_consumed) ?? 0;
      if (ACTIVE.has(st.status) || UNSURE.has(st.status)) active++;
      if (TERMINAL_FAIL.has(st.status)) failed++;
    }
    for (const h of as.history || []) if (h.status === "SUCCEEDED") consumed += num(h.credits_consumed) ?? 0;
  }
  log(`state: ${fs.existsSync(STATE_PATH) ? rel(STATE_PATH) : "（まだありません）"}${state.updated_at ? `（更新 ${state.updated_at}）` : ""}`);
  log(`ファイル: ${rel(BUILD_DIR)}/<heroes|props>/<id>/、配置先: ${rel(TRIPO_BUILD_DIR)}/<heroes|props>/<id>/（ヒーローのコンセプト画像もここから読む）`);
  const placedCell = (a) => Object.entries(state.assets[a.key]?.delivered || {}).map(([ext, d]) => {
    const f = path.resolve(ROOT, d.path);
    const cur = fs.existsSync(f) ? (sha256File(f) === d.sha256 ? "" : "（変更あり）") : "（無い）";
    return `${path.basename(d.path)}${d.front ? ` front ${d.front}` : ""}${cur}`;
  }).join(" ");
  const localCell = (a) => {
    const dir = assetDir(a);
    return fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => !f.endsWith(".part")).sort().join(" ") : "";
  };
  log("\nheroes");
  const hrows = [["ID", "名前", "concept", ...CATS.heroes.stages, "配置", "ローカル"]];
  for (const a of MANIFEST.heroes) {
    hrows.push([a.id, a.label, fs.existsSync(conceptPath(a)) ? "あり" : "-", ...CATS.heroes.stages.map((s) => cellFor(a, s)), placedCell(a) || "-", localCell(a) || "-"]);
  }
  table(hrows);
  log("\nprops");
  const prows = [["kind", "使用", ...CATS.props.stages, "配置", "ローカル"]];
  for (const a of MANIFEST.props) {
    const tagText = a.entry.bodyWorn ? "（装着物）" : a.entry.optional ? "（任意）" : "";
    prows.push([a.id, `${a.label}${tagText}`, ...CATS.props.stages.map((s) => cellFor(a, s)), placedCell(a) || "-", localCell(a) || "-"]);
  }
  table(prows);
  log(`\n消費合計 ${fmtCredits(consumed)} credits、実行中・不明 ${active}、失敗 ${failed}`);
}

// MARK: - main

function usage() {
  const h = CATS.heroes.credits;
  const p = CATS.props.credits;
  console.log(`Meshy パイプライン（VELSTRIA/ で実行）
  node tools/meshy.mjs balance                                   残高（無料 API）
  node tools/meshy.mjs estimate [heroes|props] [ids...|--all]    見積り（残高と比較）
  node tools/meshy.mjs run heroes [H001 ...|--all] [--until model|rig] [--faces N] [--source glb|fbx] [--replace-tripo]
                                                                  tools/tripo.mjs のコンセプト画像 → Image to 3D（${h.model}）→ Auto-Rigging（${h.rig}）→ 配置
  node tools/meshy.mjs run props [<kind> ...|--all] [--until concept|model] [--faces N] [--replace-tripo]
                                                                  Text to Image ${PROP_IMAGE_MODEL}（${p.concept}）→ Image to 3D meshy-t2（${p.model}）→ 配置（model.glb + source.json）
                                                                  --all は任意・装着物（bodyWorn）を除く。--faces は ${CATS.props.faces.join("〜")}（既定 ${CATS.props.defaultFaces}）
      共通: --dry-run          送信内容と出力先を表示するだけ（有料 API・state.json・ファイルに触れない）
            --max-credits N    このランで使う上限（見積りベース）
            --reserve N        残高の下限（環境変数 MESHY_RESERVE でも可）。送信後の見込みが下回るなら送らない
            --force <stage>    指定段階（以降）を作り直す（heroes: model | rig、props: concept | model、all。カンマ区切り可。
                               実行中の段階は不可、--all なら --max-credits 必須）
            --concurrency N    同時に進めるアセット数（既定 3）
            --allow-partial    残高が見積りに満たなくても始める（尽きたら送信を止める）
            --source glb|fbx   heroes: tools/tripo.mjs import へ渡す形式（既定 ${DEFAULT_SOURCE}）
            --replace-tripo    ${rel(TRIPO_BUILD_DIR)}/<cat>/<id>/ の Meshy 以外の rigged.* / model.glb を *.tripo.* へ退避して置き換える
                               （無いと、そのアセットは送信前に外す＝課金してから配置で断られない）
  node tools/meshy.mjs status                                    アセット × 段階の状態・消費・配置
  node tools/meshy.mjs task <concept|model|rig> <task_id>        タスクの JSON（署名付き URL は伏せる）

  取り込み: node tools/tripo.mjs import heroes <id>（rigged.fbx があれば rigged.glb より優先）
            node tools/tripo.mjs import props <kind>（source.json の front を使う）
  API キー: MESHY_API_KEY または ~/.config/meshy/api_key（リポジトリに置かない）  購入: ${PURCHASE_URL}`);
}

const [cmd, ...rest] = process.argv.slice(2);
const o = parseArgs(rest);
if (!cmd || cmd === "help" || o.help) { usage(); process.exit(cmd && cmd !== "help" && !o.help ? 1 : 0); }

try {
  if (cmd === "run" && !o.dry) lockState();
  switch (cmd) {
    case "balance":
      log(`残高 ${fmtCredits(await getBalance())} credits`);
      break;
    case "estimate":
      await cmdEstimate(o.pos[0], o.pos.slice(1), o);
      break;
    case "run":
      await cmdRun(o.pos[0], o.pos.slice(1), o);
      break;
    case "status":
      cmdStatus();
      break;
    case "task": {
      const stage = KIND_ALIASES[o.pos[0]];
      if (!stage || !o.pos[1]) fail("使い方: node tools/meshy.mjs task <concept|model|rig> <task_id>");
      const { json } = await getTask(stage, o.pos[1]);
      console.log(scrub(JSON.stringify(redactUrls(json), null, 2)));
      break;
    }
    default:
      usage();
      process.exit(1);
  }
} catch (e) {
  fail(e.message);
}
