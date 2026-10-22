import CoreGraphics
import Foundation
import VelstriaCore

/// Prepared on StagePrep's background task. Only the selected map's chunks/textures are loaded.
struct CanyonStagePlan: @unchecked Sendable {
    struct Chunk: Sendable { let atlas: Int; let mesh: StageMeshBuffer; var structurePoint: Vec2? = nil }
    let chunks: [Chunk]
    let atlases: [CGImage]
    let brushes: [Chunk]
    let structures: [Chunk]
    let foliage: StageLayoutResult
    let foliageAtlas: CGImage
    let quality: GraphicsQuality
    let shaderURL: URL

    private struct Header: Decodable {
        struct Chunk: Decodable {
            let atlas: Int
            let brushIndex: Int?
            let structurePoint: [Double]?
            let vertexCount: Int
            let indexCount: Int
            let vertexOffset: Int
            let indexOffset: Int
        }
        let atlasCount: Int
        let chunks: [Chunk]
    }

    static func load(map: MapDefinition, quality: RenderQuality, bundle: Bundle = .main) -> CanyonStagePlan? {
        guard let url = bundle.url(forResource: "StageCanyon", withExtension: "bin"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let parsed = parse(data, triangleBudget: BattleWorkBudget.stagePropTriangles(quality.level)),
              parsed.brushes.count == map.brushes.count,
              parsed.structures.count == map.towers.count,
              map.towers.allSatisfy({ tower in
                  parsed.structures.filter {
                      $0.structurePoint!.distance(to: tower.pos) < 0.01 &&
                      $0.mesh.triangleCount <= (tower.isCore ? 8500 : 6000)
                  }.count == 1
              }),
              let foliageAtlas = StageAssets.image(bundle, "StageBrushAtlas", "png"),
              foliageAtlas.width <= 1024, foliageAtlas.height <= 512,
              let shader = bundle.url(forResource: StageAssets.shaderResourceName, withExtension: "metallib") else { return nil }
        var atlases: [CGImage] = []
        for i in 0..<parsed.atlasCount {
            guard let image = StageAssets.image(bundle, "StageCanyonAtlas\(i)", "png"),
                  image.width <= 2048, image.height <= 1024 else { return nil }
            atlases.append(image)
        }
        var foliage = StageLayout(map: map, props: [:], density: 1, level: quality.level)
        foliage.brushFields()
        let foliageTriangles = foliage.out.brushes.reduce(0) { $0 + $1.triangleCount }
        let solidTriangles = (parsed.chunks + parsed.structures).reduce(0) { $0 + $1.mesh.triangleCount }
        guard foliageTriangles <= 90_000,
              solidTriangles + foliageTriangles <= BattleWorkBudget.stagePropTriangles(quality.level) else { return nil }
        return CanyonStagePlan(chunks: parsed.chunks, atlases: atlases,
                               brushes: parsed.brushes, structures: parsed.structures, foliage: foliage.out, foliageAtlas: foliageAtlas, quality: quality.level, shaderURL: shader)
    }

    static func parse(_ data: Data, triangleBudget: Int) -> (chunks: [Chunk], brushes: [Chunk], structures: [Chunk], atlasCount: Int)? {
        guard data.count >= 12, data.prefix(4) == Data("VCM1".utf8) else { return nil }
        func u32(_ offset: Int) -> Int {
            data.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian) }
        }
        guard u32(4) == 1 else { return nil }
        let length = u32(8)
        guard length <= data.count - 12,
              let header = try? JSONDecoder().decode(Header.self, from: data.subdata(in: 12..<(12 + length))),
              (1...3).contains(header.atlasCount), !header.chunks.isEmpty, header.chunks.count <= 512 else { return nil }
        let start = (12 + length + 15) / 16 * 16
        guard start <= data.count else { return nil }
        var chunks: [Chunk] = []
        var structures: [Chunk] = []
        var brushes: [Int: Chunk] = [:]
        var remaining = triangleBudget
        for chunk in header.chunks {
            guard (0..<header.atlasCount).contains(chunk.atlas), chunk.vertexCount > 0,
                  chunk.indexCount > 0, chunk.indexCount % 3 == 0,
                  chunk.indexCount / 3 <= remaining, chunk.vertexOffset >= 0, chunk.indexOffset >= 0,
                  chunk.vertexOffset <= data.count - start, chunk.indexOffset <= data.count - start,
                  chunk.vertexCount <= (data.count - start - chunk.vertexOffset) / 32,
                  chunk.indexCount <= (data.count - start - chunk.indexOffset) / 4 else { return nil }
            remaining -= chunk.indexCount / 3
            var mesh = StageMeshBuffer(reserveVertices: chunk.vertexCount)
            let valid: Bool = data.withUnsafeBytes { raw in
                for i in 0..<chunk.vertexCount {
                    let offset = start + chunk.vertexOffset + i * 32
                    func f(_ k: Int) -> Float { Float(bitPattern: raw.loadUnaligned(fromByteOffset: offset + k * 4, as: UInt32.self).littleEndian) }
                    let values = (0..<8).map(f)
                    guard values.allSatisfy(\.isFinite), abs(f(0)) < 500, abs(f(1)) < 500, abs(f(2)) < 500,
                          (0...1).contains(f(6)), (0...1).contains(f(7)) else { return false }
                    mesh.addVertex(SIMD3(f(0), f(1), f(2)), SIMD3(f(3), f(4), f(5)), SIMD2(f(6), f(7)))
                }
                for i in stride(from: 0, to: chunk.indexCount, by: 3) {
                    let offset = start + chunk.indexOffset + i * 4
                    let a = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
                    let b = raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self).littleEndian
                    let c = raw.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self).littleEndian
                    guard max(a, b, c) < UInt32(chunk.vertexCount) else { return false }
                    mesh.addTriangle(a, b, c)
                }
                return true
            }
            guard valid else { return nil }
            let prepared = Chunk(atlas: chunk.atlas, mesh: mesh)
            if let point = chunk.structurePoint {
                guard point.count == 2, point.allSatisfy({ $0.isFinite && (0...9720).contains($0) }),
                      chunk.brushIndex == nil, structures.count < 20, chunk.indexCount / 3 <= 8500 else { return nil }
                structures.append(Chunk(atlas: chunk.atlas, mesh: mesh, structurePoint: Vec2(point[0], point[1])))
            } else if let index = chunk.brushIndex {
                guard (0..<255).contains(index), brushes[index] == nil else { return nil }
                brushes[index] = prepared
            } else {
                chunks.append(prepared)
            }
        }
        guard brushes.keys.sorted() == Array(0..<brushes.count) else { return nil }
        return (chunks, (0..<brushes.count).compactMap { brushes[$0] }, structures, header.atlasCount)
    }
}
