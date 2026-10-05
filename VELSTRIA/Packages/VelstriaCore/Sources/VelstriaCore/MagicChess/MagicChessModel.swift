import Foundation

// 担当: core（マジックチェス）。簡易オートバトラーのデータモデルと調整定数。
// 決定論: RNG は MagicChessState.rng（SplitMix64）のみ。Date() / Set・Dictionary の列挙順に依存しない。
// 戦闘数値は既存のヒーロー成長（HeroGrowth.baseStats）と軽減式（CombatSystem.mitigationMultiplier）を流用する。

public enum MagicChessPhase: Int, Codable, Sendable {
    case shop       // 購入・配置
    case combat     // 自動戦闘
    case aftermath  // HP 精算・脱落
    case gameOver   // 勝者確定
}

/// 盤面のマス（プレイヤー自陣）。row 0 が前列（敵に近い）。
public struct GridCell: Codable, Hashable, Sendable {
    public var col: Int
    public var row: Int
    public init(col: Int, row: Int) { self.col = col; self.row = row }
}

/// 駒（ベンチまたは盤上）。
public struct BoardUnit: Codable, Hashable, Sendable, Identifiable {
    public var instanceID: Int
    public var heroID: String
    public var star: Int
    /// nil = ベンチ。
    public var cell: GridCell?
    public var id: Int { instanceID }

    public init(instanceID: Int, heroID: String, star: Int = 1, cell: GridCell? = nil) {
        self.instanceID = instanceID
        self.heroID = heroID
        self.star = star
        self.cell = cell
    }

    public var onBoard: Bool { cell != nil }
}

/// ショップ 1 枠。
public struct ShopUnit: Codable, Hashable, Sendable, Identifiable {
    public var slot: Int
    public var heroID: String
    public var cost: Int
    public var sold: Bool
    public var id: Int { slot }

    public init(slot: Int, heroID: String, cost: Int, sold: Bool = false) {
        self.slot = slot
        self.heroID = heroID
        self.cost = cost
        self.sold = sold
    }
}

/// シナジー（ロール別の発動段階）。
public struct SynergyTier: Codable, Hashable, Sendable, Identifiable {
    public var role: Role
    /// 盤上のユニーク heroID 数。
    public var count: Int
    /// 0 = 未発動、1 = 第1閾値、2 = 第2閾値。
    public var tier: Int
    public var id: String { role.rawValue }

    public init(role: Role, count: Int, tier: Int) {
        self.role = role
        self.count = count
        self.tier = tier
    }
}

/// 今ラウンドの対戦組。
public struct MCPairing: Codable, Hashable, Sendable {
    public var a: Int
    public var b: Int
    /// true なら b は a のゴースト相手（人数が奇数のとき。b は HP を失わない）。
    public var ghost: Bool
    public init(a: Int, b: Int, ghost: Bool = false) { self.a = a; self.b = b; self.ghost = ghost }
    public func contains(_ id: Int) -> Bool { a == id || (b == id && !ghost) }
}

/// 1 戦闘の結果。
public struct CombatResult: Codable, Hashable, Sendable {
    /// 勝者のプレイヤー id（nil = 引き分け）。
    public var winner: Int?
    /// 勝者側の生存ユニット数。
    public var survivors: Int
    /// 勝者側の生存ユニットの星合計（HP 精算に使う）。
    public var survivingStars: Int

    public init(winner: Int?, survivors: Int, survivingStars: Int) {
        self.winner = winner
        self.survivors = survivors
        self.survivingStars = survivingStars
    }
}

public struct MagicChessConfig: Codable, Hashable, Sendable {
    /// マジックチェス独自の版数（MatchConfig とは別）。
    public static let currentSimVersion = 1
    public var simVersion: Int
    public var seed: UInt64
    public var participantCount: Int
    public var humanName: String
    public var aiDifficulty: Difficulty

    public init(seed: UInt64, humanName: String, aiDifficulty: Difficulty = .normal,
                participantCount: Int = MagicChessData.participantCount) {
        self.simVersion = MagicChessConfig.currentSimVersion
        self.seed = seed
        self.humanName = humanName
        self.aiDifficulty = aiDifficulty
        self.participantCount = participantCount
    }
}

// MARK: - 調整定数

public enum MagicChessData {
    public static let participantCount = 8
    public static let boardCols = 6
    public static let boardRows = 3
    public static let benchSize = 8
    public static let shopSize = 5

    public static let startingGold = 4
    public static let baseIncome = 5
    public static let rerollCost = 2
    public static let startingHP = 100
    public static let maxStar = 3
    public static let copiesToCombine = 3
    /// 盤上に置ける最大数の上限。
    public static let maxBoardUnits = 7

    /// ラウンドごとの盤面容量（round は 1 始まり）。
    public static func boardCapacity(round: Int) -> Int {
        min(maxBoardUnits, 1 + round)
    }

    /// 敗北時の基本 HP 減少（+ 生存敵ユニットの星合計）。
    public static let baseRoundDamage = 3

    /// ヒーローのコスト（1〜3）。difficulty から素朴に段階化する。
    public static func unitCost(_ def: HeroDef) -> Int {
        1 + min(2, max(0, (def.difficulty - 1) / 3))
    }

    /// 星 → 参照レベル（既存の成長曲線を流用）。
    public static func level(forStar star: Int) -> Int {
        switch max(1, min(maxStar, star)) {
        case 1: return 3
        case 2: return 6
        default: return 9
        }
    }

    /// 星 → HP・攻撃の倍率（合成の価値を出す）。
    public static func starPower(_ star: Int) -> Double {
        switch max(1, min(maxStar, star)) {
        case 1: return 1.0
        case 2: return 1.8
        default: return 3.2
        }
    }

    /// 売却価格（星が上がった駒は購入額以上の価値があるため star でスケール）。
    public static func sellValue(_ unit: BoardUnit, cost: Int) -> Int {
        max(1, cost * unit.star)
    }
}
