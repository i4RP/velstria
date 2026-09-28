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

public struct MapDefinition: Codable, Hashable, Sendable {
    public var size: Double
    /// index = Team.rawValue
    public var fountains: [Vec2]
    /// index = Team.rawValue
    public var cores: [Vec2]
    /// Blue 視点のレーン経路（Blue Core → Red Core）。index = Lane.rawValue
    public var lanePaths: [[Vec2]]
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
        brushes.firstIndex { $0.rect.contains(p) }
    }

    /// 河川（x + y = size の帯）上か。
    public func isInRiver(_ p: Vec2) -> Bool {
        abs(p.x + p.y - size) / 2.0.squareRoot() <= riverWidth / 2
    }
}

extension MapDefinition {
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

        return MapDefinition(
            size: Balance.mapSize,
            fountains: [blueFountain, blueFountain.mirrored],
            cores: [blueCore, redCore],
            lanePaths: [top, mid, bot],
            towers: towers,
            camps: camps,
            brushes: [],     // core-world が設計
            obstacles: [],   // core-world が設計
            riverWidth: 900
        )
    }()
}
