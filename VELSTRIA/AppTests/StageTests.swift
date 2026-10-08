import CryptoKit
import Metal
import RealityKit
import simd
import XCTest
@testable import VELSTRIA
import VelstriaCore

// battle-renderer（ステージ）: 素材・シェーダー・配合マップ・配置の規則（docs/STAGE.md）のテスト。

@MainActor
final class StageTests: XCTestCase {
    private var assets: StageAssets {
        get throws { try XCTUnwrap(StageAssets.load(), "App/Resources/Stage の素材が読めない") }
    }

    func testAssetsLoad() throws {
        let a = try assets
        XCTAssertEqual(Set(a.props.keys), Set(StagePropKind.allCases))
        for t in StageTile.allCases {
            let img = try XCTUnwrap(a.tiles[t])
            XCTAssertEqual(img.width, 1024, t.rawValue)
            XCTAssertEqual(img.height, 1024, t.rawValue)
        }
        XCTAssertEqual(a.atlas.width, 2048)
        XCTAssertEqual(a.atlas.height, 1024)
        for (kind, m) in a.props {
            XCTAssertFalse(m.indices.isEmpty, kind.rawValue)
            XCTAssertEqual(m.positions.count, m.normals.count)
            XCTAssertEqual(m.positions.count, m.uvs.count)
            // 足跡の中心が原点・底が y = 0
            XCTAssertEqual(m.boundsMin.y, 0, accuracy: 0.01, kind.rawValue)
            XCTAssertEqual((m.boundsMin.x + m.boundsMax.x) / 2, 0, accuracy: 0.02, kind.rawValue)
            XCTAssertEqual((m.boundsMin.z + m.boundsMax.z) / 2, 0, accuracy: 0.02, kind.rawValue)
        }
        // 木は縦長、崖の岩は横長（+X が長辺）
        let tree = try XCTUnwrap(a.props[.treeTall]), cliff = try XCTUnwrap(a.props[.cliffRockA])
        XCTAssertGreaterThan(tree.size.y, max(tree.size.x, tree.size.z))
        XCTAssertGreaterThan(cliff.size.x, cliff.size.z)
    }

    /// metallib は tools/stage/build_shaders.sh で作る。ソースを変えて作り直し忘れると古いシェーダーのまま出荷される。
    func testShaderLibraryIsUpToDate() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/stage/shaders/StageShaders.metal")
        let data = try Data(contentsOf: source)
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let recorded = try String(contentsOf: XCTUnwrap(Bundle.main.url(forResource: "StageShaders", withExtension: "sha256")),
                                  encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(hex, recorded, "tools/stage/build_shaders.sh を実行して metallib を作り直す")
    }

    func testShaderLibraryHasStageFunctions() throws {
        let lib = try XCTUnwrap(StageScene.shaderLibrary(try assets.shaderURL))
        for name in ["stageGroundSurface", "stageRockSurface", "stagePropSurface", "stageVertexColorSurface", "stageWindGeometry"] {
            XCTAssertTrue(lib.functionNames.contains(name), name)
        }
    }

    // MARK: 配合マップ

    private func pixel(_ img: CGImage, _ p: SIMD2<Float>) throws -> SIMD4<Float> {
        let n = img.width
        let s = StageSplat.span / Float(n)
        let col = Int((p.x - StageSplat.origin) / s), row = Int((StageSplat.origin + StageSplat.span - p.y) / s)
        let data = try XCTUnwrap(img.dataProvider?.data) as Data
        let i = (row * n + col) * 4
        return SIMD4(Float(data[i]), Float(data[i + 1]), Float(data[i + 2]), Float(data[i + 3])) / 255
    }

    func testSplatMarksLanesRiverBasesAndJungle() throws {
        let maps = try XCTUnwrap(StageSplat.make(map: .standard, shades: []))
        // 上レーン（x = 7 m）は土
        XCTAssertGreaterThan(try pixel(maps.control, [7, 80]).x, 0.9)
        // 川の中央は水、補助マップの深さも深い
        XCTAssertGreaterThan(try pixel(maps.control, [45, 75]).z, 0.9)
        XCTAssertGreaterThan(try pixel(maps.aux, [45, 75]).z, 0.8)
        // Core の広場は石畳
        XCTAssertGreaterThan(try pixel(maps.control, [15, 15]).y, 0.9)
        // ジャングルの開けた所は草地（土・石畳・川が無い）
        let jungle = try pixel(maps.control, [36, 73])
        XCTAssertLessThan(jungle.x + jungle.y + jungle.z, 0.1)
        // 地図の外は森の下草
        XCTAssertGreaterThan(try pixel(maps.control, [-10, 60]).w, 0.9)
        // 祭壇（ボスの巣）の床では川が途切れる
        XCTAssertLessThan(try pixel(maps.control, [83, 37]).z, 0.05)
    }

    // MARK: 配置

    private func layout(_ q: GraphicsQuality = .medium) throws -> StageLayoutResult {
        let preset = RenderQuality.preset(q)
        return StageLayout.build(map: .standard, props: try assets.props, density: preset.decorationDensity, level: q)
    }

    /// 壁の足跡からのはみ出し（m）。矩形は衝突と同じ L∞（角の立った膨張）、円はユークリッド距離。内側は 0。
    private func wallOverhang(_ p: SIMD2<Float>, near walls: [Int], geo: StageGeometry) -> Float {
        var d = Float.greatestFiniteMagnitude
        for i in walls {
            if i < geo.rects.count {
                let r = geo.rects[i]
                d = min(d, max(max(r.min.x - p.x, p.x - r.max.x), max(r.min.y - p.y, p.y - r.max.y)))
            } else {
                let c = geo.circles[i - geo.rects.count]
                d = min(d, simd_distance(p, c.center) - c.radius)
            }
        }
        return max(0, d)
    }

    /// 硬い物（岩・木・遺跡）は壁の足跡の内側か地図の外にだけ置く（歩ける所にあると、通れるのに通れなく見える）。
    /// 地面近く（高さ 1 m 未満）の頂点が足跡から出てよいのは 0.4 m まで（壁で止まるユニットの半径 0.55 m より小さく）。
    /// あわせて、レーンの中心線から 3 m・泉と Core から 16 m 以内に入らないこと（壁の足跡はそれぞれ 3.5 m・18 m 離れている）。
    func testSolidPropsStayInsideWallsOrOutsideTheMap() throws {
        let props = try assets.props
        let geo = StageGeometry(map: .standard)
        let map = MapDefinition.standard
        let bases = Team.players.flatMap { [geo.m(map.fountain($0)), geo.m(map.core($0))] }
        let wallCount = geo.rects.count + geo.circles.count
        func wallBounds(_ i: Int) -> (SIMD2<Float>, SIMD2<Float>) {
            if i < geo.rects.count { return (geo.rects[i].min, geo.rects[i].max) }
            let c = geo.circles[i - geo.rects.count]
            return (c.center - c.radius, c.center + c.radius)
        }
        for q in GraphicsQuality.allCases {
            let l = try layout(q)
            XCTAssertFalse(l.placements.isEmpty)
            var worst: Float = 0, worstWhat = ""
            for p in l.placements {
                let mesh = try XCTUnwrap(props[p.kind])
                let near = (0..<wallCount).filter { i in
                    let (lo, hi) = wallBounds(i)
                    return rectDistance(p.center, lo, hi) < p.radius + 2
                }
                for v in mesh.positions {
                    let w = p.transform * SIMD4(v, 1)
                    guard w.y < 1.0 else { continue }
                    let m = SIMD2(w.x, -w.z)
                    if geo.outsideDistance(m) > -0.4 { continue } // 地図の外（縁から 0.4 m 以内を含む）
                    let o = near.isEmpty ? .greatestFiniteMagnitude : wallOverhang(m, near: near, geo: geo)
                    if o > worst { (worst, worstWhat) = (o, "\(p.kind.rawValue) at \(p.center)") }
                    XCTAssertGreaterThan(geo.laneDistance(m), 3.0, "\(q) \(p.kind.rawValue) at \(p.center) がレーンに近い")
                    for b in bases where simd_distance(m, b) < 16 {
                        XCTFail("\(q) \(p.kind.rawValue) at \(p.center) が拠点に近い")
                    }
                }
            }
            XCTAssertLessThan(worst, 0.4, "\(q): \(worstWhat) が壁の足跡から \(worst) m はみ出す")
        }
    }

    func testBrushMeshesCoverTheirRects() throws {
        let l = try layout()
        let map = MapDefinition.standard
        XCTAssertEqual(l.brushes.count, map.brushes.count)
        for (i, b) in map.brushes.enumerated() {
            let buf = l.brushes[i]
            XCTAssertFalse(buf.isEmpty)
            let w = Float(b.rect.width / 100), d = Float(b.rect.height / 100)
            // 葉は矩形から大きくはみ出さず（≤ 0.6 m）、矩形をほぼ覆う
            XCTAssertLessThan(buf.boundsMax.x, w / 2 + 0.6)
            XCTAssertGreaterThan(buf.boundsMin.x, -w / 2 - 0.6)
            XCTAssertLessThan(buf.boundsMax.z, d / 2 + 0.6)
            XCTAssertGreaterThan(buf.boundsMin.z, -d / 2 - 0.6)
            XCTAssertGreaterThan(buf.boundsMax.x - buf.boundsMin.x, w * 0.8)
            XCTAssertGreaterThan(buf.boundsMax.y, 0.7)
        }
    }

    /// 端末の負荷: 地図全体の三角形数の上限（画面に入るのはこの 1/5 程度）。
    func testTriangleBudget() throws {
        for q in GraphicsQuality.allCases {
            let l = try layout(q)
            let brush = l.brushes.reduce(0) { $0 + $1.triangleCount }
            XCTAssertLessThan(l.chunks.triangleCount, q == .high ? 1_000_000 : 900_000, "\(q)")
            XCTAssertLessThan(brush, 90_000, "\(q)")
        }
    }

    // MARK: シーン

    func testMapSceneUsesStage() throws {
        let scene = MapScene(map: .standard, materials: RenderMaterials(colorblind: false), quality: .preset(.medium), groundImage: nil)
        let stage = try XCTUnwrap(scene.stage, "ステージの材質が作れず従来の地形に戻った")
        XCTAssertEqual(scene.brushEntities.count, MapDefinition.standard.brushes.count)
        XCTAssertNotNil(stage.root.findEntity(named: "ground"))
        XCTAssertNotNil(stage.root.findEntity(named: "stageRunes"))
        // 草むらは CustomMaterial（風で揺れる）でも半透明にできる
        scene.setTranslucentBrush(0)
        XCTAssertNotNil(scene.brushEntities[0].components[OpacityComponent.self])
    }
}
