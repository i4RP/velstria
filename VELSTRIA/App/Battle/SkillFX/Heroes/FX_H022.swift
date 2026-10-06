import Foundation
import VelstriaCore

// スキル演出: H022 蒼爪のレア（Arcanist）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H022: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.87, 0.96, 1.0), primary: RGB(0.3, 0.79, 1.0),
                                   secondary: RGB(0.69, 0.91, 1.0), accent: RGB(0.2, 0.76, 1.0),
                                   dark: RGB(0.06, 0.13, 0.16))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
