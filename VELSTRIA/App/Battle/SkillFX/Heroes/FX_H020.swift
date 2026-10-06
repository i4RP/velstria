import Foundation
import VelstriaCore

// スキル演出: H020 光矢のユナ（Duelist）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H020: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.98, 0.9), primary: RGB(1.0, 0.88, 0.45),
                                   secondary: RGB(1.0, 0.95, 0.75), accent: RGB(1.0, 0.88, 0.45),
                                   dark: RGB(0.16, 0.14, 0.06))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
