#if DEBUG || TESTER_TOOLS
import Foundation
import VelstriaCore

// 担当: battle-renderer（スキル演出の範囲の検査。docs/vfx/RANGES.md）。
// sim で実際に撃った判定の形（HitShapeScenario: 円・扇・線の幅・帯）と、そのスキルの演出の「範囲を示す部品」の見える縁
// （FXEdge.outline）を、判定の時刻で比べる。判定・数値は読むだけ（sim の規則は変えない）。
//
// 比べ方（RANGES.md「測り方」と同じ）:
// - 判定ごとに、それを出す演出の段（SkillFXDirector と同じ規則: 発動・予告・飛翔・着弾）と原点・前方・時刻を決める。
// - その段の部品のうち、地面に寝かせた（または足元の）縁を持つもの（円い模様・横長の模様の板、帯・弧、円柱などの下端）で、
//   寿命の中で判定の大きさの半分以上になるものを「範囲を示す部品」とする（それより小さい輪は飾り）。
//   円の判定は中心が判定の中心の近く、扇・帯・線の判定は中心が判定の中にある部品だけ。
// - 判定の時刻（部品が後から出るならその出始め）の輪郭で、縁の差を判定の大きさに対する比で測る:
//     円   輪郭の全点の中心からの距離 − 半径
//     扇   輪郭の最も遠い点 − 半径（弧）、扇の外へはみ出す距離
//     帯   前の辺・横の辺まで（部品が示している辺だけ）、帯の外へはみ出す距離
//     線   横の端（弾・突進の幅）、線の外へはみ出す距離
//   ±3%（tolerance）を超えたら食い違い。判定より 1 tick を超えて遅れて出る部品も食い違い（遅れ）。
// - 広がる輪は、判定の時刻より後に判定の外へ出てよいのは消え始めてから（fadeOut の後）だけ。

enum FXRangeAudit {
    /// 許す差（判定の大きさに対する比）。
    static let tolerance: Float = 0.03
    /// 1 tick（判定の時刻はこの刻みに丸まる）。
    static let tick = Float(Balance.dt)
    /// 判定の後に出始める部品を、その判定に結びつける窓（秒）。
    static let lateWindow: Float = 0.12
    /// 寿命の中の最大の大きさが判定のこの比より小さい部品は飾り（範囲を示さない）。
    static let minimumScale: Float = 0.5
    /// 部品がその辺を「示している」とみなす差（帯の辺。これより遠い辺は、その部品が示していない辺）。
    static let showsEdge: Float = 0.15
    /// 調べた比較を 1 つずつ渡す（調査用。nil = 出さない）。
    nonisolated(unsafe) static var log: ((String) -> Void)?

    struct Finding: Hashable, Sendable, CustomStringConvertible {
        enum Kind: String, Sendable {
            /// 判定の時刻の縁の差。
            case edge = "縁"
            /// 判定の外へはみ出す（判定の時刻・その前）。
            case overshoot = "はみ出し"
            /// 判定より遅れて出る。
            case late = "遅れ"
            /// 判定の後、消え始める前に判定の外へ広がる。
            case lingering = "外で消えない"
        }

        var heroID: String
        var slot: SkillSlot
        var stage: Int
        var phase: String
        /// 段の中の合図の番号（0 から）と部品の説明。
        var cue: Int
        var part: String
        var judgment: String
        var kind: Kind
        /// 差（判定の大きさに対する比。+ = 大きい・外・遅い）。遅れは秒。
        var error: Float
        var detail: String

        var skillKey: String { "\(heroID) \(slot)\(stage > 0 ? " stage\(stage)" : "")" }

        var description: String {
            let e = kind == .late ? String(format: "+%.2f 秒", error) : String(format: "%+.1f%%", error * 100)
            return "\(skillKey) \(phase)#\(cue) \(part): \(kind.rawValue) \(e)（\(detail) / 判定 \(judgment)）"
        }
    }

    /// 1 ヒーローの S1・S2・奥義（再使用の段を持つスキルは段も）を撃って調べる。recasts・heroOnly は演出チェックと同じ表。
    static func audit(heroID: String, master: MasterData = .shared,
                      recasts: [String: [SkillSlot: Double]] = FXCheckDriver.recasts,
                      heroOnly: [String: Set<SkillSlot>] = FXCheckDriver.heroOnly) -> [Finding] {
        var out: [Finding] = []
        for slot in [SkillSlot.skill1, .skill2, .ultimate] {
            guard let trace = HitShapeScenario.run(heroID: heroID, slot: slot, recastAfter: recasts[heroID]?[slot],
                                                   targetsHero: heroOnly[heroID]?.contains(slot) == true,
                                                   master: master) else { continue }
            out += audit(trace: trace, master: master)
        }
        return out
    }

    // MARK: - 段の文脈

    enum Phase: String {
        case cast, telegraph, travel, impact
    }

    /// 演出の段の 1 回の再生（SkillFXDirector と同じ原点・前方・追従）。座標は上から見た m（東・北 = sim の x・y ÷ 100）。
    struct Context {
        var phase: Phase
        var stage: Int
        var t0: Double
        var origin: SIMD2<Float>
        var caster: SIMD2<Float>
        var target: SIMD2<Float>
        var forward: SIMD2<Float>
        /// 追従の相手の位置（術者・弾）。nil = 追従しない（.follow は原点）。
        var follow: [HitShapeTrace.Sample]?
        var cues: [FXCue]
    }

    /// 判定 1 つの形（上から見た m）。
    enum Form {
        case circle(center: SIMD2<Float>, radius: Float)
        case cone(apex: SIMD2<Float>, direction: SIMD2<Float>, radius: Float, half: Float)
        /// 凸多角形（反時計回りでも時計回りでもよい）。front = 前の向き（帯の前の辺を決める）。
        case polygon([SIMD2<Float>], front: SIMD2<Float>)
        case line(from: SIMD2<Float>, to: SIMD2<Float>, halfWidth: Float)
    }

    static func meters(_ v: Vec2) -> SIMD2<Float> {
        SIMD2(Float(v.x / Balance.unitsPerMeter), Float(v.y / Balance.unitsPerMeter))
    }

    static func audit(trace: HitShapeTrace, master: MasterData) -> [Finding] {
        let heroID = trace.heroID
        let slot = trace.slot
        let base = SkillFXCatalog.recipe(heroID: heroID, slot: slot, master: master)
        func recipe(_ stage: Int) -> SkillFXRecipe {
            guard stage > 0 else { return base }
            return SkillFXCatalog.stageRecipe(heroID: heroID, slot: slot, stage: stage, master: master) ?? base
        }
        var found: [String: Finding] = [:]
        for (n, j) in trace.shapes.enumerated() {
            // 続きの判定（同じ弾・突進・ゾーン）がある間は、後から出る部品は次の判定のもの
            let next = j.trackID != 0
                ? trace.shapes[(n + 1)...].first { $0.trackID == j.trackID && $0.kind == j.kind && $0.time > j.time + 1e-6 }?.time
                : nil
            guard let castMark = trace.casts.last(where: { $0.time <= j.time + 1e-6 }),
                  case .skillCast(let c) = castMark.event else { continue }
            let r = recipe(c.stage)
            let contexts = Self.contexts(for: j, cast: c, castTime: castMark.time, trace: trace, recipe: r)
            // 弾・突進の掃引・持続するゾーンは毎 tick の判定と比べ、部品ごとに最も大きい差を残す
            for ctx in contexts {
                guard let form = Self.form(j, trace: trace, ctx: ctx) else { continue }
                for f in measure(form: form, judgmentTime: j.time, nextJudgment: next, ctx: ctx, heroID: heroID, slot: slot) {
                    let key = "\(f.skillKey) \(f.phase) \(f.cue) \(f.kind)"
                    if let old = found[key], abs(old.error) >= abs(f.error) { continue }
                    found[key] = f
                }
            }
        }
        return found.values.sorted { ($0.skillKey, $0.phase, $0.cue, $0.kind.rawValue) < ($1.skillKey, $1.phase, $1.cue, $1.kind.rawValue) }
    }

    /// 判定 j を出す演出の段（複数のことがある: ゾーンの発動 = 予告の残り + 着弾）。
    static func contexts(for j: HitShape, cast c: SkillCastEvent, castTime: Double, trace: HitShapeTrace,
                         recipe r: SkillFXRecipe) -> [Context] {
        let north = SIMD2<Float>(0, 1)
        func normalized(_ v: SIMD2<Float>, min: Float, fallback: SIMD2<Float>) -> SIMD2<Float> {
            let l = (v * v).sum().squareRoot()
            return l > min ? v / l : fallback
        }
        let casterAtCast = meters(HitShapeTrace.position(trace.caster, at: castTime) ?? c.origin)
        let castForward = normalized(meters(c.target) - meters(c.origin), min: 0.05, fallback: north)
        func castContext(_ phase: Phase, origin: SIMD2<Float>, cues: [FXCue]) -> Context {
            Context(phase: phase, stage: c.stage, t0: castTime, origin: origin, caster: casterAtCast, target: meters(c.target),
                    forward: castForward, follow: trace.caster,
                    cues: FXCue.applyingCastDuration(cues, seconds: c.duration))
        }
        func event(at t: Double, _ match: (SimEvent) -> Bool) -> HitShapeTrace.Mark? {
            trace.events.first { abs($0.time - t) < 1e-6 && match($0.event) }
        }
        func zoneContexts(zoneID: EntityID, at t: Double) -> [Context] {
            guard let created = trace.events.first(where: {
                if case .zoneCreated(let id, _, _, _, _, _, _, _, _) = $0.event { return id == zoneID }
                return false
            }), case .zoneCreated(_, _, _, _, let center, _, _, _, _) = created.event else { return [] }
            let casterAt = meters(HitShapeTrace.position(trace.caster, at: created.time) ?? center)
            let c0 = meters(center)
            var out = [Context(phase: .telegraph, stage: c.stage, t0: created.time, origin: c0, caster: casterAt,
                               target: c0, forward: normalized(c0 - casterAt, min: 1e-3, fallback: north), follow: nil,
                               cues: r.telegraph)]
            // 着弾の段は最初の発動で 1 回だけ再生される（持続するゾーンの続く判定も、その再生の部品と比べる）
            if let trig = trace.events.first(where: {
                if case .zoneTriggered(let id, _, _) = $0.event { return id == zoneID && $0.time <= t + 1e-6 }
                return false
            }), case .zoneTriggered(_, let tc, _) = trig.event {
                let p = meters(tc)
                out.append(Context(phase: .impact, stage: c.stage, t0: trig.time, origin: p, caster: casterAt, target: p,
                                   forward: normalized(p - casterAt, min: 1e-3, fallback: north), follow: trace.caster,
                                   cues: r.impact))
            }
            return out
        }
        switch j.kind {
        case .zone:
            return zoneContexts(zoneID: j.trackID, at: j.time)
        case .projectile:
            guard let launch = trace.events.first(where: {
                if case .projectileLaunched(let id, _, _) = $0.event { return id == j.trackID }
                return false
            }), let path = trace.projectiles[j.trackID], let first = path.first else { return [] }
            let start = meters(HitShapeTrace.position(trace.caster, at: launch.time) ?? first.pos)
            var forward = castForward
            if path.count >= 2 { forward = normalized(meters(path[1].pos) - meters(path[0].pos), min: 1e-4, fallback: castForward) }
            return [Context(phase: .travel, stage: c.stage, t0: launch.time, origin: start, caster: start,
                            target: start + forward * 6, forward: forward, follow: path, cues: r.travel)]
        case .sweep:
            return [castContext(.cast, origin: casterAtCast, cues: r.cast)]
        case .area, .kit, .single:
            switch c.archetype {
            case .cone, .selfAoE, .teamHeal:
                return [castContext(.impact, origin: casterAtCast, cues: r.impact), castContext(.cast, origin: casterAtCast, cues: r.cast)]
            case .targetedBlink, .blinkEmpower:
                return [castContext(.impact, origin: meters(c.target), cues: r.impact),
                        castContext(.cast, origin: casterAtCast, cues: r.cast)]
            default:
                if let hit = event(at: j.time, { if case .projectileHit = $0 { return true }; return false }),
                   case .projectileHit(let pid, _, let pos) = hit.event {
                    let start = trace.events.first(where: {
                        if case .projectileLaunched(let id, _, _) = $0.event { return id == pid }
                        return false
                    }).flatMap { HitShapeTrace.position(trace.caster, at: $0.time) }.map(meters) ?? casterAtCast
                    let p = meters(pos)
                    return [Context(phase: .impact, stage: c.stage, t0: hit.time, origin: p, caster: start, target: p,
                                    forward: normalized(p - start, min: 0.2, fallback: castForward), follow: nil,
                                    cues: r.impact)]
                }
                if let trig = event(at: j.time, { if case .zoneTriggered = $0 { return true }; return false }),
                   case .zoneTriggered(let id, _, _) = trig.event {
                    return zoneContexts(zoneID: id, at: j.time)
                }
                return [castContext(.cast, origin: casterAtCast, cues: r.cast)]
            }
        }
    }

    /// 判定の形（上から見た m）。単体の命中は範囲を持たないので nil。
    static func form(_ j: HitShape, trace: HitShapeTrace, ctx: Context) -> Form? {
        switch j.form {
        case .circle(let c, let r, _):
            return .circle(center: meters(c), radius: Float(r / Balance.unitsPerMeter))
        case .cone(let c, let d, let r, let half, _):
            let dir = SIMD2(Float(d.x), Float(d.y))
            return .cone(apex: meters(c), direction: dir, radius: Float(r / Balance.unitsPerMeter), half: Float(half))
        case .line(let a, let b, let hw, _):
            // 幅を持たない線（対象の半径だけで当たる突進など）は、見える幅と比べられない
            guard hw / Balance.unitsPerMeter >= 0.05 else { return nil }
            return .line(from: meters(a), to: meters(b), halfWidth: Float(hw / Balance.unitsPerMeter))
        case .polygon(let p):
            return p.count >= 3 ? .polygon(p.map(meters), front: ctx.forward) : nil
        case .unit:
            return nil
        }
    }

    // MARK: - 部品の位置と輪郭

    /// 局所（x = 右、y = 前）の点を、前方 forward・反時計回りの角 yaw（度）で上から見た向きへ。
    static func place(_ p: SIMD2<Float>, yaw deg: Float, forward f: SIMD2<Float>) -> SIMD2<Float> {
        let a = deg * .pi / 180
        let x = p.x * cos(a) - p.y * sin(a)
        let y = p.x * sin(a) + p.y * cos(a)
        let right = SIMD2(f.y, -f.x)
        return right * x + f * y
    }

    /// 地面に寝かせた（足元の）範囲を示せる部品か。raised = 線の判定（弾・突進）: 体の高さの水平な板・立てた板も
    /// 横幅を示す（上から見た横幅は高さに関わらない）。
    static func isGroundPart(_ m: FXMesh, offsetY: Float, raised: Bool = false) -> Bool {
        guard m.pitch == 0, m.roll == 0, m.rise == 0 else { return false }
        if raised { return m.shape != .billboard }
        switch m.shape {
        case .disc, .band, .arc: return offsetY <= 0.35
        case .cylinder, .funnel, .spire, .dome, .sphere: return offsetY <= 0.35
        case .wall: return offsetY <= 0.6
        case .billboard: return false
        }
    }

    /// 1 つの部品の 1 回（合図の繰り返しの k 回目）。
    struct Part {
        var cue: Int
        var mesh: FXMesh
        var start: Float
        var anchor: FXAnchor
        var local: SIMD2<Float>
        var stepYaw: Float
        var label: String

        /// 段の始まりから s 秒の輪郭（上から見た m）。寿命の外なら nil。
        func outline(at s: Float, ctx: Context) -> [SIMD2<Float>]? {
            let age = s - start
            guard age >= -1e-4, age <= mesh.life + 1e-4 else { return nil }
            let t = min(1, max(0, age / max(0.01, mesh.life)))
            guard let shape = FXEdge.outline(mesh, size: mesh.size(at: t)) else { return nil }
            let center = position(at: s, ctx: ctx)
            let yaw = stepYaw + mesh.yawDegrees(at: t)
            return shape.map { center + FXRangeAudit.place($0, yaw: yaw, forward: ctx.forward) }
        }

        /// 段の始まりから s 秒の部品の中心。
        func position(at s: Float, ctx: Context) -> SIMD2<Float> {
            let offset = FXRangeAudit.place(local, yaw: 0, forward: ctx.forward)
            let base: SIMD2<Float>
            switch anchor {
            case .origin: base = ctx.origin
            case .target: base = ctx.target
            case .along(let f): base = ctx.caster + (ctx.target - ctx.caster) * f
            case .follow:
                // 追従するメッシュは毎フレーム相手の位置へ（相手が居なければ原点）
                if let path = ctx.follow, let p = HitShapeTrace.position(path, at: ctx.t0 + Double(s)) {
                    base = FXRangeAudit.meters(p)
                } else {
                    base = ctx.origin
                }
            }
            let age = max(0, s - start)
            let advance = FXRangeAudit.place([0, mesh.advance * age], yaw: stepYaw, forward: ctx.forward)
            return base + offset + advance
        }
    }

    /// 段の合図から、範囲を示せる部品の一覧（繰り返しは 1 回ずつ）。raised = 線の判定（isGroundPart）。
    static func parts(_ ctx: Context, raised: Bool = false) -> [Part] {
        var out: [Part] = []
        for (i, cue) in ctx.cues.enumerated() {
            guard case .mesh(let m) = cue.element else { continue }
            for k in 0..<max(1, cue.count) {
                let step = cue.stepYaw * Float(k)
                var local = cue.offset + cue.stepOffset * Float(k)
                guard isGroundPart(m, offsetY: local.y, raised: raised) else { continue }
                if cue.orbit != 0 {
                    let p = place([local.x, local.z], yaw: step, forward: [0, 1])
                    local = [p.x, local.y, p.y]
                }
                let tex = m.tex.map { "(\($0.rawValue))" } ?? ""
                out.append(Part(cue: i, mesh: m, start: cue.at + cue.every * Float(k), anchor: cue.anchor,
                                local: [local.x, local.z], stepYaw: step, label: "\(m.shape.rawValue)\(tex)"))
            }
        }
        return out
    }

    // MARK: - 測る

    /// 形の大きさ（差を割る値: 円・扇は半径、帯は前後の奥行き、線は半幅）と、部品が中にあるか。
    static func scale(_ f: Form) -> Float {
        switch f {
        case .circle(_, let r): return r
        case .cone(_, _, let r, _): return r
        case .polygon(let p, let front):
            let d = p.map { ($0 * front).sum() }
            return max(0.01, (d.max() ?? 0) - (d.min() ?? 0))
        case .line(_, _, let hw): return max(0.01, hw)
        }
    }

    /// 形の外への距離（m。中なら 0 以下）。
    static func outside(_ p: SIMD2<Float>, _ f: Form) -> Float {
        switch f {
        case .circle(let c, let r):
            return length(p - c) - r
        case .cone(let c, let d, let r, let half):
            let v = p - c
            let dist = length(v)
            guard dist > 1e-4 else { return -r }
            let ang = acos(max(-1, min(1, (v * d).sum() / dist)))
            let lateral = ang > half ? dist * sin(min(.pi / 2, ang - half)) : -1
            return max(dist - r, lateral)
        case .polygon(let poly, _):
            return polygonEdges(poly).map { ($0.normal * p).sum() - $0.offset }.max() ?? 0
        case .line(let a, let b, let hw):
            // 線は横の端だけを見る（弾・突進の 1 tick の区間の前後は次・前の tick の判定）
            return lateral(p, a, b) - hw
        }
    }

    /// 線 a → b（の延長）からの横の距離。
    static func lateral(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let d = b - a
        let l = length(d)
        guard l > 1e-6 else { return length(p - a) }
        return abs(((p - a) * SIMD2(-d.y, d.x)).sum()) / l
    }

    struct Edge {
        var normal: SIMD2<Float>
        var offset: Float
    }

    /// 凸多角形の辺（外向きの法線と、法線方向の位置）。
    static func polygonEdges(_ p: [SIMD2<Float>]) -> [Edge] {
        let c = p.reduce(SIMD2<Float>(0, 0), +) / Float(p.count)
        var out: [Edge] = []
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            let e = b - a
            var n = SIMD2(e.y, -e.x)
            let l = length(n)
            guard l > 1e-6 else { continue }
            n /= l
            if ((c - a) * n).sum() > 0 { n = -n }
            out.append(Edge(normal: n, offset: (a * n).sum()))
        }
        return out
    }

    static func length(_ v: SIMD2<Float>) -> Float { (v * v).sum().squareRoot() }

    static func segmentDistance(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a
        let l2 = (ab * ab).sum()
        let t = l2 > 1e-9 ? min(1, max(0, ((p - a) * ab).sum() / l2)) : 0
        return length(p - (a + ab * t))
    }

    /// 部品が判定に結びつくか。円は中心が判定の中心に近い部品。線（弾・突進の 1 tick の区間）は区間の近く（前後 1 m まで。
    /// 先頭の部品は区間の少し先）。扇・帯は中心が中にある部品と、段の原点（術者の足元）を中心に判定の中まで届く部品
    /// （術者を中心に前へ広がる弧・輪）。
    static func associates(_ center: SIMD2<Float>, outline: [SIMD2<Float>], origin: SIMD2<Float>, _ f: Form) -> Bool {
        switch f {
        case .circle(let c, let r): return length(center - c) <= max(0.3, 0.15 * r)
        case .line(let a, let b, let hw): return segmentDistance(center, a, b) - hw <= 1.0
        default:
            if outside(center, f) <= 0.3 { return true }
            return length(center - origin) <= 0.3 && outline.contains { outside($0, f) < 0 }
        }
    }

    /// 部品の大きさ（判定の大きさと比べる値。円・扇・帯は中心からの最大、線は横の半幅）。
    static func extent(_ outline: [SIMD2<Float>], center: SIMD2<Float>, _ f: Form) -> Float {
        switch f {
        case .line(let a, let b, _):
            let d = b - a
            let l = length(d)
            let n = l > 1e-6 ? SIMD2(-d.y, d.x) / l : SIMD2<Float>(1, 0)
            return outline.map { abs(((($0 - center) * n).sum())) }.max() ?? 0
        default:
            return outline.map { length($0 - center) }.max() ?? 0
        }
    }

    /// 判定の時刻の縁の差（比）。説明つき。
    static func edgeError(_ outline: [SIMD2<Float>], _ f: Form) -> (error: Float, detail: String) {
        let s = scale(f)
        switch f {
        case .circle(let c, let r):
            let d = outline.map { length($0 - c) }
            let lo = d.min() ?? 0, hi = d.max() ?? 0
            let e = abs(hi - r) > abs(lo - r) ? hi - r : lo - r
            return (e / r, String(format: "見える縁 %.2f〜%.2f m", lo, hi))
        case .cone(let c, _, let r, _):
            let far = outline.map { length($0 - c) }.max() ?? 0
            return ((far - r) / r, String(format: "弧 %.2f m", far))
        case .line(let a, let b, let hw):
            let d = b - a
            let l = length(d)
            let n = l > 1e-6 ? SIMD2(-d.y, d.x) / l : SIMD2<Float>(1, 0)
            let side = outline.map { abs((($0 - a) * n).sum()) }.max() ?? 0
            return ((side - hw) / hw, String(format: "見える半幅 %.2f m", side))
        case .polygon(let poly, let front):
            // 部品が示している辺（縁から showsEdge 以内まで届く辺）の差の最大。前・横の辺だけ（後ろの辺は前の帯と重なる）
            var worst: Float = .infinity
            var nearest: Float = .infinity
            var detail = ""
            for e in polygonEdges(poly) where (e.normal * front).sum() > -0.5 {
                let reach = outline.map { ($0 * e.normal).sum() }.max() ?? 0
                let err = (reach - e.offset) / s
                if abs(err) < abs(nearest) { nearest = err }
                guard abs(err) <= showsEdge else { continue }
                if worst == .infinity || abs(err) > abs(worst) {
                    worst = err
                    detail = String(format: "辺まで %+.2f m", reach - e.offset)
                }
            }
            if worst == .infinity { return (nearest, String(format: "どの辺にも届かない（最も近い辺 %+.0f%%）", nearest * 100)) }
            return (worst, detail)
        }
    }

    static func describe(_ f: Form, time: Double) -> String {
        let t = String(format: "@%.2f 秒", time)
        switch f {
        case .circle(_, let r): return String(format: "円 %.2f m ", r) + t
        case .cone(_, _, let r, let half): return String(format: "扇 %.2f m ±%.0f° ", r, half * 180 / .pi) + t
        case .polygon(_, _): return String(format: "帯 奥行き %.2f m ", scale(f)) + t
        case .line(_, _, let hw): return String(format: "線 半幅 %.2f m ", hw) + t
        }
    }

    /// 1 つの判定と、その段の範囲を示す部品を比べる。
    static func measure(form f: Form, judgmentTime: Double, nextJudgment: Double? = nil, ctx: Context, heroID: String,
                        slot: SkillSlot) -> [Finding] {
        let a = Float(judgmentTime - ctx.t0)
        let window = min(a + lateWindow, nextJudgment.map { Float($0 - ctx.t0) - 1e-4 } ?? .infinity)
        let s = scale(f)
        let judgment = describe(f, time: judgmentTime - ctx.t0)
        var out: [Finding] = []
        func finding(_ p: Part, _ kind: Finding.Kind, _ error: Float, _ detail: String) {
            out.append(Finding(heroID: heroID, slot: slot, stage: ctx.stage, phase: ctx.phase.rawValue, cue: p.cue,
                               part: p.label, judgment: judgment, kind: kind, error: error, detail: detail))
        }
        var raised = false
        if case .line = f { raised = true }
        for p in parts(ctx, raised: raised) {
            // 判定の時刻に生きている、または窓の中で出始める部品
            let end = p.start + p.mesh.life
            guard end >= a - 1e-4, p.start <= window else { continue }
            let tm = max(a, p.start)
            guard let outline = p.outline(at: tm, ctx: ctx) else { continue }
            let center = p.position(at: tm, ctx: ctx)
            guard associates(center, outline: outline, origin: ctx.origin, f) else { continue }
            // 飾りの輪（寿命の中の最大でも判定の大きさの半分に届かない）は比べない
            var maxExtent: Float = 0
            var sample = p.start
            while sample <= end + 1e-4 {
                if let o = p.outline(at: sample, ctx: ctx) {
                    maxExtent = max(maxExtent, extent(o, center: p.position(at: sample, ctx: ctx), f))
                }
                sample += 0.02
            }
            guard maxExtent >= minimumScale * s else { continue }
            if p.start > a + tick + 1e-3 { finding(p, .late, p.start - a, String(format: "出始め +%.2f 秒", p.start - a)) }
            let (err, detail) = edgeError(outline, f)
            log?("\(heroID) \(slot) \(ctx.phase.rawValue)#\(p.cue) \(p.label) " + String(format: "@%.2f: %+.1f%% ", tm, err * 100)
                 + detail + " / " + judgment)
            if abs(err) > tolerance { finding(p, .edge, err, detail) }
            // はみ出し: 判定の時刻とその前（予告・広がる途中）に、判定の外へ見える縁が出ていないか
            var over: Float = 0
            sample = max(p.start, a - 1)
            while sample <= tm + 1e-4 {
                if let o = p.outline(at: sample, ctx: ctx) { over = max(over, o.map { outside($0, f) }.max() ?? 0) }
                sample += 0.02
            }
            if over / s > tolerance, err <= tolerance {
                finding(p, .overshoot, over / s, String(format: "外へ %.2f m", over))
            }
            // 広がる輪: 判定の後に外へ出るのは消え始めてから
            sample = tm + 0.02
            while sample <= end + 1e-4 {
                let t = (sample - p.start) / max(0.01, p.mesh.life)
                if t < p.mesh.fadeOut, let o = p.outline(at: sample, ctx: ctx) {
                    let o2 = o.map { outside($0, f) }.max() ?? 0
                    if o2 / s > tolerance {
                        finding(p, .lingering, o2 / s, String(format: "消え始める前に外へ %.2f m（+%.2f 秒）", o2, sample - a))
                        break
                    }
                }
                sample += 0.02
            }
        }
        return out
    }
}
#endif
