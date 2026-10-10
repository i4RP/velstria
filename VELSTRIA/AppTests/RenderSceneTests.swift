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
        for kind in [MonsterKind.campLarge, .campSmall, .blueSentinel, .redSentinel, .astralWyrm, .ancientColossus,
                     .azureWhelp, .hornLizard, .emberBeetle, .emberGrub, .magmaGolem, .treasureCrab, .crablet, .mossWanderer] {
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
        let lane = groundPixel(image, Vec2(700, 8000))        // top レーン（土）
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
        let heroID = hero.hero?.heroID ?? ""
        XCTAssertEqual(layer.style(for: projectile(owner: hero, visual: "basic_attack"), state: state),
                       ProjectileLayer.basicStyle(heroID: heroID, team: hero.team))
        XCTAssertEqual(layer.style(for: projectile(owner: tower, visual: "tower_shot"), state: state), .tower(.red))
        XCTAssertEqual(layer.style(for: projectile(owner: hero, visual: "empowered_attack"), state: state), .empowered)
        let fx = MasterData.shared.effects.first { $0.effectType == .projectile }?.effectID ?? ""
        if case .skill(let hue, let streak) = layer.style(for: projectile(owner: hero, visual: fx), state: state) {
            XCTAssertTrue(streak, "Projectile 型の演出は細長い光条")
            // 色はスキル演出（SkillFX）のパレットで付ける。スタイルの色相はプールの区別用
            XCTAssertEqual(hue, Int(Theme.heroHue(heroID) * 1000))
        } else {
            XCTFail("スキル弾のスタイル")
        }
        // 遠隔はヒーロー別の形、近接・演出表に無いヒーローは汎用の光弾
        var other = state
        other.units[heroIndex].hero?.heroID = "H010"
        XCTAssertEqual(layer.style(for: projectile(owner: hero, visual: "basic_attack"), state: other),
                       .heroShot(heroID: "H010", team: hero.team))
        other.units[heroIndex].hero?.heroID = "H001"
        XCTAssertEqual(layer.style(for: projectile(owner: hero, visual: "basic_attack"), state: other), .heroBolt(hero.team))
        other.units[heroIndex].hero?.heroID = "H999"
        XCTAssertEqual(layer.style(for: projectile(owner: hero, visual: "basic_attack"), state: other), .heroBolt(hero.team))
    }

    // MARK: ヒーロー別の通常攻撃の演出

    /// H001〜H034 の全員に演出表があり、遠隔（射程 550）は投射物・発射炎、近接（射程 150）は武器の軌跡を持つ。
    /// 色は設計図の glow（主色）と accent（副色）。
    func testEveryHeroHasFXProfile() throws {
        for n in 1...34 {
            let id = String(format: "H%03d", n)
            let p = try XCTUnwrap(HeroFXProfiles.profile(id), id)
            let def = try XCTUnwrap(MasterData.shared.hero(id), id)
            let bp = HeroBlueprints.blueprint(heroID: id, role: def.role)
            XCTAssertEqual(p.heroID, id)
            XCTAssertEqual(p.primary, HeroFXProfiles.rgb(bp.glow), id)
            XCTAssertEqual(p.secondary, HeroFXProfiles.rgb(bp.accent), id)
            XCTAssertEqual(HeroFXProfiles.primaryColor(heroID: id), p.primary)
            XCTAssertEqual(p.isRanged, def.isRanged, "\(id): 演出表の遠近がシムの射程と一致")
            if def.isRanged {
                XCTAssertNotNil(p.shot, id)
                XCTAssertNil(p.trail, id)
                XCTAssertNotEqual(p.muzzle, HeroFXProfile.Muzzle.none, id)
            } else {
                let t = try XCTUnwrap(p.trail, id)
                XCTAssertNil(p.shot, id)
                XCTAssertNil(p.shotTrail, id)
                XCTAssertLessThan(t.inner, t.outer, id)
                XCTAssertTrue((0.08...0.3).contains(t.life), "\(id): 帯の長さ（秒）")
                XCTAssertTrue((0.4...0.95).contains(t.opacity), "\(id): 白飛びしない不透明度")
            }
            // 芯はブルームの閾値（0.6）を超える明るさ
            XCTAssertGreaterThan(max(p.core.r, max(p.core.g, p.core.b)), 0.6, id)
        }
        XCTAssertEqual(HeroFXProfiles.heroIDs.count, 34)
        XCTAssertEqual(HeroFXProfiles.profile("H003")?.launch, .bow, "副手の弓から放つ")
        XCTAssertEqual(HeroFXProfiles.profile("H025")?.launch, .bow, "副手の三日月の長弓から放つ")
        XCTAssertEqual(HeroFXProfiles.profile("H025")?.shot, .arrow)
        XCTAssertEqual(HeroFXProfiles.profile("H026")?.shot, .lightOrb)
        XCTAssertEqual(HeroFXProfiles.profile("H026")?.launch, .weaponTip, "雷杖の先端")
        XCTAssertEqual(HeroFXProfiles.profile("H029")?.impact, .heavyBlunt)
        XCTAssertEqual(HeroFXProfiles.profile("H030")?.shot, .lightOrb)
        XCTAssertEqual(HeroFXProfiles.profile("H030")?.muzzle, .blast, "星砲の大きな発射炎")
        XCTAssertEqual(HeroFXProfiles.profile("H030")?.launch, .weaponTip, "砲口")
        XCTAssertEqual(HeroFXProfiles.profile("H031")?.shot, .waterOrb)
        XCTAssertEqual(HeroFXProfiles.profile("H031")?.launch, .weaponTip, "氷の杖の先端")
        XCTAssertEqual(HeroFXProfiles.profile("H034")?.impact, .blunt)
        XCTAssertEqual(HeroFXProfiles.profile("H007")?.launch, .hands)
        XCTAssertEqual(HeroFXProfiles.profile("H022")?.launch, .hands)
        XCTAssertEqual(HeroFXProfiles.profile("H010")?.launch, .weaponTip, "掌の炎 = 武器の先端")
        XCTAssertEqual(HeroFXProfiles.profile("H017")?.shotTrail, .smoke)
        XCTAssertNil(HeroFXProfiles.profile("H999"), "表に無いヒーローは汎用の演出")
        // 表に無いヒーローの主色もロールの設計図の glow（UI の基調色 Theme.heroHue ではない）
        XCTAssertEqual(HeroFXProfiles.primaryColor(heroID: "H999", role: .arcanist),
                       HeroFXProfiles.rgb(HeroBlueprints.blueprint(heroID: "H999", role: .arcanist).glow))
        // HSB → RGB
        XCTAssertEqual(HeroFXProfiles.rgb(HSB(0, 1, 1)), RGB(1, 0, 0))
        let cyan = HeroFXProfiles.rgb(HSB(0.5, 0.5, 1))
        XCTAssertEqual(cyan.r, 0.5, accuracy: 1e-9)
        XCTAssertEqual(cyan.g, 1, accuracy: 1e-9)
        XCTAssertEqual(cyan.b, 1, accuracy: 1e-9)
    }

    /// 遠隔の全員がヒーロー別のスタイルで事前生成の計画に入り、プールから出した弾は発射位置（武器の先端）から出て、
    /// 着弾点で sim の位置に合う。全ての形・粒子の尾を出しても試合中（live）は何も作らない。
    func testHeroShotsArePlannedPerHeroAndStartAtLaunchPoint() throws {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 5))
        let heroIdx = sim.state.units.indices.filter { sim.state.units[$0].kind == .hero }
        XCTAssertEqual(heroIdx.count, 10)
        let ranged = HeroFXProfiles.heroIDs.filter { HeroFXProfiles.profile($0)?.isRanged == true }
        XCTAssertEqual(ranged.count, 16)
        // 遠隔の 16 人を 10 枠へ 2 回に分けて割り当てる
        for chunk in [Array(ranged.prefix(10)), Array(ranged.suffix(10))] {
            var state = sim.state
            for (k, i) in heroIdx.enumerated() {
                state.units[i].hero?.heroID = chunk[k]
                state.units[i].hero?.isRanged = true
            }
            let plan = ProjectileLayer.plannedStyles(state: state, master: .shared)
            for i in heroIdx {
                let u = state.units[i]
                let style = ProjectileLayer.Style.heroShot(heroID: u.hero?.heroID ?? "", team: u.team)
                XCTAssertEqual(plan.first { $0.style == style }?.count, ProjectileLayer.heroShotPool, "\(style)")
            }
            AssetLedger.beginLoading()
            let layer = ProjectileLayer(materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary(), master: .shared,
                                        quality: .preset(.high))
            for p in plan { layer.prewarm(p.style, visual: p.visual, count: p.count) }
            layer.prewarmTrails()
            AssetLedger.beginLive()
            // 各ヒーローが敵のヒーローへ撃つ（発射位置 = 足元から高さ 1.3 m・横へ 0.4 m）
            func launch(_ id: EntityID) -> SIMD3<Float>? {
                guard let u = state.unit(id) else { return nil }
                return worldPosition(u.pos, height: 1.3) + SIMD3(0.4, 0, -0.3)
            }
            var shots: [Projectile] = []
            for (k, i) in heroIdx.enumerated() {
                let u = state.units[i]
                guard let t = heroIdx.first(where: { state.units[$0].team != u.team }) else { continue }
                shots.append(Projectile(id: EntityID(5000 + k), ownerID: u.id, team: u.team, pos: u.pos,
                                        motion: .homing(targetID: state.units[t].id), speed: 1500,
                                        payload: HitPayload(damage: 1, damageType: .physical, source: .basicAttack),
                                        visual: "basic_attack"))
            }
            state.projectiles = shots
            func sync() {
                layer.sync(RenderFrame(state: state, alpha: 1, dt: 1.0 / 60, time: 0.5, viewerTeam: nil, humanID: nil, focusID: nil,
                                       ended: false, winner: nil), heightOf: { _ in 1.7 }, launchPoint: launch)
            }
            sync()
            XCTAssertEqual(layer.heroShotsShown, shots.count, "全員ヒーロー別の弾")
            XCTAssertEqual(layer.launchedFromWeapon, shots.count, "発射位置から出す")
            for p in shots {
                let pos = try XCTUnwrap(layer.position(of: p.id))
                let want = try XCTUnwrap(launch(p.ownerID))
                XCTAssertLessThan(simd_distance(pos, want), 1e-3, "最初の位置は発射位置")
            }
            // 対象の位置まで進めると、発射位置のずれは消えて sim の位置に合う
            for k in state.projectiles.indices {
                guard case .homing(let tid) = state.projectiles[k].motion, let t = state.unit(tid) else { continue }
                state.projectiles[k].pos = t.pos
                state.projectiles[k].prevPos = t.pos
            }
            sync()
            for p in state.projectiles {
                let pos = try XCTUnwrap(layer.position(of: p.id))
                let want = worldPosition(p.pos)
                XCTAssertEqual(pos.x, want.x, accuracy: 1e-3)
                XCTAssertEqual(pos.z, want.z, accuracy: 1e-3)
            }
            XCTAssertGreaterThan(layer.peakTrails, 0, "粒子の尾を持つ弾がある")
            XCTAssertEqual(layer.trailsSkipped, 0)
            state.projectiles = []
            sync()
            XCTAssertEqual(layer.count, 0, "プールへ戻る")
            let snap = AssetLedger.snapshot()
            XCTAssertEqual(snap.liveTotal, 0, "試合中の生成: \(snap.liveSamples)")
            AssetLedger.end()
        }
    }

    /// 武器の軌跡: 振りの間だけ帯が伸び（最新の列 = 今の刃）、振りが終わると寿命で消える。頂点は親（ヒーローの root）基準、
    /// UV の u は古さ（新しい列ほど小さい）、v は根元 → 先端。
    func testWeaponTrailGrowsDuringSwingAndFades() throws {
        let profile = try XCTUnwrap(HeroFXProfiles.profile("H001"))
        let style = try XCTUnwrap(profile.trail)
        let kit = WeaponTrailKit()
        let material = try XCTUnwrap(kit.material(for: profile, trail: style))
        _ = kit.material(for: profile, trail: style)
        XCTAssertEqual(kit.materialCount, 1, "ヒーロー ID ごとに 1 つ")
        let trail = try XCTUnwrap(WeaponTrail(style: style, material: material, name: "test"))
        let origin = SIMD3<Float>(10, 0, -20)
        func blade(_ a: Float, swing: Bool) -> HeroWeaponTrailSample.Blade {
            let base = origin + SIMD3(0, 1.2, 0)
            return .init(base: base, tip: base + SIMD3(sin(a), 0, -cos(a)), swing: swing)
        }
        var t: Float = 0
        trail.update(blade(0, swing: false), now: t, origin: origin)
        XCTAssertFalse(trail.isShowing, "振っていない間は出ない")
        var a: Float = 0
        for _ in 0..<9 {
            t += 1.0 / 60
            a += 0.22
            trail.update(blade(a, swing: true), now: t, origin: origin)
            XCTAssertTrue(trail.isShowing, "振りの 1 フレーム目から帯になる（前フレームの刃から始める）")
        }
        let v = trail.vertices()
        XCTAssertEqual(v.count, WeaponTrail.columns * 2)
        let tip = blade(a, swing: true).tip - origin, base = blade(a, swing: true).base - origin
        XCTAssertLessThan(simd_distance(v[1].position, base + (tip - base) * style.outer), 1e-3, "最新の列の外端 = 今の刃先の外")
        XCTAssertLessThan(simd_distance(v[0].position, base + (tip - base) * style.inner), 1e-3)
        for k in 1..<WeaponTrail.columns {
            XCTAssertGreaterThanOrEqual(v[k * 2].uv.x, v[(k - 1) * 2].uv.x, "古い列ほど u が大きい")
            XCTAssertLessThan(v[k * 2].uv.y, v[k * 2 + 1].uv.y, "v は根元 → 先端")
        }
        // 振りが終わると寿命の後に消える
        for _ in 0..<(Int(style.life * 60) + 3) {
            t += 1.0 / 60
            trail.update(blade(a, swing: false), now: t, origin: origin)
        }
        XCTAssertFalse(trail.isShowing)
        // 次の振りは新しい帯（前の振りとはつながない）
        t += 0.5
        trail.update(blade(0, swing: false), now: t, origin: origin)
        t += 1.0 / 60
        trail.update(blade(0.3, swing: true), now: t, origin: origin)
        XCTAssertTrue(trail.isShowing)
        trail.reset()
        XCTAssertFalse(trail.isShowing)
        // 陳列は更新で消えない（幕の裏で数フレーム描く）
        trail.showForWarmup(at: .zero)
        trail.update(nil, now: t + 1, origin: origin)
        XCTAssertTrue(trail.isShowing)
        trail.reset()
        XCTAssertFalse(trail.isShowing)
    }

    /// 軌跡のテクスチャ: 古いほど・根元ほど薄く、寿命で透明。新しい先端ほど白い。
    func testWeaponTrailTextureFadesWithAgeAndTowardBase() {
        for look in HeroFXProfile.TrailLook.allCases {
            XCTAssertGreaterThan(WeaponTrailKit.alpha(look: look, u: 0.05, v: 0.85), WeaponTrailKit.alpha(look: look, u: 0.6, v: 0.85),
                                 "\(look): 古いほど薄い")
            XCTAssertEqual(WeaponTrailKit.alpha(look: look, u: 1, v: 0.85), 0, accuracy: 1e-4, "\(look): 寿命で透明")
            XCTAssertGreaterThan(WeaponTrailKit.alpha(look: look, u: 0.1, v: 0.85), WeaponTrailKit.alpha(look: look, u: 0.1, v: 0.1),
                                 "\(look): 根元ほど薄い")
            XCTAssertLessThan(WeaponTrailKit.alpha(look: look, u: 0.1, v: 0), 0.05, "\(look): 握りは透明")
            XCTAssertGreaterThan(WeaponTrailKit.whiteness(look: look, u: 0, v: 1), WeaponTrailKit.whiteness(look: look, u: 0.5, v: 0.5))
        }
        let px = WeaponTrailKit.pixels(look: .blade, color: RGB(1, 0.5, 0), width: 8, height: 4)
        XCTAssertEqual(px.count, 8 * 4 * 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            XCTAssertLessThanOrEqual(px[i], px[i + 3], "アルファ乗算済み")
        }
    }

    /// 近接のヒーローの見た目に武器の軌跡を作る（二刀は 2 本、遠隔は無し）。低画質の試合では作らない。
    func testMeleeHeroesGetWeaponTrailsAndLowQualityNone() {
        var config = MatchFactory.botMatch(seed: 11)
        let ids = ["H001", "H006", "H007", "H012", "H014", "H003", "H010", "H018", "H019", "H024"]
        XCTAssertEqual(config.players.count, ids.count)
        for k in config.players.indices { config.players[k].heroID = ids[k] }
        let sim = Simulation(config: config)
        let medium = UnitLayer(materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary(), text: TextMeshCache(),
                               master: .shared, quality: .preset(.medium))
        medium.sync(frame(sim, viewer: nil))
        // 二刀（H006 は灯籠・H012・H014・H018・H024）は 2 本、H001・H007・H019 は 1 本、遠隔（H003・H010）は無し
        XCTAssertEqual(medium.weaponTrailCount, 5 * 2 + 3)
        let low = UnitLayer(materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary(), text: TextMeshCache(),
                            master: .shared, quality: .preset(.low))
        low.sync(frame(sim, viewer: nil))
        XCTAssertEqual(low.weaponTrailCount, 0)
    }

    /// ヒーロー別の着弾・発射: 1 回で出す粒子は 2 つまで（発射は 1 つ）、低画質は発射の粒子を出さず、予算も守る。
    func testHeroAttackFXParticleCountsAndBudget() throws {
        let materials = RenderMaterials(colorblind: false)
        let high = VFXSystem(quality: .preset(.high), materials: materials, meshes: UnitMeshLibrary())
        for id in HeroFXProfiles.heroIDs {
            let p = try XCTUnwrap(HeroFXProfiles.profile(id))
            let before = high.stats.spawns
            if p.isRanged {
                HeroAttackFX.rangedImpact(p, at: [0, 1, 0], direction: [0, 0, -1], vfx: high, quality: .preset(.high), important: true)
            } else {
                HeroAttackFX.meleeImpact(p, at: [0, 1, 0], direction: [0, 0, -1], vfx: high, quality: .preset(.high), important: true)
            }
            XCTAssertTrue((1...2).contains(high.stats.spawns - before), "\(id): 着弾の粒子は 1〜2")
            let m0 = high.stats.spawns
            HeroAttackFX.muzzle(p, at: [0, 1, 0], direction: [0, 0, -1], vfx: high, quality: .preset(.high), important: true)
            XCTAssertLessThanOrEqual(high.stats.spawns - m0, 1, "\(id): 発射の粒子は 1 つまで")
            high.update(dt: 3)
        }
        let lowQ = RenderQuality.preset(.low)
        let low = VFXSystem(quality: lowQ, materials: materials, meshes: UnitMeshLibrary())
        let blast = try XCTUnwrap(HeroFXProfiles.profile("H015"))
        HeroAttackFX.muzzle(blast, at: .zero, direction: [0, 0, -1], vfx: low, quality: lowQ, important: true)
        XCTAssertEqual(low.stats.spawns, 0, "低画質は発射の粒子を出さない")
        for _ in 0..<5 {
            for id in HeroFXProfiles.heroIDs {
                let p = try XCTUnwrap(HeroFXProfiles.profile(id))
                HeroAttackFX.meleeImpact(p, at: .zero, direction: [1, 0, 0], vfx: low, quality: lowQ, important: false)
            }
        }
        XCTAssertLessThanOrEqual(low.activeCount, lowQ.maxEmitters + VFXSystem.meshFXCap, "軽微な演出は予算を超えない")
    }

    /// 視界外へ出た敵の予告は隠すだけで、発動演出（onTrigger）を出さない。見えている間に消えた単発ゾーンだけ弾ける。
    func testEnemyZoneLeavingVisionDoesNotFakeTrigger() {
        let sim = Simulation(config: MatchFactory.botMatch(seed: 3))
        for _ in 0..<30 { sim.step() }
        var state = sim.state
        guard let blueHero = state.units.first(where: { $0.kind == .hero && $0.team == .blue }),
              let redCore = state.units.first(where: { $0.kind == .core && $0.team == .red })
        else { return XCTFail("ユニットがない") }
        let lit = blueHero.pos
        let dark = redCore.pos
        XCTAssertTrue(state.vision.isLit(lit, for: .blue))
        XCTAssertFalse(state.vision.isLit(dark, for: .blue))
        let layer = ZoneLayer(materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary())
        var triggers = 0
        layer.onTrigger = { _, _, _, _ in triggers += 1 }
        let payload = HitPayload(damage: 50, damageType: .magic, source: .skill(.skill2), affectsEnemies: true)
        var zone = AreaZone(id: 77, ownerID: redCore.id, team: .red, center: lit, radius: 300, delay: 1.5, payload: payload, visual: "")
        func sync() {
            layer.sync(RenderFrame(state: state, alpha: 1, dt: 1.0 / 60, time: 0, viewerTeam: .blue, humanID: nil, focusID: nil,
                                   ended: false, winner: nil))
        }
        state.zones = [zone]
        sync()
        XCTAssertTrue(layer.isShown(77))
        // 視界外へ（ゾーンはまだ残っている）
        zone.center = dark
        state.zones = [zone]
        sync()
        XCTAssertFalse(layer.isShown(77), "視界外の予告は隠す")
        XCTAssertEqual(triggers, 0, "発動していない予告を弾けさせない")
        // 再び視界内へ → 同じ見た目を再表示（新しく作り直して二重に弾けない）
        zone.center = lit
        state.zones = [zone]
        sync()
        XCTAssertTrue(layer.isShown(77))
        XCTAssertEqual(triggers, 0)
        // 見えている間に消えた単発ゾーン → 1 回だけ発動演出
        state.zones = []
        sync()
        XCTAssertEqual(triggers, 1)
        // 視界外のまま消えたゾーンは演出なし
        var hiddenZone = AreaZone(id: 78, ownerID: redCore.id, team: .red, center: lit, radius: 300, delay: 1.5, payload: payload, visual: "")
        state.zones = [hiddenZone]
        sync()
        hiddenZone.center = dark
        state.zones = [hiddenZone]
        sync()
        state.zones = []
        sync()
        XCTAssertEqual(triggers, 1, "見えない所で消えたゾーンは弾けさせない")
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
