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

/// 戦闘を止めずに戦場を確認。タッチ中のカメラ操作は小さい地図と同じ座標投影を使う。
struct HUDTacticalMap: View {
    let model: HUDModel
    let layout: HUDLayout
    @AccessibilityFocusState private var closeFocused: Bool

    var body: some View {
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
                        Text(L("戦況を確認して、次の行動へ", "Read the field. Plan your next move."))
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
                    HUDMinimapView(model: model, size: layout.tacticalMapSize, isExpanded: true)
                    legend
                        .frame(width: layout.tacticalLegendWidth, height: layout.tacticalMapSize, alignment: .topLeading)
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
            .position(x: (layout.leadingEdge + layout.trailingEdge) / 2,
                      y: (layout.topEdge + layout.bottomEdge) / 2)
        }
        .frame(width: layout.width, height: layout.height)
        .onDisappear { model.minimapReleased() }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                Text(HUDStyle.clock(Double(model.top.seconds)))
                    .monospacedDigit()
                Spacer()
                Text(L("進行中", "LIVE"))
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(HUDStyle.hp)
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            Divider().overlay(HUDStyle.rim)
            legendRow("location.north.circle", L("自分 / 追従対象", "You / camera focus"), .white)
            legendRow("circle.fill", L("ブルーチーム", "Blue team"), Theme.teamColor(.blue, colorblind: model.settings.colorblindMode))
            legendRow("diamond.fill", L("レッドチーム", "Red team"), Theme.teamColor(.red, colorblind: model.settings.colorblindMode))
            legendRow("diamond.fill", L("中立モンスター", "Neutral monsters"), Theme.gold)
            legendRow("circle.dashed", L("最後に見えた位置", "Last seen position"), HUDStyle.mutedText)
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
