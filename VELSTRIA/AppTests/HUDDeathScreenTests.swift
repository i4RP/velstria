import XCTest
import SwiftUI
@testable import VELSTRIA
import VelstriaCore

// 担当: battle-hud（death）。デス情報の集計（HUDDamageLog: ユニットごと・種類ごとの合計、window 外の除外、
// とどめの強制包含と順序、上限 5、内訳のラベル、空の場合、泉のとどめ）、HUDModel のデス情報（ヒーロー以外がとどめの時の
// キル取得ヒーロー、泉、外部の一時停止で閉じる）と、復活カウントのエンブレムの配置
// （4 端末 × 左右配置で Safe Area 内・下部パネルの中央の上。攻撃 3 つ・スキル格子・スペル・帰還・習得バッジ・
// ミニマップドック・スティックの受付領域・パネル周りの部品と重ならない）、デス情報パネルの大きさ。

@MainActor
final class HUDDeathScreenTests: XCTestCase {
    private struct Fixture {
        let sim: Simulation
        let me: EntityID
        let enemies: [VelstriaCore.Unit]
        let tower: VelstriaCore.Unit

        var state: SimState { sim.state }
        var ctx: SimContext { sim.ctx }
    }

    private func fixture() -> Fixture {
        let sim = Simulation(config: MatchFactory.standardMatch(humanHeroID: "H003", humanName: "T", seed: 5))
        let s = sim.state
        let me = s.units[s.humanHeroIndex!].id
        let enemies = s.heroIndices(team: .red).map { s.units[$0] }
        let tower = s.units.first { $0.kind == .tower && $0.team == .red }!
        return Fixture(sim: sim, me: me, enemies: enemies, tower: tower)
    }

    private func hit(_ src: EntityID?, _ dst: EntityID, _ amount: Double, _ type: DamageType = .physical,
                     _ source: DamageSource = .basicAttack) -> DamageEvent {
        DamageEvent(sourceID: src, targetID: dst, amount: amount, absorbed: 0, damageType: type, source: source,
                    isCrit: false, pos: .zero)
    }

    private func japanese(_ body: () throws -> Void) rethrows {
        let saved = Loc.current
        Loc.current = .ja
        defer { Loc.current = saved }
        try body()
    }

    // MARK: 集計

    func testRecapGroupsBySourceAndDamageType() {
        japanese {
            let f = fixture()
            let a = f.enemies[0], b = f.enemies[1]
            var log = HUDDamageLog()
            log.record(hit(a.id, f.me, 100), time: 1)
            log.record(hit(a.id, f.me, 120), time: 2)
            log.record(hit(a.id, f.me, 300, .magic, .skill(.skill1)), time: 3)
            log.record(hit(a.id, f.me, 40, .trueDamage, .dot), time: 4)
            log.record(hit(f.tower.id, f.me, 400, .physical, .tower), time: 5)
            log.record(hit(b.id, f.me, 150, .magic, .skill(.ultimate)), time: 6)
            let r = log.recap(state: f.state, ctx: f.ctx, killerID: b.id, time: 7)

            XCTAssertEqual(r.window, 10)
            XCTAssertEqual(r.total, 1110, accuracy: 1e-9)
            XCTAssertEqual(r.physical, 620, accuracy: 1e-9)
            XCTAssertEqual(r.magic, 450, accuracy: 1e-9)
            XCTAssertEqual(r.trueDamage, 40, accuracy: 1e-9)
            XCTAssertEqual(r.sources.map(\.id), [a.id, f.tower.id, b.id], "量の多い順")

            let sa = r.sources[0]
            XCTAssertEqual(sa.heroID, a.hero?.heroID)
            XCTAssertEqual(sa.kind, .hero)
            XCTAssertEqual(sa.team, .red)
            XCTAssertEqual(sa.name, HUDModel.unitName(a, f.ctx))
            XCTAssertEqual(sa.total, 560, accuracy: 1e-9)
            XCTAssertEqual(sa.physical, 220, accuracy: 1e-9)
            XCTAssertEqual(sa.magic, 300, accuracy: 1e-9)
            XCTAssertEqual(sa.trueDamage, 40, accuracy: 1e-9)
            XCTAssertEqual(sa.parts.map(\.id), ["skill1", "basic", "dot"], "内訳も量の多い順")
            XCTAssertEqual(sa.parts.map(\.amount), [300, 220, 40])
            let skill1 = f.ctx.master.skill(hero: a.hero!.heroID, slot: .skill1)!
            XCTAssertEqual(sa.parts[0].label, MasterText.skill(skill1), "スキルはヒーローのスキル名")
            XCTAssertEqual(sa.parts[1].label, "通常攻撃")
            XCTAssertEqual(sa.parts[2].label, "継続ダメージ")
            XCTAssertFalse(sa.isKiller)

            let st = r.sources[1]
            XCTAssertEqual(st.kind, .tower)
            XCTAssertNil(st.heroID)
            XCTAssertEqual(st.name, "タワー")
            XCTAssertEqual(st.parts.map(\.id), ["tower"])
            XCTAssertEqual(st.parts.first?.label, "タワー攻撃")

            let sb = r.sources[2]
            XCTAssertTrue(sb.isKiller)
            XCTAssertEqual(sb.parts.map(\.id), ["ultimate"])
            let ult = f.ctx.master.skill(hero: b.hero!.heroID, slot: .ultimate)!
            XCTAssertEqual(sb.parts.first?.label, MasterText.skill(ult))
            XCTAssertEqual(r.sources.filter(\.isKiller).count, 1)
        }
    }

    func testEventsOutsideWindowAreExcluded() {
        let f = fixture()
        let a = f.enemies[0]
        var log = HUDDamageLog()
        log.record(hit(a.id, f.me, 500), time: 0)
        log.record(hit(f.tower.id, f.me, 300, .physical, .tower), time: 4)
        log.record(hit(a.id, f.me, 80), time: 12)
        log.record(hit(a.id, f.me, 70, .magic, .skill(.skill2)), time: 15)
        XCTAssertEqual(log.entryCount, 2, "記録の時点で 10 秒より古いものは捨てる")

        let r = log.recap(state: f.state, ctx: f.ctx, killerID: a.id, time: 15)
        XCTAssertEqual(r.total, 150, accuracy: 1e-9)
        XCTAssertEqual(r.sources.map(\.id), [a.id])
        XCTAssertEqual(r.sources.first?.parts.map(\.id), ["basic", "skill2"])

        // 集計時刻から見て window 外のものも除く
        let later = log.recap(state: f.state, ctx: f.ctx, killerID: a.id, time: 23)
        XCTAssertEqual(later.total, 70, accuracy: 1e-9)
        XCTAssertEqual(later.magic, 70, accuracy: 1e-9)
        XCTAssertEqual(later.physical, 0, accuracy: 1e-9)
    }

    func testKillerAlwaysIncludedAndListCappedAtFive() {
        let f = fixture()
        XCTAssertGreaterThanOrEqual(f.enemies.count, 5)
        let gone: EntityID = 999_001
        var log = HUDDamageLog()
        for (k, amount) in [900.0, 800, 700, 600, 500].enumerated() {
            log.record(hit(f.enemies[k].id, f.me, amount), time: 1 + Double(k) * 0.5)
        }
        log.record(hit(f.tower.id, f.me, 400, .physical, .tower), time: 4)
        log.record(hit(gone, f.me, 30, .physical, .minion), time: 5)

        // とどめが少量（倒されたミニオン）: 量に関係なく最後の枠に入る
        let r = log.recap(state: f.state, ctx: f.ctx, killerID: gone, time: 6)
        XCTAssertEqual(r.sources.count, HUDDamageLog.maxSources)
        XCTAssertEqual(r.sources.map(\.total), [900, 800, 700, 600, 30])
        XCTAssertEqual(r.sources.last?.id, gone)
        XCTAssertEqual(r.sources.last?.isKiller, true)
        XCTAssertEqual(r.sources.filter(\.isKiller).count, 1)
        XCTAssertEqual(r.total, 3930, accuracy: 1e-9, "表示しないユニットの分も合計に含める")

        // とどめが上位にいれば入れ替えない
        let r2 = log.recap(state: f.state, ctx: f.ctx, killerID: f.enemies[1].id, time: 6)
        XCTAssertEqual(r2.sources.map(\.total), [900, 800, 700, 600, 500])
        XCTAssertEqual(r2.sources.map(\.isKiller), [false, true, false, false, false])

        // とどめ不明
        let r3 = log.recap(state: f.state, ctx: f.ctx, killerID: nil, time: 6)
        XCTAssertEqual(r3.sources.count, 5)
        XCTAssertFalse(r3.sources.contains(where: \.isKiller))
    }

    func testVanishedUnitsAreInferredFromDamageSource() {
        japanese {
            let f = fixture()
            let goneMinion: EntityID = 999_001, goneMonster: EntityID = 999_002
            var log = HUDDamageLog()
            log.record(hit(goneMinion, f.me, 60, .physical, .minion), time: 1)
            log.record(hit(goneMonster, f.me, 90, .physical, .monster), time: 1.5)
            log.record(hit(nil, f.me, 33, .trueDamage, .fountain), time: 2)
            log.record(hit(nil, f.me, 33, .trueDamage, .fountain), time: 2.5)
            let r = log.recap(state: f.state, ctx: f.ctx, killerID: nil, time: 3)
            XCTAssertEqual(r.sources.count, 3)

            let monster = r.sources.first { $0.id == goneMonster }
            XCTAssertEqual(monster?.kind, .monster)
            XCTAssertEqual(monster?.team, .neutral)
            XCTAssertEqual(monster?.name, "モンスター")
            XCTAssertEqual(monster?.parts.first?.id, "monster")

            let minion = r.sources.first { $0.id == goneMinion }
            XCTAssertEqual(minion?.kind, .minion)
            XCTAssertEqual(minion?.team, .red, "自分（ブルー）の敵")
            XCTAssertEqual(minion?.name, "ミニオン")
            XCTAssertEqual(minion?.parts.first?.label, "ミニオン攻撃")

            let fountain = r.sources.first { $0.kind == nil }
            XCTAssertEqual(fountain?.name, "泉")
            XCTAssertEqual(fountain?.total ?? 0, 66, accuracy: 1e-9, "発生源の無いダメージは 1 行にまとめる")
            XCTAssertEqual(fountain?.trueDamage ?? 0, 66, accuracy: 1e-9)
            XCTAssertEqual(fountain?.parts.map(\.id), ["fountain"])
            XCTAssertLessThan(fountain?.id ?? 1, 1, "実在しない ID（実在の EntityID は 1 以上）")
        }
    }

    /// 泉で倒された（最後の 1 発が発生源の無い泉のダメージ。unitDied の killerID は nil）時は泉の行をとどめにする。
    func testFountainLastHitIsTheKillerRow() {
        japanese {
            let f = fixture()
            let a = f.enemies[0]
            var log = HUDDamageLog()
            log.record(hit(a.id, f.me, 400), time: 1)
            log.record(hit(nil, f.me, 33, .trueDamage, .fountain), time: 2)
            log.record(hit(nil, f.me, 33, .trueDamage, .fountain), time: 2.1)
            XCTAssertTrue(log.lastHitIsFountain)
            let r = log.recap(state: f.state, ctx: f.ctx, killerID: nil, time: 2.2)
            XCTAssertEqual(r.sources.filter(\.isKiller).count, 1)
            let killer = r.sources.first(where: \.isKiller)
            XCTAssertEqual(killer?.id, HUDDamageLog.environmentKey(.fountain))
            XCTAssertNil(killer?.kind)
            XCTAssertEqual(killer?.name, "泉")
            XCTAssertEqual(r.sources.first { $0.id == a.id }?.isKiller, false)

            // 泉の後にヒーローから受けていれば泉ではない（killerID が付くのでそちらがとどめ）
            log.record(hit(a.id, f.me, 10), time: 2.2)
            XCTAssertFalse(log.lastHitIsFountain)
            log.reset()
            XCTAssertFalse(log.lastHitIsFountain)
        }
    }

    // MARK: HUDModel のデス情報

    private func killEvent(_ victim: EntityID, by killer: EntityID?, assists: [EntityID]) -> SimEvent {
        .heroKilled(HeroKillEvent(victimID: victim, killerID: killer, assistIDs: assists, bounty: 300,
                                  isFirstBlood: false, multiKill: 1, killerStreak: 1, isShutdown: false))
    }

    private func diedEvent(_ me: EntityID, killer: EntityID?) -> SimEvent {
        .unitDied(unitID: me, kind: .hero, team: .blue, killerID: killer, pos: .zero)
    }

    /// タワー・泉がとどめでも、キルを取ったヒーロー（heroKilled.killerID。アシストからは外れている）がデス情報に残る。
    func testDeathInfoKeepsCreditedHeroWhenNonHeroLandsLastHit() throws {
        try japanese {
            let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H003",
                                                                                              humanName: "T", seed: 5)))
            let s = c.state
            let me = try XCTUnwrap(c.humanHeroID)
            let enemies = s.heroIndices(team: .red).map { s.units[$0] }
            let tower = try XCTUnwrap(s.units.first { $0.kind == .tower && $0.team == .red })
            let x = enemies[0], y = enemies[1]
            let xID = try XCTUnwrap(x.hero?.heroID), yID = try XCTUnwrap(y.hero?.heroID)

            // X に削られ、タワーの一撃で倒された（DeathSystem はキルを X に付け、アシストは Y だけ）
            let m = HUDModel(controller: c)
            m.handle([.damage(hit(x.id, me, 600)), .damage(hit(tower.id, me, 300, .physical, .tower)),
                      diedEvent(me, killer: tower.id), killEvent(me, by: x.id, assists: [y.id])])
            let info = try XCTUnwrap(m.deathInfo)
            XCTAssertEqual(info.killerKind, .tower)
            XCTAssertNil(info.killerHeroID)
            XCTAssertEqual(info.killerName, "タワー")
            XCTAssertEqual(info.assistHeroIDs, [xID, yID], "キルを取ったヒーローを先頭に")
            XCTAssertEqual(info.recap?.sources.first(where: \.isKiller)?.id, tower.id)

            // heroKilled が unitDied より先に届いても同じ並び
            let m2 = HUDModel(controller: c)
            m2.handle([killEvent(me, by: x.id, assists: [y.id]), diedEvent(me, killer: tower.id)])
            XCTAssertEqual(m2.deathInfo?.assistHeroIDs, [xID, yID])

            // とどめがヒーローならキラー欄にいるので、アシストには足さない
            let m3 = HUDModel(controller: c)
            m3.handle([diedEvent(me, killer: x.id), killEvent(me, by: x.id, assists: [y.id])])
            XCTAssertEqual(m3.deathInfo?.killerHeroID, xID)
            XCTAssertEqual(m3.deathInfo?.assistHeroIDs, [yID])

            // 処刑（敵ヒーローの関与なし）
            let m4 = HUDModel(controller: c)
            m4.handle([diedEvent(me, killer: tower.id), killEvent(me, by: nil, assists: [])])
            XCTAssertEqual(m4.deathInfo?.assistHeroIDs, [])

            XCTAssertEqual(HUDModel.deathAssists(credited: xID, killerHeroID: nil, assists: [xID, yID]), [xID, yID],
                           "重複させない")
        }
    }

    /// 泉で倒された時はキラーを「泉」（drop.fill）にし、内訳の泉の行をとどめにする。
    func testDeathInfoNamesTheFountain() throws {
        try japanese {
            let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H003",
                                                                                              humanName: "T", seed: 5)))
            let s = c.state
            let me = try XCTUnwrap(c.humanHeroID)
            let x = s.units[s.heroIndices(team: .red)[0]]
            let m = HUDModel(controller: c)
            m.handle([.damage(hit(x.id, me, 300)), .damage(hit(nil, me, 33, .trueDamage, .fountain)),
                      diedEvent(me, killer: nil), killEvent(me, by: x.id, assists: [])])
            let info = try XCTUnwrap(m.deathInfo)
            XCTAssertTrue(info.killerIsFountain)
            XCTAssertEqual(info.killerName, "泉")
            XCTAssertNil(info.killerKind)
            XCTAssertNil(info.killerHeroID)
            XCTAssertEqual(info.killerTeam, .red, "敵の泉")
            XCTAssertEqual(info.assistHeroIDs, [x.hero?.heroID].compactMap { $0 }, "キルを取ったヒーロー")
            XCTAssertEqual(info.recap?.sources.first(where: \.isKiller)?.id, HUDDamageLog.environmentKey(.fountain))
            XCTAssertEqual(HUDDeathStyle.unitSymbol(nil), "drop.fill")

            // 発生源の分からない死（泉以外）は従来どおり不明
            let m2 = HUDModel(controller: c)
            m2.handle([.damage(hit(x.id, me, 300)), diedEvent(me, killer: nil)])
            XCTAssertEqual(m2.deathInfo?.killerIsFountain, false)
            XCTAssertNil(m2.deathInfo?.killerName)
        }
    }

    /// バックグラウンド移行の一時停止でも、ポーズメニューを開く時はデス情報パネルを閉じる。
    func testExternalPauseClosesDeathRecap() throws {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H003",
                                                                                          humanName: "T", seed: 5)))
        let m = HUDModel(controller: c)
        m.start(app: app) { _ in }
        defer { m.stop() }
        m.debugForceDeath = true
        m.refresh()
        XCTAssertTrue(m.hero.isDead)
        m.openDeathRecap()
        XCTAssertTrue(m.deathRecapOpen)
        m.externallyPaused()
        XCTAssertEqual(m.panel, .pause)
        XCTAssertFalse(m.deathRecapOpen)
    }

    func testEmptyLogGivesEmptyRecap() {
        let f = fixture()
        let empty = HUDDamageLog()
        let r = empty.recap(state: f.state, ctx: f.ctx, killerID: f.enemies[0].id, time: 30)
        XCTAssertEqual(r, HUDDeathRecap())
        XCTAssertEqual(r.window, HUDDamageLog.window)

        var log = HUDDamageLog()
        log.record(hit(f.enemies[0].id, f.me, 200), time: 1)
        log.record(hit(f.enemies[0].id, f.me, 0), time: 1.5)
        XCTAssertEqual(log.entryCount, 1, "0 ダメージは記録しない")
        log.reset()
        XCTAssertEqual(log.entryCount, 0)
        XCTAssertTrue(log.recap(state: f.state, ctx: f.ctx, killerID: nil, time: 2).sources.isEmpty)
    }

    func testLogStaysBoundedOverLongFights() {
        let f = fixture()
        var log = HUDDamageLog()
        // 敵の泉に 60 秒（毎 tick 届く）: 0.25 秒刻みにまとまる
        let dt = 1.0 / 30
        for k in 0..<1800 { log.record(hit(nil, f.me, 10, .trueDamage, .fountain), time: Double(k) * dt) }
        XCTAssertLessThanOrEqual(log.entryCount, Int(HUDDamageLog.window / HUDDamageLog.bucketSeconds) + 2)
        let r = log.recap(state: f.state, ctx: f.ctx, killerID: nil, time: 1799 * dt)
        XCTAssertEqual(r.total, 3000, accuracy: 10 * 30 * HUDDamageLog.bucketSeconds + 1, "直近 10 秒分（300 回 × 10）")

        // 別々のユニットから大量に受けても上限を超えない
        for k in 0..<1000 {
            log.record(hit(EntityID(10_000 + k), f.me, 1), time: 60 + Double(k) * 0.001)
        }
        XCTAssertLessThanOrEqual(log.entryCount, HUDDamageLog.capacity)
        XCTAssertLessThanOrEqual(log.recap(state: f.state, ctx: f.ctx, killerID: nil, time: 61).sources.count,
                                 HUDDamageLog.maxSources)
    }

    // MARK: 内訳のラベル

    func testPartIDsLabelsAndSymbols() {
        japanese {
            let f = fixture()
            let heroID = f.enemies[0].hero!.heroID
            let cases: [(DamageSource, String, String?)] = [
                (.basicAttack, "basic", "通常攻撃"),
                (.skill(.skill1), "skill1", nil), (.skill(.skill2), "skill2", nil),
                (.skill(.ultimate), "ultimate", nil), (.skill(.passive), "passive", nil), (.passive, "passive", nil),
                (.spell, "spell", "スペル"), (.item, "item", "装備効果"), (.dot, "dot", "継続ダメージ"),
                (.tower, "tower", "タワー攻撃"), (.minion, "minion", "ミニオン攻撃"),
                (.monster, "monster", "モンスター攻撃"), (.fountain, "fountain", "泉の守り"),
            ]
            for (source, id, label) in cases {
                let p = HUDDamageLog.part(for: source, heroID: heroID, ctx: f.ctx, amount: 12)
                XCTAssertEqual(p.id, id)
                XCTAssertEqual(p.amount, 12)
                if let label { XCTAssertEqual(p.label, label) }
                XCTAssertNotNil(UIImage(systemName: p.symbol), "アイコン \(p.symbol)")
                let anonymous = HUDDamageLog.part(for: source, heroID: nil, ctx: f.ctx, amount: 12)
                XCTAssertEqual(anonymous.id, id)
                XCTAssertNotNil(UIImage(systemName: anonymous.symbol), "アイコン \(anonymous.symbol)")
            }
            for slot in SkillSlot.actives {
                let def = f.ctx.master.skill(hero: heroID, slot: slot)!
                XCTAssertEqual(HUDDamageLog.part(for: .skill(slot), heroID: heroID, ctx: f.ctx, amount: 1).label,
                               MasterText.skill(def))
            }
            // ヒーロー不明（消えたユニット）の時は枠の名前
            XCTAssertEqual(HUDDamageLog.part(for: .skill(.skill2), heroID: nil, ctx: f.ctx, amount: 1).label, "スキル2")
            XCTAssertEqual(HUDDamageLog.part(for: .skill(.ultimate), heroID: nil, ctx: f.ctx, amount: 1).label, "必殺技")
            XCTAssertEqual(HUDDamageLog.part(for: .passive, heroID: nil, ctx: f.ctx, amount: 1).label, "パッシブ")
        }
        let saved = Loc.current
        defer { Loc.current = saved }
        Loc.current = .en
        let f = fixture()
        XCTAssertEqual(HUDDamageLog.part(for: .basicAttack, heroID: nil, ctx: f.ctx, amount: 1).label, "Basic attack")
        XCTAssertEqual(HUDDamageLog.part(for: .skill(.ultimate), heroID: nil, ctx: f.ctx, amount: 1).label, "Ultimate")
    }

    func testInferredKinds() {
        XCTAssertEqual(HUDDamageLog.inferredKind(.tower), .tower)
        XCTAssertEqual(HUDDamageLog.inferredKind(.minion), .minion)
        XCTAssertEqual(HUDDamageLog.inferredKind(.monster), .monster)
        XCTAssertNil(HUDDamageLog.inferredKind(.fountain))
        XCTAssertEqual(HUDDamageLog.inferredKind(.skill(.skill2)), .hero)
        XCTAssertEqual(HUDDamageLog.inferredKind(.dot), .hero)
    }

    func testDebugSampleLooksLikeARealDeath() {
        let f = fixture()
        let r = HUDDamageLog.debugSample(killerHeroID: "H005", assistHeroID: "H002", ctx: f.ctx)
        XCTAssertGreaterThan(r.total, 3500)
        XCTAssertLessThan(r.total, 4500)
        XCTAssertGreaterThan(r.physical, 0)
        XCTAssertGreaterThan(r.magic, 0)
        XCTAssertGreaterThan(r.trueDamage, 0)
        XCTAssertEqual(r.physical + r.magic + r.trueDamage, r.total, accuracy: 1e-6)
        XCTAssertEqual(r.sources.count, 4)
        XCTAssertEqual(r.sources.first?.heroID, "H005")
        let killer = r.sources.first(where: \.isKiller)
        XCTAssertEqual(killer?.heroID, "H005")
        XCTAssertTrue(Set(killer?.parts.map(\.id) ?? []).isSuperset(of: ["basic", "skill1", "ultimate"]))
        XCTAssertTrue(r.sources.contains { $0.heroID == "H002" && !$0.isKiller })
        XCTAssertEqual(Set(r.sources.compactMap(\.kind)), [.hero, .tower, .minion])
        XCTAssertEqual(r.sources.map(\.total), r.sources.map(\.total).sorted(by: >))
    }

    func testAmountFormatting() {
        XCTAssertEqual(HUDDeathStyle.amount(3962.4), "3,962")
        XCTAssertEqual(HUDDeathStyle.amount(12_345_678), "12,345,678")
        XCTAssertEqual(HUDDeathStyle.amount(-5), "0")
        XCTAssertEqual(HUDDeathStyle.percent(1, of: 3), "33%")
        XCTAssertEqual(HUDDeathStyle.percent(5, of: 0), "0%")
        for t in HUDDeathStyle.damageTypes { XCTAssertNotNil(UIImage(systemName: HUDDeathStyle.typeMarker(t))) }
        for k: UnitKind? in [.hero, .minion, .tower, .core, .monster, .dummy, nil] {
            XCTAssertNotNil(UIImage(systemName: HUDDeathStyle.unitSymbol(k)))
        }
    }

    // MARK: エンブレムの配置

    /// 横画面の論理サイズと Safe Area（左右 = Dynamic Island / ノッチ側、下 = ホームインジケータ）。HUDLayoutTests と同じ端末。
    private let devices: [(name: String, size: CGSize, side: CGFloat, bottom: CGFloat)] = [
        ("iPhone 13 mini", CGSize(width: 812, height: 375), 44, 21),
        ("iPhone 16e", CGSize(width: 844, height: 390), 47, 21),
        ("iPhone 17 Pro", CGSize(width: 874, height: 402), 62, 20),
        ("iPhone 17 Pro Max", CGSize(width: 956, height: 440), 62, 20),
    ]

    private func layout(_ d: (name: String, size: CGSize, side: CGFloat, bottom: CGFloat), leftHanded: Bool) -> HUDLayout {
        HUDLayout(size: d.size, safe: EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side),
                  leftHanded: leftHanded)
    }

    private func intersects(_ r: CGRect, circle c: CGPoint, radius: CGFloat) -> Bool {
        let x = min(max(c.x, r.minX), r.maxX)
        let y = min(max(c.y, r.minY), r.maxY)
        return hypot(c.x - x, c.y - y) < radius
    }

    private func emblemRect(_ l: HUDLayout) -> CGRect {
        let size = l.deathEmblemSize
        let c = l.deathEmblemCenter
        return CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
    }

    /// 下部パネルとその周り（HUDHeroPanel / BattleHUDView の現行の寸法）。
    private func panelRects(_ l: HUDLayout) -> [(String, CGRect)] {
        let s = min(l.scale, 1.08)
        let panelH = HUDRootMetrics.heroPanelHeight(l)
        let panel = CGRect(x: l.heroPanelCenterX - l.heroPanelWidth / 2, y: l.bottomEdge - panelH,
                           width: l.heroPanelWidth, height: panelH)
        // おすすめ購入（パネル右上 46pt 上・44pt）・状態アイコン列（パネル左上 26pt 上、6 個まで）・トースト（パネル上 104pt）
        let quickBuy = CGRect(x: panel.maxX + 2 * s - max(44, 38 * s), y: panel.minY - 46 * s,
                              width: max(44, 38 * s), height: max(44, 38 * s))
        let statusRow = CGRect(x: panel.minX + 4 * s, y: panel.minY - 26 * s, width: 6 * (22 * s + 3), height: 22 * s)
        let toastY = l.bottomEdge - (panelH + 104 * s)
        let toast = CGRect(x: l.heroPanelCenterX - 130, y: toastY - 16, width: 260, height: 32)
        return [("下部パネル", panel), ("おすすめ購入", quickBuy), ("状態アイコン列", statusRow), ("トースト", toast)]
    }

    /// 操作部品の円（攻撃 3 つ・スキル格子・習得バッジ・スペル・帰還・スティックの土台）。
    private func controlCircles(_ l: HUDLayout) -> [(String, CGPoint, CGFloat)] {
        var circles: [(String, CGPoint, CGFloat)] = AttackButtonSlot.allCases.map {
            ("attack_\($0.rawValue)", l.attackCenter(for: $0), l.attackDiameter(for: $0) / 2)
        }
        circles += [
            ("recall", l.recallCenter, l.recallDiameter / 2),
            ("spell1", l.spellCenter(0), l.spellDiameter / 2),
            ("spell2", l.spellCenter(1), l.spellDiameter / 2),
            ("joystick", l.joystickRest, l.joystickRadius),
        ]
        for slot in SkillSlot.actives {
            circles.append(("skill\(slot.rawValue)", l.skillCenter(slot),
                            (slot == .ultimate ? l.ultDiameter : l.skillDiameter) / 2))
            // 習得バッジはタップ領域（44pt）で見る
            circles.append(("level\(slot.rawValue)", l.levelBadgeCenter(slot),
                            max(l.levelBadgeDiameter, HUDLevelBadge.touchDiameter) / 2))
        }
        return circles
    }

    func testEmblemSitsAboveHeroPanelWithoutOverlap() {
        for d in devices {
            for left in [false, true] {
                let l = layout(d, leftHanded: left)
                let tag = "\(d.name) \(left ? "左利き" : "右手")"
                let size = l.deathEmblemSize
                let c = l.deathEmblemCenter
                let e = emblemRect(l)

                // 大きさ: タップ領域は 44pt 以上、幅は参考画面の比率（画面幅の約 19%）
                XCTAssertGreaterThanOrEqual(size.height, 44, tag)
                XCTAssertGreaterThanOrEqual(size.width, 44, tag)
                XCTAssertEqual(size.width / d.size.width, 0.19, accuracy: 0.01, tag)
                XCTAssertLessThan(size.height / d.size.height, 0.16, "\(tag): 控えめな大きさ")

                // Safe Area 内
                XCTAssertGreaterThanOrEqual(e.minX, d.side, tag)
                XCTAssertLessThanOrEqual(e.maxX, d.size.width - d.side, tag)
                XCTAssertGreaterThanOrEqual(e.minY, l.topEdge, tag)
                XCTAssertLessThanOrEqual(e.maxY, d.size.height - d.bottom, tag)

                // 下部パネルの中央の上
                let rects = panelRects(l)
                let panel = rects[0].1
                XCTAssertEqual(c.x, l.heroPanelCenterX, accuracy: 0.5, tag)
                XCTAssertLessThan(e.maxY, panel.minY, tag)
                XCTAssertGreaterThan(e.minX, panel.minX, "\(tag): パネルの幅に収まる")
                XCTAssertLessThan(e.maxX, panel.maxX, "\(tag): パネルの幅に収まる")

                // 重ならないもの: パネルの周り・ミニマップドック（全体マップボタン込み）・スティックの受付領域（浮動 / 固定）
                // トーストは死亡中はエンブレムの上へ譲る（BattleHUDView の HUDToastLayer）ので、生きている間の位置とは比べない
                let others = rects.filter { $0.0 != "トースト" } + [
                    ("ミニマップドック", l.minimapDockFrame), ("ミニマップ", l.minimapFrame),
                    ("スティックの受付領域", l.joystickZone), ("固定スティックの受付領域", l.fixedJoystickZone),
                ]
                for (name, r) in others {
                    XCTAssertFalse(e.intersects(r), "\(tag): エンブレムが\(name)と重なる")
                }
                for (name, center, radius) in controlCircles(l) {
                    XCTAssertFalse(intersects(e, circle: center, radius: radius + 2), "\(tag): エンブレムが \(name) と重なる")
                }
                // 上部の情報（スコア・K/D/A・味方列、高さ 64pt 以内）より下。キルフィード（情報側の端から killFeedSideReserve 内側、
                // 4 行の見積もり = signals の HUDLayout.killFeedEstimate。BattleHUDView と同じ置き方）とも離れる
                XCTAssertGreaterThan(e.minY, l.topEdge + 64, "\(tag): 上部の情報にかからない")
                let feedSize = HUDLayout.killFeedEstimate
                let feedX = left ? l.leadingEdge + l.killFeedSideReserve : l.trailingEdge - l.killFeedSideReserve - feedSize.width
                let feed = CGRect(x: feedX, y: l.killFeedTop, width: feedSize.width, height: feedSize.height)
                XCTAssertFalse(e.intersects(feed), "\(tag): エンブレムがキルフィードと重なる")
            }
        }
    }

    func testEmblemFollowsHeroPanelWhenMirrored() {
        for d in devices {
            let r = layout(d, leftHanded: false)
            let l = layout(d, leftHanded: true)
            XCTAssertEqual(r.deathEmblemSize, l.deathEmblemSize, d.name)
            XCTAssertEqual(r.deathEmblemCenter.y, l.deathEmblemCenter.y, accuracy: 1e-6, d.name)
            XCTAssertEqual(l.deathEmblemCenter.x, l.heroPanelCenterX, accuracy: 1e-6, d.name)
            XCTAssertLessThan(r.deathEmblemCenter.x, d.size.width / 2, "\(d.name): 右手配置はスティック寄り（左）")
            XCTAssertGreaterThan(l.deathEmblemCenter.x, d.size.width / 2, "\(d.name): 左利きは右へ反転")
        }
    }

    func testRecapPanelFitsEveryDevice() {
        for d in devices {
            let l = layout(d, leftHanded: false)
            let size = l.deathRecapSize
            XCTAssertLessThanOrEqual(size.width, l.trailingEdge - l.leadingEdge, d.name)
            XCTAssertLessThanOrEqual(size.height, l.bottomEdge - l.topEdge, d.name)
            XCTAssertGreaterThanOrEqual(size.height, 280, "\(d.name): 5 行が収まる高さ")
            XCTAssertGreaterThanOrEqual(size.width, 520, d.name)
        }
    }
}
