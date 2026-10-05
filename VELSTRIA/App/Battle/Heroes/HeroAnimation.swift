import Foundation
import simd
import VelstriaCore

// 担当: hero-models。手続きアニメーション（姿勢の合成と状態間ブレンド）。
// 姿勢は Float だけの値型で、毎フレームの評価はヒープ確保なしで行う。
// 角度の符号: pitch + = 前へ（腕・脚は前方へ振る、胴・頭は前傾）。武器角 θ は胴座標の絶対角で 0 = 真上、-π/2 = 前方。

struct ArmPose {
    var pitch: Float = 0
    var out: Float = 0
    var yaw: Float = 0
    var elbow: Float = 0

    static func mix(_ a: ArmPose, _ b: ArmPose, _ t: Float) -> ArmPose {
        ArmPose(pitch: a.pitch + (b.pitch - a.pitch) * t, out: a.out + (b.out - a.out) * t,
                yaw: a.yaw + (b.yaw - a.yaw) * t, elbow: a.elbow + (b.elbow - a.elbow) * t)
    }
}

struct LegPose {
    var pitch: Float = 0
    var out: Float = 0
    var knee: Float = 0

    static func mix(_ a: LegPose, _ b: LegPose, _ t: Float) -> LegPose {
        LegPose(pitch: a.pitch + (b.pitch - a.pitch) * t, out: a.out + (b.out - a.out) * t, knee: a.knee + (b.knee - a.knee) * t)
    }
}

struct HeroPose {
    var offset = SIMD3<Float>(0, 0, 0)
    var pitch: Float = 0
    var roll: Float = 0
    var yaw: Float = 0
    var hipsDrop: Float = 0
    var hipsYaw: Float = 0
    var hipsRoll: Float = 0
    var torsoPitch: Float = 0
    var torsoYaw: Float = 0
    var torsoRoll: Float = 0
    var headPitch: Float = 0
    var headYaw: Float = 0
    var headRoll: Float = 0
    var armR = ArmPose()
    var armL = ArmPose()
    var legR = LegPose()
    var legL = LegPose()
    var weaponR: Float = 0
    var weaponL: Float = 0
    var cape: Float = 0
    var wings: Float = 0
    var glow: Float = 0
    var ring: Float = 0
    var opacity: Float = 1

    @inline(__always) private static func f(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

    /// 全項目の線形補間。
    static func mix(_ a: HeroPose, _ b: HeroPose, _ t: Float) -> HeroPose {
        var p = mixUpper(a, b, t)
        p.offset = a.offset + (b.offset - a.offset) * t
        p.pitch = f(a.pitch, b.pitch, t)
        p.roll = f(a.roll, b.roll, t)
        p.yaw = f(a.yaw, b.yaw, t)
        p.hipsDrop = f(a.hipsDrop, b.hipsDrop, t)
        p.hipsYaw = f(a.hipsYaw, b.hipsYaw, t)
        p.hipsRoll = f(a.hipsRoll, b.hipsRoll, t)
        p.legR = LegPose.mix(a.legR, b.legR, t)
        p.legL = LegPose.mix(a.legL, b.legL, t)
        p.cape = f(a.cape, b.cape, t)
        p.opacity = f(a.opacity, b.opacity, t)
        return p
    }

    /// 上半身（胴・頭・腕・武器・発光）だけ補間し、下半身は a を使う。
    static func mixUpper(_ a: HeroPose, _ b: HeroPose, _ t: Float) -> HeroPose {
        var p = a
        p.torsoPitch = f(a.torsoPitch, b.torsoPitch, t)
        p.torsoYaw = f(a.torsoYaw, b.torsoYaw, t)
        p.torsoRoll = f(a.torsoRoll, b.torsoRoll, t)
        p.headPitch = f(a.headPitch, b.headPitch, t)
        p.headYaw = f(a.headYaw, b.headYaw, t)
        p.headRoll = f(a.headRoll, b.headRoll, t)
        p.armR = ArmPose.mix(a.armR, b.armR, t)
        p.armL = ArmPose.mix(a.armL, b.armL, t)
        p.weaponR = f(a.weaponR, b.weaponR, t)
        p.weaponL = f(a.weaponL, b.weaponL, t)
        p.wings = f(a.wings, b.wings, t)
        p.glow = f(a.glow, b.glow, t)
        p.ring = f(a.ring, b.ring, t)
        return p
    }
}

// MARK: - イージング

@inline(__always) func clamp01(_ x: Float) -> Float { min(1, max(0, x)) }
@inline(__always) func smooth01(_ x: Float) -> Float { let t = clamp01(x); return t * t * (3 - 2 * t) }
@inline(__always) func easeOut(_ x: Float) -> Float { let t = clamp01(x); return 1 - (1 - t) * (1 - t) }
@inline(__always) func easeIn(_ x: Float) -> Float { let t = clamp01(x); return t * t }

/// 予備動作 → 打撃 → 戻りの 3 段クリップ（上半身）。
struct ActionClip {
    var windup: HeroPose
    var strike: HeroPose
    var windupTime: Float
    var strikeTime: Float
    var total: Float

    /// base（現在の下半身と上半身の基準）から評価する。
    func evaluate(base: HeroPose, t: Float) -> HeroPose {
        let upper: HeroPose
        if t < windupTime {
            upper = HeroPose.mixUpper(base, windup, easeOut(t / windupTime))
        } else if t < windupTime + strikeTime {
            upper = HeroPose.mixUpper(windup, strike, easeIn((t - windupTime) / strikeTime))
        } else if t < total {
            upper = HeroPose.mixUpper(strike, base, smooth01((t - windupTime - strikeTime) / (total - windupTime - strikeTime)))
        } else {
            return base
        }
        return HeroPose.mixUpper(base, upper, 1)
    }
}

/// ヒーロー固有の姿勢パラメータ（設計図から一度だけ作る）。
struct HeroMotionProfile {
    var rest = HeroPose()
    var runSwingR: Float = 1
    var runSwingL: Float = 1
    var legSwing: Float = 1
    var attack: ActionClip
    /// 二刀の左手版（交互に振る）。
    var attackAlt: ActionClip?
    /// スキル詠唱（Skill1 / Skill2 / Skill3 / Ultimate）。スキル固有のモーション（SkillFXCatalog）が無ければ既定の 3 段。
    var casts: [MotionClip]
    var twoHanded: Bool
    var bowHold: Bool
    /// 盾持ち（詠唱・勝利でも盾を胸の前に保つ）。
    var shieldHold: Bool
    /// 長柄（杖・槍・大槌）は帰還中も立てて持つ。
    var longWeapon: Bool

    init(blueprint bp: HeroBlueprint, metrics m: BodyMetrics, heroID: String? = nil) {
        var r = HeroPose()
        r.armR = ArmPose(pitch: 0.12, out: m.armRestOut, yaw: 0, elbow: 0.3)
        r.armL = ArmPose(pitch: 0.12, out: m.armRestOut, yaw: 0, elbow: 0.3)
        r.weaponR = -0.9
        r.weaponL = 0
        // 足を肩幅より少し開いた、どっしり構えた立ち姿
        r.legR = LegPose(pitch: 0, out: bp.build == .heavy ? 0.12 : 0.09, knee: 0.08)
        r.legL = r.legR
        r.cape = 0.05
        r.wings = 0.2
        twoHanded = bp.twoHanded
        bowHold = bp.offhand == .ashBow || bp.offhand == .lightBow || bp.offhand == .harpBow
        shieldHold = bp.offhand == .gateShield || bp.offhand == .hideShield
        switch bp.attack {
        case .staff, .thrust, .heavySwing: longWeapon = true
        default: longWeapon = false
        }
        legSwing = bp.build == .robed ? 0.55 : 1
        switch bp.attack {
        case .slash:
            r.armR = ArmPose(pitch: 0.3, out: m.armRestOut, yaw: 0, elbow: 0.55)
            r.weaponR = -1.0
        case .heavySwing:
            // 大槌は体の横で立てて持つ（頭部が肩の外に並び、正面・上方どちらからも読める）
            r.armR = ArmPose(pitch: 0.22, out: 0.38, yaw: 0, elbow: 0.5)
            r.weaponR = -0.12
            runSwingR = 0.25
            runSwingL = 0.25
        case .thrust:
            // ランスの構え: 穂先を前へ下げて半身に構え、左手を柄に添える中段の構え
            r.armR = ArmPose(pitch: 0.6, out: m.armRestOut, yaw: 0.08, elbow: 1.0)
            r.weaponR = -1.0
            r.armL = ArmPose(pitch: 0.7, out: m.armRestOut, yaw: 0.25, elbow: 1.2)
            runSwingR = 0.5
            runSwingL = 0.5
        case .dualSlash:
            // 双剣の構え: 刃を低く前へ開き、主手を前・逆手をやや引いた半身の居合腰
            r.armR = ArmPose(pitch: 0.5, out: m.armRestOut + 0.14, yaw: 0.1, elbow: 1.05)
            r.armL = ArmPose(pitch: 0.3, out: m.armRestOut + 0.14, yaw: -0.1, elbow: 1.2)
            r.weaponR = -1.5
            r.weaponL = -1.05
        case .punch:
            r.armR = ArmPose(pitch: 0.55, out: m.armRestOut, yaw: 0.2, elbow: 1.35)
            r.armL = ArmPose(pitch: 0.55, out: m.armRestOut, yaw: 0.2, elbow: 1.35)
            runSwingR = 0.7
            runSwingL = 0.7
        case .bow:
            // 射手の構え: 弓手(左)を前へ、引き手(右)を弦の近く(胸前)に添える
            r.armL = ArmPose(pitch: 0.55, out: m.armRestOut, yaw: 0.06, elbow: 0.32)
            r.armR = ArmPose(pitch: 0.42, out: m.armRestOut, yaw: 0.5, elbow: 1.3)
            runSwingL = 0.6
            runSwingR = 0.6
        case .gun:
            r.armR = ArmPose(pitch: 0.5, out: m.armRestOut, yaw: 0.35, elbow: 1.15)
            r.armL = ArmPose(pitch: 0.75, out: 0.05, yaw: 0.65, elbow: 1.05)
            r.weaponR = -0.75
            runSwingR = 0.25
            runSwingL = 0.25
        case .staff:
            r.armR = ArmPose(pitch: 0.2, out: m.armRestOut + 0.05, yaw: 0, elbow: 0.55)
            r.weaponR = -0.08
            runSwingR = 0.35
        case .spellThrow:
            r.armR = ArmPose(pitch: 0.3, out: m.armRestOut, yaw: 0, elbow: 1.0)
            r.armL = ArmPose(pitch: 0.3, out: m.armRestOut, yaw: 0.15, elbow: 1.1)
            r.weaponR = 0
            runSwingR = 0.6
        }
        if bp.offhand == .gateShield || bp.offhand == .hideShield {
            r.armL = ArmPose(pitch: 0.45, out: m.armRestOut + 0.05, yaw: 0.2, elbow: 0.9)
            runSwingL = 0.3
        }
        if bp.weapon == .abyssCenser { r.weaponR = 0 }
        rest = r

        attack = HeroMotionProfile.attackClip(bp.attack, rest: r, left: false)
        attackAlt = bp.attack == .dualSlash || bp.attack == .punch || bp.attack == .thrust || bp.attack == .slash ? HeroMotionProfile.attackClip(bp.attack, rest: r, left: true) : nil
        let shield = shieldHold
        let builder = MotionBuilder(rest: r, style: bp.attack, shield: shield, twoHanded: bp.twoHanded, bow: bowHold)
        let slots: [SkillSlot] = [.skill1, .skill2, .skill3, .ultimate]
        casts = (0..<4).map { slot in
            if let heroID, let clip = SkillFXCatalog.motion(heroID: heroID, slot: slots[slot], builder: builder) {
                return clip
            }
            var clip = HeroMotionProfile.castClip(slot: slot, rest: r, style: bp.attack)
            if shield && slot >= 2 {
                // 盾は掲げず胸の前に構える（顔を隠さない）
                let guardArm = ArmPose(pitch: 0.9, out: 0.35, yaw: 0.1, elbow: 0.7)
                clip.windup.armL = guardArm
                clip.strike.armL = guardArm
                clip.windup.weaponL = 0
                clip.strike.weaponL = 0
            }
            return MotionClip(action: clip)
        }
    }

    // MARK: 通常攻撃

    private static func attackClip(_ style: AttackStyle, rest r: HeroPose, left: Bool) -> ActionClip {
        var w = r, s = r
        switch style {
        case .slash:
            // 太刀/片手剣風: 体幹のひねりで振り切る。連打は 袈裟斬り(下ろし, else) → 横薙ぎ(left) の2段。
            // 盾・オフハンドは構えたまま(armL は触らない)。out は体格基準(rest=armRestOut)に相対化。
            if left {
                // 横薙ぎ: 右へ引いて水平に振り抜く
                w.armR = ArmPose(pitch: 1.5, out: r.armR.out + 0.5, yaw: -0.45, elbow: 0.5)
                w.weaponR = 1.1
                w.torsoYaw = -0.4
                w.torsoRoll = -0.1
                w.headYaw = -0.2
                s.armR = ArmPose(pitch: 1.05, out: r.armR.out + 0.1, yaw: 0.7, elbow: 0.1)
                s.weaponR = -1.5
                s.torsoYaw = 0.5
                s.torsoRoll = 0.12
                s.torsoPitch = 0.12
                s.headYaw = 0.22
                return ActionClip(windup: w, strike: s, windupTime: 0.14, strikeTime: 0.07, total: 0.36)
            } else {
                // 袈裟斬り: 振りかぶって斜め下へ斬り下ろす
                w.armR = ArmPose(pitch: 2.75, out: r.armR.out + 0.3, yaw: -0.2, elbow: 0.6)
                w.weaponR = 0.95
                w.torsoYaw = 0.4
                w.torsoRoll = 0.08
                w.torsoPitch = -0.1
                w.headYaw = 0.15
                s.armR = ArmPose(pitch: 0.42, out: r.armR.out + 0.08, yaw: 0.58, elbow: 0.08)
                s.weaponR = -2.1
                s.torsoYaw = -0.45
                s.torsoRoll = -0.12
                s.torsoPitch = 0.22
                s.headYaw = -0.2
                s.headPitch = 0.08
                return ActionClip(windup: w, strike: s, windupTime: 0.16, strikeTime: 0.08, total: 0.4)
            }
        case .heavySwing:
            // 大槌/ハンマー風: 大きく振りかぶって(深い溜め)、全身で上段から叩きつける。着弾を見下ろす。
            w.armR = ArmPose(pitch: 3.0, out: 0.22, yaw: 0.18, elbow: 0.45)
            w.armL = ArmPose(pitch: 3.0, out: 0.12, yaw: 0.5, elbow: 0.45)
            w.weaponR = 1.6
            w.torsoPitch = -0.28                 // 深く反って溜め
            w.headPitch = -0.16
            s.armR = ArmPose(pitch: 0.7, out: 0.1, yaw: 0.32, elbow: 0.08)
            s.armL = ArmPose(pitch: 0.8, out: 0.0, yaw: 0.68, elbow: 0.18)
            s.weaponR = -2.45                     // 真下へ叩きつけ
            s.torsoPitch = 0.42                   // 体ごと前へ落とす
            s.headPitch = 0.22                    // 着弾を見る
            return ActionClip(windup: w, strike: s, windupTime: 0.32, strikeTime: 0.12, total: 0.64)
        case .thrust:
            // モンハン ランス風: 穂先を水平に保ってまっすぐ前へ突き出す踏み込み突き。左手を柄に添えて体ごと乗せる。
            // 連打は 中段突き(else) → 上段突き(left) の2段コンボ。穂先は水平〜やや上に保ち、跳ね上げない。
            if left {
                // 上段突き: やや上向きに素早く突き上げる追撃
                w.armR = ArmPose(pitch: 0.95, out: 0.26, yaw: -0.18, elbow: 1.9)
                w.weaponR = -1.15
                w.armL = ArmPose(pitch: 1.1, out: 0.12, yaw: 0.4, elbow: 1.45)
                w.torsoYaw = 0.44
                w.torsoPitch = -0.14
                w.headPitch = -0.08
                s.armR = ArmPose(pitch: 1.55, out: 0.06, yaw: 0.24, elbow: 0.02)
                s.weaponR = -1.2
                s.armL = ArmPose(pitch: 1.2, out: 0.1, yaw: 0.18, elbow: 0.9)
                s.torsoYaw = -0.3
                s.torsoPitch = 0.24
                s.headPitch = -0.02
                return ActionClip(windup: w, strike: s, windupTime: 0.12, strikeTime: 0.05, total: 0.30)
            } else {
                // 中段突き: 水平にまっすぐ踏み込んで突く主体
                w.armR = ArmPose(pitch: 0.55, out: 0.28, yaw: -0.2, elbow: 1.95)   // 右: 深く引いて溜める
                w.weaponR = -1.4
                w.armL = ArmPose(pitch: 0.95, out: 0.12, yaw: 0.45, elbow: 1.5)    // 左: 柄に添えて引く
                w.torsoYaw = 0.5
                w.torsoPitch = -0.12                                               // 半身で反って溜め
                w.headYaw = 0.12
                s.armR = ArmPose(pitch: 1.2, out: 0.06, yaw: 0.28, elbow: 0.02)    // 右: 水平にまっすぐ突き出す
                s.weaponR = -1.55
                s.armL = ArmPose(pitch: 1.05, out: 0.1, yaw: 0.2, elbow: 0.95)     // 左: 添えて押し出す
                s.torsoYaw = -0.34
                s.torsoPitch = 0.3                                                 // 体ごと前へ踏み込む
                s.headPitch = 0.12
                s.headYaw = -0.1
                return ActionClip(windup: w, strike: s, windupTime: 0.15, strikeTime: 0.06, total: 0.36)
            }
        case .dualSlash:
            // モンハン双剣風: 両刃を使う交差斬りを、2 拍で弧が変わる手数のコンボにする。
            // attackCount が偶数 → 斬り下ろし(else)、奇数 → 薙ぎ払い(left) が交互に出る。
            if left {
                // 薙ぎ払い: 左主手を横から水平に振り抜き、逆手が低く追従して前を一文字に薙ぐ
                w.armL = ArmPose(pitch: 1.35, out: 0.44, yaw: -0.4, elbow: 0.85)  // 主手: 横へ引いて溜める(スリム体型に合わせ開きを控えめ)
                w.weaponL = 0.2
                w.armR = ArmPose(pitch: 1.5, out: 0.35, yaw: 0.1, elbow: 0.9)     // 逆手: 反対側へ構える
                w.weaponR = -0.2
                w.torsoYaw = -0.5
                w.torsoRoll = 0.12
                w.headYaw = -0.22
                s.armL = ArmPose(pitch: 1.05, out: 0.18, yaw: 0.65, elbow: 0.15)  // 主手: 水平に振り抜く
                s.weaponL = -1.55
                s.armR = ArmPose(pitch: 1.15, out: 0.2, yaw: -0.35, elbow: 0.3)   // 逆手: 逆向きに薙いで交差
                s.weaponR = -1.5
                s.torsoYaw = 0.56
                s.torsoRoll = -0.15
                s.headYaw = 0.24
                s.torsoPitch = 0.08
                s.headPitch = 0.05
                return ActionClip(windup: w, strike: s, windupTime: 0.1, strikeTime: 0.06, total: 0.28)
            } else {
                // 斬り下ろし: 右主手が高い弧で斬り下ろし、逆手が低い弧で薙いで交差する
                w.armR = ArmPose(pitch: 2.5, out: 0.52, yaw: -0.35, elbow: 0.7)   // 主手: 振りかぶる(スリム体型に合わせ開きを控えめ)
                w.weaponR = 0.85
                w.armL = ArmPose(pitch: 0.12, out: 0.44, yaw: -0.18, elbow: 1.5)  // 逆手: 低く引いて溜める(スリム体型に合わせ開きを控えめ)
                w.weaponL = -0.3
                w.torsoYaw = 0.44
                w.torsoRoll = -0.12
                w.headYaw = 0.2
                w.torsoPitch = -0.1                                               // 振りかぶりで少し反る(溜め)
                s.armR = ArmPose(pitch: 0.5, out: 0.1, yaw: 0.62, elbow: 0.08)    // 主手: 高い弧で斬り下ろす
                s.weaponR = -2.15
                s.armL = ArmPose(pitch: 1.1, out: 0.26, yaw: 0.52, elbow: 0.38)   // 逆手: 低い弧で薙いで交差
                s.weaponL = -1.9
                s.torsoYaw = -0.52
                s.torsoRoll = 0.15
                s.headYaw = -0.22
                s.torsoPitch = 0.26
                s.headPitch = 0.1
                return ActionClip(windup: w, strike: s, windupTime: 0.12, strikeTime: 0.06, total: 0.30)
            }
        case .punch:
            // 拳/爪風: 腰のひねりで体重を乗せて打ち抜くストレート。左右交互。
            if left {
                w.armL = ArmPose(pitch: 0.35, out: 0.28, yaw: -0.12, elbow: 2.0)  // 腰だめに深く引く
                w.torsoYaw = -0.45
                s.armL = ArmPose(pitch: 1.5, out: 0.05, yaw: 0.38, elbow: 0.04)   // まっすぐ打ち抜く
                s.torsoYaw = 0.4
            } else {
                w.armR = ArmPose(pitch: 0.35, out: 0.28, yaw: -0.12, elbow: 2.0)
                w.torsoYaw = 0.45
                s.armR = ArmPose(pitch: 1.5, out: 0.05, yaw: 0.38, elbow: 0.04)
                s.torsoYaw = -0.4
            }
            w.torsoPitch = -0.06
            s.torsoPitch = 0.26                   // 体重を乗せる
            s.headPitch = 0.08
            return ActionClip(windup: w, strike: s, windupTime: 0.12, strikeTime: 0.06, total: 0.32)
        case .bow:
            // モンハン弓風: 的へ半身に構え、弓手(左)を的へロック、引き手(右)を顔の近くまで満引き。
            // 発射で弦を離し、引き手が後方へ弾ける(反動)。弓手もわずかに戻る。out は体格(armRestOut)基準に相対化。
            w.armL = ArmPose(pitch: 1.48, out: r.armL.out - 0.14, yaw: 0.12, elbow: 0.05)  // 弓手: 的へ伸ばしてロック
            w.weaponL = 0
            w.armR = ArmPose(pitch: 1.5, out: r.armL.out + 0.14, yaw: 0.55, elbow: 2.25)   // 引き手: 顔の近くまで満引き
            w.torsoYaw = 0.58
            w.torsoPitch = 0.04
            w.headYaw = -0.5                                                                // 矢の線に沿って的を狙う
            s.armL = ArmPose(pitch: 1.42, out: r.armL.out - 0.12, yaw: 0.1, elbow: 0.14)    // 弓手: 発射でわずかに戻る
            s.weaponL = 0
            s.armR = ArmPose(pitch: 1.22, out: r.armL.out + 0.42, yaw: -0.4, elbow: 1.15)   // 引き手: 弦を離して後方へ弾ける
            s.torsoYaw = 0.5
            s.headYaw = -0.44
            s.glow = 0.55
            return ActionClip(windup: w, strike: s, windupTime: 0.3, strikeTime: 0.05, total: 0.52)
        case .gun:
            // 銃風: 両手で構えて撃つ。発砲で銃口が跳ね上がり(反動)、肩と体で後ろへいなす。銃口は強く発光。
            w.armR = ArmPose(pitch: 1.32, out: 0.15, yaw: 0.3, elbow: 0.35)
            w.armL = ArmPose(pitch: 1.42, out: -0.1, yaw: 0.55, elbow: 0.5)
            w.weaponR = -1.57                     // 水平に狙う
            w.torsoYaw = 0.26
            s.armR = ArmPose(pitch: 1.66, out: 0.15, yaw: 0.3, elbow: 0.6)
            s.armL = ArmPose(pitch: 1.7, out: -0.1, yaw: 0.55, elbow: 0.7)
            s.weaponR = -1.08                     // 銃口が跳ね上がる(反動)
            s.torsoYaw = 0.28
            s.torsoPitch = -0.16                  // 反動を後ろへいなす
            s.headPitch = -0.06
            s.glow = 0.9                          // マズルフラッシュ
            return ActionClip(windup: w, strike: s, windupTime: 0.14, strikeTime: 0.04, total: 0.38)
        case .staff:
            // 杖風: 杖を掲げて力を溜め(発光)、decisive に前へ突き出して放つ(強発光)。
            w.armR = ArmPose(pitch: 0.95, out: 0.2, yaw: -0.12, elbow: 1.25)
            w.weaponR = 0.25
            w.torsoPitch = -0.1
            w.torsoYaw = 0.18
            w.glow = 0.5                          // 溜めの光
            s.armR = ArmPose(pitch: 1.4, out: 0.1, yaw: 0.22, elbow: 0.12)
            s.weaponR = -1.25                     // 前へ突き出して放つ
            s.torsoPitch = 0.18
            s.torsoYaw = -0.1
            s.headPitch = 0.06
            s.glow = 1.0                          // 放出
            return ActionClip(windup: w, strike: s, windupTime: 0.2, strikeTime: 0.07, total: 0.46)
        case .spellThrow:
            // 呪文風: 大きく振りかぶって力を溜め(発光)、体ごと回して前へ放つ(強発光バースト)。
            w.armR = ArmPose(pitch: 1.0, out: 0.35, yaw: -0.32, elbow: 1.7)
            w.weaponR = 0
            w.torsoYaw = 0.42
            w.torsoRoll = -0.08
            w.headYaw = 0.12
            w.glow = 0.4                          // 溜めの光
            s.armR = ArmPose(pitch: 1.52, out: 0.05, yaw: 0.22, elbow: 0.04)
            s.weaponR = -1.2
            s.torsoYaw = -0.36
            s.torsoRoll = 0.1
            s.torsoPitch = 0.16
            s.headYaw = -0.12
            s.glow = 1.05                         // 放出バースト
            return ActionClip(windup: w, strike: s, windupTime: 0.16, strikeTime: 0.07, total: 0.42)
        }
    }

    // MARK: スキル詠唱

    /// slot: 0 = Skill1 / 1 = Skill2 / 2 = Skill3 / 3 = Ultimate
    private static func castClip(slot: Int, rest r: HeroPose, style: AttackStyle) -> ActionClip {
        var w = r, s = r
        let ranged = style == .bow || style == .gun || style == .staff || style == .spellThrow
        switch slot {
        case 0:
            w.armR = ArmPose(pitch: 0.9, out: 0.3, yaw: -0.2, elbow: 1.6)
            w.weaponR = ranged ? 0 : 0.4
            w.torsoYaw = 0.45
            w.glow = 0.6
            s.armR = ArmPose(pitch: 1.55, out: 0.08, yaw: 0.2, elbow: 0.05)
            s.weaponR = ranged ? -1.3 : -1.62
            s.torsoYaw = -0.35
            s.torsoPitch = 0.16
            s.glow = 1.1
            return ActionClip(windup: w, strike: s, windupTime: 0.18, strikeTime: 0.1, total: 0.55)
        case 1:
            w.armR = ArmPose(pitch: -0.7, out: 0.35, yaw: 0, elbow: 0.4)
            w.armL = ArmPose(pitch: -0.7, out: 0.35, yaw: 0, elbow: 0.4)
            w.torsoPitch = 0.3
            w.headPitch = -0.2
            w.glow = 0.5
            w.wings = 0.1
            s.armR = ArmPose(pitch: -0.9, out: 0.45, yaw: 0, elbow: 0.2)
            s.armL = ArmPose(pitch: -0.9, out: 0.45, yaw: 0, elbow: 0.2)
            s.torsoPitch = 0.42
            s.headPitch = -0.3
            s.glow = 0.9
            s.wings = 0.0
            return ActionClip(windup: w, strike: s, windupTime: 0.12, strikeTime: 0.12, total: 0.5)
        case 2:
            w.armR = ArmPose(pitch: 2.9, out: 0.3, yaw: 0, elbow: 0.3)
            w.armL = ArmPose(pitch: 2.9, out: 0.3, yaw: 0, elbow: 0.3)
            w.weaponR = 0.1
            w.weaponL = 0.1
            w.torsoPitch = -0.16
            w.headPitch = -0.25
            w.glow = 1.1
            w.wings = 1
            s.armR = ArmPose(pitch: 0.95, out: 0.25, yaw: 0.1, elbow: 0.1)
            s.armL = ArmPose(pitch: 0.95, out: 0.25, yaw: 0.1, elbow: 0.1)
            s.weaponR = -2.2
            s.weaponL = -2.2
            s.torsoPitch = 0.3
            s.headPitch = 0.1
            s.glow = 1.3
            s.ring = 0.7
            s.wings = 0.6
            return ActionClip(windup: w, strike: s, windupTime: 0.3, strikeTime: 0.1, total: 0.7)
        default:
            w.armR = ArmPose(pitch: 2.6, out: 0.95, yaw: 0, elbow: 0.2)
            w.armL = ArmPose(pitch: 2.6, out: 0.95, yaw: 0, elbow: 0.2)
            w.weaponR = 0
            w.weaponL = 0
            w.torsoPitch = -0.25
            w.headPitch = -0.4
            w.glow = 1.7
            w.ring = 1
            w.wings = 1.2
            s.armR = ArmPose(pitch: 1.3, out: 0.45, yaw: 0.15, elbow: 0.1)
            s.armL = ArmPose(pitch: 1.3, out: 0.45, yaw: 0.15, elbow: 0.1)
            s.weaponR = -1.5
            s.weaponL = -0.6
            s.torsoPitch = 0.25
            s.headPitch = 0.05
            s.glow = 2.2
            s.ring = 1.3
            s.wings = 1
            return ActionClip(windup: w, strike: s, windupTime: 0.55, strikeTime: 0.15, total: 1.05)
        }
    }
}

// MARK: - アニメーター

/// 状態機械 + ブレンド。HeroModel が毎フレーム evaluate して骨へ適用する。
struct HeroAnimator {
    let profile: HeroMotionProfile
    /// 状態未指定の走行時の速度（m/s）。
    let defaultRunSpeed: Float
    /// 腰から足首までの長さ（m、モデルの拡縮込み）。歩幅と足の運びを地面の動きへ合わせるのに使う。
    var legLength: Float = 0.56

    private(set) var state: HeroAnimState = .idle
    private(set) var stateTime: Float = 0
    private(set) var time: Float = 0
    private var runPhase: Float = 0
    private var speed: Float = 0
    private var snapshot = HeroPose()
    private var blendTime: Float = 1
    private var blendDuration: Float = 0.2
    private var attackCount = 0
    private(set) var current = HeroPose()

    init(profile: HeroMotionProfile, defaultRunSpeed: Float) {
        self.profile = profile
        self.defaultRunSpeed = defaultRunSpeed
        current = profile.rest
        snapshot = profile.rest
    }

    var attackDuration: Float { profile.attack.total }

    mutating func setState(_ s: HeroAnimState) {
        if s == state {
            // 攻撃中に再度 attack が来たら、打撃を過ぎていれば次の振りを始める
            if s == .attack && stateTime >= profile.attack.windupTime + profile.attack.strikeTime {
                attackCount += 1
                begin(s, blend: 0.05)
            } else if case .cast(let slot) = s, stateTime >= profile.casts[HeroAnimator.castIndex(slot)].total {
                // 詠唱が終わった後の同じスロットの再詠唱
                begin(s, blend: 0.08)
            }
            return
        }
        if state == .attack && s != .attack { attackCount += 1 }
        let blend: Float
        switch s {
        case .attack: blend = 0.05
        case .cast: blend = 0.08
        case .dead: blend = 0.1
        case .stunned: blend = 0.1
        case .channel, .victory: blend = 0.25
        case .idle, .run: blend = state == .dead ? 0 : 0.2
        }
        begin(s, blend: blend)
    }

    /// スロットの詠唱モーションの長さ（秒）。
    func castDuration(_ slot: SkillSlot) -> Float { profile.casts[HeroAnimator.castIndex(slot)].total }

    static func castIndex(_ slot: SkillSlot) -> Int {
        switch slot {
        case .passive, .skill1: return 0
        case .skill2: return 1
        case .skill3: return 2
        case .ultimate: return 3
        }
    }

    private mutating func begin(_ s: HeroAnimState, blend: Float) {
        snapshot = current
        state = s
        stateTime = 0
        blendTime = 0
        blendDuration = blend
    }

    /// dt 秒進めて姿勢を返す。moveSpeed は m/s。
    mutating func advance(dt: Float, moveSpeed: Float) -> HeroPose {
        let dt = min(max(dt, 0), 0.1)
        time += dt
        stateTime += dt
        blendTime += dt
        var target = moveSpeed
        if state == .run && target < 0.2 { target = defaultRunSpeed }
        if state == .dead || state == .channel || state == .stunned || state == .victory { target = 0 }
        // 急な速度変化を平滑化
        speed += (target - speed) * min(1, dt * 10)
        // 1 歩（半周期）で足が進む距離 = 2·L·sin(A) が、その間に体が進む距離と一致するように位相を進める
        let sweep = sin(legSwingAngle(speed: speed))
        if speed > 0.01 { runPhase += dt * .pi * speed / (2 * max(0.2, legLength) * max(0.1, sweep)) }
        if runPhase > 1000 { runPhase -= 2 * .pi * 150 }

        let pose = evaluate()
        if blendTime < blendDuration && blendDuration > 0 {
            current = HeroPose.mix(snapshot, pose, smooth01(blendTime / blendDuration))
        } else {
            current = pose
        }
        return current
    }

    private func evaluate() -> HeroPose {
        let loco = locomotion()
        switch state {
        case .idle, .run:
            return loco
        case .attack:
            let alt = attackCount % 2 == 1
            let clip = alt ? (profile.attackAlt ?? profile.attack) : profile.attack
            // 攻撃状態が続く場合は一定周期で振り続ける
            let period = clip.total + 0.12
            let t = stateTime.truncatingRemainder(dividingBy: period)
            return clip.evaluate(base: loco, t: t)
        case .cast(let slot):
            var p = profile.casts[HeroAnimator.castIndex(slot)].evaluate(base: loco, t: stateTime)
            p.glow *= 1 + 0.15 * sin(time * 18)
            return p
        case .channel:
            return channel(loco)
        case .stunned:
            return stunned(loco)
        case .dead:
            return dead()
        case .victory:
            return victory()
        }
    }

    // MARK: 移動

    /// 走行時の脚の前後振り角（rad）。速いほど大きく振る。
    private func legSwingAngle(speed: Float) -> Float {
        0.72 * min(1.35, max(0.45, speed / 3.3)) * profile.legSwing
    }

    private func locomotion() -> HeroPose {
        let r = profile.rest
        var p = r
        let t = time
        let breathe = sin(t * 2 * .pi / 2.8)
        p.hipsDrop = 0.006 * (1 - breathe)
        p.torsoPitch = 0.025 * breathe
        p.headPitch = -0.02 * breathe + 0.03 * sin(t * 0.7)
        p.headYaw = 0.2 * sin(t * 0.43) * sin(t * 0.17)
        p.armR.out += 0.035 * breathe
        p.armL.out += 0.035 * breathe
        p.armR.pitch += 0.03 * sin(t * 2.2 + 0.5)
        p.armL.pitch += 0.03 * sin(t * 2.2 + 1.3)
        p.weaponR += 0.05 * sin(t * 1.3)
        p.weaponL += 0.04 * sin(t * 1.1 + 0.8)
        p.cape = r.cape + 0.035 * sin(t * 1.7)
        p.wings = r.wings + 0.1 * sin(t * 1.1)

        let w = smooth01((speed - 0.15) / 0.8)
        guard w > 0.001 else { return p }
        let k = min(1.35, max(0.45, speed / 3.3))
        let ph = runPhase
        let s = sin(ph), c = cos(ph)
        var run = p
        let A = legSwingAngle(speed: speed)
        // 足の前後振りは三角波寄り（接地中は一定の速さで後ろへ流れる = 地面を蹴って進んで見える）
        let tri = asin(0.95 * s) / asin(0.95)
        run.legR.pitch = A * tri
        run.legL.pitch = -A * tri
        // 振り出し側の膝を高く畳み、接地側はほぼ伸ばす
        run.legR.knee = k * (0.12 + 1.35 * max(0, c))
        run.legL.knee = k * (0.12 + 1.35 * max(0, -c))
        run.legR.out = 0.04
        run.legL.out = 0.04
        // 接地ごとに腰が沈み、蹴り出しで浮く
        run.offset.y = 0.06 * k * abs(c)
        run.hipsDrop = 0.02 * k * (1 - abs(c))
        run.pitch = 0.24 * k
        run.torsoPitch = -0.08 * k
        run.torsoYaw = 0.2 * k * s
        run.hipsYaw = -0.14 * k * s
        run.hipsRoll = 0.05 * k * s
        run.headPitch = -0.2 * k
        run.headYaw = -run.torsoYaw * 0.8
        // 腕は肘を畳んだまま小さめに振る（棒立ちで振り回さない）
        let S = 0.7 * k
        run.armR.pitch = r.armR.pitch - S * profile.runSwingR * s
        run.armL.pitch = r.armL.pitch + S * profile.runSwingL * s
        run.armR.elbow = r.armR.elbow + 0.75 * profile.runSwingR
        run.armL.elbow = r.armL.elbow + 0.75 * profile.runSwingL
        run.weaponR = r.weaponR + 0.08 * sin(ph * 2)
        run.weaponL = r.weaponL + 0.06 * sin(ph * 2)
        run.cape = 0.25 + 0.35 * k + 0.07 * sin(ph * 2)
        run.wings = 0.0
        return HeroPose.mix(p, run, w)
    }

    // MARK: 全身の状態

    private func channel(_ base: HeroPose) -> HeroPose {
        var p = base
        p.hipsDrop = 0.2
        p.pitch = 0.05
        p.legL = LegPose(pitch: 1.25, out: 0.1, knee: 1.3)
        p.legR = LegPose(pitch: -0.35, out: 0.08, knee: 1.75)
        p.torsoPitch = 0.12
        p.torsoYaw = 0
        p.headPitch = 0.35 + 0.03 * sin(time * 2)
        p.headYaw = 0
        p.armR = ArmPose(pitch: 1.0, out: 0.05, yaw: 0.65, elbow: 1.25)
        p.armL = ArmPose(pitch: 1.0, out: 0.05, yaw: 0.65, elbow: 1.25)
        p.weaponR = profile.longWeapon ? -0.1 : 2.5
        p.weaponL = profile.bowHold || profile.shieldHold ? 0 : 2.5
        p.glow = 0
        p.ring = 0.9 + 0.1 * sin(time * 4)
        p.cape = 0.1
        p.wings = 0.5
        p.offset = .zero
        return p
    }

    private func stunned(_ base: HeroPose) -> HeroPose {
        var p = profile.rest
        let t = time
        p.roll = 0.1 * sin(t * 6)
        p.pitch = -0.04 + 0.07 * cos(t * 5)
        p.hipsDrop = 0.06
        p.legR = LegPose(pitch: 0.05, out: 0.12, knee: 0.3)
        p.legL = LegPose(pitch: -0.05, out: 0.12, knee: 0.3)
        p.headRoll = 0.25 * sin(t * 4)
        p.headPitch = 0.12 + 0.1 * cos(t * 4)
        p.armR = ArmPose(pitch: 0.12 + 0.15 * sin(t * 3), out: 0.4, yaw: 0, elbow: 0.3)
        p.armL = ArmPose(pitch: 0.12 + 0.15 * cos(t * 3), out: 0.4, yaw: 0, elbow: 0.3)
        p.weaponR = profile.longWeapon ? 0.5 : 2.0
        p.weaponL = profile.bowHold || profile.shieldHold ? 0.3 : 2.0
        p.cape = 0.08
        p.wings = 0
        return p
    }

    private func dead() -> HeroPose {
        var p = profile.rest
        let t = stateTime
        let fall = easeIn(t / 0.45)
        p.pitch = -1.3 * fall
        p.offset = SIMD3<Float>(0, -0.5 * smooth01((t - 0.5) / 0.6), -0.35 * fall)
        p.hipsDrop = 0.05 * fall
        p.legR = LegPose(pitch: 0.3 * fall, out: 0.15, knee: 0.5 * fall)
        p.legL = LegPose(pitch: 0.1 * fall, out: 0.15, knee: 0.3 * fall)
        p.armR = ArmPose(pitch: 0.4 * fall, out: 0.3 + 0.9 * fall, yaw: 0, elbow: 0.2)
        p.armL = ArmPose(pitch: 0.4 * fall, out: 0.3 + 0.9 * fall, yaw: 0, elbow: 0.2)
        p.headPitch = -0.3 * fall
        p.weaponR = profile.rest.weaponR + 1.2 * fall
        p.cape = 0
        p.wings = 0
        p.opacity = 1 - smooth01((t - 0.45) / 0.6)
        return p
    }

    private func victory() -> HeroPose {
        var p = profile.rest
        let period: Float = 1.15
        let ph = stateTime.truncatingRemainder(dividingBy: period)
        let hop: Float = ph < 0.5 ? sin(.pi * ph / 0.5) * 0.3 : 0
        let crouch: Float = ph > 0.85 ? sin(.pi * (ph - 0.85) / 0.3) : 0
        p.offset.y = hop
        p.hipsDrop = 0.08 * crouch
        p.legR.knee = 0.6 * crouch + (hop > 0 ? 0.5 : 0)
        p.legL.knee = 0.6 * crouch + (hop > 0 ? 0.3 : 0)
        p.legR.pitch = hop > 0 ? 0.3 : 0
        p.armR = ArmPose(pitch: 2.95, out: 0.25, yaw: 0, elbow: 0.15)
        p.weaponR = 0.05
        if profile.twoHanded {
            p.armL = ArmPose(pitch: 2.9, out: 0.1, yaw: 0.35, elbow: 0.3)
        } else if profile.shieldHold {
            p.armL = ArmPose(pitch: 0.8, out: 0.45, yaw: 0.1, elbow: 0.8)
        } else {
            p.armL = ArmPose(pitch: 1.9 + 0.2 * sin(time * 8), out: 1.0, yaw: 0, elbow: 0.7)
        }
        p.weaponL = 0
        p.torsoPitch = -0.12
        p.headPitch = -0.3
        p.glow = 0.5 + 0.3 * sin(time * 5)
        p.cape = 0.3 + 0.3 * hop
        p.wings = 1.1 + 0.2 * sin(time * 6)
        return p
    }
}
