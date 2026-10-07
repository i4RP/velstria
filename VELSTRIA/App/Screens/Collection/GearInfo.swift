import Foundation
import VelstriaCore

// 担当: collection / battle-hud。ジャングル靴・ローム靴のオプションスキル（祝福）と時間で変わる効果の説明文。
// 数値は Balance.Gear から作るので、バランス調整で説明がずれない。

enum GearInfo {
    private static func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
    private static func clock(_ seconds: Double) -> String {
        let s = Int(seconds)
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    static func name(_ o: GearOption) -> String {
        switch o {
        case .flame: return L("炎の祝福", "Flame")
        case .ice: return L("氷の祝福", "Ice")
        case .bloody: return L("血の祝福", "Bloody")
        case .conceal: return L("隠匿", "Conceal")
        case .encourage: return L("激励", "Encourage")
        case .favor: return L("恩恵", "Favor")
        case .direHit: return L("必中", "Dire Hit")
        }
    }

    static func symbol(_ o: GearOption) -> String {
        switch o {
        case .flame: return "flame.fill"
        case .ice: return "snowflake"
        case .bloody: return "drop.fill"
        case .conceal: return "eye.slash.fill"
        case .encourage: return "bolt.heart.fill"
        case .favor: return "cross.fill"
        case .direHit: return "scope"
        }
    }

    static func summary(_ o: GearOption) -> String {
        let k = Balance.Gear.self
        switch o {
        case .flame:
            return L("狩猟印をヒーローにも使える（確定 \(Int(k.smiteHeroDamage)) ダメージ）。相手の与ダメージ −\(pct(k.flameWeaken))、自分の与ダメージ +\(pct(k.flameSelfBoost))（\(Int(k.smiteHeroEffectDuration)) 秒）",
                     "Hunting spell can hit heroes (\(Int(k.smiteHeroDamage)) true damage). Foe deals −\(pct(k.flameWeaken)) damage, you deal +\(pct(k.flameSelfBoost)) for \(Int(k.smiteHeroEffectDuration))s")
        case .ice:
            return L("狩猟印をヒーローにも使える。相手を \(pct(k.iceSlow)) 減速し、自分は \(pct(k.iceSelfSpeed)) 加速（\(Int(k.smiteHeroEffectDuration)) 秒）",
                     "Hunting spell can hit heroes. Slows the foe \(pct(k.iceSlow)) and speeds you \(pct(k.iceSelfSpeed)) for \(Int(k.smiteHeroEffectDuration))s")
        case .bloody:
            return L("狩猟印をヒーローにも使える。自分の最大 HP の \(pct(k.bloodyHealPct)) を回復",
                     "Hunting spell can hit heroes and heals you for \(pct(k.bloodyHealPct)) of max HP")
        case .conceal:
            return L("戦闘外で敵ヒーローが \(Int(k.concealRange)) 以内に来ると自動で \(Int(k.concealDuration)) 秒隠れて加速（CD \(Int(k.concealCooldown)) 秒）",
                     "Out of combat, when an enemy hero comes within \(Int(k.concealRange)), you hide and speed up for \(Int(k.concealDuration))s (\(Int(k.concealCooldown))s CD)")
        case .encourage:
            return L("周囲 \(Int(k.encourageRadius)) の味方（自分を含む）の攻撃速度 +\(pct(k.encourageAttackSpeed))・与ダメージ +\(pct(k.encourageDamage))",
                     "Allies within \(Int(k.encourageRadius)) (you included) gain +\(pct(k.encourageAttackSpeed)) attack speed and +\(pct(k.encourageDamage)) damage")
        case .favor:
            return L("HP \(pct(k.favorTriggerRatio)) 未満の味方を自動で回復（\(Int(k.favorBase)) + \(Int(k.favorPerLevel))×Lv、CD \(Int(k.favorCooldown)) 秒）",
                     "Auto-heals an ally under \(pct(k.favorTriggerRatio)) HP (\(Int(k.favorBase)) + \(Int(k.favorPerLevel))×Lv, \(Int(k.favorCooldown))s CD)")
        case .direHit:
            return L("HP \(pct(k.direHitTriggerRatio)) 未満の敵ヒーローに最大 HP の \(pct(k.direHitMinPct))〜\(pct(k.direHitMaxPct)) の魔法ダメージ（Lv で増加、CD \(Int(k.direHitCooldown)) 秒）",
                     "Magic damage of \(pct(k.direHitMinPct))–\(pct(k.direHitMaxPct)) max HP (scales with level) to an enemy hero under \(pct(k.direHitTriggerRatio)) HP (\(Int(k.direHitCooldown))s CD)")
        }
    }

    /// 時間・進行で変わる靴の効果（購入前に読めるルール文）。
    static func rules(_ category: ItemCategory) -> [String] {
        let k = Balance.Gear.self
        switch category {
        case .jungle:
            return [
                L("\(clock(k.jungleMinionPenaltyEnd)) まで、自分のミニオンの Gold/XP が \(pct(1 - k.jungleMinionMultiplier)) 減る",
                  "Until \(clock(k.jungleMinionPenaltyEnd)), your minion Gold/XP is reduced by \(pct(1 - k.jungleMinionMultiplier))"),
                L("モンスターへのダメージとモンスター Gold が増える",
                  "More damage to monsters and more monster Gold"),
                L("狩り・キル・アシストが合計 \(k.jungleBlessingUnlockCount) 回で祝福が解放（モンスターへのダメージ +\(pct(k.jungleBlessingMonsterDamage))）",
                  "After \(k.jungleBlessingUnlockCount) camps, kills or assists a blessing unlocks (+\(pct(k.jungleBlessingMonsterDamage)) damage to monsters)"),
            ]
        case .roam:
            return [
                L("\(Int(k.thrivingInterval)) 秒ごとに共有収入 \(Int(k.thrivingGoldEarly)) Gold・\(Int(k.thrivingXPEarly)) XP。\(clock(k.roamPhaseEnd)) から \(Int(k.thrivingGoldLate)) Gold・\(Int(k.thrivingXPLate)) XP（累計上限 \(Int(k.roamGoldCap)) Gold）",
                  "Shared income every \(Int(k.thrivingInterval))s: \(Int(k.thrivingGoldEarly)) Gold / \(Int(k.thrivingXPEarly)) XP, rising to \(Int(k.thrivingGoldLate)) / \(Int(k.thrivingXPLate)) from \(clock(k.roamPhaseEnd)) (\(Int(k.roamGoldCap)) Gold cap)"),
                L("\(clock(k.roamPhaseEnd)) まで、自分のミニオン・モンスターの Gold/XP が \(pct(1 - k.roamFarmMultiplier)) 減る",
                  "Until \(clock(k.roamPhaseEnd)), your minion and monster Gold/XP is reduced by \(pct(1 - k.roamFarmMultiplier))"),
                L("アシストで +\(Int(k.assistBonusGold)) Gold・+\(Int(k.assistBonusXP)) XP",
                  "Assists give +\(Int(k.assistBonusGold)) Gold and +\(Int(k.assistBonusXP)) XP"),
                L("共有収入の累計が \(k.blessingThresholds.map { String(Int($0)) }.joined(separator: " / ")) に達するたび祝福が強くなる",
                  "The blessing grows stronger at \(k.blessingThresholds.map { String(Int($0)) }.joined(separator: " / ")) shared Gold"),
                L("狩猟印を装備していると買えない", "Can't be bought with the hunting spell"),
            ]
        default:
            return []
        }
    }
}
