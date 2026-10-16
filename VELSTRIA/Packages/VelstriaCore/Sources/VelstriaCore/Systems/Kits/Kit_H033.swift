import Foundation

// 担当: kit-H033（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Alucard.md）
// H033 紅牙のヴァルド = Velstria 版の Alucard（MLBB。調査: docs/kits/Alucard.md、対応表: 同ファイル末尾）。
// 数値の正は MLBB の日本語クライアントのスキル詳細（docs/kits/Alucard.md の「日本語クライアントの画面」）。Liquipedia の表とも一致する。
// アサシン（ジャングル）の近接。キットはロールの汎用パッシブ（奇襲 +30% とキル/アシストの全 CD −30%）を置き換える。
// 公式はスキルにコストが無い（HeroKit.cost で 0）。
//   パッシブ 追撃（チェイス）           — スキルを発動するたび、4 秒以内の次の通常攻撃が「追撃」になる: 射程 400（公式 4）まで伸び、
//                                          敵の目の前まで毎秒 1070 で踏み込みながら (125% 物理攻撃) = 合計の物理攻撃の 125% の物理ダメージ。
//                                          デビルハンター: モンスターへのダメージは 110%（通常攻撃・スキルすべて。HitPayload.monsterMultiplier）。
//   S1   裂地撃（グランドスプリッター） — 指定した地点（最大 420）へ毎秒 1250 で跳び込み、着地の周り 190 に大剣を叩きつける。
//                                          270〜370（+85% 追加物理攻撃）+ 鈍足 40%（2 秒）。ボットはミニオン・ジャングルにも使う（botFarm）。
//   S2   旋回斬（サークルスマッシュ）   — その場で大剣を回転させ、周囲 250 の敵に 345〜570（+120% 追加物理攻撃）（照準なし）。
//   奥義 核分裂波（フィッションウェーブ） — 1 回目: 向きへ術者から 640・半幅 150 の帯の敵のエネルギーを吸収（鈍足 30%・混合防御 −10 / 15 / 20、6 秒）。
//                                          敵ヒーロー 1 体につき自分に混合防御 +10 / 15 / 20、6 秒間 S1・S2 の CD が 50%。
//                                          6 秒以内の再使用（同じ castSkill）で、0.16 秒の振りかぶりの後に向きへ貫通する衝撃波
//                                          （届く距離 640・半幅 165・毎秒 1000）400 / 550 / 700（+200% 追加物理攻撃）。
//                                          奥義を習得している間は常に混合吸収 10 / 20 / 30%（通常攻撃吸収とスキル吸収の両方に同じ値）。
// 幾何と時間は MLBB の訓練場の画面収録で測った値（docs/kits/Alucard.md「動画で測った値（2026-10-16）」）。
// 数値: 公式の表をそのまま使う（S1・S2 = Lv1〜6、奥義 = Lv1〜3。rank = 公式の Lv。Kit.level / Kit.official / Kit.cooldown）。
//   ダメージ = 公式の基礎 + 公式の係数 × 能力値（(+N%追加) = 追加物理攻撃 Stats.extraAttack、(125%) = 合計の物理攻撃）。換算・補間なし。
//
// 状態（KitState）:
//   timers[0] = 追撃の残り秒（>0 = 次の通常攻撃が追撃）   timers[1] = 奥義のクールダウン半減の残り秒
//   reals[0]  = S1 の着地で与えるダメージ（転がっている間だけ持つ）
//   ints[0]   = 追撃の累計回数（検証用）   ints[1] = 吸収の累計回数   ints[2] = 直近の吸収で捉えた敵ヒーローの数
//   ints[3]   = 衝撃波の累計回数（波が出た数）   ints[4] = 地割りの着地の累計回数
//   scheduled = 衝撃波の振りかぶり（Code.wave。point = 向き、param = ダメージ）

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

    // MARK: - 数値（公式の表はそのまま。距離・時間は公式に記載が無いので MLBB の画面収録で測った値: docs/kits/Alucard.md）

    enum Tune {
        // パッシブ 追撃（チェイス）
        /// 追撃のダメージ（公式「(125% 物理攻撃) の物理ダメージ」= 合計の物理攻撃の 125%。日本語クライアント・Liquipedia）。
        /// 通常攻撃（物理攻撃 × 会心の倍率）に掛ける。
        static let pursuitRatio = 1.25
        /// スキルの発動から追撃を使えるまでの猶予（公式に記載なし）。動画: 追撃のバフのアイコンの時計回りの減り方が 1 周 3.7〜4.2 秒
        /// （長い 2 回。同じ当てはめで 6.1 秒の奥義のアイコンは 5.7〜5.9 秒と 4〜7% 短く出るので 3.9〜4.4 秒）。切れるところは映っていない。
        /// 以前は 5 秒の推測。
        static let pursuitWindow = 4.0
        /// 追撃のために射程が伸びる量。通常攻撃 180（公式 1.8）+ 220 = 400。動画: 追撃の準備中に足元に出る円 3.96（通常攻撃の円 1.78 と同じ −1%
        /// の縮尺で公式の 4）。Fandom の強化通常攻撃の射程 4 とも合う（以前の +250 は通常攻撃 150 の頃の値で 430 になっていた）。
        static let pursuitRangeBonus = 220.0
        /// 踏み込みの速さ。動画: 止まった的の体力バーで 1 コマ 0.355〜0.365 = 毎秒 10.6〜11.0（3 回。以前は 2600 の推測）。
        static let pursuitDashSpeed = 1070.0
        /// 踏み込みで止まる位置（半径の和 + この値）。
        static let pursuitGap = 5.0
        static let pursuitRangeTag = KitTags.buff("H033", "pursuitRange")
        /// デビルハンター（パッシブ。日本語クライアント「モンスターに対して 110% のダメージを与える」。Liquipedia「Creeps に 10% の追加ダメージ」）:
        /// モンスター（ジャングル・バフ・亀・ロード = `UnitKind.monster`）への、ヴァルド自身の通常攻撃とスキルのダメージを 110% にする
        /// （HitPayload.monsterMultiplier。掛け算で、ほかの与ダメ補正とは足し合わせない。MLBB での重なり方は未確認）。
        /// 文は追撃の文とは別の行で、追撃に限らない。ミニオン・ヒーロー・構造物・バトルスペル・装備の追加ダメージには掛からない。
        static let devilHunter = 1.10

        // 混合吸収（奥義のパッシブ。公式 10 / 20 / 30%。日本語クライアントの表「混合吸収」）
        /// 通常攻撃吸収（lifestealBoost）とスキル吸収（spellVampBoost）に同じ値を足す（用語説明「混合吸収 = 通常攻撃吸収 + スキル吸収」）。
        /// スキルごとのスキル吸収率は、日本語クライアントのスキル詳細に記載が無いので既定の 100%（HitPayload.spellVampRatio = 1）。
        static let hybridLifesteal: [Double] = [0.10, 0.20, 0.30]
        static let lifestealTag = KitTags.buff("H033", "lifesteal")
        static let spellVampTag = KitTags.buff("H033", "spellVamp")
        /// 常時効果のステータスに持たせる持続（実質無期限）。
        static let permanent: Double = 1_000_000

        // S1 地割り（グランドスプリッター）
        /// 跳び込む距離の最大（公式に記載なし）。動画: 照準の円 4.16、射程いっぱいの 2 回の跳躍 4.20 / 4.16〜4.19（着地の円の中心 4.20 / 4.19）。
        static let s1Range = 420.0
        /// 着地で叩きつける範囲の半径（公式に記載なし）。動画: 着地点の照準の円 1.905（2 回・放射ごとに ±0.01）。
        static let s1Radius = 190.0
        /// 跳躍の速さ。動画: 指を離した次のコマから 10.3〜10.7 コマ（0.34〜0.36 秒）で 4.2、止まった的の体力バーで 1 コマ 0.41〜0.43
        /// = 毎秒 12.2〜12.8（以前は 1800 の推測）。
        static let s1Speed = 1250.0
        /// 対象を指定したときに、対象の縁の手前で止まる余裕。
        static let s1Gap = 5.0
        /// 公式: 移動速度を 2 秒間 40% 低下。動画: 的のパネルの移動速度 265 → 159（−40%）が 63〜64 コマ（2.1 秒）。
        static let s1Slow = 0.40
        static let s1SlowDuration = 2.0
        static let s1SlowTag = KitTags.buff("H033", "slow")
        /// 公式: 基礎ダメージ 270 / 290 / 310 / 330 / 350 / 370（+85% 追加物理攻撃）。
        static let s1Base: [Double] = [270, 290, 310, 330, 350, 370]
        static let s1ExtraAttackRatio = 0.85
        /// 公式: CD 8.5 / 8.1 / 7.7 / 7.3 / 6.9 / 6.5 秒。
        static let s1Cooldown: [Double] = [8.5, 8.1, 7.7, 7.3, 6.9, 6.5]

        // S2 旋回斬（サークルスマッシュ）
        /// 回転斬りの半径（公式に記載なし）。動画: 照準の円 2.469 ± 0.010（2 組のコマ。通常攻撃の円 1.775 = 公式 1.8 の −1.4% と同じ縮みで 2.5）。
        /// 命中は指を離してから 2 コマ（光る）・3 コマ（数字）で、発動の印（追撃のアイコン）と同じ頃 = 即時のまま。
        static let s2Radius = 250.0
        /// 公式: 基礎ダメージ 345 / 390 / 435 / 480 / 525 / 570（+120% 追加物理攻撃）。
        static let s2Base: [Double] = [345, 390, 435, 480, 525, 570]
        static let s2ExtraAttackRatio = 1.2
        /// 公式: CD 6.0 / 5.6 / 5.2 / 4.8 / 4.4 / 4.0 秒。
        static let s2Cooldown: [Double] = [6.0, 5.6, 5.2, 4.8, 4.4, 4.0]

        // 奥義 核分裂波（フィッションウェーブ）
        /// 吸収の範囲: 向きへ術者から伸びる帯（公式は「指定範囲」。照準は地点の円ではなく、衝撃波と同じ形の向きの帯）。
        /// 動画: 照準の帯の左右の線 ±1.45〜1.49（2 回の照準・9 コマ）、先は三日月形で中央 6.0〜6.4・端 5.4、外の円 6.44。
        /// 吸収されたのは帯の中の的だけ（術者から 4.4 の帯の外の的は 1 回目も 2 回目も吸収されない）。
        /// sim は術者 → 向きの線分（長さ absorbLength）から半幅 absorbHalfWidth の内側（端は丸い）。中央の先端 = absorbReach。
        static let absorbReach = 640.0
        static let absorbHalfWidth = 150.0
        static var absorbLength: Double { absorbReach - absorbHalfWidth }
        /// 公式: 移動速度 −30%。動画: 的のパネル 265 → 185。
        static let absorbSlow = 0.30
        /// 公式: 敵の混合防御（物理防御・魔法防御）を下げる固定値 10 / 15 / 20（表「混合防御減少」）。動画（Lv3）: パネルの物理防御・魔法防御 −20。
        static let absorbDefense: [Double] = [10, 15, 20]
        /// 鈍足・防御ダウンの持続（公式に記載なし）。動画: 吸収のコマから 183 コマ（6.1 秒）でパネルが −20 / 185 → 0 / 265 に戻る
        /// （術者の体力バーの奥義の印と同じコマで消える。以前は 4 秒の推測）。
        static let absorbDuration = 6.0
        /// 公式: 敵ヒーロー 1 体につき自分が得る混合防御 10 / 15 / 20（表「混合防御力増加」。`flatDefenseMod`、hasteDuration の間）。
        static let defensePerHero: [Double] = [10, 15, 20]
        /// 公式: 6 秒間、他のスキルの CD 時間が 50% に短縮。動画: 術者の体力バーの奥義の印 183 コマ（6.1 秒）。
        static let hasteDuration = 6.0
        /// 再使用の窓（公式に記載なし）。動画: 再使用は吸収から 2.27 / 2.40 秒（窓の終わりは映っていない）。奥義のボタンの輪の減り方は
        /// 1 周 6〜7 秒の見当（目で読んだ角度）で、6 秒のまま。
        static let ultWindow = 6.0
        static let hasteTag = KitTags.buff("H033", "defense")
        static let shredTag = KitTags.buff("H033", "shred")
        static let absorbSlowTag = KitTags.buff("H033", "absorbSlow")
        /// 衝撃波の届く距離（中央の先端）・半幅・速さ（公式に記載なし）。動画: 照準の帯 ±1.64〜1.69、外の円 6.44・矢印の先 6.3、
        /// 波は 6.4 前後で消える。命中は再使用の指を離してから、隣の的 5.5 コマ・術者から 4.2 の的 11.5 コマ・5.5 の的 15.5 コマ
        /// （再使用の 5.5 コマ後に波が術者の前に出て毎秒 10 前後で進む）。以前は 900・半幅 130・毎秒 2200 の推測。
        static let waveReach = 640.0
        static let waveHalfWidth = 165.0
        static let waveSpeed = 1000.0
        /// 弾の進む距離（弾の当たりは中心から半幅 + 対象の半径なので、届く距離 − 半幅）。
        static var waveTravel: Double { waveReach - waveHalfWidth }
        /// 再使用から波が出るまで（振りかぶり。動画: 指を離してから 5〜6 コマで隣の的に当たり、追撃のアイコンが出る。sim の 5 tick）。
        /// この間にスタン以上を受けると波は出ない（予約は interruptible。窓は閉じたまま。CD は 1 回目で消費済み）。
        static let waveDelay = 0.16
        /// 公式: 衝撃波の基礎ダメージ 400 / 550 / 700（+200% 追加物理攻撃）。
        static let waveBase: [Double] = [400, 550, 700]
        static let waveExtraAttackRatio = 2.0
        /// 公式: CD 40 / 35 / 30 秒（最初の発動で消費。再使用では変わらない）。
        static let ultCooldown: [Double] = [40, 35, 30]
    }

    /// KitTimer.code
    private enum Code {
        static let slam = 1
        /// 衝撃波の振りかぶりの終わり（波が出る）。
        static let wave = 2
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
                // 衝撃波: 向きへ貫通する直線。range は届く距離（中央の先端）、radius は半幅
                return SkillTargeting(archetype: .piercingLine, aim: .direction, range: Tune.waveReach,
                                      radius: Tune.waveHalfWidth, shape: .wideLine, recastable: true)
            }
            // 吸収: 向きの帯（MLBB の照準も衝撃波と同じ向きの帯）。range は届く距離（中央の先端）、radius は半幅。
            // 弾は出さない（即時。cast が自前で当てる）。archetype は届き方（reach = range）と照準の見せ方のため
            return SkillTargeting(archetype: .piercingLine, aim: .direction, range: Tune.absorbReach,
                                  radius: Tune.absorbHalfWidth, shape: .wideLine, recastable: true)
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
                        KitStat(key: "reachMult", value: (hero.attackRange + Tune.pursuitRangeBonus) / hero.attackRange),
                        KitStat(key: "devilHunter", value: (Tune.devilHunter * 100).rounded())]
        case .skill1:
            n.damage = Self.s1Damage(rank: rank, stats: stats)
            n.hits = 1
            n.cc = .slow
            n.ccIsUltimate = false
            n.ccDuration = Tune.s1SlowDuration
            n.cooldown = Kit.cooldown(Tune.s1Cooldown, rank: rank, stats: stats)
            n.extras = [KitStat(key: "slow", value: Tune.s1Slow * 100),
                        KitStat(key: "slowDuration", value: Tune.s1SlowDuration),
                        KitStat(key: "base", value: Kit.level(Tune.s1Base, rank: rank)),
                        KitStat(key: "atkPct", value: Tune.s1ExtraAttackRatio * 100)]
        case .skill2:
            n.damage = Self.s2Damage(rank: rank, stats: stats)
            n.hits = 1
            n.cc = .none
            n.ccDuration = 0
            n.cooldown = Kit.cooldown(Tune.s2Cooldown, rank: rank, stats: stats)
            n.extras = [KitStat(key: "base", value: Kit.level(Tune.s2Base, rank: rank)),
                        KitStat(key: "atkPct", value: Tune.s2ExtraAttackRatio * 100)]
        case .ultimate:
            // damage = 衝撃波のダメージ（吸収そのものにダメージは無い。説明・ボットの判断の基準として 1 回目にも載せる）
            n.damage = Self.waveDamage(rank: rank, stats: stats)
            n.hits = 1
            n.missingHealthRatio = 0
            n.cc = stage >= 1 ? .none : .slow
            n.ccIsUltimate = false
            n.ccDuration = stage >= 1 ? 0 : Tune.absorbDuration
            n.cooldown = Kit.cooldown(Tune.ultCooldown, rank: rank, stats: stats)
            n.stages = 2
            n.recastWindow = Tune.ultWindow
            n.extras = [KitStat(key: "slow", value: Tune.absorbSlow * 100),
                        KitStat(key: "defense", value: Self.absorbDefense(rank: rank)),
                        KitStat(key: "haste", value: Tune.hasteDuration),
                        KitStat(key: "lifesteal", value: Self.lifesteal(rank: max(1, rank)) * 100),
                        KitStat(key: "gain", value: Self.defensePerHero(rank: rank)),
                        KitStat(key: "debuff", value: Tune.absorbDuration),
                        KitStat(key: "window", value: Tune.ultWindow),
                        KitStat(key: "base", value: Kit.level(Tune.waveBase, rank: rank)),
                        KitStat(key: "atkPct", value: Tune.waveExtraAttackRatio * 100)]
        }
        return n
    }

    /// 公式はスキルにコストが無い（MLBB の Alucard は資源を持たない。master の resource は None でリソースのバーも無い）。
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double {
        slot == .passive ? base : 0
    }

    /// 説明文は日本語クライアントの文に合わせる（数値は {トークン} で sim から。{base}(+{atkPct}%追加物理攻撃) は公式の値そのもの）。
    /// 公式の文に無いのは、追撃の猶予・射程、吸収の持続、再使用の窓（どれも公式に記載が無く、選んだ値を括弧・前置きで書く）。
    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "スキルを発動するたびに、次の通常攻撃（{window}秒以内。射程は近接攻撃の約{reachMult}倍）で対象へダッシュし、({pursuit}%物理攻撃)の物理ダメージを与える。"
                    + "\n\nデビルハンター：モンスターに対して{devilHunter}%のダメージを与える。",
                en: "After each skill cast, Vald's next basic attack (within {window}s, reaching about {reachMult}x the melee attack range) lets him dash to the target and deal ({pursuit}% Physical Attack) physical damage."
                    + "\n\nDevil Hunter: Vald deals {devilHunter}% damage to monsters.",
                tags: [KitTag.buff])
        case .skill1:
            return KitText(
                ja: "指定エリアへ跳躍して斬りつけ、範囲内の敵に{base}(+{atkPct}%追加物理攻撃)の物理ダメージを与え、移動速度を{slowDuration}秒間{slow}%低下させる。",
                en: "Leap to the target area and slash, dealing {base} (+{atkPct}% Extra Physical Attack) physical damage to enemies in the area and slowing them by {slow}% for {slowDuration}s.",
                tags: [KitTag.mobility, KitTag.aoe])
        case .skill2:
            return KitText(
                ja: "回転斬りを放ち、周囲の敵に{base}(+{atkPct}%追加物理攻撃)の物理ダメージを与える。",
                en: "Launch a whirling slash, dealing {base} (+{atkPct}% Extra Physical Attack) physical damage to nearby enemies.",
                tags: [KitTag.aoe])
        case .ultimate:
            return KitText(
                ja: "パッシブ：混合吸収が永久に{lifesteal}%上昇する。\n\n"
                    + "アクティブ：指定範囲内の敵のエネルギーを吸収し、{debuff}秒間 移動速度を{slow}%、混合防御を{defense}低下させる。命中した敵ヒーロー1体につき自身の混合防御が{gain}上昇し、{haste}秒間、他のスキルのCD時間が50%に短縮される。\n\n"
                    + "再発動：{window}秒以内に、前方に強力な衝撃波を放ち、{base}(+{atkPct}%追加物理攻撃)の物理ダメージを与える。",
                en: "Passive: Vald permanently gains {lifesteal}% Hybrid Lifesteal.\n\n"
                    + "Active: absorb the energy of enemies in the target area, reducing their Movement Speed by {slow}% and Hybrid Defense by {defense} for {debuff}s. Vald gains {gain} Hybrid Defense for each enemy hero hit, and the cooldowns of his other skills are reduced to 50% for {haste}s.\n\n"
                    + "Use Again: within {window}s, release a powerful shockwave forward, dealing {base} (+{atkPct}% Extra Physical Attack) physical damage.",
                tags: [KitTag.buff, KitTag.burst])
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
    /// 転がり（突進）はノックアップ・制圧でだけ止まる（スタンでは止まらず、着地で叩きつける。CrowdControlTier）。
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
        // 経路上の敵には当たらない（affectsEnemies = false）。突進の中断と着地の通知だけを使う
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
                           skillID: c.check.skill.skillID, monsterMultiplier: Tune.devilHunter)
        p.originPos = center
        SkillArchetypes.hitArea(&s, ctx, caster: i, center: center, radius: Tune.s2Radius, shape: .circle, payload: p)
    }

    /// 奥義の 1 回目: 向きの帯（術者から absorbReach・半幅 absorbHalfWidth）の敵を吸収（鈍足・防御ダウン）。即時。
    /// 敵ヒーローの数だけ混合防御を得て、S1・S2 のクールダウンを半減させる。
    private func castAbsorb(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let id = s.units[i].id
        let origin = s.units[i].pos
        let dir = c.aim.direction
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * Tune.absorbReach, unit: c.aim.unit, shape: .wideLine,
                     duration: Tune.ultWindow, count: 1)
        let skillID = c.check.skill.skillID
        let rank = c.numbers.rank
        let shred = Self.absorbDefense(rank: rank)
        let band = ZoneShape.line(direction: dir, length: Tune.absorbLength)
        let hit = Kit.hitAreaEach(&s, ctx, caster: i, center: origin, radius: Tune.absorbHalfWidth, shape: band) { _, _ in
            // 混合防御（物理防御と魔法防御）を固定値で下げる（公式 10 / 15 / 20）
            let statuses = [
                StatusEffect(kind: .slow, duration: Tune.absorbDuration, magnitude: Tune.absorbSlow, sourceID: id,
                             tag: Tune.absorbSlowTag),
                StatusEffect(kind: .flatDefenseMod, duration: Tune.absorbDuration, magnitude: -shred, sourceID: id,
                             tag: Tune.shredTag),
            ]
            var p = HitPayload(damage: 0, damageType: .physical, source: .skill(.ultimate), statuses: statuses,
                               skillID: skillID)
            p.originPos = origin
            return p
        }
        // 無敵の相手は吸収できない（効果が入らないので数えない）
        let heroes = hit.filter { s.units[$0].kind == .hero && !CombatSystem.isInvulnerable(s, ctx, $0) }.count
        s.units[i].hero!.kit!.valdAbsorbs += 1
        s.units[i].hero!.kit!.valdAbsorbHeroes = heroes
        s.units[i].hero!.kit!.valdHaste = Tune.hasteDuration
        if heroes > 0 {
            // 敵ヒーロー 1 体につき混合防御 +10 / 15 / 20（公式。hasteDuration の間）
            CombatSystem.addStatus(&s, targetIndex: i,
                                   StatusEffect(kind: .flatDefenseMod, duration: Tune.hasteDuration,
                                                magnitude: Self.defensePerHero(rank: rank) * Double(heroes), sourceID: id,
                                                tag: Tune.hasteTag))
        }
        Kit.openRecast(&s, caster: i, slot: .ultimate, duration: Tune.ultWindow, stage: 1, charges: 1)
    }

    /// 奥義の 2 回目（再使用）: 振りかぶり（waveDelay）の後に、向きへ貫通する衝撃波（onTimer の Code.wave）。
    /// 窓はここで閉じる（クールダウンは 1 回目で消費済み）。
    func recast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast, window: RecastWindow) {
        guard c.slot == .ultimate else {
            Kit.closeRecast(&s, ctx, caster: c.caster, slot: c.slot)
            return
        }
        let i = c.caster
        let dir = c.aim.direction
        let origin = s.units[i].pos
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * Tune.waveReach, unit: c.aim.unit, shape: .wideLine,
                     duration: Tune.waveDelay + Tune.waveTravel / Tune.waveSpeed, count: 1)
        Kit.schedule(&s, caster: i, slot: .ultimate, code: Code.wave, after: Tune.waveDelay, param: c.numbers.damage,
                     point: dir, interruptible: true)
        Kit.advanceRecast(&s, ctx, caster: i, slot: .ultimate)
    }

    /// 衝撃波が出る（振りかぶりの終わり）: 今の位置から、再使用の時の向きへ。衝撃波もスキルの発動なので追撃を準備する
    /// （onSkillCast は初回の発動でしか呼ばれない。動画も追撃のアイコンは波が出る頃に付く）。
    private func launchWave(_ s: inout SimState, _ ctx: SimContext, owner i: Int, timer: KitTimer) {
        let dir = timer.point.normalized
        guard dir != .zero, s.units[i].hero?.kit != nil else { return }
        let skill = ctx.master.skill(hero: heroID, slot: .ultimate)
        var p = HitPayload(damage: timer.param, damageType: .physical, source: .skill(.ultimate),
                           skillID: skill?.skillID, monsterMultiplier: Tune.devilHunter)
        p.originPos = s.units[i].pos
        ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: dir, maxDistance: Tune.waveTravel),
                               speed: Tune.waveSpeed, width: Tune.waveHalfWidth, pierce: true, payload: p,
                               visual: skill?.effectID ?? "")
        s.units[i].hero!.kit!.valdWaves += 1
        armPursuit(&s, i)
    }

    /// 衝撃波の振りかぶりの間は、次のスキルを始められない（MLBB の発動の動作の間。動画で術者は 8〜9 コマ止まる）。
    func canStart(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) -> Bool {
        guard let k = s.units[caster].hero?.kit else { return true }
        return !k.scheduled.contains { $0.code == Code.wave }
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        if timer.code == Code.wave {
            launchWave(&s, ctx, owner: owner, timer: timer)
            return
        }
        guard timer.code == Code.slam, let kit = s.units[owner].hero?.kit else { return }
        s.units[owner].hero!.kit!.valdSlamDamage = 0
        s.units[owner].hero!.kit!.valdSlams += 1
        let center = s.units[owner].pos
        let slow = StatusEffect(kind: .slow, duration: Tune.s1SlowDuration, magnitude: Tune.s1Slow,
                                sourceID: s.units[owner].id, tag: Tune.s1SlowTag)
        var p = HitPayload(damage: kit.valdSlamDamage, damageType: .physical, source: .skill(.skill1),
                           statuses: [slow], skillID: Self.skillID(ctx, .skill1), monsterMultiplier: Tune.devilHunter)
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
        // 転がりが止められた（ノックアップ・制圧・ノックバック）: 着地の処理が呼ばれないので記録を捨てる
        s.units[owner].hero?.kit?.valdSlamDamage = 0
    }

    // MARK: - C. パッシブ（追撃・デビルハンター・混合吸収）

    func onSkillCast(_ s: inout SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) {
        armPursuit(&s, caster)
    }

    /// 通常攻撃: デビルハンター（モンスターに 110%）はすべての通常攻撃に、追撃（125%・踏み込み）は準備があるときの 1 回に。
    func shapeBasicAttack(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                          plan: inout BasicAttackPlan) {
        plan.payload.monsterMultiplier = Tune.devilHunter
        guard let k = s.units[attacker].hero?.kit, k.valdPursuit > 0 else { return }
        // 追撃は 1 回で使い切る（構造物にも消費するが、威力と踏み込みは乗らない）
        s.units[attacker].hero!.kit!.valdPursuit = 0
        s.units[attacker].statuses.removeAll { $0.kind == .attackRangeBoost && $0.tag == Tune.pursuitRangeTag }
        guard !s.units[target].isStructure else { return }
        plan.payload.damage *= Tune.pursuitRatio
        s.units[attacker].hero!.kit!.valdPursuits += 1
        // 敵の目の前まで踏み込む（ルート中は動けない。壁は手前で止まる）。ダメージは発射の tick に出る
        // （動画はダメージが踏み込みの終わり。到着まで待つのは見送り: docs/kits/Alucard.md）
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
            guard pos.distance(to: foe.pos) <= Tune.waveReach + foe.radius else { return .skip }
            return .cast(.unit(foe.id))
        }
        // 1 回目: 交戦中に、吸収の帯が敵に届くときだけ敵へ向けて撃つ（吸収は即時なので予測は要らない）
        guard fighting, pos.distance(to: foe.pos) <= Tune.absorbReach + foe.radius else { return .skip }
        return .cast(.unit(foe.id))
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

    /// 奥義を習得している間の常時効果: 混合吸収（通常攻撃吸収 + スキル吸収に同じ値）。ランクが上がれば大きさだけ更新する。
    private func syncHybridLifesteal(_ s: inout SimState, _ i: Int) {
        let life = Self.lifesteal(rank: s.units[i].hero?.rank(.ultimate) ?? 0)
        sync(&s, i, kind: .lifestealBoost, tag: Tune.lifestealTag, want: life)
        sync(&s, i, kind: .spellVampBoost, tag: Tune.spellVampTag, want: life)
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

    // MARK: - ダメージ（公式の式: 基礎[段] + 係数 × 追加物理攻撃）

    /// S1 の叩きつけ: 270〜370 (+85% 追加物理攻撃)。
    static func s1Damage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.s1Base, rank: rank, ratio: Tune.s1ExtraAttackRatio, .extraAttack, stats: stats)
    }

    /// S2 の回転斬り: 345〜570 (+120% 追加物理攻撃)。
    static func s2Damage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.s2Base, rank: rank, ratio: Tune.s2ExtraAttackRatio, .extraAttack, stats: stats)
    }

    /// 奥義の衝撃波: 400 / 550 / 700 (+200% 追加物理攻撃)。
    static func waveDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.waveBase, rank: rank, ratio: Tune.waveExtraAttackRatio, .extraAttack, stats: stats)
    }

    /// 吸収で敵の混合防御を下げる量（10 / 15 / 20）と、敵ヒーロー 1 体につき自分が得る混合防御（10 / 15 / 20）。
    static func absorbDefense(rank: Int) -> Double {
        Kit.level(Tune.absorbDefense, rank: rank)
    }

    static func defensePerHero(rank: Int) -> Double {
        Kit.level(Tune.defensePerHero, rank: rank)
    }

    /// 奥義ランク（0 = 未習得）に応じた混合吸収（通常攻撃吸収とスキル吸収に同じ値）。
    static func lifesteal(rank: Int) -> Double {
        guard rank > 0 else { return 0 }
        return Kit.level(Tune.hybridLifesteal, rank: rank)
    }

    static func skillID(_ ctx: SimContext, _ slot: SkillSlot) -> String? {
        ctx.master.skill(hero: "H033", slot: slot)?.skillID
    }
}
