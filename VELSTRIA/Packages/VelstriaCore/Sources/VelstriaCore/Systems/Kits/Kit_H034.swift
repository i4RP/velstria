import Foundation

// 担当: kit-H034（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Franco.md）
// H034 鎖鉤のゴルム = Velstria 版の Franco（MLBB。調査: docs/kits/Franco.md、対応表: 同ファイル末尾）。
// 数値の正は MLBB の日本語クライアントのスキル詳細（docs/kits/Franco.md の「公式（日本語クライアント）の数値」）。
// 公式の表をそのまま使う（スキル1・2 = Lv1〜6、アルティメット = Lv1〜3。rank = 公式の Lv。換算・補間なし）。
//   パッシブ 鉄鎖の執念    — 5 秒ダメージを受けないと 移動速度 +10%・毎秒 最大 HP の 1% 回復、闘気がたまる（最大 10）。ダメージで解除。
//                           次のスキルのダメージが当たった時に闘気をすべて消費し、そのスキルのダメージを 1 つにつき +5%（10 で +50% =
//                           1.5 倍。公式の「最大150%」は 150% まで = 1.5 倍。動画で測った値）。外れたスキル（誰にも当たらない）は消費しない。
//                           奥義は 1 撃ごとにその時の闘気を掛け、最後の 1 撃（途中で終われば、その時）で消費する。
//                           たまる速さ（1 秒に 1 つ）は推測（公式の文に無い）。
//                           ロール「サポート」の味方回復パッシブ・奥義の味方回復はキットが置き換える。
//   スキル1 鎖鉤           — 0.33 秒の振りかぶりの後に飛ぶ非貫通の鉤（射程 823・半幅 35・毎秒 1515）。最初に当たった敵
//                           （ミニオン・モンスター含む、タワーは除く）に 400〜650（+100% 物理攻撃）。当たった敵はその場でスタンし
//                           （Fandom の「Stunned」: Iron Hook はスタン + 引き寄せ。動画でも「スタン」の表示）、0.45 秒後に 0.25 秒で
//                           足元へ引き寄せられ、着地でさらに 0.6 秒スタン（命中から合計 1.3 秒）。
//                           壁は越えて飛び、引き寄せも壁を越える（足元が壁の中なら壁の手前まで。Kit.pullIgnoringTerrain）。
//   スキル2 鉄鎖旋         — 0.27 秒の振りかぶりの後、発動の位置の周り（半径 257）に 300〜450（+自身の最大 HP の 4%）の
//                           物理ダメージ、70% 減速 1.5 秒。
//   アルティメット 狩猟鎖獄 — 射程内（縁まで 188）の敵ヒーロー 1 体へ 0.25 秒で掴みかかり、その場で 1.8 秒 suppress（解除不可・
//                           CC 無効も無視）。掴んだ瞬間から 0.32 秒おきに 6 回 50 / 60 / 70（+70% 物理攻撃）で殴る。ゴルムは
//                           動かない（MLBB の Bloody Hunt に踏み込みは無い。バインド中も撃てる）。掴みかかりと拘束の間はゴルムも
//                           動けず、スタン等で中断されると相手は解放される。
// 幾何と時間は MLBB の画面収録で測った値（docs/kits/Franco.md「動画で測った値（2026-10-16）」。距離は MLBB × 100）。
// ダメージ = 公式の基礎[Lv] + 係数 × 能力値（Kit.official）。全体の倍率・キットの換算・ダメージの上限は無い。CD・マナ消費も公式の表。
// スキル吸収率・攻撃エフェクト・ミニオン / モンスターへの補正は日本語クライアントの文に無いので既定（吸収 100%・補正なし）。
// 再使用の窓は Franco に無いので使わない。
//
// 状態（KitState）:
//   ints[0]   = 闘気（0..10）            ints[1] = 「5 秒の無被弾」状態に入っているか（0/1）
//   ints[2]   = 奥義の段（0 = なし / 1 = 拘束中 / 2 = 掴みかかり中）   ints[3] = 拘束中に殴った回数
//   ints[4]   = 命中した鉤の数（検証用）  ints[5] = 直前に当たったスキルが消費した闘気の数（検証用）
//   ints[6]   = 無被弾の間に闘気を消費した（1 = 次にダメージを受けるまで闘気はたまらない）
//   ints[7]   = 飛んでいる鉤のダメージに掛けてある闘気の数（retuneHooks が今の闘気に合わせる）
//   timers[0] = 最後のダメージからの待ち（5 秒）  timers[1] = 次の闘気まで   timers[2] = 次の回復まで
//   timers[3] = 奥義の拘束の残り秒
//   ids[0]    = 奥義の対象                reals[0] = 奥義の 1 撃の基礎ダメージ（闘気の補正なし。1 撃ごとにその時の闘気を掛ける）

extension KitState {
    var gormStacks: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    var gormCalmActive: Bool {
        get { ints[1] != 0 }
        set { ints[1] = newValue ? 1 : 0 }
    }

    var gormUltPhase: Int {
        get { ints[2] }
        set { ints[2] = newValue }
    }

    var gormUltStrikes: Int {
        get { ints[3] }
        set { ints[3] = newValue }
    }

    var gormHooksLanded: Int {
        get { ints[4] }
        set { ints[4] = newValue }
    }

    /// 無被弾の間にスキルで闘気を消費したら、次にダメージを受けるまで闘気はたまらない（Fandom の注記）。
    var gormStackLock: Bool {
        get { ints[6] != 0 }
        set { ints[6] = newValue ? 1 : 0 }
    }

    var gormLastConsumed: Int {
        get { ints[5] }
        set { ints[5] = newValue }
    }

    /// 飛んでいる鉤（弾）のダメージに掛けてある闘気の数。鉤のダメージは命中の瞬間の闘気で決まるので、闘気が変わるたびに
    /// 弾のダメージを掛け直す（Kit_H034.retuneHooks）。
    var gormHookStacks: Int {
        get { ints[7] }
        set { ints[7] = newValue }
    }

    var gormCalm: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    var gormStackTimer: Double {
        get { timers[1] }
        set { timers[1] = newValue }
    }

    var gormRegenTimer: Double {
        get { timers[2] }
        set { timers[2] = newValue }
    }

    var gormUltRemaining: Double {
        get { timers[3] }
        set { timers[3] = newValue }
    }

    var gormUltTarget: EntityID {
        get { ids[0] }
        set { ids[0] = newValue }
    }

    var gormUltDamage: Double {
        get { reals[0] }
        set { reals[0] = newValue }
    }
}

struct Kit_H034: HeroKit {
    let heroID = "H034"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H034(isReady: true)` を HeroKits.testOverride に差しても試せる（有効化とは独立）。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    // MARK: - 数値（MLBB の値はそのまま。距離は Velstria 単位 ≈ MLBB × 100。資料に無い値は Franco.md の「推測の値」に理由）

    enum Tune {
        // パッシブ 鉄鎖の執念（公式: 5 秒・+10%・毎秒 1%・最大 10 スタック・最大 150%（= 1.5 倍））
        /// 最後のダメージからこの秒数 ダメージを受けないと「無被弾」状態に入る。
        static let calmDelay = 5.0
        static let calmSpeed = 0.10
        /// 毎秒の回復（最大 HP の割合）。回復は regenPulse 秒ごとにまとめて行う（イベントを増やさない）。
        static let calmRegen = 0.01
        static let regenPulse = 0.5
        static let maxStacks = 10
        /// 闘気は無被弾の間 1 秒に 1 つ（推測。公式の文に無い: 10 個で 15 秒 = 無被弾の 5 秒 + 10 秒）。
        static let stackInterval = 1.0
        /// 1 つにつきスキルのダメージ +5%（10 個で +50% = 1.5 倍）。動画で測った値: 闘気 10 の鉤が 1.5 倍、奥義の途中でたまった
        /// 闘気 1 つで 5・6 撃目が 1.05 倍（docs/kits/Franco.md「ダメージの表示」）。Fandom の properties の「1 つあたり 5% … 10 で 50%」と同じ。
        /// 公式の文の「最大150%増加」は「最大で 150% まで」（= 1.5 倍）と読む（以前の推測 +15% = 10 で 2.5 倍は外した）。
        static let stackBonus = 0.05
        static let speedTag = KitTags.buff("H034", "calmSpeed")
        /// 「ダメージを受けるまで続く」加速のステータスに持たせる持続（実質無期限）。
        static let permanent = 1_000_000.0

        // S1 鎖鉤（幾何と時間は動画で測った値。docs/kits/Franco.md「動画で測った値（2026-10-16）」。距離は MLBB × 100）
        /// 射程 = 照準の円の半径 8.23。
        static let hookRange = 823.0
        /// 鉤の当たり幅（半径）= 照準の線の半幅 0.35。ヒーロー半径 55 と合わせて、左右 90 の筋に届く。
        static let hookWidth = 35.0
        /// 鉤の速さ（毎秒 15.1。鉤の頭が 1 コマに 31.5 px）。射程の端まで 0.54 秒。
        static let hookSpeed = 1515.0
        /// 指を離してから鉤が飛び出すまで（振りかぶり 10 コマ）。この間にスタン以上を受けると鉤は出ない（コスト・CD は戻らない）。
        static let hookDelay = 0.33
        /// 命中から引き寄せが始まるまで（相手はその場でスタンしたまま。13〜14 コマ）。
        static let hookHold = 0.45
        /// 引き寄せの所要時間（8 コマ。距離に関わらず一定とした）。この間は強制移動で動けない。
        static let hookPull = 0.25
        /// 引き寄せた後に止まる、端同士の隙間（測った中心間の距離 1.38 = ヒーロー半径 55 × 2 + 28）。
        static let hookGap = 28.0
        /// 命中から引き寄せ終わるまでのスタン（hookHold + hookPull = 0.70 秒。動画の「スタン」の表示 21 コマ）。日本語クライアントの文には
        /// 無いが、Fandom の「Stunned」の頁に Iron Hook が「スタン + 引き寄せ」として載る。MLBB の引き寄せは移動・通常攻撃・スキルを封じ、
        /// 発動中のスキルを中断する。Velstria の強制移動は移動・行動を封じるが中断はしないので、中断はこのスタン（基本の段階）で起こす。
        static let hookStun = hookHold + hookPull
        /// 着地のスタン（引き寄せの後に新しく付く。動画の 2 つ目の「スタン」の表示 16 コマ + 表示の切れ目 2 コマ）。命中から合計 1.3 秒。
        static let hookLandStun = 0.6
        static let hookStunTag = KitTags.buff("H034", "hookStun")
        /// 公式: Lv1〜6 の基礎ダメージ（+100% 物理攻撃 = 合計の物理攻撃）。
        static let hookBase: [Double] = [400, 450, 500, 550, 600, 650]
        static let hookAttackRatio = 1.0
        /// 公式: CD 15.0 / 14.2 / 13.4 / 12.6 / 11.8 / 11.0 秒、MP 135 / 140 / 145 / 150 / 155 / 160。
        static let hookCooldown: [Double] = [15.0, 14.2, 13.4, 12.6, 11.8, 11.0]
        static let hookCost: [Double] = [135, 140, 145, 150, 155, 160]

        // スキル2 鉄鎖旋
        /// 半径 = 照準の円の半径 2.57（2 回の照準で 2.577 / 2.570）。対象の半径まで含めて当たる。
        static let shockRadius = 257.0
        /// 指を離してから叩きつけ（ダメージ）まで（7.5〜8.5 コマ）。発動の位置の周りに当たる。この間にスタン以上を受けると出ない。
        static let shockDelay = 0.27
        static let shockSlow = 0.70
        static let shockSlowDuration = 1.5
        static let shockSlowTag = KitTags.buff("H034", "shockSlow")
        /// 公式: Lv1〜6 の基礎ダメージ（+自身の最大 HP の 4%。物理攻撃の係数は無い）。
        static let shockBase: [Double] = [300, 330, 360, 390, 420, 450]
        static let shockMaxHPRatio = 0.04
        /// 公式: CD 7.0 / 6.5 / 6.0 / 5.5 / 5.0 / 4.5 秒、MP 40 / 45 / 50 / 55 / 60 / 65。
        static let shockCooldown: [Double] = [7.0, 6.5, 6.0, 5.5, 5.0, 4.5]
        static let shockCost: [Double] = [40, 45, 50, 55, 60, 65]

        // 奥義 狩猟鎖獄
        /// 術者の中心から対象の縁までの射程 = 照準の円の半径 1.88（動画で測った値）。踏み込みは無いので、この距離のまま拘束する。
        static let ultReach = 188.0
        /// 指を離してから掴む（制圧と 1 撃目）まで（7〜7.5 コマ）。この間はゴルムも動けず、スタン以上で取り消される。
        static let ultDelay = 0.25
        /// 掴みかかりの間に対象が射程（縁まで ultReach）から離れてよい距離（推測。0.25 秒に歩ける距離 + 余裕）。超えたら掴めない。
        static let ultLeash = 100.0
        static let ultSuppress = 1.8
        static let ultHits = 6
        /// 1 撃目は掴んだ瞬間、以後 0.32 秒おき（0, 0.32, ..., 1.60 秒。動画の 6 撃は掴んでから 0 / 10 / 20 / 30 / 38 / 48 コマで、
        /// 等間隔の当てはめが 9.5 コマ = 0.32 秒）。6 撃目のあと 0.2 秒で拘束が解ける。
        static let ultFirst = 0.0
        static let ultInterval = 0.32
        /// 公式: Lv1〜3 の 1 撃の基礎ダメージ（+70% 物理攻撃 = 合計の物理攻撃）。6 回の合計に上限は無い。
        static let ultHitBase: [Double] = [50, 60, 70]
        static let ultHitAttackRatio = 0.7
        /// 公式（日本語クライアント）: CD 62 / 55 / 48 秒（Fandom の 45 は誤り）、MP 110 / 125 / 140。
        static let ultCooldown: [Double] = [62, 55, 48]
        static let ultCost: [Double] = [110, 125, 140]
        static let lockRootTag = KitTags.buff("H034", "lockRoot")
        static let lockTag = KitTags.buff("H034", "lock")
        /// ボットのアルティメット: 相手の HP がこの割合未満 / 鉤でスタン中 / 近く（この距離以内）に味方ヒーローが居るとき、関門なしで撃つ。
        static let botWeakHP = 0.7
        static let botAllyRange = 800.0
    }

    private enum Code {
        static let strike = 1
        /// 鉤が飛び出す（振りかぶりの終わり。point = 向き、param = ダメージ（闘気の補正なし））。
        static let hookLaunch = 2
        /// 命中した相手を引き寄せ始める（targetID = 相手）。
        static let hookYank = 3
        /// 引き寄せの終わりの着地のスタン（targetID = 相手）。
        static let hookLand = 4
        /// スキル2 の叩きつけ（point = 中心、param = ダメージ（闘気の補正なし））。
        static let shockSlam = 5
        /// 奥義の掴み（掴みかかりの終わり。targetID = 相手）。
        static let ultGrab = 6
    }

    /// HitPayload.kitEvent
    private enum Event {
        static let hook = 1
    }

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 長い直線の鉤（非貫通）。radius は弾の半幅
            return SkillTargeting(archetype: .lineSkillshot, aim: .direction, range: Tune.hookRange,
                                  radius: Tune.hookWidth, shape: .wideLine)
        case .skill2:
            // 自身中心の範囲（対象なし）
            return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: Tune.shockRadius,
                                  shape: .selfRing)
        case .ultimate:
            // 対象指定（敵ヒーロー 1 体）。型は targetedBlink だが術者は動かない（movesCaster で外す）
            return SkillTargeting(archetype: .targetedBlink, aim: .unit, range: Tune.ultReach, radius: 150,
                                  shape: .lockOn, requiresTarget: true)
        case .passive:
            return base
        }
    }

    /// 奥義は照準の型が targetedBlink（対象指定）だが、ゴルムは動かない（MLBB の Bloody Hunt に踏み込み・ブリンクは無い）。
    /// バインド（移動・ブリンク・突進の封印）の間も撃てる。スキル1・2 は型のまま（どちらも術者を動かさない）。
    func movesCaster(slot: SkillSlot, stage: Int, base: Bool) -> Bool {
        slot == .ultimate ? false : base
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        var n = base
        switch slot {
        case .passive:
            n.hits = Tune.maxStacks
            // maxAmp = 増加の上限（+50%）、stackPercent = 1 つあたり（+5%）、maxDamagePercent = 上限のときのダメージ
            // （150% = 公式の文の「最大150%」）
            n.extras = [KitStat(key: "calmDelay", value: Tune.calmDelay),
                        KitStat(key: "speedPercent", value: Tune.calmSpeed * 100),
                        KitStat(key: "regenPercent", value: Tune.calmRegen * 100),
                        KitStat(key: "maxAmp", value: Tune.stackBonus * Double(Tune.maxStacks) * 100),
                        KitStat(key: "stackPercent", value: Tune.stackBonus * 100),
                        KitStat(key: "maxDamagePercent", value: Self.amp(stacks: Tune.maxStacks) * 100)]
        case .skill1:
            n.damage = Self.hookDamage(rank: rank, stats: stats)
            n.cooldown = Kit.cooldown(Tune.hookCooldown, rank: rank, stats: stats)
            n.cc = .stun
            // HUD・AI 用: 命中から動けない時間の合計（その場のスタン + 引き寄せ + 着地のスタン）
            n.ccDuration = Tune.hookStun + Tune.hookLandStun
            n.extras = [KitStat(key: "stun", value: Tune.hookStun),
                        KitStat(key: "landStun", value: Tune.hookLandStun),
                        KitStat(key: "pull", value: Tune.hookPull),
                        KitStat(key: "reachMult", value: Tune.hookRange / hero.attackRange),
                        KitStat(key: "base", value: Kit.level(Tune.hookBase, rank: rank)),
                        KitStat(key: "atkPct", value: Tune.hookAttackRatio * 100)]
        case .skill2:
            n.damage = Self.shockDamage(rank: rank, stats: stats)
            n.cooldown = Kit.cooldown(Tune.shockCooldown, rank: rank, stats: stats)
            n.cc = .slow
            n.ccDuration = Tune.shockSlowDuration
            n.extras = [KitStat(key: "slowPercent", value: Tune.shockSlow * 100),
                        KitStat(key: "slowDuration", value: Tune.shockSlowDuration),
                        KitStat(key: "maxHPPercent", value: Tune.shockMaxHPRatio * 100),
                        KitStat(key: "reachMult", value: Tune.shockRadius / hero.attackRange),
                        KitStat(key: "base", value: Kit.level(Tune.shockBase, rank: rank))]
        case .ultimate:
            // 汎用のサポートの奥義は味方回復（ダメージなし）。1 撃 = 公式の 50 / 60 / 70（+70% 物理攻撃）
            n.damage = Self.ultHitDamage(rank: rank, stats: stats)
            n.hits = Tune.ultHits
            n.heal = 0
            n.shield = 0
            n.shieldDuration = 0
            n.cc = .stun
            n.ccIsUltimate = true
            n.ccDuration = Tune.ultSuppress
            n.cooldown = Kit.cooldown(Tune.ultCooldown, rank: rank, stats: stats)
            n.extras = [KitStat(key: "suppress", value: Tune.ultSuppress),
                        KitStat(key: "interval", value: Tune.ultInterval),
                        KitStat(key: "reachMult", value: Tune.ultReach / hero.attackRange),
                        KitStat(key: "base", value: Kit.level(Tune.ultHitBase, rank: rank)),
                        KitStat(key: "atkPct", value: Tune.ultHitAttackRatio * 100)]
        }
        return n
    }

    /// ランクごとのマナ消費（公式の表: スキル1 135〜160、スキル2 40〜65、アルティメット 110 / 125 / 140）。
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double {
        let table: [Double]
        switch slot {
        case .skill1: table = Tune.hookCost
        case .skill2: table = Tune.shockCost
        case .ultimate: table = Tune.ultCost
        case .passive: return base
        }
        return HeroKits.resourceCost(Kit.level(table, rank: rank), hero: hero)
    }

    /// 説明文は公式（日本語クライアント）の文に合わせる（数値は {トークン} で sim から。{base}(+{atkPct}%物理攻撃) は公式の値そのもの）。
    /// 名前は master のもの（ワイルドフォース = 闘気、アイアンフック = 鎖鉤）。距離は近接攻撃の射程に対する倍率で括弧に足す。
    /// パッシブ: 公式の「そのスキルダメージを最大150%増加させる」は 1.5 倍のこと（動画で測った値）なので、日本語は「最大150%まで」と
    /// 1 つあたり（+5%。動画・Fandom）を括弧に足して読み違えないようにする（英語は増加分で「by up to 50%」）。消費の時は動画で見た
    /// 「ダメージが当たった時」（公式の文は「次のスキル発動時に」）。闘気のたまる速さ（推測）は公式の文に無いので書かない（docs/kits/Franco.md）。
    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "{calmDelay}秒間ダメージを受けなかった場合、移動速度が{speedPercent}%上昇し、1秒ごとに最大HPの{regenPercent}%を回復し、闘気が蓄積され始める（最大{hits}スタック）。\n\n"
                    + "次のスキルのダメージが当たった時にすべての闘気を消費し、そのスキルダメージを最大{maxDamagePercent}%まで増加させる（1スタックにつき+{stackPercent}%）。"
                    + "外れたスキルは闘気を消費しない。",
                en: "If no damage is taken for {calmDelay}s, Gorm's Movement Speed increases by {speedPercent}%, he recovers {regenPercent}% of his Max HP every second, "
                    + "and Resolve begins to accumulate (up to {hits} stacks).\n\n"
                    + "When the damage of his next skill lands, it consumes all Resolve to increase that skill's damage by up to {maxAmp}% "
                    + "(+{stackPercent}% per stack). A skill that misses does not consume Resolve.",
                tags: [KitTag.buff])
        case .skill1:
            return KitText(
                ja: "指定方向へ鎖鉤を放ち（届くのは近接攻撃の射程の約{reachMult}倍）、最初に命中した敵に{base}(+{atkPct}%物理攻撃)の物理ダメージを与え、自身の元へ引き寄せる。\n\n"
                    + "対象は引き寄せが終わるまで（{stun}秒）スタン状態になり、着地でさらに{landStun}秒スタンする。鉤は壁を越えて飛び、引き寄せも壁を越える（自身の前が壁の中なら壁の手前まで）。タワーには当たらない。",
                en: "Launch the chain hook in the target direction (reaching about {reachMult}x the melee attack range), dealing {base} (+{atkPct}% Physical Attack) "
                    + "physical damage to the first enemy hit and pulling them to Gorm.\n\n"
                    + "The target is stunned until the pull ends ({stun}s) and for another {landStun}s on landing. The hook flies over walls and pulls through them too (if the spot in front of Gorm is inside a wall, the pull stops at the wall); it does not hit turrets.",
                tags: [KitTag.disrupt, KitTag.damage])
        case .skill2:
            return KitText(
                ja: "怒りの一撃で周囲（近接攻撃の射程の約{reachMult}倍）の敵に{base}(+自身の最大HPの{maxHPPercent}%)の物理ダメージを与え、{slowDuration}秒間移動速度を{slowPercent}%低下させる。",
                en: "Strike in fury, dealing {base} (+{maxHPPercent}% of Gorm's Max HP) physical damage to nearby enemies (within about {reachMult}x the melee attack range) "
                    + "and reducing their Movement Speed by {slowPercent}% for {slowDuration}s.",
                tags: [KitTag.slow])
        case .ultimate:
            return KitText(
                ja: "対象の敵ヒーロー（近接攻撃の射程の約{reachMult}倍以内）を{suppress}秒間、制圧状態にし、その間に{hits}回攻撃する。攻撃ごとに{base}(+{atkPct}%物理攻撃)の物理ダメージを与える。\n\n"
                    + "制圧は浄化で解除できず、CC無効も無視する。ゴルムがコントロール効果を受けると、スキルは途中で終わる。",
                en: "Suppress the target enemy hero (within about {reachMult}x the melee attack range) for {suppress}s and attack them {hits} times "
                    + "during that time. Each attack deals {base} (+{atkPct}% Physical Attack) physical damage.\n\n"
                    + "Suppression cannot be cleansed and ignores crowd-control immunity. The skill ends early if Gorm is crowd controlled.",
                tags: [KitTag.burst, KitTag.disrupt])
        }
    }

    /// パッシブ = 闘気の数。闘気はスキルのダメージが当たった時に消費するので、鉤が飛んでいる間・S2 の振りかぶりの間・奥義の
    /// 最後の 1 撃の前は残って見え、当たった tick に 0 になる（外れたら減らない）。App の解放の演出（passiveRelease）はこの減少を見る。
    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            return KitBadge(kind: .stacks, value: min(k.gormStacks, Tune.maxStacks), maxValue: Tune.maxStacks)
        case .ultimate:
            guard k.gormUltRemaining > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.gormUltRemaining, total: Tune.ultSuppress)
        default:
            return nil
        }
    }

    // MARK: - B. 実行

    func resolveAim(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot, stage: Int,
                    targeting: SkillTargeting, target: SkillTarget) -> SkillAim?? {
        guard slot == .ultimate else { return nil }
        // 敵ヒーロー 1 体の対象指定: 射程内に居なければ拒否（コスト・CD を消費しない）
        guard let u = Self.pickHero(s, caster: caster, reach: targeting.reach, target: target) else {
            return .some(nil)
        }
        return .some(SkillAiming.aim(at: u, s, caster: caster, range: targeting.range,
                                     facing: Vec2.fromAngle(s.units[caster].facing)))
    }

    /// 奥義の最中（掴みかかり・拘束）は、他のスキルも奥義も撃てない（鎖で相手と繋がっている）。鉤・S2 の振りかぶりの間も、
    /// 次のスキルは始められない（MLBB の発動の動作の間。動画の振りかぶり 0.33 / 0.27 秒）。
    func canStart(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) -> Bool {
        guard let k = s.units[caster].hero?.kit else { return true }
        guard k.gormUltPhase == 0 else { return false }
        return !k.scheduled.contains { $0.code == Code.hookLaunch || $0.code == Code.shockSlam }
    }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        switch c.slot {
        case .skill1: castHook(&s, c)
        case .skill2: castShock(&s, ctx, c)
        case .ultimate: castHunt(&s, ctx, c)
        case .passive: break
        }
        return .done
    }

    /// 闘気の補正（1 + 0.05 × 闘気。10 で 1.5 倍）。
    static func amp(stacks: Int) -> Double {
        1 + Tune.stackBonus * Double(max(0, stacks))
    }

    /// スキルのダメージが当たった時に闘気をすべて消費する（動画: 鉤の命中のコマで闘気のアイコンが消えた）。呼ぶのは当たった時だけで、
    /// 外れたスキル（鉤が何にも当たらない・S2 の範囲に敵が居ない・奥義を掴めない）は闘気を残す。補正は呼ぶ側がその時の闘気で掛け済み。
    /// 闘気が 0 でも「消費した」扱い（無被弾の間なら闘気がたまらなくなる。以前の発動の時の消費と同じ）。
    private func consumeStacks(_ s: inout SimState, _ i: Int) {
        guard let k = s.units[i].hero?.kit else { return }
        s.units[i].hero!.kit!.gormStacks = 0
        s.units[i].hero!.kit!.gormLastConsumed = k.gormStacks
        // 無被弾の間に消費したら、次にダメージを受けるまで闘気はたまらない（加速・回復は続く）
        if k.gormCalmActive { s.units[i].hero!.kit!.gormStackLock = true }
        // 飛んでいる別の鉤（練習の CD なし）の補正も外す
        retuneHooks(&s, owner: i)
    }

    /// 飛んでいる鉤のダメージを今の闘気に合わせる（鉤のダメージは命中の瞬間の闘気で決まる。飛ぶ間に闘気がたまった・S2 の叩きつけが
    /// 先に当たって消費した、も命中の時の値になる）。弾のダメージ = 基礎 × amp(gormHookStacks) なので、闘気が変わっていたら比で
    /// 掛け直す（基礎は別に持たない）。発射の時・毎 tick の終わり（update）・消費の後に呼ぶ。闘気が変わっていなければ何もしない。
    /// ゴルムが倒れると状態はリセットされ更新も止まるので、倒れた後に当たった鉤は倒れる前の補正のまま。
    private func retuneHooks(_ s: inout SimState, owner i: Int) {
        guard let k = s.units[i].hero?.kit, k.gormHookStacks != k.gormStacks else { return }
        let ratio = Self.amp(stacks: k.gormStacks) / Self.amp(stacks: k.gormHookStacks)
        let id = s.units[i].id
        for j in s.projectiles.indices where s.projectiles[j].ownerID == id && !s.projectiles[j].done
            && s.projectiles[j].payload.kitEvent == Event.hook {
            s.projectiles[j].payload.damage *= ratio
        }
        s.units[i].hero!.kit!.gormHookStacks = k.gormStacks
    }

    /// S1: 振りかぶり（hookDelay）の後に非貫通の鉤が飛ぶ（onTimer の hookLaunch）。闘気は鉤が当たった時に消費する（onHit）。
    /// 振りかぶりの間にスタン以上を受けると鉤は出ない（予約は interruptible。コスト・CD は戻らない。闘気は残る）。
    private func castHook(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        Kit.emitCast(&s, c, target: s.units[i].pos + c.aim.direction * Tune.hookRange, unit: c.aim.unit,
                     shape: .wideLine, duration: Tune.hookDelay + Tune.hookRange / Tune.hookSpeed, count: 1)
        Kit.schedule(&s, caster: i, slot: .skill1, code: Code.hookLaunch, after: Tune.hookDelay,
                     param: c.numbers.damage, point: c.aim.direction, interruptible: true)
    }

    /// S1 の鉤が飛び出す: 今の位置から、発動の時の向きへ。最初に当たった敵へダメージ + スタン（その場 + 引き寄せの間）、
    /// 引き寄せと着地のスタンは onHit から予約する（hookYank → hookLand）。ダメージは今の闘気の補正で出し、飛ぶ間は retuneHooks が
    /// 闘気の変化に合わせる（命中の瞬間の闘気が掛かる）。
    private func launchHook(_ s: inout SimState, _ ctx: SimContext, owner i: Int, timer: KitTimer) {
        let dir = timer.point.normalized
        guard dir != .zero else { return }
        // 先に飛んでいる鉤を今の闘気に揃えてから、同じ補正で足す（gormHookStacks = 今の闘気）
        retuneHooks(&s, owner: i)
        let amp = Self.amp(stacks: s.units[i].hero?.kit?.gormHookStacks ?? 0)
        let stun = StatusEffect(kind: .stun, duration: Tune.hookStun, sourceID: s.units[i].id, tag: Tune.hookStunTag)
        let skill = ctx.master.skill(hero: heroID, slot: .skill1)
        let p = HitPayload(damage: timer.param * amp, damageType: .physical, source: .skill(.skill1),
                           statuses: [stun], skillID: skill?.skillID,
                           originPos: s.units[i].pos, kitEvent: Event.hook)
        ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: dir, maxDistance: Tune.hookRange),
                               speed: Tune.hookSpeed, width: Tune.hookWidth, pierce: false, payload: p,
                               visual: skill?.effectID ?? "")
    }

    /// S2: 振りかぶり（shockDelay）の後に、発動の位置の周りへ叩きつける（onTimer の shockSlam）。闘気は叩きつけが当たった時に消費する。
    private func castShock(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let origin = s.units[i].pos
        Kit.emitCast(&s, c, target: origin, shape: .selfRing, duration: Tune.shockDelay, count: 1)
        Kit.schedule(&s, caster: i, slot: .skill2, code: Code.shockSlam, after: Tune.shockDelay,
                     param: c.numbers.damage, point: origin, interruptible: true)
    }

    /// S2 の叩きつけ: 円（半径 shockRadius + 対象の半径）に公式の基礎 + 自分の最大 HP の 4%（numbers に含まれる）× 叩きつけの時の
    /// 闘気の補正、70% 減速。1 体でも当たれば（無敵でない敵が範囲に居れば）闘気を消費する。範囲に敵が居なければ闘気は残る。
    /// 当て方は SkillArchetypes.hitArea と同じ（対象を先に確定し添字昇順に同じ payload）。
    private func slam(_ s: inout SimState, _ ctx: SimContext, owner i: Int, timer: KitTimer) {
        let slow = StatusEffect(kind: .slow, duration: Tune.shockSlowDuration, magnitude: Tune.shockSlow,
                                sourceID: s.units[i].id, tag: Tune.shockSlowTag)
        let amp = Self.amp(stacks: s.units[i].hero?.kit?.gormStacks ?? 0)
        let p = HitPayload(damage: timer.param * amp, damageType: .physical, source: .skill(.skill2),
                           statuses: [slow], skillID: Self.skillID(ctx, .skill2), originPos: timer.point)
        var landed = false
        Kit.hitAreaEach(&s, ctx, caster: i, center: timer.point, radius: Tune.shockRadius, shape: .circle) { st, j in
            if !CombatSystem.isInvulnerable(st, ctx, j) { landed = true }
            return p
        }
        if landed { consumeStacks(&s, i) }
    }

    /// 奥義: 射程内の対象へ掴みかかり（ultDelay。その間ゴルムは動けない）、掴んだらその場で拘束して 6 回殴る（踏み込みは無い。
    /// 照準 resolveAim が同じ tick に射程を確かめている）。闘気は発動では消費しない（1 撃ごとにその時の闘気を掛け、最後の 1 撃で消費。strike）。
    private func castHunt(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        guard let t = c.aim.unit else { return }
        let id = s.units[i].id
        s.units[i].hero!.kit!.gormUltTarget = s.units[t].id
        s.units[i].hero!.kit!.gormUltDamage = c.numbers.damage
        s.units[i].hero!.kit!.gormUltPhase = 2
        Kit.emitCast(&s, c, target: s.units[t].pos, unit: t, shape: .lockOn, duration: Tune.ultDelay + Tune.ultSuppress,
                     count: Tune.ultHits)
        // 掴みかかりから拘束の終わりまで、自分に付ける足止め（sourceID = 自分。バインドではない）と詠唱の表示
        let total = Tune.ultDelay + Tune.ultSuppress
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .root, duration: total, sourceID: id,
                                                                 tag: Tune.lockRootTag))
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .channeling, duration: total, sourceID: id,
                                                                 tag: Tune.lockTag))
        let face = s.units[t].pos - s.units[i].pos
        if face != .zero { s.units[i].facing = face.angle }
        s.units[i].windupRemaining = nil
        Kit.schedule(&s, caster: i, slot: .ultimate, code: Code.ultGrab, after: Tune.ultDelay, targetID: s.units[t].id,
                     interruptible: true)
    }

    /// 拘束の開始（掴みかかりの終わり）: 対象を suppress し、6 回の連撃を予約する（1 撃目は同じ tick）。対象が倒れた・射程から
    /// ultLeash 以上離れた・無敵などで成立しなければ、何もせず終わる（クールダウンは戻らない）。
    private func beginLock(_ s: inout SimState, _ ctx: SimContext, owner i: Int) {
        guard let k = s.units[i].hero?.kit else { return }
        let tid = k.gormUltTarget
        guard tid != 0, let t = s.index(of: tid), CombatSystem.isLiving(s, t), s.units[t].team != s.units[i].team,
              s.units[t].kind == .hero else {
            endLock(&s, owner: i, release: false)
            return
        }
        let leash = Tune.ultReach + s.units[t].radius + Tune.ultLeash
        guard s.units[t].pos.distanceSquared(to: s.units[i].pos) <= leash * leash else {
            endLock(&s, owner: i, release: false)
            return
        }
        let id = s.units[i].id
        Kit.suppress(&s, target: t, duration: Tune.ultSuppress, sourceID: id)
        // 無敵などで拘束できなかった（suppress が付かない）なら、連撃に入らない
        guard s.units[t].has(.suppress) else {
            endLock(&s, owner: i, release: false)
            return
        }
        // 自分に付ける足止め（sourceID = 自分。バインドではない）と詠唱の表示。発動の時に付けたもの（掴みかかり + 拘束）を、
        // 浄化などで外れていても拘束の終わりまで付け直す（同じタグは長い方が残る）
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .root, duration: Tune.ultSuppress, sourceID: id,
                                                                 tag: Tune.lockRootTag))
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .channeling, duration: Tune.ultSuppress,
                                                                 sourceID: id, tag: Tune.lockTag))
        let face = s.units[t].pos - s.units[i].pos
        if face != .zero { s.units[i].facing = face.angle }
        s.units[i].windupRemaining = nil
        s.units[i].hero!.kit!.gormUltPhase = 1
        s.units[i].hero!.kit!.gormUltRemaining = Tune.ultSuppress
        s.units[i].hero!.kit!.gormUltStrikes = 0
        // 1 撃目（firstDelay 0）は同じ tick に入る（KitRuntime.fireTimers が発火中に積まれた 0 秒の予約も消化する）
        Kit.strikeSequence(&s, caster: i, slot: .ultimate, code: Code.strike, count: Tune.ultHits,
                           interval: Tune.ultInterval, firstDelay: Tune.ultFirst, targetID: tid)
    }

    /// 奥義の終わり（自然終了・対象の消失・中断）。release なら相手の拘束も外す。
    /// 拘束して 1 撃以上殴ったのに最後の 1 撃の前に終わった（相手が倒れた・ゴルムが CC を受けた）ときは、ここで闘気を消費する
    /// （6 撃目まで入れば strike が消費済み。掴めなかった・掴む前に止められたときは消費しない）。
    private func endLock(_ s: inout SimState, owner i: Int, release: Bool) {
        guard let k = s.units[i].hero?.kit else { return }
        if k.gormUltPhase == 1, k.gormUltStrikes > 0, k.gormUltStrikes < Tune.ultHits { consumeStacks(&s, i) }
        if release { Kit.releaseSuppress(&s, bySource: s.units[i].id) }
        s.units[i].statuses.removeAll {
            ($0.kind == .root && $0.tag == Tune.lockRootTag) || ($0.kind == .channeling && $0.tag == Tune.lockTag)
        }
        Kit.cancelScheduled(&s, caster: i, slot: .ultimate)
        s.units[i].hero!.kit!.gormUltPhase = 0
        s.units[i].hero!.kit!.gormUltRemaining = 0
        s.units[i].hero!.kit!.gormUltTarget = 0
        s.units[i].hero!.kit!.gormUltDamage = 0
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard let k = s.units[owner].hero?.kit else { return }
        switch timer.code {
        case Code.strike:
            guard k.gormUltPhase == 1, k.gormUltTarget == timer.targetID else { return }
            strike(&s, ctx, owner: owner, timer: timer)
        case Code.ultGrab:
            guard k.gormUltPhase == 2, k.gormUltTarget == timer.targetID else { return }
            beginLock(&s, ctx, owner: owner)
        case Code.hookLaunch:
            launchHook(&s, ctx, owner: owner, timer: timer)
        case Code.hookYank:
            yank(&s, ctx, owner: owner, timer: timer)
        case Code.hookLand:
            land(&s, owner: owner, timer: timer)
        case Code.shockSlam:
            slam(&s, ctx, owner: owner, timer: timer)
        default:
            break
        }
    }

    /// 拘束中の 1 撃。対象が倒れた・居なくなった・拘束が外れていたら、残りの連撃を取りやめて解放する。
    private func strike(_ s: inout SimState, _ ctx: SimContext, owner i: Int, timer: KitTimer) {
        guard let t = s.index(of: timer.targetID), CombatSystem.isLiving(s, t), s.units[t].has(.suppress),
              let k = s.units[i].hero?.kit else {
            endLock(&s, owner: i, release: true)
            return
        }
        // 1 撃 = 公式の値 × その時の闘気の補正。奥義の途中でたまった闘気も後の撃に掛かる（動画: 闘気 0 で撃ち、5 撃目のコマで
        // 闘気が 1 つたまると 5・6 撃目が 1.05 倍、6 撃目のコマで闘気が消えた）。6 回の合計に上限は無い（MLBB に無い）
        let p = HitPayload(damage: k.gormUltDamage * Self.amp(stacks: k.gormStacks), damageType: .physical,
                           source: .skill(.ultimate), ccIsUltimate: true, skillID: Self.skillID(ctx, .ultimate),
                           originPos: s.units[i].pos)
        CombatSystem.applyHit(&s, ctx, sourceID: s.units[i].id, team: s.units[i].team, targetIndex: t, payload: p,
                              from: s.units[i].pos)
        s.units[i].hero?.kit?.gormUltStrikes += 1
        // 闘気は最後の 1 撃で消費する（途中で終わったときは endLock）
        if (s.units[i].hero?.kit?.gormUltStrikes ?? 0) >= Tune.ultHits { consumeStacks(&s, i) }
        if !CombatSystem.isLiving(s, t) { endLock(&s, owner: i, release: true) }
    }

    /// 鉤の命中: 相手はその場でスタンしたまま（payload のスタン hookStun）、hookHold 秒後に引き寄せが始まる（hookYank）。
    /// 闘気はここで消費する（ダメージは命中の時の闘気で掛け済み。無敵の相手に当たったときは呼ばれず、闘気は残る）。
    /// 予約はゴルムが CC を受けても消えない（鉤はすでに掛かっている）。ゴルムが倒れたら消える（死亡でキットの状態は全部リセット）。
    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {
        guard event == Event.hook, s.units[owner].hero?.kit != nil else { return }
        s.units[owner].hero!.kit!.gormHooksLanded += 1
        consumeStacks(&s, owner)
        Kit.schedule(&s, caster: owner, slot: .skill1, code: Code.hookYank, after: Tune.hookHold,
                     targetID: s.units[target].id, interruptible: false)
    }

    /// 引き寄せの始まり: CC 無効・無敵でない相手を引き寄せ、引き寄せの終わり（hookPull 秒後）に着地のスタンを予約する。
    /// 浄化の呪文（CC 無効が付く）で逃れた相手は引かない。強靭でその場のスタンが短くなっていても引き寄せる（MLBB の引き寄せは強靭で縮まない）。
    /// すでに足元に居る相手（動かない）も着地のスタンは受ける。
    private func yank(_ s: inout SimState, _ ctx: SimContext, owner i: Int, timer: KitTimer) {
        guard let t = s.index(of: timer.targetID), Kit.canDisplace(s, ctx, t) else { return }
        Self.hookPull(&s, ctx, owner: i, target: t)
        Kit.schedule(&s, caster: i, slot: .skill1, code: Code.hookLand, after: Tune.hookPull, targetID: timer.targetID,
                     interruptible: false)
    }

    /// 着地のスタン（hookLandStun。引き寄せの間のスタンと同じタグ = ボットの「鉤でスタン中」も続く）。CC 無効・無敵には入らない。
    private func land(_ s: inout SimState, owner i: Int, timer: KitTimer) {
        guard let t = s.index(of: timer.targetID), CombatSystem.isLiving(s, t) else { return }
        CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .stun, duration: Tune.hookLandStun,
                                                                 sourceID: s.units[i].id, tag: Tune.hookStunTag))
    }

    /// 鉤の引き寄せ: 足元（端同士の隙間 hookGap）まで直線で、hookPull 秒で運ぶ。鉤は壁を越えて当たるので、引き寄せも壁を無視する
    /// （調査: 地形を無視して引き寄せる）。足元が壁の中などで歩けないときは、壁の手前で止まる（Kit.pullIgnoringTerrain）。
    /// CC 無効・無敵の相手は動かない。
    static func hookPull(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int) {
        guard s.units.indices.contains(target), CombatSystem.isLiving(s, target) else { return }
        // 距離は十分に大きく取る（実際の移動量は gap で決まる）
        Kit.pullIgnoringTerrain(&s, ctx, target: target, toward: s.units[owner].pos, distance: Tune.hookRange + 400,
                                duration: Tune.hookPull,
                                gap: s.units[owner].radius + s.units[target].radius + Tune.hookGap)
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner i: Int) {
        guard let k = s.units[i].hero?.kit else { return }
        // この tick にたまった闘気を、飛んでいる鉤のダメージに反映する（消費は consumeStacks が反映済み）
        defer { retuneHooks(&s, owner: i) }
        // カウントダウンは 0 まで減らすだけで厳密には 0 にならないことがある（浮動小数の端数）
        let eps = 1e-6

        // 奥義の拘束中: 通常攻撃はしない。時間が来たら終わり（相手の拘束は自然に切れる）
        if k.gormUltPhase == 1 {
            if k.gormUltRemaining <= eps {
                endLock(&s, owner: i, release: false)
            } else {
                s.units[i].windupRemaining = nil
                if s.units[i].attackCooldown < 0.1 { s.units[i].attackCooldown = 0.1 }
            }
        } else if k.gormUltPhase == 2 {
            // 掴みかかりの間も通常攻撃はしない。掴みの予約が消えていたら（想定外の取り消し）終える
            if Kit.scheduledCount(s, caster: i, code: Code.ultGrab) == 0 {
                endLock(&s, owner: i, release: false)
            } else {
                s.units[i].windupRemaining = nil
                if s.units[i].attackCooldown < 0.1 { s.units[i].attackCooldown = 0.1 }
            }
        }

        // パッシブ: 5 秒ダメージを受けていない間の加速・回復・闘気
        guard k.gormCalm <= eps else { return }
        let id = s.units[i].id
        if !k.gormCalmActive {
            s.units[i].hero!.kit!.gormCalmActive = true
            s.units[i].hero!.kit!.gormStackTimer = Tune.stackInterval
            s.units[i].hero!.kit!.gormRegenTimer = Tune.regenPulse
        } else if k.gormStackTimer <= eps {
            if !k.gormStackLock {
                s.units[i].hero!.kit!.gormStacks = min(Tune.maxStacks, k.gormStacks + 1)
            }
            s.units[i].hero!.kit!.gormStackTimer = Tune.stackInterval
        }
        if !s.units[i].statuses.contains(where: { $0.kind == .speedBoost && $0.tag == Tune.speedTag }) {
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .speedBoost, duration: Tune.permanent,
                                                                     magnitude: Tune.calmSpeed, sourceID: id,
                                                                     tag: Tune.speedTag))
        }
        if s.units[i].hero!.kit!.gormRegenTimer <= eps, s.units[i].hp < s.units[i].stats.maxHP {
            s.units[i].hero!.kit!.gormRegenTimer = Tune.regenPulse
            // 自己再生（回復強化・回復量スコア・アシスト記録の対象外。被回復の増減は受ける）
            CombatSystem.restoreHealth(&s, ctx, sourceID: id, targetIndex: i,
                                       amount: s.units[i].stats.maxHP * Tune.calmRegen * Tune.regenPulse, isVamp: true)
        }
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // 拘束中のハード CC（スタン・打ち上げ・suppress）: 連撃は取り消され、相手は解放される
        guard (s.units[owner].hero?.kit?.gormUltPhase ?? 0) != 0 else { return }
        endLock(&s, owner: owner, release: true)
    }

    // MARK: - C. パッシブ（鉄鎖の執念）

    func onDamageTaken(_ s: inout SimState, _ ctx: SimContext, victim: Int, attacker: Int?, amount: Double) {
        guard amount > 0, s.units[victim].hero?.kit != nil else { return }
        // 無被弾の待ちをやり直し。加速と回復は止まり、闘気はそのまま残る（調査: 減衰の規則は不明）
        s.units[victim].hero!.kit!.gormCalm = Tune.calmDelay
        s.units[victim].hero!.kit!.gormCalmActive = false
        s.units[victim].hero!.kit!.gormStackLock = false
        s.units[victim].hero!.kit!.gormStackTimer = 0
        s.units[victim].hero!.kit!.gormRegenTimer = 0
        s.units[victim].statuses.removeAll { $0.kind == .speedBoost && $0.tag == Tune.speedTag }
    }

    // MARK: - D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        let me = s.units[bot].pos
        switch slot {
        case .skill1:
            // 鉤は最初に当たった敵を引く: 狙う相手より手前の線上にミニオン・モンスターが居るなら撃たない（鉤を無駄にしない）。
            // 手前に別の敵ヒーローが居る場合は、その相手を引けるので撃ってよい
            let delta = s.units[target].pos - me
            let dist = delta.length
            guard dist > 1e-6 else { return .useDefault }
            let dir = delta.normalized
            let team = s.units[bot].team
            for j in s.units.indices where j != target && s.units[j].team != team && !s.units[j].isStructure
                && s.units[j].kind != .hero {
                guard CombatSystem.isLiving(s, j) else { continue }
                let rel = s.units[j].pos - me
                let along = rel.dot(dir)
                guard along > 0, along < dist, along <= Tune.hookRange else { continue }
                let lateral = abs(rel.x * dir.y - rel.y * dir.x)
                if lateral <= Tune.hookWidth + s.units[j].radius { return .skip }
            }
            return .useDefault
        case .ultimate:
            // 鉤 → 奥義が持ち味: 射程内の敵ヒーローが、傷ついている / 鉤でスタン中 / 近くに味方が居る、のいずれかなら
            // 汎用の関門（倒せる・2 体）を飛び越えて撃つ。それ以外は汎用の判断
            guard fighting, s.units[target].kind == .hero, s.units[target].team != s.units[bot].team else {
                return .useDefault
            }
            let reach = Tune.ultReach + s.units[target].radius
            guard s.units[target].pos.distanceSquared(to: me) <= reach * reach else { return .skip }
            let hooked = s.units[target].statuses.contains { $0.kind == .stun && $0.tag == Tune.hookStunTag }
            var ready = hooked || s.units[target].hpRatio < Tune.botWeakHP
            if !ready {
                for j in s.units.indices where j != bot && s.units[j].kind == .hero
                    && s.units[j].team == s.units[bot].team {
                    guard CombatSystem.isLiving(s, j) else { continue }
                    if s.units[j].pos.distanceSquared(to: me) <= Tune.botAllyRange * Tune.botAllyRange {
                        ready = true
                        break
                    }
                }
            }
            return ready ? .castNow(.unit(s.units[target].id)) : .useDefault
        default:
            return .useDefault
        }
    }

    // MARK: - ダメージ（公式の式: 基礎[Lv] + 係数 × 能力値）

    /// スキル1 の鉤: 400〜650（+100% 物理攻撃）。
    static func hookDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.hookBase, rank: rank, ratio: Tune.hookAttackRatio, .totalAttack, stats: stats)
    }

    /// スキル2: 300〜450（+自身の最大 HP の 4%）。
    static func shockDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.shockBase, rank: rank, ratio: Tune.shockMaxHPRatio, .maxHP, stats: stats)
    }

    /// アルティメットの 1 撃: 50 / 60 / 70（+70% 物理攻撃）。
    static func ultHitDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.ultHitBase, rank: rank, ratio: Tune.ultHitAttackRatio, .totalAttack, stats: stats)
    }

    static func skillID(_ ctx: SimContext, _ slot: SkillSlot) -> String? {
        ctx.master.skill(hero: "H034", slot: slot)?.skillID
    }

    /// 奥義の対象の選び方: 指定ユニット → 指定地点に近い敵 → 向きに近い敵 → 自動（HP + シールド最小）。
    /// すべて「術者の中心から対象の縁まで reach 以内」の視認中の敵ヒーロー（無敵・対象不可を除く）。
    static func pickHero(_ s: SimState, caster i: Int, reach: Double, target: SkillTarget) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        func inReach(_ j: Int) -> Bool {
            guard j != i, s.units[j].kind == .hero, s.isTargetableEnemy(j, of: team),
                  !s.units[j].has(.invulnerable) else { return false }
            let r = reach + s.units[j].radius
            return s.units[j].pos.distanceSquared(to: pos) <= r * r
        }
        if case .unit(let id) = target, let j = s.index(of: id), inReach(j) { return j }

        var best: Int?
        var bestKey = Double.infinity
        for j in s.units.indices where inReach(j) {
            let key: Double
            switch target {
            case .point(let p):
                key = s.units[j].pos.distanceSquared(to: p)
            case .direction(let d):
                let delta = s.units[j].pos - pos
                let len = delta.length
                let cosine = len > 1e-9 ? delta.dot(d.normalized) / len : 1
                key = (1 - cosine) * 1e7 + len
            case .unit, .none:
                key = max(0, s.units[j].hp) + s.units[j].totalShield
            }
            if key < bestKey {
                bestKey = key
                best = j
            }
        }
        return best
    }
}
