#!/usr/bin/env node
// H028 ザイルのモーション取得（再開可能）。キーは env（MESHY_API_KEY / TRIPO_API_KEY）か ~/.config/<provider>/api_key。
// 状態は build/h028-motion/api-state.json。有料の送信は 1 動作 1 回だけ（失敗・不確かな送信は自動で送り直さない）。
// 使い方（VELSTRIA/ で）:
//   node tools/h028_motion_api.mjs inventory          残高・Meshy ライブラリ（無料）
//   node tools/h028_motion_api.mjs rigcheck           既存モデルを Tripo へ上げて rig-check（無料）
//   node tools/h028_motion_api.mjs rig                指の骨を足す補修リグ（Tripo 25）
//   node tools/h028_motion_api.mjs motions [name..]   Meshy prime を送る・状態を見る・FBX を落とす（1 本 10）
//   node tools/h028_motion_api.mjs manifest           秘密を除いた記録を docs/MOTION_H028_API.json へ
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'build', 'h028-motion');
const journal = path.join(dir, 'api-state.json');
fs.mkdirSync(dir, { recursive: true });
const lockPath = journal + '.lock';
if (fs.existsSync(lockPath)) {
  const owner = Number(fs.readFileSync(lockPath, 'utf8'));
  try { process.kill(owner, 0); throw new Error('別の H028 取得プロセスが状態ファイルを使用中'); }
  catch (error) { if (error.code !== 'ESRCH') throw error; fs.unlinkSync(lockPath); }
}
const lock = fs.openSync(lockPath, 'wx'); fs.writeSync(lock, String(process.pid));
process.on('exit', () => { fs.closeSync(lock); fs.unlinkSync(lockPath); });

const state = fs.existsSync(journal) ? JSON.parse(fs.readFileSync(journal, 'utf8')) : {
  version: 1, hero: 'H028', budget: { meshy: 100, tripo: 55 }, tasks: {}, inventory: {},
};
const bases = { meshy: 'https://api.meshy.ai', tripo: 'https://openapi.tripo3d.ai/v3' };
const keys = {};
function save() {
  state.api_credit_total = Object.fromEntries(['meshy', 'tripo'].map(p => [p, Object.values(state.tasks)
    .filter(t => t.provider === p).reduce((n, t) => n + (t.credits_consumed ?? t.consumed_credits ?? 0), 0)]));
  fs.writeFileSync(journal + '.tmp', JSON.stringify(state, null, 2) + '\n'); fs.renameSync(journal + '.tmp', journal);
}
function key(p) { return keys[p] ||= (process.env[`${p.toUpperCase()}_API_KEY`] || fs.readFileSync(path.join(os.homedir(), '.config', p, 'api_key'), 'utf8')).trim(); }
function scrub(v) {
  if (Array.isArray(v)) return v.map(scrub);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).filter(([k]) => !/url|token/i.test(k)).map(([k, x]) => [k, scrub(x)]));
  if (typeof v === 'string') return v.replace(/https?:\/\/\S+/g, '<url>').replace(/(?:msy_|tsk_)[A-Za-z0-9]+/g, '<credential>');
  return v;
}
async function api(p, route, method = 'GET', body) {
  const res = await fetch(bases[p] + route, { method, headers: { Authorization: `Bearer ${key(p)}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const data = await res.json();
  if (!res.ok || (p === 'tripo' && data.code !== 0)) {
    const e = new Error(`${p} ${method} ${route}: HTTP ${res.status} ${JSON.stringify(scrub(data))}`); e.status = res.status; throw e;
  }
  return p === 'tripo' ? data.data : data;
}
async function download(url, name) {
  const target = path.join(dir, name);
  if (!fs.existsSync(target)) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`download ${name}: HTTP ${res.status}`);
    fs.writeFileSync(target + '.part', Buffer.from(await res.arrayBuffer())); fs.renameSync(target + '.part', target);
  }
  const buf = fs.readFileSync(target);
  return { file: path.relative(root, target), bytes: buf.length, sha256: crypto.createHash('sha256').update(buf).digest('hex') };
}
function reject(task, error) {
  // 受け付け前の拒否（4xx）は課金されない。通信切れ等は送れたか分からないので unknown（自動で送り直さない）
  const definite = [400, 401, 402, 403, 404, 413, 415, 422, 429].includes(error.status);
  Object.assign(task, { status: definite ? 'REJECTED' : 'unknown', http_status: error.status, error: scrub(error.message), checked_at: new Date().toISOString() });
  if (definite) task.consumed_credits = 0;
  save();
}
function spent(p) {
  return Object.values(state.tasks).filter(t => t.provider === p && t.status !== 'REJECTED')
    .reduce((n, t) => n + (t.credits_consumed ?? t.consumed_credits ?? t.estimate ?? 0), 0);
}

// 剣は右手。待機・移動はループ、攻撃は構え → 斬撃 → 構えへ戻るまで。400 文字以内（送る前に確かめる）。
const MOTIONS = {
  idle_prime: { duration: 4, prompt: 'Calm armored male sword assassin, loopable idle in a low half-turned guard. Left foot forward, knees bent, hips low and steady. Right hand grips a long sword low beside the right thigh, blade angled forward and down, wrist firm. Slow breathing, tiny weight shift between feet. Head turns first, left shoulder and open left hand follow; left fingers flex lightly. Feet planted. Ends in start pose.' },
  walk_prime: { duration: 3, prompt: 'Armored male sword assassin walking forward in a low crouched stance, steady pace, loopable cycle. Hips stay low, knees bent, quick short steps, feet recovered close to the ground. Upper body calm and quiet, slight forward lean. Right hand holds a long sword low at the right side, blade pointing back and down, away from the legs. Left arm swings a little. Even rhythm, no turning.' },
  run_prime: { duration: 3, prompt: 'Armored male sword assassin sprinting forward fast with a deep forward lean and low hips, loopable cycle. Quick light strides, feet skimming close to the ground. Right hand grips a long sword trailing behind and down, arm extended back, blade swept away from the legs. Left arm pumps compactly near the chest. Head level, eyes forward. Steady rhythm, no turning.' },
  // 2 案目（1 案目の待機は深いしゃがみで両手が膝、歩行は途中で振り返った）
  idle2_prime: { duration: 4, prompt: 'Armored male swordsman in a calm, slightly lowered ready stance, loopable idle. Feet shoulder width, left foot half a step forward, knees softly bent, back straight, not squatting. Right hand holds a long sword low and forward at hip height, arm relaxed. Left hand open near the left hip, fingers flexing slightly. Slow breathing, small weight shift, head glances aside. Ends in start pose.' },
  walk2_prime: { duration: 3, prompt: 'Armored male swordsman walking straight forward in a line at a steady pace, never turning. Slightly lowered hips, knees bent, short quick steps with feet low to the ground, heel to toe. Torso calm and upright with a slight forward lean. Right hand holds a long sword low at the right side, blade pointing back. Left arm swings gently. Even steps, loopable cycle.' },
  attack_prime: { duration: 4.5, prompt: 'Armored male sword assassin, long sword in right hand, three fast basic attacks from a low guard. One: small coil, step in, diagonal slash from right shoulder down to left hip. Two: hips twist, quick horizontal backhand slash left to right. Three: brief crouch, rising diagonal slash with the whole body. After each cut the torso stops the blade and he settles into a low guard. Feet end near start.' },
  skill1_prime: { duration: 2.5, prompt: 'Armored male sword assassin, long sword in right hand. From a low stance he whirls the sword in one full horizontal circle around his body at waist height, torso turning with it, then flings both arms wide open outward in a sharp release, as if launching blades in all directions. Short hold, then returns to a low guard. Feet planted, no travel.' },
  skill2_prime: { duration: 2, prompt: 'Armored male sword assassin, long sword in right hand. Explosive forward dash: drops into a deep forward lean, sword pulled back low behind the right hip, covers about three meters in a few long low strides, then plants the front foot and stops in a crouched ready stance with the sword cocked back for the next slash. Holds the ready stance.' },
  ult_prime: { duration: 3, prompt: 'Armored male sword assassin, long sword in right hand. Rushes forward in a deep low lean, arrives with a rising upward slash, then two quick light slashes, right to left and left to right, then a big full body overhead finishing slash straight down with a deep lunge. Holds the low finish briefly, then rises back to a low guard. Clear rhythm: slash, slash, slash, finisher.' },
};

async function inventory() {
  state.inventory.meshy_balance = { ...(await api('meshy', '/openapi/v1/balance')), checked_at: new Date().toISOString() };
  state.inventory.tripo_balance = { ...(await api('tripo', '/account/balance')), checked_at: new Date().toISOString() };
  const lib = await api('meshy', '/openapi/v1/animations/library');
  fs.writeFileSync(path.join(dir, 'meshy-library.json'), JSON.stringify(scrub(lib), null, 2));
  const list = Array.isArray(lib) ? lib : lib.result || [];
  const candidates = [0, 11, 21, 89, 97, 105, 219, 240, 241, 242, 509, 510, 546, 689, 91, 102];
  state.inventory.meshy_library = { count: list.length, candidates: list.filter(x => candidates.includes(x.action_id)).map(x => ({ action_id: x.action_id, name: x.name, category: x.category, sub_category: x.sub_category })), checked_at: new Date().toISOString() };
  save();
  console.log(JSON.stringify({ meshy: state.inventory.meshy_balance.balance, tripo: state.inventory.tripo_balance.balance, library: state.inventory.meshy_library.count }, null, 2));
}

async function tripoTask(name, route, request, estimate) {
  let task = state.tasks[name];
  if (!task) {
    if (spent('tripo') + estimate > state.budget.tripo) throw new Error('Tripo の予算上限');
    const bal = await api('tripo', '/account/balance');
    if (bal.balance < estimate) throw new Error('Tripo の残高不足');
    task = state.tasks[name] = { provider: 'tripo', status: 'submitting', request, estimate, submitted_at: new Date().toISOString() }; save();
    try { const data = await api('tripo', route, 'POST', request); task.task_id = data.task_id; task.status = 'queued'; save(); }
    catch (e) { reject(task, e); throw e; }
  }
  if (!task.task_id) throw new Error(`${name}: task_id の無い送信。状態を調べてから判断する（自動で送り直さない）`);
  const data = await api('tripo', `/tasks/${task.task_id}`);
  Object.assign(task, scrub(data), { checked_at: new Date().toISOString() }); save();
  if (data.status === 'success' && data.output?.model_url) { task.file = await download(data.output.model_url, `${name}.glb`); save(); }
  console.log(name, task.status, task.progress ?? '', task.credits_consumed ?? '', task.output ? JSON.stringify(task.output) : '');
  return task;
}
async function rigcheck() {
  // 完成済みモデル（取り込み前の Tripo 出力。テクスチャ・形状はそのまま）を渡し、骨だけ補修できるか調べる
  const source = path.resolve(process.argv[3] || path.join(root, '..', '..', 'vel-h25', 'VELSTRIA', 'build', 'tripo', 'heroes', 'H028', 'model.glb'));
  const bytes = fs.readFileSync(source), sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  const uploadFile = path.join(dir, 'tripo-upload.json');
  let upload = fs.existsSync(uploadFile) ? JSON.parse(fs.readFileSync(uploadFile, 'utf8')) : null;
  if (!upload || upload.sha256 !== sha256) {
    const form = new FormData(); form.set('file', new Blob([bytes], { type: 'model/gltf-binary' }), 'H028_model.glb');
    const res = await fetch(bases.tripo + '/files', { method: 'POST', headers: { Authorization: `Bearer ${key('tripo')}` }, body: form });
    const data = await res.json(); if (!res.ok || data.code !== 0) throw new Error(`Tripo upload HTTP ${res.status} ${JSON.stringify(scrub(data))}`);
    upload = { sha256, file_token: data.data.file_token }; fs.writeFileSync(uploadFile, JSON.stringify(upload, null, 2));
  }
  state.inventory.tripo_source = { file: path.basename(source), sha256, bytes: bytes.length, reason: '既存 H028 の骨は 23 本（肩・つま先あり、指なし）。形状・テクスチャを保ったまま指の骨を足す' }; save();
  return tripoTask('H028_rigcheck', '/animations/rig-check', { input: upload.file_token }, 0);
}
async function rig() {
  const check = state.tasks.H028_rigcheck;
  if (check?.status !== 'success' || check.output?.riggable !== true) throw new Error('rig-check の成功（riggable）が必要');
  return tripoTask('H028_rig_v3', '/animations/rig', { input: check.request.input, model: 'v3.0-20260909', rig_type: 'biped', spec: 'mixamo', out_format: 'glb' }, 25);
}
async function motions() {
  const names = process.argv.slice(3).length ? process.argv.slice(3) : Object.keys(MOTIONS);
  for (const name of names) {
    const spec = MOTIONS[name];
    if (!spec) throw new Error(`未知の動作 ${name}`);
    let task = state.tasks[name];
    if (task?.status === 'REJECTED' && task.http_status === 429) { delete state.tasks[name]; task = undefined; save(); }
    if (!task) {
      if (spec.prompt.length > 400) throw new Error(`${name}: プロンプトが 400 文字を超える (${spec.prompt.length})`);
      if (spent('meshy') + 10 > state.budget.meshy) { console.log(name, 'Meshy の予算上限'); continue; }
      const bal = await api('meshy', '/openapi/v1/balance');
      if (Number(bal.balance) < 10) throw new Error('Meshy の残高不足');
      const request = { mode: 'prime', duration: spec.duration, prompt: spec.prompt };
      task = state.tasks[name] = { provider: 'meshy', status: 'submitting', request, estimate: 10, submitted_at: new Date().toISOString() }; save();
      try { const data = await api('meshy', '/openapi/v1/text-to-motion', 'POST', request); task.task_id = data.result; task.status = 'PENDING'; save(); }
      catch (e) { reject(task, e); console.log(name, 'rejected', task.error); continue; }
    }
    if (!task.task_id) { console.log(name, task.status, '（task_id 無し。自動で送り直さない）'); continue; }
    const data = await api('meshy', `/openapi/v1/text-to-motion/${task.task_id}`);
    Object.assign(task, scrub(data), { checked_at: new Date().toISOString() });
    if (data.status === 'SUCCEEDED') {
      task.consumed_credits = data.consumed_credits ?? 10;
      const url = data.result?.motion_url || data.result?.fbx_url || data.result?.animation_fbx_url;
      if (url) task.file = await download(url, `${name}.fbx`);
    }
    save();
    console.log(name, task.status, task.progress ?? '', task.file?.file ?? '');
  }
}
async function manifest() {
  const tasks = Object.entries(state.tasks).map(([name, t]) => ({ name, provider: t.provider, task_id: t.task_id ?? null, status: t.status,
    http_status: t.http_status ?? null, credits_consumed: t.credits_consumed ?? t.consumed_credits ?? 0, submitted_at: t.submitted_at,
    request: Object.fromEntries(Object.entries(t.request ?? {}).filter(([k]) => k !== 'input')), output: t.output ?? null,
    file: t.file ?? null, error: t.error ?? null }));
  const extra = fs.existsSync(path.join(dir, 'adoption.json')) ? JSON.parse(fs.readFileSync(path.join(dir, 'adoption.json'), 'utf8')) : null;
  const out = { version: 1, hero: 'H028', recorded_at: new Date().toISOString(), credit_cap: state.budget, credits_consumed: state.api_credit_total,
    meshy_library: state.inventory.meshy_library, tripo_source: state.inventory.tripo_source, tasks, adoption: extra,
    references: ['https://docs.meshy.ai/api/text-to-motion.md', 'https://docs.meshy.ai/api/animation-library.md', 'https://developers.tripo3d.ai/en/docs/llms.txt'] };
  const target = path.join(root, 'docs', 'MOTION_H028_API.json');
  fs.writeFileSync(target, JSON.stringify(out, null, 2) + '\n'); console.log(path.relative(root, target));
}
try {
  const commands = { inventory, rigcheck, rig, motions, manifest };
  const command = commands[process.argv[2]];
  if (!command) throw new Error('usage: node tools/h028_motion_api.mjs inventory|rigcheck|rig|motions|manifest');
  await command();
} catch (e) { console.error(scrub(e.message)); process.exitCode = 1; }
