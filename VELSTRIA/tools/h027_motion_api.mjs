#!/usr/bin/env node
// Resumable H027 (竜槍のジャルド) motion acquisition. Same safety rules as tools/h025_motion_api.mjs:
// credentials only from env (MESHY_API_KEY / TRIPO_API_KEY) or ~/.config/<provider>/api_key, never printed;
// paid requests are never retried automatically (an uncertain submission must be inspected first);
// state + budgets live in build/h027-motion/api-state.json; downloads stay in build/h027-motion/.
//   inventory               free: balances, Meshy library, existing Text to Motion tasks
//   rigcheck [GLB]          free: upload the unrigged shipped mesh (default build/h027-motion/H027_rig_donor.glb), rig-check
//   rig                     25:  Tripo v3 mixamo rig (adds finger chains; geometry/textures are the shipped ones)
//   basics                  30:  Tripo idle/walk/run presets, animate_in_place
//   motion <name>|all       10 each: Meshy prime from tools/motion/h027-prime-spec.json
//   poll                    free: refresh every unfinished task and download finished outputs
//   manifest                writes sanitized provenance to docs/MOTION_H027_API.json
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'build', 'h027-motion');
const journal = path.join(dir, 'api-state.json');
const specFile = path.join(root, 'tools', 'motion', 'h027-prime-spec.json');
fs.mkdirSync(dir, { recursive: true });
const lockPath = journal + '.lock';
if (fs.existsSync(lockPath)) {
  const owner = Number(fs.readFileSync(lockPath, 'utf8'));
  try { process.kill(owner, 0); throw new Error('Another H027 acquisition process owns the journal'); }
  catch (error) { if (error.code !== 'ESRCH') throw error; fs.unlinkSync(lockPath); }
}
const lock = fs.openSync(lockPath, 'wx'); fs.writeSync(lock, String(process.pid));
process.on('exit', () => { fs.closeSync(lock); fs.unlinkSync(lockPath); });
const state = fs.existsSync(journal) ? JSON.parse(fs.readFileSync(journal, 'utf8')) : {
  version: 1, hero: 'H027', budget: { meshy: 110, tripo: 60 }, tasks: {}, inventory: {},
};
const bases = { meshy: 'https://api.meshy.ai', tripo: 'https://openapi.tripo3d.ai/v3' };
const keys = {};
const finished = ['success', 'failed', 'cancelled', 'banned', 'expired', 'SUCCEEDED', 'FAILED', 'CANCELED', 'REJECTED'];
function save() {
  state.api_credit_total = Object.fromEntries(['meshy', 'tripo'].map(p => [p, Object.values(state.tasks)
    .filter(t => t.provider === p).reduce((n, t) => n + (t.credits_consumed ?? t.consumed_credits ?? 0), 0)]));
  fs.writeFileSync(journal + '.tmp', JSON.stringify(state, null, 2) + '\n'); fs.renameSync(journal + '.tmp', journal);
}
function key(provider) {
  return keys[provider] ||= (process.env[`${provider.toUpperCase()}_API_KEY`]
    || fs.readFileSync(path.join(os.homedir(), '.config', provider, 'api_key'), 'utf8')).trim();
}
function scrub(value) {
  if (Array.isArray(value)) return value.map(scrub);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).filter(([k]) => !/url|token/i.test(k)).map(([k, v]) => [k, scrub(v)]));
  if (typeof value === 'string') return value.replace(/https?:\/\/\S+/g, '<url>').replace(/(?:msy_|tsk_)[A-Za-z0-9]+/g, '<credential>');
  return value;
}
function report(name, task) {
  console.log(JSON.stringify({ name, task_id: task.task_id, provider: task.provider, status: task.status, progress: task.progress,
    credits: task.credits_consumed ?? task.consumed_credits ?? null, file: task.file?.file ?? null }));
}
async function api(provider, route, method = 'GET', body) {
  const response = await fetch(bases[provider] + route, { method, headers: { Authorization: `Bearer ${key(provider)}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const data = await response.json();
  if (!response.ok || (provider === 'tripo' && data.code !== 0)) {
    const error = new Error(`${provider} ${method} ${route}: HTTP ${response.status} ${JSON.stringify(scrub(data))}`);
    error.status = response.status;
    throw error;
  }
  return { data: provider === 'tripo' ? data.data : data };
}
async function download(url, name) {
  const target = path.join(dir, name);
  if (!fs.existsSync(target)) {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`download ${name}: HTTP ${response.status}`);
    const buffer = Buffer.from(await response.arrayBuffer());
    fs.writeFileSync(target + '.part', buffer); fs.renameSync(target + '.part', target);
  }
  const bytes = fs.readFileSync(target);
  return { file: path.relative(root, target), bytes: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex') };
}
function reject(task, error) {
  const definite = [400, 401, 402, 403, 404, 413, 415, 422, 429].includes(error.status);
  Object.assign(task, { status: definite ? 'REJECTED' : 'unknown', http_status: error.status, error: scrub(error.message), checked_at: new Date().toISOString() });
  if (definite) task.consumed_credits = 0;
  save();
}
function spent(provider) {
  return Object.values(state.tasks).filter(t => t.provider === provider)
    .reduce((n, t) => n + (finished.includes(t.status) ? (t.credits_consumed ?? t.consumed_credits ?? t.estimate ?? 0) : (t.estimate ?? 0)), 0);
}
async function submit(name, provider, route, request, estimate) {
  if (state.tasks[name]) return state.tasks[name];
  if (spent(provider) + estimate > state.budget[provider]) throw new Error(`${provider} project credit cap reached (${state.budget[provider]})`);
  const balanceRoute = provider === 'meshy' ? '/openapi/v1/balance' : '/account/balance';
  const { data: balance } = await api(provider, balanceRoute);
  if (Number(balance.balance) < estimate) throw new Error(`Insufficient ${provider} credits`);
  const task = state.tasks[name] = { provider, route, status: 'submitting', request, estimate, submitted_at: new Date().toISOString() }; save();
  try {
    const { data } = await api(provider, route, 'POST', request);
    task.task_id = provider === 'meshy' ? data.result : data.task_id; task.status = 'queued'; save();
  } catch (error) { reject(task, error); throw error; }
  return task;
}
async function refresh(name) {
  const task = state.tasks[name];
  if (!task) throw new Error(`no task ${name}`);
  if (!task.task_id) { if (task.status === 'REJECTED') return task; throw new Error(`Prior ${name} submission has no task ID; inspect the account before resubmitting`); }
  if (task.file && finished.includes(task.status)) return task;
  const route = task.provider === 'meshy' ? `${task.route}/${task.task_id}` : `/tasks/${task.task_id}`;
  const { data } = await api(task.provider, route);
  Object.assign(task, scrub(data), { checked_at: new Date().toISOString() }); save();
  if (task.provider === 'meshy' && data.status === 'SUCCEEDED' && data.result?.motion_url) {
    task.file = await download(data.result.motion_url, `${name}.${data.result.motion_format || 'fbx'}`); save();
  }
  if (task.provider === 'tripo' && data.status === 'success' && data.output?.model_url) {
    task.file = await download(data.output.model_url, `${name}.${task.request.out_format || 'glb'}`); save();
  }
  return task;
}
async function inventory() {
  for (const provider of ['meshy', 'tripo']) {
    const { data } = await api(provider, provider === 'meshy' ? '/openapi/v1/balance' : '/account/balance');
    state.inventory[`${provider}_balance`] = { ...scrub(data), checked_at: new Date().toISOString() }; save();
  }
  const { data: library } = await api('meshy', '/openapi/v1/animations/library');
  const list = Array.isArray(library) ? library : library.result || library.data || [];
  fs.writeFileSync(path.join(dir, 'meshy-library.json'), JSON.stringify(scrub(list), null, 2));
  // Candidates reviewed from the preview animations (not adopted by name alone; see docs/H027_MOTION.md).
  const reviewed = [0, 11, 89, 149, 219, 221, 240, 241, 245, 377, 392, 560, 672];
  state.inventory.meshy_library = { count: list.length, reviewed: list.filter(x => reviewed.includes(x.action_id)).map(scrub), checked_at: new Date().toISOString() }; save();
  const { data: motions } = await api('meshy', '/openapi/v1/text-to-motion?page_num=1&page_size=50');
  state.inventory.existing_motion_tasks = scrub(motions).map(t => ({ id: t.id, status: t.status, created_at: t.created_at })); save();
  console.log(JSON.stringify({ balances: [state.inventory.meshy_balance, state.inventory.tripo_balance], library: list.length, motions: state.inventory.existing_motion_tasks }, null, 2));
}
async function rigcheck() {
  const source = process.argv[3] ? path.resolve(process.argv[3]) : path.join(dir, 'H027_rig_donor.glb');
  const bytes = fs.readFileSync(source), sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  const uploadFile = path.join(dir, 'tripo-upload.json');
  let upload = fs.existsSync(uploadFile) ? JSON.parse(fs.readFileSync(uploadFile, 'utf8')) : null;
  if (!upload || upload.sha256 !== sha256) {
    const form = new FormData(); form.set('file', new Blob([bytes], { type: 'model/gltf-binary' }), path.basename(source));
    const response = await fetch(bases.tripo + '/files', { method: 'POST', headers: { Authorization: `Bearer ${key('tripo')}` }, body: form });
    const data = await response.json(); if (!response.ok || data.code !== 0) throw new Error(`Tripo upload HTTP ${response.status}`);
    upload = { sha256, file_token: data.data.file_token }; fs.writeFileSync(uploadFile, JSON.stringify(upload, null, 2));
  }
  state.inventory.tripo_source = { file: path.relative(root, source), sha256, bytes: bytes.length,
    reason: 'Shipped Hero_H027.usdz has 23 joints (shoulders/toes, no fingers). Bind-pose mesh exported without skin; the rig is a donor only.' }; save();
  const name = `H027_rigcheck_${sha256.slice(0, 8)}`;
  state.selectedRigcheck = name; save();
  await submit(name, 'tripo', '/animations/rig-check', { input: upload.file_token }, 0);
  for (let i = 0; i < 30; i++) {
    const task = await refresh(name); report(name, task);
    if (finished.includes(task.status)) return task;
    await new Promise(r => setTimeout(r, 3000));
  }
}
async function rig() {
  const check = state.tasks[state.selectedRigcheck];
  if (check?.status !== 'success' || check.output?.riggable !== true) throw new Error('Successful compatible rig-check required');
  const task = await submit('H027_rig_v3', 'tripo', '/animations/rig', { input: check.request.input, model: 'v3.0-20260909', rig_type: 'biped', spec: 'mixamo', out_format: 'glb' }, 25);
  report('H027_rig_v3', await refresh('H027_rig_v3'));
  return task;
}
async function basics() {
  const rig = state.tasks.H027_rig_v3;
  if (rig?.status !== 'success') throw new Error('Successful v3 rig required');
  await submit('H027_idle_walk_run', 'tripo', '/animations/retarget', { input: rig.task_id, animations: ['preset:idle', 'preset:walk', 'preset:run'], animate_in_place: true, out_format: 'glb', export_with_geometry: true }, 30);
  report('H027_idle_walk_run', await refresh('H027_idle_walk_run'));
}
async function motion() {
  const spec = JSON.parse(fs.readFileSync(specFile, 'utf8'));
  const which = process.argv[3];
  const names = which === 'all' ? Object.keys(spec.motions) : [which];
  for (const name of names) {
    const m = spec.motions[name];
    if (!m) throw new Error(`unknown motion ${name}`);
    if (m.prompt.length > 400) throw new Error(`${name}: prompt exceeds 400 characters`);
    const prior = state.tasks[name];
    // 429 (queue full) is refused before acceptance and never charged: archive it and submit again.
    if (prior?.status === 'REJECTED' && prior.http_status === 429 && !prior.task_id) {
      (state.rejected_attempts ??= []).push({ ...prior, name, archived_at: new Date().toISOString() }); delete state.tasks[name]; save();
    } else if (prior?.status === 'REJECTED') { console.log(`${name}: previously rejected (${prior.http_status}); not resubmitting`); continue; }
    try { await submit(name, 'meshy', '/openapi/v1/text-to-motion', { mode: 'prime', duration: m.duration, prompt: m.prompt }, 10); }
    catch (error) { if (error.status === 429) { console.log(`${name}: queue full (429, not charged); run again later`); break; } throw error; }
    report(name, state.tasks[name]);
    continue;
    await submit(name, 'meshy', '/openapi/v1/text-to-motion', { mode: 'prime', duration: m.duration, prompt: m.prompt }, 10);
    report(name, state.tasks[name]);
  }
}
async function poll() {
  for (const name of Object.keys(state.tasks)) {
    const t = state.tasks[name];
    if (t.file && finished.includes(t.status)) { report(name, t); continue; }
    try { report(name, await refresh(name)); } catch (error) { console.log(name, scrub(error.message)); }
  }
}
async function manifest() {
  const tasks = Object.entries(state.tasks).map(([name, t]) => ({ name, provider: t.provider, task_id: t.task_id ?? null, status: t.status,
    http_status: t.http_status ?? null, credits_consumed: t.credits_consumed ?? t.consumed_credits ?? 0, submitted_at: t.submitted_at,
    request: Object.fromEntries(Object.entries(t.request ?? {}).filter(([k]) => k !== 'input')), output: t.output ?? null,
    file: t.file ? { ...t.file, file: t.file.file.replaceAll('\\', '/') } : null, error: t.error ?? null }));
  const extra = ['finish-report.json', 'prime-report.json'].map(f => path.join(dir, f)).filter(f => fs.existsSync(f))
    .map(f => [path.basename(f, '.json'), JSON.parse(fs.readFileSync(f, 'utf8'))])
    // per-frame joint positions stay in build/ (too large for docs); keep the round-trip check and frame counts
    .map(([k, v]) => [k, k === 'prime-report' ? Object.fromEntries(Object.entries(v).map(([n, r]) => [n, { task_id: r.task_id, frames: r.frames,
      fps: r.fps, verify: r.verify, rootRebaseY: r.rootRebaseY }])) : v]);
  const result = { version: 1, hero: 'H027', recorded_at: new Date().toISOString(), credit_cap: state.budget, credits_consumed: state.api_credit_total,
    meshy_library: state.inventory.meshy_library, tasks, retained_existing_model: true, source: state.inventory.tripo_source,
    spear_regeneration: { tool: 'tools/tripo.mjs run props dragonSpear --force concept,model --faces 20000 (state: tools/tripo/state.json)',
      credits: 65, lod: 'tools/blender/lod_h027_spear.py (19,131 -> 4,198 triangles, head 3,898 / shaft 300, seams welded first)' },
    reports: Object.fromEntries(extra),
    references: { meshy_motion: 'https://docs.meshy.ai/api/text-to-motion', meshy_library: 'https://docs.meshy.ai/api/animation-library',
      tripo_rig: 'https://developers.tripo3d.ai/en/docs/animations-rig', tripo_check: 'https://developers.tripo3d.ai/en/docs/animations-rig-check',
      tripo_retarget: 'https://developers.tripo3d.ai/en/docs/animations-retarget' } };
  const output = path.join(root, 'docs', 'MOTION_H027_API.json'); fs.writeFileSync(output, JSON.stringify(scrub(result), null, 2) + '\n'); console.log(path.relative(root, output));
}
try {
  const commands = { inventory, rigcheck, rig, basics, motion, poll, manifest };
  const command = commands[process.argv[2]];
  if (!command) throw new Error('usage: node tools/h027_motion_api.mjs inventory|rigcheck|rig|basics|motion <name|all>|poll|manifest');
  await command();
} catch (error) { console.error(scrub(error.message)); process.exitCode = 1; }
