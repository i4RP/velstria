import SwiftUI
import VelstriaCore

// 担当: ui-collection。Wave 1 で各 View を実装に置き換える（型名・イニシャライザ引数は変更しないこと）。

struct HeroListView: View {
    var body: some View { PlaceholderScreen(title: "ヒーロー一覧", screenID: "UI037") }
}

struct HeroDetailView: View {
    let heroID: String
    var body: some View { PlaceholderScreen(title: "ヒーロー詳細", screenID: "UI038") }
}

struct SkillDetailView: View {
    let skillID: String
    var body: some View { PlaceholderScreen(title: "スキル詳細", screenID: "UI039") }
}

struct ItemListView: View {
    var body: some View { PlaceholderScreen(title: "装備一覧", screenID: "UI040") }
}

struct ItemDetailView: View {
    let itemID: String
    var body: some View { PlaceholderScreen(title: "装備詳細", screenID: "UI041") }
}

struct BuildEditorView: View {
    let heroID: String
    var body: some View { PlaceholderScreen(title: "ビルド編集", screenID: "UI042") }
}

struct RunePageView: View {
    var body: some View { PlaceholderScreen(title: "ルーン", screenID: "UI043") }
}

struct SpellLoadoutView: View {
    var body: some View { PlaceholderScreen(title: "スペル", screenID: "UI044") }
}
