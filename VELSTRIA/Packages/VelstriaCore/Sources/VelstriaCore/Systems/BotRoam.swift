import Foundation

// 担当: core-bots
// サポート（ローム靴の役）の動き: レーンでキャリーに張り付かず、生きているジャングラーの近くに付いて回る。
// 参照仕様では Roam はミニオンの報酬を共有せず、味方のファームを奪わずに動き回る役（OBJ-008）。
// キャリーがレーンを 1 人で受け持てるようになり、ジャングラー（序盤の Gold/XP が突出する）の XP は付き添いと分け合い、
// ガンク・オブジェクトの局面で人数が揃う。戦闘・帰還・集団行動（BotMacro のプラン）は通常どおり優先される。

enum BotRoam {
    /// これより近ければその場で待つ（ジャングラーの狩りを邪魔しない）。
    static let followDistance: Double = 700
    /// これより遠いジャングラーには付いて行かず、レーンへ戻る。
    static let maxFollowDistance: Double = 3600

    /// 付いて回る相手: 生存・泉の外・追える距離にいる味方のジャングラー。
    static func partner(_ s: SimState, _ ctx: SimContext, _ w: BotWorld, _ a: BotAgent) -> Int? {
        var best: Int?
        var bestD = maxFollowDistance * maxFollowDistance
        for h in w.heroes where s.units[h].team == a.team && s.units[h].hero?.position == .jungle {
            guard s.units[h].isAlive, s.units[h].hero?.isDead == false,
                  !ctx.map.isInFountain(s.units[h].pos, team: a.team) else { continue }
            let d = s.units[h].pos.distanceSquared(to: a.pos)
            if d < bestD {
                bestD = d
                best = h
            }
        }
        return best
    }

    /// 付き添いの行動を取れたら true（取れなければ呼び出し側がレーン戦に回す）。
    static func follow(_ s: inout SimState, _ ctx: SimContext, _ w: BotWorld, _ a: inout BotAgent,
                       _ mem: inout BotHeroMemory) -> Bool {
        guard let p = partner(s, ctx, w, a) else { return false }
        BotAI.setGoal(&mem, .roaming, s.time)
        let target = s.units[p].pos
        if a.pos.distance(to: target) > followDistance {
            // 相手の自陣側（泉の方向）に少し寄った点へ向かう（敵側へ先に踏み込まない）
            let back = (ctx.map.fountain(a.team) - target).normalized * 350
            BotAI.move(s, ctx, &a, &mem, to: target + back)
        } else {
            BotAI.stop(s, &a)
        }
        return true
    }
}
