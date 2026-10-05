import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// スキンメッシュ（Tripo 生成・Mixamo 名の骨）を手続きアニメーションで動かすモデルの検査。
/// AppTests/Fixtures/SkinnedTestHero.usdz（正規化済みの T ポーズ人型・27 骨）を使う。
@MainActor
final class SkinnedHeroModelTests: XCTestCase {
    private let master = MasterData.shared

    private static func fixture(_ name: String) -> URL? {
        Bundle(for: SkinnedHeroModelTests.self).url(forResource: name, withExtension: "usdz")
    }

    private func makeSkinned(_ heroID: String = "H003", skinID: String? = nil, team: Team = .neutral,
                             options: HeroModelOptions = .showcase,
                             file: StaticString = #filePath, line: UInt = #line) throws -> SkinnedHeroModel {
        let url = try XCTUnwrap(Self.fixture("SkinnedTestHero"), "フィクスチャがテストバンドルに無い", file: file, line: line)
        let model = HeroModelLibrary.makeHero(heroID: heroID, skinID: skinID, team: team, master: master,
                                              options: options.with(mesh: .skinned(url)))
        return try XCTUnwrap(model as? SkinnedHeroModel, "スキンメッシュで生成されない", file: file, line: line)
    }

    /// jointTransforms を読み戻して親から累積し、モデルの root 空間での骨の位置を求める。
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

    private func pose(_ m: SkinnedHeroModel, _ p: HeroPose) -> [HeroJointRole: SIMD3<Float>] {
        m.applyPose(p)
        return joints(m)
    }

    // MARK: 読み込み・骨対応

    func testJointNameNormalization() {
        XCTAssertEqual(HeroJointRole.normalize("mixamorig:LeftArm"), "leftarm")
        XCTAssertEqual(HeroJointRole.normalize("mixamorig_Hips/mixamorig_Spine"), "spine")
        XCTAssertEqual(HeroJointRole.normalize("Armature/mixamorig1:RightHand"), "righthand")
        XCTAssertEqual(HeroJointRole.normalize("Hips"), "hips")
        XCTAssertEqual(HeroJointRole(rawValue: HeroJointRole.normalize("mixamorig_LeftHandIndex1")), .indexL)
    }

    /// 背骨が腰 → 胸の順に spine / spine1 / spine2 へ当たり、首と肩が最後の背骨（upperSpine）の子であること。
    private func assertSpineChain(_ rig: HeroSkeletonRig, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let hips = rig.index[.hips] else { return XCTFail("\(name) hips が無い", file: file, line: line) }
        var prev = hips
        for role in [HeroJointRole.spine, .spine1, .spine2] {
            guard let i = rig.index[role] else { continue }
            XCTAssertEqual(rig.parent[i], prev, "\(name) \(role)（\(rig.jointNames[i])）の親が腰側の背骨でない", file: file, line: line)
            prev = i
        }
        XCTAssertEqual(rig.upperSpine, prev, name, file: file, line: line)
        for role in [HeroJointRole.neck, .shoulderL, .shoulderR] {
            guard let i = rig.index[role] else { continue }
            XCTAssertEqual(rig.parent[i], rig.upperSpine, "\(name) \(role) が胸の骨の子でない", file: file, line: line)
        }
    }

    /// Meshy の自動リグ（tools/meshy.mjs）は背骨が腰側から Spine02 → Spine01 → Spine で、胸の骨が Mixamo の腰側と同じ
    /// 「Spine」。骨 1 本ごとの別名では直せないので実行時は別名を持たず、取り込み時に normalize_hero.py
    /// （norm_common.MESHY_TO_MIXAMO）が Mixamo 名へ付け替える。付け替え後の骨名（Hero_H002 の実物）で背骨の順を確かめる。
    func testMeshyRigIsRenamedAtImportNotAliasedAtRuntime() throws {
        XCTAssertNil(HeroJointRole(rawValue: HeroJointRole.normalize("Hips/Spine02")))
        XCTAssertNil(HeroJointRole(rawValue: HeroJointRole.normalize("Hips/Spine02/Spine01")))
        let spine = "Hips/Spine/Spine1/Spine2"
        var names = ["Hips", "Hips/Spine", "Hips/Spine/Spine1", spine, "\(spine)/Neck", "\(spine)/Neck/Head",
                     "\(spine)/Neck/Head/HeadTop_End", "\(spine)/Neck/Head/headfront"]
        for side in ["Left", "Right"] {
            let s = "\(spine)/\(side)Shoulder"
            names += [s, "\(s)/\(side)Arm", "\(s)/\(side)Arm/\(side)ForeArm", "\(s)/\(side)Arm/\(side)ForeArm/\(side)Hand"]
        }
        for side in ["Left", "Right"] {
            let u = "Hips/\(side)UpLeg"
            names += [u, "\(u)/\(side)Leg", "\(u)/\(side)Leg/\(side)Foot", "\(u)/\(side)Leg/\(side)Foot/\(side)ToeBase"]
        }
        XCTAssertEqual(names.count, 24)
        var missing: [HeroJointRole] = []
        let rig = try XCTUnwrap(HeroSkeletonRig(jointNames: names, restLocal: Array(repeating: Transform(), count: names.count),
                                                entityToHero: Transform(), missing: &missing), "\(missing)")
        XCTAssertEqual(rig.index[.spine2].map { rig.jointNames[$0] }, spine)
        assertSpineChain(rig, "Meshy（付け替え後）")
    }

    /// 同梱のヒーロー（Tripo・Meshy とも）とフィクスチャの背骨の順。Meshy の骨名のまま取り込むと胸が spine に当たって落ちる。
    func testBundledHeroSpineChains() throws {
        var urls = (Bundle.main.urls(forResourcesWithExtension: "usdz", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("Hero_") }
        urls.append(try XCTUnwrap(Self.fixture("SkinnedTestHero")))
        for url in urls {
            let t = try XCTUnwrap(HeroAssetLibrary.heroTemplate(url), url.lastPathComponent)
            assertSpineChain(t.rig, url.lastPathComponent)
        }
    }

    func testLoadsFixtureAndMapsJoints() throws {
        let m = try makeSkinned()
        XCTAssertTrue(m.isSkinned)
        XCTAssertEqual(m.skinnedEntity.jointNames.count, 27)
        for role in HeroJointRole.allCases {
            XCTAssertNotNil(m.rig.index[role], "\(role) が対応づかない")
        }
        // 背骨 3 本で腰 → 胴を分担、四肢はレスト補正あり
        XCTAssertEqual(m.rig.drive[m.rig.index[.spine2]!], .spine(1))
        XCTAssertNotEqual(m.rig.correction[m.rig.index[.armR]!].angle, 0)
        XCTAssertEqual(m.rig.correction[m.rig.index[.head]!].angle, 0, accuracy: 1e-6)
        XCTAssertEqual(m.overheadHeight, (1.7 + 0.38) * HeroBlueprints.blueprint(heroID: "H003", role: nil).scale, accuracy: 0.02)
        XCTAssertLessThanOrEqual(m.entityCount, 35)
        XCTAssertGreaterThan(m.triangleCount, 500)
        print("SkinnedHeroModelTests: 三角形 \(m.triangleCount) エンティティ \(m.entityCount) 握り R \(m.rig.gripR)")
    }

    // MARK: 姿勢

    func testRestPoseArmsHangDownAndFeetOnGround() throws {
        let m = try makeSkinned()
        let bp = HeroBlueprints.blueprint(heroID: "H003", role: nil)
        let profileRest = HeroMotionProfile(blueprint: bp, metrics: BodyMetrics.make(bp.build)).rest
        for (label, p) in [("HeroPose()", HeroPose()), ("profile.rest", profileRest)] {
            let j = pose(m, p)
            for (arm, hand) in [(HeroJointRole.armR, HeroJointRole.handR), (.armL, .handL)] {
                let a = try XCTUnwrap(j[arm]), h = try XCTUnwrap(j[hand])
                XCTAssertLessThan(h.y, a.y - 0.3, "\(label) \(hand) が肩から下がらない")
                XCTAssertLessThan(abs(h.x), 0.4, "\(label) \(hand) が体から離れている")
            }
            XCTAssertGreaterThan(try XCTUnwrap(j[.handR]).x, 0, label)
            XCTAssertLessThan(try XCTUnwrap(j[.handL]).x, 0, label)
            for (foot, toe) in [(HeroJointRole.footR, HeroJointRole.toeR), (.footL, .toeL)] {
                let f = try XCTUnwrap(j[foot]), t = try XCTUnwrap(j[toe])
                XCTAssertTrue((-0.03...0.15).contains(f.y), "\(label) \(foot) y=\(f.y)")
                // 正面 -Z: つま先は足首より前
                XCTAssertLessThan(t.z, f.z - 0.05, "\(label) \(toe)")
            }
            XCTAssertGreaterThan(try XCTUnwrap(j[.footR]).x, 0, label)
            XCTAssertGreaterThan(try XCTUnwrap(j[.head]).y, 1.4, label)
        }
    }

    func testArmPitchRaisesHandForward() throws {
        let m = try makeSkinned()
        var p = HeroPose()
        p.armR.pitch = .pi / 2
        let j = pose(m, p)
        let a = try XCTUnwrap(j[.armR]), h = try XCTUnwrap(j[.handR])
        XCTAssertLessThan(h.z, a.z - 0.3, "腕の pitch + で手が前（-Z）へ出ない")
        XCTAssertEqual(h.y, a.y, accuracy: 0.1)
        // 左腕は下がったまま
        let l = try XCTUnwrap(j[.handL]), la = try XCTUnwrap(j[.armL])
        XCTAssertLessThan(l.y, la.y - 0.3)
    }

    func testElbowBendsForward() throws {
        let m = try makeSkinned()
        var p = HeroPose()
        p.armR.elbow = .pi / 2
        let j = pose(m, p)
        let e = try XCTUnwrap(j[.foreArmR]), h = try XCTUnwrap(j[.handR]), a = try XCTUnwrap(j[.armR])
        XCTAssertLessThan(e.y, a.y - 0.2, "上腕は下がったまま")
        XCTAssertLessThan(h.z, e.z - 0.15, "肘の曲げで前腕が前へ出ない")
        XCTAssertEqual(h.y, e.y, accuracy: 0.08)
    }

    func testKneeBendMovesFootBack() throws {
        let m = try makeSkinned()
        let rest = pose(m, HeroPose())
        var p = HeroPose()
        p.legR.knee = 1.2
        let bent = pose(m, p)
        let f0 = try XCTUnwrap(rest[.footR]), f1 = try XCTUnwrap(bent[.footR])
        XCTAssertGreaterThan(f1.z, f0.z + 0.1, "膝の曲げで足が後ろ（+Z）へ行かない")
        XCTAssertGreaterThan(f1.y, f0.y + 0.05)
        // 脚の前振りで足が前へ
        var q = HeroPose()
        q.legL.pitch = 0.8
        let fwd = pose(m, q)
        XCTAssertLessThan(try XCTUnwrap(fwd[.footL]).z, try XCTUnwrap(rest[.footL]).z - 0.2)
    }

    func testHipsDropLowersHips() throws {
        let m = try makeSkinned()
        let scale = HeroBlueprints.blueprint(heroID: "H003", role: nil).scale
        let y0 = try XCTUnwrap(pose(m, HeroPose())[.hips]).y
        var p = HeroPose()
        p.hipsDrop = 0.1
        let y1 = try XCTUnwrap(pose(m, p)[.hips]).y
        // 腰の沈みは脚の長さの比（フィクスチャ 0.84 m / 手続き 0.56 m）で伸びる
        XCTAssertEqual(m.legScale, 0.84 / 0.56, accuracy: 0.02)
        XCTAssertEqual(y0 - y1, 0.1 * scale * m.legScale, accuracy: 0.005)
        // 胴の前傾で頭が前へ
        var t = HeroPose()
        t.torsoPitch = 0.5
        XCTAssertLessThan(try XCTUnwrap(pose(m, t)[.head]).z, -0.15)
    }

    func testWeaponStaysInHandThroughStates() throws {
        // 剣と盾（H001）・弓（H003）・杖（H004）
        for id in ["H001", "H003", "H004"] {
            let m = try makeSkinned(id, team: .blue)
            let states: [HeroAnimState] = [.idle, .run, .attack, .attack, .cast(.skill1), .cast(.skill2), .cast(.skill3),
                                           .cast(.ultimate), .channel, .stunned, .victory, .dead, .idle]
            var worst: Float = 0
            for (i, s) in states.enumerated() {
                m.setState(s)
                for k in 0..<40 {
                    m.update(dt: k % 9 == 0 ? 0.2 : 1.0 / 30.0, moveSpeed: Double(i % 3) * 160)
                    let j = joints(m)
                    let w = m.weapon.position(relativeTo: m.root)
                    let o = m.offhand.position(relativeTo: m.root)
                    let dw = simd_distance(w, try XCTUnwrap(j[.handR]))
                    let dO = simd_distance(o, try XCTUnwrap(j[.handL]))
                    worst = max(worst, dw, dO)
                    for t in m.skinnedEntity.jointTransforms {
                        let ok = t.translation.x.isFinite && t.translation.y.isFinite && t.translation.z.isFinite
                            && t.rotation.vector.x.isFinite && t.rotation.vector.y.isFinite
                            && t.rotation.vector.z.isFinite && t.rotation.vector.w.isFinite
                        if !ok { return XCTFail("\(id) \(s) 骨が NaN") }
                    }
                }
            }
            print("SkinnedHeroModelTests: \(id) 武器と手の最大距離 \(worst) m")
            XCTAssertLessThan(worst, 0.1, "\(id) 武器が手から離れる")
        }
    }

    func testDeathFadesAndRootIsOwnedByRenderer() throws {
        let m = try makeSkinned("H007", team: .red, options: .battle)
        let pos = SIMD3<Float>(3, 0, -5)
        m.root.position = pos
        let body = try XCTUnwrap(m.root.children.first)
        m.setState(.dead)
        for _ in 0..<90 { m.update(dt: 1.0 / 60.0, moveSpeed: 0) }
        XCTAssertLessThan(body.components[OpacityComponent.self]?.opacity ?? 1, 0.05)
        m.setState(.idle)
        m.update(dt: 1.0 / 60.0, moveSpeed: 0)
        XCTAssertNil(body.components[OpacityComponent.self])
        XCTAssertEqual(m.root.position, pos)
        XCTAssertNotNil(m.root.findEntity(named: "teamRing"))
    }

    // MARK: キャッシュ・フォールバック

    func testTemplateIsLoadedOnceAndInstancesAreIndependent() throws {
        let a = try makeSkinned("H002")
        let loads = HeroAssetLibrary.loadCount
        let b = try makeSkinned("H002")
        XCTAssertEqual(HeroAssetLibrary.loadCount, loads, "2 体目で再読み込みしている")
        XCTAssertTrue(a.skinnedEntity.model?.mesh === b.skinnedEntity.model?.mesh, "メッシュが共有されない")
        var p = HeroPose()
        p.armR.pitch = 1.5
        a.applyPose(p)
        b.applyPose(HeroPose())
        let ha = try XCTUnwrap(joints(a)[.handR]), hb = try XCTUnwrap(joints(b)[.handR])
        XCTAssertGreaterThan(simd_distance(ha, hb), 0.2, "インスタンスの骨が共有されている")
    }

    func testSkinVariantTintsSharedMaterials() throws {
        let skins = HeroSkins.skins(for: "H001", master: master)
        let skin = try XCTUnwrap(skins.first)
        let base = try makeSkinned("H001")
        let a = try makeSkinned("H001", skinID: skin.cosmeticID)
        let b = try makeSkinned("H001", skinID: skin.cosmeticID)
        let baseMat = try XCTUnwrap(base.skinnedEntity.model?.materials.first)
        let tinted = try XCTUnwrap(a.skinnedEntity.model?.materials.first)
        print("SkinnedHeroModelTests: 読み込んだマテリアル \(type(of: baseMat))")
        let p0 = try XCTUnwrap(baseMat as? PhysicallyBasedMaterial)
        let p1 = try XCTUnwrap(tinted as? PhysicallyBasedMaterial)
        XCTAssertNotEqual(p0.baseColor.tint, p1.baseColor.tint, "スキンの色味が変わらない")
        // 同じフィクスチャを別ヒーローで使っても、スキン番号が同じだけで他ヒーローの色味を流用しない
        if let other = HeroSkins.skins(for: "H004", master: master).first {
            let o = try makeSkinned("H004", skinID: other.cosmeticID)
            let po = try XCTUnwrap(o.skinnedEntity.model?.materials.first as? PhysicallyBasedMaterial)
            XCTAssertNotEqual(po.baseColor.tint, p1.baseColor.tint, "H004 のスキンが H001 の色味になった")
        }
        XCTAssertEqual(a.skin.cosmeticID, skin.cosmeticID)
        XCTAssertEqual(a.root.findEntity(named: "aura") != nil, a.skin.isEpic)
        let pa = a.skinnedEntity.model?.materials.first as? PhysicallyBasedMaterial
        let pb = b.skinnedEntity.model?.materials.first as? PhysicallyBasedMaterial
        XCTAssertEqual(pa?.baseColor.tint, pb?.baseColor.tint)
    }

    func testAutoUsesBundledAssetOrFallsBackToProcedural() {
        let model = HeroModelLibrary.makeHero(heroID: "H001", skinID: nil, team: .blue, master: master, options: .battle)
        // 現在は Hero_H001.usdz を同梱していないので手続きモデル。同梱後はスキンメッシュになる
        let bundled = HeroAssetLibrary.bundledURL("Hero_H001") != nil
        XCTAssertEqual(model.isSkinned, bundled)
        let pinned = HeroModelLibrary.makeHero(heroID: "H001", skinID: nil, team: .blue, master: master,
                                               options: HeroModelOptions.battle.with(mesh: .procedural))
        XCTAssertFalse(pinned.isSkinned)
    }

    func testBrokenAssetsFallBackToProcedural() throws {
        let missing = try XCTUnwrap(Self.fixture("SkinnedTestHero_MissingJoint"))
        let m1 = HeroModelLibrary.makeHero(heroID: "H005", skinID: nil, team: .blue, master: master,
                                           options: HeroModelOptions.battle.with(mesh: .skinned(missing)))
        XCTAssertFalse(m1.isSkinned, "必須の骨（LeftForeArm）が無いのにスキンメッシュになった")
        XCTAssertNotNil(m1.root.findEntity(named: "torso"))
        let nowhere = URL(fileURLWithPath: "/nonexistent/Hero_X.usdz")
        let m2 = HeroModelLibrary.makeHero(heroID: "H005", skinID: nil, team: .blue, master: master,
                                           options: HeroModelOptions.battle.with(mesh: .skinned(nowhere)))
        XCTAssertFalse(m2.isSkinned)
        // 失敗も記録して再読み込みしない
        let loads = HeroAssetLibrary.loadCount
        _ = HeroModelLibrary.makeHero(heroID: "H005", skinID: nil, team: .blue, master: master,
                                      options: HeroModelOptions.battle.with(mesh: .skinned(missing)))
        XCTAssertEqual(HeroAssetLibrary.loadCount, loads)
    }

    func testMirroredOrBackwardRigIsRejected() throws {
        let url = try XCTUnwrap(Self.fixture("SkinnedTestHero"))
        let t = try XCTUnwrap(HeroAssetLibrary.heroTemplate(url))
        XCTAssertNil(SkinnedHeroTemplate.contractViolation(t.rig))
        let skinned = try XCTUnwrap(HeroAssetLibrary.entity(at: t.skinnedPath, in: t.entity) as? ModelEntity)
        // 後ろ向き（Y 軸回りに 180°）に置いたリグは右腕が -X・つま先が +Z になる
        let toHero = Transform(matrix: skinned.transformMatrix(relativeTo: t.entity))
        var turned = toHero
        turned.rotation = ry(.pi) * toHero.rotation
        turned.translation = ry(.pi).act(toHero.translation)
        var missing: [HeroJointRole] = []
        let rig = try XCTUnwrap(HeroSkeletonRig(jointNames: skinned.jointNames, restLocal: skinned.jointTransforms,
                                                entityToHero: turned, missing: &missing))
        XCTAssertNotNil(SkinnedHeroTemplate.contractViolation(rig))
    }

    // MARK: 体格の違い

    func testChannelKneelStaysGrounded() throws {
        let m = try makeSkinned()
        let scale = HeroBlueprints.blueprint(heroID: "H003", role: nil).scale
        let rest = pose(m, HeroPose())
        // 詠唱・帰還の片膝立ち（HeroAnimator の channel と同じ脚）
        var p = HeroPose()
        p.hipsDrop = 0.2
        p.legL = LegPose(pitch: 1.25, out: 0.1, knee: 1.3)
        p.legR = LegPose(pitch: -0.35, out: 0.08, knee: 1.75)
        let j = pose(m, p)
        let footL = try XCTUnwrap(j[.footL]), restFootL = try XCTUnwrap(rest[.footL])
        XCTAssertLessThan(abs(footL.y - restFootL.y), 0.04 * scale, "立ち足が地面から浮く・沈む y=\(footL.y)")
        let kneeR = try XCTUnwrap(j[.legR]), restKneeR = try XCTUnwrap(rest[.legR])
        XCTAssertLessThan(kneeR.y, restKneeR.y * 0.5, "突いた膝が地面まで下りない y=\(kneeR.y)")
    }

    func testHaloFitsSkinnedHead() throws {
        for id in ["H005", "H016"] {
            let m = try makeSkinned(id)
            m.applyPose(HeroPose())
            let url = try XCTUnwrap(Self.fixture("SkinnedTestHero"))
            let t = try XCTUnwrap(HeroAssetLibrary.heroTemplate(url))
            let halo = try XCTUnwrap(m.float, "\(id) に光輪が無い")
            let pos = halo.position // motion のローカル = ヒーロー空間
            XCTAssertLessThan(abs(pos.y - t.headCenter.y), t.headRadius, "\(id) 光輪の高さが頭から外れる y=\(pos.y)")
            XCTAssertGreaterThan(pos.z - t.headCenter.z, 0, "\(id) 光輪が頭の前にある")
            XCTAssertLessThan(pos.z - t.headCenter.z, t.headBack + 0.1, "\(id) 光輪が頭から離れすぎ")
            let b = halo.visualBounds(recursive: true, relativeTo: halo.parent, excludeInactive: false)
            XCTAssertLessThan(b.extents.x * 0.5, 2.5 * t.headRadius, "\(id) 光輪が頭に比べて大きすぎる")
        }
    }

    // MARK: 手続きモデルとの一致

    /// 腕・脚の向きと武器の向きが、同じ姿勢の手続きモデルと一致する（yaw / out / roll / 左右の符号の取り違えを検出）。
    func testLimbAndWeaponDirectionsMatchProcedural() throws {
        let url = try XCTUnwrap(Self.fixture("SkinnedTestHero"))
        let limbs: [(HeroJointRole, HeroJointRole, String)] = [
            (.armR, .foreArmR, "upperArmR"), (.foreArmR, .handR, "foreArmR"), (.armL, .foreArmL, "upperArmL"),
            (.foreArmL, .handL, "foreArmL"), (.upLegR, .legR, "thighR"), (.legR, .footR, "shinR"),
            (.upLegL, .legL, "thighL"), (.legL, .footL, "shinL")]
        for id in ["H001", "H007"] {
            let s = try makeSkinned(id)
            // 手続きどうしの比較（同梱のモーションクリップが重なると腕・武器の向きが変わる）
            s.useMotion(nil, library: .empty)
            let pm = HeroModelLibrary.makeHero(heroID: id, skinID: nil, team: .neutral, master: master,
                                               options: HeroModelOptions.showcase.with(mesh: .procedural))
            let proc = try XCTUnwrap(pm as? HeroModel)
            let procWeapon = try XCTUnwrap(proc.root.findEntity(named: "weapon"))
            let procOffhand = try XCTUnwrap(proc.root.findEntity(named: "offhand"))
            var worst: Float = 1
            func compare(_ label: String) throws {
                let j = joints(s)
                for (a, b, name) in limbs {
                    let pa = try XCTUnwrap(j[a]), pb = try XCTUnwrap(j[b])
                    let d = simd_normalize(pb - pa)
                    let e = try XCTUnwrap(proc.root.findEntity(named: name))
                    let pd = e.orientation(relativeTo: proc.root).act(V3(0, -1, 0))
                    let dot = simd_dot(d, pd)
                    worst = min(worst, dot)
                    if dot < 0.999 { return XCTFail("\(id) \(label) \(name) の向きが違う dot=\(dot)") }
                }
                for (sk, pr, name) in [(s.weapon, procWeapon, "weapon"), (s.offhand, procOffhand, "offhand")] {
                    let qa = sk.orientation(relativeTo: s.root), qb = pr.orientation(relativeTo: proc.root)
                    let dot = abs(simd_dot(qa.vector, qb.vector))
                    worst = min(worst, dot)
                    if dot < 0.999 { return XCTFail("\(id) \(label) \(name) の向きが違う dot=\(dot)") }
                }
            }
            var rng = SplitMix64(seed: id == "H001" ? 0x5EED_0001 : 0x5EED_0007)
            func r(_ a: Float) -> Float { Float.random(in: -a...a, using: &rng) }
            for i in 0..<200 {
                var p = HeroPose()
                p.yaw = r(.pi); p.pitch = r(0.4); p.roll = r(0.4)
                p.hipsYaw = r(0.8); p.hipsRoll = r(0.4); p.hipsDrop = abs(r(0.2))
                p.torsoPitch = r(0.8); p.torsoYaw = r(0.8); p.torsoRoll = r(0.5)
                p.headPitch = r(0.5); p.headYaw = r(0.8); p.headRoll = r(0.4)
                p.armR = ArmPose(pitch: r(2.5), out: r(1.2), yaw: r(1.0), elbow: abs(r(2.0)))
                p.armL = ArmPose(pitch: r(2.5), out: r(1.2), yaw: r(1.0), elbow: abs(r(2.0)))
                p.legR = LegPose(pitch: r(1.5), out: r(0.6), knee: abs(r(2.0)))
                p.legL = LegPose(pitch: r(1.5), out: r(0.6), knee: abs(r(2.0)))
                p.weaponR = r(2.0); p.weaponL = r(2.0)
                s.applyPose(p)
                proc.applyPose(p)
                try compare("姿勢 \(i)")
            }
            // アニメーターの全状態（両モデルは同じプロファイルなので同じ姿勢になる）
            // 走りの位相は各モデルの脚の長さで進む（歩幅を地面に合わせる）ので、比較のため手続きモデルの値に揃える
            s.legLength = proc.legLength
            let states: [HeroAnimState] = [.idle, .run, .attack, .cast(.skill1), .cast(.skill2), .cast(.skill3),
                                           .cast(.ultimate), .channel, .stunned, .victory, .dead, .idle]
            for st in states {
                s.setState(st)
                proc.setState(st)
                for k in 0..<20 {
                    s.update(dt: 1.0 / 30.0, moveSpeed: Double(k % 3) * 160)
                    proc.update(dt: 1.0 / 30.0, moveSpeed: Double(k % 3) * 160)
                    try compare("\(st) \(k)")
                }
            }
            print("SkinnedHeroModelTests: \(id) 手続きとの向きの一致 最小 dot \(worst)")
        }
    }

    // MARK: 装備

    /// 籠手・爪（H007 / H022）は本体アセットに含めるので、手続きメッシュも Prop も付けない。
    func testBodyWornGauntletsAreNotAttachedTwice() throws {
        // Prop があっても付けない
        let box = try Self.boxProp(V3(0.3, 1, 0.3), grip: 0.5)
        HeroAssetLibrary.setPropTemplateForTesting("stoneFist", box)
        defer { HeroAssetLibrary.setPropTemplateForTesting("stoneFist", nil) }
        for id in ["H007", "H022"] {
            let m = try makeSkinned(id, team: .blue)
            XCTAssertNil(m.weapon.model, "\(id) 手続きの籠手が右手に付いている")
            XCTAssertTrue(m.weapon.children.allSatisfy { $0.name == "castGlow" }, "\(id) 右手に Prop が付いている")
            XCTAssertNil(m.offhand.model, "\(id) 手続きの籠手が左手に付いている")
            XCTAssertTrue(m.offhand.children.isEmpty, "\(id) 左手に Prop が付いている")
            XCTAssertNotNil(m.weapon.findEntity(named: "castGlow"), "\(id) 詠唱の光の親が無い")
        }
        // 通常の武器は従来どおり付く（同梱の Prop_broadsword.usdz があればそれ、無ければ手続きメッシュ）
        let sword = try makeSkinned("H001").weapon
        XCTAssertTrue(sword.model != nil || sword.findEntity(named: "propFit") != nil, "H001 の剣が付いていない")
    }

    /// 長さ 1 m の箱の Prop（握りは下端から grip の割合）。
    private static func boxProp(_ size: V3, grip: Float) throws -> HeroPropTemplate {
        let root = Entity()
        let box = ModelEntity(mesh: .generateBox(width: size.x, height: size.y, depth: size.z),
                              materials: [SimpleMaterial()])
        box.position = V3(0, size.y * (0.5 - grip), 0)
        root.addChild(box)
        return try XCTUnwrap(HeroPropTemplate(entity: root))
    }

    private static func transformed(_ b: BoundingBox, _ t: Transform) -> BoundingBox {
        var out = BoundingBox.empty
        let m = t.matrix
        for i in 0..<8 {
            let c = V3(i & 1 == 0 ? b.min.x : b.max.x, i & 2 == 0 ? b.min.y : b.max.y, i & 4 == 0 ? b.min.z : b.max.z)
            let p = m * SIMD4<Float>(c, 1)
            out = out.union(V3(p.x, p.y, p.z))
        }
        return out
    }

    /// 予備の経路: yaw を掛けずに正規化した Prop（薄い向き ±X・正面 +X）は、実行時に 90° 回して手続きの盾・竪琴・連弩と
    /// 同じ横向き・位置になる（yaw 済みの Prop は testNormalizedPropFixturesMatchProceduralOrientation）。
    func testPropFitAlignsThinAxisWithProcedural() throws {
        let cases: [(hero: String, kind: String, offhand: Bool, prop: V3, grip: Float, front: Float)] = [
            ("H001", "gateShield", true, V3(0.02, 1, 0.5), 0.5, -1),
            ("H013", "hideShield", true, V3(0.05, 1, 0.9), 0.5, -1),
            ("H002", "harpBow", true, V3(0.04, 1, 0.6), 0.1, -1),
            ("H009", "mechCrossbow", false, V3(0.12, 1, 0.6), 0.35, 1),
        ]
        for c in cases {
            let bp = HeroBlueprints.blueprint(heroID: c.hero, role: master.hero(c.hero)?.role)
            XCTAssertEqual(c.offhand ? "\(bp.offhand)" : "\(bp.weapon)", c.kind)
            let ms = HeroModelLibrary.meshSet(heroID: c.hero, blueprint: bp)
            let mesh = try XCTUnwrap(c.offhand ? ms.offhand : ms.weapon)
            let pb = mesh.bounds
            let prop = try Self.boxProp(c.prop, grip: c.grip)
            let fit = SkinnedHeroModel.propFit(c.kind, prop: prop.bounds, procedural: pb)
            let fb = Self.transformed(prop.bounds, fit)
            let procWideX = pb.extents.x > pb.extents.z
            XCTAssertEqual(fb.extents.x > fb.extents.z, procWideX,
                           "\(c.kind) 横の広い向きが手続きと違う prop=\(fb.extents) 手続き=\(pb.extents)")
            XCTAssertEqual(fb.extents.y, pb.extents.y, accuracy: 0.01, "\(c.kind) 長さ")
            // 正面・上面（+X）の行き先: 盾・竪琴は前（-Z）、連弩は上面（+Z）
            XCTAssertGreaterThan(fit.rotation.act(V3(1, 0, 0)).z * c.front, 0.9, "\(c.kind) 正面の向き")
            if HeroGearBuilder.propMount(c.kind).center {
                XCTAssertLessThan(simd_distance(fb.center, pb.center), 0.05, "\(c.kind) 位置が手続きと違う（腕を貫く）")
            }
        }
        // 剣は向きを変えず、握りを原点に長さだけ合わせる
        let bp = HeroBlueprints.blueprint(heroID: "H001", role: nil)
        let sword = try XCTUnwrap(HeroModelLibrary.meshSet(heroID: "H001", blueprint: bp).weapon)
        let fit = SkinnedHeroModel.propFit("broadsword", prop: try Self.boxProp(V3(0.02, 1, 0.15), grip: 0.1).bounds,
                                           procedural: sword.bounds)
        XCTAssertEqual(fit.rotation.angle, 0, accuracy: 1e-5)
        XCTAssertEqual(fit.translation, .zero)
    }

    /// 同梱 Prop の経路: 盾の Prop（yaw 無しの板）は 90° 回って手続きの盾の位置へ、剣の Prop は手続きの剣と同じ長さで握りから伸びる。
    func testInjectedPropsAreFittedOnModel() throws {
        let bp = HeroBlueprints.blueprint(heroID: "H001", role: master.hero("H001")?.role)
        let ms = HeroModelLibrary.meshSet(heroID: "H001", blueprint: bp)
        // 剣の Prop は手続きの剣と同じ握りの割合（柄頭 → 握り）で作る
        let sb0 = try XCTUnwrap(ms.weapon).bounds
        let swordGrip = -sb0.min.y / sb0.extents.y
        HeroAssetLibrary.setPropTemplateForTesting("gateShield", try Self.boxProp(V3(0.02, 1, 0.5), grip: 0.5))
        HeroAssetLibrary.setPropTemplateForTesting("broadsword", try Self.boxProp(V3(0.02, 1, 0.15), grip: swordGrip))
        defer {
            HeroAssetLibrary.setPropTemplateForTesting("gateShield", nil)
            HeroAssetLibrary.setPropTemplateForTesting("broadsword", nil)
        }
        let m = try makeSkinned("H001", team: .blue)
        XCTAssertNil(m.offhand.model, "手続きの盾が残っている")
        let shield = try XCTUnwrap(m.offhand.findEntity(named: "propFit"))
        let sb = shield.visualBounds(recursive: true, relativeTo: m.offhand, excludeInactive: false)
        XCTAssertGreaterThan(sb.extents.x, sb.extents.z, "盾の Prop が 90° ずれている")
        XCTAssertLessThan(simd_distance(sb.center, try XCTUnwrap(ms.offhand).bounds.center), 0.05)
        let sword = try XCTUnwrap(m.weapon.findEntity(named: "propFit"))
        let wb = sword.visualBounds(recursive: true, relativeTo: m.weapon, excludeInactive: false)
        let pw = try XCTUnwrap(ms.weapon).bounds
        XCTAssertEqual(wb.min.y, pw.min.y, accuracy: 0.02)
        XCTAssertEqual(wb.max.y, pw.max.y, accuracy: 0.02)
        XCTAssertLessThan(wb.extents.x, wb.extents.z, "剣の Prop の薄い向きが X でない")
    }

    // MARK: 正規化済み Prop（Blender）→ propFit の通し

    /// 正規化 Prop の向きの手がかり（手続き側と Prop 側でそれぞれ形から求める）。
    private enum PropFacing {
        /// 面（盾・竪琴・本の表紙）: 手続きは握り（原点）から離れる側、Prop は Marker の側。
        case awayFromGrip
        /// 上面（連弩）: 手続きは weaponTip（矢）の側、Prop は Marker の側。
        case weaponTip
        /// 弦（弓）: 中央（握り）から両端（弓先）へ向かう側。両方とも頂点から求める。
        case bowTips
        case none
    }

    /// エンティティ配下のメッシュの頂点（ref 空間）。marker: make_test_rig の Marker_*（赤い素材）の部分だけ / 以外だけ。
    private static func points(_ e: Entity, in ref: Entity, marker: Bool? = nil) -> [V3] {
        var out: [V3] = []
        if let m = e.components[ModelComponent.self] {
            out += points(m.mesh, m.materials, e.transformMatrix(relativeTo: ref), marker: marker)
        }
        for c in e.children { out += points(c, in: ref, marker: marker) }
        return out
    }

    private static func points(_ mesh: MeshResource, _ materials: [RealityKit.Material] = [],
                               _ mtx: simd_float4x4 = matrix_identity_float4x4, marker: Bool? = nil) -> [V3] {
        var out: [V3] = []
        let c = mesh.contents
        for inst in c.instances {
            guard let model = c.models[inst.model] else { continue }
            let t = mtx * inst.transform
            for part in model.parts {
                if let marker {
                    let mat = part.materialIndex < materials.count ? materials[part.materialIndex] : nil
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    (mat as? PhysicallyBasedMaterial)?.baseColor.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
                    // 赤 (0.9, 0.2, 0.1)。読み込み後の値は色空間で変わるので差で見る（Body は灰色）
                    let red = r - max(g, b) > 0.2
                    if red != marker { continue }
                }
                for v in part.positions.elements {
                    let p = t * SIMD4<Float>(v, 1)
                    out.append(V3(p.x, p.y, p.z))
                }
            }
        }
        return out
    }

    private static func centroid(_ pts: [V3]) -> V3 {
        pts.reduce(V3.zero, +) / Float(max(1, pts.count))
    }

    /// 水平面（XZ）で幅が最小になる向き n（1° 刻み）と、最大幅 / 最小幅。
    private static func thinDirection(_ pts: [V3]) -> (n: V3, ratio: Float) {
        var best = (w: Float.infinity, n: V3(1, 0, 0)), widest: Float = 0
        for k in 0..<180 {
            let a = Float(k) * .pi / 180
            let n = V3(cos(a), 0, sin(a))
            var lo = Float.infinity, hi = -Float.infinity
            for p in pts {
                let d = simd_dot(p, n)
                lo = min(lo, d)
                hi = max(hi, d)
            }
            if hi - lo < best.w { best = (hi - lo, n) }
            widest = max(widest, hi - lo)
        }
        return (best.n, widest / max(1e-5, best.w))
    }

    /// 横の広い向き（0 = X, 2 = Z）。ほぼ同じ幅なら nil（SkinnedHeroModel.propFit と同じ基準）。
    private static func wide(_ b: BoundingBox) -> Int? {
        let e = b.extents
        if e.x > e.z * 1.25 { return 0 }
        if e.z > e.x * 1.25 { return 2 }
        return nil
    }

    /// 中央（高さの中ほど 30%）から両端（上下 15%）へ向かう水平の向き。
    private static func midToEnds(_ pts: [V3]) -> V3 {
        let ys = pts.map(\.y)
        let lo = ys.min() ?? 0, hi = ys.max() ?? 0, span = max(1e-5, hi - lo), mid = (lo + hi) / 2
        let ends = pts.filter { $0.y <= lo + 0.15 * span || $0.y >= hi - 0.15 * span }
        let middle = pts.filter { abs($0.y - mid) <= 0.15 * span }
        let d = centroid(ends) - centroid(middle)
        return V3(d.x, 0, d.z)
    }

    /// tools/blender/make_test_rig.py --variants の合成 Prop を正規化した USDZ（AppTests/Fixtures/Props）を
    /// テスト用の差し込み口から入れ、モデルの武器・副手の座標で手続きメッシュと同じ向き・大きさ・位置になることを確かめる。
    /// 期待値は手続きメッシュの形から求める（正規化の yaw と実行時の propFit が二重に回していないかの検査）。
    func testNormalizedPropFixturesMatchProceduralOrientation() throws {
        let cases: [(hero: String, kind: String, offhand: Bool, fixture: String, facing: PropFacing)] = [
            ("H001", "gateShield", true, "Prop_gateShield", .awayFromGrip),
            ("H013", "hideShield", true, "Prop_hideShield", .awayFromGrip),
            // 竪琴は面が -Z の平たい板として盾のフィクスチャで代用する
            ("H002", "harpBow", true, "Prop_gateShield", .awayFromGrip),
            ("H010", "grimoire", true, "Prop_grimoire", .awayFromGrip),
            ("H009", "mechCrossbow", false, "Prop_mechCrossbow", .weaponTip),
            ("H003", "ashBow", true, "Prop_ashBow", .bowTips),
            ("H020", "lightBow", true, "Prop_ashBow", .bowTips),
            ("H001", "broadsword", false, "Prop_broadsword", .none),
            ("H021", "sandRifle", false, "Prop_sandRifle", .none),
        ]
        for c in cases {
            let bp = HeroBlueprints.blueprint(heroID: c.hero, role: master.hero(c.hero)?.role)
            XCTAssertEqual(c.offhand ? "\(bp.offhand)" : "\(bp.weapon)", c.kind, c.hero)
            let ms = HeroModelLibrary.meshSet(heroID: c.hero, blueprint: bp)
            let mesh = try XCTUnwrap(c.offhand ? ms.offhand : ms.weapon, c.kind)
            let url = try XCTUnwrap(Self.fixture(c.fixture), "\(c.fixture) がテストバンドルに無い")
            let template = try XCTUnwrap(HeroPropTemplate(entity: try Entity.load(contentsOf: url)), c.fixture)
            XCTAssertEqual(template.length, 1, accuracy: 0.02, "\(c.fixture) 正規化の長さ")
            HeroAssetLibrary.setPropTemplateForTesting(c.kind, template)
            defer { HeroAssetLibrary.setPropTemplateForTesting(c.kind, nil) }
            let m = try makeSkinned(c.hero, team: .blue)
            let holder = c.offhand ? m.offhand : m.weapon
            XCTAssertNil(holder.model, "\(c.kind) 手続きメッシュが残っている")
            let fit = try XCTUnwrap(holder.findEntity(named: "propFit"), "\(c.kind) Prop が付いていない")

            // 武器・副手の entity の座標で比べる（拡縮 weaponScale / offhandScale は両方に掛かる）
            let pb = mesh.bounds
            let fb = fit.visualBounds(recursive: true, relativeTo: holder, excludeInactive: false)
            let procPts = Self.points(mesh)
            let propPts = Self.points(fit, in: holder)
            let label = "\(c.kind) prop=\(fb.extents) c=\(fb.center) 手続き=\(pb.extents) c=\(pb.center)"
            XCTAssertFalse(propPts.isEmpty, label)

            // 長さ（Y）は揃え、横の大きさは同程度
            XCTAssertEqual(fb.extents.y, pb.extents.y, accuracy: 0.02 * pb.extents.y, "\(label) 長さ")
            let horiz = (fb.extents.x + fb.extents.z) / max(1e-4, pb.extents.x + pb.extents.z)
            XCTAssertTrue((0.5...2.0).contains(horiz), "\(label) 横の大きさ比 \(horiz)")
            // 横の広い向き（外接箱）と、最も薄い水平の向き（回した板・弓でも比べられる）
            if let a = Self.wide(fb), let b = Self.wide(pb) {
                XCTAssertEqual(a, b, "\(label) 横の広い向きが違う")
            }
            let tp = Self.thinDirection(procPts), tf = Self.thinDirection(propPts)
            if tp.ratio > 1.3 && tf.ratio > 1.3 {
                let deg = acos(min(1, abs(simd_dot(tp.n, tf.n)))) * 180 / .pi
                XCTAssertLessThan(deg, 25, "\(label) 薄い向きが \(deg)° ずれている 手続き=\(tp.n) prop=\(tf.n)")
            }
            // 位置: 中心合わせの種類は範囲の中心、それ以外は握り（原点）から同じ所へ伸びる
            if HeroGearBuilder.propMount(c.kind).center {
                XCTAssertLessThan(simd_distance(fb.center, pb.center), 0.03, "\(label) 中心")
            } else {
                let d = fb.center - pb.center
                XCTAssertLessThan(simd_length(V3(d.x, 0, d.z)), 0.08, "\(label) 横の中心")
                XCTAssertLessThan(abs(d.y), 0.12 * pb.extents.y, "\(label) 握りの位置")
            }

            // 面・上面・弦の向き
            let n = tp.n
            switch c.facing {
            case .awayFromGrip, .weaponTip:
                let procSide = c.facing == .weaponTip ? simd_dot(ms.weaponTip, n) : simd_dot(pb.center, n)
                XCTAssertGreaterThan(abs(procSide), 0.02, "\(label) 手続きの面の向きが決まらない")
                let marker = Self.points(fit, in: holder, marker: true)
                XCTAssertFalse(marker.isEmpty, "\(c.fixture) Marker の素材が見つからない")
                let propSide = simd_dot(Self.centroid(marker) - fb.center, n)
                XCTAssertGreaterThan(procSide * propSide, 0,
                                     "\(label) 面の向きが逆 手続き=\(procSide) prop=\(propSide) n=\(n)")
                if c.kind.hasSuffix("Shield") || c.kind == "harpBow" {
                    // HeroGear の盾・竪琴は面が -Z（を盾の yaw だけ回した向き）
                    let face = n * (procSide > 0 ? 1 : -1)
                    let yawed = ry(HeroGearBuilder.propMount(c.kind).yaw).act(V3(0, 0, -1))
                    XCTAssertGreaterThan(simd_dot(face, yawed), 0.9, "\(label) 手続きの面が -Z でない \(face)")
                }
            case .bowTips:
                let a = Self.midToEnds(procPts), b = Self.midToEnds(propPts)
                XCTAssertGreaterThan(simd_dot(simd_normalize(a), simd_normalize(b)), 0.7,
                                     "\(label) 弦の向きが違う 手続き=\(a) prop=\(b)")
            case .none:
                break
            }
            print("PropFixture \(c.kind): fit=\(fb.extents) c=\(fb.center) 手続き=\(pb.extents) c=\(pb.center) "
                  + "薄い向き 手続き=\(tp.n)(\(tp.ratio)) prop=\(tf.n)(\(tf.ratio))")
        }
    }

    // MARK: スキン・同梱アセット

    func testAllSkinsBuildSkinned() throws {
        let url = try XCTUnwrap(Self.fixture("SkinnedTestHero"))
        for c in master.cosmetics where c.type == .heroSkin {
            let model = HeroModelLibrary.makeHero(heroID: c.heroID, skinID: c.cosmeticID, team: .red, master: master,
                                                  options: HeroModelOptions.battle.with(mesh: .skinned(url)))
            XCTAssertTrue(model.isSkinned, c.cosmeticID)
            XCTAssertEqual(model.skin.cosmeticID, c.cosmeticID)
            XCTAssertEqual(model.root.findEntity(named: "aura") != nil, c.rarity == .epic, c.cosmeticID)
            XCTAssertLessThanOrEqual(model.entityCount, 35, c.cosmeticID)
        }
    }

    /// preload で読み込めば試合中の生成は USDZ を読まない。スキン専用アセットを優先し、壊れていれば本体を色味で塗る。
    func testPreloadAndSkinAssetPreference() throws {
        let url = try XCTUnwrap(Self.fixture("SkinnedTestHero"))
        let broken = try XCTUnwrap(Self.fixture("SkinnedTestHero_MissingJoint"))
        let skins = HeroSkins.skins(for: "H001", master: master)
        guard skins.count >= 2 else { throw XCTSkip("H001 のスキンが 2 つ未満") }
        let own = skins[0].cosmeticID, bad = skins[1].cosmeticID
        HeroAssetLibrary.resetForTesting()
        defer { HeroAssetLibrary.resetForTesting() }
        HeroAssetLibrary.resolver = { name in
            switch name {
            case "Hero_H001", "Hero_H001_\(own)": return url
            case "Hero_H001_\(bad)": return broken
            default: return nil
            }
        }
        let players: [(heroID: String, skinID: String?)] = [("H001", nil), ("H001", own), ("H001", bad), ("H002", nil)]
        HeroModelLibrary.preload(players: players, master: master)
        let loads = HeroAssetLibrary.loadCount
        let models = players.map {
            HeroModelLibrary.makeHero(heroID: $0.heroID, skinID: $0.skinID, team: .blue, master: master, options: .battle)
        }
        XCTAssertEqual(HeroAssetLibrary.loadCount, loads, "preload 後の生成で USDZ を読んだ")
        let base = try XCTUnwrap(models[0] as? SkinnedHeroModel)
        let withAsset = try XCTUnwrap(models[1] as? SkinnedHeroModel)
        let fallback = try XCTUnwrap(models[2] as? SkinnedHeroModel)
        XCTAssertFalse(models[3].isSkinned, "アセットの無い H002 は手続きモデル")
        func tint(_ m: SkinnedHeroModel) throws -> UIColor {
            try XCTUnwrap(m.skinnedEntity.model?.materials.first as? PhysicallyBasedMaterial).baseColor.tint
        }
        XCTAssertEqual(try tint(withAsset), try tint(base), "スキン専用アセットに色味を掛けている")
        XCTAssertNotEqual(try tint(fallback), try tint(base), "壊れたスキン専用アセットの代わりに本体を塗り分けていない")

        // 試合に使わないテンプレートは次の preload で捨てる（失敗の記録は残す）
        HeroModelLibrary.preload(players: [("H002", nil)], master: master)
        _ = HeroModelLibrary.makeHero(heroID: "H001", skinID: bad, team: .blue, master: master, options: .battle)
        XCTAssertEqual(HeroAssetLibrary.loadCount, loads + 1, "捨てた本体だけを読み直す")
    }

    /// ロード画面の分割読み込み: purge（読み込まない）→ 1 人ずつ preload（捨てない）→ 生成は USDZ を読まない。
    /// 次の試合の purge は使うものを残し、使わないものだけ捨てる。まとめての preload は何度呼んでもキャッシュ参照だけ。
    func testIncrementalPreloadAndPurge() throws {
        let a = try XCTUnwrap(Self.fixture("SkinnedTestHero"))
        // 別のヒーローの本体は URL を分ける（テンプレートは URL ごとに持つ）
        let b = FileManager.default.temporaryDirectory.appendingPathComponent("Hero_PreloadTestB.usdz")
        try? FileManager.default.removeItem(at: b)
        try FileManager.default.copyItem(at: a, to: b)
        defer { try? FileManager.default.removeItem(at: b) }
        let sword = try XCTUnwrap(Self.fixture("Prop_broadsword"))
        let shield = try XCTUnwrap(Self.fixture("Prop_gateShield"))
        HeroAssetLibrary.resetForTesting()
        defer { HeroAssetLibrary.resetForTesting() }
        HeroAssetLibrary.resolver = { name in
            switch name {
            case "Hero_H001": return a
            case "Hero_H002": return b
            case "Prop_broadsword": return sword
            case "Prop_gateShield": return shield
            default: return nil
            }
        }
        func make(_ id: String) -> any HeroDisplayModel {
            HeroModelLibrary.makeHero(heroID: id, skinID: nil, team: .blue, master: master, options: .battle)
        }
        let match: [(heroID: String, skinID: String?)] = [("H001", nil), ("H002", nil), ("H003", nil)]
        let before = HeroAssetLibrary.loadCount
        HeroModelLibrary.purge(keepingPlayers: match, master: master)
        XCTAssertEqual(HeroAssetLibrary.loadCount, before, "purge が読み込んでいる")
        for p in match { HeroModelLibrary.preload(heroID: p.heroID, skinID: p.skinID, master: master) }
        // 本体 2 + H001 の剣・盾（H002 の Prop は同梱が無い）
        XCTAssertEqual(HeroAssetLibrary.loadCount, before + 4)
        let loads = HeroAssetLibrary.loadCount
        let models = match.map { make($0.heroID) }
        XCTAssertEqual(HeroAssetLibrary.loadCount, loads, "preload 後の生成で USDZ を読んだ")
        XCTAssertTrue(models[0].isSkinned && models[1].isSkinned)
        XCTAssertFalse(models[2].isSkinned, "アセットの無い H003 は手続きモデル")
        XCTAssertNotNil(models[0].root.findEntity(named: "propFit"), "同梱 Prop が付いていない")

        // 次の試合（H001 のみ）: 使う H001 と Prop は残り、H002 だけ捨てる
        HeroModelLibrary.purge(keepingPlayers: [("H001", nil)], master: master)
        HeroModelLibrary.preload(heroID: "H001", skinID: nil, master: master)
        _ = make("H001")
        XCTAssertEqual(HeroAssetLibrary.loadCount, loads, "試合で使うテンプレートを捨てて読み直した")
        _ = make("H002")
        XCTAssertEqual(HeroAssetLibrary.loadCount, loads + 1, "使わない本体を捨てていない")
        // 1 人分の preload は捨てない（H002 は残る）。まとめての preload は 2 度目以降キャッシュ参照だけ
        HeroModelLibrary.preload(heroID: "H001", skinID: nil, master: master)
        _ = make("H002")
        XCTAssertEqual(HeroAssetLibrary.loadCount, loads + 1, "1 人分の preload が他を捨てた")
        HeroModelLibrary.preload(players: match, master: master)
        HeroModelLibrary.preload(players: match, master: master)
        XCTAssertEqual(HeroAssetLibrary.loadCount, loads + 1, "まとめての preload が読み直した")
    }

    /// 非同期の preload: 同時に呼んでも同じ USDZ を 2 度読まず、後の生成は同期版と同じ結果をキャッシュから作る。
    func testAsyncPreloadLoadsOnceAndMatchesSync() async throws {
        let a = try XCTUnwrap(Self.fixture("SkinnedTestHero"))
        let sword = try XCTUnwrap(Self.fixture("Prop_broadsword"))
        let shield = try XCTUnwrap(Self.fixture("Prop_gateShield"))
        HeroAssetLibrary.resetForTesting()
        defer { HeroAssetLibrary.resetForTesting() }
        HeroAssetLibrary.resolver = { name in
            switch name {
            case "Hero_H001": return a
            case "Prop_broadsword": return sword
            case "Prop_gateShield": return shield
            default: return nil
            }
        }
        let before = HeroAssetLibrary.loadCount
        async let p1: Void = HeroModelLibrary.preloadAsync(heroID: "H001", skinID: nil, master: master)
        async let p2: Void = HeroModelLibrary.preloadAsync(heroID: "H001", skinID: nil, master: master)
        _ = await (p1, p2)
        // 本体 1 + 剣・盾（進行中の読み込みは待ち合わせる）
        XCTAssertEqual(HeroAssetLibrary.loadCount, before + 3)
        // アセットの無いヒーローは手続きメッシュだけ（USDZ は読まない）
        await HeroModelLibrary.preloadAsync(heroID: "H003", skinID: nil, master: master)
        XCTAssertEqual(HeroAssetLibrary.loadCount, before + 3)
        let loads = HeroAssetLibrary.loadCount
        let model = HeroModelLibrary.makeHero(heroID: "H001", skinID: nil, team: .blue, master: master, options: .battle)
        XCTAssertEqual(HeroAssetLibrary.loadCount, loads, "非同期 preload 後の生成で USDZ を読んだ")
        XCTAssertTrue(model.isSkinned)
        XCTAssertNotNil(model.root.findEntity(named: "propFit"), "同梱 Prop が付いていない")
        model.update(dt: 1.0 / 60.0, moveSpeed: 0)
        let b = model.root.visualBounds(recursive: true, relativeTo: nil, excludeInactive: false)
        XCTAssertTrue(b.min.y.isFinite && b.max.y > 1.0, "姿勢が壊れている \(b)")
    }

    /// 同梱アセットの規約（同梱後に効く。今は対象が無いので素通り）。
    func testBundledHeroAssetsMeetContract() throws {
        let urls = Bundle.main.urls(forResourcesWithExtension: "usdz", subdirectory: nil) ?? []
        for url in urls where url.lastPathComponent.hasPrefix("Hero_") {
            let name = url.lastPathComponent
            let t = try XCTUnwrap(HeroAssetLibrary.heroTemplate(url), "\(name) が読めない・骨が足りない・規約違反")
            XCTAssertLessThan(t.triangleCount, 14_000, name)
            XCTAssertTrue((1.6...1.8).contains(t.bounds.max.y), "\(name) 身長 \(t.bounds.max.y)")
            XCTAssertEqual(t.bounds.min.y, 0, accuracy: 0.05, "\(name) 足元")
        }
        for def in master.heroes where HeroAssetLibrary.bundledURL("Hero_\(def.heroID)") != nil {
            let m = HeroModelLibrary.makeHero(heroID: def.heroID, skinID: nil, team: .blue, master: master, options: .battle)
            XCTAssertTrue(m.isSkinned, def.heroID)
            XCTAssertLessThanOrEqual(m.entityCount, 35, def.heroID)
        }
        for url in urls where url.lastPathComponent.hasPrefix("Prop_") {
            let name = url.lastPathComponent
            let t = try XCTUnwrap(HeroPropTemplate(entity: try Entity.load(contentsOf: url)), name)
            XCTAssertEqual(t.length, 1, accuracy: 0.05, name)
            // 薄い向きは水平（刃物 ±X、面が ±Z の副手は ±Z）。合わせ込み後の横の広い向きが手続きと同じ
            XCTAssertLessThanOrEqual(min(t.bounds.extents.x, t.bounds.extents.z), t.bounds.extents.y, "\(name) 長軸が Y でない")
            let kind = String(url.deletingPathExtension().lastPathComponent.dropFirst("Prop_".count))
            for def in master.heroes {
                let bp = HeroBlueprints.blueprint(heroID: def.heroID, role: def.role)
                let ms = HeroModelLibrary.meshSet(heroID: def.heroID, blueprint: bp)
                let mesh = "\(bp.weapon)" == kind ? ms.weapon : "\(bp.offhand)" == kind ? ms.offhand : nil
                guard let mesh, !SkinnedHeroModel.bodyWornGear.contains(kind) else { continue }
                let fb = Self.transformed(t.bounds, SkinnedHeroModel.propFit(kind, prop: t.bounds, procedural: mesh.bounds))
                if let a = Self.wide(fb), let b = Self.wide(mesh.bounds) {
                    XCTAssertEqual(a, b, "\(name) \(def.heroID) 横の広い向きが手続きと違う \(fb.extents) / \(mesh.bounds.extents)")
                }
            }
        }
    }

    // MARK: 性能

    func testTemplateLoadAndUpdateCost() throws {
        let url = try XCTUnwrap(Self.fixture("SkinnedTestHero"))
        let t0 = CFAbsoluteTimeGetCurrent()
        let entity = try Entity.load(contentsOf: url)
        let loadMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        let t1 = CFAbsoluteTimeGetCurrent()
        XCTAssertNotNil(SkinnedHeroTemplate(url: url, entity: entity))
        let rigMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000

        let ids = ["H001", "H004", "H007", "H011", "H013", "H016", "H019", "H021", "H022", "H024"]
        let t2 = CFAbsoluteTimeGetCurrent()
        let models = try ids.map { try makeSkinned($0, team: .blue) }
        let instanceMs = (CFAbsoluteTimeGetCurrent() - t2) * 1000 / Double(ids.count)
        for (i, m) in models.enumerated() { m.setState(i % 3 == 0 ? .attack : .run) }
        let frames = 300
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<frames {
            for m in models { m.update(dt: 1.0 / 60.0, moveSpeed: 330) }
        }
        let perFrameMs = (CFAbsoluteTimeGetCurrent() - start) / Double(frames) * 1000
        print(String(format: "SkinnedHeroModelTests: USDZ 読み込み %.1f ms / 骨対応 %.2f ms / 1 体の生成 %.2f ms / 10 体の更新 %.3f ms/フレーム",
                     loadMs, rigMs, instanceMs, perFrameMs))
        // Debug ビルド・シミュレータでも 1 フレームの予算を大きく下回ること
        XCTAssertLessThan(perFrameMs, 8)
    }
}
