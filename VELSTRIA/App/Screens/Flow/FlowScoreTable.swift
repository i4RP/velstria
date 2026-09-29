import SwiftUI
import VelstriaCore

// 担当: ui-flow。両チームの成績表（リザルト UI032・戦績詳細 UI016 で共用）。

struct MatchScoreTable: View {
    let summary: MatchSummary
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 12) {
            ForEach(orderedTeams, id: \.self) { team in
                TeamScoreSection(team: team, summary: summary, colorblind: app.profile.settings.colorblindMode)
            }
        }
    }

    /// 人間のチームを上に。観戦ではブルーが上。
    private var orderedTeams: [Team] {
        let first = summary.humanTeam ?? .blue
        return [first, first.opponent]
    }
}

private struct TeamScoreSection: View {
    let team: Team
    let summary: MatchSummary
    let colorblind: Bool

    private var players: [PlayerSummary] {
        summary.players.filter { $0.team == team }.sorted { $0.position.rawValue < $1.position.rawValue }
    }

    private var resultLabel: String? {
        guard let w = summary.winner else { return nil }
        return w == team ? L("勝利", "Victory") : L("敗北", "Defeat")
    }

    var body: some View {
        let color = Theme.teamColor(team, colorblind: colorblind)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: FlowText.teamSymbol(team)).foregroundStyle(color)
                Text(FlowText.team(team)).font(Theme.heading(14)).foregroundStyle(Theme.textPrimary)
                if let resultLabel {
                    Text(resultLabel)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(summary.winner == team ? Color.black.opacity(0.85) : Theme.textPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(summary.winner == team ? Theme.gold : Color.white.opacity(0.15)))
                }
                Spacer()
                let kills = team.rawValue < summary.teamKills.count ? summary.teamKills[team.rawValue] : 0
                let towers = team.rawValue < summary.towersDestroyed.count ? summary.towersDestroyed[team.rawValue] : 0
                Label("\(kills)", systemImage: "scope").font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel(L("キル \(kills)", "\(kills) kills"))
                Label("\(towers)", systemImage: "building.columns.fill").font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel(L("タワー破壊 \(towers)", "\(towers) towers destroyed"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.05)], startPoint: .leading, endPoint: .trailing))

            ScoreHeaderRow()
            ForEach(players) { p in
                ScoreRow(player: p)
                if p.id != players.last?.id {
                    Divider().overlay(Color.white.opacity(0.06))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .glass(cornerRadius: 12, tint: color.opacity(0.6))
    }
}

/// 列幅（ヘッダと行で共有）。
private enum ScoreColumns {
    static let level: CGFloat = 30
    static let kda: CGFloat = 76
    static let cs: CGFloat = 38
    static let gold: CGFloat = 50
    static let damage: CGFloat = 54
    static let grade: CGFloat = 30
}

private struct ScoreHeaderRow: View {
    var body: some View {
        HStack(spacing: 6) {
            Text(L("プレイヤー", "Player")).frame(maxWidth: .infinity, alignment: .leading)
            Text("Lv").frame(width: ScoreColumns.level)
            Text("K/D/A").frame(width: ScoreColumns.kda)
            Text("CS").frame(width: ScoreColumns.cs)
            Text(L("ゴールド", "Gold")).frame(width: ScoreColumns.gold)
            Text(L("ダメージ", "Damage")).frame(width: ScoreColumns.damage)
            Text(L("評価", "Grade")).frame(width: ScoreColumns.grade)
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}

private struct ScoreRow: View {
    let player: PlayerSummary
    @Environment(AppModel.self) private var app

    var body: some View {
        let s = player.score
        HStack(spacing: 6) {
            HStack(spacing: 7) {
                HeroPortraitView(heroID: player.heroID, size: 28, showsRole: false)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(player.displayName)
                            .font(Theme.heading(12))
                            .foregroundStyle(player.isHuman ? Theme.gold : Theme.textPrimary)
                            .lineLimit(1)
                        if player.isMVP { MVPBadge(compact: true) }
                    }
                    HStack(spacing: 3) {
                        Image(systemName: FlowText.positionSymbol(player.position)).font(.system(size: 9))
                        Text(heroName).lineLimit(1)
                    }
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(player.level)").frame(width: ScoreColumns.level)
            Text(FlowText.kda(s.kills, s.deaths, s.assists)).frame(width: ScoreColumns.kda)
            Text("\(s.creepScore)").frame(width: ScoreColumns.cs)
            Text(FlowText.compactNumber(s.goldEarned)).frame(width: ScoreColumns.gold)
            Text(FlowText.compactNumber(s.damageToHeroes)).frame(width: ScoreColumns.damage)
            GradeBadge(grade: player.grade, size: 22).frame(width: ScoreColumns.grade)
        }
        .font(Theme.mono(12))
        .foregroundStyle(Theme.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(player.isHuman ? Theme.gold.opacity(0.12) : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var heroName: String {
        app.master.hero(player.heroID).map { MasterText.hero($0) } ?? player.heroID
    }

    private var accessibilityText: String {
        let s = player.score
        var t = "\(player.displayName)、\(heroName)、Lv \(player.level)、"
        t += L("キル \(s.kills) デス \(s.deaths) アシスト \(s.assists)、CS \(s.creepScore)、評価 \(player.grade)",
               "\(s.kills) kills \(s.deaths) deaths \(s.assists) assists, CS \(s.creepScore), grade \(player.grade)")
        if player.isMVP { t += "、MVP" }
        return t
    }
}
