import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: hero-models。配色（パレット）・スキン解決・マテリアルの共有キャッシュ。

/// メッシュの面が参照するマテリアル番号（ModelEntity.materials の添字）。
enum HeroMat: UInt32, CaseIterable {
    case primary      // 基調色（Theme.heroHue）
    case secondary    // 基調色の暗色
    case metal        // 金属・石・骨などの素材
    case skin
    case dark         // 革・ブーツ・下地
    case accent       // モチーフ色（補色系）
    case glow         // 発光（ルーン・結晶）
    case hair
    case eye
    case cloth        // 明るい布
    case shine        // 瞳のハイライト
    case veil         // 半透明の布（霧・硝子）
}

/// 色相・彩度・明度（0...1）。
struct HSB: Equatable {
    var h: Double
    var s: Double
    var b: Double

    init(_ h: Double, _ s: Double, _ b: Double) {
        self.h = h
        self.s = s
        self.b = b
    }

    var uiColor: UIColor {
        let hue = h - floor(h)
        return UIColor(hue: CGFloat(hue), saturation: CGFloat(min(1, max(0, s))), brightness: CGFloat(min(1, max(0, b))), alpha: 1)
    }

    func hueShifted(_ d: Double) -> HSB { HSB(h + d, s, b) }
    func with(s: Double? = nil, b: Double? = nil) -> HSB { HSB(h, s ?? self.s, b ?? self.b) }
}

enum MetalKind: Equatable {
    case silver, gold, bronze, iron, obsidian, stone, bone, brass, platinum

    var color: HSB {
        switch self {
        case .platinum: return HSB(0.58, 0.05, 0.99)
        case .silver: return HSB(0.60, 0.07, 0.90)
        case .gold: return HSB(0.12, 0.62, 0.98)
        case .bronze: return HSB(0.07, 0.62, 0.78)
        case .iron: return HSB(0.60, 0.10, 0.62)
        case .obsidian: return HSB(0.72, 0.25, 0.26)
        case .stone: return HSB(0.08, 0.14, 0.58)
        case .bone: return HSB(0.11, 0.16, 0.94)
        case .brass: return HSB(0.11, 0.55, 0.85)
        }
    }

    /// (roughness, metallic)
    var surface: (Float, Float) {
        switch self {
        case .silver, .gold, .brass: return (0.30, 0.85)
        case .platinum: return (0.22, 0.75)
        case .bronze: return (0.38, 0.8)
        case .iron: return (0.42, 0.75)
        case .obsidian: return (0.22, 0.6)
        case .stone: return (0.9, 0.0)
        case .bone: return (0.7, 0.0)
        }
    }

    var swapped: MetalKind {
        switch self {
        case .gold, .brass, .bronze: return .silver
        case .silver, .iron, .platinum: return .gold
        default: return self
        }
    }
}

enum SkinTone: Equatable {
    case fair, tan, deep, pale, ashen

    var color: HSB {
        switch self {
        case .fair: return HSB(0.07, 0.26, 1.0)
        case .tan: return HSB(0.07, 0.40, 0.88)
        case .deep: return HSB(0.06, 0.50, 0.58)
        case .pale: return HSB(0.62, 0.07, 0.97)
        case .ashen: return HSB(0.40, 0.10, 0.74)
        }
    }
}

/// ヒーロー 1 体分の配色。
struct HeroPalette: Equatable {
    var primary: HSB
    var secondary: HSB
    var metal: HSB
    var metalKind: MetalKind
    var skin: HSB
    var dark: HSB
    var accent: HSB
    var glow: HSB
    var hair: HSB
    var cloth: HSB
    var veil: HSB
    var glowIntensity: Float = 2.2
    /// Epic スキンの縁取り発光（0 = なし）。
    var trimGlow: Float = 0
    /// Epic スキンのオーラ粒子。
    var aura = false
    /// 深いフードの奥で光る目。
    var glowingEyes = false
}

// MARK: - スキン

/// 解決済みのスキン情報。
struct HeroSkinInfo: Equatable {
    /// nil = 既定スキン。
    let cosmeticID: String?
    /// 0 = 既定、1... = そのヒーローの HeroSkin を ID 順に並べた番号。
    let variant: Int
    let rarity: Rarity

    var isEpic: Bool { rarity == .epic || rarity == .mythic }

    static let standard = HeroSkinInfo(cosmeticID: nil, variant: 0, rarity: .common)
}

enum HeroSkins {
    /// ヒーローの HeroSkin コスメ（ID 昇順）。
    static func skins(for heroID: String, master: MasterData) -> [CosmeticDef] {
        master.cosmetics.filter { $0.type == .heroSkin && $0.heroID == heroID }
    }

    /// skinID を解決する。未知・他ヒーロー用・スキン以外は既定スキン。
    static func resolve(heroID: String, skinID: String?, master: MasterData) -> HeroSkinInfo {
        guard let skinID, let def = master.cosmetic(skinID), def.type == .heroSkin, def.heroID == heroID else {
            return .standard
        }
        let list = skins(for: heroID, master: master)
        let index = (list.firstIndex { $0.cosmeticID == skinID } ?? 0) + 1
        return HeroSkinInfo(cosmeticID: skinID, variant: index, rarity: def.rarity)
    }

    /// 表示用のスキン名（ギャラリー用）。
    static func variantName(_ variant: Int) -> String {
        switch variant {
        case 0: return L("既定", "Default")
        case 1: return L("反転星", "Inverse Star")
        case 2: return L("夜影", "Nightshade")
        case 3: return L("天光", "Celestial")
        default: return L("異彩 \(variant)", "Variant \(variant)")
        }
    }
}

// MARK: - パレット生成

enum HeroPalettes {
    /// 既定パレット（基調色は Theme.heroHue、アクセントはモチーフ色）。
    static func base(heroID: String, blueprint bp: HeroBlueprint) -> HeroPalette {
        let h = Theme.heroHue(heroID)
        // 黄緑系は彩度が強く出るので抑える
        let yg = max(0, 1 - abs(h - 0.22) / 0.12)
        return HeroPalette(
            primary: HSB(h, 0.66 - 0.14 * yg, 0.90 - 0.06 * yg),
            secondary: HSB(h + 0.015, 0.60, 0.46),
            metal: bp.metal.color,
            metalKind: bp.metal,
            skin: bp.skin.color,
            dark: HSB(h, 0.30, 0.22),
            accent: bp.accent,
            glow: bp.glow,
            hair: bp.hairColor,
            cloth: HSB(h, 0.10, 0.96),
            veil: HSB(bp.accent.h, 0.22, 1.0),
            glowingEyes: bp.glowingEyes)
    }

    /// スキン適用後のパレット。
    static func palette(heroID: String, blueprint bp: HeroBlueprint, skin: HeroSkinInfo) -> HeroPalette {
        var p = base(heroID: heroID, blueprint: bp)
        let h = p.primary.h
        switch skin.variant {
        case 0:
            break
        case 1:
            // 反転星: 補色への色替え + 金銀反転
            p.primary = HSB(h + 0.5, 0.62, 0.88)
            p.secondary = HSB(h + 0.515, 0.58, 0.44)
            p.dark = HSB(h + 0.5, 0.3, 0.2)
            p.accent = p.accent.hueShifted(0.5)
            p.glow = p.glow.hueShifted(0.5)
            p.cloth = HSB(h + 0.5, 0.1, 0.96)
            p.metalKind = bp.metal.swapped
            p.metal = p.metalKind.color
            p.hair = p.hair.hueShifted(0.33)
        case 2:
            // 夜影: 黒曜の鎧 + 金のアクセント
            p.primary = HSB(h, 0.50, 0.34)
            p.secondary = HSB(h, 0.45, 0.16)
            p.dark = HSB(h, 0.2, 0.09)
            p.cloth = HSB(h, 0.25, 0.55)
            p.metalKind = .obsidian
            p.metal = HSB(h, 0.25, 0.4)
            p.accent = HSB(0.12, 0.72, 1.0)
            p.glow = p.glow.with(s: min(1, p.glow.s + 0.2), b: 1)
            p.hair = HSB(p.hair.h, 0.25, 0.25)
        case 3:
            // 天光: 白と金、水色の発光
            p.primary = HSB(h, 0.10, 0.97)
            p.secondary = HSB(h + 0.08, 0.40, 0.82)
            p.dark = HSB(h, 0.22, 0.46)
            p.cloth = HSB(0.13, 0.25, 1.0)
            p.metalKind = .platinum
            p.metal = MetalKind.platinum.color
            p.accent = HSB(0.12, 0.6, 1.0)
            p.glow = HSB(0.52, 0.55, 1.0)
            p.hair = HSB(0.13, 0.18, 1.0)
        default:
            let d = 0.29 * Double(skin.variant)
            p.primary = p.primary.hueShifted(d)
            p.secondary = p.secondary.hueShifted(d)
            p.dark = p.dark.hueShifted(d)
            p.accent = p.accent.hueShifted(d)
            p.glow = p.glow.hueShifted(d)
        }
        p.veil = HSB(p.accent.h, 0.22, 1.0)
        if skin.isEpic {
            p.glowIntensity = 3.2
            p.trimGlow = 0.32
            p.aura = true
        }
        return p
    }
}

// MARK: - マテリアル

@MainActor
enum HeroMaterialLibrary {
    private static var cache: [String: [RealityKit.Material]] = [:]
    private static var unlitCache: [String: RealityKit.Material] = [:]

    /// パレットからマテリアル配列（HeroMat の順）を作る。同じキーは共有する。
    static func materials(key: String, palette p: HeroPalette) -> [RealityKit.Material] {
        if let m = cache[key] { return m }
        var list: [RealityKit.Material] = []
        list.reserveCapacity(HeroMat.allCases.count)
        for slot in HeroMat.allCases {
            list.append(make(slot, p))
        }
        cache[key] = list
        return list
    }

    private static func pbr(_ c: HSB, rough: Float, metal: Float, lift: Float, emissive: HSB? = nil,
                            intensity: Float = 0, clearcoat: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c.uiColor)
        m.roughness = .init(floatLiteral: rough)
        m.metallic = .init(floatLiteral: metal)
        if let e = emissive, intensity > 0 {
            m.emissiveColor = .init(color: e.uiColor)
            m.emissiveIntensity = intensity
        } else if lift > 0 {
            // 上方カメラでも暗部が沈まないよう、基調色をわずかに自己発光させる
            m.emissiveColor = .init(color: c.uiColor)
            m.emissiveIntensity = lift
        }
        if clearcoat > 0 {
            m.clearcoat = .init(floatLiteral: clearcoat)
            m.clearcoatRoughness = .init(floatLiteral: 0.2)
        }
        return m
    }

    private static func make(_ slot: HeroMat, _ p: HeroPalette) -> RealityKit.Material {
        let (mr, mm) = p.metalKind.surface
        switch slot {
        case .primary:
            return pbr(p.primary, rough: 0.55, metal: 0.05, lift: 0.16, clearcoat: 0.25)
        case .secondary:
            return pbr(p.secondary, rough: 0.6, metal: 0.05, lift: 0.14)
        case .metal:
            if p.trimGlow > 0 {
                return pbr(p.metal, rough: mr, metal: mm, lift: 0, emissive: p.glow, intensity: p.trimGlow)
            }
            return pbr(p.metal, rough: mr, metal: mm, lift: 0.12, clearcoat: mm > 0.5 ? 0.4 : 0)
        case .skin:
            return pbr(p.skin, rough: 0.72, metal: 0, lift: 0.22)
        case .dark:
            return pbr(p.dark, rough: 0.72, metal: 0.05, lift: 0.1)
        case .accent:
            if p.trimGlow > 0 {
                return pbr(p.accent, rough: 0.4, metal: 0.1, lift: 0, emissive: p.accent, intensity: 0.45 + p.trimGlow * 0.5)
            }
            return pbr(p.accent, rough: 0.42, metal: 0.1, lift: 0.2, clearcoat: 0.3)
        case .glow:
            return pbr(p.glow.with(s: p.glow.s * 0.7), rough: 0.3, metal: 0, lift: 0, emissive: p.glow, intensity: p.glowIntensity)
        case .hair:
            return pbr(p.hair, rough: 0.5, metal: 0.05, lift: 0.16, clearcoat: 0.35)
        case .eye:
            if p.glowingEyes {
                return pbr(p.glow, rough: 0.3, metal: 0, lift: 0, emissive: p.glow, intensity: 3)
            }
            return pbr(HSB(0.65, 0.35, 0.12), rough: 0.15, metal: 0, lift: 0, clearcoat: 1)
        case .cloth:
            return pbr(p.cloth, rough: 0.8, metal: 0, lift: 0.14)
        case .shine:
            return pbr(HSB(0, 0, 1), rough: 0.2, metal: 0, lift: 0, emissive: HSB(0, 0, 1), intensity: 1.2)
        case .veil:
            var m = pbr(p.veil, rough: 0.6, metal: 0, lift: 0, emissive: p.veil, intensity: 0.35)
            m.blending = .transparent(opacity: .init(floatLiteral: 0.55))
            m.faceCulling = .none
            return m
        }
    }

    /// 発光エフェクト用の非照明マテリアル（半透明）。
    static func unlit(_ c: HSB, opacity: Float) -> RealityKit.Material {
        let key = String(format: "%.3f/%.3f/%.3f/%.2f", c.h - floor(c.h), c.s, c.b, opacity)
        if let m = unlitCache[key] { return m }
        var m = UnlitMaterial(color: c.uiColor)
        if opacity < 0.999 {
            m.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        unlitCache[key] = m
        return m
    }

    private static var spriteCache: [String: RealityKit.Material] = [:]

    /// 放射グラデーション（中心が白く、縁で透明）。
    private static let glowTexture: TextureResource? = {
        let size = 64
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0.55).cgColor,
                      UIColor(white: 1, alpha: 0.12).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
        let locations: [CGFloat] = [0, 0.18, 0.55, 1]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else {
            return nil
        }
        let c = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size) / 2, options: [])
        guard let image = ctx.makeImage() else { return nil }
        return try? TextureResource(image: image, withName: "hero.glow", options: .init(semantic: .color))
    }()

    /// 発光スプライト用マテリアル（色ごとに共有）。
    static func glowSprite(_ c: HSB) -> RealityKit.Material {
        let key = String(format: "%.3f/%.3f/%.3f", c.h - floor(c.h), c.s, c.b)
        if let m = spriteCache[key] { return m }
        var m = UnlitMaterial(color: c.with(s: c.s * 0.8, b: 1).uiColor)
        if let tex = glowTexture {
            m.color = .init(tint: c.with(s: c.s * 0.8, b: 1).uiColor, texture: .init(tex))
            m.blending = .transparent(opacity: .init(scale: 1, texture: .init(tex)))
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: 0.5))
        }
        spriteCache[key] = m
        return m
    }

    static func unlit(_ color: UIColor, opacity: Float) -> RealityKit.Material {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return unlit(HSB(Double(h), Double(s), Double(b)), opacity: opacity)
    }
}
