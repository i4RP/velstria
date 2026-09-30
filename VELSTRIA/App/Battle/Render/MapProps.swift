import Foundation
import simd

// 担当: battle-renderer。地形装飾の形状（木・岩・崖・草・柱・ランタン）。MeshBuilder へ追記する純関数群。
// 高さの目安: 岩・崖 ≤ 2.4 m、木 ≤ 4.6 m（スキル予告を隠さないよう、レーン側には置かない）。

enum TreeKind: CaseIterable {
    case round, pine, teal, autumn
}

enum MapProps {
    /// 広葉樹・針葉樹など。p は根元（地面）。
    static func tree(_ b: inout MeshBuilder, at p: SIMD3<Float>, height h: Float, kind: TreeKind, seed: UInt64) {
        var rng = RenderRNG(seed: seed)
        let yaw = rng.range(0, 2 * .pi)
        let base = MX.t(p) * MX.ry(yaw)
        switch kind {
        case .pine:
            let trunkH = h * 0.28
            b.frustum(bottomRadius: 0.2 * h / 4, topRadius: 0.12 * h / 4, height: trunkH, segments: 6,
                      color: .ramp(.trunk), transform: base)
            let layers = 3
            for k in 0..<layers {
                let t = Float(k) / Float(layers)
                let r = (1.25 - 0.32 * Float(k)) * h / 4
                let y = trunkH * 0.7 + t * h * 0.52
                b.frustum(bottomRadius: r, topRadius: 0, height: h * 0.42, segments: 7,
                          color: .ramp(.pine, from: 0.1 + t * 0.3, to: 0.75 + t * 0.25), capBottom: true,
                          phase: rng.range(0, 1), transform: base * MX.t(0, y, 0))
            }
        case .round, .teal, .autumn:
            let ramp: Ramp = kind == .teal ? .canopyTeal : (kind == .autumn ? .canopyAutumn : .canopy)
            let trunkH = h * 0.42
            b.frustum(bottomRadius: 0.24 * h / 4, topRadius: 0.13 * h / 4, height: trunkH, segments: 6,
                      color: .ramp(.trunk), transform: base)
            // 枝分かれ
            b.frustum(bottomRadius: 0.09 * h / 4, topRadius: 0.05 * h / 4, height: h * 0.22, segments: 5,
                      color: .ramp(.trunk, from: 0.4, to: 1),
                      transform: base * MX.t(0, trunkH * 0.8, 0) * MX.rz(0.6))
            let cr = h * 0.3
            let cy = trunkH + cr * 0.55
            b.blob(radius: cr, jitter: 0.18, seed: seed &+ 1, color: .ramp(ramp, from: 0.15, to: 1),
                   transform: base * MX.t(0, cy, 0) * MX.s(1.05, 0.85, 1.05))
            let n = 2 + Int(rng.nextFloat() * 2)
            for k in 0..<n {
                let a = Float(k) / Float(n) * 2 * .pi + rng.range(0, 1)
                let off = SIMD3<Float>(cos(a) * cr * 0.62, rng.range(-0.25, 0.1) * cr, -sin(a) * cr * 0.62)
                b.blob(radius: cr * rng.range(0.55, 0.72), jitter: 0.2, seed: seed &+ UInt64(k + 2),
                       color: .ramp(ramp, from: 0.05, to: 0.9),
                       transform: base * MX.t(SIMD3(0, cy, 0) + off) * MX.s(1, 0.85, 1))
            }
        }
    }

    /// 岩（p = 地面上の中心）。size = 半径の目安（m）。
    static func rock(_ b: inout MeshBuilder, at p: SIMD3<Float>, size s: Float, flat: Float = 0.62, seed: UInt64,
                     mossy: Bool = false) {
        var rng = RenderRNG(seed: seed)
        let m = MX.t(p + SIMD3(0, s * flat * 0.35, 0)) * MX.ry(rng.range(0, 6.28)) * MX.rx(rng.range(-0.2, 0.2))
            * MX.s(1 + rng.range(-0.15, 0.25), flat, 1 + rng.range(-0.15, 0.2))
        b.blob(radius: s, jitter: 0.22, seed: seed, color: .ramp(mossy ? .mossRock : .rock, from: 0.05, to: 1), transform: m)
    }

    /// 崖の塊（角ばった柱状節理風）。p = 地面中心、h = 高さ。
    static func cliff(_ b: inout MeshBuilder, at p: SIMD3<Float>, radius r: Float, height h: Float, seed: UInt64) {
        var rng = RenderRNG(seed: seed)
        let yaw = rng.range(0, 6.28)
        b.frustum(bottomRadius: r, topRadius: r * rng.range(0.62, 0.8), height: h, segments: 5 + Int(rng.nextFloat() * 3),
                  color: .ramp(.cliff, from: 0, to: 0.9), capTop: false, phase: rng.range(0, 1),
                  transform: MX.t(p) * MX.ry(yaw))
        // 苔むした天面
        b.blob(radius: r * 0.78, jitter: 0.15, seed: seed &+ 7, color: .ramp(.mossRock, from: 0.4, to: 1),
               transform: MX.t(p + SIMD3(0, h, 0)) * MX.ry(yaw) * MX.s(1, 0.28, 1))
    }

    /// 背の高い草の一株（草むら）。
    static func grassClump(_ b: inout MeshBuilder, at p: SIMD3<Float>, height h: Float, seed: UInt64) {
        var rng = RenderRNG(seed: seed)
        let blades = 5 + Int(rng.nextFloat() * 3)
        for _ in 0..<blades {
            let a = rng.range(0, 6.28)
            let off = SIMD3<Float>(cos(a), 0, sin(a)) * rng.range(0, 0.28)
            let bh = h * rng.range(0.65, 1.1)
            let tilt = rng.range(0.05, 0.32)
            b.frustum(bottomRadius: rng.range(0.07, 0.1), topRadius: 0, height: bh, segments: 3,
                      color: .ramp(.grassBlade, from: 0, to: 1), phase: rng.range(0, 1),
                      transform: MX.t(p + off) * MX.ry(a) * MX.rz(tilt))
        }
    }

    /// 花・キノコなどの小物（高さ 0.3 m 未満）。
    static func smallFlora(_ b: inout MeshBuilder, glow: inout MeshBuilder, at p: SIMD3<Float>, seed: UInt64) {
        var rng = RenderRNG(seed: seed)
        let k = rng.nextFloat()
        if k < 0.4 {
            // キノコ
            let n = 1 + Int(rng.nextFloat() * 3)
            for i in 0..<n {
                let off = SIMD3<Float>(rng.range(-0.25, 0.25), 0, rng.range(-0.25, 0.25))
                let s = rng.range(0.6, 1.1)
                b.cylinder(radius: 0.04 * s, height: 0.14 * s, segments: 5, color: .solid(.mushroom),
                           transform: MX.t(p + off))
                b.sphere(radius: 0.1 * s, segments: 7, rings: 4, color: .solid(i == 0 ? .mushroomCap : .flowerPink),
                         transform: MX.t(p + off + SIMD3(0, 0.14 * s, 0)) * MX.s(1, 0.55, 1))
            }
        } else if k < 0.75 {
            // 小さな光る結晶（夜光の星屑）
            let n = 2 + Int(rng.nextFloat() * 3)
            for _ in 0..<n {
                let off = SIMD3<Float>(rng.range(-0.3, 0.3), 0, rng.range(-0.3, 0.3))
                glow.crystal(radius: rng.range(0.05, 0.09), height: rng.range(0.2, 0.4), color: .ramp(.crystalBlue, from: 0.5, to: 1),
                             transform: MX.t(p + off) * MX.ry(rng.range(0, 6)) * MX.rz(rng.range(-0.4, 0.4)))
            }
        } else {
            // 小石
            for i in 0..<3 {
                let off = SIMD3<Float>(rng.range(-0.35, 0.35), 0, rng.range(-0.35, 0.35))
                rock(&b, at: p + off, size: rng.range(0.1, 0.22), flat: 0.5, seed: seed &+ UInt64(i))
            }
        }
    }

    /// 石柱（台座 + 柱 + 冠石）。p = 地面。
    static func pillar(_ b: inout MeshBuilder, glow: inout MeshBuilder, at p: SIMD3<Float>, height h: Float,
                       rune: Swatch, broken: Bool = false, seed: UInt64) {
        var rng = RenderRNG(seed: seed)
        let yaw = rng.range(0, 6.28)
        let m = MX.t(p) * MX.ry(yaw)
        b.box(size: [0.7, 0.2, 0.7], color: .solid(.stoneDark), transform: m)
        let ph = broken ? h * rng.range(0.4, 0.65) : h
        b.frustum(bottomRadius: 0.24, topRadius: 0.2, height: ph, segments: 6, color: .ramp(.stonePillar),
                  capTop: true, transform: m * MX.t(0, 0.2, 0))
        if !broken {
            b.box(size: [0.56, 0.16, 0.56], color: .solid(.stone), transform: m * MX.t(0, 0.2 + ph, 0))
            glow.crystal(radius: 0.12, height: 0.36, color: .solid(rune), transform: m * MX.t(0, 0.42 + ph, 0))
        } else {
            rock(&b, at: p + SIMD3(0.6, 0, 0.2), size: 0.22, seed: seed &+ 3)
        }
        glow.box(size: [0.08, ph * 0.5, 0.02], color: .solid(rune), transform: m * MX.t(0, 0.2 + ph * 0.25, 0.235))
    }

    /// 吊りランタン（支柱 + 灯）。p = 地面。
    static func lanternPost(_ b: inout MeshBuilder, glow: inout MeshBuilder, at p: SIMD3<Float>, height h: Float,
                            yaw: Float) {
        let m = MX.t(p) * MX.ry(yaw)
        b.cylinder(radius: 0.06, height: h, segments: 5, color: .solid(.woodDark), transform: m)
        b.box(size: [0.5, 0.06, 0.06], color: .solid(.woodDark), transform: m * MX.t(0.2, h - 0.08, 0))
        b.box(size: [0.2, 0.05, 0.2], color: .solid(.metalDark), transform: m * MX.t(0.4, h - 0.3, 0))
        glow.box(size: [0.16, 0.22, 0.16], color: .solid(.lanternWarm), transform: m * MX.t(0.4, h - 0.52, 0))
        b.box(size: [0.2, 0.04, 0.2], color: .solid(.metalDark), transform: m * MX.t(0.4, h - 0.56, 0))
    }
}
