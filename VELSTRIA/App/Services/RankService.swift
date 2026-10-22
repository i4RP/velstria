import Foundation
import VelstriaCore

// 担当: app-services
// ランク（Mobile Legends と同じ規則。正はクラウドの relay/src/rank.ts。片方を変えたらもう片方も変える）
// - ウォリアー III〜I（星 3）/ エリート III〜I（星 4）/ マスター IV〜I（星 4）/ グランドマスター V〜I（星 5）/
//   エピック V〜I（星 5）/ レジェンド V〜I（星 5）/ ミシック（星の累計。H ミシック 25・G ミシック 50・I ミシック 100）
// - 勝利 星 +1。満星で勝つと次の段位の星 1。敗北 星 −1、星 0 で負けると 1 段位下の「満星 −1」。
// - ウォリアーは負けても星が減らない。ティアの最下段・星 0 では下のティアへ落ちない（ミシック星 0 の敗北だけレジェンド I へ）。
// - スターポイント: 勝利でたまり、満タンで星 +1（1 試合で 1 つまで）。満タンはティアごと（starPointCap: ウォリアー 100・エリート 200・
//   マスター 300・グランドマスター 500・エピック 700・レジェンド 1000。Fandom「Ranked」）。ミシックには無い（上がると 0）。
// - 保護ポイント: 敗北でたまり、満タンで次の敗北の星が減らない（protectionCap: スターポイントと同じ値、ミシック 1100。ミシックでもたまる）。
//   ティアが変わったら新しいティアの満タンに収める（fitPoints）。1 試合の加点（勝ち 20 + 評価 × 8、MVP +30。負け 評価 × 3 + 5）は
//   Velstria の式のまま（MLBB のメダル別の今の値が分かったら合わせる。docs/OUTGAME_GAP.md 7-4）。
// - シーズン: SeasonService（新しいシーズンの最初の試合の前に下げる）。

struct LadderEntry: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var rating: Int
    var tier: RankTier
    var isPlayer: Bool
}

/// 1 試合のランクの動き（リザルトの演出に使う）。
struct RankMatchDelta: Equatable {
    var starPointsGain = 0
    var scoreBonus = 0
    var activeBonus = 0
    var protected = false
    /// この試合の前に新しいシーズンへ進めて、ランクを下げた（SeasonService.advance）。
    var seasonReset = false
}

enum RankService {
    /// ラダーに並ぶライバル数。
    static let rivalCount = 50

    /// スターポイントの満タン（Fandom「Ranked」: ウォリアー 100・エリート 200・マスター 300・グランドマスター 500・エピック 700・
    /// レジェンド 1000）。ミシックは 0（星上げポイントが無い）。割合は progress(_:cap:) で出す（0 で割らない）。relay の STAR_POINT_CAP。
    static func starPointCap(_ t: RankTier) -> Int {
        switch t {
        case .warrior: return 100
        case .elite: return 200
        case .master: return 300
        case .grandmaster: return 500
        case .epic: return 700
        case .legend: return 1000
        case .mythic: return 0
        }
    }

    /// 保護ポイントの満タン（スターポイントと同じ値。ミシックは 1100: 2.2.16 の日本語 UI の映像。Fandom の 1500 は古い）。relay の PROTECTION_CAP。
    static func protectionCap(_ t: RankTier) -> Int {
        t == .mythic ? 1100 : starPointCap(t)
    }

    /// 満タンに対する割合（0〜1）。満タンが 0（ミシックのスターポイント）なら 0。
    static func progress(_ value: Int, cap: Int) -> Double {
        cap > 0 ? min(1, max(0, Double(value) / Double(cap))) : 0
    }

    /// ポイントを今のティアの満タンに収める（スターポイントは満タン未満でミシックは 0、保護ポイントは満タンまで）。relay の fitPoints。
    static func fitPoints(_ r: inout RankState) {
        r.starPoints = max(0, min(r.starPoints, starPointCap(r.tier) - 1))
        r.protectionPoints = max(0, min(r.protectionPoints, protectionCap(r.tier)))
    }

    static func divisions(_ t: RankTier) -> Int {
        switch t {
        case .warrior, .elite: return 3
        case .master: return 4
        case .grandmaster, .epic, .legend: return 5
        case .mythic: return 1
        }
    }

    static func maxStars(_ t: RankTier) -> Int {
        switch t {
        case .warrior: return 3
        case .elite, .master: return 4
        case .grandmaster, .epic, .legend: return 5
        case .mythic: return 0
        }
    }

    /// 並べ替え用の通算ポイント。
    static func rating(_ r: RankState) -> Int {
        if r.tier == .mythic { return r.tier.rawValue * 1000 + r.stars * 10 }
        return r.tier.rawValue * 1000 + (divisions(r.tier) - r.division) * 150 + r.stars * 25
    }

    /// MLBB の試合評価（0〜16）。チーム最高 MVP スコアを 16 近くに置いた相対値。
    static func matchRating(_ p: PlayerSummary, in summary: MatchSummary) -> Double {
        let best = summary.players.map(\.mvpScore).max() ?? 1
        let v = 2 + 13.5 * max(0, p.mvpScore) / max(1, best)
        return (min(16, max(1, v)) * 10).rounded() / 10
    }

    // MARK: - 試合結果の反映

    /// 試合結果をランクへ反映（端末側の計算。クラウドに繋がれば後で正の値で上書きする）。
    /// 新しいシーズンの最初の試合なら、先にシーズンを進めて下げる（relay の match と同じ順。報酬のメールは次の起動かランク画面で送る）。
    @discardableResult
    static func apply(won: Bool, rating: Double = 6, mvp: Bool = false, to r: inout RankState, now: Date = Date()) -> RankMatchDelta {
        var d = RankMatchDelta()
        d.seasonReset = SeasonService.advance(&r, to: SeasonService.season(at: now))
        let rt = min(16, max(0, rating))
        if won {
            r.seasonWins += 1
            addStar(&r)
            if r.tier != .mythic {
                d.starPointsGain = Int((20 + rt * 8 + (mvp ? 30 : 0)).rounded())
                r.starPoints += d.starPointsGain
                let cap = starPointCap(r.tier)
                if r.starPoints >= cap {
                    r.starPoints -= cap
                    addStar(&r)
                }
            }
        } else {
            r.seasonLosses += 1
            // 保護ポイントはミシックでもたまる（満タン 1100）
            d.scoreBonus = Int((rt * 3).rounded())
            d.activeBonus = 5
            if r.protectionPoints >= protectionCap(r.tier) {
                r.protectionPoints = 0
                d.protected = true
            } else {
                removeStar(&r)
                r.protectionPoints += d.scoreBonus + d.activeBonus
            }
        }
        fitPoints(&r)
        r.highestTier = max(r.highestTier, r.tier)
        r.seasonHighestTier = max(r.seasonHighestTier, r.tier)
        if r.tier == .mythic { r.highestMythicStars = max(r.highestMythicStars, r.stars) }
        return d
    }

    private static func addStar(_ r: inout RankState) {
        if r.tier == .mythic {
            r.stars += 1
            return
        }
        if r.stars < maxStars(r.tier) {
            r.stars += 1
            return
        }
        if r.division > 1 {
            r.division -= 1
            r.stars = 1
            return
        }
        guard let next = RankTier(rawValue: r.tier.rawValue + 1) else { return }
        r.tier = next
        r.division = divisions(next)
        r.stars = next == .mythic ? 0 : 1
    }

    private static func removeStar(_ r: inout RankState) {
        switch r.tier {
        case .warrior:
            return
        case .mythic:
            if r.stars > 0 {
                r.stars -= 1
            } else {
                r.tier = .legend
                r.division = 1
                r.stars = maxStars(.legend) - 1
            }
        default:
            if r.stars > 0 {
                r.stars -= 1
            } else if r.division < divisions(r.tier) {
                r.division += 1
                r.stars = maxStars(r.tier) - 1
            }
        }
    }

    /// 保護ポイントが満タン（次の敗北で星が減らない）か。
    static func hasFloorProtection(_ r: RankState) -> Bool {
        r.protectionPoints >= protectionCap(r.tier)
    }

    /// 次の勝利で昇格（段位・ティア）するか。
    static func isPromotionMatch(_ r: RankState) -> Bool {
        r.tier != .mythic && r.stars >= maxStars(r.tier)
    }

    // MARK: - ラダー

    /// 対 AI ランキング（決定論的に生成したライバル + プレイヤー、rating 降順）。
    /// ライバルは playerID から作る乱数で固定生成するため、同じプレイヤーには常に同じ顔ぶれが並ぶ。
    static func ladder(for profile: Profile) -> [LadderEntry] {
        var rng = SplitMix64(seed: stableHash(profile.playerID) ^ 0x1ADD_E500_5EED_0001)
        let playerName = profile.displayName.isEmpty ? L("あなた", "You") : profile.displayName
        var used: Set<String> = [playerName]
        var entries: [LadderEntry] = []
        // ティアごとの人数（計 50）。中位が厚いピラミッド。
        let distribution: [(RankTier, Int)] = [
            (.warrior, 4), (.elite, 6), (.master, 8), (.grandmaster, 10),
            (.epic, 10), (.legend, 7), (.mythic, 5),
        ]
        for (tier, count) in distribution {
            for _ in 0..<count {
                var r = RankState()
                r.tier = tier
                if tier == .mythic {
                    r.division = 1
                    r.stars = rng.nextInt(in: 0...120)
                } else {
                    r.division = rng.nextInt(in: 1...divisions(tier))
                    r.stars = rng.nextInt(in: 0...maxStars(tier))
                }
                let name = rivalName(&rng, used: &used)
                entries.append(LadderEntry(name: name, rating: rating(r), tier: tier, isPlayer: false))
            }
        }
        entries.append(LadderEntry(name: playerName, rating: rating(profile.rank), tier: profile.rank.tier, isPlayer: true))
        return entries.sorted { a, b in
            if a.rating != b.rating { return a.rating > b.rating }
            if a.isPlayer != b.isPlayer { return a.isPlayer }
            return a.name < b.name
        }
    }

    /// プレイヤーの順位（1 始まり）。
    static func ladderPosition(for profile: Profile) -> Int {
        (ladder(for: profile).firstIndex { $0.isPlayer } ?? 0) + 1
    }

    private static let namePrefixes = [
        "Astra", "Nova", "Lumi", "Vega", "Rigel", "Orion", "Lyra", "Sirius", "Altair", "Deneb",
        "Mira", "Cygnus", "Kaia", "Zeph", "Rin", "Sora", "Hoshi", "Tsuki", "Yume", "Kage",
        "Aoi", "Hikari", "Ren", "Kai", "Noa", "Sei", "Ryu", "Haru", "Akira", "Mei",
    ]
    private static let nameSuffixes = [
        "blade", "fall", "wing", "heart", "storm", "shade", "arc", "rise",
        "song", "veil", "fang", "gaze", "flare", "drift", "crest", "spark",
    ]

    private static func rivalName(_ rng: inout SplitMix64, used: inout Set<String>) -> String {
        while true {
            let prefix = namePrefixes[rng.nextInt(in: 0...(namePrefixes.count - 1))]
            let suffix = nameSuffixes[rng.nextInt(in: 0...(nameSuffixes.count - 1))]
            let name: String
            switch rng.nextInt(in: 0...2) {
            case 0: name = prefix + suffix.capitalized
            case 1: name = "\(prefix)_\(rng.nextInt(in: 10...99))"
            default: name = "\(prefix)\(suffix)\(rng.nextInt(in: 1...9))"
            }
            if !used.contains(name) {
                used.insert(name)
                return name
            }
        }
    }

    /// プロセスをまたいで安定な文字列ハッシュ（FNV-1a 64bit）。String.hashValue は起動毎に変わるため使わない。
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }

    // MARK: - ランク到達報酬

    /// 到達報酬。
    static func tierRewards(_ tier: RankTier) -> [MailAttachment] {
        switch tier {
        case .warrior:
            return [MailAttachment(kind: .coin, amount: 300)]
        case .elite:
            return [MailAttachment(kind: .coin, amount: 800), MailAttachment(kind: .gem, amount: 20)]
        case .master:
            return [MailAttachment(kind: .coin, amount: 1200), MailAttachment(kind: .gem, amount: 40)]
        case .grandmaster:
            return [MailAttachment(kind: .coin, amount: 1600), MailAttachment(kind: .gem, amount: 60),
                    LiveOpsService.cosmeticReward("CO035", fallbackGems: 120)]
        case .epic:
            return [MailAttachment(kind: .coin, amount: 2000), MailAttachment(kind: .gem, amount: 80),
                    LiveOpsService.cosmeticReward("CO047", fallbackGems: 150)]
        case .legend:
            return [MailAttachment(kind: .coin, amount: 3000), MailAttachment(kind: .gem, amount: 120),
                    LiveOpsService.cosmeticReward("CO059", fallbackGems: 200)]
        case .mythic:
            return [MailAttachment(kind: .coin, amount: 5000), MailAttachment(kind: .gem, amount: 200),
                    LiveOpsService.cosmeticReward("CO071", fallbackGems: 300)]
        }
    }

    /// 到達済みか。
    static func hasReached(_ tier: RankTier, profile: Profile) -> Bool {
        profile.rank.highestTier >= tier || profile.rank.tier >= tier
    }

    static func isTierRewardClaimed(_ tier: RankTier, profile: Profile) -> Bool {
        profile.rank.claimedTierRewards.contains(tier.rawValue)
    }

    /// 到達済みかつ未受取なら受け取って true。
    static func claimTierReward(_ tier: RankTier, profile: inout Profile) -> Bool {
        guard hasReached(tier, profile: profile), !isTierRewardClaimed(tier, profile: profile) else { return false }
        profile.rank.claimedTierRewards.append(tier.rawValue)
        for a in tierRewards(tier) {
            LiveOpsService.grant(a, to: &profile)
        }
        // 報酬コスメで所持数の実績が進む
        LiveOpsService.evaluateAchievements(profile: &profile, master: .shared, now: Date())
        return true
    }

    // MARK: - 表示

    static func tierName(_ t: RankTier) -> String {
        switch t {
        case .warrior: return L("ウォリアー", "Warrior")
        case .elite: return L("エリート", "Elite")
        case .master: return L("マスター", "Master")
        case .grandmaster: return L("グランドマスター", "Grandmaster")
        case .epic: return L("エピック", "Epic")
        case .legend: return L("レジェンド", "Legend")
        case .mythic: return L("ミシック", "Mythic")
        }
    }

    /// ミシックの段階名（星の累計で決まる。日本語版の表記: ミシック 0〜24・Hミシック 25〜49・Gミシック 50〜99・Iミシック 100〜）。
    static func mythicName(stars: Int) -> String {
        switch stars {
        case 100...: return L("Iミシック", "Mythical Immortal")
        case 50...: return L("Gミシック", "Mythical Glory")
        case 25...: return L("Hミシック", "Mythical Honor")
        default: return L("ミシック", "Mythic")
        }
    }

    static func roman(_ division: Int) -> String {
        ["I", "II", "III", "IV", "V"][max(0, min(4, division - 1))]
    }

    /// 段位名（ティア名 + ローマ数字。ミシックは段階名）。
    static func shortName(_ r: RankState) -> String {
        r.tier == .mythic ? mythicName(stars: r.stars) : tierName(r.tier)
    }

    static func displayName(_ r: RankState) -> String {
        if r.tier == .mythic { return "\(mythicName(stars: r.stars)) ★\(r.stars)" }
        return "\(tierName(r.tier)) \(roman(r.division))"
    }

    /// ランクに応じた AI 難易度（味方, 敵）。
    static func botDifficulty(for r: RankState) -> (ally: Difficulty, enemy: Difficulty) {
        switch r.tier {
        case .warrior, .elite: return (.normal, .easy)
        case .master, .grandmaster, .epic: return (.normal, .normal)
        default: return (.hard, .hard)
        }
    }
}
