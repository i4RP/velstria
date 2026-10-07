import SwiftUI
import VelstriaCore

// 担当: battle-hud。戦闘 HUD の全体構成（BattleSceneView の上に重ねる）。
// 左上: ミニマップ（+ 全体マップボタン）と内側の縦列（端末状態・設定・消音・ズーム）/ 上中央: 味方 4 人の状態列と小型のスコア /
// 右上: K/D/A・CS・スコアボード、その下にクイックシグナルの列 / スコアの下: キルフィード / ミニマップの下: シグナルのメッセージ
// 左下: スティック / 右下: 攻撃・スキル・スペル・帰還 / 下中央: ヒーローパネル
// 観戦・リプレイでは操作部品を隠し、下部ドック（再生バー・10 人の追従・観戦メニュー）・ゴールドと目標タイマー・
// 情報パネルを出す（配置は HUDSpectatorLayout）。戦術マップを開いている間もドックは操作できる（マップの上に 1 段で出す）。
// シネマ表示では HUD を隠して戻すボタンだけを残す。左利き配置では左右を反転する。
// 死亡中: 色調（3D の上）、下部パネルの上に復活カウントのエンブレム（タップでデス情報パネル）と味方の追従一覧。
// 15Hz で変わる値は各レイヤーの小さなビューだけが読む（HUD 全体の body を毎回評価しない）。
// 観戦者は最下層の操作レイヤーで 3D 画面をドラッグ・ピンチ・ダブルタップできる（HUDSpectatorGestures）。
// 倒れている間は彩度を落とす幕（操作部品の下）と、復活までの秒・味方の一覧（操作部品の上）を出す。

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
            .onChange(of: controller.cameraViewportTick) { model.refreshMinimapCamera() }
            // 一時停止中の追従先・視界の切り替えもミニマップの輪・ヒーロー詳細へすぐ反映する（観戦）
            .onChange(of: controller.cameraMode) { model.cameraModeChanged() }
            .onChange(of: controller.spectatorVision) { model.cameraModeChanged() }
            .onChange(of: controller.seekingToTick) { model.seekStateChanged() }
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
            // 観戦者の 3D 画面の操作（最下層: 上の操作部品が先に触れる）
            if spectating && !ended {
                HUDSpectatorGestureLayer(model: model, layout: layout)
                    // 戦術マップの間は VoiceOver でマップのカードとドックだけを辿る（観戦ではマップを .isModal にしない）
                    .accessibilityHidden(model.isTacticalMapOpen)
            }
            if !spectating { HUDVignetteLayer(model: model) }
            if showControls { HUDDeathTintLayer(model: model) }

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
                if spectating {
                    HUDSpectatorInfoLayer(model: model, layout: layout)
                }
                HUDMinimapDock(model: model, layout: layout)
                HUDTopLayer(model: model, layout: layout)
                // シグナル列はチュートリアルでは出さないので、その間はキルフィードを端へ寄せたままにする
                HUDKillFeedLayer(model: model, layout: layout, reserveSignals: model.killFeedReservesSignals)
                // クイックチャットのメニュー（シグナル列の下へ開く）はキルフィードの上に重ねる
                if showControls { HUDSignalLayer(model: model, layout: layout) }
            }
            // シネマ表示（観戦）は HUD を隠して映像だけにする
            .opacity(spectating && model.spectator.isCinematic ? 0 : settings.hudOpacity)
            .allowsHitTesting(!model.isTacticalMapOpen && !(spectating && model.spectator.isCinematic))
            .accessibilityHidden(model.isTacticalMapOpen || (spectating && model.spectator.isCinematic))
            .animation(.easeInOut(duration: 0.3), value: model.spectator.isCinematic)

            // 倒れている間の情報と味方の一覧（操作部品より上: スティックの受付領域より先に触れる）
            if showControls {
                HUDDeathSpectateLayer(model: model, layout: layout)
                    .opacity(settings.hudOpacity)
                    .allowsHitTesting(!model.isTacticalMapOpen)
                    .accessibilityHidden(model.isTacticalMapOpen)
            }

            // 告知バナーはデス情報パネル（暗幕付き）の下に置き、開いている間にパネルの数値へ重ならないようにする。
            // 死亡中のバナーはエンブレム（下部パネルの上）の上端より上に出す（HUDRootMetrics.bannerCenterY）ので、閉じている時は両方見える。
            // チュートリアルのカードと降参の投票はデス情報パネルを開いている間は隠す（パネルの上に重ならないように）
            HUDBannerLayer(model: model, layout: layout)
            if showControls { HUDDeathInfoLayer(model: model, layout: layout) }
            if !ended && !tutorialDone { HUDTutorialLayer(model: model, layout: layout) }
            if !ended { HUDSurrenderLayer(model: model, layout: layout) }
            HUDAimOverlay(visual: model.aimVisual, layout: layout)

            // シークできる観戦・リプレイは終わった後もマップを開ける（終わった時刻の戦況を見る）
            if model.isTacticalMapOpen && (!ended || model.allowsPanelsAfterEnd) && !tutorialDone {
                HUDTacticalMap(model: model, layout: layout)
                    .zIndex(1)
            }
            if spectating {
                // 観戦の下部ドック: 戦術マップの上でも操作できる。再生終了のカードはドックと重ならない位置に出し、
                // 観戦メニュー（引き出しとその外側の暗幕）より上に置く（開いたまま終わってもカードのボタンが押せる）
                HUDSpectateDockLayer(model: model, layout: layout)
                    .zIndex(model.isTacticalMapOpen ? 1 : 0)
            }
            if spectating && model.controller.isSeekable {
                // 観戦・リプレイの終わり: 巻き戻して見直せるようにドックを残し、その上にカードを出す。
                // パネル（スコアボード・ポーズ・退出の確認）はカードより上（開いている間はカードを隠す）
                HUDSpectatorEndLayer(model: model, layout: layout)
            }

            HUDPanelsLayer(model: model, layout: layout)
            HUDToastLayer(model: model, layout: layout, showControls: showControls)

            if tutorialDone && !ended, let tutorial = model.tutorial {
                HUDTutorialComplete(model: model, director: tutorial)
                    .transition(.opacity)
            }
            if !(spectating && model.controller.isSeekable), let phase = model.endPhase {
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

    /// 告知バナーの高さの目安（肖像 44pt、または見出し + 副題 ≈ 46pt に上下 8pt。倍率は min(scale, 1.1)）。
    static func bannerHeight(_ layout: HUDLayout) -> CGFloat { 62 * min(layout.scale, 1.1) }

    /// 告知バナーの中心の高さ。通常は画面高さの 27%、チュートリアルは上の指示カードを避けて 46%。
    /// 死亡中は復活カウントのエンブレム（下部パネルの上）にかからないよう、帯の下端をエンブレムの上端より上に収める。
    static func bannerCenterY(_ layout: HUDLayout, tutorial: Bool, dead: Bool) -> CGFloat {
        let y = layout.height * (tutorial ? 0.46 : 0.27)
        guard dead else { return y }
        let emblemTop = layout.deathEmblemCenter.y - layout.deathEmblemSize.height / 2
        return min(y, emblemTop - 4 - bannerHeight(layout) / 2)
    }

    /// プレイヤーの告知バナーの中心（観戦は HUDSpectatorLayout）。死亡中はエンブレムの上に収める。
    static func playerBannerCenterY(_ layout: HUDLayout, heroDead: Bool) -> CGFloat {
        bannerCenterY(layout, tutorial: false, dead: heroDead)
    }
}

// MARK: - レイヤー（それぞれが必要な値だけを観測する）

private struct HUDVignetteLayer: View {
    let model: HUDModel

    var body: some View {
        let v = model.vitals
        HUDLowHealthVignette(active: !model.hero.isDead && v.maxHP > 1 && v.hpRatio < 0.3)
    }
}

/// 倒れている間の復活までの秒・味方の一覧（死亡中の味方追従）。
private struct HUDDeathSpectateLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        ZStack {
            if model.hero.isDead {
                HUDDeathOverlay(model: model, layout: layout)
                    .transition(.opacity)
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

/// 観戦: ゴールドとゴールド差・目標タイマー（上部中央）、情報パネル（右上ボタンの下）。
private struct HUDSpectatorInfoLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let spec = model.spectator
        let sl = HUDSpectatorLayout(base: layout, seekable: model.controller.isSeekable)
        let panelOpen = spec.panel != nil
        let cx = sl.topCenterX(panelOpen: panelOpen)
        ZStack {
            if model.endPhase == nil || model.controller.isSeekable {
                HUDSpectateScore(model: model)
                    .position(x: cx, y: sl.scorePillCenterY)
                if spec.showsObjectives {
                    HUDObjectiveStrip(model: model, maxWidth: sl.topCenterWidth(panelOpen: panelOpen))
                        .position(x: cx, y: sl.objectivesCenterY)
                }
                if panelOpen {
                    let frame = sl.infoPanelFrame
                    HUDSpectatorInfoPanel(model: model, layout: sl)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.move(edge: layout.leftHanded ? .leading : .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(width: layout.width, height: layout.height)
        .animation(.spring(duration: 0.3), value: spec.panel)
    }
}

/// 観戦: 下部ドックと観戦メニュー（引き出し）。シネマ表示中は戻すボタンだけ。
private struct HUDSpectateDockLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let spec = model.spectator
        let seekable = model.controller.isSeekable
        let mapOpen = model.isTacticalMapOpen
        let sl = HUDSpectatorLayout(base: layout, seekable: seekable, compact: mapOpen)
        ZStack {
            if spec.isCinematic {
                HUDCinematicRestoreButton(model: model)
                    .position(sl.cinematicRestoreCenter)
                    .transition(.opacity)
            } else if model.endPhase == nil || seekable {
                if spec.isDrawerOpen && !mapOpen {
                    // 引き出しの外をタップで閉じる
                    Color.black.opacity(0.18)
                        .contentShape(Rectangle())
                        .onTapGesture { model.toggleSpectatorDrawer() }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                    HUDSpectatorDrawer(model: model, layout: sl)
                        .frame(width: layout.width, height: max(0, sl.dockTop - 6), alignment: .bottom)
                        .position(x: layout.width / 2, y: max(0, sl.dockTop - 6) / 2)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HUDSpectateDock(model: model, layout: sl)
                    .position(x: sl.dockFrame.midX, y: sl.dockFrame.midY)
                    .opacity(model.settings.hudOpacity)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .animation(.spring(duration: 0.28), value: spec.isDrawerOpen)
        .animation(.easeInOut(duration: 0.3), value: spec.isCinematic)
    }
}

/// 再生終了のカードを出すか（観戦・リプレイ）。終わった後も右上のボタン（スコアボード・ポーズ・退出）と戦術マップは
/// 使えるので、それらを開いている間はカードを隠す（カードの下に開いて見えない・押せないことがないように）。
enum HUDSpectatorEndCardRule {
    @MainActor
    static func isVisible(_ model: HUDModel) -> Bool {
        let t = model.spectator.transport
        guard t.seekingTo == nil, model.panel == nil, !model.isTacticalMapOpen else { return false }
        return model.endPhase != nil || (t.isEnded && model.controller.state.endReason == .aborted)
    }
}

/// 観戦・リプレイの再生終了のカード（終了演出の代わり。ドックは残る）。記録が途中で終わったリプレイにも出す。
private struct HUDSpectatorEndLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let phase = model.endPhase
        let show = HUDSpectatorEndCardRule.isVisible(model)
        let sl = HUDSpectatorLayout(base: layout, seekable: true)
        ZStack {
            if show {
                Color.black.opacity(0.3)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                HUDSpectatorEndCard(model: model, phase: phase, colorblind: model.settings.colorblindMode)
                    .frame(maxWidth: min(520, sl.usableWidth), maxHeight: max(120, sl.dockTop - layout.topEdge - 8))
                    .position(sl.endCardCenter)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .frame(width: layout.width, height: layout.height)
        .animation(.easeInOut(duration: 0.3), value: show)
    }
}

private struct HUDKillFeedLayer: View {
    let model: HUDModel
    let layout: HUDLayout
    /// 情報側（右手配置は右、左利きは左）の端のシグナル列の分を空ける（操作中のみ）。
    let reserveSignals: Bool

    var body: some View {
        let reserve = reserveSignals ? layout.killFeedSideReserve : 0
        // 観戦の情報パネルを開いている間は同じ場所なので隠す（出来事の一覧に全部ある）
        let covered = model.isSpectating && model.spectator.panel != nil
        // シグナル列の分だけ内側（スコアの下）へ寄せている間は、画面中央の告知バナーと高さが重なるため、
        // バナーが出ている数秒だけ隠す（同じキルはバナーが大きく伝える。項目はバナーの後にまた見える）
        // レベルアップ表示（画面高さの 36%）とも 2 行目以降が重なるので、表示中（約 1.7 秒）は同じく隠す。
        // 隠れている間は項目の寿命を進めない（HUDModel.feedEntryExpired）ので、バナーが続いても一度も見えずに消えることはない
        let hidden = model.isAiming || covered || (reserve > 0 && model.killFeedYieldsToCenter)
        HUDKillFeed(entries: model.killFeed, colorblind: model.settings.colorblindMode)
            .opacity(hidden ? 0 : 1)
            .animation(.easeOut(duration: 0.2), value: hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout.topInfoAlignment)
            .padding(.top, layout.killFeedTop)
            .padding(.leading, layout.leadingEdge + (layout.leftHanded ? reserve : 0))
            .padding(.trailing, layout.width - layout.trailingEdge + (layout.leftHanded ? 0 : reserve))
    }
}

private struct HUDBannerLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        HUDBannerView(banner: model.banner, colorblind: model.settings.colorblindMode, scale: min(layout.scale, 1.1))
            .frame(maxWidth: maxWidth)
            .position(x: x, y: y)
            // シネマ表示（観戦）は告知も隠して映像だけにする
            .opacity(model.isSpectating && model.spectator.isCinematic ? 0 : 1)
            .animation(.easeInOut(duration: 0.3), value: model.spectator.isCinematic)
            .animation(.easeInOut(duration: 0.3), value: model.hero.isDead)
    }

    /// 観戦の情報パネルを開いている時は、ミニマップとパネルの間に収める（文字は縮む）。
    private var maxWidth: CGFloat? {
        guard model.isSpectating, model.spectator.panel != nil else { return nil }
        return HUDSpectatorLayout(base: layout, seekable: model.controller.isSeekable).topCenterWidth(panelOpen: true)
    }

    private var x: CGFloat {
        guard model.isSpectating else { return layout.width / 2 }
        return HUDSpectatorLayout(base: layout, seekable: model.controller.isSeekable)
            .topCenterX(panelOpen: model.spectator.panel != nil)
    }

    private var y: CGFloat {
        if model.tutorial != nil { return HUDRootMetrics.bannerCenterY(layout, tutorial: true, dead: model.hero.isDead) }
        // 観戦はゴールド・目標タイマーの帯の下に出す（低い画面で重ならないように）
        if model.isSpectating { return HUDSpectatorLayout(base: layout, seekable: model.controller.isSeekable).bannerCenterY }
        return HUDRootMetrics.playerBannerCenterY(layout, heroDead: model.hero.isDead)
    }
}

private struct HUDTutorialLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        if let tutorial = model.tutorial {
            HUDTutorialCard(director: tutorial, scale: min(layout.scale, 1.1))
                .position(x: layout.width / 2, y: layout.topEdge + 96 * min(layout.scale, 1.1))
                // デス情報パネル（この下の層）を開いている間は隠す
                .opacity(model.deathRecapOpen ? 0 : 1)
                .animation(.easeOut(duration: 0.2), value: model.deathRecapOpen)
        }
    }
}

private struct HUDSurrenderLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        // デス情報パネル（この下の層）を開いている間は隠す（閉じれば投票できる）
        let recapOpen = model.deathRecapOpen
        ZStack {
            if let surrender = model.surrender {
                HUDSurrenderPanel(model: model, snapshot: surrender)
                    .fixedSize()
                    .position(HUDSurrenderMetrics.center(layout))
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .opacity(recapOpen ? 0 : 1)
        .allowsHitTesting(!recapOpen)
        .accessibilityHidden(recapOpen)
        .animation(.easeInOut(duration: 0.3), value: model.surrender == nil)
        .animation(.easeOut(duration: 0.2), value: recapOpen)
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
        // 倒れている間は復活カウントのエンブレム（追従の一覧の上）の上に出す
        let dead = showControls && model.hero.isDead && !model.isSpectating
        let y = inShop ? layout.bottomEdge - 84
            : dead ? layout.deathEmblemCenter.y - layout.deathEmblemSize.height / 2 - 4 - 14
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
                        .padding(.leading, layout.leadingEdge + 4)
                        .padding(.trailing, layout.width - layout.trailingEdge + 4)
                        .padding(.top, layout.topEdge + 4)
                        .padding(.bottom, layout.height - layout.bottomEdge + 4)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
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
