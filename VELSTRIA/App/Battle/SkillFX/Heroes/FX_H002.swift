import Foundation
import VelstriaCore

// スキル演出: H002 星弦のリラ（Duelist）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H002: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.9, 0.99, 1.0), primary: RGB(0.45, 0.93, 1.0),
                                   secondary: RGB(0.75, 0.97, 1.0), accent: RGB(1.0, 0.88, 0.45),
                                   dark: RGB(0.06, 0.15, 0.16))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
