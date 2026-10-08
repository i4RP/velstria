import XCTest
@testable import VelstriaCore

// キット層（docs/SKILL_KITS.md）のテスト支援。
// 本物のキットはまだ有効になっていないので、テスト専用のキット（TestKit）を HeroKits.testOverride に差して枠組みを試す。
// testOverride は module 内（internal）なので、本番のコードからは触れない。テストは必ず tearDown で空に戻す。

/// 枠組みのテスト用キット。結果は KitState のレジスタに残す（決定論・シリアライズの検証にもそのまま使える）。
///
/// ints:  0 = 初回発動の回数 / 1 = 再使用の回数 / 2 = 最後に再使用した段 / 3 = onTimer の回数 / 4 = 発火した code を並べた数字 /
///        5 = 突進の着地回数 / 6 = 窓が閉じた回数 / 7 = 時間切れで閉じたか
/// reals: 0 = 中断の回数 / 1 = onHit の dealt 合計 / 2 = 最後の onHit の event / 3 = 通常攻撃の命中 / 4 = update の回数 /
///        5 = onSkillHit のダメージ合計 / 6 = 被ダメ合計 / 7 = onSkillCast の回数
/// form:  1 = 与ダメ +50% / 2 = 被ダメ 50% / 3 = 通常攻撃に追加ヒット / 9 = 発動不可（canStart が false）
struct TestKit: HeroKit {
    let heroID: String
    var isReady: Bool { true }

    // MARK: A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        guard slot == .skill1 else { return base }
        var t = base
        t.recastable = true
        if stage >= 1 {
            t.shape = .fan
            t.halfAngle = 0.5
            t.reachOverride = 999
            t.requiresTarget = true
        }
        return t
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        guard slot == .skill1 else { return base }
        var n = base
        n.extras = [KitStat(key: "bonus", value: 12.5 + Double(stage))]
        n.stages = 3
        n.recastWindow = 3
        return n
    }

    func text(slot: SkillSlot) -> KitText? {
        guard slot == .skill1 else { return nil }
        return KitText(ja: "ダメージ{damage} 範囲{range} X{x0}", en: "Deals {damage} in {range}, x{x0}")
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard slot == .skill1 else { return nil }
        return KitBadge(kind: .stacks, value: hero.kit?.ints[0] ?? 0, maxValue: 5)
    }

    // MARK: B. 実行

    func resolveAim(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot, stage: Int,
                    targeting: SkillTargeting, target: SkillTarget) -> SkillAim?? {
        // 大技は対象が居なくても撃てる（足元の照準）
        guard slot == .ultimate else { return nil }
        let facing = Vec2.fromAngle(s.units[caster].facing)
        return .some(SkillAim(direction: facing, point: s.units[caster].pos, unit: nil, distance: 0))
    }

    func canStart(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) -> Bool {
        s.units[caster].hero?.kit?.form != 9
    }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        let i = c.caster
        switch c.slot {
        case .skill1:
            s.units[i].hero!.kit!.ints[0] += 1
            Kit.emitCast(&s, c, target: s.units[i].pos + c.aim.direction * c.targeting.range, shape: .fan,
                         halfAngle: 0.5, duration: 3, count: 2)
            Kit.openRecast(&s, caster: i, slot: .skill1, duration: 3, stage: 1, charges: 2, cooldownOnClose: 7)
        case .skill2:
            let payload = HitPayload(damage: 100, damageType: .trueDamage, source: .skill(.skill2), skillID: "test")
            let to = s.units[i].pos + c.aim.direction * 600
            Kit.dashSweeping(&s, ctx, caster: i, slot: .skill2, to: to, speed: 1800, payload: payload, radius: 60,
                             arriveCode: 11)
        case .ultimate:
            Kit.strikeSequence(&s, caster: i, slot: .ultimate, code: 5, count: 3, interval: 0.1, firstDelay: 0.1)
        default:
            break
        }
        return .done
    }

    func recast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast, window: RecastWindow) {
        let i = c.caster
        s.units[i].hero!.kit!.ints[1] += 1
        s.units[i].hero!.kit!.ints[2] = c.stage
        Kit.emitCast(&s, c, target: s.units[i].pos + c.aim.direction * c.targeting.range)
        Kit.advanceRecast(&s, ctx, caster: i, slot: c.slot)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        s.units[owner].hero!.kit!.ints[3] += 1
        s.units[owner].hero!.kit!.ints[4] = s.units[owner].hero!.kit!.ints[4] * 10 + timer.code
        if timer.code == 11 { s.units[owner].hero!.kit!.ints[5] += 1 }
    }

    func onWindowClosed(_ s: inout SimState, _ ctx: SimContext, owner: Int, slot: SkillSlot, expired: Bool) {
        s.units[owner].hero!.kit!.ints[6] += 1
        if expired { s.units[owner].hero!.kit!.ints[7] = 1 }
    }

    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {
        s.units[owner].hero!.kit!.reals[1] += dealt
        s.units[owner].hero!.kit!.reals[2] = Double(event)
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        s.units[owner].hero!.kit!.reals[4] += 1
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        s.units[owner].hero!.kit!.reals[0] += 1
    }

    /// 死亡しても初回発動の回数だけ残す。
    func onDeath(old: KitState, into fresh: inout KitState) {
        fresh.ints[0] = old.ints[0]
    }

    // MARK: C. パッシブ

    func outgoingDamageBonus(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                             source: DamageSource) -> Double {
        s.units[attacker].hero?.kit?.form == 1 ? 0.5 : 0
    }

    func modifyIncomingDamage(_ s: inout SimState, _ ctx: SimContext, victim: Int, attacker: Int?,
                              source: DamageSource, amount: Double) -> Double {
        s.units[victim].hero?.kit?.form == 2 ? amount * 0.5 : amount
    }

    func shapeBasicAttack(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                          plan: inout BasicAttackPlan) {
        guard s.units[attacker].hero?.kit?.form == 3 else { return }
        plan.extras.append(HitPayload(damage: 50, damageType: .trueDamage, source: .basicAttack))
    }

    func onBasicAttackHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, damage: Double) {
        s.units[attacker].hero!.kit!.reals[3] += 1
    }

    func onSkillHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, slot: SkillSlot,
                    damage: Double) {
        s.units[attacker].hero!.kit!.reals[5] += damage
    }

    func onSkillCast(_ s: inout SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) {
        s.units[caster].hero!.kit!.reals[7] += 1
    }

    func onDamageTaken(_ s: inout SimState, _ ctx: SimContext, victim: Int, attacker: Int?, amount: Double) {
        s.units[victim].hero!.kit!.reals[6] += amount
    }

    // MARK: D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        switch slot {
        case .skill1: return .skip
        case .ultimate: return .cast(.direction(Vec2(1, 0)))
        default: return .useDefault
        }
    }
}

/// 本番のキットが無い間の枠組みテストの土台。テスト用ヒーロー（デュエリスト H002）にだけ TestKit を差す。
class KitTestCase: XCTestCase {
    /// キットを差すテスト用ヒーロー（近接デュエリスト）。
    static let kitHero = "H002"

    override func setUp() {
        super.setUp()
        HeroKits.testOverride = [TestKit(heroID: KitTestCase.kitHero)]
    }

    override func tearDown() {
        HeroKits.testOverride = []
        super.tearDown()
    }
}

extension SkillWorld {
    /// キットのヒーローを配置する（KitState() を明示的に付ける）。
    @discardableResult
    mutating func addKitHero(team: Team = .blue, at pos: Vec2 = skillArena, facing: Double? = 0,
                             ranks: [Int]? = [1, 1, 1]) -> Int {
        let i = addHero(KitTestCase.kitHero, team: team, at: pos, ranks: ranks, facing: facing)
        s.units[i].hero!.kit = KitState()
        return i
    }

    /// 敵（通常のヒーロー。動かない）。
    @discardableResult
    mutating func addDummyEnemy(at pos: Vec2, hero: String = "H003") -> Int {
        addHero(hero, team: .red, at: pos)
    }

    func kit(_ i: Int) -> KitState { s.units[i].hero!.kit! }

    /// payload を owner から target へ直接適用し、この命中で target が受けたダメージ量（HP 減少 + シールド吸収）を返す。
    @discardableResult
    mutating func hit(_ owner: Int, _ target: Int, _ payload: HitPayload) -> Double {
        let before = damage(to: target)
        CombatSystem.applyHit(&s, ctx, sourceID: id(owner), team: s.units[owner].team, targetIndex: target,
                              payload: payload, from: s.units[owner].pos)
        flushEvents()
        return damage(to: target) - before
    }

    /// 確定ダメージの単純な命中内容。
    static func truePayload(_ damage: Double = 100, source: DamageSource = .skill(.skill1)) -> HitPayload {
        HitPayload(damage: damage, damageType: .trueDamage, source: source, skillID: "test")
    }
}
