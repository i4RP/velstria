// 画像 4 のミニマップから壁を抽出し、円と矩形で貪欲に当てはめて shapes.json（obstacles）を作る。
// 使い方: node fitwalls.mjs [最大個数]  → fit_walls.json（確認用の PNG は map_proto.png に mapproto.mjs が描く）
import fs from 'fs';
import { png } from './mapproto.mjs';
const MAXN = +(process.argv[2] || 34);
const rows = fs.readFileSync('rgb4.txt', 'utf8').trim().split(/\r?\n/).map((l) => l.split(';').filter(Boolean).map((s) => s.split(',').map(Number)));
const H = rows.length, W = rows[0].length, X0 = 95;
const lum = (x, y) => { const [R, G, B] = rows[y][x - X0]; return 0.3 * R + 0.59 * G + 0.11 * B; };
const rgb = (x, y) => rows[y][x - X0];
const CX = 537.25, CY = 435.5, U = 12000 / 868;
const S = 12000, mir = (p) => [S - p[0], S - p[1]];
// 隠れている画素（アイコン・顔写真）
const occl = [[288, 0, 392, 102], [468, 640, 575, 748]];
for (const l of fs.readFileSync('icons_raw_4.csv', 'utf8').trim().split(/\r?\n/)) { const [c, n, cx, cy, x0, y0, x1, y1] = l.split(','); if (+n >= 20) occl.push([+x0 - 4, +y0 - 4, +x1 + 4, +y1 + 4]); }
const hidden = (x, y) => occl.some(([a, b, c, d]) => x >= a && x <= c && y >= b && y <= d);
const CELL = 50, N = S / CELL;
const val = new Int8Array(N * N); // 1 = 暗い, 0 = 暗くない, -1 = 不明
for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
  const X = (c + 0.5) * CELL, Y = (r + 0.5) * CELL;
  const px = CX + (X - 6000) / U, py = CY - (Y - 6000) / U;
  let dark = 0, n = 0;
  for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const x = Math.round(px) + dx, y = Math.round(py) + dy; if (x - X0 < 0 || x - X0 >= W || y < 0 || y >= H || hidden(x, y)) continue; n++; const [R, G, B] = rgb(x, y); if (lum(x, y) < 68 && B < G + 25) dark++; }
  val[r * N + c] = n < 5 ? -1 : dark >= n / 2 ? 1 : 0;
}
const at = (X, Y) => { const c = Math.floor(X / CELL), r = Math.floor(Y / CELL); return c < 0 || r < 0 || c >= N || r >= N ? -1 : val[r * N + c]; };
// 点対称で統合（見える側を使う。両方見えれば OR）
const D = new Uint8Array(N * N);
for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) { const X = (c + 0.5) * CELL, Y = (r + 0.5) * CELL; const a = at(X, Y), b = at(S - X, S - Y); D[r * N + c] = a === 1 || b === 1 ? 1 : 0; }
// 設計の制約（除外域）
const layout = JSON.parse(fs.readFileSync('layout.json'));
const dPtSeg = (p, a, b) => { const abx = b[0] - a[0], aby = b[1] - a[1], l2 = abx * abx + aby * aby; const t = l2 < 1e-9 ? 0 : Math.max(0, Math.min(1, ((p[0] - a[0]) * abx + (p[1] - a[1]) * aby) / l2)); return Math.hypot(p[0] - a[0] - abx * t, p[1] - a[1] - aby * t); };
const laneD = (p) => Math.min(...Object.values(layout.lanes).map((path) => Math.min(...path.slice(1).map((q, i) => dPtSeg(p, path[i], q)))));
const camps = [...layout.blueCamps, ...layout.redCamps].flatMap(([, p]) => [p, mir(p)]).concat([layout.bosses.wyrm, layout.bosses.colossus, layout.riverCamp]);
const swap = { top: 'bot', bot: 'top', mid: 'mid' };
const towers = [...Object.values(layout.blueTowers).flat(), ...Object.entries(layout.blueTowers).flatMap(([l, a]) => layout.blueTowers[swap[l]].map(mir))];
const towersAll = [...towers, ...towers.map(mir)];
const forbidden = new Uint8Array(N * N), target = new Uint8Array(N * N);
const inJungle = (X, Y) => X > 1400 && X < 10600 && Y > 1050 && Y < 10950;
for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
  const p = [(c + 0.5) * CELL, (r + 0.5) * CELL];
  const bad = laneD(p) < 400 || camps.some((q) => Math.max(Math.abs(p[0] - q[0]), Math.abs(p[1] - q[1])) < 330) || towersAll.some((q) => Math.max(Math.abs(p[0] - q[0]), Math.abs(p[1] - q[1])) < 250)
    || Math.max(Math.abs(p[0] - layout.core[0]), Math.abs(p[1] - layout.core[1])) < 1900 || Math.max(Math.abs(p[0] - mir(layout.core)[0]), Math.abs(p[1] - mir(layout.core)[1])) < 1900
    || Math.hypot(p[0] - layout.bosses.wyrm[0], p[1] - layout.bosses.wyrm[1]) < 1100 || Math.hypot(p[0] - layout.bosses.colossus[0], p[1] - layout.bosses.colossus[1]) < 1100
    || !inJungle(p[0], p[1]);
  forbidden[r * N + c] = bad ? 1 : 0;
  target[r * N + c] = !bad && D[r * N + c] && p[0] + p[1] < 12000 ? 1 : 0;
}
let total = target.reduce((a, b) => a + b, 0);
console.log('target cells', total, '(', total * CELL * CELL / 1e6, 'M u²)');
// 候補: 円 / 矩形。得点 = 新たに覆う目標 − 2×(目標でない許可セル) 、禁止域を覆う候補は不可
const covered = new Uint8Array(N * N);
function evalCells(cells) { let gain = 0, bad = 0, forb = 0; for (const i of cells) { if (forbidden[i]) { forb++; continue; } if (target[i]) { if (!covered[i]) gain++; } else bad++; } return { gain, bad, forb }; }
const discCache = new Map();
function disc(r) { if (!discCache.has(r)) { const k = Math.ceil(r / CELL), o = []; for (let dy = -k; dy <= k; dy++) for (let dx = -k; dx <= k; dx++) if ((dx * dx + dy * dy) * CELL * CELL <= r * r) o.push([dx, dy]); discCache.set(r, o); } return discCache.get(r); }
function circleCells(c, r, rad) { const out = []; for (const [dx, dy] of disc(rad)) { const cc = c + dx, rr = r + dy; if (cc < 0 || rr < 0 || cc >= N || rr >= N) return null; out.push(rr * N + cc); } return out; }
const shapes = [];
for (let it = 0; it < MAXN; it++) {
  let best = null;
  for (let r = 0; r < N; r += 2) for (let c = 0; c < N; c += 2) {
    if (!target[r * N + c] || covered[r * N + c]) continue;
    for (const rad of [100, 150, 200, 250, 300, 350, 400]) {
      const cells = circleCells(c, r, rad); if (!cells) continue; const e = evalCells(cells); if (e.forb > 0) continue;
      const score = e.gain - 2.2 * e.bad; if (!best || score > best.score) best = { score, t: 'C', v: [Math.round((c + 0.5) * CELL / 10) * 10, Math.round((r + 0.5) * CELL / 10) * 10, rad], cells };
    }
    // 矩形: 種から各方向へ、追加する帯の 80% 以上が目標なら伸ばす
    let x0 = c, x1 = c, y0 = r, y1 = r;
    const okStrip = (cells) => { let t = 0, f = 0; for (const i of cells) { if (forbidden[i]) f++; else if (target[i]) t++; } return f === 0 && t >= 0.8 * cells.length; };
    let grew = true; while (grew) { grew = false;
      if (x1 + 1 < N && okStrip(Array.from({ length: y1 - y0 + 1 }, (_, k) => (y0 + k) * N + x1 + 1))) { x1++; grew = true; }
      if (x0 - 1 >= 0 && okStrip(Array.from({ length: y1 - y0 + 1 }, (_, k) => (y0 + k) * N + x0 - 1))) { x0--; grew = true; }
      if (y1 + 1 < N && okStrip(Array.from({ length: x1 - x0 + 1 }, (_, k) => (y1 + 1) * N + x0 + k))) { y1++; grew = true; }
      if (y0 - 1 >= 0 && okStrip(Array.from({ length: x1 - x0 + 1 }, (_, k) => (y0 - 1) * N + x0 + k))) { y0--; grew = true; } }
    if ((x1 - x0 + 1) * CELL >= 250 && (y1 - y0 + 1) * CELL >= 250) { const cells = []; for (let rr = y0; rr <= y1; rr++) for (let cc = x0; cc <= x1; cc++) cells.push(rr * N + cc); const e = evalCells(cells); const score = e.gain - 2.2 * e.bad; if (e.forb === 0 && (!best || score > best.score)) best = { score, t: 'R', v: [x0 * CELL, y0 * CELL, (x1 + 1) * CELL, (y1 + 1) * CELL], cells }; }
  }
  if (!best || best.score < 4) break;
  for (const i of best.cells) covered[i] = 1; shapes.push({ t: best.t, v: best.v }); 
}
const left = target.reduce((a, b, i) => a + (b && !covered[i] ? 1 : 0), 0);
console.log('shapes', shapes.length, 'uncovered target', left, 'of', total);
fs.writeFileSync('fit_walls.json', JSON.stringify(shapes));

// 確認用 PNG（fit_check.png）: 灰 = 目標（壁）、緑 = 当てはめで覆えた目標、赤 = 当てはめが目標でない所を覆った、青 = 除外域
function dumpPng() {
  const Z = 4, w = N * Z, buf = Buffer.alloc(w * w * 3);
  const inShape = new Uint8Array(N * N);
  for (const sh of shapes) { if (sh.t === 'R') { for (let r = Math.floor(sh.v[1] / CELL); r < sh.v[3] / CELL; r++) for (let c = Math.floor(sh.v[0] / CELL); c < sh.v[2] / CELL; c++) inShape[r * N + c] = 1; } else { for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) if (Math.hypot((c + 0.5) * CELL - sh.v[0], (r + 0.5) * CELL - sh.v[1]) <= sh.v[2]) inShape[r * N + c] = 1; } }
  for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
    const i = r * N + c; let col = [200, 200, 200];
    if (forbidden[i]) col = [150, 170, 215];
    if (D[i]) col = [110, 110, 110];
    if (inShape[i]) col = target[i] ? [60, 190, 80] : D[i] ? [230, 200, 60] : [220, 60, 60];
    for (let dy = 0; dy < Z; dy++) for (let dx = 0; dx < Z; dx++) { const o = (((N - 1 - r) * Z + dy) * w + c * Z + dx) * 3; buf[o] = col[0]; buf[o + 1] = col[1]; buf[o + 2] = col[2]; }
  }
  fs.writeFileSync('fit_check.png', png(w, w, buf));
}
dumpPng();
