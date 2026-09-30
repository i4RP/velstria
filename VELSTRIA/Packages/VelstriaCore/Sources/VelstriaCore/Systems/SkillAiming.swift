import Foundation

// 担当: core-skills
// スキルの照準解決（方向・地点・ユニット・自動照準）。純粋関数（状態を書き換えない）。
// 自動照準（.none）: 射程内の最適な敵ヒーロー（HP + シールドが最小）→ 最寄りの敵（ミニオン・モンスター・人形）→ 向き。
// 距離はすべて「術者中心 → 対象の縁」（対象半径込み）で測る。

/// 解決済みの照準。
struct SkillAim {
    /// 発動方向（正規化済み・非ゼロ）。
    var direction: Vec2
    /// 照準点（射程内に丸め済み。自身中心のスキルは術者の位置）。
    var point: Vec2
    /// 対象ユニット（ユニット指定・自動照準で決まった場合）。
    var unit: Int?
    /// 術者から照準点までの距離。
    var distance: Double
}

enum SkillAiming {
    /// 照準を解決する。対象が必須のスキル（連続斬り・対象指定ブリンク）で対象が居なければ nil。
    static func resolve(_ s: SimState, _ ctx: SimContext, caster i: Int, targeting t: SkillTargeting,
                        target: SkillTarget) -> SkillAim? {
        let pos = s.units[i].pos
        let facing = Vec2.fromAngle(s.units[i].facing)

        switch t.archetype {
        case .passive:
            return nil
        case .selfAoE, .teamHeal:
            return SkillAim(direction: facing, point: pos, unit: nil, distance: 0)
        case .multiStrike:
            // 効果半径内（術者半径込み）の敵ヒーローが居なければ発動しない
            guard let u = bestEnemyHero(s, caster: i, reach: t.radius) else { return nil }
            let dir = (s.units[u].pos - pos).normalized
            return SkillAim(direction: dir == .zero ? facing : dir, point: pos, unit: u, distance: 0)
        case .targetedBlink:
            guard let u = blinkTarget(s, caster: i, range: t.range, target: target) else { return nil }
            return aim(at: u, s, caster: i, range: .infinity, facing: facing)
        default:
            break
        }

        switch target {
        case .direction(let d):
            let dir = d.normalized
            let use = dir == .zero ? facing : dir
            return SkillAim(direction: use, point: pos + use * t.range, unit: nil, distance: t.range)
        case .point(let p):
            let delta = p - pos
            let dist = min(delta.length, t.range)
            let n = delta.normalized
            let dir = n == .zero ? facing : n
            return SkillAim(direction: dir, point: pos + dir * dist, unit: nil, distance: dist)
        case .unit(let id):
            if let u = s.index(of: id), isAimable(s, caster: i, u) {
                return aim(at: u, s, caster: i, range: t.range, facing: facing)
            }
            return autoAim(s, caster: i, targeting: t, facing: facing)
        case .none:
            return autoAim(s, caster: i, targeting: t, facing: facing)
        }
    }

    // MARK: - 自動照準

    static func autoAim(_ s: SimState, caster i: Int, targeting t: SkillTargeting, facing: Vec2) -> SkillAim {
        let pos = s.units[i].pos
        switch t.archetype {
        case .blinkEmpower:
            // 移動スキル: 敵へ飛び込まず向き（移動方向）へ
            return SkillAim(direction: facing, point: pos + facing * t.range, unit: nil, distance: t.range)
        case .healZone:
            let reach = t.reach
            if let u = bestEnemyHero(s, caster: i, reach: reach) ?? injuredAllyHero(s, caster: i, range: t.range)
                ?? nearestEnemy(s, caster: i, reach: reach) {
                return aim(at: u, s, caster: i, range: t.range, facing: facing)
            }
            // 何も居なければ足元（自身を回復）
            return SkillAim(direction: facing, point: pos, unit: nil, distance: 0)
        default:
            let reach = t.reach
            if let u = bestEnemyHero(s, caster: i, reach: reach) ?? nearestEnemy(s, caster: i, reach: reach) {
                return aim(at: u, s, caster: i, range: t.range, facing: facing)
            }
            return SkillAim(direction: facing, point: pos + facing * t.range, unit: nil, distance: t.range)
        }
    }

    /// ユニット u へ向けた照準（照準点は射程内に丸める）。
    static func aim(at u: Int, _ s: SimState, caster i: Int, range: Double, facing: Vec2) -> SkillAim {
        let pos = s.units[i].pos
        let delta = s.units[u].pos - pos
        let len = delta.length
        let n = delta.normalized
        let dir = n == .zero ? facing : n
        let dist = min(len, range)
        return SkillAim(direction: dir, point: pos + dir * dist, unit: u, distance: dist)
    }

    /// ユニット指定の照準として使えるか（生存・構造物以外・敵なら視認中）。
    static func isAimable(_ s: SimState, caster i: Int, _ u: Int) -> Bool {
        guard u != i, CombatSystem.isLiving(s, u), !s.units[u].isStructure else { return false }
        return s.units[u].team == s.units[i].team || s.isVisible(u, to: s.units[i].team)
    }

    // MARK: - 候補探索（添字昇順・同値は添字の小さい方 = 決定論的）

    /// reach（+ 対象半径）以内で HP + シールドが最小の、視認中の敵ヒーロー（無敵中を除く）。
    static func bestEnemyHero(_ s: SimState, caster i: Int, reach: Double) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        var best: Int?
        var bestKey = Double.infinity
        for j in s.units.indices where s.units[j].kind == .hero {
            guard s.isTargetableEnemy(j, of: team), !s.units[j].has(.invulnerable) else { continue }
            let r = reach + s.units[j].radius
            guard s.units[j].pos.distanceSquared(to: pos) <= r * r else { continue }
            let key = max(0, s.units[j].hp) + s.units[j].totalShield
            if key < bestKey {
                bestKey = key
                best = j
            }
        }
        return best
    }

    /// reach（+ 対象半径）以内で最も近い、視認中の敵（構造物以外）。
    static func nearestEnemy(_ s: SimState, caster i: Int, reach: Double) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        var best: Int?
        var bestD = Double.infinity
        for j in s.units.indices where !s.units[j].isStructure {
            guard s.isTargetableEnemy(j, of: team) else { continue }
            let d = s.units[j].pos.distanceSquared(to: pos)
            let r = reach + s.units[j].radius
            guard d <= r * r, d < bestD else { continue }
            bestD = d
            best = j
        }
        return best
    }

    /// range 以内で HP 割合が最も低い、負傷した味方ヒーロー（自身を含む）。
    static func injuredAllyHero(_ s: SimState, caster i: Int, range: Double) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        var best: Int?
        var bestRatio = 1.0
        for j in s.units.indices where s.units[j].kind == .hero && s.units[j].team == team {
            guard CombatSystem.isLiving(s, j) else { continue }
            let r = range + s.units[j].radius
            guard s.units[j].pos.distanceSquared(to: pos) <= r * r else { continue }
            let ratio = s.units[j].hpRatio
            if ratio < bestRatio - 1e-9 {
                bestRatio = ratio
                best = j
            }
        }
        return best
    }

    /// 対象指定ブリンクの対象: 指定ユニット（射程内の視認中の敵ヒーロー）、地点なら最寄り、方向なら角度が最小、
    /// それ以外は術者に最も近い射程内の敵ヒーロー。
    static func blinkTarget(_ s: SimState, caster i: Int, range: Double, target: SkillTarget) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        func inRange(_ j: Int) -> Bool {
            guard s.units[j].kind == .hero, s.isTargetableEnemy(j, of: team) else { return false }
            let r = range + s.units[j].radius
            return s.units[j].pos.distanceSquared(to: pos) <= r * r
        }
        if case .unit(let id) = target, let j = s.index(of: id), inRange(j) { return j }

        var best: Int?
        var bestKey = Double.infinity
        for j in s.units.indices where inRange(j) {
            let key: Double
            switch target {
            case .point(let p):
                key = s.units[j].pos.distanceSquared(to: p)
            case .direction(let d):
                // 角度（cos の大きい順）→ 距離の順
                let delta = s.units[j].pos - pos
                let len = delta.length
                let cosine = len > 1e-9 ? delta.dot(d.normalized) / len : 1
                key = (1 - cosine) * 1e7 + len
            case .unit, .none:
                key = s.units[j].pos.distanceSquared(to: pos)
            }
            if key < bestKey {
                bestKey = key
                best = j
            }
        }
        return best
    }
}
