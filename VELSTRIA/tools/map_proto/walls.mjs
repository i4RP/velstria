// rgb4.txt（x: 95.., y: 0..）から壁（暗い塊）の候補を取り出す試み。
import fs from 'fs';
const rows = fs.readFileSync('rgb4.txt', 'utf8').trim().split(/\r?\n/).map((l) => l.split(';').filter(Boolean).map((s) => s.split(',').map(Number)));
const H = rows.length, W = rows[0].length, X0 = 95;
const lum = rows.map((r) => r.map(([R, G, B]) => 0.3 * R + 0.59 * G + 0.11 * B));
// ヒストグラム（内側の領域: 画像座標 x 200..860, y 100..760）
const hist = {}; for (let y = 100; y < 760; y++) for (let x = 200 - X0; x < 860 - X0; x++) { const k = Math.round(lum[y][x] / 8) * 8; hist[k] = (hist[k] || 0) + 1; }
console.log(Object.entries(hist).sort((a, b) => a[0] - b[0]).map(([k, v]) => k + ':' + v).join(' '));
const CX = 537.25, CY = 435.5, U = 12000 / 868;
const isDark = (x, y) => lum[y][x - X0] < 68;
const lines = [];
const CELL = 150; // units
for (let Y = 11850; Y > 0; Y -= CELL) {
  let line = '';
  for (let X = 75; X < 12000; X += CELL) {
    const px = Math.round(CX + (X - 6000) / U), py = Math.round(CY - (Y - 6000) / U);
    // セル内の暗い画素の割合（3×3 サンプル）
    let dark = 0, n = 0;
    for (let dy = -3; dy <= 3; dy += 3) for (let dx = -3; dx <= 3; dx += 3) { const x = px + dx, y = py + dy; if (x - X0 < 0 || x - X0 >= W || y < 0 || y >= H) continue; n++; if (isDark(x, y)) dark++; }
    line += n === 0 ? ' ' : dark >= 5 ? '#' : dark >= 3 ? '+' : '.';
  }
  lines.push(line);
}
console.log(lines.join('\n'));
