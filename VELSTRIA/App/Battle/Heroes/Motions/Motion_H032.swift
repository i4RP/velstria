import Foundation
import VelstriaCore

// 担当: hero-models（モーション）。H032 赤拳のディアス = MLBB のディロス。強い通常攻撃（パッシブの円撃 = 通常攻撃 2 回の後の
// 3 回目）だけの全身のモーション（詠唱は FX_H032.motion、普段の通常攻撃はモーションクリップのまま）。
//   円撃 — 腰を落として両腕の刃を右後ろへ引き（溜め）、両腕を横へ広げたまま体ごと 1 回転して周りを薙ぐ。
//          半回転（刃が正面を通る所）が打撃 = sim の円撃の命中（attackReleased。周り 2 m の敵に同時に当たる）。
//          MLBB: 紫の渦が術者の周り 2.0〜2.1 に広がる（docs/kits/Dyrroth.md）。
// 回転は体の向き（HeroPose.yaw）を 2π 回す。戻りで逆回りに巻き戻さない（MotionClip.wrapsYaw）。移動中は下半身（向き）を
// 移動の姿勢へ戻す（足を滑らせない）。角度は体の鉛直に対して書く（MotionBuilder.worldAngles）。

enum Motion_H032: HeroMotionScript {
    /// 両腕を横へ広げて刃を外へ向けた姿勢（薙ぎ）。
    private static func wide(_ p: inout HeroPose, twist: Float, glow: Float) {
        p.armR = ArmPose(pitch: 1.45, out: 1.15, yaw: -0.2, elbow: 0.08)
        p.armL = ArmPose(pitch: 1.4, out: 1.15, yaw: -0.2, elbow: 0.1)
        p.weaponR = -1.6
        p.weaponL = -1.6
        p.torsoYaw = twist
        p.torsoPitch = 0.12
        p.headPitch = 0.08
        p.hipsDrop = 0.08
        p.glow = glow
    }

    static func empoweredAttack(_ base: MotionBuilder) -> MotionClip? {
        var m = base
        m.worldAngles = true
        m.fullBody = true
        m.yieldsLowerWhenMoving = true
        // 両腕の刃で薙ぐ（武器の軌跡は両手）
        m.strikeHand = .both
        // 溜め: 腰を落とし、両腕の刃を右後ろへ引いて胴を右へひねる（向きも少し右へ）
        m.key(0.12, .out) { p in
            p.armR = ArmPose(pitch: 1.0, out: 0.9, yaw: -0.9, elbow: 0.6)
            p.armL = ArmPose(pitch: 1.2, out: 0.35, yaw: -1.0, elbow: 0.9)
            p.weaponR = -1.3
            p.weaponL = -1.3
            p.torsoYaw = -0.75
            p.torsoPitch = 0.18
            p.yaw = -0.5
            p.hipsDrop = 0.1
            p.glow = 0.9
        }
        // 半回転（刃が正面を通って後ろへ）: 打撃 = sim の円撃の命中
        m.key(0.1, .in) { p in
            wide(&p, twist: 0.25, glow: 1.8)
            p.yaw = .pi
        }
        m.markImpact()
        // 残りの半回転（1 回転して正面へ戻る）
        m.key(0.12, .linear) { p in
            wide(&p, twist: 0.45, glow: 1.4)
            p.yaw = 2 * .pi
        }
        // 振り抜いて腕を下ろす
        m.key(0.08, .out) { p in
            p.armR = ArmPose(pitch: 1.0, out: 0.6, yaw: 0.2, elbow: 0.5)
            p.armL = ArmPose(pitch: 0.9, out: 0.6, yaw: 0.1, elbow: 0.6)
            p.torsoYaw = 0.2
            p.torsoPitch = 0.08
            p.hipsDrop = 0.05
            p.glow = 0.9
        }
        var c = m.build(recover: 0.22)
        c.wrapsYaw = true
        return c
    }
}
