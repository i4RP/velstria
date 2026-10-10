import Foundation

// 担当: kit-H025（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Miya.md）
// H025 月弦のルミナ = MLBB ミヤの Velstria 版（レンジャー・遠隔 550・マナ）。調査: docs/kits/Miya.md、対応表: 同ファイル末尾。
// 数値の正は Fandom の現行の表（docs/kits/Miya.md の「公式（Fandom 現行）の数値」）。
//   パッシブ 月環の導き  — 通常攻撃が命中するたびに攻撃速度 +5%（4 秒・最大 5 段）。最大のあいだは通常攻撃のたびに「月影」が
//                          30(+25% 物理攻撃) の形の物理ダメージを追って与える（換算 × shadowScale）。ロールの「4 発毎の確定会心」は置き換え。
//   スキル1 月弦分矢     — 自己強化 4 → 9 秒（ランクで伸びる）。通常攻撃が主矢 + 副矢 2 本になる（主矢 = 通常攻撃 + 基礎 10 → 35 の換算、
//                          周囲の敵 2 体へ主矢の 30%）。効果中は再使用できない（CD 11 秒）。
//   スキル2 月蝕の矢     — 指定地点（遅延あり）。半径内の敵に 270 → 420(+45%) の形の物理ダメージと 1.2 秒の移動不能。着弾点から 6 本の小さな矢が
//                          等間隔に散り、それぞれ最初に当たった敵に 40 → 105(+20%) の形の物理ダメージと 2 秒の 30% スロウ。
//   アルティメット 隠れ月光 — 弱体をすべて解除して姿を隠し、2 秒間 移動速度 +65%。通常攻撃かスキルの発動（奥義を除く）で解ける。
//                          解けた（時間切れ含む）瞬間に月環の導きが最大の段になる。ボットは低 HP で敵が近いとき、逃走・解除に使う。
// 数値の換算: 公式の表を Velstria のランク（スキル1・2 は 4 段、アルティメットは 3 段）へ線形補間し（ランク 1 = Lv1、最大ランク = 公式の最終 Lv）、
//   ダメージは sim の通常の式 (基礎 + 係数 × 攻撃力 × skillAttackScalingFactor) × スロット倍率 にスキルごとの換算（s1Scale ほか）を掛ける。
//   コスト（マナ）・クールダウン・S1 の持続も同じ補間（コストは HeroKit.cost）。
// 再使用の窓は Miya に無いので使わない。
//
// 状態（KitState）:
//   ints[0] = 月環の導きの段（0..5）        ints[1] = 隠れ月光の最中か（0/1）
//   ints[2] = 月影の発動回数（検証用）       ints[3] = 副矢を放った本数（検証用）
//   timers[0] = 段の残り秒（4）  timers[1] = 月矢の連弾の残り秒  timers[2] = 隠れ月光の残り秒
//   reals[0] = 月矢の連弾の主矢の追加ダメージ（発動時のランク・能力値で固定）

/// ルミナの調整値（docs/kits/Miya.md の数値を Velstria の単位・TTK に合わせたもの）。
enum LuminaTuning {
    // MARK: パッシブ（月環の導き）
    static let maxStacks = 5
    /// 1 段あたりの攻撃速度。MLBB のミヤと同じ 5%（最大 +25%）。CD が半分だったころは TTK が短く立ち上がりが遅いので 9% にしていたが、
    /// CD が MLBB の秒数になって 1v1 が長くなり（Lv1 の中央値 10 → 13.6 秒）、段が積み上がる Lv1 の勝率がレンジャー中央値 +28 pt（7% でも +20 pt、
    /// 全員との総当たり 83%）に偏ったので MLBB の値へ戻した。
    static let attackSpeedPerStack: Double = 0.05
    static let stackDuration: Double = 4
    /// 月影: 公式は 30(+25% 物理攻撃)。形（固定値と攻撃力の比）はそのまま、Velstria の火力の尺度へ shadowScale 倍する
    /// （ミヤは攻撃力 115 に対し約 0.5 倍の追撃。ルミナは × 2.2 で 66 + 攻撃力 55% = 攻撃力 138〜200 に対し約 1 倍。
    /// 以前の調整値 70 + 40% とほぼ同じ大きさ。2.0 / 2.2 / 2.5 を KitBalanceTests で比べて Lv1 がレンジャー中央値に近い 2.2）。
    static let shadowBase: Double = 30
    static let shadowAttackRatio: Double = 0.25
    static let shadowScale: Double = 2.2
    static let shadowFlat: Double = shadowBase * shadowScale
    static let shadowRatio: Double = shadowAttackRatio * shadowScale

    // MARK: S1（月矢の連弾）
    /// 持続（公式: 4 / 5 / 6 / 7 / 8 / 9 秒 → ランク 1〜4 へ補間 = 4 / 5.67 / 7.33 / 9 秒）。
    static let s1DurationTable = (4.0, 9.0)
    /// 主矢の追加ダメージの基礎（公式: 10 / 15 / 20 / 25 / 30 / 35。+100% 物理攻撃は通常攻撃そのもの）。
    /// 換算は スロット倍率（4.0）× s1Scale（1 本 72 → 252。持続も 4 → 9 秒に伸びるので、公式どおりランクでの伸びが大きい）。
    /// 1.0 / 1.5 / 1.8 / 2.0 / 2.5 / 3.0 を KitBalanceTests で比べ、Lv6・12 がレンジャー中央値に近い 1.8。
    static let s1Base = (10.0, 35.0)
    static let s1Scale: Double = 1.8
    static let splashRatio: Double = 0.30
    static let splashCount = 2
    static let splashRadius: Double = 300
    /// 副矢が飛ぶ範囲の余裕（術者の射程 + 対象の半径 + この値）。
    static let splashLeeway: Double = 150
    /// 自己強化の照準リングの半径 = 通常攻撃の射程（550）。「この範囲に敵が居れば撃つ」を HUD の輪で示す。
    /// ボットの奥義の関門（周囲の敵を数える半径 = 輪 × 1.4 = 770）もこれに従う。
    static let selfRing: Double = 550
    /// 「撃てる距離」の目安（`reachOverride`。敵がこの内側に居るときだけ撃つ）。
    static let s1Reach: Double = 600
    /// MLBB の CD 11 秒（全ランク固定）。
    static let s1Cooldown = (11.0, 11.0)
    /// 公式のマナ 50 / 55 / 60 / 65 / 70 / 75。
    static let s1Cost = (50.0, 75.0)

    // MARK: S2（月蝕の矢）
    static let s2Radius: Double = 170
    static let s2Delay: Double = 0.35
    static let s2Root: Double = 1.2
    static let s2Slow: Double = 0.30
    static let s2SlowDuration: Double = 2
    static let s2Arrows = 6
    /// 6 本を等間隔（60° おき）に散らす: 中心から ±30° / ±90° / ±150°。
    static let s2ScatterHalfAngle: Double = Double.pi * 5 / 6
    static let s2ArrowSpeed: Double = 1800
    static let s2ArrowRange: Double = 420
    static let s2ArrowWidth: Double = 35
    /// 着弾: 公式 270 / 300 / 330 / 360 / 390 / 420（+45% 物理攻撃）。
    static let s2Base = (270.0, 420.0)
    static let s2AttackRatio: Double = 0.45
    /// 小さな矢 1 本: 公式 40 / 53 / 66 / 79 / 92 / 105（+20% 物理攻撃）。
    static let s2MinorBase = (40.0, 105.0)
    static let s2MinorAttackRatio: Double = 0.20
    /// 着弾・小さな矢に共通の換算（スロット倍率 3.0 に掛ける）。0.39 で着弾がランク 1 の汎用 S2 の元の値の 0.66 倍（以前の比）、
    /// 0.30 / 0.34 / 0.39 を KitBalanceTests で比べ、Lv12 がレンジャー中央値に近い 0.34。
    static let s2Scale: Double = 0.34
    /// MLBB の CD 8 秒（全ランク固定）。以前はマスターの CD（8.7 秒からランクで 6% ずつ短縮）のままだった。
    static let s2Cooldown = (8.0, 8.0)
    /// 公式のマナ 80 / 90 / 100 / 110 / 120 / 130。
    static let s2Cost = (80.0, 130.0)

    // MARK: 奥義（隠れ月光）
    static let ultDuration: Double = 2
    static let ultSpeed: Double = 0.65
    /// 「撃てる距離」の目安（奥義の距離 770。`reachOverride`）。
    static let ultReach: Double = 770
    static let ultCooldown = (30.0, 20.0)
    /// 公式のマナ 120 / 145 / 170。
    static let ultCost = (120.0, 170.0)
    /// ボットが隠れ月光で離脱する HP の割合（通常 / 減速・移動不能を受けているとき）。
    static let escapeHP: Double = 0.45
    static let escapeHPHobbled: Double = 0.70

    // MARK: タグ・コード
    static let stackTag = KitTags.buff("H025", "moonBlessing")
    static let hiddenTag = KitTags.buff("H025", "hidden")
    static let hiddenSpeedTag = KitTags.buff("H025", "hiddenSpeed")
    static let rootTag = KitTags.buff("H025", "eclipseRoot")
    static let slowTag = KitTags.buff("H025", "eclipseSlow")

    /// KitTimer.code
    enum Code {
        static let split = 1
    }
}

extension KitState {
    /// 月環の導きの段（0..5）。
    var luminaStacks: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    /// 隠れ月光の最中か。
    var luminaHidden: Bool {
        get { ints[1] != 0 }
        set { ints[1] = newValue ? 1 : 0 }
    }

    /// 月影が発動した回数（検証用）。
    var luminaShadows: Int {
        get { ints[2] }
        set { ints[2] = newValue }
    }

    /// 副矢を放った本数（検証用）。
    var luminaSplashArrows: Int {
        get { ints[3] }
        set { ints[3] = newValue }
    }

    /// 段が切れるまでの残り秒。
    var luminaStackTimer: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    /// 月矢の連弾の残り秒。
    var luminaMoonArrow: Double {
        get { timers[1] }
        set { timers[1] = newValue }
    }

    /// 隠れ月光の残り秒。
    var luminaHiddenRemaining: Double {
        get { timers[2] }
        set { timers[2] = newValue }
    }

    /// 主矢の追加ダメージ（月矢の連弾を撃った時点の値）。
    var luminaArrowBonus: Double {
        get { reals[0] }
        set { reals[0] = newValue }
    }
}

struct Kit_H025: HeroKit {
    let heroID = "H025"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H025(isReady: true)` を HeroKits.testOverride に差すこともできる。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    typealias T = LuminaTuning

    // MARK: A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 自己強化（範囲・対象なし）。radius は照準リング・発動演出の大きさ、reach は「撃てる距離に敵が居る」の目安
            return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: T.selfRing, shape: .selfRing,
                                  reachOverride: T.s1Reach)
        case .skill2:
            // 指定地点の円（着弾まで遅延）
            return SkillTargeting(archetype: .groundAoE, aim: .point, range: skill.range, radius: T.s2Radius,
                                  shape: .circleAtPoint)
        case .ultimate:
            // 自己強化（隠密 + 加速）。reach は奥義の距離 770（ボットが交戦中とみなす目安）
            return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: T.selfRing, shape: .selfRing,
                                  reachOverride: T.ultReach)
        case .passive:
            return base
        }
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        var n = base
        switch slot {
        case .passive:
            n.damage = Self.shadowDamage(attack: stats.attack)
            n.hits = 1
            n.damageType = .physical
            n.extras = [KitStat(key: "attackSpeedPerStack", value: T.attackSpeedPerStack * 100),
                        KitStat(key: "stackDuration", value: T.stackDuration),
                        KitStat(key: "shadowFlat", value: T.shadowFlat),
                        KitStat(key: "shadowRatio", value: T.shadowRatio * 100),
                        KitStat(key: "maxSpeed", value: T.attackSpeedPerStack * Double(T.maxStacks) * 100)]
        case .skill1:
            // damage = 主矢 1 本あたりの追加ダメージ（通常攻撃に足す）。hits = 効果時間に基礎の攻撃速度で撃つ本数の目安
            let duration = Self.s1Duration(rank: rank)
            n.hits = max(1, Int((duration * max(0.1, stats.attackSpeed)).rounded()))
            n.damage = Self.arrowBonus(rank: rank)
            n.cooldown = Self.cooldown(T.s1Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .none
            n.ccDuration = 0
            n.extras = [KitStat(key: "duration", value: duration),
                        KitStat(key: "splashPercent", value: T.splashRatio * 100),
                        KitStat(key: "splashCount", value: Double(T.splashCount)),
                        KitStat(key: "splashRadius", value: T.splashRadius),
                        KitStat(key: "base", value: n.damage.rounded())]
        case .skill2:
            n.damage = Self.eclipseDamage(rank: rank, stats: stats)
            n.hits = 1
            n.delay = T.s2Delay
            n.cooldown = Self.cooldown(T.s2Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .root
            n.ccDuration = T.s2Root
            // 説明に出す値は整数にそろえる（実際の小さな矢のダメージは minorDamage(rank:stats:) が持つ）
            n.extras = [KitStat(key: "minorDamage", value: Self.minorDamage(rank: rank, stats: stats).rounded()),
                        KitStat(key: "root", value: T.s2Root),
                        KitStat(key: "slowPercent", value: T.s2Slow * 100),
                        KitStat(key: "slowDuration", value: T.s2SlowDuration),
                        KitStat(key: "base", value: Self.scaledBase(T.s2Base, rank: rank).rounded()),
                        KitStat(key: "atkPct", value: Self.attackPercent(T.s2AttackRatio).rounded()),
                        KitStat(key: "minorBase", value: Self.scaledBase(T.s2MinorBase, rank: rank).rounded()),
                        KitStat(key: "minorPct", value: Self.attackPercent(T.s2MinorAttackRatio).rounded())]
        case .ultimate:
            n.damage = 0
            n.hits = 1
            n.cc = .none
            n.ccIsUltimate = false
            n.ccDuration = 0
            n.cooldown = Self.cooldown(T.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.extras = [KitStat(key: "duration", value: T.ultDuration),
                        KitStat(key: "speedPercent", value: T.ultSpeed * 100),
                        KitStat(key: "stacks", value: Double(T.maxStacks))]
        }
        return n
    }

    /// ランクごとのマナ消費（公式: スキル1 = 50 → 75、スキル2 = 80 → 130、アルティメット = 120 / 145 / 170）。
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double {
        let table: (Double, Double)
        switch slot {
        case .skill1: table = T.s1Cost
        case .skill2: table = T.s2Cost
        case .ultimate: table = T.ultCost
        case .passive: return base
        }
        return HeroKits.resourceCost(Self.lerp(table.0, table.1, rank: rank, maxRank: slot.maxRank), hero: hero)
    }

    /// 説明文は公式（Fandom の説明文）の文の構造に合わせる。数値は {トークン} で sim から入れる
    /// （{base}(+{atkPct}%物理攻撃) は sim の式に換算した値）。
    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "通常攻撃が敵に命中するたびに、{stackDuration}秒間 攻撃速度が{attackSpeedPerStack}%上昇する。最大\(T.maxStacks)スタック（{maxSpeed}%）。\n\n"
                    + "最大スタックに達すると、通常攻撃のたびに「月影」を呼び出し、{shadowFlat}(+{shadowRatio}%物理攻撃)の物理ダメージを与える。",
                en: "Each time a basic attack hits a target, gain {attackSpeedPerStack}% attack speed for {stackDuration}s. "
                    + "Stacks up to \(T.maxStacks) times ({maxSpeed}%).\n\nAt full stacks, each basic attack summons a Moonlight "
                    + "Shadow that deals {shadowFlat} (+{shadowRatio}% Physical Attack) physical damage.",
                tags: [KitTag.buff])
        case .skill1:
            return KitText(
                ja: "通常攻撃のたびに追加の矢を2本放ち、対象の敵に{base}(+100%物理攻撃)の物理ダメージを与え、"
                    + "周囲（{splashRadius}以内）の敵{splashCount}体に{splashPercent}%のダメージを与える。この効果は{duration}秒間続く。\n\n"
                    + "クールダウンは発動した時点から数える。効果中は再使用できない。",
                en: "Each basic attack fires two extra arrows, dealing {base} (+100% Physical Attack) physical damage to the "
                    + "target and {splashPercent}% damage to {splashCount} nearby enemies (within {splashRadius}). Lasts "
                    + "{duration}s.\n\nThe cooldown starts on cast. Cannot be cast again until the effect ends.",
                tags: [KitTag.buff, KitTag.aoe])
        case .skill2:
            return KitText(
                ja: "指定範囲に強化された矢を放ち（着弾まで\(Self.seconds(T.s2Delay))秒）、範囲（半径{radius}）の敵に{base}(+{atkPct}%物理攻撃)の"
                    + "物理ダメージを与え、{root}秒間 移動不能にする（攻撃とスキルは使える）。\n\n"
                    + "その後、矢は\(T.s2Arrows)本の小さな矢に分かれて散り、それぞれ最初に命中した敵に{minorBase}(+{minorPct}%物理攻撃)の"
                    + "物理ダメージを与え、{slowDuration}秒間 移動速度を{slowPercent}%低下させる。",
                en: "Launches an empowered arrow at the target area (lands after \(Self.seconds(T.s2Delay))s), dealing {base} "
                    + "(+{atkPct}% Physical Attack) physical damage to enemies within (radius {radius}) and immobilizing them "
                    + "for {root}s (they can still attack and cast).\n\nThe arrow then splits into \(T.s2Arrows) scattering "
                    + "minor arrows, each dealing {minorBase} (+{minorPct}% Physical Attack) physical damage to the first enemy "
                    + "hit and slowing them by {slowPercent}% for {slowDuration}s.",
                tags: [KitTag.disrupt, KitTag.aoe])
        case .ultimate:
            return KitText(
                ja: "自身の弱体をすべて解除して姿を隠し、移動速度が{speedPercent}%上昇する。この状態は{duration}秒間、"
                    + "または攻撃（通常攻撃とアルティメット以外のスキル）を行うまで続く。\n\n状態を抜けると、月環の導きが最大スタック（{stacks}）になる。",
                en: "Removes all debuffs on you and conceals you, gaining {speedPercent}% extra movement speed. Lasts {duration}s "
                    + "or until you attack (basic attacks and non-Ultimate skills).\n\nOn leaving the state, gain full stacks "
                    + "({stacks}) of Moonring Guidance.",
                tags: [KitTag.buff, KitTag.mobility])
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            return KitBadge(kind: .stacks, value: min(T.maxStacks, k.luminaStacks), maxValue: T.maxStacks)
        case .skill1:
            guard k.luminaMoonArrow > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.luminaMoonArrow, total: Self.s1Duration(rank: hero.rank(.skill1)))
        case .ultimate:
            guard k.luminaHidden, k.luminaHiddenRemaining > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.luminaHiddenRemaining, total: T.ultDuration)
        case .skill2:
            return nil
        }
    }

    // MARK: B. 実行

    func resolveAim(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot, stage: Int,
                    targeting: SkillTargeting, target: SkillTarget) -> SkillAim?? {
        switch slot {
        case .skill1, .ultimate:
            // 自己強化: 敵が居なくても撃てる
            let facing = Vec2.fromAngle(s.units[caster].facing)
            return .some(SkillAim(direction: facing, point: s.units[caster].pos, unit: nil, distance: 0))
        default:
            return nil
        }
    }

    /// 月矢の連弾は効果中は撃ち直せない。
    func canStart(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) -> Bool {
        guard slot == .skill1 else { return true }
        return (s.units[caster].hero?.kit?.luminaMoonArrow ?? 0) <= 0
    }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        // 隠密中に撃った（SkillSystem.cast が隠密を外した後）なら、先に月環の導きを最大にする
        if c.slot != .ultimate { Self.settleHidden(&s, c.caster) }
        switch c.slot {
        case .skill1:
            castMoonArrow(&s, c)
        case .skill2:
            castEclipse(&s, c)
        case .ultimate:
            castHidden(&s, c)
        case .passive:
            break
        }
        return .done
    }

    /// S1: 通常攻撃を月矢の連弾にする自己強化。持続と主矢の追加ダメージは発動時のランクで固定する。
    private func castMoonArrow(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        let duration = Self.s1Duration(rank: c.numbers.rank)
        s.units[i].hero?.kit?.luminaMoonArrow = duration
        s.units[i].hero?.kit?.luminaArrowBonus = c.numbers.damage
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: s.units[i].pos, shape: .selfRing,
                     duration: duration, count: 1 + T.splashCount)
    }

    /// S2: 遅延のあとに範囲ダメージ + 移動不能（ゾーン）、同じ tick に 6 本の小さな矢が散る（タイマー）。
    private func castEclipse(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        let skill = c.check.skill
        let center = c.aim.point
        let root = StatusEffect(kind: .root, duration: T.s2Root, sourceID: s.units[i].id, tag: T.rootTag)
        let p = HitPayload(damage: c.numbers.damage, damageType: skill.damageType, source: .skill(.skill2),
                           statuses: [root], skillID: skill.skillID)
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: center, unit: c.aim.unit, shape: .circleAtPoint,
                     halfAngle: T.s2ScatterHalfAngle, duration: T.s2Delay, count: T.s2Arrows)
        ZoneSystem.spawn(&s, ownerIndex: i, center: center, radius: c.targeting.radius, delay: T.s2Delay, payload: p,
                         visual: skill.effectID)
        // 矢はもう放たれている: スタンしても散る（interruptible: false）。死亡すると状態ごと消える
        Kit.schedule(&s, caster: i, slot: .skill2, code: T.Code.split, after: T.s2Delay, param: c.aim.direction.angle,
                     point: center, interruptible: false)
    }

    /// 奥義: 弱体の解除 + 隠密 + 加速。解除（時間切れ・攻撃・発動）は settleHidden が拾う。
    private func castHidden(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        let id = s.units[i].id
        CombatSystem.cleanse(&s, targetIndex: i)
        s.units[i].statuses.removeAll { $0.kind == .armorShred || $0.kind == .magicShred }
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .stealth, duration: T.ultDuration, sourceID: id,
                                                                tag: T.hiddenTag))
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .speedBoost, duration: T.ultDuration,
                                                                magnitude: T.ultSpeed, sourceID: id, tag: T.hiddenSpeedTag))
        s.units[i].hero?.kit?.luminaHidden = true
        s.units[i].hero?.kit?.luminaHiddenRemaining = T.ultDuration
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: s.units[i].pos, shape: .selfRing, duration: T.ultDuration,
                     count: 1)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard timer.code == T.Code.split else { return }
        splitEclipse(&s, ctx, owner: owner, timer: timer)
    }

    /// 着弾した矢が 6 本に分かれ、着弾点から等間隔に散る。それぞれ最初に当たった敵だけに当たる（貫通しない）。
    private func splitEclipse(_ s: inout SimState, _ ctx: SimContext, owner i: Int, timer: KitTimer) {
        guard let (skill, n) = Self.numbersNow(s, ctx, i, .skill2) else { return }
        let damage = Self.minorDamage(rank: n.rank, stats: s.units[i].stats)
        let slow = StatusEffect(kind: .slow, duration: T.s2SlowDuration, magnitude: T.s2Slow, sourceID: s.units[i].id,
                                tag: T.slowTag)
        let p = HitPayload(damage: damage, damageType: skill.damageType, source: .skill(.skill2), statuses: [slow],
                           skillID: skill.skillID, originPos: timer.point)
        Kit.fan(&s, caster: i, direction: Vec2.fromAngle(timer.param), count: T.s2Arrows, halfAngle: T.s2ScatterHalfAngle,
                speed: T.s2ArrowSpeed, range: T.s2ArrowRange, width: T.s2ArrowWidth, payload: p, visual: skill.effectID,
                origin: timer.point)
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner i: Int) {
        // 隠れ月光が終わった（時間切れ・攻撃・発動）なら、その瞬間に月環の導きを最大に
        Self.settleHidden(&s, i)
        // 月環の導き: 4 秒の間に命中が無ければ全段が消える（攻撃速度のステータスが先に切れた場合も同じ）
        guard let k = s.units[i].hero?.kit, k.luminaStacks > 0 else { return }
        let hasBuff = s.units[i].statuses.contains { $0.kind == .attackSpeedBoost && $0.tag == T.stackTag }
        if k.luminaStackTimer <= 0 || !hasBuff { Self.clearStacks(&s, i) }
    }

    // MARK: C. パッシブ（月環の導き）

    func forceCrit(_ s: inout SimState, _ ctx: SimContext, attacker: Int) -> Bool? {
        // 通常攻撃の発射（SkillSystem.forceCrit が隠密を外した直後）。ロールの確定会心は置き換え = nil
        Self.settleHidden(&s, attacker)
        return nil
    }

    func shapeBasicAttack(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                          plan: inout BasicAttackPlan) {
        // 構造物には月矢・月影は働かない（攻城の火力は汎用のレンジャーのまま。攻撃速度の段は積む）
        guard !s.units[target].isStructure, let k = s.units[attacker].hero?.kit else { return }
        if k.luminaMoonArrow > 0 {
            plan.payload.damage += k.luminaArrowBonus
            Self.fireSplash(&s, attacker: attacker, primary: target, mainDamage: plan.payload.damage,
                            isCrit: plan.payload.isCrit)
        }
        if k.luminaStacks >= T.maxStacks {
            // 月影: 会心にならず、命中時効果（吸血・段の加算）も持たない追加ダメージ
            let attack = s.units[attacker].stats.attack
            plan.extras.append(HitPayload(damage: Self.shadowDamage(attack: attack), damageType: .physical,
                                          source: .basicAttack))
            s.units[attacker].hero?.kit?.luminaShadows += 1
        }
    }

    func onBasicAttackHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, damage: Double) {
        guard s.units[attacker].hero?.kit != nil else { return }
        Self.gainStack(&s, attacker)
    }

    // MARK: D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        guard s.units.indices.contains(target) else { return .useDefault }
        let dist = s.units[bot].pos.distance(to: s.units[target].pos)
        switch slot {
        case .skill1:
            // 射程に敵が入ったら連弾を始める（効果中は canStart が弾く）
            return fighting && dist <= s.units[bot].stats.attackRange + 100 ? .cast(.none) : .skip
        case .ultimate:
            // 低 HP で交戦中: 汎用の関門（倒せる / 2 体以上）を飛ばして使う（弱体の解除 + 隠密 + 加速で離脱）。
            // それ以外は交戦中に使う（隠密を抜けると最大の段で攻撃し始める）
            if fighting, dist <= 700, Self.needsEscape(s, bot) { return .castNow(.none) }
            return fighting && dist <= 700 ? .cast(.none) : .skip
        default:
            return .useDefault
        }
    }

    /// 撤退中（敵が 500 以内）: 隠れ月光は唯一の離脱手段（解除 + 隠密 + 加速）。低 HP、または足を止められて HP が減っているとき使う。
    /// スキル1・2 は逃走に使わない（既定のまま）。
    func botEscape(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                   flee: Vec2, enemyDistance: Double) -> BotKitDecision {
        guard slot == .ultimate else { return .useDefault }
        return Self.needsEscape(s, bot) ? .castNow(.none) : .skip
    }

    /// 離脱が要る状態か: HP が 45% 以下、または減速・移動不能を受けていて HP が 70% 以下。すでに隠れている間は不要。
    static func needsEscape(_ s: SimState, _ bot: Int) -> Bool {
        guard s.units.indices.contains(bot), s.units[bot].hero?.kit?.luminaHidden != true else { return false }
        let hp = s.units[bot].hpRatio
        let hobbled = s.units[bot].has(.slow) || s.units[bot].has(.root)
        return hp <= T.escapeHP || (hobbled && hp <= T.escapeHPHobbled)
    }

    // MARK: ヘルパー

    /// 月影のダメージ（公式 30 + 攻撃力 25% を shadowScale 倍）。
    static func shadowDamage(attack: Double) -> Double { T.shadowFlat + T.shadowRatio * attack }

    /// 月弦分矢の持続（公式 4 → 9 秒をランクで補間）。
    static func s1Duration(rank: Int) -> Double {
        lerp(T.s1DurationTable.0, T.s1DurationTable.1, rank: rank, maxRank: SkillSlot.skill1.maxRank)
    }

    /// 月弦分矢の主矢 1 本の追加ダメージ（公式の基礎 10 → 35 をランクで補間し、スロット倍率 × s1Scale。+100% 物理攻撃は通常攻撃そのもの）。
    static func arrowBonus(rank: Int) -> Double {
        lerp(T.s1Base.0, T.s1Base.1, rank: rank, maxRank: SkillSlot.skill1.maxRank) * Balance.Skills.damageScale(.skill1)
            * T.s1Scale
    }

    /// 月蝕の矢の着弾のダメージ（公式 270 → 420 + 45% 物理攻撃）。
    static func eclipseDamage(rank: Int, stats: Stats) -> Double {
        s2Damage(T.s2Base, ratio: T.s2AttackRatio, rank: rank, stats: stats)
    }

    /// 月蝕の矢の小さな矢 1 本のダメージ（公式 40 → 105 + 20% 物理攻撃）。
    static func minorDamage(rank: Int, stats: Stats) -> Double {
        s2Damage(T.s2MinorBase, ratio: T.s2MinorAttackRatio, rank: rank, stats: stats)
    }

    /// (公式の基礎 + 係数 × 攻撃力 × skillAttackScalingFactor) × スロット倍率 × s2Scale。
    private static func s2Damage(_ base: (Double, Double), ratio: Double, rank: Int, stats: Stats) -> Double {
        let b = lerp(base.0, base.1, rank: rank, maxRank: SkillSlot.skill2.maxRank)
        return (b + ratio * stats.attack * Balance.skillAttackScalingFactor) * Balance.Skills.damageScale(.skill2) * T.s2Scale
    }

    /// スキル2 の公式の基礎（ランクで補間）を sim の式に通した「換算後の基礎」。
    static func scaledBase(_ table: (Double, Double), rank: Int) -> Double {
        lerp(table.0, table.1, rank: rank, maxRank: SkillSlot.skill2.maxRank) * Balance.Skills.damageScale(.skill2) * T.s2Scale
    }

    /// スキル2 の公式の「+N% 物理攻撃」を sim の式に通した、攻撃力に対する割合（%）。
    static func attackPercent(_ ratio: Double) -> Double {
        ratio * Balance.skillAttackScalingFactor * Balance.Skills.damageScale(.skill2) * T.s2Scale * 100
    }

    /// 公式の Lv1 → 最終 Lv の値を、ランク 1 → 最大ランクへ線形補間する。
    static func lerp(_ a: Double, _ b: Double, rank: Int, maxRank: Int) -> Double {
        guard maxRank > 1 else { return a }
        let t = Double(min(max(1, rank), maxRank) - 1) / Double(maxRank - 1)
        return a + (b - a) * t
    }

    /// 段を 1 つ積み、持続を 4 秒に戻す。
    static func gainStack(_ s: inout SimState, _ i: Int) {
        let next = min(T.maxStacks, (s.units[i].hero?.kit?.luminaStacks ?? 0) + 1)
        setStacks(&s, i, next)
    }

    static func setStacks(_ s: inout SimState, _ i: Int, _ stacks: Int) {
        guard s.units[i].hero?.kit != nil, stacks > 0 else { return }
        let n = min(T.maxStacks, stacks)
        s.units[i].hero?.kit?.luminaStacks = n
        s.units[i].hero?.kit?.luminaStackTimer = T.stackDuration
        CombatSystem.addStatus(&s, targetIndex: i,
                               StatusEffect(kind: .attackSpeedBoost, duration: T.stackDuration,
                                            magnitude: T.attackSpeedPerStack * Double(n), sourceID: s.units[i].id,
                                            tag: T.stackTag))
    }

    static func clearStacks(_ s: inout SimState, _ i: Int) {
        s.units[i].hero?.kit?.luminaStacks = 0
        s.units[i].hero?.kit?.luminaStackTimer = 0
        s.units[i].statuses.removeAll { $0.kind == .attackSpeedBoost && $0.tag == T.stackTag }
    }

    /// 隠れ月光が終わっていたら後始末（加速を外し、月環の導きを最大に）。終わっていなければ何もしない。
    static func settleHidden(_ s: inout SimState, _ i: Int) {
        guard s.units[i].hero?.kit?.luminaHidden == true else { return }
        let hidden = s.units[i].statuses.contains { $0.kind == .stealth && $0.tag == T.hiddenTag }
        guard !hidden else { return }
        s.units[i].hero?.kit?.luminaHidden = false
        s.units[i].hero?.kit?.luminaHiddenRemaining = 0
        s.units[i].statuses.removeAll { $0.kind == .speedBoost && $0.tag == T.hiddenSpeedTag }
        setStacks(&s, i, T.maxStacks)
    }

    /// 副矢: 主矢の対象の周囲にいる最も近い敵（最大 splashCount 体）へ、主矢の 30% の追尾弾。
    /// 術者の射程の近くにいる敵だけ（射程外の敵へは飛ばない）。構造物へは飛ばない。
    static func fireSplash(_ s: inout SimState, attacker i: Int, primary t: Int, mainDamage: Double, isCrit: Bool) {
        let team = s.units[i].team
        let center = s.units[t].pos
        let here = s.units[i].pos
        let range = s.units[i].stats.attackRange + s.units[i].radius + T.splashLeeway
        var picked: [(d: Double, j: Int)] = []
        for j in s.units.indices where j != t && j != i && !s.units[j].isStructure {
            guard s.isTargetableEnemy(j, of: team) else { continue }
            let near = T.splashRadius + s.units[j].radius
            let d = s.units[j].pos.distanceSquared(to: center)
            guard d <= near * near else { continue }
            let reach = range + s.units[j].radius
            guard s.units[j].pos.distanceSquared(to: here) <= reach * reach else { continue }
            picked.append((d, j))
        }
        guard !picked.isEmpty else { return }
        picked.sort { $0.d != $1.d ? $0.d < $1.d : $0.j < $1.j }
        let p = HitPayload(damage: mainDamage * T.splashRatio, damageType: .physical, source: .basicAttack, isCrit: isCrit)
        for entry in picked.prefix(T.splashCount) {
            ProjectileSystem.spawn(&s, ownerIndex: i, motion: .homing(targetID: s.units[entry.j].id),
                                   speed: Balance.heroProjectileSpeed, payload: p, visual: "basic_attack")
            s.units[i].hero?.kit?.luminaSplashArrows += 1
        }
    }

    /// 現在のランク・能力値でのスキルと数値。
    static func numbersNow(_ s: SimState, _ ctx: SimContext, _ i: Int, _ slot: SkillSlot) -> (SkillDef, SkillNumbers)? {
        guard let h = s.units[i].hero, let def = ctx.master.hero(h.heroID),
              let skill = ctx.master.skill(hero: h.heroID, slot: slot) else { return nil }
        return (skill, SkillCatalog.numbers(for: skill, hero: def, rank: max(1, h.rank(slot)), stats: s.units[i].stats))
    }

    /// MLBB のクールダウン（秒）をランクで線形補間し、CD 短縮を掛ける（全体倍率 cooldownScale は 1.0 = MLBB の秒数のまま）。
    static func cooldown(_ range: (Double, Double), rank: Int, maxRank: Int, stats: Stats) -> Double {
        let sec = lerp(range.0, range.1, rank: rank, maxRank: maxRank)
        let reduction = min(Balance.maxCooldownReduction, max(0, stats.cooldownReduction))
        return sec * (1 - reduction) * Balance.Skills.cooldownScale
    }

    /// 説明文に埋める秒数（整数なら整数、そうでなければ小数 2 桁まで。0.35 が 0.3 / 0.4 に丸まらないように）。
    static func seconds(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.005 { return String(Int(v.rounded())) }
        var t = String(format: "%.2f", v)
        while t.hasSuffix("0") { t.removeLast() }
        return t
    }
}
