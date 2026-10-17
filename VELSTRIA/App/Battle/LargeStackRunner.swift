import Foundation

/// sim をメインスレッド外で進めるための、スタックの大きい専用スレッド（1 本、直列）。
/// 協調スレッドプール（Task）のスタックは 512 KB しかなく、Debug ビルドの sim（アイテム効果 → 追加ダメージ → 連撃など）は
/// 20 段ほどで溢れて落ちる（観戦の事前計算・シークで発生）。ここでは 16 MB のスレッドで実行し、呼び出し側は終わるまで待つ。
final class LargeStackRunner: @unchecked Sendable {
    static let shared = LargeStackRunner()
    private static let threadName = "velstria.sim-large-stack"

    private let condition = NSCondition()
    private var jobs: [(work: () -> Void, done: DispatchSemaphore)] = []

    private init() {
        let t = Thread { [unowned self] in self.loop() }
        t.stackSize = 16 << 20
        t.name = Self.threadName
        t.qualityOfService = .userInitiated
        t.start()
    }

    private func loop() {
        while true {
            condition.lock()
            while jobs.isEmpty { condition.wait() }
            var job: (() -> Void)? = jobs[0].work
            let done = jobs.removeFirst().done
            condition.unlock()
            job?()
            // Release the nonescaping body before allowing withoutActuallyEscaping to return.
            job = nil
            done.signal()
        }
    }

    /// body を専用スレッドで実行して結果を返す（終わるまで呼び出し側を止める。専用スレッドの中から呼んだらその場で実行）。
    func run<T>(_ body: () -> T) -> T {
        if Thread.current.name == Self.threadName { return body() }
        return withoutActuallyEscaping(body) { escapable in
            var result: T?
            let done = DispatchSemaphore(value: 0)
            condition.lock()
            jobs.append((work: {
                result = escapable()
            }, done: done))
            condition.signal()
            condition.unlock()
            done.wait()
            return result!
        }
    }
}
