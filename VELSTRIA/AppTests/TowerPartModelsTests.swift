import ImageIO
import RealityKit
import XCTest
@testable import VELSTRIA

/// 塔・Star Core の部品分けモデル（tools/structures/tower_parts.py → App/Resources/Structures/Struct_<id>.usdz）:
/// 部品の子メッシュ名（TowerTimeline.swift の part_*）・三角形の予算（塔 6k・Star Core 9k、部品の合計）・寸法
/// （足元が地面、足跡が従来の台座から大きくはみ出さない）・部品が共通の原点のままであること・材質と赤チームのテクスチャ。
@MainActor
final class TowerPartModelsTests: XCTestCase {
    private struct Spec {
        let file: String
        let parts: [String]
        let budget: Int
        let height: ClosedRange<Float>
        /// 足跡（中心から x・z の最大距離）の上限 m。
        let reach: Float
    }

    private static let towerParts = ["part_plinth", "part_lower", "part_upper", "part_crown", "part_crystal"]
    private let specs: [Spec] = [
        Spec(file: "Struct_tower_outer", parts: towerParts, budget: 6000, height: 5.35...5.45, reach: 1.9),
        Spec(file: "Struct_tower_inner", parts: towerParts, budget: 6000, height: 4.4...4.7, reach: 2.15),
        Spec(file: "Struct_tower_base", parts: towerParts, budget: 6000, height: 4.5...4.8, reach: 2.45),
        Spec(file: "Struct_star_core", parts: ["part_plinth", "part_upper", "part_crystal"], budget: 9000, height: 3.8...4.1,
             reach: 3.55),
    ]

    private func models(in e: Entity) -> [Entity] {
        (e.components[ModelComponent.self] == nil ? [] : [e]) + e.children.flatMap { models(in: $0) }
    }

    func testPartModelsLoadWithinBudgetsAndSizes() async throws {
        for s in specs {
            let url = try XCTUnwrap(Bundle.main.url(forResource: s.file, withExtension: "usdz"), s.file)
            let root = try await Entity(contentsOf: url)
            // メッシュは部品だけ（部品名の物体か、その子）
            let all = models(in: root)
            XCTAssertEqual(all.count, s.parts.count, "\(s.file) のメッシュ数")
            var total = 0
            var bounds: [String: BoundingBox] = [:]
            for name in s.parts {
                let part = try XCTUnwrap(root.findEntity(named: name), "\(s.file) \(name)")
                let meshes = models(in: part)
                XCTAssertEqual(meshes.count, 1, "\(s.file) \(name)")
                let m = try XCTUnwrap(meshes.first)
                // 部品の原点は塔の原点のまま（動かすのは実行時の変換だけ）
                let t = m.transformMatrix(relativeTo: root)
                XCTAssertEqual(t.columns.3.x, 0, accuracy: 1e-4, "\(s.file) \(name) の原点")
                XCTAssertEqual(t.columns.3.y, 0, accuracy: 1e-4, "\(s.file) \(name) の原点")
                XCTAssertEqual(t.columns.3.z, 0, accuracy: 1e-4, "\(s.file) \(name) の原点")
                let tris = HeroAssetLibrary.triangleCount(m)
                XCTAssertGreaterThan(tris, 8, "\(s.file) \(name)")
                total += tris
                bounds[name] = m.visualBounds(relativeTo: root)
                let pbr = try XCTUnwrap(m.components[ModelComponent.self]?.materials.first as? PhysicallyBasedMaterial,
                                        "\(s.file) \(name) の材質")
                XCTAssertNotNil(pbr.baseColor.texture, "\(s.file) \(name)")
                XCTAssertNotNil(pbr.emissiveColor.texture, "\(s.file) \(name) 発光")
            }
            XCTAssertLessThanOrEqual(total, s.budget, "\(s.file) 三角形（部品の合計）")
            let all3 = bounds.values.reduce(bounds.values.first!) { $0.union($1) }
            XCTAssertEqual(all3.min.y, 0, accuracy: 0.02, "\(s.file) 足元が地面")
            XCTAssertTrue(s.height.contains(all3.max.y), "\(s.file) 高さ \(all3.max.y)")
            let reach = max(abs(all3.min.x), abs(all3.max.x), abs(all3.min.z), abs(all3.max.z))
            XCTAssertLessThanOrEqual(reach, s.reach, "\(s.file) 足跡")
            // 結晶は中心の上（浮遊・回転の軸）、台座が一番下
            let crystal = try XCTUnwrap(bounds["part_crystal"])
            XCTAssertLessThan(simd_length(SIMD2(crystal.center.x, crystal.center.z)), 0.3, "\(s.file) 結晶が中心")
            XCTAssertGreaterThan(crystal.min.y, 1.0, "\(s.file) 結晶が台座より上")
            XCTAssertEqual(try XCTUnwrap(bounds["part_plinth"]).min.y, 0, accuracy: 0.02, "\(s.file) 台座が地面")
            if s.parts.contains("part_crown") {
                let lower = try XCTUnwrap(bounds["part_lower"]), upper = try XCTUnwrap(bounds["part_upper"])
                let crown = try XCTUnwrap(bounds["part_crown"])
                XCTAssertLessThan(lower.center.y, upper.center.y, "\(s.file) 下半 < 上半")
                XCTAssertLessThan(upper.center.y, crown.center.y, "\(s.file) 上半 < 頂部")
                XCTAssertGreaterThan(crystal.max.y, crown.center.y, "\(s.file) 結晶は頂部の上")
            }
        }
    }

    /// 赤チームのテクスチャ（色相の付け替え）は 1024 px 以下。
    func testRedTexturesExistWithinSizeLimit() throws {
        for s in specs {
            for suffix in ["_red", "_red_emit"] {
                let url = try XCTUnwrap(Bundle.main.url(forResource: s.file + suffix, withExtension: "jpg"), s.file + suffix)
                let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
                let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
                XCTAssertLessThanOrEqual(props[kCGImagePropertyPixelWidth] as? Int ?? .max, 1024, s.file + suffix)
            }
        }
    }
}
