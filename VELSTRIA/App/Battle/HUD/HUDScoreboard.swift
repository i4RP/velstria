import SwiftUI
import VelstriaCore

// 担当: battle-hud。UI029 スコアボード: 両チーム（ポートレート・レベル・K/D/A・CS・装備・スペル（味方は CD））、
// チームのキル/タワー/オブジェクト、試合時間。
// 観戦者: 行をタップでそのヒーローを追従（スコアボードを閉じる）。装備の価値・与ダメージの列を足す（狭い画面はスペルを省く）。
// リプレイは記録した本人の行を金色で強調する。

struct HUDScoreboardPanel: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let sb = model.scoreboard
        let cb = model.settings.colorblindMode
        let metrics = model.isSpectating ? HUDScoreRowMetrics.spectator(rowWidth: Self.rowWidth(layout)) : nil
        VStack(spacing: 8) {
            header(sb, colorblind: cb)
            HStack(alignment: .top, spacing: 10) {
                teamColumn(sb.blue, team: .blue, colorblind: cb, metrics: metrics)
                teamColumn(sb.red, team: .red, colorblind: cb, metrics: metrics)
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

    /// 1 行の幅（パネルの左右の余白・列の間隔・列の内側の余白を除く）。
    static func rowWidth(_ layout: HUDLayout) -> CGFloat {
        let panel = layout.trailingEdge - layout.leadingEdge - 8
        return (panel - 24 - 10) / 2 - 12
    }

    private func teamColumn(_ rows: [HUDScoreRow], team: Team, colorblind: Bool, metrics: HUDScoreRowMetrics?) -> some View {
        let color = Theme.teamColor(team, colorblind: colorblind)
        return VStack(spacing: 4) {
            if rows.isEmpty {
                Text(L("（敵チームなし）", "(No opposing team)"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            ForEach(rows) { row in
                if let metrics {
                    // 観戦者: タップでそのヒーローを追従
                    Button { model.scoreboardRowTapped(row.id) } label: {
                        HUDScoreRowView(row: row, color: color, metrics: metrics)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HUDPressStyle())
                    .accessibilityHint(L("タップで追従", "Tap to follow"))
                    .accessibilityIdentifier("scoreboard_row_\(row.id)")
                } else {
                    HUDScoreRowView(row: row, color: color)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

/// 観戦者のスコアボードの列の出し分け（行の幅から決める）。
struct HUDScoreRowMetrics: Equatable {
    var showsSpells: Bool
    var itemSize: CGFloat
    var nameWidth: CGFloat
    var spacing: CGFloat

    static func spectator(rowWidth: CGFloat) -> HUDScoreRowMetrics {
        if rowWidth >= 380 { return HUDScoreRowMetrics(showsSpells: true, itemSize: 17, nameWidth: 72, spacing: 5) }
        if rowWidth >= 320 { return HUDScoreRowMetrics(showsSpells: false, itemSize: 16, nameWidth: 70, spacing: 5) }
        return HUDScoreRowMetrics(showsSpells: false, itemSize: 12, nameWidth: 62, spacing: 4)
    }

    /// 行の中身の幅（ポートレート・名前・CS・装備の価値・与ダメ・装備・スペルと間隔）。
    var contentWidth: CGFloat {
        let items = CGFloat(Balance.itemSlots) * itemSize + CGFloat(Balance.itemSlots - 1)
        var w: CGFloat = 30 + nameWidth + 24 + 32 + 32 + items
        var columns: CGFloat = 6
        if showsSpells {
            w += 38
            columns += 1
        }
        return w + spacing * (columns - 1) + 8
    }
}

struct HUDScoreRowView: View, Equatable {
    let row: HUDScoreRow
    let color: Color
    /// 観戦者の列（nil = プレイヤーの表示）。
    var metrics: HUDScoreRowMetrics? = nil

    var body: some View {
        if let metrics {
            spectatorRow(metrics)
        } else {
            playerRow
        }
    }

    /// 観戦者: 装備の価値・与ダメージの列。追従中の行は白枠、記録した本人は金色。
    private func spectatorRow(_ m: HUDScoreRowMetrics) -> some View {
        HStack(spacing: m.spacing) {
            ZStack(alignment: .bottomTrailing) {
                HeroPortraitView(heroID: row.heroID, size: 30, showsRole: false)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(row.isHuman ? Theme.gold : color, lineWidth: row.isHuman ? 2 : 1))
                    .saturation(row.isDead ? 0 : 1)
                    .overlay {
                        if row.isDead {
                            Text("\(Int(row.respawn))")
                                .font(.system(size: 12, weight: .black, design: .rounded))
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
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(MasterData.shared.hero(row.heroID).map { MasterText.hero($0) } ?? row.name)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(row.isHuman ? Theme.gold : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(row.kills)/\(row.deaths)/\(row.assists)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: m.nameWidth, alignment: .leading)
            column("CS", "\(row.creepScore)", width: 24)
            column(L("価値", "NW"), HUDStyle.thousands(Double(row.netWorth)), width: 32)
            column(L("与ダメ", "DMG"), HUDStyle.thousands(Double(row.damage)), width: 32)
            HStack(spacing: 1) {
                ForEach(0..<Balance.itemSlots, id: \.self) { k in
                    ZStack {
                        RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.45))
                        if k < row.items.count, let item = MasterData.shared.item(row.items[k]) {
                            ItemIconView(item: item, size: m.itemSize - 1)
                        }
                    }
                    .frame(width: m.itemSize, height: m.itemSize)
                }
            }
            if m.showsSpells {
                spells(size: 18)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(row.isHuman ? Theme.gold.opacity(0.10) : (row.isFocus ? Color.white.opacity(0.08) : Color.clear)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(row.isFocus ? Color.white.opacity(0.7) : Color.clear, lineWidth: 1.2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText + L("、装備の価値 \(row.netWorth)、与ダメージ \(row.damage)", ", net worth \(row.netWorth), damage \(row.damage)"))
        .accessibilityAddTraits(row.isFocus ? .isSelected : [])
    }

    private func column(_ title: String, _ value: String, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.5)).lineLimit(1).minimumScaleFactor(0.6)
            Text(value).font(.system(size: 11, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(width: width)
    }

    private func spells(size: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(row.spells.prefix(2).enumerated()), id: \.offset) { k, spellID in
                ZStack {
                    SpellIconView(spellID: spellID, size: size)
                    if let cds = row.spellCooldowns, k < cds.count, cds[k] > 0 {
                        Circle().fill(Color.black.opacity(0.6))
                        Text("\(Int(cds[k]))")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: size, height: size)
            }
        }
    }

    private var playerRow: some View {
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
