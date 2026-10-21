import Foundation

/// Authored standing silhouettes for the playable roster, separate from combat rest.
/// Only the upper body moves: feet keep their authored placement instead of sliding
/// with a whole-body sine wave. These are joint poses, not terrain/contact IK.
/// Evaluation uses value types only; no timers, clips, assets or effects are created.
struct HeroIdle {
    private enum Style {
        case moonSentinel, stormWeaver, dragonGuard, riftWatch, holyBulwark
        case cannonCompanion, frostSovereign, abyssChallenger, bloodHunter, chainCaptain
    }

    let name: String
    let breathPeriod: Float
    let gesturePeriod: Float
    private let style: Style

    static func authored(for heroID: String?) -> HeroIdle? {
        switch heroID {
        case "H025": return .init(name: "moonSentinel", breathPeriod: 5.8, gesturePeriod: 15.2, style: .moonSentinel)
        case "H026": return .init(name: "stormWeaver", breathPeriod: 4.1, gesturePeriod: 10.8, style: .stormWeaver)
        case "H027": return .init(name: "dragonGuard", breathPeriod: 4.8, gesturePeriod: 13.6, style: .dragonGuard)
        case "H028": return .init(name: "riftWatch", breathPeriod: 5.1, gesturePeriod: 11.4, style: .riftWatch)
        case "H029": return .init(name: "holyBulwark", breathPeriod: 5.6, gesturePeriod: 14.8, style: .holyBulwark)
        case "H030": return .init(name: "cannonCompanion", breathPeriod: 3.6, gesturePeriod: 9.6, style: .cannonCompanion)
        case "H031": return .init(name: "frostSovereign", breathPeriod: 6.4, gesturePeriod: 16.0, style: .frostSovereign)
        case "H032": return .init(name: "abyssChallenger", breathPeriod: 3.1, gesturePeriod: 9.2, style: .abyssChallenger)
        case "H033": return .init(name: "bloodHunter", breathPeriod: 4.9, gesturePeriod: 12.8, style: .bloodHunter)
        case "H034": return .init(name: "chainCaptain", breathPeriod: 4.4, gesturePeriod: 13.2, style: .chainCaptain)
        default: return nil
        }
    }

    /// A calm, readable silhouette even before the first animation tick.
    func baseline(rest: HeroPose) -> HeroPose {
        var p = rest
        p.offset = .zero
        p.pitch = 0
        p.roll = 0
        p.yaw = 0
        p.hipsDrop = 0
        p.hipsPitch = 0
        p.hipsRoll = 0
        p.hipsYaw = 0
        // Existing plant targets belong to the combat stance. Using those targets
        // here would spread Lumina's legs again and erase the authored silhouettes.
        p.plant = 0
        p.footR = .zero
        p.footL = .zero
        switch style {
        case .moonSentinel:
            // ルミナ: 長い脚をほぼ平行に、背筋を伸ばした静かな月の番人。
            p.legR = Self.leg(0.012, -0.035, 0.025)
            p.legL = Self.leg(0.032, -0.020, 0.040)
            p.torsoPitch = -0.015
            p.torsoYaw = 0.035
            p.torsoRoll = -0.008
            p.headPitch = -0.018
            p.headYaw = -0.035
            p.headRoll = 0.006
            p.armR = ArmPose(pitch: 0.12, out: 0.055, yaw: 0.12, elbow: 0.40)
            // The tall crescent bow retains its raised support arm and safe angle.
        case .stormWeaver:
            // エウリア: 片手の球電を見せる非対称のシルエット。左手は腰へ。
            p.legR = Self.leg(0.035, 0.015, 0.065)
            p.legL = Self.leg(-0.025, 0.040, 0.055)
            p.torsoPitch = -0.020
            p.torsoYaw = -0.090
            p.torsoRoll = 0.025
            p.headPitch = 0.015
            p.headYaw = 0.075
            p.headRoll = -0.020
            p.armR = ArmPose(pitch: 0.36, out: 0.18, yaw: -0.12, elbow: 1.14)
            p.armL = ArmPose(pitch: 0.08, out: 0.11, yaw: 0.16, elbow: 0.55)
        case .dragonGuard:
            // ジャルド: 少し前後に構えた脚、胸を張り、槍を両腕で安定させる。
            p.legR = Self.leg(-0.060, 0.050, 0.060)
            p.legL = Self.leg(0.090, 0.070, 0.075)
            p.torsoPitch = -0.035
            p.torsoYaw = -0.055
            p.headPitch = -0.030
            p.headYaw = 0.055
        case .riftWatch:
            // ザイル: 刃を低く保つ半身。視線だけを先行させて周囲を探る。
            p.legR = Self.leg(0.120, 0.045, 0.180)
            p.legL = Self.leg(-0.020, 0.065, 0.090)
            p.torsoPitch = 0.105
            p.torsoYaw = -0.150
            p.torsoRoll = -0.018
            p.headPitch = -0.085
            p.headYaw = 0.145
            p.armR.out += 0.045
            p.armL = ArmPose(pitch: -0.055, out: 0.090, yaw: -0.12, elbow: 0.42)
        case .holyBulwark:
            // ボルグ: 巨体を受け止める開きと低い重心。盾と槌の保持は固定。
            p.legR = Self.leg(0.050, 0.145, 0.100)
            p.legL = Self.leg(0.065, 0.125, 0.120)
            p.torsoPitch = -0.025
            p.torsoYaw = 0.040
            p.torsoRoll = 0.012
            p.headPitch = -0.020
            p.headYaw = -0.040
        case .cannonCompanion:
            // ライナ: 砲の重みを受けた非対称の足と肩。両手の支持関係を保つ。
            p.legR = Self.leg(0.090, 0.025, 0.135)
            p.legL = Self.leg(-0.025, 0.055, 0.065)
            p.torsoPitch = -0.025
            p.torsoYaw = 0.035
            p.torsoRoll = -0.035
            p.headPitch = -0.025
            p.headYaw = -0.035
            p.headRoll = 0.040
        case .frostSovereign:
            // オーリア: ドレスを崩さない狭い足幅、顎を上げた女王の静けさ。
            p.legR = Self.leg(0.010, 0.000, 0.020)
            p.legL = Self.leg(0.035, -0.010, 0.045)
            p.torsoPitch = -0.035
            p.torsoYaw = 0.065
            p.torsoRoll = 0.010
            p.headPitch = -0.055
            p.headYaw = -0.065
            p.headRoll = -0.015
            p.armR = ArmPose(pitch: 0.24, out: 0.11, yaw: -0.08, elbow: 0.92)
            p.armL = ArmPose(pitch: 0.10, out: 0.06, yaw: 0.10, elbow: 0.28)
        case .abyssChallenger:
            // ディアス: 前足を出した闘士。拳の高さをずらして挑発的に構える。
            p.legR = Self.leg(0.130, 0.110, 0.180)
            p.legL = Self.leg(-0.020, 0.060, 0.095)
            p.torsoPitch = 0.075
            p.torsoYaw = -0.100
            p.torsoRoll = -0.025
            p.headPitch = -0.060
            p.headYaw = 0.100
            p.headRoll = 0.025
            p.armR = ArmPose(pitch: 0.42, out: 0.22, yaw: 0.12, elbow: 1.18)
            p.armL = ArmPose(pitch: 0.24, out: 0.20, yaw: -0.10, elbow: 0.88)
        case .bloodHunter:
            // ヴァルド: 大剣を持つ右肩を前に、左手は腰近くへ落とす。
            p.legR = Self.leg(0.045, 0.070, 0.080)
            p.legL = Self.leg(-0.045, 0.100, 0.070)
            p.torsoPitch = 0.025
            p.torsoYaw = -0.115
            p.torsoRoll = 0.025
            p.headPitch = -0.035
            p.headYaw = 0.105
            p.headRoll = -0.018
            p.armL = ArmPose(pitch: 0.06, out: 0.12, yaw: 0.12, elbow: 0.45)
        case .chainCaptain:
            // ゴルム: 短い脚で樽のような体を支え、空いた左手を腹の脇へ。
            p.legR = Self.leg(0.055, 0.170, 0.110)
            p.legL = Self.leg(0.075, 0.130, 0.150)
            p.torsoPitch = 0.055
            p.torsoYaw = -0.045
            p.torsoRoll = 0.035
            p.headPitch = -0.035
            p.headYaw = 0.045
            p.headRoll = -0.025
            p.armL = ArmPose(pitch: 0.12, out: max(rest.armL.out, 0.25), yaw: 0.10, elbow: 0.75)
        }
        return p
    }

    func pose(rest: HeroPose, time: Float) -> HeroPose {
        var p = baseline(rest: rest)
        let t = time.isFinite ? max(0, time) : 0
        let phase = t.truncatingRemainder(dividingBy: breathPeriod) * (2 * Float.pi / breathPeriod)
        let breath = 0.5 - 0.5 * cos(phase)
        let follow = sin(phase - 0.35)
        let weight = sin(phase)
        // Each signature waits in a calm pose before anticipating, holding and
        // settling. The delayed channel lets the gaze lead the shoulders/hand.
        let gesture = Self.accent(t, period: gesturePeriod, delay: 0)
        let settle = Self.accent(t, period: gesturePeriod, delay: 0.28)
        switch style {
        case .moonSentinel:
            p.torsoPitch -= 0.006 * breath
            p.torsoRoll += 0.003 * follow
            p.headPitch += 0.004 * breath - 0.015 * gesture
            p.headYaw += 0.065 * gesture
            p.armR.elbow += 0.012 * follow + 0.045 * settle
            p.cape += 0.012 * breath
        case .stormWeaver:
            p.torsoPitch -= 0.016 * breath
            p.torsoRoll += 0.010 * follow
            p.headPitch += 0.009 * breath + 0.050 * gesture
            p.headYaw -= 0.160 * gesture
            p.armR.pitch += 0.025 * follow + 0.160 * settle
            p.armR.elbow += 0.020 * breath + 0.120 * settle
            p.armR.yaw -= 0.090 * settle
            p.armL.elbow += 0.020 * follow
        case .dragonGuard:
            p.torsoPitch -= 0.013 * breath
            p.torsoYaw += 0.018 * settle
            p.headPitch += 0.008 * follow - 0.025 * gesture
            p.headYaw += 0.130 * gesture
            // Spear hands stay coherent; the entire shoulder line turns together.
            p.cape += 0.018 * breath + 0.010 * settle
        case .riftWatch:
            p.torsoPitch += 0.008 * breath
            p.torsoYaw -= 0.035 * settle
            p.headPitch -= 0.008 * follow + 0.020 * gesture
            p.headYaw -= 0.210 * gesture
            p.armL.pitch -= 0.020 * follow
            p.armL.elbow += 0.070 * settle
            p.cape += 0.016 * breath
        case .holyBulwark:
            p.torsoPitch -= 0.020 * breath
            p.torsoRoll += 0.005 * follow
            p.headPitch += 0.009 * follow - 0.040 * gesture
            p.headYaw += 0.095 * gesture
            p.torsoYaw += 0.020 * settle
            p.cape += 0.022 * breath
        case .cannonCompanion:
            // No independent arm/weapon movement: both hands and the large cannon
            // travel with the torso, preserving the existing support-hand solve.
            p.torsoPitch -= 0.012 * breath
            p.torsoRoll += 0.010 * follow - 0.012 * settle
            p.headPitch += 0.010 * follow + 0.085 * gesture
            p.headYaw -= 0.150 * gesture
            p.headRoll += 0.055 * settle
        case .frostSovereign:
            p.torsoPitch -= 0.007 * breath
            p.torsoRoll += 0.003 * follow
            p.headPitch += 0.005 * follow - 0.018 * gesture
            p.headYaw += 0.075 * gesture
            p.armR.pitch += 0.012 * follow + 0.180 * settle
            p.armR.elbow += 0.010 * breath + 0.100 * settle
            p.armR.out += 0.045 * settle
            p.armL.out += 0.006 * follow
            p.cape += 0.010 * breath + 0.012 * settle
        case .abyssChallenger:
            p.torsoPitch += 0.017 * breath
            p.torsoRoll += 0.012 * follow
            p.torsoYaw -= 0.025 * settle
            p.headPitch -= 0.012 * breath + 0.055 * gesture
            p.headRoll += 0.065 * gesture
            p.armR.elbow += 0.025 * follow + 0.170 * settle
            p.armR.yaw += 0.070 * settle
            p.armL.pitch -= 0.018 * follow
            p.armL.elbow += 0.090 * settle
        case .bloodHunter:
            p.torsoPitch -= 0.014 * breath
            p.torsoRoll += 0.008 * follow
            p.headPitch += 0.008 * follow - 0.025 * gesture
            p.headYaw += 0.180 * gesture
            p.armL.elbow += 0.018 * breath + 0.100 * settle
            p.cape += 0.016 * breath + 0.015 * settle
        case .chainCaptain:
            p.torsoPitch -= 0.024 * breath
            p.torsoRoll += 0.014 * follow
            p.headPitch += 0.012 * follow + 0.045 * gesture
            p.headYaw -= 0.110 * gesture
            p.armL.pitch += 0.022 * breath + 0.260 * settle
            p.armL.elbow += 0.030 * follow + 0.320 * settle
            p.armL.yaw += 0.080 * settle
        }
        // Slight shoulder counterbalance is intentionally upper-body only. Do not
        // translate/rotate the pelvis: no foot contact solver is used by these idles.
        p.torsoRoll += 0.002 * weight
        return p
    }

    @inline(__always) private static func leg(_ pitch: Float, _ out: Float, _ knee: Float) -> LegPose {
        LegPose(pitch: pitch, out: out, knee: knee, ankle: knee - pitch)
    }

    /// Quintic boundaries have zero velocity and acceleration. The complete accent
    /// fits inside its period, including its delayed follow-through, so wrapping
    /// cannot snap a hand or head. A long quiet interval avoids repetitive fidgeting.
    @inline(__always) private static func accent(_ time: Float, period: Float, delay: Float) -> Float {
        let local = time.truncatingRemainder(dividingBy: period) - (period * 0.46 + delay)
        let rise: Float = 0.90, hold: Float = 0.65, fall: Float = 1.45
        if local < 0 || local >= rise + hold + fall { return 0 }
        if local < rise { return smoother(local / rise) }
        if local < rise + hold { return 1 }
        return 1 - smoother((local - rise - hold) / fall)
    }

    @inline(__always) private static func smoother(_ value: Float) -> Float {
        let x = min(1, max(0, value))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}
