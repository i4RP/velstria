import Foundation
import RealityKit
import simd

// 担当: hero-models。武器・副手・背中・浮遊物のメッシュ。
// 武器座標: 握りが原点、+Y へ伸びる。刃の平面は ±X を向き（刃筋は ±Z）、銃は +Z が上面。

@MainActor
struct HeroGearBuilder {
    let bp: HeroBlueprint
    let m: BodyMetrics
    private(set) var weaponTip = V3(0, 0.1, 0)
    private(set) var flagAnchor = V3.zero
    private(set) var floatMotion = FloatMotion.none
    private(set) var floatAnchor = V3.zero

    init(bp: HeroBlueprint, m: BodyMetrics) {
        self.bp = bp
        self.m = m
    }

    // MARK: 右手

    mutating func weapon() -> HeroMeshBuilder {
        var b = HeroMeshBuilder()
        switch bp.weapon {
        case .none:
            weaponTip = V3(0, 0.02, 0)
        case .broadsword:
            grip(&b, 0.1)
            b.rbox(V3(0, 0.12, 0), V3(0.075, 0.07, 0.36), 0.025, .metal)
            b.sphere(V3(0, 0.12, -0.0), 0.042, .glow, .low)
            let blade: [V2] = [V2(-0.075, 0), V2(0.075, 0), V2(0.08, 0.64), V2(0, 0.84), V2(-0.08, 0.64)]
            b.blade(blade, depth: 0.042, V3(0, 0.15, 0), .metal)
            b.rbox(V3(0, 0.5, 0), V3(0.05, 0.52, 0.036), 0.012, .glow)
            weaponTip = V3(0, 0.98, 0)
        case .starRapier:
            grip(&b, 0.08)
            b.dome(V3(0, 0.1, 0), V3(0.1, 0.065, 0.1), .metal)
            b.frustum(V3(0, 0.13, 0), V3(0, 0.95, 0), 0.026, 0.006, .metal, segments: 8)
            b.frustum(V3(0, 0.14, 0), V3(0, 0.7, 0), 0.03, 0.012, .glow, segments: 6)
            b.extrude(starPolygon(points: 5, outer: 0.06, inner: 0.026), depth: 0.025, V3(0, -0.12, 0), .glow, rot: ry(.pi / 2))
            b.torus(V3(0, 0.05, -0.04), 0.07, 0.01, .metal, rot: rz(.pi / 2), arc: .pi)
            weaponTip = V3(0, 0.95, 0)
        case .tideStaff:
            b.rod(V3(0, -0.44, 0), V3(0, 0.86, 0), 0.027, .cloth)
            b.cone(V3(0, -0.44, 0), V3(0, -0.56, 0), 0.032, .metal)
            for y: Float in [-0.05, 0.32, 0.8] { b.torus(V3(0, y, 0), 0.034, 0.012, .metal) }
            b.extrude(crescentPolygon(radius: 0.19, thickness: 0.055, span: 3.6, offset: 0.04), depth: 0.05,
                      V3(0, 1.02, 0), .cloth, rot: rz(-.pi / 2))
            for s: Float in [-1, 1] {
                b.ellipsoid(V3(s * 0.19, 1.1, 0), V3(0.035, 0.06, 0.03), .accent, rot: rz(-s * 0.5), detail: .low)
            }
            b.sphere(V3(0, 1.03, 0), 0.12, .glow)
            for s: Float in [-1, 1] {
                b.ellipsoid(V3(0, 0.9, s * 0.09), V3(0.02, 0.08, 0.05), .accent, rot: rx(s * 0.5), detail: .low)
            }
            weaponTip = V3(0, 1.03, 0)
        case .lightningSpear:
            b.rod(V3(0, -0.4, 0), V3(0, 0.95, 0), 0.027, .metal)
            b.cone(V3(0, -0.4, 0), V3(0, -0.5, 0), 0.034, .metal)
            for y: Float in [-0.3, 0.3, 0.6] { b.torus(V3(0, y, 0), 0.034, 0.011, .glow) }
            let bolt: [V2] = [V2(-0.07, 0), V2(0.08, 0), V2(0.025, 0.15), V2(0.12, 0.15), V2(-0.025, 0.55), V2(0.0, 0.25), V2(-0.1, 0.25)]
            b.blade(bolt, depth: 0.04, V3(0, 0.95, 0), .metal)
            b.blade(bolt.map { V2($0.x * 0.7, $0.y * 0.86 + 0.03) }, depth: 0.052, V3(0, 0.95, 0), .glow)
            b.rbox(V3(0, 0.93, 0), V3(0.05, 0.05, 0.26), 0.02, .metal)
            for s: Float in [-1, 1] { b.sphere(V3(0, 0.93, s * 0.14), 0.035, .glow, .low) }
            b.torus(V3(0, 0.1, 0), 0.034, 0.012, .glow)
            weaponTip = V3(0, 1.4, 0)
        case .crescentDagger:
            dagger(&b, crescentBlade(), bladeMat: .metal, glowEdge: true)
            weaponTip = V3(0, 0.42, -0.1)
        case .stoneFist:
            stoneFist(&b, side: 1)
            weaponTip = V3(0, -0.15, 0)
        case .windBanner:
            b.rod(V3(0, -0.45, 0), V3(0, 1.22, 0), 0.023, .metal)
            b.cone(V3(0, -0.45, 0), V3(0, -0.55, 0), 0.03, .metal)
            let leaf: [V2] = [V2(-0.05, 0), V2(0.05, 0), V2(0.065, 0.1), V2(0, 0.32), V2(-0.065, 0.1)]
            b.blade(leaf, depth: 0.032, V3(0, 1.2, 0), .metal)
            b.rbox(V3(0, 1.33, 0), V3(0.036, 0.16, 0.02), 0.008, .glow)
            b.torus(V3(0, 1.2, 0), 0.035, 0.014, .accent)
            b.torus(V3(0, 0.8, 0), 0.032, 0.012, .accent)
            flagAnchor = V3(0, 1.14, 0)
            weaponTip = V3(0, 1.5, 0)
        case .mechCrossbow:
            b.rbox(V3(0, 0.06, 0), V3(0.08, 0.52, 0.1), 0.03, .secondary)
            b.rbox(V3(0, -0.24, 0.01), V3(0.07, 0.14, 0.15), 0.03, .dark)
            b.rbox(V3(0, 0.14, 0.06), V3(0.04, 0.46, 0.03), 0.01, .metal)
            b.extrude(crescentPolygon(radius: 0.3, thickness: 0.05, span: 2.4, offset: 0.06), depth: 0.04,
                      V3(0, 0.1, 0.04), .metal, rot: rz(.pi / 2))
            let tipA = V3(-0.27, 0.23, 0.04), tipB = V3(0.27, 0.23, 0.04)
            b.rod(tipA, tipB, 0.006, .glow)
            b.rod(V3(0.045, 0.0, 0), V3(0.075, 0.0, 0), 0.075, .metal, segments: 12)
            b.rod(V3(0.07, 0.0, 0), V3(0.085, 0.0, 0), 0.035, .glow, segments: 10)
            for i in 0..<8 {
                let a = Float(i) / 8 * 2 * .pi
                b.box(V3(0.06, sin(a) * 0.085, cos(a) * 0.085), V3(0.03, 0.03, 0.03), .metal, rot: rx(a))
            }
            b.rod(V3(0, 0.1, 0.08), V3(0, 0.44, 0.08), 0.012, .dark)
            b.cone(V3(0, 0.44, 0.08), V3(0, 0.52, 0.08), 0.025, .glow)
            b.rbox(V3(0, 0.0, 0.11), V3(0.07, 0.16, 0.08), 0.02, .metal)
            weaponTip = V3(0, 0.52, 0.08)
        case .handFlame:
            b.sphere(V3(0, 0.1, 0), 0.07, .glow)
            b.cone(V3(0, 0.07, 0), V3(0, 0.3, 0), 0.075, .glow, segments: 8)
            for i in 0..<3 {
                let a = Float(i) / 3 * 2 * .pi
                let p = V3(cos(a) * 0.05, 0.07, sin(a) * 0.05)
                b.cone(p, p + V3(cos(a) * 0.04, 0.16, sin(a) * 0.04), 0.04, .accent, segments: 6)
            }
            weaponTip = V3(0, 0.14, 0)
        case .aegisStaff:
            b.rod(V3(0, -0.46, 0), V3(0, 0.96, 0), 0.026, .metal)
            b.cone(V3(0, -0.46, 0), V3(0, -0.56, 0), 0.03, .metal)
            b.sphere(V3(0, 1.08, 0), 0.075, .glow)
            b.cone(V3(0, 1.17, 0), V3(0, 1.3, 0), 0.08, .metal, segments: 8)
            b.rod(V3(0, 0.96, 0), V3(0, 0.99, 0), 0.08, .metal, segments: 10)
            for i in 0..<4 {
                let a = Float(i) / 4 * 2 * .pi + .pi / 4
                b.rod(V3(cos(a) * 0.075, 0.99, sin(a) * 0.075), V3(cos(a) * 0.075, 1.17, sin(a) * 0.075), 0.01, .metal)
            }
            for s: Float in [-1, 1] {
                for i in 0..<3 {
                    let p = V3(0, 1.0 + Float(i) * 0.035, s * 0.09)
                    b.ellipsoid(p + V3(0, 0.07, s * 0.08), V3(0.018, 0.13 - Float(i) * 0.025, 0.045), .accent,
                                rot: rx(-s * (0.6 + Float(i) * 0.3)), detail: .low)
                }
            }
            weaponTip = V3(0, 1.08, 0)
        case .glassDagger:
            glassDagger(&b)
            weaponTip = V3(0, 0.48, 0)
        case .boneClub:
            b.frustum(V3(0, -0.13, 0), V3(0, 0.48, 0), 0.03, 0.05, .metal)
            b.frustum(V3(0, -0.11, 0), V3(0, 0.12, 0), 0.038, 0.038, .dark)
            b.sphere(V3(0, -0.14, 0), 0.045, .metal, .low)
            b.ellipsoid(V3(0, 0.64, 0), V3(0.13, 0.21, 0.13), .metal)
            b.torus(V3(0, 0.5, 0), 0.07, 0.018, .glow)
            for i in 0..<6 {
                let a = Float(i) / 6 * 2 * .pi
                let yy: Float = 0.6 + (i % 2 == 0 ? 0.08 : -0.02)
                let p = V3(sin(a) * 0.11, yy, cos(a) * 0.11)
                b.cone(p, p + V3(sin(a) * 0.11, 0.03, cos(a) * 0.11), 0.03, .cloth, segments: 6)
            }
            b.cone(V3(0, 0.82, 0), V3(0, 0.94, 0), 0.04, .cloth, segments: 6)
            weaponTip = V3(0, 0.86, 0)
        case .mistKatana:
            katana(&b, scale: 1)
            weaponTip = V3(0, 0.96, 0)
        case .bellBlunderbuss:
            b.rbox(V3(0, -0.19, 0.0), V3(0.08, 0.3, 0.13), 0.03, .secondary, rot: rx(0.2))
            b.rbox(V3(0, 0.03, 0), V3(0.095, 0.2, 0.12), 0.03, .metal)
            b.rod(V3(0, 0.08, 0), V3(0, 0.5, 0), 0.042, .metal, segments: 12)
            let bell: [V2] = [V2(0.042, 0), V2(0.05, 0.05), V2(0.08, 0.1), V2(0.14, 0.16), V2(0.155, 0.175), V2(0.155, 0.175),
                              V2(0.13, 0.18)]
            b.lathe(bell, V3(0, 0.5, 0), .metal, segments: 18)
            b.torus(V3(0, 0.66, 0), 0.115, 0.016, .glow)
            for y: Float in [0.2, 0.38] { b.torus(V3(0, y, 0), 0.047, 0.014, .accent) }
            b.rbox(V3(0, 0.06, 0.075), V3(0.03, 0.08, 0.04), 0.01, .dark)
            weaponTip = V3(0, 0.7, 0)
        case .haloStaff:
            b.rod(V3(0, -0.46, 0), V3(0, 0.86, 0), 0.025, .metal)
            b.cone(V3(0, -0.46, 0), V3(0, -0.56, 0), 0.03, .metal)
            b.torus(V3(0, 1.04, 0), 0.18, 0.024, .metal, rot: rx(.pi / 2), segments: 26)
            b.torus(V3(0, 1.04, 0), 0.14, 0.01, .glow, rot: rx(.pi / 2), segments: 24)
            b.crystal(V3(0, 1.04, 0), radius: 0.055, height: 0.11, .glow, bottom: 1)
            for i in 0..<4 {
                let a = Float(i) / 4 * 2 * .pi
                b.sphere(V3(cos(a) * 0.2, 1.04 + sin(a) * 0.2, 0), 0.028, .glow, .low)
            }
            b.cone(V3(0, 1.22, 0), V3(0, 1.36, 0), 0.03, .metal, segments: 8)
            b.torus(V3(0, 0.86, 0), 0.04, 0.014, .accent)
            weaponTip = V3(0, 1.04, 0)
        case .abyssCenser:
            b.torus(V3(0, 0, 0), 0.045, 0.013, .metal, rot: rz(.pi / 2))
            for i in 0..<5 {
                let y = -0.05 - Float(i) * 0.05
                b.torus(V3(0, y, 0), 0.026, 0.008, .metal, rot: i % 2 == 0 ? rz(.pi / 2) : rx(.pi / 2), segments: 10, sides: 5)
            }
            let body: [V2] = [V2(0, -0.11), V2(0.08, -0.09), V2(0.12, 0.0), V2(0.11, 0.06), V2(0.07, 0.1), V2(0.025, 0.15), V2(0, 0.16)]
            b.lathe(body, V3(0, -0.4, 0), .metal, segments: 14)
            b.torus(V3(0, -0.4, 0), 0.118, 0.022, .glow, segments: 18)
            for i in 0..<4 {
                let a = Float(i) / 4 * 2 * .pi
                b.cone(V3(cos(a) * 0.1, -0.38, sin(a) * 0.1), V3(cos(a) * 0.18, -0.36, sin(a) * 0.18), 0.025, .dark, segments: 6)
            }
            b.sphere(V3(0, -0.52, 0), 0.04, .glow, .low)
            weaponTip = V3(0, -0.4, 0)
        case .petalBlade:
            dagger(&b, petalShape(), bladeMat: .accent, glowEdge: false)
            b.rbox(V3(0, 0.3, 0), V3(0.036, 0.24, 0.012), 0.005, .glow)
            weaponTip = V3(0, 0.46, 0)
        case .siegeHammer:
            b.rod(V3(0, -0.3, 0), V3(0, 1.0, 0), 0.036, .dark, segments: 10)
            b.sphere(V3(0, -0.33, 0), 0.055, .metal, .low)
            for y: Float in [-0.2, 0.0, 0.2] { b.torus(V3(0, y, 0), 0.042, 0.012, .accent) }
            b.rbox(V3(0, 1.08, 0), V3(0.3, 0.32, 0.56), 0.05, .metal)
            b.rod(V3(0, 1.08, -0.27), V3(0, 1.08, -0.36), 0.16, .metal, segments: 14)
            b.rod(V3(0, 1.08, 0.27), V3(0, 1.08, 0.34), 0.14, .metal, segments: 14)
            b.rbox(V3(0, 1.08, 0), V3(0.32, 0.13, 0.2), 0.02, .primary)
            for s: Float in [-1, 1] {
                b.extrude([V2(0, 0.08), V2(0.06, 0), V2(0, -0.08), V2(-0.06, 0)], depth: 0.02,
                          V3(s * 0.165, 1.08, 0), .glow, rot: ry(s * .pi / 2))
            }
            b.cone(V3(0, 1.24, 0), V3(0, 1.42, 0), 0.06, .metal, segments: 8)
            weaponTip = V3(0, 1.1, 0)
        case .lightArrowBlade:
            grip(&b, 0.08)
            for i in 0..<3 {
                let a = Float(i) / 3 * 2 * .pi
                b.ellipsoid(V3(cos(a) * 0.03, -0.12, sin(a) * 0.03), V3(0.012, 0.06, 0.03), .accent, rot: ry(-a), detail: .low)
            }
            let arrow: [V2] = [V2(-0.03, 0), V2(0.03, 0), V2(0.03, 0.36), V2(0.1, 0.33), V2(0, 0.58), V2(-0.1, 0.33), V2(-0.03, 0.36)]
            b.blade(arrow, depth: 0.03, V3(0, 0.09, 0), .glow)
            b.rbox(V3(0, 0.1, 0), V3(0.05, 0.035, 0.16), 0.012, .metal)
            weaponTip = V3(0, 0.66, 0)
        case .sandRifle:
            b.rbox(V3(0, -0.2, 0), V3(0.07, 0.27, 0.12), 0.03, .secondary, rot: rx(0.15))
            b.rbox(V3(0, 0.05, 0), V3(0.08, 0.27, 0.1), 0.025, .metal)
            b.rod(V3(0, 0.15, 0), V3(0, 0.8, 0), 0.023, .metal)
            b.rod(V3(0, 0.77, 0), V3(0, 0.84, 0), 0.034, .metal, segments: 10)
            b.rod(V3(0, 0.02, 0.085), V3(0, 0.32, 0.085), 0.026, .dark, segments: 10)
            b.rod(V3(0, 0.32, 0.085), V3(0, 0.33, 0.085), 0.02, .glow, segments: 10)
            b.rod(V3(0.045, 0.06, 0), V3(0.06, 0.06, 0), 0.065, .accent, segments: 14)
            b.rod(V3(0.058, 0.06, 0), V3(0.066, 0.06, 0), 0.03, .glow, segments: 10)
            b.crystal(V3(0, 0.3, -0.05), radius: 0.025, height: 0.07, .glow, rot: rx(.pi / 2))
            weaponTip = V3(0, 0.84, 0)
        case .azureClaw:
            claw(&b, side: 1)
            weaponTip = V3(0, -0.3, -0.08)
        case .thunderLance:
            b.rod(V3(0, -0.32, 0), V3(0, 0.12, 0), 0.03, .dark)
            b.sphere(V3(0, -0.34, 0), 0.045, .metal, .low)
            b.lathe([V2(0.03, 0.06), V2(0.15, 0.13), V2(0.15, 0.13), V2(0.13, 0.155), V2(0.035, 0.21)], .zero, .metal, segments: 16)
            b.cone(V3(0, 0.19, 0), V3(0, 1.32, 0), 0.078, .metal, segments: 14)
            for (y, r) in [(Float(0.42), Float(0.062)), (0.68, 0.045), (0.94, 0.028)] {
                b.torus(V3(0, y, 0), r + 0.004, 0.012, .glow)
            }
            b.cone(V3(0, 1.18, 0), V3(0, 1.42, 0), 0.022, .glow, segments: 8)
            weaponTip = V3(0, 1.38, 0)
        case .dreamNeedle:
            needle(&b)
            weaponTip = V3(0, 0.52, 0)
        case .dragonSpear:
            // 竜牙の長槍: 暗い柄・銀の双刃の穂先・左右に張り出す青い竜の鰭・赤い房
            b.rod(V3(0, -0.5, 0), V3(0, 1.0, 0), 0.025, .dark, segments: 10)
            b.cone(V3(0, -0.5, 0), V3(0, -0.6, 0), 0.032, .metal)
            for y: Float in [-0.3, 0.2] { b.torus(V3(0, y, 0), 0.032, 0.011, .metal) }
            let head: [V2] = [V2(-0.05, 0), V2(0.05, 0), V2(0.07, 0.12), V2(0.045, 0.3), V2(0, 0.52), V2(-0.045, 0.3), V2(-0.07, 0.12)]
            b.blade(head, depth: 0.03, V3(0, 1.0, 0), .metal)
            b.rbox(V3(0, 1.2, 0), V3(0.044, 0.34, 0.02), 0.006, .glow)
            for s: Float in [-1, 1] {
                let fin: [V2] = [V2(s * 0.05, 0.02), V2(s * 0.21, -0.04), V2(s * 0.15, 0.1), V2(s * 0.19, 0.2), V2(s * 0.05, 0.16)]
                b.blade(fin, depth: 0.02, V3(0, 0.98, 0), .glow)
            }
            b.sphere(V3(0, 0.95, 0), 0.045, .accent, .low)
            for i in 0..<5 {
                let a = Float(i) / 5 * 2 * .pi
                b.cone(V3(cos(a) * 0.03, 0.96, sin(a) * 0.03), V3(cos(a) * 0.07, 0.76, sin(a) * 0.07), 0.025, .accent, segments: 5)
            }
            weaponTip = V3(0, 1.5, 0)
        case .stormWand:
            // 雷杖: 細い杖の先に稲妻の矢じりと輪
            b.rod(V3(0, -0.4, 0), V3(0, 0.78, 0), 0.02, .dark, segments: 8)
            b.cone(V3(0, -0.4, 0), V3(0, -0.5, 0), 0.026, .metal)
            for y: Float in [-0.1, 0.3] { b.torus(V3(0, y, 0), 0.028, 0.01, .accent) }
            let bolt: [V2] = [V2(-0.07, 0), V2(0.08, 0), V2(0.025, 0.15), V2(0.12, 0.15), V2(-0.025, 0.55), V2(0.0, 0.25), V2(-0.1, 0.25)]
            b.blade(bolt.map { $0 * 0.55 }, depth: 0.03, V3(0, 0.78, 0), .glow)
            b.torus(V3(0, 0.8, 0), 0.075, 0.01, .metal, rot: rx(.pi / 2), segments: 18)
            b.sphere(V3(0, 0.86, 0), 0.035, .glow, .low)
            weaponTip = V3(0, 1.06, 0)
        case .photonBlade:
            // 光刃の長剣: 発振器の柄から伸びる光の刃（白熱の芯）
            grip(&b, 0.1)
            b.rbox(V3(0, 0.12, 0), V3(0.06, 0.07, 0.26), 0.02, .metal)
            b.rod(V3(0, 0.15, 0), V3(0, 0.27, 0), 0.032, .dark, segments: 10)
            b.torus(V3(0, 0.27, 0), 0.036, 0.01, .glow)
            let beam: [V2] = [V2(-0.045, 0), V2(0.045, 0), V2(0.05, 0.52), V2(0, 0.72), V2(-0.05, 0.52)]
            b.blade(beam, depth: 0.03, V3(0, 0.28, 0), .glow)
            b.rbox(V3(0, 0.62, 0), V3(0.044, 0.56, 0.02), 0.006, .metal)
            weaponTip = V3(0, 0.98, 0)
        case .holyMaul:
            // 聖槌: 片手で振る巨大な大槌。長い柄・青い槌頭（前後の打撃面は金の当て金と金の帯）・上面と側面に聖印。
            // 槌頭は幅 0.36 × 高さ 0.38 × 長さ 0.71（打撃面は ±Z）。上方カメラでも槌頭の上面の聖印が読める
            b.rod(V3(0, -0.34, 0), V3(0, 0.92, 0), 0.04, .dark, segments: 10)
            b.sphere(V3(0, -0.37, 0), 0.062, .metal, .low)
            for y: Float in [-0.22, 0.04, 0.3] { b.torus(V3(0, y, 0), 0.05, 0.013, .metal, segments: 12, sides: 5) }
            b.rbox(V3(0, 1.08, 0), V3(0.36, 0.38, 0.56), 0.05, .primary)
            for s: Float in [-1, 1] {
                b.rbox(V3(0, 1.08, s * 0.31), V3(0.44, 0.46, 0.09), 0.04, .metal)
                b.rbox(V3(0, 1.08, s * 0.19), V3(0.4, 0.42, 0.06), 0.02, .metal)
            }
            // 上面の聖印（XY 面の星を水平に寝かせる）と、側面の聖印
            b.extrude(starPolygon(points: 4, outer: 0.15, inner: 0.05), depth: 0.02, V3(0, 1.275, 0), .glow, rot: rx(-.pi / 2))
            for s: Float in [-1, 1] {
                b.extrude([V2(0, 0.1), V2(0.07, 0), V2(0, -0.1), V2(-0.07, 0)], depth: 0.02,
                          V3(s * 0.188, 1.08, 0), .glow, rot: ry(s * .pi / 2))
            }
            weaponTip = V3(0, 1.08, 0)
        case .starCannon:
            // 星砲: 背丈ほどの大砲。金の砲身・広がる砲口と光の輪・側面の星・桃の動力球・白い台尻
            b.rbox(V3(0, -0.2, 0), V3(0.09, 0.3, 0.13), 0.03, .secondary, rot: rx(0.15))
            b.rbox(V3(0, 0.04, 0), V3(0.13, 0.3, 0.15), 0.035, .metal)
            b.frustum(V3(0, 0.14, 0), V3(0, 0.7, 0), 0.062, 0.078, .metal, segments: 14)
            let muzzle: [V2] = [V2(0.078, 0), V2(0.1, 0.04), V2(0.14, 0.1), V2(0.15, 0.13), V2(0.12, 0.13)]
            b.lathe(muzzle, V3(0, 0.7, 0), .metal, segments: 18)
            b.torus(V3(0, 0.83, 0), 0.135, 0.016, .glow, segments: 20)
            b.rod(V3(0, 0.77, 0), V3(0, 0.8, 0), 0.1, .glow, segments: 14)
            for (y, r) in [(Float(0.26), Float(0.07)), (0.58, 0.08)] { b.torus(V3(0, y, 0), r, 0.014, .accent) }
            for s: Float in [-1, 1] {
                b.extrude(starPolygon(points: 5, outer: 0.11, inner: 0.048), depth: 0.025, V3(s * 0.085, 0.42, 0), .glow,
                          rot: ry(.pi / 2))
            }
            b.rod(V3(0.075, 0.04, 0), V3(0.095, 0.04, 0), 0.07, .accent, segments: 14)
            b.rod(V3(0.093, 0.04, 0), V3(0.103, 0.04, 0), 0.035, .glow, segments: 10)
            b.rod(V3(0, 0.16, 0.09), V3(0, 0.5, 0.09), 0.016, .dark, segments: 6)
            b.sphere(V3(0, 0.5, 0.09), 0.025, .glow, .low)
            b.sphere(V3(0, -0.35, 0.03), 0.045, .metal, .low)
            weaponTip = V3(0, 0.88, 0)
        case .iceStaff:
            // 氷の杖: 白銀の細い杖の先に大きな氷の結晶（芯は光、外は半透明）と、根元を囲む氷の棘
            b.rod(V3(0, -0.46, 0), V3(0, 0.88, 0), 0.024, .metal)
            b.cone(V3(0, -0.46, 0), V3(0, -0.56, 0), 0.03, .metal)
            for y: Float in [-0.1, 0.34, 0.82] { b.torus(V3(0, y, 0), 0.032, 0.011, .accent) }
            b.crystal(V3(0, 1.1, 0), radius: 0.08, height: 0.22, .glow, sides: 6, bottom: 0.9)
            b.crystal(V3(0, 1.1, 0), radius: 0.11, height: 0.26, .veil, sides: 6, bottom: 1.0)
            b.torus(V3(0, 0.92, 0), 0.07, 0.012, .metal)
            for i in 0..<4 {
                let a = Float(i) / 4 * 2 * .pi + .pi / 4
                let p = V3(cos(a) * 0.09, 0.93, sin(a) * 0.09)
                b.cone(p, p + V3(cos(a) * 0.1, 0.12, sin(a) * 0.1), 0.028, .accent, segments: 5)
            }
            weaponTip = V3(0, 1.12, 0)
        case .fistBlade:
            // 拳剣: 手を覆う鉄の籠手（手首の防具と包帯）と、拳の先から長く伸びる幅広の刃（赤い芯）
            b.rbox(V3(0, 0.02, 0), V3(0.15, 0.15, 0.19), 0.04, .metal)
            b.frustum(V3(0, -0.24, 0), V3(0, -0.04, 0), 0.07, 0.085, .metal)
            b.torus(V3(0, -0.2, 0), 0.078, 0.014, .accent)
            b.torus(V3(0, -0.12, 0), 0.08, 0.012, .cloth)
            b.rbox(V3(0, 0.12, 0), V3(0.05, 0.05, 0.22), 0.02, .metal)
            let blade: [V2] = [V2(-0.085, 0), V2(0.085, 0), V2(0.1, 0.5), V2(0, 0.78), V2(-0.085, 0.5)]
            b.blade(blade, depth: 0.04, V3(0, 0.14, 0), .metal)
            b.rbox(V3(0, 0.5, 0), V3(0.046, 0.6, 0.026), 0.008, .glow)
            weaponTip = V3(0, 0.9, 0)
        case .bloodGreatsword:
            // 血の大剣: 両手持ちの巨大な剣。黒鋼の幅広の刃・深紅の血溝と縁・蝙蝠の翼の鍔
            grip(&b, 0.16)
            b.rbox(V3(0, 0.19, 0), V3(0.07, 0.06, 0.16), 0.02, .metal)
            for s: Float in [-1, 1] {
                let wing: [V2] = [V2(s * 0.04, 0), V2(s * 0.27, 0.02), V2(s * 0.2, 0.08), V2(s * 0.29, 0.15), V2(s * 0.12, 0.13),
                                  V2(s * 0.04, 0.1)]
                b.blade(wing, depth: 0.034, V3(0, 0.17, 0), .accent)
            }
            let blade: [V2] = [V2(-0.1, 0), V2(0.1, 0), V2(0.118, 0.86), V2(0, 1.1), V2(-0.118, 0.86)]
            b.blade(blade, depth: 0.05, V3(0, 0.25, 0), .metal)
            b.rbox(V3(0, 0.7, 0), V3(0.058, 0.8, 0.03), 0.01, .dark)
            for s: Float in [-1, 1] { b.rbox(V3(0, 0.66, s * 0.1), V3(0.056, 0.7, 0.018), 0.006, .glow) }
            weaponTip = V3(0, 1.34, 0)
        case .hookChain:
            // 鎖鉤: 革巻きの握りから伸びる太い鎖（環は一つおきに向きを変える）と、先端の大きな鉤
            b.rod(V3(0, -0.2, 0), V3(0, 0.1, 0), 0.036, .dark, segments: 10)
            b.sphere(V3(0, -0.22, 0), 0.05, .metal, .low)
            for y: Float in [-0.12, -0.04, 0.04] { b.torus(V3(0, y, 0), 0.04, 0.011, .accent) }
            b.rbox(V3(0, 0.12, 0), V3(0.1, 0.05, 0.1), 0.02, .metal)
            for i in 0..<11 {
                let t = Float(i) / 10
                let link: simd_quatf = (i % 2 == 0 ? qIdentity : ry(.pi / 2)) * rx(.pi / 2)
                b.torus(V3(0, 0.2 + Float(i) * 0.055, -0.1 * sin(t * Float.pi)), 0.034, 0.01, .metal, rot: link,
                        segments: 8, sides: 4)
            }
            b.rod(V3(0, 0.74, 0), V3(0, 1.0, 0), 0.03, .metal, segments: 8)
            b.torus(V3(0.11, 1.0, 0), 0.11, 0.03, .metal, rot: rz(.pi) * rx(.pi / 2), segments: 14, sides: 6, arc: .pi * 1.5)
            b.cone(V3(0.11, 0.89, 0), V3(0.04, 0.92, 0), 0.03, .metal, segments: 6)
            weaponTip = V3(0, 1.1, 0)
        }
        return b
    }

    // MARK: 左手

    func offhand() -> HeroMeshBuilder {
        var b = HeroMeshBuilder()
        switch bp.offhand {
        case .none:
            break
        case .gateShield:
            // 原点で組んでから、外側へ少し向けて左腕の外に置く
            var sh = HeroMeshBuilder()
            var tower: [V2] = [V2(0.27, -0.3), V2(0.27, 0.3), V2(0.2, 0.3), V2(0.2, 0.43), V2(0.095, 0.43), V2(0.095, 0.35),
                               V2(-0.095, 0.35), V2(-0.095, 0.43), V2(-0.2, 0.43), V2(-0.2, 0.3), V2(-0.27, 0.3), V2(-0.27, -0.3)]
            tower.append(V2(0, -0.46))
            sh.extrude(tower, depth: 0.06, .zero, .primary)
            sh.extrude(tower.map { $0 * 1.08 + V2(0, -0.005) }, depth: 0.045, V3(0, 0, 0.02), .metal)
            var arch: [V2] = [V2(0.105, 0.02), V2(0.105, -0.3), V2(-0.105, -0.3), V2(-0.105, 0.02)]
            arch.append(contentsOf: arcPoints(V2(0, 0.02), 0.105, .pi, 0, 8).dropFirst().dropLast())
            sh.extrude(arch, depth: 0.02, V3(0, 0, -0.035), .dark)
            for x: Float in [-0.05, 0, 0.05] { sh.box(V3(x, -0.12, -0.046), V3(0.016, 0.3, 0.012), .metal) }
            sh.box(V3(0, -0.1, -0.046), V3(0.2, 0.016, 0.012), .metal)
            for s: Float in [-1, 1] { sh.rbox(V3(s * 0.19, -0.02, -0.036), V3(0.035, 0.5, 0.02), 0.008, .metal) }
            sh.extrude([V2(0, 0.06), V2(0.045, 0), V2(0, -0.06), V2(-0.045, 0)], depth: 0.02, V3(0, 0.2, -0.04), .glow)
            b.merge(sh, trs(V3(-0.15, 0.1, -0.1), ry(0.4)))
            b.rod(V3(0, -0.06, 0), V3(0, 0.08, 0), 0.022, .dark)
        case .harpBow:
            let o = V3(-0.02, 0.2, -0.04)
            for s: Float in [-1, 1] {
                let horn = crescentPolygon(radius: 0.22, thickness: 0.045, span: 2.2, offset: 0.03)
                b.extrude(horn, depth: 0.035, o + V3(s * 0.02, 0, 0), .metal, rot: s < 0 ? rz(.pi) : qIdentity)
                b.sphere(o + V3(s * 0.12, 0.2, 0), 0.03, .glow, .low)
            }
            b.rbox(o + V3(0, -0.2, 0), V3(0.2, 0.05, 0.05), 0.018, .accent)
            b.rbox(o + V3(0, 0.16, 0), V3(0.22, 0.035, 0.04), 0.012, .metal)
            for x: Float in [-0.06, 0, 0.06] { b.rod(o + V3(x, -0.18, 0), o + V3(x, 0.15, 0), 0.006, .glow) }
            b.extrude(starPolygon(points: 5, outer: 0.055, inner: 0.024), depth: 0.025, o + V3(0, 0.2, -0.01), .glow)
        case .ashBow:
            // 月弓（H003 フィリエル）: 金の細い弓身に月光の内縁。棘は付けない
            var bw = HeroMeshBuilder()
            bow(&bw, radius: 0.7, limbMat: .metal, glowEdge: true, spikes: false)
            b.merge(bw, trs(.zero, ry(0.6)))
        case .moonLantern:
            b.torus(V3(0, 0, 0), 0.035, 0.011, .metal, rot: rz(.pi / 2))
            b.rod(V3(0, -0.02, 0), V3(0, -0.1, 0), 0.009, .metal)
            b.cone(V3(0, -0.16, 0), V3(0, -0.09, 0), 0.09, .metal, segments: 10)
            b.sphere(V3(0, -0.26, 0), 0.1, .veil)
            b.sphere(V3(0, -0.26, 0), 0.045, .glow, .low)
            b.extrude(crescentPolygon(radius: 0.06, thickness: 0.025, span: 4, offset: 0.02), depth: 0.02,
                      V3(0, -0.26, 0), .glow, rot: rz(0.4))
            b.cone(V3(0, -0.35, 0), V3(0, -0.42, 0), 0.07, .metal, segments: 10)
            for i in 0..<4 {
                let a = Float(i) / 4 * 2 * .pi
                b.rod(V3(cos(a) * 0.092, -0.16, sin(a) * 0.092), V3(cos(a) * 0.092, -0.35, sin(a) * 0.092), 0.008, .metal)
            }
        case .stoneFist:
            stoneFist(&b, side: -1)
        case .grimoire:
            let o = V3(-0.03, 0.06, -0.06)
            b.rbox(o, V3(0.075, 0.28, 0.22), 0.02, .secondary)
            b.rbox(o + V3(0.004, 0, -0.008), V3(0.06, 0.26, 0.2), 0.01, .cloth)
            b.extrude(starPolygon(points: 6, outer: 0.06, inner: 0.03), depth: 0.02, o + V3(-0.04, 0, 0), .glow, rot: ry(.pi / 2))
            for y: Float in [-0.13, 0.13] {
                for z: Float in [-0.1, 0.1] { b.sphere(o + V3(-0.035, y, z), 0.018, .metal, .low) }
            }
            b.rbox(o + V3(0, 0, -0.11), V3(0.085, 0.05, 0.02), 0.008, .accent)
        case .glassDagger:
            glassDagger(&b)
        case .hideShield:
            let o = V3(-0.1, 0.08, -0.1)
            b.lathe([V2(0.31, 0.0), V2(0.3, 0.03), V2(0.2, 0.065), V2(0.0, 0.08)], o, .primary, rot: rx(-.pi / 2),
                    segments: 20, capBottom: true)
            b.torus(o, 0.31, 0.026, .metal, rot: rx(.pi / 2), segments: 24)
            b.sphere(o + V3(0, 0, -0.08), 0.07, .metal)
            for i in 0..<5 {
                let a = Float(i) / 5 * 2 * .pi + .pi / 2
                let p = o + V3(cos(a) * 0.3, sin(a) * 0.3, 0)
                b.cone(p, p + V3(cos(a) * 0.12, sin(a) * 0.12, 0), 0.03, .cloth, segments: 6)
            }
            for i in 0..<3 {
                let y = Float(i - 1) * 0.1
                b.extrude([V2(-0.07, 0.03), V2(0, -0.02), V2(0.07, 0.03), V2(0.07, 0.0), V2(0, -0.05), V2(-0.07, 0.0)],
                          depth: 0.02, o + V3(0, y + (i == 1 ? 0 : 0), -0.07 + abs(y) * 0.1), .glow)
            }
        case .shortBlade:
            katana(&b, scale: 0.62)
        case .petalBlade:
            dagger(&b, petalShape(), bladeMat: .accent, glowEdge: false)
            b.rbox(V3(0, 0.3, 0), V3(0.036, 0.24, 0.012), 0.005, .glow)
        case .lightBow:
            var bw = HeroMeshBuilder()
            bow(&bw, radius: 0.58, limbMat: .metal, glowEdge: true, spikes: false)
            let tipY = sin(Float(0.94)) * 0.58
            for s: Float in [-1, 1] { bw.sphere(V3(0, s * tipY, 0.58 - 0.02 - cos(0.94) * 0.58), 0.04, .glow, .low) }
            b.merge(bw, trs(.zero, ry(0.6)))
        case .azureClaw:
            claw(&b, side: -1)
        case .dreamNeedle:
            needle(&b)
        case .crescentBow:
            // 三日月の長弓（H025 ルミナ）: 大きな月光の弓身・弓先の光玉・握りの月珠
            var bw = HeroMeshBuilder()
            let R: Float = 0.78
            bow(&bw, radius: R, limbMat: .metal, glowEdge: true, spikes: false)
            let tipY = sin(Float(0.94)) * R
            let tipZ = R - 0.02 - cos(Float(0.94)) * R
            for s: Float in [-1, 1] { bw.sphere(V3(0, s * tipY, tipZ), 0.04, .glow, .low) }
            bw.sphere(V3(0, 0, -0.06), 0.045, .glow, .low)
            b.merge(bw, trs(.zero, ry(0.6)))
        case .heaterShield:
            // 聖槌の大盾（H029 ボルグ）: 縦長の凧形（盾面 幅 0.54 × 高さ 0.84、縁取り込みで 0.62 × 0.96）。金の盾面・青い縁取り・青い十字と聖印の光。
            // 原点で組んでから、左の手の外側へ少し向けて置く（面は -Z）
            var sh = HeroMeshBuilder()
            let face: [V2] = [V2(-0.27, 0.34), V2(0.27, 0.34), V2(0.27, 0.1), V2(0.2, -0.18), V2(0, -0.5),
                              V2(-0.2, -0.18), V2(-0.27, 0.1)]
            sh.extrude(face, depth: 0.05, .zero, .metal)
            sh.extrude(face.map { $0 * 1.14 }, depth: 0.04, V3(0, 0, 0.02), .primary)
            sh.box(V3(0, 0.02, -0.036), V3(0.07, 0.6, 0.02), .primary)
            sh.box(V3(0, 0.13, -0.036), V3(0.38, 0.07, 0.02), .primary)
            sh.extrude([V2(0, 0.075), V2(0.055, 0), V2(0, -0.075), V2(-0.055, 0)], depth: 0.02, V3(0, 0.13, -0.05), .glow)
            b.merge(sh, trs(V3(-0.1, 0.02, -0.12), ry(0.3)))
            b.rod(V3(0, -0.06, 0), V3(0, 0.08, 0), 0.024, .dark)
        }
        return b
    }

    /// 副手の先端（副手ローカル。weaponTip の副手版で、武器の軌跡・発射位置に使う）。nil = 先端を使わない（盾・本）。
    /// 刃は上の offhand() の刃先、弓は握り（矢を番える位置）、灯籠は火袋、籠手・爪は weaponTip と同じ。
    static func offhandTip(_ kind: OffhandKind) -> V3? {
        switch kind {
        case .glassDagger: return V3(0, 0.48, 0)
        case .petalBlade: return V3(0, 0.46, 0)
        case .dreamNeedle: return V3(0, 0.52, 0)
        // katana(scale: 0.62): 霧の刀の先端 0.96 × 0.62
        case .shortBlade: return V3(0, 0.6, 0)
        case .moonLantern: return V3(0, -0.26, 0)
        case .harpBow, .ashBow, .lightBow, .crescentBow: return .zero
        case .stoneFist: return V3(0, -0.15, 0)
        case .azureClaw: return V3(0, -0.3, -0.08)
        case .none, .gateShield, .grimoire, .hideShield, .heaterShield: return nil
        }
    }

    // MARK: 部品

    private func grip(_ b: inout HeroMeshBuilder, _ half: Float) {
        b.rod(V3(0, -half, 0), V3(0, half, 0), 0.024, .dark)
        b.sphere(V3(0, -half - 0.025, 0), 0.04, .metal, .low)
    }

    private func dagger(_ b: inout HeroMeshBuilder, _ shape: [V2], bladeMat: HeroMat, glowEdge: Bool) {
        grip(&b, 0.07)
        b.rbox(V3(0, 0.085, 0), V3(0.045, 0.04, 0.16), 0.014, .metal)
        b.blade(shape, depth: 0.032, V3(0, 0.1, 0), bladeMat)
        if glowEdge {
            let edge: [V2] = [V2(0.1, 0.08), V2(0.135, 0.18), V2(0.105, 0.29), V2(0.095, 0.28), V2(0.118, 0.18), V2(0.09, 0.09)]
            b.blade(edge, depth: 0.038, V3(0, 0.1, 0), .glow)
        }
    }

    private func crescentBlade() -> [V2] {
        [V2(-0.025, 0), V2(0.035, 0), V2(0.105, 0.08), V2(0.138, 0.18), V2(0.108, 0.29), V2(0.02, 0.38),
         V2(0.038, 0.28), V2(0.065, 0.18), V2(0.045, 0.09)]
    }

    private func petalShape() -> [V2] {
        [V2(0, 0), V2(0.065, 0.06), V2(0.08, 0.18), V2(0.045, 0.3), V2(0, 0.4), V2(-0.045, 0.3), V2(-0.08, 0.18), V2(-0.065, 0.06)]
    }

    private func glassDagger(_ b: inout HeroMeshBuilder) {
        b.rod(V3(0, -0.07, 0), V3(0, 0.07, 0), 0.022, .dark)
        b.crystal(V3(0, -0.09, 0), radius: 0.03, height: 0.03, .glow, bottom: 1)
        b.crystal(V3(0, 0.09, 0), radius: 0.07, height: 0.05, .accent, rot: rx(.pi / 2), sides: 4, bottom: 1)
        b.crystal(V3(0, 0.12, 0), radius: 0.058, height: 0.38, .veil, sides: 4, bottom: 0.15)
        b.crystal(V3(0, 0.12, 0), radius: 0.028, height: 0.3, .glow, sides: 4, bottom: 0.1)
    }

    private func katana(_ b: inout HeroMeshBuilder, scale k: Float) {
        b.rod(V3(0, -0.13 * k, 0), V3(0, 0.12 * k, 0), 0.023, .dark)
        b.sphere(V3(0, -0.14 * k, 0), 0.03, .metal, .low)
        b.rod(V3(0, 0.12 * k, 0), V3(0, 0.14 * k, 0), 0.065, .metal, segments: 12)
        let blade: [V2] = [V2(-0.014, 0), V2(0.03, 0), V2(0.038, 0.3), V2(0.024, 0.6), V2(-0.01, 0.8), V2(-0.034, 0.85),
                           V2(-0.022, 0.6), V2(-0.014, 0.3)].map { V2($0.x * (0.6 + 0.4 * k), $0.y * k) }
        b.blade(blade, depth: 0.022, V3(0, 0.14 * k, 0), .metal)
        let edge: [V2] = [V2(0.03, 0.02), V2(0.04, 0.02), V2(0.047, 0.3), V2(0.03, 0.6), V2(0.0, 0.8), V2(-0.01, 0.8),
                          V2(0.02, 0.6), V2(0.036, 0.3)].map { V2($0.x * (0.6 + 0.4 * k), $0.y * k) }
        b.blade(edge, depth: 0.026, V3(0, 0.14 * k, 0), .glow)
    }

    private func stoneFist(_ b: inout HeroMeshBuilder, side s: Float) {
        b.rbox(V3(0, -0.035, 0), V3(0.25, 0.25, 0.27), 0.075, .metal)
        b.rbox(V3(0, -0.14, -0.02), V3(0.27, 0.085, 0.23), 0.03, .metal)
        b.rbox(V3(s * 0.06, 0.08, 0.02), V3(0.13, 0.1, 0.13), 0.03, .metal, rot: rz(s * 0.4))
        b.crystal(V3(-s * 0.05, 0.02, -0.14), radius: 0.035, height: 0.1, .glow, rot: rx(-1.2))
        b.crystal(V3(s * 0.12, 0.0, 0.05), radius: 0.03, height: 0.09, .glow, rot: rz(-s * 1.0))
        b.rbox(V3(0, -0.035, -0.136), V3(0.2, 0.022, 0.012), 0.004, .glow)
        b.frustum(V3(0, 0.05, 0), V3(0, 0.15, 0), 0.105, 0.095, .metal)
    }

    private func claw(_ b: inout HeroMeshBuilder, side s: Float) {
        b.rbox(V3(0, -0.02, 0), V3(0.15, 0.15, 0.16), 0.045, .metal)
        b.frustum(V3(0, 0.03, 0), V3(0, 0.13, 0), 0.085, 0.078, .metal)
        b.sphere(V3(s * 0.078, -0.02, 0), 0.03, .glow, .low)
        let shape: [V2] = [V2(-0.012, 0), V2(0.03, 0), V2(0.07, -0.13), V2(0.13, -0.28), V2(0.05, -0.2), V2(0.0, -0.1)]
        for i in -1...1 {
            let x = Float(i) * 0.048
            b.blade(shape, depth: 0.022, V3(x, -0.07, -0.03), .accent)
        }
    }

    private func needle(_ b: inout HeroMeshBuilder) {
        b.rod(V3(0, -0.06, 0), V3(0, 0.06, 0), 0.036, .accent, segments: 12)
        b.rod(V3(0, 0.06, 0), V3(0, 0.078, 0), 0.052, .metal, segments: 12)
        b.rod(V3(0, -0.078, 0), V3(0, -0.06, 0), 0.052, .metal, segments: 12)
        b.torus(V3(0, -0.02, 0), 0.039, 0.008, .glow)
        b.torus(V3(0, 0.02, 0), 0.039, 0.008, .glow)
        b.cone(V3(0, 0.078, 0), V3(0, 0.54, 0), 0.024, .metal, segments: 8)
        b.torus(V3(0, 0.12, 0), 0.02, 0.006, .glow, rot: rz(.pi / 2), segments: 10, sides: 4)
    }

    /// 弓（YZ 平面、握りが原点、弦は背側 +Z）。
    private func bow(_ b: inout HeroMeshBuilder, radius R: Float, limbMat: HeroMat, glowEdge: Bool, spikes: Bool) {
        let span: Float = 1.9
        let c = V3(0, 0, R - 0.02)
        b.blade(crescentPolygon(radius: R, thickness: 0.06, span: span, offset: 0.0), depth: 0.055, c, limbMat)
        if glowEdge {
            b.blade(crescentPolygon(radius: R - 0.04, thickness: 0.016, span: span * 0.9, offset: 0.0), depth: 0.065, c, .glow)
        }
        if spikes {
            for a: Float in [-0.72, -0.4, 0.4, 0.72] {
                let dir = V2(cos(a), sin(a))
                let tangent = V2(-dir.y, dir.x)
                let base = dir * R
                let tri: [V2] = [base - tangent * 0.035, base + tangent * 0.035, base + dir * 0.075 + tangent * 0.02]
                b.blade(tri, depth: 0.03, c, limbMat)
            }
        }
        b.rbox(V3(0, 0, 0.01), V3(0.055, 0.15, 0.065), 0.02, .dark)
        let tipY = sin(span / 2 * 0.99) * R
        let tipZ = R - 0.02 - cos(span / 2 * 0.99) * R
        b.rod(V3(0, tipY, tipZ), V3(0, -tipY, tipZ), 0.005, .glow, segments: 5)
    }

    // MARK: 旗

    func flag() -> HeroMeshBuilder {
        var b = HeroMeshBuilder()
        guard bp.weapon == .windBanner else { return b }
        let shape: [V2] = [V2(0, 0), V2(-0.62, -0.03), V2(-0.5, -0.22), V2(-0.62, -0.42), V2(0, -0.38)]
        b.blade(shape, depth: 0.016, .zero, .accent)
        b.torus(V3(0, -0.19, 0.25), 0.075, 0.014, .glow, rot: rz(.pi / 2), segments: 16, sides: 5)
        b.extrude(starPolygon(points: 4, outer: 0.05, inner: 0.018), depth: 0.024, V3(0, -0.19, 0.25), .glow, rot: ry(.pi / 2))
        return b
    }

    // MARK: 背中

    func back() -> HeroMeshBuilder {
        var b = HeroMeshBuilder()
        let w = m.torsoW
        switch bp.back {
        case .none, .ironWings:
            if bp.back == .ironWings {
                b.rbox(V3(0, -0.05, 0.03), V3(0.22, 0.24, 0.08), 0.03, .metal)
                b.rod(V3(0, -0.05, 0.07), V3(0, -0.05, 0.085), 0.05, .glow, segments: 12)
            }
        case .cape:
            let len: Float = bp.build.isHeavy ? 0.8 : 0.7
            b.add(MeshTemplate.cloth(w0: w * 0.8, w1: w * 1.2, length: len, curve: 0.14, bulge: 0.07, cols: 6, rows: 6),
                  trs(.zero), .accent)
            for s: Float in [-1, 1] { b.sphere(V3(s * w * 0.38, 0, -0.01), 0.04, .metal, .low) }
            b.add(MeshTemplate.cloth(w0: w * 0.82, w1: w * 0.82, length: 0.05, curve: 0, bulge: 0.07, cols: 6, rows: 1),
                  trs(V3(0, 0.0, 0.004)), .metal)
        case .tatteredCape:
            b.add(MeshTemplate.cloth(w0: w * 0.8, w1: w * 1.3, length: 0.78, curve: 0.16, bulge: 0.07, cols: 8, rows: 6, jag: 0.28),
                  trs(.zero), .secondary)
            b.add(MeshTemplate.cloth(w0: w * 0.82, w1: w * 0.84, length: 0.06, curve: 0, bulge: 0.07, cols: 6, rows: 1),
                  trs(V3(0, 0, 0.004)), .accent)
        case .mistCloak:
            b.add(MeshTemplate.cloth(w0: w * 0.9, w1: w * 1.55, length: 0.95, curve: 0.2, bulge: 0.08, cols: 8, rows: 7, jag: 0.22),
                  trs(.zero), .veil)
            b.add(MeshTemplate.torus(minor: 0.2, segments: 18, sides: 6),
                  trs(V3(0, 0.04, -0.12), qIdentity, V3(w * 0.52, w * 0.52, w * 0.45)), .veil)
        case .furCape:
            b.add(MeshTemplate.cloth(w0: w * 0.9, w1: w * 1.05, length: 0.62, curve: 0.1, bulge: 0.1, cols: 7, rows: 5, jag: 0.4),
                  trs(.zero), .cloth)
        case .quiver:
            let a = V3(-0.1, -0.34, 0.07), c = V3(0.13, 0.14, 0.07)
            b.frustum(a, c, 0.075, 0.08, .secondary, segments: 12)
            b.torus(c, 0.082, 0.014, .metal, rot: rotationFromY(to: c - a))
            b.torus(a + (c - a) * 0.3, 0.08, 0.01, .metal, rot: rotationFromY(to: c - a))
            let dir = simd_normalize(c - a)
            for i in 0..<4 {
                let off = V3(Float(i % 2) * 0.04 - 0.02, 0, Float(i / 2) * 0.04 - 0.02)
                let p0 = c + off, p1 = c + off + dir * 0.16
                b.rod(p0, p1, 0.008, .dark, segments: 5)
                b.ellipsoid(p1 + dir * 0.02, V3(0.03, 0.05, 0.01), .accent, rot: rotationFromY(to: dir), detail: .low)
            }
        case .warBell:
            let o = V3(0, -0.08, 0.2)
            let bell: [V2] = [V2(0.2, -0.3), V2(0.215, -0.28), V2(0.175, -0.2), V2(0.14, -0.06), V2(0.12, 0.04), V2(0.08, 0.1), V2(0, 0.12)]
            b.lathe(bell, o, .metal, segments: 18)
            b.lathe([V2(0.0, -0.1), V2(0.19, -0.29)], o, .dark, segments: 18)
            b.torus(o + V3(0, -0.21, 0), 0.165, 0.016, .glow, segments: 20)
            b.sphere(o + V3(0, -0.31, 0), 0.045, .metal, .low)
            b.rbox(o + V3(0, 0.14, -0.02), V3(0.42, 0.05, 0.06), 0.02, .secondary)
            for s: Float in [-1, 1] { b.rbox(V3(s * 0.12, 0.02, 0.05), V3(0.05, 0.22, 0.03), 0.01, .dark, rot: rz(s * 0.3)) }
        case .gearPack:
            b.rbox(V3(0, -0.12, 0.1), V3(0.34, 0.34, 0.18), 0.05, .secondary)
            gear(&b, V3(-0.08, -0.04, 0.2), 0.09)
            gear(&b, V3(0.1, 0.06, 0.2), 0.06)
            b.rod(V3(0.12, 0.0, 0.12), V3(0.15, 0.3, 0.14), 0.03, .metal)
            b.torus(V3(0.15, 0.3, 0.14), 0.035, 0.012, .dark)
            b.rod(V3(0, -0.2, 0.19), V3(0, -0.2, 0.2), 0.045, .glow, segments: 12)
            b.rod(V3(0.07, -0.2, 0.19), V3(0.07, -0.2, 0.2), 0.02, .accent, segments: 8)
        case .scarfTails:
            for s: Float in [-1, 1] {
                b.add(MeshTemplate.cloth(w0: 0.08, w1: 0.1, length: 0.46, curve: 0.18, bulge: 0, cols: 1, rows: 5),
                      trs(V3(s * 0.05, 0.1, 0), rz(s * 0.15)), .accent)
            }
        case .windRibbons:
            for s: Float in [-1, 1] {
                b.add(MeshTemplate.cloth(w0: 0.07, w1: 0.05, length: 0.72, curve: 0.34, bulge: 0, cols: 1, rows: 6),
                      trs(V3(s * 0.08, -0.05, 0), rz(s * 0.25)), .accent)
            }
            b.sphere(V3(0, -0.05, 0.01), 0.045, .glow, .low)
        case .sash:
            let o = V3(0, -0.3, 0.03)
            for s: Float in [-1, 1] {
                b.ellipsoid(o + V3(s * 0.1, 0.02, 0), V3(0.1, 0.06, 0.04), .accent, rot: rz(s * 0.4))
                b.add(MeshTemplate.cloth(w0: 0.06, w1: 0.07, length: 0.3, curve: 0.1, bulge: 0, cols: 1, rows: 4),
                      trs(o + V3(s * 0.04, -0.02, 0), rz(s * 0.3)), .accent)
            }
            b.sphere(o, 0.045, .glow, .low)
        case .chainSash:
            // 背に斜めに掛けた太い鎖（腰から肩へ）。下端の鉤と肩の留め具
            let a = V3(-w * 0.42, -0.34, 0.06), c = V3(w * 0.42, 0.02, 0.06)
            let dir = rotationFromY(to: c - a)
            for i in 0..<7 {
                let p = a + (c - a) * (Float(i) / 6)
                let link: simd_quatf = dir * (i % 2 == 0 ? qIdentity : ry(.pi / 2)) * rx(.pi / 2)
                b.torus(p, 0.05, 0.015, .metal, rot: link, segments: 8, sides: 4)
            }
            b.sphere(c, 0.05, .accent, .low)
            b.cone(a, a + V3(0, -0.16, 0), 0.03, .metal, segments: 5)
        }
        return b
    }

    private func gear(_ b: inout HeroMeshBuilder, _ c: V3, _ r: Float) {
        b.rod(c + V3(0, 0, -0.015), c + V3(0, 0, 0.015), r, .metal, segments: 14)
        for i in 0..<8 {
            let a = Float(i) / 8 * 2 * .pi
            b.box(c + V3(cos(a) * r, sin(a) * r, 0), V3(0.03, 0.03, 0.028), .metal, rot: rz(a))
        }
        b.rod(c + V3(0, 0, 0.012), c + V3(0, 0, 0.02), r * 0.35, .glow, segments: 10)
    }

    /// 鉄の翼（片側）。根元が原点、外側へ広がる。
    func wing(side s: Float) -> HeroMeshBuilder {
        var b = HeroMeshBuilder()
        guard bp.back == .ironWings else { return b }
        let tip = V3(s * 0.4, 0.3, 0.08)
        b.limb(.zero, tip, 0.04, 0.025, .metal)
        b.sphere(tip, 0.04, .glow, .low)
        for i in 0..<6 {
            let t = Float(i) / 5
            let p = tip * (0.25 + 0.75 * t)
            let len: Float = 0.52 - t * 0.2
            let feather: [V2] = [V2(-0.04, 0), V2(0.04, 0), V2(0.035, -len * 0.82), V2(0, -len), V2(-0.035, -len * 0.82)]
            let rot = rz(s * (0.15 + t * 0.55)) * rx(-0.12)
            b.extrude(feather, depth: 0.018, p + V3(0, 0, 0.01 * Float(i)), .metal, rot: rot)
            let core: [V2] = [V2(-0.01, -0.05), V2(0.01, -0.05), V2(0.008, -len * 0.8), V2(-0.008, -len * 0.8)]
            b.extrude(core, depth: 0.024, p + V3(0, 0, 0.01 * Float(i)), .glow, rot: rot)
        }
        return b
    }

    // MARK: 浮遊物

    mutating func floating() -> HeroMeshBuilder {
        var b = HeroMeshBuilder()
        let headZ = m.torsoD * 0.5 + 0.2
        let headH = m.torsoLen + m.headY + 0.04
        switch bp.float {
        case .none:
            floatMotion = .none
        case .waterOrb:
            floatMotion = .orbit(speed: 0.9)
            floatAnchor = V3(0, 1.15, 0)
            b.sphere(V3(0.58, 0, 0), 0.12, .glow)
            b.torus(V3(0.58, 0, 0), 0.17, 0.012, .veil, rot: rz(0.5))
            for i in 0..<3 {
                let a = Float(i) / 3 * 2 * .pi
                b.sphere(V3(0.58 + cos(a) * 0.2, sin(a) * 0.12, sin(a) * 0.2), 0.03, .glow, .low)
            }
            b.sphere(V3(-0.55, 0.15, 0), 0.06, .glow, .low)
        case .lightningHalo:
            floatMotion = .halo(speed: 0.8)
            floatAnchor = V3(0, headH, headZ)
            b.torus(.zero, 0.36, 0.022, .metal, rot: rx(.pi / 2), segments: 28)
            let bolt: [V2] = [V2(-0.02, 0), V2(0.03, 0), V2(0.0, 0.06), V2(0.04, 0.06), V2(-0.02, 0.16), V2(-0.005, 0.08), V2(-0.04, 0.08)]
            for i in 0..<8 {
                let a = Float(i) / 8 * 2 * .pi
                let p = V3(cos(a) * 0.36, sin(a) * 0.36, 0)
                b.extrude(bolt, depth: 0.025, p, .glow, rot: rz(a - .pi / 2))
            }
        case .fireOrbs:
            floatMotion = .orbit(speed: 1.6)
            floatAnchor = V3(0, 1.2, 0)
            for i in 0..<3 {
                let a = Float(i) / 3 * 2 * .pi
                let p = V3(cos(a) * 0.5, Float(i) * 0.08 - 0.05, sin(a) * 0.5)
                b.sphere(p, 0.07, .glow, .low)
                b.cone(p + V3(0, 0.02, 0), p + V3(0, 0.17, 0), 0.055, .accent, segments: 6)
            }
        case .glassShards:
            floatMotion = .orbit(speed: 1.2)
            floatAnchor = V3(0, 1.1, 0)
            for i in 0..<6 {
                let a = Float(i) / 6 * 2 * .pi
                let p = V3(cos(a) * 0.52, (i % 2 == 0 ? 0.12 : -0.05), sin(a) * 0.52)
                let rot = ry(-a) * rz(0.5 + Float(i) * 0.3)
                b.crystal(p, radius: 0.045, height: 0.14, .veil, rot: rot, sides: 4, bottom: 0.6)
                b.crystal(p, radius: 0.02, height: 0.1, .glow, rot: rot, sides: 4, bottom: 0.6)
            }
        case .whiteHalo:
            floatMotion = .halo(speed: 0.35)
            floatAnchor = V3(0, headH + 0.02, headZ)
            b.torus(.zero, 0.44, 0.032, .glow, rot: rx(.pi / 2), segments: 32)
            b.torus(.zero, 0.5, 0.012, .metal, rot: rx(.pi / 2), segments: 32)
            for i in 0..<8 {
                let a = Float(i) / 8 * 2 * .pi
                let p = V3(cos(a) * 0.5, sin(a) * 0.5, 0)
                b.crystal(p, radius: 0.03, height: 0.08, .glow, rot: rz(a - .pi / 2), sides: 4, bottom: 0.4)
            }
        case .abyssChains:
            floatMotion = .orbit(speed: 0.7)
            floatAnchor = V3(0, 1.0, 0)
            for (ring, tilt) in [(0, Float(0.35)), (1, Float(-0.3))] {
                let links = 16
                let R: Float = ring == 0 ? 0.58 : 0.52
                for i in 0..<links {
                    let a = Float(i) / Float(links) * 2 * .pi
                    let local = V3(cos(a) * R, 0, sin(a) * R)
                    let tilted = rx(tilt).act(local) + V3(0, Float(ring) * 0.3, 0)
                    let tangent = rx(tilt).act(V3(-sin(a), 0, cos(a)))
                    let base = rotationFromY(to: tangent)
                    b.torus(tilted, 0.032, 0.009, .metal, rot: base * (i % 2 == 0 ? qIdentity : ry(.pi / 2)) * rx(.pi / 2),
                            segments: 10, sides: 5)
                }
            }
            b.sphere(V3(0.56, 0.05, 0), 0.05, .glow, .low)
            b.sphere(V3(-0.5, 0.35, 0), 0.05, .glow, .low)
        case .petals:
            floatMotion = .orbit(speed: 1.1)
            floatAnchor = V3(0, 1.05, 0)
            for i in 0..<8 {
                let a = Float(i) / 8 * 2 * .pi
                let p = V3(cos(a) * 0.5, sin(a * 3) * 0.1, sin(a) * 0.5)
                b.ellipsoid(p, V3(0.05, 0.015, 0.085), i % 2 == 0 ? .accent : .glow, rot: ry(-a) * rz(0.6), detail: .low)
            }
        case .hourglass:
            floatMotion = .hover(speed: 0.6)
            floatAnchor = V3(0.55, 1.72, 0.05)
            let k: Float = 1.6
            b.rod(V3(0, -0.13, 0) * k, V3(0, -0.11, 0) * k, 0.08 * k, .metal, segments: 12)
            b.rod(V3(0, 0.11, 0) * k, V3(0, 0.13, 0) * k, 0.08 * k, .metal, segments: 12)
            b.lathe([V2(0.065, -0.11), V2(0.06, -0.05), V2(0.015, 0.0), V2(0.06, 0.05), V2(0.065, 0.11)].map { $0 * k }, .zero,
                    .veil, segments: 14)
            b.cone(V3(0, -0.11, 0) * k, V3(0, -0.02, 0) * k, 0.05 * k, .glow, segments: 10)
            b.cone(V3(0, 0.02, 0) * k, V3(0, 0.07, 0) * k, 0.02 * k, .glow, segments: 8)
            for i in 0..<3 {
                let a = Float(i) / 3 * 2 * .pi
                b.rod(V3(cos(a) * 0.075, -0.12, sin(a) * 0.075) * k, V3(cos(a) * 0.075, 0.12, sin(a) * 0.075) * k, 0.012, .metal)
            }
        case .clawCrystals:
            floatMotion = .orbit(speed: 1.3)
            floatAnchor = V3(0, 1.15, 0)
            let shape: [V2] = [V2(-0.02, 0), V2(0.03, 0), V2(0.08, 0.13), V2(0.14, 0.3), V2(0.05, 0.2), V2(0.0, 0.1)]
            for i in 0..<3 {
                let a = Float(i) / 3 * 2 * .pi
                let p = V3(cos(a) * 0.52, Float(i) * 0.06, sin(a) * 0.52)
                b.extrude(shape, depth: 0.025, p, .accent, rot: ry(-a) * rz(-0.4))
                b.sphere(p, 0.03, .glow, .low)
            }
        case .thunderOrb:
            floatMotion = .hover(speed: 1.0)
            floatAnchor = V3(-0.48, 1.62, 0.05)
            b.sphere(.zero, 0.09, .glow)
            b.torus(.zero, 0.14, 0.01, .accent, rot: rz(0.6), segments: 18, sides: 5)
            b.torus(.zero, 0.14, 0.01, .accent, rot: rz(-0.6) * rx(0.5), segments: 18, sides: 5)
            for i in 0..<4 {
                let a = Float(i) / 4 * 2 * .pi
                b.cone(V3(cos(a) * 0.08, 0, sin(a) * 0.08), V3(cos(a) * 0.17, 0.04, sin(a) * 0.17), 0.02, .glow, segments: 5)
            }
        case .dreamThreads:
            floatMotion = .orbit(speed: 0.8)
            floatAnchor = V3(0, 1.1, 0)
            b.torus(.zero, 0.56, 0.008, .glow, rot: rx(0.35), segments: 36, sides: 4)
            b.torus(V3(0, 0.15, 0), 0.5, 0.008, .accent, rot: rz(-0.3), segments: 36, sides: 4)
            for i in 0..<3 {
                let a = Float(i) / 3 * 2 * .pi
                let p = rx(0.35).act(V3(cos(a) * 0.56, 0, sin(a) * 0.56))
                b.extrude(starPolygon(points: 5, outer: 0.05, inner: 0.022), depth: 0.02, p, .glow, rot: ry(-a))
            }
        case .starMotes:
            floatMotion = .orbit(speed: 1.0)
            floatAnchor = V3(0, 1.2, 0)
            for i in 0..<4 {
                let a = Float(i) / 4 * 2 * .pi
                let p = V3(cos(a) * 0.5, sin(a * 2) * 0.12, sin(a) * 0.5)
                b.extrude(starPolygon(points: 5, outer: 0.055, inner: 0.024), depth: 0.02, p, .glow, rot: ry(-a))
            }
        case .sparkOrbs:
            floatMotion = .orbit(speed: 1.5)
            floatAnchor = V3(0, 1.2, 0)
            for i in 0..<3 {
                let a = Float(i) / 3 * 2 * .pi
                let p = V3(cos(a) * 0.5, Float(i) * 0.1 - 0.05, sin(a) * 0.5)
                b.sphere(p, 0.055, .glow, .low)
                b.torus(p, 0.085, 0.008, .accent, rot: rz(0.5 + Float(i)), segments: 14, sides: 4)
                for k in 0..<3 {
                    let ka = Float(k) / 3 * 2 * .pi + a
                    b.cone(p + V3(cos(ka) * 0.05, 0, sin(ka) * 0.05), p + V3(cos(ka) * 0.12, 0.03, sin(ka) * 0.12), 0.014, .glow,
                           segments: 4)
                }
            }
        case .iceCrystals:
            floatMotion = .orbit(speed: 0.9)
            floatAnchor = V3(0, 1.1, 0)
            for i in 0..<5 {
                let a = Float(i) / 5 * 2 * .pi
                let p = V3(cos(a) * 0.55, sin(a * 2) * 0.14 + 0.05, sin(a) * 0.55)
                let rot = ry(-a) * rz(0.35)
                b.crystal(p, radius: 0.055, height: 0.2, .veil, rot: rot, sides: 6, bottom: 0.8)
                b.crystal(p, radius: 0.026, height: 0.15, .glow, rot: rot, sides: 6, bottom: 0.8)
            }
            for k in 0..<2 {
                let a = Float(k) * .pi + 0.4
                b.extrude(starPolygon(points: 6, outer: 0.07, inner: 0.03), depth: 0.014,
                          V3(cos(a) * 0.5, 0.2 + Float(k) * 0.1, sin(a) * 0.5), .glow, rot: ry(-a))
            }
        }
        return b
    }
}

// MARK: - Prop の取り付け

extension HeroGearBuilder {
    /// Prop_<kind>.usdz（正規化済み: HeroPropTemplate の規約。面が ±Z の副手も正規化の yaw で上の weapon() / offhand() の
    /// 組み立て前の向きにしてある）を、ここの座標へ合わせる補正。
    /// yaw: 手続き側で組んだ後に掛けた残りの回転（盾の ry(0.4)・弓の ry(0.6)）。正規化の yaw とは別物で、両方掛けて正しい。
    /// center: 握りでなく範囲の中心を手続きの範囲の中心へ合わせる（腕の外に置く盾・本、握りと弦の間が原点になる弓）。
    /// turn: 予備。yaw を掛けずに正規化した Prop（薄い向き ±X・正面 +X）で横の広い向きが手続きと食い違う時だけ回す向き
    /// （+1 = ry(+90°) で +X → -Z = 正面を前へ、-1 = +X → +Z = 上面を +Z へ）。yaw 済みの Prop では広い向きが一致するので回さない。
    static func propMount(_ kind: String) -> (turn: Float, yaw: Float, center: Bool) {
        switch kind {
        case "\(OffhandKind.gateShield)": return (1, 0.4, true)  // 盾面 -Z、trs((-0.15, 0.1, -0.1), ry(0.4)) で腕の外へ
        case "\(OffhandKind.hideShield)": return (1, 0, true)    // 盾面 -Z、o = (-0.1, 0.08, -0.1)
        case "\(OffhandKind.harpBow)": return (1, 0, true)       // XY 平面、o = (-0.02, 0.2, -0.04)
        case "\(OffhandKind.grimoire)": return (1, 0, true)      // o = (-0.03, 0.06, -0.06)
        case "\(WeaponKind.mechCrossbow)": return (-1, 0, false) // 弓は ±X、上面 +Z
        // bow() は YZ 平面・握りが原点で弓先と弦が +Z、ry(0.6)。Prop は握りの断面に弦が入り原点が握りと弦の間になるので中心で合わせる
        case "\(OffhandKind.ashBow)", "\(OffhandKind.lightBow)": return (1, 0.6, true)
        default: return (1, 0, false)
        }
    }
}
