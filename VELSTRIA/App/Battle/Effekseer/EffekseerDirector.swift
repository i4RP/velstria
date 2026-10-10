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
// 例外: キット（ヒーロー固有スキル。docs/SKILL_KITS.md）のヒーローは、スキル（s1/s2/ult/passive）を SkillFX に任せる
// （EffekseerRouting）。通常攻撃（atk_*）は Effekseer のまま。理由は docs/EFFEKSEER.md「キットのヒーローの役割分担」。
// 例外 2: 造形を作り直して atk_* の .efk（旧モデルの武器・配色で作った）と合わなくなったヒーロー（EffekseerRouting.staleAttackHeroes）は、
// 通常攻撃を旧来の演出（HeroFXProfiles: 実際の武器の発射位置・軌跡に付き、色は設計図の glow）に任せる。

/// どのヒーローのどの演出を Effekseer が担当するか（純粋。単体テスト対象）。
/// - 効果（.efk）を持つヒーロー（`heroes`）は、通常攻撃の演出を Effekseer が出す。ただし `attackOptOut` は旧来の演出（HeroFXProfiles）。
/// - スキルは、`skillOptOut`（キットのヒーロー）では SkillFX が出す。.efk は旧来の汎用ロール挙動（アーキタイプ）に合わせて
///   作ったため、キットの実際の挙動（再使用・対象指定・形）と合わない。SkillFX の FX_H025〜H034 は実際の挙動に合わせてある。
struct EffekseerRouting: Equatable {
    /// 効果を持つヒーロー。
    var heroes: Set<String> = []
    /// スキルを SkillFX に任せるヒーロー（heroes の部分集合）。
    var skillOptOut: Set<String> = []
    /// 通常攻撃を旧来の演出（HeroFXProfiles）に任せるヒーロー（heroes の部分集合）。
    var attackOptOut: Set<String> = []

    /// 造形の作り直しで atk_* の .efk と合わなくなったヒーロー（EffekseerDirector の既定の attackOptOut）。
    /// 発射位置は attackLaunchPoint（新しい武器の先端・弓・手）なので全員合っているが、.efk の色・形が旧モデルのまま:
    /// - H025 ルミナ: 翠緑の月光 → 造形・スキルは月光の青
    /// - H027 ジャルド: 銀青の突き → 竜槍の金の炎の穂先（橙）。武器の軌跡（橙）と二重に違う色が出ていた
    /// - H030 ライナ: 桃の星の砲弾 → 腰だめの白い魔砲と水色の動力球（スキルも水色）
    /// - H033 ヴァルド: 深紅の大剣の袈裟斬り → 片手で振る銀の大剣と青い樋（スキルも青）
    /// H026（球電）・H031（素手）・H032（手首の刃の輪）は武器が変わったが、.efk の発射の閃光は発射位置に、近接の弧は術者の前に出るだけで
    /// 武器の形に依らず、色も造形と合うので Effekseer のまま。.efk を新しい造形で作り直したら、ここから外すと Effekseer に戻る。
    static let staleAttackHeroes: Set<String> = ["H025", "H027", "H030", "H033"]

    /// 効果の名前（`H027_s1_cast`）からヒーロー ID（`H027`）。ヒーローの効果でなければ nil（試作の `Zt_*` など）。
    static func heroID(ofEffect n: String) -> String? {
        guard n.count > 5, n.hasPrefix("H"), n[n.index(n.startIndex, offsetBy: 4)] == "_" else { return nil }
        return String(n.prefix(4))
    }

    static func make<S: Sequence>(effectNames: S, skillOptOut isOptOut: (String) -> Bool,
                                  attackOptOut isAttackOptOut: (String) -> Bool = { _ in false }) -> EffekseerRouting
    where S.Element == String {
        var r = EffekseerRouting()
        r.heroes = Set(effectNames.compactMap { heroID(ofEffect: $0) })
        r.skillOptOut = r.heroes.filter(isOptOut)
        r.attackOptOut = r.heroes.filter(isAttackOptOut)
        return r
    }

    /// 通常攻撃（atk_*）の演出を Effekseer が出すか。
    func handlesAttack(_ heroID: String?) -> Bool {
        heroID.map { heroes.contains($0) && !attackOptOut.contains($0) } ?? false
    }

    /// スキル（s1/s2/ult/passive）の演出を Effekseer が出すか。
    func handlesSkill(_ heroID: String?) -> Bool {
        heroID.map { heroes.contains($0) && !skillOptOut.contains($0) } ?? false
    }
}

@MainActor
final class EffekseerDirector {
    private let overlay: EffekseerOverlay
    private unowned let units: UnitLayer
    private unowned let projectiles: ProjectileLayer
    /// スキルを SkillFX に任せるヒーローの判定（既定 = キットのヒーロー）。
    private let skillOptOut: (String) -> Bool
    /// 通常攻撃を旧来の演出（HeroFXProfiles）に任せるヒーローの判定（既定 = EffekseerRouting.staleAttackHeroes）。
    private let attackOptOut: (String) -> Bool
    private(set) var routing = EffekseerRouting()
    /// 効果を持つヒーロー。
    var heroes: Set<String> { routing.heroes }
    /// スキルを SkillFX に任せるヒーロー（効果は通常攻撃だけ）。
    var skillOptOutHeroes: Set<String> { routing.skillOptOut }
    /// 通常攻撃を旧来の演出に任せるヒーロー（通常攻撃の弾の見た目を隠さない）。
    var attackOptOutHeroes: Set<String> { routing.attackOptOut }

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

    init(overlay: EffekseerOverlay, units: UnitLayer, projectiles: ProjectileLayer,
         skillOptOut: @escaping (String) -> Bool = { HeroKits.hasKit($0) },
         attackOptOut: @escaping (String) -> Bool = { EffekseerRouting.staleAttackHeroes.contains($0) }) {
        self.overlay = overlay
        self.units = units
        self.projectiles = projectiles
        self.skillOptOut = skillOptOut
        self.attackOptOut = attackOptOut
        refreshHeroes()
    }

    func refreshHeroes() {
        routing = EffekseerRouting.make(effectNames: overlay.effectNames, skillOptOut: skillOptOut, attackOptOut: attackOptOut)
    }

    /// 通常攻撃の演出を Effekseer が出すヒーローか（attackOptOut のヒーローは false = 旧来の演出）。
    func handles(_ heroID: String?) -> Bool { routing.handlesAttack(heroID) }

    /// スキルの演出を Effekseer が出すヒーローか（キットのヒーローは false = SkillFX）。
    func handlesSkill(_ heroID: String?) -> Bool { routing.handlesSkill(heroID) }

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
        guard let hero = state.unit(src)?.hero?.heroID, routing.handlesAttack(hero) else { return false }
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
        guard routing.handlesSkill(c.heroID) else { return false }
        let s = Self.slotName(c.slot)
        let caster = units.worldPositionOf(c.casterID) ?? worldPosition(c.origin)
        let target = worldPosition(c.target)
        let fwd = Self.flat(target - worldPosition(c.origin), fallback: facing(c.casterID, state))
        let castHandle = play(name(c.heroID, "\(s)_cast"), at: caster, forward: fwd)
        if castHandle >= 0, c.slot == .ultimate || c.archetype == .selfAoE {
            follows.append(Follow(handle: castHandle, target: .unit(c.casterID), offset: .zero, until: time + 12))
        }
        // 即時に解決するアーキタイプは着弾もこの場で。突進・跳躍・地点・連撃は ZoneSystem のゾーン発動（onZoneTriggered）で出す
        switch c.archetype {
        case .cone, .selfAoE, .teamHeal:
            play(name(c.heroID, "\(s)_impact"), at: caster, forward: fwd)
        case .targetedBlink, .blinkEmpower:
            play(name(c.heroID, "\(s)_impact"), at: target, forward: fwd)
        default:
            break
        }
        return true
    }

    func onZoneCreated(zoneID: EntityID, ownerID: EntityID, visual: String, center: Vec2, state: SimState) {
        guard let u = state.unit(ownerID), let hero = u.hero?.heroID, routing.handlesSkill(hero) else { return }
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
        if visual == "basic_attack" {
            guard routing.handlesAttack(hero) else { return }   // 通常攻撃を旧来の演出に任せるヒーローの弾は ProjectileLayer
            stage = "atk_travel"
        } else if routing.handlesSkill(hero), let s = slotFor(visual: visual, hero: hero) {
            stage = "\(Self.slotName(s))_travel"
        } else {
            return   // キットのヒーローのスキルの弾は SkillFX
        }
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
        // キットのヒーローのスキルの弾の命中は SkillFX に任せる（通常攻撃の弾は Effekseer）
        if proj.visual != "basic_attack", !routing.handlesSkill(hero) { return false }
        // 通常攻撃を旧来の演出に任せるヒーローの弾の命中は HeroFXProfiles（BattleWorld）
        if proj.visual == "basic_attack", !routing.handlesAttack(hero) { return false }
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
            // 遠隔の通常攻撃は projectileHit で出す。近接だけここで（旧来の演出に任せるヒーローは BattleWorld の meleeImpact）
            guard routing.handlesAttack(hero), !Self.isRangedAttacker(u) else { return }
            stage = "atk_hit"
        case .skill(let slot):
            guard routing.handlesSkill(hero) else { return }   // キットのヒーローのスキルの被弾は SkillFX
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
