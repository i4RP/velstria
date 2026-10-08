// shapes.json 形式（SHAPES で指定）から MapDefinition.swift の壁・草むらの配列を作り直す。
import fs from 'fs';
const sh = JSON.parse(fs.readFileSync(process.env.SHAPES || './shapes.json'));
const f = '../../Packages/VelstriaCore/Sources/VelstriaCore/Sim/MapDefinition.swift';
let s = fs.readFileSync(f, 'utf8'); const crlf = s.includes('\r\n'); s = s.replace(/\r\n/g, '\n');
const ob = (o) => o.t === 'R' ? `        .rect(Rect2(minX: ${o.v[0]}, minY: ${o.v[1]}, maxX: ${o.v[2]}, maxY: ${o.v[3]})),` : `        .circle(center: Vec2(${o.v[0]}, ${o.v[1]}), radius: ${o.v[2]}),`;
const sorted = [...sh.obstacles].sort((a, b) => (a.t === 'R' ? (a.v[0] + a.v[2]) / 2 : a.v[0]) - (b.t === 'R' ? (b.v[0] + b.v[2]) / 2 : b.v[0]));
const jungle = `    /// Blue 陣地（西と南のジャングル）の壁（${sorted.length} 個 × 2）。ミニマップの暗い塊を抽出して円と矩形で当てはめた
    /// （\`tools/map_proto/fitwalls.mjs\`。制約: レーンから 400・キャンプから 330・タワーから 250・Core から 1900・ボスの巣から 1100）。
    /// Red 側は点対称。\`validationIssues\` の制約（レーン 350・キャンプ 300・タワー 210）を満たす。
    static let standardBlueJungleObstacles: [Obstacle] = [
${sorted.map(ob).join('\n')}
    ]
`;
const brushes = `    /// Blue 陣地の草むら（${sh.brushes.length} 個 × 2）。レーン脇・河川・番人の近く（ミニマップに草むらは出ないので位置は設計）。
    static let standardBlueBrushes: [Rect2] = [
${sh.brushes.map((b) => `        Rect2(minX: ${b[0]}, minY: ${b[1]}, maxX: ${b[2]}, maxY: ${b[3]}),`).join('\n')}
    ]
`;
const a = s.indexOf('    /// Blue 陣地（西と南のジャングル）の壁'), b = s.indexOf('    /// 左上の角を 45° に切る壁');
if (a < 0 || b < 0) throw new Error('markers');
s = s.slice(0, a) + jungle + '\n' + s.slice(b);
const c = s.indexOf('    /// Blue 陣地の草むら'), d = s.indexOf('\n}\n', c) + 1; // 草むらの配列の後の、拡張の閉じ括弧
s = s.slice(0, c) + brushes + s.slice(d);
if (crlf) s = s.replace(/\n/g, '\r\n');
fs.writeFileSync(f, s);
console.log('written', sorted.length, 'obstacles', sh.brushes.length, 'brushes');
