import Foundation
import VelstriaCore

// 担当: hero-models（モーション）。H025 月弦のルミナ = MLBB のミヤの全身のモーション（docs/vfx/H025.md「モーション（打撃の時刻）」）。
// MLBB の画面収録 vid3（2026-10-16、訓練場 Lv4、30fps。コマの時刻は発動 = 指を離したコマから）を目で読んで、構え・放ち・戻りの長さを測り、
// 放ちのキーを sim の判定の時刻（KitTimes = HeroKits.fxValues = LuminaTuning）から置いた。判定・数値は変えていない。
//   通常攻撃 — 的へ半身に足を開き（胸を射線の横へ）、弓手（左）を的へ伸ばして引き手（右）を顔の横まで満引き（MLBB: 止まってから 4〜5 コマ）→ 放つ
//             （打撃 = sim の矢の発射）→ 引き手が後ろへ弾け、上体が少し反って戻る。
//   スキル1 — MLBB に詠唱の動きは無い（歩いたまま青い気をまとう）。気が灯る 0.06 秒に弓を胸の前へ引き寄せて少し沈み、
//             気が全身を包む間に胸を開いて弓を前へ伸ばす（移動中は上半身だけ）。
//   スキル2 — 的へ向き直って足を大きく開き、弓を斜め上（約 45°）へ向けて天へ引き絞る（MLBB f321〜328）→ 着弾の skyFall 秒前
//             （s2Land − skyFall = 0.30 秒、MLBB f329）に天へ放つ → 引き手が弾け、弓を掲げたまま空を見上げて着弾を待ち、
//             着弾（s2Land）の後に弓を下ろす。
//   アルティメット — 発動の瞬間に外套で身を包むように低くかがみ（0.07 秒 = 隠密。MLBB はその場で 2 コマ止まる）、
//             前へ倒れ込むように走り出す（MLBB f402〜404 の疾走の前傾。脚は移動の走り）。
// 角度は体の鉛直に対して書く（MotionBuilder.worldAngles。腕の pitch 0 = 真下・π/2 = 前・π = 真上、yaw + = 左回り）。
// 弓の半身の構え: 胴を右へ約 1 rad ひねって胸を射線の横へ向け（MLBB はカメラに胸を見せて的へ弓手を伸ばす）、頭を的へ戻し、
// 弓手は外（左）へ振って的へ伸ばす（armL の yaw − = 外）、引き手は胸の前を横切って顔の横へ（armR の yaw + = 内）。
// 手続きの弓の通常攻撃（attackClip の .bow、胴 +0.58）は胸が的の側を向いて読みにくかった（2026-10-21 の撮影）ので逆へひねる。
// 足首の目標（footR / footL）は待機の足首からのずれ（m。-z = 前）。弓の握り = 左手（副手の三日月の長弓。発射位置は弓の握り）。

enum Motion_H025: HeroMotionScript {
    private static let hero = "H025"

    /// S2: 天へ放ってから着弾までの長さ（MLBB: 天へ放つ f329 → 着弾 f339 = 10 コマ）。放つ時刻 = s2Land − skyFall。
    /// 演出（FX_H025 の天へ放つ星・矢）も同じ値で置く。
    static let skyFall: Float = 0.33

    /// S2 の天へ放つ時刻（発動から。sim の着弾の時刻から逆算）。
    static func skyShot() -> Float {
        max(0.18, KitTimes(hero, .skill2).seconds("s2Land") - skyFall)
    }

    private static func builder(_ base: MotionBuilder) -> MotionBuilder {
        var m = base
        m.worldAngles = true
        m.yieldsLowerWhenMoving = true
        return m
    }

    /// 半身の構えの下半身（左足を前・右足を後ろへ開いて少し沈む）。
    private static func stance(_ p: inout HeroPose, depth: Float, wide: Float = 1) {
        p.footL = [-0.05 * wide, 0, -0.15 * wide]
        p.footR = [0.06 * wide, 0, 0.11 * wide]
        p.hipsYaw = -0.45
        p.hipsDrop = depth
    }

    // MARK: - 通常攻撃

    /// 的へ半身に構えて満引き → 放つ（打撃 = sim の発射）→ 反動。MLBB（f62〜f71）: 向き直り 2 コマ・引き 3 コマ・放ち・構えたまま。
    static func attacks(_ base: MotionBuilder) -> [MotionClip] {
        var m = builder(base)
        let out = base.rest.armL.out
        // 構え: 弓手を的へ上げ、引き手を弦へ掛ける。足を開く
        m.planted(0.1, .out) { p in
            p.armL = ArmPose(pitch: 1.5, out: out - 0.12, yaw: -0.85, elbow: 0.2)
            p.weaponL = 0
            p.armR = ArmPose(pitch: 1.45, out: out + 0.1, yaw: 0.85, elbow: 1.6)
            p.torsoYaw = -0.85
            p.torsoPitch = 0.02
            p.headYaw = 0.7
            stance(&p, depth: 0.03, wide: 0.7)
            p.glow = 0.6
        }
        // 満引き（引き手が顔の横へ）
        m.planted(0.07, .inOut) { p in
            p.armL = ArmPose(pitch: 1.52, out: out - 0.14, yaw: -1.05, elbow: 0.05)
            p.armR = ArmPose(pitch: 1.52, out: out + 0.14, yaw: 1.05, elbow: 2.25)
            p.torsoYaw = -1.05
            p.torsoPitch = -0.03
            p.headYaw = 0.85
            p.hipsDrop = 0.04
            p.glow = 1.0
        }
        m.markImpact()
        // 放つ: 引き手が後ろへ弾け、弓手がわずかに戻り、上体が少し反る
        m.planted(0.05, .snap) { p in
            p.armL = ArmPose(pitch: 1.47, out: out - 0.12, yaw: -1.0, elbow: 0.12)
            p.armR = ArmPose(pitch: 1.3, out: out + 0.45, yaw: 0.15, elbow: 1.1)
            p.torsoYaw = -0.98
            p.torsoPitch = -0.08
            p.headYaw = 0.8
            p.offset = [0, 0, 0.03]
            p.glow = 1.5
        }
        m.hold(0.08) { p in
            p.torsoPitch = -0.05
            p.offset = [0, 0, 0.02]
            p.glow = 0.8
        }
        return [m.build(recover: 0.24)]
    }

    // MARK: - スキル

    static func cast(_ slot: SkillSlot, stage: Int, _ base: MotionBuilder) -> MotionClip? {
        guard stage == 0 else { return nil }
        var m = builder(base)
        switch slot {
        case .skill1:
            moonArrow(&m)
            return m.build(recover: 0.22)
        case .skill2:
            eclipse(&m)
            return m.build(recover: 0.2)
        case .ultimate:
            hiddenMoonlight(&m)
            return m.build(recover: 0.25)
        case .passive:
            return nil
        }
    }

    /// スキル1 月弦分矢（自己強化。sim は発動の tick に効く）。演出の気（FX_H025: 0.04 秒の肩の閃き → 0.06〜0.34 秒の気）に合わせる。
    private static func moonArrow(_ m: inout MotionBuilder) {
        let out = m.rest.armL.out
        // 気が灯る（0.06 秒）: 弓を胸の前へ引き寄せ、引き手を弦へ。少し沈む
        m.planted(0.06, .out) { p in
            p.armL = ArmPose(pitch: 1.25, out: out - 0.05, yaw: 0.3, elbow: 0.7)
            p.weaponL = -0.1
            p.armR = ArmPose(pitch: 1.15, out: out + 0.05, yaw: 0.7, elbow: 1.75)
            p.torsoPitch = 0.1
            p.headPitch = 0.12
            p.hipsDrop = 0.06
            p.footL = [-0.03, 0, -0.06]
            p.footR = [0.04, 0, 0.05]
            p.glow = 1.4
        }
        m.markImpact()
        // 気が全身を包む: 胸を開いて弓を前へ伸ばし、引き手を外へ払う
        m.planted(0.12, .out) { p in
            p.armL = ArmPose(pitch: 1.6, out: out - 0.1, yaw: 0.15, elbow: 0.15)
            p.weaponL = 0
            p.armR = ArmPose(pitch: 0.9, out: out + 0.5, yaw: -0.1, elbow: 0.6)
            p.torsoPitch = -0.12
            p.torsoYaw = -0.2
            p.headPitch = -0.12
            p.hipsDrop = 0.02
            p.glow = 2.0
        }
        m.hold(0.12) { p in
            p.torsoPitch = -0.1
            p.glow = 1.8
        }
    }

    /// スキル2 月蝕の矢。放つ = s2Land − skyFall（0.30 秒）、着弾 = s2Land（0.63 秒）。MLBB（f320 = 0）: f321〜328 向き直って弓を天へ引く・
    /// f329 天へ放つ・f330〜345 弓を掲げたまま見上げる・f346〜 弓を下ろす。
    private static func eclipse(_ m: inout MotionBuilder) {
        let k = KitTimes(hero, .skill2)
        let land = k.seconds("s2Land")
        let shot = skyShot()
        let out = m.rest.armL.out
        // 向き直って足を開き、弓を斜め上へ上げ始める。引き手を弦へ
        m.planted(shot * 0.36, .out) { p in
            p.armL = ArmPose(pitch: 2.0, out: out - 0.1, yaw: -0.75, elbow: 0.25)
            p.weaponL = 0.4
            p.armR = ArmPose(pitch: 1.95, out: out + 0.1, yaw: 0.8, elbow: 1.6)
            p.torsoYaw = -0.75
            p.torsoPitch = -0.08
            p.headPitch = -0.25
            p.headYaw = 0.6
            stance(&p, depth: 0.07, wide: 1.4)
            p.glow = 0.8
        }
        // 天へ満引き（約 45° 上。体を少し反らし、空を見上げる）。放つ時刻に引き切る
        m.planted(shot * 0.64, .inOut) { p in
            p.armL = ArmPose(pitch: 2.35, out: out - 0.14, yaw: -0.95, elbow: 0.05)
            // 弓を射線（約 45° 上）に直角へ傾ける（上の弓先を体の側へ。MLBB f328 の傾いた弓）。武器角の軸は弓手の向き（yaw）で回る
            p.weaponL = 0.75
            p.armR = ArmPose(pitch: 2.3, out: out + 0.14, yaw: 1.0, elbow: 2.25)
            p.torsoYaw = -0.95
            p.torsoPitch = -0.22
            p.headPitch = -0.5
            p.headYaw = 0.75
            p.hipsDrop = 0.1
            p.glow = 1.3
        }
        m.markImpact()
        // 天へ放つ: 引き手が後ろへ弾け、弓が少し跳ねる
        m.planted(0.05, .snap) { p in
            p.armL = ArmPose(pitch: 2.42, out: out - 0.12, yaw: -0.92, elbow: 0.1)
            p.weaponL = 0.82
            p.armR = ArmPose(pitch: 2.0, out: out + 0.5, yaw: 0.1, elbow: 1.0)
            p.torsoPitch = -0.27
            p.offset = [0, 0, 0.03]
            p.glow = 1.9
        }
        // 弓を掲げたまま見上げて、着弾（s2Land）の 0.1 秒後まで待つ
        m.hold(max(0.1, land + 0.1 - m.now)) { p in
            p.torsoPitch = -0.24
            p.headPitch = -0.55
            p.offset = [0, 0, 0.02]
            p.glow = 1.4
        }
        // 弓を下ろし始める（戻りは build の recover で待機へ）
        m.planted(0.12, .inOut) { p in
            p.armL = ArmPose(pitch: 1.3, out: out, yaw: -0.3, elbow: 0.6)
            p.weaponL = -0.15
            p.armR = ArmPose(pitch: 0.8, out: out + 0.15, yaw: 0.4, elbow: 1.2)
            p.torsoYaw = -0.3
            p.torsoPitch = -0.05
            p.headPitch = -0.1
            p.headYaw = 0.2
            p.offset = .zero
            p.hipsDrop = 0.03
            p.glow = 0.7
        }
    }

    /// アルティメット 隠れ月光（隠密・加速は発動の tick から）。MLBB（f397 = 0）: f399 で姿が薄れ、その場で 2 コマ止まる →
    /// f402〜404 前へ倒れ込むように走り出す（移動中は脚が走り、上半身の前傾と腕の振りだけ）。
    private static func hiddenMoonlight(_ m: inout MotionBuilder) {
        let out = m.rest.armL.out
        // 外套で身を包むように低くかがむ（0.07 秒 = 姿が消える）
        m.planted(0.07, .snap) { p in
            p.armL = ArmPose(pitch: 0.6, out: out - 0.05, yaw: 0.45, elbow: 1.3)
            p.weaponL = -0.3
            p.armR = ArmPose(pitch: 0.95, out: out, yaw: 0.9, elbow: 1.6)
            p.torsoPitch = 0.35
            p.headPitch = 0.15
            p.hipsPitch = 0.12
            p.hipsDrop = 0.12
            p.footL = [-0.04, 0, -0.1]
            p.footR = [0.05, 0, 0.1]
            p.cape = 1.2
            p.glow = 2.0
        }
        m.markImpact()
        // 前へ倒れ込むように走り出す（腕を後ろへ流す）
        m.planted(0.16, .out) { p in
            p.armL = ArmPose(pitch: -0.3, out: out + 0.1, yaw: 0.1, elbow: 0.45)
            p.weaponL = 0.2
            p.armR = ArmPose(pitch: -0.45, out: out + 0.2, yaw: -0.1, elbow: 0.5)
            p.torsoPitch = 0.45
            p.headPitch = -0.15
            p.hipsPitch = 0.1
            p.hipsDrop = 0.06
            p.offset = [0, 0, -0.08]
            p.footL = [-0.03, 0, -0.22]
            p.footR = [0.05, 0, 0.12]
            p.cape = 1.4
            p.glow = 1.6
        }
        m.hold(0.14) { p in
            p.torsoPitch = 0.42
            p.glow = 1.3
        }
        m.planted(0.12, .inOut) { p in
            p.armL = ArmPose(pitch: 0.5, out: out, yaw: 0.1, elbow: 0.9)
            p.weaponL = -0.15
            p.armR = ArmPose(pitch: 0.35, out: out, yaw: 0.4, elbow: 1.1)
            p.torsoPitch = 0.15
            p.headPitch = 0
            p.hipsPitch = 0.03
            p.hipsDrop = 0.02
            p.offset = .zero
            p.footL = [-0.02, 0, -0.08]
            p.footR = [0.03, 0, 0.05]
            p.cape = 0.6
            p.glow = 0.8
        }
    }
}
