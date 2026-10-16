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
    /// 19: 共通回復と12種類のバトルスキル、戦闘効果・CD・狩猟報酬を更新。
    /// 20: 能力値と戦闘の式を MLBB に合わせた（防御 120/(120+防御)・下限 −60、クリティカル 200%、攻撃速度 = 基礎 + 追加 × 比率・
    ///     上限 3、移動速度の加算式・減速の合計 90%、強靭の掛け算、被ダメ軽減の上限撤廃、シールドの消費順など）。全ヒーローの能力値を
    ///     MLBB の値（H025〜H034）とロール中央値（H001〜H024）へ。docs/HERO_STATS.md。
    /// 21: H025〜H034 の 10 体の能力値を日本語クライアントの試合中のステータス画面（Lv1 / Lv15）の値に（Fandom の成長は古かった）。
    /// 22: スキルを MLBB の値に（スキルの段 6 / 6 / 3、キットは公式の表をそのまま・換算と全体の倍率を撤廃、汎用は MLBB のロール × 枠の型、
    ///     ミニオンへのスキル × 0.2 を撤廃しスキルごとの補正、スキル吸収率・攻撃エフェクト、バインドがブリンク・突進を封じる、
    ///     ノックアップ・制圧だけが突進を止める）。docs/SKILL_KITS.md・docs/GENERIC_SKILLS.md。
    /// 23: H029（ティグラル）の幾何と時間を MLBB の画面収録で測った値に（スキル1 = 台形を手前から奥へ 3 回・0.25 / 0.58 / 0.92 秒、
    ///     スキル2 = 525 を 0.67 秒・当たった敵に 0.6 秒のスタン・CD は最初の発動から・再使用の範囲 215、
    ///     奥義 = 半径 278・発動の瞬間にスタン + 引き寄せ・1.0 秒で爆発）。docs/kits/Tigreal.md「動画で測った値」。
    /// 24: 5v5マップを実測時間比で再配置。端でもキャラ中心に追従。
    /// 25: H034（フランコ）の幾何と時間を MLBB の画面収録で測った値に（スキル1 = 射程 823・半幅 35・毎秒 1515・0.33 秒の振りかぶり、
    ///     命中でその場 0.45 秒 → 0.25 秒で引き寄せ → 着地のスタン 0.6 秒、スキル2 = 半径 257・0.27 秒で叩きつけ、
    ///     奥義 = 縁まで 188・0.25 秒で掴んで 0.32 秒おきに 6 撃）。docs/kits/Franco.md「動画で測った値」。
    /// 26: 遊ぶ地図の壁を MLBB のミニマップ原本から起こした滑らかな多角形に（ed0f086。キャンプの位置・拠点の周りの規則も）、
    ///     矩形の角の衝突を丸い膨張に、経路探索の格子を 100 → 50（粗い格子で下見）。
    /// 27: 遊ぶ地図の壁・草むら・川（8 の字の水路）・キャンプをユーザーのマップ設計図（60×60 マス）から起こし直す。
    /// 28: H034（フランコ）のパッシブ ワイルドフォースを MLBB の画面収録に合わせた（闘気 1 つ +15% → +5%・10 で 1.5 倍、
    ///     消費はスキルの発動ではなくダメージが当たった時（外れたら残る）、奥義は 1 撃ごとにその時の闘気を掛けて最後の 1 撃で消費）。
    ///     docs/kits/Franco.md「パッシブを動画に合わせた（2026-10-16）」。
    /// 29: H031（オーロラ）の幾何と時間を MLBB の画面収録で測った値に（スキル1 = 射程 556・半径 191・0.56 秒で着弾・雹 5 発は同じ円の
    ///     全員に 0.47 秒後から 0.15 秒おき、スキル2 = 半径 602・半角 25.3°・0.56 秒で霜風・0.76 秒に扇の先の半分（290〜602）の
    ///     凍結エリアで凍結・0.13 秒おきに 3 回、奥義 = 0.26 秒で道（−70〜680・半幅 48）・1.49 秒で帯の氷河（−70〜620・半幅 245）が
    ///     砕けて凍結）。ゾーンに内側の欠け（innerRadius）と端の四角い線分（squareEnds）を足した。docs/kits/Aurora.md「動画で測った値」。
    /// 30: H025（ミヤ）の幾何と時間を MLBB の画面収録で測った値に（通常攻撃の矢 = 毎秒 1650、月影 = 主矢の命中で術者から放つ、
    ///     スキル2 = 射程 545・離してから 0.65 秒で着弾・その 0.33 秒後に 6 本が撃った向きから 0° / ±60° / ±120° / 180° へ
    ///     毎秒 1250 で 400）。docs/kits/Miya.md「動画で測った値」。27（フランコ）と 29（オーロラ）は並行する別の作業が使う番号。
    /// 27〜29: 同時に進めているほかのヒーローの動画の計測（別の作業）が使う番号。ここでは飛ばす。
    /// 31: H027（子龍）の幾何と時間を MLBB の画面収録で測った値に（スキル1 = 打ち上げ 0.8 → 1.0 秒・0.4 秒持ち上げてから 0.2 秒で
    ///     背後 144 へ放り投げる（以前は命中の瞬間から 0.7 秒で背後 170）、スキル2 = 突進を毎秒 2400 → 1520）。
    ///     docs/kits/Zilong.md「動画で測った値」。
    /// 32: H026（エウドラ）の幾何と時間を MLBB の画面収録で測った値に（スキル1 = 扇 576・半角 37.5°、鎖の継続ダメージ 0.12 秒から 0.27 秒おき 4 回、
    ///     スキル2 = 射程 505・雷球 毎秒 1150、奥義 = 射程 615・0.45 秒・中心 115 / 外側 273、炸裂 = 0.83 秒後・半径 261）。
    ///     docs/kits/Eudora.md「動画で測った値」。27〜31 は並行する他のヒーローの作業（フランコ・ミヤ・オーロラほか）が使うので 32 にした。
    ///     **番号はマージのときに付け直す**（main に入る順で連番にする）。
    /// 33: H028（セイバー）の幾何と時間を MLBB の画面収録で測った値に（スキル1 = 剣は術者から 385 の輪を回り、帯 325〜445 の敵へ
    ///     0.47 秒から 0.48 秒ごとに 9 回・持続 4.8 秒・剣撃の遅れ 0.1 秒、スキル2 = 300 を毎秒 1500、奥義 = 縁まで 545・毎秒 1700・
    ///     到着 + 0 / 0.39 / 0.78 秒の 3 撃・到着から 1.0 秒の硬直）。docs/kits/Saber.md「動画で測った値」。
    ///     27〜32 は並行するほかのヒーローの作業が使う（マージで振り直す）。
    public static let currentSimVersion = 33

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
