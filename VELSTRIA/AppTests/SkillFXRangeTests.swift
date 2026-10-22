import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

// スキル演出の範囲（docs/vfx/RANGES.md）: 演出の「見える縁」と判定の縁を合わせる。
// - 縁の表（FXEdge）が実際の画像の不透明度の輪郭と 1 画素以内で一致する。
// - 全レシピが読むキットの値（FXSkillInfo.kit）が全部ある（Tune の値を写さずに読む）。
// - 全ヒーローのスキルを sim で撃ち（HitShapeScenario）、判定の時刻の範囲の部品の縁が判定の縁と ±3% で一致する
//   （FXRangeAudit）。ボルグ（H029）・ゴルム（H034）は食い違い 0。ほかのヒーローは今の食い違いを pending に挙げ、
//   レーンごとに直したら外す（新しい食い違いは失敗）。
// - 内部ビルドの判定の形の表示（HitShapeOverlay）: 形 → 線、弾の掃引をつなぐ、0.5 秒で消える、試合中に何も作らない。

@MainActor
final class SkillFXRangeTests: XCTestCase {
    private var master: MasterData { MasterData.shared }

    override func tearDown() {
        HitShapeProbe.sink = nil
        AssetLedger.end()
        super.tearDown()
    }

    // MARK: - 縁の表

    /// 画像の不透明度（0〜1）を読む。
    private func alphaMap(_ t: FXTex) throws -> (w: Int, h: Int, a: [Float]) {
        let img = try XCTUnwrap(FXTextureLibrary.image(t))
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try XCTUnwrap(CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (w, h, stride(from: 3, to: buf.count, by: 4).map { Float(buf[$0]) / 255 })
    }

    /// 円い模様の見える縁: 円周の平均の不透明度が最大の 1/3 以上になる最も外の半径（板の一辺に対する比）。
    func testRadialEdgeTableMatchesTheDrawnTextures() throws {
        for t in FXTex.allCases {
            guard let expected = FXEdge.radial(t) else { continue }
            let (w, h, a) = try alphaMap(t)
            let c = Float(w) / 2
            var profile: [Float] = []
            for ri in 0..<(w / 2) {
                let r = Float(ri) + 0.5
                var sum: Float = 0
                let n = 180
                for k in 0..<n {
                    let ang = Float(k) / Float(n) * 2 * .pi
                    let x = Int(c + r * cos(ang)), y = Int(c + r * sin(ang))
                    guard x >= 0, x < w, y >= 0, y < h else { continue }
                    sum += a[y * w + x]
                }
                profile.append(sum / Float(n))
            }
            let peak = profile.max() ?? 0
            let edge = profile.lastIndex { $0 >= peak * FXEdge.threshold } ?? 0
            let measured = (Float(edge) + 1) / Float(w)
            XCTAssertEqual(measured, expected, accuracy: 1.5 / Float(w), "\(t): 見える縁の半径（板の一辺に対する比）")
        }
    }

    /// 横長の模様の見える半幅: 行ごとの最大の不透明度が最大の 1/3 以上になる、中心から最も遠い行（板の縦に対する比）。
    func testLinearEdgeTableMatchesTheDrawnTextures() throws {
        for t in FXTex.allCases {
            guard let expected = FXEdge.linearHalfWidth(t) else { continue }
            let (w, h, a) = try alphaMap(t)
            let rows = (0..<h).map { y in (0..<w).map { a[y * w + $0] }.max() ?? 0 }
            let peak = rows.max() ?? 0
            let lit = rows.indices.filter { rows[$0] >= peak * FXEdge.threshold }
            let lo = Float(lit.min() ?? 0), hi = Float((lit.max() ?? 0) + 1)
            let measured = max(Float(h) / 2 - lo, hi - Float(h) / 2) / Float(h)
            XCTAssertEqual(measured, expected, accuracy: 1.5 / Float(h), "\(t): 見える半幅（板の縦に対する比）")
        }
    }

    /// 演出の大きさ・不透明度の式は再生（SkillFXPlayer.apply）と検査で同じ。
    func testMeshTimingHelpersFollowTheEaseAndFades() {
        let m = FXMesh(shape: .disc, tex: .ring, size: [1, 1, 1], sizeEnd: [3, 1, 3], ease: .linear, life: 1, fadeIn: 0.1,
                       fadeOut: 0.5)
        XCTAssertEqual(m.size(at: 0.5).x, 2, accuracy: 1e-5)
        XCTAssertEqual(m.opacity(at: 0.05), 0.5, accuracy: 1e-5)
        XCTAssertEqual(m.opacity(at: 0.3), 1, accuracy: 1e-5)
        XCTAssertEqual(m.opacity(at: 0.75), 0.5, accuracy: 1e-5)
        XCTAssertEqual(m.with { $0.spin = 90 }.yawDegrees(at: 0.5), 45, accuracy: 1e-4)
    }

    // MARK: - キットの値

    /// 全ヒーロー・全スロット・全段のレシピが読むキットの値は、全部 HeroKits.fxValues にある（読み違いは 0 で返すので、ここで見つける）。
    func testEveryRecipeReadsOnlyExistingKitValues() {
        FXSkillInfo.misses = []
        for hero in master.allHeroes {
            for slot in SkillSlot.allCases {
                _ = SkillFXCatalog.recipe(heroID: hero.heroID, slot: slot, master: master)
                for stage in 1...SkillFXCatalog.maxStage {
                    _ = SkillFXCatalog.stageRecipe(heroID: hero.heroID, slot: slot, stage: stage, master: master)
                }
            }
        }
        XCTAssertEqual(FXSkillInfo.misses, [], "キットに無い値を読んでいる（key の綴り・単位の違い）")
    }

    /// 演出の寸法は照準・判定と同じ値（ゴルムの S2 の半径・鉤の半幅、ボルグの再使用の扇）。
    func testSkillInfoCarriesTheJudgmentSizes() {
        let hook = SkillFXCatalog.info(heroID: "H034", slot: .skill1, master: master)
        XCTAssertEqual(hook.hitRadius, 0.35, accuracy: 1e-5, "鉤の半幅（照準・判定の 35）")
        XCTAssertEqual(hook.meters("hookWidth"), hook.hitRadius, accuracy: 1e-5)
        let shock = SkillFXCatalog.info(heroID: "H034", slot: .skill2, master: master)
        XCTAssertEqual(shock.meters("shockRadius"), shock.hitRadius, accuracy: 1e-5)
        let smash = SkillFXCatalog.info(heroID: "H029", slot: .skill2, stage: 1, master: master)
        XCTAssertEqual(smash.meters("smashReach"), smash.hitRadius, accuracy: 1e-5)
        XCTAssertEqual(smash.degrees("smashHalfAngle"), smash.halfAngle, accuracy: 1e-3)
    }

    // MARK: - 判定の縁と演出の縁

    /// 範囲の食い違いが残っているスキル（docs/vfx/RANGES.md の一覧）。レーンごとに直したら外す。
    /// TODO(range): 各レーンで演出を直したら、そのスキルをここから外す（ボルグ・ゴルムは直し済みで載せない）。
    /// 2026-10-18 の FXRangeAudit の結果（一覧と直し方は RANGES.md「食い違いの一覧」）。
    static let pending: Set<String> = [
        "H001 skill2", "H001 ultimate", "H002 skill2", "H004 ultimate",
        "H006 skill1", "H006 skill2", "H007 skill1", "H007 skill2", "H007 ultimate", "H008 skill2",
        "H010 skill1", "H010 ultimate", "H012 skill1", "H012 skill2", "H013 skill2", "H013 ultimate",
        "H014 skill2", "H016 ultimate", "H017 ultimate", "H018 skill2", "H019 skill2", "H019 ultimate",
        "H020 skill1", "H020 skill2", "H022 ultimate", "H024 skill1", "H024 skill2",
        "H025 skill2", "H026 ultimate", "H031 skill1", "H031 ultimate", "H033 ultimate",
    ]

    /// 直し済み（食い違い 0 でなければならない）。
    static let fixedHeroes: Set<String> = ["H029", "H034"]

    func testRangePartsMatchTheJudgmentEdges() {
        var unexpected: [String] = []
        var stale: [String] = []
        var seen = Set<String>()
        for hero in master.allHeroes.map(\.heroID).sorted() {
            let found = FXRangeAudit.audit(heroID: hero, master: master)
            for f in found {
                seen.insert(f.skillKey)
                if SkillFXRangeTests.fixedHeroes.contains(hero) || !SkillFXRangeTests.pending.contains(f.skillKey) {
                    unexpected.append(f.description)
                }
            }
        }
        for key in SkillFXRangeTests.pending where !seen.contains(key) { stale.append(key) }
        XCTAssertEqual(unexpected, [], "範囲の食い違い（判定の縁と演出の縁の差が ±3% を超える。docs/vfx/RANGES.md）")
        // 直ったスキルは pending から外す（失敗にはしない。一覧を最新に保つための知らせ）
        if !stale.isEmpty { print("SkillFXRangeTests: pending から外せるスキル: \(stale.sorted())") }
    }

    /// ゴルムの S2: 炎の舌の帯と外の赤い線は、叩きつけの瞬間に縁がちょうど判定の半径。鉤の頭の横幅は判定の幅。
    func testGolmShockRingAndHookHeadSitOnTheJudgmentEdge() throws {
        let trace = try XCTUnwrap(HitShapeScenario.run(heroID: "H034", slot: .skill2, master: master))
        XCTAssertEqual(FXRangeAudit.audit(trace: trace, master: master).map(\.description), [])
        let r = SkillFXCatalog.recipe(heroID: "H034", slot: .skill2, master: master)
        let s = SkillFXCatalog.info(heroID: "H034", slot: .skill2, master: master)
        let R = s.meters("shockRadius")
        var ringParts = 0
        for cue in r.impact {
            guard case .mesh(let m) = cue.element, let o = FXEdge.outline(m, size: m.size(at: 0)) else { continue }
            let far = o.map { ($0 * $0).sum().squareRoot() }.max() ?? 0
            guard far > R * 0.5 else { continue }
            ringParts += 1
            XCTAssertEqual(cue.at, s.seconds("shockDelay"), accuracy: 1e-5, "範囲の部品は叩きつけの瞬間に出る")
            XCTAssertEqual(far, R, accuracy: R * 0.03, "\(m.shape) \(m.tex.map(\.rawValue) ?? "")")
        }
        XCTAssertGreaterThanOrEqual(ringParts, 2, "炎の舌の帯と赤い線")
        let hook = SkillFXCatalog.recipe(heroID: "H034", slot: .skill1, master: master)
        let widths = hook.travel.compactMap { cue -> Float? in
            guard case .mesh(let m) = cue.element, let o = FXEdge.outline(m, size: m.size(at: 0)) else { return nil }
            // 横向きの板（yaw ±90）: 輪郭の y（板の前後）が横幅
            return o.map { abs(abs(m.yaw) == 90 ? $0.y : $0.x) }.max()
        }
        XCTAssertEqual(widths.max() ?? 0, 0.35, accuracy: 0.35 * 0.03, "鉤の頭の見える半幅 = 判定の半幅 0.35m")
    }

    // MARK: - 判定の形の表示

    func testOverlaySegmentsFollowTheJudgmentShapes() {
        let circle = HitShapeOverlay.segments(.circle(center: Vec2(100, 0), radius: 257, inner: 0))
        XCTAssertEqual(circle.count, HitShapeOverlay.circleSegments)
        for (a, _) in circle { XCTAssertEqual(a.distance(to: Vec2(100, 0)), 257, accuracy: 1e-6) }
        let cone = HitShapeOverlay.segments(.cone(center: .zero, direction: Vec2(0, 1), radius: 215, halfAngle: 0.8, inner: 0))
        XCTAssertTrue(cone.contains { $0.0 == .zero }, "扇の両端の辺は頂点から")
        let capsule = HitShapeOverlay.segments(.line(from: .zero, to: Vec2(0, 300), halfWidth: 35, squareEnds: false))
        XCTAssertEqual(capsule[0].0.x, -35, accuracy: 1e-6)
        XCTAssertEqual(capsule[1].0.x, 35, accuracy: 1e-6)
        let band = HitShapeOverlay.segments(.polygon([Vec2(-1, 0), Vec2(-2, 5), Vec2(2, 5), Vec2(1, 0)]))
        XCTAssertEqual(band.count, 4)
    }

    /// 弾の毎 tick の掃引は 1 本につながり、0.5 秒で消える。試合中は何も作らない。ゴルムの S2 は半径 257 の円が出る。
    func testOverlayMergesSweepsFadesAndCreatesNothingWhileLive() {
        let config = MatchFactory.practiceMatch(humanHeroID: "H034", humanName: "P",
                                                options: PracticeOptions(noCooldowns: true, spawnMinions: false,
                                                                         startLevel: 4), seed: 3)
        let c = BattleController(launch: BattleLaunch(config: config))
        AssetLedger.beginLoading()
        let overlay = HitShapeOverlay(controller: c)
        AssetLedger.beginLive()
        overlay.attach()
        XCTAssertTrue(HitShapeProbe.isActive)
        // 掃引をつなぐ
        for k in 0..<5 {
            let a = Vec2(0, Double(k) * 50), b = Vec2(0, Double(k + 1) * 50)
            overlay.receive(HitShape(form: .line(from: a, to: b, halfWidth: 35, squareEnds: false), kind: .projectile,
                                     team: .blue, sourceID: 1, source: .skill(.skill1), trackID: 77, time: Double(k)))
        }
        overlay.update(dt: 1.0 / 30)
        XCTAssertEqual(overlay.items.count, 1)
        if case .line(let a, let b, _, _) = overlay.items.first?.shape.form {
            XCTAssertEqual(a, Vec2(0, 0))
            XCTAssertEqual(b, Vec2(0, 250))
        } else {
            XCTFail("掃引が線にならない")
        }
        XCTAssertGreaterThan(overlay.quadCounts[.blue] ?? 0, 0)
        for _ in 0..<20 { overlay.update(dt: 1.0 / 30) }
        XCTAssertTrue(overlay.items.isEmpty, "0.5 秒で消える")
        // 実際の試合の判定（ゴルムの S2）
        guard let me = c.humanHeroID else { return XCTFail("ヒーローが居ない") }
        for _ in 0..<15 { c.frame(dt: 1.0 / 30) }
        c.send(.castSkill(slot: .skill2, target: .none))
        var radii: [Double] = []
        for _ in 0..<30 {
            c.frame(dt: 1.0 / 30)
            overlay.update(dt: 1.0 / 30)
            for item in overlay.items where item.shape.sourceID == me {
                if case .circle(_, let r, _) = item.shape.form { radii.append(r) }
            }
        }
        XCTAssertTrue(radii.contains { abs($0 - 257) < 1e-6 }, "ゴルムの S2 の円（半径 257）が出る: \(radii)")
        overlay.detach()
        XCTAssertFalse(HitShapeProbe.isActive)
        let snap = AssetLedger.snapshot()
        XCTAssertEqual(snap.liveTotal, 0, "プレイ中の生成: \(snap.live)")
    }
}
