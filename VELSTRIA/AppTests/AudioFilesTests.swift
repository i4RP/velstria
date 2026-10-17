import AVFoundation
import XCTest
@testable import VELSTRIA

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
}
