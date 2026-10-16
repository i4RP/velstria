import CoreGraphics
import Foundation
import Metal
import RealityKit
import UIKit

// 担当: battle-renderer（スキル演出）。演出のメッシュの加算合成・流れる模様のための CustomMaterial の Program（FXShaders.metal）、
// 繰り返しの模様の画像（FXFlowTex）、粒子のコマ送りのスプライトシート（FXSheet。App/Resources/FX/Sheets、tools/vfx_sprites）。
// Program の生成は非同期なので、試合の読み込みの始めに prewarm（BattlePreload）し、幕を上げる前に待つ（BattleRenderer の warmupGates）。
// シミュレータでも作る（加算は Program でしか作れない）。作れなかった時（シェーダーが無い・コンパイルの失敗）は failed になり、
// 加算・模様のメッシュは従来のアルファ合成の Unlit 材質で出す（FXMaterialLibrary）。

@MainActor
enum FXPrograms {
    private(set) static var add: CustomMaterial.Program?
    private(set) static var alpha: CustomMaterial.Program?
    private(set) static var failed = false
    private(set) static var failure: String?
    private static var task: Task<Void, Never>?
    /// 生成にかかった時間（ms。計測ログ用）。
    private(set) static var buildMs: Double?

    /// 読み込みの始めに作り、幕の前に待つ環境か。シミュレータは撮影（-fxCapture）か -fxPrograms の時だけ
    /// （GPU の無い CI ではコンパイルが遅くロードを止めるため。作らない時は加算・模様のメッシュを従来の材質で出す）。
    #if targetEnvironment(simulator)
    static var prewarmsOnThisDevice: Bool {
        DebugLaunch.value(after: "-fxCapture") != nil || DebugLaunch.args.contains("-fxPrograms")
    }
    #else
    static let prewarmsOnThisDevice = true
    #endif

    static var isReady: Bool { add != nil && alpha != nil }
    /// 幕を上げてよいか（作り終えた・作れないと決まった）。
    static var isSettled: Bool { isReady || failed }

    static func prewarm() {
        guard task == nil, !isSettled else { return }
        guard let device = MTLCreateSystemDefaultDevice(), let lib = device.makeDefaultLibrary() else {
            fail("default.metallib が無い")
            return
        }
        // RealityKit のエンジンをメインスレッドで先に起こす（MaterialPrograms と同じ理由）
        AssetLedger.record(.mesh, "RealityKit engine start (fx)")
        _ = MeshResource.generatePlane(width: 0.01, depth: 0.01)
        let start = CACurrentMediaTime()
        let addShader = CustomMaterial.SurfaceShader(named: "fxAddSurface", in: lib)
        let alphaShader = CustomMaterial.SurfaceShader(named: "fxAlphaSurface", in: lib)
        task = Task { @MainActor in
            do {
                let pair = try await build(addShader, alphaShader)
                add = pair.0
                alpha = pair.1
                buildMs = (CACurrentMediaTime() - start) * 1000
            } catch {
                fail("\(error)")
            }
            task = nil
        }
    }

    private nonisolated static func build(_ addShader: CustomMaterial.SurfaceShader, _ alphaShader: CustomMaterial.SurfaceShader)
        async throws -> (CustomMaterial.Program, CustomMaterial.Program) {
        let a = try await CustomMaterial.Program(surfaceShader: addShader, geometryModifier: nil, descriptor: descriptor(.add))
        let b = try await CustomMaterial.Program(surfaceShader: alphaShader, geometryModifier: nil, descriptor: descriptor(.alpha))
        return (a, b)
    }

    nonisolated static func descriptor(_ blend: MaterialParameterTypes.BlendMode) -> CustomMaterial.Program.Descriptor {
        var d = CustomMaterial.Program.Descriptor()
        d.lightingModel = .unlit
        d.blendMode = blend
        return d
    }

    private static func fail(_ why: String) {
        failed = true
        failure = why
        print("VELSTRIA_FX_PROGRAMS failed: \(why)")
    }

    /// 生成が終わるまで待つ（テスト用）。
    static func waitUntilSettled() async {
        prewarm()
        while !isSettled {
            if let task { await task.value } else { try? await Task.sleep(for: .milliseconds(5)) }
        }
    }
}

// MARK: - 繰り返しの模様（流れる模様の画像）

/// 流れる模様の画像（白黒・継ぎ目なしの繰り返し。256 px）。CoreGraphics で作る（読み込み幕の裏で一度だけ）。
enum FXFlowTex: String, CaseIterable, Hashable, Sendable {
    /// 柔らかい雲状のノイズ（炎・エネルギーの揺らぎ）。
    case noise
    /// 縦の筋（光の柱・突進の尾・上昇）。
    case streaks
    /// 細胞状のひび（氷・結晶・電撃の網目）。
    case cells

    static let size = 256

    /// 0〜1 の値の画像（輝度 = アルファ。白 + アルファの画像として材質の custom に渡す）。
    static func image(_ t: FXFlowTex) -> CGImage? {
        let n = size
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let u = Float(x) / Float(n), v = Float(y) / Float(n)
                let value: Float
                switch t {
                case .noise: value = fbm(u, v, octaves: 4, base: 4)
                case .streaks:
                    let w = fbm(u, v * 0.25, octaves: 3, base: 6)
                    let line = 0.5 + 0.5 * sin((u * 12 + w * 1.6) * 2 * .pi)
                    value = min(1, max(0, pow(line, 3) * 0.9 + fbm(u, v, octaves: 2, base: 8) * 0.35))
                case .cells: value = cells(u, v, count: 7)
                }
                let b = UInt8(max(0, min(255, (value * 255).rounded())))
                let k = (y * n + x) * 4
                px[k] = b; px[k + 1] = b; px[k + 2] = b; px[k + 3] = b
            }
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// 周期 1 で継ぎ目の無い値ノイズ（格子 base × 2^k）。
    private static func fbm(_ u: Float, _ v: Float, octaves: Int, base: Int) -> Float {
        var sum: Float = 0, amp: Float = 0.5, norm: Float = 0
        var g = base
        for o in 0..<octaves {
            sum += amp * valueNoise(u, v, grid: g, seed: UInt32(o * 977 + 13))
            norm += amp
            amp *= 0.5
            g *= 2
        }
        return sum / norm
    }

    private static func valueNoise(_ u: Float, _ v: Float, grid g: Int, seed: UInt32) -> Float {
        let x = u * Float(g), y = v * Float(g)
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = x - Float(x0), fy = y - Float(y0)
        func h(_ i: Int, _ j: Int) -> Float {
            let a = UInt32(truncatingIfNeeded: ((i % g) + g) % g), b = UInt32(truncatingIfNeeded: ((j % g) + g) % g)
            var z = a &* 0x9E37_79B1 ^ b &* 0x85EB_CA77 ^ seed &* 0xC2B2_AE3D
            z ^= z >> 15; z = z &* 0x2C1B_3C6D; z ^= z >> 12; z = z &* 0x297A_2D39; z ^= z >> 15
            return Float(z & 0xFFFF) / 65535
        }
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = h(x0, y0) + (h(x0 + 1, y0) - h(x0, y0)) * sx
        let b = h(x0, y0 + 1) + (h(x0 + 1, y0 + 1) - h(x0, y0 + 1)) * sx
        return a + (b - a) * sy
    }

    /// 周期 1 の細胞のひび（最も近い 2 点の距離の差が小さい所が明るい線）。
    private static func cells(_ u: Float, _ v: Float, count c: Int) -> Float {
        let x = u * Float(c), y = v * Float(c)
        let cx = Int(floor(x)), cy = Int(floor(y))
        var d1: Float = 9, d2: Float = 9
        for j in -1...1 {
            for i in -1...1 {
                let gi = cx + i, gj = cy + j
                let wi = ((gi % c) + c) % c, wj = ((gj % c) + c) % c
                var z = UInt32(wi * 7919 + wj * 104_729 + 17)
                z ^= z >> 13; z = z &* 0x5BD1_E995; z ^= z >> 15
                let px = Float(gi) + Float(z & 0xFF) / 255, py = Float(gj) + Float((z >> 8) & 0xFF) / 255
                let d = hypot(px - x, py - y)
                if d < d1 { d2 = d1; d1 = d } else if d < d2 { d2 = d }
            }
        }
        let edge = 1 - min(1, (d2 - d1) * 6)
        return max(0, min(1, pow(edge, 2.2)))
    }
}

// MARK: - 粒子のコマ送り（スプライトシート）

/// 粒子のコマ送りの画像（4 × 4 = 16 コマ、1 コマ 128 px、白 + アルファ。tools/vfx_sprites/gen_sheets.py が作る）。
enum FXSheet: String, CaseIterable, Hashable, Sendable {
    case smokePuff = "smoke_puff"
    case fireBurst = "fire_burst"
    case flameLoop = "flame_loop"
    case electricArc = "electric_arc"
    case energyBurst = "energy_burst"
    case shockRing = "shock_ring"
    case slashFade = "slash_fade"
    case iceShatter = "ice_shatter"
    case sparkTwinkle = "spark_twinkle"
    case darkWisp = "dark_wisp"
    case groundCrack = "ground_crack"
    case hitFlash = "hit_flash"

    var rows: Int { 4 }
    var columns: Int { 4 }
    var frames: Int { rows * columns }

    /// 繰り返す（炎・電撃・きらめき）か、1 回で消える（それ以外。最後のコマはほぼ空）。
    var loops: Bool {
        switch self {
        case .flameLoop, .electricArc, .sparkTwinkle: return true
        default: return false
        }
    }

    /// 繰り返す画像の既定のコマ数 / 秒。
    var loopFPS: Float {
        switch self {
        case .electricArc: return 20
        case .sparkTwinkle: return 14
        default: return 18
        }
    }

    static func image(_ s: FXSheet, bundle: Bundle = .main) -> CGImage? {
        guard let url = bundle.url(forResource: s.rawValue, withExtension: "png"),
              let img = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        return img
    }
}

/// 試合に出るヒーローのレシピが使うスプライトシートの画像（アルファ合成用・加算用の輝度版）。
@MainActor
final class FXSheetLibrary {
    private var alpha: [FXSheet: TextureResource] = [:]
    private var glow: [FXSheet: TextureResource] = [:]
    /// 画像が無い・読めなかったシート（コマ送りなしの既定の画像で出す）。
    private(set) var missing: Set<FXSheet> = []

    func texture(_ s: FXSheet, additive: Bool) -> TextureResource? {
        additive ? glow[s] : alpha[s]
    }

    func prewarm(_ sheets: some Sequence<FXSheet>) {
        for s in sheets where alpha[s] == nil && !missing.contains(s) {
            guard let img = FXSheet.image(s), let lum = FXTextureLibrary.luminance(img),
                  let a = try? TextureResource(image: img, options: .init(semantic: .color)),
                  let g = try? TextureResource(image: lum, options: .init(semantic: .color)) else {
                missing.insert(s)
                continue
            }
            AssetLedger.record(.texture, "fx sheet \(s.rawValue)")
            AssetLedger.record(.texture, "fx sheet glow \(s.rawValue)")
            alpha[s] = a
            glow[s] = g
        }
    }

    var builtCount: Int { alpha.count + glow.count }
}
