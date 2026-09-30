#if DEBUG
import Foundation
import VelstriaCore

// 担当: battle-renderer。DEBUG 専用の目視確認用ショーケース（起動引数 -renderShowcase）。
// 描画フレームの SimState コピーへ合成のゾーン・投射物・状態異常を差し込み、合成イベントを流す。
// シミュレーション本体には一切書き込まない（スキル未実装の段階でも演出を確認できるようにする）。

@MainActor
final class RenderShowcase {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-renderShowcase") }
    static let period: Float = 12

    private var time: Float = 0
    private var cycle = -1
    private var fired: [Bool] = Array(repeating: false, count: 32)
    private var destroyedTower: EntityID?
    private let master: MasterData
    /// 照準表示の確認用（controller.aim が無いときに使う）。
    private(set) var aim: AimIndicator?

    init(master: MasterData) {
        self.master = master
    }

    func apply(_ f: inout RenderFrame, events: inout [SimEvent]) {
        time += f.dt
        let local = time.truncatingRemainder(dividingBy: RenderShowcase.period)
        let c = Int(time / RenderShowcase.period)
        if c != cycle {
            cycle = c
            for k in fired.indices { fired[k] = false }
        }
        if let tower = destroyedTower, let ti = f.state.index(of: tower) {
            f.state.units[ti].isAlive = false
            f.state.units[ti].hp = 0
        }
        guard let hi = f.state.humanHeroIndex ?? f.state.units.indices.first(where: { f.state.units[$0].kind == .hero })
        else { return }
        let hero = f.state.units[hi]
        guard let heroData = hero.hero else { return }
        let p = hero.pos
        // 照準: 方向型 → 地点型 → 対象型 → 自身中心 → 貫通（キャンセル）を順に表示
        let dir = Vec2(cos(Double(time) * 0.7), sin(Double(time) * 0.7))
        func targeting(_ a: SkillArchetype, _ t: AimType, range: Double, radius: Double, allies: Bool = false) -> SkillTargeting {
            SkillTargeting(archetype: a, aim: t, range: range, radius: radius, targetsAllies: allies)
        }
        if local < 3 {
            aim = AimIndicator(kind: .skill(.skill1), targeting: targeting(.lineSkillshot, .direction, range: 900, radius: 160),
                               origin: p, target: p + dir * 900, isCancelling: false)
        } else if local < 6 {
            aim = AimIndicator(kind: .skill(.skill3), targeting: targeting(.healZone, .point, range: 800, radius: 300, allies: true),
                               origin: p, target: p + dir * 600, isCancelling: false)
        } else if local < 9 {
            aim = AimIndicator(kind: .skill(.ultimate), targeting: targeting(.targetedBlink, .unit, range: 700, radius: 100),
                               origin: p, target: p + dir * 500, isCancelling: false)
        } else if local < 10.5 {
            aim = AimIndicator(kind: .spell(0), targeting: targeting(.selfAoE, .none, range: 0, radius: 350),
                               origin: p, target: p, isCancelling: false)
        } else {
            aim = AimIndicator(kind: .skill(.ultimate), targeting: targeting(.piercingLine, .direction, range: 2000, radius: 140),
                               origin: p, target: p + dir * 2000, isCancelling: true)
        }
        let skills = master.skills(forHero: heroData.heroID)
        func effect(_ slot: SkillSlot) -> String { skills.first { $0.slot == slot }?.effectID ?? "" }
        func once(_ k: Int, _ at: Float, _ body: () -> Void) {
            guard local >= at, !fired[k] else { return }
            fired[k] = true
            body()
        }

        // ゾーン（予告 → 発動）
        func zone(_ id: EntityID, start: Float, delay: Double, duration: Double, team: Team, center: Vec2, radius: Double,
                  shape: ZoneShape, heal: Bool) {
            let t = Double(local - start)
            guard t >= 0, t < delay + max(duration, 0.05) else { return }
            let payload = HitPayload(damage: heal ? 0 : 100, damageType: .magic, source: .skill(.skill3),
                                     affectsEnemies: !heal, affectsAllies: heal, healAmount: heal ? 80 : 0)
            var z = AreaZone(id: id, ownerID: hero.id, team: team, center: center, radius: radius, shape: shape,
                             delay: delay, duration: duration, payload: payload, visual: effect(.skill3))
            z.delay = max(0, delay - t)
            z.triggered = t >= delay
            f.state.zones.append(z)
        }
        zone(900_001, start: 0.5, delay: 1.2, duration: 0, team: .red, center: p + Vec2(420, 260), radius: 320,
             shape: .circle, heal: false)
        zone(900_002, start: 1.5, delay: 0.9, duration: 0, team: hero.team, center: p,
             radius: 520, shape: .cone(direction: Vec2(1, 0.2).normalized, halfAngle: 0.65), heal: false)
        zone(900_003, start: 2.5, delay: 1.3, duration: 0, team: .red, center: p + Vec2(-700, -350), radius: 130,
             shape: .line(direction: Vec2(1, 0.35).normalized, length: 1300), heal: false)
        zone(900_004, start: 3.0, delay: 0.6, duration: 3.0, team: hero.team, center: p + Vec2(-150, -420), radius: 360,
             shape: .circle, heal: true)

        // 投射物（スキル弾・タワー弾・通常攻撃）
        func projectile(_ id: EntityID, start: Float, from: Vec2, dir: Vec2, speed: Double, range: Double, visual: String,
                        team: Team) {
            let t = Double(local - start)
            guard t >= 0, t * speed < range else { return }
            let d = dir.normalized
            var pr = Projectile(id: id, ownerID: hero.id, team: team, pos: from + d * (t * speed),
                                motion: .linear(direction: d, maxDistance: range), speed: speed,
                                payload: HitPayload(damage: 0, damageType: .magic, source: .skill(.ultimate)), visual: visual)
            pr.prevPos = from + d * max(0, t * speed - speed * Balance.dt)
            f.state.projectiles.append(pr)
        }
        projectile(900_101, start: 6.0, from: p, dir: Vec2(1, 0.1), speed: 1400, range: 1200, visual: effect(.ultimate), team: hero.team)
        projectile(900_102, start: 6.3, from: p, dir: Vec2(0.2, 1), speed: 1600, range: 1000, visual: effect(.skill1), team: hero.team)
        projectile(900_103, start: 6.6, from: p + Vec2(900, 700), dir: Vec2(-1, -0.8), speed: 1500, range: 1100,
                   visual: "basic_attack", team: .red)
        projectile(900_104, start: 7.0, from: p + Vec2(-800, 600), dir: Vec2(1, -0.7), speed: 1300, range: 1000,
                   visual: "empowered_attack", team: hero.team)

        // 状態異常・シールド
        if local >= 5.0 && local < 9.5 {
            f.state.units[hi].shields.append(Shield(amount: 250, duration: 1))
        }
        if local >= 6.0 && local < 7.5 { f.state.units[hi].statuses.append(StatusEffect(kind: .stun, duration: 1)) }
        if local >= 7.5 && local < 8.5 { f.state.units[hi].statuses.append(StatusEffect(kind: .root, duration: 1)) }
        if local >= 8.5 && local < 9.5 {
            f.state.units[hi].statuses.append(StatusEffect(kind: .slow, duration: 1, magnitude: 0.3))
        }

        // イベント
        once(0, 3.4) {
            events.append(.skillCast(SkillCastEvent(casterID: hero.id, heroID: heroData.heroID, slot: .skill2, skillID: "",
                                                    effectID: effect(.skill2), archetype: .dashStrike, origin: p,
                                                    target: p + Vec2(500, 120), range: 500, radius: 250)))
        }
        once(1, 4.2) {
            events.append(.skillCast(SkillCastEvent(casterID: hero.id, heroID: heroData.heroID, slot: .ultimate, skillID: "",
                                                    effectID: effect(.ultimate), archetype: .selfAoE, origin: p, target: p,
                                                    range: 0, radius: 400)))
        }
        once(2, 5.0) {
            events.append(.levelUp(heroID: hero.id, level: heroData.level))
            events.append(.shieldGained(targetID: hero.id, sourceID: hero.id, amount: 250))
        }
        once(3, 5.4) {
            events.append(.heal(targetID: hero.id, sourceID: hero.id, amount: 180))
            events.append(.goldGained(heroID: hero.id, amount: 124, pos: p + Vec2(250, 150)))
        }
        once(4, 5.8) {
            let enemy = f.state.units.indices.first { i in
                let u = f.state.units[i]
                return u.team != hero.team && u.isAlive && !u.isStructure && u.pos.distance(to: p) < 1500
            }
            let tid = enemy.map { f.state.units[$0].id } ?? hero.id
            let tpos = enemy.map { f.state.units[$0].pos } ?? p
            events.append(.damage(DamageEvent(sourceID: hero.id, targetID: tid, amount: 342, absorbed: 0, damageType: .physical,
                                              source: .basicAttack, isCrit: true, pos: tpos)))
            events.append(.damage(DamageEvent(sourceID: tid, targetID: hero.id, amount: 88, absorbed: 0, damageType: .magic,
                                              source: .skill(.ultimate), isCrit: false, pos: p)))
        }
        once(5, 9.6) { events.append(.channelStarted(heroID: hero.id, kind: .recall, duration: 6)) }
        once(6, 11.6) { events.append(.channelCanceled(heroID: hero.id, kind: .recall)) }
        once(7, 10.5) {
            events.append(.blinked(unitID: hero.id, from: p, to: p + Vec2(300, 200)))
        }
        if cycle == 0 {
            once(8, 11.0) {
                // 最寄りのタワーを破壊状態にする（以降もコピー上で維持）
                var best: Int?
                var bestD = Double.infinity
                for i in f.state.units.indices where f.state.units[i].kind == .tower && f.state.units[i].isAlive {
                    let d = f.state.units[i].pos.distance(to: p)
                    if d < bestD { bestD = d; best = i }
                }
                if let b = best {
                    let u = f.state.units[b]
                    destroyedTower = u.id
                    f.state.units[b].isAlive = false
                    events.append(.structureDestroyed(unitID: u.id, kind: .tower, team: u.team, lane: u.tower?.lane,
                                                      tier: u.tower?.tier, killerID: hero.id))
                }
            }
        }
    }
}
#endif
