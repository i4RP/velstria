#!/usr/bin/env node
// H031 オーリアの動作素材の取得（再開可能）。キーは env MESHY_API_KEY / TRIPO_API_KEY か ~/.config/<provider>/api_key。
// 有料の送信は自動で再送しない（送信結果が不明なら journal を確認する）。同じコマンドを再実行すると完了待ち・取得だけ行う。
//   node tools/h031_motion_api.mjs prime [name...]   Meshy text-to-motion prime（1 動作 1 案）
//   node tools/h031_motion_api.mjs rigcheck <glb>     Tripo rig-check（無料）
//   node tools/h031_motion_api.mjs rig                Tripo v3 リグ補修（指を足す、25）
//   node tools/h031_motion_api.mjs basics             Tripo idle/walk/run（その場、30）
//   node tools/h031_motion_api.mjs manifest           秘密を除いた記録を docs/MOTION_H031_API.json へ
// 状態は build/h031-motion/api-state.json（予算 budget を超える送信は拒否）。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'build', 'h031-motion');
const journal = path.join(dir, 'api-state.json');
fs.mkdirSync(dir, { recursive: true });
const state = fs.existsSync(journal) ? JSON.parse(fs.readFileSync(journal, 'utf8'))
  : { version: 1, hero: 'H031', budget: { meshy: 120, tripo: 60 }, tasks: {} };
const bases = { meshy: 'https://api.meshy.ai', tripo: 'https://openapi.tripo3d.ai/v3' };
const keys = {};
const save = () => { fs.writeFileSync(journal + '.tmp', JSON.stringify(state, null, 2) + '\n'); fs.renameSync(journal + '.tmp', journal); };
const key = (p) => keys[p] ||= (process.env[`${p.toUpperCase()}_API_KEY`] || fs.readFileSync(path.join(os.homedir(), '.config', p, 'api_key'), 'utf8')).trim();
function scrub(v) {
  if (Array.isArray(v)) return v.map(scrub);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).filter(([k]) => !/url|token/i.test(k)).map(([k, x]) => [k, scrub(x)]));
  if (typeof v === 'string') return v.replace(/https?:\/\/\S+/g, '<url>').replace(/(?:msy_|tsk_)[A-Za-z0-9]+/g, '<credential>');
  return v;
}
async function api(p, route, method = 'GET', body) {
  const r = await fetch(bases[p] + route, { method, headers: { Authorization: `Bearer ${key(p)}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const data = await r.json();
  if (!r.ok || (p === 'tripo' && data.code !== 0)) { const e = new Error(`${p} ${method} ${route}: HTTP ${r.status} ${JSON.stringify(scrub(data))}`); e.status = r.status; throw e; }
  return p === 'tripo' ? data.data : data;
}
async function download(url, name) {
  const target = path.join(dir, name);
  if (!fs.existsSync(target)) {
    const r = await fetch(url);
    if (!r.ok) throw new Error(`download ${name}: HTTP ${r.status}`);
    const buf = Buffer.from(await r.arrayBuffer());
    fs.writeFileSync(target + '.part', buf); fs.renameSync(target + '.part', target);
  }
  const buf = fs.readFileSync(target);
  return { file: path.relative(root, target), bytes: buf.length, sha256: crypto.createHash('sha256').update(buf).digest('hex') };
}
const spent = (p) => Object.values(state.tasks).filter((t) => t.provider === p && t.status !== 'REJECTED')
  .reduce((n, t) => n + (t.credits_consumed ?? t.consumed_credits ?? t.estimate ?? 0), 0);
function reject(task, e) {
  const definite = [400, 401, 402, 403, 404, 413, 415, 422, 429].includes(e.status);
  Object.assign(task, { status: definite ? 'REJECTED' : 'unknown', http_status: e.status, error: scrub(e.message) });
  if (definite) task.consumed_credits = 0;
  save();
}

// 動作ごとの指示（400 字以内）。待機・移動はループ、攻撃・スキルは構え→復帰まで。
const PRIME = {
  idle: { duration: 4, prompt: 'Regal ice queen mage standing idle, no staff. Feet close together, back straight, chin raised. Slow calm breathing with a tiny weight shift between feet. Right hand held near the hip, palm up, fingers softly spread and slowly curling as if toying with frost. Left hand rests close to the waist. Head, chest and shoulders follow the breath subtly. Seamless loop, same pose at start and end. No steps.' },
  walk: { duration: 2, prompt: 'Elegant queen in a long robe walking forward in place, graceful and calm. Narrow steps, feet landing almost on one line, upper body upright and gliding with little bounce, chin raised. Arms relaxed close to the body with a small swing, right hand slightly open, left hand near the waist. Seamless walking loop, two steps, same pose at start and end.' },
  run: { duration: 2, prompt: 'Graceful sorceress in a long robe running forward lightly, slight forward lean, narrow stride, upper body steady. Small controlled arm swing kept close to the body, hands relaxed and open, elbows bent. Light quick footsteps, no big bounce. Seamless running loop, same pose at start and end.' },
  attack: { duration: 2.5, prompt: 'Elegant ice sorceress without staff, narrow stance, feet planted. From calm ready pose, right hand draws back to the chest with palm cupped gathering cold, hips and chest coil slightly right. Then thrust the right arm straight forward, fingers snapping open and extended, palm facing the target, releasing a frost bolt. Shoulders and torso absorb a small recoil, then return to the ready pose.' },
  s1: { duration: 2.5, prompt: 'Ice queen mage without staff, feet planted in a narrow stance. Raises the right arm high and forward with chest lifting, then points the extended index finger down at a spot several meters ahead, commanding ice to fall there. Holds the point briefly, then lowers the arm calmly back to a ready pose with the right hand near the hip. Left hand stays near the waist. No steps.' },
  s2: { duration: 2.5, prompt: 'Sorceress without staff, narrow stance, feet planted. Brings the right hand to the right side at shoulder height, palm cupped gathering cold wind, then sweeps the open palm horizontally across the front from right to left and pushes forward, sending a fan of frost ahead. Torso turns with the sweep, then calmly returns to the ready pose. Left hand stays near the waist. No steps.' },
  ult: { duration: 3, prompt: 'Ice queen mage without staff. Raises the right hand above the head, palm open, gathering power, then swings the right arm down powerfully, the open palm striking toward the ground in front, knees bending slightly and upper body leaning forward. Holds a brief moment, then rises gracefully back to an upright ready pose. Feet planted, no steps. Left hand stays near the waist.' },
};

async function prime(names) {
  for (const n of names.length ? names : Object.keys(PRIME)) {
    const name = `h031_prime_${n}`;
    let task = state.tasks[name];
    if (task?.status === 'REJECTED') { console.log(name, 'REJECTED', task.error); continue; }
    if (!task) {
      const req = { mode: 'prime', ...PRIME[n] };
      if (req.prompt.length > 400) throw new Error(`${n}: prompt over 400 chars`);
      if (spent('meshy') + 10 > state.budget.meshy) throw new Error('Meshy budget reached');
      task = state.tasks[name] = { provider: 'meshy', status: 'submitting', request: req, estimate: 10, submitted_at: new Date().toISOString() }; save();
      try { const d = await api('meshy', '/openapi/v1/text-to-motion', 'POST', req); task.task_id = d.result; task.status = 'PENDING'; save(); }
      catch (e) { reject(task, e); console.log(name, 'submit failed', scrub(e.message)); continue; }
    }
    if (!task.task_id) { console.log(name, 'uncertain submission: inspect account before resubmitting'); continue; }
    if (task.file) { console.log(name, 'done', task.file.file); continue; }
    const d = await api('meshy', `/openapi/v1/text-to-motion/${task.task_id}`);
    Object.assign(task, scrub(d), { checked_at: new Date().toISOString() }); save();
    if (d.status === 'SUCCEEDED') {
      const res = d.result || {};
      const url = res.motion_url || res.animation_fbx_url || res.fbx_url || Object.values(res).find((x) => typeof x === 'string' && /\.fbx/i.test(x));
      if (url) { task.file = await download(url, `${name}.fbx`); save(); }
      else console.log(name, 'result keys', Object.keys(res));
    }
    console.log(name, task.status, task.progress ?? '', task.file?.file ?? '');
  }
}

async function tripoTask(name, route, request, estimate) {
  let task = state.tasks[name];
  if (!task) {
    if (spent('tripo') + estimate > state.budget.tripo) throw new Error('Tripo budget reached');
    task = state.tasks[name] = { provider: 'tripo', status: 'submitting', request, estimate, submitted_at: new Date().toISOString() }; save();
    try { const d = await api('tripo', route, 'POST', request); task.task_id = d.task_id; task.status = 'queued'; save(); }
    catch (e) { reject(task, e); throw e; }
  }
  if (!task.task_id) throw new Error(`${name}: uncertain submission`);
  const d = await api('tripo', `/tasks/${task.task_id}`);
  Object.assign(task, scrub(d), { checked_at: new Date().toISOString() }); save();
  if (d.status === 'success' && d.output?.model_url && !task.file) { task.file = await download(d.output.model_url, `${name}.glb`); save(); }
  console.log(name, task.status, task.progress ?? '', JSON.stringify(task.output ?? {}), task.file?.file ?? '');
  return task;
}
async function rigcheck(src) {
  const bytes = fs.readFileSync(src), sha = crypto.createHash('sha256').update(bytes).digest('hex');
  const upFile = path.join(dir, 'tripo-upload.json');
  let up = fs.existsSync(upFile) ? JSON.parse(fs.readFileSync(upFile, 'utf8')) : null;
  if (!up || up.sha256 !== sha) {
    const form = new FormData(); form.set('file', new Blob([bytes], { type: 'model/gltf-binary' }), path.basename(src));
    const r = await fetch(bases.tripo + '/files', { method: 'POST', headers: { Authorization: `Bearer ${key('tripo')}` }, body: form });
    const d = await r.json(); if (!r.ok || d.code !== 0) throw new Error(`Tripo upload HTTP ${r.status} ${JSON.stringify(scrub(d))}`);
    up = { sha256: sha, file_token: d.data.file_token }; fs.writeFileSync(upFile, JSON.stringify(up, null, 2));
  }
  state.source = { file: path.relative(root, src), sha256: sha, bytes: bytes.length }; save();
  return tripoTask('H031_rigcheck', '/animations/rig-check', { input: up.file_token }, 0);
}
async function rig() {
  const c = state.tasks.H031_rigcheck;
  if (c?.status !== 'success' || c.output?.riggable !== true) throw new Error('successful rig-check required');
  return tripoTask('H031_rig_v3', '/animations/rig', { input: c.request.input, model: 'v3.0-20260909', rig_type: 'biped', spec: 'mixamo', out_format: 'glb' }, 25);
}
async function basics() {
  const r = state.tasks.H031_rig_v3;
  if (r?.status !== 'success') throw new Error('successful rig required');
  return tripoTask('H031_idle_walk_run', '/animations/retarget', { input: r.task_id, animations: ['preset:idle', 'preset:walk', 'preset:run'], animate_in_place: true, out_format: 'glb', export_with_geometry: true }, 30);
}
function manifest() {
  const tasks = Object.entries(state.tasks).map(([name, t]) => ({ name, provider: t.provider, task_id: t.task_id ?? null, status: t.status,
    credits_consumed: t.credits_consumed ?? t.consumed_credits ?? (t.status === 'SUCCEEDED' || t.status === 'success' ? t.estimate : 0),
    submitted_at: t.submitted_at, request: Object.fromEntries(Object.entries(t.request ?? {}).filter(([k]) => k !== 'input')),
    file: t.file ?? null, error: t.error ?? null }));
  const out = path.join(root, 'docs', 'MOTION_H031_API.json');
  fs.writeFileSync(out, JSON.stringify({ version: 1, hero: 'H031', recorded_at: new Date().toISOString(), budget: state.budget, source: state.source, tasks }, null, 2) + '\n');
  console.log(path.relative(root, out));
}
try {
  const [cmd, ...rest] = process.argv.slice(2);
  const cmds = { prime: () => prime(rest), rigcheck: () => rigcheck(path.resolve(rest[0])), rig, basics, manifest };
  if (!cmds[cmd]) throw new Error('usage: prime|rigcheck <glb>|rig|basics|manifest');
  await cmds[cmd]();
} catch (e) { console.error(scrub(e.message)); process.exitCode = 1; }
