import SwiftUI
import VelstriaCore

// 担当: battle-hud（Wave 2）。戦闘画面の入れ物。
// - BattleController(launch:) を所有し、BattleSceneView（3D）の上に BattleHUDView を重ねる
// - 設定の反映（カメラ距離、スキル自動習得。チュートリアルは習得操作を教えるため手動）
// - バックグラウンド移行で一時停止（オフライン対戦なので世界ごと止める）
// - 戦闘 BGM の開始・終了、効果音/触覚の BattleAudioDirector
// - 描画側がループを回すまでの予備駆動（BattleLoopFallback）
// 結果は onFinish(controller.makeOutcome(abandoned:)) で返す（HUD の「続ける」「退出」「チュートリアル完了」から）。

struct BattleContainerView: View {
    let launch: BattleLaunch
    let onFinish: (BattleOutcome) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: BattleController?
    @State private var audioDirector: BattleAudioDirector?
    /// シークできる観戦・リプレイの事前計算（先のキーフレーム・年表・メインスレッド外のシーク）。
    @State private var baker: ReplayBaker?
    @State private var loop = BattleLoopFallback()
    /// 戦闘前の自動ロックの設定（観戦は画面に触れないので、戦闘中は自動ロックを止めて終わったら戻す）。
    @State private var previousIdleTimerDisabled: Bool?

    init(launch: BattleLaunch, onFinish: @escaping (BattleOutcome) -> Void) {
        self.launch = launch
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let controller {
                BattleSceneView(controller: controller)
                    .ignoresSafeArea()
                BattleHUDView(controller: controller) { outcome in
                    finish(outcome)
                }
                if controller.isOnline { OnlineBattleOverlay(controller: controller) }
                #if DEBUG
                if DebugLaunch.isUITesting { uiTestFastForwardButton(controller) }
                #endif
            }
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .onAppear(perform: startIfNeeded)
        .onDisappear(perform: tearDown)
        .onChange(of: scenePhase) { _, phase in
            // オンライン対戦は世界を止められない（他の参加者がいる）
            guard let controller, phase != .active, !controller.isEnded, !controller.isOnline else { return }
            controller.isPaused = true
        }
    }

    private func startIfNeeded() {
        guard controller == nil else { return }
        if previousIdleTimerDisabled == nil {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        // 保険: 戦闘描画より前にヒーローのアセットを揃える（ロード画面で 1 人ずつ済んでいればキャッシュ参照だけ）
        HeroModelLibrary.preload(players: launch.config.players.map { ($0.heroID, $0.skinID) }, master: app.master)
        let c = BattleController(launch: launch, online: launch.isOnline ? app.online : nil)
        let settings = app.profile.settings
        c.cameraZoom = settings.cameraZoom
        if !c.isSpectating {
            // チュートリアルはスキル習得（＋）の操作を教えるため自動習得を切る
            let auto = launch.config.mode == .tutorial ? false : settings.autoLevelSkills
            c.send(.setAutoLevel(enabled: auto))
        }
        controller = c
        DebugLaunch.battleDidStart(c)
        if c.isOnline { app.online?.attach(controller: c) }
        if let b = ReplayBaker(controller: c) {
            b.start()
            baker = b
        }
        let director = BattleAudioDirector(controller: c, app: app)
        director.start()
        audioDirector = director
        app.audio.playMusic(.battle)
        loop.start(controller: c)
    }

    #if DEBUG
    /// UI テスト用の早送り（リザルトまでの画面遷移を短時間で検証する）。DEBUG かつ -uiTesting のみ。
    private func uiTestFastForwardButton(_ controller: BattleController) -> some View {
        Button("FF") {
            Task {
                await controller.debugFastForward()
                finish(controller.makeOutcome(abandoned: false))
            }
        }
        .font(Theme.mono(11))
        .padding(6)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .accessibilityIdentifier("battle_stub_simulate")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 4)
    }
    #endif

    private func finish(_ outcome: BattleOutcome) {
        tearDown()
        onFinish(outcome)
    }

    private func tearDown() {
        if let previous = previousIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = previous
            previousIdleTimerDisabled = nil
        }
        loop.stop()
        baker?.stop()
        baker = nil
        audioDirector?.stop()
        controller?.aim = nil
        if controller?.isOnline == true { app.online?.detach() }
    }
}

/// オンライン対戦の待機・切断表示（HUD の上に重ねる）。
struct OnlineBattleOverlay: View {
    let controller: BattleController

    var body: some View {
        let status = controller.onlineStatus
        ZStack {
            if status != .none {
                VStack(spacing: 8) {
                    ProgressView().tint(Theme.gold)
                    Text(text(status))
                        .font(Theme.heading(15))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.panelStroke))
                .transition(.opacity)
                .accessibilityIdentifier("online_battle_status")
            }
        }
        .animation(.easeInOut(duration: 0.25), value: status)
        .allowsHitTesting(false)
    }

    private func text(_ s: OnlineBattleStatus) -> String {
        switch s {
        case .none: return ""
        case .waitingForPlayers: return L("他のプレイヤーの読み込みを待っています…", "Waiting for other players to load…")
        case .waitingForHost(let seconds):
            return L("ホストからの配信を待っています… (\(Int(seconds)) 秒)", "Waiting for the host… (\(Int(seconds))s)")
        case .disconnected: return L("接続が切れました。試合を終了します", "Connection lost. Ending the match")
        }
    }
}
