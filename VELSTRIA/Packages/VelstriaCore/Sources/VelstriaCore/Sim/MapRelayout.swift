import Foundation

extension MapDefinition {
    /// Player timings: spawn→mid 22→18 s, mid→side wall 20→16 s.
    /// 0.81 is the compromise between 18/22 and 16/20; keep gameplay stats fixed.
    /// 2026-10-16: 壁（岩）とキャンプは MLBB のミニマップ原本から起こした形（MapSanctumTerrain.swift、tools/map_proto/trace_terrain.mjs）、
    /// 草むらは同じ原本の細かい格子（BushMask.sanctum）を、地図と同じ倍率で縮めて入れる（形と通路の幅の比率が MLBB のまま。docs/DESIGN.md §2.1）。
    static func makeCompactRelayout() -> MapDefinition {
        var copy = standard
        let k = 0.81
        copy.size = 9_720
        copy.fountains = copy.fountains.map { $0 * k }
        copy.cores = copy.cores.map { $0 * k }
        copy.lanePaths = copy.lanePaths.map { $0.map { $0 * k } }
        for i in copy.towers.indices { copy.towers[i].pos *= k }
        copy.riverWidth *= k
        copy.obstacles = sanctumObstacles(scale: k)
        // 草むら: 細かい格子を縮め、壁（上の多角形）に重なるセルを除く。壁を先に入れること
        copy.applySanctumBushes(scale: k)
        precondition(copy.camps.count == sanctumRelayoutCampPositions.count, "キャンプの数が地形の生成と合わない")
        for i in copy.camps.indices { copy.camps[i].pos = sanctumRelayoutCampPositions[i] }
        return copy
    }

    /// 壁: Blue 半面の制御点 → 点対称の Red 半面 → 中心の壁の順に、standard の座標で写してから k 倍し、
    /// 1 mm（0.1 ユニット）の精度で滑らかな多角形にする。
    static func sanctumObstacles(scale k: Double) -> [Obstacle] {
        let s = Balance.mapSize
        let blue = sanctumBlueWallSplines
        let red = blue.map { $0.map { Vec2(s - $0.x, s - $0.y) } }
        return (blue + red + sanctumCenterWallSplines).map { control in
            Obstacle.smoothPolygon(control.map { $0 * k }, tolerance: sanctumSplineTolerance, maxSegment: sanctumSplineMaxSegment)
        }
    }
}
