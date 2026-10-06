import Foundation
import VelstriaCore

// スキル演出: H010 焔冠のテッサ（Arcanist）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H010: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.91, 0.85), primary: RGB(1.0, 0.51, 0.15),
                                   secondary: RGB(1.0, 0.78, 0.62), accent: RGB(1.0, 0.46, 0.15),
                                   dark: RGB(0.16, 0.1, 0.06))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
