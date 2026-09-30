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
    /// リプレイ再生時: tick → その tick の入力。
    @ObservationIgnored private var replayFrames: [Int: [HeroCommand]] = [:]

    // MARK: HUD が購読する値（低頻度更新）

    /// 15Hz で増える。HUD はこれを参照して SimState を読み直す。
    private(set) var hudTick = 0
    private(set) var isEnded = false
    /// 描画側の準備（地面テクスチャ・ウォームアップが済み、読み込み幕が上がる）が完了した。
    /// これが立つまで予備駆動（BattleLoopFallback）は sim を進めず、HUD も表示しない。
    private(set) var isPresentationReady = false
    var isPaused = false
    /// 観戦・リプレイの再生速度（1, 2, 4）。
    var speed: Double = 1
    var cameraMode: CameraMode = .followHero
    /// 設定のカメラ倍率（0.8〜1.3）。
    var cameraZoom: Double = 1.0

    // MARK: 描画が毎フレーム読む値（非監視）

    @ObservationIgnored var aim: AimIndicator?
    /// 補間係数（前 tick → 現 tick）。
    @ObservationIgnored private(set) var interpolationAlpha: Double = 0

    @ObservationIgnored private var accumulator: Double = 0
    @ObservationIgnored private var hudAccumulator: Double = 0
    @ObservationIgnored private var pending: [HeroCommand] = []
    @ObservationIgnored private var sequence: UInt32 = 0
    @ObservationIgnored private var subscribers: [UUID: ([SimEvent]) -> Void] = [:]
    @ObservationIgnored private var subscriberOrder: [UUID] = []

    static let maxStepsPerFrame = 12
    static let hudInterval = 1.0 / 15.0

    init(launch: BattleLaunch) {
        self.launch = launch
        self.sim = Simulation(config: launch.config)
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
    var humanHeroID: EntityID? { isSpectating ? nil : sim.state.humanHeroID }

    /// 人間ヒーローの units 添字（観戦中は nil）。
    var humanIndex: Int? { humanHeroID.flatMap { sim.state.index(of: $0) } }

    /// 視点チーム（観戦は Blue 視点ではなく全体可視にするため nil）。
    var viewerTeam: Team? { isSpectating ? nil : .blue }

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

    /// 描画側の準備完了を通知する（BattleRenderer が読み込み幕を上げる時。予備駆動のタイムアウト時）。
    func markPresentationReady() {
        guard !isPresentationReady else { return }
        isPresentationReady = true
    }

    /// 描画フレーム毎に呼ぶ（dt = 実時間の経過秒）。
    func frame(dt: Double) {
        guard !isEnded, !isPaused else { return }
        accumulator += min(dt, 0.25) * speed
        var steps = 0
        while accumulator >= Balance.dt && steps < Self.maxStepsPerFrame {
            stepOnce()
            accumulator -= Balance.dt
            steps += 1
            if sim.isEnded {
                isEnded = true
                accumulator = 0
                break
            }
        }
        if steps == Self.maxStepsPerFrame { accumulator = min(accumulator, Balance.dt) }
        interpolationAlpha = min(1, accumulator / Balance.dt)

        hudAccumulator += dt
        if hudAccumulator >= Self.hudInterval || isEnded {
            hudAccumulator = 0
            hudTick &+= 1
        }
    }

    private func stepOnce() {
        let commands: [HeroCommand]
        if isReplay {
            commands = replayFrames[sim.state.tick + 1] ?? []
        } else {
            commands = pending
            pending.removeAll(keepingCapacity: true)
        }
        let events = sim.step(commands: commands)
        guard !events.isEmpty else { return }
        for id in subscriberOrder { subscribers[id]?(events) }
    }

    // MARK: 入力（HUD から）

    func send(_ command: PlayerCommand) {
        guard !isSpectating, !isEnded, let id = humanHeroID else { return }
        sequence &+= 1
        pending.append(HeroCommand(heroID: id, command: command, sequence: sequence))
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

    /// 試合結果（リザルト用）。
    func makeOutcome(abandoned: Bool) -> BattleOutcome {
        if abandoned && !sim.isEnded { sim.abort() }
        let summary = ScoreSystem.summary(sim.state)
        let replay = recorder?.finish(summary: summary)
        return BattleOutcome(launch: launch, summary: summary, replay: replay, abandoned: abandoned)
    }
}
