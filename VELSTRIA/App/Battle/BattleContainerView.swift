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
    @State private var loop = BattleLoopFallback()

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
            }
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .onAppear(perform: startIfNeeded)
        .onDisappear(perform: tearDown)
        .onChange(of: scenePhase) { _, phase in
            guard let controller, phase != .active, !controller.isEnded else { return }
            controller.isPaused = true
        }
    }

    private func startIfNeeded() {
        guard controller == nil else { return }
        let c = BattleController(launch: launch)
        let settings = app.profile.settings
        c.cameraZoom = settings.cameraZoom
        if !c.isSpectating {
            // チュートリアルはスキル習得（＋）の操作を教えるため自動習得を切る
            let auto = launch.config.mode == .tutorial ? false : settings.autoLevelSkills
            c.send(.setAutoLevel(enabled: auto))
        }
        controller = c
        let director = BattleAudioDirector(controller: c, app: app)
        director.start()
        audioDirector = director
        app.audio.playMusic(.battle)
        loop.start(controller: c)
    }

    private func finish(_ outcome: BattleOutcome) {
        tearDown()
        onFinish(outcome)
    }

    private func tearDown() {
        loop.stop()
        audioDirector?.stop()
        controller?.aim = nil
    }
}
