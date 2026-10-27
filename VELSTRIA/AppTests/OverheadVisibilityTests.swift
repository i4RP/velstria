import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

@MainActor
final class OverheadVisibilityTests: XCTestCase {
    private func frame() throws -> RenderFrame {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 17))
        var unit = try XCTUnwrap(sim.state.units.first { $0.kind == .hero })
        unit.team = .red
        unit.pos = Vec2(500, 1200)
        unit.prevPos = unit.pos
        unit.visibleMask = Team.blue.visionBit | Team.red.visionBit
        var state = sim.state
        state.units = [unit]
        var frame = RenderFrame(state: state, alpha: 1, dt: 1 / 60, time: 0, viewerTeam: .blue,
                                humanID: nil, focusID: nil, ended: false, winner: nil)
        frame.camera = SIMD3(5, 1.5, -5)
        frame.firstPersonID = unit.id + 1000
        frame.overheadProjection = CombatTextProjection(position: frame.camera,
            orientation: simd_quatf(angle: 0, axis: [0, 1, 0]), viewport: CGSize(width: 874, height: 402),
            verticalFOV: CameraRig.firstPersonFOV, near: CameraRig.firstPersonNear)
        return frame
    }

    private func bar() -> OverheadBar {
        OverheadBar(style: .hero(isSelf: false, showResource: false), fillColor: TeamColors.selfColor,
                    materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary(), text: TextMeshCache())
    }

    func testOnlyNearbyOnscreenVisibleMeshesHavePanels() throws {
        var f = try frame()
        let b = bar()
        func check(_ expected: Bool, _ reason: String, meshVisible: Bool = true) {
            b.updateVisibility(f, index: 0, bodyHeight: 2, meshVisible: meshVisible)
            XCTAssertEqual(b.root.isEnabled, expected, reason)
        }
        check(true, "見えている近くの敵")
        f.state.units[0].team = .blue
        check(true, "近くの味方も同じ条件")
        check(false, "メッシュが非表示ならゲージも消す", meshVisible: false)
        f.state.units[0].team = .red
        f.state.units[0].visibleMask = Team.red.visionBit
        check(false, "霧・草むら・未看破ステルスは即時非表示")
        f.state.units[0].visibleMask |= Team.blue.visionBit
        f.state.units[0].pos = Vec2(500, 2400)
        check(false, "18mより遠いキャラ")
        f.state.units[0].pos = Vec2(500, 100)
        check(false, "背後のキャラ")
        f.state.units[0].pos = Vec2(1800, 600)
        check(false, "近距離でも画面外")
        f.state.units[0].pos = Vec2(500, 1200)
        f.state.units[0].isAlive = false
        check(false, "死亡中")
    }

    func testWallOcclusionDisappearsWhenTargetWalksIntoView() throws {
        var f = try frame()
        var map = MapDefinition.brawl
        map.size = 2000
        map.obstacles = [.rect(Rect2(minX: 450, minY: 800, maxX: 550, maxY: 900))]
        f.overheadNavigation = NavGrid(map: map)
        let b = bar()
        b.updateVisibility(f, index: 0, bodyHeight: 2, meshVisible: true)
        XCTAssertFalse(b.root.isEnabled, "チーム視界に入っていても壁の向こうなら非表示")
        f.state.units[0].pos = Vec2(900, 1200)
        f.state.tick += Balance.visionUpdateEveryTicks
        b.updateVisibility(f, index: 0, bodyHeight: 2, meshVisible: true)
        XCTAssertTrue(b.root.isEnabled, "壁の横へ出たら既存パネルを再表示")
        f.state.units[0].pos = Vec2(500, 1200)
        f.dt = 0
        b.updateVisibility(f, index: 0, bodyHeight: 2, meshVisible: true)
        XCTAssertFalse(b.root.isEnabled, "停止・シークでも古い遮蔽結果を残さない")
    }

    func testHealthAndLevelMaterialsRespectSceneDepth() {
        let b = bar()
        b.update(hp: 0.6, shield: 0.1, resource: nil, level: 12, dt: 0)
        XCTAssertEqual(b.displayedLevel, 12)
        XCTAssertEqual(b.displayedHP, 0.6, accuracy: 1e-5)
        for child in b.root.children {
            for material in child.components[ModelComponent.self]?.materials ?? [] {
                guard let unlit = material as? UnlitMaterial else { continue }
                XCTAssertTrue(unlit.readsDepth, "地形越しに文字やゲージを描かない")
                XCTAssertFalse(unlit.writesDepth, "同じパネル内の HP とレベルを深度で消さない")
            }
        }
    }
}
