import Foundation
import os

// 担当: battle-renderer（性能）。戦闘のフレーム時間の分布・ヒッチ・処理内訳を常時（出荷ビルドでも）集計する。
//
// - frame: 描画ループの間隔（SceneEvents.Update の deltaTime）。メインスレッドが詰まると伸びる＝体感のカクつき。
// - work: こちらが毎フレーム行う処理（sim + 描画同期 + 重ね表示）の CPU 時間。予算は 60fps で 8 ms 目安。
// - ヒッチ: 目標間隔の 1.5 倍を超えたフレーム。ヒッチ時間 = 目標を超えた分の合計（Apple の hitch time と同じ考え方）。
//   ヒッチ率（ms/s）= ヒッチ時間 ÷ 経過秒。Apple の目安は 5 未満が良好、10 以上は要対策。
// Instruments（Points of Interest / os_signpost）では "Battle" カテゴリの区間で読み込み・幕の裏・プレイ中を確認できる。

@MainActor
final class FrameStats {
    static let log = OSLog(subsystem: "com.bitcoinpay.velstria", category: "Battle")
    static let signposter = OSSignposter(logHandle: log)

    /// 0.25 ms 刻み・200 ms まで（以降は最後の箱）。
    private static let bucketWidth = 0.25
    private static let bucketCount = 801

    struct Summary: Codable, Sendable, Equatable {
        var frames: Int
        var seconds: Double
        var targetMs: Double
        var p50Ms: Double
        var p95Ms: Double
        var p99Ms: Double
        var maxMs: Double
        var hitches: Int
        var hitchMs: Double
        /// ヒッチ時間 ÷ 経過秒（ms/s）。
        var hitchRatio: Double
        var workP50Ms: Double
        var workP95Ms: Double
        var workP99Ms: Double
        var workMaxMs: Double
        var simAvgMs: Double
        var syncAvgMs: Double
        var overlayAvgMs: Double
    }

    private(set) var targetInterval: Double
    private var frameHist = [Int](repeating: 0, count: FrameStats.bucketCount)
    private var workHist = [Int](repeating: 0, count: FrameStats.bucketCount)
    private var frames = 0
    private var seconds: Double = 0
    private var worstFrame: Double = 0
    private var worstWork: Double = 0
    private var hitches = 0
    private var hitchTime: Double = 0
    private var simSum: Double = 0
    private var syncSum: Double = 0
    private var overlaySum: Double = 0
    private var liveInterval: OSSignpostIntervalState?

    init(frameRate: Int) {
        targetInterval = 1 / Double(max(1, frameRate))
    }

    func setFrameRate(_ fps: Int) { targetInterval = 1 / Double(max(1, fps)) }

    /// 直近のフレームがヒッチだったか（品質の自動調整が参照する）。
    private(set) var lastWasHitch = false

    /// 1 フレーム分を記録する（秒）。
    func record(frameDt: Double, sim: Double, sync: Double, overlay: Double) {
        let work = sim + sync + overlay
        frames += 1
        seconds += frameDt
        worstFrame = max(worstFrame, frameDt)
        worstWork = max(worstWork, work)
        simSum += sim
        syncSum += sync
        overlaySum += overlay
        frameHist[FrameStats.bucket(frameDt)] += 1
        workHist[FrameStats.bucket(work)] += 1
        lastWasHitch = frameDt > targetInterval * 1.5
        if lastWasHitch {
            hitches += 1
            hitchTime += frameDt - targetInterval
            FrameStats.signposter.emitEvent("hitch", "\(Int(frameDt * 1000)) ms work \(Int(work * 1000)) ms")
        }
    }

    func reset() {
        frameHist = [Int](repeating: 0, count: FrameStats.bucketCount)
        workHist = [Int](repeating: 0, count: FrameStats.bucketCount)
        frames = 0
        seconds = 0
        worstFrame = 0
        worstWork = 0
        hitches = 0
        hitchTime = 0
        simSum = 0
        syncSum = 0
        overlaySum = 0
    }

    func summary() -> Summary {
        let n = Double(max(1, frames))
        return Summary(
            frames: frames, seconds: seconds, targetMs: targetInterval * 1000,
            p50Ms: FrameStats.percentile(frameHist, 0.50, total: frames),
            p95Ms: FrameStats.percentile(frameHist, 0.95, total: frames),
            p99Ms: FrameStats.percentile(frameHist, 0.99, total: frames),
            maxMs: worstFrame * 1000,
            hitches: hitches, hitchMs: hitchTime * 1000,
            hitchRatio: seconds > 0 ? hitchTime * 1000 / seconds : 0,
            workP50Ms: FrameStats.percentile(workHist, 0.50, total: frames),
            workP95Ms: FrameStats.percentile(workHist, 0.95, total: frames),
            workP99Ms: FrameStats.percentile(workHist, 0.99, total: frames),
            workMaxMs: worstWork * 1000,
            simAvgMs: simSum / n * 1000, syncAvgMs: syncSum / n * 1000, overlayAvgMs: overlaySum / n * 1000)
    }

    // MARK: プレイ中の区間（Instruments の Animation Hitches と突き合わせる）

    func beginLive() {
        guard liveInterval == nil else { return }
        liveInterval = FrameStats.signposter.beginAnimationInterval("battle.live", id: FrameStats.signposter.makeSignpostID())
    }

    func endLive() {
        if let s = liveInterval { FrameStats.signposter.endInterval("battle.live", s) }
        liveInterval = nil
    }

    // MARK: 内部

    private static func bucket(_ seconds: Double) -> Int {
        min(bucketCount - 1, max(0, Int(seconds * 1000 / bucketWidth)))
    }

    private static func percentile(_ hist: [Int], _ q: Double, total: Int) -> Double {
        guard total > 0 else { return 0 }
        let rank = Int((Double(total) * q).rounded(.up))
        var acc = 0
        for (i, c) in hist.enumerated() {
            acc += c
            if acc >= rank { return Double(i + 1) * bucketWidth }
        }
        return Double(bucketCount) * bucketWidth
    }
}
