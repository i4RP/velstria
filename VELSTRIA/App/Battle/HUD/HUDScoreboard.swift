import SwiftUI
import VelstriaCore

// 担当: battle-hud。UI029 スコアボード（参照: モバイルレジェンド）。
// プレイヤー: 画面全体を青 vs 赤で左右分割し（レッドは左右反転）、上部に両チームの総合（キル・目標・タワー）と
// 試合時間、「装備 / 成績」の 2 タブ。装備タブ = K/D/A・装備 6 枠・バトルスペル（味方は CD）、成績タブ =
// キル・デス・アシスト・CS・KDA。相手の所持 Gold・与ダメージは試合中は見せない（観戦のみ）。
// 観戦者: 従来どおり 1 行に全情報（装備の価値・与ダメージの列）を出し、行タップでそのヒーローを追従する
//（HUDScoreRowView / HUDScoreRowMetrics。収まり判定は HUDLayoutTests）。
// 枠・地色は PortraitArt.frame(_:) のアートがあれば使い、無ければコードの手続き描画で出す
//（差し込み口の仕様は tools/portraits/ui_frames.json）。

/// プレイヤーのスコアボードの表示タブ。
enum HUDScoreTab: Hashable { case gear, stats }

/// 行の向き（青 = leading、赤 = trailing で左右反転）。
enum HUDScoreSide { case leading, trailing }

enum HUDScoreFmt {
    /// 大きな数は k 表記（1,500 → 1.5k、12,340 → 12k）。
    static func compact(_ v: Int) -> String {
        if v >= 100_000 { return "\(v / 1000)k" }
        if v >= 10_000 { return String(format: "%.0fk", Double(v) / 1000) }
        if v >= 1_000 { return String(format: "%.1fk", Double(v) / 1000) }
        return "\(v)"
    }
}

struct HUDScoreboardPanel: View {
    let model: HUDModel
    let layout: HUDLayout
    @State private var tab: HUDScoreTab = .gear

    var body: some View {
        let sb = model.scoreboard
        let cb = model.settings.colorblindMode
        let spectating = model.isSpectating
        let metrics = spectating ? HUDScoreRowMetrics.spectator(rowWidth: Self.rowWidth(layout)) : nil
        let s = min(layout.scale, 1.12)
        VStack(spacing: 8 * s) {
            HUDScoreHeader(sb: sb, colorblind: cb, scale: s, showsGold: spectating,
                           tab: spectating ? nil : $tab) { model.closePanel() }
            HStack(alignment: .top, spacing: 10 * s) {
                teamColumn(sb.blue, team: .blue, side: .leading, colorblind: cb, metrics: metrics, scale: s)
                teamColumn(sb.red, team: .red, side: .trailing, colorblind: cb, metrics: metrics, scale: s)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 14 * s)
        .padding(.vertical, 12 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HUDScoreboardBackdrop(colorblind: cb))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scoreboard_panel")
    }

    /// 1 行の幅（パネルの左右の余白・列の間隔・列の内側の余白を除く）。
    /// 変更時は HUDScoreRowMetrics.contentWidth と HUDLayoutTests を合わせること。
    static func rowWidth(_ layout: HUDLayout) -> CGFloat {
        let panel = layout.trailingEdge - layout.leadingEdge - 8
        return (panel - 24 - 10) / 2 - 12
    }

    private func teamColumn(_ rows: [HUDScoreRow], team: Team, side: HUDScoreSide, colorblind: Bool,
                            metrics: HUDScoreRowMetrics?, scale: CGFloat) -> some View {
        let color = Theme.teamColor(team, colorblind: colorblind)
        return VStack(spacing: 5 * scale) {
            teamHeader(team: team, side: side, color: color, scale: scale)
            if rows.isEmpty {
                Text(L("（対向チームなし）", "(No opposing team)"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(rows) { row in
                    if let metrics {
                        // 観戦者: タップでそのヒーローを追従（従来の 1 行表示）
                        Button { model.scoreboardRowTapped(row.id) } label: {
                            HUDScoreRowView(row: row, color: color, metrics: metrics)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(HUDPressStyle())
                        .accessibilityHint(L("タップで追従", "Tap to follow"))
                        .accessibilityIdentifier("scoreboard_row_\(row.id)")
                    } else {
                        HUDScorePlayerRow(row: row, side: side, color: color, tab: tab, scale: scale)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(8 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(color.opacity(0.4), lineWidth: 1))
    }

    private func teamHeader(team: Team, side: HUDScoreSide, color: Color, scale: CGFloat) -> some View {
        HStack(spacing: 6) {
            if side == .trailing { Spacer(minLength: 0) }
            Image(systemName: team == .blue ? "shield.lefthalf.filled" : "flame.fill")
                .font(.system(size: 12 * scale, weight: .bold))
                .foregroundStyle(color)
            Text(HUDText.teamName(team))
                .font(.system(size: 13 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            Text(L("チーム", "TEAM"))
                .font(.system(size: 9 * scale, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(color.opacity(0.7))
            if side == .leading { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 4)
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

// MARK: - 地色と枠（PortraitArt.frame のアートがあれば使い、無ければ手続き描画）

private struct HUDScoreboardBackdrop: View {
    let colorblind: Bool

    var body: some View {
        let blue = Theme.teamColor(.blue, colorblind: colorblind)
        let red = Theme.teamColor(.red, colorblind: colorblind)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(red: 0.06, green: 0.08, blue: 0.18).opacity(0.98),
                                               Color(red: 0.02, green: 0.03, blue: 0.08).opacity(0.98)],
                                      startPoint: .top, endPoint: .bottom))
            if let art = PortraitArt.frame("scoreboard_bg") {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.45)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            // 左右のチームカラーの淡い染め。
            HStack(spacing: 0) {
                LinearGradient(colors: [blue.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, red.opacity(0.16)], startPoint: .leading, endPoint: .trailing)
            }
            .clipShape(shape)
            .allowsHitTesting(false)
            if let frameArt = PortraitArt.frame("scoreboard_frame") {
                Image(uiImage: frameArt)
                    .resizable(capInsets: EdgeInsets(top: 48, leading: 48, bottom: 48, trailing: 48), resizingMode: .stretch)
                    .allowsHitTesting(false)
            } else {
                shape.strokeBorder(LinearGradient(colors: [Theme.gold.opacity(0.55), HUDStyle.rim, Theme.gold.opacity(0.35)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 20)
    }
}

// MARK: - ヘッダ（総合・時間・閉じる・タブ）

private struct HUDScoreHeader: View {
    let sb: HUDScoreboardSnapshot
    let colorblind: Bool
    let scale: CGFloat
    /// 所持 Gold の総合を出すか（観戦のみ。プレイヤーには見せない）。
    let showsGold: Bool
    /// プレイヤーのみタブを出す（観戦は nil）。
    let tab: Binding<HUDScoreTab>?
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10 * scale) {
            VStack(spacing: 6 * scale) {
                HUDScoreTotals(sb: sb, colorblind: colorblind, scale: scale, showsGold: showsGold)
                if let tab {
                    HUDScoreTabBar(tab: tab, scale: scale)
                }
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16 * scale, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .overlay(Circle().strokeBorder(HUDStyle.rim, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L("閉じる", "Close"))
            .accessibilityIdentifier("scoreboard_close")
        }
    }
}

private struct HUDScoreTabBar: View {
    @Binding var tab: HUDScoreTab
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            tabButton(.gear, L("装備", "Gear"), "bag.fill", "scoreboard_tab_gear")
            tabButton(.stats, L("成績", "Stats"), "chart.bar.fill", "scoreboard_tab_stats")
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(HUDStyle.rim.opacity(0.6), lineWidth: 1))
    }

    private func tabButton(_ t: HUDScoreTab, _ title: String, _ symbol: String, _ id: String) -> some View {
        let selected = tab == t
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { tab = t }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12 * scale, weight: .bold))
                Text(title).font(.system(size: 13 * scale, weight: .bold, design: .rounded)).lineLimit(1)
            }
            .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textPrimary)
            .padding(.horizontal, 12 * scale)
            .frame(minHeight: 34 * scale)
            .background(Capsule().fill(selected ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct HUDScoreTotals: View {
    let sb: HUDScoreboardSnapshot
    let colorblind: Bool
    let scale: CGFloat
    let showsGold: Bool

    var body: some View {
        let blue = Theme.teamColor(.blue, colorblind: colorblind)
        let red = Theme.teamColor(.red, colorblind: colorblind)
        HStack(spacing: 10 * scale) {
            teamSide(kills: sb.blueKills, towers: sb.blueTowers, objectives: sb.blueObjectives,
                     gold: showsGold ? teamGold(sb.blue) : nil, color: blue, leading: true)
            VStack(spacing: 0) {
                Text("VS")
                    .font(.system(size: 16 * scale, weight: .black, design: .serif))
                    .foregroundStyle(LinearGradient(colors: [.white, Theme.gold], startPoint: .top, endPoint: .bottom))
                Text(HUDStyle.clock(Double(sb.seconds)))
                    .font(.system(size: 14 * scale, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            teamSide(kills: sb.redKills, towers: sb.redTowers, objectives: sb.redObjectives,
                     gold: showsGold ? teamGold(sb.red) : nil, color: red, leading: false)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 5 * scale)
        .background(Capsule().fill(Color.black.opacity(0.32)))
        .overlay(Capsule().strokeBorder(LinearGradient(colors: [blue.opacity(0.85), HUDStyle.rim, red.opacity(0.85)],
                                                       startPoint: .leading, endPoint: .trailing), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("ブルー \(sb.blueKills) キル対レッド \(sb.redKills) キル、経過 \(HUDStyle.clock(Double(sb.seconds)))",
                              "Blue \(sb.blueKills) kills to Red \(sb.redKills) kills, elapsed \(HUDStyle.clock(Double(sb.seconds)))"))
    }

    private func teamGold(_ rows: [HUDScoreRow]) -> Int { rows.reduce(0) { $0 + $1.netWorth } }

    private func teamSide(kills: Int, towers: Int, objectives: Int, gold: Int?, color: Color, leading: Bool) -> some View {
        // 青: キル・目標・タワー（＋観戦のみ Gold）。赤は左右反転。
        var items: [(symbol: String, value: String, tint: Color)] = [
            ("bolt.fill", "\(kills)", color),
            ("hurricane", "\(objectives)", color),
            ("building.columns.fill", "\(towers)", color),
        ]
        if let gold { items.append(("dollarsign.circle.fill", HUDScoreFmt.compact(gold), Theme.gold)) }
        let ordered = leading ? items : Array(items.reversed())
        return HStack(spacing: 9 * scale) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, it in
                HStack(spacing: 3 * scale) {
                    Image(systemName: it.symbol).font(.system(size: 9 * scale, weight: .bold)).foregroundStyle(it.tint)
                    Text(it.value).font(.system(size: 14 * scale, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }
}

// MARK: - 共有セル（ポートレート・名前・スペル）

private struct HUDScorePortrait: View {
    let row: HUDScoreRow
    let color: Color
    let scale: CGFloat

    var body: some View {
        let size = 40 * scale
        ZStack(alignment: .bottomTrailing) {
            HeroPortraitView(heroID: row.heroID, size: size, showsRole: false)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(row.isHuman ? Theme.gold : color, lineWidth: row.isHuman ? 2 : 1))
                .saturation(row.isDead ? 0 : 1)
                .overlay {
                    if row.isDead {
                        Text("\(Int(row.respawn))")
                            .font(.system(size: 14, weight: .black, design: .rounded))
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
        .frame(width: size, height: size)
    }
}

private struct HUDScoreIdentity: View {
    let row: HUDScoreRow
    let side: HUDScoreSide
    let scale: CGFloat

    var body: some View {
        let heroName = MasterData.shared.hero(row.heroID).map { MasterText.hero($0) } ?? row.heroID
        let align: HorizontalAlignment = side == .leading ? .leading : .trailing
        VStack(alignment: align, spacing: 1) {
            Text(row.name)
                .font(.system(size: 11 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(row.isHuman ? Theme.gold : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(heroName)
                .font(.system(size: 9 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: side == .leading ? .leading : .trailing)
    }
}

private struct HUDScoreSpells: View {
    let row: HUDScoreRow
    let scale: CGFloat

    var body: some View {
        let size = 17 * scale
        VStack(spacing: 2) {
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
}

// MARK: - プレイヤーの行（装備 / 成績タブ・左右反転。相手の経済は出さない）

private struct HUDScorePlayerRow: View {
    let row: HUDScoreRow
    let side: HUDScoreSide
    let color: Color
    let tab: HUDScoreTab
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 7 * scale) {
            if side == .leading {
                HUDScorePortrait(row: row, color: color, scale: scale)
                HUDScoreIdentity(row: row, side: side, scale: scale)
                content
            } else {
                content
                HUDScoreIdentity(row: row, side: side, scale: scale)
                HUDScorePortrait(row: row, color: color, scale: scale)
            }
        }
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 3 * scale)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(row.isHuman ? Theme.gold.opacity(0.12) : Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(row.isHuman ? Theme.gold.opacity(0.6) : Color.clear, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var content: some View {
        if tab == .gear {
            gearContent
        } else {
            stats
        }
    }

    @ViewBuilder private var gearContent: some View {
        if side == .leading {
            HUDScoreSpells(row: row, scale: scale)
            kda
            equipment
        } else {
            equipment
            kda
            HUDScoreSpells(row: row, scale: scale)
        }
    }

    private var kda: some View {
        let headers = ["bolt.fill", "skull", "hand.raised.fill"]
        let values = ["\(row.kills)", "\(row.deaths)", "\(row.assists)"]
        let order = side == .leading ? Array(0..<3) : Array((0..<3).reversed())
        return HStack(spacing: 5 * scale) {
            ForEach(order, id: \.self) { i in
                VStack(spacing: 1) {
                    Image(systemName: headers[i])
                        .font(.system(size: 7 * scale, weight: .bold))
                        .foregroundStyle(HUDStyle.mutedText)
                    Text(values[i])
                        .font(.system(size: 12 * scale, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .frame(width: 24 * scale)
            }
        }
    }

    private var equipment: some View {
        HStack(spacing: 2 * scale) {
            ForEach(0..<Balance.itemSlots, id: \.self) { k in
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.black.opacity(0.45))
                    RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                    if k < row.items.count, let item = MasterData.shared.item(row.items[k]) {
                        ItemIconView(item: item, size: 18 * scale)
                    }
                }
                .frame(width: 19 * scale, height: 19 * scale)
            }
        }
    }

    private var stats: some View {
        let ratio = Double(row.kills + row.assists) / Double(max(1, row.deaths))
        let cols: [(symbol: String, value: String, tint: Color, label: String)] = [
            ("bolt.fill", "\(row.kills)", HUDStyle.hp, L("キル", "K")),
            ("skull", "\(row.deaths)", Color(red: 1.0, green: 0.52, blue: 0.35), L("デス", "D")),
            ("hand.raised.fill", "\(row.assists)", HUDStyle.accent, L("アシスト", "A")),
            ("leaf.fill", "\(row.creepScore)", HUDStyle.mutedText, "CS"),
            ("chart.line.uptrend.xyaxis", String(format: "%.1f", ratio), Theme.gold, "KDA"),
        ]
        let order = side == .leading ? Array(0..<cols.count) : Array((0..<cols.count).reversed())
        return HStack(spacing: 6 * scale) {
            ForEach(order, id: \.self) { i in
                VStack(spacing: 1) {
                    Image(systemName: cols[i].symbol).font(.system(size: 8 * scale, weight: .bold)).foregroundStyle(cols[i].tint)
                    Text(cols[i].value)
                        .font(.system(size: 12 * scale, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(cols[i].label)
                        .font(.system(size: 7 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(HUDStyle.mutedText.opacity(0.8))
                }
                .frame(width: 34 * scale)
            }
        }
    }

    private var accessibilityText: String {
        let name = MasterData.shared.hero(row.heroID).map { MasterText.hero($0) } ?? row.name
        if tab == .gear {
            return L("\(name) レベル \(row.level) \(row.kills)/\(row.deaths)/\(row.assists)",
                     "\(name) level \(row.level) \(row.kills)/\(row.deaths)/\(row.assists)")
        } else {
            return L("\(name) \(row.kills)/\(row.deaths)/\(row.assists)、CS \(row.creepScore)",
                     "\(name) \(row.kills)/\(row.deaths)/\(row.assists), CS \(row.creepScore)")
        }
    }
}
