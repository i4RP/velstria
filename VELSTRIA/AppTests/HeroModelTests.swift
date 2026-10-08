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
        print("HeroModelTests: 34 体の初回生成 \(String(format: "%.2f", elapsed)) 秒")
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
        let states: [HeroAnimState] = [.idle, .run, .attack, .attack, .cast(.skill1), .cast(.skill2),
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
        XCTAssertEqual(HeroBlueprints.roster.count, 34)
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

    /// 追加ヒーロー H025〜H034（docs/NEW_HEROES.md。第 1 段階 H025〜H029・第 2 段階 H030〜H034）の見た目の要件: 武器・体格・攻撃の型・配色の方向。
    func testNewHeroBlueprintsFollowSpec() {
        let r = HeroBlueprints.roster
        XCTAssertEqual(r.count, 34)
        // H025 ルミナ: 素手 + 副手の三日月の長弓だけで戦う射手。翠と白の外套・銀白の髪・月の飾り
        XCTAssertEqual(r[24].weapon, .none)
        XCTAssertEqual(r[24].offhand, .crescentBow)
        XCTAssertEqual(r[24].attack, .bow)
        XCTAssertEqual(r[24].back, .cape)
        XCTAssertTrue(r[24].gear.contains(.crescentPin))
        XCTAssertTrue((0.3...0.5).contains(r[24].accent.h), "翠緑 \(r[24].accent.h)")
        XCTAssertLessThan(r[24].hairColor.s, 0.2, "銀白の髪")
        // H026 エウリア: 細身の雷杖・紫の髪・周囲に浮く雷球・水色の電光
        XCTAssertEqual(r[25].weapon, .stormWand)
        XCTAssertEqual(r[25].float, .sparkOrbs)
        XCTAssertEqual(r[25].build, .robed)
        XCTAssertTrue((0.7...0.85).contains(r[25].hairColor.h), "紫の髪 \(r[25].hairColor.h)")
        XCTAssertTrue((0.45...0.58).contains(r[25].glow.h), "電光の水色 \(r[25].glow.h)")
        // H027 ジャルド: 竜牙の長槍の近接。銀青の鎧・赤い差し色
        XCTAssertEqual(r[26].weapon, .dragonSpear)
        XCTAssertEqual(r[26].attack, .thrust)
        XCTAssertEqual(r[26].armor, .plate)
        XCTAssertTrue(r[26].accent.h > 0.95 || r[26].accent.h < 0.03, "赤い房飾り \(r[26].accent.h)")
        // H028 ザイル: 光刃の長剣・濃紺の軽装甲・光る visor・シアンの光
        XCTAssertEqual(r[27].weapon, .photonBlade)
        XCTAssertEqual(r[27].attack, .slash)
        XCTAssertTrue(r[27].gear.contains(.glassVisor))
        XCTAssertTrue((0.45...0.58).contains(r[27].glow.h), "シアンの光刃 \(r[27].glow.h)")
        // H029 ボルグ: 大柄な重装。聖槌 + 円盾（片手の槌なので両手持ちではない）・青と金
        XCTAssertEqual(r[28].build, .heavy)
        XCTAssertGreaterThan(r[28].scale, 1.05)
        XCTAssertEqual(r[28].weapon, .holyMaul)
        XCTAssertEqual(r[28].offhand, .roundShield)
        XCTAssertFalse(r[28].twoHanded)
        XCTAssertEqual(r[28].metal, .gold)
        XCTAssertTrue((0.55...0.65).contains(r[28].accent.h), "青い房 \(r[28].accent.h)")
        // H030 ライナ: 背丈ほどの星の砲（両手持ちの銃）・ツインテール・桃の光・赤い差し色・白と金
        XCTAssertEqual(r[29].weapon, .starCannon)
        XCTAssertEqual(r[29].attack, .gun)
        XCTAssertTrue(r[29].twoHanded)
        XCTAssertEqual(r[29].hair, .twinTails)
        XCTAssertEqual(r[29].metal, .gold)
        XCTAssertTrue((0.88...0.98).contains(r[29].glow.h), "桃の光 \(r[29].glow.h)")
        XCTAssertTrue(r[29].accent.h > 0.95 || r[29].accent.h < 0.03, "赤い差し色 \(r[29].accent.h)")
        // H031 オーリア: 氷の杖・氷の冠・青白の長髪・周囲に浮く氷の結晶・氷青の光
        XCTAssertEqual(r[30].weapon, .iceStaff)
        XCTAssertEqual(r[30].float, .iceCrystals)
        XCTAssertEqual(r[30].build, .robed)
        XCTAssertTrue(r[30].gear.contains(.iceCrown))
        XCTAssertTrue((0.5...0.62).contains(r[30].hairColor.h), "青白い髪 \(r[30].hairColor.h)")
        XCTAssertLessThan(r[30].hairColor.s, 0.2, "青白い髪")
        XCTAssertTrue((0.5...0.6).contains(r[30].glow.h), "氷青の光 \(r[30].glow.h)")
        // H032 ディアス: 刃付きの籠手（拳剣）の近接・黒髪・赤黒の軽装甲・鉄の灰
        XCTAssertEqual(r[31].weapon, .fistBlade)
        XCTAssertEqual(r[31].attack, .slash)
        XCTAssertFalse(r[31].twoHanded)
        XCTAssertLessThan(r[31].hairColor.b, 0.2, "黒髪")
        XCTAssertTrue(r[31].accent.h > 0.95 || r[31].accent.h < 0.03, "赤い差し色 \(r[31].accent.h)")
        XCTAssertEqual(r[31].metal, .iron)
        // H033 ヴァルド: 両手持ちの巨大な大剣・青白い肌・蝙蝠の翼風のマント・深紅
        XCTAssertEqual(r[32].weapon, .bloodGreatsword)
        XCTAssertEqual(r[32].attack, .heavySwing)
        XCTAssertTrue(r[32].twoHanded)
        XCTAssertEqual(r[32].skin, .pale)
        XCTAssertEqual(r[32].back, .tatteredCape)
        XCTAssertTrue(r[32].glow.h > 0.95 || r[32].glow.h < 0.03, "深紅 \(r[32].glow.h)")
        // H034 ゴルム: 大柄な重装。鉤付きの鎖（片手）・背に掛けた鎖・鉄の灰と錆びた赤
        XCTAssertEqual(r[33].build, .heavy)
        XCTAssertGreaterThan(r[33].scale, 1.1)
        XCTAssertEqual(r[33].weapon, .hookChain)
        XCTAssertEqual(r[33].back, .chainSash)
        XCTAssertFalse(r[33].twoHanded)
        XCTAssertEqual(r[33].metal, .iron)
        XCTAssertTrue(r[33].accent.h < 0.08, "錆びた赤 \(r[33].accent.h)")
    }
}
