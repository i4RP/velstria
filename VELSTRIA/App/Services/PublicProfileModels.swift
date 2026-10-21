import Foundation

// 担当: outgame（第3段）。公開の名刺とランキングの型。relay の Directory（`POST /v1/profile/…`・`POST /v1/ranking`）と同じ形。
// 名刺はオンラインに同意した人だけが送る（フレンドコードごとに 1 枚。書き込みは受信箱の鍵、読み出しはコードをまとめて指定）。
// 中身は表示用の自己申告と、relay のランク（RankAccount）が書く今のランク・今シーズンの最高ランク。

/// ランクの位置（RankTier.rawValue・ディビジョン・星）。ミシック以上はディビジョン 0 で星の数だけ。
struct PublicRank: Codable, Equatable, Hashable, Sendable {
    var tier: Int
    var division: Int
    var stars: Int

    static let unranked = PublicRank(tier: 0, division: 0, stars: 0)
}

/// 得意ヒーロー 1 体の成績（通算）。
struct PublicHeroStat: Codable, Equatable, Hashable, Sendable {
    var heroID: String
    var matches: Int
    var wins: Int
}

/// 公開の名刺（他人のフレンド一覧・ランキング・リザルトから開く）。
struct PublicProfile: Codable, Equatable, Identifiable, Sendable {
    /// フレンドコード（8 文字）。
    var code: String
    var name: String
    /// アイコンのヒーロー ID。
    var avatar: String?
    /// アバターのフレーム（コスメ ID）。
    var frame: String?
    var level: Int
    /// 今のランク。
    var rank: PublicRank
    /// 今シーズンの最高ランク（ランキングの並びの元）。
    var seasonBest: PublicRank
    /// 通算の最高ランク。
    var highest: PublicRank
    /// 国・地域（ISO 3166-1 alpha-2。自己申告）。
    var country: String?
    /// 得意ヒーロー（最大 3 体。試合数の多い順）。
    var heroes: [PublicHeroStat]
    /// 通算の試合数・勝ち数。
    var matches: Int
    var wins: Int
    /// 今シーズンのランク戦の勝ち・負け。
    var seasonWins: Int
    var seasonLosses: Int
    /// relay が受け取った日時。
    var updatedAt: Date

    var id: String { code }
}

/// ランキングの範囲（MLBB と同じ: グローバル・国・フレンド）。
enum RankingScope: Hashable, Sendable {
    case global
    /// 国・地域（ISO 3166-1 alpha-2）。
    case country(String)
    /// 自分のフレンド（と自分）。
    case friends
}

/// ランキングの 1 行（順位は 1 から）。
struct RankingEntry: Codable, Equatable, Identifiable, Sendable {
    var position: Int
    var profile: PublicProfile

    var id: String { profile.code }
}

/// ランキングの 1 ページ（上位 100 人と自分の順位）。
struct RankingPage: Equatable, Sendable {
    var entries: [RankingEntry]
    /// 自分の行（名刺を送っていない・ランク戦をしていなければ nil）。
    var me: RankingEntry?
    var fetchedAt: Date
}
