import Foundation
import AVFoundation
import UIKit

// 担当: app-services
// AVAudioEngine による手続き生成の効果音・BGM（音源ファイルなし）。
// - 効果音: 起動時に全 SFX の PCM を合成（AudioLibrary.swift）。8 個の AVAudioPlayerNode を使い回して重ねて鳴らす。
// - BGM: 曲ごとに一度だけバックグラウンドでレンダリングし .loops でスケジュール。曲の切替はクロスフェード。
//   メモリ節約のため、ループ曲のバッファは再生中の曲だけを保持する（スティンガーは小さいので保持）。
// - AVAudioSession は .ambient（消音スイッチに従い、他のアプリの音と混ざる）。
// - 割り込み・エンジン構成変更・メディアサービスのリセット・フォアグラウンド復帰で再起動する。
// - エンジンが起動できない環境では何もしない（クラッシュさせない）。

enum SFX: String, CaseIterable {
    case uiTap, uiConfirm, uiBack, uiError, purchase, reward, levelUp
    case attackMelee, attackRanged, hit, crit, skillCast, ultimateCast, heal, shield
    case death, kill, multiKill, towerDestroyed, objective, gold, recall, respawn
    case countdown, victory, defeat, announcement
}

enum MusicTrack: String, CaseIterable {
    case menu, battle, victory, defeat

    /// ループ再生する曲か（勝利・敗北は 1 回だけ鳴るスティンガー）。
    var loops: Bool { self == .menu || self == .battle }
}

@MainActor
final class AudioService {
    static let sfxPoolSize = 8
    /// BGM の基準音量（効果音より控えめにする）。
    static let musicGain: Float = 0.55
    static let crossfadeDuration: TimeInterval = 0.8

    private(set) var bgmVolume: Double = 0.7
    private(set) var sfxVolume: Double = 0.8
    private(set) var voiceVolume: Double = 0.8
    /// 再生中（または準備中）の曲。
    private(set) var currentTrack: MusicTrack?
    /// 全 SFX の合成が完了しているか。
    private(set) var sfxReady = false

    private let engine = AVAudioEngine()
    private let sfxMixer = AVAudioMixerNode()
    private let musicMixer = AVAudioMixerNode()
    private var sfxPlayers: [AVAudioPlayerNode] = []
    /// 各プレイヤーが鳴り終わる予定時刻（systemUptime）。
    private var sfxBusyUntil: [TimeInterval] = []
    private var musicPlayers: [AVAudioPlayerNode] = []
    private var activeMusicPlayer = 0
    private let monoFormat = AVAudioFormat(standardFormatWithSampleRate: SFXSynth.sampleRate, channels: 1)
    private let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: MusicComposer.sampleRate, channels: 2)
    private var graphReady = false

    // 以下の辞書は検索専用（列挙しない）
    private var sfxBuffers: [SFX: [AVAudioPCMBuffer]] = [:]
    private var variantCursor: [SFX: Int] = [:]
    private var lastPlayed: [SFX: TimeInterval] = [:]
    private var musicBuffers: [MusicTrack: AVAudioPCMBuffer] = [:]
    private var renderingTracks: Set<MusicTrack> = []

    private var fadeTask: Task<Void, Never>?
    private var interrupted = false
    private var lastStartAttempt: TimeInterval = -10
    private var observers: [NSObjectProtocol] = []

    init() {
        configureSession()
        buildGraph()
        synthesizeSFX()
        registerObservers()
        _ = startEngine()
        prepareMusic(.menu)
    }

    // MARK: - 設定

    func apply(settings: GameSettings) {
        bgmVolume = min(1, max(0, settings.bgmVolume))
        sfxVolume = min(1, max(0, settings.sfxVolume))
        voiceVolume = min(1, max(0, settings.voiceVolume))
        applyVolumes()
    }

    private func applyVolumes() {
        sfxMixer.outputVolume = Float(sfxVolume)
        musicMixer.outputVolume = Float(bgmVolume) * Self.musicGain
    }

    // MARK: - 効果音

    func play(_ sfx: SFX) {
        play(sfx, gain: 1)
    }

    /// gain: 0〜1（戦闘中の距離減衰など）。
    func play(_ sfx: SFX, gain: Double) {
        guard graphReady, sfxVolume > 0.001, gain > 0.001 else { return }
        guard let variants = sfxBuffers[sfx], !variants.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayed[sfx], now - last < Self.minInterval(sfx) { return }
        guard ensureEngineRunning() else { return }
        lastPlayed[sfx] = now
        let cursor = variantCursor[sfx] ?? 0
        variantCursor[sfx] = cursor + 1
        let buffer = variants[cursor % variants.count]
        let index = pickSFXPlayer(now: now)
        let player = sfxPlayers[index]
        var volume = Float(min(1, gain))
        if sfx == .announcement || sfx == .countdown { volume *= Float(voiceVolume) }
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
        sfxBusyUntil[index] = now + Double(buffer.frameLength) / buffer.format.sampleRate
    }

    /// 同じ効果音の最短間隔（大量の同時発生で音が割れないように）。
    private static func minInterval(_ sfx: SFX) -> TimeInterval {
        switch sfx {
        case .hit, .attackMelee, .attackRanged, .gold: return 0.045
        case .uiTap: return 0.03
        default: return 0.06
        }
    }

    /// 空いているプレイヤー。無ければ最も早く鳴り終わるものを横取りする。
    private func pickSFXPlayer(now: TimeInterval) -> Int {
        var best = 0
        for i in sfxBusyUntil.indices {
            if sfxBusyUntil[i] <= now { return i }
            if sfxBusyUntil[i] < sfxBusyUntil[best] { best = i }
        }
        return best
    }

    private func synthesizeSFX() {
        guard let monoFormat else { return }
        for sfx in SFX.allCases {
            var list: [AVAudioPCMBuffer] = []
            for v in 0..<SFXSynth.variantCount(sfx) {
                let samples = SFXSynth.render(sfx, variant: v)
                if let buffer = Self.makeBuffer(format: monoFormat, left: samples, right: nil) { list.append(buffer) }
            }
            sfxBuffers[sfx] = list
        }
        sfxReady = true
    }

    /// テスト・デバッグ用: 合成済みの長さ（秒）。
    func sfxDuration(_ sfx: SFX) -> TimeInterval? {
        guard let b = sfxBuffers[sfx]?.first else { return nil }
        return Double(b.frameLength) / b.format.sampleRate
    }

    // MARK: - BGM

    func playMusic(_ track: MusicTrack) {
        guard track != currentTrack else { return }
        currentTrack = track
        if let buffer = musicBuffers[track] {
            startMusic(buffer, track: track)
        } else {
            prepareMusic(track)
        }
    }

    func stopMusic() {
        currentTrack = nil
        guard graphReady else { return }
        let outgoing = musicPlayers[activeMusicPlayer]
        fade(incoming: nil, outgoing: outgoing, duration: 0.6)
    }

    /// 曲を先にレンダリングしておく（ロード画面などで呼ぶと切替が即座になる）。
    func prepareMusic(_ track: MusicTrack) {
        guard graphReady, musicBuffers[track] == nil, !renderingTracks.contains(track) else { return }
        renderingTracks.insert(track)
        Task.detached(priority: .utility) { [weak self] in
            let rendered = MusicComposer.render(track)
            await self?.didRender(track, rendered)
        }
    }

    private func didRender(_ track: MusicTrack, _ rendered: RenderedMusic) {
        renderingTracks.remove(track)
        guard let stereoFormat,
              let buffer = Self.makeBuffer(format: stereoFormat, left: rendered.left, right: rendered.right) else { return }
        musicBuffers[track] = buffer
        if currentTrack == track {
            startMusic(buffer, track: track)
        } else if track.loops && currentTrack?.loops == true {
            // 別のループ曲を再生中なら、使わないループ曲はメモリから外す
            musicBuffers[track] = nil
        }
    }

    private func startMusic(_ buffer: AVAudioPCMBuffer, track: MusicTrack) {
        guard graphReady else { return }
        // 再生中以外のループ曲はメモリから外す（再生中プレイヤーはバッファを保持している）
        for other in MusicTrack.allCases where other.loops && other != track {
            musicBuffers[other] = nil
        }
        guard ensureEngineRunning() else { return }
        let outgoing = musicPlayers[activeMusicPlayer]
        activeMusicPlayer = 1 - activeMusicPlayer
        let incoming = musicPlayers[activeMusicPlayer]
        incoming.stop()
        incoming.volume = 0
        incoming.scheduleBuffer(buffer, at: nil, options: track.loops ? [.loops] : [], completionHandler: nil)
        incoming.play()
        fade(incoming: incoming, outgoing: outgoing, duration: Self.crossfadeDuration)
    }

    /// 音量のクロスフェード（incoming を 0→1、outgoing を現在値→0 にして停止）。
    private func fade(incoming: AVAudioPlayerNode?, outgoing: AVAudioPlayerNode?, duration: TimeInterval) {
        fadeTask?.cancel()
        let startOut = outgoing?.volume ?? 0
        let startIn = incoming?.volume ?? 0
        let steps = 20
        fadeTask = Task { @MainActor in
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: UInt64(duration / Double(steps) * 1_000_000_000))
                if Task.isCancelled { return }
                let t = Float(i) / Float(steps)
                incoming?.volume = startIn + (1 - startIn) * t
                outgoing?.volume = startOut * (1 - t)
            }
            if outgoing !== incoming { outgoing?.stop() }
        }
    }

    // MARK: - エンジン

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            // セッションを設定できなくてもエンジン側で再試行する
        }
    }

    private func buildGraph() {
        guard let monoFormat, let stereoFormat else { return }
        engine.attach(sfxMixer)
        engine.attach(musicMixer)
        engine.connect(sfxMixer, to: engine.mainMixerNode, format: stereoFormat)
        engine.connect(musicMixer, to: engine.mainMixerNode, format: stereoFormat)
        for _ in 0..<Self.sfxPoolSize {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: sfxMixer, format: monoFormat)
            sfxPlayers.append(p)
            sfxBusyUntil.append(0)
        }
        for _ in 0..<2 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: musicMixer, format: stereoFormat)
            p.volume = 0
            musicPlayers.append(p)
        }
        applyVolumes()
        engine.prepare()
        graphReady = true
    }

    /// エンジンを起動する。失敗しても例外は出さない。
    @discardableResult
    private func startEngine() -> Bool {
        guard graphReady else { return false }
        if engine.isRunning { return true }
        lastStartAttempt = ProcessInfo.processInfo.systemUptime
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    /// 停止していれば再起動を試みる（失敗時は 1 秒間は再試行しない）。
    private func ensureEngineRunning() -> Bool {
        if engine.isRunning { return true }
        guard !interrupted, ProcessInfo.processInfo.systemUptime - lastStartAttempt > 1 else { return false }
        return restartEngineAndMusic()
    }

    /// エンジン停止後（割り込み・構成変更）の復帰。ループ曲は頭から再開する。
    @discardableResult
    private func restartEngineAndMusic() -> Bool {
        guard startEngine() else { return false }
        for i in sfxBusyUntil.indices { sfxBusyUntil[i] = 0 }
        guard let track = currentTrack, track.loops else { return true }
        guard let buffer = musicBuffers[track] else {
            prepareMusic(track)
            return true
        }
        fadeTask?.cancel()
        for p in musicPlayers { p.stop() }
        let player = musicPlayers[activeMusicPlayer]
        player.volume = 1
        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        player.play()
        return true
    }

    private func registerObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                            queue: .main) { [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated { self?.handleInterruption(typeValue: typeValue) }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMediaServicesReset() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleBecameActive() }
        })
    }

    private func handleInterruption(typeValue: UInt?) {
        guard let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            interrupted = true
        case .ended:
            interrupted = false
            try? AVAudioSession.sharedInstance().setActive(true)
            restartEngineAndMusic()
        @unknown default:
            break
        }
    }

    private func handleConfigurationChange() {
        guard !interrupted, !engine.isRunning else { return }
        restartEngineAndMusic()
    }

    private func handleMediaServicesReset() {
        configureSession()
        engine.stop()
        restartEngineAndMusic()
    }

    private func handleBecameActive() {
        interrupted = false
        if !engine.isRunning {
            try? AVAudioSession.sharedInstance().setActive(true)
            restartEngineAndMusic()
        }
    }

    // MARK: - バッファ

    private static func makeBuffer(format: AVAudioFormat, left: [Float], right: [Float]?) -> AVAudioPCMBuffer? {
        guard !left.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(left.count)
        left.withUnsafeBufferPointer { src in
            channels[0].update(from: src.baseAddress!, count: left.count)
        }
        if format.channelCount > 1 {
            let r = (right?.count == left.count) ? right! : left
            r.withUnsafeBufferPointer { src in
                channels[1].update(from: src.baseAddress!, count: left.count)
            }
        }
        return buffer
    }
}
