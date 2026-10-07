import Foundation

// 担当: core-economy
// ジャングル靴・ローム靴（Mobile Legends の「ジャングル装備」「ローム装備」に倣う、DESIGN §8.1）。
//   ジャングル靴: 狩猟印が必要。モンスターを狩りやすくなる代わりに 5:00 まではミニオンの Gold/XP が半減。
//                 モンスター・ミニオン・ヒーローの合計 5 回で「祝福」（オプションスキル）が解放される。
//   ローム靴:     狩猟印があると買えない。5 秒ごとにチーム共有の Gold/XP が入る（8:00 を境に 6G/12XP → 9G/18XP）。
//                 代わりに 8:00 までは自分のミニオン・モンスターの Gold/XP が半減。累計 Gold で祝福が段階的に強くなる。
// 数値の出典は公開攻略情報（公式パッチノートの一次資料ではない）。調整は Balance.Gear だけで行う。

// MARK: - オプションスキル

/// 靴に付けるオプションスキル（祝福）。購入時に役割に合わせて自動で選ばれ、`.setGearOption` で変更できる。
public enum GearOption: String, Codable, Hashable, Sendable, CaseIterable {
    // ジャングル靴
    case flame
    case ice
    case bloody
    // ローム靴
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

    /// 購入時の既定（ジャングル = 炎、ローム = 役割別）。
    public static func defaultOption(for category: ItemCategory, role: Role) -> GearOption? {
        switch category {
        case .jungle: return .flame
        case .roam:
            switch role {
            case .vanguard: return .conceal
            case .support: return .favor
            default: return .encourage
            }
        default: return nil
        }
    }
}

/// ヒーローごとの靴の状態（装備していなければ nil のまま）。
public struct GearState: Codable, Hashable, Sendable {
    public var option: GearOption?
    /// ローム靴の共有収入として受け取った累計 Gold（上限 Balance.Gear.roamGoldCap）。
    public var roamGold: Double = 0
    /// ローム祝福（癒し・必中・隠匿）が次に使える試合時間。
    public var abilityReadyAt: Double = 0

    public init(option: GearOption? = nil) {
        self.option = option
    }
}

// MARK: - 定数

extension Balance {
    public enum Gear {
        // MARK: ジャングル靴
        /// この時刻（秒）まではジャングル装備を持つとミニオンの Gold/XP が減る。
        public static let jungleMinionPenaltyEnd: Double = 300
        public static let jungleMinionMultiplier: Double = 0.5
        /// 祝福の解放に必要な「モンスター + ミニオン + キル + アシスト」の合計。
        public static let jungleBlessingUnlockCount = 5
        /// 祝福中のモンスターへの追加ダメージ（クリープに 150%）。
        public static let jungleBlessingMonsterDamage: Double = 0.5
        /// 祝福の狩猟印をヒーローへ使った時の確定ダメージと効果時間。
        public static let smiteHeroDamage: Double = 100
        public static let smiteHeroEffectDuration: Double = 4
        public static let flameWeaken: Double = 0.15
        public static let flameSelfBoost: Double = 0.15
        public static let iceSlow: Double = 0.3
        public static let iceSelfSpeed: Double = 0.3
        public static let bloodyHealPct: Double = 0.10

        // MARK: ローム靴
        /// この時刻（秒）を境に共有収入が増え、自分の狩りの収入制限が解ける。
        public static let roamPhaseEnd: Double = 480
        /// 制限中の自分のミニオン・モンスターの Gold/XP 倍率。
        public static let roamFarmMultiplier: Double = 0.5
        public static let thrivingInterval: Double = 5
        public static let thrivingGoldEarly: Double = 6
        public static let thrivingXPEarly: Double = 12
        public static let thrivingGoldLate: Double = 9
        public static let thrivingXPLate: Double = 18
        /// 共有収入の累計上限（Gold）。
        public static let roamGoldCap: Double = 2000
        /// アシスト時の追加報酬。
        public static let assistBonusGold: Double = 30
        public static let assistBonusXP: Double = 30

        public static func thrivingGold(at time: Double) -> Double {
            time < roamPhaseEnd ? thrivingGoldEarly : thrivingGoldLate
        }

        public static func thrivingXP(at time: Double) -> Double {
            time < roamPhaseEnd ? thrivingXPEarly : thrivingXPLate
        }

        // MARK: ローム祝福
        /// 共有収入の累計がこの値に達するごとに祝福が 1 段階強くなる。
        public static let blessingThresholds: [Double] = [250, 500, 1000]
        /// 段階（0〜3）ごとの効果倍率。0 = 未解放。
        public static let blessingScale: [Double] = [0, 0.5, 0.75, 1]
        public static let encourageRadius: Double = 900
        public static let encourageAttackSpeed: Double = 0.10
        public static let encourageDamage: Double = 0.06
        public static let favorRadius: Double = 1200
        public static let favorCooldown: Double = 15
        public static let favorTriggerRatio: Double = 0.6
        public static let favorBase: Double = 200
        public static let favorPerLevel: Double = 50
        public static let direHitRange: Double = 800
        public static let direHitCooldown: Double = 30
        public static let direHitTriggerRatio: Double = 0.30
        public static let direHitMinPct: Double = 0.05
        public static let direHitMaxPct: Double = 0.20
        public static let concealRange: Double = 2000
        public static let concealCooldown: Double = 30
        public static let concealDuration: Double = 5
        public static let concealSpeed: Double = 0.4
    }
}

// MARK: - 装備カタログ

/// 靴 2 種（正本マスターには無く、MasterData が読み込み時に加える）。
public enum GearCatalog {
    public static let jungleBootsID = "EQJ01"
    public static let roamBootsID = "EQR01"

    public static let items: [ItemDef] = [
        ItemDef(itemID: jungleBootsID, nameJa: "狩人の長靴", category: .jungle, tier: 2, priceGold: 600,
                attack: 0, abilityPower: 0, hp: 0, armor: 0, magicResist: 0, moveSpeed: 40,
                cooldownReductionPct: 0, passiveName: "狩猟の心得",
                passiveText: "ジャングルの補助効果 8%相当。5:00 までミニオンの Gold/XP が半減。5 回の狩りで祝福（炎・氷・血）が解放される。",
                buildFrom: []),
        ItemDef(itemID: roamBootsID, nameJa: "巡回者の長靴", category: .roam, tier: 2, priceGold: 600,
                attack: 0, abilityPower: 0, hp: 0, armor: 0, magicResist: 18, moveSpeed: 40,
                cooldownReductionPct: 0, passiveName: "共有収入",
                passiveText: "5 秒ごとにチーム共有の Gold と XP が入る（8:00 から増加）。8:00 まで自分のミニオン・モンスター収入は半減。",
                buildFrom: []),
    ]

    /// 英語の表示名・説明（master_en.json は正本マスターから生成されるため、靴はここで持つ）。
    public static let english: [String: String] = [
        jungleBootsID: "Hunter's Boots",
        "\(jungleBootsID).passive": "Hunter's Instinct",
        "\(jungleBootsID).desc": "Jungle gear. Needs the hunting spell. Minion Gold/XP is halved until 5:00; "
            + "a blessing (Flame, Ice or Bloody) unlocks after 5 kills, assists or camp clears.",
        roamBootsID: "Wayfarer's Boots",
        "\(roamBootsID).passive": "Shared Fortune",
        "\(roamBootsID).desc": "Roam gear. Shared team Gold and XP every 5s (more from 8:00). "
            + "Your own minion and monster income is halved until 8:00.",
    ]
}

// MARK: - 効果の計算（状態を書き換えない）

public enum GearEffects {
    public static func has(_ h: HeroData, _ category: ItemCategory, master: MasterData) -> Bool {
        h.items.contains { master.item($0)?.category == category }
    }

    /// 選んでいるオプション（装備に合わないものは既定へ）。装備が無ければ nil。
    public static func option(of h: HeroData, category: ItemCategory, master: MasterData) -> GearOption? {
        guard has(h, category, master: master) else { return nil }
        if let o = h.gear?.option, o.category == category { return o }
        return GearOption.defaultOption(for: category, role: h.role)
    }

    /// ミニオンを倒した時の自分の Gold/XP 倍率（ジャングル靴は 5:00 まで、ローム靴は 8:00 まで半減）。
    public static func minionRewardMultiplier(_ h: HeroData, time: Double, master: MasterData) -> Double {
        var m = 1.0
        if time < Balance.Gear.jungleMinionPenaltyEnd, has(h, .jungle, master: master) {
            m *= Balance.Gear.jungleMinionMultiplier
        }
        m *= monsterRewardMultiplier(h, time: time, master: master)
        return m
    }

    /// モンスターを倒した時の Gold/XP 倍率（ローム靴の 8:00 まで半減のみ）。
    public static func monsterRewardMultiplier(_ h: HeroData, time: Double, master: MasterData) -> Double {
        if time < Balance.Gear.roamPhaseEnd, has(h, .roam, master: master) {
            return Balance.Gear.roamFarmMultiplier
        }
        return 1
    }

    /// ジャングル靴の祝福が解放済みか（狩りとキルの合計が規定数以上）。
    public static func jungleBlessingActive(_ h: HeroData, master: MasterData) -> Bool {
        guard has(h, .jungle, master: master) else { return false }
        let progress = h.score.creepScore + h.score.kills + h.score.assists
        return progress >= Balance.Gear.jungleBlessingUnlockCount
    }

    /// 祝福によるモンスターへの追加ダメージ（StatCalculator が足す）。
    public static func monsterDamageBonus(_ h: HeroData, master: MasterData) -> Double {
        jungleBlessingActive(h, master: master) ? Balance.Gear.jungleBlessingMonsterDamage : 0
    }

    /// ローム祝福の段階（0 = 未解放 … 3）。
    public static func roamStage(roamGold: Double) -> Int {
        Balance.Gear.blessingThresholds.filter { roamGold >= $0 }.count
    }

    public static func roamBlessingScale(_ h: HeroData) -> Double {
        Balance.Gear.blessingScale[roamStage(roamGold: h.gear?.roamGold ?? 0)]
    }
}

// MARK: - 毎 tick の処理・コマンド

public enum GearSystem {
    /// オプションの変更。所持している靴のカテゴリに合うものだけ受け付ける。
    public static func setOption(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, option: GearOption) {
        guard let h = s.units[i].hero, GearEffects.has(h, option.category, master: ctx.master) else { return }
        var g = h.gear ?? GearState()
        g.option = option
        s.units[i].hero?.gear = g
    }

    /// 靴を買った時に、選択が無い・合わない場合だけ既定のオプションにする。
    static func assignDefaultOption(_ h: inout HeroData, itemCategory: ItemCategory) {
        guard itemCategory == .jungle || itemCategory == .roam else { return }
        var g = h.gear ?? GearState()
        if g.option?.category != itemCategory {
            g.option = GearOption.defaultOption(for: itemCategory, role: h.role)
        }
        h.gear = g
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let interval = max(1, Int((Balance.Gear.thrivingInterval * Balance.tickRate).rounded()))
        let isIncomeTick = s.tick % interval == 0
        let isSecondTick = s.tick % max(1, Int(Balance.tickRate.rounded())) == 0
        for i in s.units.indices where s.units[i].kind == .hero {
            guard let h = s.units[i].hero, GearEffects.has(h, .roam, master: ctx.master) else { continue }
            if isIncomeTick { grantThriving(&s, ctx, heroIndex: i) }
            guard isSecondTick, s.units[i].isAlive, !h.isDead else { continue }
            applyBlessing(&s, ctx, heroIndex: i)
        }
    }

    /// 共有収入（5 秒ごと。8:00 から増加、累計は上限まで）。
    private static func grantThriving(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        var g = s.units[i].hero?.gear ?? GearState()
        let room = max(0, Balance.Gear.roamGoldCap - g.roamGold)
        let gold = min(room, Balance.Gear.thrivingGold(at: s.time))
        guard gold > 0 else { return }
        g.roamGold += gold
        s.units[i].hero?.gear = g
        EconomyRewards.grantGold(&s, heroIndex: i, amount: gold, visible: false)
        HeroGrowth.grantXP(&s, ctx, heroIndex: i, amount: Balance.Gear.thrivingXP(at: s.time))
    }

    /// ローム祝福（1 秒ごとに判定）。段階 0 の間は何もしない。
    private static func applyBlessing(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        guard let h = s.units[i].hero,
              let option = GearEffects.option(of: h, category: .roam, master: ctx.master) else { return }
        let scale = GearEffects.roamBlessingScale(h)
        guard scale > 0 else { return }
        let k = Balance.Gear.self
        let team = s.units[i].team
        let pos = s.units[i].pos
        let casterID = s.units[i].id
        var g = h.gear ?? GearState()
        let ready = s.time >= g.abilityReadyAt

        switch option {
        case .encourage:
            let r2 = k.encourageRadius * k.encourageRadius
            for j in s.units.indices where isLivingAlly(s, j, team: team) && s.units[j].pos.distanceSquared(to: pos) <= r2 {
                CombatSystem.addStatus(&s, targetIndex: j, StatusEffect(
                    kind: .attackSpeedBoost, duration: 1.5, magnitude: k.encourageAttackSpeed * scale,
                    sourceID: casterID, tag: "gear_encourage"))
                CombatSystem.addStatus(&s, targetIndex: j, StatusEffect(
                    kind: .damageBoost, duration: 1.5, magnitude: k.encourageDamage * scale,
                    sourceID: casterID, tag: "gear_encourage"))
            }
        case .favor:
            guard ready else { return }
            let r2 = k.favorRadius * k.favorRadius
            var best: Int?
            var bestRatio = k.favorTriggerRatio
            for j in s.units.indices where isLivingAlly(s, j, team: team) && s.units[j].pos.distanceSquared(to: pos) <= r2 {
                let ratio = s.units[j].hp / max(1, s.units[j].stats.maxHP)
                if ratio < bestRatio {
                    bestRatio = ratio
                    best = j
                }
            }
            guard let target = best else { return }
            let amount = (k.favorBase + k.favorPerLevel * Double(h.level)) * scale
            CombatSystem.heal(&s, ctx, sourceID: casterID, targetIndex: target, amount: amount)
            g.abilityReadyAt = s.time + k.favorCooldown
            s.units[i].hero?.gear = g
        case .direHit:
            guard ready else { return }
            let range2 = k.direHitRange * k.direHitRange
            var best: Int?
            var bestRatio = k.direHitTriggerRatio
            for j in s.units.indices where s.units[j].kind == .hero && s.isTargetableEnemy(j, of: team)
                && s.units[j].pos.distanceSquared(to: pos) <= range2 {
                let ratio = s.units[j].hp / max(1, s.units[j].stats.maxHP)
                if ratio < bestRatio {
                    bestRatio = ratio
                    best = j
                }
            }
            guard let target = best else { return }
            let levelRatio = Double(max(0, h.level - 1)) / Double(max(1, Balance.maxLevel - 1))
            let pct = (k.direHitMinPct + (k.direHitMaxPct - k.direHitMinPct) * levelRatio) * scale
            CombatSystem.applyDamage(&s, ctx, sourceID: casterID, targetIndex: target,
                                     amount: s.units[target].stats.maxHP * pct, type: .magic, source: .item)
            g.abilityReadyAt = s.time + k.direHitCooldown
            s.units[i].hero?.gear = g
        case .conceal:
            // 戦闘外で敵ヒーローが近づいたら自動で隠れて加速する。
            guard ready, !EconomySystem.isInCombat(s, unitIndex: i) else { return }
            let range2 = k.concealRange * k.concealRange
            let enemyNear = s.units.indices.contains { j in
                s.units[j].kind == .hero && s.units[j].team == team.opponent && s.units[j].isAlive
                    && s.units[j].pos.distanceSquared(to: pos) <= range2
            }
            guard enemyNear else { return }
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(
                kind: .stealth, duration: k.concealDuration, sourceID: casterID, tag: "gear_conceal"))
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(
                kind: .speedBoost, duration: k.concealDuration, magnitude: k.concealSpeed * scale,
                sourceID: casterID, tag: "gear_conceal"))
            g.abilityReadyAt = s.time + k.concealCooldown
            s.units[i].hero?.gear = g
        case .flame, .ice, .bloody:
            return
        }
    }

    private static func isLivingAlly(_ s: SimState, _ j: Int, team: Team) -> Bool {
        s.units[j].kind == .hero && s.units[j].team == team && s.units[j].isAlive && s.units[j].hero?.isDead == false
    }

    /// 祝福した狩猟印をヒーローへ使った時の効果（SpellSystem から呼ばれる）。
    static func applySmiteOnHero(_ s: inout SimState, _ ctx: SimContext, caster i: Int, target u: Int) {
        guard let h = s.units[i].hero else { return }
        let k = Balance.Gear.self
        let casterID = s.units[i].id
        let tag = "gear_smite"
        CombatSystem.applyDamage(&s, ctx, sourceID: casterID, targetIndex: u,
                                 amount: k.smiteHeroDamage, type: .trueDamage, source: .spell)
        let d = k.smiteHeroEffectDuration
        switch GearEffects.option(of: h, category: .jungle, master: ctx.master) ?? .flame {
        case .ice:
            CombatSystem.addStatus(&s, targetIndex: u, StatusEffect(kind: .slow, duration: d, magnitude: k.iceSlow,
                                                                    sourceID: casterID, tag: tag))
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .speedBoost, duration: d,
                                                                    magnitude: k.iceSelfSpeed, sourceID: casterID, tag: tag))
        case .bloody:
            CombatSystem.heal(&s, ctx, sourceID: casterID, targetIndex: i, amount: s.units[i].stats.maxHP * k.bloodyHealPct)
        default:
            CombatSystem.addStatus(&s, targetIndex: u, StatusEffect(kind: .damageDealtReduction, duration: d,
                                                                    magnitude: k.flameWeaken, sourceID: casterID, tag: tag))
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .damageBoost, duration: d,
                                                                    magnitude: k.flameSelfBoost, sourceID: casterID, tag: tag))
        }
    }
}
