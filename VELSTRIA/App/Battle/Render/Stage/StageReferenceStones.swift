import simd
import VelstriaCore

extension StageLayout {
    /// Reference rocks are low moss-topped masses, with no randomly placed trees.
    func isReferenceWall(_ outline: [SIMD2<Float>]) -> Bool {
        guard map.size == 9_720, !outline.isEmpty else { return false }
        let c = outline.reduce(SIMD2<Float>.zero, +) / Float(outline.count)
        return !map.camps.contains { $0.kind.isBoss && simd_distance(c, geo.m($0.pos)) < 9 }
    }

    mutating func referenceWall(_ outline: [SIMD2<Float>], index: Int) {
        let slab = StageLayout.slopedSlab(outline: outline, seed: UInt64(index) &* 1733,
                                         tint: rockTint(), fine: level != .low,
                                         refine: level == .high && ruinsLook)
        var mesh = StageMeshBuffer()
        for i in slab.mesh.positions.indices {
            let p = slab.mesh.positions[i], n = slab.mesh.normals[i]
            mesh.addVertex(SIMD3(p.x, p.y * 0.62, p.z),
                           simd_normalize(SIMD3(n.x, n.y / 0.62, n.z)),
                           slab.mesh.uvs[i], slab.mesh.colors[i])
        }
        for i in stride(from: 0, to: slab.mesh.indices.count, by: 3) {
            mesh.addTriangle(slab.mesh.indices[i], slab.mesh.indices[i + 1], slab.mesh.indices[i + 2])
        }
        appendRock(mesh, at: outline.reduce(SIMD2<Float>.zero, +) / Float(outline.count))
    }

    /// The pink-marked rock is a low walkable ground detail, never a bush/collider.
    mutating func referenceLowStones() {
        guard map.size == MapDefinition.relayout.size else { return }
        for outline in StageReferenceLayout.lowStones {
            for mirrored in [false, true] {
                let points = outline.map { p in
                    geo.m(mirrored ? Vec2(map.size - p.x, map.size - p.y) : p)
                }
                let center = points.reduce(SIMD2<Float>.zero, +) / Float(points.count)
                appendRock(StageLayout.slabCore(outline: points, height: 0.23, seed: 517,
                                                tint: rockTint()), at: center)
            }
        }
    }
}
