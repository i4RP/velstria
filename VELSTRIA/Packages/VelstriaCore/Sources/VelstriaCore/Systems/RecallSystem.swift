import Foundation

// 担当: core-economy（最小実装。巨像の加護中の短縮・帰還門の転移先検証を実装すること）

public enum RecallSystem {
    public static func startRecall(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int) {
        guard s.units[i].isAlive, s.units[i].hero?.channel == nil else { return }
        let duration = Balance.recallChannel
        let fountain = ctx.map.fountain(s.units[i].team)
        s.units[i].hero?.channel = Channel(kind: .recall, duration: duration, target: fountain)
        s.units[i].moveIntent = .none
        s.units[i].attackTargetID = nil
        s.emit(.channelStarted(heroID: s.units[i].id, kind: .recall, duration: duration))
    }

    /// 帰還門（BS09）の詠唱開始。SpellSystem から呼ばれる。
    public static func startTeleport(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, destination: Vec2,
                                     duration: Double) {
        guard s.units[i].isAlive else { return }
        s.units[i].hero?.channel = Channel(kind: .teleport, duration: duration, target: destination)
        s.units[i].moveIntent = .none
        s.units[i].attackTargetID = nil
        s.emit(.channelStarted(heroID: s.units[i].id, kind: .teleport, duration: duration))
    }

    /// 詠唱中なら中断（移動・攻撃・スキル・被ダメで呼ばれる）。
    public static func cancelChannel(_ s: inout SimState, _ i: Int) {
        guard let ch = s.units[i].hero?.channel else { return }
        s.units[i].hero?.channel = nil
        s.emit(.channelCanceled(heroID: s.units[i].id, kind: ch.kind))
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        for i in s.units.indices where s.units[i].kind == .hero {
            guard var ch = s.units[i].hero?.channel else { continue }
            if !s.units[i].isAlive { s.units[i].hero?.channel = nil; continue }
            if s.units[i].lastDamagedTime >= s.time - Balance.dt * 0.5 {
                cancelChannel(&s, i)
                continue
            }
            ch.remaining -= Balance.dt
            if ch.remaining <= 0 {
                let dest = ch.target ?? ctx.map.fountain(s.units[i].team)
                s.units[i].hero?.channel = nil
                s.units[i].pos = dest
                s.units[i].prevPos = dest
                s.units[i].moveIntent = .none
                s.emit(.channelCompleted(heroID: s.units[i].id, kind: ch.kind, destination: dest))
            } else {
                s.units[i].hero?.channel = ch
            }
        }
    }
}
