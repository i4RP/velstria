import Foundation

// 担当: core-skills（キット層。docs/SKILL_KITS.md）
// 地形を越える跳躍（壁を跳び越す経路ヒット突進）。`Kit.dashSweeping`（KitMovement.swift）は壁の手前で止まるが、
// こちらは着地点が歩ける場所なら途中の壁を素通りして直線で跳ぶ（MLBB の跳躍。H033 の裂地撃）。
// 変位は突進（`kind: .dash`）のまま: ノックアップ・制圧で止まり、スタンでは止まらない。壁の無いところでは `dashSweeping` と同じ。

extension Kit {
    /// 地形を越える跳躍の着地点。from → to の照準の線の上で決める（マップの外・壁の中・始点から歩いて行けない閉じた区画には降りない）。
    /// - 途中に壁が無い: `NavGrid.raycast` と同じ点（従来の突進と同じ。マップの外を狙ったら端の手前）。
    /// - 途中に壁があり、照準の点に降りられる: 照準の点（壁を越える）。
    /// - 照準の点が壁の中: 照準の線の上で、照準の点に近い側の縁。手前（始点の側）と向こう側（照準の点から farReach まで）を比べ、
    ///   向こう側が同じか近ければ向こう側（照準の点が壁の半ばを越えている）、そうでなければ手前。手前の縁が最初の壁の手前なら raycast と同じ点。
    /// - 降りられる点が無い（始点が壁の中など）: raycast と同じ。
    /// overTerrain = 直進（raycast）と違う点に降りる = 途中の壁を越える。false のときの point は raycast の結果そのもの。
    static func leapLanding(_ nav: NavGrid, from: Vec2, to: Vec2, radius: Double,
                            farReach: Double) -> (point: Vec2, overTerrain: Bool) {
        let r = max(0, radius)
        let straight = nav.raycast(from: from, to: to, radius: r)
        let a = nav.clampToMap(from, radius: r)
        let d = to - a
        let len = d.length
        guard len > 1e-9 else { return (straight, false) }
        let dir = d / len
        // 照準の線がマップの端（[r, size − r] の箱）から出る距離（raycast の箱の判定と同じ式）
        let lo = r, hi = nav.map.size - r
        var edge = Double.infinity
        if dir.x > 0 { edge = min(edge, (hi - a.x) / dir.x) } else if dir.x < 0 { edge = min(edge, (lo - a.x) / dir.x) }
        if dir.y > 0 { edge = min(edge, (hi - a.y) / dir.y) } else if dir.y < 0 { edge = min(edge, (lo - a.y) / dir.y) }
        edge = max(0, edge)
        // 照準の点（マップの外を狙ったら、raycast と同じく端の 1 手前）
        let clipped = edge < len
        let aim = clipped ? max(0, edge - 1) : len
        let goal = clipped ? a + dir * aim : nav.clampToMap(to, radius: r)
        // 直進が照準の点まで届く（途中に壁が無い）: 従来どおり
        if straight.distanceSquared(to: goal) <= 4 { return (straight, false) }

        // 始点から歩いて行ける区画か（ヒーロー半径の連結成分。NavGrid.blinkLanding と同じ扱い）
        let baked = abs(r - NavGrid.bakedRadius) < 1e-9
        let startComp = baked ? nav.bakedComponents[nav.cellIndex(of: a)] : -1
        func lands(_ p: Vec2) -> Bool {
            guard nav.isWalkable(p, radius: r) else { return false }
            guard startComp >= 0 else { return true }
            let c = nav.bakedComponents[nav.cellIndex(of: p)]
            return c < 0 || c == startComp
        }
        if lands(goal) { return (goal, true) }

        let step = max(1, nav.cellSize * 0.1)
        // 手前: 照準の点から始点へ戻って最初に降りられる点
        var near: Double?
        var k = aim - step
        while k > 0 {
            if lands(a + dir * k) {
                near = k
                break
            }
            k -= step
        }
        if near == nil, lands(a) { near = 0 }
        // 向こう側: 照準の点から先へ farReach まで（マップの端の手前まで）
        var far: Double?
        let farEnd = min(aim + max(0, farReach), edge - 1)
        k = aim + step
        while k <= farEnd {
            if lands(a + dir * k) {
                far = k
                break
            }
            k += step
        }
        if let f = far, near.map({ f - aim <= aim - $0 }) ?? true {
            return (a + dir * f, true)
        }
        if let n = near {
            // 手前の縁が最初の壁の手前（壁を越えない）: 従来の突進と同じ点
            if n <= a.distance(to: straight) + step { return (straight, false) }
            return (a + dir * n, true)
        }
        return (straight, false)
    }

    /// 地形を越える経路ヒット突進（跳躍）。着地点は `leapLanding`。途中に壁が無ければ `dashSweeping` と同じ（変位・イベント・掃引）。
    /// 壁を越えるときは MovementSystem.dash と同じ形の変位（kind: .dash・同じ時間の式）を直に置く（raycast で壁に止めない）。
    /// 途中で止められて足元が壁の中に残ったときは、キットの onInterrupted で `settleOutOfTerrain` を呼ぶ。戻り値 = 着地点。
    @discardableResult
    static func dashSweepingOverTerrain(_ s: inout SimState, _ ctx: SimContext, caster i: Int, slot: SkillSlot,
                                        to target: Vec2, speed: Double, payload: HitPayload, radius: Double,
                                        farReach: Double, arriveCode: Int = 0, interruptible: Bool = true) -> Vec2 {
        let from = s.units[i].pos
        let landing = leapLanding(ctx.nav, from: from, to: target, radius: s.units[i].radius, farReach: farReach)
        guard landing.overTerrain else {
            return dashSweeping(&s, ctx, caster: i, slot: slot, to: target, speed: speed, payload: payload,
                                radius: radius, arriveCode: arriveCode, interruptible: interruptible)
        }
        let to = landing.point
        let duration = max(Balance.dt, from.distance(to: to) / max(1, speed))
        s.units[i].displacement = Displacement(kind: .dash, from: from, to: to, duration: duration)
        s.units[i].windupRemaining = nil
        s.units[i].path.removeAll()
        if to != from { s.units[i].facing = (to - from).angle }
        s.emit(.displaced(unitID: s.units[i].id, kind: .dash, from: from, to: to, duration: duration))
        armSweep(&s, caster: i, slot: slot, payload: payload, radius: radius, arriveCode: arriveCode,
                 interruptible: interruptible)
        return to
    }

    /// 壁を越える突進が途中で止められ（ノックアップ・制圧）、足元が壁の中に残ったとき、最寄りの歩ける点へ降ろす
    /// （MovementSystem が変位の終わりに着地点を直すのと同じ nearestWalkable）。変位の最中（押し出しに置き換えられたなど）は触らない
    /// （その変位の終わりに MovementSystem が直す）。歩ける場所に居れば何もしない。
    static func settleOutOfTerrain(_ s: inout SimState, _ ctx: SimContext, unit i: Int) {
        guard s.units.indices.contains(i), s.units[i].displacement == nil else { return }
        let r = s.units[i].radius
        let p = s.units[i].pos
        guard !ctx.nav.isWalkable(p, radius: r) else { return }
        s.units[i].pos = ctx.nav.nearestWalkable(p, radius: r)
    }
}
