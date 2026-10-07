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
}
