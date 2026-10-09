import Foundation
import VelstriaCore

// 担当: 統合（契約）。UI テスト・スクリーンショット検証用の起動引数。
//
// 出荷ビルドでは無効: DEBUG（Xcode の Run / Test）または SCREENSHOTS（tools/screenshots.sh が
// SWIFT_ACTIVE_COMPILATION_CONDITIONS に追加する）でコンパイルした場合だけ起動引数を読む。
// App Store 用のアーカイブ（tools/archive.sh）はどちらも定義しないため、-grant・-skipOnboarding
// （規約同意・年齢区分の省略）・-heroGallery などの隠し機能はバイナリに含まれない（ガイドライン 2.3.1）。
//
//   -uiTesting            一時ディレクトリの新規プロフィールで起動（実データに触れない）
//   -skipOnboarding       オンボーディング完了済みにする
//   -grant                Coin 100000 / Gem 10000 を付与し全ヒーロー解放
//   -route <name>         起動後に画面へ直行（例: heroes, heroDetail:H003, store, settings）
//   -battle <mode>        起動後に戦闘開始（standard / ranked / practice / tutorial / spectate / replay）
//                         replay = 保存済みの最新のリプレイ（無ければ AI 同士 5 分の合成リプレイ）
//   -spectateMap <standard|brawl>  -battle spectate のマップ（brawl = 全員 AI の乱闘）
//   -spectateSpeed <0.5|1|2|4|8>   観戦・リプレイの初期速度
//   -spectateVision <all|blue|red> 観戦・リプレイの初期視界
//   -spectateDirector <on|off>     観戦・リプレイの自動カメラ
//   -seekTo <秒>          最初の観戦・リプレイの読み込み後にその時刻へシークする
//   -sampleReplays        リプレイ一覧の確認用に見本のリプレイを保存する（AI 観戦・自分の試合・乱闘・別バージョン）
//   -practiceNoCD / -practiceLevel <n>  -battle practice の設定（クールダウン無し / 開始レベル）
//   -efkAuto <atk|s1|s2|ult>  -battle practice で、人形へ近づいて 2 秒ごとに通常攻撃 / スキルを撃ち続ける（Effekseer の確認用）
//   -hero <heroID>        -battle で自分が使うヒーロー（省略時は最後に選んだヒーロー、無ければ H003）
//   -language <ja|en>     表示言語
//   -graphics <low|medium|high>  画質
//   -heroGallery          ヒーロー 3D モデル一覧（hero-models の目視確認用）
//   -homeRail collapsed   ホームの右レール（モード一覧）を畳んだ状態で開く
//   -homeMenu             ホームのメニュードロワーを開いた状態で開く
//   -homeHero <heroID>    ホーム中央のショーケースに最初に出すヒーロー
//   -home3D               ホーム中央のショーケースを 3D 表示で開く
//   -onlineHost [port]    起動後にオンライン対戦の部屋を作る（待ち受けポート省略時は既定）。LAN の待ち受けと中継（部屋コード）の両方を開く
//   -relayCode <CODE>     -onlineHost の部屋コードを決める（自動検証用。使われていても作り直さない）
//   -relayURL <ws(s)://…> 中継サーバーの URL を差し替える（既定は OnlineRelayConfig.defaultBaseURL。例 ws://127.0.0.1:8787）
//   -onlineJoin <host:port>  起動後に部屋へ接続する（LAN）
//   -onlineJoinCode <CODE>   起動後に部屋コードで部屋へ入る（中継経由）
//   -onlineAuto           部屋で自動的に着席・ヒーロー選択・準備完了にし、ホストは全員揃ったら開始する（2 台のシミュレータでの検証用）
//   -onlineSpectate       観戦で検証する: -onlineJoin / -onlineJoinCode と併せると観戦席で入る（試合中なら途中から観戦）。
//                         -onlineHost -onlineAuto と併せるとホストは座らずに実況（キャスター）として開始する

enum DebugLaunch {
    /// 起動引数による検証用フックがこのビルドで有効か（出荷ビルドでは false）。
    #if DEBUG || SCREENSHOTS
    static let isEnabled = true
    static var args: [String] { ProcessInfo.processInfo.arguments }
    #else
    static let isEnabled = false
    /// 出荷ビルドでは起動引数を一切読まない（下の判定はすべて偽になる）。
    static var args: [String] { [] }
    #endif
    static var isUITesting: Bool { args.contains("-uiTesting") }

    static func value(after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func makePersistence() -> PersistenceService {
        #if DEBUG || SCREENSHOTS
        if isUITesting {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("VelstriaUITest-\(UUID().uuidString)", isDirectory: true)
            return PersistenceService(directory: dir)
        }
        #endif
        return PersistenceService()
    }

    @MainActor
    static func apply(to app: AppModel) {
        #if DEBUG || SCREENSHOTS
        var p = app.profile
        if args.contains("-skipOnboarding") {
            p.onboardingCompleted = true
            p.tutorialCompleted = true
            p.firstResourcePrepared = true
            p.acceptedTermsVersion = FeatureFlags.currentTermsVersion
            p.ageBracket = p.ageBracket ?? .adult
            if p.displayName.isEmpty { p.displayName = "Tester" }
        }
        if args.contains("-grant") {
            p.starlightCoin = max(p.starlightCoin, 100_000)
            p.freeGem = max(p.freeGem, 10_000)
            p.ownedHeroIDs = app.master.heroes.map(\.heroID)
        }
        if let lang = value(after: "-language"), let l = AppLanguage(rawValue: lang) {
            p.settings.language = l
        }
        if let g = value(after: "-graphics"), let q = GraphicsQuality.allCases.first(where: { "\($0)" == g }) {
            p.settings.graphicsQuality = q
        }
        app.profile = p
        if args.contains("-sampleReplays") { addSampleReplays(to: app) }

        if let r = value(after: "-route"), let route = parseRoute(r) {
            app.router.path = [route]
        }
        if args.contains("-onlineHost") {
            let port = value(after: "-onlineHost").flatMap { UInt16($0) } ?? OnlineProtocol.defaultPort
            let code: String? = value(after: "-relayCode").flatMap { try? RelayRoomCode.parse($0).get() }
            app.hostOnlineRoom(name: "\(p.displayName.isEmpty ? "Host" : p.displayName) (sim)", port: port, relayCode: code)
            app.router.path = [.onlineLobby]
        } else if let raw = value(after: "-onlineJoinCode") {
            switch RelayRoomCode.parse(raw) {
            case .success(let code):
                app.joinOnlineRoom(relayCode: code, wantsSpectate: args.contains("-onlineSpectate"))
            case .failure(let error):
                app.showToast(error.message)
            }
            app.router.path = [.onlineLobby]
        } else if let address = value(after: "-onlineJoin"), let target = OnlineNetwork.parseAddress(address) {
            let spectate = args.contains("-onlineSpectate")
            app.joinOnlineRoom(connection: NWOnlineConnection(host: target.host, port: target.port), wantsSpectate: spectate)
            app.router.path = [.onlineLobby]
        }
        if let mode = value(after: "-battle") {
            let hero = value(after: "-hero").flatMap { app.master.hero($0)?.heroID } ?? p.lastPickedHeroID ?? "H003"
            let seed: UInt64 = 20261001
            let name = p.displayName.isEmpty ? "Tester" : p.displayName
            switch mode {
            case "practice", "tutorial":
                app.startBattle(BattleLaunch(config: MatchFactory.practiceMatch(
                    humanHeroID: hero, humanName: name,
                    options: PracticeOptions(noCooldowns: args.contains("-practiceNoCD"), startLevel: value(after: "-practiceLevel").flatMap { Int($0) } ?? 1),
                    tutorial: mode == "tutorial", seed: seed)))
            case "spectate":
                let config = value(after: "-spectateMap") == "brawl"
                    ? MatchFactory.spectateMatch(options: SpectateMatchOptions(map: .brawl), seed: seed)
                    : MatchFactory.botMatch(seed: seed)
                app.startBattle(BattleLaunch(config: config, spectatorOptions: spectatorOptions()))
            case "replay":
                app.startBattle(latestReplayLaunch(app: app, seed: seed))
            default:
                let ranked = mode == "ranked"
                app.startBattle(BattleLaunch(config: MatchFactory.standardMatch(
                    mode: ranked ? .ranked : .standard, humanHeroID: hero, humanName: name, seed: seed),
                                             countsForRank: ranked))
            }
        }
        #endif
    }

    /// 戦闘の controller ができた直後に BattleContainerView から呼ばれる（-seekTo を最初の 1 回だけ適用）。
    @MainActor
    static func battleDidStart(_ controller: BattleController) {
        #if DEBUG || SCREENSHOTS
        // ストア用スクリーンショット向け: -botControl は操作キャラを AI に任せ（HUD は操作キャラのまま）、
        // -battleSpeed <1〜8> は試合を早送りして、短い待ち時間で中盤の戦闘を撮れるようにする。
        if !didApplyLaunchTweaks, !controller.isSpectating {
            didApplyLaunchTweaks = true
            if args.contains("-botControl") { controller.send(.setController(.bot)) }
            if let raw = value(after: "-battleSpeed"), let v = Double(raw), (1.0...8.0).contains(v) { controller.speed = v }
        }
        guard !didApplySeek, let raw = value(after: "-seekTo"), let seconds = Double(raw), seconds.isFinite, seconds >= 0 else { return }
        didApplySeek = true
        controller.requestSeek(toTick: Int((seconds / Balance.dt).rounded()))
        #endif
    }

    #if DEBUG || SCREENSHOTS
    @MainActor private static var didApplySeek = false
    @MainActor private static var didApplyLaunchTweaks = false

    /// -spectateSpeed / -spectateVision / -spectateDirector から観戦の初期設定を作る。
    @MainActor
    static func spectatorOptions() -> SpectatorOptions {
        var o = SpectatorOptions()
        if let raw = value(after: "-spectateSpeed"), let v = Double(raw), BattleController.spectatorSpeeds.contains(v) { o.speed = v }
        switch value(after: "-spectateVision") {
        case "blue": o.vision = .blue
        case "red": o.vision = .red
        default: break
        }
        switch value(after: "-spectateDirector") {
        case "on": o.director = true
        case "off": o.director = false
        default: break
        }
        return o
    }

    /// 合成リプレイ（AI 同士は入力が無いので構成と長さだけで再現できる）。
    static func syntheticReplay(config: MatchConfig, seconds: Double) -> ReplayData {
        ReplayData(config: config, frames: [], finalTick: Int((seconds / Balance.dt).rounded()), summary: nil)
    }

    /// 保存済みの最新のリプレイ（無い・読めなければ AI 同士 5 分の合成リプレイ）。
    @MainActor
    static func latestReplayLaunch(app: AppModel, seed: UInt64) -> BattleLaunch {
        let options = spectatorOptions()
        if let meta = ReplayLibrary.sorted(app.profile.replays).first,
           case .success(let launch) = ReplayLibrary.launch(for: meta, persistence: app.persistence, options: options) {
            return launch
        }
        let replay = syntheticReplay(config: MatchFactory.botMatch(seed: seed), seconds: 5 * 60)
        return BattleLaunch(config: replay.config, replay: replay, spectatorOptions: options)
    }

    /// 見本のリプレイ（一覧・詳細・取り込みの目視確認用。プロフィールが空の時だけ）。
    @MainActor
    static func addSampleReplays(to app: AppModel) {
        guard app.profile.replays.isEmpty else { return }
        var p = app.profile
        let now = Date()
        let persistence = app.persistence
        let ai = syntheticReplay(config: MatchFactory.botMatch(seed: 20261001), seconds: 9 * 60)
        persistence.storeReplay(ai, heroID: nil, won: nil, date: now.addingTimeInterval(-60), in: &p)
        let brawl = syntheticReplay(config: MatchFactory.spectateMatch(options: SpectateMatchOptions(map: .brawl), seed: 7), seconds: 6 * 60)
        persistence.storeReplay(brawl, heroID: nil, won: nil, date: now.addingTimeInterval(-3600), in: &p)
        let mine = syntheticReplay(config: MatchFactory.standardMatch(humanHeroID: "H003", humanName: "Tester", seed: 11), seconds: 14 * 60)
        if let meta = persistence.storeReplay(mine, heroID: "H003", won: true, date: now.addingTimeInterval(-7200), in: &p),
           let i = p.replays.firstIndex(where: { $0.id == meta.id }) {
            p.replays[i].isFavorite = true
            p.replays[i].name = "Best game"
        }
        var old = syntheticReplay(config: MatchFactory.botMatch(seed: 3), seconds: 12 * 60)
        old.config.simVersion = MatchConfig.currentSimVersion - 1
        persistence.storeReplay(old, heroID: nil, won: nil, date: now.addingTimeInterval(-86_400), in: &p)
        persistence.reconcileReplays(profile: &p)
        app.profile = p
    }

    static func parseRoute(_ s: String) -> Route? {
        let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
        let name = parts[0]
        let arg = parts.count > 1 ? parts[1] : ""
        switch name {
        case "notices": return .notices
        case "mail": return .mail
        case "profile": return .profile
        case "records": return .records
        case "achievements": return .achievements
        case "ranking": return .ranking
        case "rankOverview": return .rankOverview
        case "rankRewards": return .rankRewards
        case "accountLink": return .accountLink
        case "heroes": return .heroes
        case "heroDetail": return .heroDetail(arg.isEmpty ? "H001" : arg)
        case "skillDetail": return .skillDetail(arg.isEmpty ? "SK001_2" : arg)
        case "items": return .items
        case "itemDetail": return .itemDetail(arg.isEmpty ? "EQ101" : arg)
        case "buildEditor": return .buildEditor(arg.isEmpty ? "H001" : arg)
        case "runes": return .runes
        case "spells": return .spells
        case "store": return .store
        case "skinStore": return .skinStore
        case "currencyStore": return .currencyStore
        case "productDetail": return .productDetail(arg.isEmpty ? "SKU001" : arg)
        case "restorePurchases": return .restorePurchases
        case "inventory": return .inventory
        case "cosmetics": return .cosmetics
        case "emotes": return .emotes
        case "events": return .events
        case "eventDetail": return .eventDetail(arg)
        case "missions": return .missions
        case "starPass": return .starPass
        case "settings": return .settings
        case "controlSettings": return .controlSettings
        case "graphicsSettings": return .graphicsSettings
        case "audioSettings": return .audioSettings
        case "languageSettings": return .languageSettings
        case "notificationSettings": return .notificationSettings
        case "privacySettings": return .privacySettings
        case "support": return .support
        case "faq": return .faq
        case "contact": return .contact
        case "patchNotes": return .patchNotes
        case "tutorialMenu": return .tutorialMenu
        case "practiceSetup": return .practiceSetup
        case "credits": return .credits
        case "replays": return .replays
        case "spectateSetup": return .spectateSetup
        case "arcade": return .arcade
        case "rising": return .rising
        case "customSetup": return .customSetup
        case "magicChess": return .magicChess
        case "onlineLobby": return .onlineLobby
        default: return nil
        }
    }
    #endif
}
