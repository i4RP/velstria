import Foundation

public enum SkillTarget: Codable, Hashable, Sendable {
    /// 対象不要（自己中心・自動照準）。
    case none
    /// 方向（正規化ベクトル）。
    case direction(Vec2)
    /// 地点。
    case point(Vec2)
    /// ユニット。
    case unit(EntityID)
}

/// ヒーロー 1 体への入力。人間（HUD）も AI も同じコマンドを発行する（サーバー権威化の前提）。
public enum PlayerCommand: Codable, Hashable, Sendable {
    /// 仮想スティック。zero で停止。
    case move(direction: Vec2)
    /// 地点へ移動（AI・ミニマップ操作）。
    case moveTo(point: Vec2)
    case stop
    /// 指定ユニットを通常攻撃（射程外なら追跡）。
    case attack(targetID: EntityID)
    /// 攻撃ボタン: 優先度に従い射程+α内の最適対象を自動選択。
    case attackNearest(priority: TargetPriority)
    case castSkill(slot: SkillSlot, target: SkillTarget)
    /// index = 0/1（spells 配列の添字）。
    case castSpell(index: Int, target: SkillTarget)
    case levelSkill(slot: SkillSlot)
    case setAutoLevel(enabled: Bool)
    case buyItem(itemID: String)
    /// items 配列の添字。
    case sellItem(slotIndex: Int)
    case recall
    case emote(emoteID: String)
    case surrenderVote(yes: Bool)
    /// チュートリアルのタワー練習へ進む際、訓練人形と再出現予約を取り除く。
    case removeTutorialDummies
}

public struct HeroCommand: Codable, Hashable, Sendable {
    /// 対象ヒーローのエンティティ ID。
    public var heroID: EntityID
    public var command: PlayerCommand
    /// クライアント入力の連番（二重発動防止・サーバー検証用）。
    public var sequence: UInt32

    public init(heroID: EntityID, command: PlayerCommand, sequence: UInt32 = 0) {
        self.heroID = heroID
        self.command = command
        self.sequence = sequence
    }
}
