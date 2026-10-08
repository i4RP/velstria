import Foundation
import RealityKit
import simd

// 担当: hero-models。設計図から骨ごとのメッシュ（体・頭部）を組み立てる。
// 座標: 足元が原点、正面 -Z、右手 +X。各骨のメッシュは骨の回転中心を原点に作る。

/// 体型の寸法（m）。二頭身寄りのちびキャラ体型。
struct BodyMetrics {
    var hipY: Float = 0.56
    var thigh: Float = 0.28
    var shin: Float = 0.28
    var legR: Float = 0.085
    var hipHalf: Float = 0.11
    var torsoLen: Float = 0.46
    var torsoW: Float = 0.46
    var torsoD: Float = 0.32
    var shoulderX: Float = 0.27
    var shoulderY: Float = 0.38
    var upperArm: Float = 0.21
    var foreArm: Float = 0.19
    var armR: Float = 0.062
    var headR: Float = 0.33
    var headY: Float = 0.29
    /// 待機時の腕の開き（胴に埋まらない角度）。
    var armRestOut: Float = 0.12

    static func make(_ build: BodyBuild) -> BodyMetrics {
        var m = BodyMetrics()
        switch build {
        case .heavy:
            m.torsoW = 0.62; m.torsoD = 0.44; m.torsoLen = 0.48; m.shoulderX = 0.35; m.shoulderY = 0.39
            m.armR = 0.085; m.legR = 0.1; m.hipHalf = 0.13; m.headR = 0.31; m.headY = 0.28
            m.upperArm = 0.22; m.foreArm = 0.2; m.armRestOut = 0.2
        case .standard:
            break
        case .slim:
            m.torsoW = 0.40; m.torsoD = 0.28; m.torsoLen = 0.44; m.shoulderX = 0.235; m.shoulderY = 0.36
            m.armR = 0.055; m.legR = 0.075; m.hipHalf = 0.1; m.headR = 0.335
        case .robed:
            m.torsoW = 0.44; m.torsoD = 0.31; m.shoulderX = 0.26; m.armR = 0.06; m.legR = 0.08
        }
        return m
    }

    /// 頭頂の高さ（足元基準、拡縮前）。
    var headTop: Float { hipY + 0.03 + torsoLen + headY + headR }
}

/// 1 ヒーロー分の骨メッシュ一式（ヒーロー ID ごとに共有）。
struct HeroMeshSet {
    var hips: MeshResource
    var torso: MeshResource
    var head: MeshResource
    var upperArmL: MeshResource
    var upperArmR: MeshResource
    var foreArmL: MeshResource
    var foreArmR: MeshResource
    var thighL: MeshResource
    var thighR: MeshResource
    var shinL: MeshResource
    var shinR: MeshResource
    var weapon: MeshResource?
    var offhand: MeshResource?
    var back: MeshResource?
    var wingL: MeshResource?
    var wingR: MeshResource?
    var flag: MeshResource?
    var float: MeshResource?
    var metrics: BodyMetrics
    /// 武器先端（武器ローカル）。詠唱の光を置く。
    var weaponTip: V3
    /// 副手の先端（副手ローカル、HeroGearBuilder.offhandTip）。nil = 盾・本など先端を使わない副手。
    var offhandTip: V3?
    /// 旗の取り付け位置（武器ローカル）。
    var flagAnchor: V3
    var floatMotion: FloatMotion
    var floatAnchor: V3
    var backAnchor: V3
    var wingAnchor: V3
    var triangleCount: Int
}

/// 浮遊物の動き方。
enum FloatMotion {
    case none
    /// 体のまわりを周回（motion 基準）。
    case orbit(speed: Float)
    /// 頭の後ろで面内回転（胴基準の光輪）。
    case halo(speed: Float)
    /// 肩の上で漂う（motion 基準）。
    case hover(speed: Float)
}

@MainActor
struct HeroAssembler {
    let bp: HeroBlueprint
    let m: BodyMetrics
    private var tris = 0

    init(blueprint: HeroBlueprint) {
        bp = blueprint
        m = BodyMetrics.make(blueprint.build)
    }

    private static let fallbackMesh = MeshResource.generateBox(size: 0.001)

    private mutating func finish(_ b: HeroMeshBuilder, _ name: String) -> MeshResource {
        tris += b.triangleCount
        return b.makeAtlasMesh(name: name, glowingEyes: bp.glowingEyes) ?? Self.fallbackMesh
    }

    private mutating func finishOptional(_ b: HeroMeshBuilder, _ name: String) -> MeshResource? {
        guard !b.isEmpty else { return nil }
        tris += b.triangleCount
        return b.makeAtlasMesh(name: name, glowingEyes: bp.glowingEyes)
    }

    mutating func build(name: String) -> HeroMeshSet {
        let hips = finish(buildHips(), "\(name).hips")
        let torso = finish(buildTorso(), "\(name).torso")
        let head = finish(buildHead(), "\(name).head")
        let uaL = finish(buildUpperArm(side: -1), "\(name).upperArmL")
        let uaR = finish(buildUpperArm(side: 1), "\(name).upperArmR")
        let faL = finish(buildForeArm(side: -1), "\(name).foreArmL")
        let faR = finish(buildForeArm(side: 1), "\(name).foreArmR")
        let thL = finish(buildThigh(side: -1), "\(name).thighL")
        let thR = finish(buildThigh(side: 1), "\(name).thighR")
        let shL = finish(buildShin(side: -1), "\(name).shinL")
        let shR = finish(buildShin(side: 1), "\(name).shinR")
        var gear = HeroGearBuilder(bp: bp, m: m)
        let weapon = finishOptional(gear.weapon(), "\(name).weapon")
        let offhand = finishOptional(gear.offhand(), "\(name).offhand")
        let back = finishOptional(gear.back(), "\(name).back")
        let wingL = finishOptional(gear.wing(side: -1), "\(name).wingL")
        let wingR = finishOptional(gear.wing(side: 1), "\(name).wingR")
        let flag = finishOptional(gear.flag(), "\(name).flag")
        let float = finishOptional(gear.floating(), "\(name).float")
        return HeroMeshSet(
            hips: hips, torso: torso, head: head, upperArmL: uaL, upperArmR: uaR, foreArmL: faL, foreArmR: faR,
            thighL: thL, thighR: thR, shinL: shL, shinR: shR, weapon: weapon, offhand: offhand, back: back,
            wingL: wingL, wingR: wingR, flag: flag, float: float, metrics: m, weaponTip: gear.weaponTip,
            offhandTip: HeroGearBuilder.offhandTip(bp.offhand),
            flagAnchor: gear.flagAnchor, floatMotion: gear.floatMotion, floatAnchor: gear.floatAnchor,
            backAnchor: V3(0, m.torsoLen * 0.84, m.torsoD * 0.42), wingAnchor: V3(0, m.torsoLen * 0.8, m.torsoD * 0.5),
            triangleCount: tris)
    }

    // MARK: 素材の割り当て

    private var pantsMat: HeroMat {
        switch bp.armor {
        case .cloth, .light: return .dark
        case .fur, .rock: return .secondary
        default: return .dark
        }
    }

    private var bootMat: HeroMat { bp.armor == .plate ? .metal : .dark }

    private var sleeveMat: HeroMat {
        switch bp.armor {
        case .plate: return .metal
        case .leather, .mech: return .secondary
        case .cloth, .light: return .primary
        case .rock, .fur: return .skin
        }
    }

    private var foreArmMat: HeroMat {
        switch bp.armor {
        case .plate: return .metal
        case .cloth: return .primary
        default: return .skin
        }
    }

    private var handMat: HeroMat {
        switch bp.armor {
        case .plate: return .metal
        case .leather: return .dark
        default: return .skin
        }
    }

    // MARK: 腰

    private func buildHips() -> HeroMeshBuilder {
        var b = HeroMeshBuilder()
        let hw = m.torsoW / 2
        let zs = m.torsoD / m.torsoW
        b.rbox(V3(0, 0, 0), V3(m.torsoW * 0.8, 0.2, m.torsoD * 0.84), 0.08, pantsMat)
        let beltMat: HeroMat = bp.build == .heavy ? .metal : .dark
        b.rbox(V3(0, 0.085, 0), V3(m.torsoW * 0.88, 0.07, m.torsoD * 0.92), 0.03, beltMat)
        b.rbox(V3(0, 0.085, -m.torsoD * 0.46), V3(0.09, 0.075, 0.035), 0.012, bp.build == .heavy ? .glow : .metal)
        switch bp.skirt {
        case .none:
            break
        case .tassets:
            for s: Float in [-1, 1] {
                b.rbox(V3(s * 0.12, -0.07, -m.torsoD * 0.43), V3(0.17, 0.2, 0.04), 0.015, .primary, rot: rx(0.18))
                b.rbox(V3(s * hw * 0.86, -0.06, 0), V3(0.045, 0.2, 0.2), 0.015, .metal, rot: rz(s * 0.22))
            }
            b.rbox(V3(0, -0.07, m.torsoD * 0.43), V3(0.28, 0.18, 0.04), 0.015, .secondary, rot: rx(-0.15))
        case .robe:
            let yb = -(m.hipY - 0.1)
            let prof: [V2] = [V2(hw * 1.22, yb), V2(hw * 1.36, yb + 0.02), V2(hw * 1.3, yb * 0.72),
                              V2(hw * 1.12, yb * 0.36), V2(hw * 0.97, 0.0), V2(hw * 0.9, 0.12)]
            b.lathe(prof, V3(0, 0, 0), .primary, scale: V3(1, 1, zs * 1.15), segments: 20)
            b.add(MeshTemplate.torus(minor: 0.026 / (hw * 1.34), segments: 24, sides: 6),
                  trs(V3(0, yb + 0.03, 0), qIdentity, V3(hw * 1.34, hw * 1.34, hw * 1.34 * zs * 1.15)), .accent)
            // 前垂れ
            b.rbox(V3(0, yb * 0.45, -m.torsoD * 0.62), V3(0.15, -yb * 0.9, 0.03), 0.012, .secondary, rot: rx(-0.2))
        case .shortSkirt:
            b.lathe([V2(hw * 1.2, -0.17), V2(hw * 0.94, 0.06)], V3(0, 0, 0), .primary, scale: V3(1, 1, zs), segments: 18)
            b.add(MeshTemplate.torus(minor: 0.02 / (hw * 1.2), segments: 22, sides: 6),
                  trs(V3(0, -0.165, 0), qIdentity, V3(hw * 1.2, hw * 1.2, hw * 1.2 * zs)), .accent)
        case .coat:
            b.lathe([V2(hw * 1.14, -0.16), V2(hw * 0.94, 0.06)], V3(0, 0, 0), .primary, scale: V3(1, 1, zs), segments: 18)
            for s: Float in [-1, 1] {
                b.add(MeshTemplate.cloth(w0: 0.14, w1: 0.18, length: 0.36, curve: 0.08, bulge: 0.02, cols: 3, rows: 4),
                      trs(V3(s * 0.09, 0.0, m.torsoD * 0.44), rz(s * 0.08)), .primary)
            }
        case .loincloth:
            b.add(MeshTemplate.cloth(w0: 0.18, w1: 0.15, length: 0.3, curve: -0.04, bulge: 0.0, cols: 2, rows: 3),
                  trs(V3(0, 0.03, -m.torsoD * 0.47), ry(.pi)), .secondary)
            b.add(MeshTemplate.cloth(w0: 0.2, w1: 0.17, length: 0.28, curve: 0.05, bulge: 0.0, cols: 2, rows: 3),
                  trs(V3(0, 0.03, m.torsoD * 0.46)), .secondary)
        case .petals:
            for i in 0..<7 {
                let a = Float(i) / 7 * 2 * .pi
                let p = V3(sin(a) * hw * 0.95, -0.08, -cos(a) * hw * 0.95 * zs)
                b.ellipsoid(p, V3(0.085, 0.15, 0.03), i % 2 == 0 ? .primary : .accent, rot: ry(-a) * rx(-0.4), detail: .low)
            }
        case .kilt:
            b.lathe([V2(hw * 1.08, -0.13), V2(hw * 0.93, 0.06)], V3(0, 0, 0), .secondary, scale: V3(1, 1, zs), segments: 18)
            b.rbox(V3(0, -0.05, -m.torsoD * 0.47), V3(0.15, 0.22, 0.03), 0.012, .primary, rot: rx(0.1))
        }
        return b
    }

    // MARK: 胴

    private var torsoMat: HeroMat {
        switch bp.armor {
        case .plate: return .metal
        case .leather, .fur, .mech: return .secondary
        case .cloth, .light: return .primary
        case .rock: return .dark
        }
    }

    private func buildTorso() -> HeroMeshBuilder {
        var b = HeroMeshBuilder()
        let hw = m.torsoW / 2
        let zs = m.torsoD / m.torsoW
        let L = m.torsoLen
        let prof: [V2] = [V2(hw * 0.72, -0.05), V2(hw * 0.8, 0.05), V2(hw * 0.86, 0.15), V2(hw * 0.97, 0.27),
                          V2(hw * 1.0, 0.33), V2(hw * 0.9, 0.4), V2(hw * 0.55, L - 0.01), V2(hw * 0.2, L + 0.01),
                          V2(0, L + 0.015)]
        b.lathe(prof, .zero, torsoMat, scale: V3(1, 1, zs), segments: 18)
        let front = -m.torsoD * 0.5
        switch bp.armor {
        case .plate:
            b.ellipsoid(V3(0, 0.27, -m.torsoD * 0.1), V3(hw * 0.96, 0.2, m.torsoD * 0.45), .metal)
            b.rbox(V3(0, 0.06, front + 0.01), V3(hw * 0.85, 0.26, 0.03), 0.012, .primary)
            b.extrude([V2(0, 0.07), V2(0.05, 0), V2(0, -0.07), V2(-0.05, 0)], depth: 0.03,
                      V3(0, 0.28, front - 0.07), .glow)
            b.add(MeshTemplate.torus(minor: 0.1, segments: 20, sides: 6),
                  trs(V3(0, L - 0.03, 0), qIdentity, V3(hw * 0.6, hw * 0.6, hw * 0.6 * zs)), .metal)
        case .leather:
            b.rbox(V3(0, 0.22, 0), V3(0.06, 0.52, m.torsoD * 1.02), 0.02, .dark, rot: rz(0.62))
            b.rbox(V3(-0.05, 0.28, front - 0.005), V3(0.06, 0.06, 0.03), 0.01, .metal, rot: rz(0.62))
            b.add(MeshTemplate.torus(minor: 0.14, segments: 20, sides: 6),
                  trs(V3(0, L - 0.04, 0), qIdentity, V3(hw * 0.62, hw * 0.62, hw * 0.62 * zs)), .secondary)
        case .cloth:
            b.lathe([V2(hw * 0.62, L - 0.08), V2(hw * 0.66, L + 0.02), V2(hw * 0.5, L + 0.06)], .zero, .primary,
                    scale: V3(1, 1, zs), segments: 16)
            for s: Float in [-1, 1] {
                b.rbox(V3(s * 0.045, 0.2, front + 0.005), V3(0.035, 0.42, 0.025), 0.01, .accent, rot: rz(s * 0.12))
            }
            b.rbox(V3(0, 0.02, 0), V3(m.torsoW * 0.92, 0.07, m.torsoD * 0.95), 0.03, .secondary)
            b.crystal(V3(0, 0.3, front - 0.03), radius: 0.035, height: 0.06, .glow, rot: rx(-.pi / 2), sides: 4, bottom: 1)
        case .light:
            b.rbox(V3(0, 0.08, 0), V3(m.torsoW * 0.9, 0.14, m.torsoD * 0.96), 0.05, .dark)
            b.add(MeshTemplate.torus(minor: 0.12, segments: 20, sides: 6),
                  trs(V3(0, L - 0.035, 0), qIdentity, V3(hw * 0.62, hw * 0.62, hw * 0.62 * zs)), .accent)
            b.extrude(starPolygon(points: 4, outer: 0.06, inner: 0.022), depth: 0.02, V3(0, 0.28, front - 0.03), .glow)
        case .rock:
            b.rbox(V3(-0.1, 0.3, front + 0.06), V3(0.2, 0.17, 0.1), 0.04, .metal, rot: rz(0.2) * rx(0.2))
            b.rbox(V3(0.12, 0.26, front + 0.07), V3(0.18, 0.15, 0.09), 0.04, .metal, rot: rz(-0.25) * rx(0.15))
            b.crystal(V3(0.0, 0.18, front + 0.02), radius: 0.04, height: 0.09, .glow, rot: rx(-1.2))
            b.rbox(V3(0, 0.02, 0), V3(m.torsoW * 0.92, 0.08, m.torsoD * 0.95), 0.03, .accent)
        case .fur:
            b.add(MeshTemplate.torus(minor: 0.34, segments: 22, sides: 8),
                  trs(V3(0, L - 0.07, 0.02), qIdentity, V3(hw * 0.92, hw * 0.92, hw * 0.92 * zs)), .cloth)
            for i in 0..<6 {
                let a = Float(i) / 6 * 2 * .pi + 0.3
                let p = V3(sin(a) * hw * 0.95, L - 0.1, -cos(a) * hw * 0.95 * zs)
                b.ellipsoid(p, V3(0.09, 0.08, 0.09), .cloth, detail: .low)
            }
            for i in 0..<5 {
                let a = Float(i - 2) * 0.28
                b.cone(V3(sin(a) * hw * 0.62, L - 0.12, front * 0.9 + 0.03), V3(sin(a) * hw * 0.7, L - 0.22, front * 1.05),
                       0.022, .metal)
            }
            b.extrude([V2(0, 0.08), V2(0.07, -0.04), V2(-0.07, -0.04)], depth: 0.02, V3(0, 0.22, front - 0.02), .glow)
        case .mech:
            b.rbox(V3(0, 0.26, front + 0.05), V3(hw * 1.3, 0.24, 0.1), 0.04, .metal)
            b.rod(V3(0, 0.26, front - 0.005), V3(0, 0.26, front - 0.03), 0.055, .dark, segments: 14)
            b.rod(V3(0, 0.26, front - 0.02), V3(0, 0.26, front - 0.04), 0.038, .glow, segments: 14)
            b.rod(V3(-hw * 0.6, 0.12, front + 0.02), V3(-hw * 0.6, 0.38, front + 0.02), 0.014, .metal)
            b.rbox(V3(0, 0.03, 0), V3(m.torsoW * 0.92, 0.07, m.torsoD * 0.95), 0.03, .dark)
        }
        if bp.scarf {
            b.add(MeshTemplate.torus(minor: 0.3, segments: 20, sides: 8),
                  trs(V3(0, L - 0.02, 0), qIdentity, V3(hw * 0.62, hw * 0.62, hw * 0.62 * zs)), .accent)
            b.ellipsoid(V3(hw * 0.35, L - 0.2, m.torsoD * 0.45), V3(0.06, 0.16, 0.035), .accent, rot: rz(0.3) * rx(-0.3))
        }
        return b
    }

    // MARK: 腕

    private func buildUpperArm(side s: Float) -> HeroMeshBuilder {
        var b = HeroMeshBuilder()
        let r = m.armR
        if bp.mechArmLeft && s < 0 {
            b.sphere(V3(0, 0, 0), r * 1.6, .metal)
            b.rbox(V3(0, -m.upperArm * 0.5, 0), V3(r * 2.4, m.upperArm, r * 2.4), 0.03, .metal)
            b.rod(V3(s * r * 1.4, -0.02, -r * 0.8), V3(s * r * 1.4, -m.upperArm, -r * 0.8), 0.014, .dark)
            b.torus(V3(0, 0.02, 0), r * 1.5, 0.02, .dark, rot: rz(.pi / 2))
            b.sphere(V3(s * r * 1.55, 0.0, 0), 0.03, .glow, .low)
            return b
        }
        b.limb(V3(0, 0, 0), V3(0, -m.upperArm, 0), r * 1.08, r * 0.95, sleeveMat)
        b.sphere(V3(0, 0, 0), r * 1.3, sleeveMat)
        let tilt = rz(-s * 0.4)
        switch bp.pauldron {
        case .none:
            break
        case .small:
            b.dome(V3(s * 0.01, 0.015, 0), V3(r * 2.0, r * 1.5, r * 2.0), .primary, rot: rz(-s * 0.35))
        case .round:
            b.dome(V3(s * 0.012, 0.015, 0), V3(r * 2.4, r * 1.9, r * 2.3), .primary, rot: tilt)
            b.torus(V3(s * 0.012, 0.015, 0), r * 2.35, 0.016, .metal, rot: tilt)
        case .big:
            b.dome(V3(s * 0.035, -0.045, 0), V3(r * 2.3, r * 1.5, r * 2.1), .metal, rot: rz(-s * 0.65))
            b.dome(V3(s * 0.02, 0.02, 0), V3(r * 2.75, r * 2.2, r * 2.55), .primary, rot: rz(-s * 0.42))
            b.torus(V3(s * 0.02, 0.02, 0), r * 2.7, 0.02, .metal, rot: rz(-s * 0.42))
            b.sphere(V3(s * r * 1.25, r * 1.9 + 0.02, 0), 0.03, .glow, .low)
        case .rock:
            b.rbox(V3(s * 0.03, 0.06, 0), V3(r * 2.6, r * 1.3, r * 2.4), 0.035, .metal, rot: rz(-s * 0.35) * ry(0.3))
            b.rbox(V3(s * 0.08, -0.02, -0.03), V3(r * 1.4, r * 1.4, r * 1.5), 0.03, .metal, rot: rz(-s * 0.7))
            b.crystal(V3(s * 0.02, 0.12, 0.02), radius: 0.035, height: 0.11, .glow, rot: rz(-s * 0.3))
        case .fur:
            b.ellipsoid(V3(s * 0.02, 0.03, 0), V3(r * 2.5, r * 1.7, r * 2.5), .cloth)
            b.ellipsoid(V3(s * 0.09, -0.02, 0.03), V3(r * 1.3, r * 1.1, r * 1.3), .cloth, detail: .low)
        case .crystal:
            b.dome(V3(s * 0.01, 0.015, 0), V3(r * 2.1, r * 1.6, r * 2.1), .primary, rot: rz(-s * 0.35))
            b.crystal(V3(s * 0.04, 0.07, 0), radius: 0.03, height: 0.13, .accent, rot: rz(-s * 0.35))
            b.crystal(V3(s * 0.08, 0.03, 0.04), radius: 0.022, height: 0.08, .glow, rot: rz(-s * 0.8))
        case .feather:
            b.dome(V3(s * 0.01, 0.015, 0), V3(r * 2.0, r * 1.5, r * 2.0), .primary, rot: rz(-s * 0.35))
            for i in 0..<3 {
                let z = Float(i - 1) * 0.045
                b.ellipsoid(V3(s * 0.1, -0.03 - Float(i) * 0.01, z), V3(0.03, 0.1, 0.022), .accent,
                            rot: rz(-s * 0.5) * rx(Float(i - 1) * 0.3), detail: .low)
            }
        }
        return b
    }

    private func buildForeArm(side s: Float) -> HeroMeshBuilder {
        var b = HeroMeshBuilder()
        let r = m.armR
        let L = m.foreArm
        if bp.mechArmLeft && s < 0 {
            // 機巧の左腕: 大きな前腕と三本爪
            b.sphere(.zero, r * 1.3, .dark, .low)
            b.rbox(V3(0, -L * 0.55, 0), V3(r * 3.0, L * 1.1, r * 3.0), 0.035, .metal)
            b.rod(V3(0, -L * 0.55, -r * 1.5), V3(0, -L * 0.55, -r * 1.65), 0.035, .glow, segments: 12)
            b.rbox(V3(0, -L * 1.1, 0), V3(r * 2.2, 0.06, r * 2.2), 0.02, .dark)
            for i in 0..<3 {
                let a = Float(i) / 3 * 2 * .pi
                let base = V3(cos(a) * r * 0.8, -L * 1.12, sin(a) * r * 0.8)
                b.cone(base, base + V3(cos(a) * 0.035, -0.12, sin(a) * 0.035), 0.022, .metal)
            }
            return b
        }
        b.limb(.zero, V3(0, -L, 0), r * 0.95, r * 0.82, foreArmMat)
        switch bp.armor {
        case .plate:
            b.frustum(V3(0, -L * 0.25, 0), V3(0, -L * 0.95, 0), r * 1.12, r * 1.05, .metal)
            b.torus(V3(0, -L * 0.25, 0), r * 1.12, 0.014, .primary)
        case .leather, .light, .mech:
            b.frustum(V3(0, -L * 0.4, 0), V3(0, -L * 0.95, 0), r * 1.05, r * 1.0, .dark)
        case .cloth:
            b.frustum(V3(0, 0.02, 0), V3(0, -L * 0.8, 0), r * 1.1, r * 1.85, .primary, caps: false)
            b.add(MeshTemplate.torus(minor: 0.12, segments: 16, sides: 6),
                  trs(V3(0, -L * 0.8, 0), qIdentity, V3(r * 1.85, r * 1.85, r * 1.85)), .accent)
        case .rock:
            b.frustum(V3(0, -L * 0.3, 0), V3(0, -L * 0.95, 0), r * 1.15, r * 1.05, .metal)
        case .fur:
            b.frustum(V3(0, -L * 0.4, 0), V3(0, -L * 0.95, 0), r * 1.1, r * 1.0, .dark)
            b.torus(V3(0, -L * 0.4, 0), r * 1.15, 0.03, .cloth)
        }
        // 拳・爪は武器側で覆うので手は小さめ
        let covered = (s > 0 && bp.weaponFollowsArm) || (s < 0 && (bp.offhand == .stoneFist || bp.offhand == .azureClaw))
        b.sphere(V3(0, -L - 0.035, 0), r * (covered ? 1.0 : 1.2), handMat)
        return b
    }

    // MARK: 脚

    private func buildThigh(side s: Float) -> HeroMeshBuilder {
        var b = HeroMeshBuilder()
        b.limb(.zero, V3(0, -m.thigh, 0), m.legR, m.legR * 0.9, pantsMat)
        if bp.armor == .plate {
            b.rbox(V3(0, -m.thigh * 0.45, -m.legR * 0.55), V3(m.legR * 1.9, m.thigh * 0.6, m.legR * 0.9), 0.025, .metal)
        }
        return b
    }

    private func buildShin(side s: Float) -> HeroMeshBuilder {
        var b = HeroMeshBuilder()
        let r = m.legR
        let L = m.shin
        b.limb(.zero, V3(0, -(L - 0.1), 0), r * 0.9, r * 0.8, pantsMat)
        b.rbox(V3(0, -L + 0.07, -0.035), V3(r * 2.3, 0.14, r * 2.6 + 0.09), 0.05, bootMat)
        b.frustum(V3(0, -L + 0.12, 0), V3(0, -L + 0.25, 0), r * 1.02, r * 1.1, bootMat)
        b.torus(V3(0, -L + 0.25, 0), r * 1.1, 0.018, bp.armor == .plate ? .primary : .secondary)
        if bp.armor == .plate {
            b.sphere(V3(0, 0, -0.02), r * 1.05, .metal, .low)
            b.rbox(V3(0, -L + 0.09, -r * 1.35 - 0.04), V3(r * 1.9, 0.08, 0.06), 0.025, .primary)
        }
        return b
    }

    // MARK: 頭

    private var coversHair: Bool {
        bp.gear.contains { g in
            switch g {
            case .knightHelm, .hood, .deepHood, .hornHelm, .nightcap: return true
            default: return false
            }
        }
    }

    private func buildHead() -> HeroMeshBuilder {
        var b = HeroMeshBuilder()
        let R = m.headR
        let c = V3(0, m.headY, 0)
        b.sphere(c, R, .skin, .high)
        let masked = bp.gear.contains(.beastMask)
        if !masked {
            for s: Float in [-1, 1] { eye(&b, c, R, s) }
        }
        let mouthCovered = masked || bp.gear.contains(.mask) || bp.gear.contains(.beard)
        if !mouthCovered {
            // 小さな笑み（下向きの円弧）
            let dir = simd_normalize(V3(0, -0.36, -0.93))
            let rot = simd_quatf(from: V3(0, 0, -1), to: dir) * rx(.pi / 2) * ry(.pi * 0.2)
            b.torus(c + dir * (R * 0.985), R * 0.085, R * 0.016, .eye, rot: rot, segments: 8, sides: 4, arc: .pi * 0.6)
        }
        // 耳
        if !coversHair && !bp.gear.contains(.foxEars) {
            for s: Float in [-1, 1] {
                b.ellipsoid(c + V3(s * R * 0.97, -R * 0.08, 0.0), V3(R * 0.12, R * 0.18, R * 0.1), .skin,
                            rot: rz(s * 0.2), detail: .low)
            }
        }
        if !coversHair { hair(&b, c, R) }
        for g in bp.gear { headGear(&b, g, c, R) }
        return b
    }

    private func eye(_ b: inout HeroMeshBuilder, _ c: V3, _ R: Float, _ s: Float) {
        let yaw: Float = 0.34, pitch: Float = -0.06
        let dir = simd_normalize(V3(s * sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)))
        let rot = simd_quatf(from: V3(0, 0, -1), to: dir)
        let k = R / 0.33
        b.ellipsoid(c + dir * (R * 0.93), V3(0.056 * k, 0.08 * k, 0.04 * k), .eye, rot: rot, detail: .low)
        if !bp.glowingEyes {
            b.sphere(c + dir * (R * 0.99) + V3(-s * 0.012 * k, 0.03 * k, 0), 0.019 * k, .shine, .tiny)
        }
    }

    /// 前髪（額に沿って並べる）。
    private func bangs(_ b: inout HeroMeshBuilder, _ c: V3, _ R: Float, count: Int, spread: Float, size: Float) {
        for i in 0..<count {
            let t = count == 1 ? 0 : Float(i) / Float(count - 1) * 2 - 1
            let dir = simd_normalize(V3(t * spread, 0.62, -0.78))
            let rot = simd_quatf(from: V3(0, 0, -1), to: dir) * rz(-t * 0.35)
            b.ellipsoid(c + dir * (R * 0.99), V3(R * 0.21 * size, R * 0.34 * size, R * 0.13), .hair, rot: rot, detail: .low)
        }
    }

    private func hairCap(_ b: inout HeroMeshBuilder, _ c: V3, _ R: Float, grow: Float = 1) {
        b.ellipsoid(c + V3(0, R * 0.14, R * 0.16), V3(R * 1.08 * grow, R * 1.02 * grow, R * 1.06 * grow), .hair, detail: .high)
    }

    private func hair(_ b: inout HeroMeshBuilder, _ c: V3, _ R: Float) {
        switch bp.hair {
        case .none:
            break
        case .short:
            hairCap(&b, c, R)
            bangs(&b, c, R, count: 5, spread: 0.5, size: 1)
            for i in 0..<3 {
                let a = Float(i - 1) * 0.5
                let d = simd_normalize(V3(sin(a) * 0.8, 0.2, cos(a) * 0.9))
                b.cone(c + d * R * 0.9, c + d * R * 1.32 + V3(0, -0.04, 0), 0.08, .hair)
            }
        case .spiky:
            hairCap(&b, c, R)
            let dirs: [V3] = [V3(0, 1, 0.3), V3(0.6, 0.8, 0.3), V3(-0.6, 0.8, 0.3), V3(0.3, 0.6, 0.9), V3(-0.3, 0.6, 0.9),
                              V3(0.9, 0.3, 0.4), V3(-0.9, 0.3, 0.4), V3(0, 0.5, 1), V3(0.25, 0.9, -0.3), V3(-0.25, 0.9, -0.3)]
            for d0 in dirs {
                let d = simd_normalize(d0)
                b.cone(c + d * R * 0.85, c + d * R * 1.62, 0.1, .hair, segments: 7)
            }
            bangs(&b, c, R, count: 4, spread: 0.45, size: 0.9)
        case .long:
            hairCap(&b, c, R)
            bangs(&b, c, R, count: 5, spread: 0.5, size: 1)
            b.ellipsoid(c + V3(0, -R * 0.35, R * 0.55), V3(R * 0.98, R * 0.95, R * 0.45), .hair)
            b.ellipsoid(c + V3(0, -R * 1.2, R * 0.55), V3(R * 0.72, R * 0.55, R * 0.3), .hair)
            for s: Float in [-1, 1] {
                b.ellipsoid(c + V3(s * R * 0.86, -R * 0.55, -R * 0.2), V3(R * 0.2, R * 0.5, R * 0.22), .hair,
                            rot: rz(s * 0.1), detail: .low)
            }
        case .ponytail:
            hairCap(&b, c, R)
            bangs(&b, c, R, count: 5, spread: 0.5, size: 1)
            b.torus(c + V3(0, R * 0.62, R * 0.78), 0.05, 0.02, .accent, rot: rx(1.0))
            b.ellipsoid(c + V3(0, R * 0.45, R * 1.12), V3(0.1, 0.16, 0.1), .hair, rot: rx(-0.6))
            b.ellipsoid(c + V3(0, R * 0.0, R * 1.3), V3(0.09, 0.17, 0.09), .hair, rot: rx(-0.25))
            b.ellipsoid(c + V3(0, -R * 0.45, R * 1.32), V3(0.07, 0.15, 0.07), .hair, rot: rx(0.1))
        case .twinTails:
            hairCap(&b, c, R)
            bangs(&b, c, R, count: 5, spread: 0.5, size: 1)
            for s: Float in [-1, 1] {
                b.sphere(c + V3(s * R * 0.88, R * 0.42, R * 0.2), 0.05, .accent, .low)
                b.ellipsoid(c + V3(s * R * 1.12, -R * 0.1, R * 0.3), V3(0.1, 0.22, 0.1), .hair, rot: rz(s * 0.25))
                b.ellipsoid(c + V3(s * R * 1.25, -R * 0.75, R * 0.35), V3(0.08, 0.18, 0.08), .hair, rot: rz(s * 0.1))
            }
        case .bob:
            hairCap(&b, c, R, grow: 1.06)
            bangs(&b, c, R, count: 5, spread: 0.55, size: 1.05)
            for s: Float in [-1, 1] {
                b.ellipsoid(c + V3(s * R * 0.84, -R * 0.3, R * 0.05), V3(R * 0.32, R * 0.55, R * 0.62), .hair)
            }
        case .topknot:
            hairCap(&b, c, R)
            bangs(&b, c, R, count: 3, spread: 0.35, size: 0.9)
            b.sphere(c + V3(0, R * 1.08, R * 0.2), R * 0.3, .hair)
            b.torus(c + V3(0, R * 0.9, R * 0.18), R * 0.22, 0.02, .accent, rot: rx(0.2))
            b.ellipsoid(c + V3(0, R * 0.9, R * 0.55), V3(0.03, 0.12, 0.02), .accent, rot: rx(0.8))
        case .braids:
            hairCap(&b, c, R)
            bangs(&b, c, R, count: 5, spread: 0.5, size: 1)
            for s: Float in [-1, 1] {
                for i in 0..<4 {
                    let y = -R * 0.25 - Float(i) * 0.075
                    b.sphere(c + V3(s * R * 0.9, y, -R * 0.1 - Float(i) * 0.03), 0.055 - Float(i) * 0.005, .hair, .low)
                }
                b.sphere(c + V3(s * R * 0.9, -R * 0.25 - 0.33, -R * 0.1 - 0.13), 0.03, .accent, .low)
            }
        case .mohawk:
            for i in 0..<6 {
                let t = -0.5 + Float(i) * 0.36
                let d = V3(0, cos(t), -sin(t))
                b.ellipsoid(c + d * R * 1.02, V3(R * 0.1, R * 0.3, R * 0.2), .hair, rot: rx(t), detail: .low)
            }
        case .wild:
            hairCap(&b, c, R, grow: 1.04)
            bangs(&b, c, R, count: 5, spread: 0.55, size: 1.05)
            for i in 0..<9 {
                let a = Float(i) / 9 * 2 * .pi
                let d = simd_normalize(V3(sin(a), 0.25 + 0.3 * cos(a * 2), cos(a) * 0.8 + 0.35))
                b.cone(c + d * R * 0.9, c + d * R * 1.45 + V3(0, -0.08, 0.05), 0.09, .hair, segments: 7)
            }
        }
    }

    private func headGear(_ b: inout HeroMeshBuilder, _ g: HeadGear, _ c: V3, _ R: Float) {
        switch g {
        case .knightHelm:
            b.ellipsoid(c + V3(0, R * 0.16, R * 0.26), V3(R * 1.12, R * 1.08, R * 1.1), .metal, detail: .high)
            b.rbox(c + V3(0, R * 0.5, -R * 0.76), V3(R * 1.5, 0.07, 0.1), 0.03, .primary, rot: rx(-0.35))
            b.rbox(c + V3(0, R * 0.05, -R * 0.93), V3(0.05, R * 0.55, 0.05), 0.02, .metal)
            for s: Float in [-1, 1] {
                b.rbox(c + V3(s * R * 0.82, -R * 0.2, -R * 0.35), V3(0.07, R * 0.7, R * 0.6), 0.03, .metal, rot: ry(s * 0.35))
            }
            for i in 0..<7 {
                let t = -0.2 + Float(i) * 0.3
                let d = V3(0, cos(t), sin(t))
                let sz = 1.0 - Float(i) * 0.06
                b.ellipsoid(c + V3(0, R * 0.16, R * 0.26) + d * R * 1.12, V3(0.05, 0.12 * sz, 0.1), .accent, rot: rx(t), detail: .low)
            }
            b.sphere(c + V3(0, R * 0.5, -R * 0.86), 0.035, .glow, .low)
        case .hood, .deepHood:
            let deep = g == .deepHood
            let hc = c + V3(0, R * 0.14, R * (deep ? 0.18 : 0.26))
            b.ellipsoid(hc, V3(R * 1.16, R * 1.12, R * 1.15), .primary, detail: .high)
            b.cone(hc + V3(0, R * 0.55, R * 0.7), hc + V3(0, R * 0.2, R * 1.55), 0.12, .primary)
            b.add(MeshTemplate.torus(minor: 0.07, segments: 20, sides: 6, arc: .pi * 1.3),
                  trs(hc + V3(0, -R * 0.05, -R * 0.78), rx(-.pi / 2) * ry(.pi * 0.15), V3(R * 0.95, R * 0.95, R * 0.95)),
                  .secondary)
            // 肩に落ちる裾
            b.ellipsoid(c + V3(0, -R * 0.75, R * 0.35), V3(R * 1.05, R * 0.35, R * 0.8), .primary)
        case .mask:
            b.ellipsoid(c + V3(0, -R * 0.42, -R * 0.52), V3(R * 0.86, R * 0.36, R * 0.5), .dark)
        case .starPin:
            b.extrude(starPolygon(points: 5, outer: 0.09, inner: 0.04), depth: 0.03,
                      c + V3(R * 0.72, R * 0.58, -R * 0.35), .glow, rot: ry(-0.6))
        case .shellCrown:
            b.add(MeshTemplate.torus(minor: 0.08, segments: 22, sides: 6),
                  trs(c + V3(0, R * 0.62, R * 0.1), rx(-0.25), V3(R * 0.78, R * 0.78, R * 0.78)), .cloth)
            for i in 0..<5 {
                let a = Float(i - 2) * 0.42
                let p = c + V3(sin(a) * R * 0.78, R * 0.66, -cos(a) * R * 0.7 + R * 0.1)
                let h: Float = i == 2 ? 0.2 : 0.13
                b.cone(p, p + V3(sin(a) * 0.03, h, -cos(a) * 0.03), 0.04, i == 2 ? .accent : .cloth, segments: 8)
            }
            b.sphere(c + V3(0, R * 0.75, -R * 0.66), 0.035, .glow, .low)
        case .flameCrown:
            b.add(MeshTemplate.torus(minor: 0.1, segments: 22, sides: 6),
                  trs(c + V3(0, R * 0.66, R * 0.12), rx(-0.2), V3(R * 0.72, R * 0.72, R * 0.72)), .metal)
            for i in 0..<7 {
                let a = Float(i - 3) * 0.5
                let p = c + V3(sin(a) * R * 0.72, R * 0.72, -cos(a) * R * 0.66 + R * 0.12)
                let h: Float = 0.12 + (i == 3 ? 0.14 : (i % 2 == 0 ? 0.07 : 0.0))
                b.cone(p, p + V3(sin(a) * 0.02, h, -cos(a) * 0.02), 0.045, .glow, segments: 7)
            }
            b.crystal(c + V3(0, R * 0.75, -R * 0.62), radius: 0.035, height: 0.06, .accent, rot: rx(-.pi / 2), sides: 4, bottom: 1)
        case .goggles:
            b.add(MeshTemplate.torus(minor: 0.08, segments: 22, sides: 6),
                  trs(c + V3(0, R * 0.45, 0), rx(-0.25), V3(R * 1.0, R * 1.0, R * 1.0)), .dark)
            for s: Float in [-1, 1] {
                let p = c + V3(s * R * 0.32, R * 0.55, -R * 0.78)
                b.rod(p, p + V3(0, 0.03, -0.07), 0.07, .metal, segments: 12)
                b.rod(p + V3(0, 0.03, -0.07), p + V3(0, 0.035, -0.08), 0.055, .glow, segments: 12)
            }
        case .beastMask:
            let mc = c + V3(0, R * 0.08, -R * 0.42)
            b.ellipsoid(mc, V3(R * 0.95, R * 0.8, R * 0.7), .metal, detail: .high)
            b.ellipsoid(mc + V3(0, -R * 0.35, -R * 0.45), V3(R * 0.45, R * 0.3, R * 0.35), .metal)
            for s: Float in [-1, 1] {
                b.sphere(mc + V3(s * R * 0.35, R * 0.1, -R * 0.62), 0.045, .glow, .low)
                // 牙
                b.cone(mc + V3(s * R * 0.22, -R * 0.52, -R * 0.62), mc + V3(s * R * 0.2, -R * 0.85, -R * 0.66), 0.03, .cloth)
                // 角（外へ張り出して上へ反る）
                var p = c + V3(s * R * 0.75, R * 0.55, -R * 0.1)
                var r: Float = 0.075
                let steps: [V3] = [V3(s * 0.12, 0.05, 0), V3(s * 0.1, 0.1, 0.02), V3(s * 0.04, 0.12, 0.04), V3(-s * 0.01, 0.1, 0.05)]
                for st in steps {
                    let q = p + st
                    b.frustum(p, q, r, r * 0.72, .metal, segments: 8)
                    p = q
                    r *= 0.72
                }
                b.cone(p, p + V3(-s * 0.02, 0.07, 0.03), r, .metal, segments: 8)
            }
            b.extrude([V2(0, 0.06), V2(0.04, 0), V2(0, -0.06), V2(-0.04, 0)], depth: 0.02, mc + V3(0, R * 0.52, -R * 0.64), .glow)
        case .hornHelm:
            let hc = c + V3(0, R * 0.16, R * 0.22)
            b.ellipsoid(hc, V3(R * 1.13, R * 1.08, R * 1.12), .metal, detail: .high)
            b.rbox(c + V3(0, R * 0.42, -R * 0.82), V3(R * 1.4, 0.08, 0.1), 0.03, .primary, rot: rx(-0.3))
            b.rbox(c + V3(0, R * 0.05, -R * 0.92), V3(0.06, R * 0.5, 0.05), 0.02, .metal)
            for s: Float in [-1, 1] {
                var p = hc + V3(s * R * 0.95, R * 0.35, -R * 0.1)
                var r: Float = 0.085
                let steps: [V3] = [V3(s * 0.14, 0.02, -0.02), V3(s * 0.1, 0.1, -0.05), V3(s * 0.02, 0.12, -0.08)]
                for st in steps {
                    let q = p + st
                    b.frustum(p, q, r, r * 0.7, .cloth, segments: 8)
                    p = q
                    r *= 0.7
                }
                b.cone(p, p + V3(-s * 0.02, 0.08, -0.06), r, .cloth, segments: 8)
                b.torus(hc + V3(s * R * 1.0, R * 0.35, -R * 0.1), 0.075, 0.018, .accent, rot: rz(.pi / 2))
            }
            b.sphere(hc + V3(0, R * 1.08, 0), 0.05, .glow, .low)
        case .vikingHelm:
            let hc = c + V3(0, R * 0.2, R * 0.22)
            b.dome(hc + V3(0, R * 0.05, 0), V3(R * 1.12, R * 1.02, R * 1.12), .metal)
            b.add(MeshTemplate.torus(minor: 0.06, segments: 22, sides: 6),
                  trs(hc + V3(0, R * 0.08, 0), qIdentity, V3(R * 1.12, R * 1.12, R * 1.12)), .accent)
            b.rbox(c + V3(0, R * 0.1, -R * 0.93), V3(0.05, R * 0.55, 0.05), 0.02, .metal)
            for s: Float in [-1, 1] {
                let p = hc + V3(s * R * 1.0, R * 0.35, 0)
                b.cone(p, p + V3(s * 0.12, 0.2, -0.02), 0.06, .cloth, segments: 8)
            }
        case .wideHat:
            let hc = c + V3(0, R * 0.7, R * 0.05)
            b.lathe([V2(R * 1.75, -0.02), V2(R * 1.8, 0.0), V2(R * 1.2, 0.03), V2(R * 0.7, 0.05)], hc, .secondary,
                    rot: rx(-0.12), segments: 24, capBottom: true)
            b.lathe([V2(R * 0.72, 0.0), V2(R * 0.66, R * 0.55), V2(R * 0.45, R * 0.72), V2(0, R * 0.75)], hc, .secondary,
                    rot: rx(-0.12), segments: 18)
            b.add(MeshTemplate.torus(minor: 0.07, segments: 20, sides: 6),
                  trs(hc + V3(0, 0.05, 0), rx(-0.12), V3(R * 0.71, R * 0.71, R * 0.71)), .accent)
            b.ellipsoid(hc + V3(R * 0.55, R * 0.4, R * 0.3), V3(0.025, 0.16, 0.05), .glow, rot: rz(-0.6) * rx(0.5), detail: .low)
            hairCap(&b, c, R, grow: 0.98)
        case .foxEars:
            for s: Float in [-1, 1] {
                let base = c + V3(s * R * 0.58, R * 0.72, R * 0.1)
                b.cone(base, base + V3(s * 0.08, 0.26, 0.02), 0.11, .hair, segments: 8)
                b.cone(base + V3(0, 0.02, -0.03), base + V3(s * 0.07, 0.2, -0.02), 0.065, .accent, segments: 8)
            }
        case .wingedHelm:
            let hc = c + V3(0, R * 0.25, R * 0.18)
            b.dome(hc, V3(R * 1.1, R * 0.95, R * 1.12), .metal)
            b.rbox(c + V3(0, R * 0.38, -R * 0.84), V3(R * 1.2, 0.06, 0.08), 0.025, .metal, rot: rx(-0.3))
            for s: Float in [-1, 1] {
                for i in 0..<3 {
                    let p = hc + V3(s * R * 1.02, R * 0.25 + Float(i) * 0.04, Float(i) * 0.05)
                    b.ellipsoid(p + V3(s * 0.06, 0.1, 0.05), V3(0.025, 0.16 - Float(i) * 0.03, 0.06), .cloth,
                                rot: rz(-s * (0.5 + Float(i) * 0.25)) * rx(0.4), detail: .low)
                }
            }
            b.crystal(hc + V3(0, R * 0.95, -R * 0.2), radius: 0.03, height: 0.08, .glow)
        case .nightcap:
            let hc = c + V3(0, R * 0.2, R * 0.18)
            b.ellipsoid(hc, V3(R * 1.12, R * 1.0, R * 1.12), .primary, detail: .high)
            // 垂れた三角帽
            var p = hc + V3(0, R * 0.7, R * 0.2)
            var r: Float = 0.16
            let steps: [V3] = [V3(0.02, 0.14, 0.06), V3(0.05, 0.08, 0.1), V3(0.06, -0.02, 0.1), V3(0.04, -0.08, 0.06)]
            for st in steps {
                let q = p + st
                b.frustum(p, q, r, r * 0.66, .primary, segments: 10)
                p = q
                r *= 0.66
            }
            b.extrude(starPolygon(points: 5, outer: 0.07, inner: 0.032), depth: 0.035, p + V3(0, -0.03, 0), .glow)
            b.add(MeshTemplate.torus(minor: 0.12, segments: 20, sides: 6),
                  trs(hc + V3(0, -R * 0.05, 0), rx(-0.35), V3(R * 1.06, R * 1.06, R * 1.06)), .cloth)
            bangs(&b, c, R, count: 4, spread: 0.45, size: 0.9)
        case .flowerCrown:
            for i in 0..<6 {
                let a = Float(i) / 6 * 2 * .pi
                let p = c + V3(sin(a) * R * 0.78, R * 0.6 + 0.04 * cos(a), -cos(a) * R * 0.78 + R * 0.12)
                for k in 0..<4 {
                    let pa = Float(k) / 4 * 2 * .pi + Float(i)
                    b.ellipsoid(p + V3(cos(pa) * 0.036, 0.012, sin(pa) * 0.036), V3(0.038, 0.013, 0.025),
                                i % 2 == 0 ? .accent : .cloth, rot: ry(-pa), detail: .tiny)
                }
                b.sphere(p + V3(0, 0.02, 0), 0.02, .glow, .tiny)
            }
        case .circlet:
            b.add(MeshTemplate.torus(minor: 0.05, segments: 24, sides: 6),
                  trs(c + V3(0, R * 0.42, R * 0.05), rx(-0.3), V3(R * 1.01, R * 1.01, R * 1.01)), .metal)
            b.crystal(c + V3(0, R * 0.58, -R * 0.9), radius: 0.03, height: 0.07, .glow, rot: rx(-0.3), sides: 4, bottom: 0.6)
        case .featherPin:
            for i in 0..<2 {
                let p = c + V3(R * 0.78, R * 0.55 + Float(i) * 0.02, R * 0.1 + Float(i) * 0.08)
                b.ellipsoid(p + V3(0.05, 0.1, 0.02), V3(0.03, 0.16, 0.012), .accent, rot: rz(-0.5 - Float(i) * 0.3) * rx(0.3), detail: .low)
            }
            b.sphere(c + V3(R * 0.78, R * 0.55, R * 0.1), 0.03, .glow, .low)
        case .glassVisor:
            b.add(MeshTemplate.torus(minor: 0.12, segments: 22, sides: 6, arc: .pi * 0.9),
                  trs(c + V3(0, R * 0.02, 0), ry(.pi * 0.95), V3(R * 1.04, R * 1.04, R * 1.04)), .veil)
            b.add(MeshTemplate.torus(minor: 0.03, segments: 22, sides: 5, arc: .pi * 0.8),
                  trs(c + V3(0, R * 0.02, 0), ry(.pi * 0.9), V3(R * 1.12, R * 1.12, R * 1.12)), .glow)
            b.crystal(c + V3(R * 0.6, R * 0.62, -R * 0.3), radius: 0.03, height: 0.1, .accent, rot: rz(-0.5))
        case .ironVisor:
            let hc = c + V3(0, R * 0.22, R * 0.2)
            b.dome(hc, V3(R * 1.1, R * 0.92, R * 1.1), .metal)
            b.rbox(c + V3(0, R * 0.4, -R * 0.82), V3(R * 1.25, 0.07, 0.09), 0.025, .metal, rot: rx(-0.3))
            b.rbox(hc + V3(0, R * 0.85, R * 0.1), V3(0.05, 0.12, R * 1.2), 0.02, .accent)
            b.sphere(c + V3(0, R * 0.42, -R * 0.9), 0.03, .glow, .low)
        case .headband:
            b.add(MeshTemplate.torus(minor: 0.08, segments: 22, sides: 6),
                  trs(c + V3(0, R * 0.4, R * 0.02), rx(-0.2), V3(R * 1.0, R * 1.0, R * 1.0)), .accent)
            b.ellipsoid(c + V3(R * 0.1, R * 0.2, R * 1.05), V3(0.03, 0.12, 0.02), .accent, rot: rx(-0.4) * rz(0.3), detail: .low)
            b.crystal(c + V3(0, R * 0.5, -R * 0.93), radius: 0.03, height: 0.05, .glow, rot: rx(-.pi / 2), sides: 4, bottom: 1)
        case .beard:
            b.ellipsoid(c + V3(0, -R * 0.62, -R * 0.52), V3(R * 0.62, R * 0.42, R * 0.4), .hair)
            b.ellipsoid(c + V3(0, -R * 0.3, -R * 0.86), V3(R * 0.4, R * 0.1, R * 0.12), .hair, detail: .low)
        case .crescentPin:
            b.extrude(crescentPolygon(radius: 0.07, thickness: 0.03, span: 4.0, offset: 0.025), depth: 0.02,
                      c + V3(-R * 0.72, R * 0.6, -R * 0.38), .glow, rot: ry(0.6) * rz(0.5))
        case .ribbon:
            let p = c + V3(-R * 0.55, R * 0.72, R * 0.35)
            for s: Float in [-1, 1] {
                b.ellipsoid(p + V3(s * 0.06, 0, 0), V3(0.065, 0.045, 0.025), .accent, rot: rz(s * 0.4) * ry(0.4), detail: .low)
            }
            b.sphere(p, 0.025, .glow, .low)
        case .iceCrown:
            b.add(MeshTemplate.torus(minor: 0.08, segments: 22, sides: 6),
                  trs(c + V3(0, R * 0.64, R * 0.1), rx(-0.2), V3(R * 0.74, R * 0.74, R * 0.74)), .metal)
            for i in 0..<5 {
                let a = Float(i - 2) * 0.5
                let p = c + V3(sin(a) * R * 0.74, R * 0.7, -cos(a) * R * 0.68 + R * 0.1)
                let h: Float = i == 2 ? 0.26 : (i % 2 == 0 ? 0.2 : 0.14)
                b.crystal(p + V3(0, h * 0.5, 0), radius: 0.034, height: h * 0.5, i == 2 ? .glow : .veil, sides: 5, bottom: 1)
            }
            b.crystal(c + V3(0, R * 0.78, -R * 0.62), radius: 0.035, height: 0.07, .accent, rot: rx(-.pi / 2), sides: 4, bottom: 1)
        }
    }
}
