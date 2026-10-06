import Foundation
import VelstriaCore

// 担当: online。ホスト側の観戦配信の記録（遅延キュー・キーフレームの輪・連続したフレームの記録）。
// 接続は持たず、「いま観戦者へ出してよい範囲」と「途中参加・再同期の基準」を答えるだけ（OnlineSession が送る）。
//
// - 記録: ホストが進めた tick の入力（空の tick も含む連続した列。ReplayRecorder は空の tick を省くので使えない）を
//   すべて残し、keyframeInterval 毎に SimState を写す（値型なので写しは軽い。変化した配列だけ後で複製される）。
// - 公開: 観戦者へ出してよいのは「ホストの現在 tick − 遅延」まで（releasedTick）。試合が終わったら遅延は要らないので
//   残りをすべて公開する（finish）。
// - 基準: 途中参加・再同期は「公開済みの範囲で最新のキーフレーム」から（生の状態は渡さない）。キーフレームがまだ
//   公開範囲に無ければ tick 0（構成から誰でも作れるので状態を送らない）。
// - 保持: 基準より古いキーフレームと記録は捨てる（遅延 + キーフレーム間隔ぶんだけ残る）。

struct OnlineSpectatorRelay {
    /// 記録している（観戦を許可した部屋の試合中）。
    private(set) var isActive = false
    /// 観戦者への遅延（tick）。
    private(set) var delayTicks = 0
    private(set) var keyframeInterval = OnlineProtocol.spectatorKeyframeInterval
    /// ホストが進めた最後の tick。
    private(set) var liveTick = 0
    /// 観戦者へ出してよい最後の tick。
    private(set) var releasedTick = 0
    /// 試合が終わった tick（終わるまで nil）。中断でも同じ（観戦者は最後の tick まで遅れて見て、自然に終わっていなければ中断として終える）。
    private(set) var finalTick: Int?

    /// 記録した入力（tick = logFirstTick + 添字。連続）。
    private var log: [ReplayFrame] = []
    private var logFirstTick = 1
    /// キーフレーム（tick 昇順）。
    private var keyframes: [SimState] = []

    init() {}

    /// 試合の開始時に呼ぶ。active = false なら何も記録しない（観戦を許可していない部屋）。
    mutating func reset(active: Bool, delayTicks: Int, keyframeInterval: Int) {
        self = OnlineSpectatorRelay()
        isActive = active
        self.delayTicks = max(0, delayTicks)
        self.keyframeInterval = max(1, keyframeInterval)
    }

    /// ホストが 1 tick 進めた。state はキーフレームを取る tick だけ評価する（nil なら取らない）。
    mutating func record(_ frame: ReplayFrame, state: () -> SimState?) {
        guard isActive, finalTick == nil else { return }
        guard frame.tick > liveTick else { return }   // 重複（起こらないはず）
        if frame.tick != liveTick + 1 {
            // 連続していない（起こらないはず）: ここを起点にやり直す。古い基準を持つ観戦者は記録が無いので再同期になる
            keyframes = state().map { [$0] } ?? []
            log.removeAll()
            logFirstTick = frame.tick + 1
            liveTick = frame.tick
            return
        }
        if log.isEmpty { logFirstTick = frame.tick }
        log.append(frame)
        liveTick = frame.tick
        if frame.tick % keyframeInterval == 0, let s = state() { keyframes.append(s) }
    }

    /// 遅延を過ぎた分を公開する。公開範囲が伸びたら true。
    @discardableResult
    mutating func release() -> Bool {
        guard isActive else { return false }
        let target = finalTick != nil ? liveTick : max(0, liveTick - delayTicks)
        guard target > releasedTick else { return false }
        releasedTick = target
        return true
    }

    /// 試合が終わった（自然な終了・中断）。もう動かないので遅延は要らない: 残りをすべて公開する。
    mutating func finish() {
        guard isActive, finalTick == nil else { return }
        finalTick = liveTick
        releasedTick = liveTick
    }

    /// 途中参加・再同期の基準（公開済みの範囲で最新のキーフレーム）。nil = tick 0（構成から作る）。
    var baseState: SimState? { keyframes.last { $0.tick <= releasedTick } }
    var baseTick: Int { baseState?.tick ?? 0 }

    /// (after, through] の記録。記録がもう無い（捨てた・やり直した）なら nil。
    func frames(after: Int, through: Int) -> [ReplayFrame]? {
        guard through > after else { return [] }
        let start = after + 1 - logFirstTick
        let end = through - logFirstTick
        guard start >= 0, end < log.count else { return nil }
        return Array(log[start...end])
    }

    /// 要らなくなった記録を捨てる。pinnedTick: 基準を符号化中の観戦者の基準（その先の記録は残す）。
    mutating func trim(pinnedTick: Int?) {
        // 公開範囲で最新のキーフレームより古いキーフレームは基準にならない
        while keyframes.count >= 2, keyframes[1].tick <= releasedTick { keyframes.removeFirst() }
        let base = baseTick
        let keepAfter = min(base, pinnedTick ?? base)
        let drop = keepAfter + 1 - logFirstTick
        // 毎回詰めると O(n) が続くので、ある程度溜まってからまとめて捨てる
        guard drop >= 2 * keyframeInterval || (drop > 0 && drop >= log.count) else { return }
        let n = min(drop, log.count)
        log.removeFirst(n)
        logFirstTick += n
    }

    /// テスト・表示用: 保持している記録とキーフレームの数。
    var retainedFrameCount: Int { log.count }
    var retainedKeyframeTicks: [Int] { keyframes.map(\.tick) }
}
