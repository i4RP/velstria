import CoreGraphics
import Foundation
import RealityKit
import UIKit

// 担当: battle-renderer（カメラ）。Star Core の終幕の空。低い視点で結晶を見上げると空が映るが、ゲームカメラ（俯角 56°）は
// 空を映さないので背景は暗い単色のまま。終幕の間だけ、夕暮れの霞（地平線）→ 深い青緑（天頂）のドームを出す。
// 読み込み幕の裏で作り（AssetLedger に記録）、ウォームアップの間も描いてシェーダーを用意しておく（終幕で初めて描いて止まらない）。
// 毎フレームはカメラの位置へ動かすだけ（ドームの中心 = カメラ。半径はカメラの far 160 m の内側）。影は落とさない。

@MainActor
final class CoreFinaleSky {
    let entity: ModelEntity
    static let radius: Float = 140
    /// ドームの下端（地平線より下。外周の地面の板の向こうに見える分）。
    static let lowestElevation: Float = -15 * .pi / 180

    /// グラデーションの色（下端 → 天頂。位置はドームの v = 0〜1）。石・苔・青緑の配色に合わせた霞んだ夕暮れ。
    static let stops: [(v: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (0.00, 0.08, 0.12, 0.10),
        (0.12, 0.20, 0.25, 0.22),
        (0.143, 0.50, 0.50, 0.44),
        (0.19, 0.38, 0.44, 0.44),
        (0.40, 0.18, 0.27, 0.32),
        (1.00, 0.05, 0.08, 0.13),
    ]

    init() {
        let model = ModelEntity()
        model.name = "finaleSky"
        entity = model
        if let mesh = CoreFinaleSky.makeMesh() {
            AssetLedger.record(.mesh, "finale sky")
            var material = UnlitMaterial(applyPostProcessToneMap: false)
            if let image = CoreFinaleSky.gradientImage(),
               let texture = try? TextureResource(image: image, options: .init(semantic: .color, mipmapsMode: .none)) {
                AssetLedger.record(.texture, "finale sky")
                var t = MaterialParameters.Texture(texture)
                let sd = MTLSamplerDescriptor()
                sd.minFilter = .linear
                sd.magFilter = .linear
                sd.sAddressMode = .repeat
                sd.tAddressMode = .clampToEdge
                t.sampler = .init(sd)
                material.color = .init(tint: .white, texture: t)
            } else {
                material.color = .init(tint: UIColor(red: 0.22, green: 0.31, blue: 0.35, alpha: 1))
            }
            material.faceCulling = .none
            AssetLedger.record(.material, "finale sky")
            model.model = ModelComponent(mesh: mesh, materials: [material])
        }
        AssetLedger.record(.entity, "finale sky")
        model.components.set(DynamicLightShadowComponent(castsShadow: false))
        model.isEnabled = false
    }

    var isShown: Bool {
        get { entity.isEnabled }
        set { if entity.isEnabled != newValue { entity.isEnabled = newValue } }
    }

    /// ドームの中心をカメラへ（空はカメラと一緒に動く = 無限遠に見える）。
    func follow(_ camera: SIMD3<Float>) {
        entity.position = camera
    }

    /// 内側から見るドーム（経度 32 分割・緯度 12 段。v = 下端 0 → 天頂 1）。
    private static func makeMesh() -> MeshResource? {
        let segments = 32, rings = 12
        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        let e0 = lowestElevation, e1: Float = .pi / 2
        for r in 0...rings {
            let v = Float(r) / Float(rings)
            let e = e0 + (e1 - e0) * v
            for s in 0...segments {
                let u = Float(s) / Float(segments)
                let a = u * 2 * .pi
                positions.append(SIMD3(cos(e) * sin(a), sin(e), cos(e) * cos(a)) * radius)
                uvs.append(SIMD2(u, v))
            }
        }
        let row = UInt32(segments + 1)
        for r in 0..<UInt32(rings) {
            for s in 0..<UInt32(segments) {
                let a = r * row + s, b = a + 1, c = a + row, d = c + 1
                indices += [a, c, b, b, c, d]
            }
        }
        var d = MeshDescriptor(name: "finaleSky")
        d.positions = MeshBuffers.Positions(positions)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        d.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [d])
    }

    /// 縦 1 列のグラデーション（画像の上端 = 天頂。RealityKit の標準の UV は v = 1 が画像の上端）。
    private static func gradientImage() -> CGImage? {
        let w = 4, h = 256
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = stops.map { CGColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: 1) } as CFArray
        let locations = stops.map(\.v)
        guard let gradient = CGGradient(colorsSpace: ctx.colorSpace, colors: colors, locations: locations) else { return nil }
        // CGContext の y は下から上（y = 0 が画像の下端 = v 0）
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])
        return ctx.makeImage()
    }
}
