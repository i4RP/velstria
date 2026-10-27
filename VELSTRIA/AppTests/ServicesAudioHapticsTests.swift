import XCTest
import AVFoundation
import UIKit
@testable import VELSTRIA

final class ServicesAudioSynthTests: XCTestCase {
    func testMusicLoopLengthsAndStingers() {
        let battle = MusicComposer.render(.battle)
        XCTAssertTrue(battle.loops)
        XCTAssertEqual(Double(battle.left.count) / battle.sampleRate, 16 * 4 * 60.0 / 128, accuracy: 0.01)
        XCTAssertEqual(battle.left.count, battle.right.count)
        XCTAssertTrue(battle.left.allSatisfy { $0.isFinite && abs($0) <= 0.86 })
        // ループの継ぎ目で大きな段差が無い
        XCTAssertLessThan(abs(battle.left[0] - battle.left[battle.left.count - 1]), 0.2)

        let victory = MusicComposer.render(.victory)
        XCTAssertFalse(victory.loops)
        XCTAssertEqual(Double(victory.left.count) / victory.sampleRate, 5, accuracy: 0.01)
        XCTAssertLessThan(abs(victory.left.last ?? 1), 0.01)
        let defeat = MusicComposer.render(.defeat)
        XCTAssertFalse(defeat.loops)
        XCTAssertGreaterThan(defeat.left.map(abs).max() ?? 0, 0.3)
    }

    func testMenuMusicLoop() {
        let menu = MusicComposer.render(.menu)
        XCTAssertTrue(menu.loops)
        XCTAssertEqual(Double(menu.left.count) / menu.sampleRate, 16 * 4 * 60.0 / 84, accuracy: 0.01)
        XCTAssertGreaterThan(menu.right.map(abs).max() ?? 0, 0.3)
        XCTAssertNotEqual(menu.left, menu.right, "ステレオの広がりがある")
    }
}

@MainActor
final class ServicesAudioServiceTests: XCTestCase {
    func testAudioServiceNeverCrashes() async {
        let audio = AudioService()
        // 再生経路を通すために効果音の音量をはっきり上げてから鳴らす（既定は 70%）
        var loud = GameSettings()
        loud.sfxVolume = 0.8
        audio.apply(settings: loud)
        // 合成はバックグラウンドで行い、完了前の再生要求は無視される
        audio.play(.uiTap)
        await audio.waitUntilSFXReady()
        XCTAssertTrue(audio.sfxReady)
        for sfx in SFX.allCases {
            XCTAssertNotNil(audio.sfxDuration(sfx))
            audio.play(sfx)
        }
        // 大量の同時発生（プール 8 個を超える）
        for _ in 0..<50 { audio.play(.hit, gain: 0.5) }
        var settings = GameSettings()
        settings.bgmVolume = 0
        settings.sfxVolume = 0
        audio.apply(settings: settings)
        XCTAssertEqual(audio.bgmVolume, 0)
        audio.play(.uiTap)
        audio.playMusic(.menu)
        XCTAssertNil(audio.currentTrack)
        audio.playMusic(.victory)
        XCTAssertEqual(audio.currentTrack, .victory)
        audio.stopMusic()
        XCTAssertNil(audio.currentTrack)
    }

    /// ホーム・バトル曲は旧設定や直接指定でも準備・再生せず、スティンガーは再指定で鳴らし直せる。
    func testHomeAndBattleStaySilentAndStingersRetrigger() async throws {
        let audio = AudioService()
        var settings = GameSettings()
        settings.bgmVolume = 1
        for track in [MusicTrack.menu, .menuDream, .menuAdventure, .menuAurora,
                      .menuLegend, .menuFantasia, .menuJourney, .battle] {
            settings.bgmTrack = track.rawValue
            audio.apply(settings: settings)
            audio.playMusic(.lobby)
            XCTAssertEqual(audio.currentTrack, .lobby)
            audio.prepareMusic(track)
            audio.playMusic(track)
            XCTAssertNil(audio.currentTrack, "\(track) への遷移で前の BGM も止める")
            XCTAssertFalse(audio.isMusicPrepared(track), "廃止した曲は読み込み・合成しない")
            audio.playMusic(.menu)
            XCTAssertNil(audio.currentTrack, "保存済みのホーム選曲設定でも無音")
        }
        audio.playMusic(.victory)
        audio.playMusic(.victory)
        XCTAssertEqual(audio.currentTrack, .victory)
        audio.stopMusic()
    }

    /// 割り込み・メディアサービスのリセット（エンジンとノードの作り直し）の後も、再生要求で落ちずに鳴らせる。
    func testSurvivesInterruptionAndMediaServicesReset() async throws {
        let audio = AudioService()
        await audio.waitUntilSFXReady()
        audio.playMusic(.menu)
        let center = NotificationCenter.default
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await Task.sleep(nanoseconds: 50_000_000)
        audio.play(.hit)
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        center.post(name: .AVAudioEngineConfigurationChange, object: nil)
        center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        for sfx in SFX.allCases { audio.play(sfx) }
        for _ in 0..<20 { audio.play(.gold, gain: 0.7) }
        audio.playMusic(.battle)
        XCTAssertNil(audio.currentTrack)
        audio.playMusic(.defeat)
        XCTAssertEqual(audio.currentTrack, .defeat)
        audio.stopMusic()
        XCTAssertNil(audio.currentTrack)
    }
}

@MainActor
final class ServicesHapticsTests: XCTestCase {
    func testRateLimitsBursts() {
        let haptics = HapticsService()
        var now: TimeInterval = 100
        haptics.clock = { now }
        for _ in 0..<20 { haptics.tap() }
        XCTAssertEqual(haptics.firedCount, HapticsService.maxPerSecond)
        XCTAssertEqual(haptics.droppedCount, 20 - HapticsService.maxPerSecond)
        now += 0.5
        haptics.impact(.heavy)
        XCTAssertEqual(haptics.firedCount, 12, "1 秒以内は上限のまま")
        now += 0.6
        haptics.success()
        haptics.selection()
        haptics.impact(.rigid, intensity: 0.4)
        XCTAssertEqual(haptics.firedCount, 15)
    }

    func testDisabledDoesNothing() {
        let haptics = HapticsService()
        haptics.enabled = false
        haptics.tap()
        haptics.warning()
        haptics.error()
        XCTAssertEqual(haptics.firedCount, 0)
        XCTAssertEqual(haptics.droppedCount, 0)
        haptics.enabled = true
        haptics.tap()
        XCTAssertEqual(haptics.firedCount, 1)
    }
}
