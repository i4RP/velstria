#!/usr/bin/env node
// タワー・本拠地のクリスタル・ミニオンの 3D モデルを 概念画像 → 3D 生成 → Blender で減面・正規化 → USDZ にして
// App/Resources/Structures/ へ置く（依存なし。Node 20+ の標準 fetch）。
// 仕様（プロンプト・面数・寸法）は tools/structures/structures.json、進捗は tools/structures/state.json（task_id・状態・
// 消費クレジットのみ。秘密は含まない）。画像・GLB は build/structures/<id>/（git 管理外）。
//
// キー: Tripo は env TRIPO_API_KEY か ~/.config/tripo/api_key、Meshy は env MESHY_API_KEY か ~/.config/meshy/api_key。
// リポジトリは公開なので、キーはファイル・ログ・state.json に書かない。
//
// usage（VELSTRIA/ で実行）:
//   node tools/structures/structures.mjs balance                       Tripo / Meshy の残高（無料）
//   node tools/structures/structures.mjs concept <id...|all> [--tag t] Codex の画像生成で build/structures/<id>/concept[_t].png
//   node tools/structures/structures.mjs select <id> <tag>             concept_<tag>.png を採用版 concept.png にする
//   node tools/structures/structures.mjs model <id...|all> [--dry-run] [--force] [--max-credits N]
//                                                                       concept.png から 3D 生成 → build/structures/<id>/model.glb
//   node tools/structures/structures.mjs bake <id...|all>               Blender（tools/structures/structures_bake.py）で
//                                                                       App/Resources/Structures/Struct_<id>.usdz と赤チームのテクスチャ
//   node tools/structures/structures.mjs status
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn, spawnSync, execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const SPEC_PATH = path.join(ROOT, "tools", "structures", "structures.json");
const STATE_PATH = path.join(ROOT, "tools", "structures", "state.json");
const BUILD = path.join(ROOT, "build", "structures");
const RES = path.join(ROOT, "App", "Resources", "Structures");
const BAKE = path.join(ROOT, "tools", "structures", "structures_bake.py");
const BLENDER = process.env.BLENDER || "/Applications/Blender.app/Contents/MacOS/Blender";
const CODEX_MODEL = process.env.STRUCT_CODEX_MODEL || "gpt-6-astra";
const CODEX_SLOTS = Number(process.env.STRUCT_CODEX_SLOTS || 4);

const TRIPO = "https://openapi.tripo3d.ai/v3";
const MESHY = "https://api.meshy.ai";
// 見積り（定価）: Tripo P1 + HD テクスチャ 60（標準テクスチャ 50）、Meshy smart-topology meshy-t2 + 2K テクスチャ 15。
// Meshy は 2026-10-11 時点で無料プランの API からタスクを作れない（HTTP 402 NoMorePendingTasks）ので、全て Tripo で作った
const COST = { tripo: 60, meshy: 15 };
const costOf = (a) => (a.provider === "tripo" && a.textureQuality === "standard" ? 50 : COST[a.provider]);

const log = (...a) => console.log(...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const spec = () => JSON.parse(fs.readFileSync(SPEC_PATH, "utf8"));
const loadState = () => (fs.existsSync(STATE_PATH) ? JSON.parse(fs.readFileSync(STATE_PATH, "utf8")) : { assets: {} });
function saveState(s) {
  fs.writeFileSync(`${STATE_PATH}.tmp`, JSON.stringify(s, null, 2) + "\n");
  fs.renameSync(`${STATE_PATH}.tmp`, STATE_PATH);
}
const dirOf = (id) => path.join(BUILD, id);

function key(kind) {
  const env = kind === "tripo" ? "TRIPO_API_KEY" : "MESHY_API_KEY";
  let k = (process.env[env] || "").trim();
  const file = path.join(os.homedir(), ".config", kind, "api_key");
  if (!k && fs.existsSync(file)) k = fs.readFileSync(file, "utf8").trim();
  if (!k) throw new Error(`${kind} の API キーがありません（${env} か ${file}）`);
  return k;
}

// 応答本文からキーらしい文字列を消してから表示する
const scrub = (s) => String(s).replace(/(tsk_|msy_)[A-Za-z0-9_-]+/g, "$1***");

async function call(kind, method, p, body, { form } = {}) {
  const headers = { Authorization: `Bearer ${key(kind)}` };
  let payload;
  if (form) payload = form;
  else if (body !== undefined) { headers["Content-Type"] = "application/json"; payload = JSON.stringify(body); }
  const base = kind === "tripo" ? TRIPO : MESHY;
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(base + p, { method, headers, body: payload, signal: AbortSignal.timeout(180_000) });
    const text = await res.text();
    // 429 は受け付け前の拒否（課金なし）なので待って再送する
    if (res.status === 429 && attempt < 10) { await sleep(10_000 * attempt); continue; }
    if (res.status >= 500 && method === "GET" && attempt < 5) { await sleep(3000 * attempt); continue; }
    let json = null;
    try { json = JSON.parse(text); } catch { /* 無視 */ }
    if (kind === "tripo") {
      if (!res.ok || !json || json.code !== 0) throw new Error(`Tripo ${method} ${p}: HTTP ${res.status} ${scrub(text.slice(0, 400))}`);
      return json.data;
    }
    if (!res.ok || !json) throw new Error(`Meshy ${method} ${p}: HTTP ${res.status} ${scrub(text.slice(0, 400))}`);
    return json;
  }
}

async function balances() {
  const t = await call("tripo", "GET", "/account/balance");
  const m = await call("meshy", "GET", "/openapi/v1/balance");
  return { tripo: Number(t?.balance ?? 0), meshy: Number(m?.balance ?? 0) };
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

// MARK: - 概念画像（Codex）

let codexRunning = 0;
const codexWaiters = [];
async function codexSlot() {
  if (codexRunning < CODEX_SLOTS) { codexRunning++; return; }
  await new Promise((r) => codexWaiters.push(r));
  codexRunning++;
}
function codexRelease() {
  codexRunning--;
  const next = codexWaiters.shift();
  if (next) next();
}

function promptFor(s, a) {
  return `${s.style}\n\nObject: ${a.prompt}`;
}

async function concept(s, a, tag) {
  const dir = dirOf(a.id);
  fs.mkdirSync(dir, { recursive: true });
  const out = path.join(dir, tag ? `concept_${tag}.png` : "concept.png");
  const ref = a.useStyleReference && s.styleReference && fs.existsSync(s.styleReference) ? s.styleReference : null;
  const instruction =
    "Use your built-in image generation tool to create exactly ONE image from the prompt below"
    + (ref ? " (the attached image is only a loose mood/style reference for materials and colors; design a new original object, keep the plain background)" : "")
    + `. When it is done, copy the generated PNG file to ${out} (overwrite if it exists).`
    + " Do not modify the image and do not create any other files. Reply only with the output path."
    + "\n\n=== IMAGE PROMPT ===\n" + promptFor(s, a);
  // 作業ディレクトリは固定（Codex は -C の場所を ~/.codex/config.toml の trusted に登録するため）
  const work = path.join(BUILD, ".codex-work");
  fs.mkdirSync(work, { recursive: true });
  for (let attempt = 1; attempt <= 3; attempt++) {
    if (fs.existsSync(out)) fs.unlinkSync(out);
    await codexSlot();
    let tail = "";
    try {
      const args = ["exec", "--skip-git-repo-check", "--ephemeral", "--dangerously-bypass-approvals-and-sandbox",
        "-m", CODEX_MODEL, "-c", 'model_reasoning_effort="low"', "-C", work];
      if (ref) args.push("-i", ref);
      tail = await new Promise((resolve) => {
        const p = spawn("codex", args, { stdio: ["pipe", "pipe", "pipe"] });
        let buf = "";
        p.stdout.on("data", (d) => { buf += d; });
        p.stderr.on("data", (d) => { buf += d; });
        const timer = setTimeout(() => p.kill("SIGTERM"), 15 * 60_000);
        p.on("close", (code) => { clearTimeout(timer); resolve(`exit ${code}: ${buf.slice(-600)}`); });
        // -i は値を複数取るのでプロンプトは stdin で渡す
        p.stdin.end(instruction);
      });
    } finally {
      codexRelease();
    }
    const data = fs.existsSync(out) ? fs.readFileSync(out) : Buffer.alloc(0);
    if (data.length > 8 && data[0] === 0x89 && data.toString("latin1", 1, 4) === "PNG") {
      log(`${a.id}: ${path.relative(ROOT, out)}`);
      return out;
    }
    console.error(`${a.id}: 試行 ${attempt} 失敗 (${tail})`);
    await sleep(5000 * attempt);
  }
  console.error(`${a.id}: 生成に失敗`);
  return null;
}

// MARK: - 3D 生成

function jpegDataUri(png) {
  const jpg = path.join(os.tmpdir(), `struct_${path.basename(path.dirname(png))}.jpg`);
  execFileSync("sips", ["-s", "format", "jpeg", "-s", "formatOptions", "92", png, "--out", jpg], { stdio: "ignore" });
  return `data:image/jpeg;base64,${fs.readFileSync(jpg).toString("base64")}`;
}

async function tripoUpload(file) {
  const buf = fs.readFileSync(file);
  const form = new FormData();
  form.append("file", new Blob([buf], { type: "image/png" }), path.basename(file));
  const d = await call("tripo", "POST", "/files", undefined, { form });
  if (!d?.file_token) throw new Error("Tripo: file_token がありません");
  return d.file_token;
}

function tripoUrl(output) {
  for (const k of ["pbr_model_url", "model_url", "pbr_model", "model", "base_model_url", "base_model"]) {
    const v = output?.[k];
    const u = typeof v === "string" ? v : v?.url;
    if (typeof u === "string" && u.startsWith("http")) return u;
  }
  return null;
}

async function model(a, state, o) {
  const st = state.assets[a.id] || {};
  const dir = dirOf(a.id);
  const png = path.join(dir, "concept.png");
  if (!fs.existsSync(png)) { log(`${a.id}: concept.png がありません`); return; }
  const sha = crypto.createHash("sha256").update(fs.readFileSync(png)).digest("hex");
  if (st.status === "success" && !o.force) { log(`${a.id}: 完了済み`); return; }
  let tid = st.task_id;
  const provider = a.provider;
  if (!tid || o.force || ["failed", "FAILED", "CANCELED", "cancelled", "banned", "expired"].includes(st.status)) {
    const cost = costOf(a);
    const spent = Object.values(state.assets).filter((x) => x.provider === provider)
      .reduce((n, x) => n + (Number(x.credits) || 0) + (x.status === "submitted" ? COST[provider] : 0), 0);
    if (o.maxCredits !== undefined && spent + cost > o.maxCredits) { log(`${a.id}: --max-credits ${o.maxCredits} を超えるので送らない（${provider} 使用 ${spent}）`); return; }
    const body = provider === "tripo"
      ? { input: "<concept.png の file_token>", model: "P1-20260311", face_limit: a.faces, texture: true, pbr: true,
        texture_quality: a.textureQuality || "detailed", texture_version: "v3.5-20260815", delight: true, texture_alignment: "original_image",
        orientation: "align_image" }
      : { image_url: "<concept.png の JPEG data URI>", model_type: "smart-topology", ai_model: "meshy-t2",
        target_polycount: a.faces, should_texture: true, enable_pbr: true, texture_resolution: "2k", target_formats: ["glb"] };
    if (o.dryRun) { log(`${a.id}: dry-run ${provider}`, JSON.stringify(body)); return; }
    const bal = await balances();
    if (bal[provider] < cost) throw new Error(`${provider} の残高不足（${bal[provider]}）`);
    // request は送信前の写し（file_token・data URI は書かない）
    state.assets[a.id] = { provider, status: "submitting", concept_sha256: sha, request: { ...body }, balance_before: bal[provider],
      submitted_at: new Date().toISOString() };
    saveState(state);
    if (provider === "tripo") {
      body.input = await tripoUpload(png);
      const d = await call("tripo", "POST", "/generation/image-to-model", body);
      tid = d?.task_id;
    } else {
      body.image_url = jpegDataUri(png);
      const d = await call("meshy", "POST", "/openapi/v1/image-to-3d", body);
      tid = d?.result;
    }
    if (!tid) throw new Error(`${a.id}: task_id がありません`);
    Object.assign(state.assets[a.id], { status: "submitted", task_id: tid });
    saveState(state);
    log(`${a.id}: ${provider} 送信 ${tid}`);
  }
  // ポーリング
  let task;
  let last = "";
  for (;;) {
    task = provider === "tripo" ? await call("tripo", "GET", `/tasks/${tid}`) : await call("meshy", "GET", `/openapi/v1/image-to-3d/${tid}`);
    const status = String(task.status);
    const line = `${a.id}: ${status} ${task.progress ?? ""}`;
    if (line !== last) { log(line); last = line; }
    if (["success", "SUCCEEDED", "failed", "FAILED", "cancelled", "CANCELED", "banned", "expired"].includes(status)) break;
    await sleep(8000);
  }
  const rec = state.assets[a.id];
  rec.task_id = tid;
  const ok = task.status === "success" || task.status === "SUCCEEDED";
  rec.status = ok ? "success" : String(task.status);
  rec.credits = ok ? Number(task.credits_consumed ?? task.consumed_credits ?? COST[provider]) : 0;
  if (!ok) { rec.error = scrub(JSON.stringify(task.error ?? task.task_error ?? task.status)).slice(0, 300); saveState(state); log(`${a.id}: 失敗 ${rec.error}`); return; }
  const url = provider === "tripo" ? tripoUrl(task.output) : task.model_urls?.glb;
  if (!url) { rec.status = "no-output"; saveState(state); throw new Error(`${a.id}: GLB の URL がありません`); }
  rec.bytes = await download(url, path.join(dir, "model.glb"));
  const prev = provider === "tripo" ? (task.output?.rendered_image?.url ?? task.output?.rendered_image) : task.thumbnail_url;
  if (typeof prev === "string" && prev.startsWith("http")) await download(prev, path.join(dir, "preview.png")).catch(() => {});
  rec.completed_at = new Date().toISOString();
  saveState(state);
  log(`${a.id}: 完了 ${rec.credits} credits → ${path.relative(ROOT, path.join(dir, "model.glb"))}`);
}

// MARK: - bake

function bake(a) {
  const glb = path.join(dirOf(a.id), "model.glb");
  if (!fs.existsSync(glb)) { log(`${a.id}: model.glb がありません`); return false; }
  fs.mkdirSync(RES, { recursive: true });
  const r = spawnSync(BLENDER, ["-b", "--factory-startup", "-noaudio", "--python", BAKE, "--",
    "--id", a.id, "--glb", glb, "--out", RES, "--work", dirOf(a.id), "--faces", String(a.faces),
    "--size", JSON.stringify(a.size)], { encoding: "utf8", maxBuffer: 64 << 20 });
  const out = (r.stdout || "") + (r.stderr || "");
  const lines = out.split("\n").filter((l) => l.startsWith("[bake]") || /Error|Traceback/.test(l));
  for (const l of lines) log(l);
  if (r.status !== 0) { log(out.slice(-3000)); return false; }
  return true;
}

// MARK: - main

function pick(s, ids) {
  if (ids.includes("all")) return s.assets;
  return ids.map((id) => s.assets.find((a) => a.id === id) ?? (() => { throw new Error(`unknown id: ${id}`); })());
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const flags = { dryRun: rest.includes("--dry-run"), force: rest.includes("--force") };
  const mi = rest.indexOf("--max-credits");
  if (mi >= 0) flags.maxCredits = Number(rest[mi + 1]);
  const ti = rest.indexOf("--tag");
  const tag = ti >= 0 ? rest[ti + 1] : null;
  const ids = rest.filter((x, i) => !x.startsWith("--") && !(i > 0 && ["--max-credits", "--tag"].includes(rest[i - 1])));
  const s = spec();
  switch (cmd) {
    case "balance": { const b = await balances(); log(`Tripo ${b.tripo} credits / Meshy ${b.meshy} credits`); return; }
    case "concept": { const r = await Promise.all(pick(s, ids).map((a) => concept(s, a, tag))); process.exitCode = r.every(Boolean) ? 0 : 1; return; }
    case "select": {
      const [id, t] = ids;
      fs.copyFileSync(path.join(dirOf(id), `concept_${t}.png`), path.join(dirOf(id), "concept.png"));
      log(`${id}: concept_${t}.png → concept.png`);
      return;
    }
    case "model": {
      const state = loadState();
      const errs = [];
      await Promise.all(pick(s, ids).map((a) => model(a, state, flags).catch((e) => { errs.push(e); console.error(scrub(e.message)); })));
      saveState(state);
      process.exitCode = errs.length ? 1 : 0;
      return;
    }
    case "bake": { const ok = pick(s, ids).map(bake); process.exitCode = ok.every(Boolean) ? 0 : 1; return; }
    case "status": {
      const state = loadState();
      for (const a of s.assets) {
        const st = state.assets[a.id] || {};
        const c = fs.existsSync(path.join(dirOf(a.id), "concept.png")) ? "concept" : "-";
        const m = fs.existsSync(path.join(dirOf(a.id), "model.glb")) ? "glb" : "-";
        const u = fs.existsSync(path.join(RES, `Struct_${a.id}.usdz`)) ? "usdz" : "-";
        log(`${a.id.padEnd(14)} ${a.provider.padEnd(6)} ${c.padEnd(8)} ${(st.status || "-").padEnd(10)} ${String(st.credits ?? "").padEnd(4)} ${m.padEnd(4)} ${u}`);
      }
      return;
    }
    default:
      log(fs.readFileSync(fileURLToPath(import.meta.url), "utf8").split("\n").slice(1, 20).join("\n"));
  }
}

main().catch((e) => { console.error(scrub(e.stack || e.message)); process.exit(1); });
