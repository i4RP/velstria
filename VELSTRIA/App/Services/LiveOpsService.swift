import Foundation
import VelstriaCore

// 担当: app-services
// ライブオプス（オフライン完結）:
// - ログインボーナス（7 日周期、メールで配布）と初回起動のウェルカムメール
// - デイリーミッション（12 件のプールを 4 件ずつ 3 グループに分け、日付キーから各グループ 1 件を決定論的に選ぶ）
// - ウィークリーミッション（4 件固定、ISO 週キーで更新）
// - イベント（開幕祭 2026-10-01〜2026-12-31 とイベントミッション 3 件、毎週末の「週末スターブースト」）
// - スターパス（30 段階 × 1000 XP、無料 / プレミアム）
// - 実績（26 件、試合後などに評価）、お知らせ（4 件、静的）
// 日付はすべて端末ローカルの暦で扱う。未受取のまま期限切れになったミッション報酬はメールで届ける。
//
// イベントミッションの進捗は MissionState.weekly にウィークリー 4 件の後ろへ並べて保持する
// （UI は daily + weekly から ID で進捗を引くため）。週の切替では持ち越し、イベント終了時に
// 達成済み・未受取の報酬をメールで届けて枠を外す。ウィークリーの一覧は weeklyMissions(profile:) で引くこと。
// 所持品が増える受取（ミッション・パス・メール・ランク報酬・ストア購入）の後は実績を再評価する。

struct MissionDef: Identifiable, Equatable {
    enum Kind: String { case playMatches, winMatches, kills, assists, creepScore, destroyTowers, useHeroRole, dealDamage }
    var id: String
    var titleJa: String
    var titleEn: String
    var kind: Kind
    var target: Int
    var rewardCoins: Int
    var rewardPassXP: Int
    /// useHeroRole の対象ロール（nil = どのロールでも可）。
    var role: Role? = nil
    /// Coin / パス XP 以外の追加報酬（イベントミッション用）。
    var extraRewards: [MailAttachment] = []

    var title: String { L(titleJa, titleEn) }
}

struct AchievementDef: Identifiable, Equatable {
    var id: String
    var titleJa: String
    var titleEn: String
    var detailJa: String
    var detailEn: String
    var target: Double
    var rewardGems: Int

    var title: String { L(titleJa, titleEn) }
    var detail: String { L(detailJa, detailEn) }
}

struct PassReward: Equatable {
    var level: Int
    var free: MailAttachment?
    var premium: MailAttachment?
}

struct NoticeDef: Identifiable, Equatable {
    var id: String
    var date: Date
    var titleJa: String
    var titleEn: String
    var bodyJa: String
    var bodyEn: String

    var title: String { L(titleJa, titleEn) }
    var body: String { L(bodyJa, bodyEn) }
}

struct EventDef: Identifiable, Equatable {
    var id: String
    var titleJa: String
    var titleEn: String
    var detailJa: String
    var detailEn: String
    var start: Date
    var end: Date
    var missionIDs: [String]

    var title: String { L(titleJa, titleEn) }
    var detail: String { L(detailJa, detailEn) }
}

/// ミッション・実績の進捗入力（1 試合分）。RewardService が組み立てて渡す。
struct MatchProgressInput: Equatable {
    var won: Bool
    var kills: Int
    var deaths: Int
    var assists: Int
    var creepScore: Int
    /// 自チームが破壊したタワー数。
    var towersDestroyed: Int
    var damageToHeroes: Double
    var role: Role?
    var heroID: String
}

enum LiveOpsService {
    static let passXPPerLevel = 1000
    static let passMaxLevel = 30
    /// メール箱の上限（超えたら受取済み・添付なしの古いものから削除）。
    static let maxMailCount = 100
    /// ログインボーナスメールの受取期限（日）。
    static let loginMailLifetimeDays = 30
    /// 週末スターブーストの Coin 増加率。
    static let weekendCoinBonusRate = 0.5
    static let launchEventID = "EVT_LAUNCH"
    static let weekendEventID = "EVT_WEEKEND"

    // MARK: - 定義: ミッション

    /// デイリー 12 件（4 件 × 3 グループ: 参加 / 戦闘 / 目標・ロール）。
    static var dailyMissionPool: [MissionDef] { dailyPool }
    static var weeklyMissionPool: [MissionDef] { weeklyPool }
    static var eventMissionPool: [MissionDef] { eventPool }

    private static let dailyGroupSize = 4

    private static let dailyPool: [MissionDef] = [
        // グループ 0: 参加
        MissionDef(id: "D01", titleJa: "対戦を 2 回プレイする", titleEn: "Play 2 matches",
                   kind: .playMatches, target: 2, rewardCoins: 150, rewardPassXP: 150),
        MissionDef(id: "D02", titleJa: "対戦を 3 回プレイする", titleEn: "Play 3 matches",
                   kind: .playMatches, target: 3, rewardCoins: 250, rewardPassXP: 200),
        MissionDef(id: "D03", titleJa: "対戦で 1 回勝利する", titleEn: "Win 1 match",
                   kind: .winMatches, target: 1, rewardCoins: 200, rewardPassXP: 200),
        MissionDef(id: "D04", titleJa: "対戦で 2 回勝利する", titleEn: "Win 2 matches",
                   kind: .winMatches, target: 2, rewardCoins: 300, rewardPassXP: 250),
        // グループ 1: 戦闘
        MissionDef(id: "D05", titleJa: "敵ヒーローを 6 体倒す", titleEn: "Defeat 6 enemy heroes",
                   kind: .kills, target: 6, rewardCoins: 200, rewardPassXP: 200),
        MissionDef(id: "D06", titleJa: "アシストを 10 回獲得する", titleEn: "Earn 10 assists",
                   kind: .assists, target: 10, rewardCoins: 200, rewardPassXP: 200),
        MissionDef(id: "D07", titleJa: "敵ヒーローに 20,000 ダメージを与える", titleEn: "Deal 20,000 damage to enemy heroes",
                   kind: .dealDamage, target: 20_000, rewardCoins: 200, rewardPassXP: 200),
        MissionDef(id: "D08", titleJa: "ミニオン・モンスターを 80 体倒す（CS）", titleEn: "Reach 80 creep score",
                   kind: .creepScore, target: 80, rewardCoins: 200, rewardPassXP: 200),
        // グループ 2: 目標・ロール
        MissionDef(id: "D09", titleJa: "チームでタワーを 3 本破壊する", titleEn: "Destroy 3 towers with your team",
                   kind: .destroyTowers, target: 3, rewardCoins: 200, rewardPassXP: 200),
        MissionDef(id: "D10", titleJa: "ヴァンガードで 1 回プレイする", titleEn: "Play 1 match as a Vanguard",
                   kind: .useHeroRole, target: 1, rewardCoins: 150, rewardPassXP: 150, role: .vanguard),
        MissionDef(id: "D11", titleJa: "レンジャーで 1 回プレイする", titleEn: "Play 1 match as a Ranger",
                   kind: .useHeroRole, target: 1, rewardCoins: 150, rewardPassXP: 150, role: .ranger),
        MissionDef(id: "D12", titleJa: "サポートで 1 回プレイする", titleEn: "Play 1 match as a Support",
                   kind: .useHeroRole, target: 1, rewardCoins: 150, rewardPassXP: 150, role: .support),
    ]

    private static let weeklyPool: [MissionDef] = [
        MissionDef(id: "W01", titleJa: "対戦を 15 回プレイする", titleEn: "Play 15 matches",
                   kind: .playMatches, target: 15, rewardCoins: 1000, rewardPassXP: 800),
        MissionDef(id: "W02", titleJa: "対戦で 7 回勝利する", titleEn: "Win 7 matches",
                   kind: .winMatches, target: 7, rewardCoins: 1200, rewardPassXP: 1000),
        MissionDef(id: "W03", titleJa: "敵ヒーローを 40 体倒す", titleEn: "Defeat 40 enemy heroes",
                   kind: .kills, target: 40, rewardCoins: 800, rewardPassXP: 600),
        MissionDef(id: "W04", titleJa: "チームでタワーを 12 本破壊する", titleEn: "Destroy 12 towers with your team",
                   kind: .destroyTowers, target: 12, rewardCoins: 800, rewardPassXP: 600),
    ]

    private static let eventPool: [MissionDef] = [
        MissionDef(id: "EV01", titleJa: "開幕祭: 対戦を 10 回プレイする", titleEn: "Launch Festival: Play 10 matches",
                   kind: .playMatches, target: 10, rewardCoins: 500, rewardPassXP: 500,
                   extraRewards: [MailAttachment(kind: .gem, amount: 50)]),
        MissionDef(id: "EV02", titleJa: "開幕祭: 対戦で 5 回勝利する", titleEn: "Launch Festival: Win 5 matches",
                   kind: .winMatches, target: 5, rewardCoins: 800, rewardPassXP: 500,
                   extraRewards: [MailAttachment(kind: .gem, amount: 80)]),
        MissionDef(id: "EV03", titleJa: "開幕祭: 敵ヒーローを 30 体倒す", titleEn: "Launch Festival: Defeat 30 enemy heroes",
                   kind: .kills, target: 30, rewardCoins: 500, rewardPassXP: 500,
                   extraRewards: [cosmeticReward("CO023", fallbackGems: 150)]),
    ]

    // MARK: - 定義: 実績

    private enum AchievementMetric {
        case wins, matches, kills, assists, pentaKills, mvps, longestWinStreak, totalDamage
        case rolePlayed(Role)
        case allRolesPlayed
        case rankReached(RankTier)
        case cosmeticsOwned, heroesOwned, accountLevel
    }

    private static let achievementTable: [(def: AchievementDef, metric: AchievementMetric)] = [
        (AchievementDef(id: "ACH_FIRST_WIN", titleJa: "はじめての勝利", titleEn: "First Victory",
                        detailJa: "対戦で初めて勝利する", detailEn: "Win your first match", target: 1, rewardGems: 20), .wins),
        (AchievementDef(id: "ACH_WINS_10", titleJa: "勝利の星 I", titleEn: "Star of Victory I",
                        detailJa: "通算 10 勝する", detailEn: "Win 10 matches", target: 10, rewardGems: 30), .wins),
        (AchievementDef(id: "ACH_WINS_50", titleJa: "勝利の星 II", titleEn: "Star of Victory II",
                        detailJa: "通算 50 勝する", detailEn: "Win 50 matches", target: 50, rewardGems: 60), .wins),
        (AchievementDef(id: "ACH_WINS_100", titleJa: "勝利の星 III", titleEn: "Star of Victory III",
                        detailJa: "通算 100 勝する", detailEn: "Win 100 matches", target: 100, rewardGems: 100), .wins),
        (AchievementDef(id: "ACH_MATCHES_10", titleJa: "戦場の常連", titleEn: "Regular Contender",
                        detailJa: "対戦を 10 回プレイする", detailEn: "Play 10 matches", target: 10, rewardGems: 20), .matches),
        (AchievementDef(id: "ACH_MATCHES_100", titleJa: "星環の古強者", titleEn: "Veteran of the Star Ring",
                        detailJa: "対戦を 100 回プレイする", detailEn: "Play 100 matches", target: 100, rewardGems: 60), .matches),
        (AchievementDef(id: "ACH_KILLS_100", titleJa: "百の撃破", titleEn: "Hundred Takedowns",
                        detailJa: "敵ヒーローを通算 100 体倒す", detailEn: "Defeat 100 enemy heroes", target: 100, rewardGems: 40), .kills),
        (AchievementDef(id: "ACH_KILLS_500", titleJa: "星墜としの刃", titleEn: "Starfall Blade",
                        detailJa: "敵ヒーローを通算 500 体倒す", detailEn: "Defeat 500 enemy heroes", target: 500, rewardGems: 80), .kills),
        (AchievementDef(id: "ACH_ASSISTS_200", titleJa: "導きの手", titleEn: "Guiding Hand",
                        detailJa: "アシストを通算 200 回獲得する", detailEn: "Earn 200 assists", target: 200, rewardGems: 40), .assists),
        (AchievementDef(id: "ACH_PENTA", titleJa: "ペンタキル", titleEn: "Penta Kill",
                        detailJa: "1 試合でペンタキルを達成する", detailEn: "Score a penta kill", target: 1, rewardGems: 100), .pentaKills),
        (AchievementDef(id: "ACH_MVP_10", titleJa: "輝ける者", titleEn: "Shining Star",
                        detailJa: "MVP を 10 回獲得する", detailEn: "Earn MVP 10 times", target: 10, rewardGems: 50), .mvps),
        (AchievementDef(id: "ACH_STREAK_5", titleJa: "五連星", titleEn: "Five-Star Streak",
                        detailJa: "5 連勝する", detailEn: "Win 5 matches in a row", target: 5, rewardGems: 50), .longestWinStreak),
        (AchievementDef(id: "ACH_DAMAGE_1M", titleJa: "百万の衝撃", titleEn: "Million Impact",
                        detailJa: "敵ヒーローへの与ダメージ通算 1,000,000", detailEn: "Deal 1,000,000 total damage to heroes",
                        target: 1_000_000, rewardGems: 60), .totalDamage),
        (AchievementDef(id: "ACH_ROLE_VANGUARD", titleJa: "守護の誓い", titleEn: "Oath of the Vanguard",
                        detailJa: "ヴァンガードでプレイする", detailEn: "Play a match as a Vanguard", target: 1, rewardGems: 10), .rolePlayed(.vanguard)),
        (AchievementDef(id: "ACH_ROLE_DUELIST", titleJa: "決闘者の矜持", titleEn: "Duelist's Pride",
                        detailJa: "デュエリストでプレイする", detailEn: "Play a match as a Duelist", target: 1, rewardGems: 10), .rolePlayed(.duelist)),
        (AchievementDef(id: "ACH_ROLE_RANGER", titleJa: "遠矢の射手", titleEn: "Far-Shot Archer",
                        detailJa: "レンジャーでプレイする", detailEn: "Play a match as a Ranger", target: 1, rewardGems: 10), .rolePlayed(.ranger)),
        (AchievementDef(id: "ACH_ROLE_ARCANIST", titleJa: "星術の探究者", titleEn: "Seeker of Star Arts",
                        detailJa: "アルカニストでプレイする", detailEn: "Play a match as an Arcanist", target: 1, rewardGems: 10), .rolePlayed(.arcanist)),
        (AchievementDef(id: "ACH_ROLE_SUPPORT", titleJa: "癒しの灯", titleEn: "Healing Light",
                        detailJa: "サポートでプレイする", detailEn: "Play a match as a Support", target: 1, rewardGems: 10), .rolePlayed(.support)),
        (AchievementDef(id: "ACH_ROLE_ASSASSIN", titleJa: "影の一閃", titleEn: "Shadow Strike",
                        detailJa: "アサシンでプレイする", detailEn: "Play a match as an Assassin", target: 1, rewardGems: 10), .rolePlayed(.assassin)),
        (AchievementDef(id: "ACH_ALL_ROLES", titleJa: "六星の使い手", titleEn: "Master of Six Stars",
                        detailJa: "6 ロールすべてでプレイする", detailEn: "Play a match with all 6 roles", target: 6, rewardGems: 40), .allRolesPlayed),
        (AchievementDef(id: "ACH_RANK_GOLD", titleJa: "金環到達", titleEn: "Gold Ring Reached",
                        detailJa: "ランク戦で金環に到達する", detailEn: "Reach Gold Ring in ranked", target: 1, rewardGems: 30), .rankReached(.goldRing)),
        (AchievementDef(id: "ACH_RANK_AZURE", titleJa: "蒼晶到達", titleEn: "Azure Crystal Reached",
                        detailJa: "ランク戦で蒼晶に到達する", detailEn: "Reach Azure Crystal in ranked", target: 1, rewardGems: 60), .rankReached(.azureCrystal)),
        (AchievementDef(id: "ACH_RANK_SOVEREIGN", titleJa: "星環王", titleEn: "Star Sovereign",
                        detailJa: "ランク戦で星環王に到達する", detailEn: "Reach Star Sovereign in ranked", target: 1, rewardGems: 150),
         .rankReached(.starRingSovereign)),
        (AchievementDef(id: "ACH_COLLECT_10", titleJa: "蒐集家", titleEn: "Collector",
                        detailJa: "コスメを 10 個所持する", detailEn: "Own 10 cosmetics", target: 10, rewardGems: 50), .cosmeticsOwned),
        (AchievementDef(id: "ACH_HEROES_12", titleJa: "英雄の集い", titleEn: "Gathering of Heroes",
                        detailJa: "ヒーローを 12 体所持する", detailEn: "Own 12 heroes", target: 12, rewardGems: 50), .heroesOwned),
        (AchievementDef(id: "ACH_LEVEL_20", titleJa: "星を渡る者", titleEn: "Star Wanderer",
                        detailJa: "アカウントレベル 20 に到達する", detailEn: "Reach account level 20", target: 20, rewardGems: 50), .accountLevel),
    ]

    static var achievements: [AchievementDef] { achievementTable.map(\.def) }

    // MARK: - 定義: お知らせ

    static var notices: [NoticeDef] { noticeList }

    private static let noticeList: [NoticeDef] = [
        NoticeDef(id: "NT001", date: localDate(2026, 10, 1),
                  titleJa: "『VELSIA - 星環の戦場』配信開始！",
                  titleEn: "VELSIA: Star Ring Arena is now live!",
                  bodyJa: "VELSIA へようこそ。5 対 5・3 レーンの戦場で、4 体の AI 味方と共に敵の Star Core を破壊しましょう。\n"
                      + "オフラインでいつでも遊べます。まずはチュートリアルで操作を確認し、通常戦で腕を磨いてください。\n"
                      + "ウェルカムメールに StarlightCoin・AstralGem・アバターフレームをお届けしています。",
                  bodyEn: "Welcome to VELSIA. Team up with four AI allies on a 5v5, three-lane battlefield and destroy the enemy Star Core.\n"
                      + "Play offline anytime. Start with the tutorial, then sharpen your skills in standard matches.\n"
                      + "A welcome gift of StarlightCoin, AstralGem and an avatar frame is waiting in your mailbox."),
        NoticeDef(id: "NT002", date: localDate(2026, 10, 1),
                  titleJa: "v1.0.0 パッチノート（概要）",
                  titleEn: "v1.0.0 Patch Notes (Summary)",
                  bodyJa: "・ヒーロー 24 体（6 ロール）、アクティブスキル 96 種、装備 72 種、バトルスペル 10 種、ルーン 30 種を実装\n"
                      + "・モード: 通常戦（難易度 3 段階）、ランク戦（BAN あり）、練習場、チュートリアル、観戦、リプレイ\n"
                      + "・ランク: 隕鉄〜星冠（各 3 段位・星 3）、星環王（ポイント制）。ティア初到達時に降格保護 1 回\n"
                      + "・デイリー / ウィークリーミッション、スターパス シーズン 1（30 段階）、実績、ログインボーナス\n"
                      + "・年齢区分に応じた月間購入上限を設定しています",
                  bodyEn: "- 24 heroes across 6 roles, 96 active skills, 72 items, 10 battle spells and 30 runes\n"
                      + "- Modes: Standard (3 difficulties), Ranked (with bans), Practice, Tutorial, Spectate and Replays\n"
                      + "- Ranks: Meteorite to Star Crown (3 divisions, 3 stars each) and Star Sovereign (points). "
                      + "One demotion shield when you first reach a tier\n"
                      + "- Daily / weekly missions, Star Pass Season 1 (30 levels), achievements and login bonuses\n"
                      + "- Monthly purchase limits apply based on your age group"),
        NoticeDef(id: "NT003", date: localDate(2026, 10, 1),
                  titleJa: "イベント「星環の開幕祭」開催（〜12/31）",
                  titleEn: "Event: Star Ring Launch Festival (until Dec 31)",
                  bodyJa: "2026 年 10 月 1 日〜12 月 31 日の期間中、イベントミッションをクリアすると AstralGem やエピックのアバターフレームを獲得できます。\n"
                      + "また毎週土日は「週末スターブースト」で試合の StarlightCoin 報酬が 50% 増加します。",
                  bodyEn: "From October 1 to December 31, 2026, clear event missions to earn AstralGem and an Epic avatar frame.\n"
                      + "Every Saturday and Sunday, Weekend Star Boost increases StarlightCoin match rewards by 50%."),
        NoticeDef(id: "NT004", date: localDate(2026, 10, 1),
                  titleJa: "スターパス シーズン 1 開幕",
                  titleEn: "Star Pass Season 1 has begun",
                  bodyJa: "試合やミッションでパス XP を集めてスターパスを進めましょう。全 30 段階、1 段階 1,000 XP です。\n"
                      + "無料トラックでは StarlightCoin・AstralGem・コスメを、プレミアムトラックではエピック・ミシックのコスメと追加の StarlightCoin・AstralGem を獲得できます。",
                  bodyEn: "Earn Pass XP from matches and missions to advance the Star Pass: 30 levels, 1,000 XP each.\n"
                      + "The free track offers StarlightCoin, AstralGem and cosmetics; the premium track adds Epic and Mythic cosmetics plus extra StarlightCoin and AstralGem."),
    ]

    // MARK: - 定義: イベント

    /// 現在時刻に対するイベント一覧（週末イベントは now を含む週末、平日なら次の週末）。
    static func events(now: Date) -> [EventDef] {
        [launchEvent, weekendEvent(now: now)]
    }

    static var events: [EventDef] { events(now: Date()) }

    private static var launchEvent: EventDef {
        EventDef(id: launchEventID,
                 titleJa: "星環の開幕祭", titleEn: "Star Ring Launch Festival",
                 detailJa: "配信開始を記念したイベント。期間中にイベントミッションを達成して AstralGem とエピックのアバターフレームを手に入れよう。",
                 detailEn: "A festival celebrating launch. Complete event missions to earn AstralGem and an Epic avatar frame.",
                 start: localDate(2026, 10, 1), end: localDate(2027, 1, 1),
                 missionIDs: eventPool.map(\.id))
    }

    private static func weekendEvent(now: Date) -> EventDef {
        let (start, end) = weekendWindow(containingOrAfter: now)
        return EventDef(id: weekendEventID,
                        titleJa: "週末スターブースト", titleEn: "Weekend Star Boost",
                        detailJa: "毎週土曜・日曜は、通常戦・ランク戦で獲得する StarlightCoin が 50% 増加します。",
                        detailEn: "Every Saturday and Sunday, StarlightCoin earned from standard and ranked matches is increased by 50%.",
                        start: start, end: end, missionIDs: [])
    }

    /// now を含む週末（土 0:00〜月 0:00）。平日なら直後の週末。
    static func weekendWindow(containingOrAfter now: Date) -> (start: Date, end: Date) {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        // weekday: 1 = 日 … 7 = 土 → 土曜からの経過日数（土 = 0, 日 = 1, 月 = 2 …）
        let daysSinceSaturday = cal.component(.weekday, from: today) % 7
        let saturday: Date
        if daysSinceSaturday <= 1 {
            saturday = cal.date(byAdding: .day, value: -daysSinceSaturday, to: today) ?? today
        } else {
            saturday = cal.date(byAdding: .day, value: 7 - daysSinceSaturday, to: today) ?? today
        }
        let monday = cal.date(byAdding: .day, value: 2, to: saturday) ?? saturday.addingTimeInterval(2 * 86_400)
        return (saturday, monday)
    }

    static func activeEvents(now: Date) -> [EventDef] { events(now: now).filter { $0.start <= now && now < $0.end } }

    static func event(id: String, now: Date = Date()) -> EventDef? { events(now: now).first { $0.id == id } }

    /// 週末スターブースト中か。
    static func isWeekendBoostActive(now: Date) -> Bool {
        activeEvents(now: now).contains { $0.id == weekendEventID }
    }

    // MARK: - 定義: スターパス

    static func passRewards() -> [PassReward] { passRewardTable }

    private static let passRewardTable: [PassReward] = (1...30).map { level in
        PassReward(level: level, free: freePassReward(level), premium: premiumPassReward(level))
    }

    /// 無料トラック: 10 の倍数でコスメ、5 の倍数で Gem 30、それ以外は Coin（100 + 10×段階）。
    private static func freePassReward(_ level: Int) -> MailAttachment {
        switch level {
        case 10: return cosmeticReward("CO017", fallbackGems: 60)
        case 20: return cosmeticReward("CO030", fallbackGems: 120)
        case 30: return cosmeticReward("CO026", fallbackGems: 120)
        case _ where level % 5 == 0: return MailAttachment(kind: .gem, amount: 30)
        default: return MailAttachment(kind: .coin, amount: 100 + 10 * level)
        }
    }

    /// プレミアムトラック: 5 の倍数でエピック / 10 の倍数でミシック級コスメ（30 はエピックのヒーロースキン）、
    /// 3 の倍数で Gem 40、それ以外は Coin 400。
    private static func premiumPassReward(_ level: Int) -> MailAttachment {
        switch level {
        case 5: return cosmeticReward("CO003", fallbackGems: 260)
        case 10: return cosmeticReward("CO008", fallbackGems: 440)
        case 15: return cosmeticReward("CO011", fallbackGems: 260)
        case 20: return cosmeticReward("CO012", fallbackGems: 440)
        case 25: return cosmeticReward("CO019", fallbackGems: 260)
        case 30: return cosmeticReward("CO031", fallbackGems: 440)
        case _ where level % 3 == 0: return MailAttachment(kind: .gem, amount: 40)
        default: return MailAttachment(kind: .coin, amount: 400)
        }
    }

    /// スターパス・ランク到達・イベントで配るコスメ（ログインボーナスの巡回から除外する）。
    static var rewardTrackCosmeticIDs: [String] {
        let pass = passRewardTable.flatMap { [$0.free, $0.premium].compactMap { $0 } }
        let rank = RankTier.allCases.flatMap { RankService.tierRewards($0) }
        let event = eventPool.flatMap(\.extraRewards)
        return (pass + rank + event).compactMap { $0.kind == .cosmetic ? $0.refID : nil }
    }

    /// コスメ報酬（マスターに無い ID なら Gem で代替）。
    static func cosmeticReward(_ cosmeticID: String, fallbackGems: Int, master: MasterData = .shared) -> MailAttachment {
        master.cosmetic(cosmeticID) != nil
            ? MailAttachment(kind: .cosmetic, amount: 1, refID: cosmeticID)
            : MailAttachment(kind: .gem, amount: fallbackGems)
    }

    // MARK: - 日付キー

    /// 端末ローカルのグレゴリオ暦。
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    /// "yyyy-MM-dd"（端末ローカル日付）。
    static func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// ISO 8601 週 "YYYY-Www"（月曜始まり）。
    static func weekKey(_ date: Date) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = .current
        let c = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04ld-W%02ld", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// "yyyy-MM"（月間課金額の集計キー）。
    static func monthKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04ld-%02ld", c.year ?? 0, c.month ?? 0)
    }

    /// 端末ローカルの y/m/d 0:00。
    static func localDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: - 参照（UI が使う）

    /// 今日のデイリーミッション（profile.missions.daily の ID 順）。
    static func dailyMissions(profile: Profile) -> [MissionDef] {
        profile.missions.daily.compactMap { p in dailyPool.first { $0.id == p.id } }
    }

    static func weeklyMissions(profile: Profile) -> [MissionDef] {
        profile.missions.weekly.compactMap { p in weeklyPool.first { $0.id == p.id } }
    }

    /// イベントのミッション定義。
    static func eventMissions(eventID: String) -> [MissionDef] {
        guard eventID == launchEventID else { return [] }
        return eventPool
    }

    static func missionDef(id: String) -> MissionDef? {
        dailyPool.first { $0.id == id } ?? weeklyPool.first { $0.id == id } ?? eventPool.first { $0.id == id }
    }

    /// イベントミッションの ID か。
    static func isEventMission(_ id: String) -> Bool { eventPool.contains { $0.id == id } }

    /// イベントミッションを含むイベント（週末イベントはミッションを持たない）。
    static func event(containingMission id: String) -> EventDef? {
        launchEvent.missionIDs.contains(id) ? launchEvent : nil
    }

    /// 指定時刻にそのイベントミッションが進行・受取できるか。
    static func isEventMissionActive(_ id: String, now: Date) -> Bool {
        guard let e = event(containingMission: id) else { return false }
        return e.start <= now && now < e.end
    }

    /// デイリー / ウィークリー / イベントのどれでも進捗を返す（イベントで未着手なら進捗 0）。
    static func missionProgress(id: String, profile: Profile) -> MissionProgress? {
        if let p = profile.missions.daily.first(where: { $0.id == id }) { return p }
        if let p = profile.missions.weekly.first(where: { $0.id == id }) { return p }
        return isEventMission(id) ? MissionProgress(id: id) : nil
    }

    /// 達成済みかつ未受取のミッション数（バッジ表示用。開催中イベントのミッションを含む）。
    static func claimableMissionCount(profile: Profile, now: Date = Date()) -> Int {
        (profile.missions.daily + profile.missions.weekly).filter { p in
            guard !p.claimed, let def = missionDef(id: p.id), p.progress >= def.target else { return false }
            return !isEventMission(p.id) || isEventMissionActive(p.id, now: now)
        }.count
    }

    /// 日付キーから今日のデイリー 3 件を決定論的に選ぶ（各グループから 1 件）。
    static func dailySelection(dayKey: String) -> [String] {
        var rng = SplitMix64(seed: RankService.stableHash("daily:" + dayKey))
        let groups = stride(from: 0, to: dailyPool.count, by: dailyGroupSize).map {
            Array(dailyPool[$0..<min($0 + dailyGroupSize, dailyPool.count)])
        }
        return groups.compactMap { rng.pick($0)?.id }
    }

    /// 7 日周期のログインボーナス（index 0 = 1 日目）。7 日目は周回 0 のエピックコスメ。
    static func loginBonusCalendar() -> [MailAttachment] {
        loginBonusCalendar(cycle: 0, profile: nil)
    }

    /// プロフィールに応じた今の周回のカレンダー（7 日目のコスメが所持済みなら Gem 100）。
    static func loginBonusCalendar(profile: Profile) -> [MailAttachment] {
        loginBonusCalendar(cycle: max(0, profile.totalLoginDays - 1) / 7, profile: profile)
    }

    /// 今日受け取ったログインボーナスの日（0〜6）。未ログインなら nil。
    static func loginBonusDayIndex(profile: Profile) -> Int? {
        profile.totalLoginDays > 0 ? (profile.totalLoginDays - 1) % 7 : nil
    }

    private static func loginBonusCalendar(cycle: Int, profile: Profile?) -> [MailAttachment] {
        [
            MailAttachment(kind: .coin, amount: 100),
            MailAttachment(kind: .gem, amount: 20),
            MailAttachment(kind: .coin, amount: 150),
            MailAttachment(kind: .gem, amount: 30),
            MailAttachment(kind: .coin, amount: 200),
            MailAttachment(kind: .gem, amount: 50),
            loginDay7Reward(cycle: cycle, profile: profile),
        ]
    }

    /// 7 日目: 周回ごとに巡回するエピックコスメ（パス・ランク・イベント報酬と重ならないもの）。所持済みなら Gem 100。
    private static func loginDay7Reward(cycle: Int, profile: Profile?, master: MasterData = .shared) -> MailAttachment {
        let reserved = rewardTrackCosmeticIDs
        var epics = master.cosmetics.filter { $0.rarity == .epic && !reserved.contains($0.cosmeticID) }
        if epics.isEmpty { epics = master.cosmetics.filter { $0.rarity == .epic } }
        guard !epics.isEmpty else { return MailAttachment(kind: .gem, amount: 100) }
        let pick = epics[cycle % epics.count].cosmeticID
        if let profile, profile.ownedCosmeticIDs.contains(pick) {
            return MailAttachment(kind: .gem, amount: 100)
        }
        return MailAttachment(kind: .cosmetic, amount: 1, refID: pick)
    }

    static func passLevel(xp: Int) -> Int { min(passMaxLevel, max(0, xp) / passXPPerLevel) }

    /// 現在の段階内の XP（0〜999。最大段階では 0）。
    static func passXPInLevel(xp: Int) -> Int {
        passLevel(xp: xp) >= passMaxLevel ? 0 : max(0, xp) % passXPPerLevel
    }

    /// 受取可能なパス報酬（無料 + プレミアム）の数。
    static func claimablePassRewardCount(profile: Profile) -> Int {
        let level = passLevel(xp: profile.pass.xp)
        guard level > 0 else { return 0 }
        var n = 0
        for r in passRewardTable where r.level <= level {
            if r.free != nil && !profile.pass.claimedFree.contains(r.level) { n += 1 }
            if profile.pass.hasPremium && r.premium != nil && !profile.pass.claimedPremium.contains(r.level) { n += 1 }
        }
        return n
    }

    static func addPassXP(_ amount: Int, to profile: inout Profile) {
        guard amount > 0 else { return }
        profile.pass.xp = min(passXPPerLevel * passMaxLevel, profile.pass.xp + amount)
    }

    static func unreadNoticeCount(profile: Profile) -> Int {
        noticeList.filter { !profile.readNoticeIDs.contains($0.id) }.count
    }

    static func markNoticeRead(id: String, profile: inout Profile) {
        if !profile.readNoticeIDs.contains(id) { profile.readNoticeIDs.append(id) }
    }

    static func unreadMailCount(profile: Profile) -> Int {
        profile.mail.filter { !$0.read || (!$0.claimed && !$0.attachments.isEmpty) }.count
    }

    static func achievementDef(id: String) -> AchievementDef? { achievementTable.first { $0.def.id == id }?.def }

    /// 解除済みの実績数。
    static func unlockedAchievementCount(profile: Profile) -> Int {
        achievementTable.filter { profile.achievements[$0.def.id]?.unlockedAt != nil }.count
    }

    /// 解除済み・未受取の実績数。
    static func claimableAchievementCount(profile: Profile) -> Int {
        achievementTable.filter {
            guard let p = profile.achievements[$0.def.id] else { return false }
            return p.unlockedAt != nil && !p.claimed
        }.count
    }

    /// 添付の表示名（例: "StarlightCoin ×100"）。
    static func describe(_ attachment: MailAttachment, master: MasterData = .shared) -> String {
        switch attachment.kind {
        case .coin: return "StarlightCoin ×\(attachment.amount.formatted())"
        case .gem: return L("AstralGem（無償）×\(attachment.amount.formatted())", "AstralGem (free) ×\(attachment.amount.formatted())")
        case .passXP: return L("パス XP +\(attachment.amount.formatted())", "Pass XP +\(attachment.amount.formatted())")
        case .cosmetic:
            guard let id = attachment.refID, let def = master.cosmetic(id) else { return L("コスメ", "Cosmetic") }
            return MasterText.cosmetic(def)
        case .hero:
            guard let id = attachment.refID, let def = master.hero(id) else { return L("ヒーロー", "Hero") }
            return L("ヒーロー解放: ", "Hero unlock: ") + MasterText.hero(def)
        }
    }

    // MARK: - 更新

    /// 日付・週が変わっていればデイリー / ウィークリーを入れ替える（達成済み未受取の報酬はメールで届ける）。
    /// 端末時刻が過去に戻った場合は入れ替えない。イベントミッションの枠は週をまたいで持ち越し、イベント終了で外す。
    static func refreshMissions(profile: inout Profile, now: Date) {
        let dk = dayKey(now)
        let storedDay = profile.missions.dayKey
        if storedDay.isEmpty || dk > storedDay {
            mailUnclaimedRewards(profile.missions.daily, profile: &profile, now: now)
            profile.missions.dayKey = dk
            profile.missions.daily = dailySelection(dayKey: dk).map { MissionProgress(id: $0) }
        } else if profile.missions.daily.isEmpty {
            profile.missions.daily = dailySelection(dayKey: storedDay).map { MissionProgress(id: $0) }
        }
        let wk = weekKey(now)
        let storedWeek = profile.missions.weeklyKey
        var eventEntries: [MissionProgress] = []
        for p in profile.missions.weekly where isEventMission(p.id) && !eventEntries.contains(where: { $0.id == p.id }) {
            eventEntries.append(p)
        }
        if storedWeek.isEmpty || wk > storedWeek {
            mailUnclaimedRewards(profile.missions.weekly.filter { !isEventMission($0.id) }, profile: &profile, now: now)
            profile.missions.weeklyKey = wk
            profile.missions.weekly = weeklyPool.map { MissionProgress(id: $0.id) } + eventEntries
        } else {
            // 欠けたウィークリー枠の補完と並び順の正規化（ウィークリー 4 件 → イベント）
            let regular = weeklyPool.map { def in
                profile.missions.weekly.first { $0.id == def.id } ?? MissionProgress(id: def.id)
            }
            let normalized = regular + eventEntries
            if normalized != profile.missions.weekly { profile.missions.weekly = normalized }
        }
        closeEndedEventMissions(profile: &profile, now: now)
    }

    /// 終了したイベントのミッション枠を外し、達成済み・未受取の報酬をメールで届ける。
    private static func closeEndedEventMissions(profile: inout Profile, now: Date) {
        let ended = profile.missions.weekly.filter { p in
            guard isEventMission(p.id) else { return false }
            guard let e = event(containingMission: p.id) else { return true }
            return now >= e.end
        }
        guard !ended.isEmpty else { return }
        mailUnclaimedRewards(ended, profile: &profile, now: now,
                             title: L("未受取のイベント報酬", "Unclaimed event rewards"),
                             body: L("終了したイベントのミッション報酬をお届けします。",
                                     "Here are the mission rewards from an event that has ended."))
        let endedIDs = ended.map(\.id)
        profile.missions.weekly.removeAll { endedIDs.contains($0.id) }
    }

    private static func mailUnclaimedRewards(_ list: [MissionProgress], profile: inout Profile, now: Date,
                                             title: String? = nil, body: String? = nil) {
        var attachments: [MailAttachment] = []
        for p in list where !p.claimed {
            guard let def = missionDef(id: p.id), p.progress >= def.target else { continue }
            attachments += rewardAttachments(def)
        }
        guard !attachments.isEmpty else { return }
        sendMail(to: &profile,
                 title: title ?? L("未受取のミッション報酬", "Unclaimed mission rewards"),
                 body: body ?? L("期限が切れたミッションの報酬をお届けします。", "Here are the rewards from missions that have ended."),
                 attachments: mergeAttachments(attachments), now: now,
                 expiresAt: calendar.date(byAdding: .day, value: loginMailLifetimeDays, to: now))
    }

    /// 1 試合分の進捗をデイリー / ウィークリー / 開催中イベントのミッションに加算する。進捗したミッション ID を返す。
    @discardableResult
    static func recordMatch(_ input: MatchProgressInput, profile: inout Profile, now: Date) -> [String] {
        refreshMissions(profile: &profile, now: now)
        var progressed: [String] = []
        for i in profile.missions.daily.indices {
            if advance(&profile.missions.daily[i], input: input) { progressed.append(profile.missions.daily[i].id) }
        }
        for i in profile.missions.weekly.indices where !isEventMission(profile.missions.weekly[i].id) {
            if advance(&profile.missions.weekly[i], input: input) { progressed.append(profile.missions.weekly[i].id) }
        }
        for event in activeEvents(now: now) {
            for id in event.missionIDs {
                guard let def = missionDef(id: id), increment(for: def, input: input) > 0 else { continue }
                // 初めて進捗した時に枠を作る
                if !profile.missions.weekly.contains(where: { $0.id == id }) {
                    profile.missions.weekly.append(MissionProgress(id: id))
                }
                guard let i = profile.missions.weekly.firstIndex(where: { $0.id == id }) else { continue }
                if advance(&profile.missions.weekly[i], input: input) { progressed.append(id) }
            }
        }
        return progressed
    }

    private static func advance(_ p: inout MissionProgress, input: MatchProgressInput) -> Bool {
        guard !p.claimed, let def = missionDef(id: p.id), p.progress < def.target else { return false }
        let inc = increment(for: def, input: input)
        guard inc > 0 else { return false }
        p.progress = min(def.target, max(0, p.progress) + inc)
        return true
    }

    private static func increment(for def: MissionDef, input: MatchProgressInput) -> Int {
        switch def.kind {
        case .playMatches: return 1
        case .winMatches: return input.won ? 1 : 0
        case .kills: return max(0, input.kills)
        case .assists: return max(0, input.assists)
        case .creepScore: return max(0, input.creepScore)
        case .destroyTowers: return max(0, input.towersDestroyed)
        case .useHeroRole: return (def.role == nil || def.role == input.role) ? 1 : 0
        case .dealDamage:
            guard input.damageToHeroes.isFinite else { return 0 }
            return Int(min(1_000_000_000, max(0, input.damageToHeroes)))
        }
    }

    // MARK: - 実績

    /// 全実績を現在のプロフィールで評価し、新たに解除した実績 ID を返す（試合後・購入後・起動時に呼ぶ）。
    @discardableResult
    static func evaluateAchievements(profile: inout Profile, master: MasterData, now: Date) -> [String] {
        var unlocked: [String] = []
        for (def, metric) in achievementTable {
            let value = min(def.target, metricValue(metric, profile: profile, master: master))
            var entry = profile.achievements[def.id] ?? AchievementProgress()
            var changed = false
            if !entry.progress.isFinite {
                entry.progress = 0
                changed = true
            }
            if value > entry.progress {
                entry.progress = value
                changed = true
            }
            if entry.unlockedAt == nil && entry.progress >= def.target {
                entry.unlockedAt = now
                unlocked.append(def.id)
                changed = true
            }
            if changed { profile.achievements[def.id] = entry }
        }
        return unlocked
    }

    private static func metricValue(_ metric: AchievementMetric, profile: Profile, master: MasterData) -> Double {
        let c = profile.career
        switch metric {
        case .wins: return Double(c.wins)
        case .matches: return Double(c.matches)
        case .kills: return Double(c.kills)
        case .assists: return Double(c.assists)
        case .pentaKills: return Double(c.pentaKills)
        case .mvps: return Double(c.mvps)
        case .longestWinStreak: return Double(c.longestWinStreak)
        case .totalDamage: return c.totalDamage.isFinite ? c.totalDamage : 0
        case .rolePlayed(let role): return rolesPlayed(profile: profile, master: master).contains(role) ? 1 : 0
        case .allRolesPlayed: return Double(rolesPlayed(profile: profile, master: master).count)
        case .rankReached(let tier): return RankService.hasReached(tier, profile: profile) ? 1 : 0
        case .cosmeticsOwned: return Double(Set(profile.ownedCosmeticIDs).count)
        case .heroesOwned: return Double(Set(profile.ownedHeroIDs).count)
        case .accountLevel: return Double(profile.accountLevel)
        }
    }

    /// 1 試合以上プレイしたロール（Role.allCases 順）。
    static func rolesPlayed(profile: Profile, master: MasterData) -> [Role] {
        var played: [Role] = []
        for hero in master.heroes where (profile.career.perHero[hero.heroID]?.matches ?? 0) > 0 {
            if !played.contains(hero.role) { played.append(hero.role) }
        }
        return Role.allCases.filter { played.contains($0) }
    }

    // MARK: - 受取（冪等。受取済み・条件未達なら nil / 空配列）

    static func claimMission(id: String, profile: inout Profile, now: Date) -> [MailAttachment]? {
        refreshMissions(profile: &profile, now: now)
        guard let def = missionDef(id: id) else { return nil }
        // イベントミッションは開催期間中のみ受け取れる（終了時の未受取分はメールで届く）
        if isEventMission(id) && !isEventMissionActive(id, now: now) { return nil }
        if let i = profile.missions.daily.firstIndex(where: { $0.id == id }) {
            guard !profile.missions.daily[i].claimed, profile.missions.daily[i].progress >= def.target else { return nil }
            profile.missions.daily[i].claimed = true
        } else if let i = profile.missions.weekly.firstIndex(where: { $0.id == id }) {
            guard !profile.missions.weekly[i].claimed, profile.missions.weekly[i].progress >= def.target else { return nil }
            profile.missions.weekly[i].claimed = true
        } else {
            return nil
        }
        let granted = rewardAttachments(def).map { grantResolved($0, to: &profile) }
        reevaluateAfterGrant(granted, profile: &profile, now: now)
        return granted
    }

    /// 達成済みのミッションをまとめて受け取る。
    static func claimAllMissions(profile: inout Profile, now: Date) -> [MailAttachment] {
        refreshMissions(profile: &profile, now: now)
        let ids = profile.missions.daily.map(\.id) + profile.missions.weekly.map(\.id)
        var result: [MailAttachment] = []
        for id in ids {
            if let r = claimMission(id: id, profile: &profile, now: now) { result += r }
        }
        return mergeAttachments(result)
    }

    /// コスメ・ヒーローが増える受取の後に実績（所持数）を評価し直す。
    private static func reevaluateAfterGrant(_ granted: [MailAttachment], profile: inout Profile, now: Date) {
        guard granted.contains(where: { $0.kind == .cosmetic || $0.kind == .hero }) else { return }
        evaluateAchievements(profile: &profile, master: .shared, now: now)
    }

    static func rewardAttachments(_ def: MissionDef) -> [MailAttachment] {
        var list: [MailAttachment] = []
        if def.rewardCoins > 0 { list.append(MailAttachment(kind: .coin, amount: def.rewardCoins)) }
        if def.rewardPassXP > 0 { list.append(MailAttachment(kind: .passXP, amount: def.rewardPassXP)) }
        return list + def.extraRewards
    }

    static func claimPass(level: Int, premium: Bool, profile: inout Profile) -> MailAttachment? {
        guard (1...passMaxLevel).contains(level), passLevel(xp: profile.pass.xp) >= level,
              let reward = passRewardTable.first(where: { $0.level == level }) else { return nil }
        let granted: MailAttachment
        if premium {
            guard profile.pass.hasPremium, !profile.pass.claimedPremium.contains(level), let a = reward.premium else { return nil }
            profile.pass.claimedPremium.append(level)
            granted = grantResolved(a, to: &profile)
        } else {
            guard !profile.pass.claimedFree.contains(level), let a = reward.free else { return nil }
            profile.pass.claimedFree.append(level)
            granted = grantResolved(a, to: &profile)
        }
        reevaluateAfterGrant([granted], profile: &profile, now: Date())
        return granted
    }

    /// 受取可能なパス報酬をすべて受け取る。
    static func claimAllPass(profile: inout Profile) -> [MailAttachment] {
        var result: [MailAttachment] = []
        for level in 1...passMaxLevel {
            if let a = claimPass(level: level, premium: false, profile: &profile) { result.append(a) }
            if let a = claimPass(level: level, premium: true, profile: &profile) { result.append(a) }
        }
        return result
    }

    static func claimAchievement(id: String, profile: inout Profile, now: Date) -> Int? {
        guard let def = achievementDef(id: id), var entry = profile.achievements[id],
              entry.unlockedAt != nil, !entry.claimed else { return nil }
        entry.claimed = true
        profile.achievements[id] = entry
        profile.freeGem += def.rewardGems
        return def.rewardGems
    }

    static func claimMail(id: UUID, profile: inout Profile) -> [MailAttachment] {
        claimMail(id: id, profile: &profile, now: Date())
    }

    static func claimMail(id: UUID, profile: inout Profile, now: Date) -> [MailAttachment] {
        guard let i = profile.mail.firstIndex(where: { $0.id == id }) else { return [] }
        profile.mail[i].read = true
        guard !profile.mail[i].claimed, !isExpired(profile.mail[i], now: now) else { return [] }
        profile.mail[i].claimed = true
        let attachments = profile.mail[i].attachments
        let granted = attachments.map { grantResolved($0, to: &profile) }
        reevaluateAfterGrant(granted, profile: &profile, now: now)
        return granted
    }

    static func claimAllMail(profile: inout Profile) -> [MailAttachment] {
        claimAllMail(profile: &profile, now: Date())
    }

    static func claimAllMail(profile: inout Profile, now: Date) -> [MailAttachment] {
        var result: [MailAttachment] = []
        for id in profile.mail.map(\.id) {
            result += claimMail(id: id, profile: &profile, now: now)
        }
        return mergeAttachments(result)
    }

    static func markMailRead(id: UUID, profile: inout Profile) {
        if let i = profile.mail.firstIndex(where: { $0.id == id }) { profile.mail[i].read = true }
    }

    static func isExpired(_ mail: MailItem, now: Date) -> Bool {
        if let e = mail.expiresAt { return e <= now }
        return false
    }

    /// 添付を所持品へ反映（コイン・Gem(無償)・コスメ・ヒーロー・パス XP）。
    static func grant(_ attachment: MailAttachment, to profile: inout Profile) {
        grantResolved(attachment, to: &profile)
    }

    /// 添付を反映し、実際に付与した内容を返す（所持済みコスメ → 返還 Gem、所持済みヒーロー → 返還 Coin に変換）。
    @discardableResult
    static func grantResolved(_ attachment: MailAttachment, to profile: inout Profile,
                              master: MasterData = .shared) -> MailAttachment {
        let amount = max(0, attachment.amount)
        switch attachment.kind {
        case .coin:
            profile.starlightCoin += amount
            return attachment
        case .gem:
            profile.freeGem += amount
            return attachment
        case .passXP:
            addPassXP(amount, to: &profile)
            return attachment
        case .cosmetic:
            guard let id = attachment.refID, master.cosmetic(id) != nil else {
                return MailAttachment(kind: .gem, amount: 0)
            }
            if profile.ownedCosmeticIDs.contains(id) {
                let refund = EconomyService.duplicateRefundGems(cosmeticID: id, master: master)
                profile.freeGem += refund
                return MailAttachment(kind: .gem, amount: refund)
            }
            profile.ownedCosmeticIDs.append(id)
            return attachment
        case .hero:
            guard let id = attachment.refID, master.hero(id) != nil else {
                return MailAttachment(kind: .coin, amount: 0)
            }
            if profile.ownedHeroIDs.contains(id) {
                let refund = EconomyService.heroDuplicateRefundCoins(heroID: id, master: master)
                profile.starlightCoin += refund
                return MailAttachment(kind: .coin, amount: refund)
            }
            profile.ownedHeroIDs.append(id)
            return attachment
        }
    }

    /// 同種の通貨・XP をまとめる（コスメ・ヒーローはそのまま）。
    static func mergeAttachments(_ list: [MailAttachment]) -> [MailAttachment] {
        var result: [MailAttachment] = []
        for a in list {
            if a.kind == .coin || a.kind == .gem || a.kind == .passXP,
               let i = result.firstIndex(where: { $0.kind == a.kind && $0.refID == nil }) {
                result[i].amount += a.amount
            } else {
                result.append(a)
            }
        }
        return result.filter { $0.amount > 0 || $0.refID != nil }
    }

    // MARK: - メール

    /// メールを先頭（新しい順）に追加する。
    static func sendMail(to profile: inout Profile, title: String, body: String, attachments: [MailAttachment],
                         now: Date, expiresAt: Date? = nil) {
        let mail = MailItem(date: now, title: title, body: body, attachments: attachments, expiresAt: expiresAt)
        profile.mail.insert(mail, at: 0)
        pruneMail(profile: &profile, now: now)
    }

    /// 期限切れの削除と件数上限の維持（受取済み・添付なしの古いものから削除）。
    static func pruneMail(profile: inout Profile, now: Date) {
        profile.mail.removeAll { isExpired($0, now: now) }
        while profile.mail.count > maxMailCount {
            if let i = profile.mail.lastIndex(where: { $0.claimed || $0.attachments.isEmpty }) {
                profile.mail.remove(at: i)
            } else {
                profile.mail.removeLast()
            }
        }
    }

    // MARK: - 起動時

    /// 起動時: 初回ウェルカムメール・ログインボーナス・日替わり更新・期限切れメール整理・実績評価。
    static func onLaunch(profile: inout Profile, master: MasterData, now: Date) {
        let key = dayKey(now)
        if profile.totalLoginDays == 0 && profile.lastLoginDayKey.isEmpty {
            sendWelcomeMail(to: &profile, master: master, now: now)
        }
        // 端末時刻を戻しての再取得を防ぐため、日付キーが進んだ時だけ付与する
        if profile.lastLoginDayKey.isEmpty || key > profile.lastLoginDayKey {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now).map(dayKey) ?? ""
            profile.loginStreak = profile.lastLoginDayKey == yesterday ? profile.loginStreak + 1 : 1
            profile.lastLoginDayKey = key
            profile.totalLoginDays += 1
            sendLoginBonus(to: &profile, now: now)
        }
        refreshMissions(profile: &profile, now: now)
        pruneMail(profile: &profile, now: now)
        evaluateAchievements(profile: &profile, master: master, now: now)
    }

    private static func sendWelcomeMail(to profile: inout Profile, master: MasterData, now: Date) {
        var attachments = [MailAttachment(kind: .coin, amount: 500), MailAttachment(kind: .gem, amount: 100)]
        if let frame = master.cosmetics.first(where: { $0.type == .avatarFrame }) {
            attachments.append(MailAttachment(kind: .cosmetic, amount: 1, refID: frame.cosmeticID))
        }
        sendMail(to: &profile,
                 title: L("VELSIA へようこそ！", "Welcome to VELSIA!"),
                 body: L("星環の戦場へようこそ。はじめての戦いに役立つ贈り物をお届けします。受け取って冒険を始めましょう。",
                         "Welcome to the Battlefield of the Star Ring. Here is a gift to help you in your first battles."),
                 attachments: attachments, now: now)
    }

    private static func sendLoginBonus(to profile: inout Profile, now: Date) {
        let dayIndex = (profile.totalLoginDays - 1) % 7
        let reward = loginBonusCalendar(profile: profile)[dayIndex]
        let day = dayIndex + 1
        sendMail(to: &profile,
                 title: L("ログインボーナス \(day) 日目", "Login Bonus: Day \(day)"),
                 body: L("本日のログインボーナスです。7 日ごとに特別な報酬がもらえます。",
                         "Here is today's login bonus. A special reward awaits every 7th day."),
                 attachments: [reward], now: now,
                 expiresAt: calendar.date(byAdding: .day, value: loginMailLifetimeDays, to: now))
    }
}
