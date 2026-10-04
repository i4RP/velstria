import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

@MainActor
final class HeroModelTests: XCTestCase {
    private let master = MasterData.shared
    /// 手続きモデルの構造（骨エンティティ名・三角形数など）を前提にするため、同梱アセットの有無に関係なく手続き生成に固定する。
    private static var battle: HeroModelOptions { HeroModelOptions.battle.with(mesh: .procedural) }
    private static let showcase = HeroModelOptions.showcase.with(mesh: .procedural)

    func testAllHeroesBuildWithinBudget() {
        let start = CFAbsoluteTimeGetCurrent()
        for def in master.heroes {
            let model = HeroModelLibrary.makeHero(heroID: def.heroID, skinID: nil, team: .blue, master: master,
                                                  options: Self.battle)
            XCTAssertLessThanOrEqual(model.entityCount, 35, def.heroID)
            XCTAssertLessThan(model.triangleCount, 14_000, def.heroID)
            let parts = Self.drawParts(model.root)
            XCTAssertLessThanOrEqual(parts, 55, "\(def.heroID) 描画単位が多すぎる")
            print("HeroModelTests: \(def.heroID) 三角形 \(model.triangleCount) エンティティ \(model.entityCount) 描画単位 \(parts)")
            XCTAssertGreaterThan(model.triangleCount, 1_000, def.heroID)
            XCTAssertTrue((1.9...2.7).contains(model.overheadHeight), "\(def.heroID) \(model.overheadHeight)")
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print("HeroModelTests: 24 体の初回生成 \(String(format: "%.2f", elapsed)) 秒")
    }

    /// ModelComponent のメッシュパーツ数（≒ 描画呼び出し数）。
    private static func drawParts(_ e: Entity) -> Int {
        var n = 0
        if let model = e.components[ModelComponent.self] {
            n += model.mesh.contents.models.reduce(0) { $0 + $1.parts.count }
        }
        for c in e.children { n += drawParts(c) }
        return n
    }

    func testFeetAtOriginAndHeroHeight() {
        for def in master.heroes {
            let model = HeroModelLibrary.makeHero(heroID: def.heroID, skinID: nil, team: .neutral, master: master,
                                                  options: Self.showcase)
            model.update(dt: 1.0 / 60.0, moveSpeed: 0)
            let head = model.root.findEntity(named: "head")
            XCTAssertNotNil(head, def.heroID)
            let hips = model.root.findEntity(named: "hips")
            let b = model.root.visualBounds(recursive: true, relativeTo: nil, excludeInactive: false)
            XCTAssertGreaterThan(b.min.y, -0.08, "\(def.heroID) 足元が地面より下")
            XCTAssertLessThan(b.min.y, 0.12, "\(def.heroID) 足元が浮いている")
            if let head {
                let hb = head.visualBounds(recursive: false, relativeTo: nil)
                XCTAssertTrue((1.5...2.2).contains(hb.max.y), "\(def.heroID) 頭頂 \(hb.max.y)")
            }
            XCTAssertNotNil(hips)
        }
    }

    func testFacesMinusZ() {
        // 顔（目）は頭の -Z 側にある: 頭メッシュの重心より前方に目がある
        let model = HeroModelLibrary.makeHero(heroID: "H002", skinID: nil, team: .neutral, master: master, options: Self.showcase)
        guard let head = model.root.findEntity(named: "head") else { return XCTFail("head") }
        let b = head.visualBounds(recursive: false, relativeTo: nil)
        // 髪（後頭部）の方が後ろへ張り出すので、中心は +Z 側に寄る
        XCTAssertGreaterThan(b.center.z, -0.02)
        XCTAssertLessThan(b.min.z, -0.3)
    }

    func testRootTransformIsOwnedByRenderer() {
        let model = HeroModelLibrary.makeModel(heroID: "H007", skinID: nil, team: .red, master: master)
        let pos = SIMD3<Float>(12, 0, -34)
        let rot = worldOrientation(facing: 1.2)
        model.root.position = pos
        model.root.orientation = rot
        for state in [HeroAnimState.run, .attack, .cast(.ultimate), .channel, .stunned, .victory, .dead, .idle] {
            model.setState(state)
            for _ in 0..<30 { model.update(dt: 1.0 / 30.0, moveSpeed: 320) }
        }
        XCTAssertEqual(model.root.position, pos)
        XCTAssertEqual(model.root.orientation.vector, rot.vector)
    }

    func testDeathFadesAndRespawnRestores() {
        let model = HeroModelLibrary.makeHero(heroID: "H019", skinID: nil, team: .blue, master: master, options: Self.battle)
        guard let body = model.root.children.first else { return XCTFail("body") }
        model.setState(.dead)
        for _ in 0..<90 { model.update(dt: 1.0 / 60.0, moveSpeed: 0) }
        let faded = body.components[OpacityComponent.self]?.opacity ?? 1
        XCTAssertLessThan(faded, 0.05)
        model.setState(.idle)
        model.update(dt: 1.0 / 60.0, moveSpeed: 0)
        XCTAssertNil(body.components[OpacityComponent.self])
    }

    func testAnimationStaysFinite() {
        let model = HeroModelLibrary.makeHero(heroID: "H011", skinID: nil, team: .blue, master: master, options: Self.battle)
        let states: [HeroAnimState] = [.idle, .run, .attack, .attack, .cast(.skill1), .cast(.skill2), .cast(.skill3),
                                       .cast(.ultimate), .channel, .stunned, .dead, .idle, .victory]
        for (i, s) in states.enumerated() {
            model.setState(s)
            for k in 0..<40 {
                // 異常な dt・速度でも破綻しない
                model.update(dt: k % 7 == 0 ? 0.5 : 1.0 / 60.0, moveSpeed: Double(i * 60))
            }
        }
        var ok = true
        func visit(_ e: Entity) {
            let t = e.transform
            if !(t.translation.x.isFinite && t.translation.y.isFinite && t.translation.z.isFinite
                 && t.rotation.vector.x.isFinite && t.rotation.vector.w.isFinite) { ok = false }
            for c in e.children { visit(c) }
        }
        visit(model.root)
        XCTAssertTrue(ok)
    }

    func testMeshesAndMaterialsAreShared() {
        let a = HeroModelLibrary.makeHero(heroID: "H004", skinID: nil, team: .blue, master: master, options: Self.battle)
        let b = HeroModelLibrary.makeHero(heroID: "H004", skinID: nil, team: .red, master: master, options: Self.battle)
        let ma = (a.root.findEntity(named: "torso") as? ModelEntity)?.model?.mesh
        let mb = (b.root.findEntity(named: "torso") as? ModelEntity)?.model?.mesh
        XCTAssertNotNil(ma)
        XCTAssertTrue(ma === mb)
    }

    func testUpdateCostForTenHeroes() {
        let ids = ["H001", "H004", "H007", "H011", "H013", "H016", "H019", "H021", "H022", "H024"]
        let models = ids.map {
            HeroModelLibrary.makeHero(heroID: $0, skinID: nil, team: .blue, master: master, options: Self.battle)
        }
        for (i, m) in models.enumerated() { m.setState(i % 3 == 0 ? .attack : .run) }
        let frames = 600
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<frames {
            for m in models { m.update(dt: 1.0 / 60.0, moveSpeed: 330) }
        }
        let perFrameMs = (CFAbsoluteTimeGetCurrent() - start) / Double(frames) * 1000
        print("HeroModelTests: 10 体の更新 \(String(format: "%.3f", perFrameMs)) ms/フレーム")
        // Debug ビルド・シミュレータでも 1 フレームの予算を大きく下回ること
        XCTAssertLessThan(perFrameMs, 4)
    }

    func testBlueprintsAreDistinct() {
        XCTAssertEqual(HeroBlueprints.roster.count, 24)
        var signatures = Set<String>()
        for (i, bp) in HeroBlueprints.roster.enumerated() {
            let sig = "\(bp.weapon)|\(bp.offhand)|\(bp.back)|\(bp.float)|\(bp.gear.map { "\($0)" }.joined(separator: ","))"
            XCTAssertFalse(signatures.contains(sig), "H\(i + 1) の装備構成が重複")
            signatures.insert(sig)
        }
        // ロールごとの攻撃モーション系統
        for def in master.heroes {
            let bp = HeroBlueprints.blueprint(heroID: def.heroID, role: def.role)
            switch def.role {
            case .ranger: XCTAssertTrue(bp.attack == .bow || bp.attack == .gun, def.heroID)
            case .vanguard: XCTAssertEqual(bp.build, .heavy, def.heroID)
            case .arcanist: XCTAssertEqual(bp.build, .robed, def.heroID)
            default: break
            }
        }
    }
}
