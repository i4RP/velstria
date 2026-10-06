import Foundation
import VelstriaCore

// スキル演出: H023 雷槍のトレン（Support）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H023: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.89, 0.97, 1.0), primary: RGB(0.4, 0.82, 1.0),
                                   secondary: RGB(0.73, 0.92, 1.0), accent: RGB(0.25, 0.64, 1.0),
                                   dark: RGB(0.06, 0.13, 0.16))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
