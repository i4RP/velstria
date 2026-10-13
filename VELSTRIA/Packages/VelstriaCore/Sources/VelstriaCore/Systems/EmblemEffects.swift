import Foundation

// 担当: core-economy
// エンブレムの効果（Data/EmblemCatalog.swift のセットの能力値とタレント。docs/EMBLEMS.md）。旧ルーンの置き換え。
// ・セットの能力値と能力値だけのタレント（1 段目・武器マスター・血の祭典）は ItemStats.apply が装備と同じ所で足す。
// ・HP・位置で変わる能力値（強靭・山野の主）は StatCalculator が毎 tick（applyRuntimeStats）。
// ・「命中したら」「スキルを使ったら」などは CombatSystem / SkillSystem / DeathSystem のフックから。
// ・追加ダメージは DamageSource.item で与える（通常攻撃の命中・吸血・装備やエンブレムの効果を再び起こさない）。
// ・時間・距離は Velstria の単位（MLBB の 1 マス ≒ 100）。「レベルに応じる」はヒーローのレベル 1〜15 の線形補間。

extension Balance {
    /// エンブレムのタレントの係数（MLBB Fandom の Emblems、2026-04 / 1.9.64。日本語クライアントで確かめたものは EmblemCatalog に注記）。
    public enum Emblems {
        // MARK: 1 段目
        public static let thrillAdaptive: Double = 16
        public static let swiftAttackSpeed: Double = 0.10
        public static let vitalityHP: Double = 225
        public static let rupturePenetration: Double = 5
        public static let inspireCooldownReduction: Double = 0.05
        public static let inspireManaRegen: Double = 2
        public static let firmnessDefense: Double = 8
        public static let agilityMoveSpeed: Double = 0.04
        public static let fatalCritChance: Double = 0.05
        public static let fatalCritDamage: Double = 0.05

        // MARK: 2 段目
        public static let wildernessMoveSpeed: Double = 0.10
        /// 敵ヒーロー・ボスと交戦中は半分。
        public static let wildernessCombatScale: Double = 0.5
        public static let seasonedBossBonus: Double = 0.15
        public static let seasonedCreepBonus: Double = 0.075
        public static let tenacityHPRatio: Double = 0.5
        public static let tenacityDamageReduction: Double = 0.05
        public static let masterAssassinBonus: Double = 0.07
        /// 「近く」の半径（MLBB は数値を出していない。遠隔の射程 550 より少し広い近似）。
        public static let masterAssassinRadius: Double = 800
        public static let bargainPriceRatio: Double = 0.95
        public static let festivalSpellVamp: Double = 0.06
        public static let festivalPerStack: Double = 0.005
        public static let festivalMaxStacks = 12
        public static let pullCooldownReduction: Double = 0.12
        public static let pullPerStack: Double = 0.01
        public static let pullMaxStacks = 8
        public static let weaponMasterBonus: Double = 0.08

        // MARK: コア
        public static let impureRageMaxHP: Double = 0.04
        public static let impureRageMana: Double = 0.02
        public static let impureRageHP: Double = 0.01
        public static let impureRageNonHeroCap: Double = 120
        public static let impureRageCooldown: Double = 5
        public static let quantumMoveSpeed: Double = 0.30
        public static let quantumDuration: Double = 1.5
        public static let quantumHealMin: Double = 75
        public static let quantumHealMax: Double = 180
        public static let quantumCooldown: Double = 10
        public static let warCryHits = 3
        public static let warCryBonus: Double = 0.08
        public static let warCryDuration: Double = 6
        public static let warCryCooldown: Double = 6
        /// 同じスキルの何度ものダメージを 1 回と数える間隔（秒。何度も当たるスキルの近似）。
        public static let warCrySkillWindow: Double = 1
        public static let temporalRate: Double = 1.5
        public static let temporalDuration: Double = 4
        public static let temporalExtend: Double = 2
        public static let temporalCooldown: Double = 20
        public static let concussiveBase: Double = 100
        public static let concussiveMaxHP: Double = 0.07
        /// 「周りの敵」の半径（対象の周り。MLBB は数値を出していない）。
        public static let concussiveRadius: Double = 300
        public static let concussiveCooldown: Double = 15
        public static let killingSpreeHPRatio: Double = 0.3
        public static let killingSpreeLostHP: Double = 0.15
        public static let killingSpreeMoveSpeed: Double = 0.2
        public static let killingSpreeDuration: Double = 3
        public static let killingSpreeCooldown: Double = 30
        public static let lethalThreshold: Double = 0.07
        public static let lethalHits = 3
        public static let lethalWindow: Double = 5
        public static let lethalDamageMin: Double = 162
        public static let lethalDamageMax: Double = 750
        public static let lethalCooldown: Double = 15
        public static let braveSmiteHeal: Double = 0.05
        public static let braveSmiteCooldown: Double = 6
        public static let focusBonus: Double = 0.06
        public static let focusMoveSpeed: Double = 0.10
        public static let focusDuration: Double = 3
        public static let focusCooldown: Double = 4
        public static let weaknessSlow: Double = 0.5
        public static let weaknessAttackSpeed: Double = 0.3
        public static let weaknessDuration: Double = 1
        public static let weaknessCooldown: Double = 10
        public static let weaknessPerAttack: Double = 1
        public static let weaknessMinCooldown: Double = 3
    }
}

/// ヒーローごとのエンブレムの状態（コアタレントの CD・窓・スタック）。
public struct EmblemRuntime: Codable, Hashable, Sendable {
    /// コアタレントが次に働ける時刻。
    public var readyAt: Double = 0
    /// コアタレントが最後に働いた時刻（弱点分析の最短 3 秒）。
    public var lastAt: Double = -999
    /// 効果の終わり（時の支配の加速・集中マークの印）。
    public var until: Double = 0
    /// 集中マークを付けた敵。
    public var markedID: EntityID?
    /// ヒーローのキル・アシストの数（血の祭典・立て直しのスタック。死んでも消えない）。
    public var takedowns: Int = 0
    /// 鬨の声: 数えた命中の数と、通常攻撃（0）・スキル枠（1〜3）ごとの最後に数えた時刻。
    public var hits: Int = 0
    public var countedAt: [Double] = []
    /// 致死の発火: 大きなダメージを与えた敵と時刻（DamageRecord.sourceID = 対象）。
    public var bigHits: [DamageRecord] = []
    /// 山野の主: 最後に星喰竜・古環の巨像と交戦した時刻。
    public var bossCombatAt: Double = -999

    public init() {}

    func ready(at now: Double) -> Bool { now + 1e-9 >= readyAt }
}

public enum EmblemEffects {
    typealias K = Balance.Emblems

    // MARK: - 能力値

    /// セットの能力値と、能力値だけのタレントの合計（ItemStats.apply が装備と合わせて足す）。
    /// 割合はすべて 0.1 = 10%。適応（攻撃・貫通）は向きを決める前の量。
    struct StatBlock {
        var attack: Double = 0
        var power: Double = 0
        var adaptiveAttack: Double = 0
        var adaptivePenFlat: Double = 0
        var adaptivePenPct: Double = 0
        var magicPenFlat: Double = 0
        var hp: Double = 0
        var defense: Double = 0
        var hpRegen: Double = 0
        var manaRegen: Double = 0
        var moveSpeedPct: Double = 0
        var attackSpeedPct: Double = 0
        var cooldownReduction: Double = 0
        var lifesteal: Double = 0
        var spellVamp: Double = 0
        var healShieldPower: Double = 0
        var critChance: Double = 0
        var critDamage: Double = 0
        /// 武器マスター（装備・エンブレム・天賦で得た物理攻撃・魔法攻撃の増加率）。
        var weaponMaster: Double = 0
    }

    /// エンブレムの能力値（セットのレベルの値 + 解放レベル以上の段のタレント）。hero はスタック（血の祭典）用。
    static func statBlock(_ e: EmblemLoadout, hero: HeroData?) -> StatBlock {
        var b = StatBlock()
        for a in EmblemCatalog.set(e.set).attributes {
            let v = a.value(level: e.level)
            let p = v / 100
            switch a.kind {
            case .hybridRegen:
                b.hpRegen += v
                b.manaRegen += v
            case .hp: b.hp += v
            case .adaptiveAttack: b.adaptiveAttack += v
            case .hybridDefense: b.defense += v
            case .hpRegen: b.hpRegen += v
            case .adaptivePenetration: b.adaptivePenFlat += v
            case .adaptivePenetrationPct: b.adaptivePenPct += p
            case .movementSpeedPct: b.moveSpeedPct += p
            case .magicPower: b.power += v
            case .cooldownReductionPct: b.cooldownReduction += p
            case .magicPenetration: b.magicPenFlat += v
            case .hybridLifestealPct:
                b.lifesteal += p
                b.spellVamp += p
            case .healingEffectPct: b.healShieldPower += p
            case .attackSpeedPct: b.attackSpeedPct += p
            }
        }
        switch e.activeTier1 {
        case .thrill: b.adaptiveAttack += K.thrillAdaptive
        case .swift: b.attackSpeedPct += K.swiftAttackSpeed
        case .vitality: b.hp += K.vitalityHP
        case .rupture: b.adaptivePenFlat += K.rupturePenetration
        case .inspire:
            b.cooldownReduction += K.inspireCooldownReduction
            b.manaRegen += K.inspireManaRegen
        case .firmness: b.defense += K.firmnessDefense
        case .agility: b.moveSpeedPct += K.agilityMoveSpeed
        case .fatal:
            b.critChance += K.fatalCritChance
            b.critDamage += K.fatalCritDamage
        default: break
        }
        switch e.activeTier2 {
        case .festivalOfBlood:
            let n = min(K.festivalMaxStacks, max(0, hero?.emblemRuntime.takedowns ?? 0))
            b.spellVamp += K.festivalSpellVamp + K.festivalPerStack * Double(n)
        case .weaponMaster:
            b.weaponMaster = K.weaponMasterBonus
        default: break
        }
        return b
    }

    /// HP・位置・交戦で変わる能力値（強靭・山野の主）。StatCalculator が装備の時間効果の後・状態効果の前に呼ぶ。
    static func applyRuntimeStats(_ u: Unit, to stats: inout Stats, time now: Double, map: MapDefinition) {
        guard let h = u.hero, let e = h.emblem else { return }
        switch e.activeTier2 {
        case .tenacity:
            let ratio = stats.maxHP > 0 ? max(0, u.hp) / stats.maxHP : 1
            if ratio < K.tenacityHPRatio { stats.damageReduction += K.tenacityDamageReduction }
        case .wildernessBlessing:
            guard map.isInWilderness(u.pos) else { break }
            let fighting = now - u.lastCombatTime <= Balance.combatTimeout
                || now - h.emblemRuntime.bossCombatAt <= Balance.combatTimeout
            stats.moveSpeed *= 1 + K.wildernessMoveSpeed * (fighting ? K.wildernessCombatScale : 1)
        default:
            break
        }
    }

    /// 掘り出し上手: 装備の購入価格の倍率（ItemSystem.combine）。
    public static func purchasePriceMultiplier(_ h: HeroData) -> Double {
        h.emblem?.activeTier2 == .bargainHunter ? K.bargainPriceRatio : 1
    }

    /// 立て直し: バトルスペル・装備のアクティブの CD の倍率。
    public static func spellCooldownMultiplier(_ h: HeroData) -> Double {
        guard h.emblem?.activeTier2 == .pullYourselfTogether else { return 1 }
        let n = min(K.pullMaxStacks, max(0, h.emblemRuntime.takedowns))
        return max(0, 1 - K.pullCooldownReduction - K.pullPerStack * Double(n))
    }

    /// 時の支配: スキル枠 slot の CD が減る速さの倍率（必殺技の後 4 秒間、必殺技以外が 1.5 倍）。
    public static func skillCooldownRate(_ h: HeroData, slot: Int, time now: Double) -> Double {
        guard h.emblem?.activeCore == .temporalReign, slot != SkillSlot.ultimate.rawValue, slot != SkillSlot.passive.rawValue,
              now < h.emblemRuntime.until else { return 1 }
        return K.temporalRate
    }

    /// 「レベルに応じる」値（ヒーローのレベル 1 → lo、最大レベル → hi の線形補間）。
    static func byLevel(_ level: Int, _ lo: Double, _ hi: Double) -> Double {
        let n = Double(max(1, Balance.maxLevel - 1))
        let t = min(1, max(0, Double(level - 1) / n))
        return lo + (hi - lo) * t
    }

    // MARK: - 与ダメ

    /// 与ダメ補正（熟練ハンター・暗殺の達人・集中マーク）。CombatSystem.dealDamage が装備の補正と同じ所で足す。
    static func outgoingDamageBonus(_ s: SimState, _ ctx: SimContext, attacker a: Int, target t: Int,
                                    source: DamageSource) -> Double {
        guard s.units[a].kind == .hero, s.units[t].team != s.units[a].team else { return 0 }
        var bonus = 0.0
        if s.units[t].kind == .hero { bonus += focusBonus(s, attacker: a, target: t) }
        guard let e = s.units[a].hero?.emblem else { return bonus }
        switch e.activeTier2 {
        case .seasonedHunter:
            // 狩猟印（バトルスペル）のダメージには効かない
            guard source != .spell, s.units[t].kind == .monster, let m = s.units[t].monster else { break }
            bonus += m.kind.isBoss ? K.seasonedBossBonus : K.seasonedCreepBonus
        case .masterAssassin:
            guard s.units[t].kind == .hero else { break }
            let r2 = K.masterAssassinRadius * K.masterAssassinRadius
            let me = s.units[a].pos
            guard me.distanceSquared(to: s.units[t].pos) <= r2 else { break }
            var near = 0
            for j in s.units.indices where s.units[j].kind == .hero && s.units[j].team == s.units[t].team
                && CombatSystem.isLiving(s, j) && me.distanceSquared(to: s.units[j].pos) <= r2 {
                near += 1
                if near > 1 { break }
            }
            if near == 1 { bonus += K.masterAssassinBonus }
        default:
            break
        }
        return bonus
    }

    /// 集中マーク: 攻撃者の味方（本人を含む）が付けた印の付いた敵ヒーローへの与ダメ補正。
    static func focusBonus(_ s: SimState, attacker a: Int, target t: Int) -> Double {
        focusMarker(s, attacker: a, target: t) != nil ? K.focusBonus : 0
    }

    /// 攻撃者の味方（本人を含む）のうち、対象に集中マークを付けているヒーロー。
    static func focusMarker(_ s: SimState, attacker a: Int, target t: Int) -> Int? {
        let tid = s.units[t].id, team = s.units[a].team, now = s.time
        for j in s.units.indices where s.units[j].kind == .hero && s.units[j].team == team {
            guard let h = s.units[j].hero, h.emblem?.activeCore == .focusingMark, h.emblemRuntime.markedID == tid,
                  now < h.emblemRuntime.until else { continue }
            return j
        }
        return nil
    }

    // MARK: - ダメージを与えた・受けた

    /// ヒーローが敵にダメージを与えた後（CombatSystem.dealDamage。装備・エンブレムの追加ダメージ・継続ダメージ・泉は除く）。
    static func onDamageDealt(_ s: inout SimState, _ ctx: SimContext, attacker a: Int, target t: Int, dealt: Double,
                              type: DamageType, source: DamageSource) {
        guard s.units[a].kind == .hero, s.units[t].team != s.units[a].team, dealt > 0 else { return }
        switch source {
        case .item, .dot, .fountain, .passive: return
        default: break
        }
        let now = s.time
        let targetIsHero = s.units[t].kind == .hero
        // 集中マーク: 印の付いた敵を攻撃した味方は加速（誰が攻撃しても働く）
        if targetIsHero, let marker = focusMarker(s, attacker: a, target: t), CombatSystem.isLiving(s, a) {
            let left = max(0, (s.units[marker].hero?.emblemRuntime.until ?? now) - now)
            if left > 0 {
                CombatSystem.addStatus(&s, targetIndex: a, StatusEffect(kind: .speedBoost, duration: left, magnitude: K.focusMoveSpeed,
                                                                        sourceID: s.units[marker].id, tag: focusTag))
            }
        }
        guard let e = s.units[a].hero?.emblem else { return }
        if s.units[t].monster?.kind.isBoss == true { s.units[a].hero!.emblemRuntime.bossCombatAt = now }
        guard CombatSystem.isLiving(s, a) else { return }
        var rt = s.units[a].hero!.emblemRuntime
        let attackerID = s.units[a].id
        let level = s.units[a].hero?.level ?? 1
        switch e.activeCore {
        case .impureRage:
            guard source.isSkill, rt.ready(at: now) else { break }
            rt.readyAt = now + K.impureRageCooldown
            rt.lastAt = now
            s.units[a].hero!.emblemRuntime = rt
            if CombatSystem.isLiving(s, t) {
                var extra = s.units[t].stats.maxHP * K.impureRageMaxHP
                if !targetIsHero { extra = min(extra, K.impureRageNonHeroCap) }
                let kind: DamageType = ItemEffects.adaptiveIsMagic(s.units[a], ctx.master) ? .magic : .physical
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t, amount: extra, type: kind,
                                        source: .item, isCrit: false, appliesOnHit: false)
            }
            guard CombatSystem.isLiving(s, a) else { break }
            if s.units[a].hero?.resourceKind == .mana {
                let mx = s.units[a].stats.maxResource
                s.units[a].resource = min(mx, s.units[a].resource + mx * K.impureRageMana)
            } else {
                CombatSystem.heal(&s, ctx, sourceID: attackerID, targetIndex: a, amount: s.units[a].stats.maxHP * K.impureRageHP)
            }
        case .quantumCharge:
            guard source == .basicAttack, rt.ready(at: now) else { break }
            rt.readyAt = now + K.quantumCooldown
            rt.lastAt = now
            s.units[a].hero!.emblemRuntime = rt
            CombatSystem.addStatus(&s, targetIndex: a, StatusEffect(kind: .speedBoost, duration: K.quantumDuration,
                                                                    magnitude: K.quantumMoveSpeed, sourceID: attackerID,
                                                                    tag: "emblem.quantumCharge"))
            CombatSystem.heal(&s, ctx, sourceID: attackerID, targetIndex: a, amount: byLevel(level, K.quantumHealMin, K.quantumHealMax))
        case .warCry:
            guard targetIsHero, rt.ready(at: now) else { break }
            // 通常攻撃は 1 発ごと（同じ tick の追加ヒットはまとめる）、スキルは同じ枠の warCrySkillWindow 秒以内をまとめる
            let key: Int
            let window: Double
            switch source {
            case .basicAttack: key = 0; window = Balance.dt * 0.5
            case .skill(let slot): key = slot.rawValue; window = K.warCrySkillWindow
            default: return
            }
            while rt.countedAt.count <= key { rt.countedAt.append(-999) }
            guard now - rt.countedAt[key] > window else { break }
            rt.countedAt[key] = now
            rt.hits += 1
            if rt.hits >= K.warCryHits {
                rt.hits = 0
                rt.readyAt = now + K.warCryCooldown
                rt.lastAt = now
                s.units[a].hero!.emblemRuntime = rt
                CombatSystem.addStatus(&s, targetIndex: a, StatusEffect(kind: .damageBoost, duration: K.warCryDuration,
                                                                        magnitude: K.warCryBonus, sourceID: attackerID,
                                                                        tag: "emblem.warCry"))
            } else {
                s.units[a].hero!.emblemRuntime = rt
            }
        case .killingSpree:
            guard targetIsHero, rt.ready(at: now), s.units[t].hpRatio < K.killingSpreeHPRatio else { break }
            rt.readyAt = now + K.killingSpreeCooldown
            rt.lastAt = now
            s.units[a].hero!.emblemRuntime = rt
            let lost = max(0, s.units[a].stats.maxHP - s.units[a].hp)
            CombatSystem.heal(&s, ctx, sourceID: attackerID, targetIndex: a, amount: lost * K.killingSpreeLostHP)
            CombatSystem.addStatus(&s, targetIndex: a, StatusEffect(kind: .speedBoost, duration: K.killingSpreeDuration,
                                                                    magnitude: K.killingSpreeMoveSpeed, sourceID: attackerID,
                                                                    tag: "emblem.killingSpree"))
        case .lethalIgnition:
            guard targetIsHero, dealt > s.units[t].stats.maxHP * K.lethalThreshold else { break }
            let tid = s.units[t].id
            rt.bigHits.removeAll { now - $0.time > K.lethalWindow + 1e-9 }
            rt.bigHits.append(DamageRecord(sourceID: tid, time: now))
            let n = rt.bigHits.filter { $0.sourceID == tid }.count
            guard n >= K.lethalHits, rt.ready(at: now), CombatSystem.isLiving(s, t) else {
                s.units[a].hero!.emblemRuntime = rt
                break
            }
            rt.bigHits.removeAll { $0.sourceID == tid }
            rt.readyAt = now + K.lethalCooldown
            rt.lastAt = now
            s.units[a].hero!.emblemRuntime = rt
            let kind: DamageType = ItemEffects.adaptiveIsMagic(s.units[a], ctx.master) ? .magic : .physical
            CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t,
                                    amount: byLevel(level, K.lethalDamageMin, K.lethalDamageMax), type: kind,
                                    source: .item, isCrit: false, appliesOnHit: false)
        case .braveSmite:
            guard targetIsHero, source.isSkill, rt.ready(at: now) else { break }
            rt.readyAt = now + K.braveSmiteCooldown
            rt.lastAt = now
            s.units[a].hero!.emblemRuntime = rt
            CombatSystem.heal(&s, ctx, sourceID: attackerID, targetIndex: a, amount: s.units[a].stats.maxHP * K.braveSmiteHeal)
        case .focusingMark:
            guard targetIsHero, rt.ready(at: now), CombatSystem.isLiving(s, t) else { break }
            rt.readyAt = now + K.focusCooldown
            rt.lastAt = now
            rt.markedID = s.units[t].id
            rt.until = now + K.focusDuration
            s.units[a].hero!.emblemRuntime = rt
        default:
            break
        }
    }

    /// ヒーローがダメージを受けた後（山野の主: ボスとの交戦の記録）。
    static func onDamageTaken(_ s: inout SimState, victim t: Int, attacker a: Int?) {
        guard let a, s.units[t].hero?.emblem?.activeTier2 == .wildernessBlessing,
              s.units[a].monster?.kind.isBoss == true else { return }
        s.units[t].hero!.emblemRuntime.bossCombatAt = s.time
    }

    // MARK: - 通常攻撃

    /// 通常攻撃が命中した時（ダメージの後。装備の命中時効果と同じ所）。強震撃・弱点分析。
    static func onBasicAttackLanded(_ s: inout SimState, _ ctx: SimContext, attacker a: Int, target t: Int) {
        guard s.units[a].kind == .hero, let e = s.units[a].hero?.emblem, s.units[t].team != s.units[a].team,
              !s.units[t].isStructure, CombatSystem.isLiving(s, a) else { return }
        let now = s.time
        let attackerID = s.units[a].id
        var rt = s.units[a].hero!.emblemRuntime
        switch e.activeCore {
        case .concussiveBlast:
            guard rt.ready(at: now) else { break }
            rt.readyAt = now + K.concussiveCooldown
            rt.lastAt = now
            s.units[a].hero!.emblemRuntime = rt
            let damage = K.concussiveBase + K.concussiveMaxHP * s.units[a].stats.maxHP
            for j in ItemEffects.aoeTargets(s, team: s.units[a].team, center: s.units[t].pos, radius: K.concussiveRadius) {
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: j, amount: damage, type: .magic,
                                        source: .item, isCrit: false, appliesOnHit: false)
            }
        case .weaknessFinder:
            if !rt.ready(at: now) {
                // 通常攻撃 1 回で 1 秒縮む（前回の発動から最短 3 秒）
                rt.readyAt = max(rt.lastAt + K.weaknessMinCooldown, rt.readyAt - K.weaknessPerAttack)
                s.units[a].hero!.emblemRuntime = rt
                break
            }
            guard CombatSystem.isLiving(s, t) else { break }
            rt.readyAt = now + K.weaknessCooldown
            rt.lastAt = now
            s.units[a].hero!.emblemRuntime = rt
            CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .slow, duration: K.weaknessDuration, magnitude: K.weaknessSlow,
                                                                    sourceID: attackerID, tag: "emblem.weaknessFinder"))
            CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .attackSpeedBoost, duration: K.weaknessDuration,
                                                                    magnitude: -K.weaknessAttackSpeed, sourceID: attackerID,
                                                                    tag: "emblem.weaknessFinder"))
        default:
            break
        }
    }

    // MARK: - スキル・キル

    /// スキルを使った時（時の支配: 必殺技で加速の窓を開く）。
    static func onSkillCast(_ s: inout SimState, caster c: Int, slot: SkillSlot) {
        guard slot == .ultimate, let h = s.units[c].hero, h.emblem?.activeCore == .temporalReign,
              h.emblemRuntime.ready(at: s.time) else { return }
        let now = s.time
        s.units[c].hero!.emblemRuntime.readyAt = now + K.temporalCooldown
        s.units[c].hero!.emblemRuntime.lastAt = now
        s.units[c].hero!.emblemRuntime.until = now + K.temporalDuration
    }

    /// 敵ヒーローを倒した・アシストした時（血の祭典・立て直しのスタック、時の支配の延長）。
    static func onKillOrAssist(_ s: inout SimState, hero i: Int) {
        guard let h = s.units[i].hero, let e = h.emblem else { return }
        s.units[i].hero!.emblemRuntime.takedowns += 1
        if e.activeCore == .temporalReign, s.time < h.emblemRuntime.until {
            s.units[i].hero!.emblemRuntime.until += K.temporalExtend
        }
    }

    /// 敵ヒーローを倒した時（殺戮の連鎖: CD のリセット）。
    static func onKill(_ s: inout SimState, hero i: Int) {
        guard s.units[i].hero?.emblem?.activeCore == .killingSpree else { return }
        s.units[i].hero!.emblemRuntime.readyAt = 0
    }

    static let focusTag = "emblem.focusingMark"
}
