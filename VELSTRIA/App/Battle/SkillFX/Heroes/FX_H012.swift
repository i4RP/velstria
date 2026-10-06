import Foundation
import VelstriaCore

// スキル演出: H012 玻璃歌のエリネ（Assassin）。
// TODO: 個別の演出とモーションを書く（空の段は FXGeneric の既定演出・既定の動き）。

enum FX_H012: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.9, 0.98, 1.0), primary: RGB(0.45, 0.87, 1.0),
                                   secondary: RGB(0.75, 0.94, 1.0), accent: RGB(0.5, 0.94, 1.0),
                                   dark: RGB(0.06, 0.14, 0.16))

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        SkillFXRecipe()
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {}
}
