import Foundation

// 担当: kit-H034（docs/SKILL_KITS.md / docs/kits/Franco.md）
// 鎖鉤のゴルム用のプリミティブ: 「拘束の術者が居なくなったら suppress を解く」。
// suppress は解除不可で CC 無効も無視するため、術者の死亡・中断で確実に外す手段が要る
// （フランコの奥義は、フランコが倒される・スタンされると相手が解放される）。

extension Kit {
    /// 術者（sourceID）が掛けた suppress を、すべてのユニットから外す。術者の死亡・中断で呼ぶ。
    static func releaseSuppress(_ s: inout SimState, bySource id: EntityID) {
        for j in s.units.indices where !s.units[j].statuses.isEmpty {
            s.units[j].statuses.removeAll { $0.kind == .suppress && $0.sourceID == id }
        }
    }
}
