import XCTest
import SwiftUI
@testable import VELSTRIA
import VelstriaCore

// 担当: battle-hud。HUD の配置（iPhone 16e 〜 17 Pro Max の横画面、左右配置）: 画面内・Safe Area 内・重なり無し・44pt 以上。
// あわせて効果音の対応表と HUDModel の告知・状態アイコンを確認する。

final class HUDLayoutTests: XCTestCase {
    /// 横画面の論理サイズと Safe Area（左右 = Dynamic Island / ノッチ側、下 = ホームインジケータ）。
    private let devices: [(name: String, size: CGSize, side: CGFloat, bottom: CGFloat)] = [
        ("iPhone 13 mini", CGSize(width: 812, height: 375), 44, 21),
        ("iPhone 16e", CGSize(width: 844, height: 390), 47, 21),
        ("iPhone 17 Pro", CGSize(width: 874, height: 402), 62, 20),
        ("iPhone 17 Pro Max", CGSize(width: 956, height: 440), 62, 20),
    ]

    private struct Circle2 {
        var name: String
        var center: CGPoint
        var radius: CGFloat
    }

    private func controls(_ l: HUDLayout) -> [Circle2] {
        var out = AttackButtonSlot.allCases.map {
            Circle2(name: "attack_\($0.rawValue)", center: l.attackCenter(for: $0), radius: l.attackDiameter(for: $0) / 2)
        }
        for slot in SkillSlot.actives {
            out.append(Circle2(name: "skill\(slot.rawValue)", center: l.skillCenter(slot),
                               radius: (slot == .ultimate ? l.ultDiameter : l.skillDiameter) / 2))
            out.append(Circle2(name: "level\(slot.rawValue)", center: l.levelBadgeCenter(slot), radius: l.levelBadgeDiameter / 2))
        }
        out.append(Circle2(name: "spell0", center: l.spellCenter(0), radius: l.spellDiameter / 2))
        out.append(Circle2(name: "spell1", center: l.spellCenter(1), radius: l.spellDiameter / 2))
        out.append(Circle2(name: "recall", center: l.recallCenter, radius: l.recallDiameter / 2))
        return out
    }

    func testControlsStayInsideSafeAreaWithoutOverlap() {
        for d in devices {
            for left in [false, true] {
                let safe = EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side)
                let l = HUDLayout(size: d.size, safe: safe, leftHanded: left)
                let cs = controls(l)
                for c in cs {
                    XCTAssertGreaterThanOrEqual(c.center.x - c.radius, d.side - 0.5, "\(d.name) \(c.name) が左の Safe Area にかかる")
                    XCTAssertLessThanOrEqual(c.center.x + c.radius, d.size.width - d.side + 0.5, "\(d.name) \(c.name) が右の Safe Area にかかる")
                    XCTAssertLessThanOrEqual(c.center.y + c.radius, d.size.height - d.bottom + 0.5, "\(d.name) \(c.name) がホームインジケータにかかる")
                    XCTAssertGreaterThan(c.center.y - c.radius, l.minimapFrame.minY, "\(d.name) \(c.name) が画面上端を越える")
                    let map = l.minimapDockFrame
                    let nearest = CGPoint(x: min(max(c.center.x, map.minX), map.maxX),
                                          y: min(max(c.center.y, map.minY), map.maxY))
                    XCTAssertGreaterThan(hypot(c.center.x - nearest.x, c.center.y - nearest.y), c.radius,
                                         "\(d.name) \(c.name) がミニマップと重なる")
                }
                for i in cs.indices {
                    for j in cs.indices where j > i {
                        let a = cs[i], b = cs[j]
                        let dist = hypot(a.center.x - b.center.x, a.center.y - b.center.y)
                        XCTAssertGreaterThan(dist, a.radius + b.radius + 2, "\(d.name) \(left ? "左利き" : "右手") \(a.name) と \(b.name) が重なる")
                    }
                }
                // ヒーローパネルはスティックとスキル群の間に収まる
                let panelMin = l.heroPanelCenterX - l.heroPanelWidth / 2
                let panelMax = l.heroPanelCenterX + l.heroPanelWidth / 2
                let joyNear = left ? l.joystickRest.x - l.joystickRadius : l.joystickRest.x + l.joystickRadius
                if left {
                    XCTAssertLessThan(panelMax, joyNear, "\(d.name) パネルとスティック")
                    XCTAssertGreaterThan(panelMin, l.clusterInnerEdge, "\(d.name) パネルとスキル群")
                } else {
                    XCTAssertGreaterThan(panelMin, joyNear, "\(d.name) パネルとスティック")
                    XCTAssertLessThan(panelMax, l.clusterInnerEdge, "\(d.name) パネルとスキル群")
                }
                // スティックの土台は Safe Area 内
                XCTAssertGreaterThanOrEqual(l.joystickRest.x - l.joystickRadius, d.side)
                XCTAssertLessThanOrEqual(l.joystickRest.x + l.joystickRadius, d.size.width - d.side)
                // ミニマップは Safe Area 内（左上）
                XCTAssertGreaterThanOrEqual(l.minimapFrame.minX, d.side)
                XCTAssertLessThan(l.minimapFrame.maxY, l.joystickRest.y - l.joystickRadius)
            }
        }
    }

    func testTouchTargetsAreAtLeast44pt() {
        for d in devices {
            let l = HUDLayout(size: d.size, safe: EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side),
                              leftHanded: false)
            for slot in AttackButtonSlot.allCases {
                XCTAssertGreaterThanOrEqual(l.attackDiameter(for: slot), 44)
            }
            XCTAssertGreaterThanOrEqual(l.skillDiameter, 44)
            XCTAssertGreaterThanOrEqual(l.ultDiameter, 44)
            XCTAssertGreaterThanOrEqual(l.spellDiameter, 44)
            XCTAssertGreaterThanOrEqual(l.recallDiameter, 44)
            XCTAssertGreaterThanOrEqual(l.joystickRadius * 2, 44)
            XCTAssertGreaterThanOrEqual(l.minimapSize, 44)
        }
    }

    func testLeftHandedMirrorsControls() {
        for d in devices {
            let safe = EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side)
            let r = HUDLayout(size: d.size, safe: safe, leftHanded: false)
            let l = HUDLayout(size: d.size, safe: safe, leftHanded: true)
            for (right, left) in zip(controls(r), controls(l)) {
                XCTAssertEqual(right.center.x, d.size.width - left.center.x, accuracy: 1e-6, right.name)
                XCTAssertEqual(right.center.y, left.center.y, accuracy: 1e-6, right.name)
                XCTAssertEqual(right.radius, left.radius, accuracy: 1e-6, right.name)
            }
            XCTAssertEqual(r.joystickRest.x, d.size.width - l.joystickRest.x, accuracy: 1e-6)
            XCTAssertLessThan(l.attackCenter.x, d.size.width / 2)
            XCTAssertLessThan(l.cancelCenter.x, d.size.width / 2, "キャンセル領域もスキル側へ")
            XCTAssertGreaterThan(l.joystickZone.minX, d.size.width / 2 - 1)
        }
    }

    @MainActor
    func testLevelBadgeTouchRectanglesDoNotOverlapControls() {
        let half = HUDLevelBadge.touchDiameter / 2
        XCTAssertGreaterThanOrEqual(HUDLevelBadge.touchDiameter, 44)
        for d in devices {
            for left in [false, true] {
                let safe = EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side)
                let l = HUDLayout(size: d.size, safe: safe, leftHanded: left)
                let circles = controls(l).filter { !$0.name.hasPrefix("level") }
                let badges = SkillSlot.actives.map { slot in
                    let center = l.levelBadgeCenter(slot)
                    return CGRect(x: center.x - half, y: center.y - half,
                                  width: HUDLevelBadge.touchDiameter, height: HUDLevelBadge.touchDiameter)
                }
                for (index, rect) in badges.enumerated() {
                    XCTAssertGreaterThanOrEqual(rect.minX, d.side)
                    XCTAssertLessThanOrEqual(rect.maxX, d.size.width - d.side)
                    XCTAssertGreaterThanOrEqual(rect.minY, l.topEdge)
                    XCTAssertLessThanOrEqual(rect.maxY, l.bottomEdge)
                    XCTAssertFalse(rect.intersects(l.minimapDockFrame))
                    for circle in circles {
                        let nearest = CGPoint(x: min(max(circle.center.x, rect.minX), rect.maxX),
                                              y: min(max(circle.center.y, rect.minY), rect.maxY))
                        XCTAssertGreaterThan(hypot(circle.center.x - nearest.x, circle.center.y - nearest.y),
                                             circle.radius + 2, "\(d.name) 習得ボタン \(index) と \(circle.name) のタップ領域")
                    }
                    for other in badges.dropFirst(index + 1) {
                        XCTAssertFalse(rect.insetBy(dx: -1, dy: -1).intersects(other.insetBy(dx: -1, dy: -1)))
                    }
                }
            }
        }
    }

    func testAttackButtonsStayInTopCenterBottomOrder() {
        for d in devices {
            for left in [false, true] {
                let safe = EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side)
                let l = HUDLayout(size: d.size, safe: safe, leftHanded: left)
                let top = l.attackCenter(for: .top)
                let center = l.attackCenter(for: .center)
                let bottom = l.attackCenter(for: .bottom)
                XCTAssertEqual(top.x, center.x)
                XCTAssertEqual(center.x, bottom.x)
                XCTAssertLessThan(top.y + l.attackDiameter(for: .top) / 2, center.y - l.attackDiameter / 2)
                XCTAssertLessThan(center.y + l.attackDiameter / 2, bottom.y - l.attackDiameter(for: .bottom) / 2)
                XCTAssertGreaterThan(l.attackDiameter, l.attackDiameter(for: .top))
                XCTAssertGreaterThan(l.attackDiameter, l.attackDiameter(for: .bottom))
                XCTAssertEqual(center, l.attackCenter, "中央の攻撃ボタンをメイン操作として扱う")
            }
        }
    }

    // MARK: 効果音・触覚

    private func ctx(listener: Vec2 = Vec2(1000, 1000)) -> BattleAudioDirector.Context {
        BattleAudioDirector.Context(humanID: 7, humanTeam: .blue, humanMaxHP: 1000, listener: listener, isSpectating: false)
    }

    private func damage(_ src: EntityID?, _ dst: EntityID, _ amount: Double, crit: Bool = false) -> SimEvent {
        .damage(DamageEvent(sourceID: src, targetID: dst, amount: amount, absorbed: 0, damageType: .physical,
                            source: .basicAttack, isCrit: crit, pos: .zero))
    }

    func testAudioCuesForHumanEvents() {
        let c = ctx()
        XCTAssertEqual(BattleAudioDirector.cues(for: .attackReleased(sourceID: 7, targetID: 9, isRanged: true), context: c),
                       [.sound(.attackRanged, gain: 0.55)])
        XCTAssertEqual(BattleAudioDirector.cues(for: .attackReleased(sourceID: 8, targetID: 9, isRanged: true), context: c), [])
        XCTAssertEqual(BattleAudioDirector.cues(for: damage(7, 9, 50, crit: true), context: c), [.sound(.crit, gain: 0.9)])
        // 大きな被弾は触覚、小さな被弾は何もしない
        XCTAssertEqual(BattleAudioDirector.cues(for: damage(9, 7, 20), context: c), [])
        let hard = BattleAudioDirector.cues(for: damage(9, 7, 200), context: c)
        XCTAssertEqual(hard.count, 1)
        if case .haptic(.hitHard(let i))? = hard.first { XCTAssertGreaterThan(i, 0.5) } else { XCTFail() }
        let kill = SimEvent.heroKilled(HeroKillEvent(victimID: 9, killerID: 7, assistIDs: [], bounty: 300,
                                                     isFirstBlood: false, multiKill: 1, killerStreak: 1, isShutdown: false))
        XCTAssertEqual(BattleAudioDirector.cues(for: kill, context: c), [.sound(.kill, gain: 1), .haptic(.kill)])
        let death = SimEvent.heroKilled(HeroKillEvent(victimID: 7, killerID: 9, assistIDs: [], bounty: 300,
                                                      isFirstBlood: false, multiKill: 1, killerStreak: 1, isShutdown: false))
        XCTAssertEqual(BattleAudioDirector.cues(for: death, context: c), [.sound(.death, gain: 1), .haptic(.death)])
        XCTAssertEqual(BattleAudioDirector.cues(for: .levelUp(heroID: 7, level: 2), context: c),
                       [.sound(.levelUp, gain: 1), .haptic(.levelUp)])
        XCTAssertEqual(BattleAudioDirector.cues(for: .levelUp(heroID: 8, level: 2), context: c), [])
        XCTAssertEqual(BattleAudioDirector.cues(for: .matchEnded(winner: .blue, reason: .coreDestroyed), context: c),
                       [.sound(.victory, gain: 1), .haptic(.victory)])
        XCTAssertEqual(BattleAudioDirector.cues(for: .matchEnded(winner: .red, reason: .coreDestroyed), context: c),
                       [.sound(.defeat, gain: 1), .haptic(.defeat)])
        XCTAssertEqual(BattleAudioDirector.cues(for: .matchEnded(winner: nil, reason: .aborted), context: c), [])
        XCTAssertEqual(BattleAudioDirector.cues(for: .announcement(.towerDestroyed(team: .red, lane: .mid, tier: .outer)), context: c),
                       [.sound(.towerDestroyed, gain: 1), .haptic(.announcement)])
        XCTAssertEqual(BattleAudioDirector.cues(for: .announcement(.minionsSpawned), context: c),
                       [.sound(.announcement, gain: 0.7)], "定期的な告知は触覚なし")
    }

    func testSkillSoundsAttenuateWithDistanceFromCamera() {
        func cast(at p: Vec2, caster: EntityID) -> SimEvent {
            .skillCast(SkillCastEvent(casterID: caster, heroID: "H001", slot: .skill2, skillID: "SK001_3", effectID: "",
                                      archetype: .dashStrike, origin: p, target: p, range: 300, radius: 100))
        }
        let c = ctx(listener: Vec2(1000, 1000))
        XCTAssertEqual(BattleAudioDirector.cues(for: cast(at: Vec2(9000, 9000), caster: 7), context: c),
                       [.sound(.skillCast, gain: 1)], "自分のスキルは距離に関係なく鳴る")
        XCTAssertEqual(BattleAudioDirector.cues(for: cast(at: Vec2(9000, 9000), caster: 8), context: c), [])
        guard case .sound(_, let near)? = BattleAudioDirector.cues(for: cast(at: Vec2(1100, 1000), caster: 8), context: c).first,
              case .sound(_, let far)? = BattleAudioDirector.cues(for: cast(at: Vec2(2200, 1000), caster: 8), context: c).first else {
            return XCTFail("カメラ付近のスキル音")
        }
        XCTAssertGreaterThan(near, far)
    }

    // MARK: HUDModel

    @MainActor
    func testBannersForAnnouncements() {
        let saved = Loc.current
        defer { Loc.current = saved }
        Loc.current = .en
        let c = BattleController(launch: BattleLaunch(config: MatchFactory.standardMatch(humanHeroID: "H003", humanName: "T", seed: 3)))
        let m = HUDModel(controller: c)
        let me = c.humanHeroID!
        let enemy = c.state.heroIndices(team: .red).first.map { c.state.units[$0].id }!
        let penta = m.makeBanner(.multiKill(killerID: me, count: 5))
        XCTAssertEqual(penta?.title, "PENTAKILL")
        XCTAssertEqual(penta?.tone, .epic)
        XCTAssertEqual(m.makeBanner(.multiKill(killerID: me, count: 2))?.title, "Double Kill")
        XCTAssertEqual(m.makeBanner(.firstBlood(killerID: me, victimID: enemy))?.tone, .ally)
        XCTAssertEqual(m.makeBanner(.firstBlood(killerID: enemy, victimID: me))?.tone, .enemy)
        XCTAssertEqual(m.makeBanner(.towerDestroyed(team: .blue, lane: .top, tier: .inner))?.title, "Your Tower Was Destroyed")
        XCTAssertEqual(m.makeBanner(.towerDestroyed(team: .red, lane: .top, tier: .inner))?.tone, .ally)
        XCTAssertEqual(m.makeBanner(.ace(team: .blue))?.title, "Ace!")
        XCTAssertNil(m.makeBanner(.victory(team: .blue)), "勝敗は終了演出で表示")
        let spree = m.makeBanner(.killingSpree(killerID: me, streak: 8))
        XCTAssertEqual(spree?.title, "Legendary")
    }

    @MainActor
    func testStatusIconsMergeAndSortDebuffsFirst() {
        var u = VelstriaCore.Unit(id: 1, kind: .hero, team: .blue, pos: .zero, radius: 55, stats: Stats())
        u.statuses = [
            StatusEffect(kind: .speedBoost, duration: 2, magnitude: 0.2),
            StatusEffect(kind: .slow, duration: 1.5, magnitude: 0.3),
            StatusEffect(kind: .slow, duration: 3, magnitude: 0.1, tag: "b"),
            StatusEffect(kind: .revealed, duration: 60),
        ]
        let icons = HUDModel.statusIcons(u)
        XCTAssertEqual(icons.map(\.kind), [.slow, .speedBoost], "同種はまとめ、弱体が先、長時間の内部状態は出さない")
        XCTAssertEqual(icons[0].remaining, 3, accuracy: 1e-9)
        XCTAssertFalse(icons[0].isBuff)
    }
}
