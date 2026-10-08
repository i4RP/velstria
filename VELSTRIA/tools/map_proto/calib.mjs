// 画像 1 のミニマップ: ピクセル → 地図座標（点対称の中心と枠の幅で較正）と、点対称ペアのずれを出す。
const CX = 537.25, CY = 435.5, U = 12000 / 868;
const toMap = (x, y) => [6000 + (x - CX) * U, 6000 - (y - CY) * U];
const mir = (p) => [12000 - p[0], 12000 - p[1]];
const r = (p) => p.map((v) => Math.round(v));
const pairs = {
  // 塔: blue px, red px
  'top outer': [[138.5, 233.5], [936.5, 637.5]],
  'top inner': [[144, 411.5], [931.5, 461]],
  'top base': [[149.5, 640.5], [925, 230.5]],
  'mid base': [[277, 695.5], [798, 174.5]],
  'mid inner': [[348.5, 601.5], [726, 269.5]],
  'mid outer': [[440, 508.5], [634.5, 362.5]],
  'bot inner': [[495.5, 835.5], [579, 35.5]],
  'bot outer': [[743.5, 828.5], [331.5, 42.5]],
  'bot base': [[333.2, 823.9], [741.3, 47.1]],
  // キャンプ: blue 側（西・南）, red 側（東・北）
  'W green ↔ E green': [[247.5, 374.1], [833.5, 494.4]],
  'W diamond ↔ E diamond': [[289.7, 387.8], [784.9, 479.2]],
  'W buff ↔ E buff': [[325.7, 451.2], [760.7, 417.3]],
  'S green(near buff) ↔ N green': [[544.1, 637.2], [530.4, 229.5]],
  'S green(far) ↔ N green': [[644.3, 705.8], [436.9, 154.4]],
  'S diamond ↔ N diamond': [[583.9, 693.8], [490.8, 173.3]],
  'S buff ↔ N buff': [[509, 677.5], [564, 190]],
};
for (const [k, [b, rd]] of Object.entries(pairs)) {
  const mb = toMap(...b), mr = mir(toMap(...rd));
  const avg = [(mb[0] + mr[0]) / 2, (mb[1] + mr[1]) / 2];
  const d = Math.hypot(mb[0] - mr[0], mb[1] - mr[1]);
  console.log(k.padEnd(30), 'blue', r(mb).join(','), ' red→', r(mr).join(','), ' avg', r(avg).join(','), ' Δ', Math.round(d));
}
const extra = { 'river creature': [443.74, 340.65], 'lord(bbox)': [375, 266.5], 'turtle(bbox)': [702.5, 614.5] };
for (const [k, p] of Object.entries(extra)) console.log(k.padEnd(30), r(toMap(...p)).join(','));
