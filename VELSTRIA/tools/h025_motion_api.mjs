#!/usr/bin/env node
// Resumable H025 acquisition. Credentials stay in env or ~/.config/<provider>/api_key.
// No paid request is automatically retried; an uncertain submission requires inspection.
// Run one command again to poll (honor retry_after_seconds); downloaded files stay in build/.
// inventory: free service/library checks; attack: one 10-credit Meshy prime candidate.
// attack --resume-after-upgrade: retry only a definitive uncharged HTTP402 after user confirms a plan change.
// rigcheck [GLB]: free upload/check; rig: one 25-credit repair donor; basics: one 30-credit batch.
// Paid operations obey build/h025-motion/api-state.json budgets, initially zero for Tripo.
// `manifest` writes only sanitized provenance to docs/MOTION_H025_API.json.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'build', 'h025-motion');
const journal = path.join(dir, 'api-state.json');
fs.mkdirSync(dir, { recursive: true });
fs.mkdirSync(path.dirname(journal), { recursive: true });
const lockPath=journal+'.lock';
if(fs.existsSync(lockPath)) {
  const owner=Number(fs.readFileSync(lockPath,'utf8'));
  try { process.kill(owner,0); throw new Error('Another H025 acquisition process owns the journal'); }
  catch(error) { if(error.code!=='ESRCH') throw error; fs.unlinkSync(lockPath); }
}
const lock=fs.openSync(lockPath,'wx');fs.writeSync(lock,String(process.pid));
process.on('exit',()=>{fs.closeSync(lock);fs.unlinkSync(lockPath);});
const state = fs.existsSync(journal) ? JSON.parse(fs.readFileSync(journal, 'utf8')) : {
  version: 1, hero: 'H025', budget: { meshy: 10, tripo: 0 }, tasks: {}, inventory: {},
};
const bases = { meshy: 'https://api.meshy.ai', tripo: 'https://openapi.tripo3d.ai/v3' };
const keys = {};
function save() {
  state.api_credit_total=Object.fromEntries(['meshy','tripo'].map(provider=>[provider,Object.values(state.tasks).filter(t=>t.provider===provider).reduce((n,t)=>n+(t.credits_consumed??t.consumed_credits??0),0)]));
  fs.writeFileSync(journal + '.tmp', JSON.stringify(state, null, 2) + '\n'); fs.renameSync(journal + '.tmp', journal);
}
function key(provider) { return keys[provider] ||= (process.env[`${provider.toUpperCase()}_API_KEY`] || fs.readFileSync(path.join(os.homedir(), '.config', provider, 'api_key'), 'utf8')).trim(); }
function scrub(value) {
  if (Array.isArray(value)) return value.map(scrub);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).filter(([k]) => !/url|token/i.test(k)).map(([k,v]) => [k, scrub(v)]));
  if (typeof value === 'string') return value.replace(/https?:\/\/\S+/g, '<url>').replace(/(?:msy_|tsk_)[A-Za-z0-9]+/g, '<credential>');
  return value;
}
function report(task) {
  console.log(JSON.stringify({ task_id:task.task_id,provider:task.provider,status:task.status,progress:task.progress,credits_consumed:task.credits_consumed??task.consumed_credits??null,output:task.output,file:task.file,retry_after_seconds:task.retry_after_seconds },null,2));
}
async function api(provider, route, method='GET', body) {
  const response = await fetch(bases[provider] + route, { method, headers: { Authorization: `Bearer ${key(provider)}`, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const data = await response.json();
  if (!response.ok || (provider === 'tripo' && data.code !== 0)) {
    const error = new Error(`${provider} ${method} ${route}: HTTP ${response.status} ${JSON.stringify(scrub(data))}`);
    error.status = response.status;
    throw error;
  }
  return { data: provider === 'tripo' ? data.data : data, retryAfter: Number(response.headers.get('retry-after') || 5) };
}
async function download(url, name) {
  const target = path.join(dir, name);
  if (fs.existsSync(target)) return { file: path.relative(root, target), bytes: fs.statSync(target).size, sha256: crypto.createHash('sha256').update(fs.readFileSync(target)).digest('hex') };
  const response = await fetch(url);
  if (!response.ok) throw new Error(`download ${name}: HTTP ${response.status}`);
  const buffer = Buffer.from(await response.arrayBuffer());
  fs.writeFileSync(target + '.part', buffer); fs.renameSync(target + '.part', target);
  return { file: path.relative(root, target), bytes: buffer.length, sha256: crypto.createHash('sha256').update(buffer).digest('hex') };
}
async function inventory() {
  for (const provider of ['meshy','tripo']) {
    const {data} = await api(provider, provider === 'meshy' ? '/openapi/v1/balance' : '/account/balance');
    state.inventory[`${provider}_balance`] = { ...scrub(data), checked_at: new Date().toISOString() }; save();
  }
  const {data: library} = await api('meshy', '/openapi/v1/animations/library');
  fs.writeFileSync(path.join(dir, 'meshy-library.json'), JSON.stringify(scrub(library), null, 2));
  const list = Array.isArray(library) ? library : library.result || library.data || [];
  state.inventory.meshy_library = { count: list.length, matches: list.filter(x => [0,1,11,222,225,227,228,231,234,657,691].includes(x.action_id)).map(scrub), checked_at: new Date().toISOString() }; save();
  try {
    const {data} = await api('meshy', '/openapi/v1/text-to-motion?page_num=1&page_size=100');
    state.inventory.existing_motion_tasks = scrub(data); save();
  } catch (error) { state.inventory.motion_list_error = scrub(error.message); save(); }
  const sources = [
    ['tripo','rig-H025','/tasks/991a8f19-5e87-46ee-98ec-006ec0171d0a'],
    ['meshy','archery-225','/openapi/v1/animations/01a1095a-018f-70a6-bf72-1d192f6b5131'],
    ['meshy','archery-227-222','/openapi/v1/animations/01a1095e-ce63-73c9-96b6-940d9c85aacb'],
    ['meshy','idle-run','/openapi/v1/animations/01a1095f-3ab3-7299-b060-83e0d351f51e'],
  ];
  for (const [provider,name,route] of sources) {
    try {
      const {data} = await api(provider, route);
      state.inventory[name] = { provider, ...scrub(data), files: [] }; save();
      const urls = provider === 'tripo' ? [['glb',data.output?.model_url]] : [['glb',data.result?.animation_glb_url],['fbx',data.result?.animation_fbx_url]];
      if (['success','SUCCEEDED'].includes(data.status)) for (const [ext,url] of urls) if (url) {
        try { state.inventory[name].files.push(await download(url, `${name}.${ext}`)); save(); }
        catch(error) { state.inventory[name].download_error = scrub(error.message); save(); }
      }
      console.log(name, data.status, state.inventory[name].files.map(x=>x.file).join(' '));
    } catch(error) { state.inventory[name] = { provider, error: scrub(error.message) }; save(); console.log(name, 'unavailable'); }
  }
  console.log(JSON.stringify({ balances: [state.inventory.meshy_balance, state.inventory.tripo_balance], existing_motion_tasks: state.inventory.existing_motion_tasks, matches: state.inventory.meshy_library.matches },null,2));
}
async function attack() {
  const name = 'moon_archer_attack_prime';
  let task = state.tasks[name];
  if(task?.status==='REJECTED' && process.argv.includes('--resume-after-upgrade')) {
    if(task.http_status!==402 || task.task_id || task.consumed_credits!==0) throw new Error('Upgrade retry requires a definitive HTTP402 with no task ID and zero charge');
    state.rejected_attempts??=[];
    state.rejected_attempts.push({...task,name,retry_authorization:'User confirmed subscription upgraded',archived_at:new Date().toISOString()});
    delete state.tasks[name];task=undefined;save();
  }
  if(task?.status==='REJECTED') throw new Error(`Prior prime candidate was rejected (HTTP ${task.http_status}): ${task.error}. No automatic resubmission.`);
  if (!task) {
    const spent = Object.values(state.tasks).filter(t=>t.provider==='meshy').reduce((n,t)=>n+(t.consumed_credits ?? t.estimate ?? 0),0);
    if (spent + 10 > state.budget.meshy) throw new Error('Meshy project credit cap reached');
    const {data: balance} = await api('meshy','/openapi/v1/balance');
    if (Number(balance.balance) < 10) throw new Error('Insufficient Meshy credits');
    const request = { mode:'prime', duration:3, prompt:'Graceful expert female elf archer, left foot forward, feet planted. Left hand holds bow steady. Raise bow; right hand nocks then draws string to right cheek, right elbow back. Brief precise aim, release fingers, right hand follows back, smoothly return to ready stance. Subtle breath, coordinated shoulders, wrists and torso. No steps or root travel. One complete shot.' };
    if(request.prompt.length > 400) throw new Error('Prompt exceeds 400 characters');
    task = state.tasks[name] = { provider:'meshy', status:'submitting', request, estimate:10, submitted_at:new Date().toISOString() }; save();
    try {
      const {data} = await api('meshy','/openapi/v1/text-to-motion','POST',request);
      task.task_id = data.result; task.status = 'PENDING'; save();
    } catch(error) { reject(task,error); throw error; }
  }
  if (!task.task_id) throw new Error('Prior submission is uncertain: inspect account task listing; do not resubmit');
  const {data,retryAfter} = await api('meshy',`/openapi/v1/text-to-motion/${task.task_id}`);
  Object.assign(task,scrub(data),{ checked_at:new Date().toISOString(), retry_after_seconds:retryAfter }); save();
  if(data.status==='SUCCEEDED' && data.result?.motion_url) {task.file = await download(data.result.motion_url,`${name}.fbx`);save();}
  report(task);
}
function reject(task,error) {
  const definite = [400,401,402,403,404,413,415,422,429].includes(error.status);
  Object.assign(task,{status:definite?'REJECTED':'unknown',http_status:error.status,error:scrub(error.message),checked_at:new Date().toISOString()});
  if(definite) task.consumed_credits=0;
  save();
}
async function tripoTask(name,route,request,estimate=0) {
  let task=state.tasks[name];
  if(!task) {
    const spent=Object.values(state.tasks).filter(t=>t.provider==='tripo').reduce((n,t)=>n+(['success','failed','cancelled','REJECTED'].includes(t.status)?(t.credits_consumed??t.consumed_credits??t.estimate??0):(t.estimate??0)),0);
    if(spent+estimate>state.budget.tripo) throw new Error('Tripo project credit cap reached');
    const {data:balance}=await api('tripo','/account/balance');
    if(balance.balance<estimate) throw new Error('Insufficient Tripo credits');
    task=state.tasks[name]={provider:'tripo',status:'submitting',request,estimate,submitted_at:new Date().toISOString()};save();
    try { const {data}=await api('tripo',route,'POST',request); task.task_id=data.task_id;task.status='queued';save(); }
    catch(error){reject(task,error);throw error;}
  }
  if(!task.task_id) throw new Error(`Prior ${name} submission has no task ID; inspect journal before any resubmission`);
  const {data,retryAfter}=await api('tripo',`/tasks/${task.task_id}`);
  Object.assign(task,scrub(data),{checked_at:new Date().toISOString(),retry_after_seconds:retryAfter});save();
  if(data.status==='success'&&data.output?.model_url){task.file=await download(data.output.model_url,`${name}.${request.out_format||'glb'}`);save();}
  report(task);
  return task;
}
async function rigcheck() {
  const source=process.argv[3]?path.resolve(process.argv[3]):path.join(dir,'H025_original_import.glb'),uploadFile=path.join(dir,'tripo-upload.json');
  const bytes=fs.readFileSync(source),sha256=crypto.createHash('sha256').update(bytes).digest('hex');
  let upload=fs.existsSync(uploadFile)?JSON.parse(fs.readFileSync(uploadFile,'utf8')):null;
  if(!upload||upload.sha256!==sha256){
    const form=new FormData();form.set('file',new Blob([bytes],{type:'model/gltf-binary'}),'H025_original_import.glb');
    const response=await fetch(bases.tripo+'/files',{method:'POST',headers:{Authorization:`Bearer ${key('tripo')}`},body:form});
    const data=await response.json();if(!response.ok||data.code!==0)throw new Error(`Tripo upload HTTP ${response.status}`);
    upload={sha256,file_token:data.data.file_token};fs.writeFileSync(uploadFile,JSON.stringify(upload,null,2));
  }
  state.inventory.tripo_source={file:path.relative(root,source),sha256,bytes:bytes.length,reason:'Existing H025 skeleton has shoulders/toes but no finger joints. Inspect repair donor only; preserve original production model.'};save();
  const original=state.tasks.H025_rigcheck;
  const taskName=original?.request.input===upload.file_token?'H025_rigcheck':`H025_rigcheck_${sha256.slice(0,8)}`;
  state.selectedRigcheck=taskName;save();
  return tripoTask(taskName,'/animations/rig-check',{input:upload.file_token},0);
}
async function rig() {
  const check=state.tasks[state.selectedRigcheck||'H025_rigcheck'];
  if(check?.status!=='success'||check.output?.riggable!==true)throw new Error('Successful compatible rig-check required');
  return tripoTask('H025_rig_v3','/animations/rig',{input:check.request.input,model:'v3.0-20260909',rig_type:'biped',spec:'mixamo',out_format:'glb'},25);
}
async function basics() {
  const rig=state.tasks.H025_rig_v3;
  if(rig?.status!=='success')throw new Error('Successful v3 rig required');
  return tripoTask('H025_idle_walk_run','/animations/retarget',{input:rig.task_id,animations:['preset:idle','preset:walk','preset:run'],animate_in_place:true,out_format:'glb',export_with_geometry:true},30);
}
async function manifest() {
  const tasks=Object.entries(state.tasks).map(([name,t])=>({name,provider:t.provider,task_id:t.task_id??null,status:t.status,http_status:t.http_status??null,
    credits_consumed:t.credits_consumed??t.consumed_credits??0,submitted_at:t.submitted_at,completed_at:t.completed_at??t.rejected_at??null,
    request:Object.fromEntries(Object.entries(t.request??{}).filter(([k])=>k!=='input')),output:t.output,
    file:t.file?{...t.file,file:t.file.file.replaceAll('\\','/')}:null,error:t.error??null}));
  const reportFile=path.join(dir,'tripo-source-report.json');
  const report=fs.existsSync(reportFile)?JSON.parse(fs.readFileSync(reportFile,'utf8')):null;
  const primeReportFile=path.join(dir,'meshy-prime-report.json');
  const primeReport=fs.existsSync(primeReportFile)?JSON.parse(fs.readFileSync(primeReportFile,'utf8')):null;
  const result={version:1,hero:'H025',recorded_at:new Date().toISOString(),credit_cap:{meshy:state.budget.meshy,tripo:state.budget.tripo},
    credits_consumed:state.api_credit_total,meshy_library:state.inventory.meshy_library,tasks,rejected_attempts:state.rejected_attempts??[],
    retained_existing_model:true,rig_repair_reason:'Original H025 rig has 23 joints and no finger chains; v3 donor contains65joints including fingers. Original geometry and textures were reused, not regenerated.',
    source:{...state.inventory.tripo_source,file:state.inventory.tripo_source?.file?.replaceAll('\\','/')},
    extraction:report?{environment:'Windows / Blender4.5.10 LTS /30fps; offline source conversion, not iOS runtime validation',clips:report.clips.map(c=>({name:c.name,frames:c.frames,sourceFps:c.sourceFps,start:c.start,end:c.end,loopSeamDegrees:c.loopSeamDegrees,verify:c.verify})),warnings:report.warnings}:null,
    prime_extraction:primeReport?{source:primeReport.source,sourceSkeleton:primeReport.sourceSkeleton,bones:primeReport.bones,frames:primeReport.frames,sourceFps:primeReport.sourceFps,actionFrameRange:primeReport.actionFrameRange,verify:primeReport.verify,rootRebase:primeReport.rootRebase,releaseEstimate:primeReport.releaseEstimate,
      source_clips:'tools/motion/h025-prime-source-clips.json',source_details:'tools/motion/h025-prime-source-details.json',
      adoption:'Prime body and arm-roll variation are fitted with local IK. Authored bow grip, string contact, finger release, planted feet and gameplay release synchronization remain explicit constraints; raw full-body motion is not played unchanged.'}:null,
    references:state.references,meshy_plan_url:'https://www.meshy.ai/settings/subscription'};
  const output=path.join(root,'docs','MOTION_H025_API.json');fs.writeFileSync(output,JSON.stringify(result,null,2)+'\n');console.log(path.relative(root,output));
}
try { const commands={inventory,attack,rigcheck,rig,basics,manifest};const command=commands[process.argv[2]];if(!command)throw new Error('usage: node tools/h025_motion_api.mjs inventory|attack|rigcheck|rig|basics|manifest');await command(); }
catch(error) { console.error(scrub(error.message)); process.exitCode=1; }
