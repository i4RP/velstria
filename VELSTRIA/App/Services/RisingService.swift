import Foundation
import VelstriaCore

// 担当: app-services。ライジング（対 AI の勝ち上がりラダー）。
// 固定ステージを順に攻略する。各ステージは対 AI の通常戦（mode .standard）で、敵難易度と報酬が段階的に上がる。
// ブラケット進行は Profile.rising に永続化し、勝利ごとに未受取のステージ報酬を付与する。

enum RisingService {
    struct Stage: Identifiable, Hashable {
        let index: Int
        let enemyDifficulty: Difficulty
        let rewardCoins: Int
        let rewardGems: Int
        var id: Int { index }
    }

    /// ステージ構成（難易度・報酬を段階的に上げる）。
    static let ladder: [Stage] = [
        Stage(index: 0, enemyDifficulty: .easy,   rewardCoins: 150, rewardGems: 0),
        Stage(index: 1, enemyDifficulty: .easy,   rewardCoins: 200, rewardGems: 0),
        Stage(index: 2, enemyDifficulty: .normal, rewardCoins: 250, rewardGems: 5),
        Stage(index: 3, enemyDifficulty: .normal, rewardCoins: 350, rewardGems: 5),
        Stage(index: 4, enemyDifficulty: .hard,   rewardCoins: 450, rewardGems: 10),
        Stage(index: 5, enemyDifficulty: .hard,   rewardCoins: 700, rewardGems: 25),
    ]

    static var stageCount: Int { ladder.count }
    static func stage(_ index: Int) -> Stage? { ladder.indices.contains(index) ? ladder[index] : nil }
    static func isComplete(_ progress: RisingProgress) -> Bool { progress.stageIndex >= ladder.count }
    static func currentStage(_ progress: RisingProgress) -> Stage? { stage(progress.stageIndex) }
    static func newSeed() -> UInt64 { UInt64.random(in: 1...UInt64(UInt32.max)) }

    /// 現ステージの試合構成（対 AI・標準マップ・プレイヤーのヒーロー/ロードアウト）。
    static func config(for stage: Stage, heroID: String, profile: Profile, seed: UInt64,
                       master: MasterData = .shared) -> MatchConfig {
        let name = profile.displayName.isEmpty ? "Player" : profile.displayName
        let spells = PracticeSetup.spells(heroID: heroID, profile: profile, master: master)
        let runes = PracticeSetup.runes(profile: profile, master: master)
        let skin = profile.equippedSkins[heroID].flatMap { profile.ownedCosmeticIDs.contains($0) ? $0 : nil }
        return MatchFactory.standardMatch(mode: .standard, humanHeroID: heroID, humanName: name,
                                          humanSpells: spells, humanRunes: runes, humanSkin: skin,
                                          allyDifficulty: .normal, enemyDifficulty: stage.enemyDifficulty,
                                          seed: seed, master: master)
    }

    /// 勝敗を反映する。勝ちなら 1 段前進し、そのステージが未受取なら報酬を付与して戻り値で返す。
    /// stageIndex が現在の挑戦ステージと一致する時だけ進める（古い結果での多重前進を防ぐ）。
    @discardableResult
    static func resolve(won: Bool, stageIndex: Int, profile: inout Profile) -> Stage? {
        guard won, stageIndex == profile.rising.stageIndex, let stage = stage(stageIndex) else { return nil }
        profile.rising.stageIndex = min(ladder.count, profile.rising.stageIndex + 1)
        profile.rising.bestStageIndex = max(profile.rising.bestStageIndex, profile.rising.stageIndex)
        guard !profile.rising.claimedStages.contains(stageIndex) else { return nil }
        profile.rising.claimedStages.append(stageIndex)
        if stage.rewardCoins > 0 { LiveOpsService.grant(MailAttachment(kind: .coin, amount: stage.rewardCoins), to: &profile) }
        if stage.rewardGems > 0 { LiveOpsService.grant(MailAttachment(kind: .gem, amount: stage.rewardGems), to: &profile) }
        return stage
    }
}
