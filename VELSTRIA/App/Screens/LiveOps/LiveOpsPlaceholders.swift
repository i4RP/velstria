import SwiftUI
import VelstriaCore

// 担当: ui-liveops。Wave 1 で各 View を実装に置き換える（型名・イニシャライザ引数は変更しないこと）。

struct EventsView: View {
    var body: some View { PlaceholderScreen(title: "イベント", screenID: "UI052") }
}

struct EventDetailView: View {
    let eventID: String
    var body: some View { PlaceholderScreen(title: "イベント詳細", screenID: "UI053") }
}

struct MissionsView: View {
    var body: some View { PlaceholderScreen(title: "ミッション", screenID: "UI054") }
}

struct StarPassView: View {
    var body: some View { PlaceholderScreen(title: "スターパス", screenID: "UI055") }
}

struct ReplayListView: View {
    var body: some View { PlaceholderScreen(title: "リプレイ", screenID: "UI035") }
}

struct SpectateSetupView: View {
    var body: some View { PlaceholderScreen(title: "観戦", screenID: "UI036") }
}

struct TutorialMenuView: View {
    var body: some View { PlaceholderScreen(title: "チュートリアル", screenID: "UI071") }
}

struct PracticeSetupView: View {
    var body: some View { PlaceholderScreen(title: "練習場", screenID: "UI072") }
}
