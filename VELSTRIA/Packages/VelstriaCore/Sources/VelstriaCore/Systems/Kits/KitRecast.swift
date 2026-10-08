import Foundation

// 担当: core-skills（キット層。docs/SKILL_KITS.md）
// 再使用の窓と CD 操作。
// 最初の発動は必ずコストと CD を消費する（ボットの「当たった」判定が CD > 0 で見るため）。
// 再使用は CD・コスト無視で同じ castSkill コマンド。窓が閉じたら cooldownOnClose を適用する。

extension Kit {
    /// 開いている窓（閉じている・キットなしは nil）。
    static func window(_ s: SimState, caster i: Int, slot: SkillSlot) -> RecastWindow? {
        guard let k = s.units[i].hero?.kit, slot.rawValue < k.windows.count else { return nil }
        let w = k.windows[slot.rawValue]
        return w.isOpen ? w : nil
    }

    /// 再使用の窓を開く。charges = 再使用できる回数、cooldownOnClose >= 0 なら閉じたときにその秒数の CD にする。
    static func openRecast(_ s: inout SimState, caster i: Int, slot: SkillSlot, duration: Double, stage: Int = 1,
                           charges: Int = 1, cooldownOnClose: Double = -1) {
        guard s.units[i].hero?.kit != nil, duration > 0, stage > 0, charges > 0 else { return }
        var w = RecastWindow()
        w.stage = stage
        w.remaining = duration
        w.total = duration
        w.charges = charges
        w.cooldownOnClose = cooldownOnClose
        s.units[i].hero!.kit!.windows[slot.rawValue] = w
    }

    /// 再使用を 1 回使ったことにする。charges が尽きたら窓を閉じる。そうでなければ次の段へ進め、残り時間を戻す。
    static func advanceRecast(_ s: inout SimState, _ ctx: SimContext, caster i: Int, slot: SkillSlot, stage: Int? = nil,
                              duration: Double? = nil) {
        guard var w = window(s, caster: i, slot: slot) else { return }
        w.charges -= 1
        if w.charges <= 0 {
            closeRecast(&s, ctx, caster: i, slot: slot)
            return
        }
        w.stage = stage ?? (w.stage + 1)
        if let duration, duration > 0 { w.total = duration }
        w.remaining = w.total
        s.units[i].hero!.kit!.windows[slot.rawValue] = w
    }

    /// 窓を閉じる（cooldownOnClose を適用し、キットの onWindowClosed を呼ぶ）。expired = 時間切れ。
    static func closeRecast(_ s: inout SimState, _ ctx: SimContext, caster i: Int, slot: SkillSlot,
                            expired: Bool = false) {
        guard let k = s.units[i].hero?.kit, slot.rawValue < k.windows.count else { return }
        let w = k.windows[slot.rawValue]
        guard w.stage > 0 else { return }
        s.units[i].hero!.kit!.windows[slot.rawValue] = RecastWindow()
        if w.cooldownOnClose >= 0 { setCooldown(&s, ctx, caster: i, slot: slot, seconds: w.cooldownOnClose) }
        HeroKits.kit(in: s, i)?.onWindowClosed(&s, ctx, owner: i, slot: slot, expired: expired)
    }

    // MARK: - CD 操作（練習場の noCooldowns を尊重する）

    static func setCooldown(_ s: inout SimState, _ ctx: SimContext, caster i: Int, slot: SkillSlot, seconds: Double) {
        guard slot != .passive, s.units[i].hero != nil else { return }
        let noCD = ctx.config.practice?.noCooldowns == true
        s.units[i].hero?.skillCooldowns[slot.rawValue] = noCD ? 0 : max(0, seconds)
    }

    /// 残りクールダウンを seconds だけ縮める（0 未満にはならない）。
    static func refundCooldown(_ s: inout SimState, _ ctx: SimContext, caster i: Int, slot: SkillSlot, seconds: Double) {
        guard slot != .passive, let v = s.units[i].hero?.skillCooldowns[slot.rawValue], v > 0, seconds > 0 else { return }
        let noCD = ctx.config.practice?.noCooldowns == true
        s.units[i].hero?.skillCooldowns[slot.rawValue] = noCD ? 0 : max(0, v - seconds)
    }
}
