import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// キットの強い通常攻撃（H027 子龍の三連突き・H032 ディアスの円撃。SimEvent.empoweredAttack）の見せ方・音・手応え・モーション。
/// 数え方と合図の時刻は Core の EmpoweredAttackTests（合図の円 = sim が判定した円、三連突きの 2・3 発目 = 合図の interval）。
/// ここでは演出の縁（判定の半径・伸びた射程と ±3%。docs/vfx/RANGES.md）、次が強いと分かる目印、音のファイル、
/// ヒットストップ、強い通常攻撃の全身のモーション（打撃のキー = sim の命中の時刻）を確かめる。
@MainActor
final class EmpoweredAttackFXTests: XCTestCase {
    private var master: MasterData { MasterData.shared }
    private static let heroes = ["H027", "H032"]

    override func tearDown() {
        AssetLedger.end()
        super.tearDown()
    }

    private func cues(_ id: String) throws -> [FXCue] {
        try XCTUnwrap(SkillFXCatalog.empoweredAttack(heroID: id, master: master), "\(id) の強い通常攻撃の演出")
    }

    private func info(_ id: String) -> FXSkillInfo { SkillFXCatalog.info(heroID: id, slot: .passive, master: master) }

    // MARK: - 演出の縁

    /// 円撃: 判定の瞬間（0 秒）に、縁がちょうど判定の半径（Kit の circleRadius = sim の判定の円）の輪が出て、外へは消えながら広がる。
    /// FXRangeAudit（スキルと同じ測り方: 縁 ±3%・はみ出し・遅れ・消えずに外へ）で食い違い 0。
    func testDyrrothCircleRingSitsOnTheJudgedRadius() throws {
        let s = info("H032")
        FXSkillInfo.misses = []
        let list = try cues("H032")
        XCTAssertEqual(FXSkillInfo.misses, [], "キットの値を読み違えた")
        let R = s.meters("circleRadius")
        XCTAssertEqual(R, 2.0, accuracy: 1e-5, "Kit_H032 の円撃の半径 200（MLBB の渦の外縁 2.0〜2.1）")
        let ctx = FXRangeAudit.Context(phase: .impact, stage: 0, t0: 0, origin: [0, 0], caster: [0, 0], target: [0, 1.5],
                                       forward: [0, 1], follow: nil, cues: list)
        var compared: [String] = []
        FXRangeAudit.log = { compared.append($0) }
        defer { FXRangeAudit.log = nil }
        let findings = FXRangeAudit.measure(form: .circle(center: [0, 0], radius: R), judgmentTime: 0, ctx: ctx,
                                            heroID: "H032", slot: .passive)
        XCTAssertEqual(findings.map(\.description), [])
        XCTAssertGreaterThanOrEqual(compared.count, 2, "縁の輪（模型と模様の板）を比べた: \(compared)")
        // 縁を示す部品は判定の瞬間（0 秒）に、見える縁がちょうど R
        var edges = 0
        for cue in list {
            guard case .mesh(let m) = cue.element, FXRangeAudit.isGroundPart(m, offsetY: cue.offset.y),
                  let o = FXEdge.outline(m, size: m.size(at: 0)) else { continue }
            let far = o.map { ($0 * $0).sum().squareRoot() }.max() ?? 0
            guard far > R * 0.5 else { continue }
            edges += 1
            XCTAssertEqual(cue.at, 0, accuracy: 1e-5, "判定の瞬間に出る")
            XCTAssertEqual(far, R, accuracy: R * 0.03, "\(m.shape) \(m.tex.map(\.rawValue) ?? "")")
        }
        XCTAssertGreaterThanOrEqual(edges, 2)
    }

    /// 三連突き: 突きの筋は sim の命中の時刻（0 / flurryInterval / 2 × flurryInterval）に 3 本、伸びた射程の端
    /// （通常攻撃の射程 1.8 + 伸び 0.7 + 術者の半径 = 対象の縁が届く距離）まで届く（±3%）。
    func testZilongThrustsLandOnTheSimHitsAndReachTheExtendedRange() throws {
        let s = info("H027")
        FXSkillInfo.misses = []
        let list = try cues("H027")
        XCTAssertEqual(FXSkillInfo.misses, [])
        let gap = s.seconds("flurryInterval")
        XCTAssertEqual(gap, Float(4 * Balance.dt), accuracy: 1e-5, "4 tick（画面収録の 4 コマ）")
        let reach = FX_H027.flurryReach(s)
        XCTAssertEqual(reach, 1.8 + 0.7 + Float(Balance.heroRadius / 100), accuracy: 1e-4)
        var streaks = 0
        for cue in list {
            guard case .mesh(let m) = cue.element, m.tex == .streak else { continue }
            streaks += 1
            // 横長の模様の見える前の端（板を yaw ≈ 90 で前へ向けている。向きの差 ±7° の分だけ短い）
            let far = cue.offset.z + FXEdge.linearHalfLength * m.size.x
            XCTAssertEqual(far, reach, accuracy: reach * 0.03, "筋の前の端 = 伸びた射程")
            if cue.count > 1 {
                XCTAssertEqual(cue.count, s.count("flurryHits"))
                XCTAssertEqual(cue.every, gap, accuracy: 1e-5, "突くたびに = sim の命中の間隔")
            }
        }
        XCTAssertGreaterThanOrEqual(streaks, 3, "水色の筋・白い芯・足元の筋")
        let repeated = list.filter { $0.count == 3 && abs($0.every - gap) < 1e-5 }
        XCTAssertGreaterThanOrEqual(repeated.count, 4, "筋・芯・穂先の閃き・対象の閃きが 3 発ぶん")
    }

    /// 次が強いと分かる目印（自分だけの足元の円）: メッシュだけ（CI のシミュレータにも写る）・消せる組・出し直しの間隔より長い寿命、
    /// 円の縁は「届く距離」（子龍 = 伸びた射程、ディアス = 円撃の判定の半径）と ±3%。
    func testReadyMarkersAreGroundRingsAtTheReach() throws {
        for id in Self.heroes {
            let s = info(id)
            let list = try XCTUnwrap(SkillFXCatalog.empoweredReady(heroID: id, master: master), id)
            let reach = id == "H027" ? FX_H027.flurryReach(s) : FX_H032.circleRadius(s)
            var rings = 0
            for cue in list {
                guard case .mesh(let m) = cue.element else { return XCTFail("\(id): 目印はメッシュだけ") }
                XCTAssertEqual(m.group, SkillFXCatalog.empoweredReadyGroup, id)
                XCTAssertEqual(cue.anchor, .follow, id)
                XCTAssertGreaterThan(m.life * m.fadeOut, SkillFXCatalog.empoweredReadyPeriod, "\(id): 出し直す前に消え始めない")
                XCTAssertLessThanOrEqual(m.life, 4, id)
                guard let r = FXEdge.radial(m.tex ?? .glow) else { continue }
                rings += 1
                XCTAssertEqual(r * m.size.x, reach, accuracy: reach * 0.03, "\(id): 足元の円 = 届く距離")
                XCTAssertEqual(m.size, m.sizeEnd, "\(id): 目印の円は大きさを変えない")
            }
            XCTAssertEqual(rings, 1, id)
        }
        // 強い通常攻撃を持たないヒーローは何も出さない
        XCTAssertNil(SkillFXCatalog.empoweredAttack(heroID: "H029", master: master))
        XCTAssertNil(SkillFXCatalog.empoweredReady(heroID: "H001", master: master))
    }

    /// 予算（スキルのレシピと同じ上限）と、準備してから再生してもプレイ中に何も作らないこと。
    func testEmpoweredCuesRespectBudgetsAndCreateNothingWhileLive() throws {
        var all: [(palette: FXPalette, recipe: SkillFXRecipe)] = []
        for id in Self.heroes {
            for list in [try cues(id), try XCTUnwrap(SkillFXCatalog.empoweredReady(heroID: id, master: master))] {
                var meshes = 0, emits = 0
                for cue in list {
                    switch cue.element {
                    case .mesh(let m):
                        meshes += max(1, cue.count)
                        XCTAssertLessThanOrEqual(m.life, 4, id)
                        XCTAssertLessThanOrEqual(max(m.sizeEnd.x, m.sizeEnd.z), 16, id)
                    case .emit(let e):
                        emits += max(1, cue.count)
                        XCTAssertLessThanOrEqual(e.count, 60, id)
                        XCTAssertLessThanOrEqual(e.life, 3, id)
                    case .ribbon(let r):
                        meshes += max(1, cue.count)
                        XCTAssertLessThanOrEqual(r.span, 4, id)
                    case .shake(let k):
                        XCTAssertLessThanOrEqual(k, 0.3, "\(id): 通常攻撃の揺れは小さく")
                    case .efk:
                        break
                    }
                    XCTAssertLessThanOrEqual(cue.at + cue.every * Float(max(0, cue.count - 1)), 1, id)
                }
                XCTAssertLessThanOrEqual(meshes, 20, id)
                XCTAssertLessThanOrEqual(emits, 13, id)
                var r = SkillFXRecipe()
                r.cast = list
                all.append((SkillFXCatalog.palette(id), r))
            }
        }
        AssetLedger.beginLoading()
        let player = SkillFXPlayer(quality: .preset(.high))
        player.prewarm(recipes: all)
        player.resolve = { _ in SIMD3<Float>(1, 0, 1) }
        AssetLedger.beginLive()
        for (palette, r) in all {
            let ctx = SkillFXPlayer.Context(palette: palette, origin: .zero, caster: .zero, target: [0, 0, -2], forward: [0, 0, -1],
                                            follow: .unit(1))
            player.play(r.cast, ctx)
            for _ in 0..<3 { player.update(dt: 1.0 / 30) }
        }
        player.cut(follow: .unit(1), group: SkillFXCatalog.empoweredReadyGroup)
        for _ in 0..<150 { player.update(dt: 1.0 / 30) }
        let snap = AssetLedger.snapshot()
        XCTAssertEqual(snap.liveTotal, 0, "プレイ中の生成: \(snap.live)")
        XCTAssertEqual(player.activeCount, 0)
    }

    // MARK: - 手応え・音

    /// 軽いヒットストップ 40 ms: 自分が撃った・受けた強い通常攻撃で、相手が英雄・人形の時だけ。
    func testEmpoweredAttackHoldsLightlyOnlyWhenIAmInvolved() {
        XCTAssertEqual(BattleFeel.empoweredHoldSeconds(byMe: true, onMe: false, targetIsHero: true), 0.04)
        XCTAssertEqual(BattleFeel.empoweredHoldSeconds(byMe: false, onMe: true, targetIsHero: true), 0.04)
        XCTAssertNil(BattleFeel.empoweredHoldSeconds(byMe: true, onMe: false, targetIsHero: false), "狩りでは止めない")
        XCTAssertNil(BattleFeel.empoweredHoldSeconds(byMe: false, onMe: false, targetIsHero: true), "自分が関わらない")
        XCTAssertLessThanOrEqual(BattleFeel.empoweredHold, BattleFeel.maxHold)
    }

    /// 強い通常攻撃の音（録音）: 振り（揺らぎ 2）と命中（揺らぎ 3）。命中の音に替える窓は三連突きの 3 発目まで。
    func testEmpoweredSoundsAreBundled() {
        for id in Self.heroes {
            for (phase, count) in [(SkillSoundKey.Phase.empowered, 2), (.empoweredHit, 3)] {
                let base = SkillSoundKey(heroID: id, phase: phase).fileName
                XCTAssertEqual(base, "skill_\(id)_\(phase.rawValue)")
                for k in 1...count { XCTAssertNotNil(AudioFiles.sfxURL("\(base)_\(k)"), "\(base)_\(k).caf が無い") }
            }
        }
        XCTAssertTrue(SkillSoundKey(heroID: "H027", phase: .empoweredHit).hit)
        XCTAssertFalse(SkillSoundKey(heroID: "H027", phase: .empowered).hit)
        XCTAssertNil(WeaponSoundSet.of(heroID: "H027")?.fileName(.empowered), "武器の組の音で代えない")
        let flurry = EmpoweredAttackEvent(sourceID: 1, targetID: 2, heroID: "H027", hits: 3, interval: 4 * Balance.dt, radius: 0,
                                          reach: 250, origin: .zero)
        let w = BattleAudioDirector.empoweredHitWindow(flurry)
        XCTAssertGreaterThanOrEqual(w, 8 * Balance.dt, "3 発目（8 tick 後）まで")
        XCTAssertLessThan(w, 15 * Balance.dt, "次の通常攻撃（15 tick 以上後）は含まない")
    }

    // MARK: - モーション

    private func profile(_ id: String) -> HeroMotionProfile {
        let bp = HeroBlueprints.blueprint(heroID: id, role: master.hero(id)?.role)
        return HeroMotionProfile(blueprint: bp, metrics: BodyMetrics.make(bp.build), heroID: id)
    }

    /// 三連突きの 3 回の突き切り = sim の命中（打撃 = 1 発目、+flurryInterval、+2 × flurryInterval）。円撃は 1 回転（2π）して
    /// 戻りで巻き戻さない。普段の通常攻撃・詠唱は変わらない（強い通常攻撃のモーションは H027・H032 だけ）。
    func testEmpoweredMotionsStrikeOnTheSimHits() throws {
        KitTimes.misses = []
        let zilong = try XCTUnwrap(profile("H027").empoweredAttack)
        let impact = try XCTUnwrap(zilong.impact)
        let gap = Float(4 * Balance.dt)
        for n in 0..<3 {
            let t = impact + gap * Float(n)
            XCTAssertTrue(zilong.keys.contains { abs($0.time - t) < 1e-3 }, "\(n + 1) 発目の突き切りのキーが \(t) 秒に無い")
        }
        XCTAssertGreaterThan(zilong.total - impact, 0.33, "戻りは sim の攻撃状態（命中から 0.32 秒）より長い")
        let dias = try XCTUnwrap(profile("H032").empoweredAttack)
        XCTAssertNotNil(dias.impact)
        XCTAssertTrue(dias.wrapsYaw)
        XCTAssertTrue(dias.fullBody)
        XCTAssertEqual(dias.keys.last?.pose.yaw ?? 0, 2 * .pi, accuracy: 1e-4, "1 回転")
        // 戻りの途中も 2π の近く（逆回りに巻き戻さない）
        let mid = dias.evaluate(base: profile("H032").rest, t: (dias.keys.last!.time + dias.total) / 2)
        XCTAssertEqual(mid.yaw, 2 * .pi, accuracy: 0.01)
        XCTAssertEqual(KitTimes.misses, [])
        for def in master.allHeroes where !Self.heroes.contains(def.heroID) {
            XCTAssertNil(profile(def.heroID).empoweredAttack, def.heroID)
        }
        // 普段の通常攻撃（全身のモーション）は増えない
        XCTAssertTrue(profile("H027").attackMotions.isEmpty)
        XCTAssertTrue(profile("H032").attackMotions.isEmpty)
    }

    /// 強い通常攻撃のときだけ全身のモーションで振り、普段の通常攻撃が来たら打ち切る。打撃は windup 秒後。
    func testAnimatorPlaysTheEmpoweredMotionOnlyForTheEmpoweredAttack() {
        for id in Self.heroes {
            var a = HeroAnimator(profile: profile(id), defaultRunSpeed: 3.3)
            a.setState(.attack)
            a.playAttack(windup: 0.2, interval: 0.8, empowered: false)
            _ = a.advance(dt: 1.0 / 60, moveSpeed: 0)
            XCTAssertFalse(a.playsEmpoweredAttack, id)
            a.playAttack(windup: 0.2, interval: 0.8, empowered: true)
            _ = a.advance(dt: 1.0 / 60, moveSpeed: 0)
            XCTAssertTrue(a.playsEmpoweredAttack, id)
            var swung = false
            var t: Float = 1.0 / 60
            while t < 0.26 {
                _ = a.advance(dt: 1.0 / 60, moveSpeed: 0)
                t += 1.0 / 60
                if a.weaponSwing.right || a.weaponSwing.left { swung = true }
            }
            XCTAssertTrue(swung, "\(id): 打撃（windup 0.2 秒）の前後で武器を振る")
            a.playAttack(windup: 0.2, interval: 0.8)
            _ = a.advance(dt: 1.0 / 60, moveSpeed: 0)
            XCTAssertFalse(a.playsEmpoweredAttack, "\(id): 普段の通常攻撃で打ち切る")
        }
    }
}
