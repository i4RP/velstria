import Foundation

// 担当: core-skills（キット層。docs/SKILL_KITS.md）
// 弾のプリミティブ: 扇状の弾。ProjectileSystem.spawn のループ（角度は均等、乱数なし、生成順は左 → 右で固定）。

extension Kit {
    /// 扇状に count 発の直線弾を撃つ。center 方向を中心に ±halfAngle へ均等に並べる（count 1 なら中心のみ）。
    /// 弾の payload.originPos は未設定なら発射位置にする（距離スケーリング用）。生成した弾の ID（左から）を返す。
    @discardableResult
    static func fan(_ s: inout SimState, caster i: Int, direction: Vec2, count: Int, halfAngle: Double,
                    speed: Double, range: Double, width: Double, pierce: Bool = false, payload: HitPayload,
                    visual: String, origin: Vec2? = nil) -> [EntityID] {
        guard count > 0 else { return [] }
        let center = direction.normalized == .zero ? Vec2.fromAngle(s.units[i].facing) : direction.normalized
        var p = payload
        if p.originPos == nil { p.originPos = origin ?? s.units[i].pos }
        var ids: [EntityID] = []
        for k in 0..<count {
            let offset = count == 1 ? 0 : -halfAngle + 2 * halfAngle * Double(k) / Double(count - 1)
            let dir = center.rotated(by: offset)
            ids.append(ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: dir, maxDistance: range),
                                              speed: speed, width: width, pierce: pierce, payload: p, visual: visual,
                                              origin: origin))
        }
        return ids
    }
}
