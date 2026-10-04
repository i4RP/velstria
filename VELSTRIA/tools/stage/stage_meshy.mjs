#!/usr/bin/env node
// ステージ用 3D 素材を Meshy の Image to 3D で作る小さなクライアント（依存なし。Node 20+ の標準 fetch）。
// 入力は tools/stage/stage_art.py が作ったコンセプト画像（build/stage/art/<id>.png、kind=concept の素材）。
// 出力は build/stage/meshy/<id>/（model.glb・テクスチャ・thumbnail。git 管理外）。取り込み（Blender で正規化 →
// アプリ用メッシュ）は tools/stage/stage_bake.py が行う。
//
// ヒーロー用の tools/meshy.mjs とは別物（state も別: tools/stage/meshy_state.json）。同じアカウントの
// クレジットと同時実行枠を共有するので、--max-credits で上限を決めて流す（2026-10-05 の取り決め: ステージは 300 まで）。
//
// 環境変数: MESHY_API_KEY（省略時 ~/.config/meshy/api_key。リポジトリ・ログ・state には書かない）
//
// usage（VELSTRIA/ で実行）:
//   node tools/stage/stage_meshy.mjs balance
//   node tools/stage/stage_meshy.mjs run <id ...|--all> [--max-credits N] [--dry-run] [--force]
//   node tools/stage/stage_meshy.mjs status
//
// 安全策: 有料 POST は 429（受け付け前の拒否）以外では再送しない。task_id が記録済みの素材は --force なしでは
// 再送せずポーリングを再開する。署名付き URL は state にもログにも残さない。
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const SPEC = path.join(ROOT, "tools", "stage", "stage_art.json");
const STATE = path.join(ROOT, "tools", "stage", "meshy_state.json");
const ART = path.join(ROOT, "build", "stage", "art");
const OUT = path.join(ROOT, "build", "stage", "meshy");
const API = "https://api.meshy.ai";
const COST = 30; // Image to 3D（latest）+ テクスチャ。実際の消費はタスクの値を記録する

// 素材ごとのポリゴン数（Meshy のリメッシュ目標。端末向けの削減は stage_bake.py で行うので多めに取る）
const POLY = { default: 12000 };

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

function apiKey() {
  if (process.env.MESHY_API_KEY) return process.env.MESHY_API_KEY.trim();
  return fs.readFileSync(path.join(os.homedir(), ".config", "meshy", "api_key"), "utf8").trim();
}

function loadState() {
  try { return JSON.parse(fs.readFileSync(STATE, "utf8")); } catch { return { version: 1, assets: {} }; }
}
function saveState(s) {
  const tmp = `${STATE}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(s, null, 2) + "\n");
  fs.renameSync(tmp, STATE);
}

async function call(method, p, body, { paid = false } = {}) {
  for (let attempt = 1; ; attempt++) {
    let res, json;
    try {
      res = await fetch(API + p, {
        method,
        headers: { Authorization: `Bearer ${apiKey()}`, ...(body ? { "Content-Type": "application/json" } : {}) },
        body: body ? JSON.stringify(body) : undefined,
        signal: AbortSignal.timeout(120_000),
      });
      json = await res.json().catch(() => null);
    } catch (e) {
      if (paid) throw new Error(`送信結果が不明（${e.message}）。state を確認してから --force で再送`);
      if (attempt >= 6) throw e;
      await sleep(2000 * attempt);
      continue;
    }
    if (res.ok) return json;
    const msg = json?.message || JSON.stringify(json);
    if (res.status === 429 && /NoMoreConcurrentTasks/i.test(msg) && paid) {
      // 同時実行枠（ヒーロー側と共有）または残高切れ。受け付け前の拒否なので待って再送してよい
      if (attempt >= 40) throw new Error(`429 が続く: ${msg}`);
      log(`  429（${msg.slice(0, 80)}）→ 30 秒待って再送`);
      await sleep(30_000);
      continue;
    }
    if ((res.status === 429 || res.status >= 500) && attempt < 8) {
      if (paid && res.status >= 500) throw new Error(`HTTP ${res.status}（送信結果が不明）: ${msg}`);
      await sleep(Math.min(60_000, 2000 * 2 ** attempt));
      continue;
    }
    throw new Error(`HTTP ${res.status} ${method} ${p}: ${msg}`);
  }
}

function concepts() {
  return JSON.parse(fs.readFileSync(SPEC, "utf8")).assets.filter((a) => a.kind === "concept");
}

function dataUri(id) {
  const png = path.join(ART, `${id}.png`);
  if (!fs.existsSync(png)) throw new Error(`コンセプト画像がない: ${png}`);
  // PNG のままだと data URI が大きいので JPEG（品質 92）に変換して送る
  const jpg = path.join(os.tmpdir(), `stage_meshy_${id}.jpg`);
  execFileSync("sips", ["-s", "format", "jpeg", "-s", "formatOptions", "92", png, "--out", jpg], { stdio: "ignore" });
  const buf = fs.readFileSync(jpg);
  return { uri: `data:image/jpeg;base64,${buf.toString("base64")}`, sha: crypto.createHash("sha256").update(fs.readFileSync(png)).digest("hex") };
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

async function runOne(a, state, opts) {
  const st = state.assets[a.id] || {};
  if (st.status === "SUCCEEDED" && !opts.force) { log(`${a.id}: 完了済み`); return; }
  let taskId = st.task_id;
  if (!taskId || opts.force) {
    const balance = (await call("GET", "/openapi/v1/balance")).balance;
    const spent = Object.values(state.assets).reduce((s, x) => s + (x.credits || 0), 0) + (state.inflight || 0);
    if (spent + COST > opts.maxCredits) { log(`${a.id}: 上限 ${opts.maxCredits} を超えるので送らない（使用 ${spent}）`); return; }
    if (balance < COST) throw new Error(`残高不足（${balance}）`);
    const { uri, sha } = dataUri(a.id);
    const body = {
      image_url: uri, ai_model: "latest", should_texture: true, enable_pbr: true, texture_resolution: "2k",
      should_remesh: true, topology: "triangle", target_polycount: POLY[a.id] || POLY.default,
    };
    if (opts.dryRun) { log(`${a.id}: dry-run`, JSON.stringify({ ...body, image_url: `<jpeg ${uri.length} chars sha ${sha.slice(0, 12)}>` })); return; }
    state.assets[a.id] = { status: "submitting", input_sha256: sha, request: { ...body, image_url: `build/stage/art/${a.id}.png` }, balance_before: balance };
    state.inflight = (state.inflight || 0) + COST;
    saveState(state);
    const res = await call("POST", "/openapi/v1/image-to-3d", body, { paid: true });
    taskId = res.result;
    Object.assign(state.assets[a.id], { status: "PENDING", task_id: taskId, submitted_at: new Date().toISOString() });
    state.inflight -= COST;
    saveState(state);
    log(`${a.id}: 送信 ${taskId}`);
  }
  // ポーリング
  let task;
  for (;;) {
    task = await call("GET", `/openapi/v1/image-to-3d/${taskId}`);
    if (["SUCCEEDED", "FAILED", "CANCELED"].includes(task.status)) break;
    await sleep(10_000);
  }
  const rec = state.assets[a.id];
  rec.status = task.status;
  rec.task_id = taskId;
  rec.credits = task.status === "SUCCEEDED" ? (task.consumed_credits ?? COST) : 0;
  if (task.status !== "SUCCEEDED") {
    rec.error = task.task_error?.message || "unknown";
    saveState(state);
    log(`${a.id}: ${task.status} ${rec.error}`);
    return;
  }
  const dir = path.join(OUT, a.id);
  fs.mkdirSync(dir, { recursive: true });
  const files = {};
  if (task.model_urls?.glb) files["model.glb"] = await download(task.model_urls.glb, path.join(dir, "model.glb"));
  if (task.thumbnail_url) files["thumbnail.png"] = await download(task.thumbnail_url, path.join(dir, "thumbnail.png"));
  const tex = task.texture_urls?.[0] || {};
  for (const [k, url] of Object.entries(tex)) {
    if (typeof url === "string" && url.startsWith("http")) files[`${k}.png`] = await download(url, path.join(dir, `${k}.png`));
  }
  rec.files = files;
  rec.completed_at = new Date().toISOString();
  saveState(state);
  log(`${a.id}: 完了（${rec.credits} credits）`, Object.keys(files).join(", "));
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  if (cmd === "balance") { console.log((await call("GET", "/openapi/v1/balance")).balance); return; }
  if (cmd === "status") {
    const s = loadState();
    let total = 0;
    for (const a of concepts()) {
      const x = s.assets[a.id] || {};
      total += x.credits || 0;
      console.log(`${a.id.padEnd(16)} ${(x.status || "-").padEnd(10)} ${String(x.credits ?? "").padEnd(4)} ${x.task_id || ""}`);
    }
    console.log(`消費合計 ${total}`);
    return;
  }
  if (cmd === "run") {
    const opts = { maxCredits: 300, dryRun: false, force: false };
    const ids = [];
    for (let i = 0; i < rest.length; i++) {
      if (rest[i] === "--max-credits") opts.maxCredits = Number(rest[++i]);
      else if (rest[i] === "--dry-run") opts.dryRun = true;
      else if (rest[i] === "--force") opts.force = true;
      else if (rest[i] === "--all") ids.push(...concepts().map((a) => a.id));
      else ids.push(rest[i]);
    }
    const all = concepts();
    const state = loadState();
    state.inflight = 0;
    // 同時実行枠はヒーロー側と共有なので 2 本ずつ
    const queue = ids.map((id) => all.find((a) => a.id === id) || (() => { throw new Error(`unknown id ${id}`); })());
    const workers = Array.from({ length: 2 }, async () => {
      while (queue.length) {
        const a = queue.shift();
        try { await runOne(a, state, opts); } catch (e) { log(`${a.id}: エラー ${e.message}`); process.exitCode = 1; }
      }
    });
    await Promise.all(workers);
    return;
  }
  console.log(fs.readFileSync(fileURLToPath(import.meta.url), "utf8").split("\n").slice(1, 19).map((l) => l.replace(/^\/\/ ?/, "")).join("\n"));
}

main().catch((e) => { console.error(e.message); process.exit(1); });
