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
//   damage(.skill)   → hit（被弾者。同じ相手・同じスキルは 0.15 秒に 1 回。キットのヒーローの多段ヒットは 0.9 秒に 1 回: hitInterval）
//   パッシブの発動    → passive の cast（ロールごとの合図から推定。sim はパッシブ専用のイベントを出さない。
//                      キットのヒーローはロールの合図を使わず、キットのパッシブのバッジの変化から出す。スタックが増えた / タイマーが始まった
//                      → recipe(.passive).cast、スキルの発動の直後にスタックが尽きた → HeroFXSet.passiveRelease（持つヒーローだけ））
//   再使用の段        → skillCast.stage >= 1 は、ヒーローが段の演出（HeroFXSet.recipe(_:stage:_:)）を持てばそれを使う
//   効果の長さ        → cast と発動と同時の impact のうち durationFromCast の合図（FXEmit の継続放出の duration・FXMesh の life）は
//                      skillCast.duration を使う（0 なら書いた値。上限 FXCue.castDurationLimit）。count・shape はまだ読まない

@MainActor
final class SkillFXDirector {
    let player: SkillFXPlayer
    private let master: MasterData
    private let units: UnitLayer
    private let projectiles: ProjectileLayer

    private struct SkillKey: Hashable {
        var heroID: String
        var slot: SkillSlot
        /// 再使用の段（0 = 共通。段の演出を持つヒーローだけ 1 以上がある）。
        var stage = 0
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
    /// 被弾演出の再生間隔の管理（同じ相手・同じスキル）。
    private struct HitKey: Hashable {
        var target: EntityID
        var heroID: String
        var slot: SkillSlot
    }

    private var lastHit: [HitKey: Float] = [:]
    private var lastPassive: [EntityID: Float] = [:]
    private var lastCast: [EntityID: (slot: SkillSlot, time: Float)] = [:]
    private var ambushReady: [EntityID: Bool] = [:]
    /// キットのパッシブのバッジの前回の値（スタックの増加・タイマーの開始でパッシブの演出、発動の直後のスタックの消費で解放の演出を出す）。
    private var kitPassive: [EntityID: (stacks: Int, timer: Bool)] = [:]
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
                // 再使用の段ごとの演出（持つヒーローだけ）
                for stage in 1...SkillFXCatalog.maxStage {
                    guard let sr = SkillFXCatalog.stageRecipe(heroID: id, slot: slot, stage: stage, master: master) else { continue }
                    recipes[SkillKey(heroID: id, slot: slot, stage: stage)] = sr
                    list.append((palette, sr))
                }
            }
            // パッシブのスタックの解放の演出（持つヒーローだけ。材質を先に作る）
            if let cues = SkillFXCatalog.passiveRelease(heroID: id, released: 1, master: master) {
                var r = SkillFXRecipe()
                r.cast = cues
                list.append((palette, r))
            }
        }
        player.prewarm(recipes: list)
    }

    func recipe(heroID: String, slot: SkillSlot) -> SkillFXRecipe? { recipes[SkillKey(heroID: heroID, slot: slot)] }

    /// このスキルに固有の被弾演出があるか（既定の被弾の火花を重ねない）。
    func hasHitFX(sourceID: EntityID?, slot: SkillSlot, state: SimState) -> Bool {
        guard let id = sourceID, let heroID = state.unit(id)?.hero?.heroID else { return false }
        return !(recipes[SkillKey(heroID: heroID, slot: slot)]?.hit.isEmpty ?? true)
    }

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
        // 再使用の段の演出があればそれ（無ければ共通の演出）
        let r: SkillFXRecipe
        if c.stage > 0, let sr = recipes[SkillKey(heroID: c.heroID, slot: c.slot, stage: c.stage)] {
            r = sr
        } else if let base = recipes[key] {
            r = base
        } else {
            return false
        }
        lastCast[c.casterID] = (c.slot, time)
        let caster = units.worldPositionOf(c.casterID) ?? SkillFXDirector.ground(c.origin)
        let origin = SkillFXDirector.ground(c.origin)
        let target = SkillFXDirector.ground(c.target)
        var dir = target - origin
        dir.y = 0
        let forward: SIMD3<Float>? = simd_length(dir) > 0.05 ? dir : facing(c.casterID, state)
        let ctx = context(key, origin: caster, caster: caster, target: target, forward: forward, follow: .unit(c.casterID))
        // durationFromCast の合図（効果中ずっと続く追従の放出・メッシュ）は長さを発動のイベントから取る（0 なら書いた値）
        player.play(FXCue.applyingCastDuration(r.cast, seconds: c.duration), ctx)
        // 即時に解決するアーキタイプは着弾もこの場で
        switch c.archetype {
        case .cone, .selfAoE, .teamHeal:
            player.play(FXCue.applyingCastDuration(r.impact, seconds: c.duration), ctx)
        case .targetedBlink, .blinkEmpower:
            var hit = ctx
            hit.origin = target
            player.play(FXCue.applyingCastDuration(r.impact, seconds: c.duration), hit)
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
        let k = HitKey(target: d.targetID, heroID: hero.heroID, slot: slot)
        let interval = Self.hitInterval(kitHero: hero.kit != nil, perHit: r.hitPerHit)
        guard Self.hitReplayAllowed(last: lastHit[k], now: time, interval: interval) else { return }
        if lastHit.count > 256 { lastHit = lastHit.filter { time - $0.value < 1 } }
        lastHit[k] = time
        let caster = units.worldPositionOf(src) ?? victim
        player.play(r.hit, context(key, origin: victim, caster: caster, target: victim, forward: victim - caster,
                                   follow: .unit(d.targetID)))
    }

    /// 被弾演出を同じ相手・同じスキルへ再生し直せる最短の間隔（秒）。
    static let plainHitInterval: Float = 0.15
    /// キットのヒーローの多段ヒットのスキル（ゴルムの奥義の 6 連・ボルグの 3 波など）の間隔。1 ヒットごとに hit のレシピ全体を
    /// 重ねない（SkillFXRecipe.hitPerHit を立てた演出を除く）。lastHit のお掃除（1 秒）より短いこと。
    static let kitHitInterval: Float = 0.9

    static func hitInterval(kitHero: Bool, perHit: Bool) -> Float { kitHero && !perHit ? kitHitInterval : plainHitInterval }

    /// 前回の再生（nil = まだ）から interval 以上たっていれば再生してよい。
    static func hitReplayAllowed(last: Float?, now: Float, interval: Float) -> Bool {
        guard let last else { return true }
        return now - last >= interval
    }

    // MARK: パッシブ

    private func passive(_ heroUnit: EntityID, at target: EntityID? = nil, state: SimState, cooldown: Float,
                         fromKit: Bool = false) {
        guard let hero = state.unit(heroUnit)?.hero else { return }
        // キットのヒーローはロールの合図（クリティカル・攻撃速度のスタックなど）が当てはまらない
        if !fromKit, hero.kit != nil { return }
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
    func passiveForDemo(_ id: EntityID, state: SimState) { passive(id, state: state, cooldown: 0, fromKit: true) }

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
        observeKitPassives(state: state)
        player.update(dt: dt)
    }

    /// スタックの解放（消費）の演出を再生する。ヒーローが passiveRelease を持たなければ何もせず false。
    @discardableResult
    private func passiveRelease(_ heroUnit: EntityID, released: Int, state: SimState) -> Bool {
        guard let hero = state.unit(heroUnit)?.hero, hero.kit != nil,
              let cues = SkillFXCatalog.passiveRelease(heroID: hero.heroID, released: released, master: master),
              !cues.isEmpty, let p = units.worldPositionOf(heroUnit) else { return false }
        let key = SkillKey(heroID: hero.heroID, slot: .passive)
        player.play(cues, context(key, origin: p, caster: p, target: p, forward: facing(heroUnit, state),
                                  follow: .unit(heroUnit)))
        return true
    }

    /// キットのパッシブの発動の推定: パッシブのバッジのスタックが増えた、またはタイマーが始まった瞬間に出す
    /// （1 つ目のスタック・追撃の準備・凍結の開始など）。最初に見た値は基準にするだけで出さない。
    /// スキルの発動の直後にスタックが尽きた（ボルグの防御・ゴルムのスタック消費）ときは、passiveRelease の演出を出す
    /// （ヒーローが持たなければ従来どおり何も出さない。同時にタイマーが始まった場合は通常の合図に進む）。
    func observeKitPassives(state: SimState) {
        for u in state.units where u.kind == .hero {
            guard let h = u.hero, h.kit != nil else { continue }
            let now = Self.kitPassiveSample(HeroKits.badge(h, slot: .passive))
            defer { kitPassive[u.id] = now }
            guard let last = kitPassive[u.id], !h.isDead else { continue }
            let sinceCast = lastCast[u.id].map { time - $0.time }
            if Self.kitPassiveReleases(last: last, now: now, sinceCast: sinceCast),
               passiveRelease(u.id, released: last.stacks, state: state) { continue }
            if Self.kitPassiveFires(last: last, now: now) {
                passive(u.id, state: state, cooldown: 0.4, fromKit: true)
            }
        }
    }

    /// パッシブのバッジ → 前回と比べる値（スタックの数・タイマーが動いているか）。
    static func kitPassiveSample(_ badge: KitBadge?) -> (stacks: Int, timer: Bool) {
        guard let badge else { return (0, false) }
        switch badge.kind {
        case .stacks: return (badge.value, false)
        case .timer: return (0, badge.remaining > 0)
        case .form: return (0, false)
        }
    }

    /// スタックが増えた、またはタイマーが始まった瞬間か。
    static func kitPassiveFires(last: (stacks: Int, timer: Bool), now: (stacks: Int, timer: Bool)) -> Bool {
        now.stacks > last.stacks || (now.timer && !last.timer)
    }

    /// 解放の演出の対象にする「スキルの発動の直後」の幅（秒）。
    static let kitReleaseWindow: Float = 0.6

    /// スキルの発動の直後（sinceCast = 発動からの秒。発動が無ければ nil）に、スタックが 1 つ以上から 0 になったか。
    static func kitPassiveReleases(last: (stacks: Int, timer: Bool), now: (stacks: Int, timer: Bool), sinceCast: Float?) -> Bool {
        guard let sinceCast, sinceCast >= 0, sinceCast <= kitReleaseWindow else { return false }
        return last.stacks >= 1 && now.stacks == 0
    }

    func clear() {
        player.clear()
        lastCast.removeAll()
        zones.removeAll()
        shots.removeAll()
        lastHit.removeAll()
        kitPassive.removeAll()
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
