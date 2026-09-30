import Foundation

// 担当: core-skills
// ロール別パッシブ（DESIGN §6）。ヒーロー固有係数 k = 1.0 + 0.02 × (番号 mod 5)。
// HeroData.passive の使い方（ロール毎に独立）:
// - Vanguard: cooldown = 低 HP シールドの残り CD
// - Duelist:  stacks = 攻撃速度スタック数（"passive.duelist" の attackSpeedBoost がある間だけ有効）
// - Ranger:   value = 最後に確定クリティカルを出した時点の basicAttackCount
// - Arcanist: stacks = 今回のキャストで CD 短縮済みのスロットのビット集合（1 << SkillSlot.rawValue）
// - Support:  なし
// - Assassin: flag = 前回の更新で隠れていた（草むら/ステルス）、timer = 奇襲の残り時間、value = 1 で奇襲可能

enum SkillPassives {
    /// ヒーロー固有係数 k。
    static func coefficient(_ s: SimState, _ i: Int) -> Double {
        guard let id = s.units[i].hero?.heroID else { return 1 }
        return SkillCatalog.passiveCoefficient(heroNumber: Int(id.dropFirst()) ?? 0)
    }

    // MARK: - 共通

    /// ステルス（虚像など）を解除する。攻撃の発射・スキル発動・攻撃的なスペルで呼ばれる。
    static func breakStealth(_ s: inout SimState, _ i: Int) {
        guard s.units[i].has(.stealth) else { return }
        s.units[i].statuses.removeAll { $0.kind == .stealth }
    }

    /// スキル発動の開始（命中処理より前）。アルカニストの「1 キャストにつき 1 回」をこのスロットで再び有効にする。
    static func beginCast(_ s: inout SimState, _ i: Int, slot: SkillSlot) {
        guard s.units[i].hero?.role == .arcanist else { return }
        s.units[i].hero!.passive.stacks &= ~(1 << slot.rawValue)
    }

    /// 毎 tick のタイマー（SkillSystem.update から）。
    static func update(_ s: inout SimState, _ ctx: SimContext, _ i: Int, dt: Double) {
        guard let role = s.units[i].hero?.role else { return }
        if s.units[i].hero!.passive.cooldown > 0 {
            s.units[i].hero!.passive.cooldown = max(0, s.units[i].hero!.passive.cooldown - dt)
        }
        switch role {
        case .assassin:
            updateAmbush(&s, i, dt: dt)
        case .duelist:
            // 攻撃速度バフが切れたらスタックを戻す（HUD 表示用）
            if s.units[i].hero!.passive.stacks > 0 && !hasDuelistBuff(s, i) {
                s.units[i].hero!.passive.stacks = 0
            }
        case .vanguard, .ranger, .arcanist, .support:
            break
        }
    }

    // MARK: - Vanguard: 低 HP シールド

    static func vanguardShield(_ s: inout SimState, _ ctx: SimContext, hero v: Int) {
        guard CombatSystem.isLiving(s, v), let h = s.units[v].hero, h.passive.cooldown <= 0,
              s.units[v].hpRatio < Balance.Skills.vanguardShieldThreshold else { return }
        let k = coefficient(s, v)
        s.units[v].hero!.passive.cooldown = Balance.Skills.vanguardShieldCooldown
        CombatSystem.addShield(&s, ctx, sourceID: s.units[v].id, targetIndex: v,
                               amount: s.units[v].stats.maxHP * Balance.Skills.vanguardShieldRatio * k,
                               duration: Balance.Skills.vanguardShieldDuration, tag: Balance.Skills.vanguardPassiveTag)
    }

    // MARK: - Duelist: 攻撃速度スタック

    static func hasDuelistBuff(_ s: SimState, _ i: Int) -> Bool {
        let tag = Balance.Skills.duelistPassiveTag
        return s.units[i].statuses.contains { $0.kind == .attackSpeedBoost && $0.tag == tag }
    }

    static func duelistStack(_ s: inout SimState, _ ctx: SimContext, attacker a: Int) {
        guard CombatSystem.isLiving(s, a), s.units[a].hero != nil else { return }
        let prev = hasDuelistBuff(s, a) ? s.units[a].hero!.passive.stacks : 0
        let stacks = min(Balance.Skills.duelistMaxStacks, prev + 1)
        s.units[a].hero!.passive.stacks = stacks
        let k = coefficient(s, a)
        // 同じ tag は強さ・残り時間とも大きい方が残る: スタック増加で強くなり、持続は毎回 3 秒に戻る
        CombatSystem.addStatus(&s, targetIndex: a,
                               StatusEffect(kind: .attackSpeedBoost, duration: Balance.Skills.duelistStackDuration,
                                            magnitude: Balance.Skills.duelistAttackSpeedPerStack * k * Double(stacks),
                                            sourceID: s.units[a].id, tag: Balance.Skills.duelistPassiveTag))
    }

    // MARK: - Ranger: 4 発毎の確定クリティカル

    /// 今回の発射が 4 発目（命中済み 3, 7, 11, ...）なら確定クリティカル。同じ命中数で 2 度出さない。
    /// 倍率 1.75×k は、この tick の実効クリティカル倍率に k を掛けて表す（次 tick の再計算で戻る）。
    static func rangerForceCrit(_ s: inout SimState, _ ctx: SimContext, attacker a: Int) -> Bool? {
        guard let h = s.units[a].hero else { return nil }
        let every = max(1, Balance.Skills.rangerCritEvery)
        let count = h.basicAttackCount
        guard count % every == every - 1, h.passive.value != Double(count) else { return nil }
        s.units[a].hero!.passive.value = Double(count)
        let k = coefficient(s, a)
        s.units[a].stats.critMultiplier = max(1, s.units[a].stats.critMultiplier) * k
        return true
    }

    // MARK: - Arcanist: 命中で他スキル CD 短縮

    static func arcanistRefund(_ s: inout SimState, _ ctx: SimContext, caster a: Int, slot: SkillSlot) {
        guard slot != .passive, let h = s.units[a].hero else { return }
        let bit = 1 << slot.rawValue
        guard h.passive.stacks & bit == 0 else { return }
        s.units[a].hero!.passive.stacks |= bit
        let amount = Balance.Skills.arcanistRefund * coefficient(s, a)
        for other in SkillSlot.actives where other != slot {
            let v = s.units[a].hero!.skillCooldowns[other.rawValue]
            if v > 0 { s.units[a].hero!.skillCooldowns[other.rawValue] = max(0, v - amount) }
        }
    }

    // MARK: - Support: スキル使用時の回復

    static func supportHeal(_ s: inout SimState, _ ctx: SimContext, caster c: Int) {
        guard CombatSystem.isLiving(s, c), let h = s.units[c].hero else { return }
        let k = coefficient(s, c)
        let amount = Balance.Skills.supportHealBase + Balance.Skills.supportHealPerLevel * Double(h.level) * k
        let team = s.units[c].team
        let center = s.units[c].pos
        var best: Int?
        var bestRatio = Double.infinity
        for j in s.units.indices where s.units[j].kind == .hero && s.units[j].team == team {
            guard CombatSystem.isLiving(s, j) else { continue }
            let r = Balance.Skills.supportHealRadius + s.units[j].radius
            guard s.units[j].pos.distanceSquared(to: center) <= r * r else { continue }
            let ratio = s.units[j].hpRatio
            if ratio < bestRatio {
                bestRatio = ratio
                best = j
            }
        }
        guard let t = best, bestRatio < 1 else { return }
        CombatSystem.heal(&s, ctx, sourceID: s.units[c].id, targetIndex: t, amount: amount)
    }

    // MARK: - Assassin: 奇襲・キル/アシストで CD 短縮

    static func isHidden(_ s: SimState, _ i: Int) -> Bool {
        s.units[i].brushIndex != nil || s.units[i].has(.stealth)
    }

    /// 草むら/ステルスに入ると奇襲が有効になり、隠れている間と出てから 3 秒間、最初のダメージを強化する。
    static func updateAmbush(_ s: inout SimState, _ i: Int, dt: Double) {
        guard CombatSystem.isLiving(s, i) else {
            s.units[i].hero!.passive.flag = false
            s.units[i].hero!.passive.timer = 0
            s.units[i].hero!.passive.value = 0
            return
        }
        let window = Balance.Skills.assassinAmbushWindow
        if isHidden(s, i) {
            if !s.units[i].hero!.passive.flag { s.units[i].hero!.passive.value = 1 }
            s.units[i].hero!.passive.flag = true
            s.units[i].hero!.passive.timer = window
        } else {
            s.units[i].hero!.passive.flag = false
            let t = s.units[i].hero!.passive.timer
            if t > 0 {
                let left = t - dt
                s.units[i].hero!.passive.timer = max(0, left)
                if left <= CombatSystem.timeEpsilon { s.units[i].hero!.passive.value = 0 }
            }
        }
    }

    /// 奇襲の与ダメ補正（敵ヒーローへの直接ダメージ 1 回で消費）。
    static func consumeAmbush(_ s: inout SimState, _ ctx: SimContext, attacker a: Int, target t: Int,
                              source: DamageSource) -> Double {
        switch source {
        case .basicAttack, .skill, .spell: break
        default: return 0
        }
        guard s.units[t].kind == .hero, s.units[t].team != s.units[a].team, let p = s.units[a].hero?.passive,
              p.value >= 1, p.timer > 0 || isHidden(s, a) else { return 0 }
        s.units[a].hero!.passive.value = 0
        return Balance.Skills.assassinAmbushBonus * coefficient(s, a)
    }

    static func assassinTakedown(_ s: inout SimState, hero i: Int) {
        guard s.units[i].hero != nil else { return }
        let keep = 1 - Balance.Skills.assassinTakedownRefund
        for slot in SkillSlot.actives {
            let v = s.units[i].hero!.skillCooldowns[slot.rawValue]
            if v > 0 { s.units[i].hero!.skillCooldowns[slot.rawValue] = v * keep }
        }
    }
}
