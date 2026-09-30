import QuartzCore
import VelstriaCore

// 担当: battle-hud。戦闘ループの予備駆動。
// 通常は BattleSceneView（RealityKit の描画更新）が毎フレーム controller.frame(dt:) を呼ぶ。
// 描画側がまだループを回していない間だけ CADisplayLink で frame(dt:) を呼び、
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
