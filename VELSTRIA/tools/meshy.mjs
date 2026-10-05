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
//   node tools/meshy.mjs task <concept|model|rig|anim> <task_id>   タスクの JSON（署名付き URL は伏せる）
//
// アニメーション（モーションクリップ抽出 tools/blender/extract_clips.py の入力。docs/HERO_MOTION.md）:
//   node tools/meshy.mjs anim --rig H002 --actions 97,105,128 [--dry-run] [--max-credits N] [--fps 24|25|30|60]
//       [--allow-partial] [--force anim] [--concurrency N]
//     既存の rig タスク（state.json の heroes/<id> の rig）にライブラリのモーションを買って付け、GLB を保存する
//     （POST /openapi/v1/animations の action_ids、1 action 3 credits、1 タスク 10 個まで → 10 個ずつに分ける）。
//     保存先 build/meshy/anim/<id>/batch_<先頭の action_id>-<個数>.glb（1 action = 1 クリップ、action_ids の順。
//     ライブラリ名のクリップ。同じ名前を別のタスクが使っていれば batch_<先頭>-<個数>_<task_id>.glb）と
//     manifest.json（{ "<action_id>": { file, clip_index, name, task_id, credits, ... } }）。
//     state.json の assets["heroes/<id>"].animations にタスク（task_id・action_ids・状態・消費）を記録する（URL は残さない）。
//     manifest にあり中身も合う action（同じ rig のもの）は買わない。購入済みなら結果（保持期限切れなら手元の GLB）から
//     無料で manifest を作り直す。前回の送信結果が不明な action は --force anim なしでは送らない。
//     rig の結果の保持（3 日）が切れていれば送らない（作り直すなら run heroes <id> --force rig）。
//     --fps は post_process change_fps。docs で変換後の出力として載っているのは FBX（processed_animation_fps_fbx_url →
//     batch_*.<fps>fps.fbx）だけなので、抽出は既定（--fps なし）の GLB を使う
//   node tools/meshy.mjs anim-basic --rig H002 [--dry-run] [--force anim]
//     rig タスクの結果に付く無料の歩き・走り（result.basic_animations.*_glb_url）を build/meshy/anim/<id>/basic_{walking,running}.glb
//     へ保存（控えは同じ場所の basic.json。state.json は書かない）
//   node tools/meshy.mjs anim-library [--search 文字列] [--category Fighting]
//     ライブラリの一覧（無料 API。build/meshy/anim/library.json にそのままの配列でキャッシュ、7 日で取り直す）
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
const ENDPOINTS = {
  concept: "/openapi/v1/text-to-image", model: "/openapi/v1/image-to-3d", rig: "/openapi/v1/rigging", anim: "/openapi/v1/animations",
};
const KIND_ALIASES = {
  concept: "concept", "text-to-image": "concept", model: "model", "image-to-3d": "model", rig: "rig", rigging: "rig",
  anim: "anim", animation: "anim", animations: "anim",
};
/** Animation（1 action あたり。action_ids は 1 タスク 10 個まで）。 */
const ANIM_CREDITS = 3;
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

const VALUE_FLAGS = new Set(["until", "faces", "max-credits", "reserve", "force", "concurrency", "source", "rig", "actions", "fps", "search",
  "category"]);
const ANIM_FPS = [24, 25, 30, 60]; // post_process change_fps が受け付ける値
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
  // 段階名はカテゴリごとに cmdRun で確かめ直す（heroes: model | rig、props: concept | model）。anim は anim / anim-basic 用
  if (flags.until !== undefined && !ALL_STAGES.includes(flags.until)) fail(`--until は ${ALL_STAGES.join(" | ")}: ${flags.until}`);
  for (const f of flags.force || []) if (f !== "all" && f !== "anim" && !ALL_STAGES.includes(f)) fail(`--force は ${ALL_STAGES.join(" | ")} | all | anim: ${f}`);
  if (flags.fps !== undefined && !ANIM_FPS.includes(Number(flags.fps))) fail(`--fps は ${ANIM_FPS.join(" | ")}: ${flags.fps}`);
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
    rig: flags.rig,
    actions: flags.actions,
    fps: flags.fps === undefined ? undefined : Number(flags.fps),
    search: flags.search,
    category: flags.category,
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

// GLB のアニメーション（クリップ名・長さ・キー数・キー間隔から推した fps）。glTF はアニメーションの時刻 accessor に
// min/max を必須にしているので JSON チャンクだけで分かる
function glbAnimations(file) {
  const buf = fs.readFileSync(file);
  if (buf.length < 20 || buf.toString("latin1", 0, 4) !== "glTF") return null;
  const g = JSON.parse(buf.toString("utf8", 20, 20 + buf.readUInt32LE(12)));
  return (g.animations || []).map((an, index) => {
    let t0 = Infinity;
    let t1 = 0;
    let keys = 0;
    for (const s of an.samplers || []) {
      const acc = g.accessors?.[s.input];
      if (!acc) continue;
      t0 = Math.min(t0, num(acc.min?.[0]) ?? 0);
      t1 = Math.max(t1, num(acc.max?.[0]) ?? 0);
      keys = Math.max(keys, acc.count || 0);
    }
    const duration = Number.isFinite(t0) ? Math.max(0, t1 - t0) : 0;
    const fps = duration > 0 && keys > 1 ? Math.round(((keys - 1) / duration) * 100) / 100 : null;
    return { index, name: an.name ?? `#${index}`, duration: Math.round(duration * 1000) / 1000, keys, fps };
  });
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
  if (o.force.has("anim")) fail("--force anim は anim / anim-basic 用です（run では段階名か all）");
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

// MARK: - アニメーション（既存のリグにライブラリのモーションを付ける）

const ANIM_DIR = path.join(BUILD_DIR, "anim");
const animDir = (a) => path.join(ANIM_DIR, a.id);
const LIBRARY_PATH = path.join(ANIM_DIR, "library.json");
const LIBRARY_MAX_AGE_MS = 7 * 24 * 3600_000; // 廃止された action が残らないよう時々取り直す（docs の推奨）
const RESULT_KEEP_MS = 3 * 24 * 3600_000; // Meshy の結果の保持。state に expires_at が無いときの推定に使う
// 送信から完了まで数分かかる。期限間際の rig へ送ると処理中に消えて失敗しうる（失敗は返金だが待ちが無駄）→ 余裕を見る
const RIG_EXPIRY_MARGIN_MS = 10 * 60_000;
const ANIM_BATCH = 10; // action_ids の上限（docs: 1〜10 個、重複不可）
const BASIC_ANIMS = [["walking", "basic_walking.glb"], ["running", "basic_running.glb"]];

function fmtDuration(ms) {
  const m = Math.floor(Math.abs(ms) / 60_000);
  const d = Math.floor(m / 1440);
  const h = Math.floor((m % 1440) / 60);
  return d ? `${d}日 ${h}時間` : h ? `${h}時間 ${m % 60}分` : `${m % 60}分`;
}

// ファイルを一時ファイル経由で書く（途中で落ちても壊れた JSON を残さない）
function writeJsonAtomic(file, obj) {
  if (DRY) throw new Error(`内部エラー: dry-run 中に ${rel(file)} を書こうとしました`);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(obj, null, 2) + "\n");
  fs.renameSync(tmp, file);
}

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (e) {
    if (e.code === "ENOENT") return fallback;
    return fail(`${rel(file)} を読めません: ${e.message}（壊れている場合は退避してから再実行）`);
  }
}

function rigHero(o) {
  if (!o.rig) fail("--rig <ヒーロー ID> を指定してください（例: --rig H002）");
  return select("heroes", [o.rig], o)[0];
}

function parseActionIds(s) {
  if (!s) fail("--actions に action_id をカンマ区切りで指定してください（例: --actions 97,105,128。一覧は node tools/meshy.mjs anim-library）");
  const out = [];
  for (const t of String(s).split(",").map((x) => x.trim()).filter(Boolean)) {
    const n = Number(t);
    if (!/^\d+$/.test(t) || !Number.isSafeInteger(n)) fail(`--actions は 0 以上の整数のカンマ区切り: ${t}`);
    // 同じ id を 2 回送ると 400（重複不可）。1 回にまとめる
    if (out.includes(n)) { log(`  action ${n} が重複しています → 1 回だけ`); continue; }
    out.push(n);
  }
  if (!out.length) fail("--actions が空です");
  return out;
}

// ライブラリ一覧（無料 API）。キャッシュが無い・古い・要る id を含まないときだけ取り直す。write: false（dry-run）は保存しない
async function loadLibrary(needIds = [], { write = true } = {}) {
  let cached = null;
  try {
    if (Date.now() - fs.statSync(LIBRARY_PATH).mtimeMs < LIBRARY_MAX_AGE_MS) cached = JSON.parse(fs.readFileSync(LIBRARY_PATH, "utf8"));
  } catch { cached = null; }
  const covers = (list) => Array.isArray(list) && needIds.every((id) => list.some((x) => x?.action_id === id));
  if (covers(cached)) return { map: new Map(cached.map((x) => [x.action_id, x])), from: rel(LIBRARY_PATH) };
  if (!hasApiKey()) {
    if (Array.isArray(cached)) return { map: new Map(cached.map((x) => [x.action_id, x])), from: `${rel(LIBRARY_PATH)}（API キーが無いため古いまま）` };
    return { map: new Map(), from: null };
  }
  const { json } = await api("GET", `${ENDPOINTS.anim}/library`);
  if (!Array.isArray(json)) throw new Error("ライブラリの応答が配列ではありません");
  if (write) writeJsonAtomic(LIBRARY_PATH, json);
  return { map: new Map(json.map((x) => [x.action_id, x])), from: write ? `API → ${rel(LIBRARY_PATH)}` : "API" };
}

const libCells = (item) => (item ? [item.name, `${item.category}/${item.sub_category}`] : ["（ライブラリに無い）", ""]);

// rig タスクの id と結果の保持期限。期限は state の expires_at（無ければ完了 + 3 日）、remote なら GET（無料）で確かめ直す
// （404 = 保持期限切れか削除）
async function rigInfo(a, { remote = true } = {}) {
  const st = getStage(a, "rig");
  if (!(st?.status === "SUCCEEDED" && st.task_id)) {
    fail(`${a.key} の rig が完了していません（${st ? st.status : "未実行"}）。先に node tools/meshy.mjs run heroes ${a.id}`);
  }
  const r = { tid: st.task_id, expiresMs: Date.parse(st.expires_at ?? "") || (Date.parse(st.completed_at ?? "") + RESULT_KEEP_MS) || null, task: null, gone: false, checked: false };
  if (!remote) return r;
  try {
    r.task = (await getTask("rig", r.tid)).json;
    r.checked = true;
    r.expiresMs = num(r.task?.expires_at) || r.expiresMs;
  } catch (e) {
    if (!(e instanceof MeshyError && e.status === 404)) throw e;
    r.gone = true;
    r.checked = true;
  }
  return r;
}

function rigText(r) {
  const src = r.checked ? "GET で確認" : "state.json の記録";
  if (r.gone) return `rig ${r.tid}: 見つかりません（404。保持期限切れか削除）`;
  if (r.task && r.task.status !== "SUCCEEDED") return `rig ${r.tid}: 状態 ${r.task.status}（SUCCEEDED でない）`;
  if (!r.expiresMs) return `rig ${r.tid}: 保持期限不明（${src}）`;
  const left = r.expiresMs - Date.now();
  return `rig ${r.tid}: 保持期限 ${new Date(r.expiresMs).toISOString()}（${left > 0 ? `残り ${fmtDuration(left)}` : `${fmtDuration(left)} 前に期限切れ`}、${src}）`;
}

// 新しいアニメーションを買ってよい rig か（期限間際も不可）
const rigUsable = (r) => !r.gone && (!r.task || r.task.status === "SUCCEEDED") && (!r.expiresMs || r.expiresMs - Date.now() > RIG_EXPIRY_MARGIN_MS);
const rigExpiredText = (a, r) => `${rigText(r)}。この rig には新しいアニメーションを付けられません`
  + `（作り直すなら node tools/meshy.mjs run heroes ${a.id} --force rig: ${CATS.heroes.credits.rig} credits。リグが変わるので買ったアニメーションも買い直し）`;

const manifestPath = (a) => path.join(animDir(a), "manifest.json");
const animRecords = (a) => state.assets[a.key]?.animations || [];

function addAnimRecord(a, rec) {
  const as = (state.assets[a.key] ||= { stages: {} });
  (as.animations ||= []).push(rec);
  rec.updated_at = now();
  saveState();
  return rec;
}

function patchAnim(rec, patch) {
  Object.assign(rec, patch, { updated_at: now() });
  saveState();
  return rec;
}

const isResumable = (rec) => !!(rec?.task_id && (ACTIVE.has(rec.status) || rec.status === "unknown"));
const expiredRec = (rec) => Date.parse(rec?.expires_at ?? "") < Date.now();
const batchBase = (ids) => `batch_${ids[0]}-${ids.length}`;
// 保存先のファイル名。基本は batch_<先頭>-<個数>.glb だが、同じ名前を別のタスクが使っていれば task_id を付ける
// （--force anim で先頭と個数が同じ別の組を買うと前のファイルを上書きし、manifest の他の action が別のクリップを指す）
const batchNameTaken = (a, name, manifest, tid) => animRecords(a).some((r) => r.task_id !== tid && r.file && path.basename(r.file) === name)
  || Object.values(manifest).some((m) => m?.file === name && m.task_id !== tid);
// rec の保存先。一度決めた名前は rec.file に残す（取り直し・再開で同じファイルへ）。並行する保存と同じ名前を取り合わないよう、
// ダウンロードを待つ前に確保する（state.json へは保存時に書く）
function batchFile(a, rec, manifest) {
  if (rec.file) return path.join(animDir(a), path.basename(rec.file));
  let name = `${batchBase(rec.action_ids)}.glb`;
  if (batchNameTaken(a, name, manifest, rec.task_id)) name = `${batchBase(rec.action_ids)}_${rec.task_id}.glb`;
  rec.file = rel(path.join(animDir(a), name));
  return path.join(animDir(a), name);
}
const animBody = (rigTid, ids, o) => ({
  rig_task_id: rigTid,
  action_ids: ids,
  ...(o.fps ? { post_process: { operation_type: "change_fps", fps: o.fps } } : {}),
});

// 要求された action ごとの扱い。同じ rig の記録だけを見る（rig を作り直したら骨とメッシュが変わるので買い直し）
//   resume: 実行中（課金済み）のタスクを待つ（--force anim でも買い直さない）。404 で不明になったタスクも問い合わせ直す
//           （こちらは --force anim なら買い直す。run の --force と同じ）
//   done:   manifest にあり、ファイルの中身も合う
//   fetch:  成功済みのタスクから取り直す（無料）。保持期限切れでも手元の GLB が記録と合えば manifest だけ書き直す
//   blocked: 前回の送信結果が不明（課金済みの可能性）→ --force anim なしでは送らない
//   submit: 新しく買う（未購入・失敗・保持期限切れで手元にも無い・--force anim）
function planAnim(a, rigTid, ids, o, manifest) {
  const force = o.force.has("anim");
  const recs = animRecords(a).filter((r) => r.rig_task_id === rigTid);
  const shaCache = new Map();
  const fileOk = (file, sha) => {
    if (!shaCache.has(file)) shaCache.set(file, fs.existsSync(file) && !badContent(file, "model") ? sha256File(file) : null);
    return !!sha && shaCache.get(file) === sha;
  };
  const localOk = (r) => !!r.file && fileOk(path.join(animDir(a), path.basename(r.file)), r.sha256);
  const plan = { rows: [], resume: new Map(), fetch: new Map(), submit: [] };
  const push = (map, rec, id) => map.set(rec, [...(map.get(rec) || []), id]);
  for (const id of ids) {
    const rec = recs.findLast((r) => r.action_ids?.includes(id));
    // 最新の記録が失敗・不明でも、それより前に成功したタスクがあればそこから無料で取り直せる
    const ok = recs.findLast((r) => r.status === "SUCCEEDED" && r.task_id && r.action_ids?.includes(id) && (!expiredRec(r) || localOk(r)));
    const m = manifest[String(id)];
    let action;
    let src = rec;
    if ((ACTIVE.has(rec?.status) && rec.task_id) || (!force && isResumable(rec))) { action = "resume"; push(plan.resume, rec, id); }
    else if (!force && m?.rig_task_id === rigTid && fileOk(path.join(animDir(a), String(m.file)), m.sha256)) action = "done";
    else if (!force && ok) { action = "fetch"; src = ok; push(plan.fetch, ok, id); }
    else if (!force && rec && UNSURE.has(rec.status)) action = "blocked";
    else { action = "submit"; plan.submit.push(id); }
    plan.rows.push({ id, action, rec: src, m, local: action === "fetch" && expiredRec(src) });
  }
  return plan;
}

const chunk = (xs, n) => Array.from({ length: Math.ceil(xs.length / n) }, (_, i) => xs.slice(i * n, i * n + n));

function planRowText(row, rigTid, force) {
  const { action, rec, m } = row;
  if (action === "resume") return `実行中のタスクを待つ（${rec.task_id}, ${rec.status}）`;
  if (action === "done") return `済み（${m.file} clip ${m.clip_index}）→ スキップ`;
  if (action === "fetch") return `購入済み（${rec.task_id}）→ ${row.local ? "手元の GLB から manifest を書き直す（保持期限切れ）" : "取り直す（無料）"}`;
  if (action === "blocked") return `前回の送信結果が不明（${rec.status}${rec.task_id ? ` ${rec.task_id}` : ""}）→ 送らない。Meshy の利用履歴を確かめ、買い直すなら --force anim`;
  const why = [];
  if (force && (m || rec)) why.push("--force anim で買い直し");
  if (m && m.rig_task_id !== rigTid) why.push("manifest は別の rig のもの");
  if (rec && TERMINAL_FAIL.has(rec.status)) why.push(`前回 ${rec.status}`);
  if (rec?.status === "SUCCEEDED" && expiredRec(rec)) why.push("前回の結果は保持期限切れ");
  return `購入 ${ANIM_CREDITS} credits${why.length ? `（${why.join("、")}）` : ""}`;
}

// クリップと action の対応。docs ではクリップは action_ids の順・名前はライブラリ名（同名が重なると後ろに action_id が付く）。
// Meshy の GLB のクリップ名は "Armature|walking_man|baselayer" のような | 区切りなので、どれかの区切りが名前か key と
// 一致すれば同じとみなす。名前で全部一意に決まればそれを使い（読み込み・書き出しで順番が変わっても取り違えない）、
// 決まらなければ本数が合うときだけ順番どおり
const normName = (s) => String(s ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
function clipMatches(clipName, item, id) {
  if (!item) return false;
  const parts = [clipName, ...String(clipName ?? "").split("|")].map(normName).filter(Boolean);
  const names = [item.name, item.key].map(normName).filter(Boolean);
  return parts.some((c) => names.some((n) => c === n || c === `${n}${id}`));
}

function mapClips(ids, clips, lib) {
  const used = new Set();
  const byName = [];
  for (const id of ids) {
    const hits = clips.filter((c) => !used.has(c.index) && clipMatches(c.name, lib.get(id), id));
    if (hits.length !== 1) break;
    used.add(hits[0].index);
    byName.push(hits[0].index);
  }
  if (byName.length === ids.length) return { mapping: byName, how: "name" };
  if (clips.length === ids.length) return { mapping: ids.map((_, k) => k), how: "order" };
  return null;
}

// タスクの出力 URL からダウンロード。署名付き URL が期限切れなら（400/401/403/404/410）タスクを GET し直して 1 回だけ再試行
async function downloadFromTask(getFresh, task, pick, dest, kind, label) {
  let fresh = task ?? (await getFresh());
  const url = pick(fresh);
  if (!url) return { missing: true, keys: urlKeys(fresh) };
  try {
    return { size: await download(url, dest, kind) };
  } catch (e) {
    if (![400, 401, 403, 404, 410].includes(e.status)) throw e;
    fresh = await getFresh();
    const url2 = pick(fresh);
    if (!url2) throw e;
    log(`  ${label}: ダウンロード URL の期限切れとみなしタスクを取り直して再試行`);
    return { size: await download(url2, dest, kind) };
  }
}

// actionOf: クリップ番号 → action_id（Map。基本アニメーションなど対応が無ければ null）
function printClips(clips, actionOf, lib, indent = "    ") {
  const rows = [["clip", "名前", "長さ", "キー", "fps", ...(actionOf ? ["action", "ライブラリ名"] : [])]];
  for (const c of clips) {
    const id = actionOf?.get(c.index);
    rows.push([String(c.index), c.name, `${c.duration}s`, String(c.keys), c.fps === null ? "-" : String(c.fps),
      ...(actionOf ? [id === undefined ? "-" : String(id), id === undefined ? "-" : (lib.get(id)?.name ?? "?")] : [])]);
  }
  table(rows, indent);
}

class AnimRunner {
  constructor(a, rigTid, lib, manifest, o) {
    Object.assign(this, { a, rigTid, lib, manifest, o });
    this.submitLock = new Semaphore(1);
    this.halted = null;
    this.committed = 0; // このランで確保した見積り（完了したものは実績に置き換え）
    this.pending = new Map();
    this.stats = { submitted: 0, success: 0, failed: 0, consumed: 0, saved: 0 };
  }

  label(rec) { return `${this.a.key} anim ${rec.action_ids.join(",")}`; }

  halt(msg) {
    if (this.halted) return;
    this.halted = msg;
    log(`\n${msg}\n  新しいタスクの送信を止めました（実行中のタスクは完了まで待ちます）`);
  }

  // 予算確認 → 送信（残高の確認と送信が食い違わないよう 1 本ずつ）。送信の扱いは Runner.submit と同じ
  async submit(ids) {
    await this.submitLock.acquire();
    let rec;
    try {
      if (this.halted) return null;
      const need = ANIM_CREDITS * ids.length;
      if (this.o.maxCredits !== undefined && this.committed + need > this.o.maxCredits) {
        this.halt(`--max-credits ${this.o.maxCredits} に達するため停止（このランの見積り ${fmtCredits(this.committed)} + 次の ${need}）`);
        return null;
      }
      const bal = await getBalance();
      if (bal < need) { this.halt(shortageText(need, bal)); return null; }
      const body = animBody(this.rigTid, ids, this.o);
      rec = addAnimRecord(this.a, {
        task_id: null, rig_task_id: this.rigTid, action_ids: ids, fps: this.o.fps ?? null, request: body, status: "submitting",
        estimate: need, balance_before: bal, submitted_at: now(), completed_at: null, expires_at: null, progress: 0,
        credits_consumed: null, file: null, bytes: null, sha256: null, clips: null, outputs: null, error: null,
      });
      let json;
      try {
        ({ json } = await api("POST", ENDPOINTS.anim, body, { paid: true }));
      } catch (e) {
        // JSON の理由を伴う 4xx だけ「failed」（次回は送り直す）。5xx・通信エラー・タイムアウトはタスクが作られ課金済みの
        // 可能性があるので「unknown」にし、次回は --force anim なしでは送らない
        const definite = e instanceof MeshyError && DEFINITE_REJECT.has(e.status) && !!e.json;
        if (definite) {
          patchAnim(rec, { status: "failed", error: scrub(e.message) });
          if (e.insufficientCredits) { this.halt(shortageText(need, await getBalance().catch(() => 0))); return null; }
        } else {
          this.committed += need;
          patchAnim(rec, { status: "unknown", error: scrub(e.message) });
          log(`  ${this.label(rec)} 送信結果が不明です（タスクが作られ課金済みの可能性）。Meshy の利用履歴を確認してください`);
        }
        throw e;
      }
      const tid = typeof json?.result === "string" ? json.result : null;
      if (!tid) {
        this.committed += need;
        patchAnim(rec, { status: "unknown", error: "応答に result（task_id）がありません" });
        throw new Error(`${ENDPOINTS.anim} の応答に result がありません`);
      }
      patchAnim(rec, { status: "PENDING", task_id: tid });
      this.committed += need;
      this.pending.set(rec, need);
      this.stats.submitted++;
      log(`  ${this.label(rec)} 送信: ${tid}（見積り ${need} credits、送信前の残高 ${fmtCredits(bal)}）`);
      return rec;
    } finally {
      this.submitLock.release();
    }
  }

  async runBatch(ids) {
    if (this.halted) return false;
    const rec = await this.submit(ids);
    if (!rec) return false;
    return this.waitAndSave(rec);
  }

  async waitAndSave(rec) {
    const task = await this.poll(rec);
    if (!task) return false;
    const est = this.pending.get(rec);
    this.pending.delete(rec);
    if (task.status !== "SUCCEEDED") {
      if (est !== undefined) this.committed -= est; // 失敗・取消は返金される
      this.stats.failed++;
      process.exitCode = 1;
      return false;
    }
    const actual = num(task.consumed_credits);
    if (est !== undefined) { this.committed += (actual ?? est) - est; this.stats.consumed += actual ?? 0; }
    this.stats.success++;
    patchAnim(rec, {
      status: "SUCCEEDED", progress: 100, credits_consumed: actual, completed_at: msIso(task.finished_at) || now(),
      expires_at: msIso(task.expires_at), outputs: urlKeys(task), error: null,
    });
    return this.save(rec, task);
  }

  // Retry-After（無ければ 5 秒）ごとに状態を確認（Runner.poll と同じ。404 は作成直後の遅れを待ってから unknown にする）
  async poll(rec) {
    const t0 = Date.now();
    const submittedAt = Date.parse(rec.submitted_at ?? "") || t0;
    const label = this.label(rec);
    let lastLine = "";
    let lastPrint = 0;
    let notFound = 0;
    for (;;) {
      let task;
      let res;
      try {
        ({ json: task, res } = await getTask("anim", rec.task_id));
      } catch (e) {
        if (e instanceof MeshyError && e.status === 404) {
          notFound++;
          if (Date.now() - submittedAt < NOT_FOUND_GRACE_MS || notFound < NOT_FOUND_MIN_TRIES) {
            await sleep(Math.min(POLL_DEFAULT_MS * notFound, 15_000));
            continue;
          }
          patchAnim(rec, { status: "unknown", error: "タスクが見つかりません（404）" });
          log(`  ${label} タスク ${rec.task_id} が見つかりません（404）。次回の anim で問い合わせ直します。`
            + "Meshy の利用履歴でタスクが無いことを確かめてから --force anim で買い直してください（再課金）");
          process.exitCode = 1;
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
        log(`  ${pad(label, 26)} ${pad(status, 11)} ${String(progress).padStart(3)}%  ${pad(elapsed(t0), 7)} ${rec.task_id}${q}`);
        lastLine = line;
        lastPrint = Date.now();
      }
      if (status === "SUCCEEDED") return task;
      if (TERMINAL_FAIL.has(status)) {
        const te = task.task_error || {};
        const err = [te.type, te.code, te.message].filter((x) => x !== undefined && x !== null && x !== "").join(" ") || null;
        patchAnim(rec, { status, error: err, credits_consumed: num(task.consumed_credits), completed_at: msIso(task.finished_at) || now() });
        log(`  ${label} ${status}${err ? `: ${err}` : ""}（失敗は返金。consumed_credits ${fmtCredits(num(task.consumed_credits))}）`);
        return task;
      }
      if (rec.status !== status && ACTIVE.has(status)) patchAnim(rec, { status, progress, credits_consumed: num(task.consumed_credits) });
      if (Date.now() - t0 > POLL_TIMEOUT_MS) {
        log(`  ${label} ${Math.round(POLL_TIMEOUT_MS / 60000)} 分待っても完了しません。後で同じコマンドを実行すると続きから待ちます`);
        process.exitCode = 1;
        return null;
      }
      const ra = Number(res?.headers?.get("retry-after"));
      await sleep(ra > 0 ? Math.min(Math.max(ra * 1000, 2000), 30_000) : POLL_DEFAULT_MS);
    }
  }

  // 成功したタスクの GLB を保存し、クリップを action へ対応付けて manifest.json を書く。task が null なら GET し直す（URL は期限付き）
  async save(rec, task) {
    const ids = rec.action_ids;
    const dir = animDir(this.a);
    fs.mkdirSync(dir, { recursive: true });
    const dest = batchFile(this.a, rec, this.manifest);
    const base = path.basename(dest, ".glb");
    const label = this.label(rec);
    const getFresh = async () => (await getTask("anim", rec.task_id)).json;
    let size;
    if (rec.sha256 && fs.existsSync(dest) && !badContent(dest, "model") && sha256File(dest) === rec.sha256) {
      size = fs.statSync(dest).size; // ファイルはそのまま（manifest が欠けただけ）
    } else {
      const r = await downloadFromTask(getFresh, task, (t) => t?.result?.animation_glb_url, dest, "model", label);
      if (r.missing) {
        log(`  ${label} 出力に animation_glb_url がありません（URL のあるキー: ${r.keys.join(", ") || "なし"}）。node tools/meshy.mjs task anim ${rec.task_id} で確認`);
        process.exitCode = 1;
        return false;
      }
      size = r.size;
      this.stats.saved++;
      log(`  ${label} 保存: ${rel(dest)}（${fmtBytes(size)}）`);
    }
    let fpsFbx = null;
    if (rec.fps) {
      // fps 変換の出力（FBX）。抽出には使わない控えなので取れなくても先へ進む
      const fdest = path.join(dir, `${base}.${rec.fps}fps.fbx`);
      try {
        const r = await downloadFromTask(getFresh, task, (t) => t?.result?.processed_animation_fps_fbx_url, fdest, "fbx", label);
        if (r.missing) log(`  ${label} processed_animation_fps_fbx_url は出力に無いため省略`);
        else { fpsFbx = path.basename(fdest); log(`  ${label} 保存: ${rel(fdest)}（${fmtBytes(r.size)}）`); }
      } catch (e) {
        log(`  ${label} ${path.basename(fdest)} を取得できないため省略: ${e.message}`);
      }
    }
    const sha = sha256File(dest);
    const clips = glbAnimations(dest) || [];
    const mapped = mapClips(ids, clips, this.lib);
    const fileRec = { file: rel(dest), bytes: size, sha256: sha, clips: clips.map((c) => c.name) };
    if (!mapped) {
      const err = `クリップ ${clips.length} 本（${clips.map((c) => c.name).join(", ")}）を action ${ids.length} 個へ対応付けられません`;
      patchAnim(rec, { ...fileRec, error: err });
      log(`  ${label} ${err}。manifest は更新しません`);
      process.exitCode = 1;
      return false;
    }
    const { mapping, how } = mapped;
    if (how === "name" && mapping.some((x, k) => x !== k)) log(`  ${label} 注意: クリップの順番が action_ids と違うため名前で対応付けました`);
    const perAction = num(rec.credits_consumed) !== null ? rec.credits_consumed / ids.length : ANIM_CREDITS;
    ids.forEach((id, k) => {
      const c = clips[mapping[k]];
      const item = this.lib.get(id);
      if (item && !clipMatches(c.name, item, id)) log(`  ${label} 注意: clip ${c.index} の名前 "${c.name}" がライブラリ名 "${item.name}"（action ${id}）と一致しません（順番で対応付け）`);
      this.manifest[String(id)] = {
        file: path.basename(dest), clip_index: c.index, name: item?.name ?? c.name, clip_name: c.name, matched_by: how, task_id: rec.task_id,
        credits: perAction, rig_task_id: rec.rig_task_id, sha256: sha, duration: c.duration, keys: c.keys, fps: c.fps,
        ...(fpsFbx ? { fps_fbx: fpsFbx } : {}),
      };
    });
    writeJsonAtomic(manifestPath(this.a), sortedManifest(this.manifest));
    patchAnim(rec, { ...fileRec, error: null });
    printClips(clips, new Map(ids.map((id, k) => [mapping[k], id])), this.lib);
    return true;
  }
}

const sortedManifest = (m) => Object.fromEntries(Object.entries(m).sort(([x], [y]) => Number(x) - Number(y)));

async function cmdAnim(o) {
  if ([...o.force].some((f) => f !== "anim")) fail("anim の --force は anim だけ（買い直し。実行中のタスクは買い直さない）");
  const a = rigHero(o);
  const ids = parseActionIds(o.actions);
  if (o.dry) DRY = true;
  const head = o.dry ? "[dry-run] " : "";
  log(`${head}anim ${a.key}  ${a.label}${o.dry ? "（有料 API は呼ばず、state.json もファイルも変更しません）" : ""}`);
  const r = await rigInfo(a, { remote: hasApiKey() });
  log(`  ${rigText(r)}`);
  const lib = await loadLibrary(ids, { write: !o.dry });
  log(`  ライブラリ: ${lib.from ?? "取得できません（API キーが無くキャッシュも無い）"}`);
  const unknownIds = lib.from ? ids.filter((id) => !lib.map.has(id)) : [];
  if (unknownIds.length) fail(`ライブラリに無い action_id: ${unknownIds.join(", ")}（node tools/meshy.mjs anim-library で確認。廃止された id は送ると 400）`);

  const manifest = readJson(manifestPath(a), {});
  const plan = planAnim(a, r.tid, ids, o, manifest);
  table(plan.rows.map((row) => [String(row.id), ...libCells(lib.map.get(row.id)), "→", planRowText(row, r.tid, o.force.has("anim"))]), "    ");

  // 予算: --max-credits と残高に収まる数だけ買う（action 単位で切る。残りは次回）
  let submit = plan.submit;
  const notes = [];
  if (submit.length && !rigUsable(r)) {
    const msg = rigExpiredText(a, r);
    if (!plan.resume.size && !plan.fetch.size) fail(msg);
    log(`\nerror: ${msg}`);
    process.exitCode = 1;
    submit = [];
  }
  if (o.maxCredits !== undefined && submit.length * ANIM_CREDITS > o.maxCredits) {
    const n = Math.floor(o.maxCredits / ANIM_CREDITS);
    notes.push(`--max-credits ${o.maxCredits} のため ${n} 個だけ買います（次回へ: ${submit.slice(n).join(",")}）`);
    submit = submit.slice(0, n);
  }
  let bal = null;
  if (submit.length && (!o.dry || hasApiKey())) {
    try { bal = await getBalance(); } catch (e) { if (!o.dry) throw e; log(`  残高を取得できません: ${e.message}`); }
  }
  if (bal !== null && bal < submit.length * ANIM_CREDITS) {
    const n = Math.floor(bal / ANIM_CREDITS);
    if (!o.allowPartial && !o.dry) fail(`${shortageText(submit.length * ANIM_CREDITS, bal)}\n  途中まででよければ --allow-partial（買える ${n} 個だけ）か --max-credits N`);
    notes.push(`残高 ${fmtCredits(bal)} のため ${n} 個だけ${o.allowPartial ? "買います" : "（--allow-partial なら）"}（不足: ${submit.slice(n).join(",")}）`);
    if (o.allowPartial) submit = submit.slice(0, n);
  }
  for (const n of notes) log(`  ${n}`);
  const batches = chunk(submit, ANIM_BATCH);
  const cost = submit.length * ANIM_CREDITS;

  if (o.dry) {
    // 表示だけ（batchFile は rec.file を確保するので dry-run では使わない）
    const recFile = (rec) => rel(path.join(animDir(a), rec.file ? path.basename(rec.file) : `${batchBase(rec.action_ids)}.glb`));
    for (const [rec, rids] of plan.resume) log(`\n  待つ: ${rec.task_id}（${rec.status}、action ${rec.action_ids.join(",")}）→ ${recFile(rec)}${rids.length < rec.action_ids.length ? "（他の action も含む）" : ""}`);
    for (const [rec] of plan.fetch) log(`\n  取り直し: ${rec.task_id}（action ${rec.action_ids.join(",")}）→ ${recFile(rec)}`);
    batches.forEach((b, i) => {
      log(`\n  batch ${i + 1}/${batches.length}: POST ${API}${ENDPOINTS.anim}  見積り ${b.length * ANIM_CREDITS} credits（${b.length} × ${ANIM_CREDITS}）`);
      printJSONIndented(animBody(r.tid, b, o), "    ");
      const base = batchNameTaken(a, `${batchBase(b)}.glb`, manifest) ? `${batchBase(b)}_<task_id>` : batchBase(b);
      log(`    → ${rel(path.join(animDir(a), `${base}.glb`))}${o.fps ? ` と ${base}.${o.fps}fps.fbx` : ""}`);
      b.forEach((id, k) => log(`       clip ${k} = ${id} ${lib.map.get(id)?.name ?? "?"}`));
    });
    log(`    manifest: ${rel(manifestPath(a))}、state: ${rel(STATE_PATH)} の assets["${a.key}"].animations`);
    log(`\n[dry-run] 新規送信の見積り合計: ${cost} credits（${submit.length} actions × ${ANIM_CREDITS}、${batches.length} タスク）`);
    if (bal !== null) log(`[dry-run] 残高 ${fmtCredits(bal)}${bal < cost ? ` → 不足 ${fmtCredits(cost - bal)}。購入: ${PURCHASE_URL}` : ""}`);
    if (plan.rows.some((x) => x.action === "blocked")) process.exitCode = 1;
    return;
  }

  const runner = new AnimRunner(a, r.tid, lib.map, manifest, o);
  process.on("SIGINT", () => {
    console.error("\n中断しました。送信済みのタスクは Meshy 側で続行し、次回の anim で続きから待ちます"
      + (o.force.has("anim") ? "（--force anim は外して再実行。付けたままだと買い直し＝再課金）" : ""));
    process.exit(130);
  });
  if (cost) log(`\n新規送信 ${cost} credits（${submit.length} actions、${batches.length} タスク）、残高 ${fmtCredits(bal)}`
    + (o.maxCredits !== undefined ? `、上限 --max-credits ${o.maxCredits}` : ""));
  const jobs = [
    ...[...plan.resume.keys()].map((rec) => () => { log(`  ${runner.label(rec)} 実行中のタスクを再開: ${rec.task_id}`); return runner.waitAndSave(rec); }),
    ...[...plan.fetch.keys()].map((rec) => () => runner.save(rec, null)),
    ...batches.map((b) => () => runner.runBatch(b)),
  ];
  let next = 0;
  const worker = async () => {
    while (next < jobs.length) {
      const job = jobs[next++];
      try { await job(); } catch (e) { log(`  ${a.key} anim エラー: ${e.message}`); process.exitCode = 1; }
    }
  };
  await Promise.all(Array.from({ length: Math.min(o.concurrency, jobs.length) }, worker));

  const s = runner.stats;
  let after = null;
  if (s.submitted) { try { after = await getBalance(); } catch { /* 表示だけ */ } }
  const final = readJson(manifestPath(a), {});
  const missing = ids.filter((id) => final[String(id)]?.rig_task_id !== r.tid);
  log(`\n完了: 送信 ${s.submitted}、成功 ${s.success}、失敗 ${s.failed}、消費 ${fmtCredits(s.consumed)} credits、保存 ${s.saved}`
    + (after !== null && bal !== null ? `、残高 ${fmtCredits(bal)} → ${fmtCredits(after)}` : ""));
  if (runner.halted) log(`停止理由: ${runner.halted.split("\n")[0]}`);
  log(`manifest: ${rel(manifestPath(a))}（${ids.length - missing.length}/${ids.length} 個）`);
  if (missing.length) { log(`未完了: ${missing.join(",")}`); process.exitCode = 1; }
}

// rig タスクの結果に付く無料の歩き・走り（スキン付き GLB）。抽出ツールの試験用。控えは basic.json（state.json は書かない
// ＝ロック不要で run と並行してよい）
async function cmdAnimBasic(o) {
  if ([...o.force].some((f) => f !== "anim")) fail("anim-basic の --force は anim だけ（取り直し）");
  const a = rigHero(o);
  if (o.dry) DRY = true;
  const dir = animDir(a);
  const metaPath = path.join(dir, "basic.json");
  const meta = readJson(metaPath, {});
  const rigSt = getStage(a, "rig");
  const have = ([, name]) => {
    const f = meta.files?.[name];
    const file = path.join(dir, name);
    return meta.rig_task_id === rigSt?.task_id && f?.sha256 && fs.existsSync(file) && !badContent(file, "model") && sha256File(file) === f.sha256;
  };
  const todo = BASIC_ANIMS.filter((x) => o.force.has("anim") || !have(x));
  log(`${o.dry ? "[dry-run] " : ""}anim-basic ${a.key}  ${a.label}（無料）`);
  // 取るものが無ければ API は呼ばない（期限は state の記録で表示）
  const r = await rigInfo(a, { remote: hasApiKey() && (todo.length > 0 || o.dry) });
  log(`  ${rigText(r)}`);
  for (const x of BASIC_ANIMS) if (!todo.includes(x)) log(`  ${x[1]}: 済み → スキップ`);
  if (o.dry) {
    for (const [kind, name] of todo) log(`  ${name}: GET ${API}${ENDPOINTS.rig}/${r.tid} の result.basic_animations.${kind}_glb_url → ${rel(path.join(dir, name))}`);
    return;
  }
  if (todo.length) {
    if (r.gone) fail(`${rigText(r)}。基本アニメーションは rig の結果なので取得できません（作り直すなら node tools/meshy.mjs run heroes ${a.id} --force rig）`);
    if (r.task?.status !== "SUCCEEDED") fail(rigText(r));
  }
  fs.mkdirSync(dir, { recursive: true });
  const getFresh = async () => (await getTask("rig", r.tid)).json;
  const next = { rig_task_id: r.tid, files: { ...(meta.rig_task_id === r.tid ? meta.files : {}) } };
  for (const [kind, name] of todo) {
    const dest = path.join(dir, name);
    const label = `${a.key} basic ${kind}`;
    const res = await downloadFromTask(getFresh, r.task, (t) => t?.result?.basic_animations?.[`${kind}_glb_url`], dest, "model", label);
    if (res.missing) {
      log(`  ${label}: 出力に ${kind}_glb_url がありません（URL のあるキー: ${res.keys.join(", ") || "なし"}）`);
      process.exitCode = 1;
      continue;
    }
    next.files[name] = { bytes: res.size, sha256: sha256File(dest), saved_at: now() };
    log(`  ${label} 保存: ${rel(dest)}（${fmtBytes(res.size)}）`);
    writeJsonAtomic(metaPath, next);
  }
  for (const [, name] of BASIC_ANIMS) {
    const file = path.join(dir, name);
    if (badContent(file, "model")) continue;
    const info = glbInfo(file);
    const clips = glbAnimations(file) || [];
    log(`\n  ${rel(file)}: 骨 ${info?.joints.length ?? "?"} 本、三角形 ${info?.tris ?? "?"}、クリップ ${clips.length} 本`);
    printClips(clips, null, null);
  }
}

async function cmdAnimLibrary(o) {
  const lib = await loadLibrary([], { write: true });
  if (!lib.from) fail("ライブラリを取得できません（API キーが無くキャッシュも無い）");
  const q = (o.search || "").toLowerCase();
  const items = [...lib.map.values()].filter((x) => (!q || `${x.name} ${x.key}`.toLowerCase().includes(q)) && (!o.category || x.category === o.category));
  log(`ライブラリ: ${lib.from}（${items.length}/${lib.map.size} 件）`);
  table([["id", "名前", "category", "sub_category"], ...items.map((x) => [String(x.action_id), x.name, x.category, x.sub_category])]);
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
    for (const r of as.animations || []) {
      if (r.status === "SUCCEEDED" || ACTIVE.has(r.status)) consumed += num(r.credits_consumed) ?? 0;
      if (ACTIVE.has(r.status) || UNSURE.has(r.status)) active++;
      if (TERMINAL_FAIL.has(r.status)) failed++;
    }
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
  // anim: 今の rig で購入済み（成功）の action 数 + 実行中・不明のタスク数
  const animCell = (a) => {
    const rigTid = getStage(a, "rig")?.task_id;
    const recs = animRecords(a).filter((r) => r.rig_task_id === rigTid);
    const ok = new Set(recs.filter((r) => r.status === "SUCCEEDED").flatMap((r) => r.action_ids || []));
    const busy = recs.filter((r) => ACTIVE.has(r.status) || UNSURE.has(r.status)).length;
    return ok.size || busy ? `${ok.size}${busy ? ` +実行中/不明 ${busy}` : ""}` : "-";
  };
  log("\nheroes");
  const hrows = [["ID", "名前", "concept", ...CATS.heroes.stages, "anim", "配置", "ローカル"]];
  for (const a of MANIFEST.heroes) {
    hrows.push([a.id, a.label, fs.existsSync(conceptPath(a)) ? "あり" : "-", ...CATS.heroes.stages.map((s) => cellFor(a, s)), animCell(a), placedCell(a) || "-", localCell(a) || "-"]);
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
  node tools/meshy.mjs task <concept|model|rig|anim> <task_id>   タスクの JSON（署名付き URL は伏せる）

  アニメーション（docs/HERO_MOTION.md の抽出の入力。保存先 ${rel(ANIM_DIR)}/<id>/）
  node tools/meshy.mjs anim --rig <id> --actions 97,105,... [--dry-run] [--max-credits N] [--fps 24|25|30|60]
                                                                  既存の rig にライブラリのモーションを買って付ける（1 action ${ANIM_CREDITS}、
                                                                  10 個ずつ 1 タスク）→ batch_<先頭>-<個数>.glb と manifest.json
      --force anim       購入済み・送信結果不明の action も買い直す（実行中のタスクは買い直さない）
      --allow-partial    残高が足りなければ買える数だけ買う
  node tools/meshy.mjs anim-basic --rig <id> [--dry-run]         rig の結果に付く無料の歩き・走り → basic_{walking,running}.glb
  node tools/meshy.mjs anim-library [--search 文字列] [--category Fighting]   ライブラリの一覧（無料）

  取り込み: node tools/tripo.mjs import heroes <id>（rigged.fbx があれば rigged.glb より優先）
            node tools/tripo.mjs import props <kind>（source.json の front を使う）
  API キー: MESHY_API_KEY または ~/.config/meshy/api_key（リポジトリに置かない）  購入: ${PURCHASE_URL}`);
}

const [cmd, ...rest] = process.argv.slice(2);
const o = parseArgs(rest);
if (!cmd || cmd === "help" || o.help) { usage(); process.exit(cmd && cmd !== "help" && !o.help ? 1 : 0); }

try {
  if ((cmd === "run" || cmd === "anim") && !o.dry) lockState();
  switch (cmd) {
    case "anim":
      await cmdAnim(o);
      break;
    case "anim-basic":
      await cmdAnimBasic(o);
      break;
    case "anim-library":
      await cmdAnimLibrary(o);
      break;
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
      if (!stage || !o.pos[1]) fail("使い方: node tools/meshy.mjs task <concept|model|rig|anim> <task_id>");
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
