// MLBB から読んだ草むら（bushes_mlbb.mjs）と、ミニマップから当てはめた壁（shapes.json）の重なりを解消する。
// どちらも誤差を持つ近似なので、重なった深さを半分ずつ譲る（壁の辺を下げる・円の半径を縮める / 草むらの辺を下げる）。
// 角の壁（左上・右下）は MLBB の壁の線（斜めのレーン中心から約 950 外側）に合わせて置き直す。
// 使い方: node resolve_bushes.mjs [--write]  → walls_fit.json（譲る前の壁）と bushes_mlbb.mjs から shapes.json の obstacles / corner / brushes / brushGroups を作り直す
import fs from 'fs';
import { sourceBushes } from './bushes_mlbb.mjs';

const S = 12000;
const shapes = JSON.parse(fs.readFileSync(new URL('./shapes.json', import.meta.url)));
// 壁は譲る前の当てはめ結果（fitwalls.mjs の出力を固定したもの）から毎回始める（何度実行しても同じ結果）
const fitted = JSON.parse(fs.readFileSync(new URL('./walls_fit.json', import.meta.url))).obstacles;
// 左上の角: 斜めのレーン（y − x = 8700）から外側へ。円の縁が y − x = 10000 の線に来るよう中心は 10707 の線上。
// 最後の 1 つは、円の列と地図の角の間に残る歩ける隙間を埋める。
const corner = [[-350, 10357], [150, 10857], [650, 11357], [1150, 11857], [1650, 12357], [100, 11900]].map(([x, y]) => ({ t: 'C', v: [x, y, 500] }));
// 手で決めた調整（画像で岩と草むらの境目を確かめた所）
//  - 環状の岩の上の小円 (8930,2130) r100 は草むらの中にあるので外す
//  - 祠（ドーム）の円 (4130,3030) は MLBB の祠の大きさ（半径 約 250）に合わせる
//  - 左下の岩の右: 岩（壁 0）の東端を 1940 に、草むらは岩の角の円 (2030,4230) を避けて置く
const manualRemove = [[8930, 2130, 100]];
const src = fitted
  .filter((o) => !manualRemove.some((m) => o.t === 'C' && o.v[0] === m[0] && o.v[1] === m[1] && o.v[2] === m[2]))
  .map((o) => ({ t: o.t, v: [...o.v] }));
for (const o of src) {
  if (o.t === 'C' && o.v[0] === 4130 && o.v[1] === 3030) o.v[2] = 250;
  if (o.t === 'R' && o.v.join() === '1400,4250,2050,5250') o.v[2] = 1940;
}
const bushes = sourceBushes.flatMap(([name, ...rects], g) => rects.map((r) => ({ name, g, r: [...r] })));

const mirR = (r) => [S - r[2], S - r[3], S - r[0], S - r[1]];
const mirO = (o) => o.t === 'R' ? { t: 'R', v: mirR(o.v) } : { t: 'C', v: [S - o.v[0], S - o.v[1], o.v[2]] };
// 全体の壁（source + 写像 + 角 + 角の写像）。i → [source の添字 or -1（角）, 写像か]
function allWalls() {
  const out = [];
  src.forEach((o, i) => { out.push({ o, i, m: false }); out.push({ o: mirO(o), i, m: true }); });
  corner.forEach((o) => { out.push({ o, i: -1, m: false }); out.push({ o: mirO(o), i: -1, m: true }); });
  return out;
}
// 矩形 r と壁 o の重なりの深さと、解消する向き（r 側の辺）
function overlap(r, o) {
  if (o.t === 'R') {
    const [a0, b0, a1, b1] = o.v;
    if (!(r[0] < a1 && a0 < r[2] && r[1] < b1 && b0 < r[3])) return null;
    // r のどの辺を動かすと最小で離れるか（r.minX を a1 へ / r.maxX を a0 へ / ...）
    const cand = [[0, a1 - r[0]], [2, r[2] - a0], [1, b1 - r[1]], [3, r[3] - b0]];
    cand.sort((p, q) => p[1] - q[1]);
    return { side: cand[0][0], depth: cand[0][1] };
  }
  const [cx, cy, rad] = o.v;
  const px = Math.min(Math.max(cx, r[0]), r[2]), py = Math.min(Math.max(cy, r[1]), r[3]);
  const d = Math.hypot(px - cx, py - cy);
  if (d >= rad) return null;
  // 円の中心が矩形の外側にある向きの辺を動かす（中心が内側なら最も近い辺）
  const cand = [[0, cx + rad - r[0]], [2, r[2] - (cx - rad)], [1, cy + rad - r[1]], [3, r[3] - (cy - rad)]];
  cand.sort((p, q) => p[1] - q[1]);
  return { side: cand[0][0], depth: Math.min(cand[0][1], rad - d), circle: true };
}
const moveSide = (r, side, amt) => { const c = [...r]; if (side < 2) c[side] += amt; else c[side] -= amt; return c; };
const opp = { 0: 2, 2: 0, 1: 3, 3: 1 };

const log = [];
for (let iter = 0; iter < 200; iter++) {
  let changed = false;
  for (const b of bushes) {
    for (const w of allWalls()) {
      const ov = overlap(b.r, w.o);
      if (!ov) continue;
      changed = true;
      const half = Math.ceil(ov.depth / 2 / 10) * 10 + 10;
      // 壁側を譲る（角の円は置き直し済みなので譲らない）
      if (w.i >= 0) {
        const o = src[w.i];
        if (o.t === 'R') {
          // 壁の辺: 草むらの side と向かい合う辺（写像なら反転）
          let ws = opp[ov.side];
          if (w.m) ws = opp[ws];
          const v = moveSide(o.v, ws, half);
          if (v[2] - v[0] >= 150 && v[3] - v[1] >= 150) { log.push(`壁 ${w.i} ${o.v} → ${v}`); o.v = v; }
        } else if (ov.circle) {
          const nr = o.v[2] - half;
          if (nr >= 80) { log.push(`壁 ${w.i} 円 r ${o.v[2]} → ${nr}`); o.v[2] = nr; }
        }
      }
      // 草むら側も譲る（まだ重なっていれば、離れるまで）
      let r2 = moveSide(b.r, ov.side, half);
      const ov2 = overlap(r2, allWalls().find((x) => x.i === w.i && x.m === w.m && (w.i >= 0 || x.o === w.o))?.o ?? w.o);
      if (ov2 && ov2.side === ov.side) r2 = moveSide(r2, ov.side, ov2.depth + 10);
      if (r2[2] - r2[0] < 150 || r2[3] - r2[1] < 150) { log.push(`✗ 草むら ${b.name} ${b.r} が小さくなりすぎる`); continue; }
      b.r = r2;
    }
  }
  if (!changed) break;
}
// 草むら同士の重なり
for (let i = 0; i < bushes.length; i++) for (let j = 0; j < bushes.length; j++) {
  const a = bushes[i].r, b2 = j === i ? null : bushes[j].r;
  for (const q of [b2, mirR(bushes[j].r)]) if (q && a[0] < q[2] && q[0] < a[2] && a[1] < q[3] && q[1] < a[3]) log.push(`草むら同士が重なる ${i} ${j}`);
}
log.forEach((l) => console.log(l));
for (const b of bushes) console.log(b.name.padEnd(16), b.r.join(','));
if (process.argv.includes('--write')) {
  shapes.obstacles = src;
  shapes.corner = corner;
  shapes.brushes = bushes.map((b) => b.r);
  shapes.brushGroups = bushes.map((b) => b.g);
  shapes.brushNames = sourceBushes.map(([name]) => name);
  fs.writeFileSync(new URL('./shapes.json', import.meta.url), JSON.stringify(shapes));
  console.log('shapes.json を更新');
}
