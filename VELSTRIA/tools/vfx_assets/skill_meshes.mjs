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
// 複数のプロセス（Tripo 担当と Meshy 担当）が同じ状態ファイルへ書くので、触った件だけを最新の内容へ重ねて書く
const touched = new Set();
const save = () => {
  const cur = fs.existsSync(STATE) ? JSON.parse(fs.readFileSync(STATE, 'utf8')) : { version: 1, assets: {} };
  for (const id of touched) cur.assets[id] = state.assets[id];
  cur.updated_at = new Date().toISOString();
  const tmp = `${STATE}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(cur, null, 2) + '\n'); fs.renameSync(tmp, STATE);
};
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
// Meshy（provider: "meshy" の件のモデル）。キーは env MESHY_API_KEY か ~/.config/meshy/api_key
const MESHY = 'https://api.meshy.ai/openapi/v1';
let meshyKey;
const mkey = () => meshyKey ||= (process.env.MESHY_API_KEY || fs.readFileSync(path.join(os.homedir(), '.config/meshy/api_key'), 'utf8')).trim();
async function mcall(method, route, body) {
  const r = await fetch(MESHY + route, { method, headers: { Authorization: `Bearer ${mkey()}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) { const e = new Error(`meshy ${method} ${route}: HTTP ${r.status} ${scrub(JSON.stringify(d))}`); e.status = r.status; throw e; }
  return d;
}
async function meshyImage(a, img, o) {
  const st = (state.assets[a.id] ||= {});
  touched.add(a.id);
  let s = st.image;
  if (s?.status === 'submitted' && !s.task_id) throw new Error(`${a.id}/image: 送信結果が不明（再送しない）`);
  if (!s || s.status !== 'success') {
    const body = { ai_model: 'nano-banana-2', prompt: `${spec.style.prefix} ${a.object}. ${spec.style.suffix} Avoid: ${spec.style.negative}.`, aspect_ratio: '1:1' };
    s = st.image = { provider: 'meshy', status: 'submitted', request: body, submitted_at: new Date().toISOString() };
    save();
    for (let n = 0; ; n++) {
      try { s.task_id = (await mcall('POST', '/text-to-image', body)).result; break; } catch (e) {
        if (e.status === 429 && n < 60) { await sleep(30000); continue; }
        s.status = 'rejected'; s.error = e.message; save(); throw e;
      }
    }
    save();
  }
  let t;
  for (;;) { t = await mcall('GET', `/text-to-image/${s.task_id}`); if (['SUCCEEDED', 'FAILED', 'CANCELED'].includes(t.status)) break; await sleep(5000); }
  s.status = t.status === 'SUCCEEDED' ? 'success' : t.status; s.credits = t.status === 'SUCCEEDED' ? 6 : 0; s.completed_at = new Date().toISOString();
  save();
  if (t.status !== 'SUCCEEDED') throw new Error(`${a.id}/image: meshy ${t.status}`);
  await download(t.image_urls[0], img);
  console.log(`${a.id}: 画像（Meshy）`);
}

async function meshyModel(a, img, glb, o) {
  const st = (state.assets[a.id] ||= {});
  touched.add(a.id);
  let s = st.model;
  if (s?.status === 'submitted' && !s.task_id) throw new Error(`${a.id}/model: 送信結果が不明（再送しない）`);
  if (!s || ['failed', 'rejected', 'FAILED', 'CANCELED'].includes(s.status)) {
    if (o.maxCredits !== undefined && spent() >= o.maxCredits) throw new Error(`--max-credits ${o.maxCredits} に達した（使用 ${spent()}）`);
    const body = { image_url: `data:image/png;base64,${fs.readFileSync(img).toString('base64')}`, ai_model: 'meshy-6', should_texture: false,
      should_remesh: true, topology: 'triangle', target_polycount: a.faces || spec.faces };
    s = st.model = { provider: 'meshy', status: 'submitted', request: { ...body, image_url: '<data uri>' }, submitted_at: new Date().toISOString() };
    save();
    for (let n = 0; ; n++) {
      try { s.task_id = (await mcall('POST', '/image-to-3d', body)).result; break; } catch (e) {
        if (e.status === 429 && n < 60) { await sleep(30000); continue; }
        s.status = 'rejected'; s.error = e.message; save(); throw e;
      }
    }
    save();
  }
  let t;
  for (;;) { t = await mcall('GET', `/image-to-3d/${s.task_id}`); if (['SUCCEEDED', 'FAILED', 'CANCELED'].includes(t.status)) break; await sleep(8000); }
  s.status = t.status === 'SUCCEEDED' ? 'success' : t.status; s.credits = t.status === 'SUCCEEDED' ? 20 : 0; s.completed_at = new Date().toISOString();
  save();
  if (t.status !== 'SUCCEEDED') throw new Error(`${a.id}/model: meshy ${t.status} ${scrub(JSON.stringify(t.task_error || ''))}`);
  await download(t.model_urls.glb, glb);
  console.log(`${a.id}: モデル（Meshy）`);
}

const spent = () => Object.values(state.assets).flatMap((a) => Object.values(a)).reduce((n, s) => n + (Number(s.credits) || 0), 0);

async function stage(a, name, request, route, maxCredits) {
  const st = (state.assets[a.id] ||= {});
  touched.add(a.id);
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
  if (!fs.existsSync(img) && a.provider === 'meshy') {
    // Meshy 担当の件は参照画像も Meshy（text-to-image nano-banana-2、Tripo の同時実行の枠を空ける）
    await meshyImage(a, img, o);
  } else if (!fs.existsSync(img)) {
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
  if (a.provider === 'meshy') return meshyModel(a, img, glb, o);
  const token = await upload(img);
  const s = await stage(a, 'model', { input: token, model: a.provider === 'tripo' ? 'v3.1-20260211' : 'P1-20260311', face_limit: a.faces || spec.faces, texture: false, pbr: false, export_uv: true },
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
    const pick = (x) => (x === 'all' ? () => true : x === 'second' ? (a) => !!a.provider : x.startsWith('provider=') ? (a) => a.provider === x.slice(9) : (a) => a.id === x);
    const list = spec.assets.filter((a) => ids.some((x) => pick(x)(a)));
    const par = Number(process.env.PAR || 2);
    let i = 0, failed = 0;
    await Promise.all(Array.from({ length: par }, async () => {
      while (i < list.length) { const a = list[i++]; try { await run(a, opt); } catch (e) { failed++; console.error(`${a.id}: ${scrub(e.message)}`); } }
    }));
    console.log(`使用 ${spent()} credits、失敗 ${failed}`);
    if (failed) process.exitCode = 1;
  } else throw new Error('usage: run <id...|all> [--until image] [--max-credits N] | status');
} catch (e) { console.error(scrub(e.message)); process.exitCode = 1; }
