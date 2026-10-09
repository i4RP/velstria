import Foundation

// 担当: kit-H033（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Alucard.md）
// H033 紅牙のヴァルド = Velstria 版の Alucard（MLBB。調査: docs/kits/Alucard.md、対応表: 同ファイル末尾）。
// アサシン（ジャングル）の近接。キットはロールの汎用パッシブ（奇襲 +30% とキル/アシストの全 CD −30%）を置き換える。
//   パッシブ 追撃（Pursuit）            — スキルを発動するたび、5 秒以内の次の通常攻撃が「追撃」になる: 射程が +300 伸び、
//                                          敵の目の前まで踏み込みながら攻撃力の 140% の物理ダメージ。
//   S1   裂地撃（Groundsplitter）       — 指定した地点へ転がり込み、大剣を叩きつける。範囲にダメージ + 鈍足 40%（2 秒）。
//                                          クールダウンはランクが低いほど短い（序盤はスキル1 しか無いので）。
//                                          ボットはミニオン・ジャングルにも使う（botFarm）。
//   S2   旋回斬（Whirling Smash）       — その場で大剣を回転させ、周囲の敵にダメージ（照準なし）。
//   奥義 核分裂波（Fission Wave）       — 1 回目: 指定地点の範囲の敵のエネルギーを吸収（鈍足 30%・防御 −10、4 秒）。
//                                          敵ヒーロー 1 体につき自分に防御 +10 相当（被ダメ軽減）、6 秒間 S1・S2 のクールダウンが半分。
//                                          6 秒以内の再使用（同じ castSkill）で、向きへ貫通する衝撃波（ダメージ）。
//                                          奥義を習得している間は常に複合吸血（通常攻撃 10 / 20 / 30%、スキルはその半分）。
//
// 状態（KitState）:
//   timers[0] = 追撃の残り秒（>0 = 次の通常攻撃が追撃）   timers[1] = 奥義のクールダウン半減の残り秒
//   reals[0]  = S1 の着地で与えるダメージ（転がっている間だけ持つ）
//   ints[0]   = 追撃の累計回数（検証用）   ints[1] = 吸収の累計回数   ints[2] = 直近の吸収で捉えた敵ヒーローの数
//   ints[3]   = 衝撃波の累計回数          ints[4] = 地割りの着地の累計回数

extension KitState {
    var valdPursuit: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    var valdHaste: Double {
        get { timers[1] }
        set { timers[1] = newValue }
    }

    var valdSlamDamage: Double {
        get { reals[0] }
        set { reals[0] = newValue }
    }

    var valdPursuits: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    var valdAbsorbs: Int {
        get { ints[1] }
        set { ints[1] = newValue }
    }

    var valdAbsorbHeroes: Int {
        get { ints[2] }
        set { ints[2] = newValue }
    }

    var valdWaves: Int {
        get { ints[3] }
        set { ints[3] = newValue }
    }

    var valdSlams: Int {
        get { ints[4] }
        set { ints[4] = newValue }
    }
}

struct Kit_H033: HeroKit {
    let heroID = "H033"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H033(isReady: true)` を HeroKits.testOverride に差すこともできる。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    // MARK: - 数値（MLBB の値はそのまま。距離は Velstria 単位 ≈ MLBB × 100 を近接スキルの射程に合わせて調整）

    enum Tune {
        // パッシブ 追撃
        /// 追撃のダメージ（攻撃力の 140%。mlbb.io。mlbb.tools の 125% は古い値と見て採らない）。
        static let pursuitRatio = 1.4
        /// 調査に「不明」: スキルの発動から追撃を使えるまでの猶予。
        static let pursuitWindow = 5.0
        /// 追撃のために射程が伸びる量（通常攻撃 150 → 450）。踏み込める距離の目安。
        static let pursuitRangeBonus = 300.0
        static let pursuitDashSpeed = 2600.0
        /// 踏み込みで止まる位置（半径の和 + この値）。
        static let pursuitGap = 5.0
        static let pursuitRangeTag = KitTags.buff("H033", "pursuitRange")

        // 吸血（奥義のパッシブ。調査: 10% 一定 / 10・20・30% で割れている → 奥義ランクで伸びる 10 / 20 / 30% を採る）
        static let hybridLifesteal: [Double] = [0.10, 0.20, 0.30]
        /// スキルのダメージの吸血は通常攻撃の何倍か。MLBB の複合吸血は範囲スキルが 1/3、単体は等倍。
        /// Velstria のスペルヴァンプは命中した対象ごとに全量（範囲スキルで大勢に当てると回復が人数倍になる）ので、
        /// 範囲スキルの 1/3 に合わせた。S1・S2 はどちらも範囲で、ジャングルの周回での回復が過大にならない。
        static let spellVampFactor = 0.33
        static let lifestealTag = KitTags.buff("H033", "lifesteal")
        static let spellVampTag = KitTags.buff("H033", "spellVamp")
        /// 常時効果のステータスに持たせる持続（実質無期限）。
        static let permanent: Double = 1_000_000

        // S1 地割り
        /// 転がる距離の最大（調査に「不明」。近接スキルの標準 ≈ 300 に少し足した）。
        static let s1Range = 350.0
        /// 着地で叩きつける範囲の半径。
        static let s1Radius = 190.0
        static let s1Speed = 1800.0
        /// 対象を指定したときに、対象の縁の手前で止まる余裕。
        static let s1Gap = 5.0
        static let s1Slow = 0.40
        static let s1SlowDuration = 2.0
        static let s1SlowTag = KitTags.buff("H033", "slow")
        /// 汎用 S1 のダメージに対する倍率（ランク別）。Lv1〜3 はスキル1 しか無いので序盤を強く（0.88）、ランクが上がってスキル2・
        /// アルティメットが揃うほど下げる（0.64）。ランク 2 以降は予算の下限 0.8 を割るが、汎用の +30%/ランクが勝つので
        /// ダメージの絶対値はランクで増える。1.0 近くまで上げると Lv1 が +20pt 以上強く、0.70 で一律にすると Lv1 は 3% だった。
        static let s1Ratios: [Double] = [0.88, 0.78, 0.70, 0.64]

        // S2 旋回斬
        static let s2Radius = 250.0
        /// 汎用 S2 のダメージに対する倍率（予算の下限 0.8 のすぐ上）。
        static let s2Ratio = 0.81

        // 奥義 核分裂波
        /// 吸収の中心を置ける距離と、吸収の半径。
        static let ultCastRange = 450.0
        static let absorbRadius = 300.0
        static let absorbSlow = 0.30
        /// 敵の防御・魔防を下げる固定値と、鈍足・防御ダウンの持続（調査に「不明」）。
        static let absorbDefense = 10.0
        static let absorbDuration = 4.0
        /// 敵ヒーロー 1 体につき得る被ダメ軽減（防御 +10 の換算: Lv12 の防御 60 前後で約 6%）。
        static let defensePerHero = 0.05
        /// S1・S2 のクールダウンが半分になる秒数（調査: 6 秒。1v1 の総当たりで Lv6/12 が +20pt 以上強かったので 1 秒短くした）と、
        /// 再使用の窓（調査に「不明」: 6 秒を選んだ）。
        static let hasteDuration = 5.0
        static let ultWindow = 6.0
        static let hasteTag = KitTags.buff("H033", "defense")
        static let shredTag = KitTags.buff("H033", "shred")
        static let magicShredTag = KitTags.buff("H033", "magicShred")
        static let absorbSlowTag = KitTags.buff("H033", "absorbSlow")
        /// 衝撃波: 長さ・半幅・速さ（調査に「不明」。データ上の奥義の射程 600 を長い波へ伸ばした）。
        static let waveRange = 900.0
        static let waveHalfWidth = 130.0
        static let waveSpeed = 2200.0
        /// 汎用の奥義（アサシン = 対象指定の一撃 + 失った HP の 12%）に対する衝撃波のダメージ倍率。
        static let waveRatio = 0.81

        // クールダウン（MLBB 秒 → ランク間を線形補間 → 倍率）。奥義は Balance.Skills.cooldownScale（0.5）を掛ける。
        // S1・S2 の倍率は 0.5 より大きい: 奥義の「クールダウン半減」が掛かる 6 秒間だけ他のヒーローの通常のリズム（0.5 倍付近）に
        // なる、という MLBB の緩急を保つため。0.5 を掛けると半減中に S2 が 1.2 秒おきに飛び、1v1 の総当たりで 100% 勝つほど強かった
        // （docs/kits/Alucard.md の「バランス」）。S2 は MLBB の秒数の 1.2 倍（4〜6 秒 → 4.8〜7.2 秒。1.0 だと半減中に連打になり、
        // Lv6/12 で +15pt 以上強かった）。S1 はランク別（Lv1〜3 はスキル1 しか無く、奥義の半減も無いので、序盤だけ短くする。
        // ランクが上がってもクールダウンが延びないよう、倍率は秒数の減り方（8.5 → 6.5）に合わせて上げる: ランク 1〜4 で約 4.7 / 4.6 / 4.6 / 4.6 秒）。
        static let s1Cooldown = (8.5, 6.5)
        static let s1CooldownScales: [Double] = [0.55, 0.59, 0.64, 0.7]
        static let s2Cooldown = (6.0, 4.0)
        static let s2CooldownScale = 1.2
        static let ultCooldown = (40.0, 30.0)
    }

    /// KitTimer.code
    private enum Code {
        static let slam = 1
    }

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 指定地点へ転がって叩きつける（跳躍の archetype。着地の範囲は転がり終えた tick に自前で当てる）
            return SkillTargeting(archetype: .leapSlam, aim: .point, range: Tune.s1Range, radius: Tune.s1Radius,
                                  shape: .circleAtPoint)
        case .skill2:
            // 照準なしの自分中心の範囲
            return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: Tune.s2Radius, shape: .selfRing)
        case .ultimate:
            if stage >= 1 {
                // 衝撃波: 向きへ貫通する長い直線。radius は半幅
                return SkillTargeting(archetype: .piercingLine, aim: .direction, range: Tune.waveRange,
                                      radius: Tune.waveHalfWidth, shape: .wideLine, recastable: true)
            }
            // 吸収: 指定地点の範囲（地点 AoE）。radius は吸収の半径
            return SkillTargeting(archetype: .groundAoE, aim: .point, range: Tune.ultCastRange,
                                  radius: Tune.absorbRadius, shape: .circleAtPoint, recastable: true)
        case .passive:
            return base
        }
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        var n = base
        n.damageType = .physical
        switch slot {
        case .passive:
            n.damage = 0
            n.hits = 1
            n.extras = [KitStat(key: "pursuit", value: Tune.pursuitRatio * 100),
                        KitStat(key: "window", value: Tune.pursuitWindow),
                        KitStat(key: "range", value: Tune.pursuitRangeBonus),
                        KitStat(key: "lifesteal", value: (Tune.hybridLifesteal.last ?? 0) * 100)]
        case .skill1:
            n.damage = base.damage * Self.s1Ratio(rank: rank)
            n.hits = 1
            n.cc = .slow
            n.ccIsUltimate = false
            n.ccDuration = Tune.s1SlowDuration
            n.cooldown = Self.cooldown(Tune.s1Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats,
                                       scale: Self.s1CooldownScale(rank: rank))
            n.extras = [KitStat(key: "slow", value: Tune.s1Slow * 100),
                        KitStat(key: "slowDuration", value: Tune.s1SlowDuration)]
        case .skill2:
            n.damage = base.damage * Tune.s2Ratio
            n.hits = 1
            n.cc = .none
            n.ccDuration = 0
            n.cooldown = Self.cooldown(Tune.s2Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats, scale: Tune.s2CooldownScale)
        case .ultimate:
            // damage = 衝撃波のダメージ（吸収そのものにダメージは無い。説明・予算の基準として 1 回目にも載せる）
            n.damage = base.damage * Tune.waveRatio
            n.hits = 1
            n.missingHealthRatio = 0
            n.cc = stage >= 1 ? .none : .slow
            n.ccIsUltimate = false
            n.ccDuration = stage >= 1 ? 0 : Tune.absorbDuration
            n.cooldown = Self.cooldown(Tune.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.stages = 2
            n.recastWindow = Tune.ultWindow
            n.extras = [KitStat(key: "slow", value: Tune.absorbSlow * 100),
                        KitStat(key: "defense", value: Tune.absorbDefense),
                        KitStat(key: "haste", value: Tune.hasteDuration),
                        KitStat(key: "lifesteal", value: Self.lifesteal(rank: rank) * 100)]
        }
        return n
    }

    func text(slot: SkillSlot) -> KitText? {
        let debuff = String(format: "%g", Tune.absorbDuration)
        let window = String(format: "%g", Tune.ultWindow)
        let vamp = Int((Tune.spellVampFactor * 100).rounded())
        let perHero = Int((Tune.defensePerHero * 100).rounded())
        let wave = Int(Tune.waveRange)
        switch slot {
        case .passive:
            return KitText(
                ja: "スキルを発動するたび、{x1}秒以内の次の通常攻撃が「追撃」になる。追撃は射程が{x2}伸び、敵の目の前まで踏み込みながら攻撃力の{x0}%の物理ダメージを与える。"
                    + "アルティメットを習得すると、常に複合吸血を得る。通常攻撃の吸血はアルティメットのランクに応じて10 / 20 / {x3}%、スキルのダメージの吸血はその\(vamp)%。",
                en: "Each time you cast a skill, your next basic attack within {x1}s becomes a Pursuit: its range grows by {x2}, you dash right up to the target, and it deals {x0}% of attack as physical damage. "
                    + "Once you learn the ultimate you always have Hybrid Lifesteal. Basic attacks heal 10 / 20 / {x3}% by ultimate rank; skill damage heals \(vamp)% of that.")
        case .skill1:
            return KitText(
                ja: "指定した地点へ転がり込み、大剣を叩きつけて周囲{radius}の敵に{damage}ダメージ。{x0}%の鈍足を{x1}秒与える。クールダウン{cd}秒。",
                en: "Roll to the target spot and slam your blade, dealing {damage} damage to enemies within {radius} and slowing them by {x0}% for {x1}s. Cooldown {cd}s.")
        case .skill2:
            return KitText(
                ja: "その場で大剣を回転させ、周囲{radius}の敵に{damage}ダメージを与える（照準なし）。クールダウン{cd}秒。",
                en: "Spin your blade where you stand, dealing {damage} damage to enemies within {radius} (no aiming). Cooldown {cd}s.")
        case .ultimate:
            return KitText(
                ja: "吸収: 指定した地点（{range}以内）の周囲{radius}の敵のエネルギーを吸収し、\(debuff)秒間、{x0}%の鈍足と防御・魔防{x1}ダウンを与える。"
                    + "吸収した敵ヒーロー1体につき、被ダメージ軽減（約\(perHero)%）を得る。"
                    + "半減: {x2}秒間、スキル1とスキル2のクールダウンが半分になる。"
                    + "衝撃波: \(window)秒以内にもう一度使うと、向きへ長さ\(wave)の衝撃波を放ち、貫いた敵に{damage}ダメージ。"
                    + "吸血: 習得している間は常に複合吸血を得る（通常攻撃{x3}%、スキルのダメージはその\(vamp)%）。"
                    + "クールダウン{cd}秒。",
                en: "Absorb: absorb the energy of enemies within {radius} of a target spot (up to {range} away), slowing them by {x0}% and reducing their defense and magic defense by {x1} for \(debuff)s. "
                    + "You gain damage reduction (about \(perHero)%) for each enemy hero caught. "
                    + "Haste: for {x2}s, Skill 1 and Skill 2 cooldowns are halved. "
                    + "Shockwave: use again within \(window)s to release a shockwave \(wave) long that pierces enemies for {damage} damage. "
                    + "Lifesteal: while learned you always have Hybrid Lifesteal ({x3}% on basic attacks, \(vamp)% of that on skill damage). "
                    + "Cooldown {cd}s.")
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            // 追撃の準備ができている間は残り時間
            guard k.valdPursuit > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.valdPursuit, total: Tune.pursuitWindow)
        case .ultimate:
            // クールダウン半減の残り時間
            guard k.valdHaste > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.valdHaste, total: Tune.hasteDuration)
        default:
            return nil
        }
    }

    // MARK: - B. 実行

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        switch c.slot {
        case .skill1: castGroundsplitter(&s, ctx, c)
        case .skill2: castWhirlingSmash(&s, ctx, c)
        case .ultimate: castAbsorb(&s, ctx, c)
        case .passive: break
        }
        return .done
    }

    /// S1: 指定地点へ転がる。経路の敵には当たらず、転がり終えた tick に 1 度だけ範囲を叩く（onTimer）。
    private func castGroundsplitter(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let from = s.units[i].pos
        var travel = c.aim.distance
        if let u = c.aim.unit {
            // 対象を指定したときは対象の縁（自分の半径込み）の手前で止まる（中心が重ならない）
            let gap = s.units[i].radius + s.units[u].radius + Tune.s1Gap
            travel = max(0, from.distance(to: s.units[u].pos) - gap)
        }
        travel = min(Tune.s1Range, max(0, travel))
        let dir = c.aim.direction
        s.units[i].hero!.kit!.valdSlamDamage = c.numbers.damage
        // 経路上の敵には当たらない（affectsEnemies = false）。ハード CC の中断と着地の通知だけを使う
        let carrier = HitPayload(damage: 0, damageType: .physical, source: .skill(.skill1), affectsEnemies: false)
        let landing = Kit.dashSweeping(&s, ctx, caster: i, slot: .skill1, to: from + dir * travel,
                                       speed: Tune.s1Speed, payload: carrier, radius: 0, arriveCode: Code.slam)
        Kit.emitCast(&s, c, origin: from, target: landing, unit: c.aim.unit, shape: .circleAtPoint,
                     duration: from.distance(to: landing) / Tune.s1Speed, count: 1)
    }

    /// S2: 自分中心の円。即時。
    private func castWhirlingSmash(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let center = s.units[i].pos
        Kit.emitCast(&s, c, origin: center, target: center, shape: .selfRing, count: 1)
        var p = HitPayload(damage: c.numbers.damage, damageType: .physical, source: .skill(.skill2),
                           skillID: c.check.skill.skillID)
        p.originPos = center
        SkillArchetypes.hitArea(&s, ctx, caster: i, center: center, radius: Tune.s2Radius, shape: .circle, payload: p)
    }

    /// 奥義の 1 回目: 範囲の敵を吸収（鈍足・防御ダウン）。敵ヒーローの数だけ被ダメ軽減を得て、S1・S2 のクールダウンを半減させる。
    private func castAbsorb(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let id = s.units[i].id
        let center = c.aim.point
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: center, unit: c.aim.unit, shape: .circleAtPoint,
                     duration: Tune.ultWindow, count: 1)
        let skillID = c.check.skill.skillID
        let hit = Kit.hitAreaEach(&s, ctx, caster: i, center: center, radius: Tune.absorbRadius, shape: .circle) { st, j in
            // 防御は割合の防御ダウン（固定値 10 を、その時点の防御に対する割合へ換算）、魔防は固定値
            let armor = max(1, st.units[j].stats.armor)
            let statuses = [
                StatusEffect(kind: .slow, duration: Tune.absorbDuration, magnitude: Tune.absorbSlow, sourceID: id,
                             tag: Tune.absorbSlowTag),
                StatusEffect(kind: .armorShred, duration: Tune.absorbDuration,
                             magnitude: min(0.9, Tune.absorbDefense / armor), sourceID: id, tag: Tune.shredTag),
                StatusEffect(kind: .magicShred, duration: Tune.absorbDuration, magnitude: Tune.absorbDefense,
                             sourceID: id, tag: Tune.magicShredTag),
            ]
            var p = HitPayload(damage: 0, damageType: .physical, source: .skill(.ultimate), statuses: statuses,
                               skillID: skillID)
            p.originPos = center
            return p
        }
        // 無敵の相手は吸収できない（効果が入らないので数えない）
        let heroes = hit.filter { s.units[$0].kind == .hero && !CombatSystem.isInvulnerable(s, ctx, $0) }.count
        s.units[i].hero!.kit!.valdAbsorbs += 1
        s.units[i].hero!.kit!.valdAbsorbHeroes = heroes
        s.units[i].hero!.kit!.valdHaste = Tune.hasteDuration
        if heroes > 0 {
            CombatSystem.addStatus(&s, targetIndex: i,
                                   StatusEffect(kind: .damageReduction, duration: Tune.hasteDuration,
                                                magnitude: Tune.defensePerHero * Double(heroes), sourceID: id,
                                                tag: Tune.hasteTag))
        }
        Kit.openRecast(&s, caster: i, slot: .ultimate, duration: Tune.ultWindow, stage: 1, charges: 1)
    }

    /// 奥義の 2 回目（再使用）: 向きへ貫通する衝撃波。窓は閉じる（クールダウンは 1 回目で消費済み）。
    func recast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast, window: RecastWindow) {
        guard c.slot == .ultimate else {
            Kit.closeRecast(&s, ctx, caster: c.caster, slot: c.slot)
            return
        }
        let i = c.caster
        let dir = c.aim.direction
        let origin = s.units[i].pos
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * Tune.waveRange, unit: c.aim.unit, shape: .wideLine,
                     duration: Tune.waveRange / Tune.waveSpeed, count: 1)
        var p = HitPayload(damage: c.numbers.damage, damageType: .physical, source: .skill(.ultimate),
                           skillID: c.check.skill.skillID)
        p.originPos = origin
        ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: dir, maxDistance: Tune.waveRange),
                               speed: Tune.waveSpeed, width: Tune.waveHalfWidth, pierce: true, payload: p,
                               visual: c.check.skill.effectID)
        s.units[i].hero!.kit!.valdWaves += 1
        Kit.advanceRecast(&s, ctx, caster: i, slot: .ultimate)
        // 衝撃波もスキルの発動: 追撃の準備（onSkillCast は初回の発動でしか呼ばれない）
        armPursuit(&s, i)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard timer.code == Code.slam, let kit = s.units[owner].hero?.kit else { return }
        s.units[owner].hero!.kit!.valdSlamDamage = 0
        s.units[owner].hero!.kit!.valdSlams += 1
        let center = s.units[owner].pos
        let slow = StatusEffect(kind: .slow, duration: Tune.s1SlowDuration, magnitude: Tune.s1Slow,
                                sourceID: s.units[owner].id, tag: Tune.s1SlowTag)
        var p = HitPayload(damage: kit.valdSlamDamage, damageType: .physical, source: .skill(.skill1),
                           statuses: [slow], skillID: Self.skillID(ctx, .skill1))
        p.originPos = center
        SkillArchetypes.hitArea(&s, ctx, caster: owner, center: center, radius: Tune.s1Radius, shape: .circle, payload: p)
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let k = s.units[owner].hero?.kit else { return }
        syncHybridLifesteal(&s, owner)
        // 奥義の間は S1・S2 のクールダウンが半分 = 通常の経過に加えて、もう 1 tick ぶん進める
        if k.valdHaste > 0 {
            Kit.refundCooldown(&s, ctx, caster: owner, slot: .skill1, seconds: Balance.dt)
            Kit.refundCooldown(&s, ctx, caster: owner, slot: .skill2, seconds: Balance.dt)
        }
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // 転がりが止められた: 着地の処理が呼ばれないので記録を捨てる
        s.units[owner].hero?.kit?.valdSlamDamage = 0
    }

    // MARK: - C. パッシブ（追撃・複合吸血）

    func onSkillCast(_ s: inout SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) {
        armPursuit(&s, caster)
    }

    func shapeBasicAttack(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                          plan: inout BasicAttackPlan) {
        guard let k = s.units[attacker].hero?.kit, k.valdPursuit > 0 else { return }
        // 追撃は 1 回で使い切る（構造物にも消費するが、威力と踏み込みは乗らない）
        s.units[attacker].hero!.kit!.valdPursuit = 0
        s.units[attacker].statuses.removeAll { $0.kind == .attackRangeBoost && $0.tag == Tune.pursuitRangeTag }
        guard !s.units[target].isStructure else { return }
        plan.payload.damage *= Tune.pursuitRatio
        s.units[attacker].hero!.kit!.valdPursuits += 1
        // 敵の目の前まで踏み込む（ルート中は動けない。壁は手前で止まる）
        guard !s.units[attacker].has(.root) else { return }
        let from = s.units[attacker].pos
        let delta = s.units[target].pos - from
        let gap = s.units[attacker].radius + s.units[target].radius + Tune.pursuitGap
        guard delta.length > gap + 1 else { return }
        MovementSystem.dash(&s, ctx, unitIndex: attacker, to: from + delta.normalized * (delta.length - gap),
                            speed: Tune.pursuitDashSpeed, kind: .dash)
    }

    // MARK: - D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        guard slot == .ultimate else { return .useDefault }
        let pos = s.units[bot].pos
        let foe = s.units[target]
        if Kit.window(s, caster: bot, slot: .ultimate) != nil {
            // 2 回目: 衝撃波が届く距離に居れば撃つ
            guard pos.distance(to: foe.pos) <= Tune.waveRange + foe.radius else { return .skip }
            return .cast(.unit(foe.id))
        }
        // 1 回目: 交戦中に、吸収の円が敵に届くときだけ（吸収は即時なので予測は要らない）
        guard fighting, pos.distance(to: foe.pos) <= Tune.ultCastRange + Tune.absorbRadius else { return .skip }
        return .cast(.point(foe.pos))
    }

    /// ミニオン・ジャングルの集団にも裂地撃（S1）を使ってよいか。Lv1〜3 はスキル1 しか無く、通常攻撃だけではキャンプが遅いので、
    /// 転がり込んで叩きつける。HP が半分以上で、着地点が敵のタワー・コアの射程に入らないときだけ。
    func botFarm(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 center: Vec2, count: Int) -> Bool {
        guard slot == .skill1, s.units[bot].hpRatio >= 0.5 else { return false }
        for u in s.units where u.isStructure && u.isAlive && u.team != s.units[bot].team {
            let r = Balance.towerRange + Balance.heroRadius + 120
            if u.pos.distanceSquared(to: center) <= r * r { return false }
        }
        return true
    }

    // MARK: - 部品

    /// 追撃の準備（スキルを発動するたび）。射程が伸び、猶予の間だけ有効。
    private func armPursuit(_ s: inout SimState, _ i: Int) {
        guard s.units[i].hero?.kit != nil else { return }
        s.units[i].hero!.kit!.valdPursuit = Tune.pursuitWindow
        Kit.grantAttackRange(&s, target: i, amount: Tune.pursuitRangeBonus, duration: Tune.pursuitWindow,
                             tag: Tune.pursuitRangeTag)
    }

    /// 奥義を習得している間の常時効果: 複合吸血（通常攻撃の吸血 + スキルの吸血）。ランクが上がれば大きさだけ更新する。
    private func syncHybridLifesteal(_ s: inout SimState, _ i: Int) {
        let rank = min(max(0, s.units[i].hero?.rank(.ultimate) ?? 0), Tune.hybridLifesteal.count)
        let life = Self.lifesteal(rank: rank)
        sync(&s, i, kind: .lifestealBoost, tag: Tune.lifestealTag, want: life)
        sync(&s, i, kind: .spellVampBoost, tag: Tune.spellVampTag, want: life * Tune.spellVampFactor)
    }

    private func sync(_ s: inout SimState, _ i: Int, kind: StatusKind, tag: String, want: Double) {
        if let k = s.units[i].statuses.firstIndex(where: { $0.kind == kind && $0.tag == tag }) {
            if want <= 0 {
                s.units[i].statuses.remove(at: k)
            } else if s.units[i].statuses[k].magnitude != want {
                s.units[i].statuses[k].magnitude = want
            }
        } else if want > 0 {
            switch kind {
            case .lifestealBoost: Kit.grantLifesteal(&s, target: i, ratio: want, duration: Tune.permanent, tag: tag)
            default: Kit.grantSpellVamp(&s, target: i, ratio: want, duration: Tune.permanent, tag: tag)
            }
        }
    }

    /// S1 のダメージ倍率（ランク別）。
    static func s1Ratio(rank: Int) -> Double {
        Tune.s1Ratios[min(max(1, rank), Tune.s1Ratios.count) - 1]
    }

    /// S1 のクールダウン倍率（ランク別: 序盤ほど短い）。
    static func s1CooldownScale(rank: Int) -> Double {
        Tune.s1CooldownScales[min(max(1, rank), Tune.s1CooldownScales.count) - 1]
    }

    /// 奥義ランク（0 = 未習得）に応じた通常攻撃の吸血率。
    static func lifesteal(rank: Int) -> Double {
        guard rank > 0 else { return 0 }
        return Tune.hybridLifesteal[min(rank, Tune.hybridLifesteal.count) - 1]
    }

    /// MLBB のクールダウン（秒）をランクで線形補間し、倍率と CD 短縮を掛ける。
    /// scale は全体倍率（既定は Balance.Skills.cooldownScale）。
    static func cooldown(_ range: (Double, Double), rank: Int, maxRank: Int, stats: Stats,
                         scale: Double = Balance.Skills.cooldownScale) -> Double {
        let sec: Double
        if maxRank > 1 {
            let t = Double(min(max(1, rank), maxRank) - 1) / Double(maxRank - 1)
            sec = range.0 + (range.1 - range.0) * t
        } else {
            sec = range.0
        }
        let reduction = min(Balance.maxCooldownReduction, max(0, stats.cooldownReduction))
        return sec * (1 - reduction) * scale
    }

    static func skillID(_ ctx: SimContext, _ slot: SkillSlot) -> String? {
        ctx.master.skill(hero: "H033", slot: slot)?.skillID
    }
}
