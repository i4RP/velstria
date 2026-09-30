#if DEBUG
import QuartzCore
import UIKit

// 担当: battle-renderer。DEBUG ビルド専用の FPS / tick 時間表示（Release では丸ごと除外）。

final class DebugStatsOverlay: UILabel {
    private var frames = 0
    private var frameTimeSum: Double = 0
    private var simTimeSum: Double = 0
    private var syncTimeSum: Double = 0
    private var worstFrame: Double = 0
    private var elapsed: Double = 0
    /// 直近の集計値（テスト・計測ログ用）。
    private(set) var lastFPS: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        textColor = UIColor(white: 1, alpha: 0.92)
        backgroundColor = UIColor(white: 0, alpha: 0.4)
        numberOfLines = 2
        layer.cornerRadius = 4
        layer.masksToBounds = true
        isUserInteractionEnabled = false
        accessibilityIdentifier = "battle_debug_stats"
        text = " -- fps"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// frameDt = 描画フレーム間隔、sim = controller.frame の所要、sync = 描画同期の所要（秒）。
    func record(frameDt: Double, sim: Double, sync: Double, entities: Int) {
        frames += 1
        frameTimeSum += frameDt
        simTimeSum += sim
        syncTimeSum += sync
        worstFrame = max(worstFrame, frameDt)
        elapsed += frameDt
        guard elapsed >= 0.5 else { return }
        let n = Double(max(1, frames))
        lastFPS = n / max(0.0001, frameTimeSum)
        text = String(format: " %.0f fps  %.1fms (max %.1f)\n sim %.2fms  sync %.2fms  e%d",
                      lastFPS, frameTimeSum / n * 1000, worstFrame * 1000, simTimeSum / n * 1000, syncTimeSum / n * 1000,
                      entities)
        frames = 0
        frameTimeSum = 0
        simTimeSum = 0
        syncTimeSum = 0
        worstFrame = 0
        elapsed = 0
    }
}
#endif
