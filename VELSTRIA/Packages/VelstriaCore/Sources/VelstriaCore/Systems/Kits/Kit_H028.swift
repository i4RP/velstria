import Foundation

// 担当: kit-H028（docs/SKILL_KITS.md / docs/NEW_HEROES.md）
// H028 断空のザイル = Velstria 版の Saber（MLBB。調査: docs/kits/Saber.md、対応表: 同ファイル末尾）。
// 数値の正は MLBB の日本語クライアントのスキル詳細（docs/kits/Saber.md の「公式（日本語クライアント）の数値」。Fandom と違うところはこちらが優先）。
// アサシン（近接 180・Mana。MLBB の値。2026-10-14 に 150・Energy から直した）。キットはロールの汎用パッシブ（奇襲ボーナス・キル/アシストの全 CD 短縮）を置き換える。
//   パッシブ 空断の理（Enemy's Bane）— ダメージを与えるたび（通常攻撃・スキル）に相手の物理防御を固定値で下げる。5 層・5 秒、
//                                      1 層あたり 3〜8（日本語クライアントは範囲だけ。レベル別の表は Fandom の現行: Lv1〜3 = 3、…、Lv15 = 8）。
//   S1   環剣（Flying Sword）        — 5 本の剣が 4.8 秒間 術者から 385 の輪を回り、輪の帯（325〜445）に触れた敵に 75〜125（+25% 追加物理攻撃）の
//                                      接触ダメージ（0.48 秒ごと。術者のすぐそばの敵には触れない）。
//                                      周回中に通常攻撃/スキルでダメージを与えるたび、剣が対象へ飛んで「剣撃」200〜300（+50% 追加）
//                                      （進路上の他の敵には 50%、ミニオンへは 50%）+ スキル1 のクールダウン −0.5 秒・スキル2 −1 秒。
//   S2   断空突進（Assault）         — 指定方向へ 300 を毎秒 1500 で突進して通り道の敵に 75〜150（+50% 追加）。次の通常攻撃が強化
//                                      （75〜150 + 物理攻撃 120%、鈍足 60%・1 秒、射程 250）。
//   奥義 三連断空（Triple Slash）     — 対象指定（敵ヒーロー、縁まで 545）。毎秒 1700 で突進して 1.2 秒打ち上げ（強靭 = CC 短縮の影響を受けない）、
//                                      到着の瞬間・0.39 秒・0.78 秒に 3 連撃（120 / 170 / 220（+80% 追加）× 2 + 240 / 340 / 440（+160% 追加））、
//                                      術者は到着から 1.0 秒動けない。最初の 2 撃には S1 の剣撃が乗る（3 撃目は乗らない）。
//                                      突進はノックアップ・制圧で止まり、打ち上げたあとの連撃は制圧（suppress）でのみ中断される。
// 幾何と時間（剣の輪・回る速さ・剣が出ている秒数・剣撃の遅れ・S2 の射程と速さ・奥義の射程・速さ・3 撃の時刻・術者の硬直）は
// 2026-10-16 に MLBB の訓練場の画面収録で測った値（docs/kits/Saber.md「動画で測った値（2026-10-16）」）。ダメージ・係数・CD・MP は公式の表のまま。
// 数値: 公式の表をそのまま使う（スキル1・2 = Lv1〜6、奥義 = Lv1〜3。ランク = 公式の Lv。換算・補間・全体の倍率なし）。
//   ダメージ = 基礎[Lv] + 係数 × 能力値（`Kit.official`）。「追加物理攻撃」の係数は Stats.extraAttack（装備・エンブレム・バフで増えた分）、
//   強化通常攻撃の 120% だけは合計の物理攻撃（公式の「物理攻撃」）。追加物理攻撃は発動の時点の値。クールダウン・コストも公式の表
//   （セイバーは Mana のヒーローなのでコストはそのまま）。
// 再使用の窓は Saber に無いので使わない。
//
// 状態（KitState）:
//   ints[0]  = 奥義の段（0 = なし / 1 = 突進中 / 2 = 三連撃中）  ints[1] = 剣撃を出さない間 1（3 撃目の最中のみ）
//   ints[2]  = 剣撃を出した回数（累計。検証用）                  ints[3] = 奥義の三連撃が当たった回数（累計。検証用）
//   ints[4]  = 直近に防御ダウンを積んだ敵の層の数（パッシブのバッジ用）  ids[1] = その敵
//   timers[0] = 剣が周回している残り秒   timers[1] = 剣撃の最短間隔（同時に何本も飛ばさない）
//   timers[2] = S2 の強化通常攻撃の残り秒   timers[3] = 防御ダウンの層が残っている秒（バッジ。命中のたびに 5 秒へ戻る）
//   reals[0] = 接触ダメージ（1 回）  reals[1] = 剣撃ダメージ  reals[2] = 強化通常攻撃の基礎ダメージ  reals[3] = 奥義の 1・2 撃目
//   reals[4] = 奥義の 3 撃目
//   ids[0]   = 奥義の対象

extension KitState {
    var zailUltPhase: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    var zailSwordLock: Int {
        get { ints[1] }
        set { ints[1] = newValue }
    }

    var zailSwordStrikes: Int {
        get { ints[2] }
        set { ints[2] = newValue }
    }

    var zailUltStrikes: Int {
        get { ints[3] }
        set { ints[3] = newValue }
    }

    var zailSwordsRemaining: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    var zailSwordGap: Double {
        get { timers[1] }
        set { timers[1] = newValue }
    }

    var zailChargeWindow: Double {
        get { timers[2] }
        set { timers[2] = newValue }
    }

    var zailPulseDamage: Double {
        get { reals[0] }
        set { reals[0] = newValue }
    }

    var zailStrikeDamage: Double {
        get { reals[1] }
        set { reals[1] = newValue }
    }

    var zailChargeBonus: Double {
        get { reals[2] }
        set { reals[2] = newValue }
    }

    var zailUltDamage: Double {
        get { reals[3] }
        set { reals[3] = newValue }
    }

    var zailUltFinalDamage: Double {
        get { reals[4] }
        set { reals[4] = newValue }
    }

    var zailUltTargetID: EntityID {
        get { ids[0] }
        set { ids[0] = newValue }
    }

    var zailBaneStacks: Int {
        get { ints[4] }
        set { ints[4] = newValue }
    }

    var zailBaneWindow: Double {
        get { timers[3] }
        set { timers[3] = newValue }
    }

    var zailBaneTargetID: EntityID {
        get { ids[1] }
        set { ids[1] = newValue }
    }
}

struct Kit_H028: HeroKit {
    let heroID = "H028"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H028(isReady: true)` を HeroKits.testOverride に差すこともできる。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    // MARK: - 数値（MLBB の公式の表そのまま。距離は Velstria 単位 = MLBB × 100。公式に無い幾何と時間は 2026-10-16 の画面収録で測った値）

    enum Tune {
        // パッシブ 空断の理
        static let baneMaxStacks = 5
        static let baneDuration = 5.0
        /// 1 層あたりの物理防御の低下（固定値）。日本語クライアントの文は「3-8」（範囲）だけで、レベル別の表は Fandom の現行の
        /// {{Ability}}（2026-10 に MediaWiki API で取得。式ではなく、あるレベルに達するたびに 1 ずつ増える。Lv1〜15）。
        static let baneByLevel: [Double] = [3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 7, 7, 7, 8]
        static let baneMinPerStack = 3.0
        static let baneMaxPerStack = 8.0
        /// 防御の低下に使う状態（固定値。magnitude は負 = 低下。層 × 1 層あたりを 1 つの状態で持つ）。公式どおり物理防御だけ
        /// （`flatArmorMod`。魔法防御は変えない）。
        static let baneStatus: StatusKind = .flatArmorMod
        static let baneMark = "bane"
        static let baneTag = KitTags.buff("H028", "bane")

        // S1 周回する剣（幾何と時間は 2026-10-16 の画面収録で測った値。docs/kits/Saber.md「動画で測った値（2026-10-16）」）
        /// 剣の周回の半径（術者の中心から剣の中心まで）。動画: 5 本の剣の中心が術者から 3.86〜3.88（剣の高さを 55 ヒーロー px として
        /// 地面へ戻した中央値。高さの見当で ±0.15）。以前の推測は 230（対象の縁まで、円の中の全員）。
        static let orbitRadius = 385.0
        /// 剣が届く外縁（術者の中心から）。動画: S1 を押したままの照準の円 4.45（72 方向で ±0.02）= 剣の帯の外縁
        /// （剣の中心 3.85 + 手裏剣の半径 0.6）。剣の帯は orbitRadius ± swordHalfWidth（325〜445）で、対象の体がこの帯に掛かれば触れる。
        static let swordReach = 445.0
        static var swordHalfWidth: Double { swordReach - orbitRadius }
        static let swordCount = 5
        /// 剣が出ている秒数。動画: 指を離してから 0.2 秒で剣が出て、0.47 秒で輪に着き、4.6 秒で戻り始め、4.83 秒で戻り終わる（2 回とも同じ）。
        static let swordsDuration = 4.8
        /// 剣の回る速さ（度/秒、上から見て時計回り）。動画: 毎秒 151°（S1 の 1 回目、65 点）・154°（4 回目、38 点）。周期 2.4 秒。
        static let orbitSpeed = 151.0
        /// 接触ダメージの最初の時刻・間隔・回数。剣が輪に着く 0.47 秒から、5 本が 72° おきに毎秒 151° で回るので、輪の上の 1 点を
        /// 0.48 秒ごとに剣が通る（72 / 151）。戻り始める 4.6 秒までに 9 回（0.47〜4.31 秒）。以前は 0.5 秒ごと 9 回（0.5〜4.5 秒）。
        static let pulseFirst = 0.47
        static let pulseInterval = 0.48
        static let pulseCount = 9
        /// 公式（日本語クライアント）の表: 接触（「基礎ダメージ」）75 / 85 / 95 / 105 / 115 / 125（+25% 追加物理攻撃）、
        /// 剣の攻撃 = 剣撃（「追加ダメージ」）200 / 220 / 240 / 260 / 280 / 300（+50% 追加物理攻撃）。追加物理攻撃は発動の時点の値。
        static let contactBase: [Double] = [75, 85, 95, 105, 115, 125]
        static let contactAttackRatio = 0.25
        static let strikeBase: [Double] = [200, 220, 240, 260, 280, 300]
        static let strikeAttackRatio = 0.5
        /// 命中から剣撃が当たるまで。動画: 奥義の 1・2 撃目 → 剣撃の数字が 3 コマ（2 回）、強化通常攻撃 → 2 コマ（以前の推測は 0.12 秒）。
        static let strikeDelay = 0.1
        /// 剣撃どうしの最短間隔（多段ヒットのスキルで一度に何本も飛ばさない。公式に記載なし = 推測の値）。
        static let strikeGap = 0.35
        /// 剣撃が届く最大距離（術者の中心から対象の縁まで）。
        static let strikeReach = 450.0
        static let strikePassRadius = 80.0
        static let strikePassOvershoot = 100.0
        /// 進路上の他の敵への割合（公式「進路上の敵に50%のダメージ」）。
        static let strikePassRatio = 0.5
        /// 剣の攻撃のミニオンへの倍率（公式「ミニオンへのダメージは50%に低下」。主語は「剣の攻撃」なので主対象と進路上の敵の両方に掛ける
        /// = 進路上のミニオンは 25%。モンスター・練習場の人形・ヒーローは 100%。`HitPayload.minionMultiplier`）。
        static let strikeMinionRatio = 0.5
        /// 剣撃 1 本あたりの S2 のクールダウン短縮（公式 1 秒）。
        static let chargeRefund = 1.0
        /// 剣撃 1 本あたりの S1 自身のクールダウン短縮（公式 0.5 秒）。
        static let swordsRefund = 0.5

        // S2 突進
        /// 射程と速さ。動画: 照準の円 2.97（±0.01）、突進は 6.2 コマで 3.0〜3.1、止まった的の体力バーで 1 コマ 0.50 = 毎秒 15.0
        /// （3 回とも同じ速さ）。以前の推測は 350・1800。
        static let dashRange = 300.0
        static let dashSpeed = 1500.0
        /// 経路の当たり半径（対象の半径は別に足す）。
        static let dashWidth = 70.0
        /// 公式（日本語クライアント）の表: 突撃（「基礎ダメージ」）75 / 90 / 105 / 120 / 135 / 150（+50% 追加物理攻撃）。
        /// 強化通常攻撃（「強化ダメージ」）75 / 90 / 105 / 120 / 135 / 150（+120% 物理攻撃 = 合計の物理攻撃）で通常攻撃を置き換える
        /// （= 通常攻撃のダメージ × 1.2 + 基礎）。
        static let dashBase: [Double] = [75, 90, 105, 120, 135, 150]
        static let dashAttackRatio = 0.5
        static let enhanceBase: [Double] = [75, 90, 105, 120, 135, 150]
        static let enhanceAttackRatio = 1.2
        /// 強化通常攻撃を撃てる時間（公式に記載なし。汎用の強化通常攻撃（blinkEmpower）に合わせた）。動画の 3 回はどれも
        /// 到着から 0.1〜0.7 秒で使ったので、上限は測れていない。
        static let enhanceWindow = Balance.Skills.empowerDuration
        /// 強化通常攻撃の射程（公式 2.5 = 250。通常攻撃の射程 180 との差を、強化が残っている間だけ足す）。動画: 強化の間の足元の円 2.47〜2.48
        /// （通常攻撃の円 1.78〜1.80 と同じく公式の −1%）。
        static let enhanceRange = 250.0
        static let enhanceRangeTag = KitTags.buff("H028", "enhanceRange")
        static let slowAmount = 0.6
        static let slowDuration = 1.0
        static let slowTag = KitTags.buff("H028", "chargeSlow")

        // 奥義 三連断空
        /// 突進の届く距離（術者の中心から対象の縁まで）。動画: 照準の円 5.44〜5.45（2 回）。以前の推測は 500（調査の 4.6・旧 5.9）。
        static let ultReach = 545.0
        /// 突進の速さ。動画: 止まった的の体力バーで 1 コマ 0.56〜0.60 = 毎秒 17.0〜17.4（2 回）。以前の推測は 2600。
        static let ultSpeed = 1700.0
        static let ultGap = 10.0
        /// 到着時に対象がこれより離れていたら外れ（突進の追尾はしない）。
        static let ultSlack = 260.0
        /// 打ち上げ（公式 1.2 秒）。動画: 対象の「ノックアップ」の表示が 37・38 コマ（1.23・1.27 秒）。
        static let airborne = 1.2
        static let strikeCount = 3
        /// 3 撃の時刻（到着から）。動画: 1 撃目は打ち上げの表示と同じコマ（到着の瞬間）、2 撃目は 12・13 コマ後、3 撃目は 23・24 コマ後
        /// （2 回とも。3 撃目は 1 撃目のちょうど 2 倍の数字で見分けた）= 0 / 0.40 / 0.78 秒。以前の推測は 0.2 / 0.6 / 1.0 秒。
        static let ultFirstDelay = 0.0
        static let ultInterval = 0.39
        /// 術者が動けない時間（到着から）。動画: 到着から 30 コマ（1.0 秒。3 撃目の 8 コマ後）で歩き出す（2 回とも）。
        /// 以前は 3 撃目で解けた。
        static let ultLock = 1.0
        /// 公式（日本語クライアント）の表: 1・2 撃目（「基礎ダメージ」）120 / 170 / 220（+80% 追加物理攻撃）、
        /// 3 撃目（「追加ダメージ」）240 / 340 / 440（+160% 追加物理攻撃）（Fandom の 120 / 150 / 180（+100%）は誤り）。
        static let ultStrikeBase: [Double] = [120, 170, 220]
        static let ultStrikeAttackRatio = 0.8
        static let ultFinalBase: [Double] = [240, 340, 440]
        static let ultFinalAttackRatio = 1.6
        static let channelTag = KitTags.buff("H028", "channel")
        /// ボットが関門を待たずに奥義を撃つ、敵ヒーローの HP の割合の上限（打ち上げ中の 3 連撃 + 防御ダウンで削り切れる目安）。
        static let botExecuteRatio = 0.6

        // クールダウン（公式の表の秒数。CD 短縮を掛ける: Kit.cooldown）。全 Lv 一定のものは 1 要素
        /// S1 は全 Lv 10 秒（日本語クライアント。Fandom の 9 秒は誤り）。持続 5 秒、剣撃 1 本ごとに 0.5 秒縮む。
        static let swordsCooldown: [Double] = [10]
        static let chargeCooldown: [Double] = [7]
        static let ultCooldown: [Double] = [44, 40, 36]
        // コスト（公式の MP。セイバーは Mana のヒーローなので倍率は掛からない: HeroKits.resourceCost）
        /// 日本語クライアント: S1 60 / 65 / 70 / 75 / 80 / 85、S2 40 / 44 / 48 / 52 / 56 / 60、奥義 100 / 120 / 140
        /// （Fandom の S1 75 → 125・S2 70 → 45 は誤り）。
        static let swordsCost: [Double] = [60, 65, 70, 75, 80, 85]
        static let chargeCost: [Double] = [40, 44, 48, 52, 56, 60]
        static let ultCost: [Double] = [100, 120, 140]
    }

    /// KitTimer.code
    private enum Code {
        static let pulse = 1
        static let swordStrike = 2
        static let chargeArrive = 3
        static let ultArrive = 4
        static let ultStrike = 5
        /// 奥義の硬直の終わり（到着から ultLock 秒）
        static let ultEnd = 6
    }

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 自己中心（剣が周囲を回る）。radius = 剣の帯の外縁（照準の円 4.45）。接触は輪の帯（orbitRadius ± swordHalfWidth）だけ
            return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: Tune.swordReach, shape: .selfRing)
        case .skill2:
            // 指定方向への突進（経路上の敵に当たる）。radius は経路の当たり半径
            return SkillTargeting(archetype: .dashStrike, aim: .direction, range: Tune.dashRange,
                                  radius: Tune.dashWidth, shape: .dashToPoint)
        case .ultimate:
            // 敵ヒーローを指定して突進（居なければ消費せず失敗）
            return SkillTargeting(archetype: .targetedBlink, aim: .unit, range: Tune.ultReach, radius: 120,
                                  shape: .lockOn, requiresTarget: true)
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
            n.extras = [KitStat(key: "baneMin", value: Tune.baneMinPerStack),
                        KitStat(key: "baneMax", value: Tune.baneMaxPerStack),
                        KitStat(key: "stacks", value: Double(Tune.baneMaxStacks)),
                        KitStat(key: "duration", value: Tune.baneDuration)]
        case .skill1:
            n.hits = Tune.pulseCount
            n.damage = Self.contactDamage(rank: rank, stats: stats)
            n.cc = .none
            n.ccDuration = 0
            n.cooldown = Kit.cooldown(Tune.swordsCooldown, rank: rank, stats: stats)
            n.extras = [KitStat(key: "strikeDamage", value: Self.strikeDamage(rank: rank, stats: stats).rounded()),
                        KitStat(key: "duration", value: Tune.swordsDuration),
                        KitStat(key: "refund", value: Tune.chargeRefund),
                        KitStat(key: "passPercent", value: Tune.strikePassRatio * 100),
                        KitStat(key: "minionPercent", value: Tune.strikeMinionRatio * 100),
                        KitStat(key: "base", value: Kit.level(Tune.contactBase, rank: rank)),
                        KitStat(key: "atkPct", value: Tune.contactAttackRatio * 100),
                        KitStat(key: "strikeBase", value: Kit.level(Tune.strikeBase, rank: rank)),
                        KitStat(key: "strikePct", value: Tune.strikeAttackRatio * 100),
                        KitStat(key: "selfRefund", value: Tune.swordsRefund)]
        case .skill2:
            n.hits = 1
            n.damage = Self.dashDamage(rank: rank, stats: stats)
            // 鈍足は強化通常攻撃につく
            n.cc = .slow
            n.ccDuration = Tune.slowDuration
            n.cooldown = Kit.cooldown(Tune.chargeCooldown, rank: rank, stats: stats)
            let enhance = Self.enhanceBaseDamage(rank: rank)
            n.extras = [KitStat(key: "enhanceDamage", value: (stats.attack * Tune.enhanceAttackRatio + enhance).rounded()),
                        KitStat(key: "slowPercent", value: Tune.slowAmount * 100),
                        KitStat(key: "slowDuration", value: Tune.slowDuration),
                        KitStat(key: "window", value: Tune.enhanceWindow),
                        KitStat(key: "base", value: Kit.level(Tune.dashBase, rank: rank)),
                        KitStat(key: "atkPct", value: Tune.dashAttackRatio * 100),
                        KitStat(key: "enhanceBase", value: enhance),
                        KitStat(key: "enhancePct", value: Tune.enhanceAttackRatio * 100),
                        KitStat(key: "enhanceReach", value: Tune.enhanceRange / hero.attackRange)]
        case .ultimate:
            let first = Self.ultStrikeDamage(rank: rank, stats: stats)
            let final = Self.ultFinalDamage(rank: rank, stats: stats)
            n.hits = Tune.strikeCount
            // 平均 1 撃（totalDamage = 1・2 撃目 × 2 + 3 撃目）
            n.damage = (first * Double(Tune.strikeCount - 1) + final) / Double(Tune.strikeCount)
            n.missingHealthRatio = 0
            n.cc = .knockback
            n.ccIsUltimate = true
            n.ccDuration = Tune.airborne
            n.cooldown = Kit.cooldown(Tune.ultCooldown, rank: rank, stats: stats)
            n.extras = [KitStat(key: "strike1", value: first.rounded()),
                        KitStat(key: "strike3", value: final.rounded()),
                        KitStat(key: "airborne", value: Tune.airborne),
                        KitStat(key: "interval", value: Tune.ultInterval),
                        KitStat(key: "base", value: Kit.level(Tune.ultStrikeBase, rank: rank)),
                        KitStat(key: "atkPct", value: Tune.ultStrikeAttackRatio * 100),
                        KitStat(key: "base3", value: Kit.level(Tune.ultFinalBase, rank: rank)),
                        KitStat(key: "atkPct3", value: Tune.ultFinalAttackRatio * 100)]
        }
        return n
    }

    /// Lv ごとのコスト（公式の MP の表。Mana なので値そのまま: S1 60〜85、S2 40〜60、奥義 100 / 120 / 140）。
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double {
        let table: [Double]
        switch slot {
        case .skill1: table = Tune.swordsCost
        case .skill2: table = Tune.chargeCost
        case .ultimate: table = Tune.ultCost
        case .passive: return base
        }
        return HeroKits.resourceCost(Kit.level(table, rank: rank), hero: hero)
    }

    /// 説明文は公式（日本語クライアント）の文の構造に合わせる（数値は {トークン} で sim から。{base}(+{atkPct}%追加物理攻撃) は公式の表の値）。
    /// 名前は master のもの（フライングソード = 環剣、アサルト = 断空突進、剣の攻撃 = 剣撃）。
    func text(slot: SkillSlot) -> KitText? {
        let gap = String(format: "%g", Tune.strikeGap)
        let every = String(format: "%g", Tune.pulseInterval)
        switch slot {
        case .passive:
            return KitText(
                ja: "ダメージを与えるたびに、対象の物理防御を{duration}秒間{baneMin}-{baneMax}低下させる（レベルに応じて増加。最大{stacks}スタック）。\n\n"
                    + "防御を下げるのは通常攻撃とスキルのダメージで、ミニオンには積まれない。",
                en: "Each time Zail deals damage, the target's Physical Defense is reduced by {baneMin}-{baneMax} for {duration}s (grows with level; up to {stacks} stacks).\n\n"
                    + "Only basic attack and skill damage reduce defense, and it does not apply to minions.",
                tags: [KitTag.debuff])
        case .skill1:
            return KitText(
                ja: "自身の周囲を旋回する剣を5本放ち、命中した周囲の敵に{base}(+{atkPct}%追加物理攻撃)の物理ダメージを与える（\(every)秒ごと、最大{hits}回。剣は少し離れた輪を回り、すぐそばの敵には触れない）。効果時間（{duration}秒）終了後、剣は自身のもとへ戻る。\n\n"
                    + "発動中、通常攻撃またはスキルでダメージを与えるたびに剣撃を放つ（\(gap)秒に1回まで）。剣撃は対象に{strikeBase}(+{strikePct}%追加物理攻撃)の物理ダメージを与え、進路上の敵に{passPercent}%のダメージを与える（ミニオンへのダメージは{minionPercent}%に低下）。剣撃ごとに、環剣のクールダウンが{selfRefund}秒、断空突進のクールダウンが{refund}秒短縮される。",
                en: "Release 5 swords that orbit around Zail, dealing {base} (+{atkPct}% Extra Physical Attack) physical damage to nearby enemies hit (every \(every)s, up to {hits} times; the swords circle a ring a short distance away and do not touch enemies right next to Zail). When the effect ends ({duration}s), the swords return to Zail.\n\n"
                    + "While active, each time Zail deals damage with a basic attack or a skill, a sword strike flies at the target (at most once every \(gap)s), dealing {strikeBase} (+{strikePct}% Extra Physical Attack) physical damage to the target and {passPercent}% damage to enemies in its path (damage to minions is reduced to {minionPercent}%). Each sword strike reduces the cooldown of this skill by {selfRefund}s and of Charge by {refund}s.",
                tags: [KitTag.aoe, KitTag.buff])
        case .skill2:
            return KitText(
                ja: "指定方向へ突撃し、進路上の敵に{base}(+{atkPct}%追加物理攻撃)の物理ダメージを与える。\n\n"
                    + "突撃後、強化された通常攻撃を獲得する（{window}秒以内。射程は近接攻撃の約{enhanceReach}倍）。強化された通常攻撃は対象に{enhanceBase}(+{enhancePct}%物理攻撃)の物理ダメージを与え、移動速度を{slowDuration}秒間{slowPercent}%低下させる。",
                en: "Charge in the target direction, dealing {base} (+{atkPct}% Extra Physical Attack) physical damage to enemies along the way.\n\n"
                    + "After the charge, Zail gains an enhanced basic attack (within {window}s, reaching about {enhanceReach}x the melee attack range) that deals {enhanceBase} (+{enhancePct}% Physical Attack) physical damage to the target and reduces its Movement Speed by {slowPercent}% for {slowDuration}s.",
                tags: [KitTag.mobility])
        case .ultimate:
            return KitText(
                ja: "対象の敵ヒーローへ突撃し、{airborne}秒間ノックアップさせる（強靭＝コントロール時間短縮の影響を受けない）。\n\n"
                    + "ノックアップの間に対象を3回攻撃し、最初の2回はそれぞれ{base}(+{atkPct}%追加物理攻撃)の物理ダメージ、3回目は{base3}(+{atkPct3}%追加物理攻撃)の物理ダメージを与える。"
                    + "突撃の途中はノックアップと制圧で止められるが、ノックアップさせた後は制圧によってのみ中断される。",
                en: "Charge at the target enemy hero and knock them airborne for {airborne}s (not affected by Resilience, i.e. crowd-control reduction).\n\n"
                    + "Strike the target 3 times while airborne: the first two strikes deal {base} (+{atkPct}% Extra Physical Attack) physical damage each, and the third deals {base3} (+{atkPct3}% Extra Physical Attack). "
                    + "The charge can be stopped by knock-ups and suppression, but once the target is airborne the skill can only be interrupted by suppression.",
                tags: [KitTag.burst, KitTag.disrupt])
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            // 直近に防御ダウンを積んだ敵の層の数（残りの時間があるあいだ）。層が増えるたびに演出のパッシブの合図が出る
            guard k.zailBaneWindow > 0, k.zailBaneStacks > 0 else { return nil }
            return KitBadge(kind: .stacks, value: min(Tune.baneMaxStacks, k.zailBaneStacks), maxValue: Tune.baneMaxStacks)
        case .skill1:
            guard k.zailSwordsRemaining > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.zailSwordsRemaining, total: Tune.swordsDuration)
        case .skill2:
            guard k.zailChargeWindow > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.zailChargeWindow, total: Tune.enhanceWindow)
        default:
            return nil
        }
    }

    // MARK: - B. 実行

    func canStart(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) -> Bool {
        // 奥義の突進・三連撃の間は、ほかのスキルを始められない
        (s.units[caster].hero?.kit?.zailUltPhase ?? 0) == 0
    }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        switch c.slot {
        case .skill1: castSwords(&s, c)
        case .skill2: castCharge(&s, ctx, c)
        case .ultimate: castTripleSweep(&s, ctx, c)
        case .passive: break
        }
        return .done
    }

    /// S1: 剣が術者から orbitRadius の輪を回る。輪に着く 0.47 秒から 0.48 秒ごとに輪の帯の敵へ接触ダメージ（CC では止まらない）。
    private func castSwords(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        // 重ね掛け（クールダウンのリセットなど）は予約を作り直す
        Kit.cancelScheduled(&s, caster: i, slot: .skill1, code: Code.pulse)
        let n = c.numbers
        // 接触・剣撃のダメージ（公式の表 + 25% / 50% 追加物理攻撃。発動した時点の Lv・追加物理攻撃）
        let stats = s.units[i].stats
        let pulse = Self.contactDamage(rank: n.rank, stats: stats)
        s.units[i].hero!.kit!.zailSwordsRemaining = Tune.swordsDuration
        s.units[i].hero!.kit!.zailPulseDamage = pulse
        s.units[i].hero!.kit!.zailStrikeDamage = Self.strikeDamage(rank: n.rank, stats: stats)
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: s.units[i].pos, shape: .selfRing,
                     duration: Tune.swordsDuration, count: Tune.swordCount)
        Kit.strikeSequence(&s, caster: i, slot: .skill1, code: Code.pulse, count: Tune.pulseCount,
                           interval: Tune.pulseInterval, firstDelay: Tune.pulseFirst, param: pulse,
                           interruptible: false)
    }

    /// S2: 指定方向への突進。通り道の敵に 1 度ずつダメージ。到着で次の通常攻撃が強化される。
    private func castCharge(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let from = s.units[i].pos
        let dir = c.aim.direction
        var distance = c.aim.distance
        if let u = c.aim.unit {
            // 対象を指定したときは対象の縁で止まる
            distance = max(0, min(Tune.dashRange, distance - s.units[u].radius - s.units[i].radius - 5))
        }
        distance = min(distance, Tune.dashRange)
        // 強化通常攻撃の基礎（公式の表）。通常攻撃のダメージ × 1.2 に足す（shapeBasicAttack）
        s.units[i].hero!.kit!.zailChargeBonus = Self.enhanceBaseDamage(rank: c.numbers.rank)
        // 突進のダメージ = 基礎 + 50% 追加物理攻撃（発動した時点の値）
        var p = HitPayload(damage: Self.dashDamage(rank: c.numbers.rank, stats: s.units[i].stats),
                           damageType: .physical, source: .skill(.skill2), skillID: c.check.skill.skillID)
        p.originPos = from
        let landing = Kit.dashSweeping(&s, ctx, caster: i, slot: .skill2, to: from + dir * distance,
                                       speed: Tune.dashSpeed, payload: p, radius: Tune.dashWidth,
                                       arriveCode: Code.chargeArrive)
        Kit.emitCast(&s, c, origin: from, target: landing, unit: c.aim.unit, shape: .dashToPoint,
                     duration: from.distance(to: landing) / Tune.dashSpeed, count: 1)
    }

    /// 奥義: 対象の敵ヒーローへ突進。到着で打ち上げて三連撃を予約する（onTimer）。
    private func castTripleSweep(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        guard let t = c.aim.unit else { return }
        let from = s.units[i].pos
        let toTarget = s.units[t].pos - from
        let dir = toTarget.normalized == .zero ? Vec2.fromAngle(s.units[i].facing) : toTarget.normalized
        // 対象の縁（術者の半径込み）で止まる
        let gap = s.units[i].radius + s.units[t].radius + Tune.ultGap
        let travel = min(Tune.ultReach, max(0, toTarget.length - gap))
        s.units[i].hero!.kit!.zailUltTargetID = s.units[t].id
        // 1・2 撃目 = 基礎 + 80% 追加物理攻撃、3 撃目 = 基礎 + 160% 追加物理攻撃（公式の表。発動した時点の値）
        let stats = s.units[i].stats
        s.units[i].hero!.kit!.zailUltDamage = Self.ultStrikeDamage(rank: c.numbers.rank, stats: stats)
        s.units[i].hero!.kit!.zailUltFinalDamage = Self.ultFinalDamage(rank: c.numbers.rank, stats: stats)
        s.units[i].hero!.kit!.zailUltPhase = 1
        // 経路上の敵には当たらない（affectsEnemies = false）。ハード CC の中断と着地の通知だけを使う
        let carrier = HitPayload(damage: 0, damageType: .physical, source: .skill(.ultimate), affectsEnemies: false)
        let landing = Kit.dashSweeping(&s, ctx, caster: i, slot: .ultimate, to: from + dir * travel,
                                       speed: Tune.ultSpeed, payload: carrier, radius: 0, arriveCode: Code.ultArrive)
        let dash = from.distance(to: landing) / Tune.ultSpeed
        // 長さ = 突進 + 到着からの硬直（3 撃はその中: 到着 + 0 / 0.39 / 0.78 秒）
        Kit.emitCast(&s, c, origin: from, target: s.units[t].pos, unit: t, shape: .lockOn,
                     duration: dash + Tune.ultLock, count: Tune.strikeCount)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        switch timer.code {
        case Code.pulse: pulse(&s, ctx, owner: owner, timer: timer)
        case Code.swordStrike: sendSword(&s, ctx, owner: owner, timer: timer)
        case Code.chargeArrive:
            s.units[owner].hero?.kit?.zailChargeWindow = Tune.enhanceWindow
            // 強化通常攻撃の射程（公式 2.5 = 250）。強化が残っている間だけ通常攻撃の射程を伸ばす
            let bonus = Tune.enhanceRange - (ctx.master.hero(heroID)?.attackRange ?? Tune.enhanceRange)
            if bonus > 0 {
                Kit.grantAttackRange(&s, target: owner, amount: bonus, duration: Tune.enhanceWindow,
                                     tag: Tune.enhanceRangeTag)
            }
        case Code.ultArrive: ultArrive(&s, ctx, owner: owner)
        case Code.ultStrike: ultStrike(&s, ctx, owner: owner, timer: timer)
        case Code.ultEnd:
            // 3 撃の後の硬直が明けた（到着から ultLock 秒）
            if s.units[owner].hero?.kit?.zailUltPhase == 2 { endUlt(&s, owner) }
        default: break
        }
    }

    /// S1 の接触ダメージ 1 回: 剣の輪の帯（術者から orbitRadius ± swordHalfWidth）に体が掛かる敵（構造物を除く）。
    /// 輪の内側（術者のすぐそば）・外側の敵には触れない（動画: 剣は術者から 3.85 を回り、隣の敵に接触の数字が出ない）。
    private func pulse(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        let p = HitPayload(damage: timer.param, damageType: .physical, source: .skill(.skill1),
                           skillID: Self.skillID(ctx, .skill1))
        let me = s.units[owner].pos
        let team = s.units[owner].team
        var targets: [Int] = []
        for j in s.units.indices where s.units[j].team != team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j) else { continue }
            if abs(me.distance(to: s.units[j].pos) - Tune.orbitRadius) <= Tune.swordHalfWidth + s.units[j].radius {
                targets.append(j)
            }
        }
        guard !targets.isEmpty else { return }
        let ownerID = s.units[owner].id
        for j in targets {
            CombatSystem.applyHit(&s, ctx, sourceID: ownerID, team: team, targetIndex: j, payload: p, from: me)
        }
    }

    /// 剣撃: 主対象にダメージ + S1・S2 のクールダウン短縮、軌道上の他の敵に 50%。ミニオンへは主対象・軌道上とも 50%（公式）。
    private func sendSword(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard let t = s.index(of: timer.targetID), CombatSystem.isLiving(s, t), !s.units[t].isStructure,
              s.units[t].team != s.units[owner].team else { return }
        let me = s.units[owner].pos
        let tp = s.units[t].pos
        let reach = Tune.strikeReach + s.units[t].radius
        guard me.distanceSquared(to: tp) <= reach * reach else { return }
        let dir = (tp - me).normalized == .zero ? Vec2.fromAngle(s.units[owner].facing) : (tp - me).normalized
        let end = tp + dir * Tune.strikePassOvershoot
        // 軌道上の敵は先に確定（命中中の死亡で判定が変わらないように）
        var others: [Int] = []
        for j in s.units.indices where j != t && s.units[j].team != s.units[owner].team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j) else { continue }
            if distancePointToSegment(s.units[j].pos, me, end) <= Tune.strikePassRadius + s.units[j].radius {
                others.append(j)
            }
        }
        let skillID = Self.skillID(ctx, .skill1)
        let ownerID = s.units[owner].id
        let team = s.units[owner].team
        // 剣撃 1 本ごとに S2 のクールダウン −1 秒・S1 自身のクールダウン −0.5 秒（日本語クライアント）。
        // ミニオンへは 50%（公式「ミニオンへのダメージは50%に低下」。モンスターは 100%）
        let main = HitPayload(damage: timer.param, damageType: .physical, source: .skill(.skill1),
                              skillID: skillID, effects: [.refundCooldown(slot: .skill2, seconds: Tune.chargeRefund),
                                                          .refundCooldown(slot: .skill1, seconds: Tune.swordsRefund)],
                              minionMultiplier: Tune.strikeMinionRatio)
        CombatSystem.applyHit(&s, ctx, sourceID: ownerID, team: team, targetIndex: t, payload: main, from: me)
        guard CombatSystem.isLiving(s, owner) else { return }
        let pass = HitPayload(damage: timer.param * Tune.strikePassRatio, damageType: .physical, source: .skill(.skill1),
                              skillID: skillID, minionMultiplier: Tune.strikeMinionRatio)
        for j in others {
            CombatSystem.applyHit(&s, ctx, sourceID: ownerID, team: team, targetIndex: j, payload: pass, from: me)
        }
    }

    /// 奥義の到着: 打ち上げて三連撃を予約する。対象が居ない・離れすぎ・対象不可なら外れ。
    private func ultArrive(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let k = s.units[owner].hero?.kit, k.zailUltPhase == 1 else { return }
        guard let t = s.index(of: k.zailUltTargetID), CombatSystem.isLiving(s, t),
              s.units[t].team != s.units[owner].team, !s.units[t].has(.untargetable) else {
            endUlt(&s, owner)
            return
        }
        let reach = s.units[owner].radius + s.units[t].radius + Tune.ultSlack
        guard s.units[owner].pos.distanceSquared(to: s.units[t].pos) <= reach * reach else {
            endUlt(&s, owner)
            return
        }
        let id = s.units[owner].id
        s.units[owner].hero!.kit!.zailUltPhase = 2
        // 打ち上げ（CC 無効・無敵の相手には掛からないが、三連撃は続ける）
        // 公式「強靭の影響を受けない」
        Kit.knockUp(&s, target: t, duration: Tune.airborne, sourceID: id, ignoresResilience: true)
        let face = (s.units[t].pos - s.units[owner].pos)
        if face != .zero { s.units[owner].facing = face.angle }
        // 三連撃と、その後の硬直（到着から ultLock 秒。動画: 3 撃目の 8 コマ後に歩き出す）の間は動かない。
        // 打ち上げたあとは制圧（suppress）でのみ中断される（公式。スタンなどでは止まらない）
        let span = Tune.ultLock
        s.units[owner].attackTargetID = nil
        s.units[owner].windupRemaining = nil
        s.units[owner].moveIntent = .none
        s.units[owner].path.removeAll()
        CombatSystem.addStatus(&s, targetIndex: owner, StatusEffect(kind: .root, duration: span, sourceID: id,
                                                                      tag: Tune.channelTag))
        CombatSystem.addStatus(&s, targetIndex: owner, StatusEffect(kind: .channeling, duration: span, sourceID: id,
                                                                      tag: Tune.channelTag))
        Kit.strikeSequence(&s, caster: owner, slot: .ultimate, code: Code.ultStrike, count: Tune.strikeCount,
                           interval: Tune.ultInterval, firstDelay: Tune.ultFirstDelay, targetID: k.zailUltTargetID,
                           param: k.zailUltDamage, interruptible: false)
        Kit.schedule(&s, caster: owner, slot: .ultimate, code: Code.ultEnd, after: span, interruptible: false)
    }

    /// 奥義の予約（3 撃と硬直の終わり）をすべて取り消して終える。
    private func abortUlt(_ s: inout SimState, _ owner: Int) {
        Kit.cancelScheduled(&s, caster: owner, slot: .ultimate, code: Code.ultStrike)
        Kit.cancelScheduled(&s, caster: owner, slot: .ultimate, code: Code.ultEnd)
        endUlt(&s, owner)
    }

    /// 奥義の 1 撃。対象が倒れた・離れすぎた・術者が制圧されたら残りを取り消して終える。3 撃目は剣撃を乗せない。
    /// 3 撃目の後も硬直（到着から ultLock 秒）が明けるまで奥義は続く（Code.ultEnd で終える）。
    private func ultStrike(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard s.units[owner].hero?.kit?.zailUltPhase == 2 else { return }
        guard let t = s.index(of: timer.targetID), CombatSystem.isLiving(s, t), s.units[t].team != s.units[owner].team,
              !s.units[owner].has(.suppress)
        else {
            abortUlt(&s, owner)
            return
        }
        let reach = s.units[owner].radius + s.units[t].radius + Tune.ultSlack
        guard s.units[owner].pos.distanceSquared(to: s.units[t].pos) <= reach * reach else {
            abortUlt(&s, owner)
            return
        }
        let last = timer.index >= Tune.strikeCount - 1
        // 1・2 撃目 = 予約の param（基礎 + 80%）、3 撃目 = 発動の時点に決めた 3 撃目の値（基礎 + 160%）
        let damage = last ? (s.units[owner].hero?.kit?.zailUltFinalDamage ?? 0) : timer.param
        var p = HitPayload(damage: damage, damageType: .physical, source: .skill(.ultimate),
                           skillID: Self.skillID(ctx, .ultimate))
        p.originPos = s.units[owner].pos
        if last { s.units[owner].hero!.kit!.zailSwordLock = 1 }
        CombatSystem.applyHit(&s, ctx, sourceID: s.units[owner].id, team: s.units[owner].team, targetIndex: t,
                              payload: p, from: s.units[owner].pos)
        s.units[owner].hero?.kit?.zailSwordLock = 0
        s.units[owner].hero?.kit?.zailUltStrikes += 1
        // 3 撃目の後は硬直の終わり（Code.ultEnd）を待つ。予約が無ければ（念のため）ここで終える
        if last, Kit.scheduledCount(s, caster: owner, code: Code.ultEnd) == 0 { endUlt(&s, owner) }
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // バッジの敵が倒れた・居なくなったら層の表示を消す
        if let b = s.units[owner].hero?.kit, b.zailBaneWindow > 0 {
            let alive = s.index(of: b.zailBaneTargetID).map { CombatSystem.isLiving(s, $0) } ?? false
            if !alive {
                s.units[owner].hero!.kit!.zailBaneWindow = 0
                s.units[owner].hero!.kit!.zailBaneStacks = 0
                s.units[owner].hero!.kit!.zailBaneTargetID = 0
            }
        }
        guard let k = s.units[owner].hero?.kit, k.zailUltPhase != 0 else { return }
        // 打ち上げたあとの三連撃は制圧（suppress）でのみ中断される（スタンなどは予約を消さない）
        if k.zailUltPhase == 2, s.units[owner].has(.suppress) {
            abortUlt(&s, owner)
            return
        }
        // 奥義の突進・三連撃の間は、通常攻撃を始めない・動かない
        s.units[owner].attackTargetID = nil
        s.units[owner].windupRemaining = nil
        s.units[owner].moveIntent = .none
        // 想定外に予約・突進が消えていたら終える（状態を残さない）
        if k.zailUltPhase == 1, k.sweep == nil {
            endUlt(&s, owner)
        } else if k.zailUltPhase == 2, Kit.scheduledCount(s, caster: owner, code: Code.ultStrike) == 0,
                  Kit.scheduledCount(s, caster: owner, code: Code.ultEnd) == 0 {
            endUlt(&s, owner)
        }
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // 突進中のハード CC: 突進は取り消し済み。奥義の状態を畳む（クールダウンは戻らない）。
        // 三連撃（段 2）の予約は中断されない（interruptible: false）ので、ここでは畳まない（制圧だけが update で止める）
        guard s.units[owner].hero?.kit?.zailUltPhase == 1 else { return }
        abortUlt(&s, owner)
    }

    // MARK: - C. パッシブ

    func onBasicAttackHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, damage: Double) {
        guard damage > 0, s.units[attacker].hero?.kit != nil else { return }
        afterDamage(&s, ctx, owner: attacker, target: target, trigger: true)
    }

    func onSkillHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, slot: SkillSlot,
                    damage: Double) {
        // 「ダメージを与えた」ときだけ（CC のみの命中は数えない）。S1（接触・剣撃）は防御ダウンは入れるが剣撃は呼ばない
        guard damage > 0, s.units[attacker].hero?.kit != nil else { return }
        afterDamage(&s, ctx, owner: attacker, target: target, trigger: slot != .skill1)
    }

    private func afterDamage(_ s: inout SimState, _ ctx: SimContext, owner: Int, target t: Int, trigger: Bool) {
        applyBane(&s, ctx, owner: owner, target: t)
        guard trigger, let k = s.units[owner].hero?.kit, k.zailSwordsRemaining > 0, k.zailSwordGap <= 0,
              k.zailSwordLock == 0, s.units.indices.contains(t), !s.units[t].isStructure,
              s.units[t].team != s.units[owner].team else { return }
        s.units[owner].hero!.kit!.zailSwordGap = Tune.strikeGap
        s.units[owner].hero!.kit!.zailSwordStrikes = k.zailSwordStrikes + 1
        Kit.schedule(&s, caster: owner, slot: .skill1, code: Code.swordStrike, after: Tune.strikeDelay,
                     targetID: s.units[t].id, param: k.zailStrikeDamage, interruptible: false)
    }

    /// 空断の理: 防御ダウンの層を積む（最大 5 層・5 秒、命中のたびに持続が戻る）。ヒーロー・モンスター・人形が対象
    /// （ミニオンは対象外 = Fandom の注記・sim の負荷。構造物には効かない）。
    private func applyBane(_ s: inout SimState, _ ctx: SimContext, owner: Int, target t: Int) {
        guard s.units.indices.contains(t), CombatSystem.isLiving(s, t), s.units[t].team != s.units[owner].team else {
            return
        }
        switch s.units[t].kind {
        case .hero, .monster, .dummy: break
        default: return
        }
        let ownerID = s.units[owner].id
        let tag = KitTags.mark("H028", Tune.baneMark, owner: ownerID)
        let stacks = Kit.addMark(&s, target: t, ownerID: ownerID, tag: tag, maxStacks: Tune.baneMaxStacks,
                                 duration: Tune.baneDuration)
        guard stacks > 0 else { return }
        // バッジ用: 直近に積んだ敵の層の数と、残り時間（命中のたびに 5 秒へ戻る）
        s.units[owner].hero!.kit!.zailBaneStacks = stacks
        s.units[owner].hero!.kit!.zailBaneWindow = Tune.baneDuration
        s.units[owner].hero!.kit!.zailBaneTargetID = s.units[t].id
        // 防御ダウンは固定値（公式「物理防御を 3-8 低下」）: 層 × 1 層あたり（術者のレベル）を 1 つの状態で持ち、命中のたびに置き換える
        // （addStatus は同じ tag の強さを大きい方に寄せるので、負の値は外してから付け直す）。ほかの防御ダウンとは足し合わせ、0 を下回ってよい
        let level = s.units[owner].hero?.level ?? 1
        let amount = Double(stacks) * Self.baneFlat(level: level)
        s.units[t].statuses.removeAll { $0.kind == Tune.baneStatus && $0.tag == Tune.baneTag }
        CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: Tune.baneStatus, duration: Tune.baneDuration,
                                                                 magnitude: -amount, sourceID: ownerID,
                                                                 tag: Tune.baneTag))
        // 同じ tick の続きのダメージ（剣撃・奥義の次の一撃）から効くように能力値を更新する
        StatCalculator.recompute(&s, t, ctx)
    }

    func shapeBasicAttack(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                          plan: inout BasicAttackPlan) {
        guard let k = s.units[attacker].hero?.kit, k.zailChargeWindow > 0 else { return }
        // 強化通常攻撃（1 回で消える）: 通常攻撃を「基礎 + 物理攻撃の 120%」に置き換える
        // = 通常攻撃のダメージ（物理攻撃 × 会心）× 1.2 + 基礎（公式の表）。鈍足 60% 1 秒。射程の延長も消す
        plan.payload.damage = plan.payload.damage * Tune.enhanceAttackRatio + k.zailChargeBonus
        plan.payload.statuses.append(StatusEffect(kind: .slow, duration: Tune.slowDuration, magnitude: Tune.slowAmount,
                                                  sourceID: s.units[attacker].id, tag: Tune.slowTag))
        s.units[attacker].hero!.kit!.zailChargeWindow = 0
        s.units[attacker].statuses.removeAll { $0.kind == .attackRangeBoost && $0.tag == Tune.enhanceRangeTag }
    }

    // MARK: - D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        let me = s.units[bot].pos
        let foe = s.units[target]
        switch slot {
        case .skill2:
            // 突進: 交戦中、対象へ向けて（対象の縁で止まる）
            guard fighting, foe.id != 0 else { return .skip }
            let reach = targeting.reach + foe.radius + 100
            guard me.distanceSquared(to: foe.pos) <= reach * reach else { return .skip }
            return .cast(.unit(foe.id))
        case .ultimate:
            // 交戦中の敵ヒーローが射程内のとき。倒しやすい（HP が少ない）なら関門を待たずに今撃つ。
            // それ以外は汎用の関門（倒せる・2 体以上）を通ったときだけ（剣が回っているかどうかでは決めない）
            guard fighting, foe.kind == .hero else { return .skip }
            let reach = Tune.ultReach + foe.radius
            guard me.distanceSquared(to: foe.pos) <= reach * reach else { return .skip }
            if foe.hpRatio <= Tune.botExecuteRatio { return .castNow(.unit(foe.id)) }
            return .cast(.unit(foe.id))
        default:
            return .useDefault
        }
    }

    // MARK: - 部品

    private func endUlt(_ s: inout SimState, _ i: Int) {
        s.units[i].hero?.kit?.zailUltPhase = 0
        s.units[i].hero?.kit?.zailUltTargetID = 0
        s.units[i].statuses.removeAll { ($0.kind == .root || $0.kind == .channeling) && $0.tag == Tune.channelTag }
    }

    /// 1 層あたりの防御ダウン（固定値）。レベル別の表（Fandom の現行: Lv1〜3 = 3、Lv4〜6 = 4、…、Lv15 = 8）。
    static func baneFlat(level: Int) -> Double {
        Tune.baneByLevel[min(max(1, level), Tune.baneByLevel.count) - 1]
    }

    // MARK: - ダメージ（公式の表: 基礎[Lv] + 係数 × 能力値。Kit.official）

    /// S1 の接触 1 回（75〜125 + 25% 追加物理攻撃）。stats の追加物理攻撃（Stats.extraAttack）を使う。
    static func contactDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.contactBase, rank: rank, ratio: Tune.contactAttackRatio, .extraAttack, stats: stats)
    }

    /// S1 の剣撃 1 本（主対象。200〜300 + 50% 追加物理攻撃）。
    static func strikeDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.strikeBase, rank: rank, ratio: Tune.strikeAttackRatio, .extraAttack, stats: stats)
    }

    /// S2 の突進（75〜150 + 50% 追加物理攻撃）。
    static func dashDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.dashBase, rank: rank, ratio: Tune.dashAttackRatio, .extraAttack, stats: stats)
    }

    /// S2 の強化通常攻撃の基礎（75〜150）。通常攻撃のダメージ（合計の物理攻撃 × 会心）× 1.2 に足す（shapeBasicAttack）。
    static func enhanceBaseDamage(rank: Int) -> Double {
        Kit.level(Tune.enhanceBase, rank: rank)
    }

    /// 奥義の 1・2 撃目（120 / 170 / 220 + 80% 追加物理攻撃）。
    static func ultStrikeDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.ultStrikeBase, rank: rank, ratio: Tune.ultStrikeAttackRatio, .extraAttack, stats: stats)
    }

    /// 奥義の 3 撃目（240 / 340 / 440 + 160% 追加物理攻撃）。
    static func ultFinalDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.ultFinalBase, rank: rank, ratio: Tune.ultFinalAttackRatio, .extraAttack, stats: stats)
    }

    static func skillID(_ ctx: SimContext, _ slot: SkillSlot) -> String? {
        ctx.master.skill(hero: "H028", slot: slot)?.skillID
    }
}
