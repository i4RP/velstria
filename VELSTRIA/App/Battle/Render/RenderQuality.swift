import Foundation

// 担当: battle-renderer。画質設定（GameSettings.graphicsQuality / frameRate）→ 描画パラメータ。

struct RenderQuality: Equatable {
    var level: GraphicsQuality
    /// 太陽光の影（high のみ）。
    var shadows: Bool
    /// 地面テクスチャの一辺（high 2048 / それ以外 1024）。
    var groundTextureSize: Int
    /// 霧テクスチャの一辺。
    var fogTextureSize: Int
    /// パーティクル数の倍率。
    var particleScale: Float
    /// 同時に存在できるパーティクル放出体の上限。
    var maxEmitters: Int
    /// 装飾（木・岩・草）の密度倍率。
    var decorationDensity: Float
    /// 投射物のパーティクル軌跡。
    var projectileTrails: Bool
    /// 環境パーティクル（泉・河川のきらめき）。
    var ambientParticles: Bool

    static func preset(_ q: GraphicsQuality) -> RenderQuality {
        switch q {
        case .low:
            return RenderQuality(level: q, shadows: false, groundTextureSize: 1024, fogTextureSize: 64,
                                 particleScale: 0.4, maxEmitters: 14, decorationDensity: 0.6,
                                 projectileTrails: false, ambientParticles: false)
        case .medium:
            return RenderQuality(level: q, shadows: false, groundTextureSize: 1024, fogTextureSize: 128,
                                 particleScale: 0.7, maxEmitters: 28, decorationDensity: 0.85,
                                 projectileTrails: true, ambientParticles: false)
        case .high:
            return RenderQuality(level: q, shadows: true, groundTextureSize: 2048, fogTextureSize: 192,
                                 particleScale: 1.0, maxEmitters: 44, decorationDensity: 1.0,
                                 projectileTrails: true, ambientParticles: true)
        }
    }

    /// 品質に応じたパーティクル数（最低 1）。
    func particles(_ base: Int) -> Int { max(1, Int((Float(base) * particleScale).rounded())) }
}

/// 描画に関係するユーザー設定のスナップショット。
struct RenderSettings: Equatable {
    var quality: RenderQuality
    var frameRate: Int
    var showDamageNumbers: Bool
    var colorblind: Bool

    init(quality: RenderQuality, frameRate: Int, showDamageNumbers: Bool, colorblind: Bool) {
        self.quality = quality
        self.frameRate = frameRate
        self.showDamageNumbers = showDamageNumbers
        self.colorblind = colorblind
    }

    init(_ s: GameSettings) {
        self.init(quality: .preset(s.graphicsQuality), frameRate: s.frameRate.rawValue,
                  showDamageNumbers: s.showDamageNumbers, colorblind: s.colorblindMode)
    }
}
