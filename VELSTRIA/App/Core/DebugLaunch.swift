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
//   -battle <mode>        起動後に戦闘開始（standard / ranked / practice / tutorial / spectate）
//   -hero <heroID>        -battle で自分が使うヒーロー（省略時は最後に選んだヒーロー、無ければ H003）
//   -language <ja|en>     表示言語
//   -heroGallery          ヒーロー 3D モデル一覧（hero-models の目視確認用）

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
        app.profile = p

        if let r = value(after: "-route"), let route = parseRoute(r) {
            app.router.path = [route]
        }
        if let mode = value(after: "-battle") {
            let hero = value(after: "-hero").flatMap { app.master.hero($0)?.heroID } ?? p.lastPickedHeroID ?? "H003"
            let seed: UInt64 = 20261001
            let name = p.displayName.isEmpty ? "Tester" : p.displayName
            switch mode {
            case "practice", "tutorial":
                app.startBattle(BattleLaunch(config: MatchFactory.practiceMatch(
                    humanHeroID: hero, humanName: name, options: PracticeOptions(), tutorial: mode == "tutorial", seed: seed)))
            case "spectate":
                app.startBattle(BattleLaunch(config: MatchFactory.botMatch(seed: seed)))
            default:
                let ranked = mode == "ranked"
                app.startBattle(BattleLaunch(config: MatchFactory.standardMatch(
                    mode: ranked ? .ranked : .standard, humanHeroID: hero, humanName: name, seed: seed),
                                             countsForRank: ranked))
            }
        }
        #endif
    }

    #if DEBUG || SCREENSHOTS
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
        case "itemDetail": return .itemDetail(arg.isEmpty ? "EQ031" : arg)
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
        default: return nil
        }
    }
    #endif
}
