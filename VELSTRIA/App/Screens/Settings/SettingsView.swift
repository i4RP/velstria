import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI060 設定ハブ。

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmReset = false

    var body: some View {
        let s = app.profile.settings
        ScreenScaffold(title: L("設定", "Settings"), showsCurrencies: false) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        tile(L("操作", "Controls"), "\(SettingsText.joystick(s.joystickMode)) · \(SettingsText.castMode(s.skillCastMode))",
                             "gamecontroller.fill", id: "settings_controls", route: .controlSettings)
                        tile(L("グラフィック", "Graphics"), "\(SettingsText.quality(s.graphicsQuality)) · \(SettingsText.frameRate(s.frameRate))",
                             "sparkles.tv.fill", id: "settings_graphics", route: .graphicsSettings)
                        tile(L("サウンド", "Audio"), L("BGM \(SettingsText.percent(s.bgmVolume)) · 効果音 \(SettingsText.percent(s.sfxVolume))",
                                                   "Music \(SettingsText.percent(s.bgmVolume)) · SFX \(SettingsText.percent(s.sfxVolume))"),
                             "speaker.wave.2.fill", id: "settings_audio", route: .audioSettings)
                        tile(L("言語", "Language"), SettingsText.language(s.language),
                             "globe", id: "settings_language", route: .languageSettings)
                        tile(L("通知", "Notifications"), SettingsText.onOff(s.notificationsEnabled),
                             "bell.badge.fill", id: "settings_notifications", route: .notificationSettings)
                        tile(L("プライバシー", "Privacy"), L("データは端末内のみに保存", "Data stays on this device"),
                             "hand.raised.fill", id: "settings_privacy", route: .privacySettings)
                        tile(L("データ引き継ぎ", "Data Transfer"), L("バックアップと復元", "Backup & restore"),
                             "arrow.triangle.2.circlepath", id: "settings_account_link", route: .accountLink)
                        tile(L("サポート", "Support"), L("FAQ・お問い合わせ", "FAQ & contact"),
                             "questionmark.circle.fill", tint: Theme.gold, id: "settings_support", route: .support)
                        tile(L("クレジット", "Credits"), L("制作チーム", "The team"),
                             "star.fill", tint: Theme.gold, id: "settings_credits", route: .credits)
                    }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .alert(L("設定を初期値に戻しますか？", "Reset settings to default?"), isPresented: $confirmReset) {
            Button(L("初期値に戻す", "Reset"), role: .destructive) { reset() }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("操作・グラフィック・サウンドの設定が初期値に戻ります。言語と通知の設定はそのままです。",
                   "Controls, graphics and audio settings return to defaults. Language and notification settings are kept."))
        }
    }

    private func tile(_ title: String, _ summary: String, _ symbol: String, tint: Color = Theme.cyan,
                      id: String, route: Route) -> some View {
        SettingsHubTile(title: title, summary: summary, symbol: symbol, tint: tint, identifier: id) {
            app.audio.play(.uiTap)
            app.router.push(route)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VELSIA \(AppVersionInfo.display)")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textSecondary)
                Text(L("設定は自動で保存されます", "Settings are saved automatically"))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                confirmReset = true
            } label: {
                Label(L("初期値に戻す", "Reset to Default"), systemImage: "arrow.counterclockwise")
                    .lineLimit(1)
            }
            .buttonStyle(LiveOpsTallButtonStyle(base: SecondaryButtonStyle()))
            .accessibilityIdentifier("settings_reset")
        }
        .padding(.top, 4)
    }

    private func reset() {
        app.profile.settings = SettingsDefaults.reset(app.profile.settings)
        app.audio.play(.uiConfirm)
        app.showToast(L("設定を初期値に戻しました", "Settings reset to default"))
    }
}
