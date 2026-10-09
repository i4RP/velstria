import XCTest
@testable import VelstriaCore

// キット層の共有部品のテスト: KitText の {key}・stateHash の予約タイマー・fireTimers の in-place 化・
// ボットのフック（奥義の関門 / ファーム / 撤退）。docs/SKILL_KITS.md

// MARK: - KitText の {key}

final class KitTextNamedExtrasTests: XCTestCase {
    private let targeting = SkillTargeting(archetype: .cone, aim: .direction, range: 650, radius: 155.2)

    func testNamedExtrasAreFilledWithTheSameValuesAsIndexedPlaceholders() {
        var n = SkillNumbers()
        n.extras = [KitStat(key: "bleed", value: 2.5), KitStat(key: "stacks", value: 4), KitStat(key: "pct", value: 12.04),
                    KitStat(key: "fifth", value: 9)]
        // {x#} は先頭 4 つ、{key} は全要素。整数に近ければ整数・そうでなければ小数 1 桁（どちらも同じ書式）
        XCTAssertEqual(KitText.fill("{bleed}/{stacks}/{pct}/{fifth}", numbers: n, targeting: targeting), "2.5/4/12/9")
        XCTAssertEqual(KitText.fill("{x0}/{x1}/{x2}/{x3}", numbers: n, targeting: targeting), "2.5/4/12/9")
        XCTAssertEqual(KitText.fill("{x0}={bleed} {x1}={stacks}", numbers: n, targeting: targeting), "2.5=2.5 4=4")
    }

    func testNamedExtrasRepeatAndUnknownKeysStayUntouched() {
        var n = SkillNumbers()
        n.damage = 100
        n.extras = [KitStat(key: "bleed", value: 3)]
        XCTAssertEqual(KitText.fill("{bleed} + {bleed} / {nope} / {damage}", numbers: n, targeting: targeting),
                       "3 + 3 / {nope} / 100")
    }

    func testBuiltInNamesWinAndFirstDuplicateKeyWins() {
        var n = SkillNumbers()
        n.damage = 100
        n.extras = [KitStat(key: "damage", value: 7), KitStat(key: "same", value: 1), KitStat(key: "same", value: 2),
                    KitStat(key: "", value: 5)]
        XCTAssertEqual(KitText.fill("{damage}/{same}/{}", numbers: n, targeting: targeting), "100/1/{}")
    }

    func testNonFiniteExtrasBecomeZero() {
        var n = SkillNumbers()
        n.extras = [KitStat(key: "bad", value: .infinity)]
        XCTAssertEqual(KitText.fill("{bad}", numbers: n, targeting: targeting), "0")
    }
}

// MARK: - stateHash と予約タイマー

final class KitStateHashTests: KitTestCase {
    private func world() -> (SkillWorld, Int) {
        var w = SkillWorld()
        let k = w.addKitHero()
        _ = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        return (w, k)
    }

    func testScheduledTimerChangesTheHash() {
        let (base, k) = world()
        var a = base
        var b = base
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        Kit.schedule(&a.s, caster: k, slot: .skill1, code: 5, after: 2)
        XCTAssertNotEqual(a.s.stateHash(), b.s.stateHash(), "予約があるかないか")
        Kit.schedule(&b.s, caster: k, slot: .skill1, code: 5, after: 2)
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())

        func hash(_ edit: (inout SimState) -> Void) -> UInt64 {
            var w = base
            Kit.schedule(&w.s, caster: k, slot: .skill1, code: 5, after: 2, targetID: 7)
            edit(&w.s)
            return w.s.stateHash()
        }
        let reference = hash { _ in }
        XCTAssertNotEqual(reference, hash { $0.units[k].hero!.kit!.scheduled[0].code = 6 }, "code")
        XCTAssertNotEqual(reference, hash { $0.units[k].hero!.kit!.scheduled[0].remaining = 2.5 }, "remaining")
        XCTAssertNotEqual(reference, hash { $0.units[k].hero!.kit!.scheduled[0].slot = .skill2 }, "slot")
        XCTAssertNotEqual(reference, hash { $0.units[k].hero!.kit!.scheduled[0].targetID = 8 }, "targetID")
        XCTAssertNotEqual(reference, hash { $0.units[k].hero!.kit!.scheduled[0].index = 1 }, "index")
        // 0.01 未満の差は丸めて同じ（他の浮動小数と同じ規則）
        XCTAssertEqual(reference, hash { $0.units[k].hero!.kit!.scheduled[0].remaining += 0.001 })
    }

    func testTimerOrderMatters() {
        let (base, k) = world()
        var a = base
        var b = base
        Kit.schedule(&a.s, caster: k, slot: .skill1, code: 1, after: 1)
        Kit.schedule(&a.s, caster: k, slot: .skill1, code: 2, after: 1)
        Kit.schedule(&b.s, caster: k, slot: .skill1, code: 2, after: 1)
        Kit.schedule(&b.s, caster: k, slot: .skill1, code: 1, after: 1)
        XCTAssertNotEqual(a.s.stateHash(), b.s.stateHash(), "挿入順に消化するので順序も状態")
    }

    func testSweepArriveCodeChangesTheHash() {
        let (base, k) = world()
        func hash(_ arrive: Int?) -> UInt64 {
            var w = base
            if let arrive {
                w.s.units[k].hero!.kit!.sweep = KitSweep(slot: .skill2, payload: SkillWorld.truePayload(), radius: 60,
                                                         arriveCode: arrive)
            }
            return w.s.stateHash()
        }
        XCTAssertNotEqual(hash(nil), hash(0))
        XCTAssertNotEqual(hash(0), hash(11))
        XCTAssertNotEqual(hash(11), hash(12))
        XCTAssertEqual(hash(11), hash(11))
    }

    /// 同じ入力を 2 回流した結果が、予約タイマーを含めて一致する（決定論）。
    func testDeterministicRunsKeepEqualHashesWhileTimersAreScheduled() {
        func run() -> [UInt64] {
            var (w, k) = world()
            var out: [UInt64] = []
            w.cast(k, .ultimate)
            for _ in 0..<12 {
                w.tick()
                out.append(w.s.stateHash())
            }
            XCTAssertGreaterThan(w.kit(k).ints[3], 0, "ult の連撃が発火した")
            return out
        }
        XCTAssertEqual(run(), run())
    }
}

// MARK: - fireTimers

final class KitFireTimersTests: KitTestCase {
    func testWaitingTimersCountDownInPlaceAndKeepOrder() {
        var w = SkillWorld()
        let k = w.addKitHero()
        Kit.schedule(&w.s, caster: k, slot: .skill1, code: 1, after: 5)
        Kit.schedule(&w.s, caster: k, slot: .skill1, code: 2, after: 0.1)
        Kit.schedule(&w.s, caster: k, slot: .skill1, code: 3, after: 4)
        let ticks = 6
        w.tick(ticks)
        // 0.1 s のタイマーだけが発火し、残りは順序を保ったままちょうど ticks 分減っている
        XCTAssertEqual(w.kit(k).ints[3], 1)
        XCTAssertEqual(w.kit(k).scheduled.map(\.code), [1, 3])
        XCTAssertEqual(w.kit(k).scheduled[0].remaining, 5 - Double(ticks) * Balance.dt, accuracy: 1e-9)
        XCTAssertEqual(w.kit(k).scheduled[1].remaining, 4 - Double(ticks) * Balance.dt, accuracy: 1e-9)
    }

    func testEmptyScheduleIsLeftAlone() {
        var w = SkillWorld()
        let k = w.addKitHero()
        w.tick(5)
        XCTAssertTrue(w.kit(k).scheduled.isEmpty)
        XCTAssertEqual(w.kit(k).ints[3], 0)
    }

    func testZeroDelayTimerFiresOnTheSameTick() {
        var w = SkillWorld()
        let k = w.addKitHero()
        Kit.schedule(&w.s, caster: k, slot: .skill1, code: 9, after: 0)
        w.tick()
        XCTAssertEqual(w.kit(k).ints[3], 1)
        XCTAssertTrue(w.kit(k).scheduled.isEmpty)
    }
}

// MARK: - ボットのフック

/// ボットのフックを試すキット。KitState.form で挙動を切り替える。
///   botCast:   form 1 = .cast / 2 = .castNow / 6 = .skip（奥義）、それ以外 = .useDefault
///   botFarm:   form 3 = true
///   botEscape: form 4 = .castNow(逃げる向き)（奥義だけ）/ 5 = .skip（全部）、それ以外 = .useDefault
/// スキル1 は passive、スキル2 は dashStrike に見せる（汎用の突入系）。
private struct BotHookKit: HeroKit {
    let heroID: String
    var isReady: Bool { true }

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        var t = base
        switch slot {
        case .skill1:
            t.archetype = .passive
        case .skill2:
            t.archetype = .dashStrike
            t.aim = .direction
            t.range = 500
            t.radius = 150
        default:
            break
        }
        return t
    }

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        guard slot == .ultimate else { return .useDefault }
        switch s.units[bot].hero?.kit?.form ?? 0 {
        case 1: return .cast(.direction(Vec2(1, 0)))
        case 2: return .castNow(.direction(Vec2(1, 0)))
        case 6: return .skip
        default: return .useDefault
        }
    }

    func botFarm(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 center: Vec2, count: Int) -> Bool {
        s.units[bot].hero?.kit?.form == 3
    }

    func botEscape(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                   flee: Vec2, enemyDistance: Double) -> BotKitDecision {
        switch s.units[bot].hero?.kit?.form ?? 0 {
        case 4: return slot == .ultimate ? .castNow(.direction(flee)) : .useDefault
        case 5: return .skip
        default: return .useDefault
        }
    }
}

final class KitBotHookTests: XCTestCase {
    override func tearDown() {
        HeroKits.testOverride = []
        super.tearDown()
    }

    /// blue/mid のボットにフック用キットを差し、敵 1 体（HP 極大 = 倒せない）を 300 先に置く。
    private struct Scene {
        var f: BotFixture
        let me: Int
        let foe: Int
        var agent: BotAgent
        var mem: BotHeroMemory
        let sighting: BotSighting

        init(difficulty: Difficulty = .hard) {
            var fx = BotFixture.bots(difficulty, time: 600)
            fx.parkAllHeroes()
            let m = fx.hero(.blue, .mid)
            let e = fx.hero(.red, .mid)
            HeroKits.testOverride = [BotHookKit(heroID: fx.s.units[m].hero!.heroID)]
            fx.place(m, at: Vec2(6000, 6000))
            fx.place(e, at: Vec2(6300, 6000))
            fx.s.units[m].hero!.kit = KitState()
            fx.s.units[m].hero!.level = 12
            fx.s.units[m].hero!.skillRanks = [1, 1, 1, 1]
            fx.s.units[m].hero!.skillCooldowns = Array(repeating: 0, count: fx.s.units[m].hero!.skillCooldowns.count)
            fx.s.units[m].resource = fx.s.units[m].stats.maxResource
            // 倒せない敵
            fx.s.units[e].stats.maxHP = 1_000_000
            fx.s.units[e].hp = 1_000_000
            let def = fx.ctx.master.hero(fx.s.units[m].hero!.heroID)!
            let sight = BotSighting(index: e, id: fx.s.units[e].id, pos: Vec2(6300, 6000), velocity: .zero,
                                    distance: 300, visible: true)
            var ag = BotAgent(i: m, slot: fx.slot(of: m), id: fx.s.units[m].id, team: .blue, profile: .of(.hard),
                              difficulty: .hard, pos: Vec2(6000, 6000), level: 12, role: def.role, position: .mid,
                              isRanged: def.isRanged, skillsWork: true)
            ag.enemies = [sight]
            me = m
            foe = e
            sighting = sight
            agent = ag
            mem = fx.memory(m)
            f = fx
        }

        mutating func setForm(_ v: Int) { f.s.units[me].hero!.kit!.form = v }

        mutating func castSkills() -> [PlayerCommand] {
            agent.commands = []
            BotCombat.castSkills(&f.s, f.ctx, &agent, &mem, target: sighting, fighting: true)
            return agent.commands
        }

        mutating func escape() -> [PlayerCommand] {
            agent.commands = []
            mem.lastSkillTime = -100
            let w = BotWorld(f.s, f.ctx)
            BotCombat.castEscapeSkill(&f.s, f.ctx, w, &agent, &mem)
            return agent.commands
        }

        mutating func farm(minions: Int = 3) -> [PlayerCommand] {
            var targets: [Int] = []
            for k in 0..<minions {
                targets.append(f.addMinion(.melee, team: .red, lane: .mid, at: Vec2(6250 + Double(k) * 20, 6000)))
            }
            agent.commands = []
            mem.lastSkillTime = -100
            BotCombat.castFarmSkills(&f.s, f.ctx, &agent, &mem, targets: targets, minCluster: 1)
            return agent.commands
        }
    }

    private static func slots(_ cmds: [PlayerCommand]) -> [SkillSlot] {
        cmds.compactMap { if case .castSkill(let slot, _) = $0 { return slot } else { return nil } }
    }

    // MARK: 奥義の関門

    func testUltimateGateStillBlocksDefaultAndCast() {
        for form in [0, 1] {
            var sc = Scene()
            sc.setForm(form)
            XCTAssertFalse(Self.slots(sc.castSkills()).contains(.ultimate), "form \(form): 倒せず 1 体なら奥義は撃たない")
        }
    }

    func testCastNowBypassesTheUltimateGate() {
        var sc = Scene()
        sc.setForm(2)
        let cmds = sc.castSkills()
        XCTAssertEqual(Self.slots(cmds).first, .ultimate, "\(cmds)")
        if case .castSkill(_, let target) = cmds.first { XCTAssertEqual(target, .direction(Vec2(1, 0))) }
    }

    func testSkipStillSkipsTheUltimate() {
        var sc = Scene()
        sc.setForm(6)
        XCTAssertFalse(Self.slots(sc.castSkills()).contains(.ultimate))
    }

    func testRecastingUltimateBypassesTheGate() {
        for form in [1, 2] {
            var sc = Scene()
            sc.setForm(form)
            // 初回の発動後（CD 中）で再使用の窓が開いている
            sc.f.s.units[sc.me].hero!.skillCooldowns[SkillSlot.ultimate.rawValue] = 30
            Kit.openRecast(&sc.f.s, caster: sc.me, slot: .ultimate, duration: 5)
            XCTAssertTrue(HeroKits.isRecasting(sc.f.s, sc.me, .ultimate))
            let cmds = sc.castSkills()
            XCTAssertEqual(Self.slots(cmds).first, .ultimate, "form \(form): \(cmds)")
            // 同じ状況で窓が無ければ、.cast は関門で止まる
            var closed = Scene()
            closed.setForm(form)
            closed.f.s.units[closed.me].hero!.skillCooldowns[SkillSlot.ultimate.rawValue] = 30
            XCTAssertFalse(Self.slots(closed.castSkills()).contains(.ultimate), "form \(form) 窓なし")
        }
    }

    func testCrowdOrKillableStillOpensTheGateForCast() {
        var sc = Scene()
        sc.setForm(1)
        // 2 体を巻き込める → 関門は通る
        let second = sc.f.hero(.red, .top)
        sc.f.place(second, at: Vec2(6320, 6020))
        sc.agent.enemies.append(BotSighting(index: second, id: sc.f.s.units[second].id, pos: Vec2(6320, 6020),
                                            velocity: .zero, distance: 330, visible: true))
        XCTAssertEqual(Self.slots(sc.castSkills()).first, .ultimate)
    }

    // MARK: ファーム

    func testFarmSkipsGapClosersUnlessTheKitAllowsIt() {
        var off = Scene()
        XCTAssertTrue(Self.slots(off.farm()).isEmpty, "既定では突入系でファームしない")
        var on = Scene()
        on.setForm(3)
        XCTAssertEqual(Self.slots(on.farm()), [.skill2])
    }

    // MARK: 撤退

    func testEscapeDefaultKeepsGenericDashBehaviour() {
        var sc = Scene()
        let cmds = sc.escape()
        XCTAssertEqual(Self.slots(cmds), [.skill2], "既定は従来どおり突進系のスキル2 だけ: \(cmds)")
    }

    func testEscapeLetsKitUseTheUltimateToFlee() {
        var sc = Scene()
        sc.setForm(4)
        let cmds = sc.escape()
        XCTAssertEqual(Self.slots(cmds), [.ultimate], "\(cmds)")
        if case .castSkill(_, .direction(let d)) = cmds.first { XCTAssertEqual(d.length, 1, accuracy: 1e-6) }
    }

    func testEscapeSkipSuppressesEverything() {
        var sc = Scene()
        sc.setForm(5)
        XCTAssertTrue(Self.slots(sc.escape()).isEmpty)
    }
}
