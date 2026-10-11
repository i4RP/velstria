import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 同梱のスキンメッシュのヒーロー（Hero_H0xx.usdz）で、武器が手に握られた向き・大きさになっているかの検査。
/// 待機（モーションクリップの idle）・通常攻撃・詠唱の各時点で、武器・副手の entity（握りが原点）が手の骨の近くにあり、
/// 槍は立て、弓は上を少し前へ傾け、灯籠は真下へ吊るす（HeroMotionSets.idleWeaponR / L・SkinnedHeroModel.hangingGear）。
@MainActor
final class HeroGripTests: XCTestCase {
    private let master = MasterData.shared
    private let up = SIMD3<Float>(0, 1, 0)

    private func skinned(_ id: String, state: HeroAnimState, seconds: Double) -> SkinnedHeroModel? {
        guard HeroAssetLibrary.bundledURL("Hero_\(id)") != nil else { return nil }
        let m = HeroModelLibrary.makeHero(heroID: id, skinID: nil, team: .neutral, master: master, options: .showcase)
        guard let s = m as? SkinnedHeroModel else { return nil }
        s.setState(state)
        for _ in 0..<Int(seconds * 60) { s.update(dt: 1.0 / 60.0, moveSpeed: 0) }
        return s
    }

    /// 武器・副手の +Y（握り → 先端）のヒーロー空間の向き。
    private func axis(_ e: Entity) -> SIMD3<Float> { simd_normalize(e.orientation.act(up)) }

    func testWeaponsStayInHandAcrossBundledHeroes() throws {
        var checked = 0
        for def in master.heroes {
            for (state, t) in [(HeroAnimState.idle, 1.5), (.attack, 0.35), (.cast(.skill1), 0.3)] {
                guard let s = skinned(def.heroID, state: state, seconds: t) else { continue }
                let hr = try XCTUnwrap(s.jointPosition(.handR)), hl = try XCTUnwrap(s.jointPosition(.handL))
                XCTAssertLessThan(simd_distance(s.weapon.position, hr), 0.1, "\(def.heroID) \(state) 武器が右手から離れる")
                XCTAssertLessThan(simd_distance(s.offhand.position, hl), 0.1, "\(def.heroID) \(state) 副手が左手から離れる")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0, "同梱のスキンメッシュのヒーローが無い")
    }

    /// 待機の槍は立てて持つ（腰だめの構え -1.0 のままだと穂先が顔の前を横切る）。
    func testSpearsStandUprightInIdle() throws {
        for id in ["H005", "H008", "H023"] {
            guard let s = skinned(id, state: .idle, seconds: 1.5) else { continue }
            XCTAssertGreaterThan(simd_dot(axis(s.weapon), up), 0.9, "\(id) 待機の槍が立っていない")
        }
    }

    /// 待機の弓は縦に握り、上の弓先を少し前へ傾ける。下の弓先が足元（地面から 15 cm 以内）へ届かない。
    func testBowsAreHeldUprightAndClearOfTheFeet() throws {
        for id in ["H003", "H020"] {
            guard let s = skinned(id, state: .idle, seconds: 1.5) else { continue }
            let a = axis(s.offhand)
            XCTAssertGreaterThan(simd_dot(a, up), 0.75, "\(id) 弓が縦でない（構えの前傾込み）")
            XCTAssertLessThan(a.z, -0.15, "\(id) 弓の上が前へ傾いていない")
            let b = s.offhand.visualBounds(recursive: true, relativeTo: s.root, excludeInactive: false)
            XCTAssertGreaterThan(b.min.y, 0.15, "\(id) 弓の下端が足元に立つ")
            XCTAssertLessThan(b.extents.y, 1.1, "\(id) 弓が大きすぎる")
        }
    }

    /// 灯籠は振りの武器角に関係なく真下へ吊るす。
    func testLanternHangsStraightDown() throws {
        for (state, t) in [(HeroAnimState.idle, 1.5), (.attack, 0.35), (.run, 0.5)] {
            guard let s = skinned("H006", state: state, seconds: t) else { continue }
            XCTAssertGreaterThan(simd_dot(axis(s.offhand), up), 0.999, "H006 \(state) 灯籠が吊り下がっていない")
        }
    }

    /// H003 の本体: 矢筒の矢が背中の後ろへ突き出していない（Tripo の崩れた部品を切った。tools/blender/fix_hero_mesh.py）。
    func testFirielQuiverDoesNotStickOutBehind() throws {
        let url = try XCTUnwrap(HeroAssetLibrary.bundledURL("Hero_H003"))
        let t = try XCTUnwrap(HeroAssetLibrary.heroTemplate(url))
        XCTAssertLessThan(t.bounds.max.z, 0.9, "H003 の背中の後ろへ突き出した部品が残っている（範囲 \(t.bounds.max.z) m）")
    }
}
