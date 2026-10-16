import SwiftUI

// 担当: battle-hud。ミニマップの目標物アイコン（塔・クリスタル・ロード・タートル・番人）。
// すべて単位座標（中心 0・半径 1、y は下向き）のベクター。描く時に中心と半径で拡大するので、
// ドックの小さな地図でも全体マップでも同じ形がにじまずに出る。

enum HUDMinimapIcons {
    /// 単位座標の点列を中心 `c`・半径 `r` に写して閉じたパスにする。
    static func shape(_ points: [CGPoint], at c: CGPoint, radius r: CGFloat) -> Path {
        var path = Path()
        for (k, q) in points.enumerated() {
            let p = CGPoint(x: c.x + q.x * r, y: c.y + q.y * r)
            if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    private static func mirrored(_ half: [CGPoint]) -> [CGPoint] {
        half + half.reversed().map { CGPoint(x: -$0.x, y: $0.y) }
    }

    /// 塔: 尖った頂・左右の角・細い胴・広がった台座（MLBB の塔の記号に寄せた細身のシルエット）。
    static let turret: [CGPoint] = mirrored([
        CGPoint(x: 0, y: -1),
        CGPoint(x: 0.22, y: -0.6),
        CGPoint(x: 0.74, y: -0.74),
        CGPoint(x: 0.5, y: -0.3),
        CGPoint(x: 0.24, y: -0.2),
        CGPoint(x: 0.26, y: 0.4),
        CGPoint(x: 0.58, y: 0.68),
        CGPoint(x: 0.58, y: 0.98),
    ])

    /// クリスタル（本拠）: 翼を広げた結晶と台座。
    static let crystal: [CGPoint] = mirrored([
        CGPoint(x: 0, y: -1),
        CGPoint(x: 0.24, y: -0.5),
        CGPoint(x: 0.5, y: -0.72),
        CGPoint(x: 0.98, y: -0.42),
        CGPoint(x: 0.64, y: -0.22),
        CGPoint(x: 0.86, y: 0.12),
        CGPoint(x: 0.36, y: 0.08),
        CGPoint(x: 0.3, y: 0.5),
        CGPoint(x: 0.7, y: 0.66),
        CGPoint(x: 0.7, y: 0.96),
    ])

    /// ロード: 角の生えた兜と広げた翼。
    static let lord: [CGPoint] = mirrored([
        CGPoint(x: 0, y: -0.62),
        CGPoint(x: 0.2, y: -0.66),
        CGPoint(x: 0.36, y: -1),
        CGPoint(x: 0.42, y: -0.5),
        CGPoint(x: 0.98, y: -0.7),
        CGPoint(x: 0.82, y: -0.2),
        CGPoint(x: 0.98, y: 0.06),
        CGPoint(x: 0.5, y: 0.08),
        CGPoint(x: 0.4, y: 0.5),
        CGPoint(x: 0.6, y: 0.96),
        CGPoint(x: 0.14, y: 0.74),
    ])

    /// 番人（紫・赤バフ）: 小さな角付きの紋章。
    static let sentinel: [CGPoint] = mirrored([
        CGPoint(x: 0, y: -0.5),
        CGPoint(x: 0.3, y: -1),
        CGPoint(x: 0.42, y: -0.4),
        CGPoint(x: 0.9, y: -0.56),
        CGPoint(x: 0.66, y: 0.1),
        CGPoint(x: 0.34, y: 0.52),
        CGPoint(x: 0, y: 1),
    ])

    /// タートル: 甲羅（楕円）・頭・4 本の脚・甲羅の模様。塗りと模様の線を分けて返す。
    static func turtle(at c: CGPoint, radius r: CGFloat) -> (body: Path, pattern: Path) {
        var body = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x * r, y: c.y + y * r) }
        // 脚（甲羅の四隅から斜めに出る）
        for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] as [(CGFloat, CGFloat)] {
            body.addEllipse(in: CGRect(x: c.x + (sx * 0.62 - 0.2) * r, y: c.y + (sy * 0.4 + 0.1 - 0.17) * r,
                                       width: 0.4 * r, height: 0.34 * r))
        }
        // 頭（右上へ向く）と尾
        body.addEllipse(in: CGRect(x: c.x + 0.62 * r, y: c.y - 0.42 * r, width: 0.42 * r, height: 0.38 * r))
        body.move(to: pt(-0.7, 0.18))
        body.addLine(to: pt(-1.0, 0.36))
        body.addLine(to: pt(-0.66, 0.36))
        body.closeSubpath()
        // 甲羅
        body.addEllipse(in: CGRect(x: c.x - 0.78 * r, y: c.y - 0.6 * r, width: 1.5 * r, height: 1.08 * r))
        var pattern = Path()
        let angles = (0..<6).map { CGFloat($0) * .pi / 3 }
        let hex = angles.map { pt(-0.03 + cos($0) * 0.3, -0.06 + sin($0) * 0.24) }
        pattern.move(to: hex[0])
        for p in hex.dropFirst() { pattern.addLine(to: p) }
        pattern.closeSubpath()
        for (k, a) in angles.enumerated() {
            pattern.move(to: hex[k])
            pattern.addLine(to: pt(-0.03 + cos(a) * 0.66, -0.06 + sin(a) * 0.5))
        }
        return (body, pattern)
    }
}
