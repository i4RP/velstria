import Foundation

// 担当: core-world（草むら・障害物・河川の詳細設計はこのファイルで行う）。
// 保存版 standard の座標は docs/DESIGN.md §2。稼働版 relayout は docs/maps/RELAYOUT_2026-10.md。

public struct TowerSpot: Codable, Hashable, Sendable {
    public var team: Team
    /// Core は nil。
    public var lane: Lane?
    public var tier: TowerTier
    public var pos: Vec2
    public var isCore: Bool
}

public enum CampKind: Int, Codable, Hashable, Sendable {
    /// 旧マップの小キャンプ（大 1 + 小 2）。標準マップでは使わない。
    case small
    case blueSentinel
    case redSentinel
    case astralWyrm
    case ancientColossus
    // MLBB の現行マップに合わせて追加（docs/DESIGN.md §2）
    case hornLizard
    case emberBeetle
    case magmaGolem
    /// 宝殻蟹（サイドレーン脇の川の端。3:00 までは子が出る）。
    case treasureCrab
    /// 苔甲の徘徊者（川の中立、mid の片側だけ）。
    case mossWanderer
}

extension CampKind {
    /// 星喰竜・古環の巨像。
    public var isBoss: Bool { self == .astralWyrm || self == .ancientColossus }
    /// 紫・赤バフの番人。
    public var isSentinel: Bool { self == .blueSentinel || self == .redSentinel }
    /// 地面に広めの空き地を作るキャンプ（番人・小キャンプ）。川の中立・ボスの巣は別。
    public var hasClearing: Bool {
        switch self {
        case .small, .blueSentinel, .redSentinel, .hornLizard, .emberBeetle, .magmaGolem: return true
        case .astralWyrm, .ancientColossus, .treasureCrab, .mossWanderer: return false
        }
    }
}

public struct CampSpot: Codable, Hashable, Sendable {
    public var id: Int
    /// そのキャンプがある陣地（ボスは neutral）。
    public var side: Team
    public var kind: CampKind
    public var pos: Vec2
    public var firstSpawn: Double
    public var respawn: Double
}

public struct BrushArea: Codable, Hashable, Sendable {
    public var id: Int
    public var rect: Rect2
    /// 草むらの番号（1 つの草むらが複数の矩形からなるとき同じ値。先頭の矩形の id）。同じ草むらの中は互いに見える。
    public var bush: Int

    public init(id: Int, rect: Rect2, bush: Int? = nil) {
        self.id = id
        self.rect = rect
        self.bush = bush ?? id
    }
}

public enum Obstacle: Codable, Hashable, Sendable {
    case rect(Rect2)
    case circle(center: Vec2, radius: Double)
    /// 多角形の壁（ミニマップからなぞった曲線の岩など）。頂点は地図座標（+y = 北）で反時計回り、自己交差なし（凹でもよい）、
    /// 閉じる頂点は繰り返さない。滑らかな輪郭は `Obstacle.smoothPolygon` で制御点から作る。
    case polygon([Vec2])

    public func contains(_ p: Vec2, inflatedBy r: Double = 0) -> Bool {
        switch self {
        case .rect(let rect):
            // 角は半径 r で丸めて膨張する（2026-10-16 から。角まで四角く膨張すると、壁の角の何もない所で止まって見え、
            // 角を回り込むときに引っかかる）
            guard r > 0 else { return rect.expanded(by: r).contains(p) }
            let dx = max(rect.minX - p.x, 0, p.x - rect.maxX)
            let dy = max(rect.minY - p.y, 0, p.y - rect.maxY)
            return dx * dx + dy * dy <= r * r
        case .circle(let c, let radius):
            return p.distanceSquared(to: c) <= (radius + r) * (radius + r)
        case .polygon(let v):
            // 内部か、境界から r 以内（角は丸く膨張）。r < 0 は内部で境界から −r 以上離れた所。
            // signedDistance と同じ計算から判定し、`signedDistance(p) <= r` と必ず一致させる
            let probe = Obstacle.probePolygon(v, p)
            let d = probe.distanceSquared.squareRoot()
            return r >= 0 ? (probe.inside || d <= r) : (probe.inside && d >= -r)
        }
    }
}

extension Obstacle {
    /// 点から障害物までの符号付き距離（内部は負）。
    /// 矩形の外側はユークリッド距離（角の外は角の点までの距離）、内側は最も近い辺までの距離。多角形は境界までの距離。
    /// `signedDistance(p) <= r` ⇔ `contains(p, inflatedBy: r)`（r ≥ 0）。
    public func signedDistance(to p: Vec2) -> Double {
        switch self {
        case .rect(let r):
            let ex = max(r.minX - p.x, p.x - r.maxX), ey = max(r.minY - p.y, p.y - r.maxY)
            if ex > 0 || ey > 0 {
                let dx = max(ex, 0), dy = max(ey, 0)
                return (dx * dx + dy * dy).squareRoot()
            }
            return max(ex, ey)
        case .circle(let c, let radius):
            return p.distance(to: c) - radius
        case .polygon(let v):
            let probe = Obstacle.probePolygon(v, p)
            let d = probe.distanceSquared.squareRoot()
            return probe.inside ? -d : d
        }
    }

    /// 外接矩形。
    public var bounds: Rect2 {
        switch self {
        case .rect(let r): return r
        case .circle(let c, let radius):
            return Rect2(minX: c.x - radius, minY: c.y - radius, maxX: c.x + radius, maxY: c.y + radius)
        case .polygon(let v):
            guard let first = v.first else { return Rect2(minX: 0, minY: 0, maxX: 0, maxY: 0) }
            var lo = first, hi = first
            for q in v {
                lo = Vec2(min(lo.x, q.x), min(lo.y, q.y))
                hi = Vec2(max(hi.x, q.x), max(hi.y, q.y))
            }
            return Rect2(minX: lo.x, minY: lo.y, maxX: hi.x, maxY: hi.y)
        }
    }

    /// 点における外向き法線（最も近い面の向き。矩形の角の外側では角の点から外へ: 角を滑らかに回り込む）。
    public func outwardNormal(at p: Vec2) -> Vec2 {
        switch self {
        case .rect(let r):
            let vx = p.x < r.minX ? p.x - r.minX : (p.x > r.maxX ? p.x - r.maxX : 0)
            let vy = p.y < r.minY ? p.y - r.minY : (p.y > r.maxY ? p.y - r.maxY : 0)
            if vx != 0 && vy != 0 { return Vec2(vx, vy).normalized }
            let d = [r.minX - p.x, p.x - r.maxX, r.minY - p.y, p.y - r.maxY]
            let normals = [Vec2(-1, 0), Vec2(1, 0), Vec2(0, -1), Vec2(0, 1)]
            var best = 0
            for k in 1..<4 where d[k] > d[best] { best = k }
            return normals[best]
        case .circle(let c, _):
            let n = (p - c).normalized
            return n == .zero ? Vec2(1, 0) : n
        case .polygon(let v):
            return Obstacle.polygonNormal(v, p, Obstacle.probePolygon(v, p))
        }
    }

    /// 中心 (6000,6000) に対する点対称写像（Blue 側の定義 → Red 側）。
    public var mirrored: Obstacle {
        switch self {
        case .rect(let r): return .rect(r.mirrored)
        case .circle(let c, let radius): return .circle(center: c.mirrored, radius: radius)
        // 180° 回転なので頂点の順はそのまま（反時計回りのまま）
        case .polygon(let v): return .polygon(v.map(\.mirrored))
        }
    }

    /// y = x に関する鏡映（Blue の下側ジャングル → 上側ジャングル）。
    var reflectedAcrossDiagonal: Obstacle {
        switch self {
        case .rect(let r): return .rect(Rect2(minX: r.minY, minY: r.minX, maxX: r.maxY, maxY: r.maxX))
        case .circle(let c, let radius): return .circle(center: Vec2(c.y, c.x), radius: radius)
        // 鏡映で回る向きが逆になるので、頂点の順も逆にして反時計回りに戻す
        case .polygon(let v): return .polygon(v.reversed().map { Vec2($0.y, $0.x) })
        }
    }

    /// 制御点を順に通る滑らかな閉曲線（centripetal Catmull-Rom）を、制御点の間ごとに samplesPerSpan 点ずつ標本化した
    /// 多角形の壁。制御点は時計回りでもよい（反時計回りに直す）。制御点を結んだ多角形が自己交差しないこと。
    /// 頂点は 1/64 単位に丸める（端数の多い値だと点対称の写像 `mirrored` を 2 回掛けても元の値に戻らず、
    /// 点対称の検査で同じ壁と見なされない）。
    /// 制御点を通る閉じた centripetal Catmull-Rom を、弦と曲線のずれ tolerance 以下・弦の長さ maxSegment 以下に
    /// 細かく分けた多角形（曲がりのきつい所ほど頂点が多い。頂点は 1/64 へ丸め、反時計回りにする）。
    public static func smoothPolygon(_ control: [Vec2], tolerance: Double, maxSegment: Double) -> Obstacle {
        var v = Spline.closedCatmullRom(control, tolerance: tolerance, maxSegment: maxSegment).map {
            Vec2(($0.x * 64).rounded() / 64, ($0.y * 64).rounded() / 64)
        }
        if Spline.signedArea(v) < 0 { v.reverse() }
        return .polygon(v)
    }

    public static func smoothPolygon(_ control: [Vec2], samplesPerSpan: Int = 6) -> Obstacle {
        var v = Spline.closedCatmullRom(control, samplesPerSpan: samplesPerSpan).map {
            Vec2(($0.x * 64).rounded() / 64, ($0.y * 64).rounded() / 64)
        }
        if Spline.signedArea(v) < 0 { v.reverse() }
        return .polygon(v)
    }
}

// MARK: - 多角形の幾何（Obstacle.polygon と NavGrid が使う）

extension Obstacle {
    /// 多角形の境界で点に最も近い所と、点が内部か。
    struct PolygonProbe {
        /// 内部か（交差数の偶奇。境界上はどちらにもなりうるが、そこでは距離が 0 なので contains・signedDistance に効かない）。
        var inside: Bool
        /// 境界までの距離の 2 乗（頂点が無ければ +∞）。
        var distanceSquared: Double
        /// 境界上で最も近い点。
        var closest: Vec2
        /// closest を含む辺（v[edge] → v[edge + 1]）。頂点が無ければ -1。
        var edge: Int
    }

    /// 辺を 1 周して、交差数と境界上の最近点を同時に求める。
    static func probePolygon(_ v: [Vec2], _ p: Vec2) -> PolygonProbe {
        var out = PolygonProbe(inside: false, distanceSquared: .infinity, closest: p, edge: -1)
        let n = v.count
        for i in 0..<n {
            let a = v[i], b = v[i + 1 == n ? 0 : i + 1]
            if crossesRay(a, b, p) { out.inside.toggle() }
            let q = closestPointOnSegment(p, a, b)
            let d2 = p.distanceSquared(to: q)
            if d2 < out.distanceSquared {
                out.distanceSquared = d2
                out.closest = q
                out.edge = i
            }
        }
        return out
    }

    /// 外向き法線。外側は最も近い境界の点から p へ、内側は p から最も近い境界の点へ（凸の角の外では角を丸く回り込む）。
    /// 境界上はその辺の外向き法線（反時計回りなので辺 a→b の右側 (e.y, −e.x)）。
    static func polygonNormal(_ v: [Vec2], _ p: Vec2, _ probe: PolygonProbe) -> Vec2 {
        guard probe.edge >= 0 else { return Vec2(1, 0) }
        let n = (probe.inside ? probe.closest - p : p - probe.closest).normalized
        if n != .zero { return n }
        let a = v[probe.edge], b = v[probe.edge + 1 == v.count ? 0 : probe.edge + 1]
        let e = Vec2(b.y - a.y, a.x - b.x).normalized
        return e == .zero ? Vec2(1, 0) : e
    }

    /// 点が多角形の内部か（交差数の偶奇。境界上はどちらにもなりうる）。
    static func polygonContains(_ v: [Vec2], _ p: Vec2) -> Bool {
        var inside = false
        let n = v.count
        for i in 0..<n where crossesRay(v[i], v[i + 1 == n ? 0 : i + 1], p) { inside.toggle() }
        return inside
    }

    /// 辺 a→b が p から +x 方向へ伸ばした半直線と交わるか（交差数の 1 回分。辺の下端を含み上端を含まない）。
    @inline(__always) static func crossesRay(_ a: Vec2, _ b: Vec2, _ p: Vec2) -> Bool {
        guard (a.y > p.y) != (b.y > p.y) else { return false }
        return p.x < a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
    }

    /// 線分 a–b 上で p に最も近い点。
    @inline(__always) static func closestPointOnSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Vec2 {
        let e = b - a
        let len2 = e.lengthSquared
        guard len2 > 0 else { return a }
        return a + e * max(0, min(1, (p - a).dot(e) / len2))
    }

    /// 線分 a–b が多角形に半径 r で触れるか（端点が内部・辺と交わる・辺から r 以内）。
    static func polygonTouchesSegment(_ v: [Vec2], _ a: Vec2, _ b: Vec2, radius r: Double) -> Bool {
        let minX = min(a.x, b.x) - r, maxX = max(a.x, b.x) + r
        let minY = min(a.y, b.y) - r, maxY = max(a.y, b.y) + r
        let r2 = r * r
        var inside = false
        let n = v.count
        for i in 0..<n {
            let p = v[i], q = v[i + 1 == n ? 0 : i + 1]
            if crossesRay(p, q, a) { inside.toggle() }
            // 外接矩形どうしが r より離れている辺は測らない
            if max(p.x, q.x) < minX || min(p.x, q.x) > maxX || max(p.y, q.y) < minY || min(p.y, q.y) > maxY { continue }
            if MapDefinition.segmentDistanceSquared(a, b, p, q) <= r2 { return true }
        }
        // どの辺にも触れずに a が内部なら、線分全体が内部
        return inside
    }
}

public struct MapDefinition: Codable, Hashable, Sendable {
    public var size: Double
    /// index = Team.rawValue
    public var fountains: [Vec2]
    /// index = Team.rawValue
    public var cores: [Vec2]
    /// Blue 視点のレーン経路（Blue Core → Red Core）。index = Lane.rawValue
    public var lanePaths: [[Vec2]]
    /// 実在するレーン。通常は 3 本、乱闘は `[.mid]` のみ。
    /// ミニオン生成・ボットのレーン選択・レーン検証はこの配列を基準にする
    /// （`lanePaths` は常に 3 要素を保ちインデックス安全性を確保する）。
    public var lanes: [Lane] = Lane.allCases
    public var towers: [TowerSpot]
    public var camps: [CampSpot]
    public var brushes: [BrushArea]
    public var obstacles: [Obstacle]
    public var riverWidth: Double
    /// 草むらの細かい格子（MLBB のミニマップの形のまま。BushMask.swift）。nil なら `brushes` の矩形が草むら。
    /// あるときは `brushes[k]` は草むら k の外接矩形で、判定は格子で行う。
    public var bushMask: BushMask? = nil
    /// 川の形（2026-10-16〜、設計図の 8 の字の水路: 左上と右下の池を中央の細い水路がつなぐ）。nil なら x + y = size の
    /// 幅 riverWidth の帯（standard・乱闘）。
    public var river: Obstacle? = nil
    /// Authored stage identity; nil preserves older/procedural map fixtures and decoding.
    public var stageID: String? = nil

    /// team のミニオンが進む経路。Red は Blue 経路の逆順。
    public func lanePath(_ lane: Lane, for team: Team) -> [Vec2] {
        let p = lanePaths[lane.rawValue]
        return team == .red ? Array(p.reversed()) : p
    }

    public func fountain(_ team: Team) -> Vec2 { fountains[min(team.rawValue, 1)] }
    public func core(_ team: Team) -> Vec2 { cores[min(team.rawValue, 1)] }

    /// 点が泉の範囲内か。
    public func isInFountain(_ p: Vec2, team: Team) -> Bool {
        p.distance(to: fountain(team)) <= Balance.fountainRadius
    }

    /// 点を含む草むらの番号（`BrushArea.bush`。複数の矩形からなる草むらはどの矩形でも同じ値）。
    public func brushIndex(at p: Vec2) -> Int? {
        if let m = bushMask {
            // `brushes` を空にした地図（テスト）では草むらなし
            guard let k = m.bush(at: p), k < brushes.count else { return nil }
            return brushes[k].bush
        }
        for k in brushes.indices where brushes[k].rect.contains(p) { return brushes[k].bush }
        return nil
    }

    /// 河川上か（`river` の多角形、無ければ x + y = size の帯）。
    public func isInRiver(_ p: Vec2) -> Bool {
        riverSignedDistance(p) <= 0
    }

    /// 川の岸までの距離（川の中は負）。
    public func riverSignedDistance(_ p: Vec2) -> Double {
        if let river { return river.signedDistance(to: p) }
        return abs(p.x + p.y - size) / 2.0.squareRoot() - riverWidth / 2
    }

    /// ジャングルか川か（エンブレムの山野の主）。マップに区域の定義は無いので近似:
    /// 川の帯、またはレーンの通り道（中心線から wildernessLaneHalfWidth）と両陣地（泉・コアの周り baseClearRadius）の外。
    public func isInWilderness(_ p: Vec2) -> Bool {
        if isInRiver(p) { return true }
        for t in Team.players {
            if p.distance(to: fountain(t)) < MapDefinition.baseClearRadius || p.distance(to: core(t)) < MapDefinition.baseClearRadius {
                return false
            }
        }
        return nearestLane(to: p).distance > MapDefinition.wildernessLaneHalfWidth
    }

    /// 山野の主の「レーンの通り道」の半幅（障害物はレーンの中心線から laneObstacleClearance 以上離れている）。
    public static let wildernessLaneHalfWidth: Double = 400

    /// p がどちらの陣地のジャングルか（川・レーン・基地は nil）。陣地は泉に近い方（地図は点対称なので川の帯の両岸に分かれる）。
    public func jungleSide(of p: Vec2) -> Team? {
        guard !isInRiver(p), isInWilderness(p) else { return nil }
        return p.distanceSquared(to: fountain(.blue)) <= p.distanceSquared(to: fountain(.red)) ? .blue : .red
    }
}

// MARK: - レーン幾何（ミニオン・ボット・HUD が使う）

/// 折れ線上の最近点。
public struct PolylineProjection: Hashable, Sendable {
    /// 最近点。
    public var point: Vec2
    /// 最近点までの距離。
    public var distance: Double
    /// 最近点を含む区間の終点インデックス（区間 = path[segmentEnd-1] → path[segmentEnd]）。
    public var segmentEnd: Int
}

extension MapDefinition {
    /// 折れ線 path 上で p に最も近い点。firstSegmentEnd より前の区間は無視する（後戻り防止）。
    public static func project(_ p: Vec2, onto path: [Vec2], firstSegmentEnd: Int = 1) -> PolylineProjection {
        guard path.count >= 2 else {
            let q = path.first ?? p
            return PolylineProjection(point: q, distance: p.distance(to: q), segmentEnd: 0)
        }
        var best = PolylineProjection(point: path[0], distance: .infinity, segmentEnd: 1)
        let start = max(1, min(path.count - 1, firstSegmentEnd))
        for k in start..<path.count {
            let a = path[k - 1], b = path[k]
            let ab = b - a
            let lenSq = ab.lengthSquared
            let t = lenSq < 1e-9 ? 0 : max(0, min(1, (p - a).dot(ab) / lenSq))
            let q = a + ab * t
            let d = p.distance(to: q)
            if d < best.distance { best = PolylineProjection(point: q, distance: d, segmentEnd: k) }
        }
        return best
    }

    /// レーン中心線までの距離。
    public func distanceToLane(_ p: Vec2, lane: Lane) -> Double {
        MapDefinition.project(p, onto: lanePaths[lane.rawValue]).distance
    }

    /// 最も近いレーンとその距離（実在レーンのみ対象）。
    public func nearestLane(to p: Vec2) -> (lane: Lane, distance: Double) {
        var best: (lane: Lane, distance: Double) = (lanes.first ?? .mid, .infinity)
        for lane in lanes {
            let d = distanceToLane(p, lane: lane)
            if d < best.distance { best = (lane, d) }
        }
        return best
    }

    /// EXP レーン = 最初に出現する中立ボスに近い側レーン、Gold レーン = 遠い側レーン（参照仕様 §3.1）。
    /// 側レーン（top・bot）が両方ある標準マップだけが持つ。乱闘など単レーンのマップは nil。
    public var expLane: Lane? {
        // 川の中立（片側のみの小キャンプ）は数えない。ボス（星喰竜・古環の巨像）だけが対象。
        guard lanes.contains(.top), lanes.contains(.bot),
              let boss = camps.filter({ $0.side == .neutral && ($0.kind == .astralWyrm || $0.kind == .ancientColossus) })
                  .min(by: { $0.firstSpawn < $1.firstSpawn }) else { return nil }
        return distanceToLane(boss.pos, lane: .top) < distanceToLane(boss.pos, lane: .bot) ? .top : .bot
    }

    public var goldLane: Lane? {
        guard let exp = expLane else { return nil }
        return exp == .top ? .bot : .top
    }

    /// ポジション → 担当レーン（ジャングルは nil）。EXP 向き（top）は EXP レーン、Gold 向き（carry）と支援は Gold レーン。
    /// 側レーンが無いマップでは従来どおり top → top、carry・support → bot。
    public func lane(for position: LanePosition) -> Lane? {
        switch position {
        case .jungle: return nil
        case .mid: return .mid
        case .top: return expLane ?? .top
        case .carry, .support: return goldLane ?? .bot
        }
    }

    /// 点を含む障害物の添字（膨張半径込み）。
    public func obstacleIndex(at p: Vec2, inflatedBy r: Double = 0) -> Int? {
        obstacles.firstIndex { $0.contains(p, inflatedBy: r) }
    }
}

// MARK: - 標準マップ

extension MapDefinition {
    /// レーン中心線から障害物までの最小距離（DESIGN §2）。
    public static let laneObstacleClearance: Double = 350
    /// 泉・Core 周辺で障害物を置かない半径。
    /// 2026-10-16 に 1800 → 1600（MLBB の拠点を囲む壁が Core から 1640 前後。遊ぶ地図の縮尺で）。
    static let baseClearRadius: Double = 1600

    /// 泉・Core・mid の経路とタワー（標準マップと乱闘マップで共通）。
    static let standardBlueFountain = Vec2(600, 600)
    static let standardBlueCore = Vec2(1250, 1250)
    /// ミニマップのアイコンから測った位置（外塔・内塔・基部塔）。mid レーンの帯（y = x）の中で、Blue は左上寄りに置かれている。
    static let standardMidTowers = [Vec2(4656, 4991), Vec2(3391, 3705), Vec2(2399, 2399)]

    public static let standard: MapDefinition = {
        let blueFountain = standardBlueFountain
        let blueCore = standardBlueCore
        let redCore = blueCore.mirrored

        // レーンの帯は地図の縁に沿い（中心線は縁から 700）、左上と右下の角は 45° に切る。
        // top = 左縁を上り、左上の角を斜めに抜けて上縁を右へ。bot = 下縁を右へ、右下の角を斜めに抜けて右縁を上へ（top の点対称の逆順）。
        let top: [Vec2] = [blueCore, Vec2(700, 2600), Vec2(700, 9400), Vec2(2600, 11300), Vec2(9400, 11300), redCore]
        let mid: [Vec2] = [blueCore, Vec2(2300, 2300), Vec2(9700, 9700), redCore]
        let bot: [Vec2] = [blueCore, Vec2(2600, 700), Vec2(9400, 700), Vec2(11300, 2600), Vec2(11300, 9400), redCore]

        // Blue タワー（レーン, 外/内/基部）。ミニマップのアイコンの重心から測った位置（点対称のペアで較正、誤差 数十）。
        // 縁のレーンではタワーが帯の外側寄り（縁側）に立つ。
        let blueTowerPos: [Lane: [Vec2]] = [
            .top: [Vec2(484, 8793), Vec2(556, 6342), Vec2(639, 3166)],
            .mid: standardMidTowers,
            .bot: [Vec2(8848, 567), Vec2(5423, 470), Vec2(3179, 630)],
        ]
        var towers: [TowerSpot] = []
        for lane in Lane.allCases {
            for tier in TowerTier.allCases {
                towers.append(TowerSpot(team: .blue, lane: lane, tier: tier,
                                        pos: blueTowerPos[lane]![tier.rawValue], isCore: false))
            }
        }
        // Red: 点対称で top ⇄ bot が入れ替わる（Blue bot の写像が Red top）。
        for lane in Lane.allCases {
            let source: Lane = lane == .top ? .bot : (lane == .bot ? .top : .mid)
            for tier in TowerTier.allCases {
                towers.append(TowerSpot(team: .red, lane: lane, tier: tier,
                                        pos: blueTowerPos[source]![tier.rawValue].mirrored, isCore: false))
            }
        }
        towers.append(TowerSpot(team: .blue, lane: nil, tier: .base, pos: blueCore, isCore: true))
        towers.append(TowerSpot(team: .red, lane: nil, tier: .base, pos: redCore, isCore: true))

        // キャンプ: MLBB の現行マップ（Sanctum Island）と同じ種類・配置（docs/DESIGN.md §2）。
        // 位置はミニマップのアイコンから測り（誤差 数十）、種類は MLBB Wiki のミニマップ凡例と俯瞰画像で確かめた。
        // ゲーム側の配置は厳密な点対称ではないので、Red 側も測った値をそのまま使う（Blue 側の写像とのずれは最大 約 100）。
        // 各陣地: 紫バフ（蒼晶の番人 + 仔）と棘角トカゲが EXP レーン側から遠い方（Blue は西）、
        // 赤バフ（紅焔の番人）と熔岩の岩人・熾甲虫が近い方（Blue は南）。
        let blueCamps: [(CampKind, Vec2)] = [
            (.blueSentinel, Vec2(3075, 5755)),
            (.redSentinel, Vec2(5609, 2627)),
            (.hornLizard, Vec2(1994, 6821)),
            (.magmaGolem, Vec2(6095, 3184)),
            (.emberBeetle, Vec2(7480, 2235)),
        ]
        let redCamps: [(CampKind, Vec2)] = [
            (.blueSentinel, Vec2(9089, 6224)),
            (.redSentinel, Vec2(6370, 9366)),
            (.hornLizard, Vec2(10096, 5158)),
            (.magmaGolem, Vec2(5905, 8820)),
            (.emberBeetle, Vec2(4613, 9859)),
        ]
        var camps: [CampSpot] = []
        func timing(_ k: CampKind) -> (first: Double, respawn: Double) {
            typealias J = Balance.Jungle
            switch k {
            case .blueSentinel, .redSentinel: return (J.campFirstSpawn, J.buffRespawn)
            case .hornLizard, .emberBeetle, .magmaGolem, .small: return (J.campFirstSpawn, J.creepRespawn)
            // 序盤ボス 2:00・再出現 120 秒、後半ボス 8:00・再出現 180 秒（参照仕様 §5.1・§5.3）
            case .astralWyrm: return (120, 120)
            case .ancientColossus: return (480, 180)
            // 子の 20 秒周期と 3:00 の交代は SpawnSystem が扱う（ここの値は親の再出現）
            case .treasureCrab: return (J.crabFirstSpawn, J.crabRespawn)
            case .mossWanderer: return (J.wandererFirstSpawn, J.wandererRespawn)
            }
        }
        func add(_ side: Team, _ k: CampKind, _ p: Vec2) {
            let t = timing(k)
            camps.append(CampSpot(id: camps.count, side: side, kind: k, pos: p, firstSpawn: t.first, respawn: t.respawn))
        }
        for (k, p) in blueCamps { add(.blue, k, p) }
        for (k, p) in redCamps { add(.red, k, p) }
        add(.neutral, .astralWyrm, Vec2(8260, 3590))
        add(.neutral, .ancientColossus, Vec2(3740, 8410))
        // 川の中立は mid の片側だけ（古環の巨像の巣の側）。
        add(.neutral, .mossWanderer, Vec2(4710, 7285))
        // 宝殻蟹は左上・右下の川の端（サイドレーン脇の結晶の岩のそば）に 1 体ずつ。俯瞰画像から読んだ位置を、
        // 岩（壁）から 300 離れるよう少し川側へ寄せた。
        add(.neutral, .treasureCrab, Vec2(2220, 8850))
        add(.neutral, .treasureCrab, Vec2(2220, 8850).mirrored)

        // 障害物・草むら: Blue 陣地（西と南のジャングル + 左上の角）を定義し、点対称で Red 半面を作る。
        // 角（左上）の写像が右下の角になる。
        let blueHalfObstacles = standardBlueJungleObstacles + standardCornerObstacles
        let obstacles = blueHalfObstacles + blueHalfObstacles.map(\.mirrored)

        // 草むら: 1 つの草むらを成す矩形には同じ番号（先頭の矩形の id）を振る。
        var brushes: [BrushArea] = []
        for rects in standardBlueBushes + standardBlueBushes.map({ $0.map(\.mirrored) }) {
            let bush = brushes.count
            for r in rects { brushes.append(BrushArea(id: brushes.count, rect: r, bush: bush)) }
        }

        return MapDefinition(
            size: Balance.mapSize,
            fountains: [blueFountain, blueFountain.mirrored],
            cores: [blueCore, redCore],
            lanePaths: [top, mid, bot],
            towers: towers,
            camps: camps,
            brushes: brushes,
            obstacles: obstacles,
            riverWidth: 900
        )
    }()

    /// 2026-10 relayout: original `standard` remains an immutable comparison fixture.
    /// Only positions and terrain extents change; obstacle footprints and gameplay stats do not.
    public static let relayout: MapDefinition = makeCompactRelayout()

    /// New matches default to Seaside. Brawl and Magic Chess keep their dedicated maps.
    public static func map(for mode: MatchMode, stage: MatchStage = .seaside) -> MapDefinition {
        if mode == .brawl { return .brawl }
        return stage == .seaside ? .seaside : .canyon
    }

    /// Resolve the recorded stage as well as the mode for matches, online play and replays.
    /// Legacy configs without a stage continue to use Canyon.
    public static func map(for config: MatchConfig) -> MapDefinition {
        map(for: config.mode, stage: config.resolvedStage)
    }

    /// 乱闘マップ（単レーン・ジャングル無し）。mid の対角 1 本だけを使う 5v5。
    /// `lanePaths` は 3 要素（top=bot=mid）を保ちつつ `lanes=[.mid]` で挙動を制限する。
    /// 障害物・キャンプは置かず、検証（laneObstacleClearance/baseClearRadius）を確実に通す。
    public static let brawl: MapDefinition = {
        let blueFountain = standardBlueFountain
        let blueCore = standardBlueCore
        let redCore = blueCore.mirrored
        let mid: [Vec2] = [blueCore, Vec2(2300, 2300), Vec2(9700, 9700), redCore]

        // mid 3 tier を両チーム分 + コア。
        let blueMidTowers = standardMidTowers
        var towers: [TowerSpot] = []
        for tier in TowerTier.allCases {
            towers.append(TowerSpot(team: .blue, lane: .mid, tier: tier, pos: blueMidTowers[tier.rawValue], isCore: false))
            towers.append(TowerSpot(team: .red, lane: .mid, tier: tier, pos: blueMidTowers[tier.rawValue].mirrored, isCore: false))
        }
        towers.append(TowerSpot(team: .blue, lane: nil, tier: .base, pos: blueCore, isCore: true))
        towers.append(TowerSpot(team: .red, lane: nil, tier: .base, pos: redCore, isCore: true))

        return MapDefinition(
            size: Balance.mapSize,
            fountains: [blueFountain, blueFountain.mirrored],
            cores: [blueCore, redCore],
            lanePaths: [mid, mid, mid],
            lanes: [.mid],
            towers: towers,
            camps: [],
            brushes: [],
            obstacles: [],
            riverWidth: 900
        )
    }()

    /// Blue 陣地（西と南のジャングル）の壁（47 個 × 2）。ミニマップの暗い塊を抽出して円と矩形で当てはめ
    /// （`tools/map_proto/fitwalls.mjs`。制約: レーンから 400・キャンプから 330・タワーから 250・Core から 1900・ボスの巣から 1100）、
    /// MLBB の草むらと重なる所は深さを半分ずつ譲った（`tools/map_proto/resolve_bushes.mjs`）。
    /// Red 側は点対称。`validationIssues` の制約（レーン 350・キャンプ 300・タワー 210）を満たす。
    static let standardBlueJungleObstacles: [Obstacle] = [
        .rect(Rect2(minX: 1400, minY: 3450, maxX: 1750, maxY: 3750)),
        .rect(Rect2(minX: 1400, minY: 7950, maxX: 1900, maxY: 9100)),
        .rect(Rect2(minX: 1400, minY: 6110, maxX: 1900, maxY: 6500)),
        .rect(Rect2(minX: 1400, minY: 4250, maxX: 1940, maxY: 5250)),
        .rect(Rect2(minX: 1400, minY: 3400, maxX: 1950, maxY: 3650)),
        .rect(Rect2(minX: 1400, minY: 8000, maxX: 2240, maxY: 8500)),
        .rect(Rect2(minX: 1600, minY: 7150, maxX: 2200, maxY: 7340)),
        .circle(center: Vec2(2030, 4230), radius: 150),
        .rect(Rect2(minX: 1850, minY: 3200, maxX: 2250, maxY: 3450)),
        .circle(center: Vec2(2630, 5330), radius: 100),
        .rect(Rect2(minX: 2600, minY: 7200, maxX: 2900, maxY: 7750)),
        .rect(Rect2(minX: 2650, minY: 5190, maxX: 3000, maxY: 5400)),
        .rect(Rect2(minX: 2700, minY: 3900, maxX: 3100, maxY: 4350)),
        .circle(center: Vec2(2930, 7230), radius: 110),
        .rect(Rect2(minX: 2900, minY: 6100, maxX: 3350, maxY: 6350)),
        .rect(Rect2(minX: 2950, minY: 4200, maxX: 3600, maxY: 4550)),
        .rect(Rect2(minX: 3150, minY: 1150, maxX: 3550, maxY: 2200)),
        .circle(center: Vec2(3530, 5930), radius: 100),
        .rect(Rect2(minX: 3450, minY: 6800, maxX: 3700, maxY: 7100)),
        .circle(center: Vec2(3630, 1330), radius: 200),
        .circle(center: Vec2(3930, 2730), radius: 150),
        .rect(Rect2(minX: 3900, minY: 4800, maxX: 4200, maxY: 5360)),
        .circle(center: Vec2(4130, 3030), radius: 200),
        .rect(Rect2(minX: 4140, minY: 4950, maxX: 4350, maxY: 5600)),
        .circle(center: Vec2(4330, 2130), radius: 300),
        .circle(center: Vec2(4330, 3330), radius: 100),
        .rect(Rect2(minX: 4120, minY: 5450, maxX: 4550, maxY: 5700)),
        .circle(center: Vec2(4430, 1830), radius: 100),
        .circle(center: Vec2(4530, 6530), radius: 150),
        .rect(Rect2(minX: 4550, minY: 6200, maxX: 4800, maxY: 6460)),
        .circle(center: Vec2(4930, 3830), radius: 250),
        .circle(center: Vec2(4930, 6130), radius: 200),
        .rect(Rect2(minX: 5000, minY: 3850, maxX: 5650, maxY: 4450)),
        .rect(Rect2(minX: 4750, minY: 1300, maxX: 6000, maxY: 1700)),
        .rect(Rect2(minX: 4900, minY: 3900, maxX: 5950, maxY: 4300)),
        .circle(center: Vec2(6030, 1530), radius: 100),
        .rect(Rect2(minX: 5900, minY: 4950, maxX: 6250, maxY: 5250)),
        .rect(Rect2(minX: 5950, minY: 2350, maxX: 6250, maxY: 2850)),
        .circle(center: Vec2(6230, 4930), radius: 90),
        .rect(Rect2(minX: 6200, minY: 4650, maxX: 6550, maxY: 4840)),
        .rect(Rect2(minX: 6400, minY: 3050, maxX: 6650, maxY: 3580)),
        .rect(Rect2(minX: 6400, minY: 4500, maxX: 6700, maxY: 4740)),
        .circle(center: Vec2(6730, 4430), radius: 100),
        .rect(Rect2(minX: 6600, minY: 1350, maxX: 7550, maxY: 1750)),
        .rect(Rect2(minX: 6950, minY: 2550, maxX: 7500, maxY: 2800)),
        .rect(Rect2(minX: 8150, minY: 1400, maxX: 9350, maxY: 1650)),
        .rect(Rect2(minX: 8650, minY: 1400, maxX: 9450, maxY: 2080)),
    ]

    /// 左上の角を 45° に切る壁（円の連なり）。点対称の写像が右下の角になる。
    /// MLBB の角の壁の線（斜めのレーン中心 y − x = 8700 から 約 950 外側、y − x = 10000）に円の縁が来るよう置き、
    /// 最後の 1 つで地図の角との隙間を埋める。レーンとの間に角の草むらが入る。
    static let standardCornerObstacles: [Obstacle] = [
        .circle(center: Vec2(-350, 10357), radius: 500),
        .circle(center: Vec2(150, 10857), radius: 500),
        .circle(center: Vec2(650, 11357), radius: 500),
        .circle(center: Vec2(1150, 11857), radius: 500),
        .circle(center: Vec2(1650, 12357), radius: 500),
        .circle(center: Vec2(100, 11900), radius: 500),
    ]

    /// Blue 側の草むら（16 か所 × 2、矩形 22 個 × 2）。MLBB の現行マップの俯瞰画像を、タワーの位置で
    /// 射影変換して真上から見た図にし、背の高い草の範囲を読み取った（`tools/map_proto/bushes_mlbb.mjs`）。
    /// 斜めや細長い草むらは複数の矩形で近似し、同じ草むらとして扱う。Red 側は点対称。
    static let standardBlueBushes: [[Rect2]] = [
        // 左レーン外側
        [Rect2(minX: 100, minY: 7200, maxX: 540, maxY: 7950)],
        // 下レーン外側
        [Rect2(minX: 7000, minY: 200, maxX: 8000, maxY: 550)],
        // 右下の角（斜めの帯）
        [Rect2(minX: 9875, minY: 275, maxX: 10325, maxY: 725),
         Rect2(minX: 10325, minY: 725, maxX: 10775, maxY: 1175),
         Rect2(minX: 10775, minY: 1175, maxX: 11225, maxY: 1625),
         Rect2(minX: 11225, minY: 1625, maxX: 11675, maxY: 2075)],
        // 紅焔の番人の下
        [Rect2(minX: 5400, minY: 1720, maxX: 6250, maxY: 2150)],
        // 祠の右
        [Rect2(minX: 4350, minY: 2600, maxX: 4650, maxY: 3050)],
        // 竜の巣の西岸
        [Rect2(minX: 6420, minY: 3610, maxX: 6800, maxY: 3920)],
        // 熾甲虫の右
        [Rect2(minX: 7800, minY: 1750, maxX: 8300, maxY: 2350)],
        // 環状の岩の上
        [Rect2(minX: 8750, minY: 2100, maxX: 9750, maxY: 2450)],
        // 宝殻蟹（上）の右
        [Rect2(minX: 1850, minY: 7360, maxX: 2450, maxY: 7900),
         Rect2(minX: 2260, minY: 7900, maxX: 2550, maxY: 8500)],
        // 棘角トカゲの岩の右
        [Rect2(minX: 1600, minY: 5700, maxX: 2100, maxY: 6090)],
        // 左下の岩の右
        [Rect2(minX: 1960, minY: 4390, maxX: 2330, maxY: 4750)],
        // 蒼晶の番人の下
        [Rect2(minX: 2800, minY: 4840, maxX: 3400, maxY: 5170)],
        // 巨像の池の西岸
        [Rect2(minX: 2850, minY: 6800, maxX: 3300, maxY: 7110)],
        // 蒼晶の番人の右
        [Rect2(minX: 3700, minY: 5390, maxX: 4090, maxY: 6000)],
        // 中央の帯（北西側）
        [Rect2(minX: 4690, minY: 6490, maxX: 4980, maxY: 6850),
         Rect2(minX: 4980, minY: 6650, maxX: 5410, maxY: 7100),
         Rect2(minX: 5410, minY: 6900, maxX: 5670, maxY: 7130)],
        // 川の中の草むら（巨像の側）
        [Rect2(minX: 4380, minY: 7440, maxX: 4770, maxY: 7870)],
    ]
}

// MARK: - 検証・デバッグ（テスト用、内部）

extension MapDefinition {
    /// 設計制約の違反一覧（空 = OK）。レーンとの距離・構造物/キャンプの埋没・草むらと障害物の重なり・本拠点周辺。
    func validationIssues() -> [String] {
        var issues: [String] = []
        for (k, o) in obstacles.enumerated() {
            for lane in lanes {
                let d = MapDefinition.distance(from: o, toPolyline: lanePaths[lane.rawValue])
                if d < MapDefinition.laneObstacleClearance {
                    issues.append("obstacle \(k) is \(Int(d)) from lane \(lane)")
                }
            }
            for team in Team.players {
                if o.signedDistance(to: fountain(team)) < MapDefinition.baseClearRadius {
                    issues.append("obstacle \(k) is inside base area of \(team)")
                }
                if o.signedDistance(to: core(team)) < MapDefinition.baseClearRadius {
                    issues.append("obstacle \(k) is too close to core of \(team)")
                }
            }
        }
        for t in towers {
            let r: Double = t.isCore ? 250 : 110
            if let k = obstacleIndex(at: t.pos, inflatedBy: r + 100) {
                issues.append("tower \(t.team) \(String(describing: t.lane)) \(t.tier) overlaps obstacle \(k)")
            }
        }
        for c in camps {
            if let k = obstacleIndex(at: c.pos, inflatedBy: MapDefinition.campClearance(c.kind)) {
                issues.append("camp \(c.id) overlaps obstacle \(k)")
            }
        }
        if let m = bushMask {
            // 格子の草むら: セルの中心が壁の中に入っていないこと（セルは 1 つの草むらにしか属さないので草むら同士は重ならない）
            // 多角形の壁は 1 回の判定が重いので、外接矩形で先に絞る
            let boxes = obstacles.map(\.bounds)
            var reported = Set<Int>()
            for (q, v) in m.cells.enumerated() where v != 0 && !reported.contains(Int(v) - 1) {
                let p = m.center(col: q % m.cols, row: q / m.cols)
                if let k = obstacles.indices.first(where: { boxes[$0].contains(p) && obstacles[$0].contains(p) }) {
                    issues.append("brush \(Int(v) - 1) overlaps obstacle \(k)")
                    reported.insert(Int(v) - 1)
                }
            }
            if m.bushCount != brushes.count { issues.append("bush mask has \(m.bushCount) bushes for \(brushes.count) brushes") }
            return issues
        }
        for b in brushes {
            for (k, o) in obstacles.enumerated() where MapDefinition.rect(b.rect, overlaps: o) {
                issues.append("brush \(b.id) overlaps obstacle \(k)")
            }
            for other in brushes where other.id > b.id && MapDefinition.rect(b.rect, overlaps: .rect(other.rect)) {
                issues.append("brush \(b.id) overlaps brush \(other.id)")
            }
        }
        return issues
    }

    /// キャンプの中心から壁までの最小距離: 最も大きいモンスターの半径 + 40（2026-10-16。MLBB のモンスターは岩のくぼみの巣にいる。
    /// 旧: どのキャンプも 300）。
    static func campClearance(_ kind: CampKind) -> Double {
        var largest = 0.0
        for member in SpawnSystem.campMembers(kind) {
            largest = max(largest, UnitFactory.monsterProfile(member.kind).radius)
        }
        return largest + 40
    }

    /// 障害物と折れ線の最短距離（ユークリッド）。
    static func distance(from o: Obstacle, toPolyline path: [Vec2]) -> Double {
        var best = Double.infinity
        for k in 1..<path.count {
            best = min(best, distance(from: o, toSegment: path[k - 1], path[k]))
        }
        return best
    }

    static func distance(from o: Obstacle, toSegment a: Vec2, _ b: Vec2) -> Double {
        switch o {
        case .circle(let c, let r):
            return max(0, distancePointToSegment(c, a, b) - r)
        case .rect(let rect):
            if segmentIntersectsRect(a, b, rect) { return 0 }
            let corners = [Vec2(rect.minX, rect.minY), Vec2(rect.maxX, rect.minY),
                           Vec2(rect.minX, rect.maxY), Vec2(rect.maxX, rect.maxY)]
            var best = min(a.distance(to: rect.closestPoint(to: a)), b.distance(to: rect.closestPoint(to: b)))
            for q in corners { best = min(best, distancePointToSegment(q, a, b)) }
            return best
        case .polygon(let v):
            // 端点が内部なら 0。そうでなければ各辺との線分どうしの距離の最小（交われば 0）
            let n = v.count
            guard n > 0 else { return .infinity }
            if Obstacle.polygonContains(v, a) || Obstacle.polygonContains(v, b) { return 0 }
            var best = Double.infinity
            for i in 0..<n { best = min(best, segmentDistanceSquared(a, b, v[i], v[i + 1 == n ? 0 : i + 1])) }
            return best.squareRoot()
        }
    }

    /// 線分 a–b と c–d が交わるか（端点での接触・同一直線上の重なりを含む）。
    static func segmentsIntersect(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2) -> Bool {
        let d1 = (d - c).cross(a - c), d2 = (d - c).cross(b - c)
        let d3 = (b - a).cross(c - a), d4 = (b - a).cross(d - a)
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) { return true }
        // 端点が相手の直線上にあるときは、相手の線分の範囲に入っているか
        func within(_ p: Vec2, _ s: Vec2, _ e: Vec2) -> Bool {
            p.x >= min(s.x, e.x) && p.x <= max(s.x, e.x) && p.y >= min(s.y, e.y) && p.y <= max(s.y, e.y)
        }
        return (d1 == 0 && within(a, c, d)) || (d2 == 0 && within(b, c, d))
            || (d3 == 0 && within(c, a, b)) || (d4 == 0 && within(d, a, b))
    }

    /// 線分 a–b と c–d の最短距離の 2 乗（交われば 0）。交わらない線分どうしの最短距離は、どちらかの端点と
    /// もう一方の線分の間にある。
    static func segmentDistanceSquared(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ d: Vec2) -> Double {
        if segmentsIntersect(a, b, c, d) { return 0 }
        func pointToSegment(_ p: Vec2, _ s: Vec2, _ e: Vec2) -> Double {
            p.distanceSquared(to: Obstacle.closestPointOnSegment(p, s, e))
        }
        return min(min(pointToSegment(a, c, d), pointToSegment(b, c, d)), min(pointToSegment(c, a, b), pointToSegment(d, a, b)))
    }

    /// 線分が開いた矩形（境界を含まない）の内部を通るか（スラブ法。境界をなぞる・角に触れるだけは通らない）。
    static func segmentIntersectsOpenRect(_ a: Vec2, _ b: Vec2, _ r: Rect2) -> Bool {
        var t0 = 0.0, t1 = 1.0
        let d = b - a
        let p = [-d.x, d.x, -d.y, d.y]
        let q = [a.x - r.minX, r.maxX - a.x, a.y - r.minY, r.maxY - a.y]
        for k in 0..<4 {
            if p[k] == 0 {
                if q[k] <= 0 { return false }
            } else {
                let t = q[k] / p[k]
                if p[k] < 0 { t0 = max(t0, t) } else { t1 = min(t1, t) }
            }
        }
        return t0 < t1
    }

    /// 線分が矩形（境界含む）と交差するか（スラブ法）。
    static func segmentIntersectsRect(_ a: Vec2, _ b: Vec2, _ r: Rect2) -> Bool {
        var t0 = 0.0, t1 = 1.0
        let d = b - a
        let p = [-d.x, d.x, -d.y, d.y]
        let q = [a.x - r.minX, r.maxX - a.x, a.y - r.minY, r.maxY - a.y]
        for k in 0..<4 {
            if abs(p[k]) < 1e-12 {
                if q[k] < 0 { return false }
            } else {
                let t = q[k] / p[k]
                if p[k] < 0 { t0 = max(t0, t) } else { t1 = min(t1, t) }
                if t0 > t1 { return false }
            }
        }
        return true
    }

    static func rect(_ r: Rect2, overlaps o: Obstacle) -> Bool {
        switch o {
        case .rect(let other):
            return r.minX < other.maxX && other.minX < r.maxX && r.minY < other.maxY && other.minY < r.maxY
        case .circle(let c, let radius):
            return r.closestPoint(to: c).distance(to: c) < radius
        case .polygon(let v):
            // 開いた矩形と多角形の内部が重なる ⇔ 多角形の辺が矩形の内部を通る（矩形の角が多角形の中・多角形の頂点が
            // 矩形の中・辺の交差はどれもこれに当たる）か、矩形が多角形の中にすっぽり入っている（中心が内部）
            let n = v.count
            for i in 0..<n where segmentIntersectsOpenRect(v[i], v[i + 1 == n ? 0 : i + 1], r) { return true }
            return n >= 3 && Obstacle.polygonContains(v, r.center)
        }
    }

    /// マップを ASCII で描画する（上が +y）。
    /// `#` 障害物 `"` 草むら `=` レーン `~` 河川 `T` タワー `C` Core `F` 泉 `c` キャンプ `B` ボス `.` 地面
    func debugASCII(cellSize: Double = 200) -> String {
        let n = Int((size / cellSize).rounded(.up))
        var grid = [[Character]](repeating: [Character](repeating: ".", count: n), count: n)
        func cell(_ p: Vec2) -> (Int, Int) {
            (min(n - 1, max(0, Int(p.x / cellSize))), min(n - 1, max(0, Int(p.y / cellSize))))
        }
        for r in 0..<n {
            for c in 0..<n {
                let p = Vec2((Double(c) + 0.5) * cellSize, (Double(r) + 0.5) * cellSize)
                var ch: Character = "."
                if isInRiver(p) { ch = "~" }
                if nearestLane(to: p).distance <= cellSize * 0.75 { ch = "=" }
                if brushIndex(at: p) != nil { ch = "\"" }
                if obstacleIndex(at: p) != nil { ch = "#" }
                grid[r][c] = ch
            }
        }
        for team in Team.players {
            let (c, r) = cell(fountain(team)); grid[r][c] = "F"
        }
        for camp in camps {
            let (c, r) = cell(camp.pos)
            grid[r][c] = camp.side == .neutral ? "B" : "c"
        }
        for t in towers {
            let (c, r) = cell(t.pos)
            grid[r][c] = t.isCore ? "C" : "T"
        }
        return grid.reversed().map { String($0) }.joined(separator: "\n")
    }
}
