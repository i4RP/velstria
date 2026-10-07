import CoreGraphics
import VelstriaCore

// 担当: battle-hud。スキル・スペルのドラッグ照準の計算（純粋関数。単体テスト対象）。
// ドラッグベクトルは UIKit 座標（右 = +x、下 = +y）。sim 方向への変換は BattleController.simDirection と同じ規則。

enum HUDAim {
    /// これ未満の移動はタップとみなす（pt）。
    static let tapThreshold: CGFloat = 14
    /// ドラッグ方向として扱う最小の長さ（pt）。これ未満はヒーローの向きを使う。
    static let minDirectionDrag: CGFloat = 4

    /// ドラッグ量 → 射程に対する比率（0...1）。
    static func dragRatio(_ drag: CGVector, maxDrag: CGFloat) -> Double {
        guard maxDrag > 0 else { return 0 }
        let len = (drag.dx * drag.dx + drag.dy * drag.dy).squareRoot()
        return Double(min(1, len / maxDrag))
    }

    /// ドラッグ方向（sim 座標・正規化）。ドラッグが短い場合は facing（ラジアン）。
    static func direction(_ drag: CGVector, facing: Double) -> Vec2 {
        let len = (drag.dx * drag.dx + drag.dy * drag.dy).squareRoot()
        guard len >= minDirectionDrag else { return Vec2.fromAngle(facing) }
        return simDirection(drag)
    }

    /// UIKit のドラッグ → sim 方向（BattleController.simDirection と同じ規則: 画面の上 = sim +y）。
    static func simDirection(_ drag: CGVector) -> Vec2 {
        Vec2(Double(drag.dx), -Double(drag.dy)).normalized
    }

    /// 照準点。方向型は常に最大射程、地点型・対象型はドラッグ比率 × 射程、対象不要は発動点。
    static func aimPoint(origin: Vec2, drag: CGVector, maxDrag: CGFloat, targeting: SkillTargeting,
                         facing: Double) -> Vec2 {
        let dir = direction(drag, facing: facing)
        switch targeting.aim {
        case .none:
            return origin
        case .direction:
            return origin + dir * targeting.range
        case .point, .unit:
            return origin + dir * (targeting.range * dragRatio(drag, maxDrag: maxDrag))
        }
    }

    /// キャンセル領域の判定（中心からの距離）。
    static func isInCancelZone(_ p: CGPoint, center: CGPoint, radius: CGFloat) -> Bool {
        let dx = p.x - center.x, dy = p.y - center.y
        return dx * dx + dy * dy <= radius * radius
    }

    /// 指を離した時に送る発動対象。
    /// - unit 型: 照準点に最も近い対象（敵ヒーロー、回復系は味方ヒーロー）。居なければ .none（sim の自動選択に任せる）。
    static func castTarget(targeting: SkillTargeting, origin: Vec2, aimPoint: Vec2, drag: CGVector, facing: Double,
                           state: SimState, team: Team, casterID: EntityID?) -> SkillTarget {
        switch targeting.aim {
        case .none:
            return .none
        case .direction:
            return .direction(direction(drag, facing: facing))
        case .point:
            return .point(aimPoint)
        case .unit:
            let pick = nearestUnit(state: state, team: team, to: aimPoint, origin: origin,
                                   maxRange: targeting.range + unitAimSlack, allies: targeting.targetsAllies,
                                   heroesOnly: true, excluding: targeting.targetsAllies ? nil : casterID)
            return pick.map { .unit($0) } ?? .none
        }
    }

    /// 対象指定で射程外でも拾う余裕（ユニットの半径・移動分）。
    static let unitAimSlack: Double = 150

    /// point に最も近い対象（origin から maxRange 以内・生存・視認）。同距離は添字の小さい方。
    static func nearestUnit(state s: SimState, team: Team, to point: Vec2, origin: Vec2, maxRange: Double,
                            allies: Bool, heroesOnly: Bool, kinds: [UnitKind]? = nil,
                            excluding: EntityID? = nil) -> EntityID? {
        var best: EntityID?
        var bestD = Double.infinity
        let r2 = maxRange * maxRange
        for i in s.units.indices {
            let u = s.units[i]
            guard u.isAlive, u.id != excluding else { continue }
            if heroesOnly && u.kind != .hero { continue }
            if let kinds, !kinds.contains(u.kind) { continue }
            if u.kind == .hero, u.hero?.isDead == true { continue }
            if allies {
                guard u.team == team else { continue }
            } else {
                guard s.isTargetableEnemy(i, of: team) else { continue }
            }
            guard u.pos.distanceSquared(to: origin) <= r2 else { continue }
            let d = u.pos.distanceSquared(to: point)
            if d < bestD {
                bestD = d
                best = u.id
            }
        }
        return best
    }
}

/// バトルスペルの照準方式（DESIGN §7）。nil は即時発動（照準なし）。
enum HUDSpellAim {
    static let smiteID = "BS05"
    static let teleportID = "BS09"

    static func targeting(spellID: String) -> SkillTargeting? {
        switch spellID {
        case "BS01": return SkillTargeting(archetype: .blinkEmpower, aim: .direction, range: 400, radius: 60)
        case "BS05": return SkillTargeting(archetype: .selfAoE, aim: .unit, range: 500, radius: 90)
        case "BS07": return SkillTargeting(archetype: .selfAoE, aim: .unit, range: 600, radius: 90)
        case "BS09": return SkillTargeting(archetype: .targetedBlink, aim: .point, range: Balance.mapSize, radius: 250,
                                           targetsAllies: true)
        case "BS10": return SkillTargeting(archetype: .selfAoE, aim: .unit, range: 650, radius: 90)
        case "BS11": return SkillTargeting(archetype: .selfAoE, aim: .unit, range: Balance.Spells.executeRange, radius: 90)
        case "BS14": return SkillTargeting(archetype: .lineSkillshot, aim: .direction, range: Balance.Spells.flameshotRange,
                                           radius: Balance.Spells.flameshotWidth)
        default: return nil
        }
    }

    /// スペルの発動対象（照準点から決める）。
    static func castTarget(spellID: String, targeting: SkillTargeting, origin: Vec2, aimPoint: Vec2, drag: CGVector,
                           facing: Double, state: SimState, team: Team) -> SkillTarget {
        switch spellID {
        case smiteID:
            let pick = HUDAim.nearestUnit(state: state, team: team, to: aimPoint, origin: origin,
                                          maxRange: targeting.range + HUDAim.unitAimSlack, allies: false,
                                          heroesOnly: false, kinds: [.minion, .monster])
            return pick.map { .unit($0) } ?? .none
        case teleportID:
            return .point(aimPoint)
        default:
            if targeting.aim == .unit {
                let pick = HUDAim.nearestUnit(state: state, team: team, to: aimPoint, origin: origin,
                                              maxRange: targeting.range + HUDAim.unitAimSlack, allies: false,
                                              heroesOnly: true)
                return pick.map { .unit($0) } ?? .none
            }
            return HUDAim.castTarget(targeting: targeting, origin: origin, aimPoint: aimPoint, drag: drag,
                                     facing: facing, state: state, team: team, casterID: nil)
        }
    }

    /// 帰還門の転移先: ドラッグ方向に最もよく合う味方の生存タワー（ドラッグ無しは最も前線のタワー）。
    static func teleportDestination(state s: SimState, team: Team, origin: Vec2, drag: CGVector,
                                    fountain: Vec2) -> Vec2 {
        var towers: [Vec2] = []
        for u in s.units where u.kind == .tower && u.team == team && u.isAlive { towers.append(u.pos) }
        guard !towers.isEmpty else { return fountain }
        let len = (drag.dx * drag.dx + drag.dy * drag.dy).squareRoot()
        if len < HUDAim.tapThreshold {
            // 最も前線（自陣の泉から遠い）
            var best = towers[0]
            for p in towers where p.distanceSquared(to: fountain) > best.distanceSquared(to: fountain) { best = p }
            return best
        }
        let dir = HUDAim.simDirection(drag)
        var best = towers[0]
        var bestScore = -Double.infinity
        for p in towers {
            let to = (p - origin).normalized
            // 方向の一致を優先し、同程度なら近い方
            let score = to.dot(dir) - p.distance(to: origin) / 40_000
            if score > bestScore {
                bestScore = score
                best = p
            }
        }
        return best
    }
}
