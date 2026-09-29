import Foundation

// 担当: core-world。中立モンスターの行動（巣で待機・最後の攻撃者へ反撃・追跡・リーシュ帰還・リセット）。
// 出現・再出現は SpawnSystem、撃破報酬は DeathSystem。
// リーシュ: 巣からリーシュ半径（通常 900 / ボス 700）を超えたら、被ダメ無効・CC 無効のまま巣へ歩いて戻り、
// 到着で全回復する。攻撃者が倒れた・居なくなった場合も同じ手順でリセットする。

public enum MonsterSystem {
    /// 帰還中の被ダメ無効・CC 無効ステータスのタグ。
    static let leashTag = "monster_leash"

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        // キャンプ毎の生存メンバー（添字昇順）
        var members = [[Int]](repeating: [], count: ctx.map.camps.count)
        for i in s.units.indices where s.units[i].kind == .monster && s.units[i].isAlive {
            if let c = s.units[i].monster?.campID, c >= 0, c < members.count { members[c].append(i) }
        }
        for i in s.units.indices where s.units[i].kind == .monster && s.units[i].isAlive {
            guard let m = s.units[i].monster else { continue }
            let profile = UnitFactory.monsterProfile(m.kind)
            if m.leashing {
                returnHome(&s, ctx, i, home: m.home)
                continue
            }
            let fromHome = s.units[i].pos.distance(to: m.home)
            if fromHome > profile.leashRadius {
                startLeash(&s, ctx, i)
                returnHome(&s, ctx, i, home: m.home)
                continue
            }
            let mates = m.campID >= 0 && m.campID < members.count ? members[m.campID] : []
            if let t = aggroTarget(s, i, campmates: mates, home: m.home, leash: profile.leashRadius) {
                engage(&s, i, t)
            } else if s.units[i].attackTargetID != nil || fromHome > Balance.monsterHomeTolerance
                        || s.units[i].hp < s.units[i].stats.maxHP {
                // 攻撃者が倒れた・遠くへ離れた: リセットして巣へ戻る
                startLeash(&s, ctx, i)
                returnHome(&s, ctx, i, home: m.home)
            } else {
                s.units[i].moveIntent = .none
            }
        }
    }

    /// 反撃対象: 自分の最後の攻撃者 > 交戦中の相手 > 同じキャンプの仲間の最後の攻撃者（最も新しい被ダメ）。
    /// 交戦中の相手を残すのは、発生源の無いダメージ（環境・持続ダメージ等）で lastAttackerID が
    /// 失われても戦闘中にリセット（全回復）しないため。
    static func aggroTarget(_ s: SimState, _ i: Int, campmates: [Int], home: Vec2, leash: Double) -> Int? {
        if let a = validAttacker(s, s.units[i].lastAttackerID, home: home, leash: leash) { return a }
        if let a = validAttacker(s, s.units[i].attackTargetID, home: home, leash: leash) { return a }
        var best: Int?
        var bestTime = -Double.infinity
        for j in campmates where j != i {
            guard s.units[j].monster?.leashing == false, s.units[j].lastDamagedTime > bestTime,
                  let a = validAttacker(s, s.units[j].lastAttackerID, home: home, leash: leash) else { continue }
            bestTime = s.units[j].lastDamagedTime
            best = a
        }
        return best
    }

    /// 反撃可能な攻撃者か（生存・中立以外・巣の近く）。
    static func validAttacker(_ s: SimState, _ id: EntityID?, home: Vec2, leash: Double) -> Int? {
        guard let a = s.index(of: id), s.units[a].isAlive, s.units[a].team != .neutral,
              s.units[a].hero?.isDead != true else { return nil }
        let r = leash + Balance.monsterAggroExtraRange
        guard s.units[a].pos.distanceSquared(to: home) <= r * r else { return nil }
        return a
    }

    static func engage(_ s: inout SimState, _ i: Int, _ t: Int) {
        let id = s.units[t].id
        if s.units[i].attackTargetID != id {
            s.units[i].attackTargetID = id
            s.units[i].windupRemaining = nil
        }
        // CombatSystem はモンスターの追跡を設定しないため、ここで射程まで追う
        s.units[i].moveIntent = .follow(targetID: id, range: s.units[i].stats.attackRange)
    }

    /// リセット開始: 対象を捨て、受けている弱体・CC を解除し、帰還中は被ダメ無効・CC 無効。
    static func startLeash(_ s: inout SimState, _ ctx: SimContext, _ i: Int) {
        s.units[i].monster?.leashing = true
        s.units[i].attackTargetID = nil
        s.units[i].windupRemaining = nil
        s.units[i].lastAttackerID = nil
        s.units[i].path = []
        s.units[i].statuses.removeAll { $0.kind.isCleansable || $0.kind == .airborne }
        refreshLeashProtection(&s, i)
        s.emit(.statusApplied(targetID: s.units[i].id, kind: .invulnerable, duration: 1))
    }

    /// 帰還中の被ダメ無効・CC 無効を 1 秒延長する（毎 tick 呼ぶので帰還中は切れない）。
    static func refreshLeashProtection(_ s: inout SimState, _ i: Int) {
        for kind in [StatusKind.invulnerable, .ccImmune] {
            if let k = s.units[i].statuses.firstIndex(where: { $0.kind == kind && $0.tag == leashTag }) {
                s.units[i].statuses[k].remaining = 1
            } else {
                s.units[i].statuses.append(StatusEffect(kind: kind, duration: 1, tag: leashTag))
            }
        }
    }

    /// 巣へ歩く。到着したら全回復して待機に戻る。
    static func returnHome(_ s: inout SimState, _ ctx: SimContext, _ i: Int, home: Vec2) {
        refreshLeashProtection(&s, i)
        s.units[i].attackTargetID = nil
        let pos = s.units[i].pos
        if pos.distance(to: home) > Balance.monsterHomeTolerance {
            s.units[i].moveIntent = .point(WorldSteering.nextWaypoint(ctx, from: pos, to: home, radius: s.units[i].radius))
            return
        }
        let healed = s.units[i].stats.maxHP - s.units[i].hp
        s.units[i].hp = s.units[i].stats.maxHP
        s.units[i].statuses.removeAll { $0.tag == leashTag || $0.kind.isCleansable }
        s.units[i].monster?.leashing = false
        s.units[i].lastAttackerID = nil
        s.units[i].moveIntent = .none
        s.units[i].path = []
        if healed > 0 { s.emit(.heal(targetID: s.units[i].id, sourceID: nil, amount: healed)) }
    }
}
