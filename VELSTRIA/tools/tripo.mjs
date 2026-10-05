#!/usr/bin/env node
// Tripo API v3 の小さなクライアント（依存なし。Node 20+ の標準 fetch）。
// ヒーロー本体・武器・スキンの 3D モデルを 生成 → リグ付け → ダウンロード し、Blender で正規化して App/Resources/Heroes へ取り込む。
// マニフェストは tools/tripo/assets.json（手書き）、進捗は tools/tripo/state.json（自動生成。task_id・状態・消費クレジット・
// ローカルパスのみで秘密は含まない）。ダウンロード物は build/tripo/（git 管理外）。
//
// 環境変数:
//   TRIPO_API_KEY      API キー（省略時 ~/.config/tripo/api_key）。リポジトリ・ログ・state.json には決して書かない
//   TRIPO_API_BASE     既定 https://openapi.tripo3d.ai/v3
//   TRIPO_CONCURRENCY  同時に進めるタスク数（既定 3。--concurrency でも指定可）
//   BLENDER            Blender 実行ファイル（既定 /Applications/Blender.app/Contents/MacOS/Blender）
//   SWIFTC             取り込みの検査ツール（tools/blender/verify_usdz.swift）をコンパイルする swiftc（既定 swiftc）
//   TRIPO_STATE_DIR    state.json（とロック）の置き場所（既定 tools/tripo/）
//   TRIPO_BUILD_DIR    ダウンロード物・取り込みレポート・検査ツールのバイナリ（既定 build/tripo/）
//   TRIPO_RESOURCES_DIR 取り込み先（既定 App/Resources/Heroes/）
//     この 3 つはリポジトリを汚さずに取り込みを試すためのもの（合成リグを置いた一時ディレクトリを指す）
//   HEROREF_BUILD_DIR  --concept-source fullbody の参照画像の置き場所（既定 build/heroref/。tools/heroref/fullbody.py と同じ）
//
// usage（VELSTRIA/ で実行）:
//   node tools/tripo.mjs balance                                    残高（無料 API）
//   node tools/tripo.mjs estimate [heroes|props|skins|all] [ids...] [--concept-source fullbody]
//                                                                   見積り（credits と USD、残高と比較）
//   node tools/tripo.mjs run heroes [H001 ...|--all] [--until concept|model|rigcheck|rig] [--faces N]
//       [--concept-source fullbody]  concept を Tripo の text-to-image ではなくローカルの全身画像
//       （build/heroref/<ID>/fullbody.png）の写しにする（0 credits）。model はその画像を POST /files で上げた file_token
//       から作る。前回の concept（Tripo 製か、sha256 の違うローカル画像）は後段ごと履歴へ移して作り直す。同じ画像なら何もしない
//   node tools/tripo.mjs run props  [<kind> ...|--all] [--include-optional] [--faces N] [--replace-meshy]
//   node tools/tripo.mjs run skins  [<cosmeticID> ...|--all] [--style-image]
//       共通: [--dry-run] [--max-credits N] [--force <stage>[,<stage>]|all] [--concurrency N] [--allow-partial]
//   node tools/tripo.mjs status                                     全アセット × 段階の状態・消費・ローカルファイル
//   node tools/tripo.mjs task <task_id>                             タスクの生 JSON
//   node tools/tripo.mjs import [heroes|props|skins] [ids...|--all] [--dry-run] [--texture-size PX] [--max-faces N]
//       ヒーロー・スキン: [--height M] [--forward auto|+x|-x|+z|-z]  Prop: [--length M] [--axis auto|up|pca|vertical]
//       tools/blender/normalize_{hero,prop}.py で一時ファイルへ正規化 → tools/blender/verify_usdz.swift で検査 → 合格したものだけ
//       App/Resources/Heroes へ rename で置き換える（不合格なら既存のファイルはそのまま）。Prop の --grip / axis / front /
//       yaw / side は assets.json の値（tools/meshy.mjs が置いた model.glb は同じフォルダの source.json の front（+z）と
//       assets.json の props[].meshy の上書きを重ねる）。ヒーロー・スキンは build/tripo/<cat>/<id>/rigged.fbx があれば rigged.glb より優先。
//       bodyWorn の Prop（stoneFist・azureClaw）は実行時に付けないので取り込まない
//
// --dry-run は送信予定のリクエスト本文と出力先を表示するだけ（有料 API を呼ばず、state.json も変更しない）。
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MANIFEST_PATH = path.join(ROOT, "tools", "tripo", "assets.json");
const envDir = (k, def) => (process.env[k] ? path.resolve(process.env[k]) : def);
const STATE_PATH = path.join(envDir("TRIPO_STATE_DIR", path.join(ROOT, "tools", "tripo")), "state.json");
const BUILD_DIR = envDir("TRIPO_BUILD_DIR", path.join(ROOT, "build", "tripo"));
const RES_DIR = envDir("TRIPO_RESOURCES_DIR", path.join(ROOT, "App", "Resources", "Heroes"));
const BLENDER_SCRIPTS = path.join(ROOT, "tools", "blender");
const VERIFY_SRC = path.join(BLENDER_SCRIPTS, "verify_usdz.swift");
const VERIFY_BIN = path.join(BUILD_DIR, "verify_usdz");
const SWIFTC = process.env.SWIFTC || "swiftc";
const API = (process.env.TRIPO_API_BASE || "https://openapi.tripo3d.ai/v3").replace(/\/+$/, "");
const BLENDER = process.env.BLENDER || "/Applications/Blender.app/Contents/MacOS/Blender";
const KEY_FILE = path.join(os.homedir(), ".config", "tripo", "api_key");
const PURCHASE_URL = "https://platform.tripo3d.ai/";
const HEROREF_DIR = envDir("HEROREF_BUILD_DIR", path.join(ROOT, "build", "heroref"));

// --concept-source: concept 段階を Tripo の text-to-image ではなくローカルの画像で置き換える（ヒーローのみ）。
// file は採用版の画像、tagFile は fullbody.py select が書く採用候補のタグ（記録用）
const CONCEPT_SOURCES = {
  fullbody: {
    file: (a) => path.join(HEROREF_DIR, a.id, "fullbody.png"),
    tagFile: (a) => path.join(HEROREF_DIR, a.id, "fullbody.source"),
    howTo: (a) => `python3 tools/heroref/fullbody.py generate ${a.id} --tag t1 && python3 tools/heroref/fullbody.py select ${a.id} t1`,
  },
};
const UPLOAD_IMAGE_MAX = 20 << 20; // POST /files の画像は 20 MB まで（files.md）
const MIN_IMAGE_PX = 256; // image-to-model の推奨最小解像度
// ローカル画像を前段に持つ段階の input（送信直前に POST /files で得た file_token に差し替える）
const UPLOAD_PLACEHOLDER = "<concept.png を POST /files でアップロードした file_token>";
// 別の API キー（差し替え前のキーなど）で作ったタスクは今のキーの GET /tasks からは見えず、存在しないタスクと同じ
// HTTP 404 / code 2001 になる（2026-10 に確認）。区別できないので、どちらの可能性も伝える
const NOT_FOUND_WHY = "HTTP 404 / code 2001。別の API キー（差し替え前のキーなど）で作ったタスクは今のキーからは見えません";

const IMAGE_MODEL = "seedream_v5";
const MODEL_P1 = "P1-20260311";
const TEXTURE_MODEL = "v3.5-20260815";
const RIG_MODEL = "v1.0-20240301";
const IMAGE_SIZE = "2048x2048";

// 見積り用クレジット（1 credit = $0.01）。developers.tripo3d.com/en/pricing（2026-10 時点）の定価。
// 実際の消費は各タスクの credits_consumed を state.json に記録する（VIP 割引などで下がることがある）。
// 実行中のタスクはこの値で数えるので、--max-credits を守るには定価（上振れ側）で見積る。
const CREDITS = {
  concept: 5, // text-to-image seedream_v5（1K/2K/4K とも 5）
  model: 60, // image-to-model P1: 標準テクスチャ込み 50 + HD テクスチャ（texture_quality detailed）+10
  rigcheck: 0, // rig-check は無料
  rig: 25, // Auto Rig
  texture: 20, // models/texture HD（detailed）
  retarget: 10, // 1 アニメーションあたり（未使用）
  convert: 5, // 形式変換 Basic（未使用）
};
const USD_PER_CREDIT = 0.01;

const STAGES = { heroes: ["concept", "model", "rigcheck", "rig"], props: ["concept", "model"], skins: ["texture", "rig"] };
const ENDPOINTS = {
  concept: "/generation/text-to-image",
  model: "/generation/image-to-model",
  rigcheck: "/animations/rig-check",
  rig: "/animations/rig",
  texture: "/models/texture",
};
// 同時実行数はカテゴリ別・アカウント単位（rate-limits.md の既定値。画像生成は 1 本ずつ）
const CATEGORY = { concept: "image", model: "p-series", rigcheck: "animation", rig: "animation", texture: "processing" };
const CATEGORY_LIMIT = { image: 1, "p-series": 5, animation: 10, processing: 5 };
const DEFAULT_FACES = { heroes: 10000, props: 2500 };
const FACE_RANGE = [50, 20000]; // P1-20260311
// 段階ごとに保存するファイル（[出力の種類, ファイル名, 必須]）
const STAGE_FILES = {
  concept: [["image", "concept.png", true]],
  model: [["model", "model.glb", true], ["preview", "preview.png", false]],
  rigcheck: [],
  rig: [["model", "rigged.glb", true]],
  texture: [["model", "textured.glb", true], ["preview", "preview.png", false]],
};
const ACTIVE = new Set(["queued", "running"]);
const UNSURE = new Set(["submitting", "unknown"]);
const TERMINAL_FAIL = new Set(["failed", "cancelled", "banned", "expired"]);
// ポーリングを再開できる段階: 実行中、または task_id はあるが GET /tasks が 404 だった「unknown」（作成直後の不整合や
// 一時的な 404 のことがあるので、--force で再課金する前に次回の run で問い合わせ直す）
const resumable = (st) => !!(st?.task_id && (ACTIVE.has(st.status) || st.status === "unknown"));
const NOT_FOUND_GRACE_MS = 60_000; // 送信からこの時間内の 404 は待って問い合わせ直す
const NOT_FOUND_MIN_TRIES = 3; // 再開時も最低この回数は 404 を確かめてから諦める
const POLL_INTERVAL_MS = 5000;
const POLL_TIMEOUT_MS = 45 * 60 * 1000;
const MAX_ATTEMPTS = 6; // 通信エラー・5xx（1+5 回）
const MAX_ATTEMPTS_429 = 12;

let DRY = false;
let apiKeyCache = null;

function fail(msg) {
  console.error(`error: ${scrub(msg)}`);
  process.exit(1);
}

function log(msg) {
  console.log(scrub(msg));
}

// 念のため、出力に API キーが紛れ込まないようにする
function scrub(s) {
  const t = String(s);
  return apiKeyCache ? t.split(apiKeyCache).join("***") : t;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const now = () => new Date().toISOString();
// リポジトリ内は相対、外（TRIPO_*_DIR の一時ディレクトリなど）は絶対パスで表示する
const rel = (p) => {
  const r = path.relative(ROOT, p);
  return r.startsWith("..") || path.isAbsolute(r) ? p : r;
};
const usd = (c) => `$${(c * USD_PER_CREDIT).toFixed(2)}`;
const num = (v) => (v === null || v === undefined || v === "" || Number.isNaN(Number(v)) ? null : Number(v));
const fmtCredits = (c) => (c === null || c === undefined ? "-" : Number.isInteger(c) ? String(c) : c.toFixed(2));

function elapsed(t0) {
  const s = Math.round((Date.now() - t0) / 1000);
  return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m${String(s % 60).padStart(2, "0")}s`;
}

// 全角文字を 2 桁として数えた表示幅
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

const VALUE_FLAGS = new Set(["until", "faces", "max-credits", "force", "concurrency", "height", "texture-size", "max-faces", "forward", "length", "axis",
  "concept-source"]);
const BOOL_FLAGS = new Set(["all", "dry-run", "include-optional", "style-image", "no-style-image", "allow-partial", "replace-meshy", "help"]);

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
      fail(`不明なオプション: --${k}（node tools/tripo.mjs で使い方を表示）`);
    }
  }
  const intFlag = (k, min, max) => {
    if (flags[k] === undefined) return undefined;
    const n = Number(flags[k]);
    if (!Number.isInteger(n) || n < min || n > max) fail(`--${k} は ${min}〜${max} の整数: ${flags[k]}`);
    return n;
  };
  const posFlag = (k) => {
    if (flags[k] === undefined) return undefined;
    const n = Number(flags[k]);
    if (!(n > 0)) fail(`--${k} は正の数: ${flags[k]}`);
    return n;
  };
  const choiceFlag = (k, choices) => {
    if (flags[k] !== undefined && !choices.includes(flags[k])) fail(`--${k} は ${choices.join(" | ")} のいずれか: ${flags[k]}`);
    return flags[k];
  };
  if (flags["style-image"] && flags["no-style-image"]) fail("--style-image と --no-style-image は同時に指定できません");
  const envConc = process.env.TRIPO_CONCURRENCY ? Number(process.env.TRIPO_CONCURRENCY) : 3;
  return {
    pos,
    all: !!flags.all,
    dry: !!flags["dry-run"],
    includeOptional: !!flags["include-optional"],
    // スキンの style_image は既定で送らない（ヒーロー既定配色のコンセプト画像が色替えを打ち消す方向に効くため）。
    // --style-image で送る（試験用）。--no-style-image は旧オプション（既定と同じ）
    noStyleImage: !flags["style-image"],
    styleImageFlag: flags["style-image"] ? "--style-image" : flags["no-style-image"] ? "--no-style-image" : null,
    allowPartial: !!flags["allow-partial"],
    replaceMeshy: !!flags["replace-meshy"],
    help: !!flags.help,
    until: flags.until,
    faces: intFlag("faces", FACE_RANGE[0], FACE_RANGE[1]),
    maxCredits: flags["max-credits"] === undefined ? undefined : (() => {
      const n = Number(flags["max-credits"]);
      if (!(n >= 0)) fail(`--max-credits は 0 以上の数: ${flags["max-credits"]}`);
      return n;
    })(),
    force: new Set(flags.force || []),
    conceptSource: choiceFlag("concept-source", Object.keys(CONCEPT_SOURCES)),
    concurrency: intFlag("concurrency", 1, 10) ?? (Number.isInteger(envConc) && envConc >= 1 ? Math.min(envConc, 10) : 3),
    importOpts: {
      height: posFlag("height"),
      textureSize: intFlag("texture-size", 16, 8192),
      maxFaces: intFlag("max-faces", 100, 1000000),
      forward: choiceFlag("forward", ["auto", "+x", "-x", "+z", "-z"]),
      length: posFlag("length"),
      axis: choiceFlag("axis", ["auto", "up", "pca", "vertical"]),
    },
  };
}

// MARK: - API

class TripoError extends Error {
  constructor(method, p, status, json, text) {
    const code = json?.code;
    const msg = json?.message || (text ? text.slice(0, 200) : "");
    super(`${method} ${p} → HTTP ${status}${code !== undefined ? ` code ${code}` : ""}: ${msg}${json?.suggestion ? `（${json.suggestion}）` : ""}`
      + `${json?.request_id ? ` [request_id ${json.request_id}]` : ""}`);
    this.status = status;
    this.code = code;
    this.json = json;
  }
  get insufficientCredits() {
    return this.code === 2010 || (this.status === 403 && /credit/i.test(this.json?.message || ""));
  }
}

// GET /tasks/{id} の「見つからない」（存在しない・作成直後で未反映・別の API キーで作ったタスク）
const taskNotFound = (e) => e instanceof TripoError && (e.status === 404 || e.code === 2001);

function apiKey() {
  if (apiKeyCache) return apiKeyCache;
  let k = (process.env.TRIPO_API_KEY || "").trim();
  if (!k && fs.existsSync(KEY_FILE)) k = fs.readFileSync(KEY_FILE, "utf8").trim();
  if (!k) fail(`API キーがありません: TRIPO_API_KEY を設定するか ${KEY_FILE} に保存してください（リポジトリには置かない）`);
  apiKeyCache = k;
  return k;
}

const hasApiKey = () => !!(process.env.TRIPO_API_KEY || "").trim() || fs.existsSync(KEY_FILE);
const backoffSec = (attempt) => Math.min(32, 2 ** (attempt - 1));

function retryAfterSec(res) {
  const ra = Number(res.headers.get("retry-after"));
  if (ra > 0) return Math.min(ra, 120);
  const reset = Number(res.headers.get("x-ratelimit-reset"));
  if (reset > 0) return Math.min(Math.max(1, Math.ceil(reset - Date.now() / 1000)), 120);
  return null;
}

// 通信エラー・HTTP 429・5xx は指数バックオフで再試行する（4xx の業務エラーは再試行しない）。
// paid（タスクを作る有料 POST）は 429 だけ再試行する: 429（code 1007 / 2000）はタスクが作られていないことが保証されるが、
// タイムアウト・通信エラー・5xx はサーバ側でタスク作成と課金が済んでいることがあり、再送すると二重課金になる。
async function api(method, p, body, { form, paid = false } = {}) {
  for (let attempt = 1; ; attempt++) {
    let res;
    let text;
    try {
      const headers = { Authorization: `Bearer ${apiKey()}` };
      let payload;
      if (form) payload = form;
      else if (body !== undefined) { headers["Content-Type"] = "application/json"; payload = JSON.stringify(body); }
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
    const limit = res.status === 429 ? MAX_ATTEMPTS_429 : (paid ? 1 : MAX_ATTEMPTS);
    if ((res.status === 429 || res.status >= 500) && attempt < limit) {
      const wait = (res.status === 429 && retryAfterSec(res)) || backoffSec(attempt);
      const what = res.status === 429 ? (json?.code === 2000 ? "同時実行数の上限" : "レート制限") : `HTTP ${res.status} `;
      console.error(`  ${what}のため ${wait}s 後に再試行（${attempt}/${limit - 1}）: ${method} ${p}`);
      await sleep(wait * 1000);
      continue;
    }
    if (!res.ok || !json || json.code !== 0) throw new TripoError(method, p, res.status, json, text);
    return json.data;
  }
}

async function getBalance() {
  const d = await api("GET", "/account/balance");
  return { balance: num(d?.balance) ?? 0, frozen: num(d?.frozen) ?? 0 };
}

function shortageText(need, bal) {
  return [
    `クレジット不足: 残高 ${fmtCredits(bal.balance)}（凍結 ${fmtCredits(bal.frozen)}）、必要 約 ${fmtCredits(need)} credits（${usd(need)}）、`
      + `不足 ${fmtCredits(Math.max(0, need - bal.balance))} credits`,
    `  購入: ${PURCHASE_URL}（開発者コンソールの Billing。API キーも同じコンソールの API Keys で管理）`,
  ].join("\n");
}

async function uploadFile(file, buf = fs.readFileSync(file)) {
  const form = new FormData();
  form.append("file", new Blob([buf], { type: sniffMime(buf) }), path.basename(file));
  const data = await api("POST", "/files", undefined, { form });
  if (!data?.file_token) throw new Error(`アップロードに失敗（file_token なし）: ${rel(file)}`);
  return data.file_token;
}

// MARK: - 出力 URL・ダウンロード

const URL_KEYS = {
  image: ["generated_image_url", "image_url", "generated_image", "image", "images", "url"],
  model: ["pbr_model_url", "model_url", "pbr_model", "model", "base_model_url", "base_model"],
  preview: ["rendered_image_url", "rendered_image", "preview_image_url", "preview_url"],
};
const URL_EXT = { image: /\.(png|jpe?g|webp)$/i, model: /\.glb$/i };

function urlOf(v) {
  if (typeof v === "string") return /^https?:\/\//.test(v) ? v : null;
  if (Array.isArray(v)) { for (const x of v) { const u = urlOf(x); if (u) return u; } return null; }
  if (v && typeof v === "object") return urlOf(v.url) || urlOf(v.download_url);
  return null;
}

function outputUrl(output, kind) {
  if (!output || typeof output !== "object") return null;
  for (const k of URL_KEYS[kind]) { const u = urlOf(output[k]); if (u) return u; }
  if (!URL_EXT[kind]) return null;
  // 既知のキーが無ければ拡張子で探す（プレビューは誤認を避けて探さない）
  for (const v of Object.values(output)) {
    const u = urlOf(v);
    if (!u) continue;
    try { if (URL_EXT[kind].test(new URL(u).pathname)) return u; } catch { /* 無視 */ }
  }
  return null;
}

function sniffMime(buf) {
  if (buf.length >= 4 && buf.toString("latin1", 0, 4) === "glTF") return "model/gltf-binary";
  if (buf.length >= 8 && buf[0] === 0x89 && buf.toString("latin1", 1, 4) === "PNG") return "image/png";
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return "image/jpeg";
  if (buf.length >= 12 && buf.toString("latin1", 0, 4) === "RIFF" && buf.toString("latin1", 8, 12) === "WEBP") return "image/webp";
  return "application/octet-stream";
}

// PNG の幅・高さ（IHDR）。PNG でなければ null
function pngSize(buf) {
  if (sniffMime(buf) !== "image/png" || buf.length < 24 || buf.toString("latin1", 12, 16) !== "IHDR") return null;
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
}

const sha256Of = (buf) => crypto.createHash("sha256").update(buf).digest("hex");
const sha256File = (file) => sha256Of(fs.readFileSync(file));
const shortSha = (h) => (h ? `${h.slice(0, 12)}…` : "?");

function readHead(file, n = 16) {
  const fd = fs.openSync(file, "r");
  try {
    const buf = Buffer.alloc(n);
    const read = fs.readSync(fd, buf, 0, n, 0);
    return buf.subarray(0, read);
  } finally { fs.closeSync(fd); }
}

// 中身の検査（GLB は 'glTF'、画像は PNG/JPEG/WebP）。問題なければ null、あれば理由
function badContent(file, kind) {
  if (!fs.existsSync(file)) return "ファイルがありません";
  if (fs.statSync(file).size === 0) return "空のファイル";
  const mime = sniffMime(readHead(file));
  if (kind === "model") return mime === "model/gltf-binary" ? null : "GLB ではありません（先頭が glTF でない）";
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
      const mime = sniffMime(readHead(dest));
      if (dest.endsWith(".png") && mime !== "image/png") console.error(`  注意: ${rel(dest)} の中身は ${mime} です`);
      return fs.statSync(dest).size;
    } catch (e) {
      fs.rmSync(tmp, { force: true });
      const retryable = !e.permanent && (!(e instanceof HttpStatusError) || e.status === 429 || e.status >= 500);
      if (!retryable || attempt >= 5) throw new Error(`ダウンロード失敗 ${rel(dest)}: ${e.cause?.code || e.message}`);
      await sleep(backoffSec(attempt) * 1000);
    }
  }
}

const fmtBytes = (n) => (n >= 1 << 20 ? `${(n / (1 << 20)).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`);

// MARK: - マニフェスト

function loadManifest() {
  let m;
  try { m = JSON.parse(fs.readFileSync(MANIFEST_PATH, "utf8")); } catch (e) { fail(`マニフェストを読めません: ${rel(MANIFEST_PATH)}: ${e.message}`); }
  for (const k of ["style", "heroes", "props", "skins"]) if (!m[k]) fail(`マニフェストに ${k} がありません`);
  const heroes = m.heroes.map((e) => ({ cat: "heroes", id: e.id, key: `heroes/${e.id}`, entry: e, label: e.name_ja, optional: false }));
  const props = m.props.map((e) => ({ cat: "props", id: e.kind, key: `props/${e.kind}`, entry: e, label: (e.heroes || []).join(","), optional: !!e.optional }));
  const skins = m.skins.map((e) => ({ cat: "skins", id: e.cosmeticID, key: `skins/${e.cosmeticID}`, entry: e, label: `${e.heroID} ${e.name_ja || ""}`.trim(), optional: false }));
  for (const s of skins) if (!heroes.some((h) => h.id === s.entry.heroID)) fail(`スキン ${s.id} のヒーロー ${s.entry.heroID} がマニフェストにありません`);
  return { style: m.style, assets: { heroes, props, skins } };
}

const manifest = loadManifest();
const heroAsset = (id) => manifest.assets.heroes.find((h) => h.id === id);
const assetDir = (a) => path.join(BUILD_DIR, a.cat, a.id);

function findAsset(cat, id) {
  const list = manifest.assets[cat];
  return list.find((a) => a.id === id) || list.find((a) => a.id.toLowerCase() === id.toLowerCase());
}

// ids 指定 → その資産、--all（または defaultAll）→ 全件（任意の Prop は --include-optional のときだけ）
function select(cat, ids, o, defaultAll = false) {
  if (ids.length) {
    const found = ids.map((id) => findAsset(cat, id)
      || fail(`${cat} に ${id} はありません（候補: ${manifest.assets[cat].map((a) => a.id).join(" ")}）`));
    // findAsset はマニフェストの同じオブジェクトを返すので、重複や大文字小文字違いの ID はここで 1 件にまとまる
    // （同じ段階を 2 本並行で送信＝二重課金するのを防ぐ）
    return [...new Set(found)];
  }
  if (!o.all && !defaultAll) fail(`対象を指定してください（ID を並べるか --all）。候補: ${manifest.assets[cat].map((a) => a.id).join(" ")}`);
  // bodyWorn（本体に含める籠手・爪）は実行時に Prop として付けないので、ID を名指ししたときだけ対象にする
  return manifest.assets[cat].filter((a) => (!a.optional || o.includeOptional) && !a.entry.bodyWorn);
}

function promptFor(a) {
  const s = manifest.style;
  const join = (parts, negatives) => {
    const p = parts.filter(Boolean).join(" ");
    const n = negatives.filter(Boolean).join(", ");
    return n ? `${p} --no ${n}` : p;
  };
  if (a.cat === "heroes") return join([s.bodyPrefix, a.entry.prompt, s.bodySuffix], [s.bodyNegative, a.entry.negative]);
  if (a.cat === "props") return join([s.propPrefix, a.entry.prompt, s.propSuffix], [s.propNegative, a.entry.negative]);
  return [s.skinPrefix, a.entry.prompt, s.skinSuffix].filter(Boolean).join(" ");
}

// MARK: - 状態（state.json）

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

// run / import は state.json 全体を書き戻すので、並行するもう 1 本が相手の task_id を消してしまう → 排他ロック
const LOCK_PATH = `${STATE_PATH}.lock`;
function lockState() {
  fs.mkdirSync(path.dirname(LOCK_PATH), { recursive: true }); // TRIPO_STATE_DIR が新しいディレクトリのとき
  for (let i = 0; i < 2; i++) {
    let fd;
    try {
      fd = fs.openSync(LOCK_PATH, "wx");
    } catch (e) {
      if (e.code !== "EEXIST") throw e;
      let pid = NaN;
      try { pid = Number.parseInt(fs.readFileSync(LOCK_PATH, "utf8"), 10); } catch { /* 消えた・読めない → 取り直す */ }
      let alive = false;
      if (Number.isInteger(pid) && pid > 0) {
        try { process.kill(pid, 0); alive = true; } catch (k) { alive = k.code === "EPERM"; }
      } else {
        // 作成直後で PID をまだ書いていない可能性 → 新しいロックは生きているとみなす
        try { alive = Date.now() - fs.statSync(LOCK_PATH).mtimeMs < 10_000; } catch { /* 消えた → 取り直す */ }
      }
      if (alive) fail(`別の tools/tripo.mjs（PID ${Number.isInteger(pid) ? pid : "?"}）が state.json を更新中です。終わってから実行してください`);
      fs.rmSync(LOCK_PATH, { force: true }); // 落ちたプロセスの残骸
      continue;
    }
    fs.writeSync(fd, String(process.pid));
    fs.closeSync(fd);
    process.on("exit", () => {
      try { if (fs.readFileSync(LOCK_PATH, "utf8") === String(process.pid)) fs.unlinkSync(LOCK_PATH); } catch { /* 無視 */ }
    });
    state = loadState(); // ロック前に読んだ内容は他プロセスの最後の書き込みより古いことがある
    return;
  }
  fail(`${rel(LOCK_PATH)} を取得できません`);
}

// 一時ファイルに書いてから rename（途中で落ちても壊れない）
function saveState() {
  if (DRY) throw new Error("内部エラー: dry-run 中に state.json を書こうとしました");
  state.note = "tools/tripo.mjs が自動生成。task_id・状態・消費クレジット・ローカルパスのみ（秘密情報なし）";
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

// --force: 指定段階以降を履歴へ移す（後段は前段の task_id に依存するため）
function archiveFrom(a, stage) {
  const as = state.assets[a.key];
  if (!as?.stages) return;
  const list = STAGES[a.cat];
  let changed = false;
  for (const s of list.slice(list.indexOf(stage))) {
    const st = as.stages[s];
    if (!st) continue;
    if (ACTIVE.has(st.status)) log(`  ${tag(a, s)} 実行中のタスク ${st.task_id} を破棄して作り直します（そのタスクの課金は発生し得ます）`);
    (as.history ||= []).push({ stage: s, archived_at: now(), ...st });
    delete as.stages[s];
    changed = true;
  }
  if (changed) saveState();
}

// 送信内容の控え（署名付き URL は残さない）
function redactBody(body) {
  const b = structuredClone(body);
  if (b.texture_prompt?.style_image?.url) b.texture_prompt.style_image.url = "<コンセプト画像の URL>";
  return b;
}

// 出力の控え（URL は期限付きなので保存せず、キー名とスカラー値だけ残す）
function summarizeOutput(output) {
  if (!output || typeof output !== "object") return null;
  const out = {};
  const urls = [];
  for (const [k, v] of Object.entries(output)) {
    if (urlOf(v)) urls.push(k);
    else if (v === null || ["string", "number", "boolean"].includes(typeof v)) out[k] = v;
  }
  if (urls.length) out.url_keys = urls;
  return out;
}

const tag = (a, stage) => `${a.key} ${stage}`;

// MARK: - ローカルのコンセプト（--concept-source）

// 参照画像の検査と sha256。計画（見積り・置き換えの判定）と実行で同じ値を使うよう 1 回だけ読み、
// 写すときに読み直した内容の sha256 と照合する（計画の後で差し替えられたら写さない）
const conceptSrcCache = new Map();
function conceptSource(a, o) {
  if (!o.conceptSource || a.cat !== "heroes") return null;
  if (conceptSrcCache.has(a.key)) return conceptSrcCache.get(a.key);
  const def = CONCEPT_SOURCES[o.conceptSource];
  const src = { kind: o.conceptSource, path: def.file(a) };
  try {
    const t = fs.readFileSync(def.tagFile(a), "utf8").trim();
    if (t) src.tag = t;
  } catch { /* select を通さず置いた画像 */ }
  src.error = (() => {
    if (!fs.existsSync(src.path)) return "ファイルがありません";
    const size = fs.statSync(src.path).size;
    if (size === 0) return "空のファイル";
    if (size > UPLOAD_IMAGE_MAX) return `${fmtBytes(size)}（POST /files の画像は 20 MB まで）`;
    const buf = fs.readFileSync(src.path);
    const dim = pngSize(buf);
    // 写し先は concept.png なので PNG に限る（fullbody.py は PNG だけを採用する）
    if (!dim) return `PNG ではありません（${sniffMime(buf)}）`;
    if (dim.width < MIN_IMAGE_PX || dim.height < MIN_IMAGE_PX) return `${dim.width}x${dim.height}（${MIN_IMAGE_PX}px 以上が必要）`;
    Object.assign(src, dim, { sha256: sha256Of(buf) });
    return null;
  })();
  if (!src.error) delete src.error;
  conceptSrcCache.set(a.key, src);
  return src;
}

// 既存の concept がこの参照画像の写しか（同じ種類・同じ sha256 なら後段も含めて作り直さない）
function localConceptPlan(a, o) {
  const src = conceptSource(a, o);
  if (!src) return null;
  const st = getStage(a, "concept");
  const same = !src.error && st?.status === "success" && !!st.local && st.source?.kind === src.kind && st.source?.sha256 === src.sha256;
  return { src, same };
}

// 履歴へ移し始める段階の番号（--force の指定と、concept をローカル画像で置き換えるとき 0）
function effectiveForceIndex(a, o) {
  const lc = localConceptPlan(a, o);
  return lc && !lc.same ? 0 : forcedIndex(a.cat, o.force);
}

// 前段がローカル画像の concept なら、アップロードする concept.png のパス（それ以外は null = task_id を渡す）。
// --concept-source を付けない run でも、state の concept が local ならその写しを使い続ける。
// planned（dry-run）に concept があれば Tripo で作り直す予定なのでローカルではない
function localInputFile(a, stage, o, planned = null) {
  const src = sourceOf(a, stage);
  if (!src || src.stage !== "concept") return null;
  const local = conceptSource(src.asset, o) ? true
    : planned?.has(`${src.asset.key}:concept`) ? false
      : !!getStage(src.asset, "concept")?.local;
  return local ? path.join(assetDir(src.asset), "concept.png") : null;
}

const describeSource = (s) => [s.kind, s.tag, s.width && `${s.width}x${s.height}`, `sha256 ${shortSha(s.sha256)}`].filter(Boolean).join("、");

// MARK: - リクエスト本文

function stagesFor(cat, until) {
  const list = STAGES[cat];
  if (!until) return list;
  const i = list.indexOf(until);
  if (i < 0) fail(`${cat} の --until は ${list.join(" | ")} のいずれか: ${until}`);
  return list.slice(0, i + 1);
}

function validateForce(cat, force) {
  for (const f of force) if (f !== "all" && !STAGES[cat].includes(f)) fail(`${cat} の --force は ${STAGES[cat].join(" | ")} | all: ${f}`);
}

function forcedIndex(cat, force) {
  if (force.has("all")) return 0;
  let idx = Infinity;
  for (const f of force) { const i = STAGES[cat].indexOf(f); if (i >= 0) idx = Math.min(idx, i); }
  return idx;
}

// 前段（入力に使う task_id を持つ段階）
function sourceOf(a, stage) {
  if (a.cat === "skins") return stage === "texture" ? { asset: heroAsset(a.entry.heroID), stage: "model" } : { asset: a, stage: "texture" };
  if (stage === "concept") return null;
  if (stage === "model") return { asset: a, stage: "concept" };
  return { asset: a, stage: "model" }; // rigcheck / rig はモデルのタスク
}

function inputFor(a, stage, planned) {
  const src = sourceOf(a, stage);
  if (!src) return null;
  const placeholder = `<${src.asset.key} ${src.stage} の task_id>`;
  if (planned?.has(`${src.asset.key}:${src.stage}`)) return placeholder;
  const st = getStage(src.asset, src.stage);
  if (st?.status === "success" && st.task_id) return st.task_id;
  return planned ? placeholder : null;
}

function buildBody(a, stage, input, o, styleImage) {
  switch (stage) {
    case "concept": {
      const body = { prompt: promptFor(a), model: IMAGE_MODEL, size: IMAGE_SIZE, output_format: "png", watermark: false };
      if (a.cat === "heroes") body.template = "t_pose";
      return body;
    }
    case "model": {
      const body = {
        input, model: MODEL_P1, face_limit: o.faces ?? DEFAULT_FACES[a.cat],
        texture: true, pbr: true, texture_quality: "detailed", texture_version: TEXTURE_MODEL, delight: true,
        texture_alignment: "original_image",
      };
      if (a.cat === "props") body.orientation = "align_image";
      return body;
    }
    case "rigcheck":
      return { input };
    case "rig":
      return { input, model: RIG_MODEL, rig_type: "biped", spec: "mixamo", out_format: "glb" };
    case "texture": {
      // 色替えなので配置は形状優先（original_image だと既定配色の参照画像に引っ張られやすい）
      const texturePrompt = { text: promptFor(a) };
      if (styleImage) texturePrompt.style_image = styleImage;
      return { input, model: TEXTURE_MODEL, texture_prompt: texturePrompt, pbr: true, texture_quality: "detailed", texture_alignment: "geometry", delight: true };
    }
    default:
      return fail(`未知の段階: ${stage}`);
  }
}

// スキンの参照画像（--style-image のときだけ）: ヒーローのコンセプト画像（タスクを取り直して新しい URL、無ければローカルをアップロード）
async function styleImageFor(a, o) {
  if (o.noStyleImage) return null;
  const hero = heroAsset(a.entry.heroID);
  const st = getStage(hero, "concept");
  if (st?.status === "success" && st.task_id) {
    try {
      const t = await api("GET", `/tasks/${encodeURIComponent(st.task_id)}`);
      const u = t?.status === "success" ? outputUrl(t.output, "image") : null;
      if (u) return { url: u };
    } catch (e) {
      console.error(`  ${tag(a, "texture")} コンセプト画像の URL を取得できません: ${scrub(e.message)}`
        + (taskNotFound(e) ? `（${NOT_FOUND_WHY}）。ローカルの concept.png を使います` : ""));
    }
  }
  const local = path.join(assetDir(hero), "concept.png");
  if (!badContent(local, "image")) {
    log(`  ${tag(a, "texture")} 参照画像として ${rel(local)} をアップロードします`);
    return { file_token: await uploadFile(local) };
  }
  log(`  ${tag(a, "texture")} 参照画像（${hero.key} のコンセプト）が無いため style_image なしで送信します`);
  return null;
}

// MARK: - 実行

// action: submit（有料 POST）/ local（ローカル画像を写す、0 credits）/ missing（参照画像が無い・不正）/ done / resume / blocked。
// why: 既存の結果を履歴へ移す理由（force = --force、concept = concept をローカル画像で置き換えるため）
function planStages(a, o) {
  const list = stagesFor(a.cat, o.until);
  const lc = localConceptPlan(a, o);
  const ffi = forcedIndex(a.cat, o.force);
  const fi = effectiveForceIndex(a, o);
  return list.map((stage, i) => {
    const st = getStage(a, stage);
    const why = i >= ffi ? "force" : "concept";
    if (lc && stage === "concept") {
      if (lc.src.error) return { stage, action: "missing", st, src: lc.src };
      if (i >= fi) return { stage, action: "local", st, src: lc.src, forced: !!st, why };
      return { stage, action: "done", st };
    }
    if (i >= fi) return { stage, action: "submit", st, forced: !!st, why };
    if (!st) return { stage, action: "submit" };
    if (st.status === "success") return { stage, action: "done", st };
    if (resumable(st)) return { stage, action: "resume", st };
    if (UNSURE.has(st.status)) return { stage, action: "blocked", st };
    return { stage, action: "submit", st };
  });
}

// ローカル画像の concept（local）は Tripo に送らないので 0
const planCost = (plan) => plan.reduce((sum, p) => sum + (p.action === "submit" ? CREDITS[p.stage] : 0), 0);

function skinPrereq(a) {
  const hero = heroAsset(a.entry.heroID);
  const st = getStage(hero, "model");
  if (!(st?.status === "success" && st.task_id)) return `${hero.key} の model が未完了（先に run heroes ${hero.id} --until model）`;
  const rc = getStage(hero, "rigcheck");
  if (rc?.status === "success" && (rc.output?.riggable === false || (rc.output?.rig_type && rc.output.rig_type !== "biped"))) {
    return `${hero.key} は rig-check でリグ不可（先にヒーローを作り直す）`;
  }
  return null;
}

function skinStale(a) {
  const tex = getStage(a, "texture");
  const model = getStage(heroAsset(a.entry.heroID), "model");
  return !!(tex?.input && model?.task_id && tex.input !== model.task_id);
}

class Runner {
  constructor(o) {
    this.o = o;
    this.sems = Object.fromEntries(Object.entries(CATEGORY_LIMIT).map(([k, n]) => [k, new Semaphore(Math.min(n, o.concurrency))]));
    this.submitLock = new Semaphore(1);
    this.halted = null;
    this.committed = 0; // このランで確保した見積り（完了したものは実績に置き換え）
    this.pending = new Map();
    this.stats = { submitted: 0, success: 0, failed: 0, aborted: 0, consumed: 0 };
  }

  halt(msg) {
    if (this.halted) return;
    this.halted = msg;
    log(`\n${msg}\n  新しいタスクの送信を止めました（実行中のタスクは完了まで待ちます）`);
  }

  async runAsset(a) {
    const fi = effectiveForceIndex(a, this.o);
    if (fi < Infinity) {
      if (this.halted) return; // 作り直せないのに既存の結果だけ履歴へ移さない
      const lc = localConceptPlan(a, this.o);
      if (lc && !lc.same) {
        // 後段は前の concept から作ったものなので、--until より後の段階も含めて履歴へ移す（残すと古いモデルを使い続ける）
        const old = STAGES[a.cat].filter((s) => getStage(a, s));
        if (old.length) log(`  ${a.key}: concept を ${lc.src.kind} の画像に置き換えるため ${old.join(" / ")} を履歴へ移します`);
      }
      archiveFrom(a, STAGES[a.cat][fi]);
    }
    for (const stage of stagesFor(a.cat, this.o.until)) {
      if (this.halted && getStage(a, stage)?.status !== "success" && !resumable(getStage(a, stage))) return;
      let ok;
      try {
        ok = await this.ensureStage(a, stage);
      } catch (e) {
        log(`  ${tag(a, stage)} エラー: ${e.message}`);
        ok = false;
      }
      if (!ok) return;
    }
  }

  async ensureStage(a, stage) {
    if (stage === "concept" && conceptSource(a, this.o)) return this.ensureLocalConcept(a);
    let st = getStage(a, stage);
    if (st?.status === "success") return this.finish(a, stage, null);
    if (st && UNSURE.has(st.status) && !resumable(st)) {
      log(`  ${tag(a, stage)} 前回の送信結果が不明です（課金済みの可能性）。Tripo の利用履歴を確認し、作り直すなら --force ${stage}`);
      return false;
    }
    const sem = this.sems[CATEGORY[stage]];
    await sem.acquire();
    try {
      // 待っている間に同じ段階が別の経路で進んだかもしれないので取り直す
      st = getStage(a, stage);
      if (st?.status === "success") return this.finish(a, stage, null);
      if (st && UNSURE.has(st.status) && !resumable(st)) return false;
      let tid = resumable(st) ? st.task_id : null;
      if (tid) {
        log(`  ${tag(a, stage)} 実行中のタスクを再開: ${tid}`);
      } else {
        if (this.halted) return false;
        if (st && TERMINAL_FAIL.has(st.status)) log(`  ${tag(a, stage)} 前回 ${st.status} → 再送します`);
        tid = await this.submitStage(a, stage);
        if (!tid) return false;
      }
      const task = await this.poll(a, stage, tid);
      if (!task) return false;
      const key = `${a.key}:${stage}`;
      const est = this.pending.get(key);
      this.pending.delete(key);
      if (task.status !== "success") {
        if (est !== undefined) this.committed -= est; // 失敗・取消は課金されない
        this.stats.failed++;
        return false;
      }
      const actual = num(task.credits_consumed);
      if (est !== undefined) this.committed += (actual ?? est) - est;
      this.stats.success++;
      this.stats.consumed += actual ?? 0;
      setStage(a, stage, {
        status: "success", progress: 100, credits_consumed: actual, completed_at: task.completed_at || now(),
        output: summarizeOutput(task.output), error: null,
      });
      return this.finish(a, stage, task);
    } finally {
      sem.release();
    }
  }

  // --concept-source: 参照画像を concept.png へ写して concept を成功扱いにする（Tripo のタスクなし、0 credits）。
  // 置き換え（前回と違う画像）の履歴への移動は runAsset が済ませている
  async ensureLocalConcept(a) {
    const src = conceptSource(a, this.o);
    if (src.error) {
      log(`  ${tag(a, "concept")} 参照画像を使えません: ${rel(src.path)}: ${src.error}`);
      return false;
    }
    let buf;
    try { buf = fs.readFileSync(src.path); } catch (e) {
      log(`  ${tag(a, "concept")} 参照画像を読めません: ${rel(src.path)}: ${e.code || e.message}`);
      return false;
    }
    const sha = sha256Of(buf);
    if (sha !== src.sha256) {
      log(`  ${tag(a, "concept")} ${rel(src.path)} が計画の後で変わりました（写さずに中止。もう一度実行してください）`);
      return false;
    }
    const dest = path.join(assetDir(a), "concept.png");
    const source = { kind: src.kind, path: rel(src.path), sha256: sha, ...(src.tag ? { tag: src.tag } : {}), width: src.width, height: src.height };
    const copy = () => {
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      fs.writeFileSync(`${dest}.part`, buf);
      fs.renameSync(`${dest}.part`, dest);
    };
    const st = getStage(a, "concept");
    if (st?.status === "success" && st.local && st.source?.kind === src.kind && st.source?.sha256 === sha) {
      // 同じ画像: 後段はそのまま。写しが消えた・書き換わったときだけ写し直す（置き場所やタグの変更は記録だけ更新）
      const intact = fs.existsSync(dest) && sha256File(dest) === sha;
      if (!intact) {
        copy();
        log(`  ${tag(a, "concept")} ${rel(dest)} を写し直しました（${describeSource(source)}）`);
      }
      if (!intact || JSON.stringify(st.source) !== JSON.stringify(source)) setStage(a, "concept", { source, files: { image: rel(dest) } });
      return this.finish(a, "concept", null);
    }
    if (st) archiveFrom(a, "concept"); // 通常は runAsset で移し済み（念のため。上書きして消さない）
    copy();
    const t = now();
    setStage(a, "concept", {
      status: "success", task_id: null, local: true, source, input: null, request: null, estimate: 0,
      submitted_at: t, completed_at: t, progress: 100, credits_consumed: 0, output: null, files: { image: rel(dest) }, error: null,
    });
    log(`  ${tag(a, "concept")} ローカル画像: ${rel(src.path)} → ${rel(dest)}（${describeSource(source)}、0 credits）`);
    return this.finish(a, "concept", null);
  }

  // ローカル画像の concept.png を POST /files（無料）へ上げて file_token を得る。上げる直前に concept の記録と照合する
  async uploadLocalInput(a, stage, file) {
    const src = sourceOf(a, stage);
    const cst = getStage(src.asset, src.stage);
    let buf;
    try { buf = fs.readFileSync(file); } catch (e) { throw new Error(`${rel(file)} を読めません（${e.code || e.message}）`); }
    const sha = sha256Of(buf);
    if (sha !== cst?.source?.sha256) {
      throw new Error(`${rel(file)} が ${tag(src.asset, src.stage)} の記録（sha256 ${shortSha(cst?.source?.sha256)}）と違います。`
        + `--concept-source ${cst?.source?.kind ?? "fullbody"} を付けて写し直してください`);
    }
    const token = await uploadFile(file, buf);
    log(`  ${tag(a, stage)} ${rel(file)} をアップロード（${fmtBytes(buf.length)}）: ${token}`);
    return { file: rel(file), sha256: sha, file_token: token, uploaded_at: now() };
  }

  async submitStage(a, stage) {
    const localFile = localInputFile(a, stage, this.o);
    if (localFile) {
      const src = sourceOf(a, stage);
      const cst = getStage(src.asset, src.stage);
      if (!(cst?.status === "success" && cst.local)) {
        log(`  ${tag(a, stage)} 前段 ${src.asset.key} ${src.stage}（ローカル画像）が未完了のため送信しません`);
        return null;
      }
      // input は submit が予算・残高の確認を通した後でアップロードして差し替える
      const body = buildBody(a, stage, UPLOAD_PLACEHOLDER, this.o, null);
      return this.submit(a, stage, body, () => this.uploadLocalInput(a, stage, localFile));
    }
    const input = inputFor(a, stage, null);
    if (sourceOf(a, stage) && !input) {
      const src = sourceOf(a, stage);
      log(`  ${tag(a, stage)} 前段 ${src.asset.key} ${src.stage} が未完了のため送信しません`);
      return null;
    }
    const styleImage = stage === "texture" ? await styleImageFor(a, this.o) : null;
    const body = buildBody(a, stage, input, this.o, styleImage);
    if (a.cat === "skins" && stage === "rig") {
      try {
        return await this.submit(a, stage, body);
      } catch (e) {
        // rig の入力にテクスチャタスクの ID が通らない場合は、ダウンロード済みの GLB をアップロードして渡す
        if (!(e instanceof TripoError) || e.status !== 400) throw e;
        log(`  ${tag(a, stage)} テクスチャタスク ID が rig の入力として通りませんでした → textured.glb をアップロードして再送`);
        const token = await uploadFile(path.join(assetDir(a), "textured.glb"));
        return this.submit(a, stage, { ...body, input: token });
      }
    }
    return this.submit(a, stage, body);
  }

  // 予算確認 → 送信（残高の確認と送信が並行で食い違わないよう 1 本ずつ）。
  // prepareUpload があれば確認を通った後で呼び、その file_token を input にする（止まるときは上げない）
  async submit(a, stage, body, prepareUpload = null) {
    await this.submitLock.acquire();
    try {
      if (this.halted) return null;
      // 送信してよいのは未送信か失敗が確定した段階だけ（実行中・成功・結果不明の段階へ二重に課金しない）
      const cur = getStage(a, stage);
      if (cur && !TERMINAL_FAIL.has(cur.status)) {
        log(`  ${tag(a, stage)} 既に ${cur.status}${cur.task_id ? `（${cur.task_id}）` : ""} のため送信しません`);
        return null;
      }
      const need = CREDITS[stage];
      if (need > 0) {
        if (this.o.maxCredits !== undefined && this.committed + need > this.o.maxCredits) {
          this.halt(`--max-credits ${this.o.maxCredits} に達するため停止（このランの見積り ${fmtCredits(this.committed)} + 次の ${need}）`);
          return null;
        }
        const bal = await getBalance();
        if (bal.balance < need) {
          this.halt(shortageText(need, bal));
          return null;
        }
      }
      // アップロードは無料で、失敗しても有料の POST は送っていないので段階の状態は変えない（例外は runAsset が表示）
      const upload = prepareUpload ? await prepareUpload() : undefined;
      if (upload) body = { ...body, input: upload.file_token };
      setStage(a, stage, {
        // upload: 上げた画像と file_token の控え（API キーは含まない）。undefined なら前回の控えを消す
        status: "submitting", task_id: null, input: body.input ?? null, request: redactBody(body), upload, estimate: need,
        submitted_at: now(), completed_at: null, progress: 0, credits_consumed: null, output: null, files: {}, error: null,
      });
      let data;
      try {
        data = await api("POST", ENDPOINTS[stage], body, { paid: true });
      } catch (e) {
        // 「failed」（次回は再送）にするのは JSON の業務エラーを伴う 4xx だけ。5xx・通信エラー・タイムアウト・JSON でない応答は
        // タスクが作られて課金済みの可能性があるので「unknown」にして、次回は --force なしでは再送しない
        const definite = e instanceof TripoError && e.status >= 400 && e.status < 500 && !!e.json && e.code !== undefined;
        if (definite) {
          setStage(a, stage, { status: "failed", error: scrub(e.message) });
          if (e.insufficientCredits) { this.halt(shortageText(need, await getBalance().catch(() => ({ balance: 0, frozen: 0 })))); return null; }
        } else {
          setStage(a, stage, { status: "unknown", error: scrub(e.message) });
          log(`  ${tag(a, stage)} 送信結果が不明です（タスクが作られ課金済みの可能性）。Tripo の利用履歴を確認してください`);
        }
        throw e;
      }
      const tid = data?.task_id;
      if (!tid) {
        setStage(a, stage, { status: "unknown", error: "応答に task_id がありません" });
        throw new Error(`${ENDPOINTS[stage]} の応答に task_id がありません`);
      }
      setStage(a, stage, { status: "queued", task_id: tid });
      this.committed += need;
      this.pending.set(`${a.key}:${stage}`, need);
      this.stats.submitted++;
      log(`  ${tag(a, stage)} 送信: ${tid}（見積り ${need} credits）`);
      return tid;
    } finally {
      this.submitLock.release();
    }
  }

  // 5 秒ごとに状態を確認。表示は状態か進捗（10% 刻み）が変わったときと 1 分ごとに 1 行
  async poll(a, stage, tid) {
    const t0 = Date.now();
    const submittedAt = Date.parse(getStage(a, stage)?.submitted_at ?? "") || t0;
    let lastLine = "";
    let lastPrint = 0;
    let notFound = 0;
    for (;;) {
      let task;
      try {
        task = await api("GET", `/tasks/${encodeURIComponent(tid)}`);
      } catch (e) {
        if (taskNotFound(e)) {
          // 作成直後は GET に反映されていないことがある → 送信から 60 秒（再開時も最低 3 回）は待って問い合わせ直す
          notFound++;
          if (Date.now() - submittedAt < NOT_FOUND_GRACE_MS || notFound < NOT_FOUND_MIN_TRIES) {
            await sleep(Math.min(POLL_INTERVAL_MS * notFound, 15_000));
            continue;
          }
          // task_id は残す（次回の run で問い合わせ直す。--force だと再課金になる）
          setStage(a, stage, { status: "unknown", error: `タスクが見つかりません（${NOT_FOUND_WHY}）` });
          log(`  ${tag(a, stage)} タスク ${tid} が見つかりません（${NOT_FOUND_WHY}）。次回の run で問い合わせ直します。`
            + `API キーを差し替えたなら前のキーの利用履歴を、そうでなければ Tripo の利用履歴でタスクが無いことを確かめてから`
            + ` --force ${stage} で作り直してください（作り直しは再課金）`);
          return null;
        }
        throw e;
      }
      notFound = 0;
      const status = task?.status || "unknown";
      const progress = num(task?.progress) ?? 0;
      const line = `${status} ${Math.floor(progress / 10)}`;
      if (line !== lastLine || Date.now() - lastPrint > 60_000) {
        log(`  ${pad(tag(a, stage), 30)} ${pad(status, 9)} ${String(progress).padStart(3)}%  ${pad(elapsed(t0), 7)} ${tid}`);
        lastLine = line;
        lastPrint = Date.now();
      }
      const st = getStage(a, stage);
      if (status === "success") return task;
      if (TERMINAL_FAIL.has(status)) {
        const err = [task.error_code, task.error_message].filter((x) => x !== undefined && x !== null && x !== "").join(" ") || null;
        setStage(a, stage, { status, error: err, completed_at: task.completed_at || now() });
        log(`  ${tag(a, stage)} ${status}${err ? `: ${err}` : ""}${status === "banned" ? "（プロンプト・画像を見直してください）" : ""}`);
        return task;
      }
      if (st?.status !== status && ACTIVE.has(status)) setStage(a, stage, { status, progress });
      if (Date.now() - t0 > POLL_TIMEOUT_MS) {
        log(`  ${tag(a, stage)} ${Math.round(POLL_TIMEOUT_MS / 60000)} 分待っても完了しません。後で同じコマンドを実行すると続きから待ちます`);
        return null;
      }
      await sleep(POLL_INTERVAL_MS);
    }
  }

  // 完了後: ダウンロードと段階ごとの検査
  async finish(a, stage, task) {
    if (!(await this.ensureFiles(a, stage, task))) return false;
    if (stage === "rigcheck") {
      const o = getStage(a, stage).output || {};
      if (o.riggable === false || (o.rig_type && o.rig_type !== "biped")) {
        log(`  ${a.key}: リグ不可（riggable=${o.riggable}, rig_type=${o.rig_type ?? "?"}）のため中止。`
          + `コンセプトを見直して --force concept（またはモデルだけ --force model）で作り直してください`);
        this.stats.aborted++;
        return false;
      }
      if (o.riggable === undefined) log(`  ${tag(a, stage)} 注意: rig-check の結果に riggable がありません（output: ${JSON.stringify(o)}）。続行します`);
    }
    if (a.cat === "skins" && stage === "texture" && skinStale(a)) {
      log(`  ${tag(a, stage)} 注意: ${a.entry.heroID} の model が作り直されています。合わせるなら --force texture`);
    }
    return true;
  }

  async ensureFiles(a, stage, task) {
    const specs = STAGE_FILES[stage];
    if (!specs.length) return true;
    const st = getStage(a, stage);
    const dir = assetDir(a);
    fs.mkdirSync(dir, { recursive: true });
    if (st.local) {
      // ローカル画像の段階（--concept-source）は Tripo のタスクが無く取り直せない → 写しを記録の sha256 と照合するだけ
      for (const [, name] of specs) {
        const dest = path.join(dir, name);
        if (fs.existsSync(dest) && sha256File(dest) === st.source?.sha256) continue;
        log(`  ${tag(a, stage)} ${rel(dest)} が無いか記録（${st.source?.kind ?? "?"}、sha256 ${shortSha(st.source?.sha256)}）と違います。`
          + `--concept-source ${st.source?.kind ?? "fullbody"} を付けて写し直してください`);
        // 段階は success のままで後段も確かめずに止まる（後段が成功済みだと「完了」に数えられる）→ 終了コードで知らせる
        process.exitCode = 1;
        return false;
      }
      return true;
    }
    const files = { ...(st.files || {}) };
    let fresh = task;
    let changed = false;
    for (const [kind, name, required] of specs) {
      const dest = path.join(dir, name);
      if (files[kind] === rel(dest) && !badContent(dest, kind === "model" ? "model" : "image")) continue;
      if (!fresh?.output) {
        try {
          fresh = await api("GET", `/tasks/${encodeURIComponent(st.task_id)}`); // URL は期限付きなので取り直す
        } catch (e) {
          if (!taskNotFound(e)) throw e;
          log(`  ${tag(a, stage)} ${name} を取り直せません: タスク ${st.task_id} が見つかりません（${NOT_FOUND_WHY}）。`
            + `${rel(dest)} を戻すか、--force ${stage} で作り直してください（再課金）`);
          process.exitCode = 1; // 段階は success のままなので「未完了」に数えられない → 終了コードで知らせる
          return false;
        }
      }
      const url = outputUrl(fresh?.output, kind);
      if (!url) {
        const keys = Object.keys(fresh?.output || {}).join(", ") || "なし";
        if (required) {
          log(`  ${tag(a, stage)} 出力に ${kind} の URL がありません（output のキー: ${keys}）。node tools/tripo.mjs task ${st.task_id} で確認`);
          return false;
        }
        log(`  ${tag(a, stage)} ${name} は出力に無いため省略（output のキー: ${keys}）`);
        continue;
      }
      const size = await download(url, dest, kind === "model" ? "model" : "image");
      files[kind] = rel(dest);
      changed = true;
      log(`  ${tag(a, stage)} 保存: ${rel(dest)}（${fmtBytes(size)}）`);
    }
    if (changed) setStage(a, stage, { files });
    return true;
  }
}

async function runPool(items, limit, fn) {
  let next = 0;
  const worker = async () => {
    while (next < items.length) await fn(items[next++]);
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
}

function printJSONIndented(obj, indent) {
  for (const line of JSON.stringify(obj, null, 2).split("\n")) log(indent + line);
}

function dryRun(cat, plans, o) {
  const planned = new Set();
  let total = 0;
  for (const { a, plan } of plans) {
    log(`\n${a.key}  ${a.cat === "props" ? `（${a.label}、grip ${a.entry.grip}${a.optional ? "、任意" : ""}）` : a.label}`);
    if (a.cat === "skins") {
      const pre = skinPrereq(a);
      if (pre) log(`  前提: ${pre}`);
      if (skinStale(a)) log(`  注意: ${a.entry.heroID} の model が作り直されています（--force texture で合わせる）`);
    }
    for (const p of plan) {
      const head = `  ${pad(p.stage, 9)}`;
      const sub = " ".repeat(dispWidth(head));
      if (p.action === "missing") {
        log(`${head}参照画像（--concept-source ${p.src.kind}）を使えません: ${rel(p.src.path)}: ${p.src.error} → run 全体を始めない`);
        log(`${sub}作り方: ${CONCEPT_SOURCES[p.src.kind].howTo(a)}`);
        break;
      }
      if (p.action === "local") {
        const dest = path.join(assetDir(a), "concept.png");
        log(`${head}ローカル画像を写す（Tripo に送らない）  見積り 0 credits: ${rel(p.src.path)} → ${rel(dest)}`);
        log(`${sub}${describeSource(p.src)}`);
        // 置き換えでは --until より後の段階も履歴へ移す（runAsset と同じ）
        const old = STAGES[a.cat].filter((s) => getStage(a, s));
        if (old.length) {
          const prev = p.st ? (p.st.local ? `前回のローカル画像 sha256 ${shortSha(p.st.source?.sha256)}` : `Tripo の ${p.st.task_id ?? p.st.status}`) : "concept なし";
          log(`${sub}既存の ${old.join(" / ")} を履歴へ移して作り直す（${p.why === "force" ? "--force" : `concept が変わる: ${prev}`}）`);
        }
        continue;
      }
      if (p.action === "done") {
        log(`${head}済み（${p.st.local ? `ローカル画像 ${describeSource(p.st.source || {})}` : p.st.task_id}）→ スキップ`);
        continue;
      }
      if (p.action === "resume") {
        log(`${head}${p.st.status === "unknown" ? "前回 404 だったタスク" : "実行中"}（${p.st.task_id}, ${p.st.status}）→ ポーリングを再開`);
        continue;
      }
      if (p.action === "blocked") { log(`${head}前回の送信結果が不明（${p.st.status}）→ 送信しない。作り直すなら --force ${p.stage}`); continue; }
      const upload = localInputFile(a, p.stage, o, planned);
      const input = upload ? UPLOAD_PLACEHOLDER : inputFor(a, p.stage, planned);
      const styleImage = p.stage === "texture" && !o.noStyleImage
        ? { url: `<${a.entry.heroID} のコンセプト画像 URL（送信直前に GET /tasks/{concept} で取得。無ければ concept.png をアップロードして file_token）>` }
        : null;
      const body = buildBody(a, p.stage, input, o, styleImage);
      const cost = CREDITS[p.stage];
      total += cost;
      planned.add(`${a.key}:${p.stage}`);
      const note = p.forced ? (p.why === "force" ? "（--force: 既存の結果を履歴へ移して再送）" : "（concept が変わるため既存の結果を履歴へ移して再送）")
        : p.st ? `（前回 ${p.st.status} → 再送）` : "";
      if (upload) log(`${head}POST /files（無料。予算・残高の確認を通った後、送信の直前）: ${rel(upload)} → file_token を input へ`);
      log(`${upload ? sub : head}POST ${ENDPOINTS[p.stage]}  見積り ${cost} credits${note}`);
      printJSONIndented(body, "    ");
      const promptText = body.prompt ?? body.texture_prompt?.text;
      if (promptText) log(`    prompt ${promptText.length} 文字`);
      if (p.stage === "rigcheck") log("    → riggable=false または rig_type≠biped ならこのヒーローは中止");
      const outs = STAGE_FILES[p.stage].map(([, name]) => rel(path.join(assetDir(a), name)));
      if (outs.length) log(`    → ${outs.join(", ")}`);
      if (a.cat === "skins" && p.stage === "rig") log("    （入力のテクスチャタスク ID が拒否されたら textured.glb をアップロードして file_token で再送）");
    }
  }
  return total;
}

async function cmdRun(cat, ids, o) {
  if (!STAGES[cat]) fail("run の対象は heroes | props | skins");
  if (o.faces !== undefined && cat === "skins") fail("--faces は heroes / props のみ");
  if (o.styleImageFlag && cat !== "skins") fail(`${o.styleImageFlag} は skins のみ`);
  if (o.conceptSource && cat !== "heroes") fail("--concept-source は heroes のみ");
  validateForce(cat, o.force);
  const inRun = stagesFor(cat, o.until);
  const beyond = [...o.force].filter((f) => f !== "all" && !inRun.includes(f));
  if (beyond.length) fail(`--force ${beyond.join(",")} は --until ${o.until} より後の段階です（送信せずに既存の結果を履歴へ移すことになるため中止）`);
  let assets = select(cat, ids, o);
  // tools/meshy.mjs が置いた model.glb（source.json の sha256 が一致）は、Tripo の model を送ると課金した上で上書きしてしまう
  // → 送信前に外す（--replace-meshy で Tripo の model に戻す。上書き後は source.json が外れて Tripo の向きで取り込む）
  if (cat === "props" && !o.replaceMeshy) {
    const meshy = assets.filter((a) => planStages(a, o).some((p) => p.stage === "model" && p.action === "submit") && propSource(a, { quiet: true }));
    for (const a of meshy) log(`  ${a.key}: ${rel(path.join(assetDir(a), "model.glb"))} は tools/meshy.mjs 製（source.json）→ スキップ（Tripo で作り直すなら --replace-meshy）`);
    assets = assets.filter((a) => !meshy.includes(a));
    if (meshy.length && ids.length) process.exitCode = 1;
  }
  const plans = assets.map((a) => ({ a, plan: planStages(a, o) }));
  // 参照画像が無い・使えないヒーローがあれば何も始めない（一部だけ置き換えて残りを Tripo の concept のまま進めない）
  const missing = plans.flatMap(({ plan }) => plan.filter((p) => p.action === "missing").map((p) => p.src));
  const missingText = () => `参照画像（--concept-source ${o.conceptSource}）を使えません:\n`
    + missing.map((s) => `  ${rel(s.path)}: ${s.error}`).join("\n")
    + "\n  作り方: python3 tools/heroref/fullbody.py generate <ID> --tag t1 → 確認して select <ID> <tag>";

  if (o.dry) {
    DRY = true;
    log(`[dry-run] run ${cat}: ${assets.length} 件。有料 API は呼ばず、state.json も変更しません`
      + (o.conceptSource ? `（concept はローカル画像 ${o.conceptSource}: ${rel(HEROREF_DIR)}/<ID>/）` : ""));
    const total = dryRun(cat, plans, o);
    log(`\n[dry-run] 新規送信の見積り合計: ${total} credits（${usd(total)}）`);
    if (missing.length) {
      log(`[dry-run] ${missingText()}`);
      process.exitCode = 1;
    }
    if (hasApiKey()) {
      try {
        const bal = await getBalance();
        log(`[dry-run] 残高 ${fmtCredits(bal.balance)}（凍結 ${fmtCredits(bal.frozen)}）${bal.balance < total ? ` → 不足 ${fmtCredits(total - bal.balance)}。購入: ${PURCHASE_URL}` : ""}`);
      } catch (e) {
        log(`[dry-run] 残高を取得できません: ${e.message}`);
      }
    }
    return;
  }

  if (missing.length) fail(missingText());
  if (cat === "skins") {
    const blocked = assets.filter((a) => skinPrereq(a) && planStages(a, o).some((p) => p.stage === "texture" && p.action === "submit"));
    for (const a of blocked) log(`  ${a.key}: スキップ（${skinPrereq(a)}）`);
    assets = assets.filter((a) => !blocked.includes(a));
    if (blocked.length) process.exitCode = 1;
  }
  const total = assets.reduce((sum, a) => sum + planCost(planStages(a, o)), 0);
  const bal = await getBalance();
  log(`run ${cat}: ${assets.length} 件、新規送信の見積り ${total} credits（${usd(total)}）、残高 ${fmtCredits(bal.balance)}（凍結 ${fmtCredits(bal.frozen)}）`
    + (o.maxCredits !== undefined ? `、上限 --max-credits ${o.maxCredits}` : "")
    + (o.conceptSource ? `、concept はローカル画像（${o.conceptSource}、0 credits）` : ""));
  const needNow = Math.min(total, o.maxCredits ?? Infinity);
  if (needNow > 0 && bal.balance < needNow && !o.allowPartial) {
    fail(`${shortageText(needNow, bal)}\n  途中まででよければ --allow-partial（残高が尽きた時点で送信を止めます）か --max-credits N`);
  }
  if (!assets.length) return;

  const runner = new Runner(o);
  process.on("SIGINT", () => {
    console.error("\n中断しました。送信済みのタスクは Tripo 側で続行し、次回の run で続きから再開します"
      + (o.force.size ? "（--force は外して再実行。付けたままだと作り直し＝再課金）" : ""));
    process.exit(130);
  });
  await runPool(assets, o.concurrency, (a) => runner.runAsset(a));

  const s = runner.stats;
  log(`\n完了: 送信 ${s.submitted}、成功 ${s.success}、失敗 ${s.failed}${s.aborted ? `、リグ不可で中止 ${s.aborted}` : ""}、`
    + `消費 ${fmtCredits(s.consumed)} credits（${usd(s.consumed)}）`);
  if (runner.halted) log(`停止理由: ${runner.halted.split("\n")[0]}`);
  const last = stagesFor(cat, o.until).at(-1);
  const done = assets.filter((a) => getStage(a, last)?.status === "success");
  if (done.length && last === STAGES[cat].at(-1)) log(`取り込み: node tools/tripo.mjs import ${cat} ${done.map((a) => a.id).join(" ")}`);
  const incomplete = assets.filter((a) => !done.includes(a));
  if (incomplete.length) log(`未完了: ${incomplete.map((a) => a.id).join(" ")}（node tools/tripo.mjs status で確認）`);
  if (incomplete.length || runner.halted) process.exitCode = 1;
}

// MARK: - 見積り・状態

async function cmdEstimate(catArg, ids, o) {
  const cats = !catArg || catArg === "all" ? ["heroes", "props", "skins"] : [catArg];
  if (cats.some((c) => !STAGES[c])) fail("estimate の対象は heroes | props | skins | all");
  if (o.conceptSource && !cats.includes("heroes")) fail("--concept-source は heroes のみ");
  // ローカル画像の concept は 0 credits（--concept-source はヒーローだけに効く）
  const stageCost = (c, st) => (st === "concept" && c === "heroes" && o.conceptSource ? 0 : CREDITS[st]);
  const chosen = { heroes: [], props: [], skins: [] };
  if (ids.length) {
    for (const id of ids) {
      const hit = cats.map((c) => findAsset(c, id)).find(Boolean);
      if (!hit) fail(`${cats.join("/")} に ${id} はありません`);
      if (!chosen[hit.cat].includes(hit)) chosen[hit.cat].push(hit);
    }
  } else {
    for (const c of cats) chosen[c] = select(c, [], o, true);
  }
  log("見積り（1 credit = $0.01。料金ページ 2026-10 時点の定価。作り直しの余裕は含まない）");
  let full = 0;
  let remaining = 0;
  const rows = [["", "件数", "1 件あたり", "合計", "未完了分（state 基準）"]];
  for (const c of cats) {
    const list = chosen[c];
    if (!list.length) continue;
    const per = STAGES[c].reduce((s, st) => s + stageCost(c, st), 0);
    const rem = list.reduce((s, a) => s + planCost(planStages(a, { ...o, until: undefined, force: new Set() })), 0);
    full += per * list.length;
    remaining += rem;
    rows.push([c, String(list.length), `${per}（${STAGES[c].map((st) => `${st} ${stageCost(c, st)}`).join(" + ")}）`,
      `${per * list.length}（${usd(per * list.length)}）`, `${rem}（${usd(rem)}）`]);
  }
  rows.push(["合計", "", "", `${full}（${usd(full)}）`, `${remaining}（${usd(remaining)}）`]);
  table(rows);
  if (o.conceptSource && chosen.heroes.length) {
    // 未完了分は「参照画像の写しで concept を置き換え、後段を作り直す」前提。画像の無いヒーローもその前提で数える
    const missing = chosen.heroes.filter((a) => conceptSource(a, o).error);
    log(`  heroes の concept はローカル画像（${o.conceptSource}: ${rel(HEROREF_DIR)}/<ID>/）。前回と違う画像なら model 以降を作り直す前提`
      + (missing.length ? `\n  参照画像が無い・使えない: ${missing.map((a) => a.id).join(" ")}（run は止まる）` : ""));
  }
  if (cats.includes("props") && !ids.length) {
    const opt = manifest.assets.props.filter((a) => a.optional && !a.entry.bodyWorn);
    const worn = manifest.assets.props.filter((a) => a.entry.bodyWorn);
    if (!o.includeOptional && opt.length) {
      log(`  props は任意の ${opt.map((a) => a.id).join(" / ")} を除く（--include-optional で +${opt.length * (CREDITS.concept + CREDITS.model)}）`);
    }
    if (worn.length) log(`  props は本体に含める ${worn.map((a) => a.id).join(" / ")}（bodyWorn）を除く（ID を名指ししたときだけ対象）`);
  }
  if (!hasApiKey()) { log("  残高: API キーが無いため未取得"); return; }
  let bal;
  try { bal = await getBalance(); } catch (e) { log(`  残高を取得できません: ${e.message}`); process.exitCode = 1; return; }
  log(`  残高 ${fmtCredits(bal.balance)} credits（${usd(bal.balance)}、凍結 ${fmtCredits(bal.frozen)}）`
    + (bal.balance >= remaining ? " → 足ります" : ` → 不足 ${fmtCredits(remaining - bal.balance)} credits（${usd(remaining - bal.balance)}）。購入: ${PURCHASE_URL}`));
}

function cellFor(a, stage) {
  const st = getStage(a, stage);
  if (!st) return "-";
  if (st.status === "success") {
    if (st.local) return `local ${st.source?.kind ?? ""}`.trim();
    if (stage === "rigcheck") {
      const o = st.output || {};
      return o.riggable === false || (o.rig_type && o.rig_type !== "biped") ? `NG ${o.rig_type ?? ""}`.trim() : `ok ${o.rig_type ?? ""}`.trim();
    }
    const stale = a.cat === "skins" && stage === "texture" && skinStale(a) ? " 古い" : "";
    return `success ${fmtCredits(st.credits_consumed)}${stale}`;
  }
  if (ACTIVE.has(st.status)) return `${st.status} ${st.progress ?? 0}%`;
  return st.status;
}

// リグ付きモデル: 同じリグの rigged.fbx を置けばそちらを使う（Tripo の GLB は骨とメッシュの軸ずれや全頂点 Hips の
// ダミーのスキンで届くことがあり、normalize_hero.py の検査で弾かれる。有料リクエストは out_format "glb" のまま）
function riggedInput(a) {
  const fbx = path.join(assetDir(a), "rigged.fbx");
  return fs.existsSync(fbx) ? fbx : path.join(assetDir(a), "rigged.glb");
}

function importTarget(a) {
  if (a.cat === "heroes") return { input: riggedInput(a), out: path.join(RES_DIR, `Hero_${a.id}.usdz`), script: "normalize_hero.py" };
  if (a.cat === "skins") return { input: riggedInput(a), out: path.join(RES_DIR, `Hero_${a.entry.heroID}_${a.id}.usdz`), script: "normalize_hero.py" };
  return { input: path.join(assetDir(a), "model.glb"), out: path.join(RES_DIR, `Prop_${a.id}.usdz`), script: "normalize_prop.py" };
}

function cmdStatus() {
  let consumed = 0;
  let active = 0;
  let failed = 0;
  for (const as of Object.values(state.assets)) {
    for (const st of Object.values(as.stages || {})) {
      consumed += num(st.credits_consumed) ?? 0;
      if (ACTIVE.has(st.status) || UNSURE.has(st.status)) active++;
      if (TERMINAL_FAIL.has(st.status)) failed++;
    }
    for (const h of as.history || []) consumed += num(h.credits_consumed) ?? 0;
  }
  log(`state: ${fs.existsSync(STATE_PATH) ? rel(STATE_PATH) : "（まだありません）"}${state.updated_at ? `（更新 ${state.updated_at}）` : ""}`);
  for (const cat of ["heroes", "props", "skins"]) {
    log(`\n${cat}（ファイル: ${rel(BUILD_DIR)}/${cat}/<id>/、取り込み先: ${rel(RES_DIR)}/）`);
    const head = cat === "heroes" ? ["ID", "名前"] : cat === "props" ? ["kind", "使用"] : ["ID", "ヒーロー"];
    const rows = [[...head, ...STAGES[cat], "取り込み", "ローカル"]];
    for (const a of manifest.assets[cat]) {
      const dir = assetDir(a);
      const local = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => !f.endsWith(".part")).sort().join(" ") : "";
      const t = importTarget(a);
      const imp = state.assets[a.key]?.import;
      const impCell = fs.existsSync(t.out)
        ? `${path.basename(t.out)}${imp?.status === "failed" ? "（最新の取り込みは不合格・旧版のまま）" : ""}`
        : imp?.status === "failed" ? "failed" : a.entry.bodyWorn ? "（本体に含む）" : "-";
      rows.push([a.id, a.cat === "props" ? `${a.label}${a.optional ? "（任意）" : ""}` : a.label, ...STAGES[cat].map((s) => cellFor(a, s)), impCell, local || "-"]);
    }
    table(rows);
  }
  log(`\n消費合計 ${fmtCredits(consumed)} credits（${usd(consumed)}）、実行中・不明 ${active}、失敗 ${failed}`);
}

// MARK: - 取り込み（Blender）

const shq = (s) => (/^[\w@%+=:,./-]+$/.test(s) ? s : `'${String(s).replace(/'/g, "'\\''")}'`);

// 正規化レポートの要約（パスは省き、数値配列はそのまま、その他の配列は件数）
function printReport(file) {
  if (!fs.existsSync(file)) { log("    レポートなし"); return; }
  let r;
  try { r = JSON.parse(fs.readFileSync(file, "utf8")); } catch { log(`    レポートを読めません: ${rel(file)}`); return; }
  const fmt = (v) => (typeof v === "number" && !Number.isInteger(v) ? String(Number(v.toFixed(4))) : String(v));
  const parts = [];
  for (const [k, v] of Object.entries(r)) {
    if (k === "input" || k === "output" || k === "warnings" || k === "errors") continue;
    if (v === null || ["string", "number", "boolean"].includes(typeof v)) parts.push(`${k}=${fmt(v)}`);
    else if (Array.isArray(v)) parts.push(v.length <= 4 && v.every((x) => typeof x === "number") ? `${k}=[${v.map(fmt).join(", ")}]` : `${k}=${v.length}件`);
    else if (typeof v === "object") parts.push(`${k}={${Object.entries(v).map(([kk, vv]) => `${kk}: ${typeof vv === "object" ? JSON.stringify(vv) : fmt(vv)}`).join(", ")}}`);
  }
  for (let i = 0; i < parts.length; i += 6) log(`    ${parts.slice(i, i + 6).join("  ")}`);
  for (const k of ["warnings", "errors"]) {
    if (Array.isArray(r[k]) && r[k].length) for (const w of r[k].slice(0, 10)) log(`    ${k === "errors" ? "エラー" : "警告"}: ${typeof w === "string" ? w : JSON.stringify(w)}`);
  }
}

// 検査ツール（verify_usdz.swift）: swiftc で BUILD_DIR/verify_usdz に 1 度だけコンパイルし、ソースより新しければ再利用する
// （swift でスクリプトとして実行すると毎回コンパイルが走る）。コンパイルできなければ swift のスクリプト実行で代用する。
let verifierCache = null;
const verifierFresh = () => fs.existsSync(VERIFY_BIN) && fs.statSync(VERIFY_BIN).mtimeMs >= fs.statSync(VERIFY_SRC).mtimeMs;

function verifierCommand() {
  if (verifierCache) return verifierCache;
  if (!fs.existsSync(VERIFY_SRC)) fail(`検査ツールがありません: ${rel(VERIFY_SRC)}`);
  if (!verifierFresh()) {
    log(`検査ツールをコンパイル: ${SWIFTC} -O ${rel(VERIFY_SRC)} -o ${rel(VERIFY_BIN)}（初回・ソース更新時のみ）`);
    fs.mkdirSync(path.dirname(VERIFY_BIN), { recursive: true });
    const tmp = `${VERIFY_BIN}.${process.pid}.tmp`;
    const t0 = Date.now();
    const r = spawnSync(SWIFTC, ["-O", VERIFY_SRC, "-o", tmp], { encoding: "utf8", timeout: 10 * 60_000 });
    if (r.status === 0 && fs.existsSync(tmp)) {
      fs.renameSync(tmp, VERIFY_BIN); // 並行する別プロセスと競合しても rename なので壊れない
      log(`  完了（${elapsed(t0)}）`);
    } else {
      fs.rmSync(tmp, { force: true });
      const why = `${r.stderr || ""}${r.error ? ` ${r.error.code || r.error.message}` : ""}`.trim().split("\n").slice(-5).join("\n    ");
      log(`  コンパイルできないので swift でスクリプトとして実行します（1 件ごとに遅い）:\n    ${why}`);
      verifierCache = ["swift", VERIFY_SRC];
      return verifierCache;
    }
  }
  verifierCache = [VERIFY_BIN];
  return verifierCache;
}

// Prop の model.glb の出どころ（tools/meshy.mjs が置く source.json）。sha256 が今の model.glb と一致するときだけ有効
// （Tripo が model.glb を作り直したら外れる）。無い・合わない → null（Tripo の GLB とみなす）
const PROP_FRONTS = new Set(["+x", "-x", "+z", "-z"]);
// assets.json の props[] に出どころ別の上書き（"meshy": {...}）を置けるのは既知の出どころだけ（"grip" などの項目と取り違えない）
const PROP_PROVIDERS = new Set(["meshy"]);
function propSource(a, { quiet = false } = {}) {
  const file = path.join(assetDir(a), "source.json");
  const model = path.join(assetDir(a), "model.glb");
  if (!fs.existsSync(file) || !fs.existsSync(model)) return null;
  let src;
  try { src = JSON.parse(fs.readFileSync(file, "utf8")); } catch { if (!quiet) log(`  ${rel(file)} を読めないので無視します`); return null; }
  const h = crypto.createHash("sha256").update(fs.readFileSync(model)).digest("hex");
  if (src.sha256 !== h) { if (!quiet) log(`  ${rel(file)} は今の model.glb と sha256 が合わないので無視します（Tripo の GLB とみなす）`); return null; }
  if (src.front !== undefined && !PROP_FRONTS.has(src.front)) fail(`${rel(file)} の front が不正です: ${src.front}`);
  return { provider: String(src.provider || "unknown"), front: src.front };
}

// Prop の正規化の値。assets.json の値に、出どころ（source.json）の front と、出どころ別の上書き
// （例: "meshy": { "yaw": 90 }。キーは front / yaw / side / axis）を重ねる。--axis（io.axis）が最優先
function propParams(a, io) {
  const e = a.entry;
  const src = propSource(a);
  const raw = src && PROP_PROVIDERS.has(src.provider) && Object.hasOwn(e, src.provider) ? e[src.provider] : null;
  const over = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  const pick = (k) => (over[k] !== undefined ? over[k] : k === "front" && src?.front !== undefined ? src.front : e[k]);
  return {
    provider: src?.provider ?? "tripo",
    grip: e.grip ?? 0.5,
    front: pick("front"),
    yaw: pick("yaw"),
    side: pick("side"),
    axis: io.axis ?? pick("axis"),
  };
}

// 検査の引数。ヒーロー・スキンは身長、Prop は握り・長さと、propParams の yaw / axis から決まる薄い向き・長軸
function verifyArgs(a, io, pp = a.cat === "props" ? propParams(a, io) : null) {
  if (a.cat !== "props") return ["--expect", "hero", "--height", String(io.height ?? 1.7)];
  const yaw = ((Number(pp.yaw ?? 0) % 360) + 360) % 360;
  // normalize_prop.py は薄い向きを ±X に置いてから yaw を掛ける: ±90° なら ±Z、0/180° なら ±X、それ以外は調べない
  const thin = yaw === 90 || yaw === 270 ? "z" : yaw === 0 || yaw === 180 ? "x" : "any";
  // 長軸（PCA の第 1 軸）が Y に来たかは、面が ±X の Prop で axis vertical でないときだけ調べる
  const axis = pp.axis ?? "auto";
  const long = thin === "x" && axis !== "vertical" ? "y" : "any";
  return ["--expect", "prop", "--grip", String(pp.grip), "--length", String(io.length ?? 1.0),
    "--thin-axis", thin, "--long-axis", long];
}

// 合格した一時ファイルを取り込み先へ置く。同じボリュームなら rename 1 回、違えば同じフォルダの一時名へ写してから rename
function installAtomically(staged, out) {
  fs.mkdirSync(path.dirname(out), { recursive: true });
  try {
    fs.renameSync(staged, out);
    return;
  } catch (e) {
    if (e.code !== "EXDEV") throw e;
  }
  const tmp = path.join(path.dirname(out), `.${path.basename(out)}.${process.pid}.part`);
  try {
    fs.copyFileSync(staged, tmp);
    fs.renameSync(tmp, out);
  } finally {
    fs.rmSync(tmp, { force: true });
  }
}

const tail = (text, n) => text.trim().split("\n").slice(-n).join("\n    ");

function cmdImport(catArg, ids, o) {
  const cats = catArg ? [catArg] : ["heroes", "props", "skins"];
  if (cats.some((c) => !STAGES[c])) fail("import の対象は heroes | props | skins");
  if (!ids.length && !o.all) fail("取り込む ID を並べるか --all を指定してください");
  if (ids.length && cats.length > 1) fail("ID を指定するときは heroes | props | skins も指定してください");
  if (o.dry) DRY = true;
  const io = o.importOpts;
  if ((io.length !== undefined || io.axis !== undefined) && !cats.includes("props")) fail("--length / --axis は props のみ");
  if ((io.height !== undefined || io.forward !== undefined) && cats.every((c) => c === "props")) fail("--height / --forward は heroes / skins のみ");
  // 正規化の出力は取り込み先の外の一時ディレクトリへ（検査に通ったものだけを取り込み先へ移す）
  let stageRoot = null;
  const stageDir = (a) => {
    if (!stageRoot) {
      stageRoot = fs.mkdtempSync(path.join(os.tmpdir(), "velstria-import-"));
      process.on("exit", () => fs.rmSync(stageRoot, { recursive: true, force: true }));
    }
    const d = path.join(stageRoot, `${a.cat}-${a.id}`);
    fs.mkdirSync(d, { recursive: true });
    return d;
  };
  let okCount = 0;
  let failCount = 0;
  const skipped = [];
  const record = (a, t, patch) => {
    (state.assets[a.key] ||= { stages: {} }).import = { at: now(), out: rel(t.out), ...patch };
    saveState();
  };
  for (const cat of cats) {
    const list = ids.length ? select(cat, ids, o) : manifest.assets[cat];
    for (const a of list) {
      if (a.entry.bodyWorn) {
        // 籠手・爪は本体のメッシュに含め、実行時は Prop として付けない（SkinnedHeroModel.bodyWornGear）
        if (ids.length || o.dry) log(`${a.key}: 本体に含める装着物（bodyWorn）なので取り込みません`);
        continue;
      }
      const t = importTarget(a);
      const script = path.join(BLENDER_SCRIPTS, t.script);
      const report = path.join(assetDir(a), "import_report.json");
      const verifyLog = path.join(assetDir(a), "import_verify.log");
      const normLog = path.join(assetDir(a), "import_normalize.log");
      const extra = [];
      const pp = cat === "props" ? propParams(a, io) : null;
      if (cat === "props") {
        extra.push("--grip", String(pp.grip));
        if (io.length !== undefined) extra.push("--length", String(io.length));
        if (pp.axis !== undefined) extra.push("--axis", pp.axis);
        // 正面・回転・符号の確認は assets.json（+ source.json の出どころ）の値（= 形式で渡す。"-90" や "-x" を値として読ませるため）。
        // Meshy の GLB は正面が +Z、Tripo は +X（normalize_prop.py の既定）
        if (pp.front !== undefined) extra.push(`--front=${pp.front}`);
        if (pp.yaw !== undefined) extra.push(`--yaw=${Number(pp.yaw)}`);
        if (pp.side !== undefined) extra.push(`--side=${pp.side}`);
        if (pp.provider !== "tripo") log(`${a.key}: model.glb は ${pp.provider} 製（source.json）→ front ${pp.front ?? "+x"}`);
      } else {
        if (io.height !== undefined) extra.push("--height", String(io.height));
        if (io.forward !== undefined) extra.push("--forward", io.forward);
      }
      if (io.textureSize !== undefined) extra.push("--texture-size", String(io.textureSize));
      if (io.maxFaces !== undefined) extra.push("--max-faces", String(io.maxFaces));
      const vargs = verifyArgs(a, io, pp);
      if (!fs.existsSync(t.input)) {
        if (ids.length || o.dry) log(`${a.key}: 入力がありません（${rel(t.input)}）→ スキップ`);
        skipped.push(a.key);
        if (!o.dry) continue;
      }
      const blenderArgs = (staged) => ["-b", "--factory-startup", "--python-exit-code", "1", "--python", script, "--",
        "--in", t.input, "--out", staged, ...extra, "--report", report];
      if (o.dry) {
        const staged = path.join(os.tmpdir(), "velstria-import-XXXXXX", `${a.cat}-${a.id}`, path.basename(t.out));
        log(`[dry-run] ${a.key} → ${rel(t.out)}`);
        log(`  1. 正規化: ${[BLENDER, ...blenderArgs(staged)].map(shq).join(" ")}`);
        log(`  2. 検査:   ${[VERIFY_BIN, staged, ...vargs].map(shq).join(" ")}`
          + (verifierFresh() ? "" : `\n           （${rel(VERIFY_BIN)} は未作成か古い: 実行時に ${SWIFTC} -O ${rel(VERIFY_SRC)} でコンパイル）`));
        log(`  3. 終了コード 0 なら ${rel(t.out)} へ rename（不合格なら既存のファイルはそのまま）`);
        if (!fs.existsSync(script)) log(`  注意: ${rel(script)} がまだありません`);
        continue;
      }
      if (!fs.existsSync(script)) fail(`Blender 正規化スクリプトがありません: ${rel(script)}`);
      if (!fs.existsSync(BLENDER)) fail(`Blender が見つかりません: ${BLENDER}（環境変数 BLENDER で指定）`);
      const verifier = verifierCommand();
      const staged = path.join(stageDir(a), path.basename(t.out));
      fs.mkdirSync(assetDir(a), { recursive: true });
      fs.rmSync(report, { force: true }); // 前回のレポートを今回の結果と取り違えない
      log(`${a.key}: ${rel(t.input)} → ${rel(t.out)}`);
      const t0 = Date.now();
      const r = spawnSync(BLENDER, blenderArgs(staged), { encoding: "utf8", maxBuffer: 256 << 20, timeout: 20 * 60_000 });
      const nout = `${r.stdout || ""}\n${r.stderr || ""}`;
      fs.writeFileSync(normLog, nout);
      if (!(r.status === 0 && fs.existsSync(staged) && fs.statSync(staged).size > 0)) {
        let reported = false;
        try { reported = JSON.parse(fs.readFileSync(report, "utf8")).errors?.length > 0; } catch { /* レポートなし */ }
        // 正規化が理由をレポートの errors に書いていればそれを、無ければログの末尾を出す
        log(`  正規化で不合格（終了コード ${r.status ?? r.signal ?? r.error?.code}）。${fs.existsSync(t.out) ? "既存のファイルはそのまま" : "取り込みなし"}`
          + (reported ? "" : `:\n    ${tail(nout, 25)}`));
        if (reported) printReport(report);
        log(`    全文: ${rel(normLog)}`);
        record(a, t, { status: "failed", stage: "normalize", report: rel(report), log: rel(normLog) });
        failCount++;
        continue;
      }
      const v = spawnSync(verifier[0], [...verifier.slice(1), staged, ...vargs],
        { encoding: "utf8", maxBuffer: 64 << 20, timeout: 10 * 60_000 });
      const vout = `${v.stdout || ""}\n${v.stderr || ""}`;
      fs.writeFileSync(verifyLog, `$ ${[...verifier, staged, ...vargs].map(shq).join(" ")}\n${vout}`);
      if (v.status !== 0) {
        const fails = vout.split("\n").filter((l) => l.startsWith("FAIL"));
        const rejected = path.join(assetDir(a), `rejected_${path.basename(t.out)}`);
        fs.copyFileSync(staged, rejected);
        log(`  検査で不合格（終了コード ${v.status ?? v.signal ?? v.error?.code}）。${fs.existsSync(t.out) ? "既存のファイルはそのまま" : "取り込みなし"}:\n    `
          + (fails.length ? [...fails, ...vout.split("\n").filter((l) => l.startsWith("RESULT"))].join("\n    ") : tail(vout, 25)));
        log(`    全文: ${rel(verifyLog)}、不合格の出力: ${rel(rejected)}`);
        printReport(report);
        record(a, t, { status: "failed", stage: "verify", report: rel(report), verifyLog: rel(verifyLog), rejected: rel(rejected) });
        failCount++;
        continue;
      }
      installAtomically(staged, t.out);
      const checks = vout.split("\n").filter((l) => l.startsWith("PASS")).length;
      log(`  OK ${fmtBytes(fs.statSync(t.out).size)}、検査 PASS ${checks} 項目、${elapsed(t0)}`);
      printReport(report);
      record(a, t, { status: "success", report: rel(report), log: rel(normLog), verifyLog: rel(verifyLog), ...(pp ? { provider: pp.provider } : {}) });
      okCount++;
    }
  }
  if (o.dry) return;
  log(`\n取り込み: 成功 ${okCount}、失敗 ${failCount}${skipped.length ? `、入力なしでスキップ ${skipped.length}` : ""}`);
  if (failCount) process.exitCode = 1;
}

// MARK: - main

function usage() {
  console.log(`Tripo v3 パイプライン（VELSTRIA/ で実行）
  node tools/tripo.mjs balance                                    残高（無料 API）
  node tools/tripo.mjs estimate [heroes|props|skins|all] [ids...] [--concept-source fullbody]
                                                                   見積り（credits と USD、残高と比較）
  node tools/tripo.mjs run heroes [H001 ...|--all] [--until concept|model|rigcheck|rig] [--faces N] [--concept-source fullbody]
                                                                   コンセプト → モデル(P1) → rig-check → リグ
                                                                   （--concept-source fullbody: コンセプトを Tripo で作らず
                                                                   ${rel(HEROREF_DIR)}/<ID>/fullbody.png を写し（0 credits）、
                                                                   POST /files で上げて image-to-model の input にする。
                                                                   前回と違う画像なら model 以降を作り直す）
  node tools/tripo.mjs run props  [<kind> ...|--all] [--include-optional] [--faces N] [--replace-meshy]
                                                                   コンセプト → モデル(P1, 画像の向きに合わせる)
  node tools/tripo.mjs run skins  [<cosmeticID> ...|--all] [--style-image]
                                                                   ヒーローのモデルに再テクスチャ → リグ
                                                                   （--style-image: ヒーローのコンセプトを style_image に添える）
      共通: --dry-run          送信内容と出力先を表示するだけ（有料 API・state.json に触れない）
            --max-credits N    このランで使う上限（見積りベース）
            --force <stage>    指定段階（以降）を作り直す（カンマ区切り可、all で全段階）
            --concurrency N    同時に進めるタスク数（既定 3。画像生成は常に 1 本ずつ）
            --allow-partial    残高が見積りに満たなくても始める（尽きたら送信を止める）
            --replace-meshy    props: tools/meshy.mjs が置いた model.glb（source.json）を Tripo の model で上書きしてよい
  node tools/tripo.mjs status                                     全アセット × 段階の状態・消費・ローカルファイル
  node tools/tripo.mjs task <task_id>                             タスクの生 JSON
  node tools/tripo.mjs import [heroes|props|skins] [ids...|--all] [--dry-run] [--texture-size PX] [--max-faces N]
        ヒーロー・スキン: [--height M] [--forward auto|+x|-x|+z|-z]   Prop: [--length M] [--axis auto|up|pca|vertical]
                                                                   Blender で一時ファイルへ正規化 → verify_usdz で検査
                                                                   → 合格したものだけ ${rel(RES_DIR)}/ へ（不合格は旧版のまま）

  置き場所の上書き（取り込みの試験用）: TRIPO_STATE_DIR（state.json）・TRIPO_BUILD_DIR（${rel(BUILD_DIR)}）・
    TRIPO_RESOURCES_DIR（${rel(RES_DIR)}）・HEROREF_BUILD_DIR（--concept-source の画像。${rel(HEROREF_DIR)}）

  API キー: TRIPO_API_KEY または ~/.config/tripo/api_key（リポジトリに置かない）
  クレジット購入・API キー管理: ${PURCHASE_URL}`);
}

const [cmd, ...rest] = process.argv.slice(2);
const o = parseArgs(rest);
if (!cmd || cmd === "help" || o.help) { usage(); process.exit(cmd && cmd !== "help" && !o.help ? 1 : 0); }

if (o.conceptSource && cmd !== "run" && cmd !== "estimate") fail("--concept-source は run / estimate のみ");

try {
  if ((cmd === "run" || cmd === "import") && !o.dry) lockState();
  switch (cmd) {
    case "balance": {
      const b = await getBalance();
      log(`残高 ${fmtCredits(b.balance)} credits（${usd(b.balance)}）、凍結 ${fmtCredits(b.frozen)}（実行中タスクの確保分）`);
      if (b.balance <= 0) log(`  クレジットがありません。購入: ${PURCHASE_URL}`);
      break;
    }
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
      if (!o.pos[0]) fail("task_id を指定してください");
      let t;
      try {
        t = await api("GET", `/tasks/${encodeURIComponent(o.pos[0])}`);
      } catch (e) {
        if (taskNotFound(e)) fail(`${e.message}\n  ${NOT_FOUND_WHY}（作ったときのキーで問い合わせてください）`);
        throw e;
      }
      console.log(JSON.stringify(t, null, 2));
      break;
    }
    case "import":
      cmdImport(o.pos[0], o.pos.slice(1), o);
      break;
    default:
      usage();
      process.exit(1);
  }
} catch (e) {
  fail(e.message);
}
