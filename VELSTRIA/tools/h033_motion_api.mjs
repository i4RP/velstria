#!/usr/bin/env node
// Resumable H033 (ヴァルド) motion acquisition. Credentials come from MESHY_API_KEY / TRIPO_API_KEY
// (or ~/.config/<provider>/api_key) and are never written to disk or logs.
// `submit [name...]` creates at most one Meshy prime task per motion (journal prevents re-billing);
// `poll` checks every pending task and downloads finished FBX into build/h033-motion/;
// `inventory` saves balances + the Animation Library list; `manifest` writes sanitized provenance.
// No paid request is retried automatically. A submission without task_id is "uncertain": inspect before resubmitting.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'build', 'h033-motion');
const journal = path.join(dir, 'api-state.json');
fs.mkdirSync(dir, { recursive: true });
const state = fs.existsSync(journal) ? JSON.parse(fs.readFileSync(journal, 'utf8'))
  : { version: 1, hero: 'H033', budget: { meshy: 120, tripo: 0 }, tasks: {}, inventory: {} };
const base = 'https://api.meshy.ai';
let cachedKey;
const key = () => cachedKey ||= (process.env.MESHY_API_KEY || fs.readFileSync(path.join(os.homedir(), '.config', 'meshy', 'api_key'), 'utf8')).trim();
function save() {
  state.api_credit_total = { meshy: Object.values(state.tasks).reduce((n, t) => n + (t.consumed_credits ?? 0), 0), tripo: 0 };
  fs.writeFileSync(journal + '.tmp', JSON.stringify(state, null, 2) + '\n'); fs.renameSync(journal + '.tmp', journal);
}
function scrub(v) {
  if (Array.isArray(v)) return v.map(scrub);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).filter(([k]) => !/url|token/i.test(k)).map(([k, x]) => [k, scrub(x)]));
  if (typeof v === 'string') return v.replace(/https?:\/\/\S+/g, '<url>').replace(/(?:msy_|tsk_)[A-Za-z0-9]+/g, '<credential>');
  return v;
}
async function api(route, method = 'GET', body) {
  const r = await fetch(base + route, { method, headers: { Authorization: `Bearer ${key()}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) { const e = new Error(`meshy ${method} ${route}: HTTP ${r.status} ${JSON.stringify(scrub(data))}`); e.status = r.status; throw e; }
  return data;
}

// One prime candidate per motion. Prompts <= 400 chars; durations 2-10 s in 0.5 s steps.
// Sword: one-handed in the RIGHT hand (silver gauntlet), left hand free. Blade edge leads the swing.
export const MOTIONS = {
  idle: { duration: 4, prompt: 'Seamless looping combat idle. Swordsman holds a huge greatsword one-handed in right hand, blade low and forward by right leg, edge down. Right shoulder and right foot forward, knees soft, weight centered. Slow deep breath, tiny weight shift between feet, head and chest calmly scan left then right. Free left hand relaxed, fingers flex slightly. Feet planted. Ends exactly in start pose.' },
  walk: { duration: 3, prompt: 'Looping heavy confident walk forward. Right hand carries a huge greatsword one-handed at right side, blade angled down and back, arm firm and steady. Long grounded strides, heel then toe, shoulders lag slightly behind hips, calm upright chest, small vertical bob. Left arm swings naturally. Even rhythm, every step same length.' },
  run: { duration: 2, prompt: 'Looping fast run forward. Torso leans forward, right hand holds a huge greatsword one-handed low behind right hip, blade trailing back close to body, arm stable. Powerful long strides, knees drive up, feet push off strongly, left arm pumps. Head steady looking ahead. Even rhythm, seamless loop.' },
  // Second candidate only for run: the first take is a 5 m/s sprint with long flight (game speed ~2.6 m/s).
  run2: { duration: 2, prompt: 'Looping steady heavy jog forward, moderate speed, not a sprint. Torso leans slightly forward, right hand holds a huge greatsword one-handed low at right side, blade trailing back along the body, arm firm. Short grounded strides, feet stay close to ground, little bounce, left arm swings. Head steady. Even rhythm, seamless loop.' },
  attack1: { duration: 2.5, prompt: 'Heavy one-handed greatsword slash, right hand. From ready stance, small crouch, raise sword high over right shoulder, blade back. Short pause, then hips rotate left and chest follows as the arm drives the blade diagonally down across the front to low left in a wide fast arc. Torso absorbs the weight, brief hold, then quickly return to ready stance, sword low at right. Feet stay planted.' },
  attack2: { duration: 2.5, prompt: 'Heavy one-handed backhand greatsword sweep, right hand. From ready stance, wind sword across body to low left, shoulders coil left. Brief pause, then hips and chest uncoil right and the blade sweeps horizontally from left to right at waist height in a wide arc. Momentum stopped by core, brief hold, then quickly return to ready stance, sword low at right. Feet planted.' },
  attack3: { duration: 2.5, prompt: 'Powerful one-handed overhead greatsword chop, right hand. From ready stance, step left foot slightly, lift sword straight up above head, back arches. Tiny pause, then whole body drops and the blade slams straight down in front, hips and chest driving the weight, knees bend on impact. Hold briefly, then rise and return to ready stance, sword low at right side.' },
  s1_leap: { duration: 2.5, prompt: 'Leaping greatsword slam. Holding huge greatsword in right hand, crouch then jump forward high, raising sword with both hands above head while in the air. On landing, both feet hit ground and the sword slams straight down in front at the exact landing moment, knees deep bent. Hold, then rise to ready stance, sword low in right hand.' },
  s2_spin: { duration: 2, prompt: 'Spinning greatsword slash. Holding huge greatsword one-handed in right hand extended outward at waist height, swordsman spins counterclockwise in place one and a half turns fast, blade sweeping a full horizontal circle, feet pivoting on balls. Stops facing forward, core braces, sword low at right side, ready stance.' },
  ult_absorb: { duration: 2, prompt: 'Greatsword power absorb. Holding huge greatsword in right hand, swordsman quickly raises the sword vertically above head, point up, left hand open reaching up beside it, chest lifts and head tilts back, drawing energy in. Brief hold, then lowers sword to ready stance at right side. Feet planted.' },
  ult_wave: { duration: 2, prompt: 'Forward greatsword shockwave swing. Holding huge greatsword in right hand, quick windup lifting blade back over right shoulder, then step forward with left foot and swing the blade powerfully down and forward in front, arm extended, body leaning into it to launch a wave. Brief hold, then return to ready stance, sword low at right side.' },
};
for (const [n, m] of Object.entries(MOTIONS)) if (m.prompt.length > 400) throw new Error(`${n} prompt ${m.prompt.length} > 400`);

async function inventory() {
  state.inventory.meshy_balance = { ...(await api('/openapi/v1/balance')), checked_at: new Date().toISOString() }; save();
  const lib = await api('/openapi/v1/animations/library');
  const list = Array.isArray(lib) ? lib : lib.result || lib.data || [];
  fs.writeFileSync(path.join(dir, 'meshy-library.json'), JSON.stringify(scrub(list), null, 2));
  const ids = [0, 11, 21, 89, 91, 97, 99, 102, 128, 219, 221, 237, 238, 242, 86, 382];
  state.inventory.meshy_library = { count: list.length, candidates: list.filter(x => ids.includes(x.action_id)), checked_at: new Date().toISOString() }; save();
  console.log(JSON.stringify({ balance: state.inventory.meshy_balance.balance, library: list.length }, null, 2));
}
async function submit(names) {
  for (const name of names.length ? names : Object.keys(MOTIONS)) {
    const m = MOTIONS[name]; if (!m) throw new Error(`unknown motion ${name}`);
    if (state.tasks[name]) { console.log(name, 'already', state.tasks[name].status); continue; }
    const committed = Object.values(state.tasks).reduce((n, t) => n + (t.consumed_credits ?? t.estimate ?? 0), 0);
    if (committed + 10 > state.budget.meshy) throw new Error('Meshy H033 credit cap reached');
    const request = { mode: 'prime', duration: m.duration, prompt: m.prompt };
    const task = state.tasks[name] = { provider: 'meshy', status: 'submitting', request, estimate: 10, submitted_at: new Date().toISOString() }; save();
    try { const d = await api('/openapi/v1/text-to-motion', 'POST', request); task.task_id = d.result; task.status = 'PENDING'; }
    catch (e) {
      // 429 NoMorePendingTasks = queue full (other heroes share the account): nothing was created or billed.
      if (e.status === 429) { delete state.tasks[name]; save(); console.log(name, 'queue full'); return false; }
      Object.assign(task, { status: e.status ? 'REJECTED' : 'unknown', http_status: e.status, error: scrub(e.message) }); if (e.status) task.consumed_credits = 0;
    }
    save(); console.log(name, task.status, task.task_id ?? '');
  }
}
async function download(url, name) {
  const target = path.join(dir, name);
  if (!fs.existsSync(target)) {
    const r = await fetch(url); if (!r.ok) throw new Error(`download ${name}: HTTP ${r.status}`);
    fs.writeFileSync(target, Buffer.from(await r.arrayBuffer()));
  }
  const b = fs.readFileSync(target);
  return { file: path.relative(root, target).replaceAll('\\', '/'), bytes: b.length, sha256: crypto.createHash('sha256').update(b).digest('hex') };
}
async function poll() {
  for (const [name, t] of Object.entries(state.tasks)) {
    if (!t.task_id || t.file) { console.log(name, t.status, t.file?.file ?? ''); continue; }
    const d = await api(`/openapi/v1/text-to-motion/${t.task_id}`);
    Object.assign(t, scrub(d), { checked_at: new Date().toISOString() });
    if (d.status === 'SUCCEEDED') {
      t.consumed_credits = d.consumed_credits ?? d.credits ?? t.estimate;
      const url = d.result?.motion_url || d.result?.animation_fbx_url || d.motion_url;
      if (url) t.file = await download(url, `${name}.fbx`);
      else t.result_keys = Object.keys(d.result ?? d);
    } else if (['FAILED', 'CANCELED'].includes(d.status)) t.consumed_credits = 0;
    save(); console.log(name, d.status, d.progress ?? '', t.file?.file ?? '');
  }
}
function manifest() {
  const report = fs.existsSync(path.join(dir, 'finish-report.json')) ? JSON.parse(fs.readFileSync(path.join(dir, 'finish-report.json'), 'utf8')) : null;
  const out = { version: 1, hero: 'H033', recorded_at: new Date().toISOString(), credit_cap: state.budget, credits_consumed: state.api_credit_total,
    meshy_library: state.inventory.meshy_library ? { count: state.inventory.meshy_library.count, candidates: state.inventory.meshy_library.candidates } : null,
    tasks: Object.entries(state.tasks).map(([name, t]) => ({ name, provider: t.provider, task_id: t.task_id ?? null, status: t.status, credits_consumed: t.consumed_credits ?? 0,
      submitted_at: t.submitted_at, request: t.request, file: t.file ?? null, error: t.error ?? null })),
    retained_existing_model: true, finish: report,
    references: ['https://docs.meshy.ai/en/api/text-to-motion', 'https://docs.meshy.ai/en/api/animation-library'] };
  const f = path.join(root, 'docs', 'MOTION_H033_API.json'); fs.writeFileSync(f, JSON.stringify(out, null, 2) + '\n'); console.log(path.relative(root, f));
}
// `run`: submit one at a time whenever the shared queue has room, poll until every motion is downloaded.
async function run() {
  for (;;) {
    for (const [n, t] of Object.entries(state.tasks)) if (t.status === 'REJECTED' && t.http_status === 429) delete state.tasks[n];
    const todo = Object.keys(MOTIONS).filter(n => !state.tasks[n]);
    for (const n of todo) if ((await submit([n])) === false) break;
    await poll();
    const open = Object.keys(MOTIONS).filter(n => !state.tasks[n] || (!state.tasks[n].file && !['FAILED', 'CANCELED', 'REJECTED', 'unknown'].includes(state.tasks[n].status)));
    if (!open.length) return;
    await new Promise(r => setTimeout(r, 20000));
  }
}
const [cmd, ...rest] = process.argv.slice(2);
const commands = { inventory, submit: () => submit(rest), poll, manifest, run };
try { if (!commands[cmd]) console.error('usage: inventory|submit [names]|poll|run|manifest'); else await commands[cmd](); }
catch (e) { console.error(scrub(e.message)); process.exitCode = 1; }
