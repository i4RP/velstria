import Foundation
import VelstriaCore

// スキル演出: H009 機巧士オリン（Ranger）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H009: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.93, 0.84), primary: RGB(1.0, 0.59, 0.1),
                                   secondary: RGB(1.0, 0.81, 0.59), accent: RGB(1.0, 0.59, 0.3),
                                   dark: RGB(0.16, 0.12, 0.06))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
