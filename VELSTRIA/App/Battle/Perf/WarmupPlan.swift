import Foundation

// 担当: battle-renderer（性能）。読み込み幕の裏で行う準備の段（BattleWorld が作り、BattleRenderer が刻んで実行する）。
//
// AAA の作り方と同じく「試合で使う可能性のあるものは、幕が上がる前にすべて一度作って一度描く」。
// 重い段（メッシュの大量生成・ヒーローの読み込みなど）は 1 フレームに 1 つ、軽い段はフレーム予算内でまとめて実行し、
// 読み込み中もロード表示のアニメーションが止まらないようにする。

struct WarmupStep {
    /// 進捗表示・計測ログ用の名前。
    let name: String
    /// 1 フレームの予算を超えうる重い段（1 フレームに 1 つだけ実行する）。
    let heavy: Bool
    let run: @MainActor () -> Void

    init(_ name: String, heavy: Bool = false, run: @escaping @MainActor () -> Void) {
        self.name = name
        self.heavy = heavy
        self.run = run
    }
}
