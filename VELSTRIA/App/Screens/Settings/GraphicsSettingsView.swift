import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI062 グラフィック設定（色覚サポートのチーム色プレビュー付き）。

struct GraphicsSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let s = app.profile.settings
        ScreenScaffold(title: L("グラフィック", "Graphics"), showsCurrencies: false) {
            HStack(alignment: .top, spacing: 14) {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 10) {
                        SettingsSection(title: L("描画", "Rendering"), symbol: "sparkles.tv.fill") {
                            SettingsChoiceRow(title: L("画質", "Quality"), detail: SettingsText.qualityDetail(s.graphicsQuality),
                                              symbol: "sparkles",
                                              options: GraphicsQuality.allCases.map { ($0, SettingsText.quality($0)) },
                                              selection: settingsBinding(app, \.graphicsQuality), identifier: "graphics_quality")
                            SettingsDivider()
                            SettingsChoiceRow(title: L("フレームレート", "Frame Rate"), detail: SettingsText.frameRateDetail(s.frameRate),
                                              symbol: "speedometer",
                                              options: FrameRateOption.allCases.map { ($0, SettingsText.frameRate($0)) },
                                              selection: settingsBinding(app, \.frameRate), identifier: "graphics_fps")
                        }
                        SettingsSection(title: L("表示", "Display"), symbol: "eye.fill") {
                            SettingsToggleRow(title: L("ダメージ数値", "Damage Numbers"),
                                              detail: L("与えたダメージ・回復量を数値で表示します。", "Shows damage and healing as floating numbers."),
                                              symbol: "textformat.123", isOn: settingsBinding(app, \.showDamageNumbers),
                                              identifier: "graphics_damage_numbers")
                            SettingsDivider()
                            SettingsToggleRow(title: L("色覚サポート", "Colorblind Mode"),
                                              detail: L("チーム色を青 / 橙にし、形状マーカーを強調します。", "Uses blue / orange team colors and emphasises shape markers."),
                                              symbol: "eyedropper.halffull", isOn: settingsBinding(app, \.colorblindMode),
                                              identifier: "graphics_colorblind")
                        }
                    }
                    .padding(.bottom, 10)
                }
                TeamColorPreview(settings: s)
                    .frame(width: 250)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }
}

/// チーム色・ダメージ表示のプレビュー。
struct TeamColorPreview: View {
    let settings: GameSettings

    var body: some View {
        Panel(padding: 12) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    LiveOpsSectionHeader(title: L("チームカラー", "Team Colors"), symbol: "paintpalette.fill")
                    teamRow(.blue, label: L("味方", "Ally"), hp: 0.72)
                    teamRow(.red, label: L("敵", "Enemy"), hp: 0.41)
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(red: 0.08, green: 0.14, blue: 0.16))
                        HStack(spacing: 26) {
                            unitMarker(.blue)
                            unitMarker(.red)
                        }
                        if settings.showDamageNumbers {
                            Text("-128")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(Theme.gold)
                                .shadow(color: .black, radius: 2)
                                .offset(x: 30, y: -34)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .frame(height: 84)
                    .animation(.easeInOut(duration: 0.25), value: settings)
                    Text(settings.colorblindMode ? L("色覚サポート: オン（青 / 橙）", "Colorblind mode: On (blue / orange)")
                                                 : L("色覚サポート: オフ（青 / 赤）", "Colorblind mode: Off (blue / red)"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settings.colorblindMode ? L("チームカラーのプレビュー。味方は青、敵は橙", "Team color preview. Allies blue, enemies orange")
                                                    : L("チームカラーのプレビュー。味方は青、敵は赤", "Team color preview. Allies blue, enemies red"))
    }

    private func teamRow(_ team: Team, label: String, hp: Double) -> some View {
        let color = Theme.teamColor(team, colorblind: settings.colorblindMode)
        return HStack(spacing: 8) {
            Image(systemName: LiveOpsFormat.teamSymbol(team))
                .font(.system(size: settings.colorblindMode ? 14 : 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 18)
            Text(label)
                .font(Theme.heading(13))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, alignment: .leading)
            LiveOpsProgressBar(fraction: hp, tint: color, height: 10)
        }
    }

    private func unitMarker(_ team: Team) -> some View {
        let color = Theme.teamColor(team, colorblind: settings.colorblindMode)
        return VStack(spacing: 4) {
            Capsule().fill(Color.black.opacity(0.6)).frame(width: 40, height: 6)
                .overlay(alignment: .leading) { Capsule().fill(color).frame(width: team == .blue ? 30 : 16, height: 6) }
            ZStack {
                Circle().fill(color.opacity(0.9)).frame(width: 26, height: 26)
                if settings.colorblindMode {
                    Image(systemName: LiveOpsFormat.teamSymbol(team))
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                }
            }
            .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
        }
    }
}
