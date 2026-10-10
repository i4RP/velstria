import Foundation

// 担当: core-skills（キット層。docs/SKILL_KITS.md）
// 状態系のプリミティブ: マーク（敵側のスタック）・維持されるステルス・対象不可・打ち上げ・suppress・構造物の凍結・シールド・吸血系。
// 敵側のスタック/マークは `.mark` status（magnitude = スタック数。tag に所有者 ID を含める）。

/// キットが status / shield に付ける tag。
enum KitTags {
    /// 攻撃・スキルの発動で解除されないステルス（SkillPassives.breakStealth が残す）。
    static let persistentStealth = "kit.stealth"
    static let untargetable = "kit.untargetable"
    static let knockUp = "kit.knockUp"
    static let suppress = "kit.suppress"

    /// 所有者ごとに分かれるマークの tag。例: mark("H032", "brand", owner: id)
    static func mark(_ heroID: String, _ name: String, owner: EntityID) -> String {
        "kit.\(heroID).\(name).\(owner)"
    }

    static func shield(_ heroID: String, _ name: String) -> String { "kit.\(heroID).\(name)" }
    static func buff(_ heroID: String, _ name: String) -> String { "kit.\(heroID).\(name)" }
}

extension Kit {
    // MARK: - マーク

    /// マークを積む（tag は KitTags.mark で作ったもの）。同じ tag は上限まで加算し、持続は毎回 duration に戻す。新しいスタック数を返す。
    @discardableResult
    static func addMark(_ s: inout SimState, target t: Int, ownerID: EntityID, tag: String, stacks: Int = 1,
                        maxStacks: Int, duration: Double) -> Int {
        guard s.units.indices.contains(t), CombatSystem.isLiving(s, t), !s.units[t].isStructure, stacks > 0,
              maxStacks > 0, duration > 0 else { return 0 }
        if let k = s.units[t].statuses.firstIndex(where: { $0.kind == .mark && $0.tag == tag }) {
            var st = s.units[t].statuses[k]
            let n = min(maxStacks, Int(st.magnitude.rounded()) + stacks)
            st.magnitude = Double(n)
            st.remaining = duration
            st.duration = duration
            st.sourceID = ownerID
            s.units[t].statuses[k] = st
            s.emit(.statusApplied(targetID: s.units[t].id, kind: .mark, duration: duration))
            return n
        }
        let n = min(maxStacks, stacks)
        s.units[t].statuses.append(StatusEffect(kind: .mark, duration: duration, magnitude: Double(n),
                                                sourceID: ownerID, tag: tag))
        s.emit(.statusApplied(targetID: s.units[t].id, kind: .mark, duration: duration))
        return n
    }

    static func markStacks(_ s: SimState, target t: Int, tag: String) -> Int {
        guard s.units.indices.contains(t) else { return 0 }
        for st in s.units[t].statuses where st.kind == .mark && st.tag == tag { return Int(st.magnitude.rounded()) }
        return 0
    }

    /// マークを全部消費して、消費したスタック数を返す。
    @discardableResult
    static func consumeMarks(_ s: inout SimState, target t: Int, tag: String) -> Int {
        let n = markStacks(s, target: t, tag: tag)
        if n > 0 { s.units[t].statuses.removeAll { $0.kind == .mark && $0.tag == tag } }
        return n
    }

    // MARK: - ステルス・対象不可

    /// 攻撃・スキルの発動で解除されないステルス。
    static func setPersistentStealth(_ s: inout SimState, caster i: Int, duration: Double) {
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .stealth, duration: duration,
                                                                sourceID: s.units[i].id,
                                                                tag: KitTags.persistentStealth))
    }

    static func clearPersistentStealth(_ s: inout SimState, caster i: Int) {
        s.units[i].statuses.removeAll { $0.kind == .stealth && $0.tag == KitTags.persistentStealth }
    }

    /// 対象不可（単体指定・追尾弾・通常攻撃の対象から外れる。範囲・直線には当たる）。
    static func setUntargetable(_ s: inout SimState, target t: Int, duration: Double, tag: String = KitTags.untargetable) {
        CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .untargetable, duration: duration,
                                                                sourceID: s.units[t].id, tag: tag))
    }

    // MARK: - CC

    /// 打ち上げ（既存の .airborne。CC 無効・無敵には効かない）。
    static func knockUp(_ s: inout SimState, target t: Int, duration: Double, sourceID: EntityID?) {
        CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .airborne, duration: duration,
                                                                sourceID: sourceID, tag: KitTags.knockUp))
    }

    /// suppress（行動不能・移動不能。解除不可で CC 無効も無視する。無敵・構造物には効かない）。
    static func suppress(_ s: inout SimState, target t: Int, duration: Double, sourceID: EntityID?) {
        guard s.units.indices.contains(t), CombatSystem.isLiving(s, t), !s.units[t].isStructure else { return }
        s.units[t].displacement = nil
        CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .suppress, duration: duration,
                                                                sourceID: sourceID, tag: KitTags.suppress))
    }

    static func releaseSuppress(_ s: inout SimState, target t: Int) {
        s.units[t].statuses.removeAll { $0.kind == .suppress }
    }

    /// 敵の構造物（タワー・Core）を凍結する（`.stun`。凍結の間は索敵・攻撃をしない: TowerSystem / CombatSystem.stepAttacker）。
    /// ダメージは与えない。無敵の構造物には効かない。構造物に弱体を付けられるのはこの関数だけ（`addStatus(allowStructure:)`）。
    /// 付いた（残り時間が延びた）ら true。
    @discardableResult
    static func freezeStructure(_ s: inout SimState, _ ctx: SimContext, target t: Int, duration: Double,
                                sourceID: EntityID?, tag: String) -> Bool {
        guard s.units.indices.contains(t), s.units[t].isStructure, CombatSystem.isLiving(s, t), duration > 0,
              !CombatSystem.isInvulnerable(s, ctx, t) else { return false }
        if let src = s.index(of: sourceID), s.units[src].team == s.units[t].team { return false }
        let before = s.units[t].statuses.first { $0.kind == .stun && $0.tag == tag }?.remaining ?? 0
        CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .stun, duration: duration, sourceID: sourceID,
                                                                tag: tag), allowStructure: true)
        let after = s.units[t].statuses.first { $0.kind == .stun && $0.tag == tag }?.remaining ?? 0
        guard after > before + 1e-9 else { return false }
        s.emit(.ccApplied(targetID: s.units[t].id, cc: .stun, duration: duration))
        return true
    }

    // MARK: - シールド・吸血

    /// tag 付きのシールド（同じ tag は置き換え）。name は KitTags.shield(heroID, name) の name。
    static func shield(_ s: inout SimState, _ ctx: SimContext, caster i: Int, target t: Int, amount: Double,
                       duration: Double, name: String) {
        let heroID = s.units[i].hero?.heroID ?? ""
        CombatSystem.addShield(&s, ctx, sourceID: s.units[i].id, targetIndex: t, amount: amount, duration: duration,
                               tag: KitTags.shield(heroID, name))
    }

    /// 通常攻撃の吸血を増やす（magnitude = 加算割合）。
    static func grantLifesteal(_ s: inout SimState, target t: Int, ratio: Double, duration: Double, tag: String) {
        CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .lifestealBoost, duration: duration,
                                                                magnitude: ratio, sourceID: s.units[t].id, tag: tag))
    }

    /// スキルの吸血（スペルヴァンプ）を増やす。
    static func grantSpellVamp(_ s: inout SimState, target t: Int, ratio: Double, duration: Double, tag: String) {
        CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .spellVampBoost, duration: duration,
                                                                magnitude: ratio, sourceID: s.units[t].id, tag: tag))
    }

    /// 通常攻撃の射程を増やす（magnitude = 加算距離）。
    static func grantAttackRange(_ s: inout SimState, target t: Int, amount: Double, duration: Double, tag: String) {
        CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .attackRangeBoost, duration: duration,
                                                                magnitude: amount, sourceID: s.units[t].id, tag: tag))
    }

    /// 防御を割合で下げる（magnitude = 減少率。敵に付ける）。
    static func shredArmor(_ s: inout SimState, target t: Int, ratio: Double, duration: Double, sourceID: EntityID?,
                           tag: String) {
        CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .armorShred, duration: duration,
                                                                magnitude: ratio, sourceID: sourceID, tag: tag))
    }
}
