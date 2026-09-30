import CoreGraphics
import RealityKit
import simd
import XCTest
@testable import VELSTRIA
import VelstriaCore

// battle-renderer: メッシュ生成・テクスチャ生成・レイヤー（プール・予算・可視性）の結合テスト。

@MainActor
final class RenderSceneTests: XCTestCase {
    // MARK: メッシュ

    /// すべての三角形の法線が形状の中心から外向き（裏面カリングで消えない）。
    private func assertOutward(_ b: MeshBuilder, center: SIMD3<Float>, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(b.isEmpty, file: file, line: line)
        var inward = 0
        var k = 0
        while k + 2 < b.indices.count {
            let a = b.positions[Int(b.indices[k])], c1 = b.positions[Int(b.indices[k + 1])], c2 = b.positions[Int(b.indices[k + 2])]
            let n = simd_cross(c1 - a, c2 - a)
            let centroid = (a + c1 + c2) / 3
            if simd_length(n) > 1e-6 && simd_dot(n, centroid - center) < -1e-5 { inward += 1 }
            k += 3
        }
        XCTAssertEqual(inward, 0, "内向きの三角形がある", file: file, line: line)
    }

    func testPrimitiveWindingIsOutward() {
        var box = MeshBuilder()
        box.box(size: [1, 2, 3], color: .solid(.stone))
        XCTAssertEqual(box.triangleCount, 12)
        assertOutward(box, center: [0, 1, 0])

        var frustum = MeshBuilder()
        frustum.frustum(bottomRadius: 1, topRadius: 0.5, height: 2, segments: 8, color: .ramp(.rock), capBottom: true)
        assertOutward(frustum, center: [0, 1, 0])

        var sphere = MeshBuilder()
        sphere.sphere(radius: 1, segments: 10, rings: 6, color: .solid(.skin))
        assertOutward(sphere, center: .zero)

        var torus = MeshBuilder()
        torus.torus(majorRadius: 2, minorRadius: 0.2, color: .solid(.gold))
        XCTAssertGreaterThan(torus.triangleCount, 0)

        var crystal = MeshBuilder()
        crystal.crystal(radius: 0.5, height: 2, color: .ramp(.crystalBlue))
        assertOutward(crystal, center: [0, 0.9, 0])

        var blob = MeshBuilder()
        blob.blob(radius: 1, jitter: 0.2, seed: 3, color: .ramp(.rock))
        assertOutward(blob, center: .zero)
    }

    func testFlatShapesFaceUp() {
        var b = MeshBuilder()
        b.annulus(inner: 0.5, outer: 1, segments: 12, color: .solid(.white))
        b.flatRect(width: 2, depth: 1, color: .solid(.white))
        b.annulus(inner: 0, outer: 1, segments: 8, startAngle: -0.5, sweep: 1, color: .solid(.white))
        for n in b.normals { XCTAssertGreaterThan(n.y, 0.99) }
    }

    func testAppendTransformsPositionsAndNormals() {
        var part = MeshBuilder()
        part.box(size: [1, 1, 1], color: .solid(.stone))
        var whole = MeshBuilder()
        whole.append(part, transform: MX.t(10, 0, 0))
        XCTAssertEqual(whole.vertexCount, part.vertexCount)
        XCTAssertEqual(whole.positions.map(\.x).min() ?? 0, 9.5, accuracy: 1e-5)
        XCTAssertNotNil(whole.makeMesh(name: "test"))
        XCTAssertNil(MeshBuilder().makeMesh(name: "empty"))
    }

    func testMapPropsProduceGeometry() {
        var b = MeshBuilder()
        var g = MeshBuilder()
        for kind in TreeKind.allCases {
            MapProps.tree(&b, at: .zero, height: 3.5, kind: kind, seed: 1)
        }
        MapProps.rock(&b, at: .zero, size: 0.5, seed: 2)
        MapProps.cliff(&b, at: .zero, radius: 1, height: 2, seed: 3)
        MapProps.grassClump(&b, at: .zero, height: 1.2, seed: 4)
        MapProps.pillar(&b, glow: &g, at: .zero, height: 2, rune: .glowBlue, seed: 5)
        MapProps.lanternPost(&b, glow: &g, at: .zero, height: 2, yaw: 0)
        XCTAssertGreaterThan(b.triangleCount, 300)
        XCTAssertGreaterThan(g.triangleCount, 0)
        // 木の高さは指定値を大きく超えない（スキル予告を隠さない）
        var tree = MeshBuilder()
        MapProps.tree(&tree, at: .zero, height: 3.5, kind: .round, seed: 9)
        XCTAssertLessThan(tree.positions.map(\.y).max() ?? 99, 3.5 * 1.25)
    }

    func testUnitMeshLibraryBuildsAllKinds() {
        let lib = UnitMeshLibrary()
        for type in [MinionType.melee, .ranged, .siege] {
            for team in Team.players {
                let m = lib.minion(type, team: team)
                XCTAssertNotNil(m.body)
                XCTAssertNotNil(m.part)
            }
        }
        for kind in [MonsterKind.campLarge, .campSmall, .blueSentinel, .redSentinel, .astralWyrm, .ancientColossus] {
            XCTAssertNotNil(lib.monster(kind).body, "\(kind)")
        }
        XCTAssertNotNil(lib.dummy.body)
        XCTAssertNotNil(lib.rubble)
        XCTAssertNotNil(lib.stunStars)
        XCTAssertNotNil(lib.rootVines)
        XCTAssertNotNil(lib.slowRing)
        XCTAssertNotNil(lib.sector(halfAngle: 0.6, outline: true))
        // キャッシュ（同じ半径は同じリソース）
        XCTAssertTrue(lib.ring(radius: 2, thickness: 0.1) === lib.ring(radius: 2.01, thickness: 0.1))
    }

    // MARK: テクスチャ

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // CGContext のメモリは上端が行 0
        let i = (y * w + x) * 4
        return (Double(data[i]) / 255, Double(data[i + 1]) / 255, Double(data[i + 2]) / 255)
    }

    /// sim 座標 → 地面テクスチャのピクセル（行 0 = sim y 最大）。
    private func groundPixel(_ image: CGImage, _ p: Vec2) -> (r: Double, g: Double, b: Double) {
        let n = Double(image.width)
        return pixel(image, x: Int(p.x / Balance.mapSize * n), y: Int((1 - p.y / Balance.mapSize) * n))
    }

    func testGroundTextureLayout() throws {
        let image = try XCTUnwrap(GroundTextureGenerator.makeImage(map: .standard, size: 256, colorblind: false))
        XCTAssertEqual(image.width, 256)
        XCTAssertEqual(image.height, 256)
        let lane = groundPixel(image, Vec2(1400, 8000))       // top レーン（土）
        let jungle = groundPixel(image, Vec2(3600, 7300))     // ジャングル（草）
        let river = groundPixel(image, Vec2(4500, 7500))      // 河川
        XCTAssertGreaterThan(lane.r, jungle.r + 0.1, "レーンは土色")
        XCTAssertGreaterThan(jungle.g, jungle.r, "ジャングルは緑")
        XCTAssertGreaterThan(river.b, river.r, "河川は青")
    }

    func testPaletteAndAuxiliaryImages() throws {
        let palette = try XCTUnwrap(PaletteColors.makeImage(teams: TeamColors(colorblind: false)))
        XCTAssertEqual(palette.width, PaletteLayout.size)
        // スウォッチの中心は定義色
        let c = PaletteLayout.uv(.blueMain)
        let px = Int(c.x * Float(PaletteLayout.size))
        let py = Int((PaletteLayout.originBottomLeft ? 1 - c.y : c.y) * Float(PaletteLayout.size))
        let got = pixel(palette, x: px, y: py)
        let want = TeamColors(colorblind: false).main(.blue)
        XCTAssertEqual(got.b, want.b, accuracy: 0.02)
        XCTAssertEqual(got.r, want.r, accuracy: 0.02)
        XCTAssertNotNil(GroundTextureGenerator.outerImage())
        XCTAssertNotNil(MapScene.waterHighlightImage())
        XCTAssertNotNil(MapScene.detailImage())
    }

    // MARK: シーン

    func testMapSceneBrushesAndTranslucency() {
        let materials = RenderMaterials(colorblind: false)
        let map = MapScene(map: .standard, materials: materials, quality: .preset(.low), groundImage: nil)
        XCTAssertEqual(map.brushEntities.count, MapDefinition.standard.brushes.count)
        map.setTranslucentBrush(3)
        XCTAssertNotNil(map.brushEntities[3].components[OpacityComponent.self])
        map.setTranslucentBrush(nil)
        XCTAssertNil(map.brushEntities[3].components[OpacityComponent.self])
        XCTAssertEqual(map.fountainSpires.count, 2)
        // スキル予告に重なる草むらは半透明（予告を草で隠さない）
        let def = MapDefinition.standard
        map.beginBrushMarks()
        map.markBrushes(overlapping: def.brushes[5].rect.center, radius: 100, map: def)
        map.applyBrushTranslucency()
        XCTAssertTrue(map.isBrushTranslucent(5))
        XCTAssertFalse(map.isBrushTranslucent(4))
        map.beginBrushMarks()
        map.applyBrushTranslucency()
        XCTAssertFalse(map.isBrushTranslucent(5))
    }

    func testFogOfWarBuilds() {
        let fog = FogOfWar(team: .blue, size: 64)
        XCTAssertNotNil(fog)
        let sim = Simulation(config: MatchFactory.botMatch(seed: 7))
        fog?.update(state: sim.state, dt: 0.2)
    }

    private func frame(_ sim: Simulation, viewer: Team?, dt: Float = 1.0 / 60, time: Float = 0) -> RenderFrame {
        RenderFrame(state: sim.state, alpha: 0.5, dt: dt, time: time, viewerTeam: viewer, humanID: sim.state.humanHeroID,
                    focusID: sim.state.humanHeroID, ended: sim.isEnded, winner: sim.state.winner)
    }

    func testRenderFrameVisibility() {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 3))
        let f = frame(sim, viewer: .blue)
        let spectate = frame(sim, viewer: nil)
        guard let enemy = sim.state.units.indices.first(where: {
            sim.state.units[$0].kind == .hero && sim.state.units[$0].team == .red
        }) else { return XCTFail("敵ヒーローがいない") }
        // 試合開始時、赤ヒーローは赤の泉（青の視界外）
        XCTAssertFalse(f.isVisible(enemy))
        XCTAssertTrue(spectate.isVisible(enemy), "観戦は全可視")
        guard let tower = sim.state.units.indices.first(where: { sim.state.units[$0].kind == .tower && sim.state.units[$0].team == .red })
        else { return XCTFail("塔がない") }
        XCTAssertTrue(f.isVisible(tower), "構造物は常に可視")
    }

    func testUnitLayerPoolsCreatures() {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 11))
        let materials = RenderMaterials(colorblind: false)
        let layer = UnitLayer(materials: materials, meshes: UnitMeshLibrary(), text: TextMeshCache(), master: .shared)
        layer.prewarm()
        layer.sync(frame(sim, viewer: nil))
        XCTAssertEqual(layer.heroes.count, sim.state.units.filter { $0.kind == .hero }.count)
        XCTAssertEqual(layer.structures.count, sim.state.units.filter { $0.isStructure }.count)
        // 最初のウェーブ（0:20）以降まで進める
        for _ in 0..<(30 * 45) { sim.step() }
        layer.sync(frame(sim, viewer: nil))
        let creatures = sim.state.units.filter { ($0.kind == .minion || $0.kind == .monster) && $0.isAlive }.count
        XCTAssertGreaterThan(creatures, 0)
        for u in sim.state.units where (u.kind == .minion || u.kind == .monster) && u.isAlive {
            XCTAssertNotNil(layer.creature(u.id), "表示中のクリーチャー")
        }
        // 戦闘で消えたユニットは死亡演出の後プールへ戻る（表示数が単調増加しない）
        for _ in 0..<(30 * 60) {
            sim.step()
            if sim.state.tick % 4 == 0 { layer.sync(frame(sim, viewer: nil, dt: 0.2)) }
        }
        layer.sync(frame(sim, viewer: nil, dt: 2))
        layer.sync(frame(sim, viewer: nil, dt: 2))
        let alive = sim.state.units.filter { $0.kind == .minion || $0.kind == .monster || $0.kind == .dummy }.count
        XCTAssertEqual(layer.liveCount, layer.heroes.count + layer.structures.count + alive)
    }

    func testProjectileStyles() {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 5))
        let layer = ProjectileLayer(materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary(), master: .shared,
                                    quality: .preset(.medium))
        let state = sim.state
        guard let heroIndex = state.units.indices.first(where: { state.units[$0].kind == .hero }),
              let towerIndex = state.units.indices.first(where: { state.units[$0].kind == .tower && state.units[$0].team == .red })
        else { return XCTFail("ユニットがない") }
        let hero = state.units[heroIndex], tower = state.units[towerIndex]
        func projectile(owner: VelstriaCore.Unit, visual: String) -> Projectile {
            Projectile(id: 99, ownerID: owner.id, team: owner.team, pos: owner.pos, motion: .linear(direction: Vec2(1, 0), maxDistance: 100),
                       speed: 1000, payload: HitPayload(damage: 1, damageType: .physical, source: .basicAttack), visual: visual)
        }
        XCTAssertEqual(layer.style(for: projectile(owner: hero, visual: "basic_attack"), state: state), .heroBolt(hero.team))
        XCTAssertEqual(layer.style(for: projectile(owner: tower, visual: "tower_shot"), state: state), .tower(.red))
        XCTAssertEqual(layer.style(for: projectile(owner: hero, visual: "empowered_attack"), state: state), .empowered)
        let fx = MasterData.shared.effects.first { $0.effectType == .projectile }?.effectID ?? ""
        if case .skill(_, let streak) = layer.style(for: projectile(owner: hero, visual: fx), state: state) {
            XCTAssertTrue(streak, "Projectile 型の演出は細長い光条")
        } else {
            XCTFail("スキル弾のスタイル")
        }
    }

    /// 同じスタイル（色相・細長さ）のプールから出したスキル弾も、演出ごとの大きさ（scale_m）で描く。
    func testPooledSkillProjectileUsesItsOwnEffectScale() {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 5))
        let layer = ProjectileLayer(materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary(), master: .shared,
                                    quality: .preset(.medium))
        var state = sim.state
        guard let hero = state.units.first(where: { $0.kind == .hero }) else { return XCTFail("ヒーローがいない") }
        let streaks = MasterData.shared.effects.filter { $0.effectType == .projectile || $0.effectType == .trail }
        guard let a = streaks.first,
              let b = streaks.first(where: { abs($0.scaleM - a.scaleM) > 0.2 })
        else { return XCTFail("大きさの違う光条演出がない") }
        func projectile(_ id: EntityID, _ visual: String) -> Projectile {
            Projectile(id: id, ownerID: hero.id, team: hero.team, pos: hero.pos, motion: .linear(direction: Vec2(1, 0), maxDistance: 100),
                       speed: 1000, payload: HitPayload(damage: 1, damageType: .physical, source: .basicAttack), visual: visual)
        }
        func sync() {
            layer.sync(RenderFrame(state: state, alpha: 1, dt: 1.0 / 60, time: 0, viewerTeam: nil, humanID: nil, focusID: nil,
                                   ended: false, winner: nil), heightOf: { _ in 1 })
        }
        XCTAssertEqual(layer.style(for: projectile(1, a.effectID), state: state),
                       layer.style(for: projectile(2, b.effectID), state: state), "同じプールを使う")
        state.projectiles = [projectile(1, a.effectID)]
        sync()
        XCTAssertEqual(layer.coreScale(of: 1), ProjectileLayer.skillScales(Float(a.scaleM), streak: true).core)
        state.projectiles = []
        sync()
        XCTAssertEqual(layer.count, 0, "プールへ戻る")
        state.projectiles = [projectile(2, b.effectID)]
        sync()
        XCTAssertEqual(layer.coreScale(of: 2), ProjectileLayer.skillScales(Float(b.scaleM), streak: true).core,
                       "再利用した見た目を演出の大きさに合わせ直す")
        state.projectiles = []
        sync()
        state.projectiles = [projectile(3, a.effectID)]
        sync()
        XCTAssertEqual(layer.coreScale(of: 3), ProjectileLayer.skillScales(Float(a.scaleM), streak: true).core)
    }

    func testVFXBudget() {
        let vfx = VFXSystem(quality: .preset(.low), materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary())
        let limit = RenderQuality.preset(.low).maxEmitters
        for _ in 0..<(limit * 2) { vfx.spawn(.hitSpark, at: .zero, color: .white) }
        XCTAssertEqual(vfx.activeCount, limit, "予算を超えた軽微な演出は省く")
        vfx.spawn(.levelUp, at: .zero, color: .yellow, important: true)
        XCTAssertEqual(vfx.activeCount, limit, "重要な演出は軽微な演出と入れ替える")
        vfx.startLoop(id: 5, at: .zero, color: .blue)
        XCTAssertTrue(vfx.hasLoop(5))
        vfx.stopLoop(id: 5)
        XCTAssertFalse(vfx.hasLoop(5))
        vfx.update(dt: 5)
        XCTAssertEqual(vfx.activeCount, 0, "寿命で回収される")
        vfx.ring(at: .zero, color: RGB(1, 1, 1), from: 0.5, to: 2, duration: 0.3)
        XCTAssertEqual(vfx.activeCount, 1)
        vfx.update(dt: 0.5)
        XCTAssertEqual(vfx.activeCount, 0)
    }

    func testCombatTextOverlayPooling() {
        let overlay = CombatTextOverlay(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        for k in 0..<(CombatTextOverlay.capacity + 10) {
            overlay.spawn(text: "\(k)", world: .zero, style: .dealt(.physical, crit: k % 5 == 0), seed: k)
        }
        XCTAssertEqual(overlay.activeCount, CombatTextOverlay.capacity, "満杯時は古いものを再利用")
        overlay.update(dt: 0.1) { _ in CGPoint(x: 100, y: 100) }
        XCTAssertEqual(overlay.activeCount, CombatTextOverlay.capacity)
        overlay.update(dt: 2) { _ in CGPoint(x: 100, y: 100) }
        XCTAssertEqual(overlay.activeCount, 0)
        overlay.spawn(text: "+10", world: .zero, style: .gold, seed: 1)
        overlay.clear()
        XCTAssertEqual(overlay.activeCount, 0)
    }

    func testRendererTeardownReleasesRenderer() {
        let config = MatchFactory.practiceMatch(humanHeroID: "H003", humanName: "T", options: PracticeOptions(),
                                                tutorial: false, seed: 1)
        let controller = BattleController(launch: BattleLaunch(config: config))
        weak var weakRenderer: BattleRenderer?
        var view: BattleRenderView?
        autoreleasepool {
            let renderer = BattleRenderer(controller: controller, settings: RenderSettings(GameSettings()))
            view = renderer.makeView()
            weakRenderer = renderer
            renderer.apply(settings: RenderSettings(quality: .preset(.high), frameRate: 30, showDamageNumbers: false,
                                                    colorblind: false))
            renderer.teardown()
        }
        XCTAssertNil(weakRenderer, "購読・クロージャが描画側を保持し続けない")
        XCTAssertNotNil(view)
        // 解除後もコントローラは単独で進められる（購読者が残っていない）
        controller.frame(dt: 0.5)
        XCTAssertGreaterThan(controller.state.tick, 0)
    }

    func testOverheadBarReflectsValues() {
        let bar = OverheadBar(style: .hero(isSelf: true, showResource: true), fillColor: TeamColors.selfColor,
                              materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary(), text: TextMeshCache(),
                              name: "Tester", resourceColor: RGB(0.3, 0.6, 1))
        bar.update(hp: 0.5, shield: 0.8, resource: 0.25, level: 7, dt: 1.0 / 60)
        XCTAssertEqual(bar.displayedHP, 0.5, accuracy: 1e-5)
        XCTAssertEqual(bar.displayedShield, 0.5, accuracy: 1e-5, "HP + シールドは 1 を超えない")
        XCTAssertEqual(bar.displayedLevel, 7)
        bar.update(hp: 1.4, shield: 0, resource: nil, level: 7, dt: 1.0 / 60)
        XCTAssertEqual(bar.displayedHP, 1, accuracy: 1e-5)
    }
}
