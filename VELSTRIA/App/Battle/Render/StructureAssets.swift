import Foundation
import os
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。タワー・本拠地（Core）・ミニオンの生成 3D モデル（tools/structures/ で作る Struct_<id>.usdz）。
// 読み込みは試合の準備中に非同期で 1 度だけ（BattlePreload が始め、BattleRenderer が世界を作る前に待つ）。
// 試合中は同期で読まない: 読み込みが済んでいない・失敗した種類は nil を返し、呼び出し側は従来の手続きメッシュを使う。
// チーム色: メッシュは 1 つ。青は USDZ の材質、赤は色相を付け替えたテクスチャ（Struct_<id>_red.jpg / _red_emit.jpg）へ差し替えた複製。
//
// 複数部品の塔（RigKind: Struct_tower_outer / _inner / _base / Struct_star_core）: 子メッシュの名前（TowerPart の
// part_plinth / part_lower / part_upper / part_crown / part_crystal。Core は plinth・upper・crystal）で部品を集め、
// 1 つの共有材質をチーム別・発光の段階別（MaterialSet）に複製する。部品は塔の原点を共有する。
// 無い・部品が欠ける・予算を超える種類は nil（StructureVisual は従来の 1 つのメッシュ → 手続きメッシュの順に戻る）。
// 起動引数 -legacyStructures で複数部品のモデルを使わずに従来のモデルで比べられる（isEnabled = false は全て手続き）。

private let structureAssetLog = Logger(subsystem: "com.bitcoinpay.velstria", category: "StructureAssets")

@MainActor
enum StructureAssets {
    enum Kind: String, CaseIterable, Sendable {
        case tower
        case towerOrb = "tower_orb"
        case coreBase = "core_base"
        case coreCrystal = "core_crystal"
        case minionMelee = "minion_melee"
        case minionRanged = "minion_ranged"
        case minionSiege = "minion_siege"

        var fileName: String { "Struct_\(rawValue)" }

        /// 塔・Core の部位（ミニオン以外）。
        var isStructure: Bool {
            switch self {
            case .tower, .towerOrb, .coreBase, .coreCrystal: return true
            case .minionMelee, .minionRanged, .minionSiege: return false
            }
        }

        static func minion(_ t: MinionType) -> Kind {
            switch t {
            case .melee: return .minionMelee
            case .ranged: return .minionRanged
            case .siege: return .minionSiege
            }
        }

        /// 三角形の上限（docs/BATTLE_PERFORMANCE.md。ミニオンは画面に 30 体以上出る）。
        var triangleBudget: Int {
            switch self {
            case .tower, .coreBase: return 6000
            case .towerOrb, .coreCrystal: return 2500
            case .minionMelee, .minionRanged, .minionSiege: return 2500
            }
        }
    }

    /// 読み込んだ 1 種類（メッシュは共有、材質はチーム別）。
    @MainActor
    final class Model {
        let kind: Kind
        let mesh: MeshResource
        /// USDZ 内のメッシュの変換（ルート基準。通常は単位行列）。
        let transform: Transform
        let blue: RealityKit.Material
        let red: RealityKit.Material
        /// メッシュの範囲（transform 込み）。
        let bounds: BoundingBox
        let triangleCount: Int
        /// 発光の段階・破損の材質（構造物だけ。ミニオンは nil）。
        let sets: (blue: MaterialSet, red: MaterialSet)?

        init(kind: Kind, mesh: MeshResource, transform: Transform, blue: RealityKit.Material, red: RealityKit.Material,
             sets: (blue: MaterialSet, red: MaterialSet)? = nil) {
            self.kind = kind
            self.mesh = mesh
            self.transform = transform
            self.blue = blue
            self.red = red
            self.sets = sets
            bounds = StructureAssets.bounds(of: mesh, transform: transform.matrix)
            triangleCount = HeroAssetLibrary.triangleCount(mesh)
        }

        func material(_ team: Team) -> RealityKit.Material { team == .red ? red : blue }
        func materialSet(_ team: Team) -> MaterialSet? { team == .red ? sets?.red : sets?.blue }

        /// 表示用のエンティティ（メッシュ・材質は共有）。
        func makeEntity(team: Team) -> ModelEntity {
            AssetLedger.record(.entity, "structure model \(kind.rawValue)")
            let e = ModelEntity(mesh: mesh, materials: [material(team)])
            e.name = kind.fileName
            e.transform = transform
            return e
        }
    }

    /// 生成モデルを使うか（テスト・比較用に切れる。切ると全て手続きメッシュ。起動引数 -proceduralStructures でも切れる）。
    static var isEnabled = !ProcessInfo.processInfo.arguments.contains("-proceduralStructures")
    /// 複数部品の塔を使わず従来のモデルにする（起動引数 -legacyStructures。新旧の見比べ用）。
    static var useLegacyModels = ProcessInfo.processInfo.arguments.contains("-legacyStructures")
    /// 名前・拡張子 → 同梱ファイルの URL（テストで差し替える）。
    static var resolver: (String, String) -> URL? = { Bundle.main.url(forResource: $0, withExtension: $1) }
    /// 発光の強さ（USD Preview Surface には強さの入力が無いので実行時に掛ける）。
    static let emissiveIntensity: Float = 1.6

    private static var models: [Kind: Model] = [:]
    private static var rigs: [RigKind: RigModel] = [:]
    private static var attempted = false
    private static var task: Task<Void, Never>?

    /// 同梱されているか（Struct_tower.usdz の有無）。
    static var isBundled: Bool { resolver(Kind.tower.fileName, "usdz") != nil }

    /// 読み込み済みのモデル（未読み込み・失敗・無効なら nil = 手続きメッシュ）。試合中に読み込みは始めない。
    static func model(_ kind: Kind) -> Model? {
        guard isEnabled else { return nil }
        return models[kind]
    }

    /// 読み込み済みの全モデル（ウォームアップの陳列用）。
    static var loadedModels: [Model] { Kind.allCases.compactMap { model($0) } }

    /// 読み込み済みの複数部品の塔（未読み込み・失敗・無効・-legacyStructures なら nil = 従来のモデルか手続き）。
    static func rig(_ kind: RigKind) -> RigModel? {
        guard isEnabled, !useLegacyModels else { return nil }
        return rigs[kind]
    }

    /// 読み込み済みの全ての複数部品の塔（ウォームアップの陳列用）。
    static var loadedRigs: [RigModel] { RigKind.allCases.compactMap { rig($0) } }

    /// 読み込みを始める（済み・進行中なら何もしない）。
    static func prefetch() {
        guard isEnabled, !attempted, task == nil else { return }
        task = Task { @MainActor in
            await loadAll()
            attempted = true
            task = nil
        }
    }

    /// 読み込みの完了を待つ（始めていなければ始める）。
    static func load() async {
        guard isEnabled, !attempted else { return }
        prefetch()
        await task?.value
    }

    private static func loadAll() async {
        let start = CFAbsoluteTimeGetCurrent()
        for kind in Kind.allCases where models[kind] == nil {
            if let m = await loadModel(kind) { models[kind] = m }
        }
        if !useLegacyModels {
            for kind in RigKind.allCases where rigs[kind] == nil {
                if let r = await loadRig(kind) { rigs[kind] = r }
            }
        }
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        structureAssetLog.info("loaded \(models.count, privacy: .public)/\(Kind.allCases.count, privacy: .public) + rigs \(rigs.count, privacy: .public)/\(RigKind.allCases.count, privacy: .public) in \(String(format: "%.0f", ms), privacy: .public) ms")
    }

    private static func loadModel(_ kind: Kind) async -> Model? {
        guard let url = resolver(kind.fileName, "usdz") else { return nil }
        do {
            let root = try await Entity(contentsOf: url)
            guard let (entity, component) = firstModel(in: root) else {
                structureAssetLog.error("\(kind.fileName, privacy: .public): メッシュが無い")
                return nil
            }
            guard var pbr = component.materials.first as? PhysicallyBasedMaterial else {
                structureAssetLog.error("\(kind.fileName, privacy: .public): 材質が PBR ではない")
                return nil
            }
            pbr.roughness = .init(floatLiteral: 0.7)
            pbr.metallic = .init(floatLiteral: 0)
            pbr.specular = .init(floatLiteral: 0.3)
            pbr.emissiveIntensity = emissiveIntensity
            var red = pbr
            if let u = resolver("\(kind.fileName)_red", "jpg") {
                red.baseColor.texture = .init(try await TextureResource(contentsOf: u, options: .init(semantic: .color)))
                AssetLedger.record(.texture, "\(kind.fileName)_red")
            }
            if let u = resolver("\(kind.fileName)_red_emit", "jpg") {
                red.emissiveColor.texture = .init(try await TextureResource(contentsOf: u, options: .init(semantic: .color)))
                AssetLedger.record(.texture, "\(kind.fileName)_red_emit")
            }
            AssetLedger.record(.mesh, kind.fileName)
            AssetLedger.record(.material, "\(kind.fileName) blue")
            AssetLedger.record(.material, "\(kind.fileName) red")
            // 構造物は発光の段階（結晶の点灯・攻撃の溜め・損傷）と破損の材質も作っておく（試合中に材質を作らない）
            let sets = kind.isStructure ? (blue: materialSet(pbr, label: "\(kind.fileName) blue"),
                                           red: materialSet(red, label: "\(kind.fileName) red")) : nil
            let model = Model(kind: kind, mesh: component.mesh, transform: Transform(matrix: entity.transformMatrix(relativeTo: root)),
                              blue: pbr, red: red, sets: sets)
            if model.triangleCount > kind.triangleBudget {
                // 予算超過のアセットは使わない（手続きメッシュへ戻す）
                structureAssetLog.error("\(kind.fileName, privacy: .public): \(model.triangleCount) 三角形（上限 \(kind.triangleBudget)）")
                return nil
            }
            return model
        } catch {
            structureAssetLog.error("\(kind.fileName, privacy: .public): 読み込み失敗 \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func firstModel(in e: Entity) -> (Entity, ModelComponent)? {
        if let m = e.components[ModelComponent.self] { return (e, m) }
        for c in e.children {
            if let r = firstModel(in: c) { return r }
        }
        return nil
    }

    private static func allModels(in e: Entity, into out: inout [(Entity, ModelComponent)]) {
        if let m = e.components[ModelComponent.self] { out.append((e, m)) }
        for c in e.children { allModels(in: c, into: &out) }
    }

    /// メッシュの外接箱（変換込み）。
    static func bounds(of mesh: MeshResource, transform m: simd_float4x4) -> BoundingBox {
        let b = mesh.bounds
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for x in [b.min.x, b.max.x] {
            for y in [b.min.y, b.max.y] {
                for z in [b.min.z, b.max.z] {
                    let p = m * SIMD4(x, y, z, 1)
                    lo = simd_min(lo, SIMD3(p.x, p.y, p.z))
                    hi = simd_max(hi, SIMD3(p.x, p.y, p.z))
                }
            }
        }
        return BoundingBox(min: lo, max: hi)
    }

    // MARK: 発光の段階

    /// 発光の段階（emissiveIntensity への倍率）。結晶の点灯・攻撃の溜め・損傷の減光は、この段階の材質への差し替えで表す
    /// （材質は読み込み中に作り、試合中は作らない）。
    nonisolated static let glowLevels: [Float] = [0.03, 0.3, 0.65, 1.0, 1.7, 2.8]

    /// 明るさ（0 = 消灯、1 = 通常）→ 最も近い段階。
    nonisolated static func glowLevel(_ g: Float) -> Int {
        var best = 0
        var bestD = Float.greatestFiniteMagnitude
        for (k, v) in glowLevels.enumerated() {
            let d = abs(v - g)
            if d < bestD { bestD = d; best = k }
        }
        return best
    }

    /// 1 チーム分の材質（発光の段階 + 破損 = 紋様の消えた暗い石）。
    struct MaterialSet {
        let levels: [RealityKit.Material]
        let ruin: RealityKit.Material

        func material(glow: Float, ruined: Bool) -> RealityKit.Material {
            ruined ? ruin : levels[StructureAssets.glowLevel(glow)]
        }
    }

    static func materialSet(_ base: PhysicallyBasedMaterial, label: String) -> MaterialSet {
        var levels: [RealityKit.Material] = []
        for (k, s) in glowLevels.enumerated() {
            var m = base
            m.emissiveIntensity = emissiveIntensity * s
            AssetLedger.record(.material, "\(label) glow\(k)")
            levels.append(m)
        }
        var ruin = base
        ruin.emissiveIntensity = 0
        ruin.baseColor.tint = UIColor(white: 0.6, alpha: 1)
        AssetLedger.record(.material, "\(label) ruin")
        return MaterialSet(levels: levels, ruin: ruin)
    }

    // MARK: 複数部品の塔

    /// 複数部品の塔の種類（外塔・内塔・基地塔・Star Core）。
    enum RigKind: String, CaseIterable, Sendable {
        case towerOuter = "tower_outer"
        case towerInner = "tower_inner"
        case towerBase = "tower_base"
        case starCore = "star_core"

        var fileName: String { "Struct_\(rawValue)" }
        var isCore: Bool { self == .starCore }

        /// 必要な部品（1 つでも欠けたら使わない）。
        var parts: [TowerPart] { isCore ? [.plinth, .upper, .crystal] : TowerPart.allCases }

        static func tower(_ tier: TowerTier) -> RigKind {
            switch tier {
            case .outer: return .towerOuter
            case .inner: return .towerInner
            case .base: return .towerBase
            }
        }

        /// 三角形の上限（docs/BATTLE_PERFORMANCE.md の塔・Core 台座 6k / 結晶 2.5k と同じ）: 結晶以外の合計と結晶。
        static let bodyTriangleBudget = 6000
        static let crystalTriangleBudget = 2500
    }

    /// 読み込んだ複数部品の塔（メッシュは共有、材質はチーム別・発光の段階別）。
    @MainActor
    final class RigModel {
        struct PartMesh {
            let mesh: MeshResource
            /// USDZ 内の変換（ルート基準。部品は塔の原点を共有する）。
            let transform: Transform
            let bounds: BoundingBox
            let triangles: Int
        }

        let kind: RigKind
        let parts: [TowerPart: [PartMesh]]
        let blue: MaterialSet
        let red: MaterialSet

        init(kind: RigKind, parts: [TowerPart: [PartMesh]], blue: MaterialSet, red: MaterialSet) {
            self.kind = kind
            self.parts = parts
            self.blue = blue
            self.red = red
        }

        func materials(_ team: Team) -> MaterialSet { team == .red ? red : blue }

        /// 部品の外接箱（複数のメッシュならその和）。
        func box(_ part: TowerPart) -> PartBox? {
            guard let list = parts[part], !list.isEmpty else { return nil }
            var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
            for p in list {
                lo = simd_min(lo, p.bounds.min)
                hi = simd_max(hi, p.bounds.max)
            }
            return PartBox(min: lo, max: hi)
        }

        var geometry: TowerGeometry? {
            var boxes: [TowerPart: PartBox] = [:]
            for p in TowerPart.allCases { boxes[p] = box(p) }
            return TowerGeometry.rig(isCore: kind.isCore, boxes: boxes)
        }

        /// 結晶以外の三角形の合計。
        var bodyTriangles: Int {
            parts.filter { $0.key != .crystal }.values.reduce(0) { $0 + $1.reduce(0) { $0 + $1.triangles } }
        }
        var crystalTriangles: Int { (parts[.crystal] ?? []).reduce(0) { $0 + $1.triangles } }

        /// 部品の表示用エンティティ（メッシュ・材質は共有）。
        func makeEntities(_ part: TowerPart, team: Team) -> [ModelEntity] {
            (parts[part] ?? []).map { p in
                AssetLedger.record(.entity, "structure rig \(kind.rawValue) \(part.rawValue)")
                let e = ModelEntity(mesh: p.mesh, materials: [materials(team).levels[3]])
                e.name = part.rawValue
                e.transform = p.transform
                return e
            }
        }
    }

    private static func loadRig(_ kind: RigKind) async -> RigModel? {
        guard let url = resolver(kind.fileName, "usdz") else { return nil }
        do {
            let root = try await Entity(contentsOf: url)
            var redBase: TextureResource?, redEmit: TextureResource?
            if let u = resolver("\(kind.fileName)_red", "jpg") {
                redBase = try await TextureResource(contentsOf: u, options: .init(semantic: .color))
                AssetLedger.record(.texture, "\(kind.fileName)_red")
            }
            if let u = resolver("\(kind.fileName)_red_emit", "jpg") {
                redEmit = try await TextureResource(contentsOf: u, options: .init(semantic: .color))
                AssetLedger.record(.texture, "\(kind.fileName)_red_emit")
            }
            return assembleRig(kind, root: root, redBase: redBase, redEmit: redEmit)
        } catch {
            structureAssetLog.error("\(kind.fileName, privacy: .public): 読み込み失敗 \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 名前の部品（その名前のエンティティ、または「名前_」「名前.」で始まるエンティティ。最初に見つかったもの）。
    static func findPart(_ part: TowerPart, in e: Entity) -> Entity? {
        let n = e.name
        if n == part.rawValue || n.hasPrefix(part.rawValue + "_") || n.hasPrefix(part.rawValue + ".") { return e }
        for c in e.children {
            if let r = findPart(part, in: c) { return r }
        }
        return nil
    }

    /// 読み込んだ木構造から部品を集めて塔のモデルにする（読み込みとテストで共有）。部品が欠ける・材質が PBR でない・
    /// 予算を超える・寸法が求まらないなら nil。
    static func assembleRig(_ kind: RigKind, root: Entity, redBase: TextureResource?, redEmit: TextureResource?) -> RigModel? {
        var parts: [TowerPart: [RigModel.PartMesh]] = [:]
        var shared: PhysicallyBasedMaterial?
        for part in kind.parts {
            guard let node = findPart(part, in: root) else {
                structureAssetLog.error("\(kind.fileName, privacy: .public): 部品 \(part.rawValue, privacy: .public) が無い")
                return nil
            }
            var found: [(Entity, ModelComponent)] = []
            allModels(in: node, into: &found)
            guard !found.isEmpty else {
                structureAssetLog.error("\(kind.fileName, privacy: .public): \(part.rawValue, privacy: .public) にメッシュが無い")
                return nil
            }
            parts[part] = found.map { e, c in
                let m = e.transformMatrix(relativeTo: root)
                return RigModel.PartMesh(mesh: c.mesh, transform: Transform(matrix: m), bounds: bounds(of: c.mesh, transform: m),
                                         triangles: HeroAssetLibrary.triangleCount(c.mesh))
            }
            if shared == nil { shared = found.lazy.compactMap { $0.1.materials.first as? PhysicallyBasedMaterial }.first }
        }
        guard var pbr = shared else {
            structureAssetLog.error("\(kind.fileName, privacy: .public): 材質が PBR ではない")
            return nil
        }
        // 石は艶を抑える（金属は控えめな反射。塗り分けはテクスチャ側）
        pbr.roughness = .init(floatLiteral: 0.75)
        pbr.metallic = .init(floatLiteral: 0)
        pbr.specular = .init(floatLiteral: 0.3)
        pbr.emissiveIntensity = emissiveIntensity
        var red = pbr
        if let redBase { red.baseColor.texture = .init(redBase) }
        if let redEmit { red.emissiveColor.texture = .init(redEmit) }
        let rig = RigModel(kind: kind, parts: parts, blue: materialSet(pbr, label: "\(kind.fileName) blue"),
                           red: materialSet(red, label: "\(kind.fileName) red"))
        if rig.bodyTriangles > RigKind.bodyTriangleBudget || rig.crystalTriangles > RigKind.crystalTriangleBudget {
            // 予算超過のアセットは使わない（従来のモデルへ戻す）
            structureAssetLog.error("\(kind.fileName, privacy: .public): 本体 \(rig.bodyTriangles) / 結晶 \(rig.crystalTriangles) 三角形（上限 \(RigKind.bodyTriangleBudget) / \(RigKind.crystalTriangleBudget)）")
            return nil
        }
        guard rig.geometry != nil else {
            structureAssetLog.error("\(kind.fileName, privacy: .public): 部品の寸法が求まらない")
            return nil
        }
        for part in kind.parts { AssetLedger.record(.mesh, "\(kind.fileName) \(part.rawValue)") }
        return rig
    }

    /// テスト用: 組み立てた塔を読み込み済みとして置く（nil で外す）。
    static func setRigForTesting(_ kind: RigKind, _ rig: RigModel?) {
        attempted = true
        rigs[kind] = rig
    }

    /// テスト用: キャッシュを捨てて初期状態へ戻す。
    static func resetForTesting() {
        task?.cancel()
        task = nil
        models = [:]
        rigs = [:]
        attempted = false
        isEnabled = true
        useLegacyModels = false
        resolver = { Bundle.main.url(forResource: $0, withExtension: $1) }
    }
}
