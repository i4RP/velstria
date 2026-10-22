#!/usr/bin/env node
// H032 赤拳のディアスのモーション取得（Meshy）。再開可能: 状態は build/h032-motion/api-state.json（task_id・条件・消費のみ）。
// キーは env MESHY_API_KEY か ~/.config/meshy/api_key。キー・署名 URL は保存も表示もしない。
// 有料 POST は自動で再送しない（結果不明の送信は state を見て手で判断する）。同じコマンドをもう一度実行すると取得の続きになる。
//   node tools/h032_motion_api.mjs rig        H032 の静的 GLB（build/h032-motion/H032_rig_input.glb）を Meshy で自動リグ
//   node tools/h032_motion_api.mjs motions    Text to Motion（prime）を動作ごとに 1 案ずつ
//   node tools/h032_motion_api.mjs library    ライブラリの候補をリグへ適用（action_ids、比較用）
//   node tools/h032_motion_api.mjs apply      prime の結果をリグへ適用（motion_task_id）→ GLB
//   node tools/h032_motion_api.mjs status | manifest
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'build', 'h032-motion');
const journal = path.join(dir, 'api-state.json');
fs.mkdirSync(dir, { recursive: true });
const BUDGET = 200; // このヒーローの Meshy の上限（credits）
const state = fs.existsSync(journal) ? JSON.parse(fs.readFileSync(journal, 'utf8')) : { version: 1, hero: 'H032', budget: { meshy: BUDGET }, tasks: {} };
const save = () => { fs.writeFileSync(journal + '.tmp', JSON.stringify(state, null, 2) + '\n'); fs.renameSync(journal + '.tmp', journal); };
const key = () => (process.env.MESHY_API_KEY || fs.readFileSync(path.join(os.homedir(), '.config', 'meshy', 'api_key'), 'utf8')).trim();
const scrub = (v) => Array.isArray(v) ? v.map(scrub) : v && typeof v === 'object'
  ? Object.fromEntries(Object.entries(v).filter(([k]) => !/url|token/i.test(k)).map(([k, x]) => [k, scrub(x)]))
  : typeof v === 'string' ? v.replace(/https?:\/\/\S+/g, '<url>').replace(/msy_[A-Za-z0-9]+/g, '<credential>') : v;

async function api(route, method = 'GET', body) {
  const r = await fetch('https://api.meshy.ai' + route, { method, headers: { Authorization: `Bearer ${key()}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) { const e = new Error(`${method} ${route}: HTTP ${r.status} ${JSON.stringify(scrub(data))}`); e.status = r.status; throw e; }
  return data;
}
async function download(url, name) {
  const target = path.join(dir, name);
  if (!fs.existsSync(target)) {
    const r = await fetch(url);
    if (!r.ok) throw new Error(`download ${name}: HTTP ${r.status}`);
    fs.writeFileSync(target + '.part', Buffer.from(await r.arrayBuffer())); fs.renameSync(target + '.part', target);
  }
  const b = fs.readFileSync(target);
  return { file: path.relative(root, target), bytes: b.length, sha256: crypto.createHash('sha256').update(b).digest('hex') };
}
const spent = () => Object.values(state.tasks).reduce((n, t) => n + (t.consumed_credits ?? t.estimate ?? 0), 0);

/** 1 タスクを送る（未送信なら）→ 状態を取る → 成功なら files を落とす。 */
async function task(name, route, body, estimate, files) {
  let t = state.tasks[name];
  // 429（同時実行の上限）は受け付け前の拒否で課金されないので、次の実行で送り直す
  if (t?.status === 'REJECTED' && t.http_status === 429) { delete state.tasks[name]; t = undefined; }
  if (!t) {
    if (spent() + estimate > state.budget.meshy) throw new Error(`budget: ${name}`);
    t = state.tasks[name] = { route, request: Object.fromEntries(Object.entries(body).filter(([k]) => k !== 'model_url')), estimate, status: 'submitting', submitted_at: new Date().toISOString() }; save();
    try { t.task_id = (await api(route, 'POST', body)).result; t.status = 'PENDING'; save(); }
    catch (e) { Object.assign(t, { status: e.status && e.status < 500 && e.status !== 408 ? 'REJECTED' : 'unknown', http_status: e.status, error: scrub(e.message) }); if (t.status === 'REJECTED') t.consumed_credits = 0; save(); throw e; }
  }
  if (!t.task_id) throw new Error(`${name}: 前回の送信が不明（${t.status}）。再送しない`);
  const d = await api(`${route}/${t.task_id}`);
  Object.assign(t, { status: d.status, progress: d.progress, consumed_credits: d.consumed_credits, expires_at: d.expires_at, finished_at: d.finished_at, task_error: scrub(d.task_error) });
  if (d.status === 'SUCCEEDED') { t.files = []; for (const [pick, out] of files) { const u = pick(d.result ?? d); if (u) t.files.push(await download(u, out)); } }
  save();
  console.log(name, t.status, t.progress ?? '', t.consumed_credits ?? '', (t.files || []).map((f) => f.file).join(' '));
  return t;
}

// 動作ごとの prime 生成（400 字以内）。共通: 両前腕に刃付きの籠手、拳は固く握り、刃は前腕の外側に沿って後ろ向き。
const MOTIONS = {
  idle: [4, 'Young demon brawler in a fighting guard, looped idle. Left foot forward, weight on front leg, knees bent. Both fists clenched tight in bladed gauntlets, left fist at chin height forward, right fist lower near jaw, elbows tucked, blades along outer forearms. Chin up. Slow breathing lifts shoulders slightly, small weight shift front to back. Head, chest, shoulders move together. Feet stay planted.'],
  walk: [3, 'Aggressive brawler walking forward in a boxing guard, steady looping steps. Torso leans forward, knees lift high on each step, heel to toe contact. Both fists clenched in bladed gauntlets, held tight near the chin, elbows tucked against ribs so the forearm blades never touch the thighs. Small shoulder sway with each step, eyes forward. Constant walking pace, no stopping.'],
  run: [2, 'Fierce brawler sprinting forward, looping run. Deep forward lean, powerful knee drive, feet strike under the hips. Both fists clenched in bladed gauntlets pumping close to the body, elbows bent 90 degrees, arms swinging front to back and never crossing the thighs. Chest forward, chin up, aggressive. Constant speed, no stopping.'],
  combo: [3, 'Brawler in fighting guard, left foot forward, fists clenched in bladed gauntlets. Small crouch to load, then explosive step in with a sharp left jab: hips and shoulders rotate, arm snaps fully straight, fist knuckles forward. Snap back. Then a powerful right straight punch, back heel pivots, torso twists, right fist fully extended. Absorb recoil in shoulders and return quickly to guard.'],
  s1: [2.5, 'Brawler in fighting guard, fists clenched in bladed gauntlets. Rapid three punch flurry forward: right straight, left straight, right straight, each fully extended at chest height with the torso twisting into every blow and short steps forward. Even rhythm, 0.2 seconds between punches. Recoil in shoulders, then return to tight guard.'],
  s2dash: [2, 'Brawler crouches low and bursts forward in a fast low dash, torso almost horizontal, right fist leading forward at waist height in bladed gauntlet, left fist tucked at the hip. Covers ground explosively, then plants the front foot to stop and rises back to fighting guard.'],
  s2leap: [3, 'Brawler in fighting guard winds up, both fists clenched in bladed gauntlets raised behind the head, then leaps forward in a high arc and lands with a crushing double overhead fist smash into the ground, knees deep bent. On landing throws a quick left hook and a right uppercut. Then recovers to fighting guard.'],
  ult: [3, 'Brawler plants wide stance without stepping, twists torso far back, right fist clenched in bladed gauntlet drawn back to the hip, left arm extended forward aiming, charging power and trembling, feet fixed. Then explodes with a massive right straight punch, full body lunges forward, rear heel pivots, arm fully extended, knuckles forward. Holds briefly and returns to guard.'],
};
// ライブラリの比較候補（名前ではなく動作で見るため、すべて同じリグで GLB にする）
const LIBRARY = [89, 21, 510, 191, 192, 210, 198];

const commands = {
  async rig() {
    const input = path.join(dir, 'H032_rig_input.glb');
    const b64 = fs.readFileSync(input).toString('base64');
    await task('rig', '/openapi/v1/rigging', { model_url: `data:model/gltf-binary;base64,${b64}`, height_meters: 1.75 }, 5,
      [[(r) => r.rigged_character_glb_url, 'H032_meshy_rigged.glb'], [(r) => r.basic_animations?.walking_glb_url, 'basic_walking.glb'], [(r) => r.basic_animations?.running_glb_url, 'basic_running.glb']]);
  },
  async motions() {
    const only = process.argv[3]?.split(',');
    for (const [name, [duration, prompt]] of Object.entries(MOTIONS)) {
      if (only && !only.includes(name)) continue;
      if (prompt.length > 400) throw new Error(`${name}: prompt ${prompt.length} > 400`);
      try { await task(`motion_${name}`, '/openapi/v1/text-to-motion', { mode: 'prime', duration, prompt }, 10, [[(r) => r.motion_url, `motion_${name}.fbx`]]); }
      catch (e) { console.error(name, scrub(e.message)); }
    }
  },
  async library() {
    const rig = state.tasks.rig;
    if (rig?.status !== 'SUCCEEDED') throw new Error('rig が未完了');
    await task('library', '/openapi/v1/animations', { rig_task_id: rig.task_id, action_ids: LIBRARY }, 3 * LIBRARY.length, [[(r) => r.animation_glb_url, 'library.glb']]);
  },
  async apply() {
    const rig = state.tasks.rig;
    if (rig?.status !== 'SUCCEEDED') throw new Error('rig が未完了');
    for (const name of Object.keys(MOTIONS)) {
      const m = state.tasks[`motion_${name}`];
      if (m?.status !== 'SUCCEEDED') { console.log(name, 'motion 未完了'); continue; }
      try { await task(`anim_${name}`, '/openapi/v1/animations', { rig_task_id: rig.task_id, motion_task_id: m.task_id }, 3, [[(r) => r.animation_glb_url, `anim_${name}.glb`]]); }
      catch (e) { console.error(name, scrub(e.message)); }
    }
  },
  async status() {
    console.log(JSON.stringify(await api('/openapi/v1/balance'))); console.log('spent', spent());
    for (const [n, t] of Object.entries(state.tasks)) console.log(n, t.task_id, t.status, t.consumed_credits ?? `~${t.estimate}`);
  },
  async manifest() {
    const out = { version: 1, hero: 'H032', recorded_at: new Date().toISOString(), credit_cap: state.budget, credits_consumed: spent(),
      library_candidates: LIBRARY, prompts: Object.fromEntries(Object.entries(MOTIONS).map(([k, [d, p]]) => [k, { duration: d, prompt: p }])),
      tasks: Object.entries(state.tasks).map(([name, t]) => ({ name, task_id: t.task_id ?? null, route: t.route, status: t.status, consumed_credits: t.consumed_credits ?? 0, request: t.request?.prompt ? { mode: t.request.mode, duration: t.request.duration } : t.request, files: t.files ?? [] })) };
    fs.writeFileSync(path.join(root, 'docs', 'MOTION_H032_API.json'), JSON.stringify(out, null, 2) + '\n');
  },
};
const cmd = commands[process.argv[2]];
if (!cmd) { console.error('usage: rig|motions|library|apply|status|manifest'); process.exit(1); }
try { await cmd(); } catch (e) { console.error(scrub(e.message)); process.exitCode = 1; }
