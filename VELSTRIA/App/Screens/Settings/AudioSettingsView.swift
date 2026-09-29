import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI063 サウンド設定（音量・触覚・字幕）。

struct AudioSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScreenScaffold(title: L("サウンド", "Audio"), showsCurrencies: false) {
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 14) {
                    SettingsSection(title: L("音量", "Volume"), symbol: "speaker.wave.2.fill") {
                        SettingsSliderRow(title: L("BGM", "Music"), symbol: "music.note",
                                          value: settingsBinding(app, \.bgmVolume), range: 0...1, step: 0.05,
                                          format: SettingsText.percent, identifier: "audio_bgm") { preview() }
                        SettingsDivider()
                        SettingsSliderRow(title: L("効果音", "Sound Effects"), symbol: "speaker.wave.3.fill",
                                          value: settingsBinding(app, \.sfxVolume), range: 0...1, step: 0.05,
                                          format: SettingsText.percent, identifier: "audio_sfx") { preview() }
                        SettingsDivider()
                        SettingsSliderRow(title: L("ボイス", "Voice"), symbol: "waveform",
                                          value: settingsBinding(app, \.voiceVolume), range: 0...1, step: 0.05,
                                          format: SettingsText.percent, identifier: "audio_voice") { preview() }
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 10) {
                        SettingsSection(title: L("その他", "Other"), symbol: "slider.horizontal.3") {
                            SettingsToggleRow(title: L("触覚フィードバック", "Haptics"),
                                              detail: L("タップや撃破時に端末を振動させます。", "Vibrates on taps, kills and other events."),
                                              symbol: "iphone.radiowaves.left.and.right",
                                              isOn: Binding(get: { app.profile.settings.hapticsEnabled },
                                                            set: { on in
                                                                app.profile.settings.hapticsEnabled = on
                                                                if on { app.haptics.impact(.medium) }
                                                            }),
                                              identifier: "audio_haptics")
                            SettingsDivider()
                            SettingsToggleRow(title: L("字幕", "Subtitles"),
                                              detail: L("ボイスやアナウンスを字幕で表示します。", "Shows captions for voice lines and announcements."),
                                              symbol: "captions.bubble.fill", isOn: settingsBinding(app, \.subtitlesEnabled),
                                              identifier: "audio_subtitles")
                        }
                        Text(L("消音モードでは効果音が鳴らない場合があります。スライダーを離すと試聴音が鳴ります。",
                               "Sound effects may be silent in silent mode. Release a slider to hear a preview."))
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
        }
    }

    private func preview() {
        app.audio.play(.uiTap)
    }
}
