import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

// スキル演出（SkillFX）: 34 ヒーロー × 4 スロット（パッシブ+Skill1/2+Ult）の固有演出・詠唱モーションがそろっていること、予算の範囲、
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
        XCTAssertEqual(heroIDs.count, 34)
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

    // MARK: 再使用の段（キット層）

    /// 段の演出を持つ（持たない）テスト用のヒーロー定義。
    private enum StagedSet: HeroFXSet {
        static let palette = FXPalette.from(RGB(1, 0.2, 0.2))
        static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
            var r = SkillFXRecipe()
            r.cast = [.shake(0.1)]
            r.hit = [.shake(0.3)]
            return r
        }
        static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
        static func recipe(_ slot: SkillSlot, stage: Int, _ s: FXSkillInfo) -> SkillFXRecipe? {
            guard slot == .skill2, stage == 1 else { return nil }
            var r = SkillFXRecipe()
            r.impact = [.shake(0.2)]
            return r
        }
    }

    private enum PlainSet: HeroFXSet {
        static let palette = FXPalette.from(RGB(0.2, 0.2, 1))
        static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe { SkillFXRecipe() }
        static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
    }

    /// 段の演出を書かないヒーローの既定は nil = 共通の演出（プロトコルの既定実装）。stage 0 は段の演出ではない。
    func testStageRecipeHookDefaultsToNoOverride() {
        let info = FXSkillInfo(heroID: "H029", slot: .skill2, archetype: .dashStrike, radius: 1, range: 4)
        XCTAssertNil(PlainSet.recipe(.skill2, stage: 1, info))
        XCTAssertNil(SkillFXCatalog.stageRecipe(heroID: "H029", slot: .skill2, stage: 0, master: master))
        XCTAssertNil(SkillFXCatalog.stageRecipe(heroID: "H999", slot: .skill2, stage: 1, master: master), "未知のヒーロー")
    }

    func testStageRecipeKeepsItsOwnPhasesAndFillsTheRestFromTheBase() throws {
        let info = FXSkillInfo(heroID: "HT", slot: .skill2, archetype: .dashStrike, radius: 1, range: 4)
        let base = StagedSet.recipe(.skill2, info)
        let staged = try XCTUnwrap(StagedSet.recipe(.skill2, stage: 1, info))
        XCTAssertNil(StagedSet.recipe(.skill1, stage: 1, info), "他のスロットは段で変えない")
        XCTAssertNil(StagedSet.recipe(.skill2, stage: 2, info), "他の段は共通の演出")
        let merged = SkillFXCatalog.merged(staged, over: base)
        XCTAssertEqual(merged.impact, staged.impact, "段の演出が優先")
        XCTAssertEqual(merged.cast, base.cast, "空の段は共通の演出で補う")
        XCTAssertEqual(merged.hit, base.hit)
        XCTAssertTrue(merged.travel.isEmpty)
        XCTAssertNotEqual(merged.impact, base.impact)
    }

    /// キットのパッシブの演出の合図: スタックが増えた・タイマーが始まった瞬間だけ。
    func testKitPassiveFiresOnStackGainOrTimerStart() {
        let none = SkillFXDirector.kitPassiveSample(nil)
        XCTAssertEqual(none.stacks, 0)
        XCTAssertFalse(none.timer)
        let two = SkillFXDirector.kitPassiveSample(KitBadge(kind: .stacks, value: 2, maxValue: 4))
        XCTAssertEqual(two.stacks, 2)
        XCTAssertFalse(two.timer)
        let running = SkillFXDirector.kitPassiveSample(KitBadge(kind: .timer, remaining: 1.5, total: 3))
        XCTAssertEqual(running.stacks, 0)
        XCTAssertTrue(running.timer)
        XCTAssertFalse(SkillFXDirector.kitPassiveSample(KitBadge(kind: .timer, remaining: 0, total: 3)).timer)
        XCTAssertFalse(SkillFXDirector.kitPassiveSample(KitBadge(kind: .form, value: 1, maxValue: 1)).timer)

        XCTAssertTrue(SkillFXDirector.kitPassiveFires(last: (1, false), now: (2, false)), "スタックが増えた")
        XCTAssertFalse(SkillFXDirector.kitPassiveFires(last: (2, false), now: (2, false)), "変わらない")
        XCTAssertFalse(SkillFXDirector.kitPassiveFires(last: (3, false), now: (0, false)), "消費・リセットでは出さない")
        XCTAssertTrue(SkillFXDirector.kitPassiveFires(last: (0, false), now: (0, true)), "タイマーの開始")
        XCTAssertFalse(SkillFXDirector.kitPassiveFires(last: (0, true), now: (0, true)), "タイマーの継続")
        XCTAssertFalse(SkillFXDirector.kitPassiveFires(last: (0, true), now: (0, false)), "タイマーの終了")
    }

    /// 解放の演出（パッシブのスタックの消費）を持つ（持たない）テスト用のヒーロー定義。
    private enum ReleaseSet: HeroFXSet {
        static let palette = FXPalette.from(RGB(0.9, 0.9, 0.2))
        static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe { SkillFXRecipe() }
        static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
        static func passiveRelease(_ s: FXSkillInfo, released: Int) -> [FXCue]? {
            released >= 2 ? [.shake(0.3)] : [.shake(0.1)]
        }
    }

    /// 解放の演出の既定は nil（何も出さない）。未知のヒーローも nil。実装したヒーローは消費したスタック数を受け取れる。
    func testPassiveReleaseHookDefaultsToNil() throws {
        let info = FXSkillInfo(heroID: "HT", slot: .passive, archetype: .passive, radius: 1, range: 4)
        XCTAssertNil(PlainSet.passiveRelease(info, released: 3))
        XCTAssertNil(StagedSet.passiveRelease(info, released: 1))
        XCTAssertNil(SkillFXCatalog.passiveRelease(heroID: "H999", released: 1, master: master))
        XCTAssertEqual(ReleaseSet.passiveRelease(info, released: 1) ?? [], [FXCue.shake(0.1)])
        XCTAssertEqual(ReleaseSet.passiveRelease(info, released: 4) ?? [], [FXCue.shake(0.3)])
    }

    /// 解放の合図: スキルの発動の直後（窓の中）に、スタックが 1 以上から 0 になったときだけ。
    func testKitPassiveReleasesOnlyRightAfterACast() {
        let w = SkillFXDirector.kitReleaseWindow
        XCTAssertTrue(SkillFXDirector.kitPassiveReleases(last: (2, false), now: (0, false), sinceCast: 0))
        XCTAssertTrue(SkillFXDirector.kitPassiveReleases(last: (1, false), now: (0, false), sinceCast: w))
        XCTAssertFalse(SkillFXDirector.kitPassiveReleases(last: (1, false), now: (0, false), sinceCast: w + 0.01), "窓を過ぎた")
        XCTAssertFalse(SkillFXDirector.kitPassiveReleases(last: (1, false), now: (0, false), sinceCast: nil), "発動していない（死亡・期限切れなど）")
        XCTAssertFalse(SkillFXDirector.kitPassiveReleases(last: (1, false), now: (0, false), sinceCast: -0.1), "未来の発動は数えない")
        XCTAssertFalse(SkillFXDirector.kitPassiveReleases(last: (0, false), now: (0, false), sinceCast: 0), "元から 0")
        XCTAssertFalse(SkillFXDirector.kitPassiveReleases(last: (3, false), now: (1, false), sinceCast: 0), "一部だけ減った")
        XCTAssertFalse(SkillFXDirector.kitPassiveReleases(last: (1, false), now: (2, false), sinceCast: 0), "増えた")
        // 増える側の合図は従来どおり（解放の合図とは同時に立たない）
        XCTAssertFalse(SkillFXDirector.kitPassiveFires(last: (2, false), now: (0, false)))
    }

    /// 被弾演出の間隔: キットのヒーローは 0.9 秒、他は 0.15 秒。1 発ごとの演出（hitPerHit）は 0.15 秒のまま。
    func testHitReplayIntervalForKitHeroes() {
        XCTAssertEqual(SkillFXDirector.hitInterval(kitHero: false, perHit: false), SkillFXDirector.plainHitInterval)
        XCTAssertEqual(SkillFXDirector.hitInterval(kitHero: true, perHit: false), SkillFXDirector.kitHitInterval)
        XCTAssertEqual(SkillFXDirector.hitInterval(kitHero: true, perHit: true), SkillFXDirector.plainHitInterval)
        XCTAssertEqual(SkillFXDirector.hitInterval(kitHero: false, perHit: true), SkillFXDirector.plainHitInterval)
        XCTAssertLessThan(SkillFXDirector.kitHitInterval, 1, "lastHit のお掃除（1 秒）より短い")
        XCTAssertFalse(SkillFXRecipe().hitPerHit, "既定は間引く")

        // ゴルムの奥義: 0.3 秒おきの 6 ヒット
        let times: [Float] = [0, 0.3, 0.6, 0.9, 1.2, 1.5]
        func replays(_ interval: Float) -> Int {
            var last: Float?
            var n = 0
            for t in times where SkillFXDirector.hitReplayAllowed(last: last, now: t, interval: interval) {
                last = t
                n += 1
            }
            return n
        }
        XCTAssertEqual(replays(SkillFXDirector.plainHitInterval), 6, "従来の間隔なら全ヒットで再生")
        XCTAssertEqual(replays(SkillFXDirector.kitHitInterval), 2, "最初と 0.9 秒後だけ")
        XCTAssertTrue(SkillFXDirector.hitReplayAllowed(last: nil, now: 0, interval: 0.9), "初回は再生")
        XCTAssertFalse(SkillFXDirector.hitReplayAllowed(last: 1, now: 1.5, interval: 0.9))
        XCTAssertTrue(SkillFXDirector.hitReplayAllowed(last: 1, now: 2, interval: 0.9))
    }

    /// 段の演出が hit を持たず共通の演出から借りるときは、1 発ごとの指定も共通のものに合わせる。
    func testMergedStageRecipeFollowsBaseHitPerHit() {
        var base = SkillFXRecipe()
        base.hit = [.shake(0.2)]
        base.hitPerHit = true
        var stage = SkillFXRecipe()
        stage.impact = [.shake(0.1)]
        XCTAssertTrue(SkillFXCatalog.merged(stage, over: base).hitPerHit)
        stage.hit = [.shake(0.4)]
        XCTAssertFalse(SkillFXCatalog.merged(stage, over: base).hitPerHit, "段が自分の hit を持てば段の指定")
    }

    func testTexturesAreDrawn() {
        for t in FXTex.allCases {
            let img = FXTextureLibrary.image(t)
            XCTAssertNotNil(img, "\(t) が描けない")
            XCTAssertNotNil(img.flatMap { FXTextureLibrary.luminance($0) }, "\(t) の輝度版が作れない")
        }
    }
}
