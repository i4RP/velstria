import Foundation
import Observation
import VelstriaCore

// 担当: 統合（契約）。battle-renderer / battle-hud は読み取り専用で利用する。
//
// 役割:
// - Simulation を所有し、描画フレームから固定 tick（30Hz）で進める（アキュムレータ方式）
// - HUD の入力を HeroCommand に変換してキューし、次 tick で適用（sequence 付き）
// - SimEvent を購読者（描画・HUD・音）へ配信
// - カメラ・照準表示の共有状態
//
// 座標系: 人間は常に Blue（左下）。カメラは回転しないので、画面の右 = sim +x、画面の上 = sim +y。
// よってドラッグベクトル (dx, dy)（UIKit 座標）は sim 方向 Vec2(dx, -dy) に対応する。
// オンライン対戦（launch.onlineSeat != nil）では自分のヒーローは座席のもの（Red 側のこともある。カメラは回転しない）。
//
// オンライン対戦（リッスンサーバー、App/Online/）:
// - ホスト: 自分の入力 + クライアントから届いた入力で sim を進め、tick 毎の入力列を配信する（権威）。
// - クライアント: 入力はホストへ送るだけで、配信された tick の入力が届いた分だけ sim を進める（遅れて再生）。
//   届くまでは待つ（補間係数 1 で止まる）。溜まったら早送りで追いつく。一時停止は世界を止めない。

/// オンライン対戦の進行状態（HUD の待機表示用）。
enum OnlineBattleStatus: Equatable {
    case none
    /// ホスト: 他の参加者の読み込みを待っている。
    case waitingForPlayers
    /// クライアント: ホストからの配信を待っている（秒）。
    case waitingForHost(Double)
    case disconnected
}

/// 照準表示（HUD がドラッグ中に設定し、描画が 3D で表示する）。
struct AimIndicator: Equatable {
    enum Kind: Equatable {
        case skill(SkillSlot)
        case spell(Int)
    }
    var kind: Kind
    var targeting: SkillTargeting
    /// 発動点（通常は自ヒーロー位置）。
    var origin: Vec2
    /// 照準先（方向型なら origin + dir × range）。
    var target: Vec2
    /// キャンセル領域にいる。
    var isCancelling: Bool
}

enum CameraMode: Equatable {
    /// 自ヒーロー追従（死亡中も死亡地点付近）。
    case followHero
    /// 任意ユニット追従（観戦）。
    case followUnit(EntityID)
    /// ミニマップ操作などで固定位置を表示。
    case free(Vec2)
}

@Observable
@MainActor
final class BattleController {
    let launch: BattleLaunch
    @ObservationIgnored let sim: Simulation
    @ObservationIgnored let recorder: ReplayRecorder?
    /// オンライン対戦の窓口（nil ならオフライン）。
    @ObservationIgnored let online: OnlineBattleLink?
    /// オンライン対戦で自分が操作するヒーロー（座席から決まる）。オフラインは nil（sim.state.humanHeroID を使う）。
    @ObservationIgnored private(set) var localHeroID: EntityID?
    /// オンライン対戦の進行状態（hudTick と同じ頻度で更新）。
    private(set) var onlineStatus: OnlineBattleStatus = .none
    @ObservationIgnored private var onlineStall: Double = 0
    /// リプレイ再生時: tick → その tick の入力。
    @ObservationIgnored private var replayFrames: [Int: [HeroCommand]] = [:]

    // MARK: HUD が購読する値（低頻度更新）

    /// 15Hz で増える。HUD はこれを参照して SimState を読み直す。
    private(set) var hudTick = 0
    /// Camera presentation has its own clock so the map outline also moves while the sim is paused.
    private(set) var cameraViewportTick = 0
    private(set) var isEnded = false
    /// 描画側の準備（地面テクスチャ・ウォームアップが済み、読み込み幕が上がる）が完了した。
    /// これが立つまで予備駆動（BattleLoopFallback）は sim を進めず、HUD も表示しない。
    private(set) var isPresentationReady = false
    /// 一時停止。オンライン対戦では世界を止められない（他の参加者がいる）ので常に false を返す（メニューは HUD が開くだけ）。
    var isPaused: Bool {
        get { isOnline ? false : pauseRequested }
        set { pauseRequested = newValue }
    }
    private var pauseRequested = false
    /// 観戦・リプレイの再生速度（1, 2, 4）。
    var speed: Double = 1
    var cameraMode: CameraMode = .followHero
    /// 設定のカメラ倍率（0.8〜1.3）。
    var cameraZoom: Double = 1.0

    // MARK: 描画が毎フレーム読む値（非監視）

    @ObservationIgnored var aim: AimIndicator?
    /// 補間係数（前 tick → 現 tick）。
    @ObservationIgnored private(set) var interpolationAlpha: Double = 0
    @ObservationIgnored private(set) var renderedCameraViewport: [Vec2] = []
    @ObservationIgnored private var cameraViewportAccumulator: Double = 0
    @ObservationIgnored private var cameraViewportDirty = false

    @ObservationIgnored private var accumulator: Double = 0
    @ObservationIgnored private var hudAccumulator: Double = 0
    @ObservationIgnored private var pending: [HeroCommand] = []
    @ObservationIgnored private var sequence: UInt32 = 0
    @ObservationIgnored private var subscribers: [UUID: ([SimEvent]) -> Void] = [:]
    @ObservationIgnored private var subscriberOrder: [UUID] = []

    /// 1 描画フレームで進める sim の最大 step 数（早送り時）。
    static let maxStepsPerFrame = 12
    /// 通常速度（speed ≤ 1）での上限。遅れたフレームの後に 1 フレームで大量の step を回すと、その分の演出が
    /// 次のフレームに集中してさらに遅れる（死のスパイラル）。上限を超えた遅れは追いかけずに捨てる（時間の伸び。sim の結果は変わらない）。
    static let maxCatchUpSteps = 4
    static let hudInterval = 1.0 / 15.0

    /// 速度に応じた 1 フレームの step 上限。
    static func maxSteps(speed: Double) -> Int { speed > 1 ? maxStepsPerFrame : maxCatchUpSteps }

    /// オンライン対戦の早送り判定: これより多く配信が溜まっていたら 1 フレームで多めに進める。
    static let onlineCatchUpThreshold = 6
    /// オンライン対戦のジッタ吸収: これより多く溜まっていれば時計を待たずに進める（この tick 数だけ遅れて再生する）。
    static let onlineJitterBuffer = 2

    init(launch: BattleLaunch, online: OnlineBattleLink? = nil) {
        self.launch = launch
        self.online = launch.onlineSeat != nil ? online : nil
        self.sim = Simulation(config: launch.config, map: MapDefinition.map(for: launch.config.mode))
        if let seat = launch.onlineSeat {
            let heroes = sim.state.heroIndices
            if heroes.indices.contains(seat) { localHeroID = sim.state.units[heroes[seat]].id }
        }
        if let replay = launch.replay {
            recorder = nil
            for f in replay.frames { replayFrames[f.tick, default: []].append(contentsOf: f.commands) }
        } else if launch.config.mode == .spectate {
            recorder = nil
        } else {
            let r = ReplayRecorder(config: launch.config)
            recorder = r
            sim.recorder = r
        }
        if launch.isSpectating {
            if let first = sim.state.heroIndices.first { cameraMode = .followUnit(sim.state.units[first].id) }
        }
    }

    var state: SimState { sim.state }
    var ctx: SimContext { sim.ctx }
    var isReplay: Bool { launch.replay != nil }
    var isSpectating: Bool { launch.isSpectating }
    var isOnline: Bool { online != nil }
    var isOnlineHost: Bool { online?.isHost ?? false }
    var isOnlineClient: Bool { online.map { !$0.isHost } ?? false }
    /// 自分が操作するヒーロー（オンラインは座席のヒーロー、オフラインは唯一の人間）。観戦中は nil。
    var humanHeroID: EntityID? { isSpectating ? nil : (localHeroID ?? sim.state.humanHeroID) }

    /// 人間ヒーローの units 添字（観戦中は nil）。
    var humanIndex: Int? { humanHeroID.flatMap { sim.state.index(of: $0) } }

    /// 自分のチーム（観戦中は nil）。
    var localTeam: Team? {
        guard !isSpectating else { return nil }
        return humanHeroID.flatMap { sim.state.unit($0)?.team } ?? .blue
    }

    /// 視点チーム（観戦は Blue 視点ではなく全体可視にするため nil）。
    var viewerTeam: Team? { localTeam }

    /// 座席番号 → ヒーローのエンティティ ID（オンライン対戦の入力検証用）。
    func heroID(forSeat seat: Int) -> EntityID? {
        let heroes = sim.state.heroIndices
        guard heroes.indices.contains(seat) else { return nil }
        return sim.state.units[heroes[seat]].id
    }

    // MARK: 購読

    /// イベント購読。戻り値のトークンで解除。
    @discardableResult
    func subscribe(_ handler: @escaping ([SimEvent]) -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = handler
        subscriberOrder.append(id)
        return id
    }

    func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
        subscriberOrder.removeAll { $0 == id }
    }

    // MARK: ループ

    func updateCameraViewport(_ polygon: [Vec2], dt: Double) {
        let first = renderedCameraViewport.isEmpty
        if renderedCameraViewport != polygon {
            renderedCameraViewport = polygon
            cameraViewportDirty = true
        }
        cameraViewportAccumulator += max(0, dt)
        guard cameraViewportDirty, first || cameraViewportAccumulator >= 1.0 / 30.0 else { return }
        cameraViewportAccumulator = 0
        cameraViewportDirty = false
        cameraViewportTick &+= 1
    }

    /// 描画側の準備完了を通知する（BattleRenderer が読み込み幕を上げる時。予備駆動のタイムアウト時）。
    func markPresentationReady() {
        guard !isPresentationReady else { return }
        isPresentationReady = true
    }

    /// 描画フレーム毎に呼ぶ（dt = 実時間の経過秒）。
    func frame(dt: Double) {
        guard !isEnded else { return }
        if let online {
            // オンライン対戦は一時停止しても世界が止まらない（isPaused は常に false。メニューを開いているだけ）
            if online.isHost { advanceOnlineHost(dt: dt, online: online) } else { advanceOnlineClient(dt: dt, online: online) }
        } else {
            guard !isPaused else { return }
            advanceOffline(dt: dt)
        }

        hudAccumulator += dt
        if hudAccumulator >= Self.hudInterval || isEnded {
            hudAccumulator = 0
            hudTick &+= 1
        }
    }

    private func advanceOffline(dt: Double) {
        accumulator += min(dt, 0.25) * speed
        let maxSteps = Self.maxSteps(speed: speed)
        var steps = 0
        while accumulator >= Balance.dt && steps < maxSteps {
            stepOnce()
            accumulator -= Balance.dt
            steps += 1
            if sim.isEnded {
                isEnded = true
                accumulator = 0
                break
            }
        }
        if steps == maxSteps { accumulator = min(accumulator, Balance.dt) }
        interpolationAlpha = min(1, accumulator / Balance.dt)
    }

    /// ホスト: 全員の読み込みが済むまで待ち、以後は通常速度で進めて tick 毎の入力を配信する。
    private func advanceOnlineHost(dt: Double, online: OnlineBattleLink) {
        guard online.canBegin else {
            accumulator = 0
            interpolationAlpha = 1
            setOnlineStatus(.waitingForPlayers)
            return
        }
        setOnlineStatus(.none)
        accumulator += min(dt, 0.25)
        var steps = 0
        while accumulator >= Balance.dt && steps < Self.maxCatchUpSteps {
            stepOnce()
            accumulator -= Balance.dt
            steps += 1
            if sim.isEnded {
                isEnded = true
                accumulator = 0
                break
            }
        }
        if steps == Self.maxCatchUpSteps { accumulator = min(accumulator, Balance.dt) }
        interpolationAlpha = min(1, accumulator / Balance.dt)
        online.flush()
    }

    /// クライアント: 届いた tick の入力だけで進める。届かない間は待ち、溜まったら追いつく。
    /// ホストを失った（切断・ホストの中断）時は、届いている分を消化してから中断終了する（自然に終わっていればそのまま終わる）。
    private func advanceOnlineClient(dt: Double, online: OnlineBattleLink) {
        if let snapshot = online.takeSnapshot() { restore(snapshot) }
        let live = online.isMatchLive
        let buffered = online.bufferedFrames
        guard live || buffered > 0 else {
            if !sim.isEnded {
                // step は ended では何もしないので、終了イベントは直接配る（HUD が終了演出を出す）
                sim.abort()
                dispatch([.matchEnded(winner: nil, reason: .aborted)])
            }
            isEnded = true
            setOnlineStatus(.disconnected)
            return
        }
        accumulator += min(dt, 0.25)
        let maxSteps = (!live || buffered > Self.onlineCatchUpThreshold) ? Self.maxStepsPerFrame : Self.maxCatchUpSteps
        var steps = 0
        var starved = false
        while steps < maxSteps {
            let wantsStep = !live || accumulator >= Balance.dt || (buffered - steps) > Self.onlineJitterBuffer
            guard wantsStep else { break }
            guard let frame = online.frame(forTick: sim.state.tick + 1) else {
                starved = true
                break
            }
            dispatch(sim.step(commands: frame.commands))
            if sim.state.tick % OnlineProtocol.hashInterval == 0 {
                online.reportHash(tick: sim.state.tick, value: sim.state.stateHash())
            }
            accumulator = max(0, accumulator - Balance.dt)
            steps += 1
            if sim.isEnded {
                isEnded = true
                accumulator = 0
                break
            }
        }
        if starved {
            // 配信待ち: 時計を進めず現在の位置で止まる（次の配信が届いたらすぐ 1 tick 進める）
            accumulator = min(accumulator, Balance.dt)
        }
        if steps == 0 {
            // このフレームで一歩も進めなかった時間が続いたら待機表示
            onlineStall += dt
            setOnlineStatus(onlineStall > 0.5 ? .waitingForHost(onlineStall) : .none)
        } else {
            onlineStall = 0
            setOnlineStatus(.none)
        }
        if steps == maxSteps { accumulator = min(accumulator, Balance.dt) }
        interpolationAlpha = min(1, accumulator / Balance.dt)
        online.flush()
    }

    private func setOnlineStatus(_ s: OnlineBattleStatus) {
        if onlineStatus != s { onlineStatus = s }
    }

    /// ホストのスナップショットで状態を置き換える（オンライン対戦の再同期）。
    func restore(_ snapshot: SimState) {
        sim.restore(from: snapshot)
        accumulator = 0
        interpolationAlpha = 1
        if sim.isEnded { isEnded = true }
        hudTick &+= 1
    }

    private func stepOnce() {
        let commands: [HeroCommand]
        if isReplay {
            commands = replayFrames[sim.state.tick + 1] ?? []
        } else if let online, online.isHost {
            commands = pending + online.takeRemoteInputs()
            pending.removeAll(keepingCapacity: true)
        } else {
            commands = pending
            pending.removeAll(keepingCapacity: true)
        }
        let events = sim.step(commands: commands)
        if let online, online.isHost {
            let tick = sim.state.tick
            online.publish(frame: ReplayFrame(tick: tick, commands: commands),
                           stateHash: tick % OnlineProtocol.hashInterval == 0 ? sim.state.stateHash() : nil)
        }
        dispatch(events)
    }

    private func dispatch(_ events: [SimEvent]) {
        guard !events.isEmpty else { return }
        for id in subscriberOrder { subscribers[id]?(events) }
    }

    // MARK: 入力（HUD から）

    func send(_ command: PlayerCommand) {
        guard !isSpectating, !isEnded, let id = humanHeroID else { return }
        sequence &+= 1
        let c = HeroCommand(heroID: id, command: command, sequence: sequence)
        if let online, !online.isHost {
            // クライアントは自分で適用せず、ホストに送って配信を待つ
            online.sendInput(c)
        } else {
            pending.append(c)
        }
    }

    /// 仮想スティック（UIKit のドラッグベクトル。長さは任意）。
    func joystick(_ drag: CGVector) {
        let v = Vec2(Double(drag.dx), -Double(drag.dy))
        send(.move(direction: v.length < 0.05 ? .zero : v.normalized))
    }

    /// UIKit のドラッグベクトル → sim の方向ベクトル（正規化）。
    static func simDirection(fromDrag drag: CGVector) -> Vec2 {
        Vec2(Double(drag.dx), -Double(drag.dy)).normalized
    }

    #if DEBUG
    /// UI テスト用: 描画ループを止め、試合を終了（または maxTime）まで早送りする。
    /// 数百 tick ごとにメインスレッドを譲り、UI を固めない。
    func debugFastForward(maxTime: Double = 25 * 60) async {
        isPaused = true
        while !sim.isEnded && sim.state.time < maxTime {
            for _ in 0..<600 where !sim.isEnded { stepOnce() }
            await Task.yield()
        }
        if !sim.isEnded { sim.abort() }
        isEnded = true
        hudTick &+= 1
    }
    #endif

    // MARK: 終了

    /// 試合結果（リザルト用）。オンライン対戦では「人間」を自分だけにする（勝敗・強調表示は自分の視点）。
    func makeOutcome(abandoned: Bool) -> BattleOutcome {
        if abandoned && !sim.isEnded { sim.abort() }
        var summary = ScoreSystem.summary(sim.state)
        if isOnline, let localHeroID {
            summary.humanTeam = localTeam
            for k in summary.players.indices { summary.players[k].isHuman = summary.players[k].entityID == localHeroID }
        }
        let replay = recorder?.finish(summary: summary)
        return BattleOutcome(launch: launch, summary: summary, replay: replay, abandoned: abandoned)
    }
}
