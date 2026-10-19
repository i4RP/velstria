import Foundation
import simd
import VelstriaCore

extension StageLayout {
    /// Reference sanctuary: open southeast, raised rear wall, low foreground sill.
    /// All surfaces are baked into the existing material chunks during StagePrep.
    mutating func sanctuary(center c: SIMD2<Float>, lower: Bool) {
        if let source = sanctuaryMesh {
            var mesh = StageMeshBuffer()
            let flip: Float = lower ? -1 : 1
            for i in source.positions.indices {
                let p = source.positions[i], n = source.normals[i]
                _ = mesh.addVertex([c.x + p.x * flip, p.y, -c.y + p.z * flip],
                                   [n.x * flip, n.y, n.z * flip], source.uvs[i], stageColor(0.36, 0.43, 0.43, 0))
            }
            for i in stride(from: 0, to: source.indices.count, by: 3) {
                let a = source.indices[i], b = source.indices[i + 1], d = source.indices[i + 2]
                mesh.addTriangle(a, b, d)
            }
            let key = StageChunks.key(world(c))
            var chunk = out.chunks.sanctuaries[key] ?? StageMeshBuffer()
            chunk.append(mesh)
            out.chunks.sanctuaries[key] = chunk
            return
        }
        let n = BossPitGeometry.segments
        let start = Float(BossPitGeometry.startAngle), sweep = Float(BossPitGeometry.sweep)
        let flip: Float = lower ? -1 : 1
        func p(_ a: Float, _ r: Float) -> SIMD2<Float> { c + SIMD2(cos(a), sin(a)) * (r * flip) }
        func height(_ a: Float) -> Float {
            0.62 + 1.1 * smoothstep(-0.7, 0.8, sin(a))
        }
        // Cross section: broad foot, recessed face, rounded pale coping, inner face.
        let profile: [(Float, Float)] = [(4.10, 0.02), (4.08, 0.22), (3.98, 0.32),
                                         (3.98, 0.80), (3.91, 0.95), (3.79, 1),
                                         (3.54, 1), (3.44, 0.90), (3.42, 0.15)]
        var mesh = StageMeshBuffer()
        for k in 0..<n {
            let a = start + sweep * Float(k) / Float(n)
            let b = start + sweep * Float(k + 1) / Float(n)
            for j in 0..<(profile.count - 1) {
                let (r0, h0) = profile[j], (r1, h1) = profile[j + 1]
                let vertices = [world(p(a, r0), height(a) * h0), world(p(b, r0), height(b) * h0),
                                world(p(b, r1), height(b) * h1), world(p(a, r1), height(a) * h1)]
                var normal = simd_normalize(simd_cross(vertices[1] - vertices[0], vertices[2] - vertices[0]))
                
                let brightness: Float = j >= 4 && j <= 6 ? 1.25 : (j == 1 ? 0.7 : 1)
                let variation: Float = 1 + sin(Float(k * 7)) * 0.035
                let stone = stageColor(0.14 * brightness * variation, 0.22 * brightness * variation,
                                       0.20 * brightness * variation, 0)
                let ids = vertices.map { mesh.addVertex($0, normal, .zero, stone) }
                mesh.addTriangle(ids[0], ids[1], ids[2]); mesh.addTriangle(ids[0], ids[2], ids[3])
            }
            // Thin aged bronze coping, not a complete floor circle.
            let top = (height(a) + height(b)) * 0.5
            stonePrism([p(a, 3.79), p(b, 3.79), p(b, 3.72), p(a, 3.72)],
                       bottom: top, top: top + 0.035, color: stageColor(0.35, 0.29, 0.13, 0))
            if k % 5 == 0 {
                let edge = a + 0.012
                stonePrism([p(a, 4.02), p(edge, 4.02), p(edge, 3.45), p(a, 3.45)],
                           bottom: top - 0.05, top: top + 0.025, color: stageColor(0.16, 0.23, 0.21, 0))
            }
        }
        let key = StageChunks.key(world(c))
        var chunk = out.chunks.flora.removeValue(forKey: key) ?? StageMeshBuffer()
        chunk.append(mesh)
        out.chunks.flora[key] = chunk
        // Broken stone end caps close the otherwise hollow profile at the entrance.
        for a in [start, start + sweep] {
            stonePrism([p(a - 0.025, 4.1), p(a + 0.025, 4.1), p(a + 0.025, 3.42), p(a - 0.025, 3.42)],
                       bottom: 0, top: height(a), color: stageColor(0.30, 0.40, 0.37, 0))
        }
        // Submerged paving leaves the textured riverbed visible between worn arcs.
        for ring in 0..<3 {
            let r: Float = 2.65 + Float(ring) * 0.25
            for k in 0..<48 {
                let a: Float = Float(k) * (2 * Float.pi / 48)
                let b: Float = a + 0.12
                stonePrism([p(a, r), p(b, r), p(b, r - 0.035), p(a, r - 0.035)],
                           bottom: 0.004, top: 0.012, color: stageColor(0.04, 0.16, 0.16, 0))
            }
        }
        // Rear fountain crest and narrow blue water channel.
        let crest: Float = 2.10
        let at = p(crest, 3.75)
        let tangent = SIMD2<Float>(-sin(crest), cos(crest)) * flip
        let radial = SIMD2<Float>(cos(crest), sin(crest)) * flip
        let front = at - radial * Float(0.25)
        let rear = at + radial * Float(0.25)
        let wide = tangent * Float(0.61), narrow = tangent * Float(0.48)
        let crestFoot: [SIMD2<Float>] = [front - wide, front + wide, rear + narrow, rear - narrow]
        stonePrism(crestFoot, bottom: 0.15, top: 1.58, color: stageColor(0.19, 0.30, 0.28, 0))
        var ornament = StageMeshBuffer()
        func crestVertex(_ x: Float, _ y: Float, _ d: Float, _ color: SIMD4<UInt8>) -> UInt32 {
            let q = at + tangent * x - radial * d
            return ornament.addVertex(world(q, y), SIMD3(-radial.x, 0, radial.y), .zero, color)
        }
        // Oval, inset blue crest with a pale bevel; both faces keep the reflected asset visible.
        func face(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
            ornament.addTriangle(a, b, c)
            ornament.addTriangle(c, b, a)
        }
        let rim = stageColor(0.32, 0.39, 0.31, 0)
        let blue = stageColor(0.018, 0.24, 0.31, 0)
        let hub = crestVertex(0, 1.9, 0.35, blue)
        for k in 0..<32 {
            let a = Float(k) * 2 * Float.pi / 32, b = Float(k + 1) * 2 * Float.pi / 32
            let ia = crestVertex(cos(a) * 0.42, 1.9 + sin(a) * 0.55, 0.35, blue)
            let ib = crestVertex(cos(b) * 0.42, 1.9 + sin(b) * 0.55, 0.35, blue)
            let oa = crestVertex(cos(a) * 0.65, 1.9 + sin(a) * 0.78, 0.28, rim)
            let ob = crestVertex(cos(b) * 0.65, 1.9 + sin(b) * 0.78, 0.28, rim)
            face(hub, ia, ib); face(ia, oa, ob); face(ia, ob, ib)
        }
        // Smooth narrow water ribbon, extending from the crest into the shallow basin.
        let wa = crestVertex(-0.19, 1.58, 0.38, blue)
        let wb = crestVertex(0.19, 1.58, 0.38, blue)
        let wc = crestVertex(0.28, 0.04, 0.95, stageColor(0.018, 0.19, 0.23, 0))
        let wd = crestVertex(-0.28, 0.04, 0.95, stageColor(0.018, 0.19, 0.23, 0))
        face(wa, wb, wc); face(wa, wc, wd)
        var decorated = out.chunks.flora.removeValue(forKey: key) ?? StageMeshBuffer()
        decorated.append(ornament)
        out.chunks.flora[key] = decorated
        // Wall-top moss is a low leafy decoration, never a vision/hiding volume.
        for a: Float in [0.50, 2.65, 3.0] {
            sanctuaryMoss(at: p(a, 3.76), height: height(a))
        }
    }

    /// Fixed, low broad leaves. Unlike brushFields, these have no hiding mesh or tall grass cards.
    mutating func sanctuaryMoss(at center: SIMD2<Float>, height: Float) {
        let key = StageChunks.key(world(center))
        var mesh = out.chunks.flora.removeValue(forKey: key) ?? StageMeshBuffer()
        for i in 0..<80 {
            let angle = Float(i) * 2.39996
            let r = sqrt(Float(i) / 80) * 0.65
            let q = center + SIMD2(cos(angle), sin(angle)) * r
            let h = height + 0.08 + 0.23 * (1 - r)
            let along = SIMD2<Float>(cos(angle + 0.7), sin(angle + 0.7)) * 0.10
            let across = SIMD2<Float>(-along.y, along.x) * 0.48
            let shade: Float = 0.8 + Float(i % 5) * 0.065
            let color = stageColor(0.025 * shade, 0.085 * shade, 0.065 * shade, 0)
            let a = mesh.addVertex(world(q - along, h - 0.04), [0, 1, 0], .zero, color)
            let b = mesh.addVertex(world(q + across, h), [0, 1, 0], .zero, color)
            let c = mesh.addVertex(world(q + along, h + 0.035), [0, 1, 0], .zero, color)
            let d = mesh.addVertex(world(q - across, h), [0, 1, 0], .zero, color)
            mesh.addTriangle(a, d, c); mesh.addTriangle(a, c, b)
        }
        out.chunks.flora[key] = mesh
    }
}
