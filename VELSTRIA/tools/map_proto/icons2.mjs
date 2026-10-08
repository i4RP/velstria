// 使い方: node icons2.mjs icons_raw_4.csv  — タワー（青・赤・金のアイコン）とキャンプ（緑・水色・桃）を抽出して地図座標へ。
import fs from 'fs';
const file = process.argv[2] || 'icons_raw.csv';
const rows = fs.readFileSync(file, 'utf8').trim().split(/\r?\n/).map((l) => { const [c, n, cx, cy, x0, y0, x1, y1] = l.split(','); return { c, n: +n, cx: +cx, cy: +cy, x0: +x0, y0: +y0, x1: +x1, y1: +y1 }; });
const gap = (a, b) => Math.max(0, Math.max(a.x0 - b.x1, b.x0 - a.x1), Math.max(a.y0 - b.y1, b.y0 - a.y1));
function cluster(items, g) {
  const grp = items.map((_, i) => i); const f = (i) => (grp[i] === i ? i : (grp[i] = f(grp[i])));
  for (let i = 0; i < items.length; i++) for (let j = i + 1; j < items.length; j++) if (gap(items[i], items[j]) <= g) grp[f(i)] = f(j);
  const m = new Map(); items.forEach((it, i) => { const k = f(i); (m.get(k) || m.set(k, []).get(k)).push(it); });
  return [...m.values()].map((g2) => { const o = { x0: Math.min(...g2.map((a) => a.x0)), y0: Math.min(...g2.map((a) => a.y0)), x1: Math.max(...g2.map((a) => a.x1)), y1: Math.max(...g2.map((a) => a.y1)), n: g2.reduce((s, a) => s + a.n, 0), parts: g2.length, classes: [...new Set(g2.map((a) => a.c))].join('+') }; o.bx = (o.x0 + o.x1) / 2; o.by = (o.y0 + o.y1) / 2; return o; });
}
const CX = 537.25, CY = 435.5, U = 12000 / 868;
const toMap = (x, y) => [Math.round(6000 + (x - CX) * U), Math.round(6000 - (y - CY) * U)];
const towers = cluster(rows.filter((r) => ['blue', 'cyan', 'gold', 'red'].includes(r.c) && r.n >= 20), 4)
  .filter((g) => g.n > 1000 && g.x1 - g.x0 >= 50 && g.x1 - g.x0 <= 70 && g.y1 - g.y0 >= 50 && g.y1 - g.y0 <= 75);
console.log(file, 'towers:', towers.length);
towers.sort((a, b) => a.bx - b.bx).forEach((g) => console.log(' ', g.bx.toFixed(1), g.by.toFixed(1), g.classes.padEnd(18), 'n', g.n, 'bbox', g.x0, g.y0, g.x1, g.y1, '=>', toMap(g.bx, g.by).join(',')));
const small = rows.filter((r) => ['green', 'cyan'].includes(r.c) && r.n >= 200 && r.n <= 450 && !towers.some((t) => r.cx >= t.x0 - 2 && r.cx <= t.x1 + 2 && r.cy >= t.y0 - 2 && r.cy <= t.y1 + 2));
console.log('camp dots/diamonds:'); small.forEach((r) => console.log(' ', r.c.padEnd(6), r.cx.toFixed(2), r.cy.toFixed(2), 'n', r.n, '=>', toMap(r.cx, r.cy).join(',')));
console.log('pink:'); rows.filter((r) => r.c === 'pink' && r.n >= 300).forEach((r) => console.log(' ', r.cx.toFixed(2), r.cy.toFixed(2), 'n', r.n, 'bbox', r.x0, r.y0, r.x1, r.y1));
