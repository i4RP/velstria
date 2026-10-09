import Foundation
import VelstriaCore

// 担当: スキル演出（VFX + 詠唱モーション）の目録。ヒーローごとの定義（FX_H001 … FX_H034）を束ねる。
// 1 ヒーロー = 1 ファイル（App/Battle/SkillFX/Heroes/FX_H0xx.swift）に、パレット・4 スロットの演出（パッシブ+Skill1/2+Ult）・3 スキルの詠唱モーション。
// レシピが空の段は FXGeneric（アーキタイプ別の既定演出）で補う。

/// 1 ヒーローのスキル演出の定義。
protocol HeroFXSet {
    /// 演出の色（芯・主・副・差し色・暗色）。
    static var palette: FXPalette { get }
    /// スロットの演出（passive の cast = パッシブ発動時の演出）。
    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe
    /// スロットの詠唱モーション（passive は呼ばれない）。何も積まなければ既定の動き。
    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder)
    /// 再使用の段（SkillCastEvent.stage >= 1。キット層）ごとの演出。nil = 段で変えない（共通の recipe を使う）。
    /// 段の演出で空の段（cast など）は、共通の演出（stage 0）で補う。
    static func recipe(_ slot: SkillSlot, stage: Int, _ s: FXSkillInfo) -> SkillFXRecipe?
    /// キットのパッシブのスタックを使い切った（>= 1 → 0、スキルの発動の直後）ときの「消費・解放」の演出。術者に追従して再生する。
    /// released = 消費したスタック数。nil（既定）= 何も出さない（スタックが増えたときの演出は recipe(.passive, _).cast のまま）。
    /// s は passive スロットの寸法。ボルグの防御・ゴルムのスタック消費など、積む演出と区別したいヒーローだけが実装する。
    static func passiveRelease(_ s: FXSkillInfo, released: Int) -> [FXCue]?
}

extension HeroFXSet {
    static func recipe(_ slot: SkillSlot, stage: Int, _ s: FXSkillInfo) -> SkillFXRecipe? { nil }
    static func passiveRelease(_ s: FXSkillInfo, released: Int) -> [FXCue]? { nil }
}

enum SkillFXCatalog {
    static let sets: [String: HeroFXSet.Type] = [
        "H001": FX_H001.self, "H002": FX_H002.self, "H003": FX_H003.self, "H004": FX_H004.self,
        "H005": FX_H005.self, "H006": FX_H006.self, "H007": FX_H007.self, "H008": FX_H008.self,
        "H009": FX_H009.self, "H010": FX_H010.self, "H011": FX_H011.self, "H012": FX_H012.self,
        "H013": FX_H013.self, "H014": FX_H014.self, "H015": FX_H015.self, "H016": FX_H016.self,
        "H017": FX_H017.self, "H018": FX_H018.self, "H019": FX_H019.self, "H020": FX_H020.self,
        "H021": FX_H021.self, "H022": FX_H022.self, "H023": FX_H023.self, "H024": FX_H024.self,
        "H025": FX_H025.self, "H026": FX_H026.self, "H027": FX_H027.self, "H028": FX_H028.self,
        "H029": FX_H029.self, "H030": FX_H030.self, "H031": FX_H031.self, "H032": FX_H032.self,
        "H033": FX_H033.self, "H034": FX_H034.self,
    ]

    /// 演出 ID（FX_SK_001_2）→ ヒーロー ID（H001）。
    static func heroID(forEffect effectID: String) -> String? {
        let parts = effectID.split(separator: "_")
        guard parts.count >= 4, parts[0] == "FX", parts[1] == "SK", parts[2].count == 3, Int(parts[2]) != nil else { return nil }
        return "H" + parts[2]
    }

    static func palette(_ heroID: String) -> FXPalette {
        sets[heroID]?.palette ?? FXPalette.from(RGB(0.6, 0.85, 1))
    }

    /// スキルの寸法（マスターデータ + 照準の規則から。m）。
    static func info(heroID: String, slot: SkillSlot, master: MasterData) -> FXSkillInfo {
        guard let hero = master.hero(heroID), let skill = master.skill(hero: heroID, slot: slot) else {
            return FXSkillInfo(heroID: heroID, slot: slot, archetype: .passive, radius: 1.5, range: 6)
        }
        let t = SkillCatalog.targeting(for: skill, hero: hero)
        let k = Float(Balance.unitsPerMeter)
        return FXSkillInfo(heroID: heroID, slot: slot, archetype: t.archetype, radius: max(0.6, Float(t.radius) / k),
                           range: max(1, Float(t.range) / k))
    }

    /// スロットの演出（ヒーローの定義 → 空の段は既定演出で補う）。
    static func recipe(heroID: String, slot: SkillSlot, master: MasterData) -> SkillFXRecipe {
        let s = info(heroID: heroID, slot: slot, master: master)
        let generic = FXGeneric.recipe(s)
        guard let set = sets[heroID] else { return generic }
        var r = set.recipe(slot, s)
        if r.cast.isEmpty { r.cast = generic.cast }
        if r.impact.isEmpty { r.impact = generic.impact }
        if r.travel.isEmpty { r.travel = generic.travel }
        if r.hit.isEmpty { r.hit = generic.hit }
        if r.telegraph.isEmpty { r.telegraph = generic.telegraph }
        return r
    }

    /// 再使用の段（1...）の演出。ヒーローが段で変える演出を持つときだけ（無ければ nil = 共通の演出を使う）。
    /// 空の段は共通の演出（stage 0）で補う。
    static func stageRecipe(heroID: String, slot: SkillSlot, stage: Int, master: MasterData) -> SkillFXRecipe? {
        guard stage > 0, let set = sets[heroID] else { return nil }
        let s = info(heroID: heroID, slot: slot, master: master)
        guard let r = set.recipe(slot, stage: stage, s) else { return nil }
        return merged(r, over: recipe(heroID: heroID, slot: slot, master: master))
    }

    /// キットのパッシブのスタックの消費・解放の演出（ヒーローが持つときだけ。無ければ nil）。released = 消費したスタック数。
    static func passiveRelease(heroID: String, released: Int, master: MasterData) -> [FXCue]? {
        guard let set = sets[heroID] else { return nil }
        return set.passiveRelease(info(heroID: heroID, slot: .passive, master: master), released: released)
    }

    /// 段の演出の空の段を共通の演出で補う。
    static func merged(_ stage: SkillFXRecipe, over base: SkillFXRecipe) -> SkillFXRecipe {
        var r = stage
        // hit を共通の演出から借りるときは、再生の単位（1 発ごとか）も共通のものに合わせる
        if r.hit.isEmpty { r.hitPerHit = base.hitPerHit }
        if r.cast.isEmpty { r.cast = base.cast }
        if r.impact.isEmpty { r.impact = base.impact }
        if r.travel.isEmpty { r.travel = base.travel }
        if r.hit.isEmpty { r.hit = base.hit }
        if r.telegraph.isEmpty { r.telegraph = base.telegraph }
        return r
    }

    /// 段の演出を探す最大の段（キットの再使用は 3 段まで）。
    static let maxStage = 3

    /// スロットの詠唱モーション（無ければ nil = 既定の動き）。
    static func motion(heroID: String, slot: SkillSlot, builder: MotionBuilder) -> MotionClip? {
        guard slot != .passive, let set = sets[heroID] else { return nil }
        var m = builder
        set.motion(slot, &m)
        guard !m.keys.isEmpty else { return nil }
        return m.build(recover: slot == .ultimate ? 0.35 : 0.25)
    }
}
