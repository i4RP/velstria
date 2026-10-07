import SwiftUI
import VelstriaCore

// 担当: ui-collection。コレクション/ストア画面で共通の表示名・色・記号。
// 他担当と型名が衝突しないよう、共有型への extension は作らず static 関数に集約する。

enum CollectionStyle {
    // MARK: 数値表示

    /// 小数は最大 digits 桁（末尾の 0 は省略）。
    static func number(_ v: Double, digits: Int = 1) -> String {
        v.formatted(.number.precision(.fractionLength(0...digits)))
    }

    static func percent(_ v: Double, digits: Int = 1) -> String {
        "\(number(v, digits: digits))%"
    }

    static func seconds(_ v: Double) -> String {
        L("\(number(v, digits: 2))秒", "\(number(v, digits: 2))s")
    }

    // MARK: ヒーロー

    static func resourceName(_ r: ResourceKind) -> String {
        switch r {
        case .mana: return L("マナ", "Mana")
        case .energy: return L("エナジー", "Energy")
        }
    }

    static func resourceColor(_ r: ResourceKind) -> Color {
        switch r {
        case .mana: return Color(red: 0.38, green: 0.62, blue: 1.0)
        case .energy: return Color(red: 1.0, green: 0.85, blue: 0.35)
        }
    }

    static func resourceSymbol(_ r: ResourceKind) -> String {
        r == .mana ? "drop.fill" : "bolt.fill"
    }

    static func damageTypeName(_ d: DamageType) -> String {
        switch d {
        case .physical: return L("物理", "Physical")
        case .magic: return L("魔法", "Magic")
        case .trueDamage: return L("確定", "True")
        }
    }

    static func damageTypeColor(_ d: DamageType) -> Color {
        switch d {
        case .physical: return Color(red: 1.0, green: 0.55, blue: 0.35)
        case .magic: return Color(red: 0.62, green: 0.55, blue: 1.0)
        case .trueDamage: return Color.white
        }
    }

    static func damageTypeSymbol(_ d: DamageType) -> String {
        switch d {
        case .physical: return "burst.fill"
        case .magic: return "sparkles"
        case .trueDamage: return "staroflife.fill"
        }
    }

    static func difficultyName(_ d: Int) -> String {
        switch d {
        case ...1: return L("かんたん", "Easy")
        case 2: return L("ふつう", "Moderate")
        case 3: return L("標準", "Standard")
        case 4: return L("むずかしい", "Hard")
        default: return L("上級", "Expert")
        }
    }

    // MARK: スキル

    static func slotBadge(_ s: SkillSlot) -> String {
        switch s {
        case .passive: return "P"
        case .skill1: return "1"
        case .skill2: return "2"
        case .ultimate: return "U"
        }
    }

    static func slotName(_ s: SkillSlot) -> String {
        switch s {
        case .passive: return L("パッシブ", "Passive")
        case .skill1: return L("スキル1", "Skill 1")
        case .skill2: return L("スキル2", "Skill 2")
        case .ultimate: return L("アルティメット", "Ultimate")
        }
    }

    static func slotColor(_ s: SkillSlot) -> Color {
        switch s {
        case .passive: return Color(red: 0.62, green: 0.66, blue: 0.80)
        case .skill1, .skill2: return Theme.cyan
        case .ultimate: return Theme.gold
        }
    }

    static func ccName(_ c: CrowdControl) -> String {
        switch c {
        case .none: return L("なし", "None")
        case .slow: return L("スロー", "Slow")
        case .knockback: return L("ノックバック", "Knockback")
        case .root: return L("拘束", "Root")
        case .stun: return L("スタン", "Stun")
        }
    }

    static func ccSymbol(_ c: CrowdControl) -> String {
        switch c {
        case .none: return "minus.circle"
        case .slow: return "tortoise.fill"
        case .knockback: return "arrow.up.right.circle.fill"
        case .root: return "link"
        case .stun: return "star.circle.fill"
        }
    }

    static func ccColor(_ c: CrowdControl) -> Color {
        switch c {
        case .none: return Theme.textSecondary
        case .slow: return Color(red: 0.45, green: 0.78, blue: 1.0)
        case .knockback: return Color(red: 1.0, green: 0.62, blue: 0.30)
        case .root: return Color(red: 0.45, green: 0.95, blue: 0.55)
        case .stun: return Color(red: 1.0, green: 0.86, blue: 0.30)
        }
    }

    static func archetypeName(_ a: SkillArchetype) -> String {
        switch a {
        case .passive: return L("パッシブ", "Passive")
        case .cone: return L("前方扇形", "Cone")
        case .lineSkillshot: return L("直線スキルショット", "Line Skillshot")
        case .piercingLine: return L("貫通直線", "Piercing Line")
        case .dashStrike: return L("突進攻撃", "Dash Strike")
        case .blinkEmpower: return L("ブリンク強化", "Blink & Empower")
        case .groundAoE: return L("地点範囲", "Ground AoE")
        case .selfAoE: return L("自身中心範囲", "Self AoE")
        case .healZone: return L("回復ゾーン", "Healing Zone")
        case .leapSlam: return L("跳躍突撃", "Leap Slam")
        case .multiStrike: return L("連続斬り", "Multi-Strike")
        case .teamHeal: return L("味方全体回復", "Team Heal")
        case .targetedBlink: return L("対象指定ブリンク", "Targeted Blink")
        }
    }

    static func archetypeDescription(_ a: SkillArchetype) -> String {
        switch a {
        case .passive:
            return L("常時発動する固有能力。条件を満たすと自動で効果が発動します。",
                     "An always-on trait that triggers automatically when its condition is met.")
        case .cone:
            return L("前方の扇形（角度 90°）内の敵すべてに即座に効果を与えます。",
                     "Instantly hits every enemy inside a 90° cone in front of you.")
        case .lineSkillshot:
            return L("指定方向へ弾を放ち、最初に当たった敵に効果を与えます。",
                     "Fires a projectile that hits the first enemy in its path.")
        case .piercingLine:
            return L("長い直線上を貫通し、触れた敵すべてに効果を与えます。",
                     "A long piercing line that hits every enemy it passes through.")
        case .dashStrike:
            return L("指定方向へ突進し、着地点の周囲に効果を与えます。",
                     "Dash in a direction and hit enemies around the landing point.")
        case .blinkEmpower:
            return L("短距離をブリンクし、次の通常攻撃が強化されます。",
                     "Blink a short distance; your next basic attack is empowered.")
        case .groundAoE:
            return L("指定地点に予告円を出し、短い遅延の後に範囲効果が発動します。",
                     "Marks a target area; the effect detonates after a short delay.")
        case .selfAoE:
            return L("自身の周囲に即座に範囲効果を与え、自身にシールドを得ます。",
                     "Instantly hits enemies around you and grants yourself a shield.")
        case .healZone:
            return L("指定地点に味方を回復するゾーンを展開し、敵にはダメージを与えます。",
                     "Creates a zone that heals allies and damages enemies inside.")
        case .leapSlam:
            return L("遠くへ跳躍し、着地点の広い範囲に効果を与えます。",
                     "Leap a long distance and slam a wide area on landing.")
        case .multiStrike:
            return L("範囲内の敵ヒーローを連続で攻撃し、その間の被ダメージを軽減します。",
                     "Strikes nearby enemy heroes repeatedly while reducing damage taken.")
        case .teamHeal:
            return L("周囲の味方全員を回復・シールドし、近くの敵を妨害します。",
                     "Heals and shields all nearby allies and disrupts nearby enemies.")
        case .targetedBlink:
            return L("最寄りの敵ヒーローへ瞬時に移動し、失った HP に応じた追加ダメージを与えます。",
                     "Blinks to the nearest enemy hero and deals bonus damage based on missing HP.")
        }
    }

    // MARK: 装備

    static func categoryName(_ c: ItemCategory) -> String {
        switch c {
        case .attack: return L("攻撃", "Attack")
        case .magic: return L("魔力", "Magic")
        case .defense: return L("防御", "Defense")
        case .movement: return L("移動", "Movement")
        case .utility: return L("補助", "Utility")
        case .jungle: return L("ジャングル", "Jungle")
        }
    }

    static func categorySymbol(_ c: ItemCategory) -> String {
        switch c {
        case .attack: return "bolt.fill"
        case .magic: return "sparkles"
        case .defense: return "shield.fill"
        case .movement: return "wind"
        case .utility: return "cross.vial.fill"
        case .jungle: return "leaf.fill"
        }
    }

    static func categoryColor(_ c: ItemCategory) -> Color {
        switch c {
        case .attack: return Color(red: 1.0, green: 0.46, blue: 0.36)
        case .magic: return Color(red: 0.70, green: 0.50, blue: 1.0)
        case .defense: return Color(red: 0.42, green: 0.70, blue: 1.0)
        case .movement: return Color(red: 0.45, green: 0.95, blue: 0.80)
        case .utility: return Color(red: 0.98, green: 0.78, blue: 0.40)
        case .jungle: return Color(red: 0.52, green: 0.86, blue: 0.40)
        }
    }

    static func tierName(_ tier: Int) -> String {
        L("ティア\(tier)", "Tier \(tier)")
    }

    static func tierColor(_ tier: Int) -> Color {
        switch tier {
        case ...1: return Color(red: 0.72, green: 0.76, blue: 0.84)
        case 2: return Color(red: 0.45, green: 0.78, blue: 1.0)
        default: return Theme.gold
        }
    }

    // MARK: ルーン

    static func runePathName(_ p: RunePath) -> String {
        switch p {
        case .valor: return L("勇気", "Valor")
        case .arcana: return L("秘術", "Arcana")
        case .resolve: return L("堅守", "Resolve")
        case .cunning: return L("狡知", "Cunning")
        case .harmony: return L("調和", "Harmony")
        }
    }

    static func runePathSymbol(_ p: RunePath) -> String {
        switch p {
        case .valor: return "flame.fill"
        case .arcana: return "sparkles"
        case .resolve: return "shield.lefthalf.filled"
        case .cunning: return "eye.fill"
        case .harmony: return "leaf.fill"
        }
    }

    static func runePathColor(_ p: RunePath) -> Color {
        switch p {
        case .valor: return Color(red: 1.0, green: 0.45, blue: 0.35)
        case .arcana: return Color(red: 0.72, green: 0.52, blue: 1.0)
        case .resolve: return Color(red: 0.40, green: 0.72, blue: 1.0)
        case .cunning: return Color(red: 1.0, green: 0.80, blue: 0.32)
        case .harmony: return Color(red: 0.40, green: 0.92, blue: 0.62)
        }
    }

    static func runePathTagline(_ p: RunePath) -> String {
        switch p {
        case .valor: return L("攻撃力を高める", "Raises attack")
        case .arcana: return L("魔力とスキルダメージ", "Power & skill damage")
        case .resolve: return L("最大HPと防御", "Max HP & defenses")
        case .cunning: return L("移動速度とCD短縮", "Speed & cooldowns")
        case .harmony: return L("回復と自然回復", "Healing & regen")
        }
    }

    // MARK: コスメ・レアリティ

    static func rarityName(_ r: Rarity) -> String {
        switch r {
        case .common: return L("コモン", "Common")
        case .rare: return L("レア", "Rare")
        case .epic: return L("エピック", "Epic")
        case .mythic: return L("ミシック", "Mythic")
        }
    }

    static func cosmeticTypeName(_ t: CosmeticType) -> String {
        switch t {
        case .heroSkin: return L("スキン", "Skin")
        case .recall: return L("帰還演出", "Recall")
        case .spawn: return L("出現演出", "Spawn")
        case .emote: return L("エモート", "Emote")
        case .avatarFrame: return L("アバターフレーム", "Avatar Frame")
        case .killEffect: return L("キル演出", "Kill Effect")
        }
    }

    static func cosmeticTypeSymbol(_ t: CosmeticType) -> String {
        switch t {
        case .heroSkin: return "paintpalette.fill"
        case .recall: return "arrow.uturn.down.circle.fill"
        case .spawn: return "light.beacon.max.fill"
        case .emote: return "bubble.left.fill"
        case .avatarFrame: return "person.crop.square.fill"
        case .killEffect: return "burst.fill"
        }
    }

    static func currencyName(_ c: Currency) -> String {
        switch c {
        case .astralGem: return "AstralGem"
        case .starlightCoin: return "StarlightCoin"
        }
    }

    static func currencySymbol(_ c: Currency) -> String {
        c == .astralGem ? "diamond.fill" : "star.circle.fill"
    }

    static func currencyColor(_ c: Currency) -> Color {
        c == .astralGem ? Theme.cyan : Theme.gold
    }

    /// 戦闘内 Gold（装備価格）の色。
    static let goldColor = Color(red: 1.0, green: 0.76, blue: 0.28)
}
