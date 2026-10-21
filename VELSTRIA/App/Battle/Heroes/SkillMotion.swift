import Foundation
import simd
import VelstriaCore

// 担当: hero-models（スキル演出）。スキルごとの詠唱モーション（多段のキー姿勢、全身・跳躍・回転を含む）。
// 書き方: MotionBuilder に「技」（windup・slash・leap・spin …）を順に積む。各キーは直前のキーの姿勢から変える
// （累積）ので、技を並べるだけで連続した動きになる。最後に build(recover:) で元の姿勢へ戻る時間を足す。
// sim はスキルの効果を発動の tick に即時に解決するので、打撃のキー（strike）は 0.05〜0.15 秒以内に置き、
// 演出（SkillFXRecipe の cast の at）をそこへ合わせる。
// 角度の規約は HeroAnimation.swift と同じ（pitch + = 前、武器角 0 = 真上・-π/2 = 前方、yaw + = 左回り）。

/// 多段の動作クリップ。
struct MotionClip {
    struct Key {
        /// クリップ開始からこのキーに達する時刻（秒）。
        var time: Float
        var pose: HeroPose
        var ease: MotionEase
    }

    var keys: [Key]
    /// 元の姿勢へ戻り終える時刻（= 詠唱状態の長さ）。
    var total: Float
    /// 下半身・全身の移動（跳躍・回転・踏み込み）も動かすか。false なら上半身だけ。
    var fullBody: Bool
    /// 全身のモーションでも、移動している間（sim が動かしている間を含む）は下半身・体の位置を移動の姿勢へ戻す
    /// （HeroAnimator が 0.12 秒で寄せる。足を滑らせない）。既定 false = 従来どおり（既存のヒーローの動きは変えない）。
    var yieldsLowerWhenMoving = false
    /// 打撃の時刻（クリップの秒）。通常攻撃のモーション（HeroMotionProfile.attackMotions）はこれを sim の命中の時刻へ合わせる。
    var impact: Float?
    /// 打つ手（武器の軌跡）。
    var strikeHand: HeroStrikeHand = .right
    /// sim が術者を止めておく長さ（秒。奥義の拘束など）。これがあるモーションは長さの上限を sim の時間に合わせてよい（SkillFXTests）。
    var simLock: Float?
    /// 体の向き（yaw）を 1 回転以上回すモーション（円撃の回転）。戻りは最後のキーに近い向き（2π の倍数だけずらした待機の向き）へ
    /// 戻し、逆回りに巻き戻さない。既定 false = 従来どおり（既存のヒーローの動きは変えない）。
    var wrapsYaw = false

    /// base（現在の移動・待機の姿勢）から評価する。
    func evaluate(base: HeroPose, t: Float) -> HeroPose {
        guard let first = keys.first, t < total else { return base }
        var target: HeroPose
        if t < first.time {
            let e = first.ease.apply(t / max(0.001, first.time))
            target = HeroPose.mix(base, first.pose, e)
            // 足の接地は始めから効かせる（base = 待機の立ち位置 = 目標 0 から踏み出す。重みを混ぜると上げた足が地面に残って滑る）
            target.plant = max(target.plant, first.pose.plant)
            Self.liftSteps(&target, from: base, to: first.pose, e)
        } else if let last = keys.last, t >= last.time {
            let u = smooth01((t - last.time) / max(0.001, total - last.time))
            var back = base
            if last.pose.plant > 0 {
                // 全身のモーションは武器を 1 回転以上回して書くことがある（下から振り上げる・頭上で回す）。待機へ戻る時は
                // 最後のキーに近い向き（2π の倍数だけずらした待機の角）へ戻し、逆回りに回して戻さない
                back.weaponR = last.pose.weaponR + remainder(base.weaponR - last.pose.weaponR, 2 * .pi)
                back.weaponL = last.pose.weaponL + remainder(base.weaponL - last.pose.weaponL, 2 * .pi)
            }
            if wrapsYaw { back.yaw = last.pose.yaw + remainder(base.yaw - last.pose.yaw, 2 * .pi) }
            target = HeroPose.mix(last.pose, back, u)
            // 戻りも最後まで接地したまま待機の立ち位置へ踏み戻す（終わりの姿勢は目標 0 = 待機の脚と同じ）
            target.plant = max(target.plant, last.pose.plant)
            Self.liftSteps(&target, from: last.pose, to: back, u)
        } else {
            var k = 0
            while k + 1 < keys.count && keys[k + 1].time <= t { k += 1 }
            let a = keys[k], b = keys[k + 1]
            let e = b.ease.apply((t - a.time) / max(0.001, b.time - a.time))
            target = HeroPose.mix(a.pose, b.pose, e)
            Self.liftSteps(&target, from: a.pose, to: b.pose, e)
        }
        return fullBody ? target : HeroPose.mixUpper(base, target, 1)
    }

    /// 足の接地のモーションで、キーの間に足首の目標が地面の上を動く足は弧を描いて上げる（踏み出し。滑らせない）。
    /// 上げる高さ = 動く距離の 0.45 倍（最大 0.16 m）× sin(πu)。目標の y（キーに書いた高さ）に足す。
    @inline(__always) static func liftSteps(_ p: inout HeroPose, from a: HeroPose, to b: HeroPose, _ u: Float) {
        guard p.plant > 0.001 else { return }
        let arc = sin(Float.pi * min(1, max(0, u)))
        guard arc > 0 else { return }
        func lift(_ x: SIMD3<Float>, _ y: SIMD3<Float>) -> Float {
            let dx = y.x - x.x, dz = y.z - x.z
            return min(0.16, 0.45 * (dx * dx + dz * dz).squareRoot()) * arc
        }
        p.footR.y += lift(a.footR, b.footR)
        p.footL.y += lift(a.footL, b.footL)
    }

    /// 旧来の 3 段クリップから作る（上半身のみ）。
    init(action c: ActionClip) {
        keys = [Key(time: c.windupTime, pose: c.windup, ease: .out),
                Key(time: c.windupTime + c.strikeTime, pose: c.strike, ease: .in)]
        total = c.total
        fullBody = false
    }

    init(keys: [Key], total: Float, fullBody: Bool) {
        self.keys = keys
        self.total = total
        self.fullBody = fullBody
    }
}

enum MotionEase {
    case linear, out, `in`, inOut, snap

    func apply(_ x: Float) -> Float {
        switch self {
        case .linear: return clamp01(x)
        case .out: return easeOut(x)
        case .in: return easeIn(x)
        case .inOut: return smooth01(x)
        case .snap:
            // 鋭い打撃（ほぼ一瞬で到達して僅かに行き過ぎない）
            let t = clamp01(x)
            return 1 - pow(1 - t, 4)
        }
    }
}

/// 詠唱モーションの組み立て。
struct MotionBuilder {
    let rest: HeroPose
    let style: AttackStyle
    /// 盾持ち（左腕は盾を構えたまま）。
    let shield: Bool
    let twoHanded: Bool
    let bow: Bool
    private(set) var keys: [MotionClip.Key] = []
    /// 直前のキーの姿勢（次のキーはここから変える）。
    var pose: HeroPose
    private(set) var time: Float = 0
    /// 全身を動かすか（leap・spin・lunge などの技を使うと true になる）。
    var fullBody = false
    /// 盾持ちの左腕を胸の前に保つ（既定 true）。false の間に積んだキーは左腕・盾の角も書ける（盾を掲げる・叩きつける）。
    var shieldGuard = true
    /// 移動中は下半身を移動の姿勢へ戻す（MotionClip.yieldsLowerWhenMoving）。
    var yieldsLowerWhenMoving = false
    /// 打撃の時刻（markImpact で今の時刻を入れる）。
    var impact: Float?
    var strikeHand: HeroStrikeHand = .right
    /// sim が術者を止めておく長さ（MotionClip.simLock）。
    var simLock: Float?
    /// 腕の前後（pitch）・武器角・頭の前後を、胴ではなく体の鉛直に対して書く（既定 false = 従来どおり胴に対して）。
    /// 胴を大きく前へ倒す全身のモーションで、腕・武器が胴と一緒に後ろへ回らないようにする。true の間に積んだキーは、
    /// 書いた値（authored）から torsoPitch の分を足し引きして胴の座標へ直して積む（authored は次のキーへ持ち越す）。
    var worldAngles = false
    private var authored: HeroPose

    init(rest: HeroPose, style: AttackStyle, shield: Bool, twoHanded: Bool, bow: Bool) {
        self.rest = rest
        self.style = style
        self.shield = shield
        self.twoHanded = twoHanded
        self.bow = bow
        pose = rest
        authored = rest
    }

    /// 体の鉛直に対して書いた腕・武器・頭の角度を、胴の座標へ直す（胴の前傾 tp = 全身の傾き + 腰の前傾 + 腰に対する胴の前傾:
    /// 腕・武器 + tp、頭 - tp）。
    static func torsoRelative(_ a: HeroPose) -> HeroPose {
        var p = a
        let tp = a.torsoPitch + a.hipsPitch + a.pitch
        p.armR.pitch += tp
        p.armL.pitch += tp
        p.weaponR += tp
        p.weaponL += tp
        p.headPitch -= tp
        return p
    }

    var isRanged: Bool { style == .bow || style == .gun || style == .staff || style == .spellThrow }

    /// dt 秒かけて、直前の姿勢を f で変えた姿勢へ動く。
    mutating func key(_ dt: Float, _ ease: MotionEase = .out, _ f: (inout HeroPose) -> Void) {
        var p = worldAngles ? authored : pose
        f(&p)
        if worldAngles {
            authored = p
            p = Self.torsoRelative(p)
        } else {
            authored = p
        }
        if shield && shieldGuard {
            // 盾は胸の前に保つ（顔を隠さない）
            p.armL = ArmPose(pitch: 0.9, out: 0.35, yaw: 0.1, elbow: 0.7)
            p.weaponL = 0
        }
        time += max(0.01, dt)
        keys.append(MotionClip.Key(time: time, pose: p, ease: ease))
        pose = p
    }

    /// 今の姿勢のまま dt 秒止める（揺らぎ f を足せる）。
    mutating func hold(_ dt: Float, _ f: (inout HeroPose) -> Void = { _ in }) {
        key(dt, .linear, f)
    }

    /// 元の姿勢（rest）から作り直したキー。
    mutating func keyFromRest(_ dt: Float, _ ease: MotionEase = .out, _ f: (inout HeroPose) -> Void) {
        let r = rest
        key(dt, ease) { p in
            let keepOffset = p.offset, keepYaw = p.yaw
            p = r
            p.offset = keepOffset
            p.yaw = keepYaw
            f(&p)
        }
    }

    func build(recover: Float = 0.3) -> MotionClip {
        var c = MotionClip(keys: keys, total: time + max(0.08, recover), fullBody: fullBody)
        c.yieldsLowerWhenMoving = yieldsLowerWhenMoving
        c.impact = impact
        c.strikeHand = strikeHand
        c.simLock = simLock
        return c
    }

    /// 足を接地したまま全身を動かすキー（plant = 1。f の中で足首の目標 footR / footL・体の位置・腰・上半身を書く）。
    /// 足首の目標が動くキーの間は、その足を弧を描いて踏み出す（MotionClip.liftSteps）。全身のモーションになる。
    mutating func planted(_ dt: Float, _ ease: MotionEase = .out, _ f: (inout HeroPose) -> Void) {
        fullBody = true
        key(dt, ease) { p in
            p.plant = 1
            f(&p)
        }
    }

    /// 今の時刻（直前のキーの時刻）を打撃の時刻にする。
    mutating func markImpact() {
        impact = time
    }

    /// 今の時刻（直前に積んだキーの時刻）。
    var now: Float { time }
}

// MARK: - 技（組み合わせて使う部品）

extension MotionBuilder {
    // MARK: 構え・踏み込み

    /// 足を開いて腰を落とす（強い技の前の構え）。
    mutating func brace(_ dt: Float = 0.1, depth: Float = 0.08) {
        fullBody = true
        key(dt) { p in
            p.hipsDrop = depth
            p.legR = LegPose(pitch: -0.25, out: 0.16, knee: 0.55)
            p.legL = LegPose(pitch: 0.35, out: 0.14, knee: 0.5)
        }
    }

    /// 前へ踏み込む（distance m、前 = -Z）。
    mutating func lunge(_ dt: Float = 0.08, distance: Float = 0.35, lean: Float = 0.25) {
        fullBody = true
        key(dt, .snap) { p in
            p.offset.z = -distance
            p.pitch = lean
            p.hipsDrop = 0.1
            p.legL = LegPose(pitch: 0.75, out: 0.08, knee: 0.7)
            p.legR = LegPose(pitch: -0.55, out: 0.08, knee: 0.2)
        }
    }

    /// 後ろへ跳び退く。
    mutating func backstep(_ dt: Float = 0.12, distance: Float = 0.35) {
        fullBody = true
        key(dt, .out) { p in
            p.offset.z = distance
            p.offset.y = 0.12
            p.pitch = -0.2
            p.legL = LegPose(pitch: 0.4, out: 0.1, knee: 0.9)
            p.legR = LegPose(pitch: 0.1, out: 0.1, knee: 0.6)
        }
    }

    /// 足元へ戻る（踏み込み・跳躍の位置を戻す）。
    mutating func settle(_ dt: Float = 0.12) {
        key(dt, .inOut) { p in
            p.offset = .zero
            p.pitch = 0
            p.hipsDrop = 0.04
            p.legR = LegPose(pitch: -0.1, out: 0.12, knee: 0.25)
            p.legL = LegPose(pitch: 0.15, out: 0.12, knee: 0.25)
        }
    }

    /// 跳び上がる（height m。前へ forward m 進む）。
    mutating func leap(_ dt: Float = 0.22, height: Float = 0.9, forward: Float = 0) {
        fullBody = true
        key(dt, .out) { p in
            p.offset.y = height
            p.offset.z = -forward
            p.pitch = -0.15
            p.legR = LegPose(pitch: 0.9, out: 0.1, knee: 1.6)
            p.legL = LegPose(pitch: 0.5, out: 0.1, knee: 1.4)
        }
    }

    /// 着地（強く沈み込む）。
    mutating func land(_ dt: Float = 0.1, depth: Float = 0.22) {
        fullBody = true
        key(dt, .in) { p in
            p.offset.y = 0
            p.pitch = 0.35
            p.hipsDrop = depth
            p.legR = LegPose(pitch: -0.35, out: 0.2, knee: 1.25)
            p.legL = LegPose(pitch: 0.75, out: 0.18, knee: 1.35)
        }
    }

    /// 全身を回す（turns 回転。+ = 左回り）。
    mutating func spin(_ dt: Float = 0.3, turns: Float = 1, arms: Bool = true) {
        fullBody = true
        key(dt, .inOut) { p in
            p.yaw += turns * 2 * .pi
            if arms {
                p.armR = ArmPose(pitch: 1.45, out: 0.9, yaw: 0.2, elbow: 0.1)
                p.armL = ArmPose(pitch: 1.3, out: 0.9, yaw: 0.2, elbow: 0.2)
                p.weaponR = -1.6
                p.weaponL = -1.4
            }
            p.hipsDrop = 0.1
            p.legR = LegPose(pitch: -0.2, out: 0.2, knee: 0.5)
            p.legL = LegPose(pitch: 0.3, out: 0.2, knee: 0.5)
        }
    }

    /// 踏みつけ（右足を上げて地面を踏む）。
    mutating func stomp(_ dt: Float = 0.18) {
        fullBody = true
        key(dt * 0.55, .out) { p in
            p.legR = LegPose(pitch: 1.0, out: 0.15, knee: 1.5)
            p.legL = LegPose(pitch: 0, out: 0.1, knee: 0.2)
            p.offset.y = 0.06
            p.torsoPitch = -0.15
        }
        key(dt * 0.45, .snap) { p in
            p.legR = LegPose(pitch: 0.2, out: 0.2, knee: 0.4)
            p.legL = LegPose(pitch: -0.1, out: 0.15, knee: 0.5)
            p.offset.y = 0
            p.hipsDrop = 0.14
            p.torsoPitch = 0.3
        }
    }

    /// 片膝をつく（祈り・地へ力を流す）。
    mutating func kneel(_ dt: Float = 0.18) {
        fullBody = true
        key(dt) { p in
            p.hipsDrop = 0.28
            p.legL = LegPose(pitch: 1.2, out: 0.1, knee: 1.3)
            p.legR = LegPose(pitch: -0.4, out: 0.08, knee: 1.7)
            p.torsoPitch = 0.2
        }
    }

    /// 突進の前傾（腕を後ろへ流す）。
    mutating func dash(_ dt: Float = 0.1, lean: Float = 0.5) {
        fullBody = true
        key(dt, .snap) { p in
            p.pitch = lean
            p.offset.z = -0.15
            p.armR = ArmPose(pitch: -0.7, out: 0.35, yaw: 0, elbow: 0.3)
            p.armL = ArmPose(pitch: -0.7, out: 0.35, yaw: 0, elbow: 0.3)
            p.weaponR = 0.6
            p.weaponL = 0.6
            p.legR = LegPose(pitch: -0.7, out: 0.06, knee: 0.4)
            p.legL = LegPose(pitch: 0.8, out: 0.06, knee: 1.0)
            p.cape = 0.9
        }
    }

    // MARK: 武器・腕

    /// 横薙ぎの振りかぶり（右上後ろへ）。side = 1 で右から、-1 で左から。
    mutating func windup(_ dt: Float = 0.1, side: Float = 1, power: Float = 1) {
        let twoHanded = self.twoHanded
        key(dt, .out) { p in
            p.armR = ArmPose(pitch: 2.2 + 0.4 * power, out: 0.55, yaw: -0.35 * side, elbow: 0.8)
            p.weaponR = 0.9
            p.torsoYaw = 0.5 * side * power
            p.torsoPitch = -0.1
            p.glow = 0.8
            if p.weaponL != 0 || twoHanded { p.armL = ArmPose(pitch: 1.6, out: 0.3, yaw: -0.4, elbow: 1.2) }
        }
    }

    /// 横薙ぎ（振り抜く）。
    mutating func slash(_ dt: Float = 0.07, side: Float = 1, power: Float = 1) {
        let twoHanded = self.twoHanded
        key(dt, .snap) { p in
            p.armR = ArmPose(pitch: 0.55, out: 0.25, yaw: 0.65 * side, elbow: 0.1)
            p.weaponR = -2.0
            p.torsoYaw = -0.55 * side * power
            p.torsoPitch = 0.2
            p.glow = 1.3
            if twoHanded { p.armL = ArmPose(pitch: 0.7, out: 0.2, yaw: 0.7, elbow: 0.4) }
        }
    }

    /// 二刀の交差斬り（両腕を開いてから交差させる）。
    mutating func crossSlash(_ dt: Float = 0.16) {
        key(dt * 0.45, .out) { p in
            p.armR = ArmPose(pitch: 2.4, out: 0.9, yaw: -0.3, elbow: 0.5)
            p.armL = ArmPose(pitch: 2.4, out: 0.9, yaw: -0.3, elbow: 0.5)
            p.weaponR = 0.6
            p.weaponL = 0.6
            p.torsoPitch = -0.15
            p.glow = 0.9
        }
        key(dt * 0.55, .snap) { p in
            p.armR = ArmPose(pitch: 0.8, out: -0.1, yaw: 0.9, elbow: 0.15)
            p.armL = ArmPose(pitch: 0.8, out: -0.1, yaw: 0.9, elbow: 0.15)
            p.weaponR = -2.3
            p.weaponL = -2.3
            p.torsoPitch = 0.3
            p.glow = 1.4
        }
    }

    /// 頭上へ振りかぶる（両手）。
    mutating func overhead(_ dt: Float = 0.14) {
        let shield = self.shield
        key(dt, .out) { p in
            p.armR = ArmPose(pitch: 3.0, out: 0.25, yaw: 0, elbow: 0.35)
            if !shield { p.armL = ArmPose(pitch: 2.9, out: 0.2, yaw: 0.2, elbow: 0.45) }
            p.weaponR = 0.5
            p.torsoPitch = -0.25
            p.headPitch = -0.25
            p.glow = 1.0
        }
    }

    /// 振り下ろし（地面へ叩きつける）。
    mutating func smash(_ dt: Float = 0.08) {
        let shield = self.shield
        key(dt, .snap) { p in
            p.armR = ArmPose(pitch: 0.95, out: 0.15, yaw: 0.2, elbow: 0.05)
            if !shield { p.armL = ArmPose(pitch: 0.95, out: 0.1, yaw: 0.4, elbow: 0.2) }
            p.weaponR = -2.7
            p.torsoPitch = 0.5
            p.headPitch = 0.15
            p.hipsDrop = max(p.hipsDrop, 0.12)
            p.glow = 1.6
        }
    }

    /// 突き（腕を伸ばし切る）。
    mutating func thrust(_ dt: Float = 0.07, reach: Float = 1) {
        let twoHanded = self.twoHanded
        let style = self.style
        key(dt, .snap) { p in
            p.armR = ArmPose(pitch: 1.55, out: 0.05, yaw: 0.15, elbow: 0.02)
            p.weaponR = -1.57
            p.torsoYaw = -0.35 * reach
            p.torsoPitch = 0.12
            p.glow = 1.3
            if twoHanded || style == .thrust { p.armL = ArmPose(pitch: 1.35, out: 0.05, yaw: 0.45, elbow: 0.6) }
        }
    }

    /// 突きの引き（肘を後ろへ）。
    mutating func chamber(_ dt: Float = 0.1) {
        key(dt, .out) { p in
            p.armR = ArmPose(pitch: 0.9, out: 0.3, yaw: -0.2, elbow: 1.7)
            p.weaponR = -1.4
            p.torsoYaw = 0.45
            p.glow = 0.7
        }
    }

    /// 切り上げ（下から上へ）。
    mutating func uppercut(_ dt: Float = 0.1) {
        key(dt * 0.4, .out) { p in
            p.armR = ArmPose(pitch: -0.3, out: 0.3, yaw: 0.3, elbow: 0.2)
            p.weaponR = -2.9
            p.torsoPitch = 0.3
            p.hipsDrop = max(p.hipsDrop, 0.1)
        }
        key(dt * 0.6, .snap) { p in
            p.armR = ArmPose(pitch: 2.9, out: 0.2, yaw: 0.1, elbow: 0.1)
            p.weaponR = 0.2
            p.torsoPitch = -0.25
            p.headPitch = -0.3
            p.offset.y = max(p.offset.y, 0.12)
            p.glow = 1.5
        }
    }

    /// 武器を手元で回す（turns 回転）。
    mutating func twirl(_ dt: Float = 0.3, turns: Float = 1) {
        key(dt, .linear) { p in
            p.armR = ArmPose(pitch: 1.4, out: 0.3, yaw: 0.3, elbow: 0.5)
            p.weaponR -= turns * 2 * .pi
            p.glow = 1.1
        }
    }

    /// 盾で打つ（左腕を突き出す）。
    mutating func shieldBash(_ dt: Float = 0.08) {
        fullBody = true
        key(dt, .snap) { p in
            p.torsoYaw = -0.5
            p.pitch = 0.2
            p.offset.z = -0.25
            p.armR = ArmPose(pitch: 0.4, out: 0.4, yaw: 0, elbow: 0.6)
            p.legL = LegPose(pitch: 0.6, out: 0.1, knee: 0.6)
            p.legR = LegPose(pitch: -0.45, out: 0.1, knee: 0.25)
        }
    }

    // MARK: 術

    /// 両腕を天へ掲げる（ring = 光輪、wings = 翼の開き）。
    mutating func raise(_ dt: Float = 0.2, glow: Float = 1.6) {
        let shield = self.shield
        key(dt, .out) { p in
            p.armR = ArmPose(pitch: 2.9, out: 0.45, yaw: 0, elbow: 0.2)
            if !shield { p.armL = ArmPose(pitch: 2.9, out: 0.45, yaw: 0, elbow: 0.2) }
            p.weaponR = 0.1
            p.weaponL = 0.1
            p.torsoPitch = -0.22
            p.headPitch = -0.4
            p.glow = glow
            p.ring = 1
            p.wings = 1.2
        }
    }

    /// 両手を前へ突き出す（掌底・放出）。
    mutating func push(_ dt: Float = 0.08, high: Float = 0) {
        let shield = self.shield
        key(dt, .snap) { p in
            p.armR = ArmPose(pitch: 1.5 + high, out: 0.15, yaw: 0.25, elbow: 0.08)
            if !shield { p.armL = ArmPose(pitch: 1.5 + high, out: 0.15, yaw: 0.25, elbow: 0.08) }
            p.weaponR = -1.4
            p.torsoPitch = 0.18
            p.glow = 1.6
        }
    }

    /// 手元へ力を溜める（両手を胸の前に寄せる）。
    mutating func gather(_ dt: Float = 0.15) {
        let shield = self.shield
        key(dt, .out) { p in
            p.armR = ArmPose(pitch: 1.0, out: 0.0, yaw: 0.85, elbow: 1.5)
            if !shield { p.armL = ArmPose(pitch: 1.0, out: 0.0, yaw: 0.85, elbow: 1.5) }
            p.weaponR = -0.6
            p.torsoPitch = -0.05
            p.headPitch = 0.15
            p.glow = 1.2
            p.ring = 0.6
        }
    }

    /// 片手を振りかぶって投げる（火球・符）。
    mutating func throwCast(_ dt: Float = 0.16) {
        key(dt * 0.55, .out) { p in
            p.armR = ArmPose(pitch: 2.3, out: 0.45, yaw: -0.4, elbow: 1.3)
            p.torsoYaw = 0.45
            p.torsoPitch = -0.12
            p.glow = 1.0
        }
        key(dt * 0.45, .snap) { p in
            p.armR = ArmPose(pitch: 1.45, out: 0.05, yaw: 0.3, elbow: 0.05)
            p.weaponR = -1.3
            p.torsoYaw = -0.4
            p.torsoPitch = 0.18
            p.glow = 1.5
        }
    }

    /// 杖を地面へ突き立てる。
    mutating func plant(_ dt: Float = 0.12) {
        key(dt, .snap) { p in
            p.armR = ArmPose(pitch: 0.75, out: 0.2, yaw: 0.2, elbow: 0.5)
            p.weaponR = -0.15
            p.torsoPitch = 0.12
            p.hipsDrop = max(p.hipsDrop, 0.06)
            p.glow = 1.6
            p.ring = 1
        }
    }

    /// 片手を天へ、もう片手を地へ（召喚・号令）。
    mutating func command(_ dt: Float = 0.16) {
        let shield = self.shield
        key(dt, .out) { p in
            p.armR = ArmPose(pitch: 2.8, out: 0.3, yaw: 0, elbow: 0.15)
            if !shield { p.armL = ArmPose(pitch: 0.35, out: 0.75, yaw: 0, elbow: 0.15) }
            p.weaponR = 0.15
            p.torsoPitch = -0.15
            p.headPitch = -0.3
            p.glow = 1.5
            p.ring = 1
        }
    }

    /// 雄叫び（胸を張り腕を広げる）。
    mutating func roar(_ dt: Float = 0.16) {
        let shield = self.shield
        key(dt, .out) { p in
            p.armR = ArmPose(pitch: 0.6, out: 1.2, yaw: 0, elbow: 1.2)
            if !shield { p.armL = ArmPose(pitch: 0.6, out: 1.2, yaw: 0, elbow: 1.2) }
            p.torsoPitch = -0.3
            p.headPitch = -0.45
            p.glow = 1.4
            p.wings = 1.3
        }
    }

    /// 腕を胸の前で交差して守る。
    mutating func guardCross(_ dt: Float = 0.12) {
        let shield = self.shield
        key(dt, .out) { p in
            p.armR = ArmPose(pitch: 1.3, out: -0.05, yaw: 0.95, elbow: 1.4)
            if !shield { p.armL = ArmPose(pitch: 1.3, out: -0.05, yaw: 0.95, elbow: 1.4) }
            p.weaponR = 0.3
            p.torsoPitch = 0.12
            p.hipsDrop = max(p.hipsDrop, 0.08)
            p.glow = 1.2
        }
    }

    // MARK: 射撃

    /// 弓を引き絞る（power = 引きの強さ、up = 仰角 rad）。
    mutating func draw(_ dt: Float = 0.14, up: Float = 0) {
        key(dt, .out) { p in
            p.armL = ArmPose(pitch: 1.55 + up, out: 0.05, yaw: 0.08, elbow: 0.05)
            p.armR = ArmPose(pitch: 1.45 + up, out: 0.1, yaw: 0.95, elbow: 2.1)
            p.torsoYaw = 0.55
            p.headYaw = -0.4
            p.headPitch = -up * 0.6
            p.glow = 1.2
        }
    }

    /// 矢を放つ（引き手が後ろへ抜ける）。
    mutating func release(_ dt: Float = 0.06) {
        key(dt, .snap) { p in
            p.armR = ArmPose(pitch: p.armR.pitch - 0.2, out: 0.75, yaw: 0.4, elbow: 0.45)
            p.torsoYaw = 0.4
            p.glow = 1.6
        }
    }

    /// 銃・弩を構える。
    mutating func aim(_ dt: Float = 0.1, up: Float = 0) {
        key(dt, .out) { p in
            p.armR = ArmPose(pitch: 1.5 + up, out: 0.05, yaw: 0.45, elbow: 0.6)
            p.armL = ArmPose(pitch: 1.55 + up, out: 0.05, yaw: 0.7, elbow: 0.7)
            p.weaponR = -1.57 + up
            p.torsoYaw = 0.25
            p.headPitch = -up * 0.6
            p.glow = 1.0
        }
    }

    /// 反動（上体が跳ね上がる）。
    mutating func recoil(_ dt: Float = 0.06, power: Float = 1) {
        fullBody = true
        key(dt, .snap) { p in
            p.armR.pitch += 0.45 * power
            p.armL.pitch += 0.4 * power
            p.weaponR += 0.45 * power
            p.torsoPitch = -0.2 * power
            p.offset.z = 0.12 * power
            p.glow = 1.8
        }
    }
}
