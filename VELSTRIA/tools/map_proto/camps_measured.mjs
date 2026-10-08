import fs from 'fs';
const CX = 537.25, CY = 435.5, U = 12000 / 868, DY = 2; // アイコンの中心は基準点より約 2px 上（点対称ペアの y 和から）
const toMap = (x, y) => [Math.round(6000 + (x - CX) * U), Math.round(6000 - (y + DY - CY) * U)];
const blue = { // 西 3 + 南 4
  blueSentinel: [325.7, 451.2], redSentinel: [509, 677.5],
  small: [[247.5, 374.1], [289.7, 387.8], [544.1, 637.2], [644.3, 705.8], [583.9, 693.8]],
};
const red = { // 東 3 + 北 4
  blueSentinel: [760.7, 417.3], redSentinel: [564, 190],
  small: [[833.5, 494.4], [784.9, 479.2], [530.4, 229.5], [436.9, 154.4], [490.8, 173.3]],
};
const fmt = (s) => ({ blueSentinel: toMap(...s.blueSentinel), redSentinel: toMap(...s.redSentinel), small: s.small.map((p) => toMap(...p)) });
console.log(JSON.stringify({ blue: fmt(blue), red: fmt(red), river: toMap(443.74, 340.65) }, null, 1));
