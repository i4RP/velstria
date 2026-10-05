import Foundation

// 担当: core-world（草むら・障害物・河川の詳細設計はこのファイルで行う）。
// タワー / Core / 泉 / レーン経路 / キャンプの座標は docs/DESIGN.md §2 の値を維持すること。

public struct TowerSpot: Codable, Hashable, Sendable {
    public var team: Team
    /// Core は nil。
    public var lane: Lane?
    public var tier: TowerTier
    public var pos: Vec2
    public var isCore: Bool
}

public enum CampKind: Int, Codable, Hashable, Sendable {
    case small
    case blueSentinel
    case redSentinel
    case astralWyrm
    case ancientColossus
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
}

public enum Obstacle: Codable, Hashable, Sendable {
    case rect(Rect2)
    case circle(center: Vec2, radius: Double)

    public func contains(_ p: Vec2, inflatedBy r: Double = 0) -> Bool {
        switch self {
        case .rect(let rect):
            return rect.expanded(by: r).contains(p)
        case .circle(let c, let radius):
            return p.distanceSquared(to: c) <= (radius + r) * (radius + r)
        }
    }
}

extension Obstacle {
    /// 点から障害物までの符号付き距離（内部は負）。
    /// 矩形は `contains(_:inflatedBy:)` と一致させるため L∞ 距離（角も四角く膨張）で測る。
    /// `signedDistance(p) <= r` ⇔ `contains(p, inflatedBy: r)`。
    public func signedDistance(to p: Vec2) -> Double {
        switch self {
        case .rect(let r):
            return max(max(r.minX - p.x, p.x - r.maxX), max(r.minY - p.y, p.y - r.maxY))
        case .circle(let c, let radius):
            return p.distance(to: c) - radius
        }
    }

    /// 外接矩形。
    public var bounds: Rect2 {
        switch self {
        case .rect(let r): return r
        case .circle(let c, let radius):
            return Rect2(minX: c.x - radius, minY: c.y - radius, maxX: c.x + radius, maxY: c.y + radius)
        }
    }

    /// 点における外向き法線（最も近い面の向き）。
    public func outwardNormal(at p: Vec2) -> Vec2 {
        switch self {
        case .rect(let r):
            let d = [r.minX - p.x, p.x - r.maxX, r.minY - p.y, p.y - r.maxY]
            let normals = [Vec2(-1, 0), Vec2(1, 0), Vec2(0, -1), Vec2(0, 1)]
            var best = 0
            for k in 1..<4 where d[k] > d[best] { best = k }
            return normals[best]
        case .circle(let c, _):
            let n = (p - c).normalized
            return n == .zero ? Vec2(1, 0) : n
        }
    }

    /// 中心 (6000,6000) に対する点対称写像（Blue 側の定義 → Red 側）。
    public var mirrored: Obstacle {
        switch self {
        case .rect(let r): return .rect(r.mirrored)
        case .circle(let c, let radius): return .circle(center: c.mirrored, radius: radius)
        }
    }

    /// y = x に関する鏡映（Blue の下側ジャングル → 上側ジャングル）。
    var reflectedAcrossDiagonal: Obstacle {
        switch self {
        case .rect(let r): return .rect(Rect2(minX: r.minY, minY: r.minX, maxX: r.maxY, maxY: r.maxX))
        case .circle(let c, let radius): return .circle(center: Vec2(c.y, c.x), radius: radius)
        }
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

    /// 点を含む草むらの添字。
    public func brushIndex(at p: Vec2) -> Int? {
        for k in brushes.indices where brushes[k].rect.contains(p) { return k }
        return nil
    }

    /// 河川（x + y = size の帯）上か。
    public func isInRiver(_ p: Vec2) -> Bool {
        abs(p.x + p.y - size) / 2.0.squareRoot() <= riverWidth / 2
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
    static let baseClearRadius: Double = 1800

    public static let standard: MapDefinition = {
        let blueFountain = Vec2(700, 700)
        let blueCore = Vec2(1500, 1500)
        let redCore = blueCore.mirrored

        let top: [Vec2] = [blueCore, Vec2(1400, 2400), Vec2(1400, 10600), Vec2(9600, 10600), redCore]
        let mid: [Vec2] = [blueCore, Vec2(2300, 2300), Vec2(9700, 9700), redCore]
        let bot: [Vec2] = [blueCore, Vec2(2400, 1400), Vec2(10600, 1400), Vec2(10600, 9600), redCore]

        // Blue タワー（レーン, 外/内/基部）
        let blueTowerPos: [Lane: [Vec2]] = [
            .top: [Vec2(1400, 7000), Vec2(1400, 4800), Vec2(1400, 3000)],
            .mid: [Vec2(4300, 4300), Vec2(3400, 3400), Vec2(2600, 2600)],
            .bot: [Vec2(7000, 1400), Vec2(4800, 1400), Vec2(3000, 1400)],
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

        // キャンプ（Blue 側 → Red 側は写像、ボスは中立）
        let blueCamps: [(CampKind, Vec2)] = [
            (.blueSentinel, Vec2(3300, 6300)),
            (.redSentinel, Vec2(6300, 3300)),
            (.small, Vec2(2800, 5000)),
            (.small, Vec2(4700, 5800)),
            (.small, Vec2(5000, 2800)),
            (.small, Vec2(5800, 4700)),
        ]
        var camps: [CampSpot] = []
        func respawn(_ k: CampKind) -> Double {
            switch k {
            case .small: return 60
            case .blueSentinel, .redSentinel: return 90
            case .astralWyrm: return 240
            case .ancientColossus: return 300
            }
        }
        for (k, p) in blueCamps {
            camps.append(CampSpot(id: camps.count, side: .blue, kind: k, pos: p, firstSpawn: 30, respawn: respawn(k)))
        }
        for (k, p) in blueCamps {
            camps.append(CampSpot(id: camps.count, side: .red, kind: k, pos: p.mirrored, firstSpawn: 30, respawn: respawn(k)))
        }
        camps.append(CampSpot(id: camps.count, side: .neutral, kind: .astralWyrm, pos: Vec2(8300, 3700),
                              firstSpawn: 120, respawn: respawn(.astralWyrm)))
        camps.append(CampSpot(id: camps.count, side: .neutral, kind: .ancientColossus, pos: Vec2(3700, 8300),
                              firstSpawn: 480, respawn: respawn(.ancientColossus)))

        // 障害物・草むら: Blue 陣地の下側ジャングル（y < x、bot レーンと mid レーンの間）を定義し、
        // y = x の鏡映で上側ジャングルを作り（Blue 半面）、点対称で Red 半面を作る。
        let blueHalfObstacles = standardBotJungleObstacles + standardBotJungleObstacles.map(\.reflectedAcrossDiagonal)
        let obstacles = blueHalfObstacles + blueHalfObstacles.map(\.mirrored)

        let blueHalfBrushes = standardBotJungleBrushes + standardBotJungleBrushes.map {
            Rect2(minX: $0.minY, minY: $0.minX, maxX: $0.maxY, maxY: $0.maxX)
        }
        let brushRects = blueHalfBrushes + blueHalfBrushes.map(\.mirrored)
        let brushes = brushRects.enumerated().map { BrushArea(id: $0.offset, rect: $0.element) }

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

    /// モードに応じたマップ（`config.mode` から決定論的に導出する。リプレイはマップを保存しないため、
    /// `Simulation` を組む全箇所でこれを使うこと）。マジックチェスは専用の `magicChessBoard` を直接使う。
    public static func map(for mode: MatchMode) -> MapDefinition {
        mode == .brawl ? .brawl : .standard
    }

    /// 乱闘マップ（単レーン・ジャングル無し）。mid の対角 1 本だけを使う 5v5。
    /// `lanePaths` は 3 要素（top=bot=mid）を保ちつつ `lanes=[.mid]` で挙動を制限する。
    /// 障害物・キャンプは置かず、検証（laneObstacleClearance/baseClearRadius）を確実に通す。
    public static let brawl: MapDefinition = {
        let blueFountain = Vec2(700, 700)
        let blueCore = Vec2(1500, 1500)
        let redCore = blueCore.mirrored
        let mid: [Vec2] = [blueCore, Vec2(2300, 2300), Vec2(9700, 9700), redCore]

        // mid 3 tier を両チーム分 + コア。
        let blueMidTowers = [Vec2(4300, 4300), Vec2(3400, 3400), Vec2(2600, 2600)]
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

    /// Blue 下側ジャングルの壁（10 個 × 4 = 40 個）。
    /// 通路: bot レーン→小キャンプ(5000,2800)、小→紅焔の番人(6300,3300)、番人→小(5800,4700)→mid/河川、
    ///       番人→星喰竜の巣(8300,3700) の南西口、bot レーン→巣の南口（外塔の先）、泉側からの裏口。
    static let standardBotJungleObstacles: [Obstacle] = [
        // 本拠点寄りの岩（裏口と mid からの入口を分ける）
        .circle(center: Vec2(3600, 2500), radius: 320),
        // bot レーンと番人・小キャンプを隔てる長い壁
        .rect(Rect2(minX: 5300, minY: 1950, maxX: 6900, maxY: 2450)),
        // mid 側の中央壁（小キャンプ2つと番人の間）
        .rect(Rect2(minX: 4700, minY: 3350, maxX: 5750, maxY: 3900)),
        // 番人の北東壁（兼 竜の巣の西壁）
        .rect(Rect2(minX: 6700, minY: 3700, maxX: 7400, maxY: 4200)),
        // 竜の巣の南壁
        .circle(center: Vec2(8300, 2800), radius: 300),
        // bot 河口の岩
        .circle(center: Vec2(9000, 2150), radius: 200),
        // 河川寄りの岩（小キャンプ(5800,4700) の河川側）
        .circle(center: Vec2(6400, 4900), radius: 200),
        // 外塔の先のジャングル入口を二分する岩
        .circle(center: Vec2(7700, 2300), radius: 230),
        // mid 入口の柱（小キャンプ(5000,2800) の北西）
        .rect(Rect2(minX: 4050, minY: 2800, maxX: 4450, maxY: 3100)),
        // 番人と河川小キャンプの間の柱
        .rect(Rect2(minX: 6100, minY: 4050, maxX: 6400, maxY: 4300)),
    ]

    /// Blue 下側ジャングルの草むら（6 個 × 4 = 24 個）。
    static let standardBotJungleBrushes: [Rect2] = [
        // bot レーン脇（河川との交差付近）
        Rect2(minX: 9300, minY: 1800, maxX: 9800, maxY: 2100),
        // 河川（竜の巣の北西口）
        Rect2(minX: 7250, minY: 4250, maxX: 7550, maxY: 4450),
        // mid レーン脇（河川との交差付近）
        Rect2(minX: 5900, minY: 5150, maxX: 6250, maxY: 5450),
        // bot レーンからのジャングル入口
        Rect2(minX: 4250, minY: 1900, maxX: 4600, maxY: 2250),
        // 番人の東（竜の巣へ抜ける通路）
        Rect2(minX: 6750, minY: 2800, maxX: 7100, maxY: 3150),
        // mid 側入口（河川小キャンプの手前）
        Rect2(minX: 5150, minY: 4150, maxX: 5500, maxY: 4400),
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
            if let k = obstacleIndex(at: c.pos, inflatedBy: 300) {
                issues.append("camp \(c.id) overlaps obstacle \(k)")
            }
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
        }
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
