import Foundation
import VelstriaCore

// 担当: hero-models（モーション）。H027 竜槍のジャルド = MLBB の子龍。強い通常攻撃（パッシブ 竜の三連突き）だけの全身のモーション
// （詠唱は FX_H027.motion、普段の通常攻撃はモーションクリップのまま）。
//   三連突き — 肘を引いて槍を構え（振りかぶり）、1 発目を突き出す（打撃 = sim の 1 発目の命中 = attackReleased）。
//             穂先を少し引いては突き直し、2・3 発目を sim の 2・3 発目の命中（flurryInterval = 4 tick ≈ 0.133 秒おき）に突き切る。
//             MLBB（f484 / f488 / f492）: 1 本ごとに突きの向きが少し変わる。腕は前へ伸びたまま、胴が突くたびに前へ入る。
// 打撃の後の時刻は攻撃速度で縮めない（HeroAnimator は強い通常攻撃の戻りを等速で再生する。MLBB も奥義の攻撃速度で縮まない）。
// 角度は体の鉛直に対して書く（MotionBuilder.worldAngles）。

enum Motion_H027: HeroMotionScript {
    private static let hero = "H027"

    /// 突き出した腕（向き yaw・胴のひねり twist・前傾 lean）。
    private static func extended(_ p: inout HeroPose, yaw: Float, twist: Float, lean: Float, glow: Float) {
        p.armR = ArmPose(pitch: 1.55, out: 0.05, yaw: yaw, elbow: 0.02)
        p.weaponR = -1.57
        p.armL = ArmPose(pitch: 1.35, out: 0.05, yaw: 0.45 + yaw * 0.5, elbow: 0.55)
        p.torsoYaw = twist
        p.torsoPitch = lean
        p.headPitch = 0.05
        p.glow = glow
    }

    /// 穂先を少し引く（肘を曲げ、胴を戻す）。
    private static func retract(_ p: inout HeroPose, twist: Float) {
        p.armR = ArmPose(pitch: 1.25, out: 0.18, yaw: 0, elbow: 0.95)
        p.weaponR = -1.5
        p.armL = ArmPose(pitch: 1.25, out: 0.1, yaw: 0.5, elbow: 0.85)
        p.torsoYaw = twist
        p.torsoPitch = 0.08
        p.glow = 1.0
    }

    static func empoweredAttack(_ base: MotionBuilder) -> MotionClip? {
        var m = base
        m.worldAngles = true
        let k = KitTimes(hero, .passive)
        let gap = max(0.08, k.seconds("flurryInterval"))
        let hits = max(1, k.count("flurryHits"))
        // 構え: 肘を後ろへ引いて槍を腰だめに、胴を右へひねる。左手は柄を前で支える
        m.key(0.13, .out) { p in
            p.armR = ArmPose(pitch: 0.9, out: 0.3, yaw: -0.2, elbow: 1.7)
            p.weaponR = -1.4
            p.armL = ArmPose(pitch: 1.2, out: 0.1, yaw: 0.55, elbow: 1.0)
            p.torsoYaw = 0.55
            p.torsoPitch = 0.04
            p.headPitch = 0
            p.glow = 0.9
        }
        // 1 発目（打撃 = sim の 1 発目の命中）
        m.key(0.05, .snap) { p in extended(&p, yaw: 0.15, twist: -0.4, lean: 0.14, glow: 1.6) }
        m.markImpact()
        // 2・3 発目: 引き（間の 4 割）→ 突き（6 割）。突き切るキーが sim の命中の時刻（impact + gap × n）に来る
        let yaws: [Float] = [0.27, 0.05, 0.18, 0.1]
        for n in 1..<hits {
            m.key(gap * 0.4, .out) { p in retract(&p, twist: 0.12) }
            let yaw = yaws[(n - 1) % yaws.count]
            m.key(gap * 0.6, .snap) { p in
                extended(&p, yaw: yaw, twist: -0.45 - 0.05 * Float(n), lean: 0.16 + 0.03 * Float(n), glow: 1.6 + 0.2 * Float(n))
            }
        }
        // 突き切ったまま少し止めて戻す（戻りの終わり = 3 発目 + 0.08 + 0.2 秒。sim の攻撃状態 0.32 秒より長い）
        m.hold(0.08) { p in p.glow = 1.2 }
        return m.build(recover: 0.2)
    }
}
