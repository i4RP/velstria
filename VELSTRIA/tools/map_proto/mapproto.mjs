// マップ試作・検証: MapDefinition.standard（Swift）と同じ座標を camps.json / shapes.json に持ち、
// validationIssues と同じ制約（レーン 350・拠点 1800・タワー 210・キャンプ 300・草むらの重なり）と 100 格子の到達性を確認して PNG に描く。
// Swift のマップを変えたらこちらも同じ値に更新し、`node mapproto.mjs` が違反 0 になることを確かめてから反映する（Swift が使えない環境用）。
import fs from 'fs';
import zlib from 'zlib';
import { fileURLToPath } from 'url';

const S = 12000;
const mir = (p) => [S - p[0], S - p[1]];
const rectMir = (r) => ({ t: 'rect', minX: S - r.maxX, minY: S - r.maxY, maxX: S - r.minX, maxY: S - r.minY });
const R = (minX, minY, maxX, maxY) => ({ t: 'rect', minX, minY, maxX, maxY });
const C = (x, y, r) => ({ t: 'circle', c: [x, y], r });
const obMir = (o) => o.t === 'rect' ? rectMir(o) : { t: 'circle', c: mir(o.c), r: o.r };

// ---------- 定義 ----------
const layout = JSON.parse(fs.readFileSync(new URL('./layout.json', import.meta.url)));
export const blueCore = layout.core;
export const redCore = mir(blueCore);
export const blueFountain = layout.fountain;
export const lanes = layout.lanes;
export const blueTowers = layout.blueTowers;
export const blueCamps = layout.blueCamps;
export const redCamps = layout.redCamps;
export const bosses = layout.bosses;
export const riverCamp = layout.riverCamp;

const shapes = JSON.parse(fs.readFileSync(new URL(process.env.SHAPES || './shapes.json', import.meta.url)));
const toOb = (s) => s.t === 'R' ? R(...s.v) : C(...s.v);
export const blueObstacles = shapes.obstacles.map(toOb);
export const cornerObstacles = shapes.corner.map(toOb); // 左上の角（右下は点対称）
export const obstacles = [...blueObstacles, ...cornerObstacles].flatMap((o) => [o, obMir(o)]);
export const blueBrushes = shapes.brushes.map((b) => R(...b));
export const brushes = blueBrushes.flatMap((b) => [b, rectMir(b)]);

// ---------- 幾何 ----------
const sd = (o, p) => o.t === 'rect'
  ? Math.max(Math.max(o.minX - p[0], p[0] - o.maxX), Math.max(o.minY - p[1], p[1] - o.maxY))
  : Math.hypot(p[0] - o.c[0], p[1] - o.c[1]) - o.r;
const contains = (o, p, inf = 0) => o.t === 'rect'
  ? (p[0] >= o.minX - inf && p[0] <= o.maxX + inf && p[1] >= o.minY - inf && p[1] <= o.maxY + inf)
  : (Math.hypot(p[0] - o.c[0], p[1] - o.c[1]) <= o.r + inf);
function dPtSeg(p, a, b) {
  const abx = b[0] - a[0], aby = b[1] - a[1];
  const l2 = abx * abx + aby * aby;
  const t = l2 < 1e-9 ? 0 : Math.max(0, Math.min(1, ((p[0] - a[0]) * abx + (p[1] - a[1]) * aby) / l2));
  return Math.hypot(p[0] - (a[0] + abx * t), p[1] - (a[1] + aby * t));
}
function segIntersectsRect(a, b, r) {
  let t0 = 0, t1 = 1;
  const d = [b[0] - a[0], b[1] - a[1]];
  const p = [-d[0], d[0], -d[1], d[1]];
  const q = [a[0] - r.minX, r.maxX - a[0], a[1] - r.minY, r.maxY - a[1]];
  for (let k = 0; k < 4; k++) {
    if (Math.abs(p[k]) < 1e-12) { if (q[k] < 0) return false; }
    else { const t = q[k] / p[k]; if (p[k] < 0) t0 = Math.max(t0, t); else t1 = Math.min(t1, t); if (t0 > t1) return false; }
  }
  return true;
}
function distObSeg(o, a, b) {
  if (o.t === 'circle') return Math.max(0, dPtSeg(o.c, a, b) - o.r);
  if (segIntersectsRect(a, b, o)) return 0;
  const corners = [[o.minX, o.minY], [o.maxX, o.minY], [o.minX, o.maxY], [o.maxX, o.maxY]];
  const cp = (p) => [Math.min(Math.max(p[0], o.minX), o.maxX), Math.min(Math.max(p[1], o.minY), o.maxY)];
  let best = Math.min(Math.hypot(a[0] - cp(a)[0], a[1] - cp(a)[1]), Math.hypot(b[0] - cp(b)[0], b[1] - cp(b)[1]));
  for (const q of corners) best = Math.min(best, dPtSeg(q, a, b));
  return best;
}
const distObPoly = (o, path) => { let b = Infinity; for (let k = 1; k < path.length; k++) b = Math.min(b, distObSeg(o, path[k - 1], path[k])); return b; };
const rectOverlapsOb = (r, o) => o.t === 'rect'
  ? (r.minX < o.maxX && o.minX < r.maxX && r.minY < o.maxY && o.minY < r.maxY)
  : (Math.hypot(Math.min(Math.max(o.c[0], r.minX), r.maxX) - o.c[0], Math.min(Math.max(o.c[1], r.minY), r.maxY) - o.c[1]) < o.r);

export function allTowers() {
  const out = [];
  for (const lane of ['top', 'mid', 'bot']) for (const p of blueTowers[lane]) out.push({ team: 'blue', lane, p });
  const swap = { top: 'bot', bot: 'top', mid: 'mid' };
  for (const lane of ['top', 'mid', 'bot']) for (const p of blueTowers[swap[lane]]) out.push({ team: 'red', lane, p: mir(p) });
  return out;
}
export function allCamps() {
  const out = [];
  for (const [k, p] of blueCamps) out.push({ side: 'blue', kind: k, p });
  for (const [k, p] of redCamps) out.push({ side: 'red', kind: k, p });
  out.push({ side: 'neutral', kind: 'wyrm', p: bosses.wyrm });
  out.push({ side: 'neutral', kind: 'colossus', p: bosses.colossus });
  out.push({ side: 'neutral', kind: 'river', p: riverCamp });
  return out;
}

export function validate() {
  const issues = [];
  const lanePaths = Object.values(lanes);
  obstacles.forEach((o, k) => {
    for (const path of lanePaths) {
      const d = distObPoly(o, path);
      if (d < 350) issues.push(`obstacle ${k} ${JSON.stringify(o)} is ${Math.round(d)} from a lane`);
    }
    for (const f of [blueFountain, mir(blueFountain)]) if (sd(o, f) < 1800) issues.push(`obstacle ${k} inside base area (fountain)`);
    for (const c of [blueCore, redCore]) if (sd(o, c) < 1800) issues.push(`obstacle ${k} too close to core`);
  });
  for (const t of allTowers()) {
    obstacles.forEach((o, k) => { if (contains(o, t.p, 210)) issues.push(`tower ${t.team} ${t.lane} ${t.p} overlaps obstacle ${k}`); });
  }
  for (const c of [...allCamps(), ...allCamps().filter((x) => x.side !== 'neutral').map((x) => ({ ...x, kind: x.kind + '(mirror)', p: mir(x.p) }))]) {
    obstacles.forEach((o, k) => { if (contains(o, c.p, 300)) issues.push(`camp ${c.kind} ${c.p} overlaps obstacle ${k} ${JSON.stringify(o)}`); });
  }
  brushes.forEach((b, i) => {
    obstacles.forEach((o, k) => { if (rectOverlapsOb(b, o)) issues.push(`brush ${i} ${JSON.stringify(b)} overlaps obstacle ${k}`); });
    brushes.forEach((b2, j) => { if (j > i && rectOverlapsOb(b, b2)) issues.push(`brush ${i} overlaps brush ${j}`); });
  });
  return issues;
}

// ---------- ナビ（100 格子、半径 55）----------
const N = 120, CELL = 100;
export function clearanceGrid() {
  const cl = new Float64Array(N * N);
  for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
    const p = [(c + 0.5) * CELL, (r + 0.5) * CELL];
    let d = Math.min(p[0], p[1], S - p[0], S - p[1]);
    for (const o of obstacles) d = Math.min(d, sd(o, p));
    cl[r * N + c] = d;
  }
  return cl;
}
export function components(cl, radius = 55) {
  const comp = new Int32Array(N * N).fill(-1);
  let id = 0;
  for (let s = 0; s < N * N; s++) {
    if (comp[s] !== -1 || !(cl[s] > radius)) continue;
    const stack = [s]; comp[s] = id;
    while (stack.length) {
      const u = stack.pop(); const ur = Math.floor(u / N), uc = u % N;
      for (const [dr, dc] of [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]) {
        const r = ur + dr, c = uc + dc; if (r < 0 || c < 0 || r >= N || c >= N) continue;
        const v = r * N + c; if (comp[v] !== -1 || !(cl[v] > radius)) continue;
        comp[v] = id; stack.push(v);
      }
    }
    id++;
  }
  return { comp, count: id };
}
const cellOf = (p) => Math.floor(p[1] / CELL) * N + Math.floor(p[0] / CELL);
export function reachability() {
  const cl = clearanceGrid();
  const { comp, count } = components(cl);
  const issues = [];
  const f = comp[cellOf(blueFountain)];
  if (f < 0) issues.push('fountain not walkable');
  const targets = [...allCamps().map((c) => ['camp ' + c.kind + ' ' + c.p, c.p]), ['redCore', redCore], ['blueCore', blueCore],
    ...allTowers().map((t) => [`tower ${t.team} ${t.lane} ${t.p}`, t.p])];
  for (const [name, p] of targets) {
    const k = comp[cellOf(p)];
    if (k < 0) issues.push(`${name} cell not walkable (cl=${cl[cellOf(p)].toFixed(0)})`);
    else if (k !== f) issues.push(`${name} unreachable (component ${k} != ${f})`);
  }
  // 小さな孤立領域（歩ける面積）
  const sizes = {}; for (const k of comp) if (k >= 0) sizes[k] = (sizes[k] || 0) + 1;
  const isolated = Object.entries(sizes).filter(([k]) => +k !== f).map(([k, v]) => `${k}:${v}`);
  // レーン中心線の視線（半径 220）
  for (const [name, path] of Object.entries(lanes)) {
    for (let k = 1; k < path.length; k++) {
      const a = path[k - 1], b = path[k];
      const steps = Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / 25);
      for (let i = 0; i <= steps; i++) {
        const p = [a[0] + (b[0] - a[0]) * i / steps, a[1] + (b[1] - a[1]) * i / steps];
        let d = Math.min(p[0], p[1], S - p[0], S - p[1]);
        for (const o of obstacles) d = Math.min(d, sd(o, p));
        if (d <= 220) { issues.push(`lane ${name} seg ${k} blocked at ${p.map(Math.round)} cl=${d.toFixed(0)}`); break; }
      }
    }
  }
  return { issues, isolated, cl, comp, f };
}

// ---------- 描画 ----------
export function png(w, h, rgb) {
  const crc = (() => { const t = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return (b) => { let c = 0xffffffff; for (const x of b) c = t[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; }; })();
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 3 + 1)] = 0; rgb.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3); }
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([len, td, c]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}
export function render(file, scale = 14) { // 1 px = scale units
  const W = Math.round(S / scale), buf = Buffer.alloc(W * W * 3);
  const put = (x, y, c) => { if (x < 0 || y < 0 || x >= W || y >= W) return; const i = (y * W + x) * 3; buf[i] = c[0]; buf[i + 1] = c[1]; buf[i + 2] = c[2]; };
  const lanePaths = Object.values(lanes);
  const dLane = (p) => Math.min(...lanePaths.map((path) => { let b = Infinity; for (let k = 1; k < path.length; k++) b = Math.min(b, dPtSeg(p, path[k - 1], path[k])); return b; }));
  for (let y = 0; y < W; y++) for (let x = 0; x < W; x++) {
    const p = [(x + 0.5) * scale, S - (y + 0.5) * scale];
    let col = [96, 122, 128];
    const river = Math.abs(p[0] + p[1] - S) / Math.SQRT2 <= 450;
    if (river) col = [38, 118, 138];
    if (dLane(p) <= 550) col = [150, 165, 170];
    if (brushes.some((b) => contains(b, p))) col = [70, 140, 70];
    if (obstacles.some((o) => contains(o, p))) col = [38, 52, 54];
    put(x, y, col);
  }
  const dot = (p, r, c) => { const cx = Math.round(p[0] / scale), cy = Math.round((S - p[1]) / scale); for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) if (dx * dx + dy * dy <= r * r) put(cx + dx, cy + dy, c); };
  for (const t of allTowers()) dot(t.p, 6, t.team === 'blue' ? [60, 140, 255] : [255, 80, 80]);
  for (const c of allCamps()) dot(c.p, c.kind === 'wyrm' || c.kind === 'colossus' ? 12 : 5, c.kind.includes('Sentinel') ? [230, 60, 220] : c.kind === 'river' ? [80, 220, 255] : c.kind === 'small' ? [90, 220, 90] : [255, 100, 255]);
  dot(blueCore, 9, [40, 100, 255]); dot(redCore, 9, [255, 40, 40]);
  fs.writeFileSync(file, png(W, W, buf));
}

if (process.argv[1].endsWith('mapproto.mjs')) {
  const issues = validate();
  console.log('validation issues:', issues.length); issues.forEach((i) => console.log('  ', i));
  const r = reachability();
  console.log('reach issues:', r.issues.length); r.issues.forEach((i) => console.log('  ', i));
  console.log('isolated components (id:cells):', r.isolated.join(' ') || 'none');
  console.log('obstacles:', obstacles.length, 'brushes:', brushes.length, 'camps:', allCamps().length);
  render(fileURLToPath(new URL('./map_proto.png', import.meta.url)));
}
