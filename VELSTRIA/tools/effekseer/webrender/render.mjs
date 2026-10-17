#!/usr/bin/env node
// .efk を実際の Effekseer ランタイム（EffekseerForWebGL 1.80.7。アプリの C++ ランタイムと同じ 1.8 系）で描いてコマを撮る（Mac が無くても確かめられる）。
// 無頭の Chrome / Edge（WebGL は SwiftShader）でページ（page.html / page.js）を開き、DevTools の通信で 1 フレームずつ進めて撮る。
//
// 使い方（VELSTRIA/ で）:
//   node tools/effekseer/webrender/render.mjs <効果> [<効果> …] [--frames 60] [--every 4] [--out DIR] [--camera mlbb]
//        [--size 1108x512] [--crop x,y,w,h] [--bloom 1.5] [--cols 6] [--sheet-scale 0.5] [--rings 2.57,8.23] [--no-bodies]
//        [--ground '#5b6250'] [--seed 1] [--fx-dir DIR（既定 Effects/Effekseer）]
//   効果: <Effects/Effekseer からの名前（.efk なし）>[@x,y,z][:yaw=度][:scale=倍][:delay=フレーム][:speed=倍][:top]
//         例 H034_s2_impact  Kit/H034_s2_slam@0,0,0:delay=16  Kit/H034_hit_flash@0,1,-4:top
//         位置はヒーロー（原点・北 = -Z を向く）から。練習場の人形は (0, 0, -4)。top = 3D の上の層（深度を消してから描く）
//   出力: DIR/f<フレーム>.png（撮ったコマ）と DIR/sheet.png（一覧。左上にフレームと秒）。既定の DIR は %TEMP%/efk-render/<最初の効果>
//   ランタイム: 環境変数 EFK_WEBGL_DIR（無ければ一時フォルダへ GitHub の公開版 zip を 1 回だけ落として展開。リポジトリには入れない）
//   ブラウザ: 環境変数 CHROME（無ければ Chrome → Edge の既定の場所を探す）
import { spawn, execFileSync } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..', '..');
let FX_DIR = path.join(ROOT, 'Effects', 'Effekseer');
const RUNTIME_VERSION = '1.80.7';
const RUNTIME_URL = `https://github.com/effekseer/Effekseer/releases/download/1807/EffekseerForWebGL${RUNTIME_VERSION}.zip`;

// ---- 引数 ---------------------------------------------------------------------------------

function parseArgs(argv) {
  const o = {
    fx: [], frames: 60, every: 4, out: null, camera: 'mlbb', width: 1108, height: 512, crop: null, bloom: 0, cols: 6,
    sheetScale: 0.5, rings: [], bodies: true, grid: true, ground: '#5b6250', sky: '#1d2733', seed: 1, focus: [0, 0, 0],
  };
  for (let i = 0; i < argv.length; i++) if (argv[i] === '--fx-dir') FX_DIR = path.resolve(argv[i + 1]);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    if (a === '--frames') o.frames = +next();
    else if (a === '--every') o.every = Math.max(1, +next());
    else if (a === '--out') o.out = next();
    else if (a === '--camera') {
      const v = next();
      if (v.includes(',')) {
        const [pitch, fov, distance, lead] = v.split(',').map(Number);
        o.camera = { pitch, fov, distance, lead: lead || 0 };
      } else o.camera = v;
    } else if (a === '--size') [o.width, o.height] = next().split('x').map(Number);
    else if (a === '--crop') o.crop = next().split(',').map(Number);
    else if (a === '--bloom') o.bloom = +next();
    else if (a === '--cols') o.cols = +next();
    else if (a === '--sheet-scale') o.sheetScale = +next();
    else if (a === '--rings') o.rings = next().split(',').map(Number);
    else if (a === '--no-bodies') o.bodies = false;
    else if (a === '--no-grid') o.grid = false;
    else if (a === '--ground') o.ground = next();
    else if (a === '--sky') o.sky = next();
    else if (a === '--seed') o.seed = +next();
    else if (a === '--focus') o.focus = next().split(',').map(Number);
    else if (a === '--fx-dir') FX_DIR = path.resolve(next());
    else if (a.startsWith('--')) throw new Error(`知らない指定: ${a}`);
    else o.fx.push(parseFx(a));
  }
  if (!o.fx.length) throw new Error('効果を 1 つ以上指定する（例: H034_s2_impact）');
  return o;
}

function parseFx(s) {
  const parts = s.split(':');
  let [name, at] = parts[0].split('@');
  const fx = { name, pos: [0, 0, 0], yaw: 0, scale: 1, delay: 0, speed: 1, top: false };
  if (at) fx.pos = at.split(',').map(Number);
  for (const p of parts.slice(1)) {
    const [k, v] = p.split('=');
    if (k === 'top') fx.top = true;
    else if (k in fx) fx[k] = +v;
    else throw new Error(`効果の指定が分からない: ${p}`);
  }
  if (!fs.existsSync(path.join(FX_DIR, name + '.efk'))) throw new Error(`${name}.efk が ${FX_DIR} に無い`);
  return fx;
}

// ---- ランタイム・ブラウザ -----------------------------------------------------------------------

async function ensureRuntime() {
  const dir = process.env.EFK_WEBGL_DIR || path.join(os.tmpdir(), `efk-webgl-${RUNTIME_VERSION}`);
  if (fs.existsSync(path.join(dir, 'effekseer.wasm'))) return dir;
  fs.mkdirSync(dir, { recursive: true });
  const zip = path.join(dir, 'runtime.zip');
  process.stderr.write(`EffekseerForWebGL ${RUNTIME_VERSION} を取得: ${RUNTIME_URL}\n`);
  const res = await fetch(RUNTIME_URL);
  if (!res.ok) throw new Error(`取得に失敗: ${res.status}`);
  fs.writeFileSync(zip, Buffer.from(await res.arrayBuffer()));
  execFileSync('tar', ['-xf', zip, '-C', dir]);   // Windows 10 以降・macOS の tar は zip を展開できる
  fs.rmSync(zip);
  if (!fs.existsSync(path.join(dir, 'effekseer.wasm'))) throw new Error(`${dir} に effekseer.wasm が無い（zip の構造が変わった？）`);
  return dir;
}

function findBrowser() {
  const env = process.env.CHROME;
  if (env && fs.existsSync(env)) return env;
  const pf = process.env['PROGRAMFILES'] || 'C:\\Program Files', pf86 = process.env['PROGRAMFILES(X86)'] || 'C:\\Program Files (x86)';
  const local = process.env.LOCALAPPDATA || '';
  const list = [
    path.join(pf, 'Google/Chrome/Application/chrome.exe'), path.join(pf86, 'Google/Chrome/Application/chrome.exe'),
    path.join(local, 'Google/Chrome/Application/chrome.exe'), path.join(pf86, 'Microsoft/Edge/Application/msedge.exe'),
    path.join(pf, 'Microsoft/Edge/Application/msedge.exe'),
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '/usr/bin/google-chrome', '/usr/bin/chromium',
  ];
  const hit = list.find((p) => fs.existsSync(p));
  if (!hit) throw new Error('Chrome / Edge が見つからない（環境変数 CHROME で指定する）');
  return hit;
}

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png',
  '.efk': 'application/octet-stream', '.efkmodel': 'application/octet-stream', '.dds': 'application/octet-stream' };

function serve(runtimeDir) {
  const roots = { rt: runtimeDir, fx: FX_DIR, page: HERE };
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    const [, root, ...rest] = url.split('/');
    const base = roots[root];
    const file = base && path.resolve(base, rest.join('/'));
    if (!file || !file.startsWith(path.resolve(base)) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      res.writeHead(404);
      res.end();
      return;
    }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

async function launch(browser, url) {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'efk-render-profile-'));
  const proc = spawn(browser, [
    '--headless=new', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
    '--remote-debugging-port=0', `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check',
    '--disable-extensions', '--hide-scrollbars', '--mute-audio', `--window-size=1400,900`, url,
  ], { stdio: 'ignore' });
  const portFile = path.join(profile, 'DevToolsActivePort');
  for (let i = 0; i < 200 && !fs.existsSync(portFile); i++) await sleep(50);
  if (!fs.existsSync(portFile)) throw new Error('ブラウザの DevTools が起動しない');
  const port = fs.readFileSync(portFile, 'utf8').split('\n')[0].trim();
  let target;
  for (let i = 0; i < 100 && !target; i++) {
    const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json().catch(() => []);
    target = list.find((t) => t.type === 'page' && t.url.startsWith(url));
    if (!target) await sleep(100);
  }
  if (!target) throw new Error('ページが開かない');
  const close = async () => {
    const exited = new Promise((r) => proc.once('exit', r));
    proc.kill();
    await Promise.race([exited, sleep(3000)]);
    try {
      fs.rmSync(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
    } catch {
      // 使用中で消せない一時フォルダは残す（OS の一時フォルダの掃除に任せる）
    }
  };
  return { ws: target.webSocketDebuggerUrl, close };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/// DevTools（CDP）の最小限の窓口。
async function devtools(wsUrl) {
  const ws = new WebSocket(wsUrl);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  let id = 0;
  const waiting = new Map();
  const logs = [];
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.id && waiting.has(msg.id)) {
      waiting.get(msg.id)(msg);
      waiting.delete(msg.id);
    } else if (msg.method === 'Runtime.consoleAPICalled') {
      logs.push(msg.params.args.map((a) => a.value ?? a.description).join(' '));
    } else if (msg.method === 'Runtime.exceptionThrown') {
      logs.push('exception: ' + (msg.params.exceptionDetails.exception?.description || msg.params.exceptionDetails.text));
    }
  };
  const send = (method, params = {}) => new Promise((resolve) => {
    id += 1;
    waiting.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });
  const evaluate = async (expr) => {
    const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
    if (r.result?.exceptionDetails) {
      throw new Error((r.result.exceptionDetails.exception?.description || r.result.exceptionDetails.text) + '\n' + logs.join('\n'));
    }
    return r.result?.result?.value;
  };
  await send('Runtime.enable');
  return { evaluate, logs, close: () => ws.close() };
}

function writePng(file, dataUrl) {
  fs.writeFileSync(file, Buffer.from(dataUrl.slice(dataUrl.indexOf(',') + 1), 'base64'));
}

// ---- 本体 ---------------------------------------------------------------------------------

async function main() {
  const o = parseArgs(process.argv.slice(2));
  const out = o.out || path.join(os.tmpdir(), 'efk-render', o.fx[0].name.replace(/[\\/]/g, '_'));
  fs.mkdirSync(out, { recursive: true });
  for (const f of fs.readdirSync(out)) if (/^f\d+\.png$|^sheet\.png$/.test(f)) fs.rmSync(path.join(out, f));
  const runtime = await ensureRuntime();
  const server = await serve(runtime);
  const url = `http://127.0.0.1:${server.address().port}/page/page.html`;
  const browser = await launch(findBrowser(), url);
  const cdp = await devtools(browser.ws);
  try {
    for (let i = 0; i < 100 && !(await cdp.evaluate('!!window.__efkPageReady')); i++) await sleep(100);
    const spec = { ...o, fx: o.fx };
    const info = await cdp.evaluate(`efkSetup(${JSON.stringify(spec)})`);
    if (info.errors.length) throw new Error('読み込めない効果: ' + info.errors.join(', '));
    let shotCount = 0;
    for (let f = 0; f <= o.frames; f += o.every) {
      writePng(path.join(out, `f${String(f).padStart(3, '0')}.png`), await cdp.evaluate('efkShot()'));
      shotCount += 1;
      if (f + o.every <= o.frames) await cdp.evaluate(`efkStep(${o.every})`);
    }
    const sheet = await cdp.evaluate(`efkSheet(${o.cols}, ${o.sheetScale})`);
    if (sheet) writePng(path.join(out, 'sheet.png'), sheet);
    console.log(JSON.stringify({ out, shots: shotCount, sheet: path.join(out, 'sheet.png'), camera: info.camera }));
    if (cdp.logs.length) process.stderr.write(cdp.logs.join('\n') + '\n');
  } finally {
    cdp.close();
    await browser.close();
    server.close();
  }
}

main().catch((e) => {
  console.error('error:', e.message);
  process.exit(1);
});
