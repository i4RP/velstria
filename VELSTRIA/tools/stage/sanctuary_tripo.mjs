#!/usr/bin/env node
// Tripo v2 only. Resume recorded task; never automatically repeat a paid submission.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const dir = path.dirname(fileURLToPath(import.meta.url));
const statePath = path.join(dir, 'sanctuary_tripo_state.json');
const output = path.resolve(dir, '../../build/stage/sanctuary');
const key = (process.env.TRIPO_API_KEY || fs.readFileSync(path.join(os.homedir(), '.config/tripo/api_key'), 'utf8')).trim();
async function call(route, body) {
  const form = body instanceof FormData;
  const r = await fetch(`https://api.tripo3d.ai/v2/openapi${route}`, {
    method: body ? 'POST' : 'GET',
    headers: { Authorization: `Bearer ${key}`, ...(!form && body ? {'Content-Type':'application/json'} : {}) },
    body: form ? body : body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(180000),
  });
  const j = await r.json();
  if (!r.ok || j.code !== 0) throw new Error(`Tripo HTTP ${r.status}, code ${j.code}`);
  return j.data;
}
let state = fs.existsSync(statePath) ? JSON.parse(fs.readFileSync(statePath, 'utf8')) : {};
const save = () => fs.writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
if (!state.task_id) {
  if (state.submitting) throw new Error('Prior submission uncertain; inspect Tripo before creating another paid task.');
  const form = new FormData();
  form.append('file', new Blob([fs.readFileSync(path.join(dir, 'references/sanctuary_concept.png'))], {type:'image/png'}), 'sanctuary.png');
  const upload = await call('/upload', form);
  const request = { type:'image_to_model', model_version:'v2.5-20250123',
    texture:true, pbr:true, texture_quality:'detailed', texture_alignment:'original_image',
    orientation:'align_image', face_limit:30000, model_seed:171026, texture_seed:171026 };
  state = { submitting:true, request, concept:'references/sanctuary_concept.png' }; save();
  const task = await call('/task', {...request, file:{type:'png', file_token:upload.image_token ?? upload.file_token}});
  state.task_id = task.task_id; state.submitting = false; save();
}
console.log('task', state.task_id);
fs.mkdirSync(output, {recursive:true});
for (;;) {
  const task = await call(`/task/${state.task_id}`);
  state.status = task.status; state.progress = task.progress; save();
  console.log(task.status, task.progress);
  if (task.status === 'success') {
    for (const [name, keys] of [['model.glb',['pbr_model','model','base_model']], ['preview.webp',['rendered_image']]]) {
      const v = keys.map(k => task.output?.[k]).find(Boolean);
      const url = typeof v === 'string' ? v : v?.url;
      if (!url) continue;
      const r = await fetch(url); if (!r.ok) throw new Error(`Download HTTP ${r.status}`);
      fs.writeFileSync(path.join(output,name), Buffer.from(await r.arrayBuffer()));
      console.log('saved',name);
    }
    break;
  }
  if (['failed','cancelled','unknown'].includes(task.status)) throw new Error(`Generation ${task.status}`);
  await new Promise(resolve => setTimeout(resolve, 8000));
}
