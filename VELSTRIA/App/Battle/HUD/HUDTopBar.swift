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
        HStack(spacing: 10 * scale) {
            teamSide(top.blueKills, color: blue, symbol: "circle.fill", leading: true)
            VStack(spacing: 0) {
                Text(HUDStyle.clock(Double(top.seconds)))
                    .font(.system(size: 15 * scale, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 8 * scale, weight: .bold))
                    .foregroundStyle(Theme.gold.opacity(0.8))
            }
            .frame(minWidth: 54 * scale)
            teamSide(top.redKills, color: red, symbol: "diamond.fill", leading: false)
        }
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(LinearGradient(colors: [HUDStyle.glassTop, HUDStyle.glassBottom], startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            Capsule().strokeBorder(LinearGradient(colors: [blue.opacity(0.8), Theme.gold.opacity(0.6), red.opacity(0.8)],
                                                  startPoint: .leading, endPoint: .trailing), lineWidth: 1.2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("キル数 ブルー \(top.blueKills) 対 レッド \(top.redKills)、経過 \(HUDStyle.clock(Double(top.seconds)))",
                              "Kills Blue \(top.blueKills) to Red \(top.redKills), time \(HUDStyle.clock(Double(top.seconds)))"))
        .accessibilityIdentifier("hud_score")
    }

    /// チームのキル数（色に加えて形でも区別する: ブルー = 丸、レッド = ひし形）。
    private func teamSide(_ kills: Int, color: Color, symbol: String, leading: Bool) -> some View {
        HStack(spacing: 5 * scale) {
            if leading {
                Image(systemName: symbol).font(.system(size: 9 * scale, weight: .bold)).foregroundStyle(color)
            }
            Text("\(kills)")
                .font(.system(size: 22 * scale, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.6), radius: 4)
                .frame(minWidth: 28 * scale, alignment: leading ? .trailing : .leading)
            if !leading {
                Image(systemName: symbol).font(.system(size: 9 * scale, weight: .bold)).foregroundStyle(color)
            }
        }
    }
}

struct HUDTopRight: View {
    let model: HUDModel
    let scale: CGFloat

    var body: some View {
        let top = model.top
        HStack(spacing: 6) {
            if !model.isSpectating {
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Text("\(top.kills)").foregroundStyle(.white)
                        Text("/").foregroundStyle(.white.opacity(0.45))
                        Text("\(top.deaths)").foregroundStyle(Theme.danger)
                        Text("/").foregroundStyle(.white.opacity(0.45))
                        Text("\(top.assists)").foregroundStyle(.white)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("K/D/A \(top.kills) / \(top.deaths) / \(top.assists)")
                    HStack(spacing: 3) {
                        Image(systemName: "person.3.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.gold)
                        Text("\(top.creepScore)").foregroundStyle(.white)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("CS \(top.creepScore)")
                }
                .font(.system(size: 13 * scale, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .frame(height: 30)
                .hudGlass(cornerRadius: 15)
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
