// shapes.json 形式（SHAPES で指定）から MapDefinition.swift の壁・角の壁・草むらの配列を作り直す。
import fs from 'fs';
const sh = JSON.parse(fs.readFileSync(process.env.SHAPES || './shapes.json'));
const f = '../../Packages/VelstriaCore/Sources/VelstriaCore/Sim/MapDefinition.swift';
let s = fs.readFileSync(f, 'utf8'); const crlf = s.includes('\r\n'); s = s.replace(/\r\n/g, '\n');
const ob = (o) => o.t === 'R' ? `        .rect(Rect2(minX: ${o.v[0]}, minY: ${o.v[1]}, maxX: ${o.v[2]}, maxY: ${o.v[3]})),` : `        .circle(center: Vec2(${o.v[0]}, ${o.v[1]}), radius: ${o.v[2]}),`;
const sorted = [...sh.obstacles].sort((a, b) => (a.t === 'R' ? (a.v[0] + a.v[2]) / 2 : a.v[0]) - (b.t === 'R' ? (b.v[0] + b.v[2]) / 2 : b.v[0]));
const jungle = `    /// Blue 陣地（西と南のジャングル）の壁（${sorted.length} 個 × 2）。ミニマップの暗い塊を抽出して円と矩形で当てはめ
    /// （\`tools/map_proto/fitwalls.mjs\`。制約: レーンから 400・キャンプから 330・タワーから 250・Core から 1900・ボスの巣から 1100）、
    /// MLBB の草むらと重なる所は深さを半分ずつ譲った（\`tools/map_proto/resolve_bushes.mjs\`）。
    /// Red 側は点対称。\`validationIssues\` の制約（レーン 350・キャンプ 300・タワー 210）を満たす。
    static let standardBlueJungleObstacles: [Obstacle] = [
${sorted.map(ob).join('\n')}
    ]
`;
const corner = `    /// 左上の角を 45° に切る壁（円の連なり）。点対称の写像が右下の角になる。
    /// MLBB の角の壁の線（斜めのレーン中心 y − x = 8700 から 約 950 外側、y − x = 10000）に円の縁が来るよう置き、
    /// 最後の 1 つで地図の角との隙間を埋める。レーンとの間に角の草むらが入る。
    static let standardCornerObstacles: [Obstacle] = [
${sh.corner.map(ob).join('\n')}
    ]
`;
const groups = [];
sh.brushes.forEach((b, i) => { const g = sh.brushGroups[i]; (groups[g] ||= []).push(b); });
const rect = (b) => `Rect2(minX: ${b[0]}, minY: ${b[1]}, maxX: ${b[2]}, maxY: ${b[3]})`;
const bushLines = groups.map((rs, g) => rs ? `        // ${sh.brushNames[g]}\n        [${rs.map(rect).join(',\n         ')}],` : null).filter(Boolean);
const brushes = `    /// Blue 側の草むら（${bushLines.length} か所 × 2、矩形 ${sh.brushes.length} 個 × 2）。MLBB の現行マップの俯瞰画像を、タワーの位置で
    /// 射影変換して真上から見た図にし、背の高い草の範囲を読み取った（\`tools/map_proto/bushes_mlbb.mjs\`）。
    /// 斜めや細長い草むらは複数の矩形で近似し、同じ草むらとして扱う。Red 側は点対称。
    static let standardBlueBushes: [[Rect2]] = [
${bushLines.join('\n')}
    ]
`;
const a = s.indexOf('    /// Blue 陣地（西と南のジャングル）の壁'), b = s.indexOf('    /// 左上の角を 45° に切る壁');
if (a < 0 || b < 0) throw new Error('markers');
s = s.slice(0, a) + jungle + '\n' + s.slice(b);
const c = s.indexOf('    /// 左上の角を 45° に切る壁'), d = s.indexOf('\n}\n', c) + 1; // 角・草むらの配列の後の、拡張の閉じ括弧
s = s.slice(0, c) + corner + '\n' + brushes + s.slice(d);
if (crlf) s = s.replace(/\n/g, '\r\n');
fs.writeFileSync(f, s);
console.log('written', sorted.length, 'obstacles', sh.corner.length, 'corner', bushLines.length, 'bushes', sh.brushes.length, 'rects');
