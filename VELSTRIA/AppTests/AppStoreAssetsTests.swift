import UIKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

// 担当: appstore-assets。
// App Store 提出物（英語オーバーレイ・プライバシーマニフェスト・アイコン・起動画面・Info.plist）が
// ビルド済みアプリに正しく入っていることを検査する。生成元は tools/gen_master_en.py と tools/make_icon.swift。

final class AppStoreAssetsTests: XCTestCase {
    private var overlay: [String: String] = [:]

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "master_en", withExtension: "json"),
                                "master_en.json がアプリバンドルに含まれていません")
        overlay = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    // MARK: 英語オーバーレイ

    func testEnglishOverlayCoversEveryMasterID() {
        let m = MasterData.shared
        var missing: [String] = []
        func need(_ key: String) {
            if (overlay[key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty { missing.append(key) }
        }
        for h in m.heroes {
            need(h.heroID)
            for suffix in [".epithet", ".lore", ".strengths", ".weaknesses", ".counterplay"] { need(h.heroID + suffix) }
        }
        for s in m.skills { need(s.skillID); need(s.skillID + ".desc") }
        for i in m.items { need(i.itemID); need(i.itemID + ".desc"); need(i.itemID + ".passive") }
        for s in m.spells { need(s.spellID); need(s.spellID + ".desc") }
        for r in m.runes { need(r.runeID); need(r.runeID + ".desc") }
        for c in m.cosmetics { need(c.cosmeticID) }
        for s in m.store { need(s.sku) }
        for e in m.effects { need(e.effectID) }
        XCTAssertEqual(missing, [], "未翻訳のキーがあります（python3 tools/gen_master_en.py で再生成）")

        XCTAssertEqual(m.heroes.count, 24)
        XCTAssertEqual(m.skills.count, 120)
        XCTAssertEqual(m.items.count, 72)
        XCTAssertEqual(m.spells.count, 10)
        XCTAssertEqual(m.runes.count, 30)
        XCTAssertEqual(m.cosmetics.count, 72)
        XCTAssertEqual(m.store.count, 114)
    }

    func testEnglishOverlayContainsNoJapaneseText() throws {
        let japanese = try NSRegularExpression(pattern: "[\\u3040-\\u30ff\\u3400-\\u9fff\\uff00-\\uffef]")
        let offenders = overlay.keys.sorted().filter { key in
            let v = overlay[key] ?? ""
            return japanese.firstMatch(in: v, range: NSRange(v.startIndex..., in: v)) != nil
        }
        XCTAssertEqual(offenders, [])
    }

    func testCosmeticAndHeroNamesAreUniqueInEnglish() {
        let m = MasterData.shared
        let heroNames = m.heroes.compactMap { overlay[$0.heroID] }
        XCTAssertEqual(Set(heroNames).count, heroNames.count)
        let cosmeticNames = m.cosmetics.compactMap { overlay[$0.cosmeticID] }
        XCTAssertEqual(Set(cosmeticNames).count, cosmeticNames.count)
        let itemNames = m.items.compactMap { overlay[$0.itemID] }
        XCTAssertEqual(Set(itemNames).count, itemNames.count)
    }

    func testMasterTextSwitchesWithLanguage() throws {
        let saved = Loc.current
        defer { Loc.current = saved }
        let m = MasterData.shared
        let alden = try XCTUnwrap(m.heroes.first { $0.heroID == "H001" })
        let lyraRecall = try XCTUnwrap(m.cosmetics.first { $0.cosmeticID == "CO002" })
        let dagger = try XCTUnwrap(m.items.first { $0.itemID == "EQ001" })

        Loc.current = .en
        XCTAssertEqual(MasterText.hero(alden), "Alden, Gate Warden")
        XCTAssertEqual(MasterText.cosmetic(lyraRecall), "Starstring Recall I")
        XCTAssertEqual(MasterText.item(dagger), "Dawn Dagger 01")
        XCTAssertTrue(MasterText.description(id: dagger.itemID, ja: dagger.passiveText).hasPrefix("Unique Passive"))

        Loc.current = .ja
        XCTAssertEqual(MasterText.hero(alden), alden.displayNameJa)
        XCTAssertEqual(MasterText.item(dagger), dagger.nameJa)
    }

    // MARK: プライバシーマニフェスト

    func testPrivacyManifestIsBundledWithNoTrackingAndNoCollection() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                                "PrivacyInfo.xcprivacy がアプリバンドルに含まれていません")
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((plist["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        XCTAssertEqual((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)

        let apis = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let declared = apis.compactMap { entry -> (String, [String])? in
            guard let type = entry["NSPrivacyAccessedAPIType"] as? String,
                  let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] else { return nil }
            return (type, reasons)
        }
        XCTAssertEqual(declared.count, apis.count, "型や理由の欠けたエントリがあります")
        XCTAssertEqual(declared.first { $0.0 == "NSPrivacyAccessedAPICategoryUserDefaults" }?.1, ["CA92.1"])
        XCTAssertEqual(declared.first { $0.0 == "NSPrivacyAccessedAPICategoryFileTimestamp" }?.1, ["C617.1"])
    }

    // MARK: Info.plist・アセット

    func testInfoPlistMatchesAppStoreConfiguration() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let launch = try XCTUnwrap(info["UILaunchScreen"] as? [String: Any])
        XCTAssertEqual(launch["UIImageName"] as? String, "LaunchLogo")
        XCTAssertEqual(launch["UIColorName"] as? String, "LaunchBackground")
        XCTAssertEqual(info["UIUserInterfaceStyle"] as? String, "Dark")
        XCTAssertEqual(info["ITSAppUsesNonExemptEncryption"] as? Bool, false)
        XCTAssertEqual(info["NSHumanReadableCopyright"] as? String, "© 2026 VELSTRIA")
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "VELSTRIA")
        XCTAssertEqual(info["UIDeviceFamily"] as? [Int], [1], "iPhone 専用であること")

        let orientations = try XCTUnwrap(info["UISupportedInterfaceOrientations"] as? [String])
        XCTAssertFalse(orientations.isEmpty)
        XCTAssertTrue(orientations.allSatisfy { $0.hasPrefix("UIInterfaceOrientationLandscape") }, "横画面固定")

        let icons = (info["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any]
        XCTAssertEqual(icons?["CFBundleIconName"] as? String, "AppIcon")
    }

    func testIconAndLaunchAssetsAreCompiled() throws {
        XCTAssertNotNil(Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png"),
                        "AppIcon がアセットカタログからコンパイルされていません")
        let logo = try XCTUnwrap(UIImage(named: "LaunchLogo"), "LaunchLogo がありません")
        XCTAssertEqual(logo.size, CGSize(width: 240, height: 240))
        XCTAssertNotNil(UIColor(named: "LaunchBackground"))
        XCTAssertNotNil(UIColor(named: "AccentColor"))
    }
}
