import Foundation
import VelstriaCore

// スキル演出: H018 花星のセリア（Assassin）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H018: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.9, 0.95), primary: RGB(1.0, 0.45, 0.71),
                                   secondary: RGB(1.0, 0.75, 0.87), accent: RGB(1.0, 0.5, 0.71),
                                   dark: RGB(0.16, 0.06, 0.11))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
