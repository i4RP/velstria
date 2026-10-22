#!/usr/bin/env node
// スキルの攻撃演出に使うメッシュの生成（再開可能）: 参照画像（Tripo text-to-image）→ メッシュ（Tripo image-to-model、テクスチャ無し）。
// 仕様は tools/vfx_assets/skill_meshes.json、状態は tools/vfx_assets/skill_meshes_state.json（task_id・費用のみ。秘密は書かない）。
// 生成物は build/skill-meshes/<id>/（image.png・model.glb）。fxm への変換は blender/skill_mesh_to_fxm.py。
//   node tools/vfx_assets/skill_meshes.mjs run <id...|all> [--until image] [--max-credits N]
//   node tools/vfx_assets/skill_meshes.mjs status
// キーは env TRIPO_API_KEY か ~/.config/tripo/api_key。有料の送信は自動で再送しない（送信結果が不明なら状態を確認する）。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const SPEC = path.join(ROOT, 'tools/vfx_assets/skill_meshes.json');
const STATE = path.join(ROOT, 'tools/vfx_assets/skill_meshes_state.json');
const OUT = path.join(ROOT, 'build/skill-meshes');
const BASE = 'https://openapi.tripo3d.ai/v3';
const spec = JSON.parse(fs.readFileSync(SPEC, 'utf8'));
const state = fs.existsSync(STATE) ? JSON.parse(fs.readFileSync(STATE, 'utf8')) : { version: 1, assets: {} };
const save = () => { state.updated_at = new Date().toISOString(); fs.writeFileSync(STATE + '.tmp', JSON.stringify(state, null, 2) + '\n'); fs.renameSync(STATE + '.tmp', STATE); };
let apiKey;
const key = () => apiKey ||= (process.env.TRIPO_API_KEY || fs.readFileSync(path.join(os.homedir(), '.config/tripo/api_key'), 'utf8')).trim();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const scrub = (s) => String(s).replace(/https?:\/\/\S+/g, '<url>').replace(/tsk_[A-Za-z0-9]+/g, '<credential>');

async function call(method, route, body) {
  const r = await fetch(BASE + route, { method, headers: { Authorization: `Bearer ${key()}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const d = await r.json().catch(() => ({}));
  if (!r.ok || d.code !== 0) { const e = new Error(`${method} ${route}: HTTP ${r.status} ${scrub(JSON.stringify(d))}`); e.status = r.status; throw e; }
  return d.data;
}
async function upload(file) {
  const form = new FormData();
  form.set('file', new Blob([fs.readFileSync(file)], { type: 'image/png' }), path.basename(file));
  const r = await fetch(BASE + '/files', { method: 'POST', headers: { Authorization: `Bearer ${key()}` }, body: form });
  const d = await r.json();
  if (!r.ok || d.code !== 0) throw new Error(`upload: HTTP ${r.status} ${scrub(JSON.stringify(d))}`);
  return d.data.file_token;
}
async function download(url, file) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`download ${path.basename(file)}: HTTP ${r.status}`);
  fs.writeFileSync(file, Buffer.from(await r.arrayBuffer()));
}
async function wait(taskId) {
  for (;;) {
    const t = await call('GET', `/tasks/${taskId}`);
    if (['success', 'failed', 'cancelled', 'banned', 'expired', 'unknown'].includes(t.status)) return t;
    await sleep(5000);
  }
}
const spent = () => Object.values(state.assets).flatMap((a) => Object.values(a)).reduce((n, s) => n + (Number(s.credits) || 0), 0);

async function stage(a, name, request, route, maxCredits) {
  const st = (state.assets[a.id] ||= {});
  let s = st[name];
  if (s?.status === 'success') return s;
  if (s?.status === 'submitted' && !s.task_id) throw new Error(`${a.id}/${name}: 送信結果が不明（再送しない）`);
  if (!s || ['failed', 'cancelled', 'banned', 'expired', 'rejected'].includes(s.status)) {
    if (maxCredits !== undefined && spent() >= maxCredits) throw new Error(`--max-credits ${maxCredits} に達した（使用 ${spent()}）`);
    s = st[name] = { status: 'submitted', request: { ...request, input: request.input ? '<file_token>' : undefined }, submitted_at: new Date().toISOString() };
    save();
    for (let n = 0; ; n++) {
      try { s.task_id = (await call('POST', route, request)).task_id; break; } catch (e) {
        // 429（生成の上限）は受け付け前の拒否で課金されない → 待って送り直す
        if (e.status === 429 && n < 40) { await sleep(30000); continue; }
        s.status = 'rejected'; s.error = e.message; save(); throw e;
      }
    }
    save();
  }
  const t = await wait(s.task_id);
  s.status = t.status; s.credits = Number(t.credits_consumed ?? t.consumed_credits ?? 0); s.completed_at = new Date().toISOString();
  save();
  if (t.status !== 'success') throw new Error(`${a.id}/${name}: ${t.status}`);
  // 出力の URL（署名付き・期限あり）は状態に書かない
  Object.defineProperty(s, '_output', { value: t.output, enumerable: false, configurable: true });
  return s;
}

async function run(a, o) {
  const dir = path.join(OUT, a.id);
  fs.mkdirSync(dir, { recursive: true });
  const img = path.join(dir, 'image.png');
  if (!fs.existsSync(img)) {
    const prompt = `${spec.style.prefix} ${a.object}. ${spec.style.suffix} --no ${spec.style.negative}`;
    const s = await stage(a, 'image', { model: 'seedream_v5', prompt, size: '2048x2048', output_format: 'png' }, '/generation/text-to-image', o.maxCredits);
    const url = s._output?.image_url || s._output?.generated_image || Object.values(s._output || {}).find((v) => typeof v === 'string' && v.startsWith('http'));
    if (!url) throw new Error(`${a.id}: 画像の URL が無い ${Object.keys(s._output || {})}`);
    await download(url, img);
    console.log(`${a.id}: 画像 ${s.credits} credits`);
  }
  if (o.until === 'image') return;
  const glb = path.join(dir, 'model.glb');
  if (fs.existsSync(glb)) return;
  const token = await upload(img);
  const s = await stage(a, 'model', { input: token, model: 'P1-20260311', face_limit: a.faces || spec.faces, texture: false, pbr: false, export_uv: true },
    '/generation/image-to-model', o.maxCredits);
  const url = s._output?.model_url || s._output?.pbr_model_url || s._output?.base_model_url;
  if (!url) throw new Error(`${a.id}: モデルの URL が無い`);
  await download(url, glb);
  console.log(`${a.id}: モデル ${s.credits} credits`);
}

const [cmd, ...rest] = process.argv.slice(2);
const opt = { until: rest.includes('--until') ? rest[rest.indexOf('--until') + 1] : undefined,
  maxCredits: rest.includes('--max-credits') ? Number(rest[rest.indexOf('--max-credits') + 1]) : undefined };
const ids = rest.filter((x, i) => !x.startsWith('--') && !['--until', '--max-credits'].includes(rest[i - 1]));
try {
  if (cmd === 'status') {
    for (const a of spec.assets) { const s = state.assets[a.id] || {}; console.log(a.id.padEnd(10), (s.image?.status || '-').padEnd(9), (s.model?.status || '-').padEnd(9), (s.image?.credits ?? 0) + (s.model?.credits ?? 0)); }
    console.log('total', spent());
  } else if (cmd === 'run') {
    const list = ids.includes('all') ? spec.assets : spec.assets.filter((a) => ids.includes(a.id));
    const par = Number(process.env.PAR || 2);
    let i = 0, failed = 0;
    await Promise.all(Array.from({ length: par }, async () => {
      while (i < list.length) { const a = list[i++]; try { await run(a, opt); } catch (e) { failed++; console.error(`${a.id}: ${scrub(e.message)}`); } }
    }));
    console.log(`使用 ${spent()} credits、失敗 ${failed}`);
    if (failed) process.exitCode = 1;
  } else throw new Error('usage: run <id...|all> [--until image] [--max-credits N] | status');
} catch (e) { console.error(scrub(e.message)); process.exitCode = 1; }
