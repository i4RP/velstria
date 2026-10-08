import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 武器の軌跡（HeroModelHandle.weaponTrailSample）と遠隔の通常攻撃の発射位置（attackLaunchPoint）の検査。
/// 打つ手・近接の判定は合成クリップと同梱の HeroMotionClips.json、姿勢は同梱のヒーロー（Hero_<id>.usdz）と手続きモデルで見る。
@MainActor
final class HeroWeaponTrailTests: XCTestCase {
    private let master = MasterData.shared

    override func setUp() {
        super.setUp()
        // 他のテストが差し込んだライブラリを外し、同梱の HeroMotionClips.json を使う
        HeroMotionClips.setResolverForTesting(nil)
    }

    override func tearDown() {
        HeroMotionClips.setResolverForTesting(nil)
        super.tearDown()
    }

    // MARK: 合成クリップ

    /// 31 フレーム・打撃 15 の合成クリップ。右・左の腕（上腕・前腕・手）を rx で振り上げて戻し、
    /// twist は胴と両腕をまとめて Y 軸で回す（体のひねり。左右の腕を同じだけ回す）。
    private static func clip(_ name: String, right: Float, left: Float, twist: Float = 0, impact: Float? = 15,
                             melee: Bool? = nil) -> [String: Any] {
        let frames = 31
        var rot: [Double] = []
        for f in 0..<frames {
            let t = Float(f) / 30
            let body = ry(twist * t)
            for s in 0..<HeroSegmentRotations.count {
                let q: simd_quatf
                switch s {
                case 1, 2: q = body
                case 3, 4, 5: q = body * rx(right * sin(.pi * t))
                case 6, 7, 8: q = body * rx(left * sin(.pi * t))
                default: q = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                }
                rot += [q.vector.x, q.vector.y, q.vector.z, q.vector.w].map { Double($0) }
            }
        }
        var c: [String: Any] = ["name": name, "frames": frames, "loop": false, "rot": rot,
                                "root": [Double](repeating: 0, count: frames * 3)]
        if let impact { c["events"] = ["impact": Double(impact)] }
        if let melee { c["melee"] = melee }
        return c
    }

    private static func library(_ clips: [[String: Any]]) throws -> HeroMotionLibrary {
        let top: [String: Any] = ["version": 1, "fps": 30.0, "segments": HeroSegmentRotations.names, "clips": clips]
        var skipped: [String] = []
        let lib = try HeroMotionLibrary.decode(try JSONSerialization.data(withJSONObject: top), skipped: &skipped)
        XCTAssertTrue(skipped.isEmpty, "\(skipped)")
        return lib
    }

    private func profile(_ heroID: String) -> HeroMotionProfile {
        let bp = HeroBlueprints.blueprint(heroID: heroID, role: nil)
        return HeroMotionProfile(blueprint: bp, metrics: BodyMetrics.make(bp.build))
    }

    // MARK: モデル

    /// 同梱のヒーロー（スキンメッシュ）。
    private func bundled(_ id: String, file: StaticString = #filePath, line: UInt = #line) throws -> SkinnedHeroModel {
        let url = try XCTUnwrap(HeroAssetLibrary.bundledURL("Hero_\(id)"), "Hero_\(id).usdz が同梱されていない", file: file, line: line)
        let model = HeroModelLibrary.makeHero(heroID: id, skinID: nil, team: .blue, master: master,
                                              options: HeroModelOptions.showcase.with(mesh: .skinned(url)))
        return try XCTUnwrap(model as? SkinnedHeroModel, "\(id) がスキンメッシュで生成されない", file: file, line: line)
    }

    private func procedural(_ id: String) -> any HeroDisplayModel {
        HeroModelLibrary.makeHero(heroID: id, skinID: nil, team: .blue, master: master,
                                  options: HeroModelOptions.showcase.with(mesh: .procedural))
    }

    /// 骨のワールド位置（jointPosition はヒーロー空間 = root → body → motion のローカル）。
    private func joint(_ m: SkinnedHeroModel, _ role: HeroJointRole, file: StaticString = #filePath, line: UInt = #line) throws -> SIMD3<Float> {
        let motion = try XCTUnwrap(m.root.children.first?.children.first, file: file, line: line)
        return motion.convert(position: try XCTUnwrap(m.jointPosition(role), file: file, line: line), to: nil)
    }

    private func step(_ m: some HeroDisplayModel, _ n: Int, dt: Double = 1.0 / 60.0, speed: Double = 0) {
        for _ in 0..<n { m.update(dt: dt, moveSpeed: speed) }
    }

    /// 通常攻撃を 1 回振り、打撃（クリップ時刻が impact に達するか 1 フレーム過ぎたところ）まで進める。
    private func playToImpact(_ m: SkinnedHeroModel, windup: Double = 0.3, interval: Double = 0.9, dt: Double = 1.0 / 60.0) {
        m.playAttack(windup: windup, interval: interval)
        var n = 0
        while m.clipLayer.clipTime < m.clipLayer.impactTime - 1e-4 && n < Int(windup / dt) + 20 {
            m.update(dt: dt, moveSpeed: 0)
            n += 1
        }
    }

    // MARK: 打つ手・近接（読み込み時）

    /// 打つ手は胴に対する前腕の角速度で決まる（体のひねりだけでは決めない）。近接は名前と JSON の melee。
    func testStrikeHandAndMeleeFromSyntheticClips() throws {
        let lib = try Self.library([
            Self.clip("slash", right: 2, left: 0),
            Self.clip("hook_x", right: 0.3, left: 2),
            Self.clip("clap", right: 2, left: 2),
            Self.clip("spin", right: 0, left: 0, twist: 6),
            Self.clip("spin_left", right: 0, left: 1, twist: 6),
            Self.clip("cast_bolt", right: 2, left: 0),
            Self.clip("gun", right: 2, left: 0),
            Self.clip("slash_flag", right: 2, left: 0, melee: false),
            Self.clip("cast_blade", right: 2, left: 0, melee: true),
            Self.clip("pose", right: 2, left: 0, impact: nil),
        ])
        func info(_ name: String) throws -> HeroMotionClip { lib.clips[try XCTUnwrap(lib.index(of: name), name)] }
        XCTAssertEqual(try info("slash").strikeHand, .right)
        XCTAssertEqual(try info("hook_x").strikeHand, .left)
        XCTAssertEqual(try info("clap").strikeHand, .both)
        XCTAssertEqual(try info("spin").strikeHand, .right, "体の回転だけ（腕は胴に対して止まっている）は既定の右")
        XCTAssertEqual(try info("spin_left").strikeHand, .left, "体の回転が左右の差を埋めて両手になる（ヒーロー空間で測っている）")
        XCTAssertTrue(try info("slash").melee)
        XCTAssertTrue(try info("hook_x").melee)
        XCTAssertFalse(try info("cast_bolt").melee)
        XCTAssertFalse(try info("gun").melee)
        XCTAssertFalse(try info("slash_flag").melee, "JSON の melee: false が効かない")
        XCTAssertTrue(try info("cast_blade").melee, "JSON の melee: true が効かない")
        XCTAssertFalse(try info("pose").melee, "打撃の無いクリップは近接でない")
    }

    /// 同梱のクリップの打つ手・近接（docs/HERO_MOTION.md に書いた代表）。
    func testBundledStrikeHandsAndMelee() throws {
        let lib = HeroMotionClips.shared
        guard !lib.isEmpty else { throw XCTSkip("HeroMotionClips.json が同梱されていない") }
        func info(_ name: String) throws -> HeroMotionClip { lib.clips[try XCTUnwrap(lib.index(of: name), name)] }
        for (name, hand) in [("hook_l", HeroStrikeHand.left), ("punch_a", .left), ("uppercut_r", .right), ("elbow", .right),
                             ("sword_combo_1", .right), ("sword_combo_3", .right), ("dual_combo_c", .right), ("dual_spin", .both)] {
            XCTAssertEqual(try info(name).strikeHand, hand, name)
        }
        for name in ["sword_combo_1", "hook_l", "thrust", "dual_combo_a", "overhead_2h", "jump_attack", "ground_slam"] {
            XCTAssertTrue(try info(name).melee, "\(name) が近接でない")
        }
        for name in ["gun_fire", "cast_throw", "cast_point", "bow_shot", "javelin_throw", "dodge_spin", "idle_b", "death_back"] {
            XCTAssertFalse(try info(name).melee, "\(name) が近接になっている")
        }
        print("HeroWeaponTrailTests: 打つ手 " + lib.clips.filter { $0.impact != nil }
            .map { "\($0.name)=\($0.strikeHand)\($0.melee ? "" : "(遠隔)")" }.joined(separator: " "))
    }

    // MARK: 振りの区間

    /// 振りの区間はクリップ時刻で打撃の前 0.18 秒〜後 0.06 秒（実時間は打撃までの再生速度に比例して縮む）。
    /// 拍待ちで最後の姿勢に止まっている間・待機は振っていない。
    func testSwingWindowFollowsClipTime() throws {
        let lib = try Self.library([Self.clip("slash", right: 2, left: 0)])
        var set = HeroMotionSet()
        set.attacks = ["slash"]
        let binding = try XCTUnwrap(HeroMotionBinding(set: set, library: lib))
        let dt: Float = 1.0 / 240
        for windup in [Float(0.1), 0.3, 0.6] {
            var a = HeroAnimator(profile: profile("H001"), defaultRunSpeed: 3.3, motion: binding)
            _ = a.advance(dt: dt, moveSpeed: 0)
            XCTAssertFalse(a.weaponSwing.right || a.weaponSwing.left, "待機で振っている")
            a.playAttack(windup: windup, interval: windup + 0.6)
            let pre = a.clips.preRate
            var lead = 0, any = false
            for _ in 0..<Int((windup + 0.8) / dt) {
                _ = a.advance(dt: dt, moveSpeed: 0)
                let t = a.clips.clipTime, imp = a.clips.impactTime
                let inside = t >= imp - HeroMotionClip.swingLead && t <= imp + HeroMotionClip.swingTail
                XCTAssertEqual(a.weaponSwing.right, inside, "windup \(windup) t=\(t)")
                XCTAssertFalse(a.weaponSwing.left)
                if a.weaponSwing.right && t < imp { lead += 1 }
                any = any || inside
            }
            XCTAssertTrue(any, "windup \(windup): 打撃の前後で振っていない")
            XCTAssertEqual(Float(lead) * dt, HeroMotionClip.swingLead / pre, accuracy: 2 * dt,
                           "windup \(windup): 打撃の前の振りが再生速度 \(pre) 倍で縮まない")
            XCTAssertTrue(a.clips.finished && a.clips.holdAtEnd)
            XCTAssertFalse(a.weaponSwing.right, "拍待ちの最後の姿勢で振っている")
        }
        // 遠隔のクリップ（melee でない）は振らない
        var ranged = HeroMotionSet()
        ranged.attacks = ["cast_bolt"]
        let rlib = try Self.library([Self.clip("cast_bolt", right: 2, left: 0)])
        var b = HeroAnimator(profile: profile("H004"), defaultRunSpeed: 3.3,
                             motion: try XCTUnwrap(HeroMotionBinding(set: ranged, library: rlib)))
        b.playAttack(windup: 0.3, interval: 0.9)
        for _ in 0..<Int(0.9 / dt) {
            _ = b.advance(dt: dt, moveSpeed: 0)
            XCTAssertFalse(b.weaponSwing.right || b.weaponSwing.left)
        }
    }

    /// クリップの無い手続きの振り: 近接の型だけ、打撃区間（予備動作の終わり〜打撃の終わり + 0.06 秒）。二刀は奇数回目が左手。
    func testProceduralAttackSwingWindow() {
        let dt: Float = 1.0 / 240
        var a = HeroAnimator(profile: profile("H012"), defaultRunSpeed: 3.3)
        for _ in 0..<10 { _ = a.advance(dt: dt, moveSpeed: 0) }
        XCTAssertFalse(a.weaponSwing.right || a.weaponSwing.left)
        a.setState(.attack)
        let atk = a.profile.attack
        var right = 0
        for _ in 0..<Int(atk.total / dt) {
            _ = a.advance(dt: dt, moveSpeed: 0)
            if a.weaponSwing.right { right += 1 }
            XCTAssertFalse(a.weaponSwing.left)
        }
        XCTAssertEqual(Float(right) * dt, atk.strikeTime + HeroMotionClip.swingTail, accuracy: 2 * dt)
        XCTAssertEqual(a.strikeHand, .right)
        // 打撃を過ぎてからの再指定 = 次の振り（二刀は左手）
        a.setState(.attack)
        XCTAssertEqual(a.strikeHand, .left)
        var left = 0
        for _ in 0..<Int(atk.total / dt) {
            _ = a.advance(dt: dt, moveSpeed: 0)
            if a.weaponSwing.left { left += 1 }
            XCTAssertFalse(a.weaponSwing.right)
        }
        XCTAssertGreaterThan(left, 0, "二刀の左手の振りが無い")
        // 遠隔の型（杖）は振らない
        var s = HeroAnimator(profile: profile("H004"), defaultRunSpeed: 3.3)
        s.setState(.attack)
        for _ in 0..<Int(1 / dt) {
            _ = s.advance(dt: dt, moveSpeed: 0)
            XCTAssertFalse(s.weaponSwing.right || s.weaponSwing.left)
        }
    }

    // MARK: 軌跡のサンプル（同梱のヒーロー）

    /// 先端は握りより手から遠く、通常攻撃のクリップの間は動き、打撃の前後だけ swing。待機では振っていない。
    func testTrailSampleOnBundledHeroes() throws {
        guard !HeroMotionClips.shared.isEmpty else { throw XCTSkip("HeroMotionClips.json が同梱されていない") }
        for id in ["H001", "H006", "H012", "H014", "H019", "H022", "H024"] {
            let m = try bundled(id)
            let dual = ["H006", "H012", "H014", "H024"].contains(id)
            step(m, 10)
            let idle = try XCTUnwrap(m.weaponTrailSample(), id)
            XCTAssertFalse(idle.right.swing || (idle.left?.swing ?? false), "\(id) 待機で振っている")
            XCTAssertEqual(idle.left != nil, dual, "\(id) 左手の刃の有無")
            var tips: [SIMD3<Float>] = []
            var swung = false
            m.playAttack(windup: 0.3, interval: 0.9)
            for k in 0..<50 {
                m.update(dt: 1.0 / 60.0, moveSpeed: 0)
                let s = try XCTUnwrap(m.weaponTrailSample(), id)
                let hr = try joint(m, .handR)
                XCTAssertGreaterThan(simd_distance(s.right.tip, hr), simd_distance(s.right.base, hr) + 0.05,
                                     "\(id) フレーム \(k): 右の先端が握りより手から遠くない")
                if let l = s.left {
                    let hl = try joint(m, .handL)
                    XCTAssertGreaterThan(simd_distance(l.tip, hl), simd_distance(l.base, hl) + 0.05,
                                         "\(id) フレーム \(k): 左の先端が握りより手から遠くない")
                }
                tips.append(s.right.tip)
                swung = swung || s.right.swing || (s.left?.swing ?? false)
                let c = m.clipLayer
                let inside = c.clipTime >= c.impactTime - HeroMotionClip.swingLead && c.clipTime <= c.impactTime + HeroMotionClip.swingTail
                if !inside { XCTAssertFalse(s.right.swing || (s.left?.swing ?? false), "\(id) フレーム \(k): 振りの区間の外で swing") }
            }
            let travel = zip(tips, tips.dropFirst()).reduce(Float(0)) { $0 + simd_distance($1.0, $1.1) }
            XCTAssertGreaterThan(travel, 0.3, "\(id) 攻撃のクリップで先端が動かない（\(travel) m）")
            // H022 の hook_l は左手で打つが、左の爪は軌跡を持たない（二刀の刃だけ）
            if id != "H022" { XCTAssertTrue(swung, "\(id) 打撃の前後で swing にならない") }
            let steps = zip(tips, tips.dropFirst()).map { String(format: "%.2f", simd_distance($0.0, $0.1)) }.joined(separator: ",")
            print("HeroWeaponTrailTests: \(id) \(m.clipLayer.clipName ?? "-") 先端の移動 \(travel) m [\(steps)]")
        }
    }

    /// 左手で打つクリップは左の刃が swing（右は振らない）。発射位置も左手の側。
    func testLeftHandClipSwingsLeftBlade() throws {
        let lib = try Self.library([Self.clip("hook_x", right: 0.2, left: 2.2)])
        var set = HeroMotionSet()
        set.attacks = ["hook_x"]
        set.offhandGrip = HeroMotionSet.fistGrip
        let m = try bundled("H014")
        m.useMotion(set, library: lib)
        step(m, 5)
        playToImpact(m)
        let s = try XCTUnwrap(m.weaponTrailSample())
        let l = try XCTUnwrap(s.left)
        XCTAssertTrue(l.swing, "左手の打撃で左の刃が swing にならない")
        XCTAssertFalse(s.right.swing, "左手の打撃で右も swing")
        let p = try XCTUnwrap(m.attackLaunchPoint())
        XCTAssertLessThan(simd_distance(p, l.tip), 1e-4, "左手で打つ時の発射位置が左の刃先でない")
    }

    // MARK: 発射位置

    /// H003（素手 + 副手の弓）: 発射位置は弓の握り（左手）。Prop の弓（propFit）でも弓の範囲の中。軌跡は無い。
    func testLaunchPointNearBowForH003() throws {
        guard let prop = Bundle(for: Self.self).url(forResource: "Prop_ashBow", withExtension: "usdz") else {
            throw XCTSkip("Prop_ashBow のフィクスチャが無い")
        }
        HeroAssetLibrary.resetForTesting()
        defer { HeroAssetLibrary.resetForTesting() }
        HeroAssetLibrary.resolver = { name in
            name == "Prop_ashBow" ? prop : Bundle.main.url(forResource: name, withExtension: "usdz")
        }
        let m = try bundled("H003")
        XCTAssertNotNil(m.offhand.findEntity(named: "propFit"), "Prop の弓が付いていない")
        XCTAssertNil(m.weaponTrailSample(), "素手の H003 に軌跡がある")
        step(m, 10)
        func check(_ label: String) throws {
            let p = try XCTUnwrap(m.attackLaunchPoint())
            XCTAssertLessThan(simd_distance(p, m.offhand.position(relativeTo: nil)), 1e-4, "\(label): 弓の握りでない")
            XCTAssertLessThan(simd_distance(p, try joint(m, .handL)), 0.15, "\(label): 左手（弓）から離れている")
            let b = m.offhand.visualBounds(recursive: true, relativeTo: nil)
            let margin = SIMD3<Float>(repeating: 0.05)
            XCTAssertTrue(all(p .>= b.min - margin) && all(p .<= b.max + margin), "\(label): 弓の範囲の外 \(p) \(b)")
        }
        try check("待機")
        playToImpact(m)
        XCTAssertNotNil(m.clipLayer.clipName)
        try check("\(m.clipLayer.clipName ?? "-") の打撃")
    }

    /// H022（両手の爪）: 発射位置は手のひら。hook_l（左手で打つ）は左手、cast_throw は右手。
    func testLaunchPointNearHandForH022() throws {
        guard !HeroMotionClips.shared.isEmpty else { throw XCTSkip("HeroMotionClips.json が同梱されていない") }
        let m = try bundled("H022")
        step(m, 10)
        XCTAssertLessThan(simd_distance(try XCTUnwrap(m.attackLaunchPoint()), try joint(m, .handR)), 0.15, "待機: 右手から離れている")
        playToImpact(m)
        XCTAssertEqual(m.clipLayer.clipName, "hook_l")
        let hook = try XCTUnwrap(m.attackLaunchPoint())
        XCTAssertLessThan(simd_distance(hook, try joint(m, .handL)), 0.15, "hook_l: 左手から離れている")
        XCTAssertLessThan(simd_distance(hook, try joint(m, .handL)), simd_distance(hook, try joint(m, .handR)))
        step(m, 60)
        playToImpact(m)
        XCTAssertEqual(m.clipLayer.clipName, "cast_throw")
        let throwPoint = try XCTUnwrap(m.attackLaunchPoint())
        XCTAssertLessThan(simd_distance(throwPoint, try joint(m, .handR)), 0.15, "cast_throw: 右手から離れている")
    }

    /// 杖・銃・掌の炎は武器の先端（castGlow と同じ点）から放つ。
    func testLaunchPointIsWeaponTipForStaffGunAndFlame() throws {
        for id in ["H004", "H010", "H021"] {
            let m = try bundled(id)
            step(m, 10)
            let glow = try XCTUnwrap(m.weapon.findEntity(named: "castGlow"), id)
            let p = try XCTUnwrap(m.attackLaunchPoint(), id)
            XCTAssertLessThan(simd_distance(p, glow.position(relativeTo: nil)), 1e-4, "\(id) 発射位置が武器の先端でない")
        }
    }

    // MARK: 座標・既定・手続きモデル

    /// 返す座標はワールド（親の変換を含む）。
    func testSamplesAreInWorldSpace() throws {
        let a = try bundled("H012"), b = try bundled("H012")
        let parent = Entity()
        parent.transform = Transform(scale: SIMD3(repeating: 1.3), rotation: ry(1.1), translation: SIMD3(4, 0.5, -3))
        parent.addChild(b.root)
        b.root.position = SIMD3(1, 0, 2)
        a.root.position = SIMD3(1, 0, 2)
        for m in [a, b] {
            m.playAttack(windup: 0.3, interval: 0.9)
            step(m, 14)
        }
        let sa = try XCTUnwrap(a.weaponTrailSample()), sb = try XCTUnwrap(b.weaponTrailSample())
        let la = try XCTUnwrap(sa.left), lb = try XCTUnwrap(sb.left)
        let mtx = parent.transform.matrix
        func world(_ p: SIMD3<Float>) -> SIMD3<Float> { let v = mtx * SIMD4(p, 1); return SIMD3(v.x, v.y, v.z) }
        for (x, y) in [(sa.right.tip, sb.right.tip), (sa.right.base, sb.right.base), (la.tip, lb.tip), (la.base, lb.base),
                       (try XCTUnwrap(a.attackLaunchPoint()), try XCTUnwrap(b.attackLaunchPoint()))] {
            XCTAssertLessThan(simd_distance(world(x), y), 1e-3)
        }
        XCTAssertEqual(sa.right.swing, sb.right.swing)
    }

    /// 手続きモデル: 武器を持つ全員に軌跡（二刀は左も）、先端は握りから離れ、手続きの振りの打撃区間で swing。H003・H025 は弓の握りから放つ。
    func testProceduralModels() throws {
        for n in 1...34 {
            let id = String(format: "H%03d", n)
            let m = procedural(id)
            XCTAssertFalse(m.isSkinned)
            step(m, 3)
            let bp = HeroBlueprints.blueprint(heroID: id, role: nil)
            XCTAssertNotNil(m.attackLaunchPoint(), id)
            guard bp.weapon != .none else {
                XCTAssertNil(m.weaponTrailSample(), id)
                continue
            }
            let s = try XCTUnwrap(m.weaponTrailSample(), id)
            XCTAssertGreaterThan(simd_distance(s.right.tip, s.right.base), 0.1, id)
            XCTAssertEqual(s.left != nil, HeroWeaponPoints.dualBlades.contains(bp.offhand), id)
            XCTAssertFalse(s.right.swing, "\(id) 待機で振っている")
        }
        let sword = procedural("H001")
        sword.setState(.attack)
        var swung = 0
        for _ in 0..<24 {
            sword.update(dt: 1.0 / 60.0, moveSpeed: 0)
            if try XCTUnwrap(sword.weaponTrailSample()).right.swing { swung += 1 }
        }
        XCTAssertGreaterThan(swung, 0, "手続きの剣の振りで swing にならない")
        for id in ["H003", "H025"] {
            let archer = procedural(id)
            let bow = try XCTUnwrap(archer.root.findEntity(named: "offhand"), id)
            XCTAssertLessThan(simd_distance(try XCTUnwrap(archer.attackLaunchPoint(), id), bow.position(relativeTo: nil)), 1e-4, id)
        }
    }

    /// 対応していないハンドルは既定の nil。
    func testDefaultImplementationsReturnNil() {
        let h: HeroModelHandle = StubHandle()
        XCTAssertNil(h.attackLaunchPoint())
        XCTAssertNil(h.weaponTrailSample())
    }
}

@MainActor
private final class StubHandle: HeroModelHandle {
    let root = Entity()
    var overheadHeight: Float { 2 }
    func setState(_ state: HeroAnimState) {}
    func castDuration(_ slot: SkillSlot) -> Float { 0.5 }
    func update(dt: Double, moveSpeed: Double) {}
}
