import Foundation
import AVFoundation
import UIKit
import VelstriaCore

// 担当: app-services
// AVAudioEngine による効果音・BGM。効果音はすべて録音の音のファイル（App/Resources/Audio。AudioFiles）。合成の効果音は使わない
// （ファイルが無い音は鳴らさない。2026-10-20 ユーザー指示: 合成は保険にも使わない）。
// - 効果音: 初期化時に全 SFX のファイル（揺らぎ _1 … を含む）をバックグラウンドで読む（画面の効果音は小さいので起動時に全部読む）。
//   8 個の AVAudioPlayerNode を使い回して重ねて鳴らす。準備完了前の再生要求は無視する。
// - BGM: ファイルの曲は AVAudioFile から流し読みする（全部をメモリに展開しない。読み終わりで頭から予約し直してループ）。
//   合成の曲は一度だけバックグラウンドでレンダリングしてバッファを保持し、.loops でスケジュールする。
//   曲の切替はクロスフェード。メモリ警告時は再生中以外の曲のバッファを解放する（次回再生時に作り直す）。
// - AVAudioSession は .ambient（消音スイッチに従い、他のアプリの音と混ざる）。
// - 割り込み・エンジン構成変更・フォアグラウンド復帰で再起動し、メディアサービスのリセット時はエンジンを作り直す。
// - エンジンが起動できない環境では何もしない（クラッシュさせない）。

enum SFX: String, CaseIterable {
    case uiTap, uiConfirm, uiBack, uiError, purchase, reward, levelUp
    case attackMelee, attackRanged, hit, crit, skillCast, ultimateCast, heal, shield
    case death, kill, multiKill, towerDestroyed, objective, gold, recall, respawn
    case countdown, victory, defeat, announcement
    /// 塔・Star Core（描画側の StructureFXDirector が画面付近の構造物だけ鳴らす）: 立ち上がりの地鳴り・頂部のロック・
    /// 亀裂・倒壊・着地・結晶の消失。
    case towerRise, towerLock, towerCrack, towerCollapse, towerImpact, crystalFade
    /// 試合の外: タブの切替・マッチ成立・ピックの確定・バン・試合開始の合図。
    case uiTab, matchFound, lockIn, ban, matchStart
}

enum MusicTrack: String, CaseIterable {
    case menu, menuDream, menuAdventure, menuAurora, battle, victory, defeat
    /// ファイルの曲（AudioFiles.music）。ホーム曲の識別子は旧設定との互換用に残すが、再生しない。
    case menuLegend, menuFantasia, menuJourney, lobby, draft, draftTense, loading, result

    var displayName: String {
        switch self {
        case .menu: return "静かな星明かり"
        case .menuDream: return "夢の水辺"
        case .menuAdventure: return "旅立ちの朝"
        case .menuAurora: return "オーロラの庭"
        case .menuLegend: return "伝説の夜明け"
        case .menuFantasia: return "幻想の序曲"
        case .menuJourney: return "宝探しの旅"
        case .battle: return "戦闘"
        case .victory: return "勝利"
        case .defeat: return "敗北"
        case .lobby: return "ロビー"
        case .draft: return "ヒーロー選択"
        case .draftTense: return "ヒーロー選択（残りわずか）"
        case .loading: return "出陣"
        case .result: return "戦いのあと"
        }
    }
    /// ホームとバトルのメインテーマは廃止。旧設定や画面遷移からの要求でも読み込まず、BGM を止める。
    var isSilent: Bool {
        switch self {
        case .menu, .menuDream, .menuAdventure, .menuAurora, .menuLegend, .menuFantasia, .menuJourney, .battle:
            return true
        default:
            return false
        }
    }

    /// ループ再生する曲か（勝利・敗北は 1 回だけ鳴るスティンガー）。
    var loops: Bool { self != .victory && self != .defeat }
}

/// スキルの音の鍵（ファイル skill_<ヒーロー>_<s1|s2|ult>[_r<段>]_<cast|hit>.caf）。
struct SkillSoundKey: Hashable, Sendable {
    /// 鳴らす段（ファイル名の末尾）。
    enum Phase: String, Sendable, CaseIterable {
        case cast
        case hit
        /// 通常攻撃の振り・発射（attackReleased）。
        case attack = "atk"
        /// 通常攻撃の命中（damage(.basicAttack)）。
        case attackHit = "atkhit"
        /// パッシブの発動・スタックの解放。
        case passive
        /// 通常攻撃の会心（damage(.basicAttack) の isCrit。命中の代わりに鳴らす）。
        case crit
        /// キットの強い通常攻撃（三連突き・円撃。SimEvent.empoweredAttack）の振り。その攻撃の通常攻撃の振りの代わりに鳴らす。
        case empowered = "atkx"
        /// 強い通常攻撃の命中（三連突きは 1 撃ごと、円撃は 1 回）。その攻撃の通常攻撃の命中・会心の代わりに鳴らす。
        case empoweredHit = "atkxhit"
    }

    var heroID: String
    var slot: SkillSlot
    var stage: Int = 0
    var phase: Phase = .cast

    init(heroID: String, slot: SkillSlot, stage: Int = 0, hit: Bool = false) {
        self.heroID = heroID
        self.slot = slot
        self.stage = stage
        self.phase = hit ? .hit : .cast
    }

    /// 通常攻撃・パッシブの鍵（スキルの枠は持たない）。
    init(heroID: String, phase: Phase) {
        self.heroID = heroID
        self.slot = .passive
        self.phase = phase
    }

    var hit: Bool { phase == .hit || phase == .attackHit || phase == .crit || phase == .empoweredHit }

    /// ファイル名（揺らぎの番号なし）。揺らぎは fileName_1 … fileName_4（AudioService が全部読んで順に鳴らす）。
    var fileName: String {
        switch phase {
        case .attack, .attackHit, .passive, .crit, .empowered, .empoweredHit:
            return "skill_\(heroID)_\(phase.rawValue)"
        case .cast, .hit:
            let s: String
            switch slot {
            case .skill1: s = "s1"
            case .skill2: s = "s2"
            case .ultimate: s = "ult"
            case .passive: s = "passive"
            }
            return "skill_\(heroID)_\(s)" + (stage > 0 ? "_r\(stage)" : "") + "_\(phase.rawValue)"
        }
    }

    /// ヒーロー固有の音が無い時に読む武器の組の音（通常攻撃・命中・会心だけ。HeroWeaponSounds）。
    var fallbackFileName: String? { WeaponSoundSet.of(heroID: heroID)?.fileName(phase) }

    /// 揺らぎの番号の上限。
    static let maxVariants = 4

    /// そのヒーローの全ての鍵（ファイルがあるかは読む時に見る）。
    static func all(heroID: String) -> [SkillSoundKey] {
        var out: [SkillSoundKey] = []
        for slot in [SkillSlot.skill1, .skill2, .ultimate] {
            out.append(SkillSoundKey(heroID: heroID, slot: slot, hit: true))
            for stage in 0...3 { out.append(SkillSoundKey(heroID: heroID, slot: slot, stage: stage)) }
        }
        for phase in [Phase.attack, .attackHit, .crit, .passive, .empowered, .empoweredHit] {
            out.append(SkillSoundKey(heroID: heroID, phase: phase))
        }
        return out
    }
}

@MainActor
final class AudioService {
    static let sfxPoolSize = 8
    /// BGM の基準音量（効果音より控えめにする）。
    static let musicGain: Float = 0.55
    static let crossfadeDuration: TimeInterval = 0.8

    private(set) var bgmVolume: Double = GameSettings().bgmVolume
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
    /// 画面の効果音の組の標本化周波数（ファイルは読む時にこの形へ変換する）。
    nonisolated static let sfxSampleRate: Double = 44_100
    private let monoFormat = AVAudioFormat(standardFormatWithSampleRate: AudioService.sfxSampleRate, channels: 1)
    private let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: MusicComposer.sampleRate, channels: 2)
    private var graphReady = false

    // 以下の辞書は検索専用（列挙しない）
    private var sfxBuffers: [SFX: [AVAudioPCMBuffer]] = [:]
    private var variantCursor: [SFX: Int] = [:]
    private var lastPlayed: [SFX: TimeInterval] = [:]
    private var musicBuffers: [MusicTrack: AVAudioPCMBuffer] = [:]
    /// 開いたファイルの曲（流し読み）。
    private var musicFiles: [MusicTrack: AVAudioFile] = [:]
    /// 曲を始めるたびに増やす（ファイルのループの予約し直しを、切り替えた後の古い曲で続けないため）。
    private var musicGeneration = 0
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
        loadSFX()
    }

    // MARK: - 設定

    func apply(settings: GameSettings) {
        bgmVolume = min(1, max(0, settings.bgmVolume))
        sfxVolume = min(1, max(0, settings.sfxVolume))
        voiceVolume = min(1, max(0, settings.voiceVolume))
        applyVolumes()
    }

    func setTemporaryMute(_ muted: Bool) {
        guard muted != isTemporarilyMuted else { return }
        isTemporarilyMuted = muted
        applyVolumes()
    }

    private func applyVolumes() {
        let gate: Float = isTemporarilyMuted ? 0 : 1
        // 奥義の下げ（duckLevel）: BGM は duckMusic まで、画面の効果音は duckSFX の割合で下げる
        let sfxDuck = 1 - (1 - duckLevel) * (1 - Self.duckSFX) / (1 - Self.duckMusic)
        sfxMixer.outputVolume = Float(sfxVolume) * gate * sfxDuck
        musicMixer.outputVolume = Float(bgmVolume) * Self.musicGain * gate * duckLevel
        skillMixer.outputVolume = Float(sfxVolume) * gate
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

    /// 全 SFX のファイルをバックグラウンドで読む（起動処理をメインスレッドで待たせない）。ファイルが無い音は鳴らさない。
    private func loadSFX() {
        Task.detached(priority: .userInitiated) { [weak self] in
            var rendered: [(SFX, [[Float]])] = []
            for sfx in SFX.allCases {
                let variants = AudioFiles.sfxNames(sfx).compactMap { name -> [Float]? in
                    guard let url = AudioFiles.sfxURL(name) else { return nil }
                    return AudioFiles.readMono(url, sampleRate: AudioService.sfxSampleRate)
                }
                if !variants.isEmpty { rendered.append((sfx, variants)) }
            }
            await self?.didLoadSFX(rendered)
        }
    }

    private func didLoadSFX(_ rendered: [(SFX, [[Float]])]) {
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

    // MARK: - スキルの音（H025〜H034。試合に出るヒーローの分だけ、試合の始めに裏で読む）
    //
    // 画面の効果音（8 声）とは別の 24 声のプール（48 kHz モノラル → 左右の定位）。同時に鳴らせる数が足りない時は、
    // 最も早く鳴り終わる声を横取りする。奥義の時は他の音（BGM・画面の効果音・鳴っているスキルの音）を少し下げる（duck）。

    static let skillPoolSize = 24
    nonisolated static let skillSampleRate: Double = 48_000
    /// 同じスキルの命中の音の最短間隔（多段・範囲の命中で重ねすぎない）。
    static let skillHitInterval: TimeInterval = 0.1
    /// 奥義の時に下げる量（倍率）。BGM・画面の効果音・鳴っている他のスキルの音。
    static let duckMusic: Float = 0.5
    static let duckSFX: Float = 0.6
    static let duckOtherSkills: Float = 0.65

    private var skillBuffers: [SkillSoundKey: [AVAudioPCMBuffer]] = [:]
    private var skillCursor: [SkillSoundKey: Int] = [:]
    private var skillHeroes: Set<String> = []
    private var lastSkillHit: [SkillSoundKey: TimeInterval] = [:]
    private var skillMixer = AVAudioMixerNode()
    private var skillPlayers: [AVAudioPlayerNode] = []
    private var skillBusyUntil: [TimeInterval] = []
    private let skillFormat = AVAudioFormat(standardFormatWithSampleRate: AudioService.skillSampleRate, channels: 1)
    /// 奥義の下げ（1 = 下げない）。applyVolumes が BGM と画面の効果音に掛ける。
    private var duckLevel: Float = 1
    private var duckTask: Task<Void, Never>?

    /// 試合の始め（BattleAudioDirector.start）に呼ぶ。試合に出るヒーローのスキルの音を裏で読み、出ないヒーローの分は捨てる
    /// （プレイ中にファイルを読まない。読み終わる前に撃ったスキルは汎用の発動の音で鳴る）。揺らぎ（_1 … _4）も全部読む。
    func preloadSkillSounds(heroIDs: [String]) {
        let want = Set(heroIDs)
        skillBuffers = skillBuffers.filter { want.contains($0.key.heroID) }
        let missing = want.subtracting(skillHeroes)
        skillHeroes = want
        guard !missing.isEmpty else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            var loaded: [(SkillSoundKey, [[Float]])] = []
            for id in missing.sorted() {
                for key in SkillSoundKey.all(heroID: id) {
                    // ヒーロー固有の音（揺らぎ込み）。無ければ武器の組の音（通常攻撃・命中・会心）
                    var variants = Self.readVariants(key.fileName)
                    if variants.isEmpty, let fallback = key.fallbackFileName { variants = Self.readVariants(fallback) }
                    if !variants.isEmpty { loaded.append((key, variants)) }
                }
            }
            await self?.didLoadSkills(loaded)
        }
    }

    /// 名前のファイルと揺らぎ（名前_1 … 名前_maxVariants）を 48 kHz モノラルで読む。
    nonisolated static func readVariants(_ name: String) -> [[Float]] {
        ([name] + (1...SkillSoundKey.maxVariants).map { "\(name)_\($0)" }).compactMap { n in
            AudioFiles.sfxURL(n).flatMap { AudioFiles.readMono($0, sampleRate: AudioService.skillSampleRate) }
        }
    }

    private func didLoadSkills(_ loaded: [(SkillSoundKey, [[Float]])]) {
        guard let skillFormat else { return }
        for (key, variants) in loaded where skillHeroes.contains(key.heroID) {
            skillBuffers[key] = variants.compactMap { Self.makeBuffer(format: skillFormat, left: $0, right: nil) }
        }
    }

    /// 試合の終わり（BattleAudioDirector.stop）に呼ぶ。
    func releaseSkillSounds() {
        skillBuffers.removeAll()
        skillCursor.removeAll()
        skillHeroes.removeAll()
        lastSkillHit.removeAll()
    }

    /// 読み込んだスキルの音か（テスト用）。
    func hasSkillSound(_ key: SkillSoundKey) -> Bool { !(skillBuffers[key]?.isEmpty ?? true) }

    /// 読み込んだ揺らぎの数（テスト用）。
    func skillVariantCount(_ key: SkillSoundKey) -> Int { skillBuffers[key]?.count ?? 0 }

    /// スキルの音を鳴らす。そのスキルの音が無ければ false（呼び出し側が汎用の音で代える）。
    /// pan: 左右（-1 = 左、1 = 右。画面の上の位置から BattleAudioDirector が決める）。
    /// 音量 0・間隔の内で鳴らさなかった時も、音があれば true（汎用の音を重ねない）。揺らぎは順に鳴らす。
    @discardableResult
    func playSkill(_ key: SkillSoundKey, gain: Double, pan: Float = 0) -> Bool {
        guard let variants = skillBuffers[key], !variants.isEmpty else { return false }
        guard graphReady, sfxVolume > 0.001, gain > 0.001, !skillPlayers.isEmpty else { return true }
        let now = ProcessInfo.processInfo.systemUptime
        if key.hit {
            if let last = lastSkillHit[key], now - last < Self.skillHitInterval { return true }
            lastSkillHit[key] = now
        }
        guard ensureEngineRunning() else { return true }
        let cursor = skillCursor[key] ?? 0
        skillCursor[key] = cursor + 1
        let buffer = variants[cursor % variants.count]
        let index = pickSkillPlayer(now: now)
        let player = skillPlayers[index]
        player.volume = Float(min(1, gain))
        player.pan = max(-1, min(1, pan))
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
        skillBusyUntil[index] = now + Double(buffer.frameLength) / buffer.format.sampleRate
        return true
    }

    private func pickSkillPlayer(now: TimeInterval) -> Int {
        var best = 0
        for i in skillBusyUntil.indices {
            if skillBusyUntil[i] <= now { return i }
            if skillBusyUntil[i] < skillBusyUntil[best] { best = i }
        }
        return best
    }

    /// 奥義の時: BGM・画面の効果音・鳴っている他のスキルの音を seconds 秒だけ下げて、なだらかに戻す。
    /// 呼んだ後に鳴らす音（奥義そのもの）は下げない。
    func duckForUltimate(seconds: Double = 1.4) {
        let now = ProcessInfo.processInfo.systemUptime
        for i in skillPlayers.indices where skillBusyUntil[i] > now {
            skillPlayers[i].volume *= Self.duckOtherSkills
        }
        duckTask?.cancel()
        duckLevel = 1
        applyVolumes()
        duckTask = Task { @MainActor in
            // 0.06 秒で下げ、seconds 秒保ち、0.5 秒で戻す
            for i in 1...6 {
                try? await Task.sleep(nanoseconds: 10_000_000)
                if Task.isCancelled { return }
                self.duckLevel = 1 - (1 - Self.duckMusic) * Float(i) / 6
                self.applyVolumes()
            }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            for i in 1...20 {
                try? await Task.sleep(nanoseconds: 25_000_000)
                if Task.isCancelled { return }
                self.duckLevel = Self.duckMusic + (1 - Self.duckMusic) * Float(i) / 20
                self.applyVolumes()
            }
        }
    }

    /// 下げている最中か（テスト用）。
    var isDucking: Bool { duckLevel < 0.999 }

    // MARK: - BGM

    /// 曲を再生する。同じループ曲の再指定は無視し、スティンガー（勝利・敗北）は再指定で頭から鳴らし直す。
    func playMusic(_ track: MusicTrack) {
        guard !track.isSilent else {
            stopMusic(immediately: true)
            return
        }
        guard track != currentTrack || !track.loops else { return }
        currentTrack = track
        if let file = musicFile(track) {
            startMusic(file: file, track: track)
        } else if let buffer = musicBuffers[track] {
            startMusic(buffer, track: track)
        } else {
            prepareMusic(track)
        }
    }

    func stopMusic(immediately: Bool = false) {
        currentTrack = nil
        musicGeneration += 1
        if immediately {
            fadeTask?.cancel()
            // クロスフェード中の旧曲も止め、ホーム・バトルへ持ち越さない。
            for player in musicPlayers {
                player.stop()
                player.volume = 0
            }
            return
        }
        guard graphReady, musicPlayers.indices.contains(activeMusicPlayer) else { return }
        let outgoing = musicPlayers[activeMusicPlayer]
        fade(incoming: nil, outgoing: outgoing, duration: 0.6)
    }

    /// 曲を先にレンダリングしておく（ロード画面などで呼ぶと切替が即座になる）。
    func prepareMusic(_ track: MusicTrack) {
        guard !track.isSilent else { return }
        // ファイルの曲は開くだけ（流し読みなので先に読むものは無い）
        if musicFile(track) != nil { return }
        guard musicBuffers[track] == nil, !renderingTracks.contains(track) else { return }
        renderingTracks.insert(track)
        Task.detached(priority: .utility) { [weak self] in
            let rendered = MusicComposer.render(track)
            await self?.didRender(track, rendered)
        }
    }

    /// レンダリング済みの曲か（テスト・デバッグ用）。
    func isMusicPrepared(_ track: MusicTrack) -> Bool {
        !track.isSilent && (musicBuffers[track] != nil || musicFile(track) != nil)
    }

    /// ファイルの曲（開けて、BGM の形式 = 44.1 kHz ステレオの時だけ。違えば合成で鳴らす）。
    private func musicFile(_ track: MusicTrack) -> AVAudioFile? {
        guard !track.isSilent else { return nil }
        if let f = musicFiles[track] { return f }
        guard let name = AudioFiles.music(track), let url = AudioFiles.musicURL(name),
              let file = try? AVAudioFile(forReading: url), let stereoFormat,
              file.processingFormat.channelCount == stereoFormat.channelCount,
              file.processingFormat.sampleRate == stereoFormat.sampleRate else { return nil }
        musicFiles[track] = file
        return file
    }

    private func startMusic(file: AVAudioFile, track: MusicTrack) {
        guard graphReady, ensureEngineRunning() else { return }
        let outgoing = musicPlayers[activeMusicPlayer]
        activeMusicPlayer = 1 - activeMusicPlayer
        let incoming = musicPlayers[activeMusicPlayer]
        incoming.stop()
        incoming.volume = 0
        musicGeneration += 1
        scheduleFile(file, on: incoming, loops: track.loops, generation: musicGeneration)
        incoming.play()
        fade(incoming: incoming, outgoing: outgoing, duration: Self.crossfadeDuration)
    }

    /// ファイルを予約する。ループの曲は読み終わったら（再生の終わりより前に）頭からもう一度予約する。
    /// 曲を切り替えた・止めた後の古い予約は generation で見分けて続けない。
    private func scheduleFile(_ file: AVAudioFile, on player: AVAudioPlayerNode, loops: Bool, generation: Int) {
        player.scheduleFile(file, at: nil, completionCallbackType: .dataConsumed) { [weak self] _ in
            guard loops else { return }
            Task { @MainActor in
                guard let self, self.musicGeneration == generation else { return }
                self.scheduleFile(file, on: player, loops: true, generation: generation)
            }
        }
    }

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
        musicGeneration += 1
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
        engine.attach(skillMixer)
        engine.connect(sfxMixer, to: engine.mainMixerNode, format: stereoFormat)
        engine.connect(musicMixer, to: engine.mainMixerNode, format: stereoFormat)
        engine.connect(skillMixer, to: engine.mainMixerNode, format: stereoFormat)
        skillPlayers = []
        skillBusyUntil = []
        if let skillFormat {
            for _ in 0..<Self.skillPoolSize {
                let p = AVAudioPlayerNode()
                engine.attach(p)
                engine.connect(p, to: skillMixer, format: skillFormat)
                skillPlayers.append(p)
                skillBusyUntil.append(0)
            }
        }
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
        skillMixer = AVAudioMixerNode()
        buildGraph()
    }

    /// エンジンを起動する。失敗しても例外は出さない。
    @discardableResult
    private func startEngine() -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-stageSilent") { return false }
        #endif
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
        for p in skillPlayers { p.stop() }
        for i in skillBusyUntil.indices { skillBusyUntil[i] = 0 }
        guard let track = currentTrack, track.loops else { return true }
        if let file = musicFile(track) {
            fadeTask?.cancel()
            for p in musicPlayers { p.stop() }
            let player = musicPlayers[activeMusicPlayer]
            player.volume = 1
            musicGeneration += 1
            scheduleFile(file, on: player, loops: true, generation: musicGeneration)
            player.play()
            return true
        }
        guard let buffer = musicBuffers[track] else {
            prepareMusic(track)
            return true
        }
        fadeTask?.cancel()
        for p in musicPlayers { p.stop() }
        let player = musicPlayers[activeMusicPlayer]
        player.volume = 1
        musicGeneration += 1
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
