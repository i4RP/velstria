import Foundation

// 担当: kit-H029（docs/SKILL_KITS.md / docs/NEW_HEROES.md）
// H029 聖槌のボルグ = Velstria 版の Tigreal（MLBB）。数値・文言の正は日本語クライアントのスキル詳細（docs/kits/Tigreal.md の
// 「公式（日本語クライアント）の数値」。Liquipedia の Tigreal の AbilityCard と一致）。ウェブ調査の値と食い違うところは公式が優先。
// 対応表: 同ファイル末尾。
// サポート（ローム）の近接タンク。キットはロールの汎用パッシブ（味方回復）と汎用奥義（味方全体回復）を置き換える。
//   パッシブ 聖鎚の誓い        — 通常攻撃（タワー・ジャングルの敵を含む。ミニオンは数えない）を受ける / スキルを使うたびに「誓い」+1。
//                               4 つで次に受ける通常攻撃（タワーからの攻撃を含む）をブロック（ダメージ無効）して誓いが消える（Fearless）。
//                               時間では消えない（公式の文に期限が無い）。ミニオンのダメージは誓いを増やしも消費もしない。
//                               ブロックの瞬間は自分に 0.3 秒の「blocked」の印（.mark）が付き、パッシブのバッジが 0.3 秒だけタイマーになる（App の演出の合図）。
//   スキル1 聖槌波（Attack Wave）— 前方の台形（手前が狭く奥が広い）に衝撃波を 3 回。衝撃波は手前 → 中 → 奥へ進みながらはじける
//                               （回ごとの帯は奥行きの 0〜1/2・1/4〜3/4・1/2〜1。止まっている敵には 1〜2 回当たる）。
//                               1 回ごとに 270〜520（+70% 物理攻撃）のダメージ + 移動速度低下（20 → 40 → 60%、1.5 秒。命中した回数で深まる）。
//   スキル2 聖槌突撃（Sacred Hammer）— 突進して進路の敵に 100% 物理攻撃のダメージ（基礎ダメージなし）+ スタン、突進の終点まで押し出す。
//                               4 秒以内の再使用（同じ castSkill）で前方の敵に 280〜380（+60% 物理攻撃）+ 0.6 秒の打ち上げ。クールダウンは最初の発動から数える。
//                               突進は術者を動かすのでバインド（敵の root）中は撃てない。再使用の叩きつけは動かないので撃てる。
//                               突進はスタンでは止まらず、ノックアップ・制圧で止まる（CC の段階。KitRuntime）。
//   アルティメット 崩落聖域（Implosion） — 詠唱 1.0 秒。発動の瞬間から周囲の敵をスタンして引き寄せ（0.67 秒で集める）、1.0 秒で
//                               600 / 800 / 1000（+130% 物理攻撃）のダメージ + 残りのスタン（発動から合計 1.8 秒）。
//                               最初の 0.5 秒（前半）は CC（スタン・打ち上げ・suppress）で、その後は suppress だけで中断される。中断したら敵を放す。
//                               詠唱中の自分の足止め（root）はバインドではない（瞬歩を使える。Unit.isBound）。瞬歩の先で集め直す。
// 幾何と時間は MLBB の画面収録（訓練場のティグラル、2026-10-15）から測った値（docs/kits/Tigreal.md「動画で測った値」）。距離 = MLBB × 100。
// 数値: 公式の段の表をそのまま使う（スキル1・2 = Lv1〜6、アルティメット = Lv1〜3。rank = 公式の Lv。換算・補間なし）。
//   ダメージ = 公式の基礎[段] + 公式の係数 × 合計の物理攻撃（Kit.official。公式の文は「(+N%物理攻撃)」= 合計）。
//   クールダウン = 公式の秒数[段] × (1 − CD 短縮)（Kit.cooldown）、マナ = 公式の表（HeroKit.cost）。
//   スキル吸収率・攻撃エフェクト・ミニオン / モンスターへの補正は公式の文に無いので既定（吸収 100%・補正なし）。
//
// 状態（KitState）:
//   ints[0]  = 誓い（0..4。4 = ブロックの準備完了）    ints[1] = 奥義の段（0 = なし / 1 = 前半 / 2 = 後半）
//   ints[2]  = ブロックした回数（累計。検証用）         ints[3] = 直近の奥義で捕まえた敵の数（検証用）
//   ints[4..5] = 奥義の引き寄せの中心（整数に丸めた座標。瞬歩で動いたら集め直す）
//   timers[0] = 未使用（誓いに期限は無い）              timers[1] = 奥義の詠唱の残り秒（HUD 用）
//   timers[2] = ブロックの演出の残り秒（0.3 秒。バッジをタイマーにする）
//   reals[0..1] = S1 の方向    reals[2..3] = S2 の突進の終点    reals[4..5] = S2 再使用の方向    reals[6..7] = S2 の突進の方向

extension KitState {
    var borgVow: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    var borgUltPhase: Int {
        get { ints[1] }
        set { ints[1] = newValue }
    }

    var borgBlocks: Int {
        get { ints[2] }
        set { ints[2] = newValue }
    }

    var borgPulled: Int {
        get { ints[3] }
        set { ints[3] = newValue }
    }

    var borgChannel: Double {
        get { timers[1] }
        set { timers[1] = newValue }
    }

    var borgBlockFlash: Double {
        get { timers[2] }
        set { timers[2] = newValue }
    }

    var borgAim: Vec2 {
        get { Vec2(reals[0], reals[1]) }
        set {
            reals[0] = newValue.x
            reals[1] = newValue.y
        }
    }

    var borgDashEnd: Vec2 {
        get { Vec2(reals[2], reals[3]) }
        set {
            reals[2] = newValue.x
            reals[3] = newValue.y
        }
    }

    var borgSmashDir: Vec2 {
        get { Vec2(reals[4], reals[5]) }
        set {
            reals[4] = newValue.x
            reals[5] = newValue.y
        }
    }

    /// S2 の突進の向き（押し運ぶ向き）。S1 の向き（borgAim）とは分ける（S1 の衝撃波が走っている間に突進しても混ざらない）。
    var borgDashDir: Vec2 {
        get { Vec2(reals[6], reals[7]) }
        set {
            reals[6] = newValue.x
            reals[7] = newValue.y
        }
    }

    /// 奥義の引き寄せの中心（整数に丸めた座標）。術者がここから動いたら（瞬歩）捕まえた敵を集め直す。
    var borgPullCenter: Vec2 {
        get { Vec2(Double(ints[4]), Double(ints[5])) }
        set {
            ints[4] = Int(newValue.x.rounded())
            ints[5] = Int(newValue.y.rounded())
        }
    }
}

struct Kit_H029: HeroKit {
    let heroID = "H029"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H029(isReady: true)` を HeroKits.testOverride に差すこともできる。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    // MARK: - 数値（MLBB の値はそのまま。距離は Velstria 単位 = MLBB × 100。幾何と時間は MLBB の画面収録から測った値）
    // 計測（2026-10-15、iPhone の画面収録 30fps、訓練場の Lv4 ティグラル）: カメラの地面への写像を 2 つの同心の照準円で合わせ、
    // 縮尺を歩き（移動速度 260 = 毎秒 2.6）で決めた。誤差は距離で約 ±3%、時間は ±1 コマ（0.033 秒）。手順と数値: docs/kits/Tigreal.md、
    // 道具: tools/mlbb_video/measure.py。

    enum Tune {
        // パッシブ 聖鎚の誓い
        /// 無効化が準備できる誓いの数。
        static let vowStacks = 4
        /// 無効化の合図（自分への「blocked」の印 + パッシブのバッジのタイマー）の長さ。App の演出がこれを見て盾の弾けを出す。
        static let blockFlash = 0.3
        static let blockMark = "blocked"

        // スキル1 聖槌波（動画: 照準は台形。手前の幅 2.14・奥の幅 4.26・奥行き 6.1（MLBB の単位）。左右の辺はそれぞれ 9.9° 開く）
        /// 台形の奥行き（術者の位置から奥の辺まで）。奥の辺は僅かに丸いが直線で近似（差は角で 0.2 以下）。
        static let waveReach = 610.0
        /// 台形の半幅: 手前（術者の位置）→ 奥（waveReach）へ線形に広がる。
        static let waveNearHalfWidth = 107.0
        static let waveFarHalfWidth = 213.0
        /// 照準表示（AimShape.wideLine の帯）の半幅 = 台形の平均の半幅（HUD に台形が無いので帯で近似）。
        static let waveAimHalfWidth = 160.0
        static let waveCount = 3
        /// 衝撃波は手前から奥へ進む: k 回目の帯 = 奥行きの [waveBandStart[k], waveBandStart[k] + waveBandLength] 倍
        /// （帯の中心は 1/4・1/2・3/4。動画の 3 回の爆発の中心 = 奥行きの 0.23 / 0.52 / 0.77 倍）。帯は半分ずつ重なるので、
        /// 止まっている敵には 1〜2 回当たる（動画: 奥行きの約 0.51 倍に居た的は 2 回目と 3 回目に当たった）。
        static let waveBandStart: [Double] = [0, 0.25, 0.5]
        static let waveBandLength = 0.5
        /// 発動（指を離した瞬間）から 1 回目まで（動画: 7〜8 コマ）と、回の間隔（動画: 10 コマ = 1/3 秒）。
        static let waveFirstDelay = 0.25
        static let waveInterval = 1.0 / 3.0
        /// 命中 1 回ごとの鈍足（20 → 40 → 60%）。
        static let waveSlowPerStack = 0.20
        static let waveSlowDuration = 1.5
        static let waveSlowTag = KitTags.buff("H029", "waveSlow")
        static let waveMark = "wave"
        /// 公式の基礎ダメージ（1 回の爆発ごと。Lv1〜6）と係数（+70% 物理攻撃 = 合計の物理攻撃）。
        static let waveBase: [Double] = [270, 320, 370, 420, 470, 520]
        static let waveAttackRatio = 0.7

        // スキル2 聖槌突撃（動画: 照準の円の半径 5.56・矢印の先も同じ。実際に進んだ距離 5.23 を約 0.67 秒）
        /// 突進の距離（実際に進んだ距離。照準の円 556 より 6% 短い。円は届く先の目安で、術者の半径ぶん長いと考える）。
        static let dashRange = 525.0
        /// 突進の速さ（525 を約 0.67 秒）。
        static let dashSpeed = 780.0
        /// 経路の当たり半径（対象の半径は別に足す）。動画の照準の矢印の半幅 0.99 と同じ。
        static let dashWidth = 100.0
        /// 突進に当たった敵のスタン（動画: 当たった瞬間から「スタン」の表示と時間のバーが 20 コマ = 0.63〜0.67 秒。押し運ばれる間を含む。
        /// 公式 0.6 秒の再使用のノックアップの表示も同じ 20 コマだったので 0.6 秒とみる）。
        static let dashStun = 0.6
        /// 押し運んだ敵を突進の終点の先に置く隙間（半径どうしの和に足す）。
        static let carryGap = 20.0
        /// 到着した tick に当たった敵を押し出す最小の時間。
        static let carryMinTime = 0.12
        static let recastWindow = 4.0
        /// 再使用の振りかぶり（動画: 指を離してから打ち上げの表示まで 6〜7 コマ）。
        static let smashDelay = 0.2
        /// 再使用の範囲: 照準の円（半径 2.15）の前方の扇（照準の弧の開き ±45〜50°）。
        static let smashReach = 215.0
        static let smashHalfAngle = 0.8
        /// 打ち上げの秒数（公式 0.6 秒）。
        static let smashAirborne = 0.6
        /// 突進のダメージは (100% 物理攻撃) で基礎ダメージなし（公式の段の表は再使用のノックアップダメージだけ）。
        static let dashBase: [Double] = [0]
        static let dashAttackRatio = 1.0
        /// 再使用のノックアップダメージ（Lv1〜6）と係数（+60% 物理攻撃）。
        static let smashBase: [Double] = [280, 300, 320, 340, 360, 380]
        static let smashAttackRatio = 0.6

        // アルティメット 崩落聖域（Implosion）（動画: 照準の円の半径 2.78。発動の次のコマで「スタン」と引き寄せが始まり、
        // 0.67 秒で集まり、1.0 秒でダメージ。スタンの表示は発動から 1.77〜1.8 秒で消える）
        /// 引き寄せ・爆発の半径。
        static let ultReach = 278.0
        /// 詠唱の前半（ultGather 秒。CC で中断できる）と全体（ultTotal 秒の終わりに爆発）。前半 = 全体の半分（公式の「前半 / 後半」）。
        static let ultGather = 0.5
        static let ultTotal = 1.0
        /// 引き寄せの所要時間（発動から。爆発の前に集まり終わる）と、引き寄せた敵を置く隙間。
        static let ultPullTime = 0.67
        static let ultPullGap = 20.0
        /// スタンの合計（公式 1.8 秒。発動の瞬間から数える）。捕まえた敵は爆発まで ultHoldTag のスタン、爆発で残り（ultSlamStun）。
        static let ultStun = 1.8
        static let ultSlamStun = ultStun - ultTotal
        /// 詠唱の間に敵を捕まえておくスタンの tag の頭（術者の ID を足す。中断したら外して放す）。
        static let ultHoldTag = KitTags.buff("H029", "implosionHold")
        /// 引き寄せの間に術者がこれより動いたら（瞬歩）、新しい位置へ集め直す。
        static let ultRegatherDistance = 30.0
        /// 公式の基礎ダメージ（Lv1〜3）と係数（+130% 物理攻撃）。
        static let ultBase: [Double] = [600, 800, 1000]
        static let ultAttackRatio = 1.3
        static let channelTag = KitTags.buff("H029", "channel")
        /// ボットのアルティメット: 近くに味方ヒーロー（この距離以内）が居るか、相手の HP がこの割合未満のときだけ。敵タワーの射程内では撃たない。
        static let botAllyRange = 900.0
        static let botWeakHP = 0.5

        // クールダウン（公式の段の表の秒数。CD 短縮を掛ける）
        static let waveCooldown: [Double] = [7.0, 6.4, 5.8, 5.2, 4.6, 4.0]
        static let hammerCooldown: [Double] = [16.0, 15.4, 14.8, 14.2, 13.6, 13.0]
        static let ultCooldown: [Double] = [55, 50, 45]
        // マナ消費（公式。スキル1・2 は全段一定、アルティメットは 120 / 140 / 160）
        static let waveCost: [Double] = [45]
        static let hammerCost: [Double] = [70]
        static let ultCost: [Double] = [120, 140, 160]
    }

    /// HitPayload.kitEvent
    private enum Event {
        static let wave = 1
        static let dash = 2
    }

    /// KitTimer.code
    private enum Code {
        static let wave = 1
        static let smash = 2
        /// 奥義の前半の終わり（ここから先は suppress だけで中断される）。
        static let ultHalf = 3
        static let ultDetonate = 4
    }

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 前方の台形（判定は waveTargets）。照準表示は台形の平均の半幅の帯（HUD に台形の形が無いため）
            var t = base
            t.archetype = .cone
            t.aim = .direction
            t.range = Tune.waveReach
            t.radius = Tune.waveAimHalfWidth
            t.shape = .wideLine
            t.halfAngle = 0
            return t
        case .skill2:
            if stage >= 1 {
                // 再使用: 前方の扇を叩く（対象が居なくても撃てる）
                return SkillTargeting(archetype: .cone, aim: .direction, range: Tune.smashReach, radius: Tune.smashReach,
                                      shape: .fan, halfAngle: Tune.smashHalfAngle, recastable: true)
            }
            // 突進（経路上の敵に当たる）。radius は経路の当たり半径
            return SkillTargeting(archetype: .dashStrike, aim: .direction, range: Tune.dashRange,
                                  radius: Tune.dashWidth, shape: .dashToPoint, recastable: true)
        case .ultimate:
            // 自己中心の詠唱（敵が居なくても撃てる）。radius = 引き寄せ・爆発の半径
            return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: Tune.ultReach, shape: .selfRing)
        case .passive:
            return base
        }
    }

    /// 演出が読む時刻・寸法（Tune そのもの。App の FX_H029 は値を写さずここから読む。docs/vfx/RANGES.md）。
    func fxValues(slot: SkillSlot, stage: Int) -> [KitFXValue] {
        switch slot {
        case .skill1:
            return [KitFXValue("waveFirstDelay", Tune.waveFirstDelay, .seconds),
                    KitFXValue("waveInterval", Tune.waveInterval, .seconds),
                    KitFXValue("waveCount", Double(Tune.waveCount), .count),
                    KitFXValue("waveReach", Tune.waveReach, .distance),
                    KitFXValue("waveNearHalfWidth", Tune.waveNearHalfWidth, .distance),
                    KitFXValue("waveFarHalfWidth", Tune.waveFarHalfWidth, .distance),
                    KitFXValue("waveBandStart", list: Tune.waveBandStart, .ratio),
                    KitFXValue("waveBandLength", Tune.waveBandLength, .ratio),
                    // 照準の帯の縁を判定の台形に（App の AimLayer.taper。照準の数値 waveAimHalfWidth は変えない）
                    KitFXValue("aimNearHalfWidth", Tune.waveNearHalfWidth, .distance),
                    KitFXValue("aimFarHalfWidth", Tune.waveFarHalfWidth, .distance)]
        case .skill2 where stage >= 1:
            return [KitFXValue("smashDelay", Tune.smashDelay, .seconds), KitFXValue("smashReach", Tune.smashReach, .distance),
                    KitFXValue("smashHalfAngle", Tune.smashHalfAngle, .radians),
                    KitFXValue("smashAirborne", Tune.smashAirborne, .seconds)]
        case .skill2:
            return [KitFXValue("dashRange", Tune.dashRange, .distance), KitFXValue("dashSpeed", Tune.dashSpeed, .speed),
                    KitFXValue("dashWidth", Tune.dashWidth, .distance), KitFXValue("dashStun", Tune.dashStun, .seconds),
                    KitFXValue("recastWindow", Tune.recastWindow, .seconds)]
        case .ultimate:
            return [KitFXValue("ultReach", Tune.ultReach, .distance), KitFXValue("ultGather", Tune.ultGather, .seconds),
                    KitFXValue("ultTotal", Tune.ultTotal, .seconds), KitFXValue("ultPullTime", Tune.ultPullTime, .seconds),
                    KitFXValue("ultStun", Tune.ultStun, .seconds)]
        case .passive:
            return [KitFXValue("blockFlash", Tune.blockFlash, .seconds)]
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
            n.extras = [KitStat(key: "vows", value: Double(Tune.vowStacks))]
        case .skill1:
            n.hits = Tune.waveCount
            n.damage = Self.waveDamage(rank: rank, stats: stats)
            n.cooldown = Kit.cooldown(Tune.waveCooldown, rank: rank, stats: stats)
            n.cc = .slow
            n.ccDuration = Tune.waveSlowDuration
            n.extras = [KitStat(key: "slow1", value: Tune.waveSlowPerStack * 100),
                        KitStat(key: "slow2", value: Tune.waveSlowPerStack * 200),
                        KitStat(key: "slow3", value: Tune.waveSlowPerStack * 300),
                        KitStat(key: "slowDuration", value: Tune.waveSlowDuration),
                        KitStat(key: "reachMult", value: Tune.waveReach / hero.attackRange),
                        KitStat(key: "base", value: Kit.level(Tune.waveBase, rank: rank)),
                        KitStat(key: "atkPct", value: Self.percent(Tune.waveAttackRatio))]
        case .skill2:
            let dash = Self.dashDamage(stats: stats)
            let smash = Self.smashDamage(rank: rank, stats: stats)
            n.hits = 1
            n.damage = stage >= 1 ? smash : dash
            n.cc = stage >= 1 ? .knockback : .stun
            n.ccDuration = stage >= 1 ? Tune.smashAirborne : Tune.dashStun
            n.cooldown = Kit.cooldown(Tune.hammerCooldown, rank: rank, stats: stats)
            n.stages = 2
            n.recastWindow = Tune.recastWindow
            n.extras = [KitStat(key: "dashDamage", value: dash.rounded()),
                        KitStat(key: "smashDamage", value: smash.rounded()),
                        KitStat(key: "airborne", value: Tune.smashAirborne),
                        KitStat(key: "window", value: Tune.recastWindow),
                        KitStat(key: "dashPct", value: Self.percent(Tune.dashAttackRatio)),
                        KitStat(key: "smashBase", value: Kit.level(Tune.smashBase, rank: rank)),
                        KitStat(key: "smashPct", value: Self.percent(Tune.smashAttackRatio)),
                        KitStat(key: "dashStun", value: Tune.dashStun)]
        case .ultimate:
            n.hits = 1
            n.damage = Self.ultDamage(rank: rank, stats: stats)
            n.cc = .stun
            n.ccIsUltimate = true
            n.ccDuration = Tune.ultStun
            // 汎用の味方全体回復は持たない
            n.heal = 0
            n.shield = 0
            n.shieldDuration = 0
            n.damageReduction = 0
            n.damageReductionDuration = 0
            n.cooldown = Kit.cooldown(Tune.ultCooldown, rank: rank, stats: stats)
            n.extras = [KitStat(key: "stun", value: Tune.ultStun),
                        KitStat(key: "channel", value: Tune.ultTotal),
                        KitStat(key: "gather", value: Tune.ultGather),
                        KitStat(key: "reachMult", value: Tune.ultReach / hero.attackRange),
                        KitStat(key: "base", value: Kit.level(Tune.ultBase, rank: rank)),
                        KitStat(key: "atkPct", value: Self.percent(Tune.ultAttackRatio))]
        }
        return n
    }

    /// 段ごとのマナ消費（公式: スキル1 = 45、スキル2 = 70、アルティメット = 120 / 140 / 160）。
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double {
        let table: [Double]
        switch slot {
        case .skill1: table = Tune.waveCost
        case .skill2: table = Tune.hammerCost
        case .ultimate: table = Tune.ultCost
        case .passive: return base
        }
        return HeroKits.resourceCost(Kit.level(table, rank: rank), hero: hero)
    }

    /// 説明文は公式の文の構造に合わせる（数値は {トークン} で sim から。{base}(+{atkPct}%物理攻撃) は公式の値そのまま）。
    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "通常攻撃を受けるたびに、聖鎚の誓いを1スタック獲得する。{vows}スタックに達すると、それらを消費して次に受ける通常攻撃（タワーからの攻撃を含む）をブロックする。また、スキルを発動するたびに、聖鎚の誓いを1スタック獲得する。\n\nミニオンからのダメージは、聖鎚の誓いのスタックを付与または消費しない。",
                en: "Each time you take a basic attack, gain 1 stack of Sacred Oath. At {vows} stacks, consume them to block the next basic attack you take (including attacks from towers). Also gain 1 stack of Sacred Oath each time you cast a skill.\n\nDamage from minions neither grants nor consumes Sacred Oath stacks.",
                tags: [KitTag.buff])
        case .skill1:
            return KitText(
                ja: "ハンマーで地面を叩き、扇形範囲で{hits}回爆発する衝撃波を放つ（範囲の奥行きは近接攻撃の射程の約{reachMult}倍。衝撃波は手前から奥へ進みながら爆発する）。各爆発は命中した敵に{base}(+{atkPct}%物理攻撃)の物理ダメージを与え、移動速度を{slowDuration}秒間{slow1}%/{slow2}%/{slow3}%低下させる（同じ敵に命中した爆発の数で深くなる）。",
                en: "Slam the ground with the hammer, sending out a shockwave that erupts {hits} times in a fan (the area reaches about {reachMult}x your melee attack range; the shockwave erupts from near to far as it travels). Each eruption deals {base} (+{atkPct}% Physical Attack) physical damage to enemies hit and slows their movement speed by {slow1}%/{slow2}%/{slow3}% for {slowDuration}s (deeper with each eruption that hits the same enemy).",
                tags: [KitTag.aoe, KitTag.slow])
        case .skill2:
            return KitText(
                ja: "指定方向へ突進し、進路上の敵に({dashPct}%物理攻撃)の物理ダメージを与えて突進の終点まで押し出す（押し出された敵は{dashStun}秒間スタン）。\n\n再発動：{window}秒以内にもう一度使うと、前方の敵に{smashBase}(+{smashPct}%物理攻撃)の物理ダメージを与えて{airborne}秒間ノックアップさせる。",
                en: "Charge in the specified direction, dealing physical damage equal to {dashPct}% of your Physical Attack to enemies along the way and pushing them to the end of the charge (pushed enemies are stunned for {dashStun}s).\n\nRecast: use it again within {window}s to deal {smashBase} (+{smashPct}% Physical Attack) physical damage to enemies in front of you and knock them up for {airborne}s.",
                tags: [KitTag.clash, KitTag.disrupt])
        case .ultimate:
            return KitText(
                ja: "ハンマーの力を解放し、周囲（近接攻撃の射程の約{reachMult}倍）の敵を引き寄せて{base}(+{atkPct}%物理攻撃)の物理ダメージを与え、{stun}秒間スタンさせる（引き寄せとスタンは発動の瞬間から、ダメージは{channel}秒後）。\n\nスキルの前半（最初の{gather}秒）はコントロール効果によって中断されるが、後半は制圧によってのみ中断される。",
                en: "Unleash the power of the hammer, pulling in nearby enemies (within about {reachMult}x your melee attack range), dealing {base} (+{atkPct}% Physical Attack) physical damage and stunning them for {stun}s (the pull and the stun start at once; the damage lands after {channel}s).\n\nThe first half of the skill (the first {gather}s) can be interrupted by control effects, but the second half can only be interrupted by suppression.",
                tags: [KitTag.disrupt, KitTag.aoe])
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            // 無効化した直後の 0.3 秒だけタイマー（誓いが 4 → 0 になった合図。App の演出がタイマーの開始を見て盾の弾けを出す）
            if k.borgBlockFlash > 0 { return KitBadge(kind: .timer, remaining: k.borgBlockFlash, total: Tune.blockFlash) }
            return KitBadge(kind: .stacks, value: min(k.borgVow, Tune.vowStacks), maxValue: Tune.vowStacks)
        case .ultimate:
            guard k.borgUltPhase != 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.borgChannel, total: Tune.ultTotal)
        default:
            return nil
        }
    }

    // MARK: - B. 実行

    func resolveAim(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot, stage: Int,
                    targeting: SkillTargeting, target: SkillTarget) -> SkillAim?? {
        switch slot {
        case .ultimate:
            // 自己中心の詠唱: 敵が居なくても撃てる
            let facing = Vec2.fromAngle(s.units[caster].facing)
            return .some(SkillAim(direction: facing, point: s.units[caster].pos, unit: nil, distance: 0))
        case .skill2 where stage >= 1:
            // 詠唱中（奥義）は再使用できない
            if (s.units[caster].hero?.kit?.borgUltPhase ?? 0) != 0 { return .some(nil) }
            return nil
        default:
            return nil
        }
    }

    func canStart(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) -> Bool {
        // 奥義の詠唱中は、ほかのスキルを始められない
        (s.units[caster].hero?.kit?.borgUltPhase ?? 0) == 0
    }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        switch c.slot {
        case .skill1: castWave(&s, c)
        case .skill2: castCharge(&s, ctx, c)
        case .ultimate: castImplosion(&s, ctx, c)
        case .passive: break
        }
        return .done
    }

    /// S1: 発動の方向と原点に 3 回、台形の衝撃波を手前から奥へ起こす（途中でスタンされても止まらない: すでに地面に走った衝撃波）。
    private func castWave(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        let origin = s.units[i].pos
        let dir = c.aim.direction
        s.units[i].hero!.kit!.borgAim = dir
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * Tune.waveReach, unit: c.aim.unit, shape: .wideLine,
                     halfAngle: 0, duration: Tune.waveFirstDelay + Tune.waveInterval * Double(Tune.waveCount - 1),
                     count: Tune.waveCount)
        Kit.strikeSequence(&s, caster: i, slot: .skill1, code: Code.wave, count: Tune.waveCount,
                           interval: Tune.waveInterval, firstDelay: Tune.waveFirstDelay, param: c.numbers.damage,
                           point: origin, interruptible: false)
    }

    /// S2 の 1 回目: 突進。通り道の敵にダメージ + スタンを与え、突進の終点まで押し運ぶ。再使用の窓を開く。
    /// クールダウンは最初の発動から数える（動画: 再使用の前から CD の表示が 16 秒から減っていた）。
    private func castCharge(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let from = s.units[i].pos
        let dir = c.aim.direction
        let stun = StatusEffect(kind: .stun, duration: Tune.dashStun, sourceID: s.units[i].id, tag: CombatSystem.tagStun)
        var p = HitPayload(damage: c.numbers.damage, damageType: .physical, source: .skill(.skill2), statuses: [stun],
                           skillID: c.check.skill.skillID, kitEvent: Event.dash)
        p.originPos = from
        let landing = Kit.dashSweeping(&s, ctx, caster: i, slot: .skill2, to: from + dir * Tune.dashRange,
                                       speed: Tune.dashSpeed, payload: p, radius: Tune.dashWidth)
        let actual = (landing - from).normalized
        s.units[i].hero!.kit!.borgDashDir = actual == .zero ? dir : actual
        s.units[i].hero!.kit!.borgDashEnd = landing
        Kit.emitCast(&s, c, origin: from, target: landing, unit: c.aim.unit, shape: .dashToPoint,
                     duration: from.distance(to: landing) / Tune.dashSpeed, count: 1)
        // 最初の発動のコスト・CD は消費済み。窓を閉じても CD は変えない
        Kit.openRecast(&s, caster: i, slot: .skill2, duration: Tune.recastWindow, stage: 1, charges: 1)
    }

    /// S2 の再使用: 短い振りかぶりのあと、前方の扇を叩いて打ち上げる。
    func recast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast, window: RecastWindow) {
        guard c.slot == .skill2 else {
            Kit.closeRecast(&s, ctx, caster: c.caster, slot: c.slot)
            return
        }
        let i = c.caster
        let origin = s.units[i].pos
        let dir = c.aim.direction
        s.units[i].hero!.kit!.borgSmashDir = dir
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * Tune.smashReach, unit: c.aim.unit, shape: .fan,
                     halfAngle: Tune.smashHalfAngle, duration: Tune.smashDelay, count: 1)
        Kit.schedule(&s, caster: i, slot: .skill2, code: Code.smash, after: Tune.smashDelay, param: c.numbers.damage,
                     point: origin, interruptible: true)
        Kit.advanceRecast(&s, ctx, caster: i, slot: .skill2)
    }

    /// 奥義: 詠唱の開始。発動の瞬間に周囲の敵を捕まえて（スタン + 引き寄せ）、前半（ultGather 秒）の終わりから後半、
    /// 詠唱の終わり（ultTotal 秒）に爆発（onTimer）。引き寄せの間（ultPullTime 秒）に瞬歩で動いたら update が新しい位置へ集め直す。
    /// 引き寄せの途中で半径へ入ってきた敵は捕まえない（爆発の瞬間に半径内ならダメージと残りのスタン）。
    private func castImplosion(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let pos = s.units[i].pos
        Kit.emitCast(&s, c, origin: pos, target: pos, shape: .selfRing, duration: Tune.ultTotal, count: 2)
        beginChannel(&s, i)
        s.units[i].hero!.kit!.borgPulled = 0
        s.units[i].hero!.kit!.borgPullCenter = pos
        gather(&s, ctx, owner: i, elapsed: 0, regather: false)
        // 前半（CC で中断できる）の終わり。それ以降は suppress だけで中断される（CC では取り消されない）
        Kit.schedule(&s, caster: i, slot: .ultimate, code: Code.ultHalf, after: Tune.ultGather, interruptible: true)
        Kit.schedule(&s, caster: i, slot: .ultimate, code: Code.ultDetonate, after: Tune.ultTotal,
                     param: c.numbers.damage, interruptible: false)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        switch timer.code {
        case Code.wave: erupt(&s, ctx, owner: owner, timer: timer)
        case Code.smash: smash(&s, ctx, owner: owner, timer: timer)
        case Code.ultHalf: enterSecondHalf(&s, owner: owner)
        case Code.ultDetonate: detonate(&s, ctx, owner: owner, timer: timer)
        default: break
        }
    }

    /// スキル1 の 1 回ぶん: 台形の k 回目の帯（waveTargets）にダメージ + 鈍足の層（命中ごとに 1 層、最大 3 層）。
    /// 帯は回ごとに奥へ進む（timer.index 0 → 2）: 止まっている敵には 1〜2 回、衝撃波と一緒に奥へ逃げる敵には 3 回当たる。
    private func erupt(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard let dir = s.units[owner].hero?.kit?.borgAim, dir != .zero else { return }
        let p = HitPayload(damage: timer.param, damageType: .physical, source: .skill(.skill1),
                           skillID: Self.skillID(ctx, .skill1),
                           effects: [.addMark(name: Tune.waveMark, stacks: 1, maxStacks: Tune.waveCount,
                                              duration: Tune.waveSlowDuration)],
                           kitEvent: Event.wave)
        // 検証用の観測: この回の台形の帯（受け口が無ければ何もしない。docs/vfx/RANGES.md）
        HitShapeProbe.emit(.kit(.polygon(Self.waveBand(origin: timer.point, direction: dir, eruption: timer.index)), s,
                                caster: owner, source: .skill(.skill1)))
        let targets = Self.waveTargets(s, owner: owner, origin: timer.point, direction: dir, eruption: timer.index)
        guard !targets.isEmpty else { return }
        let casterID = s.units[owner].id
        let team = s.units[owner].team
        for j in targets {
            CombatSystem.applyHit(&s, ctx, sourceID: casterID, team: team, targetIndex: j, payload: p, from: timer.point)
        }
    }

    /// スキル1 の k 回目の衝撃波が当たる敵（構造物・死亡を除く。添字昇順）。台形 = origin から direction へ奥行き waveReach、
    /// 半幅は手前 waveNearHalfWidth → 奥 waveFarHalfWidth（線形）。k 回目の帯 = 奥行きの [waveBandStart[k], + waveBandLength] 倍。
    /// 帯の前後は対象の中心で見る（帯の境目は衝撃波の位置で、隣の帯と重なる）。台形の外周（手前・奥・左右の辺）は対象の半径まで含む。
    static func waveTargets(_ s: SimState, owner i: Int, origin: Vec2, direction: Vec2, eruption k: Int) -> [Int] {
        let dir = direction.normalized
        guard dir != .zero else { return [] }
        let team = s.units[i].team
        let last = Tune.waveBandStart.count - 1
        let band = min(max(0, k), last)
        let lo = Tune.waveBandStart[band] * Tune.waveReach
        let hi = (Tune.waveBandStart[band] + Tune.waveBandLength) * Tune.waveReach
        var out: [Int] = []
        for j in s.units.indices where s.units[j].team != team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j) else { continue }
            let r = s.units[j].radius
            let rel = s.units[j].pos - origin
            let along = rel.dot(dir)
            // 前後: 帯の中（最初の帯の手前・最後の帯の奥は台形の辺なので対象の半径まで）
            guard along >= (band == 0 ? -r : lo), along <= (band == last ? Tune.waveReach + r : hi) else { continue }
            // 左右: その奥行きでの台形の半幅 + 対象の半径
            let f = min(max(along, 0), Tune.waveReach) / Tune.waveReach
            let half = Tune.waveNearHalfWidth + (Tune.waveFarHalfWidth - Tune.waveNearHalfWidth) * f
            guard abs(rel.x * dir.y - rel.y * dir.x) <= half + r else { continue }
            out.append(j)
        }
        return out
    }

    /// スキル1 の k 回目の帯の形（waveTargets と同じ寸法。対象の半径は含まない）: 手前の左・奥の左・奥の右・手前の右。
    /// 最初の帯の手前は台形の手前の辺（奥行き 0）、最後の帯の奥は台形の奥の辺（waveReach）。
    static func waveBand(origin: Vec2, direction: Vec2, eruption k: Int) -> [Vec2] {
        let dir = direction.normalized
        guard dir != .zero else { return [] }
        let last = Tune.waveBandStart.count - 1
        let band = min(max(0, k), last)
        let lo = band == 0 ? 0 : Tune.waveBandStart[band] * Tune.waveReach
        let hi = band == last ? Tune.waveReach : (Tune.waveBandStart[band] + Tune.waveBandLength) * Tune.waveReach
        let left = Vec2(-dir.y, dir.x)
        func half(_ along: Double) -> Double {
            Tune.waveNearHalfWidth + (Tune.waveFarHalfWidth - Tune.waveNearHalfWidth) * along / Tune.waveReach
        }
        return [origin + dir * lo + left * half(lo), origin + dir * hi + left * half(hi),
                origin + dir * hi - left * half(hi), origin + dir * lo - left * half(lo)]
    }

    /// S2 の再使用: 今の位置から前方の扇へダメージ + 打ち上げ。
    private func smash(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard let dir = s.units[owner].hero?.kit?.borgSmashDir, dir != .zero else { return }
        let p = HitPayload(damage: timer.param, damageType: .physical, source: .skill(.skill2),
                           skillID: Self.skillID(ctx, .skill2), effects: [.knockUp(duration: Tune.smashAirborne)])
        SkillArchetypes.hitArea(&s, ctx, caster: owner, center: s.units[owner].pos, radius: Tune.smashReach,
                                shape: .cone(direction: dir, halfAngle: Tune.smashHalfAngle), payload: p)
    }

    /// 奥義で捕まえておくスタンの tag（術者ごと。別のボルグの奥義と混ざらない）。
    static func holdTag(_ owner: EntityID) -> String { Tune.ultHoldTag + ".\(owner)" }

    /// 敵 j を owner（EntityID）の奥義が捕まえているか（爆発までのスタンが残っている）。
    static func isHeld(_ s: SimState, _ j: Int, by owner: EntityID) -> Bool {
        let tag = holdTag(owner)
        return s.units[j].statuses.contains { $0.kind == .stun && $0.tag == tag }
    }

    /// 奥義の引き寄せ: 今の位置の半径内の敵（構造物を除く）を捕まえる（爆発までスタン + 術者の元へ集める）。elapsed = 発動からの秒。
    /// 集め終わりは発動から ultPullTime 秒（引き寄せの最中に捕まえた敵も同じ時刻に着く）。CC 無効・無敵の相手は捕まらない（爆発のダメージだけ）。
    /// regather = 術者が瞬歩で動いた: 捕まえている敵も新しい位置へ集め直し、新しい位置の半径内の敵も捕まえる。
    private func gather(_ s: inout SimState, _ ctx: SimContext, owner: Int, elapsed: Double, regather: Bool) {
        let team = s.units[owner].team
        let id = s.units[owner].id
        let tag = Self.holdTag(id)
        let center = s.units[owner].pos
        let pullLeft = max(Balance.dt, Tune.ultPullTime - elapsed)
        let holdLeft = max(Balance.dt, Tune.ultTotal - elapsed)
        // 検証用の観測: 捕まえる円（発動の瞬間と、瞬歩で集め直した位置）
        HitShapeProbe.emit(.kit(.circle(center: center, radius: Tune.ultReach, inner: 0), s, caster: owner,
                                source: .skill(.ultimate)))
        var caught = 0
        for j in s.units.indices where s.units[j].team != team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j) else { continue }
            if !Self.isHeld(s, j, by: id) {
                let reach = Tune.ultReach + s.units[j].radius
                guard s.units[j].pos.distanceSquared(to: center) <= reach * reach, Kit.canDisplace(s, ctx, j) else { continue }
                CombatSystem.addStatus(&s, targetIndex: j, StatusEffect(kind: .stun, duration: holdLeft, sourceID: id,
                                                                        tag: tag))
                guard Self.isHeld(s, j, by: id) else { continue }
                caught += 1
            } else if !regather {
                continue
            }
            let gap = s.units[owner].radius + s.units[j].radius + Tune.ultPullGap
            Kit.pull(&s, ctx, target: j, toward: center, distance: s.units[j].pos.distance(to: center),
                     duration: pullLeft, gap: gap)
        }
        if caught > 0 { s.units[owner].hero!.kit!.borgPulled += caught }
    }

    /// 捕まえた敵を放す（爆発までのスタンを外す）。stopPull = 引き寄せの途中でも止める（詠唱を中断したとき）。
    private func releaseHeld(_ s: inout SimState, owner: Int, stopPull: Bool) {
        let tag = Self.holdTag(s.units[owner].id)
        for j in s.units.indices {
            guard s.units[j].statuses.contains(where: { $0.kind == .stun && $0.tag == tag }) else { continue }
            s.units[j].statuses.removeAll { $0.kind == .stun && $0.tag == tag }
            if stopPull, let d = s.units[j].displacement, d.kind == .knockback { s.units[j].displacement = nil }
        }
    }

    /// 奥義の前半の終わり: ここから先は CC では止まらず、suppress だけが詠唱を止める。
    private func enterSecondHalf(_ s: inout SimState, owner: Int) {
        guard s.units[owner].hero?.kit?.borgUltPhase == 1 else { return }
        s.units[owner].hero!.kit!.borgUltPhase = 2
    }

    /// 奥義の取り消し（前半の CC・後半の suppress・予約の消失）: 爆発を捨て、捕まえた敵を放して詠唱を終える（クールダウンは戻らない）。
    private func cancelImplosion(_ s: inout SimState, owner: Int) {
        Kit.cancelScheduled(&s, caster: owner, slot: .ultimate)
        releaseHeld(&s, owner: owner, stopPull: true)
        endChannel(&s, owner)
    }

    /// 奥義の爆発: 周囲の敵にダメージ + 残りのスタン（ultSlamStun。捕まえておくスタンと合わせて発動から ultStun 秒）。
    /// suppress を受けていれば不発（捕まえた敵は放す）。
    private func detonate(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard s.units[owner].hero?.kit?.borgUltPhase == 2 else { return }
        endChannel(&s, owner)
        releaseHeld(&s, owner: owner, stopPull: false)
        guard !s.units[owner].has(.suppress) else { return }
        let stun = StatusEffect(kind: .stun, duration: Tune.ultSlamStun, sourceID: s.units[owner].id,
                                tag: CombatSystem.tagStun)
        let p = HitPayload(damage: timer.param, damageType: .physical, source: .skill(.ultimate), statuses: [stun],
                           skillID: Self.skillID(ctx, .ultimate))
        SkillArchetypes.hitArea(&s, ctx, caster: owner, center: s.units[owner].pos, radius: Tune.ultReach,
                                shape: .circle, payload: p)
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let k = s.units[owner].hero?.kit else { return }
        guard k.borgUltPhase != 0 else { return }
        // 後半は suppress だけが詠唱を止める（前半は KitRuntime がハード CC で取り消す → onInterrupted）
        if k.borgUltPhase == 2, s.units[owner].has(.suppress) {
            cancelImplosion(&s, owner: owner)
            return
        }
        // 詠唱中は動かず、攻撃も始めない
        s.units[owner].attackTargetID = nil
        s.units[owner].windupRemaining = nil
        s.units[owner].moveIntent = .none
        // 引き寄せの間に術者が動いた（瞬歩）: 新しい位置へ集め直す
        let elapsed = Tune.ultTotal - k.borgChannel
        if elapsed < Tune.ultPullTime, s.units[owner].pos.distance(to: k.borgPullCenter) > Tune.ultRegatherDistance {
            s.units[owner].hero!.kit!.borgPullCenter = s.units[owner].pos
            gather(&s, ctx, owner: owner, elapsed: elapsed, regather: true)
        }
        // 予約が消えていたら（想定外の取り消し）詠唱を終える
        if Kit.scheduledCount(s, caster: owner, code: Code.ultHalf) + Kit.scheduledCount(s, caster: owner, code: Code.ultDetonate) == 0 {
            cancelImplosion(&s, owner: owner)
        }
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // 前半に CC を受けた: 前半の終わりの予約が消えたので、爆発の予約も捨て、捕まえた敵を放して詠唱を終える
        guard s.units[owner].hero?.kit?.borgUltPhase == 1 else { return }
        cancelImplosion(&s, owner: owner)
    }

    // MARK: - C. パッシブ（聖鎚の誓い）

    func onSkillCast(_ s: inout SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) {
        guard slot != .passive else { return }
        gainVow(&s, caster)
    }

    func modifyIncomingDamage(_ s: inout SimState, _ ctx: SimContext, victim: Int, attacker: Int?,
                              source: DamageSource, amount: Double) -> Double {
        // 通常攻撃（ヒーロー・タワー・ジャングルの敵）だけが対象。ミニオンの攻撃・スキル・継続ダメージは誓いを増やしも消費もしない
        switch source {
        case .basicAttack, .tower, .monster: break
        default: return amount
        }
        guard let k = s.units[victim].hero?.kit else { return amount }
        if k.borgVow >= Tune.vowStacks {
            s.units[victim].hero!.kit!.borgVow = 0
            s.units[victim].hero!.kit!.borgBlocks = k.borgBlocks + 1
            // 無効化の合図: 自分に 0.3 秒の「blocked」の印 + パッシブのバッジを 0.3 秒だけタイマーにする（誓いの 4 → 0 を App が見分けられる）
            s.units[victim].hero!.kit!.borgBlockFlash = Tune.blockFlash
            let id = s.units[victim].id
            Kit.addMark(&s, target: victim, ownerID: id, tag: KitTags.mark("H029", Tune.blockMark, owner: id),
                        maxStacks: 1, duration: Tune.blockFlash)
            return 0
        }
        gainVow(&s, victim)
        return amount
    }

    // MARK: - D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        let me = s.units[bot].pos
        switch slot {
        case .skill2:
            // 再使用: 敵が前方の扇に入っているか、窓が閉じそうなら叩く
            guard let w = Kit.window(s, caster: bot, slot: .skill2) else { return .useDefault }
            let delta = s.units[target].pos - me
            let dir = delta.normalized
            let reach = Tune.smashReach * 0.85 + s.units[target].radius
            guard dir != .zero, delta.length <= reach || w.remaining < 0.8 else { return .skip }
            return .cast(.direction(dir))
        case .ultimate:
            // 敵ヒーローを 2 体以上巻き込めるか、狙う相手が傷ついているときだけ。さらに、近くに味方ヒーローが居るか
            // 相手の HP が半分未満のときだけ（引き寄せた相手を一人で受けない）。敵タワーの射程内では撃たない
            guard fighting else { return .skip }
            let team = s.units[bot].team
            var heroes = 0
            for j in s.units.indices where s.units[j].kind == .hero && s.units[j].team != team {
                guard CombatSystem.isLiving(s, j), s.isTargetableEnemy(j, of: team) else { continue }
                let reach = Tune.ultReach + s.units[j].radius
                if s.units[j].pos.distanceSquared(to: me) <= reach * reach { heroes += 1 }
            }
            guard heroes >= 2 || (heroes == 1 && s.units[target].hpRatio < 0.8) else { return .skip }
            var supported = s.units[target].hpRatio < Tune.botWeakHP
            if !supported {
                for j in s.units.indices where j != bot && s.units[j].kind == .hero && s.units[j].team == team {
                    guard CombatSystem.isLiving(s, j) else { continue }
                    if s.units[j].pos.distanceSquared(to: me) <= Tune.botAllyRange * Tune.botAllyRange {
                        supported = true
                        break
                    }
                }
            }
            guard supported, !Self.insideEnemyTowerRange(s, bot: bot) else { return .skip }
            return .cast(.none)
        default:
            return .useDefault
        }
    }

    // MARK: - 部品

    /// 敵の構造物（タワー・コア）の攻撃が届く距離か（TowerSystem.inReach と同じ基準: 射程 + 双方の半径）。
    static func insideEnemyTowerRange(_ s: SimState, bot: Int) -> Bool {
        let me = s.units[bot]
        for j in s.units.indices where s.units[j].isStructure && s.units[j].team != me.team {
            guard CombatSystem.isLiving(s, j), s.units[j].stats.attackRange > 0 else { continue }
            let reach = s.units[j].stats.attackRange + s.units[j].radius + me.radius
            if s.units[j].pos.distanceSquared(to: me.pos) <= reach * reach { return true }
        }
        return false
    }

    private func gainVow(_ s: inout SimState, _ i: Int) {
        guard let k = s.units[i].hero?.kit else { return }
        s.units[i].hero!.kit!.borgVow = min(Tune.vowStacks, k.borgVow + 1)
    }

    /// 詠唱の開始: 溜めに入り、その場から動けない。攻撃も始めない。
    private func beginChannel(_ s: inout SimState, _ i: Int) {
        let id = s.units[i].id
        s.units[i].hero!.kit!.borgUltPhase = 1
        s.units[i].hero!.kit!.borgChannel = Tune.ultTotal
        s.units[i].attackTargetID = nil
        s.units[i].windupRemaining = nil
        s.units[i].moveIntent = .none
        s.units[i].path.removeAll()
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .root, duration: Tune.ultTotal, sourceID: id,
                                                                 tag: Tune.channelTag))
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .channeling, duration: Tune.ultTotal,
                                                                 sourceID: id, tag: Tune.channelTag))
    }

    private func endChannel(_ s: inout SimState, _ i: Int) {
        s.units[i].hero?.kit?.borgUltPhase = 0
        s.units[i].hero?.kit?.borgChannel = 0
        s.units[i].statuses.removeAll { ($0.kind == .root || $0.kind == .channeling) && $0.tag == Tune.channelTag }
    }

    /// 突進に巻き込んだ敵を、突進の終点の先まで同じ向きに押し運ぶ（到着に間に合う速さで）。CC 無効の相手は動かない。
    private func carry(_ s: inout SimState, _ ctx: SimContext, owner: Int, target t: Int) {
        guard Kit.canDisplace(s, ctx, t), let k = s.units[owner].hero?.kit else { return }
        var dir = k.borgDashDir
        if dir == .zero { dir = Vec2.fromAngle(s.units[owner].facing) }
        let remaining: Double
        if let d = s.units[owner].displacement, d.kind == .dash {
            remaining = max(Balance.dt, d.duration - d.elapsed)
        } else {
            remaining = Tune.carryMinTime
        }
        let ahead = max(0, (k.borgDashEnd - s.units[t].pos).dot(dir))
        let gap = s.units[owner].radius + s.units[t].radius + Tune.carryGap
        MovementSystem.knockback(&s, ctx, unitIndex: t, direction: dir, distance: ahead + gap, duration: remaining)
    }

    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {
        switch event {
        case Event.dash:
            carry(&s, ctx, owner: owner, target: target)
        case Event.wave:
            // 鈍足は命中ごとに深まる: 20% × 層（1.5 秒、層は命中のたびに持続が戻る）
            let tag = KitTags.mark("H029", Tune.waveMark, owner: s.units[owner].id)
            let stacks = Kit.markStacks(s, target: target, tag: tag)
            guard stacks > 0, CombatSystem.isLiving(s, target) else { return }
            let slow = StatusEffect(kind: .slow, duration: Tune.waveSlowDuration,
                                    magnitude: Tune.waveSlowPerStack * Double(stacks), sourceID: s.units[owner].id,
                                    tag: Tune.waveSlowTag)
            CombatSystem.addStatus(&s, targetIndex: target, slow)
        default:
            break
        }
    }

    /// 公式の係数（0.7 など）を説明文の「+N%」の N にする（70 など。丸めの誤差を残さない）。
    static func percent(_ ratio: Double) -> Double {
        (ratio * 100).rounded()
    }

    /// スキル1: 1 回の爆発のダメージ（公式: 270 / 320 / 370 / 420 / 470 / 520（+70% 物理攻撃））。
    static func waveDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.waveBase, rank: rank, ratio: Tune.waveAttackRatio, .totalAttack, stats: stats)
    }

    /// スキル2 の突進のダメージ（公式: (100% 物理攻撃)。基礎ダメージなし・全段同じ）。
    static func dashDamage(stats: Stats) -> Double {
        Kit.official(Tune.dashBase, rank: 1, ratio: Tune.dashAttackRatio, .totalAttack, stats: stats)
    }

    /// スキル2 の再使用のダメージ（公式: 280 / 300 / 320 / 340 / 360 / 380（+60% 物理攻撃））。
    static func smashDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.smashBase, rank: rank, ratio: Tune.smashAttackRatio, .totalAttack, stats: stats)
    }

    /// 奥義のダメージ（公式: 600 / 800 / 1000（+130% 物理攻撃））。
    static func ultDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.ultBase, rank: rank, ratio: Tune.ultAttackRatio, .totalAttack, stats: stats)
    }

    static func skillID(_ ctx: SimContext, _ slot: SkillSlot) -> String? {
        ctx.master.skill(hero: "H029", slot: slot)?.skillID
    }
}
