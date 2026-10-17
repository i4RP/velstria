import Foundation
import VelstriaCore

// 担当: hero-models（モーション）。ヒーロー固有の全身のモーション（スキルの詠唱・再使用の段・命中の後・通常攻撃）の目録。
// スキル演出の定義（FX_H0xx.motion）より優先する（演出と同じファイルに持たないのは、演出の担当とモーションの担当を分けるため）。
// 打撃のキーは sim の判定の時刻（KitMotionTimings = キットの Tune）に置く。各ヒーローの時刻の表は docs/vfx/H0xx.md
// 「モーション（打撃の時刻）」、仕組みは docs/HERO_MOTION.md「全身のモーション」。
// ここに無いヒーローは従来どおり（FX_H0xx.motion の詠唱、モーションクリップの通常攻撃）で、動きは変わらない。

/// 1 ヒーロー分の全身のモーション。nil / 空 = その動作は従来どおり。
protocol HeroMotionScript {
    /// スロットの詠唱（stage 0 = 発動、1... = 再使用の段）。
    static func cast(_ slot: SkillSlot, stage: Int, _ m: MotionBuilder) -> MotionClip?
    /// そのスキルが最初に当たった時（sim のダメージ）に続けて再生するモーション（詠唱中だけ）。
    static func onHit(_ slot: SkillSlot, _ m: MotionBuilder) -> MotionClip?
    /// 全身の通常攻撃（順に繰り返す。impact を sim の命中へ合わせる）。
    static func attacks(_ m: MotionBuilder) -> [MotionClip]
}

extension HeroMotionScript {
    static func cast(_ slot: SkillSlot, stage: Int, _ m: MotionBuilder) -> MotionClip? { nil }
    static func onHit(_ slot: SkillSlot, _ m: MotionBuilder) -> MotionClip? { nil }
    static func attacks(_ m: MotionBuilder) -> [MotionClip] { [] }
}

enum HeroSkillMotions {
    static let scripts: [String: HeroMotionScript.Type] = [
        "H029": Motion_H029.self,
        "H034": Motion_H034.self,
    ]

    static func script(_ heroID: String) -> HeroMotionScript.Type? { scripts[heroID] }

    /// スロット・段の詠唱（無ければ nil）。
    static func cast(heroID: String, slot: SkillSlot, stage: Int, builder: MotionBuilder) -> MotionClip? {
        guard slot != .passive, let s = scripts[heroID] else { return nil }
        return s.cast(slot, stage: stage, builder)
    }
}

/// sim の時刻（秒、Double）→ モーションの時刻（Float）。
@inline(__always) func motionTime(_ seconds: Double) -> Float { Float(seconds) }
