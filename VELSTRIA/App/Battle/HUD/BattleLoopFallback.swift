import QuartzCore
import VelstriaCore

// 担当: battle-hud。戦闘ループの予備駆動。
// 通常は BattleSceneView（RealityKit の描画更新）が毎フレーム controller.frame(dt:) を呼ぶ。
// 描画側は読み込み幕が上がる時に controller.markPresentationReady() を呼んでから駆動を始めるので、
// それまで（地面テクスチャ生成・ウォームアップ中）は sim を進めずに待ち、準備完了を見たら駆動せずに停止する。
// 描画側が一定時間（readyTimeoutFrames）準備を終えない場合だけ、準備完了扱いにして CADisplayLink で frame(dt:) を呼び、
// 自分以外の呼び出し（tick または補間係数の変化）を検出したら即座に停止して二重駆動を避ける。

@MainActor
final class BattleLoopFallback {
    /// CADisplayLink はターゲットを強参照するので、弱参照の中継を挟む。
    private final class Proxy: NSObject {
        weak var owner: BattleLoopFallback?

        @objc func step(_ link: CADisplayLink) {
            MainActor.assumeIsolated { owner?.step(link) }
        }
    }

    private weak var controller: BattleController?
    private var link: CADisplayLink?
    private let proxy = Proxy()
    private var lastTimestamp: CFTimeInterval = 0
    private var expectedTick = -1
    private var expectedAlpha = -1.0
    /// 描画側の準備を待ったフレーム数（一時停止中は数えない）。
    private var waitedFrames = 0
    /// 描画側の準備をこのフレーム数（60Hz で約 10 秒）待っても終わらなければ予備駆動に切り替える。
    static let readyTimeoutFrames = 600
    /// 描画側がループを駆動していると判定して停止した。
    private(set) var yielded = false

    var isRunning: Bool { link != nil }

    func start(controller: BattleController) {
        guard link == nil, !yielded else { return }
        self.controller = controller
        proxy.owner = self
        let l = CADisplayLink(target: proxy, selector: #selector(Proxy.step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    private func step(_ l: CADisplayLink) {
        guard let c = controller else {
            stop()
            return
        }
        if expectedTick < 0 {
            // まだ一度も駆動していない
            if c.isPresentationReady {
                // 描画側が準備を終えて駆動を始めた → 予備駆動は不要
                yielded = true
                stop()
                return
            }
            // 読み込み幕の裏では sim を進めない（開始告知・試合時間が幕の裏で進まないように）
            if !c.isPaused { waitedFrames += 1 }
            guard waitedFrames >= Self.readyTimeoutFrames else { return }
            c.markPresentationReady()
        }
        let tick = c.sim.state.tick
        if expectedTick >= 0 && (tick != expectedTick || c.interpolationAlpha != expectedAlpha) {
            // 前回の呼び出し以降に誰かが frame(dt:) を呼んだ
            yielded = true
            stop()
            return
        }
        let dt = lastTimestamp == 0 ? 1.0 / 60.0 : max(0, l.timestamp - lastTimestamp)
        lastTimestamp = l.timestamp
        c.frame(dt: dt)
        expectedTick = c.sim.state.tick
        expectedAlpha = c.interpolationAlpha
    }
}
