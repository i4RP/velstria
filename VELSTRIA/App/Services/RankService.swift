import Foundation
import VelstriaCore

// 担当: app-services（最小実装。昇格/降格・星環王ポイント・ランク報酬を実装すること）

enum RankService {
    static func tierName(_ t: RankTier) -> String {
        switch t {
        case .meteorite: return L("隕鉄", "Meteorite")
        case .silverRing: return L("銀環", "Silver Ring")
        case .goldRing: return L("金環", "Gold Ring")
        case .whiteStar: return L("白星", "White Star")
        case .azureCrystal: return L("蒼晶", "Azure Crystal")
        case .starCrown: return L("星冠", "Star Crown")
        case .starRingSovereign: return L("星環王", "Star Sovereign")
        }
    }

    static func displayName(_ r: RankState) -> String {
        if r.tier == .starRingSovereign { return "\(tierName(r.tier)) \(r.points)pt" }
        let roman = ["I", "II", "III"]
        return "\(tierName(r.tier)) \(roman[max(0, min(2, r.division - 1))])"
    }

    /// ランクに応じた AI 難易度（味方, 敵）。
    static func botDifficulty(for r: RankState) -> (ally: Difficulty, enemy: Difficulty) {
        switch r.tier {
        case .meteorite, .silverRing: return (.normal, .easy)
        case .goldRing, .whiteStar: return (.normal, .normal)
        default: return (.hard, .hard)
        }
    }

    /// 試合結果をランクへ反映。
    static func apply(won: Bool, to r: inout RankState) {
        if won { r.seasonWins += 1 } else { r.seasonLosses += 1 }
    }
}
