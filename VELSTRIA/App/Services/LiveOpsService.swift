import Foundation
import VelstriaCore

// 担当: app-services（最小実装。ログインボーナス・デイリー/ウィークリーミッション・スターパス・実績・メール・
// お知らせ・イベント定義と受取処理を実装すること）

struct MissionDef: Identifiable, Equatable {
    enum Kind: String { case playMatches, winMatches, kills, assists, creepScore, destroyTowers, useHeroRole, dealDamage }
    var id: String
    var titleJa: String
    var titleEn: String
    var kind: Kind
    var target: Int
    var rewardCoins: Int
    var rewardPassXP: Int
}

struct AchievementDef: Identifiable, Equatable {
    var id: String
    var titleJa: String
    var titleEn: String
    var detailJa: String
    var detailEn: String
    var target: Double
    var rewardGems: Int
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
}

enum LiveOpsService {
    static let passXPPerLevel = 1000
    static let passMaxLevel = 30

    static var dailyMissionPool: [MissionDef] { [] }
    static var achievements: [AchievementDef] { [] }
    static var notices: [NoticeDef] { [] }
    static var events: [EventDef] { [] }

    static func passRewards() -> [PassReward] { [] }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: 参照（UI が使う）

    /// 今日のデイリーミッション（profile.missions.daily の ID 順）。
    static func dailyMissions(profile: Profile) -> [MissionDef] { [] }
    static func weeklyMissions(profile: Profile) -> [MissionDef] { [] }
    static func missionDef(id: String) -> MissionDef? { nil }
    static func activeEvents(now: Date) -> [EventDef] { events.filter { $0.start <= now && now < $0.end } }
    /// 7 日周期のログインボーナス（index 0 = 1 日目）。
    static func loginBonusCalendar() -> [MailAttachment] { [] }
    static func passLevel(xp: Int) -> Int { min(passMaxLevel, xp / passXPPerLevel) }

    // MARK: 受取（冪等。受取済み・条件未達なら nil / 空配列）

    static func claimMission(id: String, profile: inout Profile, now: Date) -> [MailAttachment]? { nil }
    static func claimPass(level: Int, premium: Bool, profile: inout Profile) -> MailAttachment? { nil }
    static func claimAchievement(id: String, profile: inout Profile, now: Date) -> Int? { nil }
    static func claimMail(id: UUID, profile: inout Profile) -> [MailAttachment] { [] }
    static func claimAllMail(profile: inout Profile) -> [MailAttachment] { [] }
    /// 添付を所持品へ反映（コイン・Gem(無償)・コスメ・ヒーロー・パス XP）。
    static func grant(_ attachment: MailAttachment, to profile: inout Profile) {}

    /// 起動時: ログインボーナス・日替わり更新・初回メール。
    static func onLaunch(profile: inout Profile, master: MasterData, now: Date) {
        let key = dayKey(now)
        if profile.lastLoginDayKey != key {
            profile.lastLoginDayKey = key
            profile.totalLoginDays += 1
        }
    }
}
