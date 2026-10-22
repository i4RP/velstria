// blueprint_terrain.mjs（2026-10-16〜。旧: trace_terrain.mjs）の結果（trace_stats.json）を、遊ぶ地図（relayout、standard の 0.81 倍）の縮尺で
// MapDefinition.validationIssues と同じ規則で調べ、キャンプを壁に掛からない最寄りの位置へ寄せて、
// Sim/MapSanctumTerrain.swift を書く（--write）。
// 壁はスプライン（閉じた centripetal Catmull-Rom を 1 mm の精度で折れ線に）で多角形にしてから測る（Swift の Obstacle.smoothPolygon と同じ）。
//
// 使い方: node terrain_swift.mjs [--write]
import fs from 'fs';

const K = 0.81, S = 12000;
/** スプラインを折れ線にする精度（relayout のユニット = cm）: 弦と曲線のずれ 0.1（1 mm）以下・弦の長さ 50 以下（Swift の Spline.closedCatmullRom と同じ）。 */
const TOLERANCE = 0.1, MAX_SEGMENT = 50;
/** 川は大きく判定も描画も細かさが要らないので粗く（弦のずれ 2・弦 120）。Swift の sanctumRiverTolerance と同じ。 */
const RIVER_TOLERANCE = 2, RIVER_MAX_SEGMENT = 120;
/** relayout の規則（MapDefinition.validationIssues）。拠点の周りは MLBB の拠点を囲む壁が入るよう 1600（2026-10-16）。 */
const RULE = { lane: 350, base: 1600, tower: 110 + 100, core: 250 + 100 };
/** キャンプは「最も大きいモンスターの半径 + 40」まで壁に寄ってよい（MapDefinition.campClearance と同じ。MLBB の巣は岩のくぼみ）。 */
const RADIUS = { blueSentinel: 110, redSentinel: 110, hornLizard: 80, magmaGolem: 95, emberBeetle: 80, astralWyrm: 180, ancientColossus: 220, mossWanderer: 75, crab: 85 };
const clearance = (name) => RADIUS[name.split(" ").pop()] + 40;
const here = (f) => new URL(`./${f}`, import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const st = JSON.parse(fs.readFileSync(here('trace_stats.json')));
const write = process.argv.includes('--write');
const mir = (p) => [S - p[0], S - p[1]];
const sc = (p) => [p[0] * K, p[1] * K];

/** 閉じた centripetal Catmull-Rom を、区間ごとに中点のずれが TOLERANCE 以下・弦が MAX_SEGMENT 以下になるまで二分して折れ線にする
 *  （Swift の Spline.closedCatmullRom(_:tolerance:maxSegment:) と同じエルミート形・同じ分け方。最後に 1/64 へ丸める）。 */
export function catmull(pts, tol = TOLERANCE, maxSeg = MAX_SEGMENT) {
  const n = pts.length, out = [];
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1]], add = (a, b) => [a[0] + b[0], a[1] + b[1]], mul = (a, k) => [a[0] * k, a[1] * k];
  const dt = (a, b) => Math.sqrt(Math.sqrt((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2));
  const d2seg = (m, a, b) => { const ab = sub(b, a), l2 = ab[0] ** 2 + ab[1] ** 2; const t = l2 > 0 ? Math.max(0, Math.min(1, ((m[0] - a[0]) * ab[0] + (m[1] - a[1]) * ab[1]) / l2)) : 0; const q = add(a, mul(ab, t)); return (q[0] - m[0]) ** 2 + (q[1] - m[1]) ** 2; };
  for (let i = 0; i < n; i++) {
    const p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
    const dt0 = dt(p0, p1), dt1 = dt(p1, p2), dt2 = dt(p2, p3);
    const m1 = mul(add(sub(mul(sub(p1, p0), 1 / dt0), mul(sub(p2, p0), 1 / (dt0 + dt1))), mul(sub(p2, p1), 1 / dt1)), dt1);
    const m2 = mul(add(sub(mul(sub(p2, p1), 1 / dt1), mul(sub(p3, p1), 1 / (dt1 + dt2))), mul(sub(p3, p2), 1 / dt2)), dt1);
    const c2 = sub(sub(mul(sub(p2, p1), 3), mul(m1, 2)), m2);
    const c3 = add(add(mul(sub(p1, p2), 2), m1), m2);
    const at = (u) => add(p1, mul(add(m1, mul(add(c2, mul(c3, u)), u)), u));
    const refine = (ua, pa, ub, pb, depth) => {
      const um = (ua + ub) / 2, pm = at(um);
      if (depth < 12 && (d2seg(pm, pa, pb) > tol * tol || (pb[0] - pa[0]) ** 2 + (pb[1] - pa[1]) ** 2 > maxSeg * maxSeg)) {
        refine(ua, pa, um, pm, depth + 1); out.push(pm); refine(um, pm, ub, pb, depth + 1);
      }
    };
    out.push(p1);
    refine(0, p1, 1, p2, 0);
  }
  return out.map((p) => [Math.round(p[0] * 64) / 64, Math.round(p[1] * 64) / 64]);
}
const segDist = (p, a, b) => { const dx = b[0] - a[0], dy = b[1] - a[1], l = dx * dx + dy * dy; let t = l ? ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l : 0; t = Math.max(0, Math.min(1, t)); return Math.hypot(p[0] - a[0] - dx * t, p[1] - a[1] - dy * t); };
const inside = (p, poly) => { let c = false; for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) { const a = poly[i], b = poly[j]; if ((a[1] > p[1]) !== (b[1] > p[1]) && p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]) c = !c; } return c; };
const sdist = (p, poly) => { let d = Infinity; for (let i = 0; i < poly.length; i++) d = Math.min(d, segDist(p, poly[i], poly[(i + 1) % poly.length])); return inside(p, poly) ? -d : d; };
const segSeg = (a, b, c, d) => { const o = (p, q, r) => Math.sign((q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])); if (o(a, b, c) !== o(a, b, d) && o(c, d, a) !== o(c, d, b)) return 0; return Math.min(segDist(a, c, d), segDist(b, c, d), segDist(c, a, b), segDist(d, a, b)); };
const polyLineDist = (poly, path) => { let best = Infinity; for (let k = 1; k < path.length; k++) { if (inside(path[k], poly)) return 0; for (let i = 0; i < poly.length; i++) best = Math.min(best, segSeg(path[k - 1], path[k], poly[i], poly[(i + 1) % poly.length])); } return best; };

// 壁（relayout の座標）。順は Swift と同じ: Blue の壁ぜんぶ → その写像 → 中心の壁
const blue = st.walls.filter((w) => w.side === 'blue').map((w) => w.control);
const center = st.walls.filter((w) => w.side === 'center').map((w) => w.control);
const controls = [...blue, ...blue.map((c) => c.map(mir)), ...center];
const walls = controls.map((c) => catmull(c.map(sc)));
const wallDist = (p) => Math.min(...walls.map((w) => sdist(p, w)));

// standard の配置（MapDefinition.standard と同じ値）
const bc = [1250, 1250], rc = mir(bc);
const lanes = {
  top: [bc, [700, 2600], [700, 9400], [2600, 11300], [9400, 11300], rc],
  mid: [bc, [2300, 2300], [9700, 9700], rc],
  bot: [bc, [2600, 700], [9400, 700], [11300, 2600], [11300, 9400], rc],
};
const blueTowers = [[484, 8793], [556, 6342], [639, 3166], [4656, 4991], [3391, 3705], [2399, 2399], [8848, 567], [5423, 470], [3179, 630]];
// standard.camps と同じ順（Blue 5・Red 5・星喰竜・巨像・苔甲・宝殻蟹 2）。whelp = 紫バフの仔の位置（Red は向きが逆）
const camps = [
  ['blue blueSentinel', [3075, 5755], 'blue'], ['blue redSentinel', [5609, 2627], 'blue'], ['blue hornLizard', [1994, 6821], 'blue'],
  ['blue magmaGolem', [6095, 3184], 'blue'], ['blue emberBeetle', [7480, 2235], 'blue'],
  ['red blueSentinel', [9089, 6224], 'red'], ['red redSentinel', [6370, 9366], 'red'], ['red hornLizard', [10096, 5158], 'red'],
  ['red magmaGolem', [5905, 8820], 'red'], ['red emberBeetle', [4613, 9859], 'red'],
  ['astralWyrm', [8260, 3590], 'neutral'], ['ancientColossus', [3740, 8410], 'neutral'], ['mossWanderer', [4710, 7285], 'neutral'],
  ['crab', [2220, 8850], 'neutral'], ['crab', mir([2220, 8850]), 'neutral'],
];
// 設計図から起こしたときはキャンプの位置も設計図のもの（standard の座標、同じ順）
if (st.camps) st.camps.forEach((p, i) => { camps[i][1] = p; });
const river = st.river ? catmull(st.river.map(sc), RIVER_TOLERANCE, RIVER_MAX_SEGMENT) : null;
const inRiver = (p) => river && sdist(p, river) < 0;
// 点対称の組（Blue 側の添字 → 相手の添字）。組は両方の平均を寄せて、相手はその写像にする
const pairs = [[0, 5], [1, 6], [2, 7], [3, 8], [4, 9], [10, 11], [13, 14]];

/** p（relayout）から最も近い、壁から need 以上離れた点（紫バフは仔の位置も壁から離す）。 */
function relocate(p, need, whelp) {
  const ok = (q) => wallDist(q) >= need && (!whelp || wallDist([q[0] + whelp[0], q[1] + whelp[1]]) >= 60 + 20);
  if (ok(p)) return p;
  for (let r = 10; r <= 800; r += 10) {
    let best = null;
    for (let a = 0; a < 72; a++) {
      const q = [p[0] + r * Math.cos(a * Math.PI / 36), p[1] + r * Math.sin(a * Math.PI / 36)];
      if (ok(q)) { best = q; break; }
    }
    if (best) return best;
  }
  throw new Error(`no spot near ${p}`);
}
const campPos = camps.map(([, p]) => sc(p));
const moves = [];
for (const [b, r] of pairs) {
  const avg = [(camps[b][1][0] + S - camps[r][1][0]) / 2, (camps[b][1][1] + S - camps[r][1][1]) / 2];
  const whelp = camps[b][0].endsWith('blueSentinel') ? [-190, 170] : null;
  const q = relocate(sc(avg), Math.max(clearance(camps[b][0]), clearance(camps[r][0])) + 10, whelp);
  campPos[b] = q;
  campPos[r] = [S * K - q[0], S * K - q[1]];
  moves.push([camps[b][0], Math.hypot(q[0] - sc(camps[b][1])[0], q[1] - sc(camps[b][1])[1]), Math.hypot(campPos[r][0] - sc(camps[r][1])[0], campPos[r][1] - sc(camps[r][1])[1])]);
}
{
  const q = relocate(campPos[12], clearance(camps[12][0]) + 10, null);
  moves.push([camps[12][0], Math.hypot(q[0] - campPos[12][0], q[1] - campPos[12][1])]);
  campPos[12] = q;
}

// 検証（relayout の縮尺）
const issues = [];
walls.forEach((w, k) => {
  for (const [name, path] of Object.entries(lanes)) { const d = polyLineDist(w, path.map(sc)); if (d < RULE.lane) issues.push(`wall ${k} is ${Math.round(d)} from lane ${name}`); }
  for (const [name, p] of [['blue fountain', [600, 600]], ['red fountain', mir([600, 600])], ['blue core', bc], ['red core', rc]]) {
    const d = sdist(sc(p), w); if (d < RULE.base) issues.push(`wall ${k} is ${Math.round(d)} from ${name}`);
  }
  blueTowers.concat(blueTowers.map(mir)).forEach((t, i) => { const d = sdist(sc(t), w); if (d <= RULE.tower) issues.push(`tower ${i} overlaps wall ${k} (${Math.round(d)})`); });
  for (const p of [bc, rc]) { const d = sdist(sc(p), w); if (d <= RULE.core) issues.push(`core overlaps wall ${k}`); }
  campPos.forEach((p, i) => { const d = sdist(p, w); if (d <= clearance(camps[i][0])) issues.push(`camp ${camps[i][0]} overlaps wall ${k} (${Math.round(d)})`); });
});

console.log(`walls ${walls.length}（頂点 ${walls.reduce((a, w) => a + w.length, 0)}）`);
for (const m of moves) console.log(`  camp ${m[0]}: 寄せた距離 ${m.slice(1).map((v) => Math.round(v)).join(' / ')}`);
if (river) {
  console.log(`river 頂点 ${river.length}`);
  for (const i of [12, 13, 14]) if (!inRiver(campPos[i])) issues.push(`camp ${camps[i][0]} is not in the river`);
  for (const [name, path] of Object.entries(lanes)) if (name !== 'mid' && path.map(sc).some((p) => inRiver(p))) issues.push(`lane ${name} crosses the river`);
}
console.log(issues.length ? issues.join('\n') : 'OK: 違反なし');

// 通路の幅（壁と壁、壁と地図の縁の最も狭い所。relayout のユニット）。レベルデザインの基準値の確認用
{
  const gaps = [];
  for (let i = 0; i < walls.length; i++) {
    for (let j = i + 1; j < walls.length; j++) {
      let best = Infinity;
      for (const p of walls[i]) best = Math.min(best, sdist(p, walls[j]));
      if (best < 900) gaps.push(best);
    }
  }
  gaps.sort((a, b) => a - b);
  const q = (f) => Math.round(gaps[Math.floor(f * (gaps.length - 1))]);
  console.log(`通路の幅（隣り合う壁の最短距離、900 未満の ${gaps.length} 組）: 最小 ${q(0)} / 10% ${q(0.1)} / 中央 ${q(0.5)} / 90% ${q(0.9)}`);
}

if (write) {
  const f = (v) => { const s = (Math.round(v * 10) / 10).toFixed(1); return s.endsWith('.0') ? s.slice(0, -2) : s; };
  const pt = (p) => `Vec2(${f(p[0])}, ${f(p[1])})`;
  const list = (cs) => cs.map((c) => `        [${c.map(pt).join(', ')}],`).join('\n');
  const swift = `// 生成: tools/map_proto/blueprint_terrain.mjs → terrain_swift.mjs（2026-10-16 のマップ設計図 = 60×60 マスの方眼から）。
// 手で編集しない。壁・川は standard（12000）の地図座標、キャンプは relayout の座標。
// 草むらは同じ設計図の細かい格子（blueprint_terrain.mjs → MapSanctumBushGrid.swift）。

extension MapDefinition {
    /// 壁（岩）の制御点（Blue 半面。Red は点対称）。閉じた Catmull-Rom スプラインでなめらかな多角形にする（Obstacle.smoothPolygon）。
    static let sanctumBlueWallSplines: [[Vec2]] = [
${list(blue)}
    ]

    /// 点対称の中心にあり、自分自身が写像になる壁（写さない）。
    static let sanctumCenterWallSplines: [[Vec2]] = [
${list(center)}
    ]

    /// 川の制御点（点対称の中心をまたぐ 1 つの閉じた輪郭: 左上の池 → 中央の細い水路 → 右下の池）。
    static let sanctumRiverSpline: [Vec2] = [
        ${(st.river || []).map(pt).join(', ')},
    ]

    /// relayout のキャンプの位置（standard.camps と同じ順）。設計図のアイコンの位置（点対称の組は両陣営の平均）を縮め、
    /// 壁から「最も大きいモンスターの半径 + 50」以上離れた最寄りの位置へ寄せた。
    static let sanctumRelayoutCampPositions: [Vec2] = [
${campPos.map((p) => `        ${pt(p)},`).join('\n')}
    ]

    /// スプラインを折れ線にする精度（ユニット = cm。relayout の座標で）: 弦と曲線のずれ ${TOLERANCE}（1 mm）以下・弦の長さ ${MAX_SEGMENT} 以下。
    static let sanctumSplineTolerance: Double = ${TOLERANCE}
    static let sanctumSplineMaxSegment: Double = ${MAX_SEGMENT}
    static let sanctumRiverTolerance: Double = ${RIVER_TOLERANCE}
    static let sanctumRiverMaxSegment: Double = ${RIVER_MAX_SEGMENT}
}
`;
  fs.writeFileSync(here('../../Packages/VelstriaCore/Sources/VelstriaCore/Sim/MapSanctumTerrain.swift'), swift);
  console.log('wrote Sim/MapSanctumTerrain.swift');
}
