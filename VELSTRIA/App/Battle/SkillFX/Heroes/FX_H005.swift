import Foundation
import VelstriaCore

// スキル演出: H005 黒雷のヴォス（Support）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H005: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.95, 0.89, 1.0), primary: RGB(0.74, 0.4, 1.0),
                                   secondary: RGB(0.88, 0.73, 1.0), accent: RGB(0.69, 0.3, 1.0),
                                   dark: RGB(0.12, 0.06, 0.16))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
