import XCTest
@testable import VelstriaCore

/// H034 鎖鉤のゴルム（Franco の Velstria 版）のキット。仕様: docs/kits/Franco.md、実装対応表: 同ファイル末尾。
/// キットは HeroKits.testOverride に有効な Kit_H034 を差して試す（本番の有効化とは独立。有効化後も同じ結果）。
/// 敵は動かない通常のヒーロー（H001 / H003 ほか）。パッシブの闘気は、調べるテスト以外では「たまらない状態」から始める。
final class Kit_H034Tests: XCTestCase {
    typealias Tune = Kit_H034.Tune

    override func setUp() {
        super.setUp()
        HeroKits.testOverride = [Kit_H034(isReady: true)]
    }

    override func tearDown() {
        HeroKits.testOverride = []
        super.tearDown()
    }

    // MARK: - 土台

    /// ゴルム（blue, 東向き）を置く。passive = false なら闘気・加速・回復が動かない状態（無被弾の待ちを長く取る）で始める。
    private func world(level: Int = 1, ranks: [Int]? = [1, 1, 1], noCooldowns: Bool = false,
                       passive: Bool = false) -> (SkillWorld, Int) {
        var w = SkillWorld(noCooldowns: noCooldowns)
        let k = w.addHero("H034", team: .blue, at: skillArena, level: level, ranks: ranks, facing: 0)
        if !passive { w.s.units[k].hero!.kit!.gormCalm = 1000 }
        return (w, k)
    }

    @discardableResult
    private func addEnemy(_ w: inout SkillWorld, dx: Double, dy: Double = 0, hero: String = "H001", level: Int = 12) -> Int {
        w.addHero(hero, team: .red, at: skillArena + Vec2(dx, dy), level: level, ranks: [1, 1, 1])
    }

    private func kit(_ w: SkillWorld, _ k: Int) -> KitState { w.s.units[k].hero!.kit! }

    private func dist(_ w: SkillWorld, _ a: Int, _ b: Int) -> Double {
        w.s.units[a].pos.distance(to: w.s.units[b].pos)
    }

    /// 中心間距離がちょうど端同士の隙間 gap になる値。
    private func contact(_ w: SkillWorld, _ a: Int, _ b: Int, gap: Double = 0) -> Double {
        w.s.units[a].radius + w.s.units[b].radius + gap
    }

    private func events(_ w: SkillWorld, to e: Int, _ source: DamageSource) -> [DamageEvent] {
        w.damageEvents.filter { $0.targetID == w.id(e) && $0.source == source }
    }

    private func hurt(_ w: inout SkillWorld, _ i: Int, by attacker: Int, amount: Double = 10) {
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(attacker), targetIndex: i, amount: amount,
                                 type: .trueDamage, source: .spell)
    }

    private var hero: HeroDef { MasterData.shared.hero("H034")! }

    private func skill(_ slot: SkillSlot) -> SkillDef { MasterData.shared.skill(hero: "H034", slot: slot)! }

    // MARK: - レジストリ・照準・数値

    func testRegistryAndTargetingPerSlot() throws {
        XCTAssertTrue(HeroKits.hasKit("H034"))
        XCTAssertTrue(Kit_H034(isReady: true).isReady)
        XCTAssertFalse(HeroKits.hasKit("H001"))
        func target(_ slot: SkillSlot, stage: Int = 0) -> SkillTargeting {
            HeroKits.targeting(for: skill(slot), hero: hero, stage: stage)
        }
        // S1: 長い直線の鉤（非貫通）
        let s1 = target(.skill1)
        XCTAssertEqual(s1.archetype, .lineSkillshot)
        XCTAssertEqual(s1.aim, .direction)
        XCTAssertEqual(s1.shape, .wideLine)
        XCTAssertEqual(s1.range, Tune.hookRange)
        XCTAssertEqual(s1.radius, Tune.hookWidth)
        XCTAssertEqual(s1.reach, Tune.hookRange)
        XCTAssertFalse(s1.requiresTarget)
        XCTAssertFalse(s1.recastable, "Franco に再使用は無い")
        // 他の近接スキル（マスターの射程 300）・通常攻撃（150）より明らかに長い
        XCTAssertGreaterThan(s1.reach, 2 * skill(.skill1).range)
        XCTAssertGreaterThan(s1.reach, 4 * hero.attackRange)
        // S2: 自身中心の範囲
        let s2 = target(.skill2)
        XCTAssertEqual(s2.archetype, .selfAoE)
        XCTAssertEqual(s2.aim, .none)
        XCTAssertEqual(s2.shape, .selfRing)
        XCTAssertEqual(s2.radius, Tune.shockRadius)
        XCTAssertFalse(s2.requiresTarget)
        // 奥義: 敵ヒーロー 1 体の対象指定（短い射程）
        let ult = target(.ultimate)
        XCTAssertEqual(ult.archetype, .targetedBlink)
        XCTAssertEqual(ult.aim, .unit)
        XCTAssertEqual(ult.shape, .lockOn)
        XCTAssertTrue(ult.requiresTarget)
        XCTAssertEqual(ult.reach, Tune.ultReach)
        XCTAssertLessThan(ult.reach, s1.reach)
        XCTAssertEqual(target(.passive).archetype, .passive)
        // 段（再使用）は無い: どの段でも同じ
        for slot in [SkillSlot.skill1, .skill2, .ultimate] {
            XCTAssertEqual(target(slot, stage: 1), target(slot), "\(slot)")
        }
        // 実ユニット: キット状態が付き、窓は閉じている
        let (w, k) = world()
        XCTAssertNotNil(w.s.units[k].hero?.kit)
        for slot in SkillSlot.allCases {
            XCTAssertNil(HeroKits.recast(w.s.units[k].hero!, slot: slot))
            XCTAssertEqual(HeroKits.activeStage(w.s.units[k].hero!, slot: slot), 0)
        }
        // 汎用の設計（キットなし）とは別物
        let generic = SkillCatalog.genericTargeting(for: skill(.ultimate), hero: hero)
        XCTAssertEqual(generic.archetype, .teamHeal, "汎用のサポートの奥義は味方回復。キットが置き換える")
        XCTAssertNotEqual(ult, generic)
    }

    /// 1 スロットの単体総ダメージは汎用の 0.8〜1.3 倍。
    private func damageRatio(_ slot: SkillSlot, level: Int, rank: Int) -> Double {
        let (w, k) = world(level: level)
        let stats = w.s.units[k].stats
        let generic = SkillCatalog.genericNumbers(for: skill(slot), hero: hero, rank: rank, stats: stats)
        let kitN = SkillCatalog.numbers(for: skill(slot), hero: hero, rank: rank, stats: stats)
        return kitN.totalDamage / generic.totalDamage
    }

    /// S1・S2 の予算の帯（汎用の何倍か）。鉤は公式のスタンが引き寄せの間だけ（0.3 秒）になったぶん、Lv1 の勝率で上限 1.3 を少し超える（1.5 まで許す）。
    static let hookBudget = 0.8...1.5
    static let shockBudget = 0.8...1.3

    func testNumbersStayWithinDamageBudgetAndFollowCooldownFormula() throws {
        for level in [1, 6, 12] {
            for rank in 1...Balance.basicSkillMaxRank {
                for slot in [SkillSlot.skill1, .skill2] {
                    let r = damageRatio(slot, level: level, rank: rank)
                    let band = slot == .skill1 ? Self.hookBudget : Self.shockBudget
                    XCTAssertTrue(band.contains(r), "\(slot) Lv\(level) r\(rank): \(r)")
                }
            }
            // 奥義: 汎用のサポートの奥義にはダメージが無い（味方回復）ので予算は適用しない。公式の 1 撃 50 / 60 / 70（+70%）
            let (w, k) = world(level: level)
            let stats = w.s.units[k].stats
            let atk = stats.attack * Balance.skillAttackScalingFactor
            for (rank, b) in [(1, 50.0), (2, 60), (3, 70)] {
                let n = SkillCatalog.numbers(for: skill(.ultimate), hero: hero, rank: rank, stats: stats)
                XCTAssertEqual(n.hits, Tune.ultHits)
                XCTAssertEqual(n.damage, (b + 0.7 * atk) * Balance.Skills.damageScale(.ultimate) * Tune.ultScale,
                               accuracy: 1e-6, "Lv\(level) r\(rank)")
                XCTAssertEqual(n.heal, 0, "味方回復は持たない")
                XCTAssertEqual(n.shield, 0)
                XCTAssertEqual(n.cc, .stun)
                XCTAssertEqual(n.ccDuration, Tune.ultSuppress)
                XCTAssertTrue(n.ccIsUltimate)
            }
            // 公式のダメージ: (基礎 + 係数 × 攻撃力 × 0.6) × スロット倍率 × 換算（S2 は基礎だけ換算 + 自分の最大 HP の 4%）
            for rank in 1...4 {
                let lv = 1 + Double(rank - 1) * 5 / 3
                XCTAssertEqual(SkillCatalog.numbers(for: skill(.skill1), hero: hero, rank: rank, stats: stats).damage,
                               (400 + (lv - 1) * 50 + 1.0 * atk) * Balance.Skills.damageScale(.skill1) * Tune.hookScale,
                               accuracy: 1e-6, "鉤 Lv\(level) r\(rank)")
                XCTAssertEqual(SkillCatalog.numbers(for: skill(.skill2), hero: hero, rank: rank, stats: stats).damage,
                               (300 + (lv - 1) * 30) * Balance.Skills.damageScale(.skill2) * Tune.shockScale + 0.04 * stats.maxHP,
                               accuracy: 1e-6, "S2 Lv\(level) r\(rank)")
            }
        }
        // クールダウン = 公式の秒数（ランクで線形）× 全体倍率 × (1 − CD 短縮)
        let (w, k) = world()
        let stats = w.s.units[k].stats
        let cdr = stats.cooldownReduction
        func expected(_ a: Double, _ b: Double, rank: Int, maxRank: Int) -> Double {
            (a + (b - a) * Double(rank - 1) / Double(maxRank - 1)) * (1 - cdr) * Balance.Skills.cooldownScale
        }
        for rank in 1...4 {
            // 公式の 15 → 11 秒の線形補間（ランク 1 も 15 秒）
            XCTAssertEqual(SkillCatalog.numbers(for: skill(.skill1), hero: hero, rank: rank, stats: stats).cooldown,
                           expected(15, 11, rank: rank, maxRank: 4), accuracy: 1e-9)
            XCTAssertEqual(SkillCatalog.numbers(for: skill(.skill2), hero: hero, rank: rank, stats: stats).cooldown,
                           expected(7, 4.5, rank: rank, maxRank: 4), accuracy: 1e-9)
        }
        for (rank, sec) in [(1, 62.0), (2, 55), (3, 48)] {
            // 公式（日本語クライアント）62 / 55 / 48 秒（表で引く）
            XCTAssertEqual(SkillCatalog.numbers(for: skill(.ultimate), hero: hero, rank: rank, stats: stats).cooldown,
                           sec * (1 - cdr) * Balance.Skills.cooldownScale, accuracy: 1e-9)
        }
        // マナ消費（公式）: S1 135 → 160、S2 40 → 65、アルティメット 110 / 125 / 140
        for (rank, hookMP, shockMP) in [(1, 135.0, 40.0), (4, 160, 65)] {
            XCTAssertEqual(SkillSystem.cost(for: skill(.skill1), hero: hero, rank: rank), hookMP, accuracy: 1e-9)
            XCTAssertEqual(SkillSystem.cost(for: skill(.skill2), hero: hero, rank: rank), shockMP, accuracy: 1e-9)
            XCTAssertEqual(SkillCatalog.numbers(for: skill(.skill1), hero: hero, rank: rank, stats: stats).cost, hookMP,
                           accuracy: 1e-9)
        }
        for (rank, mp) in [(1, 110.0), (2, 125), (3, 140)] {
            XCTAssertEqual(SkillSystem.cost(for: skill(.ultimate), hero: hero, rank: rank), mp, accuracy: 1e-9)
        }
        // 鉤はスタン、S2 は減速（HUD・AI 用の CC 種別）。ランクが上がるほど強く・CD は短く
        let h1 = SkillCatalog.numbers(for: skill(.skill1), hero: hero, rank: 1, stats: stats)
        let h4 = SkillCatalog.numbers(for: skill(.skill1), hero: hero, rank: 4, stats: stats)
        XCTAssertEqual(h1.cc, .stun)
        XCTAssertEqual(h1.ccDuration, Tune.hookStun)
        XCTAssertGreaterThan(h4.damage, h1.damage)
        // ランクが上がるほど CD が短い
        let h2 = SkillCatalog.numbers(for: skill(.skill1), hero: hero, rank: 2, stats: stats)
        let h3 = SkillCatalog.numbers(for: skill(.skill1), hero: hero, rank: 3, stats: stats)
        XCTAssertLessThan(h4.cooldown, h3.cooldown)
        XCTAssertLessThan(h3.cooldown, h2.cooldown)
        XCTAssertLessThan(h2.cooldown, h1.cooldown)
        let s2 = SkillCatalog.numbers(for: skill(.skill2), hero: hero, rank: 1, stats: stats)
        XCTAssertEqual(s2.cc, .slow)
        XCTAssertEqual(s2.ccDuration, Tune.shockSlowDuration)
        XCTAssertEqual(s2.shield, 0)
        // コストはキットの公式の値（numbers・検証・HUD が同じ値）
        XCTAssertEqual(s2.cost, SkillSystem.cost(for: skill(.skill2), hero: hero, rank: 1))
    }

    func testTagsFollowTheOfficialSkillTags() {
        // 公式: パッシブ Buff / S1 CC・Damage（Damage のキーが無いので「バースト」）/ S2 Slow / アルティメット Burst・CC
        XCTAssertEqual(HeroKits.tags(heroID: "H034", slot: .passive), ["buff"])
        XCTAssertEqual(HeroKits.tags(heroID: "H034", slot: .skill1), ["disrupt", "damage"])
        XCTAssertEqual(HeroKits.tags(heroID: "H034", slot: .skill2), ["slow"])
        XCTAssertEqual(HeroKits.tags(heroID: "H034", slot: .ultimate), ["burst", "disrupt"])
        for slot in SkillSlot.allCases {
            for tag in HeroKits.tags(heroID: "H034", slot: slot) { XCTAssertTrue(KitTag.all.contains(tag), tag) }
        }
    }

    func testShockDamageScalesWithOwnMaxHealth() throws {
        let (w, k) = world(level: 12)
        var stats = w.s.units[k].stats
        let base = Kit_H034.scaledBase(Tune.shockBase, slot: .skill2, scale: Tune.shockScale, rank: 2, maxRank: 4)
        let n = SkillCatalog.numbers(for: skill(.skill2), hero: hero, rank: 2, stats: stats)
        XCTAssertEqual(n.damage, base + 0.04 * stats.maxHP, accuracy: 1e-9)
        // 最大 HP が 1000 増えると 40 増える（4%）
        stats.maxHP += 1000
        let n2 = SkillCatalog.numbers(for: skill(.skill2), hero: hero, rank: 2, stats: stats)
        XCTAssertEqual(n2.damage - n.damage, 40, accuracy: 1e-9)
        // 低レベルほど小さい（HP が低い）
        let (w1, k1) = world(level: 1)
        let n1 = SkillCatalog.numbers(for: skill(.skill2), hero: hero, rank: 2, stats: w1.s.units[k1].stats)
        XCTAssertLessThan(n1.damage, n.damage)
    }

    func testTextFillsEverySlotWithSimNumbers() throws {
        let (w, k) = world(level: 6, ranks: [2, 2, 2])
        for slot in SkillSlot.allCases {
            let text = try XCTUnwrap(HeroKits.text(heroID: "H034", slot: slot), "\(slot)")
            let n = SkillCatalog.numbers(for: skill(slot), hero: hero, rank: max(1, w.s.units[k].hero!.rank(slot)),
                                         stats: w.s.units[k].stats)
            let t = SkillCatalog.targeting(for: skill(slot), hero: hero)
            for english in [false, true] {
                let s = text.filled(english: english, numbers: n, targeting: t)
                XCTAssertFalse(s.contains("{"), "\(slot) en=\(english): \(s)")
                XCTAssertFalse(s.isEmpty)
            }
        }
        // 数値は sim と一致する
        func ja(_ slot: SkillSlot, rank: Int = 1) throws -> String {
            let n = SkillCatalog.numbers(for: skill(slot), hero: hero, rank: rank, stats: w.s.units[k].stats)
            let t = SkillCatalog.targeting(for: skill(slot), hero: hero)
            return try XCTUnwrap(HeroKits.text(heroID: "H034", slot: slot)).filled(english: false, numbers: n, targeting: t)
        }
        let passive = try ja(.passive)
        // 闘気の増える間隔は Tune.stackInterval から、最大の上乗せは 15% × 10 = 150%（公式の「最大 150%」）
        for token in ["5秒間ダメージを受けなかった場合", "10%上昇", "1秒ごとに最大HPの1%を回復", "+15%", "最大10スタック", "1秒に1スタック",
                      "最大150%増加"] {
            XCTAssertTrue(passive.contains(token), "\(token): \(passive)")
        }
        // 単位の無い距離（680 / 260 / 350）は出さず、近接攻撃の射程（150）に対する倍率で書く
        let s1 = try ja(.skill1, rank: 2)
        let n1 = SkillCatalog.numbers(for: skill(.skill1), hero: hero, rank: 2, stats: w.s.units[k].stats)
        let b1 = Int(Kit_H034.scaledBase(Tune.hookBase, slot: .skill1, scale: Tune.hookScale, rank: 2, maxRank: 4).rounded())
        let p1 = Int(Kit_H034.attackPercent(Tune.hookAttackRatio, slot: .skill1, scale: Tune.hookScale).rounded())
        XCTAssertEqual(n1.ccDuration, Tune.hookPull, "スタンは引き寄せの間だけ")
        for token in ["約4.5倍", "最初に命中した敵に\(b1)(+\(p1)%物理攻撃)の物理ダメージ", "自身の元へ引き寄せる", "0.3秒"] {
            XCTAssertTrue(s1.contains(token), "\(token): \(s1)")
        }
        let s2 = try ja(.skill2, rank: 2)
        let n2 = SkillCatalog.numbers(for: skill(.skill2), hero: hero, rank: 2, stats: w.s.units[k].stats)
        let b2 = Int(Kit_H034.scaledBase(Tune.shockBase, slot: .skill2, scale: Tune.shockScale, rank: 2, maxRank: 4).rounded())
        XCTAssertGreaterThan(n2.damage, Double(b2))
        for token in ["約1.7倍", "\(b2)(+自身の最大HPの4%)の物理ダメージ", "1.5秒間移動速度を70%低下"] {
            XCTAssertTrue(s2.contains(token), "\(token): \(s2)")
        }
        let ult = try ja(.ultimate, rank: 2)
        let n3 = SkillCatalog.numbers(for: skill(.ultimate), hero: hero, rank: 2, stats: w.s.units[k].stats)
        let b3 = Int(Kit_H034.scaledBase(Tune.ultHitBase, slot: .ultimate, scale: Tune.ultScale, rank: 2, maxRank: 3).rounded())
        let p3 = Int(Kit_H034.attackPercent(Tune.ultHitAttackRatio, slot: .ultimate, scale: Tune.ultScale).rounded())
        XCTAssertEqual(n3.hits, 6)
        for token in ["約2.3倍", "攻撃ごとに\(b3)(+\(p3)%物理攻撃)の物理ダメージ", "1.8秒間、制圧状態", "6回攻撃"] {
            XCTAssertTrue(ult.contains(token), "\(token): \(ult)")
        }
    }

    // MARK: - パッシブ: 鉄鎖の執念

    func testCalmStateGrantsSpeedAndOneStackPerSecondUpToTen() throws {
        var (w, k) = world(level: 12, passive: true)
        var (ref, rk) = world(level: 12)    // 比較用（パッシブが動かない同じヒーロー）
        ref.tick(3)
        w.tick(3)
        XCTAssertEqual(w.s.units[k].stats.moveSpeed, ref.s.units[rk].stats.moveSpeed * 1.10, accuracy: 1e-6)
        XCTAssertTrue(kit(w, k).gormCalmActive)
        XCTAssertEqual(kit(w, k).gormStacks, 0)
        w.run(seconds: 1.0)
        XCTAssertEqual(kit(w, k).gormStacks, 1)
        w.run(seconds: 1.0)
        XCTAssertEqual(kit(w, k).gormStacks, 2)
        w.run(seconds: 3.0)
        XCTAssertEqual(kit(w, k).gormStacks, 5)
        XCTAssertEqual(HeroKits.badge(w.s.units[k].hero!, slot: .passive),
                       KitBadge(kind: .stacks, value: 5, maxValue: 10))
        w.run(seconds: 12)
        XCTAssertEqual(kit(w, k).gormStacks, Tune.maxStacks, "最大 10")
        XCTAssertEqual(HeroKits.badge(w.s.units[k].hero!, slot: .passive)?.value, 10)
        // 加速のステータスは 1 つだけ（積み重ならない）
        XCTAssertEqual(w.s.units[k].statuses.filter { $0.kind == .speedBoost }.count, 1)
    }

    func testCalmRegenerationHealsOnePercentOfMaxHealthPerSecond() {
        var (w, k) = world(level: 12, passive: true)
        let maxHP = w.s.units[k].stats.maxHP
        w.s.units[k].hp = maxHP * 0.5
        w.tick(2)
        w.log.removeAll()
        w.run(seconds: 4.0)
        let healed = w.log.compactMap { e -> Double? in
            if case .heal(let t, _, let a) = e, t == w.id(k) { return a } else { return nil }
        }
        let multiplier = w.s.units[k].stats.healingReceivedMultiplier
        XCTAssertGreaterThanOrEqual(healed.count, 7)
        XCTAssertLessThanOrEqual(healed.count, 8)
        for h in healed { XCTAssertEqual(h, maxHP * 0.01 * 0.5 * multiplier, accuracy: 1e-6) }
        // 4 秒でおよそ 4%（ヒーローの自然回復は同じ条件の比較用ワールドで差し引く）
        var (ref, rk) = world(level: 12)
        ref.s.units[rk].hp = maxHP * 0.5
        ref.tick(2)
        ref.run(seconds: 4.0)
        XCTAssertEqual(w.s.units[k].hp - ref.s.units[rk].hp, maxHP * 0.04 * multiplier, accuracy: maxHP * 0.006)
        // 満タンなら回復しない
        w.s.units[k].hp = maxHP
        w.log.removeAll()
        w.run(seconds: 2)
        XCTAssertTrue(w.log.allSatisfy { if case .heal = $0 { return false } else { return true } })
        // 回復量スコア・回復強化の対象外
        XCTAssertEqual(w.s.units[k].hero!.score.healingDone, 0)
    }

    func testTakingDamageEndsCalmStateButKeepsStacksAndRestartsAfterFiveSeconds() {
        var (w, k) = world(level: 12, passive: true)
        let e = addEnemy(&w, dx: 900)
        w.run(seconds: 3.5)
        XCTAssertEqual(kit(w, k).gormStacks, 3)
        XCTAssertTrue(w.s.units[k].statuses.contains { $0.kind == .speedBoost })
        w.s.units[k].hp = w.s.units[k].stats.maxHP * 0.8
        hurt(&w, k, by: e)
        XCTAssertFalse(w.s.units[k].statuses.contains { $0.kind == .speedBoost }, "加速は止まる")
        XCTAssertFalse(kit(w, k).gormCalmActive)
        XCTAssertEqual(kit(w, k).gormCalm, Tune.calmDelay, accuracy: 1e-9)
        XCTAssertEqual(kit(w, k).gormStacks, 3, "闘気は消えない（減衰の規則は調査に無い）")
        // 5 秒の間は加速も回復も闘気もない
        w.log.removeAll()
        w.run(seconds: 4.5)
        XCTAssertEqual(kit(w, k).gormStacks, 3)
        XCTAssertFalse(w.log.contains { if case .heal = $0 { return true } else { return false } }, "回復しない")
        XCTAssertFalse(w.s.units[k].statuses.contains { $0.kind == .speedBoost })
        // 5 秒たつと戻り、さらに 1 秒で闘気が増える
        w.run(seconds: 1.0)
        XCTAssertTrue(w.s.units[k].statuses.contains { $0.kind == .speedBoost })
        XCTAssertEqual(kit(w, k).gormStacks, 3)
        w.run(seconds: 1.4)
        XCTAssertEqual(kit(w, k).gormStacks, 4)
        // シールドが全部吸収したダメージでも「ダメージを受けた」ことになる
        CombatSystem.addShield(&w.s, w.ctx, sourceID: w.id(k), targetIndex: k, amount: 500, duration: 5)
        let before = w.s.units[k].hp
        hurt(&w, k, by: e, amount: 50)
        XCTAssertEqual(w.s.units[k].hp, before, accuracy: 1e-9)
        XCTAssertFalse(kit(w, k).gormCalmActive)
        XCTAssertEqual(kit(w, k).gormCalm, Tune.calmDelay, accuracy: 1e-9)
    }

    func testNextSkillConsumesAllStacksAndAmplifiesDamage() {
        // S2: 闘気 4 つ → +60%
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 150)
        let n = w.numbers(k, .skill2)
        w.s.units[k].hero!.kit!.gormStacks = 4
        XCTAssertTrue(w.cast(k, .skill2))
        XCTAssertEqual(kit(w, k).gormStacks, 0)
        XCTAssertEqual(kit(w, k).gormLastConsumed, 4)
        XCTAssertEqual(events(w, to: e, .skill(.skill2)).first?.amount ?? 0, w.mitigated(n.damage * 1.6, .physical, on: e),
                       accuracy: 1e-6)
        // 10 個 → +150%（調査: 最大 +150%）
        var (w2, k2) = world(level: 12)
        let e2 = addEnemy(&w2, dx: 150)
        let n2 = w2.numbers(k2, .skill2)
        w2.s.units[k2].hero!.kit!.gormStacks = 10
        XCTAssertTrue(w2.cast(k2, .skill2))
        XCTAssertEqual(events(w2, to: e2, .skill(.skill2)).first?.amount ?? 0,
                       w2.mitigated(n2.damage * 2.5, .physical, on: e2), accuracy: 1e-6)
        // 闘気なしは補正なし
        var (w3, k3) = world(level: 12)
        let e3 = addEnemy(&w3, dx: 150)
        let n3 = w3.numbers(k3, .skill2)
        XCTAssertTrue(w3.cast(k3, .skill2))
        XCTAssertEqual(events(w3, to: e3, .skill(.skill2)).first?.amount ?? 0, w3.mitigated(n3.damage, .physical, on: e3),
                       accuracy: 1e-6)
    }

    /// 公式の注記: 無被弾の間に闘気を消費したら、次にダメージを受けるまで闘気はたまらない（加速・回復は続く）。
    func testStacksDoNotRefillAfterBeingSpentWhileCalmUntilDamageIsTaken() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 900)
        w.s.units[k].hero!.kit!.gormCalm = 0
        w.run(seconds: 3)
        XCTAssertTrue(kit(w, k).gormCalmActive)
        XCTAssertGreaterThan(kit(w, k).gormStacks, 0)
        XCTAssertTrue(w.cast(k, .skill2))
        XCTAssertEqual(kit(w, k).gormStacks, 0)
        XCTAssertTrue(kit(w, k).gormStackLock)
        w.run(seconds: 3)
        XCTAssertEqual(kit(w, k).gormStacks, 0, "ダメージを受けるまでたまらない")
        XCTAssertTrue(w.s.units[k].statuses.contains { $0.kind == .speedBoost && $0.tag == Tune.speedTag }, "加速は続く")
        // ダメージを受けると解除され、5 秒の無被弾のあとにまたたまる
        w.hit(e, k, SkillWorld.truePayload(10, source: .skill(.skill1)))
        XCTAssertFalse(kit(w, k).gormStackLock)
        w.run(seconds: Tune.calmDelay + 2.5)
        XCTAssertGreaterThan(kit(w, k).gormStacks, 0)
    }

    func testStacksAreConsumedEvenWhenTheHookMissesAndByTheHookAndUltimate() {
        // 外れても消費
        var (w, k) = world(level: 12)
        w.s.units[k].hero!.kit!.gormStacks = 7
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        XCTAssertEqual(kit(w, k).gormStacks, 0)
        XCTAssertEqual(kit(w, k).gormLastConsumed, 7)
        // 鉤: ダメージが補正される
        var (w2, k2) = world(level: 12)
        let e2 = addEnemy(&w2, dx: 400)
        let n2 = w2.numbers(k2, .skill1)
        w2.s.units[k2].hero!.kit!.gormStacks = 10
        XCTAssertTrue(w2.cast(k2, .skill1, .unit(w2.id(e2))))
        w2.run(seconds: 0.5)
        XCTAssertEqual(events(w2, to: e2, .skill(.skill1)).first?.amount ?? 0,
                       w2.mitigated(n2.damage * 2.5, .physical, on: e2), accuracy: 1e-6)
        // 奥義: 6 回すべてに補正（発動時に闘気を消費）
        var (w3, k3) = world(level: 12)
        let e3 = addEnemy(&w3, dx: 120)
        let n3 = w3.numbers(k3, .ultimate)
        w3.s.units[k3].hero!.kit!.gormStacks = 5
        XCTAssertTrue(w3.cast(k3, .ultimate))
        XCTAssertEqual(kit(w3, k3).gormStacks, 0)
        w3.run(seconds: 2.0)
        let hits = events(w3, to: e3, .skill(.ultimate))
        XCTAssertEqual(hits.count, 6)
        // 6 回の合計（軽減前）の上限 = 相手の最大 HP の 80%（闘気 5 個の公式の値はこの相手だと上限に届く）
        let perHit = min(n3.damage * 1.75, w3.s.units[e3].stats.maxHP * Tune.ultMaxHPFraction / Double(Tune.ultHits))
        for h in hits { XCTAssertEqual(h.amount, w3.mitigated(perHit, .physical, on: e3), accuracy: 1e-6) }
    }

    func testKitReplacesTheGenericSupportPassiveAndUltimateHeal() {
        var (w, k) = world(level: 12)
        let ally = w.addHero("H002", team: .blue, at: skillArena + Vec2(-300, 0), level: 12)
        w.s.units[ally].hp = w.s.units[ally].stats.maxHP * 0.3
        let e = addEnemy(&w, dx: 150)
        XCTAssertTrue(w.cast(k, .skill2))
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        w.run(seconds: 0.5)
        XCTAssertTrue(w.s.units[ally].shields.isEmpty)
        XCTAssertFalse(w.log.contains { if case .heal(let t, _, _) = $0 { return t == w.id(ally) } else { return false } })
    }

    // MARK: - S1: 鎖鉤

    func testHookDamagesStunsAndPullsOnlyTheFirstEnemyAndStopsAtTheGap() throws {
        var (w, k) = world(level: 12)
        let near = addEnemy(&w, dx: 500)
        let far = addEnemy(&w, dx: 640, hero: "H003")    // 同じ直線上の奥
        let farPos = w.s.units[far].pos
        let n = w.numbers(k, .skill1)
        let mana = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(near))))
        XCTAssertLessThan(w.s.units[k].resource, mana, "コストを消費")
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), n.cooldown, accuracy: 1e-9)
        let ev = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(ev.slot, .skill1)
        XCTAssertEqual(ev.shape, .wideLine)
        XCTAssertEqual(ev.range, Tune.hookRange)
        XCTAssertEqual(ev.archetype, .lineSkillshot)
        XCTAssertEqual(w.s.projectiles.count, 1)
        XCTAssertFalse(w.s.projectiles[0].pierce, "非貫通")
        XCTAssertEqual(w.damage(to: near), 0, "飛んでいる間はダメージが無い")
        w.run(seconds: 0.6)
        let hits = events(w, to: near, .skill(.skill1))
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].amount, w.mitigated(n.damage, .physical, on: near), accuracy: 1e-6)
        // 最初の敵だけ: 奥の敵には何も起きない
        XCTAssertEqual(w.damage(to: far), 0)
        XCTAssertEqual(w.s.units[far].pos, farPos)
        XCTAssertTrue(w.s.units[far].statuses.isEmpty)
        // 足元へ引き寄せ（端同士の隙間 10 で止まる）
        XCTAssertEqual(dist(w, k, near), contact(w, k, near, gap: Tune.hookGap), accuracy: 3)
        XCTAssertEqual(w.s.units[near].pos.y, skillArena.y, accuracy: 1)
        XCTAssertGreaterThan(w.s.units[near].pos.x, w.s.units[k].pos.x)
        // スタン: 公式は「先にスタン、それから引き寄せ」で、スタンは引き寄せの間だけ（命中から 0.3 秒）。着いたらすぐ動ける
        XCTAssertFalse(w.s.units[near].has(.stun), "命中から 0.6 秒後にはスタンは解けている")
        XCTAssertTrue(w.s.units[near].canAct)
        XCTAssertEqual(kit(w, k).gormHooksLanded, 1)
        XCTAssertFalse(w.s.units[near].statuses.contains { $0.kind == .stun })
    }

    func testHookStunDurationAndPullTimeMatchTheTuning() throws {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 300)
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(e))))
        var hitTick: Int?
        var stunEnd: Int?
        var pullEnd: Int?
        for t in 1...90 {
            w.tick()
            if hitTick == nil, w.damage(to: e) > 0 { hitTick = t }
            if hitTick != nil, pullEnd == nil, w.s.units[e].displacement == nil { pullEnd = t }
            if hitTick != nil, stunEnd == nil, !w.s.units[e].has(.stun) { stunEnd = t }
        }
        let h = try XCTUnwrap(hitTick), p = try XCTUnwrap(pullEnd), s = try XCTUnwrap(stunEnd)
        XCTAssertEqual(Double(p - h) / Balance.tickRate, Tune.hookPull, accuracy: 0.1)
        XCTAssertEqual(Double(s - h) / Balance.tickRate, Tune.hookStun, accuracy: 0.1)
    }

    func testHookRangeAndWidth() {
        func fires(dx: Double, dy: Double = 0) -> Bool {
            var (w, k) = world(level: 12)
            let e = addEnemy(&w, dx: dx, dy: dy)
            XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
            w.run(seconds: 1.2)
            return w.damage(to: e) > 0
        }
        XCTAssertTrue(fires(dx: 700), "射程 680 + 対象の縁")
        XCTAssertTrue(fires(dx: 735))
        XCTAssertFalse(fires(dx: 900), "射程の外")
        XCTAssertTrue(fires(dx: 400, dy: 100), "弾幅 55 + 対象の半径 55 以内")
        XCTAssertFalse(fires(dx: 400, dy: 140), "横にそれていたら外れ")
        XCTAssertFalse(fires(dx: -400), "後ろには飛ばない")
    }

    func testHookIgnoresStructuresAlliesAndHitsMinionsFirst() {
        // タワーは素通り: 手前にタワーがあっても奥の敵に当たる。タワーにはダメージも引き寄せも無い
        var (w, k) = world(level: 12)
        let tower = w.addTower(team: .red, at: skillArena + Vec2(300, 0))
        let hp = w.s.units[tower].hp
        let e = addEnemy(&w, dx: 520)
        XCTAssertTrue(w.cast(k, .skill1, .direction(Vec2(1, 0))))
        w.run(seconds: 0.7)
        XCTAssertGreaterThan(w.damage(to: e), 0)
        XCTAssertEqual(w.damage(to: tower), 0)
        XCTAssertEqual(w.s.units[tower].hp, hp)
        XCTAssertEqual(w.s.units[tower].pos, skillArena + Vec2(300, 0))
        XCTAssertLessThan(dist(w, k, e), 200, "引き寄せられた")

        // 味方は素通り
        var (w2, k2) = world(level: 12)
        let ally = w2.addHero("H002", team: .blue, at: skillArena + Vec2(250, 0), level: 12)
        let e2 = addEnemy(&w2, dx: 500)
        XCTAssertTrue(w2.cast(k2, .skill1, .direction(Vec2(1, 0))))
        w2.run(seconds: 0.7)
        XCTAssertEqual(w2.damage(to: ally), 0)
        XCTAssertEqual(w2.s.units[ally].pos, skillArena + Vec2(250, 0))
        XCTAssertGreaterThan(w2.damage(to: e2), 0)

        // 「最初の敵ユニット」: ミニオンが手前に居ればミニオンに当たり、ヒーローは無傷
        var (w3, k3) = world(level: 12)
        let minion = w3.addMinion(team: .red, at: skillArena + Vec2(300, 0))
        let e3 = addEnemy(&w3, dx: 520)
        XCTAssertTrue(w3.cast(k3, .skill1, .direction(Vec2(1, 0))))
        w3.run(seconds: 0.7)
        XCTAssertGreaterThan(w3.damage(to: minion), 0)
        XCTAssertEqual(w3.damage(to: e3), 0)
        XCTAssertEqual(w3.s.units[e3].pos, skillArena + Vec2(520, 0))
        XCTAssertTrue(w3.s.units[e3].statuses.isEmpty)
    }

    func testHookOnCCImmuneTargetDamagesButDoesNotStunOrMove() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 450)
        CombatSystem.addStatus(&w.s, targetIndex: e, StatusEffect(kind: .ccImmune, duration: 5))
        let at = w.s.units[e].pos
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(e))))
        w.run(seconds: 1.0)
        XCTAssertGreaterThan(w.damage(to: e), 0)
        XCTAssertFalse(w.s.units[e].has(.stun))
        XCTAssertEqual(w.s.units[e].pos, at)
        // 無敵の相手には何も起きない
        var (w2, k2) = world(level: 12)
        let e2 = addEnemy(&w2, dx: 450)
        CombatSystem.addStatus(&w2.s, targetIndex: e2, StatusEffect(kind: .invulnerable, duration: 5))
        XCTAssertTrue(w2.cast(k2, .skill1, .unit(w2.id(e2))))
        w2.run(seconds: 1.0)
        XCTAssertEqual(w2.damage(to: e2), 0)
        XCTAssertEqual(w2.s.units[e2].pos, skillArena + Vec2(450, 0))
    }

    func testHookAtPointBlankStunsWithoutMovingAndCostsResources() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 125)    // 端同士の隙間 5 < 10: すでに足元
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(e))))
        // 命中した tick にはスタンが付いている（引き寄せの間だけ）
        for _ in 0..<30 where w.damage(to: e) == 0 { w.tick() }
        XCTAssertGreaterThan(w.damage(to: e), 0)
        XCTAssertTrue(w.s.units[e].has(.stun))
        w.run(seconds: 0.5)
        XCTAssertEqual(dist(w, k, e), 125, accuracy: 6)
        // 資源が足りない・スタン中は撃てない
        var (w2, k2) = world(level: 12)
        w2.s.units[k2].resource = 0
        XCTAssertFalse(w2.cast(k2, .skill1, .direction(Vec2(1, 0))))
        w2.s.units[k2].resource = w2.s.units[k2].stats.maxResource
        CombatSystem.addStatus(&w2.s, targetIndex: k2, StatusEffect(kind: .stun, duration: 1))
        XCTAssertFalse(w2.cast(k2, .skill1, .direction(Vec2(1, 0))))
        XCTAssertEqual(w2.s.units[k2].hero!.cooldown(.skill1), 0)
    }

    /// 壁を挟んだ 2 点（壁の南北どちらかに 1 体ずつ）。マップの矩形の障害物から探す。
    private func wallScenario() -> (gorm: Vec2, enemy: Vec2, rect: Rect2)? {
        let ctx = SkillWorld.standardContext
        for o in ctx.map.obstacles {
            guard case .rect(let r) = o, r.maxY - r.minY <= 400, r.maxX - r.minX >= 200 else { continue }
            let cx = (r.minX + r.maxX) / 2
            let a = Vec2(cx, r.minY - 90)
            let b = Vec2(cx, r.maxY + 90)
            guard ctx.nav.isWalkable(a, radius: 55), ctx.nav.isWalkable(b, radius: 55) else { continue }
            return (a, b, r)
        }
        return nil
    }

    func testHookFliesOverWallsButThePullStopsInFrontOfTheWall() throws {
        let sc = try XCTUnwrap(wallScenario(), "壁を挟める障害物がマップに無い")
        var w = SkillWorld()
        let k = w.addHero("H034", team: .blue, at: sc.gorm, level: 12, ranks: [1, 1, 1], facing: Double.pi / 2)
        w.s.units[k].hero!.kit!.gormCalm = 1000
        let e = w.addHero("H001", team: .red, at: sc.enemy, level: 12, ranks: [1, 1, 1])
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(e))))
        w.run(seconds: 0.7)
        // 鉤は壁を越えて当たる（調査: 壁・タワーを通り抜ける）
        XCTAssertGreaterThan(w.damage(to: e), 0)
        XCTAssertEqual(w.s.units[k].hero!.kit!.gormHooksLanded, 1)
        // 引き寄せは壁の手前で止まり、壁の中へは入らない（壁の反対側に残る）
        let p = w.s.units[e].pos
        XCTAssertGreaterThanOrEqual(p.y, sc.rect.maxY + w.s.units[e].radius - 1)
        XCTAssertFalse(Obstacle.rect(sc.rect).contains(p, inflatedBy: w.s.units[e].radius - 1))
        XCTAssertTrue(w.ctx.nav.isWalkable(p, radius: w.s.units[e].radius - 1))
    }

    // MARK: - スキル2: 鉄鎖旋

    func testShockHitsEveryEnemyAroundWithMaxHealthDamageAndSlow() throws {
        var (w, k) = world(level: 12)
        let a = addEnemy(&w, dx: 200)
        let b = addEnemy(&w, dx: 0, dy: -240, hero: "H003")
        let minion = w.addMinion(team: .red, at: skillArena + Vec2(-250, 0))
        let outside = addEnemy(&w, dx: 0, dy: 400, hero: "H004")
        let tower = w.addTower(team: .red, at: skillArena + Vec2(0, 150))
        let n = w.numbers(k, .skill2)
        let mana = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .skill2))
        XCTAssertLessThan(w.s.units[k].resource, mana)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), n.cooldown, accuracy: 1e-9)
        for e in [a, b] {
            let hits = events(w, to: e, .skill(.skill2))
            XCTAssertEqual(hits.count, 1)
            XCTAssertEqual(hits[0].amount, w.mitigated(n.damage, .physical, on: e), accuracy: 1e-6)
            let slow = try XCTUnwrap(w.s.units[e].statuses.first { $0.kind == .slow })
            XCTAssertEqual(slow.magnitude, 0.70, accuracy: 1e-9)
            XCTAssertEqual(slow.remaining, 1.5, accuracy: 1e-9)
        }
        XCTAssertGreaterThan(w.damage(to: minion), 0, "ミニオンにも当たる")
        XCTAssertEqual(w.damage(to: outside), 0, "範囲の外")
        XCTAssertEqual(w.damage(to: tower), 0, "構造物には当たらない")
        // 自身にシールドなどは付かない（汎用の自身中心 AoE ではない）
        XCTAssertTrue(w.s.units[k].shields.isEmpty)
        let ev = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(ev.shape, .selfRing)
        XCTAssertEqual(ev.radius, Tune.shockRadius)
        // 移動速度は 70% 減（残り 30%）、1.5 秒で解ける
        w.tick(2)
        var w2 = SkillWorld()
        let e2 = w2.addHero("H001", team: .red, at: skillArena + Vec2(5000, 0), level: 12, ranks: [1, 1, 1])
        w2.tick(2)
        XCTAssertEqual(w.s.units[a].stats.moveSpeed, w2.s.units[e2].stats.moveSpeed * 0.30, accuracy: 1e-6)
        w.run(seconds: 1.6)
        XCTAssertFalse(w.s.units[a].has(.slow))
    }

    func testShockRadiusEdgeAndCCImmuneTarget() {
        var (w, k) = world(level: 12)
        // 半径 260 + 対象の半径までが範囲
        let edge = addEnemy(&w, dx: Tune.shockRadius + 50)
        let out = addEnemy(&w, dx: 0, dy: Tune.shockRadius + 70, hero: "H003")
        let immune = addEnemy(&w, dx: -150, hero: "H004")
        CombatSystem.addStatus(&w.s, targetIndex: immune, StatusEffect(kind: .ccImmune, duration: 5))
        XCTAssertTrue(w.cast(k, .skill2))
        XCTAssertGreaterThan(w.damage(to: edge), 0)
        XCTAssertEqual(w.damage(to: out), 0)
        XCTAssertGreaterThan(w.damage(to: immune), 0)
        XCTAssertFalse(w.s.units[immune].has(.slow), "CC 無効には減速が入らない")
        XCTAssertTrue(w.s.units[edge].has(.slow))
    }

    // MARK: - 奥義: 狩猟鎖獄

    func testUltimateNeedsAnEnemyHeroInReachAndKeepsResourcesOtherwise() {
        var (w, k) = world(level: 12)
        let minion = w.addMinion(team: .red, at: skillArena + Vec2(150, 0))
        let far = addEnemy(&w, dx: 420)    // 縁まで 365 > 350
        let before = w.s.units[k].resource
        XCTAssertFalse(w.cast(k, .ultimate, .unit(w.id(far))))
        XCTAssertFalse(w.cast(k, .ultimate, .unit(w.id(minion))), "敵ヒーローだけが対象")
        XCTAssertFalse(w.cast(k, .ultimate))
        XCTAssertEqual(w.s.units[k].resource, before)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.ultimate), 0)
        XCTAssertEqual(w.damage(to: far), 0)
        // 縁がちょうど届く距離は撃てる
        w.s.units[far].pos = skillArena + Vec2(Tune.ultReach + w.s.units[far].radius - 1, 0)
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(far))))
    }

    func testUltimateAutoTargetsLowestHealthHeroAndHonoursPointAndDirection() {
        var (w, k) = world(level: 12)
        let tank = addEnemy(&w, dx: 0, dy: 200, hero: "H001")
        let squishy = addEnemy(&w, dx: 0, dy: -200, hero: "H003")
        w.s.units[squishy].hp = w.s.units[squishy].stats.maxHP * 0.5
        XCTAssertEqual(Kit_H034.pickHero(w.s, caster: k, reach: Tune.ultReach, target: .none), squishy)
        XCTAssertEqual(Kit_H034.pickHero(w.s, caster: k, reach: Tune.ultReach, target: .direction(Vec2(0, 1))), tank)
        XCTAssertEqual(Kit_H034.pickHero(w.s, caster: k, reach: Tune.ultReach, target: .point(w.s.units[tank].pos)), tank)
        XCTAssertEqual(Kit_H034.pickHero(w.s, caster: k, reach: Tune.ultReach, target: .unit(w.id(tank))), tank)
        CombatSystem.addStatus(&w.s, targetIndex: squishy, StatusEffect(kind: .invulnerable, duration: 5))
        XCTAssertEqual(Kit_H034.pickHero(w.s, caster: k, reach: Tune.ultReach, target: .none), tank, "無敵は選べない")
        XCTAssertTrue(w.cast(k, .ultimate))
        w.run(seconds: 0.3)
        XCTAssertTrue(w.s.units[tank].has(.suppress))
        XCTAssertFalse(w.s.units[squishy].has(.suppress))
    }

    func testUltimateSuppressesForOnePointEightSecondsAndStrikesSixTimes() throws {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 120)
        let n = w.numbers(k, .ultimate)
        let mana = w.s.units[k].resource
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        XCTAssertLessThan(w.s.units[k].resource, mana)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.ultimate), n.cooldown, accuracy: 1e-9)
        let ev = try XCTUnwrap(w.castEvents.last)
        XCTAssertEqual(ev.shape, .lockOn)
        XCTAssertEqual(ev.targetUnitID, w.id(e))
        XCTAssertEqual(ev.duration, Tune.ultSuppress)
        XCTAssertEqual(ev.count, Tune.ultHits)
        // 拘束: 行動・移動不能、スキルは使えない
        let sup = try XCTUnwrap(w.s.units[e].statuses.first { $0.kind == .suppress })
        XCTAssertEqual(sup.remaining, 1.8, accuracy: 1e-9)
        XCTAssertEqual(sup.sourceID, w.id(k))
        XCTAssertFalse(w.s.units[e].canAct)
        XCTAssertFalse(w.s.units[e].canMove)
        XCTAssertFalse(SkillSystem.canCast(w.s, w.ctx, heroIndex: e, slot: .skill1))
        // ゴルムも動けない・他のスキルも撃てない・通常攻撃もしない
        XCTAssertEqual(kit(w, k).gormUltPhase, 2)
        XCTAssertTrue(w.s.units[k].has(.root))
        XCTAssertTrue(w.s.units[k].has(.channeling))
        XCTAssertFalse(w.s.units[k].canMove)
        XCTAssertFalse(w.cast(k, .skill1, .unit(w.id(e))))
        XCTAssertFalse(w.cast(k, .skill2))
        XCTAssertFalse(w.cast(k, .ultimate, .unit(w.id(e))))
        let badge = try XCTUnwrap(HeroKits.badge(w.s.units[k].hero!, slot: .ultimate))
        XCTAssertEqual(badge.kind, .timer)
        XCTAssertEqual(badge.total, Tune.ultSuppress)
        XCTAssertEqual(w.damage(to: e), 0, "最初の 1 撃は 0.15 秒後")

        w.s.units[k].attackTargetID = w.id(e)
        var strikeTicks: [Int] = []
        var count = 0
        for t in 1...57 {
            w.tick()
            let c = events(w, to: e, .skill(.ultimate)).count
            if c > count { strikeTicks.append(contentsOf: Array(repeating: t, count: c - count)) }
            count = c
            if t == 30 {
                XCTAssertTrue(w.s.units[e].has(.suppress), "1 秒の時点ではまだ拘束中")
                XCTAssertTrue(w.s.units[k].has(.root))
            }
        }
        let hits = events(w, to: e, .skill(.ultimate))
        XCTAssertEqual(hits.count, 6)
        for h in hits { XCTAssertEqual(h.amount, w.mitigated(n.damage, .physical, on: e), accuracy: 1e-6) }
        XCTAssertEqual(strikeTicks.count, 6)
        // 拘束の 1.8 秒の中に等間隔（0.15, 0.45, ..., 1.65 秒）
        XCTAssertEqual(Double(strikeTicks.first!) / Balance.tickRate, 0.15, accuracy: 0.07)
        XCTAssertEqual(Double(strikeTicks.last!) / Balance.tickRate, 1.65, accuracy: 0.1)
        XCTAssertLessThan(Double(strikeTicks.last!) / Balance.tickRate, Tune.ultSuppress)
        XCTAssertEqual(w.damage(to: e, from: .basicAttack), 0, "拘束中は通常攻撃をしない")
        XCTAssertEqual(kit(w, k).gormUltStrikes, 6)
        // 1.8 秒で解ける: 相手も自分も自由に
        XCTAssertFalse(w.s.units[e].has(.suppress))
        XCTAssertTrue(w.s.units[e].canAct)
        XCTAssertEqual(kit(w, k).gormUltPhase, 0)
        XCTAssertFalse(w.s.units[k].has(.root))
        XCTAssertFalse(w.s.units[k].has(.channeling))
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .ultimate))
        XCTAssertEqual(kit(w, k).gormUltTarget, 0)
        // 解けたらまた他のスキルを撃てる
        XCTAssertTrue(w.cast(k, .skill2))
    }

    func testSuppressIgnoresCCImmunityCleanseAndCancelsTheTargetsActions() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 120)
        CombatSystem.addStatus(&w.s, targetIndex: e, StatusEffect(kind: .ccImmune, duration: 10))
        w.s.units[e].windupRemaining = 0.2    // 攻撃の前隙の途中
        w.s.units[e].attackTargetID = w.id(k)
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        XCTAssertTrue(w.s.units[e].has(.suppress), "CC 無効を無視する")
        XCTAssertNil(w.s.units[e].windupRemaining, "相手の行動は中断される")
        CombatSystem.cleanse(&w.s, targetIndex: e)
        XCTAssertTrue(w.s.units[e].has(.suppress), "解除できない")
        w.run(seconds: 1.0)
        XCTAssertEqual(w.damage(to: k, from: .basicAttack), 0, "拘束中は殴り返せない")
        XCTAssertTrue(w.s.units[e].has(.suppress))
        // 通常のスタンは CC 無効に防がれるが、suppress は防がれない
        let stun = StatusEffect(kind: .stun, duration: 1)
        CombatSystem.addStatus(&w.s, targetIndex: e, stun)
        XCTAssertFalse(w.s.units[e].has(.stun))
    }

    func testUltimateRushesToATargetWithinReachThenLocks() throws {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 340)
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        // 踏み込み中: まだ拘束していない
        XCTAssertEqual(kit(w, k).gormUltPhase, 1)
        XCTAssertNotNil(kit(w, k).sweep)
        XCTAssertNotNil(w.s.units[k].displacement)
        XCTAssertFalse(w.s.units[e].has(.suppress))
        XCTAssertFalse(w.cast(k, .skill1, .unit(w.id(e))), "踏み込み中は撃てない")
        w.run(seconds: 0.3)
        XCTAssertNil(kit(w, k).sweep)
        XCTAssertEqual(kit(w, k).gormUltPhase, 2)
        XCTAssertTrue(w.s.units[e].has(.suppress))
        XCTAssertEqual(dist(w, k, e), contact(w, k, e, gap: Tune.ultContactGap), accuracy: 6)
        w.run(seconds: 2.0)
        XCTAssertEqual(events(w, to: e, .skill(.ultimate)).count, 6)
        XCTAssertEqual(kit(w, k).gormUltPhase, 0)
        // 踏み込み中に対象が遠くへ離れた（ブリンクなど）: 拘束できず、何も起きない
        var (w2, k2) = world(level: 12)
        let e2 = addEnemy(&w2, dx: 340)
        XCTAssertTrue(w2.cast(k2, .ultimate, .unit(w2.id(e2))))
        w2.s.units[e2].pos = w2.s.units[e2].pos + Vec2(0, 900)
        w2.run(seconds: 0.5)
        XCTAssertFalse(w2.s.units[e2].has(.suppress))
        XCTAssertEqual(kit(w2, k2).gormUltPhase, 0)
        XCTAssertFalse(w2.s.units[k2].has(.root))
        XCTAssertEqual(w2.damage(to: e2), 0)
        // 踏み込み中に対象が倒れた
        var (w3, k3) = world(level: 12)
        let e3 = addEnemy(&w3, dx: 340)
        XCTAssertTrue(w3.cast(k3, .ultimate, .unit(w3.id(e3))))
        w3.s.units[e3].isAlive = false
        w3.run(seconds: 0.5)
        XCTAssertEqual(kit(w3, k3).gormUltPhase, 0)
        XCTAssertFalse(w3.s.units[k3].has(.root))
    }

    func testUltimateEndsWhenTheTargetDiesAndStopsStriking() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 120)
        w.s.units[e].hp = 1    // 最初の 1 撃で倒れる
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        w.run(seconds: 2.0)
        XCTAssertFalse(w.s.units[e].isAlive)
        XCTAssertEqual(events(w, to: e, .skill(.ultimate)).count, 1)
        XCTAssertEqual(kit(w, k).gormUltPhase, 0)
        XCTAssertFalse(w.s.units[k].has(.root))
        XCTAssertFalse(w.s.units[k].has(.channeling))
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k), 0)
        XCTAssertTrue(w.cast(k, .skill2), "すぐ動ける")
    }

    func testStunningGormMidChannelCancelsStrikesAndFreesTheTarget() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 120)
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        w.run(seconds: 0.6)
        let so_far = events(w, to: e, .skill(.ultimate)).count
        XCTAssertGreaterThanOrEqual(so_far, 1)
        XCTAssertLessThan(so_far, 6)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1.0))
        w.tick(2)
        XCTAssertFalse(w.s.units[e].has(.suppress), "拘束が解ける")
        XCTAssertTrue(w.s.units[e].canAct)
        XCTAssertEqual(kit(w, k).gormUltPhase, 0)
        XCTAssertEqual(Kit.scheduledCount(w.s, caster: k), 0)
        XCTAssertFalse(w.s.units[k].has(.channeling))
        XCTAssertEqual(kit(w, k).gormUltRemaining, 0)
        w.run(seconds: 2.0)
        XCTAssertEqual(events(w, to: e, .skill(.ultimate)).count, so_far, "残りの連撃は出ない")
        // クールダウンは戻らない
        XCTAssertGreaterThan(w.s.units[k].hero!.cooldown(.ultimate), 5)
        // 打ち上げでも同じ
        var (w2, k2) = world(level: 12)
        let e2 = addEnemy(&w2, dx: 120)
        XCTAssertTrue(w2.cast(k2, .ultimate, .unit(w2.id(e2))))
        w2.run(seconds: 0.5)
        Kit.knockUp(&w2.s, target: k2, duration: 0.8, sourceID: w2.id(e2))
        w2.tick(2)
        XCTAssertFalse(w2.s.units[e2].has(.suppress))
        // 別のゴルムの suppress でも同じ（suppress はハード CC）
        var (w3, k3) = world(level: 12)
        let e3 = addEnemy(&w3, dx: 120)
        XCTAssertTrue(w3.cast(k3, .ultimate, .unit(w3.id(e3))))
        w3.run(seconds: 0.5)
        Kit.suppress(&w3.s, target: k3, duration: 1.0, sourceID: w3.id(e3))
        w3.tick(2)
        XCTAssertFalse(w3.s.units[e3].has(.suppress))
        XCTAssertEqual(kit(w3, k3).gormUltPhase, 0)
    }

    func testGormDyingMidChannelReleasesTheTargetAndResetsEverything() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 120)
        let other = addEnemy(&w, dx: 0, dy: 600, hero: "H003")
        w.s.units[k].hero!.kit!.gormStacks = 3
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        w.run(seconds: 0.5)
        XCTAssertTrue(w.s.units[e].has(.suppress))
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(other), targetIndex: k, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertTrue(w.s.units[k].hero!.isDead)
        XCTAssertFalse(w.s.units[e].has(.suppress), "術者が倒れたら拘束は解ける（フレームワークの修正）")
        XCTAssertEqual(kit(w, k), KitState())
        XCTAssertTrue(w.s.units[k].statuses.isEmpty)
        let hits = events(w, to: e, .skill(.ultimate)).count
        w.run(seconds: 2.0)
        XCTAssertEqual(kit(w, k), KitState(), "死亡中は更新しない")
        XCTAssertEqual(events(w, to: e, .skill(.ultimate)).count, hits)
    }

    /// フレームワークの追加プリミティブ（Kit.releaseSuppress）: 指定した術者が掛けた suppress だけを外す。
    func testReleaseSuppressOnlyRemovesTheGivenSourcesSuppress() {
        var (w, k) = world(level: 12)
        let a = addEnemy(&w, dx: 600)
        let b = addEnemy(&w, dx: 0, dy: 600, hero: "H003")
        Kit.suppress(&w.s, target: a, duration: 3, sourceID: w.id(k))
        Kit.suppress(&w.s, target: b, duration: 3, sourceID: w.id(a))
        CombatSystem.addStatus(&w.s, targetIndex: a, StatusEffect(kind: .slow, duration: 3, magnitude: 0.3))
        Kit.releaseSuppress(&w.s, bySource: w.id(k))
        XCTAssertFalse(w.s.units[a].has(.suppress), "指定した術者の拘束は外れる")
        XCTAssertTrue(w.s.units[a].has(.slow), "他のステータスは残る")
        XCTAssertTrue(w.s.units[b].has(.suppress), "別の術者の拘束は残る")
        Kit.releaseSuppress(&w.s, bySource: w.id(a))
        XCTAssertFalse(w.s.units[b].has(.suppress))
    }

    func testUltimateOnInvulnerableTargetDoesNotLock() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 120)
        CombatSystem.addStatus(&w.s, targetIndex: e, StatusEffect(kind: .invulnerable, duration: 5))
        // 無敵の相手は対象にできない（照準の段階で拒否）
        XCTAssertFalse(w.cast(k, .ultimate, .unit(w.id(e))))
        XCTAssertEqual(kit(w, k).gormUltPhase, 0)
        XCTAssertFalse(w.s.units[k].has(.root))
    }

    func testPracticeNoCooldownsKeepsCooldownsAtZeroAndStillWorks() {
        var (w, k) = world(level: 12, noCooldowns: true)
        let e = addEnemy(&w, dx: 300)
        XCTAssertTrue(w.cast(k, .skill1, .unit(w.id(e))))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill1), 0)
        w.run(seconds: 0.6)
        XCTAssertTrue(w.cast(k, .skill2))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), 0)
        XCTAssertTrue(w.cast(k, .ultimate, .unit(w.id(e))))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.ultimate), 0)
        w.run(seconds: 2.5)
        XCTAssertEqual(events(w, to: e, .skill(.ultimate)).count, 6)
    }

    // MARK: - 死亡・割り込み

    func testDeathResetsStacksCalmStateAndSpeedBoost() {
        var (w, k) = world(level: 12, passive: true)
        let e = addEnemy(&w, dx: 900)
        w.run(seconds: 4.2)
        XCTAssertGreaterThan(kit(w, k).gormStacks, 0)
        XCTAssertTrue(w.s.units[k].statuses.contains { $0.kind == .speedBoost })
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage,
                                 source: .spell)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertTrue(w.s.units[k].hero!.isDead)
        XCTAssertEqual(kit(w, k), KitState())
        XCTAssertTrue(w.s.units[k].statuses.isEmpty)
        w.run(seconds: 1)
        XCTAssertEqual(kit(w, k), KitState(), "死亡中は更新しない")
    }

    func testStunnedGormCannotCastAnySkill() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 120)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1))
        XCTAssertFalse(w.cast(k, .skill1, .unit(w.id(e))))
        XCTAssertFalse(w.cast(k, .skill2))
        XCTAssertFalse(w.cast(k, .ultimate, .unit(w.id(e))))
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.ultimate), 0)
    }

    // MARK: - 決定性

    private func makeScriptWorld() -> (SkillWorld, Int, Int, Int, Int) {
        var w = SkillWorld()
        let k = w.addHero("H034", team: .blue, at: skillArena, level: 12, ranks: [2, 2, 2], facing: 0)
        let e1 = w.addHero("H001", team: .red, at: skillArena + Vec2(420, 0), level: 12)
        let e2 = w.addHero("H004", team: .red, at: skillArena + Vec2(330, 160), level: 12)
        let m = w.addMinion(team: .red, at: skillArena + Vec2(200, -100))
        return (w, k, e1, e2, m)
    }

    private func script(_ w: inout SkillWorld, k: Int, e1: Int, e2: Int, m: Int, step: Int) {
        switch step {
        case 0: w.cast(k, .skill1, .unit(w.id(e1)))
        case 1: w.s.units[k].attackTargetID = w.id(e1)
        case 2: w.cast(k, .skill2)
        case 3: w.cast(k, .ultimate, .unit(w.id(e1)))
        case 4: w.cast(k, .skill1, .unit(w.id(e2)))
        case 5: w.cast(k, .skill2)
        case 6: w.cast(k, .ultimate, .unit(w.id(e2)))
        case 7: w.cast(k, .skill1, .unit(w.id(m)))
        default: break
        }
    }

    private func run(_ w: inout SkillWorld, _ k: Int, _ e1: Int, _ e2: Int, _ m: Int, from: Int, to: Int) {
        for step in from..<to {
            script(&w, k: k, e1: e1, e2: e2, m: m, step: step)
            w.run(seconds: 0.9)
        }
    }

    func testScriptedRunIsDeterministicAndExercisesTheKit() {
        var (a, ka, a1, a2, am) = makeScriptWorld()
        var (b, kb, b1, b2, bm) = makeScriptWorld()
        run(&a, ka, a1, a2, am, from: 0, to: 12)
        run(&b, kb, b1, b2, bm, from: 0, to: 12)
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(a.s.units, b.s.units)
        XCTAssertEqual(a.log, b.log)
        XCTAssertTrue(a.damageEvents.contains { $0.source == .skill(.skill1) }, "鉤を撃っている")
        XCTAssertTrue(a.damageEvents.contains { $0.source == .skill(.skill2) }, "S2 を撃っている")
        XCTAssertEqual(a.damageEvents.filter { $0.source == .skill(.ultimate) }.count % 6, 0, "奥義は 6 回ずつ")
        XCTAssertGreaterThanOrEqual(a.damageEvents.filter { $0.source == .skill(.ultimate) }.count, 6)
    }

    func testJSONRoundTripMidHookAndMidUltimateResumesIdentically() throws {
        // 鉤が飛んでいる途中
        var (b, kb, b1, b2, bm) = makeScriptWorld()
        b.cast(kb, .skill1, .unit(b.id(b1)))
        b.tick(4)
        XCTAssertFalse(b.s.projectiles.filter { !$0.done }.isEmpty, "鉤は飛翔中")
        var data = try JSONEncoder().encode(b.s)
        var resumed = b
        resumed.s = try JSONDecoder().decode(SimState.self, from: data)
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        b.run(seconds: 0.9)
        resumed.run(seconds: 0.9)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        XCTAssertGreaterThan(b.damage(to: b1, from: .skill(.skill1)), 0)
        run(&b, kb, b1, b2, bm, from: 1, to: 12)
        run(&resumed, kb, b1, b2, bm, from: 1, to: 12)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.damageEvents.count, b.damageEvents.count)

        // 奥義の途中（拘束中・連撃の予約が残っている）
        var (c, kc, c1, c2, cm) = makeScriptWorld()
        c.s.units[c1].pos = c.s.units[kc].pos + Vec2(120, 0)
        c.cast(kc, .ultimate, .unit(c.id(c1)))
        c.run(seconds: 0.6)
        XCTAssertEqual(kit(c, kc).gormUltPhase, 2)
        XCTAssertGreaterThan(Kit.scheduledCount(c.s, caster: kc), 0)
        data = try JSONEncoder().encode(c.s)
        var resumedC = c
        resumedC.s = try JSONDecoder().decode(SimState.self, from: data)
        XCTAssertEqual(resumedC.s.units, c.s.units)
        XCTAssertEqual(resumedC.s.stateHash(), c.s.stateHash())
        c.run(seconds: 0.4)
        resumedC.run(seconds: 0.4)
        XCTAssertEqual(resumedC.s.stateHash(), c.s.stateHash())
        run(&c, kc, c1, c2, cm, from: 4, to: 12)
        run(&resumedC, kc, c1, c2, cm, from: 4, to: 12)
        XCTAssertEqual(resumedC.s.stateHash(), c.s.stateHash())
        XCTAssertEqual(resumedC.s.units, c.s.units)
        XCTAssertEqual(c.damageEvents.filter { $0.source == .skill(.ultimate) }.count % 6, 0)
        XCTAssertEqual(resumedC.damageEvents.count, c.damageEvents.count)
    }

    func testUltimateTotalIsCappedAtAFractionOfTheTargetsMaxHealth() {
        // 最大 HP の小さい相手（Lv1）: 闘気 10 個の奥義でも 6 回の合計（軽減前）は最大 HP × ultMaxHPFraction まで
        var (w, k) = world(level: 12, ranks: [2, 2, 3])
        let e = addEnemy(&w, dx: 120, hero: "H004", level: 1)
        let maxHP = w.s.units[e].stats.maxHP
        let n = w.numbers(k, .ultimate)
        XCTAssertGreaterThan(w.mitigated(n.damage * 2.5 * Double(Tune.ultHits), .physical, on: e), maxHP * Tune.ultMaxHPFraction,
                             "テストの前提: 上限が無ければ上限を超える")
        w.s.units[k].hero!.kit!.gormStacks = Tune.maxStacks
        XCTAssertTrue(w.cast(k, .ultimate))
        w.run(seconds: 2.0)
        XCTAssertTrue(w.s.units[e].isAlive, "上限が無いと一撃で倒れる")
        XCTAssertGreaterThan(w.damage(to: e), 0)
        XCTAssertLessThanOrEqual(w.damage(to: e), maxHP * Tune.ultMaxHPFraction + 1e-6)
        // 上限に届かない通常の相手では上限は効かない（闘気 0 のダメージ = numbers のとおり）
        var (w2, k2) = world(level: 12)
        let e2 = addEnemy(&w2, dx: 120)
        let n2 = w2.numbers(k2, .ultimate)
        XCTAssertTrue(w2.cast(k2, .ultimate))
        w2.run(seconds: 2.0)
        XCTAssertEqual(events(w2, to: e2, .skill(.ultimate)).first?.amount ?? 0, w2.mitigated(n2.damage, .physical, on: e2),
                       accuracy: 1e-6)
    }

    // MARK: - ボットの判断

    private func decide(_ w: SkillWorld, _ k: Int, _ slot: SkillSlot, target: Int) -> String {
        let tg = HeroKits.targeting(for: skill(slot), hero: hero, stage: 0)
        switch HeroKits.botCast(w.s, w.ctx, bot: k, slot: slot, targeting: tg, target: target, fighting: true) {
        case .useDefault: return "default"
        case .cast: return "cast"
        case .castNow(let t):
            if case .unit(let id) = t, id == w.id(target) { return "castNow(target)" }
            return "castNow(other)"
        case .skip: return "skip"
        }
    }

    func testBotHookSkipsWhenAMinionOrMonsterIsInTheWayButNotForAHeroOrOffTheLine() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 500)
        XCTAssertEqual(decide(w, k, .skill1, target: e), "default", "線上に何も無い")
        // 手前の線上のミニオン: 撃たない
        let m = w.addMinion(team: .red, at: skillArena + Vec2(250, Tune.hookWidth))
        XCTAssertEqual(decide(w, k, .skill1, target: e), "skip", "ミニオンが線上（幅 + 半径以内）")
        // 線から外れたミニオン: 撃つ
        w.s.units[m].pos = skillArena + Vec2(250, Tune.hookWidth + w.s.units[m].radius + 40)
        XCTAssertEqual(decide(w, k, .skill1, target: e), "default", "線から外れている")
        // 標的より奥のミニオンは関係ない
        w.s.units[m].pos = skillArena + Vec2(600, 0)
        XCTAssertEqual(decide(w, k, .skill1, target: e), "default", "標的より奥")
        // 味方のミニオンは当たらない
        _ = w.addMinion(team: .blue, at: skillArena + Vec2(250, 0))
        XCTAssertEqual(decide(w, k, .skill1, target: e), "default", "味方は鉤を遮らない")
        // 手前に別の敵ヒーロー: その相手を引けるので撃つ
        _ = addEnemy(&w, dx: 250, hero: "H003")
        XCTAssertEqual(decide(w, k, .skill1, target: e), "default", "別の敵ヒーローは引ける")
    }

    func testBotUltimateIsCastNowOnAHookedWeakOrSupportedTargetWithinReach() {
        var (w, k) = world(level: 12)
        let e = addEnemy(&w, dx: 300)
        // 満タンの相手・味方なし: 汎用の判断
        XCTAssertEqual(decide(w, k, .ultimate, target: e), "default")
        // 傷ついた相手（< 70%）
        w.s.units[e].hp = w.s.units[e].stats.maxHP * 0.65
        XCTAssertEqual(decide(w, k, .ultimate, target: e), "castNow(target)")
        w.s.units[e].hp = w.s.units[e].stats.maxHP
        // 鉤でスタン中の相手
        CombatSystem.addStatus(&w.s, targetIndex: e, StatusEffect(kind: .stun, duration: 1, sourceID: w.id(k),
                                                                   tag: Tune.hookStunTag))
        XCTAssertEqual(decide(w, k, .ultimate, target: e), "castNow(target)", "鉤 → 奥義")
        // ほかのスタンでは特別扱いしない
        w.s.units[e].statuses.removeAll()
        CombatSystem.addStatus(&w.s, targetIndex: e, StatusEffect(kind: .stun, duration: 1))
        XCTAssertEqual(decide(w, k, .ultimate, target: e), "default")
        w.s.units[e].statuses.removeAll()
        // 近くの味方（800 以内）
        let ally = w.addHero("H002", team: .blue, at: skillArena + Vec2(-700, 0), level: 12)
        XCTAssertEqual(decide(w, k, .ultimate, target: e), "castNow(target)")
        w.s.units[ally].pos = skillArena + Vec2(-(Tune.botAllyRange + 100), 0)
        XCTAssertEqual(decide(w, k, .ultimate, target: e), "default", "味方が遠い")
        // 射程（350 + 半径）の外では撃たない
        w.s.units[e].hp = w.s.units[e].stats.maxHP * 0.5
        w.s.units[e].pos = skillArena + Vec2(Tune.ultReach + 200, 0)
        XCTAssertEqual(decide(w, k, .ultimate, target: e), "skip", "射程外")
        // ミニオンは対象にしない（汎用の判断）
        let m = w.addMinion(team: .red, at: skillArena + Vec2(200, 0))
        XCTAssertEqual(decide(w, k, .ultimate, target: m), "default")
    }

    /// 闘気 10 個の奥義 +150% が、通常の相手を一撃で倒すほどにならないこと（報告用の数値も出す）。
    func testFullStackUltimateDoesNotOneShotAHealthyTarget() {
        for level in [6, 12] {
            for foe in ["H001", "H003", "H004", "H005"] {
                var (w, k) = world(level: level, ranks: [2, 2, 3])
                let e = addEnemy(&w, dx: 120, hero: foe, level: level)
                w.s.units[k].hero!.kit!.gormStacks = Tune.maxStacks
                XCTAssertTrue(w.cast(k, .ultimate))
                w.run(seconds: 2.0)
                let dealt = w.damage(to: e)
                let ratio = dealt / w.s.units[e].stats.maxHP
                print(String(format: "H034 10-stack ult Lv%d vs %@: %.0f dmg = %.0f%% of max HP", level, foe, dealt, ratio * 100))
                XCTAssertLessThan(ratio, Tune.ultMaxHPFraction + 0.02, "Lv\(level) \(foe): 闘気 10 個の奥義で一撃になる")
            }
        }
    }

    // MARK: - ボットの煙テスト

    /// ゴルムをボットにして通常の 10 人戦を回す。S1 / S2 / 奥義のすべてを撃ち、状態が壊れない。
    func testBotSmokeCastsEverySlotAndStateStaysBounded() throws {
        var cfg = MatchFactory.botMatch(seed: 31)
        let idx = try XCTUnwrap(cfg.players.firstIndex { $0.team == .blue && $0.position == .top })
        if let other = cfg.players.firstIndex(where: { $0.heroID == "H034" }), other != idx {
            cfg.players[other].heroID = cfg.players[idx].heroID
        }
        cfg.players[idx].heroID = "H034"
        let sim = Simulation(config: cfg)
        let hero = try XCTUnwrap(sim.state.heroIndices.first { sim.state.units[$0].hero?.heroID == "H034" })
        let heroID = sim.state.units[hero].id
        XCTAssertNotNil(sim.state.units[hero].hero?.kit)
        var casts: [SkillSlot: Int] = [:]
        var maxStacks = 0
        while !sim.isEnded && sim.state.time < 1500 {
            let events = sim.step()
            for e in events {
                if case .skillCast(let c) = e, c.casterID == heroID { casts[c.slot, default: 0] += 1 }
            }
            let i = sim.state.index(of: heroID)!
            let u = sim.state.units[i]
            let k = u.hero!.kit!
            maxStacks = max(maxStacks, k.gormStacks)
            XCTAssertTrue(u.hp.isFinite && u.pos.x.isFinite && u.pos.y.isFinite && u.resource.isFinite)
            XCTAssertLessThanOrEqual(k.gormStacks, Tune.maxStacks)
            XCTAssertGreaterThanOrEqual(k.gormStacks, 0)
            XCTAssertTrue(k.reals.allSatisfy { $0.isFinite })
            XCTAssertTrue(k.timers.allSatisfy { $0.isFinite && $0 >= 0 })
            XCTAssertLessThanOrEqual(k.gormUltRemaining, Tune.ultSuppress + 1e-9)
            XCTAssertLessThanOrEqual(k.scheduled.count, 6)
            XCTAssertLessThanOrEqual(u.statuses.count, 24)
            if k.gormUltPhase == 2 { XCTAssertTrue(u.has(.channeling)) }
            // 生きているゴルムの拘束だけが残る: 死んだゴルムの suppress は誰にも残らない
            if u.hero!.isDead || !u.isAlive {
                XCTAssertFalse(sim.state.units.contains { $0.statuses.contains { $0.kind == .suppress && $0.sourceID == heroID } })
            }
            if casts[.skill1, default: 0] > 0, casts[.skill2, default: 0] > 0, casts[.ultimate, default: 0] > 0,
               sim.state.time > 130 { break }
        }
        XCTAssertGreaterThan(casts[.skill1, default: 0], 0, "S1: \(casts)")
        XCTAssertGreaterThan(casts[.skill2, default: 0], 0, "S2: \(casts)")
        XCTAssertGreaterThan(casts[.ultimate, default: 0], 0, "奥義: \(casts)")
        XCTAssertGreaterThanOrEqual(maxStacks, 1)
        print("H034 bot smoke: \(casts) maxStacks \(maxStacks) until \(sim.state.time) s")
    }

    // MARK: - 1v1 の TTK（H001–H006 相手、Lv 1 / 6 / 12）

    func testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives() {
        var failures: [String] = []
        var wins = 0
        var total = 0
        var table = "H034 TTK\n"
        for level in SkillBalanceTests.levels {
            for foe in SkillBalanceTests.representatives {
                let r = SkillBalanceTests.duel("H034", foe, level: level)
                total += 1
                if r.winnerIsA == true { wins += 1 }
                table += String(format: "Lv%d vs %@: %.1f s %@\n", level, foe, r.ttk,
                                r.winnerIsA.map { $0 ? "win" : "lose" } ?? "draw")
                if r.ttk < SkillBalanceTests.minTTK || r.ttk > SkillBalanceTests.maxTTK {
                    failures.append(String(format: "Lv%d %@: %.2f s", level, foe, r.ttk))
                }
            }
        }
        print(table + "wins \(wins)/\(total)")
        XCTAssertTrue(failures.isEmpty, "TTK が範囲外: \(failures)")
        XCTAssertGreaterThanOrEqual(wins, total / 4, "弱すぎる: \(wins)/\(total)")
    }

    /// 全ヒーローとの総当たり（Lv 6 / 12）の勝率。サポートのタンクとして 35〜65% を目安にし、極端な偏りだけを落とす。
    func testRoundRobinWinRateAgainstTheWholeRosterIsNotLopsided() {
        let foes = MasterData.shared.heroes.map(\.heroID).filter { $0 != "H034" }
        var table = "H034 round robin\n"
        var allWins = 0.0
        var allTotal = 0
        for level in [6, 12] {
            var wins = 0.0
            for foe in foes {
                let r = SkillBalanceTests.duel("H034", foe, level: level)
                // 時間切れ・相打ちは 0.5 勝
                wins += r.winnerIsA.map { $0 ? 1.0 : 0.0 } ?? 0.5
            }
            table += String(format: "Lv%d: %.1f/%d = %.0f%%\n", level, wins, foes.count, wins / Double(foes.count) * 100)
            allWins += wins
            allTotal += foes.count
        }
        let rate = allWins / Double(allTotal)
        print(table + String(format: "overall %.0f%%", rate * 100))
        XCTAssertGreaterThanOrEqual(rate, 0.25, "弱すぎる")
        XCTAssertLessThanOrEqual(rate, 0.75, "強すぎる")
    }
}
