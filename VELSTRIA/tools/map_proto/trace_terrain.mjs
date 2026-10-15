// MLBB の現行マップ（Sanctum Island）のミニマップ原本から、壁（岩）を滑らかな閉じたスプラインの制御点に、
// 起こす（2026-10-16）。岩は岩として読み、草むらは terrain_grid.mjs の細かい格子に任せる。
//
// 入力: minimap_sanctum.png（MLBB Wiki の File:Minimap.png、512×512、アイコンなし。著作物なのでコミットしない。
//   取得方法は minimap_fit.mjs の先頭のコメント）。
// 画素 → 地図座標（standard、12000）: x = −30 + 23.55·px、y = 12010 − 23.55·py（minimap_fit.mjs と同じ較正。
//   タワー・キャンプの測定値と同じ座標系）。
//
// 1. 各画素を最も近い地形色に分け（minimap_fit.mjs と同じ色表）、壁の確からしさを 25 ユニット格子へ読む。
//    点対称に平均し、少しぼかしてから 0.5 の等値線を引く（マーチングスクエア、格子より細かい精度の滑らかな輪郭）。
// 2. 壁: 塊ごとの輪郭を、弧長で等間隔（CONTROL_STEP）に並べた制御点にする。Swift 側（Spline.closedCatmullRom）が
//    閉じた Catmull-Rom スプラインでなめらかな多角形に戻す。地図の外枠（暗い緑）のうち地図の内側に入り込んだ所
//    （左上・右下の角の斜めの切り欠き）も壁として読む。拠点を囲む破線（拠点の範囲の印）は壁にしない。
//
// 使い方: node trace_terrain.mjs
//   → trace_stats.json と trace_debug.png（確認用。コミットしない）。続けて node terrain_swift.mjs --write。
import fs from 'fs';
import { readPNG, writePNG } from './png.mjs';

const S = 12000, G = 25, N = S / G;
const SX = 23.55, OX = -30, OY = 12010;
/** 制御点の間隔（ユニット）。スプラインが輪郭から外れる量は 1〜2 % 程度。 */
const CONTROL_STEP = 160;
/** これより小さい壁の塊は捨てる（セル数。25×25 ユニット）。 */
const MIN_WALL_CELLS = 30;

const im = readPNG(new URL('./minimap_sanctum.png', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const W = im.w, H = im.h;
const idx = (r, c) => r * N + c;
const cx = (c) => (c + 0.5) * G, cy = (r) => (r + 0.5) * G;
const toPx = (x, y) => [(x - OX) / SX, (OY - y) / SX];

// ---------- 1. 地形色 ----------
// [名前, 色, 壁]
const PAL = [
  ['wall', [16, 36, 44], 1], ['frame', [6, 28, 20], 1], ['wall2', [12, 34, 40], 1],
  ['floor', [60, 84, 92], 0], ['lane', [84, 108, 116], 0], ['laneBright', [116, 159, 174], 0],
  ['bushJ', [84, 117, 136], 0], ['bushL', [111, 137, 149], 0], ['bushR', [104, 146, 157], 0],
  ['river', [20, 116, 138], 0], ['blueBase', [28, 78, 114], 0], ['blueBase2', [36, 84, 112], 0],
  ['redBase', [84, 48, 56], 0], ['redBase2', [84, 44, 48], 0],
];
function soft(channel) {
  const out = new Float32Array(W * H);
  for (let i = 0; i < W * H; i++) {
    const ds = PAL.map((p) => [(im.rgb[i * 3] - p[1][0]) ** 2 + (im.rgb[i * 3 + 1] - p[1][1]) ** 2 + (im.rgb[i * 3 + 2] - p[1][2]) ** 2, p[channel]])
      .sort((a, b) => a[0] - b[0]);
    const a = Math.sqrt(ds[0][0]), b = Math.sqrt(ds[1][0]);
    out[i] = ds[0][1] === ds[1][1] ? ds[0][1] : (ds[0][1] * b + ds[1][1] * a) / (a + b + 1e-9);
  }
  return out;
}
function bilinear(arr, x, y) {
  const [fx0, fy0] = toPx(x, y); const fx = fx0 - 0.5, fy = fy0 - 0.5;
  const x0 = Math.floor(fx), y0 = Math.floor(fy), tx = fx - x0, ty = fy - y0;
  const at = (px, py) => arr[Math.min(H - 1, Math.max(0, py)) * W + Math.min(W - 1, Math.max(0, px))];
  return at(x0, y0) * (1 - tx) * (1 - ty) + at(x0 + 1, y0) * tx * (1 - ty) + at(x0, y0 + 1) * (1 - tx) * ty + at(x0 + 1, y0 + 1) * tx * ty;
}
/** 格子へ読み、点対称に平均し、σ = 1 セルでぼかす。 */
function field(prob) {
  const m = new Float32Array(N * N);
  for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) m[idx(r, c)] = bilinear(prob, cx(c), cy(r));
  const s = new Float32Array(N * N);
  for (let k = 0; k < N * N; k++) s[k] = (m[k] + m[N * N - 1 - k]) / 2;
  const kern = [0.0545, 0.2442, 0.4026, 0.2442, 0.0545];
  const tmp = new Float32Array(N * N), out = new Float32Array(N * N);
  for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
    let v = 0; for (let d = -2; d <= 2; d++) v += kern[d + 2] * s[idx(r, Math.min(N - 1, Math.max(0, c + d)))]; tmp[idx(r, c)] = v;
  }
  for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
    let v = 0; for (let d = -2; d <= 2; d++) v += kern[d + 2] * tmp[idx(Math.min(N - 1, Math.max(0, r + d)), c)]; out[idx(r, c)] = v;
  }
  return out;
}
const wallF = field(soft(2));

// ---------- 連結成分 ----------
function components(mask, minCells) {
  const label = new Int32Array(N * N).fill(-1);
  const comps = [];
  for (let k = 0; k < N * N; k++) {
    if (!mask[k] || label[k] >= 0) continue;
    const id = comps.length, cells = [k], stack = [k];
    label[k] = id;
    while (stack.length) {
      const q = stack.pop(), r = Math.floor(q / N), c = q % N;
      for (let dr = -1; dr <= 1; dr++) for (let dc = -1; dc <= 1; dc++) {
        const rr = r + dr, cc = c + dc;
        if ((dr || dc) && rr >= 0 && cc >= 0 && rr < N && cc < N) {
          const j = idx(rr, cc);
          if (mask[j] && label[j] < 0) { label[j] = id; cells.push(j); stack.push(j); }
        }
      }
    }
    let sx = 0, sy = 0, r0 = N, r1 = 0, c0 = N, c1 = 0;
    for (const q of cells) { const r = Math.floor(q / N), c = q % N; sx += cx(c); sy += cy(r); r0 = Math.min(r0, r); r1 = Math.max(r1, r); c0 = Math.min(c0, c); c1 = Math.max(c1, c); }
    comps.push({ id, cells, n: cells.length, x: sx / cells.length, y: sy / cells.length, r0, r1, c0, c1 });
  }
  return { label, comps: comps.filter((c) => c.n >= minCells), all: comps };
}

// ---------- マーチングスクエア（1 つの塊の外周） ----------
function outline(F, label, comp) {
  // 塊の周り 3 セルだけを見る（隣の塊は 0 にして切り離す）
  const pad = 3, r0 = comp.r0 - pad, c0 = comp.c0 - pad, R = comp.r1 - comp.r0 + 1 + 2 * pad, C = comp.c1 - comp.c0 + 1 + 2 * pad;
  const own = new Uint8Array(R * C);
  for (const q of comp.cells) { const r = Math.floor(q / N) - r0, c = (q % N) - c0; own[r * C + c] = 1; }
  // 自分の塊から 2 セル以内（他の塊でない所）の値だけを使う
  const near = new Uint8Array(R * C);
  for (let r = 0; r < R; r++) for (let c = 0; c < C; c++) if (own[r * C + c]) {
    for (let dr = -2; dr <= 2; dr++) for (let dc = -2; dc <= 2; dc++) { const rr = r + dr, cc = c + dc; if (rr >= 0 && cc >= 0 && rr < R && cc < C) near[rr * C + cc] = 1; }
  }
  const v = (r, c) => {
    if (r <= 0 || c <= 0 || r >= R - 1 || c >= C - 1) return 0;
    const gr = r + r0, gc = c + c0;
    if (gr < 0 || gc < 0 || gr >= N || gc >= N) return 0;
    const l = label[idx(gr, gc)];
    if (l >= 0 && l !== comp.id) return 0;
    return near[r * C + c] ? F[idx(gr, gc)] : 0;
  };
  const iso = 0.5;
  // 辺上の点: キー → 座標
  const pts = new Map();
  const edgePoint = (key, ra, ca, rb, cb) => {
    if (!pts.has(key)) {
      const a = v(ra, ca), b = v(rb, cb), t = Math.abs(b - a) < 1e-9 ? 0.5 : (iso - a) / (b - a);
      const rr = ra + (rb - ra) * t, cc = ca + (cb - ca) * t;
      pts.set(key, [cx(cc + c0), cy(rr + r0)]);
    }
    return key;
  };
  const segs = [];
  for (let r = 0; r < R - 1; r++) for (let c = 0; c < C - 1; c++) {
    const a = v(r, c) >= iso, b = v(r, c + 1) >= iso, d = v(r + 1, c) >= iso, e = v(r + 1, c + 1) >= iso;
    const code = (a ? 1 : 0) | (b ? 2 : 0) | (e ? 4 : 0) | (d ? 8 : 0);
    if (code === 0 || code === 15) continue;
    const T = () => edgePoint(`h${r},${c}`, r, c, r, c + 1);        // 下の辺（r 行）
    const B = () => edgePoint(`h${r + 1},${c}`, r + 1, c, r + 1, c + 1); // 上の辺
    const L = () => edgePoint(`v${r},${c}`, r, c, r + 1, c);
    const Rt = () => edgePoint(`v${r},${c + 1}`, r, c + 1, r + 1, c + 1);
    const center = (v(r, c) + v(r, c + 1) + v(r + 1, c) + v(r + 1, c + 1)) / 4 >= iso;
    switch (code) {
      case 1: case 14: segs.push([L(), T()]); break;
      case 2: case 13: segs.push([T(), Rt()]); break;
      case 3: case 12: segs.push([L(), Rt()]); break;
      case 4: case 11: segs.push([Rt(), B()]); break;
      case 6: case 9: segs.push([T(), B()]); break;
      case 7: case 8: segs.push([L(), B()]); break;
      case 5: if (center) { segs.push([L(), B()]); segs.push([T(), Rt()]); } else { segs.push([L(), T()]); segs.push([Rt(), B()]); } break;
      case 10: if (center) { segs.push([L(), T()]); segs.push([Rt(), B()]); } else { segs.push([L(), B()]); segs.push([T(), Rt()]); } break;
    }
  }
  // 線分をつなぐ
  const byPt = new Map();
  segs.forEach((s, i) => { for (const p of s) { if (!byPt.has(p)) byPt.set(p, []); byPt.get(p).push(i); } });
  const used = new Uint8Array(segs.length);
  const loops = [];
  for (let i = 0; i < segs.length; i++) {
    if (used[i]) continue;
    used[i] = 1;
    const loop = [segs[i][0]];
    let cur = segs[i][1];
    while (cur !== loop[0]) {
      loop.push(cur);
      const next = (byPt.get(cur) || []).find((j) => !used[j]);
      if (next === undefined) break;
      used[next] = 1;
      cur = segs[next][0] === cur ? segs[next][1] : segs[next][0];
    }
    loops.push(loop.map((k) => pts.get(k)));
  }
  loops.sort((p, q) => Math.abs(area(q)) - Math.abs(area(p)));
  let poly = loops[0];
  if (area(poly) < 0) poly = poly.slice().reverse();
  return poly;
}
function area(poly) {
  let a = 0; for (let i = 0; i < poly.length; i++) { const p = poly[i], q = poly[(i + 1) % poly.length]; a += p[0] * q[1] - q[0] * p[1]; } return a / 2;
}
/** 閉じた折れ線を弧長で等間隔に並べ直す（間隔 step 前後、点は最低 6 つ）。 */
function resample(poly, step) {
  const n = poly.length, cum = [0];
  for (let i = 0; i < n; i++) { const p = poly[i], q = poly[(i + 1) % n]; cum.push(cum[i] + Math.hypot(q[0] - p[0], q[1] - p[1])); }
  const L = cum[n], k = Math.max(6, Math.round(L / step)), out = [];
  let j = 0;
  for (let i = 0; i < k; i++) {
    const s = (i / k) * L;
    while (cum[j + 1] < s) j++;
    const p = poly[j], q = poly[(j + 1) % n], t = (s - cum[j]) / Math.max(1e-9, cum[j + 1] - cum[j]);
    out.push([p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t]);
  }
  return out;
}

// ---------- 2. 壁 ----------
// 地図の縁の 3 セル（75）は外枠の細い帯なので壁にしない（移動の限界は地図の縁）。
// 角の切り欠きは帯の内側で輪郭が閉じるので、縁の近くの頂点を地図の外へ出す（snapOut）。
const BORDER_CELLS = 3;
const wallMask = new Uint8Array(N * N);
for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
  const edge = r < BORDER_CELLS || c < BORDER_CELLS || r >= N - BORDER_CELLS || c >= N - BORDER_CELLS;
  wallMask[idx(r, c)] = !edge && wallF[idx(r, c)] >= 0.5 ? 1 : 0;
}
for (let k = 0; k < N * N; k++) if (!wallMask[k]) wallF[k] = Math.min(wallF[k], 0.49);
/** 重なった点と、地図の外の同じ直線上に並んだ中間の点を除く（スプラインの区間の長さ 0 を避ける）。 */
function dedupe(poly) {
  let p = poly.filter((q, i) => { const r = poly[(i + 1) % poly.length]; return Math.hypot(q[0] - r[0], q[1] - r[1]) > 1; });
  const outside = (q) => q[0] < 0 || q[0] > S || q[1] < 0 || q[1] > S;
  const same = (a, b, k) => a[k] === b[k] && (a[k] < 0 || a[k] > S);
  return p.filter((q, i) => {
    const a = p[(i - 1 + p.length) % p.length], b = p[(i + 1) % p.length];
    return !(outside(q) && ((same(a, q, 0) && same(q, b, 0)) || (same(a, q, 1) && same(q, b, 1))));
  });
}
function snapOut(poly) {
  const lim = (BORDER_CELLS + 1.5) * G, out = 150;
  return poly.map(([x, y]) => [x < lim ? -out : x > S - lim ? S + out : x, y < lim ? -out : y > S - lim ? S + out : y]);
}
const W0 = components(wallMask, MIN_WALL_CELLS);
// 拠点を囲む破線: 拠点の角（Blue は (0, 0)、Red は (S, S)）からの距離がほぼ一定の小さな塊
const BASE_ARC = { r0: 3500, r1: 4700, maxCells: 260 };
function isBaseDash(c) {
  if (c.n > BASE_ARC.maxCells) return false;
  return [[0, 0], [S, S]].some(([bx, by]) => { const d = Math.hypot(c.x - bx, c.y - by); return d > BASE_ARC.r0 && d < BASE_ARC.r1; });
}
const half = (c) => {
  const s = c.x + c.y;
  if (Math.abs(c.x - S / 2) < 60 && Math.abs(c.y - S / 2) < 60) return 'center';
  return s < S - 1 || (Math.abs(s - S) <= 1 && c.x < c.y) ? 'blue' : 'red';
};
const walls = [];
const dropped = [];
for (const c of W0.comps) {
  const side = half(c);
  if (side === 'red') continue;
  if (isBaseDash(c)) { dropped.push({ why: 'base-dash', x: Math.round(c.x), y: Math.round(c.y), n: c.n }); continue; }
  const raw = outline(wallF, W0.label, c);
  if (!raw || raw.length < 6) continue;
  const touches = c.r0 <= BORDER_CELLS || c.c0 <= BORDER_CELLS || c.r1 >= N - 1 - BORDER_CELLS || c.c1 >= N - 1 - BORDER_CELLS;
  const control = resample(raw, CONTROL_STEP);
  walls.push({ side, n: c.n, x: c.x, y: c.y, poly: raw, control: touches ? dedupe(snapOut(control)) : control });
}

// 草むらは terrain_grid.mjs（20 ユニットの細かい格子。MapSanctumBushGrid.swift）が起こす。

// ---------- 報告・確認画像 ----------
console.log(`walls: ${walls.length}（blue ${walls.filter((w) => w.side === 'blue').length}, center ${walls.filter((w) => w.side === 'center').length}）` +
  ` 制御点 ${walls.reduce((a, w) => a + w.control.length, 0)}、捨てた塊 ${dropped.length}`);
for (const w of walls) console.log(`  wall ${w.side} (${Math.round(w.x)}, ${Math.round(w.y)}) cells ${w.n} 輪郭 ${w.poly.length} 制御点 ${w.control.length}`);
for (const d of dropped) console.log(`  dropped ${d.why} (${d.x}, ${d.y}) cells ${d.n}`);

{
  const K = 2, D = W * K, rgb = Buffer.alloc(D * D * 3);
  for (let y = 0; y < D; y++) for (let x = 0; x < D; x++) {
    const i = (Math.floor(y / K) * W + Math.floor(x / K)) * 3, o = (y * D + x) * 3;
    rgb[o] = im.rgb[i] * 0.6; rgb[o + 1] = im.rgb[i + 1] * 0.6; rgb[o + 2] = im.rgb[i + 2] * 0.6;
  }
  const plot = (x, y, col) => { const [px, py] = toPx(x, y); const X = Math.round(px * K), Y = Math.round(py * K); if (X >= 0 && Y >= 0 && X < D && Y < D) { const o = (Y * D + X) * 3; rgb[o] = col[0]; rgb[o + 1] = col[1]; rgb[o + 2] = col[2]; } };
  const line = (a, b, col) => { const n = Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / 8); for (let i = 0; i <= n; i++) plot(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n, col); };
  const mir = (p) => [S - p[0], S - p[1]];
  for (const w of walls) {
    for (const poly of w.side === 'center' ? [w.control] : [w.control, w.control.map(mir)]) {
      for (let i = 0; i < poly.length; i++) line(poly[i], poly[(i + 1) % poly.length], [255, 120, 40]);
      for (const p of poly) plot(p[0], p[1], [255, 255, 0]);
    }
  }
  writePNG(new URL('./trace_debug.png', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'), D, D, rgb);
}
fs.writeFileSync(new URL('./trace_stats.json', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'),
  JSON.stringify({ walls: walls.map((w) => ({ side: w.side, control: w.control.map((p) => p.map((v) => Math.round(v))) })) }));

// Swift への書き出しは terrain_swift.mjs（壁との距離の検証とキャンプの位置合わせを含む）。
