import Foundation

// 担当: kit-H025（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Miya.md）
// H025 月弦のルミナ = MLBB ミヤの Velstria 版（レンジャー・遠隔 550・マナ）。調査: docs/kits/Miya.md、対応表: 同ファイル末尾。
//   パッシブ 月環の導き  — 通常攻撃が命中するたびに攻撃速度 +9%（4 秒・最大 5 段）。最大のあいだは通常攻撃のたびに「月影」が
//                          70 + 攻撃力 40% の物理ダメージを追って与える。ロールの「4 発毎の確定会心」は置き換え。
//   スキル1 月弦分矢     — 自己強化 4 秒。通常攻撃が主矢 + 副矢 2 本になる（主矢に追加ダメージ、周囲の敵 2 体へ主矢の 30%）。
//                          効果中は再使用できない（CD 11 秒 × Velstria の倍率）。
//   スキル2 月蝕の矢     — 指定地点（遅延あり）。半径内の敵に物理ダメージと 1.2 秒の移動不能。着弾点から 6 本の小さな矢が
//                          等間隔に散り、それぞれ最初に当たった敵に物理ダメージと 2 秒の 30% スロウ。
//   アルティメット 隠れ月光 — 弱体をすべて解除して姿を隠し、2 秒間 移動速度 +65%。通常攻撃かスキルの発動（奥義を除く）で解ける。
//                          解けた（時間切れ含む）瞬間に月環の導きが最大の段になる。ボットは低 HP で敵が近いとき、逃走・解除に使う。
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
    /// 1 段あたりの攻撃速度（ミヤは 5%）。Velstria は TTK が短く立ち上がりが遅いので 9%（最大 +45%）に調整。
    /// 総当たりの勝率がレンジャー中央値より Lv6 で 25 pt 低かったため（0.06 → 0.09 と月影の増強で -14 pt 台へ）。
    static let attackSpeedPerStack: Double = 0.09
    static let stackDuration: Double = 4
    /// 月影: ミヤは 30 + 攻撃力 25%（攻撃力 115 に対し約 0.5 倍の追撃）。Velstria は TTK が短く構えの立ち上がりが遅い分、
    /// 固定値 70・攻撃力 40%（攻撃力 138〜200 に対し約 0.9 倍）に調整した。docs/kits/Miya.md の対応表を参照。
    static let shadowFlat: Double = 70
    static let shadowRatio: Double = 0.40

    // MARK: S1（月矢の連弾）
    static let s1Duration: Double = 4
    /// 主矢の追加ダメージの合計（標準的な s1Arrows 本ぶん）が、汎用 S1 の何倍か。CD が汎用の 3.25 秒に対し 5.5 秒と長いので 1.3 倍の上限近くまで使う。
    static let s1Ratio: Double = 1.28
    /// 効果時間内に撃つ標準的な本数（基礎の攻撃速度で 4 秒に撃つ数。説明・予算の目安で、攻撃速度の段が積もれば 6 本前後まで増える）。
    static let s1Arrows = 4
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
    /// 汎用の遠隔 S2 は「ブリンク + 強化攻撃」で数値が半分になっているので、基準は元のスキル値（base ÷ empowerRatio）。
    static let s2PrimaryRatio: Double = 0.66
    /// 小さな矢 1 本 = 着弾の 0.15 倍（ミヤ: 40/270 = 0.15）。6 本すべてが 1 体に当たる最悪でも合計 1.26 倍。
    static let s2MinorRatio: Double = 0.10

    // MARK: 奥義（隠れ月光）
    static let ultDuration: Double = 2
    static let ultSpeed: Double = 0.65
    /// 「撃てる距離」の目安（奥義の距離 770。`reachOverride`）。
    static let ultReach: Double = 770
    static let ultCooldown = (30.0, 20.0)
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
                        KitStat(key: "shadowRatio", value: T.shadowRatio * 100)]
        case .skill1:
            // damage = 主矢 1 本あたりの追加ダメージ。hits = 標準的な本数（合計 = 汎用 S1 の s1Ratio 倍）
            n.hits = T.s1Arrows
            n.damage = base.damage * T.s1Ratio / Double(T.s1Arrows)
            n.cooldown = Self.cooldown(T.s1Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .none
            n.ccDuration = 0
            n.extras = [KitStat(key: "duration", value: T.s1Duration),
                        KitStat(key: "splashPercent", value: T.splashRatio * 100),
                        KitStat(key: "splashCount", value: Double(T.splashCount)),
                        KitStat(key: "splashRadius", value: T.splashRadius)]
        case .skill2:
            let raw = base.damage / Balance.Skills.empowerRatio
            n.damage = raw * T.s2PrimaryRatio
            n.hits = 1
            n.delay = T.s2Delay
            n.cc = .root
            n.ccDuration = T.s2Root
            // 説明に出す値は整数にそろえる（実際の小さな矢のダメージは minorDamage(primary:) が持つ）
            n.extras = [KitStat(key: "minorDamage", value: Self.minorDamage(primary: n.damage).rounded()),
                        KitStat(key: "root", value: T.s2Root),
                        KitStat(key: "slowPercent", value: T.s2Slow * 100),
                        KitStat(key: "slowDuration", value: T.s2SlowDuration)]
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

    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "通常攻撃が命中するたびに攻撃速度が{x0}%上がる（{x1}秒間・最大\(T.maxStacks)段）。最大まで重なると、"
                    + "通常攻撃のたびに「月影」が追撃し、{damage}の物理ダメージ（{x2}＋攻撃力の{x3}%）を与える。",
                en: "Each basic attack hit grants +{x0}% attack speed for {x1}s (up to \(T.maxStacks) stacks). At full stacks, "
                    + "every basic attack is followed by a Moonlight Shadow that deals {damage} physical damage ({x2} + {x3}% of attack).")
        case .skill1:
            return KitText(
                ja: "{x0}秒間、通常攻撃が主矢と副矢の連弾になる。主矢に{damage}の物理ダメージを加えて撃ち（標準で{hits}本、合計{total}）、"
                    + "主矢の周囲{x3}にいる敵{x2}体へ、主矢の{x1}%の副矢が飛ぶ。効果中は再使用できない。クールダウン{cd}秒。",
                en: "For {x0}s, basic attacks become volleys. The main arrow deals an extra {damage} physical damage "
                    + "(about {hits} arrows, {total} total), and {x2} enemies within {x3} of it are hit by side arrows for {x1}% "
                    + "of the main arrow. Cannot be recast while active. Cooldown {cd}s.")
        case .skill2:
            return KitText(
                ja: "指定地点へ矢を放つ（着弾まで\(Self.seconds(T.s2Delay))秒）。半径{radius}の敵に{damage}の物理ダメージを与え、"
                    + "{x1}秒間 移動できなくする（攻撃とスキルは可能）。着弾後、矢は\(T.s2Arrows)本に分かれて四方へ散り、"
                    + "それぞれ最初に当たった敵に{x0}の物理ダメージと、{x3}秒間{x2}%のスロウを与える。",
                en: "Fires an arrow at a target area (lands after \(Self.seconds(T.s2Delay))s). Enemies within {radius} take "
                    + "{damage} physical damage and cannot move for {x1}s (they can still attack and cast). On landing, the arrow "
                    + "splits into \(T.s2Arrows) arrows that scatter evenly; each deals {x0} physical damage to the first enemy it hits "
                    + "and slows them by {x2}% for {x3}s.")
        case .ultimate:
            return KitText(
                ja: "受けている弱体をすべて解除し、{x0}秒間 姿を隠して移動速度が{x1}%上がる。通常攻撃かスキルの発動（アルティメットを除く）で解ける。"
                    + "解けた瞬間、月環の導きが最大の段（{x2}段）になる。クールダウン{cd}秒。",
                en: "Removes all debuffs and conceals you for {x0}s with +{x1}% movement speed. Ends when you attack or cast a "
                    + "skill (other than the Ultimate). When it ends, Moonring Guidance jumps to full stacks ({x2}). Cooldown {cd}s.")
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            return KitBadge(kind: .stacks, value: min(T.maxStacks, k.luminaStacks), maxValue: T.maxStacks)
        case .skill1:
            guard k.luminaMoonArrow > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.luminaMoonArrow, total: T.s1Duration)
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

    /// S1: 通常攻撃を月矢の連弾にする自己強化。主矢の追加ダメージは発動時のランク・能力値で固定する。
    private func castMoonArrow(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        s.units[i].hero?.kit?.luminaMoonArrow = T.s1Duration
        s.units[i].hero?.kit?.luminaArrowBonus = c.numbers.damage
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: s.units[i].pos, shape: .selfRing,
                     duration: T.s1Duration, count: 1 + T.splashCount)
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
        let damage = Self.minorDamage(primary: n.damage)
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

    /// 月影のダメージ（30 + 攻撃力 25% の Velstria 版）。
    static func shadowDamage(attack: Double) -> Double { T.shadowFlat + T.shadowRatio * attack }

    /// 月蝕の矢の小さな矢 1 本のダメージ（着弾のダメージ primary と同じ元の値から、比で決まる）。
    static func minorDamage(primary: Double) -> Double { primary * T.s2MinorRatio / T.s2PrimaryRatio }

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

    /// MLBB のクールダウン（秒）をランクで線形補間し、Velstria の全体倍率と CD 短縮を掛ける。
    static func cooldown(_ range: (Double, Double), rank: Int, maxRank: Int, stats: Stats) -> Double {
        var sec = range.0
        if maxRank > 1 {
            let t = Double(min(max(1, rank), maxRank) - 1) / Double(maxRank - 1)
            sec = range.0 + (range.1 - range.0) * t
        }
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
