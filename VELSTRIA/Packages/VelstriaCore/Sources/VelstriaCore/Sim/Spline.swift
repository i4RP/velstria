import Foundation

// 担当: core-world。
// ミニマップからなぞった岩の輪郭（制御点）を滑らかな多角形の壁にするための曲線（Obstacle.smoothPolygon）。
// 決定論のため四則演算と平方根だけを使う（pow・三角関数は端末で結果が変わりうる）。

/// 閉じた曲線の標本化と多角形の面積。
public enum Spline {
    /// 制御点を順に通る閉じた centripetal Catmull-Rom 曲線（alpha = 0.5）を、隣り合う制御点の間ごとに
    /// samplesPerSpan 点ずつ標本化した点列。各区間の始点（= 制御点そのもの）を含み、閉じる点は繰り返さない。
    /// centripetal は制御点の間隔が不揃いでも尖り・区間内の自己交差が出ない（uniform は出る）。
    /// 隣と同じ位置の制御点は除く。それで 3 点未満になるときは制御点をそのまま返す。
    public static func closedCatmullRom(_ pts: [Vec2], samplesPerSpan: Int) -> [Vec2] {
        // 区間の長さ 0 で割らないよう、隣（末尾と先頭を含む）と同じ位置の点を除く
        var p: [Vec2] = []
        p.reserveCapacity(pts.count)
        for q in pts where p.last.map({ $0.distanceSquared(to: q) > 1e-12 }) ?? true { p.append(q) }
        while p.count > 1, p[p.count - 1].distanceSquared(to: p[0]) <= 1e-12 { p.removeLast() }
        let n = p.count
        guard n >= 3 else { return p }
        let steps = max(1, samplesPerSpan)
        var out: [Vec2] = []
        out.reserveCapacity(n * steps)
        for i in 0..<n {
            let p0 = p[(i + n - 1) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n]
            // 節点の間隔 = 距離^0.5（距離の 2 乗の 4 乗根）
            let dt0 = p0.distanceSquared(to: p1).squareRoot().squareRoot()
            let dt1 = p1.distanceSquared(to: p2).squareRoot().squareRoot()
            let dt2 = p2.distanceSquared(to: p3).squareRoot().squareRoot()
            // 区間 p1→p2 を u ∈ [0, 1] で表したときの両端の接線（centripetal の節点で求め、区間の長さ dt1 へ直す）
            let m1 = ((p1 - p0) / dt0 - (p2 - p0) / (dt0 + dt1) + (p2 - p1) / dt1) * dt1
            let m2 = ((p2 - p1) / dt1 - (p3 - p1) / (dt1 + dt2) + (p3 - p2) / dt2) * dt1
            // 3 次エルミート曲線 p1 + m1·u + c2·u² + c3·u³（u = 0 で p1、u = 1 で p2 を通る）
            let c2 = (p2 - p1) * 3 - m1 * 2 - m2
            let c3 = (p1 - p2) * 2 + m1 + m2
            for k in 0..<steps {
                let u = Double(k) / Double(steps)
                out.append(p1 + (m1 + (c2 + c3 * u) * u) * u)
            }
        }
        return out
    }

    /// 同じ曲線を、区間ごとに「中点が弦から tolerance 以内・弦の長さ maxSegment 以下」になるまで二分して標本化した点列
    /// （曲がりのきつい所ほど細かい。2026-10-16、壁の輪郭を 1 mm = 0.1 ユニットの精度で作るため）。
    /// 各区間の始点（= 制御点そのもの）を含み、閉じる点は繰り返さない。二分は 12 段まで。
    public static func closedCatmullRom(_ pts: [Vec2], tolerance: Double, maxSegment: Double) -> [Vec2] {
        var p: [Vec2] = []
        p.reserveCapacity(pts.count)
        for q in pts where p.last.map({ $0.distanceSquared(to: q) > 1e-12 }) ?? true { p.append(q) }
        while p.count > 1, p[p.count - 1].distanceSquared(to: p[0]) <= 1e-12 { p.removeLast() }
        let n = p.count
        guard n >= 3 else { return p }
        let tol2 = tolerance * tolerance, seg2 = maxSegment * maxSegment
        var out: [Vec2] = []
        out.reserveCapacity(n * 8)
        for i in 0..<n {
            let p0 = p[(i + n - 1) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n]
            let dt0 = p0.distanceSquared(to: p1).squareRoot().squareRoot()
            let dt1 = p1.distanceSquared(to: p2).squareRoot().squareRoot()
            let dt2 = p2.distanceSquared(to: p3).squareRoot().squareRoot()
            let m1 = ((p1 - p0) / dt0 - (p2 - p0) / (dt0 + dt1) + (p2 - p1) / dt1) * dt1
            let m2 = ((p2 - p1) / dt1 - (p3 - p1) / (dt1 + dt2) + (p3 - p2) / dt2) * dt1
            let c2 = (p2 - p1) * 3 - m1 * 2 - m2
            let c3 = (p1 - p2) * 2 + m1 + m2
            func at(_ u: Double) -> Vec2 { p1 + (m1 + (c2 + c3 * u) * u) * u }
            /// 点 m から線分 ab までの距離の 2 乗。
            func dist2(_ m: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
                let ab = b - a, l2 = ab.lengthSquared
                let t = l2 > 0 ? max(0, min(1, (m - a).dot(ab) / l2)) : 0
                return (a + ab * t).distanceSquared(to: m)
            }
            func refine(_ ua: Double, _ pa: Vec2, _ ub: Double, _ pb: Vec2, _ depth: Int) {
                let um = (ua + ub) / 2
                let pm = at(um)
                guard depth < 12, dist2(pm, pa, pb) > tol2 || pa.distanceSquared(to: pb) > seg2 else { return }
                refine(ua, pa, um, pm, depth + 1)
                out.append(pm)
                refine(um, pm, ub, pb, depth + 1)
            }
            out.append(p1)
            refine(0, p1, 1, p2, 0)
        }
        return out
    }

    /// 多角形の符号付き面積（地図座標 +y = 北で、反時計回りが正）。閉じる頂点は繰り返さない。
    public static func signedArea(_ v: [Vec2]) -> Double {
        guard v.count >= 3 else { return 0 }
        var s = 0.0
        var a = v[v.count - 1]
        for b in v {
            s += a.cross(b)
            a = b
        }
        return s / 2
    }
}
