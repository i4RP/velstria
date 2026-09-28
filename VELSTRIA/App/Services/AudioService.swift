import Foundation
import AVFoundation

// 担当: app-services（未実装。AVAudioEngine による手続き生成の効果音・BGM を実装すること。音源ファイル不要）

enum SFX: String, CaseIterable {
    case uiTap, uiConfirm, uiBack, uiError, purchase, reward, levelUp
    case attackMelee, attackRanged, hit, crit, skillCast, ultimateCast, heal, shield
    case death, kill, multiKill, towerDestroyed, objective, gold, recall, respawn
    case countdown, victory, defeat, announcement
}

enum MusicTrack: String, CaseIterable {
    case menu, battle, victory, defeat
}

@MainActor
final class AudioService {
    private(set) var bgmVolume: Double = 0.7
    private(set) var sfxVolume: Double = 0.8

    init() {}

    func apply(settings: GameSettings) {
        bgmVolume = settings.bgmVolume
        sfxVolume = settings.sfxVolume
    }

    func play(_ sfx: SFX) {}
    func playMusic(_ track: MusicTrack) {}
    func stopMusic() {}
}
