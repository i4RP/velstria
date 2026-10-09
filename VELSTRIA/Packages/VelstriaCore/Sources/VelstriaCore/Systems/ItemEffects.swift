import Foundation

// 担当: core-economy
// 装備の固有効果（Mobile Legends の装備の固有パッシブ・アクティブをそのまま写したもの。2026-10 の総入れ替え）。
// 仕様と係数は tools/equipment_spec.mjs（ItemDef.effects = [ItemEffectRef(id: ItemEffectKind の rawValue, v: 係数)]）。
// 能力値（攻撃・貫通・吸血など）は ItemStats が足す。ここは「命中したら」「スキルを使ったら」などの振る舞いと、
// 時間で変わる能力値（スタック・一時的な強化）を持つ。
// ・同じ種類の効果は重ならない（MLBB の「ユニークパッシブ」）。複数の装備が持つ時は Tier の高い装備の係数を使う。
// ・追加ダメージは DamageSource.item で与える（通常攻撃の命中・吸血・装備の効果を再び起こさない）。
// ・時間・距離は Velstria の単位（MLBB の 1 マス ≒ 100）。

extension Balance {
    public enum Items {
        /// コントロール時間短縮の上限。
        public static let maxCCReduction: Double = 0.7
        /// 同じスキルの他の命中にも共鳴（ボルトロッド）を乗せる猶予（秒）。
        public static let resonateWindow: Double = 0.1
        /// ウィンドテラーの台風の魔法ダメージ（攻撃速度 1 以下で 150、3 以上で 362、その間は 106 × 攻撃速度 + 44）。
        public static let typhoonMin: Double = 150
        public static let typhoonMax: Double = 362
        public static let typhoonPerAttackSpeed: Double = 106
        public static let typhoonFlat: Double = 44
        /// ボットがウィンタークラウン・ナチュラルウィンドを使う HP の割合。
        public static let botActiveHPRatio: Double = 0.3
    }
}

public enum ItemEffectKind: String, CaseIterable, Codable, Hashable, Sendable {
    // 攻撃
    case maleficEnergy, supremeWarrior, lifebane, punish, dragonScale, lifeline, huntChase, despair, ambush, typhoon
    case divineJustice, doom, frenzy, breaker, frozen, timestream, lethality, fightingSpirit, windChant, goldenStaff
    case corrosive, impulse, engulf, devour, crossbow
    // 魔法
    case butterfly, oasisBlessing, geniusShred, resonate, guardWings, crisis, scorch, iceBound, recharge, mystery
    case spellbreaker, destiny, gift, affliction, manaSpring, magicMastery, judgement
    // 防御
    case holyBlessing, chastise, redemption, bruteForce, immortal, fortress, lifebaneAura, valkyrie, deter, recovery
    case defender, burningSoul, curse, thunderbolt, demonize, defiance, bladedArmor
    // 移動
    case mysticism, valor

    /// `ItemRuntime` の配列の添字。
    var slot: Int { ItemEffectKind.slots[self] ?? 0 }
    private static let slots: [ItemEffectKind: Int] = {
        var m: [ItemEffectKind: Int] = [:]
        for (k, c) in allCases.enumerated() { m[c] = k }
        return m
    }()

    /// アクティブ（HUD のボタンで使う）か。
    public var isActive: Bool { self == .frozen || self == .windChant }
}

/// 対象ごとの装備効果の印（焼灼の燃焼、オアシスのフラスコの対象ごとの CD）。
public struct ItemMark: Codable, Hashable, Sendable {
    public var kind: Int
    public var targetID: EntityID
    public var until: Double
    public var nextTick: Double
}

/// ヒーローごとの装備効果の状態（クールダウン・スタック・窓）。
public struct ItemRuntime: Codable, Hashable, Sendable {
    /// 効果ごとの「次に働ける時刻」（`ItemEffectKind.slot` の添字。足りない分は 0）。
    public var readyAt: [Double] = []
    /// 効果ごとの一時的な強化の終わり。
    public var untilAt: [Double] = []
    /// 効果ごとのスタック数。
    public var stacks: [Double] = []
    /// 効果ごとの最後にスタックが増えた・発動した時刻（スタックの期限・発動の間隔）。
    public var lastAt: [Double] = []
    /// 最後にスキルを使った時刻（エンドレスバトル・アズールブレイド・星の大鎌の窓）。
    public var skillCastAt: Double = -999
    /// ハンターストライク: 続けてダメージを与えている敵と回数。
    public var hitTargetID: EntityID?
    public var hitCount: Int = 0
    /// 最後にダメージを受けた時刻（ブラッドウィングのシールドの張り直し）。
    public var damagedAt: Double = -999
    /// ウィッシュランタン: 敵ヒーローに与えた魔法ダメージ（軽減前）の累計。
    public var magicTally: Double = 0
    /// 如意棒: クリティカルでない通常攻撃の数。
    public var attackCount: Int = 0
    /// 効果中のポーション（所持枠を使わない消耗品）。
    public var potionID: String?
    public var potionUntil: Double = 0
    /// 対象ごとの印。
    public var marks: [ItemMark] = []
    /// 継続回復（贖罪・贈り物）: 毎秒の HP・MP の回復量と終わり。
    public var regenHP: Double = 0
    public var regenHPUntil: Double = 0
    public var regenMana: Double = 0
    public var regenManaUntil: Double = 0
    /// イモータル: 復活待ち（その場で復活する位置）。
    public var revivePos: Vec2?

    public init() {}

    private static func get(_ a: [Double], _ i: Int, _ d: Double) -> Double { i < a.count ? a[i] : d }
    private static func set(_ a: inout [Double], _ i: Int, _ v: Double, _ d: Double) {
        if a.count <= i { a.append(contentsOf: [Double](repeating: d, count: i + 1 - a.count)) }
        a[i] = v
    }

    func ready(_ k: ItemEffectKind, at now: Double) -> Bool { now + 1e-9 >= Self.get(readyAt, k.slot, 0) }
    func readyTime(_ k: ItemEffectKind) -> Double { Self.get(readyAt, k.slot, 0) }
    mutating func setReady(_ k: ItemEffectKind, at t: Double) { Self.set(&readyAt, k.slot, t, 0) }
    func until(_ k: ItemEffectKind) -> Double { Self.get(untilAt, k.slot, 0) }
    mutating func setUntil(_ k: ItemEffectKind, _ t: Double) { Self.set(&untilAt, k.slot, t, 0) }
    func stack(_ k: ItemEffectKind) -> Double { Self.get(stacks, k.slot, 0) }
    mutating func setStack(_ k: ItemEffectKind, _ v: Double) { Self.set(&stacks, k.slot, v, 0) }
    func last(_ k: ItemEffectKind) -> Double { Self.get(lastAt, k.slot, -999) }
    mutating func setLast(_ k: ItemEffectKind, _ t: Double) { Self.set(&lastAt, k.slot, t, -999) }

    /// 期限（最後に増えてから duration 秒）内のスタック数。
    func liveStacks(_ k: ItemEffectKind, now: Double, duration: Double) -> Double {
        now < last(k) + duration ? stack(k) : 0
    }

    /// 間隔 interval ごとに 1 つずつ増えるスタック（最大 cap）。増えたら true。
    mutating func gainStack(_ k: ItemEffectKind, now: Double, interval: Double, duration: Double, cap: Double) -> Bool {
        guard now - last(k) + 1e-9 >= interval else { return false }
        let cur = now < last(k) + duration ? stack(k) : 0
        setStack(k, min(cap, cur + 1))
        setLast(k, now)
        return true
    }
}

/// HUD のアクティブボタン用の情報。
public struct ItemActiveInfo: Hashable, Sendable {
    public var itemID: String
    public var kind: ItemEffectKind
    /// 残りクールダウン（0 なら使える）。
    public var remaining: Double
    public var cooldown: Double
}

public enum ItemEffects {
    typealias Active = (kind: ItemEffectKind, v: [Double])

    /// 所持品とポーションの効果（同じ種類は Tier の高い装備の 1 つだけ。並びは種類の宣言順で決定的）。
    static func active(_ u: Unit, _ master: MasterData) -> [Active] {
        guard let h = u.hero, !h.items.isEmpty else { return [] }
        var best: [ItemEffectKind: (tier: Int, v: [Double])] = [:]
        for id in h.items {
            guard let it = master.item(id) else { continue }
            for e in it.effects {
                guard let k = ItemEffectKind(rawValue: e.id) else { continue }
                if let cur = best[k], cur.tier >= it.tier { continue }
                best[k] = (it.tier, e.v)
            }
        }
        return ItemEffectKind.allCases.compactMap { k in best[k].map { (k, $0.v) } }
    }

    /// 効果 kind の係数（持っていなければ nil。Tier の高い装備が優先）。
    static func values(_ kind: ItemEffectKind, of u: Unit, _ master: MasterData) -> [Double]? {
        guard let items = u.hero?.items else { return nil }
        var out: (tier: Int, v: [Double])?
        for id in items {
            guard let it = master.item(id) else { continue }
            for e in it.effects where e.id == kind.rawValue {
                if let o = out, o.tier >= it.tier { continue }
                out = (it.tier, e.v)
            }
        }
        return out?.v
    }

    /// 射手・メイジ・サポートなどで半分になる効果の倍率。
    static func roleScale(_ role: Role?, halfFor roles: [Role], scale: Double) -> Double {
        guard let role, roles.contains(role) else { return 1 }
        return scale
    }

    /// 適応（攻撃力か魔力か）でヒーローの主なダメージが魔法か。
    static func adaptiveIsMagic(_ u: Unit, _ master: MasterData) -> Bool {
        guard let h = u.hero else { return false }
        if u.stats.abilityPower != u.stats.attack {
            let extraPower = u.stats.abilityPower
            let extraAttack = u.stats.attack - u.baseStats.attack
            if extraPower != extraAttack { return extraPower > extraAttack }
        }
        return master.skills(forHero: h.heroID).first?.damageType == .magic
    }

    // MARK: - 能力値

    /// 能力値だけで決まる効果（ItemStats がルーンの後に呼ぶ）。base = レベル成長だけの能力値。
    static func applyStatEffects(items: [String], hero: HeroData?, to stats: inout Stats, base: Stats, master: MasterData) {
        var found: [ItemEffectKind: (tier: Int, v: [Double])] = [:]
        for id in items {
            guard let it = master.item(id) else { continue }
            for e in it.effects {
                guard let k = ItemEffectKind(rawValue: e.id) else { continue }
                if let cur = found[k], cur.tier >= it.tier { continue }
                found[k] = (it.tier, e.v)
            }
        }
        guard !found.isEmpty else { return }
        let level = Double(hero?.level ?? 1)
        if let v = found[.maleficEnergy]?.v, v.count >= 1 { stats.attackRange *= 1 + v[0] }
        if let v = found[.goldenStaff]?.v, v.count >= 1 {
            // 追加のクリティカル率を攻撃速度へ（クリティカルは出なくなる）
            stats.attackSpeed *= 1 + max(0, stats.critChance) * v[0]
            stats.critChance = 0
        }
        if let v = found[.mystery]?.v, v.count >= 2 { stats.abilityPower *= 1 + v[0] + v[1] * level }
        if let v = found[.magicMastery]?.v, v.count >= 1 { stats.cooldownReductionCap += v[0] }
        if let v = found[.dragonScale]?.v, v.count >= 3 {
            let extra = max(0, stats.attack - base.attack)
            var def = min(v[1], extra * v[0])
            if hero?.role != .duelist { def *= v[2] }
            stats.armor += def
            stats.magicResist += def
        }
    }

    /// 時間で変わる能力値（スタック・一時的な強化）。StatCalculator が装備・祝福の後に呼ぶ。
    static func applyRuntimeStats(_ u: Unit, to stats: inout Stats, time now: Double, master: MasterData) {
        guard let h = u.hero, !h.items.isEmpty else { return }
        let rt = h.itemRuntime
        let level = Double(h.level)
        for (kind, v) in active(u, master) {
            switch kind {
            case .despair where v.count >= 3:
                if now < rt.until(.despair) { stats.attack *= 1 + v[1] }
            case .fightingSpirit where v.count >= 5:
                let n = rt.liveStacks(.fightingSpirit, now: now, duration: v[1])
                stats.attack += v[0] * n * roleScale(h.role, halfFor: [.ranger, .arcanist, .support], scale: v[4])
            case .impulse where v.count >= 3:
                stats.attackSpeed *= 1 + v[0] * rt.liveStacks(.impulse, now: now, duration: v[1])
            case .recharge where v.count >= 5:
                stats.abilityPower += v[0] * rt.liveStacks(.recharge, now: now, duration: v[4])
            case .destiny where v.count >= 5:
                let d = (v[0] + v[1] * level) * rt.liveStacks(.destiny, now: now, duration: v[2])
                stats.armor += d
                stats.magicResist += d
            case .valor where v.count >= 3:
                stats.armor += v[0] * rt.liveStacks(.valor, now: now, duration: v[1])
            case .holyBlessing where v.count >= 5:
                stats.magicResist += (v[0] + v[1] * level) * rt.liveStacks(.holyBlessing, now: now, duration: v[2])
            case .bruteForce where v.count >= 6:
                let n = rt.liveStacks(.bruteForce, now: now, duration: v[2])
                guard n > 0 else { break }
                if adaptiveIsMagic(u, master) { stats.abilityPower += v[0] * n } else { stats.attack += v[0] * n }
                stats.moveSpeed *= 1 + v[1] * n
                if n >= v[3] { stats.ccReduction += v[4] }
            case .guardWings where v.count >= 6:
                if u.shields.contains(where: { $0.tag == guardWingsTag }) { stats.moveSpeed += v[3] }
                if now < rt.until(.guardWings) { stats.moveSpeed += v[4] }
            case .fortress where v.count >= 3:
                let d = min(v[1], v[0] * rt.stack(.fortress))
                stats.armor += d
                stats.magicResist += d
            case .thunderbolt:
                stats.armor += rt.stack(.thunderbolt)
                stats.magicResist += rt.stack(.thunderbolt)
            default:
                break
            }
        }
        stats.ccReduction = min(Balance.Items.maxCCReduction, max(0, stats.ccReduction))
    }

    // MARK: - 与ダメ・貫通・被ダメ

    /// 与ダメ補正（懲罰・充填・反抗・絶望）。
    static func outgoingDamageBonus(_ s: inout SimState, _ ctx: SimContext, attacker a: Int, target t: Int,
                                    type: DamageType) -> Double {
        // 威嚇を受けている攻撃者の物理ダメージ（攻撃者が装備を持っていなくても働く）
        var deter = 0.0
        if type == .physical, let st = s.units[a].statuses.first(where: { $0.kind == .damageDealtReduction && $0.tag == deterTag }) {
            deter = st.magnitude
        }
        guard s.units[a].kind == .hero, s.units[a].hero?.items.isEmpty == false, s.units[t].team != s.units[a].team else { return -deter }
        let now = s.time
        var bonus = 0.0
        for (kind, v) in active(s.units[a], ctx.master) {
            switch kind {
            case .punish where v.count >= 1:
                guard s.units[t].kind == .hero else { break }
                let mine = s.units[a].stats.maxHP - s.units[a].baseStats.maxHP
                let theirs = s.units[t].stats.maxHP - s.units[t].baseStats.maxHP
                if theirs > mine { bonus += v[0] }
            case .recharge where v.count >= 5:
                if type == .magic, now < s.units[a].hero!.itemRuntime.until(.recharge) { bonus += v[3] }
            case .defiance where v.count >= 2:
                bonus += min(v[1], max(0, 1 - s.units[a].hpRatio) * v[0])
            case .despair where v.count >= 3:
                // HP が半分未満の敵（ミニオン以外）: 物理攻撃 +25% をこの一撃から（強化中でなければダメージで近似）
                guard s.units[t].kind != .minion, s.units[t].hpRatio < v[0] else { break }
                if now >= s.units[a].hero!.itemRuntime.until(.despair), type == .physical { bonus += v[1] }
                s.units[a].hero!.itemRuntime.setUntil(.despair, now + v[2])
            default:
                break
            }
        }
        return bonus - deter
    }

    /// 追加の割合貫通（破壊者・魔法破り: 対象の防御 1 につき 0.1%）。
    static func extraPenetration(_ s: SimState, _ ctx: SimContext, attacker a: Int, target t: Int, magic: Bool) -> Double {
        guard s.units[a].kind == .hero, s.units[a].hero?.items.isEmpty == false else { return 0 }
        if magic {
            guard let v = values(.spellbreaker, of: s.units[a], ctx.master), v.count >= 2 else { return 0 }
            return min(v[1], max(0, s.units[t].stats.magicResist) * v[0])
        }
        guard let v = values(.breaker, of: s.units[a], ctx.master), v.count >= 2 else { return 0 }
        return min(v[1], max(0, s.units[t].stats.armor) * v[0])
    }

    /// 通常攻撃の吸血への加算（今の装備には無い。キットの互換のため残す）。
    static func lifestealBonus(_ s: SimState, _ ctx: SimContext, attacker a: Int) -> Double { 0 }

    /// 被ダメ（防御・軽減の後、シールドの前）の補正。ナチュラルウィンド: 物理無効、ヴァルキュリアブレス: 魔法 −25%。
    static func modifyIncoming(_ s: inout SimState, _ ctx: SimContext, victim t: Int, attacker a: Int?, type: DamageType,
                               source: DamageSource, amount: Double) -> Double {
        guard s.units[t].kind == .hero, let h = s.units[t].hero, !h.items.isEmpty else { return amount }
        let now = s.time
        var out = amount
        if type == .physical, now < h.itemRuntime.until(.windChant) { return 0 }
        if type == .magic, let v = values(.valkyrie, of: s.units[t], ctx.master), v.count >= 3 {
            if now < h.itemRuntime.until(.valkyrie) {
                out *= 1 - v[0]
            } else if let a, s.units[a].kind == .hero, s.units[a].team != s.units[t].team,
                      source == .basicAttack || source.isSkill, h.itemRuntime.ready(.valkyrie, at: now) {
                s.units[t].hero!.itemRuntime.setUntil(.valkyrie, now + v[1])
                // 戦闘を離れて 5 秒たつまで次は働かない（update が戻す）
                s.units[t].hero!.itemRuntime.setReady(.valkyrie, at: .greatestFiniteMagnitude)
                out *= 1 - v[0]
            }
        }
        return out
    }

    // MARK: - 通常攻撃

    /// クリティカルが出た時（狂乱: 攻撃速度 +）。
    static func onCrit(_ s: inout SimState, _ ctx: SimContext, attacker a: Int) {
        guard s.units[a].kind == .hero, let v = values(.frenzy, of: s.units[a], ctx.master), v.count >= 2 else { return }
        CombatSystem.addStatus(&s, targetIndex: a, StatusEffect(kind: .attackSpeedBoost, duration: v[1], magnitude: v[0],
                                                                sourceID: s.units[a].id, tag: "item.frenzy"))
    }

    /// 通常攻撃が命中した時（ダメージ適用の後）。追加ダメージ・スキル後の強化・連鎖・スタック。
    static func onBasicAttackLanded(_ s: inout SimState, _ ctx: SimContext, attacker a: Int, target t: Int, dealt: Double,
                                    isCrit: Bool = false) {
        guard s.units[a].kind == .hero, s.units[a].hero?.items.isEmpty == false, s.units[t].team != s.units[a].team else { return }
        let effects = active(s.units[a], ctx.master)
        guard !effects.isEmpty else { return }
        let now = s.time
        let attackerID = s.units[a].id
        // 如意棒: クリティカルでない通常攻撃 2 回ごとに、次の通常攻撃の命中時効果が 2 回多く働く
        var triggers = 1
        if let v = effects.first(where: { $0.kind == .goldenStaff })?.v, v.count >= 4 {
            s.units[a].hero!.itemRuntime.attackCount += 1
            if s.units[a].hero!.itemRuntime.attackCount > Int(v[1]) {
                s.units[a].hero!.itemRuntime.attackCount = 0
                triggers += Int(v[3])
                s.units[a].statuses.removeAll { $0.tag == goldenStaffTag }
            } else if s.units[a].hero!.itemRuntime.attackCount == Int(v[1]) {
                // 次の通常攻撃は攻撃速度 +80%（命中で外す）
                CombatSystem.addStatus(&s, targetIndex: a, StatusEffect(kind: .attackSpeedBoost, duration: 2, magnitude: v[2],
                                                                        sourceID: attackerID, tag: goldenStaffTag))
            }
        }

        for (kind, v) in effects {
            guard CombatSystem.isLiving(s, a) else { return }
            let targetAlive = CombatSystem.isLiving(s, t)
            var rt = s.units[a].hero!.itemRuntime
            switch kind {
            case .maleficEnergy where v.count >= 3:
                CombatSystem.addStatus(&s, targetIndex: a, StatusEffect(kind: .speedBoost, duration: v[2], magnitude: v[1],
                                                                        sourceID: attackerID, tag: "item.maleficEnergy"))
            case .typhoon where v.count >= 6:
                if !rt.ready(.typhoon, at: now) {
                    // 通常攻撃 1 回で 0.2 秒縮む（前回の発動から最短 2 秒）
                    rt.setReady(.typhoon, at: max(rt.last(.typhoon) + v[2], rt.readyTime(.typhoon) - v[1]))
                    s.units[a].hero!.itemRuntime = rt
                    break
                }
                rt.setReady(.typhoon, at: now + v[0])
                rt.setLast(.typhoon, now)
                s.units[a].hero!.itemRuntime = rt
                let speed = s.units[a].stats.attackSpeed
                let k = Balance.Items.self
                var damage = min(k.typhoonMax, max(k.typhoonMin, k.typhoonPerAttackSpeed * speed + k.typhoonFlat))
                if isCrit { damage *= critMultiplier(s, attacker: a, target: t) }
                let center = s.units[t].pos
                var hit = 0
                for j in aoeTargets(s, team: s.units[a].team, center: center, radius: v[5]) where hit < Int(v[3]) {
                    hit += 1
                    let amount = s.units[j].kind == .minion ? damage * v[4] : damage
                    CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: j, amount: amount, type: .magic,
                                            source: .item, isCrit: isCrit, appliesOnHit: false)
                }
            case .divineJustice where v.count >= 5:
                guard targetAlive, skillWindowOpen(rt, .divineJustice, now: now, window: v[1]) else { break }
                rt.setReady(.divineJustice, at: now + v[2])
                rt.setLast(.divineJustice, now)
                s.units[a].hero!.itemRuntime = rt
                let attack = s.units[a].stats.attack
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t, amount: attack * v[0], type: .trueDamage,
                                        source: .item, isCrit: false, appliesOnHit: false)
                CombatSystem.heal(&s, ctx, sourceID: attackerID, targetIndex: a, amount: v[3] + attack * v[4])
            case .judgement where v.count >= 3:
                guard targetAlive, skillWindowOpen(rt, .judgement, now: now, window: v[1]) else { break }
                rt.setReady(.judgement, at: now + v[2])
                rt.setLast(.judgement, now)
                s.units[a].hero!.itemRuntime = rt
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t, amount: v[0], type: .trueDamage,
                                        source: .item, isCrit: false, appliesOnHit: false)
            case .crisis where v.count >= 6:
                guard targetAlive, skillWindowOpen(rt, .crisis, now: now, window: v[2]) else { break }
                rt.setReady(.crisis, at: now + v[3])
                rt.setLast(.crisis, now)
                s.units[a].hero!.itemRuntime = rt
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t,
                                        amount: v[0] + v[1] * s.units[a].stats.abilityPower, type: .trueDamage,
                                        source: .item, isCrit: false, appliesOnHit: false)
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .slow, duration: v[5], magnitude: v[4],
                                                                        sourceID: attackerID, tag: "item.crisis"))
            case .ambush where v.count >= 5:
                // 5 秒間ヒーローとのダメージのやり取りがない（update が構える）
                guard targetAlive, rt.until(.ambush) > now else { break }
                rt.setUntil(.ambush, 0)
                s.units[a].hero!.itemRuntime = rt
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t,
                                        amount: v[1] + v[2] * s.units[a].stats.attack, type: .physical,
                                        source: .item, isCrit: false, appliesOnHit: false)
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .slow, duration: v[4], magnitude: v[3],
                                                                        sourceID: attackerID, tag: "item.ambush"))
            case .doom where v.count >= 1:
                guard isCrit, targetAlive else { break }
                let raw = s.units[a].stats.attack * critMultiplier(s, attacker: a, target: t)
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t, amount: raw * v[0], type: .trueDamage,
                                        source: .item, isCrit: false, appliesOnHit: false)
            case .impulse where v.count >= 3:
                _ = rt.gainStack(.impulse, now: now, interval: 0, duration: v[1], cap: v[2])
                s.units[a].hero!.itemRuntime = rt
            case .thunderbolt where v.count >= 8:
                guard targetAlive, rt.ready(.thunderbolt, at: now) else { break }
                rt.setReady(.thunderbolt, at: now + v[0])
                s.units[a].hero!.itemRuntime = rt
                let scale = roleScale(s.units[a].hero?.role, halfFor: [.ranger, .arcanist, .assassin], scale: v[7])
                let st = s.units[a].stats, base = s.units[a].baseStats
                let damage = (v[1] + v[2] * max(0, st.armor - base.armor) + v[3] * max(0, st.magicResist - base.magicResist)) * scale
                var targets = [t]
                for j in aoeTargets(s, team: s.units[a].team, center: s.units[t].pos, radius: v[6]) where j != t { targets.append(j) }
                for j in targets where CombatSystem.isLiving(s, j) {
                    if s.units[j].kind == .hero {
                        s.units[a].hero!.itemRuntime.setStack(.thunderbolt, s.units[a].hero!.itemRuntime.stack(.thunderbolt) + scale)
                    }
                    CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: j, amount: damage, type: .trueDamage,
                                            source: .item, isCrit: false, appliesOnHit: false)
                    CombatSystem.addStatus(&s, targetIndex: j, StatusEffect(kind: .slow, duration: v[5], magnitude: v[4],
                                                                            sourceID: attackerID, tag: "item.thunderbolt"))
                }
            default:
                break
            }
        }
        // 命中時の効果（如意棒で複数回働く）
        for _ in 0..<triggers {
            applyOnHitEffects(&s, ctx, attacker: a, target: t, effects: effects)
        }
    }

    /// 命中時の効果（追加ダメージ・回復・減速の重ね）。如意棒の「無尽の打撃」で繰り返される。
    private static func applyOnHitEffects(_ s: inout SimState, _ ctx: SimContext, attacker a: Int, target t: Int,
                                          effects: [Active]) {
        let attackerID = s.units[a].id
        let level = Double(s.units[a].hero?.level ?? 1)
        for (kind, v) in effects {
            guard CombatSystem.isLiving(s, a), CombatSystem.isLiving(s, t) else { return }
            let minion = s.units[t].kind == .minion
            switch kind {
            case .corrosive where v.count >= 5:
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t, amount: v[0], type: .physical,
                                        source: .item, isCrit: false, appliesOnHit: false)
                let per = v[1] * ((s.units[a].hero?.isRanged ?? false) ? v[2] : 1)
                let cur = s.units[t].statuses.first { $0.kind == .slow && $0.tag == "item.corrosive" }?.magnitude ?? 0
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .slow, duration: v[3],
                                                                        magnitude: min(per * v[4], cur + per),
                                                                        sourceID: attackerID, tag: "item.corrosive"))
            case .engulf where v.count >= 2:
                var extra = max(0, s.units[t].hp) * v[0]
                if minion { extra = min(extra, v[1]) }
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t, amount: extra, type: .physical,
                                        source: .item, isCrit: false, appliesOnHit: false)
            case .devour where v.count >= 3:
                let heal = (v[0] + v[1] * level) * (minion ? v[2] : 1)
                CombatSystem.heal(&s, ctx, sourceID: attackerID, targetIndex: a, amount: heal)
            case .crossbow where v.count >= 1:
                let type: DamageType = adaptiveIsMagic(s.units[a], ctx.master) ? .magic : .physical
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t, amount: v[0], type: type,
                                        source: .item, isCrit: false, appliesOnHit: false)
            case .affliction where v.count >= 2:
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t,
                                        amount: v[0] + v[1] * s.units[a].stats.abilityPower, type: .magic,
                                        source: .item, isCrit: false, appliesOnHit: false)
            default:
                break
            }
        }
    }

    /// クリティカルの倍率（対象のクリティカルダメージ軽減で上乗せ分が減る。CombatSystem の通常攻撃と同じ式）。
    static func critMultiplier(_ s: SimState, attacker a: Int, target t: Int) -> Double {
        let cut = min(1, max(0, s.units[t].stats.critDamageReduction))
        return max(1, 1 + (s.units[a].stats.critMultiplier - 1) * (1 - cut))
    }

    /// スキル使用後の窓が開いていて、この窓でまだ使っておらず、CD も明けているか。
    private static func skillWindowOpen(_ rt: ItemRuntime, _ k: ItemEffectKind, now: Double, window: Double) -> Bool {
        now - rt.skillCastAt <= window + 1e-9 && rt.last(k) < rt.skillCastAt && rt.ready(k, at: now)
    }

    // MARK: - スキル

    /// スキルを使った時（スキル後の窓を開く。龍神の槍: 必殺技で加速）。
    static func onSkillCast(_ s: inout SimState, _ ctx: SimContext, caster c: Int, slot: SkillSlot) {
        guard s.units[c].kind == .hero, s.units[c].hero?.items.isEmpty == false else { return }
        let now = s.time
        s.units[c].hero!.itemRuntime.skillCastAt = now
        if slot == .ultimate, let v = values(.supremeWarrior, of: s.units[c], ctx.master), v.count >= 3,
           s.units[c].hero!.itemRuntime.ready(.supremeWarrior, at: now) {
            s.units[c].hero!.itemRuntime.setReady(.supremeWarrior, at: now + v[2])
            CombatSystem.addStatus(&s, targetIndex: c, StatusEffect(kind: .speedBoost, duration: v[1], magnitude: v[0],
                                                                    sourceID: s.units[c].id, tag: "item.supremeWarrior"))
        }
    }

    /// スキルが敵に命中した時（ダメージの後）。氷結の減速、共鳴の追加ダメージ。
    static func onSkillHit(_ s: inout SimState, _ ctx: SimContext, attacker a: Int, target t: Int) {
        guard s.units[a].kind == .hero, s.units[a].hero?.items.isEmpty == false,
              s.units[t].team != s.units[a].team, CombatSystem.isLiving(s, t) else { return }
        let now = s.time
        let attackerID = s.units[a].id
        for (kind, v) in active(s.units[a], ctx.master) {
            switch kind {
            case .iceBound where v.count >= 3:
                guard s.units[t].kind == .hero else { break }
                let cur = s.units[t].statuses.first { $0.kind == .slow && $0.tag == "item.iceBound" }?.magnitude ?? 0
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .slow, duration: v[1],
                                                                        magnitude: min(v[0] * v[2], cur + v[0]),
                                                                        sourceID: attackerID, tag: "item.iceBound"))
            case .resonate where v.count >= 3:
                var rt = s.units[a].hero!.itemRuntime
                if rt.ready(.resonate, at: now) {
                    rt.setReady(.resonate, at: now + v[0])
                    rt.setUntil(.resonate, now + Balance.Items.resonateWindow)
                } else if now > rt.until(.resonate) {
                    break
                }
                s.units[a].hero!.itemRuntime = rt
                CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t,
                                        amount: v[1] + v[2] * s.units[a].stats.abilityPower, type: .magic,
                                        source: .item, isCrit: false, appliesOnHit: false)
            default:
                break
            }
        }
    }

    // MARK: - ダメージを与えた・受けた

    /// ヒーローが敵にダメージを与えた後（装備の追加ダメージ・継続ダメージは除く）。
    static func onDamageDealt(_ s: inout SimState, _ ctx: SimContext, attacker a: Int, target t: Int, raw: Double,
                              dealt: Double, type: DamageType, source: DamageSource) {
        guard s.units[a].kind == .hero, s.units[t].team != s.units[a].team, dealt > 0 || raw > 0,
              source != .item, source != .dot, source != .fountain else { return }
        GearSystem.onDamageDealt(&s, ctx, attacker: a, target: t, source: source)
        guard s.units[a].hero?.items.isEmpty == false, CombatSystem.isLiving(s, a) else { return }
        let effects = active(s.units[a], ctx.master)
        guard !effects.isEmpty else { return }
        let now = s.time
        let attackerID = s.units[a].id
        let targetIsHero = s.units[t].kind == .hero
        let level = Double(s.units[a].hero?.level ?? 1)
        // 奇襲はヒーローとのダメージのやり取りで解ける（通常攻撃の命中は onBasicAttackLanded が消費する）
        if targetIsHero, source != .basicAttack { s.units[a].hero!.itemRuntime.setUntil(.ambush, 0) }
        if targetIsHero { s.units[a].hero!.itemRuntime.setLast(.ambush, now) }

        for (kind, v) in effects {
            guard CombatSystem.isLiving(s, a) else { return }
            switch kind {
            case .lifebane where v.count >= 2:
                guard CombatSystem.isLiving(s, t) else { break }
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .healReduction, duration: v[1], magnitude: v[0],
                                                                        sourceID: attackerID, tag: "item.lifebane"))
            case .scorch where v.count >= 2:
                guard type == .magic, CombatSystem.isLiving(s, t) else { break }
                let tid = s.units[t].id
                let slot = ItemEffectKind.scorch.slot
                var marks = s.units[a].hero!.itemRuntime.marks
                if let k = marks.firstIndex(where: { $0.kind == slot && $0.targetID == tid }) {
                    marks[k].until = now + v[0]
                } else {
                    marks.append(ItemMark(kind: slot, targetID: tid, until: now + v[0], nextTick: now + 1))
                }
                s.units[a].hero!.itemRuntime.marks = marks
            case .geniusShred where v.count >= 4:
                guard type == .magic, targetIsHero, CombatSystem.isLiving(s, t) else { break }
                let per = v[0] + v[1] * level
                let cur = s.units[t].statuses.first { $0.kind == .magicShred && $0.tag == "item.geniusShred" }?.magnitude ?? 0
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .magicShred, duration: v[3],
                                                                        magnitude: min(per * v[2], cur + per),
                                                                        sourceID: attackerID, tag: "item.geniusShred"))
            case .butterfly where v.count >= 3:
                guard type == .magic, targetIsHero else { break }
                var tally = s.units[a].hero!.itemRuntime.magicTally + raw
                var summons = 0
                while tally >= v[0] {
                    tally -= v[0]
                    summons += 1
                }
                s.units[a].hero!.itemRuntime.magicTally = tally
                for _ in 0..<summons where CombatSystem.isLiving(s, t) {
                    CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t,
                                            amount: max(v[2], s.units[t].hp * v[1]), type: .magic,
                                            source: .item, isCrit: false, appliesOnHit: false)
                }
            case .recharge where v.count >= 5:
                guard type == .magic else { break }
                var rt = s.units[a].hero!.itemRuntime
                if rt.gainStack(.recharge, now: now, interval: v[2], duration: v[4], cap: v[1]), rt.stack(.recharge) >= v[1] {
                    rt.setUntil(.recharge, now + v[4])
                }
                s.units[a].hero!.itemRuntime = rt
            case .destiny where v.count >= 5:
                guard type == .magic, targetIsHero else { break }
                _ = s.units[a].hero!.itemRuntime.gainStack(.destiny, now: now, interval: v[4], duration: v[2], cap: v[3])
            case .fightingSpirit where v.count >= 6:
                var rt = s.units[a].hero!.itemRuntime
                _ = rt.gainStack(.fightingSpirit, now: now, interval: v[5], duration: v[1], cap: v[2])
                let full = rt.liveStacks(.fightingSpirit, now: now, duration: v[1]) >= v[2]
                s.units[a].hero!.itemRuntime = rt
                if full, CombatSystem.isLiving(s, t) {
                    let scale = roleScale(s.units[a].hero?.role, halfFor: [.ranger, .arcanist, .support], scale: v[4])
                    CombatSystem.dealDamage(&s, ctx, sourceID: attackerID, targetIndex: t, amount: raw * v[3] * scale,
                                            type: .trueDamage, source: .item, isCrit: false, appliesOnHit: false)
                }
            case .bruteForce where v.count >= 6:
                _ = s.units[a].hero!.itemRuntime.gainStack(.bruteForce, now: now, interval: v[5], duration: v[2], cap: v[3])
            case .huntChase where v.count >= 4:
                guard targetIsHero || s.units[t].kind == .monster else { break }
                var rt = s.units[a].hero!.itemRuntime
                let tid = s.units[t].id
                rt.hitCount = rt.hitTargetID == tid ? rt.hitCount + 1 : 1
                rt.hitTargetID = tid
                if rt.hitCount >= Int(v[0]), rt.ready(.huntChase, at: now) {
                    rt.hitCount = 0
                    rt.setReady(.huntChase, at: now + v[3])
                    s.units[a].hero!.itemRuntime = rt
                    CombatSystem.addStatus(&s, targetIndex: a, StatusEffect(kind: .speedBoost, duration: v[2], magnitude: v[1],
                                                                            sourceID: attackerID, tag: "item.huntChase"))
                } else {
                    s.units[a].hero!.itemRuntime = rt
                }
            case .lethality where v.count >= 5:
                // 天空の刃: HP がしきい値未満の敵ヒーローを、シールドを無視して倒す
                guard targetIsHero, CombatSystem.isLiving(s, t) else { break }
                let threshold = v[0] + v[1] * s.units[a].hero!.itemRuntime.stack(.lethality)
                if s.units[t].hp > 0, s.units[t].hpRatio < threshold {
                    s.units[t].hp = 0
                    CombatSystem.commitDeath(&s, t, killerID: attackerID)
                    s.emit(.damage(DamageEvent(sourceID: attackerID, targetID: s.units[t].id, amount: 0, absorbed: 0,
                                               damageType: .trueDamage, source: .item, isCrit: false, pos: s.units[t].pos)))
                }
            default:
                break
            }
        }
    }

    /// ヒーローがダメージを受けた後。raw = 軽減前のダメージ。
    static func onDamageTaken(_ s: inout SimState, _ ctx: SimContext, victim t: Int, attacker a: Int?, dealt: Double,
                              raw: Double = 0, type: DamageType = .physical, source: DamageSource) {
        guard s.units[t].kind == .hero, dealt > 0, CombatSystem.isLiving(s, t) else { return }
        let hostile = a.map { s.units[$0].team != s.units[t].team } ?? false
        if hostile { GearSystem.onDamageTaken(&s, ctx, victim: t) }
        guard s.units[t].hero?.items.isEmpty == false else { return }
        let effects = active(s.units[t], ctx.master)
        guard !effects.isEmpty else { return }
        let now = s.time
        let victimID = s.units[t].id
        let level = Double(s.units[t].hero?.level ?? 1)
        let fromHero = a.map { s.units[$0].kind == .hero && hostile } ?? false
        s.units[t].hero!.itemRuntime.damagedAt = now
        if fromHero {
            s.units[t].hero!.itemRuntime.setUntil(.ambush, 0)
            s.units[t].hero!.itemRuntime.setLast(.ambush, now)
        }
        for (kind, v) in effects {
            guard CombatSystem.isLiving(s, t) else { return }
            var rt = s.units[t].hero!.itemRuntime
            switch kind {
            case .lifeline where v.count >= 6:
                guard s.units[t].hpRatio < v[0], rt.ready(.lifeline, at: now), v[5] == 0 || fromHero else { break }
                rt.setReady(.lifeline, at: now + v[4])
                s.units[t].hero!.itemRuntime = rt
                CombatSystem.addShield(&s, ctx, sourceID: victimID, targetIndex: t, amount: v[1] * level, duration: v[3],
                                       tag: "item.lifeline")
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .speedBoost, duration: v[3] / 2, magnitude: v[2],
                                                                        sourceID: victimID, tag: "item.lifeline"))
            case .valor where v.count >= 3:
                guard type == .physical, hostile else { break }
                _ = rt.gainStack(.valor, now: now, interval: 0, duration: v[1], cap: v[2])
                s.units[t].hero!.itemRuntime = rt
            case .holyBlessing where v.count >= 5:
                guard type == .magic, hostile else { break }
                _ = rt.gainStack(.holyBlessing, now: now, interval: v[4], duration: v[2], cap: v[3])
                s.units[t].hero!.itemRuntime = rt
            case .chastise where v.count >= 2:
                guard hostile, let a, CombatSystem.isLiving(s, a), !s.units[a].isStructure else { break }
                CombatSystem.addStatus(&s, targetIndex: a, StatusEffect(kind: .attackSpeedBoost, duration: v[1], magnitude: -v[0],
                                                                        sourceID: victimID, tag: "item.chastise"))
            case .redemption where v.count >= 4:
                guard s.units[t].hpRatio < v[0], rt.ready(.redemption, at: now) else { break }
                rt.setReady(.redemption, at: now + v[3])
                rt.regenHP = s.units[t].stats.maxHP * v[1] / max(0.1, v[2])
                rt.regenHPUntil = now + v[2]
                s.units[t].hero!.itemRuntime = rt
            case .deter where v.count >= 3:
                guard fromHero, source.isSkill, let a else { break }
                let cur = s.units[a].statuses.first { $0.kind == .damageDealtReduction && $0.tag == deterTag }?.magnitude ?? 0
                CombatSystem.addStatus(&s, targetIndex: a, StatusEffect(kind: .damageDealtReduction, duration: v[1],
                                                                        magnitude: min(v[0] * v[2], cur + v[0]),
                                                                        sourceID: victimID, tag: deterTag))
            case .defender where v.count >= 3:
                guard dealt > v[0] else { break }
                let pct = (v[1] + v[2] * s.units[t].stats.maxHP) / 100
                CombatSystem.heal(&s, ctx, sourceID: victimID, targetIndex: t, amount: (dealt - v[0]) * min(1, pct))
            case .bladedArmor where v.count >= 4:
                guard hostile, let a, source == .basicAttack, !s.units[a].isStructure, CombatSystem.isLiving(s, a) else { break }
                let pct = (v[0] + v[1] * max(0, s.units[t].stats.armor)) / 100
                CombatSystem.dealDamage(&s, ctx, sourceID: victimID, targetIndex: a, amount: max(raw, dealt) * pct,
                                        type: .physical, source: .passive, isCrit: false, appliesOnHit: false)
                if CombatSystem.isLiving(s, a) {
                    CombatSystem.addStatus(&s, targetIndex: a, StatusEffect(kind: .slow, duration: v[3], magnitude: v[2],
                                                                            sourceID: victimID, tag: "item.bladedArmor"))
                }
            case .demonize where v.count >= 5:
                guard fromHero, s.units[t].hpRatio < v[0], rt.ready(.demonize, at: now) else { break }
                rt.setReady(.demonize, at: now + v[4])
                s.units[t].hero!.itemRuntime = rt
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .damageReduction, duration: v[2], magnitude: v[1],
                                                                        sourceID: victimID, tag: "item.demonize"))
                reduceSkillCooldowns(&s, t, by: v[3])
            case .gift where v.count >= 4:
                tryGift(&s, t, v: v, now: now)
            default:
                break
            }
        }
    }

    /// 味方（自分以外のヒーロー）を回復・シールドした時（オアシスのフラスコ・恩恵）。CombatSystem から呼ばれる。
    static func onSupport(_ s: inout SimState, _ ctx: SimContext, source src: Int, target t: Int) {
        guard src != t, s.units[src].kind == .hero, s.units[t].kind == .hero, s.units[t].team == s.units[src].team else { return }
        GearSystem.onSupport(&s, ctx, source: src, target: t)
        guard let v = values(.oasisBlessing, of: s.units[src], ctx.master), v.count >= 5,
              CombatSystem.isLiving(s, t), s.units[t].hpRatio < v[0] else { return }
        let now = s.time
        let tid = s.units[t].id
        let slot = ItemEffectKind.oasisBlessing.slot
        var marks = s.units[src].hero!.itemRuntime.marks
        if let m = marks.first(where: { $0.kind == slot && $0.targetID == tid }), now < m.until { return }
        marks.removeAll { $0.kind == slot && $0.targetID == tid }
        marks.append(ItemMark(kind: slot, targetID: tid, until: now + v[4], nextTick: .greatestFiniteMagnitude))
        s.units[src].hero!.itemRuntime.marks = marks
        let level = Double(s.units[src].hero?.level ?? 1)
        CombatSystem.addShield(&s, ctx, sourceID: s.units[src].id, targetIndex: t, amount: v[1] * level, duration: v[2],
                               tag: "item.oasisBlessing")
        reduceSkillCooldowns(&s, src, by: v[3])
    }

    private static func reduceSkillCooldowns(_ s: inout SimState, _ i: Int, by sec: Double) {
        guard var cds = s.units[i].hero?.skillCooldowns else { return }
        for k in cds.indices { cds[k] = max(0, cds[k] - sec) }
        s.units[i].hero?.skillCooldowns = cds
    }

    /// 贈り物: HP・MP が半分を下回ったら 3 秒かけて回復（CD は共通）。
    private static func tryGift(_ s: inout SimState, _ t: Int, v: [Double], now: Double) {
        guard var rt = s.units[t].hero?.itemRuntime, rt.ready(.gift, at: now) else { return }
        let st = s.units[t].stats
        let lowHP = s.units[t].hpRatio < v[0]
        let lowMana = s.units[t].hero?.resourceKind == .mana && st.maxResource > 0 && s.units[t].resource / st.maxResource < v[0]
        guard lowHP || lowMana else { return }
        rt.setReady(.gift, at: now + v[3])
        if lowHP {
            rt.regenHP = st.maxHP * v[1] / max(0.1, v[2])
            rt.regenHPUntil = now + v[2]
        }
        if lowMana {
            rt.regenMana = st.maxResource * v[1] / max(0.1, v[2])
            rt.regenManaUntil = now + v[2]
        }
        s.units[t].hero?.itemRuntime = rt
    }

    // MARK: - キル・アシスト・死亡

    /// 敵ヒーローを倒した・アシストした時（刹那: 必殺技の CD 短縮）。
    static func onKillOrAssist(_ s: inout SimState, _ ctx: SimContext, hero i: Int) {
        guard s.units[i].kind == .hero, s.units[i].hero?.items.isEmpty == false else { return }
        if let v = values(.timestream, of: s.units[i], ctx.master), let r = v.first {
            let slot = SkillSlot.ultimate.rawValue
            if let cd = s.units[i].hero?.skillCooldowns[slot], cd > 0 { s.units[i].hero?.skillCooldowns[slot] = cd * (1 - r) }
        }
    }

    /// 敵ヒーローを倒した時（天空の刃: 致死のスタック）。
    static func onKill(_ s: inout SimState, _ ctx: SimContext, hero i: Int) {
        guard s.units[i].kind == .hero, s.units[i].hero?.items.isEmpty == false,
              let v = values(.lethality, of: s.units[i], ctx.master), v.count >= 5 else { return }
        let cur = s.units[i].hero!.itemRuntime.stack(.lethality)
        s.units[i].hero!.itemRuntime.setStack(.lethality, min(v[4], cur + v[2]))
    }

    /// 敵ミニオンを倒した時（デモンブーツ: MP 回復）。
    static func onMinionKill(_ s: inout SimState, _ ctx: SimContext, hero i: Int) {
        guard s.units[i].kind == .hero, s.units[i].hero?.resourceKind == .mana, CombatSystem.isLiving(s, i),
              let v = values(.mysticism, of: s.units[i], ctx.master), let r = v.first else { return }
        let st = s.units[i].stats
        s.units[i].resource = min(st.maxResource, s.units[i].resource + st.maxResource * r)
    }

    /// ヒーローが倒された時（DeathSystem が復活時間を決めた後）。イモータル: その場で 2.5 秒後に復活。天空の刃: スタック −30%。
    static func onHeroDeath(_ s: inout SimState, _ ctx: SimContext, hero v: Int) {
        guard s.units[v].kind == .hero, s.units[v].hero?.items.isEmpty == false else { return }
        let now = s.time
        if let x = values(.lethality, of: s.units[v], ctx.master), x.count >= 5 {
            let cur = s.units[v].hero!.itemRuntime.stack(.lethality)
            s.units[v].hero!.itemRuntime.setStack(.lethality, (cur * (1 - x[3])).rounded(.down))
        }
        if let x = values(.immortal, of: s.units[v], ctx.master), x.count >= 6,
           s.units[v].hero!.itemRuntime.ready(.immortal, at: now) {
            s.units[v].hero!.itemRuntime.setReady(.immortal, at: now + x[5])
            s.units[v].hero!.itemRuntime.revivePos = s.units[v].pos
            s.units[v].hero!.respawnTimer = min(s.units[v].hero!.respawnTimer, x[0])
        }
    }

    /// 復活の直前（RespawnSystem）。イモータルの復活ならその位置を返す。
    static func revivePosition(_ s: SimState, heroIndex i: Int) -> Vec2? {
        s.units[i].hero?.itemRuntime.revivePos
    }

    /// 復活の直後（全快の後）。イモータルの復活なら HP を 16% にしてシールドを張る。
    static func afterRespawn(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        guard s.units[i].hero?.itemRuntime.revivePos != nil else { return }
        s.units[i].hero!.itemRuntime.revivePos = nil
        guard let v = values(.immortal, of: s.units[i], ctx.master), v.count >= 6 else { return }
        let level = Double(s.units[i].hero?.level ?? 1)
        s.units[i].hp = max(1, s.units[i].stats.maxHP * v[1])
        CombatSystem.addShield(&s, ctx, sourceID: s.units[i].id, targetIndex: i, amount: v[2] + v[3] * level,
                               duration: v[4], tag: "item.immortal")
    }

    // MARK: - アクティブ

    /// 持っているアクティブ装備（HUD のボタン用。無ければ nil）。
    public static func activeInfo(_ h: HeroData, time now: Double, master: MasterData) -> ItemActiveInfo? {
        for id in h.items {
            guard let it = master.item(id) else { continue }
            for e in it.effects {
                guard let k = ItemEffectKind(rawValue: e.id), k.isActive, e.v.count >= 2 else { continue }
                return ItemActiveInfo(itemID: id, kind: k, remaining: max(0, h.itemRuntime.readyTime(k) - now), cooldown: e.v[1])
            }
        }
        return nil
    }

    /// アクティブ装備を使う（.useItemActive）。ウィンタークラウン: 2 秒間 凍結。ナチュラルウィンド: 物理無効。
    public static func useActive(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        guard let h = s.units[i].hero, CombatSystem.isLiving(s, i),
              let info = activeInfo(h, time: s.time, master: ctx.master), info.remaining <= 1e-9,
              let v = values(info.kind, of: s.units[i], ctx.master) else { return }
        let now = s.time
        let id = s.units[i].id
        s.units[i].hero!.itemRuntime.setReady(info.kind, at: now + info.cooldown)
        switch info.kind {
        case .frozen:
            let d = v[0]
            // 行動不能（suppress）は弱体なので、無敵より先に付ける
            for kind in [StatusKind.suppress, .invulnerable, .untargetable] {
                CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: kind, duration: d, sourceID: id, tag: "item.frozen"))
            }
        case .windChant where v.count >= 3:
            let d = v[0] * (h.role == .ranger ? 1 : v[2])
            s.units[i].hero!.itemRuntime.setUntil(.windChant, now + d)
        default:
            break
        }
    }

    // MARK: - 毎 tick

    static let guardWingsTag = "item.guardWings"
    /// 威嚇（上古の鎧・ドレッドノートメイル）: 攻撃者の物理ダメージだけを下げる与ダメ低下。
    static let deterTag = "item.deter"
    static let goldenStaffTag = "item.goldenStaff"

    /// 周りへの継続効果・シールドの張り直し・燃焼・継続回復・ポーションの期限・ボットのアクティブ。
    static func update(_ s: inout SimState, _ ctx: SimContext, hero i: Int) {
        guard let h = s.units[i].hero else { return }
        if h.itemRuntime.potionID != nil, s.time >= h.itemRuntime.potionUntil {
            s.units[i].hero!.itemRuntime.potionID = nil
            StatCalculator.recompute(&s, i, ctx)
        }
        guard !h.items.isEmpty, CombatSystem.isLiving(s, i) else { return }
        let effects = active(s.units[i], ctx.master)
        guard !effects.isEmpty else { return }
        let now = s.time
        let dt = Balance.dt
        let id = s.units[i].id
        let team = s.units[i].team
        let level = Double(h.level)
        let everySecond = s.tick % max(1, Int(Balance.tickRate.rounded())) == 0
        let everyHalf = s.tick % max(1, Int((Balance.tickRate / 2).rounded())) == 0

        for (kind, v) in effects {
            guard CombatSystem.isLiving(s, i) else { return }
            switch kind {
            case .burningSoul where v.count >= 4:
                guard everySecond else { break }
                let curse = values(.curse, of: s.units[i], ctx.master)
                for j in aoeTargets(s, team: team, center: s.units[i].pos, radius: v[3]) {
                    var dmg = v[0] * s.units[i].stats.maxHP
                    if s.units[j].kind == .minion || s.units[j].kind == .monster { dmg *= 1 + v[1] + v[2] * level }
                    CombatSystem.dealDamage(&s, ctx, sourceID: id, targetIndex: j, amount: dmg, type: .magic,
                                            source: .item, isCrit: false, appliesOnHit: false)
                    if let c = curse, c.count >= 3, CombatSystem.isLiving(s, j) {
                        let cur = s.units[j].statuses.first { $0.kind == .flatDefenseMod && $0.tag == "item.curse" }?.magnitude ?? 0
                        replaceStatus(&s, j, StatusEffect(kind: .flatDefenseMod, duration: c[1],
                                                          magnitude: max(-c[0] * c[2], cur - c[0]), sourceID: id, tag: "item.curse"))
                    }
                }
            case .lifebaneAura where v.count >= 2:
                guard everySecond else { break }
                for j in aoeTargets(s, team: team, center: s.units[i].pos, radius: v[0]) where s.units[j].kind == .hero {
                    CombatSystem.addStatus(&s, targetIndex: j, StatusEffect(kind: .healReduction, duration: 1.5, magnitude: v[1],
                                                                            sourceID: id, tag: "item.lifebaneAura"))
                }
            case .fortress where v.count >= 3:
                guard everyHalf else { break }
                let n = aoeTargets(s, team: team, center: s.units[i].pos, radius: v[2]).filter { s.units[$0].kind == .hero }.count
                s.units[i].hero!.itemRuntime.setStack(.fortress, Double(n))
            case .guardWings where v.count >= 6:
                let has = s.units[i].shields.contains { $0.tag == guardWingsTag }
                var rt = s.units[i].hero!.itemRuntime
                if has {
                    rt.setStack(.guardWings, 1)
                } else {
                    if rt.stack(.guardWings) > 0 {
                        // 割れた: 1 秒間 加速
                        rt.setStack(.guardWings, 0)
                        rt.setUntil(.guardWings, now + v[5])
                    }
                    if now - rt.damagedAt >= v[2] {
                        rt.setStack(.guardWings, 1)
                        s.units[i].hero!.itemRuntime = rt
                        CombatSystem.addShield(&s, ctx, sourceID: id, targetIndex: i,
                                               amount: v[0] + v[1] * s.units[i].stats.abilityPower,
                                               duration: 9_999, tag: guardWingsTag)
                        rt = s.units[i].hero!.itemRuntime
                    }
                }
                s.units[i].hero!.itemRuntime = rt
            case .manaSpring where v.count >= 1:
                guard s.units[i].hero?.resourceKind == .mana else { break }
                let mx = s.units[i].stats.maxResource
                s.units[i].resource = min(mx, s.units[i].resource + mx * v[0] * dt)
            case .recovery where v.count >= 2:
                guard now - s.units[i].lastCombatTime >= v[0] else { break }
                regenerate(&s, i, hp: s.units[i].stats.maxHP * v[1] * dt)
            case .gift where v.count >= 4:
                tryGift(&s, i, v: v, now: now)
            case .valkyrie where v.count >= 3:
                let rt = s.units[i].hero!.itemRuntime
                if !rt.ready(.valkyrie, at: now), now >= rt.until(.valkyrie), now - s.units[i].lastCombatTime >= v[2] {
                    s.units[i].hero!.itemRuntime.setReady(.valkyrie, at: now)
                }
            case .ambush where v.count >= 1:
                let rt = s.units[i].hero!.itemRuntime
                if rt.until(.ambush) <= now, now - rt.last(.ambush) >= v[0] {
                    s.units[i].hero!.itemRuntime.setUntil(.ambush, .greatestFiniteMagnitude)
                }
            case .frozen, .windChant:
                if h.controller == .bot { botUseActive(&s, ctx, heroIndex: i, kind: kind) }
            default:
                break
            }
        }
        tickMarks(&s, ctx, heroIndex: i)
        // 継続回復（贖罪・贈り物）
        let rt = s.units[i].hero!.itemRuntime
        if now < rt.regenHPUntil, rt.regenHP > 0 { regenerate(&s, i, hp: rt.regenHP * dt) }
        if now < rt.regenManaUntil, rt.regenMana > 0 {
            let mx = s.units[i].stats.maxResource
            s.units[i].resource = min(mx, s.units[i].resource + rt.regenMana * dt)
        }
    }

    /// 焼灼の燃焼（1 秒ごとに最大 HP の 1% の魔法ダメージ）と、期限切れの印の掃除。
    private static func tickMarks(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        guard let marks = s.units[i].hero?.itemRuntime.marks, !marks.isEmpty else { return }
        let now = s.time
        let scorch = ItemEffectKind.scorch.slot
        let v = values(.scorch, of: s.units[i], ctx.master)
        var keep: [ItemMark] = []
        var hits: [EntityID] = []
        for var m in marks {
            if m.kind == scorch {
                guard now <= m.until + 1e-9, v != nil else { continue }
                if now + 1e-9 >= m.nextTick {
                    m.nextTick += 1
                    hits.append(m.targetID)
                }
            } else if now >= m.until {
                continue
            }
            keep.append(m)
        }
        s.units[i].hero!.itemRuntime.marks = keep
        guard let v, v.count >= 2 else { return }
        for tid in hits {
            guard let t = s.index(of: tid), CombatSystem.isLiving(s, t) else { continue }
            CombatSystem.dealDamage(&s, ctx, sourceID: s.units[i].id, targetIndex: t, amount: s.units[t].stats.maxHP * v[1],
                                    type: .magic, source: .item, isCrit: false, appliesOnHit: false)
        }
    }

    /// ボットのアクティブ装備: 敵ヒーローに攻められて HP が減ったら使う。
    private static func botUseActive(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, kind: ItemEffectKind) {
        guard s.units[i].hpRatio < Balance.Items.botActiveHPRatio, s.time - s.units[i].lastDamagedTime < 0.5,
              let last = s.index(of: s.units[i].lastAttackerID), s.units[last].kind == .hero,
              s.units[last].team != s.units[i].team else { return }
        // ナチュラルウィンドは物理で攻めてくる相手にだけ
        if kind == .windChant, adaptiveIsMagic(s.units[last], ctx.master) { return }
        useActive(&s, ctx, heroIndex: i)
    }

    /// 継続回復（自然回復と同じく毎 tick 直接足す。回復のイベントは出さない。回復阻害は受ける）。
    static func regenerate(_ s: inout SimState, _ i: Int, hp amount: Double) {
        guard amount > 0, CombatSystem.isLiving(s, i) else { return }
        let st = s.units[i].stats
        s.units[i].hp = min(st.maxHP, s.units[i].hp + amount * max(0, st.healingReceivedMultiplier))
    }

    /// 同じ kind + tag の状態を置き換える（負の値を重ねる時は addStatus の「大きい方」では重ならないため）。
    private static func replaceStatus(_ s: inout SimState, _ t: Int, _ e: StatusEffect) {
        s.units[t].statuses.removeAll { $0.kind == e.kind && $0.tag == e.tag }
        CombatSystem.addStatus(&s, targetIndex: t, e)
    }

    /// center の周囲 radius にいる、team から見た敵（ヒーロー・ミニオン・モンスター。構造物は除く）。
    static func aoeTargets(_ s: SimState, team: Team, center: Vec2, radius: Double) -> [Int] {
        var out: [Int] = []
        let r2 = radius * radius
        for j in s.units.indices where CombatSystem.isLiving(s, j) {
            let u = s.units[j]
            guard u.team != team, u.kind == .hero || u.kind == .minion || u.kind == .monster,
                  !u.has(.invulnerable), u.pos.distanceSquared(to: center) <= r2 else { continue }
            out.append(j)
        }
        return out
    }
}
