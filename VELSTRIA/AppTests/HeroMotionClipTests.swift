import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// モーションクリップ（docs/HERO_MOTION.md）の読み込み・補間・重ね合わせの検査。
/// クリップは合成した JSON をメモリ上でデコードし、骨は AppTests/Fixtures/SkinnedTestHero.usdz を使う。
@MainActor
final class HeroMotionClipTests: XCTestCase {
    private let master = MasterData.shared

    // MARK: 合成クリップ

    /// 合成クリップ（rot は (フレーム, 区間の添字) → 回転、root はフレーム → 腰のずれ）。
    private struct Synth {
        var name: String
        var frames: Int
        var loop = false
        var rootXZ: Float = 0
        var events: [String: Float] = [:]
        var rot: (Int, Int) -> simd_quatf = { _, _ in simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
        var root: (Int) -> SIMD3<Float> = { _ in .zero }
    }

    /// HeroMotionClips.json と同じ形の JSON（segments は指定の順で書く）。
    private static func json(_ clips: [Synth], fps: Float = 30, segments: [String] = HeroSegmentRotations.names,
                             version: Int = 1) throws -> Data {
        let names = HeroSegmentRotations.names
        let list: [[String: Any]] = clips.map { c in
            var rot: [Double] = []
            var root: [Double] = []
            for f in 0..<c.frames {
                for seg in segments {
                    let q = names.firstIndex(of: seg).map { c.rot(f, $0) } ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                    rot += [Double(q.vector.x), Double(q.vector.y), Double(q.vector.z), Double(q.vector.w)]
                }
                let r = c.root(f)
                root += [Double(r.x), Double(r.y), Double(r.z)]
            }
            return ["name": c.name, "source": "test", "frames": c.frames, "loop": c.loop, "rootXZ": Double(c.rootXZ),
                    "events": c.events.mapValues { Double($0) }, "rot": rot, "root": root]
        }
        let top: [String: Any] = ["version": version, "fps": Double(fps), "segments": segments, "clips": list]
        return try JSONSerialization.data(withJSONObject: top)
    }

    private static func library(_ clips: [Synth], fps: Float = 30) throws -> HeroMotionLibrary {
        var skipped: [String] = []
        let lib = try HeroMotionLibrary.decode(try json(clips, fps: fps), skipped: &skipped)
        XCTAssertTrue(skipped.isEmpty, "\(skipped)")
        return lib
    }

    /// 打撃 15 フレーム目・31 フレームの振り（右腕を前へ振り上げて戻す）。
    private static let swing = Synth(name: "swing", frames: 31, events: ["impact": 15], rot: { f, s in
        let t = Float(f) / 30
        switch s {
        case 3, 4, 5: return rx(2.2 * sin(.pi * t))
        case 1, 2: return ry(0.4 * sin(.pi * t))
        default: return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        }
    })

    /// 全区間を毎フレーム大きく回す（武器が手から離れないかを見る）。
    private static let wild = Synth(name: "wild", frames: 24, events: ["impact": 8], rot: { f, s in
        let a = 2.5 * sin(Float(f) * 0.7 + Float(s))
        let axis = simd_normalize(SIMD3<Float>(sin(Float(s)), cos(Float(f) * 0.3 + Float(s)), 0.5))
        return simd_quatf(angle: a, axis: axis)
    }, root: { f in SIMD3<Float>(0.05 * sin(Float(f)), -0.1 * Float(f) / 24, 0) })

    // MARK: フィクスチャ

    private static func fixtureURL() throws -> URL {
        try XCTUnwrap(Bundle(for: HeroMotionClipTests.self).url(forResource: "SkinnedTestHero", withExtension: "usdz"),
                      "フィクスチャがテストバンドルに無い")
    }

    private func rig() throws -> HeroSkeletonRig {
        try XCTUnwrap(HeroAssetLibrary.heroTemplate(try Self.fixtureURL())).rig
    }

    private func makeSkinned(_ heroID: String = "H001", file: StaticString = #filePath, line: UInt = #line) throws -> SkinnedHeroModel {
        let model = HeroModelLibrary.makeHero(heroID: heroID, skinID: nil, team: .blue, master: master,
                                              options: HeroModelOptions.showcase.with(mesh: .skinned(try Self.fixtureURL())))
        return try XCTUnwrap(model as? SkinnedHeroModel, "スキンメッシュで生成されない", file: file, line: line)
    }

    private func profile(_ heroID: String) -> HeroMotionProfile {
        let bp = HeroBlueprints.blueprint(heroID: heroID, role: nil)
        return HeroMotionProfile(blueprint: bp, metrics: BodyMetrics.make(bp.build))
    }

    /// jointTransforms を親から累積した骨の位置（モデルの root 空間）。
    private func joints(_ m: SkinnedHeroModel) -> [HeroJointRole: SIMD3<Float>] {
        let e = m.skinnedEntity
        let names = e.jointNames
        let local = e.jointTransforms
        var byPath: [String: Int] = [:]
        for (i, n) in names.enumerated() { byPath[n] = i }
        var cache: [Int: simd_float4x4] = [:]
        func model(_ i: Int) -> simd_float4x4 {
            if let c = cache[i] { return c }
            var mtx = local[i].matrix
            if let slash = names[i].lastIndex(of: "/"), let p = byPath[String(names[i][..<slash])] {
                mtx = model(p) * mtx
            }
            cache[i] = mtx
            return mtx
        }
        let toRoot = e.transformMatrix(relativeTo: m.root)
        var out: [HeroJointRole: SIMD3<Float>] = [:]
        for (role, i) in m.rig.index {
            let p = toRoot * model(i).columns.3
            out[role] = SIMD3(p.x, p.y, p.z)
        }
        return out
    }

    /// 回転の差（q と -q は同じ回転）。
    private static func rotationError(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        min(simd_length(a.vector - b.vector), simd_length(a.vector + b.vector))
    }

    /// ローカル変換の列の最大の差（平行移動 m・四元数の成分）。
    private static func maxError(_ a: [Transform], _ b: [Transform]) -> (translation: Float, rotation: Float) {
        var t: Float = 0, r: Float = 0
        for (x, y) in zip(a, b) {
            t = max(t, simd_length(x.translation - y.translation))
            r = max(r, rotationError(x.rotation, y.rotation))
        }
        return (t, r)
    }

    /// 変更前の solve（手・足は前腕・脛に「親に追従」、腰のずれ無し）。手続きの見た目が変わらないことの基準。
    private static func legacySolve(_ rig: HeroSkeletonRig, _ q: HeroSegmentRotations, hipsDrop: Float) -> [Transform] {
        var rotation = rig.restRotation
        var position = rig.restPosition
        var local = rig.restLocal
        let hips = rig.index[.hips] ?? -1
        for j in rig.order {
            let p = rig.parent[j]
            let rest = rig.restLocal[j]
            var pos = p < 0 ? rig.entityPosition + rig.entityRotation.act(rig.entityScale * rest.translation)
                : position[p] + rotation[p].act(rig.restScale[p] * rest.translation)
            if j == hips { pos += SIMD3<Float>(0, -hipsDrop, 0) }
            let c = rig.correction[j], r0 = rig.restRotation[j]
            let rot: simd_quatf
            switch rig.drive[j] {
            case .rest, .handR, .handL, .footR, .footL:
                rot = p < 0 ? rig.entityRotation * rest.rotation : rotation[p] * rest.rotation
            case .hips: rot = q.hips * r0
            case .spine(let t): rot = simd_slerp(q.hips, q.torso, t) * r0
            case .neck: rot = simd_slerp(q.torso, q.head, 0.5) * r0
            case .head: rot = q.head * r0
            case .armR: rot = q.armR * c * r0
            case .foreArmR: rot = q.foreArmR * c * r0
            case .armL: rot = q.armL * c * r0
            case .foreArmL: rot = q.foreArmL * c * r0
            case .thighR: rot = q.thighR * c * r0
            case .shinR: rot = q.shinR * c * r0
            case .thighL: rot = q.thighL * c * r0
            case .shinL: rot = q.shinL * c * r0
            }
            rotation[j] = rot
            position[j] = pos
            var t = rest
            if p < 0 {
                let inv = rig.entityRotation.inverse
                t.rotation = (inv * rot).normalized
                t.translation = inv.act(pos - rig.entityPosition) / rig.entityScale
            } else {
                let inv = rotation[p].inverse
                t.rotation = (inv * rot).normalized
                t.translation = inv.act(pos - position[p]) / rig.restScale[p]
            }
            local[j] = t
        }
        return local
    }

    /// 区間 → 骨（胴は最後の背骨）。
    private static func segmentJoint(_ rig: HeroSkeletonRig, _ s: Int) -> Int? {
        let roles: [HeroJointRole?] = [.hips, nil, .head, .armR, .foreArmR, .handR, .armL, .foreArmL, .handL,
                                       .upLegR, .legR, .footR, .upLegL, .legL, .footL]
        if s == 1 { return rig.upperSpine }
        return roles[s].flatMap { rig.index[$0] }
    }

    // MARK: 骨の駆動

    /// 手・足を区間で駆動しても、手続きの姿勢（手 = 前腕、足 = 脛）では従来の「親に追従」と同じ骨になる。
    func testProceduralPosesMatchLegacySolveWithHandAndFootDrives() throws {
        let rig = try rig()
        for (role, drive, limb) in [(HeroJointRole.handR, HeroSkeletonRig.Drive.handR, HeroJointRole.foreArmR),
                                    (.handL, .handL, .foreArmL), (.footR, .footR, .legR), (.footL, .footL, .legL)] {
            let j = try XCTUnwrap(rig.index[role]), l = try XCTUnwrap(rig.index[limb])
            XCTAssertEqual(rig.drive[j], drive, "\(role) が区間で駆動されない")
            XCTAssertLessThan(Self.rotationError(rig.correction[j], rig.correction[l]), 1e-7, "\(role) の補正が \(limb) と違う")
        }
        var poses: [HeroPose] = [HeroPose()]
        for id in ["H001", "H003", "H007", "H019"] { poses.append(profile(id).rest) }
        var rng = SplitMix64(seed: 0xC11B_0001)
        func r(_ a: Float) -> Float { Float.random(in: -a...a, using: &rng) }
        for _ in 0..<60 {
            var p = HeroPose()
            p.hipsYaw = r(0.8); p.hipsRoll = r(0.4); p.hipsDrop = abs(r(0.2))
            p.torsoPitch = r(0.8); p.torsoYaw = r(0.8); p.torsoRoll = r(0.5)
            p.headPitch = r(0.5); p.headYaw = r(0.8); p.headRoll = r(0.4)
            p.armR = ArmPose(pitch: r(2.5), out: r(1.2), yaw: r(1.0), elbow: abs(r(2.0)))
            p.armL = ArmPose(pitch: r(2.5), out: r(1.2), yaw: r(1.0), elbow: abs(r(2.0)))
            p.legR = LegPose(pitch: r(1.5), out: r(0.6), knee: abs(r(2.0)))
            p.legL = LegPose(pitch: r(1.5), out: r(0.6), knee: abs(r(2.0)))
            poses.append(p)
        }
        var poser = HeroSkeletonPoser(rig: rig)
        var worst: (translation: Float, rotation: Float) = (0, 0)
        for (i, p) in poses.enumerated() {
            let q = HeroSegmentRotations(p)
            XCTAssertEqual(q.handR.vector, q.foreArmR.vector)
            XCTAssertEqual(q.footL.vector, q.shinL.vector)
            poser.solve(q, hipsDrop: p.hipsDrop)
            let e = Self.maxError(poser.local, Self.legacySolve(rig, q, hipsDrop: p.hipsDrop))
            worst = (max(worst.translation, e.translation), max(worst.rotation, e.rotation))
            XCTAssertLessThanOrEqual(e.translation, 1e-5, "姿勢 \(i) の骨の位置が従来と違う")
            XCTAssertLessThanOrEqual(e.rotation, 1e-5, "姿勢 \(i) の骨の回転が従来と違う")
        }
        print("HeroMotionClipTests: 従来の solve との差 最大 位置 \(worst.translation) m / 回転 \(worst.rotation)")
    }

    /// 同梱のヒーロー（あるだけ。A ポーズ・T ポーズのどちらのリグも）でも、手続きの姿勢は従来の solve と同じ骨になる。
    func testBundledRigsMatchLegacySolve() throws {
        var rng = SplitMix64(seed: 0xC11B_0002)
        func r(_ a: Float) -> Float { Float.random(in: -a...a, using: &rng) }
        var poses: [HeroPose] = [HeroPose(), profile("H001").rest, profile("H019").rest]
        for _ in 0..<12 {
            var p = HeroPose()
            p.hipsYaw = r(0.8); p.torsoPitch = r(0.8); p.torsoYaw = r(0.8); p.headYaw = r(0.8); p.hipsDrop = abs(r(0.2))
            p.armR = ArmPose(pitch: r(2.5), out: r(1.2), yaw: r(1.0), elbow: abs(r(2.0)))
            p.armL = ArmPose(pitch: r(2.5), out: r(1.2), yaw: r(1.0), elbow: abs(r(2.0)))
            p.legR = LegPose(pitch: r(1.5), out: r(0.6), knee: abs(r(2.0)))
            p.legL = LegPose(pitch: r(1.5), out: r(0.6), knee: abs(r(2.0)))
            poses.append(p)
        }
        var checked = 0
        for n in 1...24 {
            let id = String(format: "H%03d", n)
            guard let url = HeroAssetLibrary.bundledURL("Hero_\(id)"), let rig = HeroAssetLibrary.heroTemplate(url)?.rig else { continue }
            checked += 1
            var poser = HeroSkeletonPoser(rig: rig)
            for (i, p) in poses.enumerated() {
                let q = HeroSegmentRotations(p)
                poser.solve(q, hipsDrop: p.hipsDrop)
                let e = Self.maxError(poser.local, Self.legacySolve(rig, q, hipsDrop: p.hipsDrop))
                XCTAssertLessThanOrEqual(e.translation, 1e-5, "\(id) 姿勢 \(i) の骨の位置が従来と違う")
                XCTAssertLessThanOrEqual(e.rotation, 1e-5, "\(id) 姿勢 \(i) の骨の回転が従来と違う")
            }
        }
        print("HeroMotionClipTests: 同梱 \(checked) 体のリグで従来の solve と一致")
    }

    /// 手・足の区間は手首・足首だけを曲げる（前腕・脛は動かず、指・つま先が動く）。腰のずれは腰ごと動かす。
    func testHandFootDrivesAndHipsOffset() throws {
        let rig = try rig()
        var poser = HeroSkeletonPoser(rig: rig)
        let base = HeroSegmentRotations(HeroPose())
        poser.solve(base, hipsDrop: 0)
        let rest = poser.position
        var q = base
        q.handR = q.foreArmR * rx(1.0)
        q.footL = q.shinL * rx(-0.8)
        poser.solve(q, hipsDrop: 0)
        let i = { (r: HeroJointRole) in rig.index[r]! }
        XCTAssertLessThan(simd_distance(poser.position[i(.handR)], rest[i(.handR)]), 1e-5, "手首の位置は前腕で決まる")
        XCTAssertGreaterThan(simd_distance(poser.position[i(.indexR)], rest[i(.indexR)]), 0.01, "手の区間で指が動かない")
        XCTAssertLessThan(simd_distance(poser.position[i(.indexL)], rest[i(.indexL)]), 1e-5, "左手は動かない")
        XCTAssertGreaterThan(simd_distance(poser.position[i(.toeL)], rest[i(.toeL)]), 0.01, "足の区間でつま先が動かない")
        XCTAssertLessThan(simd_distance(poser.position[i(.toeR)], rest[i(.toeR)]), 1e-5, "右足は動かない")

        let offset = SIMD3<Float>(0.1, -0.2, 0.05)
        poser.solve(base, hipsDrop: 0.03, hipsOffset: offset)
        XCTAssertLessThan(simd_distance(poser.position[i(.hips)], rest[i(.hips)] + offset - SIMD3(0, 0.03, 0)), 1e-5)
        XCTAssertLessThan(simd_distance(poser.position[i(.head)], rest[i(.head)] + offset - SIMD3(0, 0.03, 0)), 1e-5)
    }

    /// 全フレームが Q_s = C_s⁻¹（元リグ自身のレスト）のクリップは、レストの jointTransforms を再現する。
    func testRestClipReproducesRestJointTransforms() throws {
        let rig = try rig()
        let inv: [simd_quatf] = (0..<HeroSegmentRotations.count).map { s in
            // 腰・胴・頭は C = 単位、四肢は骨のレスト補正（手 = 前腕、足 = 脛）
            guard s != 0, s != 1, s != 2, let j = Self.segmentJoint(rig, s) else { return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
            return rig.correction[j].inverse
        }
        let lib = try Self.library([Synth(name: "rest", frames: 3, rot: { _, s in inv[s] })])
        let (q, root) = lib.sample(0, time: 0.04)
        XCTAssertEqual(root, .zero)
        var poser = HeroSkeletonPoser(rig: rig)
        poser.solve(q, hipsDrop: 0, hipsOffset: root)
        let e = Self.maxError(poser.local, rig.restLocal)
        XCTAssertLessThan(e.translation, 1e-4, "位置がレストと違う")
        XCTAssertLessThan(e.rotation, 1e-4, "回転がレストと違う")

        // モデル経由（死亡クリップとして全身で重ね、手続きの倒れ・腰の沈みは止まる）
        let m = try makeSkinned()
        var set = HeroMotionSet()
        set.death = "rest"
        m.useMotion(set, library: lib)
        m.setState(.dead)
        for _ in 0..<20 { m.update(dt: 1.0 / 30.0, moveSpeed: 0) }
        XCTAssertEqual(m.clipLayer.clipName, "rest")
        let em = Self.maxError(m.skinnedEntity.jointTransforms, rig.restLocal)
        XCTAssertLessThan(em.translation, 1e-4, "モデルの骨の位置がレストと違う")
        XCTAssertLessThan(em.rotation, 1e-4, "モデルの骨の回転がレストと違う")
    }

    // MARK: 補間

    func testSamplingInterpolatesLoopsAndClamps() throws {
        let ramp = Synth(name: "ramp", frames: 4, rot: { f, _ in ry(Float(f) * 0.3) },
                         root: { f in SIMD3<Float>(0.1 * Float(f), 0.01 * Float(f), 0) })
        var loop = ramp
        loop.name = "loop"
        loop.loop = true
        let lib = try Self.library([ramp, loop])
        let r = try XCTUnwrap(lib.index(of: "ramp")), l = try XCTUnwrap(lib.index(of: "loop"))
        XCTAssertEqual(lib.clips[r].duration, 3.0 / 30, accuracy: 1e-6)
        XCTAssertEqual(lib.clips[l].duration, 4.0 / 30, accuracy: 1e-6)
        XCTAssertEqual(lib.clips[r].endTime, 3.0 / 30, accuracy: 1e-6, "end の省略時は最終フレーム")

        func hipsAngle(_ c: Int, _ frame: Float) -> (Float, SIMD3<Float>) {
            let (q, root) = lib.sample(c, time: frame / 30)
            for s in 0..<HeroSegmentRotations.count {
                XCTAssertLessThan(Self.rotationError(q[s], q.hips), 1e-6, "区間 \(s) が他と違う")
            }
            return (q.hips.angle * (q.hips.axis.y < 0 ? -1 : 1), root)
        }
        // フレームの中間
        var (a, root) = hipsAngle(r, 0.5)
        XCTAssertEqual(a, 0.15, accuracy: 1e-4)
        XCTAssertEqual(root.x, 0.05, accuracy: 1e-5)
        XCTAssertEqual(root.y, 0.005, accuracy: 1e-5)
        (a, _) = hipsAngle(r, 2.25)
        XCTAssertEqual(a, 0.675, accuracy: 1e-4)
        // 非ループは両端で止まる
        (a, root) = hipsAngle(r, 100)
        XCTAssertEqual(a, 0.9, accuracy: 1e-4)
        XCTAssertEqual(root.x, 0.3, accuracy: 1e-5)
        (a, _) = hipsAngle(r, -5)
        XCTAssertEqual(a, 0, accuracy: 1e-4)
        // ループは最終フレーム → 先頭へ補間し、1 周で折り返す
        (a, _) = hipsAngle(l, 3.5)
        XCTAssertEqual(a, 0.45, accuracy: 1e-4)
        (a, root) = hipsAngle(l, 5)
        XCTAssertEqual(a, 0.3, accuracy: 1e-4)
        XCTAssertEqual(root.x, 0.1, accuracy: 1e-5)
        (a, _) = hipsAngle(l, -1)
        XCTAssertEqual(a, 0.9, accuracy: 1e-4)
    }

    /// ファイルの区間の並びが違っても名前で並べ替える。区間が足りない・形が違う・長さの合わないクリップは落とす。
    func testDecodeRemapsSegmentsAndRejectsBadInput() throws {
        let names = HeroSegmentRotations.names
        let marked = Synth(name: "marked", frames: 2, rot: { _, s in rx(Float(s) * 0.1) })
        var skipped: [String] = []
        let lib = try HeroMotionLibrary.decode(try Self.json([marked], segments: names.reversed() + ["tail"]), skipped: &skipped)
        let (q, _) = lib.sample(0, time: 0)
        for s in 0..<names.count {
            XCTAssertLessThan(Self.rotationError(q[s], rx(Float(s) * 0.1)), 1e-5, "\(names[s]) の並べ替えが違う")
        }
        XCTAssertThrowsError(try HeroMotionLibrary.decode(try Self.json([marked], segments: Array(names.dropLast())), skipped: &skipped))
        XCTAssertThrowsError(try HeroMotionLibrary.decode(try Self.json([marked], version: 2), skipped: &skipped))
        XCTAssertThrowsError(try HeroMotionLibrary.decode(Data("[1, 2]".utf8), skipped: &skipped))
        XCTAssertThrowsError(try HeroMotionLibrary.decode(Data("not json".utf8), skipped: &skipped))

        // 回転の数が frames と合わないクリップだけを落とす
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: try Self.json([marked, Self.swing])) as? [String: Any])
        var clips = try XCTUnwrap(obj["clips"] as? [[String: Any]])
        clips[0]["frames"] = 3
        obj["clips"] = clips
        skipped = []
        let partial = try HeroMotionLibrary.decode(try JSONSerialization.data(withJSONObject: obj), skipped: &skipped)
        XCTAssertEqual(skipped, ["marked"])
        XCTAssertNil(partial.index(of: "marked"))
        XCTAssertEqual(partial.index(of: "swing"), 0)
        XCTAssertEqual(partial.clips[0].impact, 15)
    }

    /// 同梱ファイルが無い・壊れている時は空のライブラリ（手続きのみ）。
    func testMissingOrInvalidFileGivesEmptyLibrary() async throws {
        defer { HeroMotionClips.setResolverForTesting(nil) }
        XCTAssertTrue(HeroMotionClips.load(url: nil).isEmpty)
        let dir = FileManager.default.temporaryDirectory
        let missing = dir.appendingPathComponent("HeroMotionClips_missing_\(UUID().uuidString).json")
        XCTAssertTrue(HeroMotionClips.load(url: missing).isEmpty)
        let broken = dir.appendingPathComponent("HeroMotionClips_broken_\(UUID().uuidString).json")
        try Data("{\"version\": 1, \"clips\": [".utf8).write(to: broken)
        defer { try? FileManager.default.removeItem(at: broken) }
        XCTAssertTrue(HeroMotionClips.load(url: broken).isEmpty)
        let good = dir.appendingPathComponent("HeroMotionClips_good_\(UUID().uuidString).json")
        try Self.json([Self.swing]).write(to: good)
        defer { try? FileManager.default.removeItem(at: good) }
        XCTAssertEqual(HeroMotionClips.load(url: good).clips.count, 1)

        // shared は 1 度だけ読み、壊れていれば空のまま（モデルは手続きのみで作れる）
        HeroMotionClips.setResolverForTesting { broken }
        XCTAssertTrue(HeroMotionClips.shared.isEmpty)
        let m = try makeSkinned()
        XCTAssertNil(m.clipLayer.binding)
        m.setState(.attack)
        m.update(dt: 1.0 / 30.0, moveSpeed: 0)
        XCTAssertFalse(m.clipLayer.isActive)

        // ロード画面の非同期読み込み（メインスレッドの外でデコード）
        HeroMotionClips.setResolverForTesting { good }
        XCTAssertFalse(HeroMotionClips.isLoaded)
        await HeroMotionClips.preloadAsync()
        XCTAssertTrue(HeroMotionClips.isLoaded)
        XCTAssertEqual(HeroMotionClips.shared.index(of: "swing"), 0)

        // スキンメッシュの非同期読み込み（ロード画面の HeroModelLibrary.preloadAsync が使う）はクリップも並行して読む
        HeroAssetLibrary.resetForTesting()
        defer { HeroAssetLibrary.resetForTesting() }
        HeroMotionClips.setResolverForTesting { good }
        XCTAssertFalse(HeroMotionClips.isLoaded)
        let template = await HeroAssetLibrary.loadHeroTemplate(try Self.fixtureURL())
        XCTAssertNotNil(template)
        XCTAssertTrue(HeroMotionClips.isLoaded, "テンプレートの非同期読み込みでクリップが読まれない")
        XCTAssertEqual(HeroMotionClips.shared.index(of: "swing"), 0)
    }

    /// 同梱の HeroMotionClips.json（あれば）が読めて、暫定表の名前がどれだけ揃っているかを報告する。
    func testBundledLibraryAndProvisionalTable() throws {
        HeroMotionClips.setResolverForTesting(nil)
        let lib = HeroMotionClips.shared
        XCTAssertEqual(HeroMotionSets.table.count, 24)
        for n in 1...24 {
            let id = String(format: "H%03d", n)
            let set = try XCTUnwrap(HeroMotionSets.set(heroID: id), id)
            XCTAssertFalse(set.attacks.isEmpty, id)
            XCTAssertEqual(set.casts.count, 4, id)
        }
        guard Bundle.main.url(forResource: HeroMotionClips.resourceName, withExtension: "json") != nil else {
            print("HeroMotionClipTests: HeroMotionClips.json は未同梱（手続きのみ）")
            return
        }
        XCTAssertFalse(lib.isEmpty, "同梱の HeroMotionClips.json が読めない")
        var missing = Set<String>()
        for set in HeroMotionSets.table.values {
            let names = set.attacks + set.casts.compactMap { $0 } + [set.idle, set.run, set.death, set.victory, set.stunned, set.channel].compactMap { $0 }
            for name in names where lib.index(of: name) == nil { missing.insert(name) }
        }
        print("HeroMotionClipTests: 同梱 \(lib.clips.count) クリップ / 暫定表で未収録 \(missing.sorted())")
    }

    /// 同梱のクリップ（あれば）を同梱のヒーロー（あるだけ）に実行時と同じ計算で載せる。骨が有限で、ループは頭が腰より上。
    /// 立ったままのループ（待機・移動。腰の平均の沈みが脚の長さの 25% 未満）は脚のどこか（足首・つま先・膝）が地面の近く
    /// （抽出と実行時の約束 = docs/HERO_MOTION.md の区間回転・腰の位置が食い違うと、腰が浮く・沈む）。
    /// 膝立ち・しゃがみは元リグとの脚の比率の差で関節の中心が地面から離れやすい（メッシュの最下点は preview_clip.py の
    /// groundMin で見る）ので、値を報告するだけにする。
    func testBundledClipsPoseBundledRigsPlausibly() throws {
        HeroMotionClips.setResolverForTesting(nil)
        let lib = HeroMotionClips.shared
        guard !lib.isEmpty else { return print("HeroMotionClipTests: 同梱のクリップ無し") }
        var report: [String] = []
        for n in 1...24 {
            let id = String(format: "H%03d", n)
            guard let url = HeroAssetLibrary.bundledURL("Hero_\(id)"), let rig = HeroAssetLibrary.heroTemplate(url)?.rig else { continue }
            let rp = rig.restPosition
            let hips = try XCTUnwrap(rig.index[.hips]), head = try XCTUnwrap(rig.index[.head])
            let feet = [HeroJointRole.footL, .footR].compactMap { rig.index[$0] }
            guard feet.count == 2 else { continue }
            let restFoot = feet.map { rp[$0].y }.reduce(0, +) / 2
            let leg = max(0.1, rp[hips].y - restFoot)
            // 接地しうる骨（膝立ちは膝、つま先立ちはつま先）。レストで最も低いものを地面の基準にする
            let contacts = [HeroJointRole.footL, .footR, .toeL, .toeR, .legL, .legR].compactMap { rig.index[$0] }
            let restLowest = contacts.map { rp[$0].y }.min()!
            var poser = HeroSkeletonPoser(rig: rig)
            for (c, clip) in lib.clips.enumerated() {
                var lowest = Float.infinity
                var sinkSum: Float = 0
                for f in 0..<clip.frames {
                    var (q, root) = lib.sample(c, time: Float(f) / clip.fps)
                    root.x *= clip.rootXZ
                    root.z *= clip.rootXZ
                    sinkSum += root.y
                    poser.solve(q, hipsDrop: 0, hipsOffset: root * leg)
                    let finite = poser.position.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
                    if !finite { return XCTFail("\(id) \(clip.name) フレーム \(f) の骨が NaN") }
                    lowest = min(lowest, contacts.map { poser.position[$0].y }.min()!)
                    if clip.loop {
                        XCTAssertGreaterThan(poser.position[head].y, poser.position[hips].y, "\(id) \(clip.name) フレーム \(f) 頭が腰より下")
                    }
                }
                let standing = sinkSum / Float(clip.frames) > -0.25
                if clip.loop && standing {
                    XCTAssertEqual(lowest, restLowest, accuracy: 0.08, "\(id) \(clip.name) 立ったままのループで脚が地面から離れる・沈む")
                }
                if clip.loop && (n == 1 || n == 4 || !standing) {
                    report.append("\(id) \(clip.name) 最も低い脚の骨 \(String(format: "%.3f", lowest)) m（レスト \(String(format: "%.3f", restLowest))）")
                }
            }
        }
        print("HeroMotionClipTests: " + report.joined(separator: " / "))
    }

    // MARK: 通常攻撃の拍

    /// playAttack(windup:) の windup 秒後にクリップの打撃フレームが来る（再生速度の範囲外は開始位置をずらす）。
    func testAttackImpactLandsAtWindup() throws {
        let lib = try Self.library([Self.swing])
        var set = HeroMotionSet()
        set.attacks = ["swing"]
        let binding = try XCTUnwrap(HeroMotionBinding(set: set, library: lib))
        let dt: Float = 1.0 / 60
        for (windup, interval) in [(Float(0.3), Float(0.8)), (0.1, 0.8), (1.5, 2.0), (0.5, 0.6)] {
            var a = HeroAnimator(profile: profile("H001"), defaultRunSpeed: 3.3, motion: binding)
            _ = a.advance(dt: dt, moveSpeed: 0)
            a.playAttack(windup: windup, interval: interval)
            XCTAssertEqual(a.state, .attack)
            XCTAssertEqual(a.clips.role, .attack)
            let steps = Int((windup / dt).rounded())
            for _ in 0..<steps { _ = a.advance(dt: dt, moveSpeed: 0) }
            XCTAssertEqual(a.clips.frame, 15, accuracy: 1, "windup \(windup): 打撃が \(windup) 秒後に来ない frame=\(a.clips.frame)")
            // 戻り（打撃 → 最終フレーム）は max(0.2, interval - windup) 秒に収まる（1 倍速より遅くはしない）
            let recover = Int((max(0.2, interval - windup) / dt).rounded()) + 1
            for _ in 0..<recover { _ = a.advance(dt: dt, moveSpeed: 0) }
            XCTAssertTrue(a.clips.finished, "windup \(windup) interval \(interval): 戻りが interval に収まらない")
            XCTAssertGreaterThanOrEqual(a.clips.postRate, 1)
            XCTAssertTrue(a.clips.holdAtEnd, "拍待ちの攻撃は最後の姿勢で待つ")
        }
        // 速度の範囲: windup 0.1 → 打撃まで 4 倍（上限）、1.5 → 0.5 倍（下限）
        var fast = HeroAnimator(profile: profile("H001"), defaultRunSpeed: 3.3, motion: binding)
        fast.playAttack(windup: 0.1, interval: 0.8)
        XCTAssertEqual(fast.clips.preRate, 4)
        XCTAssertEqual(fast.clips.clipTime, 0.5 - 0.4, accuracy: 1e-5, "上限で足りない分だけ先から始める")
        var slow = HeroAnimator(profile: profile("H001"), defaultRunSpeed: 3.3, motion: binding)
        slow.playAttack(windup: 1.5, interval: 2)
        XCTAssertEqual(slow.clips.preRate, 0.5)
        XCTAssertLessThan(slow.clips.clipTime, 0, "下限で余る分は先頭で待つ")
    }

    /// setState(.attack) だけ（プレビュー）でも振り続け、playAttack はモデルの操作ハンドルから呼べる。
    func testAttackStateCyclesClipsAndHandleForwardsPlayAttack() throws {
        var b = Self.swing
        b.name = "swing_b"
        let lib = try Self.library([Self.swing, b])
        var set = HeroMotionSet()
        set.attacks = ["swing", "missing_name", "swing_b"]
        let m = try makeSkinned()
        m.useMotion(set, library: lib)
        m.setState(.attack)
        var names: [String] = []
        for _ in 0..<120 {
            m.update(dt: 1.0 / 30.0, moveSpeed: 0)
            if let n = m.clipLayer.clipName, names.last != n { names.append(n) }
        }
        XCTAssertGreaterThanOrEqual(names.count, 3, "攻撃状態のまま次の振りへ進まない \(names)")
        XCTAssertEqual(Array(names.prefix(3)), ["swing", "swing_b", "swing"], "無い名前を飛ばして順に繰り返さない")

        let handle: HeroModelHandle = m
        m.setState(.idle)
        for _ in 0..<30 { m.update(dt: 1.0 / 30.0, moveSpeed: 0) }
        XCTAssertFalse(m.clipLayer.isActive, "待機でクリップが残る")
        handle.playAttack(windup: 0.3, interval: 0.8)
        XCTAssertEqual(m.state, .attack)
        for _ in 0..<9 { m.update(dt: 1.0 / 30.0, moveSpeed: 0) }
        XCTAssertEqual(m.clipLayer.frame, 15, accuracy: 1)
        // 手続きモデルは既定の何もしない実装
        let proc = HeroModelLibrary.makeHero(heroID: "H001", skinID: nil, team: .blue, master: master,
                                             options: HeroModelOptions.showcase.with(mesh: .procedural))
        (proc as HeroModelHandle).playAttack(windup: 0.3, interval: 0.8)
        XCTAssertEqual(proc.state, .idle)
    }

    /// 描画側が setState(.attack) と playAttack を続けて呼んでも、割り当ての順を飛ばさず同じ振りを拍に合わせ直す。
    func testSetStateThenPlayAttackDoesNotSkipClip() throws {
        var b = Self.swing
        b.name = "swing_b"
        let lib = try Self.library([Self.swing, b])
        var set = HeroMotionSet()
        set.attacks = ["swing", "swing_b"]
        let binding = try XCTUnwrap(HeroMotionBinding(set: set, library: lib))
        let dt: Float = 1.0 / 60
        var a = HeroAnimator(profile: profile("H001"), defaultRunSpeed: 3.3, motion: binding)
        _ = a.advance(dt: dt, moveSpeed: 0)
        var names: [String] = []
        for _ in 0..<4 {
            a.setState(.attack)
            a.playAttack(windup: 0.2, interval: 0.6)
            names.append(a.clips.clipName ?? "-")
            // 打撃 15 フレーム（0.5 秒）を 0.2 秒後へ: 2.5 倍・先頭から
            XCTAssertEqual(a.clips.preRate, 2.5, accuracy: 1e-5)
            XCTAssertEqual(a.clips.clipTime, 0, accuracy: 1e-5)
            for _ in 0..<12 { _ = a.advance(dt: dt, moveSpeed: 0) }
            XCTAssertEqual(a.clips.frame, 15, accuracy: 1)
            for _ in 0..<26 { _ = a.advance(dt: dt, moveSpeed: 0) }
            XCTAssertTrue(a.clips.finished)
            a.setState(.idle)
            for _ in 0..<12 { _ = a.advance(dt: dt, moveSpeed: 0) }
            XCTAssertFalse(a.clips.isActive, "攻撃の後に待機のクリップが無ければ手続きへ戻る")
        }
        XCTAssertEqual(names, ["swing", "swing_b", "swing", "swing_b"])
    }

    /// applyPose（検査用）は手続きの姿勢だけを置く（再生中のクリップを重ねない）。
    func testApplyPoseIgnoresClipOverlay() throws {
        let lib = try Self.library([Self.wild])
        var set = HeroMotionSet()
        set.attacks = ["wild"]
        let a = try makeSkinned(), b = try makeSkinned()
        a.useMotion(set, library: lib)
        b.useMotion(nil, library: lib)
        a.setState(.attack)
        for _ in 0..<6 { a.update(dt: 1.0 / 30.0, moveSpeed: 0) }
        XCTAssertGreaterThan(a.clipLayer.upperWeight, 0.99)
        var p = HeroPose()
        p.armR = ArmPose(pitch: 1.2, out: 0.2, yaw: 0.1, elbow: 0.6)
        p.legL = LegPose(pitch: 0.4, out: 0.05, knee: 0.7)
        p.hipsDrop = 0.05
        a.applyPose(p)
        b.applyPose(p)
        let e = Self.maxError(a.skinnedEntity.jointTransforms, b.skinnedEntity.jointTransforms)
        XCTAssertLessThan(e.translation, 1e-6)
        XCTAssertLessThan(e.rotation, 1e-6)
        XCTAssertEqual(a.weapon.transform, b.weapon.transform)
    }

    /// 立ち止まっていれば全身、移動中は上半身だけ（脚・腰は手続きの走り）。
    func testAttackMaskFollowsSpeed() throws {
        let lib = try Self.library([Self.wild])
        var set = HeroMotionSet()
        set.attacks = ["wild"]
        let a = try makeSkinned(), b = try makeSkinned()
        a.useMotion(set, library: lib)
        b.useMotion(nil, library: lib)
        for m in [a, b] { m.setState(.attack) }
        for _ in 0..<6 {
            for m in [a, b] { m.update(dt: 1.0 / 30.0, moveSpeed: 330) }
        }
        let ja = joints(a), jb = joints(b)
        for role in [HeroJointRole.hips, .upLegR, .legR, .footR, .upLegL, .legL, .footL, .toeL] {
            XCTAssertLessThan(simd_distance(try XCTUnwrap(ja[role]), try XCTUnwrap(jb[role])), 1e-4, "移動中に \(role) がクリップで動く")
        }
        XCTAssertGreaterThan(simd_distance(try XCTUnwrap(ja[.handR]), try XCTUnwrap(jb[.handR])), 0.02, "上半身にクリップが乗らない")
        // 立ち止まると下半身も重なる
        for _ in 0..<15 { a.update(dt: 1.0 / 30.0, moveSpeed: 0) }
        XCTAssertGreaterThan(a.clipLayer.lowerWeight, 0.99)
    }

    // MARK: 状態のループ・ループクリップの割り当て

    /// 待機のクリップがあれば、生成直後（状態は最初から待機で setState が来ない）から再生する。
    func testIdleClipPlaysFromSpawn() throws {
        let lib = try Self.library([Synth(name: "breathe", frames: 30, loop: true, rot: { f, _ in ry(0.1 * sin(Float(f) * 0.2)) })])
        var set = HeroMotionSet()
        set.idle = "breathe"
        let binding = try XCTUnwrap(HeroMotionBinding(set: set, library: lib))
        var a = HeroAnimator(profile: profile("H001"), defaultRunSpeed: 3.3, motion: binding)
        for _ in 0..<10 { _ = a.advance(dt: 1.0 / 30.0, moveSpeed: 0) }
        XCTAssertEqual(a.state, .idle)
        XCTAssertEqual(a.clips.clipName, "breathe", "生成直後の待機でクリップが始まらない")
        XCTAssertGreaterThan(a.clips.upperWeight, 0.99)
    }

    /// ループのクリップを通常攻撃・詠唱に割り当てても 1 回で終わる（待機・移動へ戻った後も重なり続けない）。
    func testLoopClipAssignedToActionPlaysOnce() throws {
        let chant = Synth(name: "chant", frames: 20, loop: true, events: ["impact": 8],
                          rot: { f, s in s == 3 ? rx(1.5 * sin(Float(f) * 0.3)) : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) })
        let lib = try Self.library([chant])
        var set = HeroMotionSet()
        set.attacks = ["chant"]
        set.casts = ["chant", nil, nil, nil]
        let binding = try XCTUnwrap(HeroMotionBinding(set: set, library: lib))
        let dt: Float = 1.0 / 30
        var a = HeroAnimator(profile: profile("H004"), defaultRunSpeed: 3.3, motion: binding)
        a.setState(.cast(.skill1))
        XCTAssertEqual(a.clips.role, .cast)
        for _ in 0..<15 { _ = a.advance(dt: dt, moveSpeed: 0) }
        a.setState(.idle)
        for _ in 0..<60 { _ = a.advance(dt: dt, moveSpeed: 0) }
        XCTAssertFalse(a.clips.isActive, "ループの詠唱クリップが待機に残り続ける")

        a.playAttack(windup: 0.2, interval: 0.6)
        XCTAssertEqual(a.clips.role, .attack)
        for _ in 0..<6 { _ = a.advance(dt: dt, moveSpeed: 0) }
        XCTAssertEqual(a.clips.frame, 8, accuracy: 1, "ループの攻撃クリップでも打撃が windup 秒後に来ない")
        a.setState(.run)
        for _ in 0..<60 { _ = a.advance(dt: dt, moveSpeed: 330) }
        XCTAssertFalse(a.clips.isActive, "ループの攻撃クリップが移動に残り続ける")
    }

    // MARK: 詠唱・死亡

    func testCastClipImpactComesShortlyAfterCall() throws {
        let cast = Synth(name: "cast", frames: 40, events: ["impact": 20])
        let lib = try Self.library([cast])
        var set = HeroMotionSet()
        set.casts = [nil, "cast", nil, nil]
        let m = try makeSkinned("H004")
        m.useMotion(set, library: lib)
        m.setState(.cast(.skill1))
        m.update(dt: 1.0 / 60.0, moveSpeed: 0)
        XCTAssertFalse(m.clipLayer.isActive, "Skill1 は割り当てが無いので手続き")
        m.setState(.cast(.skill2))
        XCTAssertEqual(m.clipLayer.frame, 20 - 0.12 * 30, accuracy: 1e-3)
        for _ in 0..<4 { m.update(dt: 0.03, moveSpeed: 0) }
        XCTAssertEqual(m.clipLayer.frame, 20, accuracy: 0.5, "詠唱の 0.12 秒後に打撃が来ない")
        for _ in 0..<60 { m.update(dt: 1.0 / 30.0, moveSpeed: 0) }
        XCTAssertFalse(m.clipLayer.isActive, "詠唱のクリップが終わっても消えない")
    }

    /// 死亡クリップは最後のフレームで止まり、手続きの倒れ（全身の傾き・沈み）を止めて腰の位置はクリップが持つ。不透明度は手続きのまま消える。
    func testDeathClipHoldsLastFrameAndOwnsTheFall() throws {
        let fall = Synth(name: "fall", frames: 10, rot: { f, s in s == 0 ? rx(-0.15 * Float(f)) : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) },
                         root: { f in SIMD3<Float>(0, -0.5 * Float(f) / 9, 0) })
        let lib = try Self.library([fall])
        var set = HeroMotionSet()
        set.death = "fall"
        let m = try makeSkinned("H007")
        m.useMotion(set, library: lib)
        let hips0 = try XCTUnwrap(joints(m)[.hips])
        m.setState(.dead)
        for _ in 0..<90 { m.update(dt: 1.0 / 60.0, moveSpeed: 0) }
        XCTAssertTrue(m.clipLayer.finished && m.clipLayer.holdAtEnd)
        XCTAssertEqual(m.clipLayer.frame, 9, accuracy: 1e-4)
        let body = try XCTUnwrap(m.root.children.first)
        let motion = try XCTUnwrap(body.children.first)
        XCTAssertLessThan(simd_length(motion.position), 1e-5, "手続きの倒れ（移動）が残る")
        XCTAssertLessThan(Self.rotationError(motion.orientation, simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)), 1e-5, "手続きの倒れ（傾き）が残る")
        let scale = HeroBlueprints.blueprint(heroID: "H007", role: nil).scale
        let hips1 = try XCTUnwrap(joints(m)[.hips])
        XCTAssertEqual(hips0.y - hips1.y, 0.5 * m.clipLegLength * scale, accuracy: 0.01, "腰がクリップの位置へ下りない")
        XCTAssertLessThan(body.components[OpacityComponent.self]?.opacity ?? 1, 0.05, "死亡のフェードが止まった")
        // 復活は即座に手続きへ
        m.setState(.idle)
        m.update(dt: 1.0 / 60.0, moveSpeed: 0)
        XCTAssertFalse(m.clipLayer.isActive)
        XCTAssertNil(body.components[OpacityComponent.self])
    }

    // MARK: 武器・フォールバック

    /// クリップ再生中も武器・副手は手から離れない（握りは手の区間に追従）。
    func testWeaponStaysInHandWhileClipPlays() throws {
        let lib = try Self.library([Self.wild])
        var set = HeroMotionSet()
        set.attacks = ["wild"]
        set.casts = ["wild", "wild", "wild", "wild"]
        set.death = "wild"
        set.victory = "wild"
        for id in ["H001", "H003", "H007", "H021"] {
            let m = try makeSkinned(id)
            m.useMotion(set, library: lib)
            var worst: Float = 0
            var maxWeight: Float = 0
            for (i, s) in [HeroAnimState.attack, .cast(.skill3), .run, .victory, .dead].enumerated() {
                m.setState(s)
                for k in 0..<30 {
                    if s == .attack && k % 10 == 0 { m.playAttack(windup: 0.2, interval: 0.5) }
                    m.update(dt: 1.0 / 30.0, moveSpeed: Double(i % 2) * 330)
                    let j = joints(m)
                    let w = m.weapon.position(relativeTo: m.root), o = m.offhand.position(relativeTo: m.root)
                    worst = max(worst, simd_distance(w, try XCTUnwrap(j[.handR])), simd_distance(o, try XCTUnwrap(j[.handL])))
                    maxWeight = max(maxWeight, m.clipLayer.upperWeight)
                    for t in m.skinnedEntity.jointTransforms {
                        let ok = t.translation.x.isFinite && t.translation.y.isFinite && t.translation.z.isFinite
                            && t.rotation.vector.x.isFinite && t.rotation.vector.w.isFinite
                        if !ok { return XCTFail("\(id) \(s) 骨が NaN") }
                    }
                }
            }
            print("HeroMotionClipTests: \(id) クリップ再生中の武器と手の最大距離 \(worst) m")
            XCTAssertGreaterThan(maxWeight, 0.99, "\(id) クリップが重ならない")
            XCTAssertLessThan(worst, 0.1, "\(id) 武器が手から離れる")
        }
    }

    /// 割り当ての名前がライブラリに無ければ手続きと同じ（骨・武器とも）。
    func testMissingClipNamesFallBackToProcedural() throws {
        let lib = try Self.library([Self.swing])
        var set = HeroMotionSet()
        set.attacks = ["nope_1", "nope_2"]
        set.casts = ["nope_3", nil, "nope_4", nil]
        set.death = "nope_5"
        set.idle = "nope_6"
        XCTAssertNil(HeroMotionBinding(set: set, library: lib))
        XCTAssertNil(HeroMotionBinding(set: HeroMotionSet(), library: lib))
        // 一部だけ無い名前は落とす
        set.attacks = ["nope_1", "swing"]
        XCTAssertEqual(HeroMotionBinding(set: set, library: lib)?.attacks, [0])
        XCTAssertNil(HeroMotionBinding(set: set, library: lib)?.death)
        set.attacks = ["nope_1"]

        let a = try makeSkinned(), b = try makeSkinned()
        a.useMotion(set, library: lib)
        b.useMotion(nil, library: lib)
        let states: [HeroAnimState] = [.idle, .run, .attack, .cast(.skill1), .cast(.ultimate), .channel, .stunned, .victory, .dead, .idle]
        for (i, s) in states.enumerated() {
            a.setState(s)
            b.setState(s)
            a.playAttack(windup: 0.3, interval: 0.8)
            b.playAttack(windup: 0.3, interval: 0.8)
            a.setState(s)
            b.setState(s)
            for k in 0..<12 {
                let speed = Double((i + k) % 3) * 160
                a.update(dt: 1.0 / 30.0, moveSpeed: speed)
                b.update(dt: 1.0 / 30.0, moveSpeed: speed)
                let e = Self.maxError(a.skinnedEntity.jointTransforms, b.skinnedEntity.jointTransforms)
                XCTAssertEqual(e.translation, 0, "\(s) \(k)")
                XCTAssertEqual(e.rotation, 0, "\(s) \(k)")
                XCTAssertEqual(a.weapon.transform, b.weapon.transform)
                XCTAssertEqual(a.offhand.transform, b.offhand.transform)
            }
        }
        XCTAssertFalse(a.clipLayer.isActive)
    }

    // MARK: Python（抽出・プレビュー）との突き合わせ

    private static func number(_ v: Any?) throws -> Float {
        try XCTUnwrap(v as? NSNumber, "数値でない: \(String(describing: v))").floatValue
    }

    private static func vector(_ v: Any?) throws -> SIMD3<Float> {
        let a = try XCTUnwrap(v as? [NSNumber], "配列でない: \(String(describing: v))").map(\.floatValue)
        return try XCTUnwrap(a.count == 3 ? SIMD3(a[0], a[1], a[2]) : nil, "3 要素でない: \(a)")
    }

    /// JSON の (x, y, z, w)。
    private static func quaternion(_ v: Any?) throws -> simd_quatf {
        let a = try XCTUnwrap(v as? [NSNumber], "配列でない: \(String(describing: v))").map(\.floatValue)
        return try XCTUnwrap(a.count == 4 ? simd_quatf(ix: a[0], iy: a[1], iz: a[2], r: a[3]) : nil, "4 要素でない: \(a)")
    }

    /// clip_math.Rig の駆動の名前と同じ表記（spine は t を小数 4 桁、四肢・手・足は区間名）。
    private static func driveName(_ d: HeroSkeletonRig.Drive) -> String {
        if case .spine(let t) = d { return String(format: "spine:%.4f", t) }
        return String(describing: d)
    }

    /// jointTransforms を親から累積した骨の位置（添字順、ancestor の座標 = motion ならヒーロー空間）。
    private func jointPositions(_ m: SkinnedHeroModel, relativeTo ancestor: Entity) -> [SIMD3<Float>] {
        let e = m.skinnedEntity
        let names = e.jointNames
        let local = e.jointTransforms
        var byPath: [String: Int] = [:]
        for (i, n) in names.enumerated() { byPath[n] = i }
        var cache: [Int: simd_float4x4] = [:]
        func model(_ i: Int) -> simd_float4x4 {
            if let c = cache[i] { return c }
            var mtx = local[i].matrix
            if let slash = names[i].lastIndex(of: "/"), let p = byPath[String(names[i][..<slash])] { mtx = model(p) * mtx }
            cache[i] = mtx
            return mtx
        }
        let toAncestor = e.transformMatrix(relativeTo: ancestor)
        return names.indices.map { i in
            let p = toAncestor * model(i).columns.3
            return SIMD3(p.x, p.y, p.z)
        }
    }

    /// tools/blender/make_clip_crosscheck.py が書いたフィクスチャ（Fixtures/MotionClips/crosscheck.json）を実行時の経路
    /// （HeroMotionLibrary.decode → HeroClipLayer の補間・rootXZ → HeroSkeletonPoser.solve、最後はモデル経由）で解き、
    /// Python 版の実行時の計算（clip_math.interp_clip + Rig.solve）と関節の位置が 1 mm 以内で一致することを確かめる。
    /// クリップは Blender で既知の動きを付けたフィクスチャのリグから extract_clips.extract で抜いたもの（そのまま / 反転 + yaw + ループ）。
    /// 同じファイルのレスト（位置・補正 C・駆動・脚の長さ）、rotationBetween の表（反平行）、元のアニメーション
    /// （Blender の評価）とも突き合わせる（docs/HERO_MOTION.md の約束が両側で同じであること）。
    /// 環境変数 VELSTRIA_CROSSCHECK_EXTRA（":" 区切りのパス。xcodebuild には TEST_RUNNER_ を付けて渡す）があれば、
    /// 同梱のヒーローで作った一時的なファイル（make_clip_crosscheck.py --fixture Hero_<ID>.usdz）も同じ検査に通す。
    func testCrossCheckFixtureMatchesPythonSolve() throws {
        let url = try XCTUnwrap(Bundle(for: HeroMotionClipTests.self).url(forResource: "crosscheck", withExtension: "json"),
                                "crosscheck.json がテストバンドルに無い")
        try crossCheck(url)
        let extra = ProcessInfo.processInfo.environment["VELSTRIA_CROSSCHECK_EXTRA"] ?? ""
        for path in extra.split(separator: ":") where !path.isEmpty {
            try crossCheck(URL(fileURLWithPath: String(path)))
        }
    }

    private func crossCheck(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        var skipped: [String] = []
        let lib = try HeroMotionLibrary.decode(data, skipped: &skipped)
        XCTAssertEqual(skipped, [], "フィクスチャのクリップが落とされた")
        let top = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let xc = try XCTUnwrap(top["crosscheck"] as? [String: Any])
        let tolerance = try Self.number(xc["toleranceMeters"])
        XCTAssertLessThanOrEqual(tolerance, 0.001)

        // クリップの属性（events は出力フレーム、rootXZ・loop はそのまま）
        let basic = try XCTUnwrap(lib.index(of: "xc_basic")), mirrored = try XCTUnwrap(lib.index(of: "xc_mirror_yaw"))
        XCTAssertEqual(lib.clips[basic].frames, 5)
        XCTAssertEqual(lib.clips[basic].impact ?? -1, 2.5, accuracy: 1e-6)
        XCTAssertEqual(lib.clips[basic].rootXZ, 1)
        XCTAssertFalse(lib.clips[basic].loop)
        XCTAssertEqual(lib.clips[mirrored].frames, 4)
        XCTAssertTrue(lib.clips[mirrored].loop)
        XCTAssertEqual(lib.clips[mirrored].rootXZ, 0.5)
        XCTAssertNotNil(lib.index(of: "xc_signs"), "符号を反転したクリップが無い")

        // rotationBetween（反平行・ほぼ平行のしきい値・一般の向き）。q と -q は同じ回転
        for case let e as [String: Any] in try XCTUnwrap(xc["rotationBetween"] as? [Any]) {
            let a = try Self.vector(e["a"]), b = try Self.vector(e["b"])
            XCTAssertLessThan(Self.rotationError(rotationBetween(a, b), try Self.quaternion(e["q"])), 1e-4,
                              "rotationBetween(\(a), \(b)) が Python と違う")
        }

        // リグ: フィクスチャ（SkinnedTestHero）か同梱のヒーロー（Hero_<ID>）
        let rigName = try XCTUnwrap(xc["rig"] as? String)
        let rigURL = try XCTUnwrap(rigName == "SkinnedTestHero" ? try Self.fixtureURL() : HeroAssetLibrary.bundledURL(rigName),
                                   "\(rigName) が無い")
        let rig = try XCTUnwrap(HeroAssetLibrary.heroTemplate(rigURL), "\(rigName) が読めない").rig

        // レスト: 関節の位置・補正 C・駆動（名前は USD の関節パスの末尾 = Blender の骨名）
        var byLeaf: [String: Int] = [:]
        for (i, path) in rig.jointNames.enumerated() {
            byLeaf[path.split(separator: "/").last.map(String.init) ?? path] = i
        }
        let joints = try XCTUnwrap(xc["joints"] as? [[String: Any]])
        XCTAssertEqual(joints.count, rig.jointNames.count, "骨の数が違う")
        var order: [Int] = []
        var names: [String] = []
        for jt in joints {
            let name = try XCTUnwrap(jt["name"] as? String)
            let j = try XCTUnwrap(byLeaf[name], "\(name) がリグに無い")
            order.append(j)
            names.append(name)
            XCTAssertLessThan(simd_distance(rig.restPosition[j], try Self.vector(jt["position"])), 1e-4, "\(name) のレストの位置")
            XCTAssertLessThan(Self.rotationError(rig.correction[j], try Self.quaternion(jt["correction"])), 1e-4, "\(name) の補正 C")
            XCTAssertEqual(Self.driveName(rig.drive[j]), jt["drive"] as? String, "\(name) の駆動")
        }
        let model = try XCTUnwrap(HeroModelLibrary.makeHero(heroID: "H001", skinID: nil, team: .blue, master: master,
                                                            options: HeroModelOptions.showcase.with(mesh: .skinned(rigURL)))
                                  as? SkinnedHeroModel, "\(rigName) がスキンメッシュで生成されない")
        let legLength = model.clipLegLength
        XCTAssertEqual(legLength, try Self.number(xc["legLength"]), accuracy: 1e-4, "脚の長さ L（腰の位置の単位）が違う")

        /// 期待値（位置・ΔR）と比べ、最大の差（m・四元数の成分）を返す。
        func compare(_ positions: [SIMD3<Float>], _ rotations: [simd_quatf]?, _ e: [String: Any], _ label: String,
                     tolerance: Float) throws -> (Float, Float) {
            let wantP = try XCTUnwrap(e["positions"] as? [Any]), wantR = try XCTUnwrap(e["rotations"] as? [Any])
            XCTAssertEqual(wantP.count, order.count)
            // 食い違いは標本ごとに最も大きい骨だけを報告する（約束の違いは全身の骨に及ぶので）
            var worstP: (Float, String) = (0, ""), worstR: (Float, String) = (0, "")
            for (k, j) in order.enumerated() {
                let dp = simd_distance(positions[j], try Self.vector(wantP[k]))
                if dp > worstP.0 { worstP = (dp, names[k]) }
                if let rotations {
                    let dr = Self.rotationError(rotations[j], try Self.quaternion(wantR[k]))
                    if dr > worstR.0 { worstR = (dr, names[k]) }
                }
            }
            XCTAssertLessThan(worstP.0, tolerance, "\(label) \(worstP.1) の位置が \(worstP.0 * 1000) mm 違う")
            XCTAssertLessThan(worstR.0, 2e-3, "\(label) \(worstR.1) の回転 ΔR が違う（四元数の成分 \(worstR.0)）")
            return (worstP.0, worstR.0)
        }

        // 区間回転 → 骨（実行時の経路: HeroClipLayer が補間と rootXZ、solve の腰のずれは L 倍）
        var set = HeroMotionSet()
        set.idle = "xc_basic"
        let binding = try XCTUnwrap(HeroMotionBinding(set: set, library: lib))
        var poser = HeroSkeletonPoser(rig: rig)
        func solve(_ clip: String, time: Float) throws -> ([SIMD3<Float>], [simd_quatf]) {
            let c = try XCTUnwrap(lib.index(of: clip), clip)
            var layer = HeroClipLayer(binding: binding)
            layer.start(c, role: .state, from: time, fullBody: true, speedMask: false, hold: true)
            poser.solve(layer.pose, hipsDrop: 0, hipsOffset: layer.root * legLength)
            let dR = rig.jointNames.indices.map { poser.rotation[$0] * rig.restRotation[$0].inverse }
            return (poser.position, dR)
        }
        var worst: (Float, Float) = (0, 0)
        let samples = try XCTUnwrap(xc["samples"] as? [[String: Any]])
        XCTAssertFalse(samples.isEmpty)
        for e in samples {
            let clip = try XCTUnwrap(e["clip"] as? String), time = try Self.number(e["time"])
            let (p, r) = try solve(clip, time: time)
            let w = try compare(p, r, e, "\(rigName) \(clip) t=\(time)", tolerance: tolerance)
            worst = (max(worst.0, w.0), max(worst.1, w.1))
        }
        // 元のアニメーション（Blender の評価）: 抽出 → 実行時の往復で元の姿勢に戻る（動きは実行時の駆動で表せるものだけ）
        var worstSource: (Float, Float) = (0, 0)
        for e in try XCTUnwrap(xc["source"] as? [[String: Any]]) {
            let clip = try XCTUnwrap(e["clip"] as? String), time = try Self.number(e["time"])
            let (p, r) = try solve(clip, time: time)
            let w = try compare(p, r, e, "\(rigName) 元の姿勢 \(clip) t=\(time)", tolerance: tolerance)
            worstSource = (max(worstSource.0, w.0), max(worstSource.1, w.1))
        }

        // モデル経由（死亡クリップとして全身で重ね、最後のフレームで止まる）。jointTransforms を motion の座標へ累積して比べる
        let last = try XCTUnwrap(samples.first { ($0["clip"] as? String) == "xc_basic" && (($0["frame"] as? NSNumber)?.floatValue ?? -1) == 4 })
        var death = HeroMotionSet()
        death.death = "xc_basic"
        model.useMotion(death, library: lib)
        model.setState(.dead)
        for _ in 0..<60 { model.update(dt: 1.0 / 30.0, moveSpeed: 0) }
        XCTAssertTrue(model.clipLayer.finished && model.clipLayer.clipName == "xc_basic")
        XCTAssertEqual(model.clipLayer.lowerWeight, 1)
        let motion = try XCTUnwrap(model.root.children.first?.children.first)
        let wModel = try compare(jointPositions(model, relativeTo: motion), nil, last, "\(rigName) モデル経由 xc_basic 最終フレーム",
                                 tolerance: tolerance)
        print(String(format: "HeroMotionClipTests: %@ Python との差 最大 位置 %.4f mm / ΔR %.2e、元の姿勢との差 %.4f mm / %.2e、モデル経由 %.4f mm（%d 標本）",
                     rigName, worst.0 * 1000, worst.1, worstSource.0 * 1000, worstSource.1, wModel.0 * 1000, samples.count))
    }

    // MARK: 性能

    /// クリップを重ねた 10 体の更新が予算内（SkinnedHeroModelTests.testTemplateLoadAndUpdateCost と同じ上限）。
    func testUpdateCostWithClips() throws {
        let lib = try Self.library([Self.swing, Self.wild, Synth(name: "loop", frames: 30, loop: true, rot: { f, s in ry(0.1 * sin(Float(f + s))) })])
        var set = HeroMotionSet()
        set.attacks = ["swing", "wild"]
        set.run = "loop"
        set.idle = "loop"
        let ids = ["H001", "H004", "H007", "H011", "H013", "H016", "H019", "H021", "H022", "H024"]
        let models = try ids.map { try makeSkinned($0) }
        for (i, m) in models.enumerated() {
            m.useMotion(set, library: lib)
            m.setState(i % 3 == 0 ? .attack : .run)
        }
        let frames = 300
        let start = CFAbsoluteTimeGetCurrent()
        for f in 0..<frames {
            for (i, m) in models.enumerated() {
                if i % 3 == 0 && f % 40 == 0 { m.playAttack(windup: 0.25, interval: 0.66) }
                m.update(dt: 1.0 / 60.0, moveSpeed: 330)
            }
        }
        let perFrameMs = (CFAbsoluteTimeGetCurrent() - start) / Double(frames) * 1000
        print(String(format: "HeroMotionClipTests: クリップを重ねた 10 体の更新 %.3f ms/フレーム", perFrameMs))
        XCTAssertTrue(models.allSatisfy { $0.clipLayer.isActive })
        XCTAssertLessThan(perFrameMs, 8)
    }
}
