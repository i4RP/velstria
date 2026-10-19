import simd
import VelstriaCore

extension StageLayout {
    /// Reference rocks are low moss-topped masses, with no randomly placed trees.
    func isReferenceWall(_ outline: [SIMD2<Float>]) -> Bool {
        guard map.size == 9_720, !outline.isEmpty else { return false }
        return true
    }

    mutating func referenceWall(_ outline: [SIMD2<Float>], index: Int) {
        if fieldWall(outline, index: index) { return }
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

    /// Fit baked scenery to the measured collision outline, during StagePrep only.
    /// Ground vertices are clamped to the same outline used by navigation.
    mutating func fieldWall(_ outline: [SIMD2<Float>], index: Int) -> Bool {
        let count = StageReferenceLayout.walls.count
        guard index < count * 2,
              let kind = StagePropKind(rawValue: StageReferenceLayout.wallKinds[index % count]),
              let source = fieldProps[kind], admitProp(source) else { return false }
        let halfTurn = index >= count
        let controls = StageReferenceLayout.walls[index % count].map { p -> SIMD2<Float> in
            let q = halfTurn ? Vec2(map.size - p.x, map.size - p.y) : p
            return geo.m(q)
        }
        let center = controls.reduce(SIMD2<Float>.zero, +) / Float(controls.count)
        var xx: Float = 0, yy: Float = 0, xy: Float = 0
        for q in controls { let d = q - center; xx += d.x*d.x; yy += d.y*d.y; xy += d.x*d.y }
        // Camp entrances keep their photographed orientation; long banks follow their axis.
        let angle: Float = (kind == .campCrescent || kind == .campGate)
            ? (halfTurn ? .pi : 0) + (kind == .campCrescent ? .pi / 4 : -.pi / 6)
            : 0.5 * atan2(2*xy, xx-yy) + (halfTurn ? .pi : 0)
        let axis = SIMD2<Float>(cos(angle), sin(angle)), side = SIMD2<Float>(-sin(angle), cos(angle))
        var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for q in controls {
            let d = q-center, v = SIMD2(simd_dot(d, axis), simd_dot(d, side))
            lo = simd_min(lo,v); hi = simd_max(hi,v)
        }
        let span = hi-lo, mid = (lo+hi)/2
        let sx = span.x / source.size.x, sz = span.y / source.size.z
        func constrain(_ q: SIMD2<Float>) -> SIMD2<Float> {
            guard polygonDistance(q, outline) > 0 else { return q }
            var nearest = q, best = Float.greatestFiniteMagnitude
            for j in outline.indices {
                let a = outline[j], b = outline[(j+1)%outline.count], ab = b-a
                let t = min(1,max(0,simd_dot(q-a,ab)/max(0.000001,simd_length_squared(ab))))
                let at = a+ab*t, d = simd_length_squared(at-q)
                if d < best { nearest = at; best = d }
            }
            return nearest
        }
        var mesh = StageMeshBuffer()
        var ground: [SIMD2<Float>] = []
        let heightScale: Float = kind == .campCrescent ? 1.42 : (kind == .rootWall ? 1.25 : 1)
        for i in source.positions.indices {
            let p = source.positions[i], n = source.normals[i]
            let q = constrain(center + axis * (p.x*sx+mid.x) + side * (-p.z*sz+mid.y))
            let normal = simd_normalize(SIMD3<Float>(axis.x*n.x/sx-side.x*n.z/sz,n.y/heightScale,
                                                    -axis.y*n.x/sx+side.y*n.z/sz))
            ground.append(q)
            mesh.addVertex(world(q,p.y * heightScale),normal,source.uvs[i],stageColor(0.43,0.47,0.46,0))
        }
        for i in stride(from: 0, to: source.indices.count, by: 3) {
            // A concave footprint must never gain a triangle across its entrance.
            let a = ground[Int(source.indices[i])], b = ground[Int(source.indices[i+1])], c = ground[Int(source.indices[i+2])]
            let stretched = max(simd_length_squared(a-b), max(simd_length_squared(b-c),simd_length_squared(c-a))) > 0.64
            if stretched {
                guard polygonDistance((a+b+c)/3, outline) < 0.025,
                  polygonDistance((a+b)/2, outline) < 0.025,
                  polygonDistance((b+c)/2, outline) < 0.025,
                  polygonDistance((c+a)/2, outline) < 0.025 else { continue }
            }
            mesh.addTriangle(source.indices[i],source.indices[i+1],source.indices[i+2])
        }
        let key = StageChunks.key(world(center))
        var chunk = out.chunks.fieldProps.removeValue(forKey:key) ?? StageMeshBuffer()
        chunk.append(mesh); out.chunks.fieldProps[key] = chunk
        out.counts[kind, default:0] += 1
        return true
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
