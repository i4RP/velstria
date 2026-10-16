// ユーザー提供の設計図（MOBA マップ設計図、60×60 マスの方眼。2026-10-16）から、壁・草むら・川・キャンプを起こす。
// trace_terrain.mjs（MLBB のミニマップ原本）の置き換え。広さ・レーン・タワー・拠点は今のまま（設計図のレーンの帯に合わせて較正）。
//
// 入力: blueprint_ref.png（設計図の画像 1448×1086。コミットしない）。
// 画素 → 地図座標（standard、12000）: レーンの帯の中心（左 463 px・右 1280 px・上 185 px・下 961 px）を
//   standard のレーンの中心線（縁から 700）に合わせる。x = 700 + (px − 463)·12.97、y = 700 + (961 − py)·13.66。
//
// 1. 画素を設計図の凡例の色（壁 = 濃いグレー、草むら = 緑のハッチング、川 = 薄い青、床 = ベージュ・薄緑）に分け、
//    25 ユニット格子（草むらは 20 ユニット格子）へ読み、点対称に平均してぼかす。文字の注記は消す。
// 2. 壁: レーン・拠点・タワー・キャンプ・川の周りを空けてから、塊ごとの輪郭を制御点にする（trace_terrain.mjs と同じ）。
// 3. 川: 橋と祭壇で切れた水面をクロージングでつなぎ、1 つの多角形の制御点にする（点対称の中心をまたぐ 8 の字）。
// 4. 草むら: 緑の塊（小さいものは捨てる）を Blue 半面で番号付けし、Red は点対称（BushMask、MapSanctumBushGrid.swift）。
// 5. キャンプ: 設計図のアイコンの位置（点対称に平均）。壁からの距離の調整は terrain_swift.mjs。
//
// 使い方: node blueprint_terrain.mjs [--write]
//   → trace_stats.json（壁・川・キャンプ）と blueprint_debug.png（確認用。コミットしない）。
//   → --write で MapSanctumBushGrid.swift。続けて node terrain_swift.mjs --write。
import fs from 'fs';
import { readPNG, writePNG } from './png.mjs';

const here = (f) => new URL(`./${f}`, import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const S = 12000, K = 0.81;
const PX0 = 463, PY0 = 961, SXP = 12.97, SYP = 13.66;
const toPx = (x, y) => [PX0 + (x - 700) / SXP, PY0 - (y - 700) / SYP];
const fromPx = (px, py) => [700 + (px - PX0) * SXP, 700 + (PY0 - py) * SYP];
const mir = (p) => [S - p[0], S - p[1]];

const im = readPNG(here('blueprint_ref.png'));
const W = im.w, H = im.h;

// ---------- 1. 色 ----------
const WALL = 0, BUSH = 1, RIVER = 2, FLOOR = 3;
const PAL = [
  [[124, 137, 139], WALL], [[94, 106, 110], WALL], [[59, 74, 75], WALL], [[144, 157, 170], WALL], [[16, 21, 23], WALL],
  [[90, 158, 83], BUSH], [[47, 114, 50], BUSH], [[70, 135, 65], BUSH],
  [[114, 196, 241], RIVER], [[190, 229, 249], RIVER], [[150, 212, 245], RIVER],
  [[239, 234, 200], FLOOR], [[175, 210, 149], FLOOR], [[200, 215, 169], FLOOR], [[144, 184, 128], FLOOR],
  [[199, 202, 198], FLOOR], [[246, 136, 50], FLOOR], [[12, 99, 241], FLOOR], [[220, 50, 50], FLOOR],
  [[150, 90, 220], FLOOR], [[255, 255, 255], FLOOR], [[230, 120, 120], FLOOR],
];
// 文字の注記（画素の矩形）。地図の中のラベルだけ
const LABELS = [
  [785, 180, 910, 207], [828, 282, 955, 322], [600, 422, 765, 466], [800, 422, 885, 464], [800, 552, 895, 602],
  [565, 598, 700, 642], [665, 655, 770, 750], [1005, 582, 1095, 627], [980, 692, 1110, 737], [785, 835, 920, 878],
  [865, 945, 985, 972], [1245, 520, 1315, 602],
];
const prob = [0, 1, 2, 3].map(() => new Float32Array(W * H));
for (let i = 0; i < W * H; i++) {
  const x = i % W, y = Math.floor(i / W);
  if (LABELS.some(([a, b, c, d]) => x >= a && x <= c && y >= b && y <= d)) { prob[FLOOR][i] = 1; continue; }
  const r = im.rgb[i * 3], g = im.rgb[i * 3 + 1], b = im.rgb[i * 3 + 2];
  // 岩: 彩度が低く（灰色）明るすぎない。明るい上面から暗い影・輪郭線まで
  const sat = Math.max(r, g, b) - Math.min(r, g, b), lum = (r + g + b) / 3;
  if (sat < 34 && lum < 182) { prob[WALL][i] = 1; continue; }
  const ds = PAL.map(([c, k]) => [(r - c[0]) ** 2 + (g - c[1]) ** 2 + (b - c[2]) ** 2, k]).sort((p, q) => p[0] - q[0]);
  const a = Math.sqrt(ds[0][0]), bb = Math.sqrt(ds[1][0]);
  if (ds[0][1] === ds[1][1]) prob[ds[0][1]][i] = 1;
  else { prob[ds[0][1]][i] = bb / (a + bb + 1e-9); prob[ds[1][1]][i] = a / (a + bb + 1e-9); }
}
function sampler(arr) {
  return (x, y) => {
    const [fx0, fy0] = toPx(x, y); const fx = fx0 - 0.5, fy = fy0 - 0.5;
    const x0 = Math.floor(fx), y0 = Math.floor(fy), tx = fx - x0, ty = fy - y0;
    const at = (px, py) => arr[Math.min(H - 1, Math.max(0, py)) * W + Math.min(W - 1, Math.max(0, px))];
    return at(x0, y0) * (1 - tx) * (1 - ty) + at(x0 + 1, y0) * tx * (1 - ty) + at(x0, y0 + 1) * (1 - tx) * ty + at(x0 + 1, y0 + 1) * tx * ty;
  };
}
/** 格子へ読み、点対称にそろえ（blueOnly: Blue 半面の値を写す。設計図の左右は少し違うので岩・草むらは Blue 側を正とする。
 *  そうでなければ両半面の平均）、passes 回ぼかす。 */
function field(arr, G, passes, blueOnly = false) {
  const N = S / G, get = sampler(arr), m = new Float32Array(N * N);
  for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) m[r * N + c] = get((c + 0.5) * G, (r + 0.5) * G);
  let s = new Float32Array(N * N);
  for (let k = 0; k < N * N; k++) {
    const blue = (k % N) + Math.floor(k / N) < N - 1;
    s[k] = blueOnly ? (blue ? m[k] : m[N * N - 1 - k]) : (m[k] + m[N * N - 1 - k]) / 2;
  }
  const kern = [0.0545, 0.2442, 0.4026, 0.2442, 0.0545];
  for (let p = 0; p < passes; p++) {
    const tmp = new Float32Array(N * N), out = new Float32Array(N * N);
    for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
      let v = 0; for (let d = -2; d <= 2; d++) v += kern[d + 2] * s[r * N + Math.min(N - 1, Math.max(0, c + d))]; tmp[r * N + c] = v;
    }
    for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
      let v = 0; for (let d = -2; d <= 2; d++) v += kern[d + 2] * tmp[Math.min(N - 1, Math.max(0, r + d)) * N + c]; out[r * N + c] = v;
    }
    s = out;
  }
  return s;
}

// ---------- 配置（standard。MapDefinition.standard と同じ） ----------
const bc = [1250, 1250], rc = mir(bc);
const lanes = [
  [bc, [700, 2600], [700, 9400], [2600, 11300], [9400, 11300], rc],
  [bc, [2300, 2300], [9700, 9700], rc],
  [bc, [2600, 700], [9400, 700], [11300, 2600], [11300, 9400], rc],
];
const blueTowers = [[484, 8793], [556, 6342], [639, 3166], [4656, 4991], [3391, 3705], [2399, 2399], [8848, 567], [5423, 470], [3179, 630]];
const towers = blueTowers.concat(blueTowers.map(mir));
const segDist = (p, a, b) => { const dx = b[0] - a[0], dy = b[1] - a[1], l = dx * dx + dy * dy; let t = l ? ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l : 0; t = Math.max(0, Math.min(1, t)); return Math.hypot(p[0] - a[0] - dx * t, p[1] - a[1] - dy * t); };
const laneDist = (p) => Math.min(...lanes.map((L) => { let d = Infinity; for (let k = 1; k < L.length; k++) d = Math.min(d, segDist(p, L[k - 1], L[k])); return d; }));

// キャンプ（設計図のアイコンの画素 → standard。点対称の組は平均）。順は standard.camps と同じ:
// Blue 5（紫バフ・赤バフ・棘角トカゲ・熔岩の岩人・熾甲虫）・Red 5・星喰竜・巨像・苔甲・宝殻蟹 2
const P = (px, py) => fromPx(px, py);
const avg = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
const blueCamp = {
  blueSentinel: avg(P(623, 585), mir(P(1114, 572))),
  redSentinel: avg(P(863, 818), mir(P(852, 360))),
  hornLizard: mir(P(1201, 486)),
  magmaGolem: P(803, 738),
  emberBeetle: avg(P(978, 864), mir(P(709, 302))),
};
const wyrm = avg(P(1064, 768), mir(P(670, 393)));   // 右下の池（大型: バロン）
const colossus = mir(wyrm);                          // 左上の池（大型: リフトヘラルド）
const order = ['blueSentinel', 'redSentinel', 'hornLizard', 'magmaGolem', 'emberBeetle'];
// 苔甲（川の中立）は巨像の池から中央へ向かう水路、宝殻蟹は池の外れ（下で川の中へ寄せる）
const moss = [colossus[0] + 0.55 * (S / 2 - colossus[0]), colossus[1] + 0.55 * (S / 2 - colossus[1])];
let crab = [colossus[0] - 1100, colossus[1] + 600];
const RADIUS = { blueSentinel: 110, redSentinel: 110, hornLizard: 80, magmaGolem: 95, emberBeetle: 80, astralWyrm: 180, ancientColossus: 220, mossWanderer: 75, crab: 85 };

// ---------- 2. 壁 ----------
const G = 25, N = S / G, idx = (r, c) => r * N + c;
const cx = (c) => (c + 0.5) * G, cy = (r) => (r + 0.5) * G;
const wallF = field(prob[WALL], G, 2, true);
const riverF = field(prob[RIVER], G, 1);

// 川: 0.45 以上 → クロージング（橋・祭壇・文字の穴）→ 最大の塊 → 穴埋め
function dilate(m, R) {
  const out = new Uint8Array(N * N), offs = [];
  for (let dr = -R; dr <= R; dr++) for (let dc = -R; dc <= R; dc++) if (dr * dr + dc * dc <= R * R) offs.push([dr, dc]);
  for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) if (m[idx(r, c)]) {
    for (const [dr, dc] of offs) { const rr = r + dr, cc = c + dc; if (rr >= 0 && cc >= 0 && rr < N && cc < N) out[idx(rr, cc)] = 1; }
  }
  return out;
}
const invert = (m) => m.map((v) => 1 - v);
const erode = (m, R) => invert(dilate(invert(m), R));
function components(mask, minCells = 0) {
  const label = new Int32Array(N * N).fill(-1), comps = [];
  for (let k = 0; k < N * N; k++) {
    if (!mask[k] || label[k] >= 0) continue;
    const id = comps.length, cells = [k], stack = [k];
    label[k] = id;
    while (stack.length) {
      const q = stack.pop(), r = Math.floor(q / N), c = q % N;
      for (let dr = -1; dr <= 1; dr++) for (let dc = -1; dc <= 1; dc++) {
        const rr = r + dr, cc = c + dc;
        if ((dr || dc) && rr >= 0 && cc >= 0 && rr < N && cc < N) { const j = idx(rr, cc); if (mask[j] && label[j] < 0) { label[j] = id; cells.push(j); stack.push(j); } }
      }
    }
    let sx = 0, sy = 0, r0 = N, r1 = 0, c0 = N, c1 = 0;
    for (const q of cells) { const r = Math.floor(q / N), c = q % N; sx += cx(c); sy += cy(r); r0 = Math.min(r0, r); r1 = Math.max(r1, r); c0 = Math.min(c0, c); c1 = Math.max(c1, c); }
    comps.push({ id, cells, n: cells.length, x: sx / cells.length, y: sy / cells.length, r0, r1, c0, c1 });
  }
  return { label, comps: comps.filter((c) => c.n >= minCells) };
}
let riverMask = new Uint8Array(N * N);
for (let k = 0; k < N * N; k++) riverMask[k] = riverF[k] >= 0.45 ? 1 : 0;
riverMask = erode(dilate(riverMask, 16), 16);
{
  const { label, comps } = components(riverMask);
  const big = comps.sort((a, b) => b.n - a.n)[0];
  for (let k = 0; k < N * N; k++) riverMask[k] = label[k] === big.id ? 1 : 0;
  // 穴埋め: 外から届かない 0 を 1 に
  const outside = new Uint8Array(N * N), st = [];
  for (let i = 0; i < N; i++) for (const q of [idx(0, i), idx(N - 1, i), idx(i, 0), idx(i, N - 1)]) if (!riverMask[q] && !outside[q]) { outside[q] = 1; st.push(q); }
  while (st.length) { const q = st.pop(), r = Math.floor(q / N), c = q % N; for (const [dr, dc] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const rr = r + dr, cc = c + dc; if (rr >= 0 && cc >= 0 && rr < N && cc < N) { const j = idx(rr, cc); if (!riverMask[j] && !outside[j]) { outside[j] = 1; st.push(j); } } } }
  for (let k = 0; k < N * N; k++) if (!outside[k]) riverMask[k] = 1;
  // 点対称にそろえる
  for (let k = 0; k < N * N; k++) if (riverMask[k] !== riverMask[N * N - 1 - k]) { riverMask[k] = 1; riverMask[N * N - 1 - k] = 1; }
}

// 壁を置かない所（standard のユニット）。relayout の規則（レーン 350・拠点 1600・タワー 210）を 0.81 で割り、スプラインのはみ出し分の余裕を足す
const CLEAR = { lane: 350 / K + 50, base: 1600 / K + 60, tower: 210 / K + 40 };
const BORDER = 520;
const campSpots = [
  ...order.map((k) => [blueCamp[k], RADIUS[k]]), ...order.map((k) => [mir(blueCamp[k]), RADIUS[k]]),
  [wyrm, RADIUS.astralWyrm], [colossus, RADIUS.ancientColossus],
];
const wallMask = new Uint8Array(N * N);
for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
  const p = [cx(c), cy(r)], q = idx(r, c);
  if (wallF[q] < 0.5 || riverMask[q]) continue;
  if (p[0] < BORDER || p[1] < BORDER || p[0] > S - BORDER || p[1] > S - BORDER) continue;
  if (laneDist(p) < CLEAR.lane) continue;
  if ([[600, 600], mir([600, 600]), bc, rc].some((b) => Math.hypot(p[0] - b[0], p[1] - b[1]) < CLEAR.base)) continue;
  if (towers.some((t) => Math.hypot(p[0] - t[0], p[1] - t[1]) < CLEAR.tower)) continue;
  if (campSpots.some(([cp, rad]) => Math.hypot(p[0] - cp[0], p[1] - cp[1]) < (rad + 40) / K + 70)) continue;
  wallMask[q] = 1;
}
// 細い線（文字・矢印の残り）を落とす: 1 セルのオープニング
{
  const opened = dilate(erode(wallMask, 1), 1);
  for (let k = 0; k < N * N; k++) wallMask[k] = wallMask[k] && opened[k] ? 1 : 0;
}
const wallField = new Float32Array(N * N);
for (let k = 0; k < N * N; k++) wallField[k] = wallMask[k] ? Math.max(0.5, wallF[k]) : Math.min(0.49, wallF[k]);

function outline(F, label, comp) {
  const pad = 3, r0 = comp.r0 - pad, c0 = comp.c0 - pad, R = comp.r1 - comp.r0 + 1 + 2 * pad, C = comp.c1 - comp.c0 + 1 + 2 * pad;
  const v = (r, c) => {
    if (r <= 0 || c <= 0 || r >= R - 1 || c >= C - 1) return 0;
    const gr = r + r0, gc = c + c0;
    if (gr < 0 || gc < 0 || gr >= N || gc >= N) return 0;
    const l = label[idx(gr, gc)];
    if (l !== comp.id) return Math.min(0.49, l >= 0 ? 0 : F[idx(gr, gc)]);
    return F[idx(gr, gc)];
  };
  const iso = 0.5, pts = new Map();
  const edgePoint = (key, ra, ca, rb, cb) => {
    if (!pts.has(key)) {
      const a = v(ra, ca), b = v(rb, cb), t = Math.abs(b - a) < 1e-9 ? 0.5 : (iso - a) / (b - a);
      pts.set(key, [cx(ca + (cb - ca) * t + c0), cy(ra + (rb - ra) * t + r0)]);
    }
    return key;
  };
  const segs = [];
  for (let r = 0; r < R - 1; r++) for (let c = 0; c < C - 1; c++) {
    const a = v(r, c) >= iso, b = v(r, c + 1) >= iso, d = v(r + 1, c) >= iso, e = v(r + 1, c + 1) >= iso;
    const code = (a ? 1 : 0) | (b ? 2 : 0) | (e ? 4 : 0) | (d ? 8 : 0);
    if (code === 0 || code === 15) continue;
    const T = () => edgePoint(`h${r},${c}`, r, c, r, c + 1), B = () => edgePoint(`h${r + 1},${c}`, r + 1, c, r + 1, c + 1);
    const L = () => edgePoint(`v${r},${c}`, r, c, r + 1, c), Rt = () => edgePoint(`v${r},${c + 1}`, r, c + 1, r + 1, c + 1);
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
  const byPt = new Map();
  segs.forEach((s, i) => { for (const p of s) { if (!byPt.has(p)) byPt.set(p, []); byPt.get(p).push(i); } });
  const used = new Uint8Array(segs.length), loops = [];
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
function area(poly) { let a = 0; for (let i = 0; i < poly.length; i++) { const p = poly[i], q = poly[(i + 1) % poly.length]; a += p[0] * q[1] - q[0] * p[1]; } return a / 2; }
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
/** 制御点の間隔（ユニット）。 */
const CONTROL_STEP = 160;
/** これより小さい壁の塊は捨てる（25×25 ユニットのセル数 ≈ 直径 300 の岩）。 */
const MIN_WALL_CELLS = 90;
const half = (c) => {
  if (Math.abs(c.x - S / 2) < 60 && Math.abs(c.y - S / 2) < 60) return 'center';
  const s = c.x + c.y;
  return s < S - 1 || (Math.abs(s - S) <= 1 && c.x < c.y) ? 'blue' : 'red';
};
const WC = components(wallMask, MIN_WALL_CELLS);
const walls = [];
for (const c of WC.comps) {
  const side = half(c);
  if (side === 'red') continue;
  const raw = outline(wallField, WC.label, c);
  if (!raw || raw.length < 6) continue;
  walls.push({ side, n: c.n, x: c.x, y: c.y, poly: raw, control: resample(raw, CONTROL_STEP) });
}

// 川の輪郭
let river;
{
  const F = new Float32Array(N * N);
  // 縁をなめらかに（二値をぼかしてから 0.5 の等値線）
  for (let k = 0; k < N * N; k++) F[k] = riverMask[k];
  const kern = [0.0545, 0.2442, 0.4026, 0.2442, 0.0545];
  let s = F;
  for (let p = 0; p < 3; p++) {
    const tmp = new Float32Array(N * N), out = new Float32Array(N * N);
    for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) { let v = 0; for (let d = -2; d <= 2; d++) v += kern[d + 2] * s[idx(r, Math.min(N - 1, Math.max(0, c + d)))]; tmp[idx(r, c)] = v; }
    for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) { let v = 0; for (let d = -2; d <= 2; d++) v += kern[d + 2] * tmp[idx(Math.min(N - 1, Math.max(0, r + d)), c)]; out[idx(r, c)] = v; }
    s = out;
  }
  const lab = new Int32Array(N * N).fill(0);
  let r0 = N, r1 = 0, c0 = N, c1 = 0;
  for (let k = 0; k < N * N; k++) if (riverMask[k]) { const r = Math.floor(k / N), c = k % N; r0 = Math.min(r0, r); r1 = Math.max(r1, r); c0 = Math.min(c0, c); c1 = Math.max(c1, c); }
  const raw = outline(s, lab, { id: 0, r0, r1, c0, c1 });
  river = resample(raw, 200);
}
const inside = (p, poly) => { let c = false; for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) { const a = poly[i], b = poly[j]; if ((a[1] > p[1]) !== (b[1] > p[1]) && p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]) c = !c; } return c; };
const edgeDist = (p, poly) => { let d = Infinity; for (let i = 0; i < poly.length; i++) d = Math.min(d, segDist(p, poly[i], poly[(i + 1) % poly.length])); return d; };
// 宝殻蟹: 巨像の池の左上の外れ。川の中で岸から 250 以上の所まで池の中心へ寄せる
for (let t = 0; t <= 1; t += 0.02) {
  const q = [crab[0] + (colossus[0] - crab[0]) * t, crab[1] + (colossus[1] - crab[1]) * t];
  if (inside(q, river) && edgeDist(q, river) >= 250) { crab = q; break; }
}

// ---------- 4. 草むら（20 ユニット格子） ----------
const GB = 20, NB = S / GB, ib = (r, c) => r * NB + c;
const bushF = field(prob[BUSH], GB, 2, true);
const wallFB = field(prob[WALL], GB, 0, true);
const MIN_BUSH_CELLS = 120;
const bmask = new Uint8Array(NB * NB);
for (let r = 0; r < NB; r++) for (let c = 0; c < NB; c++) {
  const q = ib(r, c), p = [(c + 0.5) * GB, (r + 0.5) * GB];
  if (bushF[q] < 0.42 || wallFB[q] > 0.5) continue;
  if (p[0] < 0 || p[1] < 0) continue;
  if (laneDist(p) < 420) continue;  // レーンの帯（幅 約 650）には草むらを置かない
  if ([[600, 600], mir([600, 600]), bc, rc].some((b) => Math.hypot(p[0] - b[0], p[1] - b[1]) < 1700)) continue;
  // 川の中は置かない（巨像の池から中央の水路の岸だけ。岸から 100 内側まで許す）
  const rq = idx(Math.min(N - 1, Math.floor(p[1] / G)), Math.min(N - 1, Math.floor(p[0] / G)));
  if (riverMask[rq] && edgeDist(p, river) > 100) continue;
  bmask[q] = 1;
}
const bushes = [];
{
  const label = new Int32Array(NB * NB).fill(-1);
  for (let k = 0; k < NB * NB; k++) {
    if (!bmask[k] || label[k] >= 0) continue;
    const id = bushes.length, cells = [k], st = [k];
    label[k] = id;
    while (st.length) {
      const q = st.pop(), r = Math.floor(q / NB), c = q % NB;
      for (const [dr, dc] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const rr = r + dr, cc = c + dc;
        if (rr >= 0 && cc >= 0 && rr < NB && cc < NB) { const j = ib(rr, cc); if (bmask[j] && label[j] < 0) { label[j] = id; cells.push(j); st.push(j); } }
      }
    }
    let sx = 0, sy = 0;
    for (const q of cells) { sx += (q % NB + 0.5) * GB; sy += (Math.floor(q / NB) + 0.5) * GB; }
    bushes.push({ cells, n: cells.length, x: sx / cells.length, y: sy / cells.length });
  }
}
const mirrorB = (q) => NB * NB - 1 - q;
// 対角線をまたぐ草むらは自分の写像と重なるセルを除き（Blue 側のセルだけ）、それで小さくなったものは捨てる
const blueBushes = bushes.filter((b) => b.x + b.y < S)
  .map((b) => { const cells = b.cells.filter((q) => (q % NB) + Math.floor(q / NB) < NB - 1); return { ...b, cells, n: cells.length }; })
  .filter((b) => b.n >= MIN_BUSH_CELLS)
  .sort((a, b) => a.y - b.y || a.x - b.x);
const nBlue = blueBushes.length;
const mask = new Uint8Array(NB * NB);
blueBushes.forEach((b, k) => { for (const q of b.cells) { if (!mask[mirrorB(q)]) { mask[q] = k + 1; mask[mirrorB(q)] = k + nBlue + 1; } } });
if (nBlue * 2 > 254) throw new Error('草むらが多すぎる');

// ---------- 報告 ----------
console.log(`walls: ${walls.length}（blue ${walls.filter((w) => w.side === 'blue').length}, center ${walls.filter((w) => w.side === 'center').length}） 制御点 ${walls.reduce((a, w) => a + w.control.length, 0)}`);
console.log(`river: 制御点 ${river.length}、川のセル ${riverMask.reduce((a, v) => a + v, 0)}`);
console.log(`bushes: Blue ${nBlue}（セル ${blueBushes.map((b) => b.n).join(' ')}）`);
const R = (p) => p.map(Math.round);
for (const k of order) console.log(`  camp blue ${k} ${R(blueCamp[k])} lane ${Math.round(laneDist(blueCamp[k]))}`);
console.log(`  wyrm ${R(wyrm)} colossus ${R(colossus)} moss ${R(moss)} inRiver ${inside(moss, river)} crab ${R(crab)} inRiver ${inside(crab, river)}`);

// 確認画像: 設計図を地図の範囲で切り出し、壁（橙）・川（水色）・草むら（緑）の輪郭とキャンプを重ねる
{
  const D = 960, rgb = Buffer.alloc(D * D * 3), u = S / D;
  for (let y = 0; y < D; y++) for (let x = 0; x < D; x++) {
    const X = (x + 0.5) * u, Y = S - (y + 0.5) * u;
    const [px, py] = toPx(X, Y).map(Math.round);
    const i = (Math.min(H - 1, Math.max(0, py)) * W + Math.min(W - 1, Math.max(0, px))) * 3, o = (y * D + x) * 3;
    let c = [im.rgb[i] * 0.55, im.rgb[i + 1] * 0.55, im.rgb[i + 2] * 0.55];
    const qb = ib(Math.min(NB - 1, Math.floor(Y / GB)), Math.min(NB - 1, Math.floor(X / GB)));
    if (mask[qb]) c = [c[0] * 0.5 + 20, c[1] * 0.5 + 110, c[2] * 0.5 + 20];
    rgb[o] = c[0]; rgb[o + 1] = c[1]; rgb[o + 2] = c[2];
  }
  const plot = (X, Y, col, s = 1) => { const x = Math.round(X / u), y = Math.round((S - Y) / u); for (let dy = -s + 1; dy < s; dy++) for (let dx = -s + 1; dx < s; dx++) { const xx = x + dx, yy = y + dy; if (xx >= 0 && yy >= 0 && xx < D && yy < D) { const o = (yy * D + xx) * 3; rgb[o] = col[0]; rgb[o + 1] = col[1]; rgb[o + 2] = col[2]; } } };
  const line = (a, b, col) => { const n = Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / 6); for (let i = 0; i <= n; i++) plot(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n, col); };
  const ring = (poly, col) => { for (let i = 0; i < poly.length; i++) line(poly[i], poly[(i + 1) % poly.length], col); };
  for (const w of walls) for (const poly of w.side === 'center' ? [w.control] : [w.control, w.control.map(mir)]) ring(poly, [255, 140, 40]);
  ring(river, [80, 220, 255]);
  for (const L of lanes) for (let k = 1; k < L.length; k++) line(L[k - 1], L[k], [240, 240, 240]);
  for (const t of towers) plot(t[0], t[1], [255, 255, 255], 4);
  for (const [p] of campSpots) plot(p[0], p[1], [255, 60, 200], 5);
  plot(moss[0], moss[1], [255, 255, 0], 4); plot(crab[0], crab[1], [255, 255, 0], 4); plot(...mir(crab), [255, 255, 0], 4);
  writePNG(here('blueprint_debug.png'), D, D, rgb);
}

const rnd = (p) => p.map((v) => Math.round(v));
fs.writeFileSync(here('trace_stats.json'), JSON.stringify({
  source: 'blueprint',
  walls: walls.map((w) => ({ side: w.side, control: w.control.map(rnd) })),
  river: river.map(rnd),
  camps: [...order.map((k) => rnd(blueCamp[k])), ...order.map((k) => rnd(mir(blueCamp[k]))), rnd(wyrm), rnd(colossus), rnd(moss), rnd(crab), rnd(mir(crab))],
}));

if (process.argv.includes('--write')) {
  const bytes = [];
  let q = 0;
  while (q < NB * NB) {
    const v = mask[q];
    let n = 0;
    while (q < NB * NB && mask[q] === v) { q++; n++; }
    bytes.push(v);
    while (n >= 0x80) { bytes.push((n & 0x7f) | 0x80); n >>>= 7; }
    bytes.push(n);
  }
  const lines = Buffer.from(bytes).toString('base64').match(/.{1,120}/g);
  const names = blueBushes.map((b, k) => `    ///   ${k} / ${k + nBlue}: (${Math.round(b.x)}, ${Math.round(b.y)}) ${b.n} セル`).join('\n');
  fs.writeFileSync(here('../../Packages/VelstriaCore/Sources/VelstriaCore/Sim/MapSanctumBushGrid.swift'), `// 生成: tools/map_proto/blueprint_terrain.mjs --write（2026-10-16 のマップ設計図から）。手で編集しない。

extension BushMask {
    /// 設計図の草むら（standard の地図座標、${GB} ユニット四方の格子 ${NB}×${NB}）。値 = 草むらの番号 + 1。
    /// Blue 半面 ${nBlue} か所、Red 半面はその点対称（番号 + ${nBlue}）。中心の位置と大きさ:
${names}
    static let sanctum = BushMask(cell: ${GB}, cols: ${NB}, rows: ${NB}, runLengthBase64: """
${lines.map((l) => `        ${l}`).join('\n')}
        """)!
}
`);
  console.log('wrote Sim/MapSanctumBushGrid.swift');
}
