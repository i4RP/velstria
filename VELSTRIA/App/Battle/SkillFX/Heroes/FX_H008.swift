import Foundation
import VelstriaCore

// スキル演出: H008 風標のニア（Duelist）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H008: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.9, 1.0, 0.98), primary: RGB(0.45, 1.0, 0.9),
                                   secondary: RGB(0.75, 1.0, 0.96), accent: RGB(0.38, 1.0, 0.93),
                                   dark: RGB(0.06, 0.16, 0.14))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
