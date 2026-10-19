import Foundation

extension MapDefinition {
    /// Player timings: spawn→mid 22→18 s, mid→side wall 20→16 s.
    /// 0.81 is the compromise between 18/22 and 16/20; keep gameplay stats fixed.
    /// 2026-10-19: 添付26画面から起こした壁・川・キャンプ・草むらを既定にする。
    /// 反対側は180度回転。草むらの描画・隠蔽判定は共通の16.2cm格子。
    static func makeCompactRelayout() -> MapDefinition {
        var copy = standard
        let k = 0.81
        copy.size = 9_720
        copy.fountains = copy.fountains.map { $0 * k }
        copy.cores = copy.cores.map { $0 * k }
        copy.lanePaths = copy.lanePaths.map { $0.map { $0 * k } }
        for i in copy.towers.indices { copy.towers[i].pos *= k }
        copy.riverWidth *= k
        for i in copy.camps.indices { copy.camps[i].pos *= k }
        // All October 19 views define the default terrain, including boss surroundings.
        copy.applyReferenceLayout()
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
