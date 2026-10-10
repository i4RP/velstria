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

    /// H029 ボルグは「青い鎧に金の縁」の巨漢に見えること。全身が金一色になる（基調色が金）・小さい玩具のように見える退行を防ぐ。
    func testH029IsBlueAndGoldHeavyKnight() {
        let bp = HeroBlueprints.roster[28]
        // 基調色（鎧の地色）は青。金は metal（縁・聖印・槌の打撃面）、赤は accent（マント）
        let hue = Theme.heroHue("H029")
        XCTAssertTrue((0.55...0.65).contains(hue), "基調色 \(hue)")
        let p = HeroPalettes.base(heroID: "H029", blueprint: bp)
        XCTAssertTrue((0.55...0.65).contains(p.primary.h), "primary \(p.primary.h)")
        XCTAssertEqual(p.metalKind, .gold)
        XCTAssertTrue((0.08...0.16).contains(p.metal.h), "金 \(p.metal.h)")
        XCTAssertTrue(p.accent.h > 0.95 || p.accent.h < 0.03, "赤いマント \(p.accent.h)")
        // 大きさ: 他の重装（H001・H019 は 1.06〜1.12）より明らかに大きく、肩幅・胸板も heavy より広い
        XCTAssertGreaterThanOrEqual(bp.scale, 1.25)
        let titan = BodyMetrics.make(.titan), heavy = BodyMetrics.make(.heavy)
        XCTAssertGreaterThan(titan.torsoW, heavy.torsoW)
        XCTAssertGreaterThan(titan.shoulderX, heavy.shoulderX)
        XCTAssertGreaterThan(titan.armR, heavy.armR)
        XCTAssertLessThan(titan.headTop, heavy.headTop, "頭は肩の間に沈め、scale を上げても高さの上限（overheadHeight 2.7）に収める")
        XCTAssertLessThanOrEqual((titan.headTop + 0.38) * bp.scale, 2.7)
        // 実際のモデルでも、足元から頭頂までが上限に収まり、肩幅（左右）は他の重装より広い
        let model = HeroModelLibrary.makeHero(heroID: "H029", skinID: nil, team: .blue, master: master, options: Self.showcase)
        model.update(dt: 1.0 / 60.0, moveSpeed: 0)
        let rival = HeroModelLibrary.makeHero(heroID: "H019", skinID: nil, team: .blue, master: master, options: Self.showcase)
        rival.update(dt: 1.0 / 60.0, moveSpeed: 0)
        let torso = model.root.findEntity(named: "torso")?.visualBounds(recursive: false, relativeTo: nil)
        let rivalTorso = rival.root.findEntity(named: "torso")?.visualBounds(recursive: false, relativeTo: nil)
        XCTAssertNotNil(torso)
        XCTAssertNotNil(rivalTorso)
        if let torso, let rivalTorso {
            XCTAssertGreaterThan(torso.extents.x, rivalTorso.extents.x * 1.15, "H029 の胴は H019 より 15% 以上広い")
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
        // H028 ザイル（セイバー）: 赤い刃縁の黒い長剣・鋼青の機甲に黒い下地・赤い visor・銀白の高い結い髪・回る小剣
        XCTAssertEqual(r[27].weapon, .photonBlade)
        XCTAssertEqual(r[27].attack, .slash)
        XCTAssertEqual(r[27].armor, .cyber)
        XCTAssertTrue(r[27].gear.contains(.cyberVisor))
        XCTAssertEqual(r[27].hair, .highPonytail)
        XCTAssertEqual(r[27].float, .orbitBlades)
        XCTAssertEqual(r[27].metal, .silver)
        XCTAssertTrue(r[27].glow.h > 0.95 || r[27].glow.h < 0.03, "赤い visor・刃縁 \(r[27].glow.h)")
        XCTAssertLessThan(r[27].hairColor.s, 0.15, "銀白の髪")
        // H029 ボルグ: 巨漢の重装。聖槌 + 大盾（片手の槌なので両手持ちではない）・青い板金に金の縁・赤いマント・金髪（兜は被らない）
        XCTAssertEqual(r[28].build, .titan)
        XCTAssertEqual(r[28].armor, .knight)
        XCTAssertGreaterThanOrEqual(r[28].scale, 1.25)
        XCTAssertEqual(r[28].weapon, .holyMaul)
        XCTAssertEqual(r[28].offhand, .heaterShield)
        XCTAssertEqual(r[28].back, .cape)
        XCTAssertFalse(r[28].twoHanded)
        XCTAssertEqual(r[28].metal, .gold)
        XCTAssertTrue(r[28].accent.h > 0.95 || r[28].accent.h < 0.03, "赤いマント \(r[28].accent.h)")
        XCTAssertTrue((0.1...0.16).contains(r[28].hairColor.h), "金髪 \(r[28].hairColor.h)")
        XCTAssertGreaterThan(r[28].hairColor.b, 0.9, "金髪")
        XCTAssertEqual(r[28].hair, .short)
        XCTAssertFalse(r[28].gear.contains(.knightHelm), "兜のドームで顔と髪を隠さない")
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
        // H033 ヴァルド（アルーカード）: 片手で振る巨大な銀の大剣・金髪・濃紺の長いコートに銅の縁・青い短いケープ・青い光
        XCTAssertEqual(r[32].weapon, .bloodGreatsword)
        XCTAssertEqual(r[32].attack, .slash)
        XCTAssertFalse(r[32].twoHanded)
        XCTAssertEqual(r[32].armor, .hunter)
        XCTAssertEqual(r[32].skirt, .longCoat)
        XCTAssertEqual(r[32].back, .capelet)
        XCTAssertEqual(r[32].metal, .silver)
        XCTAssertTrue((0.1...0.15).contains(r[32].hairColor.h), "金髪 \(r[32].hairColor.h)")
        XCTAssertGreaterThan(r[32].hairColor.b, 0.9, "金髪")
        XCTAssertTrue((0.05...0.1).contains(r[32].accent.h), "銅の縁 \(r[32].accent.h)")
        XCTAssertTrue((0.5...0.62).contains(r[32].glow.h), "青い光 \(r[32].glow.h)")
        // H034 ゴルム（フランコ）: 脚の短い巨漢。角の鉄兜・赤い大髭・円盤の肩当て・鉄の鉤（片手）・背に掛けた鎖・緑の上衣
        XCTAssertEqual(r[33].build, .brute)
        XCTAssertGreaterThanOrEqual(r[33].scale, 1.3)
        XCTAssertEqual(r[33].weapon, .hookChain)
        XCTAssertEqual(r[33].back, .chainSash)
        XCTAssertFalse(r[33].twoHanded)
        XCTAssertEqual(r[33].metal, .iron)
        XCTAssertEqual(r[33].armor, .viking)
        XCTAssertEqual(r[33].pauldron, .disc)
        XCTAssertTrue(r[33].gear.contains(.raiderHelm))
        XCTAssertTrue(r[33].gear.contains(.fullBeard))
        XCTAssertTrue(r[33].hairColor.h < 0.06 && r[33].hairColor.s > 0.6, "赤毛の髭 \(r[33].hairColor.h)")
        XCTAssertTrue((0.2...0.33).contains(r[33].accent.h), "緑の上衣 \(r[33].accent.h)")
    }

    /// H028・H033・H034 はモバレジェの原作（セイバー・アルーカード・フランコ）の配色と大きさで見えること。
    /// 基調色の取り違え（シアン・深紅に戻る）や、フランコが他の重装と同じ大きさに戻る退行を防ぐ。
    func testMLBBInspiredH028H033H034() {
        // セイバー: 鋼青の装甲（基調色）・黒い下地・銀の縁
        let saber = HeroPalettes.base(heroID: "H028", blueprint: HeroBlueprints.roster[27])
        XCTAssertTrue((0.56...0.62).contains(saber.primary.h), "鋼青 \(saber.primary.h)")
        XCTAssertLessThan(saber.dark.b, 0.3, "黒い下地")
        // アルーカード: 青いケープ（基調色）と濃紺のコート（secondary）、金ではなく銀の大剣
        let vald = HeroPalettes.base(heroID: "H033", blueprint: HeroBlueprints.roster[32])
        XCTAssertTrue((0.58...0.64).contains(vald.primary.h), "青 \(vald.primary.h)")
        XCTAssertLessThan(vald.secondary.b, 0.5, "濃紺のコート")
        XCTAssertEqual(vald.metalKind, .silver)
        // フランコ: 樽のような巨漢。脚は短く、胴と腕は titan より太い。背を伸ばさずに幅で大きく見せ、高さの上限に収める
        let brute = BodyMetrics.make(.brute), titan = BodyMetrics.make(.titan)
        XCTAssertGreaterThan(brute.torsoW, titan.torsoW)
        XCTAssertGreaterThan(brute.armR, titan.armR)
        XCTAssertLessThan(brute.hipY, titan.hipY, "脚が短い")
        XCTAssertLessThanOrEqual((brute.headTop + 0.38) * HeroBlueprints.roster[33].scale, 2.7)
        let franco = HeroModelLibrary.makeHero(heroID: "H034", skinID: nil, team: .blue, master: master, options: Self.showcase)
        franco.update(dt: 1.0 / 60.0, moveSpeed: 0)
        let borg = HeroModelLibrary.makeHero(heroID: "H029", skinID: nil, team: .blue, master: master, options: Self.showcase)
        borg.update(dt: 1.0 / 60.0, moveSpeed: 0)
        let ft = franco.root.findEntity(named: "torso")?.visualBounds(recursive: false, relativeTo: nil)
        let bt = borg.root.findEntity(named: "torso")?.visualBounds(recursive: false, relativeTo: nil)
        XCTAssertNotNil(ft)
        XCTAssertNotNil(bt)
        if let ft, let bt {
            XCTAssertGreaterThan(ft.extents.x, bt.extents.x * 1.1, "H034 の胴は H029 より 10% 以上広い")
        }
    }
}
