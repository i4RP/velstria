import Foundation
import VelstriaCore

// 担当: ui-collection。画面表示用の純粋な計算（DESIGN.md の式をそのまま表示に使う。AppTests で検証）。

// MARK: - スキル（DESIGN §5・§6）

enum SkillMath {
    /// ランク 1...最大ランク。
    static func ranks(for slot: SkillSlot) -> [Int] {
        slot == .passive ? [] : Array(1...slot.maxRank)
    }

    /// 基礎ダメージ（ランク補正込み）= base × (1 + 0.30 × (rank − 1))。
    static func damage(base: Double, rank: Int) -> Double {
        base * (1 + Balance.skillDamagePerRank * Double(max(0, rank - 1)))
    }

    /// 実戦の数値（シミュレーションと同じ `SkillCatalog.numbers`）。能力値ボーナス（攻撃力・魔力）を含めない値
    /// ＝ 表示上の「基礎値」。スロット別の調整倍率（Balance.Skills.damageScaleBySlot）と
    /// アーキタイプ補正（強化攻撃 50%・連続斬り 45%×3・回復倍率・味方全体回復のダメージなし など）は込み。
    static func numbers(_ skill: SkillDef, hero: HeroDef, rank: Int) -> SkillNumbers {
        SkillCatalog.numbers(for: skill, hero: hero, rank: rank, stats: Stats())
    }

    /// 攻撃力・魔力 1 あたりの増分（実効係数）。ダメージは 1 ヒットあたり、回復は味方 1 体あたり。
    struct Scaling: Equatable {
        var attack: Double
        var power: Double
        var isEmpty: Bool { attack <= 1e-9 && power <= 1e-9 }
    }

    /// ダメージ・回復の能力値係数。シミュレーションの式を差分で取り出す（式を二重に持たない）。
    static func scaling(_ skill: SkillDef, hero: HeroDef) -> (damage: Scaling, heal: Scaling) {
        let probe = 100.0
        let base = numbers(skill, hero: hero, rank: 1)
        var atk = Stats()
        atk.attack = probe
        var pow = Stats()
        pow.abilityPower = probe
        let a = SkillCatalog.numbers(for: skill, hero: hero, rank: 1, stats: atk)
        let p = SkillCatalog.numbers(for: skill, hero: hero, rank: 1, stats: pow)
        return (Scaling(attack: (a.damage - base.damage) / probe, power: (p.damage - base.damage) / probe),
                Scaling(attack: (a.heal - base.heal) / probe, power: (p.heal - base.heal) / probe))
    }

    /// ランク表に出す数値の種類（アーキタイプで決まる）。
    enum Figure: Equatable {
        /// 1 ヒットのダメージ（連続斬りは「回数×1 撃」）。
        case damage
        /// ブリンク後の強化通常攻撃の追加ダメージ。
        case bonusDamage
        /// 味方 1 体あたりの回復量。
        case heal
        /// 味方 1 体あたりのシールド量。
        case shield
    }

    static func figures(_ archetype: SkillArchetype) -> [Figure] {
        switch archetype {
        case .passive: return []
        case .blinkEmpower: return [.bonusDamage]
        case .healZone: return [.damage, .heal]
        case .teamHeal: return [.heal, .shield]
        case .cone, .lineSkillshot, .piercingLine, .dashStrike, .groundAoE, .selfAoE, .leapSlam, .multiStrike,
             .targetedBlink:
            return [.damage]
        }
    }

    static func figureTitle(_ f: Figure) -> String {
        switch f {
        case .damage: return L("ダメージ", "Damage")
        case .bonusDamage: return L("追加ダメージ", "Bonus Dmg")
        case .heal: return L("回復", "Heal")
        case .shield: return L("シールド", "Shield")
        }
    }

    static func figureValue(_ f: Figure, _ n: SkillNumbers) -> String {
        let num = { (v: Double) in CollectionStyle.number(v, digits: 0) }
        switch f {
        case .damage: return n.hits > 1 ? "\(n.hits)×\(num(n.damage))" : num(n.damage)
        case .bonusDamage: return num(n.damage)
        case .heal: return num(n.heal)
        case .shield: return num(n.shield)
        }
    }

    /// CD（CD 短縮なし）= cooldown × (1 − 0.06 × (rank − 1)) × 調整倍率。
    static func cooldown(_ skill: SkillDef, rank: Int) -> Double {
        SkillSystem.cooldown(for: skill, rank: rank, cdr: 0)
    }

    /// 実効コスト（Energy は ×0.6）。
    static func cost(_ skill: SkillDef, resource: ResourceKind) -> Double {
        SkillSystem.cost(for: skill, resource: resource)
    }

    /// スキルの説明文（ランク 1・能力値ボーナスなしの実戦値から生成。マスターの説明文は汎用の仮文のため使わない）。
    /// パッシブは `passiveText`。
    static func description(_ skill: SkillDef, hero: HeroDef) -> String {
        guard skill.slot != .passive else { return passiveText(role: hero.role, heroNumber: hero.number) }
        let k = Balance.Skills.self
        let t = SkillCatalog.targeting(for: skill, hero: hero)
        let n = numbers(skill, hero: hero, rank: 1)
        let num = { (v: Double) in CollectionStyle.number(v, digits: 0) }
        let sec = { (v: Double) in CollectionStyle.number(v, digits: 2) }
        let pct = { (v: Double) in CollectionStyle.number(v * 100, digits: 1) }
        let d = num(n.damage)
        let range = num(t.range)
        let typeJa = CollectionStyle.damageTypeName(skill.damageType)
        let typeEn = CollectionStyle.damageTypeName(skill.damageType).lowercased()
        let cc = skill.cc
        let name = hero.codeName

        // 日本語の CC 句（「<対象>を〜する」。対象を省くと「〜する」）
        func ccJa(_ who: String?) -> String {
            switch cc {
            case .none: return ""
            case .slow: return who.map { "\($0)の移動速度を低下させる" } ?? "移動速度を低下させる"
            case .root: return (who.map { "\($0)を" } ?? "") + "移動不能にする"
            case .stun: return (who.map { "\($0)を" } ?? "") + "スタンさせる"
            case .knockback: return (who.map { "\($0)を" } ?? "") + "ノックバックさせる"
            }
        }
        // 「<対象>に基礎 N の<種別>ダメージを与え(、CC)。」
        func hitJa(_ subject: String, _ amount: String) -> String {
            cc == .none ? "\(subject)に基礎 \(amount) の\(typeJa)ダメージを与える。"
                : "\(subject)に基礎 \(amount) の\(typeJa)ダメージを与え、" + ccJa(nil) + "。"
        }
        // 英語の CC 句（複数の敵が主語 / 単体が主語 / 通常攻撃が主語 / 状態）
        let ccPlural: String
        let ccSingle: String
        let ccVerb: String
        let ccState: String
        switch cc {
        case .none: ccPlural = ""; ccSingle = ""; ccVerb = ""; ccState = ""
        case .slow: ccPlural = " and are slowed"; ccSingle = " and is slowed"; ccVerb = " and slows the target"; ccState = "slowed"
        case .root: ccPlural = " and are rooted"; ccSingle = " and is rooted"; ccVerb = " and roots the target"; ccState = "rooted"
        case .stun: ccPlural = " and are stunned"; ccSingle = " and is stunned"; ccVerb = " and stuns the target"; ccState = "stunned"
        case .knockback:
            ccPlural = " and are knocked back"; ccSingle = " and is knocked back"
            ccVerb = " and knocks the target back"; ccState = "knocked back"
        }

        switch t.archetype {
        case .passive:
            return passiveText(role: hero.role, heroNumber: hero.number)
        case .cone:
            let deg = num(k.coneHalfAngle * 2 * 180 / .pi)
            return L("前方 \(deg)° の扇形を斬りつけ、" + hitJa("命中した敵", d),
                     "Slashes in a \(deg)° cone ahead. Enemies hit take \(d) base \(typeEn) damage\(ccPlural).")
        case .lineSkillshot:
            return L("指定方向へスキルショットを放ち、" + hitJa("最初に命中した敵", d),
                     "Fires a skillshot in the target direction. The first enemy hit takes \(d) base \(typeEn) damage\(ccSingle).")
        case .dashStrike:
            return L("指定方向へ \(range) 突進し、" + hitJa("着地点周辺の敵", d),
                     "Dashes \(range) units in the target direction. Enemies near the landing point take \(d) base \(typeEn) damage\(ccPlural).")
        case .blinkEmpower:
            let jaCC = cc == .none ? "与える。" : "与え、" + ccJa(nil) + "。"
            return L("指定方向へ \(range) ブリンクする。\(sec(k.empowerDuration)) 秒以内の次の通常攻撃は基礎 \(d) の\(typeJa)ダメージを追加で\(jaCC)",
                     "Blinks \(range) units in the target direction. The next basic attack within \(sec(k.empowerDuration))s deals \(d) bonus base \(typeEn) damage\(ccVerb).")
        case .groundAoE where skill.slot == .ultimate:
            return L("\(sec(n.delay)) 秒の予告後、指定地点の広範囲を攻撃し、" + hitJa("範囲内の敵", d),
                     "After a \(sec(n.delay))s warning, devastates a large area at the target location. Enemies inside take \(d) base \(typeEn) damage\(ccPlural).")
        case .groundAoE:
            return L("\(sec(n.delay)) 秒の予告後、指定地点で炸裂し、" + hitJa("範囲内の敵", d),
                     "After a \(sec(n.delay))s warning, erupts at the target location. Enemies in the area take \(d) base \(typeEn) damage\(ccPlural).")
        case .selfAoE:
            return L("自身の周囲に衝撃波を放ち、" + hitJa("周囲の敵", d)
                        + "自身は最大 HP の \(pct(k.selfShieldMaxHPRatio))% のシールドを得る（\(sec(n.shieldDuration)) 秒）。",
                     "Releases a shockwave around \(name). Nearby enemies take \(d) base \(typeEn) damage\(ccPlural), and \(name) gains a shield equal to \(pct(k.selfShieldMaxHPRatio))% of max HP for \(sec(n.shieldDuration))s.")
        case .healZone:
            return L("\(sec(n.delay)) 秒後、指定地点に癒しの陣を展開する。範囲内の味方の HP を \(num(n.heal)) 回復し、" + hitJa("敵", d),
                     "After \(sec(n.delay))s, creates a restorative field at the target location. Allies inside recover \(num(n.heal)) HP, while enemies take \(d) base \(typeEn) damage\(ccPlural).")
        case .leapSlam:
            return L("指定地点へ最大 \(range) 跳躍し、" + hitJa("着地点の広範囲の敵", d),
                     "Leaps up to \(range) units to the target location. On landing, enemies in a wide area take \(d) base \(typeEn) damage\(ccPlural).")
        case .multiStrike:
            let reduction = pct(n.damageReduction)
            let jaCC = cc == .none ? "" : "初撃で" + ccJa("対象") + "。"
            let enCC = cc == .none ? "" : " The first hit leaves targets \(ccState)."
            return L("範囲内の敵ヒーローを \(n.hits) 回攻撃し、1 撃ごとに基礎 \(d) の\(typeJa)ダメージを与える。\(jaCC)自身は \(sec(n.damageReductionDuration)) 秒間 被ダメージ −\(reduction)%。",
                     "Strikes every enemy hero in range \(n.hits) times, each hit dealing \(d) base \(typeEn) damage.\(enCC) \(name) takes \(reduction)% less damage for \(sec(n.damageReductionDuration)) seconds.")
        case .piercingLine:
            return L("長さ \(range) の貫通する大矢を放ち、" + hitJa("直線上の全ての敵", d),
                     "Fires a massive piercing arrow \(range) units long. All enemies in its path take \(d) base \(typeEn) damage\(ccPlural).")
        case .teamHeal:
            let jaCC = cc == .none ? "" : ccJa("周囲の敵") + "。"
            let enCC = cc == .none ? "" : " Nearby enemies are \(ccState)."
            return L("\(range) 以内の味方ヒーロー全員の HP を \(num(n.heal)) 回復し、\(num(n.shield)) のシールドを付与する（\(sec(n.shieldDuration)) 秒）。\(jaCC)",
                     "Heals all allied heroes within \(range) units for \(num(n.heal)) HP and grants each a \(num(n.shield)) shield for \(sec(n.shieldDuration))s.\(enCC)")
        case .targetedBlink:
            let missing = pct(n.missingHealthRatio)
            let enCC = cc == .none ? "" : " The target is \(ccState)."
            return L("\(range) 以内の敵ヒーローの背後へ瞬間移動し、" + hitJa("対象", "\(d) + 失った HP の \(missing)%"),
                     "Blinks behind an enemy hero within \(range) units and strikes for \(d) base \(typeEn) damage plus \(missing)% of the target's missing HP.\(enCC)")
        }
    }

    /// CC の効果量と時間（Ult は強化版）。
    static func ccDetail(_ cc: CrowdControl, isUltimate: Bool) -> String {
        let s = CollectionStyle.seconds
        switch cc {
        case .none:
            return L("なし", "None")
        case .slow:
            let pct = (isUltimate ? Balance.ultSlowPct : Balance.slowPct) * 100
            let dur = isUltimate ? Balance.ultSlowDuration : Balance.slowDuration
            return L("移動速度 −\(CollectionStyle.percent(pct)) / \(s(dur))",
                     "−\(CollectionStyle.percent(pct)) move speed for \(s(dur))")
        case .root:
            let dur = isUltimate ? Balance.ultRootDuration : Balance.rootDuration
            return L("移動不可 \(s(dur))", "Rooted for \(s(dur))")
        case .stun:
            let dur = isUltimate ? Balance.ultStunDuration : Balance.stunDuration
            return L("行動不能 \(s(dur))", "Stunned for \(s(dur))")
        case .knockback:
            let dist = CollectionStyle.number(Balance.knockbackDistance, digits: 0)
            return L("\(dist) 押し出し + スタン \(s(Balance.knockbackStun))",
                     "Pushed \(dist) units + \(s(Balance.knockbackStun)) stun")
        }
    }

    /// ヒーロー固有のパッシブ係数 k = 1.0 + 0.02 × (番号 mod 5)。
    static func passiveCoefficient(heroNumber: Int) -> Double {
        1.0 + 0.02 * Double(heroNumber % 5)
    }

    /// ロール別パッシブの効果文（DESIGN §6）。
    static func passiveText(role: Role, heroNumber: Int) -> String {
        let k = passiveCoefficient(heroNumber: heroNumber)
        let n = { (v: Double) in CollectionStyle.number(v, digits: 2) }
        switch role {
        case .vanguard:
            return L("HP が 40% 未満になると最大 HP の \(n(15 * k))% のシールドを得る（CD 20 秒）。",
                     "Below 40% HP, gain a shield equal to \(n(15 * k))% max HP (20s cooldown).")
        case .duelist:
            return L("通常攻撃が命中する毎に攻撃速度 +\(n(6 * k))%（最大 5 スタック、3 秒持続）。",
                     "Each basic attack hit grants +\(n(6 * k))% attack speed (up to 5 stacks, 3s).")
        case .ranger:
            return L("4 発毎の通常攻撃が必ずクリティカルになり、\(n(1.75 * k)) 倍のダメージを与える。",
                     "Every 4th basic attack is a guaranteed critical dealing \(n(1.75 * k))× damage.")
        case .arcanist:
            return L("スキル命中時、他のスキルの CD を \(n(0.6 * k)) 秒短縮する（1 キャストにつき 1 回）。",
                     "Skill hits reduce your other cooldowns by \(n(0.6 * k))s (once per cast).")
        case .support:
            return L("スキル使用時、800 以内で HP 割合が最も低い味方を 40 + \(n(10 * k))×Lv 回復する。",
                     "Casting a skill heals the lowest-HP ally within 800 for 40 + \(n(10 * k))×Lv.")
        case .assassin:
            return L("草むら/ステルス解除後 3 秒以内の最初のダメージ +\(n(30 * k))%。キル/アシストで全スキルの CD −30%。",
                     "First damage within 3s of leaving brush/stealth deals +\(n(30 * k))%. Takedowns cut all cooldowns by 30%.")
        }
    }
}

// MARK: - 能力値（DESIGN §4）

enum HeroStatKind: CaseIterable, Identifiable {
    case hp, attack, defense, magicDefense, attackSpeed, moveSpeed, range
    var id: Self { self }

    var label: String {
        switch self {
        case .hp: return L("最大HP", "Max HP")
        case .attack: return L("攻撃力", "Attack")
        case .defense: return L("防御", "Armor")
        case .magicDefense: return L("魔防", "Magic Res.")
        case .attackSpeed: return L("攻撃速度", "Atk Speed")
        case .moveSpeed: return L("移動速度", "Move Speed")
        case .range: return L("射程", "Range")
        }
    }

    var symbol: String {
        switch self {
        case .hp: return "heart.fill"
        case .attack: return "bolt.fill"
        case .defense: return "shield.fill"
        case .magicDefense: return "sparkles"
        case .attackSpeed: return "timer"
        case .moveSpeed: return "hare.fill"
        case .range: return "scope"
        }
    }

    func value(_ st: Stats) -> Double {
        switch self {
        case .hp: return st.maxHP
        case .attack: return st.attack
        case .defense: return st.armor
        case .magicDefense: return st.magicResist
        case .attackSpeed: return st.attackSpeed
        case .moveSpeed: return st.moveSpeed
        case .range: return st.attackRange
        }
    }

    /// レベル毎の成長量（表示用）。成長しない項目は nil。
    func growth(_ def: HeroDef) -> Double? {
        switch self {
        case .hp: return def.hpGrowth
        case .attack: return def.attackGrowth
        case .defense: return def.defenseGrowth
        case .magicDefense: return def.magicDefenseGrowth
        case .attackSpeed:
            let base = def.isRanged ? Balance.rangedAttackSpeed : Balance.meleeAttackSpeed
            return base * Balance.attackSpeedPerLevel
        case .moveSpeed, .range: return nil
        }
    }

    var digits: Int { self == .attackSpeed ? 2 : 0 }
}

enum HeroStatMath {
    /// 全ヒーロー Lv 最大時の最大値（バーの正規化用）。
    static func maxValue(_ kind: HeroStatKind, master: MasterData) -> Double {
        let values = master.heroes.map { kind.value(HeroGrowth.baseStats(def: $0, level: Balance.maxLevel)) }
        return max(values.max() ?? 1, 1e-6)
    }
}

// MARK: - 装備（DESIGN §8）

struct ItemStatLine: Identifiable, Equatable {
    var id: String { label }
    var label: String
    var value: String
    var symbol: String
}

enum ItemMath {
    /// 非ゼロの能力値。
    static func statLines(_ item: ItemDef) -> [ItemStatLine] {
        var lines: [ItemStatLine] = []
        let n = { (v: Double) in CollectionStyle.number(v, digits: 1) }
        if item.attack != 0 { lines.append(.init(label: L("攻撃力", "Attack"), value: "+\(n(item.attack))", symbol: "bolt.fill")) }
        if item.abilityPower != 0 { lines.append(.init(label: L("魔力", "Power"), value: "+\(n(item.abilityPower))", symbol: "sparkles")) }
        if item.hp != 0 { lines.append(.init(label: L("最大HP", "Max HP"), value: "+\(n(item.hp))", symbol: "heart.fill")) }
        if item.armor != 0 { lines.append(.init(label: L("防御", "Armor"), value: "+\(n(item.armor))", symbol: "shield.fill")) }
        if item.magicResist != 0 { lines.append(.init(label: L("魔防", "Magic Res."), value: "+\(n(item.magicResist))", symbol: "shield.lefthalf.filled")) }
        if item.moveSpeed != 0 { lines.append(.init(label: L("移動速度", "Move Speed"), value: "+\(n(item.moveSpeed))", symbol: "hare.fill")) }
        if item.cooldownReductionPct != 0 {
            lines.append(.init(label: L("CD短縮", "Cooldown Red."), value: "+\(CollectionStyle.percent(item.cooldownReductionPct))", symbol: "timer"))
        }
        // 装備の作り直し（2026-10）で足した能力値。貫通・吸血・クリティカルなど
        let pct = { (v: Double) in "+\(CollectionStyle.percent(v))" }
        if item.attackSpeedPct != 0 { lines.append(.init(label: L("攻撃速度", "Attack Speed"), value: pct(item.attackSpeedPct), symbol: "speedometer")) }
        if item.critChancePct != 0 { lines.append(.init(label: L("クリティカル率", "Crit Chance"), value: pct(item.critChancePct), symbol: "scope")) }
        if item.critDamagePct != 0 { lines.append(.init(label: L("クリティカルダメージ", "Crit Damage"), value: pct(item.critDamagePct), symbol: "scope")) }
        if item.armorPenPct != 0 { lines.append(.init(label: L("物理貫通", "Physical Pen."), value: pct(item.armorPenPct), symbol: "xmark.shield.fill")) }
        if item.armorPenFlat != 0 { lines.append(.init(label: L("物理貫通（固定）", "Physical Pen. (flat)"), value: "+\(n(item.armorPenFlat))", symbol: "xmark.shield.fill")) }
        if item.magicPenPct != 0 { lines.append(.init(label: L("魔法貫通", "Magic Pen."), value: pct(item.magicPenPct), symbol: "xmark.shield.fill")) }
        if item.magicPenFlat != 0 { lines.append(.init(label: L("魔法貫通（固定）", "Magic Pen. (flat)"), value: "+\(n(item.magicPenFlat))", symbol: "xmark.shield.fill")) }
        if item.lifestealPct != 0 { lines.append(.init(label: L("ライフスティール", "Lifesteal"), value: pct(item.lifestealPct), symbol: "drop.fill")) }
        if item.spellVampPct != 0 { lines.append(.init(label: L("スペルヴァンプ", "Spell Vamp"), value: pct(item.spellVampPct), symbol: "drop.fill")) }
        if item.abilityPowerPct != 0 { lines.append(.init(label: L("魔力", "Power"), value: pct(item.abilityPowerPct), symbol: "sparkles")) }
        if item.hpRegen != 0 { lines.append(.init(label: L("HP回復", "HP Regen"), value: "+\(n(item.hpRegen))", symbol: "cross.fill")) }
        if item.resourceRegen != 0 { lines.append(.init(label: L("リソース回復", "Resource Regen"), value: "+\(n(item.resourceRegen))", symbol: "drop.circle.fill")) }
        if item.moveSpeedPct != 0 { lines.append(.init(label: L("移動速度", "Move Speed"), value: pct(item.moveSpeedPct), symbol: "hare.fill")) }
        if item.outOfCombatMovePct != 0 { lines.append(.init(label: L("非戦闘時の移動速度", "Out-of-combat Move Speed"), value: pct(item.outOfCombatMovePct), symbol: "hare.fill")) }
        if item.healShieldPowerPct != 0 { lines.append(.init(label: L("回復・シールド量", "Heal & Shield Power"), value: pct(item.healShieldPowerPct), symbol: "heart.circle.fill")) }
        if item.monsterDamagePct != 0 { lines.append(.init(label: L("モンスターへのダメージ", "Monster Damage"), value: pct(item.monsterDamagePct), symbol: "pawprint.fill")) }
        return lines
    }

    /// 一覧用の主要能力（最初の能力値）。
    static func primaryStat(_ item: ItemDef) -> ItemStatLine? {
        statLines(item).first
    }

    /// カテゴリ別の固有パッシブ効果（X = passive_text の %）。
    static func passiveEffectText(_ item: ItemDef) -> String {
        // 装備の作り直し（2026-10）以降、固有効果は装備ごとの文（日本語はマスター、英語は master_en.json の "<id>.desc"）。
        // ギア（EQJ/EQR のジャングル靴・ローム靴）は従来どおりカテゴリ別の説明。
        if item.itemID.hasPrefix("EQ0"), !item.passiveText.isEmpty {
            return MasterText.description(id: item.itemID, ja: item.passiveText)
        }
        let x = item.passivePercent
        let p = { (v: Double) in CollectionStyle.percent(v) }
        switch item.category {
        case .attack:
            return L("通常攻撃のダメージ +\(p(x))", "Basic attack damage +\(p(x))")
        case .magic:
            return L("スキルダメージ +\(p(x))", "Skill damage +\(p(x))")
        case .defense:
            return L("受けるダメージ −\(p(x / 2))", "Damage taken −\(p(x / 2))")
        case .movement:
            return L("非戦闘時の移動速度 +\(p(x))", "Out-of-combat move speed +\(p(x))")
        case .utility:
            return L("回復・シールド量 +\(p(x))、Mana 回復 +\(p(x))", "Healing & shielding +\(p(x)), mana regen +\(p(x))")
        case .jungle:
            return L("モンスターへのダメージ +\(p(3 * x))、モンスター Gold +20%（ミニオンの Gold/XP は 5:00 まで半減）",
                     "Damage to monsters +\(p(3 * x)), monster gold +20% (minion Gold/XP halved until 5:00)")
        case .roam:
            return L("5 秒ごとにチーム共有の Gold・XP（8:00 から増加）。自分のミニオン・モンスター収入は 8:00 まで半減",
                     "Shared team Gold/XP every 5s (more from 8:00). Your minion and monster income is halved until 8:00")
        }
    }

    /// 素材（build_from）。存在しない ID は除外、重複は保持。
    static func components(_ item: ItemDef, master: MasterData) -> [ItemDef] {
        item.buildFrom.compactMap { master.item($0) }
    }

    /// この装備を素材に含む上位装備（ID 昇順）。
    static func buildsInto(_ itemID: String, master: MasterData) -> [ItemDef] {
        master.items.filter { $0.buildFrom.contains(itemID) }
    }

    /// 素材をすべて所持している場合の合成コスト = max(price × 0.3, price − 素材価格合計)。
    static func combineCost(_ item: ItemDef, master: MasterData) -> Double {
        let parts = components(item, master: master).reduce(0) { $0 + $1.priceGold }
        guard parts > 0 else { return item.priceGold }
        return max(item.priceGold * Balance.minCombineCostRatio, item.priceGold - parts).rounded()
    }

    static func filtered(_ items: [ItemDef], category: ItemCategory?, tier: Int?) -> [ItemDef] {
        items.filter { (category == nil || $0.category == category) && (tier == nil || $0.tier == tier) }
    }
}

// MARK: - ビルド（DESIGN §8: 6 枠・移動系 1・ジャングル系 1）

enum BuildCheck: Equatable {
    case ok
    case full
    case duplicate
    case movementLimit
    case jungleLimit
    case roamLimit
    /// 靴枠（移動系・ジャングル靴・ローム靴）は 1 つまで。
    case bootsLimit
    /// ローム靴とジャングル装備は同時に持てない（狩猟印の有無が前提のため）。
    case roamJungleConflict
    /// ローム靴は狩猟印を装備していると使えない。
    case roamBlockedBySmite
    case unknown

    var message: String {
        switch self {
        case .ok: return ""
        case .full: return L("装備枠がいっぱいです（最大 6 個）", "All 6 slots are filled")
        case .duplicate: return L("同じ装備は 1 つまでです（固有パッシブは重複しません）", "Only one of each item (unique passives don't stack)")
        case .movementLimit: return L("移動系装備は 1 つまでです", "Only one Movement item allowed")
        case .jungleLimit: return L("ジャングル系装備は 1 つまでです", "Only one Jungle item allowed")
        case .roamLimit: return L("ローム系装備は 1 つまでです", "Only one Roam item allowed")
        case .bootsLimit: return L("靴は 1 つまでです（移動系・ジャングル靴・ローム靴）", "Only one pair of boots (Movement, Jungle or Roam)")
        case .roamJungleConflict: return L("ローム装備とジャングル装備は同時に持てません", "Roam and Jungle items can't be combined")
        case .roamBlockedBySmite:
            return L("ローム靴は狩猟印と一緒には使えません。ローム靴を入れるには、先にバトルスペルから狩猟印を外してください（狩猟印はジャングル用のスペルです）",
                     "Roam boots can't be used with the hunting spell (Jungle's spell). Remove it from your battle spells first to add roam boots")
        case .unknown: return L("不明な装備です", "Unknown item")
        }
    }
}

enum BuildRules {
    static var slotCount: Int { Balance.itemSlots }

    /// 不明 ID・上限超過・制限違反を取り除く（順序は保持）。
    static func sanitized(_ build: [String], master: MasterData) -> [String] {
        var result: [String] = []
        for id in build where check(id, adding: result, replacing: nil, master: master) == .ok {
            result.append(id)
        }
        return result
    }

    /// build に itemID を追加（replacing 指定時はその位置を置換）できるか。
    /// spells = 装備中のバトルスペル（渡すと、狩猟印ありでのローム靴を断る）。
    static func check(_ itemID: String, adding build: [String], replacing index: Int?, master: MasterData,
                      spells: [String]? = nil) -> BuildCheck {
        guard let item = master.item(itemID) else { return .unknown }
        if item.category == .roam, spells?.contains(smiteSpellID) == true { return .roamBlockedBySmite }
        var others = build
        if let index, others.indices.contains(index) {
            others.remove(at: index)
        } else if build.count >= slotCount {
            return .full
        }
        if others.contains(itemID) { return .duplicate }
        let categories = others.compactMap { master.item($0)?.category }
        if item.category == .movement && categories.contains(.movement) { return .movementLimit }
        if item.category == .jungle && categories.contains(.jungle) { return .jungleLimit }
        if item.category == .roam && categories.contains(.roam) { return .roamLimit }
        if (item.category == .roam && categories.contains(.jungle)) || (item.category == .jungle && categories.contains(.roam)) {
            return .roamJungleConflict
        }
        if ItemSystem.isBoots(item), others.contains(where: { master.item($0).map(ItemSystem.isBoots) == true }) {
            return .bootsLimit
        }
        return .ok
    }

    /// 狩猟印（ジャングル装備の購入に必要なバトルスペル、DESIGN §7）。
    static let smiteSpellID = "BS05"

    /// 狩猟印の表示名（英語はマスターの英語名に追従）。
    static func smiteName(master: MasterData) -> String {
        master.spell(smiteSpellID).map { MasterText.spell($0) } ?? smiteSpellID
    }

    /// ジャングル装備を含み、かつ狩猟印を装備していないか（戦闘中に購入できない組み合わせ）。
    static func lacksSmite(_ build: [String], spells: [String], master: MasterData) -> Bool {
        build.contains { master.item($0)?.category == .jungle } && !spells.contains(smiteSpellID)
    }

    /// ローム靴を含み、かつ狩猟印を装備していないか（ローム靴は狩猟印と併用できず、戦闘中に購入できない）。
    static func roamConflictsSmite(_ build: [String], spells: [String], master: MasterData) -> Bool {
        build.contains { master.item($0)?.category == .roam } && spells.contains(smiteSpellID)
    }

    static func totalCost(_ build: [String], master: MasterData) -> Double {
        build.compactMap { master.item($0)?.priceGold }.reduce(0, +)
    }

    /// 推奨ビルド（ヒーロー別、無ければロール別。未提供なら空）。
    static func recommended(for heroID: String, master: MasterData) -> [String] {
        guard let role = master.hero(heroID)?.role else { return [] }
        return sanitized(ItemSystem.recommendedBuild(heroID: heroID, role: role, master: master), master: master)
    }

    /// 表示・編集の初期値: カスタムビルド優先、無ければ推奨。
    static func current(for heroID: String, profile: Profile, master: MasterData) -> [String] {
        if let custom = profile.customBuilds[heroID] {
            return sanitized(custom, master: master)
        }
        return recommended(for: heroID, master: master)
    }

    static func move(_ build: [String], from: Int, by offset: Int) -> [String] {
        let to = from + offset
        guard build.indices.contains(from), build.indices.contains(to) else { return build }
        var b = build
        b.swapAt(from, to)
        return b
    }
}

// MARK: - ルーン（DESIGN §8: メインパス 1 + 各 Tier 1 個）

struct RuneBonus: Equatable {
    var attackPct: Double = 0
    var abilityPowerPct: Double = 0
    var skillDamagePct: Double = 0
    var maxHPPct: Double = 0
    var defensesPct: Double = 0
    var moveSpeedPct: Double = 0
    var cooldownReductionPct: Double = 0
    var regenPct: Double = 0
    var healingPct: Double = 0

    /// 表示用の行（0 は除外）。
    var lines: [ItemStatLine] {
        var out: [ItemStatLine] = []
        let p = { (v: Double) in "+" + CollectionStyle.percent(v) }
        if attackPct > 0 { out.append(.init(label: L("攻撃力", "Attack"), value: p(attackPct), symbol: "bolt.fill")) }
        if abilityPowerPct > 0 { out.append(.init(label: L("魔力", "Power"), value: p(abilityPowerPct), symbol: "sparkles")) }
        if skillDamagePct > 0 { out.append(.init(label: L("スキルダメージ", "Skill Damage"), value: p(skillDamagePct), symbol: "wand.and.stars")) }
        if maxHPPct > 0 { out.append(.init(label: L("最大HP", "Max HP"), value: p(maxHPPct), symbol: "heart.fill")) }
        if defensesPct > 0 { out.append(.init(label: L("防御・魔防", "Armor & MR"), value: p(defensesPct), symbol: "shield.fill")) }
        if moveSpeedPct > 0 { out.append(.init(label: L("移動速度", "Move Speed"), value: p(moveSpeedPct), symbol: "hare.fill")) }
        if cooldownReductionPct > 0 { out.append(.init(label: L("CD短縮", "Cooldown Red."), value: p(cooldownReductionPct), symbol: "timer")) }
        if regenPct > 0 { out.append(.init(label: L("HP/Mana 回復", "HP/Mana Regen"), value: p(regenPct), symbol: "arrow.clockwise")) }
        if healingPct > 0 { out.append(.init(label: L("回復量", "Healing"), value: p(healingPct), symbol: "cross.circle.fill")) }
        return out
    }
}

enum RuneMath {
    static let maxPages = 5
    static let tiers = [1, 2, 3]
    static let maxNameLength = 16

    /// パス・Tier のルーン（ID 昇順）。
    static func runes(path: RunePath, tier: Int, master: MasterData) -> [RuneDef] {
        master.runes.filter { $0.path == path && $0.tier == tier }
    }

    static func defaultPageName(index: Int) -> String {
        L("ページ\(index + 1)", "Page \(index + 1)")
    }

    /// 各 Tier の先頭ルーンを選んだ既定ページ。
    static func defaultPage(name: String, path: RunePath = .valor, master: MasterData) -> RunePage {
        RunePage(name: name, primaryPath: path,
                 runeIDs: tiers.map { runes(path: path, tier: $0, master: master).first?.runeID ?? "" })
    }

    /// パスと Tier が一致しないルーンを既定値に置き換え、3 枠に揃える。
    static func normalized(_ page: RunePage, master: MasterData) -> RunePage {
        var p = page
        p.runeIDs = tiers.enumerated().map { i, tier in
            let options = runes(path: page.primaryPath, tier: tier, master: master)
            let current = i < page.runeIDs.count ? page.runeIDs[i] : ""
            if options.contains(where: { $0.runeID == current }) { return current }
            return options.first?.runeID ?? ""
        }
        let trimmed = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        p.name = String(trimmed.prefix(maxNameLength))
        return p
    }

    /// パス変更（ルーンは新パスの既定に置換）。
    static func changingPath(_ page: RunePage, to path: RunePath, master: MasterData) -> RunePage {
        var p = page
        p.primaryPath = path
        p.runeIDs = []
        return normalized(p, master: master)
    }

    /// 1 個分の効果（X = effect の %）。
    static func bonus(path: RunePath, percent x: Double) -> RuneBonus {
        var b = RuneBonus()
        switch path {
        case .valor:
            b.attackPct = x
        case .arcana:
            b.abilityPowerPct = x
            b.skillDamagePct = x / 2
        case .resolve:
            b.maxHPPct = x
            b.defensesPct = x
        case .cunning:
            b.moveSpeedPct = x / 2
            b.cooldownReductionPct = x / 2
        case .harmony:
            b.regenPct = 3 * x
            b.healingPct = x
        }
        return b
    }

    /// ページ全体の合計。
    static func bonus(for page: RunePage, master: MasterData) -> RuneBonus {
        var total = RuneBonus()
        for id in page.runeIDs {
            guard let r = master.rune(id) else { continue }
            let b = bonus(path: r.path, percent: r.percent)
            total.attackPct += b.attackPct
            total.abilityPowerPct += b.abilityPowerPct
            total.skillDamagePct += b.skillDamagePct
            total.maxHPPct += b.maxHPPct
            total.defensesPct += b.defensesPct
            total.moveSpeedPct += b.moveSpeedPct
            total.cooldownReductionPct += b.cooldownReductionPct
            total.regenPct += b.regenPct
            total.healingPct += b.healingPct
        }
        return total
    }

    /// ルーン 1 個の効果文。
    static func effectText(_ rune: RuneDef) -> String {
        bonus(path: rune.path, percent: rune.percent).lines.map { "\($0.label) \($0.value)" }
            .joined(separator: L("・", ", "))
    }
}

// MARK: - スペル（2 枠・既定 + ヒーロー別）
// モバイル系 MOBA 風に、1 枠目は好きなスペルを選べる枠、2 枠目は治癒波（BS03）で固定する。

enum SpellLoadoutRules {
    static let slotCount = 2
    /// 選べる枠（瞬歩が既定）。
    static let selectableSlot = 0
    /// 固定枠（治癒波）。
    static let fixedSlot = 1
    static let fixedSpellID = "BS03"

    /// 選べる枠に入れられるスペルか（固定スペル以外）。
    static func isSelectable(_ spellID: String) -> Bool { spellID != fixedSpellID }

    /// 選べる枠に spellID を入れる。固定枠・固定スペルは変更しない。
    static func assigning(_ spellID: String, slot: Int, in current: [String]) -> [String] {
        var s = normalized(current)
        guard slot == selectableSlot, isSelectable(spellID) else { return s }
        s[selectableSlot] = spellID
        return s
    }

    /// 2 枠に揃える（[選べる枠, 治癒波]）。選べる枠は不明 ID・治癒波を除いた先頭、無ければ BS01/BS04 で補う。
    static func normalized(_ spells: [String], master: MasterData = .shared) -> [String] {
        let free = (spells + ["BS01", "BS04"]).first { isSelectable($0) && master.spell($0) != nil } ?? "BS01"
        return [free, fixedSpellID]
    }

    /// ヒーローの実効スペル（上書きが無ければ既定）。
    static func effective(heroID: String?, profile: Profile) -> [String] {
        if let heroID, let override = profile.heroSpells[heroID] { return normalized(override) }
        return normalized(profile.defaultSpells)
    }
}

// MARK: - エモート（最大 4 枠）
// profile.equippedEmotes は「空き枠を詰めた最大 4 要素の ID 列」で保存する（EconomyService・戦闘 HUD と同じ表現）。
// 枠 i の中身は ids[i]（i >= count は空き枠）。

enum EmoteSlots {
    static let count = 4

    /// 空文字・重複を除き、最大 4 個に詰める（順序は保持）。
    static func normalized(_ ids: [String]) -> [String] {
        var out: [String] = []
        for id in ids where !id.isEmpty && !out.contains(id) {
            out.append(id)
            if out.count == count { break }
        }
        return out
    }

    /// 表示用の枠 i の中身（空き枠は nil）。
    static func emote(at slot: Int, in ids: [String]) -> String? {
        let s = normalized(ids)
        return s.indices.contains(slot) ? s[slot] : nil
    }

    /// 次に埋まる空き枠（満杯なら nil）。
    static func firstEmptySlot(in ids: [String]) -> Int? {
        let n = normalized(ids).count
        return n < count ? n : nil
    }

    /// slot に emoteID を装備する。
    /// 装備済みのエモートを別の埋まった枠へ置くと入れ替え、空き枠を指定した場合は末尾（最初の空き枠）へ詰める。
    static func assigning(_ emoteID: String, slot: Int, in current: [String]) -> [String] {
        var s = normalized(current)
        guard !emoteID.isEmpty, (0..<count).contains(slot) else { return s }
        if let other = s.firstIndex(of: emoteID) {
            if s.indices.contains(slot) { s.swapAt(other, slot) }
            return s
        }
        if s.indices.contains(slot) {
            s[slot] = emoteID
        } else if s.count < count {
            s.append(emoteID)
        }
        return s
    }

    /// 枠を空ける（後ろの枠は前へ詰まる）。
    static func clearing(slot: Int, in current: [String]) -> [String] {
        var s = normalized(current)
        if s.indices.contains(slot) { s.remove(at: slot) }
        return s
    }

    /// 所持していない ID を外す。
    static func pruned(_ ids: [String], owned: [String]) -> [String] {
        normalized(ids).filter { owned.contains($0) }
    }
}
