import Foundation

// 担当: battle-renderer（性能）。画質の自動調整（ガバナー）。UIKit・RealityKit に依存しない純粋なロジック（単体テスト可能）。
//
// AAA タイトルの動的品質と同じく、フレーム時間・端末温度・低電力モードを見て、ユーザーが選んだ画質を「上限」として段階的に下げ、
// 余裕が戻れば 1 段ずつ戻す。出力はユーザー設定を超えない（影・軌跡・後処理・粒子・解像度・fps のどれも上げる方向には動かさない）。
// - 入力: 毎フレームの描画間隔（dt）と処理時間（work = sim + 描画同期 + 重ね表示）、ProcessInfo.thermalState、低電力モード
// - 判定: 1 秒ごとに直近 2 秒の p95 を評価。予算超過が 3 秒続けば 1 段下げ、余裕が 10 秒続けば 1 段戻す。変更の間隔は 4 秒以上
// - 下げる順: 環境パーティクル → 粒子量・放出体上限 → 投射物の軌跡 → 後処理 1 段 → 後処理なし → 影 → 解像度 87.5% → 75% → 30fps
//   （30fps は温度 .critical のときだけ。影は両方の状態を読み込み幕の裏で描いたときだけ切り替える＝試合中にシェーダーを作らない）
// - 温度 .serious は「後処理なし」以上、.critical は最低段を強制。低電力モードは「後処理 1 段」以上
// - 戻した直後にまた下がった（行ったり来たり）場合は、次に戻すまでの待ちを倍にする（最大 60 秒）

struct AdaptiveQuality {
    /// 下げる段（rawValue が大きいほど軽い）。ユーザーの設定によっては変化のない段があり、その段は飛ばす。
    enum Step: Int, CaseIterable, Comparable, Codable, Sendable, CustomStringConvertible {
        case full = 0
        case noAmbient
        case fewerParticles
        case noTrails
        case reducedPost
        case noPost
        case noShadows
        case scale88
        case scale75
        case fps30

        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }

        var description: String {
            switch self {
            case .full: return "full"
            case .noAmbient: return "noAmbient"
            case .fewerParticles: return "fewerParticles"
            case .noTrails: return "noTrails"
            case .reducedPost: return "reducedPost"
            case .noPost: return "noPost"
            case .noShadows: return "noShadows"
            case .scale88: return "scale88"
            case .scale75: return "scale75"
            case .fps30: return "fps30"
            }
        }
    }

    /// 実際に描画へ反映する値。
    struct Output: Equatable {
        /// 画質（level はユーザーの選択のまま。個々の項目だけ下げる）。
        var settings: RenderSettings
        var post: PostProcessSettings
        /// 描画解像度の倍率（arView.contentScaleFactor = 端末の倍率 × これ。0.75〜1）。
        var renderScale: Float
    }

    enum Reason: Equatable, CustomStringConvertible {
        case overBudget(frameP95Ms: Double, workP95Ms: Double)
        case headroom
        case thermal(ProcessInfo.ThermalState)
        case lowPower(Bool)
        case settings

        var description: String {
            switch self {
            case let .overBudget(f, w): return String(format: "over budget (frame p95 %.1f ms, work p95 %.1f ms)", f, w)
            case .headroom: return "headroom"
            case let .thermal(s): return "thermal \(AdaptiveQuality.thermalName(s))"
            case let .lowPower(on): return on ? "low power on" : "low power off"
            case .settings: return "settings"
            }
        }
    }

    struct Change: Equatable {
        var from: Step
        var to: Step
        var reason: Reason
        var output: Output
        /// ガバナーの経過時間（秒。フレーム dt の合計）。
        var time: Double

        var summary: String { String(format: "%.1fs %@ -> %@ (%@)", time, from.description, to.description, reason.description) }
    }

    struct Config {
        /// 評価の周期（秒）と、p95 を取る窓の数（周期 × span 秒分）。
        var window: Double = 1
        var span = 2
        /// 予算超過: p95 の描画間隔 > 目標 × overFrame、または p95 の処理時間 > 目標 × overWork。
        var overFrame = 1.25
        var overWork = 0.7
        /// 余裕あり: p95 の描画間隔 ≤ 目標 × headroomFrame かつ p95 の処理時間 ≤（1 段上の）目標 × headroomWork。
        var headroomFrame = 1.1
        var headroomWork = 0.4
        /// 予算超過がこの秒数続いたら 1 段下げる。
        var downAfter: Double = 3
        /// 余裕がこの秒数続いたら 1 段戻す（行ったり来たりすると倍になる）。
        var upAfter: Double = 10
        var maxUpAfter: Double = 60
        /// 変更の最小間隔（秒）。
        var cooldown: Double = 4
        /// 戻してからこの秒数以内に下がったら「戻しすぎ」とみなす。
        var revertWindow: Double = 20
        /// 温度・低電力モードで強制する段の下限。
        var seriousFloor: Step = .noPost
        var criticalFloor: Step = .fps30
        var lowPowerFloor: Step = .reducedPost
        /// フレーム時間で上げ下げする（false なら温度・低電力モードの下限だけ。スクリーンショットの撮影用）。
        var adaptsToFrameTime = true
    }

    let config: Config
    private(set) var user: RenderSettings
    private(set) var shadowSwitchable: Bool
    private(set) var thermal: ProcessInfo.ThermalState
    private(set) var lowPower: Bool
    /// 変化のある段だけを並べたもの（先頭は .full）。
    private(set) var steps: [Step]
    private(set) var index = 0
    private(set) var output: Output
    private(set) var time: Double = 0
    private(set) var upAfter: Double
    private var frames: [Double] = []
    private var works: [Double] = []
    private var history: [[Double]] = []
    private var workHistory: [[Double]] = []
    private var windowTime: Double = 0
    private var overTime: Double = 0
    private var headroomTime: Double = 0
    private var lastChange: Double = -.infinity
    private var lastUpgrade: Double?
    /// 直近の評価の p95（ms。デバッグ表示用）。
    private(set) var lastFrameP95Ms: Double = 0
    private(set) var lastWorkP95Ms: Double = 0

    init(user: RenderSettings, shadowSwitchable: Bool = false, thermal: ProcessInfo.ThermalState = .nominal,
         lowPower: Bool = false, config: Config = Config()) {
        self.config = config
        self.user = user
        self.shadowSwitchable = shadowSwitchable
        self.thermal = thermal
        self.lowPower = lowPower
        upAfter = config.upAfter
        steps = AdaptiveQuality.effectiveSteps(user: user, shadowSwitchable: shadowSwitchable)
        output = AdaptiveQuality.output(.full, user: user, shadowSwitchable: shadowSwitchable)
        frames.reserveCapacity(150)
        works.reserveCapacity(150)
        index = max(index, floorIndex)
        output = AdaptiveQuality.output(steps[index], user: user, shadowSwitchable: shadowSwitchable)
    }

    var step: Step { steps[index] }

    /// 温度・低電力モードから決まる段の下限（steps の添字）。
    var floorIndex: Int {
        var floor = Step.full
        switch thermal {
        case .serious: floor = max(floor, config.seriousFloor)
        case .critical: floor = max(floor, config.criticalFloor)
        default: break
        }
        if lowPower { floor = max(floor, config.lowPowerFloor) }
        guard floor > .full else { return 0 }
        return steps.firstIndex { $0 >= floor } ?? steps.count - 1
    }

    // MARK: 入力

    /// 1 フレーム分（秒）。段を変えたときだけ Change を返す。
    mutating func record(frameDt: Double, work: Double) -> Change? {
        let dt = max(0, min(frameDt, 1))
        time += dt
        windowTime += dt
        frames.append(dt)
        works.append(max(0, work))
        guard windowTime >= config.window else { return nil }
        windowTime = 0
        history.append(frames)
        workHistory.append(works)
        frames.removeAll(keepingCapacity: true)
        works.removeAll(keepingCapacity: true)
        if history.count > config.span {
            history.removeFirst(history.count - config.span)
            workHistory.removeFirst(workHistory.count - config.span)
        }
        return evaluate()
    }

    /// 一時停止・復帰・段の変更の直後など、直前のフレームを判定に使わない。
    mutating func resetWindow() {
        frames.removeAll(keepingCapacity: true)
        works.removeAll(keepingCapacity: true)
        history.removeAll()
        workHistory.removeAll()
        windowTime = 0
        overTime = 0
        headroomTime = 0
    }

    mutating func setThermal(_ s: ProcessInfo.ThermalState) -> Change? {
        guard s != thermal else { return nil }
        thermal = s
        return enforceFloor(reason: .thermal(s))
    }

    mutating func setLowPower(_ on: Bool) -> Change? {
        guard on != lowPower else { return nil }
        lowPower = on
        return enforceFloor(reason: .lowPower(on))
    }

    /// ユーザーが設定を変えた（同じ段を新しい設定の上で表し直す）。
    mutating func setUser(_ s: RenderSettings) -> Change? {
        guard s != user else { return nil }
        user = s
        return rebuildSteps()
    }

    /// 影の両方の状態がウォームアップ済みか（済んでいなければ影は切り替えない）。
    mutating func setShadowSwitchable(_ on: Bool) -> Change? {
        guard on != shadowSwitchable else { return nil }
        shadowSwitchable = on
        return rebuildSteps()
    }

    // MARK: 判定

    private var targetInterval: Double { 1 / Double(max(1, output.settings.frameRate)) }

    private mutating func evaluate() -> Change? {
        let f = AdaptiveQuality.percentile(history.flatMap { $0 }, 0.95)
        let w = AdaptiveQuality.percentile(workHistory.flatMap { $0 }, 0.95)
        lastFrameP95Ms = f * 1000
        lastWorkP95Ms = w * 1000
        guard config.adaptsToFrameTime else { return nil }
        let target = targetInterval
        // 1 段上（戻した先）の目標。30fps から戻すときは 60fps の予算で余裕を測る
        let upTarget = index > 0
            ? 1 / Double(max(1, AdaptiveQuality.output(steps[index - 1], user: user, shadowSwitchable: shadowSwitchable).settings.frameRate))
            : target
        let over = f > target * config.overFrame || w > target * config.overWork
        let headroom = f <= target * config.headroomFrame && w <= upTarget * config.headroomWork
        if over {
            overTime += config.window
            headroomTime = 0
        } else if headroom {
            headroomTime += config.window
            overTime = 0
        } else {
            overTime = 0
            headroomTime = 0
        }
        // 戻した後しばらく下がらなければ、戻すまでの待ちを元へ近づける
        if let up = lastUpgrade, time - up >= config.revertWindow {
            lastUpgrade = nil
            upAfter = max(config.upAfter, upAfter / 2)
        }
        let cooled = time - lastChange >= config.cooldown
        // フレーム時間だけでは 30fps の段まで下げない（30fps は温度 .critical の下限としてだけ使う）
        let budgetLimit = steps.lastIndex { $0 < .fps30 } ?? 0
        if over, overTime >= config.downAfter, cooled, index < budgetLimit {
            if let up = lastUpgrade, time - up < config.revertWindow {
                upAfter = min(config.maxUpAfter, upAfter * 2)
                lastUpgrade = nil
            }
            return move(to: index + 1, reason: .overBudget(frameP95Ms: f * 1000, workP95Ms: w * 1000))
        }
        if headroom, headroomTime >= upAfter, cooled, index > floorIndex {
            lastUpgrade = time
            return move(to: index - 1, reason: .headroom)
        }
        return nil
    }

    private mutating func enforceFloor(reason: Reason) -> Change? {
        // 下限に押さえられていた間の余裕は数えない（温度が戻ってから改めて余裕を確かめて 1 段ずつ戻す）
        overTime = 0
        headroomTime = 0
        let floor = floorIndex
        guard index < floor else { return nil }
        return move(to: floor, reason: reason)
    }

    private mutating func rebuildSteps() -> Change? {
        let current = step
        let before = output
        steps = AdaptiveQuality.effectiveSteps(user: user, shadowSwitchable: shadowSwitchable)
        // 同じ段（無ければそれより軽い最初の段）に合わせる
        index = steps.firstIndex { $0 >= current } ?? steps.count - 1
        index = max(index, floorIndex)
        output = AdaptiveQuality.output(steps[index], user: user, shadowSwitchable: shadowSwitchable)
        guard output != before else { return nil }
        return Change(from: current, to: step, reason: .settings, output: output, time: time)
    }

    private mutating func move(to newIndex: Int, reason: Reason) -> Change? {
        let from = step
        index = max(0, min(steps.count - 1, newIndex))
        guard step != from else { return nil }
        output = AdaptiveQuality.output(step, user: user, shadowSwitchable: shadowSwitchable)
        lastChange = time
        resetWindow()
        return Change(from: from, to: step, reason: reason, output: output, time: time)
    }

    // MARK: 段 → 設定

    /// 段 step を user に適用した結果（ユーザー設定を超えない）。
    static func output(_ step: Step, user: RenderSettings, shadowSwitchable: Bool) -> Output {
        var s = user
        var q = user.quality
        if step >= .noAmbient { q.ambientParticles = false }
        if step >= .fewerParticles {
            q.particleScale = min(user.quality.particleScale, max(0.25, user.quality.particleScale * 0.6))
            q.maxEmitters = min(user.quality.maxEmitters, max(8, Int((Float(user.quality.maxEmitters) * 0.6).rounded())))
        }
        if step >= .noTrails { q.projectileTrails = false }
        if step >= .noShadows && shadowSwitchable { q.shadows = false }
        s.quality = q
        var post = PostProcessSettings.preset(user.quality.level)
        if step >= .reducedPost { post = .preset(lower(user.quality.level)) }
        if step >= .noPost { post = .preset(.low) }
        var scale: Float = 1
        if step >= .scale88 { scale = 0.875 }
        if step >= .scale75 { scale = 0.75 }
        if step >= .fps30 { s.frameRate = min(user.frameRate, 30) }
        return Output(settings: s, post: post, renderScale: scale)
    }

    /// user で実際に変化のある段だけを並べる（先頭は .full）。
    static func effectiveSteps(user: RenderSettings, shadowSwitchable: Bool) -> [Step] {
        var result: [Step] = [.full]
        var last = output(.full, user: user, shadowSwitchable: shadowSwitchable)
        for step in Step.allCases.dropFirst() {
            let o = output(step, user: user, shadowSwitchable: shadowSwitchable)
            if o != last {
                result.append(step)
                last = o
            }
        }
        return result
    }

    static func lower(_ q: GraphicsQuality) -> GraphicsQuality {
        switch q {
        case .high: return .medium
        case .medium, .low: return .low
        }
    }

    static func percentile(_ values: [Double], _ q: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((Double(sorted.count) * q).rounded(.up)) - 1
        return sorted[max(0, min(sorted.count - 1, rank))]
    }

    static func thermalName(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
