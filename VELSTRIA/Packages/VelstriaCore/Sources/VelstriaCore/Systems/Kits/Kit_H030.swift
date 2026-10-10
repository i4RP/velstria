import Foundation

// 担当: kit-H030（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Layla.md）
// H030 星砲のライナ = MLBB ライラの Velstria 版（レンジャー・遠隔 550・マナ）。
// 遠距離ほど火力が伸びる砲撃手。パッシブは距離補正（通常攻撃・スキル。タワーには効かない）、
// スキル1（遠星弾）は会心のある直線弾（命中で射程延長と加速）、スキル2（星爆弾）は爆発する星環弾（誰にも当たらなくても射程の端で
// 爆発し、軽い減速と刻印を付ける。刻印へ当てると弾けて周囲をスタン）、アルティメット（星砕の大砲）は短い溜めの後に画面を貫く貫通ビーム。
// アルティメットのランクごとに通常攻撃と星環弾の射程が常に伸びる。
// 数値の正は MLBB の日本語クライアントのスキル詳細（docs/kits/Layla.md の「公式（日本語クライアント）の数値」。Fandom と違うところはこちらが優先）。
// クールダウン・マナ・ダメージの表を Velstria のランク（スキル1・2 は 4 段、アルティメットは 3 段）へ線形補間し（ランク 1 = Lv1、最大ランク = 公式の最終 Lv）、
// ダメージは sim の通常の式 (基礎 + 係数 × 攻撃力 × skillAttackScalingFactor) × スロット倍率 にスキルごとの換算（s1Scale ほか）を掛ける。
// 対応表は docs/kits/Layla.md の「Velstria 実装対応表」。

/// ライナの調整値（docs/kits/Layla.md の数値を Velstria の単位・TTK に合わせたもの）。
enum RainaTuning {
    // MARK: パッシブ（遠星の照準）
    /// 補正が最大になる距離（Velstria 単位）。公式は「6 離れると最大」= 6 マス ≈ 600（距離は MLBB × 100）。
    /// 基本射程の端（550）では約 +14%、射程延長を重ねると頭打ちの +15% に届く。
    static let farDistance: Double = 600
    /// 遠隔の基本射程（通常攻撃。説明文で「射程の何倍」と書くための値）。
    static let baseRange: Double = 550
    /// 公式: 最小 100%、最大 115%（タワーには適用されない）。
    static let maxDistanceBonus: Double = 0.15
    static let distanceScaling = DamageScaling.distance(near: 0, far: farDistance, minMult: 1,
                                                        maxMult: 1 + maxDistanceBonus)
    /// パッシブのバッジ（遠距離命中の合図）: 敵ヒーローへの通常攻撃・スキルの命中の距離補正がこの値以上なら、
    /// バッジに短いタイマーを出す（+10% = 最大の 2/3 = 距離 400 以上。基本射程の端 550 では +14%）。HUD の金の印と App のパッシブの演出の合図。
    static let farHitBonus: Double = 0.10
    /// 合図の長さ。命中のたびに付け直すので、射程の端から撃ち続けている間は点いたまま（演出は点いた瞬間に 1 回）。
    static let farHitFlash: Double = 1.5

    // MARK: 射程
    /// 奥義 1 ランクごとの通常攻撃・星環弾の射程の常時延長（ライラ: +0.6 マス/ランク）。
    static let ultRangePerRank: Double = 60
    /// S1 命中時の一時的な射程延長（奥義ランク 0〜3。ライラ: +1.6 / 1.4 / 1.2 / 1.0 マス）。
    static let s1RangeBuff: [Double] = [160, 140, 120, 100]
    static let s1RangeBuffDuration: Double = 3
    /// 常時延長のステータスに持たせる持続（実質無期限）。
    static let permanent: Double = 1_000_000

    // MARK: S1（マレフィック・ボム）
    /// 公式: 200 / 240 / 280 / 320 / 360 / 400（+80% 物理攻撃）。Lv1 → Lv6 をランク 1 → 4 へ線形補間し、
    /// sim の通常の式 (基礎 + 係数 × 攻撃力 × 0.6) × スロット倍率 に換算 s1Scale を掛ける。
    static let s1Base = (200.0, 400.0)
    static let s1AttackRatio: Double = 0.8
    /// 0.53 でランク 1 が以前の「汎用 S1 × 0.92」と同じ大きさ（Lv1 で約 565）。距離補正が日本語クライアントの最大 115%（以前 130%）になって Lv1 がレンジャー中央値 −20 pt になったので 0.58。
    static let s1Scale: Double = 0.58
    /// 命中時の加速（+60%、1.2 秒かけて 0 へ。敵ヒーローに当たると持続が倍）。
    static let rushSpeed: Double = 0.6
    static let rushDuration: Double = 1.2
    static let rushHeroDuration: Double = 2.4

    // MARK: S2（ヴォイド・プロジェクタイル）
    /// 公式: 爆発 170 → 320（+65% 物理攻撃）、刻印の炸裂（追加ダメージ）100 → 200（+35% 物理攻撃）。換算は s2Scale（両方に共通）。
    static let s2Base = (170.0, 320.0)
    static let s2AttackRatio: Double = 0.65
    static let detonationBase = (100.0, 200.0)
    static let detonationAttackRatio: Double = 0.35
    /// 0.55 でランク 1 の爆発が以前の「元のスキル値 × 0.70」と同じ。KitBalanceTests で Lv12 を中央値へ寄せて 0.54。
    static let s2Scale: Double = 0.54
    static let s2Speed: Double = 1500
    static let s2Width: Double = 60
    // 爆発の減速は無い（日本語クライアントの文・タグ「範囲技・妨害」に減速は無い。以前は Fandom のタグ「Slowed」から 30%・1 秒を足していた）。
    /// 射程の端で消える瞬間に爆発させる予約の余裕（弾が消えた次の tick 以降に爆発させる）。
    static let orbEndLag: Double = Balance.dt
    /// 爆発と刻印の弾けの半径は同じ（スキル定義の radius）。
    static let markDuration: Double = 3
    static let markStun: Double = 0.25

    // MARK: 奥義（デストラクション・ラッシュ）
    /// 公式: 500 / 650 / 800（+150% 物理攻撃）。アルティメットの 3 ランクは公式の Lv そのまま。換算は ultScale。
    static let ultBase = (500.0, 800.0)
    static let ultAttackRatio: Double = 1.5
    /// 0.59 でランク 1 が以前の「汎用の奥義 × 1.0」と同じ。KitBalanceTests で Lv12 を中央値へ寄せて 0.56 → S1 を 0.58 に上げたぶん 0.52。
    static let ultScale: Double = 0.52
    /// 溜め（0.3 → 0.2 秒）とビームの速さ（3600 → 7000）。弾は 1 tick の区間を線分で掃引して当てる（ProjectileSystem.stepLinear）ので
    /// 7000（1 tick = 約 233）でもすり抜けない。射程 2000 を約 0.29 秒で貫くので、動く相手にも「撃った瞬間」に近く当たる。
    static let ultWindup: Double = 0.2
    static let ultBeamSpeed: Double = 7000

    // MARK: クールダウン（MLBB の秒数そのまま。ランク間を線形補間し、CD 短縮を掛ける。全体倍率 Balance.Skills.cooldownScale は 1.0）
    /// ライラ: S1 6.0 → 4.0 / S2 7.5 → 6.5 / 奥義 37 / 32 / 27 秒（以前はマスターの CD 6.5 / 7.6 / 33 秒のままだった）。
    static let s1Cooldown = (6.0, 4.0)
    static let s2Cooldown = (7.5, 6.5)
    static let ultCooldown = (37.0, 27.0)

    // MARK: マナ（公式の表をランクで線形補間。HeroKit.cost）
    /// ライラ（日本語クライアント）: S1 35 → 60 / S2 70（一定）/ 奥義 130 / 150 / 170（Fandom の S1 40 → 65・S2 65 → 90 は誤り。
    /// その前はマスターの 45 / 50 / 100 のままだった）。
    static let s1Cost = (35.0, 60.0)
    static let s2Cost = (70.0, 70.0)
    static let ultCost = (130.0, 170.0)

    // MARK: タグ・コード
    static let ultRangeTag = KitTags.buff("H030", "ultRange")
    static let s1RangeTag = KitTags.buff("H030", "s1Range")
    static let rushTag = KitTags.buff("H030", "rush")
    static let markStunTag = KitTags.buff("H030", "markStun")
    static let markName = "void"

    /// HitPayload.kitEvent
    enum Event {
        static let bomb = 1
        static let orb = 2
        static let beam = 3
        /// 星環弾の爆発（範囲の各対象。パッシブの合図だけに使う）
        static let blast = 4
    }

    /// KitTimer.code
    enum Code {
        static let beam = 1
        /// 星環弾が何にも当たらずに射程の端へ着いた: その場で爆発する（当たったら onHit が取り消す）。
        static let orbEnd = 2
    }
}

extension KitState {
    /// S1 の射程延長の残り秒（HUD のバッジ用）。
    var rainaRangeBuff: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    /// S2 を撃った位置（爆発の距離補正の起点）。
    var rainaOrbOrigin: Vec2 {
        get { Vec2(reals[0], reals[1]) }
        set {
            reals[0] = newValue.x
            reals[1] = newValue.y
        }
    }

    /// 刻印が弾けた回数（検証用）。
    var rainaDetonations: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    /// パッシブの合図（遠距離命中）の残り秒。
    var rainaFarFlash: Double {
        get { timers[1] }
        set { timers[1] = newValue }
    }

    /// 合図を出した最後の命中の距離補正（%、整数に丸めた値）。
    var rainaFarBonus: Int {
        get { ints[1] }
        set { ints[1] = newValue }
    }
    /// 最後に放った通常攻撃の発射位置（パッシブの合図の距離の起点。ダメージの補正は弾ごとの originPos）。
    var rainaShotOrigin: Vec2 {
        get { Vec2(reals[2], reals[3]) }
        set {
            reals[2] = newValue.x
            reals[3] = newValue.y
        }
    }

    /// S1 を撃った位置（パッシブの合図の距離の起点）。
    var rainaBombOrigin: Vec2 {
        get { Vec2(reals[4], reals[5]) }
        set {
            reals[4] = newValue.x
            reals[5] = newValue.y
        }
    }

    /// 奥義のビームを放った位置（パッシブの合図の距離の起点）。
    var rainaBeamOrigin: Vec2 {
        get { Vec2(reals[6], reals[7]) }
        set {
            reals[6] = newValue.x
            reals[7] = newValue.y
        }
    }
}

struct Kit_H030: HeroKit {
    let heroID = "H030"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H030(isReady: true)` を HeroKits.testOverride に差すこともできる。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    typealias T = RainaTuning

    // MARK: A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 汎用の遠隔直線弾のまま（射程 650・弾幅は半径の半分）
            return base
        case .skill2:
            // 星環弾: 直線に飛んで最初の敵で爆発する。radius は弾の半幅（爆発の半径は numbers の extras）
            return SkillTargeting(archetype: .lineSkillshot, aim: .direction, range: skill.range, radius: T.s2Width)
        case .ultimate:
            var t = base
            t.shape = .wideLine
            return t
        case .passive:
            return base
        }
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        var n = base
        switch slot {
        case .passive:
            n.extras = [KitStat(key: "maxBonus", value: T.maxDistanceBonus * 100),
                        KitStat(key: "rangePerRank", value: T.ultRangePerRank),
                        KitStat(key: "farDistance", value: T.farDistance),
                        KitStat(key: "maxPercent", value: (1 + T.maxDistanceBonus) * 100)]
        case .skill1:
            n.damage = Self.damage(base: T.s1Base, ratio: T.s1AttackRatio, slot: .skill1, scale: T.s1Scale, rank: rank,
                                   stats: stats)
            n.cooldown = Self.cooldown(T.s1Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.extras = [KitStat(key: "rangeBuff", value: T.s1RangeBuff[0]),
                        KitStat(key: "rangeBuffDuration", value: T.s1RangeBuffDuration),
                        KitStat(key: "rushPercent", value: T.rushSpeed * 100),
                        KitStat(key: "rushDuration", value: T.rushDuration),
                        KitStat(key: "rangeBuffMin", value: T.s1RangeBuff[T.s1RangeBuff.count - 1]),
                        KitStat(key: "base", value: Self.scaledBase(T.s1Base, slot: .skill1, scale: T.s1Scale, rank: rank,
                                                                    maxRank: slot.maxRank).rounded()),
                        KitStat(key: "atkPct", value: Self.attackPercent(T.s1AttackRatio, slot: .skill1,
                                                                         scale: T.s1Scale).rounded())]
        case .skill2:
            n.damage = Self.damage(base: T.s2Base, ratio: T.s2AttackRatio, slot: .skill2, scale: T.s2Scale, rank: rank,
                                   stats: stats)
            n.cooldown = Self.cooldown(T.s2Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            // CC は刻印の弾けのスタン（爆発そのものには CC が無い）
            n.cc = .stun
            n.ccDuration = T.markStun
            let detonation = Self.damage(base: T.detonationBase, ratio: T.detonationAttackRatio, slot: .skill2,
                                         scale: T.s2Scale, rank: rank, stats: stats)
            n.extras = [KitStat(key: "detonation", value: detonation),
                        KitStat(key: "markDuration", value: T.markDuration),
                        KitStat(key: "markStun", value: T.markStun),
                        KitStat(key: "blastRadius", value: skill.radius),
                        KitStat(key: "base", value: Self.scaledBase(T.s2Base, slot: .skill2, scale: T.s2Scale, rank: rank,
                                                                    maxRank: slot.maxRank).rounded()),
                        KitStat(key: "atkPct", value: Self.attackPercent(T.s2AttackRatio, slot: .skill2,
                                                                         scale: T.s2Scale).rounded()),
                        KitStat(key: "detBase", value: Self.scaledBase(T.detonationBase, slot: .skill2, scale: T.s2Scale,
                                                                       rank: rank, maxRank: slot.maxRank).rounded()),
                        KitStat(key: "detPct", value: Self.attackPercent(T.detonationAttackRatio, slot: .skill2,
                                                                         scale: T.s2Scale).rounded())]
        case .ultimate:
            n.damage = Self.damage(base: T.ultBase, ratio: T.ultAttackRatio, slot: .ultimate, scale: T.ultScale, rank: rank,
                                   stats: stats)
            n.cooldown = Self.cooldown(T.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.extras = [KitStat(key: "rangePerRank", value: T.ultRangePerRank),
                        KitStat(key: "windup", value: T.ultWindup),
                        KitStat(key: "base", value: Self.scaledBase(T.ultBase, slot: .ultimate, scale: T.ultScale, rank: rank,
                                                                    maxRank: slot.maxRank).rounded()),
                        KitStat(key: "atkPct", value: Self.attackPercent(T.ultAttackRatio, slot: .ultimate,
                                                                         scale: T.ultScale).rounded()),
                        KitStat(key: "rangeMax", value: T.ultRangePerRank * Double(slot.maxRank))]
        }
        return n
    }

    /// ランクごとのマナ消費（公式: スキル1 = 35 → 60、スキル2 = 70（一定）、アルティメット = 130 / 150 / 170）。
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

    /// 説明文は公式（日本語クライアント）の文の構造に合わせる。数値は {トークン} で sim から入れる
    /// （{base}(+{atkPct}%物理攻撃) は sim の式に換算した値。距離は通常攻撃の基本射程に対する倍率でも示す）。
    /// 名前は master のもの（マジックボム = 遠星弾、ボイドショット = 星爆弾、マジックマーク = 刻印）。
    func text(slot: SkillSlot) -> KitText? {
        let farMult = String(format: "%.1f", T.farDistance / T.baseRange)
        let edgeBonus = Int((T.maxDistanceBonus * T.baseRange / T.farDistance * 100).rounded())
        switch slot {
        case .passive:
            return KitText(
                ja: "距離が遠い対象ほど、与ダメージが増加する（最小100%、距離{farDistance}＝基本射程の約\(farMult)倍離れると最大{maxPercent}%まで増加する。"
                    + "基本射程（\(Int(T.baseRange))）の端では約\(100 + edgeBonus)%）。タワーには適用されない。\n\n"
                    + "ダメージの増加は通常攻撃とスキルにのみ適用される。",
                en: "Deals more damage to targets farther away (at least 100%, rising to up to {maxPercent}% at distance {farDistance}, "
                    + "about \(farMult)x the basic range; about \(100 + edgeBonus)% at the edge of the basic range, \(Int(T.baseRange))). "
                    + "Does not apply to turrets.\n\nThe increase only applies to basic attacks and skills.",
                tags: [KitTag.buff])
        case .skill1:
            return KitText(
                ja: "指定方向に遠星弾を放ち、最初に命中した敵に{base}(+{atkPct}%物理攻撃)の物理ダメージを与える（クリティカル可能）。\n\n"
                    + "敵に命中すると、通常攻撃と星爆弾の射程が{rangeBuffDuration}秒間{rangeBuff}伸びる（アルティメットのランクが上がるほど小さくなり、"
                    + "最大ランクで{rangeBuffMin}）。さらに移動速度が追加で{rushPercent}%上昇し、この移動速度上昇効果は{rushDuration}秒かけて徐々に減少する。"
                    + "敵ヒーローに命中した場合、移動速度上昇効果の持続時間が2倍になる。",
                en: "Fires a Farstar Shot in the target direction, dealing {base} (+{atkPct}% Physical Attack) physical damage "
                    + "to the first enemy hit (can critically strike).\n\nUpon hitting an enemy, the range of basic attacks and "
                    + "Starburst Shell increases by {rangeBuff} for {rangeBuffDuration}s (smaller as the Ultimate ranks up, "
                    + "{rangeBuffMin} at max rank). Movement Speed also increases by an extra {rushPercent}%, decaying over "
                    + "{rushDuration}s. The duration of the Movement Speed boost is doubled if an enemy hero is hit.",
                tags: [KitTag.burst, KitTag.buff])
        case .skill2:
            return KitText(
                ja: "指定方向に星爆弾を放ち、命中すると爆発して範囲（半径{blastRadius}）の敵に{base}(+{atkPct}%物理攻撃)の物理ダメージを与え、"
                    + "{markDuration}秒間「刻印」を付与する（何にも当たらなければ射程の端で爆発する）。\n\n"
                    + "刻印の付いた敵を攻撃すると（通常攻撃・遠星弾・アルティメット）、その敵と周囲に{detBase}(+{detPct}%物理攻撃)の"
                    + "物理ダメージを与え、{markStun}秒間スタンさせる。",
                en: "Fires a Starburst Shell in the target direction that explodes on hit, dealing {base} (+{atkPct}% Physical Attack) "
                    + "physical damage to enemies in the area (radius {blastRadius}) and applying a Mark for {markDuration}s "
                    + "(it explodes at the end of its range if nothing is hit).\n\nAttacking a marked enemy (basic attack, Farstar Shot "
                    + "or the Ultimate) deals {detBase} (+{detPct}% Physical Attack) physical damage to that enemy and those around "
                    + "it and stuns them for {markStun}s.",
                tags: [KitTag.aoe, KitTag.disrupt])
        case .ultimate:
            return KitText(
                ja: "パッシブ：星爆弾と通常攻撃の射程が{rangePerRank}広がる（このスキルのランクごと。最大{rangeMax}）。\n\n"
                    + "アクティブ：{windup}秒溜めてから指定方向に星の砲撃を放ち、直線上（射程{range}）の敵に{base}(+{atkPct}%物理攻撃)の物理ダメージを与える。",
                en: "Passive: the range of Starburst Shell and basic attacks increases by {rangePerRank} (per rank of this skill, "
                    + "up to {rangeMax}).\n\nActive: after a {windup}s charge, fires a blast of star energy in the target direction, "
                    + "dealing {base} (+{atkPct}% Physical Attack) physical damage to enemies in a line (range {range}).",
                tags: [KitTag.burst, KitTag.buff])
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            // 遠距離命中の合図: 敵ヒーローに補正 +10% 以上で当てた直後の 1.5 秒。value = その命中の補正（%）、maxValue = 頭打ちの 15
            guard k.rainaFarFlash > 0 else { return nil }
            return KitBadge(kind: .timer, value: k.rainaFarBonus, maxValue: Int((T.maxDistanceBonus * 100).rounded()),
                            remaining: k.rainaFarFlash, total: T.farHitFlash)
        case .skill1:
            guard k.rainaRangeBuff > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.rainaRangeBuff, total: T.s1RangeBuffDuration)
        default:
            return nil
        }
    }

    // MARK: B. 実行

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        let i = c.caster
        switch c.slot {
        case .skill1:
            castBomb(&s, c)
        case .skill2:
            castOrb(&s, ctx, c)
        case .ultimate:
            // 溜め（連打・スタンで途切れる）の後にビームを放つ。向きは発動時に固定
            Kit.emitCast(&s, c, target: s.units[i].pos + c.aim.direction * c.targeting.range, unit: c.aim.unit,
                         shape: .wideLine, duration: T.ultWindup, count: 1)
            Kit.schedule(&s, caster: i, slot: .ultimate, code: T.Code.beam, after: T.ultWindup, point: c.aim.direction)
        case .passive:
            break
        }
        return .done
    }

    /// S1: 直線弾。最初に当たった敵へ（会心あり・距離補正）。命中で射程延長と加速。
    private func castBomb(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        var p = HitPayload(damage: c.numbers.damage, damageType: c.check.skill.damageType, source: .skill(.skill1),
                           skillID: c.check.skill.skillID, scaling: T.distanceScaling, originPos: s.units[i].pos,
                           kitEvent: T.Event.bomb)
        if Self.rollCrit(&s, i) {
            p.isCrit = true
            p.damage *= max(1, s.units[i].stats.critMultiplier)
        }
        // パッシブの合図の距離の起点
        let castAt = s.units[i].pos
        s.units[i].hero?.kit?.rainaBombOrigin = castAt
        Kit.emitCast(&s, c, target: s.units[i].pos + c.aim.direction * c.targeting.range, unit: c.aim.unit, count: 1)
        ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: c.aim.direction, maxDistance: c.targeting.range),
                               speed: Balance.Skills.skillshotSpeed, width: c.targeting.radius, pierce: false,
                               payload: p, visual: c.check.skill.effectID)
    }

    /// S2: 星環弾。奥義ランクの常時延長と S1 の一時延長ぶん遠くへ届く。最初に当たった敵の位置で爆発する（onHit）。
    /// 何にも当たらなければ射程の端で爆発する（予約タイマー。当たったら onHit が取り消すので 1 回だけ爆発する）。
    private func castOrb(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let range = c.targeting.range + Self.rangeBonus(s, i)
        let p = HitPayload(damage: 0, damageType: c.check.skill.damageType, source: .skill(.skill2),
                           skillID: c.check.skill.skillID, kitEvent: T.Event.orb)
        let here = s.units[i].pos
        s.units[i].hero?.kit?.rainaOrbOrigin = here
        var shown = c
        shown.targeting.range = range
        Kit.emitCast(&s, shown, target: s.units[i].pos + c.aim.direction * range, unit: c.aim.unit,
                     duration: range / T.s2Speed, count: 1)
        let orb = ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: c.aim.direction, maxDistance: range),
                                         speed: T.s2Speed, width: T.s2Width, pierce: false, payload: p,
                                         visual: c.check.skill.effectID)
        // マップの端で止まるときはそこまでの距離で数える（弾が消える位置 = 爆発の位置）
        let dir = c.aim.direction.normalized
        let edge = ProjectileSystem.distanceToMapEdge(from: here, direction: dir, size: ctx.map.size)
        let flight = min(range, edge)
        Kit.schedule(&s, caster: i, slot: .skill2, code: T.Code.orbEnd, after: flight / T.s2Speed + T.orbEndLag,
                     targetID: orb, point: here + dir * flight, interruptible: false)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        switch timer.code {
        case T.Code.beam:
            fireBeam(&s, ctx, owner: owner, direction: timer.point)
        case T.Code.orbEnd:
            // 弾は何にも当たらず消えた（当たっていれば onHit が予約を取り消している）: 射程の端で爆発する
            explode(&s, ctx, owner: owner, center: timer.point)
        default:
            break
        }
    }

    /// 奥義: ライン上の全ての敵に（距離補正）。貫通する高速の弾でビームを表す。
    private func fireBeam(_ s: inout SimState, _ ctx: SimContext, owner i: Int, direction: Vec2) {
        guard let (skill, n) = Self.numbersNow(s, ctx, i, .ultimate),
              let def = ctx.master.hero(skill.heroID) else { return }
        let t = HeroKits.targeting(for: skill, hero: def, stage: 0)
        let dir = direction.normalized == .zero ? Vec2.fromAngle(s.units[i].facing) : direction.normalized
        let p = HitPayload(damage: n.damage, damageType: skill.damageType, source: .skill(.ultimate),
                           ccIsUltimate: true, skillID: skill.skillID, scaling: T.distanceScaling,
                           originPos: s.units[i].pos, kitEvent: T.Event.beam)
        let fireAt = s.units[i].pos
        s.units[i].hero?.kit?.rainaBeamOrigin = fireAt
        ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: dir, maxDistance: t.range),
                               speed: T.ultBeamSpeed, width: t.radius, pierce: true, payload: p, visual: skill.effectID)
    }

    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {
        switch event {
        case T.Event.bomb:
            Self.noteFarHit(&s, owner: owner, target: target, origin: s.units[owner].hero?.kit?.rainaBombOrigin)
            bombLanded(&s, owner: owner, target: target)
            detonate(&s, ctx, owner: owner, target: target)
        case T.Event.orb:
            // 当たった: 射程の端の爆発の予約は要らない
            Kit.cancelScheduled(&s, caster: owner, code: T.Code.orbEnd)
            explode(&s, ctx, owner: owner, center: s.units[target].pos)
        case T.Event.blast:
            Self.noteFarHit(&s, owner: owner, target: target, origin: s.units[owner].hero?.kit?.rainaOrbOrigin)
        case T.Event.beam:
            Self.noteFarHit(&s, owner: owner, target: target, origin: s.units[owner].hero?.kit?.rainaBeamOrigin)
            detonate(&s, ctx, owner: owner, target: target)
        default:
            break
        }
    }

    /// パッシブの合図: 敵ヒーローへの命中の距離補正（ダメージと同じ式・同じ起点）が farHitBonus 以上なら、バッジのタイマーを付け直す。
    /// 刻印の弾け（周囲への追加ダメージ）は数えない（弾けさせた命中そのものが数える）。
    static func noteFarHit(_ s: inout SimState, owner i: Int, target t: Int, origin: Vec2?) {
        guard let origin, s.units.indices.contains(t), s.units[t].kind == .hero, s.units[t].team != s.units[i].team,
              CombatSystem.isLiving(s, i), s.units[i].hero?.kit != nil else { return }
        let bonus = distanceBonus(origin.distance(to: s.units[t].pos))
        guard bonus >= T.farHitBonus - 1e-9 else { return }
        s.units[i].hero?.kit?.rainaFarFlash = T.farHitFlash
        s.units[i].hero?.kit?.rainaFarBonus = Int((bonus * 100).rounded())
    }

    /// 距離 → 与ダメージの増加（distanceScaling と同じ: 0 で 0、farDistance 以上で maxDistanceBonus、間は線形）。
    static func distanceBonus(_ distance: Double) -> Double {
        T.maxDistanceBonus * min(1, max(0, distance / T.farDistance))
    }

    /// S1 命中: 射程延長（奥義ランクが高いほど一時延長は小さい）と加速（敵ヒーローなら持続が倍）。
    private func bombLanded(_ s: inout SimState, owner i: Int, target t: Int) {
        guard CombatSystem.isLiving(s, i) else { return }
        let ultRank = min(max(0, s.units[i].hero?.rank(.ultimate) ?? 0), T.s1RangeBuff.count - 1)
        Kit.grantAttackRange(&s, target: i, amount: T.s1RangeBuff[ultRank], duration: T.s1RangeBuffDuration,
                             tag: T.s1RangeTag)
        s.units[i].hero?.kit?.rainaRangeBuff = T.s1RangeBuffDuration
        let duration = s.units[t].kind == .hero ? T.rushHeroDuration : T.rushDuration
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .speedBoost, duration: duration,
                                                                magnitude: T.rushSpeed, sourceID: s.units[i].id,
                                                                tag: T.rushTag))
    }

    /// S2 の爆発（命中した敵の位置、または射程の端）: 半径内の全ての敵に距離補正つきのダメージ + 刻印。
    private func explode(_ s: inout SimState, _ ctx: SimContext, owner i: Int, center: Vec2) {
        guard let (skill, n) = Self.numbersNow(s, ctx, i, .skill2) else { return }   // 放たれた弾は術者が倒れても爆発する
        let origin = s.units[i].hero?.kit?.rainaOrbOrigin ?? s.units[i].pos
        let p = HitPayload(damage: n.damage, damageType: skill.damageType, source: .skill(.skill2),
                           skillID: skill.skillID,
                           effects: [.addMark(name: T.markName, stacks: 1, maxStacks: 1, duration: T.markDuration)],
                           scaling: T.distanceScaling, originPos: origin, kitEvent: T.Event.blast)
        SkillArchetypes.hitArea(&s, ctx, caster: i, center: center, radius: skill.radius, shape: .circle, payload: p)
    }

    /// 刻印が付いた敵に通常攻撃・S1・奥義が当たったら、刻印を消費して周囲に爆発とスタン（予告なしのゾーンで演出も出す）。
    private func detonate(_ s: inout SimState, _ ctx: SimContext, owner i: Int, target t: Int) {
        guard s.units.indices.contains(t), CombatSystem.isLiving(s, i), CombatSystem.isLiving(s, t) else { return }
        let tag = KitTags.mark("H030", T.markName, owner: s.units[i].id)
        guard Kit.markStacks(s, target: t, tag: tag) > 0, let (skill, n) = Self.numbersNow(s, ctx, i, .skill2),
              let damage = n.extras.first(where: { $0.key == "detonation" })?.value else { return }
        Kit.consumeMarks(&s, target: t, tag: tag)
        s.units[i].hero?.kit?.rainaDetonations += 1
        let stun = StatusEffect(kind: .stun, duration: T.markStun, sourceID: s.units[i].id, tag: T.markStunTag)
        let p = HitPayload(damage: damage, damageType: skill.damageType, source: .skill(.skill2), statuses: [stun],
                           skillID: skill.skillID, scaling: T.distanceScaling, originPos: s.units[i].pos)
        ZoneSystem.spawn(&s, ownerIndex: i, center: s.units[t].pos, radius: skill.radius, delay: 0, payload: p,
                         visual: skill.effectID)
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner i: Int) {
        // 奥義ランクの常時射程延長（ステータスで持つ。ランクが上がれば大きさだけ更新）
        let want = T.ultRangePerRank * Double(s.units[i].hero?.rank(.ultimate) ?? 0)
        if let k = s.units[i].statuses.firstIndex(where: { $0.kind == .attackRangeBoost && $0.tag == T.ultRangeTag }) {
            if want <= 0 {
                s.units[i].statuses.remove(at: k)
            } else if s.units[i].statuses[k].magnitude != want {
                s.units[i].statuses[k].magnitude = want
            }
        } else if want > 0 {
            Kit.grantAttackRange(&s, target: i, amount: want, duration: T.permanent, tag: T.ultRangeTag)
        }
        // 加速は 1.2 秒かけて 0 へ（持続が倍のときは最初の 1.2 秒は維持）
        if let k = s.units[i].statuses.firstIndex(where: { $0.kind == .speedBoost && $0.tag == T.rushTag }) {
            let left = max(0, s.units[i].statuses[k].remaining)
            s.units[i].statuses[k].magnitude = T.rushSpeed * min(1, left / T.rushDuration)
        }
    }

    // MARK: C. パッシブ（遠星の照準）

    func shapeBasicAttack(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                          plan: inout BasicAttackPlan) {
        // タワーには効かない（公式「タワーには適用されない」）。弾の発射位置を起点に、命中時の距離で補正する
        guard !s.units[target].isStructure else { return }
        plan.payload.scaling = T.distanceScaling
        plan.payload.originPos = s.units[attacker].pos
        let shotAt = s.units[attacker].pos
        s.units[attacker].hero?.kit?.rainaShotOrigin = shotAt
    }

    func onBasicAttackHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, damage: Double) {
        // 合図の起点は最後に放った弾の位置（同時に複数の弾が飛んでいるときは最後の 1 発。ダメージは弾ごとの発射位置で正しく補正される）
        if !s.units[target].isStructure {
            Self.noteFarHit(&s, owner: attacker, target: target, origin: s.units[attacker].hero?.kit?.rainaShotOrigin)
        }
        detonate(&s, ctx, owner: attacker, target: target)
    }

    // MARK: D. ボット

    /// アルティメットの狙い: 相手の動きを先読みする。ビームは発動の 0.2 秒後（溜め）に速さ 7000 で飛ぶので、
    /// 到達までの時間は 溜め + 距離 ÷ 速さ。汎用の見積もり（0.1 + 距離 ÷ 1600）はビームより長いので使わない。
    /// 先読みの強さは難易度の精度（乱数を引かない = botCast は状態を変えない）。撃つ判断は汎用の関門（倒せる / 2 体以上）のまま。
    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting, target: Int,
                 fighting: Bool) -> BotKitDecision {
        guard slot == .ultimate, s.units.indices.contains(target), s.units.indices.contains(bot) else { return .useDefault }
        let me = s.units[bot].pos
        let foe = s.units[target]
        let dist = me.distance(to: foe.pos)
        guard dist <= targeting.range + foe.radius else { return .skip }
        let accuracy = BotProfile.of(s.units[bot].hero?.botDifficulty ?? .normal).accuracy
        let travel = T.ultWindup + dist / T.ultBeamSpeed
        let velocity = Self.observedVelocity(s, bot: bot, target: target)
        let leadSeconds = travel * accuracy
        let lead = Vec2(velocity.x * leadSeconds, velocity.y * leadSeconds)
        let direction = (foe.pos + lead - me).normalized
        return direction == .zero ? .skip : .cast(.direction(direction))
    }

    // MARK: ヘルパー

    /// ボットのチームが観測している敵ヒーローの移動速度（ユニット/秒）。見えていない・観測できなければ 0。
    static func observedVelocity(_ s: SimState, bot: Int, target: Int) -> Vec2 {
        let team = s.units[bot].team.rawValue
        guard s.bots.teams.indices.contains(team) else { return .zero }
        let intel = s.bots.teams[team]
        guard let k = intel.enemyIDs.firstIndex(of: s.units[target].id), intel.velocity.indices.contains(k) else {
            return .zero
        }
        return intel.velocity[k]
    }

    /// 通常攻撃と星環弾の現在の射程延長（奥義ランクの常時延長 + S1 の一時延長）。
    static func rangeBonus(_ s: SimState, _ i: Int) -> Double {
        var bonus = 0.0
        for st in s.units[i].statuses where st.kind == .attackRangeBoost
            && (st.tag == T.ultRangeTag || st.tag == T.s1RangeTag) {
            bonus += st.magnitude
        }
        return bonus
    }

    /// 現在のランク・能力値でのスキルと数値。
    static func numbersNow(_ s: SimState, _ ctx: SimContext, _ i: Int, _ slot: SkillSlot) -> (SkillDef, SkillNumbers)? {
        guard let h = s.units[i].hero, let def = ctx.master.hero(h.heroID),
              let skill = ctx.master.skill(hero: h.heroID, slot: slot) else { return nil }
        return (skill, SkillCatalog.numbers(for: skill, hero: def, rank: max(1, h.rank(slot)), stats: s.units[i].stats))
    }

    /// 公式の基礎ダメージ（ランクで補間）を sim の通常の式に通した「換算後の基礎」。
    static func scaledBase(_ table: (Double, Double), slot: SkillSlot, scale: Double, rank: Int, maxRank: Int) -> Double {
        lerp(table.0, table.1, rank: rank, maxRank: maxRank) * Balance.Skills.damageScale(slot) * scale
    }

    /// 公式の「+N% 物理攻撃」を sim の通常の式（× skillAttackScalingFactor × スロット倍率 × 換算）に通した、攻撃力に対する割合（%）。
    static func attackPercent(_ ratio: Double, slot: SkillSlot, scale: Double) -> Double {
        ratio * Balance.skillAttackScalingFactor * Balance.Skills.damageScale(slot) * scale * 100
    }

    /// (公式の基礎 + 係数 × 攻撃力 × skillAttackScalingFactor) × スロット倍率 × 換算。
    static func damage(base: (Double, Double), ratio: Double, slot: SkillSlot, scale: Double, rank: Int,
                       stats: Stats) -> Double {
        let b = lerp(base.0, base.1, rank: rank, maxRank: slot.maxRank)
        return (b + ratio * stats.attack * Balance.skillAttackScalingFactor) * Balance.Skills.damageScale(slot) * scale
    }

    /// MLBB のクールダウン（秒）をランクで線形補間し、CD 短縮を掛ける（全体倍率 cooldownScale は 1.0 = MLBB の秒数のまま）。
    static func cooldown(_ range: (Double, Double), rank: Int, maxRank: Int, stats: Stats) -> Double {
        let sec = lerp(range.0, range.1, rank: rank, maxRank: maxRank)
        let reduction = min(Balance.maxCooldownReduction, max(0, stats.cooldownReduction))
        return sec * (1 - reduction) * Balance.Skills.cooldownScale
    }

    /// 公式の Lv1 → 最終 Lv の値を、ランク 1 → 最大ランクへ線形補間する。
    static func lerp(_ a: Double, _ b: Double, rank: Int, maxRank: Int) -> Double {
        guard maxRank > 1 else { return a }
        let t = Double(min(max(1, rank), maxRank) - 1) / Double(maxRank - 1)
        return a + (b - a) * t
    }

    /// 会心の判定（通常攻撃と同じ。確率が 0 のときは乱数を引かない）。
    static func rollCrit(_ s: inout SimState, _ i: Int) -> Bool {
        let chance = s.units[i].stats.critChance
        if chance >= 1 { return true }
        return chance > 0 && s.rng.nextDouble() < chance
    }
}
