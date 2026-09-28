import Foundation

// 担当: core-economy
// 死亡の一括処理: キル/アシスト判定・バウンティ・連続キル/連続死亡・告知・XP 分配・構造物/オブジェクト報酬
// （DESIGN §3, §4, §5, §8, §11）。CombatSystem が積んだ s.pendingDeaths を tick 毎に消化する。

public enum DeathSystem {
    public static func process(_ s: inout SimState, _ ctx: SimContext) {
        guard !s.pendingDeaths.isEmpty else { return }
        let deaths = s.pendingDeaths
        s.pendingDeaths.removeAll()

        // この処理より前から Core が無防備だったチーム（基部塔が既に落ちている）
        var coreExposed = [false, false]
        for u in s.units where u.kind == .tower && u.tower?.tier == .base && !u.isAlive && u.team != .neutral {
            if !deaths.contains(where: { $0.victimID == u.id }) { coreExposed[u.team.rawValue] = true }
        }
        var heroDiedOnTeam = [false, false]
        var processed: [EntityID] = []

        for d in deaths {
            guard !processed.contains(d.victimID), let v = s.index(of: d.victimID) else { continue }
            processed.append(d.victimID)
            if s.units[v].kind == .hero, s.units[v].hero?.isDead == true { continue }
            // 念のため死亡状態を確定させる（CombatSystem 以外から積まれた場合も同じ扱い）
            if s.units[v].isAlive || s.units[v].deathTime == nil {
                s.units[v].isAlive = false
                s.units[v].hp = 0
                s.units[v].deathTime = s.units[v].deathTime ?? d.time
            }
            let victim = s.units[v]
            s.emit(.unitDied(unitID: victim.id, kind: victim.kind, team: victim.team, killerID: d.killerID,
                             pos: victim.pos))
            switch victim.kind {
            case .hero:
                heroDeath(&s, ctx, victimIndex: v, killerID: d.killerID)
                if victim.team != .neutral { heroDiedOnTeam[victim.team.rawValue] = true }
            case .minion:
                minionDeath(&s, ctx, victimIndex: v, killerID: d.killerID)
            case .monster:
                monsterDeath(&s, ctx, victimIndex: v, killerID: d.killerID)
            case .tower, .core:
                structureDeath(&s, ctx, victimIndex: v, killerID: d.killerID, coreExposed: &coreExposed)
            case .dummy:
                break
            }
        }

        // 全滅（Ace）: この tick の死亡でチーム全員が倒れたら 1 回だけ告知
        for team in Team.players where heroDiedOnTeam[team.rawValue] {
            let heroes = s.heroIndices(team: team)
            guard heroes.count >= 2, heroes.allSatisfy({ !s.units[$0].isAlive }) else { continue }
            let acer = team.opponent
            guard s.teams[acer.rawValue].lastAceTime < s.time else { continue }
            s.teams[acer.rawValue].lastAceTime = s.time
            s.emit(.announcement(.ace(team: acer)))
        }
    }

    // MARK: - ヒーロー

    /// ヒーローキルのバウンティ（初キルボーナスを除く）。
    /// 被害者の連続キル s ≥ 2 で +60×(s−1)（上限 +480）、連続死亡 d ≥ 2 で −15%×(d−1)（下限 100）。
    /// d は今回の死亡を含まない（直前までの連続死亡数）。
    public static func bounty(victimKillStreak ks: Int, victimDeathStreak ds: Int) -> Double {
        var b = Balance.heroKillBounty
        if ks >= 2 {
            b += min(Balance.maxStreakBonus, Balance.streakBonusPerKill * Double(ks - 1))
        }
        if ds >= 2 {
            b *= max(0, 1 - Balance.deathStreakPenaltyPct * Double(ds - 1))
        }
        return max(Balance.minBounty, b).rounded()
    }

    /// アシスト 1 人あたりの Gold（バウンティの 50% を等分、最低 40）。
    public static func assistGold(bounty: Double, assisters n: Int) -> Double {
        guard n > 0 else { return 0 }
        return max(Balance.minAssistGold, bounty * Balance.assistBountyShare / Double(n)).rounded()
    }

    /// ヒーローキルの XP（100 + 30 × 被害者Lv）。
    public static func heroKillXP(victimLevel: Int) -> Double {
        Balance.Economy.heroKillXPBase + Balance.Economy.heroKillXPPerLevel * Double(victimLevel)
    }

    /// キルの帰属先（ヒーロー添字）。止めがヒーローならそのヒーロー、
    /// ミニオン/タワー/モンスター/泉などなら 10 秒以内に最後にダメージを与えた敵ヒーロー。該当なしは nil（処刑）。
    public static func creditedKiller(_ s: SimState, victimIndex v: Int, killerID: EntityID?) -> Int? {
        let victimTeam = s.units[v].team
        if let k = s.index(of: killerID), k != v, s.units[k].kind == .hero, s.units[k].team != victimTeam {
            return k
        }
        guard let h = s.units[v].hero else { return nil }
        var best: Int?
        var bestTime = -Double.infinity
        for rec in h.recentDamagers where s.time - rec.time <= Balance.assistWindow {
            guard let k = s.index(of: rec.sourceID), k != v, s.units[k].kind == .hero,
                  s.units[k].team != victimTeam, s.units[k].team != .neutral else { continue }
            // 同時刻は後に記録された方を優先
            if rec.time >= bestTime {
                bestTime = rec.time
                best = k
            }
        }
        return best
    }

    /// アシスト（ヒーロー添字、ID 昇順）。DESIGN §5:
    /// 10 秒以内に被害者へダメージ/CC を与えた敵ヒーロー + キラーを回復/シールドしたヒーロー
    /// + 被害者に攻撃されていた味方を回復/シールドしたヒーロー。キラー本人は除く。
    public static func assisters(_ s: SimState, victimIndex v: Int, killerIndex k: Int) -> [Int] {
        let window = Balance.assistWindow
        let killerTeam = s.units[k].team
        let victimID = s.units[v].id
        var ids: [EntityID] = []
        func add(_ id: EntityID) {
            guard id != s.units[k].id, !ids.contains(id), let a = s.index(of: id),
                  s.units[a].kind == .hero, s.units[a].team == killerTeam else { return }
            ids.append(id)
        }
        for rec in s.units[v].hero?.recentDamagers ?? [] where s.time - rec.time <= window {
            add(rec.sourceID)
        }
        for rec in s.units[k].hero?.recentSupporters ?? [] where s.time - rec.time <= window {
            add(rec.sourceID)
        }
        for a in s.heroIndices(team: killerTeam) where a != k {
            guard let ah = s.units[a].hero,
                  ah.recentDamagers.contains(where: { $0.sourceID == victimID && s.time - $0.time <= window })
            else { continue }
            for rec in ah.recentSupporters where s.time - rec.time <= window { add(rec.sourceID) }
        }
        ids.sort()
        return ids.compactMap { s.index(of: $0) }
    }

    static func heroDeath(_ s: inout SimState, _ ctx: SimContext, victimIndex v: Int, killerID: EntityID?) {
        guard let vh = s.units[v].hero else { return }
        let now = s.time
        let victimPos = s.units[v].pos
        let victimID = s.units[v].id
        let killer = creditedKiller(s, victimIndex: v, killerID: killerID)
        let assistIdx = killer.map { assisters(s, victimIndex: v, killerIndex: $0) } ?? []

        // 被害者の状態を死亡へ
        if let ch = vh.channel {
            s.emit(.channelCanceled(heroID: victimID, kind: ch.kind))
        }
        s.units[v].hero!.respawnTimer = RespawnSystem.respawnTime(level: vh.level, time: now)
        s.units[v].hero!.channel = nil
        s.units[v].hero!.empoweredAttack = nil
        s.units[v].hero!.score.deaths += 1
        s.units[v].hero!.killStreak = 0
        s.units[v].hero!.deathStreak += 1
        s.units[v].hero!.multiKillCount = 0
        s.units[v].hero!.recentDamagers.removeAll()
        s.units[v].hero!.recentSupporters.removeAll()
        s.units[v].attackTargetID = nil
        s.units[v].moveIntent = .none
        s.units[v].path = []
        s.units[v].windupRemaining = nil
        s.units[v].displacement = nil
        s.units[v].statuses.removeAll()
        s.units[v].shields.removeAll()

        guard let k = killer else {
            // 処刑（敵ヒーローの関与なし）: 報酬なし。killerID = nil の heroKilled で HUD が「処刑」を表示する。
            s.emit(.heroKilled(HeroKillEvent(victimID: victimID, killerID: nil, assistIDs: [], bounty: 0,
                                             isFirstBlood: false, multiKill: 0, killerStreak: 0, isShutdown: false)))
            return
        }
        let killerID = s.units[k].id
        let killerTeam = s.units[k].team

        // バウンティ
        let base = bounty(victimKillStreak: vh.killStreak, victimDeathStreak: vh.deathStreak)
        let isFirstBlood = !s.firstBloodTaken
        s.firstBloodTaken = true
        let isShutdown = vh.killStreak >= Balance.Economy.shutdownStreak

        // キラーの連続キル・マルチキル
        var kh = s.units[k].hero!
        kh.killStreak += 1
        kh.deathStreak = 0
        kh.multiKillCount = now - kh.lastKillTime <= Balance.Economy.multiKillWindow ? kh.multiKillCount + 1 : 1
        kh.lastKillTime = now
        kh.score.kills += 1
        kh.score.largestKillStreak = max(kh.score.largestKillStreak, kh.killStreak)
        let multi = min(Balance.Economy.maxMultiKill, kh.multiKillCount)
        kh.score.largestMultiKill = max(kh.score.largestMultiKill, multi)
        s.units[k].hero = kh
        if killerTeam != .neutral { s.teams[killerTeam.rawValue].kills += 1 }

        let assistIDs = assistIDsOf(s, assistIdx)
        s.emit(.heroKilled(HeroKillEvent(victimID: victimID, killerID: killerID, assistIDs: assistIDs,
                                         bounty: base, isFirstBlood: isFirstBlood, multiKill: multi,
                                         killerStreak: kh.killStreak, isShutdown: isShutdown)))

        // Gold
        EconomyRewards.grantGold(&s, heroIndex: k, amount: base + (isFirstBlood ? Balance.firstBloodBonus : 0),
                                 at: victimPos)
        let perAssist = assistGold(bounty: base, assisters: assistIdx.count)
        for a in assistIdx {
            s.units[a].hero!.score.assists += 1
            EconomyRewards.grantGold(&s, heroIndex: a, amount: perAssist, at: victimPos)
        }

        // XP: キラー 100%、1400 以内のアシストで 60% を等分
        let xp = heroKillXP(victimLevel: vh.level)
        HeroGrowth.grantXP(&s, ctx, heroIndex: k, amount: xp)
        let r2 = Balance.xpShareRadius * Balance.xpShareRadius
        let nearAssists = assistIdx.filter {
            s.units[$0].isAlive && s.units[$0].pos.distanceSquared(to: victimPos) <= r2
        }
        if !nearAssists.isEmpty {
            let each = xp * Balance.Economy.assistXPShare / Double(nearAssists.count)
            for a in nearAssists { HeroGrowth.grantXP(&s, ctx, heroIndex: a, amount: each) }
        }

        // 告知
        if isFirstBlood {
            s.emit(.announcement(.firstBlood(killerID: killerID, victimID: victimID)))
        }
        if isShutdown {
            s.emit(.announcement(.shutdown(killerID: killerID, victimID: victimID)))
        }
        // ダブル〜ペンタのみ告知（ペンタ後に復活した敵を 10 秒以内に倒してもペンタを繰り返さない）
        if (2...Balance.Economy.maxMultiKill).contains(kh.multiKillCount) {
            s.emit(.announcement(.multiKill(killerID: killerID, count: multi)))
        }
        if Balance.Economy.killingSpreeStreaks.contains(kh.killStreak) {
            s.emit(.announcement(.killingSpree(killerID: killerID, streak: kh.killStreak)))
        }

        // パッシブ（アサシンの CD 短縮など）
        PassiveHooks.onKillOrAssist(&s, ctx, hero: k, victim: v)
        for a in assistIdx { PassiveHooks.onKillOrAssist(&s, ctx, hero: a, victim: v) }
    }

    static func assistIDsOf(_ s: SimState, _ idx: [Int]) -> [EntityID] { idx.map { s.units[$0].id } }

    // MARK: - ミニオン

    static func minionDeath(_ s: inout SimState, _ ctx: SimContext, victimIndex v: Int, killerID: EntityID?) {
        guard let m = s.units[v].minion else { return }
        let pos = s.units[v].pos
        // Gold はヒーローのラストヒットのみ
        if let k = s.index(of: killerID), s.units[k].kind == .hero, s.units[k].team != s.units[v].team {
            s.units[k].hero?.score.minionKills += 1
            EconomyRewards.grantGold(&s, heroIndex: k, amount: Balance.Economy.minionGold(m.type), at: pos)
        }
        // XP は周囲の敵ヒーローで分配（止めを刺したのがミニオンでも入る）
        HeroGrowth.shareXP(&s, ctx, team: s.units[v].team.opponent, around: pos,
                           amount: Balance.Economy.minionXP(m.type))
    }

    // MARK: - 中立モンスター

    static func monsterDeath(_ s: inout SimState, _ ctx: SimContext, victimIndex v: Int, killerID: EntityID?) {
        guard let md = s.units[v].monster else { return }
        let pos = s.units[v].pos
        // 止めを刺したユニットが既に除去されていれば、最後に攻撃したユニットのチームに帰属
        guard let k = s.index(of: killerID) ?? s.index(of: s.units[v].lastAttackerID) else { return }
        let team = s.units[k].team
        guard team != .neutral else { return }
        let killerHero: Int? = s.units[k].kind == .hero ? k : nil

        // ラストヒット Gold（Jungle 装備で +20%）
        if let kh = killerHero {
            s.units[kh].hero?.score.monsterKills += 1
            let gold = Balance.Economy.monsterGold(md.kind)
            if gold > 0 {
                let bonus = max(0, s.units[kh].stats.monsterGoldBonus)
                EconomyRewards.grantGold(&s, heroIndex: kh, amount: (gold * (1 + bonus)).rounded(), at: pos)
            }
        }

        switch md.kind {
        case .campLarge, .campSmall:
            HeroGrowth.shareXP(&s, ctx, team: team, around: pos, amount: Balance.Economy.monsterXP(md.kind))
        case .blueSentinel, .redSentinel:
            HeroGrowth.shareXP(&s, ctx, team: team, around: pos, amount: Balance.Economy.monsterXP(md.kind))
            if let kh = killerHero {
                s.units[kh].hero?.score.objectivesTaken += 1
                let kind: StatusKind = md.kind == .blueSentinel ? .blueBuff : .redBuff
                let d = Balance.Economy.sentinelBuffDuration
                CombatSystem.addStatus(&s, targetIndex: kh,
                                       StatusEffect(kind: kind, duration: d, sourceID: s.units[v].id, tag: "sentinel"))
            }
            s.emit(.objectiveTaken(kind: md.kind, team: team, killerID: killerID))
        case .astralWyrm:
            s.teams[team.rawValue].wyrmKills += 1
            if let kh = killerHero { s.units[kh].hero?.score.objectivesTaken += 1 }
            teamObjectiveReward(&s, ctx, team: team, gold: Balance.Economy.wyrmTeamGold,
                                xp: Balance.Economy.wyrmTeamXP,
                                blessing: StatusEffect(kind: .wyrmBlessing, duration: Balance.Economy.wyrmBlessingDuration,
                                                       magnitude: Balance.Economy.wyrmBlessingDamageBonus,
                                                       sourceID: s.units[v].id, tag: "wyrm"))
            s.emit(.objectiveTaken(kind: md.kind, team: team, killerID: killerID))
            s.emit(.announcement(.wyrmSlain(team: team)))
        case .ancientColossus:
            s.teams[team.rawValue].colossusKills += 1
            if let kh = killerHero { s.units[kh].hero?.score.objectivesTaken += 1 }
            teamObjectiveReward(&s, ctx, team: team, gold: Balance.Economy.colossusTeamGold,
                                xp: Balance.Economy.colossusTeamXP,
                                blessing: StatusEffect(kind: .colossusBlessing,
                                                       duration: Balance.Economy.colossusBlessingDuration,
                                                       magnitude: Balance.Economy.colossusBlessingDamageBonus,
                                                       sourceID: s.units[v].id, tag: "colossus"))
            s.emit(.objectiveTaken(kind: md.kind, team: team, killerID: killerID))
            s.emit(.announcement(.colossusSlain(team: team)))
        }
    }

    /// ボス報酬: チーム全員に Gold/XP、生存者に加護。
    static func teamObjectiveReward(_ s: inout SimState, _ ctx: SimContext, team: Team, gold: Double, xp: Double,
                                    blessing: StatusEffect) {
        for i in s.heroIndices(team: team) {
            EconomyRewards.grantGold(&s, heroIndex: i, amount: gold)
            HeroGrowth.grantXP(&s, ctx, heroIndex: i, amount: xp)
            if s.units[i].isAlive, s.units[i].hero?.isDead == false {
                CombatSystem.addStatus(&s, targetIndex: i, blessing)
            }
        }
    }

    // MARK: - 構造物

    static func structureDeath(_ s: inout SimState, _ ctx: SimContext, victimIndex v: Int, killerID: EntityID?,
                               coreExposed: inout [Bool]) {
        let victim = s.units[v]
        s.emit(.structureDestroyed(unitID: victim.id, kind: victim.kind, team: victim.team,
                                   lane: victim.tower?.lane, tier: victim.tower?.tier, killerID: killerID))
        // Core は勝敗処理（MatchFlowSystem）のみ
        guard victim.kind == .tower, victim.team != .neutral else { return }
        let destroyer = victim.team.opponent
        s.teams[destroyer.rawValue].towersDestroyed += 1

        if let k = s.index(of: killerID), s.units[k].kind == .hero, s.units[k].team == destroyer {
            s.units[k].hero?.score.towersDestroyed += 1
            EconomyRewards.grantGold(&s, heroIndex: k, amount: Balance.towerLastHitGold, at: victim.pos)
        }
        EconomyRewards.grantTeamGold(&s, team: destroyer, amount: Balance.towerTeamGold)

        let tier = victim.tower?.tier ?? .outer
        s.emit(.announcement(.towerDestroyed(team: victim.team, lane: victim.tower?.lane, tier: tier)))
        if tier == .base, !coreExposed[victim.team.rawValue] {
            coreExposed[victim.team.rawValue] = true
            s.emit(.announcement(.coreVulnerable(team: victim.team)))
        }
    }
}
