import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI054 ミッション（デイリー / ウィークリー）と、イベント画面と共有するミッション表示ロジック。

enum LiveOpsMissionState: Equatable {
    case inProgress, claimable, claimed
}

/// 定義 + 進捗を合わせた 1 行分。
struct LiveOpsMissionEntry: Identifiable, Equatable {
    var def: MissionDef
    var progress: Int
    var claimed: Bool

    var id: String { def.id }
    var isComplete: Bool { progress >= def.target }
    var state: LiveOpsMissionState { claimed ? .claimed : (isComplete ? .claimable : .inProgress) }
    var fraction: Double { def.target > 0 ? min(1, Double(progress) / Double(def.target)) : 1 }
    var title: String { L(def.titleJa, def.titleEn) }

    var rewards: [MailAttachment] {
        var list: [MailAttachment] = []
        if def.rewardCoins > 0 { list.append(MailAttachment(kind: .coin, amount: def.rewardCoins)) }
        if def.rewardPassXP > 0 { list.append(MailAttachment(kind: .passXP, amount: def.rewardPassXP)) }
        return list + LiveOpsMissions.extraRewards(def)
    }
}

enum LiveOpsMissions {
    /// 定義列と進捗列を結合（進捗が無いものは 0・未受取）。
    static func entries(_ defs: [MissionDef], progress: [MissionProgress]) -> [LiveOpsMissionEntry] {
        defs.map { def in
            let p = progress.first { $0.id == def.id }
            return LiveOpsMissionEntry(def: def, progress: p?.progress ?? 0, claimed: p?.claimed ?? false)
        }
    }

    static func daily(_ profile: Profile) -> [LiveOpsMissionEntry] {
        entries(LiveOpsService.dailyMissions(profile: profile), progress: profile.missions.daily)
    }

    static func weekly(_ profile: Profile) -> [LiveOpsMissionEntry] {
        entries(LiveOpsService.weeklyMissions(profile: profile), progress: profile.missions.weekly)
    }

    /// イベントミッション。LiveOpsService は開催中イベントの進捗を profile.missions.weekly の
    /// ウィークリー分の後ろに並べて保持するため、デイリー → ウィークリーの順に ID で検索する（未着手は進捗 0）。
    static func event(_ event: EventDef, profile: Profile) -> [LiveOpsMissionEntry] {
        let defs = event.missionIDs.compactMap { LiveOpsService.missionDef(id: $0) }
        return entries(defs, progress: profile.missions.daily + profile.missions.weekly)
    }

    /// Coin / パス XP 以外の追加報酬（イベントミッションの Gem・コスメなど）。
    /// LiveOpsService 側で MissionDef に `extraRewards: [MailAttachment]` が追加される（契約の型には無い）ため、
    /// コンパイル時に依存しないよう名前で読み取る。フィールドが無ければ空。
    static func extraRewards(_ def: MissionDef) -> [MailAttachment] {
        extraRewards(reflecting: def)
    }

    static func extraRewards(reflecting value: Any) -> [MailAttachment] {
        Mirror(reflecting: value).children.first { $0.label == "extraRewards" }?.value as? [MailAttachment] ?? []
    }

    /// 表示順: 受取可能 → 進行中 → 受取済み（各グループ内は元の順）。
    static func displayOrder(_ list: [LiveOpsMissionEntry]) -> [LiveOpsMissionEntry] {
        func rank(_ s: LiveOpsMissionState) -> Int {
            switch s {
            case .claimable: return 0
            case .inProgress: return 1
            case .claimed: return 2
            }
        }
        return list.enumerated()
            .sorted { a, b in
                let ra = rank(a.element.state), rb = rank(b.element.state)
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map(\.element)
    }

    static func symbol(_ kind: MissionDef.Kind) -> String {
        switch kind {
        case .playMatches: return "gamecontroller.fill"
        case .winMatches: return "trophy.fill"
        case .kills: return "flame.fill"
        case .assists: return "hands.sparkles.fill"
        case .creepScore: return "leaf.fill"
        case .destroyTowers: return "building.columns.fill"
        case .useHeroRole: return "person.crop.circle.badge.checkmark"
        case .dealDamage: return "burst.fill"
        }
    }
}

/// ミッション受取の共通処理。成功した報酬を返し、1 件も受け取れなければ nil。
@MainActor
enum LiveOpsClaims {
    static func claimMissions(_ ids: [String], app: AppModel, now: Date = Date()) -> [MailAttachment]? {
        var p = app.profile
        var granted: [MailAttachment] = []
        var any = false
        for id in ids {
            if let rewards = LiveOpsService.claimMission(id: id, profile: &p, now: now) {
                any = true
                granted += rewards
            }
        }
        // 受取に失敗しても、受取処理内の日替わり更新（期限切れ報酬のメール送付など）は反映する
        app.profile = p
        guard any else {
            app.audio.play(.uiError)
            app.haptics.warning()
            app.showToast(L("受け取れる報酬がありません", "Nothing to claim"))
            return nil
        }
        return granted
    }

    /// 受取結果をポップアップ用の内容に変換（報酬が空ならトーストのみ）。
    static func content(for rewards: [MailAttachment], app: AppModel) -> RewardClaimContent? {
        guard !RewardClaimText.merged(rewards).isEmpty else {
            app.showToast(L("受け取りました", "Claimed"))
            return nil
        }
        return RewardClaimContent(attachments: rewards)
    }
}

/// ミッション 1 行。
struct LiveOpsMissionRow: View {
    let entry: LiveOpsMissionEntry
    /// false の場合は受取ボタンを無効化（イベント期間外など）。
    var claimEnabled = true
    let onClaim: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: LiveOpsMissions.symbol(entry.def.kind))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(entry.state == .claimed ? Theme.textSecondary : Theme.cyan)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.cyan.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(Theme.heading(14))
                    .foregroundStyle(entry.state == .claimed ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                HStack(spacing: 8) {
                    LiveOpsProgressBar(fraction: entry.fraction, tint: entry.isComplete ? Theme.gold : Theme.cyan)
                        .frame(maxWidth: 220)
                    Text("\(min(entry.progress, entry.def.target).formatted()) / \(entry.def.target.formatted())")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
                LiveOpsFlowLayout(spacing: 6, lineSpacing: 4) {
                    ForEach(Array(entry.rewards.enumerated()), id: \.offset) { _, reward in
                        LiveOpsRewardChip(attachment: reward)
                    }
                }
            }
            Spacer(minLength: 4)
            claimButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(entry.state == .claimable ? Theme.gold.opacity(0.10) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(entry.state == .claimable ? Theme.gold.opacity(0.7) : Theme.panelStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var claimButton: some View {
        switch entry.state {
        case .claimable:
            Button(action: onClaim) {
                Text(L("受け取る", "Claim")).lineLimit(1).frame(minWidth: 70, minHeight: 22)
            }
            .buttonStyle(LiveOpsTallButtonStyle(base: PrimaryButtonStyle()))
            .disabled(!claimEnabled)
            .opacity(claimEnabled ? 1 : 0.45)
            .accessibilityIdentifier("mission_claim_\(entry.id)")
            .accessibilityLabel("\(entry.title), \(L("受け取る", "Claim"))")
        case .inProgress:
            Text(L("進行中", "In progress"))
                .font(Theme.heading(13))
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 96, minHeight: 44)
                .accessibilityLabel("\(entry.title), \(L("進行中", "In progress")) \(entry.progress) / \(entry.def.target)")
        case .claimed:
            Label(L("受取済み", "Claimed"), systemImage: "checkmark.circle.fill")
                .font(Theme.heading(13))
                .foregroundStyle(Theme.success)
                .frame(minWidth: 96, minHeight: 44)
                .accessibilityLabel("\(entry.title), \(L("受取済み", "Claimed"))")
        }
    }
}

// MARK: - UI054 ミッション

struct MissionsView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: Tab = .daily
    @State private var reward: RewardClaimContent?

    enum Tab: Hashable { case daily, weekly }

    var body: some View {
        let daily = LiveOpsMissions.daily(app.profile)
        let weekly = LiveOpsMissions.weekly(app.profile)
        let current = tab == .daily ? daily : weekly
        ScreenScaffold(title: L("ミッション", "Missions")) {
            HStack(alignment: .top, spacing: 14) {
                sidePanel(daily: daily, weekly: weekly, current: current)
                    .frame(width: 230)
                missionList(current)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .rewardClaimPopup($reward)
        // 表示中に 0:00 を過ぎたらミッションを入れ替える
        .task { await LiveOpsDayRollover.watch(app) }
    }

    private func sidePanel(daily: [LiveOpsMissionEntry], weekly: [LiveOpsMissionEntry], current: [LiveOpsMissionEntry]) -> some View {
        // 「すべて受け取る」は表示中のタブに限らず、デイリー・ウィークリーの両方を対象にする
        let claimable = (daily + weekly).filter { $0.state == .claimable }
        let done = current.filter { $0.state != .inProgress }.count
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                Panel(padding: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        LiveOpsSegmented(options: [
                            LiveOpsSegmentOption(value: Tab.daily, title: L("デイリー", "Daily"), symbol: "sun.max.fill",
                                                 badge: daily.filter { $0.state == .claimable }.count, identifier: "missions_tab_daily"),
                            LiveOpsSegmentOption(value: Tab.weekly, title: L("ウィークリー", "Weekly"), symbol: "calendar",
                                                 badge: weekly.filter { $0.state == .claimable }.count, identifier: "missions_tab_weekly"),
                        ], selection: $tab, axis: .vertical, onChange: { _ in app.audio.play(.uiTap) })
                        SettingsDivider()
                        HStack(spacing: 6) {
                            Text(L("更新まで", "Resets in"))
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            LiveOpsCountdownLabel(resetTarget: tab == .daily ? { LiveOpsClock.nextDailyReset(after: $0) }
                                                                             : { LiveOpsClock.nextWeeklyReset(after: $0) },
                                                  prefix: "", symbol: "arrow.clockwise.circle.fill")
                                .id(tab)
                        }
                        HStack {
                            Text(L("達成", "Completed"))
                            Spacer()
                            Text("\(done) / \(current.count)").monospacedDigit()
                        }
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityElement(children: .combine)
                    }
                }
                Button {
                    claim(claimable.map(\.id))
                } label: {
                    Label(L("すべて受け取る", "Claim All"), systemImage: "gift.fill")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(LiveOpsTallButtonStyle(base: PrimaryButtonStyle()))
                .disabled(claimable.isEmpty)
                .opacity(claimable.isEmpty ? 0.45 : 1)
                .accessibilityIdentifier("missions_claim_all")
                passShortcut
            }
            .padding(.bottom, 4)
        }
    }

    private var passShortcut: some View {
        let level = LiveOpsService.passLevel(xp: app.profile.pass.xp)
        return Button {
            app.audio.play(.uiTap)
            app.router.push(.starPass)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "star.leadinghalf.filled")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("スターパス", "Star Pass"))
                        .font(Theme.heading(14))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("Lv \(level) · 対戦とミッションで XP 獲得", "Lv \(level) · Earn XP from matches & missions"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.panelStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("missions_open_pass")
    }

    @ViewBuilder
    private func missionList(_ entries: [LiveOpsMissionEntry]) -> some View {
        if entries.isEmpty {
            Panel {
                LiveOpsEmptyState(symbol: "checklist",
                                  title: tab == .daily ? L("デイリーミッションはありません", "No daily missions")
                                                       : L("ウィークリーミッションはありません", "No weekly missions"),
                                  message: L("ミッションは更新時刻に新しく配布されます。対戦をプレイしてお待ちください。",
                                             "New missions arrive at the next reset. Play a match in the meantime."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 8) {
                    ForEach(LiveOpsMissions.displayOrder(entries)) { entry in
                        LiveOpsMissionRow(entry: entry) { claim([entry.id]) }
                    }
                }
                .padding(.bottom, 8)
                .animation(.easeInOut(duration: 0.25), value: entries)
            }
        }
    }

    private func claim(_ ids: [String]) {
        guard !ids.isEmpty, let rewards = LiveOpsClaims.claimMissions(ids, app: app) else { return }
        reward = LiveOpsClaims.content(for: rewards, app: app)
    }
}
