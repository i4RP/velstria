import RealityKit
import VelstriaCore
import XCTest
@testable import VELSTRIA

// Effekseer の同梱効果: 全ファイルが読めること、名前が規則どおりであること。
// 効果は tools/effekseer/ の DSL で作って Effects/Effekseer/ にコミットする（docs/EFFEKSEER.md）。

@MainActor
final class EffekseerTests: XCTestCase {
    private static let stages: Set<String> = [
        "atk_cast", "atk_cast2", "atk_travel", "atk_hit",
        "s1_cast", "s1_travel", "s1_telegraph", "s1_impact", "s1_hit",
        "s2_cast", "s2_travel", "s2_telegraph", "s2_impact", "s2_hit",
        "ult_cast", "ult_travel", "ult_telegraph", "ult_impact", "ult_hit",
        "passive_cast", "passive_hit",
    ]

    private func bundledFiles() throws -> [URL] {
        let dir = try XCTUnwrap(Bundle.main.url(forResource: EffekseerOverlay.bundleFolder, withExtension: nil), "同梱フォルダが無い")
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "efk" }
    }

    func testEveryBundledEffectLoads() throws {
        let runtime = try XCTUnwrap(EfkRuntime(), "Metal が使えない環境では確認できない")
        let files = try bundledFiles()
        XCTAssertFalse(files.isEmpty)
        for url in files {
            let name = url.deletingPathExtension().lastPathComponent
            XCTAssertTrue(runtime.loadEffectNamed(name, path: url.path, magnification: 1), "\(name): 読み込めない（テクスチャの相対パスなど）")
        }
        XCTAssertEqual(runtime.loadedCount, files.count)
    }

    func testHeroEffectNamesFollowTheStageConvention() throws {
        let master = MasterData.shared
        for url in try bundledFiles() {
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("H"), name.dropFirst().prefix(3).allSatisfy(\.isNumber) else { continue }   // Zt_* などの試作は対象外
            let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
            XCTAssertEqual(parts.count, 2, name)
            XCTAssertNotNil(master.hero(parts[0]), "\(name): 存在しないヒーロー")
            XCTAssertTrue(Self.stages.contains(parts[1]), "\(name): 段の名前が規則に無い")
        }
    }

    func testPlayingAndRenderingDoesNotCrash() throws {
        let overlay = try XCTUnwrap(EffekseerOverlay(), "Metal が使えない環境では確認できない")
        overlay.loadBundledEffects()
        let camera = Entity()
        camera.position = [0, 20, 14]
        camera.look(at: .zero, from: camera.position, relativeTo: nil)
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        overlay.attach(to: host)
        for name in overlay.effectNames.sorted().prefix(40) {
            let h = overlay.play(name, at: [0, 0, 0], yaw: 0.4)
            XCTAssertGreaterThanOrEqual(h, 0, name)
        }
        for _ in 0..<5 { overlay.render(camera: camera, host: host, dt: 1.0 / 30) }
        overlay.runtime.stopAll()
        overlay.render(camera: camera, host: host, dt: 1.0 / 30)
    }

    /// 効果を持つ全ヒーロー（22 体・278 本）の効果を読む時間（実際の戦闘は出場 10 人分だけを幕の裏で 1 回）。
    /// シミュレータ（Debug）で数秒に収まること。ヒーローを足すたびに上限を触らなくて済むよう、1 効果あたり 0.03 秒（従来の 4 秒 / 150 効果）で見積もる。
    func testLoadingEveryHeroEffectIsFast() throws {
        let overlay = try XCTUnwrap(EffekseerOverlay(), "Metal が使えない環境では確認できない")
        let start = CFAbsoluteTimeGetCurrent()
        overlay.loadBundledEffects()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print("effekseer load all: \(overlay.effectNames.count) effects in \(Int(elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, max(4.0, Double(overlay.effectNames.count) * 0.03))
    }

    // MARK: 演出の役割分担（キットのヒーローのスキルは SkillFX）

    /// 効果名 → ヒーロー ID。試作（Zt_*）やヒーロー以外の名前は対象外。
    func testRoutingParsesHeroIDsFromEffectNames() {
        XCTAssertEqual(EffekseerRouting.heroID(ofEffect: "H027_s1_cast"), "H027")
        XCTAssertEqual(EffekseerRouting.heroID(ofEffect: "H003_atk_hit"), "H003")
        XCTAssertNil(EffekseerRouting.heroID(ofEffect: "Zt_flash"))
        XCTAssertNil(EffekseerRouting.heroID(ofEffect: "H027"))
        XCTAssertNil(EffekseerRouting.heroID(ofEffect: ""))
    }

    /// 効果を持つヒーローは通常攻撃を Effekseer が出す。スキルは、オプトアウト（キット）のヒーローでは SkillFX に任せる。
    func testRoutingLeavesSkillsOfOptedOutHeroesToSkillFX() {
        let names = ["H027_atk_cast", "H027_s1_cast", "H027_ult_impact", "H003_atk_cast", "H003_s1_cast", "Zt_flash"]
        let r = EffekseerRouting.make(effectNames: names, skillOptOut: { $0 == "H027" })
        XCTAssertEqual(r.heroes, ["H027", "H003"])
        XCTAssertEqual(r.skillOptOut, ["H027"])
        XCTAssertTrue(r.handlesAttack("H027"), "通常攻撃は Effekseer のまま")
        XCTAssertFalse(r.handlesSkill("H027"), "キットのスキルは SkillFX")
        XCTAssertTrue(r.handlesAttack("H003"))
        XCTAssertTrue(r.handlesSkill("H003"), "キットの無いヒーローは従来どおり全部 Effekseer")
        XCTAssertFalse(r.handlesAttack("H001"))
        XCTAssertFalse(r.handlesSkill("H001"))
        XCTAssertFalse(r.handlesAttack(nil))
        XCTAssertFalse(r.handlesSkill(nil))
        // オプトアウトが無ければ従来と同じ（効果を持つヒーローは全部 Effekseer）
        let plain = EffekseerRouting.make(effectNames: names, skillOptOut: { _ in false })
        XCTAssertTrue(plain.handlesSkill("H027"))
        XCTAssertEqual(plain.skillOptOut, [])
    }

    /// 同梱の効果 × 実際のキット: キットのヒーローは通常攻撃だけ Effekseer、それ以外のヒーローは全部 Effekseer。
    func testRoutingWithBundledEffectsAndRealKits() throws {
        let names = try bundledFiles().map { $0.deletingPathExtension().lastPathComponent }
        let r = EffekseerRouting.make(effectNames: names, skillOptOut: { HeroKits.hasKit($0) })
        for hero in r.heroes {
            if HeroKits.hasKit(hero) {
                XCTAssertTrue(r.handlesAttack(hero), hero)
                XCTAssertFalse(r.handlesSkill(hero), "\(hero): キットのスキルは SkillFX")
                XCTAssertTrue(names.contains("\(hero)_atk_cast"), "\(hero): 通常攻撃の効果は残っている")
            } else {
                XCTAssertTrue(r.handlesSkill(hero), "\(hero): キットの無いヒーローは従来どおり")
            }
        }
        XCTAssertEqual(r.skillOptOut, r.heroes.filter { HeroKits.hasKit($0) })
    }

    /// 追加ヒーロー（第 1 段階 H025〜H029・第 2 段階 H030〜H034）の効果が、役割ごとの段の組をそろえていること。
    /// 遠隔レンジャー（H003 と同じ 14 本）・遠隔アルカニスト（H016 と同じ 14 本）・近接（12 本）。
    /// 第 1 段階は 14 + 14 + 12 × 3 = 64 本、第 2 段階も同じ構成で 64 本（計 128 本）。
    func testAddedHeroesHaveTheirFullStageSets() throws {
        let melee = ["atk_cast", "atk_cast2", "atk_hit", "s1_cast", "s1_impact", "s1_hit", "s2_cast", "s2_impact", "s2_hit", "ult_cast", "ult_impact", "ult_hit"]
        let ranger = ["atk_cast", "atk_travel", "atk_hit", "s1_cast", "s1_travel", "s1_impact", "s1_hit", "s2_cast", "s2_impact", "s2_hit",
                      "ult_cast", "ult_travel", "ult_impact", "ult_hit"]
        let arcanist = ["atk_cast", "atk_travel", "atk_hit", "s1_cast", "s1_travel", "s1_impact", "s1_hit", "s2_cast", "s2_impact", "s2_hit",
                        "ult_cast", "ult_telegraph", "ult_impact", "ult_hit"]
        let expected: [String: [String]] = [
            "H025": ranger, "H026": arcanist, "H027": melee, "H028": melee, "H029": melee,
            "H030": ranger, "H031": arcanist, "H032": melee, "H033": melee, "H034": melee,
        ]
        let files = try bundledFiles()
        let names = Set(files.map { $0.deletingPathExtension().lastPathComponent })
        for (hero, stages) in expected.sorted(by: { $0.key < $1.key }) {
            for stage in stages {
                XCTAssertTrue(names.contains("\(hero)_\(stage)"), "\(hero)_\(stage) が無い")
            }
            XCTAssertEqual(names.filter { $0.hasPrefix(hero + "_") }.count, stages.count, "\(hero): 想定外の効果が混ざっている")
        }
    }
}
