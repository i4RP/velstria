import Foundation
import VelstriaCore

// スキル演出: H017 深淵鎖のモルド（Support）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H017: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.98, 0.88, 1.0), primary: RGB(0.87, 0.35, 1.0),
                                   secondary: RGB(0.94, 0.71, 1.0), accent: RGB(0.81, 0.4, 1.0),
                                   dark: RGB(0.14, 0.06, 0.16))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
