#!/usr/bin/env node
// ステージ用 3D 素材（「遺跡と森」セット）を Tripo の image-to-model で作る小さなクライアント（依存なし。Node 20+ の標準 fetch）。
// 入力は tools/stage/stage_art.py（STAGE_SET=ruins）が作ったコンセプト画像（build/stage/ruins/art/<id>.png、kind=concept）。
// 出力は build/stage/ruins/tripo/<id>/（model.glb・base_color.png・preview.png。git 管理外）。取り込み（Blender で減面・
// 色の焼き付け → アプリ用メッシュ）は tools/stage/stage_bake.py（STAGE_SET=ruins）が行う。
//
// Meshy は 2026-10-11 から無料プランの API でタスクを作れないので、旧セット（tools/stage/stage_meshy.mjs）の代わりにこれを使う。
// API の呼び方は tools/structures/structures.mjs と同じ（Tripo v3、P1 モデル、PBR テクスチャ、光の除去）。
// 状態は tools/stage/tripo_state.json（task_id・状態・消費クレジットのみ。秘密・署名付き URL は書かない）。
//
// キー: env TRIPO_API_KEY か ~/.config/tripo/api_key（リポジトリ・ログ・state には書かない）。
//
// usage（VELSTRIA/ で実行）:
//   node tools/stage/stage_tripo.mjs balance
//   node tools/stage/stage_tripo.mjs run <id ...|--all> [--max-credits N] [--dry-run] [--force]
//   node tools/stage/stage_tripo.mjs extract <id ...|--all>      model.glb から base_color.png を取り出し直す
//   node tools/stage/stage_tripo.mjs status
//
// 安全策: 有料 POST は 429（受け付け前の拒否）以外では再送しない。task_id が記録済みの素材は --force なしでは
// 再送せずポーリングを再開する。--max-credits はこのセットで使った合計（state の記録）に対する上限。
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const SPEC = path.join(ROOT, "tools", "stage", "stage_art_ruins.json");
const STATE = path.join(ROOT, "tools", "stage", "tripo_state.json");
const ART = path.join(ROOT, "build", "stage", "ruins", "art");
const OUT = path.join(ROOT, "build", "stage", "ruins", "tripo");
const API = "https://openapi.tripo3d.ai/v3";
const COST = 60; // P1 + detailed テクスチャの定価。実際の消費はタスクの値を記録する

// 素材ごとの面数（Tripo の生成目標）。端末向けの削減は stage_bake.py で行うので、色を焼き付ける元として多めに取る
const FACES = { default: 20000, bush: 16000 }; // P1 の face_limit は 50〜20000

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

function apiKey() {
  if (process.env.TRIPO_API_KEY) return process.env.TRIPO_API_KEY.trim();
  return fs.readFileSync(path.join(os.homedir(), ".config", "tripo", "api_key"), "utf8").trim();
}

function loadState() {
  try { return JSON.parse(fs.readFileSync(STATE, "utf8")); } catch { return { version: 1, assets: {} }; }
}
function saveState(s) {
  const tmp = `${STATE}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(s, null, 2) + "\n");
  fs.renameSync(tmp, STATE);
}

// 応答本文からキーらしい文字列を消してから表示する
const scrub = (s) => String(s).replace(/(tsk_)[A-Za-z0-9_-]+/g, "$1***");

async function call(method, p, body, { form, paid = false } = {}) {
  const headers = { Authorization: `Bearer ${apiKey()}` };
  let payload;
  if (form) payload = form;
  else if (body !== undefined) { headers["Content-Type"] = "application/json"; payload = JSON.stringify(body); }
  for (let attempt = 1; ; attempt++) {
    let res, text;
    try {
      res = await fetch(API + p, { method, headers, body: payload, signal: AbortSignal.timeout(180_000) });
      text = await res.text();
    } catch (e) {
      // 有料の POST は届いたか分からないので再送しない（state の task_id で再開する）
      if (paid || attempt >= 5) throw e;
      await sleep(3000 * attempt);
      continue;
    }
    // 429 は受け付け前の拒否（課金なし）なので待って再送する
    if (res.status === 429 && attempt < 10) { await sleep(10_000 * attempt); continue; }
    if (res.status >= 500 && method === "GET" && attempt < 5) { await sleep(3000 * attempt); continue; }
    let json = null;
    try { json = JSON.parse(text); } catch { /* 無視 */ }
    if (!res.ok || !json || json.code !== 0) throw new Error(`Tripo ${method} ${p}: HTTP ${res.status} ${scrub(text.slice(0, 400))}`);
    return json.data;
  }
}

async function balance() {
  const d = await call("GET", "/account/balance");
  return Number(d?.balance ?? 0);
}

async function download(url, file) {
  for (let attempt = 1; attempt <= 5; attempt++) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(10 * 60_000) });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const buf = Buffer.from(await res.arrayBuffer());
      fs.writeFileSync(`${file}.part`, buf);
      fs.renameSync(`${file}.part`, file);
      return buf.length;
    } catch (e) {
      if (attempt === 5) throw e;
      await sleep(3000 * attempt);
    }
  }
}

async function upload(file) {
  const form = new FormData();
  form.append("file", new Blob([fs.readFileSync(file)], { type: "image/png" }), path.basename(file));
  const d = await call("POST", "/files", undefined, { form });
  if (!d?.file_token) throw new Error("Tripo: file_token がありません");
  return d.file_token;
}

function modelUrl(output) {
  for (const k of ["pbr_model_url", "model_url", "pbr_model", "model", "base_model_url", "base_model"]) {
    const v = output?.[k];
    const u = typeof v === "string" ? v : v?.url;
    if (typeof u === "string" && u.startsWith("http")) return u;
  }
  return null;
}

/** GLB の最初の材質の baseColorTexture を base_color.png に書き出す（stage_bake.py の焼き付けの元）。 */
function extractBaseColor(dir) {
  const glb = fs.readFileSync(path.join(dir, "model.glb"));
  if (glb.readUInt32LE(0) !== 0x46546c67) throw new Error("GLB ではありません");
  let off = 12, json = null, bin = null;
  while (off < glb.length) {
    const len = glb.readUInt32LE(off), type = glb.readUInt32LE(off + 4);
    const data = glb.subarray(off + 8, off + 8 + len);
    if (type === 0x4e4f534a) json = JSON.parse(data.toString("utf8"));
    else if (type === 0x004e4942) bin = data;
    off += 8 + len;
  }
  const mats = json?.materials ?? [];
  if (mats.length !== 1) log(`${path.basename(dir)}: 材質が ${mats.length} 個（最初の 1 つの色だけを使う）`);
  const ti = mats[0]?.pbrMetallicRoughness?.baseColorTexture?.index;
  if (ti === undefined) throw new Error("baseColorTexture がありません");
  const img = json.images[json.textures[ti].source];
  const bv = json.bufferViews[img.bufferView];
  const bytes = bin.subarray(bv.byteOffset ?? 0, (bv.byteOffset ?? 0) + bv.byteLength);
  const out = path.join(dir, "base_color.png");
  if (img.mimeType === "image/png") {
    fs.writeFileSync(out, bytes);
  } else {
    const tmp = path.join(dir, "base_color_src.jpg");
    fs.writeFileSync(tmp, bytes);
    execFileSync("sips", ["-s", "format", "png", tmp, "--out", out], { stdio: "ignore" });
    fs.unlinkSync(tmp);
  }
  return out;
}

function concepts() {
  return JSON.parse(fs.readFileSync(SPEC, "utf8")).assets.filter((a) => a.kind === "concept").map((a) => a.id);
}

const DONE = ["success"];
const FAILED = ["failed", "cancelled", "banned", "expired"];

async function run(id, state, o) {
  const dir = path.join(OUT, id);
  const png = path.join(ART, `${id}.png`);
  if (!fs.existsSync(png)) { log(`${id}: ${path.relative(ROOT, png)} がありません`); return false; }
  const sha = crypto.createHash("sha256").update(fs.readFileSync(png)).digest("hex");
  const st = state.assets[id] || {};
  if (DONE.includes(st.status) && !o.force && fs.existsSync(path.join(dir, "model.glb"))) { log(`${id}: 完了済み`); return true; }
  let tid = st.task_id;
  if (!tid || o.force || FAILED.includes(st.status)) {
    const spent = Object.values(state.assets).reduce((n, x) => n + (Number(x.credits) || 0) + (x.status === "submitted" ? COST : 0), 0);
    if (o.maxCredits !== undefined && spent + COST > o.maxCredits) {
      log(`${id}: --max-credits ${o.maxCredits} を超えるので送らない（使用 ${spent}）`);
      return false;
    }
    const body = { input: "<concept.png の file_token>", model: "P1-20260311", face_limit: FACES[id] ?? FACES.default,
      texture: true, pbr: true, texture_quality: "detailed", texture_version: "v3.5-20260815", delight: true,
      texture_alignment: "original_image", orientation: "align_image" };
    if (o.dryRun) { log(`${id}: dry-run`, JSON.stringify(body)); return true; }
    const bal = await balance();
    if (bal < COST) throw new Error(`Tripo の残高不足（${bal}）`);
    // request は送信前の写し（file_token は書かない）
    state.assets[id] = { status: "submitting", concept_sha256: sha, request: { ...body }, balance_before: bal,
      submitted_at: new Date().toISOString() };
    saveState(state);
    body.input = await upload(png);
    const d = await call("POST", "/generation/image-to-model", body, { paid: true });
    tid = d?.task_id;
    if (!tid) throw new Error(`${id}: task_id がありません`);
    Object.assign(state.assets[id], { status: "submitted", task_id: tid });
    saveState(state);
    log(`${id}: 送信 ${tid}`);
  }
  let task, last = "";
  for (;;) {
    task = await call("GET", `/tasks/${tid}`);
    const line = `${id}: ${task.status} ${task.progress ?? ""}`;
    if (line !== last) { log(line); last = line; }
    if (DONE.includes(task.status) || FAILED.includes(task.status)) break;
    await sleep(8000);
  }
  const rec = state.assets[id];
  rec.task_id = tid;
  rec.status = String(task.status);
  if (!DONE.includes(task.status)) {
    rec.credits = 0;
    rec.error = scrub(JSON.stringify(task.error ?? task.status)).slice(0, 300);
    saveState(state);
    log(`${id}: 失敗 ${rec.error}`);
    return false;
  }
  rec.credits = Number(task.credits_consumed ?? task.consumed_credits ?? COST);
  const url = modelUrl(task.output);
  if (!url) { rec.status = "no-output"; saveState(state); throw new Error(`${id}: GLB の URL がありません`); }
  fs.mkdirSync(dir, { recursive: true });
  rec.bytes = await download(url, path.join(dir, "model.glb"));
  const prev = task.output?.rendered_image?.url ?? task.output?.rendered_image;
  if (typeof prev === "string" && prev.startsWith("http")) await download(prev, path.join(dir, "preview.png")).catch(() => {});
  extractBaseColor(dir);
  rec.completed_at = new Date().toISOString();
  saveState(state);
  log(`${id}: 完了 ${rec.credits} credits → ${path.relative(ROOT, path.join(dir, "model.glb"))}`);
  return true;
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const o = { dryRun: rest.includes("--dry-run"), force: rest.includes("--force") };
  const mi = rest.indexOf("--max-credits");
  if (mi >= 0) o.maxCredits = Number(rest[mi + 1]);
  let ids = rest.filter((x, i) => !x.startsWith("--") && !(i > 0 && rest[i - 1] === "--max-credits"));
  if (rest.includes("--all")) ids = concepts();
  switch (cmd) {
    case "balance": log(`Tripo ${await balance()} credits`); return;
    case "run": {
      const state = loadState();
      const errs = [];
      const ok = await Promise.all(ids.map((id) => run(id, state, o).catch((e) => { errs.push(e); console.error(scrub(e.message)); return false; })));
      saveState(state);
      process.exitCode = ok.every(Boolean) && !errs.length ? 0 : 1;
      return;
    }
    case "extract": for (const id of ids) log(`${id}: ${path.relative(ROOT, extractBaseColor(path.join(OUT, id)))}`); return;
    case "status": {
      const state = loadState();
      let total = 0;
      for (const id of concepts()) {
        const st = state.assets[id] || {};
        total += Number(st.credits) || 0;
        const c = fs.existsSync(path.join(ART, `${id}.png`)) ? "concept" : "-";
        const m = fs.existsSync(path.join(OUT, id, "model.glb")) ? "glb" : "-";
        log(`${id.padEnd(14)} ${c.padEnd(8)} ${(st.status || "-").padEnd(10)} ${String(st.credits ?? "").padEnd(4)} ${m}`);
      }
      log(`使用合計 ${total} credits`);
      return;
    }
    default:
      log(fs.readFileSync(fileURLToPath(import.meta.url), "utf8").split("\n").slice(1, 19).join("\n"));
  }
}

main().catch((e) => { console.error(scrub(e.stack || e.message)); process.exit(1); });
