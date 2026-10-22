import Foundation
import VelstriaCore

// 担当: hero-models（モーション）。ヒーロー固有の全身のモーション（スキルの詠唱・再使用の段・命中の後・通常攻撃）の目録。
// スキル演出の定義（FX_H0xx.motion）より優先する（演出と同じファイルに持たないのは、演出の担当とモーションの担当を分けるため）。
// 打撃のキーは sim の判定の時刻（KitTimes = HeroKits.fxValues = キットの Tune）に置く。各ヒーローの時刻の表は docs/vfx/H0xx.md
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
    /// キットの強い通常攻撃（SimEvent.empoweredAttack を出す攻撃: 三連突き・円撃）だけの全身のモーション。impact = 1 発目の命中
    /// （sim の attackReleased）。次の通常攻撃が強いとき（HeroKits.empoweredAttackReady）に、通常攻撃の代わりに 1 回だけ振る。
    /// nil = 強い通常攻撃も普段の通常攻撃のまま。
    static func empoweredAttack(_ m: MotionBuilder) -> MotionClip?
    /// 詠唱のモーションクリップ（HeroMotionSet.casts / stageCasts）の打撃を置く時刻（発動からの秒 = KitTimes の判定の時刻）。
    /// クリップの impact がこの秒に来るよう開始位置を決める。nil = 従来（呼び出しの castLead 秒後に打撃）。
    static func clipStrike(_ slot: SkillSlot, stage: Int) -> Float?
}

extension HeroMotionScript {
    static func cast(_ slot: SkillSlot, stage: Int, _ m: MotionBuilder) -> MotionClip? { nil }
    static func onHit(_ slot: SkillSlot, _ m: MotionBuilder) -> MotionClip? { nil }
    static func attacks(_ m: MotionBuilder) -> [MotionClip] { [] }
    static func empoweredAttack(_ m: MotionBuilder) -> MotionClip? { nil }
    static func clipStrike(_ slot: SkillSlot, stage: Int) -> Float? { nil }
}

enum HeroSkillMotions {
    /// H027・H032 は強い通常攻撃（三連突き・円撃）のモーションだけ（詠唱・普段の通常攻撃は従来どおり）。
    static let scripts: [String: HeroMotionScript.Type] = [
        "H027": Motion_H027.self,
        "H029": Motion_H029.self,
        "H032": Motion_H032.self,
        "H034": Motion_H034.self,
    ]

    static func script(_ heroID: String) -> HeroMotionScript.Type? { scripts[heroID] }

    /// スロット・段の詠唱（無ければ nil）。
    static func cast(heroID: String, slot: SkillSlot, stage: Int, builder: MotionBuilder) -> MotionClip? {
        guard slot != .passive, let s = scripts[heroID] else { return nil }
        return s.cast(slot, stage: stage, builder)
    }
}

/// キットの時刻・寸法（`HeroKits.fxValues` = 判定に使う Tune の値そのもの）。照準・判定・演出（FXSkillInfo）・音と同じ 1 つの
/// 読み取り口で、モーションの側に値を写さない（docs/vfx/RANGES.md）。無い key（キットが無効・名前の食い違い）は 0 を返して
/// `misses` に残す（AppTests/HeroFullBodyMotionTests が空であることを確かめる）。
struct KitTimes {
    let heroID: String
    let slot: SkillSlot
    let stage: Int
    private let values: [String: KitFXValue]
    /// 見つからなかった key（"H029 skill1 0 waveFirstDelay"）。
    nonisolated(unsafe) static var misses: Set<String> = []

    init(_ heroID: String, _ slot: SkillSlot, stage: Int = 0) {
        self.heroID = heroID
        self.slot = slot
        self.stage = stage
        var v: [String: KitFXValue] = [:]
        for x in HeroKits.fxValues(heroID: heroID, slot: slot, stage: stage) { v[x.key] = x }
        values = v
    }

    private func read(_ key: String, _ unit: KitFXValue.Unit) -> Double {
        guard let v = values[key], v.unit == unit else {
            KitTimes.misses.insert("\(heroID) \(slot) \(stage) \(key)")
            return 0
        }
        return v.value
    }

    /// 秒。
    func seconds(_ key: String) -> Float { Float(read(key, .seconds)) }
    /// sim の単位（100 = 1 m）。
    func distance(_ key: String) -> Double { read(key, .distance) }
    /// sim の単位 / 秒。
    func speed(_ key: String) -> Double { read(key, .speed) }
    func count(_ key: String) -> Int { Int(read(key, .count).rounded()) }
}
