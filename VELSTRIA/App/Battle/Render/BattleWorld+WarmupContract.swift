import Foundation

// 担当: battle-renderer（性能）。ウォームアップ契約の仮実装 — stream A replaces this。
//
// BattleRenderer（WarmupScheduler）は makeWarmupPlan() の段をすべて実行し、幕を上げる直前に finishWarmup() を呼ぶ。
// 本実装（ウォームアップ用の仮表示の片付けなど）は stream A が BattleWorld.swift に入れる。
// その変更が入ったら、このファイルは削除すること（同名のメソッドが二重定義になる）。

extension BattleWorld {
    /// 幕を上げる直前に呼ばれる（仮実装: 何もしない。stream A replaces this）。
    func finishWarmup() {}
}
