#!/usr/bin/env node
// Retexture the existing Seaside arch with its original reference; never generate geometry again.
// node tools/stage/seaside_texture.mjs submit|status|download
// MESHY_API_KEY or ~/.config/meshy/api_key. State contains no credentials or signed URLs.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const statePath = path.join(dir, 'seaside_texture.json');
const generationPath = path.join(dir, 'seaside_generation.json');
const output = path.resolve(dir, '../../build/stage/seaside/limestone_arch');
const modelPath = path.join(output, 'model.glb');
const originalPath = path.join(output, 'geometry-original.glb');
const referencePath = path.join(dir, 'references/seaside/limestone_arch.png');
const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');
const scrub = value => String(value)
  .replace(/(?:msy_|tsk_)[A-Za-z0-9_-]+/g, '[redacted]')
  .replace(/(?:https?:\/\/|data:)[^\s"'<>]+/g, '[url omitted]');
const [command = 'status'] = process.argv.slice(2);
if (command === '--help') {
  console.log('Usage: node tools/stage/seaside_texture.mjs submit|status|download');
  process.exit(0);
}
if (!['submit', 'status', 'download'].includes(command)) throw new Error('Expected submit, status or download');

async function api(route, body) {
  const key = (process.env.MESHY_API_KEY || fs.readFileSync(path.join(os.homedir(), '.config/meshy/api_key'), 'utf8')).trim();
  const response = await fetch(`https://api.meshy.ai/openapi/v1${route}`, {
    method: body ? 'POST' : 'GET',
    headers: {Authorization: `Bearer ${key}`, ...(body ? {'Content-Type': 'application/json'} : {})},
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(180000),
  });
  const text = await response.text();
  let json;
  try { json = JSON.parse(text); } catch { json = {}; }
  if (!response.ok) {
    const error = new Error(`Meshy HTTP ${response.status}: ${scrub(json.message ?? 'request rejected').slice(0, 300)}`);
    error.httpStatus = response.status;
    throw error;
  }
  return json;
}

function glbDocument(data) {
  if (data.length < 20 || data.toString('ascii', 0, 4) !== 'glTF' || data.readUInt32LE(4) !== 2 ||
      data.readUInt32LE(8) !== data.length || data.readUInt32LE(16) !== 0x4e4f534a) {
    throw new Error('Downloaded model is not a valid GLB 2.0');
  }
  return JSON.parse(data.toString('utf8', 20, 20 + data.readUInt32LE(12)));
}

function hasTexture(data) {
  const doc = glbDocument(data);
  return (doc.images?.length ?? 0) > 0 && doc.materials?.some(m => m.pbrMetallicRoughness?.baseColorTexture);
}

async function downloadBytes(url) {
  if (!url || new URL(url).protocol !== 'https:') throw new Error('Missing HTTPS model URL');
  const response = await fetch(url, {signal: AbortSignal.timeout(180000)});
  if (!response.ok) throw new Error(`Model download HTTP ${response.status}`);
  return Buffer.from(await response.arrayBuffer());
}

async function main() {
  let state = fs.existsSync(statePath) ? JSON.parse(fs.readFileSync(statePath, 'utf8')) : {};
  const save = () => {
    const temporary = `${statePath}.${process.pid}.tmp`;
    fs.writeFileSync(temporary, JSON.stringify(state, null, 2) + '\n');
    fs.renameSync(temporary, statePath);
  };
  if (command === 'submit' && !state.task_id) {
    if (state.submitting) throw new Error('Previous paid submission is uncertain; inspect Meshy tasks before retrying');
    const generation = JSON.parse(fs.readFileSync(generationPath, 'utf8')).limestone_arch;
    const image = fs.readFileSync(referencePath);
    if (sha256(image) !== generation.input_sha256) throw new Error('Reference differs from the original arch generation input');
    const balance = await api('/balance');
    if (!Number.isFinite(balance.balance) || balance.balance < 10) {
      throw new Error(`Retexture requires 10 API credits; available ${balance.balance ?? 'unknown'}`);
    }
    let source, sourceID;
    if (generation.task_id) {
      const task = await api(`/image-to-3d/${encodeURIComponent(generation.task_id)}`);
      if (task.status !== 'SUCCEEDED') throw new Error(`Source geometry is ${task.status}; no texture task submitted`);
      sourceID = generation.task_id;
      source = fs.existsSync(originalPath) ? fs.readFileSync(originalPath)
        : fs.existsSync(modelPath) ? fs.readFileSync(modelPath) : await downloadBytes(task.model_urls?.glb);
    } else {
      source = fs.readFileSync(fs.existsSync(originalPath) ? originalPath : modelPath);
    }
    if (hasTexture(source)) throw new Error('Source already has a base-color texture; refusing another paid texture task');
    if (source.length > 100 * 1024 * 1024 && !sourceID) throw new Error('Local GLB exceeds the data URI limit');
    const hasUV = glbDocument(source).meshes?.every(m => m.primitives.every(p => p.attributes.TEXCOORD_0 !== undefined));
    const request = {ai_model: 'meshy-7', enable_pbr: true, enable_original_uv: Boolean(hasUV),
      texture_resolution: '2k', target_formats: ['glb']};
    fs.mkdirSync(output, {recursive: true});
    if (!fs.existsSync(originalPath)) fs.writeFileSync(originalPath, source, {flag: 'wx'});
    state = {provider: 'meshy', submitting: true, concept: 'references/seaside/limestone_arch.png',
      input_sha256: sha256(image), source_sha256: sha256(source), source_task_id: sourceID,
      request, balance_before: balance.balance, expected_credits: 10, submitted_at: new Date().toISOString()};
    save(); // Persist BEFORE the only paid POST; timeouts and malformed responses remain uncertain.
    try {
      const task = await api('/retexture', {...request,
        ...(sourceID ? {input_task_id: sourceID} : {model_url: `data:application/octet-stream;base64,${source.toString('base64')}`}),
        image_style_url: `data:image/png;base64,${image.toString('base64')}`});
      if (!task.result) throw new Error('Submission returned no task ID; inspect Meshy before retrying');
      state.task_id = task.result;
      state.submitting = false;
      save();
    } catch (error) {
      if ([400, 401, 402, 403, 404, 422, 429].includes(error.httpStatus)) {
        state.submitting = false;
        state.status = 'rejected';
        state.error = scrub(error.message);
        save();
      }
      throw error;
    }
  }
  if (!state.task_id) {
    console.log('limestone_arch texture', state.submitting ? 'submission uncertain' : 'not submitted');
    return;
  }
  const task = await api(`/retexture/${encodeURIComponent(state.task_id)}`);
  state.status = task.status;
  state.progress = task.progress;
  if (task.consumed_credits !== undefined) state.credits = task.consumed_credits;
  if (task.task_error?.message) state.error = scrub(task.task_error.message).slice(0, 300);
  save();
  console.log('limestone_arch texture', state.task_id, state.status, state.progress);
  if (command !== 'download' || task.status !== 'SUCCEEDED') return;
  const textured = await downloadBytes(task.model_urls?.glb);
  if (!hasTexture(textured)) throw new Error('Successful output has no base-color texture; original retained');
  const hash = sha256(textured);
  if (fs.existsSync(modelPath)) {
    const current = fs.readFileSync(modelPath);
    if (sha256(current) !== hash && sha256(current) !== state.source_sha256) {
      throw new Error('Current model differs from the submitted geometry; refusing to overwrite it');
    }
  }
  const original = fs.readFileSync(originalPath);
  if (sha256(original) !== state.source_sha256) throw new Error('Original geometry backup changed; refusing replacement');
  fs.writeFileSync(`${modelPath}.part`, textured);
  fs.renameSync(`${modelPath}.part`, modelPath);
  state.model_sha256 = hash;
  state.completed_at = new Date().toISOString();
  save();
  console.log('Saved textured limestone_arch/model.glb; geometry-original.glb retained');
}

// An exclusive local lock prevents two script processes from racing a paid submission.
const lockPath = `${statePath}.lock`;
let locked = false;
try {
  fs.writeFileSync(lockPath, String(process.pid), {flag: 'wx'});
  locked = true;
  await main();
} catch (error) {
  console.error(scrub(error.message));
  process.exitCode = 1;
} finally {
  if (locked) fs.unlinkSync(lockPath);
}
