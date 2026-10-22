import Foundation

// 担当: kit-H025（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Miya.md）
// H025 月弦のルミナ = MLBB ミヤの Velstria 版（レンジャー・遠隔 480（MLBB の 4.8）・マナ）。調査: docs/kits/Miya.md、対応表: 同ファイル末尾。
// 数値の正は MLBB の日本語クライアントのスキル詳細（docs/kits/Miya.md の「公式（日本語クライアント）の数値」。Fandom と違うところはこちらが優先）。
//   パッシブ 月環の導き  — 通常攻撃が命中するたびに攻撃速度 +5%（4 秒・最大 5 段）。最大のあいだは主矢が命中するたびに「月影」が現れ、
//                          術者の位置から対象へ自分の矢を放って 25(+20% 物理攻撃) の物理ダメージ（攻撃エフェクト 20%）。
//                          ロールの「4 発毎の確定会心」は置き換え。
//   スキル1 月弦分矢     — 自己強化 4 / 5 / 6 / 7 / 8 / 9 秒。通常攻撃が主矢 + 副矢 2 本になる（主矢 = 通常攻撃 + 基礎 10〜35、
//                          周囲の敵 2 体へ主矢の 30%。副矢は攻撃エフェクト 30%）。効果中は再使用できない（CD 11 秒）。
//   スキル2 月蝕の矢     — 指定地点（射程 545・離してから 0.65 秒で着弾）。半径内の敵に 270〜420(+45%) の物理ダメージと 1.2 秒のバインド。
//                          着弾の 0.33 秒後に着弾点から 6 本の小さな矢が 60° おき（1 本は撃った向き）に散り、それぞれ最初に当たった敵に
//                          40〜105(+20%) の物理ダメージと 2 秒の 30% スロウ。
// 幾何と時間（射程・半径・遅れ・矢の向き / 速さ / 距離・月影の時刻）は MLBB の訓練場の画面収録で測った値（docs/kits/Miya.md「動画で測った値」）。
//   アルティメット 隠れ月光 — 弱体をすべて解除して姿を隠し、2 秒間 移動速度 +65%。通常攻撃かスキルの発動（奥義を除く）で解ける。
//                          解けた（時間切れ含む）瞬間に月環の導きが最大の段になる。ボットは低 HP で敵が近いとき、逃走・解除に使う。
// 数値: 公式の表をそのまま使う（スキル1・2 = Lv1〜6、アルティメット = Lv1〜3。rank = 公式の Lv。換算・補間なし）。
//   ダメージ = 公式の基礎[段] + 公式の係数 × 合計の物理攻撃（Kit.official）。コスト（マナ）・クールダウン・S1 の持続も表を引く（Kit.level）。
// 再使用の窓は Miya に無いので使わない。
//
// 状態（KitState）:
//   ints[0] = 月環の導きの段（0..5）        ints[1] = 隠れ月光の最中か（0/1）
//   ints[2] = 月影の発動回数（検証用）       ints[3] = 副矢を放った本数（検証用）
//   timers[0] = 段の残り秒（4）  timers[1] = 月矢の連弾の残り秒  timers[2] = 隠れ月光の残り秒
//   reals[0] = 月矢の連弾の主矢の追加ダメージ（発動時のランク・能力値で固定）

/// ルミナの値。数値は MLBB の日本語クライアントのスキル詳細の表そのまま（docs/kits/Miya.md の「公式（日本語クライアント）の数値」）。
/// 距離・遅延・散り方など公式の文に無い値は MLBB の画面収録で測った値（同 docs の「動画で測った値（2026-10-16）」。
/// 距離は MLBB × 100）。測れなかったものは Velstria の推測（同 docs の「まだ MLBB と違うところ」）。
enum LuminaTuning {
    // MARK: 通常攻撃
    /// 通常攻撃の矢の速さ（動画で測った値: 毎秒 16.5 単位 ± 1。主矢・副矢・月影の矢で同じ。印 0 / 5 で変わらない）。
    /// 汎用の Balance.heroProjectileSpeed（1500）の代わり。
    static let arrowSpeed: Double = 1650

    // MARK: パッシブ（月環の導き = スイフト）
    static let maxStacks = 5
    /// 1 段あたりの攻撃速度（公式 5%、最大 +25%）。
    static let attackSpeedPerStack: Double = 0.05
    /// 段の持続（公式 4 秒。動画: 最後の主矢の命中からちょうど 4.0 秒で印が消える）。
    static let stackDuration: Double = 4
    /// 月影（ムーンライトシャドウ）: 公式 25(+20% 物理攻撃)（Fandom の 30(+25%) は古い値）。
    static let shadowFlat: Double = 25
    static let shadowRatio: Double = 0.20
    /// 月影は攻撃効果の 20% を引き継ぐ（公式）。HitPayload.attackEffect（装備の命中時効果・通常攻撃吸収をこの割合で）。
    static let shadowAttackEffect: Double = 0.20

    // MARK: S1（月弦分矢 = スプリットショット）
    /// 持続（公式: Lv1〜6 = 4 / 5 / 6 / 7 / 8 / 9 秒）。
    static let s1Duration: [Double] = [4, 5, 6, 7, 8, 9]
    /// 主矢の追加ダメージの基礎（公式: 10 / 15 / 20 / 25 / 30 / 35。+100% 物理攻撃は通常攻撃そのもの）。
    static let s1Base: [Double] = [10, 15, 20, 25, 30, 35]
    /// その他の対象へのダメージ（公式 30%）。
    static let splashRatio: Double = 0.30
    /// 各矢は攻撃効果の 30% を引き継ぐ（公式）。副矢の HitPayload.attackEffect。
    static let splashAttackEffect: Double = 0.30
    static let splashCount = 2
    /// 副矢が飛ぶ「その他の対象」の範囲（主矢の対象から。公式の文に無い Velstria の推測。動画では主矢の対象から 1.85 と 2.7〜2.8 の
    /// 的に飛んで当たった = この範囲の内側。上限は測れていない）。
    static let splashRadius: Double = 300
    /// 副矢が飛ぶ範囲の余裕（術者の射程 + 対象の半径 + この値。動画では術者から 5.0〜5.5 = 射程 4.8 の外の的にも当たった）。
    static let splashLeeway: Double = 150
    /// 自己強化の照準リングの半径 = 通常攻撃の射程（MLBB の 4.8 = 480。2026-10-14 に 550 から）。「この範囲に敵が居れば撃つ」を
    /// HUD の輪で示す。ボットの奥義の関門（周囲の敵を数える半径 = 輪 × 1.4 = 672）もこれに従う。
    static let selfRing: Double = 480
    /// 「撃てる距離」の目安（`reachOverride`。敵がこの内側に居るときだけ撃つ）。
    static let s1Reach: Double = 600
    /// 公式の CD 11 秒（全 Lv 一定）。
    static let s1Cooldown: [Double] = [11]
    /// 公式（日本語クライアント）のマナ 60 / 65 / 70 / 75 / 80 / 85（Fandom の 50 → 75 は古い値）。
    static let s1Cost: [Double] = [60, 65, 70, 75, 80, 85]

    // MARK: S2（月蝕の矢 = レインアロー）
    /// 射程（動画で測った値: 最大の照準の円 5.43、照準を端まで引いたときの円の中心 5.47 → 545。以前はマスターの 650）。
    static let s2Range: Double = 545
    /// 半径（パッチ履歴 1.1.22 の 1.7。動画の照準の円 1.71 と合う）。
    static let s2Radius: Double = 170
    /// 指を離してから着弾（ダメージ・バインド）まで（動画で測った値: 0.65 / 0.68 秒。距離 5.47 / 4.26 で同じ = 距離によらない。
    /// 弓を天へ向ける 0.27 秒（CD の表示はここから）+ 矢が落ちる 0.40 秒。以前の推測は 0.35）。
    static let s2Delay: Double = 0.65
    /// 着弾から 6 本の小さな矢が散るまで（動画で測った値: 2 回とも 10 コマ = 0.33 秒。以前は着弾と同時）。
    static let s2SplitDelay: Double = 0.33
    /// バインド（公式 1.2 秒）。敵に付ける root = バインド（移動・ブリンク・アサルトスキル・瞬歩を封じる。スキルは中断しない）。
    static let s2Root: Double = 1.2
    static let s2Slow: Double = 0.30
    static let s2SlowDuration: Double = 2
    static let s2Arrows = 6
    /// 6 本を 60° おきに散らす。動画で測った値: 撃った向き（術者 → 着弾点）を 0° として 0° / ±60° / ±120° / 180°
    /// （4 本の軌跡が予想の向きと 1.3° 以内）。Kit.fan の ±150° の扇を 30° 回して、1 本を撃った向きに揃える
    /// （以前の推測は ±30° / ±90° / ±150°）。
    static let s2ScatterHalfAngle: Double = Double.pi * 5 / 6
    static let s2ScatterTurn: Double = Double.pi / 6
    /// 小さな矢の速さ・射程（動画で測った値: 着弾点から毎秒 12.5 ± 0.4 単位、4.0 ± 0.1 で消える。以前の推測は 1800 / 420）。
    static let s2ArrowSpeed: Double = 1250
    static let s2ArrowRange: Double = 400
    /// 小さな矢の幅（公式の文に無い。動画では測れなかった推測。docs の「まだ MLBB と違うところ」）。
    static let s2ArrowWidth: Double = 35
    /// 着弾: 公式 270 / 300 / 330 / 360 / 390 / 420（+45% 物理攻撃 = 合計の物理攻撃）。
    static let s2Base: [Double] = [270, 300, 330, 360, 390, 420]
    static let s2AttackRatio: Double = 0.45
    /// 小さな矢 1 本: 公式 40 / 53 / 66 / 79 / 92 / 105（+20% 物理攻撃 = 合計の物理攻撃）。
    static let s2MinorBase: [Double] = [40, 53, 66, 79, 92, 105]
    static let s2MinorAttackRatio: Double = 0.20
    /// 公式の CD 8 秒（全 Lv 一定）。
    static let s2Cooldown: [Double] = [8]
    /// 公式（日本語クライアントの画面 2026-10-11）のマナ 90（全 Lv 一定）。「MP消費量：90」は画面の吹き出しの半透明の裏から読んだ
    /// （表に MP の行が無い = 全 Lv 同じ）。以前は Fandom の 80 / 90 / 100 / 110 / 120 / 130。
    static let s2Cost: [Double] = [90]

    // MARK: 奥義（隠れ月光 = 隠月）
    /// 隠密と加速の長さ（公式「最大 2 秒」。動画: 発動から 1.98 秒で印が最大になり、同じコマで歩く速さが戻る）。
    static let ultDuration: Double = 2
    /// 加速（公式 65%。動画: 隠れている間の歩きは普段の 1.66 倍）。
    static let ultSpeed: Double = 0.65
    /// 「撃てる距離」の目安（奥義の距離 770。`reachOverride`）。
    static let ultReach: Double = 770
    /// 公式の CD 30 / 25 / 20 秒。
    static let ultCooldown: [Double] = [30, 25, 20]
    /// 公式のマナ 120 / 145 / 170。
    static let ultCost: [Double] = [120, 145, 170]
    /// ボットが隠れ月光で離脱する HP の割合（通常 / 減速・バインドを受けているとき）。
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
            // 指定地点の円（着弾まで遅延）。射程は動画で測った値（マスターの skill.range 650 の代わり）
            return SkillTargeting(archetype: .groundAoE, aim: .point, range: T.s2Range, radius: T.s2Radius,
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
                        KitStat(key: "shadowEffect", value: T.shadowAttackEffect * 100),
                        KitStat(key: "maxSpeed", value: T.attackSpeedPerStack * Double(T.maxStacks) * 100)]
        case .skill1:
            // damage = 主矢 1 本あたりの追加ダメージ（通常攻撃に足す）。hits = 効果時間に基礎の攻撃速度で撃つ本数の目安
            let duration = Self.s1Duration(rank: rank)
            n.hits = max(1, Int((duration * max(0.1, stats.attackSpeed)).rounded()))
            n.damage = Self.arrowBonus(rank: rank)
            n.cooldown = Kit.cooldown(T.s1Cooldown, rank: rank, stats: stats)
            n.cc = .none
            n.ccDuration = 0
            n.extras = [KitStat(key: "duration", value: duration),
                        KitStat(key: "splashPercent", value: T.splashRatio * 100),
                        KitStat(key: "splashEffect", value: T.splashAttackEffect * 100),
                        KitStat(key: "splashCount", value: Double(T.splashCount)),
                        KitStat(key: "splashRadius", value: T.splashRadius),
                        KitStat(key: "base", value: n.damage)]
        case .skill2:
            n.damage = Self.eclipseDamage(rank: rank, stats: stats)
            n.hits = 1
            n.delay = T.s2Delay
            n.cooldown = Kit.cooldown(T.s2Cooldown, rank: rank, stats: stats)
            n.cc = .root
            n.ccDuration = T.s2Root
            // 説明に出す値は公式の基礎と係数そのまま（実際の小さな矢のダメージは minorDamage(rank:stats:) が持つ）
            n.extras = [KitStat(key: "minorDamage", value: Self.minorDamage(rank: rank, stats: stats).rounded()),
                        KitStat(key: "root", value: T.s2Root),
                        KitStat(key: "slowPercent", value: T.s2Slow * 100),
                        KitStat(key: "slowDuration", value: T.s2SlowDuration),
                        KitStat(key: "base", value: Kit.level(T.s2Base, rank: rank)),
                        KitStat(key: "atkPct", value: T.s2AttackRatio * 100),
                        KitStat(key: "minorBase", value: Kit.level(T.s2MinorBase, rank: rank)),
                        KitStat(key: "minorPct", value: T.s2MinorAttackRatio * 100)]
        case .ultimate:
            n.damage = 0
            n.hits = 1
            n.cc = .none
            n.ccIsUltimate = false
            n.ccDuration = 0
            n.cooldown = Kit.cooldown(T.ultCooldown, rank: rank, stats: stats)
            n.extras = [KitStat(key: "duration", value: T.ultDuration),
                        KitStat(key: "speedPercent", value: T.ultSpeed * 100),
                        KitStat(key: "stacks", value: Double(T.maxStacks))]
        }
        return n
    }

    /// ランクごとのマナ消費（公式（日本語クライアント）: スキル1 = 60 / 65 / 70 / 75 / 80 / 85、スキル2 = 90（全 Lv 一定。
    /// 画面の吹き出しの裏から読んだ値）、アルティメット = 120 / 145 / 170）。
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double {
        let table: [Double]
        switch slot {
        case .skill1: table = T.s1Cost
        case .skill2: table = T.s2Cost
        case .ultimate: table = T.ultCost
        case .passive: return base
        }
        return HeroKits.resourceCost(Kit.level(table, rank: rank), hero: hero)
    }

    /// 説明文は公式（日本語クライアント）の文の構造に合わせる。数値は {トークン} で sim から入れる
    /// （{base}(+{atkPct}%物理攻撃) は公式の基礎と係数そのもの）。名前は master のもの（スイフト = 月環の導き、ムーンライトシャドウ = 月影）。
    /// 「攻撃効果の 20% / 30% を引き継ぐ」は公式の節（HitPayload.attackEffect で実装）。
    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "通常攻撃が対象に命中するたび、{stackDuration}秒間、攻撃速度が{attackSpeedPerStack}%上昇する（最大\(T.maxStacks)スタック・合計{maxSpeed}%）。\n\n"
                    + "最大スタック時、通常攻撃のたびに「月影」を召喚して対象を攻撃し、{shadowFlat}(+{shadowRatio}%物理攻撃)の物理ダメージを与える。"
                    + "「月影」は攻撃効果の{shadowEffect}%を引き継ぐ。",
                en: "Each time a basic attack hits a target, attack speed increases by {attackSpeedPerStack}% for {stackDuration}s "
                    + "(up to \(T.maxStacks) stacks, {maxSpeed}% in total).\n\nAt max stacks, each basic attack summons a Moonlight "
                    + "Shadow to attack the target, dealing {shadowFlat} (+{shadowRatio}% Physical Attack) physical damage. "
                    + "The Moonlight Shadow inherits {shadowEffect}% of attack effects.",
                tags: [KitTag.buff])
        case .skill1:
            return KitText(
                ja: "通常攻撃時、追加で分裂の矢を{splashCount}本放つ。各矢は攻撃効果の{splashEffect}%を引き継ぎ、"
                    + "メインターゲットに{base}(+100%物理攻撃)の物理ダメージ、"
                    + "その他の対象（メインターゲットの周囲{splashRadius}以内で近い{splashCount}体）に{splashPercent}%のダメージを与える。\n\n"
                    + "この効果は{duration}秒間持続する。クールダウンは発動した時点から数える。効果中は再使用できない。",
                en: "Basic attacks fire {splashCount} extra split arrows. Each arrow inherits {splashEffect}% of attack effects, "
                    + "dealing {base} (+100% Physical Attack) physical damage "
                    + "to the main target and {splashPercent}% damage to other targets (the {splashCount} nearest enemies within "
                    + "{splashRadius} of the main target).\n\nThis effect lasts {duration}s. The cooldown starts on cast. Cannot be "
                    + "cast again until the effect ends.",
                tags: [KitTag.buff, KitTag.aoe])
        case .skill2:
            return KitText(
                ja: "指定エリアに月蝕の力を呼び起こし（着弾まで\(Self.seconds(T.s2Delay))秒）、範囲内（半径{radius}）の敵に{base}(+{atkPct}%物理攻撃)の"
                    + "物理ダメージを与え、{root}秒間バインド状態にする（移動・ブリンク・アサルトスキルが使えない。スキルは中断されない）。\n\n"
                    + "その後（着弾の\(Self.seconds(T.s2SplitDelay))秒後）、攻撃は\(T.s2Arrows)本の矢に分裂して様々な方向へ飛んでいく（60°おきに散る）。"
                    + "各矢は最初に命中した敵に{minorBase}(+{minorPct}%物理攻撃)の"
                    + "物理ダメージを与え、命中した敵の移動速度を{slowDuration}秒間{slowPercent}%低下させる。",
                en: "Calls down the power of the eclipse on the target area (lands after \(Self.seconds(T.s2Delay))s), dealing {base} "
                    + "(+{atkPct}% Physical Attack) physical damage to enemies within (radius {radius}) and binding them "
                    + "for {root}s (they cannot move, blink or dash; their skills are not interrupted).\n\n\(Self.seconds(T.s2SplitDelay))s later, "
                    + "the attack splits into \(T.s2Arrows) scattering "
                    + "arrows flying in different directions (60° apart). Each arrow deals {minorBase} (+{minorPct}% Physical Attack) physical damage "
                    + "to the first enemy hit and reduces its movement speed by {slowPercent}% for {slowDuration}s.",
                tags: [KitTag.disrupt, KitTag.aoe])
        case .ultimate:
            return KitText(
                ja: "すべてのデバフを解除し、隠蔽状態になる。最大{duration}秒間、移動速度が{speedPercent}%上昇する"
                    + "（攻撃すると状態が早期終了する。攻撃 = 通常攻撃とアルティメット以外のスキル）。\n\n隠蔽状態が終了すると、最大スタック（{stacks}）の月環の導きを獲得する。",
                en: "Removes all debuffs and enters concealment. Movement speed increases by {speedPercent}% for up to {duration}s "
                    + "(attacking ends the state early: basic attacks and non-Ultimate skills).\n\nWhen concealment ends, gain max "
                    + "stacks ({stacks}) of Moonring Guidance.",
                tags: [KitTag.conceal, KitTag.cleanse])
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

    /// S2: 遅延（s2Delay）のあとに範囲ダメージ + バインド（ゾーン。敵に付ける root = Unit.isBound）、
    /// その s2SplitDelay 秒後に 6 本の小さな矢が散る（タイマー）。
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
        Kit.schedule(&s, caster: i, slot: .skill2, code: T.Code.split, after: T.s2Delay + T.s2SplitDelay,
                     param: c.aim.direction.angle, point: center, interruptible: false)
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

    /// 着弾した矢が 6 本に分かれ、着弾点から 60° おきに散る（撃った向きを 0° として 0° / ±60° / ±120° / 180°）。
    /// それぞれ最初に当たった敵だけに当たる（貫通しない）。
    private func splitEclipse(_ s: inout SimState, _ ctx: SimContext, owner i: Int, timer: KitTimer) {
        guard let (skill, n) = Self.numbersNow(s, ctx, i, .skill2) else { return }
        let damage = Self.minorDamage(rank: n.rank, stats: s.units[i].stats)
        let slow = StatusEffect(kind: .slow, duration: T.s2SlowDuration, magnitude: T.s2Slow, sourceID: s.units[i].id,
                                tag: T.slowTag)
        let p = HitPayload(damage: damage, damageType: skill.damageType, source: .skill(.skill2), statuses: [slow],
                           skillID: skill.skillID, originPos: timer.point)
        // ±150° の扇（-150, -90, …, 150）を 30° 回す = 撃った向きから -120, -60, 0, 60, 120, 180
        Kit.fan(&s, caster: i, direction: Vec2.fromAngle(timer.param + T.s2ScatterTurn), count: T.s2Arrows,
                halfAngle: T.s2ScatterHalfAngle,
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
        // 矢の速さは動画で測った値（構造物への矢も同じ）
        plan.projectileSpeed = T.arrowSpeed
        // 構造物には月矢・月影は働かない（公式の文に無い Velstria の推測。攻城の火力は汎用のレンジャーのまま。攻撃速度の段は積む）
        guard !s.units[target].isStructure, let k = s.units[attacker].hero?.kit else { return }
        if k.luminaMoonArrow > 0 {
            plan.payload.damage += k.luminaArrowBonus
            Self.fireSplash(&s, attacker: attacker, primary: target, mainDamage: plan.payload.damage,
                            isCrit: plan.payload.isCrit)
        }
        // 月影は主矢の命中で現れる（onBasicAttackHit）。発射の時には何も足さない
    }

    func onBasicAttackHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, damage: Double) {
        guard let k = s.units[attacker].hero?.kit else { return }
        // 月影（動画で測った値）: 最大の段のあいだ、主矢が命中した瞬間に術者の足元へ月影が現れ、術者の位置から対象へ自分の矢を放つ
        // （約 4 の距離で主矢の 8 コマ = 0.27 秒後に着く）。段はこの命中で積む前の数で見る（5 段目を積んだ命中では出ない）。
        // 構造物・倒れた対象には出ない
        if k.luminaStacks >= T.maxStacks, !s.units[target].isStructure, CombatSystem.isLiving(s, target) {
            Self.summonShadow(&s, attacker: attacker, target: target)
        }
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

    /// 離脱が要る状態か: HP が 45% 以下、または減速・バインド（root）を受けていて HP が 70% 以下。すでに隠れている間は不要。
    static func needsEscape(_ s: SimState, _ bot: Int) -> Bool {
        guard s.units.indices.contains(bot), s.units[bot].hero?.kit?.luminaHidden != true else { return false }
        let hp = s.units[bot].hpRatio
        let hobbled = s.units[bot].has(.slow) || s.units[bot].has(.root)
        return hp <= T.escapeHP || (hobbled && hp <= T.escapeHPHobbled)
    }

    // MARK: ヘルパー

    /// 月影のダメージ（公式 25 (+20% 物理攻撃) = 25 + 合計の物理攻撃 × 0.20）。
    static func shadowDamage(attack: Double) -> Double { T.shadowFlat + T.shadowRatio * attack }

    /// 月影の命中: 通常攻撃のダメージ（source .basicAttack）で、攻撃エフェクト 20%（装備の命中時効果・通常攻撃吸収を 20% だけ）。
    /// 通常攻撃そのものではない（appliesOnHit = false: 命中数・段の加算・パッシブの命中フックに数えない）。会心にならない
    /// （公式の文に会心の記述が無い。未検証）。
    static func shadowPayload(attack: Double) -> HitPayload {
        HitPayload(damage: shadowDamage(attack: attack), damageType: .physical, source: .basicAttack,
                   attackEffect: T.shadowAttackEffect)
    }

    /// 月影の矢: 術者の位置から対象への追尾弾（通常攻撃の矢と同じ速さ）。主矢の命中のたびに 1 本。
    static func summonShadow(_ s: inout SimState, attacker i: Int, target t: Int) {
        s.units[i].hero?.kit?.luminaShadows += 1
        ProjectileSystem.spawn(&s, ownerIndex: i, motion: .homing(targetID: s.units[t].id), speed: T.arrowSpeed,
                               payload: shadowPayload(attack: s.units[i].stats.attack), visual: "basic_attack")
    }

    /// 月弦分矢の持続（公式 4 / 5 / 6 / 7 / 8 / 9 秒）。
    static func s1Duration(rank: Int) -> Double { Kit.level(T.s1Duration, rank: rank) }

    /// 月弦分矢の主矢 1 本の追加ダメージ（公式の基礎 10 / 15 / 20 / 25 / 30 / 35。+100% 物理攻撃は通常攻撃そのもの）。
    static func arrowBonus(rank: Int) -> Double { Kit.level(T.s1Base, rank: rank) }

    /// 月蝕の矢の着弾のダメージ（公式 270〜420 (+45% 物理攻撃)。合計の物理攻撃）。
    static func eclipseDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(T.s2Base, rank: rank, ratio: T.s2AttackRatio, .totalAttack, stats: stats)
    }

    /// 月蝕の矢の小さな矢 1 本のダメージ（公式 40〜105 (+20% 物理攻撃)。合計の物理攻撃）。
    static func minorDamage(rank: Int, stats: Stats) -> Double {
        Kit.official(T.s2MinorBase, rank: rank, ratio: T.s2MinorAttackRatio, .totalAttack, stats: stats)
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

    /// 副矢: 主矢の対象の周囲にいる最も近い敵（最大 splashCount 体）へ、主矢の 30% の追尾弾（攻撃エフェクト 30%）。
    /// 術者の射程の近くにいる敵だけ（射程外の敵へは飛ばない）。構造物へは飛ばない（対象の選び方は Velstria の推測）。
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
        let p = splashPayload(mainDamage: mainDamage, isCrit: isCrit)
        for entry in picked.prefix(T.splashCount) {
            ProjectileSystem.spawn(&s, ownerIndex: i, motion: .homing(targetID: s.units[entry.j].id),
                                   speed: T.arrowSpeed, payload: p, visual: "basic_attack")
            s.units[i].hero?.kit?.luminaSplashArrows += 1
        }
    }

    /// 副矢の命中: 主矢（追加ダメージ込み）の 30% の通常攻撃のダメージで、攻撃エフェクト 30%（公式「各矢は攻撃効果の30%を引き継ぎ」）。
    /// 通常攻撃そのものではない（appliesOnHit = false: 段・命中数に数えない）。会心の表示は主矢から引き継ぐ。
    static func splashPayload(mainDamage: Double, isCrit: Bool) -> HitPayload {
        HitPayload(damage: mainDamage * T.splashRatio, damageType: .physical, source: .basicAttack, isCrit: isCrit,
                   attackEffect: T.splashAttackEffect)
    }

    /// 現在のランク・能力値でのスキルと数値。
    static func numbersNow(_ s: SimState, _ ctx: SimContext, _ i: Int, _ slot: SkillSlot) -> (SkillDef, SkillNumbers)? {
        guard let h = s.units[i].hero, let def = ctx.master.hero(h.heroID),
              let skill = ctx.master.skill(hero: h.heroID, slot: slot) else { return nil }
        return (skill, SkillCatalog.numbers(for: skill, hero: def, rank: max(1, h.rank(slot)), stats: s.units[i].stats))
    }

    /// 説明文に埋める秒数（整数なら整数、そうでなければ小数 2 桁まで。0.35 が 0.3 / 0.4 に丸まらないように）。
    static func seconds(_ v: Double) -> String {
        if abs(v - v.rounded()) < 0.005 { return String(Int(v.rounded())) }
        var t = String(format: "%.2f", v)
        while t.hasSuffix("0") { t.removeLast() }
        return t
    }
}

extension Kit_H025 {
    /// ZoneSystem.spawn と同じ形（描画の事前生成用。HeroKit.plannedZones）。
    func plannedZones(master: MasterData) -> [KitZoneShape] {
        // S2 月蝕: 照準の半径の円（castEclipse）
        [KitZoneShape(radius: T.s2Radius)]
    }
}
