import SwiftUI
import VelstriaCore

// 担当: battle-hud。上部: 中央にチームキル数と試合時間、右に自分の K/D/A・CS とスコアボード（UI029）/ポーズ（UI030）ボタン。

struct HUDScoreCapsule: View {
    let top: HUDTopSnapshot
    let colorblind: Bool
    let scale: CGFloat

    var body: some View {
        let blue = Theme.teamColor(.blue, colorblind: colorblind)
        let red = Theme.teamColor(.red, colorblind: colorblind)
        HStack(spacing: 9 * scale) {
            teamSide(top.blueKills, towers: top.blueTowers, color: blue, symbol: "circle.fill")
            VStack(spacing: 1) {
                Text(HUDStyle.clock(Double(top.seconds)))
                    .font(.system(size: 20 * scale, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(L("経過時間", "ELAPSED"))
                    .font(.system(size: 7 * scale, weight: .heavy, design: .rounded))
                    .tracking(1.2 * scale)
                    .foregroundStyle(HUDStyle.mutedText)
            }
            .frame(minWidth: 70 * scale)
            .padding(.horizontal, 3 * scale)
            .overlay(alignment: .leading) { Rectangle().fill(blue.opacity(0.4)).frame(width: 1, height: 22 * scale) }
            .overlay(alignment: .trailing) { Rectangle().fill(red.opacity(0.4)).frame(width: 1, height: 22 * scale) }
            teamSide(top.redKills, towers: top.redTowers, color: red, symbol: "diamond.fill")
        }
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 5 * scale)
        .background(
            RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                .fill(LinearGradient(colors: [HUDStyle.glassTop, HUDStyle.glassBottom], startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18 * scale, style: .continuous)
                .strokeBorder(LinearGradient(colors: [blue.opacity(0.85), HUDStyle.rim, red.opacity(0.85)],
                                             startPoint: .leading, endPoint: .trailing), lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(0.28), radius: 5, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("キル数 ブルー \(top.blueKills) 対 レッド \(top.redKills)、破壊タワー ブルー \(top.blueTowers) 対 レッド \(top.redTowers)、経過 \(HUDStyle.clock(Double(top.seconds)))",
                              "Kills Blue \(top.blueKills) to Red \(top.redKills), towers destroyed Blue \(top.blueTowers) to Red \(top.redTowers), time \(HUDStyle.clock(Double(top.seconds)))"))
        .accessibilityIdentifier("hud_score")
    }

    /// チームのキル数（色に加えて形でも区別する: ブルー = 丸、レッド = ひし形）。
    private func teamSide(_ kills: Int, towers: Int, color: Color, symbol: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4 * scale) {
                Image(systemName: symbol)
                    .font(.system(size: 6 * scale, weight: .black))
                    .foregroundStyle(color)
                Text("\(kills)")
                    .font(.system(size: 21 * scale, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            HStack(spacing: 3 * scale) {
                Image(systemName: "building.2.fill")
                Text("\(towers)")
                    .monospacedDigit()
            }
            .font(.system(size: 8 * scale, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
        }
        .frame(minWidth: 44 * scale)
    }
}

struct HUDTopRight: View {
    let model: HUDModel
    let scale: CGFloat

    var body: some View {
        let top = model.top
        HStack(spacing: 6) {
            if !model.isSpectating {
                HStack(spacing: 9 * scale) {
                    VStack(spacing: 1) {
                        Text("K / D / A")
                            .font(.system(size: 7 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(HUDStyle.mutedText)
                        HStack(spacing: 3 * scale) {
                            Text("\(top.kills)").foregroundStyle(.white)
                            Text("/").foregroundStyle(HUDStyle.mutedText.opacity(0.6))
                            Text("\(top.deaths)").foregroundStyle(.white)
                            Text("/").foregroundStyle(HUDStyle.mutedText.opacity(0.6))
                            Text("\(top.assists)").foregroundStyle(.white)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("K/D/A \(top.kills) / \(top.deaths) / \(top.assists)")
                    Rectangle().fill(HUDStyle.rim).frame(width: 1, height: 19 * scale)
                    VStack(spacing: 1) {
                        Text("CS")
                            .font(.system(size: 7 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(HUDStyle.mutedText)
                        Text("\(top.creepScore)").foregroundStyle(.white)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("CS \(top.creepScore)")
                }
                .font(.system(size: 12 * scale, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .frame(height: 36 * scale)
                .hudGlass(cornerRadius: 12)
            }
            HUDRoundButton(symbol: "list.bullet.rectangle.fill", label: L("スコアボード", "Scoreboard"),
                           identifier: "hud_scoreboard") {
                if model.panel == .scoreboard { model.closePanel() } else { model.openPanel(.scoreboard) }
            }
            HUDRoundButton(symbol: "pause.fill", label: L("ポーズ・設定", "Pause & Settings"), identifier: "hud_pause") {
                model.openPanel(.pause)
            }
            if model.isSpectating {
                HUDRoundButton(symbol: "rectangle.portrait.and.arrow.right", label: L("観戦をやめる", "Leave"),
                               identifier: "spectate_leave", tint: Theme.danger) {
                    model.requestLeave()
                }
            }
        }
    }
}
