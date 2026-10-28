import CoreGraphics
import Foundation
import RealityKit
import UIKit

// 担当: battle-renderer（カメラ）。一人称と Star Core の終幕で共有する空。
// 夕方の青紫の空と柔らかな雲のドーム。俯瞰カメラでは隠す。
// 読み込み幕の裏で作り（AssetLedger に記録）、ウォームアップの間も描いてシェーダーを用意しておく（終幕で初めて描いて止まらない）。
// 毎フレームはカメラの位置へ動かすだけ（ドームの中心 = カメラ。半径はカメラの far 160 m の内側）。影は落とさない。

@MainActor
final class CoreFinaleSky {
    let entity: ModelEntity
    static let radius: Float = 140
    /// ドームの下端（地平線より下。外周の地面の板の向こうに見える分）。
    static let lowestElevation: Float = -15 * .pi / 180

    /// 地平線の淡い夕色から天頂の青紫へ（位置はドームの v = 0〜1）。
    static let stops: [(v: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (0.00, 0.72, 0.66, 0.73),
        (0.143, 0.78, 0.69, 0.76),
        (0.25, 0.48, 0.53, 0.73),
        (0.50, 0.29, 0.39, 0.65),
        (1.00, 0.17, 0.27, 0.51),
    ]

    static let backgroundColor = UIColor(red: 0.78, green: 0.69, blue: 0.76, alpha: 1)

    static let seasideBackgroundColor = UIColor(red: 0.48, green: 0.80, blue: 0.94, alpha: 1)

    init(seaside: Bool = false) {
        let model = ModelEntity()
        model.name = "finaleSky"
        entity = model
        if let mesh = CoreFinaleSky.makeMesh() {
            AssetLedger.record(.mesh, "finale sky")
            var material = UnlitMaterial(applyPostProcessToneMap: false)
            if let image = CoreFinaleSky.skyImage(seaside: seaside),
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
                material.color = .init(tint: seaside ? Self.seasideBackgroundColor : Self.backgroundColor)
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

    /// 雲も読み込み中に 1 枚へ焼く。追加の Entity・毎フレームの生成や更新は不要。
    /// 画像の上端 = 天頂（RealityKit の標準の UV は v = 1 が画像の上端）。
    private static func skyImage(seaside: Bool) -> CGImage? {
        let w = 1024, h = 512
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let palette: [(v: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] = seaside ? [
            (0.00, 0.70, 0.90, 0.96), (0.143, 0.48, 0.80, 0.94),
            (0.25, 0.20, 0.68, 0.92), (0.50, 0.09, 0.55, 0.88), (1.00, 0.06, 0.38, 0.76),
        ] : stops
        let colors = palette.map { CGColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: 1) } as CFArray
        let locations = palette.map(\.v)
        guard let gradient = CGGradient(colorsSpace: ctx.colorSpace, colors: colors, locations: locations) else { return nil }
        // CGContext の y は下から上（y = 0 が画像の下端 = v 0）
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h), options: [])
        // 360 度に散らした小さな積雲。画像の左右端と天頂は空け、継ぎ目や極の歪みを避ける。
        let clouds: [(u: CGFloat, v: CGFloat, width: CGFloat, height: CGFloat)] = [
            (0.08, 0.29, 0.090, 0.065),
            (0.26, 0.42, 0.085, 0.075),
            (0.44, 0.25, 0.070, 0.045),
            (0.60, 0.35, 0.105, 0.080),
            (0.78, 0.49, 0.075, 0.065),
            (0.92, 0.26, 0.065, 0.045),
        ]
        for cloud in clouds {
            drawCloud(in: ctx, rect: CGRect(x: (cloud.u - cloud.width / 2) * CGFloat(w),
                                           y: cloud.v * CGFloat(h),
                                           width: cloud.width * CGFloat(w) * (seaside ? 1.7 : 1), height: cloud.height * CGFloat(h) * (seaside ? 1.35 : 1)), seaside: seaside)
        }
        return ctx.makeImage()
    }

    private static func drawCloud(in ctx: CGContext, rect: CGRect, seaside: Bool) {
        // 不揃いな丸みを重ね、底は薄く、日を受ける上側は白くする。
        let puffs: [CGRect] = [
            CGRect(x: 0.06, y: 0.05, width: 0.87, height: 0.36),
            CGRect(x: 0.00, y: 0.14, width: 0.31, height: 0.42),
            CGRect(x: 0.18, y: 0.20, width: 0.35, height: 0.61),
            CGRect(x: 0.39, y: 0.23, width: 0.35, height: 0.77),
            CGRect(x: 0.60, y: 0.16, width: 0.28, height: 0.55),
            CGRect(x: 0.76, y: 0.10, width: 0.24, height: 0.38),
        ]
        // Feather every lobe into the sky; no opaque cutout edge at eye level.
        let colors = seaside ? [CGColor(srgbRed: 1, green: 1, blue: 0.97, alpha: 0.98),
                                 CGColor(srgbRed: 0.95, green: 0.98, blue: 1, alpha: 0.90),
                                 CGColor(srgbRed: 0.77, green: 0.89, blue: 0.96, alpha: 0)] as CFArray
            : [CGColor(srgbRed: 0.92, green: 0.78, blue: 0.78, alpha: 0.52),
                      CGColor(srgbRed: 0.70, green: 0.66, blue: 0.80, alpha: 0.28),
                      CGColor(srgbRed: 0.60, green: 0.61, blue: 0.76, alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: ctx.colorSpace, colors: colors,
                                        locations: [0, 0.55, 1]) else { return }
        for puff in puffs {
            let box = CGRect(x: rect.minX + puff.minX * rect.width,
                             y: rect.minY + puff.minY * rect.height,
                             width: puff.width * rect.width, height: puff.height * rect.height)
            ctx.saveGState()
            ctx.translateBy(x: box.midX, y: box.midY)
            ctx.scaleBy(x: box.width / 2, y: box.height / 2)
            ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: 1, options: [])
            ctx.restoreGState()
        }
    }
}
