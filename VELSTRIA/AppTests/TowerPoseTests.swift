import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 塔・Star Core の部品の姿勢（TowerPose: 時刻だけで決まる純粋関数）・合図（一度きり）・見た目への反映（StructureVisual）・
/// 複数部品のモデルの読み込みと従来モデルへの戻り・予算。
@MainActor
final class TowerPoseTests: XCTestCase {
    override func tearDown() async throws {
        StructureAssets.resetForTesting()
        try await super.tearDown()
    }

    /// 複数部品の塔の寸法（外塔の設計に近い数値）。
    private let rigTower = TowerGeometry.rig(isCore: false, boxes: [
        .plinth: PartBox(min: [-1.6, 0, -1.6], max: [1.6, 0.7, 1.6]),
        .lower: PartBox(min: [-0.6, 0, -0.6], max: [0.6, 1.6, 0.6]),
        .upper: PartBox(min: [-0.7, 1.6, -0.7], max: [0.7, 3.8, 0.7]),
        .crown: PartBox(min: [-0.9, 3.8, -0.9], max: [0.9, 4.6, 0.9]),
        .crystal: PartBox(min: [-0.4, 4.7, -0.4], max: [0.4, 5.7, 0.4]),
    ])!

    private let rigCore = TowerGeometry.rig(isCore: true, boxes: [
        .plinth: PartBox(min: [-3.4, 0, -3.4], max: [3.4, 1.2, 3.4]),
        .upper: PartBox(min: [-3.0, 1.2, -3.0], max: [3.0, 4.5, 3.0]),
        .crystal: PartBox(min: [-1, 3.5, -1], max: [1, 6.5, 1]),
    ])!

    private func input(_ g: TowerGeometry, _ t: Double, death: Double? = nil, hp: Double = 1, style: CollapseStyle = .full)
        -> TowerPoseInput {
        TowerPoseInput(geometry: g, time: t, deathTime: death, hpRatio: hp, style: style, seed: 42)
    }

    private func assertClose(_ a: simd_float4x4, _ b: simd_float4x4, accuracy: Float = 1e-4, _ msg: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        for c in 0..<4 {
            for r in 0..<4 {
                XCTAssertEqual(a[c][r], b[c][r], accuracy: accuracy, msg, file: file, line: line)
            }
        }
    }

    private func center(_ m: simd_float4x4, _ box: PartBox) -> SIMD3<Float> { TowerPose.transform(m, box.center) }

    // MARK: 決定論

    /// 同じ入力なら同じ姿勢（前の評価に依存しない）。
    func testSameTimeGivesSamePose() {
        for g in [rigTower, rigCore, TowerGeometry.proceduralTower] {
            for t in [0.0, 0.7, 1.6, 2.1, 30.0] {
                XCTAssertEqual(TowerPose.evaluate(input(g, t)), TowerPose.evaluate(input(g, t)))
                XCTAssertEqual(TowerPose.evaluate(input(g, t, hp: 0.2)), TowerPose.evaluate(input(g, t, hp: 0.2)))
            }
            for e in [0.0, 0.1, 0.4, 0.9, 1.2, 2.0, 3.0, 5.0, 6.0, 7.0] {
                let a = TowerPose.evaluate(input(g, 100 + e, death: 100))
                // 間に別の時刻を評価しても変わらない
                _ = TowerPose.evaluate(input(g, 100 + e * 0.5, death: 100))
                XCTAssertEqual(a, TowerPose.evaluate(input(g, 100 + e, death: 100)), "e = \(e)")
            }
        }
    }

    // MARK: 立ち上がり

    /// 立ち上がりの終わり = 無傷の静止姿勢（石の部品は単位行列、明るさは通常）。途中で飛び・伸び縮みしない。
    func testRiseEndsAtTheIntactPose() {
        let g = rigTower
        let end = TowerPose.evaluate(input(g, TowerTimeline.riseEnd))
        for piece in [end.plinth, end.lower, end.upper, end.crown] {
            assertClose(piece.matrix, matrix_identity_float4x4)
            XCTAssertTrue(piece.visible)
        }
        XCTAssertEqual(end.plinthGlow, 1, accuracy: 0.01)
        XCTAssertEqual(end.bodyGlow, 1, accuracy: 0.01)
        XCTAssertEqual(end.crystalGlow, 1, accuracy: 0.01)
        XCTAssertEqual(end.phase, .idle)
        // 試合の途中から見る（2.4 秒より後）は完成した姿
        let later = TowerPose.evaluate(input(g, 95))
        assertClose(later.upper.matrix, matrix_identity_float4x4)
        assertClose(later.crown.matrix, matrix_identity_float4x4)
        // 結晶は待機の揺れ（上下・回転・脈動）だけ: 静止位置の近く
        let c = center(later.crystal.matrix, g.crystal)
        XCTAssertLessThan(simd_distance(c, g.crystal.center), 0.12)

        // 始まり: 支柱・頂部・結晶は全て基壇の上面より下（基壇と地面に隠れる）、結晶は消灯
        let start = TowerPose.evaluate(input(g, 0))
        for (m, box) in [(start.upper.matrix, g.upper), (start.crown.matrix, g.crown!), (start.crystal.matrix, g.crystal),
                         (start.lower.matrix, g.lower!)] {
            let top = box.corners.map { TowerPose.transform(m, $0).y }.max()!
            XCTAssertLessThanOrEqual(top, g.plinthTop, "沈んだ部品が基壇から出ていない")
        }
        XCTAssertLessThan(start.crystalGlow, 0.1)
        XCTAssertEqual(start.phase, .rising)

        // 連続: 1/60 秒ごとに部品の位置が大きく飛ばない（跳ね返り・伸び縮み無し = 拡縮は常に 1）
        var prev = TowerPose.evaluate(input(g, -0.1))
        var t = -0.1
        var peak: Float = 0
        while t < TowerTimeline.riseEnd + 0.2 {
            t += 1.0 / 60
            let p = TowerPose.evaluate(input(g, t))
            for (a, b, box) in [(prev.upper, p.upper, g.upper), (prev.crown, p.crown, g.crown!)] {
                XCTAssertLessThan(simd_distance(center(a.matrix, box), center(b.matrix, box)), 0.2, "t = \(t)")
                XCTAssertEqual(simd_length(SIMD3(b.matrix.columns.1.x, b.matrix.columns.1.y, b.matrix.columns.1.z)), 1,
                               accuracy: 1e-4, "伸び縮みしない")
            }
            // 上部は上がるだけ（行き過ぎて戻らない）
            XCTAssertGreaterThanOrEqual(p.upper.matrix.columns.3.y, prev.upper.matrix.columns.3.y - 1e-5, "t = \(t)")
            peak = max(peak, p.crystalGlow)
            prev = p
        }
        XCTAssertGreaterThan(peak, 2, "点灯の短い山")
    }

    // MARK: 損傷・攻撃

    func testDamageStagesLeanAndDimAndChargeBrightens() {
        let g = rigTower
        let healthy = TowerPose.evaluate(input(g, 50, hp: 1))
        let one = TowerPose.evaluate(input(g, 50, hp: 0.6))
        let two = TowerPose.evaluate(input(g, 50, hp: 0.3))
        XCTAssertEqual(TowerTimeline.damageStage(hpRatio: 0.6), 1)
        let top = SIMD3<Float>(0, g.upper.max.y, 0)
        let lean0 = TowerPose.transform(healthy.upper.matrix, top)
        let lean1 = TowerPose.transform(one.upper.matrix, top)
        let lean2 = TowerPose.transform(two.upper.matrix, top)
        XCTAssertGreaterThan(simd_distance(lean0, lean1), 0.03)
        XCTAssertGreaterThan(simd_distance(lean0, lean2), simd_distance(lean0, lean1), "2 段階はさらに傾く")
        XCTAssertLessThan(lean2.z, lean0.z, "奥（北）へ傾く")
        // 根元・基壇は揺れない
        assertClose(two.lower.matrix, matrix_identity_float4x4)
        assertClose(two.plinth.matrix, matrix_identity_float4x4)
        XCTAssertLessThan(one.crystalGlow, healthy.crystalGlow)
        XCTAssertLessThan(two.crystalGlow, healthy.crystalGlow)
        // 攻撃の前隙: 紋様と結晶が明るくなる
        var charged = input(g, 50)
        charged.charge = 1
        let c = TowerPose.evaluate(charged)
        XCTAssertGreaterThan(c.crystalGlow, healthy.crystalGlow + 1)
        XCTAssertGreaterThan(c.bodyGlow, healthy.bodyGlow)
    }

    // MARK: 倒壊

    /// 上部は奥（北 = -z）へ倒れ、基部から 3 m ほどに着地する。頂部は外れて別に落ちる。跳ね返らない。
    func testCollapseTopplesAwayFromTheCameraAndLandsNearTheBase() throws {
        let g = rigTower
        let d = 200.0
        let landed = TowerPose.evaluate(input(g, d + TowerTimeline.toppleEnd, death: d))
        let uc = center(landed.upper.matrix, g.upper)
        XCTAssertLessThan(uc.z, -0.8, "奥へ倒れる")
        XCTAssertLessThan(simd_length(SIMD2(uc.x, uc.z)), 3.5, "基部の近くに落ちる")
        XCTAssertLessThan(uc.y, 1.0, "地面に載る")
        // 頂部は外れて遅れて落ち、着地の区間（〜2.3 秒）のうちに地面で止まる
        let crownLand = try XCTUnwrap(TowerPose.crownLandTime(g, times: .full, seed: 42))
        XCTAssertGreaterThan(crownLand, CollapseTimes.full.separate)
        XCTAssertLessThan(crownLand, TowerTimeline.impactEnd)
        let settledCrown = TowerPose.evaluate(input(g, d + TowerTimeline.impactEnd, death: d))
        let cc = center(settledCrown.crown.matrix, g.crown!)
        XCTAssertLessThan(cc.z, 0)
        XCTAssertLessThan(simd_length(SIMD2(cc.x, cc.z)), 4.5)
        XCTAssertLessThan(cc.y, 1.0)
        XCTAssertFalse(landed.crystal.visible, "結晶は割れて破片になる")
        XCTAssertEqual(landed.shards.count, TowerPose.shardCount(core: false, style: .full))
        // 着地の後は動かない（跳ね返り・転がり無し）
        let rest = TowerPose.evaluate(input(g, d + TowerTimeline.impactEnd, death: d))
        assertClose(rest.upper.matrix, TowerPose.evaluate(input(g, d + 3.5, death: d)).upper.matrix)
        assertClose(rest.crown.matrix, TowerPose.evaluate(input(g, d + 3.5, death: d)).crown.matrix)
        for k in rest.shards.indices {
            assertClose(rest.shards[k].matrix, TowerPose.evaluate(input(g, d + 3.5, death: d)).shards[k].matrix)
        }
        // 破断までは上部が無傷の位置の近く（異常発光・亀裂の区間）
        let flash = TowerPose.evaluate(input(g, d + 0.15, death: d))
        XCTAssertLessThan(simd_distance(center(flash.upper.matrix, g.upper), g.upper.center), 0.25)
        XCTAssertTrue(flash.crystal.visible)
        XCTAssertGreaterThan(flash.crystalGlow, 1.5, "結晶の異常発光")
        XCTAssertEqual(flash.plinthGlow, 0, "紋様が消える")
        XCTAssertGreaterThanOrEqual(flash.debris.count + flash.shards.count, 0)
    }

    /// 整理の後は破損した基壇と折れた根元だけ（上部・頂部・結晶・破片は無い）。
    func testDestroyedLeavesOnlyStumpAndPlinthAfterClearEnd() {
        for style in [CollapseStyle.full, .short] {
            let g = rigTower
            let d = 50.0
            let times = CollapseTimes.of(style)
            let after = TowerPose.evaluate(input(g, d + times.clear + 0.01, death: d, style: style))
            XCTAssertEqual(after.phase, .cleared)
            XCTAssertTrue(after.plinth.visible)
            XCTAssertTrue(after.lower.visible)
            XCTAssertFalse(after.upper.visible)
            XCTAssertFalse(after.crown.visible)
            XCTAssertFalse(after.crystal.visible)
            XCTAssertTrue(after.shards.isEmpty && after.debris.isEmpty)
            XCTAssertTrue(after.ruined, "紋様の消えた破損基壇")
            XCTAssertLessThan(after.plinth.matrix.columns.3.y, -0.05, "基壇は少し下がる")
            assertClose(after.lower.matrix, matrix_identity_float4x4)
            // 整理の直前: 大きな石は地面へ沈み切っている（一様に薄くして消すのではない）
            let before = TowerPose.evaluate(input(g, d + times.clear - 0.001, death: d, style: style))
            let top = g.upper.corners.map { TowerPose.transform(before.upper.matrix, $0).y }.max()!
            XCTAssertLessThan(top, 0.1, "\(style)")
            XCTAssertEqual(before.upper.opacity, 1)
            // 瓦礫の間は残っている
            let rubble = TowerPose.evaluate(input(g, d + times.hold - 0.1, death: d, style: style))
            XCTAssertTrue(rubble.upper.visible)
            XCTAssertFalse(rubble.shards.isEmpty)
            XCTAssertEqual(rubble.debris.filter(\.visible).count, TowerPose.debrisCount(core: false, style: style))
        }
    }

    /// Core: 過負荷 → 石柱が外へ崩れる → 大結晶が縮んで割れる（光の柱）→ 落ち着く。試合終了後の時刻でも進む。
    func testStarCoreCollapses() {
        let g = rigCore
        let d = 600.0
        let overload = TowerPose.evaluate(input(g, d + 0.3, death: d))
        XCTAssertGreaterThan(overload.crystalGlow, 1.5)
        XCTAssertTrue(overload.crystal.visible)
        let column = TowerPose.evaluate(input(g, d + 2.5, death: d))
        XCTAssertGreaterThan(column.column, 0.9, "光の柱")
        XCTAssertFalse(column.crystal.visible)
        XCTAssertEqual(column.shards.count, 6)
        let settled = TowerPose.evaluate(input(g, d + TowerTimeline.finaleResult, death: d))
        XCTAssertEqual(settled.column, 0)
        XCTAssertLessThan(settled.upper.matrix.columns.3.y, -1, "石柱と弧は台座へ崩れ落ちる")
        XCTAssertTrue(settled.plinth.visible)
        XCTAssertNotEqual(TowerPose.evaluate(input(g, d + 2.2, death: d)), TowerPose.evaluate(input(g, d + 2.3, death: d)),
                          "終了後の時刻でも動く")
    }

    // MARK: 合図

    /// 合図は 1 回だけ（評価の刻み方によらない）。時刻順。
    func testCuesFireOnceRegardlessOfFrameRate() {
        let g = rigTower
        let d = 30.0
        func run(step: Double) -> [TowerCue] {
            var out: [TowerCue] = []
            var t = -0.5
            var hp = 1.0
            while t < d + 7 {
                let next = t + step
                if next > 10 { hp = 0.3 }
                out += TowerPose.cues(input(g, next, death: next >= d ? d : nil, hp: hp), from: t, to: next).map(\.cue)
                t = next
            }
            return out
        }
        let a = run(step: 1.0 / 60), b = run(step: 1.0 / 23)
        XCTAssertEqual(a, b)
        for cue: TowerCue in [.riseStart, .riseLock, .crystalIgnite, .breakFlash, .crack, .toppleStart, .crystalShatter, .separate,
                              .crownImpact, .impact, .clearDebris, .crystalFade, .crumble] {
            XCTAssertEqual(a.filter { $0 == cue }.count, 1, "\(cue)")
        }
        XCTAssertGreaterThan(a.filter { $0 == .wisp }.count, 2, "損傷 2 段階の魔力漏れ")
        XCTAssertEqual(a.firstIndex(of: .breakFlash).map { $0 < a.firstIndex(of: .impact)! }, true)
        // 時刻が戻る・同じ時刻では何も出ない
        XCTAssertTrue(TowerPose.cues(input(g, d + 1, death: d), from: d + 2, to: d + 1).isEmpty)
        XCTAssertTrue(TowerPose.cues(input(g, d + 1, death: d), from: d + 1, to: d + 1).isEmpty)
        // 破壊の後に立ち上がりの合図は出ない（途中から見た時）
        XCTAssertTrue(TowerPose.cues(input(g, 1, death: 0.5), from: 0, to: 2.5).allSatisfy { $0.cue != .riseLock })
    }

    /// 同時に倒れる塔の上限: 先に倒れ始めて着地していない塔が上限以上なら短縮版。破壊の時刻だけで決まる。
    func testConcurrentCollapsesBeyondTheLimitUseTheShortVersion() {
        let others: [(deathTime: Double, id: EntityID)] = [(10.0, 5), (10.2, 9), (10.4, 3), (20, 7)]
        XCTAssertEqual(TowerPose.collapseStyle(id: 5, deathTime: 10.0, others: others), .full)
        XCTAssertEqual(TowerPose.collapseStyle(id: 9, deathTime: 10.2, others: others), .full)
        XCTAssertEqual(TowerPose.collapseStyle(id: 3, deathTime: 10.4, others: others), .short)
        XCTAssertEqual(TowerPose.collapseStyle(id: 7, deathTime: 20, others: others), .full, "前の倒壊が終わった後")
        XCTAssertEqual(TowerTimeline.maxConcurrentCollapses, 2)
        // 短縮版は小破片を出さず、結晶片も少ない
        XCTAssertEqual(TowerPose.debrisCount(core: false, style: .short), 0)
        XCTAssertLessThan(TowerPose.shardCount(core: false, style: .short), TowerPose.shardCount(core: false, style: .full))
    }

    // MARK: 見た目（StructureVisual）

    private func frame(_ s: SimState, t: Double) -> RenderFrame {
        var f = RenderFrame(state: s, alpha: 1, dt: 1.0 / 60, time: 0, viewerTeam: nil, humanID: nil, focusID: nil,
                            ended: false, winner: nil)
        f.presentationTime = t
        return f
    }

    private func layer() -> UnitLayer {
        UnitLayer(materials: RenderMaterials(colorblind: false), meshes: UnitMeshLibrary(), text: TextMeshCache(), master: .shared)
    }

    /// シーク（presentationEpoch）で飛んだ先の見た目 = 続けて再生した見た目。飛ばした区間の合図は出さない。
    func testSeekGivesTheSameLookAsContinuousPlayAndDoesNotReplayCues() throws {
        StructureAssets.isEnabled = false
        let sim = Simulation(config: MatchFactory.botMatch(seed: 31))
        let alive = sim.state
        let ti = try XCTUnwrap(alive.units.indices.first { alive.units[$0].kind == .tower && alive.units[$0].team == .red })
        let id = alive.units[ti].id
        var dead = alive
        dead.units[ti].hp = 0
        dead.units[ti].isAlive = false
        dead.units[ti].deathTime = 100

        let a = layer()
        var cues: [TowerCue] = []
        var t = 98.0
        while t < 101.2 {
            t += 1.0 / 60
            a.sync(frame(t >= 100 ? dead : alive, t: t))
            cues += a.structureCues.filter { $0.id == id }.map(\.cue)
            a.clearStructureCues()
        }
        XCTAssertEqual(cues.filter { $0 == .breakFlash }.count, 1)
        XCTAssertEqual(cues.filter { $0 == .crack }.count, 1)
        XCTAssertEqual(cues.filter { $0 == .toppleStart }.count, 1)

        let b = layer()
        b.sync(frame(alive, t: 40))
        b.resetForPresentationEpoch()
        b.sync(frame(dead, t: t))
        XCTAssertTrue(b.structureCues.filter { $0.id == id }.isEmpty, "シークで飛ばした区間の合図は出さない")
        let va = try XCTUnwrap(a.structure(id)), vb = try XCTUnwrap(b.structure(id))
        for part in TowerPart.allCases {
            XCTAssertEqual(va.partState(part).visible, vb.partState(part).visible, "\(part)")
            guard va.partState(part).visible else { continue }
            assertClose(va.partState(part).matrix, vb.partState(part).matrix, accuracy: 1e-3, "\(part)")
        }
        XCTAssertEqual(va.visiblePieces.shards, vb.visiblePieces.shards)
        XCTAssertEqual(va.visiblePieces.debris, vb.visiblePieces.debris)
        XCTAssertTrue(vb.isCollapsing, "deathTime のある状態では時刻どおりの倒れる途中")

        // 整理の後: 基壇と根元だけ
        b.sync(frame(dead, t: 100 + TowerTimeline.clearEnd + 0.5))
        XCTAssertTrue(vb.partState(.plinth).visible)
        XCTAssertTrue(vb.partState(.lower).visible)
        XCTAssertFalse(vb.partState(.upper).visible)
        XCTAssertFalse(vb.partState(.crystal).visible)
        XCTAssertEqual(vb.visiblePieces.shards + vb.visiblePieces.debris, 0)
        XCTAssertFalse(vb.isCollapsing)

        // 生きている状態へ戻ると元の姿（シーク・再同期）
        b.resetForPresentationEpoch()
        b.sync(frame(alive, t: 99))
        XCTAssertFalse(vb.destroyed)
        assertClose(vb.partState(.upper).matrix, matrix_identity_float4x4)
        XCTAssertTrue(vb.partState(.crystal).visible)
        XCTAssertTrue(vb.bar.root.isEnabled)
    }

    /// 被弾の演出: 同時 2 つまで、0.15 秒以内はまとめる、攻撃者の側に出す。壊れた後は出さない。
    func testHitsAreMergedCappedAndFaceTheAttacker() throws {
        StructureAssets.isEnabled = false
        let sim = Simulation(config: MatchFactory.botMatch(seed: 32))
        let l = layer()
        l.sync(frame(sim.state, t: 60))
        let tower = try XCTUnwrap(sim.state.units.first { $0.kind == .tower })
        let v = try XCTUnwrap(l.structure(tower.id))
        let east = v.root.position + SIMD3(6, 0, 0)
        let p = try XCTUnwrap(v.hitPoint(toward: east, time: 1.0))
        XCTAssertGreaterThan(p.x, v.root.position.x + 0.3, "攻撃者の側")
        XCTAssertNil(v.hitPoint(toward: east, time: 1.1), "0.15 秒以内はまとめる")
        XCTAssertNotNil(v.hitPoint(toward: east, time: 1.16))
        XCTAssertNil(v.hitPoint(toward: east, time: 1.32), "同時 2 つまで")
        XCTAssertEqual(v.activeHits(at: 1.32), 2)
        XCTAssertNotNil(v.hitPoint(toward: east, time: 1.7), "古い演出が終われば出せる")
    }

    /// 地鳴りは塔の数によらず 1 回。同時に鳴らす数には上限。画面外の塔の音は鳴らさない（Core の終幕は鳴らす）。
    func testStructureSoundsAreCappedAndRiseRumblesOnce() {
        let materials = RenderMaterials(colorblind: false)
        let fx = StructureFXDirector(vfx: VFXSystem(quality: .preset(.medium), materials: materials, meshes: UnitMeshLibrary()),
                                     materials: materials)
        var heard: [SFX] = []
        StructureAudio.sink = { sfx, _ in heard.append(sfx) }
        defer { StructureAudio.sink = nil }
        func ev(_ cue: TowerCue, _ i: Int, core: Bool = false) -> StructureCueEvent {
            StructureCueEvent(id: EntityID(i), team: .blue, isCore: core, style: .full, cue: cue, position: [Float(i), 0, 0], time: 0)
        }
        _ = fx.play((0..<18).map { ev(.riseStart, $0) }, now: 0, near: { _ in true }, listener: .zero, focus: nil, speed: 1)
        XCTAssertEqual(heard.filter { $0 == .towerRise }.count, 1)
        heard.removeAll()
        _ = fx.play((0..<6).map { ev(.impact, $0) }, now: 5, near: { _ in true }, listener: .zero, focus: nil, speed: 1)
        XCTAssertEqual(heard.count, StructureFXDirector.maxSoundsPerWindow)
        heard.removeAll()
        _ = fx.play([ev(.impact, 1)], now: 10, near: { _ in false }, listener: .zero, focus: nil, speed: 1)
        XCTAssertTrue(heard.isEmpty, "画面外の塔は鳴らさない")
        _ = fx.play([ev(.coreShockwave, 1, core: true)], now: 12, near: { _ in false }, listener: .zero, focus: nil, speed: 1)
        XCTAssertEqual(heard, [.towerImpact])
        heard.removeAll()
        _ = fx.play([ev(.impact, 1)], now: 20, near: { _ in true }, listener: .zero, focus: nil, speed: 8)
        XCTAssertTrue(heard.isEmpty, "4 倍速を超えると鳴らさない")
        // 近い着地は小さく揺らす。遠ければ揺らさない
        XCTAssertGreaterThan(fx.play([ev(.impact, 1)], now: 30, near: { _ in true }, listener: .zero, focus: [1, 0, 0], speed: 1), 0)
        XCTAssertEqual(fx.play([ev(.impact, 1)], now: 31, near: { _ in true }, listener: .zero, focus: [60, 0, 0], speed: 1), 0)
    }

    // MARK: 読み込み・従来モデルへの戻り・予算

    /// 部品の名前の付いた木構造（USDZ を読んだ後と同じ形）を作る。
    private func rigRoot(omit: TowerPart? = nil, heavyUpper: Bool = false, core: Bool = false) -> Entity {
        let root = Entity()
        root.name = "Struct_test"
        var pbr = PhysicallyBasedMaterial()
        pbr.baseColor = .init(tint: .gray)
        let boxes: [TowerPart: PartBox] = core ? [
            .plinth: PartBox(min: [-3.4, 0, -3.4], max: [3.4, 1.2, 3.4]),
            .upper: PartBox(min: [-3.0, 1.2, -3.0], max: [3.0, 4.5, 3.0]),
            .crystal: PartBox(min: [-1, 3.5, -1], max: [1, 6.5, 1]),
        ] : [
            .plinth: PartBox(min: [-1.6, 0, -1.6], max: [1.6, 0.7, 1.6]),
            .lower: PartBox(min: [-0.6, 0, -0.6], max: [0.6, 1.6, 0.6]),
            .upper: PartBox(min: [-0.7, 1.6, -0.7], max: [0.7, 3.8, 0.7]),
            .crown: PartBox(min: [-0.9, 3.8, -0.9], max: [0.9, 4.6, 0.9]),
            .crystal: PartBox(min: [-0.4, 4.7, -0.4], max: [0.4, 5.7, 0.4]),
        ]
        for (part, box) in boxes where part != omit {
            let holder = Entity()
            holder.name = part.rawValue
            let mesh: MeshResource
            if heavyUpper && part == .upper {
                var b = MeshBuilder()
                b.sphere(radius: 0.7, segments: 130, rings: 30, color: .solid(.stone))
                mesh = b.makeMesh(name: "heavy")!
            } else {
                mesh = MeshResource.generateBox(size: box.extents)
            }
            let e = ModelEntity(mesh: mesh, materials: [pbr])
            e.name = part.rawValue + "_geo"
            e.position = box.center
            holder.addChild(e)
            root.addChild(holder)
        }
        return root
    }

    func testRigAssemblesPartsByNameAndRejectsMissingOrOverBudget() throws {
        let rig = try XCTUnwrap(StructureAssets.assembleRig(.towerOuter, root: rigRoot(), redBase: nil, redEmit: nil))
        XCTAssertEqual(Set(rig.parts.keys), Set(TowerPart.allCases))
        let g = try XCTUnwrap(rig.geometry)
        XCTAssertEqual(g.plinthTop, 0.7, accuracy: 0.01)
        XCTAssertEqual(g.breakY, 1.6, accuracy: 0.01)
        XCTAssertEqual(g.crystal.center.y, 5.2, accuracy: 0.01)
        XCTAssertLessThanOrEqual(rig.bodyTriangles, StructureAssets.RigKind.bodyTriangleBudget)
        XCTAssertLessThanOrEqual(rig.crystalTriangles, StructureAssets.RigKind.crystalTriangleBudget)
        XCTAssertEqual(rig.blue.levels.count, StructureAssets.glowLevels.count)
        XCTAssertNotNil(StructureAssets.assembleRig(.starCore, root: rigRoot(core: true), redBase: nil, redEmit: nil))
        // 部品が欠ける・予算超過は使わない
        XCTAssertNil(StructureAssets.assembleRig(.towerOuter, root: rigRoot(omit: .crown), redBase: nil, redEmit: nil))
        XCTAssertNil(StructureAssets.assembleRig(.towerOuter, root: rigRoot(heavyUpper: true), redBase: nil, redEmit: nil))
        XCTAssertNil(StructureAssets.assembleRig(.starCore, root: rigRoot(omit: .crystal, core: true), redBase: nil, redEmit: nil))
        XCTAssertEqual(StructureAssets.RigKind.bodyTriangleBudget, 6000)
        XCTAssertEqual(StructureAssets.RigKind.crystalTriangleBudget, 2500)
    }

    /// 複数部品のモデルがあれば使い、無い・-legacyStructures なら従来のモデル（または手続き）へ戻る。
    func testVisualsUseRigsWhenLoadedAndFallBackOtherwise() throws {
        // 同梱が見つからない複数部品の塔は nil（従来のモデルの読み込みは続く）
        StructureAssets.resolver = { name, ext in name.hasPrefix("Struct_tower_") || name.hasPrefix("Struct_star_core") ? nil
            : Bundle.main.url(forResource: name, withExtension: ext) }
        for k in StructureAssets.RigKind.allCases { XCTAssertNil(StructureAssets.rig(k)) }

        let rig = try XCTUnwrap(StructureAssets.assembleRig(.towerOuter, root: rigRoot(), redBase: nil, redEmit: nil))
        StructureAssets.setRigForTesting(.towerOuter, rig)
        let sim = Simulation(config: MatchFactory.botMatch(seed: 33))
        let l = layer()
        l.sync(frame(sim.state, t: 30))
        let outer = try XCTUnwrap(sim.state.units.first { $0.kind == .tower && $0.tower?.tier == .outer })
        let inner = try XCTUnwrap(sim.state.units.first { $0.kind == .tower && $0.tower?.tier == .inner })
        let ov = try XCTUnwrap(l.structure(outer.id)), iv = try XCTUnwrap(l.structure(inner.id))
        XCTAssertEqual(ov.rigKind, .towerOuter)
        XCTAssertEqual(ov.generatedParts, 5)
        XCTAssertEqual(ov.muzzleHeight, 5.2, accuracy: 0.01, "発射点は結晶")
        XCTAssertGreaterThan(ov.bar.root.position.y, 5.7)
        XCTAssertTrue(ov.partState(.crown).visible)
        XCTAssertNil(iv.rigKind, "読み込めていない段は従来のモデルか手続き")

        StructureAssets.useLegacyModels = true
        XCTAssertNil(StructureAssets.rig(.towerOuter), "-legacyStructures で比べる")
        let legacy = layer()
        legacy.sync(frame(sim.state, t: 30))
        XCTAssertNil(try XCTUnwrap(legacy.structure(outer.id)).rigKind)
    }

    /// 実際の USD ファイル（部品ごとの Xform の下にメッシュ。Blender の書き出しと同じ形）を読み込みの経路で読み、
    /// 子の名前で部品を集める。赤のテクスチャが無くても読める。
    func testLoadsMultiPartUSDFileByPartNames() async throws {
        let parts: [(String, SIMD3<Float>, SIMD3<Float>)] = [
            ("part_plinth", [-1.6, 0, -1.6], [1.6, 0.7, 1.6]), ("part_lower", [-0.6, 0, -0.6], [0.6, 1.6, 0.6]),
            ("part_upper", [-0.7, 1.6, -0.7], [0.7, 3.8, 0.7]), ("part_crown", [-0.9, 3.8, -0.9], [0.9, 4.6, 0.9]),
            ("part_crystal", [-0.4, 4.7, -0.4], [0.4, 5.7, 0.4]),
        ]
        var usda = "#usda 1.0\n(\n    defaultPrim = \"Struct_tower_outer\"\n    metersPerUnit = 1\n    upAxis = \"Y\"\n)\n"
        usda += "def Xform \"Struct_tower_outer\"\n{\n"
        for (name, lo, hi) in parts {
            let pts = [SIMD3(lo.x, lo.y, lo.z), SIMD3(hi.x, lo.y, lo.z), SIMD3(hi.x, hi.y, lo.z), SIMD3(lo.x, hi.y, lo.z),
                       SIMD3(lo.x, lo.y, hi.z), SIMD3(hi.x, lo.y, hi.z), SIMD3(hi.x, hi.y, hi.z), SIMD3(lo.x, hi.y, hi.z)]
            let points = pts.map { "(\($0.x), \($0.y), \($0.z))" }.joined(separator: ", ")
            usda += """
                def Xform "\(name)"
                {
                    def Mesh "\(name)_geo" (
                        prepend apiSchemas = ["MaterialBindingAPI"]
                    )
                    {
                        int[] faceVertexCounts = [4, 4, 4, 4, 4, 4]
                        int[] faceVertexIndices = [0, 3, 2, 1, 4, 5, 6, 7, 0, 1, 5, 4, 2, 3, 7, 6, 1, 2, 6, 5, 0, 4, 7, 3]
                        point3f[] points = [\(points)]
                        uniform token subdivisionScheme = "none"
                        rel material:binding = </Struct_tower_outer/Looks/Stone>
                    }
                }

            """
        }
        usda += """
            def Scope "Looks"
            {
                def Material "Stone"
                {
                    token outputs:surface.connect = </Struct_tower_outer/Looks/Stone/PBR.outputs:surface>
                    def Shader "PBR"
                    {
                        uniform token info:id = "UsdPreviewSurface"
                        color3f inputs:diffuseColor = (0.42, 0.47, 0.42)
                        color3f inputs:emissiveColor = (0.05, 0.4, 0.45)
                        token outputs:surface
                    }
                }
            }
        }

        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Struct_tower_outer_test.usda")
        try usda.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        StructureAssets.resolver = { name, ext in
            if name == "Struct_tower_outer" && ext == "usdz" { return url }
            if name.hasPrefix("Struct_tower_outer") || name.hasPrefix("Struct_tower_inner") || name.hasPrefix("Struct_tower_base")
                || name.hasPrefix("Struct_star_core") { return nil }
            return Bundle.main.url(forResource: name, withExtension: ext)
        }
        await StructureAssets.load()
        let rig = try XCTUnwrap(StructureAssets.rig(.towerOuter), "部品の名前で集められる")
        XCTAssertEqual(Set(rig.parts.keys), Set(TowerPart.allCases))
        let g = try XCTUnwrap(rig.geometry)
        XCTAssertEqual(g.plinthTop, 0.7, accuracy: 0.01)
        XCTAssertEqual(g.breakY, 1.6, accuracy: 0.01)
        XCTAssertEqual(g.crown?.max.y ?? 0, 4.6, accuracy: 0.01)
        XCTAssertEqual(g.crystal.center.y, 5.2, accuracy: 0.01)
        XCTAssertNil(StructureAssets.rig(.towerInner), "無い段は従来のモデル")
        XCTAssertNotNil(StructureAssets.model(.tower), "従来のモデルも読む（戻り先）")
    }

    /// 1 基のエンティティ数と破片の数の上限（作るのは読み込み中だけ）。
    func testStructureEntityBudget() throws {
        StructureAssets.isEnabled = false
        let sim = Simulation(config: MatchFactory.botMatch(seed: 34))
        let l = layer()
        l.sync(frame(sim.state, t: 30))
        for u in sim.state.units where u.isStructure {
            let v = try XCTUnwrap(l.structure(u.id))
            XCTAssertLessThanOrEqual(v.entityCount, u.kind == .core ? 40 : 32, "\(u.kind)")
        }
        XCTAssertLessThanOrEqual(TowerPose.debrisCapacity(core: false), TowerTimeline.maxSmallDebris)
        XCTAssertLessThanOrEqual(TowerPose.debrisCapacity(core: true), TowerTimeline.maxSmallDebris)
    }
}
