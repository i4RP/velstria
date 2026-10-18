import Foundation
import simd

// 担当: hero-models。全身のモーション（スキル・通常攻撃の MotionClip）の足の接地（docs/HERO_MOTION.md「全身のモーション」）。
// HeroPose.plant > 0 の間、足首を目標（HeroPose.footR / footL = 待機の足首からのずれ、ヒーロー空間・m）へ置く腿・脛の角度を
// 2 関節の IK で解き、作者が書いた脚の角度と plant の重みで混ぜる。そのうえで足首が地面（待機の足首の高さ）より下なら体ごと持ち上げる。
// 手続きモデル・スキンメッシュのどちらも HeroPose の脚の角度で骨を置く（HeroSegmentRotations と HeroModelLibrary.apply が同じ合成順）
// ので、角度を解けば両方に効く。plant = 0（既定・既存のすべての動き）は何もしない。
//
// 座標（両モデル共通）: ヒーロー空間 = motion エンティティの親（body）のローカル。足元が原点・Y 上・正面 -Z・右 +X・m（拡縮込み）。
//   体の位置 offset、全身の回転 Rb = ry(yaw)·rx(-pitch)·rz(roll)（足元を中心に回る）、腰の関節 = 待機の腰 - (0, hipsDrop·dropScale, 0)、
//   腰の回転 Rh = ry(hipsYaw)·rx(-hipsPitch)·rz(hipsRoll)、腿の付け根 = 腰 + Rh·socket、腿の向き A·(0,-1,0)（A = Rh·rx(pitch)·rz(±out)）、
//   脛の向き A·rx(-knee)·(0,-1,0)。足首 = offset + Rb·(付け根 + 腿·thigh + 脛·shin)。

/// 脚の寸法（モデルごとに読み込み時に 1 度だけ作る。値型・確保なし）。
struct HeroLegRig {
    /// 待機の腰の関節の位置（m、拡縮込み。手続きモデルは (0, 腰の高さ, 0)）。
    let hips: V3
    /// 腰の関節 → 腿の付け根（待機。m、拡縮込み）。
    let socketR: V3
    let socketL: V3
    let thigh: Float
    let shin: Float
    /// HeroPose.hipsDrop 1 あたりの腰の沈み（m）。
    let dropScale: Float
    /// 待機の足首（plant の目標の原点。ヒーロー空間・m）。足首の地面の高さはこの y。
    private(set) var restAnkleR = V3.zero
    private(set) var restAnkleL = V3.zero

    init(hips: V3, socketR: V3, socketL: V3, thigh: Float, shin: Float, dropScale: Float, rest: HeroPose) {
        self.hips = hips
        self.socketR = socketR
        self.socketL = socketL
        self.thigh = max(0.02, thigh)
        self.shin = max(0.02, shin)
        self.dropScale = dropScale
        // 待機の立ち姿（体の位置・傾き・腰の沈みなし）の足首
        var r = rest
        r.offset = .zero
        r.pitch = 0
        r.roll = 0
        r.yaw = 0
        r.hipsDrop = 0
        r.hipsYaw = 0
        r.hipsRoll = 0
        r.hipsPitch = 0
        restAnkleR = ankle(r, right: true)
        restAnkleL = ankle(r, right: false)
    }

    /// 手続きモデルの寸法（BodyMetrics・ブループリントの拡縮）。
    init(metrics m: BodyMetrics, scale s: Float, rest: HeroPose) {
        self.init(hips: V3(0, m.hipY * s, 0), socketR: V3(m.hipHalf * s, 0, 0), socketL: V3(-m.hipHalf * s, 0, 0),
                  thigh: m.thigh * s, shin: m.shin * s, dropScale: s, rest: rest)
    }

    @inline(__always) private static func body(_ p: HeroPose) -> simd_quatf { ry(p.yaw) * rx(-p.pitch) * rz(p.roll) }
    @inline(__always) private static func hipsRotation(_ p: HeroPose) -> simd_quatf {
        ry(p.hipsYaw) * rx(-p.hipsPitch) * rz(p.hipsRoll)
    }

    /// 腿の付け根（motion のローカル = 体の回転の前。m）。
    @inline(__always) private func socket(_ p: HeroPose, right: Bool) -> V3 {
        hips - V3(0, p.hipsDrop * dropScale, 0) + Self.hipsRotation(p).act(right ? socketR : socketL)
    }

    /// 足首（ヒーロー空間）。脚の角度は p.legR / p.legL。
    func ankle(_ p: HeroPose, right: Bool) -> V3 {
        let leg = right ? p.legR : p.legL
        let a = Self.hipsRotation(p) * rx(leg.pitch) * rz(right ? leg.out : -leg.out)
        let down = V3(0, -1, 0)
        let local = socket(p, right: right) + a.act(down) * thigh + (a * rx(-leg.knee)).act(down) * shin
        return p.offset + Self.body(p).act(local)
    }

    /// 足首を target（ヒーロー空間）へ置く脚の角度。膝は前へ曲げる。届かなければ伸ばして向け、近すぎれば曲げ切って向ける。
    func solve(_ p: HeroPose, target: V3, right: Bool) -> LegPose {
        let local = Self.body(p).inverse.act(target - p.offset)
        var v = Self.hipsRotation(p).inverse.act(local - socket(p, right: right))
        let a = thigh, b = shin
        let dMax = (a + b) * 0.999
        let dMin = abs(a - b) + 0.1 * (a + b)
        var d = simd_length(v)
        if d < 1e-5 {
            v = V3(0, -1, 0)
            d = 1
        }
        let dc = min(dMax, max(dMin, d))
        v *= dc / d
        // 膝の曲げ（0 = まっすぐ）: 腿と脛のなす角の補角
        let cosInner = (a * a + b * b - dc * dc) / (2 * a * b)
        let knee = Float.pi - acos(min(1, max(-1, cosInner)))
        // 腿の局所（rz → rx の前）で足首は (0, -m, zl)。rz(out) で x を、rx(pitch) で y-z 面の向きを合わせる
        let m = a + b * cos(knee)
        let zl = b * sin(knee)
        let out = asin(min(0.99, max(-0.99, v.x / max(1e-4, m))))
        var pitch = atan2(v.z, v.y) - atan2(zl, -m * cos(out))
        if pitch > .pi { pitch -= 2 * .pi }
        if pitch < -.pi { pitch += 2 * .pi }
        return LegPose(pitch: pitch, out: right ? out : -out, knee: knee)
    }

    /// p.plant の重みで脚を目標へ解き、足首が地面より下なら体ごと持ち上げる（p を書き換える）。plant = 0 は何もしない。
    func applyPlant(_ p: inout HeroPose) {
        let w = min(1, max(0, p.plant))
        guard w > 0.001 else { return }
        var tR = restAnkleR + p.footR
        var tL = restAnkleL + p.footL
        // 目標は地面より下に置かない
        tR.y = max(tR.y, restAnkleR.y)
        tL.y = max(tL.y, restAnkleL.y)
        let r = solve(p, target: tR, right: true)
        let l = solve(p, target: tL, right: false)
        p.legR = LegPose.mix(p.legR, r, w)
        p.legL = LegPose.mix(p.legL, l, w)
        // 地面より下に入った足首（届かない目標・作者の角度との混ぜ）は体ごと持ち上げる（重みに関係なく、足を地面に埋めない）
        let low = min(ankle(p, right: true).y - restAnkleR.y, ankle(p, right: false).y - restAnkleL.y)
        if low < 0 { p.offset.y -= low }
    }

    /// 足首の地面からの高さ（右・左。m）。テスト・確認用。
    func ankleHeights(_ p: HeroPose) -> (right: Float, left: Float) {
        (ankle(p, right: true).y - restAnkleR.y, ankle(p, right: false).y - restAnkleL.y)
    }
}
