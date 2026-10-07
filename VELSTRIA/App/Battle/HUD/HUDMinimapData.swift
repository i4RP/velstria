import Foundation
import VelstriaCore

/// The same inset and world extent are used by terrain, markers, camera outline and gestures.
struct HUDMinimapProjection: Equatable {
    let size: CGFloat
    var mapSize: Double = Balance.mapSize
    var inset: CGFloat = 0

    private var extent: Double { mapSize.isFinite && mapSize > 0 ? mapSize : Balance.mapSize }
    private var padding: CGFloat { min(max(0, inset), max(0, size / 2)) }
    private var span: CGFloat { max(0, size - padding * 2) }

    func point(_ p: Vec2) -> CGPoint {
        guard p.x.isFinite, p.y.isFinite else { return CGPoint(x: size / 2, y: size / 2) }
        return CGPoint(x: padding + CGFloat(p.x / extent) * span,
                       y: padding + CGFloat(1 - p.y / extent) * span)
    }

    func world(_ q: CGPoint) -> Vec2 {
        guard span > 0, q.x.isFinite, q.y.isFinite else { return Vec2(extent / 2, extent / 2) }
        let x = min(1, max(0, Double((q.x - padding) / span))) * extent
        let y = (1 - min(1, max(0, Double((q.y - padding) / span)))) * extent
        return Vec2(x, y)
    }

    func length(_ units: Double) -> CGFloat { CGFloat(units / extent) * span }

    /// Clip edges, rather than independently clamping corners: perspective views can cross a map corner.
    func clippedPolygon(_ vertices: [Vec2]) -> [Vec2] {
        guard vertices.count >= 3, vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return [] }
        var polygon = vertices
        let boundaries: [(Vec2) -> Double] = [
            { $0.x }, { extent - $0.x }, { $0.y }, { extent - $0.y },
        ]
        for distance in boundaries {
            guard let last = polygon.last else { return [] }
            var clipped: [Vec2] = []
            var previous = last
            var previousDistance = distance(previous)
            for current in polygon {
                let currentDistance = distance(current)
                if (currentDistance >= 0) != (previousDistance >= 0) {
                    let t = previousDistance / (previousDistance - currentDistance)
                    clipped.append(Vec2.lerp(previous, current, t))
                }
                if currentDistance >= 0 { clipped.append(current) }
                previous = current
                previousDistance = currentDistance
            }
            polygon = clipped
        }
        return polygon
    }
}

/// Reused storage keeps the minimap independent from the heavier HUD snapshots.
final class HUDMinimapBuffer {
    struct Dot {
        var pos: Vec2
        var team: Team
        var kind: UnitKind
        var hue: Double
        var isHuman: Bool
        var isFocus: Bool
        /// Current sightings are opaque; last-known positions fade without following hidden enemies.
        var alpha: Double
        var heroID: String? = nil
        var facing: Vec2? = nil
        var visionRadius: Double = 0
    }

    struct Structure {
        var pos: Vec2
        var team: Team
        var alive: Bool
        var isCore: Bool
        var hpFraction: Double = 1
    }

    struct Camp {
        var pos: Vec2
        var alive: Bool
        var isBoss: Bool
        var kind: CampKind? = nil
        var respawnRemaining: Double? = nil
    }

    /// クイックシグナルのピン（HUDSignalCenter が書き込む。ミニマップと全体マップの両方に描く）。
    struct Ping: Equatable {
        var pos: Vec2
        var kind: HUDSignalKind
        /// 作成時刻（HUD の時計 = systemUptime）。
        var createdAt: TimeInterval
    }

    var units: [Dot] = []
    var heroes: [Dot] = []
    var structures: [Structure] = []
    var camps: [Camp] = []
    var pings: [Ping] = []
    /// ピンの経過時間の基準（ピンがある間だけ HUDSignalCenter が 15Hz で進める）。
    var pingClock: TimeInterval = 0
    var mapSize: Double = Balance.mapSize
    var viewportPolygon: [Vec2] = []
    var vision = VisionState()
    var colorblind = false
    var viewerTeam: Team? = .blue
}
