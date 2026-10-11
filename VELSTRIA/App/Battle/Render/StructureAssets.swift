import Foundation
import os
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。タワー・本拠地（Core）・ミニオンの生成 3D モデル（tools/structures/ で作る Struct_<id>.usdz）。
// 読み込みは試合の準備中に非同期で 1 度だけ（BattlePreload が始め、BattleRenderer が世界を作る前に待つ）。
// 試合中は同期で読まない: 読み込みが済んでいない・失敗した種類は nil を返し、呼び出し側は従来の手続きメッシュを使う。
// チーム色: メッシュは 1 つ。青は USDZ の材質、赤は色相を付け替えたテクスチャ（Struct_<id>_red.jpg / _red_emit.jpg）へ差し替えた複製。

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

        init(kind: Kind, mesh: MeshResource, transform: Transform, blue: RealityKit.Material, red: RealityKit.Material) {
            self.kind = kind
            self.mesh = mesh
            self.transform = transform
            self.blue = blue
            self.red = red
            let b = mesh.bounds
            let m = transform.matrix
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
            bounds = BoundingBox(min: lo, max: hi)
            triangleCount = HeroAssetLibrary.triangleCount(mesh)
        }

        func material(_ team: Team) -> RealityKit.Material { team == .red ? red : blue }

        /// 表示用のエンティティ（メッシュ・材質は共有）。
        func makeEntity(team: Team) -> ModelEntity {
            AssetLedger.record(.entity, "structure model \(kind.rawValue)")
            let e = ModelEntity(mesh: mesh, materials: [material(team)])
            e.name = kind.fileName
            e.transform = transform
            return e
        }
    }

    /// 生成モデルを使うか（テスト・比較用に切れる。切ると全て手続きメッシュ）。
    static var isEnabled = true
    /// 名前・拡張子 → 同梱ファイルの URL（テストで差し替える）。
    static var resolver: (String, String) -> URL? = { Bundle.main.url(forResource: $0, withExtension: $1) }
    /// 発光の強さ（USD Preview Surface には強さの入力が無いので実行時に掛ける）。
    static let emissiveIntensity: Float = 1.6

    private static var models: [Kind: Model] = [:]
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
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        structureAssetLog.info("loaded \(models.count, privacy: .public)/\(Kind.allCases.count, privacy: .public) in \(String(format: "%.0f", ms), privacy: .public) ms")
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
            let model = Model(kind: kind, mesh: component.mesh, transform: Transform(matrix: entity.transformMatrix(relativeTo: root)),
                              blue: pbr, red: red)
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

    /// テスト用: キャッシュを捨てて初期状態へ戻す。
    static func resetForTesting() {
        task?.cancel()
        task = nil
        models = [:]
        attempted = false
        isEnabled = true
        resolver = { Bundle.main.url(forResource: $0, withExtension: $1) }
    }
}
