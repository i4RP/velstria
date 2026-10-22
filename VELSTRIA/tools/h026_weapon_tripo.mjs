#!/usr/bin/env node
// H026 ballLightning prop: the Meshy concept image (build/meshy/props/ballLightning/concept.png) -> Tripo image-to-model.
// Used when Meshy credits are short. Resumable: build/tripo/props/ballLightning/h026-task.json keeps the task id;
// a submitted task is never resubmitted. Key from TRIPO_API_KEY (or ~/.config/tripo/api_key), never written.
// Output: build/tripo/props/ballLightning/model.glb -> node tools/tripo.mjs import props ballLightning
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const concept = path.join(root, 'build/meshy/props/ballLightning/concept.png');
const dir = path.join(root, 'build/tripo/props/ballLightning');
const journal = path.join(dir, 'h026-task.json');
fs.mkdirSync(dir, { recursive: true });
const key = (process.env.TRIPO_API_KEY || fs.readFileSync(path.join(os.homedir(), '.config/tripo/api_key'), 'utf8')).trim();
const API = 'https://openapi.tripo3d.ai/v3';
const state = fs.existsSync(journal) ? JSON.parse(fs.readFileSync(journal, 'utf8')) : {};
const save = () => fs.writeFileSync(journal, JSON.stringify(state, null, 2) + '\n');
async function api(method, route, body, form) {
  const r = await fetch(API + route, { method, headers: { Authorization: `Bearer ${key}`, ...(form ? {} : { 'Content-Type': 'application/json' }) },
    body: form ?? (body ? JSON.stringify(body) : undefined) });
  const d = await r.json();
  if (!r.ok || d.code !== 0) throw Object.assign(new Error(`tripo ${method} ${route}: HTTP ${r.status} ${JSON.stringify(d).replace(/https?:\/\/\S+/g, '<url>')}`), { status: r.status });
  return d.data;
}
if (!state.task_id) {
  if (state.status === 'submitting') throw new Error('previous submission is uncertain; inspect the Tripo task list before resubmitting');
  const buf = fs.readFileSync(concept);
  const form = new FormData();
  form.append('file', new Blob([buf], { type: 'image/png' }), 'concept.png');
  const { file_token } = await api('POST', '/files', undefined, form);
  Object.assign(state, { status: 'submitting', concept_sha256: crypto.createHash('sha256').update(buf).digest('hex'), submitted_at: new Date().toISOString() }); save();
  const request = { input: file_token, model: 'P1-20260311', face_limit: 2000, texture: true, pbr: true, texture_quality: 'detailed',
    texture_version: 'v3.5-20260815', delight: true };
  try { const d = await api('POST', '/generation/image-to-model', request); state.task_id = d.task_id; state.status = 'queued'; }
  catch (e) { state.status = e.status ? 'rejected' : 'unknown'; state.error = e.message; save(); throw e; }
  state.request = { ...request, input: '<file_token>' }; save();
}
for (;;) {
  const d = await api('GET', `/tasks/${state.task_id}`);
  state.status = d.status; state.progress = d.progress; state.credits = d.credits_consumed ?? d.consumed_credits ?? state.credits; save();
  console.log(state.task_id, d.status, d.progress ?? '');
  if (d.status === 'success') {
    const url = d.output?.pbr_model || d.output?.model_url || d.output?.model || d.output?.base_model;
    const r = await fetch(typeof url === 'string' ? url : url.url);
    const buf = Buffer.from(await r.arrayBuffer());
    fs.writeFileSync(path.join(dir, 'model.glb'), buf);
    state.model_sha256 = crypto.createHash('sha256').update(buf).digest('hex'); save();
    console.log('saved', path.relative(root, path.join(dir, 'model.glb')), buf.length, 'bytes; credits', state.credits);
    break;
  }
  if (['failed', 'cancelled', 'banned', 'expired'].includes(d.status)) throw new Error(`task ${d.status}`);
  await new Promise(r => setTimeout(r, 8000));
}
