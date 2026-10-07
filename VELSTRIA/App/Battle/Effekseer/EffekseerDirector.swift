import Foundation
import RealityKit
import VelstriaCore

// 担当: Effekseer の効果の再生係。sim のイベント → 効果（Effects/Effekseer/<ヒーロー>_<段>.efk）の再生。
//
// 効果の名前: <heroID>_<段>。段（ヒーロー固有の効果が無い段は何も出さない。旧来の演出が代わりに出る）:
//   atk_cast     通常攻撃の発射・打撃の瞬間（遠隔 = 発射位置、近接 = 術者。atk_cast2 があれば交互）
//   atk_travel   通常攻撃の投射物（飛んでいる間、投射物に追従）
//   atk_hit      通常攻撃の着弾・命中（近接は damage、遠隔は projectileHit）
//   s1_ / s2_ / ult_ + cast（発動）/ travel（投射物）/ impact（着弾・ゾーン発動・即時の着弾）/ hit（被弾者）/ telegraph（予告）
//   passive_cast パッシブの発動
// 向き: 効果は「前 = -Z」で作る。再生時に yaw で前を合わせる（前 = (-sin yaw, 0, -cos yaw)。UnitLayer・ProjectileLayer と同じ規則）。
// 同じヒーローの効果が 1 つでもあれば、そのヒーローの旧来の演出（SkillFX・通常攻撃の演出）は止める（二重に出さない）。

@MainActor
final class EffekseerDirector {
    private let overlay: EffekseerOverlay
    private unowned let units: UnitLayer
    private unowned let projectiles: ProjectileLayer
    /// 効果を持つヒーロー。
    private(set) var heroes: Set<String> = []

    private enum Target { case unit(EntityID), projectile(EntityID) }
    private struct Follow {
        var handle: Int32
        var target: Target
        var offset: SIMD3<Float>
        var until: Float
    }
    private var follows: [Follow] = []
    private var shots: [EntityID: Int32] = [:]
    private var zones: [EntityID: (slot: SkillSlot, hero: String, caster: EntityID)] = [:]
    private var lastHit: [Int: Float] = [:]
    private var swing: [EntityID: Int] = [:]
    private var time: Float = 0

    init(overlay: EffekseerOverlay, units: UnitLayer, projectiles: ProjectileLayer) {
        self.overlay = overlay
        self.units = units
        self.projectiles = projectiles
        refreshHeroes()
    }

    func refreshHeroes() {
        heroes = Set(overlay.effectNames.compactMap { n in
            guard n.count > 5, n.hasPrefix("H"), n[n.index(n.startIndex, offsetBy: 4)] == "_" else { return nil }
            return String(n.prefix(4))
        })
    }

    func handles(_ heroID: String?) -> Bool { heroID.map { heroes.contains($0) } ?? false }

    // MARK: 名前

    private static func slotName(_ s: SkillSlot) -> String {
        switch s {
        case .skill1: return "s1"
        case .skill2: return "s2"
        case .ultimate: return "ult"
        case .passive: return "passive"
        }
    }

    private func name(_ hero: String, _ stage: String) -> String? {
        let n = "\(hero)_\(stage)"
        return overlay.effectNames.contains(n) ? n : nil
    }

    private static func yaw(forward f: SIMD3<Float>) -> Float { atan2(-f.x, -f.z) }

    private static func flat(_ v: SIMD3<Float>, fallback: SIMD3<Float> = [0, 0, -1]) -> SIMD3<Float> {
        var f = v
        f.y = 0
        return simd_length(f) < 1e-3 ? fallback : simd_normalize(f)
    }

    private func facing(_ id: EntityID, _ s: SimState) -> SIMD3<Float> {
        guard let u = s.unit(id) else { return [0, 0, -1] }
        return [Float(cos(u.facing)), 0, -Float(sin(u.facing))]
    }

    @discardableResult
    private func play(_ n: String?, at p: SIMD3<Float>, forward: SIMD3<Float>, scale: Float = 1) -> Int32 {
        guard let n else { return -1 }
        return overlay.play(n, at: p, yaw: Self.yaw(forward: Self.flat(forward)), scale: scale)
    }

    // MARK: 通常攻撃

    /// 通常攻撃の発射・打撃。効果を再生したら true（呼び出し側は旧来の発射演出を出さない）。
    @discardableResult
    func onAttackReleased(src: EntityID, target: EntityID, isRanged: Bool, state: SimState) -> Bool {
        guard let hero = state.unit(src)?.hero?.heroID, heroes.contains(hero) else { return false }
        let from = (units.hero(src)?.handle.attackLaunchPoint()) ?? units.worldPositionOf(src).map { $0 + [0, 1, 0] } ?? .zero
        let tp = units.worldPositionOf(target) ?? from + facing(src, state)
        let fwd = Self.flat(tp - from, fallback: facing(src, state))
        let n = (swing[src] ?? 0) & 1
        swing[src] = n + 1
        let cast = (n == 1 ? name(hero, "atk_cast2") : nil) ?? name(hero, "atk_cast")
        play(cast, at: isRanged ? from : (units.worldPositionOf(src) ?? from), forward: fwd)
        return true
    }

    // MARK: スキル

    /// スキル発動。演出を再生したら true。
    @discardableResult
    func onCast(_ c: SkillCastEvent, state: SimState) -> Bool {
        guard heroes.contains(c.heroID) else { return false }
        let s = Self.slotName(c.slot)
        let caster = units.worldPositionOf(c.casterID) ?? worldPosition(c.origin)
        let target = worldPosition(c.target)
        let fwd = Self.flat(target - worldPosition(c.origin), fallback: facing(c.casterID, state))
        let castHandle = play(name(c.heroID, "\(s)_cast"), at: caster, forward: fwd)
        if castHandle >= 0, c.slot == .ultimate || c.archetype == .selfAoE {
            follows.append(Follow(handle: castHandle, target: .unit(c.casterID), offset: .zero, until: time + 12))
        }
        switch c.archetype {
        case .cone, .selfAoE, .teamHeal, .multiStrike, .leapSlam:
            play(name(c.heroID, "\(s)_impact"), at: caster, forward: fwd)
        case .targetedBlink, .blinkEmpower, .dashStrike:
            play(name(c.heroID, "\(s)_impact"), at: target, forward: fwd)
        default:
            break
        }
        return true
    }

    func onZoneCreated(zoneID: EntityID, ownerID: EntityID, visual: String, center: Vec2, state: SimState) {
        guard let u = state.unit(ownerID), let hero = u.hero?.heroID, heroes.contains(hero) else { return }
        guard let slot = slotFor(visual: visual, hero: hero) else { return }
        zones[zoneID] = (slot, hero, ownerID)
        if zones.count > 64 { zones.removeAll() }
        play(name(hero, "\(Self.slotName(slot))_telegraph"), at: worldPosition(center), forward: facing(ownerID, state))
    }

    @discardableResult
    func onZoneTriggered(zoneID: EntityID, center: Vec2, state: SimState) -> Bool {
        guard let z = zones[zoneID] else { return false }
        play(name(z.hero, "\(Self.slotName(z.slot))_impact"), at: worldPosition(center), forward: facing(z.caster, state))
        return true
    }

    func isEffekseerZone(_ id: EntityID) -> Bool { zones[id] != nil }

    // MARK: 投射物

    func onProjectileLaunched(projectileID: EntityID, ownerID: EntityID, visual: String, state: SimState) {
        guard let hero = state.unit(ownerID)?.hero?.heroID, heroes.contains(hero) else { return }
        let stage: String
        if visual == "basic_attack" { stage = "atk_travel" } else if let s = slotFor(visual: visual, hero: hero) { stage = "\(Self.slotName(s))_travel" } else { return }
        guard let n = name(hero, stage) else { return }
        let p = projectiles.info(projectileID)
        let from = p?.pos ?? units.worldPositionOf(ownerID) ?? .zero
        let h = play(n, at: from, forward: p?.forward ?? facing(ownerID, state))
        guard h >= 0 else { return }
        shots[projectileID] = h
        follows.append(Follow(handle: h, target: .projectile(projectileID), offset: .zero, until: time + 6))
        if shots.count > 64 { shots.removeAll() }
    }

    /// 投射物の命中。演出を再生したら true。
    @discardableResult
    func onProjectileHit(projectileID: EntityID, pos: Vec2, state: SimState) -> Bool {
        guard let proj = state.projectiles.first(where: { $0.id == projectileID }),
              let hero = state.unit(proj.ownerID)?.hero?.heroID, heroes.contains(hero) else { return false }
        let info = projectiles.info(projectileID)
        if !proj.pierce, let handle = shots[projectileID] {
            overlay.runtime.stopHandle(handle)
            follows.removeAll { $0.handle == handle }
            shots[projectileID] = nil
        }
        let visual = proj.visual
        let stage = visual == "basic_attack" ? "atk_hit" : (slotFor(visual: visual, hero: hero).map { "\(Self.slotName($0))_impact" } ?? "")
        play(name(hero, stage), at: worldPosition(pos, height: 0.9), forward: info?.forward ?? [0, 0, -1])
        return true
    }

    // MARK: 被弾

    /// ダメージ。通常攻撃（近接）の命中・スキルの被弾の効果を出す。
    func onDamage(_ d: DamageEvent, state: SimState) {
        guard let src = d.sourceID, let u = state.unit(src), let hero = u.hero?.heroID, heroes.contains(hero),
              let victim = units.worldPositionOf(d.targetID) else { return }
        let stage: String
        switch d.source {
        case .basicAttack:
            // 遠隔の通常攻撃は projectileHit で出す。近接だけここで
            guard !Self.isRangedAttacker(u) else { return }
            stage = "atk_hit"
        case .skill(let slot):
            stage = "\(Self.slotName(slot))_hit"
        default:
            return
        }
        guard let n = name(hero, stage) else { return }
        let k = Int(d.targetID) &* 16 &+ stage.hashValue & 15
        if let t = lastHit[k], time - t < 0.12 { return }
        if lastHit.count > 256 { lastHit = lastHit.filter { time - $0.value < 1 } }
        lastHit[k] = time
        let from = units.worldPositionOf(src) ?? victim
        play(n, at: victim + [0, 0.9, 0], forward: Self.flat(victim - from, fallback: facing(src, state)))
    }

    private static func isRangedAttacker(_ u: VelstriaCore.Unit) -> Bool { u.stats.attackRange > 300 }

    /// 発動したスキルの種類（投射物・ゾーンの visual = 演出 ID から）。
    private func slotFor(visual: String, hero: String) -> SkillSlot? {
        for slot in [SkillSlot.skill1, .skill2, .ultimate] where visualMatches(visual, hero: hero, slot: slot) { return slot }
        return nil
    }

    private var slotCache: [String: SkillSlot] = [:]
    private func visualMatches(_ visual: String, hero: String, slot: SkillSlot) -> Bool {
        if let c = slotCache[visual] { return c == slot }
        // 演出 ID: FX_SK_003_2 = ヒーロー 003 の 2 番目（1 パッシブ・2 Skill1・3 Skill2・5 Ult）
        let parts = visual.split(separator: "_")
        guard parts.count == 4, parts[0] == "FX", parts[1] == "SK", let idx = Int(parts[3]) else { return false }
        let mapped: SkillSlot? = idx == 2 ? .skill1 : idx == 3 ? .skill2 : idx == 5 ? .ultimate : nil
        if let mapped { slotCache[visual] = mapped }
        return mapped == slot
    }

    // MARK: 毎フレーム

    func update(dt: Float, state: SimState) {
        time += dt
        var i = 0
        while i < follows.count {
            let f = follows[i]
            var pos: SIMD3<Float>?
            var forward: SIMD3<Float>?
            switch f.target {
            case .unit(let id):
                pos = units.worldPositionOf(id)
                forward = nil
            case .projectile(let id):
                if let info = projectiles.info(id) { pos = info.pos; forward = info.forward }
            }
            if let pos, time < f.until {
                if let forward {
                    overlay.runtime.setPosition(pos + f.offset, yaw: Self.yaw(forward: Self.flat(forward)), forHandle: f.handle)
                } else {
                    overlay.runtime.setLocation(pos + f.offset, forHandle: f.handle)   // 術者への追従は向きを変えない
                }
                i += 1
            } else {
                if case .projectile(let id) = f.target { shots[id] = nil }
                overlay.runtime.stopHandle(f.handle)
                follows.remove(at: i)
            }
        }
    }

    func clear() {
        follows.removeAll()
        shots.removeAll()
        zones.removeAll()
        overlay.runtime.stopAll()
    }
}
