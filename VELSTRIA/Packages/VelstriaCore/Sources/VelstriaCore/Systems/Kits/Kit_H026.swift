import Foundation

// 担当: kit-H026（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Eudora.md）
// H026 紫電のエウリア = Velstria 版の Eudora（MLBB。調査: docs/kits/Eudora.md、対応表: 同ファイル末尾）。
// アルカニスト（遠隔 550・マナ）。ロールの汎用パッシブ（スキル命中で他スキルの CD 短縮）を置き換える。
//   パッシブ 超伝導        — スキルが命中した敵（ミニオンを除く）に「超伝導」の印を 5 秒付ける。
//                            印の付いた敵に当たると各スキルに追加効果（印そのものはダメージを増やさない）。
//   スキル1 分岐雷         — 前方の扇に雷（ミニオンには 2 倍）。超伝導の敵に当たると 1 秒の「雷の鎖」: 移動速度 +40%・継続ダメージ・
//                            終わりに追加ダメージ。追加ダメージが当たると S1 のクールダウンが 50% 縮む。同じ相手への鎖は 6 秒に 1 回まで
//                            （印は消費しないので、鎖が無限に繋がらないための制限）。
//   スキル2 雷球           — 対象指定の雷球（スタン 1 秒・魔防ダウン 1.8 秒）。超伝導の敵に当たると周囲の敵にも同じダメージが広がる
//                            （スタン・魔防ダウンはミニオンには広がらない）。
//   アルティメット 九天雷鳴 — 指定地点に遅れて落ちる大雷（中心に重く、外側に半分）。超伝導の敵に当たると、その敵を中心に少し遅れて
//                            雷が炸裂する（複数なら重なる）。
// 再使用の窓は Eudora に無いので使わない。
// 数値の正は Fandom の現行の表（docs/kits/Eudora.md の「公式（Fandom 現行）の数値」）。クールダウン・マナ・ダメージの表を Velstria のランク
// （スキル1・2 は 4 段、アルティメットは 3 段）へ線形補間し（ランク 1 = Lv1、最大ランク = 公式の最終 Lv）、ダメージは
// (基礎 + 係数 × 魔力) × スロット倍率 にスキルごとの換算（s1Scale ほか）を掛ける（公式どおり魔法攻撃だけで伸び、物理攻撃の係数は持たない）。
//
// 状態（KitState）:
//   timers[0] = 雷の鎖の残り秒（HUD 用）   timers[1...4] = ids[0...3] の相手へ次の鎖を結べるまでの残り秒（相手ごとのロックアウト）
//   ints[0] = 雷の鎖を結んだ回数   ints[1] = 鎖の終わりの一撃が当たった回数   ints[2] = 雷の炸裂を起こした回数
//   ints[3] = 雷球が周囲へ広がった回数   ints[4] = 超伝導を付けた回数（いずれも検証用）
//   ids[0...3] = 最近鎖を結んだ相手（4 体まで。空きが無ければ残りが最も短いものを入れ替える）

extension KitState {
    var euriaChainRemaining: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    var euriaChains: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    var euriaChainEnds: Int {
        get { ints[1] }
        set { ints[1] = newValue }
    }

    var euriaBursts: Int {
        get { ints[2] }
        set { ints[2] = newValue }
    }

    var euriaSplashes: Int {
        get { ints[3] }
        set { ints[3] = newValue }
    }

    var euriaMarksApplied: Int {
        get { ints[4] }
        set { ints[4] = newValue }
    }

    /// その相手へ次の鎖を結べるまでの残り秒（0 = 結べる）。
    func euriaChainLockout(for id: EntityID) -> Double {
        for k in 0..<4 where ids[k] == id && id != 0 { return timers[1 + k] }
        return 0
    }

    /// その相手へのロックアウトを始める（既にあれば更新、空きが無ければ残りが最も短いものと入れ替える）。
    mutating func setEuriaChainLockout(for id: EntityID, seconds: Double) {
        var slot = (0..<4).first { ids[$0] == id }
        if slot == nil { slot = (0..<4).first { timers[1 + $0] <= 0 } }
        if slot == nil { slot = (0..<4).min { timers[1 + $0] < timers[1 + $1] } }
        let k = slot ?? 0
        ids[k] = id
        timers[1 + k] = seconds
    }
}

/// エウリアの調整値（docs/kits/Eudora.md の数値を Velstria の単位・TTK に合わせたもの）。
enum EuriaTuning {
    // MARK: パッシブ（超伝導）
    /// 印の持続。日本語クライアント（2026-10-10 受領の画面）の 5 秒（Liquipedia・mlbbhub の 3 秒は古い）。
    static let markDuration: Double = 5
    static let markName = "sc"

    // MARK: S1（Forked Lightning）
    /// 扇の半角（調査に角度は無い）。射程はスキル定義（650）。
    static let s1HalfAngle: Double = Double.pi / 6
    /// 1 撃（最初の一撃 = 鎖の終わりの一撃）。公式: 275 / 320 / 365 / 410 / 455 / 500（+100% 魔法攻撃）。
    /// sim の式は (基礎 + 係数 × 魔力) × スロット倍率 × s1Scale（公式どおり物理攻撃の係数は持たない）。
    static let s1Base = (275.0, 500.0)
    static let s1PowerRatio: Double = 1.0
    /// 1 撃 377 → 686（以前の「汎用 S1 × 0.55」と同じ大きさ）。Lv1 をアルカニスト中央値の −15 pt 以内にするには 0.49 以上が要るが、
    /// そうすると鎖（2 撃 + 50% 短縮）で Lv6 / 12 が +17〜+50 pt になるので上げない（docs/kits/Eudora.md の「公式の数値に合わせる」）。
    static let s1Scale: Double = 0.343
    /// 継続ダメージ 1 回。公式: 10 / 12 / 14 / 16 / 18 / 20（+4% 魔法攻撃）。換算は s1Scale。
    static let dotBase = (10.0, 20.0)
    static let dotPowerRatio: Double = 0.04
    static let dotCount = 4
    static let dotInterval: Double = 0.2
    static let chainDuration: Double = 1.0
    /// 同じ相手へは、前の鎖を結んでからこの秒数が過ぎるまで次の鎖を結ばない。印は消費しない（印のあいだ S1 が当たるたびに鎖が繋がり、
    /// 終わりの一撃のクールダウン短縮で回り続けるのを抑える）。総当たりの勝率（アルカニスト中央値との差）は
    /// 制限なし Lv1 +40 / Lv6 +15 / Lv12 +41 pt → 3 秒で Lv1 +4 / Lv6 +12 / Lv12 +28 pt（全体の CD が半分だったころ。6 秒でも同程度）。
    /// CD が MLBB の秒数（2 倍）になったので、CD に対する割合を保って 6 秒にした（3 秒のままだと CD 短縮なしでは一度も効かない）。
    static let chainLockout: Double = 6.0
    static let chainSpeed: Double = 0.40
    /// 鎖が切れる距離（調査に無い。S1 の射程 650 に余裕を足した値）。術者と対象の中心間。
    static let chainLeash: Double = 800
    /// 鎖の終わりの一撃が当たったときの S1 のクールダウン短縮 = S1 のクールダウン（CD 短縮込み）の 50%（公式の説明文。
    /// 以前は mlbbhub の「1.5 秒」）。
    static let chainRefundRatio: Double = 0.5
    static let chainSpeedTag = KitTags.buff("H026", "chain")

    // MARK: S2（Ball Lightning）
    /// 公式: 300 / 320 / 340 / 360 / 380 / 400（+50% 魔法攻撃）。換算は s2Scale。
    static let s2Base = (300.0, 400.0)
    static let s2PowerRatio: Double = 0.5
    /// 580 → 773（公式の伸びは 1.33 倍で汎用の +30%/ランクより小さい）。0.644 でランク 2（Lv6）が以前の値（元のスキル値 × 0.81）と同じ。
    static let s2Scale: Double = 0.644
    static let s2Speed: Double = 1800
    static let s2Stun: Double = 1.0
    /// 魔防ダウン（固定値。調査: 10/13/16/19/22/25 の 6 段 → 4 段へ線形）と持続。
    static let shredRange = (10.0, 25.0)
    static let shredDuration: Double = 1.8
    /// 超伝導の敵に当たったときの広がり（調査に半径は無い）。
    static let splashRadius: Double = 260
    static let shredTag = KitTags.buff("H026", "shred")

    // MARK: 奥義（Thunder's Wrath）
    /// 公式（日本語クライアント）: 中心 600 / 800 / 1000（+160% 魔法攻撃）、外側 300 / 400 / 500（+100%）、
    /// サンダーバースト 330 / 440 / 550（+110%。Fandom の 300 / 425 / 550 は誤り）。
    /// 3 つとも換算は ultScale（アルティメットの 3 ランクは公式の Lv そのまま）。
    static let ultCenterBase = (600.0, 1000.0)
    static let ultCenterPowerRatio: Double = 1.6
    static let ultOuterBase = (300.0, 500.0)
    static let ultOuterPowerRatio: Double = 1.0
    static let burstBase = (330.0, 550.0)
    static let burstPowerRatio: Double = 1.1
    /// 中心 437 / 582 / 728、炸裂 218 / 309 / 400。0.49 で中心が以前の「汎用の奥義 × 0.82」と同じだが、公式の炸裂（中心の 0.5〜0.55 倍。以前は 0.40 倍）
    /// と終わりの一撃の 50% 短縮で Lv6 / 12 がアルカニスト中央値の +25 / +38 pt になったので、奥義を下げて合わせた（0.49 / 0.38 / 0.32 / 0.30 / 0.28 を比較）。
    static let ultScale: Double = 0.28
    static let ultCenterRadius: Double = 150
    static let ultOuterRadius: Double = 300
    static let ultDelay: Double = 0.8
    static let burstRadius: Double = 190
    static let burstDelay: Double = 0.5

    // MARK: クールダウン（MLBB の秒数そのまま。ランク間を線形補間し、CD 短縮を掛ける。全体倍率 Balance.Skills.cooldownScale は 1.0）
    /// 日本語クライアント: S1 は全 Lv 5.0 秒（Fandom の 7.0 → 5.0 は誤り）、S2 11.0 → 8.5、奥義 32 / 29 / 26。
    static let s1Cooldown = (5.0, 5.0)
    static let s2Cooldown = (11.0, 8.5)
    static let ultCooldown = (32.0, 26.0)

    // MARK: マナ（日本語クライアントの表をランクで線形補間。HeroKit.cost）
    /// S1 40 → 65、S2 80 → 105、奥義 130 / 160 / 190（Fandom の S1 50 → 70・S2 70 → 95 は誤り。その前はマスターの 62 / 74 / 118）。
    static let s1Cost = (40.0, 65.0)
    static let s2Cost = (80.0, 105.0)
    static let ultCost = (130.0, 190.0)

    /// HitPayload.kitEvent
    enum Event {
        static let fork = 1
        static let chainEnd = 2
        static let orb = 3
        static let orbSplash = 4
        static let thunder = 5
        static let burst = 6
    }

    /// KitTimer.code
    enum Code {
        static let dot = 1
        static let end = 2
        /// サンダーバースト（遅れて、対象を中心の範囲の「超伝導の敵」にだけダメージ）
        static let burst = 3
    }
}

struct Kit_H026: HeroKit {
    let heroID = "H026"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H026(isReady: true)` を HeroKits.testOverride に差すこともできる。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    typealias T = EuriaTuning

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 前方の扇（範囲の半径 = 射程）
            return SkillTargeting(archetype: .cone, aim: .direction, range: skill.range, radius: skill.range,
                                  shape: .fan, halfAngle: T.s1HalfAngle)
        case .skill2:
            // 対象指定の雷球（追尾する弾）。radius は表示用の弾の大きさ
            return SkillTargeting(archetype: .lineSkillshot, aim: .unit, range: skill.range, radius: 60,
                                  shape: .lockOn, requiresTarget: true)
        case .ultimate:
            // 地点指定（遅れて落ちる）。radius は外側の半径
            return SkillTargeting(archetype: .groundAoE, aim: .point, range: skill.range, radius: T.ultOuterRadius,
                                  shape: .circleAtPoint)
        case .passive:
            return base
        }
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        var n = base
        n.damageType = .magic
        switch slot {
        case .passive:
            n.extras = [KitStat(key: "markDuration", value: T.markDuration)]
        case .skill1:
            // damage = 1 撃（最初の一撃と鎖の終わりの一撃）、hits = 2。継続ダメージは extras
            n.damage = Self.magicDamage(T.s1Base, ratio: T.s1PowerRatio, slot: .skill1, scale: T.s1Scale, rank: rank,
                                        stats: stats)
            n.hits = 2
            n.cooldown = Self.cooldown(T.s1Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .none
            n.ccDuration = 0
            n.extras = [KitStat(key: "chainDuration", value: T.chainDuration),
                        KitStat(key: "chainSpeed", value: T.chainSpeed * 100),
                        KitStat(key: "refund", value: T.chainRefundRatio * 100),
                        KitStat(key: "dot", value: Self.dotDamage(rank: rank, stats: stats).rounded()),
                        KitStat(key: "lockout", value: T.chainLockout),
                        KitStat(key: "base", value: Self.scaledBase(T.s1Base, slot: .skill1, scale: T.s1Scale, rank: rank)
                            .rounded()),
                        KitStat(key: "mpPct", value: Self.powerPercent(T.s1PowerRatio, slot: .skill1, scale: T.s1Scale)
                            .rounded()),
                        KitStat(key: "dotBase", value: Self.scaledBase(T.dotBase, slot: .skill1, scale: T.s1Scale, rank: rank)
                            .rounded()),
                        KitStat(key: "dotPct", value: Self.powerPercent(T.dotPowerRatio, slot: .skill1, scale: T.s1Scale)
                            .rounded())]
        case .skill2:
            n.damage = Self.magicDamage(T.s2Base, ratio: T.s2PowerRatio, slot: .skill2, scale: T.s2Scale, rank: rank,
                                        stats: stats)
            n.hits = 1
            n.cooldown = Self.cooldown(T.s2Cooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .stun
            n.ccIsUltimate = false
            n.ccDuration = T.s2Stun
            n.extras = [KitStat(key: "shred", value: Self.shredAmount(rank: rank, maxRank: slot.maxRank)),
                        KitStat(key: "shredDuration", value: T.shredDuration),
                        KitStat(key: "splashRadius", value: T.splashRadius),
                        KitStat(key: "stun", value: T.s2Stun),
                        KitStat(key: "base", value: Self.scaledBase(T.s2Base, slot: .skill2, scale: T.s2Scale, rank: rank)
                            .rounded()),
                        KitStat(key: "mpPct", value: Self.powerPercent(T.s2PowerRatio, slot: .skill2, scale: T.s2Scale)
                            .rounded())]
        case .ultimate:
            n.damage = Self.magicDamage(T.ultCenterBase, ratio: T.ultCenterPowerRatio, slot: .ultimate, scale: T.ultScale,
                                        rank: rank, stats: stats)
            n.hits = 1
            n.cooldown = Self.cooldown(T.ultCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .none
            n.ccIsUltimate = false
            n.ccDuration = 0
            n.delay = T.ultDelay
            func base(_ t: (Double, Double)) -> Double {
                Self.scaledBase(t, slot: .ultimate, scale: T.ultScale, rank: rank).rounded()
            }
            func pct(_ r: Double) -> Double { Self.powerPercent(r, slot: .ultimate, scale: T.ultScale).rounded() }
            n.extras = [KitStat(key: "outer", value: Self.outerDamage(rank: rank, stats: stats).rounded()),
                        KitStat(key: "burst", value: Self.burstDamage(rank: rank, stats: stats).rounded()),
                        KitStat(key: "delay", value: T.ultDelay),
                        KitStat(key: "centerRadius", value: T.ultCenterRadius),
                        KitStat(key: "base", value: base(T.ultCenterBase)),
                        KitStat(key: "mpPct", value: pct(T.ultCenterPowerRatio)),
                        KitStat(key: "outerBase", value: base(T.ultOuterBase)),
                        KitStat(key: "outerPct", value: pct(T.ultOuterPowerRatio)),
                        KitStat(key: "burstBase", value: base(T.burstBase)),
                        KitStat(key: "burstPct", value: pct(T.burstPowerRatio))]
        }
        return n
    }

    /// ランクごとのマナ消費（公式 = 日本語クライアント: スキル1 = 40 → 65、スキル2 = 80 → 105、アルティメット = 130 / 160 / 190）。
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

    /// 説明文は公式（日本語クライアント。2026-10-10 受領の画面）の文の構造に合わせる。数値は {トークン} で sim から入れる
    /// （{base}(+{mpPct}%魔法攻撃) は sim の式に換算した値）。名前は master のもの（超電導状態 = 超伝導、フォークライトニング = 分岐雷、
    /// エレキアロー = 雷球、サンダーストローク = 九天雷鳴、サンダーバースト = 雷の炸裂）。
    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "スキルがミニオン以外のユニットに命中すると、{markDuration}秒間「超伝導」を付与する。超伝導の影響を受けている敵に対しては追加効果が発動する"
                    + "（スキル1 分岐雷は雷の鎖、スキル2 雷球は周囲への広がりとスタン、アルティメット 九天雷鳴は雷の炸裂）。\n\n"
                    + "超伝導そのものはダメージを増やさず、追加効果で消費されない。",
                en: "Skills inflict Superconductor for {markDuration}s on non-minion units hit, and trigger additional "
                    + "effects against enemies affected by Superconductor (Skill 1 Forked Bolt: a lightning chain, Skill 2 "
                    + "Thunder Orb: spreads and stuns nearby enemies, Ultimate Nine Heavens Thunder: a Thunderburst)."
                    + "\n\nSuperconductor itself adds no damage and is not consumed by those effects.",
                tags: [KitTag.buff])
        case .skill1:
            return KitText(
                ja: "扇状の範囲に分岐雷を放ち、{base}(+{mpPct}%魔法攻撃)の魔法ダメージを与える（ミニオンには200%）。\n\n"
                    + "超伝導の対象に命中すると、対象との間に雷の鎖を形成し（同じ対象には{lockout}秒に1回まで）、鎖が存在する間、"
                    + "移動速度が{chainSpeed}%上昇する（最大{chainDuration}秒）。\n\n雷の鎖は継続的に{dotBase}(+{dotPct}%魔法攻撃)の魔法ダメージを与え、"
                    + "終了時に追加で{base}(+{mpPct}%魔法攻撃)の魔法ダメージを与える。この追加ダメージが命中した場合、このスキルのクールダウンを{refund}%短縮する。",
                en: "Casts Forked Bolt in a fan-shaped area, dealing {base} (+{mpPct}% Magic Power) magic damage to enemies "
                    + "within (200% against minions).\n\nWhen it hits a target affected by Superconductor, Euria forms a "
                    + "lightning chain with the target (once per {lockout}s on the same target), gaining {chainSpeed}% movement "
                    + "speed during the chain for up to {chainDuration}s.\n\nThe chain deals {dotBase} (+{dotPct}% Magic Power) "
                    + "magic damage over time and an additional {base} (+{mpPct}% Magic Power) when it ends. If this hit lands, "
                    + "it reduces the skill's cooldown by {refund}%.",
                tags: [KitTag.aoe])
        case .skill2:
            return KitText(
                ja: "対象の敵に雷球を放ち、{shredDuration}秒間魔法防御を{shred}低下させ、{base}(+{mpPct}%魔法攻撃)の魔法ダメージを与え、"
                    + "{stun}秒間スタンさせる。\n\n対象が超伝導の場合、雷球は周囲（{splashRadius}以内）の敵の魔法防御を低下させ、"
                    + "対象を中心に範囲ダメージを与え、周囲の敵をすべてスタンさせる（ミニオンにはダメージのみ）。",
                en: "Hurls a Thunder Orb at the target enemy, reducing their magic defense by {shred} for {shredDuration}s, "
                    + "dealing {base} (+{mpPct}% Magic Power) magic damage and stunning them for {stun}s.\n\nIf the target is "
                    + "affected by Superconductor, the orb also reduces the magic defense of nearby enemies (within "
                    + "{splashRadius}), deals area damage centered on the target and stuns all nearby enemies (minions take "
                    + "damage only).",
                tags: [KitTag.disrupt, KitTag.damage])
        case .ultimate:
            return KitText(
                ja: "指定範囲に稲妻を落とし（{delay}秒後・射程{range}）、中心（半径{centerRadius}）の対象に{base}(+{mpPct}%魔法攻撃)の魔法ダメージを与える。"
                    + "その後、中心の外側（半径{radius}まで）にいる対象に雷が落ち、{outerBase}(+{outerPct}%魔法攻撃)の魔法ダメージを与える。\n\n"
                    + "九天雷鳴が超伝導の対象に命中するたび、短い遅延の後、その対象を中心とした雷の炸裂が発動し、範囲内の超伝導の対象に"
                    + "{burstBase}(+{burstPct}%魔法攻撃)の魔法ダメージを与える（複数なら重なる）。",
                en: "Calls down a lightning strike on the target area (after {delay}s, range {range}), dealing {base} "
                    + "(+{mpPct}% Magic Power) magic damage to targets at the center (radius {centerRadius}). Lightning then strikes "
                    + "targets outside the center (up to radius {radius}), dealing {outerBase} (+{outerPct}% Magic Power) magic damage."
                    + "\n\nEach time it hits a target affected by Superconductor, a Thunderburst centered on that target triggers after "
                    + "a short delay, dealing {burstBase} (+{burstPct}% Magic Power) magic damage to Superconductor targets in the area "
                    + "(bursts overlap).",
                tags: [KitTag.burst])
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard slot == .skill1, let k = hero.kit, k.euriaChainRemaining > 0 else { return nil }
        return KitBadge(kind: .timer, remaining: k.euriaChainRemaining, total: T.chainDuration)
    }

    // MARK: - B. 実行

    func resolveAim(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot, stage: Int,
                    targeting: SkillTargeting, target: SkillTarget) -> SkillAim?? {
        guard slot == .skill2 else { return nil }
        // 対象指定: 射程内の敵が居なければ拒否（コスト・CD を消費しない）
        guard let u = Self.pickTarget(s, caster: caster, reach: targeting.reach, target: target) else {
            return .some(nil)
        }
        return .some(SkillAiming.aim(at: u, s, caster: caster, range: targeting.range,
                                     facing: Vec2.fromAngle(s.units[caster].facing)))
    }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        switch c.slot {
        case .skill1: castFork(&s, ctx, c)
        case .skill2: castOrb(&s, c)
        case .ultimate: castThunder(&s, c)
        case .passive: break
        }
        return .done
    }

    /// S1: 前方の扇に即時の雷。当たった敵ごとに onHit（印の付与と鎖）。
    private func castFork(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let origin = s.units[i].pos
        let dir = c.aim.direction
        Kit.emitCast(&s, c, origin: origin, target: origin + dir * c.targeting.range, unit: c.aim.unit, shape: .fan,
                     halfAngle: T.s1HalfAngle, duration: T.chainDuration, count: 3)
        let p = HitPayload(damage: c.numbers.damage, damageType: c.check.skill.damageType, source: .skill(.skill1),
                           skillID: c.check.skill.skillID, originPos: origin, kitEvent: T.Event.fork)
        SkillArchetypes.hitArea(&s, ctx, caster: i, center: origin, radius: c.targeting.range,
                                shape: .cone(direction: dir, halfAngle: T.s1HalfAngle), payload: p)
    }

    /// S2: 対象を追う雷球。命中で onHit（印の付与と、印済みなら周囲への広がり）。
    private func castOrb(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        guard let t = c.aim.unit else { return }
        let payload = Self.orbPayload(skill: c.check.skill, numbers: c.numbers, rank: c.numbers.rank,
                                      event: T.Event.orb)
        let dist = s.units[i].pos.distance(to: s.units[t].pos)
        Kit.emitCast(&s, c, target: s.units[t].pos, unit: t, shape: .lockOn, duration: dist / T.s2Speed, count: 1)
        ProjectileSystem.spawn(&s, ownerIndex: i, motion: .homing(targetID: s.units[t].id), speed: T.s2Speed,
                               payload: payload, visual: c.check.skill.effectID)
    }

    /// 奥義: 指定地点に遅れて落ちる大雷（予告の円 = ゾーンの delay）。中心は重く、外側は半分（距離補正を段差にして使う）。
    private func castThunder(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        let center = c.aim.point
        // 外側のダメージ ÷ 中心（魔力 0 なら公式どおり 0.5。魔力の係数が違うので魔力が増えると少し下がる）
        let outer = Self.outerDamage(rank: c.numbers.rank, stats: s.units[i].stats)
        let outerMult = c.numbers.damage > 0 ? outer / c.numbers.damage : 0.5
        let p = HitPayload(damage: c.numbers.damage, damageType: c.check.skill.damageType, source: .skill(.ultimate),
                           skillID: c.check.skill.skillID,
                           scaling: .distance(near: T.ultCenterRadius, far: T.ultCenterRadius + 1, minMult: 1,
                                              maxMult: outerMult),
                           originPos: center, kitEvent: T.Event.thunder)
        Kit.emitCast(&s, c, origin: s.units[i].pos, target: center, unit: c.aim.unit, shape: .circleAtPoint,
                     duration: T.ultDelay, count: 1)
        ZoneSystem.spawn(&s, ownerIndex: i, center: center, radius: T.ultOuterRadius, delay: T.ultDelay, payload: p,
                         visual: c.check.skill.effectID)
    }

    // MARK: - 命中

    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {
        guard s.units.indices.contains(target), s.units.indices.contains(owner) else { return }
        switch event {
        case T.Event.fork:
            // 印済みの敵に当たったら鎖を結ぶ（印の付与が先ではなく、付与前の状態で判定する）
            let had = markAndReport(&s, owner: owner, target: target)
            if had, CombatSystem.isLiving(s, owner), CombatSystem.isLiving(s, target),
               !Self.chainLocked(s, owner: owner, target: target) {
                startChain(&s, ctx, owner: owner, target: target)
            }
        case T.Event.orb:
            let had = markAndReport(&s, owner: owner, target: target)
            if had, CombatSystem.isLiving(s, owner) { splash(&s, ctx, owner: owner, center: target) }
        case T.Event.thunder:
            let had = markAndReport(&s, owner: owner, target: target)
            if had, CombatSystem.isLiving(s, owner) { thunderburst(&s, ctx, owner: owner, target: target) }
        case T.Event.orbSplash, T.Event.burst:
            _ = markAndReport(&s, owner: owner, target: target)
        case T.Event.chainEnd:
            s.units[owner].hero?.kit?.euriaChainEnds += 1
        default:
            break
        }
    }

    /// 超伝導を付ける（ミニオン・構造物には付かない）。付ける前から印があれば true。
    private func markAndReport(_ s: inout SimState, owner: Int, target: Int) -> Bool {
        guard Self.canMark(s, target), CombatSystem.isLiving(s, target) else { return false }
        let tag = Self.markTag(s, owner)
        let had = Kit.markStacks(s, target: target, tag: tag) > 0
        Kit.addMark(&s, target: target, ownerID: s.units[owner].id, tag: tag, maxStacks: 1, duration: T.markDuration)
        s.units[owner].hero?.kit?.euriaMarksApplied += 1
        return had
    }

    // MARK: S1: 雷の鎖

    /// 鎖を結ぶ: 移動速度 +40%（鎖の間）、継続ダメージ 4 回、終わりに追加ダメージ（当たるとクールダウン短縮）。
    private func startChain(_ s: inout SimState, _ ctx: SimContext, owner i: Int, target t: Int) {
        guard let (_, n) = Self.numbersNow(s, ctx, i, .skill1) else { return }
        let tid = s.units[t].id
        // 同じ対象の鎖は張り直し
        s.units[i].hero?.kit?.scheduled.removeAll { $0.targetID == tid && ($0.code == T.Code.dot || $0.code == T.Code.end) }
        let dot = Self.dotDamage(rank: n.rank, stats: s.units[i].stats)
        for k in 1...T.dotCount {
            Kit.schedule(&s, caster: i, slot: .skill1, code: T.Code.dot, after: T.dotInterval * Double(k), targetID: tid,
                         index: k, param: dot, interruptible: true)
        }
        Kit.schedule(&s, caster: i, slot: .skill1, code: T.Code.end, after: T.chainDuration, targetID: tid, param: n.damage,
                     interruptible: true)
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .speedBoost, duration: T.chainDuration,
                                                                magnitude: T.chainSpeed, sourceID: s.units[i].id,
                                                                tag: T.chainSpeedTag))
        s.units[i].hero?.kit?.euriaChainRemaining = T.chainDuration
        s.units[i].hero?.kit?.euriaChains += 1
        s.units[i].hero?.kit?.setEuriaChainLockout(for: tid, seconds: T.chainLockout)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        if timer.code == T.Code.burst {
            fireThunderburst(&s, ctx, owner: owner, timer: timer)
            return
        }
        guard timer.code == T.Code.dot || timer.code == T.Code.end else { return }
        let isEnd = timer.code == T.Code.end
        // 対象が倒れた・見えなくなった・離れすぎた: 鎖は切れる（終わりの一撃は当たらず、クールダウンも縮まない）
        guard let t = s.index(of: timer.targetID), CombatSystem.isLiving(s, t),
              s.isTargetableEnemy(t, of: s.units[owner].team),
              s.units[owner].pos.distance(to: s.units[t].pos) <= T.chainLeash else {
            breakChain(&s, owner: owner, targetID: timer.targetID)
            return
        }
        guard let (skill, n) = Self.numbersNow(s, ctx, owner, .skill1) else { return }
        var p = HitPayload(damage: timer.param, damageType: skill.damageType, source: .skill(.skill1),
                           skillID: skill.skillID, originPos: s.units[owner].pos)
        if isEnd {
            // 当たると S1 のクールダウン（CD 短縮込み）の 50% ぶん縮む
            p.kitEvent = T.Event.chainEnd
            p.effects = [.refundCooldown(slot: .skill1, seconds: Self.chainRefund(cooldown: n.cooldown))]
        }
        CombatSystem.applyHit(&s, ctx, sourceID: s.units[owner].id, team: s.units[owner].team, targetIndex: t,
                              payload: p, from: s.units[owner].pos)
        if isEnd { finishChainIfIdle(&s, owner: owner) }
    }

    /// 対象の鎖を外す（予約を捨てる）。ほかの鎖が残っていなければ加速も外す。
    private func breakChain(_ s: inout SimState, owner: Int, targetID: EntityID) {
        s.units[owner].hero?.kit?.scheduled.removeAll {
            $0.targetID == targetID && ($0.code == T.Code.dot || $0.code == T.Code.end)
        }
        finishChainIfIdle(&s, owner: owner)
    }

    private func finishChainIfIdle(_ s: inout SimState, owner: Int) {
        let active = s.units[owner].hero?.kit?.scheduled.contains { $0.code == T.Code.dot || $0.code == T.Code.end } ?? false
        guard !active else { return }
        s.units[owner].statuses.removeAll { $0.kind == .speedBoost && $0.tag == T.chainSpeedTag }
        s.units[owner].hero?.kit?.euriaChainRemaining = 0
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // ハード CC: 鎖の予約は取り消された。加速も終わる
        s.units[owner].statuses.removeAll { $0.kind == .speedBoost && $0.tag == T.chainSpeedTag }
        s.units[owner].hero?.kit?.euriaChainRemaining = 0
    }

    // MARK: S2: 周囲への広がり

    /// 印済みの敵に雷球が当たった: その周囲の敵（当たった敵を除く）にも同じダメージ・スタン・魔防ダウン。
    private func splash(_ s: inout SimState, _ ctx: SimContext, owner i: Int, center t: Int) {
        guard let (skill, n) = Self.numbersNow(s, ctx, i, .skill2) else { return }
        let team = s.units[i].team
        let c = s.units[t].pos
        var targets: [Int] = []
        for j in s.units.indices where j != t && s.units[j].team != team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j) else { continue }
            let reach = T.splashRadius + s.units[j].radius
            if s.units[j].pos.distanceSquared(to: c) <= reach * reach { targets.append(j) }
        }
        s.units[i].hero?.kit?.euriaSplashes += 1
        // ミニオンにはダメージだけ（スタン・魔防ダウンは広がらない。主対象と周囲のヒーロー・モンスターには広がる）
        let p = Self.orbPayload(skill: skill, numbers: n, rank: n.rank, event: T.Event.orbSplash)
        var damageOnly = p
        damageOnly.statuses = []
        for j in targets {
            CombatSystem.applyHit(&s, ctx, sourceID: s.units[i].id, team: team, targetIndex: j,
                                  payload: s.units[j].kind == .minion ? damageOnly : p, from: c)
        }
    }

    // MARK: 奥義: 雷の炸裂

    /// 印済みの敵に大雷が当たった: その敵を中心に少し遅れて雷が炸裂する（対象が倒れれば不発）。
    /// 公式（日本語クライアント）「サンダーバーストが発動し、超電導の対象に〜の魔法ダメージ」= 炸裂の範囲にいる**超伝導の敵にだけ**当たる
    /// （以前は範囲の全ての敵）。ダメージは予約（非中断。術者が倒れると消える）で出し、ゾーンは見た目だけ（敵に当たらない）。
    private func thunderburst(_ s: inout SimState, _ ctx: SimContext, owner i: Int, target t: Int) {
        guard CombatSystem.isLiving(s, t), let (_, n) = Self.numbersNow(s, ctx, i, .ultimate) else { return }
        let visual = HitPayload(damage: 0, damageType: .magic, source: .skill(.ultimate), affectsEnemies: false)
        s.units[i].hero?.kit?.euriaBursts += 1
        ZoneSystem.spawn(&s, ownerIndex: i, center: s.units[t].pos, radius: T.burstRadius, delay: T.burstDelay,
                         followsTargetID: s.units[t].id, payload: visual, visual: Self.burstVisual(ctx))
        Kit.schedule(&s, caster: i, slot: .ultimate, code: T.Code.burst, after: T.burstDelay, targetID: s.units[t].id,
                     param: Self.burstDamage(rank: n.rank, stats: s.units[i].stats), interruptible: false)
    }

    /// サンダーバーストの発動: 対象（倒れていれば不発）を中心に、半径内の超伝導（この術者の印）の敵へダメージ。添字の昇順。
    private func fireThunderburst(_ s: inout SimState, _ ctx: SimContext, owner i: Int, timer: KitTimer) {
        guard let t = s.index(of: timer.targetID), CombatSystem.isLiving(s, t),
              let skill = ctx.master.skill(hero: heroID, slot: .ultimate) else { return }
        let center = s.units[t].pos
        let team = s.units[i].team
        let tag = Self.markTag(s, i)
        var hits: [Int] = []
        for j in s.units.indices where s.units[j].team != team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j), Kit.markStacks(s, target: j, tag: tag) > 0 else { continue }
            let reach = T.burstRadius + s.units[j].radius
            if s.units[j].pos.distanceSquared(to: center) <= reach * reach { hits.append(j) }
        }
        let p = HitPayload(damage: timer.param, damageType: skill.damageType, source: .skill(.ultimate),
                           skillID: skill.skillID, originPos: center, kitEvent: T.Event.burst)
        for j in hits {
            CombatSystem.applyHit(&s, ctx, sourceID: s.units[i].id, team: team, targetIndex: j, payload: p, from: center)
        }
    }

    // MARK: - C. パッシブ

    func outgoingDamageBonus(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                             source: DamageSource) -> Double {
        // S1 はミニオンに 200%
        guard source == .skill(.skill1), s.units[target].kind == .minion else { return 0 }
        return 1
    }

    // MARK: - D. ボット

    /// 印を付けてから重い技を使う: 印の無い敵には、スキル1（雷の鎖）が実際に撃てるあいだは S1 → (S2 / アルティメット) の順にする。
    /// 「撃てる」= クールダウンが明け、マナがあり、沈黙などでなく、敵が S1 の射程（扇）に入っていること
    /// （撃てないのに待ち続けて、アルティメットや S2 が永久に出なくならないように）。
    /// S2 は印が広がるので、近くに別のヒーローが居るときは印を付けてから。居なければ先に撃ってよい（S2 自身が印を付ける）。
    /// S1 は、近くに別のヒーローが居ない印の無い敵に S2 が撃てるなら待つ（S2 = 印 + スタン → S1 = 鎖 の順）。S1 のクールダウン
    /// （日本語クライアントの 5 秒）が印（5 秒）と同じで、S1 → 印 → S1 の順ではほとんど鎖が繋がらない（印が切れる tick と重なる）ため。
    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        guard fighting, s.units.indices.contains(target), Self.canMark(s, target) else { return .useDefault }
        let marked = Kit.markStacks(s, target: target, tag: Self.markTag(s, bot)) > 0
        if slot == .skill1 {
            guard !marked else { return .useDefault }
            // 雷球が飛んでいる間は着弾（印）を待つ
            let me = s.units[bot].id
            if s.projectiles.contains(where: { $0.ownerID == me && $0.payload.kitEvent == T.Event.orb }) { return .skip }
            guard Self.orbReady(s, ctx, bot: bot, target: target),
                  Self.heroesNear(s, bot: bot, target: target) == 0 else { return .useDefault }
            return .skip
        }
        guard !marked, Self.fork1Ready(s, ctx, bot: bot, target: target) else { return .useDefault }
        switch slot {
        case .ultimate:
            return .skip
        case .skill2:
            // 周囲に別のヒーローが居るときだけ待つ（印済みなら広がるので）
            return Self.heroesNear(s, bot: bot, target: target) >= 1 ? .skip : .useDefault
        default:
            return .useDefault
        }
    }

    /// 対象の周り（S2 の広がりの半径）に居る、対象以外の敵ヒーローの数。
    static func heroesNear(_ s: SimState, bot: Int, target: Int) -> Int {
        var near = 0
        for j in s.units.indices where j != target && s.units[j].team != s.units[bot].team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j), s.units[j].kind == .hero else { continue }
            let reach = T.splashRadius + s.units[j].radius
            if s.units[j].pos.distanceSquared(to: s.units[target].pos) <= reach * reach { near += 1 }
        }
        return near
    }

    /// スキル2 が今この敵に撃てるか（クールダウン・マナ・行動可能・射程）。
    static func orbReady(_ s: SimState, _ ctx: SimContext, bot: Int, target: Int) -> Bool {
        guard SkillSystem.canCast(s, ctx, heroIndex: bot, slot: .skill2),
              let skill = ctx.master.skill(hero: "H026", slot: .skill2) else { return false }
        let reach = skill.range + s.units[target].radius
        return s.units[bot].pos.distanceSquared(to: s.units[target].pos) <= reach * reach
    }

    /// スキル1 が今この敵に撃てるか（クールダウン・マナ・行動可能・射程）。
    static func fork1Ready(_ s: SimState, _ ctx: SimContext, bot: Int, target: Int) -> Bool {
        guard SkillSystem.canCast(s, ctx, heroIndex: bot, slot: .skill1),
              let skill = ctx.master.skill(hero: "H026", slot: .skill1), let h = s.units[bot].hero,
              let def = ctx.master.hero("H026"),
              s.units[bot].resource + 1e-6 >= SkillSystem.cost(for: skill, hero: def, rank: max(1, h.rank(.skill1)),
                                                               resource: h.resourceKind) else { return false }
        let reach = skill.range + s.units[target].radius
        return s.units[bot].pos.distanceSquared(to: s.units[target].pos) <= reach * reach
    }

    // MARK: - 部品

    /// 同じ相手への鎖がまだ結び直せないか（前の鎖から chainLockout 秒以内）。
    static func chainLocked(_ s: SimState, owner: Int, target: Int) -> Bool {
        guard let k = s.units[owner].hero?.kit else { return false }
        return k.euriaChainLockout(for: s.units[target].id) > 0
    }

    /// 超伝導を付けられる相手（ミニオン・構造物には付かない）。
    static func canMark(_ s: SimState, _ t: Int) -> Bool {
        guard s.units.indices.contains(t), !s.units[t].isStructure else { return false }
        switch s.units[t].kind {
        case .hero, .monster, .dummy: return true
        default: return false
        }
    }

    static func markTag(_ s: SimState, _ owner: Int) -> String {
        KitTags.mark("H026", T.markName, owner: s.units[owner].id)
    }

    /// 雷球（主対象・広がりの共通）。スタン + 魔防ダウン（固定値）。
    static func orbPayload(skill: SkillDef, numbers n: SkillNumbers, rank: Int, event: Int) -> HitPayload {
        let stun = StatusEffect(kind: .stun, duration: T.s2Stun, tag: CombatSystem.tagStun)
        let shred = StatusEffect(kind: .magicShred, duration: T.shredDuration,
                                 magnitude: shredAmount(rank: rank, maxRank: SkillSlot.skill2.maxRank), tag: T.shredTag)
        return HitPayload(damage: n.damage, damageType: skill.damageType, source: .skill(.skill2), statuses: [stun, shred],
                          skillID: skill.skillID, kitEvent: event)
    }

    /// 魔防ダウン量（固定値 10 → 25 をランクで線形に）。
    static func shredAmount(rank: Int, maxRank: Int) -> Double {
        lerp(T.shredRange.0, T.shredRange.1, rank: rank, maxRank: maxRank)
    }

    /// 雷の炸裂のゾーンに使う演出 ID（パッシブの演出枠。大雷とは別の演出にするため）。
    static func burstVisual(_ ctx: SimContext) -> String {
        ctx.master.skill(hero: "H026", slot: .passive)?.effectID ?? ""
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

    /// (公式の基礎 + 係数 × 魔力) × スロット倍率 × 換算。基礎は Lv1 → 最終 Lv をランクで線形補間（物理攻撃の係数は持たない）。
    static func magicDamage(_ base: (Double, Double), ratio: Double, slot: SkillSlot, scale: Double, rank: Int,
                            stats: Stats) -> Double {
        let b = lerp(base.0, base.1, rank: rank, maxRank: slot.maxRank)
        return (b + ratio * stats.abilityPower) * Balance.Skills.damageScale(slot) * scale
    }

    /// 公式の基礎ダメージ（ランクで補間）を sim の式に通した「換算後の基礎」。
    static func scaledBase(_ table: (Double, Double), slot: SkillSlot, scale: Double, rank: Int) -> Double {
        lerp(table.0, table.1, rank: rank, maxRank: slot.maxRank) * Balance.Skills.damageScale(slot) * scale
    }

    /// 公式の「+N% 魔法攻撃」を sim の式（× スロット倍率 × 換算）に通した、魔力に対する割合（%）。
    static func powerPercent(_ ratio: Double, slot: SkillSlot, scale: Double) -> Double {
        ratio * Balance.Skills.damageScale(slot) * scale * 100
    }

    /// 雷の鎖の継続ダメージ 1 回（公式 10 → 20 + 4% 魔法攻撃）。
    static func dotDamage(rank: Int, stats: Stats) -> Double {
        magicDamage(T.dotBase, ratio: T.dotPowerRatio, slot: .skill1, scale: T.s1Scale, rank: rank, stats: stats)
    }

    /// 終わりの一撃が当たったときに縮める秒数（S1 のクールダウンの 50%）。
    static func chainRefund(cooldown: Double) -> Double { max(0, cooldown) * T.chainRefundRatio }

    /// 奥義の外側（中心の外）のダメージ（公式 300 / 400 / 500 + 100% 魔法攻撃）。
    static func outerDamage(rank: Int, stats: Stats) -> Double {
        magicDamage(T.ultOuterBase, ratio: T.ultOuterPowerRatio, slot: .ultimate, scale: T.ultScale, rank: rank, stats: stats)
    }

    /// 雷の炸裂（サンダーバースト）のダメージ（公式 330 / 440 / 550 + 110% 魔法攻撃）。
    static func burstDamage(rank: Int, stats: Stats) -> Double {
        magicDamage(T.burstBase, ratio: T.burstPowerRatio, slot: .ultimate, scale: T.ultScale, rank: rank, stats: stats)
    }

    static func lerp(_ a: Double, _ b: Double, rank: Int, maxRank: Int) -> Double {
        guard maxRank > 1 else { return a }
        let t = Double(min(max(1, rank), maxRank) - 1) / Double(maxRank - 1)
        return a + (b - a) * t
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
