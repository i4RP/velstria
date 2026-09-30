import SwiftUI
import VelstriaCore

// 担当: battle-hud。UI029 スコアボード: 両チーム（ポートレート・レベル・K/D/A・CS・装備・スペル（味方は CD））、
// チームのキル/タワー/オブジェクト、試合時間。

struct HUDScoreboardPanel: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let sb = model.scoreboard
        let cb = model.settings.colorblindMode
        VStack(spacing: 8) {
            header(sb, colorblind: cb)
            HStack(alignment: .top, spacing: 10) {
                teamColumn(sb.blue, team: .blue, colorblind: cb)
                teamColumn(sb.red, team: .red, colorblind: cb)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.07, green: 0.08, blue: 0.18).opacity(0.96),
                                              Color(red: 0.02, green: 0.03, blue: 0.08).opacity(0.96)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(HUDStyle.rim, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scoreboard_panel")
    }

    private func header(_ sb: HUDScoreboardSnapshot, colorblind: Bool) -> some View {
        let blue = Theme.teamColor(.blue, colorblind: colorblind)
        let red = Theme.teamColor(.red, colorblind: colorblind)
        return HStack(spacing: 12) {
            teamStats(kills: sb.blueKills, towers: sb.blueTowers, wyrms: sb.blueWyrms, colossi: sb.blueColossi, color: blue,
                      name: HUDText.teamName(.blue), leading: true)
            Spacer(minLength: 4)
            VStack(spacing: 0) {
                Text(L("スコアボード", "Scoreboard"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                Text(HUDStyle.clock(Double(sb.seconds)))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 4)
            teamStats(kills: sb.redKills, towers: sb.redTowers, wyrms: sb.redWyrms, colossi: sb.redColossi, color: red,
                      name: HUDText.teamName(.red), leading: false)
            Button { model.closePanel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L("閉じる", "Close"))
            .accessibilityIdentifier("scoreboard_close")
        }
    }

    private func teamStats(kills: Int, towers: Int, wyrms: Int, colossi: Int, color: Color, name: String,
                           leading: Bool) -> some View {
        HStack(spacing: 10) {
            if !leading { Spacer(minLength: 0) }
            Text(name)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            stat("\(kills)", symbol: "bolt.fill", label: L("キル", "Kills"))
            stat("\(towers)", symbol: "building.columns.fill", label: L("タワー", "Towers"))
            stat("\(wyrms)", symbol: "hurricane", label: L("星喰竜", "Wyrm"))
            stat("\(colossi)", symbol: "crown.fill", label: L("巨像", "Colossus"))
            if leading { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ value: String, symbol: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.gold)
            Text(value).font(.system(size: 14, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }

    private func teamColumn(_ rows: [HUDScoreRow], team: Team, colorblind: Bool) -> some View {
        let color = Theme.teamColor(team, colorblind: colorblind)
        return VStack(spacing: 4) {
            if rows.isEmpty {
                Text(L("（敵チームなし）", "(No opposing team)"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            ForEach(rows) { row in
                HUDScoreRowView(row: row, color: color)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

struct HUDScoreRowView: View, Equatable {
    let row: HUDScoreRow
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                HeroPortraitView(heroID: row.heroID, size: 32, showsRole: false)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(row.isHuman ? Theme.gold : color, lineWidth: row.isHuman ? 2 : 1))
                    .saturation(row.isDead ? 0 : 1)
                    .overlay {
                        if row.isDead {
                            Text("\(Int(row.respawn))")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: .black, radius: 2)
                        }
                    }
                Text("\(row.level)")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 15, height: 15)
                    .background(Circle().fill(Color.black.opacity(0.85)))
                    .overlay(Circle().strokeBorder(HUDStyle.xp, lineWidth: 1))
                    .offset(x: 4, y: 4)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(MasterData.shared.hero(row.heroID).map { MasterText.hero($0) } ?? row.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(row.isHuman ? Theme.gold : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(row.kills) / \(row.deaths) / \(row.assists)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 78, alignment: .leading)
            VStack(spacing: 0) {
                Text("CS").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                Text("\(row.creepScore)").font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 28)
            HStack(spacing: 2) {
                ForEach(0..<Balance.itemSlots, id: \.self) { k in
                    ZStack {
                        RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.45))
                        if k < row.items.count, let item = MasterData.shared.item(row.items[k]) {
                            ItemIconView(item: item, size: 18)
                        }
                    }
                    .frame(width: 19, height: 19)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                ForEach(Array(row.spells.prefix(2).enumerated()), id: \.offset) { k, spellID in
                    ZStack {
                        SpellIconView(spellID: spellID, size: 20)
                        if let cds = row.spellCooldowns, k < cds.count, cds[k] > 0 {
                            Circle().fill(Color.black.opacity(0.6))
                            Text("\(Int(cds[k]))")
                                .font(.system(size: 8, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 20, height: 20)
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(row.isHuman ? Theme.gold.opacity(0.10) : Color.clear))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let name = MasterData.shared.hero(row.heroID).map { MasterText.hero($0) } ?? row.name
        return L("\(name) レベル \(row.level) \(row.kills)/\(row.deaths)/\(row.assists) CS \(row.creepScore)",
                 "\(name) level \(row.level) \(row.kills)/\(row.deaths)/\(row.assists) CS \(row.creepScore)")
    }
}
