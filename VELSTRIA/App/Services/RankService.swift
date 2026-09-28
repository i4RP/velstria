import Foundation
import VelstriaCore

// 担当: app-services
// ランク（対 AI ローカルラダー。DESIGN §12）
// - 隕鉄〜星冠: 各ティア 段位 III → II → I、星 0〜3。
//   勝利: 星 +1。星 3 の状態で勝つと次の段位（I の次は次ティアの III）へ昇格し、星 1 から始まる。
//   敗北: 星 −1。星 0 で負けると 1 段位降格して星 2（ティアをまたぐ場合は下位ティアの I・星 2）。
//   隕鉄は降格も星の減少による段位低下もしない（星は 0 で止まる）。
// - 降格保護（ティア下限保護）: 各ティアへ「初めて」昇格した時に 1 回分付与される。
//   そのティアの III・星 0 で負けてティア降格する場面で 1 回だけ降格を防ぐ（消費される）。
//   契約の RankState に専用フィールドが無いため、星環王未満では `points` を保護の残り回数（0/1）として使う。
//   （星環王ではポイントそのもの。rating() は星環王未満の points を無視する）
// - 星環王: ポイント制。勝利 +20 / 敗北 −15（0 で下げ止まり）。0pt で負けると星冠 I・星 2 へ降格。

struct LadderEntry: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var rating: Int
    var tier: RankTier
    var isPlayer: Bool
}

enum RankService {
    static let maxStars = 3
    static let sovereignWinPoints = 20
    static let sovereignLossPoints = 15
    /// ラダーに並ぶライバル数。
    static let rivalCount = 50

    /// 並べ替え用の通算ポイント。
    static func rating(_ r: RankState) -> Int {
        let base = r.tier.rawValue * 1000 + (3 - r.division) * 300 + r.stars * 100
        return r.tier == .starRingSovereign ? base + r.points : base
    }

    // MARK: - 試合結果の反映

    /// 試合結果をランクへ反映。
    static func apply(won: Bool, to r: inout RankState) {
        if won {
            r.seasonWins += 1
            applyWin(&r)
        } else {
            r.seasonLosses += 1
            applyLoss(&r)
        }
        r.highestTier = max(r.highestTier, r.tier)
    }

    private static func applyWin(_ r: inout RankState) {
        if r.tier == .starRingSovereign {
            r.points += sovereignWinPoints
            return
        }
        if r.stars < maxStars {
            r.stars += 1
            return
        }
        // 星 3 での勝利 → 昇格
        if r.division > 1 {
            r.division -= 1
            r.stars = 1
            return
        }
        guard let next = RankTier(rawValue: r.tier.rawValue + 1) else { return }
        let firstTime = next > r.highestTier
        r.tier = next
        if next == .starRingSovereign {
            r.division = 1
            r.stars = 0
            r.points = 0
        } else {
            r.division = 3
            r.stars = 1
            r.points = firstTime ? 1 : 0
        }
    }

    private static func applyLoss(_ r: inout RankState) {
        switch r.tier {
        case .starRingSovereign:
            if r.points > 0 {
                r.points = max(0, r.points - sovereignLossPoints)
            } else {
                r.tier = .starCrown
                r.division = 1
                r.stars = 2
                r.points = 0
            }
        case .meteorite:
            r.stars = max(0, r.stars - 1)
        default:
            if r.stars > 0 {
                r.stars -= 1
            } else if r.division < 3 {
                r.division += 1
                r.stars = 2
            } else if r.points > 0 {
                // 降格保護を消費してティアに留まる
                r.points = 0
            } else if let lower = RankTier(rawValue: r.tier.rawValue - 1) {
                r.tier = lower
                r.division = 1
                r.stars = 2
                r.points = 0
            }
        }
    }

    /// 降格保護が残っているか（星環王・隕鉄では常に false）。
    static func hasFloorProtection(_ r: RankState) -> Bool {
        r.tier != .starRingSovereign && r.tier != .meteorite && r.points > 0
    }

    /// 次の勝利で昇格（段位・ティア）するか。
    static func isPromotionMatch(_ r: RankState) -> Bool {
        r.tier != .starRingSovereign && r.stars >= maxStars
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
            (.meteorite, 6), (.silverRing, 9), (.goldRing, 10), (.whiteStar, 9),
            (.azureCrystal, 7), (.starCrown, 6), (.starRingSovereign, 3),
        ]
        for (tier, count) in distribution {
            for _ in 0..<count {
                var r = RankState()
                r.tier = tier
                if tier == .starRingSovereign {
                    r.division = 1
                    r.points = rng.nextInt(in: 0...48) * 5
                } else {
                    r.division = rng.nextInt(in: 1...3)
                    r.stars = rng.nextInt(in: 0...maxStars)
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
        case .meteorite:
            return [MailAttachment(kind: .coin, amount: 300)]
        case .silverRing:
            return [MailAttachment(kind: .coin, amount: 800), MailAttachment(kind: .gem, amount: 20)]
        case .goldRing:
            return [MailAttachment(kind: .coin, amount: 1200), MailAttachment(kind: .gem, amount: 40)]
        case .whiteStar:
            return [MailAttachment(kind: .coin, amount: 1600), MailAttachment(kind: .gem, amount: 60),
                    LiveOpsService.cosmeticReward("CO035", fallbackGems: 120)]
        case .azureCrystal:
            return [MailAttachment(kind: .coin, amount: 2000), MailAttachment(kind: .gem, amount: 80),
                    LiveOpsService.cosmeticReward("CO047", fallbackGems: 150)]
        case .starCrown:
            return [MailAttachment(kind: .coin, amount: 3000), MailAttachment(kind: .gem, amount: 120),
                    LiveOpsService.cosmeticReward("CO059", fallbackGems: 200)]
        case .starRingSovereign:
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
        return true
    }

    // MARK: - 表示

    static func tierName(_ t: RankTier) -> String {
        switch t {
        case .meteorite: return L("隕鉄", "Meteorite")
        case .silverRing: return L("銀環", "Silver Ring")
        case .goldRing: return L("金環", "Gold Ring")
        case .whiteStar: return L("白星", "White Star")
        case .azureCrystal: return L("蒼晶", "Azure Crystal")
        case .starCrown: return L("星冠", "Star Crown")
        case .starRingSovereign: return L("星環王", "Star Sovereign")
        }
    }

    static func displayName(_ r: RankState) -> String {
        if r.tier == .starRingSovereign { return "\(tierName(r.tier)) \(r.points)pt" }
        let roman = ["I", "II", "III"]
        return "\(tierName(r.tier)) \(roman[max(0, min(2, r.division - 1))])"
    }

    /// ランクに応じた AI 難易度（味方, 敵）。
    static func botDifficulty(for r: RankState) -> (ally: Difficulty, enemy: Difficulty) {
        switch r.tier {
        case .meteorite, .silverRing: return (.normal, .easy)
        case .goldRing, .whiteStar: return (.normal, .normal)
        default: return (.hard, .hard)
        }
    }
}
