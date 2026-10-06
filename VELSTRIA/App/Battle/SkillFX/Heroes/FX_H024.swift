import Foundation
import VelstriaCore

// スキル演出: H024 夢織のノア（Assassin）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H024: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.98, 0.9, 1.0), primary: RGB(0.89, 0.45, 1.0),
                                   secondary: RGB(0.95, 0.75, 1.0), accent: RGB(0.84, 0.5, 1.0),
                                   dark: RGB(0.14, 0.06, 0.16))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
