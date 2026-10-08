// icons_raw.csv（icons.ps1 の出力）からアイコンを組み立て、地図座標へ変換する。
import fs from 'fs';
const rows = fs.readFileSync('icons_raw.csv', 'utf8').trim().split(/\r?\n/).map((l) => { const [c, n, cx, cy, x0, y0, x1, y1] = l.split(','); return { c, n: +n, cx: +cx, cy: +cy, x0: +x0, y0: +y0, x1: +x1, y1: +y1 }; });
const gap = (a, b) => Math.max(0, Math.max(a.x0 - b.x1, b.x0 - a.x1), Math.max(a.y0 - b.y1, b.y0 - a.y1));
function cluster(items, g) {
  const grp = items.map((_, i) => i);
  const f = (i) => (grp[i] === i ? i : (grp[i] = f(grp[i])));
  for (let i = 0; i < items.length; i++) for (let j = i + 1; j < items.length; j++) if (gap(items[i], items[j]) <= g) grp[f(i)] = f(j);
  const m = new Map(); items.forEach((it, i) => { const k = f(i); (m.get(k) || m.set(k, []).get(k)).push(it); });
  return [...m.values()].map((g2) => ({ x0: Math.min(...g2.map((a) => a.x0)), y0: Math.min(...g2.map((a) => a.y0)), x1: Math.max(...g2.map((a) => a.x1)), y1: Math.max(...g2.map((a) => a.y1)), n: g2.reduce((s, a) => s + a.n, 0), parts: g2.length }));
}
const box = (g) => ({ ...g, bx: (g.x0 + g.x1) / 2, by: (g.y0 + g.y1) / 2 });
const FX0 = 102.5, FX1 = 970.5, FY1 = 869, W = FX1 - FX0, FY0 = FY1 - W;
const U = 12000 / W;
const toMap = (bx, by) => [(bx - FX0) * U, (FY1 - by) * U];
const blueTower = cluster(rows.filter((r) => r.c === 'blue' || (r.c === 'cyan' && r.n < 320)), 4).filter((g) => g.n > 600 && g.parts >= 3);
const redTower = cluster(rows.filter((r) => r.c === 'red'), 4).filter((g) => g.n > 1500 && g.x1 - g.x0 < 70);
const out = {};
out.blueTowers = blueTower.map(box).map((g) => ({ ...g, m: toMap(g.bx, g.by).map(Math.round) }));
out.redTowers = redTower.map(box).map((g) => ({ ...g, m: toMap(g.bx, g.by).map(Math.round) }));
console.log('scale u/px', U.toFixed(3), 'frame y0', FY0);
for (const k of ['blueTowers', 'redTowers']) { console.log(k); out[k].sort((a, b) => a.bx - b.bx).forEach((g) => console.log(' ', g.bx.toFixed(1), g.by.toFixed(1), 'n', g.n, 'parts', g.parts, 'bbox', g.x0, g.y0, g.x1, g.y1, '=>', g.m.join(','))); }
