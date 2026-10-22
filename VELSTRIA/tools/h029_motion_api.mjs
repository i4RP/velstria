#!/usr/bin/env node
// H029 ボルグの動作素材の取得（再開可能）。キーは env MESHY_API_KEY / TRIPO_API_KEY か ~/.config/<provider>/api_key。
// 有料の送信は自動で再送しない（送信結果が不明なら journal と各サービスのタスク一覧を確認する）。
// 同じコマンドを再実行すると完了待ち・取得だけ行う（retry_after を守る）。
//   node tools/h029_motion_api.mjs inventory            残高・Meshy Animation Library・既存の text-to-motion（無料）
//   node tools/h029_motion_api.mjs prime [name...]      Meshy text-to-motion prime（tools/motion/h029-prime-spec.json、1 動作 1 案 10）
//   node tools/h029_motion_api.mjs rigcheck <glb>       Tripo rig-check（無料）
//   node tools/h029_motion_api.mjs rig                  Tripo v3 リグ補修（指を足す、25）
//   node tools/h029_motion_api.mjs basics               Tripo idle/walk/run（animate_in_place、30）
//   node tools/h029_motion_api.mjs manifest             秘密を除いた記録を docs/MOTION_H029_API.json へ
// 状態は build/h029-motion/api-state.json（予算 budget を超える送信は拒否）。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'build', 'h029-motion');
const journal = path.join(dir, 'api-state.json');
const specFile = path.join(root, 'tools', 'motion', 'h029-prime-spec.json');
fs.mkdirSync(dir, { recursive: true });
const lockPath = journal + '.lock';
if (fs.existsSync(lockPath)) {
  const owner = Number(fs.readFileSync(lockPath, 'utf8'));
  try { process.kill(owner, 0); throw new Error('Another H029 acquisition process owns the journal'); }
  catch (error) { if (error.code !== 'ESRCH') throw error; fs.unlinkSync(lockPath); }
}
const lock = fs.openSync(lockPath, 'wx'); fs.writeSync(lock, String(process.pid));
process.on('exit', () => { fs.closeSync(lock); fs.unlinkSync(lockPath); });
const state = fs.existsSync(journal) ? JSON.parse(fs.readFileSync(journal, 'utf8'))
  : { version: 1, hero: 'H029', budget: { meshy: 100, tripo: 60 }, tasks: {}, inventory: {} };
const bases = { meshy: 'https://api.meshy.ai', tripo: 'https://openapi.tripo3d.ai/v3' };
const keys = {};
function save() {
  state.api_credit_total = Object.fromEntries(['meshy', 'tripo'].map((p) => [p, Object.values(state.tasks)
    .filter((t) => t.provider === p).reduce((n, t) => n + (t.credits_consumed ?? t.consumed_credits ?? 0), 0)]));
  fs.writeFileSync(journal + '.tmp', JSON.stringify(state, null, 2) + '\n'); fs.renameSync(journal + '.tmp', journal);
}
const key = (p) => keys[p] ||= (process.env[`${p.toUpperCase()}_API_KEY`] || fs.readFileSync(path.join(os.homedir(), '.config', p, 'api_key'), 'utf8')).trim();
function scrub(v) {
  if (Array.isArray(v)) return v.map(scrub);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).filter(([k]) => !/url|token/i.test(k)).map(([k, x]) => [k, scrub(x)]));
  if (typeof v === 'string') return v.replace(/https?:\/\/\S+/g, '<url>').replace(/(?:msy_|tsk_)[A-Za-z0-9]+/g, '<credential>');
  return v;
}
async function api(p, route, method = 'GET', body) {
  const r = await fetch(bases[p] + route, { method, headers: { Authorization: `Bearer ${key(p)}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const text = await r.text();
  let data; try { data = JSON.parse(text); } catch { data = { raw: text.slice(0, 200) }; }
  if (!r.ok || (p === 'tripo' && data.code !== 0)) { const e = new Error(`${p} ${method} ${route}: HTTP ${r.status} ${JSON.stringify(scrub(data))}`); e.status = r.status; throw e; }
  return { data: p === 'tripo' ? data.data : data, retryAfter: Number(r.headers.get('retry-after') || 5) };
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
// 送信済み（未完了を含む）の見積もりも数える
const committed = (p) => Object.values(state.tasks).filter((t) => t.provider === p && t.status !== 'REJECTED')
  .reduce((n, t) => n + (t.credits_consumed ?? t.consumed_credits ?? t.estimate ?? 0), 0);
function reject(task, error) {
  const definite = [400, 401, 402, 403, 404, 413, 415, 422, 429].includes(error.status);
  Object.assign(task, { status: definite ? 'REJECTED' : 'unknown', http_status: error.status ?? null, error: scrub(error.message), checked_at: new Date().toISOString() });
  if (definite) task.consumed_credits = 0;
  save();
}
function report(name, t) {
  console.log(JSON.stringify({ name, task_id: t.task_id, provider: t.provider, status: t.status, progress: t.progress,
    credits_consumed: t.credits_consumed ?? t.consumed_credits ?? null, file: t.file?.file, retry_after_seconds: t.retry_after_seconds }));
}

async function inventory() {
  for (const p of ['meshy', 'tripo']) {
    const { data } = await api(p, p === 'meshy' ? '/openapi/v1/balance' : '/account/balance');
    state.inventory[`${p}_balance`] = { ...scrub(data), checked_at: new Date().toISOString() }; save();
  }
  const { data: library } = await api('meshy', '/openapi/v1/animations/library');
  fs.writeFileSync(path.join(dir, 'meshy-library.json'), JSON.stringify(library, null, 2));
  const list = Array.isArray(library) ? library : library.result || library.data || [];
  const words = /idle|guard|shield|walk|run|sprint|charge|hammer|smash|slam|ground|overhead|uppercut|heavy|swing|chop|axe|strike|knight|warrior/i;
  state.inventory.meshy_library = { count: list.length, candidates: list.filter((x) => words.test(JSON.stringify(scrub(x))))
    .map((x) => scrub(x)), checked_at: new Date().toISOString() };
  save();
  try {
    const { data } = await api('meshy', '/openapi/v1/text-to-motion?page_num=1&page_size=50');
    state.inventory.existing_motion_tasks = scrub(data); save();
  } catch (error) { state.inventory.motion_list_error = scrub(error.message); save(); }
  console.log(JSON.stringify({ balances: [state.inventory.meshy_balance, state.inventory.tripo_balance],
    library: state.inventory.meshy_library.count, candidates: state.inventory.meshy_library.candidates.length }, null, 2));
}

async function prime() {
  const spec = JSON.parse(fs.readFileSync(specFile, 'utf8')).motions;
  const names = process.argv.slice(3).length ? process.argv.slice(3) : Object.keys(spec);
  for (const name of names) {
    const s = spec[name];
    if (!s) throw new Error(`unknown motion ${name}`);
    let task = state.tasks[name];
    if (task?.status === 'REJECTED') { report(name, task); continue; }
    if (!task) {
      const request = { prompt: s.prompt, mode: 'prime', duration: s.duration };
      if (request.prompt.length > 400) throw new Error(`${name}: prompt exceeds 400 characters`);
      if (committed('meshy') + 10 > state.budget.meshy) throw new Error('Meshy project credit cap reached');
      const { data: balance } = await api('meshy', '/openapi/v1/balance');
      if (Number(balance.balance) < 10) throw new Error('Insufficient Meshy credits');
      task = state.tasks[name] = { provider: 'meshy', kind: 'text-to-motion', status: 'submitting', request, estimate: 10, submitted_at: new Date().toISOString() }; save();
      try { const { data } = await api('meshy', '/openapi/v1/text-to-motion', 'POST', request); task.task_id = data.result; task.status = 'PENDING'; save(); }
      catch (error) {
        // 429 は受け付け前の拒否（課金なし）。記録を消して、次の実行で送り直せるようにする
        if (error.status === 429) { delete state.tasks[name]; save(); console.log(JSON.stringify({ name, status: 'RATE_LIMITED_RETRY_LATER' })); continue; }
        reject(task, error); report(name, task); continue;
      }
    }
    if (!task.task_id) throw new Error(`${name}: prior submission is uncertain; inspect the account before resubmitting`);
    const { data, retryAfter } = await api('meshy', `/openapi/v1/text-to-motion/${task.task_id}`);
    Object.assign(task, scrub(data), { checked_at: new Date().toISOString(), retry_after_seconds: retryAfter });
    if (data.status === 'SUCCEEDED') {
      task.credits_consumed = 10;
      if (data.result?.motion_url) task.file = await download(data.result.motion_url, `${name}.fbx`);
    }
    if (data.status === 'FAILED' || data.status === 'CANCELED') task.credits_consumed = 0;
    save(); report(name, task);
  }
}

async function tripoTask(name, route, request, estimate = 0) {
  let task = state.tasks[name];
  if (!task) {
    if (committed('tripo') + estimate > state.budget.tripo) throw new Error('Tripo project credit cap reached');
    if (estimate > 0) { const { data: b } = await api('tripo', '/account/balance'); if (b.balance < estimate) throw new Error('Insufficient Tripo credits'); }
    task = state.tasks[name] = { provider: 'tripo', status: 'submitting', request, estimate, submitted_at: new Date().toISOString() }; save();
    try { const { data } = await api('tripo', route, 'POST', request); task.task_id = data.task_id; task.status = 'queued'; save(); }
    catch (error) { reject(task, error); throw error; }
  }
  if (!task.task_id) throw new Error(`Prior ${name} submission has no task ID; inspect journal before any resubmission`);
  const { data, retryAfter } = await api('tripo', `/tasks/${task.task_id}`);
  Object.assign(task, scrub(data), { checked_at: new Date().toISOString(), retry_after_seconds: retryAfter }); save();
  if (data.status === 'success' && data.output?.model_url) { task.file = await download(data.output.model_url, `${name}.${request.out_format || 'glb'}`); save(); }
  report(name, task);
  return task;
}
async function rigcheck() {
  const source = path.resolve(process.argv[3] || path.join(dir, 'H029_original_model.glb'));
  const bytes = fs.readFileSync(source), sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  const uploadFile = path.join(dir, 'tripo-upload.json');
  let upload = fs.existsSync(uploadFile) ? JSON.parse(fs.readFileSync(uploadFile, 'utf8')) : null;
  if (!upload || upload.sha256 !== sha256) {
    const form = new FormData(); form.set('file', new Blob([bytes], { type: 'model/gltf-binary' }), 'H029_original_model.glb');
    const r = await fetch(bases.tripo + '/files', { method: 'POST', headers: { Authorization: `Bearer ${key('tripo')}` }, body: form });
    const data = await r.json(); if (!r.ok || data.code !== 0) throw new Error(`Tripo upload HTTP ${r.status} ${JSON.stringify(scrub(data))}`);
    upload = { sha256, file_token: data.data.file_token }; fs.writeFileSync(uploadFile, JSON.stringify(upload, null, 2));
  }
  state.inventory.tripo_source = { file: path.relative(root, source), sha256, bytes: bytes.length,
    reason: 'Production H029 rig has 23 joints and no fingers (open flat hands cannot grip the maul handle). Repair donor only; geometry and textures are kept.' }; save();
  return tripoTask('H029_rigcheck', '/animations/rig-check', { input: upload.file_token }, 0);
}
async function rig() {
  const check = state.tasks.H029_rigcheck;
  if (check?.status !== 'success' || check.output?.riggable !== true) throw new Error('Successful compatible rig-check required');
  return tripoTask('H029_rig_v3', '/animations/rig', { input: check.request.input, model: 'v3.0-20260909', rig_type: 'biped', spec: 'mixamo', out_format: 'glb' }, 25);
}
async function basics() {
  const r = state.tasks.H029_rig_v3;
  if (r?.status !== 'success') throw new Error('Successful v3 rig required');
  return tripoTask('H029_idle_walk_run', '/animations/retarget', { input: r.task_id, animations: ['preset:idle', 'preset:walk', 'preset:run'], animate_in_place: true, out_format: 'glb', export_with_geometry: true }, 30);
}
async function manifest() {
  const tasks = Object.entries(state.tasks).map(([name, t]) => ({ name, provider: t.provider, kind: t.kind ?? t.type ?? null, task_id: t.task_id ?? null, status: t.status,
    http_status: t.http_status ?? null, credits_consumed: t.credits_consumed ?? t.consumed_credits ?? 0, submitted_at: t.submitted_at,
    request: Object.fromEntries(Object.entries(t.request ?? {}).filter(([k]) => k !== 'input')), file: t.file ?? null, error: t.error ?? null }));
  const extra = fs.existsSync(path.join(dir, 'adoption.json')) ? JSON.parse(fs.readFileSync(path.join(dir, 'adoption.json'), 'utf8')) : null;
  const out = { version: 1, hero: 'H029', recorded_at: new Date().toISOString(), credit_cap: state.budget, credits_consumed: state.api_credit_total,
    meshy_library: state.inventory.meshy_library ? { count: state.inventory.meshy_library.count, reviewed: state.inventory.meshy_library.candidates?.map((c) => c.action_id ?? c.id ?? c.name) } : null,
    tasks, source: state.inventory.tripo_source ?? null, adoption: extra,
    references: ['https://docs.meshy.ai/api/text-to-motion.md', 'https://docs.meshy.ai/api/animation-library.md', 'https://developers.tripo3d.ai/en/docs/animations-rig.md', 'https://developers.tripo3d.ai/en/docs/animations-retarget.md'] };
  const file = path.join(root, 'docs', 'MOTION_H029_API.json'); fs.writeFileSync(file, JSON.stringify(out, null, 2) + '\n'); console.log(path.relative(root, file));
}
try {
  const commands = { inventory, prime, rigcheck, rig, basics, manifest };
  const command = commands[process.argv[2]];
  if (!command) throw new Error('usage: node tools/h029_motion_api.mjs inventory|prime [name...]|rigcheck [glb]|rig|basics|manifest');
  await command();
} catch (error) { console.error(scrub(error.message)); process.exitCode = 1; }
