import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 観戦者の音と触覚（B31）: 追従中のユニットが音の主役、触覚なし、終了は勝敗でなく中立の締めの音、
/// 早送りでは主要でない音を弱める・止める、シーク・再同期の直後は鳴らさない。プレイヤーの音は変わらない。
@MainActor
final class SpectatorAudioTests: XCTestCase {
    private typealias Director = BattleAudioDirector

    private let focus: EntityID = 7
    private let other: EntityID = 8
    private let enemy: EntityID = 9

    private func spectator(speed: Double = 1, suppressed: Bool = false, focus: EntityID? = 7,
                           listener: Vec2 = Vec2(1000, 1000)) -> Director.Context {
        Director.Context(humanID: nil, humanTeam: nil, humanMaxHP: 1, listener: listener, isSpectating: true,
                         focusID: focus, speed: speed, suppressed: suppressed)
    }

    private func player(suppressed: Bool = false) -> Director.Context {
        Director.Context(humanID: focus, humanTeam: .blue, humanMaxHP: 1000, listener: Vec2(1000, 1000), isSpectating: false,
                         suppressed: suppressed)
    }

    private func damage(_ src: EntityID?, _ dst: EntityID, _ amount: Double, crit: Bool = false) -> SimEvent {
        .damage(DamageEvent(sourceID: src, targetID: dst, amount: amount, absorbed: 0, damageType: .physical,
                            source: .basicAttack, isCrit: crit, pos: .zero))
    }

    private func kill(victim: EntityID, killer: EntityID?) -> SimEvent {
        .heroKilled(HeroKillEvent(victimID: victim, killerID: killer, assistIDs: [], bounty: 300, isFirstBlood: false,
                                  multiKill: 1, killerStreak: 1, isShutdown: false))
    }

    private func cast(by caster: EntityID, at p: Vec2, slot: SkillSlot = .skill2) -> SimEvent {
        .skillCast(SkillCastEvent(casterID: caster, heroID: "H001", slot: slot, skillID: "SK001_3", effectID: "",
                                  archetype: .dashStrike, origin: p, target: p, range: 300, radius: 100))
    }

    /// 試合で起こりうる代表的なイベント。
    private var sampleEvents: [SimEvent] {
        [.attackReleased(sourceID: focus, targetID: enemy, isRanged: false), damage(focus, enemy, 50, crit: true),
         damage(enemy, focus, 900), kill(victim: enemy, killer: focus), kill(victim: focus, killer: enemy),
         kill(victim: other, killer: enemy), .levelUp(heroID: focus, level: 3), .goldGained(heroID: focus, amount: 20, pos: .zero),
         .respawned(heroID: focus, pos: .zero), .channelStarted(heroID: focus, kind: .recall, duration: 8),
         .channelCompleted(heroID: focus, kind: .recall, destination: .zero), .itemPurchased(heroID: focus, itemID: "I001"),
         .announcement(.towerDestroyed(team: .red, lane: .mid, tier: .outer)), .announcement(.multiKill(killerID: focus, count: 3)),
         .announcement(.wyrmSlain(team: .blue)), .announcement(.minionsSpawned),
         .matchEnded(winner: .blue, reason: .coreDestroyed), cast(by: focus, at: Vec2(9000, 9000))]
    }

    // MARK: 観戦者

    func testSpectatorsNeverGetHaptics() {
        for e in sampleEvents {
            for c in Director.cues(for: e, context: spectator()) {
                if case .haptic = c { XCTFail("観戦者に触覚: \(e) → \(c)") }
            }
        }
    }

    func testFollowedUnitIsTheAudioFocus() {
        let c = spectator()
        XCTAssertEqual(Director.cues(for: .attackReleased(sourceID: focus, targetID: enemy, isRanged: true), context: c),
                       [.sound(.attackRanged, gain: 0.4)])
        XCTAssertEqual(Director.cues(for: .attackReleased(sourceID: other, targetID: enemy, isRanged: true), context: c), [],
                       "追従していないユニットの攻撃音は鳴らさない")
        XCTAssertEqual(Director.cues(for: damage(focus, enemy, 50), context: c), [.sound(.hit, gain: 0.4)])
        XCTAssertEqual(Director.cues(for: damage(focus, enemy, 50, crit: true), context: c), [.sound(.crit, gain: 0.7)])
        XCTAssertEqual(Director.cues(for: damage(enemy, focus, 900), context: c), [], "被弾の触覚なし")
        XCTAssertEqual(Director.cues(for: cast(by: focus, at: Vec2(9000, 9000)), context: c), [.sound(.skillCast, gain: 0.85)],
                       "追従中のヒーローのスキルは距離に関係なく鳴る")
        XCTAssertEqual(Director.cues(for: cast(by: other, at: Vec2(9000, 9000)), context: c), [])
        XCTAssertEqual(Director.cues(for: .levelUp(heroID: focus, level: 4), context: c), [.sound(.levelUp, gain: 0.6)])
        XCTAssertEqual(Director.cues(for: .levelUp(heroID: other, level: 4), context: c), [])
        XCTAssertEqual(Director.cues(for: .respawned(heroID: focus, pos: .zero), context: c), [.sound(.respawn, gain: 0.75)])
        XCTAssertEqual(Director.cues(for: kill(victim: enemy, killer: focus), context: c), [.sound(.kill, gain: 0.85)])
        XCTAssertEqual(Director.cues(for: kill(victim: focus, killer: enemy), context: c), [.sound(.death, gain: 0.75)])
        XCTAssertEqual(Director.cues(for: kill(victim: other, killer: enemy), context: c), [.sound(.kill, gain: 0.45)],
                       "他のキルも控えめに鳴らす")
        XCTAssertEqual(Director.cues(for: .itemPurchased(heroID: focus, itemID: "I001"), context: c), [],
                       "購入の音は操作した本人への手応え")
        // 誰も追従していない（自由視点）: 主役の音は無く、カメラ付近のスキルとキルだけ
        let free = spectator(focus: nil)
        XCTAssertEqual(Director.cues(for: damage(nil, enemy, 50), context: free), [])
        XCTAssertEqual(Director.cues(for: .attackReleased(sourceID: focus, targetID: enemy, isRanged: false), context: free), [])
        XCTAssertEqual(Director.cues(for: kill(victim: other, killer: enemy), context: free), [.sound(.kill, gain: 0.45)])
        guard case .sound(_, let near)? = Director.cues(for: cast(by: other, at: Vec2(1100, 1000)), context: free).first else {
            return XCTFail("カメラ付近のスキル音")
        }
        XCTAssertLessThan(near, 0.85)
    }

    func testSpectatorsHearANeutralEndStingAndAnnouncementsWithoutHaptics() {
        let c = spectator()
        XCTAssertEqual(Director.cues(for: .matchEnded(winner: .blue, reason: .coreDestroyed), context: c),
                       [.sound(.objective, gain: 1)], "勝利・敗北ではなく中立の締めの音")
        XCTAssertEqual(Director.cues(for: .matchEnded(winner: .red, reason: .surrender), context: c), [.sound(.objective, gain: 1)])
        XCTAssertEqual(Director.cues(for: .matchEnded(winner: nil, reason: .aborted), context: c), [])
        XCTAssertEqual(Director.cues(for: .announcement(.towerDestroyed(team: .red, lane: .mid, tier: .outer)), context: c),
                       [.sound(.towerDestroyed, gain: 1)])
        XCTAssertEqual(Director.cues(for: .announcement(.minionsSpawned), context: c), [.sound(.announcement, gain: 0.7)])
    }

    func testFastPlaybackDampensThenDropsNonEssentialSounds() {
        let hit = damage(focus, enemy, 50)
        let k = kill(victim: enemy, killer: focus)
        let tower = SimEvent.announcement(.towerDestroyed(team: .red, lane: .mid, tier: .outer))
        for speed in [0.5, 1, 2] {
            XCTAssertEqual(Director.cues(for: hit, context: spectator(speed: speed)), [.sound(.hit, gain: 0.4)], "\(speed)×")
        }
        XCTAssertEqual(Director.cues(for: hit, context: spectator(speed: 4)), [.sound(.hit, gain: 0.4 * Director.dampenedGain)],
                       "2 倍速を超えると弱める")
        XCTAssertEqual(Director.cues(for: hit, context: spectator(speed: 8)), [], "4 倍速を超えると鳴らさない")
        XCTAssertEqual(Director.cues(for: .goldGained(heroID: focus, amount: 20, pos: .zero), context: spectator(speed: 8)), [])
        for speed in [4.0, 8] {
            XCTAssertEqual(Director.cues(for: k, context: spectator(speed: speed)), [.sound(.kill, gain: 0.85)],
                           "キルは早送りでも残す")
            XCTAssertEqual(Director.cues(for: tower, context: spectator(speed: speed)), [.sound(.towerDestroyed, gain: 1)])
            XCTAssertEqual(Director.cues(for: .matchEnded(winner: .blue, reason: .coreDestroyed), context: spectator(speed: speed)),
                           [.sound(.objective, gain: 1)])
        }
        XCTAssertTrue(Director.isEssential(.kill))
        XCTAssertTrue(Director.isEssential(.objective))
        XCTAssertFalse(Director.isEssential(.hit))
        XCTAssertFalse(Director.isEssential(.skillCast))
    }

    func testNothingButTheEndPlaysRightAfterASeekOrResync() {
        for e in sampleEvents {
            let cues = Director.cues(for: e, context: spectator(suppressed: true))
            if case .matchEnded = e {
                XCTAssertEqual(cues, [.sound(.objective, gain: 1)], "終了の音は鳴らす")
            } else {
                XCTAssertEqual(cues, [], "シーク直後: \(e)")
            }
        }
        // プレイヤーの再同期の直後も、追いつきの連続イベントで鳴らし続けない（終了は鳴らす）
        XCTAssertEqual(Director.cues(for: kill(victim: enemy, killer: focus), context: player(suppressed: true)), [])
        XCTAssertEqual(Director.cues(for: damage(enemy, focus, 900), context: player(suppressed: true)), [])
        XCTAssertEqual(Director.cues(for: .matchEnded(winner: .blue, reason: .coreDestroyed), context: player(suppressed: true)),
                       [.sound(.victory, gain: 1), .haptic(.victory)])
    }

    // MARK: プレイヤーは変わらない

    func testPlayerCuesAreUnchanged() {
        let c = player()
        XCTAssertEqual(Director.cues(for: kill(victim: enemy, killer: focus), context: c), [.sound(.kill, gain: 1), .haptic(.kill)])
        XCTAssertEqual(Director.cues(for: .matchEnded(winner: .blue, reason: .coreDestroyed), context: c),
                       [.sound(.victory, gain: 1), .haptic(.victory)])
        XCTAssertEqual(Director.cues(for: .matchEnded(winner: .red, reason: .coreDestroyed), context: c),
                       [.sound(.defeat, gain: 1), .haptic(.defeat)])
        XCTAssertEqual(Director.cues(for: .announcement(.towerDestroyed(team: .red, lane: .mid, tier: .outer)), context: c),
                       [.sound(.towerDestroyed, gain: 1), .haptic(.announcement)])
        XCTAssertEqual(Director.cues(for: .itemPurchased(heroID: focus, itemID: "I001"), context: c), [.sound(.purchase, gain: 1)])
        // 既定の Context（既存の呼び出し）は速度 1・抑制なし
        let legacy = Director.Context(humanID: focus, humanTeam: .blue, humanMaxHP: 1000, listener: .zero, isSpectating: false)
        XCTAssertEqual(legacy.speed, 1)
        XCTAssertFalse(legacy.suppressed)
        XCTAssertNil(legacy.focusID)
    }
}
