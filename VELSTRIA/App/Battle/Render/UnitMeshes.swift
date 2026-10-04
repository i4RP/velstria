import Foundation
import RealityKit
import simd
import VelstriaCore

// 担当: battle-renderer。ミニオン・モンスター・人形・構造物・共通 UI 形状のメッシュ（1 度だけ生成して共有）。
// すべて正面 -Z、足元が原点。チーム色はパレットのチーム用スウォッチで作り分ける（チーム毎に別メッシュ）。

/// 胴体（静的）と攻撃で動く部位（武器・腕）。
struct PartMeshes {
    var body: MeshResource?
    var bodyGlow: MeshResource?
    var part: MeshResource?
    var partGlow: MeshResource?
    /// 部位の回転軸の位置（胴体ローカル）。
    var partPivot: SIMD3<Float> = .zero
    /// 左右対の部位（ゴーレムの腕）。
    var mirrorPart = false
}

@MainActor
final class UnitMeshLibrary {
    private var minionCache: [Int: PartMeshes] = [:]
    private var monsterCache: [Int: PartMeshes] = [:]
    private var ringCache: [Int: MeshResource] = [:]
    private var discCache: [Int: MeshResource] = [:]
    private var sectorCache: [Int: MeshResource] = [:]

    /// 左端原点・+Z 向きの単位四角形（HP バー）。
    lazy var barQuad: MeshResource? = {
        var d = MeshDescriptor(name: "barQuad")
        d.positions = MeshBuffers.Positions([[0, -0.5, 0], [1, -0.5, 0], [1, 0.5, 0], [0, 0.5, 0]])
        d.normals = MeshBuffers.Normals([[0, 0, 1], [0, 0, 1], [0, 0, 1], [0, 0, 1]])
        d.textureCoordinates = MeshBuffers.TextureCoordinates([[0, 0], [1, 0], [1, 1], [0, 1]])
        d.primitives = .triangles([0, 1, 2, 0, 2, 3])
        return try? MeshResource.generate(from: [d])
    }()

    /// 中心原点・+Z 向きの単位四角形。
    lazy var centeredQuad: MeshResource? = {
        var d = MeshDescriptor(name: "centeredQuad")
        d.positions = MeshBuffers.Positions([[-0.5, -0.5, 0], [0.5, -0.5, 0], [0.5, 0.5, 0], [-0.5, 0.5, 0]])
        d.normals = MeshBuffers.Normals([[0, 0, 1], [0, 0, 1], [0, 0, 1], [0, 0, 1]])
        d.textureCoordinates = MeshBuffers.TextureCoordinates([[0, 0], [1, 0], [1, 1], [0, 1]])
        d.primitives = .triangles([0, 1, 2, 0, 2, 3])
        return try? MeshResource.generate(from: [d])
    }()

    /// 地面に置く上向きの単位矩形（x: 0〜1、z: -0.5〜0.5。+x 方向へ伸ばす）。
    lazy var groundStrip: MeshResource? = {
        var b = MeshBuilder()
        b.flatRect(width: 1, depth: 1, color: .solid(.white), transform: MX.t(0.5, 0, 0))
        return b.makeMesh(name: "groundStrip")
    }()

    /// 上向きの三角形（矢印の先端、+x 方向）。
    lazy var arrowHead: MeshResource? = {
        var b = MeshBuilder()
        let uv = PaletteLayout.uv(.white)
        b.triangle([0, 0, 0.5], [1, 0, 0], [0, 0, -0.5], uv: uv)
        return b.makeMesh(name: "arrowHead")
    }()

    lazy var unitSphere: MeshResource = MeshResource.generateSphere(radius: 1)

    /// 気絶の星（3 つが円周上）。
    lazy var stunStars: MeshResource? = {
        var b = MeshBuilder()
        for k in 0..<3 {
            let a = Float(k) / 3 * 2 * .pi
            b.star(outer: 0.21, inner: 0.09, thickness: 0.06, color: .solid(.glowGold),
                   transform: MX.t(cos(a) * 0.46, 0, -sin(a) * 0.46) * MX.rx(.pi / 2) * MX.rz(a))
        }
        return b.makeMesh(name: "stunStars")
    }()

    /// 束縛の蔦（足元の棘付き輪）。
    lazy var rootVines: MeshResource? = {
        var b = MeshBuilder()
        b.torus(majorRadius: 0.55, minorRadius: 0.06, segments: 18, sides: 5, color: .solid(.glowGreen))
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi
            b.frustum(bottomRadius: 0.06, topRadius: 0, height: 0.32, segments: 4, color: .solid(.glowGreen),
                      transform: MX.t(cos(a) * 0.55, 0, -sin(a) * 0.55) * MX.rz(0.3 * (k % 2 == 0 ? 1 : -1)))
        }
        return b.makeMesh(name: "rootVines")
    }()

    /// 減速の氷の輪。
    /// 鈍足の輪の、メッシュ内での高さ。
    static let slowRingY: Float = 0.04

    lazy var slowRing: MeshResource? = {
        var b = MeshBuilder()
        b.annulus(inner: 0.5, outer: 0.62, segments: 28, y: UnitMeshLibrary.slowRingY, color: .solid(.glowBlueSoft))
        for k in 0..<6 {
            let a = Float(k) / 6 * 2 * .pi + 0.2
            b.crystal(radius: 0.05, height: 0.22, color: .solid(.glowBlueSoft),
                      transform: MX.t(cos(a) * 0.56, 0, -sin(a) * 0.56))
        }
        return b.makeMesh(name: "slowRing")
    }()

    // MARK: 地面の輪・円盤・扇形（半径 m を 0.05 m 単位で量子化してキャッシュ）

    func ring(radius: Float, thickness: Float) -> MeshResource? {
        let key = Int((radius * 20).rounded()) * 1000 + Int((thickness * 100).rounded())
        if let m = ringCache[key] { return m }
        var b = MeshBuilder()
        let r = max(0.05, Float(Int((radius * 20).rounded())) / 20)
        let segs = max(24, min(96, Int(r * 12)))
        b.annulus(inner: max(0, r - thickness), outer: r, segments: segs, color: .solid(.white))
        let m = b.makeMesh(name: "ring_\(key)")
        ringCache[key] = m
        return m
    }

    /// 単位円盤（半径 1、拡大して使う）。
    lazy var unitDisc: MeshResource? = {
        var b = MeshBuilder()
        b.annulus(inner: 0, outer: 1, segments: 48, color: .solid(.white))
        return b.makeMesh(name: "unitDisc")
    }()

    /// 扇形（中心から +x 方向を中心に ±halfAngle、半径 1）。outline = true で縁取りの弧帯。
    func sector(halfAngle: Float, outline: Bool, thicknessRatio: Float = 0.06) -> MeshResource? {
        let key = Int((halfAngle * 100).rounded()) * 10 + (outline ? 1 : 0)
        if let m = sectorCache[key] { return m }
        var b = MeshBuilder()
        let segs = max(8, Int(halfAngle * 24))
        // annulus は角度 a を (cos a, 0, -sin a) に置くので、+x を中心に -h〜+h
        if outline {
            b.annulus(inner: 1 - thicknessRatio, outer: 1, segments: segs, startAngle: -halfAngle, sweep: halfAngle * 2,
                      color: .solid(.white))
            for s in [-halfAngle, halfAngle] {
                let dir = SIMD3<Float>(cos(s), 0, -sin(s))
                let nrm = SIMD3<Float>(-dir.z, 0, dir.x) * (thicknessRatio / 2)
                let uv = PaletteLayout.uv(.white)
                b.quad(-nrm, dir - nrm, dir + nrm, nrm, uv: uv, uv, uv, uv)
                b.quad(nrm, dir + nrm, dir - nrm, -nrm, uv: uv, uv, uv, uv)
            }
        } else {
            b.annulus(inner: 0, outer: 1, segments: segs, startAngle: -halfAngle, sweep: halfAngle * 2, color: .solid(.white))
        }
        let m = b.makeMesh(name: "sector_\(key)")
        sectorCache[key] = m
        return m
    }

    // MARK: ミニオン

    func minion(_ type: MinionType, team: Team) -> PartMeshes {
        let key = type.rawValue * 4 + team.rawValue
        if let m = minionCache[key] { return m }
        let red = team == .red
        let main: Swatch = red ? .redMain : .blueMain
        let cloth: Swatch = red ? .redCloth : .blueCloth
        let dark: Swatch = red ? .redDark : .blueDark
        let glowS: Swatch = red ? .glowRed : .glowBlue
        var body = MeshBuilder(), bodyGlow = MeshBuilder(), part = MeshBuilder(), partGlow = MeshBuilder()
        var pivot = SIMD3<Float>.zero
        switch type {
        case .melee:
            for s: Float in [-1, 1] {
                body.box(size: [0.15, 0.36, 0.17], color: .solid(.leather), transform: MX.t(0.12 * s, 0, 0))
                body.box(size: [0.17, 0.08, 0.22], color: .solid(.metalDark), transform: MX.t(0.12 * s, 0, -0.03))
            }
            body.frustum(bottomRadius: 0.27, topRadius: 0.31, height: 0.44, segments: 6, color: .solid(cloth),
                         transform: MX.t(0, 0.34, 0) * MX.s(1, 1, 0.78))
            body.box(size: [0.44, 0.34, 0.1], color: .solid(.steel), transform: MX.t(0, 0.42, -0.2))
            body.box(size: [0.2, 0.08, 0.02], color: .solid(main), transform: MX.t(0, 0.62, -0.26))
            body.sphere(radius: 0.17, segments: 8, rings: 6, color: .solid(.skin), transform: MX.t(0, 0.93, 0))
            body.frustum(bottomRadius: 0.2, topRadius: 0.12, height: 0.2, segments: 7, color: .solid(.steel),
                         capTop: true, transform: MX.t(0, 0.93, 0))
            body.box(size: [0.28, 0.05, 0.05], color: .solid(.metalDark), transform: MX.t(0, 0.94, -0.17))
            bodyGlow.crystal(radius: 0.05, height: 0.24, color: .solid(glowS), transform: MX.t(0, 1.11, 0.02))
            // 盾（左腕）
            body.cylinder(radius: 0.27, height: 0.07, segments: 10, color: .solid(main),
                          transform: MX.t(-0.36, 0.52, -0.05) * MX.rz(.pi / 2))
            body.torus(majorRadius: 0.26, minorRadius: 0.035, segments: 14, sides: 4, color: .solid(.gold),
                       transform: MX.t(-0.405, 0.52, -0.05) * MX.rz(.pi / 2))
            body.sphere(radius: 0.06, segments: 6, rings: 4, color: .solid(.gold), transform: MX.t(-0.42, 0.52, -0.05))
            // 剣（右手）
            pivot = [0.33, 0.52, -0.05]
            part.box(size: [0.14, 0.12, 0.12], color: .solid(.skin), transform: MX.t(0, -0.06, 0))
            part.box(size: [0.05, 0.14, 0.05], color: .solid(.leather), transform: MX.t(0, -0.02, -0.04))
            part.box(size: [0.2, 0.04, 0.06], color: .solid(.gold), transform: MX.t(0, 0.1, -0.04))
            part.box(size: [0.07, 0.56, 0.025], color: .ramp(.stonePillar, from: 0.6, to: 1), transform: MX.t(0, 0.12, -0.04))
        case .ranged:
            body.frustum(bottomRadius: 0.3, topRadius: 0.15, height: 0.72, segments: 8, color: .solid(cloth),
                         capTop: true, transform: MX.t(0, 0, 0))
            body.frustum(bottomRadius: 0.31, topRadius: 0.28, height: 0.1, segments: 8, color: .solid(dark),
                         transform: MX.t(0, 0, 0))
            body.box(size: [0.36, 0.06, 0.3], color: .solid(.gold), transform: MX.t(0, 0.45, 0))
            body.sphere(radius: 0.16, segments: 8, rings: 6, color: .solid(.skin), transform: MX.t(0, 0.86, 0))
            body.frustum(bottomRadius: 0.21, topRadius: 0, height: 0.42, segments: 7, color: .solid(main),
                         transform: MX.t(0, 0.84, 0.03) * MX.rx(-0.25))
            bodyGlow.box(size: [0.2, 0.05, 0.02], color: .solid(.eye), transform: MX.t(0, 0.87, -0.155))
            // 杖（右手）
            pivot = [0.3, 0.5, -0.05]
            part.cylinder(radius: 0.03, height: 1.05, segments: 5, color: .solid(.wood), transform: MX.t(0, -0.45, 0))
            part.torus(majorRadius: 0.09, minorRadius: 0.02, segments: 10, sides: 4, color: .solid(.gold),
                       transform: MX.t(0, 0.62, 0) * MX.rx(.pi / 2))
            partGlow.crystal(radius: 0.08, height: 0.26, color: .ramp(red ? .crystalRed : .crystalBlue, from: 0.4, to: 1),
                             transform: MX.t(0, 0.5, 0))
        case .siege:
            body.box(size: [0.95, 0.36, 1.15], color: .solid(.wood), transform: MX.t(0, 0.22, 0))
            body.box(size: [1.0, 0.1, 1.2], color: .solid(dark), transform: MX.t(0, 0.58, 0))
            body.box(size: [0.2, 0.22, 1.18], color: .solid(main), transform: MX.t(-0.42, 0.34, 0))
            body.box(size: [0.2, 0.22, 1.18], color: .solid(main), transform: MX.t(0.42, 0.34, 0))
            for x: Float in [-0.52, 0.52] {
                for z: Float in [-0.38, 0.38] {
                    body.cylinder(radius: 0.24, height: 0.12, segments: 10, color: .solid(.woodDark),
                                  transform: MX.t(x - (x > 0 ? 0.06 : -0.06), 0.24, z) * MX.rz(.pi / 2))
                    body.cylinder(radius: 0.08, height: 0.14, segments: 6, color: .solid(.metal),
                                  transform: MX.t(x - (x > 0 ? 0.07 : -0.07), 0.24, z) * MX.rz(.pi / 2))
                }
            }
            body.box(size: [0.5, 0.35, 0.5], color: .solid(.metalDark), transform: MX.t(0, 0.66, 0.2))
            bodyGlow.crystal(radius: 0.14, height: 0.5, sides: 5, color: .ramp(red ? .crystalRed : .crystalBlue, from: 0.3, to: 1),
                             transform: MX.t(0, 1.0, 0.25))
            // 砲身（前方 -Z）
            pivot = [0, 0.86, 0]
            part.cylinder(radius: 0.17, height: 0.95, segments: 10, color: .solid(.metalDark),
                          transform: MX.t(0, 0, 0.1) * MX.rx(-.pi / 2))
            part.torus(majorRadius: 0.18, minorRadius: 0.04, segments: 12, sides: 4, color: .solid(main),
                       transform: MX.t(0, 0, -0.75) * MX.rx(.pi / 2))
            part.sphere(radius: 0.24, segments: 8, rings: 5, color: .solid(.metal), transform: MX.t(0, 0, 0.12))
        }
        let m = PartMeshes(body: body.makeMesh(name: "minion_body_\(key)"), bodyGlow: bodyGlow.makeMesh(name: "minion_glow_\(key)"),
                           part: part.makeMesh(name: "minion_part_\(key)"), partGlow: partGlow.makeMesh(name: "minion_partglow_\(key)"),
                           partPivot: pivot)
        minionCache[key] = m
        return m
    }

    // MARK: モンスター・人形

    func monster(_ kind: MonsterKind) -> PartMeshes {
        let key = kind.rawValue
        if let m = monsterCache[key] { return m }
        var body = MeshBuilder(), glow = MeshBuilder(), part = MeshBuilder(), partGlow = MeshBuilder()
        var pivot = SIMD3<Float>.zero
        var mirror = false
        switch kind {
        case .campLarge, .campSmall:
            // 結晶を背負う四足獣
            let large = kind == .campLarge
            let fur: Swatch = large ? .beastPurple : .furBrown
            let crystal: Ramp = large ? .crystalPurple : .crystalBlue
            body.sphere(radius: 1, segments: 10, rings: 7, color: .solid(fur), transform: MX.t(0, 0.72, 0.05) * MX.s(0.5, 0.42, 0.78))
            body.sphere(radius: 1, segments: 8, rings: 5, color: .solid(.beastBelly), transform: MX.t(0, 0.6, 0.05) * MX.s(0.4, 0.3, 0.62))
            for (x, z) in [(Float(-0.3), Float(-0.45)), (0.3, -0.45), (-0.3, 0.5), (0.3, 0.5)] {
                body.frustum(bottomRadius: 0.1, topRadius: 0.14, height: 0.52, segments: 6, color: .solid(fur),
                             transform: MX.t(x, 0, z))
                body.box(size: [0.2, 0.08, 0.24], color: .solid(.horn), transform: MX.t(x, 0, z - 0.04))
            }
            body.sphere(radius: 0.32, segments: 9, rings: 6, color: .solid(fur), transform: MX.t(0, 0.86, -0.72) * MX.s(1, 0.9, 1.15))
            body.sphere(radius: 0.18, segments: 7, rings: 5, color: .solid(.beastBelly), transform: MX.t(0, 0.74, -0.98))
            for s: Float in [-1, 1] {
                body.frustum(bottomRadius: 0.07, topRadius: 0, height: 0.36, segments: 5, color: .solid(.horn),
                             transform: MX.t(0.18 * s, 1.08, -0.72) * MX.rz(-0.5 * s) * MX.rx(0.3))
                glow.sphere(radius: 0.05, segments: 5, rings: 3, color: .solid(.eye), transform: MX.t(0.14 * s, 0.92, -0.99))
            }
            body.frustum(bottomRadius: 0.08, topRadius: 0.02, height: 0.5, segments: 5, color: .solid(fur),
                         transform: MX.t(0, 0.7, 0.8) * MX.rx(1.1))
            for k in 0..<5 {
                let z = -0.35 + Float(k) * 0.2
                glow.crystal(radius: 0.09 + 0.02 * Float(k % 2), height: 0.4 + 0.1 * Float((k + 1) % 3), sides: 5,
                             color: .ramp(crystal, from: 0.3, to: 1),
                             transform: MX.t(0, 1.0 - abs(z) * 0.2, z) * MX.rz(Float(k % 2 == 0 ? 0.25 : -0.25)))
            }
        case .blueSentinel, .redSentinel, .ancientColossus:
            let colossus = kind == .ancientColossus
            let stone: Ramp = colossus ? .colossus : .rock
            let coreRamp: Ramp = colossus ? .crystalGold : (kind == .blueSentinel ? .crystalBlue : .crystalRed)
            let rune: Swatch = colossus ? .glowGold : (kind == .blueSentinel ? .glowBlue : .glowRed)
            // 脚
            for s: Float in [-1, 1] {
                body.frustum(bottomRadius: 0.24, topRadius: 0.3, height: 0.75, segments: 6, color: .ramp(stone, from: 0.1, to: 0.6),
                             transform: MX.t(0.34 * s, 0, 0))
                body.box(size: [0.5, 0.18, 0.62], color: .ramp(stone, from: 0, to: 0.3), transform: MX.t(0.34 * s, 0, -0.06))
            }
            // 胴（岩塊）+ 胸の核
            body.blob(radius: 0.72, jitter: 0.12, seed: colossus ? 77 : 33, color: .ramp(stone, from: 0.2, to: 1),
                      transform: MX.t(0, 1.35, 0) * MX.s(1.15, 0.95, 0.85))
            body.box(size: [0.9, 0.32, 0.6], color: .ramp(stone, from: 0.1, to: 0.5), transform: MX.t(0, 0.72, 0))
            glow.crystal(radius: 0.2, height: 0.5, sides: 6, color: .ramp(coreRamp, from: 0.2, to: 1),
                         transform: MX.t(0, 1.12, -0.52) * MX.rx(-0.25))
            glow.torus(majorRadius: 0.28, minorRadius: 0.035, segments: 16, sides: 4, color: .solid(rune),
                       transform: MX.t(0, 1.35, -0.58) * MX.rx(.pi / 2))
            // 頭と苔
            body.box(size: [0.42, 0.34, 0.4], color: .ramp(stone, from: 0.5, to: 1), transform: MX.t(0, 1.95, -0.08))
            body.blob(radius: 0.2, jitter: 0.2, seed: 11, color: .solid(colossus ? .goldDark : .moss),
                      transform: MX.t(0, 2.12, -0.02) * MX.s(1.1, 0.4, 1))
            for s: Float in [-1, 1] {
                body.blob(radius: 0.32, jitter: 0.2, seed: 12, color: .solid(colossus ? .colossusDark : .moss),
                          transform: MX.t(0.45 * s, 1.95, 0.12) * MX.s(1, 0.45, 1))
            }
            glow.box(size: [0.28, 0.06, 0.02], color: .solid(rune), transform: MX.t(0, 2.1, -0.29))
            // 肩の結晶
            for s: Float in [-1, 1] {
                glow.crystal(radius: 0.1, height: 0.46, sides: 5, color: .ramp(coreRamp, from: 0.3, to: 1),
                             transform: MX.t(0.62 * s, 1.72, 0.1) * MX.rz(-0.45 * s))
            }
            if colossus {
                // 古環: 胴を巡る金の輪と背の石板
                glow.torus(majorRadius: 1.0, minorRadius: 0.05, segments: 28, sides: 5, color: .solid(.glowGold),
                           transform: MX.t(0, 1.4, 0) * MX.rx(0.25))
                body.box(size: [1.1, 1.0, 0.18], color: .ramp(.colossus, from: 0.3, to: 0.9), transform: MX.t(0, 1.25, 0.62) * MX.rx(0.15))
                for s: Float in [-1, 1] {
                    glow.box(size: [0.06, 0.5, 0.02], color: .solid(.glowGold), transform: MX.t(0.3 * s, 1.5, 0.72) * MX.rx(0.15))
                }
            }
            // 腕（左右対、肩が回転軸）
            pivot = [0.82, 1.62, 0]
            mirror = true
            part.sphere(radius: 0.26, segments: 7, rings: 5, color: .ramp(stone, from: 0.4, to: 1))
            part.frustum(bottomRadius: 0.2, topRadius: 0.17, height: 0.62, segments: 6, color: .ramp(stone, from: 0.2, to: 0.8),
                         transform: MX.t(0.05, -0.72, 0))
            part.blob(radius: 0.3, jitter: 0.15, seed: 5, color: .ramp(stone, from: 0.1, to: 0.7),
                      transform: MX.t(0.08, -0.98, -0.05) * MX.s(1, 1.1, 1))
            partGlow.box(size: [0.04, 0.4, 0.04], color: .solid(rune), transform: MX.t(0.2, -0.65, -0.12))
        case .astralWyrm:
            // 胴体は BattleUnits 側で節エンティティとして組むので、ここでは頭部のみ（part = 1 節）
            body.sphere(radius: 0.5, segments: 10, rings: 7, color: .ramp(.wyrm, from: 0.1, to: 1), transform: MX.s(1, 0.85, 1.35))
            body.sphere(radius: 0.3, segments: 8, rings: 5, color: .solid(.wyrmBelly), transform: MX.t(0, -0.2, -0.45) * MX.s(1, 0.5, 1.3))
            for s: Float in [-1, 1] {
                body.frustum(bottomRadius: 0.1, topRadius: 0, height: 0.7, segments: 5, color: .solid(.horn),
                             transform: MX.t(0.25 * s, 0.25, 0.1) * MX.rx(0.9) * MX.rz(-0.35 * s))
                glow.sphere(radius: 0.08, segments: 6, rings: 4, color: .solid(.glowPink), transform: MX.t(0.27 * s, 0.14, -0.5))
                // 翼膜
                let uv = PaletteLayout.uv(.wyrmScaleDark)
                body.triangle([0.35 * s, 0.05, 0.2], [1.6 * s, 0.75, 0.75], [0.45 * s, 0.0, 1.1], uv: uv)
                body.triangle([0.45 * s, 0.0, 1.1], [1.6 * s, 0.75, 0.75], [0.35 * s, 0.05, 0.2], uv: uv)
                body.frustum(bottomRadius: 0.04, topRadius: 0.02, height: 1.35, segments: 4, color: .solid(.horn),
                             transform: MX.t(0.35 * s, 0.05, 0.2) * MX.ry(s > 0 ? -0.55 : 0.55) * MX.rz(-1.1 * s))
            }
            glow.crystal(radius: 0.08, height: 0.3, color: .solid(.glowPurple), transform: MX.t(0, 0.38, -0.2))
            pivot = .zero
            part.sphere(radius: 1, segments: 9, rings: 6, color: .ramp(.wyrm, from: 0.05, to: 0.95))
            partGlow.crystal(radius: 0.2, height: 0.7, sides: 4, color: .ramp(.crystalPurple, from: 0.3, to: 1),
                             transform: MX.t(0, 0.85, 0))
        }
        let m = PartMeshes(body: body.makeMesh(name: "monster_\(key)"), bodyGlow: glow.makeMesh(name: "monster_glow_\(key)"),
                           part: part.makeMesh(name: "monster_part_\(key)"), partGlow: partGlow.makeMesh(name: "monster_partglow_\(key)"),
                           partPivot: pivot, mirrorPart: mirror)
        monsterCache[key] = m
        return m
    }

    lazy var dummy: PartMeshes = {
        var body = MeshBuilder(), glow = MeshBuilder()
        body.cylinder(radius: 0.07, height: 1.2, segments: 6, color: .solid(.woodDark))
        body.frustum(bottomRadius: 0.5, topRadius: 0.45, height: 0.12, segments: 8, color: .solid(.stoneDark))
        body.frustum(bottomRadius: 0.24, topRadius: 0.3, height: 0.62, segments: 8, color: .solid(.straw), transform: MX.t(0, 0.62, 0))
        body.box(size: [1.0, 0.1, 0.1], color: .solid(.woodDark), transform: MX.t(0, 1.05, 0))
        for s: Float in [-1, 1] {
            body.frustum(bottomRadius: 0.07, topRadius: 0.1, height: 0.3, segments: 6, color: .solid(.straw),
                         transform: MX.t(0.52 * s, 1.1, 0) * MX.rz(.pi / 2 * s))
        }
        body.sphere(radius: 0.21, segments: 8, rings: 6, color: .solid(.straw), transform: MX.t(0, 1.46, 0))
        body.torus(majorRadius: 0.24, minorRadius: 0.03, segments: 12, sides: 4, color: .solid(.rope), transform: MX.t(0, 1.26, 0))
        // 的
        for (k, r) in [Float(0.22), 0.15, 0.08].enumerated() {
            body.cylinder(radius: r, height: 0.02 + Float(k) * 0.01, segments: 16, color: .solid(k % 2 == 0 ? .redMain : .white),
                          transform: MX.t(0, 0.9, -0.3) * MX.rx(.pi / 2))
        }
        glow.crystal(radius: 0.05, height: 0.2, color: .solid(.glowGold), transform: MX.t(0, 1.7, 0))
        return PartMeshes(body: body.makeMesh(name: "dummy"), bodyGlow: glow.makeMesh(name: "dummy_glow"))
    }()

    /// 構造物の瓦礫（破壊後）。
    lazy var rubble: MeshResource? = {
        var b = MeshBuilder()
        var rng = RenderRNG(seed: 4242)
        for k in 0..<11 {
            let a = rng.range(0, 6.28)
            let d = rng.range(0.2, 1.4)
            let p = SIMD3<Float>(cos(a) * d, 0, sin(a) * d)
            if k % 3 == 0 {
                b.box(size: [rng.range(0.3, 0.6), rng.range(0.2, 0.4), rng.range(0.3, 0.6)], color: .solid(.stone),
                      transform: MX.t(p) * MX.ry(rng.range(0, 3)) * MX.rz(rng.range(-0.4, 0.4)))
            } else {
                MapProps.rock(&b, at: p, size: rng.range(0.2, 0.42), seed: UInt64(k) &+ 90)
            }
        }
        b.frustum(bottomRadius: 0.72, topRadius: 0.55, height: 0.7, segments: 8, color: .ramp(.stonePillar, from: 0, to: 0.5),
                  capTop: true)
        return b.makeMesh(name: "rubble")
    }()
}
