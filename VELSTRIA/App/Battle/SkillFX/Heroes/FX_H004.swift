import Foundation
import VelstriaCore

// スキル演出: H004 潮祈のミレア（Arcanist）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H004: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.88, 1.0, 1.0), primary: RGB(0.35, 1.0, 1.0),
                                   secondary: RGB(0.71, 1.0, 1.0), accent: RGB(1.0, 0.56, 0.5),
                                   dark: RGB(0.06, 0.16, 0.16))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
