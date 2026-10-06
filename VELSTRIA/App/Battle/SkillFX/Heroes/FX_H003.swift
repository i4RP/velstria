import Foundation
import VelstriaCore

// スキル演出: H003 月弓のフィリエル（Ranger）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H003: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.9, 0.99, 1.0), primary: RGB(0.45, 0.93, 1.0),
                                   secondary: RGB(0.75, 0.97, 1.0), accent: RGB(0.3, 1.0, 1.0),
                                   dark: RGB(0.06, 0.15, 0.16))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
