import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI018 対AIランキング / UI019 ランク概要 / UI020 ランク報酬。

// MARK: - UI018 対AIランキング

struct RankingView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScreenScaffold(title: L("対AIランキング", "Ladder vs AI")) {
            let ladder = RankService.ladder(for: app.profile)
            HStack(alignment: .top, spacing: 14) {
                sidePanel(ladder)
                    .frame(width: 230)
                if ladder.isEmpty {
                    FlowEmptyState(symbol: "list.number", title: L("ランキングを準備中です", "The ladder is being prepared"),
                                   message: L("ランク戦をプレイすると、AI ライバルとの順位が表示されます。", "Play ranked matches to see where you stand against AI rivals."))
                        .glass(cornerRadius: 16)
                } else {
                    ladderList(ladder)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    private func sidePanel(_ ladder: [LadderEntry]) -> some View {
        let p = app.profile
        let position = ladder.firstIndex { $0.isPlayer }.map { $0 + 1 }
        return VStack(alignment: .leading, spacing: 10) {
            Label(L("オフラインの対AIラダー", "Offline ladder vs AI"), systemImage: "cpu")
                .font(Theme.heading(13))
                .foregroundStyle(Theme.cyan)
            Text(L("この順位は端末内のみで計算されます。ライバルは AI が操作する架空のプレイヤーで、ランク戦の結果に応じて順位が変動します。",
                   "This ladder is computed on your device. Rivals are fictional AI-controlled players; your position changes with your ranked results."))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(Theme.panelStroke)
            HStack(spacing: 10) {
                RankEmblemView(tier: p.rank.tier, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(RankService.displayName(p.rank)).font(Theme.heading(14)).foregroundStyle(Theme.textPrimary)
                    Text(L("レート \(RankService.rating(p.rank))", "Rating \(RankService.rating(p.rank))"))
                        .font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                }
            }
            if let position {
                Text(L("現在 \(position) 位 / \(ladder.count) 人", "#\(position) of \(ladder.count)"))
                    .font(Theme.title(20))
                    .foregroundStyle(Theme.gold)
            }
            Spacer(minLength: 0)
            Button {
                FlowFX.tap(app)
                app.router.push(.rankOverview)
            } label: {
                Label(L("ランク概要", "Rank Overview"), systemImage: "crown.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(minHeight: 44)
            .accessibilityIdentifier("ranking_overview")
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .glass(cornerRadius: 16)
    }

    private func ladderList(_ ladder: [LadderEntry]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(ladder.enumerated()), id: \.element.id) { i, e in
                        ladderRow(position: i + 1, entry: e)
                            .id(e.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                if let me = ladder.first(where: { $0.isPlayer }) {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(me.id, anchor: .center) }
                    }
                }
            }
        }
    }

    private func ladderRow(position: Int, entry: LadderEntry) -> some View {
        HStack(spacing: 10) {
            Group {
                if position <= 3 {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(position == 1 ? Theme.gold : (position == 2 ? Color(white: 0.82) : Color(red: 0.8, green: 0.5, blue: 0.3)))
                        .overlay(Text("\(position)").font(.system(size: 9, weight: .black)).foregroundStyle(.black).offset(y: -2))
                } else {
                    Text("\(position)").font(Theme.mono(14)).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 36)
            RankEmblemView(tier: entry.tier, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(Theme.heading(14))
                        .foregroundStyle(entry.isPlayer ? Theme.gold : Theme.textPrimary)
                        .lineLimit(1)
                    if entry.isPlayer {
                        Text(L("あなた", "YOU"))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.gold))
                    } else {
                        Image(systemName: "cpu").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                            .accessibilityLabel("AI")
                    }
                }
                Text(RankService.tierName(entry.tier)).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text("\(entry.rating)")
                .font(Theme.mono(15))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 50)
        .glass(cornerRadius: 12, tint: entry.isPlayer ? Theme.gold : Theme.panelStroke, highlighted: entry.isPlayer)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(entry.isPlayer ? "ranking_player_row" : "ranking_row_\(position)")
    }
}

// MARK: - UI019 ランク概要

struct RankOverviewView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScreenScaffold(title: L("ランク", "Rank")) {
            HStack(alignment: .top, spacing: 14) {
                currentPanel
                    .frame(width: 270)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        actions
                        tierLadder
                        rules
                    }
                    .padding(.bottom, 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private var currentPanel: some View {
        let r = app.profile.rank
        let games = r.seasonWins + r.seasonLosses
        let diff = RankService.botDifficulty(for: r)
        return ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    StarRingView(tint: FlowText.tierColors(r.tier)[0], accent: Theme.gold, speed: 0.07, starCount: 22, showsCore: false)
                        .frame(width: 240, height: 64)
                        .offset(y: 30)
                    RankEmblemView(tier: r.tier, size: 88)
                        .glowPulse(FlowText.tierColors(r.tier)[0], radius: 16)
                }
                .frame(height: 104)
                Text(RankService.displayName(r))
                    .font(Theme.title(22))
                    .foregroundStyle(Theme.textPrimary)
                if r.tier == .starRingSovereign {
                    Text("\(r.points) pt").font(Theme.mono(15)).foregroundStyle(Theme.gold)
                } else {
                    RankStarsView(stars: r.stars, size: 20)
                }
                HStack(spacing: 6) {
                    FlowStatCell(title: L("勝利", "Wins"), value: "\(r.seasonWins)", tint: Theme.success)
                    FlowStatCell(title: L("敗北", "Losses"), value: "\(r.seasonLosses)", tint: Theme.danger)
                    FlowStatCell(title: L("勝率", "Win%"), value: games > 0 ? "\(r.seasonWins * 100 / games)%" : "—")
                }
                HStack(spacing: 6) {
                    Image(systemName: "cpu").foregroundStyle(Theme.cyan)
                    Text(L("AI 難易度: 味方 \(FlowText.difficulty(diff.ally)) / 敵 \(FlowText.difficulty(diff.enemy))",
                           "AI: allies \(FlowText.difficulty(diff.ally)) / enemies \(FlowText.difficulty(diff.enemy))"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(L("最高ランク: \(RankService.tierName(r.highestTier))", "Highest: \(RankService.tierName(r.highestTier))"))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(14)
        }
        .glass(cornerRadius: 16)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                FlowFX.confirm(app)
                MatchFlowIntent.present(.ranked, app: app)
            } label: {
                Label(L("ランク戦を開始", "Play Ranked"), systemImage: "crown.fill")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .glowPulse(Theme.gold, radius: 10)
            .accessibilityIdentifier("rank_play")
            HStack(spacing: 8) {
                Button {
                    FlowFX.tap(app)
                    app.router.push(.ranking)
                } label: {
                    Label(L("ランキング", "Ladder"), systemImage: "list.number")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(minHeight: 44)
                .accessibilityIdentifier("rank_ladder")
                Button {
                    FlowFX.tap(app)
                    app.router.push(.rankRewards)
                } label: {
                    Label(L("ランク報酬", "Rewards"), systemImage: "gift.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(minHeight: 44)
                .overlay(alignment: .topTrailing) { FlowCountBadge(count: HomeBadges.claimableRankRewards(app.profile)) }
                .accessibilityIdentifier("rank_rewards")
            }
        }
        .padding(.top, 2)
    }

    private var tierLadder: some View {
        let r = app.profile.rank
        return VStack(alignment: .leading, spacing: 8) {
            FlowSectionTitle(title: L("ランク一覧", "Tiers"), symbol: "stairs")
            ForEach(RankTier.allCases.reversed()) { t in
                let current = t == r.tier
                let reached = t <= r.highestTier
                let diff = RankService.botDifficulty(for: RankState(tier: t))
                HStack(spacing: 10) {
                    RankEmblemView(tier: t, size: current ? 38 : 30)
                        .opacity(reached ? 1 : 0.45)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(RankService.tierName(t))
                            .font(Theme.heading(current ? 15 : 13))
                            .foregroundStyle(current ? Theme.gold : Theme.textPrimary)
                        Text(t == .starRingSovereign ? L("ポイント制", "Point system") : L("3 段階 × 星 3", "3 divisions × 3 stars"))
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text(L("敵AI \(FlowText.difficulty(diff.enemy))", "Enemy AI \(FlowText.difficulty(diff.enemy))"))
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                    if current {
                        Text(L("現在", "Current"))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.gold))
                    } else if reached {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                            .accessibilityLabel(L("到達済み", "Reached"))
                    }
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 46)
                .glass(cornerRadius: 12, tint: current ? Theme.gold : Theme.panelStroke, highlighted: current)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowSectionTitle(title: L("ルール", "Rules"), symbol: "info.circle.fill")
            ruleRow("arrow.up.circle.fill", Theme.success, L("勝利で星 +1。星 3 つで次の段階へ昇格します。", "Win: +1 star. Three stars promote you to the next division."))
            ruleRow("arrow.down.circle.fill", Theme.danger, L("敗北で星 −1（隕鉄では降格しません）。", "Loss: −1 star (no demotion in Meteorite)."))
            ruleRow("cpu", Theme.cyan, L("ランクが上がるほど AI が強くなります。", "Higher ranks face stronger AI."))
            ruleRow("hand.raised.fill", Theme.gold, L("ランク戦では各チーム 2 体ずつ BAN してからピックします。", "In ranked, each team bans two heroes before picking."))
        }
        .padding(12)
        .glass(cornerRadius: 14)
    }

    private func ruleRow(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        Label {
            Text(text).font(Theme.body(12)).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }
}

// MARK: - UI020 ランク報酬

struct RankRewardsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScreenScaffold(title: L("ランク報酬", "Rank Rewards")) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(Theme.cyan)
                    Text(L("シーズン中に到達したランクの報酬を 1 回ずつ受け取れます。", "Claim a one-time reward for each tier you reach this season."))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    RankInlineView(rank: app.profile.rank, emblemSize: 22)
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(RankTier.allCases) { t in
                            rewardRow(t)
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func rewardRow(_ t: RankTier) -> some View {
        let rank = app.profile.rank
        let rewards = RankService.tierRewards(t)
        let reached = t <= rank.highestTier
        let claimed = rank.claimedTierRewards.contains(t.rawValue)
        return HStack(spacing: 12) {
            RankEmblemView(tier: t, size: 42)
                .opacity(reached ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 5) {
                Text(RankService.tierName(t))
                    .font(Theme.heading(15))
                    .foregroundStyle(reached ? Theme.textPrimary : Theme.textSecondary)
                if rewards.isEmpty {
                    Text(L("このランクの報酬はありません", "No reward for this tier"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    FlowWrapLayout(spacing: 6) {
                        ForEach(rewards.indices, id: \.self) { i in
                            AttachmentChip(attachment: rewards[i], claimed: claimed)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Group {
                if claimed {
                    Label(L("受取済み", "Claimed"), systemImage: "checkmark.circle.fill")
                        .font(Theme.heading(12))
                        .foregroundStyle(Theme.success)
                } else if reached && !rewards.isEmpty {
                    Button(L("受け取る", "Claim")) { claim(t) }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("rank_claim_\(t.rawValue)")
                } else if !reached {
                    Label(L("未到達", "Locked"), systemImage: "lock.fill")
                        .font(Theme.heading(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 120)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 60)
        .glass(cornerRadius: 14, tint: reached && !claimed && !rewards.isEmpty ? Theme.gold : Theme.panelStroke,
               highlighted: reached && !claimed && !rewards.isEmpty)
        .accessibilityElement(children: .contain)
    }

    private func claim(_ t: RankTier) {
        var p = app.profile
        let rewards = RankService.tierRewards(t)
        if RankService.claimTierReward(t, profile: &p) {
            app.profile = p
            FlowFX.reward(app)
            app.showToast(L("受け取りました: ", "Received: ") + FlowText.attachmentsSummary(rewards, master: app.master))
        } else {
            FlowFX.error(app)
            app.showToast(L("受け取れませんでした", "Couldn't claim the reward"))
        }
    }
}
