#!/usr/bin/env node
// Image concepts -> Tripo v2.5. Task IDs are persisted before polling; never repeat
// an uncertain paid submission. Credentials and signed output URLs are not saved.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const statePath = path.join(dir, 'reference_tripo_state.json');
const output = path.resolve(dir, '../../build/stage/field');
const key = (process.env.TRIPO_API_KEY || fs.readFileSync(path.join(os.homedir(), '.config/tripo/api_key'), 'utf8')).trim();
const state = fs.existsSync(statePath) ? JSON.parse(fs.readFileSync(statePath, 'utf8')) : {};
const save = () => fs.writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
const command = process.argv[2] || 'status';
const ids = process.argv.slice(3).length ? process.argv.slice(3) : ['root_wall', 'camp_crescent', 'camp_gate', 'river_wall'];
async function call(route, body) {
  const form = body instanceof FormData;
  const response = await fetch(`https://api.tripo3d.ai/v2/openapi${route}`, {
    method: body ? 'POST' : 'GET',
    headers: {Authorization: `Bearer ${key}`, ...(!form && body ? {'Content-Type':'application/json'} : {})},
    body: form ? body : body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(180000),
  });
  const data = await response.json();
  if (!response.ok || data.code !== 0) throw new Error(`Tripo HTTP ${response.status}, code ${data.code}`);
  return data.data;
}
for (const id of ids) {
  let s = state[id];
  if (!s?.task_id && command === 'submit') {
    if (s?.submitting) throw new Error(`${id}: prior submission uncertain; inspect account before retrying`);
    const file = path.join(dir, 'references/field', `${id}.png`);
    const form = new FormData();
    form.append('file', new Blob([fs.readFileSync(file)], {type:'image/png'}), `${id}.png`);
    const upload = await call('/upload', form);
    s = state[id] = {submitting:true, concept:`references/field/${id}.png`, request:{
      type:'image_to_model', model_version:'v2.5-20250123', texture:true, pbr:true,
      texture_quality:'detailed', texture_alignment:'original_image', orientation:'align_image',
      face_limit:24000, model_seed:191026, texture_seed:191026,
    }};
    save();
    const task = await call('/task', {...s.request, file:{type:'png', file_token:upload.image_token ?? upload.file_token}});
    s.task_id = task.task_id;
    s.submitting = false;
    save();
  }
  if (!s?.task_id) { console.log(id, 'not submitted'); continue; }
  const task = await call(`/task/${s.task_id}`);
  s.status = task.status; s.progress = task.progress; save();
  console.log(id, s.task_id, s.status, s.progress);
  if (command === 'download' && task.status === 'success') {
    const folder = path.join(output, id); fs.mkdirSync(folder, {recursive:true});
    for (const [name, keys] of [['model.glb',['pbr_model','model','base_model']], ['preview.webp',['rendered_image']]]) {
      const destination = path.join(folder, name);
      if (fs.existsSync(destination)) continue;
      const v = keys.map(k => task.output?.[k]).find(Boolean);
      const url = typeof v === 'string' ? v : v?.url;
      if (!url) continue;
      const response = await fetch(url);
      if (!response.ok) throw new Error(`Download HTTP ${response.status}`);
      fs.writeFileSync(destination, Buffer.from(await response.arrayBuffer()));
      console.log('saved', id, name);
    }
  }
}
