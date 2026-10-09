import CryptoKit
import Foundation
import VelstriaCore

// 担当: 統合。内部テスト用の「全ヒーロー解放」。
//
// 引き換えコードを知っている端末だけ、設定画面からコードを入力して全ヒーローを解放できる（他のテスターには出ない）。
// コードそのものはリポジトリに置かず、SHA-256 だけを持つ（リポジトリは公開）。解放の記録はプロフィールとは別に UserDefaults へ
// 置く（Profile に項目を足すと古い保存データが読めなくなるため）。起動時に毎回、所持ヒーローへ全員を足す
// （新しいヒーローが増えても入力し直し不要）。
//
// 有効なのは DEBUG / SCREENSHOTS、または内部テスト用の配信ビルド（tools/archive.sh が TESTER_TOOLS=1 のとき
// SWIFT_ACTIVE_COMPILATION_CONDITIONS に TESTER_TOOLS を足す）だけ。App Store 用のアーカイブには含めない（隠し機能を持たない）。
enum TesterAccess {
    #if DEBUG || SCREENSHOTS || TESTER_TOOLS
    static let isAvailable = true
    #else
    static let isAvailable = false
    #endif

    /// 引き換えコード（英数字 20 文字。ハイフン・空白・大小文字は無視）の SHA-256（16 進）。
    static let codeDigest = "300806f78bba45f7a6205cb8c8d74542acf11608e2c943bf041b550bf51af7c3"

    static let flagKey = "velstria.testerUnlockAll"

    /// 入力を正規化する（英数字だけを大文字にする）。
    static func normalize(_ code: String) -> String {
        String(code.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    static func digest(of code: String) -> String {
        SHA256.hash(data: Data(normalize(code).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func isValid(_ code: String, expectedDigest: String = codeDigest) -> Bool {
        digest(of: code) == expectedDigest
    }

    /// この端末で全ヒーロー解放が有効か。
    static func isUnlocked(defaults: UserDefaults = .standard) -> Bool {
        isAvailable && defaults.bool(forKey: flagKey)
    }

    /// コードを検証し、正しければこの端末の解放を有効にする。誤りなら何も変えない。
    @discardableResult
    static func redeem(_ code: String, expectedDigest: String = codeDigest, defaults: UserDefaults = .standard) -> Bool {
        guard isAvailable, isValid(code, expectedDigest: expectedDigest) else { return false }
        defaults.set(true, forKey: flagKey)
        return true
    }

    /// 解放を無効に戻す（所持ヒーローはそのまま。次の起動から追加されなくなる）。
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: flagKey)
    }

    /// 全ヒーローを所持に足す（既存の所持は消さない・順序は保つ）。変わったら true。
    @discardableResult
    static func grantAllHeroes(to profile: inout Profile, master: MasterData) -> Bool {
        let missing = master.heroes.map(\.heroID).filter { !profile.ownedHeroIDs.contains($0) }
        guard !missing.isEmpty else { return false }
        profile.ownedHeroIDs.append(contentsOf: missing)
        return true
    }

    /// 起動時: 解放が有効なら全ヒーローを足す。
    static func applyIfUnlocked(to profile: inout Profile, master: MasterData, defaults: UserDefaults = .standard) {
        guard isUnlocked(defaults: defaults) else { return }
        grantAllHeroes(to: &profile, master: master)
    }
}
