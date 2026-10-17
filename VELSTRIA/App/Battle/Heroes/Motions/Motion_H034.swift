import Foundation
import VelstriaCore

// 担当: hero-models（モーション）。H034 鎖鉤のゴルム = MLBB のフランコの全身のモーション（docs/vfx/H034.md「モーション（打撃の時刻）」）。
// MLBB の画面収録（訓練場、30fps。コマの時刻は発動 = 指を離したコマから）を目で読んで、溜め・打撃・戻りの長さを測り、
// 打撃のキーを sim の判定の時刻（KitTimes = HeroKits.fxValues = Kit_H034.Tune）に置いた。判定・数値は変えていない。
//   通常攻撃 — 鎖鉤を右から左へ横に払う → 次は左から右へ返す（MLBB は左右交互の 2 拍）。
//   スキル1 — 体を前へ倒して大きくひねり、鉤を右の後ろ下へ回してから、ほどきながら前へ投げ放つ（0.33 秒 = 鉤が飛ぶ）。
//             腕を前へ伸ばしたまま待つ。当たれば（命中の後のモーション）鎖を張ったまま 0.45 秒待ち、肩の上へ引き寄せる
//             （命中 + 0.45〜0.70 秒 = 引き寄せ）。外れたら鎖を手繰って戻る。
//   スキル2 — 少し沈んでから両腕を頭上へ振り上げて小さく跳び、着地と同時に鉤を前の地面へ叩きつける（0.27 秒 = 叩きつけ）。
//   アルティメット — 前へ低く踏み込んで掴みかかり（0.25 秒 = 掴み・1 撃目）、掴んだまま左右交互に 4 回振る（0.32 秒おき）。
//             6 撃目は頭上へ振り上げて前の地面へ叩きつけ（1.68 秒に地を打ち、1.85 秒 = 6 撃目の判定で最も深く）、拘束の終わり（2.05 秒）まで沈む。
// 角度は体の鉛直に対して書く（MotionBuilder.worldAngles。腕の pitch 0 = 真下・π/2 = 前・π = 真上、武器角 0 = 真上・-π/2 = 前・
// ±π = 真下・+ = 後ろ。yaw + = 左回り）。足首の目標（footR / footL）は待機の足首からのずれ（m。-z = 前）。
// 腰の沈み hipsDrop は手続きの脚（0.5）に対する値で、スキンの脚へ伸ばす（ゴルムは拡縮 1.36 の脚の短い巨漢）。

enum Motion_H034: HeroMotionScript {
    private static let hero = "H034"

    // MARK: - 通常攻撃

    /// 左右交互の 2 拍。MLBB: 振りかぶり 約 0.1 秒 → 横の払い（命中）→ 体を流して戻る。2 拍目は逆向き。
    static func attacks(_ base: MotionBuilder) -> [MotionClip] {
        // 1 拍目: 右から左へ（鉤を右の後ろへ引いて、体を左へひねりながら前を払う）
        var a = base
        a.yieldsLowerWhenMoving = true
        a.worldAngles = true
        a.planted(0.16, .out) { p in
            p.armR = ArmPose(pitch: 1.3, out: 0.75, yaw: -0.75, elbow: 0.7)
            p.weaponR = 0.4
            p.torsoYaw = -0.55
            p.hipsYaw = -0.22
            p.torsoPitch = 0.05
            p.torsoRoll = 0.1
            p.armL = ArmPose(pitch: 0.7, out: 0.45, yaw: 0.3, elbow: 1.0)
            p.hipsDrop = 0.05
            p.footL = [-0.02, 0, -0.06]
            p.footR = [0.03, 0, 0.04]
            p.glow = 0.4
        }
        a.planted(0.08, .snap) { p in
            p.armR = ArmPose(pitch: 1.35, out: 0.25, yaw: 0.55, elbow: 0.1)
            p.weaponR = -1.6
            p.torsoYaw = 0.45
            p.hipsYaw = 0.2
            p.torsoPitch = 0.3
            p.torsoRoll = -0.08
            p.armL = ArmPose(pitch: 0.3, out: 0.6, yaw: -0.2, elbow: 0.6)
            p.hipsDrop = 0.07
            p.footL = [-0.03, 0, -0.16]
            p.glow = 1.2
        }
        a.markImpact()
        a.planted(0.12, .out) { p in
            p.armR = ArmPose(pitch: 1.0, out: 0.15, yaw: 0.95, elbow: 0.2)
            p.weaponR = -1.9
            p.torsoYaw = 0.65
            p.hipsYaw = 0.28
            p.torsoPitch = 0.34
            p.glow = 0.6
        }
        let first = a.build(recover: 0.26)

        // 2 拍目: 左から右へ返す（裏拳の払い）
        var b = base
        b.yieldsLowerWhenMoving = true
        b.worldAngles = true
        b.planted(0.14, .out) { p in
            p.armR = ArmPose(pitch: 1.25, out: -0.05, yaw: 0.95, elbow: 1.2)
            p.weaponR = -0.3
            p.torsoYaw = 0.6
            p.hipsYaw = 0.25
            p.torsoPitch = 0.12
            p.torsoRoll = -0.1
            p.armL = ArmPose(pitch: 0.5, out: 0.5, yaw: -0.1, elbow: 0.9)
            p.hipsDrop = 0.06
            p.footR = [0.04, 0, -0.1]
            p.footL = [-0.03, 0, 0.03]
            p.glow = 0.4
        }
        b.planted(0.08, .snap) { p in
            p.armR = ArmPose(pitch: 1.4, out: 0.7, yaw: -0.6, elbow: 0.1)
            p.weaponR = -1.45
            p.torsoYaw = -0.45
            p.hipsYaw = -0.2
            p.torsoPitch = 0.28
            p.torsoRoll = 0.1
            p.armL = ArmPose(pitch: 0.9, out: 0.3, yaw: 0.4, elbow: 1.1)
            p.hipsDrop = 0.07
            p.footR = [0.05, 0, -0.18]
            p.glow = 1.2
        }
        b.markImpact()
        b.planted(0.12, .out) { p in
            p.armR = ArmPose(pitch: 1.0, out: 1.0, yaw: -0.85, elbow: 0.25)
            p.weaponR = -1.2
            p.torsoYaw = -0.62
            p.hipsYaw = -0.26
            p.torsoPitch = 0.3
            p.glow = 0.6
        }
        let second = b.build(recover: 0.26)
        return [first, second]
    }

    // MARK: - スキル

    static func cast(_ slot: SkillSlot, stage: Int, _ base: MotionBuilder) -> MotionClip? {
        guard stage == 0 else { return nil }
        var m = base
        m.yieldsLowerWhenMoving = true
        m.worldAngles = true
        switch slot {
        case .skill1:
            hookThrow(&m)
            return m.build(recover: 0.2)
        case .skill2:
            stompSlam(&m)
            return m.build(recover: 0.28)
        case .ultimate:
            bloodyHunt(&m)
            return m.build(recover: 0.3)
        case .passive:
            return nil
        }
    }

    /// 鉤が当たった後（引き寄せ）。命中の瞬間から: 腕を伸ばしたまま鎖を張って待ち（0.45 秒 = sim のその場のスタン）、
    /// 0.38 秒から鎖を握り直して、0.45〜0.70 秒（引き寄せ）に体を後ろへひねって肩の上へ引く。MLBB（f119 = 命中）:
    /// f119〜f130 伸ばしたまま・f131〜f132 鎖を握り直す・f133〜f140 肩の上へ引く・f140〜f145 前へかがんで受ける。
    static func onHit(_ slot: SkillSlot, _ base: MotionBuilder) -> MotionClip? {
        guard slot == .skill1 else { return nil }
        var m = base
        m.yieldsLowerWhenMoving = true
        m.worldAngles = true
        let k = KitTimes(hero, .skill1)
        let hold = k.seconds("hookHold"), pull = k.seconds("hookPull")
        // 伸ばした腕で鎖を張る（投げ放った姿勢から少し引いて踏ん張る）
        m.planted(0.1, .out) { p in
            throwExtended(&p)
            p.armR.elbow = 0.25
            p.torsoPitch = 0.12
            p.hipsDrop = 0.08
            p.glow = 0.5
        }
        m.hold(hold - 0.1 - 0.08) { p in
            p.torsoPitch = 0.1
        }
        // 鎖を握り直す（腕を少し曲げ、腰を落とす）
        m.planted(0.08, .out) { p in
            p.armR = ArmPose(pitch: 1.4, out: 0.2, yaw: 0.25, elbow: 0.6)
            p.weaponR = -1.4
            p.armL = ArmPose(pitch: 1.3, out: 0.1, yaw: 0.55, elbow: 0.8)
            p.torsoPitch = 0.2
            p.hipsDrop = 0.11
            p.glow = 0.8
        }
        m.markImpact()
        // 引き寄せ（命中 + 0.45〜0.70 秒）: 体を後ろへひねって鎖を肩の上へ引く。重心を後ろの右足へ
        m.planted(pull * 0.6, .snap) { p in
            p.armR = ArmPose(pitch: 2.5, out: 0.6, yaw: -0.6, elbow: 1.6)
            p.weaponR = 1.4
            p.armL = ArmPose(pitch: 1.0, out: 0.3, yaw: 0.3, elbow: 1.3)
            p.torsoYaw = -0.6
            p.hipsYaw = -0.25
            p.torsoPitch = -0.22
            p.torsoRoll = 0.1
            p.headYaw = 0.25
            p.hipsDrop = 0.07
            p.offset = [0, 0, 0.1]
            p.glow = 1.4
        }
        m.hold(pull * 0.4) { p in
            p.torsoYaw = -0.66
            p.torsoPitch = -0.25
        }
        // 引き寄せた相手を前へかがんで受ける
        m.planted(0.14, .out) { p in
            p.armR = ArmPose(pitch: 0.9, out: 0.4, yaw: 0.2, elbow: 0.9)
            p.weaponR = -1.5
            p.armL = ArmPose(pitch: 0.8, out: 0.4, yaw: 0.2, elbow: 1.0)
            p.torsoYaw = 0.1
            p.hipsYaw = 0
            p.hipsPitch = 0.15
            p.torsoPitch = 0.3
            p.torsoRoll = 0
            p.headYaw = 0
            p.hipsDrop = 0.1
            p.offset = .zero
            p.glow = 0.6
        }
        return m.build(recover: 0.25)
    }

    /// 投げ放った姿勢（鉤の腕を前へ伸ばし切り、左足を踏み込んで前へ体重を乗せる）。
    private static func throwExtended(_ p: inout HeroPose) {
        p.armR = ArmPose(pitch: 1.6, out: 0.15, yaw: 0.3, elbow: 0.08)
        p.weaponR = -1.55
        p.armL = ArmPose(pitch: 0.4, out: 0.6, yaw: -0.2, elbow: 0.7)
        p.torsoYaw = 0.35
        p.hipsYaw = 0.15
        p.torsoPitch = 0.22
        p.torsoRoll = -0.05
        p.headYaw = -0.2
        p.headPitch = -0.05
        p.hipsDrop = 0.07
        p.footL = [-0.04, 0, -0.32]
        p.footR = [0.05, 0, 0.1]
    }

    /// スキル1 鎖鉤（投げ）。MLBB（f96 = 0）: 0〜0.07 向き直る・0.07〜0.23 体を前へ倒して大きくひねり、鉤を右の後ろ下へ・
    /// 0.23〜0.33 ほどきながら前へ振り出す・0.33 投げ放つ（sim: 鉤が飛ぶ）・伸ばしたまま待つ。外れたら（最大 0.54 秒飛ぶ）鎖を手繰る。
    private static func hookThrow(_ m: inout MotionBuilder) {
        let k = KitTimes(hero, .skill1)
        let launch = k.seconds("hookDelay")
        let flight = Float(k.distance("hookRange") / max(1, k.speed("hookSpeed")))
        // 構え: 少し沈んで向き直る
        m.planted(0.07, .out) { p in
            p.hipsDrop = 0.08
            p.torsoPitch = 0.1
            p.armR = ArmPose(pitch: 0.6, out: 0.5, yaw: -0.3, elbow: 0.8)
            p.footR = [0.05, 0, 0.05]
            p.footL = [-0.03, 0, -0.04]
        }
        // 振りかぶり: 体を前へ倒して右へ大きくひねり、鉤を右の後ろ下へ回す。左腕は前へ出して釣り合う
        m.planted(0.16, .out) { p in
            p.armR = ArmPose(pitch: -0.9, out: 0.6, yaw: -0.4, elbow: 0.3)
            p.weaponR = 2.4
            p.armL = ArmPose(pitch: 1.5, out: 0.3, yaw: 0.5, elbow: 0.6)
            p.torsoYaw = -0.75
            p.hipsYaw = -0.3
            // MLBB f98〜f102: 背がほぼ水平になるまで前へ倒し、顔は的へ残す
            p.hipsPitch = 0.45
            p.torsoPitch = 0.5
            p.torsoRoll = 0.15
            p.headYaw = 0.45
            p.headPitch = -0.6
            p.hipsDrop = 0.12
            p.footL = [-0.04, 0.04, -0.2]
            p.glow = 0.5
        }
        // 振り出し: ほどきながら鉤を横から頭の高さへ（左足を踏み込む）
        m.planted(launch - 0.07 - 0.16 - 0.04, .in) { p in
            p.armR = ArmPose(pitch: 2.0, out: 0.55, yaw: -0.1, elbow: 0.5)
            p.weaponR = -0.4
            p.armL = ArmPose(pitch: 0.8, out: 0.5, yaw: 0.1, elbow: 0.8)
            p.torsoYaw = 0
            p.hipsYaw = 0
            p.hipsPitch = 0.05
            p.torsoPitch = 0.15
            p.torsoRoll = 0
            p.headYaw = 0
            p.headPitch = 0
            p.hipsDrop = 0.07
            p.footL = [-0.04, 0, -0.32]
            p.glow = 0.9
        }
        // 投げ放つ（0.33 秒 = 鉤が飛び出す）: 腕を前へ伸ばし切る
        m.planted(0.04, .snap) { p in
            throwExtended(&p)
            p.glow = 1.3
        }
        m.markImpact()
        // 伸ばしたまま待つ（命中すれば命中の後のモーションへ移る）。外れた鉤が射程の端に届くまで
        m.hold(max(0.1, flight - 0.1)) { p in
            p.torsoPitch = 0.2
            p.glow = 0.8
        }
        // 外れた: 鎖を手繰って戻す
        m.planted(0.12, .inOut) { p in
            p.armR = ArmPose(pitch: 1.0, out: 0.35, yaw: -0.1, elbow: 1.4)
            p.weaponR = -0.8
            p.torsoYaw = -0.15
            p.torsoPitch = 0.05
            p.hipsYaw = -0.05
            p.footL = [-0.03, 0, -0.18]
            p.glow = 0.3
        }
    }

    /// スキル2 鉄鎖旋。MLBB（f186 = 0）: 0〜0.1 沈む・0.13〜0.23 両腕を頭上へ振り上げて跳ぶ・0.27 着地と同時に鉤を前の地面へ
    /// 叩きつけ（sim の叩きつけ = ダメージ）・0.55 秒まで沈んだまま・0.85 秒で戻る。
    private static func stompSlam(_ m: inout MotionBuilder) {
        let slam = KitTimes(hero, .skill2).seconds("shockDelay")
        // 沈む（跳ぶ前の溜め）
        m.planted(0.09, .out) { p in
            p.hipsDrop = 0.11
            p.torsoPitch = 0.25
            p.armR = ArmPose(pitch: 0.3, out: 0.5, yaw: 0, elbow: 0.6)
            p.weaponR = -1.6
            p.armL = ArmPose(pitch: 0.3, out: 0.5, yaw: 0, elbow: 0.6)
            p.footL = [-0.04, 0, -0.06]
            p.footR = [0.04, 0, 0.04]
            p.glow = 0.4
        }
        // 跳ぶ: 両腕を頭上へ（鉤を両手で振り上げる）、体を反らせ、足を畳む
        m.planted(slam - 0.09 - 0.06, .out) { p in
            p.armR = ArmPose(pitch: 3.0, out: 0.2, yaw: 0.25, elbow: 0.45)
            p.weaponR = 0.9
            p.armL = ArmPose(pitch: 2.9, out: 0.2, yaw: 0.4, elbow: 0.55)
            p.torsoPitch = -0.25
            p.headPitch = -0.2
            p.hipsDrop = 0
            p.offset = [0, 0.32, -0.08]
            p.footL = [-0.04, 0.2, -0.12]
            p.footR = [0.04, 0.16, -0.02]
            p.glow = 1.0
        }
        // 叩きつけ（0.27 秒）: 着地と同時に鉤を前の地面へ。深くしゃがむ
        m.planted(0.06, .snap) { p in
            p.armR = ArmPose(pitch: 1.0, out: 0.1, yaw: 0.35, elbow: 0.15)
            p.weaponR = -2.4
            p.armL = ArmPose(pitch: 1.0, out: 0.1, yaw: 0.45, elbow: 0.3)
            p.hipsPitch = 0.3
            p.torsoPitch = 0.4
            p.headPitch = 0.2
            p.hipsDrop = 0.17
            p.offset = [0, 0, -0.1]
            p.footL = [-0.06, 0, -0.18]
            p.footR = [0.06, 0, 0.04]
            p.glow = 1.8
        }
        m.markImpact()
        m.hold(0.26) { p in
            p.hipsPitch = 0.28
            p.torsoPitch = 0.38
            p.hipsDrop = 0.15
            p.glow = 1.2
        }
        m.planted(0.14, .inOut) { p in
            p.hipsPitch = 0.08
            p.torsoPitch = 0.2
            p.hipsDrop = 0.07
            p.offset = [0, 0, -0.04]
            p.armR = ArmPose(pitch: 0.7, out: 0.4, yaw: 0.1, elbow: 0.7)
            p.weaponR = -1.3
            p.armL = ArmPose(pitch: 0.4, out: 0.4, yaw: 0.1, elbow: 0.6)
            p.glow = 0.5
        }
    }

    /// アルティメット 狩猟鎖獄。MLBB（f300 = 0）: 0〜0.12 沈んで向き直る・0.13〜0.23 前へ低く踏み込んで両腕を伸ばす・0.25 掴む（1 撃目）・
    /// 2〜5 撃（0.57 / 0.89 / 1.21 / 1.53）は左右交互の振り（撃の 0.15 秒前から振りかぶる）・1.55〜1.68 頭上へ振り上げ・1.68 地を打つ・
    /// 1.85（6 撃目）最も深く・2.05 拘束の終わりまで沈む・2.35 秒で戻る。
    private static func bloodyHunt(_ m: inout MotionBuilder) {
        let k = KitTimes(hero, .ultimate)
        let grab = k.seconds("ultDelay") + k.seconds("ultFirst")
        let gap = k.seconds("ultInterval")
        let hits = max(2, k.count("ultHits"))
        let last = grab + gap * Float(hits - 1)
        let release = k.seconds("ultDelay") + k.seconds("ultSuppress")
        m.simLock = release
        // 溜め: 沈んで前を向く
        m.planted(0.1, .out) { p in
            p.hipsDrop = 0.1
            p.torsoPitch = 0.3
            p.armR = ArmPose(pitch: 0.4, out: 0.5, yaw: -0.2, elbow: 0.9)
            p.armL = ArmPose(pitch: 0.4, out: 0.5, yaw: -0.2, elbow: 0.9)
            p.footR = [0.05, 0, 0.06]
            p.footL = [-0.04, 0, -0.04]
        }
        // 掴みかかり: 前へ低く踏み込み、両腕を前へ伸ばす
        m.planted(grab - 0.1 - 0.05, .out) { p in
            p.armR = ArmPose(pitch: 1.75, out: 0.2, yaw: 0.3, elbow: 0.15)
            p.weaponR = -1.4
            p.armL = ArmPose(pitch: 1.7, out: 0.2, yaw: 0.3, elbow: 0.2)
            p.hipsPitch = 0.3
            p.torsoPitch = 0.35
            p.headPitch = -0.35
            p.hipsDrop = 0.14
            p.offset = [0, 0, -0.3]
            p.footL = [-0.05, 0, -0.5]
            p.footR = [0.06, 0, 0.0]
            p.glow = 1.0
        }
        // 掴む（0.25 秒 = 掴み・1 撃目）: 引き寄せて体を起こし、左手で相手を押さえる
        m.planted(0.05, .snap) { p in
            p.armL = ArmPose(pitch: 1.45, out: 0.15, yaw: 0.35, elbow: 0.7)
            p.weaponL = 0
            p.armR = ArmPose(pitch: 1.5, out: 0.3, yaw: 0.2, elbow: 0.5)
            p.weaponR = -1.5
            p.hipsPitch = 0.1
            p.torsoPitch = 0.3
            p.headPitch = 0
            p.hipsDrop = 0.1
            p.offset = [0, 0, -0.14]
            p.footL = [-0.05, 0, -0.34]
            p.glow = 1.4
        }
        m.markImpact()
        // 2〜5 撃: 左右交互（右から左 → 左から右 …）。撃の 0.15 秒前から振りかぶり、撃の時刻に振り抜く
        for k in 1..<(hits - 1) {
            let hitAt = grab + gap * Float(k)
            let fromRight = k % 2 == 1
            let side: Float = fromRight ? 1 : -1
            // 振りかぶり（撃の 0.15 秒前に頂点）
            m.planted(hitAt - 0.15 - m.now, .out) { p in
                p.armR = fromRight ? ArmPose(pitch: 2.3, out: 0.7, yaw: -0.6, elbow: 0.8)
                                   : ArmPose(pitch: 2.0, out: -0.05, yaw: 0.9, elbow: 1.2)
                p.weaponR = fromRight ? 0.7 : 0.3
                p.torsoYaw = -0.45 * side
                p.hipsYaw = -0.18 * side
                p.torsoPitch = 0.12
                p.torsoRoll = 0.08 * side
                p.hipsDrop = 0.08
                p.glow = 1.0
            }
            // 撃（sim の k+1 撃目の時刻）
            m.planted(0.15, .snap) { p in
                p.armR = fromRight ? ArmPose(pitch: 1.3, out: 0.15, yaw: 0.6, elbow: 0.1)
                                   : ArmPose(pitch: 1.35, out: 0.75, yaw: -0.6, elbow: 0.1)
                p.weaponR = fromRight ? -2.0 : -1.8
                p.torsoYaw = 0.45 * side
                p.hipsYaw = 0.18 * side
                p.torsoPitch = 0.38
                p.torsoRoll = -0.06 * side
                p.hipsDrop = 0.11
                p.glow = 1.6
            }
        }
        // 6 撃目: 頭上へ振り上げ（1.55〜1.68）→ 地を打つ（1.68）→ 最も深く（1.85 = 判定）
        let ground = last - 0.17
        m.planted(ground - 0.07 - m.now, .out) { p in
            p.armR = ArmPose(pitch: 3.1, out: 0.25, yaw: 0.15, elbow: 0.35)
            p.weaponR = 0.8
            p.armL = ArmPose(pitch: 2.4, out: 0.3, yaw: 0.3, elbow: 0.7)
            p.torsoYaw = 0.05
            p.hipsYaw = 0
            p.hipsPitch = 0
            p.torsoPitch = -0.25
            p.torsoRoll = 0
            p.headPitch = -0.2
            p.hipsDrop = 0.02
            p.offset = [0, 0.06, -0.1]
            p.glow = 1.6
        }
        m.planted(0.07, .snap) { p in
            p.armR = ArmPose(pitch: 1.0, out: 0.1, yaw: 0.3, elbow: 0.1)
            p.weaponR = -2.4
            p.armL = ArmPose(pitch: 1.0, out: 0.15, yaw: 0.4, elbow: 0.3)
            p.hipsPitch = 0.35
            p.torsoPitch = 0.4
            p.headPitch = 0.25
            p.hipsDrop = 0.15
            p.offset = [0, 0, -0.18]
            p.footL = [-0.06, 0, -0.42]
            p.glow = 2.2
        }
        m.planted(last - m.now, .out) { p in
            p.weaponR = -2.3
            p.hipsPitch = 0.38
            p.torsoPitch = 0.44
            p.hipsDrop = 0.19
            p.glow = 2.0
        }
        m.markImpact()
        // 拘束の終わり（2.05 秒）まで沈んだまま
        m.hold(max(0.05, release - m.now)) { p in
            p.hipsPitch = 0.36
            p.torsoPitch = 0.42
            p.hipsDrop = 0.17
            p.glow = 1.2
        }
    }
}
