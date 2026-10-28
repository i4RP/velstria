import SwiftUI
import VelstriaCore

// 担当: 統合（契約）

@main
struct VelstriaApp: App {
    @State private var app = AppModel(persistence: DebugLaunch.makePersistence())
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .onAppear {
                    app.onLaunch()
                    DebugLaunch.apply(to: app)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        app.persistence.saveNow(app.profile)
                        app.account.autoSave()
                        app.friends.stop()
                    }
                    // 日付を跨いで復帰した場合のログインボーナス・デイリー更新（同日なら何もしない）
                    if phase == .active {
                        LiveOpsService.onLaunch(profile: &app.profile, master: app.master, now: Date())
                        app.friends.start()
                    }
                }
                // 招待リンク（velstria://join?code=XXXXXX）: 部屋コードでオンライン対戦の部屋に入る。
                // 共有されたリプレイ（.vreplay）を「VELSIA で開く」: 検証してから一覧に取り込む
                .onOpenURL { url in
                    if app.openFriendLink(url) { return }
                    if app.openOnlineJoinLink(url) { return }
                    guard ReplayArchiveService.isReplayFile(url) else { return }
                    Task { @MainActor in await ReplayArchiveService.handleOpenedFile(url, app: app) }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var battleSession: WorldBattleSession?

    var body: some View {
        ZStack {
            // アプリが開いている間、非バトルの世界はこの一枚を保つ。
            PartyBackdrop()
            #if DEBUG || SCREENSHOTS
            if DebugLaunch.args.contains("-heroGallery") {
                HeroGalleryView()
            } else {
                mainContent
            }
            #else
            mainContent
            #endif
            PartyInviteOverlay()
            ToastOverlay()
        }
        .onChange(of: app.activeBattle?.id, initial: true) { _, _ in
            battleSession = app.activeBattle.map { WorldBattleSession(launch: $0) }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private var mainContent: some View {
        ZStack {
            WorldShellView(battleSession: battleSession)
                .opacity(isFighting || app.activeMagicChess != nil ? 0 : 1)
                .allowsHitTesting(!isFighting && app.activeMagicChess == nil)
            if let session = battleSession, case .battle = session.phase {
                BattleContainerView(launch: session.launch) { outcome in
                    session.finish(outcome, app: app)
                }
                .id(session.launch.id)
            }
            if let launch = app.activeMagicChess {
                MagicChessGameView(launch: launch).id(launch.id)
            }
        }
    }

    private var isFighting: Bool {
        guard let battleSession else { return false }
        if case .battle = battleSession.phase { return true }
        return false
    }
}

/// ロードと結果はワールドの枠内、実際の戦闘だけを画面いっぱいに表示する。
@Observable
@MainActor
final class WorldBattleSession {
    enum Phase {
        case loading
        case battle
        case result(BattleOutcome, RewardReport)
    }
    let launch: BattleLaunch
    var phase: Phase = .loading

    init(launch: BattleLaunch) { self.launch = launch }

    func finish(_ outcome: BattleOutcome, app: AppModel) {
        guard case .battle = phase else { return }
        let mode = launch.config.mode
        if launch.isOnline {
            app.online?.matchEnded(aborted: outcome.abandoned || outcome.summary.endReason == .aborted,
                                   spectating: launch.onlineSpectator)
        }
        if outcome.abandoned && (mode == .practice || mode == .tutorial) {
            if mode == .tutorial { app.profile.tutorialCompleted = true }
            app.dismissBattle()
            return
        }
        phase = .result(outcome, app.completeBattle(outcome))
    }
}

/// 画面上部のトースト。
struct ToastOverlay: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack {
            if let msg = app.toast {
                Text(msg)
                    .font(Theme.body(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .overlay(Capsule().stroke(Theme.panelStroke))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: msg) {
                        try? await Task.sleep(for: .seconds(2.2))
                        withAnimation { app.toast = nil }
                    }
                    .accessibilityIdentifier("toast")
            }
            Spacer()
        }
        .padding(.top, 12)
        .animation(.spring(duration: 0.3), value: app.toast)
        .allowsHitTesting(false)
    }
}
