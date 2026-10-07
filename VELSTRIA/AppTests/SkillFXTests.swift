import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

// スキル演出（SkillFX）: 24 ヒーロー × 4 スロット（パッシブ+Skill1/2+Ult）の固有演出・詠唱モーションがそろっていること、予算の範囲、
// プレイ中に何も作らないこと（全レシピを読み込み幕の裏で準備してから全段を再生しても AssetLedger の live = 0）。

@MainActor
final class SkillFXTests: XCTestCase {
    private var master: MasterData { MasterData.shared }

    private var heroIDs: [String] { master.heroes.map(\.heroID).sorted() }

    override func tearDown() {
        AssetLedger.end()
        super.tearDown()
    }

    func testEveryHeroHasOwnRecipeAndMotionForEverySkill() {
        XCTAssertEqual(heroIDs.count, 24)
        for id in heroIDs {
            guard let set = SkillFXCatalog.sets[id] else {
                XCTFail("\(id): 演出の定義が目録に無い")
                continue
            }
            for slot in SkillSlot.allCases {
                let info = SkillFXCatalog.info(heroID: id, slot: slot, master: master)
                let r = set.recipe(slot, info)
                XCTAssertFalse(r.isEmpty, "\(id) \(slot): 固有の演出が無い（既定演出のまま）")
                if slot == .passive {
                    XCTAssertFalse(r.cast.isEmpty, "\(id) パッシブ: 発動の演出（cast）が無い")
                } else {
                    XCTAssertFalse(r.cast.isEmpty && r.impact.isEmpty, "\(id) \(slot): 発動・着弾の演出が無い")
                }
            }
        }
    }

    func testEveryActiveSkillHasOwnMotionWithinDuration() {
        for id in heroIDs {
            let def = master.hero(id)
            let bp = HeroBlueprints.blueprint(heroID: id, role: def?.role)
            let profile = HeroMotionProfile(blueprint: bp, metrics: BodyMetrics.make(bp.build), heroID: id)
            let builder = MotionBuilder(rest: profile.rest, style: bp.attack, shield: profile.shieldHold,
                                        twoHanded: bp.twoHanded, bow: profile.bowHold)
            for (k, slot) in SkillSlot.actives.enumerated() {
                let clip = SkillFXCatalog.motion(heroID: id, slot: slot, builder: builder)
                XCTAssertNotNil(clip, "\(id) \(slot): 固有の詠唱モーションが無い")
                guard let clip else { continue }
                let limit: ClosedRange<Float> = slot == .ultimate ? 0.45...1.7 : 0.3...1.1
                XCTAssertTrue(limit.contains(clip.total), "\(id) \(slot): モーションの長さ \(clip.total) 秒が範囲外 \(limit)")
                XCTAssertEqual(profile.casts[k].total, clip.total, accuracy: 1e-5, "\(id) \(slot): 姿勢の設定に反映されていない")
                // 打撃（最初の数キー）が早い: 最初のキーは 0.25 秒以内
                XCTAssertLessThanOrEqual(clip.keys.first?.time ?? 0, 0.25, "\(id) \(slot): 最初のキーが遅い（sim は即時に解決する）")
                for key in clip.keys {
                    XCTAssertLessThan(simd_length(key.pose.offset), 2.5, "\(id) \(slot): 体の移動が大きすぎる")
                }
                // 評価が破綻しない（NaN が出ない）
                var t: Float = 0
                while t < clip.total {
                    let p = clip.evaluate(base: profile.rest, t: t)
                    XCTAssertFalse(p.armR.pitch.isNaN || p.offset.y.isNaN, "\(id) \(slot): 姿勢が NaN")
                    t += 0.05
                }
            }
        }
    }

    func testRecipesRespectBudgets() {
        for id in heroIDs {
            for slot in SkillSlot.allCases {
                let r = SkillFXCatalog.recipe(heroID: id, slot: slot, master: master)
                let ult = slot == .ultimate
                var meshes = 0, emits = 0
                for cue in r.all {
                    let n = max(1, cue.count)
                    switch cue.element {
                    case .mesh(let m):
                        meshes += n
                        XCTAssertGreaterThan(m.life, 0.01, "\(id) \(slot): 寿命 0 のメッシュ")
                        XCTAssertLessThanOrEqual(m.life, 4, "\(id) \(slot): メッシュの寿命が長すぎる")
                        XCTAssertLessThanOrEqual(max(m.sizeEnd.x, m.sizeEnd.z), 16, "\(id) \(slot): メッシュが大きすぎる")
                    case .emit(let e):
                        emits += n
                        XCTAssertLessThanOrEqual(e.count, 60, "\(id) \(slot): 粒子が多すぎる")
                        XCTAssertLessThanOrEqual(e.rate, 160, "\(id) \(slot): 継続放出が多すぎる")
                        XCTAssertLessThanOrEqual(e.life, 3, "\(id) \(slot): 粒子の寿命が長すぎる")
                        XCTAssertLessThanOrEqual(e.size * max(1, e.grow), 12, "\(id) \(slot): 粒子が大きすぎる（画面が白く飛ぶ）")
                        if e.rate > 0 && e.duration <= 0 {
                            XCTAssertEqual(cue.anchor, .follow, "\(id) \(slot): 止まらない継続放出は追従（travel）だけで使う")
                        }
                    case .shake(let s):
                        XCTAssertLessThanOrEqual(s, 1, "\(id) \(slot): 揺れが強すぎる")
                    }
                    XCTAssertLessThanOrEqual(cue.at + cue.every * Float(max(0, cue.count - 1)), 2.5,
                                             "\(id) \(slot): 遅れが長すぎる")
                }
                XCTAssertLessThanOrEqual(meshes, ult ? 28 : 20, "\(id) \(slot): メッシュの合図が多すぎる")
                XCTAssertLessThanOrEqual(emits, ult ? 16 : 13, "\(id) \(slot): 粒子の合図が多すぎる")
            }
        }
    }

    func testRecipesAreDistinctAcrossHeroes() {
        var seen: [Int: String] = [:]
        for id in heroIDs {
            for slot in SkillSlot.allCases {
                let r = SkillFXCatalog.recipe(heroID: id, slot: slot, master: master)
                var h = Hasher()
                h.combine(r.all)
                h.combine(SkillFXCatalog.palette(id).primary.r)
                let k = h.finalize()
                if let other = seen[k] { XCTFail("\(id) \(slot) の演出が \(other) と同じ") }
                seen[k] = "\(id) \(slot)"
            }
        }
    }

    /// 全ヒーローの全スキルを準備してから全段を再生しても、プレイ中に何も作らない。
    func testPlayingEveryRecipeCreatesNothingWhileLive() {
        AssetLedger.beginLoading()
        let player = SkillFXPlayer(quality: .preset(.high))
        var all: [(palette: FXPalette, recipe: SkillFXRecipe)] = []
        for id in heroIDs {
            for slot in SkillSlot.allCases {
                all.append((SkillFXCatalog.palette(id), SkillFXCatalog.recipe(heroID: id, slot: slot, master: master)))
            }
        }
        player.prewarm(recipes: all)
        player.resolve = { _ in SIMD3<Float>(1, 0, 1) }
        AssetLedger.beginLive()
        for (palette, r) in all {
            let ctx = SkillFXPlayer.Context(palette: palette, origin: .zero, caster: .zero, target: [0, 0, -5], forward: [0, 0, -1],
                                            follow: .unit(1))
            for phase in [r.cast, r.telegraph, r.travel, r.impact, r.hit] { player.play(phase, ctx) }
            for _ in 0..<3 { player.update(dt: 1.0 / 30) }
        }
        for _ in 0..<120 { player.update(dt: 1.0 / 30) }
        player.stop(follow: .unit(1))
        for _ in 0..<60 { player.update(dt: 1.0 / 30) }
        let snap = AssetLedger.snapshot()
        XCTAssertEqual(snap.liveTotal, 0, "プレイ中の生成: \(snap.live)\n" + snap.liveSamples.joined(separator: "\n"))
        XCTAssertGreaterThan(player.stats.plays, 200)
        XCTAssertEqual(player.activeCount, 0, "再生が終わったら全てプールへ戻る")
    }

    func testTexturesAreDrawn() {
        for t in FXTex.allCases {
            let img = FXTextureLibrary.image(t)
            XCTAssertNotNil(img, "\(t) が描けない")
            XCTAssertNotNil(img.flatMap { FXTextureLibrary.luminance($0) }, "\(t) の輝度版が作れない")
        }
    }
}
