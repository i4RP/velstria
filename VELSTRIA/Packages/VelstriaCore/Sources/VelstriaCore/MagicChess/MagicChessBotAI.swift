import Foundation

// 担当: core（マジックチェス）。AI プレイヤーのショップ行動（決定論・貪欲）。
// 合成候補（同名所持）を最優先に購入し、盤面を自動整列する。難易度でリロール頻度を変える。

public enum MagicChessBotAI {
    public static func runShopPhase(_ state: inout MagicChessState, playerIndex i: Int, master: MasterData) {
        let difficulty = state.config.aiDifficulty
        if shouldReroll(state.players[i], difficulty: difficulty) {
            MagicChessSim.reroll(&state, playerIndex: i)
        }
        var safety = 0
        while safety < 30 {
            safety += 1
            guard let slot = bestBuy(state.players[i], master: master) else { break }
            let before = state.players[i].gold
            _ = MagicChessSim.buy(&state, playerIndex: i, slot: slot, master: master)
            if state.players[i].gold == before { break }
        }
        MagicChessSim.autoArrange(&state, playerIndex: i, master: master)
    }

    static func shouldReroll(_ p: MChPlayer, difficulty: Difficulty) -> Bool {
        let threshold: Int
        switch difficulty {
        case .hard: threshold = 8
        case .normal: threshold = 12
        case .easy: threshold = 99
        }
        return p.gold >= threshold
    }

    /// 次に買うべきショップ枠（合成候補 → 安い順）。買えないなら nil。
    static func bestBuy(_ p: MChPlayer, master: MasterData) -> Int? {
        let owned = Set(p.allUnits.map(\.heroID))
        var best: ShopUnit?
        for s in p.shop where !s.sold && s.cost <= p.gold {
            guard let current = best else { best = s; continue }
            let currentDup = owned.contains(current.heroID)
            let candidateDup = owned.contains(s.heroID)
            if candidateDup != currentDup {
                if candidateDup { best = s }
                continue
            }
            if s.cost < current.cost { best = s }
        }
        guard let pick = best else { return nil }
        if !p.benchHasSpace() {
            // ベンチ満杯なら合成につながる時だけ。
            let dup = p.allUnits.filter { $0.heroID == pick.heroID && $0.star == 1 }.count
            if dup < 2 { return nil }
        }
        return pick.slot
    }
}
