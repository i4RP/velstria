import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI052 イベント一覧 / UI053 イベント詳細。

enum LiveOpsEventPhase: Equatable {
    case upcoming, active, ended

    static func of(_ event: EventDef, now: Date) -> LiveOpsEventPhase {
        if now < event.start { return .upcoming }
        if now >= event.end { return .ended }
        return .active
    }

    var label: String {
        switch self {
        case .upcoming: return L("開催予定", "Upcoming")
        case .active: return L("開催中", "Live")
        case .ended: return L("終了", "Ended")
        }
    }

    var color: Color {
        switch self {
        case .upcoming: return Theme.cyan
        case .active: return Theme.success
        case .ended: return Theme.textSecondary
        }
    }

    var symbol: String {
        switch self {
        case .upcoming: return "hourglass"
        case .active: return "dot.radiowaves.left.and.right"
        case .ended: return "flag.checkered"
        }
    }
}

enum LiveOpsEvents {
    /// 開催中（終了が近い順）。
    static func active(now: Date) -> [EventDef] {
        LiveOpsService.activeEvents(now: now).sorted { $0.end != $1.end ? $0.end < $1.end : $0.id < $1.id }
    }

    /// 開催予定（開始が近い順）。
    static func upcoming(now: Date) -> [EventDef] {
        LiveOpsService.events.filter { $0.start > now }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.id < $1.id }
    }

    static func event(id: String) -> EventDef? {
        LiveOpsService.events.first { $0.id == id }
    }

    static func title(_ e: EventDef) -> String { L(e.titleJa, e.titleEn) }
    static func detail(_ e: EventDef) -> String { L(e.detailJa, e.detailEn) }

    static func period(_ e: EventDef) -> String {
        "\(LiveOpsFormat.dateTime(e.start)) 〜 \(LiveOpsFormat.dateTime(e.end))"
    }
}

/// イベントのバナー背景（ID から決まる色相）。
private struct EventBannerBackground: View {
    let eventID: String

    var body: some View {
        let hue = LiveOpsFormat.hue(for: eventID)
        ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.65, brightness: 0.55),
                                    Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "sparkles")
                .font(.system(size: 90, weight: .bold))
                .foregroundStyle(.white.opacity(0.09))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 14, y: -14)
        }
    }
}

// MARK: - UI052 イベント一覧

struct EventsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScreenScaffold(title: L("イベント", "Events")) {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                content(now: ctx.date)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let active = LiveOpsEvents.active(now: now)
        let upcoming = LiveOpsEvents.upcoming(now: now)
        if active.isEmpty && upcoming.isEmpty {
            Panel {
                LiveOpsEmptyState(symbol: "calendar.badge.clock",
                                  title: L("現在開催中のイベントはありません", "No events right now"),
                                  message: L("新しいイベントはお知らせでご案内します。デイリー・ウィークリーミッションで報酬を獲得しましょう。",
                                             "New events will be announced in Notices. Meanwhile, earn rewards from daily and weekly missions."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .bottom) {
                Button {
                    app.router.push(.missions)
                } label: {
                    Label(L("ミッションへ", "Go to Missions"), systemImage: "checklist")
                }
                .buttonStyle(LiveOpsTallButtonStyle(base: SecondaryButtonStyle()))
                .padding(.bottom, 18)
                .accessibilityIdentifier("events_open_missions")
            }
        } else {
            // 開催中（終了が近い順）→ 開催予定（開始が近い順）。状態はカードのタグで示す
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(active + upcoming) { event in
                        EventCard(event: event, now: now) {
                            app.audio.play(.uiTap)
                            app.router.push(.eventDetail(event.id))
                        }
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }
}

private struct EventCard: View {
    let event: EventDef
    let now: Date
    let onOpen: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let phase = LiveOpsEventPhase.of(event, now: now)
        let missions = LiveOpsMissions.event(event, profile: app.profile)
        let done = missions.filter { $0.state != .inProgress }.count
        let claimable = missions.filter { $0.state == .claimable }.count
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    LiveOpsTag(text: phase.label, symbol: phase.symbol, color: phase.color)
                    if claimable > 0 && phase == .active {
                        LiveOpsTag(text: L("受取可能 \(claimable)", "\(claimable) to claim"), symbol: "gift.fill", color: Theme.gold)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.7))
                }
                Text(LiveOpsEvents.title(event))
                    .font(Theme.heading(18))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(LiveOpsEvents.detail(event))
                    .font(Theme.body(12))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    if phase == .upcoming {
                        LiveOpsCountdownLabel(target: event.start, prefix: L("開始まで", "Starts in"), symbol: "hourglass", tint: Theme.cyan)
                    } else {
                        LiveOpsCountdownLabel(target: event.end, prefix: L("終了まで", "Ends in"))
                    }
                    Spacer(minLength: 0)
                    if !missions.isEmpty {
                        Text("\(done) / \(missions.count)")
                            .font(Theme.mono(12))
                            .foregroundStyle(.white.opacity(0.85))
                            .monospacedDigit()
                    }
                }
                if !missions.isEmpty {
                    LiveOpsProgressBar(fraction: Double(done) / Double(missions.count), tint: Theme.gold, height: 6)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(EventBannerBackground(eventID: event.id))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(LiveOpsEvents.title(event)), \(phase.label)")
        .accessibilityIdentifier("event_card_\(event.id)")
    }
}

// MARK: - UI053 イベント詳細

struct EventDetailView: View {
    let eventID: String
    @Environment(AppModel.self) private var app
    @State private var reward: RewardClaimContent?

    var body: some View {
        let event = LiveOpsEvents.event(id: eventID)
        ScreenScaffold(title: event.map(LiveOpsEvents.title) ?? L("イベント詳細", "Event Details")) {
            Group {
                if let event {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        detail(event, now: ctx.date)
                    }
                } else {
                    Panel {
                        LiveOpsEmptyState(symbol: "questionmark.folder",
                                          title: L("イベントが見つかりません", "Event not found"),
                                          message: L("このイベントは終了したか、配信が取り下げられました。", "This event has ended or is no longer available."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .rewardClaimPopup($reward)
    }

    private func detail(_ event: EventDef, now: Date) -> some View {
        let phase = LiveOpsEventPhase.of(event, now: now)
        let missions = LiveOpsMissions.event(event, profile: app.profile)
        return HStack(alignment: .top, spacing: 14) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        LiveOpsTag(text: phase.label, symbol: phase.symbol, color: phase.color)
                        Spacer(minLength: 0)
                    }
                    Text(LiveOpsEvents.title(event))
                        .font(Theme.title(20))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(LiveOpsEvents.period(event), systemImage: "calendar")
                        .font(Theme.body(12))
                        .foregroundStyle(.white.opacity(0.85))
                    switch phase {
                    case .upcoming:
                        LiveOpsCountdownLabel(target: event.start, prefix: L("開始まで", "Starts in"), symbol: "hourglass", tint: Theme.cyan)
                    case .active:
                        LiveOpsCountdownLabel(target: event.end, prefix: L("終了まで", "Ends in"))
                    case .ended:
                        Label(L("このイベントは終了しました", "This event has ended"), systemImage: "flag.checkered")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Divider().overlay(Color.white.opacity(0.2))
                    Text(LiveOpsEvents.detail(event))
                        .font(Theme.body(13))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(EventBannerBackground(eventID: event.id))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1))
            .frame(width: 300)

            missionPanel(event: event, phase: phase, missions: missions)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func missionPanel(event: EventDef, phase: LiveOpsEventPhase, missions: [LiveOpsMissionEntry]) -> some View {
        let claimable = missions.filter { $0.state == .claimable }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LiveOpsSectionHeader(title: L("イベントミッション", "Event Missions"), symbol: "flag.fill")
                Spacer()
                if phase == .active && claimable.count > 1 {
                    Button {
                        claim(claimable.map(\.id))
                    } label: {
                        Label(L("すべて受け取る", "Claim All"), systemImage: "gift.fill").fixedSize()
                    }
                    .buttonStyle(LiveOpsCompactButtonStyle())
                    .accessibilityIdentifier("event_claim_all")
                }
            }
            if missions.isEmpty {
                Panel {
                    LiveOpsEmptyState(symbol: "flag.slash",
                                      title: L("ミッションはありません", "No missions"),
                                      message: L("このイベントには達成ミッションがありません。", "This event has no missions."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                if phase != .active {
                    Text(phase == .upcoming ? L("イベント開始後に進行・受け取りができます。", "Progress and claims open when the event starts.")
                                            : L("イベント期間が終了したため受け取れません。", "The event has ended; rewards can no longer be claimed."))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 8) {
                        ForEach(LiveOpsMissions.displayOrder(missions)) { entry in
                            LiveOpsMissionRow(entry: entry, claimEnabled: phase == .active) { claim([entry.id]) }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func claim(_ ids: [String]) {
        guard let event = LiveOpsEvents.event(id: eventID), LiveOpsEventPhase.of(event, now: Date()) == .active else {
            app.showToast(L("イベント期間外です", "The event is not active"))
            return
        }
        guard let rewards = LiveOpsClaims.claimMissions(ids, app: app) else { return }
        reward = LiveOpsClaims.content(for: rewards, app: app)
    }
}
