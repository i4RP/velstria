import Foundation

// 担当: core-world。ワールド系（ミニオン・タワー・中立モンスター・視界・練習用人形）の調整定数。
// 値は docs/DESIGN.md §2–§4・§9 と一致させる。統合フェーズで Balance.swift へ集約してよい。

extension Balance {
    // MARK: ミニオン
    /// 新しい攻撃対象を探す半径。
    public static let minionAcquireRadius: Double = 700
    /// 攻撃対象を維持する半径（これより離れたら解除）。
    public static let minionKeepRadius: Double = 900
    /// レーン中心線からこれ以上離れて追跡しない。
    public static let minionLaneChaseLimit: Double = 900
    /// 攻撃対象なしでレーンからこれ以上離れていれば、まずレーンへ戻る（射程内の敵には反撃する）。
    public static let minionReturnThreshold: Double = 300
    /// 救援要請: 味方ヒーローを攻撃した敵ヒーローを優先する時間窓。
    public static let callForHelpWindow: Double = 2
    /// 救援要請: 攻撃された味方ヒーローがミニオンからこの距離以内なら応じる。
    public static let callForHelpRadius: Double = 1000
    /// 巨像の加護を持つ味方ヒーローからこの距離以内のミニオンが強化される。
    public static let minionEmpowerRadius: Double = 1200
    /// 強化解除の距離（ちらつき防止のヒステリシス）。
    public static let minionEmpowerReleaseRadius: Double = 1400
    /// 強化ミニオンの HP・攻撃倍率。
    public static let minionEmpowerMultiplier: Double = 1.5
    public static let minionSight: Double = 800
    /// 出現位置: Core 中心から最前列までの距離と列の間隔。
    public static let minionSpawnDistance: Double = 700
    public static let minionSpawnSpacing: Double = 55
    /// 側レーン（top・bot）のミニオン移動速度倍率（参照仕様 §3.1: −10%）。中央レーンは 1。
    public static let sideLaneMinionSpeedMultiplier: Double = 0.9

    // MARK: タワー・Core
    public static let towerRange: Double = 750
    public static let coreRange: Double = 800
    public static let towerSight: Double = 1100
    public static let towerRadius: Double = 110
    public static let coreRadius: Double = 250
    /// 「味方ヒーローを攻撃した敵ヒーロー」を最優先にする時間窓。
    public static let towerAggroWindow: Double = 2
    /// タワー 1 発でミニオンの最大 HP を削る割合（近接/遠隔/攻城）。
    public static let towerMeleeMinionDamagePct: Double = 0.45
    public static let towerRangedMinionDamagePct: Double = 0.70
    public static let towerSiegeMinionDamagePct: Double = 0.14
    /// 裏取り保護: この半径内に攻撃側のミニオンが居なければヒーローからのダメージを軽減。
    public static let backdoorMinionRadius: Double = 800
    /// 攻城ミニオンの構造物への与ダメ倍率。
    public static let siegeStructureDamageMultiplier: Double = 1.5

    // MARK: 中立モンスター
    /// ボス（星喰竜・古環の巨像）のリーシュ半径。
    public static let bossLeashRadius: Double = 700
    /// 帰還完了とみなす巣からの距離。
    public static let monsterHomeTolerance: Double = 20
    /// 攻撃者が巣からこれ以上離れていれば反撃せずリセットする（超長射程対策）。
    public static let monsterAggroExtraRange: Double = 800

    // MARK: 視界
    /// 泉は常に自チームへこの半径の視界を与える。
    public static let fountainSight: Double = 1500

    // MARK: 練習用人形
    public static let dummyHP: Double = 3000
    public static let dummyArmor: Double = 30
    public static let dummyRadius: Double = 55
    /// 最後の被ダメからこの秒数で全回復。
    public static let dummyRegenDelay: Double = 4
    /// 撃破後の再出現までの秒数。
    public static let dummyRespawnDelay: Double = 4
    /// 人形の配置: Blue mid 外塔からレーン前方への距離と横方向の間隔。
    public static let dummyForwardDistance: Double = 1000
    public static let dummySpacing: Double = 250
}
