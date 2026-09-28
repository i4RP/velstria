import SwiftUI
import VelstriaCore

// 担当: ui-flow。Wave 1 で各 View を実装に置き換える（型名・イニシャライザ引数は変更しないこと）。

struct OnboardingFlowView: View {
    var body: some View { PlaceholderScreen(title: "起動・年齢確認・規約・プレイヤー名・初回準備", screenID: "UI001-006") }
}

struct HomeView: View {
    var body: some View { PlaceholderScreen(title: "ホーム", screenID: "UI007") }
}

struct NoticesView: View {
    var body: some View { PlaceholderScreen(title: "お知らせ", screenID: "UI008") }
}

struct MailView: View {
    var body: some View { PlaceholderScreen(title: "メール", screenID: "UI009") }
}

struct ProfileView: View {
    var body: some View { PlaceholderScreen(title: "プロフィール", screenID: "UI015") }
}

struct RecordsView: View {
    var body: some View { PlaceholderScreen(title: "戦績", screenID: "UI016") }
}

struct AchievementsView: View {
    var body: some View { PlaceholderScreen(title: "実績", screenID: "UI017") }
}

struct RankingView: View {
    var body: some View { PlaceholderScreen(title: "ランキング", screenID: "UI018") }
}

struct RankOverviewView: View {
    var body: some View { PlaceholderScreen(title: "ランク概要", screenID: "UI019") }
}

struct RankRewardsView: View {
    var body: some View { PlaceholderScreen(title: "ランク報酬", screenID: "UI020") }
}

struct AccountLinkView: View {
    var body: some View { PlaceholderScreen(title: "アカウント連携", screenID: "UI005") }
}

struct MatchFlowView: View {
    var body: some View { PlaceholderScreen(title: "マッチ選択・ドラフト・ヒーロー選択", screenID: "UI021-025") }
}

/// UI026 ロード画面。準備完了で onReady を呼ぶ。
struct LoadingScreenView: View {
    let launch: BattleLaunch
    let onReady: () -> Void
    var body: some View {
        PlaceholderScreen(title: "ロード", screenID: "UI026")
            .task { try? await Task.sleep(for: .seconds(1)); onReady() }
    }
}

/// UI032 リザルト（+ UI033 評価 / UI034 通報シート）。閉じるで onClose。
struct MatchResultView: View {
    let outcome: BattleOutcome
    let report: RewardReport
    let onClose: () -> Void
    var body: some View {
        VStack {
            Text("UI032 リザルト")
            Button("閉じる", action: onClose).accessibilityIdentifier("result_close")
        }
    }
}
