import AVFoundation
import Foundation

// 担当: app-services。音のファイル（App/Resources/Audio。CC0 の素材を tools/audio/build_audio.py で加工したもの。
// 出典は docs/audio/SOURCES.md と CreditsView の「音楽・効果音」）。効果音はすべてファイル（合成の効果音は使わない）。
// - 効果音: 44.1 kHz モノラルの .caf。使う前にバッファへ読む（プレイ中にファイルを読まない）。
// - BGM: 44.1 kHz ステレオの .m4a。AVAudioFile から流し読みする（全部をメモリに展開しない）。

enum AudioFiles {
    /// 効果音のファイル名（拡張子なし。揺らぎがある音は 名前_1 … 名前_6 のどれか）。戦闘の音は tools/audio/sets/common.py、
    /// 画面の音は build_audio.py の ui（2026-10-20 から sets/ui.py）が作る。
    static func sfx(_ s: SFX) -> String {
        switch s {
        case .uiTap: return "sfx_ui_tap"
        case .uiConfirm: return "sfx_ui_confirm"
        case .uiBack: return "sfx_ui_back"
        case .uiTab: return "sfx_ui_tab"
        case .uiError: return "sfx_ui_error"
        case .purchase: return "sfx_purchase"
        case .reward: return "sfx_reward"
        case .levelUp: return "sfx_level_up"
        case .attackMelee: return "sfx_attack_melee"
        case .attackRanged: return "sfx_attack_ranged"
        case .hit: return "sfx_hit"
        case .crit: return "sfx_crit"
        case .skillCast: return "sfx_skill_cast"
        case .ultimateCast: return "sfx_ultimate_cast"
        case .heal: return "sfx_heal"
        case .shield: return "sfx_shield"
        case .death: return "sfx_death"
        case .kill: return "sfx_kill"
        case .multiKill: return "sfx_multi_kill"
        case .towerDestroyed: return "sfx_tower_destroyed"
        case .objective: return "sfx_objective"
        case .gold: return "sfx_gold"
        case .recall: return "sfx_recall"
        case .respawn: return "sfx_respawn"
        case .countdown: return "sfx_countdown"
        case .victory: return "sfx_victory"
        case .defeat: return "sfx_defeat"
        case .announcement: return "sfx_announcement"
        case .towerRise: return "sfx_tower_rise"
        case .towerLock: return "sfx_tower_lock"
        case .towerCrack: return "sfx_tower_crack"
        case .towerCollapse: return "sfx_tower_collapse"
        case .towerImpact: return "sfx_tower_impact"
        case .crystalFade: return "sfx_crystal_fade"
        case .matchFound: return "sfx_match_found"
        case .lockIn: return "sfx_lock_in"
        case .ban: return "sfx_ban"
        case .matchStart: return "sfx_match_start"
        }
    }

    /// その効果音のある分のファイル名（揺らぎの無い名前があればそれだけ、無ければ 名前_1 … 名前_6 のある分）。
    static func sfxNames(_ s: SFX, bundle: Bundle = .main) -> [String] {
        let base = sfx(s)
        if sfxURL(base, bundle: bundle) != nil { return [base] }
        return (1...6).map { "\(base)_\($0)" }.filter { sfxURL($0, bundle: bundle) != nil }
    }

    /// BGM のファイル名（拡張子なし）。ホーム・バトルは無音、それ以外の nil は合成。
    static func music(_ t: MusicTrack) -> String? {
        switch t {
        case .lobby: return "bgm_lobby"
        case .draft: return "bgm_draft"
        case .draftTense: return "bgm_draft_tense"
        case .loading: return "bgm_loading"
        case .result: return "bgm_result"
        default: return nil
        }
    }

    static func sfxURL(_ name: String, bundle: Bundle = .main) -> URL? { bundle.url(forResource: name, withExtension: "caf") }
    static func musicURL(_ name: String, bundle: Bundle = .main) -> URL? { bundle.url(forResource: name, withExtension: "m4a") }

    /// ファイルをモノラル・sampleRate の Float の並びに読む（違う形式なら変換する。読めなければ nil）。
    static func readMono(_ url: URL, sampleRate: Double) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let target = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }
        let src = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: frames),
              (try? file.read(into: input)) != nil else { return nil }
        let pcm: AVAudioPCMBuffer
        if src.sampleRate == target.sampleRate, src.channelCount == 1, src.commonFormat == .pcmFormatFloat32 {
            pcm = input
        } else {
            guard let converter = AVAudioConverter(from: src, to: target),
                  let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(
                      Double(frames) * target.sampleRate / src.sampleRate) + 1024) else { return nil }
            var fed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if fed {
                    status.pointee = .endOfStream
                    return nil
                }
                fed = true
                status.pointee = .haveData
                return input
            }
            guard error == nil else { return nil }
            pcm = out
        }
        guard let ch = pcm.floatChannelData, pcm.frameLength > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(pcm.frameLength)))
    }
}
