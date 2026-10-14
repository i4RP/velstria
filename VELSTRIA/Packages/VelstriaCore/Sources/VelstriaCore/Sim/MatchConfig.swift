import Foundation

public struct PlayerSlot: Codable, Hashable, Sendable {
    public var team: Team
    public var heroID: String
    public var controller: Controller
    public var position: LanePosition
    /// バトルスペル 2 つ。
    public var spells: [String]
    /// エンブレム（nil = 無し）。MatchFactory は人間に選んだもの、ボットに「有効」のバトルプラン（無ければロール別）のものを入れる。
    /// 後から足した任意の値なので、旧版の構成・リプレイ（runes を持つ）は nil として読む。
    public var emblem: EmblemLoadout?
    public var skinID: String?
    public var displayName: String
    public var botDifficulty: Difficulty
    public var autoLevelSkills: Bool
    /// 人間が選んだバトルプランの添字（ItemSystem.heroPlans。nil = 「有効」のプラン。ボットは常に nil）。
    /// 後から足した任意の値なので、旧版の構成・リプレイは nil として読む。
    public var buildPlan: Int?

    public init(team: Team, heroID: String, controller: Controller, position: LanePosition,
                spells: [String] = ["BS01", "BS03"], emblem: EmblemLoadout? = nil, skinID: String? = nil,
                displayName: String, botDifficulty: Difficulty = .normal, autoLevelSkills: Bool = true,
                buildPlan: Int? = nil) {
        self.team = team
        self.heroID = heroID
        self.controller = controller
        self.position = position
        self.spells = spells
        self.emblem = emblem
        self.skinID = skinID
        self.displayName = displayName
        self.botDifficulty = botDifficulty
        self.autoLevelSkills = autoLevelSkills
        self.buildPlan = buildPlan
    }
}

public struct PracticeOptions: Codable, Hashable, Sendable {
    public var infiniteGold: Bool
    public var noCooldowns: Bool
    public var spawnMinions: Bool
    public var spawnDummies: Bool
    public var startLevel: Int

    public init(infiniteGold: Bool = false, noCooldowns: Bool = false, spawnMinions: Bool = true,
                spawnDummies: Bool = true, startLevel: Int = 1) {
        self.infiniteGold = infiniteGold
        self.noCooldowns = noCooldowns
        self.spawnMinions = spawnMinions
        self.spawnDummies = spawnDummies
        self.startLevel = startLevel
    }
}

public struct MatchConfig: Codable, Hashable, Sendable {
    /// リプレイ互換性のためのシミュレーション版数。ルール変更時に上げる。
    /// 4: 乱闘（単レーン・経済加速）を追加。
    /// 5: ジャングル靴・ローム靴（収入制限・共有収入・祝福）と推奨ビルドの靴を追加。
    /// 6: ヒーロー固有スキル（キット層）を有効化（最初は H030 星砲のライナ。以後キットのヒーローは固有のスキル・パッシブ）。
    /// 8: 装備を MLBB の図鑑に総入れ替え（92 個・多段の合成・靴に付ける祝福・装備のアクティブ・ポーション）。
    /// 9: ジャングルを MLBB の現行マップに合わせた（モンスターの種類・草むら・角の壁・バフの効果）。
    /// 10: スキルのクールダウンを MLBB と同じ秒数に（全体倍率 0.5 を廃止。キットの CD 短縮・レイジなどの補正も MLBB の値へ）。
    /// 11: キット（H025 / H026 / H028 / H029 / H030 / H034）の数値・挙動を MLBB の日本語クライアントの画面に合わせた
    ///     （ライラの距離補正 115%・セイバーの追加物理攻撃・エウドラの炸裂は超伝導の敵だけ など）。キットの忠実度（H031 の凍結がタワーにも効く・
    ///     H032 の円撃は装備の命中時効果を発動しない・H034 の鉤の引き寄せが壁を越える）。
    /// 12: H032 の奥義の失った HP の割合 20% → 25%（日本語クライアントの画面）。
    /// 13: 日本語クライアントの無加工の画面に合わせた: H031 の S1・S2 のクールダウン（5 → 4 / 10 → 8 秒）、H033 の S1 の係数 +85% と
    ///     デビルハンター（モンスターへ 110%）、H027 の通常攻撃の式（100 + 物理攻撃 80%）、H025 の S2 のマナ 90（全 Lv）。
    /// 14: H026 / H031 / H034 の推奨ビルドを日本語クライアントのバトルプランに合わせ、H034 のロームの祝福を激励に（ボットの購入が変わる）。
    /// 15: 推奨ビルドを日本語クライアントのバトルプランに合わせる（H025 ほか。ボットの購入が変わる）。
    /// 16: H025〜H034 に 3 つのバトルプラン（人間は PlayerSlot.buildPlan で選べる）。H027 / H030 / H032 の推奨ビルドも
    ///     「有効」のプランになる（ボットの購入が変わる）。
    /// 17: ルーンを廃止して MLBB のエンブレム（7 セット・タレント 3 段）に置き換え（ボットも「有効」のバトルプラン、無ければロール別の
    ///     エンブレムを付ける。能力値と戦い方が変わる）。
    /// 18: エンブレムのレベル（仮の表）。人間の能力値はセットのレベルの値になり、解放レベル未満の段の天賦は働かない
    ///     （1 段目 Lv10・2 段目 Lv15・コア Lv20）。ボットは Lv60 のまま。
    /// 19: 能力値と戦闘の式を MLBB に合わせた（防御 120/(120+防御)・下限 −60、クリティカル 200%、攻撃速度 = 基礎 + 追加 × 比率・
    ///     上限 3、移動速度の加算式・減速の合計 90%、強靭の掛け算、被ダメ軽減の上限撤廃、シールドの消費順など）。全ヒーローの能力値を
    ///     MLBB の値（H025〜H034）とロール中央値（H001〜H024）へ。docs/HERO_STATS.md。
    public static let currentSimVersion = 19

    public var simVersion: Int
    public var mode: MatchMode
    public var seed: UInt64
    /// 通常は 10 人（blue 5 + red 5）。練習場・チュートリアルは人間 1 人のみ。
    public var players: [PlayerSlot]
    public var practice: PracticeOptions?
    /// 安全装置の最大試合時間（秒）。
    public var maxDuration: Double

    public init(mode: MatchMode, seed: UInt64, players: [PlayerSlot], practice: PracticeOptions? = nil,
                maxDuration: Double = 40 * 60) {
        self.simVersion = MatchConfig.currentSimVersion
        self.mode = mode
        self.seed = seed
        self.players = players
        self.practice = practice
        self.maxDuration = maxDuration
    }

    public var humanSlot: PlayerSlot? { players.first { $0.controller == .human } }
}
