import Foundation
import VelstriaCore

// 担当: hero-models。34 ヒーローの造形設計（体型・頭部・武器・背中・浮遊物・攻撃モーション）。
// 基調色は Theme.heroHue、アクセント・発光は名前のモチーフから決める。

/// titan = heavy よりさらに肩幅・胸板・腕脚が太く、頭を肩の間に沈めた巨漢（H029 ボルグ）。
enum BodyBuild { case heavy, standard, slim, robed, titan }

extension BodyBuild {
    /// 重装の体格（heavy / titan）。腰の金具・マントの長さ・脚の開きなどを共通にする。
    var isHeavy: Bool { self == .heavy || self == .titan }
}

/// knight = 基調色（青）の板金に、金属色（金）の縁取り・胸の聖印・籠手の輪を添えた重装（H029 ボルグ）。
/// plate は金属色そのものが鎧の地色になる（銀・鉄・金の鎧）。
/// frost / dragon / abyss は H031 オーリア・H027 ジャルド・H032 ディアス専用（HeroAssembler の各 case に説明）。
enum ArmorStyle { case plate, leather, cloth, rock, fur, mech, light, knight, frost, dragon, abyss }

/// spiked = 濃い紫の肩甲から上へ反る棘（H032 ディアス）。
enum PauldronStyle { case none, small, round, big, rock, fur, crystal, feather, spiked }

/// iceGown = 裾が氷の結晶で広がる人魚形の長いドレス（H031）。longCoat = 淡い上衣の長い前後の裾と青緑の草摺（H027）。
enum SkirtStyle { case none, tassets, robe, shortSkirt, coat, loincloth, petals, kilt, iceGown, longCoat }

/// flowing = 腰まで流れる量の多い長髪と、肩の前へ垂らす房（H031）。
enum HairStyle { case none, short, spiky, long, ponytail, twinTails, bob, topknot, braids, mohawk, wild, flowing }

enum HeadGear {
    case knightHelm, hood, deepHood, mask, starPin, shellCrown, flameCrown, goggles, beastMask
    case hornHelm, vikingHelm, wideHat, foxEars, wingedHelm, nightcap, flowerCrown, circlet
    case featherPin, glassVisor, ironVisor, headband, beard, crescentPin, ribbon
    case iceCrown
    case dragonCrest, demonHorns
}

enum WeaponKind {
    case none, broadsword, starRapier, tideStaff, lightningSpear, crescentDagger, stoneFist, windBanner
    case mechCrossbow, handFlame, aegisStaff, glassDagger, boneClub, mistKatana, bellBlunderbuss
    case haloStaff, abyssCenser, petalBlade, siegeHammer, lightArrowBlade, sandRifle, azureClaw
    case thunderLance, dreamNeedle
    case dragonSpear, stormWand, photonBlade, holyMaul
    case starCannon, iceStaff, fistBlade, bloodGreatsword, hookChain
    /// 手首の刃の輪（H032 ディアス。左手は OffhandKind.abyssRing）。
    case abyssRing
}

enum OffhandKind {
    case none, gateShield, harpBow, ashBow, moonLantern, stoneFist, grimoire, glassDagger, hideShield
    case shortBlade, petalBlade, lightBow, azureClaw, dreamNeedle
    case crescentBow, heaterShield
    case abyssRing
}

enum BackKind {
    case none, cape, quiver, ironWings, warBell, gearPack, mistCloak, tatteredCape, scarfTails
    case windRibbons, sash, furCape, chainSash
    case demonTail
}

enum FloatKind {
    case none, waterOrb, lightningHalo, fireOrbs, glassShards, whiteHalo, abyssChains, petals
    case hourglass, clawCrystals, thunderOrb, dreamThreads, starMotes, sparkOrbs, iceCrystals
}

/// 通常攻撃のモーション系統。
enum AttackStyle { case slash, heavySwing, thrust, dualSlash, punch, bow, gun, staff, spellThrow }

struct HeroBlueprint {
    var build: BodyBuild
    var armor: ArmorStyle
    var pauldron: PauldronStyle
    var skirt: SkirtStyle
    var hair: HairStyle
    var gear: [HeadGear]
    var weapon: WeaponKind
    var offhand: OffhandKind
    var back: BackKind
    var float: FloatKind
    var attack: AttackStyle
    var metal: MetalKind
    var skin: SkinTone
    var hairColor: HSB
    var accent: HSB
    var glow: HSB
    /// 全体の拡縮（Vanguard は大きめ、Assassin は小さめ）。
    var scale: Float = 1
    /// 左腕が機械腕（オリン）。
    var mechArmLeft = false
    /// 深いフードの奥で目が光る。
    var glowingEyes = false
    /// 首元のスカーフ。
    var scarf = false

    /// 右手武器の表示倍率（上方カメラで読めるよう大きめ）。
    var weaponScale: Float {
        switch weapon {
        case .siegeHammer, .tideStaff, .haloStaff, .aegisStaff, .thunderLance, .windBanner, .dragonSpear, .stormWand, .iceStaff, .starCannon: return 1.08
        case .lightningSpear: return 1.12
        case .stoneFist, .holyMaul, .fistBlade, .hookChain: return 1.1
        case .broadsword, .boneClub, .mistKatana, .photonBlade: return 1.18
        case .bloodGreatsword: return 1.0
        default: return 1.28
        }
    }

    /// 左手装備の表示倍率。
    var offhandScale: Float {
        switch offhand {
        case .gateShield: return 0.88
        case .hideShield: return 0.95
        case .heaterShield: return 1.0
        case .stoneFist: return 1.1
        case .ashBow, .lightBow, .crescentBow: return 1.12
        default: return 1.28
        }
    }

    /// 右手武器が腕に追従する（拳・爪）。
    var weaponFollowsArm: Bool { weapon == .stoneFist || weapon == .azureClaw }
    /// 両手持ち（左手を柄・銃身に添える）。
    var twoHanded: Bool {
        switch weapon {
        case .siegeHammer, .mechCrossbow, .bellBlunderbuss, .sandRifle, .starCannon, .bloodGreatsword: return true
        default: return false
        }
    }
}

enum HeroBlueprints {
    /// H001...H034 の順。
    static let roster: [HeroBlueprint] = [
        // H001 城門の誓衛アルデン（Vanguard）: 城門塔の大盾・広刃剣・騎士兜
        HeroBlueprint(build: .heavy, armor: .plate, pauldron: .big, skirt: .tassets, hair: .none,
                      gear: [.knightHelm], weapon: .broadsword, offhand: .gateShield, back: .cape, float: .none,
                      attack: .slash, metal: .silver, skin: .fair, hairColor: HSB(0.08, 0.5, 0.45),
                      accent: HSB(0.58, 0.72, 0.9), glow: HSB(0.13, 0.45, 1.0), scale: 1.06),
        // H002 星弦のリラ（Duelist）: 星弦の竪琴弓・星の細剣
        HeroBlueprint(build: .standard, armor: .light, pauldron: .small, skirt: .shortSkirt, hair: .ponytail,
                      gear: [.starPin], weapon: .starRapier, offhand: .harpBow, back: .sash, float: .starMotes,
                      attack: .thrust, metal: .silver, skin: .fair, hairColor: HSB(0.13, 0.35, 1.0),
                      accent: HSB(0.13, 0.55, 1.0), glow: HSB(0.52, 0.45, 1.0)),
        // H003 月弓のフィリエル（Ranger）: 月の弓・三日月の額冠・銀白の長髪・矢筒
        HeroBlueprint(build: .slim, armor: .light, pauldron: .small, skirt: .shortSkirt, hair: .long,
                      gear: [.circlet, .crescentPin], weapon: .none, offhand: .ashBow, back: .quiver, float: .none,
                      attack: .bow, metal: .gold, skin: .fair, hairColor: HSB(0.55, 0.12, 0.96),
                      accent: HSB(0.5, 0.7, 0.85), glow: HSB(0.52, 0.45, 1.0)),
        // H004 潮祈のミレア（Arcanist）: 潮の杖と水球
        HeroBlueprint(build: .robed, armor: .cloth, pauldron: .small, skirt: .robe, hair: .long,
                      gear: [.shellCrown], weapon: .tideStaff, offhand: .none, back: .none, float: .waterOrb,
                      attack: .staff, metal: .silver, skin: .fair, hairColor: HSB(0.60, 0.72, 0.55),
                      accent: HSB(0.02, 0.38, 1.0), glow: HSB(0.50, 0.65, 1.0)),
        // H005 黒雷のヴォス（Support）: 黒雷の槍・雷の光輪
        HeroBlueprint(build: .robed, armor: .cloth, pauldron: .crystal, skirt: .robe, hair: .spiky,
                      gear: [], weapon: .lightningSpear, offhand: .none, back: .tatteredCape, float: .lightningHalo,
                      attack: .thrust, metal: .obsidian, skin: .pale, hairColor: HSB(0.7, 0.05, 0.96),
                      accent: HSB(0.76, 0.7, 1.0), glow: HSB(0.76, 0.6, 1.0)),
        // H006 月灯のセレン（Assassin）: 月の灯籠・三日月の短刀・フードと覆面
        HeroBlueprint(build: .slim, armor: .leather, pauldron: .none, skirt: .kilt, hair: .short,
                      gear: [.hood, .mask, .crescentPin], weapon: .crescentDagger, offhand: .moonLantern,
                      back: .scarfTails, float: .none, attack: .dualSlash, metal: .silver, skin: .fair,
                      hairColor: HSB(0.75, 0.15, 0.9), accent: HSB(0.14, 0.35, 1.0), glow: HSB(0.15, 0.45, 1.0),
                      scale: 0.97),
        // H007 岩脈のガルク（Vanguard）: 岩の籠手
        HeroBlueprint(build: .heavy, armor: .rock, pauldron: .rock, skirt: .loincloth, hair: .mohawk,
                      gear: [.headband, .beard], weapon: .stoneFist, offhand: .stoneFist, back: .none, float: .none,
                      attack: .punch, metal: .stone, skin: .tan, hairColor: HSB(0.02, 0.6, 0.45),
                      accent: HSB(0.08, 0.3, 0.55), glow: HSB(0.08, 0.9, 1.0), scale: 1.1),
        // H008 風標のニア（Duelist）: 風の旗槍
        HeroBlueprint(build: .standard, armor: .light, pauldron: .feather, skirt: .shortSkirt, hair: .short,
                      gear: [.featherPin], weapon: .windBanner, offhand: .none, back: .windRibbons, float: .none,
                      attack: .thrust, metal: .silver, skin: .fair, hairColor: HSB(0.06, 0.62, 0.62),
                      accent: HSB(0.48, 0.62, 0.95), glow: HSB(0.47, 0.5, 1.0)),
        // H009 機巧士オリン（Ranger）: 機械腕・連弩・ゴーグル
        HeroBlueprint(build: .standard, armor: .mech, pauldron: .round, skirt: .kilt, hair: .short,
                      gear: [.goggles], weapon: .mechCrossbow, offhand: .none, back: .gearPack, float: .none,
                      attack: .gun, metal: .brass, skin: .tan, hairColor: HSB(0.07, 0.55, 0.4),
                      accent: HSB(0.07, 0.7, 0.8), glow: HSB(0.09, 0.9, 1.0), mechArmLeft: true),
        // H010 焔冠のテッサ（Arcanist）: 焔の冠・魔導書・火球
        HeroBlueprint(build: .robed, armor: .cloth, pauldron: .small, skirt: .robe, hair: .long,
                      gear: [.flameCrown], weapon: .handFlame, offhand: .grimoire, back: .none, float: .fireOrbs,
                      attack: .spellThrow, metal: .gold, skin: .fair, hairColor: HSB(0.02, 0.82, 0.85),
                      accent: HSB(0.06, 0.85, 1.0), glow: HSB(0.07, 0.85, 1.0)),
        // H011 鉄翼のルーク（Support）: 鉄の翼・灯火の杖
        HeroBlueprint(build: .standard, armor: .plate, pauldron: .round, skirt: .kilt, hair: .short,
                      gear: [.ironVisor], weapon: .aegisStaff, offhand: .none, back: .ironWings, float: .none,
                      attack: .staff, metal: .iron, skin: .tan, hairColor: HSB(0.6, 0.3, 0.3),
                      accent: HSB(0.58, 0.18, 0.72), glow: HSB(0.5, 0.7, 1.0), scale: 1.03),
        // H012 玻璃歌のエリネ（Assassin）: 硝子の短剣・硝子片
        HeroBlueprint(build: .slim, armor: .light, pauldron: .crystal, skirt: .kilt, hair: .bob,
                      gear: [.glassVisor], weapon: .glassDagger, offhand: .glassDagger, back: .scarfTails,
                      float: .glassShards, attack: .dualSlash, metal: .silver, skin: .pale,
                      hairColor: HSB(0.55, 0.3, 1.0), accent: HSB(0.52, 0.28, 1.0), glow: HSB(0.54, 0.5, 1.0),
                      scale: 0.97),
        // H013 獣刻のダガン（Vanguard）: 獣の仮面・骨の棍棒・獣皮の盾
        HeroBlueprint(build: .heavy, armor: .fur, pauldron: .fur, skirt: .loincloth, hair: .wild,
                      gear: [.beastMask], weapon: .boneClub, offhand: .hideShield, back: .furCape, float: .none,
                      attack: .slash, metal: .bone, skin: .deep, hairColor: HSB(0.05, 0.4, 0.22),
                      accent: HSB(0.11, 0.2, 0.93), glow: HSB(0.0, 0.85, 1.0), scale: 1.08),
        // H014 霧歩のシオ（Duelist）: 霧の外套・二刀
        HeroBlueprint(build: .slim, armor: .cloth, pauldron: .none, skirt: .kilt, hair: .topknot,
                      gear: [.ribbon], weapon: .mistKatana, offhand: .shortBlade, back: .mistCloak, float: .none,
                      attack: .dualSlash, metal: .silver, skin: .fair, hairColor: HSB(0.66, 0.4, 0.2),
                      accent: HSB(0.72, 0.2, 0.95), glow: HSB(0.6, 0.35, 1.0)),
        // H015 戦鐘のヴァルカ（Ranger）: 鐘口の大筒・背負い戦鐘
        HeroBlueprint(build: .standard, armor: .leather, pauldron: .round, skirt: .kilt, hair: .braids,
                      gear: [.vikingHelm], weapon: .bellBlunderbuss, offhand: .none, back: .warBell, float: .none,
                      attack: .gun, metal: .bronze, skin: .fair, hairColor: HSB(0.12, 0.55, 1.0),
                      accent: HSB(0.09, 0.65, 0.85), glow: HSB(0.12, 0.7, 1.0), scale: 1.02),
        // H016 白環のイリス（Arcanist）: 白い光輪・環の杖
        HeroBlueprint(build: .robed, armor: .cloth, pauldron: .small, skirt: .robe, hair: .long,
                      gear: [.circlet], weapon: .haloStaff, offhand: .none, back: .none, float: .whiteHalo,
                      attack: .staff, metal: .gold, skin: .fair, hairColor: HSB(0.6, 0.04, 1.0),
                      accent: HSB(0.15, 0.06, 1.0), glow: HSB(0.13, 0.3, 1.0)),
        // H017 深淵鎖のモルド（Support）: 深淵の鎖・香炉灯
        HeroBlueprint(build: .robed, armor: .cloth, pauldron: .none, skirt: .robe, hair: .none,
                      gear: [.deepHood, .mask], weapon: .abyssCenser, offhand: .none, back: .tatteredCape,
                      float: .abyssChains, attack: .spellThrow, metal: .iron, skin: .ashen,
                      hairColor: HSB(0.3, 0.2, 0.3), accent: HSB(0.78, 0.6, 0.55), glow: HSB(0.8, 0.65, 1.0),
                      glowingEyes: true),
        // H018 花星のセリア（Assassin）: 花弁の双刃・花冠
        HeroBlueprint(build: .slim, armor: .cloth, pauldron: .none, skirt: .petals, hair: .bob,
                      gear: [.flowerCrown, .crescentPin], weapon: .petalBlade, offhand: .petalBlade, back: .none,
                      float: .petals, attack: .dualSlash, metal: .gold, skin: .fair, hairColor: HSB(0.93, 0.42, 1.0),
                      accent: HSB(0.93, 0.5, 1.0), glow: HSB(0.92, 0.5, 1.0), scale: 0.96),
        // H019 砦砕のブラム（Vanguard）: 攻城槌・角兜
        HeroBlueprint(build: .heavy, armor: .plate, pauldron: .big, skirt: .tassets, hair: .none,
                      gear: [.hornHelm], weapon: .siegeHammer, offhand: .none, back: .none, float: .none,
                      attack: .heavySwing, metal: .iron, skin: .tan, hairColor: HSB(0.05, 0.5, 0.3),
                      accent: HSB(0.07, 0.8, 1.0), glow: HSB(0.08, 0.9, 1.0), scale: 1.12),
        // H020 光矢のユナ（Duelist）: 光の弓・光矢の刃
        HeroBlueprint(build: .standard, armor: .light, pauldron: .small, skirt: .shortSkirt, hair: .twinTails,
                      gear: [.ribbon], weapon: .lightArrowBlade, offhand: .lightBow, back: .none, float: .none,
                      attack: .slash, metal: .gold, skin: .fair, hairColor: HSB(0.13, 0.5, 1.0),
                      accent: HSB(0.13, 0.55, 1.0), glow: HSB(0.13, 0.4, 1.0)),
        // H021 時砂のキロス（Ranger）: 砂時計・長銃・つば広帽
        HeroBlueprint(build: .standard, armor: .leather, pauldron: .small, skirt: .coat, hair: .short,
                      gear: [.wideHat], weapon: .sandRifle, offhand: .none, back: .none, float: .hourglass,
                      attack: .gun, metal: .brass, skin: .tan, hairColor: HSB(0.1, 0.35, 0.75),
                      accent: HSB(0.11, 0.55, 0.92), glow: HSB(0.1, 0.8, 1.0), scarf: true),
        // H022 蒼爪のレア（Arcanist）: 蒼い爪・獣耳
        HeroBlueprint(build: .robed, armor: .cloth, pauldron: .small, skirt: .robe, hair: .wild,
                      gear: [.foxEars], weapon: .azureClaw, offhand: .azureClaw, back: .none, float: .clawCrystals,
                      attack: .dualSlash, metal: .silver, skin: .fair, hairColor: HSB(0.56, 0.22, 1.0),
                      accent: HSB(0.55, 0.8, 1.0), glow: HSB(0.55, 0.7, 1.0)),
        // H023 雷槍のトレン（Support）: 雷の騎槍・翼兜・雷球
        HeroBlueprint(build: .standard, armor: .plate, pauldron: .round, skirt: .kilt, hair: .short,
                      gear: [.wingedHelm], weapon: .thunderLance, offhand: .none, back: .cape, float: .thunderOrb,
                      attack: .thrust, metal: .silver, skin: .tan, hairColor: HSB(0.08, 0.5, 0.3),
                      accent: HSB(0.58, 0.75, 1.0), glow: HSB(0.55, 0.6, 1.0)),
        // H024 夢織のノア（Assassin）: 夢の糸・針の双刃・ナイトキャップ
        HeroBlueprint(build: .slim, armor: .cloth, pauldron: .none, skirt: .kilt, hair: .bob,
                      gear: [.nightcap, .crescentPin], weapon: .dreamNeedle, offhand: .dreamNeedle, back: .none,
                      float: .dreamThreads, attack: .dualSlash, metal: .silver, skin: .fair,
                      hairColor: HSB(0.75, 0.3, 0.95), accent: HSB(0.78, 0.35, 1.0), glow: HSB(0.8, 0.45, 1.0),
                      scale: 0.96),
        // H025 月弦のルミナ（Ranger）: 三日月の長弓・銀白の長髪・翠と白の外套
        HeroBlueprint(build: .slim, armor: .light, pauldron: .small, skirt: .shortSkirt, hair: .long,
                      gear: [.featherPin, .crescentPin], weapon: .none, offhand: .crescentBow, back: .cape, float: .none,
                      attack: .bow, metal: .silver, skin: .fair, hairColor: HSB(0.13, 0.07, 0.98),
                      accent: HSB(0.42, 0.7, 0.72), glow: HSB(0.14, 0.4, 1.0)),
        // H026 紫電のエウリア（Arcanist）: 細身の雷杖・紫の髪と短い外套・周囲に浮く雷球
        HeroBlueprint(build: .robed, armor: .cloth, pauldron: .small, skirt: .robe, hair: .ponytail,
                      gear: [.ribbon], weapon: .stormWand, offhand: .none, back: .cape, float: .sparkOrbs,
                      attack: .staff, metal: .silver, skin: .fair, hairColor: HSB(0.77, 0.6, 0.62),
                      accent: HSB(0.76, 0.7, 0.95), glow: HSB(0.52, 0.5, 1.0)),
        // H027 竜槍のジャルド（Duelist）: 青緑の竜の胸甲と大きな肩当てに金の縁・淡い上衣の長い裾・赤いマント・茶髪の高い結い髪に
        // 青緑の竜の額当て。身の丈の 1.6 倍ほどの竜槍（青緑の竜頭の口から伸びる金の炎の穂先、橙に光る目と芯）。
        // 基調色 = Theme.heroHue（青緑 0.50）、cloth = 淡い上衣、metal = 金（縁・穂先・竜の角）、accent = 赤（マント・髪紐）、glow = 橙。
        HeroBlueprint(build: .standard, armor: .dragon, pauldron: .big, skirt: .longCoat, hair: .ponytail,
                      gear: [.dragonCrest], weapon: .dragonSpear, offhand: .none, back: .cape, float: .none,
                      attack: .thrust, metal: .gold, skin: .fair, hairColor: HSB(0.06, 0.55, 0.3),
                      accent: HSB(0.99, 0.8, 0.75), glow: HSB(0.08, 0.8, 1.0), scale: 1.06),
        // H028 断空のザイル（Assassin）: 光刃の長剣・濃紺の軽装甲・光る visor
        HeroBlueprint(build: .slim, armor: .light, pauldron: .small, skirt: .coat, hair: .spiky,
                      gear: [.glassVisor], weapon: .photonBlade, offhand: .none, back: .none, float: .none,
                      attack: .slash, metal: .obsidian, skin: .pale, hairColor: HSB(0.6, 0.5, 0.2),
                      accent: HSB(0.52, 0.85, 0.95), glow: HSB(0.52, 0.55, 1.0), scale: 0.98),
        // H029 聖槌のボルグ（Support）: 巨大な聖槌と金の大盾・青い板金に金の縁取り・赤いマント・金髪に金の額冠（兜は被らない）。
        // 基調色 = Theme.heroHue（青 0.60）、metal = 金（縁・聖印・槌の打撃面）、accent = 赤（マント）。
        // scale 1.32: overheadHeight = (headTop 1.55 + 0.38) * 1.32 = 2.55（上限 2.7）、頭頂 1.593 * 1.32 = 2.10（上限 2.2）。
        HeroBlueprint(build: .titan, armor: .knight, pauldron: .big, skirt: .tassets, hair: .short,
                      gear: [.circlet], weapon: .holyMaul, offhand: .heaterShield, back: .cape, float: .none,
                      attack: .slash, metal: .gold, skin: .fair, hairColor: HSB(0.13, 0.45, 1.0),
                      accent: HSB(0.99, 0.78, 0.85), glow: HSB(0.13, 0.5, 1.0), scale: 1.32),
        // H030 星砲のライナ（Ranger）: 背丈ほどの星の砲（両手持ち）・桃みがかった金髪のツインテール・白と金の戦闘服
        HeroBlueprint(build: .slim, armor: .light, pauldron: .round, skirt: .shortSkirt, hair: .twinTails,
                      gear: [.starPin, .ribbon], weapon: .starCannon, offhand: .none, back: .gearPack, float: .none,
                      attack: .gun, metal: .gold, skin: .fair, hairColor: HSB(0.05, 0.38, 1.0),
                      accent: HSB(0.99, 0.72, 0.92), glow: HSB(0.93, 0.5, 1.0), scale: 0.98),
        // H031 氷嵐のオーリア（Arcanist）: 背の高い氷の女王。群青の人魚形のドレス（裾は氷の結晶）・銀青の袖と手首の氷・
        // 腰まで流れる白銀の長髪・頭の後ろに立つ氷の光輪の冠・肩から引く半透明の氷のヴェール。杖は持たず、氷華に覆われた右手から放つ。
        // 基調色 = Theme.heroHue（群青 0.645）、cloth = 銀青の袖、metal = 白金（冠の額の輪）、accent = 氷の水色（結晶）、veil = 氷のヴェール。
        HeroBlueprint(build: .robed, armor: .frost, pauldron: .crystal, skirt: .iceGown, hair: .flowing,
                      gear: [.iceCrown], weapon: .none, offhand: .none, back: .mistCloak, float: .iceCrystals,
                      attack: .spellThrow, metal: .platinum, skin: .pale, hairColor: HSB(0.58, 0.06, 1.0),
                      accent: HSB(0.52, 0.55, 1.0), glow: HSB(0.54, 0.45, 1.0), scale: 1.12),
        // H032 赤拳のディアス（Duelist）: 深淵の王子。両手首に金の刃の輪（内縁が紅く光る）・白い髪と金の角・紅く光る目・
        // 薄紫の肌のはだけた胸に紅い光の核・濃い紫の棘の肩甲と上着・紅のズボンと脛の棘の輪・長い黒い尾。小柄。
        // 基調色 = Theme.heroHue（紫 0.71。secondary = 濃い紫の鎧）、metal = 金（刃の輪・角）、accent = 紅（ズボン・襟の裏）、glow = 赤。
        HeroBlueprint(build: .slim, armor: .abyss, pauldron: .spiked, skirt: .none, hair: .wild,
                      gear: [.demonHorns], weapon: .abyssRing, offhand: .abyssRing, back: .demonTail, float: .none,
                      attack: .dualSlash, metal: .gold, skin: .violet, hairColor: HSB(0.72, 0.06, 0.97),
                      accent: HSB(0.97, 0.8, 0.6), glow: HSB(0.99, 0.85, 1.0), scale: 1.0, glowingEyes: true),
        // H033 紅牙のヴァルド（Assassin）: 巨大な血の大剣（両手持ち）・長い黒髪・蝙蝠の翼風のマント・深紅と黒の鎧
        HeroBlueprint(build: .standard, armor: .plate, pauldron: .round, skirt: .coat, hair: .long,
                      gear: [], weapon: .bloodGreatsword, offhand: .none, back: .tatteredCape, float: .none,
                      attack: .heavySwing, metal: .obsidian, skin: .pale, hairColor: HSB(0.75, 0.2, 0.1),
                      accent: HSB(0.99, 0.9, 0.7), glow: HSB(0.98, 0.8, 1.0), scale: 1.04),
        // H034 鎖鉤のゴルム（Support）: 鉤付きの太い鎖・鉄の肩当てと胸当て・背に掛けた鎖・短髪の大男
        HeroBlueprint(build: .heavy, armor: .plate, pauldron: .big, skirt: .loincloth, hair: .short,
                      gear: [], weapon: .hookChain, offhand: .none, back: .chainSash, float: .none,
                      attack: .slash, metal: .iron, skin: .tan, hairColor: HSB(0.07, 0.45, 0.22),
                      accent: HSB(0.03, 0.7, 0.62), glow: HSB(0.05, 0.75, 1.0), scale: 1.12),
    ]

    /// heroID の設計図。未知の ID はロールから近いものを選ぶ。
    static func blueprint(heroID: String, role: Role?) -> HeroBlueprint {
        let n = Int(heroID.dropFirst()) ?? 0
        if n >= 1 && n <= roster.count { return roster[n - 1] }
        switch role {
        case .vanguard?: return roster[0]
        case .duelist?: return roster[1]
        case .ranger?: return roster[2]
        case .arcanist?: return roster[3]
        case .support?: return roster[4]
        case .assassin?: return roster[5]
        case nil: return roster[(max(0, n) % roster.count)]
        }
    }
}
