import UIKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

// 担当: appstore-assets。
// App Store 提出物（英語オーバーレイ・プライバシーマニフェスト・アイコン・起動画面・Info.plist）が
// ビルド済みアプリに正しく入っていることを検査する。英語オーバーレイの生成元は tools/gen_master_en.py。

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
        for i in m.items where GearCatalog.english[i.itemID] == nil {  // 靴は GearCatalog が英語を持つ
            need(i.itemID); need(i.itemID + ".desc"); need(i.itemID + ".passive")
        }
        for s in m.spells { need(s.spellID); need(s.spellID + ".desc") }
        for r in m.runes { need(r.runeID); need(r.runeID + ".desc") }
        for c in m.cosmetics { need(c.cosmeticID) }
        for s in m.store { need(s.sku) }
        for e in m.effects { need(e.effectID) }
        XCTAssertEqual(missing, [], "未翻訳のキーがあります（python3 tools/gen_master_en.py で再生成）")

        XCTAssertEqual(m.heroes.count, 34)
        XCTAssertEqual(m.skills.count, 136)
        XCTAssertEqual(m.items.count, 72 + GearCatalog.items.count)  // 正本 72 + 靴
        XCTAssertEqual(m.spells.count, 15)
        XCTAssertEqual(m.runes.count, 30)
        XCTAssertEqual(m.cosmetics.count, 102)
        XCTAssertEqual(m.store.count, 154)
    }

    func testEnglishOverlayContainsNoJapaneseText() throws {
        let japanese = try NSRegularExpression(pattern: "[\\u3040-\\u30ff\\u3400-\\u9fff\\uff00-\\uffef]")
        let offenders = overlay.keys.sorted().filter { key in
            let v = overlay[key] ?? ""
            return japanese.firstMatch(in: v, range: NSRange(v.startIndex..., in: v)) != nil
        }
        XCTAssertEqual(offenders, [])
    }

    /// スキル説明が DESIGN §6 のアーキタイプ数値と一致すること（代表値の抜き取り）。
    func testSkillDescriptionsFollowDesignArchetypes() throws {
        let m = MasterData.shared
        for s in m.skills {
            let desc = try XCTUnwrap(overlay[s.skillID + ".desc"])
            let hero = try XCTUnwrap(m.heroes.first { $0.heroID == s.heroID })
            // キットのヒーローの説明は HeroKits.text（SkillMath.description）が持つ。汎用文（.desc）は存在チェックのみ
            if HeroKits.hasKit(hero.heroID) { continue }
            switch s.slot {
            case .skill2 where hero.isRanged:
                // 遠隔: 350 のブリンク + 次の通常攻撃にスキル基礎値の 50%
                XCTAssertTrue(desc.contains("350 units") && desc.contains("50% of \(Int(s.baseDamage))"), "\(s.skillID): \(desc)")
            case .skill2:
                // 近接: range + 100 の突進
                XCTAssertTrue(desc.contains("\(Int(s.range) + 100) units"), "\(s.skillID): \(desc)")
            case .ultimate where hero.role == .vanguard:
                XCTAssertTrue(desc.contains("\(Int(s.range) + 200) units"), "\(s.skillID): \(desc)")
            default:
                break
            }
        }
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
        XCTAssertEqual(MasterText.item(dagger), "Dawn Dagger")
        let gale = try XCTUnwrap(m.items.first { $0.itemID == "EQ019" })
        XCTAssertTrue(MasterText.description(id: gale.itemID, ja: gale.passiveText).hasPrefix("Unique Passive"))

        Loc.current = .ja
        XCTAssertEqual(MasterText.hero(alden), alden.displayNameJa)
        XCTAssertEqual(MasterText.item(dagger), dagger.nameJa)
        XCTAssertEqual(MasterText.cosmetic(lyraRecall), "星弦の帰還 I")
    }

    // MARK: 日本語オーバーレイ（マスターの開発用仮名の置き換え）

    /// 日本語表示のコスメ・ストア商品・スキル名に開発用の仮名（「〜 HeroSkin 1」「Alden式・一閃」「星環シフト2」）が残らない。
    func testJapaneseNamesHaveNoPlaceholderTokens() throws {
        XCTAssertNotNil(Bundle.main.url(forResource: "master_ja", withExtension: "json"),
                        "master_ja.json がアプリバンドルに含まれていません（python3 tools/gen_master_ja.py）")
        let saved = Loc.current
        defer { Loc.current = saved }
        Loc.current = .ja
        let m = MasterData.shared
        // ローマ数字の連番（I/II/III）以外のラテン文字、末尾の数字は仮名の残り
        let latin = try NSRegularExpression(pattern: "[A-Za-z]{2,}")
        func offending(_ name: String) -> Bool {
            let stripped = name.replacingOccurrences(of: " [IVX]+$", with: "", options: .regularExpression)
            return latin.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) != nil
                || stripped.last?.isNumber == true
        }
        let cosmetics = m.cosmetics.map { MasterText.cosmetic($0) }
        XCTAssertEqual(cosmetics.filter(offending), [])
        XCTAssertEqual(Set(cosmetics).count, cosmetics.count, "コスメ名が重複しています")
        XCTAssertEqual(m.store.filter { $0.type == .cosmetic }.map { MasterText.storeItem($0) }.filter(offending), [])
        XCTAssertEqual(m.skills.map { MasterText.skill($0) }.filter(offending), [])
        let aldenSkill1 = try XCTUnwrap(m.skill(hero: "H001", slot: .skill1))
        XCTAssertEqual(MasterText.skill(aldenSkill1), "アルデン式・一閃")
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
        // 効果音・触覚の再生間隔に ProcessInfo.systemUptime を使う（app-services）
        XCTAssertEqual(declared.first { $0.0 == "NSPrivacyAccessedAPICategorySystemBootTime" }?.1, ["35F9.1"])
        let types = declared.map(\.0)
        XCTAssertEqual(Set(types).count, types.count, "同じカテゴリが重複して宣言されています")
    }

    /// StoreKit 構成ファイルは Xcode 上のローカル課金テスト専用で、出荷バンドルに含めない。
    func testStoreKitConfigurationIsNotShipped() {
        XCTAssertNil(Bundle.main.url(forResource: "Velstria", withExtension: "storekit"),
                     "Velstria.storekit がアプリバンドルに含まれています（project.yml で buildPhase: none にする）")
    }

    // MARK: Info.plist・アセット

    func testInfoPlistMatchesAppStoreConfiguration() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let launch = try XCTUnwrap(info["UILaunchScreen"] as? [String: Any])
        XCTAssertEqual(launch["UIImageName"] as? String, "LaunchLogo")
        XCTAssertEqual(launch["UIColorName"] as? String, "LaunchBackground")
        XCTAssertEqual(info["UIUserInterfaceStyle"] as? String, "Dark")
        XCTAssertEqual(info["ITSAppUsesNonExemptEncryption"] as? Bool, false)
        XCTAssertEqual(info["NSHumanReadableCopyright"] as? String, "© 2026 VELSIA")
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "VELSIA")
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
        XCTAssertNotNil(UIImage(named: "BrandLogo"), "VELSIA マスターロゴがありません")
        XCTAssertNotNil(UIImage(named: "BrandMark"), "VELSIA シルエットロゴがありません")
        let loadingArt = try XCTUnwrap(UIImage(named: "LoadingKeyArt"), "起動・ロード用キービジュアルがありません")
        XCTAssertGreaterThan(loadingArt.size.width, loadingArt.size.height, "キービジュアルは横画面用であること")
        XCTAssertNotNil(UIColor(named: "LaunchBackground"))
        XCTAssertNotNil(UIColor(named: "AccentColor"))
    }

    /// 全ヒーロー・全ヒーロースキンに描き下ろしポートレートがあること（tools/portraits/portraits.py install）。
    @MainActor
    func testEveryHeroAndSkinHasPortraitArt() {
        let m = MasterData.shared
        var missing: [String] = []
        // 追加ヒーロー第 1・第 2 段階（docs/NEW_HEROES.md）。立ち絵は未生成で、頭文字の暫定表示になる。
        // tools/portraits/portraits.py で生成・取り込みしたらこの一覧から外す（外し忘れても下の確認で気づける）。
        let artPending: Set<String> = ["H025", "H026", "H027", "H028", "H029", "H030", "H031", "H032", "H033", "H034"]
        for h in m.heroes {
            guard let img = PortraitArt.hero(h.heroID) else {
                if !artPending.contains(h.heroID) { missing.append(h.heroID) }
                continue
            }
            XCTAssertFalse(artPending.contains(h.heroID), "\(h.heroID) の立ち絵を取り込んだので artPending から外してください")
            XCTAssertEqual(img.size.width, img.size.height, "\(h.heroID) のポートレートが正方形ではありません")
            XCTAssertGreaterThanOrEqual(img.size.width * img.scale, 512, "\(h.heroID) のポートレートの解像度が不足")
        }
        for c in m.cosmetics where c.type == .heroSkin {
            guard let img = PortraitArt.skin(c.cosmeticID) else { missing.append(c.cosmeticID); continue }
            XCTAssertEqual(img.size.width, img.size.height, "\(c.cosmeticID) のポートレートが正方形ではありません")
        }
        XCTAssertEqual(missing, [], "ポートレート画像がありません（tools/portraits/ で生成・取り込み）")
        XCTAssertNil(PortraitArt.hero("H999"), "未知の ID は頭文字の暫定表示にフォールバックする")
    }

    /// 全装備に固有の描き下ろしアイコンがあること（tools/portraits/portraits.py install items）。
    @MainActor
    func testEveryItemHasIconArt() {
        var missing: [String] = []
        for it in MasterData.shared.items where GearCatalog.english[it.itemID] == nil {  // 靴のアイコンは未作成（手続き生成で表示）
            guard let img = PortraitArt.item(it.itemID) else { missing.append(it.itemID); continue }
            XCTAssertEqual(img.size.width, img.size.height, "\(it.itemID) のアイコンが正方形ではありません")
            // 最大表示 70pt × 3x = 210px
            XCTAssertGreaterThanOrEqual(img.size.width * img.scale, 256, "\(it.itemID) のアイコンの解像度が不足")
        }
        XCTAssertEqual(missing, [], "装備アイコンがありません（tools/portraits/ で生成・取り込み）")
        XCTAssertNil(PortraitArt.item("EQ999"), "未知の ID は手続き生成の暫定表示にフォールバックする")
    }
}
