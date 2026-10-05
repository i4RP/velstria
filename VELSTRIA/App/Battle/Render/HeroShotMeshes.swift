import Foundation
import RealityKit
import simd

// 担当: battle-renderer。ヒーロー別の投射物の形（矢・雷の投げ槍・光輪・爪の三日月）。
// どれも白の単色（パレットの白の UV）で作り、色は ProjectileLayer が単色の Unlit で付ける（ヒーローの色・チームで
// メッシュを分けない）。形は -Z が進行方向、原点が中心。使う形だけを読み込み中（投射物のプールの事前生成）に 1 度作る。
// 光球・曳光弾・散弾は単位球（UnitMeshLibrary.unitSphere）を拡縮して使う。

@MainActor
final class HeroShotMeshes {
    private static let white = PaletteColor.solid(.white)

    /// 矢（全長 0.62 m）: 細い矢柄・四角錐の鏃・十字の矢羽。矢弾（H009）は拡縮して太く短くする。
    lazy var arrow: MeshResource? = {
        var b = MeshBuilder()
        let toFront = MX.rx(-.pi / 2)
        b.box(size: [0.026, 0.5, 0.026], color: HeroShotMeshes.white, transform: MX.t(0, 0, 0.27) * toFront)
        b.frustum(bottomRadius: 0.055, topRadius: 0, height: 0.14, segments: 4, color: HeroShotMeshes.white, capBottom: true,
                  transform: MX.t(0, 0, -0.2) * toFront)
        b.box(size: [0.1, 0.12, 0.006], color: HeroShotMeshes.white, transform: MX.t(0, -0.003, 0.31) * toFront)
        b.box(size: [0.006, 0.12, 0.1], color: HeroShotMeshes.white, transform: MX.t(0, 0, 0.31) * toFront)
        return b.makeMesh(name: "shot_arrow")
    }()

    /// 雷の投げ槍（全長 0.9 m のジグザグの細い光条 + 小さな枝）。A・B を交互に出して明滅させる。
    lazy var lightningA: MeshResource? = Self.lightning(offsets: [0, 0.07, -0.05, 0.08, -0.04, 0.06, 0], fork: 2,
                                                        name: "shot_lightningA")
    lazy var lightningB: MeshResource? = Self.lightning(offsets: [0, -0.06, 0.08, -0.03, 0.07, -0.05, 0], fork: 4,
                                                        name: "shot_lightningB")

    /// 回る光輪（半径 0.2 m の環 + 回転が見える 4 つの玉）。水平に置き、ProjectileLayer が傾けて回す。
    lazy var haloRing: MeshResource? = {
        var b = MeshBuilder()
        b.torus(majorRadius: 0.2, minorRadius: 0.022, segments: 28, sides: 6, color: HeroShotMeshes.white)
        for k in 0..<4 {
            let a = Float(k) / 4 * 2 * .pi
            b.sphere(radius: 0.042, segments: 8, rings: 5, color: HeroShotMeshes.white, transform: MX.t(cos(a) * 0.2, 0, -sin(a) * 0.2))
        }
        return b.makeMesh(name: "shot_haloRing")
    }()

    /// 爪の三日月（進行方向へ反った細い弧 3 本、水平）。上方のカメラから読めるよう面は上向き。
    lazy var clawCrescent: MeshResource? = {
        var b = MeshBuilder()
        for k in 0..<3 {
            let r = 0.2 + Float(k) * 0.06
            let th: Float = 0.022 + Float(k) * 0.004
            let sweep: Float = 1.5 - Float(k) * 0.15
            // annulus は角度 a を (cos a, 0, -sin a) に置く → π/2 が -Z（進行方向）
            b.annulus(inner: r - th, outer: r, segments: 14, startAngle: .pi / 2 - sweep / 2, sweep: sweep,
                      color: HeroShotMeshes.white, transform: MX.t(0, 0, 0.26))
        }
        return b.makeMesh(name: "shot_clawCrescent")
    }()

    private static func lightning(offsets: [Float], fork: Int, name: String) -> MeshResource? {
        var b = MeshBuilder()
        let n = offsets.count - 1
        var pts: [SIMD3<Float>] = []
        for (k, o) in offsets.enumerated() {
            let z = 0.45 - 0.9 * Float(k) / Float(n)
            pts.append([o, o * 0.4, z])
        }
        func segment(_ a: SIMD3<Float>, _ c: SIMD3<Float>, width w: Float) {
            let d = c - a
            let len = simd_length(d)
            guard len > 1e-4 else { return }
            let rot = simd_float4x4(simd_quatf(from: [0, 1, 0], to: d / len))
            b.box(size: [w, len, w], color: white, transform: MX.t(a) * rot)
        }
        for k in 0..<n {
            // 両端ほど細い
            let mid = 1 - abs(Float(k) + 0.5 - Float(n) / 2) / (Float(n) / 2)
            segment(pts[k], pts[k + 1], width: 0.022 + 0.022 * mid)
        }
        // 枝: 途中の節から斜め後ろへ短く
        let p = pts[fork]
        segment(p, p + SIMD3(offsets[fork] >= 0 ? 0.12 : -0.12, 0.03, 0.1), width: 0.016)
        return b.makeMesh(name: name)
    }
}
