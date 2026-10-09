import XCTest
@testable import VELSTRIA
import VelstriaCore

// 担当: battle-hud。キット層（ヒーロー固有スキル。docs/SKILL_KITS.md）の HUD 表示値・照準の形の単体テスト。

@MainActor
final class HUDKitTests: XCTestCase {
    private let master = MasterData.shared

    // MARK: スナップショット

    /// 再使用の窓が開いている間は CD・コストを見ずに撃てる（sim の validate と同じ）。窓が閉じたら通常どおり。
    func testRecastWindowMakesTheSkillReadyIgnoringCooldownAndCost() {
        var sn = HUDSkillSnapshot(slot: .skill2)
        sn.rank = 1
        sn.castable = true
        sn.affordable = false
        sn.cooldown = 8
        XCTAssertFalse(sn.isReady, "CD 中・リソース不足は撃てない")
        sn.recast = RecastInfo(stage: 1, remaining: 3, total: 4, charges: 1)
        XCTAssertTrue(sn.recasting)
        XCTAssertTrue(sn.isReady, "再使用の窓が開いていれば CD・コストは無視")
        sn.castable = false
        XCTAssertFalse(sn.isReady, "スタン・沈黙などで撃てないときは再使用もできない")
        sn.castable = true
        sn.rank = 0
        XCTAssertFalse(sn.isReady, "未習得は撃てない")
        sn.rank = 1
        sn.recast = nil
        XCTAssertFalse(sn.isReady)
        sn.cooldown = 0
        sn.affordable = true
        XCTAssertTrue(sn.isReady)
    }

    func testKitDisplayRoundsRemainingTimeUpToTenths() {
        XCTAssertNil(HUDKitDisplay.rounded(nil as RecastInfo?))
        XCTAssertNil(HUDKitDisplay.rounded(nil as KitBadge?))
        let r = HUDKitDisplay.rounded(RecastInfo(stage: 2, remaining: 3.04, total: 4, charges: 1))
        XCTAssertEqual(r?.remaining ?? 0, 3.1, accuracy: 1e-9)
        XCTAssertEqual(r?.stage, 2)
        XCTAssertEqual(r?.charges, 1)
        let b = HUDKitDisplay.rounded(KitBadge(kind: .timer, remaining: 0.01, total: 4))
        XCTAssertEqual(b?.remaining ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertEqual(HUDKitDisplay.rounded(KitBadge(kind: .timer, remaining: -1, total: 4))?.remaining, 0)
    }

    func testBadgeFractionTextAndVisibility() {
        let stacks = KitBadge(kind: .stacks, value: 3, maxValue: 5)
        XCTAssertEqual(HUDKitDisplay.fraction(stacks), 0.6, accuracy: 1e-9)
        XCTAssertEqual(HUDKitDisplay.text(stacks), "3")
        XCTAssertTrue(HUDKitDisplay.isVisible(stacks))
        XCTAssertFalse(HUDKitDisplay.isVisible(KitBadge(kind: .stacks, value: 0, maxValue: 5)), "0 個のスタックは出さない")
        // 上限 1 の「準備できた」は輪だけ（数字なし）
        let ready = KitBadge(kind: .stacks, value: 1, maxValue: 1)
        XCTAssertEqual(HUDKitDisplay.text(ready), "")
        XCTAssertEqual(HUDKitDisplay.fraction(ready), 1, accuracy: 1e-9)
        let timer = KitBadge(kind: .timer, remaining: 2.5, total: 10)
        XCTAssertEqual(HUDKitDisplay.fraction(timer), 0.25, accuracy: 1e-9)
        XCTAssertEqual(HUDKitDisplay.text(timer), "2.5")
        XCTAssertEqual(HUDKitDisplay.text(KitBadge(kind: .timer, remaining: 7.4, total: 10)), "7")
        XCTAssertEqual(HUDKitDisplay.text(KitBadge(kind: .timer, remaining: 0, total: 10)), "")
        XCTAssertFalse(HUDKitDisplay.isVisible(KitBadge(kind: .timer, remaining: 0, total: 10)))
        XCTAssertEqual(HUDKitDisplay.fraction(KitBadge(kind: .timer, remaining: 5, total: 0)), 0, "全体が 0 でも壊れない")
        XCTAssertEqual(HUDKitDisplay.fraction(KitBadge(kind: .stacks, value: 2, maxValue: 0)), 0)
        let form = KitBadge(kind: .form, value: 1, maxValue: 1)
        XCTAssertEqual(HUDKitDisplay.fraction(form), 1)
        XCTAssertEqual(HUDKitDisplay.text(form), "")
        XCTAssertEqual(HUDKitDisplay.text(KitBadge(kind: .form, value: 2, maxValue: 3)), "2")
    }

    // MARK: ビルダー

    /// 再使用の窓が開くと、スナップショットは窓・その段の照準・撃てる状態になる（H029 ボルグ: S2 の 2 段目は扇）。
    func testBuildHeroPanelReflectsRecastWindowAndStageTargeting() throws {
        try XCTSkipUnless(HeroKits.hasKit("H029"), "H029 のキットが有効でない")
        let sim = Simulation(config: MatchFactory.standardMatch(humanHeroID: "H029", humanName: "T", seed: 7))
        var s = sim.state
        let hi = try XCTUnwrap(s.units.firstIndex { $0.hero?.heroID == "H029" })
        s.units[hi].hero?.skillRanks[SkillSlot.skill2.rawValue] = 1
        s.units[hi].hero?.skillCooldowns[SkillSlot.skill2.rawValue] = 7
        let k = SkillSlot.skill2.rawValue
        XCTAssertNotNil(s.units[hi].hero?.kit)

        let before = try XCTUnwrap(HUDModel.buildHeroPanel(s, sim.ctx, index: hi))
        let b = try XCTUnwrap(before.skills.first { $0.slot == .skill2 })
        XCTAssertNil(b.recast)
        XCTAssertGreaterThan(b.cooldown, 0)
        XCTAssertFalse(b.isReady, "CD 中")
        XCTAssertEqual(b.targeting.shape, .dashToPoint, "1 段目は突進")
        XCTAssertNil(before.hero.passiveBadge, "0 スタックのバッジは出さない")

        var w = RecastWindow()
        w.stage = 1
        w.remaining = 3.04
        w.total = 4
        w.charges = 1
        s.units[hi].hero?.kit?.windows[k] = w
        let after = try XCTUnwrap(HUDModel.buildHeroPanel(s, sim.ctx, index: hi))
        let a = try XCTUnwrap(after.skills.first { $0.slot == .skill2 })
        XCTAssertEqual(a.recast?.stage, 1)
        XCTAssertEqual(a.recast?.remaining ?? 0, 3.1, accuracy: 1e-9)
        XCTAssertEqual(a.recast?.total, 4)
        XCTAssertEqual(a.targeting.shape, .fan, "2 段目はその段の照準（扇）")
        XCTAssertGreaterThan(a.targeting.halfAngle, 0)
        XCTAssertGreaterThan(a.cooldown, 0, "CD は進んでいる")
        XCTAssertTrue(a.castable, "窓が開いていれば CD・コストなしで撃てる（sim の validate）")
        XCTAssertTrue(a.isReady)
        // 他のスロットは窓なし
        XCTAssertNil(after.skills.first { $0.slot == .skill1 }?.recast)
    }

    // MARK: 照準の形

    private func plan(_ aim: AimType, _ shape: AimShape, halfAngle: Double = 0, radius: Double = 200) -> AimShapePlan {
        AimShapePlan.make(SkillTargeting(archetype: .groundAoE, aim: aim, range: 600, radius: radius, shape: shape,
                                         halfAngle: halfAngle))
    }

    func testAutoShapeFallsThroughToTheArchetypeLogic() {
        for aim in [AimType.none, .direction, .point, .unit] {
            XCTAssertEqual(plan(aim, .auto), .legacy)
        }
    }

    func testShapePlanBranchesOnShapeFirst() {
        XCTAssertEqual(plan(.direction, .fan, halfAngle: 0.5), .fan(halfAngle: 0.5))
        XCTAssertEqual(plan(.direction, .fan, halfAngle: 9), .fan(halfAngle: Float(Double.pi)), "半角は π まで")
        XCTAssertEqual(plan(.direction, .wideLine, radius: 300), .band(halfWidth: 3))
        XCTAssertEqual(plan(.direction, .wideLine, radius: 10), .band(halfWidth: 0.3), "細すぎる線は最小の半幅")
        XCTAssertEqual(plan(.direction, .dashToPoint, radius: 150), .dash(halfWidth: 1.5))
        XCTAssertEqual(plan(.point, .circleAtPoint, radius: 350), .circleAtPoint(radius: 3.5))
        XCTAssertEqual(plan(.none, .selfRing, radius: 400), .selfRing(radius: 4))
        XCTAssertEqual(plan(.unit, .lockOn), .lockOn)
    }

    /// shape と aim が合わない・扇の角度が無いときは従来の分岐に戻す（壊れた組み合わせでも照準が消えない）。
    func testShapePlanFallsBackWhenShapeAndAimDisagree() {
        XCTAssertEqual(plan(.direction, .fan, halfAngle: 0), .legacy)
        XCTAssertEqual(plan(.point, .fan, halfAngle: 0.5), .legacy)
        XCTAssertEqual(plan(.point, .wideLine), .legacy)
        XCTAssertEqual(plan(.none, .dashToPoint), .legacy)
        XCTAssertEqual(plan(.direction, .circleAtPoint), .legacy)
        XCTAssertEqual(plan(.direction, .selfRing), .legacy)
        XCTAssertEqual(plan(.point, .lockOn), .legacy)
    }

    /// 実際のキットが設定する shape は、全スロット・全段で aim と合い、計画（.legacy 以外）になる。
    func testEveryRealKitShapeResolvesToAPlan() throws {
        let kitHeroes = master.heroes.filter { HeroKits.hasKit($0.heroID) }
        try XCTSkipIf(kitHeroes.isEmpty, "有効なキットが無い")
        for hero in kitHeroes {
            for slot in SkillSlot.actives {
                let skill = try XCTUnwrap(master.skill(hero: hero.heroID, slot: slot))
                for stage in 0...3 {
                    let t = HeroKits.targeting(for: skill, hero: hero, stage: stage)
                    let p = AimShapePlan.make(t)
                    let label = "\(hero.heroID) \(slot) stage \(stage): shape \(t.shape) aim \(t.aim)"
                    if t.shape == .auto {
                        XCTAssertEqual(p, .legacy, label)
                    } else {
                        XCTAssertNotEqual(p, .legacy, "\(label) が従来の分岐へ落ちる（aim か halfAngle が合わない）")
                    }
                }
            }
        }
    }

    /// 対象指定（lockOn）は aim .unit のまま: 指を離したときに照準点に最も近い敵ヒーローを送る。
    func testLockOnCastTargetStaysAUnit() {
        let lockOn = SkillTargeting(archetype: .targetedBlink, aim: .unit, range: 700, radius: 150, shape: .lockOn,
                                    requiresTarget: true)
        XCTAssertEqual(AimShapePlan.make(lockOn), .lockOn)
        let sim = Simulation(config: MatchFactory.standardMatch(humanHeroID: "H003", humanName: "T", seed: 7))
        var s = sim.state
        let reds = s.heroIndices(team: .red)
        XCTAssertGreaterThanOrEqual(reds.count, 2)
        s.units[reds[0]].pos = Vec2(5000, 5000)
        s.units[reds[1]].pos = Vec2(5400, 5000)
        for i in reds { s.units[i].visibleMask = Team.blue.visionBit | Team.red.visionBit }
        let origin = Vec2(4800, 4800)
        let target = HUDAim.castTarget(targeting: lockOn, origin: origin, aimPoint: Vec2(5350, 5000), drag: .zero, facing: 0,
                                       state: s, team: .blue, casterID: nil)
        XCTAssertEqual(target, .unit(s.units[reds[1]].id))
        // 敵が居なければ .none（sim の自動選択 / requiresTarget の拒否に任せる）
        for i in reds { s.units[i].visibleMask = Team.red.visionBit }
        XCTAssertEqual(HUDAim.castTarget(targeting: lockOn, origin: origin, aimPoint: Vec2(5350, 5000), drag: .zero, facing: 0,
                                         state: s, team: .blue, casterID: nil), .none)
    }

    // MARK: キット層の状態の見え方（タグ → 表示）

    private func bareUnit(team: Team = .blue) -> VelstriaCore.Unit {
        VelstriaCore.Unit(id: 1, kind: .hero, team: team, pos: .zero, radius: 55, stats: Stats())
    }

    /// KitTags.mark の書式 "kit.<ヒーロー>.<名前>.<所有者>" を読む。キットの tag でなければ nil。
    func testParseMarkTag() {
        XCTAssertEqual(KitStatusVisuals.parseMark("kit.H026.sc.12"), KitStatusVisuals.MarkTag(heroID: "H026", name: "sc", owner: 12))
        XCTAssertEqual(KitStatusVisuals.parseMark("kit.H030.void.3")?.heroID, "H030")
        XCTAssertNil(KitStatusVisuals.parseMark("kit.H028.bane")?.owner, "所有者が無い書式でも読める")
        XCTAssertNotNil(KitStatusVisuals.parseMark("kit.H028.bane"))
        XCTAssertNil(KitStatusVisuals.parseMark("cc.stun"))
        XCTAssertNil(KitStatusVisuals.parseMark("kit.H03.x.1"), "ヒーロー ID の形でない")
        XCTAssertNil(KitStatusVisuals.parseMark("kit.Hxyz.x.1"))
        XCTAssertNil(KitStatusVisuals.parseMark("kit.H026"))
        XCTAssertNil(KitStatusVisuals.parseMark(""))
    }

    func testStatusLookByKindAndTag() {
        XCTAssertEqual(KitStatusVisuals.look(kind: .stun, tag: "kit.H031.freeze"), .freeze)
        XCTAssertEqual(KitStatusVisuals.look(kind: .suppress, tag: "kit.H031.prideFreeze"), .prideFreeze)
        XCTAssertEqual(KitStatusVisuals.look(kind: .mark, tag: "kit.H026.sc.5"), .mark(heroID: "H026", name: "sc"))
        // 種類が違えば同じ tag でも汎用（凍結の tag は stun、氷の誇りは suppress だけ）
        XCTAssertEqual(KitStatusVisuals.look(kind: .slow, tag: "kit.H031.freeze"), .generic)
        XCTAssertEqual(KitStatusVisuals.look(kind: .stun, tag: "kit.H031.prideFreeze"), .generic)
        XCTAssertEqual(KitStatusVisuals.look(kind: .suppress, tag: "kit.suppress"), .generic)
        XCTAssertEqual(KitStatusVisuals.look(kind: .stun, tag: "cc.stun"), .generic)
        XCTAssertEqual(KitStatusVisuals.look(kind: .mark, tag: "legacy"), .generic, "読めないマークは汎用")
        XCTAssertEqual(KitStatusVisuals.look(kind: .stun, tag: KitStatusVisuals.freezeTag), .freeze)
        XCTAssertTrue(KitStatusVisuals.isFreeze(StatusEffect(kind: .stun, duration: 1, tag: "kit.H031.freeze")))
        XCTAssertFalse(KitStatusVisuals.isFreeze(StatusEffect(kind: .stun, duration: 1, tag: "cc.stun")))
    }

    func testStatusVariantsSeparateIconsButKeepGenericMerged() {
        let generic = KitStatusVisuals.variant(kind: .stun, tag: "cc.stun")
        XCTAssertEqual(generic, 0)
        XCTAssertEqual(KitStatusVisuals.variant(kind: .stun, tag: ""), generic, "汎用はタグによらずまとめる")
        let freeze = KitStatusVisuals.variant(kind: .stun, tag: "kit.H031.freeze")
        let pride = KitStatusVisuals.variant(kind: .suppress, tag: "kit.H031.prideFreeze")
        let sc = KitStatusVisuals.variant(kind: .mark, tag: "kit.H026.sc.1")
        let void = KitStatusVisuals.variant(kind: .mark, tag: "kit.H030.void.1")
        XCTAssertEqual(Set([generic, freeze, pride, sc, void]).count, 5)
        XCTAssertEqual(sc, KitStatusVisuals.variant(kind: .mark, tag: "kit.H026.sc.99"), "所有者が違っても同じヒーローのマークはまとめる")
        XCTAssertEqual(KitStatusVisuals.variant(kind: .mark, tag: "unknown"), 0)
    }

    /// 状態アイコンの名前: マークは所有者のヒーロー固有の名前、H031 の凍結はスタンではなく凍結。無ければ汎用。
    func testTagAwareStatusNamesAndSymbols() {
        XCTAssertEqual(HUDSymbols.statusName(.mark, tag: "kit.H026.sc.7"), L("超伝導", "Superconduct"))
        XCTAssertEqual(HUDSymbols.statusName(.mark, tag: "kit.H030.void.7"), L("虚空の印", "Void mark"))
        XCTAssertEqual(HUDSymbols.statusName(.mark, tag: "kit.H099.zzz.7"), HUDSymbols.statusName(.mark), "未登録のマークは汎用の刻印")
        XCTAssertEqual(HUDSymbols.statusName(.mark, tag: ""), HUDSymbols.statusName(.mark))
        XCTAssertEqual(HUDSymbols.statusName(.stun, tag: "kit.H031.freeze"), L("凍結", "Frozen"))
        XCTAssertEqual(HUDSymbols.statusName(.suppress, tag: "kit.H031.prideFreeze"), L("凍結", "Frozen"))
        XCTAssertEqual(HUDSymbols.statusName(.stun, tag: "cc.stun"), HUDSymbols.statusName(.stun))
        XCTAssertNotEqual(HUDSymbols.statusName(.stun, tag: "kit.H031.freeze"), HUDSymbols.statusName(.stun))
        XCTAssertEqual(HUDSymbols.statusName(.suppress, tag: "kit.suppress"), HUDSymbols.statusName(.suppress))

        XCTAssertEqual(HUDSymbols.status(.stun, tag: "kit.H031.freeze"), KitStatusVisuals.freezeSymbol)
        XCTAssertEqual(HUDSymbols.status(.mark, tag: "kit.H026.sc.7"), "bolt.fill")
        XCTAssertEqual(HUDSymbols.status(.mark, tag: "kit.H029.wave.7"), HUDSymbols.status(.mark), "固有のアイコンが無いマークは汎用")
        XCTAssertEqual(HUDSymbols.status(.stun, tag: ""), HUDSymbols.status(.stun))
        for name in KitStatusVisuals.hudSymbols { XCTAssertTrue(HUDSymbols.all.contains(name), name) }
    }

    /// 状態アイコン列: 凍結と通常のスタン、別ヒーローのマークは別のアイコン。同じヒーローのマークは 1 つにまとめる。
    func testStatusIconsSeparateKitVariants() {
        var u = bareUnit()
        u.statuses = [
            StatusEffect(kind: .stun, duration: 1, tag: "cc.stun"),
            StatusEffect(kind: .stun, duration: 2, tag: "kit.H031.freeze"),
            StatusEffect(kind: .mark, duration: 3, magnitude: 1, tag: "kit.H026.sc.4"),
            StatusEffect(kind: .mark, duration: 4, magnitude: 1, tag: "kit.H026.sc.5"),
            StatusEffect(kind: .mark, duration: 2, magnitude: 1, tag: "kit.H030.void.6"),
        ]
        let icons = HUDModel.statusIcons(u)
        XCTAssertEqual(icons.count, 4)
        XCTAssertEqual(Set(icons.map(\.id)).count, 4, "id は重ならない")
        XCTAssertEqual(icons.filter { $0.kind == .stun }.count, 2)
        let sc = icons.first { $0.tag.hasPrefix("kit.H026") }
        XCTAssertEqual(sc?.remaining ?? 0, 4, accuracy: 1e-9, "同じヒーローのマークは長い方")
        let freeze = icons.first { $0.tag == "kit.H031.freeze" }
        XCTAssertEqual(freeze.map { HUDSymbols.statusName($0.kind, tag: $0.tag) }, L("凍結", "Frozen"))
    }

    // MARK: キット層の状態の見え方（世界）

    func testIndicatorFlagsShowFreezeAsIceNotStars() {
        var u = bareUnit()
        XCTAssertEqual(StatusIndicators.flags(of: u), StatusIndicators.Flags())
        u.statuses = [StatusEffect(kind: .stun, duration: 1, tag: "cc.stun")]
        var f = StatusIndicators.flags(of: u)
        XCTAssertTrue(f.stunned)
        XCTAssertFalse(f.frozen, "通常のスタンは回る星")
        u.statuses = [StatusEffect(kind: .stun, duration: 1, tag: "kit.H031.freeze")]
        f = StatusIndicators.flags(of: u)
        XCTAssertTrue(f.stunned)
        XCTAssertTrue(f.frozen, "H031 の凍結は氷の殻")
        u.statuses = [StatusEffect(kind: .suppress, duration: 1, tag: "kit.H031.prideFreeze")]
        f = StatusIndicators.flags(of: u)
        XCTAssertTrue(f.stunned && f.frozen, "氷の誇りの凍結（suppress）も氷の殻")
        u.statuses = [StatusEffect(kind: .suppress, duration: 1, tag: "kit.suppress")]
        f = StatusIndicators.flags(of: u)
        XCTAssertTrue(f.stunned, "行動不能の suppress は星で示す")
        XCTAssertFalse(f.frozen)
        u.statuses = [StatusEffect(kind: .slow, duration: 1, magnitude: 0.3, tag: "kit.H031.freeze")]
        XCTAssertFalse(StatusIndicators.flags(of: u).frozen, "種類が違う")
    }

    func testMarkGlyphPicksTheLargestStackAndTintsByOwnerHero() {
        XCTAssertNil(KitStatusVisuals.markGlyph(in: []))
        XCTAssertNil(KitStatusVisuals.markGlyph(in: [StatusEffect(kind: .slow, duration: 1, magnitude: 0.3)]))
        let list = [
            StatusEffect(kind: .mark, duration: 3, magnitude: 1, tag: "kit.H030.void.2"),
            StatusEffect(kind: .mark, duration: 3, magnitude: 3, tag: "kit.H028.bane.9"),
            StatusEffect(kind: .mark, duration: 3, magnitude: 3, tag: "kit.H029.wave.8"),
        ]
        XCTAssertEqual(KitStatusVisuals.markGlyph(in: list), KitStatusVisuals.MarkGlyph(heroID: "H028", stacks: 3), "最大スタック、同数は先")
        var expired = StatusEffect(kind: .mark, duration: 3, magnitude: 5, tag: "kit.H026.sc.1")
        expired.remaining = 0
        XCTAssertEqual(KitStatusVisuals.markGlyph(in: [expired, list[0]])?.heroID, "H030", "切れたものは数えない")
        XCTAssertEqual(KitStatusVisuals.markGlyph(in: [StatusEffect(kind: .mark, duration: 1, magnitude: 0, tag: "x")]),
                       KitStatusVisuals.MarkGlyph(heroID: "", stacks: 1), "読めない tag・0 スタックでも 1 つは出す")
        var u = bareUnit()
        u.statuses = [StatusEffect(kind: .mark, duration: 3, magnitude: 1, tag: "kit.H026.sc.4")]
        XCTAssertEqual(StatusIndicators.flags(of: u).mark?.heroID, "H026")

        XCTAssertEqual(KitStatusVisuals.markScale(stacks: 1), 1)
        XCTAssertGreaterThan(KitStatusVisuals.markScale(stacks: 3), KitStatusVisuals.markScale(stacks: 2))
        XCTAssertEqual(KitStatusVisuals.markScale(stacks: 50), KitStatusVisuals.markScale(stacks: 5), "上限あり")
        XCTAssertEqual(KitStatusVisuals.markScale(stacks: 0), 1)
        XCTAssertNotEqual(KitStatusVisuals.markColor(heroID: "H026"), KitStatusVisuals.markColor(heroID: "H030"))
        XCTAssertEqual(KitStatusVisuals.markColor(heroID: "H001"), KitStatusVisuals.markColor(heroID: ""), "キットの無いヒーローは既定色")
    }

    /// ステルス中のモデルは自分・味方・観戦者にだけ薄く見える。敵の視点では変えない（敵のステルスを暴かない）。
    func testStealthOpacityOnlyForAlliesAndSpectators() {
        let a = KitStatusVisuals.stealthAllyOpacity
        XCTAssertEqual(a, 0.4, accuracy: 1e-6)
        XCTAssertEqual(KitStatusVisuals.stealthOpacity(stealthed: true, dead: false, unitTeam: .blue, viewerTeam: .blue), a)
        XCTAssertEqual(KitStatusVisuals.stealthOpacity(stealthed: true, dead: false, unitTeam: .red, viewerTeam: .red), a)
        XCTAssertEqual(KitStatusVisuals.stealthOpacity(stealthed: true, dead: false, unitTeam: .blue, viewerTeam: nil), a, "観戦")
        XCTAssertEqual(KitStatusVisuals.stealthOpacity(stealthed: true, dead: false, unitTeam: .blue, viewerTeam: .red), 1,
                       "敵の視点では変えない（見えているなら看破されている）")
        XCTAssertEqual(KitStatusVisuals.stealthOpacity(stealthed: false, dead: false, unitTeam: .blue, viewerTeam: .blue), 1)
        XCTAssertEqual(KitStatusVisuals.stealthOpacity(stealthed: true, dead: true, unitTeam: .blue, viewerTeam: .blue), 1)
    }

    /// 氷の誇りの輪: H031 の生きているヒーローで、パッシブのバッジが「準備できた」ときだけ。
    func testIceReadyRingFollowsThePassiveBadge() {
        let ready = KitBadge(kind: .stacks, value: 1, maxValue: 1)
        XCTAssertTrue(KitStatusVisuals.showsIceReady(heroID: "H031", alive: true, badge: ready))
        XCTAssertFalse(KitStatusVisuals.showsIceReady(heroID: "H031", alive: false, badge: ready))
        XCTAssertFalse(KitStatusVisuals.showsIceReady(heroID: "H031", alive: true, badge: nil))
        XCTAssertFalse(KitStatusVisuals.showsIceReady(heroID: "H031", alive: true,
                                                       badge: KitBadge(kind: .timer, remaining: 30, total: 90)), "再発動待ち・凍結中はタイマー")
        XCTAssertFalse(KitStatusVisuals.showsIceReady(heroID: "H031", alive: true,
                                                       badge: KitBadge(kind: .stacks, value: 0, maxValue: 1)))
        XCTAssertFalse(KitStatusVisuals.showsIceReady(heroID: "H032", alive: true, badge: ready), "他のヒーローには出さない")
        XCTAssertFalse(KitStatusVisuals.showsIceReady(of: bareUnit()), "ヒーローのデータが無い")
    }

    /// 実際の H031 では、スナップショットの状態だけから誰のでも読める（観戦・敵の視点でも同じ）。死亡中は出ない。
    func testIceReadyRingReadsFromSimStateForAnyUnit() throws {
        try XCTSkipUnless(HeroKits.hasKit("H031"), "H031 のキットが有効でない")
        let sim = Simulation(config: MatchFactory.standardMatch(humanHeroID: "H031", humanName: "T", seed: 7))
        var s = sim.state
        let i = try XCTUnwrap(s.units.firstIndex { $0.hero?.heroID == "H031" })
        XCTAssertTrue(KitStatusVisuals.showsIceReady(of: s.units[i]), "開始直後は使える")
        XCTAssertTrue(StatusIndicators.flags(of: s.units[i]).iceReady)
        s.units[i].hero?.respawnTimer = 5
        XCTAssertFalse(KitStatusVisuals.showsIceReady(of: s.units[i]), "死亡中")
        let other = try XCTUnwrap(s.units.firstIndex { $0.kind == .hero && $0.hero?.heroID != "H031" })
        XCTAssertFalse(StatusIndicators.flags(of: s.units[other]).iceReady)
    }
}
