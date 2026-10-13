import Foundation
import RealityKit
import simd
import VelstriaCore

// 担当: battle-renderer。タワー・Star Core の見た目（部品ごとのエンティティ）と、その姿勢・明るさの反映。
// 姿勢は TowerPose（演出時刻から求める純粋関数。時刻表は TowerTimeline）で決める:
//   立ち上がり（試合開始 0〜2.4 秒）→ 待機（結晶だけ揺れる）・攻撃の溜め・損傷 → 倒壊（unit.deathTime から）→ 瓦礫 → 整理。
// 部品の出どころは 3 段（上ほど優先）:
//   1. 複数部品の生成モデル（StructureAssets.RigKind。part_plinth / lower / upper / crown / crystal）
//   2. 従来の生成モデル（Struct_tower + Struct_tower_orb、Struct_core_base + Struct_core_crystal。本体ごと 1 つ）
//   3. 手続きメッシュ（StructureMeshes）
// 2・3 は同じ部品の枠（基壇・根元・上部・頂部・結晶）へ当てはめ、同じ姿勢の式で動かす。
// 一度きりの演出・音は TowerCue として UnitLayer に溜め、BattleWorld（StructureFXDirector）が粒子・音へ変える。
// 状態が置き換わって（シーク・オンラインの再同期）生きていれば元の姿へ戻す（姿勢は時刻と状態だけで決まる）。

@MainActor
final class StructureMeshes {
    struct TeamSet {
        var plinth: MeshResource?
        var pillar: MeshResource?
        var pillarGlow: MeshResource?
        var crystal: MeshResource?
        var shards: MeshResource?
        var coreBase: MeshResource?
        var coreBaseGlow: MeshResource?
        var coreStar: MeshResource?
        var coreRing: MeshResource?
        var coreRingSmall: MeshResource?
        /// 割れた結晶の破片（倒壊後に飛んで地面に残る）。
        var shardPiece: MeshResource?
    }

    private var sets: [Int: TeamSet] = [:]

    func set(_ team: Team) -> TeamSet {
        if let s = sets[team.rawValue] { return s }
        let red = team == .red
        let main: Swatch = red ? .redMain : .blueMain
        let cloth: Swatch = red ? .redCloth : .blueCloth
        let rune: Swatch = red ? .glowRed : .glowBlue
        let crystalRamp: Ramp = red ? .crystalRed : .crystalBlue
        var s = TeamSet()

        // タワー台座（破壊後も残る）
        var plinth = MeshBuilder()
        plinth.frustum(bottomRadius: 1.55, topRadius: 1.4, height: 0.34, segments: 8, color: .solid(.stoneDark), phase: 0.39)
        plinth.frustum(bottomRadius: 1.2, topRadius: 1.08, height: 0.32, segments: 8, color: .solid(.stone), phase: 0.39,
                       transform: MX.t(0, 0.34, 0))
        for k in 0..<4 {
            let a = Float(k) / 4 * 2 * .pi + .pi / 4
            plinth.box(size: [0.34, 0.5, 0.34], color: .solid(.stoneDark), transform: MX.t(cos(a) * 1.28, 0, -sin(a) * 1.28) * MX.ry(a))
        }
        s.plinth = plinth.makeMesh(name: "towerPlinth_\(team.rawValue)")

        // 柱・冠・旗・ランタン
        var pillar = MeshBuilder(), pillarGlow = MeshBuilder()
        pillar.frustum(bottomRadius: 0.66, topRadius: 0.44, height: 3.1, segments: 8, color: .ramp(.stonePillar), phase: 0.39,
                       transform: MX.t(0, 0.66, 0))
        for y: Float in [1.3, 2.7] {
            pillar.torus(majorRadius: y < 2 ? 0.62 : 0.5, minorRadius: 0.07, segments: 16, sides: 4, color: .solid(.gold),
                         transform: MX.t(0, y, 0))
        }
        pillar.frustum(bottomRadius: 0.42, topRadius: 0.78, height: 0.36, segments: 8, color: .solid(.metalDark), phase: 0.39,
                       transform: MX.t(0, 3.76, 0))
        for k in 0..<4 {
            let a = Float(k) / 4 * 2 * .pi
            pillar.frustum(bottomRadius: 0.1, topRadius: 0, height: 0.75, segments: 4, color: .solid(.gold),
                           transform: MX.t(cos(a) * 0.62, 4.05, -sin(a) * 0.62) * MX.ry(a) * MX.rz(-0.35))
            // 旗
            pillar.box(size: [0.36, 1.1, 0.04], color: .solid(cloth),
                       transform: MX.t(cos(a) * 0.6, 1.55, -sin(a) * 0.6) * MX.ry(a + .pi / 2))
            pillar.box(size: [0.36, 0.1, 0.05], color: .solid(.gold),
                       transform: MX.t(cos(a) * 0.62, 2.62, -sin(a) * 0.62) * MX.ry(a + .pi / 2))
            pillarGlow.crystal(radius: 0.06, height: 0.22, color: .solid(rune),
                               transform: MX.t(cos(a) * 0.64, 2.0, -sin(a) * 0.64))
            // 台座角のランタン
            let b = Float(k) / 4 * 2 * .pi + .pi / 4
            pillar.box(size: [0.18, 0.05, 0.18], color: .solid(.metalDark), transform: MX.t(cos(b) * 1.28, 0.5, -sin(b) * 1.28))
            pillarGlow.box(size: [0.14, 0.2, 0.14], color: .solid(.lanternWarm), transform: MX.t(cos(b) * 1.28, 0.55, -sin(b) * 1.28))
            pillar.frustum(bottomRadius: 0.12, topRadius: 0, height: 0.14, segments: 4, color: .solid(.metalDark),
                           transform: MX.t(cos(b) * 1.28, 0.75, -sin(b) * 1.28))
        }
        pillarGlow.annulus(inner: 0.46, outer: 0.56, segments: 16, y: 4.132, color: .solid(rune))
        s.pillar = pillar.makeMesh(name: "towerPillar_\(team.rawValue)")
        s.pillarGlow = pillarGlow.makeMesh(name: "towerPillarGlow_\(team.rawValue)")

        var crystal = MeshBuilder()
        crystal.crystal(radius: 0.46, height: 1.45, sides: 6, waist: 0.42, color: .ramp(crystalRamp, from: 0.15, to: 1),
                        transform: MX.t(0, -0.62, 0))
        s.crystal = crystal.makeMesh(name: "towerCrystal_\(team.rawValue)")
        var shards = MeshBuilder()
        for k in 0..<3 {
            let a = Float(k) / 3 * 2 * .pi
            shards.crystal(radius: 0.1, height: 0.34, color: .ramp(crystalRamp, from: 0.4, to: 1),
                           transform: MX.t(cos(a) * 0.85, -0.1 + Float(k) * 0.1, -sin(a) * 0.85))
        }
        s.shards = shards.makeMesh(name: "towerShards_\(team.rawValue)")

        // Core 台座
        var coreBase = MeshBuilder(), coreGlow = MeshBuilder()
        coreBase.frustum(bottomRadius: 3.4, topRadius: 3.15, height: 0.4, segments: 12, color: .solid(.stoneDark))
        coreBase.frustum(bottomRadius: 2.7, topRadius: 2.5, height: 0.34, segments: 12, color: .solid(.stone),
                         transform: MX.t(0, 0.4, 0))
        coreBase.frustum(bottomRadius: 1.5, topRadius: 1.2, height: 0.5, segments: 12, color: .solid(.stoneLight),
                         transform: MX.t(0, 0.74, 0))
        // 台座の天面（0.74 / 1.24）から 12 mm 浮かせる
        coreGlow.annulus(inner: 2.2, outer: 2.38, segments: 36, y: 0.752, color: .solid(rune))
        coreGlow.annulus(inner: 1.0, outer: 1.12, segments: 24, y: 1.252, color: .solid(rune))
        for k in 0..<6 {
            let a = Float(k) / 6 * 2 * .pi + .pi / 6
            let p = SIMD3<Float>(cos(a) * 2.95, 0.4, -sin(a) * 2.95)
            coreBase.frustum(bottomRadius: 0.26, topRadius: 0.2, height: 2.3, segments: 6, color: .ramp(.stonePillar),
                             transform: MX.t(p))
            coreBase.box(size: [0.55, 0.16, 0.55], color: .solid(.gold), transform: MX.t(p + SIMD3(0, 2.3, 0)) * MX.ry(a))
            coreGlow.crystal(radius: 0.14, height: 0.5, color: .ramp(crystalRamp, from: 0.4, to: 1),
                             transform: MX.t(p + SIMD3(0, 2.46, 0)))
            coreBase.box(size: [0.3, 1.0, 0.03], color: .solid(main), transform: MX.t(p + SIMD3(0, 1.3, 0)) * MX.ry(a + .pi / 2)
                         * MX.t(0, 0, -0.26))
        }
        s.coreBase = coreBase.makeMesh(name: "coreBase_\(team.rawValue)")
        s.coreBaseGlow = coreGlow.makeMesh(name: "coreBaseGlow_\(team.rawValue)")

        // 星結晶（中心の大結晶 + 放射状の小結晶）
        var star = MeshBuilder()
        star.crystal(radius: 0.95, height: 3.0, sides: 6, waist: 0.5, color: .ramp(crystalRamp, from: 0.1, to: 1),
                     transform: MX.t(0, -1.5, 0))
        for k in 0..<6 {
            let a = Float(k) / 6 * 2 * .pi
            star.crystal(radius: 0.28, height: 1.5, sides: 5, color: .ramp(crystalRamp, from: 0.3, to: 1),
                         transform: MX.ry(a) * MX.rz(-1.25) * MX.t(0, 0.5, 0))
        }
        s.coreStar = star.makeMesh(name: "coreStar_\(team.rawValue)")
        var ring = MeshBuilder()
        ring.torus(majorRadius: 2.25, minorRadius: 0.08, segments: 40, sides: 5, color: .solid(rune))
        for k in 0..<4 {
            let a = Float(k) / 4 * 2 * .pi
            ring.crystal(radius: 0.1, height: 0.3, color: .solid(.glowWhite), transform: MX.t(cos(a) * 2.25, -0.15, -sin(a) * 2.25))
        }
        s.coreRing = ring.makeMesh(name: "coreRing_\(team.rawValue)")
        var ring2 = MeshBuilder()
        ring2.torus(majorRadius: 1.65, minorRadius: 0.06, segments: 32, sides: 5, color: .solid(.glowGold))
        s.coreRingSmall = ring2.makeMesh(name: "coreRing2_\(team.rawValue)")
        var piece = MeshBuilder()
        piece.crystal(radius: 0.08, height: 0.36, sides: 5, waist: 0.4, color: .ramp(crystalRamp, from: 0.3, to: 1),
                      transform: MX.t(0, -0.18, 0))
        s.shardPiece = piece.makeMesh(name: "towerShardPiece_\(team.rawValue)")
        sets[team.rawValue] = s
        return s
    }

    /// 小破片の石（チームによらない。苔のある灰緑の石）。
    private(set) lazy var chunks: [MeshResource] = {
        var out: [MeshResource] = []
        var a = MeshBuilder()
        a.blob(radius: 0.17, jitter: 0.3, seed: 811, color: .ramp(.mossRock, from: 0, to: 0.55), transform: MX.s(1.1, 0.7, 1))
        if let m = a.makeMesh(name: "structureChunk0") { out.append(m) }
        var b = MeshBuilder()
        // 灰緑の暗い石（stoneDark は紫がかって明るく、生成モデルの花崗岩の隣で浮く）
        b.box(size: [0.3, 0.18, 0.24], color: .ramp(.mossRock, from: 0, to: 0.2), transform: MX.ry(0.4) * MX.rz(0.12) * MX.t(0, -0.09, 0))
        b.blob(radius: 0.08, jitter: 0.25, seed: 823, color: .ramp(.mossRock, from: 0.4, to: 1), transform: MX.t(0.04, 0.06, 0))
        if let m = b.makeMesh(name: "structureChunk1") { out.append(m) }
        var c = MeshBuilder()
        c.blob(radius: 0.15, jitter: 0.35, seed: 829, color: .ramp(.mossRock, from: 0.05, to: 1), transform: MX.s(1, 0.8, 1.2))
        if let m = c.makeMesh(name: "structureChunk2") { out.append(m) }
        return out
    }()

    /// 手続きの塔の折れた根元（柱の内側に隠れていて、上部が倒れると見える）。
    private(set) lazy var stump: MeshResource? = {
        var b = MeshBuilder()
        b.frustum(bottomRadius: 0.6, topRadius: 0.55, height: 1.2, segments: 8, color: .ramp(.stonePillar, from: 0, to: 0.45),
                  phase: 0.39)
        for k in 0..<4 {
            let a = Float(k) / 4 * 2 * .pi + 0.5
            b.crystal(radius: 0.13, height: 0.24 + Float(k % 2) * 0.08, sides: 4, color: .solid(.stoneDark),
                      transform: MX.t(cos(a) * 0.36, 1.12, -sin(a) * 0.36))
        }
        return b.makeMesh(name: "towerStump")
    }()

    /// Core の光の柱（半径 1・高さ 1 の筒。上が細い。単色の半透明で描く）。
    private(set) lazy var column: MeshResource? = {
        var b = MeshBuilder()
        b.frustum(bottomRadius: 1, topRadius: 0.55, height: 1, segments: 18, color: .solid(.white), capTop: false)
        return b.makeMesh(name: "coreColumn")
    }()

    /// 作成済みのメッシュ全て（ウォームアップの陳列用）。
    var builtMeshes: [MeshResource] {
        var out: [MeshResource] = []
        for k in sets.keys.sorted() {
            guard let s = sets[k] else { continue }
            for m in [s.plinth, s.pillar, s.pillarGlow, s.crystal, s.shards, s.coreBase, s.coreBaseGlow, s.coreStar,
                      s.coreRing, s.coreRingSmall, s.shardPiece] {
                if let m { out.append(m) }
            }
        }
        if !sets.isEmpty {
            out += chunks
            for m in [stump, column] { if let m { out.append(m) } }
        }
        return out
    }
}


/// 構造物の一度きりの演出・音の合図（UnitLayer が溜め、BattleWorld の StructureFXDirector が鳴らす）。
struct StructureCueEvent {
    var id: EntityID
    var team: Team
    var isCore: Bool
    var style: CollapseStyle
    var cue: TowerCue
    /// world 位置。
    var position: SIMD3<Float>
    /// 合図の時刻（演出時刻）。
    var time: Double
}

/// 部品の発光の差し替え（段階ごとの材質を読み込み中に作っておき、段階が変わった時だけ差し替える）。
@MainActor
private struct GlowSlot {
    var entities: [ModelEntity] = []
    /// 段階（StructureAssets.glowLevels）ごとの材質。
    var levels: [RealityKit.Material] = []
    /// 破損の材質（nil = 差し替えない）。
    var ruin: RealityKit.Material?
    /// 明るさへの倍率（複数部品の塔の結晶は発光が面全体に乗って形が飛ぶので抑える）。
    var gain: Float = 1
    private var current = -1

    init() {}

    init(_ entities: [ModelEntity], set: StructureAssets.MaterialSet?, gain: Float = 1) {
        self.entities = entities
        self.gain = gain
        if let set {
            levels = set.levels
            ruin = set.ruin
        }
    }

    /// 手続きメッシュ: 消灯 = 光らないパレット、点灯 = 発光パレット。
    init(_ entities: [ModelEntity], off: RealityKit.Material, on: RealityKit.Material) {
        self.entities = entities
        levels = StructureAssets.glowLevels.indices.map { $0 == 0 ? off : on }
        ruin = off
    }

    mutating func set(glow: Float, ruined: Bool) {
        guard !entities.isEmpty, !levels.isEmpty else { return }
        let k = ruined && ruin != nil ? levels.count : StructureAssets.glowLevel(glow * gain)
        guard k != current else { return }
        current = k
        let m = k == levels.count ? (ruin ?? levels[0]) : levels[min(k, levels.count - 1)]
        for e in entities { e.model?.materials = [m] }
    }

    mutating func invalidate() { current = -1 }
}

@MainActor
final class StructureVisual {
    let id: EntityID
    let isCore: Bool
    let team: Team
    let root = Entity()
    /// 基壇（破壊後も残る）。
    private let plinthNode = Entity()
    /// 支柱（根元・上部・頂部・結晶。追従ヒーローを隠す間はまとめて半透明にする）。
    private let body = Entity()
    private let lowerNode = Entity()
    private let upperNode = Entity()
    private let crownNode = Entity()
    private let crystalNode = Entity()
    /// 結晶片・小破片（作っておき、倒壊の間だけ出す）。
    private var shardNodes: [ModelEntity] = []
    private var debrisNodes: [ModelEntity] = []
    /// Core の光の柱。
    private var column: ModelEntity?
    /// 従来の生成モデルの塔の瓦礫（台座ごと倒れるので、倒れた後の足元に置く）。
    private var legacyRubble: ModelEntity?
    /// 従来の Core の回る環・手続きの塔の結晶の周りを回る小結晶（待機中だけ回す）。
    private var ringA: Entity?
    private var ringB: Entity?
    private var orbitShards: Entity?
    let bar: OverheadBar
    let rangeRing: ModelEntity
    /// 姿勢の寸法（部品の外接箱）。
    let geometry: TowerGeometry
    /// 使っている複数部品の塔（nil = 従来のモデル・手続きメッシュ）。
    let rigKind: StructureAssets.RigKind?
    private(set) var destroyed = false
    /// 浮遊する結晶の静止時の高さ（中心）。
    let floatBaseY: Float
    /// 生成 3D モデルを使っている部位の数（テスト用。0 = 全て手続きメッシュ。複数部品の塔は部品の数）。
    private(set) var generatedParts = 0
    /// 攻撃の発射点（world 高さ）。結晶の静止時の中心（従来の手続きメッシュは 4.5 m）。
    let muzzleHeight: Float
    private let seed: UInt64

    private var plinthGlow = GlowSlot()
    private var bodyGlow = GlowSlot()
    private var crystalGlow = GlowSlot()

    /// 前回の合図の評価の時刻（nil = まだ・シーク直後。過ぎた合図を出し直さない）。
    private var cueClock: Double?
    /// deathTime の無い状態（合成した状態など）で破壊を見つけた時刻。
    private var observedDeath: Double?
    private var lastStage: Int?
    /// 損傷の傾き（閾値をまたいだら少しずつ寄せる）。
    private var lean: Float = 0
    /// 最後に反映した姿勢の段階・倒壊の経過（テスト・計測用）。
    private(set) var lastPhase: TowerPose.Phase = .idle
    private(set) var lastCollapseElapsed: Double?
    private var lastStyle: CollapseStyle = .full
    private var applied = false
    private var nodeCache: [simd_float4x4] = Array(repeating: simd_float4x4(diagonal: SIMD4(repeating: .nan)), count: 5)
    /// 破片の最後に書いた行列（止まっている瓦礫は書き直さない）。
    private var shardCache: [simd_float4x4] = []
    private var debrisCache: [simd_float4x4] = []
    private var piecesShown = false
    private var columnShown = false
    private var rangeAlpha: Float = 0
    private var occlusionAlpha: Float = 1
    private var clock: Float
    /// 被弾の演出の時刻（同時 2 つまで・0.15 秒以内はまとめる）。
    private var hitTimes: [Float] = []

    /// 複数部品の塔の結晶の明るさの倍率（通常 1 → 発光の段階 0.65。面全体が光って結晶の面が見えなくなるのを抑える。
    /// 攻撃の溜め・異常発光の山は段階 1.7 まで残る）。
    static let rigCrystalGain: Float = 0.6

    /// 1 基あたりの被弾の演出の同時数・まとめる間隔・1 つの長さ。
    static let maxConcurrentHits = 2
    static let hitMergeWindow: Float = 0.15
    static let hitLife: Float = 0.35

    init(unit u: VelstriaCore.Unit, meshes: StructureMeshes, unitMeshes: UnitMeshLibrary, materials: RenderMaterials, text: TextMeshCache) {
        id = u.id
        isCore = u.kind == .core
        team = u.team
        seed = UInt64(UInt32(bitPattern: u.id)) &* 0x9E37_79B9 &+ 17
        clock = Float(u.id % 7)
        root.name = isCore ? "core_\(u.id)" : "tower_\(u.id)"
        root.position = worldPosition(u.pos)
        let s = meshes.set(u.team)
        let kind: StructureAssets.RigKind = isCore ? .starCore : .tower(u.tower?.tier ?? .outer)
        let rigModel = StructureAssets.rig(kind)
        let rigGeometry = rigModel?.geometry
        // 寸法（部品の外接箱）と結晶・HP バーの高さ
        let geo: TowerGeometry
        let barY: Float
        var orbBox: PartBox?, starBox: PartBox?
        if let g = rigGeometry {
            geo = g
            floatBaseY = g.crystal.center.y
            muzzleHeight = floatBaseY
            barY = g.top + (isCore ? 1.2 : 0.8)
        } else if isCore {
            let base = StructureAssets.model(.coreBase), star = StructureAssets.model(.coreCrystal)
            // 大結晶の下端が台座の上面より 0.35 m 上（従来の高さ 3.6 m より下げない）
            let baseTop = base?.bounds.max.y ?? 1.24
            let half = star.map { -$0.bounds.min.y } ?? 1.5
            floatBaseY = max(3.6, baseTop + half + 0.35)
            muzzleHeight = floatBaseY - 0.2
            barY = floatBaseY + 3.4
            let baseBox = base.map { PartBox(min: $0.bounds.min, max: $0.bounds.max) }
                ?? PartBox(min: [-3.4, 0, -3.4], max: [3.4, 1.24, 3.4])
            starBox = (star.map { PartBox(min: $0.bounds.min, max: $0.bounds.max) }
                ?? PartBox(min: [-1.6, -1.5, -1.6], max: [1.6, 1.5, 1.6])).offset([0, floatBaseY, 0])
            geo = .legacyCore(base: baseBox, rings: PartBox(min: [-2.35, floatBaseY - 0.6, -2.35], max: [2.35, floatBaseY + 0.6, 2.35]),
                              crystal: starBox ?? PartBox(min: [-1, 3, -1], max: [1, 5, 1]))
        } else {
            let tower = StructureAssets.model(.tower), orb = StructureAssets.model(.towerOrb)
            // 生成モデルの塔は頂部の爪（高さ 3.6〜4.35 m、内径約 0.7 m）の中に球（半径約 0.55 m）を浮かべる。
            // 爪の先端 = 外接箱の上端から 0.2 m 下が球の中心（揺れでも爪の根元の台に沈み込まない）
            let fy = tower.map { $0.bounds.max.y - 0.2 } ?? 4.95
            floatBaseY = fy
            muzzleHeight = tower == nil ? 4.5 : fy
            barY = fy + 1.45
            orbBox = orb.map { PartBox(min: $0.bounds.min, max: $0.bounds.max).offset([0, fy, 0]) }
            if let tower {
                geo = .legacyTower(body: PartBox(min: tower.bounds.min, max: tower.bounds.max),
                                   crystal: orbBox ?? PartBox(min: [-0.5, fy - 0.5, -0.5], max: [0.5, fy + 0.5, 0.5]))
            } else {
                var g = TowerGeometry.proceduralTower
                if let orbBox { g.crystal = orbBox }
                geo = g
            }
        }
        geometry = geo
        rigKind = rigGeometry != nil ? rigModel?.kind : nil
        bar = OverheadBar(style: .structure(core: isCore), fillColor: materials.teams.main(u.team), materials: materials,
                          meshes: unitMeshes, text: text)
        let range = Float((isCore ? Balance.coreRange : Balance.towerRange) / Balance.unitsPerMeter)
        rangeRing = ModelEntity(mesh: unitMeshes.ring(radius: range, thickness: 0.12) ?? unitMeshes.unitSphere,
                                materials: [materials.unlit(RGB(1.0, 0.35, 0.3), alpha: 0.85)])

        AssetLedger.record(.entity, "structure nodes")
        root.addChild(plinthNode)
        root.addChild(body)
        for n in [lowerNode, upperNode, crownNode, crystalNode] { body.addChild(n) }
        var generated = 0
        if let r = rigModel, rigGeometry != nil {
            // 複数部品の生成モデル（部品は塔の原点を共有するので、そのまま各部品の枠へ入れる）
            let set = r.materials(u.team)
            let nodes: [TowerPart: Entity] = [.plinth: plinthNode, .lower: lowerNode, .upper: upperNode, .crown: crownNode,
                                              .crystal: crystalNode]
            var made: [TowerPart: [ModelEntity]] = [:]
            for part in TowerPart.allCases {
                let es = r.makeEntities(part, team: u.team)
                guard !es.isEmpty, let node = nodes[part] else { continue }
                for e in es { node.addChild(e) }
                made[part] = es
                generated += 1
            }
            plinthGlow = GlowSlot(made[.plinth] ?? [], set: set)
            bodyGlow = GlowSlot((made[.lower] ?? []) + (made[.upper] ?? []) + (made[.crown] ?? []), set: set)
            crystalGlow = GlowSlot(made[.crystal] ?? [], set: set, gain: StructureVisual.rigCrystalGain)
        } else if isCore {
            let base = StructureAssets.model(.coreBase), star = StructureAssets.model(.coreCrystal)
            if let base {
                // 台座は破壊後も残る（従来の手続きの台座と同じ）
                let e = base.makeEntity(team: u.team)
                plinthNode.addChild(e)
                plinthGlow = GlowSlot([e], set: base.materialSet(u.team))
                generated += 1
            } else {
                if let m = s.coreBase { plinthNode.addChild(ModelEntity(mesh: m, materials: [materials.lit])) }
                if let m = s.coreBaseGlow {
                    let e = ModelEntity(mesh: m, materials: [materials.glow])
                    plinthNode.addChild(e)
                    plinthGlow = GlowSlot([e], off: materials.lit, on: materials.glow)
                }
            }
            let holder = Entity()
            holder.position.y = floatBaseY
            crystalNode.addChild(holder)
            if let star {
                let e = star.makeEntity(team: u.team)
                holder.addChild(e)
                crystalGlow = GlowSlot([e], set: star.materialSet(u.team))
                generated += 1
            } else if let m = s.coreStar {
                let e = ModelEntity(mesh: m, materials: [materials.glow])
                holder.addChild(e)
                crystalGlow = GlowSlot([e], off: materials.lit, on: materials.glow)
            }
            // 回る環は「上部」（崩壊で台座へ沈む）
            let a = Entity(), b = Entity()
            var ringEntities: [ModelEntity] = []
            if let m = s.coreRing {
                let e = ModelEntity(mesh: m, materials: [materials.glow])
                a.addChild(e)
                ringEntities.append(e)
            }
            if let m = s.coreRingSmall {
                let e = ModelEntity(mesh: m, materials: [materials.glow])
                b.addChild(e)
                ringEntities.append(e)
            }
            a.position.y = floatBaseY
            b.position.y = floatBaseY
            upperNode.addChild(a)
            upperNode.addChild(b)
            ringA = a
            ringB = b
            bodyGlow = GlowSlot(ringEntities, off: materials.lit, on: materials.glow)
        } else {
            let tower = StructureAssets.model(.tower), orb = StructureAssets.model(.towerOrb)
            if let tower {
                // 台座ごと 1 つのメッシュ（全体が地面から立ち上がり、足元から倒れる。倒れた後は従来の瓦礫）
                let e = tower.makeEntity(team: u.team)
                upperNode.addChild(e)
                bodyGlow = GlowSlot([e], set: tower.materialSet(u.team))
                generated += 1
                if let m = unitMeshes.rubble {
                    let r = ModelEntity(mesh: m, materials: [materials.lit])
                    r.position.y = 0.6
                    r.isEnabled = false
                    plinthNode.addChild(r)
                    legacyRubble = r
                }
            } else {
                if let m = s.plinth { plinthNode.addChild(ModelEntity(mesh: m, materials: [materials.lit])) }
                if let m = meshes.stump { lowerNode.addChild(ModelEntity(mesh: m, materials: [materials.lit])) }
                if let m = s.pillar { upperNode.addChild(ModelEntity(mesh: m, materials: [materials.lit])) }
                if let m = s.pillarGlow {
                    let e = ModelEntity(mesh: m, materials: [materials.glow])
                    upperNode.addChild(e)
                    bodyGlow = GlowSlot([e], off: materials.lit, on: materials.glow)
                }
            }
            let holder = Entity()
            holder.position.y = floatBaseY
            crystalNode.addChild(holder)
            if let orb {
                let e = orb.makeEntity(team: u.team)
                holder.addChild(e)
                crystalGlow = GlowSlot([e], set: orb.materialSet(u.team))
                generated += 1
            } else if let m = s.crystal {
                let e = ModelEntity(mesh: m, materials: [materials.glow])
                holder.addChild(e)
                crystalGlow = GlowSlot([e], off: materials.lit, on: materials.glow)
            }
            let sh = Entity()
            if let m = s.shards { sh.addChild(ModelEntity(mesh: m, materials: [materials.glow])) }
            sh.position.y = floatBaseY - 0.15
            crystalNode.addChild(sh)
            orbitShards = sh
        }
        generatedParts = generated
        // 結晶片・小破片（倒壊の間だけ出す。作るのはここだけ）
        if let m = s.shardPiece {
            for _ in 0..<TowerPose.shardCapacity(core: isCore) {
                AssetLedger.record(.entity, "structure shard")
                let e = ModelEntity(mesh: m, materials: [materials.glow])
                e.isEnabled = false
                root.addChild(e)
                shardNodes.append(e)
            }
        }
        let chunks = meshes.chunks
        if !chunks.isEmpty {
            for k in 0..<TowerPose.debrisCapacity(core: isCore) {
                AssetLedger.record(.entity, "structure debris")
                let e = ModelEntity(mesh: chunks[k % chunks.count], materials: [materials.lit])
                e.isEnabled = false
                root.addChild(e)
                debrisNodes.append(e)
            }
        }
        if isCore, let m = meshes.column {
            AssetLedger.record(.entity, "core column")
            let e = ModelEntity(mesh: m, materials: [materials.unlit(materials.teams.light(u.team), alpha: VFXSystem.ringAlpha)])
            e.isEnabled = false
            root.addChild(e)
            column = e
        }
        // 結晶の上（手続きメッシュでは従来どおり Core 7.0 m・塔 6.4 m）
        bar.root.position.y = barY
        root.addChild(bar.root)
        rangeRing.position.y = GroundLayer.rangeRing
        rangeRing.isEnabled = false
        OverlayOrder.apply(rangeRing, OverlayOrder.rangeRing)
        root.addChild(rangeRing)
        if !u.isAlive {
            // 最初から壊れている（途中から見る観戦・リプレイ）: 崩れる途中を見せない
            snapNextUpdate = true
            setDestroyed(true)
        }
        // 姿勢は最初の update で時刻から決める（それまでは静止した無傷の姿）
        apply(TowerPose.intact(geometry, seed: seed), alive: u.isAlive)
    }

    private func setDestroyed(_ on: Bool) {
        guard on != destroyed else { return }
        destroyed = on
        bar.root.isEnabled = !on
        if on {
            rangeRing.isEnabled = false
            rangeAlpha = 0
            occlusionAlpha = 1
            body.components.remove(OpacityComponent.self)
            hitTimes.removeAll(keepingCapacity: true)
        } else {
            observedDeath = nil
            rangeAlpha = 0
            rangeRing.isEnabled = false
        }
    }

    /// 次の update で破壊を見つけたら崩れる演出なしで瓦礫にする（シーク・再同期の直後。deathTime の無い状態の時）。
    private var snapNextUpdate = false

    /// 倒れている途中か（着地の後の砂まで。テスト用）。
    var isCollapsing: Bool {
        guard destroyed, let e = lastCollapseElapsed else { return false }
        return e < (isCore ? CoreCollapse.settled : CollapseTimes.of(lastStyle).impact)
    }

    /// presentationEpoch の変化（シーク・再同期）: 次の update は今の時刻の姿勢へそのまま合わせ、
    /// 飛ばした区間の合図（演出・音）を出さない。
    func resetForPresentationEpoch() {
        snapNextUpdate = true
        cueClock = nil
        lastStage = nil
        hitTimes.removeAll(keepingCapacity: true)
    }

    /// 追従ヒーローがこの構造物の奥（画面上で柱に隠れる位置）にいるか。
    func occludes(_ p: SIMD3<Float>) -> Bool {
        let c = root.position
        let dz = c.z - p.z
        return abs(p.x - c.x) < (isCore ? 3.4 : 1.7) && dz > 0.2 && dz < (isCore ? 6.5 : 4.6)
    }

    /// 攻撃の前隙の進み（0〜1）。塔は前隙の間に紋様と結晶が明るくなり、終わりに弾が出る（sim の状態から求める）。
    static func attackCharge(_ u: VelstriaCore.Unit) -> Float {
        guard u.isAlive, let w = u.windupRemaining else { return 0 }
        let total = CombatSystem.attackInterval(u.stats) * Balance.attackWindupRatio
        guard total > 1e-6 else { return 0 }
        return Float(max(0, min(1, 1 - w / total)))
    }

    /// now: 演出時刻（UnitLayer.presentationClock）。style: 倒壊の版。showRange: 視点ヒーローが敵タワーの射程付近にいる。
    /// occluding: 追従ヒーローを隠している（半透明にする）。合図は cues に足す。
    func update(_ f: RenderFrame, index i: Int, now: Double, style: CollapseStyle = .full, showRange: Bool,
                occluding: Bool = false, cues: inout [StructureCueEvent]) {
        let u = f.state.units[i]
        clock += f.dt
        let snap = snapNextUpdate
        snapNextUpdate = false
        // 破壊の時刻: sim の deathTime。無い状態（合成した状態など）は見つけた時刻、シーク直後なら終わった姿
        if u.isAlive {
            observedDeath = nil
        } else if observedDeath == nil {
            observedDeath = snap ? now - 1e6 : now
        }
        let deathTime: Double? = u.isAlive ? nil : (u.deathTime ?? observedDeath)
        setDestroyed(!u.isAlive)
        let stage = u.isAlive ? TowerTimeline.damageStage(hpRatio: u.hpRatio) : 2
        // 損傷の傾きは閾値をまたいだら 0.3 秒ほどで寄せる（シーク・最初は即座に）
        let leanTarget = TowerPose.leanAngle(stage: stage)
        if snap || cueClock == nil {
            lean = leanTarget
        } else {
            let step = 0.15 * f.dt
            lean = abs(leanTarget - lean) <= step ? leanTarget : lean + (leanTarget > lean ? step : -step)
        }
        let input = TowerPoseInput(geometry: geometry, time: now, deathTime: deathTime, hpRatio: u.hpRatio,
                                   charge: StructureVisual.attackCharge(u), lean: lean, style: style, seed: seed)
        // 合図: 前回の評価から今回までに入ったものだけ（シーク直後・時刻が戻った時は出さない）
        if let prev = cueClock, now > prev, !snap {
            for c in TowerPose.cues(input, from: prev, to: now) {
                cues.append(StructureCueEvent(id: id, team: team, isCore: isCore, style: style, cue: c.cue,
                                              position: root.position + c.position, time: c.time))
            }
            if let last = lastStage, stage > last, u.isAlive, !isCore {
                cues.append(StructureCueEvent(id: id, team: team, isCore: isCore, style: style, cue: .damaged,
                                              position: root.position + SIMD3(0, geometry.breakY + 0.3, 0), time: now))
            }
        }
        cueClock = now
        lastStage = stage
        lastStyle = style
        lastCollapseElapsed = deathTime.map { now - $0 }
        // 画面外は姿勢・バーを更新しない（戻った時に今の時刻の姿勢へ合わせる。生死・合図は上で更新済み）
        guard f.needsDetail(i) || snap || !applied else { return }
        let pose = TowerPose.evaluate(input)
        apply(pose, alive: u.isAlive)
        applied = true
        guard u.isAlive else { return }
        // 追従ヒーローを隠す間は支柱と結晶を半透明に
        let occTarget: Float = occluding ? 0.4 : 1
        if abs(occTarget - occlusionAlpha) > 0.01 {
            occlusionAlpha += (occTarget - occlusionAlpha) * min(1, f.dt * 8)
            if abs(occTarget - occlusionAlpha) < 0.02 { occlusionAlpha = occTarget }
            if occlusionAlpha >= 0.995 {
                body.components.remove(OpacityComponent.self)
            } else {
                body.components.set(OpacityComponent(opacity: occlusionAlpha))
            }
        }
        // 従来の Core の環・手続きの塔の小結晶は待機中だけ回す（石の本体は揺れない）
        let t = clock
        ringA?.orientation = simd_quatf(angle: t * 0.8, axis: [0, 1, 0]) * simd_quatf(angle: 0.45, axis: [1, 0, 0])
        ringB?.orientation = simd_quatf(angle: -t * 1.1, axis: [0, 1, 0]) * simd_quatf(angle: -0.6, axis: [0, 0, 1])
        orbitShards?.orientation = simd_quatf(angle: -t * 1.3, axis: [0, 1, 0])
        // 外塔のエネルギーシールドは HP の右に重ねて見せる（HP + シールドが最大 HP を超える間は、全体を 1 本のバーに収める）
        let maxHP = max(1, u.stats.maxHP)
        let shield = max(0, u.totalShield)
        let span = max(maxHP, u.hp + shield)
        bar.update(hp: Float(u.hp / span), shield: Float(shield / span), resource: nil, level: nil, dt: f.dt)
        bar.keepScreenSize(camera: f.camera)
        // 射程円（フェード）
        let target: Float = showRange ? 1 : 0
        rangeAlpha += (target - rangeAlpha) * min(1, f.dt * 6)
        rangeRing.isEnabled = rangeAlpha > 0.02
        if rangeRing.isEnabled {
            rangeRing.components.set(OpacityComponent(opacity: rangeAlpha * (0.75 + sin(t * 4) * 0.2)))
        }
    }

    // MARK: 姿勢の反映

    private func apply(_ p: TowerPose, alive: Bool) {
        lastPhase = p.phase
        setNode(plinthNode, p.plinth, 0)
        setNode(lowerNode, p.lower, 1)
        setNode(upperNode, p.upper, 2)
        setNode(crownNode, p.crown, 3)
        setNode(crystalNode, p.crystal, 4)
        // 従来の生成モデルの塔: 台座ごと倒れるので、倒れ始めたら足元に従来の瓦礫を出す
        if let r = legacyRubble {
            let show = !alive && p.phase.rawValue >= TowerPose.Phase.toppling.rawValue
            if r.isEnabled != show { r.isEnabled = show }
        }
        plinthGlow.set(glow: p.plinthGlow, ruined: p.ruined)
        bodyGlow.set(glow: p.bodyGlow, ruined: p.ruined)
        crystalGlow.set(glow: p.crystalGlow, ruined: false)
        // 破片（無い間は一度だけ全て隠す）
        if p.shards.isEmpty && p.debris.isEmpty {
            if piecesShown {
                for e in shardNodes { e.isEnabled = false }
                for e in debrisNodes { e.isEnabled = false }
                piecesShown = false
            }
        } else {
            piecesShown = true
            setPieces(shardNodes, p.shards, cache: &shardCache)
            setPieces(debrisNodes, p.debris, cache: &debrisCache)
        }
        // Core の光の柱
        if let column {
            let show = p.column > 0.01
            if show {
                let c = geometry.crystal.center
                column.position = SIMD3(c.x, geometry.plinthTop, c.z)
                let w = 0.35 + 0.65 * p.column
                column.scale = SIMD3(w * 1.1, 16, w * 1.1)
                column.components.set(OpacityComponent(opacity: 0.55 * p.column))
            }
            if show != columnShown {
                column.isEnabled = show
                columnShown = show
            }
        }
    }

    private func setNode(_ e: Entity, _ piece: TowerPose.Piece, _ k: Int) {
        if e.isEnabled != piece.visible { e.isEnabled = piece.visible }
        guard piece.visible, nodeCache[k] != piece.matrix else { return }
        nodeCache[k] = piece.matrix
        e.transform = Transform(matrix: piece.matrix)
    }

    private func setPieces(_ nodes: [ModelEntity], _ pieces: [TowerPose.Piece], cache: inout [simd_float4x4]) {
        if cache.count != nodes.count {
            cache = Array(repeating: simd_float4x4(diagonal: SIMD4(repeating: .nan)), count: nodes.count)
        }
        for (k, e) in nodes.enumerated() {
            guard k < pieces.count, pieces[k].visible else {
                if e.isEnabled { e.isEnabled = false }
                continue
            }
            let piece = pieces[k]
            if !e.isEnabled { e.isEnabled = true }
            if cache[k] != piece.matrix {
                cache[k] = piece.matrix
                e.transform = Transform(matrix: piece.matrix)
            }
            if piece.opacity < 0.995 {
                e.components.set(OpacityComponent(opacity: max(0, piece.opacity)))
            } else if e.components.has(OpacityComponent.self) {
                e.components.remove(OpacityComponent.self)
            }
        }
    }

    // MARK: 被弾

    /// 被弾の演出の位置（攻撃者に向いた側面）。同時 2 つまで、0.15 秒以内の被弾は 1 つにまとめる（nil = 出さない）。
    func hitPoint(toward attacker: SIMD3<Float>, time: Float) -> SIMD3<Float>? {
        guard !destroyed else { return nil }
        hitTimes.removeAll { time - $0 > StructureVisual.hitLife || $0 > time }
        if let last = hitTimes.last, time - last < StructureVisual.hitMergeWindow { return nil }
        guard hitTimes.count < StructureVisual.maxConcurrentHits else { return nil }
        hitTimes.append(time)
        var d = attacker - root.position
        d.y = 0
        let len = simd_length(d)
        let dir = len > 1e-3 ? d / len : SIMD3<Float>(0, 0, 1)
        let k = Float(TowerPose.hash(seed, Int(time * 60)))
        let y: Float = isCore ? geometry.plinthTop + 0.3 + 0.5 * k
            : min(geometry.breakY + 0.5 + 1.0 * k, geometry.upper.max.y - 0.4)
        return root.position + dir * geometry.hitRadius + SIMD3(0, y, 0)
    }

    // MARK: テスト用

    /// 部品の今の姿勢と表示（テスト用）。
    func partState(_ part: TowerPart) -> (matrix: simd_float4x4, visible: Bool) {
        let e: Entity
        switch part {
        case .plinth: e = plinthNode
        case .lower: e = lowerNode
        case .upper: e = upperNode
        case .crown: e = crownNode
        case .crystal: e = crystalNode
        }
        return (e.transform.matrix, e.isEnabled && !e.children.isEmpty)
    }

    /// 表示中の結晶片・小破片の数（テスト用）。
    var visiblePieces: (shards: Int, debris: Int) {
        (shardNodes.filter(\.isEnabled).count, debrisNodes.filter(\.isEnabled).count)
    }

    /// この構造物が持つエンティティの数（予算のテスト用。HP バー・射程円を除く）。
    var entityCount: Int {
        func count(_ e: Entity) -> Int { 1 + e.children.reduce(0) { $0 + count($1) } }
        return count(root) - count(bar.root) - 1
    }

    /// 同時に出ている被弾の演出の数（テスト用）。
    func activeHits(at time: Float) -> Int { hitTimes.filter { time - $0 <= StructureVisual.hitLife }.count }
}
