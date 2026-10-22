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
    /// 味方のロードからこの距離以内のミニオンが強化される。
    public static let minionEmpowerRadius: Double = 1200
    /// 強化解除の距離（ちらつき防止のヒステリシス）。
    public static let minionEmpowerReleaseRadius: Double = 1400
    /// 強化ミニオンの HP・攻撃倍率。
    public static let minionEmpowerMultiplier: Double = 1.5
    public static let minionSight: Double = 800
    /// 出現位置: Core 中心から最前列までの距離と列の間隔。MLBB のウェーブは 1 列に約 200 ずつ離れて歩く（2026-10-10 の実機のスクリーンショット）。
    /// 速さと同じく standard の地図で測った値で、ほかの地図ではレーンの長さの比を掛ける（minionLaneScale）。
    public static let minionSpawnDistance: Double = 900
    public static let minionSpawnSpacing: Double = 200
    /// ミニオンの移動速度（standard の中央レーン。種類によらず同じで、ウェーブがまとまって進む）。
    /// MLBB Wiki の「出てから中央レーンは約 15 秒、側レーンは約 25 秒で着く」は、両軍のウェーブが出会うレーンの中点までの時間。
    /// 実機のミニマップ（0:23・0:27・0:32 のミニオンの点）で側レーンは毎秒 約 390 進み、0:32〜0:33 に左上・右下の角で出会った。
    /// 中央 405（ウェーブの中心が中点に着くまで 15 秒、最前列どうしが出会うのは 0:25）、側は ×0.957 ≈ 388（同 23 秒、最前列どうしは 0:33）。
    public static let minionMoveSpeed: Double = 405
    /// 側レーン（top・bot）のミニオン移動速度倍率（MLBB は 1.5.16 で側レーン −10%、1.5.38 で中央 −6% → 0.9 / 0.94）。
    public static let sideLaneMinionSpeedMultiplier: Double = 0.957
    /// 移動速度の伸び: 12:00 から毎分 +30、上限 +120（MLBB の値にヒーローと同じ Balance.mapScale を掛ける）。
    /// MLBB は 1.5.24 で 9 分から毎分 +15・上限 +120、1.5.44 で毎分 +30、1.6.42 で 9 分 → 12 分。
    public static let minionSpeedGrowthStart: Double = 12 * 60
    public static let minionSpeedGrowthPerMinute: Double = 30 * mapScale
    public static let minionSpeedGrowthMax: Double = 120 * mapScale
    /// 精鋭兵（スーパーミニオン。相手のベースタワーが壊れたレーンに、以後のウェーブが強化されて出る。MLBB の Call of Raging）。
    /// 能力値は資料に無いので仮の値: HP・攻撃 ×1.6、物防・魔防 +30、半径 ×1.2（docs/TOWER_BASE_MLBB.md）。
    public static let superMinionHPMultiplier: Double = 1.6
    public static let superMinionAttackMultiplier: Double = 1.6
    public static let superMinionDefenseBonus: Double = 30
    public static let superMinionRadiusMultiplier: Double = 1.2

    // MARK: タワー・Core（MLBB の数値・規則は Balance.Tower）
    /// 射程 5.3・視界 8（MLBB × 100。MLBB の Fandom は塔とベースで同じ射程）。届く距離は射程 + 双方の半径（ヒーローと同じ）。
    public static let towerRange: Double = 530
    public static let coreRange: Double = 530
    public static let towerSight: Double = 800
    public static let towerRadius: Double = 110
    public static let coreRadius: Double = 250
    /// 「味方ヒーローを攻撃した敵ヒーロー」に切り替える時間窓。
    public static let towerAggroWindow: Double = 2
    /// 「味方ヒーローを攻撃した」と見る味方の範囲（塔の射程より少し外まで。MLBB の Fandom「射程より少し遠く」。量は資料に無い）。
    public static let towerAggroAllyMargin: Double = 150
    /// タワー 1 発でミニオンの最大 HP を削る割合（近接/遠隔/攻城）。MLBB の値は資料に無いので Velstria の旧来の値。
    public static let towerMeleeMinionDamagePct: Double = 0.45
    public static let towerRangedMinionDamagePct: Double = 0.70
    public static let towerSiegeMinionDamagePct: Double = 0.14
    /// 攻城ミニオンの構造物への与ダメ倍率（MLBB の値は資料に無いので旧来の値）。
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
