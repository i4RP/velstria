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
    private func assets(_ set: StageArtSet = .ruins) throws -> StageAssets {
        try XCTUnwrap(StageAssets.load(set: set), "App/Resources/Stage の素材（\(set.rawValue)）が読めない")
    }

    /// 新旧どちらのセットも読める（-legacyStage で旧セットに切り替えられる）。
    func testAssetsLoad() throws {
        for set in StageArtSet.allCases {
            let a = try assets(set)
            XCTAssertEqual(a.set, set)
            XCTAssertEqual(Set(a.props.keys), Set(set.propKinds), set.rawValue)
            for t in StageTile.allCases {
                let img = try XCTUnwrap(a.tiles[t])
                XCTAssertEqual(img.width, 1024, "\(set) \(t.rawValue)")
                XCTAssertEqual(img.height, 1024, "\(set) \(t.rawValue)")
            }
            XCTAssertEqual(a.atlas.width, 2048)
            XCTAssertEqual(a.atlas.height, 1024)
            for (kind, m) in a.props {
                XCTAssertFalse(m.indices.isEmpty, kind.rawValue)
                XCTAssertEqual(m.positions.count, m.normals.count)
                XCTAssertEqual(m.positions.count, m.uvs.count)
                // 足跡の中心が原点・底が y = 0
                XCTAssertEqual(m.boundsMin.y, 0, accuracy: 0.01, "\(set) \(kind.rawValue)")
                XCTAssertEqual((m.boundsMin.x + m.boundsMax.x) / 2, 0, accuracy: 0.02, "\(set) \(kind.rawValue)")
                XCTAssertEqual((m.boundsMin.z + m.boundsMax.z) / 2, 0, accuracy: 0.02, "\(set) \(kind.rawValue)")
            }
            // 木は縦長、崖の岩は横長（+X が長辺）
            let tree = try XCTUnwrap(a.props[.treeTall]), cliff = try XCTUnwrap(a.props[.cliffRockA])
            XCTAssertGreaterThan(tree.size.y, max(tree.size.x, tree.size.z), set.rawValue)
            XCTAssertGreaterThan(cliff.size.x, cliff.size.z, set.rawValue)
        }
    }

    /// 新セットの泉の台座は旧い泉の台座と同じ足跡（直径 6.8 m）で、低い床と縁の柱を持つ（柱の頂部にチーム色の結晶を置く）。
    func testFountainDaisKeepsTheOldFootprint() throws {
        let dais = try XCTUnwrap(try assets(.ruins).props[.spawnDais])
        XCTAssertLessThanOrEqual(max(dais.size.x, dais.size.z), 6.8 * 1.02)
        let f = StageLayout.daisFeatures(dais)
        XCTAssertGreaterThanOrEqual(f.sockets.count, 4, "台座の縁の柱が見つからない")
        XCTAssertLessThanOrEqual(f.sockets.count, 8)
        let l = try layout(set: .ruins)
        XCTAssertEqual(l.fountainSockets.count, Team.players.count)
        let geo = StageGeometry(map: .standard)
        for (k, team) in Team.players.enumerated() {
            let c = geo.m(MapDefinition.standard.fountain(team))
            XCTAssertEqual(l.fountainSockets[k].count, f.sockets.count)
            for s in l.fountainSockets[k] {
                XCTAssertLessThan(simd_distance(SIMD2(s.x, -s.z), c), 3.5, "柱が旧い泉の足跡の外にある")
                XCTAssertGreaterThan(s.y, 0.5)
            }
        }
        // 旧セットには台座が無い（MapScene が旧来の泉を作る）
        XCTAssertTrue(try layout(set: .legacy).fountainSockets.isEmpty)
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
        let lib = try XCTUnwrap(StageScene.shaderLibrary(try assets().shaderURL))
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
        for set in StageArtSet.allCases {
            let maps = try XCTUnwrap(StageSplat.make(map: .standard, shades: [], set: set))
            // 上レーン（x = 7 m）は土
            XCTAssertGreaterThan(try pixel(maps.control, [7, 80]).x, 0.9, set.rawValue)
            // 川の中央は水、補助マップの深さも深い
            XCTAssertGreaterThan(try pixel(maps.control, [45, 75]).z, 0.9, set.rawValue)
            XCTAssertGreaterThan(try pixel(maps.aux, [45, 75]).z, 0.8, set.rawValue)
            // Core の広場は石畳
            XCTAssertGreaterThan(try pixel(maps.control, [15, 15]).y, 0.9, set.rawValue)
            // ジャングルの開けた所は草地（土・石畳・川が無い）
            let jungle = try pixel(maps.control, [36, 73])
            XCTAssertLessThan(jungle.x + jungle.y + jungle.z, 0.1, set.rawValue)
            // 地図の外は森の下草
            XCTAssertGreaterThan(try pixel(maps.control, [-10, 60]).w, 0.9, set.rawValue)
            // 祭壇（ボスの巣）の床では川が途切れる
            XCTAssertLessThan(try pixel(maps.control, [83, 37]).z, 0.05, set.rawValue)
        }
    }

    /// 新セットの拠点の石畳は一様に敷き詰めない: 泉・Core の中央はきれいな石畳（風化 0）、旧い広場の範囲の外寄りには
    /// 土・苔が入り込んだ所と風化した石がある（旧セットは広場全体が石畳）。
    func testRuinsBasePlazaBlendsStoneEarthAndMoss() throws {
        let map = MapDefinition.standard
        let geo = StageGeometry(map: map)
        let ruins = try XCTUnwrap(StageSplat.make(map: map, shades: [], set: .ruins))
        let legacy = try XCTUnwrap(StageSplat.make(map: map, shades: [], set: .legacy))
        for team in Team.players {
            let f = geo.m(map.fountain(team)), c = geo.m(map.core(team))
            let toCore = simd_normalize(c - f)
            // 中央（泉の台座のすぐ外・Core の脇・参道の中央）は石畳で風化なし
            for p in [f + SIMD2(4.2, 0), c + SIMD2(0, 5), (f + c) / 2] {
                let ctrl = try pixel(ruins.control, p), aux = try pixel(ruins.aux, p)
                XCTAssertGreaterThan(ctrl.y, 0.95, "\(team) \(p): 中央が石畳でない")
                XCTAssertLessThan(aux.w, 0.1, "\(team) \(p): 中央が風化している")
            }
            // 旧い広場（Core から 9〜12.5 m の環）の上を一周: 石畳が抜けた所と、風化した石畳の両方がある
            var broken = 0, worn = 0, legacyBroken = 0
            let n = 180
            for k in 0..<n {
                let a = Float(k) / Float(n) * 2 * .pi
                for r: Float in [9.5, 11, 12.5] {
                    let p = c + SIMD2(cos(a), sin(a)) * r
                    // 参道の側（泉の方）は除く
                    if simd_dot(simd_normalize(p - c), -toCore) > 0.7 { continue }
                    if try pixel(ruins.control, p).y < 0.5 { broken += 1 }
                    if try pixel(ruins.aux, p).w > 0.4 { worn += 1 }
                    if try pixel(legacy.control, p).y < 0.5 { legacyBroken += 1 }
                }
            }
            XCTAssertGreaterThan(broken, 40, "\(team): 広場の縁に土・苔の入り込みが少ない（\(broken)）")
            XCTAssertGreaterThan(worn, 80, "\(team): 風化した石畳が少ない（\(worn)）")
            XCTAssertLessThan(legacyBroken, 10, "\(team): 旧セットの広場は一様な石畳のはず")
        }
    }

    // MARK: 配置

    private func layout(_ q: GraphicsQuality = .medium, set: StageArtSet = .ruins) throws -> StageLayoutResult {
        let preset = RenderQuality.preset(q)
        return StageLayout.build(map: .standard, props: try assets(set).props, density: preset.decorationDensity, level: q)
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
        try checkSolidProps(.ruins, limit: 0.4)
        // 旧セットは 2026-10-05 の素材をそのまま残した見比べ用。d6aaf94 の時点ですでに cliff_rock_a が (29, 72) で
        // 0.416 m はみ出していた（素材を作り直さない限り直せない）ので、それより悪くならないことだけを確かめる
        try checkSolidProps(.legacy, limit: 0.42)
    }

    private func checkSolidProps(_ set: StageArtSet, limit: Float) throws {
        let props = try assets(set).props
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
            let l = try layout(q, set: set)
            XCTAssertFalse(l.placements.isEmpty)
            // 泉の台座は歩ける所の飾り（硬い物の記録に入れない）
            XCTAssertFalse(l.placements.contains { $0.kind == .spawnDais })
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
                    XCTAssertGreaterThan(geo.laneDistance(m), 3.0, "\(set) \(q) \(p.kind.rawValue) at \(p.center) がレーンに近い")
                    for b in bases where simd_distance(m, b) < 16 {
                        XCTFail("\(set) \(q) \(p.kind.rawValue) at \(p.center) が拠点に近い")
                    }
                }
            }
            XCTAssertLessThan(worst, limit, "\(set) \(q): \(worstWhat) が壁の足跡から \(worst) m はみ出す")
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
        for set in StageArtSet.allCases {
            for q in GraphicsQuality.allCases {
                let l = try layout(q, set: set)
                let brush = l.brushes.reduce(0) { $0 + $1.triangleCount }
                let props = l.chunks.props.values.reduce(0) { $0 + $1.triangleCount }
                XCTAssertLessThanOrEqual(props, BattleWorkBudget.stagePropTriangles(q), "\(set) \(q)")
                XCTAssertLessThan(l.chunks.triangleCount, q == .high ? 1_000_000 : 900_000, "\(set) \(q)")
                XCTAssertLessThan(brush, 90_000, "\(set) \(q)")
            }
        }
    }

    // MARK: シーン

    func testMapSceneUsesStage() throws {
        for set in StageArtSet.allCases {
            let scene = MapScene(map: .standard, materials: RenderMaterials(colorblind: false), quality: .preset(.medium),
                                 groundImage: nil, artSet: set)
            let stage = try XCTUnwrap(scene.stage, "ステージの材質が作れず従来の地形に戻った（\(set.rawValue)）")
            XCTAssertEqual(stage.artSet, set)
            XCTAssertEqual(scene.brushEntities.count, MapDefinition.standard.brushes.count)
            XCTAssertNotNil(stage.root.findEntity(named: "ground"))
            XCTAssertNotNil(stage.root.findEntity(named: "stageRunes"))
            XCTAssertEqual(scene.fountainSpires.count, 2)
            // 新セットは泉に遺跡の台座（柱の受け皿にチーム色の結晶）、旧セットは旧来の泉
            XCTAssertEqual(stage.fountainSockets.isEmpty, set == .legacy)
            // 草むらは CustomMaterial（風で揺れる）でも半透明にできる
            scene.setTranslucentBrush(0)
            XCTAssertNotNil(scene.brushEntities[0].components[OpacityComponent.self])
        }
    }
}
