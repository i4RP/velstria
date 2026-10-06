import Foundation
import VelstriaCore

// スキル演出: H006 月灯のセレン（Assassin）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H006: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.99, 0.9), primary: RGB(1.0, 0.94, 0.45),
                                   secondary: RGB(1.0, 0.98, 0.75), accent: RGB(1.0, 0.92, 0.5),
                                   dark: RGB(0.16, 0.15, 0.06))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
