import Foundation

// 担当: core-skills（キット層。docs/SKILL_KITS.md）
// ヒーロー固有スキルの上書き層。状態を持たない値型で、動的な状態はすべて HeroData.kit・status・zone・projectile に置く。
// すべてのメソッドに既定実装がある（キットは上書きしたいものだけ実装する）。isReady == false のキットは存在しないのと同じ。

/// スキル説明の `{x0}..{x3}` に入る、キット固有の数値（順序付き）。
public struct KitStat: Codable, Hashable, Sendable {
    public var key: String
    public var value: Double

    public init(key: String, value: Double) {
        self.key = key
        self.value = value
    }
}

/// キットのスキル発動に渡す文脈（初回も再使用も同じ形）。
struct KitCast {
    var caster: Int
    var slot: SkillSlot
    /// 0 = 通常の発動、1 以上 = 再使用の段。
    var stage: Int
    var check: SkillCastCheck
    var targeting: SkillTargeting
    var numbers: SkillNumbers
    var aim: SkillAim
}

/// `HeroKit.cast` の結果。
enum KitCastOutcome {
    /// キットが全部処理した。
    case done
    /// 汎用の実行（SkillArchetypes.execute）に委ねる。nil は既定の照準情報・数値を使う。
    case generic(SkillTargeting?, SkillNumbers?)
}

/// `HeroKit.botCast` の結果。
enum BotKitDecision {
    case useDefault
    /// この対象で撃つ。ただし奥義の汎用の関門（倒せる / 2 体以上を巻き込む）は通る。
    case cast(SkillTarget)
    /// 汎用の関門を飛び越えて、この対象で今撃つ（関門の外で奥義を使いたいキット用。再使用の段は常に関門なし）。
    case castNow(SkillTarget)
    case skip
}

protocol HeroKit: Sendable {
    var heroID: String { get }
    /// false の間はレジストリに存在しないのと同じ（スタブ）。
    var isReady: Bool { get }

    // MARK: A. 記述（HUD・AI・ツールチップ）

    /// base は汎用の結果。stage 0 = 通常、1 以上 = 再使用の段。
    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting
    /// ダメージは base.damage の比で表し TTK を保つ。
    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers
    func text(slot: SkillSlot) -> KitText?
    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge?
    /// ランクごとのコスト（発動の検証・消費・numbers の cost・ボット・HUD が同じ値を使う）。base は汎用の実効コスト
    /// （リソースが Energy なら energyCostMultiplier 込み）。キットが固定の値を返すときは `HeroKits.resourceCost` を通す。
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double

    // MARK: B. 実行

    /// nil = 既定の照準、`.some(nil)` = 発動を拒否。
    func resolveAim(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot, stage: Int,
                    targeting: SkillTargeting, target: SkillTarget) -> SkillAim??
    /// 追加の発動条件（初回のみ。再使用では呼ばれない）。HUD の可否判定にも使われるので状態だけで決める。
    func canStart(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) -> Bool
    /// 初回の発動（コスト・CD は消費済み）。
    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome
    /// 再使用（窓が開いている間の同じ `castSkill`。CD・コストは消費しない）。窓を進める/閉じるのはキット側（`Kit.advanceRecast`）。
    func recast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast, window: RecastWindow)
    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer)
    func onWindowClosed(_ s: inout SimState, _ ctx: SimContext, owner: Int, slot: SkillSlot, expired: Bool)
    /// HitPayload.kitEvent が 0 以外の命中（ダメージ適用後）。
    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double)
    /// 毎 tick（SkillSystem.update から。タイマー・窓・突進の処理の後）。
    func update(_ s: inout SimState, _ ctx: SimContext, owner: Int)
    /// ハード CC でタイマー/突進が取り消されたとき。
    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int)
    /// 死亡で全リセットされた後の状態に、残したいものを `fresh` へ書き戻す。
    func onDeath(old: KitState, into fresh: inout KitState)

    // MARK: C. パッシブ（キットのヒーローはロールのパッシブを置き換える）

    func outgoingDamageBonus(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                             source: DamageSource) -> Double
    /// 被ダメ（防御・軽減の後、シールドの前）の量を返す。
    func modifyIncomingDamage(_ s: inout SimState, _ ctx: SimContext, victim: Int, attacker: Int?,
                              source: DamageSource, amount: Double) -> Double
    func forceCrit(_ s: inout SimState, _ ctx: SimContext, attacker: Int) -> Bool?
    func shapeBasicAttack(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                          plan: inout BasicAttackPlan)
    func onBasicAttackHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, damage: Double)
    func onSkillHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, slot: SkillSlot,
                    damage: Double)
    func onSkillCast(_ s: inout SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot)
    func onDamageTaken(_ s: inout SimState, _ ctx: SimContext, victim: Int, attacker: Int?, amount: Double)
    func onKillOrAssist(_ s: inout SimState, _ ctx: SimContext, hero: Int, victim: Int)

    // MARK: D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision
    /// ミニオン・モンスターの集団に対し、突入・瞬間移動系（dashStrike / leapSlam / targetedBlink / blinkEmpower /
    /// multiStrike）のスキルを撃ってよいか。center = 集団の中心、count = 巻き込む数。既定 false（撃たない）。
    /// 敵タワーの射程や自身の HP など、安全の判断はキット側で行う。
    func botFarm(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 center: Vec2, count: Int) -> Bool
    /// 撤退中（敵が 500 以内）にこのスキルで逃げるか。flee = 逃げる向き（正規化済み）、enemyDistance = 最寄りの敵との距離。
    /// `.cast` / `.castNow` で発動、`.skip` で見送り、`.useDefault` は従来どおり（突進・ブリンク系のスキル1/2 だけ
    /// 逃げる向きへ撃つ。奥義は撃たない）。奥義を逃走に使うのは、キットが明示した時だけ。
    func botEscape(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                   flee: Vec2, enemyDistance: Double) -> BotKitDecision
}

extension HeroKit {
    var isReady: Bool { false }

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        base
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        base
    }

    func text(slot: SkillSlot) -> KitText? { nil }
    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? { nil }
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double { base }

    func resolveAim(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot, stage: Int,
                    targeting: SkillTargeting, target: SkillTarget) -> SkillAim?? {
        nil
    }

    func canStart(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) -> Bool { true }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome { .generic(nil, nil) }

    /// 既定: 再使用は何もせず窓を閉じる。
    func recast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast, window: RecastWindow) {
        Kit.closeRecast(&s, ctx, caster: c.caster, slot: c.slot)
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {}
    func onWindowClosed(_ s: inout SimState, _ ctx: SimContext, owner: Int, slot: SkillSlot, expired: Bool) {}
    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {}
    func update(_ s: inout SimState, _ ctx: SimContext, owner: Int) {}
    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {}
    func onDeath(old: KitState, into fresh: inout KitState) {}

    func outgoingDamageBonus(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                             source: DamageSource) -> Double {
        0
    }

    func modifyIncomingDamage(_ s: inout SimState, _ ctx: SimContext, victim: Int, attacker: Int?,
                              source: DamageSource, amount: Double) -> Double {
        amount
    }

    func forceCrit(_ s: inout SimState, _ ctx: SimContext, attacker: Int) -> Bool? { nil }

    func shapeBasicAttack(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int,
                          plan: inout BasicAttackPlan) {}

    func onBasicAttackHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, damage: Double) {}

    func onSkillHit(_ s: inout SimState, _ ctx: SimContext, attacker: Int, target: Int, slot: SkillSlot,
                    damage: Double) {}

    func onSkillCast(_ s: inout SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) {}
    func onDamageTaken(_ s: inout SimState, _ ctx: SimContext, victim: Int, attacker: Int?, amount: Double) {}
    func onKillOrAssist(_ s: inout SimState, _ ctx: SimContext, hero: Int, victim: Int) {}

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        .useDefault
    }

    func botFarm(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 center: Vec2, count: Int) -> Bool {
        false
    }

    func botEscape(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                   flee: Vec2, enemyDistance: Double) -> BotKitDecision {
        .useDefault
    }
}
