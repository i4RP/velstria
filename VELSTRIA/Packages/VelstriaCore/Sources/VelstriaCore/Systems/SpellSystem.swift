import Foundation

// 担当: core-skills
// バトルスペル BS01–BS15（DESIGN §7）。検証 → 対象解決（.none は自動）→ CD → .spellCast → 効果。
// 浄化は CC 中でも使える。それ以外は行動可能（スタン・打ち上げ・強制移動中でない）な時のみ。沈黙では封じられない。
// 攻撃的なスペル（狩猟印・点火・星鎖）はステルスを解除する。

/// バトルスペルの種別（マスターの spell_id と 1:1）。
public enum BattleSpell: String, Codable, Hashable, Sendable, CaseIterable {
    case blink = "BS01"
    case cleanse = "BS02"
    case heal = "BS03"
    case barrier = "BS04"
    case smite = "BS05"
    case ghost = "BS06"
    case ignite = "BS07"
    case stealth = "BS08"
    case teleport = "BS09"
    case exhaust = "BS10"
    case execute = "BS11"
    case inspire = "BS12"
    case petrify = "BS13"
    case flameshot = "BS14"
    case vengeance = "BS15"

    /// 照準方式（HUD のドラッグ照準・AI）。
    public var aim: AimType {
        switch self {
        case .blink, .flameshot: return .direction
        case .smite, .ignite, .exhaust, .execute: return .unit
        case .teleport: return .point
        case .cleanse, .heal, .barrier, .ghost, .stealth, .inspire, .petrify, .vengeance: return .none
        }
    }

    /// 射程（対象指定・瞬歩の距離・石化の半径。帰還門は 0 = 距離無制限）。
    public var range: Double {
        switch self {
        case .blink: return Balance.Spells.blinkDistance
        case .smite: return Balance.Spells.smiteRange
        case .ignite: return Balance.Spells.igniteRange
        case .exhaust: return Balance.Spells.exhaustRange
        case .heal: return Balance.Spells.healAllyRadius
        case .execute: return Balance.Spells.executeRange
        case .petrify: return Balance.Spells.petrifyRadius
        case .flameshot: return Balance.Spells.flameshotRange
        case .cleanse, .barrier, .ghost, .stealth, .teleport, .inspire, .vengeance: return 0
        }
    }

    /// 攻撃的なスペル（ステルスを解除する）。
    public var isOffensive: Bool {
        switch self {
        case .smite, .ignite, .exhaust, .execute, .petrify, .flameshot: return true
        default: return false
        }
    }

    /// CC 中でも使えるか。
    public var usableWhileDisabled: Bool { self == .cleanse }
}

/// 発動検証を通ったスペル。
struct SpellCheck {
    let spell: BattleSpell
    let def: SpellDef
    /// 練習場の CD なし。
    let free: Bool
}

/// 解決済みのスペル対象。
struct SpellPlan {
    /// .spellCast の target（瞬歩の到達予定点・対象の位置・転移先）。
    var point: Vec2
    var unit: Int?
}

public enum SpellSystem {
    /// バトルスペル発動（DESIGN §7）。成功で true。対象が必要なスペルで対象が居なければ CD を消費せず false。
    public static func cast(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, spellIndex: Int,
                            target: SkillTarget) -> Bool {
        guard let check = validate(s, ctx, heroIndex: i, spellIndex: spellIndex),
              let plan = resolve(check.spell, s, ctx, caster: i, target: target) else { return false }
        let spell = check.spell
        let origin = s.units[i].pos
        s.units[i].hero?.spellCooldowns[spellIndex] = check.free ? 0 : check.def.cooldownSec
        s.emit(.spellCast(casterID: s.units[i].id, spellID: spell.rawValue, origin: origin, target: plan.point))
        if spell.isOffensive { SkillPassives.breakStealth(&s, i) }
        apply(spell, &s, ctx, caster: i, plan: plan)
        return true
    }

    /// 発動可能か（CD・生存・CC）。HUD・AI が参照。対象の有無は含まない。
    public static func canCast(_ s: SimState, _ ctx: SimContext, heroIndex i: Int, spellIndex: Int) -> Bool {
        validate(s, ctx, heroIndex: i, spellIndex: spellIndex) != nil
    }

    /// スペルの照準情報（HUD の照準表示用。archetype は照準の形の近いもの）。
    /// 瞬歩 = blinkEmpower（方向・400）、対象指定 = targetedBlink（射程円）、帰還門 = groundAoE（地点）、
    /// 自己強化 = selfAoE（治癒波は味方を探す半径 800）。
    public static func targeting(for spellID: String) -> SkillTargeting? {
        guard let spell = BattleSpell(rawValue: spellID) else { return nil }
        switch spell {
        case .blink:
            return SkillTargeting(archetype: .blinkEmpower, aim: .direction, range: spell.range, radius: 0)
        case .smite, .ignite, .exhaust, .execute:
            return SkillTargeting(archetype: .targetedBlink, aim: .unit, range: spell.range, radius: 0)
        case .flameshot:
            return SkillTargeting(archetype: .lineSkillshot, aim: .direction, range: spell.range,
                                  radius: Balance.Spells.flameshotWidth)
        case .petrify:
            return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: spell.range)
        case .teleport:
            return SkillTargeting(archetype: .groundAoE, aim: .point, range: 0,
                                  radius: Balance.Economy.teleportTowerRadius, targetsAllies: true)
        case .heal:
            return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: spell.range, targetsAllies: true)
        case .cleanse, .barrier, .ghost, .stealth, .inspire, .vengeance:
            return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: 0)
        }
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        let noCD = ctx.config.practice?.noCooldowns == true
        for i in s.units.indices where s.units[i].kind == .hero {
            guard let h = s.units[i].hero else { continue }
            for k in h.spellCooldowns.indices where h.spellCooldowns[k] > 0 {
                s.units[i].hero?.spellCooldowns[k] = noCD ? 0 : max(0, h.spellCooldowns[k] - Balance.dt)
            }
        }
    }

    // MARK: - 検証

    static func validate(_ s: SimState, _ ctx: SimContext, heroIndex i: Int, spellIndex k: Int) -> SpellCheck? {
        guard s.units.indices.contains(i), s.units[i].kind == .hero, let h = s.units[i].hero, !h.isDead,
              s.units[i].isAlive, k >= 0, k < h.spells.count, k < h.spellCooldowns.count,
              let spell = BattleSpell(rawValue: h.spells[k]), let def = ctx.master.spell(h.spells[k]) else { return nil }
        let free = ctx.config.practice?.noCooldowns == true
        guard free || h.spellCooldowns[k] <= CombatSystem.timeEpsilon else { return nil }
        guard spell.usableWhileDisabled || s.units[i].canAct else { return nil }
        return SpellCheck(spell: spell, def: def, free: free)
    }

    // MARK: - 対象解決（状態を書き換えない）

    static func resolve(_ spell: BattleSpell, _ s: SimState, _ ctx: SimContext, caster i: Int,
                        target: SkillTarget) -> SpellPlan? {
        let pos = s.units[i].pos
        switch spell {
        case .blink:
            let facing = Vec2.fromAngle(s.units[i].facing)
            var delta: Vec2
            switch target {
            case .direction(let d): delta = d.normalized * spell.range
            case .point(let p): delta = (p - pos).clamped(maxLength: spell.range)
            case .unit(let id): delta = s.unit(id).map { ($0.pos - pos).clamped(maxLength: spell.range) } ?? .zero
            case .none: delta = facing * spell.range
            }
            if delta.lengthSquared < 1e-12 { delta = facing * spell.range }
            return SpellPlan(point: pos + delta, unit: nil)
        case .smite:
            // 祝福済みのジャングル靴ならヒーローを直接指定して使える
            if case .unit(let id) = target, let j = s.index(of: id),
               let h = s.units[i].hero, GearEffects.jungleBlessingActive(h, master: ctx.master),
               isEnemyHero(s, caster: i, j, range: Balance.Spells.smiteRange) {
                return SpellPlan(point: s.units[j].pos, unit: j)
            }
            guard let u = smiteTarget(s, caster: i, target: target) else { return nil }
            return SpellPlan(point: s.units[u].pos, unit: u)
        case .ignite, .exhaust, .execute:
            guard let u = heroTarget(s, caster: i, range: spell.range, target: target,
                                     preferLowHealth: spell == .ignite || spell == .execute) else { return nil }
            return SpellPlan(point: s.units[u].pos, unit: u)
        case .flameshot:
            // 方向（指定が無ければ向いている方向）へ射程いっぱいの線を撃つ。当たらなくても発動する
            var dir: Vec2
            switch target {
            case .direction(let d): dir = d.normalized
            case .point(let p): dir = (p - pos).normalized
            case .unit(let id): dir = s.unit(id).map { ($0.pos - pos).normalized } ?? .zero
            case .none: dir = .zero
            }
            if dir == .zero { dir = Vec2.fromAngle(s.units[i].facing) }
            return SpellPlan(point: pos + dir * spell.range, unit: nil)
        case .teleport:
            guard let dest = teleportRequest(s, ctx, caster: i, target: target),
                  RecallSystem.teleportDestination(s, ctx, heroIndex: i, requested: dest) != nil else { return nil }
            return SpellPlan(point: dest, unit: nil)
        case .cleanse, .heal, .barrier, .ghost, .stealth, .inspire, .petrify, .vengeance:
            return SpellPlan(point: pos, unit: nil)
        }
    }

    /// 対象の縁までの距離が range 以内の、視認中の敵ヒーローか。
    static func isEnemyHero(_ s: SimState, caster i: Int, _ j: Int, range: Double) -> Bool {
        guard s.units[j].kind == .hero, s.isTargetableEnemy(j, of: s.units[i].team) else { return false }
        let r = range + s.units[j].radius
        return s.units[j].pos.distanceSquared(to: s.units[i].pos) <= r * r
    }

    /// 点火・星鎖の対象: 指定ユニット → 地点/方向に最も近い → 自動（点火は HP 最小、星鎖は最寄り）。
    static func heroTarget(_ s: SimState, caster i: Int, range: Double, target: SkillTarget,
                           preferLowHealth: Bool) -> Int? {
        if case .unit(let id) = target, let j = s.index(of: id), isEnemyHero(s, caster: i, j, range: range) {
            return j
        }
        let pos = s.units[i].pos
        var best: Int?
        var bestKey = Double.infinity
        for j in s.units.indices where isEnemyHero(s, caster: i, j, range: range) {
            let key: Double
            switch target {
            case .point(let p): key = s.units[j].pos.distanceSquared(to: p)
            case .direction(let d): key = s.units[j].pos.distanceSquared(to: pos + d.normalized * range)
            case .unit, .none:
                key = preferLowHealth ? max(0, s.units[j].hp) + s.units[j].totalShield
                    : s.units[j].pos.distanceSquared(to: pos)
            }
            if key < bestKey {
                bestKey = key
                best = j
            }
        }
        return best
    }

    /// 狩猟印の対象（500 以内の視認中の敵ミニオン/中立を含むモンスター）。
    /// 自動: モンスター優先（最大 HP の大きい順 = ボス > バフ > 大 > 小）→ ミニオン（HP の低い順）→ 近い順。
    static func smiteTarget(_ s: SimState, caster i: Int, target: SkillTarget) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        let range = Balance.Spells.smiteRange
        func valid(_ j: Int) -> Bool {
            let kind = s.units[j].kind
            guard kind == .minion || kind == .monster, s.isTargetableEnemy(j, of: team) else { return false }
            let r = range + s.units[j].radius
            return s.units[j].pos.distanceSquared(to: pos) <= r * r
        }
        if case .unit(let id) = target, let j = s.index(of: id), valid(j) { return j }
        var best: Int?
        var bestKey = Double.infinity
        for j in s.units.indices where valid(j) {
            let d = s.units[j].pos.distanceSquared(to: pos)
            let key: Double
            switch target {
            case .point(let p):
                key = s.units[j].pos.distanceSquared(to: p)
            case .direction(let dir):
                key = s.units[j].pos.distanceSquared(to: pos + dir.normalized * range)
            case .unit, .none:
                // 距離（最大 ~1e6）より大きな段差で種別・HP を優先する
                if s.units[j].kind == .monster {
                    key = -s.units[j].stats.maxHP * 1e7 + d
                } else {
                    key = max(0, s.units[j].hp) * 1e7 + d
                }
            }
            if key < bestKey {
                bestKey = key
                best = j
            }
        }
        return best
    }

    /// 帰還門の転移先の要求点。地点が無効なら最寄りの味方タワーへ寄せる。
    /// 自動: 自分のレーンの最も前線の味方タワー → 任意レーンの最も前線のタワー → 泉。
    static func teleportRequest(_ s: SimState, _ ctx: SimContext, caster i: Int, target: SkillTarget) -> Vec2? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        func towers(_ body: (Int) -> Void) {
            for j in s.units.indices where s.units[j].kind == .tower && s.units[j].team == team && s.units[j].isAlive {
                body(j)
            }
        }
        switch target {
        case .point(let p):
            if RecallSystem.teleportDestination(s, ctx, heroIndex: i, requested: p) != nil { return p }
            var best: Int?
            var bestD = Double.infinity
            towers { j in
                let d = s.units[j].pos.distanceSquared(to: p)
                if d < bestD { bestD = d; best = j }
            }
            return best.map { s.units[$0].pos }
        case .unit(let id):
            if let j = s.index(of: id), s.units[j].kind == .tower, s.units[j].team == team, s.units[j].isAlive {
                return s.units[j].pos
            }
            return autoTeleport(s, ctx, caster: i)
        case .direction(let d):
            let dir = d.normalized
            guard dir != .zero else { return autoTeleport(s, ctx, caster: i) }
            var best: Int?
            var bestKey = Double.infinity
            towers { j in
                let delta = s.units[j].pos - pos
                let len = delta.length
                let cosine = len > 1e-9 ? delta.dot(dir) / len : 1
                let key = (1 - cosine) * 1e7 + len
                if key < bestKey { bestKey = key; best = j }
            }
            return best.map { s.units[$0].pos } ?? autoTeleport(s, ctx, caster: i)
        case .none:
            return autoTeleport(s, ctx, caster: i)
        }
    }

    static func autoTeleport(_ s: SimState, _ ctx: SimContext, caster i: Int) -> Vec2 {
        let team = s.units[i].team
        let pos = s.units[i].pos
        let lane: Lane? = s.units[i].hero.flatMap { ctx.map.lane(for: $0.position) }
        var best: Int?
        var bestKey = Double.infinity
        for j in s.units.indices where s.units[j].kind == .tower && s.units[j].team == team && s.units[j].isAlive {
            guard let t = s.units[j].tower else { continue }
            // 自レーン優先 → 前線（外塔）優先 → 近い順
            let laneKey: Double = (lane == nil || t.lane == lane) ? 0 : 1
            let key = laneKey * 1e9 + Double(t.tier.rawValue) * 1e8 + s.units[j].pos.distanceSquared(to: pos) * 1e-2
            if key < bestKey {
                bestKey = key
                best = j
            }
        }
        return best.map { s.units[$0].pos } ?? ctx.map.fountain(team)
    }

    // MARK: - 効果

    static func apply(_ spell: BattleSpell, _ s: inout SimState, _ ctx: SimContext, caster i: Int, plan: SpellPlan) {
        let k = Balance.Spells.self
        let casterID = s.units[i].id
        let tag = k.tag(spell)
        let level = Double(s.units[i].hero?.level ?? 1)
        switch spell {
        case .blink:
            MovementSystem.blink(&s, ctx, unitIndex: i, to: plan.point)
        case .cleanse:
            CombatSystem.cleanse(&s, targetIndex: i)
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .ccImmune, duration: k.cleanseImmunityDuration,
                                                                    sourceID: casterID, tag: tag))
        case .heal:
            var targets = [i]
            if let ally = lowestAlly(s, caster: i, radius: k.healAllyRadius) { targets.append(ally) }
            for t in targets {
                CombatSystem.heal(&s, ctx, sourceID: casterID, targetIndex: t, amount: s.units[t].stats.maxHP * k.healPct)
                CombatSystem.addStatus(&s, targetIndex: t, StatusEffect(kind: .speedBoost, duration: k.healSpeedDuration,
                                                                        magnitude: k.healSpeedBoost, sourceID: casterID,
                                                                        tag: tag))
            }
        case .barrier:
            CombatSystem.addShield(&s, ctx, sourceID: casterID, targetIndex: i,
                                   amount: s.units[i].stats.maxHP * k.barrierPct, duration: k.barrierDuration, tag: tag)
        case .smite:
            guard let u = plan.unit else { return }
            if s.units[u].kind == .hero {
                GearSystem.applySmiteOnHero(&s, ctx, caster: i, target: u)
                return
            }
            CombatSystem.applyDamage(&s, ctx, sourceID: casterID, targetIndex: u,
                                     amount: k.smiteBase + k.smitePerLevel * level, type: .trueDamage, source: .spell)
        case .ghost:
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .speedBoost, duration: k.ghostDuration,
                                                                    magnitude: k.ghostSpeedBoost, sourceID: casterID,
                                                                    tag: tag))
        case .ignite:
            guard let u = plan.unit else { return }
            let total = k.igniteBase + k.ignitePerLevel * level
            CombatSystem.addStatus(&s, targetIndex: u, StatusEffect(kind: .burn, duration: k.igniteDuration,
                                                                    magnitude: total / k.igniteDuration,
                                                                    sourceID: casterID, tag: tag))
            CombatSystem.addStatus(&s, targetIndex: u, StatusEffect(kind: .healReduction, duration: k.igniteDuration,
                                                                    magnitude: k.igniteHealReduction,
                                                                    sourceID: casterID, tag: tag))
        case .stealth:
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .stealth, duration: k.stealthDuration,
                                                                    sourceID: casterID, tag: tag))
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .speedBoost, duration: k.stealthDuration,
                                                                    magnitude: k.stealthSpeedBoost, sourceID: casterID,
                                                                    tag: tag))
        case .teleport:
            RecallSystem.startTeleport(&s, ctx, heroIndex: i, destination: plan.point, duration: k.teleportChannel)
        case .exhaust:
            guard let u = plan.unit else { return }
            CombatSystem.addStatus(&s, targetIndex: u, StatusEffect(kind: .slow, duration: k.exhaustDuration,
                                                                    magnitude: k.exhaustSlow, sourceID: casterID,
                                                                    tag: tag))
            CombatSystem.addStatus(&s, targetIndex: u, StatusEffect(kind: .damageDealtReduction,
                                                                    duration: k.exhaustDuration,
                                                                    magnitude: k.exhaustDamageDealtReduction,
                                                                    sourceID: casterID, tag: tag))
        case .execute:
            guard let u = plan.unit else { return }
            let missing = max(0, s.units[u].stats.maxHP - s.units[u].hp)
            CombatSystem.applyDamage(&s, ctx, sourceID: casterID, targetIndex: u,
                                     amount: k.executeBase + k.executePerLevel * level + k.executeMissingHPPct * missing,
                                     type: .trueDamage, source: .spell)
        case .inspire:
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .attackSpeedBoost, duration: k.inspireDuration,
                                                                    magnitude: k.inspireAttackSpeed, sourceID: casterID,
                                                                    tag: tag))
        case .petrify:
            let team = s.units[i].team
            let origin = s.units[i].pos
            for j in s.units.indices where s.units[j].kind == .hero && s.isTargetableEnemy(j, of: team) {
                let r = k.petrifyRadius + s.units[j].radius
                guard s.units[j].pos.distanceSquared(to: origin) <= r * r else { continue }
                CombatSystem.addStatus(&s, targetIndex: j, StatusEffect(kind: .stun, duration: k.petrifyStun,
                                                                        sourceID: casterID, tag: tag))
                CombatSystem.addStatus(&s, targetIndex: j, StatusEffect(kind: .slow,
                                                                        duration: k.petrifyStun + k.petrifySlowAfterStun,
                                                                        magnitude: k.petrifySlow, sourceID: casterID,
                                                                        tag: tag))
            }
        case .flameshot:
            let dir = (plan.point - s.units[i].pos).normalized
            let damage = k.flameshotBase + k.flameshotPerLevel * level
            ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: dir, maxDistance: k.flameshotRange),
                                   speed: k.flameshotSpeed, width: k.flameshotWidth, pierce: false,
                                   payload: HitPayload(damage: damage, damageType: .magic, source: .spell, cc: .knockback,
                                                       heroesOnly: true),
                                   visual: tag)
        case .vengeance:
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .damageReduction, duration: k.vengeanceDuration,
                                                                    magnitude: k.vengeanceReduction, sourceID: casterID,
                                                                    tag: tag))
        }
    }

    /// radius 以内で HP 割合が最も低い味方ヒーロー（自身を除く）。
    static func lowestAlly(_ s: SimState, caster i: Int, radius: Double) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        var best: Int?
        var bestRatio = Double.infinity
        for j in s.units.indices where j != i && s.units[j].kind == .hero && s.units[j].team == team {
            guard CombatSystem.isLiving(s, j) else { continue }
            let r = radius + s.units[j].radius
            guard s.units[j].pos.distanceSquared(to: pos) <= r * r else { continue }
            let ratio = s.units[j].hpRatio
            if ratio < bestRatio {
                bestRatio = ratio
                best = j
            }
        }
        return best
    }
}
