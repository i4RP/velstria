import SwiftUI
import VelstriaCore

// 担当: battle-hud。戦闘 HUD の全体構成（BattleSceneView の上に重ねる）。
// 左上: ミニマップ / 上中央: キル数と時間 / 右上: K/D/A・CS・スコアボード・ポーズ / 右: キルフィード
// 左下: スティック / 右下: 攻撃・スキル・スペル・帰還 / 下中央: ヒーローパネル
// 観戦・リプレイでは操作部品を隠し、速度・追従・進行バーを出す。左利き配置では左右を反転する。
// 15Hz で変わる値は各レイヤーの小さなビューだけが読む（HUD 全体の body を毎回評価しない）。

struct BattleHUDView: View {
    let controller: BattleController
    let onFinish: (BattleOutcome) -> Void

    @Environment(AppModel.self) private var app
    @State private var model: HUDModel

    init(controller: BattleController, onFinish: @escaping (BattleOutcome) -> Void) {
        self.controller = controller
        self.onFinish = onFinish
        _model = State(initialValue: HUDModel(controller: controller))
    }

    var body: some View {
        // Safe Area を読むため GeometryReader 自体は Safe Area 内に置き、HUD は画面全体へ広げる
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let full = CGSize(width: geo.size.width + safe.leading + safe.trailing,
                              height: geo.size.height + safe.top + safe.bottom)
            let layout = HUDLayout(size: full, safe: safe, leftHanded: model.settings.leftHandedLayout)
            HUDRoot(model: model, layout: layout)
                .offset(x: -safe.leading, y: -safe.top)
                .onAppear { model.layout = layout }
                .onChange(of: layout) { _, new in model.layout = new }
        }
        .background(HUDTicker(controller: controller, model: model))
        .onAppear { model.start(app: app, onFinish: onFinish) }
        .onDisappear { model.stop() }
        .onChange(of: controller.isPaused) { _, paused in
            if paused { model.externallyPaused() }
        }
    }
}

/// hudTick（15Hz）の観測専用。
private struct HUDTicker: View {
    let controller: BattleController
    let model: HUDModel

    var body: some View {
        Color.clear
            .onChange(of: controller.hudTick) { model.refresh() }
            .accessibilityHidden(true)
    }
}

private struct HUDRoot: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        // 読み込み幕が上がるまで HUD を置かない（見えない HUD が操作・VoiceOver・UI テストの対象にならないように）
        ZStack {
            if model.isReady {
                layers.transition(.opacity)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .coordinateSpace(name: HUDSpace.name)
        .animation(.easeOut(duration: 0.35), value: model.isReady)
    }

    @ViewBuilder
    private var layers: some View {
        let spectating = model.isSpectating
        let settings = model.settings
        let ended = model.endPhase != nil
        let tutorialDone = model.tutorial?.isComplete ?? false
        let showControls = !spectating && !ended && !tutorialDone
        ZStack {
            if !spectating { HUDVignetteLayer(model: model) }
            if showControls { HUDDeathLayer(model: model, scale: layout.scale) }

            // 操作部品と情報（HUD の不透明度を適用）
            Group {
                if showControls {
                    HUDJoystick(model: model, layout: layout, mode: settings.joystickMode,
                                highlighted: model.tutorial?.highlight == .joystick)
                    HUDActionCluster(model: model, layout: layout)
                    HUDHeroPanel(model: model, layout: layout)
                        .position(x: layout.heroPanelCenterX, y: layout.bottomEdge - HUDRootMetrics.heroPanelHeight(layout) / 2)
                    HUDChannelLayer(model: model, layout: layout)
                    HUDLevelUpLayer(model: model)
                        .position(x: layout.width / 2, y: layout.height * 0.36)
                }
                if spectating && !ended {
                    HUDSpectateLayer(model: model, layout: layout)
                }
                HUDMinimapView(model: model, size: layout.minimapSize)
                    .position(x: layout.minimapFrame.midX, y: layout.minimapFrame.midY)
                HUDScoreLayer(model: model, layout: layout)
                HUDTopRight(model: model, scale: min(layout.scale, 1.1))
                    .fixedSize()
                    .opacity(model.isAiming ? 0.25 : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, layout.topEdge)
                    .padding(.trailing, layout.width - layout.trailingEdge)
                HUDKillFeedLayer(model: model, layout: layout)
            }
            .opacity(settings.hudOpacity)

            HUDBannerLayer(model: model, layout: layout)
            if !ended && !tutorialDone { HUDTutorialLayer(model: model, layout: layout) }
            if !ended { HUDSurrenderLayer(model: model, layout: layout) }
            HUDAimOverlay(visual: model.aimVisual, layout: layout)

            HUDPanelsLayer(model: model, layout: layout)
            HUDToastLayer(model: model, layout: layout, showControls: showControls)

            if tutorialDone && !ended, let tutorial = model.tutorial {
                HUDTutorialComplete(model: model, director: tutorial)
                    .transition(.opacity)
            }
            if let phase = model.endPhase {
                HUDEndOfMatchView(model: model, phase: phase, colorblind: settings.colorblindMode)
                    .transition(.opacity)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .animation(.easeInOut(duration: 0.4), value: tutorialDone)
        .animation(.easeInOut(duration: 0.4), value: ended)
    }
}

enum HUDRootMetrics {
    static func heroPanelHeight(_ layout: HUDLayout) -> CGFloat { 110 * min(layout.scale, 1.08) }
}

// MARK: - レイヤー（それぞれが必要な値だけを観測する）

private struct HUDVignetteLayer: View {
    let model: HUDModel

    var body: some View {
        let v = model.vitals
        HUDLowHealthVignette(active: !model.hero.isDead && v.maxHP > 1 && v.hpRatio < 0.3)
    }
}

private struct HUDDeathLayer: View {
    let model: HUDModel
    let scale: CGFloat

    var body: some View {
        ZStack {
            if model.hero.isDead {
                HUDDeathOverlay(model: model, scale: scale)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.hero.isDead)
    }
}

private struct HUDChannelLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        HUDChannelBar(channel: model.hero.channel, width: 210)
            .position(x: layout.heroPanelCenterX,
                      y: layout.bottomEdge - HUDRootMetrics.heroPanelHeight(layout) - 60 * min(layout.scale, 1.08))
    }
}

private struct HUDLevelUpLayer: View {
    let model: HUDModel

    var body: some View {
        HUDLevelUpText(pulse: model.levelUpPulse, level: model.lastLevelUp)
    }
}

private struct HUDSpectateLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let barHeight: CGFloat = model.spectate.finalTick == nil ? 64 : 88
        ZStack {
            HUDSpectateBar(model: model, layout: layout)
                .fixedSize()
                .position(x: layout.width / 2, y: layout.bottomEdge - barHeight / 2)
            HUDSpectateScore(model: model)
                .position(x: layout.width / 2, y: layout.topEdge + 62)
        }
    }
}

private struct HUDScoreLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        HUDScoreCapsule(top: model.top, colorblind: model.settings.colorblindMode, scale: min(layout.scale, 1.1))
            .position(x: layout.width / 2, y: layout.topEdge + 22)
    }
}

private struct HUDKillFeedLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        HUDKillFeed(entries: model.killFeed, colorblind: model.settings.colorblindMode)
            .opacity(model.isAiming ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, layout.topEdge + 52)
            .padding(.trailing, layout.width - layout.trailingEdge)
    }
}

private struct HUDBannerLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        HUDBannerView(banner: model.banner, colorblind: model.settings.colorblindMode, scale: min(layout.scale, 1.1))
            .position(x: layout.width / 2, y: layout.height * (model.tutorial == nil ? 0.27 : 0.46))
    }
}

private struct HUDTutorialLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        if let tutorial = model.tutorial {
            HUDTutorialCard(director: tutorial, scale: min(layout.scale, 1.1))
                .position(x: layout.width / 2, y: layout.topEdge + 96 * min(layout.scale, 1.1))
        }
    }
}

private struct HUDSurrenderLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        ZStack {
            if let surrender = model.surrender {
                HUDSurrenderPanel(model: model, snapshot: surrender)
                    .fixedSize()
                    .position(x: layout.minimapFrame.minX + 110, y: layout.minimapFrame.maxY + 84)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.surrender == nil)
    }
}

private struct HUDToastLayer: View {
    let model: HUDModel
    let layout: HUDLayout
    let showControls: Bool

    var body: some View {
        // ショップを開いている間は所持品の上、それ以外はヒーローパネル（と詠唱バー）の上
        let inShop = model.panel == .shop
        let x = inShop || !showControls ? layout.width / 2 : layout.heroPanelCenterX
        let y = inShop ? layout.bottomEdge - 84
            : layout.bottomEdge - (showControls ? HUDRootMetrics.heroPanelHeight(layout) + 104 * min(layout.scale, 1.08) : 100)
        HUDToastView(toast: model.toast)
            .position(x: x, y: y)
    }
}

private struct HUDPanelsLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        ZStack {
            if let panel = model.panel {
                Color.black.opacity(panel == .pause ? 0.55 : 0.35)
                    .contentShape(Rectangle())
                    .onTapGesture { if panel != .pause { model.closePanel() } }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                switch panel {
                case .shop:
                    HUDShopPanel(model: model, layout: layout)
                        .padding(.leading, layout.leadingEdge + 4)
                        .padding(.trailing, layout.width - layout.trailingEdge + 4)
                        .padding(.top, layout.topEdge + 4)
                        .padding(.bottom, layout.height - layout.bottomEdge + 2)
                        .transition(.move(edge: layout.leftHanded ? .leading : .trailing).combined(with: .opacity))
                case .scoreboard:
                    HUDScoreboardPanel(model: model, layout: layout)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, layout.leadingEdge + 4)
                        .padding(.trailing, layout.width - layout.trailingEdge + 4)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                case .pause:
                    HUDPauseMenu(model: model)
                        .fixedSize()
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
        }
        .frame(width: layout.width, height: layout.height)
        .animation(.spring(duration: 0.3), value: model.panel)
    }
}
