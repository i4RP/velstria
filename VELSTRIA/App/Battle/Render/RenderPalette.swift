import CoreGraphics
import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。
// 手続きメッシュは頂点色の代わりに「パレットテクスチャ」の UV で色を指定する。
// 全ての静的装飾・構造物・ミニオン・モンスターが 2 つのマテリアル（lit / glow）を共有し、ドローコールと
// マテリアル切替を最小にする。上半分 = 単色スウォッチ（16×16px）、下半分 = 縦グラデーション用ランプ（8px 高）。

/// 単色スウォッチ。
enum Swatch: Int, CaseIterable {
    // 植物
    case grassDark, grass, grassLight, leafDark, leaf, leafLight, leafTeal, leafAutumn
    case bark, barkDark, moss, flowerPink, flowerYellow, reed, mushroom, mushroomCap
    // 岩・地面
    case rock, rockLight, rockDark, rockMoss, cliff, cliffDark, sand, dirt
    // 構造物
    case stone, stoneLight, stoneDark, marble, gold, goldDark, metal, metalDark
    case wood, woodDark, straw, cloth, rope, ink, white, black
    // チーム（青 / 赤。色覚サポート時は赤 → 橙）
    case blueMain, blueDark, blueLight, blueCloth, redMain, redDark, redLight, redCloth
    // 生物
    case skin, steel, leather, furBrown, furGrey, beastPurple, beastBelly, horn
    case wyrmScale, wyrmScaleDark, wyrmBelly, golemStone, golemStoneDark, colossusStone, colossusDark, bone
    // 発光（glow マテリアル用）
    case glowBlue, glowRed, glowGold, glowPurple, glowCyan, glowGreen, glowWhite, lanternWarm
    case glowBlueSoft, glowRedSoft, glowOrange, glowPink, waterDeep, waterLight, eye, runeTeal
    // 石畳
    case paving1, paving2, paving3, paving4
}

/// 縦グラデーション（t = 0 → 1）。
enum Ramp: Int, CaseIterable {
    case trunk, canopy, canopyTeal, canopyAutumn, rock, cliff, grassBlade, crystalBlue
    case crystalRed, crystalGold, crystalPurple, stonePillar, wyrm, colossus, pine, mossRock
}

/// メッシュ頂点の色指定。
enum PaletteColor: Equatable {
    case solid(Swatch)
    /// 形状の下端 = from、上端 = to の縦グラデーション。
    case ramp(Ramp, from: Float, to: Float)

    static func ramp(_ r: Ramp) -> PaletteColor { .ramp(r, from: 0, to: 1) }
}

enum PaletteLayout {
    static let size = 256
    static let swatchCell = 16
    static let swatchColumns = 16
    static let rampTop = 128
    static let rampHeight = 8

    /// true: テクスチャ座標の原点が画像の左下（USD 規約）。RealityKit はこの規約で CGImage を貼る。
    static let originBottomLeft = true

    /// 画像ピクセル座標（左上原点）→ UV。
    static func uv(pixelX: Float, pixelY: Float) -> SIMD2<Float> {
        let u = pixelX / Float(size)
        let v = pixelY / Float(size)
        return SIMD2(u, originBottomLeft ? 1 - v : v)
    }

    static func uv(_ s: Swatch) -> SIMD2<Float> {
        let col = s.rawValue % swatchColumns
        let row = s.rawValue / swatchColumns
        return uv(pixelX: Float(col * swatchCell) + Float(swatchCell) / 2,
                  pixelY: Float(row * swatchCell) + Float(swatchCell) / 2)
    }

    static func uv(_ r: Ramp, t: Float) -> SIMD2<Float> {
        // 端のテクセルを避ける（線形補間で隣のランプへ滲まないよう行の中心、列は 4px 内側）
        let x = 4 + max(0, min(1, t)) * Float(size - 8)
        return uv(pixelX: x, pixelY: Float(rampTop + r.rawValue * rampHeight) + Float(rampHeight) / 2)
    }

    static func uv(_ c: PaletteColor, t: Float) -> SIMD2<Float> {
        switch c {
        case .solid(let s): return uv(s)
        case .ramp(let r, let a, let b): return uv(r, t: a + (b - a) * t)
        }
    }
}

/// 色の定義（sRGB 0〜1）。
struct RGB: Equatable {
    var r: Double, g: Double, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    func mixed(_ o: RGB, _ t: Double) -> RGB {
        RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }

    func scaled(_ k: Double) -> RGB { RGB(min(1, r * k), min(1, g * k), min(1, b * k)) }

    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
    func uiColor(alpha: Double) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: alpha) }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    func cgColor(alpha: Double) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

/// チーム色（描画用）。色覚サポートでは赤チームを橙にする（Theme.teamColor と一致）。
struct TeamColors {
    var colorblind: Bool

    func main(_ team: Team) -> RGB {
        switch team {
        case .blue: return colorblind ? RGB(0.25, 0.55, 1.0) : RGB(0.28, 0.62, 1.0)
        case .red: return colorblind ? RGB(1.0, 0.62, 0.15) : RGB(1.0, 0.32, 0.36)
        case .neutral: return RGB(0.85, 0.80, 0.55)
        }
    }

    func dark(_ team: Team) -> RGB { main(team).mixed(RGB(0.05, 0.05, 0.12), 0.55) }
    func light(_ team: Team) -> RGB { main(team).mixed(RGB(1, 1, 1), 0.45) }

    /// 自ヒーローの HP バー・足元リング。
    static let selfColor = RGB(0.40, 0.95, 0.45)
    static let gold = RGB(0.98, 0.80, 0.38)
}

enum PaletteColors {
    static func rgb(_ s: Swatch, teams: TeamColors) -> RGB {
        switch s {
        case .grassDark: return RGB(0.18, 0.38, 0.20)
        case .grass: return RGB(0.29, 0.53, 0.25)
        case .grassLight: return RGB(0.47, 0.70, 0.31)
        case .leafDark: return RGB(0.11, 0.30, 0.19)
        case .leaf: return RGB(0.19, 0.45, 0.25)
        case .leafLight: return RGB(0.40, 0.66, 0.30)
        case .leafTeal: return RGB(0.13, 0.43, 0.40)
        case .leafAutumn: return RGB(0.80, 0.52, 0.22)
        case .bark: return RGB(0.40, 0.27, 0.18)
        case .barkDark: return RGB(0.25, 0.17, 0.12)
        case .moss: return RGB(0.33, 0.47, 0.24)
        case .flowerPink: return RGB(0.95, 0.55, 0.72)
        case .flowerYellow: return RGB(0.98, 0.86, 0.40)
        case .reed: return RGB(0.56, 0.66, 0.36)
        case .mushroom: return RGB(0.92, 0.88, 0.80)
        case .mushroomCap: return RGB(0.78, 0.30, 0.42)
        case .rock: return RGB(0.47, 0.47, 0.52)
        case .rockLight: return RGB(0.64, 0.64, 0.68)
        case .rockDark: return RGB(0.29, 0.29, 0.35)
        case .rockMoss: return RGB(0.36, 0.46, 0.32)
        case .cliff: return RGB(0.44, 0.40, 0.44)
        case .cliffDark: return RGB(0.26, 0.24, 0.30)
        case .sand: return RGB(0.80, 0.72, 0.53)
        case .dirt: return RGB(0.55, 0.42, 0.29)
        case .stone: return RGB(0.72, 0.70, 0.67)
        case .stoneLight: return RGB(0.86, 0.85, 0.82)
        case .stoneDark: return RGB(0.44, 0.43, 0.48)
        case .marble: return RGB(0.90, 0.89, 0.92)
        case .gold: return RGB(0.95, 0.76, 0.34)
        case .goldDark: return RGB(0.66, 0.48, 0.18)
        case .metal: return RGB(0.58, 0.61, 0.68)
        case .metalDark: return RGB(0.30, 0.32, 0.38)
        case .wood: return RGB(0.58, 0.40, 0.23)
        case .woodDark: return RGB(0.36, 0.24, 0.14)
        case .straw: return RGB(0.86, 0.73, 0.41)
        case .cloth: return RGB(0.86, 0.83, 0.76)
        case .rope: return RGB(0.70, 0.58, 0.38)
        case .ink: return RGB(0.10, 0.10, 0.14)
        case .white: return RGB(0.97, 0.97, 0.97)
        case .black: return RGB(0.05, 0.05, 0.07)
        case .blueMain: return teams.main(.blue)
        case .blueDark: return teams.dark(.blue)
        case .blueLight: return teams.light(.blue)
        case .blueCloth: return teams.main(.blue).mixed(RGB(0.1, 0.12, 0.3), 0.3)
        case .redMain: return teams.main(.red)
        case .redDark: return teams.dark(.red)
        case .redLight: return teams.light(.red)
        case .redCloth: return teams.main(.red).mixed(RGB(0.3, 0.08, 0.1), 0.3)
        case .skin: return RGB(0.93, 0.76, 0.60)
        case .steel: return RGB(0.66, 0.70, 0.76)
        case .leather: return RGB(0.44, 0.31, 0.21)
        case .furBrown: return RGB(0.52, 0.36, 0.25)
        case .furGrey: return RGB(0.55, 0.55, 0.60)
        case .beastPurple: return RGB(0.42, 0.30, 0.55)
        case .beastBelly: return RGB(0.78, 0.70, 0.62)
        case .horn: return RGB(0.90, 0.86, 0.74)
        case .wyrmScale: return RGB(0.30, 0.20, 0.52)
        case .wyrmScaleDark: return RGB(0.16, 0.10, 0.30)
        case .wyrmBelly: return RGB(0.66, 0.54, 0.86)
        case .golemStone: return RGB(0.50, 0.49, 0.50)
        case .golemStoneDark: return RGB(0.32, 0.31, 0.35)
        case .colossusStone: return RGB(0.66, 0.60, 0.50)
        case .colossusDark: return RGB(0.40, 0.35, 0.30)
        case .bone: return RGB(0.90, 0.87, 0.78)
        case .glowBlue: return RGB(0.45, 0.80, 1.0)
        case .glowRed: return teams.colorblind ? RGB(1.0, 0.70, 0.30) : RGB(1.0, 0.42, 0.40)
        case .glowGold: return RGB(1.0, 0.86, 0.45)
        case .glowPurple: return RGB(0.78, 0.55, 1.0)
        case .glowCyan: return RGB(0.50, 1.0, 0.95)
        case .glowGreen: return RGB(0.55, 1.0, 0.55)
        case .glowWhite: return RGB(1.0, 1.0, 1.0)
        case .lanternWarm: return RGB(1.0, 0.82, 0.50)
        case .glowBlueSoft: return RGB(0.60, 0.86, 1.0)
        case .glowRedSoft: return teams.colorblind ? RGB(1.0, 0.82, 0.55) : RGB(1.0, 0.66, 0.62)
        case .glowOrange: return RGB(1.0, 0.62, 0.25)
        case .glowPink: return RGB(1.0, 0.60, 0.85)
        case .waterDeep: return RGB(0.13, 0.36, 0.52)
        case .waterLight: return RGB(0.40, 0.75, 0.85)
        case .eye: return RGB(1.0, 0.95, 0.60)
        case .runeTeal: return RGB(0.35, 0.95, 0.85)
        case .paving1: return RGB(0.60, 0.59, 0.58)
        case .paving2: return RGB(0.66, 0.65, 0.63)
        case .paving3: return RGB(0.55, 0.55, 0.57)
        case .paving4: return RGB(0.70, 0.68, 0.64)
        }
    }

    static func ramp(_ r: Ramp, teams: TeamColors) -> (RGB, RGB) {
        switch r {
        case .trunk: return (RGB(0.20, 0.13, 0.09), RGB(0.46, 0.32, 0.21))
        case .canopy: return (RGB(0.09, 0.26, 0.16), RGB(0.42, 0.68, 0.30))
        case .canopyTeal: return (RGB(0.06, 0.25, 0.26), RGB(0.28, 0.62, 0.52))
        case .canopyAutumn: return (RGB(0.40, 0.20, 0.10), RGB(0.95, 0.66, 0.28))
        case .rock: return (RGB(0.25, 0.25, 0.31), RGB(0.68, 0.68, 0.72))
        case .cliff: return (RGB(0.20, 0.18, 0.24), RGB(0.56, 0.52, 0.54))
        case .grassBlade: return (RGB(0.10, 0.27, 0.14), RGB(0.55, 0.78, 0.34))
        case .crystalBlue: return (teams.dark(.blue), RGB(0.62, 0.88, 1.0))
        case .crystalRed: return (teams.dark(.red), teams.colorblind ? RGB(1.0, 0.86, 0.55) : RGB(1.0, 0.68, 0.64))
        case .crystalGold: return (RGB(0.55, 0.36, 0.10), RGB(1.0, 0.95, 0.70))
        case .crystalPurple: return (RGB(0.22, 0.10, 0.42), RGB(0.90, 0.78, 1.0))
        case .stonePillar: return (RGB(0.40, 0.39, 0.44), RGB(0.90, 0.89, 0.88))
        case .wyrm: return (RGB(0.14, 0.08, 0.28), RGB(0.50, 0.36, 0.78))
        case .colossus: return (RGB(0.34, 0.30, 0.26), RGB(0.78, 0.72, 0.60))
        case .pine: return (RGB(0.05, 0.20, 0.16), RGB(0.24, 0.52, 0.34))
        case .mossRock: return (RGB(0.28, 0.30, 0.30), RGB(0.42, 0.58, 0.32))
        }
    }

    /// パレット画像（256×256 RGBA）。
    static func makeImage(teams: TeamColors) -> CGImage? {
        let n = PaletteLayout.size
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // CG の原点は左下。画像ピクセル (x, y 下向き) → CG 矩形 (x, n - y - h)
        func fill(_ c: RGB, x: Int, y: Int, w: Int, h: Int) {
            ctx.setFillColor(c.cgColor)
            ctx.fill(CGRect(x: x, y: n - y - h, width: w, height: h))
        }
        fill(RGB(1, 0, 1), x: 0, y: 0, w: n, h: n)
        for s in Swatch.allCases {
            let col = s.rawValue % PaletteLayout.swatchColumns
            let row = s.rawValue / PaletteLayout.swatchColumns
            fill(rgb(s, teams: teams), x: col * PaletteLayout.swatchCell, y: row * PaletteLayout.swatchCell,
                 w: PaletteLayout.swatchCell, h: PaletteLayout.swatchCell)
        }
        for r in Ramp.allCases {
            let (a, b) = ramp(r, teams: teams)
            let y = PaletteLayout.rampTop + r.rawValue * PaletteLayout.rampHeight
            for x in 0..<n {
                let t = max(0, min(1, Double(x - 4) / Double(n - 8)))
                fill(a.mixed(b, t), x: x, y: y, w: 1, h: PaletteLayout.rampHeight)
            }
        }
        return ctx.makeImage()
    }
}

/// 共有マテリアル（レンダラー毎に 1 つ。チーム色・色覚設定を反映）。
@MainActor
final class RenderMaterials {
    let teams: TeamColors
    /// ライティングありのパレットマテリアル（地形装飾・構造物・ユニット）。
    let lit: RealityKit.Material
    /// 発光パレット（結晶・ランタン・ルーン）。
    let glow: RealityKit.Material
    /// 半透明の発光パレット（消えゆく結晶など）。
    let paletteTexture: TextureResource?

    private var unlitCache: [UInt64: UnlitMaterial] = [:]

    init(colorblind: Bool) {
        teams = TeamColors(colorblind: colorblind)
        var tex: TextureResource?
        if let img = PaletteColors.makeImage(teams: teams) {
            tex = try? TextureResource(image: img, options: .init(semantic: .color, mipmapsMode: .none))
        }
        paletteTexture = tex
        var pbr = PhysicallyBasedMaterial()
        if let tex {
            pbr.baseColor = .init(tint: .white, texture: .init(tex))
        } else {
            pbr.baseColor = .init(tint: UIColor(white: 0.6, alpha: 1))
        }
        pbr.roughness = .init(floatLiteral: 0.82)
        pbr.metallic = .init(floatLiteral: 0.0)
        pbr.specular = .init(floatLiteral: 0.25)
        lit = pbr
        var unlit = UnlitMaterial(applyPostProcessToneMap: false)
        if let tex {
            unlit.color = .init(tint: .white, texture: .init(tex))
        } else {
            unlit.color = .init(tint: .white)
        }
        glow = unlit
    }

    /// 単色の Unlit（トーンマップなし）。alpha < 1 で半透明。キャッシュ共有。
    func unlit(_ c: RGB, alpha: Double = 1, depthTest: Bool = true) -> UnlitMaterial {
        let key = Self.key(c, alpha: alpha, depthTest: depthTest)
        if let m = unlitCache[key] { return m }
        var m = UnlitMaterial(applyPostProcessToneMap: false)
        m.color = .init(tint: c.uiColor)
        if alpha < 0.999 {
            m.blending = .transparent(opacity: .init(floatLiteral: Float(alpha)))
        }
        if !depthTest {
            m.readsDepth = false
            m.writesDepth = false
            if alpha >= 0.999 { m.blending = .transparent(opacity: .init(floatLiteral: 1)) }
        } else if alpha < 0.999 {
            m.writesDepth = false
        }
        unlitCache[key] = m
        return m
    }

    private static func key(_ c: RGB, alpha: Double, depthTest: Bool) -> UInt64 {
        func q(_ v: Double) -> UInt64 { UInt64(max(0, min(255, (v * 255).rounded()))) }
        return q(c.r) | q(c.g) << 8 | q(c.b) << 16 | q(alpha) << 24 | (depthTest ? 1 : 0) << 32
    }

}
