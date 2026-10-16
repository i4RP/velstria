#!/usr/bin/env node
// 中立モンスター（structures.json の monster_*）に Tripo の自動リグとプリセット動作を付ける。
// 入力は structures.mjs model の task_id（state.json）。出力は build/structures/<id>/rig.glb（リグのみ）と
// anim_<preset>.glb（プリセット動作 1 本ずつ）。待機・攻撃・被弾・死亡の不足分は creature_bake.py が骨に手付けする。
// キーは env TRIPO_API_KEY か ~/.config/tripo/api_key（ファイル・ログに書かない）。
//
// usage（VELSTRIA/ で実行）: node tools/structures/creature_rig.mjs <id...>
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const STATE_PATH = path.join(ROOT, "tools", "structures", "state.json");
const BUILD = path.join(ROOT, "build", "structures");
const TRIPO = "https://openapi.tripo3d.ai/v3";
// 人型は env RIG_V1_<id>=1 で v1.0（人型専用・プリセット 90 以上）を使える（v2.5 の人型プリセットが失敗する物がある）
const RIG_MODEL = "v2.5-20260210";
const RIG_MODEL_V1 = "v1.0-20240301";
// リグ種別ごとのプリセット（v2.5 の四足は歩行だけ）
const PRESETS = {
  biped: ["preset:idle", "preset:walk", "preset:slash", "preset:hurt"],
  bipedV1: ["preset:biped:idle", "preset:biped:walk", "preset:biped:chop", "preset:biped:hit_to_body_01"],
  quadruped: ["preset:quadruped:walk"],
};

const key = process.env.TRIPO_API_KEY || fs.readFileSync(path.join(os.homedir(), ".config", "tripo", "api_key"), "utf8").trim();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log(...a);

async function call(method, p, body) {
  const r = await fetch(TRIPO + p, {
    method,
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await r.json().catch(() => ({}));
  if (j.code !== 0) throw new Error(`${method} ${p}: HTTP ${r.status} ${JSON.stringify(j).slice(0, 300)}`);
  return j.data;
}

async function run(label, p, body) {
  const { task_id } = await call("POST", p, body);
  for (;;) {
    await sleep(4000);
    const t = await call("GET", `/tasks/${task_id}`);
    if (t.status === "success") { log(`${label}: ok (${t.credits_consumed ?? "?"} credits)`); return { task_id, ...t }; }
    if (["failed", "cancelled", "banned", "expired", "unknown"].includes(t.status)) throw new Error(`${label}: ${t.status}`);
  }
}

async function download(url, out) {
  const r = await fetch(url);
  fs.writeFileSync(out, Buffer.from(await r.arrayBuffer()));
}

async function rigOne(id) {
  const st = JSON.parse(fs.readFileSync(STATE_PATH, "utf8")).assets[id];
  if (!st?.task_id) throw new Error(`${id}: model の task_id がありません`);
  const dir = path.join(BUILD, id);
  const check = await run(`${id} rig-check`, "/animations/rig-check", { input: st.task_id });
  const rigType = process.env[`RIG_${id}`] || check.output?.rig_type || "quadruped";
  log(`${id}: riggable=${check.output?.riggable} rig_type=${check.output?.rig_type} → ${rigType}`);
  const v1 = rigType === "biped" && !!process.env[`RIG_V1_${id}`];
  const rig = await run(`${id} rig`, "/animations/rig", { input: st.task_id, model: v1 ? RIG_MODEL_V1 : RIG_MODEL, rig_type: rigType, spec: "tripo", out_format: "glb" });
  await download(rig.output.model_url, path.join(dir, "rig.glb"));
  const presets = PRESETS[v1 ? "bipedV1" : rigType] || [];
  const anims = {};
  await Promise.allSettled(presets.map(async (preset) => {
    const a = await run(`${id} ${preset}`, "/animations/retarget", { input: rig.task_id, animation: preset, out_format: "glb", bake_animation: true, animate_in_place: true });
    const name = preset.split(":").pop();
    await download(a.output.model_url, path.join(dir, `anim_${name}.glb`));
    anims[name] = a.task_id;
  }));
  const meta = { rigType, rigTask: rig.task_id, anims };
  fs.writeFileSync(path.join(dir, "rig.json"), JSON.stringify(meta, null, 2) + "\n");
  return meta;
}

const ids = process.argv.slice(2);
const results = await Promise.allSettled(ids.map(rigOne));
results.forEach((r, i) => log(ids[i], r.status === "fulfilled" ? JSON.stringify(r.value) : `失敗: ${r.reason.message}`));
