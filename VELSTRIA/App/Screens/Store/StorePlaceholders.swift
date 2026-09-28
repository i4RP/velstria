import SwiftUI
import VelstriaCore

// 担当: ui-collection。Wave 1 で各 View を実装に置き換える（型名・イニシャライザ引数は変更しないこと）。

struct StoreHomeView: View {
    var body: some View { PlaceholderScreen(title: "ストア", screenID: "UI045") }
}

struct SkinStoreView: View {
    var body: some View { PlaceholderScreen(title: "スキンストア", screenID: "UI046") }
}

struct CurrencyStoreView: View {
    var body: some View { PlaceholderScreen(title: "通貨購入", screenID: "UI047") }
}

struct ProductDetailView: View {
    let sku: String
    var body: some View { PlaceholderScreen(title: "商品詳細", screenID: "UI048") }
}

struct RestorePurchasesView: View {
    var body: some View { PlaceholderScreen(title: "購入の復元", screenID: "UI051") }
}

struct InventoryView: View {
    var body: some View { PlaceholderScreen(title: "インベントリ", screenID: "UI057") }
}

struct CosmeticsView: View {
    var body: some View { PlaceholderScreen(title: "コスメ", screenID: "UI058") }
}

struct EmoteLoadoutView: View {
    var body: some View { PlaceholderScreen(title: "エモート", screenID: "UI059") }
}
