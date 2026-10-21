import Foundation

// 担当: app-services
// ランクのシーズン（MLBB と同じ番号・長さ。正はクラウドの relay/src/rank.ts。片方を変えたらもう片方も変える）
// - シーズン N は 2026-09-16 08:00 UTC（MLBB S42 の開始）+ (N − 42) × 91 日（13 週）に始まる。S43 は 2026-12-16 08:00 UTC から。
//   シーズン制は S42 から（それより前の番号・旧版のデータは S42 として読む）。
// - 新しいシーズンの最初の起動（AppModel.onLaunch）・ランク画面を開いた時・ランク戦の結果の反映（RankService.apply）で、
//   前のシーズンの最終ランクから 1 回だけ下げる（resetPlace。星・両ポイント・勝敗は 0、最高到達はそのまま）。何シーズン空いても 1 回。
//   クラウドのランクを使う時は relay も同じ規則で（新シーズンの最初の get / seed / match で）下げ、端末はその値で上書きする（adopt）。
//   シーズンの番号は端末の RankState.season で持ち、進めるのは advance だけ（同じシーズンへは二度下げない）。
// - シーズン報酬: 終わったシーズンの最高ティア（そのシーズンに 1 試合以上した時だけ）。MLBB の BP の数をコインで、メールで 1 回だけ送る
//   （advance が endedSeasons に積み、deliverRewards が送って rewardedSeason を進める。同じシーズンは二度送らない）。

/// 終わったシーズンの記録（報酬のメールを送るまで RankState.endedSeasons に置く）。
struct SeasonRecord: Codable, Equatable {
    var season: Int
    /// そのシーズンの最高ティア（報酬の基準）。
    var highestTier: RankTier
    /// 最終ランク（下げ方の基準）。
    var tier: RankTier
    var division: Int
    var stars: Int
    var wins: Int
    var losses: Int

    /// そのシーズンにランク戦をしたか（報酬はした時だけ）。
    var played: Bool { wins + losses > 0 }

    private enum CodingKeys: String, CodingKey {
        case season, highestTier, tier, division, stars, wins, losses
    }
}

extension SeasonRecord {
    /// 欠けた項目は既定で読む（保存データの要素。PersistenceService の補完に頼らない）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        season = try c.decodeIfPresent(Int.self, forKey: .season) ?? SeasonService.firstSeason
        tier = try c.decodeIfPresent(RankTier.self, forKey: .tier) ?? .warrior
        highestTier = try c.decodeIfPresent(RankTier.self, forKey: .highestTier) ?? tier
        division = try c.decodeIfPresent(Int.self, forKey: .division) ?? 1
        stars = try c.decodeIfPresent(Int.self, forKey: .stars) ?? 0
        wins = try c.decodeIfPresent(Int.self, forKey: .wins) ?? 0
        losses = try c.decodeIfPresent(Int.self, forKey: .losses) ?? 0
    }
}

enum SeasonService {
    /// シーズン制を始めたシーズン（MLBB の S42）。これより前の番号は S42 として読む。
    static let firstSeason = 42
    /// S42 の開始: 2026-09-16 08:00 UTC（MLBB S42 の開始日。切り替えの時刻はコミュニティの記録）。relay の SEASON_EPOCH_MS。
    static let firstSeasonStart = Date(timeIntervalSince1970: 1_789_545_600)
    /// 1 シーズン = 91 日（13 週。MLBB はおよそ 3 か月で、S36〜S38・S41・S42 は 91 日）。relay の SEASON_MS。
    static let seasonLength: TimeInterval = 91 * 86_400
    /// 報酬を送る前の終わったシーズンを覚えておく数（ふつうは 1 つ。起動もランク画面も開かずに何シーズンも過ぎた時の上限）。
    static let maxEndedSeasons = 4

    // MARK: - 境目

    /// その時刻のシーズン（S42 の開始より前は S42）。
    static func season(at date: Date) -> Int {
        let elapsed = date.timeIntervalSince(firstSeasonStart)
        guard elapsed >= 0 else { return firstSeason }
        return firstSeason + Int((elapsed / seasonLength).rounded(.down))
    }

    /// シーズンの開始時刻（終わりは次のシーズンの開始）。S42 より前の番号は S42。
    static func start(of season: Int) -> Date {
        firstSeasonStart.addingTimeInterval(Double(max(firstSeason, season) - firstSeason) * seasonLength)
    }

    /// 今のシーズンの残り日数（切り上げ。最後の 1 日未満も 1）。
    static func daysLeft(at date: Date) -> Int {
        let end = start(of: season(at: date) + 1)
        return max(1, Int((end.timeIntervalSince(date) / 86_400).rounded(.up)))
    }

    // MARK: - 下げ方

    /// 新しいシーズンの開始位置（前のシーズンの最終ランク → ティア・段位・星）。relay の seasonResetPlace と同じ。
    /// MLBB は公式の表を出しておらず、紹介ページどうしで食い違う。マスター〜エピックは 2017 年の公式（Patch Notes 1.2.18 の S5→S6）の形、
    /// ウォリアー・エリート（星だけ 0）とレジェンドは 2026 年の各ページで一致する行、ミシックは 2.2.16 の映像（docs/OUTGAME_GAP.md 7-12）。
    static func resetPlace(_ r: RankState) -> (tier: RankTier, division: Int, stars: Int) {
        switch r.tier {
        case .warrior, .elite:
            return (r.tier, min(max(1, r.division), RankService.divisions(r.tier)), 0)
        case .master:
            switch r.division {
            case ...1: return (.master, 3, 0)
            case 2: return (.master, 4, 0)
            default: return (.elite, 1, 0)
            }
        case .grandmaster:
            switch r.division {
            case ...1: return (.grandmaster, 3, 0)
            case 2: return (.grandmaster, 4, 0)
            case 3: return (.grandmaster, 5, 0)
            case 4: return (.master, 1, 0)
            default: return (.master, 2, 0)
            }
        case .epic:
            switch r.division {
            case ...1: return (.epic, 4, 0)
            case 2, 3: return (.epic, 5, 0)
            case 4: return (.grandmaster, 1, 0)
            default: return (.grandmaster, 2, 0)
            }
        case .legend:
            return r.division >= 5 ? (.epic, 4, 0) : (.epic, 3, 0)
        case .mythic:
            // 星の累計: Iミシック（100〜）→ エピック I・星 1、Hミシック・Gミシック（25〜99）→ エピック II（映像で確認）。
            // ミシック（0〜24）は見つからないのでエピック II とする（未確認）
            if r.stars >= 100 { return (.epic, 1, 1) }
            return (.epic, 2, 0)
        }
    }

    /// season へ進める。前のシーズンの記録なら 1 回だけ下げ（星・両ポイント・勝敗は 0、最高到達はそのまま）、終わったシーズンを
    /// endedSeasons に積む（1 試合以上した時だけ）。同じシーズン・先のシーズンへは何もしない（false）。何シーズン空いても下げるのは 1 回。
    /// relay の rollover と同じ。
    @discardableResult
    static func advance(_ r: inout RankState, to season: Int) -> Bool {
        let from = max(firstSeason, r.season)
        guard from < season else {
            if r.season != from { r.season = from }
            return false
        }
        let ended = SeasonRecord(season: from, highestTier: max(r.seasonHighestTier, r.tier), tier: r.tier,
                                 division: r.division, stars: r.stars, wins: r.seasonWins, losses: r.seasonLosses)
        if ended.played {
            r.endedSeasons.append(ended)
            if r.endedSeasons.count > maxEndedSeasons { r.endedSeasons.removeFirst(r.endedSeasons.count - maxEndedSeasons) }
        }
        let place = resetPlace(r)
        r.tier = place.tier
        r.division = place.division
        r.stars = place.stars
        r.starPoints = 0
        r.protectionPoints = 0
        r.seasonWins = 0
        r.seasonLosses = 0
        r.season = season
        r.seasonHighestTier = r.tier
        return true
    }

    // MARK: - 報酬

    /// シーズン報酬（そのシーズンの最高ティア）。MLBB の BP の数をそのままコインで（チケット・スキンの欠片・ミシックのエモートは
    /// Velstria に無いので送らない。docs/OUTGAME_GAP.md 7-13）。マスター〜ミシックは S39 の値（esports.gg 2025-12-26）、
    /// ウォリアー・エリートは Fandom「Season Rank Rewards」の値。
    static func rewards(for tier: RankTier) -> [MailAttachment] {
        let battlePoints: Int
        switch tier {
        case .warrior: battlePoints = 500
        case .elite: battlePoints = 1000
        case .master: battlePoints = 2000
        case .grandmaster: battlePoints = 3500
        case .epic: battlePoints = 6000
        case .legend, .mythic: battlePoints = 10_000
        }
        return [MailAttachment(kind: .coin, amount: battlePoints)]
    }

    /// 積んである終わったシーズンの報酬をメールで送る（rewardedSeason より後で、1 試合以上したシーズンだけ）。積んだ記録は消す。
    /// 送ったシーズンを返す。
    @discardableResult
    static func deliverRewards(profile: inout Profile, now: Date) -> [SeasonRecord] {
        let pending = profile.rank.endedSeasons.sorted { $0.season < $1.season }
        guard !pending.isEmpty else { return [] }
        profile.rank.endedSeasons = []
        var sent: [SeasonRecord] = []
        for record in pending where record.played && record.season > profile.rank.rewardedSeason {
            let tier = RankService.tierName(record.highestTier)
            LiveOpsService.sendMail(
                to: &profile,
                title: L("シーズン \(record.season) の報酬", "Season \(record.season) rewards"),
                body: L("シーズン \(record.season) の最高ランク「\(tier)」の報酬です。新しいシーズンが始まり、ランクはシーズンの初めの位置から再開しました。",
                        "Your reward for reaching \(tier) in Season \(record.season). A new season has begun, and your rank has restarted from its new-season position."),
                attachments: rewards(for: record.highestTier),
                now: now)
            profile.rank.rewardedSeason = record.season
            sent.append(record)
        }
        return sent
    }

    /// 起動時・ランク画面を開いた時: 今のシーズンへ進め（新しいシーズンなら下げる）、今シーズンの最高ティアを今のティアで更新し
    /// （クラウドの値で上がった分）、ポイントをティアの満タンに収め（旧規則の中継の値）、終わったシーズンの報酬をメールで送る。
    /// 送ったシーズンを返す。
    @discardableResult
    static func refresh(profile: inout Profile, now: Date) -> [SeasonRecord] {
        advance(&profile.rank, to: season(at: now))
        profile.rank.seasonHighestTier = max(profile.rank.seasonHighestTier, profile.rank.tier)
        RankService.fitPoints(&profile.rank)
        return deliverRewards(profile: &profile, now: now)
    }
}
