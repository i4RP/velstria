import Foundation
import RealityKit
import VelstriaCore

// 担当: battle-renderer（スキル演出）。sim のイベント → スキル固有演出（SkillFXRecipe）の段の再生。
//   skillCast        → cast（術者）。即時に解決するアーキタイプ（扇・自身中心・味方全体・対象指定ブリンク・
//                      ブリンク強化）は impact もこの場で再生する
//   zoneCreated      → telegraph（予告の中心）。ゾーン ID → スキルを覚える
//   zoneTriggered    → impact（ゾーンの中心。連撃は回ごとに左右反転）
//   projectileLaunched → travel（投射物に追従）
//   projectileHit    → impact（最初の命中だけ）・travel の停止
//   damage(.skill)   → hit（被弾者。同じ相手・同じスキルは 0.15 秒に 1 回）
//   パッシブの発動    → passive の cast（ロールごとの合図から推定。sim はパッシブ専用のイベントを出さない）

@MainActor
final class SkillFXDirector {
    let player: SkillFXPlayer
    private let master: MasterData
    private let units: UnitLayer
    private let projectiles: ProjectileLayer

    private struct SkillKey: Hashable {
        var heroID: String
        var slot: SkillSlot
    }

    private var recipes: [SkillKey: SkillFXRecipe] = [:]
    private var palettes: [String: FXPalette] = [:]
    /// 演出 ID（EffectDef / 投射物・ゾーンの visual）→ スキル。
    private var byEffect: [String: SkillKey] = [:]

    private struct Live {
        var key: SkillKey
        var casterID: EntityID
        var origin: SIMD3<Float>
        var triggers = 0
    }

    private var zones: [EntityID: Live] = [:]
    private var shots: [EntityID: Live] = [:]
    private var lastHit: [Int: Float] = [:]
    private var lastPassive: [EntityID: Float] = [:]
    private var lastCast: [EntityID: (slot: SkillSlot, time: Float)] = [:]
    private var ambushReady: [EntityID: Bool] = [:]
    private var time: Float = 0

    init(master: MasterData, quality: RenderQuality, units: UnitLayer, projectiles: ProjectileLayer) {
        self.master = master
        self.units = units
        self.projectiles = projectiles
        player = SkillFXPlayer(quality: quality)
        player.resolve = { [weak self, weak units, weak projectiles] f in
            switch f {
            case .unit(let id):
                return units?.worldPositionOf(id)
            case .projectile(let id):
                #if DEBUG
                if let p = self?.demo?.shotPosition(id) { return p }
                #endif
                guard var p = projectiles?.info(id)?.pos else { return nil }
                p.y = 0
                return p
            }
        }
    }

    // MARK: 準備（読み込み幕の裏）

    /// 試合のヒーローの全スキルのレシピを組み、画像・材質・プールを作る。
    func prewarm(heroIDs: [String]) {
        var list: [(palette: FXPalette, recipe: SkillFXRecipe)] = []
        for id in Set(heroIDs).sorted() {
            let palette = SkillFXCatalog.palette(id)
            palettes[id] = palette
            for slot in SkillSlot.allCases {
                let r = SkillFXCatalog.recipe(heroID: id, slot: slot, master: master)
                let key = SkillKey(heroID: id, slot: slot)
                recipes[key] = r
                list.append((palette, r))
                if let sk = master.skill(hero: id, slot: slot), !sk.effectID.isEmpty { byEffect[sk.effectID] = key }
            }
        }
        player.prewarm(recipes: list)
    }

    func recipe(heroID: String, slot: SkillSlot) -> SkillFXRecipe? { recipes[SkillKey(heroID: heroID, slot: slot)] }

    private func context(_ key: SkillKey, origin: SIMD3<Float>, caster: SIMD3<Float>, target: SIMD3<Float>,
                         forward: SIMD3<Float>?, follow: SkillFXPlayer.Follow?, variant: Int = 0) -> SkillFXPlayer.Context {
        var f = forward ?? (target - caster)
        f.y = 0
        if simd_length(f) < 1e-3 { f = [0, 0, -1] }
        return SkillFXPlayer.Context(palette: palettes[key.heroID] ?? .from(RGB(1, 1, 1)), origin: origin, caster: caster,
                                     target: target, forward: simd_normalize(f), follow: follow, variant: variant)
    }

    private static func ground(_ v: Vec2) -> SIMD3<Float> { worldPosition(v) }

    /// 術者の向き（xz の単位ベクトル）。
    private func facing(_ id: EntityID, _ s: SimState) -> SIMD3<Float>? {
        guard let u = s.unit(id) else { return nil }
        return [Float(cos(u.facing)), 0, -Float(sin(u.facing))]
    }

    // MARK: イベント

    /// スキル発動。演出を再生したら true（呼び出し側は既定の演出を出さない）。
    @discardableResult
    func onCast(_ c: SkillCastEvent, state: SimState) -> Bool {
        let key = SkillKey(heroID: c.heroID, slot: c.slot)
        guard let r = recipes[key] else { return false }
        lastCast[c.casterID] = (c.slot, time)
        let caster = units.worldPositionOf(c.casterID) ?? SkillFXDirector.ground(c.origin)
        let origin = SkillFXDirector.ground(c.origin)
        let target = SkillFXDirector.ground(c.target)
        var dir = target - origin
        dir.y = 0
        let forward: SIMD3<Float>? = simd_length(dir) > 0.05 ? dir : facing(c.casterID, state)
        let ctx = context(key, origin: caster, caster: caster, target: target, forward: forward, follow: .unit(c.casterID))
        player.play(r.cast, ctx)
        // 即時に解決するアーキタイプは着弾もこの場で
        switch c.archetype {
        case .cone, .selfAoE, .teamHeal:
            player.play(r.impact, ctx)
        case .targetedBlink, .blinkEmpower:
            var hit = ctx
            hit.origin = target
            player.play(r.impact, hit)
        default:
            break
        }
        return true
    }

    func onZoneCreated(zoneID: EntityID, ownerID: EntityID, visual: String, center: Vec2) {
        guard let key = byEffect[visual], let r = recipes[key] else { return }
        let c = SkillFXDirector.ground(center)
        let caster = units.worldPositionOf(ownerID) ?? c
        zones[zoneID] = Live(key: key, casterID: ownerID, origin: caster)
        if zones.count > 64 { zones.removeAll() }
        guard !r.telegraph.isEmpty else { return }
        player.play(r.telegraph, context(key, origin: c, caster: caster, target: c, forward: nil, follow: nil))
    }

    /// ゾーンの発動。演出を再生したら true（呼び出し側は既定の発動演出を出さない）。
    @discardableResult
    func onZoneTriggered(zoneID: EntityID, center: Vec2) -> Bool {
        guard var live = zones[zoneID], let r = recipes[live.key] else { return false }
        let c = SkillFXDirector.ground(center)
        var dir = c - live.origin
        dir.y = 0
        // 連撃（術者に追従するゾーン）は術者の向き
        let forward: SIMD3<Float>? = simd_length(dir) > 0.3 ? dir : nil
        let variant = sameCastIndex(live)
        player.play(r.impact, context(live.key, origin: c, caster: live.origin, target: c, forward: forward,
                                      follow: .unit(live.casterID), variant: variant))
        live.triggers += 1
        zones[zoneID] = live
        return true
    }

    func isSkillZone(_ zoneID: EntityID) -> Bool { zones[zoneID] != nil }

    /// 同じ術者・同じスキルのゾーンが続けて発動した回数（連撃の左右反転用）。
    private func sameCastIndex(_ live: Live) -> Int {
        zones.values.filter { $0.casterID == live.casterID && $0.key == live.key && $0.triggers > 0 }.count
    }

    func onProjectileLaunched(projectileID: EntityID, ownerID: EntityID, visual: String, state: SimState) {
        guard let key = byEffect[visual], let r = recipes[key] else { return }
        let start = units.worldPositionOf(ownerID) ?? .zero
        var forward: SIMD3<Float>?
        if let p = state.projectiles.first(where: { $0.id == projectileID }) {
            if case .linear(let d, _) = p.motion { forward = [Float(d.x), 0, -Float(d.y)] }
        }
        shots[projectileID] = Live(key: key, casterID: ownerID, origin: start)
        if shots.count > 64 { shots.removeAll() }
        player.play(r.travel, context(key, origin: start, caster: start, target: start + (forward ?? [0, 0, -1]) * 6,
                                      forward: forward, follow: .projectile(projectileID)))
    }

    /// 投射物の命中。演出を再生したら true。
    @discardableResult
    func onProjectileHit(projectileID: EntityID, pos: Vec2, state: SimState) -> Bool {
        guard var live = shots[projectileID], let r = recipes[live.key] else { return false }
        let p = SkillFXDirector.ground(pos)
        let pierce = state.projectiles.first(where: { $0.id == projectileID })?.pierce ?? false
        if !pierce { player.stop(follow: .projectile(projectileID)) }
        if live.triggers == 0 {
            var dir = p - live.origin
            dir.y = 0
            player.play(r.impact, context(live.key, origin: p, caster: live.origin, target: p,
                                          forward: simd_length(dir) > 0.2 ? dir : nil, follow: nil))
        }
        live.triggers += 1
        shots[projectileID] = live
        return true
    }

    /// スキルの傷（被弾者ごと）。
    func onDamage(_ d: DamageEvent, state: SimState) {
        guard case .skill(let slot) = d.source, let src = d.sourceID, let hero = state.unit(src)?.hero else { return }
        let key = SkillKey(heroID: hero.heroID, slot: slot)
        guard let r = recipes[key], !r.hit.isEmpty, let victim = units.worldPositionOf(d.targetID) else { return }
        let k = Int(d.targetID) &* 8 &+ slot.rawValue
        if let t = lastHit[k], time - t < 0.15 { return }
        if lastHit.count > 256 { lastHit = lastHit.filter { time - $0.value < 1 } }
        lastHit[k] = time
        let caster = units.worldPositionOf(src) ?? victim
        player.play(r.hit, context(key, origin: victim, caster: caster, target: victim, forward: victim - caster,
                                   follow: .unit(d.targetID)))
    }

    // MARK: パッシブ

    private func passive(_ heroUnit: EntityID, at target: EntityID? = nil, state: SimState, cooldown: Float) {
        guard let hero = state.unit(heroUnit)?.hero else { return }
        if let t = lastPassive[heroUnit], time - t < cooldown { return }
        let key = SkillKey(heroID: hero.heroID, slot: .passive)
        guard let r = recipes[key] else { return }
        lastPassive[heroUnit] = time
        let who = target ?? heroUnit
        guard let p = units.worldPositionOf(who) else { return }
        player.play(r.cast, context(key, origin: p, caster: p, target: p, forward: facing(heroUnit, state), follow: .unit(who)))
    }

    /// パッシブの発動の推定（ロール別の合図）。
    func observe(_ e: SimEvent, state: SimState) {
        switch e {
        case .shieldGained(let target, let source, _):
            // ヴァンガード: 瀕死の自己シールド（境界制圧などスキルのシールドは除く）
            guard source == target, let u = state.unit(target), u.hero?.role == .vanguard else { return }
            if let c = lastCast[target], time - c.time < 0.1 { return }
            passive(target, state: state, cooldown: 2)
        case .statusApplied(let target, let kind, _):
            // デュエリスト: 攻撃速度のスタック
            guard kind == .attackSpeedBoost, state.unit(target)?.hero?.role == .duelist else { return }
            passive(target, state: state, cooldown: 0.9)
        case .damage(let d):
            guard let src = d.sourceID, let u = state.unit(src), let role = u.hero?.role else { return }
            switch role {
            case .ranger:
                if d.isCrit, d.source == .basicAttack { passive(src, state: state, cooldown: 0.5) }
            case .arcanist:
                if d.source.isSkill, state.unit(d.targetID)?.kind == .hero { passive(src, state: state, cooldown: 1.2) }
            case .assassin:
                if ambushReady[src] == true, u.hero?.passive.value ?? 0 < 1, state.unit(d.targetID)?.kind == .hero {
                    ambushReady[src] = false
                    passive(src, at: d.targetID, state: state, cooldown: 0.5)
                }
            default:
                break
            }
        case .heal(let target, let source, let amount):
            // サポート: スキルの後の味方回復
            guard let src = source, amount > 0, src != target, state.unit(src)?.hero?.role == .support else { return }
            passive(src, at: target, state: state, cooldown: 1)
        default:
            break
        }
    }

    #if DEBUG
    /// 目視確認用の実演（-skillDemo）。
    var demo: SkillFXDemo?

    func lastPassiveReset(_ id: EntityID) { lastPassive[id] = nil }
    func passiveForDemo(_ id: EntityID, state: SimState) { passive(id, state: state, cooldown: 0) }

    func launchForDemo(projectileID: EntityID, ownerID: EntityID, visual: String, start: SIMD3<Float>, forward: SIMD3<Float>) {
        guard let key = byEffect[visual], let r = recipes[key] else { return }
        shots[projectileID] = Live(key: key, casterID: ownerID, origin: start)
        player.play(r.travel, context(key, origin: start, caster: start, target: start + forward * 6, forward: forward,
                                      follow: .projectile(projectileID)))
    }

    func hitForDemo(projectileID: EntityID, at p: SIMD3<Float>) {
        guard let live = shots[projectileID], let r = recipes[live.key] else { return }
        player.stop(follow: .projectile(projectileID))
        player.play(r.impact, context(live.key, origin: p, caster: live.origin, target: p, forward: p - live.origin, follow: nil))
    }

    func hitFXForDemo(heroID: String, slot: SkillSlot, casterID: EntityID, at p: SIMD3<Float>) {
        let key = SkillKey(heroID: heroID, slot: slot)
        guard let r = recipes[key] else { return }
        let caster = units.worldPositionOf(casterID) ?? p
        player.play(r.hit, context(key, origin: p, caster: caster, target: p, forward: p - caster, follow: nil))
    }
    #endif

    // MARK: 毎フレーム

    func update(dt: Float, state: SimState) {
        time += dt
        // 奇襲の準備状態（消費された瞬間を捉えるため前フレームの値を覚える）
        for u in state.units where u.kind == .hero {
            guard let h = u.hero, h.role == .assassin else { continue }
            ambushReady[u.id] = h.passive.value >= 1
        }
        player.update(dt: dt)
    }

    func clear() {
        player.clear()
        zones.removeAll()
        shots.removeAll()
        lastHit.removeAll()
    }
}

#if DEBUG
// MARK: - 目視確認用の実演（起動引数 -skillDemo）

/// 操作中のヒーローのパッシブ → S1 → S2 → S3 → 奥義を一定の間隔で順に実演する（sim には書き込まない）。
/// 詠唱モーションを動かし、各段（cast / telegraph / travel / impact / hit）を本番と同じ再生器で出す。
/// `-skillDemoSlot <0-4>` で 1 つのスロットだけを繰り返す。
@MainActor
final class SkillFXDemo {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-skillDemo") }
    static var onlySlot: SkillSlot? {
        DebugLaunch.value(after: "-skillDemoSlot").flatMap { Int($0) }.flatMap { SkillSlot(rawValue: $0) }
    }
    static let period: Float = 3.2

    private var time: Float = 0
    private var next: Float = 6
    private var moved = false
    /// 開始時に泉から開けた場所へ歩かせる（BattleWorld が設定）。
    var walk: (Vec2) -> Void = { _ in }
    private var index = 0
    private var queue: [(time: Float, run: () -> Void)] = []
    private var fakeShots: [EntityID: (start: SIMD3<Float>, dir: SIMD3<Float>, speed: Float, t0: Float, life: Float)] = [:]
    private var nextFakeID: EntityID = 900_000
    private var noteCast: (EntityID, SkillSlot) -> Void = { _, _ in }

    /// 偽の投射物の位置（SkillFXPlayer.resolve から先に引く）。
    func shotPosition(_ id: EntityID) -> SIMD3<Float>? {
        guard let s = fakeShots[id] else { return nil }
        let t = time - s.t0
        guard t <= s.life else { return nil }
        return s.start + s.dir * s.speed * t
    }

    func update(dt: Float, director: SkillFXDirector, units: UnitLayer, master: MasterData, state: SimState,
                humanID: EntityID?, noteCast: @escaping (EntityID, SkillSlot) -> Void) {
        self.noteCast = noteCast
        time += dt
        var k = 0
        while k < queue.count {
            if queue[k].time <= time {
                let q = queue.remove(at: k)
                q.run()
            } else {
                k += 1
            }
        }
        if !moved, let id = humanID, let u = state.unit(id) {
            moved = true
            let dir: Double = u.pos.x < 5000 ? 1 : -1
            walk(u.pos + Vec2(1100 * dir, 900 * dir))
        }
        guard time >= next, let id = humanID, let u = state.unit(id), let hero = u.hero,
              let p = units.worldPositionOf(id) else { return }
        next = time + SkillFXDemo.period
        let slot = SkillFXDemo.onlySlot ?? SkillSlot.allCases[index % SkillSlot.allCases.count]
        index += 1
        play(slot: slot, heroUnit: id, heroID: hero.heroID, at: p, director: director, units: units, master: master,
             state: state)
    }

    private func at(_ dt: Float, _ f: @escaping () -> Void) { queue.append((time + dt, f)) }

    private func play(slot: SkillSlot, heroUnit id: EntityID, heroID: String, at p: SIMD3<Float>,
                      director: SkillFXDirector, units: UnitLayer, master: MasterData, state: SimState) {
        let info = SkillFXCatalog.info(heroID: heroID, slot: slot, master: master)
        // カメラは南から北を見るので、前方 = 北（-Z）へ放つ
        let fwd = SIMD3<Float>(0, 0, -1)
        func vec(_ w: SIMD3<Float>) -> Vec2 { Vec2(Double(w.x) * Balance.unitsPerMeter, Double(-w.z) * Balance.unitsPerMeter) }
        if slot == .passive {
            director.debugPassive(heroUnit: id, state: state)
            return
        }
        noteCast(id, slot)
        let reach: Float
        switch info.archetype {
        case .cone: reach = info.range
        case .dashStrike, .leapSlam: reach = min(5, info.range)
        case .blinkEmpower: reach = 3.5
        case .targetedBlink: reach = 4
        case .groundAoE, .healZone: reach = min(5.5, info.range)
        case .lineSkillshot, .piercingLine: reach = min(9, info.range)
        default: reach = 0
        }
        let target = p + fwd * reach
        let skill = master.skill(hero: heroID, slot: slot)
        let ev = SkillCastEvent(casterID: id, heroID: heroID, slot: slot, skillID: skill?.skillID ?? "",
                                effectID: skill?.effectID ?? "", archetype: info.archetype, origin: vec(p), target: vec(target),
                                range: Double(info.range) * Balance.unitsPerMeter,
                                radius: Double(info.radius) * Balance.unitsPerMeter)
        director.onCast(ev, state: state)
        let visual = skill?.effectID ?? ""
        let zone = nextFakeID
        nextFakeID += 1
        switch info.archetype {
        case .dashStrike, .leapSlam, .groundAoE, .healZone:
            let delay: Float = info.archetype == .dashStrike ? 0.25 : (info.archetype == .leapSlam ? 0.45 : (slot == .ultimate ? 1.0 : 0.6))
            director.onZoneCreated(zoneID: zone, ownerID: id, visual: visual, center: vec(target))
            at(delay) { director.onZoneTriggered(zoneID: zone, center: vec(target)) }
        case .multiStrike:
            for k in 0..<3 {
                let z = zone + EntityID(k) * 100
                director.onZoneCreated(zoneID: z, ownerID: id, visual: visual, center: vec(p))
                at(Float(k) * 0.3) { director.onZoneTriggered(zoneID: z, center: vec(p)) }
            }
        case .lineSkillshot, .piercingLine:
            let speed: Float = info.archetype == .piercingLine ? 22 : 16
            let life = reach / speed
            fakeShots[zone] = (p, fwd, speed, time, life)
            director.debugLaunch(projectileID: zone, ownerID: id, visual: visual, start: p, forward: fwd)
            at(life) { director.debugHit(projectileID: zone, at: target) }
        default:
            break
        }
        // 着弾点の被弾者（演出のみ）
        at(0.3) { director.debugHitFX(heroID: heroID, slot: slot, casterID: id, at: target) }
    }
}

extension SkillFXDirector {
    func debugPassive(heroUnit: EntityID, state: SimState) {
        lastPassiveReset(heroUnit)
        passiveForDemo(heroUnit, state: state)
    }

    func debugLaunch(projectileID: EntityID, ownerID: EntityID, visual: String, start: SIMD3<Float>, forward: SIMD3<Float>) {
        launchForDemo(projectileID: projectileID, ownerID: ownerID, visual: visual, start: start, forward: forward)
    }

    func debugHit(projectileID: EntityID, at p: SIMD3<Float>) {
        hitForDemo(projectileID: projectileID, at: p)
    }

    func debugHitFX(heroID: String, slot: SkillSlot, casterID: EntityID, at p: SIMD3<Float>) {
        hitFXForDemo(heroID: heroID, slot: slot, casterID: casterID, at: p)
    }
}
#endif
