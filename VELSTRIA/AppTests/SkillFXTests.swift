import RealityKit
import XCTest
@testable import VELSTRIA
import VelstriaCore

// スキル演出（SkillFX）: 34 ヒーロー × 4 スロット（パッシブ+Skill1/2+Ult）の固有演出・詠唱モーションがそろっていること、予算の範囲、
// プレイ中に何も作らないこと（全レシピを読み込み幕の裏で準備してから全段を再生しても AssetLedger の live = 0）。

@MainActor
final class SkillFXTests: XCTestCase {
    private var master: MasterData { MasterData.shared }

    private var heroIDs: [String] { master.allHeroes.map(\.heroID).sorted() }

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
                var meshes = 0, emits = 0, efks = 0
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
                    case .efk(let x):
                        efks += n
                        XCTAssertTrue(x.name.hasPrefix(id + "_"), "\(id) \(slot): 重ねる .efk はそのヒーローの名前（\(x.name)）")
                        XCTAssertLessThanOrEqual(x.scale, 3, "\(id) \(slot): .efk の倍率が大きすぎる")
                        XCTAssertLessThanOrEqual(x.followFor, 4, "\(id) \(slot): .efk の追従が長すぎる")
                    case .ribbon(let rb):
                        // 帯はメッシュの枠として数える（帯のプールは ribbonCapacity）
                        meshes += n
                        XCTAssertLessThanOrEqual(rb.span, 4, "\(id) \(slot): 帯の寿命が長すぎる")
                        XCTAssertLessThanOrEqual(rb.width, 6, "\(id) \(slot): 帯が太すぎる")
                    }
                    XCTAssertLessThanOrEqual(cue.at + cue.every * Float(max(0, cue.count - 1)), 2.5,
                                             "\(id) \(slot): 遅れが長すぎる")
                }
                XCTAssertLessThanOrEqual(meshes, ult ? 28 : 20, "\(id) \(slot): メッシュの合図が多すぎる")
                XCTAssertLessThanOrEqual(emits, ult ? 16 : 13, "\(id) \(slot): 粒子の合図が多すぎる")
                XCTAssertLessThanOrEqual(efks, BattleWorkBudget.efkCuesPerRecipe, "\(id) \(slot): 重ねる .efk が多すぎる")
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

    func testCosmeticCueQueueIsBoundedAndRecoversAfterOverload() {
        let player = SkillFXPlayer(quality: .preset(.low))
        let ctx = SkillFXPlayer.Context(palette: .from(RGB(1, 1, 1)), origin: .zero,
                                       caster: .zero, target: .zero, forward: [0, 0, -1])
        var cue = FXCue.shake(0.1, at: 1)
        cue.count = 100_000
        for _ in 0..<20 { player.play([cue], ctx) }
        XCTAssertEqual(player.pendingCount, BattleWorkBudget.pendingCues)
        XCTAssertGreaterThan(player.stats.droppedCues, 0)
        var fired = 0
        player.onShake = { _, _ in fired += 1 }
        player.update(dt: 2)
        XCTAssertEqual(fired, BattleWorkBudget.pendingCues)
        XCTAssertEqual(player.pendingCount, 0)
        player.play([.shake(0.1)], ctx)
        XCTAssertEqual(fired, BattleWorkBudget.pendingCues + 1)
        player.clear()
        XCTAssertEqual(player.pendingCount, 0)
    }

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

    // MARK: 空の段の補い

    /// 空の段は既定演出（FXGeneric）で補う。fillsEmptyPhases = false のレシピは空の段を空のまま残す
    /// （ゴルムのスキル2・奥義の振りかぶりは MLBB で光らない。補うと魔法陣と光が出ていた）。
    func testRecipeCanKeepAnEmptyPhaseWithoutTheGenericFill() {
        for slot in [SkillSlot.skill2, .ultimate] {
            let r = SkillFXCatalog.recipe(heroID: "H034", slot: slot, master: master)
            XCTAssertFalse(r.fillsEmptyPhases)
            XCTAssertTrue(r.cast.isEmpty, "H034 \(slot) の cast は空のまま")
            XCTAssertFalse(r.impact.isEmpty)
        }
        let passive = SkillFXCatalog.recipe(heroID: "H028", slot: .passive, master: master)
        XCTAssertTrue(passive.fillsEmptyPhases)
        let s = SkillFXCatalog.info(heroID: "H028", slot: .passive, master: master)
        XCTAssertEqual(passive.hit, FXGeneric.recipe(s).hit, "既定のレシピの空の段は今までどおり補う")
    }

    // MARK: 残りの数（H028 の環剣の剣）

    /// ザイルの環剣: 回る刃は 1 本ずつ別の合図で FXMesh.group 1〜5（2.4 秒ずつ 2 組）。sim の剣の本数（スキル1 のバッジ）が減ると
    /// 使った本数ぶんの組を消す（低画質でも出す 3 本は最後に消える）。
    func testZailSwordBladesHaveOneGroupPerSwordAndDisappearInOrder() {
        let r = SkillFXCatalog.recipe(heroID: "H028", slot: .skill1, master: master)
        var groups: [Int: Int] = [:]
        var lowQuality = Set<Int>()
        for cue in r.cast {
            guard case .mesh(let m) = cue.element, m.group != 0 else { continue }
            XCTAssertEqual(m.shape, .arc)
            XCTAssertEqual(cue.anchor, .follow)
            XCTAssertEqual(cue.count, 1, "刃 1 本ずつ別の合図")
            XCTAssertEqual(m.size, m.sizeEnd, "消すときに寿命を縮めるので大きさは変えない")
            groups[m.group, default: 0] += 1
            if cue.minQuality == 0 { lowQuality.insert(m.group) }
        }
        XCTAssertEqual(groups, [1: 2, 2: 2, 3: 2, 4: 2, 5: 2], "5 本 × 2 組")
        XCTAssertEqual(lowQuality, [3, 4, 5], "低画質の 3 本は最後に消える")
        XCTAssertTrue((r.impact + r.hit).allSatisfy { cue in
            if case .mesh(let m) = cue.element { return m.group == 0 }
            return true
        }, "組は回る刃だけ")
        XCTAssertEqual(SkillFXCatalog.countedSlot(heroID: "H028"), .skill1)
        XCTAssertNil(SkillFXCatalog.countedSlot(heroID: "H001"))
        XCTAssertEqual(SkillFXCatalog.spentGroups(heroID: "H028", remaining: 5), [])
        XCTAssertEqual(SkillFXCatalog.spentGroups(heroID: "H028", remaining: 4), [1])
        XCTAssertEqual(SkillFXCatalog.spentGroups(heroID: "H028", remaining: 2), [1, 2, 3])
        XCTAssertEqual(SkillFXCatalog.spentGroups(heroID: "H028", remaining: 0), [1, 2, 3, 4, 5])
        XCTAssertEqual(SkillFXCatalog.spentGroups(heroID: "H028", remaining: 9), [])
        XCTAssertEqual(SkillFXCatalog.spentGroups(heroID: "H001", remaining: 0), [])
        XCTAssertEqual(PlainSet.spentGroups(remaining: 0), [], "既定は消さない")
        XCTAssertNil(PlainSet.countedSlot)
        // 数の読み取り（.stacks の値だけ）と、減ったかの判定
        XCTAssertEqual(SkillFXDirector.kitCountSample(nil), 0)
        XCTAssertEqual(SkillFXDirector.kitCountSample(KitBadge(kind: .stacks, value: 3, maxValue: 5)), 3)
        XCTAssertEqual(SkillFXDirector.kitCountSample(KitBadge(kind: .timer, remaining: 2, total: 4)), 0)
        XCTAssertFalse(SkillFXDirector.kitCountDropped(last: nil, now: 4), "最初に見た値は基準だけ")
        XCTAssertTrue(SkillFXDirector.kitCountDropped(last: 5, now: 4))
        XCTAssertTrue(SkillFXDirector.kitCountDropped(last: 1, now: 0), "使い切った・戻った")
        XCTAssertFalse(SkillFXDirector.kitCountDropped(last: 3, now: 5), "撃ち直しで増えた")
        XCTAssertFalse(SkillFXDirector.kitCountDropped(last: 4, now: 4))
        XCTAssertTrue(SkillFXDirector.kitCountDropped(last: Int.max, now: 5), "発動の直後の基準（消す組は無い）")
    }

    /// cut: 追従している主体の、その組のメッシュだけを短く消し、まだ出ていない同じ組の合図も取り消す。
    func testCutRemovesOnlyThatGroupOfTheFollowedUnitAndItsPendingCues() {
        let player = SkillFXPlayer(quality: .preset(.high))
        player.prewarm(recipes: [])
        player.resolve = { _ in SIMD3<Float>(0, 0, 0) }
        let blade = FXMesh(shape: .arc, tex: .shard, tint: .core, alpha: 1, size: [4, 1, 4], sizeEnd: [4, 1, 4], ease: .linear,
                           life: 2, fadeIn: 0.05, fadeOut: 0.9, spin: -150)
        let ctx = SkillFXPlayer.Context(palette: .from(RGB(1, 1, 1)), origin: .zero, caster: .zero, target: [0, 0, -1],
                                        forward: [0, 0, -1], follow: .unit(7))
        player.play([.mesh(blade.with { $0.group = 1 }, .follow), .mesh(blade.with { $0.group = 2 }, .follow),
                     .mesh(blade.with { $0.group = 1 }, at: 1, .follow)], ctx)
        XCTAssertEqual(player.activeCount, 2)
        XCTAssertEqual(player.pendingCount, 1)
        player.cut(follow: .unit(8), group: 1)
        player.update(dt: 0.2)
        XCTAssertEqual(player.activeCount, 2, "ほかの主体の組は消さない")
        XCTAssertEqual(player.pendingCount, 1)
        player.cut(follow: .unit(7), group: 1)
        XCTAssertEqual(player.pendingCount, 0, "まだ出ていない同じ組の合図も取り消す")
        player.update(dt: 0.2)
        XCTAssertEqual(player.activeCount, 1, "組 1 だけ消えた")
        player.cut(follow: .unit(7), group: 0)
        player.update(dt: 0.05)
        XCTAssertEqual(player.activeCount, 1, "組 0 は消さない")
        player.clear()
    }

    /// 被弾演出の間隔: キットのヒーローは 0.9 秒、他は 0.15 秒。1 発ごとの演出（hitPerHit）は 0.15 秒のまま。
    func testHitReplayIntervalForKitHeroes() {
        XCTAssertEqual(SkillFXDirector.hitInterval(kitHero: false, perHit: false), SkillFXDirector.plainHitInterval)
        XCTAssertEqual(SkillFXDirector.hitInterval(kitHero: true, perHit: false), SkillFXDirector.kitHitInterval)
        XCTAssertEqual(SkillFXDirector.hitInterval(kitHero: true, perHit: true), SkillFXDirector.plainHitInterval)
        XCTAssertEqual(SkillFXDirector.hitInterval(kitHero: false, perHit: true), SkillFXDirector.plainHitInterval)
        XCTAssertLessThan(SkillFXDirector.kitHitInterval, 1, "lastHit のお掃除（1 秒）より短い")
        XCTAssertFalse(SkillFXRecipe().hitPerHit, "既定は間引く")

        // ゴルムの奥義: 0.32 秒おきの 6 ヒット（MLBB の画面収録で測った値。Kit_H034.Tune.ultInterval）
        let times: [Float] = [0, 0.32, 0.64, 0.96, 1.28, 1.6]
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
        XCTAssertEqual(replays(SkillFXDirector.kitHitInterval), 2, "最初と 0.96 秒後だけ")
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

    /// 発動のイベントの長さ（SkillCastEvent.duration）: 0 以下・有限でない値は使わず、上書きは下限〜上限に収める。
    func testCastDurationIsClampedAndFallsBackWhenZero() {
        XCTAssertNil(FXCue.castDuration(0), "0 = 書いた値のまま")
        XCTAssertNil(FXCue.castDuration(-1))
        XCTAssertNil(FXCue.castDuration(.nan))
        XCTAssertNil(FXCue.castDuration(.infinity))
        XCTAssertEqual(FXCue.castDuration(6.5) ?? 0, 6.5, accuracy: 1e-5)
        XCTAssertEqual(FXCue.castDuration(30) ?? 0, FXCue.castDurationLimit, "上限で抑える")
        XCTAssertEqual(FXCue.castDuration(0.01) ?? 0, FXCue.castDurationFloor, "下限で抑える")
        XCTAssertLessThanOrEqual(FXCue.castDurationLimit, 10)
    }

    /// durationFromCast を立てた継続放出の duration・メッシュの life だけが発動の長さになる。
    func testCastDurationOverridesOnlyFlaggedCues() {
        let loop = FXEmit(rate: 10, duration: 4, life: 0.4, durationFromCast: true)
        let burst = FXEmit(count: 8, life: 0.4, durationFromCast: true)
        let plainLoop = FXEmit(rate: 10, duration: 4, life: 0.4)
        let mesh = FXMesh(shape: .disc, life: 4, durationFromCast: true)
        let plainMesh = FXMesh(shape: .disc, life: 4)
        let cues: [FXCue] = [.emit(loop, .follow), .emit(burst), .emit(plainLoop, .follow), .mesh(mesh, .follow),
                             .mesh(plainMesh), .shake(0.2)]
        XCTAssertEqual(cues.map(\.usesCastDuration), [true, false, false, true, false, false],
                       "一斉放出（rate 0）・印の無い合図・揺れは対象外")

        let out = FXCue.applyingCastDuration(cues, seconds: 9)
        XCTAssertEqual(out.count, cues.count)
        guard case .emit(let e0) = out[0].element, case .emit(let e1) = out[1].element, case .emit(let e2) = out[2].element,
              case .mesh(let m3) = out[3].element, case .mesh(let m4) = out[4].element else {
            return XCTFail("要素の種類が変わった")
        }
        XCTAssertEqual(e0.duration, 9, accuracy: 1e-5)
        XCTAssertEqual(e0.life, 0.4, accuracy: 1e-5, "粒子 1 つの寿命は変えない")
        XCTAssertEqual(e1, burst)
        XCTAssertEqual(e2, plainLoop)
        XCTAssertEqual(m3.life, 9, accuracy: 1e-5)
        XCTAssertEqual(m4, plainMesh)
        XCTAssertEqual(out[5], cues[5])
        XCTAssertEqual(out[3].anchor, .follow, "置き方は変えない")

        XCTAssertEqual(FXCue.applyingCastDuration(cues, seconds: 0), cues, "長さ 0 = 書いた値のまま")
        let clamped = FXCue.applyingCastDuration(cues, seconds: 600)
        guard case .mesh(let mc) = clamped[3].element, case .emit(let ec) = clamped[0].element else { return XCTFail() }
        XCTAssertEqual(mc.life, FXCue.castDurationLimit)
        XCTAssertEqual(ec.duration, FXCue.castDurationLimit)
    }

    /// ルミナの S1（効果時間 4→9 秒）: 効果中の弓のきらめきは発動の長さに合わせ、書いた値はランク 1 の 4 秒。
    /// （足元の三日月は MLBB の画面収録に無いので 2026-10-17 に外した。docs/vfx/H025.md）
    func testLuminaMoonArrowBuffFollowsCastDuration() {
        let r = SkillFXCatalog.recipe(heroID: "H025", slot: .skill1, master: master)
        let flagged = r.cast.filter(\.usesCastDuration)
        XCTAssertEqual(flagged.count, 1, "弓のきらめき（継続放出）")
        XCTAssertTrue(flagged.allSatisfy { if case .emit = $0.element { return true } else { return false } })
        for cue in flagged {
            XCTAssertEqual(cue.anchor, .follow, "効果中の演出は術者に追従する")
            switch cue.element {
            case .mesh(let m): XCTAssertEqual(m.life, 4, accuracy: 1e-5)
            case .emit(let e): XCTAssertEqual(e.duration, 4, accuracy: 1e-5)
            case .shake, .ribbon, .efk: XCTFail()
            }
        }
        for cue in FXCue.applyingCastDuration(r.cast, seconds: 9).filter(\.usesCastDuration) {
            switch cue.element {
            case .mesh(let m): XCTAssertEqual(m.life, 9, accuracy: 1e-5)
            case .emit(let e): XCTAssertEqual(e.duration, 9, accuracy: 1e-5)
            case .shake, .ribbon, .efk: XCTFail()
            }
        }
        XCTAssertTrue(r.impact.allSatisfy { !$0.usesCastDuration }, "放つ矢は長さに関係しない")
        // 奥義（隠密）は位置を見せないため、効果の長さで追従する合図を持たない
        let ult = SkillFXCatalog.recipe(heroID: "H025", slot: .ultimate, master: master)
        XCTAssertTrue(ult.all.allSatisfy { !$0.usesCastDuration })
    }

    /// 発動の長さを取る合図も、書いた値は予算の範囲（testRecipesRespectBudgets）。上書きは上限で抑えられる。
    func testCastDurationCuesStayBoundedForEveryHero() {
        for id in heroIDs {
            for slot in SkillSlot.allCases {
                let r = SkillFXCatalog.recipe(heroID: id, slot: slot, master: master)
                for cue in FXCue.applyingCastDuration(r.cast + r.impact, seconds: 1_000) where cue.usesCastDuration {
                    switch cue.element {
                    case .mesh(let m): XCTAssertLessThanOrEqual(m.life, FXCue.castDurationLimit, "\(id) \(slot)")
                    case .emit(let e): XCTAssertLessThanOrEqual(e.duration, FXCue.castDurationLimit, "\(id) \(slot)")
                    case .shake, .ribbon, .efk: break
                    }
                }
            }
        }
    }

    func testTexturesAreDrawn() {
        for t in FXTex.allCases {
            let img = FXTextureLibrary.image(t)
            XCTAssertNotNil(img, "\(t) が描けない")
            XCTAssertNotNil(img.flatMap { FXTextureLibrary.luminance($0) }, "\(t) の輝度版が作れない")
        }
    }

    // MARK: 予算の観測（打ち切り・破棄の集計。docs/SKILL_FX.md「予算の観測」）
    // 容量は本番の値（低画質のプール）をそのまま使い、実際の取得の経路で超過させる。

    private func budgetContext(_ heroID: String, follow: SkillFXPlayer.Follow? = nil) -> SkillFXPlayer.Context {
        SkillFXPlayer.Context(palette: .from(RGB(1, 1, 1)), origin: .zero, caster: .zero, target: [0, 0, -1],
                              forward: [0, 0, -1], follow: follow,
                              source: SkillFXPlayer.Source(heroID: heroID, slot: .skill1, stage: 0))
    }

    /// 一斉放出（回収は寿命 × 1.2 + 0.1 秒後）を x の位置に置く。
    private func burst(x: Float, life: Float = 0.5, at: Float = 0) -> FXCue {
        .emit(FXEmit(count: 4, life: life), at: at, offset: [x, 0, 0])
    }

    private func disc(x: Float, life: Float = 2, at: Float = 0) -> FXCue {
        .mesh(FXMesh(shape: .disc, life: life), at: at, offset: [x, 0, 0])
    }

    /// x の位置で使用中の粒子放出体・メッシュ。
    private func emitter(_ p: SkillFXPlayer, x: Float) -> Entity? {
        p.root.children.first {
            $0.isEnabled && $0.components[ParticleEmitterComponent.self] != nil && abs($0.position.x - x) < 0.001
        }
    }

    private func mesh(_ p: SkillFXPlayer, x: Float) -> Entity? {
        p.root.children.first { $0.isEnabled && $0 is ModelEntity && abs($0.position.x - x) < 0.001 }
    }

    func testBudgetCountsNoCutWithinCapacity() {
        let q = RenderQuality.preset(.low)
        let player = SkillFXPlayer(quality: q)
        player.prewarm(recipes: [])
        let nE = SkillFXPlayer.emitterCapacity(q), nD = SkillFXPlayer.meshCapacity(.disc, q)
        let cues = (0..<nE).map { burst(x: Float($0)) } + (0..<nD).map { disc(x: Float($0)) }
        XCTAssertLessThanOrEqual(cues.count, BattleWorkBudget.cuesPerPlay)
        player.play(cues, budgetContext("H900"))
        let s = player.budgetSnapshot()
        XCTAssertEqual(s.poolQuality, "low")
        XCTAssertEqual(s.emitters.pooled, nE)
        XCTAssertEqual(s.emitters.inUse, nE)
        XCTAssertEqual(s.emitters.counts, SkillFXPlayer.PoolStats(requests: nE, peakInUse: nE))
        XCTAssertEqual(s.meshShapes["disc"]?.pooled, nD)
        XCTAssertEqual(s.meshShapes["disc"]?.counts, SkillFXPlayer.PoolStats(requests: nD, peakInUse: nD))
        XCTAssertEqual(s.meshes.counts.cut + s.meshes.counts.rejected + s.meshes.counts.reclaimed, 0)
        XCTAssertEqual(s.cues.overPerPlay, 0)
        XCTAssertEqual(s.cues.overPending, 0)
        XCTAssertTrue(s.bySource.isEmpty, "何も失っていない")
        player.clear()
    }

    /// 空きが無いときは、従来どおり最も早く終わる一斉放出・同じ形の最も古いメッシュを打ち切り、打ち切った側に 1 回だけ数える。
    func testPoolOverflowCutsInTheExistingOrderAndCountsEachCutOnce() {
        let q = RenderQuality.preset(.low)
        let player = SkillFXPlayer(quality: q)
        player.prewarm(recipes: [])
        let nE = SkillFXPlayer.emitterCapacity(q)
        // x が大きいほど長生き: 最も早く終わるのは x = 0、次が x = 1
        player.play((0..<nE).map { burst(x: Float($0), life: 1 + 0.1 * Float($0)) }, budgetContext("H900"))
        let first = emitter(player, x: 0), second = emitter(player, x: 1)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        // 新しい 2 つは長生き（2 つ目の要求が 1 つ目の新しい演出を打ち切らない）
        player.play([burst(x: 100, life: 5), burst(x: 101, life: 5)], budgetContext("H901"))
        XCTAssertEqual(first?.position.x, 100, "最も早く終わる一斉放出を打ち切る")
        XCTAssertEqual(second?.position.x, 101)
        let s = player.budgetSnapshot()
        XCTAssertEqual(s.emitters.counts, SkillFXPlayer.PoolStats(requests: nE + 2, cut: 2, peakInUse: nE))
        XCTAssertEqual(s.emitters.inUse, nE)
        XCTAssertEqual(s.bySource["H900.skill1.0"]?.emitterCut, 2, "打ち切られた側の出所に数える")
        XCTAssertNil(s.bySource["H901.skill1.0"], "受理された側は何も失っていない")
        player.clear()

        let meshes = SkillFXPlayer(quality: q)
        meshes.prewarm(recipes: [])
        let nD = SkillFXPlayer.meshCapacity(.disc, q)
        for k in 0..<nD {
            meshes.play([disc(x: Float(k))], budgetContext("H900"))
            meshes.update(dt: 0.01)
        }
        let oldest = mesh(meshes, x: 0)
        XCTAssertNotNil(oldest)
        meshes.play([disc(x: 100)], budgetContext("H901"))
        XCTAssertEqual(oldest?.position.x, 100, "同じ形の最も古いものを打ち切る")
        let m = meshes.budgetSnapshot()
        XCTAssertEqual(m.meshShapes["disc"]?.counts, SkillFXPlayer.PoolStats(requests: nD + 1, cut: 1, peakInUse: nD))
        XCTAssertEqual(m.meshes.counts.cut, 1)
        XCTAssertEqual(m.meshes.inUse, nD)
        XCTAssertEqual(m.bySource["H900.skill1.0"]?.meshCut, 1)
        XCTAssertEqual(meshes.stats.stolenMeshes, 1)
        meshes.clear()
    }

    /// 打ち切れる一斉放出が無い（全て止まらない継続放出）ときは要求を捨て、打ち切りとは別に数える。
    func testRequestIsRejectedWhenOnlyLoopingEmittersAreLive() {
        let q = RenderQuality.preset(.low)
        let player = SkillFXPlayer(quality: q)
        player.prewarm(recipes: [])
        let nE = SkillFXPlayer.emitterCapacity(q)
        let loop = FXCue.emit(FXEmit(rate: 10, life: 0.5), .follow)
        player.play(Array(repeating: loop, count: nE), budgetContext("H900", follow: .unit(1)))
        player.play([burst(x: 0)], budgetContext("H901"))
        let s = player.budgetSnapshot()
        XCTAssertEqual(s.emitters.counts, SkillFXPlayer.PoolStats(requests: nE + 1, rejected: 1, peakInUse: nE))
        XCTAssertEqual(s.bySource["H901.skill1.0"]?.emitterRejected, 1, "要求した側の出所に数える")
        XCTAssertNil(s.bySource["H900.skill1.0"], "継続放出は打ち切っていない")
        player.clear()
    }

    /// 寿命を終えた枠の再利用（空きに戻った後・回収待ちの引き取り）は打ち切りに数えない。
    func testReusingFinishedSlotsIsNotCountedAsCut() {
        let q = RenderQuality.preset(.low)
        let player = SkillFXPlayer(quality: q)
        player.prewarm(recipes: [])
        let nE = SkillFXPlayer.emitterCapacity(q), nD = SkillFXPlayer.meshCapacity(.disc, q)
        let full = (0..<nE).map { burst(x: Float($0), life: 0.2) } + (0..<nD).map { disc(x: Float($0), life: 0.2) }
        player.play(full, budgetContext("H900"))
        player.update(dt: 1)
        XCTAssertEqual(player.activeCount, 0, "寿命を終えて空きに戻った")
        player.play(full, budgetContext("H900"))
        var s = player.budgetSnapshot()
        XCTAssertEqual(s.emitters.counts, SkillFXPlayer.PoolStats(requests: 2 * nE, peakInUse: nE))
        XCTAssertEqual(s.meshShapes["disc"]?.counts, SkillFXPlayer.PoolStats(requests: 2 * nD, peakInUse: nD))
        player.update(dt: 1)
        // 予定の合図は同じ update の回収より先に出るので、寿命を過ぎて回収待ちの枠を引き取る（正常終了。打ち切りではない）
        player.play(full + [burst(x: 50, life: 0.2, at: 0.5), disc(x: 50, life: 0.2, at: 0.5)], budgetContext("H900"))
        player.update(dt: 1)
        s = player.budgetSnapshot()
        XCTAssertEqual(s.emitters.counts.cut, 0)
        XCTAssertEqual(s.emitters.counts.reclaimed, 1)
        XCTAssertEqual(s.meshShapes["disc"]?.counts.cut, 0)
        XCTAssertEqual(s.meshShapes["disc"]?.counts.reclaimed, 1)
        XCTAssertTrue(s.bySource.isEmpty)
        player.clear()
    }

    /// 1 回の再生の上限（64）と遅延予約の上限（512）の破棄を別々に数える。受け付ける順は従来どおり先頭から。
    func testPerPlayAndPendingDropsAreCountedSeparately() {
        let player = SkillFXPlayer(quality: .preset(.high))
        let per = BattleWorkBudget.cuesPerPlay
        var strengths: [Float] = []
        player.onShake = { s, _ in strengths.append(s) }
        player.play((0..<(per + 6)).map { FXCue.shake(Float($0) / 1000) }, budgetContext("H900"))
        XCTAssertEqual(strengths, (0..<per).map { Float($0) / 1000 }, "先頭から 64 個を受け付ける")
        // 繰り返しは 1 回ずつ数える。この画質で出さない合図は数えない
        var repeated = FXCue.shake(0.5)
        repeated.count = per + 10
        var never = FXCue.shake(0.5)
        never.minQuality = 3
        player.play([repeated, never], budgetContext("H900"))
        var s = player.budgetSnapshot()
        XCTAssertEqual(s.cues.overPerPlay, 6 + 10)
        XCTAssertEqual(s.cues.overPending, 0)
        // 遅れのある合図で予約を埋めると、その先は予約の上限で捨てる（1 回の再生の上限には当たらない）
        let delayed = (0..<per).map { _ in FXCue.shake(0.1, at: 1) }
        let plays = BattleWorkBudget.pendingCues / per + 1
        for _ in 0..<plays { player.play(delayed, budgetContext("H901")) }
        s = player.budgetSnapshot()
        XCTAssertEqual(s.cues.overPerPlay, 16)
        XCTAssertEqual(s.cues.overPending, plays * per - BattleWorkBudget.pendingCues)
        XCTAssertEqual(s.cues.pending, BattleWorkBudget.pendingCues)
        XCTAssertEqual(s.cues.peakPending, BattleWorkBudget.pendingCues)
        XCTAssertEqual(s.bySource["H900.skill1.0"], SkillFXPlayer.SourceStats(cuesOverPerPlay: 16))
        XCTAssertEqual(s.bySource["H901.skill1.0"],
                       SkillFXPlayer.SourceStats(cuesOverPending: plays * per - BattleWorkBudget.pendingCues))
        player.update(dt: 2)
        s = player.budgetSnapshot()
        XCTAssertEqual(s.cues.pending, 0, "予約は出し切った")
        XCTAssertEqual(s.cues.overPending, plays * per - BattleWorkBudget.pendingCues, "出し切っても破棄の数は残る")
        player.clear()
    }

    /// 読み込み幕の裏の陳列は要求に数えない。clear（幕が上がる直前・シーク・破棄）と新しい試合の再生器で前の集計は残らない。
    func testBudgetCountersExcludeWarmupAndResetOnClear() {
        let q = RenderQuality.preset(.low)
        let player = SkillFXPlayer(quality: q)
        player.prewarm(recipes: [])
        player.fireWarmup(around: .zero, spread: 4)
        XCTAssertEqual(player.budgetSnapshot().emitters.counts.requests, 0)
        XCTAssertEqual(player.budgetSnapshot().meshes.counts.requests, 0)
        player.clear()
        let nE = SkillFXPlayer.emitterCapacity(q)
        player.play((0..<(nE + 3)).map { burst(x: Float($0)) }, budgetContext("H900"))
        player.play((0..<(BattleWorkBudget.cuesPerPlay + 1)).map { _ in FXCue.shake(0.1) }, budgetContext("H900"))
        player.play([FXCue.shake(0.1, at: 1)], budgetContext("H900"))
        var s = player.budgetSnapshot()
        XCTAssertEqual(s.emitters.counts.cut, 3)
        XCTAssertEqual(s.cues.overPerPlay, 1)
        XCTAssertEqual(s.cues.pending, 1)
        player.clear()
        s = player.budgetSnapshot()
        XCTAssertEqual(s.plays, 0)
        XCTAssertEqual(s.emitters.counts, SkillFXPlayer.PoolStats())
        XCTAssertEqual(s.meshes.counts, SkillFXPlayer.PoolStats())
        XCTAssertEqual(s.emitters.inUse, 0)
        XCTAssertEqual(s.emitters.pooled, nE, "枠は残る（作り直さない）")
        XCTAssertEqual(s.cues, SkillFXBudgetSnapshot.Cues(perPlayLimit: BattleWorkBudget.cuesPerPlay,
                                                           pendingLimit: BattleWorkBudget.pendingCues,
                                                           overPerPlay: 0, overPending: 0, pending: 0, peakPending: 0))
        XCTAssertTrue(s.bySource.isEmpty)
        let next = SkillFXPlayer(quality: q)
        XCTAssertEqual(next.budgetSnapshot().emitters.counts, SkillFXPlayer.PoolStats(), "次の試合の再生器は 0 から")
    }

    /// 出所の無い合図は "unknown"。写しは JSON（性能記録）へ書き出して読み戻せる。
    func testBudgetSnapshotNamesUnknownSourceAndRoundTripsJSON() throws {
        let player = SkillFXPlayer(quality: .preset(.low))
        let ctx = SkillFXPlayer.Context(palette: .from(RGB(1, 1, 1)), origin: .zero, caster: .zero, target: .zero,
                                        forward: [0, 0, -1])
        player.play((0..<(BattleWorkBudget.cuesPerPlay + 2)).map { _ in FXCue.shake(0.1) }, ctx)
        let s = player.budgetSnapshot()
        XCTAssertEqual(s.bySource["unknown"]?.cuesOverPerPlay, 2)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(SkillFXBudgetSnapshot.self, from: data), s)
    }

    // MARK: 加算合成・流れる模様・コマ送り（FXPrograms・FXShaders.metal・FXSheet）

    private func recipe(_ cues: [FXCue]) -> (palette: FXPalette, recipe: SkillFXRecipe) {
        var r = SkillFXRecipe()
        r.cast = cues
        return (FXPalette.from(RGB(1, 0.6, 0.2)), r)
    }

    private func context(_ palette: FXPalette) -> SkillFXPlayer.Context {
        SkillFXPlayer.Context(palette: palette, origin: .zero, caster: .zero, target: [0, 0, -1], forward: [0, 0, -1])
    }

    func testMeshDefaultsStayAlphaBlendedWithTheLegacyMaterial() {
        let m = FXMesh(shape: .disc)
        XCTAssertEqual(m.blend, .alpha)
        XCTAssertNil(m.flow)
        XCTAssertNil(FXMaterialLibrary.shadedKey(m, palette: .from(RGB(1, 1, 1)), level: 3), "既定は従来の Unlit")
        let player = SkillFXPlayer(quality: .preset(.high))
        let r = recipe([.mesh(FXMesh(shape: .disc, tex: .ring, life: 1), offset: [7, 0, 0])])
        player.prewarm(recipes: [r])
        player.play(r.recipe.cast, context(r.palette))
        let e = mesh(player, x: 7) as? ModelEntity
        XCTAssertTrue(e?.model?.materials.first is UnlitMaterial)
        player.clear()
    }

    func testAddLevelsCoverTheFadeAndHideAtZero() {
        XCTAssertEqual(FXMaterialLibrary.addLevel(0), 0)
        XCTAssertEqual(FXMaterialLibrary.addLevel(1), FXMaterialLibrary.addLevels)
        XCTAssertEqual(FXMaterialLibrary.addLevel(0.01), 1)
        XCTAssertEqual(FXMaterialLibrary.addLevel(0.55), 6)
        XCTAssertEqual(FXMaterialLibrary.addLevel(5), FXMaterialLibrary.addLevels)
    }

    /// 演出用シェーダーの Program がアプリの default.metallib から作れる（シミュレータでも）。
    func testFXProgramsCompile() async {
        await FXPrograms.waitUntilSettled()
        XCTAssertTrue(FXPrograms.isReady, "FXShaders.metal の Program が作れない: \(FXPrograms.failure ?? "?")")
    }

    /// 加算のメッシュは明るさの段階の材質で落とし、枠を使い回した次のアルファ合成のメッシュには従来の材質と不透明度が戻る。
    /// 加算・模様の材質も読み込み幕の裏で作り切る（プレイ中は何も作らない）。
    func testAdditiveMeshFadesByLevelAndPoolReuseResetsTheMaterial() async {
        await FXPrograms.waitUntilSettled()
        guard FXPrograms.isReady else { return XCTFail("Program が無い: \(FXPrograms.failure ?? "?")") }
        AssetLedger.beginLoading()
        let player = SkillFXPlayer(quality: .preset(.low))
        let glow = FXMesh(shape: .disc, tex: .shockwave, life: 1, fadeIn: 0.01, fadeOut: 0.3).with { $0.blend = .add }
        let flowing = FXMesh(shape: .cylinder, tex: .beam, life: 1).with {
            $0.flow = FXFlow(pattern: .streaks, scroll: [0, -1.5], tiling: 2, strength: 0.8, erosion: 0.3, edge: .core)
        }
        let plain = FXMesh(shape: .disc, tex: .ring, life: 1, fadeIn: 0.01, fadeOut: 0.3)
        let r = recipe([.mesh(glow, offset: [3, 0, 0]), .mesh(flowing, offset: [4, 0, 0]), .mesh(plain, offset: [5, 0, 0])])
        player.prewarm(recipes: [r])
        AssetLedger.beginLive()
        player.play([r.recipe.cast[0]], context(r.palette))
        let e = mesh(player, x: 3) as? ModelEntity
        XCTAssertTrue(e?.model?.materials.first is CustomMaterial, "加算は CustomMaterial")
        let full = (e?.model?.materials.first as? CustomMaterial)?.roughness.scale
        XCTAssertEqual(full ?? 0, 1, accuracy: 1e-4)
        player.update(dt: 0.65)
        let dim = (e?.model?.materials.first as? CustomMaterial)?.roughness.scale ?? 1
        XCTAssertLessThan(dim, 1, "消え始めたら明るさの段階を落とす")
        XCTAssertEqual(e?.components[OpacityComponent.self]?.opacity ?? 0, 1, accuracy: 1e-4, "加算は段階で落とし、不透明度は 1")
        player.play([r.recipe.cast[1]], context(r.palette))
        XCTAssertTrue((mesh(player, x: 4) as? ModelEntity)?.model?.materials.first is CustomMaterial, "模様は CustomMaterial")
        player.update(dt: 1)
        XCTAssertEqual(player.activeCount, 0)
        // 加算に使った枠（円板）を次のアルファ合成の円板が使い回す
        player.play([r.recipe.cast[2]], context(r.palette))
        let reused = mesh(player, x: 5) as? ModelEntity
        XCTAssertTrue(reused?.model?.materials.first is UnlitMaterial, "使い回しで従来の材質に戻る")
        XCTAssertTrue(reused === e, "同じ枠を使い回している")
        player.update(dt: 0.85)
        let a = reused?.components[OpacityComponent.self]?.opacity ?? 1
        XCTAssertLessThan(a, 1, "アルファ合成は不透明度で落とす")
        XCTAssertGreaterThan(a, 0)
        player.clear()
        let snap = AssetLedger.snapshot()
        XCTAssertEqual(snap.liveTotal, 0, "プレイ中の生成: \(snap.live)\n" + snap.liveSamples.joined(separator: "\n"))
    }

    /// Program が幕に間に合わなかった試合（sealShadedMaterials → createsShaded = false）は、後で Program が出来ても
    /// プレイ中に CustomMaterial を作らず従来の材質で出し、加算のメッシュも不透明度で落とす。間に合えば封じない。
    func testLateProgramsKeepTheLegacyMaterialForTheMatch() async {
        await FXPrograms.waitUntilSettled()
        guard FXPrograms.isReady else { return XCTFail("Program が無い: \(FXPrograms.failure ?? "?")") }
        let glow = FXMesh(shape: .disc, tex: .shockwave, life: 1, fadeIn: 0.01, fadeOut: 0.3).with { $0.blend = .add }
        let r = recipe([.mesh(glow, offset: [3, 0, 0])])
        let ready = SkillFXPlayer(quality: .preset(.low))
        ready.prewarm(recipes: [r])
        XCTAssertTrue(ready.sealShadedMaterials(), "作り切れていれば封じない")
        XCTAssertTrue(ready.materials.createsShaded)

        AssetLedger.beginLoading()
        let player = SkillFXPlayer(quality: .preset(.low))
        // 幕の時点で Program が無かった試合と同じ状態（この試合は加算・模様の材質を作らない）
        player.materials.createsShaded = false
        player.prewarm(recipes: [r])
        AssetLedger.beginLive()
        player.play(r.recipe.cast, context(r.palette))
        let e = mesh(player, x: 3) as? ModelEntity
        XCTAssertTrue(e?.model?.materials.first is UnlitMaterial, "従来の材質で代える")
        player.update(dt: 0.65)
        let a = e?.components[OpacityComponent.self]?.opacity ?? 1
        XCTAssertLessThan(a, 1, "従来の材質の加算のメッシュは不透明度で落とす")
        XCTAssertGreaterThan(a, 0)
        player.clear()
        let snap = AssetLedger.snapshot()
        XCTAssertEqual(snap.liveTotal, 0, "プレイ中の生成: \(snap.live)\n" + snap.liveSamples.joined(separator: "\n"))
    }

    /// アルファ合成の粒子の画像は「色 = アルファ」の乗算していない画像（FXTextureLibrary.particleAlpha）。白 + アルファのままだと
    /// RealityKit が色を乗算済みとして重ねて粒子の四角い縁が見える（2026-10-17 実機のボルグ S2 の土煙）。全ての画像・シートで作れる。
    func testAlphaParticleImagesCarryTheAlphaInTheColour() {
        func check(_ name: String, _ img: CGImage?) {
            guard let img, let p = FXTextureLibrary.particleAlpha(img) else { return XCTFail("\(name) が作れない") }
            XCTAssertEqual(p.alphaInfo, .last, name)
            guard let data = p.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return XCTFail(name) }
            var maxDiff = 0, covered = 0
            for k in stride(from: 0, to: p.width * p.height * 4, by: 4) {
                let a = Int(bytes[k + 3])
                if a > 0 { covered += 1 }
                maxDiff = max(maxDiff, abs(Int(bytes[k]) - a), abs(Int(bytes[k + 1]) - a), abs(Int(bytes[k + 2]) - a))
            }
            XCTAssertGreaterThan(covered, 0, "\(name) が空")
            XCTAssertLessThanOrEqual(maxDiff, 1, "\(name): 色がアルファと違う（透明な所に色が残ると四角い縁が出る）")
        }
        for t in FXTex.allCases { check(t.rawValue, FXTextureLibrary.image(t)) }
        for s in FXSheet.allCases where !s.colored { check(s.rawValue, FXSheet.image(s)) }
        // 色付きのシート（Blender の爆炎・煙・岩）は色 × アルファ（乗算済みの色がアルファを超えない = 透明な所に色が残らない）
        for s in FXSheet.allCases where s.colored {
            guard let img = FXSheet.image(s), let p = FXTextureLibrary.particleAlpha(img),
                  let data = p.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { XCTFail(s.rawValue); continue }
            var over = 0, covered = 0
            for k in stride(from: 0, to: p.width * p.height * 4, by: 4) {
                let a = Int(bytes[k + 3])
                if a > 0 { covered += 1 }
                over = max(over, Int(bytes[k]) - a, Int(bytes[k + 1]) - a, Int(bytes[k + 2]) - a)
            }
            XCTAssertGreaterThan(covered, 0, "\(s.rawValue) が空")
            XCTAssertLessThanOrEqual(over, 1, "\(s.rawValue): 色がアルファを超える（乗算済みでない）")
        }
        let lib = FXTextureLibrary()
        XCTAssertNotNil(lib.particleTexture(.smoke), "粒子の画像から TextureResource が作れる")
        let sheets = FXSheetLibrary()
        sheets.prewarm(FXSheet.allCases)
        XCTAssertTrue(sheets.missing.isEmpty, "\(sheets.missing)")
    }

    /// シートの画像が宣言の格子（列 × 行 × 1 コマの画素）どおりに同梱されている（手続きは 4 × 4 × 128、Blender は 5 × 5・4 × 4 × 256 など）。
    func testEverySheetIsBundledAsItsDeclaredGrid() {
        for s in FXSheet.allCases {
            guard let img = FXSheet.image(s) else { XCTFail("\(s.rawValue).png が無い"); continue }
            XCTAssertEqual(img.width, s.columns * s.frameSize, s.rawValue)
            XCTAssertEqual(img.height, s.rows * s.frameSize, s.rawValue)
            XCTAssertEqual(s.frames, s.rows * s.columns)
            XCTAssertLessThanOrEqual(img.width, 2048, "\(s.rawValue): 2K を超える")
            if !s.rawValue.hasPrefix("fx_") { XCTAssertEqual(s.frames, 16, "手続きのシートは従来の 4 × 4") }
        }
    }

    func testSheetFPSFollowsLifeForOneShotAndLoopRateForLoops() {
        let once = FXEmit(life: 0.8).with { $0.sheet = .smokePuff }
        XCTAssertEqual(SkillFXPlayer.sheetFPS(once, .smokePuff), 20, accuracy: 1e-4, "16 コマを寿命 0.8 秒で流す")
        let loop = FXEmit(life: 0.8).with { $0.sheet = .flameLoop }
        XCTAssertEqual(SkillFXPlayer.sheetFPS(loop, .flameLoop), FXSheet.flameLoop.loopFPS)
        let fixed = FXEmit(life: 0.8).with { $0.sheet = .smokePuff; $0.sheetFPS = 12 }
        XCTAssertEqual(SkillFXPlayer.sheetFPS(fixed, .smokePuff), 12)
    }

    /// コマ送りの粒子は imageSequence を付け、同じ放出体を使い回した次の 1 枚絵の粒子では外す。シートは読み込み幕の裏で作る。
    func testSheetEmitterSetsImageSequenceAndReuseClearsIt() {
        AssetLedger.beginLoading()
        let player = SkillFXPlayer(quality: .preset(.low))
        let smoke = FXEmit(count: 4, life: 0.8).with { $0.sheet = .smokePuff; $0.additive = false }
        let r = recipe([.emit(smoke, offset: [6, 0, 0]), .emit(FXEmit(count: 4, life: 0.5), offset: [8, 0, 0])])
        player.prewarm(recipes: [r])
        XCTAssertFalse(player.sheets.missing.contains(.smokePuff), "シートが読めない")
        AssetLedger.beginLive()
        // 放出体を 1 つだけ空ける: 残りを全部使ってから、コマ送りの粒子を出す
        let n = SkillFXPlayer.emitterCapacity(.preset(.low))
        player.play((0..<(n - 1)).map { burst(x: 20 + Float($0), life: 5) }, context(r.palette))
        player.play([r.recipe.cast[0]], context(r.palette))
        let e = emitter(player, x: 6)
        let seq = e?.components[ParticleEmitterComponent.self]?.mainEmitter.imageSequence
        XCTAssertNotNil(seq)
        XCTAssertEqual(seq?.rowCount, 4)
        XCTAssertEqual(seq?.columnCount, 4)
        XCTAssertEqual(seq?.animationMode, .playOnce)
        XCTAssertEqual(seq?.frameRate ?? 0, 20, accuracy: 1e-4)
        player.update(dt: 1.2)
        // コマ送りの粒子の枠が空いた（ほかは寿命 5 秒）→ 次の 1 枚絵の粒子が同じ放出体を使う
        player.play([r.recipe.cast[1]], context(r.palette))
        let plain = emitter(player, x: 8)
        XCTAssertTrue(plain === e, "同じ放出体を使い回している")
        XCTAssertNil(plain?.components[ParticleEmitterComponent.self]?.mainEmitter.imageSequence, "使い回しでコマ送りを外す")
        player.clear()
        let snap = AssetLedger.snapshot()
        XCTAssertEqual(snap.liveTotal, 0, "プレイ中の生成: \(snap.live)\n" + snap.liveSamples.joined(separator: "\n"))
    }

    func testFlowPatternsAreSeamlessTiles() {
        for p in FXFlowTex.allCases {
            guard let img = FXFlowTex.image(p) else { XCTFail("\(p) が作れない"); continue }
            XCTAssertEqual(img.width, p.imageSize, "\(p)")
            XCTAssertEqual(img.height, p.imageSize, "\(p)")
        }
    }

    /// Program があっても無くても、全ヒーローの全レシピを準備してから再生してプレイ中に何も作らない（加算・模様・シートを含む）。
    func testPlayingEveryRecipeWithShadersCreatesNothingWhileLive() async {
        await FXPrograms.waitUntilSettled()
        AssetLedger.beginLoading()
        let player = SkillFXPlayer(quality: .preset(.high))
        var all: [(palette: FXPalette, recipe: SkillFXRecipe)] = []
        for id in heroIDs {
            for slot in SkillSlot.allCases {
                all.append((SkillFXCatalog.palette(id), SkillFXCatalog.recipe(heroID: id, slot: slot, master: master)))
                for stage in 1...SkillFXCatalog.maxStage {
                    if let sr = SkillFXCatalog.stageRecipe(heroID: id, slot: slot, stage: stage, master: master) {
                        all.append((SkillFXCatalog.palette(id), sr))
                    }
                }
            }
        }
        player.prewarm(recipes: all)
        XCTAssertTrue(player.prewarmShaded())
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
        if FXPrograms.isReady { XCTAssertEqual(player.materials.fallbacks, 0, "Program があるのに従来の材質で代えた") }
        XCTAssertTrue(player.sheets.missing.isEmpty, "読めないシート: \(player.sheets.missing)")
    }

    // MARK: Blender の素材（tools/vfx_assets）・模型・コマ送りのメッシュ・溶け・帯

    /// Blender の模型（fxm_<名前>.bin）が全て同梱され、読めて、単位の大きさに収まる。壊れた中身は読まない。
    func testBlenderModelsAreBundledAndParse() {
        for s in FXShape.allCases where s.isModel {
            guard let g = FXModelFile.load(s) else { XCTFail("\(s.rawValue) の模型が読めない"); continue }
            XCTAssertGreaterThan(g.positions.count, 3, s.rawValue)
            XCTAssertEqual(g.indices.count % 3, 0, s.rawValue)
            XCTAssertLessThanOrEqual(g.indices.count / 3, 4000, "\(s.rawValue): 三角形が多すぎる")
            XCTAssertTrue(g.indices.allSatisfy { Int($0) < g.positions.count }, s.rawValue)
            for p in [g.boundsMin, g.boundsMax] {
                XCTAssertLessThanOrEqual(simd_reduce_max(simd_abs(p)), 1.8, "\(s.rawValue): 単位の大きさを超える")
            }
        }
        XCTAssertNil(FXModelFile.parse(Data([0x46, 0x58, 0x4D, 0x31, 1, 2, 3])), "短い中身は読まない")
    }

    /// 模型の形は、試合のレシピが使うものだけプールする（使わない模型は作らない）。
    func testModelShapesArePooledOnlyWhenARecipeUsesThem() {
        let q = RenderQuality.preset(.low)
        let none = SkillFXPlayer(quality: q)
        none.prewarm(recipes: [])
        XCTAssertEqual(none.budgetSnapshot().meshShapes["crescent"]?.pooled, 0)
        let used = SkillFXPlayer(quality: q)
        used.prewarm(recipes: [recipe([.mesh(.model(.crescent, .swoosh, size: [2, 1, 2]))])])
        XCTAssertEqual(used.budgetSnapshot().meshShapes["crescent"]?.pooled, SkillFXPlayer.meshCapacity(.crescent, q))
        XCTAssertEqual(used.budgetSnapshot().meshShapes["twister"]?.pooled, 0)
    }

    /// コマ送り・溶けのメッシュは 1 体ごとの値を頂点の色へ書く（コマは寿命で進み、溶けは from から増える）。
    /// 枠を使い回した次のメッシュでは既定値に戻る。材質は読み込み幕の裏で作り切る。
    func testSheetAndDissolveMeshWriteVertexParams() async {
        await FXPrograms.waitUntilSettled()
        AssetLedger.beginLoading()
        let player = SkillFXPlayer(quality: .preset(.low))
        let flip = FXMesh.groundFlipbook(.fireball, 3, life: 1).dissolving(from: 0.5)
        let plain = FXMesh(shape: .disc, tex: .ring, life: 1)
        let r = recipe([.mesh(flip, offset: [3, 0, 0]), .mesh(plain, offset: [4, 0, 0])])
        player.prewarm(recipes: [r])
        XCTAssertTrue(player.prewarmShaded())
        AssetLedger.beginLive()
        player.play([r.recipe.cast[0]], context(r.palette))
        guard let e = mesh(player, x: 3) else { return XCTFail("出ていない") }
        player.update(dt: 0.02)
        let early = player.meshParams(e)
        XCTAssertEqual(early?.z, 0, "溶け始め（寿命の 0.5）の前は 0")
        player.update(dt: 0.6)
        let late = player.meshParams(e)
        XCTAssertGreaterThan(late?.y ?? 0, early?.y ?? 0, "コマが進む")
        XCTAssertLessThan(Int(late?.y ?? 99), FXSheet.fireball.frames)
        XCTAssertGreaterThan(late?.z ?? 0, 0, "溶けが進む")
        if FXPrograms.isReady {
            XCTAssertTrue((e as? ModelEntity)?.model?.materials.first is CustomMaterial, "コマ送りは CustomMaterial")
        }
        player.update(dt: 1)
        XCTAssertEqual(player.activeCount, 0)
        player.play([r.recipe.cast[1]], context(r.palette))
        guard let reused = mesh(player, x: 4) else { return XCTFail("出ていない") }
        XCTAssertTrue(reused === e, "同じ枠を使い回す")
        XCTAssertEqual(player.meshParams(reused), FXMeshSlot.rest, "使い回しでコマ・溶けを戻す")
        player.clear()
        let snap = AssetLedger.snapshot()
        XCTAssertEqual(snap.liveTotal, 0, "プレイ中の生成: \(snap.live)\n" + snap.liveSamples.joined(separator: "\n"))
    }

    func testSheetFrameFollowsLifeAndLoops() {
        let once = FXMesh.flipbook(.fireball, 2, life: 1)
        XCTAssertEqual(SkillFXPlayer.sheetFrame(once, .fireball, age: 0), 0)
        XCTAssertEqual(SkillFXPlayer.sheetFrame(once, .fireball, age: 0.5), 12)
        XCTAssertEqual(SkillFXPlayer.sheetFrame(once, .fireball, age: 5), FXSheet.fireball.frames - 1, "1 回の画像は最後のコマで止まる")
        let loop = FXMesh.flipbook(.rockTumble, 1, life: 3)
        let n = FXSheet.rockTumble.frames
        let f = SkillFXPlayer.sheetFrame(loop, .rockTumble, age: 2)
        XCTAssertEqual(f, Int(2 * FXSheet.rockTumble.loopFPS) % n, "繰り返す画像は loopFPS で回る")
        XCTAssertEqual(SkillFXPlayer.dissolveAmount(FXDissolve(from: 0.5), t: 0.25), 0)
        XCTAssertEqual(SkillFXPlayer.dissolveAmount(FXDissolve(from: 0.5), t: 0.75), 0.5, accuracy: 1e-5)
        XCTAssertEqual(SkillFXPlayer.dissolveAmount(FXDissolve(from: 0.5), t: 1), 1, accuracy: 1e-5)
    }

    /// 弧の帯は頭が弧を掃き、外縁が半径・高さの上に乗る。寿命の後はプールへ戻る（プレイ中に何も作らない）。
    func testArcRibbonSweepsTheArcAndReturnsToThePool() {
        AssetLedger.beginLoading()
        let player = SkillFXPlayer(quality: .preset(.low))
        let swing = FXRibbon.swing(radius: 2, from: 80, to: -80, height: 1, duration: 0.2, life: 0.2, width: 0.5)
        let r = recipe([.ribbon(swing)])
        player.prewarm(recipes: [r])
        AssetLedger.beginLive()
        player.play(r.recipe.cast, context(r.palette))
        for _ in 0..<6 { player.update(dt: 1.0 / 30) }
        let v = player.ribbonVertices()
        XCTAssertEqual(v.count, 1)
        for c in v.first ?? [] {
            XCTAssertEqual(simd_length(SIMD2<Float>(c.outer.x, c.outer.z)), 2, accuracy: 0.02, "外縁は半径 2 の弧")
            XCTAssertEqual(c.outer.y, 1, accuracy: 0.02, "高さ 1 の水平の弧")
            XCTAssertLessThan(simd_length(SIMD2<Float>(c.inner.x, c.inner.z)), 1.95, "内縁は内側")
        }
        XCTAssertEqual(v.first?.first?.u ?? 1, 0, accuracy: 1e-3, "列 0 は頭（古さ 0）")
        for _ in 0..<30 { player.update(dt: 1.0 / 30) }
        XCTAssertEqual(player.activeCount, 0, "寿命の後はプールへ戻る")
        player.clear()
        let snap = AssetLedger.snapshot()
        XCTAssertEqual(snap.liveTotal, 0, "プレイ中の生成: \(snap.live)\n" + snap.liveSamples.joined(separator: "\n"))
    }

    /// 帯を使うレシピが無い試合は帯の枠を作らない（要求は捨てる）。枠が尽きたら最も古い帯を打ち切る（作らない）。
    func testRibbonPoolIsMadeOnlyForRecipesWithRibbonsAndNeverGrows() {
        let q = RenderQuality.preset(.low)
        let trail = FXRibbon.trail(width: 1, life: 0.3, duration: 0.5)
        let none = SkillFXPlayer(quality: q)
        none.prewarm(recipes: [])
        none.play([.ribbon(trail)], context(.from(RGB(1, 1, 1))))
        XCTAssertEqual(none.stats.ribbons.rejected, 1)
        XCTAssertEqual(none.activeCount, 0)
        let player = SkillFXPlayer(quality: q)
        player.prewarm(recipes: [recipe([.ribbon(trail)])])
        let n = SkillFXPlayer.ribbonCapacity(q)
        player.play(Array(repeating: FXCue.ribbon(trail), count: n + 1), context(.from(RGB(1, 1, 1))))
        XCTAssertEqual(player.stats.ribbons.cut, 1)
        XCTAssertEqual(player.activeCount, n)
        player.clear()
        XCTAssertEqual(player.activeCount, 0)
    }
}
