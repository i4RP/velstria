import Foundation

// 担当: core-economy
// 靴に付ける祝福（Mobile Legends の「装備の祝福」をそのまま写したもの。2026-10 の総入れ替え、パッチ 2.2.16）。
//   ・祝福は 0 Gold。持っている 1 足の靴に付く（装備枠を使わない）。靴が無ければスピードブーツ（250）を一緒に買う。
//     靴を合成しても祝福は残り、靴を売ると外れる。
//   ・ジャングル（炎撃・氷刺・血刃の狩猟）: 狩猟印が必要（狩猟印を持つと靴は必ずジャングルの祝福になる）。
//     モンスターに与えたダメージの後に確定ダメージ（狩人）。モンスター・キル・アシストの合計 5 で狩猟印がヒーローにも使え、
//     祝福の効果（奪取）が付く。合計 15 で物理攻撃・魔法攻撃 +10、最大 HP +100。
//   ・ローム（激励・恩恵・致命傷・隠蔽）: 狩猟印があると付けられない。2:00 を過ぎると新たには付けられない。
//     5 秒ごとの共栄（Gold・EXP）、近くの味方の稼ぎの 30%（無私）、敵ヒーローへのダメージで報酬（15 秒に 1 回）。
//     ローム持ちが複数いれば、所持 Gold が最も少ない 1 人だけが収入を得る。共栄・無私で得た Gold（共栄ゴールド）が
//     1000 に達すると祝福の能力が解放される。
// 数値は Balance.Gear。出典は MLBB の日本語クライアントの祝福の説明とパッチノート（2.1.18〜2.1.88）。

// MARK: - 祝福

/// 靴に付ける祝福。`.setGearOption` で付ける・付け替える（rawValue はリプレイに残るので変えない）。
public enum GearOption: String, Codable, Hashable, Sendable, CaseIterable {
    // ジャングル
    case flame
    case ice
    case bloody
    // ローム
    case conceal
    case encourage
    case favor
    case direHit

    public var category: ItemCategory {
        switch self {
        case .flame, .ice, .bloody: return .jungle
        case .conceal, .encourage, .favor, .direHit: return .roam
        }
    }

    public static func options(for category: ItemCategory) -> [GearOption] {
        allCases.filter { $0.category == category }
    }

    /// 自動で付ける時の既定（ジャングル = 炎撃、ローム = 役割別）。
    public static func defaultOption(for category: ItemCategory, role: Role) -> GearOption? {
        switch category {
        case .jungle: return .flame
        case .roam:
            switch role {
            case .vanguard: return .encourage
            case .support: return .favor
            default: return .encourage
            }
        default: return nil
        }
    }
}

/// ヒーローごとの祝福の状態（祝福を付けるまで nil）。
public struct GearState: Codable, Hashable, Sendable {
    public var option: GearOption?
    /// 共栄ゴールド（ローム: 共栄・無私で得た累計 Gold）。
    public var roamGold: Double = 0
    /// 無私で得た累計 Gold（上限 Balance.Gear.devotionGoldCap）。
    public var devotionGold: Double = 0
    /// 祝福の能力（恩恵・隠蔽）が次に使える時刻。
    public var abilityReadyAt: Double = 0
    /// 敵ヒーローへのダメージで報酬が次に入る時刻（無私）。
    public var devotionHitReadyAt: Double = 0
    /// 致命傷のフォース（移動で溜まる）。
    public var force: Double = 0
    /// 血刃の狩猟: 回復が続く間の毎秒の回復量と終わり。
    public var drainPerSecond: Double = 0
    public var drainUntil: Double = 0

    public init(option: GearOption? = nil) {
        self.option = option
    }
}

// MARK: - 定数

extension Balance {
    public enum Gear {
        /// 祝福を付けるために一緒に買う靴（スピードブーツ）。
        public static let baseBootsID = "EQ408"

        // MARK: ジャングル
        /// この時刻（秒）までは、ジャングルの祝福を持つとミニオンの Gold/XP が減る（2:00 まで共有できない）。
        public static let jungleMinionPenaltyEnd: Double = 120
        public static let jungleMinionMultiplier: Double = 0.5
        /// 狩猟印の強化（ヒーローに使える）に必要な「モンスター + キル + アシスト」の合計。
        public static let jungleBlessingUnlockCount = 5
        /// 2 段目の強化（物理攻撃・魔法攻撃 +10、最大 HP +100）に必要な合計。
        public static let jungleSecondUnlockCount = 15
        public static let jungleSecondAttack: Double = 10
        public static let jungleSecondHP: Double = 100
        /// 狩人: モンスターにダメージを与えた後、3 秒かけて 40（+3×レベル）（+最大 HP の 1%）の確定ダメージ。射手以外は 2 倍。
        public static let hunterBase: Double = 40
        public static let hunterPerLevel: Double = 3
        public static let hunterMaxHPRatio: Double = 0.01
        public static let hunterDuration: Double = 3
        public static let hunterNonMarksmanMultiplier: Double = 2
        /// 強化した狩猟印をヒーローへ使った時の確定ダメージと奪取の時間。
        public static let smiteHeroDamage: Double = 100
        public static let smiteHeroEffectDuration: Double = 3
        /// 炎撃: 物理攻撃・魔法攻撃を 67.5 + 3.5×レベル 奪う（Lv1 71 〜 Lv15 120）。
        public static let flameStealBase: Double = 67.5
        public static let flameStealPerLevel: Double = 3.5
        /// 氷刺: 移動速度を 50 + 2×レベル 奪う（Lv1 52 〜 Lv15 80）。
        public static let iceStealBase: Double = 50
        public static let iceStealPerLevel: Double = 2
        /// 血刃: 300 + 自分の追加 HP の 24% を 3 秒かけて奪う。
        public static let bloodyStealBase: Double = 300
        public static let bloodyStealExtraHPRatio: Double = 0.24

        // MARK: ローム
        /// この時刻（秒）を過ぎるとロームの祝福を新たには付けられない。
        public static let roamPurchaseDeadline: Double = 120
        /// この時刻（秒）を境に共栄が増える。
        public static let roamPhaseEnd: Double = 480
        public static let thrivingInterval: Double = 5
        public static let thrivingGoldEarly: Double = 6
        public static let thrivingXPEarly: Double = 12
        public static let thrivingGoldLate: Double = 10
        public static let thrivingXPLate: Double = 20
        /// 無私: 近くの味方がミニオン・モンスターから得た Gold/XP の 30% を自分も得る（味方の取り分は減らない）。
        public static let devotionShare: Double = 0.30
        public static let devotionRadius: Double = 1400
        public static let devotionGoldCap: Double = 2000
        /// 無私: 敵ヒーローにダメージを与えると（15 秒に 1 回）30 + 2×レベル Gold、20 + 8×レベル EXP。
        public static let devotionHitCooldown: Double = 15
        public static let devotionHitGoldBase: Double = 30
        public static let devotionHitGoldPerLevel: Double = 2
        public static let devotionHitXPBase: Double = 20
        public static let devotionHitXPPerLevel: Double = 8
        /// 祝福の能力が解放される共栄ゴールド。
        public static let blessingUnlockGold: Double = 1000
        /// アシスト時の追加報酬（MLBB の現行のロームには無い）。
        public static let assistBonusGold: Double = 0
        public static let assistBonusXP: Double = 0

        public static func thrivingGold(at time: Double) -> Double {
            time < roamPhaseEnd ? thrivingGoldEarly : thrivingGoldLate
        }

        public static func thrivingXP(at time: Double) -> Double {
            time < roamPhaseEnd ? thrivingXPEarly : thrivingXPLate
        }

        // MARK: ローム祝福
        /// 激励: 自分と周りの味方ヒーローの混合防御 +20。
        public static let encourageRadius: Double = 700
        public static let encourageDefense: Double = 20
        /// 恩恵: 15 秒ごとに、味方への回復・シールドで、周り 5 マスの最も HP の低い味方（自分を含む）を 400 回復。
        public static let favorRadius: Double = 500
        public static let favorCooldown: Double = 15
        public static let favorHeal: Double = 400
        /// 致命傷: 移動 1 マスにつきフォース 1（最大 40、フォース 1 につき移動速度 +1）。20 以上で次の攻撃がフォース × 7.5 の確定ダメージ。
        public static let direHitDistancePerStack: Double = 100
        public static let direHitMaxStacks: Double = 40
        public static let direHitMinStacks: Double = 20
        public static let direHitSpeedPerStack: Double = 1
        public static let direHitDamagePerStack: Double = 7.5
        /// 隠蔽: 自分と周りの味方を 5 秒間 隠れさせ、移動速度 +40%（ダメージを与える・受けると解除。CD 60 秒）。
        public static let concealRadius: Double = 700
        public static let concealCooldown: Double = 60
        public static let concealDuration: Double = 5
        public static let concealSpeed: Double = 0.4
        /// ボットが隠蔽を使う距離（敵ヒーローがこの距離に入ったら、戦闘外で使う）。
        public static let concealBotTriggerRange: Double = 1600
    }
}

// MARK: - 効果の計算（状態を書き換えない）

public enum GearEffects {
    /// 靴を持っているか。
    public static func hasBoots(_ h: HeroData, master: MasterData) -> Bool {
        h.items.contains { master.item($0)?.isBoots == true }
    }

    /// 付いている祝福（靴が無ければ nil）。
    public static func option(of h: HeroData, master: MasterData) -> GearOption? {
        guard let o = h.gear?.option, hasBoots(h, master: master) else { return nil }
        return o
    }

    /// category（.jungle / .roam）の祝福を持っているか。
    public static func has(_ h: HeroData, _ category: ItemCategory, master: MasterData) -> Bool {
        option(of: h, master: master)?.category == category
    }

    /// category の祝福（持っていなければ nil）。
    public static func option(of h: HeroData, category: ItemCategory, master: MasterData) -> GearOption? {
        guard let o = option(of: h, master: master), o.category == category else { return nil }
        return o
    }

    /// ミニオンを倒した時の自分の Gold/XP 倍率（ジャングルの祝福は 2:00 まで半減）。
    public static func minionRewardMultiplier(_ h: HeroData, time: Double, master: MasterData) -> Double {
        if time < Balance.Gear.jungleMinionPenaltyEnd, has(h, .jungle, master: master) {
            return Balance.Gear.jungleMinionMultiplier
        }
        return 1
    }

    /// モンスターを倒した時の Gold/XP 倍率（今の MLBB のロームには自分の狩りの減額が無いので 1）。
    public static func monsterRewardMultiplier(_ h: HeroData, time: Double, master: MasterData) -> Double {
        1
    }

    /// ジャングルの祝福の進み（モンスター + キル + アシスト）。
    public static func jungleProgress(_ h: HeroData) -> Int {
        h.score.monsterKills + h.score.kills + h.score.assists
    }

    /// 狩猟印が強化済み（ヒーローに使える）か。
    public static func jungleBlessingActive(_ h: HeroData, master: MasterData) -> Bool {
        has(h, .jungle, master: master) && jungleProgress(h) >= Balance.Gear.jungleBlessingUnlockCount
    }

    /// 祝福によるモンスターへの追加ダメージ（2.1.88 で廃止。狩人の確定ダメージに置き換わった）。
    public static func monsterDamageBonus(_ h: HeroData, master: MasterData) -> Double {
        0
    }

    /// 祝福による能力値（StatCalculator が装備の後に足す）。ジャングル 2 段目・致命傷の移動速度・モンスター Gold 補正。
    public static func applyStats(_ h: HeroData, to stats: inout Stats, master: MasterData) {
        guard let o = option(of: h, master: master) else { return }
        switch o.category {
        case .jungle:
            stats.monsterGoldBonus += Balance.Economy.jungleMonsterGoldBonus
            if jungleProgress(h) >= Balance.Gear.jungleSecondUnlockCount {
                stats.attack += Balance.Gear.jungleSecondAttack
                stats.abilityPower += Balance.Gear.jungleSecondAttack
                stats.maxHP += Balance.Gear.jungleSecondHP
            }
        case .roam:
            if o == .direHit, roamBlessingUnlocked(h) {
                stats.moveSpeed += (h.gear?.force ?? 0) * Balance.Gear.direHitSpeedPerStack
            }
        default:
            break
        }
    }

    /// ロームの祝福の能力が解放済みか（共栄ゴールド 1000）。
    public static func roamBlessingUnlocked(_ h: HeroData) -> Bool {
        (h.gear?.roamGold ?? 0) >= Balance.Gear.blessingUnlockGold
    }

    /// 旧 API（段階 0〜1）。解放済みなら 1。
    public static func roamStage(roamGold: Double) -> Int {
        roamGold >= Balance.Gear.blessingUnlockGold ? 1 : 0
    }

    /// 収入を得るローム持ち（チームで所持 Gold が最も少ない 1 人。同じなら添字の小さい方）。
    public static func activeRoamer(_ s: SimState, team: Team, master: MasterData) -> Int? {
        var best: Int?
        for i in s.heroIndices(team: team) {
            guard let h = s.units[i].hero, has(h, .roam, master: master) else { continue }
            if let b = best, let bh = s.units[b].hero, bh.gold <= h.gold { continue }
            best = i
        }
        return best
    }

    /// 祝福を付けられるかの見積もり（HUD のショップ表示・実際の付与で共通）。cost = 一緒に買う靴の Gold（靴があれば 0）。
    public static func quote(_ h: HeroData, option: GearOption, time: Double, ctx: SimContext) -> PurchaseQuote {
        let hasSmite = h.spells.contains(Balance.Economy.smiteSpellID)
        let id = "gear:\(option.rawValue)"
        if option.category == .jungle && !hasSmite {
            return PurchaseQuote(itemID: id, cost: 0, consumedSlots: [], failure: .requiresSmite)
        }
        if option.category == .roam {
            if hasSmite { return PurchaseQuote(itemID: id, cost: 0, consumedSlots: [], failure: .blockedBySmite) }
            let current = h.gear?.option
            if time > Balance.Gear.roamPurchaseDeadline, current?.category != .roam || !hasBoots(h, master: ctx.master) {
                return PurchaseQuote(itemID: id, cost: 0, consumedSlots: [], failure: .roamClosed)
            }
        }
        if hasBoots(h, master: ctx.master) {
            return PurchaseQuote(itemID: id, cost: 0, consumedSlots: [], failure: nil)
        }
        // 靴が無ければスピードブーツを一緒に買う
        var q = ItemSystem.quote(h, itemID: Balance.Gear.baseBootsID, ctx: ctx)
        q.itemID = id
        return q
    }
}

// MARK: - 毎 tick の処理・コマンド

public enum GearSystem {
    /// 祝福を付ける・付け替える（.setGearOption）。靴が無ければスピードブーツを買ってから付ける。
    public static func setOption(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, option: GearOption) {
        guard let h = s.units[i].hero else { return }
        let q = GearEffects.quote(h, option: option, time: s.time, ctx: ctx)
        if let f = q.failure {
            s.emit(.purchaseFailed(heroID: s.units[i].id, itemID: q.itemID, reason: f.rawValue))
            return
        }
        if !GearEffects.hasBoots(h, master: ctx.master) {
            ItemSystem.buy(&s, ctx, heroIndex: i, itemID: Balance.Gear.baseBootsID)
            guard let after = s.units[i].hero, GearEffects.hasBoots(after, master: ctx.master) else { return }
        }
        var g = s.units[i].hero?.gear ?? GearState()
        if g.option?.category != option.category {
            // 種類が変わったら進み（フォース・回復）は持ち越さない。共栄ゴールドは残す
            g.force = 0
            g.drainUntil = 0
        }
        g.option = option
        s.units[i].hero?.gear = g
        StatCalculator.recompute(&s, i, ctx)
    }

    /// 所持品が変わった時（購入・売却）。靴を失ったら祝福を外す。靴を得た時は狩猟印持ちならジャングル、
    /// ボットのサポート（ローム枠）ならロームの祝福を自動で付ける（人が操作するヒーローはショップで選ぶ）。
    static func didChangeItems(_ h: inout HeroData, master: MasterData, time: Double = 0) {
        let boots = GearEffects.hasBoots(h, master: master)
        guard boots else {
            if h.gear?.option != nil { h.gear?.option = nil }
            return
        }
        guard h.gear?.option == nil else { return }
        let hasSmite = h.spells.contains(Balance.Economy.smiteSpellID)
        var option: GearOption?
        if hasSmite {
            option = GearOption.defaultOption(for: .jungle, role: h.role)
        } else if h.controller == .bot, h.position == .support, time <= Balance.Gear.roamPurchaseDeadline {
            option = GearOption.defaultOption(for: .roam, role: h.role)
        }
        guard let option else { return }
        var g = h.gear ?? GearState()
        g.option = option
        h.gear = g
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let interval = max(1, Int((Balance.Gear.thrivingInterval * Balance.tickRate).rounded()))
        let isIncomeTick = s.tick % interval == 0
        let isSecondTick = s.tick % max(1, Int(Balance.tickRate.rounded())) == 0
        if isIncomeTick {
            for team in [Team.blue, Team.red] {
                if let r = GearEffects.activeRoamer(s, team: team, master: ctx.master) { grantThriving(&s, ctx, heroIndex: r) }
            }
        }
        for i in s.units.indices where s.units[i].kind == .hero {
            guard let h = s.units[i].hero, let option = GearEffects.option(of: h, master: ctx.master) else { continue }
            guard s.units[i].isAlive, !h.isDead else { continue }
            switch option {
            case .bloody:
                drainTick(&s, ctx, heroIndex: i)
            case .direHit:
                accumulateForce(&s, ctx, heroIndex: i)
            case .encourage:
                if isSecondTick { applyEncourage(&s, ctx, heroIndex: i) }
            case .conceal:
                if isSecondTick, h.controller == .bot { botConceal(&s, ctx, heroIndex: i) }
            default:
                break
            }
        }
    }

    /// 共栄（5 秒ごと。8:00 から増加）。共栄ゴールドに数える。
    private static func grantThriving(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        let gold = Balance.Gear.thrivingGold(at: s.time)
        var g = s.units[i].hero?.gear ?? GearState()
        g.roamGold += gold
        s.units[i].hero?.gear = g
        EconomyRewards.grantGold(&s, heroIndex: i, amount: gold, visible: false)
        HeroGrowth.grantXP(&s, ctx, heroIndex: i, amount: Balance.Gear.thrivingXP(at: s.time))
    }

    /// 無私: 近くの味方（earner）がミニオン・モンスターから Gold/XP を得た時、収入を得るローム持ちが 30% を別に得る。
    /// DeathSystem（ラストヒットの Gold）と HeroGrowth.shareXP（XP）から呼ばれる。
    static func devotion(_ s: inout SimState, _ ctx: SimContext, earner k: Int, gold: Double, xp: Double) {
        guard gold > 0 || xp > 0, s.units[k].kind == .hero, s.units[k].team != .neutral,
              let r = GearEffects.activeRoamer(s, team: s.units[k].team, master: ctx.master), r != k,
              s.units[r].isAlive, s.units[r].hero?.isDead == false else { return }
        let radius = Balance.Gear.devotionRadius
        guard s.units[r].pos.distanceSquared(to: s.units[k].pos) <= radius * radius else { return }
        var g = s.units[r].hero?.gear ?? GearState()
        let room = max(0, Balance.Gear.devotionGoldCap - g.devotionGold)
        let goldShare = min(room, gold * Balance.Gear.devotionShare)
        if goldShare > 0 {
            g.devotionGold += goldShare
            g.roamGold += goldShare
            s.units[r].hero?.gear = g
            EconomyRewards.grantGold(&s, heroIndex: r, amount: goldShare, visible: false)
        }
        if xp > 0 { HeroGrowth.grantXP(&s, ctx, heroIndex: r, amount: xp * Balance.Gear.devotionShare) }
    }

    /// ロームの祝福を持つヒーローが敵ヒーローにダメージを与えた時（無私の報酬、致命傷の消費、隠蔽の解除）。
    /// ジャングルの祝福を持つヒーローがモンスターにダメージを与えた時（狩人）。ItemEffects.onDamageDealt から呼ばれる。
    static func onDamageDealt(_ s: inout SimState, _ ctx: SimContext, attacker a: Int, target t: Int, source: DamageSource) {
        guard let h = s.units[a].hero, let option = GearEffects.option(of: h, master: ctx.master) else { return }
        let k = Balance.Gear.self
        if option.category == .jungle {
            guard s.units[t].kind == .monster, source != .dot else { return }
            let level = Double(h.level)
            var total = k.hunterBase + k.hunterPerLevel * level + k.hunterMaxHPRatio * s.units[a].stats.maxHP
            if h.role != .ranger { total *= k.hunterNonMarksmanMultiplier }
            CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .burn, duration: k.hunterDuration,
                                                                    magnitude: total / k.hunterDuration,
                                                                    sourceID: s.units[a].id, tag: "gear_hunter"))
            return
        }
        guard s.units[t].kind == .hero else { return }
        endConceal(&s, heroIndex: a)
        var g = h.gear ?? GearState()
        // 無私: 敵ヒーローへのダメージ（収入を得るローム持ちだけ）
        if s.time >= g.devotionHitReadyAt, GearEffects.activeRoamer(s, team: s.units[a].team, master: ctx.master) == a {
            g.devotionHitReadyAt = s.time + k.devotionHitCooldown
            let level = Double(h.level)
            let gold = k.devotionHitGoldBase + k.devotionHitGoldPerLevel * level
            g.roamGold += gold
            s.units[a].hero?.gear = g
            EconomyRewards.grantGold(&s, heroIndex: a, amount: gold, visible: false)
            HeroGrowth.grantXP(&s, ctx, heroIndex: a, amount: k.devotionHitXPBase + k.devotionHitXPPerLevel * level)
            g = s.units[a].hero?.gear ?? g
        }
        // 致命傷: フォースが 20 以上なら全部使って確定ダメージ
        if option == .direHit, GearEffects.roamBlessingUnlocked(h), g.force >= k.direHitMinStacks, source != .item {
            let damage = g.force * k.direHitDamagePerStack
            g.force = 0
            s.units[a].hero?.gear = g
            StatCalculator.recompute(&s, a, ctx)
            CombatSystem.applyDamage(&s, ctx, sourceID: s.units[a].id, targetIndex: t, amount: damage,
                                     type: .trueDamage, source: .item)
        }
    }

    /// 祝福を持つヒーローがダメージを受けた時（隠蔽の解除）。
    static func onDamageTaken(_ s: inout SimState, _ ctx: SimContext, victim t: Int) {
        endConceal(&s, heroIndex: t)
    }

    /// 恩恵: 味方（自分以外）を回復・シールドした時、周りで最も HP の低い味方（自分を含む）を 400 回復（15 秒に 1 回）。
    static func onSupport(_ s: inout SimState, _ ctx: SimContext, source src: Int, target t: Int) {
        guard src != t, s.units[src].kind == .hero, let h = s.units[src].hero, s.units[t].team == s.units[src].team,
              s.units[t].kind == .hero, GearEffects.option(of: h, category: .roam, master: ctx.master) == .favor,
              GearEffects.roamBlessingUnlocked(h), s.time >= (h.gear?.abilityReadyAt ?? 0) else { return }
        let k = Balance.Gear.self
        s.units[src].hero?.gear?.abilityReadyAt = s.time + k.favorCooldown
        let r2 = k.favorRadius * k.favorRadius
        var best: Int?
        var bestRatio = Double.infinity
        for j in s.units.indices where isLivingAlly(s, j, team: s.units[src].team)
            && s.units[j].pos.distanceSquared(to: s.units[src].pos) <= r2 {
            let ratio = s.units[j].hp / max(1, s.units[j].stats.maxHP)
            if ratio < bestRatio {
                bestRatio = ratio
                best = j
            }
        }
        guard let best else { return }
        CombatSystem.heal(&s, ctx, sourceID: s.units[src].id, targetIndex: best, amount: k.favorHeal)
    }

    /// 隠蔽（.useGearActive）。自分と周りの味方を隠れさせて加速する。
    public static func useActive(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        guard let h = s.units[i].hero, GearEffects.option(of: h, category: .roam, master: ctx.master) == .conceal,
              GearEffects.roamBlessingUnlocked(h), s.time >= (h.gear?.abilityReadyAt ?? 0),
              CombatSystem.isLiving(s, i) else { return }
        let k = Balance.Gear.self
        s.units[i].hero?.gear?.abilityReadyAt = s.time + k.concealCooldown
        let r2 = k.concealRadius * k.concealRadius
        let casterID = s.units[i].id
        for j in s.units.indices where isLivingAlly(s, j, team: s.units[i].team)
            && s.units[j].pos.distanceSquared(to: s.units[i].pos) <= r2 {
            CombatSystem.addStatus(&s, targetIndex: j, StatusEffect(kind: .stealth, duration: k.concealDuration,
                                                                    sourceID: casterID, tag: concealTag))
            CombatSystem.addStatus(&s, targetIndex: j, StatusEffect(kind: .speedBoost, duration: k.concealDuration,
                                                                    magnitude: k.concealSpeed, sourceID: casterID, tag: concealTag))
        }
    }

    /// 隠蔽の能力の残りクールダウン（HUD 用。使えない祝福なら nil）。
    public static func activeCooldown(_ h: HeroData, time: Double, master: MasterData) -> Double? {
        guard GearEffects.option(of: h, category: .roam, master: master) == .conceal, GearEffects.roamBlessingUnlocked(h)
        else { return nil }
        return max(0, (h.gear?.abilityReadyAt ?? 0) - time)
    }

    static let concealTag = "gear_conceal"

    private static func endConceal(_ s: inout SimState, heroIndex i: Int) {
        if s.units[i].statuses.contains(where: { $0.tag == concealTag }) {
            s.units[i].statuses.removeAll { $0.tag == concealTag }
        }
    }

    /// ボットの隠蔽: 戦闘外で敵ヒーローが近づいたら使う。
    private static func botConceal(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        guard let h = s.units[i].hero, GearEffects.roamBlessingUnlocked(h), s.time >= (h.gear?.abilityReadyAt ?? 0),
              !EconomySystem.isInCombat(s, unitIndex: i) else { return }
        let range2 = Balance.Gear.concealBotTriggerRange * Balance.Gear.concealBotTriggerRange
        let pos = s.units[i].pos
        let team = s.units[i].team
        let enemyNear = s.units.indices.contains { j in
            s.units[j].kind == .hero && s.units[j].team == team.opponent && s.units[j].isAlive
                && s.units[j].pos.distanceSquared(to: pos) <= range2
        }
        if enemyNear { useActive(&s, ctx, heroIndex: i) }
    }

    /// 激励: 自分と周りの味方ヒーローの混合防御 +20（1 秒ごとに付け直す）。
    private static func applyEncourage(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        guard let h = s.units[i].hero, GearEffects.roamBlessingUnlocked(h) else { return }
        let k = Balance.Gear.self
        let r2 = k.encourageRadius * k.encourageRadius
        let casterID = s.units[i].id
        for j in s.units.indices where isLivingAlly(s, j, team: s.units[i].team)
            && s.units[j].pos.distanceSquared(to: s.units[i].pos) <= r2 {
            CombatSystem.addStatus(&s, targetIndex: j, StatusEffect(kind: .flatDefenseMod, duration: 1.5,
                                                                    magnitude: k.encourageDefense, sourceID: casterID,
                                                                    tag: "gear_encourage"))
        }
    }

    /// 致命傷: 動いた距離でフォースを溜める（最大 40）。
    private static func accumulateForce(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        guard let h = s.units[i].hero, GearEffects.roamBlessingUnlocked(h) else { return }
        let k = Balance.Gear.self
        let moved = s.units[i].pos.distance(to: s.units[i].prevPos)
        guard moved > 0.01, moved < 400 else { return }
        var g = h.gear ?? GearState()
        let before = g.force
        g.force = min(k.direHitMaxStacks, g.force + moved / k.direHitDistancePerStack)
        s.units[i].hero?.gear = g
        if floor(before) != floor(g.force) { StatCalculator.recompute(&s, i, ctx) }
    }

    /// 血刃の狩猟: 奪った HP を 3 秒かけて回復する。
    private static func drainTick(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        guard let g = s.units[i].hero?.gear, s.time < g.drainUntil, g.drainPerSecond > 0 else { return }
        ItemEffects.regenerate(&s, i, hp: g.drainPerSecond * Balance.dt)
    }

    private static func isLivingAlly(_ s: SimState, _ j: Int, team: Team) -> Bool {
        s.units[j].kind == .hero && s.units[j].team == team && s.units[j].isAlive && s.units[j].hero?.isDead == false
    }

    /// 強化した狩猟印をヒーローへ使った時の効果（SpellSystem から呼ばれる）。100 の確定ダメージと、祝福ごとの奪取。
    static func applySmiteOnHero(_ s: inout SimState, _ ctx: SimContext, caster i: Int, target u: Int) {
        guard let h = s.units[i].hero else { return }
        let k = Balance.Gear.self
        let casterID = s.units[i].id
        let tag = "gear_smite"
        let level = Double(h.level)
        let d = k.smiteHeroEffectDuration
        CombatSystem.applyDamage(&s, ctx, sourceID: casterID, targetIndex: u,
                                 amount: k.smiteHeroDamage, type: .trueDamage, source: .spell)
        guard CombatSystem.isLiving(s, u) else { return }
        switch GearEffects.option(of: h, category: .jungle, master: ctx.master) ?? .flame {
        case .ice:
            let steal = k.iceStealBase + k.iceStealPerLevel * level
            CombatSystem.addStatus(&s, targetIndex: u, StatusEffect(kind: .flatMoveSpeedMod, duration: d, magnitude: -steal,
                                                                    sourceID: casterID, tag: tag))
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .flatMoveSpeedMod, duration: d, magnitude: steal,
                                                                    sourceID: casterID, tag: tag))
        case .bloody:
            let extraHP = max(0, s.units[i].stats.maxHP - s.units[i].baseStats.maxHP)
            let total = k.bloodyStealBase + k.bloodyStealExtraHPRatio * extraHP
            CombatSystem.addStatus(&s, targetIndex: u, StatusEffect(kind: .burn, duration: d, magnitude: total / d,
                                                                    sourceID: casterID, tag: tag))
            var g = s.units[i].hero?.gear ?? GearState()
            g.drainPerSecond = total / d
            g.drainUntil = s.time + d
            s.units[i].hero?.gear = g
        default:
            let steal = k.flameStealBase + k.flameStealPerLevel * level
            CombatSystem.addStatus(&s, targetIndex: u, StatusEffect(kind: .flatPowerMod, duration: d, magnitude: -steal,
                                                                    sourceID: casterID, tag: tag))
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .flatPowerMod, duration: d, magnitude: steal,
                                                                    sourceID: casterID, tag: tag))
        }
    }
}
