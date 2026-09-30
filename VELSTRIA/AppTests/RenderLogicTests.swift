import simd
import XCTest
@testable import VELSTRIA
import VelstriaCore

// battle-renderer: 描画の純粋ロジック（カメラ・角度・霧・画質・数値表示・アニメーション状態）。

@MainActor
final class RenderLogicTests: XCTestCase {
    // MARK: カメラ

    func testCriticallyDampedSpringConvergesWithoutOvershoot() {
        var s = CriticallyDampedSpring(SIMD2(0, 0))
        let target = SIMD2<Float>(10, -4)
        var lastDistance = simd_distance(s.value, target)
        for _ in 0..<120 {
            s.update(target: target, smoothTime: 0.12, dt: 1.0 / 60)
            let d = simd_distance(s.value, target)
            XCTAssertLessThanOrEqual(d, lastDistance + 1e-4, "臨界減衰は目標を行き過ぎない")
            lastDistance = d
        }
        XCTAssertLessThan(lastDistance, 0.01)
    }

    func testSpringSnapAndZeroDt() {
        var s = CriticallyDampedSpring(SIMD2(3, 3))
        s.update(target: SIMD2(0, 0), smoothTime: 0.2, dt: 0)
        XCTAssertEqual(s.value, SIMD2(3, 3))
        s.snap(to: SIMD2(1, 2))
        XCTAssertEqual(s.value, SIMD2(1, 2))
        XCTAssertEqual(s.velocity, .zero)
    }

    func testCameraOffsetMatchesPitch() {
        let o = CameraRig.offset(distance: 10)
        let pitch = atan2(o.y, o.z) * 180 / .pi
        XCTAssertEqual(pitch, CameraRig.pitchDegrees, accuracy: 0.01)
        XCTAssertEqual(simd_length(o), 10, accuracy: 0.001)
        // カメラの前方（-Z）は注視点へ向く
        let forward = CameraRig.orientation.act(SIMD3<Float>(0, 0, -1))
        XCTAssertEqual(simd_dot(simd_normalize(-o), forward), 1, accuracy: 1e-4)
    }

    func testCameraZoomAndClamp() {
        XCTAssertLessThan(CameraRig.distance(forZoom: 0.8), CameraRig.distance(forZoom: 1.3))
        XCTAssertEqual(CameraRig.distance(forZoom: 5), CameraRig.distance(forZoom: 1.4))
        let M = MapScene.mapMeters
        let c = CameraRig.clampFocus(SIMD2(-50, 50), mapMeters: M)
        XCTAssertGreaterThan(c.x, 0)
        XCTAssertLessThan(c.y, 0)
        let d = CameraRig.clampFocus(SIMD2(500, -500), mapMeters: M)
        XCTAssertLessThan(d.x, M)
        XCTAssertGreaterThan(d.y, -M)
        let inside = SIMD2<Float>(60, -60)
        XCTAssertEqual(CameraRig.clampFocus(inside, mapMeters: M), inside)
    }

    // MARK: 向き

    func testApproachAngleTakesShortestPath() {
        // 350° → 10° は +20° 回る（-340° ではない）
        let a = approachAngle(Float(350).radians, Float(10).radians, rate: 100, dt: 1)
        XCTAssertEqual(normalizedDegrees(a), 10, accuracy: 0.01)
        let b = approachAngle(0, .pi / 2, rate: 1, dt: 0.5)
        XCTAssertEqual(b, 0.5, accuracy: 1e-5, "角速度制限")
        let c = approachAngle(0.2, -0.2, rate: 1, dt: 0.1)
        XCTAssertEqual(c, 0.1, accuracy: 1e-5)
    }

    func testYawMatchesContractOrientation() {
        for facing in stride(from: -3.0, through: 3.0, by: 0.7) {
            let q1 = simd_quatf(angle: yawForFacing(facing), axis: [0, 1, 0])
            let q2 = worldOrientation(facing: facing)
            let v1 = q1.act(SIMD3<Float>(0, 0, -1)), v2 = q2.act(SIMD3<Float>(0, 0, -1))
            XCTAssertEqual(simd_distance(v1, v2), 0, accuracy: 1e-5)
            // -Z 正面が sim の facing 方向（world では (cos, 0, -sin)）を向く
            let expected = SIMD3<Float>(Float(cos(facing)), 0, Float(-sin(facing)))
            XCTAssertEqual(simd_distance(v1, expected), 0, accuracy: 1e-4)
        }
    }

    // MARK: 霧

    func testFogFieldAllLitAndAllDark() {
        var f = FogField(size: 32)
        f.computeTarget(cells: [UInt8](repeating: Team.blue.visionBit, count: 60 * 60), cols: 60, rows: 60,
                        bit: Team.blue.visionBit)
        f.blend(1)
        XCTAssertEqual(f.current.max() ?? 1, 0, accuracy: 1e-5)
        f.computeTarget(cells: [UInt8](repeating: Team.red.visionBit, count: 60 * 60), cols: 60, rows: 60,
                        bit: Team.blue.visionBit)
        f.blend(1)
        XCTAssertEqual(f.current.min() ?? 0, 1, accuracy: 1e-5, "赤の視界は青の霧を晴らさない")
    }

    func testFogFieldLocalVisionAndTemporalBlend() {
        var cells = [UInt8](repeating: 0, count: 60 * 60)
        // sim (1000..2000, 1000..2000) を照らす
        for r in 5..<10 { for c in 5..<10 { cells[r * 60 + c] = Team.blue.visionBit } }
        var f = FogField(size: 64)
        f.computeTarget(cells: cells, cols: 60, rows: 60, bit: Team.blue.visionBit)
        XCTAssertLessThan(f.value(atSim: Vec2(1500, 1500), mapSize: 12000), 0.2)
        XCTAssertGreaterThan(f.value(atSim: Vec2(9000, 9000), mapSize: 12000), 0.95)
        // 視界が消えても 1 回の補間では完全には戻らない（滑らかなフェード）
        f.computeTarget(cells: [UInt8](repeating: 0, count: 60 * 60), cols: 60, rows: 60, bit: Team.blue.visionBit)
        f.blend(0.5)
        let mid = f.value(atSim: Vec2(1500, 1500), mapSize: 12000)
        XCTAssertGreaterThan(mid, 0.3)
        XCTAssertLessThan(mid, 0.8)
    }

    func testFogWriteOrientation() {
        var cells = [UInt8](repeating: 0, count: 60 * 60)
        // 上端（sim y 大）の帯だけ照らす
        for r in 48..<60 { for c in 0..<60 { cells[r * 60 + c] = Team.blue.visionBit } }
        var f = FogField(size: 16)
        f.computeTarget(cells: cells, cols: 60, rows: 60, bit: Team.blue.visionBit)
        f.blend(1)
        var bytes = [UInt8](repeating: 0, count: 16 * 16 * 4)
        bytes.withUnsafeMutableBufferPointer { b in
            f.write(into: b.baseAddress!, maxAlpha: 1, topDown: true)
        }
        let topAlpha = bytes[3]
        let bottomAlpha = bytes[(15 * 16) * 4 + 3]
        XCTAssertLessThan(topAlpha, bottomAlpha, "topDown: 行 0 = sim y 最大側（照らされている）")
        XCTAssertEqual(bytes[0], 255, "RGB は白（色は tint）")
    }

    func testFogEmptyVisionClearsFog() {
        var f = FogField(size: 8)
        f.computeTarget(cells: [], cols: 0, rows: 0, bit: Team.blue.visionBit)
        f.blend(1)
        XCTAssertEqual(f.current.max() ?? 1, 0)
    }

    // MARK: 画質

    func testQualityPresets() {
        let low = RenderQuality.preset(.low), mid = RenderQuality.preset(.medium), high = RenderQuality.preset(.high)
        XCTAssertFalse(low.shadows)
        XCTAssertFalse(mid.shadows)
        XCTAssertTrue(high.shadows, "影は high のみ")
        XCTAssertEqual(high.groundTextureSize, 2048)
        XCTAssertEqual(mid.groundTextureSize, 1024)
        XCTAssertEqual(low.groundTextureSize, 1024)
        XCTAssertLessThan(low.particleScale, mid.particleScale)
        XCTAssertLessThan(mid.particleScale, high.particleScale)
        XCTAssertLessThan(low.maxEmitters, high.maxEmitters)
        XCTAssertLessThan(low.fogTextureSize, high.fogTextureSize)
        XCTAssertEqual(low.particles(0), 1, "最低 1 粒")
        XCTAssertEqual(high.particles(40), 40)
    }

    func testRenderSettingsFromGameSettings() {
        var g = GameSettings()
        g.graphicsQuality = .high
        g.frameRate = .fps30
        g.showDamageNumbers = false
        g.colorblindMode = true
        let s = RenderSettings(g)
        XCTAssertEqual(s.quality.level, .high)
        XCTAssertEqual(s.frameRate, 30)
        XCTAssertFalse(s.showDamageNumbers)
        XCTAssertTrue(s.colorblind)
    }

    // MARK: 戦闘数値・色

    func testCombatTextFormat() {
        XCTAssertEqual(CombatTextFormat.damage(341.6, crit: true), "342!")
        XCTAssertEqual(CombatTextFormat.damage(88.2, crit: false), "88")
        XCTAssertEqual(CombatTextFormat.plus(124), "+124")
    }

    func testTeamColorsColorblind() {
        let normal = TeamColors(colorblind: false), cb = TeamColors(colorblind: true)
        XCTAssertNotEqual(normal.main(.red), cb.main(.red))
        XCTAssertGreaterThan(cb.main(.red).g, normal.main(.red).g, "色覚サポートの赤チームは橙")
        XCTAssertGreaterThan(normal.main(.blue).b, normal.main(.blue).r)
    }

    func testPaletteUVsAreInsideTextureAndDistinct() {
        var seen = Set<String>()
        for s in Swatch.allCases {
            let uv = PaletteLayout.uv(s)
            XCTAssertTrue((0...1).contains(uv.x) && (0...1).contains(uv.y))
            seen.insert("\(uv.x),\(uv.y)")
        }
        XCTAssertEqual(seen.count, Swatch.allCases.count)
        XCTAssertLessThan(Swatch.allCases.count, (PaletteLayout.rampTop / PaletteLayout.swatchCell) * PaletteLayout.swatchColumns,
                          "スウォッチはランプ領域と重ならない")
        XCTAssertLessThanOrEqual(Ramp.allCases.count * PaletteLayout.rampHeight, PaletteLayout.size - PaletteLayout.rampTop)
        let a = PaletteLayout.uv(.canopy, t: 0), b = PaletteLayout.uv(.canopy, t: 1)
        XCTAssertLessThan(a.x, b.x)
        XCTAssertEqual(a.y, b.y)
    }

    func testZoneColors() {
        let teams = TeamColors(colorblind: false)
        func zone(team: Team, heal: Bool) -> AreaZone {
            let payload = HitPayload(damage: heal ? 0 : 50, damageType: .magic, source: .skill(.skill3),
                                     affectsEnemies: !heal, affectsAllies: heal, healAmount: heal ? 80 : 0)
            return AreaZone(id: 1, ownerID: 2, team: team, center: .zero, radius: 300, delay: 0.5, payload: payload, visual: "")
        }
        XCTAssertEqual(ZoneLayer.color(for: zone(team: .blue, heal: true), viewer: .blue, teams: teams), RGB(0.4, 1.0, 0.55))
        let ally = ZoneLayer.color(for: zone(team: .blue, heal: false), viewer: .blue, teams: teams)
        let enemy = ZoneLayer.color(for: zone(team: .red, heal: false), viewer: .blue, teams: teams)
        XCTAssertGreaterThan(ally.b, ally.r)
        XCTAssertGreaterThan(enemy.r, enemy.b)
        let neutral = ZoneLayer.color(for: zone(team: .neutral, heal: false), viewer: .blue, teams: teams)
        XCTAssertGreaterThan(neutral.r, neutral.b)
    }

    // MARK: ヒーローのアニメーション状態

    private func makeHero() -> VelstriaCore.Unit {
        let master = MasterData.shared
        guard let def = master.hero("H001") else {
            XCTFail("H001 がマスターに無い")
            return VelstriaCore.Unit(id: 1, kind: .hero, team: .blue, pos: .zero, radius: 55, stats: Stats())
        }
        let slot = PlayerSlot(team: .blue, heroID: "H001", controller: .bot, position: .top, displayName: "T")
        var u = UnitFactory.makeHero(def: def, slot: slot, pos: Vec2(1000, 1000))
        u.id = 7
        return u
    }

    func testHeroAnimStateMapping() {
        var u = makeHero()
        func state(_ u: VelstriaCore.Unit, time: Float = 10, cast: Float = -1, attack: Float = -1, ended: Bool = false,
                   winner: Team? = nil) -> HeroAnimState {
            HeroVisual.animState(unit: u, time: time, castUntil: cast, castSlot: .skill2, attackUntil: attack,
                                 ended: ended, winner: winner)
        }
        XCTAssertEqual(state(u), .idle)
        u.prevPos = Vec2(990, 1000)
        XCTAssertEqual(state(u), .run)
        XCTAssertEqual(state(u, attack: 11), .attack)
        XCTAssertEqual(state(u, cast: 11, attack: 11), .cast(.skill2), "スキルは通常攻撃より優先")
        u.hero?.channel = Channel(kind: .recall, duration: 6)
        XCTAssertEqual(state(u, cast: 11), .channel)
        u.statuses.append(StatusEffect(kind: .stun, duration: 1))
        XCTAssertEqual(state(u), .stunned)
        XCTAssertEqual(state(u, ended: true, winner: .blue), .victory)
        u.hero?.respawnTimer = 5
        XCTAssertEqual(state(u, ended: true, winner: .blue), .dead, "死亡が最優先")
        var airborne = makeHero()
        airborne.statuses.append(StatusEffect(kind: .airborne, duration: 0.3))
        XCTAssertEqual(state(airborne), .stunned)
    }

    func testCreatureKeys() {
        var minion = VelstriaCore.Unit(id: 1, kind: .minion, team: .red, pos: .zero, radius: 36, stats: Stats())
        minion.minion = MinionData(type: .siege, lane: .mid, spawnTime: 0)
        XCTAssertEqual(CreatureKey(minion), .minion(.siege, .red))
        var monster = VelstriaCore.Unit(id: 2, kind: .monster, team: .neutral, pos: .zero, radius: 180, stats: Stats())
        monster.monster = MonsterData(kind: .astralWyrm, campID: 1, home: .zero)
        XCTAssertEqual(CreatureKey(monster), .monster(.astralWyrm))
        XCTAssertTrue(CreatureKey(monster)?.isBoss == true)
        let dummy = VelstriaCore.Unit(id: 3, kind: .dummy, team: .red, pos: .zero, radius: 55, stats: Stats())
        XCTAssertEqual(CreatureKey(dummy), .dummy)
        XCTAssertNil(CreatureKey(makeHero()))
    }

    private func normalizedDegrees(_ radians: Float) -> Float {
        var d = radians * 180 / .pi
        while d < 0 { d += 360 }
        while d >= 360 { d -= 360 }
        return d
    }
}

private extension Float {
    var radians: Float { self * .pi / 180 }
}
