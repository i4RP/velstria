import Foundation

// 担当: kit-H027（docs/SKILL_KITS.md / docs/NEW_HEROES.md）
// H027 竜槍のジャルド = Velstria 版の Zilong（MLBB。調査: docs/kits/Zilong.md、対応表: 同ファイル末尾）。
// 数値は MLBB の日本語クライアントの公式の表をそのまま使う（スキル1・2 = Lv1〜6、アルティメット = Lv1〜3。rank = 公式の Lv。
//   換算・補間・スロット倍率なし。docs/kits/Zilong.md の「日本語クライアントの画面（2026-10-11・無加工の原本）」）。
//   パッシブ 竜の三連突き  — 攻撃エフェクト 50%。ダメージを与える（通常攻撃・スキル）たびに竜気 +1。3 つ（奥義中は 2 つ）で次の通常攻撃が
//                           射程の伸びた三連撃（1 撃 80 (+30% 物理攻撃) の通常攻撃ダメージ・命中ごとに 50 (+20% 物理攻撃) 回復）になる。
//                           各撃は攻撃エフェクトの 50%（装備の命中時効果と通常攻撃吸収が半分。命中数・竜気・通常攻撃の命中フックには数えない）。
//                           1 発目は通常攻撃と同じ tick、2・3 発目は 4 / 8 tick（0.133 / 0.267 秒）後（onTimer。対象が倒れた・射程外なら出ない。
//                           HP 50% 未満の +30 は 1 発ごとに、当たる瞬間の対象で決める）。間隔は MLBB の画面収録で測った値と同じ
//                           （4 コマおき。奥義の攻撃速度でも縮まない）。
//                           HP 50% 未満の相手へは通常攻撃・スキルのダメージが常に +30（固定値）。
//                           三連突きでない通常攻撃は公式の式「100 (+80% 物理攻撃)」（汎用の物理攻撃 100% を置き換える）。
//   S1   跳槍撃（槍の跳ね上げ）— 対象指定。敵を槍で跳ね上げ（打ち上げ 1.0 秒）、0.4 秒持ち上げてから 0.2 秒で頭上を越えて
//                           背後 144 へ放り投げる。250〜350 (+80% 物理攻撃)。
//   S2   竜牙突き（竜牙の踏み込み）— 対象指定の突進（毎秒 1520）。踏み込みざまに 250〜450 (+60% 物理攻撃) + 物理防御 −15〜30（固定値）2 秒、
//                           その後は通常攻撃へ。敵を倒すたびにクールダウンがリセットされる（ヒーローは止めを刺したとき。ミニオン・モンスターは
//                           直前 0.5 秒以内に傷つけたものが倒れたとき）。ボットはミニオン・ジャングルにも使う（botFarm。リセットの連鎖で周回が速くなる）。
//   奥義 至高の武人        — 自己強化 7.5 秒: 移動速度 +40%・攻撃速度 +35/45/55%・スロウ解除と無効。
//                           三連突きは 2 回のダメージごとに発動する。ダメージ・CC は無い。
// 再使用の窓は Zilong に無いので使わない（SkillSystem.cast の経路は 3 スキルとも初回発動のみ）。
// マナ消費は公式の表（HeroKits.resourceCost。MLBB の趙子龍は Mana なので公式の値そのまま）。
// 幾何と時間（射程・突進の速さ・打ち上げと放り投げ・三連突きの間隔・奥義の秒数）は MLBB の画面収録で測った値
// （docs/kits/Zilong.md「動画で測った値（2026-10-16）」。ダメージ・係数・CD・MP は公式の表のまま）。
//
// 状態（KitState）:
//   ints[0]  = 竜気（0..3）
//   timers[0] = 奥義の残り秒          timers[1] = 「直前に傷つけた敵が倒れたら S2 リセット」の窓（0.5 秒）
//   ids[0]   = 直前に傷つけた敵（ヒーロー・構造物以外）  ids[1] = S2 の突進先の敵
//   reals[0] = S2 の突進ダメージ      reals[1] = S2 の物理防御ダウン量（固定値）

extension KitState {
    var jarldCharge: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    var jarldUltRemaining: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    var jarldResetWindow: Double {
        get { timers[1] }
        set { timers[1] = newValue }
    }

    var jarldWatchedID: EntityID {
        get { ids[0] }
        set { ids[0] = newValue }
    }

    var jarldDashTargetID: EntityID {
        get { ids[1] }
        set { ids[1] = newValue }
    }

    var jarldDashDamage: Double {
        get { reals[0] }
        set { reals[0] = newValue }
    }

    var jarldDashShred: Double {
        get { reals[1] }
        set { reals[1] = newValue }
    }
}

struct Kit_H027: HeroKit {
    let heroID = "H027"
    var isReady: Bool { true }

    // MARK: - 数値（公式の表はそのまま。距離は Velstria 単位 = MLBB × 100）

    enum Tune {
        // パッシブ 竜の三連突き（公式: 攻撃エフェクト 50%、1 撃 80 (+30% 物理攻撃) の通常攻撃ダメージ、回復 50 (+20% 物理攻撃)）
        static let flurryHits = 3
        static let flurryFlat = 80.0
        static let flurryAttackRatio = 0.30
        static let flurryHealFlat = 50.0
        static let flurryHealRatio = 0.20
        /// 三連突きの各撃が引き継ぐ攻撃エフェクトの割合（公式「攻撃エフェクト: 50%」。HitPayload.attackEffect）。
        static let flurryAttackEffect = 0.5
        /// 竜気がたまる数。奥義中は 2。
        static let chargeNormal = 3
        static let chargeUlt = 2
        /// 三連突きの 2・3 発目を予約する間隔（秒）。予約は「撃った tick を 1 回目に数えて」減るので、0.14 秒の予約は 4 tick 後
        /// （0.133 秒）、0.28 秒は 8 tick 後（0.267 秒）に当たる。MLBB の画面収録（30fps）の的の総ダメージ・体力の表示が変わるコマも
        /// 1 発目から 4 / 8 コマ後（三連突き 9 回すべて。奥義の攻撃速度 +55% の間・物理防御ダウン中も同じ）で、この値と一致する
        /// （ダメージの数字の出始めは 2 発目以降が 1 コマ遅れて見える）。被弾演出（Effekseer の近接ヒットは同じ相手へ 0.12 秒に 1 回）に
        /// 潰されない（0.13 だと 3 tick = 0.1 秒おきになる）。
        static let flurryGap = 0.14
        /// 遅れて当たる発が届く余裕（射程 + 三連突きの伸び + 半径の和に足す。相手が少し動いても外れない程度）。
        static let flurrySlack = 30.0
        /// 三連突き中の射程の伸び（MLBB の通常攻撃の射程 1.8 → 三連突きの準備中 2.5 = +0.7 ユニット。Velstria 単位 × 100）。
        /// 画面収録の射程の円も、竜気 2 つまで 1.78、満タンで 2.48（縮尺 62.3 px / 単位）で公式の値と合う。
        static let flurryRangeBonus = 70.0
        static let rangeTag = "kit.H027.flurryRange"
        /// HP がこの割合未満の相手へ、通常攻撃・スキルのダメージが固定で +executeFlat（公式。防御の前に足す）。
        static let executeBelow = 0.5
        static let executeFlat = 30.0
        /// 通常攻撃そのものの式（日本語クライアント・Liquipedia・Fandom のパッシブの文「通常攻撃は 100 (+80% 物理攻撃) の物理ダメージを与える」）。
        /// sim の汎用の通常攻撃（物理攻撃の 100%）を、100 + 物理攻撃 80% に置き換える（会心の倍率はそのまま掛かる）。
        static let basicFlat = 100.0
        static let basicAttackRatio = 0.80

        // S1 槍の跳ね上げ（千鈞担槍）。幾何と時間は MLBB の画面収録で測った値（docs/kits/Zilong.md「動画で測った値」）
        /// 射程（術者の中心から対象の縁まで）。照準の円の半径 2.97 単位（通常攻撃の円 1.78 = 公式 1.8 で割り戻すと 3.0）。
        static let flipReach = 300.0
        /// 打ち上げ（ノックアップ）の秒数。命中のコマから的の「ノックアップ」の表示と時間のバーが消えるまで 31 コマ（1.03 秒。以前の推測は 0.8）。
        static let flipAirborne = 1.0
        /// 命中から放り投げるまで（対象を槍で持ち上げたまま。的の体力バーがその場で止まっている 12 コマ = 0.40 秒）。
        static let flipHold = 0.4
        /// 頭上を越えて背後へ飛ぶ時間（6 コマ = 0.20 秒）。着地の後も打ち上げは残る（命中から合計 flipAirborne）。
        static let flipFlight = 0.2
        /// 放り投げた敵が着地する、術者の中心からの距離（背後）。画面収録で 1.43〜1.44 単位（2026-10-16 までの推測は 170）。
        static let flipLandingGap = 144.0
        /// 公式の基礎ダメージ（Lv1〜6）と係数（+80% 物理攻撃 = 合計の物理攻撃）。
        static let flipBase: [Double] = [250, 270, 290, 310, 330, 350]
        static let flipAttackRatio = 0.8
        static let flipCooldown: [Double] = [12.0, 11.5, 11.0, 10.5, 10.0, 9.5]
        static let flipCost: [Double] = [80, 85, 90, 95, 100, 105]

        // S2 竜牙の踏み込み（破陣槍）。幾何と時間は MLBB の画面収録で測った値
        /// 射程（術者の中心から対象の縁まで）。照準の円の半径 4.47 単位（2 回。通常攻撃の円 1.78 = 公式 1.8 で割り戻すと 4.52）。
        static let strikeReach = 450.0
        /// 突進の速さ。床の 1 コマの変位 31.7 px（3.40 単位を 6.7 コマ、3.66 単位を 7.25 コマ）= 毎秒 15.2 単位。
        /// 距離によらず同じ速さ（2026-10-16 までの推測は 2400）。
        static let strikeSpeed = 1520.0
        /// 到着時に対象がこれより離れていたら外れ（突進の追尾はしない）。
        static let strikeSlack = 260.0
        /// 公式の基礎ダメージ（Lv1〜6）と係数（+60% 物理攻撃 = 合計の物理攻撃）。
        static let strikeBase: [Double] = [250, 290, 330, 370, 410, 450]
        static let strikeAttackRatio = 0.6
        /// 公式の物理防御ダウン（固定値、Lv1〜6）と秒数（画面収録で的の物理防御 −30 の表示が 63〜64 コマ = 2.1 秒。公式の 2 秒のまま）。
        static let shredFlat: [Double] = [15, 18, 21, 24, 27, 30]
        static let shredDuration = 2.0
        static let shredTag = "kit.H027.shred"
        /// 直前に傷つけたミニオン・モンスターが、この秒数以内に倒れたら S2 リセット（Fandom の 1.8.08 の更新: ダメージの 0.5 秒以内に
        /// 倒れたミニオンも数える）。ヒーローは止めを刺したときだけ（onKillOrAssist）。
        static let resetWindow = 0.5
        static let strikeCooldown: [Double] = [12.0, 11.4, 10.8, 10.2, 9.6, 9.0]
        static let strikeCost: [Double] = [40]

        // 奥義 至高の武人（武神降臨）。画面収録で自分の体力バーの印（奥義の絵）が 226 コマ = 7.53 秒、歩きは 1.40 倍（公式の値のまま）
        static let ultDuration = 7.5
        static let ultMoveSpeed = 0.40
        static let ultAttackSpeed: [Double] = [0.35, 0.45, 0.55]
        static let ultMoveTag = "kit.H027.ult.move"
        static let ultAttackTag = "kit.H027.ult.attack"
        static let ultCooldown: [Double] = [35, 31, 27]
        static let ultCost: [Double] = [120, 140, 160]
    }

    private enum Code {
        static let strikeArrive = 1
        static let flurryHit = 2
        static let flipThrow = 3
    }

    /// HitPayload.kitEvent（三連突きの命中: 竜気にはしないが、S2 リセットの窓には入れる）。
    private enum Event {
        static let flurryHit = 1
    }

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        var t = base
        switch slot {
        case .skill1:
            // 対象指定（槍で跳ね上げる）。HUD・FX は cone の近接として扱い、shape で対象指定を示す（術者は動かない: バインド中も撃てる）
            t.aim = .unit
            t.range = Tune.flipReach
            t.radius = 150
            t.shape = .lockOn
            t.requiresTarget = true
        case .skill2:
            // 対象指定の突進（ブリンク系の archetype。突進の着地 AoE ゾーンは作らない。バインド中は撃てない）
            t = SkillTargeting(archetype: .targetedBlink, aim: .unit, range: Tune.strikeReach, radius: 150,
                               shape: .lockOn, requiresTarget: true)
        case .ultimate:
            // 自己強化（範囲・対象なし）。radius はボットが「近くに敵が居る」と数える目安と演出の大きさ
            t = SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: 350, shape: .selfRing)
        default:
            break
        }
        return t
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        var n = base
        switch slot {
        case .passive:
            n.hits = Tune.flurryHits
            n.damage = Self.flurryHitDamage(attack: stats.attack)
            n.heal = Self.flurryHeal(attack: stats.attack)
            n.damageType = .physical
            // 説明文に出す値は整数にそろえる（実際の値は damage / heal が持つ）
            n.extras = [KitStat(key: "flurryDamage", value: n.damage.rounded()),
                        KitStat(key: "flurryHeal", value: n.heal.rounded()),
                        KitStat(key: "executeFlat", value: Tune.executeFlat),
                        KitStat(key: "charge", value: Double(Tune.chargeNormal)),
                        KitStat(key: "attackEffect", value: Tune.flurryAttackEffect * 100),
                        KitStat(key: "flurryFlat", value: Tune.flurryFlat),
                        KitStat(key: "flurryPct", value: Tune.flurryAttackRatio * 100),
                        KitStat(key: "healFlat", value: Tune.flurryHealFlat),
                        KitStat(key: "healPct", value: Tune.flurryHealRatio * 100),
                        KitStat(key: "basicFlat", value: Tune.basicFlat),
                        KitStat(key: "basicPct", value: Tune.basicAttackRatio * 100),
                        KitStat(key: "basicDamage", value: Self.basicDamage(attack: stats.attack).rounded())]
        case .skill1:
            n.damage = Self.flipDamage(rank: rank, stats: stats)
            n.cooldown = Kit.cooldown(Tune.flipCooldown, rank: rank, stats: stats)
            n.cc = .knockback
            n.ccDuration = Tune.flipAirborne
            n.extras = [KitStat(key: "airborne", value: Tune.flipAirborne),
                        KitStat(key: "executeFlat", value: Tune.executeFlat),
                        KitStat(key: "base", value: Kit.level(Tune.flipBase, rank: rank)),
                        KitStat(key: "atkPct", value: Tune.flipAttackRatio * 100)]
        case .skill2:
            n.damage = Self.strikeDamage(rank: rank, stats: stats)
            n.cooldown = Kit.cooldown(Tune.strikeCooldown, rank: rank, stats: stats)
            n.cc = .none
            n.ccDuration = 0
            n.extras = [KitStat(key: "shred", value: Self.shredFlat(rank: rank)),
                        KitStat(key: "shredDuration", value: Tune.shredDuration),
                        KitStat(key: "resetWindow", value: Tune.resetWindow),
                        KitStat(key: "base", value: Kit.level(Tune.strikeBase, rank: rank)),
                        KitStat(key: "atkPct", value: Tune.strikeAttackRatio * 100)]
        case .ultimate:
            n.damage = 0
            n.hits = 1
            n.cc = .none
            n.ccIsUltimate = false
            n.ccDuration = 0
            // 汎用の連撃の被ダメ軽減は持たない（自己強化のみ）
            n.damageReduction = 0
            n.damageReductionDuration = 0
            n.cooldown = Kit.cooldown(Tune.ultCooldown, rank: rank, stats: stats)
            n.extras = [KitStat(key: "moveSpeed", value: Tune.ultMoveSpeed * 100),
                        KitStat(key: "attackSpeed", value: Kit.level(Tune.ultAttackSpeed, rank: rank) * 100),
                        KitStat(key: "duration", value: Tune.ultDuration),
                        KitStat(key: "charge", value: Double(Tune.chargeUlt))]
        }
        return n
    }

    /// ランクごとのマナ消費（公式の表: スキル1 80〜105、スキル2 40、アルティメット 120 / 140 / 160）。Mana なので公式の値そのまま。
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double {
        let table: [Double]
        switch slot {
        case .skill1: table = Tune.flipCost
        case .skill2: table = Tune.strikeCost
        case .ultimate: table = Tune.ultCost
        case .passive: return base
        }
        return HeroKits.resourceCost(Kit.level(table, rank: rank), hero: hero)
    }

    /// 説明文は公式の文の構造に合わせる（数値は {トークン} で sim から。{base}(+{atkPct}%物理攻撃) は公式の値そのもの）。
    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "攻撃エフェクト: {attackEffect}%"
                    + "\n\n通常攻撃かスキルでダメージを{charge}回与えると、次の通常攻撃で竜の三連突きが発動し、対象を{hits}回攻撃する。"
                    + "1回ごとに{flurryFlat}(+{flurryPct}%物理攻撃)の通常攻撃ダメージ（現在{flurryDamage}）を与え、自身のHPを{healFlat}(+{healPct}%物理攻撃)（現在{flurryHeal}）回復する。"
                    + "\n\n通常攻撃は{basicFlat}(+{basicPct}%物理攻撃)の物理ダメージ（現在{basicDamage}）を与える。"
                    + "\n\n対象のHPが50%未満の場合、スキルと通常攻撃のダメージが{executeFlat}増加する。",
                en: "Attack Effect: {attackEffect}%"
                    + "\n\nAfter dealing damage {charge} times with basic attacks or skills, your next basic attack triggers Dragon Flurry, hitting the target {hits} times. "
                    + "Each hit deals {flurryFlat} (+{flurryPct}% Physical Attack) basic attack damage (now {flurryDamage}) and heals you for {healFlat} (+{healPct}% Physical Attack) HP (now {flurryHeal})."
                    + "\n\nYour basic attacks deal {basicFlat} (+{basicPct}% Physical Attack) physical damage (now {basicDamage})."
                    + "\n\nIf the target's HP is below 50%, all damage dealt by your skills and basic attacks is increased by {executeFlat}.",
                tags: [KitTag.buff, KitTag.heal])
        case .skill1:
            return KitText(
                ja: "対象の敵を槍で頭上へ跳ね上げて背後へ放り投げ、{base}(+{atkPct}%物理攻撃)の物理ダメージ（現在{damage}）を与える。対象は{airborne}秒間打ち上げられて行動できない。",
                en: "With your Spear, fling the target enemy over your head to land behind you, dealing {base} (+{atkPct}% Physical Attack) physical damage (now {damage}). The target is airborne for {airborne}s and cannot act.",
                tags: [KitTag.disrupt, KitTag.damage])
        case .skill2:
            return KitText(
                ja: "対象の敵に突きかかり、{base}(+{atkPct}%物理攻撃)の物理ダメージ（現在{damage}）を与えて、物理防御を{shredDuration}秒間{shred}低下させる。踏み込んだあとはそのまま通常攻撃に移る。"
                    + "\n\n敵をキルするたびに、このスキルのクールダウンがリセットされる（直前に傷つけたミニオン・モンスターが{resetWindow}秒以内に倒れたときも）。",
                en: "Lunge at the target enemy, dealing {base} (+{atkPct}% Physical Attack) physical damage (now {damage}) and reducing their Physical Defense by {shred} for {shredDuration}s, then follow up with a basic attack. "
                    + "\n\nThe cooldown resets each time you kill an enemy (also when a minion or monster you just damaged dies within {resetWindow}s).",
                tags: [KitTag.mobility, KitTag.debuff])
        case .ultimate:
            return KitText(
                ja: "自身のスロウ効果をすべて解除し、{duration}秒間 移動速度+{moveSpeed}%・攻撃速度+{attackSpeed}%とスロウ無効を得る（スタンなどスロウ以外の行動阻害は防げない）。"
                    + "\n\nこの間は、{charge}回ごとに竜の三連突きが発動する（通常は\(Tune.chargeNormal)回）。",
                en: "Remove all slow effects on yourself and gain {moveSpeed}% Movement Speed, {attackSpeed}% Attack Speed and Slow Immunity for {duration}s (stuns and other disables still work on you). "
                    + "\n\nFor the duration, Dragon Flurry triggers after every {charge} hits (instead of \(Tune.chargeNormal)).",
                tags: [KitTag.haste, KitTag.buff])
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            let need = k.jarldUltRemaining > 0 ? Tune.chargeUlt : Tune.chargeNormal
            return KitBadge(kind: .stacks, value: min(k.jarldCharge, need), maxValue: need)
        case .ultimate:
            guard k.jarldUltRemaining > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.jarldUltRemaining, total: Tune.ultDuration)
        default:
            return nil
        }
    }

    /// 次の通常攻撃が三連突き（竜気が必要数 = 3、奥義中 2 たまっている）。shapeBasicAttack の分かれ目と同じ条件。
    func empoweredAttackReady(hero: HeroData) -> Bool {
        guard let k = hero.kit else { return false }
        return k.jarldCharge >= (k.jarldUltRemaining > 0 ? Tune.chargeUlt : Tune.chargeNormal)
    }

    /// 竜気を必要数まで満たす（演出の撮影用）。
    func primeEmpoweredAttack(hero: inout HeroData) {
        guard let k = hero.kit else { return }
        hero.kit!.jarldCharge = k.jarldUltRemaining > 0 ? Tune.chargeUlt : Tune.chargeNormal
    }

    /// 演出・モーション・音が読む三連突きの時刻と寸法（Tune そのもの。docs/vfx/RANGES.md）。
    /// flurryGap は予約の秒（実際の間隔は Kit.firesAfter で tick に丸めた flurryInterval）。
    func fxValues(slot: SkillSlot, stage: Int) -> [KitFXValue] {
        guard slot == .passive else { return [] }
        return [KitFXValue("flurryHits", Double(Tune.flurryHits), .count),
                KitFXValue("flurryGap", Tune.flurryGap, .seconds),
                KitFXValue("flurryInterval", Kit.firesAfter(Tune.flurryGap), .seconds),
                KitFXValue("flurryRangeBonus", Tune.flurryRangeBonus, .distance),
                KitFXValue("chargeNormal", Double(Tune.chargeNormal), .count),
                KitFXValue("chargeUlt", Double(Tune.chargeUlt), .count)]
    }

    // MARK: - B. 実行

    func resolveAim(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot, stage: Int,
                    targeting: SkillTargeting, target: SkillTarget) -> SkillAim?? {
        switch slot {
        case .skill1, .skill2:
            // 対象指定: 射程内の敵が居なければ拒否（コスト・CD を消費しない）
            guard let u = Self.pickTarget(s, caster: caster, reach: targeting.reach, target: target) else {
                return .some(nil)
            }
            return .some(SkillAiming.aim(at: u, s, caster: caster, range: targeting.range,
                                         facing: Vec2.fromAngle(s.units[caster].facing)))
        case .ultimate:
            // 自己強化: 敵が居なくても撃てる
            let facing = Vec2.fromAngle(s.units[caster].facing)
            return .some(SkillAim(direction: facing, point: s.units[caster].pos, unit: nil, distance: 0))
        default:
            return nil
        }
    }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        switch c.slot {
        case .skill1: castFlip(&s, ctx, c)
        case .skill2: castStrike(&s, ctx, c)
        case .ultimate: castUltimate(&s, ctx, c)
        case .passive: break
        }
        return .done
    }

    /// S1: 敵を跳ね上げてダメージ → 打ち上げ（1.0 秒）→ 0.4 秒持ち上げたまま → 0.2 秒で術者の頭上を越えて背後へ放り投げる
    /// （MLBB の画面収録: 命中から 0.4 秒は対象がその場に浮き、0.6 秒で背後に着地、1.0 秒で打ち上げが解ける）。
    private func castFlip(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        guard let t = c.aim.unit else { return }
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: s.units[t].pos, unit: t, shape: .lockOn,
                     duration: Tune.flipAirborne, count: 1)
        var p = Self.skillPayload(c, damage: c.numbers.damage + Self.executeBonus(s, t), effects:
                                  [.knockUp(duration: Tune.flipAirborne)])
        p.originPos = s.units[i].pos
        CombatSystem.applyHit(&s, ctx, sourceID: s.units[i].id, team: s.units[i].team, targetIndex: t, payload: p,
                              from: s.units[i].pos)
        // 打ち上げが入った相手だけ、持ち上げた後に頭上を越えて背後へ投げる（CC 無効・構造物には動かない）。
        // 投げるのは対象に入った打ち上げの続きなので、術者がスタンされても取り消さない（術者が倒れたら投げずにその場で落ちる）
        guard CombatSystem.isLiving(s, t), s.units[t].has(.airborne), Kit.canDisplace(s, ctx, t) else { return }
        Kit.schedule(&s, caster: i, slot: .skill1, code: Code.flipThrow, after: Tune.flipHold, targetID: s.units[t].id,
                     interruptible: false)
    }

    /// S1 の続き（命中から flipHold 秒）: まだ打ち上げられている対象を、その時の術者の頭上を越えて背後 flipLandingGap へ flipFlight 秒で
    /// 飛ばす。打ち上げが先に解けた（強靭・浄化）・倒れた・CC 無効になった相手は動かさない。
    private func throwOverhead(_ s: inout SimState, _ ctx: SimContext, owner i: Int, timer: KitTimer) {
        guard let t = s.index(of: timer.targetID), CombatSystem.isLiving(s, t), s.units[t].has(.airborne),
              Kit.canDisplace(s, ctx, t) else { return }
        let from = s.units[t].pos
        let me = s.units[i].pos
        var dir = (me - from).normalized
        if dir == .zero { dir = -Vec2.fromAngle(s.units[i].facing) }
        MovementSystem.knockback(&s, ctx, unitIndex: t, direction: dir,
                                 distance: from.distance(to: me) + Tune.flipLandingGap, duration: Tune.flipFlight)
    }

    /// S2: 対象へ突進し、到着した tick に 1 度だけダメージ + 物理防御ダウン + 通常攻撃へ。
    private func castStrike(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        guard let t = c.aim.unit else { return }
        let from = s.units[i].pos
        let toTarget = s.units[t].pos - from
        let dir = toTarget.normalized == .zero ? Vec2.fromAngle(s.units[i].facing) : toTarget.normalized
        // 対象の縁（術者の半径込み）で止まる
        let gap = s.units[i].radius + s.units[t].radius + 5
        let travel = min(Tune.strikeReach, max(0, toTarget.length - gap))
        let targetID = s.units[t].id
        s.units[i].hero!.kit!.jarldDashTargetID = targetID
        s.units[i].hero!.kit!.jarldDashDamage = c.numbers.damage
        s.units[i].hero!.kit!.jarldDashShred = Self.shredFlat(rank: c.numbers.rank)
        // 経路上の敵には当たらない（affectsEnemies = false）。ノックアップ・制圧の中断と着地の通知だけを使う
        let carrier = HitPayload(damage: 0, damageType: .physical, source: .skill(.skill2), affectsEnemies: false)
        let landing = Kit.dashSweeping(&s, ctx, caster: i, slot: .skill2, to: from + dir * travel,
                                       speed: Tune.strikeSpeed, payload: carrier, radius: 0,
                                       arriveCode: Code.strikeArrive)
        Kit.emitCast(&s, c, origin: from, target: s.units[t].pos, unit: t, shape: .lockOn,
                     duration: from.distance(to: landing) / Tune.strikeSpeed, count: 1)
    }

    /// 奥義: スロウ解除 + 移動速度・攻撃速度 + 三連突きの必要回数を 2 に。
    private func castUltimate(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let id = s.units[i].id
        s.units[i].statuses.removeAll { $0.kind == .slow }
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .speedBoost, duration: Tune.ultDuration,
                                                                 magnitude: Tune.ultMoveSpeed, sourceID: id,
                                                                 tag: Tune.ultMoveTag))
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .attackSpeedBoost, duration: Tune.ultDuration,
                                                                 magnitude: Kit.level(Tune.ultAttackSpeed, rank: c.numbers.rank),
                                                                 sourceID: id, tag: Tune.ultAttackTag))
        s.units[i].hero!.kit!.jarldUltRemaining = Tune.ultDuration
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: s.units[i].pos, shape: .selfRing,
                     duration: Tune.ultDuration, count: Tune.chargeUlt)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        if timer.code == Code.flurryHit {
            flurryHit(&s, ctx, owner: owner, timer: timer)
            return
        }
        if timer.code == Code.flipThrow {
            throwOverhead(&s, ctx, owner: owner, timer: timer)
            return
        }
        guard timer.code == Code.strikeArrive, let kit = s.units[owner].hero?.kit else { return }
        let targetID = kit.jarldDashTargetID
        s.units[owner].hero!.kit!.jarldDashTargetID = 0
        guard let t = s.index(of: targetID), CombatSystem.isLiving(s, t), !s.units[t].has(.untargetable),
              s.units[t].team != s.units[owner].team else { return }
        // 突進の間に対象が離れすぎていたら外れ
        let reach = s.units[owner].radius + s.units[t].radius + Tune.strikeSlack
        guard s.units[owner].pos.distanceSquared(to: s.units[t].pos) <= reach * reach else { return }

        // 物理防御を固定値で下げる（公式 15〜30、2 秒。魔法防御は変えない: flatArmorMod）。ダメージの後に付くので、この一撃には掛からない
        let shred = StatusEffect(kind: .flatArmorMod, duration: Tune.shredDuration, magnitude: -kit.jarldDashShred,
                                 sourceID: s.units[owner].id, tag: Tune.shredTag)
        var p = HitPayload(damage: kit.jarldDashDamage + Self.executeBonus(s, t), damageType: .physical,
                           source: .skill(.skill2), statuses: [shred], skillID: Self.skillID(ctx, .skill2))
        p.originPos = s.units[owner].pos
        CombatSystem.applyHit(&s, ctx, sourceID: s.units[owner].id, team: s.units[owner].team, targetIndex: t,
                              payload: p, from: s.units[owner].pos)
        // 突進のあとはそのまま通常攻撃（調査資料: 未確認だが複数の解説が言及）
        if CombatSystem.isLiving(s, owner), CombatSystem.isLiving(s, t) {
            s.units[owner].attackTargetID = s.units[t].id
            s.units[owner].attackCooldown = 0
        }
    }

    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {
        // 三連突きの命中: 竜気にはしない（攻撃エフェクトの割合の命中は通常攻撃の命中フックを通らない）が、S2 リセットの窓には入れる
        guard event == Event.flurryHit, dealt > 0 else { return }
        watch(&s, owner, target)
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        guard let k = s.units[owner].hero?.kit else { return }

        // 奥義中: スロウ無効
        if k.jarldUltRemaining > 0, s.units[owner].has(.slow) {
            s.units[owner].statuses.removeAll { $0.kind == .slow }
        }

        // 三連突きの準備ができている間は射程が伸びる（0.5 秒の状態を短くなったら更新し、イベントを出し続けない）
        let need = k.jarldUltRemaining > 0 ? Tune.chargeUlt : Tune.chargeNormal
        if k.jarldCharge >= need {
            let left = s.units[owner].statuses.first { $0.kind == .attackRangeBoost && $0.tag == Tune.rangeTag }?.remaining
            if left == nil || left! < 0.2 {
                Kit.grantAttackRange(&s, target: owner, amount: Tune.flurryRangeBonus, duration: 0.5, tag: Tune.rangeTag)
            }
        }

        // 直前に傷つけた敵（ミニオン・モンスターなど）が 0.5 秒以内に倒れたら S2 のクールダウンをリセット
        if k.jarldWatchedID != 0 {
            if k.jarldResetWindow <= 0 {
                s.units[owner].hero!.kit!.jarldWatchedID = 0
            } else if Self.isDead(s, k.jarldWatchedID) {
                s.units[owner].hero!.kit!.jarldWatchedID = 0
                s.units[owner].hero!.kit!.jarldResetWindow = 0
                Kit.setCooldown(&s, ctx, caster: owner, slot: .skill2, seconds: 0)
            }
        }
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // 突進中のノックアップ・制圧（突進が取り消された）: 到着処理が呼ばれないので突進先の記録だけ捨てる。
        // スタンは突進を止めず、三連突きの残り（中断できる予約）だけを取り消すので、突進が続いていれば記録は残す
        guard s.units[owner].hero?.kit?.sweep == nil else { return }
        s.units[owner].hero?.kit?.jarldDashTargetID = 0
    }

    // MARK: - C. パッシブ

    func shapeBasicAttack(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                          plan: inout BasicAttackPlan) {
        guard let k = s.units[attacker].hero?.kit else { return }
        let flat = Self.executeBonus(s, target)
        let attack = s.units[attacker].stats.attack
        let need = k.jarldUltRemaining > 0 ? Tune.chargeUlt : Tune.chargeNormal
        guard k.jarldCharge >= need else {
            // 通常攻撃の式: 物理攻撃 × 会心倍率 → (100 + 物理攻撃 80%) × 会心倍率（会心・会心軽減の倍率は payload のまま）
            if attack > 0 { plan.payload.damage *= Self.basicDamage(attack: attack) / attack }
            plan.payload.damage += flat
            return
        }
        // 三連突き: 同じ対象へ 3 回。1 発目は通常攻撃と同じ tick（ここで整形）、2・3 発目は 4 / 8 tick（約 0.13 / 0.27 秒）後（onTimer）。
        // 1 撃 80 + 物理攻撃 30%、命中ごとに 50 + 20% 回復。会心は 3 発で 1 回の判定を共有する（会心倍率は通常攻撃と同じ式）。
        // 各撃は攻撃エフェクトの 50%（appliesOnHit = false: 命中数・竜気・通常攻撃の命中フックには数えない）
        let crit = plan.payload.isCrit
            ? CombatSystem.critMultiplier(attacker: s.units[attacker].stats, target: s.units[target].stats) : 1
        var hit = plan.payload
        hit.damage = Self.flurryHitDamage(attack: attack) * crit + flat
        hit.appliesOnHit = false
        hit.attackEffect = Tune.flurryAttackEffect
        hit.kitEvent = Event.flurryHit
        hit.effects = [.healOwner(flat: Self.flurryHeal(attack: attack), ratioOfDealt: 0)]
        plan.payload = hit
        let targetID = s.units[target].id
        for n in 1..<Tune.flurryHits {
            // param = 会心倍率（会心でなければ 1）、point.x = 会心か（0 / 1）。当たる瞬間に対象の状態を見直すので、ダメージは持たない
            Kit.schedule(&s, caster: attacker, slot: .passive, code: Code.flurryHit, after: Tune.flurryGap * Double(n),
                         targetID: targetID, index: n, param: crit, point: Vec2(plan.payload.isCrit ? 1 : 0, 0),
                         interruptible: true)
        }
        // 描画・音への合図（判定・数値は変えない）。2・3 発目は flurryGap の予約が発火する tick（4 / 8 tick 後）に当たる。
        // 届く距離は伸びた射程（範囲の伸びを外す前に出す）
        Kit.emitEmpoweredAttack(&s, attacker: attacker, target: target, hits: Tune.flurryHits,
                                interval: Kit.firesAfter(Tune.flurryGap))
        s.units[attacker].hero!.kit!.jarldCharge = 0
        s.units[attacker].statuses.removeAll { $0.kind == .attackRangeBoost && $0.tag == Tune.rangeTag }
    }

    /// 三連突きの 2・3 発目。対象が倒れた・射程（伸びを含む）の外へ出た・対象不可なら出ない。
    /// HP 50% 未満の +30 は、当たる瞬間の対象で決める。竜気にはならない（攻撃エフェクト 50% の命中）。
    private func flurryHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard let t = s.index(of: timer.targetID), CombatSystem.isLiving(s, t), !s.units[t].has(.untargetable),
              s.units[t].team != s.units[owner].team else { return }
        let reach = s.units[owner].stats.attackRange + Tune.flurryRangeBonus + s.units[owner].radius
            + s.units[t].radius + Tune.flurrySlack
        guard s.units[owner].pos.distanceSquared(to: s.units[t].pos) <= reach * reach else { return }
        let attack = s.units[owner].stats.attack
        let isCrit = timer.point.x > 0.5
        var p = HitPayload(damage: Self.flurryHitDamage(attack: attack) * max(1, timer.param) + Self.executeBonus(s, t),
                           damageType: .physical, source: .basicAttack, isCrit: isCrit, appliesOnHit: false,
                           effects: [.healOwner(flat: Self.flurryHeal(attack: attack), ratioOfDealt: 0)],
                           kitEvent: Event.flurryHit, attackEffect: Tune.flurryAttackEffect)
        p.originPos = s.units[owner].pos
        CombatSystem.applyHit(&s, ctx, sourceID: s.units[owner].id, team: s.units[owner].team, targetIndex: t,
                              payload: p, from: s.units[owner].pos)
    }

    func onBasicAttackHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, damage: Double) {
        // 三連突きでない通常攻撃の命中（三連突きの命中は攻撃エフェクトの割合の命中なので、ここを通らない）
        guard s.units[attacker].hero?.kit != nil else { return }
        gainCharge(&s, attacker)
        watch(&s, attacker, target)
    }

    func onSkillHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, slot: SkillSlot,
                    damage: Double) {
        // 「ダメージを与えた」ときだけ（CC のみの命中は数えない）
        guard damage > 0, s.units[attacker].hero?.kit != nil else { return }
        gainCharge(&s, attacker)
        watch(&s, attacker, target)
    }

    func onKillOrAssist(_ s: inout SimState, _ ctx: SimContext, hero: Int, victim: Int) {
        // ヒーローのキル（止めを刺したのが自分）で S2 リセット。アシストでは戻らない
        guard s.units[victim].lastAttackerID == s.units[hero].id else { return }
        Kit.setCooldown(&s, ctx, caster: hero, slot: .skill2, seconds: 0)
    }

    // MARK: - D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        switch slot {
        case .ultimate:
            // 追撃・交戦の強化: 強化中は撃たない。交戦中の敵ヒーローに踏み込みの射程で届くなら、汎用の関門
            // （倒せる・2 体以上）を待たずに今撃つ（自己強化なので、殴り合いの頭に使うのが一番強い）
            guard (s.units[bot].hero?.kit?.jarldUltRemaining ?? 0) <= 0 else { return .skip }
            let foe = s.units[target]
            let dist = s.units[bot].pos.distance(to: foe.pos)
            if fighting, foe.kind == .hero, dist <= Tune.strikeReach + foe.radius { return .castNow(.none) }
            // それ以外（ミニオン・遠い敵）は従来どおり: 交戦中で敵が近く、汎用の関門を通ったときだけ
            guard fighting, dist <= 700 else { return .skip }
            return .cast(.none)
        default:
            return .useDefault
        }
    }

    /// ミニオン・ジャングルの集団にも竜牙突き（S2）を使ってよいか。倒すたびにリセットされるので、周回の連鎖に使える。
    /// HP が半分以上で、突進の先が敵のタワー・コアの射程に入らないときだけ。
    func botFarm(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 center: Vec2, count: Int) -> Bool {
        guard slot == .skill2, s.units[bot].hpRatio >= 0.5 else { return false }
        for u in s.units where u.isStructure && u.isAlive && u.team != s.units[bot].team {
            let r = Balance.towerRange + Balance.heroRadius + 120
            if u.pos.distanceSquared(to: center) <= r * r { return false }
        }
        return true
    }

    // MARK: - 部品

    private func gainCharge(_ s: inout SimState, _ i: Int) {
        let need = (s.units[i].hero?.kit?.jarldUltRemaining ?? 0) > 0 ? Tune.chargeUlt : Tune.chargeNormal
        let n = s.units[i].hero?.kit?.jarldCharge ?? 0
        s.units[i].hero?.kit?.jarldCharge = min(need, n + 1)
    }

    /// 直前に傷つけた敵を覚える（0.5 秒以内に倒れたら S2 リセット）。構造物と、ヒーロー（止めを刺したときだけ: onKillOrAssist）は除く。
    private func watch(_ s: inout SimState, _ i: Int, _ t: Int) {
        guard s.units.indices.contains(t), !s.units[t].isStructure, s.units[t].kind != .hero else { return }
        let id = s.units[t].id
        s.units[i].hero?.kit?.jarldWatchedID = id
        s.units[i].hero?.kit?.jarldResetWindow = Tune.resetWindow
    }

    static func isDead(_ s: SimState, _ id: EntityID) -> Bool {
        guard let t = s.index(of: id) else { return true }
        return !s.units[t].isAlive || s.units[t].hero?.isDead == true
    }

    /// 相手の HP が半分未満なら固定で +30。
    static func executeBonus(_ s: SimState, _ t: Int) -> Double {
        guard s.units.indices.contains(t), !s.units[t].isStructure, s.units[t].hpRatio < Tune.executeBelow else { return 0 }
        return Tune.executeFlat
    }

    /// 通常攻撃 1 発（会心なし）: 公式の 100 + 80% 物理攻撃（合計の物理攻撃）。
    static func basicDamage(attack: Double) -> Double {
        Tune.basicFlat + Tune.basicAttackRatio * max(0, attack)
    }

    /// 三連突き 1 回のダメージ（会心なし）: 公式の 80 + 30% 物理攻撃。
    static func flurryHitDamage(attack: Double) -> Double {
        Tune.flurryFlat + Tune.flurryAttackRatio * max(0, attack)
    }

    /// 三連突き 1 回の回復: 公式の 50 + 20% 物理攻撃（相手の種類によらない）。
    static func flurryHeal(attack: Double) -> Double { Tune.flurryHealFlat + Tune.flurryHealRatio * max(0, attack) }

    /// スキル1 のダメージ（公式: 250〜350 + 80% 物理攻撃）。
    static func flipDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.flipBase, rank: rank, ratio: Tune.flipAttackRatio, .totalAttack, stats: stats)
    }

    /// スキル2 のダメージ（公式: 250〜450 + 60% 物理攻撃）。
    static func strikeDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(Tune.strikeBase, rank: rank, ratio: Tune.strikeAttackRatio, .totalAttack, stats: stats)
    }

    /// 物理防御ダウン量（公式の固定値 15〜30）。
    static func shredFlat(rank: Int) -> Double { Kit.level(Tune.shredFlat, rank: rank) }

    static func skillID(_ ctx: SimContext, _ slot: SkillSlot) -> String? {
        ctx.master.skill(hero: "H027", slot: slot)?.skillID
    }

    private static func skillPayload(_ c: KitCast, damage: Double, effects: [HitEffect]) -> HitPayload {
        HitPayload(damage: damage, damageType: c.numbers.damageType, source: .skill(c.slot),
                   skillID: c.check.skill.skillID, effects: effects)
    }

    /// 対象指定の選び方: 指定ユニット → 指定地点に近い敵 → 向きに近い敵 → 自動（ヒーロー優先で HP + シールド最小）。
    /// すべて「術者の中心から対象の縁まで reach 以内」の視認中の敵（構造物・無敵・対象不可を除く）。
    static func pickTarget(_ s: SimState, caster i: Int, reach: Double, target: SkillTarget) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        func inReach(_ j: Int) -> Bool {
            guard j != i, !s.units[j].isStructure, s.isTargetableEnemy(j, of: team),
                  !s.units[j].has(.invulnerable) else { return false }
            let r = reach + s.units[j].radius
            return s.units[j].pos.distanceSquared(to: pos) <= r * r
        }
        if case .unit(let id) = target, let j = s.index(of: id), inReach(j) { return j }

        var best: Int?
        var bestKey = Double.infinity
        for j in s.units.indices where inReach(j) {
            let hero = s.units[j].kind == .hero
            var key: Double
            switch target {
            case .point(let p):
                key = s.units[j].pos.distanceSquared(to: p)
            case .direction(let d):
                let delta = s.units[j].pos - pos
                let len = delta.length
                let cosine = len > 1e-9 ? delta.dot(d.normalized) / len : 1
                key = (1 - cosine) * 1e7 + len
            case .unit, .none:
                key = hero ? max(0, s.units[j].hp) + s.units[j].totalShield : s.units[j].pos.distanceSquared(to: pos)
            }
            // ヒーローを先に（同じ基準の中で）
            if !hero { key += 1e12 }
            if key < bestKey {
                bestKey = key
                best = j
            }
        }
        return best
    }
}
