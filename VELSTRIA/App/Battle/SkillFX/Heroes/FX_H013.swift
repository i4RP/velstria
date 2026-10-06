import Foundation
import VelstriaCore

// スキル演出: H013 獣刻のダガン（Vanguard）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H013: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.85, 0.85), primary: RGB(1.0, 0.15, 0.15),
                                   secondary: RGB(1.0, 0.62, 0.62), accent: RGB(1.0, 0.83, 0.5),
                                   dark: RGB(0.16, 0.06, 0.06))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
