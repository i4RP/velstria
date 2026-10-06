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
// 観戦（launch.isSpectating: AI 同士の観戦・リプレイ・オンラインの観戦席・人間のいない構成）:
// - 操作は送れない。霧は spectatorVision（nil = 全体が見える、.blue / .red = そのチームの視界）。
// - オフラインの観戦・リプレイはシークできる（isSeekable）。requestSeek(toTick:) はキーフレームから
//   イベントを配らずに再シミュレーションし、終わったら presentationEpoch を上げる（描画・HUD は残像を捨てて作り直す）。
// - 年表（timeline: キル・構造物・目標・ゴールド推移）は step 毎に作る。リプレイに年表が入っていれば fullTimeline で先まで分かる。
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
    /// 任意ユニット追従（観戦、死亡中の味方追従）。
    case followUnit(EntityID)
    /// ミニマップ操作などで固定位置を表示。
    case free(Vec2)
    /// 複数のユニットをまとめて画面に収める（自動カメラの集団戦）。先頭が主役（注目対象）。
    case framing([EntityID])
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

    // MARK: 観戦（視点・シーク・年表）

    /// 観戦者の視界（nil = 全体が見える、.blue / .red = そのチームの視界で霧を掛ける）。観戦中だけ効く。
    var spectatorVision: Team?
    /// 自動カメラ（見どころを自動で追う）。観戦中だけ効く。手動でカメラを動かすと自動カメラ側がしばらく控える。
    var spectatorDirectorEnabled = false
    /// 描画・HUD の作り直しが必要な不連続（シーク・再同期）のたびに増える。購読側は値の変化で残像・演出を捨てる。
    private(set) var presentationEpoch = 0
    /// シーク中の目標 tick（nil = シークしていない）。シーク中は frame(dt:) で進めない。
    private(set) var seekingToTick: Int?
    /// 観戦者のカメラ倍率（ピンチ・自動カメラ）。nil なら設定の cameraZoom。毎フレーム書き換えるので非監視。
    @ObservationIgnored var cameraZoomOverride: Double?
    /// リプレイの持ち主のヒーロー（強調表示・最初の追従先）。
    @ObservationIgnored private(set) var ownerHeroID: EntityID?
    /// シーク用のキーフレーム（tick 昇順・重複なし。先頭は試合開始時の状態）。シークできない時は空。
    @ObservationIgnored private(set) var keyframes: [SimState] = []
    /// 年表（step 毎に作る）。決定論なので巻き戻しても一度記録した区間は正しいまま捨てず、まだ記録していない tick だけ追記する。
    @ObservationIgnored private var timelineBuilder = ReplayTimelineBuilder()
    /// 試合全体の年表が先に分かっている場合（年表入りのリプレイ、バックグラウンドの事前計算）。
    @ObservationIgnored private(set) var fullTimeline: ReplayTimeline?
    @ObservationIgnored private var seekTask: Task<Void, Never>?
    /// シークの目標 tick の状態をメインスレッド外で作る（ReplayBaker が登録）。nil を返したら従来どおりここで進める。
    /// 返す状態は目標 tick のもの（または目標より前に試合が終わった状態）。
    @ObservationIgnored var seekStateProvider: (@MainActor (Int) async -> SimState?)?

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
    /// 観戦・リプレイの再生速度（spectatorSpeeds のいずれか）。オンラインでは無視される。
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

    /// 観戦・リプレイで選べる再生速度。
    static let spectatorSpeeds: [Double] = [0.5, 1, 2, 4, 8]
    /// シーク用キーフレームの間隔（tick）。30 秒（状態 1 つ約 200KB、40 分で約 16MB）。
    static let keyframeInterval = 900
    /// シークの再シミュレーションで、メインスレッドを譲るまでに進める tick 数。
    static let seekChunkTicks = 240

    /// オンライン対戦の早送り判定: これより多く配信が溜まっていたら 1 フレームで多めに進める。
    static let onlineCatchUpThreshold = 6
    /// オンライン対戦のジッタ吸収: これより多く溜まっていれば時計を待たずに進める（この tick 数だけ遅れて再生する）。
    static let onlineJitterBuffer = 2
    /// オンラインの観戦席のジッタ吸収: ホストが遅延を掛けて 0.1 秒（3 tick）毎にまとめて配るので厚めにする。
    /// 観戦は元々遅れて見ているので、数 tick 余分に遅れても困らない（滑らかさを優先する）。
    static let onlineSpectatorJitterBuffer = 8
    /// オンラインの観戦席の早送り判定: 参加直後・再同期の後のキーフレームからの追いかけ（最大で約 10 秒分）だけ早送りする。
    static let onlineSpectatorCatchUpThreshold = 45

    init(launch: BattleLaunch, online: OnlineBattleLink? = nil) {
        self.launch = launch
        self.online = launch.isOnline ? online : nil
        self.sim = Simulation(config: launch.config, map: MapDefinition.map(for: launch.config.mode))
        if let seat = launch.onlineSeat {
            let heroes = sim.state.heroIndices
            if heroes.indices.contains(seat) { localHeroID = sim.state.units[heroes[seat]].id }
        }
        if let replay = launch.replay {
            recorder = nil
            for f in replay.frames { replayFrames[f.tick, default: []].append(contentsOf: f.commands) }
            if let t = replay.timeline, t.coveredTick >= replay.finalTick { fullTimeline = t }
        } else if launch.onlineSpectator && self.online?.isHost != true {
            // 観戦席は途中から・遅延付きで見るので、記録しても再現できない
            // （ホストの実況は権威シミュレーションを tick 0 から遅延なしで回すので、選手のホストと同じく記録する）
            recorder = nil
        } else {
            // AI 同士の観戦も記録する（入力が無いので設定とシードだけの小さなリプレイになる）
            let r = ReplayRecorder(config: launch.config)
            recorder = r
            sim.recorder = r
        }
        if let seat = launch.ownerSeat { ownerHeroID = heroID(forSeat: seat) }
        if launch.isSpectating {
            if let owner = ownerHeroID {
                cameraMode = .followUnit(owner)
            } else if let first = sim.state.heroIndices.first {
                cameraMode = .followUnit(sim.state.units[first].id)
            }
        }
        timelineBuilder.begin(state: sim.state)
        if isSeekable { keyframes = [sim.state] }
        if launch.isSpectating {
            let o = launch.spectatorOptions
            spectatorVision = o.vision
            if !launch.isOnline, Self.spectatorSpeeds.contains(o.speed) { speed = o.speed }
            spectatorDirectorEnabled = o.director ?? (launch.replay == nil)
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

    /// 視点チーム（霧・見え方の基準）。プレイヤーは自分のチーム。観戦者は spectatorVision（既定 nil = 全体が見える）。
    var viewerTeam: Team? { isSpectating ? spectatorVision : localTeam }

    /// 実際に使うカメラ倍率（観戦者のピンチ・自動カメラの上書き > 設定）。
    var effectiveCameraZoom: Double { cameraZoomOverride ?? cameraZoom }

    /// 演出の注目対象（戦闘テキスト・遮蔽フェード・画面揺れ・足元の輪）。
    /// 追従中のユニット（観戦・死亡中の味方追従）> 自分のヒーロー。
    var presentationFocusID: EntityID? {
        switch cameraMode {
        case .followUnit(let id): return id
        case .framing(let ids): return ids.first ?? humanHeroID
        case .followHero, .free: return humanHeroID
        }
    }

    /// シーク（巻き戻し・早送り・コマ送り）できるか: オフラインの観戦・リプレイ。
    var isSeekable: Bool { !isOnline && isSpectating }

    /// リプレイの最終 tick（リプレイ以外は nil）。
    var replayFinalTick: Int? { launch.replay?.finalTick }

    /// これまでに分かっている年表（巻き戻した後は現在の tick より先も含む）。
    var knownTimeline: ReplayTimeline { timelineBuilder.timeline }

    /// 現在の tick までの年表（イベント一覧・ゴールド差の現在値）。
    var timeline: ReplayTimeline {
        var t = timelineBuilder.timeline
        if t.coveredTick > sim.state.tick { t.truncate(after: sim.state.tick) }
        return t
    }

    /// シークバー・グラフに使う年表（試合全体が分かっていればそれ、無ければこれまでに分かっている分）。
    var displayTimeline: ReplayTimeline {
        if let full = fullTimeline, full.coveredTick >= timelineBuilder.timeline.coveredTick { return full }
        return timelineBuilder.timeline
    }

    /// オンラインの観戦席: 配信の遅延（秒）。観戦席以外は nil。
    var onlineSpectatorDelaySeconds: Double? {
        guard launch.onlineSpectator, let online else { return nil }
        return Double(online.spectatorDelayTicks) * Balance.dt
    }

    /// オンライン対戦の観戦者数（オフラインは 0）。
    var onlineSpectatorCount: Int { online?.spectatorCount ?? 0 }

    /// シークできる最後の tick（リプレイは最終 tick、観戦は試合の最大時間）。
    var seekUpperBound: Int {
        if let final = replayFinalTick { return final }
        return Int((sim.state.config.maxDuration / Balance.dt).rounded())
    }

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
        guard !isEnded, seekingToTick == nil else { return }
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
    /// 観戦席（launch.onlineSpectator）: ホストが遅延を掛けて配るので、ジッタ吸収を厚く・早送りを控えめにする。
    /// 試合の終わりに遅延分の残りが前倒しで届いても、それは早送りせず通常の速さで見せる（ホストが終わった tick を知らせる）。
    private func advanceOnlineClient(dt: Double, online: OnlineBattleLink) {
        if let snapshot = online.takeSnapshot() { restore(snapshot) }
        let watcher = launch.onlineSpectator
        if watcher, let final = online.spectatorFinalTick, sim.state.tick >= final, !sim.isEnded {
            // 観戦席: ホストの試合が step の外で終わった（中断など）。最後の tick まで見たら中断として終える
            endOnlineMatchAborted()
            return
        }
        let buffered = online.bufferedFrames
        // 観戦席: 終わった tick を知らされていれば残りは全部届いている。その後にホストが部屋を閉じても（接続が切れても）
        // 残りは早送りせず遅延のまま見せる（届いた分が尽きたら下で中断として終える）
        let live = online.isMatchLive || (watcher && online.spectatorFinalTick != nil && buffered > 0)
        guard live || buffered > 0 else {
            endOnlineMatchAborted()
            return
        }
        // 早送りの判定に使う溜まり（観戦席: 前倒しで届いた遅延分の残りは数えない）
        var backlog = buffered
        if watcher, let final = online.spectatorFinalTick {
            backlog = max(0, min(buffered, final - online.spectatorDelayTicks - sim.state.tick))
        }
        let jitterBuffer = watcher ? Self.onlineSpectatorJitterBuffer : Self.onlineJitterBuffer
        let catchUpThreshold = watcher ? Self.onlineSpectatorCatchUpThreshold : Self.onlineCatchUpThreshold
        accumulator += min(dt, 0.25)
        let maxSteps = (!live || backlog > catchUpThreshold) ? Self.maxStepsPerFrame : Self.maxCatchUpSteps
        var steps = 0
        var starved = false
        while steps < maxSteps {
            let wantsStep = !live || accumulator >= Balance.dt || (backlog - steps) > jitterBuffer
            guard wantsStep else { break }
            guard let frame = online.frame(forTick: sim.state.tick + 1) else {
                starved = true
                break
            }
            let events = sim.step(commands: frame.commands)
            observeStep(events)
            dispatch(events)
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
            // 秒単位に丸める（表示は秒。毎フレーム値が変わると重ね表示が毎フレーム描き直される）
            setOnlineStatus(onlineStall > 0.5 ? .waitingForHost(onlineStall.rounded(.down)) : .none)
        } else {
            onlineStall = 0
            setOnlineStatus(.none)
        }
        if steps == maxSteps { accumulator = min(accumulator, Balance.dt) }
        interpolationAlpha = min(1, accumulator / Balance.dt)
        online.flush()
    }

    /// クライアント: ホストを失った・ホストが試合を中断した（届いていた分は消化済み）。中断として終える。
    private func endOnlineMatchAborted() {
        if !sim.isEnded {
            // step は ended では何もしないので、終了イベントは直接配る（HUD・年表が終わりを知る）
            sim.abort()
            let events: [SimEvent] = [.matchEnded(winner: nil, reason: .aborted)]
            observeStep(events)
            dispatch(events)
        }
        isEnded = true
        setOnlineStatus(.disconnected)
    }

    private func setOnlineStatus(_ s: OnlineBattleStatus) {
        if onlineStatus != s { onlineStatus = s }
    }

    /// ホストのスナップショットで状態を置き換える（オンライン対戦の再同期・途中参加）。
    func restore(_ snapshot: SimState) {
        // 状態が飛ぶ（途中の tick を自分で進めていない）と、記録した入力列からは再現できない。
        // オンラインは同じ tick でも、ずれた状態をホストの状態で置き換えたので記録した入力列からは再現できない
        if online != nil || snapshot.tick != sim.state.tick { recorder?.markIncomplete() }
        sim.restore(from: snapshot)
        // ずれた状態で記録した先の年表は信用できないので、置き換え後の tick より先は捨てる
        if snapshot.tick < timelineBuilder.timeline.coveredTick { timelineBuilder.rewind(to: snapshot.tick) }
        accumulator = 0
        interpolationAlpha = 1
        isEnded = sim.isEnded
        presentationEpoch &+= 1
        hudTick &+= 1
    }

    // MARK: 観戦のシーク

    /// 指定 tick へ移動する（オフラインの観戦・リプレイのみ）。最寄りのキーフレームから、イベントを配らずに再シミュレーションする。
    /// 先の時刻へは今の位置から進める。長い区間は数百 tick ごとにメインスレッドを譲る（seekingToTick が立っている間は frame で進めない）。
    func requestSeek(toTick target: Int) {
        guard isSeekable else { return }
        let goal = max(0, min(target, seekUpperBound))
        seekTask?.cancel()
        seekingToTick = goal
        seekTask = Task { @MainActor [weak self] in
            await self?.performSeek(to: goal)
        }
    }

    /// 現在位置からの相対シーク（秒）。
    func seek(bySeconds seconds: Double) {
        let base = seekingToTick ?? sim.state.tick
        requestSeek(toTick: base + Int((seconds / Balance.dt).rounded()))
    }

    private func performSeek(to goal: Int) async {
        if let provider = seekStateProvider {
            // バックグラウンドの事前計算（ReplayBaker）で目標の状態を作る（UI を止めない）
            let exact = await provider(goal)
            if Task.isCancelled { return }
            if let exact, exact.config == sim.state.config,
               exact.tick == goal || (exact.tick < goal && exact.phase == .ended) {
                sim.restore(from: exact)
                // ここで進めた時と同じく、記録の終わりを到達した tick まで伸ばす（観戦の記録は入力が無いので列は変わらない）
                recorder?.record(tick: exact.tick, commands: [])
            }
        }
        // 戻る・保存済みのキーフレームを越えて進む時は、目標以前で最も新しいキーフレームから再開する
        let base = keyframes.last { $0.tick <= goal }
        if let base, goal < sim.state.tick || base.tick > sim.state.tick {
            // 年表は捨てない（決定論なので記録済みの区間は進め直しても同じ。未記録の tick だけ追記される）
            sim.restore(from: base)
        }
        while sim.state.tick < goal && !sim.isEnded {
            if Task.isCancelled { return }
            var n = 0
            while n < Self.seekChunkTicks && sim.state.tick < goal && !sim.isEnded {
                _ = advanceOneTick()
                n += 1
                if reachedReplayEnd { break }
            }
            if reachedReplayEnd { break }
            await Task.yield()
        }
        if Task.isCancelled { return }
        finishReplayIfNeeded(dispatchEnd: false)
        accumulator = 0
        interpolationAlpha = 1
        isEnded = sim.isEnded
        seekingToTick = nil
        presentationEpoch &+= 1
        hudTick &+= 1
    }

    /// 一時停止中のコマ送り（イベントは配る）。
    func stepTicks(_ count: Int) {
        guard isSeekable, isPaused, seekingToTick == nil, !isEnded else { return }
        for _ in 0..<max(0, count) {
            stepOnce()
            if sim.isEnded { isEnded = true; break }
        }
        interpolationAlpha = 1
        hudTick &+= 1
    }

    /// バックグラウンドで先に計算した状態をキーフレームに加える（tick 昇順を保つ）。
    func adoptKeyframe(_ state: SimState) {
        guard isSeekable, state.config == sim.state.config else { return }
        if let i = keyframes.firstIndex(where: { $0.tick >= state.tick }) {
            if keyframes[i].tick == state.tick { return }
            keyframes.insert(state, at: i)
        } else {
            keyframes.append(state)
        }
    }

    /// バックグラウンドで先に作った試合全体の年表を採用する。
    func adoptFullTimeline(_ timeline: ReplayTimeline) {
        if (fullTimeline?.coveredTick ?? -1) < timeline.coveredTick { fullTimeline = timeline }
        // 決定論なので先頭は同じ。記録側も置き換えて、先のキーフレームへ飛んでも年表に穴が開かないようにする
        if timeline.coveredTick > timelineBuilder.timeline.coveredTick { timelineBuilder.replace(with: timeline) }
    }

    /// リプレイが記録の最終 tick に達した。
    private var reachedReplayEnd: Bool {
        guard let final = replayFinalTick else { return false }
        return sim.state.tick >= final
    }

    /// リプレイが最終 tick に達しても sim が終わっていない（途中で抜けた記録）なら中断終了にする。
    private func finishReplayIfNeeded(dispatchEnd: Bool) {
        guard reachedReplayEnd, !sim.isEnded else { return }
        sim.abort()
        let events: [SimEvent] = [.matchEnded(winner: nil, reason: .aborted)]
        timelineBuilder.observe(events: events, state: sim.state)
        if dispatchEnd { dispatch(events) }
    }

    /// 1 tick 進める（入力の供給・配信・年表・キーフレーム）。イベントを返すだけで配らない。
    private func advanceOneTick() -> [SimEvent] {
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
        observeStep(events)
        return events
    }

    /// step の後処理（年表・シーク用キーフレーム）。
    private func observeStep(_ events: [SimEvent]) {
        timelineBuilder.observe(events: events, state: sim.state)
        if isSeekable, sim.state.tick % Self.keyframeInterval == 0, sim.state.tick > (keyframes.last?.tick ?? -1) {
            keyframes.append(sim.state)
        }
    }

    private func stepOnce() {
        dispatch(advanceOneTick())
        finishReplayIfNeeded(dispatchEnd: true)
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
    /// リプレイは記録時の結果を使う（途中で抜けても、巻き戻していても、試合本来の結果を見せる）。
    func makeOutcome(abandoned: Bool) -> BattleOutcome {
        seekTask?.cancel()
        seekTask = nil
        seekingToTick = nil
        if abandoned && !sim.isEnded { sim.abort() }
        var summary = ScoreSystem.summary(sim.state)
        if let recorded = launch.replay?.summary {
            summary = recorded
        } else if launch.onlineSpectator {
            summary.humanTeam = nil
            for k in summary.players.indices { summary.players[k].isHuman = false }
        } else if isOnline, let localHeroID {
            summary.humanTeam = localTeam
            for k in summary.players.indices { summary.players[k].isHuman = summary.players[k].entityID == localHeroID }
        }
        if let recorder {
            // 事前計算で先まで分かっていても、保存するのは記録した区間まで
            var recorded = timelineBuilder.timeline
            recorded.truncate(after: recorder.lastTick)
            recorder.timeline = recorded
        }
        let replay = recorder.flatMap { $0.isIncomplete ? nil : $0.finish(summary: summary) }
        return BattleOutcome(launch: launch, summary: summary, replay: replay, abandoned: abandoned)
    }
}
