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
                    if phase == .background { app.persistence.saveNow(app.profile) }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var router = app.router
        ZStack {
            if app.profile.onboardingCompleted {
                NavigationStack(path: $router.path) {
                    HomeView()
                        .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
                }
            } else {
                OnboardingFlowView()
            }
            ToastOverlay()
        }
        .id(app.profile.settings.language)
        .fullScreenCover(isPresented: $router.isMatchFlowPresented) {
            MatchFlowView().environment(app)
        }
        .fullScreenCover(item: Binding(get: { app.activeBattle }, set: { app.activeBattle = $0 })) { launch in
            BattleSessionView(launch: launch).environment(app)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
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

/// ロード → 戦闘 → リザルトの 1 セッション。
struct BattleSessionView: View {
    let launch: BattleLaunch
    @Environment(AppModel.self) private var app

    private enum Phase {
        case loading
        case battle
        case result(BattleOutcome, RewardReport)
    }

    @State private var phase: Phase = .loading

    var body: some View {
        switch phase {
        case .loading:
            LoadingScreenView(launch: launch) { phase = .battle }
        case .battle:
            BattleContainerView(launch: launch) { outcome in
                let mode = launch.config.mode
                if outcome.abandoned && (mode == .practice || mode == .tutorial) {
                    if mode == .tutorial { app.profile.tutorialCompleted = true }
                    app.dismissBattle()
                    return
                }
                let report = app.completeBattle(outcome)
                phase = .result(outcome, report)
            }
        case .result(let outcome, let report):
            MatchResultView(outcome: outcome, report: report) { app.dismissBattle() }
        }
    }
}
