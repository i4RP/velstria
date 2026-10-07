import Foundation
import AVFoundation
import UIKit

// 担当: app-services
// AVAudioEngine による手続き生成の効果音・BGM（音源ファイルなし）。
// - 効果音: 初期化時に全 SFX の PCM をバックグラウンドで合成（AudioLibrary.swift）し、起動を妨げない。
//   8 個の AVAudioPlayerNode を使い回して重ねて鳴らす。合成完了前の再生要求は無視する。
// - BGM: 曲ごとに一度だけバックグラウンドでレンダリングしてバッファを保持し、.loops でスケジュールする。
//   曲の切替はクロスフェード。メモリ警告時は再生中以外の曲のバッファを解放する（次回再生時に作り直す）。
// - AVAudioSession は .ambient（消音スイッチに従い、他のアプリの音と混ざる）。
// - 割り込み・エンジン構成変更・フォアグラウンド復帰で再起動し、メディアサービスのリセット時はエンジンを作り直す。
// - エンジンが起動できない環境では何もしない（クラッシュさせない）。

enum SFX: String, CaseIterable {
    case uiTap, uiConfirm, uiBack, uiError, purchase, reward, levelUp
    case attackMelee, attackRanged, hit, crit, skillCast, ultimateCast, heal, shield
    case death, kill, multiKill, towerDestroyed, objective, gold, recall, respawn
    case countdown, victory, defeat, announcement
}

enum MusicTrack: String, CaseIterable {
    case menu, menuDream, menuAdventure, menuAurora, battle, victory, defeat

    static var selectableMenuTracks: [MusicTrack] { [.menu, .menuDream, .menuAdventure, .menuAurora] }
    var displayName: String {
        switch self {
        case .menu: return "静かな星明かり"
        case .menuDream: return "夢の水辺"
        case .menuAdventure: return "旅立ちの朝"
        case .menuAurora: return "オーロラの庭"
        case .battle: return "戦闘"
        case .victory: return "勝利"
        case .defeat: return "敗北"
        }
    }
    var isMenuTrack: Bool { Self.selectableMenuTracks.contains(self) }

    /// ループ再生する曲か（勝利・敗北は 1 回だけ鳴るスティンガー）。
    var loops: Bool { isMenuTrack || self == .battle }
}

@MainActor
final class AudioService {
    static let sfxPoolSize = 8
    /// BGM の基準音量（効果音より控えめにする）。
    static let musicGain: Float = 0.55
    static let crossfadeDuration: TimeInterval = 0.8

    private(set) var bgmVolume: Double = GameSettings().bgmVolume
    private var selectedMenuTrack: MusicTrack = .menu
    private(set) var sfxVolume: Double = GameSettings().sfxVolume
    private(set) var voiceVolume: Double = 0.8
    /// 再生中（または準備中）の曲。
    private(set) var currentTrack: MusicTrack?
    /// 全 SFX の合成が完了しているか。
    private(set) var sfxReady = false
    /// 戦闘 HUD の消音ボタン（設定は変えずに全体を一時的に無音にする）。
    private(set) var isTemporarilyMuted = false

    private var engine = AVAudioEngine()
    private var sfxMixer = AVAudioMixerNode()
    private var musicMixer = AVAudioMixerNode()
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
    private var sfxWaiters: [CheckedContinuation<Void, Never>] = []

    private var fadeTask: Task<Void, Never>?
    private var interrupted = false
    private var lastStartAttempt: TimeInterval = -10
    private var observers: [NSObjectProtocol] = []

    init() {
        configureSession()
        buildGraph()
        registerObservers()
        _ = startEngine()
        synthesizeSFX()
        prepareMusic(.menu)
    }

    // MARK: - 設定

    func apply(settings: GameSettings) {
        bgmVolume = min(1, max(0, settings.bgmVolume))
        selectedMenuTrack = MusicTrack(rawValue: settings.bgmTrack).flatMap { $0.isMenuTrack ? $0 : nil } ?? .menu
        sfxVolume = min(1, max(0, settings.sfxVolume))
        voiceVolume = min(1, max(0, settings.voiceVolume))
        applyVolumes()
        if currentTrack?.isMenuTrack == true, currentTrack != selectedMenuTrack { playMusic(selectedMenuTrack) }
    }

    func setTemporaryMute(_ muted: Bool) {
        guard muted != isTemporarilyMuted else { return }
        isTemporarilyMuted = muted
        applyVolumes()
    }

    private func applyVolumes() {
        let gate: Float = isTemporarilyMuted ? 0 : 1
        sfxMixer.outputVolume = Float(sfxVolume) * gate
        musicMixer.outputVolume = Float(bgmVolume) * Self.musicGain * gate
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

    /// 全 SFX をバックグラウンドで合成する（起動処理をメインスレッドで待たせない）。
    private func synthesizeSFX() {
        Task.detached(priority: .userInitiated) { [weak self] in
            var rendered: [(SFX, [[Float]])] = []
            for sfx in SFX.allCases {
                rendered.append((sfx, (0..<SFXSynth.variantCount(sfx)).map { SFXSynth.render(sfx, variant: $0) }))
            }
            await self?.didSynthesize(rendered)
        }
    }

    private func didSynthesize(_ rendered: [(SFX, [[Float]])]) {
        if let monoFormat {
            for (sfx, variants) in rendered {
                sfxBuffers[sfx] = variants.compactMap { Self.makeBuffer(format: monoFormat, left: $0, right: nil) }
            }
        }
        sfxReady = true
        let waiters = sfxWaiters
        sfxWaiters = []
        for w in waiters { w.resume() }
    }

    /// 効果音の合成完了を待つ（ロード画面・テスト用。完了済みなら即座に戻る）。
    func waitUntilSFXReady() async {
        guard !sfxReady else { return }
        await withCheckedContinuation { sfxWaiters.append($0) }
    }

    /// テスト・デバッグ用: 合成済みの長さ（秒）。
    func sfxDuration(_ sfx: SFX) -> TimeInterval? {
        guard let b = sfxBuffers[sfx]?.first else { return nil }
        return Double(b.frameLength) / b.format.sampleRate
    }

    // MARK: - BGM

    /// 曲を再生する。同じループ曲の再指定は無視し、スティンガー（勝利・敗北）は再指定で頭から鳴らし直す。
    func playMusic(_ track: MusicTrack) {
        let track = track == .menu ? selectedMenuTrack : track
        guard track != currentTrack || !track.loops else { return }
        currentTrack = track
        if let buffer = musicBuffers[track] {
            startMusic(buffer, track: track)
        } else {
            prepareMusic(track)
        }
    }

    func stopMusic() {
        currentTrack = nil
        guard graphReady, musicPlayers.indices.contains(activeMusicPlayer) else { return }
        let outgoing = musicPlayers[activeMusicPlayer]
        fade(incoming: nil, outgoing: outgoing, duration: 0.6)
    }

    /// 曲を先にレンダリングしておく（ロード画面などで呼ぶと切替が即座になる）。
    func prepareMusic(_ track: MusicTrack) {
        guard musicBuffers[track] == nil, !renderingTracks.contains(track) else { return }
        renderingTracks.insert(track)
        Task.detached(priority: .utility) { [weak self] in
            let rendered = MusicComposer.render(track)
            await self?.didRender(track, rendered)
        }
    }

    /// レンダリング済みの曲か（テスト・デバッグ用）。
    func isMusicPrepared(_ track: MusicTrack) -> Bool { musicBuffers[track] != nil }

    private func didRender(_ track: MusicTrack, _ rendered: RenderedMusic) {
        renderingTracks.remove(track)
        guard let stereoFormat,
              let buffer = Self.makeBuffer(format: stereoFormat, left: rendered.left, right: rendered.right) else { return }
        musicBuffers[track] = buffer
        if currentTrack == track { startMusic(buffer, track: track) }
    }

    private func startMusic(_ buffer: AVAudioPCMBuffer, track: MusicTrack) {
        guard graphReady, ensureEngineRunning() else { return }
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

    /// メモリ警告: 再生中以外の曲のバッファを解放する（効果音は小さいので保持）。
    private func releaseIdleMusic() {
        for track in MusicTrack.allCases where track != currentTrack {
            musicBuffers[track] = nil
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
        sfxPlayers = []
        sfxBusyUntil = []
        for _ in 0..<Self.sfxPoolSize {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: sfxMixer, format: monoFormat)
            sfxPlayers.append(p)
            sfxBusyUntil.append(0)
        }
        musicPlayers = []
        for _ in 0..<2 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: musicMixer, format: stereoFormat)
            p.volume = 0
            musicPlayers.append(p)
        }
        activeMusicPlayer = 0
        applyVolumes()
        engine.prepare()
        graphReady = true
    }

    /// エンジンとノードを作り直す（メディアサービスのリセット後は既存のノードが使えないため）。
    private func rebuildEngine() {
        fadeTask?.cancel()
        engine.stop()
        graphReady = false
        engine = AVAudioEngine()
        sfxMixer = AVAudioMixerNode()
        musicMixer = AVAudioMixerNode()
        buildGraph()
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
        // エンジン停止後もプレイヤーの isPlaying が true のまま残ることがあり、その場合 play() が呼ばれず無音になる。
        // 一度止めて状態を揃え、次の再生要求で play() し直す（溜まった古い予約も破棄される）。
        for p in sfxPlayers { p.stop() }
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
        // エンジンは作り直すことがあるため object を指定せず、自分のエンジンの状態だけを見る
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil,
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
        observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseIdleMusic() }
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
        rebuildEngine()
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
