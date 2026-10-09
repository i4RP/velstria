import Foundation

// 担当: kit-H026（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Eudora.md）
// H026 紫電のエウリア = Velstria 版の Eudora（MLBB。調査: docs/kits/Eudora.md、対応表: 同ファイル末尾）。
// アルカニスト（遠隔 550・マナ）。ロールの汎用パッシブ（スキル命中で他スキルの CD 短縮）を置き換える。
//   パッシブ 超伝導        — スキルが命中した敵（ミニオンを除く）に「超伝導」の印を 5 秒付ける。
//                            印の付いた敵に当たると各スキルに追加効果（印そのものはダメージを増やさない）。
//   スキル1 分岐雷         — 前方の扇に雷（ミニオンには 2 倍）。超伝導の敵に当たると 1 秒の「雷の鎖」: 移動速度 +40%・継続ダメージ・
//                            終わりに追加ダメージ。追加ダメージが当たると S1 のクールダウンが縮む。同じ相手への鎖は 3 秒に 1 回まで
//                            （印は消費しないので、鎖が無限に繋がらないための制限）。
//   スキル2 雷球           — 対象指定の雷球（スタン 1 秒・魔防ダウン 1.8 秒）。超伝導の敵に当たると周囲の敵にも同じダメージが広がる
//                            （スタン・魔防ダウンはミニオンには広がらない）。
//   アルティメット 九天雷鳴 — 指定地点に遅れて落ちる大雷（中心に重く、外側に半分）。超伝導の敵に当たると、その敵を中心に少し遅れて
//                            雷が炸裂する（複数なら重なる）。
// 再使用の窓は Eudora に無いので使わない。
//
// 状態（KitState）:
//   timers[0] = 雷の鎖の残り秒（HUD 用）   timers[1...4] = ids[0...3] の相手へ次の鎖を結べるまでの残り秒（相手ごとのロックアウト）
//   ints[0] = 雷の鎖を結んだ回数   ints[1] = 鎖の終わりの一撃が当たった回数   ints[2] = 雷の炸裂を起こした回数
//   ints[3] = 雷球が周囲へ広がった回数   ints[4] = 超伝導を付けた回数（いずれも検証用）
//   ids[0...3] = 最近鎖を結んだ相手（4 体まで。空きが無ければ残りが最も短いものを入れ替える）

extension KitState {
    var euriaChainRemaining: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    var euriaChains: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    var euriaChainEnds: Int {
        get { ints[1] }
        set { ints[1] = newValue }
    }

    var euriaBursts: Int {
        get { ints[2] }
        set { ints[2] = newValue }
    }

    var euriaSplashes: Int {
        get { ints[3] }
        set { ints[3] = newValue }
    }

    var euriaMarksApplied: Int {
        get { ints[4] }
        set { ints[4] = newValue }
    }

    /// その相手へ次の鎖を結べるまでの残り秒（0 = 結べる）。
    func euriaChainLockout(for id: EntityID) -> Double {
        for k in 0..<4 where ids[k] == id && id != 0 { return timers[1 + k] }
        return 0
    }

    /// その相手へのロックアウトを始める（既にあれば更新、空きが無ければ残りが最も短いものと入れ替える）。
    mutating func setEuriaChainLockout(for id: EntityID, seconds: Double) {
        var slot = (0..<4).first { ids[$0] == id }
        if slot == nil { slot = (0..<4).first { timers[1 + $0] <= 0 } }
        if slot == nil { slot = (0..<4).min { timers[1 + $0] < timers[1 + $1] } }
        let k = slot ?? 0
        ids[k] = id
        timers[1 + k] = seconds
    }
}

/// エウリアの調整値（docs/kits/Eudora.md の数値を Velstria の単位・TTK に合わせたもの）。
enum EuriaTuning {
    // MARK: パッシブ（超伝導）
    /// 印の持続。調査では資料が割れている（Fandom 5 秒 / mlbbhub 3 秒）ので Fandom に従う。
    static let markDuration: Double = 5
    static let markName = "sc"

    // MARK: S1（Forked Lightning）
    /// 扇の半角（調査に角度は無い）。射程はスキル定義（650）。
    static let s1HalfAngle: Double = Double.pi / 6
    /// 1 撃（最初の一撃 = 鎖の終わりの一撃）のダメージ ÷ 汎用 S1。鎖が結ばれると 2 撃 + 継続ダメージで 1.2 倍前後になる。
    static let s1Ratio: Double = 0.55
    /// 継続ダメージ 1 回 ÷ 1 撃（調査: 10〜20 + 4% に対し 275〜500 + 100%）。
    static let dotRatio: Double = 0.04
    static let dotCount = 4
    static let dotInterval: Double = 0.2
    static let chainDuration: Double = 1.0
    /// 同じ相手へは、前の鎖を結んでからこの秒数が過ぎるまで次の鎖を結ばない。印は消費しない（印のあいだ S1 が当たるたびに鎖が繋がり、
    /// 終わりの一撃のクールダウン短縮で回り続けるのを抑える）。総当たりの勝率（アルカニスト中央値との差）は
    /// 制限なし Lv1 +40 / Lv6 +15 / Lv12 +41 pt → 3 秒で Lv1 +4 / Lv6 +12 / Lv12 +28 pt。それ以上の秒数ではほとんど変わらない（6 秒でも同程度）。
    static let chainLockout: Double = 3.0
    static let chainSpeed: Double = 0.40
    /// 鎖が切れる距離（調査に無い。S1 の射程 650 に余裕を足した値）。術者と対象の中心間。
    static let chainLeash: Double = 800
    /// 鎖の終わりの一撃が当たったときの S1 のクールダウン短縮（MLBB 1.5 秒 × 全体のクールダウン倍率）。
    static let chainRefund: Double = 1.5 * Balance.Skills.cooldownScale
    static let chainSpeedTag = KitTags.buff("H026", "chain")

    // MARK: S2（Ball Lightning）
    /// 汎用の遠隔 S2 は「ブリンク + 強化攻撃」で数値が半分になっているため、基準は元のスキル値（base ÷ empowerRatio）。
    static let s2Ratio: Double = 0.81
    static let s2Speed: Double = 1800
    static let s2Stun: Double = 1.0
    /// 魔防ダウン（固定値。調査: 10/13/16/19/22/25 の 6 段 → 4 段へ線形）と持続。
    static let shredRange = (10.0, 25.0)
    static let shredDuration: Double = 1.8
    /// 超伝導の敵に当たったときの広がり（調査に半径は無い）。
    static let splashRadius: Double = 260
    static let shredTag = KitTags.buff("H026", "shred")

    // MARK: 奥義（Thunder's Wrath）
    /// 中心の敵へのダメージ ÷ 汎用の奥義（アルカニストの地点 AoE）。0.85 → 0.82（総当たりの勝率がアルカニスト中央値より高かったため、
    /// 鎖の再結びの制限・スキル2 0.85 → 0.81・炸裂 0.47 → 0.40 と合わせて調整）。
    static let ultCenterRatio: Double = 0.82
    /// 外側の敵へのダメージ ÷ 中心（調査: 300〜500 に対し 600〜1000）。
    static let ultOuterRatio: Double = 0.5
    /// 超伝導の敵を中心に炸裂する雷のダメージ ÷ 中心（調査: 300〜550 に対し 600〜1000 = 約 0.5）。
    static let burstRatio: Double = 0.40
    static let ultCenterRadius: Double = 150
    static let ultOuterRadius: Double = 300
    static let ultDelay: Double = 0.8
    static let burstRadius: Double = 190
    static let burstDelay: Double = 0.5

    // MARK: クールダウン（MLBB 秒 → ランク間を線形補間 → Balance.Skills.cooldownScale を掛ける）
    static let s1Cooldown = (7.0, 5.0)
    static let s2Cooldown = (11.0, 8.5)
    static let ultCooldown = (32.0, 26.0)

    /// HitPayload.kitEvent
    enum Event {
        static let fork = 1
        static let chainEnd = 2
        static let orb = 3
        static let orbSplash = 4
        static let thunder = 5
        static let burst = 6
    }

    /// KitTimer.code
    enum Code {
        static let dot = 1
        static let end = 2
    }
}

struct Kit_H026: HeroKit {
    let heroID = "H026"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H026(isReady: true)` を HeroKits.testOverride に差すこともできる。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    typealias T = EuriaTuning

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 前方の扇（範囲の半径 = 射程）
            return SkillTargeting(archetype: .cone, aim: .direction, range: skill.range, radius: skill.range,
                                  shape: .fan, halfAngle: T.s1HalfAngle)
        case .skill2:
            // 対象指定の雷球（追尾する弾）。radius は表示用の弾の大きさ
            return SkillTargeting(archetype: .lineSkillshot, aim: .unit, range: skill.range, radius: 60,
                                  shape: .lockOn, requiresTarget: true)
        case .ultimate:
            // 地点指定（遅れて落ちる）。radius は外側の半径
            return SkillTargeting(archetype: .groundAoE, aim: .point, range: skill.range, radius: T.ultOuterRadius,
                                  shape: .circleAtPoint)
        case .passive:
            return base
        }
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        var n = base
        n.damageType = .magic
        switch slot {
        case .passive:
            n.extras = [KitStat(key: "markDuration", value: T.markDuration)]
        case .skill1:
            // damage = 1 撃（最初の一撃と鎖の終わりの一撃）、hits = 2。継続ダメージは extras
            n.damage = base.damage * T.s1Ratio
            n.hits = 2
            n.cooldown = Self.cooldown(T.s1Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .none
            n.ccDuration = 0
            n.extras = [KitStat(key: "chainDuration", value: T.chainDuration),
                        KitStat(key: "chainSpeed", value: T.chainSpeed * 100),
                        KitStat(key: "refund", value: T.chainRefund),
                        KitStat(key: "dot", value: (n.damage * T.dotRatio).rounded()),
                        KitStat(key: "lockout", value: T.chainLockout)]
        case .skill2:
            let raw = base.damage / Balance.Skills.empowerRatio
            n.damage = raw * T.s2Ratio
            n.hits = 1
            n.cooldown = Self.cooldown(T.s2Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .stun
            n.ccIsUltimate = false
            n.ccDuration = T.s2Stun
            n.extras = [KitStat(key: "shred", value: Self.shredAmount(rank: rank, maxRank: slot.maxRank)),
                        KitStat(key: "shredDuration", value: T.shredDuration),
                        KitStat(key: "splashRadius", value: T.splashRadius),
                        KitStat(key: "stun", value: T.s2Stun)]
        case .ultimate:
            n.damage = base.damage * T.ultCenterRatio
            n.hits = 1
            n.cooldown = Self.cooldown(T.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .none
            n.ccIsUltimate = false
            n.ccDuration = 0
            n.delay = T.ultDelay
            n.extras = [KitStat(key: "outer", value: (n.damage * T.ultOuterRatio).rounded()),
                        KitStat(key: "burst", value: (n.damage * T.burstRatio).rounded()),
                        KitStat(key: "delay", value: T.ultDelay),
                        KitStat(key: "centerRadius", value: T.ultCenterRadius)]
        }
        return n
    }

    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "スキルが命中した敵（ミニオンを除く）に「超伝導」を{x0}秒付ける。超伝導の敵に当たると追加効果が起きる"
                    + "（分岐雷＝スキル1 は雷の鎖、雷球＝スキル2 は周囲へ広がってスタン、九天雷鳴＝アルティメットは遅れて雷が炸裂）。"
                    + "印そのものは威力を増やさず、追加効果で消えることもない。",
                en: "Skills that hit an enemy (minions excluded) inflict Superconductor for {x0}s. Hitting a Superconductor "
                    + "enemy triggers an extra effect (Forked Bolt / Skill 1: a lightning chain, Thunder Orb / Skill 2: spreads "
                    + "and stuns nearby enemies, Nine Heavens Thunder / Ultimate: a delayed Thunderburst). The mark itself adds "
                    + "no damage and is not consumed by those effects.")
        case .skill1:
            return KitText(
                ja: "前方の扇へ雷を放ち、範囲の敵に{damage}の魔法ダメージ（ミニオンには2倍）。超伝導の敵に当たると{x0}秒の雷の鎖を結ぶ"
                    + "（同じ相手には{lockout}秒に1回まで）。鎖の間は移動速度が{x1}%上がり、継続ダメージ（1回{x3}）を与え、"
                    + "終わりに{damage}の追加ダメージ。追加ダメージが当たるとクールダウンが{x2}秒縮む。クールダウン{cd}秒。",
                en: "Fires lightning in a fan ahead, dealing {damage} magic damage to enemies in it (double against minions). "
                    + "Hitting a Superconductor enemy forms a {x0}s lightning chain (once per {lockout}s on the same target): you "
                    + "gain {x1}% movement speed, it deals damage over time ({x3} per tick) and {damage} more when it ends. If that "
                    + "final hit lands, the cooldown is reduced by {x2}s. Cooldown {cd}s.")
        case .skill2:
            return KitText(
                ja: "対象の敵へ雷球を放ち、{damage}の魔法ダメージと{x3}秒のスタン。{x1}秒間、魔法防御を{x0}下げる。"
                    + "超伝導の敵に当たると、周囲{x2}の敵にも同じダメージが広がり、ヒーローとモンスターにはスタンと魔防ダウンも広がる"
                    + "（ミニオンにはダメージのみ）。クールダウン{cd}秒。",
                en: "Hurls an orb at a target enemy, dealing {damage} magic damage and stunning for {x3}s, and reducing "
                    + "magic defense by {x0} for {x1}s. Hitting a Superconductor enemy spreads the same damage to enemies within "
                    + "{x2}, and the stun and defense reduction to heroes and monsters among them (minions take damage only). "
                    + "Cooldown {cd}s.")
        case .ultimate:
            return KitText(
                ja: "指定地点に{x2}秒後に大雷を落とす（射程{range}）。中心（半径{x3}）の敵に{damage}、外側（半径{radius}）の敵に{x0}の魔法ダメージ。"
                    + "超伝導の敵に当たると、その敵を中心に少し遅れて雷が炸裂し、周囲に{x1}の魔法ダメージ（複数なら重なる）。クールダウン{cd}秒。",
                en: "Calls down a great bolt on the target area after {x2}s (range {range}). Deals {damage} magic damage "
                    + "at the center (radius {x3}) and {x0} outside it (radius {radius}). Each Superconductor enemy hit "
                    + "triggers a Thunderburst centered on it shortly after, dealing {x1} magic damage nearby (bursts "
                    + "overlap). Cooldown {cd}s.")
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard slot == .skill1, let k = hero.kit, k.euriaChainRemaining > 0 else { return nil }
        return KitBadge(kind: .timer, remaining: k.euriaChainRemaining, total: T.chainDuration)
    }

    // MARK: - B. 実行

    func resolveAim(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot, stage: Int,
                    targeting: SkillTargeting, target: SkillTarget) -> SkillAim?? {
        guard slot == .skill2 else { return nil }
        // 対象指定: 射程内の敵が居なければ拒否（コスト・CD を消費しない）
        guard let u = Self.pickTarget(s, caster: caster, reach: targeting.reach, target: target) else {
            return .some(nil)
        }
        return .some(SkillAiming.aim(at: u, s, caster: caster, range: targeting.range,
                                     facing: Vec2.fromAngle(s.units[caster].facing)))
    }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        switch c.slot {
        case .skill1: castFork(&s, ctx, c)
        case .skill2: castOrb(&s, c)
        case .ultimate: castThunder(&s, c)
        case .passive: break
        }
        return .done
    }

    /// S1: 前方の扇に即時の雷。当たった敵ごとに onHit（印の付与と鎖）。
    private func castFork(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let origin = s.units[i].pos
        let dir = c.aim.direction
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * c.targeting.range, unit: c.aim.unit, shape: .fan,
                     halfAngle: T.s1HalfAngle, duration: T.chainDuration, count: 3)
        let p = HitPayload(damage: c.numbers.damage, damageType: c.check.skill.damageType, source: .skill(.skill1),
                           skillID: c.check.skill.skillID, originPos: origin, kitEvent: T.Event.fork)
        SkillArchetypes.hitArea(&s, ctx, caster: i, center: origin, radius: c.targeting.range,
                                shape: .cone(direction: dir, halfAngle: T.s1HalfAngle), payload: p)
    }

    /// S2: 対象を追う雷球。命中で onHit（印の付与と、印済みなら周囲への広がり）。
    private func castOrb(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        guard let t = c.aim.unit else { return }
        let payload = Self.orbPayload(skill: c.check.skill, numbers: c.numbers, rank: c.numbers.rank,
                                      event: T.Event.orb)
        let dist = s.units[i].pos.distance(to: s.units[t].pos)
        Kit.emitCast(&s, c, target: s.units[t].pos, unit: t, shape: .lockOn, duration: dist / T.s2Speed, count: 1)
        ProjectileSystem.spawn(&s, ownerIndex: i, motion: .homing(targetID: s.units[t].id), speed: T.s2Speed,
                               payload: payload, visual: c.check.skill.effectID)
    }

    /// 奥義: 指定地点に遅れて落ちる大雷（予告の円 = ゾーンの delay）。中心は重く、外側は半分（距離補正を段差にして使う）。
    private func castThunder(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        let center = c.aim.point
        let p = HitPayload(damage: c.numbers.damage, damageType: c.check.skill.damageType, source: .skill(.ultimate),
                           skillID: c.check.skill.skillID,
                           scaling: .distance(near: T.ultCenterRadius, far: T.ultCenterRadius + 1, minMult: 1,
                                              maxMult: T.ultOuterRatio),
                           originPos: center, kitEvent: T.Event.thunder)
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: center, unit: c.aim.unit, shape: .circleAtPoint,
                     duration: T.ultDelay, count: 1)
        ZoneSystem.spawn(&s, ownerIndex: i, center: center, radius: T.ultOuterRadius, delay: T.ultDelay, payload: p,
                         visual: c.check.skill.effectID)
    }

    // MARK: - 命中

    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {
        guard s.units.indices.contains(target), s.units.indices.contains(owner) else { return }
        switch event {
        case T.Event.fork:
            // 印済みの敵に当たったら鎖を結ぶ（印の付与が先ではなく、付与前の状態で判定する）
            let had = markAndReport(&s, owner: owner, target: target)
            if had, CombatSystem.isLiving(s, owner), CombatSystem.isLiving(s, target),
               !Self.chainLocked(s, owner: owner, target: target) {
                startChain(&s, ctx, owner: owner, target: target)
            }
        case T.Event.orb:
            let had = markAndReport(&s, owner: owner, target: target)
            if had, CombatSystem.isLiving(s, owner) { splash(&s, ctx, owner: owner, center: target) }
        case T.Event.thunder:
            let had = markAndReport(&s, owner: owner, target: target)
            if had, CombatSystem.isLiving(s, owner) { thunderburst(&s, ctx, owner: owner, target: target) }
        case T.Event.orbSplash, T.Event.burst:
            _ = markAndReport(&s, owner: owner, target: target)
        case T.Event.chainEnd:
            s.units[owner].hero?.kit?.euriaChainEnds += 1
        default:
            break
        }
    }

    /// 超伝導を付ける（ミニオン・構造物には付かない）。付ける前から印があれば true。
    private func markAndReport(_ s: inout SimState, owner: Int, target: Int) -> Bool {
        guard Self.canMark(s, target), CombatSystem.isLiving(s, target) else { return false }
        let tag = Self.markTag(s, owner)
        let had = Kit.markStacks(s, target: target, tag: tag) > 0
        Kit.addMark(&s, target: target, ownerID: s.units[owner].id, tag: tag, maxStacks: 1, duration: T.markDuration)
        s.units[owner].hero?.kit?.euriaMarksApplied += 1
        return had
    }

    // MARK: S1: 雷の鎖

    /// 鎖を結ぶ: 移動速度 +40%（鎖の間）、継続ダメージ 4 回、終わりに追加ダメージ（当たるとクールダウン短縮）。
    private func startChain(_ s: inout SimState, _ ctx: SimContext, owner i: Int, target t: Int) {
        guard let (_, n) = Self.numbersNow(s, ctx, i, .skill1) else { return }
        let tid = s.units[t].id
        // 同じ対象の鎖は張り直し
        s.units[i].hero?.kit?.scheduled.removeAll { $0.targetID == tid && ($0.code == T.Code.dot || $0.code == T.Code.end) }
        let dot = n.damage * T.dotRatio
        for k in 1...T.dotCount {
            Kit.schedule(&s, caster: i, slot: .skill1, code: T.Code.dot, after: T.dotInterval * Double(k), targetID: tid,
                         index: k, param: dot, interruptible: true)
        }
        Kit.schedule(&s, caster: i, slot: .skill1, code: T.Code.end, after: T.chainDuration, targetID: tid, param: n.damage,
                     interruptible: true)
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .speedBoost, duration: T.chainDuration,
                                                                magnitude: T.chainSpeed, sourceID: s.units[i].id,
                                                                tag: T.chainSpeedTag))
        s.units[i].hero?.kit?.euriaChainRemaining = T.chainDuration
        s.units[i].hero?.kit?.euriaChains += 1
        s.units[i].hero?.kit?.setEuriaChainLockout(for: tid, seconds: T.chainLockout)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard timer.code == T.Code.dot || timer.code == T.Code.end else { return }
        let isEnd = timer.code == T.Code.end
        // 対象が倒れた・見えなくなった・離れすぎた: 鎖は切れる（終わりの一撃は当たらず、クールダウンも縮まない）
        guard let t = s.index(of: timer.targetID), CombatSystem.isLiving(s, t),
              s.isTargetableEnemy(t, of: s.units[owner].team),
              s.units[owner].pos.distance(to: s.units[t].pos) <= T.chainLeash else {
            breakChain(&s, owner: owner, targetID: timer.targetID)
            return
        }
        guard let (skill, _) = Self.numbersNow(s, ctx, owner, .skill1) else { return }
        var p = HitPayload(damage: timer.param, damageType: skill.damageType, source: .skill(.skill1),
                           skillID: skill.skillID, originPos: s.units[owner].pos)
        if isEnd {
            p.kitEvent = T.Event.chainEnd
            p.effects = [.refundCooldown(slot: .skill1, seconds: T.chainRefund)]
        }
        CombatSystem.applyHit(&s, ctx, sourceID: s.units[owner].id, team: s.units[owner].team, targetIndex: t,
                              payload: p, from: s.units[owner].pos)
        if isEnd { finishChainIfIdle(&s, owner: owner) }
    }

    /// 対象の鎖を外す（予約を捨てる）。ほかの鎖が残っていなければ加速も外す。
    private func breakChain(_ s: inout SimState, owner: Int, targetID: EntityID) {
        s.units[owner].hero?.kit?.scheduled.removeAll {
            $0.targetID == targetID && ($0.code == T.Code.dot || $0.code == T.Code.end)
        }
        finishChainIfIdle(&s, owner: owner)
    }

    private func finishChainIfIdle(_ s: inout SimState, owner: Int) {
        let active = s.units[owner].hero?.kit?.scheduled.contains { $0.code == T.Code.dot || $0.code == T.Code.end } ?? false
        guard !active else { return }
        s.units[owner].statuses.removeAll { $0.kind == .speedBoost && $0.tag == T.chainSpeedTag }
        s.units[owner].hero?.kit?.euriaChainRemaining = 0
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // ハード CC: 鎖の予約は取り消された。加速も終わる
        s.units[owner].statuses.removeAll { $0.kind == .speedBoost && $0.tag == T.chainSpeedTag }
        s.units[owner].hero?.kit?.euriaChainRemaining = 0
    }

    // MARK: S2: 周囲への広がり

    /// 印済みの敵に雷球が当たった: その周囲の敵（当たった敵を除く）にも同じダメージ・スタン・魔防ダウン。
    private func splash(_ s: inout SimState, _ ctx: SimContext, owner i: Int, center t: Int) {
        guard let (skill, n) = Self.numbersNow(s, ctx, i, .skill2) else { return }
        let team = s.units[i].team
        let c = s.units[t].pos
        var targets: [Int] = []
        for j in s.units.indices where j != t && s.units[j].team != team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j) else { continue }
            let reach = T.splashRadius + s.units[j].radius
            if s.units[j].pos.distanceSquared(to: c) <= reach * reach { targets.append(j) }
        }
        s.units[i].hero?.kit?.euriaSplashes += 1
        // ミニオンにはダメージだけ（スタン・魔防ダウンは広がらない。主対象と周囲のヒーロー・モンスターには広がる）
        let p = Self.orbPayload(skill: skill, numbers: n, rank: n.rank, event: T.Event.orbSplash)
        var damageOnly = p
        damageOnly.statuses = []
        for j in targets {
            CombatSystem.applyHit(&s, ctx, sourceID: s.units[i].id, team: team, targetIndex: j,
                                  payload: s.units[j].kind == .minion ? damageOnly : p, from: c)
        }
    }

    // MARK: 奥義: 雷の炸裂

    /// 印済みの敵に大雷が当たった: その敵を中心に少し遅れて雷が炸裂する（敵に追従するゾーン。対象が倒れれば不発）。
    private func thunderburst(_ s: inout SimState, _ ctx: SimContext, owner i: Int, target t: Int) {
        guard CombatSystem.isLiving(s, t), let (skill, n) = Self.numbersNow(s, ctx, i, .ultimate) else { return }
        let p = HitPayload(damage: n.damage * T.burstRatio, damageType: skill.damageType, source: .skill(.ultimate),
                           skillID: skill.skillID, originPos: s.units[t].pos, kitEvent: T.Event.burst)
        s.units[i].hero?.kit?.euriaBursts += 1
        ZoneSystem.spawn(&s, ownerIndex: i, center: s.units[t].pos, radius: T.burstRadius, delay: T.burstDelay,
                         followsTargetID: s.units[t].id, payload: p, visual: Self.burstVisual(ctx))
    }

    // MARK: - C. パッシブ

    func outgoingDamageBonus(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                             source: DamageSource) -> Double {
        // S1 はミニオンに 200%
        guard source == .skill(.skill1), s.units[target].kind == .minion else { return 0 }
        return 1
    }

    // MARK: - D. ボット

    /// 印を付けてから重い技を使う: 印の無い敵には、スキル1（雷の鎖）が実際に撃てるあいだは S1 → (S2 / アルティメット) の順にする。
    /// 「撃てる」= クールダウンが明け、マナがあり、沈黙などでなく、敵が S1 の射程（扇）に入っていること
    /// （撃てないのに待ち続けて、アルティメットや S2 が永久に出なくならないように）。
    /// S2 は印が広がるので、近くに別のヒーローが居るときは印を付けてから。居なければ先に撃ってよい（S2 自身が印を付ける）。
    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        guard fighting, slot != .skill1, s.units.indices.contains(target), Self.canMark(s, target) else { return .useDefault }
        let marked = Kit.markStacks(s, target: target, tag: Self.markTag(s, bot)) > 0
        guard !marked, Self.fork1Ready(s, ctx, bot: bot, target: target) else { return .useDefault }
        switch slot {
        case .ultimate:
            return .skip
        case .skill2:
            // 周囲に別のヒーローが居るときだけ待つ（印済みなら広がるので）
            var near = 0
            for j in s.units.indices where j != target && s.units[j].team != s.units[bot].team && !s.units[j].isStructure {
                guard CombatSystem.isLiving(s, j), s.units[j].kind == .hero else { continue }
                let reach = T.splashRadius + s.units[j].radius
                if s.units[j].pos.distanceSquared(to: s.units[target].pos) <= reach * reach { near += 1 }
            }
            return near >= 1 ? .skip : .useDefault
        default:
            return .useDefault
        }
    }

    /// スキル1 が今この敵に撃てるか（クールダウン・マナ・行動可能・射程）。
    static func fork1Ready(_ s: SimState, _ ctx: SimContext, bot: Int, target: Int) -> Bool {
        guard SkillSystem.canCast(s, ctx, heroIndex: bot, slot: .skill1),
              let skill = ctx.master.skill(hero: "H026", slot: .skill1), let h = s.units[bot].hero,
              s.units[bot].resource + 1e-6 >= SkillSystem.cost(for: skill, resource: h.resourceKind) else { return false }
        let reach = skill.range + s.units[target].radius
        return s.units[bot].pos.distanceSquared(to: s.units[target].pos) <= reach * reach
    }

    // MARK: - 部品

    /// 同じ相手への鎖がまだ結び直せないか（前の鎖から chainLockout 秒以内）。
    static func chainLocked(_ s: SimState, owner: Int, target: Int) -> Bool {
        guard let k = s.units[owner].hero?.kit else { return false }
        return k.euriaChainLockout(for: s.units[target].id) > 0
    }

    /// 超伝導を付けられる相手（ミニオン・構造物には付かない）。
    static func canMark(_ s: SimState, _ t: Int) -> Bool {
        guard s.units.indices.contains(t), !s.units[t].isStructure else { return false }
        switch s.units[t].kind {
        case .hero, .monster, .dummy: return true
        default: return false
        }
    }

    static func markTag(_ s: SimState, _ owner: Int) -> String {
        KitTags.mark("H026", T.markName, owner: s.units[owner].id)
    }

    /// 雷球（主対象・広がりの共通）。スタン + 魔防ダウン（固定値）。
    static func orbPayload(skill: SkillDef, numbers n: SkillNumbers, rank: Int, event: Int) -> HitPayload {
        let stun = StatusEffect(kind: .stun, duration: T.s2Stun, tag: CombatSystem.tagStun)
        let shred = StatusEffect(kind: .magicShred, duration: T.shredDuration,
                                 magnitude: shredAmount(rank: rank, maxRank: SkillSlot.skill2.maxRank), tag: T.shredTag)
        return HitPayload(damage: n.damage, damageType: skill.damageType, source: .skill(.skill2), statuses: [stun, shred],
                          skillID: skill.skillID, kitEvent: event)
    }

    /// 魔防ダウン量（固定値 10 → 25 をランクで線形に）。
    static func shredAmount(rank: Int, maxRank: Int) -> Double {
        lerp(T.shredRange.0, T.shredRange.1, rank: rank, maxRank: maxRank)
    }

    /// 雷の炸裂のゾーンに使う演出 ID（パッシブの演出枠。大雷とは別の演出にするため）。
    static func burstVisual(_ ctx: SimContext) -> String {
        ctx.master.skill(hero: "H026", slot: .passive)?.effectID ?? ""
    }

    /// 現在のランク・能力値でのスキルと数値。
    static func numbersNow(_ s: SimState, _ ctx: SimContext, _ i: Int, _ slot: SkillSlot) -> (SkillDef, SkillNumbers)? {
        guard let h = s.units[i].hero, let def = ctx.master.hero(h.heroID),
              let skill = ctx.master.skill(hero: h.heroID, slot: slot) else { return nil }
        return (skill, SkillCatalog.numbers(for: skill, hero: def, rank: max(1, h.rank(slot)), stats: s.units[i].stats))
    }

    /// MLBB のクールダウン（秒）をランクで線形補間し、Velstria の全体倍率と CD 短縮を掛ける。
    static func cooldown(_ range: (Double, Double), rank: Int, maxRank: Int, stats: Stats) -> Double {
        let sec = lerp(range.0, range.1, rank: rank, maxRank: maxRank)
        let reduction = min(Balance.maxCooldownReduction, max(0, stats.cooldownReduction))
        return sec * (1 - reduction) * Balance.Skills.cooldownScale
    }

    private static func lerp(_ a: Double, _ b: Double, rank: Int, maxRank: Int) -> Double {
        guard maxRank > 1 else { return a }
        let t = Double(min(max(1, rank), maxRank) - 1) / Double(maxRank - 1)
        return a + (b - a) * t
    }

    /// 対象指定の選び方: 指定ユニット → 指定地点に近い敵 → 向きに近い敵 → 自動（ヒーロー優先で HP + シールド最小）。
    /// すべて「術者の中心から対象の縁まで reach 以内」の視認中の敵（構造物・無敵・対象不可を除く）。
    static func pickTarget(_ s: SimState, caster i: Int, reach: Double, target: SkillTarget) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        func inReach(_ j: Int) -> Bool {
            guard j != i, !s.units[j].isStructure, s.isTargetableEnemy(j, of: team),
                  !s.units[j].has(.invulnerable) else { return false }
            let r = reach + s.units[j].radius
            return s.units[j].pos.distanceSquared(to: pos) <= r * r
        }
        if case .unit(let id) = target, let j = s.index(of: id), inReach(j) { return j }

        var best: Int?
        var bestKey = Double.infinity
        for j in s.units.indices where inReach(j) {
            let hero = s.units[j].kind == .hero
            var key: Double
            switch target {
            case .point(let p):
                key = s.units[j].pos.distanceSquared(to: p)
            case .direction(let d):
                let delta = s.units[j].pos - pos
                let len = delta.length
                let cosine = len > 1e-9 ? delta.dot(d.normalized) / len : 1
                key = (1 - cosine) * 1e7 + len
            case .unit, .none:
                key = hero ? max(0, s.units[j].hp) + s.units[j].totalShield : s.units[j].pos.distanceSquared(to: pos)
            }
            // ヒーローを先に（同じ基準の中で）
            if !hero { key += 1e12 }
            if key < bestKey {
                bestKey = key
                best = j
            }
        }
        return best
    }
}
