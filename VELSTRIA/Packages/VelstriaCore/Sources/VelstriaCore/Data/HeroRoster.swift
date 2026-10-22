import Foundation

// 担当: core-data。ゲームに出すヒーローの名簿。
// 2026-10-12: H025〜H034 の 10 体に絞って磨き込む方針（ユーザー指示）。H001〜H024 はデータ（マスター・3D・演出）を残したまま
// 一覧（MasterData.heroes）・ストア・ボット・ドラフトから外す。ID での参照（MasterData.hero(_:)）は全員引ける
// （古いセーブ・リプレイ・テストが参照しても壊れない）。戻すときは activeHeroIDs を全員にする。

public enum HeroRoster {
    /// ゲームに出すヒーロー（ID 昇順）。新規プレイヤーが最初から持つヒーロー（オンボーディングヒーロー）も同じ 10 体。
    public static let activeHeroIDs: [String] = (25...34).map { "H0\($0)" }
    private static let activeSet = Set(activeHeroIDs)

    /// 新規プレイヤーが最初から持つヒーロー。
    public static var starterHeroIDs: [String] { activeHeroIDs }
    /// 既定のヒーロー（アバター・フォールバック）。
    public static var defaultHeroID: String { activeHeroIDs[0] }

    public static func isActive(_ heroID: String) -> Bool { activeSet.contains(heroID) }
}
