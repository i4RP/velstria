import Foundation
import VelstriaCore

// 担当: hero-models（モーション）。H030 星砲のライナ = MLBB のライラの全身のモーション（docs/vfx/H030.md「モーション（打撃の時刻）」）。
// MLBB の画面収録 vid10（訓練場、30fps。コマの時刻は発動 = 指を離したコマから）を目で読んで、構え・反動・戻りの長さを測り、
// 撃つキーを sim の発射の時刻（KitTimes = HeroKits.fxValues = Kit_H030 の RainaTuning）に置いた。判定・数値は変えていない。
//   スキル1 — 腰だめの星砲を的へ向けて水平に構え（s1Windup = 砲弾が出る）、反動で砲口が少し跳ねて上体が後ろへ揺れる。
//   スキル2 — 星砲を前の上（約 55°）へ大きく振り上げて構え（s2Windup = 光球が出る）、反動を受けて掲げたまま待ち、下ろす。
//   アルティメット — 左足を前へ大きく開いて腰を落とし、星砲を胸の高さで前へ据えて溜める（ultWindup = ビーム）。撃った反動で
//             体が後ろへ押され、さらに沈み、砲口が上へ跳ね上がる。ビームが細るまで沈んだまま耐え、起き上がる。
//   通常攻撃 — モーションクリップ（gun_fire）のまま（MLBB も腰だめで撃つだけ。全身にしても読みが変わらない）。
// 角度は体の鉛直に対して書く（MotionBuilder.worldAngles。腕の pitch 0 = 真下・π/2 = 前・π = 真上、武器角 0 = 真上・-π/2 = 前・
// + = 後ろ。yaw + = 左回り）。足首の目標（footR / footL）は待機の足首からのずれ（m。-z = 前）。体の位置 offset は描画だけ
// （sim の位置は動かない。+z = 後ろ）。砲口の位置は FX_H030 の muzzle と同じ（棒人形の寸法で測った値。docs/vfx/H030.md）。

enum Motion_H030: HeroMotionScript {
    private static let hero = "H030"

    static func cast(_ slot: SkillSlot, stage: Int, _ base: MotionBuilder) -> MotionClip? {
        guard stage == 0 else { return nil }
        var m = base
        m.yieldsLowerWhenMoving = true
        m.worldAngles = true
        switch slot {
        case .skill1:
            farstarShot(&m)
            return m.build(recover: 0.24)
        case .skill2:
            starburstShell(&m)
            return m.build(recover: 0.26)
        case .ultimate:
            starbreakerCannon(&m)
            return m.build(recover: 0.3)
        case .passive:
            return nil
        }
    }

    // MARK: - 構え

    /// 腰だめで星砲を前へ水平に構える（両手で砲身を支え、右手は台尻の後ろの握り、左手は砲身の下）。lift = 砲口を上げる角（rad）。
    private static func levelAim(_ p: inout HeroPose, lift: Float = 0) {
        // 武器の向き = 胴の yaw + 右腕の yaw（0 で真っすぐ前、+ = 左）。右手は右の腰の前、左手は体の前を渡って砲身の下を支える。
        // 砲口が体の中心の線（sim の弾・ビームの通り道）の上に来るよう、砲は少し内へ向ける（胴 0.12 + 腕 0.05 = 0.17 rad）
        p.armR = ArmPose(pitch: 0.6 + lift * 0.5, out: 0.22, yaw: 0.05, elbow: 1.45)
        p.armL = ArmPose(pitch: 1.0 + lift * 0.6, out: -0.05, yaw: 0.95, elbow: 1.3)
        p.weaponR = -1.57 + lift
        p.torsoYaw = 0.12
        p.hipsYaw = 0.06
        p.headYaw = -0.1
    }

    // MARK: - スキル1 遠星弾

    /// MLBB（vid10 f1042 = 0）: f1043〜f1046（0.03〜0.13 秒）星砲を的へ向けて腰だめに構える・f1047〜f1049 砲口の光と閃光・
    /// f1050〜f1052（0.27〜0.33 秒）反動で砲口が少し跳ねる・f1053（0.37 秒）歩き出す。sim の砲弾は s1Windup（0.1 秒）に出るので、
    /// 撃つキーは 0.1 秒（MLBB の閃光は弾の進みを中心へ戻した時刻より 2〜3 コマ遅い。docs/kits/Layla.md）。
    private static func farstarShot(_ m: inout MotionBuilder) {
        let fire = KitTimes(hero, .skill1).seconds("s1Windup")
        // 構え: 向き直って星砲を前へ水平に（右足を少し引いて半身）
        m.planted(max(0.04, fire - 0.03), .out) { p in
            levelAim(&p, lift: 0.04)
            p.torsoPitch = 0.06
            p.hipsDrop = 0.04
            p.footR = [0.02, 0, 0.08]
            p.footL = [-0.02, 0, -0.06]
            p.glow = 1.0
        }
        // 狙いを止める（撃つ = 砲弾が出る）
        m.planted(fire - m.now, .linear) { p in
            p.torsoPitch = 0.08
            p.glow = 1.4
        }
        m.markImpact()
        // 反動: 砲口が跳ね、上体が後ろへ揺れる（体の位置を 5 cm 後ろへ）
        m.planted(0.06, .snap) { p in
            levelAim(&p, lift: 0.3)
            p.armR.elbow = 1.1
            p.torsoPitch = -0.12
            p.headPitch = -0.08
            p.hipsDrop = 0.06
            p.offset = [0, 0, 0.05]
            p.glow = 1.9
        }
        // 構え直す（MLBB は 0.37 秒で歩き出す）
        m.planted(0.14, .inOut) { p in
            levelAim(&p, lift: 0.06)
            p.torsoPitch = 0.04
            p.headPitch = 0
            p.hipsDrop = 0.04
            p.offset = [0, 0, 0.01]
            p.glow = 0.9
        }
    }

    // MARK: - スキル2 星爆弾

    /// MLBB（vid10 f965 = 0・f789 = 0）: f967〜f969（0.07〜0.13 秒）星砲を前の上へ大きく振り上げる（f794〜f798 はほぼ真上まで）・
    /// f971（0.2 秒）砲口の閃光・f972〜f974 掲げたまま光球が出る・f975〜f976（0.33〜0.37 秒）下ろして歩き出す。
    /// sim の光球は s2Windup（0.1 秒）に出る。光球は弧を描いて落ちる（演出の高さ）ので、砲口は前の上 55° へ向ける。
    private static func starburstShell(_ m: inout MotionBuilder) {
        let fire = KitTimes(hero, .skill2).seconds("s2Windup")
        // 振り上げ: 両腕で星砲を前の上へ（砲口 55°）。少し反って見上げ、左足を前へ出して支える
        m.planted(max(0.05, fire - 0.02), .out) { p in
            p.armR = ArmPose(pitch: 1.35, out: 0.2, yaw: 0.05, elbow: 1.35)
            p.armL = ArmPose(pitch: 2.0, out: -0.05, yaw: 0.95, elbow: 0.9)
            p.weaponR = -0.62
            p.torsoYaw = 0.12
            p.hipsYaw = 0.06
            p.torsoPitch = -0.1
            p.headPitch = -0.28
            p.headYaw = -0.15
            p.hipsDrop = 0.05
            p.footL = [-0.03, 0, -0.14]
            p.footR = [0.03, 0, 0.06]
            p.glow = 1.2
        }
        m.planted(fire - m.now, .linear) { p in
            p.glow = 1.5
        }
        m.markImpact()
        // 反動: 砲口がさらに上へ跳ね、上体が後ろへ（体の位置を 4 cm 後ろへ）
        m.planted(0.06, .snap) { p in
            p.weaponR = -0.42
            p.armR.pitch = 1.55
            p.armL.pitch = 2.2
            p.torsoPitch = -0.2
            p.headPitch = -0.32
            p.hipsDrop = 0.07
            p.offset = [0, 0, 0.04]
            p.glow = 2.0
        }
        // 掲げたまま光球を見送る（MLBB f972〜f974）
        m.planted(0.12, .out) { p in
            p.weaponR = -0.55
            p.armR.pitch = 1.4
            p.armL.pitch = 2.05
            p.torsoPitch = -0.12
            p.offset = [0, 0, 0.02]
            p.glow = 1.2
        }
        // 下ろす（腰だめへ）
        m.planted(0.12, .inOut) { p in
            levelAim(&p, lift: -0.1)
            p.torsoPitch = 0.02
            p.headPitch = 0
            p.hipsDrop = 0.03
            p.offset = .zero
            p.footL = [-0.02, 0, -0.08]
            p.glow = 0.6
        }
    }

    // MARK: - アルティメット 星砕の大砲

    /// MLBB（vid10 f370 = 0）: f372（0.07 秒）的へ向き直って星砲を前へ・f374〜f384（0.13〜0.47 秒）左足を前へ開いて腰を落とし、
    /// 胸の高さで星砲を前へ据えて溜める・f386（0.53 秒）閃光・f388〜f394（0.6〜0.8 秒）撃った反動で体が後ろへ押されて沈み、
    /// 砲口が上へ跳ねる・f396〜f398 沈んだまま・f400〜f406（1.0〜1.2 秒）起き上がる。sim のビームは ultWindup（0.55 秒）。
    private static func starbreakerCannon(_ m: inout MotionBuilder) {
        let fire = KitTimes(hero, .ultimate).seconds("ultWindup")
        // 向き直って星砲を前へ（左足を前へ踏み出し始める）
        m.planted(0.1, .out) { p in
            levelAim(&p, lift: 0.05)
            p.armR.pitch = 0.85
            p.armL.pitch = 1.2
            p.torsoPitch = 0.1
            p.hipsDrop = 0.08
            p.footL = [-0.05, 0, -0.24]
            p.footR = [0.04, 0, 0.12]
            p.glow = 1.2
        }
        // 腰を落として据える（足を大きく開く。前の左足に体重）
        m.planted(0.14, .out) { p in
            levelAim(&p, lift: 0.08)
            p.armR.pitch = 0.95
            p.armL.pitch = 1.3
            p.armL.elbow = 1.1
            p.torsoPitch = 0.16
            p.hipsPitch = 0.06
            p.hipsDrop = 0.15
            p.offset = [0, 0, -0.04]
            p.footL = [-0.06, 0, -0.34]
            p.footR = [0.06, 0, 0.18]
            p.glow = 1.8
            p.ring = 1.0
        }
        // 溜める（ビームまで構えたまま。わずかに沈み込む）
        m.planted(max(0.05, fire - m.now), .linear) { p in
            p.torsoPitch = 0.2
            p.hipsDrop = 0.17
            p.glow = 2.6
            p.ring = 1.3
        }
        m.markImpact()
        // 反動: 体が後ろへ押され（0.2 m）、沈み、砲口が上へ跳ねる
        m.planted(0.07, .snap) { p in
            levelAim(&p, lift: 0.62)
            p.armR.elbow = 1.25
            p.armL.elbow = 1.05
            p.torsoPitch = -0.22
            p.hipsPitch = -0.05
            p.headPitch = -0.15
            p.hipsDrop = 0.26
            p.offset = [0, 0, 0.2]
            p.glow = 2.6
        }
        // 沈んだまま耐える（ビームが細るまで。MLBB f390〜f398）
        m.planted(0.24, .out) { p in
            levelAim(&p, lift: 0.5)
            p.armR.elbow = 1.2
            p.torsoPitch = -0.12
            p.hipsPitch = 0
            p.headPitch = -0.08
            p.hipsDrop = 0.24
            p.offset = [0, 0, 0.16]
            p.glow = 1.8
            p.ring = 0.6
        }
        // 起き上がる（足を戻し始める）
        m.planted(0.2, .inOut) { p in
            levelAim(&p, lift: 0.1)
            p.torsoPitch = 0.02
            p.headPitch = 0
            p.hipsDrop = 0.06
            p.offset = [0, 0, 0.04]
            p.footL = [-0.03, 0, -0.12]
            p.footR = [0.03, 0, 0.06]
            p.glow = 0.8
            p.ring = 0
        }
    }
}
