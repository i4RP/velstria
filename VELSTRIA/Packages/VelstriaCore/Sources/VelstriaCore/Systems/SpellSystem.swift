import Foundation

// 担当: core-skills（Wave 2）。現在はスタブ。

public enum SpellSystem {
    /// バトルスペル発動（DESIGN §7）。成功で true。
    public static func cast(_ s: inout SimState, _ ctx: SimContext, heroIndex i: Int, spellIndex: Int,
                            target: SkillTarget) -> Bool {
        false
    }

    public static func canCast(_ s: SimState, _ ctx: SimContext, heroIndex i: Int, spellIndex: Int) -> Bool {
        guard let h = s.units[i].hero, spellIndex < h.spellCooldowns.count else { return false }
        return h.spellCooldowns[spellIndex] <= 0 && s.units[i].isAlive
    }

    public static func update(_ s: inout SimState, _ ctx: SimContext) {
        for i in s.units.indices where s.units[i].kind == .hero {
            guard let h = s.units[i].hero else { continue }
            for k in h.spellCooldowns.indices where h.spellCooldowns[k] > 0 {
                s.units[i].hero!.spellCooldowns[k] = max(0, h.spellCooldowns[k] - Balance.dt)
            }
        }
    }
}
