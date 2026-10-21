import Foundation

/// Authored locomotion for the playable roster. Distances are in leg-length units;
/// cadence uses the actual (scaled) skeleton length, not the character's class.
/// No clips, entities, timers or per-frame collections are allocated here.
struct HeroGait {
    let name: String
    let reach: Float
    let contact: Float
    let clearance: Float
    let stance: Float
    let bounce: Float
    let sway: Float
    let twist: Float
    let lean: Float
    let armSwing: Float
    let armLag: Float
    let toeRoll: Float

    static func authored(for heroID: String?) -> HeroGait? {
        switch heroID {
        case "H025": // ルミナ: 長い弧で静かに運ぶ、弓を安定させた足取り
            return .init(name: "moonStride", reach: 0.48, contact: 0.58, clearance: 0.12, stance: 0.025, bounce: 0.012, sway: 0.018, twist: 0.09, lean: 0.06, armSwing: 0.32, armLag: 0.12, toeRoll: 0.18)
        case "H026": // エウリア: 素早い切り返しを感じる小刻みなステップ
            return .init(name: "sparkStep", reach: 0.34, contact: 0.53, clearance: 0.23, stance: 0.035, bounce: 0.035, sway: 0.022, twist: 0.13, lean: 0.12, armSwing: 0.48, armLag: 0.06, toeRoll: 0.28)
        case "H027": // ジャルド: 槍の軸を保ち、膝を送り出す堂々とした歩幅
            return .init(name: "lancerMarch", reach: 0.46, contact: 0.61, clearance: 0.20, stance: 0.06, bounce: 0.022, sway: 0.012, twist: 0.06, lean: 0.10, armSwing: 0.30, armLag: 0.10, toeRoll: 0.22)
        case "H028": // ザイル: 腰を低く、足を地面近くで素早く回収
            return .init(name: "riftProwl", reach: 0.51, contact: 0.54, clearance: 0.09, stance: 0.045, bounce: 0.009, sway: 0.014, twist: 0.11, lean: 0.25, armSwing: 0.24, armLag: 0.18, toeRoll: 0.12)
        case "H029": // ボルグ: 巨体と盾の重量を長い支持時間で受け止める
            return .init(name: "bulwarkTread", reach: 0.36, contact: 0.70, clearance: 0.13, stance: 0.12, bounce: 0.028, sway: 0.045, twist: 0.045, lean: 0.08, armSwing: 0.18, armLag: 0.25, toeRoll: 0.10)
        case "H030": // ライナ: 大砲を抱えた短い弾む足取り、上半身は抑える
            return .init(name: "cannonScurry", reach: 0.30, contact: 0.57, clearance: 0.25, stance: 0.065, bounce: 0.045, sway: 0.028, twist: 0.035, lean: 0.16, armSwing: 0.12, armLag: 0.16, toeRoll: 0.26)
        case "H031": // オーリア: ローブを乱さない狭い足幅と穏やかな重心
            return .init(name: "frostProcession", reach: 0.39, contact: 0.65, clearance: 0.07, stance: 0.018, bounce: 0.006, sway: 0.010, twist: 0.055, lean: 0.025, armSwing: 0.20, armLag: 0.22, toeRoll: 0.08)
        case "H032": // ディアス: 前重心で膝を高く回収する闘士のステップ
            return .init(name: "fighterDrive", reach: 0.43, contact: 0.52, clearance: 0.29, stance: 0.08, bounce: 0.038, sway: 0.025, twist: 0.18, lean: 0.22, armSwing: 0.60, armLag: 0.04, toeRoll: 0.32)
        case "H033": // ヴァルド: 大剣を支え、肩を遅らせる長く重い踏み込み
            return .init(name: "bloodStride", reach: 0.55, contact: 0.63, clearance: 0.16, stance: 0.075, bounce: 0.018, sway: 0.030, twist: 0.12, lean: 0.17, armSwing: 0.22, armLag: 0.30, toeRoll: 0.20)
        case "H034": // ゴルム: 鎖の重さを横へ受け流す幅広の足取り
            return .init(name: "chainLumber", reach: 0.40, contact: 0.68, clearance: 0.18, stance: 0.14, bounce: 0.032, sway: 0.060, twist: 0.15, lean: 0.14, armSwing: 0.38, armLag: 0.34, toeRoll: 0.14)
        default: return nil
        }
    }

    func strideReach(speed: Float) -> Float {
        reach * (0.55 + 0.45 * smooth01(speed / 3.3))
    }

    /// A support foot travels 2 * reach while the body advances by the same distance.
    func cyclesPerSecond(speed: Float, legLength: Float) -> Float {
        max(0, speed) * contact / (2 * strideReach(speed: speed) * max(0.2, legLength))
    }

    /// Sagittal two-bone solve. Support is linear; recovery has a smooth arc and
    /// zero vertical velocity at lift-off/landing. Both phases meet at identical poses.
    func leg(phase: Float, speed: Float, height: Float, thighRatio: Float) -> LegPose {
        let t = phase - floor(phase)
        let a = strideReach(speed: speed)
        let x: Float, lift: Float, roll: Float
        if t < contact {
            let u = t / contact
            x = a * (1 - 2 * u)
            lift = 0
            roll = toeRoll * (smooth01((u - 0.75) / 0.25) - 0.45 * (1 - smooth01(u / 0.18)))
        } else {
            let u = (t - contact) / (1 - contact)
            // Hermite endpoints share the support phase's backwards velocity.
            let tangent = -2 * a * (1 - contact) / contact
            x = -a + 2 * a * smooth01(u) + tangent * (2 * u * u * u - 3 * u * u + u)
            lift = clearance * pow(sin(.pi * u), 2)
            roll = toeRoll * (1 - 1.45 * smooth01(u))
        }
        let upper = min(0.65, max(0.35, thighRatio)), lower = 1 - upper
        let y = max(0.2, height - lift)
        let d = min(0.999, max(abs(upper - lower) + 0.001, sqrt(x * x + y * y)))
        let knee = .pi - acos(min(1, max(-1, (upper * upper + lower * lower - d * d) / (2 * upper * lower))))
        let pitch = atan2(x, y) + acos(min(1, max(-1, (upper * upper + d * d - lower * lower) / (2 * upper * d))))
        return LegPose(pitch: pitch, out: stance, knee: knee, ankle: knee - pitch - roll)
    }

    func pose(rest r: HeroPose, phase: Float, speed: Float, legLength: Float,
              thighRatio: Float, swingR: Float, swingL: Float) -> HeroPose {
        var p = r
        let ph = phase * 2 * Float.pi
        let wave = sin(ph), weight = cos(ph * 2)
        let a = strideReach(speed: speed)
        // Leave extension reserve for the recovery curve and lateral stance.
        let height = sqrt(max(0.1, 0.96 * 0.96 - a * a)) - bounce * (1 - weight)
        p.legR = leg(phase: phase, speed: speed, height: height, thighRatio: thighRatio)
        p.legL = leg(phase: phase + 0.5, speed: speed, height: height, thighRatio: thighRatio)
        p.hipsDrop = (1 - height) * legLength
        p.offset = SIMD3<Float>(sway * wave * legLength, 0, 0)
        p.hipsYaw = -twist * wave * 0.45
        p.hipsRoll = 0 // Keep the support chain vertical; weight shift uses translation.
        p.torsoPitch = lean
        p.torsoYaw = twist * sin(ph - armLag)
        p.torsoRoll = -sway * wave * 0.5
        p.headPitch = -lean * 0.65
        p.headYaw = -p.torsoYaw * 0.8
        let arms = sin(ph - armLag)
        p.armR.pitch -= armSwing * swingR * arms
        p.armL.pitch += armSwing * swingL * arms
        p.armR.elbow += 0.35 * swingR
        p.armL.elbow += 0.35 * swingL
        p.cape = 0.18 + speed * 0.07 + bounce * sin(ph * 2 - 0.5)
        p.wings = 0
        return p
    }
}
