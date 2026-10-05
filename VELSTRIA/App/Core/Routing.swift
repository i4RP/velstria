import SwiftUI
import VelstriaCore

// 担当: 統合（契約）。Route の追加・画面の差し替えは統合フェーズで行う。
// 各画面の実体は Screens/<Area>/ の担当ファイルにある（ここでは型名で参照するだけ）。

/// NavigationStack で push する画面。
enum Route: Hashable {
    // ui-flow
    case notices                 // UI008
    case mail                    // UI009
    case profile                 // UI015
    case records                 // UI016
    case achievements            // UI017
    case ranking                 // UI018
    case rankOverview            // UI019
    case rankRewards             // UI020
    case accountLink             // UI005
    // ui-collection
    case heroes                  // UI037
    case heroDetail(String)      // UI038
    case skillDetail(String)     // UI039
    case items                   // UI040
    case itemDetail(String)      // UI041
    case buildEditor(String)     // UI042（heroID）
    case runes                   // UI043
    case spells                  // UI044
    case store                   // UI045
    case skinStore               // UI046
    case currencyStore           // UI047
    case productDetail(String)   // UI048（sku）
    case restorePurchases        // UI051
    case inventory               // UI057
    case cosmetics               // UI058
    case emotes                  // UI059
    // ui-liveops
    case events                  // UI052
    case eventDetail(String)     // UI053
    case missions                // UI054
    case starPass                // UI055
    case settings                // UI060
    case controlSettings         // UI061
    case graphicsSettings        // UI062
    case audioSettings           // UI063
    case languageSettings        // UI064
    case notificationSettings    // UI065
    case privacySettings         // UI066
    case support                 // UI067
    case faq                     // UI068
    case contact                 // UI069
    case patchNotes              // UI070
    case tutorialMenu            // UI071
    case practiceSetup           // UI072
    case credits                 // UI073
    case replays                 // UI035
    case spectateSetup           // UI036
    // ゲームモード（モバイルレジェンド風の選択画面）
    case arcade                  // アーケード（遊べる変種のハブ）
    case rising                  // ライジング（対 AI の勝ち上がりラダー）
    case customSetup             // AI 対戦とカスタム
    case magicChess              // マジックチェス（オートバトラー）
}

@Observable
final class Router {
    var path: [Route] = []
    /// 対戦前フロー（モード選択 → ドラフト/ヒーロー選択 → ロードアウト → マッチング）。
    var isMatchFlowPresented = false

    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
}

struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .notices: NoticesView()
        case .mail: MailView()
        case .profile: ProfileView()
        case .records: RecordsView()
        case .achievements: AchievementsView()
        case .ranking: RankingView()
        case .rankOverview: RankOverviewView()
        case .rankRewards: RankRewardsView()
        case .accountLink: AccountLinkView()
        case .heroes: HeroListView()
        case .heroDetail(let id): HeroDetailView(heroID: id)
        case .skillDetail(let id): SkillDetailView(skillID: id)
        case .items: ItemListView()
        case .itemDetail(let id): ItemDetailView(itemID: id)
        case .buildEditor(let id): BuildEditorView(heroID: id)
        case .runes: RunePageView()
        case .spells: SpellLoadoutView()
        case .store: StoreHomeView()
        case .skinStore: SkinStoreView()
        case .currencyStore: CurrencyStoreView()
        case .productDetail(let sku): ProductDetailView(sku: sku)
        case .restorePurchases: RestorePurchasesView()
        case .inventory: InventoryView()
        case .cosmetics: CosmeticsView()
        case .emotes: EmoteLoadoutView()
        case .events: EventsView()
        case .eventDetail(let id): EventDetailView(eventID: id)
        case .missions: MissionsView()
        case .starPass: StarPassView()
        case .settings: SettingsView()
        case .controlSettings: ControlSettingsView()
        case .graphicsSettings: GraphicsSettingsView()
        case .audioSettings: AudioSettingsView()
        case .languageSettings: LanguageSettingsView()
        case .notificationSettings: NotificationSettingsView()
        case .privacySettings: PrivacySettingsView()
        case .support: SupportView()
        case .faq: FAQView()
        case .contact: ContactView()
        case .patchNotes: PatchNotesView()
        case .tutorialMenu: TutorialMenuView()
        case .practiceSetup: PracticeSetupView()
        case .credits: CreditsView()
        case .replays: ReplayListView()
        case .spectateSetup: SpectateSetupView()
        case .arcade: ArcadeHubView()
        case .rising: RisingBracketView()
        case .customSetup: CustomSetupView()
        case .magicChess: MagicChessSetupView()
        }
    }
}
