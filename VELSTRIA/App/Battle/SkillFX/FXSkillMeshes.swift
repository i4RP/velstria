import Foundation
import VelstriaCore

// 担当: battle-renderer（スキル演出）。名簿の 10 体（H025〜H034）のスキル 1 つずつに、攻撃の瞬間の模型を 1 つ重ねる。
// 模型は参照画像（Tripo text-to-image）→ メッシュ（Tripo image-to-model）→ skill_mesh_to_fxm.py の .fxm
// （tools/vfx_assets/skill_meshes.json。FXShape の sk<番号><段>）。各ヒーローの演出（FX_H0xx）はそのままで、
// SkillFXCatalog.recipe が組み立てた後に段（stage）へ足す。模型は単位の大きさ（ground / forward は水平の半幅 1、upright は高さ 1）。
// H031 以外の 9 体は 2 枚目（second: 既存の模型と逆の段。詠唱の模型 ⇔ 着弾・命中の模型）を足し、攻撃の前後をどちらもメッシュで見せる。
// 1 スキルにつきメッシュ最大 2 枚・プールは FXShape ごとに 2（SkillFXPlayer.meshCapacity）で、上限の無い予約は増やさない。
// レシピのメッシュの合図の上限（SkillFXTests: スキル 20・奥義 28）を超える時は、同じ段の高画質だけの飾り（minQuality ≥ 1）を 1 つ外して
// 枠を空ける（外せる飾りが無ければ足さない）。

enum FXSkillMeshes {
    enum Stage { case cast, impact, hit }

    struct Spec {
        var shape: FXShape
        var stage: Stage = .impact
        var at: Float = 0
        var offset: SIMD3<Float> = .zero
        var size: SIMD3<Float>
        var grow: Float = 1.15
        var life: Float = 0.5
        var tint: FXTint = .primary
        var glow = true
        var alpha: Float = 0.9
        var spin: Float = 0
        var rise: Float = 0
        var advance: Float = 0
    }

    /// 模型の層を足す（名簿の 10 体のスキル 1・2・アルティメットだけ）。
    static func apply(heroID: String, slot: SkillSlot, info s: FXSkillInfo, to r: inout SkillFXRecipe) {
        let limit = slot == .ultimate ? 28 : 20
        if let x = spec(heroID: heroID, slot: slot, s), meshCues(r) < limit || freeSlot(x.stage, in: &r) { add(x, to: &r) }
        // 2 枚目は空のまま残す段（fillsEmptyPhases = false のレシピ）には足さない
        if let x = second(heroID: heroID, slot: slot, s), r.fillsEmptyPhases || !phase(x.stage, of: r).isEmpty,
           meshCues(r) < limit || freeSlot(x.stage, in: &r) {
            add(x, to: &r)
        }
    }

    private static func phase(_ stage: Stage, of r: SkillFXRecipe) -> [FXCue] {
        switch stage {
        case .cast: return r.cast
        case .impact: return r.impact
        case .hit: return r.hit
        }
    }

    private static func meshCues(_ r: SkillFXRecipe) -> Int {
        r.all.reduce(0) { n, c in
            switch c.element {
            case .mesh, .ribbon: return n + max(1, c.count)
            default: return n
            }
        }
    }

    /// 段の高画質だけの飾り（メッシュ・count 1）を後ろから 1 つ外す。
    private static func freeSlot(_ stage: Stage, in r: inout SkillFXRecipe) -> Bool {
        func drop(_ list: inout [FXCue]) -> Bool {
            guard let i = list.lastIndex(where: { c in
                guard c.minQuality >= 1, c.count <= 1, case .mesh(let m) = c.element else { return false }
                // 残りの数を示す組（H028 の環剣の刃）とスキルの模型は外さない
                return m.group == 0 && !m.shape.isSkillMesh
            }) else { return false }
            list.remove(at: i)
            return true
        }
        switch stage {
        case .cast: return drop(&r.cast) || drop(&r.impact) || drop(&r.hit)
        case .impact: return drop(&r.impact) || drop(&r.cast) || drop(&r.hit)
        case .hit: return drop(&r.hit) || drop(&r.impact) || drop(&r.cast)
        }
    }

    private static func add(_ x: Spec, to r: inout SkillFXRecipe) {
        var m = FXMesh.model(x.shape, nil, x.tint, size: x.size, sizeEnd: x.size * x.grow, life: x.life, alpha: x.alpha)
        m.spin = x.spin
        m.rise = x.rise
        m.advance = x.advance
        m.fadeIn = 0.06
        m.fadeOut = 0.55
        if x.glow { m = m.glowing() }
        let cue = FXCue.mesh(m, at: x.at, offset: x.offset)
        switch x.stage {
        case .cast: r.cast.append(cue)
        case .impact: r.impact.append(cue)
        case .hit: r.hit.append(cue)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func spec(heroID: String, slot: SkillSlot, _ s: FXSkillInfo) -> Spec? {
        let R = min(max(s.radius, 0.8), 3.0)
        let L = min(max(s.range, 2), 8)
        switch (heroID, slot) {
        // H025 ルミナ（月光）
        case ("H025", .skill1): return Spec(shape: .sk025s1, offset: [0, 0.06, 0], size: [1.1, 1.1, 1.1], grow: 1.3, life: 1.0, spin: 90)
        case ("H025", .skill2): return Spec(shape: .sk025s2, offset: [0, 2.6, 0], size: [0.55, 1.6, 0.55], grow: 1.0, life: 0.35,
                                            tint: .core, rise: -6)
        case ("H025", .ultimate): return Spec(shape: .sk025ult, stage: .cast, offset: [0, 2.4, 0], size: [1.4, 1.4, 1.4], life: 0.9)
        // H026 エウリア（青い稲妻）
        case ("H026", .skill1): return Spec(shape: .sk026s1, offset: [0, 0.8, -L * 0.5], size: [1.2, 0.6, L * 0.5], grow: 1.05,
                                            life: 0.3, tint: .core)
        case ("H026", .skill2): return Spec(shape: .sk026s2, offset: [0, 1.0, 0], size: [0.8, 0.8, 0.8], grow: 1.6, life: 0.5, spin: 180)
        case ("H026", .ultimate): return Spec(shape: .sk026ult, size: [2.5, 4.0, 2.5], grow: 1.1, life: 0.45, tint: .core)
        // H027 ジャルド（水色に光る槍）
        case ("H027", .skill1): return Spec(shape: .sk027s1, offset: [0, 1.0, -1.0], size: [1.8, 1.8, 1.8], grow: 1.2, life: 0.3)
        case ("H027", .skill2): return Spec(shape: .sk027s2, offset: [0, 1.1, 0.6], size: [0.6, 0.6, 1.6], grow: 1.1, life: 0.3,
                                            tint: .core, advance: 4)
        case ("H027", .ultimate): return Spec(shape: .sk027ult, size: [1.6, 1.6, 1.6], grow: 1.15, life: 1.0, alpha: 0.75, spin: 120,
                                              rise: 0.8)
        // H028 ザイル（赤い手裏剣の剣）
        case ("H028", .skill1): return Spec(shape: .sk028s1, stage: .cast, offset: [0, 1.0, 0], size: [1.4, 1.4, 1.4], grow: 1.25,
                                            life: 0.5, spin: 720)
        case ("H028", .skill2): return Spec(shape: .sk028s2, stage: .cast, offset: [0, 1.0, -1.5], size: [0.8, 0.6, 2.0], life: 0.35,
                                            tint: .secondary)
        case ("H028", .ultimate): return Spec(shape: .sk028ult, offset: [0, 0.3, 0], size: [1.8, 1.8, 1.8], grow: 1.2, life: 0.5)
        // H029 ボルグ（金の聖槌）
        case ("H029", .skill1): return Spec(shape: .sk029s1, offset: [0, 0, -3.0], size: [1.4, 1.0, 3.0], grow: 1.05, life: 0.8,
                                            tint: .secondary, glow: false)
        case ("H029", .skill2): return Spec(shape: .sk029s2, stage: .cast, offset: [0, 0.4, -0.8], size: [1.2, 1.2, 1.2], life: 0.5)
        case ("H029", .ultimate): return Spec(shape: .sk029ult, size: [R, R, R], grow: 1.08, life: 1.2, spin: 30)
        // H030 ライナ（魔砲）
        case ("H030", .skill1): return Spec(shape: .sk030s1, offset: [0, 1.0, 0.8], size: [0.5, 0.5, 1.0], grow: 1.3, life: 0.25,
                                            tint: .core, advance: 6)
        case ("H030", .skill2): return Spec(shape: .sk030s2, offset: [0, 0.8, 0], size: [1.3, 1.3, 1.3], grow: 1.4, life: 0.45, spin: 360)
        case ("H030", .ultimate): return Spec(shape: .sk030ult, stage: .cast, at: 0.55, offset: [0, 1.2, -3.5], size: [1.6, 1.6, 3.0],
                                              grow: 1.2, life: 0.4)
        // H031 オーリア（氷の結晶）
        case ("H031", .skill1): return Spec(shape: .sk031s1, size: [0.9, 2.2, 0.9], grow: 1.05, life: 0.9, glow: false)
        case ("H031", .skill2): return Spec(shape: .sk031s2, stage: .cast, at: 0.3, offset: [0, 0.3, -3.0], size: [2.0, 0.6, 3.0],
                                            grow: 1.1, life: 0.6)
        case ("H031", .ultimate): return Spec(shape: .sk031ult, size: [2.4, 1.6, 3.0], grow: 1.05, life: 1.0, glow: false)
        // H032 ディアス（奈落の紫と紅）
        case ("H032", .skill1): return Spec(shape: .sk032s1, offset: [0, 1.0, -1.2], size: [1.4, 1.4, 1.4], grow: 1.2, life: 0.3)
        case ("H032", .skill2): return Spec(shape: .sk032s2, stage: .cast, at: 0.4, offset: [0, 0.5, 0], size: [1.2, 1.2, 1.2],
                                            grow: 1.5, life: 0.4, tint: .secondary)
        case ("H032", .ultimate): return Spec(shape: .sk032ult, stage: .cast, offset: [0, 0, -L * 0.5], size: [1.2, 1.0, L * 0.5],
                                              grow: 1.05, life: 0.8, glow: false)
        // H033 ヴァルド（蒼い大剣と血）
        case ("H033", .skill1): return Spec(shape: .sk033s1, size: [1.9, 1.9, 1.9], grow: 1.1, life: 0.8, glow: false)
        case ("H033", .skill2): return Spec(shape: .sk033s2, offset: [0, 0.9, 0], size: [2.5, 2.5, 2.5], grow: 1.1, life: 0.35, spin: 720)
        case ("H033", .ultimate): return Spec(shape: .sk033ult, offset: [0, 1.2, 0], size: [1.2, 1.2, 1.2], grow: 1.3, life: 0.7,
                                              tint: .secondary)
        // H034 ゴルム（鉄の鎖鉤）
        case ("H034", .skill1): return Spec(shape: .sk034s1, stage: .hit, offset: [0, 0.8, 0], size: [0.6, 0.9, 0.6], life: 0.4,
                                            tint: .secondary, glow: false)
        case ("H034", .skill2): return Spec(shape: .sk034s2, offset: [0, 0.05, 0], size: [2.2, 2.2, 2.2], grow: 1.1, life: 0.8,
                                            glow: false, spin: 60)
        case ("H034", .ultimate): return Spec(shape: .sk034ult, size: [1.3, 1.3, 1.3], grow: 1.05, life: 1.2, glow: false)
        default: return nil
        }
    }

    /// 2 枚目（H031 以外の 9 体）。既存の模型と逆の段に置く。
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func second(heroID: String, slot: SkillSlot, _ s: FXSkillInfo) -> Spec? {
        let R = min(max(s.radius, 0.8), 3.0)
        let L = min(max(s.range, 2), 8)
        switch (heroID, slot) {
        // H025: 放つ瞬間の扇の 3 矢 / 着弾の霜の月花 / 隠密の羽の渦
        case ("H025", .skill1): return Spec(shape: .sk025s1b, stage: .cast, offset: [0, 1.2, -0.6], size: [0.9, 0.35, 1.2], grow: 1.1,
                                            life: 0.35, tint: .core, advance: 5)
        case ("H025", .skill2): return Spec(shape: .sk025s2b, at: 0.25, offset: [0, 0.05, 0], size: [R * 0.9, R * 0.9, R * 0.9], grow: 1.2,
                                            life: 0.8, spin: 30)
        case ("H025", .ultimate): return Spec(shape: .sk025ultb, stage: .cast, at: 0.15, size: [1.5, 2.6, 1.5], grow: 1.1, life: 1.1,
                                              alpha: 0.7, spin: 160, rise: 1.0)
        // H026: 命中の雷の星 / 衝撃の雷輪 / 落雷の焦げた紋
        case ("H026", .skill1): return Spec(shape: .sk026s1b, stage: .hit, offset: [0, 1.0, 0], size: [0.9, 0.9, 0.9], grow: 1.5,
                                            life: 0.3, tint: .core, spin: 90)
        case ("H026", .skill2): return Spec(shape: .sk026s2b, at: 0.1, offset: [0, 0.05, 0], size: [R * 1.1, R * 1.1, R * 1.1], grow: 1.35,
                                            life: 0.45, spin: 120)
        case ("H026", .ultimate): return Spec(shape: .sk026ultb, at: 0.05, offset: [0, 0.05, 0], size: [R * 1.2, R * 1.2, R * 1.2],
                                              grow: 1.15, life: 1.1, tint: .secondary, spin: 40)
        // H027: 竜の絡む槍 / 竜鱗の衝撃輪 / 立ち昇る竜気の柱
        case ("H027", .skill1): return Spec(shape: .sk027s1b, stage: .cast, offset: [0, 1.1, -0.4], size: [0.5, 0.5, 1.4], life: 0.35,
                                            tint: .core, advance: 3)
        case ("H027", .skill2): return Spec(shape: .sk027s2b, at: 0.12, offset: [0, 0.05, 0], size: [1.4, 1.4, 1.4], grow: 1.3, life: 0.45)
        case ("H027", .ultimate): return Spec(shape: .sk027ultb, stage: .cast, size: [1.3, 3.0, 1.3], grow: 1.1, life: 0.9, alpha: 0.75,
                                              spin: 200, rise: 0.5)
        // H028: 回る 6 本の剣 / 立った斬撃 / 降る巨剣
        case ("H028", .skill1): return Spec(shape: .sk028s1b, offset: [0, 1.0, 0], size: [1.8, 1.8, 1.8], life: 0.8, tint: .secondary,
                                            spin: 540)
        case ("H028", .skill2): return Spec(shape: .sk028s2b, offset: [0, 0.2, -0.8], size: [1.6, 1.8, 1.6], grow: 1.2, life: 0.3,
                                            tint: .core)
        case ("H028", .ultimate): return Spec(shape: .sk028ultb, stage: .cast, offset: [0, 2.5, -1.5], size: [0.9, 2.4, 0.9], life: 0.45,
                                              tint: .core, rise: -5)
        // H029: 振り下ろす聖槌 / 光の殻 / 降る十字剣
        case ("H029", .skill1): return Spec(shape: .sk029s1b, stage: .cast, offset: [0, 1.6, -1.0], size: [1.0, 1.5, 1.0], life: 0.4,
                                            tint: .secondary, rise: -2.5)
        case ("H029", .skill2): return Spec(shape: .sk029s2b, size: [1.6, 1.6, 1.6], grow: 1.35, life: 0.4, alpha: 0.7)
        case ("H029", .ultimate): return Spec(shape: .sk029ultb, stage: .cast, offset: [0, 3.0, 0], size: [1.4, 3.2, 1.4], life: 0.5,
                                              tint: .core, rise: -6)
        // H030: 命中の星の爆ぜ / 砲口の炎の花 / 砲の光線
        case ("H030", .skill1): return Spec(shape: .sk030s1b, stage: .hit, offset: [0, 1.0, 0], size: [1.0, 1.0, 1.0], grow: 1.6, life: 0.3,
                                            tint: .core)
        case ("H030", .skill2): return Spec(shape: .sk030s2b, stage: .cast, offset: [0, 1.1, -0.9], size: [0.8, 0.8, 0.8], grow: 1.5,
                                            life: 0.22, tint: .core)
        case ("H030", .ultimate): return Spec(shape: .sk030ultb, stage: .cast, at: 0.6, offset: [0, 1.2, -L * 0.5], size: [0.5, 0.5, L * 0.5],
                                              grow: 1.05, life: 0.5, tint: .core)
        // H032: 突き出す拳 / 足元の炎の渦 / 奈落の棘の爆ぜ
        case ("H032", .skill1): return Spec(shape: .sk032s1b, stage: .cast, offset: [0, 1.1, -0.5], size: [0.6, 0.6, 0.9], life: 0.25,
                                            tint: .secondary, advance: 4)
        case ("H032", .skill2): return Spec(shape: .sk032s2b, offset: [0, 0.05, 0], size: [1.6, 1.6, 1.6], grow: 1.3, life: 0.6, spin: 300)
        case ("H032", .ultimate): return Spec(shape: .sk032ultb, size: [1.6, 1.6, 1.6], grow: 1.3, life: 0.6, tint: .secondary)
        // H033: 突き立つ大剣 / 血の飛沫 / 吠える狼の頭
        case ("H033", .skill1): return Spec(shape: .sk033s1b, stage: .cast, offset: [0, 2.6, -1.2], size: [1.0, 2.2, 1.0], life: 0.4,
                                            tint: .core, rise: -6)
        case ("H033", .skill2): return Spec(shape: .sk033s2b, stage: .hit, offset: [0, 1.0, 0], size: [0.8, 0.8, 0.8], grow: 1.5, life: 0.35,
                                            tint: .secondary)
        case ("H033", .ultimate): return Spec(shape: .sk033ultb, stage: .cast, offset: [0, 2.2, 0.4], size: [1.8, 1.8, 1.8], grow: 1.2,
                                              life: 0.8, tint: .secondary, alpha: 0.8)
        // H034: 伸びる鎖 / 回る鉄球 / 命中の枷
        case ("H034", .skill1): return Spec(shape: .sk034s1b, stage: .cast, offset: [0, 1.0, -L * 0.5], size: [0.3, 0.3, L * 0.5], life: 0.35,
                                            tint: .secondary, glow: false)
        case ("H034", .skill2): return Spec(shape: .sk034s2b, offset: [0, 1.0, 0], size: [0.7, 0.7, 0.7], life: 0.6, glow: false, spin: 720)
        case ("H034", .ultimate): return Spec(shape: .sk034ultb, stage: .hit, offset: [0, 0.6, 0], size: [0.8, 0.8, 0.8], life: 1.0,
                                              tint: .secondary, glow: false)
        default: return nil
        }
    }
}
