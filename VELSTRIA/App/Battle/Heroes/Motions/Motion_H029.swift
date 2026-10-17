import Foundation
import VelstriaCore

// 担当: hero-models（モーション）。H029 聖槌のボルグ = MLBB のティグラルの全身のモーション（docs/vfx/H029.md「モーション（打撃の時刻）」）。
// MLBB の画面収録（訓練場、30fps。コマの時刻は発動 = 指を離したコマから）を目で読んで、溜め・打撃・戻りの長さを測り、
// 打撃のキーを sim の判定の時刻（KitMotionTimings.Borg = Kit_H029.Tune）に置いた。判定・数値は変えていない。
//   通常攻撃 — 槌を右肩の上へ振りかぶり、右上から左下へ斜めに振り抜く（体を左へひねり、左足を少し踏み込む）。MLBB は毎回同じ振り。
//   スキル1 — 槌を右の後ろ下へ引いてから、後ろ → 頭上 → 前へ縦に大きく回し、左足を踏み込んで地へ叩きつけ（0.25 秒 = 1 回目の衝撃波）、
//             深く沈んだ構えのまま衝撃波を見送ってから起き上がる。
//   スキル2 — 盾を前に突き出し、槌を後ろへ流して前傾で突進（移動中の脚は走り）。終点で盾を押し込む。
//   スキル2 の再使用 — 槌を右の後ろ下へ引いて踏み込み、下から振り上げる（0.2 秒 = 打ち上げ）。槌を頭上に掲げてから肩へ戻す。
//   アルティメット — 盾を頭上へ掲げて踏ん張り（発動から引き寄せ）、0.86 秒から盾と槌を前の地面へ叩き落とす（1.0 秒 = 崩落）。
//             沈んだ構えで止まってから起き上がる。
// 角度は体の鉛直に対して書く（MotionBuilder.worldAngles。腕の pitch 0 = 真下・π/2 = 前・π = 真上、武器角 0 = 真上・-π/2 = 前・
// ±π = 真下・+ = 後ろ。yaw + = 左回り）。足首の目標（footR / footL）は待機の足首からのずれ（m。-z = 前）。
// 腰の沈み hipsDrop は手続きの脚（0.56）に対する値で、スキンの脚へ伸ばす（ボルグは拡縮 1.32 の巨漢・脚 約 1 m）。

enum Motion_H029: HeroMotionScript {
    private typealias T = KitMotionTimings.Borg

    // MARK: - 姿勢の部品

    /// 盾を胸の前に構えた左腕（MotionBuilder の盾の既定。胴が起きている時の値）。
    private static let shieldGuardArm = ArmPose(pitch: 0.9, out: 0.35, yaw: 0.1, elbow: 0.7)

    /// 槌を右肩に担ぐ（MLBB の構え。柄を肩に乗せ、槌頭は後ろ上）。
    private static func shoulderHammer(_ p: inout HeroPose) {
        p.armR = ArmPose(pitch: 1.2, out: 0.35, yaw: 0.35, elbow: 1.9)
        p.weaponR = 0.9
    }

    private static func builder(_ base: MotionBuilder) -> MotionBuilder {
        var m = base
        m.worldAngles = true
        m.yieldsLowerWhenMoving = true
        return m
    }

    // MARK: - 通常攻撃

    /// 右上から左下への斜めの振り抜き（MLBB のティグラル: 振りかぶり 約 0.3 秒 → 打撃 → 左下へ流して 約 0.45 秒で戻る）。
    static func attacks(_ base: MotionBuilder) -> [MotionClip] {
        var m = builder(base)
        // 振りかぶり: 槌を右肩の上・後ろへ。体を右へひねって少し反り、重心を後ろの右足へ
        m.planted(0.2, .out) { p in
            p.armR = ArmPose(pitch: 2.75, out: 0.55, yaw: -0.55, elbow: 0.7)
            p.weaponR = 0.75
            p.torsoYaw = -0.5
            p.hipsYaw = -0.2
            p.torsoPitch = -0.1
            p.torsoRoll = 0.08
            p.headYaw = 0.3
            p.hipsDrop = 0.03
            p.footL = [-0.02, 0, -0.04]
            p.footR = [0.04, 0, 0.04]
            p.glow = 0.5
        }
        // 振り下ろしの途中（右上 → 前）
        m.planted(0.06, .in) { p in
            p.armR = ArmPose(pitch: 1.9, out: 0.35, yaw: 0.1, elbow: 0.25)
            p.weaponR = -1.2
            p.torsoYaw = 0.05
            p.hipsYaw = 0.05
            p.torsoPitch = 0.12
            p.torsoRoll = 0
            p.headYaw = 0
            p.footL = [-0.03, 0, -0.16]
        }
        // 打撃: 前で槌が当たる（左足を踏み込み、体を左へひねって前へ落とす）
        m.planted(0.04, .snap) { p in
            p.armR = ArmPose(pitch: 1.2, out: 0.2, yaw: 0.6, elbow: 0.08)
            p.weaponR = -2.05
            p.torsoYaw = 0.45
            p.hipsYaw = 0.22
            p.torsoPitch = 0.35
            p.torsoRoll = -0.1
            p.headPitch = 0.15
            p.headYaw = -0.15
            p.hipsDrop = 0.07
            p.footL = [-0.04, 0, -0.2]
            p.footR = [0.04, 0, 0.04]
            p.glow = 1.3
        }
        m.markImpact()
        // 振り抜き: 槌を左下へ流す
        m.planted(0.12, .out) { p in
            p.armR = ArmPose(pitch: 0.75, out: 0.1, yaw: 0.95, elbow: 0.15)
            p.weaponR = -2.5
            p.torsoYaw = 0.7
            p.hipsYaw = 0.3
            p.torsoPitch = 0.4
            p.headYaw = -0.3
            p.hipsDrop = 0.08
            p.glow = 0.9
        }
        m.hold(0.08) { $0.glow = 0.5 }
        return [m.build(recover: 0.3)]
    }

    // MARK: - スキル

    static func cast(_ slot: SkillSlot, stage: Int, _ base: MotionBuilder) -> MotionClip? {
        var m = builder(base)
        switch (slot, stage) {
        case (.skill1, 0):
            attackWave(&m)
            return m.build(recover: 0.33)
        case (.skill2, 0):
            charge(&m)
            return m.build(recover: 0.25)
        case (.skill2, 1):
            uppercut(&m)
            return m.build(recover: 0.18)
        case (.ultimate, 0):
            implosion(&m)
            return m.build(recover: 0.3)
        default:
            return nil
        }
    }

    /// スキル1 聖槌波。MLBB（f196.5 = 0）: 0〜0.10 槌を右後ろの下へ引く・0.13〜0.20 後ろから頭上へ・0.25 前の地面へ叩きつけ
    /// （深い踏み込み）・0.7 秒まで沈んだまま・1.1 秒で起き上がる。sim: 衝撃波 0.25 / 0.58 / 0.92 秒。
    private static func attackWave(_ m: inout MotionBuilder) {
        let strike = motionTime(T.waveFirstDelay)
        // 引き: 槌を右の後ろ下へ。体を右へひねり、腰を落とし始める
        m.planted(strike * 0.4, .out) { p in
            p.armR = ArmPose(pitch: -0.7, out: 0.45, yaw: -0.3, elbow: 0.35)
            p.weaponR = 2.3
            p.torsoYaw = -0.55
            p.hipsYaw = -0.25
            p.torsoPitch = 0.15
            p.torsoRoll = 0.12
            p.headYaw = 0.25
            p.hipsDrop = 0.04
            p.footR = [0.06, 0, 0.04]
            p.footL = [-0.03, 0, -0.04]
            p.glow = 0.6
        }
        // 振り上げ: 後ろ → 頭上（槌頭が後ろの上）。体を起こして反り、左足を踏み出し始める
        m.planted(strike * 0.36, .inOut) { p in
            p.armR = ArmPose(pitch: 3.3, out: 0.3, yaw: -0.05, elbow: 0.35)
            p.weaponR = 1.2
            p.torsoYaw = -0.2
            p.hipsYaw = -0.1
            p.torsoPitch = -0.25
            p.torsoRoll = 0.04
            p.headPitch = -0.15
            p.headYaw = 0.1
            p.hipsDrop = 0.01
            p.footL = [-0.06, 0.05, -0.28]
            p.glow = 1.0
        }
        // 叩きつけ（0.25 秒 = 1 回目の衝撃波）: 槌を前の地面へ。左足を大きく踏み込み、体ごと前へ深く沈む
        m.planted(strike * 0.24, .snap) { p in
            p.armR = ArmPose(pitch: 1.2, out: 0.12, yaw: 0.05, elbow: 0.05)
            p.weaponR = -2.35
            p.torsoYaw = 0.12
            p.hipsYaw = 0.05
            p.torsoPitch = 0.6
            p.torsoRoll = -0.05
            p.headPitch = 0.25
            p.headYaw = -0.1
            p.hipsDrop = 0.13
            p.offset = [0, 0, -0.16]
            p.footL = [-0.08, 0, -0.5]
            p.footR = [0.08, 0, 0.12]
            p.glow = 1.8
        }
        m.markImpact()
        // 衝撃波を見送る（2 回目 0.58 秒・3 回目 0.92 秒）: 沈んだまま槌を地に押し付ける
        m.planted(0.16, .out) { p in
            p.torsoPitch = 0.66
            p.hipsDrop = 0.15
            p.armR.pitch = 1.15
            p.weaponR = -2.3
            p.glow = 2.0
        }
        m.hold(0.23) { p in
            p.torsoPitch = 0.62
            p.hipsDrop = 0.14
            p.glow = 2.2
        }
        // 起き上がり: 槌を肩へ戻しながら（戻りは build の recover で待機へ）
        m.planted(0.12, .inOut) { p in
            p.torsoPitch = 0.25
            p.hipsDrop = 0.06
            p.offset = [0, 0, -0.08]
            p.armR = ArmPose(pitch: 1.4, out: 0.3, yaw: 0.2, elbow: 0.9)
            p.weaponR = -0.8
            p.headPitch = 0.05
            p.glow = 1.0
        }
    }

    /// スキル2 聖槌突撃（1 回目）。MLBB: 指を離した次のコマから突進（21 コマ = 0.67 秒）。盾を前に突き出し、槌を後ろへ流して前傾。
    /// 突進の間は sim が術者を動かすので、脚は移動の走り（yieldsLowerWhenMoving）。終点で盾を押し込んで止まる。
    private static func charge(_ m: inout MotionBuilder) {
        let dash = motionTime(T.dashDuration)
        m.shieldGuard = false
        // 盾を前へ突き出し、槌を右後ろへ（前傾）
        m.planted(0.08, .snap) { p in
            p.armL = ArmPose(pitch: 1.35, out: 0.15, yaw: 0.35, elbow: 0.55)
            p.weaponL = 0
            p.armR = ArmPose(pitch: -0.55, out: 0.4, yaw: -0.1, elbow: 0.45)
            p.weaponR = 1.9
            p.torsoYaw = 0.3
            p.hipsYaw = 0.12
            p.torsoPitch = 0.42
            p.headPitch = 0.1
            p.hipsDrop = 0.07
            p.footL = [-0.04, 0, -0.3]
            p.footR = [0.06, 0, 0.18]
            p.cape = 0.9
            p.glow = 1.0
        }
        m.hold(dash - 0.08 - 0.06) { p in
            p.torsoPitch = 0.46
            p.glow = 1.2
        }
        // 終点（押し運んだ敵ごと止まる）: 盾を押し込む
        m.planted(0.06, .snap) { p in
            p.armL = ArmPose(pitch: 1.5, out: 0.1, yaw: 0.3, elbow: 0.2)
            p.torsoPitch = 0.32
            p.offset = [0, 0, -0.12]
            p.hipsDrop = 0.09
            p.glow = 1.5
        }
        m.markImpact()
        m.planted(0.14, .out) { p in
            p.armL = shieldGuardArm
            p.weaponL = 0
            p.torsoPitch = 0.12
            p.offset = .zero
            p.hipsDrop = 0.05
            p.cape = 0.3
            p.glow = 0.6
        }
    }

    /// スキル2 の再使用（打ち上げ）。MLBB（f426 = 0）: 0〜0.10 槌を右後ろの下へ引いて踏み込み・0.13〜0.2 下から前へ振り上げ
    /// （0.2 秒 = ノックアップ）・0.3 秒で頭上・0.6 秒まで掲げて 0.75 秒で肩へ。
    private static func uppercut(_ m: inout MotionBuilder) {
        let strike = motionTime(T.smashDelay)
        // 引き: 槌を右の後ろ下へ。腰を落とし、左足を踏み出す
        m.planted(strike * 0.5, .out) { p in
            p.armR = ArmPose(pitch: -0.6, out: 0.4, yaw: -0.15, elbow: 0.2)
            p.weaponR = 2.0
            p.torsoYaw = -0.45
            p.hipsYaw = -0.2
            p.torsoPitch = 0.28
            p.headYaw = 0.2
            p.hipsDrop = 0.09
            p.footL = [-0.05, 0.03, -0.22]
            p.footR = [0.06, 0, 0.08]
            p.glow = 0.8
        }
        // 振り上げの途中（0.2 秒 = 判定）: 槌が前の低い所を下から上へ抜ける
        m.planted(strike * 0.5, .in) { p in
            p.armR = ArmPose(pitch: 1.2, out: 0.2, yaw: 0.25, elbow: 0.1)
            p.weaponR = -1.3
            p.torsoYaw = 0.15
            p.hipsYaw = 0.1
            p.torsoPitch = 0.12
            p.headYaw = 0
            p.hipsDrop = 0.05
            p.footL = [-0.05, 0, -0.32]
            p.glow = 1.6
        }
        m.markImpact()
        // 振り抜き: 槌を頭上へ（体を伸ばして少し反る）
        m.planted(0.1, .out) { p in
            p.armR = ArmPose(pitch: 2.95, out: 0.2, yaw: 0.1, elbow: 0.12)
            p.weaponR = 0.25
            p.torsoYaw = 0.3
            p.hipsYaw = 0.12
            p.torsoPitch = -0.18
            p.headPitch = -0.3
            p.hipsDrop = 0.0
            p.offset = [0, 0.04, 0]
            p.glow = 1.8
        }
        m.hold(0.28) { p in
            p.torsoPitch = -0.14
            p.offset = [0, 0.02, 0]
            p.glow = 1.5
        }
        // 槌を肩へ戻す
        m.planted(0.14, .inOut) { p in
            shoulderHammer(&p)
            p.torsoYaw = 0.1
            p.torsoPitch = 0
            p.headPitch = 0
            p.offset = .zero
            p.footL = [-0.03, 0, -0.12]
            p.glow = 0.5
        }
    }

    /// アルティメット 崩落聖域。MLBB（f650 = 0）: 0〜0.13 槌を右肩へ上げて踏ん張る・0.17〜0.3 盾を頭上へ掲げる・0.83 まで掲げたまま
    /// （引き寄せ 0.67 秒）・0.86〜0.97 前へ踏み込んで盾と槌を地へ叩き落とす・1.0 崩落・0.6 秒ほど沈んだまま。
    private static func implosion(_ m: inout MotionBuilder) {
        let slam = motionTime(T.ultDetonate)
        m.shieldGuard = false
        // 踏ん張り: 足を開き、槌を右肩へ
        m.planted(0.12, .out) { p in
            shoulderHammer(&p)
            p.armL = ArmPose(pitch: 1.2, out: 0.45, yaw: 0.2, elbow: 0.9)
            p.weaponL = 0
            p.torsoPitch = 0.1
            p.hipsDrop = 0.07
            p.footL = [-0.1, 0, -0.08]
            p.footR = [0.1, 0, 0.06]
            p.glow = 0.9
        }
        // 盾を頭上へ掲げる（左腕を伸ばして上へ。盾の面を前へ向ける）
        m.planted(0.16, .out) { p in
            p.armL = ArmPose(pitch: 2.75, out: 0.35, yaw: 0.25, elbow: 0.3)
            p.weaponL = -0.25
            p.armR = ArmPose(pitch: 0.9, out: 0.5, yaw: -0.2, elbow: 1.5)
            p.weaponR = 0.7
            p.torsoPitch = -0.15
            p.torsoYaw = 0.1
            p.headPitch = -0.3
            p.hipsDrop = 0.05
            p.glow = 1.6
            p.ring = 1
        }
        // 掲げたまま力を溜める（0.76 秒まで。引き寄せは 0.67 秒で終わる）
        m.hold(slam - 0.12 - 0.16 - 0.17 - 0.07) { p in
            p.torsoPitch = -0.2
            p.headPitch = -0.35
            p.armL.pitch = 2.85
            p.glow = 2.4
            p.ring = 1.4
        }
        // 振りかぶりの頂点: 体を伸ばし、左足を踏み出し始める
        m.planted(0.17, .inOut) { p in
            p.armL = ArmPose(pitch: 3.05, out: 0.2, yaw: 0.2, elbow: 0.15)
            p.armR = ArmPose(pitch: 2.6, out: 0.4, yaw: -0.2, elbow: 0.6)
            p.weaponR = 0.6
            p.torsoPitch = -0.25
            p.offset = [0, 0.04, 0]
            p.footL = [-0.08, 0.08, -0.25]
            p.glow = 2.6
        }
        // 叩き落とし（1.0 秒 = 崩落）: 盾と槌を前の地面へ。左足を踏み込み、体ごと深く沈む
        m.planted(0.07, .snap) { p in
            p.armL = ArmPose(pitch: 1.15, out: 0.15, yaw: 0.35, elbow: 0.3)
            p.weaponL = -1.4
            p.armR = ArmPose(pitch: 1.2, out: 0.25, yaw: 0.05, elbow: 0.15)
            p.weaponR = -2.2
            p.torsoPitch = 0.65
            p.torsoYaw = 0.05
            p.headPitch = 0.3
            p.hipsDrop = 0.16
            p.offset = [0, 0, -0.14]
            p.footL = [-0.12, 0, -0.45]
            p.footR = [0.12, 0, 0.14]
            p.glow = 2.2
            p.ring = 1.2
        }
        m.markImpact()
        // 沈んだまま（MLBB は 0.6〜0.8 秒）
        m.hold(0.22) { p in
            p.torsoPitch = 0.7
            p.hipsDrop = 0.17
            p.glow = 1.6
        }
        m.planted(0.15, .inOut) { p in
            p.armL = shieldGuardArm
            p.weaponL = 0
            shoulderHammer(&p)
            p.torsoPitch = 0.25
            p.headPitch = 0.1
            p.hipsDrop = 0.07
            p.offset = [0, 0, -0.06]
            p.glow = 0.8
            p.ring = 0.4
        }
    }
}
