import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 中立モンスターの動く生成モデル（tools/structures/creature_bake.py → Creature_<id>.usdz / .json）:
/// 全種類が読めて、待機・歩行・攻撃・被弾の区間が取れ、複製に動作を流せること。
@MainActor
final class CreatureAssetsTests: XCTestCase {
    override func tearDown() async throws {
        StructureAssets.resetForTesting()
        try await super.tearDown()
    }

    func testAllCreaturesLoadWithClips() async throws {
        await StructureAssets.load()
        for kind in CreatureAssets.Kind.allCases {
            let mk: MonsterKind = switch kind {
            case .turtle: .astralWyrm
            case .lord: .ancientColossus
            case .red: .redSentinel
            case .purple: .blueSentinel
            case .whelp: .azureWhelp
            case .wanderer: .mossWanderer
            case .golem: .magmaGolem
            case .beetle: .emberBeetle
            case .grub: .emberGrub
            case .crab: .treasureCrab
            case .crablet: .crablet
            case .lizard: .hornLizard
            }
            let m = try XCTUnwrap(CreatureAssets.model(mk), "\(kind.fileName) が読めない")
            for clip in CreatureAssets.Clip.allCases {
                XCTAssertNotNil(m.clips[clip], "\(kind) \(clip)")
                XCTAssertGreaterThan(m.durations[clip] ?? 0, 0.1, "\(kind) \(clip)")
            }
            let inst = m.makeInstance()
            let anim = CreatureAnimator(model: m, target: inst.animTarget)
            anim.update(dt: 0.016, moving: false, visible: true)
            anim.trigger(.attack)
            anim.update(dt: 0.016, moving: true, visible: true)
            let b = inst.root.visualBounds(relativeTo: nil)
            XCTAssertGreaterThan(b.extents.y, 0.5, "\(kind) 高さ")
            XCTAssertLessThan(b.extents.y, 5.5, "\(kind) 高さ")
        }
    }
}
