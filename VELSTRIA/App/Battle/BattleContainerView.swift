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
                if controller.isOnline {
                    OnlineBattleOverlay(controller: controller, session: app.online) {
                        app.audio.stopMusic()
                        finish(controller.makeOutcome(abandoned: false))
                    }
                }
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
        if c.isOnline { app.online?.attach(controller: c) }
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
        audioDirector?.stop()
        controller?.aim = nil
        if controller?.isOnline == true { app.online?.detach() }
    }
}

/// オンライン対戦の重ね表示（HUD の上）。担当: online。
/// - 待機: 読み込み待ち・配信待ち（観戦席は遅延の説明）。
/// - 中断: ホストとの切断・ホストの中断で試合が終わった。HUD は中断では終了演出を出さないので、ここで「退出」を出す。
/// - 観戦者数: 選手には観戦している人数と遅延を小さく見せる（観戦されていること・ゴースティング対策が分かるように）。
struct OnlineBattleOverlay: View {
    let controller: BattleController
    /// 部屋（観戦の遅延・実況の有無）。
    var session: OnlineSession?
    /// 中断で終わった試合の「退出」（BattleContainerView の終了処理へ）。
    var onLeave: () -> Void = {}

    @Environment(AppModel.self) private var app
    @State private var leaving = false

    var body: some View {
        let status = controller.onlineStatus
        let interrupted = controller.isEnded && status == .disconnected
        // HUD と同じく Safe Area を読んでから画面全体へ広げる
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let full = CGSize(width: geo.size.width + safe.leading + safe.trailing,
                              height: geo.size.height + safe.top + safe.bottom)
            let layout = HUDLayout(size: full, safe: safe, leftHanded: app.profile.settings.leftHandedLayout)
            ZStack {
                if !controller.isSpectating && !controller.isEnded {
                    spectatorBadge(layout)
                }
                if interrupted {
                    interruptedPrompt
                        .transition(.opacity)
                } else if status != .none {
                    waitingBox(status)
                        .position(x: layout.width / 2, y: layout.height / 2)
                        .transition(.opacity)
                }
            }
            .frame(width: full.width, height: full.height)
            .offset(x: -safe.leading, y: -safe.top)
        }
        .animation(.easeInOut(duration: 0.25), value: status)
        .animation(.easeInOut(duration: 0.25), value: interrupted)
    }

    // MARK: 待機

    private func waitingBox(_ status: OnlineBattleStatus) -> some View {
        VStack(spacing: 8) {
            ProgressView().tint(Theme.gold)
            Text(text(status))
                .font(Theme.heading(15))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.panelStroke))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("online_battle_status")
        .allowsHitTesting(false)
    }

    private func text(_ s: OnlineBattleStatus) -> String {
        switch s {
        case .none: return ""
        case .waitingForPlayers: return L("他のプレイヤーの読み込みを待っています…", "Waiting for other players to load…")
        case .waitingForHost(let seconds):
            if controller.launch.onlineSpectator, let delay = controller.onlineSpectatorDelaySeconds, delay > 0,
               controller.state.tick == 0 {
                // 観戦の開始直後: ホストは遅延の分だけ配信を溜めてから出す
                return L("観戦は \(Int(delay.rounded())) 秒遅れで配信されます。まもなく始まります…（\(Int(seconds)) 秒）",
                         "Spectating is delayed by \(Int(delay.rounded()))s. Starting soon… (\(Int(seconds))s)")
            }
            return L("ホストからの配信を待っています… (\(Int(seconds)) 秒)", "Waiting for the host… (\(Int(seconds))s)")
        case .disconnected: return L("接続が切れました。試合を終了します", "Connection lost. Ending the match")
        }
    }

    // MARK: 中断

    private var interruptedPrompt: some View {
        let connected = controller.online?.isConnected ?? false
        return ZStack {
            // 試合は終わっているので HUD の操作を塞ぐ
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
            VStack(spacing: 12) {
                Image(systemName: connected ? "flag.slash.fill" : "wifi.exclamationmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.danger)
                    .accessibilityHidden(true)
                Text(L("試合が中断されました", "Match Interrupted"))
                    .font(Theme.title(22))
                    .foregroundStyle(.white)
                Text(connected ? L("ホストが試合を終了しました。", "The host ended the match.")
                               : L("ホストとの接続が切れました。", "Lost connection to the host."))
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    guard !leaving else { return }
                    leaving = true
                    onLeave()
                } label: {
                    Label(controller.isSpectating ? L("観戦を終える", "Stop Watching") : L("退出", "Leave"),
                          systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(minWidth: 180, minHeight: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(leaving)
                .accessibilityIdentifier("online_battle_leave")
            }
            .padding(22)
            .frame(maxWidth: 380)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.panelStroke))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("online_battle_interrupted")
        }
    }

    // MARK: 観戦者数（選手向け）

    /// 選手に見せる観戦の状況: 観戦者数（ホストの実況を含む）、実況の印、観戦席への遅延（実況は遅延なし）。
    @ViewBuilder
    private func spectatorBadge(_ layout: HUDLayout) -> some View {
        let count = controller.onlineSpectatorCount
        if count > 0, let room = session?.room {
            let s = min(layout.scale, 1.1)
            let caster = room.hostIsCaster
            // 観戦席の観戦者（実況を除く）がいる時だけ遅延を出す
            let delay: Int? = count - (caster ? 1 : 0) > 0 ? Int(room.spectatorDelaySeconds.rounded()) : nil
            HStack(spacing: 4 * s) {
                Image(systemName: "eye.fill")
                Text("\(count)").monospacedDigit()
                if caster {
                    // ホストの実況は権威シミュレーションそのもの（遅延なし）
                    Image(systemName: "mic.fill")
                    Text(L("実況", "Cast"))
                }
                if let delay {
                    Text(delay > 0 ? L("\(delay)秒遅れ", "\(delay)s delay") : L("遅延なし", "No delay"))
                }
            }
            .font(.system(size: 10 * s, weight: .heavy, design: .rounded))
            .foregroundStyle((delay ?? 1) > 0 ? Color.white.opacity(0.85) : Theme.gold)
            .padding(.horizontal, 8 * s)
            .padding(.vertical, 3 * s)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .overlay(Capsule().stroke(Theme.panelStroke))
            .fixedSize()
            // スコア表示（上中央、topEdge + 22 が中心で高さ約 45×s）の真下
            .position(x: layout.width / 2, y: layout.topEdge + 22 + 23 * s + 4 + 9 * s)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(badgeAccessibilityLabel(count: count, delay: delay, caster: caster))
            .accessibilityIdentifier("online_spectator_count")
            .allowsHitTesting(false)
        }
    }

    private func badgeAccessibilityLabel(count: Int, delay: Int?, caster: Bool) -> String {
        var parts = [L("観戦者 \(count) 人", "\(count) watching")]
        if caster { parts.append(L("ホストが実況中（遅延なし）", "the host is casting live")) }
        if let delay {
            parts.append(delay > 0 ? L("観戦席は \(delay) 秒遅れで配信", "spectators see a \(delay) second delay")
                                   : L("観戦席も遅延なし", "spectators have no delay"))
        }
        return parts.joined(separator: L("、", ", "))
    }
}
