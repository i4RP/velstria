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
    static let baseClearRadius: Double = 1800

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

        // キャンプ: ミニマップのアイコンから測った位置（誤差 数十）。ゲーム側の配置は厳密な点対称ではないので、
        // Red 側も測った値をそのまま使う（Blue 側の写像とのずれは最大 約 100）。ボスと川の中立は中立。
        // Blue: 西のジャングル（左レーンと mid の間）に蒼晶の番人と小 2、南のジャングル（下レーンと mid の間）に紅焔の番人と小 3。
        let blueCamps: [(CampKind, Vec2)] = [
            (.blueSentinel, Vec2(3075, 5755)),
            (.redSentinel, Vec2(5609, 2627)),
            (.small, Vec2(1994, 6821)),
            (.small, Vec2(2578, 6632)),
            (.small, Vec2(6095, 3184)),
            (.small, Vec2(6645, 2401)),
            (.small, Vec2(7480, 2235)),
        ]
        // Red: 東のジャングル（Blue の西の対）に蒼晶の番人と小 2、北のジャングル（Blue の南の対）に紅焔の番人と小 3。
        let redCamps: [(CampKind, Vec2)] = [
            (.blueSentinel, Vec2(9089, 6224)),
            (.redSentinel, Vec2(6370, 9366)),
            (.small, Vec2(10096, 5158)),
            (.small, Vec2(9424, 5368)),
            (.small, Vec2(5905, 8820)),
            (.small, Vec2(5358, 9597)),
            (.small, Vec2(4613, 9859)),
        ]
        var camps: [CampSpot] = []
        func respawn(_ k: CampKind) -> Double {
            switch k {
            // 参照仕様（REFERENCE_SPEC §3.3）: 小キャンプもバフも再出現 90 秒（以前は小 60 秒）。
            case .small, .blueSentinel, .redSentinel: return 90
            // 序盤ボス 120 秒・後半ボス 180 秒（参照仕様 §5.1・§5.3。旧: 240 / 300 秒）
            case .astralWyrm: return 120
            case .ancientColossus: return 180
            }
        }
        for (k, p) in blueCamps {
            camps.append(CampSpot(id: camps.count, side: .blue, kind: k, pos: p, firstSpawn: 30, respawn: respawn(k)))
        }
        for (k, p) in redCamps {
            camps.append(CampSpot(id: camps.count, side: .red, kind: k, pos: p, firstSpawn: 30, respawn: respawn(k)))
        }
        camps.append(CampSpot(id: camps.count, side: .neutral, kind: .astralWyrm, pos: Vec2(8260, 3590),
                              firstSpawn: 120, respawn: respawn(.astralWyrm)))
        camps.append(CampSpot(id: camps.count, side: .neutral, kind: .ancientColossus, pos: Vec2(3740, 8410),
                              firstSpawn: 480, respawn: respawn(.ancientColossus)))
        // 川の中立（片側のみ: 古環の巨像の巣の側）。参照仕様 §3.3 / §5.1: 約 0:45 に出現、再出現 2 分。
        camps.append(CampSpot(id: camps.count, side: .neutral, kind: .small, pos: Vec2(4710, 7285),
                              firstSpawn: 45, respawn: 120))

        // 障害物・草むら: Blue 陣地（西と南のジャングル + 左上の角）を定義し、点対称で Red 半面を作る。
        // 角（左上）の写像が右下の角になる。
        let blueHalfObstacles = standardBlueJungleObstacles + standardCornerObstacles
        let obstacles = blueHalfObstacles + blueHalfObstacles.map(\.mirrored)

        let brushRects = standardBlueBrushes + standardBlueBrushes.map(\.mirrored)
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

    /// Blue 陣地（西と南のジャングル）の壁（48 個 × 2）。ミニマップの暗い塊を抽出して円と矩形で当てはめた
    /// （`tools/map_proto/fitwalls.mjs`。制約: レーンから 400・キャンプから 330・タワーから 250・Core から 1900・ボスの巣から 1100）。
    /// Red 側は点対称。`validationIssues` の制約（レーン 350・キャンプ 300・タワー 210）を満たす。
    static let standardBlueJungleObstacles: [Obstacle] = [
        .rect(Rect2(minX: 1400, minY: 3450, maxX: 1750, maxY: 3750)),
        .rect(Rect2(minX: 1400, minY: 7950, maxX: 1900, maxY: 9100)),
        .rect(Rect2(minX: 1400, minY: 6000, maxX: 1900, maxY: 6500)),
        .rect(Rect2(minX: 1400, minY: 3400, maxX: 1950, maxY: 3650)),
        .rect(Rect2(minX: 1400, minY: 4250, maxX: 2050, maxY: 5250)),
        .rect(Rect2(minX: 1600, minY: 7150, maxX: 2200, maxY: 7400)),
        .rect(Rect2(minX: 1400, minY: 8000, maxX: 2450, maxY: 8500)),
        .circle(center: Vec2(2030, 4230), radius: 150),
        .rect(Rect2(minX: 1850, minY: 3200, maxX: 2250, maxY: 3450)),
        .circle(center: Vec2(2630, 5330), radius: 100),
        .rect(Rect2(minX: 2600, minY: 7200, maxX: 2900, maxY: 7750)),
        .rect(Rect2(minX: 2650, minY: 5100, maxX: 3000, maxY: 5400)),
        .rect(Rect2(minX: 2700, minY: 3900, maxX: 3100, maxY: 4350)),
        .circle(center: Vec2(2930, 7230), radius: 250),
        .rect(Rect2(minX: 2900, minY: 6100, maxX: 3350, maxY: 6350)),
        .rect(Rect2(minX: 2950, minY: 4200, maxX: 3600, maxY: 4550)),
        .rect(Rect2(minX: 3150, minY: 1150, maxX: 3550, maxY: 2200)),
        .circle(center: Vec2(3530, 5930), radius: 100),
        .rect(Rect2(minX: 3450, minY: 6800, maxX: 3700, maxY: 7100)),
        .circle(center: Vec2(3630, 1330), radius: 200),
        .circle(center: Vec2(3930, 2730), radius: 150),
        .rect(Rect2(minX: 3900, minY: 4800, maxX: 4200, maxY: 5400)),
        .circle(center: Vec2(4130, 3030), radius: 350),
        .rect(Rect2(minX: 4000, minY: 4950, maxX: 4350, maxY: 5600)),
        .rect(Rect2(minX: 4100, minY: 5450, maxX: 4550, maxY: 5700)),
        .circle(center: Vec2(4330, 2130), radius: 300),
        .circle(center: Vec2(4330, 3330), radius: 100),
        .circle(center: Vec2(4430, 1830), radius: 100),
        .circle(center: Vec2(4530, 6530), radius: 150),
        .rect(Rect2(minX: 4550, minY: 6200, maxX: 4800, maxY: 6550)),
        .circle(center: Vec2(4930, 3830), radius: 250),
        .circle(center: Vec2(4930, 6130), radius: 200),
        .rect(Rect2(minX: 5000, minY: 3850, maxX: 5650, maxY: 4450)),
        .rect(Rect2(minX: 4750, minY: 1300, maxX: 6000, maxY: 1700)),
        .rect(Rect2(minX: 4900, minY: 3900, maxX: 5950, maxY: 4300)),
        .circle(center: Vec2(6030, 1530), radius: 100),
        .rect(Rect2(minX: 5900, minY: 4950, maxX: 6250, maxY: 5250)),
        .rect(Rect2(minX: 5950, minY: 2350, maxX: 6250, maxY: 2850)),
        .circle(center: Vec2(6230, 4930), radius: 200),
        .rect(Rect2(minX: 6200, minY: 4650, maxX: 6550, maxY: 4950)),
        .rect(Rect2(minX: 6400, minY: 3050, maxX: 6650, maxY: 3650)),
        .rect(Rect2(minX: 6400, minY: 4500, maxX: 6700, maxY: 4800)),
        .circle(center: Vec2(6730, 4430), radius: 100),
        .rect(Rect2(minX: 6600, minY: 1350, maxX: 7550, maxY: 1750)),
        .rect(Rect2(minX: 6950, minY: 2550, maxX: 7500, maxY: 2800)),
        .rect(Rect2(minX: 8150, minY: 1400, maxX: 9350, maxY: 1650)),
        .circle(center: Vec2(8930, 2130), radius: 100),
        .rect(Rect2(minX: 8650, minY: 1400, maxX: 9450, maxY: 2100)),
    ]

    /// 左上の角を 45° に切る壁（円の連なり）。点対称の写像が右下の角になる。
    /// レーンの斜めの区間（(700,9400)→(2600,11300)）から 550 以上離す。
    static let standardCornerObstacles: [Obstacle] = [
        .circle(center: Vec2(150, 10450), radius: 500),
        .circle(center: Vec2(750, 11050), radius: 500),
        .circle(center: Vec2(250, 11650), radius: 500),
        .circle(center: Vec2(1350, 11650), radius: 500),
        .circle(center: Vec2(1900, 12100), radius: 500),
    ]

    /// Blue 陣地の草むら（12 個 × 2）。レーン脇・河川・番人の近く（ミニマップに草むらは出ないので位置は設計）。
    static let standardBlueBrushes: [Rect2] = [
        Rect2(minX: 1000, minY: 7600, maxX: 1400, maxY: 8200),
        Rect2(minX: 1000, minY: 4800, maxX: 1400, maxY: 5400),
        Rect2(minX: 4900, minY: 7000, maxX: 5300, maxY: 7300),
        Rect2(minX: 2600, minY: 3100, maxX: 3000, maxY: 3450),
        Rect2(minX: 1950, minY: 5400, maxX: 2250, maxY: 5750),
        Rect2(minX: 3700, minY: 6300, maxX: 4100, maxY: 6600),
        Rect2(minX: 5500, minY: 1000, maxX: 6000, maxY: 1250),
        Rect2(minX: 8000, minY: 1000, maxX: 8500, maxY: 1250),
        Rect2(minX: 4550, minY: 2800, maxX: 4850, maxY: 3150),
        Rect2(minX: 7150, minY: 4350, maxX: 7450, maxY: 4650),
        Rect2(minX: 5500, minY: 3500, maxX: 5900, maxY: 3800),
        Rect2(minX: 7800, minY: 2100, maxX: 8200, maxY: 2400),
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
