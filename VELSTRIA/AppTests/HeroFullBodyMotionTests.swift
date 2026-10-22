import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 全身のモーション（HeroSkillMotions: 詠唱・再使用の段・命中の後・通常攻撃。足の接地 HeroLegRig）の検査
/// （docs/HERO_MOTION.md「全身のモーション」）。
/// - 既定のヒーロー（スクリプトの無い 32 体）の詠唱モーションは変わらない（足の接地・移動中の下半身の戻し・段のモーションが無い）。
/// - 打撃のキーが sim の判定の時刻（HeroKits.fxValues = キットの Tune。照準・判定・演出と同じ読み取り口）にある。
/// - 体の位置（描画だけのずれ）はクリップの終わりで 0 へ戻り、足首は地面より下へ入らない（同梱のスキンメッシュの骨で測る）。
/// - 再使用の段は同じスロットの詠唱中でも始め直し、命中の後のモーションは 1 回の詠唱で 1 度だけ。
/// - 全身の通常攻撃の打撃（武器の軌跡の振り）は playAttack の windup 秒後に来る。
@MainActor
final class HeroFullBodyMotionTests: XCTestCase {
    private let master = MasterData.shared
    private static let scripted = ["H029", "H034"]
    /// 通常攻撃を専用の収録（HeroMotionSet.dedicatedAttack のクリップ。H029MotionClipTests 等）で振るヒーロー。
    /// 全身の手続きの通常攻撃（Motion_H0xx.attacks）は profile に載らない。
    private static func clipAttack(_ id: String) -> Bool { HeroMotionSets.table[id]?.dedicatedAttack == true }

    private func profile(_ id: String) -> HeroMotionProfile {
        let bp = HeroBlueprints.blueprint(heroID: id, role: master.hero(id)?.role)
        return HeroMotionProfile(blueprint: bp, metrics: BodyMetrics.make(bp.build), heroID: id)
    }

    private func animator(_ id: String) -> HeroAnimator {
        let bp = HeroBlueprints.blueprint(heroID: id, role: master.hero(id)?.role)
        let m = BodyMetrics.make(bp.build)
        var a = HeroAnimator(profile: HeroMotionProfile(blueprint: bp, metrics: m, heroID: id), defaultRunSpeed: 3.3)
        a.legRig = HeroLegRig(metrics: m, scale: bp.scale, rest: a.profile.rest)
        return a
    }

    /// 全てのモーション（詠唱・段・命中の後・通常攻撃）と名前。
    private func motions(_ p: HeroMotionProfile) -> [(String, MotionClip)] {
        var out: [(String, MotionClip)] = []
        for (k, slot) in ["s1", "s2", "ult"].enumerated() {
            out.append((slot, p.casts[k]))
            for (i, c) in p.recasts[k].enumerated() { out.append(("\(slot)r\(i + 1)", c)) }
            if let c = p.hitFollowUps[k] { out.append(("\(slot)hit", c)) }
        }
        for (i, c) in p.attackMotions.enumerated() { out.append(("atk\(i + 1)", c)) }
        return out
    }

    // MARK: 既定のヒーローは変わらない

    func testHeroesWithoutScriptKeepTheirMotions() {
        for def in master.allHeroes where !Self.scripted.contains(def.heroID) {
            let p = profile(def.heroID)
            XCTAssertTrue(p.recasts.allSatisfy(\.isEmpty), "\(def.heroID) に段のモーションがある")
            XCTAssertTrue(p.hitFollowUps.allSatisfy { $0 == nil }, "\(def.heroID) に命中の後のモーションがある")
            XCTAssertTrue(p.attackMotions.isEmpty, "\(def.heroID) に全身の通常攻撃がある")
            for (k, c) in p.casts.enumerated() {
                XCTAssertFalse(c.yieldsLowerWhenMoving, "\(def.heroID) 詠唱 \(k) が移動中に下半身を戻す（既定は従来どおり）")
                XCTAssertTrue(c.keys.allSatisfy { $0.pose.plant == 0 }, "\(def.heroID) 詠唱 \(k) が足を接地させる")
                XCTAssertNil(c.simLock, "\(def.heroID) 詠唱 \(k)")
                // 演出の定義（FX_H0xx.motion）と同じ（スクリプトの目録を通っても変わらない）
                let bp = HeroBlueprints.blueprint(heroID: def.heroID, role: def.role)
                let builder = MotionBuilder(rest: p.rest, style: bp.attack, shield: p.shieldHold, twoHanded: bp.twoHanded,
                                            bow: p.bowHold)
                let slot = SkillSlot.actives[k]
                if let set = SkillFXCatalog.sets[def.heroID] {
                    var m = builder
                    set.motion(slot, &m)
                    if !m.keys.isEmpty {
                        XCTAssertEqual(c.keys.count, m.keys.count, "\(def.heroID) \(slot)")
                    }
                }
            }
            var a = HeroAnimator(profile: p, defaultRunSpeed: 3.3)
            XCTAssertFalse(a.castRestarts(.skill2, stage: 1), def.heroID)
            a.setState(.cast(.skill1))
            _ = a.advance(dt: 0.1, moveSpeed: 0)
            XCTAssertNil(a.playCastHit(.skill1), def.heroID)
        }
    }

    // MARK: 打撃の時刻 = sim の判定

    func testStrikeKeysSitOnSimTimes() throws {
        // sim の時刻は判定と同じ 1 つの読み取り口（HeroKits.fxValues = Tune）から読む
        func v(_ hero: String, _ slot: SkillSlot, _ key: String, stage: Int = 0) throws -> Double {
            try XCTUnwrap(HeroKits.fxValues(heroID: hero, slot: slot, stage: stage).first { $0.key == key }?.value,
                          "\(hero) \(slot) \(stage) の fxValues に \(key) が無い")
        }
        func near(_ a: Float?, _ b: Double, _ label: String) {
            XCTAssertEqual(a ?? -1, Float(b), accuracy: 1e-3, label)
        }
        KitTimes.misses = []
        let borg = profile("H029")
        near(borg.casts[0].impact, try v("H029", .skill1, "waveFirstDelay"), "ボルグ S1 の叩きつけ = 1 回目の衝撃波")
        near(borg.casts[1].impact, try v("H029", .skill2, "dashRange") / v("H029", .skill2, "dashSpeed"),
             "ボルグ S2 の盾の押し込み = 突進の終わり")
        near(try XCTUnwrap(borg.recasts[1].first).impact, try v("H029", .skill2, "smashDelay", stage: 1),
             "ボルグ S2 の再使用の振り上げ = 打ち上げ")
        near(borg.casts[2].impact, try v("H029", .ultimate, "ultTotal"), "ボルグ 奥義の叩き落とし = 崩落")
        XCTAssertEqual(borg.attackMotions.count, Self.clipAttack("H029") ? 0 : 1)

        let golm = profile("H034")
        near(golm.casts[0].impact, try v("H034", .skill1, "hookDelay"), "ゴルム S1 の投げ放ち = 鉤が飛ぶ")
        near(try XCTUnwrap(golm.hitFollowUps[0]).impact, try v("H034", .skill1, "hookHold"), "ゴルム S1 の引き = 命中からの引き寄せ")
        near(golm.casts[1].impact, try v("H034", .skill2, "shockDelay"), "ゴルム S2 の叩きつけ")
        let ult = golm.casts[2]
        let grab = try v("H034", .ultimate, "ultDelay") + v("H034", .ultimate, "ultFirst")
        let gap = try v("H034", .ultimate, "ultInterval")
        let hits = Int(try v("H034", .ultimate, "ultHits"))
        near(ult.impact, grab + gap * Double(hits - 1), "ゴルム 奥義の 6 撃目")
        for k in 0..<hits {
            let t = Float(grab + gap * Double(k))
            XCTAssertTrue(ult.keys.contains { abs($0.time - t) < 1e-3 }, "ゴルム 奥義の \(k + 1) 撃目（\(t) 秒）にキーが無い")
        }
        near(ult.simLock, try v("H034", .ultimate, "ultDelay") + v("H034", .ultimate, "ultSuppress"), "ゴルム 奥義の拘束")
        XCTAssertEqual(golm.attackMotions.count, Self.clipAttack("H034") ? 0 : 2, "フランコの通常攻撃は左右交互の 2 拍")
        XCTAssertTrue(KitTimes.misses.isEmpty, "モーションが読むキットの値が fxValues に無い: \(KitTimes.misses.sorted())")
    }

    // MARK: 体の位置は 0 へ戻り、足は地面より下へ入らない（手続きの寸法）

    func testOffsetReturnsToZeroAndFeetStayAboveGround() {
        for id in Self.scripted {
            let p = profile(id)
            let bp = HeroBlueprints.blueprint(heroID: id, role: master.hero(id)?.role)
            let rig = HeroLegRig(metrics: BodyMetrics.make(bp.build), scale: bp.scale, rest: p.rest)
            for (name, c) in motions(p) {
                XCTAssertTrue(c.fullBody, "\(id) \(name) が全身でない")
                XCTAssertTrue(c.yieldsLowerWhenMoving, "\(id) \(name) が移動中に下半身を戻さない")
                var t: Float = 0
                var lowest: Float = 1
                var farthest: Float = 0
                while t <= c.total {
                    var q = c.evaluate(base: p.rest, t: t)
                    rig.applyPlant(&q)
                    let h = rig.ankleHeights(q)
                    lowest = min(lowest, h.right, h.left)
                    farthest = max(farthest, simd_length(SIMD3(q.offset.x, 0, q.offset.z)))
                    XCTAssertFalse(q.offset.x.isNaN || q.legR.knee.isNaN || q.legL.pitch.isNaN, "\(id) \(name) NaN")
                    t += 1.0 / 60.0
                }
                XCTAssertGreaterThan(lowest, -0.002, "\(id) \(name): 足首が地面より下 \(lowest) m")
                XCTAssertLessThan(farthest, 0.6, "\(id) \(name): 体が sim の位置から離れすぎる \(farthest) m")
                let end = c.evaluate(base: p.rest, t: c.total)
                XCTAssertEqual(simd_length(end.offset), 0, accuracy: 1e-5, "\(id) \(name): 終わりで体の位置が戻らない")
                XCTAssertEqual(end.plant, 0, "\(id) \(name): 終わりで接地が残る")
                // 戻りの直前（終わりの 0.03 秒前）もほぼ戻っている
                let near = c.evaluate(base: p.rest, t: max(0, c.total - 0.03))
                XCTAssertLessThan(simd_length(near.offset), 0.05, "\(id) \(name): 戻りが急すぎる")
            }
        }
    }

    /// 足の接地の IK: 待機の立ち位置を目標にすると待機の脚に戻り、届く目標には 1 mm 以内に置く。
    func testLegRigReachesTargetsAndKeepsRest() {
        let bp = HeroBlueprints.blueprint(heroID: "H029", role: nil)
        let m = BodyMetrics.make(bp.build)
        let rest = profile("H029").rest
        let rig = HeroLegRig(metrics: m, scale: bp.scale, rest: rest)
        var r = rest
        r.plant = 1
        rig.applyPlant(&r)
        XCTAssertEqual(r.legR.pitch, rest.legR.pitch, accuracy: 0.01)
        XCTAssertEqual(r.legR.knee, rest.legR.knee, accuracy: 0.02)
        XCTAssertEqual(r.legL.out, rest.legL.out, accuracy: 0.01)
        XCTAssertEqual(r.offset.y, 0, accuracy: 1e-4)
        var rng = SplitMix64(seed: 0xF00D)
        let leg = rig.thigh + rig.shin
        var checked = 0
        for _ in 0..<400 {
            var p = rest
            p.plant = 1
            p.hipsDrop = Float.random(in: 0...0.12, using: &rng)
            p.hipsYaw = Float.random(in: -0.4...0.4, using: &rng)
            p.hipsPitch = Float.random(in: 0...0.4, using: &rng)
            p.offset = SIMD3(Float.random(in: -0.1...0.1, using: &rng), 0, Float.random(in: -0.2...0.2, using: &rng))
            p.footR = SIMD3(Float.random(in: -0.05...0.1, using: &rng), Float.random(in: 0...0.1, using: &rng),
                            Float.random(in: -0.3...0.2, using: &rng))
            p.footL = SIMD3(Float.random(in: -0.1...0.05, using: &rng), 0, Float.random(in: -0.3...0.2, using: &rng))
            // 腿の付け根（体の回転なし: 体の位置 + 待機の腰 - 腰の沈み + 腰の回転 · 付け根）から届く目標だけ、置けたかを確かめる
            let hipsQ = ry(p.hipsYaw) * rx(-p.hipsPitch) * rz(p.hipsRoll)
            let hip = p.offset + rig.hips - SIMD3(0, p.hipsDrop * rig.dropScale, 0)
            let tR = rig.restAnkleR + p.footR, tL = rig.restAnkleL + p.footL
            let reach = { (socket: SIMD3<Float>, t: SIMD3<Float>) -> Bool in
                let d = simd_distance(hip + hipsQ.act(socket), t)
                return d < 0.97 * leg && d > 0.3 * leg
            }
            let reachable = reach(rig.socketR, tR) && reach(rig.socketL, tL)
            rig.applyPlant(&p)
            let h = rig.ankleHeights(p)
            XCTAssertGreaterThan(min(h.right, h.left), -0.001, "足首が地面より下")
            // 届いて体を持ち上げなかった時は目標そのもの
            if reachable && p.offset.y < 1e-4 {
                checked += 1
                XCTAssertLessThan(simd_distance(rig.ankle(p, right: true), tR), 0.001)
                XCTAssertLessThan(simd_distance(rig.ankle(p, right: false), tL), 0.001)
            }
        }
        XCTAssertGreaterThan(checked, 50, "届く目標が少なすぎて IK を確かめていない")
    }

    // MARK: アニメーター（段・命中の後・移動中の下半身・通常攻撃）

    func testRecastRestartsWithStageMotion() throws {
        var a = animator("H029")
        XCTAssertTrue(a.castRestarts(.skill2, stage: 1))
        XCTAssertFalse(a.castRestarts(.skill2, stage: 2))
        XCTAssertFalse(a.castRestarts(.skill1, stage: 1))
        let recast = try XCTUnwrap(a.profile.recasts[1].first)
        XCTAssertEqual(a.castDuration(.skill2, stage: 1), recast.total, accuracy: 1e-5)
        XCTAssertEqual(a.castDuration(.skill2, stage: 0), a.profile.casts[1].total, accuracy: 1e-5)
        a.setState(.cast(.skill2))
        for _ in 0..<18 { _ = a.advance(dt: 1.0 / 60.0, moveSpeed: 0) }
        a.playCast(.skill2, stage: 1)
        XCTAssertEqual(a.state, .cast(.skill2))
        XCTAssertEqual(a.stateTime, 0, "再使用で始め直していない")
        // 振り上げ（打ち上げ）の時刻に、右腕が段のモーションの姿勢へ来ている
        let steps = Int((recast.impact ?? 0) * 60)
        for _ in 0..<steps { _ = a.advance(dt: 1.0 / 60.0, moveSpeed: 0) }
        let expected = recast.evaluate(base: a.profile.rest, t: a.stateTime)
        XCTAssertEqual(a.current.armR.pitch, expected.armR.pitch, accuracy: 0.05)
    }

    func testHitFollowUpPlaysOncePerCast() {
        var a = animator("H034")
        a.setState(.cast(.skill1))
        for _ in 0..<30 { _ = a.advance(dt: 1.0 / 60.0, moveSpeed: 0) }
        let d = a.playCastHit(.skill1)
        XCTAssertEqual(d ?? 0, a.profile.hitFollowUps[0]?.total ?? -1, accuracy: 1e-5)
        XCTAssertEqual(a.stateTime, 0)
        XCTAssertNil(a.playCastHit(.skill1), "1 回の詠唱で 2 度始めた")
        XCTAssertNil(a.playCastHit(.skill2), "詠唱していないスロットで始めた")
        // 次の詠唱では再び始められる
        a.setState(.idle)
        _ = a.advance(dt: 0.1, moveSpeed: 0)
        a.setState(.cast(.skill1))
        _ = a.advance(dt: 0.1, moveSpeed: 0)
        XCTAssertNotNil(a.playCastHit(.skill1))
        // ボルグのスキル1 には無い
        var b = animator("H029")
        b.setState(.cast(.skill1))
        _ = b.advance(dt: 0.1, moveSpeed: 0)
        XCTAssertNil(b.playCastHit(.skill1))
    }

    /// 移動している間（突進を含む）は、全身のモーションの下半身・体の位置を移動の姿勢へ戻す（足を滑らせない）。
    func testMovingYieldsLowerBodyToLocomotion() {
        var still = animator("H029")
        var moving = animator("H029")
        still.setState(.cast(.skill1))
        moving.setState(.cast(.skill1))
        for _ in 0..<18 {
            _ = still.advance(dt: 1.0 / 60.0, moveSpeed: 0)
            _ = moving.advance(dt: 1.0 / 60.0, moveSpeed: 4)
        }
        XCTAssertGreaterThan(still.current.plant, 0.99, "立ち止まっていれば足を接地させる")
        XCTAssertLessThan(moving.current.plant, 0.01, "移動中も足を接地させている")
        XCTAssertLessThan(abs(moving.current.offset.z), 0.02, "移動中も踏み込みで体を前へ出している")
        // 上半身は同じ（打撃の振りは移動中も出す）
        XCTAssertEqual(still.current.armR.pitch, moving.current.armR.pitch, accuracy: 0.05)
    }

    /// 全身の通常攻撃: 武器の振り（軌跡）は playAttack の windup 秒後の前後だけ。戻りは攻撃状態の後も続き、待機へつながる。
    func testAttackMotionStrikesAtWindup() {
        for id in Self.scripted where !Self.clipAttack(id) {
            for windup: Float in [0.18, 0.25, 0.4] {
                var a = animator(id)
                a.setState(.attack)
                a.playAttack(windup: windup, interval: 1.0)
                var t: Float = 0
                var firstSwing: Float?
                var lastSwing: Float?
                while t < 1.2 {
                    _ = a.advance(dt: 1.0 / 120.0, moveSpeed: 0)
                    t += 1.0 / 120.0
                    if a.weaponSwing.right {
                        if firstSwing == nil { firstSwing = t }
                        lastSwing = t
                    }
                    if t > 0.6 && a.state == .attack { a.setState(.idle) }
                }
                let lead = HeroMotionClip.swingLead, tail = HeroMotionClip.swingTail
                let first = firstSwing ?? -1, last = lastSwing ?? -1
                XCTAssertLessThanOrEqual(first, windup + 0.01, "\(id) windup \(windup): 振りが打撃より後に始まる")
                XCTAssertGreaterThanOrEqual(last, windup - 0.01, "\(id) windup \(windup): 振りが打撃の前に終わる")
                XCTAssertGreaterThanOrEqual(first, windup - lead * 4.1 - 0.02, "\(id) windup \(windup): 振りが早すぎる")
                XCTAssertLessThanOrEqual(last, windup + tail + 0.02, "\(id) windup \(windup): 振りが遅すぎる")
                XCTAssertEqual(a.state, .idle)
                XCTAssertEqual(a.current.plant, 0, accuracy: 1e-4, "\(id): 待機へ戻っても接地が残る")
            }
        }
    }

    // MARK: 同梱のスキンメッシュ（骨で測る）

    /// 同梱の H029 / H034 で、全てのモーションの間、足首の骨が地面（待機の足首の高さ）より下へ入らず、体の位置が戻る。
    func testBundledSkinnedFeetStayOnGround() throws {
        var checked = 0
        for id in Self.scripted {
            guard let url = HeroAssetLibrary.bundledURL("Hero_\(id)") else { continue }
            let model = HeroModelLibrary.makeHero(heroID: id, skinID: nil, team: .blue, master: master,
                                                  options: HeroModelOptions.showcase.with(mesh: .skinned(url)))
            let m = try XCTUnwrap(model as? SkinnedHeroModel, id)
            let rig = try XCTUnwrap(m.legRig, "\(id): 脚の寸法が無い")
            print("HeroFullBodyMotionTests: \(id) 脚 hips \(rig.hips) 腿 \(rig.thigh) 脛 \(rig.shin) 沈み \(rig.dropScale)"
                  + " 足首 \(rig.restAnkleR) / \(rig.restAnkleL)")
            // 地面の基準 = 手続きの待機の姿勢の足首（待機のモーションクリップの立ち方ではなく、接地の IK の原点）
            m.applyPose(profile(id).rest)
            let rest = try footHeights(m)
            for (slot, stage) in [(SkillSlot.skill1, 0), (.skill2, 0), (.skill2, 1), (.ultimate, 0)] {
                m.setState(.idle)
                for _ in 0..<20 { m.update(dt: 1.0 / 30.0, moveSpeed: 0) }
                if stage == 0 { m.setState(.cast(slot)) } else { m.playCast(slot, stage: stage) }
                let total = m.castDuration(slot, stage: stage)
                var t: Float = 0
                var lowest: Float = 1
                var lowestAt: Float = 0
                while t < total {
                    m.update(dt: 1.0 / 60.0, moveSpeed: 0)
                    t += 1.0 / 60.0
                    // 始めの 0.2 秒は待機のモーションクリップとの混ぜ（HeroClipLayer のフェード 0.15 秒。関節の角度を混ぜるので
                    // 足が数 cm 沈むことがある = 従来からの全ヒーロー共通の混ぜ方）。足の接地はその後を測る
                    // 終わり（最後の 0.05 秒）は待機の手続きの姿勢（呼吸の腰の沈み）へ戻り切る所で、待機のモーションクリップが
                    // まだ重なっていない（詠唱の状態のまま進めているため）。足の接地の範囲だけを測る
                    guard t > 0.2, t < total - 0.05 else { continue }
                    let h = try footHeights(m)
                    let low = min(h.0 - rest.0, h.1 - rest.1)
                    if low < lowest { lowest = low; lowestAt = t }
                }
                XCTAssertGreaterThan(lowest, -0.01, "\(id) \(slot) 段 \(stage): 足首の骨が地面より下 \(lowest) m（\(lowestAt) 秒）")
                XCTAssertLessThan(simd_length(m.currentPose.offset), 0.05, "\(id) \(slot) 段 \(stage): 終わりで体の位置が戻らない")
                checked += 1
            }
        }
        if checked == 0 { throw XCTSkip("Hero_H029 / Hero_H034 が同梱されていない") }
    }

    /// 足首の骨の高さ（右・左。ヒーローの root 空間 = 地面が 0）。
    private func footHeights(_ m: SkinnedHeroModel) throws -> (Float, Float) {
        let motion = try XCTUnwrap(m.root.children.first?.children.first)
        let r = motion.convert(position: try XCTUnwrap(m.jointPosition(.footR)), to: m.root)
        let l = motion.convert(position: try XCTUnwrap(m.jointPosition(.footL)), to: m.root)
        return (r.y, l.y)
    }
}
