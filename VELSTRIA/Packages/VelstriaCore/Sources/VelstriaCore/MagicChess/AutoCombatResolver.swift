import Foundation

// 担当: core（マジックチェス）。盤面 2 つの自動戦闘を決定論的に解決する。
// 既存のヒーロー成長（HeroGrowth.baseStats）と軽減式（CombatSystem.mitigationMultiplier）を流用した
// 自己完結のミニ戦闘ループ（MOBA の毎 tick システムは使わない）。RNG は会心判定のみで、派生シードから。

/// レンダリング用のユニットスナップショット。
public struct MCCombatUnit: Codable, Hashable, Sendable {
    public var team: Int       // 0 = 自分側, 1 = 相手側
    public var heroID: String
    public var star: Int
    public var x: Double
    public var y: Double
    public var hp: Double
    public var maxHP: Double
    public var shield: Double
    public var alive: Bool
}

public struct MCCombatFrame: Codable, Sendable {
    public var units: [MCCombatUnit]
}

public struct MCCombatOutcome: Codable, Sendable {
    public var result: CombatResult
    /// 人間の戦闘のみ非空（AI 戦は省略して高速化）。
    public var frames: [MCCombatFrame]
}

public enum AutoCombatResolver {
    static let dt = 0.1
    static let maxTicks = 400          // 40 秒上限
    static let engageEpsilon = 60.0
    static let cellW = 220.0
    static let cellH = 220.0
    static let frontGap = 170.0

    /// HP 精算用（フレーム記録なし）。teamA=aID, teamB=bID。
    public static func resolve(boardA: [BoardUnit], boardB: [BoardUnit], aID: Int, bID: Int,
                               seed: UInt64, master: MasterData = .shared) -> CombatResult {
        run(boardA: boardA, boardB: boardB, aID: aID, bID: bID, seed: seed, master: master, recordFrames: false).result
    }

    /// 人間の戦闘用（フレーム記録あり）。
    public static func fight(boardA: [BoardUnit], boardB: [BoardUnit], aID: Int, bID: Int,
                             seed: UInt64, master: MasterData = .shared) -> MCCombatOutcome {
        run(boardA: boardA, boardB: boardB, aID: aID, bID: bID, seed: seed, master: master, recordFrames: true)
    }

    // MARK: - 内部

    private struct Fighter {
        let team: Int
        let heroID: String
        let star: Int
        var pos: Vec2
        var hp: Double
        let maxHP: Double
        var shield: Double
        let attack: Double
        let attackSpeed: Double
        let attackRange: Double
        let moveSpeed: Double
        let armor: Double
        let magicResist: Double
        let critChance: Double
        let critMult: Double
        let lifesteal: Double
        let damageReduction: Double
        let damageBonus: Double
        let magicDamage: Bool
        var cooldown: Double
        var targetIndex: Int?
        var alive: Bool { hp > 0 }
    }

    private static func run(boardA: [BoardUnit], boardB: [BoardUnit], aID: Int, bID: Int,
                            seed: UInt64, master: MasterData, recordFrames: Bool) -> MCCombatOutcome {
        var rng = SplitMix64(seed: seed)
        var fighters: [Fighter] = []
        fighters += build(board: boardA, team: 0, master: master)
        fighters += build(board: boardB, team: 1, master: master)

        var frames: [MCCombatFrame] = []
        if recordFrames { frames.append(snapshot(fighters)) }

        var tick = 0
        while tick < maxTicks {
            // 終了判定（どちらかが全滅）。
            let aAlive = fighters.contains { $0.team == 0 && $0.alive }
            let bAlive = fighters.contains { $0.team == 1 && $0.alive }
            if !aAlive || !bAlive { break }

            for i in fighters.indices where fighters[i].alive {
                // ターゲット（最近接の生存敵、同距離は添字昇順）。
                if fighters[i].targetIndex == nil || !(fighters[fighters[i].targetIndex!].alive) {
                    fighters[i].targetIndex = nearestEnemy(fighters, of: i)
                }
                guard let t = fighters[i].targetIndex else { continue }
                let dist = fighters[i].pos.distance(to: fighters[t].pos)
                if dist <= fighters[i].attackRange + engageEpsilon {
                    fighters[i].cooldown -= dt
                    if fighters[i].cooldown <= 0 {
                        attack(&fighters, attacker: i, target: t, rng: &rng)
                        fighters[i].cooldown += 1.0 / max(0.1, fighters[i].attackSpeed)
                    }
                } else {
                    let dir = (fighters[t].pos - fighters[i].pos).normalized
                    fighters[i].pos = fighters[i].pos + dir * (fighters[i].moveSpeed * dt)
                    if fighters[i].cooldown > 0 { fighters[i].cooldown -= dt }
                }
            }
            tick += 1
            if recordFrames { frames.append(snapshot(fighters)) }
        }

        let result = outcome(fighters, aID: aID, bID: bID)
        return MCCombatOutcome(result: result, frames: frames)
    }

    private static func nearestEnemy(_ fighters: [Fighter], of i: Int) -> Int? {
        let me = fighters[i]
        var best: Int?
        var bestDist = Double.infinity
        for j in fighters.indices where fighters[j].team != me.team && fighters[j].alive {
            let d = me.pos.distanceSquared(to: fighters[j].pos)
            if d < bestDist { bestDist = d; best = j }
        }
        return best
    }

    private static func attack(_ fighters: inout [Fighter], attacker a: Int, target t: Int, rng: inout SplitMix64) {
        var raw = fighters[a].attack
        if fighters[a].critChance > 0, rng.chance(fighters[a].critChance) { raw *= fighters[a].critMult }
        raw *= (1 + fighters[a].damageBonus)
        let type: DamageType = fighters[a].magicDamage ? .magic : .physical
        let mult = CombatSystem.mitigationMultiplier(type, armor: fighters[t].armor, magicResist: fighters[t].magicResist)
        let dr = min(Balance.maxDamageReduction, fighters[t].damageReduction)
        var dmg = max(1, raw * mult * (1 - dr))
        if fighters[t].shield > 0 {
            let absorbed = min(fighters[t].shield, dmg)
            fighters[t].shield -= absorbed
            dmg -= absorbed
        }
        fighters[t].hp -= dmg
        if fighters[a].lifesteal > 0 {
            fighters[a].hp = min(fighters[a].maxHP, fighters[a].hp + dmg * fighters[a].lifesteal)
        }
    }

    private static func outcome(_ fighters: [Fighter], aID: Int, bID: Int) -> CombatResult {
        let aAlive = fighters.filter { $0.team == 0 && $0.alive }
        let bAlive = fighters.filter { $0.team == 1 && $0.alive }
        func stars(_ f: [Fighter]) -> Int { f.reduce(0) { $0 + $1.star } }
        if aAlive.isEmpty && bAlive.isEmpty {
            return CombatResult(winner: nil, survivors: 0, survivingStars: 0)
        }
        if bAlive.isEmpty {
            return CombatResult(winner: aID, survivors: aAlive.count, survivingStars: stars(aAlive))
        }
        if aAlive.isEmpty {
            return CombatResult(winner: bID, survivors: bAlive.count, survivingStars: stars(bAlive))
        }
        // 時間切れ: 生存数 → 合計 HP の順で判定。
        if aAlive.count != bAlive.count {
            let winA = aAlive.count > bAlive.count
            let w = winA ? aAlive : bAlive
            return CombatResult(winner: winA ? aID : bID, survivors: w.count, survivingStars: stars(w))
        }
        let aHP = aAlive.reduce(0.0) { $0 + $1.hp }
        let bHP = bAlive.reduce(0.0) { $0 + $1.hp }
        if aHP == bHP { return CombatResult(winner: nil, survivors: 0, survivingStars: 0) }
        let winA = aHP > bHP
        let w = winA ? aAlive : bAlive
        return CombatResult(winner: winA ? aID : bID, survivors: w.count, survivingStars: stars(w))
    }

    private static func snapshot(_ fighters: [Fighter]) -> MCCombatFrame {
        MCCombatFrame(units: fighters.map {
            MCCombatUnit(team: $0.team, heroID: $0.heroID, star: $0.star, x: $0.pos.x, y: $0.pos.y,
                         hp: max(0, $0.hp), maxHP: $0.maxHP, shield: max(0, $0.shield), alive: $0.alive)
        })
    }

    // MARK: - 盤面 → 戦闘ユニット

    private static func build(board: [BoardUnit], team: Int, master: MasterData) -> [Fighter] {
        let tiers = MagicChessSynergy.tiers(board: board, master: master)
        func tier(_ role: Role) -> Int { tiers.first { $0.role == role }?.tier ?? 0 }
        let vanguard = tier(.vanguard), duelist = tier(.duelist), ranger = tier(.ranger)
        let arcanist = tier(.arcanist), support = tier(.support), assassin = tier(.assassin)

        var out: [Fighter] = []
        for unit in board {
            guard let cell = unit.cell, let def = master.hero(unit.heroID) else { continue }
            let st = HeroGrowth.baseStats(def: def, level: MagicChessData.level(forStar: unit.star))
            let power = MagicChessData.starPower(unit.star)
            let maxHP = st.maxHP * power
            var attack = st.attack * power
            let magic = def.role == .arcanist || def.role == .support
            var attackSpeed = st.attackSpeed
            var critChance = st.critChance
            var damageReduction = st.damageReduction
            var shield = 0.0

            // シナジー適用（簡易）。
            if vanguard > 0 { damageReduction += vanguard == 2 ? 0.20 : 0.10 }
            if duelist > 0 { attackSpeed *= duelist == 2 ? 1.30 : 1.15 }
            if ranger > 0, def.role == .ranger { attack *= ranger == 2 ? 1.25 : 1.12 }
            if arcanist > 0, def.role == .arcanist { attack *= arcanist == 2 ? 1.35 : 1.15 }
            if support > 0 { shield += maxHP * (support == 2 ? 0.30 : 0.15) }
            if assassin > 0, def.role == .assassin {
                attack *= assassin == 2 ? 1.30 : 1.15
                critChance += assassin == 2 ? 0.30 : 0.15
            }

            let x = Double(cell.col) * cellW - Double(MagicChessData.boardCols - 1) * cellW / 2
            let yMag = frontGap + Double(cell.row) * cellH
            let y = team == 0 ? -yMag : yMag
            out.append(Fighter(team: team, heroID: unit.heroID, star: unit.star,
                               pos: Vec2(x, y), hp: maxHP, maxHP: maxHP, shield: shield,
                               attack: attack, attackSpeed: attackSpeed, attackRange: st.attackRange,
                               moveSpeed: max(150, st.moveSpeed), armor: st.armor, magicResist: st.magicResist,
                               critChance: min(1, critChance), critMult: st.critMultiplier, lifesteal: st.lifesteal,
                               damageReduction: damageReduction, damageBonus: st.damageBonus, magicDamage: magic,
                               cooldown: 1.0 / max(0.1, attackSpeed)))
        }
        return out
    }
}
