import Foundation
import VelstriaCore

// スキル演出: H021 時砂のキロス（Ranger）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H021: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.94, 0.86), primary: RGB(1.0, 0.68, 0.2),
                                   secondary: RGB(1.0, 0.86, 0.64), accent: RGB(1.0, 0.81, 0.45),
                                   dark: RGB(0.16, 0.12, 0.06))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
