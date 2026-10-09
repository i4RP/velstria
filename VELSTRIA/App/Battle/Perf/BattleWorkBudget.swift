import Foundation

/// Content-independent presentation budgets. Never use these to skip simulation or attack telegraphs.
enum BattleWorkBudget {
    /// Ground footprint padding for tall models, shadows and one frame of camera motion (metres).
    static let unitMargin: Float = 10
    /// Cosmetic cues admitted by one play call (including repeats).
    static let cuesPerPlay = 64
    /// Total delayed cosmetic cues, shared by all heroes in this battle.
    static let pendingCues = 512
}
