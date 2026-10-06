import Foundation
import VelstriaCore

// スキル演出: H007 岩脈のガルク（Vanguard）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H007: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.92, 0.84), primary: RGB(1.0, 0.53, 0.1),
                                   secondary: RGB(1.0, 0.79, 0.59), accent: RGB(1.0, 0.74, 0.5),
                                   dark: RGB(0.16, 0.11, 0.06))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
