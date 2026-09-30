import Foundation

// 担当: core-bots
// AI のドラフト（ピック / BAN）。ランク戦のドラフト UI と MatchFactory が使う。
// 評価 = ポジション適性 + 基礎性能 + 編成の補完（役割の重複・前衛・ダメージ種別）+ 相手への相性。
// 上位 3 体から state 外の SplitMix64（呼び出し側が渡す）で重み付き抽選するため決定論的。

public enum DraftAI {
    /// 上位候補の抽選重み（1 位, 2 位, 3 位）。
    static let topWeights: [Double] = [0.6, 0.28, 0.12]

    /// ポジションに合うヒーローを選ぶ。available が空なら空文字。
    public static func draftPick(available: [String], allyPicks: [String], enemyPicks: [String],
                                 position: LanePosition, rng: inout SplitMix64,
                                 master: MasterData = .shared) -> String {
        let scored = available.compactMap { id -> (String, Double)? in
            guard master.hero(id) != nil else { return nil }
            return (id, pickScore(heroID: id, allyPicks: allyPicks, enemyPicks: enemyPicks, position: position,
                                  master: master))
        }
        return choose(scored, rng: &rng) ?? available.first ?? ""
    }

    /// BAN するヒーローを選ぶ（強く、こちらの編成に刺さるもの）。available が空なら空文字。
    public static func draftBan(available: [String], allyPicks: [String], enemyPicks: [String],
                                rng: inout SplitMix64, master: MasterData = .shared) -> String {
        let scored = available.compactMap { id -> (String, Double)? in
            guard master.hero(id) != nil else { return nil }
            return (id, banScore(heroID: id, allyPicks: allyPicks, enemyPicks: enemyPicks, master: master))
        }
        return choose(scored, rng: &rng) ?? available.first ?? ""
    }

    // MARK: - 評価

    /// ピックの評価値。
    public static func pickScore(heroID: String, allyPicks: [String], enemyPicks: [String], position: LanePosition,
                                 master: MasterData = .shared) -> Double {
        guard let def = master.hero(heroID) else { return -.infinity }
        var score = 0.0
        // ポジション適性
        let preferred = MatchFactory.preferredRoles(for: position)
        if let k = preferred.firstIndex(of: def.role) { score += k == 0 ? 3.0 : 1.8 }
        if MatchFactory.defaultPosition(for: def.role) == position { score += 0.4 }
        // 基礎性能
        score += heroPower(def, master: master)
        // 編成の補完
        let allies = allyPicks.compactMap { master.hero($0) }
        let sameRole = allies.filter { $0.role == def.role }.count
        score -= 1.2 * Double(sameRole)
        let frontline = allies.contains { $0.role == .vanguard || $0.role == .duelist }
        if !frontline && (def.role == .vanguard || def.role == .duelist) { score += 0.5 }
        let magic = allies.filter { damageType($0, master: master) == .magic }.count
        let physical = allies.count - magic
        let mine = damageType(def, master: master)
        if mine == .magic && physical >= magic + 2 { score += 0.4 }
        if mine == .physical && magic >= physical + 2 { score += 0.4 }
        // 相手への相性
        let enemies = enemyPicks.compactMap { master.hero($0) }
        score += counterValue(def.role, against: enemies.map(\.role))
        // 扱いやすさ（AI は難しいヒーローをわずかに避ける）
        score -= 0.04 * Double(def.difficulty)
        return score
    }

    /// BAN の評価値（基礎性能 + こちらの編成への相性 + 相手の編成の穴埋め度）。
    public static func banScore(heroID: String, allyPicks: [String], enemyPicks: [String],
                                master: MasterData = .shared) -> Double {
        guard let def = master.hero(heroID) else { return -.infinity }
        var score = heroPower(def, master: master) * 1.5
        let allies = allyPicks.compactMap { master.hero($0) }
        score += counterValue(def.role, against: allies.map(\.role)) * 1.2
        // 相手がまだ持っていない役割ほど相手に取られやすい
        let enemies = enemyPicks.compactMap { master.hero($0) }
        if !enemies.contains(where: { $0.role == def.role }) { score += 0.3 }
        return score
    }

    /// 基礎性能（Lv8 時点の HP・攻撃・防御・移動速度を役割平均と比べた相対値、おおむね -1...1）。
    public static func heroPower(_ def: HeroDef, master: MasterData = .shared) -> Double {
        let peers = master.heroes(role: def.role)
        guard !peers.isEmpty else { return 0 }
        func value(_ h: HeroDef) -> Double {
            let n = 7.0
            let hp = h.baseHP + h.hpGrowth * n
            let atk = h.baseAttack + h.attackGrowth * n
            let def = h.baseDefense + h.defenseGrowth * n + h.baseMagicDefense + h.magicDefenseGrowth * n
            return hp / 3000 + atk / 110 * 1.2 + def / 70 * 0.5 + h.moveSpeed / 260 * 0.4
        }
        let avg = peers.map(value).reduce(0, +) / Double(peers.count)
        return max(-1, min(1, (value(def) - avg) * 4))
    }

    /// ヒーローの主なダメージ種別（Skill1 の種別）。
    static func damageType(_ def: HeroDef, master: MasterData) -> DamageType {
        master.skill(hero: def.heroID, slot: .skill1)?.damageType ?? .physical
    }

    /// role が相手の役割構成に対して持つ相性（正 = 有利）。
    static func counterValue(_ role: Role, against enemies: [Role]) -> Double {
        var v = 0.0
        for e in enemies {
            switch (role, e) {
            case (.assassin, .ranger), (.assassin, .arcanist): v += 0.3
            case (.ranger, .vanguard), (.arcanist, .vanguard): v += 0.2
            case (.vanguard, .assassin), (.support, .assassin): v += 0.25
            case (.duelist, .support), (.duelist, .ranger): v += 0.15
            case (.arcanist, .duelist): v += 0.15
            case (.ranger, .assassin), (.arcanist, .assassin): v -= 0.2
            default: break
            }
        }
        return v
    }

    /// 評価の高い順に並べ、上位 3 体から重み付きで抽選する（同点は ID 昇順）。
    static func choose(_ scored: [(String, Double)], rng: inout SplitMix64) -> String? {
        let sorted = scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        guard !sorted.isEmpty else { return nil }
        let top = Array(sorted.prefix(topWeights.count))
        let weights = topWeights.prefix(top.count)
        let total = weights.reduce(0, +)
        var roll = rng.nextDouble() * total
        for (k, w) in weights.enumerated() {
            if roll < w { return top[k].0 }
            roll -= w
        }
        return top[top.count - 1].0
    }
}
