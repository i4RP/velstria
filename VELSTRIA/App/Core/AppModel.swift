import SwiftUI
import VelstriaCore

// 担当: 統合（契約）

/// 戦闘の起動元の文脈（アプリ内のみ。sim / replay には載せない）。
enum BattleContext: Equatable {
    case normal
    /// ライジングのステージ（終了後にブラケットを進める）。
    case rising(stageIndex: Int)
}

/// 戦闘の起動パラメータ。
struct BattleLaunch: Identifiable, Equatable {
    let id = UUID()
    var config: MatchConfig
    /// リプレイ再生の場合に設定（入力は replay から供給）。
    var replay: ReplayData?
    /// ランク戦などで結果をランクに反映するか。
    var countsForRank: Bool = false
    /// 起動元の文脈（ライジング等）。
    var context: BattleContext = .normal
    /// オンライン対戦: 自分の座席（config.players の添字）。nil ならオフライン（または観戦席）。
    var onlineSeat: Int?
    /// オンライン対戦を観戦席で見る（座席なし。ホストの配信を遅延付きで再生する）。
    var onlineSpectator: Bool = false
    /// リプレイの持ち主の座席（config.players の添字）。nil なら最初の人間の枠。
    var replayOwnerSeat: Int?

    /// 観戦者として見る（操作なし・霧は観戦者の選んだ視点・報酬なし）。
    /// AI 同士の観戦、リプレイ、オンラインの観戦席、人間のいないオフライン構成（全 AI のカスタムなど）。
    var isSpectating: Bool {
        config.mode == .spectate || replay != nil || onlineSpectator || isAllBotsOffline
    }
    /// 人間の枠が 1 つもないオフライン構成。
    var isAllBotsOffline: Bool {
        onlineSeat == nil && !onlineSpectator && !config.players.isEmpty
            && config.players.allSatisfy { $0.controller == .bot }
    }
    var isOnline: Bool { onlineSeat != nil || onlineSpectator }
    /// 自分のチーム（オンラインは座席、オフラインは唯一の人間。観戦者は nil）。
    var localTeam: Team? {
        if isSpectating { return nil }
        if let seat = onlineSeat, config.players.indices.contains(seat) { return config.players[seat].team }
        return config.humanSlot?.team
    }
    /// リプレイの持ち主の座席（リプレイ以外は nil）。
    var ownerSeat: Int? {
        guard replay != nil else { return nil }
        if let s = replayOwnerSeat, config.players.indices.contains(s) { return s }
        return config.players.firstIndex { $0.controller == .human }
    }
}

/// マジックチェスの起動パラメータ。
struct MagicChessLaunch: Identifiable, Equatable {
    let id = UUID()
    var config: MagicChessConfig
}

/// 戦闘の終了結果。
struct BattleOutcome: Equatable {
    var launch: BattleLaunch
    var summary: MatchSummary
    var replay: ReplayData?
    /// 途中離脱（練習場の退出など）。
    var abandoned: Bool
}

/// アプリ全体の状態。`@Environment(AppModel.self)` で参照する。
@Observable
@MainActor
final class AppModel {
    let master = MasterData.shared
    let router = Router()
    let persistence: PersistenceService
    let storeKit: StoreKitService
    let audio: AudioService
    let haptics: HapticsService

    var profile: Profile {
        didSet {
            guard profile != oldValue else { return }
            if profile.settings.language != oldValue.settings.language {
                Loc.current = Loc.resolve(profile.settings.language)
            }
            if profile.settings != oldValue.settings {
                audio.apply(settings: profile.settings)
                haptics.enabled = profile.settings.hapticsEnabled
            }
            persistence.scheduleSave(profile)
        }
    }

    /// 起動中の戦闘（ルートで fullScreenCover 表示）。
    var activeBattle: BattleLaunch?
    /// 起動中のマジックチェス（ルートで fullScreenCover 表示）。
    var activeMagicChess: MagicChessLaunch?
    /// 参加中のオンライン対戦の部屋（ロビー〜戦闘〜リザルトの間保持。退出で nil）。
    var online: OnlineSession?
    /// 直近の戦闘結果と報酬（リザルト画面用）。
    var lastOutcome: BattleOutcome?
    var lastRewardReport: RewardReport?
    /// トースト表示用メッセージ。
    var toast: String?

    init(persistence: PersistenceService = PersistenceService()) {
        self.persistence = persistence
        let loaded = persistence.loadProfile() ?? Profile()
        self.profile = loaded
        self.storeKit = StoreKitService()
        self.audio = AudioService()
        self.haptics = HapticsService()
        Loc.current = Loc.resolve(loaded.settings.language)
        audio.apply(settings: loaded.settings)
        haptics.enabled = loaded.settings.hapticsEnabled
        storeKit.attach(to: self)
    }

    /// 起動時処理（ログインボーナス・デイリー更新・未処理トランザクション）。
    func onLaunch(now: Date = Date()) {
        LiveOpsService.onLaunch(profile: &profile, master: master, now: now)
        Task { await storeKit.start() }
    }

    // MARK: 戦闘

    func startBattle(_ launch: BattleLaunch) {
        router.isMatchFlowPresented = false
        activeBattle = launch
    }

    // MARK: オンライン対戦

    /// 部屋を作る（ホスト）。既に参加中なら先に退出する。
    func hostOnlineRoom(name roomName: String? = nil, port: UInt16? = OnlineProtocol.defaultPort) {
        leaveOnlineRoom()
        let name = profile.displayName.isEmpty ? L("プレイヤー", "Player") : profile.displayName
        let session = OnlineSession.host(peerID: profile.playerID, name: name,
                                         roomName: roomName ?? L("\(name) の部屋", "\(name)'s room"))
        wire(session)
        session.startListening(preferredPort: port)
        online = session
    }

    /// 部屋に入る（クライアント）。
    func joinOnlineRoom(connection: OnlineConnection) {
        leaveOnlineRoom()
        let name = profile.displayName.isEmpty ? L("プレイヤー", "Player") : profile.displayName
        let session = OnlineSession.join(peerID: profile.playerID, name: name, connection: connection)
        wire(session)
        online = session
    }

    private func wire(_ session: OnlineSession) {
        session.onMatchStart = { [weak self] config, seat in
            guard let self, let seat, config.players.indices.contains(seat) else { return }
            if self.activeBattle != nil {
                // 別の戦闘中（練習場など）に開始の合図が来た: 進行中の戦闘は守り、自分の枠は AI に任せる
                session.declineMatch()
                self.showToast(L("オンライン対戦が始まりましたが、戦闘中のため参加できませんでした", "The online match started while you were in another battle"))
                return
            }
            var p = self.profile
            p.lastPickedHeroID = config.players[seat].heroID
            self.profile = p
            self.startBattle(BattleLaunch(config: config, onlineSeat: seat))
        }
        session.onDisconnected = { [weak self] reason in
            self?.showToast(reason)
        }
    }

    func leaveOnlineRoom() {
        online?.leave()
        online = nil
    }

    /// 戦闘終了時に BattleSessionView から呼ばれる。報酬を適用しリザルト用に保持する。
    @discardableResult
    func completeBattle(_ outcome: BattleOutcome, now: Date = Date()) -> RewardReport {
        var p = profile
        let report = RewardService.apply(outcome: outcome, to: &p, master: master, persistence: persistence, now: now)
        profile = p
        lastOutcome = outcome
        lastRewardReport = report
        return report
    }

    func dismissBattle() {
        activeBattle = nil
    }

    // MARK: マジックチェス

    func startMagicChess(_ launch: MagicChessLaunch) {
        router.isMatchFlowPresented = false
        activeMagicChess = launch
    }

    func dismissMagicChess() {
        activeMagicChess = nil
    }

    // MARK: 便利

    func showToast(_ message: String) {
        toast = message
    }

    func owns(heroID: String) -> Bool { profile.ownedHeroIDs.contains(heroID) }
    func owns(cosmeticID: String) -> Bool { profile.ownedCosmeticIDs.contains(cosmeticID) }
}
