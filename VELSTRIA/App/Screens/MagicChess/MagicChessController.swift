import SwiftUI
import VelstriaCore

// 担当: ui（マジックチェス）。MagicChessSim を保持し、人間の操作と戦闘再生を仲介する。
// state は sim からの読み取りスナップショット（変更のたびに sync して @Observable で画面を更新）。

@MainActor
@Observable
final class MagicChessController {
    private let sim: MagicChessSim
    let master: MasterData
    private(set) var state: MagicChessState
    /// 選択中の駒（instanceID）。
    var selected: Int?
    /// 戦闘再生フレーム。
    private(set) var combatFrames: [MCCombatFrame] = []
    var frameIndex: Int = 0

    init(config: MagicChessConfig, master: MasterData = .shared) {
        self.sim = MagicChessSim(config: config, master: master)
        self.master = master
        self.state = sim.state
    }

    private func sync() { state = sim.state }

    var human: MChPlayer? { state.humanPlayer }
    var phase: MagicChessPhase { state.phase }
    var round: Int { state.round }
    var synergies: [SynergyTier] { sim.humanSynergies }
    var boardCapacity: Int { MagicChessData.boardCapacity(round: state.round) }
    var currentFrame: MCCombatFrame? { combatFrames.indices.contains(frameIndex) ? combatFrames[frameIndex] : nil }
    var frameCount: Int { combatFrames.count }

    func isOnBench(_ id: Int) -> Bool { human?.bench.contains { $0.instanceID == id } ?? false }
    func unit(_ id: Int) -> BoardUnit? { human?.allUnits.first { $0.instanceID == id } }

    // 操作（ショップフェーズ）。
    func reroll() { sim.reroll(); sync() }
    func buy(slot: Int) { sim.buy(slot: slot); sync() }
    func sell(_ id: Int) { sim.sell(instanceID: id); if selected == id { selected = nil }; sync() }
    func toBench(_ id: Int) { sim.moveToBench(instanceID: id); sync() }
    func place(_ id: Int, at cell: GridCell) { sim.place(instanceID: id, at: cell); sync() }
    func autoArrange() { sim.autoArrange(); sync() }

    // 戦闘。
    func startCombat() {
        let outcome = sim.advanceToCombat()
        combatFrames = outcome?.frames ?? []
        frameIndex = 0
        sync()
    }

    /// 再生を 1 コマ進める。末尾なら false。
    func advanceFrame() -> Bool {
        guard frameIndex < combatFrames.count - 1 else { return false }
        frameIndex += 1
        return true
    }

    func nextRound() {
        sim.continueToNextRound()
        combatFrames = []
        frameIndex = 0
        selected = nil
        sync()
    }
}
