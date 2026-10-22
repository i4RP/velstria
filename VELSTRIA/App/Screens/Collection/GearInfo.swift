import Foundation
import VelstriaCore

// 担当: collection / battle-hud。靴に付ける祝福（ジャングル・ローム。GearOption）の名前・効果・ルールの説明文。
// 祝福は装備ではなく、持っている 1 足の靴に付く（0 Gold・装備枠を使わない）。効果の仕様は Systems/GearSystem.swift の冒頭。
// 数値は Balance.Gear から作るので、バランス調整で説明がずれない。

enum GearInfo {
    private static func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
    /// 67.5 → "67.5"、40 → "40"。
    private static func num(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
    private static func clock(_ seconds: Double) -> String {
        let s = Int(seconds)
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
    private static var smite: String { BuildRules.smiteName(master: MasterData.shared) }

    /// ジャングル・ロームのタブ（装備は並ばず、祝福を並べる）か。
    static func isBlessingCategory(_ c: ItemCategory) -> Bool {
        c == .jungle || c == .roam
    }

    static func name(_ o: GearOption) -> String {
        switch o {
        case .flame: return L("炎撃の狩猟", "Flame Hunt")
        case .ice: return L("氷刺の狩猟", "Ice Hunt")
        case .bloody: return L("血刃の狩猟", "Blood Hunt")
        case .conceal: return L("隠蔽", "Conceal")
        case .encourage: return L("激励", "Encourage")
        case .favor: return L("恩恵", "Favor")
        case .direHit: return L("致命傷", "Dire Hit")
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

    /// 一覧のカードに出す短い効果。
    static func short(_ o: GearOption) -> String {
        let k = Balance.Gear.self
        switch o {
        case .flame: return L("\(smite)で物理・魔法攻撃を奪う", "\(smite) steals physical & magic attack")
        case .ice: return L("\(smite)で移動速度を奪う", "\(smite) steals movement speed")
        case .bloody: return L("\(smite)で HP を奪う", "\(smite) drains HP")
        case .conceal: return L("味方と隠れて加速（アクティブ）", "Hide with allies and speed up (active)")
        case .encourage:
            return L("周りの味方の物理・魔法防御 +\(num(k.encourageDefense))", "Nearby allies +\(num(k.encourageDefense)) hybrid defense")
        case .favor: return L("味方を回復すると HP の低い味方も回復", "Healing an ally also heals the weakest ally")
        case .direHit: return L("移動でフォースを溜め、確定ダメージ", "Build Force by moving for true damage")
        }
    }

    /// 祝福そのものの効果（ジャングルは強化した狩猟印、ロームは共栄ゴールドの解放で働く）。
    static func summary(_ o: GearOption) -> String {
        let k = Balance.Gear.self
        let d = num(k.smiteHeroEffectDuration)
        let onHero = L("強化した\(smite)を敵ヒーローに使うと \(num(k.smiteHeroDamage)) の確定ダメージを与え、",
                       "Empowered \(smite) on an enemy hero deals \(num(k.smiteHeroDamage)) true damage and ")
        switch o {
        case .flame:
            return onHero + L("物理攻撃・魔法攻撃を \(num(k.flameStealBase)) + \(num(k.flameStealPerLevel))×レベル 奪う（\(d) 秒）",
                              "steals \(num(k.flameStealBase)) + \(num(k.flameStealPerLevel)) × level physical & magic attack for \(d)s")
        case .ice:
            return onHero + L("移動速度を \(num(k.iceStealBase)) + \(num(k.iceStealPerLevel))×レベル 奪う（\(d) 秒）",
                              "steals \(num(k.iceStealBase)) + \(num(k.iceStealPerLevel)) × level movement speed for \(d)s")
        case .bloody:
            return onHero + L("\(num(k.bloodyStealBase)) + 自分の追加 HP の \(pct(k.bloodyStealExtraHPRatio)) を \(d) 秒かけて奪う",
                              "drains \(num(k.bloodyStealBase)) + \(pct(k.bloodyStealExtraHPRatio)) of your extra HP over \(d)s")
        case .conceal:
            return L("アクティブ（CD \(num(k.concealCooldown)) 秒）: 自分と周り \(num(k.concealRadius)) の味方を \(num(k.concealDuration)) 秒間 隠れさせ、移動速度 +\(pct(k.concealSpeed))。ダメージを与える・受けると解除",
                     "Active (\(num(k.concealCooldown))s CD): you and allies within \(num(k.concealRadius)) are concealed for \(num(k.concealDuration))s with +\(pct(k.concealSpeed)) movement speed. Dealing or taking damage reveals you")
        case .encourage:
            return L("自分と周り \(num(k.encourageRadius)) の味方ヒーローの物理防御・魔法防御 +\(num(k.encourageDefense))",
                     "You and allied heroes within \(num(k.encourageRadius)) gain +\(num(k.encourageDefense)) physical and magic defense")
        case .favor:
            return L("自分の回復・シールドのスキルで味方を回復・シールドすると、周り \(num(k.favorRadius)) で HP が最も少ない味方ヒーロー 1 体（自分を含む）の HP を \(num(k.favorHeal)) 回復（\(num(k.favorCooldown)) 秒に 1 回）",
                     "Healing or shielding another ally with your skill also restores \(num(k.favorHeal)) HP to the allied hero with the least HP within \(num(k.favorRadius)), you included (once per \(num(k.favorCooldown))s)")
        case .direHit:
            return L("移動 \(num(k.direHitDistancePerStack)) ごとにフォース 1（最大 \(num(k.direHitMaxStacks))。フォース 1 につき移動速度 +\(num(k.direHitSpeedPerStack))）。フォースが \(num(k.direHitMinStacks)) 以上なら、次に敵ヒーローに当てたスキルか通常攻撃でフォースをすべて使い、フォース × \(num(k.direHitDamagePerStack)) の確定ダメージ",
                     "Gain 1 Force per \(num(k.direHitDistancePerStack)) units moved (max \(num(k.direHitMaxStacks)); +\(num(k.direHitSpeedPerStack)) movement speed per Force). At \(num(k.direHitMinStacks))+ Force, your next skill or basic attack on an enemy hero spends it all for Force × \(num(k.direHitDamagePerStack)) true damage")
        }
    }

    /// 祝福に共通の決まり（付け方・外れ方）。
    static var commonRules: [String] {
        [
            L("祝福は 0 Gold。持っている靴に付き、装備枠を使わない。付け替えもできる",
              "Blessings cost 0 Gold, attach to your boots and take no slot. You can swap them"),
            L("靴が無ければ\(MasterData.shared.item(Balance.Gear.baseBootsID).map { MasterText.item($0) } ?? "")（\(Int(MasterData.shared.item(Balance.Gear.baseBootsID)?.priceGold ?? 0))）を一緒に買う。靴を売ると外れる",
              "Without boots, \(MasterData.shared.item(Balance.Gear.baseBootsID).map { MasterText.item($0) } ?? "boots") (\(Int(MasterData.shared.item(Balance.Gear.baseBootsID)?.priceGold ?? 0))) are bought with it. Selling your boots removes it"),
        ]
    }

    /// ジャングル・ロームの祝福のルール（種類ごとに共通）。
    static func rules(_ category: ItemCategory) -> [String] {
        let k = Balance.Gear.self
        switch category {
        case .jungle:
            return [
                L("「\(smite)」が必要（持っていると靴は必ずジャングルの祝福になる）",
                  "Requires \(smite) (with it, your boots always carry a jungle blessing)"),
                L("\(smite)を持つと、モンスターの報酬 +\(pct(k.jungleMonsterMultiplier - 1))・モンスター（星喰竜・古環の巨像を除く）から受けるダメージ −\(pct(1 - Balance.Spells.smiteMonsterDamageTaken))。\(clock(k.jungleMinionShareEnd)) までは味方とミニオンの報酬を分け合わない",
                  "With \(smite): monster rewards +\(pct(k.jungleMonsterMultiplier - 1)), damage taken from monsters (except the Astral Wyrm and the Ancient Colossus) −\(pct(1 - Balance.Spells.smiteMonsterDamageTaken)). Until \(clock(k.jungleMinionShareEnd)) you don't share minion rewards with allies"),
                L("狩人: モンスターにダメージを与えると \(num(k.hunterDuration)) 秒かけて \(num(k.hunterBase)) + \(num(k.hunterPerLevel))×レベル + 最大 HP の \(pct(k.hunterMaxHPRatio)) の確定ダメージ（射手以外は \(num(k.hunterNonMarksmanMultiplier)) 倍）",
                  "Hunter: damaging a monster deals \(num(k.hunterBase)) + \(num(k.hunterPerLevel)) × level + \(pct(k.hunterMaxHPRatio)) of your max HP true damage over \(num(k.hunterDuration))s (×\(num(k.hunterNonMarksmanMultiplier)) for non-marksmen)"),
                L("\(clock(Balance.Jungle.earlyJungleRuleEnd)) までは、自陣のジャングルで倒れたモンスターの Gold・EXP は近くの\(smite)を持つ味方に入り、バフは直前に攻撃した\(smite)を持つ味方に付く。敵のジャングルでは受けるダメージ +\(pct(Balance.Jungle.invaderDamageTaken - 1))",
                  "Until \(clock(Balance.Jungle.earlyJungleRuleEnd)), Gold and EXP from monsters slain in your own jungle go to a nearby ally with \(smite), and buffs go to the one who just hit it. Heroes in the enemy jungle take +\(pct(Balance.Jungle.invaderDamageTaken - 1)) damage"),
                L("モンスター・キル・アシストの合計 \(k.jungleBlessingUnlockCount) で\(smite)を敵ヒーローにも使える（祝福の効果が付く）",
                  "After \(k.jungleBlessingUnlockCount) monsters, kills or assists in total, \(smite) can hit enemy heroes (with the blessing's effect)"),
                L("合計 \(k.jungleSecondUnlockCount) で物理攻撃・魔法攻撃 +\(num(k.jungleSecondAttack))、最大 HP +\(num(k.jungleSecondHP))",
                  "At \(k.jungleSecondUnlockCount), +\(num(k.jungleSecondAttack)) physical & magic attack and +\(num(k.jungleSecondHP)) max HP"),
            ]
        case .roam:
            return [
                L("「\(smite)」を持っていると付けられない。\(clock(k.roamPurchaseDeadline)) を過ぎると新たには付けられない",
                  "Not available with \(smite), and can't be newly taken after \(clock(k.roamPurchaseDeadline))"),
                L("\(clock(k.roamPhaseEnd)) までは、周り \(num(k.devotionRadius)) に味方ヒーローが居ない時に倒したミニオン・モンスターの Gold・XP が \(pct(k.roamOwnRewardMultiplier))",
                  "Until \(clock(k.roamPhaseEnd)), Gold and XP from minions and monsters you slay with no allied hero within \(num(k.devotionRadius)) are \(pct(k.roamOwnRewardMultiplier))"),
                L("共栄: \(num(k.thrivingInterval)) 秒ごとに \(num(k.thrivingGoldEarly)) Gold・\(num(k.thrivingXPEarly)) XP（\(clock(k.roamPhaseEnd)) から \(num(k.thrivingGoldLate)) Gold・\(num(k.thrivingXPLate)) XP）",
                  "Thriving: \(num(k.thrivingGoldEarly)) Gold and \(num(k.thrivingXPEarly)) XP every \(num(k.thrivingInterval))s (\(num(k.thrivingGoldLate)) Gold and \(num(k.thrivingXPLate)) XP from \(clock(k.roamPhaseEnd)))"),
                L("無私: 周り \(num(k.devotionRadius)) の味方がミニオン・モンスターから得た Gold・XP の \(pct(k.devotionShare)) を自分も得る（Gold は累計 \(num(k.devotionGoldCap)) まで）",
                  "Devotion: earn \(pct(k.devotionShare)) of the Gold and XP nearby allies (within \(num(k.devotionRadius))) get from minions and monsters (up to \(num(k.devotionGoldCap)) Gold in total)"),
                L("敵ヒーローにダメージを与えると \(num(k.devotionHitGoldBase)) + \(num(k.devotionHitGoldPerLevel))×レベル Gold・\(num(k.devotionHitXPBase)) + \(num(k.devotionHitXPPerLevel))×レベル XP（\(num(k.devotionHitCooldown)) 秒に 1 回）",
                  "Damaging an enemy hero grants \(num(k.devotionHitGoldBase)) + \(num(k.devotionHitGoldPerLevel)) × level Gold and \(num(k.devotionHitXPBase)) + \(num(k.devotionHitXPPerLevel)) × level XP (once per \(num(k.devotionHitCooldown))s)"),
                L("味方の視界から \(num(k.revealHiddenTime)) 秒以上消えていた敵ヒーローを、視界かスキルで最初に暴くと \(num(k.revealGoldBase)) + \(num(k.revealGoldPerLevel))×レベル Gold・\(num(k.revealXPBase)) + \(num(k.revealXPPerLevel))×レベル XP（無私の上限に数える）",
                  "Revealing an enemy hero that was out of your team's sight for \(num(k.revealHiddenTime))s+ (by vision or a skill) grants \(num(k.revealGoldBase)) + \(num(k.revealGoldPerLevel)) × level Gold and \(num(k.revealXPBase)) + \(num(k.revealXPPerLevel)) × level XP (counts toward the Devotion cap)"),
                L("ロームの祝福を持つ味方が複数いれば、所持 Gold の最も少ない 1 人だけが収入を得る",
                  "If several allies have a roam blessing, only the one with the least Gold earns"),
                L("共栄・無私で得た Gold（共栄ゴールド）が \(num(k.blessingUnlockGold)) に達すると祝福の効果が解放される",
                  "The blessing's effect unlocks once Thriving and Devotion have earned \(num(k.blessingUnlockGold)) Gold (shared gold)"),
            ]
        default:
            return []
        }
    }

    /// 詳細に並べる文（祝福の効果 → 種類のルール → 共通の決まり）。
    static func details(_ o: GearOption) -> [String] {
        [summary(o)] + rules(o.category) + commonRules
    }

    // MARK: 進み具合

    /// ジャングル: モンスター + キル + アシストの合計（狩猟印の強化 5・2 段目 15）。
    static func jungleProgressText(_ count: Int) -> String {
        let k = Balance.Gear.self
        if count < k.jungleBlessingUnlockCount {
            return L("狩りとキル \(count) / \(k.jungleBlessingUnlockCount)", "Hunts & takedowns \(count) / \(k.jungleBlessingUnlockCount)")
        }
        if count < k.jungleSecondUnlockCount {
            return L("狩猟印を強化済み・次の強化 \(count) / \(k.jungleSecondUnlockCount)",
                     "Retribution empowered · next \(count) / \(k.jungleSecondUnlockCount)")
        }
        return L("強化をすべて解放（狩りとキル \(count)）", "Fully empowered (\(count) hunts & takedowns)")
    }

    /// ローム: 共栄ゴールド（1000 で祝福の効果を解放）。
    static func roamProgressText(_ gold: Int) -> String {
        let need = Int(Balance.Gear.blessingUnlockGold)
        if gold < need { return L("共栄ゴールド \(gold) / \(need)", "Shared gold \(gold) / \(need)") }
        return L("祝福の効果を解放済み（共栄ゴールド \(gold)）", "Blessing unlocked (shared gold \(gold))")
    }
}
