import Foundation
import VelstriaCore

// スキル演出: H015 戦鐘のヴァルカ（Ranger）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H015: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.96, 0.87), primary: RGB(1.0, 0.8, 0.3),
                                   secondary: RGB(1.0, 0.91, 0.69), accent: RGB(1.0, 0.7, 0.35),
                                   dark: RGB(0.16, 0.13, 0.06))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
