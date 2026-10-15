import Foundation

extension MapDefinition {
    /// Player timings: spawn→mid 22→18 s, mid→side wall 20→16 s.
    /// 0.81 is the compromise between 18/22 and 16/20; keep gameplay stats fixed.
    static func makeCompactRelayout() -> MapDefinition {
        var copy = standard
        let k = 0.81
        copy.size = 9_720
        copy.fountains = copy.fountains.map { $0 * k }
        copy.cores = copy.cores.map { $0 * k }
        copy.lanePaths = copy.lanePaths.map { $0.map { $0 * k } }
        for i in copy.towers.indices { copy.towers[i].pos *= k }
        for i in copy.camps.indices { copy.camps[i].pos *= k }
        copy.riverWidth *= k

        // Individually fitted wall centers, in original index order. Dimensions stay unchanged.
        let centers: [Vec2] = [
            Vec2(1275.75, 2966.00),
            Vec2(1236.50, 6905.25),
            Vec2(1336.50, 5007.05),
            Vec2(1352.70, 3847.50),
            Vec2(1356.75, 2955.25),
            Vec2(1474.20, 6607.50),
            Vec2(1539.00, 5943.45),
            Vec2(1644.30, 3426.30),
            Vec2(1660.50, 2943.25),
            Vec2(2130.30, 4317.30),
            Vec2(2227.50, 6054.75),
            Vec2(2288.25, 4238.95),
            Vec2(2324.00, 3341.25),
            Vec2(2373.30, 5856.30),
            Vec2(2531.25, 5117.25),
            Vec2(2577.75, 3593.75),
            Vec2(3038.50, 1456.75),
            Vec2(2859.30, 4828.30),
            Vec2(2895.75, 5629.50),
            Vec2(3015.30, 1127.30),
            Vec2(3133.30, 2161.30),
            Vec2(3230.50, 4164.80),
            Vec2(3345.30, 2454.30),
            Vec2(3388.45, 4322.75),
            Vec2(3557.30, 1725.30),
            Vec2(3507.30, 2722.30),
            Vec2(3511.35, 4590.75),
            Vec2(3588.30, 1482.30),
            Vec2(3669.30, 5289.30),
            Vec2(3786.75, 5127.30),
            Vec2(3993.30, 3102.30),
            Vec2(3993.30, 4965.30),
            Vec2(4388.25, 3261.50),
            Vec2(4353.75, 1215.00),
            Vec2(4469.25, 3246.00),
            Vec2(4884.30, 1239.30),
            Vec2(4945.75, 4106.00),
            Vec2(5016.00, 2006.00),
            Vec2(5046.30, 4043.30),
            Vec2(5163.75, 3843.45),
            Vec2(5385.25, 2685.15),
            Vec2(5305.50, 3742.20),
            Vec2(5451.30, 3588.30),
            Vec2(5730.75, 1230.50),
            Vec2(5852.25, 2241.75),
            Vec2(7062.50, 1260.25),
            Vec2(7255.50, 1459.40),
            Vec2(-283.50, 8389.17),
            Vec2(121.50, 8794.17),
            Vec2(526.50, 9199.17),
            Vec2(931.50, 9604.17),
            Vec2(1336.50, 10009.17),
            Vec2(-69.00, 9789.00),
        ]
        func mirror(_ p: Vec2) -> Vec2 { Vec2(copy.size - p.x, copy.size - p.y) }
        for i in copy.obstacles.indices {
            let c = i < centers.count ? centers[i] : mirror(centers[i - centers.count])
            switch standard.obstacles[i] {
            case .circle(_, let radius):
                copy.obstacles[i] = .circle(center: c, radius: radius)
            case .rect(let r):
                copy.obstacles[i] = .rect(Rect2(minX: c.x - r.width / 2, minY: c.y - r.height / 2,
                                               maxX: c.x + r.width / 2, maxY: c.y + r.height / 2))
            }
        }

        // 草むら: MLBB のミニマップの形の細かい格子（BushMask.sanctum）を地図と同じ倍率で縮め、壁に重なるセルを除く
        copy.applySanctumBushes(scale: k)
        return copy
    }
}
