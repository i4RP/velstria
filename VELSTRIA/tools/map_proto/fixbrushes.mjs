// 壁に重なる草むらを、近くの空いた場所へずらす（SHAPES=./shapes_fit.json で壁を指定）。結果は shapes_fit.json に書く。
import fs from 'fs';
const file = process.env.SHAPES || './shapes_fit.json';
const sh = JSON.parse(fs.readFileSync(file));
const S = 12000;
const rectMir = (r) => [S - r[2], S - r[3], S - r[0], S - r[1]];
const obsRects = (o) => o.t === 'R' ? { rect: o.v } : { circle: o.v };
const ov = (b, o) => o.t === 'R' ? (b[0] < o.v[2] && o.v[0] < b[2] && b[1] < o.v[3] && o.v[1] < b[3])
  : Math.hypot(Math.min(Math.max(o.v[0], b[0]), b[2]) - o.v[0], Math.min(Math.max(o.v[1], b[1]), b[3]) - o.v[1]) < o.v[2];
const mirOb = (o) => o.t === 'R' ? { t: 'R', v: rectMir(o.v) } : { t: 'C', v: [S - o.v[0], S - o.v[1], o.v[2]] };
const all = [...sh.obstacles, ...sh.corner].flatMap((o) => [o, mirOb(o)]);
const hits = (b) => all.some((o) => ov(b, o)) || sh.brushes.some((c) => c !== b && (ov(b, { t: 'R', v: c }) === true) ) ;
const rectHit = (a, b) => a[0] < b[2] && b[0] < a[2] && a[1] < b[3] && b[1] < a[3];
const clash = (b, skip) => all.some((o) => ov(b, o)) || sh.brushes.some((c) => c !== skip && (rectHit(b, c) || rectHit(b, rectMir(c))));
let moved = 0;
sh.brushes = sh.brushes.map((b) => {
  if (!clash(b, b)) return b;
  for (let r = 100; r <= 900; r += 100) for (let a = 0; a < 16; a++) { const dx = Math.round(r * Math.cos(a * Math.PI / 8) / 50) * 50, dy = Math.round(r * Math.sin(a * Math.PI / 8) / 50) * 50; const nb = [b[0] + dx, b[1] + dy, b[2] + dx, b[3] + dy]; if (nb[0] > 900 && nb[2] < 11100 && nb[1] > 400 && nb[3] < 11600 && !clash(nb, b)) { moved++; return nb; } }
  throw new Error('no place for brush ' + b);
});
fs.writeFileSync(file, JSON.stringify(sh));
console.log('moved', moved);
