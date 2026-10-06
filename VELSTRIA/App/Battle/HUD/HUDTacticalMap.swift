import SwiftUI
import VelstriaCore

/// 小さい地図のドラッグ操作と、全体確認用の44ptボタンを分ける。
struct HUDMinimapDock: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        VStack(spacing: 4) {
            HUDMinimapView(model: model, size: layout.minimapSize)
            Button { model.setTacticalMap(open: true) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "map.fill")
                        .foregroundStyle(HUDStyle.accent)
                    Text(L("全体マップ", "MAP OVERVIEW"))
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(width: layout.minimapSize, height: 32)
                .hudGlass(cornerRadius: 10)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(HUDPressStyle())
            .accessibilityLabel(L("全体マップを開く", "Open map overview"))
            .accessibilityIdentifier("hud_minimap_expand")
        }
        .frame(width: layout.minimapDockFrame.width, height: layout.minimapDockFrame.height)
        .position(x: layout.minimapDockFrame.midX, y: layout.minimapDockFrame.midY)
    }
}

/// 戦術マップの見出し・状態の文言（観戦・リプレイ・オンラインの観戦席・プレイヤーで変える）。
enum HUDTacticalMapText {
    enum Status: Equatable {
        /// プレイヤーの試合（進行中）。
        case live
        /// オンラインの観戦席（遅延付きのライブ）。
        case liveWatch
        /// AI 同士の観戦。
        case spectating
        case replay
        case paused
    }

    static func status(isSpectating: Bool, isReplay: Bool, isLiveWatcher: Bool, paused: Bool) -> Status {
        if isLiveWatcher { return .liveWatch }
        if isSpectating && paused { return .paused }
        if isReplay { return .replay }
        return isSpectating ? .spectating : .live
    }

    static func label(_ s: Status) -> String {
        switch s {
        case .live: return L("進行中", "LIVE")
        case .liveWatch: return "LIVE"
        case .spectating: return L("観戦中", "SPECTATING")
        case .replay: return L("リプレイ", "REPLAY")
        case .paused: return L("一時停止中", "PAUSED")
        }
    }

    static func subtitle(isSpectating: Bool, isReplay: Bool) -> String {
        if isReplay { return L("試合の流れを見返す", "Review how the match unfolded") }
        if isSpectating { return L("戦場全体の動きを見る", "Watch the whole battlefield") }
        return L("戦況を確認して、次の行動へ", "Read the field. Plan your next move.")
    }

    /// 自分 / 注目の凡例。
    static func focusLegend(isSpectating: Bool, hasOwner: Bool) -> String {
        if !isSpectating { return L("自分 / 追従対象", "You / camera focus") }
        return hasOwner ? L("記録した本人 / 追従中", "Recorder / camera focus") : L("追従中のヒーロー", "Followed hero")
    }

    /// 「最後に見えた位置」の凡例を出すか（霧のある視点だけ。観戦の全体視界には無い）。
    static func showsLastSeen(viewerTeam: Team?) -> Bool { viewerTeam != nil }
}

/// 戦闘を止めずに戦場を確認。タッチ中のカメラ操作は小さい地図と同じ座標投影を使う。
/// 観戦者は下部ドックを 1 段にしてマップの下に残す（マップを開いたまま一時停止・速度・シークできる）。
struct HUDTacticalMap: View {
    let model: HUDModel
    let layout: HUDLayout
    @AccessibilityFocusState private var closeFocused: Bool

    var body: some View {
        let spectator = model.isSpectating ? HUDSpectatorLayout(base: layout, seekable: model.controller.isSeekable) : nil
        let mapSize = spectator?.tacticalMapSize ?? layout.tacticalMapSize
        let center = spectator?.tacticalMapCenter
            ?? CGPoint(x: (layout.leadingEdge + layout.trailingEdge) / 2, y: (layout.topEdge + layout.bottomEdge) / 2)
        ZStack {
            Color.black.opacity(0.62)
                .contentShape(Rectangle())
                .onTapGesture { model.setTacticalMap(open: false) }
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(HUDStyle.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("戦場マップ", "BATTLE MAP"))
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                        Text(HUDTacticalMapText.subtitle(isSpectating: model.isSpectating, isReplay: model.controller.isReplay))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(HUDStyle.mutedText)
                    }
                    Spacer(minLength: 8)
                    HUDRoundButton(symbol: "xmark", label: L("マップを閉じる", "Close map"),
                                   identifier: "hud_tactical_close") {
                        model.setTacticalMap(open: false)
                    }
                    .accessibilityFocused($closeFocused)
                }
                HStack(alignment: .top, spacing: 16) {
                    HUDMinimapView(model: model, size: mapSize, isExpanded: true)
                    legend
                        .frame(width: layout.tacticalLegendWidth, height: mapSize, alignment: .topLeading)
                }
            }
            .padding(12)
            .foregroundStyle(.white)
            .hudGlass(cornerRadius: 20, tint: HUDStyle.accent.opacity(0.6))
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("hud_tactical_panel")
            .onAppear { closeFocused = true }
            .accessibilityAction(.escape) { model.setTacticalMap(open: false) }
            .position(center)
        }
        .frame(width: layout.width, height: layout.height)
        .onDisappear { model.minimapReleased() }
    }

    private var legend: some View {
        let c = model.controller
        let status = HUDTacticalMapText.status(isSpectating: model.isSpectating, isReplay: c.isReplay,
                                               isLiveWatcher: model.isSpectating && c.isOnline, paused: model.spectatorPaused)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                Text(HUDStyle.clock(Double(model.top.seconds)))
                    .monospacedDigit()
                Spacer()
                Text(HUDTacticalMapText.label(status))
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(statusColor(status))
                    .accessibilityIdentifier("hud_tactical_status")
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            Divider().overlay(HUDStyle.rim)
            legendRow("location.north.circle",
                      HUDTacticalMapText.focusLegend(isSpectating: model.isSpectating, hasOwner: c.ownerHeroID != nil), .white)
            legendRow("circle.fill", L("ブルーチーム", "Blue team"), Theme.teamColor(.blue, colorblind: model.settings.colorblindMode))
            legendRow("diamond.fill", L("レッドチーム", "Red team"), Theme.teamColor(.red, colorblind: model.settings.colorblindMode))
            legendRow("diamond.fill", L("中立モンスター", "Neutral monsters"), Theme.gold)
            if HUDTacticalMapText.showsLastSeen(viewerTeam: c.viewerTeam) {
                legendRow("circle.dashed", L("最後に見えた位置", "Last seen position"), HUDStyle.mutedText)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Label(L("ドラッグで周囲を見る", "Drag to look around"), systemImage: "hand.draw")
                    .font(.system(size: 11, weight: .bold))
                Text(model.isSpectating
                     ? L("離すと、その場所にカメラを固定します。", "Release to keep the camera there.")
                     : L("指を離すと自分の視点に戻ります。", "Release to return to your hero."))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HUDStyle.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusColor(_ s: HUDTacticalMapText.Status) -> Color {
        switch s {
        case .live, .spectating: return HUDStyle.hp
        case .liveWatch: return Theme.danger
        case .replay: return Theme.gold
        case .paused: return HUDStyle.mutedText
        }
    }

    private func legendRow(_ symbol: String, _ title: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
