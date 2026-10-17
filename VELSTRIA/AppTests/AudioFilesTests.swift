import AVFoundation
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 音のファイル（AudioFiles。CC0 の素材を tools/audio/build_audio.py で加工したもの）: 同梱・形式・AudioService が使うこと・出典の表記。
@MainActor
final class AudioFilesTests: XCTestCase {
    /// 効果音は 44.1 kHz モノラル、BGM は 44.1 kHz ステレオ（AudioService のプレイヤーの形式そのまま）で同梱している。
    func testEveryMappedFileIsBundledInThePlayerFormat() throws {
        var sfxCount = 0
        for s in SFX.allCases {
            guard let name = AudioFiles.sfx(s) else { continue }
            sfxCount += 1
            let url = try XCTUnwrap(AudioFiles.sfxURL(name), "\(name).caf が無い")
            let f = try AVAudioFile(forReading: url)
            XCTAssertEqual(f.processingFormat.sampleRate, SFXSynth.sampleRate, name)
            XCTAssertEqual(f.processingFormat.channelCount, 1, name)
            let samples = try XCTUnwrap(AudioFiles.readMono(url, sampleRate: SFXSynth.sampleRate), name)
            XCTAssertGreaterThan(samples.count, Int(SFXSynth.sampleRate * 0.02), name)
            XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.1, "\(name) が無音")
        }
        XCTAssertGreaterThanOrEqual(sfxCount, 14)
        var musicCount = 0
        for t in MusicTrack.allCases {
            guard let name = AudioFiles.music(t) else { continue }
            musicCount += 1
            let url = try XCTUnwrap(AudioFiles.musicURL(name), "\(name).m4a が無い")
            let f = try AVAudioFile(forReading: url)
            XCTAssertEqual(f.processingFormat.sampleRate, MusicComposer.sampleRate, name)
            XCTAssertEqual(f.processingFormat.channelCount, 2, name)
            XCTAssertGreaterThan(Double(f.length) / f.processingFormat.sampleRate, 20, "\(name) が短すぎる")
        }
        XCTAssertEqual(musicCount, 8)
    }

    /// AudioService はファイルのある効果音をファイルで鳴らし（合成は 0.8 秒まで。試合開始の合図のファイルは 2 秒ある）、
    /// ファイルの曲を用意済みとして扱う。ホームの選べる曲にファイルの 3 曲が入っている。
    func testServiceUsesTheFiles() async {
        let audio = AudioService()
        await audio.waitUntilSFXReady()
        XCTAssertGreaterThan(audio.sfxDuration(.matchStart) ?? 0, 1.0, "ファイルの音を読んでいる")
        XCTAssertNotNil(audio.sfxDuration(.uiTab))
        XCTAssertTrue(audio.isMusicPrepared(.lobby))
        for t in [MusicTrack.menuLegend, .menuFantasia, .menuJourney] {
            XCTAssertTrue(MusicTrack.selectableMenuTracks.contains(t))
            XCTAssertTrue(t.loops)
        }
        XCTAssertFalse(MusicTrack.victory.loops)
        // ファイルの曲を流してから合成の曲へ切り替えても、終わったファイルの曲の予約し直しで戻らない
        audio.playMusic(.lobby)
        XCTAssertEqual(audio.currentTrack, .lobby)
        audio.playMusic(.battle)
        XCTAssertEqual(audio.currentTrack, .battle)
        audio.stopMusic()
        XCTAssertNil(audio.currentTrack)
    }

    /// クレジットの「音楽・効果音」と docs/audio/SOURCES.md の素材の表が同じ素材を挙げている（CC0 の作者と URL）。
    func testCreditsListEverySource() throws {
        let doc = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/audio/SOURCES.md")
        let text = try String(contentsOf: doc, encoding: .utf8)
        let rows = text.split(separator: "\n").filter { $0.hasPrefix("| ") && $0.contains("| CC0 1.0 |") }
        XCTAssertEqual(rows.count, CreditsCatalog.audio.count, "素材の表とクレジットの数が違う")
        for a in CreditsCatalog.audio {
            XCTAssertTrue(text.contains(a.url), "\(a.title) が SOURCES.md に無い")
            XCTAssertTrue(text.contains(a.author), a.title)
        }
        XCTAssertFalse(text.lowercased().contains("mobile legends"), "MLBB の音は使わない")
    }

    // MARK: スキルの音（H025〜H034）

    /// 10 体の S1・S2・奥義の発動の音と、再使用の段（H029 S2・H032 S2・H033 奥義）の音がある。
    func testSkillSoundFilesExistForTheTenHeroes() {
        for n in 25...34 {
            let id = String(format: "H%03d", n)
            for slot in [SkillSlot.skill1, .skill2, .ultimate] {
                let key = SkillSoundKey(heroID: id, slot: slot)
                XCTAssertNotNil(AudioFiles.sfxURL(key.fileName), "\(key.fileName).caf が無い")
            }
        }
        for (id, slot) in [("H029", SkillSlot.skill2), ("H032", .skill2), ("H033", .ultimate)] {
            XCTAssertNotNil(AudioFiles.sfxURL(SkillSoundKey(heroID: id, slot: slot, stage: 1).fileName), "\(id) の再使用の段")
        }
        XCTAssertEqual(SkillSoundKey(heroID: "H029", slot: .skill2, stage: 1).fileName, "skill_H029_s2_r1_cast")
        XCTAssertEqual(SkillSoundKey(heroID: "H034", slot: .ultimate, hit: true).fileName, "skill_H034_ult_hit")
    }

    /// 試合に出るヒーローの分だけ読み、試合が終われば捨てる。音の無いスキルは false（汎用の発動の音で代える）。
    func testSkillSoundsLoadOnlyForTheMatchHeroes() async throws {
        let audio = AudioService()
        audio.preloadSkillSounds(heroIDs: ["H029", "H001"])
        let ult = SkillSoundKey(heroID: "H029", slot: .ultimate)
        for _ in 0..<200 where !audio.hasSkillSound(ult) { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(audio.hasSkillSound(ult))
        XCTAssertTrue(audio.hasSkillSound(SkillSoundKey(heroID: "H029", slot: .skill2, stage: 1)))
        XCTAssertFalse(audio.hasSkillSound(SkillSoundKey(heroID: "H030", slot: .ultimate)), "試合に出ないヒーローは読まない")
        XCTAssertFalse(audio.playSkill(SkillSoundKey(heroID: "H001", slot: .skill1), gain: 1), "音の無いスキル")
        XCTAssertTrue(audio.playSkill(ult, gain: 1), "音量 0 でも音があれば汎用の音を重ねない")
        audio.releaseSkillSounds()
        XCTAssertFalse(audio.hasSkillSound(ult))
    }

    /// スキルの命中の音の音量: 自分が撃った・受けた 0.8、ほかは距離で弱める。速い再生・シーク直後は鳴らさない。
    func testSkillHitGain() {
        func d(source: EntityID?, target: EntityID, at pos: Vec2) -> DamageEvent {
            DamageEvent(sourceID: source, targetID: target, amount: 10, absorbed: 0, damageType: .magic,
                        source: .skill(.skill1), isCrit: false, pos: pos)
        }
        let me = EntityID(1), foe = EntityID(2), other = EntityID(3)
        var c = BattleAudioDirector.Context(humanID: me, humanTeam: .blue, humanMaxHP: 1000, listener: Vec2(0, 0), isSpectating: false)
        XCTAssertEqual(BattleAudioDirector.skillHitGain(d(source: me, target: foe, at: Vec2(5000, 0)), context: c), 0.8)
        XCTAssertEqual(BattleAudioDirector.skillHitGain(d(source: foe, target: me, at: Vec2(0, 0)), context: c), 0.8)
        let near = BattleAudioDirector.skillHitGain(d(source: foe, target: other, at: Vec2(850, 0)), context: c)
        XCTAssertEqual(near, 0.25, accuracy: 1e-6)
        XCTAssertEqual(BattleAudioDirector.skillHitGain(d(source: foe, target: other, at: Vec2(3000, 0)), context: c), 0)
        c.speed = 3
        XCTAssertEqual(BattleAudioDirector.skillHitGain(d(source: me, target: foe, at: .zero), context: c), 0.8 * 0.45, accuracy: 1e-6)
        c.speed = 8
        XCTAssertEqual(BattleAudioDirector.skillHitGain(d(source: me, target: foe, at: .zero), context: c), 0)
        c.speed = 1
        c.suppressed = true
        XCTAssertEqual(BattleAudioDirector.skillHitGain(d(source: me, target: foe, at: .zero), context: c), 0)
    }
}
