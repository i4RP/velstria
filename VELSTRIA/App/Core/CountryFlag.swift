import SwiftUI

/// 国・地域の旗（ISO 3166 の 2 文字 → 絵文字の国旗）。ロード画面のカードの左上に出す。
enum CountryFlag {
    /// 端末の地域（アカウント作成時に Profile.countryCode へ入れる）。
    static var deviceRegion: String? { normalized(Locale.current.region?.identifier ?? "") }

    /// 自分の国（プロフィールの読み込み時に入る。オンラインの名乗りで送る）。
    nonisolated(unsafe) static var local: String? = deviceRegion

    /// 英大文字 2 文字だけを通す。
    static func normalized(_ code: String) -> String? {
        let c = code.uppercased()
        return c.count == 2 && c.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) ? c : nil
    }

    static func emoji(_ code: String) -> String? {
        guard let c = normalized(code) else { return nil }
        return String(String.UnicodeScalarView(c.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }))
    }
}

/// 丸い国旗バッジ。
struct CountryFlagBadge: View {
    let code: String?
    var size: CGFloat = 22

    var body: some View {
        if let code, let flag = CountryFlag.emoji(code) {
            Text(flag)
                .font(.system(size: size * 1.35))
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.2))
                .shadow(color: .black.opacity(0.5), radius: 2)
                .accessibilityLabel(Locale.current.localizedString(forRegionCode: code) ?? code)
        }
    }
}
