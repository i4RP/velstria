import Foundation

// 担当: core（マジックチェス）。メタループ（ショップ→戦闘→精算→次ラウンド）。
// 値型の state を保持し、UI/テストが呼ぶ操作を提供する。すべて state.rng で決定論。

public final class MagicChessSim {
    public private(set) var state: MagicChessState
    public let master: MasterData
    /// 直近戦闘の人間側アウトカム（レンダリング用）。
    public private(set) var lastHumanOutcome: MCCombatOutcome?

    public var humanIndex: Int { state.index(of: 0) ?? 0 }

    public init(config: MagicChessConfig, master: MasterData = .shared) {
        self.master = master
        var players: [MChPlayer] = []
        for i in 0..<config.participantCount {
            let human = i == 0
            let name = human ? config.humanName : "CPU \(i)"
            players.append(MChPlayer(id: i, isHuman: human, displayName: name,
                                     gold: MagicChessData.startingGold, hp: MagicChessData.startingHP))
        }
        self.state = MagicChessState(config: config, players: players)
        startShopPhase()
    }

    // MARK: - フェーズ進行

    /// ショップフェーズを始める（収入・ショップ更新・AI 行動）。
    public func startShopPhase() {
        state.round += 1
        for i in state.players.indices where state.players[i].alive {
            state.players[i].gold += MagicChessData.baseIncome
            state.players[i].lastDamageTaken = 0
            Self.refillShop(&state, playerIndex: i)
        }
        // AI の行動（プレイヤー添字昇順で決定論）。
        for i in state.players.indices where state.players[i].alive && !state.players[i].isHuman {
            MagicChessBotAI.runShopPhase(&state, playerIndex: i, master: master)
        }
        state.phase = .shop
    }

    /// 戦闘へ進む。全組を解決し HP を精算、脱落・勝者を確定する。人間側のアウトカムを返す。
    @discardableResult
    public func advanceToCombat() -> MCCombatOutcome? {
        state.phase = .combat
        let pairings = Self.makePairings(&state)
        state.pairings = pairings
        lastHumanOutcome = nil
        let humanID = state.humanPlayer?.id

        for pairing in pairings {
            guard let ia = state.index(of: pairing.a), let ib = state.index(of: pairing.b) else { continue }
            let boardA = state.players[ia].board
            let boardB = state.players[ib].board
            let fightSeed = Self.combatSeed(state.config.seed, round: state.round, a: pairing.a, b: pairing.b)
            let involvesHuman = pairing.a == humanID || (pairing.b == humanID && !pairing.ghost)
            let result: CombatResult
            if involvesHuman {
                let outcome = AutoCombatResolver.fight(boardA: boardA, boardB: boardB, aID: pairing.a, bID: pairing.b,
                                                       seed: fightSeed, master: master)
                lastHumanOutcome = outcome
                result = outcome.result
            } else {
                result = AutoCombatResolver.resolve(boardA: boardA, boardB: boardB, aID: pairing.a, bID: pairing.b,
                                                    seed: fightSeed, master: master)
            }
            applyResult(result, pairing: pairing)
        }
        resolveEliminations()
        if state.aliveCount <= 1 {
            if let w = state.players.first(where: { $0.alive }) {
                if let i = state.index(of: w.id) { state.players[i].placement = 1 }
                state.winner = w.id
            }
            state.phase = .gameOver
        } else {
            state.phase = .aftermath
        }
        return lastHumanOutcome
    }

    /// 次ラウンドへ（ゲーム終了済みなら何もしない）。
    public func continueToNextRound() {
        guard state.phase != .gameOver else { return }
        startShopPhase()
    }

    // MARK: - 精算

    private func applyResult(_ result: CombatResult, pairing: MCPairing) {
        let base = MagicChessData.baseRoundDamage
        if let winner = result.winner {
            let loserID = winner == pairing.a ? pairing.b : pairing.a
            // ゴースト相手（b）は HP を失わない。
            if pairing.ghost, loserID == pairing.b { return }
            let dmg = base + result.survivingStars
            if let li = state.index(of: loserID) { damage(&state.players[li], dmg) }
        } else {
            // 引き分け: 両者が基本ダメージ（ゴースト相手は除く）。
            if let ia = state.index(of: pairing.a) { damage(&state.players[ia], base) }
            if !pairing.ghost, let ib = state.index(of: pairing.b) { damage(&state.players[ib], base) }
        }
    }

    private func damage(_ player: inout MChPlayer, _ amount: Int) {
        guard player.alive, amount > 0 else { return }
        player.hp -= amount
        player.lastDamageTaken += amount
    }

    private func resolveEliminations() {
        // HP 昇順（最も削られた順）に脱落させる。同 HP は id 昇順。最後の 1 人は必ず残す（勝者確定のため）。
        var dying = state.players.filter { $0.alive && $0.hp <= 0 }
        guard !dying.isEmpty else { return }
        dying.sort { $0.hp != $1.hp ? $0.hp < $1.hp : $0.id < $1.id }
        var remaining = state.aliveCount
        for p in dying {
            if remaining <= 1 { break }   // 全員同時に 0 以下でも 1 人は生存＝勝者
            guard let i = state.index(of: p.id) else { continue }
            state.players[i].alive = false
            state.players[i].placement = remaining   // 今生きている人数 = この脱落の順位
            remaining -= 1
        }
    }

    // MARK: - 人間の操作（ショップフェーズのみ有効）

    public func reroll() { guard state.phase == .shop else { return }; Self.reroll(&state, playerIndex: humanIndex) }
    public func buy(slot: Int) { guard state.phase == .shop else { return }; Self.buy(&state, playerIndex: humanIndex, slot: slot, master: master) }
    public func sell(instanceID: Int) { guard state.phase == .shop else { return }; Self.sell(&state, playerIndex: humanIndex, instanceID: instanceID, master: master) }
    public func place(instanceID: Int, at cell: GridCell) { guard state.phase == .shop else { return }; Self.place(&state, playerIndex: humanIndex, instanceID: instanceID, at: cell) }
    public func moveToBench(instanceID: Int) { guard state.phase == .shop else { return }; Self.moveToBench(&state, playerIndex: humanIndex, instanceID: instanceID) }
    public func autoArrange() { guard state.phase == .shop else { return }; Self.autoArrange(&state, playerIndex: humanIndex, master: master) }

    public var humanSynergies: [SynergyTier] {
        MagicChessSynergy.tiers(board: state.humanPlayer?.board ?? [], master: master)
    }

    // MARK: - 静的ヘルパー（state を直接操作。Bot からも使う）

    static func combatSeed(_ seed: UInt64, round: Int, a: Int, b: Int) -> UInt64 {
        var mix = seed ^ 0xA24B_AED4_963E_E407
        mix = (mix &+ UInt64(round &* 0x9E37)) &* 0xBF58_476D_1CE4_E5B9
        mix = (mix ^ UInt64(min(a, b) &* 0x2545)) &* 0x94D0_49BB_1331_11EB
        mix = mix ^ UInt64(max(a, b) &* 0x27D4) ^ (mix >> 31)
        return mix
    }

    /// 生存プレイヤーをシャッフルして組を作る。奇数なら 1 人がゴースト戦。
    static func makePairings(_ state: inout MagicChessState) -> [MCPairing] {
        var alive = state.players.filter { $0.alive }.map(\.id).sorted()
        // フィッシャー–イェーツ（state.rng）。
        if alive.count > 1 {
            for i in stride(from: alive.count - 1, to: 0, by: -1) {
                let j = state.rng.nextInt(in: 0...i)
                alive.swapAt(i, j)
            }
        }
        var pairings: [MCPairing] = []
        var k = 0
        while k + 1 < alive.count {
            pairings.append(MCPairing(a: alive[k], b: alive[k + 1]))
            k += 2
        }
        if k < alive.count {
            // 余り 1 人 → 他の生存者のゴースト戦。
            let leftover = alive[k]
            let others = alive.filter { $0 != leftover }
            if let ghost = state.rng.pick(others) {
                pairings.append(MCPairing(a: leftover, b: ghost, ghost: true))
            }
        }
        return pairings
    }

    static func refillShop(_ state: inout MagicChessState, playerIndex i: Int) {
        var shop: [ShopUnit] = []
        let heroes = MasterData.shared.heroes
        for slot in 0..<MagicChessData.shopSize {
            guard let def = state.rng.pick(heroes) else { continue }
            shop.append(ShopUnit(slot: slot, heroID: def.heroID, cost: MagicChessData.unitCost(def)))
        }
        state.players[i].shop = shop
    }

    static func reroll(_ state: inout MagicChessState, playerIndex i: Int) {
        guard state.players[i].gold >= MagicChessData.rerollCost else { return }
        state.players[i].gold -= MagicChessData.rerollCost
        refillShop(&state, playerIndex: i)
    }

    @discardableResult
    static func buy(_ state: inout MagicChessState, playerIndex i: Int, slot: Int, master: MasterData) -> Bool {
        guard let si = state.players[i].shop.firstIndex(where: { $0.slot == slot }) else { return false }
        let shopUnit = state.players[i].shop[si]
        guard !shopUnit.sold, state.players[i].gold >= shopUnit.cost else { return false }
        // ベンチが満杯でも、合成につながる（同名 heroID を 2 つ以上所持）なら購入を許可。
        let dupCount = state.players[i].allUnits.filter { $0.heroID == shopUnit.heroID && $0.star == 1 }.count
        guard state.players[i].benchHasSpace() || dupCount >= 2 else { return false }
        state.players[i].gold -= shopUnit.cost
        state.players[i].shop[si].sold = true
        let unit = BoardUnit(instanceID: state.nextInstanceID, heroID: shopUnit.heroID, star: 1, cell: nil)
        state.nextInstanceID += 1
        state.players[i].bench.append(unit)
        combine(&state, playerIndex: i)
        return true
    }

    static func sell(_ state: inout MagicChessState, playerIndex i: Int, instanceID: Int, master: MasterData) {
        guard let unit = state.players[i].allUnits.first(where: { $0.instanceID == instanceID }),
              let def = master.hero(unit.heroID) else { return }
        state.players[i].board.removeAll { $0.instanceID == instanceID }
        state.players[i].bench.removeAll { $0.instanceID == instanceID }
        state.players[i].gold += MagicChessData.sellValue(unit, cost: MagicChessData.unitCost(def))
    }

    /// 駒を盤面セルへ（ベンチ↔盤・盤内移動）。占有セルとは入れ替え。容量超過は拒否。
    static func place(_ state: inout MagicChessState, playerIndex i: Int, instanceID: Int, at cell: GridCell) {
        guard cell.col >= 0, cell.col < MagicChessData.boardCols, cell.row >= 0, cell.row < MagicChessData.boardRows
        else { return }
        let fromBench = state.players[i].bench.contains { $0.instanceID == instanceID }
        // 対象セルの占有者。
        let occupantID = state.players[i].board.first { $0.cell == cell }?.instanceID
        if fromBench {
            // ベンチ → 盤。空セルなら容量チェック、占有セルなら占有者をベンチへ。
            if occupantID == nil, state.players[i].boardCount >= MagicChessData.boardCapacity(round: state.round) {
                return
            }
            if let occupantID, let oi = state.players[i].board.firstIndex(where: { $0.instanceID == occupantID }) {
                state.players[i].board[oi].cell = nil
                state.players[i].bench.append(state.players[i].board[oi])
                state.players[i].board.remove(at: oi)
            }
            guard let bi = state.players[i].bench.firstIndex(where: { $0.instanceID == instanceID }) else { return }
            var moved = state.players[i].bench.remove(at: bi)
            moved.cell = cell
            state.players[i].board.append(moved)
        } else {
            // 盤内移動。占有者と座標を入れ替え。
            guard let mi = state.players[i].board.firstIndex(where: { $0.instanceID == instanceID }) else { return }
            let oldCell = state.players[i].board[mi].cell
            if let occupantID, occupantID != instanceID,
               let oi = state.players[i].board.firstIndex(where: { $0.instanceID == occupantID }) {
                state.players[i].board[oi].cell = oldCell
            }
            state.players[i].board[mi].cell = cell
        }
    }

    static func moveToBench(_ state: inout MagicChessState, playerIndex i: Int, instanceID: Int) {
        guard let bi = state.players[i].board.firstIndex(where: { $0.instanceID == instanceID }),
              state.players[i].benchHasSpace() else { return }
        var unit = state.players[i].board.remove(at: bi)
        unit.cell = nil
        state.players[i].bench.append(unit)
    }

    /// 同名・同星が 3 つ揃ったら 1 つ上の星へ合成する（連鎖あり）。盤上の駒があれば盤に残す。
    static func combine(_ state: inout MagicChessState, playerIndex i: Int) {
        var changed = true
        while changed {
            changed = false
            // heroID+star でグループ化。
            var groups: [String: [BoardUnit]] = [:]
            for u in state.players[i].allUnits where u.star < MagicChessData.maxStar {
                groups["\(u.heroID)#\(u.star)", default: []].append(u)
            }
            for (_, units) in groups.sorted(by: { $0.key < $1.key }) where units.count >= MagicChessData.copiesToCombine {
                let trio = Array(units.prefix(MagicChessData.copiesToCombine))
                let keepCell = trio.compactMap { $0.cell }.first
                let ids = Set(trio.map(\.instanceID))
                state.players[i].board.removeAll { ids.contains($0.instanceID) }
                state.players[i].bench.removeAll { ids.contains($0.instanceID) }
                var upgraded = BoardUnit(instanceID: state.nextInstanceID, heroID: trio[0].heroID,
                                         star: trio[0].star + 1, cell: keepCell)
                state.nextInstanceID += 1
                if keepCell != nil {
                    state.players[i].board.append(upgraded)
                } else {
                    upgraded.cell = nil
                    state.players[i].bench.append(upgraded)
                }
                changed = true
                break
            }
        }
    }

    /// 盤面を容量まで自動整列（Bot・クイック配置用）。前列=近接・後列=遠隔。
    static func autoArrange(_ state: inout MagicChessState, playerIndex i: Int, master: MasterData) {
        let capacity = MagicChessData.boardCapacity(round: state.round)
        // 強い順（星→コスト）に並べ、容量分を盤へ、残りをベンチへ。
        var all = state.players[i].allUnits
        all.sort { lhs, rhs in
            if lhs.star != rhs.star { return lhs.star > rhs.star }
            let lc = master.hero(lhs.heroID).map { MagicChessData.unitCost($0) } ?? 1
            let rc = master.hero(rhs.heroID).map { MagicChessData.unitCost($0) } ?? 1
            if lc != rc { return lc > rc }
            return lhs.instanceID < rhs.instanceID
        }
        let starters = Array(all.prefix(capacity))
        let benched = Array(all.dropFirst(capacity))
        var board: [BoardUnit] = []
        var frontCol = 0, backCol = 0
        for u in starters {
            var unit = u
            let ranged = master.hero(u.heroID)?.isRanged ?? false
            let row = ranged ? MagicChessData.boardRows - 1 : 0
            let col = ranged ? backCol : frontCol
            unit.cell = GridCell(col: min(col, MagicChessData.boardCols - 1), row: row)
            if ranged { backCol += 1 } else { frontCol += 1 }
            board.append(unit)
        }
        state.players[i].board = board
        state.players[i].bench = benched.map { var u = $0; u.cell = nil; return u }
    }

    // MARK: - テスト用

    /// 全プレイヤーを Bot で動かして最後まで進める（決定論の検証用）。
    public func runHeadless(maxRounds: Int = 100) {
        var guardRounds = 0
        while state.phase != .gameOver && guardRounds < maxRounds {
            // 人間も Bot で動かす。
            if let hi = state.index(of: 0), state.players[hi].alive {
                MagicChessBotAI.runShopPhase(&state, playerIndex: hi, master: master)
            }
            advanceToCombat()
            if state.phase == .gameOver { break }
            continueToNextRound()
            guardRounds += 1
        }
    }
}
