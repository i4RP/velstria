import Foundation

// 担当: kit-H032（docs/SKILL_KITS.md / docs/kits/Dyrroth.md）
// 赤拳のディアス用のプリミティブ:
//   hitAreaEach     — 範囲内の敵へ「対象ごとに内容が違う」命中を与える（ミニオンへの減衰・失った HP の加算・円の除外）
//   firstBlocker    — 突進の進路で最初に当たる敵（ヒーロー・ミニオン・モンスター）。そこで止まる突進に使う

extension Kit {
    /// 範囲（扇・円・線）内の敵（構造物を除く）に、対象ごとに作った payload を適用する。
    /// 対象を先に確定し、payload も全員ぶん先に作ってから、添字昇順に適用する（命中中のノックバック・死亡で判定が変わらない）。
    /// excluding の対象は除く（主対象に別の内容を与える円の通常攻撃など）。戻り値 = 命中させた対象の添字（昇順）。
    @discardableResult
    static func hitAreaEach(_ s: inout SimState, _ ctx: SimContext, caster i: Int, center: Vec2, radius: Double,
                            shape: ZoneShape, excluding: Int? = nil, from: Vec2? = nil,
                            payload: (SimState, Int) -> HitPayload) -> [Int] {
        let team = s.units[i].team
        var hits: [(index: Int, payload: HitPayload)] = []
        for j in s.units.indices where j != excluding && s.units[j].team != team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j) else { continue }
            guard ZoneSystem.contains(shape: shape, center: center, radius: radius, point: s.units[j].pos,
                                      pointRadius: s.units[j].radius) else { continue }
            let p = payload(s, j)
            if p.heroesOnly && s.units[j].kind != .hero { continue }
            hits.append((j, p))
        }
        guard !hits.isEmpty else { return [] }
        let casterID = s.units[i].id
        for h in hits {
            CombatSystem.applyHit(&s, ctx, sourceID: casterID, team: team, targetIndex: h.index, payload: h.payload,
                                  from: from ?? center)
        }
        return hits.map(\.index)
    }

    /// 術者の位置から direction へ延びる進路（幅 = width の半幅）で、最初に当たる敵と、その敵に接するまでの突進距離。
    /// 構造物・対象不可・死亡中は除く。突進が届く距離（maxDistance）より遠い敵は無視する。
    static func firstBlocker(_ s: SimState, caster i: Int, direction: Vec2, maxDistance: Double, width: Double,
                             contactGap: Double = 5) -> (index: Int, distance: Double)? {
        let dir = direction.normalized
        guard dir != .zero else { return nil }
        let team = s.units[i].team
        let origin = s.units[i].pos
        var best: (index: Int, distance: Double)?
        for j in s.units.indices where s.units[j].team != team && !s.units[j].isStructure {
            guard CombatSystem.isLiving(s, j), !s.units[j].has(.untargetable) else { continue }
            let rel = s.units[j].pos - origin
            let along = rel.dot(dir)
            guard along > 0 else { continue }
            let lateral = abs(rel.x * dir.y - rel.y * dir.x)
            guard lateral <= width + s.units[j].radius else { continue }
            // 術者と対象の半径が接する位置まで進む（中心が重ならない）
            let stop = max(0, along - s.units[i].radius - s.units[j].radius - contactGap)
            guard stop <= maxDistance else { continue }
            if best == nil || stop < best!.distance || (stop == best!.distance && j < best!.index) {
                best = (j, stop)
            }
        }
        return best
    }
}
