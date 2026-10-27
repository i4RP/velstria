import AVFoundation
import XCTest
@testable import VELSTRIA
import VelstriaCore

/// 音のファイル（AudioFiles。CC0 の素材を tools/audio/build_audio.py で加工したもの）: 同梱・形式・AudioService が使うこと・出典の表記。
@MainActor
final class AudioFilesTests: XCTestCase {
    /// 効果音はすべて録音のファイル（合成の効果音は無い）: どの SFX にもファイル（揺らぎ込み）があり、モノラル・無音でない。
    /// ファイルは 44.1 kHz（試合の外の画面の音）か 48 kHz（tools/audio/make_sounds.py の録音の音）。BGM は 44.1 kHz ステレオ。
    func testEveryMappedFileIsBundledInThePlayerFormat() throws {
        for s in SFX.allCases {
            let names = AudioFiles.sfxNames(s)
            XCTAssertFalse(names.isEmpty, "\(AudioFiles.sfx(s)).caf（または _1 …）が無い。合成の効果音は使わない")
            for name in names {
                let url = try XCTUnwrap(AudioFiles.sfxURL(name), "\(name).caf が無い")
                let f = try AVAudioFile(forReading: url)
                XCTAssertTrue([44_100.0, 48_000.0].contains(f.processingFormat.sampleRate), name)
                XCTAssertEqual(f.processingFormat.channelCount, 1, name)
                let samples = try XCTUnwrap(AudioFiles.readMono(url, sampleRate: AudioService.sfxSampleRate), name)
                XCTAssertGreaterThan(samples.count, Int(AudioService.sfxSampleRate * 0.02), name)
                XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.05, "\(name) が無音")
            }
        }
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
        XCTAssertEqual(musicCount, 5)
    }

    /// AudioService は効果音をファイルで鳴らし（試合開始の合図のファイルは 2 秒ある）、
    /// ファイルの曲を用意済みとして扱う。廃止したホーム曲は読み込まない。
    func testServiceUsesTheFiles() async {
        let audio = AudioService()
        await audio.waitUntilSFXReady()
        XCTAssertGreaterThan(audio.sfxDuration(.matchStart) ?? 0, 1.0, "ファイルの音を読んでいる")
        XCTAssertNotNil(audio.sfxDuration(.uiTab))
        XCTAssertTrue(audio.isMusicPrepared(.lobby))
        for t in [MusicTrack.menuLegend, .menuFantasia, .menuJourney] {
            XCTAssertNil(AudioFiles.music(t))
            XCTAssertFalse(audio.isMusicPrepared(t))
        }
        XCTAssertFalse(MusicTrack.victory.loops)
        // ファイルの曲を流してからバトルへ移った時は BGM を止める
        audio.playMusic(.lobby)
        XCTAssertEqual(audio.currentTrack, .lobby)
        audio.playMusic(.battle)
        XCTAssertNil(audio.currentTrack)
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
        // Sonniss の素材集（ヒーロー固有の音）も同じ数・同じ題名と作者
        let sonniss = text.split(separator: "\n").filter { $0.hasPrefix("| ") && $0.contains("| Sonniss GDC |") }
        XCTAssertEqual(sonniss.count, CreditsCatalog.sonniss.count, "Sonniss の表とクレジットの数が違う")
        for a in CreditsCatalog.sonniss {
            XCTAssertTrue(sonniss.contains { $0.contains(a.title) && $0.contains(a.author) }, "\(a.title) が SOURCES.md に無い")
        }
    }

    // MARK: スキルの音（H025〜H034）

    /// 10 体の S1・S2・奥義の発動の音と、再使用の段（H029 S2・H032 S2・H033 奥義）の音がある。
    func testSkillSoundFilesExistForTheTenHeroes() {
        // 34 体すべて（旧 24 体は tools/audio/sets/legacy.py の属性と武器の録音、H025〜H034 は heroes/h0xx.py）
        for n in 1...34 {
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
        XCTAssertEqual(SkillSoundKey(heroID: "H029", phase: .attack).fileName, "skill_H029_atk")
        XCTAssertEqual(SkillSoundKey(heroID: "H029", phase: .attackHit).fileName, "skill_H029_atkhit")
        XCTAssertEqual(SkillSoundKey(heroID: "H029", phase: .passive).fileName, "skill_H029_passive")
        XCTAssertTrue(SkillSoundKey(heroID: "H029", phase: .attackHit).hit)
    }

    /// 仕上げたヒーロー（tools/audio/make_sounds.py の heroes/。ローム: H029・H034）は、通常攻撃・通常攻撃の命中・スキルの命中に揺らぎ（_1〜_3 以上）と
    /// パッシブの音がある。揺らぎのある音は揺らぎの無い名前のファイルを置かない（v1 の命中の音は消した）。
    func testFinishedHeroesHaveVariantsAndAPassive() {
        for id in ["H029", "H034"] {
            for base in ["atk", "atkhit", "s1_hit", "s2_hit", "ult_hit"].map({ "skill_\(id)_\($0)" }) {
                for n in 1...3 { XCTAssertNotNil(AudioFiles.sfxURL("\(base)_\(n)"), "\(base)_\(n).caf が無い") }
                XCTAssertNil(AudioFiles.sfxURL(base), "\(base).caf（揺らぎの無い古い音）が残っている")
            }
            XCTAssertNotNil(AudioFiles.sfxURL("skill_\(id)_atk_4"))
            XCTAssertNotNil(AudioFiles.sfxURL("skill_\(id)_passive"))
        }
    }

    /// 34 体すべてに武器の音の組があり、組のファイル（通常攻撃 4・命中 3・会心 2）がそろっている。
    /// 固有の通常攻撃の音が無いヒーローは、試合の始めに組の音を自分の鍵で読む（SkillSoundKey.fallbackFileName）。
    func testEveryHeroHasAWeaponSoundSet() async throws {
        for n in 1...34 {
            let id = String(format: "H%03d", n)
            let set = try XCTUnwrap(WeaponSoundSet.of(heroID: id), id)
            for (phase, count) in [(SkillSoundKey.Phase.attack, 4), (.attackHit, 3), (.crit, 2)] {
                let base = try XCTUnwrap(set.fileName(phase))
                for k in 1...count { XCTAssertNotNil(AudioFiles.sfxURL("\(base)_\(k)"), "\(base)_\(k).caf が無い（\(id)）") }
            }
        }
        let audio = AudioService()
        audio.preloadSkillSounds(heroIDs: ["H001", "H030"])
        let key = SkillSoundKey(heroID: "H001", phase: .attack)
        for _ in 0..<200 where audio.skillVariantCount(SkillSoundKey(heroID: "H030", phase: .crit)) == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(audio.skillVariantCount(key), 4, "固有の音の無い H001 は剣の組の 4 種")
        XCTAssertEqual(audio.skillVariantCount(SkillSoundKey(heroID: "H001", phase: .crit)), 2)
        XCTAssertEqual(audio.skillVariantCount(SkillSoundKey(heroID: "H030", phase: .attackHit)), 3, "砲の組の命中 3 種")
        audio.releaseSkillSounds()
    }

    /// ほかのヒーローの通常攻撃は聞こえる距離の 6 割まで、近いほど大きい。
    func testOtherHeroAttackGainFallsWithDistance() {
        XCTAssertEqual(BattleAudioDirector.otherCombatGain(.zero, listener: .zero, scale: 0.32), 0.32, accuracy: 1e-9)
        let r = BattleAudioDirector.hearingRadius * 0.6
        XCTAssertEqual(BattleAudioDirector.otherCombatGain(Vec2(r / 2, 0), listener: .zero, scale: 0.32), 0.16, accuracy: 1e-9)
        XCTAssertEqual(BattleAudioDirector.otherCombatGain(Vec2(r + 1, 0), listener: .zero, scale: 0.32), 0)
    }

    /// 試合に出るヒーローの分だけ読み、試合が終われば捨てる。音の無いスキルは false（汎用の発動の音で代える）。
    func testSkillSoundsLoadOnlyForTheMatchHeroes() async throws {
        let audio = AudioService()
        audio.preloadSkillSounds(heroIDs: ["H029", "H999"])
        let ult = SkillSoundKey(heroID: "H029", slot: .ultimate)
        for _ in 0..<200 where !audio.hasSkillSound(ult) { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(audio.hasSkillSound(ult))
        XCTAssertTrue(audio.hasSkillSound(SkillSoundKey(heroID: "H029", slot: .skill2, stage: 1)))
        XCTAssertFalse(audio.hasSkillSound(SkillSoundKey(heroID: "H030", slot: .ultimate)), "試合に出ないヒーローは読まない")
        XCTAssertFalse(audio.playSkill(SkillSoundKey(heroID: "H999", slot: .skill1), gain: 1), "音の無いスキル")
        XCTAssertTrue(audio.playSkill(ult, gain: 1), "音量 0 でも音があれば汎用の音を重ねない")
        audio.releaseSkillSounds()
        XCTAssertFalse(audio.hasSkillSound(ult))
    }

    /// パッシブの音は演出が 3 秒止んでいた時だけ（毎秒たまるパッシブは、たまり始めの 1 回）。
    func testPassiveSoundOnlyAfterAQuietSpell() {
        XCTAssertTrue(BattleAudioDirector.passiveSounds(lastFire: nil, now: 10))
        XCTAssertFalse(BattleAudioDirector.passiveSounds(lastFire: 9, now: 10))
        XCTAssertTrue(BattleAudioDirector.passiveSounds(lastFire: 7, now: 10))
        XCTAssertTrue(BattleAudioDirector.passiveSounds(lastFire: 12, now: 10), "巻き戻しの後は鳴らす")
    }

    /// 画面の左右: 聞き手から右は正、左は負、端（panHalfWidth）より外は ±0.85 で止まる。奥義の下げは呼ぶと始まる。
    func testPanAndDuck() async throws {
        XCTAssertEqual(BattleAudioDirector.pan(Vec2(100, 0), listener: Vec2(100, 500)), 0, accuracy: 1e-6)
        XCTAssertGreaterThan(BattleAudioDirector.pan(Vec2(550, 0), listener: Vec2(100, 0)), 0.3)
        XCTAssertLessThan(BattleAudioDirector.pan(Vec2(-350, 0), listener: Vec2(100, 0)), -0.3)
        XCTAssertEqual(BattleAudioDirector.pan(Vec2(9000, 0), listener: .zero), 0.85, accuracy: 1e-6)
        let audio = AudioService()
        XCTAssertFalse(audio.isDucking)
        audio.duckForUltimate(seconds: 0.2)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(audio.isDucking, "奥義の間は下げている")
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertFalse(audio.isDucking, "戻る")
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
