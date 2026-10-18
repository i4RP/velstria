import Foundation

// 担当: 統合（契約）

enum FeatureFlags {
    /// オンライン対戦とフレンド・パーティ（リッスンサーバー: 参加者の 1 台がホスト。同一 LAN / Bonjour、IP 直接入力、または部屋コード（中継サーバー経由））。
    /// ホームの「オンライン」から使う。初回はコミュニティガイドラインと利用規約への同意が要る（OnlineAccess。13 歳未満は使えない）。
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
    static let supportEmail = "info@btcpay.jp"
    static let privacyPolicyURLJa = URL(string: "https://velsia.xyz/privacy")!
    static let privacyPolicyURLEn = URL(string: "https://velsia.xyz/en/privacy")!
    static let termsURLJa = URL(string: "https://velsia.xyz/terms")!
    static let termsURLEn = URL(string: "https://velsia.xyz/en/terms")!
    /// 表示言語のプライバシーポリシー（英語表示では英語版を開く）。
    static var privacyPolicyURL: URL { Loc.isEnglish ? privacyPolicyURLEn : privacyPolicyURLJa }
    /// 表示言語の利用規約（英語表示では英語版を開く）。
    static var termsURL: URL { Loc.isEnglish ? termsURLEn : termsURLJa }
    static let currentTermsVersion = 1

    // オンライン機能のルール（ガイドライン 1.2）。公開サイト（site/）の同じパスのページを開く。
    static let communityGuidelinesURLJa = URL(string: "https://velsia.xyz/community")!
    static let communityGuidelinesURLEn = URL(string: "https://velsia.xyz/en/community")!
    /// 規約・表示の一覧（利用規約・プライバシー・特商法・資金決済法・外部送信など）。
    static let legalIndexURLJa = URL(string: "https://velsia.xyz/legal")!
    static let legalIndexURLEn = URL(string: "https://velsia.xyz/en/legal")!
    /// オープンソースライセンスの一覧（アプリ内のクレジットにも主な表記を載せる）。
    static let licensesURLJa = URL(string: "https://velsia.xyz/licenses")!
    static let licensesURLEn = URL(string: "https://velsia.xyz/en/licenses")!
    /// 通報とブロックの方法・データの削除とプライバシーの選択（ASC の「ユーザーのプライバシー選択 URL」と同じページ）。
    static let safetyURLJa = URL(string: "https://velsia.xyz/safety")!
    static let safetyURLEn = URL(string: "https://velsia.xyz/en/safety")!
    static let privacyChoicesURLJa = URL(string: "https://velsia.xyz/privacy-choices")!
    static let privacyChoicesURLEn = URL(string: "https://velsia.xyz/en/privacy-choices")!
    /// 外部送信の公表（電気通信事業法 第 27 条の 12。英語版は参考訳）。設定 > プライバシーとオンラインの同意画面から直接開く。
    static let externalTransmissionURLJa = URL(string: "https://velsia.xyz/external-transmission")!
    static let externalTransmissionURLEn = URL(string: "https://velsia.xyz/en/external-transmission")!
    static var communityGuidelinesURL: URL { Loc.isEnglish ? communityGuidelinesURLEn : communityGuidelinesURLJa }
    static var safetyURL: URL { Loc.isEnglish ? safetyURLEn : safetyURLJa }
    static var privacyChoicesURL: URL { Loc.isEnglish ? privacyChoicesURLEn : privacyChoicesURLJa }
    static var legalIndexURL: URL { Loc.isEnglish ? legalIndexURLEn : legalIndexURLJa }
    static var licensesURL: URL { Loc.isEnglish ? licensesURLEn : licensesURLJa }
    static var externalTransmissionURL: URL { Loc.isEnglish ? externalTransmissionURLEn : externalTransmissionURLJa }
    /// オンライン機能のルール（コミュニティガイドラインと利用規約のオンラインの条項）の版。
    /// 上げると、次にオンラインを開いた時に同意し直す（それまでフレンドの受信箱へも繋がない。OnlineAccess）。
    static let currentOnlineRulesVersion = 1
}
