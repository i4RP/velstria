import RealityKit
import VelstriaCore
import XCTest
@testable import VELSTRIA

// キットのヒーローの段に重ねる Effekseer の効果（FXElement.efk / FXEfk。Effects/Effekseer/Kit/）。
// 効果は試合のヒーローの分だけ読み込み幕の裏で読み、SkillFXPlayer の予定表（遅れ・画質・上限）で発火して EffekseerDirector が再生する。

@MainActor
final class EffekseerKitStackTests: XCTestCase {
    private var master: MasterData { MasterData.shared }

    private func kitFiles() throws -> [URL] {
        let dir = try XCTUnwrap(Bundle.main.url(forResource: EffekseerOverlay.bundleFolder, withExtension: nil), "同梱フォルダが無い")
        let kit = dir.appendingPathComponent(EffekseerOverlay.kitFolder)
        return ((try? FileManager.default.contentsOfDirectory(at: kit, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "efk" }
    }

    /// 全レシピが重ねる効果の名前（ヒーロー ID → 名前）。
    private func referencedNames() -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for hero in master.allHeroes.map(\.heroID) {
            for slot in SkillSlot.allCases {
                var cues = SkillFXCatalog.recipe(heroID: hero, slot: slot, master: master).all
                for stage in 1...SkillFXCatalog.maxStage {
                    cues += SkillFXCatalog.stageRecipe(heroID: hero, slot: slot, stage: stage, master: master)?.all ?? []
                }
                cues += SkillFXCatalog.passiveRelease(heroID: hero, released: 10, master: master) ?? []
                for cue in cues {
                    if case .efk(let x) = cue.element { out[hero, default: []].insert(x.name) }
                }
            }
        }
        return out
    }

    /// 同梱の重ねる効果は全部読める（テクスチャは ../Texture/）。名前は <ヒーロー ID>_ で始まり、ヒーローが存在する。
    func testEveryKitEffectLoadsAndIsNamedAfterAHero() throws {
        let runtime = try XCTUnwrap(EfkRuntime(), "Metal が使えない環境では確認できない")
        for url in try kitFiles() {
            let name = url.deletingPathExtension().lastPathComponent
            XCTAssertNotNil(master.hero(String(name.prefix(4))), "\(name): 存在しないヒーロー")
            XCTAssertEqual(name.dropFirst(4).first, "_", name)
            XCTAssertTrue(runtime.loadEffectNamed(EffekseerOverlay.kitKey(name), path: url.path, magnification: 1),
                          "\(name): 読み込めない（テクスチャの相対パスなど）")
        }
    }

    /// レシピが重ねる効果は全部同梱されている（足りないと実機で黙って出ない）。
    func testEveryReferencedKitEffectIsBundled() throws {
        let bundled = Set(try kitFiles().map { $0.deletingPathExtension().lastPathComponent })
        for (hero, names) in referencedNames() {
            for n in names { XCTAssertTrue(bundled.contains(n), "\(hero): \(n).efk が Effects/Effekseer/Kit に無い") }
        }
    }

    /// 試合に出るヒーローの重ねる効果だけを読む（段の効果の名前の規則・数は変えない）。
    func testOnlyHeroesInTheMatchAreLoaded() throws {
        let files = try kitFiles()
        guard let first = files.first else { throw XCTSkip("重ねる効果がまだ無い") }
        let hero = String(first.deletingPathExtension().lastPathComponent.prefix(4))
        let overlay = try XCTUnwrap(EffekseerOverlay(), "Metal が使えない環境では確認できない")
        overlay.loadBundledEffects(heroes: [hero])
        XCTAssertFalse(overlay.kitEffectNames.isEmpty)
        XCTAssertTrue(overlay.kitEffectNames.allSatisfy { $0.hasPrefix(hero + "_") })
        XCTAssertTrue(overlay.effectNames.allSatisfy { !$0.hasPrefix(EffekseerOverlay.kitFolder) }, "段の効果の名前に混ざらない")
        for n in overlay.kitEffectNames { XCTAssertTrue(overlay.runtime.hasEffectNamed(EffekseerOverlay.kitKey(n)), n) }
    }

    /// 重ねる効果の合図は他の合図と同じ予定表で発火する（遅れ・位置・追従の主体）。準備で名前を集める。
    func testEfkCueFiresOnTheScheduleWithTheCuePosition() {
        let player = SkillFXPlayer(quality: .preset(.high))
        var r = SkillFXRecipe()
        r.impact = [.efk("H034_test", at: 0.2, .follow, offset: [0, 1, 0.5], scale: 1.2, onTop: true)]
        player.prewarm(recipes: [(FX_H034.palette, r)])
        XCTAssertEqual(player.efk.names, ["H034_test"])
        var got: [(FXEfk, SIMD3<Float>, SkillFXPlayer.Follow?)] = []
        player.efk.sink = { x, p, _, follow, _ in got.append((x, p, follow)) }
        player.resolve = { _ in [10, 0, 5] }
        let ctx = SkillFXPlayer.Context(palette: FX_H034.palette, origin: [10, 0, 5], caster: [10, 0, 5], target: [10, 0, 0],
                                        forward: [0, 0, -1], follow: .unit(7))
        player.play(r.impact, ctx)
        player.update(dt: 0.1)
        XCTAssertTrue(got.isEmpty, "0.2 秒の遅れの前には出ない")
        player.update(dt: 0.15)
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got.first?.0.scale ?? 0, 1.2, accuracy: 1e-5)
        XCTAssertEqual(got.first?.0.onTop, true)
        XCTAssertEqual(got.first?.2, .unit(7))
        // 前 = -Z なので、前へ 0.5 m・上へ 1 m
        let p = got.first?.1 ?? .zero
        XCTAssertEqual(p.x, 10, accuracy: 1e-4)
        XCTAssertEqual(p.y, 1, accuracy: 1e-4)
        XCTAssertEqual(p.z, 4.5, accuracy: 1e-4)
    }
}
