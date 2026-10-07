import SwiftUI
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 死亡中の味方追従（プレイヤー）: 戦っている味方の判定・自動で追う味方の選び方、味方一覧の中身と並び、
/// 死亡中の表示の配置（iPhone SE〜17 Pro Max の横画面・左右配置で、操作部品・ヒーローパネルと重ならず 44pt 以上）。
@MainActor
final class DeathSpectateTests: XCTestCase {
    /// 自分（Blue の人間）が倒れていて、味方を互いに離れた場所に置いた状態（time = 200 秒、視界は全て暗い）。
    private func deadState() -> (state: SimState, me: Int, allies: [Int], enemies: [Int]) {
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 6)))
        var s = c.state
        s.time = 200
        let me = c.humanIndex!
        let allies = s.heroIndices(team: .blue).filter { $0 != me }
        let enemies = s.heroIndices(team: .red)
        s.units[me].pos = Vec2(3000, 3000)
        s.units[me].isAlive = false
        s.units[me].hero?.respawnTimer = 15
        s.units[me].deathTime = 199
        for (k, i) in allies.enumerated() { s.units[i].pos = Vec2(2000 + Double(k) * 2500, 8000) }
        for (k, i) in enemies.enumerated() { s.units[i].pos = Vec2(11000, 1000 + Double(k) * 2000) }
        for i in s.heroIndices {
            s.units[i].prevPos = s.units[i].pos
            s.units[i].visibleMask = Team.blue.visionBit | Team.red.visionBit
        }
        return (s, me, allies, enemies)
    }

    /// ally を敵 enemy と戦わせる。
    private func fight(_ s: inout SimState, ally: Int, enemy: Int, offset: Double = 400) {
        s.units[enemy].pos = s.units[ally].pos + Vec2(offset, 0)
        s.units[ally].lastCombatTime = s.time - 1
    }

    func testFightScoreNeedsRecentCombatAndAVisibleEnemy() {
        var (s, _, allies, enemies) = deadState()
        XCTAssertEqual(HUDDeathSpectate.fightScore(s, index: allies[0]), 0, "誰とも戦っていない")
        fight(&s, ally: allies[0], enemy: enemies[0])
        XCTAssertEqual(HUDDeathSpectate.fightScore(s, index: allies[0]), 2)
        // 最近戦っていなければ（近くに敵がいるだけ）戦闘中ではない
        s.units[allies[0]].lastCombatTime = s.time - 10
        XCTAssertEqual(HUDDeathSpectate.fightScore(s, index: allies[0]), 0)
        s.units[allies[0]].lastDamagedTime = s.time - 0.5
        XCTAssertEqual(HUDDeathSpectate.fightScore(s, index: allies[0]), 2, "被弾も戦闘")
        // 味方のチームから見えていない敵は数えない
        s.units[enemies[0]].visibleMask = Team.red.visionBit
        XCTAssertEqual(HUDDeathSpectate.fightScore(s, index: allies[0]), 0)
        // 倒れている味方は戦っていない
        s.units[enemies[0]].visibleMask = Team.blue.visionBit | Team.red.visionBit
        s.units[allies[0]].hero?.respawnTimer = 5
        XCTAssertEqual(HUDDeathSpectate.fightScore(s, index: allies[0]), 0)
    }

    func testAutoTargetPrefersFightsThenStaysThenNearest() {
        var (s, me, allies, enemies) = deadState()
        let myID = s.units[me].id
        // 誰も戦っていない: 自分の倒れた場所に一番近い味方（(2000, 8000) の allies[0]）
        XCTAssertEqual(HUDDeathSpectate.autoTarget(state: s, me: myID, current: nil), s.units[allies[0]].id)
        // 今の味方が生きていて戦っている味方が居なければそのまま
        XCTAssertEqual(HUDDeathSpectate.autoTarget(state: s, me: myID, current: s.units[allies[2]].id), s.units[allies[2]].id)
        // 戦っている味方を優先（遠くても）
        fight(&s, ally: allies[3], enemy: enemies[0])
        XCTAssertEqual(HUDDeathSpectate.autoTarget(state: s, me: myID, current: s.units[allies[2]].id), s.units[allies[3]].id)
        // 戦っている味方を見ていれば、同じくらいの戦いが他で始まっても乗り換えない
        fight(&s, ally: allies[1], enemy: enemies[1])
        XCTAssertEqual(HUDDeathSpectate.autoTarget(state: s, me: myID, current: s.units[allies[3]].id), s.units[allies[3]].id)
        // 明らかに大きい戦い（2 人以上多い）へは乗り換える
        s.units[enemies[2]].pos = s.units[allies[1]].pos + Vec2(-300, 200)
        s.units[enemies[3]].pos = s.units[allies[1]].pos + Vec2(0, 500)
        XCTAssertEqual(HUDDeathSpectate.autoTarget(state: s, me: myID, current: s.units[allies[3]].id), s.units[allies[1]].id)
        // 戦っている味方が複数で今の味方が戦っていなければ、自分に近い方
        XCTAssertEqual(HUDDeathSpectate.autoTarget(state: s, me: myID, current: nil), s.units[allies[1]].id)
        // 味方が全員倒れていれば nil（自分へ戻る）
        for i in allies { s.units[i].hero?.respawnTimer = 3 }
        XCTAssertNil(HUDDeathSpectate.autoTarget(state: s, me: myID, current: s.units[allies[1]].id))
    }

    func testAllyListOrderAndContents() {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 6)))
        let model = HUDModel(controller: c)
        model.start(app: app, onFinish: { _ in })
        defer { model.stop() }
        var (s, _, allies, _) = deadState()
        s.units[allies[0]].hero?.respawnTimer = 7.2
        s.units[allies[2]].hp = s.units[allies[2]].stats.maxHP * 0.43
        c.restore(s)
        let list = HUDDeathSpectate.allies(model)
        XCTAssertEqual(list.count, 4, "自分以外の味方 4 人（敵は出さない）")
        XCTAssertEqual(list.last?.id, s.units[allies[0]].id, "倒れている味方は後ろ")
        XCTAssertEqual(list.last?.isDead, true)
        XCTAssertEqual(list.last?.respawn, 8)
        XCTAssertEqual(list.first { $0.id == s.units[allies[2]].id }?.hpRatio ?? 0, 0.45, accuracy: 1e-9, "5% 刻み（15Hz の差分を減らす）")
        XCTAssertFalse(list.contains { $0.id == c.humanHeroID })
        // 一覧から選ぶ: 味方を追い、自分を選ぶと自分へ戻る（敵は追えない: HUDModel の方針）
        model.follow(list[0].id)
        XCTAssertEqual(c.cameraMode, .followUnit(list[0].id))
        XCTAssertEqual(c.presentationFocusID, list[0].id, "戦闘テキスト・揺れも味方に付く")
        model.follow(c.humanHeroID!)
        XCTAssertEqual(c.cameraMode, .followHero)
        // 観戦者には一覧を出さない
        let spectator = HUDModel(controller: BattleController(launch: BattleLaunch(config: MatchFactory.botMatch(seed: 6))))
        XCTAssertTrue(HUDDeathSpectate.allies(spectator).isEmpty)
    }

    /// オンラインの再同期で復活を飛び越えた（.respawned が配られない）: 死亡中の味方追従をやめて自分の追従へ戻る。
    func testResyncPastTheRespawnReturnsTheCameraToTheHero() {
        let app = AppModel(persistence: ServicesFixtures.tempPersistence())
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H001", humanName: "P", seed: 6)))
        let model = HUDModel(controller: c)
        model.start(app: app, onFinish: { _ in })
        defer { model.stop() }
        let (s, me, allies, _) = deadState()
        c.restore(s)
        model.refresh()
        let ally = s.units[allies[1]].id
        model.follow(ally)
        XCTAssertEqual(c.cameraMode, .followUnit(ally))
        // 死亡中のままの再同期では味方の追従を続ける
        var stillDead = s
        stillDead.time += 1
        stillDead.units[me].hero?.respawnTimer = 14
        c.restore(stillDead)
        model.refresh()
        XCTAssertEqual(c.cameraMode, .followUnit(ally), "死亡中の再同期では味方を見続ける")
        XCTAssertEqual(model.cameraFollowID, ally)
        // 復活した後の状態へ置き換わった（ホストのスナップショットが復活の tick より先）
        var alive = stillDead
        alive.time += 20
        alive.units[me].isAlive = true
        alive.units[me].hero?.respawnTimer = 0
        alive.units[me].hp = alive.units[me].stats.maxHP
        c.restore(alive)
        model.refresh()
        XCTAssertNil(model.cameraFollowID)
        XCTAssertEqual(c.cameraMode, .followHero, "復活を飛び越えた再同期では自分の追従へ戻る")
    }

    // MARK: 配置

    private let devices: [(name: String, size: CGSize, side: CGFloat, bottom: CGFloat)] = [
        ("iPhone SE", CGSize(width: 667, height: 375), 0, 0),
        ("iPhone 13 mini", CGSize(width: 812, height: 375), 44, 21),
        ("iPhone 16e", CGSize(width: 844, height: 390), 47, 21),
        ("iPhone 17 Pro", CGSize(width: 874, height: 402), 62, 20),
        ("iPhone 17 Pro Max", CGSize(width: 956, height: 440), 62, 20),
    ]

    private func circles(_ l: HUDLayout) -> [(name: String, center: CGPoint, radius: CGFloat)] {
        var out = AttackButtonSlot.allCases.map { ("attack", l.attackCenter(for: $0), l.attackDiameter(for: $0) / 2) }
        for slot in SkillSlot.actives {
            out.append(("skill\(slot.rawValue)", l.skillCenter(slot), (slot == .ultimate ? l.ultDiameter : l.skillDiameter) / 2))
            out.append(("level\(slot.rawValue)", l.levelBadgeCenter(slot), l.levelBadgeDiameter / 2))
        }
        out.append(("spell0", l.spellCenter(0), l.spellDiameter / 2))
        out.append(("spell1", l.spellCenter(1), l.spellDiameter / 2))
        out.append(("recall", l.recallCenter, l.recallDiameter / 2))
        out.append(("joystick", l.joystickRest, l.joystickRadius))
        return out
    }

    func testDeathStripFitsBetweenTheControlsOnEveryDevice() {
        for d in devices {
            for left in [false, true] {
                let safe = EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side)
                let l = HUDLayout(size: d.size, safe: safe, leftHanded: left)
                let strip = HUDDeathMetrics.stripFrame(l, allies: 4)
                let tag = "\(d.name) \(left ? "左利き" : "右手")"
                XCTAssertGreaterThanOrEqual(strip.minX, l.leadingEdge, "\(tag): 左の Safe Area")
                XCTAssertLessThanOrEqual(strip.maxX, l.trailingEdge, "\(tag): 右の Safe Area")
                // ヒーローパネルの上に載る（重ならない）
                let panelTop = l.bottomEdge - HUDRootMetrics.heroPanelHeight(l)
                XCTAssertLessThanOrEqual(strip.maxY, panelTop, "\(tag): ヒーローパネルと重なる")
                XCTAssertFalse(strip.intersects(l.minimapDockFrame), "\(tag): ミニマップと重なる")
                for c in circles(l) {
                    let nearest = CGPoint(x: min(max(c.center.x, strip.minX), strip.maxX),
                                          y: min(max(c.center.y, strip.minY), strip.maxY))
                    XCTAssertGreaterThan(hypot(c.center.x - nearest.x, c.center.y - nearest.y), c.radius,
                                         "\(tag): 味方の一覧が \(c.name) と重なる")
                }
            }
        }
        XCTAssertGreaterThanOrEqual(HUDDeathMetrics.cell, 44, "タッチ領域は 44pt 以上")
        XCTAssertEqual(HUDDeathMetrics.stripSize(allies: 0).width, 44 + 10, "味方がいなくても自動の枠は 1 つ")
    }

    func testCameraLeadKeepsTheAllyAboveTheStrip() {
        // 味方は画面の中央より上（注視点が味方より南）: 一覧は中央より下にある
        XCTAssertLessThan(BattleWorld.deathFollowLead, 0)
        for d in devices {
            let l = HUDLayout(size: d.size, safe: EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side),
                              leftHanded: false)
            XCTAssertGreaterThan(HUDDeathMetrics.stripFrame(l, allies: 4).minY, l.height / 2, "\(d.name): 一覧は画面の下半分")
        }
    }
}
