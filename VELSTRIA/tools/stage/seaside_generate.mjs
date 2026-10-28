#!/usr/bin/env node
// Dedicated Seaside image-to-model jobs. Never repeat uncertain paid submissions.
// Credentials: MESHY_API_KEY/TRIPO_API_KEY or ~/.config/{meshy,tripo}/api_key.
// node tools/stage/seaside_generate.mjs submit|status|download [limestone_arch|palm_cluster]
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const statePath = path.join(dir, 'seaside_generation.json');
const state = fs.existsSync(statePath) ? JSON.parse(fs.readFileSync(statePath, 'utf8')) : {};
const save = () => fs.writeFileSync(statePath, JSON.stringify(state, null, 2) + '\n');
const assets = {limestone_arch:'meshy', palm_cluster:'tripo'};
const [command = 'status', ...requested] = process.argv.slice(2);
if (!['submit','status','download'].includes(command)) throw new Error('Expected submit, status or download');
const scrub = value => String(value).replace(/(?:msy_|tsk_)[A-Za-z0-9_-]+/g, '[redacted]');
async function call(provider, route, body) {
  const key = (process.env[`${provider.toUpperCase()}_API_KEY`] || fs.readFileSync(path.join(os.homedir(), '.config', provider, 'api_key'), 'utf8')).trim();
  const form = body instanceof FormData;
  const response = await fetch((provider === 'meshy' ? 'https://api.meshy.ai' : 'https://openapi.tripo3d.ai/v3') + route, {
    method: body ? 'POST' : 'GET',
    headers: {Authorization:`Bearer ${key}`, ...(!form && body ? {'Content-Type':'application/json'} : {})},
    body: form ? body : body ? JSON.stringify(body) : undefined,
    signal:AbortSignal.timeout(180000),
  });
  const json = await response.json();
  if (!response.ok || (provider === 'tripo' && json.code !== 0)) {
    const error = new Error(`${provider} HTTP ${response.status}: ${scrub(JSON.stringify(json)).slice(0,400)}`);
    error.httpStatus = response.status;
    throw error;
  }
  return provider === 'tripo' ? json.data : json;
}
async function download(url, destination) {
  if (fs.existsSync(destination)) return;
  const response = await fetch(url, {signal:AbortSignal.timeout(180000)});
  if (!response.ok) throw new Error(`Download HTTP ${response.status}`);
  fs.writeFileSync(destination + '.part', Buffer.from(await response.arrayBuffer()));
  fs.renameSync(destination + '.part', destination);
}
for (const id of requested.length ? requested : Object.keys(assets)) {
  const provider = assets[id];
  if (!provider) throw new Error(`Unknown asset ${id}`);
  let entry = state[id];
  if (command === 'submit' && !entry?.task_id) {
    if (entry?.submitting) throw new Error(`${id}: previous submission uncertain; inspect provider before retrying`);
    const image = fs.readFileSync(path.join(dir, 'references/seaside', `${id}.png`));
    const request = provider === 'meshy' ? {
      ai_model:'meshy-t2.5', model_type:'smart-topology', should_texture:false, enable_pbr:false,
      topology:'triangle', target_polycount:2400, target_formats:['glb'],
    } : {
      model:'P1-20260311', face_limit:12000, texture:true, pbr:true, texture_quality:'detailed',
      texture_version:'v3.5-20260815', delight:true, texture_alignment:'original_image', orientation:'align_image',
    };
    const balance = await call(provider, provider === 'meshy' ? '/openapi/v1/balance' : '/account/balance');
    let input;
    if (provider === 'tripo') {
      const form = new FormData();
      form.append('file', new Blob([image], {type:'image/png'}), `${id}.png`);
      const upload = await call(provider, '/files', form);
      if (!upload.file_token) throw new Error('Tripo file token missing');
      input = upload.file_token;
    }
    entry = state[id] = {provider, submitting:true, concept:`references/seaside/${id}.png`,
      input_sha256:crypto.createHash('sha256').update(image).digest('hex'), request,
      balance_before:balance.balance, submitted_at:new Date().toISOString()};
    save();
    let result;
    try {
      result = await call(provider, provider === 'meshy' ? '/openapi/v1/image-to-3d' : '/generation/image-to-model',
        {...request, ...(provider === 'meshy' ? {image_url:`data:image/png;base64,${image.toString('base64')}`} : {input})});
    } catch (error) {
      // Definite rejection before task creation can be retried after account repair.
      // Network errors and 5xx remain uncertain and must never auto-submit again.
      if ([400,401,402,403,422,429].includes(error.httpStatus)) {
        entry.submitting = false;
        entry.status = 'rejected';
        entry.error = scrub(error.message);
        save();
      }
      throw error;
    }
    entry.task_id = provider === 'meshy' ? result.result : result.task_id;
    if (!entry.task_id) throw new Error('Submission returned no task ID');
    entry.submitting = false;
    save();
  }
  if (!entry?.task_id) { console.log(id, 'not submitted'); continue; }
  const task = await call(provider, provider === 'meshy' ? `/openapi/v1/image-to-3d/${entry.task_id}` : `/tasks/${entry.task_id}`);
  entry.status = task.status; entry.progress = task.progress;
  const credits = task.consumed_credits ?? task.credits_consumed;
  if (credits !== undefined) entry.credits = credits;
  save();
  console.log(id, provider, entry.task_id, entry.status, entry.progress);
  if (command === 'download' && ['success','SUCCEEDED'].includes(task.status)) {
    const output = path.resolve(dir, '../../build/stage/seaside', id);
    fs.mkdirSync(output, {recursive:true});
    const urls = provider === 'meshy' ? [task.model_urls?.glb, task.thumbnail_url] : [
      ['pbr_model_url','model_url','pbr_model','model','base_model_url','base_model'].map(k=>task.output?.[k]).find(Boolean),
      task.output?.rendered_image_url ?? task.output?.rendered_image,
    ];
    for (const [i,value] of urls.entries()) {
      const url = typeof value === 'string' ? value : value?.url;
      if (url) await download(url, path.join(output, i === 0 ? 'model.glb' : 'preview.png'));
    }
    if (!fs.existsSync(path.join(output, 'model.glb'))) throw new Error(`${id}: model GLB missing`);
    // The later texture pass may replace model.glb. Keep the geometry job's original provenance.
    entry.model_sha256 ??= crypto.createHash('sha256').update(fs.readFileSync(path.join(output, 'model.glb'))).digest('hex');
    entry.completed_at ??= new Date().toISOString();
    save();
    console.log('saved', id, 'model.glb');
  }
}
