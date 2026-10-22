import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer（スキル演出）。FXCue の再生器。
// - 粒子: 汎用の放出体のプール（部品は付けたまま、再生のたびに FXEmit の全項目を書き戻して restart / burst）。
// - メッシュ: 形ごとのエンティティのプール（材質は FXMaterialLibrary のキャッシュを差し替えるだけ）。枠ごとに LowLevelMesh を持ち
//   （FXMeshSlot）、コマ送りのコマ・溶けの進み・模様の種を頂点の色へ書く（材質は作らない）。Blender の模型の形は、試合のレシピが
//   使うものだけプールする。
// - 帯（FXRibbon）: LowLevelMesh の帯のプール（ribbonCapacity）。毎フレーム頂点だけを書き換える（WeaponTrail と同じ作り）。
// - 遅れ・繰り返しは予定表で順に発火し、追従（術者・被弾者・投射物）は毎フレーム位置を読み直す。
// プレイ中は何も作らない: 画像・メッシュ・材質・放出体は prewarm（読み込み幕の裏）で作り切る。プールが尽きたら
// 最も古いものを打ち切って使い回す（追従の継続放出は打ち切らない）。
// 予算による打ち切り・破棄は stats に数え、budgetSnapshot() で性能記録（PerfReport.skillFXBudget）へ出す
// （数え方は docs/SKILL_FX.md「予算の観測」）。数えるだけで、選ぶ順・捨てる動作は変えない。

@MainActor
final class SkillFXPlayer {
    let root = Entity()
    let textures = FXTextureLibrary()
    let meshes = FXMeshLibrary()
    let materials: FXMaterialLibrary
    let sheets = FXSheetLibrary()
    private var quality: RenderQuality
    let poolQuality: RenderQuality

    /// 追従の主体。
    enum Follow: Hashable {
        case unit(EntityID)
        case projectile(EntityID)
    }

    /// 1 回の再生の文脈（world 座標）。
    struct Context {
        var palette: FXPalette
        /// 段の原点。
        var origin: SIMD3<Float>
        /// 術者の位置（along の起点）。
        var caster: SIMD3<Float>
        /// 照準点。
        var target: SIMD3<Float>
        /// 前方（xz の単位ベクトル）。
        var forward: SIMD3<Float>
        var follow: Follow?
        /// 同じ段の何回目か（連撃の 2 撃目など。向きの左右を変えるのに使う）。
        var variant = 0
        /// 演出の出所（予算の集計だけに使う。nil = 不明）。
        var source: Source?
    }

    /// 演出の出所（ヒーロー・スキル・再使用の段）。cast / impact などの段（phase）は持たない。
    struct Source: Hashable, Sendable {
        var heroID: String
        var slot: SkillSlot
        var stage: Int

        var label: String { "\(heroID).\(slot).\(stage)" }
    }

    /// 追従の主体の位置（BattleWorld が設定）。nil = 消えた。
    var resolve: (Follow) -> SIMD3<Float>? = { _ in nil }
    /// 画面の揺れの要求（強さ・位置）。
    var onShake: (Float, SIMD3<Float>) -> Void = { _, _ in }
    /// Effekseer の効果の合図の中継（SkillFXPlayer+Efk.swift）。
    let efk = FXEfkRelay()

    // MARK: プール

    @MainActor
    final class Emitter {
        let entity = Entity()
    }

    private struct EmitInst {
        var emitter: Emitter
        var until: Float
        var follow: Follow?
        var offset: SIMD3<Float>
        var yaw: Float
        var looping: Bool
        var stopAt: Float
        var start: Float = 0
        /// 追従の主体を一度でも見つけたか（投射物は発射の次のフレームに現れる）。
        var seen = false
        var source: Source?
    }

    private struct MeshInst {
        var entity: ModelEntity
        var shape: FXShape
        var spec: FXMesh
        var start: Float
        var base: SIMD3<Float>
        var yaw: Float
        var follow: Follow?
        var offset: SIMD3<Float>
        var ground: Bool
        var source: Source?
        /// 加算の明るさの段階の材質を選ぶための色（加算だけ）。
        var palette: FXPalette?
        /// いま付けている加算の明るさの段階（0 = 隠している、加算でなければ使わない）。
        var level = 0
        /// 頂点の色を書く枠（コマ・溶け・種）。
        var slot: FXMeshSlot?
        /// 模様の種（溶けを使うメッシュだけ。ほかは 0 = 従来どおり）。
        var seed: UInt8 = 0
    }

    private struct Pending {
        var time: Float
        var cue: FXCue
        var ctx: Context
        var index: Int
    }

    private var freeEmitters: [Emitter] = []
    private var emitterCount = 0
    private var emits: [EmitInst] = []
    private var freeMeshes: [FXShape: [ModelEntity]] = [:]
    private var meshInsts: [MeshInst] = []
    /// プールのメッシュの枠（エンティティ → 頂点の色を書く LowLevelMesh）。
    private var slotOf: [ObjectIdentifier: FXMeshSlot] = [:]
    private var seedCounter: UInt8 = 0
    private var freeRibbons: [RibbonSlot] = []
    private var ribbons: [RibbonInst] = []
    private var ribbonCount = 0
    private var pending: [Pending] = []
    private var time: Float = 0
    private var prewarmed = false
    private lazy var blank: ParticleEmitterComponent = {
        AssetLedger.record(.emitter, "skillfx blank")
        return ParticleEmitterComponent()
    }()

    /// 1 種類の枠（粒子放出体・形ごとのメッシュ）の取得の集計。1 回の要求は受理（空き / 打ち切り / 回収待ちの引き取り /
    /// 準備前の追加生成）か拒否のどれか 1 つに数える。
    struct PoolStats: Codable, Equatable, Sendable {
        /// 取得要求（spawn の回数）。
        var requests = 0
        /// 空きが無く、寿命の途中の演出を打ち切って受理した回数（打ち切った 1 回を取得側だけで数える）。
        var cut = 0
        /// 空きが無く、寿命を過ぎて回収待ちだった枠をそのまま使った回数（正常終了。打ち切りではない）。
        var reclaimed = 0
        /// 空きも打ち切れる演出も無く、要求を捨てた回数。
        var rejected = 0
        /// prewarm の前でプールに無く、新しく作った回数（試合中は 0。作れば AssetLedger の live にも出る）。
        var grown = 0
        /// 使用中の枠の数の最大（受理した直後に測る）。
        var peakInUse = 0
    }

    /// 演出を失った側の出所ごとの集計（打ち切りは打ち切られた側、拒否・合図の破棄は要求した側）。
    struct SourceStats: Codable, Equatable, Sendable {
        var emitterCut = 0
        var emitterRejected = 0
        var meshCut = 0
        var meshRejected = 0
        var cuesOverPerPlay = 0
        var cuesOverPending = 0
    }

    /// 再生の集計。clear() で 0 に戻る（幕が上がる直前の片付け・シークや再同期での作り直し・破棄）。
    /// clear・stop・cut で消えた演出、寿命を終えて空きに戻った枠の再利用は、打ち切り・破棄に数えない。
    struct Stats {
        var plays = 0
        /// 粒子放出体（ParticleEmitterComponent 1 つの枠。生きている粒子の数ではない）。
        var emitters = PoolStats()
        /// 形ごとのメッシュ。
        var meshShapes: [FXShape: PoolStats] = [:]
        /// 使用中のメッシュの合計（形をまたいだ同時数）の最大。
        var peakMeshes = 0
        /// 従来の合計（1 回の再生の上限と予約の上限の両方を粗く数える）。原因の切り分けは下の 2 つを使う。
        var droppedCues = 0
        /// 1 回の再生の上限（BattleWorkBudget.cuesPerPlay）で受け付けなかった合図（繰り返しは 1 回ずつ。画質で出さない合図は含まない）。
        var cuesOverPerPlay = 0
        /// 遅延予約の上限（BattleWorkBudget.pendingCues）が埋まっていて捨てた合図。
        var cuesOverPending = 0
        var peakPending = 0
        /// 出所ごと（nil = 不明）。キーは試合のヒーローのスキルの数までしか増えない。
        var bySource: [Source?: SourceStats] = [:]
        /// 帯（FXRibbon）の枠。
        var ribbons = PoolStats()

        /// 打ち切った回数（回収待ちの引き取りは含まない）。
        var stolenEmitters: Int { emitters.cut }
        var stolenMeshes: Int { meshShapes.values.reduce(0) { $0 + $1.cut } }
        var peakEmitters: Int { emitters.peakInUse }

        /// 形をまたいだメッシュの合計（peakInUse は同時数の最大）。
        var meshes: PoolStats {
            var t = PoolStats()
            for s in meshShapes.values {
                t.requests += s.requests
                t.cut += s.cut
                t.reclaimed += s.reclaimed
                t.rejected += s.rejected
                t.grown += s.grown
            }
            t.peakInUse = peakMeshes
            return t
        }
    }
    private(set) var stats = Stats()

    init(quality: RenderQuality) {
        self.quality = quality
        poolQuality = quality
        materials = FXMaterialLibrary(textures: textures, sheets: sheets)
        root.name = "skillfx"
        emits.reserveCapacity(64)
        meshInsts.reserveCapacity(128)
        pending.reserveCapacity(BattleWorkBudget.pendingCues)
    }

    func apply(quality q: RenderQuality) { quality = q }

    var pendingCount: Int { pending.count }

    var activeCount: Int { emits.count + meshInsts.count + ribbons.count }

    /// 予算の集計の写し（性能記録 PerfReport.skillFXBudget。docs/SKILL_FX.md「予算の観測」）。呼んでも 0 には戻さない。
    func budgetSnapshot() -> SkillFXBudgetSnapshot {
        var shapes: [String: SkillFXBudgetSnapshot.Pool] = [:]
        for s in FXShape.allCases {
            let inUse = meshInsts.reduce(0) { $1.shape == s ? $0 + 1 : $0 }
            shapes[s.rawValue] = SkillFXBudgetSnapshot.Pool(pooled: inUse + (freeMeshes[s]?.count ?? 0), inUse: inUse,
                                                            counts: stats.meshShapes[s] ?? PoolStats())
        }
        var sources: [String: SourceStats] = [:]
        for (k, v) in stats.bySource { sources[k?.label ?? "unknown"] = v }
        let cues = SkillFXBudgetSnapshot.Cues(perPlayLimit: BattleWorkBudget.cuesPerPlay,
                                              pendingLimit: BattleWorkBudget.pendingCues,
                                              overPerPlay: stats.cuesOverPerPlay, overPending: stats.cuesOverPending,
                                              pending: pending.count, peakPending: stats.peakPending)
        return SkillFXBudgetSnapshot(
            quality: "\(quality.level)", poolQuality: "\(poolQuality.level)", plays: stats.plays,
            emitters: SkillFXBudgetSnapshot.Pool(pooled: emitterCount, inUse: emits.count, counts: stats.emitters),
            meshes: SkillFXBudgetSnapshot.Pool(pooled: shapes.values.reduce(0) { $0 + $1.pooled }, inUse: meshInsts.count,
                                               counts: stats.meshes),
            meshShapes: shapes, cues: cues, bySource: sources)
    }

    /// 放出体のプールの大きさ（粒子系 1 つ ≒ 1 MB を常に持つので画質で決める）。
    static func emitterCapacity(_ q: RenderQuality) -> Int {
        switch q.level {
        case .low: return 10
        case .medium: return 22
        case .high: return 34
        }
    }

    /// 形ごとのメッシュのプールの大きさ。
    static func meshCapacity(_ s: FXShape, _ q: RenderQuality) -> Int {
        let base: Int
        switch s {
        case .disc: base = 28
        case .arc: base = 12
        case .billboard: base = 12
        case .cylinder, .sphere: base = 10
        case .wall, .band: base = 8
        case .dome, .spire, .funnel: base = 5
        // 模型（試合のレシピが使うものだけプールする）
        case .crescent, .ringLip: base = 6
        case .burstDome, .pillar2: base = 4
        case .twister, .bladeRing, .starCross, .shardRing: base = 3
        // スキルの攻撃の模型（1 ヒーローのスキル 1 つにつき 1 つ。重なる再使用の分）
        case .sk025s1, .sk025s2, .sk025ult, .sk026s1, .sk026s2, .sk026ult, .sk027s1, .sk027s2, .sk027ult, .sk028s1, .sk028s2, .sk028ult, .sk029s1, .sk029s2, .sk029ult, .sk030s1, .sk030s2, .sk030ult, .sk031s1, .sk031s2, .sk031ult, .sk032s1, .sk032s2, .sk032ult, .sk033s1, .sk033s2, .sk033ult, .sk034s1, .sk034s2, .sk034ult, .sk025s1b, .sk025s2b, .sk025ultb, .sk026s1b, .sk026s2b, .sk026ultb, .sk027s1b, .sk027s2b, .sk027ultb, .sk028s1b, .sk028s2b, .sk028ultb, .sk029s1b, .sk029s2b, .sk029ultb, .sk030s1b, .sk030s2b, .sk030ultb, .sk032s1b, .sk032s2b, .sk032ultb, .sk033s1b, .sk033s2b, .sk033ultb, .sk034s1b, .sk034s2b, .sk034ultb: base = 2
        }
        return q.level == .low ? max(2, base / 2) : base
    }

    /// 帯（FXRibbon）のプールの大きさ（レシピが帯を使う試合だけ作る）。
    static func ribbonCapacity(_ q: RenderQuality) -> Int {
        switch q.level {
        case .low: return 2
        case .medium: return 4
        case .high: return 6
        }
    }

    /// コマ送りのメッシュの今のコマ（0〜frames − 1）。1 回の画像は寿命で全コマ、繰り返す画像は sheetFPS か loopFPS で回す。
    nonisolated static func sheetFrame(_ m: FXMesh, _ sheet: FXSheet, age: Float) -> Int {
        let n = sheet.frames
        let fps = m.sheetFPS > 0 ? m.sheetFPS : (sheet.loops ? sheet.loopFPS : Float(n) / max(0.05, m.life))
        let f = Int((max(0, age) * fps).rounded(.down))
        return sheet.loops ? ((f % n) + n) % n : min(n - 1, max(0, f))
    }

    /// 溶けの進み（0〜1。寿命の比 from から 1 へ）。
    nonisolated static func dissolveAmount(_ d: FXDissolve, t: Float) -> Float {
        guard t > d.from else { return 0 }
        return min(1, (t - d.from) / max(0.001, 1 - d.from))
    }

    /// コマ送りの速さ（コマ / 秒）: 指定が無ければ、1 回の画像は粒子の寿命で 16 コマを流し、繰り返す画像は FXSheet.loopFPS。
    nonisolated static func sheetFPS(_ e: FXEmit, _ sheet: FXSheet) -> Float {
        if e.sheetFPS > 0 { return e.sheetFPS }
        return sheet.loops ? sheet.loopFPS : Float(sheet.frames) / max(0.05, e.life)
    }

    static func qualityRank(_ q: RenderQuality) -> Int {
        switch q.level {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    // MARK: 事前生成（読み込み幕の裏）

    /// シートの使い方（合成で版が違う。FXSheetLibrary）。
    private struct SheetUse: Hashable {
        var sheet: FXSheet
        var additive: Bool
    }

    /// 加算・模様・コマ送り・溶けの材質（CustomMaterial）を使うか。
    private static func usesShaded(_ m: FXMesh) -> Bool {
        m.blend == .add || m.flow != nil || m.sheet != nil || m.dissolve != nil
    }

    /// 試合のヒーローのレシピが使う画像・材質と、全てのプールを作る（Blender の大きな画像・模型・帯はレシピが使うものだけ）。
    func prewarm(recipes: [(palette: FXPalette, recipe: SkillFXRecipe)]) {
        // 使う画像・シート・模型を先に集める（材質が画像を引く前に作る）
        var sheetUses = Set<SheetUse>()
        // Blender の大きな画像は使う版だけ作る（メッシュ = 白 + アルファ、加算の粒子 = 輝度、アルファ合成の粒子 = 色にアルファ）
        var bundledTex = Set<FXTex>()
        var bundledGlow = Set<FXTex>()
        var bundledParticle = Set<FXTex>()
        var models = Set<FXShape>()
        var usesRibbons = false
        for (_, r) in recipes {
            for cue in r.all {
                switch cue.element {
                case .mesh(let m):
                    if let s = m.sheet { sheetUses.insert(SheetUse(sheet: s, additive: m.blend == .add)) }
                    if let t = m.tex, t.bundled != nil { bundledTex.insert(t) }
                    if m.shape.isModel { models.insert(m.shape) }
                case .emit(let e):
                    if let s = e.sheet { sheetUses.insert(SheetUse(sheet: s, additive: e.additive)) }
                    if e.tex.bundled != nil {
                        if e.additive { bundledGlow.insert(e.tex) } else { bundledParticle.insert(e.tex) }
                    }
                case .ribbon(let rb):
                    usesRibbons = true
                    if let t = rb.tex, t.bundled != nil { bundledTex.insert(t) }
                case .shake, .efk:
                    break
                }
            }
        }
        textures.prewarm(FXTex.allCases.filter { $0.bundled == nil })
        for t in bundledTex.sorted(by: { $0.rawValue < $1.rawValue }) { _ = textures.texture(t) }
        for t in bundledGlow.sorted(by: { $0.rawValue < $1.rawValue }) { _ = textures.glowTexture(t) }
        for t in bundledParticle.sorted(by: { $0.rawValue < $1.rawValue }) { _ = textures.particleTexture(t) }
        for u in sheetUses.sorted(by: { ($0.sheet.rawValue, $0.additive ? 1 : 0) < ($1.sheet.rawValue, $1.additive ? 1 : 0) }) {
            sheets.prewarm(u.sheet, additive: u.additive)
        }
        meshes.prewarm()
        for s in models.sorted(by: { $0.rawValue < $1.rawValue }) { _ = meshes.mesh(s) }
        _ = blank
        for (palette, r) in recipes {
            for cue in r.all {
                switch cue.element {
                case .mesh(let m):
                    // 従来の材質は必ず作る（加算・模様の Program が無い時の代わり）
                    _ = materials.material(m.tex, palette.rgb(m.tint), onTop: m.onTop)
                    if SkillFXPlayer.usesShaded(m) { shadedPending.append((m, palette)) }
                case .ribbon(let rb):
                    let look = rb.look
                    _ = materials.material(look.tex, palette.rgb(look.tint), onTop: look.onTop)
                    if SkillFXPlayer.usesShaded(look) { shadedPending.append((look, palette)) }
                case .efk(let x):
                    efk.note(x)
                case .emit, .shake:
                    break
                }
            }
        }
        _ = prewarmShaded()
        let n = SkillFXPlayer.emitterCapacity(poolQuality)
        while emitterCount < n { freeEmitters.append(makeEmitter()) }
        for s in FXShape.allCases where !s.isModel || (models.contains(s) && meshes.geometry(s) != nil) {
            var list = freeMeshes[s] ?? []
            while list.count < SkillFXPlayer.meshCapacity(s, poolQuality) { list.append(makeMesh(s)) }
            freeMeshes[s] = list
        }
        if usesRibbons {
            while ribbonCount < SkillFXPlayer.ribbonCapacity(poolQuality) {
                guard let r = RibbonSlot.make() else { break }
                AssetLedger.record(.mesh, "skillfx ribbon")
                AssetLedger.record(.entity, "skillfx ribbon")
                ribbonCount += 1
                root.addChild(r.entity)
                freeRibbons.append(r)
            }
        }
        prewarmed = true
    }

    /// 加算・模様の材質（CustomMaterial）の作り残し。Program が出来るまで待つ（BattleRenderer の warmupGates が幕の前に呼ぶ）。
    private var shadedPending: [(FXMesh, FXPalette)] = []

    /// 加算・模様の材質を作る。Program が出来ていれば作り終えて true、作れないと決まった（failed）ときも true
    /// （従来の材質で代える）。まだ作っている途中なら false。
    @discardableResult
    func prewarmShaded() -> Bool {
        guard !shadedPending.isEmpty else { return true }
        guard FXPrograms.isSettled else { return false }
        if FXPrograms.isReady {
            for (m, palette) in shadedPending { materials.prewarm(m, palette: palette) }
        }
        shadedPending.removeAll()
        return true
    }

    /// 幕を上げる時に呼ぶ。Program が幕に間に合わず加算・模様の材質を作り切れていなければ、この試合は従来の材質で出す
    /// （幕の後に Program が出来ても、プレイ中に CustomMaterial を作らない）。作り切れていれば true。
    @discardableResult
    func sealShadedMaterials() -> Bool {
        if prewarmShaded() { return true }
        shadedPending.removeAll()
        materials.createsShaded = false
        return false
    }

    private func makeEmitter() -> Emitter {
        AssetLedger.record(.entity, "skillfx emitter")
        AssetLedger.record(.emitter, "skillfx")
        emitterCount += 1
        let em = Emitter()
        var c = ParticleEmitterComponent()
        configure(&c, FXEmit(), palette: .from(RGB(1, 1, 1)))
        c.isEmitting = false
        em.entity.components.set(c)
        em.entity.isEnabled = false
        root.addChild(em.entity)
        return em
    }

    private func makeMesh(_ s: FXShape) -> ModelEntity {
        AssetLedger.record(.entity, "skillfx \(s.rawValue)")
        // 枠ごとの LowLevelMesh（頂点の色を 1 体ごとに書く）。作れなければ共通のメッシュ（頂点の色は既定値）
        let slot = meshes.makeSlot(s)
        let m = ModelEntity(mesh: slot?.resource ?? meshes.mesh(s) ?? MeshResource.generateBox(size: 0.01), materials: [])
        if let slot { slotOf[ObjectIdentifier(m)] = slot }
        if s == .billboard { m.components.set(BillboardComponent()) }
        m.components.set(DynamicLightShadowComponent(castsShadow: false))
        m.isEnabled = false
        root.addChild(m)
        return m
    }

    // MARK: 再生

    /// 段の合図を全て予定に入れる（遅れ 0 のものはこの場で発火）。
    func play(_ cues: [FXCue], _ ctx: Context) {
        guard !cues.isEmpty else { return }
        stats.plays += 1
        let rank = SkillFXPlayer.qualityRank(quality)
        stats.droppedCues += max(0, cues.count - BattleWorkBudget.cuesPerPlay)
        var remaining = BattleWorkBudget.cuesPerPlay
        var admittedTotal = 0
        for cue in cues.prefix(BattleWorkBudget.cuesPerPlay) where cue.minQuality <= rank {
            guard remaining > 0 else { stats.droppedCues += 1; break }
            let requested = max(1, cue.count)
            let admitted = min(requested, remaining)
            stats.droppedCues += requested - admitted
            remaining -= admitted
            admittedTotal += admitted
            for k in 0..<admitted {
                let t = cue.at + cue.every * Float(k)
                if t <= 0.0001 {
                    fire(cue, ctx, index: k)
                } else if pending.count < BattleWorkBudget.pendingCues {
                    pending.append(Pending(time: time + t, cue: cue, ctx: ctx, index: k))
                    stats.peakPending = max(stats.peakPending, pending.count)
                } else {
                    stats.droppedCues += 1
                    stats.cuesOverPending += 1
                    stats.bySource[ctx.source, default: SourceStats()].cuesOverPending += 1
                }
            }
        }
        // 1 回の再生の上限で受け付けなかった合図 = この画質で出す合図（繰り返しは 1 回ずつ）のうち、受け付けなかった数
        let wanted = cues.reduce(0) { $1.minQuality <= rank ? $0 + max(1, $1.count) : $0 }
        if wanted > admittedTotal {
            stats.cuesOverPerPlay += wanted - admittedTotal
            stats.bySource[ctx.source, default: SourceStats()].cuesOverPerPlay += wanted - admittedTotal
        }
    }

    /// 追従の継続放出を止める（投射物の着弾・消滅、術者の死亡）。メッシュの追従は最後の位置に残す。
    func stop(follow f: Follow) {
        for k in emits.indices where emits[k].follow == f && emits[k].looping {
            stopEmitting(k)
        }
        for k in meshInsts.indices where meshInsts[k].follow == f {
            meshInsts[k].follow = nil
        }
        // 追従の帯は頭をそこで止める（通った所は寿命で尾から消える）
        for k in ribbons.indices where ribbons[k].follow == f {
            ribbons[k].follow = nil
            ribbons[k].headEnd = min(ribbons[k].headEnd, time)
        }
        pending.removeAll { $0.ctx.follow == f && $0.cue.anchor == .follow }
    }

    /// 追従しているメッシュのうち FXMesh.group が g のものを fade 秒で消し、まだ出ていない同じ組の合図も取り消す
    /// （sim の数が減ったとき。H028 の環剣で剣を 1 本使ったら、その刃を消す）。g = 0 は何もしない。
    func cut(follow f: Follow, group g: Int, fade: Float = 0.12) {
        guard g != 0 else { return }
        for k in meshInsts.indices where meshInsts[k].follow == f && meshInsts[k].spec.group == g {
            var m = meshInsts[k].spec
            let age = max(0, time - meshInsts[k].start)
            // もう消え始めている（寿命の終わりの fadeOut に入った）ものはそのまま
            guard m.life > 0.01, age / m.life < m.fadeOut else { continue }
            // fadeIn・fadeOut は寿命に対する比なので、秒に直してから新しい寿命の比に戻す（回転・上昇は経過の秒で決まるので変わらない）
            let fadeInSeconds = m.fadeIn * m.life
            let end = age + max(0.02, fade)
            m.life = end
            m.fadeIn = min(1, fadeInSeconds / end)
            m.fadeOut = min(1, age / end)
            meshInsts[k].spec = m
        }
        pending.removeAll { p in
            guard p.ctx.follow == f, case .mesh(let m) = p.cue.element else { return false }
            return m.group == g
        }
    }

    private func stopEmitting(_ k: Int) {
        let e = emits[k]
        if var c = e.emitter.entity.components[ParticleEmitterComponent.self] {
            c.isEmitting = false
            e.emitter.entity.components.set(c)
        }
        emits[k].looping = false
        emits[k].until = min(e.until, time + 0.8)
    }

    // MARK: 発火

    /// 局所の向き（前方の yaw + 加算の度）。
    private static func yaw(of forward: SIMD3<Float>) -> Float { atan2(-forward.x, -forward.z) }

    private static func rotate(_ v: SIMD3<Float>, yaw: Float) -> SIMD3<Float> {
        // 局所（右・上・前）→ world。前 = -Z を yaw だけ回す
        let c = cos(yaw), s = sin(yaw)
        let local = SIMD3<Float>(v.x, v.y, -v.z)
        return SIMD3(local.x * c + local.z * s, local.y, -local.x * s + local.z * c)
    }

    private func anchorPosition(_ a: FXAnchor, _ ctx: Context) -> SIMD3<Float> {
        switch a {
        case .origin: return ctx.origin
        case .follow: return ctx.follow.flatMap { resolve($0) } ?? ctx.origin
        case .target: return ctx.target
        case .along(let t): return ctx.caster + (ctx.target - ctx.caster) * t
        }
    }

    private func fire(_ cue: FXCue, _ ctx: Context, index k: Int) {
        let baseYaw = SkillFXPlayer.yaw(of: ctx.forward)
        let stepYaw = cue.stepYaw * Float(k) * .pi / 180
        // 位置: 輪状の配置（orbit）は向きと一緒に回す
        var local = cue.offset + cue.stepOffset * Float(k)
        if cue.orbit != 0 {
            let r = SkillFXPlayer.rotate(local, yaw: stepYaw)
            local = SIMD3(r.x, r.y, -r.z)
        }
        let yaw = baseYaw + stepYaw
        let anchor = anchorPosition(cue.anchor, ctx)
        let worldOffset = SkillFXPlayer.rotate(local, yaw: baseYaw)
        let follow: Follow? = cue.anchor == .follow ? ctx.follow : nil
        switch cue.element {
        case .shake(let s):
            onShake(s, anchor)
        case .efk(let x):
            efk.fire(x, at: anchor + worldOffset, yaw: yaw, follow: follow, offset: worldOffset)
        case .emit(let e):
            spawnEmit(e, at: anchor + worldOffset, yaw: yaw, follow: follow, offset: worldOffset, ctx: ctx)
        case .mesh(var m):
            // 連撃の偶数回は左右反転（掃く向きを交互に）
            if ctx.variant % 2 == 1 {
                m.yaw = -m.yaw
                m.yawEnd = m.yawEnd.map { -$0 }
                m.roll = -m.roll
            }
            spawnMesh(m, at: anchor + worldOffset, yaw: yaw, follow: follow, offset: worldOffset, ctx: ctx,
                      groundLevel: local.y < 0.05 && anchor.y < 0.3)
        case .ribbon(var r):
            // 連撃の偶数回は水平に近い弧を左右反転（縦の弧は上下が入れ替わるので反転しない）
            if ctx.variant % 2 == 1, case .arc(let radius, let from, let to, let height, let roll) = r.path, abs(roll) < 45 {
                r.path = .arc(radius: radius, from: -from, to: -to, height: height, roll: roll)
            }
            spawnRibbon(r, at: anchor + worldOffset, yaw: yaw, follow: follow, offset: worldOffset, ctx: ctx)
        }
    }

    private func spawnEmit(_ e: FXEmit, at p: SIMD3<Float>, yaw: Float, follow: Follow?, offset: SIMD3<Float>, ctx: Context) {
        stats.emitters.requests += 1
        let em: Emitter
        if let free = freeEmitters.popLast() {
            em = free
        } else if prewarmed {
            // 最も早く終わる一斉放出を打ち切る（継続放出は残す）
            guard let k = emits.indices.filter({ !emits[$0].looping }).min(by: { emits[$0].until < emits[$1].until }) else {
                stats.emitters.rejected += 1
                stats.bySource[ctx.source, default: SourceStats()].emitterRejected += 1
                return
            }
            em = emits[k].emitter
            // 寿命を過ぎて回収（update）を待っていた枠は正常終了。寿命の途中なら打ち切り（打ち切られた側の出所に数える）
            if emits[k].until <= time {
                stats.emitters.reclaimed += 1
            } else {
                stats.emitters.cut += 1
                stats.bySource[emits[k].source, default: SourceStats()].emitterCut += 1
            }
            emits.swapAt(k, emits.count - 1)
            emits.removeLast()
        } else {
            stats.emitters.grown += 1
            em = makeEmitter()
        }
        var c = em.entity.components[ParticleEmitterComponent.self] ?? blank
        configure(&c, e, palette: ctx.palette)
        em.entity.position = p
        em.entity.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        if e.rate > 0 {
            c.isEmitting = true
            c.restart()
        } else {
            c.isEmitting = false
            c.restart()
            c.burst()
        }
        em.entity.components.set(c)
        em.entity.isEnabled = true
        let looping = e.rate > 0
        let span = e.span
        emits.append(EmitInst(emitter: em, until: span.isFinite ? time + span : .infinity, follow: follow, offset: offset,
                              yaw: yaw, looping: looping && e.duration <= 0,
                              stopAt: looping && e.duration > 0 ? time + e.duration : .infinity, start: time,
                              source: ctx.source))
        stats.emitters.peakInUse = max(stats.emitters.peakInUse, emits.count)
    }

    private func spawnMesh(_ m: FXMesh, at p: SIMD3<Float>, yaw: Float, follow: Follow?, offset: SIMD3<Float>, ctx: Context,
                           groundLevel: Bool) {
        stats.meshShapes[m.shape, default: PoolStats()].requests += 1
        let e: ModelEntity
        if let free = freeMeshes[m.shape]?.popLast() {
            e = free
        } else if prewarmed {
            guard let k = meshInsts.indices.filter({ meshInsts[$0].shape == m.shape })
                .min(by: { meshInsts[$0].start < meshInsts[$1].start }) else {
                stats.meshShapes[m.shape, default: PoolStats()].rejected += 1
                stats.bySource[ctx.source, default: SourceStats()].meshRejected += 1
                return
            }
            e = meshInsts[k].entity
            // 寿命を過ぎて回収（update）を待っていた枠は正常終了。寿命の途中なら打ち切り（打ち切られた側の出所に数える）
            if time - meshInsts[k].start >= max(0.01, meshInsts[k].spec.life) {
                stats.meshShapes[m.shape, default: PoolStats()].reclaimed += 1
            } else {
                stats.meshShapes[m.shape, default: PoolStats()].cut += 1
                stats.bySource[meshInsts[k].source, default: SourceStats()].meshCut += 1
            }
            meshInsts.swapAt(k, meshInsts.count - 1)
            meshInsts.removeLast()
        } else {
            stats.meshShapes[m.shape, default: PoolStats()].grown += 1
            e = makeMesh(m.shape)
        }
        // 使い回す枠の前回の材質（加算の段階・模様）は全て書き換える。加算は明るさの段階 addLevels（最大）から始め、apply で落とす
        // （加算の材質を作れず従来の材質で代えた時は、段階では明るさが変わらないので不透明度で落とす）
        let material = materials.material(for: m, palette: ctx.palette)
        let additive = m.blend == .add && material is CustomMaterial
        e.model?.materials = [material]
        let ground = groundLevel && (m.shape == .disc || m.shape == .arc || m.shape == .band)
        if ground {
            OverlayOrder.apply(e, OverlayOrder.skillDecal)
        } else {
            e.components.remove(ModelSortGroupComponent.self)
        }
        var base = p
        if ground { base.y = GroundLayer.skillDecal }
        // 溶けるメッシュは重ねても模様が揃わないよう種をずらす（ほかは 0 = 従来どおり）
        var seed: UInt8 = 0
        if m.dissolve != nil {
            seedCounter = seedCounter &+ 89
            seed = seedCounter
        }
        let inst = MeshInst(entity: e, shape: m.shape, spec: m, start: time, base: base, yaw: yaw, follow: follow,
                            offset: offset, ground: ground, source: ctx.source, palette: additive ? ctx.palette : nil,
                            level: additive ? FXMaterialLibrary.addLevels : 0, slot: slotOf[ObjectIdentifier(e)], seed: seed)
        meshInsts.append(inst)
        apply(meshInsts.count - 1, t: 0)
        e.isEnabled = true
        stats.peakMeshes = max(stats.peakMeshes, meshInsts.count)
        let sameShape = meshInsts.reduce(0) { $1.shape == m.shape ? $0 + 1 : $0 }
        let peak = max(stats.meshShapes[m.shape]?.peakInUse ?? 0, sameShape)
        stats.meshShapes[m.shape, default: PoolStats()].peakInUse = peak
    }

    // MARK: 更新

    func update(dt: Float) {
        time += dt
        // 予定の発火
        if !pending.isEmpty {
            var k = 0
            while k < pending.count {
                if pending[k].time <= time {
                    let p = pending[k]
                    pending.swapAt(k, pending.count - 1)
                    pending.removeLast()
                    fire(p.cue, p.ctx, index: p.index)
                } else {
                    k += 1
                }
            }
        }
        // 粒子
        var k = 0
        while k < emits.count {
            var e = emits[k]
            if let f = e.follow {
                if let p = resolve(f) {
                    e.emitter.entity.position = p + e.offset
                    emits[k].seen = true
                } else if e.looping && (e.seen || time - e.start > 0.3) {
                    stopEmitting(k)
                    e = emits[k]
                    emits[k].follow = nil
                }
            }
            if e.stopAt <= time && e.stopAt.isFinite {
                stopEmitting(k)
                emits[k].stopAt = .infinity
            }
            if emits[k].until <= time {
                release(emitAt: k)
                continue
            }
            k += 1
        }
        // メッシュ
        k = 0
        while k < meshInsts.count {
            let inst = meshInsts[k]
            let t = (time - inst.start) / max(0.01, inst.spec.life)
            if t >= 1 {
                inst.entity.isEnabled = false
                freeMeshes[inst.shape, default: []].append(inst.entity)
                meshInsts.swapAt(k, meshInsts.count - 1)
                meshInsts.removeLast()
                continue
            }
            if let f = inst.follow, let p = resolve(f) {
                var b = p + inst.offset
                if inst.ground { b.y = GroundLayer.skillDecal }
                meshInsts[k].base = b
            }
            apply(k, t: t)
            k += 1
        }
        // 帯
        if !ribbons.isEmpty { updateRibbons() }
    }

    private func apply(_ index: Int, t: Float) {
        let inst = meshInsts[index]
        let m = inst.spec
        let age = t * m.life
        // 大きさ・向き・不透明度は範囲の検査（FXRangeAudit）と同じ式（FXEdge.swift の FXMesh の拡張）
        let size = m.size(at: t)
        let yaw = inst.yaw + m.yawDegrees(at: t) * .pi / 180
        var q = simd_quatf(angle: yaw, axis: [0, 1, 0])
        if m.pitch != 0 { q = q * simd_quatf(angle: -m.pitch * .pi / 180, axis: [1, 0, 0]) }
        if m.roll != 0 { q = q * simd_quatf(angle: m.roll * .pi / 180, axis: [0, 0, 1]) }
        var p = inst.base
        p.y += m.rise * age - 0.5 * m.gravity * age * age
        if m.advance != 0 { p += SkillFXPlayer.rotate([0, 0, m.advance * age], yaw: inst.yaw) }
        inst.entity.position = p
        if m.shape != .billboard { inst.entity.orientation = q }
        inst.entity.scale = size
        // 1 体ごとの値（頂点の色）: コマ送りのコマ・溶けの進み・模様の種（変わった時だけ書く）
        if let slot = inst.slot {
            var params = FXMeshSlot.rest
            if let sheet = m.sheet { params.y = UInt8(SkillFXPlayer.sheetFrame(m, sheet, age: age)) }
            if let d = m.dissolve { params.z = UInt8((SkillFXPlayer.dissolveAmount(d, t: t) * 255).rounded()) }
            params.w = inst.seed
            slot.set(params)
        }
        // 不透明度: fadeIn まで立ち上がり、fadeOut から 0 へ
        let opacity = m.opacity(at: t)
        if m.blend == .add, let palette = inst.palette {
            // 加算: 明るさの段階の材質を差し替えて落とす（段階が変わった時だけ）。OpacityComponent は出す / 隠すだけ
            let level = FXMaterialLibrary.addLevel(opacity)
            if level != inst.level {
                if level > 0 { inst.entity.model?.materials = [materials.material(for: m, palette: palette, level: level)] }
                meshInsts[index].level = level
            }
            inst.entity.components.set(OpacityComponent(opacity: level > 0 ? 1 : 0))
        } else {
            inst.entity.components.set(OpacityComponent(opacity: opacity))
        }
    }

    private func release(emitAt k: Int) {
        let e = emits[k]
        e.emitter.entity.isEnabled = false
        freeEmitters.append(e.emitter)
        emits.swapAt(k, emits.count - 1)
        emits.removeLast()
    }

    // MARK: 画面の歪み（後処理）

    /// 画面の歪みの輪（FXMesh.refract を持つ使用中のメッシュ。world の中心・半径と今の強さ）。
    struct Refraction: Equatable {
        var center: SIMD3<Float>
        var radius: Float
        var strength: Float
    }

    private var refractionBuffer: [Refraction] = []

    /// 今フレームの歪みの輪（強い順に最大 n）。BattleRenderer が画面へ投影して後処理（PostProcessor.ripples）へ渡す。
    func refractions(max n: Int = PostProcessor.maxRipples) -> [Refraction] {
        refractionBuffer.removeAll(keepingCapacity: true)
        for inst in meshInsts where inst.spec.refract > 0 && inst.entity.isEnabled {
            let m = inst.spec
            let t = min(1, max(0, (time - inst.start) / max(0.01, m.life)))
            let radius = inst.entity.scale.x * (inst.shape == .disc ? 0.5 : 1)
            refractionBuffer.append(Refraction(center: inst.entity.position, radius: radius, strength: m.refract * m.opacity(at: t)))
        }
        if refractionBuffer.count > n {
            refractionBuffer.sort { $0.strength > $1.strength }
            refractionBuffer.removeLast(refractionBuffer.count - n)
        }
        return refractionBuffer
    }

    #if DEBUG
    /// 比較撮影（FXCapture）で画面を撮る間だけ、生きている粒子の動きを止める / 戻す（メッシュは update が呼ばれないので止まる）。
    func freezeParticles(_ frozen: Bool) {
        for e in emits {
            guard var c = e.emitter.entity.components[ParticleEmitterComponent.self] else { continue }
            c.simulationState = frozen ? .pause : .play
            e.emitter.entity.components.set(c)
        }
    }
    #endif

    /// 全て止めてプールへ戻す。
    func clear() {
        pending.removeAll(keepingCapacity: true)
        while !emits.isEmpty {
            if var c = emits[emits.count - 1].emitter.entity.components[ParticleEmitterComponent.self] {
                c.isEmitting = false
                emits[emits.count - 1].emitter.entity.components.set(c)
            }
            release(emitAt: emits.count - 1)
        }
        for inst in meshInsts {
            inst.entity.isEnabled = false
            freeMeshes[inst.shape, default: []].append(inst.entity)
        }
        meshInsts.removeAll()
        for r in ribbons {
            r.slot.entity.isEnabled = false
            freeRibbons.append(r.slot)
        }
        ribbons.removeAll()
        // 陳列（fireWarmup）で出した空きの帯も隠す
        for r in freeRibbons { r.entity.isEnabled = false }
        stats = Stats()
    }

    // MARK: ウォームアップ（読み込み幕の裏）

    /// 全ての形のプールを一度描き、全ての放出体を画像を替えながら一度ずつ動かす。
    func fireWarmup(around center: SIMD3<Float>, spread: Float) {
        let mats = materials.built
        var n = 0
        func slot() -> SIMD3<Float> {
            let a = Float(n) * 2.399963
            let r = spread * (0.2 + 0.8 * Float((n * 37) % 100) / 100)
            n += 1
            return center + SIMD3(cos(a) * r, 0.8, sin(a) * r * 0.5)
        }
        for s in FXShape.allCases {
            guard var list = freeMeshes[s] else { continue }
            for e in list {
                e.model?.materials = mats.isEmpty ? [] : [mats[n % mats.count]]
                e.position = slot()
                e.scale = SIMD3(repeating: 0.3)
                e.components.set(OpacityComponent(opacity: 0.5))
                e.isEnabled = true
                meshInsts.append(MeshInst(entity: e, shape: s, spec: FXMesh(shape: s, life: 0.6), start: time,
                                          base: e.position, yaw: 0, follow: nil, offset: .zero, ground: false))
            }
            list.removeAll()
            freeMeshes[s] = list
        }
        // 帯の枠も一度描く（材質の全ては陳列の棚で描く）
        for (k, r) in freeRibbons.enumerated() {
            r.showForWarmup(at: slot(), material: mats.isEmpty ? nil : mats[k % mats.count])
        }
        // 材質の全ては陳列の棚（BattleWorld.openGalleryShelf）で一度ずつ描く
        let palette = FXPalette.from(RGB(1, 1, 1))
        // 手続きの画像だけを回す（Blender の大きな画像はレシピが使うものだけ作ってある。ここで作らない）
        let warmTex = FXTex.allCases.filter { $0.bundled == nil }
        var texIndex = 0
        while let em = freeEmitters.popLast() {
            let tex = warmTex[texIndex % warmTex.count]
            texIndex += 1
            var c = em.entity.components[ParticleEmitterComponent.self] ?? blank
            configure(&c, FXEmit(tex: tex, count: 4, life: 0.4, size: 0.2, speed: 1), palette: palette)
            c.isEmitting = false
            c.restart()
            c.burst()
            em.entity.components.set(c)
            em.entity.position = slot()
            em.entity.isEnabled = true
            emits.append(EmitInst(emitter: em, until: time + 0.8, follow: nil, offset: .zero, yaw: 0, looping: false,
                                  stopAt: .infinity))
        }
    }

    // MARK: 粒子の設定

    /// FXEmit の全項目を部品へ書く（使い回す部品の前回の値を全て上書きする）。
    private func configure(_ p: inout ParticleEmitterComponent, _ e: FXEmit, palette: FXPalette) {
        p.fieldSimulationSpace = .global
        p.particlesInheritTransform = false
        p.spawnedEmitter = nil
        p.speed = e.speed
        p.speedVariation = e.speed * e.speedVar
        p.radialAmount = 0
        p.torusInnerRadius = 0.05
        p.birthLocation = e.surface ? .surface : .volume
        switch e.shape {
        case .point:
            p.emitterShape = .point
            p.emitterShapeSize = SIMD3(repeating: 0.01)
        case .sphere(let r):
            p.emitterShape = .sphere
            p.emitterShapeSize = SIMD3(repeating: max(0.01, r))
        case .disc(let r):
            p.emitterShape = .cylinder
            p.emitterShapeSize = [max(0.01, r), 0.02, max(0.01, r)]
        case .ring(let r):
            p.emitterShape = .torus
            p.emitterShapeSize = SIMD3(repeating: max(0.05, r))
            p.torusInnerRadius = min(0.08, r * 0.2)
        case .box(let b):
            p.emitterShape = .box
            p.emitterShapeSize = SIMD3(max(0.01, b.x), max(0.01, b.y), max(0.01, b.z))
        case .line(let len):
            p.emitterShape = .box
            p.emitterShapeSize = [0.05, 0.05, max(0.05, len)]
        }
        switch e.dir {
        case .outward:
            p.birthDirection = .normal
            p.emissionDirection = [0, 1, 0]
        case .up:
            p.birthDirection = .world
            p.emissionDirection = [0, 1, 0]
        case .down:
            p.birthDirection = .world
            p.emissionDirection = [0, -1, 0]
        case .forward:
            p.birthDirection = .local
            p.emissionDirection = [0, 0, -1]
        case .backward:
            p.birthDirection = .local
            p.emissionDirection = [0, 0, 1]
        case .local(let v):
            p.birthDirection = .local
            let n = simd_length(v) > 1e-4 ? simd_normalize(v) : SIMD3<Float>(0, 1, 0)
            p.emissionDirection = [n.x, n.y, -n.z]
        }
        var m = p.mainEmitter
        // コマ送り: 使い回す放出体は前回の画像・コマ送りを必ず書き換える（シートが無い・読めなければ 1 枚絵）
        if let sheet = e.sheet, let tex = sheets.texture(sheet, additive: e.additive) {
            m.image = tex
            var seq = ParticleEmitterComponent.ParticleEmitter.ImageSequence()
            seq.rowCount = sheet.rows
            seq.columnCount = sheet.columns
            seq.frameRate = SkillFXPlayer.sheetFPS(e, sheet)
            seq.frameRateVariation = 0
            seq.initialFrame = 0
            seq.initialFrameVariation = e.sheetRandomStart && sheet.loops ? sheet.frames - 1 : 0
            seq.animationMode = sheet.loops ? .looping : .playOnce
            m.imageSequence = seq
        } else {
            m.image = e.additive ? textures.glowTexture(e.tex) : textures.particleTexture(e.tex)
            m.imageSequence = nil
        }
        m.blendMode = e.additive ? .additive : .alpha
        m.isLightingEnabled = false
        m.opacityCurve = e.fade
        switch e.orient {
        case .billboard: m.billboardMode = .billboard
        case .upright: m.billboardMode = .billboardYAligned
        case .ground: m.billboardMode = .free(axis: [0, 1, 0], variation: 0)
        case .facing: m.billboardMode = .free(axis: [0, 0, 1], variation: 0)
        }
        let start = palette.rgb(e.tint).uiColor(alpha: 1)
        if let end = e.tintEnd {
            m.color = .evolving(start: .single(start), end: .single(palette.rgb(end).uiColor(alpha: 1)))
        } else {
            m.color = .constant(.single(start))
        }
        m.colorEvolutionPower = 1
        m.size = e.size
        m.sizeVariation = e.size * e.sizeVar
        m.sizeMultiplierAtEndOfLifespan = e.grow
        m.sizeMultiplierAtEndOfLifespanPower = 1
        m.lifeSpan = Double(e.life)
        m.lifeSpanVariation = Double(e.life * e.lifeVar)
        m.spreadingAngle = e.spread * .pi / 180
        m.acceleration = [0, -e.gravity, 0]
        m.dampingFactor = e.drag
        m.angle = e.angle * .pi / 180
        m.angleVariation = e.angleVar * .pi / 180
        m.angularSpeed = e.spin * .pi / 180
        m.angularSpeedVariation = e.spinVar * .pi / 180
        m.stretchFactor = e.stretch
        m.noiseStrength = e.noise
        m.noiseScale = 1
        m.noiseAnimationSpeed = 1
        m.vortexStrength = e.vortex
        m.vortexDirection = [0, 1, 0]
        m.attractionStrength = e.attract
        m.attractionCenter = .zero
        m.mass = 1
        m.massVariation = 0
        if e.rate > 0 {
            m.birthRate = e.rate * quality.particleScale
            m.birthRateVariation = 0
            p.burstCount = 0
            p.burstCountVariation = 0
            p.timing = .repeating(warmUp: nil, emit: .init(duration: 1), idle: nil)
        } else if e.emit > 0.001 {
            let n = quality.particles(e.count)
            m.birthRate = Float(n) / e.emit
            m.birthRateVariation = 0
            p.burstCount = 0
            p.burstCountVariation = 0
            p.timing = .once(warmUp: nil, emit: .init(duration: Double(e.emit)))
        } else {
            m.birthRate = 0
            m.birthRateVariation = 0
            // 1 枚もの（閃光・衝撃波）は画質で減らさない
            p.burstCount = e.count <= 2 ? e.count : quality.particles(e.count)
            p.burstCountVariation = 0
            p.timing = .once(warmUp: nil, emit: .init(duration: 0.05))
        }
        p.mainEmitter = m
    }
}

// MARK: - 帯（FXRibbon）

extension SkillFXPlayer {
    /// 帯を出す（空きの枠が無ければ最も古い帯を打ち切る。プレイ中に枠は作らない）。p = 弧の中心・追従の帯の頭の最初の位置。
    fileprivate func spawnRibbon(_ r: FXRibbon, at p: SIMD3<Float>, yaw: Float, follow: Follow?, offset: SIMD3<Float>,
                                 ctx: Context) {
        stats.ribbons.requests += 1
        let slot: RibbonSlot
        if let free = freeRibbons.popLast() {
            slot = free
        } else if let k = ribbons.indices.min(by: { ribbons[$0].start < ribbons[$1].start }) {
            slot = ribbons[k].slot
            if time - ribbons[k].start >= ribbons[k].spec.span {
                stats.ribbons.reclaimed += 1
            } else {
                stats.ribbons.cut += 1
            }
            ribbons.swapAt(k, ribbons.count - 1)
            ribbons.removeLast()
        } else {
            stats.ribbons.rejected += 1
            return
        }
        slot.reset()
        let look = r.look
        let material = materials.material(for: look, palette: ctx.palette)
        let additive = look.blend == .add && material is CustomMaterial
        slot.entity.model?.materials = [material]
        let ground = !r.upright && p.y < 0.3
        if ground {
            OverlayOrder.apply(slot.entity, OverlayOrder.skillDecal)
        } else {
            slot.entity.components.remove(ModelSortGroupComponent.self)
        }
        slot.entity.components.set(OpacityComponent(opacity: additive ? 1 : max(0, min(1, r.alpha))))
        ribbons.append(RibbonInst(slot: slot, spec: r, start: time, headEnd: time + max(0.01, r.duration), anchor: p, yaw: yaw,
                                  follow: follow, offset: offset, source: ctx.source, palette: additive ? ctx.palette : nil,
                                  level: additive ? FXMaterialLibrary.addLevels : 0, ground: ground))
        stats.ribbons.peakInUse = max(stats.ribbons.peakInUse, ribbons.count)
    }

    /// 弧の帯の時刻 τ の頭（world）と、中心から頭への向き（world の単位ベクトル）。
    fileprivate static func arcPoint(_ r: FXRibbon, anchor: SIMD3<Float>, yaw: Float, s: Float)
        -> (point: SIMD3<Float>, radial: SIMD3<Float>) {
        guard case .arc(let radius, let from, let to, let height, let roll) = r.path else { return (anchor, [0, 1, 0]) }
        let e = r.ease.apply(s)
        let theta = (from + (to - from) * e) * .pi / 180
        let rho = roll * .pi / 180
        let x = -sin(theta) * radius
        // 弧の面を前の軸まわりに傾ける（roll 90 で「左」が上になる）
        let dir = SIMD3<Float>(x * cos(rho), -x * sin(rho), cos(theta) * radius)
        let local = dir + SIMD3<Float>(0, height, 0)
        let radial = radius > 1e-4 ? dir / radius : SIMD3<Float>(0, 1, 0)
        return (anchor + rotate(local, yaw: yaw), rotate(radial, yaw: yaw))
    }

    fileprivate func updateRibbons() {
        var k = 0
        while k < ribbons.count {
            let r = ribbons[k]
            let spec = r.spec
            if time - r.start >= spec.span || time - r.headEnd >= spec.life {
                r.slot.entity.isEnabled = false
                freeRibbons.append(r.slot)
                ribbons.swapAt(k, ribbons.count - 1)
                ribbons.removeLast()
                continue
            }
            // 基準（追従の主体 + 置いた時のずれ）。主体が消えたら頭を止める
            var anchor = r.anchor
            if let f = r.follow {
                if let p = resolve(f) {
                    anchor = p + r.offset
                    ribbons[k].anchor = anchor
                } else if time - r.start > 0.3 {
                    ribbons[k].follow = nil
                    ribbons[k].headEnd = min(r.headEnd, time)
                }
            }
            let headEnd = ribbons[k].headEnd
            if case .follow = spec.path, time <= headEnd { r.slot.push(time, anchor) }
            // 見えている区間（τ0 = 尾、τ1 = 頭）
            let tau1 = min(time, headEnd)
            let tau0 = max(r.start, time - spec.life)
            guard tau1 - tau0 > 1e-3 else {
                if r.slot.entity.isEnabled { r.slot.entity.isEnabled = false }
                k += 1
                continue
            }
            let n = RibbonSlot.columns
            let life = max(0.01, spec.life)
            let dur = max(0.01, spec.duration)
            var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
            for c in 0..<n {
                let f = Float(c) / Float(n - 1)
                let tau = tau1 - (tau1 - tau0) * f
                let u = min(1, max(0, (time - tau) / life))
                let w = spec.width * (1 + (spec.tailWidth - 1) * u)
                var inner: SIMD3<Float>, outer: SIMD3<Float>
                switch spec.path {
                case .arc:
                    let a = SkillFXPlayer.arcPoint(spec, anchor: anchor, yaw: r.yaw, s: (tau - r.start) / dur)
                    outer = a.point
                    inner = a.point - a.radial * w
                case .follow:
                    let p = r.slot.sample(at: tau) ?? anchor
                    let side: SIMD3<Float>
                    if spec.upright {
                        side = [0, 1, 0]
                    } else {
                        let ahead = r.slot.sample(at: tau + 0.02) ?? p
                        let behind = r.slot.sample(at: tau - 0.02) ?? p
                        var tangent = ahead - behind
                        tangent.y = 0
                        if simd_length(tangent) < 1e-4 { tangent = SkillFXPlayer.rotate([0, 0, 1], yaw: r.yaw) }
                        let s = simd_cross(SIMD3<Float>(0, 1, 0), simd_normalize(tangent))
                        side = simd_length(s) > 1e-4 ? simd_normalize(s) : [1, 0, 0]
                    }
                    inner = p - side * (w * 0.5)
                    outer = p + side * (w * 0.5)
                }
                if r.ground {
                    inner.y = GroundLayer.skillDecal
                    outer.y = GroundLayer.skillDecal
                }
                r.slot.inner[c] = inner
                r.slot.outer[c] = outer
                r.slot.u[c] = u
                lo = simd_min(lo, simd_min(inner, outer))
                hi = simd_max(hi, simd_max(inner, outer))
            }
            r.slot.commit(lo: lo, hi: hi)
            // 明るさ（加算は段階の材質、アルファ合成は不透明度）。尾が頭に追いつく最後の life 秒で全体も弱める
            var a = max(0, min(1, spec.alpha))
            if time > headEnd { a *= max(0, 1 - (time - headEnd) / life) }
            if spec.blend == .add, let palette = r.palette {
                let level = FXMaterialLibrary.addLevel(a)
                if level != r.level {
                    if level > 0 { r.slot.entity.model?.materials = [materials.material(for: spec.look, palette: palette, level: level)] }
                    ribbons[k].level = level
                }
                r.slot.entity.components.set(OpacityComponent(opacity: level > 0 ? 1 : 0))
            } else {
                r.slot.entity.components.set(OpacityComponent(opacity: a))
            }
            if !r.slot.entity.isEnabled { r.slot.entity.isEnabled = true }
            k += 1
        }
    }

    #if DEBUG
    /// テスト用: 使用中の帯の頂点（列 c の内端・外端）。
    func ribbonVertices() -> [[(inner: SIMD3<Float>, outer: SIMD3<Float>, u: Float)]] {
        ribbons.map { r in (0..<RibbonSlot.columns).map { (r.slot.inner[$0], r.slot.outer[$0], r.slot.u[$0]) } }
    }
    #endif

    /// テスト用: プールのメッシュの枠の頂点の色（無ければ nil）。
    func meshParams(_ e: Entity) -> SIMD4<UInt8>? { slotOf[ObjectIdentifier(e)]?.params }
}

/// 帯の 1 枠（LowLevelMesh の 2 × columns 頂点。並び 0 = 位置・法線・UV を毎フレーム書き、並び 1 = 頂点の色は既定値のまま）。
@MainActor
fileprivate final class RibbonSlot {
    /// 帯の列の数（時刻で等間隔）。
    static let columns = 24
    /// 追従の帯の標本の数（120 fps で 0.8 秒）。
    static let capacity = 96

    let entity: ModelEntity
    let mesh: LowLevelMesh
    private var times = [Float](repeating: 0, count: RibbonSlot.capacity)
    private var points = [SIMD3<Float>](repeating: .zero, count: RibbonSlot.capacity)
    private var head = 0
    private var count = 0
    /// 今フレームの列（内端・外端・古さ）。update が書き、commit が頂点にする。
    var inner = [SIMD3<Float>](repeating: .zero, count: RibbonSlot.columns)
    var outer = [SIMD3<Float>](repeating: .zero, count: RibbonSlot.columns)
    var u = [Float](repeating: 0, count: RibbonSlot.columns)

    private init(entity: ModelEntity, mesh: LowLevelMesh) {
        self.entity = entity
        self.mesh = mesh
    }

    static func make() -> RibbonSlot? {
        let n = columns
        var d = LowLevelMesh.Descriptor()
        d.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: 0),
            .init(semantic: .normal, format: .float3, offset: 12),
            .init(semantic: .uv0, format: .float2, offset: 24),
            .init(semantic: .color, format: .uchar4Normalized, layoutIndex: 1, offset: 0),
        ]
        d.vertexLayouts = [.init(bufferIndex: 0, bufferStride: FXMeshSlot.stride), .init(bufferIndex: 1, bufferStride: 4)]
        d.vertexCapacity = n * 2
        d.indexCapacity = (n - 1) * 6
        d.indexType = .uint16
        guard let ll = try? LowLevelMesh(descriptor: d) else { return nil }
        ll.withUnsafeMutableIndices { raw in
            let dst = raw.bindMemory(to: UInt16.self)
            var k = 0
            for c in 0..<(n - 1) {
                let a = UInt16(c * 2), b = a + 1, c2 = a + 2, d2 = a + 3
                for i in [a, b, d2, a, d2, c2] where k < dst.count {
                    dst[k] = i
                    k += 1
                }
            }
        }
        ll.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            _ = raw.initializeMemory(as: UInt8.self, repeating: 0)
        }
        ll.withUnsafeMutableBytes(bufferIndex: 1) { raw in
            let dst = raw.bindMemory(to: SIMD4<UInt8>.self)
            for k in 0..<min(n * 2, dst.count) { dst[k] = FXMeshSlot.rest }
        }
        ll.parts.replaceAll([LowLevelMesh.Part(indexCount: (n - 1) * 6, topology: .triangle,
                                               bounds: BoundingBox(min: [-1, 0, -1], max: [1, 2, 1]))])
        guard let resource = try? MeshResource(from: ll) else { return nil }
        let e = ModelEntity(mesh: resource, materials: [])
        e.name = "skillfx ribbon"
        e.components.set(DynamicLightShadowComponent(castsShadow: false))
        e.isEnabled = false
        return RibbonSlot(entity: e, mesh: ll)
    }

    func reset() {
        head = 0
        count = 0
    }

    /// 追従の帯の標本を積む（同じ時刻は置き換え、満杯なら最も古いものを捨てる）。
    func push(_ t: Float, _ p: SIMD3<Float>) {
        let cap = RibbonSlot.capacity
        if count > 0 {
            let last = (head + count - 1) % cap
            if t - times[last] < 1e-4 {
                points[last] = p
                return
            }
        }
        if count == cap {
            head = (head + 1) % cap
            count -= 1
        }
        let i = (head + count) % cap
        times[i] = t
        points[i] = p
        count += 1
    }

    /// 時刻 τ の位置（積んだ範囲に丸め、隣の標本の間を線形に補間）。標本が無ければ nil。
    func sample(at tau: Float) -> SIMD3<Float>? {
        guard count > 0 else { return nil }
        let cap = RibbonSlot.capacity
        let first = head % cap, last = (head + count - 1) % cap
        if tau <= times[first] { return points[first] }
        if tau >= times[last] { return points[last] }
        var k = count - 2
        while k > 0 && times[(head + k) % cap] > tau { k -= 1 }
        let a = (head + k) % cap, b = (head + k + 1) % cap
        let span = times[b] - times[a]
        let s: Float = span > 1e-5 ? (tau - times[a]) / span : 0
        return points[a] + (points[b] - points[a]) * s
    }

    /// inner / outer / u の列を頂点に書く（列 c の内端 = 2c、外端 = 2c + 1）。UV = (1 − 古さ, 内 0 / 外 1): 画像の u は
    /// 尾 0 → 頭 1（三日月の模型・swoosh・blade の画像と同じ向き）。
    func commit(lo: SIMD3<Float>, hi: SIMD3<Float>) {
        let n = RibbonSlot.columns
        mesh.replaceUnsafeMutableBytes(bufferIndex: 0) { raw in
            guard let dst = raw.baseAddress else { return }
            for c in 0..<n {
                RibbonSlot.write(dst, c * 2, inner[c], uv: SIMD2(1 - u[c], 0))
                RibbonSlot.write(dst, c * 2 + 1, outer[c], uv: SIMD2(1 - u[c], 1))
            }
        }
        guard lo.x <= hi.x else { return }
        mesh.parts[0].bounds = BoundingBox(min: lo - 0.05, max: hi + 0.05)
    }

    /// 陳列（読み込み幕の裏）: p のまわりに短い帯を出して描画の準備をさせる（clear で隠す）。
    func showForWarmup(at p: SIMD3<Float>, material: (any Material)?) {
        let n = RibbonSlot.columns
        for c in 0..<n {
            let f = Float(c) / Float(n - 1)
            let a = -1.2 + 2.4 * f
            let dir = SIMD3<Float>(sin(a), 0, -cos(a))
            inner[c] = p + dir * 0.15
            outer[c] = p + dir * 0.5 + SIMD3<Float>(0, 0.2, 0)
            u[c] = f
        }
        commit(lo: p - 1, hi: p + 1)
        if let material { entity.model?.materials = [material] }
        entity.components.set(OpacityComponent(opacity: 0.5))
        entity.isEnabled = true
    }

    @inline(__always)
    private static func write(_ dst: UnsafeMutableRawPointer, _ index: Int, _ p: SIMD3<Float>, uv: SIMD2<Float>) {
        let o = dst + index * FXMeshSlot.stride
        o.storeBytes(of: p.x, toByteOffset: 0, as: Float.self)
        o.storeBytes(of: p.y, toByteOffset: 4, as: Float.self)
        o.storeBytes(of: p.z, toByteOffset: 8, as: Float.self)
        o.storeBytes(of: Float(0), toByteOffset: 12, as: Float.self)
        o.storeBytes(of: Float(1), toByteOffset: 16, as: Float.self)
        o.storeBytes(of: Float(0), toByteOffset: 20, as: Float.self)
        o.storeBytes(of: uv.x, toByteOffset: 24, as: Float.self)
        o.storeBytes(of: uv.y, toByteOffset: 28, as: Float.self)
    }
}

/// 使用中の帯。
fileprivate struct RibbonInst {
    var slot: RibbonSlot
    var spec: FXRibbon
    var start: Float
    /// 頭が止まる時刻（start + duration。追従の主体が消えたら早まる）。
    var headEnd: Float
    /// 弧の中心・追従の帯の頭（world）。
    var anchor: SIMD3<Float>
    var yaw: Float
    var follow: SkillFXPlayer.Follow?
    var offset: SIMD3<Float>
    var source: SkillFXPlayer.Source?
    /// 加算の明るさの段階の材質を選ぶための色（加算だけ）。
    var palette: FXPalette?
    var level: Int
    /// 地面に寝かせた帯（地面の模様の層に描く）。
    var ground: Bool
}

/// SkillFXPlayer の予算の集計の写し（性能記録 PerfReport.skillFXBudget へ JSON で出す）。
struct SkillFXBudgetSnapshot: Codable, Equatable, Sendable {
    struct Pool: Codable, Equatable, Sendable {
        /// 作ってある枠の数（使用中 + 空き）。
        var pooled: Int
        /// 写しを取った時点の使用中の枠の数。
        var inUse: Int
        var counts: SkillFXPlayer.PoolStats
    }

    struct Cues: Codable, Equatable, Sendable {
        var perPlayLimit: Int
        var pendingLimit: Int
        var overPerPlay: Int
        var overPending: Int
        /// 写しを取った時点の遅延予約の数と、その最大。
        var pending: Int
        var peakPending: Int
    }

    /// いまの画質（自動調整の後）と、プールの大きさを決めた試合開始時の画質。
    var quality: String
    var poolQuality: String
    var plays: Int
    var emitters: Pool
    var meshes: Pool
    /// 形（FXShape の名前）ごと。
    var meshShapes: [String: Pool]
    var cues: Cues
    /// 出所ごと（"H029.skill1.0" = ヒーロー.スキル.再使用の段。cast / impact などの段は含まない。"unknown" = 不明）。
    var bySource: [String: SkillFXPlayer.SourceStats]
}
