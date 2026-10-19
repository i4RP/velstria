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
        let camp = kind == .campCrescent || kind == .campGate
        let pivot = (controls.reduce(SIMD2<Float>(repeating: .greatestFiniteMagnitude), simd_min)
                   + controls.reduce(SIMD2<Float>(repeating: -.greatestFiniteMagnitude), simd_max)) / 2
        func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x*b.y-a.y*b.x }
        func arc(_ angles: [Float]) -> (Float, Float) {
            let a = angles.map { $0 < 0 ? $0 + 2 * .pi : $0 }.sorted()
            var start = a[0], length: Float = 2 * .pi, gap: Float = -1
            for i in a.indices {
                let next = i+1 < a.count ? a[i+1] : a[0]+2 * .pi
                if next-a[i] > gap { gap=next-a[i];start=next;length=2 * .pi-gap }
            }
            return (start,length)
        }
        let sourceArc = arc(source.positions.filter { $0.y < source.size.y * 0.65 }.map { atan2(-$0.z,$0.x) })
        let targetArc = arc(controls.map { atan2($0.y-pivot.y,$0.x-pivot.x) })
        func progress(_ angle: Float, _ range: (Float, Float)) -> Float {
            var a = angle
            while a < range.0 { a += 2 * .pi }
            while a >= range.0 + 2 * .pi { a -= 2 * .pi }
            if a > range.0 + range.1 && a-range.0 > (range.1+2 * .pi)/2 { a -= 2 * .pi }
            return min(0.995,max(0.005,(a-range.0)/max(0.01,range.1)))
        }
        var radii = [(Float,Float)](repeating:(.greatestFiniteMagnitude,0),count:64)
        if camp {
            for p in source.positions {
                let bin = min(63,Int(progress(atan2(-p.z,p.x),sourceArc)*64))
                let r = hypot(p.x,p.z)
                radii[bin].0=min(radii[bin].0,r);radii[bin].1=max(radii[bin].1,r)
            }
        }
        let oriented = outline.map { q -> SIMD2<Float> in
            let d=q-center;return SIMD2(simd_dot(d,axis),simd_dot(d,side))
        }
        func fitted(_ p: SIMD3<Float>) -> (SIMD2<Float>,Float) {
            if camp {
                let sa=atan2(-p.z,p.x),u=progress(sa,sourceArc)
                let ta=targetArc.0+targetArc.1*u,dir=SIMD2<Float>(cos(ta),sin(ta))
                var hits: [Float] = []
                for j in outline.indices {
                    let a=outline[j]-pivot,ab=outline[(j+1)%outline.count]-outline[j]
                    let den=cross(dir,ab)
                    if abs(den)<0.000001 { continue }
                    let r=cross(a,ab)/den,t=cross(a,dir)/den
                    if r>=0 && t>=0 && t<=1 { hits.append(r) }
                }
                if let far=hits.max() {
                    let near=hits.count>1 ? hits.min()! : 0
                    let bin=min(63,Int(u*64));var rlo=Float.greatestFiniteMagnitude,rhi:Float=0
                    for k in max(0,bin-2)...min(63,bin+2) { rlo=min(rlo,radii[k].0);rhi=max(rhi,radii[k].1) }
                    let v=min(1,max(0,(hypot(p.x,p.z)-rlo)/max(0.05,rhi-rlo)))
                    return (pivot+dir*(near+(far-near)*v),ta-sa)
                }
            } else {
                // Follow the measured bank curve without collapsing a straight model onto its edges.
                let x=min(hi.x-0.002,max(lo.x+0.002,p.x*sx+mid.x))
                var cuts: [Float] = []
                for j in oriented.indices {
                    let a=oriented[j],b=oriented[(j+1)%oriented.count]
                    guard (a.x<=x && b.x>x) || (b.x<=x && a.x>x) else { continue }
                    cuts.append(a.y+(b.y-a.y)*(x-a.x)/(b.x-a.x))
                }
                if let lower=cuts.min(),let upper=cuts.max() {
                    let v=min(1,max(0,0.5-p.z/source.size.z))
                    return (center+axis*x+side*(lower+(upper-lower)*v),angle)
                }
            }
            return (center+axis*(p.x*sx+mid.x)+side*(-p.z*sz+mid.y),angle)
        }
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
        let heightScale: Float = kind == .campCrescent ? 1.6 : (kind == .rootWall ? 1.6 : (kind == .riverWall ? 1.25 : 1.1))
        for i in source.positions.indices {
            let p = source.positions[i], n = source.normals[i]
            let (fit,yaw) = fitted(p), q = constrain(fit)
            let ax=SIMD2<Float>(cos(yaw),sin(yaw)),sy=SIMD2<Float>(-sin(yaw),cos(yaw))
            let normal = simd_normalize(SIMD3<Float>(ax.x*n.x/sx-sy.x*n.z/sz,n.y/heightScale,
                                                    -ax.y*n.x/sx+sy.y*n.z/sz))
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
