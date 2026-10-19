import Foundation

/// Content-independent presentation budgets. Never use these to skip simulation or attack telegraphs.
enum BattleWorkBudget {
    /// Ground footprint padding for tall models, shadows and one frame of camera motion (metres).
    static let unitMargin: Float = 10
    /// Cosmetic cues admitted by one play call (including repeats).
    static let cuesPerPlay = 64
    /// Total delayed cosmetic cues, shared by all heroes in this battle.
    static let pendingCues = 512
    /// Effekseer effects stacked on one skill recipe phase set (FXElement.efk, counted with repeats).
    static let efkCuesPerRecipe = 6
    /// Stacked Effekseer effects that follow a unit or projectile at the same time (all heroes). Extra plays skip the follow.
    static let efkFollows = 32
    /// Effekseer particle instances alive (manager capacity 4000). Stacked effects are skipped above this.
    static let efkInstances = 3000

    /// Decorative prop meshes only. Collision silhouettes and brush fields are never dropped.
    static func stagePropTriangles(_ quality: GraphicsQuality) -> Int {
        switch quality {
        case .low: return 600_000
        case .medium: return 700_000
        case .high: return 800_000
        }
    }
}
