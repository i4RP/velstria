#!/usr/bin/env node
// Resumable H034 (Gorm, chain hook) motion acquisition. Same journal rules as h025_motion_api.mjs:
// keys from env MESHY_API_KEY / TRIPO_API_KEY (or ~/.config/<provider>/api_key), never written to disk or logs.
// No paid request is retried automatically; a submission without task ID must be inspected before resubmitting.
// Run a command again to poll; downloaded files stay in build/h034-motion/ (git-ignored).
//   inventory          free: balances, Meshy library list, prior text-to-motion tasks
//   prime [name...]    Meshy text-to-motion prime (10 credits each, one candidate per motion)
//   rigcheck | rig | basics   Tripo v3 rig repair donor (fingers) and idle/walk/run presets
//   manifest           sanitized provenance → docs/MOTION_H034_API.json
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'build', 'h034-motion');
const journal = path.join(dir, 'api-state.json');
fs.mkdirSync(dir, { recursive: true });
const lockPath = journal + '.lock';
if (fs.existsSync(lockPath)) {
  const owner = Number(fs.readFileSync(lockPath, 'utf8'));
  try { process.kill(owner, 0); throw new Error('Another H034 acquisition process owns the journal'); }
  catch (error) { if (error.code !== 'ESRCH') throw error; fs.unlinkSync(lockPath); }
}
const lock = fs.openSync(lockPath, 'wx'); fs.writeSync(lock, String(process.pid));
process.on('exit', () => { fs.closeSync(lock); fs.unlinkSync(lockPath); });
const state = fs.existsSync(journal) ? JSON.parse(fs.readFileSync(journal, 'utf8')) : {
  version: 1, hero: 'H034', budget: { meshy: 100, tripo: 60 }, tasks: {}, inventory: {},
};
const bases = { meshy: 'https://api.meshy.ai', tripo: 'https://openapi.tripo3d.ai/v3' };
const keys = {};

// One prime candidate per motion. Prompts ≤ 400 chars; loops describe a seamless cycle.
const PRIME = {
  idle: { duration: 4, prompt: 'Huge heavy barbarian brute with short legs, wide stance, feet planted far apart, knees slightly bent, weight low. Right hand grips a heavy chain hook steady at the right hip; left hand rests near the belly. Slow deep breathing: chest, shoulders and head rise and fall together, tiny weight shift side to side. No stepping, no arm swinging. Seamless loop ending in the start pose.' },
  walk: { duration: 3, prompt: 'Huge heavy barbarian with short legs walking forward at a steady pace with wide rolling steps, feet landing well apart, body swaying side to side to carry a heavy chain. Torso upright and steady, chest proud. Right hand holds a chain hook close at the right hip without swinging it; left arm swings a little. Constant speed, cyclic walk loop.' },
  run: { duration: 3, prompt: 'Huge heavy barbarian with short legs running forward, torso leaning forward, short powerful wide strides, heavy pounding footfalls. Right hand pulls a heavy chain hook tight against the right side of the body; left arm pumps. Shoulders roll with the weight. Constant speed, cyclic run loop.' },
  attack: { duration: 3, prompt: 'Huge barbarian in a wide planted stance, right hand grips a heavy chain hook, left hand holds the chain near the belly. Small crouch, twist torso right and raise the hook high back over the right shoulder, brief hold, then swing it forward and down to smash the ground in front with full body weight, hips and shoulders turning. Absorb the recoil, pull the chain back hand over hand, back to stance.' },
  hook: { duration: 3, prompt: 'Huge barbarian, feet planted wide. Right hand holds a heavy chain hook. Wind up: twist the torso right and swing the hook back low behind the right hip. Then uncoil and throw it straight forward, right arm fully extended, left arm back, chest facing forward. Hold the arm out a moment, then both hands yank the chain back hand over hand toward the chest in strong pulls. Return to stance.' },
  slam: { duration: 2.5, prompt: 'Huge barbarian with short legs crouches, swings a heavy chain hook up high over the head with both hands, small heavy hop, lands and slams it straight down onto the ground in front with full body weight, knees bending deep on impact, shoulders hunched. Brief pause, then rises back into a wide ready stance holding the chain at the right hip.' },
  ult: { duration: 3.5, prompt: 'Huge barbarian lunges forward low and grabs an enemy by the collar with the left hand, holds him, and beats him with a heavy chain hook in the right hand: a vertical overhead blow, a low swing left to right, another overhead blow, a low swing right to left, then a final huge overhead smash to the ground with the whole body. Quickly recovers to a wide stance.' },
};

function save() {
  state.api_credit_total = Object.fromEntries(['meshy', 'tripo'].map(p => [p, Object.values(state.tasks).filter(t => t.provider === p).reduce((n, t) => n + (t.credits_consumed ?? t.consumed_credits ?? 0), 0)]));
  fs.writeFileSync(journal + '.tmp', JSON.stringify(state, null, 2) + '\n'); fs.renameSync(journal + '.tmp', journal);
}
function key(p) { return keys[p] ||= (process.env[`${p.toUpperCase()}_API_KEY`] || fs.readFileSync(path.join(os.homedir(), '.config', p, 'api_key'), 'utf8')).trim(); }
function scrub(v) {
  if (Array.isArray(v)) return v.map(scrub);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).filter(([k]) => !/url|token/i.test(k)).map(([k, x]) => [k, scrub(x)]));
  if (typeof v === 'string') return v.replace(/https?:\/\/\S+/g, '<url>').replace(/(?:msy_|tsk_)[A-Za-z0-9]+/g, '<credential>');
  return v;
}
function report(name, t) { console.log(name, JSON.stringify({ task_id: t.task_id, status: t.status, progress: t.progress, credits: t.credits_consumed ?? t.consumed_credits ?? null, file: t.file?.file })); }
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
    fs.writeFileSync(target + '.part', Buffer.from(await r.arrayBuffer())); fs.renameSync(target + '.part', target);
  }
  const b = fs.readFileSync(target);
  return { file: path.relative(root, target), bytes: b.length, sha256: crypto.createHash('sha256').update(b).digest('hex') };
}
function reject(task, e) {
  const definite = [400, 401, 402, 403, 404, 413, 415, 422, 429].includes(e.status);
  Object.assign(task, { status: definite ? 'REJECTED' : 'unknown', http_status: e.status, error: scrub(e.message), checked_at: new Date().toISOString() });
  if (definite) task.consumed_credits = 0;
  save();
}
function spent(p) { return Object.values(state.tasks).filter(t => t.provider === p && t.status !== 'REJECTED').reduce((n, t) => n + (t.credits_consumed ?? t.consumed_credits ?? t.estimate ?? 0), 0); }

async function inventory() {
  state.inventory.meshy_balance = { ...(await api('meshy', '/openapi/v1/balance')), checked_at: new Date().toISOString() };
  state.inventory.tripo_balance = { ...(await api('tripo', '/account/balance')), checked_at: new Date().toISOString() }; save();
  const lib = await api('meshy', '/openapi/v1/animations/library');
  const list = Array.isArray(lib) ? lib : lib.result || lib.data || [];
  fs.writeFileSync(path.join(dir, 'meshy-library.json'), JSON.stringify(scrub(list), null, 2));
  const re = /idle|walk|run|swing|throw|slam|smash|pull|axe|hammer|heavy|chain|rope|punch|strike|attack|combo|grab/i;
  state.inventory.meshy_library = { count: list.length, candidates: list.filter(x => re.test(JSON.stringify(scrub(x)))).map(x => ({ action_id: x.action_id, name: x.name, category: x.category, sub_category: x.sub_category })), checked_at: new Date().toISOString() };
  try { state.inventory.existing_motion_tasks = scrub(await api('meshy', '/openapi/v1/text-to-motion?page_num=1&page_size=50')).map(t => ({ id: t.id, status: t.status })); }
  catch (e) { state.inventory.motion_list_error = scrub(e.message); }
  save();
  console.log(JSON.stringify({ meshy: state.inventory.meshy_balance.balance, tripo: state.inventory.tripo_balance.balance, library: list.length, candidates: state.inventory.meshy_library.candidates.length, prior_motion_tasks: state.inventory.existing_motion_tasks?.length }));
}

async function prime() {
  const names = process.argv.slice(3).length ? process.argv.slice(3) : Object.keys(PRIME);
  for (const name of names) {
    const spec = PRIME[name]; if (!spec) throw new Error(`unknown motion ${name}`);
    const tname = `prime_${name}`;
    let task = state.tasks[tname];
    if (task?.status === 'REJECTED') { console.log(tname, 'rejected earlier:', task.error); continue; }
    if (!task) {
      if (spec.prompt.length > 400) throw new Error(`${name}: prompt ${spec.prompt.length} > 400`);
      if (spent('meshy') + 10 > state.budget.meshy) throw new Error('Meshy project credit cap reached');
      const request = { mode: 'prime', duration: spec.duration, prompt: spec.prompt };
      task = state.tasks[tname] = { provider: 'meshy', status: 'submitting', request, estimate: 10, submitted_at: new Date().toISOString() }; save();
      try { task.task_id = (await api('meshy', '/openapi/v1/text-to-motion', 'POST', request)).result; task.status = 'PENDING'; save(); }
      catch (e) { reject(task, e); console.log(tname, 'submit failed', task.error); continue; }
    }
    if (!task.task_id) { console.log(tname, 'uncertain submission; inspect the account task list before resubmitting'); continue; }
    if (task.status !== 'SUCCEEDED' || !task.file) {
      const data = await api('meshy', `/openapi/v1/text-to-motion/${task.task_id}`);
      Object.assign(task, scrub(data), { checked_at: new Date().toISOString() }); save();
      if (data.status === 'SUCCEEDED' && data.result?.motion_url) { task.file = await download(data.result.motion_url, `${tname}.fbx`); save(); }
    }
    report(tname, task);
  }
}

async function tripoTask(name, route, request, estimate) {
  let task = state.tasks[name];
  if (!task) {
    if (spent('tripo') + estimate > state.budget.tripo) throw new Error('Tripo project credit cap reached');
    task = state.tasks[name] = { provider: 'tripo', status: 'submitting', request, estimate, submitted_at: new Date().toISOString() }; save();
    try { task.task_id = (await api('tripo', route, 'POST', request)).task_id; task.status = 'queued'; save(); }
    catch (e) { reject(task, e); throw e; }
  }
  if (!task.task_id) throw new Error(`${name}: no task ID; inspect before resubmitting`);
  if (task.status !== 'success' || !task.file) {
    const data = await api('tripo', `/tasks/${task.task_id}`);
    Object.assign(task, scrub(data), { checked_at: new Date().toISOString() }); save();
    if (data.status === 'success' && data.output?.model_url) { task.file = await download(data.output.model_url, `${name}.${request.out_format || 'glb'}`); save(); }
  }
  report(name, task);
  return task;
}
async function rigcheck() {
  const source = path.join(dir, 'H034_tripo_model.glb');
  const bytes = fs.readFileSync(source), sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  const uploadFile = path.join(dir, 'tripo-upload.json');
  let up = fs.existsSync(uploadFile) ? JSON.parse(fs.readFileSync(uploadFile, 'utf8')) : null;
  if (!up || up.sha256 !== sha256) {
    const form = new FormData(); form.set('file', new Blob([bytes], { type: 'model/gltf-binary' }), 'H034_model.glb');
    const r = await fetch(bases.tripo + '/files', { method: 'POST', headers: { Authorization: `Bearer ${key('tripo')}` }, body: form });
    const d = await r.json(); if (!r.ok || d.code !== 0) throw new Error(`Tripo upload HTTP ${r.status} ${JSON.stringify(scrub(d))}`);
    up = { sha256, file_token: d.data.file_token }; fs.writeFileSync(uploadFile, JSON.stringify(up, null, 2));
  }
  state.inventory.tripo_source = { file: path.relative(root, source), sha256, bytes: bytes.length, reason: 'Shipped H034 rig (Tripo v1.0, 23 joints) has no fingers/shoulder detail for the chain grip. Same Tripo model (task e732348c) re-rigged; geometry and textures are not regenerated.' }; save();
  return tripoTask('H034_rigcheck', '/animations/rig-check', { input: up.file_token }, 0);
}
async function rig() {
  const c = state.tasks.H034_rigcheck;
  if (c?.status !== 'success' || c.output?.riggable !== true) throw new Error('Successful compatible rig-check required');
  return tripoTask('H034_rig_v3', '/animations/rig', { input: c.request.input, model: 'v3.0-20260909', rig_type: 'biped', spec: 'mixamo', out_format: 'glb' }, 25);
}
async function basics() {
  const r = state.tasks.H034_rig_v3;
  if (r?.status !== 'success') throw new Error('Successful v3 rig required');
  return tripoTask('H034_idle_walk_run', '/animations/retarget', { input: r.task_id, animations: ['preset:idle', 'preset:walk', 'preset:run'], animate_in_place: true, out_format: 'glb', export_with_geometry: true }, 30);
}
async function manifest() {
  const tasks = Object.entries(state.tasks).map(([name, t]) => ({ name, provider: t.provider, task_id: t.task_id ?? null, status: t.status, http_status: t.http_status ?? null,
    credits_consumed: t.credits_consumed ?? t.consumed_credits ?? 0, submitted_at: t.submitted_at,
    request: Object.fromEntries(Object.entries(t.request ?? {}).filter(([k]) => k !== 'input')), file: t.file ?? null, error: t.error ?? null }));
  const out = { version: 1, hero: 'H034', recorded_at: new Date().toISOString(), credit_cap: state.budget, credits_consumed: state.api_credit_total,
    meshy_library: state.inventory.meshy_library, adoption: state.adoption ?? null, source: state.inventory.tripo_source, tasks,
    references: ['https://docs.meshy.ai/en/api/text-to-motion', 'https://docs.meshy.ai/en/api/animation', 'https://platform.tripo3d.ai/docs'] };
  const f = path.join(root, 'docs', 'MOTION_H034_API.json'); fs.writeFileSync(f, JSON.stringify(out, null, 2) + '\n'); console.log(path.relative(root, f));
}
try {
  const commands = { inventory, prime, rigcheck, rig, basics, manifest };
  const c = commands[process.argv[2]]; if (!c) throw new Error('usage: node tools/h034_motion_api.mjs inventory|prime [name..]|rigcheck|rig|basics|manifest');
  await c();
} catch (e) { console.error(scrub(e.message)); process.exitCode = 1; }
