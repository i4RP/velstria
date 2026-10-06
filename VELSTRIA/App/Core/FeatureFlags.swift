import Foundation

// 担当: 統合（契約）

enum FeatureFlags {
    /// オンライン機能（フレンド・チャット・パーティ・招待・オンラインランキング）。Phase 2 でサーバー導入後に有効化。
    static let online = false
    /// オンライン対戦（リッスンサーバー: 参加者の 1 台がホスト。同一 LAN / Bonjour、IP 直接入力、または部屋コード（中継サーバー経由））。
    /// 開発期間の対戦テスト用。App Store 提出時は審査メモ・年齢区分の記述（「マルチプレイなし」）と整合させること。
    static let lanMatch = true
    /// StoreKit による有償通貨販売。App Store Connect に商品登録済みであること。
    static let inAppPurchases = true
    /// デバッグメニュー（DEBUG ビルドのみ）。
    #if DEBUG
    static let debugMenu = true
    #else
    static let debugMenu = false
    #endif

    // 公開 URL・窓口（App Store 提出前に確定値へ置き換える。docs/APPSTORE.md §2）。
    // tools/validate_appstore_metadata.py --release は、このファイルを含む App/ のソースに仮ドメイン（.example）や
    // {{…}} が残っているとエラーにする。privacy の URL は metadata/<locale>/privacy_url.txt と一致させること（検証あり）。
    static let supportEmail = "support@velstria.example"
    static let privacyPolicyURLJa = URL(string: "https://velstria.example/privacy")!
    static let privacyPolicyURLEn = URL(string: "https://velstria.example/en/privacy")!
    static let termsURLJa = URL(string: "https://velstria.example/terms")!
    static let termsURLEn = URL(string: "https://velstria.example/en/terms")!
    /// 表示言語のプライバシーポリシー（英語表示では英語版を開く）。
    static var privacyPolicyURL: URL { Loc.isEnglish ? privacyPolicyURLEn : privacyPolicyURLJa }
    /// 表示言語の利用規約（英語表示では英語版を開く）。
    static var termsURL: URL { Loc.isEnglish ? termsURLEn : termsURLJa }
    static let currentTermsVersion = 1
}
