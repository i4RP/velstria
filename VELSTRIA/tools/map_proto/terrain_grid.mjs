// MLBB の現行マップ（Sanctum Island）のミニマップ原本を、20 ユニット四方（standard の地図座標。relayout では 16.2）の
// 細かい格子 600×600 に分類する: 外・壁・床・レーン・草むら・川・Blue 拠点・Red 拠点（2026-10-16）。
// 草むらは矩形で近似せず、この格子のまま VelstriaCore に入れる（MapSanctumBushGrid.swift → BushMask）。
//
// 入力: minimap_sanctum.png（MLBB Wiki の File:Minimap.png、512×512、アイコンなし。著作物なのでコミットしない。
//   取得方法は minimap_fit.mjs の先頭のコメント）。
// 画素 → 地図座標: x = −30 + 23.55·px、y = 12010 − 23.55·py（minimap_fit.mjs と同じ較正）。
//
// 1. 各画素の地形色を、最も近い 2 色の距離の比で 8 種類の確からしさに分ける（レーンの槍の装飾の光の周りは草むらにしない）。
// 2. 格子の中心で双線形に読み、点対称に平均（Blue 拠点 ⇔ Red 拠点を入れ替えて）し、σ = 1 セルでぼかして最大の種類を取る。
// 3. 草むら: オープニングで細い線（色の境目のにじみ）を落とし、俯瞰画像で読んだ草むら（bushes_mlbb.mjs）に重なる塊だけを残す。
//    Blue 半面の塊に番号を振り、Red 半面は点対称に写す（番号 + Blue の数）。拠点を囲む破線は壁にしない。
//
// 使い方: node terrain_grid.mjs [--write]
//   → terrain_grid.png（格子の確認画像。1 セル 4 px、種類ごとに色分け。コミットしない）
//   → --write で Packages/VelstriaCore/Sources/VelstriaCore/Sim/MapSanctumBushGrid.swift を書き換える
import fs from 'fs';
import zlib from 'zlib';
import { sourceBushes } from './bushes_mlbb.mjs';

const here = (f) => new URL(f, import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const S = 12000, G = 20, N = S / G;
const SX = 23.55, OX = -30, OY = 12010;
/** 残す草むらの最小の大きさ（セル）。 */
const MIN_BUSH_CELLS = 40;

// ---------- PNG ----------
function readPNG(file) {
  const b = fs.readFileSync(file);
  let p = 8, w = 0, h = 0, ct = 0;
  const idat = [];
  while (p < b.length) {
    const len = b.readUInt32BE(p), type = b.toString('ascii', p + 4, p + 8), data = b.subarray(p + 8, p + 8 + len);
    if (type === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); ct = data[9]; if (data[8] !== 8 || data[12] !== 0) throw new Error('unsupported'); }
    else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    p += 12 + len;
  }
  const ch = { 6: 4, 2: 3, 0: 1, 4: 2 }[ct];
  if (!ch) throw new Error('color type ' + ct);
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * ch, out = Buffer.alloc(w * h * 3);
  let prev = Buffer.alloc(stride), cur = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)];
    raw.copy(cur, 0, y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let x = 0; x < stride; x++) {
      const a = x >= ch ? cur[x - ch] : 0, up = prev[x], c = x >= ch ? prev[x - ch] : 0;
      let v = cur[x];
      if (f === 1) v += a; else if (f === 2) v += up; else if (f === 3) v += (a + up) >> 1;
      else if (f === 4) { const pp = a + up - c, pa = Math.abs(pp - a), pb = Math.abs(pp - up), pc = Math.abs(pp - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? up : c; }
      cur[x] = v & 255;
    }
    for (let x = 0; x < w; x++) {
      const o = (y * w + x) * 3;
      if (ch >= 3) { out[o] = cur[x * ch]; out[o + 1] = cur[x * ch + 1]; out[o + 2] = cur[x * ch + 2]; }
      else out[o] = out[o + 1] = out[o + 2] = cur[x * ch];
    }
    [prev, cur] = [cur, prev];
  }
  return { w, h, rgb: out };
}
function writePNG(file, w, h, rgb) {
  const crcT = [];
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; crcT[n] = c >>> 0; }
  const crc = (buf) => { let c = 0xffffffff; for (const x of buf) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) rgb.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3);
  const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 2;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]));
}

// ---------- 1. 地形色 → 8 種類の確からしさ ----------
const OUT = 0, WALL = 1, FLOOR = 2, LANE = 3, BUSH = 4, RIVER = 5, BLUE = 6, RED = 7, K = 8;
const NAMES = ['外', '壁', '床', 'レーン', '草むら', '川', 'Blue 拠点', 'Red 拠点'];
// 確認画像の色（種類ごとにはっきり違う色相・明るさ）
const COLORS = [
  [12, 14, 18], [150, 92, 44], [44, 58, 70], [176, 184, 192],
  [40, 210, 70], [0, 190, 235], [40, 100, 230], [225, 60, 52],
];
const PAL = [
  [WALL, [16, 36, 44]], [OUT, [6, 28, 20]], [WALL, [12, 34, 40]],
  [FLOOR, [60, 84, 92]], [LANE, [84, 108, 116]], [LANE, [116, 159, 174]],
  [BUSH, [84, 117, 136]], [BUSH, [111, 137, 149]], [BUSH, [104, 146, 157]],
  [RIVER, [20, 116, 138]], [BLUE, [28, 78, 114]], [BLUE, [36, 84, 112]],
  [RED, [84, 48, 56]], [RED, [84, 44, 48]],
];
const im = readPNG(here('./minimap_sanctum.png'));
const W = im.w, H = im.h;
const prob = new Float32Array(W * H * K);
{
  // レーンの槍の装飾の光（G ≥ 155）の周り 5 px は草むらの色に近いのでレーンにする
  const glow = new Uint8Array(W * H);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (im.rgb[(y * W + x) * 3 + 1] >= 155) {
    for (let dy = -5; dy <= 5; dy++) for (let dx = -5; dx <= 5; dx++) {
      const yy = y + dy, xx = x + dx;
      if (yy >= 0 && xx >= 0 && yy < H && xx < W && dx * dx + dy * dy <= 25) glow[yy * W + xx] = 1;
    }
  }
  for (let i = 0; i < W * H; i++) {
    const ds = PAL.map(([k, c]) => [Math.hypot(im.rgb[i * 3] - c[0], im.rgb[i * 3 + 1] - c[1], im.rgb[i * 3 + 2] - c[2]), k])
      .sort((a, b) => a[0] - b[0]);
    const [[a, ka], [b, kb]] = ds;
    const fix = (k) => (glow[i] && k === BUSH ? LANE : k);
    prob[i * K + fix(ka)] += (b + 1e-9) / (a + b + 2e-9);
    prob[i * K + fix(kb)] += (a + 1e-9) / (a + b + 2e-9);
  }
}

// ---------- 2. 格子へ ----------
const idx = (r, c) => r * N + c;
const cx = (c) => (c + 0.5) * G, cy = (r) => (r + 0.5) * G;
const mirrorCell = (k) => N * N - 1 - k;
let field = new Float32Array(N * N * K);
for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
  const fx = (cx(c) - OX) / SX - 0.5, fy = (OY - cy(r)) / SX - 0.5;
  const x0 = Math.floor(fx), y0 = Math.floor(fy), tx = fx - x0, ty = fy - y0;
  const o = idx(r, c) * K;
  for (const [px, py, wgt] of [[x0, y0, (1 - tx) * (1 - ty)], [x0 + 1, y0, tx * (1 - ty)], [x0, y0 + 1, (1 - tx) * ty], [x0 + 1, y0 + 1, tx * ty]]) {
    const i = Math.min(H - 1, Math.max(0, py)) * W + Math.min(W - 1, Math.max(0, px));
    for (let k = 0; k < K; k++) field[o + k] += wgt * prob[i * K + k];
  }
}
{
  // 点対称に平均（写像先の Blue 拠点は Red 拠点として数える）
  const sym = new Float32Array(N * N * K);
  const swap = (k) => (k === BLUE ? RED : k === RED ? BLUE : k);
  for (let q = 0; q < N * N; q++) {
    const m = mirrorCell(q);
    for (let k = 0; k < K; k++) sym[q * K + k] = (field[q * K + k] + field[m * K + swap(k)]) / 2;
  }
  // σ = 1 セルでぼかす（縦横に分けて）
  const kern = [0.0545, 0.2442, 0.4026, 0.2442, 0.0545];
  const tmp = new Float32Array(N * N * K);
  for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) for (let d = -2; d <= 2; d++) {
    const cc = Math.min(N - 1, Math.max(0, c + d));
    for (let k = 0; k < K; k++) tmp[idx(r, c) * K + k] += kern[d + 2] * sym[idx(r, cc) * K + k];
  }
  field = new Float32Array(N * N * K);
  for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) for (let d = -2; d <= 2; d++) {
    const rr = Math.min(N - 1, Math.max(0, r + d));
    for (let k = 0; k < K; k++) field[idx(r, c) * K + k] += kern[d + 2] * tmp[idx(rr, c) * K + k];
  }
}
const cls = new Uint8Array(N * N);
/** except の種類（1 つか配列）を除いて最も確からしい種類。 */
function best(q, except = -1) {
  const ex = Array.isArray(except) ? except : [except];
  let bk = 0, bv = -1;
  for (let k = 0; k < K; k++) if (!ex.includes(k) && field[q * K + k] > bv) { bv = field[q * K + k]; bk = k; }
  return bk;
}
for (let q = 0; q < N * N; q++) cls[q] = best(q);
// 拠点の色は拠点の角から 5200 以内だけ（川と壁の境目のにじみが拠点の色に近くなる点を除く）
for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
  const q = idx(r, c);
  if (cls[q] === BLUE && Math.hypot(cx(c), cy(r)) > 5200) cls[q] = best(q, BLUE);
  if (cls[q] === RED && Math.hypot(S - cx(c), S - cy(r)) > 5200) cls[q] = best(q, RED);
}

// ---------- 連結成分（8 近傍） ----------
function components(mask) {
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
    let sx = 0, sy = 0;
    for (const q of cells) { sx += cx(q % N); sy += cy(Math.floor(q / N)); }
    comps.push({ id, cells, n: cells.length, x: sx / cells.length, y: sy / cells.length });
  }
  return { label, comps };
}

// 拠点を囲む破線（壁の色の小さな塊が拠点の角から一定の距離に並ぶ）は壁にしない
{
  const { comps } = components(Uint8Array.from(cls, (v) => (v === WALL ? 1 : 0)));
  let n = 0;
  for (const c of comps) {
    // 破線は拠点の角から 3900 前後（塊 1 つ 900 セル前後）。いちばん近い本物の壁は 4800 先
    if (c.n > 1200) continue;
    if (![[0, 0], [S, S]].some(([bx, by]) => { const d = Math.hypot(c.x - bx, c.y - by); return d > 3600 && d < 4300; })) continue;
    for (const q of c.cells) cls[q] = best(q, [WALL, OUT, FLOOR, BUSH]);
    n++;
  }
  console.log(`拠点の破線: ${n} 個を壁から外した`);
}

// ---------- 3. 草むら ----------
const bushRaw = Uint8Array.from(cls, (v) => (v === BUSH ? 1 : 0));
// オープニング（3×3 で削ってから戻す）: 色の境目にできる 2 セル以下の細い線を落とす
const morph = (src, keep) => {
  const out = new Uint8Array(N * N);
  for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
    let all = true, any = false;
    for (let dr = -1; dr <= 1; dr++) for (let dc = -1; dc <= 1; dc++) {
      const rr = r + dr, cc = c + dc;
      const v = rr >= 0 && cc >= 0 && rr < N && cc < N ? src[idx(rr, cc)] : 0;
      all = all && v === 1; any = any || v === 1;
    }
    out[idx(r, c)] = (keep ? any : all) ? 1 : 0;
  }
  return out;
};
const opened = morph(morph(bushRaw, false), true);
for (let q = 0; q < N * N; q++) opened[q] = opened[q] && bushRaw[q] ? 1 : 0;
const srcRects = sourceBushes.flatMap(([name, ...rs], order) => rs.map((r) => ({ name, order, r })));
const srcAll = srcRects.concat(srcRects.map(({ name, order, r }) => ({ name, order, r: [S - r[2], S - r[3], S - r[0], S - r[1]] })));
const { comps: bushComps } = components(opened);
const blueBushes = [];
const keep = new Uint8Array(N * N);
for (const c of bushComps) {
  if (c.n < MIN_BUSH_CELLS) continue;
  const hit = srcAll.find(({ r }) => c.cells.some((q) => { const x = cx(q % N), y = cy(Math.floor(q / N)); return x >= r[0] && x <= r[2] && y >= r[1] && y <= r[3]; }));
  if (!hit) continue;
  for (const q of c.cells) keep[q] = 1;
  if (c.x + c.y < S) blueBushes.push({ ...c, name: hit.name, order: hit.order });
}
// Red 半面の塊が Blue の写像と一致するかの確認（点対称に平均したので、ずれるのは同点のセルだけのはず）
{
  let diff = 0;
  for (let q = 0; q < N * N; q++) if (keep[q] !== keep[mirrorCell(q)]) diff++;
  if (diff) console.log(`注意: 草むらの点対称のずれ ${diff} セル（Blue 側に合わせる）`);
}
blueBushes.sort((a, b) => a.order - b.order || a.x - b.x || a.y - b.y);
const nBlue = blueBushes.length;
const mask = new Uint8Array(N * N);
blueBushes.forEach((b, k) => {
  for (const q of b.cells) {
    if (mask[mirrorCell(q)]) throw new Error(`草むら ${k} が自分の写像と重なる`);
    mask[q] = k + 1;
    mask[mirrorCell(q)] = k + nBlue + 1;
  }
});
if (nBlue * 2 > 254) throw new Error('草むらが多すぎる');
// 種類の格子を最終の草むらに合わせる（捨てた草むらの色は 2 番目の種類へ）
for (let q = 0; q < N * N; q++) {
  if (mask[q]) cls[q] = BUSH;
  else if (cls[q] === BUSH) cls[q] = best(q, BUSH);
}

// 確認画像だけ: 4 近傍のどれとも違う 1 セルだけの種類は、周りで最も多い種類にする（にじみの点。草むらのセルは変えない）
{
  const fixed = cls.slice();
  for (let r = 1; r < N - 1; r++) for (let c = 1; c < N - 1; c++) {
    const q = idx(r, c), nb = [cls[q - 1], cls[q + 1], cls[q - N], cls[q + N]];
    if (mask[q] || nb.includes(cls[q])) continue;
    const tally = new Map();
    for (const v of nb) tally.set(v, (tally.get(v) || 0) + 1);
    const v = [...tally.entries()].sort((a, b) => b[1] - a[1])[0][0];
    if (v !== BUSH) fixed[q] = v;
  }
  cls.set(fixed);
}

// ---------- 報告 ----------
const counts = new Array(K).fill(0);
for (let q = 0; q < N * N; q++) counts[cls[q]]++;
console.log(`格子 ${N}×${N}（1 セル ${G} ユニット）`);
NAMES.forEach((n, k) => console.log(`  ${n}: ${counts[k]} セル（${(counts[k] * G * G / 1e4).toFixed(0)} m²）`));
console.log(`草むら: Blue ${nBlue} + Red ${nBlue}`);
const bushInfo = [];
for (let id = 0; id < nBlue * 2; id++) {
  let n = 0, r0 = N, r1 = -1, c0 = N, c1 = -1;
  for (let q = 0; q < N * N; q++) if (mask[q] === id + 1) {
    n++; const r = Math.floor(q / N), c = q % N;
    r0 = Math.min(r0, r); r1 = Math.max(r1, r); c0 = Math.min(c0, c); c1 = Math.max(c1, c);
  }
  bushInfo.push({ id, n, rect: [c0 * G, r0 * G, (c1 + 1) * G, (r1 + 1) * G] });
}
blueBushes.forEach((b, k) => console.log(`  ${k}: ${b.name} ${b.n} セル（${(b.n * G * G / 1e4).toFixed(1)} m²） 範囲 ${bushInfo[k].rect.join(', ')}`));

// ---------- 確認画像（全体: 1 セル 4 px = 3 px の塗り + 1 px の格子線。拡大: 1 セル 8 px） ----------
/** 列 c0..c1・行 r0..r1 のセルを 1 セル P px で描く（上が北）。 */
function renderGrid(file, P, c0, c1, r0, r1) {
  const Wd = (c1 - c0 + 1) * P, Hd = (r1 - r0 + 1) * P, rgb = Buffer.alloc(Wd * Hd * 3);
  for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) {
    const q = idx(r, c), col = COLORS[cls[q]];
    // 草むらの縁のセルは少し暗く（隣り合う草むらの境目が分かるように）
    let edge = false;
    if (mask[q]) {
      for (const [dr, dc] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const rr = r + dr, cc = c + dc;
        if (rr < 0 || cc < 0 || rr >= N || cc >= N || mask[idx(rr, cc)] !== mask[q]) edge = true;
      }
    }
    const top = (r1 - r) * P, left = (c - c0) * P;
    for (let y = 0; y < P; y++) for (let x = 0; x < P; x++) {
      const line = x === P - 1 || y === P - 1;
      const f = (edge ? 0.62 : 1) * (line ? 0.72 : 1);
      const o = ((top + y) * Wd + left + x) * 3;
      rgb[o] = col[0] * f; rgb[o + 1] = col[1] * f; rgb[o + 2] = col[2] * f;
    }
  }
  writePNG(here(file), Wd, Hd, rgb);
  console.log(`${file} ${Wd}×${Hd}`);
}
renderGrid('./terrain_grid.png', 4, 0, N - 1, 0, N - 1);
// 拡大: Blue 側の川の円と中央の帯のあたり（3000〜6000 × 6000〜9000）
renderGrid('./terrain_grid_zoom.png', 8, 150, 299, 300, 449);

// ---------- Swift ----------
if (process.argv.includes('--write')) {
  // 行（y の小さい方から）を順につないだ値の連なりを、[値 1 バイト][長さ LEB128] の組にして base64 にする
  const bytes = [];
  let q = 0;
  while (q < N * N) {
    const v = mask[q];
    let n = 0;
    while (q < N * N && mask[q] === v) { q++; n++; }
    bytes.push(v);
    while (n >= 0x80) { bytes.push((n & 0x7f) | 0x80); n >>>= 7; }
    bytes.push(n);
  }
  const b64 = Buffer.from(bytes).toString('base64');
  const lines = b64.match(/.{1,120}/g);
  const names = blueBushes.map((b, k) => `    ///   ${k} / ${k + nBlue}: ${b.name}（${b.n} セル）`).join('\n');
  const swift = `// 生成: tools/map_proto/terrain_grid.mjs --write（MLBB Wiki の File:Minimap.png = Sanctum Island のミニマップ原本から）。
// 手で編集しない。

extension BushMask {
    /// MLBB の現行マップの草むら（standard の地図座標、${G} ユニット四方の格子 ${N}×${N}）。値 = 草むらの番号 + 1。
    /// Blue 半面 ${nBlue} か所、Red 半面はその点対称（番号 + ${nBlue}）。
${names}
    static let sanctum = BushMask(cell: ${G}, cols: ${N}, rows: ${N}, runLengthBase64: """
${lines.map((l) => `        ${l}`).join('\n')}
        """)!
}
`;
  const out = here('../../Packages/VelstriaCore/Sources/VelstriaCore/Sim/MapSanctumBushGrid.swift');
  fs.writeFileSync(out, swift);
  console.log(`wrote ${out}（${bytes.length} バイト、base64 ${b64.length} 文字）`);
}
