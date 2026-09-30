import Foundation
import VelstriaCore

// 担当: battle-hud。チュートリアル（mode == .tutorial）の進行管理。
// SimEvent と SimState の読み取り、HUD 操作の通知だけで進む状態機械（純粋な値型。単体テスト対象）。
//   移動 600 → 人形を通常攻撃 3 回 → スキル1 を習得 → スキル1 を発動 → ショップを開く → 装備を購入
//   → 味方ミニオンと敵の中央外塔を破壊 → 帰還 → 完了

enum TutorialStep: Int, CaseIterable, Equatable, Sendable {
    case move
    case attackDummy
    case learnSkill
    case castSkill
    case openShop
    case buyItem
    case destroyTower
    case recall
    case complete
}

/// 強調表示する操作部品。
enum TutorialHighlight: Equatable, Sendable {
    case joystick
    case attack
    case levelSkill1
    case skill1
    case shop
    case recall
}

struct TutorialDirector: Equatable, Sendable {
    static let moveGoal: Double = 600
    static let dummyHitGoal = 3
    /// これを超える 1 回の移動は転移（帰還・ブリンク）とみなして数えない。
    static let teleportJump: Double = 400
    /// 目標の敵タワー（Red の中央外塔）。
    static let targetTowerTeam: Team = .red
    static let targetTowerLane: Lane = .mid
    static let targetTowerTier: TowerTier = .outer

    private(set) var step: TutorialStep = .move
    private(set) var moved: Double = 0
    private(set) var dummyHits = 0
    /// 手順より先に塔が落ちていた場合に備えて覚えておく。
    private(set) var targetTowerDestroyed = false
    private var lastPosition: Vec2?

    var isComplete: Bool { step == .complete }

    var highlight: TutorialHighlight? {
        switch step {
        case .move: return .joystick
        case .attackDummy, .destroyTower: return .attack
        case .learnSkill: return .levelSkill1
        case .castSkill: return .skill1
        case .openShop, .buyItem: return .shop
        case .recall: return .recall
        case .complete: return nil
        }
    }

    /// 1 から数えた手順番号（完了は nil）と総数。
    var stepNumber: Int? { isComplete ? nil : step.rawValue + 1 }
    static var stepCount: Int { TutorialStep.allCases.count - 1 }

    /// 進捗（0...1）。数える手順のみ。
    var progress: Double? {
        switch step {
        case .move: return min(1, moved / Self.moveGoal)
        case .attackDummy: return min(1, Double(dummyHits) / Double(Self.dummyHitGoal))
        default: return nil
        }
    }

    // MARK: 入力

    /// 状態の観測（HUD の 15Hz 更新から）。
    mutating func observe(heroPosition: Vec2, alive: Bool, skill1Rank: Int) {
        if !alive {
            lastPosition = nil
            return
        }
        if step == .move, let last = lastPosition {
            let d = heroPosition.distance(to: last)
            if d < Self.teleportJump { moved += d }
            if moved >= Self.moveGoal { advance() }
        }
        lastPosition = heroPosition
        // 既に習得済み（自動習得など）なら習得手順を飛ばす
        if step == .learnSkill && skill1Rank > 0 { advance() }
    }

    /// SimEvent の処理。進んだら true。
    @discardableResult
    mutating func handle(_ event: SimEvent, humanID: EntityID, dummyIDs: [EntityID]) -> Bool {
        let before = step
        switch event {
        case .structureDestroyed(_, let kind, let team, let lane, let tier, _):
            if kind == .tower && team == Self.targetTowerTeam && lane == Self.targetTowerLane && tier == Self.targetTowerTier {
                targetTowerDestroyed = true
                if step == .destroyTower { advance() }
            }
        case .damage(let d):
            if step == .attackDummy, d.sourceID == humanID, d.source == .basicAttack, dummyIDs.contains(d.targetID) {
                dummyHits += 1
                if dummyHits >= Self.dummyHitGoal { advance() }
            }
        case .skillLeveled(let heroID, let slot, _):
            if step == .learnSkill, heroID == humanID, slot == .skill1 { advance() }
        case .skillCast(let c):
            if step == .castSkill, c.casterID == humanID, c.slot == .skill1 { advance() }
        case .itemPurchased(let heroID, _):
            // ショップを開かずにおすすめ購入した場合も購入手順まで進める
            if heroID == humanID && (step == .buyItem || step == .openShop) {
                step = .buyItem
                advance()
            }
        case .channelCompleted(let heroID, let kind, _):
            if step == .recall, heroID == humanID, kind == .recall { advance() }
        default:
            break
        }
        return step != before
    }

    /// HUD がスキル発動コマンドを送った（sim のスキル処理が未実装・不発でも手順を進められるように）。
    mutating func noteSkillCommand(slot: SkillSlot, castable: Bool) {
        if step == .castSkill && slot == .skill1 && castable { advance() }
    }

    mutating func noteShopOpened() {
        if step == .openShop { advance() }
    }

    /// 次の手順へ（先に満たされている条件は続けて消化する）。
    private mutating func advance() {
        guard let next = TutorialStep(rawValue: step.rawValue + 1) else { return }
        step = next
        if step == .destroyTower && targetTowerDestroyed { advance() }
    }

    // MARK: 表示

    /// 手順の指示カード（日英）。
    var title: String {
        switch step {
        case .move: return L("移動してみよう", "Move Around")
        case .attackDummy: return L("通常攻撃", "Basic Attacks")
        case .learnSkill: return L("スキルを習得", "Learn a Skill")
        case .castSkill: return L("スキルを発動", "Cast a Skill")
        case .openShop: return L("ショップを開く", "Open the Shop")
        case .buyItem: return L("装備を購入", "Buy an Item")
        case .destroyTower: return L("タワーを破壊", "Destroy a Tower")
        case .recall: return L("帰還", "Recall")
        case .complete: return L("チュートリアル完了", "Tutorial Complete")
        }
    }

    var instruction: String {
        switch step {
        case .move:
            return L("移動スティックをドラッグしてヒーローを動かそう。",
                     "Drag the movement stick to move your hero.")
        case .attackDummy:
            return L("中央レーンの訓練人形に近づき、攻撃ボタンで 3 回攻撃しよう。",
                     "Walk to the training dummies in the mid lane and hit one 3 times with Attack.")
        case .learnSkill:
            return L("スキル1 の近くに出た「＋」をタップして習得しよう。",
                     "Tap the “+” next to Skill 1 to learn it.")
        case .castSkill:
            return L("スキル1 をタップで発動。ドラッグで狙いを定め、「キャンセル」まで運ぶと取り消せる。",
                     "Tap Skill 1 to cast. Drag to aim, or drag onto “Cancel” to call it off.")
        case .openShop:
            return L("ゴールドのボタンからショップを開こう。倒れている間も買い物できる。",
                     "Open the shop from the gold button. You can shop even while dead.")
        case .buyItem:
            return L("光っている「おすすめ」の装備を購入しよう。Gold が足りなければミニオンを倒して稼ごう。",
                     "Buy the highlighted recommended item. Short on gold? Last-hit minions to earn more.")
        case .destroyTower:
            return L("味方ミニオンと一緒に敵の中央外塔を破壊しよう。ミニオンがタワーの攻撃を受けている間に攻撃するのがコツ。",
                     "Destroy the enemy's outer mid tower with your minions. Attack while the tower is shooting your minions.")
        case .recall:
            return L("帰還ボタンで泉へ戻ろう。詠唱中に動いたり攻撃を受けると中断される。",
                     "Tap Recall to return to your fountain. Moving or taking damage interrupts it.")
        case .complete:
            return L("基本操作をマスターしました。通常戦で腕試しをしよう！",
                     "You've mastered the basics. Try a standard match next!")
        }
    }

    /// 報酬・次の目標の案内（完了時）。
    var rewardNote: String {
        L("通常戦で勝利すると毎日の初勝利ボーナス +\(RewardService.firstWinBonusCoins) Coin を獲得できます。",
          "Win a standard match to earn the daily first-win bonus of +\(RewardService.firstWinBonusCoins) Coins.")
    }

    var progressText: String? {
        switch step {
        case .move: return "\(Int(min(moved, Self.moveGoal)))/\(Int(Self.moveGoal))"
        case .attackDummy: return "\(min(dummyHits, Self.dummyHitGoal))/\(Self.dummyHitGoal)"
        default: return nil
        }
    }

    /// ミニマップに示す目標地点。
    func objective(map: MapDefinition, dummySpots: [Vec2]) -> Vec2? {
        switch step {
        case .attackDummy:
            return dummySpots.count > 1 ? dummySpots[1] : dummySpots.first
        case .destroyTower:
            return map.towers.first {
                $0.team == Self.targetTowerTeam && $0.lane == Self.targetTowerLane && $0.tier == Self.targetTowerTier && !$0.isCore
            }?.pos
        case .recall:
            return map.fountain(.blue)
        default:
            return nil
        }
    }
}
