import XCTest
@testable import VelstriaCore

/// 靴に付ける祝福（ジャングル: 炎撃・氷刺・血刃、ローム: 隠蔽・激励・恩恵・致命傷。Systems/GearSystem.swift）:
/// 付け方（靴の自動購入・狩猟印・2:00 の締め切り・靴の売却）、ジャングルの強化、ロームの収入（共栄・無私）と祝福の能力。
final class GearTests: XCTestCase {
    private let spot = Vec2(6000, 6000)
    private let noSmite = ["BS01", "BS03"]
    private let smite = [Balance.Economy.smiteSpellID, "BS01"]
    private let boots = Balance.Gear.baseBootsID

    /// 全ヒーローを泉へ退避し、人間（blue）を spot に置く。option があればスピードブーツと祝福を持たせる。
    private func blessed(_ option: GearOption?, spells: [String]? = nil, time: Double = 300,
                         roamGold: Double = 0) -> (EconomyFixture, Int) {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        for i in f.s.heroIndices {
            f.s.units[i].hero!.autoLevelSkills = false
            f.s.units[i].hero!.runes = []
            f.s.units[i].hero!.kit = nil
        }
        let a = f.human
        f.place(a, at: spot)
        f.s.units[a].hero!.spells = spells ?? (option?.category == .jungle ? smite : noSmite)
        f.s.tick = Int((time * Balance.tickRate).rounded())
        f.s.time = Double(f.s.tick) * Balance.dt
        if let option { give(&f, a, option, roamGold: roamGold) }
        StatCalculator.recompute(&f.s, a, f.ctx)
        f.s.events.removeAll()
        return (f, a)
    }

    /// スピードブーツと祝福を直接持たせる。
    private func give(_ f: inout EconomyFixture, _ i: Int, _ option: GearOption, roamGold: Double = 0) {
        f.s.units[i].hero!.items = [boots]
        f.s.units[i].hero!.itemInvested = [250]
        var g = GearState(option: option)
        g.roamGold = roamGold
        f.s.units[i].hero!.gear = g
        StatCalculator.recompute(&f.s, i, f.ctx)
    }

    /// .setGearOption を実行し、購入失敗の理由を返す。
    private func setOption(_ f: inout EconomyFixture, _ i: Int, _ option: GearOption) -> [String] {
        f.s.events.removeAll()
        CommandSystem.apply([HeroCommand(heroID: f.id(i), command: .setGearOption(option))], &f.s, f.ctx)
        return f.s.events.purchaseFailures
    }

    /// red の先頭のヒーローを p に置く（HP 満タン・被ダメ軽減 0・両チームから見える）。
    private func enemy(_ f: inout EconomyFixture, at p: Vec2) -> Int {
        let v = f.heroes(.red)[0]
        f.place(v, at: p)
        StatCalculator.recompute(&f.s, v, f.ctx)
        f.s.units[v].hp = f.s.units[v].stats.maxHP
        f.s.units[v].stats.damageReduction = 0
        for i in f.s.units.indices { f.s.units[i].visibleMask = Team.blue.visionBit | Team.red.visionBit }
        return v
    }

    private func ally(_ f: EconomyFixture, _ a: Int, _ n: Int = 0) -> Int {
        f.heroes(.blue).filter { $0 != a }[n]
    }

    private func gearStatus(_ f: EconomyFixture, _ i: Int, _ tag: String) -> [StatusEffect] {
        f.s.units[i].statuses.filter { $0.tag == tag }
    }

    // MARK: - 祝福の一覧

    func testBlessingsAreBootOptionsNotItems() {
        XCTAssertEqual(GearOption.allCases.map(\.rawValue), ["flame", "ice", "bloody", "conceal", "encourage", "favor", "direHit"],
                       "rawValue はリプレイに残る")
        XCTAssertEqual(GearOption.options(for: .jungle), [.flame, .ice, .bloody])
        XCTAssertEqual(GearOption.options(for: .roam), [.conceal, .encourage, .favor, .direHit])
        XCTAssertEqual(GearOption.defaultOption(for: .jungle, role: .ranger), .flame)
        XCTAssertEqual(GearOption.defaultOption(for: .roam, role: .support), .favor)
        XCTAssertEqual(GearOption.defaultOption(for: .roam, role: .vanguard), .encourage)
        XCTAssertNil(GearOption.defaultOption(for: .attack, role: .ranger))
        XCTAssertFalse(MasterData.shared.items.contains { $0.category == .jungle || $0.category == .roam },
                       "ジャングル・ロームの装備は売っていない")
        // 祝福は靴に付く（靴が無ければ効かない）
        let f = EconomyFixture.standard()
        var h = f.hero(f.human)
        h.gear = GearState(option: .encourage)
        h.items = []
        XCTAssertNil(GearEffects.option(of: h, master: f.master))
        h.items = ["EQ406"]
        XCTAssertEqual(GearEffects.option(of: h, master: f.master), .encourage)
        XCTAssertTrue(GearEffects.has(h, .roam, master: f.master))
        XCTAssertFalse(GearEffects.has(h, .jungle, master: f.master))
        XCTAssertEqual(GearEffects.option(of: h, category: .roam, master: f.master), .encourage)
        XCTAssertNil(GearEffects.option(of: h, category: .jungle, master: f.master))
    }

    // MARK: - 付け方

    func testBlessingBuysBasicBootsWhenNoneOwned() {
        var (f, a) = blessed(nil, time: 60)
        f.s.units[a].hero!.gold = 500
        let q = GearEffects.quote(f.hero(a), option: .encourage, time: f.s.time, ctx: f.ctx)
        XCTAssertNil(q.failure)
        XCTAssertEqual(q.cost, 250)
        XCTAssertEqual(q.itemID, "gear:encourage")
        XCTAssertEqual(setOption(&f, a, .encourage), [])
        XCTAssertTrue(f.s.events.contains(.itemPurchased(heroID: f.id(a), itemID: boots)))
        XCTAssertEqual(f.hero(a).items, [boots])
        XCTAssertEqual(f.hero(a).gold, 250)
        XCTAssertEqual(f.hero(a).gear?.option, .encourage)
        // 靴があれば 0 Gold で付け替える
        XCTAssertEqual(GearEffects.quote(f.hero(a), option: .favor, time: f.s.time, ctx: f.ctx).cost, 0)
        XCTAssertEqual(setOption(&f, a, .favor), [])
        XCTAssertEqual(f.hero(a).gold, 250)
        XCTAssertEqual(f.hero(a).items, [boots])
        XCTAssertEqual(f.hero(a).gear?.option, .favor)
        // 靴が買えなければ付かない
        var (g, b) = blessed(nil, time: 60)
        g.s.units[b].hero!.gold = 100
        XCTAssertEqual(setOption(&g, b, .encourage), ["not_enough_gold"])
        XCTAssertTrue(g.hero(b).items.isEmpty)
        XCTAssertNil(g.hero(b).gear?.option)
    }

    func testJungleBlessingRequiresSmite() {
        var (f, a) = blessed(nil, spells: noSmite)
        f.s.units[a].hero!.gold = 1000
        XCTAssertEqual(setOption(&f, a, .flame), ["requires_smite"])
        XCTAssertTrue(f.hero(a).items.isEmpty, "失敗したら靴も買わない")
        f.s.units[a].hero!.spells = smite
        XCTAssertEqual(setOption(&f, a, .ice), [])
        XCTAssertEqual(f.hero(a).items, [boots])
        XCTAssertEqual(f.hero(a).gear?.option, .ice)
        XCTAssertEqual(setOption(&f, a, .bloody), [])
        XCTAssertEqual(f.hero(a).gear?.option, .bloody)
        // 狩猟印があるとロームは付けられない
        XCTAssertEqual(setOption(&f, a, .encourage), ["blocked_by_smite"])
        XCTAssertEqual(f.hero(a).gear?.option, .bloody)
        // 狩猟印を持って靴を買うと、自動でジャングルの祝福（炎撃）が付く
        var (g, b) = blessed(nil, spells: smite)
        g.s.units[b].hero!.gold = 1000
        ItemSystem.buy(&g.s, g.ctx, heroIndex: b, itemID: "EQ403")
        XCTAssertEqual(g.hero(b).gear?.option, .flame)
        XCTAssertEqual(g.s.units[b].stats.monsterGoldBonus, Balance.Economy.jungleMonsterGoldBonus, accuracy: 1e-9)
    }

    func testRoamBlessingClosesAfterTwoMinutes() {
        for (time, expected) in [(120.0, [String]()), (121.0, ["roam_closed"])] {
            var (f, a) = blessed(nil, time: time)
            f.s.units[a].hero!.gold = 1000
            XCTAssertEqual(setOption(&f, a, .favor), expected, "t=\(time)")
        }
        // 付けた後なら、2:00 を過ぎても別のロームの祝福へ付け替えられる
        var (f, a) = blessed(.encourage, time: 300)
        XCTAssertEqual(setOption(&f, a, .direHit), [])
        XCTAssertEqual(f.hero(a).gear?.option, .direHit)
        // 靴を売ると外れ、付け直せない
        ItemSystem.sell(&f.s, f.ctx, heroIndex: a, slotIndex: 0)
        XCTAssertNil(f.hero(a).gear?.option)
        f.s.units[a].hero!.gold = 1000
        XCTAssertEqual(setOption(&f, a, .encourage), ["roam_closed"])
        // ジャングルは時間の制限が無い
        var (g, b) = blessed(nil, spells: smite, time: 900)
        g.s.units[b].hero!.gold = 1000
        XCTAssertEqual(setOption(&g, b, .flame), [])
    }

    func testBotSupportGetsRoamBlessingWithBootsBoughtBeforeTwoMinutes() {
        for (time, expectRoam) in [(60.0, true), (200.0, false)] {
            var f = EconomyFixture.standard()
            let sup = f.heroes(.blue).first { f.hero($0).position == .support && f.hero($0).controller == .bot }!
            f.s.tick = Int(time * Balance.tickRate)
            f.s.time = time
            f.s.units[sup].hero!.gold = 1000
            ItemSystem.buy(&f.s, f.ctx, heroIndex: sup, itemID: boots)
            let expected = expectRoam ? GearOption.defaultOption(for: .roam, role: f.hero(sup).role) : nil
            XCTAssertEqual(f.hero(sup).gear?.option, expected, "t=\(time)")
        }
    }

    func testCombiningBootsKeepsTheBlessingAndSellingRemovesIt() {
        var (f, a) = blessed(nil, spells: smite)
        f.s.units[a].hero!.gold = 2000
        XCTAssertEqual(setOption(&f, a, .ice), [])
        ItemSystem.buy(&f.s, f.ctx, heroIndex: a, itemID: "EQ406")
        XCTAssertEqual(f.hero(a).items, ["EQ406"])
        XCTAssertEqual(f.hero(a).gold, 2000 - 250 - 470)
        XCTAssertEqual(f.hero(a).gear?.option, .ice, "靴を合成しても祝福は残る")
        XCTAssertEqual(f.s.units[a].stats.monsterGoldBonus, Balance.Economy.jungleMonsterGoldBonus, accuracy: 1e-9)
        ItemSystem.sell(&f.s, f.ctx, heroIndex: a, slotIndex: 0)
        XCTAssertNil(f.hero(a).gear?.option)
        XCTAssertNil(GearEffects.option(of: f.hero(a), master: f.master))
        XCTAssertEqual(f.s.units[a].stats.monsterGoldBonus, 0, accuracy: 1e-9)
    }

    // MARK: - ジャングル

    func testJungleBlessingUpgradesAtFiveAndFifteen() {
        var (f, a) = blessed(.flame)
        XCTAssertEqual(f.s.units[a].stats.monsterGoldBonus, Balance.Economy.jungleMonsterGoldBonus, accuracy: 1e-9)
        let before = f.s.units[a].stats
        f.s.units[a].hero!.score.monsterKills = 3
        f.s.units[a].hero!.score.kills = 1
        XCTAssertEqual(GearEffects.jungleProgress(f.hero(a)), 4)
        XCTAssertFalse(GearEffects.jungleBlessingActive(f.hero(a), master: f.master))
        f.s.units[a].hero!.score.assists = 1
        XCTAssertTrue(GearEffects.jungleBlessingActive(f.hero(a), master: f.master), "合計 5 で狩猟印をヒーローに使える")
        f.s.units[a].hero!.score.monsterKills = 12
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.attack, before.attack, accuracy: 1e-9, "合計 14")
        f.s.units[a].hero!.score.monsterKills = 13
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.attack, before.attack + 10, accuracy: 1e-9, "合計 15")
        XCTAssertEqual(f.s.units[a].stats.abilityPower, before.abilityPower + 10, accuracy: 1e-9)
        XCTAssertEqual(f.s.units[a].stats.maxHP, before.maxHP + 100, accuracy: 1e-9)
        // ロームの祝福には付かない
        var (g, b) = blessed(.encourage)
        g.s.units[b].hero!.score.monsterKills = 20
        XCTAssertFalse(GearEffects.jungleBlessingActive(g.hero(b), master: g.master))
    }

    func testJungleBlessingHalvesMinionRewardsUntilTwoMinutes() {
        for (time, factor) in [(100.0, 0.5), (200.0, 1.0)] {
            var (f, a) = blessed(.flame, time: time)
            let m = f.addMinion(.melee, team: .red, at: spot)
            let gold = f.hero(a).gold, xp = f.hero(a).xp
            f.kill(m, by: f.id(a))
            let bonus = DeathSystem.laneBonus(f.s, f.ctx, lane: .mid)
            XCTAssertEqual(f.hero(a).gold - gold, Balance.Economy.minionGold(.melee, at: f.s.time) * factor * bonus.gold,
                           accuracy: 1e-9, "t=\(time)")
            XCTAssertEqual(f.hero(a).xp - xp, Balance.Economy.minionXP(.melee) * factor * bonus.xp, accuracy: 1e-9,
                           "t=\(time)")
        }
    }

    func testHunterBurnsMonstersAfterDamage() {
        for (role, mult) in [(Role.ranger, 1.0), (.assassin, 2.0)] {
            var (f, a) = blessed(.flame)
            f.s.units[a].hero!.role = role
            let mon = f.addMonster(.campLarge, at: spot + Vec2(100, 0))
            f.s.units[mon].stats.maxHP = 5000
            f.s.units[mon].hp = 5000
            CombatSystem.dealDamage(&f.s, f.ctx, sourceID: f.id(a), targetIndex: mon, amount: 10, type: .physical,
                                    source: .basicAttack, isCrit: false, appliesOnHit: false)
            // 40（+3×レベル）（+最大 HP の 1%）を 3 秒かけて。射手以外は 2 倍
            let total = (40 + 3 * Double(f.hero(a).level) + 0.01 * f.s.units[a].stats.maxHP) * mult
            let burn = gearStatus(f, mon, "gear_hunter").first
            XCTAssertEqual(burn?.kind, .burn, "\(role)")
            XCTAssertEqual(burn?.magnitude ?? 0, total / 3, accuracy: 1e-6, "\(role)")
            XCTAssertEqual(burn?.remaining ?? 0, 3, accuracy: 1e-9, "\(role)")
        }
        // ロームの祝福では付かない
        var (g, b) = blessed(.encourage)
        let mon = g.addMonster(.campLarge, at: spot + Vec2(100, 0))
        g.s.units[mon].stats.maxHP = 5000
        g.s.units[mon].hp = 5000
        CombatSystem.dealDamage(&g.s, g.ctx, sourceID: g.id(b), targetIndex: mon, amount: 10, type: .physical,
                                source: .basicAttack, isCrit: false, appliesOnHit: false)
        XCTAssertTrue(gearStatus(g, mon, "gear_hunter").isEmpty)
    }

    func testSmiteOnHeroStealsByBlessing() {
        for option in GearOption.options(for: .jungle) {
            var (f, a) = blessed(option)
            f.s.units[a].hero!.level = 5
            StatCalculator.recompute(&f.s, a, f.ctx)
            f.s.units[a].hp = f.s.units[a].stats.maxHP * 0.5
            let v = enemy(&f, at: spot + Vec2(100, 0))
            let caster = f.s.units[a].stats, target = f.s.units[v].stats
            let hp = f.s.units[v].hp
            GearSystem.applySmiteOnHero(&f.s, f.ctx, caster: a, target: v)
            XCTAssertEqual(hp - f.s.units[v].hp, 100, accuracy: 1e-6, "\(option): 100 の確定ダメージ")
            StatCalculator.recompute(&f.s, a, f.ctx)
            StatCalculator.recompute(&f.s, v, f.ctx)
            switch option {
            case .flame:
                // 物理攻撃・魔法攻撃を 67.5 + 3.5 × 5 = 85 奪う（3 秒）
                XCTAssertEqual(f.s.units[a].stats.attack, caster.attack + 85, accuracy: 1e-6)
                XCTAssertEqual(f.s.units[a].stats.abilityPower, caster.abilityPower + 85, accuracy: 1e-6)
                XCTAssertEqual(f.s.units[v].stats.attack, max(0, target.attack - 85), accuracy: 1e-6)
                XCTAssertEqual(f.s.units[v].stats.abilityPower, max(0, target.abilityPower - 85), accuracy: 1e-6)
                XCTAssertEqual(gearStatus(f, v, "gear_smite").first?.remaining ?? 0, 3, accuracy: 1e-9)
            case .ice:
                // 移動速度を 50 + 2 × 5 = 60 奪う
                XCTAssertEqual(f.s.units[a].stats.moveSpeed, caster.moveSpeed + 60, accuracy: 1e-6)
                XCTAssertEqual(f.s.units[v].stats.moveSpeed, target.moveSpeed - 60, accuracy: 1e-6)
            case .bloody:
                // 300（+自分の追加 HP の 24%）を 3 秒かけて奪う（スピードブーツは HP 0）
                let total = 300 + 0.24 * (caster.maxHP - f.s.units[a].baseStats.maxHP)
                let burn = gearStatus(f, v, "gear_smite").first
                XCTAssertEqual(burn?.kind, .burn)
                XCTAssertEqual(burn?.magnitude ?? 0, total / 3, accuracy: 1e-6)
                XCTAssertEqual(f.hero(a).gear?.drainPerSecond ?? 0, total / 3, accuracy: 1e-6)
                XCTAssertEqual(f.hero(a).gear?.drainUntil ?? 0, f.s.time + 3, accuracy: 1e-9)
                let own = f.s.units[a].hp
                for _ in 0..<Int(3.5 * Balance.tickRate) {
                    f.s.tick += 1
                    f.s.time = Double(f.s.tick) * Balance.dt
                    GearSystem.update(&f.s, f.ctx)
                }
                XCTAssertEqual(f.s.units[a].hp - own, total, accuracy: total / 30 + 1e-6, "3 秒かけて回復")
            default:
                XCTFail("\(option)")
            }
        }
    }

    func testSmiteTargetsHeroesOnlyAfterTheJungleBlessingUnlocks() {
        var (f, a) = blessed(.flame)
        let v = enemy(&f, at: spot + Vec2(200, 0))
        let k = f.hero(a).spells.firstIndex(of: Balance.Economy.smiteSpellID)!
        let hp = f.s.units[v].hp
        XCTAssertFalse(SpellSystem.cast(&f.s, f.ctx, heroIndex: a, spellIndex: k, target: .unit(f.id(v))))
        XCTAssertEqual(f.s.units[v].hp, hp, accuracy: 1e-9)
        f.s.units[a].hero!.score.monsterKills = Balance.Gear.jungleBlessingUnlockCount
        XCTAssertTrue(SpellSystem.cast(&f.s, f.ctx, heroIndex: a, spellIndex: k, target: .unit(f.id(v))))
        XCTAssertLessThan(f.s.units[v].hp, hp)
        XCTAssertFalse(gearStatus(f, v, "gear_smite").isEmpty)
    }

    // MARK: - ローム: 収入

    func testThrivingGoesOnlyToTheLowestGoldRoamer() {
        var (f, a) = blessed(.encourage, time: 300)     // tick 9000 = 共栄の tick
        let b = ally(f, a)
        give(&f, b, .favor)
        f.s.units[a].hero!.gold = 100
        f.s.units[b].hero!.gold = 500
        let xa = f.hero(a).xp, xb = f.hero(b).xp
        XCTAssertEqual(GearEffects.activeRoamer(f.s, team: .blue, master: f.master), a)
        GearSystem.update(&f.s, f.ctx)
        // 8:00 までは 6 Gold・12 EXP（共栄ゴールドに数える）
        XCTAssertEqual(f.hero(a).gold, 106, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).xp - xa, 12, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).gear?.roamGold ?? 0, 6, accuracy: 1e-9)
        XCTAssertEqual(f.hero(b).gold, 500, accuracy: 1e-9)
        XCTAssertEqual(f.hero(b).xp, xb, accuracy: 1e-9)
        XCTAssertEqual(f.hero(b).gear?.roamGold ?? 0, 0, accuracy: 1e-9)
        // 所持 Gold が逆転すると b が受け取る
        f.s.units[b].hero!.gold = 50
        let interval = Int((Balance.Gear.thrivingInterval * Balance.tickRate).rounded())
        f.s.tick += interval
        f.s.time = Double(f.s.tick) * Balance.dt
        GearSystem.update(&f.s, f.ctx)
        XCTAssertEqual(f.hero(b).gold, 56, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).gold, 106, accuracy: 1e-9)
        // 5 秒ごとの tick 以外では入らない
        f.s.tick += 1
        f.s.time = Double(f.s.tick) * Balance.dt
        GearSystem.update(&f.s, f.ctx)
        XCTAssertEqual(f.hero(b).gold, 56, accuracy: 1e-9)
        // 8:00 以降は 10 Gold・20 EXP
        f.s.tick = Int(Balance.Gear.roamPhaseEnd * Balance.tickRate)
        f.s.time = Double(f.s.tick) * Balance.dt
        let xb2 = f.hero(b).xp
        GearSystem.update(&f.s, f.ctx)
        XCTAssertEqual(f.hero(b).gold, 66, accuracy: 1e-9)
        XCTAssertEqual(f.hero(b).xp - xb2, 20, accuracy: 1e-9)
        // ローム持ちがいなければ誰にも入らない
        var (g, c) = blessed(nil, time: 300)
        let gold = g.hero(c).gold
        XCTAssertNil(GearEffects.activeRoamer(g.s, team: .blue, master: g.master))
        GearSystem.update(&g.s, g.ctx)
        XCTAssertEqual(g.hero(c).gold, gold, accuracy: 1e-9)
    }

    func testDevotionGivesTheRoamerThirtyPercentOfANearbyAllysMinionRewards() {
        var (f, a) = blessed(.encourage, time: 300)
        let b = ally(f, a)
        f.place(b, at: spot + Vec2(600, 0))
        let ga = f.hero(a).gold, gb = f.hero(b).gold
        let xa = f.hero(a).xp, xb = f.hero(b).xp
        f.kill(f.addMinion(.melee, team: .red, at: spot + Vec2(700, 0)), by: f.id(b))
        let bonus = DeathSystem.laneBonus(f.s, f.ctx, lane: .mid)
        let earned = Balance.Economy.minionGold(.melee, at: f.s.time) * bonus.gold
        XCTAssertEqual(f.hero(b).gold - gb, earned, accuracy: 1e-9, "味方の取り分は減らない")
        XCTAssertEqual(f.hero(a).gold - ga, earned * 0.3, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).gear?.roamGold ?? 0, earned * 0.3, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).gear?.devotionGold ?? 0, earned * 0.3, accuracy: 1e-9)
        // EXP: 味方は 1 人で倒した分を丸ごと、ローム持ちは別に 30%
        let xp = Balance.Economy.minionXP(.melee) * bonus.xp
        XCTAssertEqual(f.hero(b).xp - xb, xp, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).xp - xa, xp * 0.3, accuracy: 1e-9)
        // 遠く（1400 より外）の味方の稼ぎには付かない
        f.place(b, at: spot + Vec2(3000, 0))
        let ga2 = f.hero(a).gold, xa2 = f.hero(a).xp
        f.kill(f.addMinion(.melee, team: .red, at: spot + Vec2(3100, 0)), by: f.id(b))
        XCTAssertEqual(f.hero(a).gold, ga2, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).xp, xa2, accuracy: 1e-9)
        // 無私の Gold は累計 2000 まで
        f.place(b, at: spot + Vec2(600, 0))
        f.s.units[a].hero!.gear!.devotionGold = Balance.Gear.devotionGoldCap - 1
        let ga3 = f.hero(a).gold
        f.kill(f.addMinion(.melee, team: .red, at: spot + Vec2(700, 0)), by: f.id(b))
        XCTAssertEqual(f.hero(a).gold - ga3, 1, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).gear?.devotionGold ?? 0, Balance.Gear.devotionGoldCap, accuracy: 1e-9)
    }

    func testDevotionRewardsHittingEnemyHeroesEveryFifteenSeconds() {
        var (f, a) = blessed(.encourage, time: 300)
        let v = enemy(&f, at: spot + Vec2(200, 0))
        func poke() {
            CombatSystem.dealDamage(&f.s, f.ctx, sourceID: f.id(a), targetIndex: v, amount: 10, type: .physical,
                                    source: .skill(.skill1), isCrit: false, appliesOnHit: false)
        }
        let level = Double(f.hero(a).level)
        var gold = f.hero(a).gold
        let xp = f.hero(a).xp
        poke()
        XCTAssertEqual(f.hero(a).gold - gold, 30 + 2 * level, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).xp - xp, 20 + 8 * level, accuracy: 1e-9)
        XCTAssertEqual(f.hero(a).gear?.roamGold ?? 0, 30 + 2 * level, accuracy: 1e-9)
        // 15 秒に 1 回
        gold = f.hero(a).gold
        poke()
        XCTAssertEqual(f.hero(a).gold, gold, accuracy: 1e-9)
        f.s.time += Balance.Gear.devotionHitCooldown
        let level2 = Double(f.hero(a).level)
        poke()
        XCTAssertEqual(f.hero(a).gold - gold, 30 + 2 * level2, accuracy: 1e-9)
        // 収入を得るローム持ち（所持 Gold が最少）でなければ入らない
        let b = ally(f, a)
        give(&f, b, .favor)
        f.s.units[b].hero!.gold = 0
        f.s.time += Balance.Gear.devotionHitCooldown
        gold = f.hero(a).gold
        poke()
        XCTAssertEqual(f.hero(a).gold, gold, accuracy: 1e-9)
    }

    func testRoamBlessingDoesNotReduceOwnFarm() {
        var (f, a) = blessed(.encourage, time: 100)
        var gold = f.hero(a).gold
        f.kill(f.addMinion(.melee, team: .red, at: spot), by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - gold,
                       Balance.Economy.minionGold(.melee, at: f.s.time) * DeathSystem.laneBonus(f.s, f.ctx, lane: .mid).gold,
                       accuracy: 1e-9)
        gold = f.hero(a).gold
        f.kill(f.addMonster(.campLarge, at: spot), by: f.id(a))
        XCTAssertEqual(f.hero(a).gold - gold, Balance.Economy.monsterGold(.campLarge).rounded(), accuracy: 1e-9)
    }

    // MARK: - ローム: 祝福の能力（共栄ゴールド 1000 で解放）

    func testRoamBlessingUnlocksAtOneThousandRoamGoldAndEncourageAddsDefense() {
        XCTAssertEqual(Balance.Gear.blessingUnlockGold, 1000)
        XCTAssertEqual(GearEffects.roamStage(roamGold: 999), 0)
        XCTAssertEqual(GearEffects.roamStage(roamGold: 1000), 1)
        // tick 9030: 1 秒ごとの判定はあるが、共栄の tick ではない（共栄ゴールドが増えない）
        var (f, a) = blessed(.encourage, time: 301, roamGold: 999)
        XCTAssertFalse(GearEffects.roamBlessingUnlocked(f.hero(a)))
        let near = ally(f, a, 0), far = ally(f, a, 1)
        f.place(near, at: spot + Vec2(300, 0))
        f.place(far, at: spot + Vec2(1500, 0))
        StatCalculator.recompute(&f.s, near, f.ctx)
        let before = f.s.units[near].stats
        GearSystem.update(&f.s, f.ctx)
        XCTAssertTrue(gearStatus(f, a, "gear_encourage").isEmpty, "解放前は働かない")
        f.s.units[a].hero!.gear!.roamGold = 1000
        XCTAssertTrue(GearEffects.roamBlessingUnlocked(f.hero(a)))
        GearSystem.update(&f.s, f.ctx)
        for i in [a, near] {
            let st = gearStatus(f, i, "gear_encourage").first
            XCTAssertEqual(st?.kind, .flatDefenseMod)
            XCTAssertEqual(st?.magnitude ?? 0, 20, accuracy: 1e-9)
        }
        XCTAssertTrue(gearStatus(f, far, "gear_encourage").isEmpty, "700 より遠い味方には届かない")
        StatCalculator.recompute(&f.s, near, f.ctx)
        XCTAssertEqual(f.s.units[near].stats.armor, before.armor + 20, accuracy: 1e-9)
        XCTAssertEqual(f.s.units[near].stats.magicResist, before.magicResist + 20, accuracy: 1e-9)
    }

    func testConcealHidesNearbyAlliesUntilTheyFight() {
        var (f, a) = blessed(.conceal, time: 300, roamGold: 999)
        let near = ally(f, a, 0), far = ally(f, a, 1)
        f.place(near, at: spot + Vec2(300, 0))
        f.place(far, at: spot + Vec2(1500, 0))
        let v = enemy(&f, at: spot + Vec2(400, 0))
        let use = HeroCommand(heroID: f.id(a), command: .useGearActive)
        XCTAssertNil(GearSystem.activeCooldown(f.hero(a), time: f.s.time, master: f.master), "解放前は使えない")
        CommandSystem.apply([use], &f.s, f.ctx)
        XCTAssertFalse(f.s.units[a].has(.stealth))
        f.s.units[a].hero!.gear!.roamGold = 1000
        XCTAssertEqual(GearSystem.activeCooldown(f.hero(a), time: f.s.time, master: f.master) ?? -1, 0, accuracy: 1e-9)
        CommandSystem.apply([use], &f.s, f.ctx)
        for i in [a, near] {
            XCTAssertEqual(gearStatus(f, i, "gear_conceal").first { $0.kind == .stealth }?.remaining ?? 0, 5, accuracy: 1e-9)
            XCTAssertEqual(gearStatus(f, i, "gear_conceal").first { $0.kind == .speedBoost }?.magnitude ?? 0, 0.4,
                           accuracy: 1e-9)
        }
        XCTAssertTrue(gearStatus(f, far, "gear_conceal").isEmpty)
        XCTAssertEqual(GearSystem.activeCooldown(f.hero(a), time: f.s.time, master: f.master) ?? 0, 60, accuracy: 1e-9)
        // ダメージを与えると自分の隠蔽が解ける（味方は残る）
        CombatSystem.dealDamage(&f.s, f.ctx, sourceID: f.id(a), targetIndex: v, amount: 10, type: .physical,
                                source: .skill(.skill1), isCrit: false, appliesOnHit: false)
        XCTAssertTrue(gearStatus(f, a, "gear_conceal").isEmpty)
        XCTAssertFalse(gearStatus(f, near, "gear_conceal").isEmpty)
        // 敵ヒーローからダメージを受けると解ける
        CombatSystem.dealDamage(&f.s, f.ctx, sourceID: f.id(v), targetIndex: near, amount: 10, type: .physical,
                                source: .skill(.skill1), isCrit: false, appliesOnHit: false)
        XCTAssertTrue(gearStatus(f, near, "gear_conceal").isEmpty)
        // CD 中は使えない
        CommandSystem.apply([use], &f.s, f.ctx)
        XCTAssertFalse(f.s.units[a].has(.stealth))
    }

    func testFavorHealsTheLowestAllyWhenHealingAnAlly() {
        var (f, a) = blessed(.favor, time: 300, roamGold: 1000)
        let low = ally(f, a, 0), mid = ally(f, a, 1)
        f.place(low, at: spot + Vec2(200, 0))
        f.place(mid, at: spot + Vec2(0, 300))
        f.s.units[low].hp = f.s.units[low].stats.maxHP * 0.3
        f.s.units[mid].hp = f.s.units[mid].stats.maxHP * 0.5
        var lowHP = f.s.units[low].hp
        CombatSystem.heal(&f.s, f.ctx, sourceID: f.id(a), targetIndex: mid, amount: 100)
        XCTAssertEqual(f.s.units[low].hp - lowHP, 400, accuracy: 1e-6, "周りで最も HP の低い味方を 400 回復")
        XCTAssertEqual(f.hero(a).gear?.abilityReadyAt ?? 0, f.s.time + 15, accuracy: 1e-9)
        // CD 15 秒
        lowHP = f.s.units[low].hp
        CombatSystem.heal(&f.s, f.ctx, sourceID: f.id(a), targetIndex: mid, amount: 100)
        XCTAssertEqual(f.s.units[low].hp, lowHP, accuracy: 1e-9)
        // 自分への回復では働かない
        f.s.time += 15
        f.s.units[a].hp = f.s.units[a].stats.maxHP * 0.5
        CombatSystem.heal(&f.s, f.ctx, sourceID: f.id(a), targetIndex: a, amount: 100)
        XCTAssertEqual(f.s.units[low].hp, lowHP, accuracy: 1e-9)
        // 解放前は働かない
        f.s.units[a].hero!.gear!.roamGold = 999
        CombatSystem.heal(&f.s, f.ctx, sourceID: f.id(a), targetIndex: mid, amount: 100)
        XCTAssertEqual(f.s.units[low].hp, lowHP, accuracy: 1e-9)
    }

    func testDireHitStoresForceWhileMovingAndSpendsItOnAnEnemyHero() {
        var (f, a) = blessed(.direHit, time: 300, roamGold: 1000)
        f.s.tick += 1                     // 共栄・1 秒ごとの判定の tick を避ける
        let speed = f.s.units[a].stats.moveSpeed
        func walk(_ steps: Int) {
            for _ in 0..<steps {
                f.s.units[a].prevPos = f.s.units[a].pos
                f.s.units[a].pos.y += 300
                GearSystem.update(&f.s, f.ctx)
            }
        }
        walk(10)                          // 1 マス（100）につき 1
        XCTAssertEqual(f.hero(a).gear?.force ?? 0, 30, accuracy: 1e-9)
        XCTAssertEqual(f.s.units[a].stats.moveSpeed, speed + 30, accuracy: 1e-6, "フォース 1 につき移動速度 +1")
        walk(10)
        XCTAssertEqual(f.hero(a).gear?.force ?? 0, 40, accuracy: 1e-9, "最大 40")
        // 敵ヒーローへのダメージでフォースを全部使い、フォース × 7.5 の確定ダメージ
        let v = enemy(&f, at: f.s.units[a].pos + Vec2(200, 0))
        var hp = f.s.units[v].hp
        CombatSystem.dealDamage(&f.s, f.ctx, sourceID: f.id(a), targetIndex: v, amount: 10, type: .trueDamage,
                                source: .skill(.skill1), isCrit: false, appliesOnHit: false)
        XCTAssertEqual(hp - f.s.units[v].hp, 10 + 40 * 7.5, accuracy: 1e-6)
        XCTAssertEqual(f.hero(a).gear?.force ?? -1, 0, accuracy: 1e-9)
        // 20 未満では使わない
        f.s.units[a].hero!.gear!.force = 19
        hp = f.s.units[v].hp
        CombatSystem.dealDamage(&f.s, f.ctx, sourceID: f.id(a), targetIndex: v, amount: 10, type: .trueDamage,
                                source: .skill(.skill1), isCrit: false, appliesOnHit: false)
        XCTAssertEqual(hp - f.s.units[v].hp, 10, accuracy: 1e-6)
        // 解放前は溜まらない
        var (g, b) = blessed(.direHit, time: 300, roamGold: 0)
        g.s.tick += 1
        for _ in 0..<5 {
            g.s.units[b].prevPos = g.s.units[b].pos
            g.s.units[b].pos.y += 300
            GearSystem.update(&g.s, g.ctx)
        }
        XCTAssertEqual(g.hero(b).gear?.force ?? 0, 0, accuracy: 1e-9)
    }
}
