import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI064 言語設定（選択すると即時に全画面へ反映）。

struct LanguageSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let current = app.profile.settings.language
        ScreenScaffold(title: L("言語", "Language"), showsCurrencies: false) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        ForEach(AppLanguage.allCases) { lang in
                            option(lang, selected: lang == current)
                        }
                    }
                    Panel(padding: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(L("表示言語はすぐに切り替わります。", "The display language changes immediately."), systemImage: "bolt.fill")
                            Label(L("「システム設定」は端末の言語設定に合わせて日本語 / English を選びます。",
                                    "\"System\" follows your device language (Japanese or English)."), systemImage: "iphone")
                            Label(L("通知のリマインダー文も選んだ言語で届きます。", "Reminder notifications use the selected language too."),
                                  systemImage: "bell.fill")
                        }
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
        }
    }

    private func option(_ lang: AppLanguage, selected: Bool) -> some View {
        Button {
            select(lang)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol(lang))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(selected ? Theme.gold : Theme.cyan)
                Text(SettingsText.language(lang))
                    .font(Theme.heading(17))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle(lang))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(selected ? Theme.gold : Theme.textSecondary.opacity(0.6))
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(selected ? Theme.gold.opacity(0.12) : Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? Theme.gold : Theme.panelStroke, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SettingsText.language(lang))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("language_\(lang.rawValue)")
    }

    private func symbol(_ lang: AppLanguage) -> String {
        switch lang {
        case .system: return "iphone.gen3"
        case .ja: return "character.ja"
        case .en: return "textformat.abc"
        }
    }

    private func subtitle(_ lang: AppLanguage) -> String {
        switch lang {
        case .system:
            let resolved = Loc.resolve(.system)
            return L("端末に合わせる（現在: \(SettingsText.language(resolved))）", "Match device (now: \(SettingsText.language(resolved)))")
        case .ja: return "Japanese"
        case .en: return "英語"
        }
    }

    private func select(_ lang: AppLanguage) {
        guard app.profile.settings.language != lang else { return }
        app.audio.play(.uiConfirm)
        app.haptics.tap()
        // RootView は言語で id が変わり全画面が再構築されるため、即時に反映される
        app.profile.settings.language = lang
        if app.profile.settings.notificationsEnabled {
            let resolved = Loc.resolve(lang)
            Task { await DailyReminder.reschedule(language: resolved) }
        }
    }
}
