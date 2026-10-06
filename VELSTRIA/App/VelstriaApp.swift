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
                    // 日付を跨いで復帰した場合のログインボーナス・デイリー更新（同日なら何もしない）
                    if phase == .active { LiveOpsService.onLaunch(profile: &app.profile, master: app.master, now: Date()) }
                }
                // 共有されたリプレイ（.vreplay）を「VELSIA で開く」: 検証してから一覧に取り込む
                .onOpenURL { url in
                    guard ReplayArchiveService.isReplayFile(url) else { return }
                    Task { @MainActor in await ReplayArchiveService.handleOpenedFile(url, app: app) }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var showsBrandLaunch = !DebugLaunch.isUITesting

    var body: some View {
        @Bindable var router = app.router
        ZStack {
            #if DEBUG || SCREENSHOTS
            // 開発用のヒーロー 3D モデル一覧（出荷ビルドには含めない。DebugLaunch 参照）
            if DebugLaunch.args.contains("-heroGallery") {
                HeroGalleryView()
            } else {
                mainContent
            }
            #else
            mainContent
            #endif
            ToastOverlay()
            if showsBrandLaunch {
                BrandLaunchView {
                    withAnimation(.easeOut(duration: 0.45)) { showsBrandLaunch = false }
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .id(app.profile.settings.language)
        .fullScreenCover(isPresented: $router.isMatchFlowPresented) {
            MatchFlowView().environment(app)
        }
        .fullScreenCover(item: Binding(get: { app.activeBattle }, set: { app.activeBattle = $0 })) { launch in
            BattleSessionView(launch: launch).environment(app)
        }
        .fullScreenCover(item: Binding(get: { app.activeMagicChess }, set: { app.activeMagicChess = $0 })) { launch in
            MagicChessGameView(launch: launch).environment(app)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    @ViewBuilder
    private var mainContent: some View {
        @Bindable var router = app.router
        if app.profile.onboardingCompleted {
            NavigationStack(path: $router.path) {
                HomeView()
                    .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
            }
        } else {
            OnboardingFlowView()
        }
    }
}

/// ネイティブのシルエットロゴからキービジュアルへつなぐ起動シーケンス。
private struct BrandLaunchView: View {
    let onFinished: () -> Void
    @State private var revealsWorld = false
    @State private var progress = 0.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.012, green: 0.016, blue: 0.055).ignoresSafeArea()

                if revealsWorld {
                    Image("LoadingKeyArt")
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    LinearGradient(colors: [.black.opacity(0.08), .clear, .black.opacity(0.86)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                    VStack {
                        Image("BrandLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: min(620, geo.size.width * 0.52))
                            .shadow(color: Theme.cyan.opacity(0.42), radius: 24)
                        Spacer()
                        VStack(spacing: 9) {
                            Text(L("星環を再構築しています…", "REBUILDING THE STAR RING…"))
                                .font(Theme.heading(12))
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.9))
                            FlowProgressBar(value: progress, tint: Theme.gold, height: 5)
                                .frame(maxWidth: min(760, geo.size.width * 0.72))
                        }
                        .padding(.bottom, 30)
                    }
                    .padding(.top, 20)
                    .transition(.opacity)
                } else {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(330, geo.size.height * 0.48), height: min(330, geo.size.height * 0.48))
                        .foregroundStyle(.white)
                        .shadow(color: Theme.cyan.opacity(0.7), radius: 28)
                        .transition(.scale(scale: 0.86).combined(with: .opacity))
                }
            }
        }
        .persistentSystemOverlays(.hidden)
        .task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeInOut(duration: 0.7)) { revealsWorld = true }
            withAnimation(.easeInOut(duration: 1.55)) { progress = 1 }
            try? await Task.sleep(for: .milliseconds(1850))
            onFinished()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("VELSIA を起動しています", "Launching VELSIA"))
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
                if launch.isOnline { app.online?.matchEnded(aborted: outcome.abandoned || outcome.summary.endReason == .aborted) }
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
