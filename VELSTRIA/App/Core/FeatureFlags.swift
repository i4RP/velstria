import Foundation

// 担当: 統合（契約）

enum FeatureFlags {
    /// オンライン機能（フレンド・チャット・パーティ・招待・オンラインランキング）。Phase 2 でサーバー導入後に有効化。
    static let online = false
    /// StoreKit による有償通貨販売。App Store Connect に商品登録済みであること。
    static let inAppPurchases = true
    /// デバッグメニュー（DEBUG ビルドのみ）。
    #if DEBUG
    static let debugMenu = true
    #else
    static let debugMenu = false
    #endif

    static let supportEmail = "support@velstria.example"
    static let privacyPolicyURL = URL(string: "https://velstria.example/privacy")!
    static let termsURL = URL(string: "https://velstria.example/terms")!
    static let currentTermsVersion = 1
}
