import XCTest
@testable import VelstriaCore

/// 装備の固有効果（Mobile Legends の装備の固有パッシブ・アクティブ。Systems/ItemEffects.swift）。
/// 係数は tools/equipment_spec.mjs の `v`（各テストの見出しのコメントに写した）。
final class ItemEffectsTests: XCTestCase {
    private let spot = Vec2(6000, 6000)

    /// 1v1（blue の攻撃側 a と red の受け側 v）。キット・ルーン・自動習得を外す。
    /// 受け側は防御・魔防・被ダメ軽減 0、最大 HP 20000（ダメージがそのまま通り、倒れない）。受け側を計算し直すと元に戻る。
    private func duel(_ attackerItems: [String] = [], victimItems: [String] = [], attacker: String = "H002",
                      victim: String = "H008", level: Int = 1) -> (EconomyFixture, Int, Int) {
        let players = [
            PlayerSlot(team: .blue, heroID: attacker, controller: .human, position: .mid, displayName: "A",
                       autoLevelSkills: false),
            PlayerSlot(team: .red, heroID: victim, controller: .human, position: .mid, displayName: "V",
                       autoLevelSkills: false),
        ]
        var f = EconomyFixture(config: MatchConfig(mode: .standard, seed: 1, players: players))
        let a = f.heroes(.blue)[0], v = f.heroes(.red)[0]
        f.place(a, at: spot)
        f.place(v, at: spot + Vec2(150, 0))
        for (i, items) in [(a, attackerItems), (v, victimItems)] {
            let invested = items.map { MasterData.shared.item($0)?.priceGold ?? 0 }
            f.s.units[i].hero!.kit = nil
            f.s.units[i].hero!.runes = []
            f.s.units[i].hero!.level = level
            f.s.units[i].hero!.items = items
            f.s.units[i].hero!.itemInvested = invested
            StatCalculator.recompute(&f.s, i, f.ctx)
            f.s.units[i].hp = f.s.units[i].stats.maxHP
        }
        bare(&f, v)
        f.s.events.removeAll()
        return (f, a, v)
    }

    /// 防御・魔防・被ダメ軽減 0、最大 HP・HP を hp に。
    private func bare(_ f: inout EconomyFixture, _ i: Int, hp: Double = 20_000) {
        f.s.units[i].stats.armor = 0
        f.s.units[i].stats.magicResist = 0
        f.s.units[i].stats.damageReduction = 0
        f.s.units[i].stats.maxHP = hp
        f.s.units[i].hp = hp
    }

    /// from → to のダメージ（既定はスキル 1）。戻り値 = 実ダメージ。
    @discardableResult
    private func hit(_ f: inout EconomyFixture, _ from: Int, _ to: Int, _ raw: Double, _ type: DamageType,
                     _ source: DamageSource = .skill(.skill1)) -> Double {
        CombatSystem.dealDamage(&f.s, f.ctx, sourceID: f.id(from), targetIndex: to, amount: raw, type: type,
                                source: source, isCrit: false, appliesOnHit: false)
    }

    /// 通常攻撃の命中後の装備効果だけを起こす（通常攻撃のダメージ自体は与えない）。
    private func land(_ f: inout EconomyFixture, _ a: Int, _ t: Int, crit: Bool = false) {
        ItemEffects.onBasicAttackLanded(&f.s, f.ctx, attacker: a, target: t, dealt: 0, isCrit: crit)
    }

    /// 通常攻撃（ダメージ + 命中後の装備効果）。
    private func basicAttack(_ f: inout EconomyFixture, _ a: Int, _ t: Int, raw: Double) {
        let dealt = CombatSystem.dealDamage(&f.s, f.ctx, sourceID: f.id(a), targetIndex: t, amount: raw, type: .physical,
                                            source: .basicAttack, isCrit: false, appliesOnHit: true)
        ItemEffects.onBasicAttackLanded(&f.s, f.ctx, attacker: a, target: t, dealt: dealt)
    }

    /// 時間を進める。heroes の装備の毎 tick 処理（ItemEffects.update）も回す。
    private func advance(_ f: inout EconomyFixture, _ seconds: Double, update heroes: [Int] = []) {
        for _ in 0..<Int((seconds * Balance.tickRate).rounded()) {
            f.s.tick += 1
            f.s.time = Double(f.s.tick) * Balance.dt
            for i in heroes { ItemEffects.update(&f.s, f.ctx, hero: i) }
        }
    }

    private func itemDamageEvents(_ f: EconomyFixture, to i: Int) -> [DamageEvent] {
        f.s.events.compactMap {
            if case .damage(let d) = $0, d.targetID == f.id(i), d.source == .item { return d }
            return nil
        }
    }

    /// 装備の追加ダメージ（DamageSource.item）の合計。
    private func itemDamage(_ f: EconomyFixture, to i: Int) -> Double {
        itemDamageEvents(f, to: i).reduce(0) { $0 + $1.amount }
    }

    private func status(_ f: EconomyFixture, _ i: Int, _ tag: String) -> StatusEffect? {
        f.s.units[i].statuses.first { $0.tag == tag }
    }

    private func runtime(_ f: EconomyFixture, _ i: Int) -> ItemRuntime { f.s.units[i].hero!.itemRuntime }

    /// 防御 0・HP の多いミニオン。
    private func addMinion(_ f: inout EconomyFixture, near p: Vec2, hp: Double = 5000) -> Int {
        let m = f.addMinion(.melee, team: .red, at: p)
        f.s.units[m].stats.maxHP = hp
        f.s.units[m].baseStats.maxHP = hp
        f.s.units[m].hp = hp
        return m
    }

    // MARK: - 貫通

    func testArmorBusterAndBreakerAddPercentPenetration() {
        var (f, a, v) = duel(["EQ112"])    // スピリットシャウト: 撃砕 30% + 破壊者 [0.001, 0.3]
        XCTAssertEqual(f.s.units[a].stats.armorPenPct, 0.30, accuracy: 1e-9)
        f.s.units[v].stats.armor = 100
        // 30% + 防御 100 × 0.1% = 40% → 防御 60
        XCTAssertEqual(hit(&f, a, v, 1000, .physical), 1000 * 100 / 160, accuracy: 1e-6)
        // 防御 400: 破壊者は +30% で頭打ち → 60% → 160
        f.s.units[v].stats.armor = 400
        XCTAssertEqual(hit(&f, a, v, 1000, .physical), 1000 * 100 / 260, accuracy: 1e-6)
        // 魔法ダメージには効かない
        f.s.units[v].stats.magicResist = 100
        XCTAssertEqual(hit(&f, a, v, 1000, .magic), 500, accuracy: 1e-6)
    }

    func testFlatPenetrationAppliesAfterPercentAndStopsAtZero() {
        // マジックガン・スピリットシャウトの撃砕（重ならない）+ 破壊者 + ハンターストライクの固有の固定貫通 15
        var (f, a, v) = duel(["EQ101", "EQ112", "EQ105"])
        XCTAssertEqual(f.s.units[a].stats.armorPenPct, 0.30, accuracy: 1e-9)
        XCTAssertEqual(f.s.units[a].stats.armorPenFlat, 15, accuracy: 1e-9)
        f.s.units[v].stats.armor = 100
        // 100 × (1 − 0.4) − 15 = 45
        XCTAssertEqual(hit(&f, a, v, 1000, .physical), 1000 * 100 / 145, accuracy: 1e-6)
        f.s.units[v].stats.armor = 10
        XCTAssertEqual(hit(&f, a, v, 1000, .physical), 1000, accuracy: 1e-6)
    }

    func testSpellbreakerAndMagicPenetration() {
        // 魔法の聖剣: 魔法貫通 40% + 魔法破り [0.001, 0.2]。アーケインブーツ: 魔法貫通 +10
        var (f, a, v) = duel(["EQ211", "EQ404"], attacker: "H004")
        XCTAssertEqual(f.s.units[a].stats.magicPenPct, 0.40, accuracy: 1e-9)
        XCTAssertEqual(f.s.units[a].stats.magicPenFlat, 10, accuracy: 1e-9)
        f.s.units[v].stats.magicResist = 100
        // 100 × (1 − 0.5) − 10 = 40
        XCTAssertEqual(hit(&f, a, v, 1000, .magic), 1000 * 100 / 140, accuracy: 1e-6)
        // 300 × (1 − 0.6) − 10 = 110（魔法破りは +20% で頭打ち）
        f.s.units[v].stats.magicResist = 300
        XCTAssertEqual(hit(&f, a, v, 1000, .magic), 1000 * 100 / 210, accuracy: 1e-6)
        // 物理には効かない。確定ダメージは防御を無視
        f.s.units[v].stats.armor = 100
        XCTAssertEqual(hit(&f, a, v, 1000, .physical), 500, accuracy: 1e-6)
        XCTAssertEqual(hit(&f, a, v, 500, .trueDamage), 500, accuracy: 1e-6)
    }

    // MARK: - スキルの後の通常攻撃

    func testDivineJusticeAddsTrueDamageAndHealOncePerSkillWindow() {
        var (f, a, v) = duel(["EQ109"])   // エンドレスバトル [0.6, 3, 1.5, 80, 0.4]
        let attack = f.s.units[a].stats.attack
        f.s.units[a].hp = f.s.units[a].stats.maxHP * 0.4
        var hp = f.s.units[v].hp
        // スキルを使っていなければ働かない
        land(&f, a, v)
        XCTAssertEqual(f.s.units[v].hp, hp, accuracy: 1e-9)
        // スキル後の次の通常攻撃: 物理攻撃の 60% の確定ダメージと、80（+物理攻撃の 40%）の回復
        ItemEffects.onSkillCast(&f.s, f.ctx, caster: a, slot: .skill1)
        let own = f.s.units[a].hp
        land(&f, a, v)
        XCTAssertEqual(hp - f.s.units[v].hp, attack * 0.6, accuracy: 1e-6)
        XCTAssertEqual(f.s.units[a].hp - own, 80 + attack * 0.4, accuracy: 1e-6)
        // 1 つの窓で 1 回だけ
        hp = f.s.units[v].hp
        land(&f, a, v)
        XCTAssertEqual(f.s.units[v].hp, hp, accuracy: 1e-9)
        // CD 1.5 秒の間は、スキルを使い直しても働かない
        advance(&f, 1)
        ItemEffects.onSkillCast(&f.s, f.ctx, caster: a, slot: .skill2)
        land(&f, a, v)
        XCTAssertEqual(f.s.units[v].hp, hp, accuracy: 1e-9)
        // CD が明ければ、同じ窓（スキルから 3 秒以内）の通常攻撃で働く
        advance(&f, 1)
        land(&f, a, v)
        XCTAssertEqual(hp - f.s.units[v].hp, attack * 0.6, accuracy: 1e-6)
        // 窓（3 秒）を過ぎた通常攻撃では働かない
        advance(&f, 1)
        ItemEffects.onSkillCast(&f.s, f.ctx, caster: a, slot: .skill1)
        advance(&f, 3.2)
        hp = f.s.units[v].hp
        land(&f, a, v)
        XCTAssertEqual(f.s.units[v].hp, hp, accuracy: 1e-9)
        ItemEffects.onSkillCast(&f.s, f.ctx, caster: a, slot: .skill1)
        land(&f, a, v)
        XCTAssertEqual(hp - f.s.units[v].hp, attack * 0.6, accuracy: 1e-6)
    }

    func testJudgementAndCrisisAfterASkill() {
        // アズールブレイド（素材）: 審判 [50, 3, 1.5] → 50 の確定ダメージ
        var (f, a, v) = duel(["EQ217"])
        var hp = f.s.units[v].hp
        ItemEffects.onSkillCast(&f.s, f.ctx, caster: a, slot: .skill1)
        land(&f, a, v)
        XCTAssertEqual(hp - f.s.units[v].hp, 50, accuracy: 1e-9)
        // 星の大鎌: 危機 [90, 0.6, 3, 1.5, 0.15, 1.5] → 90（+魔法攻撃の 60%）の確定ダメージと 15% 減速 1.5 秒
        var (g, b, w) = duel(["EQ206"], attacker: "H004")
        let power = g.s.units[b].stats.abilityPower
        hp = g.s.units[w].hp
        ItemEffects.onSkillCast(&g.s, g.ctx, caster: b, slot: .ultimate)
        land(&g, b, w)
        XCTAssertEqual(hp - g.s.units[w].hp, 90 + 0.6 * power, accuracy: 1e-6)
        let slow = status(g, w, "item.crisis")
        XCTAssertEqual(slow?.kind, .slow)
        XCTAssertEqual(slow?.magnitude ?? 0, 0.15, accuracy: 1e-9)
        XCTAssertEqual(slow?.remaining ?? 0, 1.5, accuracy: 1e-9)
    }

    // MARK: - 攻撃の固有効果

    func testDespairBoostsDamageAgainstLowHealthNonMinions() {
        var (f, a, v) = duel(["EQ106"])   // ディスペアブレイド [0.5, 0.25, 2]
        let attack = f.s.units[a].stats.attack
        f.s.units[v].hp = 16_000
        XCTAssertEqual(hit(&f, a, v, 1000, .physical), 1000, accuracy: 1e-6)
        XCTAssertEqual(runtime(f, a).until(.despair), 0)
        // HP 50% 未満: その一撃から +25%、2 秒間 物理攻撃 +25%
        f.s.units[v].hp = 8_000
        XCTAssertEqual(hit(&f, a, v, 1000, .physical), 1250, accuracy: 1e-6)
        XCTAssertEqual(runtime(f, a).until(.despair), f.s.time + 2, accuracy: 1e-9)
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.attack, attack * 1.25, accuracy: 1e-6)
        // 強化中は能力値の側で増えるので、ダメージには重ねない
        XCTAssertEqual(hit(&f, a, v, 1000, .physical), 1000, accuracy: 1e-6)
        advance(&f, 2.1)
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.attack, attack, accuracy: 1e-6)
        // ミニオンには働かない
        let m = addMinion(&f, near: f.s.units[v].pos, hp: 1000)
        f.s.units[m].hp = 100
        XCTAssertEqual(hit(&f, a, m, 50, .physical, .basicAttack), 50, accuracy: 1e-6)
        XCTAssertLessThanOrEqual(runtime(f, a).until(.despair), f.s.time)
    }

    func testAmbushArmsAfterFiveQuietSecondsAndEmpowersOneBasicAttack() {
        var (f, a, v) = duel(["EQ107"])   // オーシャンエッジ [5, 160, 0.4, 0.4, 1.5]
        let attack = f.s.units[a].stats.attack
        ItemEffects.update(&f.s, f.ctx, hero: a)
        XCTAssertGreaterThan(runtime(f, a).until(.ambush), f.s.time, "構えた")
        var hp = f.s.units[v].hp
        basicAttack(&f, a, v, raw: 100)
        XCTAssertEqual(hp - f.s.units[v].hp, 100 + 160 + 0.4 * attack, accuracy: 1e-6)
        let slow = status(f, v, "item.ambush")
        XCTAssertEqual(slow?.magnitude ?? 0, 0.4, accuracy: 1e-9)
        XCTAssertEqual(slow?.remaining ?? 0, 1.5, accuracy: 1e-9)
        // 1 回で解け、ヒーローとのやり取りから 5 秒たつまで構え直さない
        hp = f.s.units[v].hp
        basicAttack(&f, a, v, raw: 100)
        XCTAssertEqual(hp - f.s.units[v].hp, 100, accuracy: 1e-6)
        advance(&f, 4, update: [a])
        XCTAssertLessThanOrEqual(runtime(f, a).until(.ambush), f.s.time)
        advance(&f, 1.1, update: [a])
        XCTAssertGreaterThan(runtime(f, a).until(.ambush), f.s.time, "5 秒たつと構え直す")
        // ヒーローからダメージを受けると解ける
        hit(&f, v, a, 10, .physical)
        XCTAssertLessThanOrEqual(runtime(f, a).until(.ambush), f.s.time)
    }

    func testTyphoonHitsUpToThreeEnemiesAndRechargesFasterWithAttacks() {
        var (f, a, v) = duel(["EQ108"])   // ウィンドテラー [5, 0.2, 2, 3, 2, 450]
        let p = f.s.units[v].pos
        let minions = (0..<3).map { k in addMinion(&f, near: p + Vec2(Double(k) * 50, 60)) }
        f.s.units[a].stats.attackSpeed = 2
        land(&f, a, v)
        // 攻撃速度 2 → 106 × 2 + 44 = 256 の魔法ダメージ。ミニオンには 2 倍。対象は最大 3 体
        XCTAssertEqual(itemDamage(f, to: v), 256, accuracy: 1e-6)
        XCTAssertEqual(itemDamage(f, to: minions[0]), 512, accuracy: 1e-6)
        XCTAssertEqual(itemDamage(f, to: minions[1]), 512, accuracy: 1e-6)
        XCTAssertEqual(itemDamage(f, to: minions[2]), 0, accuracy: 1e-6)
        // 次は 5 秒後。通常攻撃 1 回で 0.2 秒縮み、最短 2 秒
        let fired = f.s.time
        XCTAssertEqual(runtime(f, a).readyTime(.typhoon), fired + 5, accuracy: 1e-9)
        f.s.events.removeAll()
        for _ in 0..<20 { land(&f, a, v) }
        XCTAssertEqual(itemDamage(f, to: v), 0)
        XCTAssertEqual(runtime(f, a).readyTime(.typhoon), fired + 2, accuracy: 1e-9)
        advance(&f, 2)
        f.s.units[a].stats.attackSpeed = 4
        f.s.events.removeAll()
        land(&f, a, v)
        XCTAssertEqual(itemDamage(f, to: v), 362, accuracy: 1e-6, "攻撃速度 3 以上で最大 362")
        // 下限 150。クリティカルなら倍率が掛かる
        advance(&f, 5)
        f.s.units[a].stats.attackSpeed = 0.5
        f.s.events.removeAll()
        land(&f, a, v, crit: true)
        XCTAssertEqual(itemDamage(f, to: v), 150 * f.s.units[a].stats.critMultiplier, accuracy: 1e-6)
    }

    func testDoomAddsTrueDamageOnCriticalBasicAttacks() {
        var (f, a, v) = duel(["EQ110"])   // バーサーク [0.12]、固有のクリティカルダメージ +30%
        let st = f.s.units[a].stats
        XCTAssertEqual(st.critMultiplier, f.s.units[a].baseStats.critMultiplier + 0.30, accuracy: 1e-9)
        let hp = f.s.units[v].hp
        land(&f, a, v)
        XCTAssertEqual(f.s.units[v].hp, hp, accuracy: 1e-9)
        land(&f, a, v, crit: true)
        XCTAssertEqual(hp - f.s.units[v].hp, st.attack * st.critMultiplier * 0.12, accuracy: 1e-6)
    }

    func testCorrosiveSlowAndImpulseStacks() {
        var (f, a, v) = duel(["EQ119"])   // ラスティサイズ: 腐食 [80, 0.08, 0.5, 1.5, 5]、衝動 [0.06, 3, 5]
        let speed = f.s.units[a].stats.attackSpeed
        let hp = f.s.units[v].hp
        for _ in 0..<6 { land(&f, a, v) }
        XCTAssertEqual(hp - f.s.units[v].hp, 80 * 6, accuracy: 1e-6)
        XCTAssertEqual(status(f, v, "item.corrosive")?.magnitude ?? 0, 0.40, accuracy: 1e-9, "8% × 5 回まで")
        XCTAssertEqual(status(f, v, "item.corrosive")?.remaining ?? 0, 1.5, accuracy: 1e-9)
        XCTAssertEqual(runtime(f, a).stack(.impulse), 5)
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.attackSpeed, speed * 1.30, accuracy: 1e-9)
        advance(&f, 3.1)
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.attackSpeed, speed, accuracy: 1e-9, "3 秒で切れる")
        // 遠隔は減速が半分（4% × 5）
        var (g, b, w) = duel(["EQ119"], attacker: "H003")
        for _ in 0..<6 { land(&g, b, w) }
        XCTAssertEqual(status(g, w, "item.corrosive")?.magnitude ?? 0, 0.20, accuracy: 1e-9)
        // スイフトクロスボウ（Tier 2: 衝動 3%）と重ねても、Tier の高い方の 1 つだけ
        let (h, c, _) = duel(["EQ126", "EQ119"])
        XCTAssertEqual(ItemEffects.values(.impulse, of: h.s.units[c], h.master), [0.06, 3, 5])
        XCTAssertEqual(ItemEffects.active(h.s.units[c], h.master).filter { $0.kind == .impulse }.count, 1)
    }

    func testEngulfAndDevourOnBasicAttacks() {
        var (f, a, v) = duel(["EQ120"], level: 5)   // デモンハント: 侵食 [0.08, 60]、貪食 [10, 4, 0.5]
        f.s.units[v].hp = 5000
        f.s.units[a].hp = 100
        land(&f, a, v)
        XCTAssertEqual(f.s.units[v].hp, 5000 - 400, accuracy: 1e-6, "現在 HP の 8%")
        XCTAssertEqual(f.s.units[a].hp, 100 + 10 + 4 * 5, accuracy: 1e-6)
        // ミニオンには最大 60、回復は半分
        let m = addMinion(&f, near: f.s.units[v].pos, hp: 5000)
        f.s.units[a].hp = 100
        land(&f, a, m)
        XCTAssertEqual(f.s.units[m].hp, 5000 - 60, accuracy: 1e-6)
        XCTAssertEqual(f.s.units[a].hp, 100 + 15, accuracy: 1e-6)
    }

    func testGoldenStaffTurnsCritIntoAttackSpeedAndRepeatsOnHitEffects() {
        // 迅速 [1, ...]: クリティカル率 1% → 攻撃速度 +1%（クリティカルは出ない）。ジャベリン: クリティカル率 8%
        let (f, a, _) = duel(["EQ118", "EQ131"])
        let base = HeroGrowth.baseStats(def: f.master.hero("H002")!, level: 1)
        XCTAssertEqual(f.s.units[a].stats.critChance, 0, accuracy: 1e-9)
        XCTAssertEqual(f.s.units[a].stats.attackSpeed,
                       min(Balance.maxAttackSpeed, base.attackSpeed * 1.15 * (1 + base.critChance + 0.08)), accuracy: 1e-9)
        // 無尽の打撃: クリティカルでない通常攻撃 2 回ごとに、次の通常攻撃の命中時効果が 2 回多く働く
        var (g, b, w) = duel(["EQ118", "EQ119"])
        var hp = g.s.units[w].hp
        var dealt: [Double] = []
        for _ in 0..<4 {
            land(&g, b, w)
            dealt.append(hp - g.s.units[w].hp)
            hp = g.s.units[w].hp
        }
        XCTAssertEqual(dealt.map { $0.rounded() }, [80, 80, 240, 80], "腐食（80）が 3 回目だけ 3 回")
    }

    func testMaleficEnergyAndDragonScaleAreStatEffects() {
        // マジックガン: 通常攻撃の射程 +12%
        let (f, a, _) = duel(["EQ101"])
        let range = HeroGrowth.baseStats(def: f.master.hero("H002")!, level: 1).attackRange
        XCTAssertEqual(f.s.units[a].stats.attackRange, range * 1.12, accuracy: 1e-6)
        // デモンフォール: 追加の物理攻撃 4 につき混合防御 +1（最大 50）。ファイター以外は半分
        let (g, b, _) = duel(["EQ104", "EQ106"])    // ファイター（H002）: 追加攻撃 30 + 160 → +47.5
        let gb = g.s.units[b].baseStats
        XCTAssertEqual(g.s.units[b].stats.armor - gb.armor, 190 * 0.25, accuracy: 1e-6)
        XCTAssertEqual(g.s.units[b].stats.magicResist - gb.magicResist, 190 * 0.25, accuracy: 1e-6)
        let (h, c, _) = duel(["EQ104", "EQ106", "EQ125"], attacker: "H006")   // アサシン: min(50, 250 / 4) × 0.5 = 25
        XCTAssertEqual(h.s.units[c].stats.armor - h.s.units[c].baseStats.armor, 25, accuracy: 1e-6)
    }

    func testLifebaneCutsHealingAndPunishHitsBulkierHeroes() {
        var (f, a, v) = duel(["EQ103"])   // トライデント: 生命の災い [0.4, 3]、懲罰 [0.08]
        hit(&f, a, v, 100, .physical)
        let cut = status(f, v, "item.lifebane")
        XCTAssertEqual(cut?.kind, .healReduction)
        XCTAssertEqual(cut?.magnitude ?? 0, 0.4, accuracy: 1e-9)
        XCTAssertEqual(cut?.remaining ?? 0, 3, accuracy: 1e-9)
        StatCalculator.recompute(&f.s, v, f.ctx)
        f.s.units[v].hp = 100
        XCTAssertEqual(CombatSystem.heal(&f.s, f.ctx, sourceID: f.id(v), targetIndex: v, amount: 1000), 600, accuracy: 1e-6)
        // 懲罰: 自分より追加 HP が多い敵ヒーローへのダメージ +8%
        f.s.units[v].statuses.removeAll()
        f.s.units[v].hp = f.s.units[v].stats.maxHP
        f.s.units[v].stats.damageReduction = 0
        XCTAssertEqual(hit(&f, a, v, 1000, .trueDamage), 1000, accuracy: 1e-6, "追加 HP が同じ（0）なら働かない")
        f.s.units[v].hero!.items = ["EQ309"]
        StatCalculator.recompute(&f.s, v, f.ctx)
        f.s.units[v].hp = f.s.units[v].stats.maxHP
        f.s.units[v].stats.damageReduction = 0
        XCTAssertEqual(hit(&f, a, v, 1000, .trueDamage), 1080, accuracy: 1e-6)
    }

    func testSkyPiercerExecutesLowHealthHeroesThroughShields() {
        var (f, a, v) = duel(["EQ115"])   // 天空の刃 [0.04, 0.001, 10, 0.3, 80]
        f.s.units[v].hp = 1000            // 5%
        hit(&f, a, v, 100, .trueDamage)
        XCTAssertTrue(f.s.units[v].isAlive, "4.5% は残る")
        hit(&f, a, v, 200, .trueDamage)
        XCTAssertFalse(f.s.units[v].isAlive, "4% 未満で倒れる")
        XCTAssertEqual(f.s.pendingDeaths.last?.victimID, f.id(v))
        XCTAssertEqual(f.s.pendingDeaths.last?.killerID, f.id(a))
        // シールドを無視する
        var (g, b, w) = duel(["EQ115"])
        g.s.units[w].hp = 600             // 3%
        CombatSystem.addShield(&g.s, g.ctx, sourceID: g.id(w), targetIndex: w, amount: 100_000, duration: 10)
        hit(&g, b, w, 1, .trueDamage)
        XCTAssertFalse(g.s.units[w].isAlive)
        // キルで 10 ずつ（最大 80）、1 につき しきい値 +0.1%。倒されると 30% を失う
        for _ in 0..<9 { ItemEffects.onKill(&g.s, g.ctx, hero: b) }
        XCTAssertEqual(runtime(g, b).stack(.lethality), 80)
        ItemEffects.onHeroDeath(&g.s, g.ctx, hero: b)
        XCTAssertEqual(runtime(g, b).stack(.lethality), 56)
        // 56 → しきい値 9.6%
        var (h, c, x) = duel(["EQ115"])
        h.s.units[c].hero!.itemRuntime.setStack(.lethality, 56)
        h.s.units[x].hp = 2000            // 10%
        hit(&h, c, x, 100, .trueDamage)   // 9.5%
        XCTAssertFalse(h.s.units[x].isAlive)
    }

    func testWarAxeFightingSpiritStacksOncePerSecond() {
        var (f, a, v) = duel(["EQ116"])   // 常勝の神斧 [12, 4, 6, 0.1, 0.5, 1]
        let attack = f.s.units[a].stats.attack
        for _ in 0..<5 {
            hit(&f, a, v, 100, .physical)
            hit(&f, a, v, 100, .physical)     // 1 秒に 1 回まで
            advance(&f, 1)
        }
        XCTAssertEqual(runtime(f, a).stack(.fightingSpirit), 5)
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.attack, attack + 60, accuracy: 1e-6)
        // 6 回目で最大: 与えたダメージの 10% の確定ダメージを追加
        let hp = f.s.units[v].hp
        hit(&f, a, v, 100, .physical)
        XCTAssertEqual(hp - f.s.units[v].hp, 100 + 10, accuracy: 1e-6)
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.attack, attack + 72, accuracy: 1e-6)
        // 4 秒で切れる
        advance(&f, 4.1)
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.attack, attack, accuracy: 1e-6)
        // 射手は半分
        var (g, b, w) = duel(["EQ116"], attacker: "H003")
        let rangerAttack = g.s.units[b].stats.attack
        for _ in 0..<5 {
            hit(&g, b, w, 100, .physical)
            advance(&g, 1)
        }
        let hp2 = g.s.units[w].hp
        hit(&g, b, w, 100, .physical)
        XCTAssertEqual(hp2 - g.s.units[w].hp, 100 + 5, accuracy: 1e-6)
        StatCalculator.recompute(&g.s, b, g.ctx)
        XCTAssertEqual(g.s.units[b].stats.attack, rangerAttack + 36, accuracy: 1e-6)
    }

    // MARK: - 魔法の固有効果

    func testScorchBurnsForThreeSecondsAfterMagicDamage() {
        var (f, a, v) = duel(["EQ207"], attacker: "H004")   // ヒートロッド: 焼灼 [3, 0.01]
        hit(&f, a, v, 100, .physical)
        XCTAssertTrue(runtime(f, a).marks.isEmpty, "物理では燃えない")
        hit(&f, a, v, 100, .magic)
        f.s.events.removeAll()
        advance(&f, 4, update: [a])
        XCTAssertEqual(itemDamageEvents(f, to: v).count, 3, "1 秒ごとに 3 回")
        XCTAssertEqual(itemDamage(f, to: v), 20_000 * 0.01 * 3, accuracy: 1e-6)
        XCTAssertTrue(runtime(f, a).marks.isEmpty, "期限が切れた印は消える")
    }

    func testGeniusWandShredsMagicDefenseInStacks() {
        var (f, a, v) = duel(["EQ203"], attacker: "H004", level: 3)   // ジーニアスワンド [2.5, 0.5, 3, 2] → Lv3 で 1 回 4
        StatCalculator.recompute(&f.s, v, f.ctx)
        let resist = f.s.units[v].stats.magicResist
        bare(&f, v)
        hit(&f, a, v, 10, .physical)
        XCTAssertNil(status(f, v, "item.geniusShred"), "物理では下がらない")
        for _ in 0..<4 { hit(&f, a, v, 10, .magic) }
        let shred = status(f, v, "item.geniusShred")
        XCTAssertEqual(shred?.kind, .magicShred)
        XCTAssertEqual(shred?.magnitude ?? 0, 12, accuracy: 1e-9, "3 回まで重なる")
        XCTAssertEqual(shred?.remaining ?? 0, 2, accuracy: 1e-9)
        StatCalculator.recompute(&f.s, v, f.ctx)
        XCTAssertEqual(f.s.units[v].stats.magicResist, max(0, resist - 12), accuracy: 1e-9)
        // ミニオンには付かない
        let m = addMinion(&f, near: f.s.units[v].pos)
        hit(&f, a, m, 10, .magic)
        XCTAssertTrue(f.s.units[m].statuses.isEmpty)
    }

    func testWishingLanternSummonsAButterflyEvery900RawMagicDamage() {
        var (f, a, v) = duel(["EQ201"], attacker: "H004")   // ウィッシュランタン [900, 0.08, 50]
        hit(&f, a, v, 500, .magic)
        XCTAssertEqual(itemDamageEvents(f, to: v).count, 0)
        XCTAssertEqual(runtime(f, a).magicTally, 500, accuracy: 1e-9)
        hit(&f, a, v, 500, .magic)
        // 累計 1000 → 1 匹（その時の現在 HP 19000 の 8%）。端数 100 は持ち越す
        XCTAssertEqual(itemDamageEvents(f, to: v).count, 1)
        XCTAssertEqual(itemDamage(f, to: v), 19_000 * 0.08, accuracy: 1e-6)
        XCTAssertEqual(runtime(f, a).magicTally, 100, accuracy: 1e-9)
        // 物理・ミニオンへの魔法は数えない
        hit(&f, a, v, 2000, .physical)
        let m = addMinion(&f, near: f.s.units[v].pos)
        hit(&f, a, m, 2000, .magic)
        XCTAssertEqual(runtime(f, a).magicTally, 100, accuracy: 1e-9)
        // 軽減前の値で数える（魔防があっても同じ）。1800 で 2 匹
        f.s.units[v].stats.magicResist = 100
        f.s.events.removeAll()
        hit(&f, a, v, 1700, .magic)
        XCTAssertEqual(itemDamageEvents(f, to: v).count, 2)
        XCTAssertEqual(runtime(f, a).magicTally, 0, accuracy: 1e-9)
        // 最低 50
        f.s.units[v].stats.magicResist = 0
        f.s.units[v].hp = 500
        f.s.units[a].hero!.itemRuntime.magicTally = 850
        f.s.events.removeAll()
        hit(&f, a, v, 50, .magic)
        XCTAssertEqual(itemDamage(f, to: v), 50, accuracy: 1e-6)
    }

    func testResonateAddsDamageToEveryTargetOfOneSkillEverySixSeconds() {
        var (f, a, v) = duel(["EQ204"], attacker: "H004")   // ボルトロッド [6, 255, 0.85]
        let bonus = 255 + 0.85 * f.s.units[a].stats.abilityPower
        let m = addMinion(&f, near: f.s.units[v].pos)
        hit(&f, a, v, 100, .magic)
        hit(&f, a, m, 100, .magic)        // 同じスキルの別の命中（同じ tick）
        XCTAssertEqual(itemDamage(f, to: v), bonus, accuracy: 1e-6)
        XCTAssertEqual(itemDamage(f, to: m), bonus, accuracy: 1e-6)
        // 6 秒たつまでは働かない。通常攻撃では働かない
        advance(&f, 1)
        f.s.events.removeAll()
        hit(&f, a, v, 100, .magic)
        hit(&f, a, v, 100, .physical, .basicAttack)
        XCTAssertEqual(itemDamage(f, to: v), 0)
        advance(&f, 5)
        hit(&f, a, v, 100, .magic)
        XCTAssertEqual(itemDamage(f, to: v), bonus, accuracy: 1e-6)
    }

    func testBloodWingsShieldRegrowsTwentySecondsAfterDamage() {
        var (f, a, v) = duel(["EQ205"], attacker: "H004")   // ブラッドウィング [800, 1.0, 20, 30, 150, 1]
        let power = f.s.units[a].stats.abilityPower
        let speed = f.s.units[a].stats.moveSpeed
        f.s.units[a].stats.damageReduction = 0
        ItemEffects.update(&f.s, f.ctx, hero: a)
        let shield = f.s.units[a].shields.first { $0.tag == ItemEffects.guardWingsTag }
        XCTAssertEqual(shield?.amount ?? 0, 800 + power, accuracy: 1e-6)
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.moveSpeed, speed + 30, accuracy: 1e-6, "シールドがある間 +30")
        // 割れると 1 秒間 +150
        f.s.units[a].stats.damageReduction = 0
        hit(&f, v, a, (shield?.amount ?? 0) + 10, .trueDamage)
        XCTAssertTrue(f.s.units[a].shields.isEmpty)
        ItemEffects.update(&f.s, f.ctx, hero: a)
        XCTAssertTrue(f.s.units[a].shields.isEmpty, "受けてから 20 秒は張り直さない")
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.moveSpeed, speed + 150, accuracy: 1e-6)
        advance(&f, 1.1, update: [a])
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.moveSpeed, speed, accuracy: 1e-6)
        advance(&f, 18, update: [a])
        XCTAssertTrue(f.s.units[a].shields.isEmpty)
        advance(&f, 1, update: [a])
        XCTAssertNotNil(f.s.units[a].shields.first { $0.tag == ItemEffects.guardWingsTag }, "20 秒で張り直す")
    }

    func testHolyCrystalMagicPowerScalesWithLevel() {
        for (level, mult) in [(1, 1.21), (15, 1.35)] {
            let (f, a, _) = duel(["EQ210"], attacker: "H004", level: level)
            var st = Stats()
            ItemStats.apply(items: ["EQ210", "EQ210"], runes: [], to: &st, master: f.master, hero: f.hero(a))
            XCTAssertEqual(st.abilityPower, 330 * mult, accuracy: 1e-9, "Lv\(level): 神秘は 1 つだけ")
            let base = f.s.units[a].baseStats.abilityPower
            XCTAssertEqual(f.s.units[a].stats.abilityPower, (base + 165) * mult, accuracy: 1e-6, "Lv\(level)")
        }
    }

    func testEnchantedTalismanRaisesTheCooldownCap() {
        var (f, a, _) = duel(["EQ102", "EQ105", "EQ116", "EQ109", "EQ204"], attacker: "H004")   // CD 短縮 50%
        XCTAssertEqual(f.s.units[a].stats.cooldownReduction, Balance.maxCooldownReduction, accuracy: 1e-9)
        // タリスマン（15% + 魔法の極意: 上限 +5%）×2 でも上限は 45%
        f.s.units[a].hero!.items = ["EQ214", "EQ214", "EQ102", "EQ105", "EQ116", "EQ109"]
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.cooldownReductionCap, 0.45, accuracy: 1e-9)
        XCTAssertEqual(f.s.units[a].stats.cooldownReduction, 0.45, accuracy: 1e-9)
    }

    // MARK: - 防御の固有効果

    func testImmortalityRevivesInPlaceWithHealthAndShield() {
        var (f, a, v) = duel([], victimItems: ["EQ304"], level: 4)   // イモータル [2.5, 0.16, 150, 70, 3, 210]
        StatCalculator.recompute(&f.s, v, f.ctx)
        let maxHP = f.s.units[v].stats.maxHP
        let pos = f.s.units[v].pos
        f.kill(v, by: f.id(a))
        XCTAssertFalse(f.s.units[v].isAlive)
        XCTAssertEqual(f.hero(v).respawnTimer, 2.5, accuracy: 1e-9)
        XCTAssertFalse(runtime(f, v).ready(.immortal, at: f.s.time))
        XCTAssertEqual(runtime(f, v).readyTime(.immortal), f.s.time + 210, accuracy: 1e-9)
        for _ in 0..<120 where !f.s.units[v].isAlive {
            f.s.tick += 1
            f.s.time = Double(f.s.tick) * Balance.dt
            RespawnSystem.update(&f.s, f.ctx)
        }
        XCTAssertTrue(f.s.units[v].isAlive)
        XCTAssertEqual(f.s.units[v].pos, pos, "倒れた場所で復活")
        XCTAssertEqual(f.s.units[v].hp, maxHP * 0.16, accuracy: 1e-6)
        let shield = f.s.units[v].shields.first { $0.tag == "item.immortal" }
        XCTAssertEqual(shield?.amount ?? 0, 150 + 70 * 4, accuracy: 1e-6)
        XCTAssertEqual(shield?.remaining ?? 0, 3, accuracy: 1e-9)
        XCTAssertNil(runtime(f, v).revivePos)
        // CD（210 秒）の間にもう一度倒れると通常の復活
        f.s.time += 10
        f.kill(v, by: f.id(a))
        XCTAssertEqual(f.hero(v).respawnTimer, RespawnSystem.respawnTime(level: 4, time: f.s.time), accuracy: 1e-9)
        XCTAssertGreaterThan(f.hero(v).respawnTimer, 2.5)
        XCTAssertNil(runtime(f, v).revivePos)
    }

    func testValkyrieCutsMagicDamageForThreeSecondsThenRechargesOutOfCombat() {
        var (f, a, v) = duel([], victimItems: ["EQ306"], attacker: "H004")   // ヴァルキュリアブレス [0.25, 3, 5]
        XCTAssertEqual(hit(&f, a, v, 1000, .magic), 750, accuracy: 1e-6, "その一撃から −25%")
        XCTAssertEqual(runtime(f, v).until(.valkyrie), f.s.time + 3, accuracy: 1e-9)
        advance(&f, 1)
        XCTAssertEqual(hit(&f, a, v, 1000, .magic), 750, accuracy: 1e-6)
        XCTAssertEqual(hit(&f, a, v, 1000, .physical), 1000, accuracy: 1e-6, "物理には効かない")
        advance(&f, 2.1)
        XCTAssertEqual(hit(&f, a, v, 1000, .magic), 1000, accuracy: 1e-6, "切れた後は戦闘を離れるまで働かない")
        // 戦闘を離れて 5 秒で再び使える
        advance(&f, 4, update: [v])
        XCTAssertFalse(runtime(f, v).ready(.valkyrie, at: f.s.time))
        advance(&f, 1.1, update: [v])
        XCTAssertTrue(runtime(f, v).ready(.valkyrie, at: f.s.time))
        // スキル・通常攻撃以外（装備の効果など）の魔法では起動しない
        XCTAssertEqual(hit(&f, a, v, 1000, .magic, .item), 1000, accuracy: 1e-6)
        XCTAssertEqual(hit(&f, a, v, 1000, .magic, .basicAttack), 750, accuracy: 1e-6)
    }

    func testChastiseSlowsTheAttackerAndRedemptionHealsBelowThirtyPercent() {
        var (f, a, v) = duel([], victimItems: ["EQ302"])   // 懲罰の肩甲: 懲罰 [0.25, 2]、贖罪 [0.3, 0.2, 2, 60]
        let speed = f.s.units[a].stats.attackSpeed
        hit(&f, a, v, 100, .physical, .basicAttack)
        let chastise = status(f, a, "item.chastise")
        XCTAssertEqual(chastise?.kind, .attackSpeedBoost)
        XCTAssertEqual(chastise?.magnitude ?? 0, -0.25, accuracy: 1e-9)
        XCTAssertEqual(chastise?.remaining ?? 0, 2, accuracy: 1e-9)
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.attackSpeed, speed * 0.75, accuracy: 1e-9)
        // 贖罪: 30% を下回ると 2 秒かけて最大 HP の 20% を回復
        f.s.units[v].hp = 7000            // 35%
        hit(&f, a, v, 2000, .trueDamage)  // 25%
        XCTAssertEqual(runtime(f, v).regenHP, 20_000 * 0.2 / 2, accuracy: 1e-6)
        XCTAssertEqual(runtime(f, v).regenHPUntil, f.s.time + 2, accuracy: 1e-9)
        let hp = f.s.units[v].hp
        advance(&f, 2.5, update: [v])
        XCTAssertEqual(f.s.units[v].hp - hp, 20_000 * 0.2, accuracy: 20_000 * 0.004)
        // CD 60 秒
        let until = runtime(f, v).regenHPUntil
        f.s.units[v].hp = 7000
        hit(&f, a, v, 2000, .trueDamage)
        XCTAssertEqual(runtime(f, v).regenHPUntil, until, accuracy: 1e-9)
    }

    func testAntiqueCuirassDeterWeakensSkillAttackers() {
        var (f, a, v) = duel([], victimItems: ["EQ308"])   // 上古の鎧: 威嚇 [0.06, 2, 3]
        hit(&f, a, v, 100, .physical, .basicAttack)
        XCTAssertNil(status(f, a, "item.deter"), "通常攻撃では働かない")
        for _ in 0..<4 { hit(&f, a, v, 100, .physical) }
        let deter = status(f, a, "item.deter")
        XCTAssertEqual(deter?.kind, .damageDealtReduction)
        XCTAssertEqual(deter?.magnitude ?? 0, 0.18, accuracy: 1e-9, "6% × 3 回まで")
        XCTAssertEqual(deter?.remaining ?? 0, 2, accuracy: 1e-9)
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(hit(&f, a, v, 1000, .physical, .basicAttack), 820, accuracy: 1e-6)
        // ドレッドノートメイル（Tier 2: 4%）と重ねても Tier の高い方
        let (g, _, w) = duel([], victimItems: ["EQ315", "EQ308"])
        XCTAssertEqual(ItemEffects.values(.deter, of: g.s.units[w], g.master), [0.06, 2, 3])
    }

    func testGuardianHelmetDefenderHealsPartOfABigHit() {
        var (f, a, v) = duel([], victimItems: ["EQ309"])   // 守り人の兜: 守り手 [500, 30, 0.003]
        bare(&f, v, hp: 10_000)
        var hp = f.s.units[v].hp
        hit(&f, a, v, 400, .trueDamage)
        XCTAssertEqual(hp - f.s.units[v].hp, 400, accuracy: 1e-6, "500 以下は回復しない")
        // 1500 → 超えた 1000 の（30 + 10000 × 0.3%）% = 60% を回復
        hp = f.s.units[v].hp
        hit(&f, a, v, 1500, .trueDamage)
        XCTAssertEqual(hp - f.s.units[v].hp, 1500 - 600, accuracy: 1e-6)
    }

    func testBladeArmorReflectsBasicAttacksAndCutsCritDamage() {
        var (f, a, v) = duel([], victimItems: ["EQ313"])   // ブレイドアーマー [30, 0.02, 0.15, 1]、固有のクリティカルダメージ軽減 20%
        StatCalculator.recompute(&f.s, v, f.ctx)
        XCTAssertEqual(f.s.units[v].stats.critDamageReduction, 0.20, accuracy: 1e-9)
        bare(&f, v)
        f.s.units[v].stats.armor = 100
        f.s.units[a].stats.armor = 0
        f.s.units[a].stats.damageReduction = 0
        var own = f.s.units[a].hp
        XCTAssertEqual(hit(&f, a, v, 1000, .physical, .basicAttack), 500, accuracy: 1e-6)
        // 軽減前の 1000 × (30 + 防御 100 × 0.02)% = 320 の物理ダメージを返し、15% 減速 1 秒
        XCTAssertEqual(own - f.s.units[a].hp, 320, accuracy: 1e-6)
        XCTAssertEqual(status(f, a, "item.bladedArmor")?.magnitude ?? 0, 0.15, accuracy: 1e-9)
        XCTAssertEqual(status(f, a, "item.bladedArmor")?.remaining ?? 0, 1, accuracy: 1e-9)
        // スキルは返さない
        own = f.s.units[a].hp
        hit(&f, a, v, 1000, .physical)
        XCTAssertEqual(f.s.units[a].hp, own, accuracy: 1e-9)
        // クリティカルは上乗せ分（倍率 − 1）が 20% 減る（実際の通常攻撃）
        f.s.units[v].stats.armor = 0
        f.s.units[a].stats.critChance = 1
        let attack = f.s.units[a].stats.attack, mult = f.s.units[a].stats.critMultiplier
        f.s.events.removeAll()
        CombatSystem.releaseAttack(&f.s, f.ctx, attacker: a, target: v)
        let crit = f.s.events.compactMap { e -> DamageEvent? in
            if case .damage(let d) = e, d.targetID == f.id(v), d.source == .basicAttack { return d }
            return nil
        }.first
        XCTAssertEqual(crit?.isCrit, true)
        XCTAssertEqual(crit?.amount ?? 0, attack * (1 + (mult - 1) * 0.8), accuracy: 1e-6)
    }

    func testThunderBeltStrikesEveryFourSecondsAndGrowsDefense() {
        var (f, a, v) = duel(["EQ311"])   // サンダーベルト [4, 50, 1, 1, 0.99, 0.3, 250, 0.5]
        let st = f.s.units[a].stats, base = f.s.units[a].baseStats
        let extra = (st.armor - base.armor) + (st.magicResist - base.magicResist)
        XCTAssertEqual(extra, 30, accuracy: 1e-9)
        let m = addMinion(&f, near: f.s.units[v].pos + Vec2(0, 100))
        land(&f, a, v)
        XCTAssertEqual(itemDamage(f, to: v), 50 + extra, accuracy: 1e-6)
        XCTAssertEqual(itemDamage(f, to: m), 50 + extra, accuracy: 1e-6, "周りの敵にも")
        XCTAssertEqual(status(f, v, "item.thunderbolt")?.magnitude ?? 0, 0.99, accuracy: 1e-9)
        XCTAssertEqual(runtime(f, a).stack(.thunderbolt), 1, "敵ヒーロー 1 体につき混合防御 +1")
        // 4 秒に 1 回
        f.s.events.removeAll()
        land(&f, a, v)
        XCTAssertEqual(itemDamage(f, to: v), 0)
        advance(&f, 4)
        StatCalculator.recompute(&f.s, a, f.ctx)
        XCTAssertEqual(f.s.units[a].stats.armor, st.armor + 1, accuracy: 1e-9)
        XCTAssertEqual(f.s.units[a].stats.magicResist, st.magicResist + 1, accuracy: 1e-9)
        land(&f, a, v)
        XCTAssertEqual(itemDamage(f, to: v), 50 + extra + 2, accuracy: 1e-6, "増えた防御も追加の防御に数える")
        XCTAssertEqual(runtime(f, a).stack(.thunderbolt), 2)
        // 射手・メイジ・アサシンは半分
        var (g, b, w) = duel(["EQ311"], attacker: "H003")
        land(&g, b, w)
        XCTAssertEqual(itemDamage(g, to: w), (50 + 30) * 0.5, accuracy: 1e-6)
        XCTAssertEqual(runtime(g, b).stack(.thunderbolt), 0.5)
    }

    func testQueensWingsDemonizeAndDefiance() {
        var (f, a, v) = duel([], victimItems: ["EQ312"])   // クイーンズウイング: 魔人化 [0.4, 0.3, 3, 2, 60]、反抗 [0.25, 0.15]
        f.s.units[v].hero!.skillCooldowns = [0, 5, 5, 5]
        f.s.units[v].hp = 10_000
        hit(&f, a, v, 1000, .trueDamage)  // 45%
        XCTAssertNil(status(f, v, "item.demonize"))
        hit(&f, a, v, 2000, .trueDamage)  // 35%
        let demonize = status(f, v, "item.demonize")
        XCTAssertEqual(demonize?.kind, .damageReduction)
        XCTAssertEqual(demonize?.magnitude ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(demonize?.remaining ?? 0, 3, accuracy: 1e-9)
        XCTAssertEqual(f.hero(v).skillCooldowns, [0, 3, 3, 3])
        // CD 60 秒
        f.s.units[v].statuses.removeAll()
        hit(&f, a, v, 10, .trueDamage)
        XCTAssertNil(status(f, v, "item.demonize"))
        // 反抗: 失った HP 1% につき与えるダメージ +0.25%（最大 15%）
        bare(&f, a)
        f.s.units[v].hp = 16_000          // 20% 失った → +5%
        XCTAssertEqual(hit(&f, v, a, 1000, .trueDamage), 1050, accuracy: 1e-6)
        f.s.units[v].hp = 4_000           // 80% 失った → +20% → 15%
        XCTAssertEqual(hit(&f, v, a, 1000, .trueDamage), 1150, accuracy: 1e-6)
    }

    // MARK: - 靴

    func testWarriorBootsValorStacksOnPhysicalDamage() {
        var (f, a, v) = duel([], victimItems: ["EQ407"])   // ウォリアーブーツ: 勇気 [4, 3, 5]
        StatCalculator.recompute(&f.s, v, f.ctx)
        let armor = f.s.units[v].stats.armor
        bare(&f, v)
        hit(&f, a, v, 10, .magic)
        XCTAssertEqual(runtime(f, v).stack(.valor), 0, "魔法では増えない")
        for _ in 0..<6 { hit(&f, a, v, 10, .physical) }
        XCTAssertEqual(runtime(f, v).stack(.valor), 5)
        StatCalculator.recompute(&f.s, v, f.ctx)
        XCTAssertEqual(f.s.units[v].stats.armor, armor + 20, accuracy: 1e-9)
        advance(&f, 3.1)
        StatCalculator.recompute(&f.s, v, f.ctx)
        XCTAssertEqual(f.s.units[v].stats.armor, armor, accuracy: 1e-9, "3 秒で切れる")
    }

    func testRapidBootsWeakenSlows() {
        for (boots, reduction) in [("EQ402", 0.35), ("EQ403", 0.0)] {
            var (f, a, v) = duel([boots])
            XCTAssertEqual(f.s.units[a].stats.slowReduction, reduction, accuracy: 1e-9, boots)
            let speed = f.s.units[a].stats.moveSpeed
            CombatSystem.addStatus(&f.s, targetIndex: a, StatusEffect(kind: .slow, duration: 2, magnitude: 0.4,
                                                                      sourceID: f.id(v), tag: "test.slow"))
            StatCalculator.recompute(&f.s, a, f.ctx)
            XCTAssertEqual(f.s.units[a].stats.moveSpeed, speed * (1 - 0.4 * (1 - reduction)), accuracy: 1e-6, boots)
        }
    }

    func testToughBootsAndBruteForceShortenCrowdControlUpToTheCap() {
        var (f, a, v) = duel([], victimItems: ["EQ406"])   // タフブーツ: コントロール時間短縮 25%
        StatCalculator.recompute(&f.s, v, f.ctx)
        XCTAssertEqual(f.s.units[v].stats.ccReduction, 0.25, accuracy: 1e-9)
        func apply(_ kind: StatusKind, from source: Int) -> Double {
            f.s.units[v].statuses.removeAll()
            CombatSystem.addStatus(&f.s, targetIndex: v, StatusEffect(kind: kind, duration: 2, magnitude: 0.3,
                                                                      sourceID: f.id(source), tag: "test"))
            return f.s.units[v].statuses.first { $0.kind == kind }?.remaining ?? 0
        }
        XCTAssertEqual(apply(.stun, from: a), 1.5, accuracy: 1e-9)
        XCTAssertEqual(apply(.slow, from: a), 1.5, accuracy: 1e-9)
        XCTAssertEqual(apply(.root, from: a), 1.5, accuracy: 1e-9)
        XCTAssertEqual(apply(.speedBoost, from: a), 2, accuracy: 1e-9, "強化は縮まない")
        XCTAssertEqual(apply(.slow, from: v), 2, accuracy: 1e-9, "自分で付けたものは縮まない")
        // ブレストプレート: 暴力 [8, 0.02, 4, 6, 0.25, 1] が最大（6 回）でさらに +25%
        f.s.units[v].hero!.items = ["EQ406", "EQ303"]
        StatCalculator.recompute(&f.s, v, f.ctx)
        for _ in 0..<6 {
            hit(&f, v, a, 10, .physical)
            advance(&f, 1)
        }
        XCTAssertEqual(runtime(f, v).stack(.bruteForce), 6)
        StatCalculator.recompute(&f.s, v, f.ctx)
        XCTAssertEqual(f.s.units[v].stats.ccReduction, 0.50, accuracy: 1e-9)
        XCTAssertEqual(apply(.stun, from: a), 1.0, accuracy: 1e-9)
        // 上限 70%
        f.s.units[v].stats.ccReduction = 0.9
        XCTAssertEqual(apply(.stun, from: a), 2 * (1 - Balance.Items.maxCCReduction), accuracy: 1e-9)
    }

    func testDemonShoesRestoreManaOnMinionKills() {
        var (f, a, _) = duel(["EQ401"], attacker: "H004")   // デモンブーツ: 神髄 [0.04]
        let maxMana = f.s.units[a].stats.maxResource
        XCTAssertGreaterThan(maxMana, 0)
        f.s.units[a].resource = 0
        f.kill(f.addMinion(.melee, team: .red, at: f.s.units[a].pos), by: f.id(a))
        XCTAssertEqual(f.s.units[a].resource, maxMana * 0.04, accuracy: 1e-6)
        // Energy のヒーローには働かない
        var (g, b, _) = duel(["EQ401"])
        g.s.units[b].resource = 0
        g.kill(g.addMinion(.melee, team: .red, at: g.s.units[b].pos), by: g.id(b))
        XCTAssertEqual(g.s.units[b].resource, 0, accuracy: 1e-9)
    }

    // MARK: - ポーション・アクティブ

    func testPotionBuffExpiresAfterTwoMinutes() {
        var (f, a, _) = duel()
        f.s.units[a].hero!.gold = 2000
        let attack = f.s.units[a].stats.attack
        ItemSystem.buy(&f.s, f.ctx, heroIndex: a, itemID: "EQ134")
        XCTAssertEqual(f.s.units[a].stats.attack, attack + 30, accuracy: 1e-6)
        advance(&f, 119, update: [a])
        XCTAssertEqual(f.hero(a).itemRuntime.potionID, "EQ134")
        advance(&f, 1.1, update: [a])
        XCTAssertNil(f.hero(a).itemRuntime.potionID)
        XCTAssertEqual(f.s.units[a].stats.attack, attack, accuracy: 1e-6, "切れたら能力値を計算し直す")
    }

    func testWinterCrownFreezesTheHolderThroughTheCommand() {
        var (f, a, v) = duel(["EQ113"])   // ウィンタークラウン: 凍結 [2, 100]
        let info = ItemEffects.activeInfo(f.hero(a), time: f.s.time, master: f.master)
        XCTAssertEqual(info?.itemID, "EQ113")
        XCTAssertEqual(info?.kind, .frozen)
        XCTAssertEqual(info?.remaining ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(info?.cooldown ?? 0, 100, accuracy: 1e-9)
        CommandSystem.apply([HeroCommand(heroID: f.id(a), command: .useItemActive)], &f.s, f.ctx)
        for kind in [StatusKind.invulnerable, .untargetable, .suppress] {
            XCTAssertEqual(f.s.units[a].status(kind)?.remaining ?? 0, 2, accuracy: 1e-9, "\(kind)")
        }
        XCTAssertFalse(f.s.units[a].canAct, "凍結中は動けない")
        XCTAssertEqual(hit(&f, v, a, 1000, .trueDamage), 0, "凍結中はダメージを受けない")
        XCTAssertEqual(ItemEffects.activeInfo(f.hero(a), time: f.s.time, master: f.master)?.remaining ?? 0, 100, accuracy: 1e-9)
        // CD 中は使えない
        f.s.units[a].statuses.removeAll()
        CommandSystem.apply([HeroCommand(heroID: f.id(a), command: .useItemActive)], &f.s, f.ctx)
        XCTAssertFalse(f.s.units[a].has(.invulnerable))
        advance(&f, 100)
        CommandSystem.apply([HeroCommand(heroID: f.id(a), command: .useItemActive)], &f.s, f.ctx)
        XCTAssertTrue(f.s.units[a].has(.invulnerable))
    }

    func testWindOfNatureBlocksPhysicalDamage() {
        // ナチュラルウィンド: 風の歌 [2, 90, 0.5] → 射手 2 秒、ほかは 1 秒
        for (hero, duration) in [("H003", 2.0), ("H002", 1.0)] {
            var (f, a, holder) = duel([], victimItems: ["EQ117"], victim: hero)
            CommandSystem.apply([HeroCommand(heroID: f.id(holder), command: .useItemActive)], &f.s, f.ctx)
            XCTAssertEqual(runtime(f, holder).until(.windChant), f.s.time + duration, accuracy: 1e-9, hero)
            XCTAssertEqual(hit(&f, a, holder, 1000, .physical), 0, accuracy: 1e-9, hero)
            XCTAssertEqual(hit(&f, a, holder, 1000, .physical, .basicAttack), 0, accuracy: 1e-9, hero)
            XCTAssertEqual(hit(&f, a, holder, 100, .magic), 100, accuracy: 1e-9, "\(hero): 魔法は通る")
            advance(&f, duration + 0.1)
            XCTAssertEqual(hit(&f, a, holder, 1000, .physical), 1000, accuracy: 1e-9, hero)
            XCTAssertEqual(ItemEffects.activeInfo(f.hero(holder), time: f.s.time, master: f.master)?.remaining ?? 0,
                           90 - duration - 0.1, accuracy: 1e-6, hero)
        }
    }

    // MARK: - その他

    func testSameEffectFromTwoCopiesWorksOnce() {
        let (f, a, _) = duel(["EQ109", "EQ109"])
        let effects = ItemEffects.active(f.s.units[a], f.master)
        XCTAssertEqual(effects.filter { $0.kind == .divineJustice }.count, 1)
        // 種類の宣言順で並ぶ（決定論）
        let (g, b, _) = duel(["EQ119", "EQ120", "EQ126"])
        XCTAssertEqual(ItemEffects.active(g.s.units[b], g.master).map(\.kind), [.corrosive, .impulse, .engulf, .devour, .crossbow])
    }

    func testTimestreamAndSupremeWarrior() {
        // フリーティングタイム: キル・アシストで必殺技の残り CD −30%
        var (f, a, _) = duel(["EQ114"])
        f.s.units[a].hero!.skillCooldowns[SkillSlot.ultimate.rawValue] = 40
        ItemEffects.onKillOrAssist(&f.s, f.ctx, hero: a)
        XCTAssertEqual(f.hero(a).skillCooldowns[SkillSlot.ultimate.rawValue], 28, accuracy: 1e-9)
        // 龍神の槍: 必殺技で 7.5 秒間 移動速度 +30%（CD 15 秒）
        var (g, b, _) = duel(["EQ102"])
        ItemEffects.onSkillCast(&g.s, g.ctx, caster: b, slot: .skill1)
        XCTAssertNil(status(g, b, "item.supremeWarrior"))
        ItemEffects.onSkillCast(&g.s, g.ctx, caster: b, slot: .ultimate)
        XCTAssertEqual(status(g, b, "item.supremeWarrior")?.magnitude ?? 0, 0.30, accuracy: 1e-9)
        XCTAssertEqual(status(g, b, "item.supremeWarrior")?.remaining ?? 0, 7.5, accuracy: 1e-9)
        XCTAssertEqual(runtime(g, b).readyTime(.supremeWarrior), g.s.time + 15, accuracy: 1e-9)
    }
}
