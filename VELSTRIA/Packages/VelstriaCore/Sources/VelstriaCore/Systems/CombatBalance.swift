import Foundation

// 担当: core-combat
// 戦闘系の追加定数（統合フェーズで Balance.swift へ集約する）と StatusKind の分類。
// 他担当の extension と衝突しないよう、名前は combat 接頭辞で統一する。

extension Balance {
    // MARK: 通常攻撃
    /// 攻撃ボタンの索敵距離 = 射程 + 自身の半径 + この値（+ 対象半径）。
    public static let combatTargetSearchBonus: Double = 300
    /// 攻撃ボタンの追撃: 敵ヒーローを狙ってから、射程内により優先度の高い敵ヒーローがいない限り同じ対象を追う時間（秒）。
    public static let attackStickyWindow: Double = 2.0
    /// 追撃を続ける距離 = 射程 + 自身の半径 + 対象の半径 + この値。これより離れたら追撃をやめる。
    public static let attackStickyChaseExtra: Double = 1200
    /// 遠隔ミニオンの通常攻撃弾速。
    public static let combatMinionProjectileSpeed: Double = 1100
    /// タワー / Core の通常攻撃弾速。
    public static let combatStructureProjectileSpeed: Double = 1400
    /// 前隙中に対象が射程外へ出たとみなすまでの猶予距離（射程バッファ）。
    /// 前隙（Lv1 近接で約 0.29 秒）の間に移動速度 ~270 の対象は ~80 動くため、歩いて逃げるだけでは
    /// 取り消されず、突進・ブリンクなどで大きく離れた場合だけ取り消される値にする。
    public static let combatWindupRangeLeeway: Double = 150
    /// 追跡は射程よりこの分だけ内側で止まる（射程境界での往復を防ぐ）。
    public static let combatFollowRangeMargin: Double = 10
    /// 追尾弾の最大飛行距離（安全装置）。
    public static let combatHomingMaxTravel: Double = 6000

    // MARK: 状態効果
    /// 燃焼ダメージの刻み（秒）。合計は magnitude × 持続時間で一定。
    public static let combatBurnTickInterval: Double = 0.5
    /// 持続時間 0 以下で渡されたシールドの既定持続。
    public static let combatDefaultShieldDuration: Double = 3
    /// 紅焔バフ: 通常攻撃で 3 秒間に 30 + 8×Lv の確定ダメージ + 10% スロー 1 秒。
    public static let combatRedBuffBurnBase: Double = 30
    public static let combatRedBuffBurnPerLevel: Double = 8
    public static let combatRedBuffBurnDuration: Double = 3
    public static let combatRedBuffSlowPct: Double = 0.10
    public static let combatRedBuffSlowDuration: Double = 1.0
    /// 蒼晶バフ: CD 短縮 +15%、リソース回復 +5/s。
    public static let combatBlueBuffCooldownReduction: Double = 0.15
    public static let combatBlueBuffResourceRegen: Double = 5
    /// 竜の加護 / 巨像の加護の与ダメ補正。
    public static let combatWyrmBlessingDamageBonus: Double = 0.10
    public static let combatColossusBlessingDamageBonus: Double = 0.15

    // MARK: 移動
    /// 経路の目標がこれ以上ずれたら再計算する。
    public static let combatRepathDistance: Double = 50
    /// 歩行不能な目標（Core・壁の中の地点）へ向かう経路は、終点がこの距離以内なら作り直さない。
    public static let combatUnwalkableGoalTolerance: Double = 400
    /// 地点移動の到着判定距離。
    public static let combatArrivalDistance: Double = 4
    /// 1 tick の移動量が歩幅のこの割合未満なら「詰まり」とみなす。
    public static let combatStuckRatio: Double = 0.25
    /// 詰まり時の経路再計算は (tick + id) がこの倍数の tick のみ（A* の多発を防ぐ）。
    public static let combatStuckRepathEveryTicks = 10
    /// ミニオン同士の押し合い: 目標間隔 = 半径和 × この値。
    public static let combatMinionSeparationRatio: Double = 0.9
    /// 1 tick で解消する重なりの割合。
    public static let combatMinionSeparationStiffness: Double = 0.5
    /// 押し合いによる 1 tick の最大移動量。
    public static let combatMinionSeparationMaxPush: Double = 8
}

extension StatusKind {
    /// CC 無効・構造物で防がれる行動阻害。
    var combatIsCrowdControl: Bool {
        switch self {
        case .stun, .root, .slow, .airborne, .silence: return true
        default: return false
        }
    }

    /// 弱体（敵ヒーローからの付与はアシスト対象、構造物・無敵には付与しない）。
    /// suppress は CC 無効を無視する（combatIsCrowdControl に含めない）。mark は弱体にも強化にも数えない。
    var combatIsHarmful: Bool { isCleansable || self == .airborne || self == .armorShred || self == .magicShred || self == .suppress }

    /// 強化（HitPayload.statuses のうち味方へ付与するもの）。
    var combatIsBeneficial: Bool {
        switch self {
        case .speedBoost, .attackSpeedBoost, .damageBoost, .damageReduction, .ccImmune, .invulnerable, .stealth,
             .blueBuff, .redBuff, .wyrmBlessing, .colossusBlessing,
             .lifestealBoost, .spellVampBoost, .attackRangeBoost, .untargetable, .channeling:
            return true
        default:
            return false
        }
    }
}
