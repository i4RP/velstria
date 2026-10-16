import ImageIO
import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// タワー・Core・ミニオンの生成 3D モデル（tools/structures/ → App/Resources/Structures/）: 予算（三角形・テクスチャ）・寸法・
/// チーム別の材質、構造物とミニオンの見た目が使うこと、読めない・無効なら従来の手続きメッシュへ戻ること。
@MainActor
final class StructureAssetsTests: XCTestCase {
    override func tearDown() async throws {
        StructureAssets.resetForTesting()
        try await super.tearDown()
    }

    private func frame(_ s: SimState) -> RenderFrame {
        RenderFrame(state: s, alpha: 1, dt: 1.0 / 60, time: 0, viewerTeam: nil, humanID: nil, focusID: nil,
                    ended: false, winner: nil)
    }

    private func layer() -> UnitLayer {
        UnitLayer(materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary(), text: TextMeshCache(), master: .shared)
    }

    func testBundledModelsFitBudgetsAndSizes() async throws {
        XCTAssertTrue(StructureAssets.isBundled)
        await StructureAssets.load()
        for kind in StructureAssets.Kind.allCases {
            let m = try XCTUnwrap(StructureAssets.model(kind), "\(kind.fileName) が読めない")
            XCTAssertGreaterThan(m.triangleCount, 100, "\(kind)")
            XCTAssertLessThanOrEqual(m.triangleCount, kind.triangleBudget, "\(kind)")
            let red = try XCTUnwrap(m.red as? PhysicallyBasedMaterial)
            let blue = try XCTUnwrap(m.blue as? PhysicallyBasedMaterial)
            XCTAssertNotNil(blue.baseColor.texture, "\(kind)")
            XCTAssertNotNil(blue.emissiveColor.texture, "\(kind) 発光")
            XCTAssertFalse(red.baseColor.texture?.resource === blue.baseColor.texture?.resource, "\(kind) 赤はテクスチャを差し替える")
            let size = m.bounds.extents
            switch kind {
            case .tower:
                XCTAssertEqual(size.y, 4.35, accuracy: 0.05)
                XCTAssertEqual(m.bounds.min.y, 0, accuracy: 0.01, "足元が地面")
                XCTAssertLessThan(max(size.x, size.z), 3.6, "従来の台座（直径 3.1 m）程度")
            case .coreBase:
                XCTAssertEqual(max(size.x, size.z), 6.8, accuracy: 0.05)
                XCTAssertEqual(m.bounds.min.y, 0, accuracy: 0.01)
            case .towerOrb, .coreCrystal:
                XCTAssertEqual(m.bounds.center.y, 0, accuracy: 0.02, "浮遊する物は中心が原点")
            case .minionMelee, .minionRanged, .minionSiege:
                XCTAssertEqual(m.bounds.min.y, 0, accuracy: 0.01)
                XCTAssertLessThan(size.y, 1.3, "HP バー（頭上 1.5 m〜）より低い")
                XCTAssertLessThan(max(size.x, size.z), 1.4)
            case .monsterTurtle, .monsterLord:
                XCTAssertEqual(m.bounds.min.y, 0, accuracy: 0.01)
                XCTAssertLessThan(size.y, 5.0, "HP バー（頭上）より低い")
            }
        }
    }

    /// 赤チームのテクスチャは 1024 px 以下（ミニオンは 512 px 以下）。
    func testRedTexturesStayWithinSizeLimits() throws {
        for kind in StructureAssets.Kind.allCases {
            for suffix in ["_red", "_red_emit"] {
                let url = try XCTUnwrap(StructureAssets.resolver(kind.fileName + suffix, "jpg"), "\(kind.fileName)\(suffix).jpg")
                let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
                let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
                let w = props[kCGImagePropertyPixelWidth] as? Int ?? .max
                let limit = kind.rawValue.hasPrefix("minion") ? 512 : 1024
                XCTAssertLessThanOrEqual(w, limit, "\(kind)\(suffix)")
            }
        }
    }

    func testStructuresAndMinionsUseGeneratedModels() async throws {
        await StructureAssets.load()
        let sim = Simulation(config: MatchFactory.botMatch(seed: 21))
        sim.runHeadless(maxTime: 30)
        let l = layer()
        l.sync(frame(sim.state))
        let tower = try XCTUnwrap(sim.state.units.first { $0.kind == .tower })
        let core = try XCTUnwrap(sim.state.units.first { $0.kind == .core })
        let tv = try XCTUnwrap(l.structure(tower.id))
        let cv = try XCTUnwrap(l.structure(core.id))
        if let rig = StructureAssets.rig(.tower(tower.tower?.tier ?? .outer)) {
            // 複数部品の塔（同梱されていれば）: 部品の数、発射点は結晶
            XCTAssertEqual(tv.generatedParts, rig.kind.parts.count)
            XCTAssertEqual(tv.muzzleHeight, tv.floatBaseY)
        } else {
            XCTAssertEqual(tv.generatedParts, 2, "塔の本体と結晶球")
            // 球は爪の中（本体の上端の少し下）
            XCTAssertEqual(tv.floatBaseY, 4.15, accuracy: 0.05)
        }
        if let rig = StructureAssets.rig(.starCore) {
            XCTAssertEqual(cv.generatedParts, rig.kind.parts.count)
        } else {
            XCTAssertEqual(cv.generatedParts, 2, "Core の台座と大結晶")
            XCTAssertGreaterThanOrEqual(cv.floatBaseY, 3.6)
        }
        // HP バーは結晶の上
        XCTAssertGreaterThan(tv.bar.root.position.y, tv.floatBaseY + 0.6)
        let minion = try XCTUnwrap(sim.state.units.first { $0.kind == .minion && $0.isAlive })
        XCTAssertEqual(l.creature(minion.id)?.isGenerated, true)

        // 破壊・復帰は従来どおり
        var destroyed = sim.state
        let ti = try XCTUnwrap(destroyed.index(of: tower.id))
        destroyed.units[ti].hp = 0
        destroyed.units[ti].isAlive = false
        l.sync(frame(destroyed))
        XCTAssertTrue(tv.destroyed)
        XCTAssertTrue(tv.isCollapsing)
        l.resetForPresentationEpoch()
        l.sync(frame(sim.state))
        XCTAssertFalse(tv.destroyed)
    }

    /// 無効（または読み込み前・失敗）なら手続きメッシュ。
    func testFallsBackToProceduralMeshes() throws {
        StructureAssets.isEnabled = false
        let sim = Simulation(config: MatchFactory.botMatch(seed: 22))
        sim.runHeadless(maxTime: 30)
        let l = layer()
        l.sync(frame(sim.state))
        let tower = try XCTUnwrap(sim.state.units.first { $0.kind == .tower })
        let tv = try XCTUnwrap(l.structure(tower.id))
        XCTAssertEqual(tv.generatedParts, 0)
        XCTAssertEqual(tv.floatBaseY, 4.95)
        XCTAssertEqual(tv.bar.root.position.y, 6.4, accuracy: 0.001)
        XCTAssertEqual(tv.muzzleHeight, 4.5)
        let minion = try XCTUnwrap(sim.state.units.first { $0.kind == .minion && $0.isAlive })
        XCTAssertEqual(l.creature(minion.id)?.isGenerated, false)
    }

    /// 複数部品の塔（Struct_tower_outer / _inner / _base / Struct_star_core）: 同梱されている種類は全て読めて、
    /// 部品が揃い、三角形（塔は本体 6k・結晶 2.5k、Star Core は合計 8.5k）と赤のテクスチャ（1024 px）の予算に収まる。同梱が無ければ従来のモデル。
    func testBundledRigsFitBudgets() async throws {
        await StructureAssets.load()
        for kind in StructureAssets.RigKind.allCases {
            guard StructureAssets.resolver(kind.fileName, "usdz") != nil else {
                XCTAssertNil(StructureAssets.rig(kind), "\(kind.fileName) が無ければ従来のモデル")
                continue
            }
            let rig = try XCTUnwrap(StructureAssets.rig(kind), "\(kind.fileName) が読めない（部品・予算・材質）")
            XCTAssertEqual(Set(rig.parts.keys), Set(kind.parts))
            XCTAssertTrue(kind.fitsBudget(body: rig.bodyTriangles, crystal: rig.crystalTriangles),
                          "\(kind) 本体 \(rig.bodyTriangles) / 結晶 \(rig.crystalTriangles)")
            XCTAssertLessThanOrEqual(rig.crystalTriangles, StructureAssets.RigKind.crystalTriangleBudget, "\(kind)")
            if kind.isCore {
                XCTAssertLessThanOrEqual(rig.bodyTriangles + rig.crystalTriangles, StructureAssets.RigKind.coreTriangleBudget)
            } else {
                XCTAssertLessThanOrEqual(rig.bodyTriangles, StructureAssets.RigKind.bodyTriangleBudget, "\(kind)")
            }
            let g = try XCTUnwrap(rig.geometry)
            XCTAssertEqual(g.plinth?.min.y ?? 0, 0, accuracy: 0.15, "\(kind) 足元が地面")
            XCTAssertGreaterThan(g.crystal.center.y, g.plinthTop, "\(kind)")
            for suffix in ["_red", "_red_emit"] {
                guard let url = StructureAssets.resolver(kind.fileName + suffix, "jpg") else { continue }
                let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
                let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
                XCTAssertLessThanOrEqual(props[kCGImagePropertyPixelWidth] as? Int ?? .max, 1024, "\(kind)\(suffix)")
            }
        }
        // -legacyStructures は複数部品の塔を使わない
        StructureAssets.useLegacyModels = true
        for kind in StructureAssets.RigKind.allCases { XCTAssertNil(StructureAssets.rig(kind)) }
    }

    /// 同梱が見つからない種類は nil（読み込み失敗で落ちない）。
    func testMissingFilesFallBack() async {
        StructureAssets.resolver = { name, ext in name == "Struct_tower" ? nil : Bundle.main.url(forResource: name, withExtension: ext) }
        await StructureAssets.load()
        XCTAssertNil(StructureAssets.model(.tower))
        XCTAssertNotNil(StructureAssets.model(.towerOrb))
    }
}
