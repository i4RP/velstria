import Foundation
import VelstriaCore

// 担当: battle-renderer（スキル演出）。名簿の 10 体（H025〜H034）のスキル 1 つずつに、攻撃の瞬間の模型を 1 つ重ねる。
// 模型は参照画像（Tripo text-to-image）→ メッシュ（Tripo image-to-model）→ skill_mesh_to_fxm.py の .fxm
// （tools/vfx_assets/skill_meshes.json。FXShape の sk<番号><段>）。各ヒーローの演出（FX_H0xx）はそのままで、
// SkillFXCatalog.recipe が組み立てた後に段（stage）へ足す。模型は単位の大きさ（ground / forward は水平の半幅 1、upright は高さ 1）。
// 1 スキルにつきメッシュ 1 枚・プールは FXShape ごとに 2（SkillFXPlayer.meshCapacity）で、上限の無い予約は増やさない。

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
        guard let x = spec(heroID: heroID, slot: slot, s) else { return }
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
}
