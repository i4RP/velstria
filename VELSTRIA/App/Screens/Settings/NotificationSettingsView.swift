import SwiftUI
import UIKit
import UserNotifications
import VelstriaCore

// 担当: ui-liveops。UI065 通知設定と、毎日 19:00 のローカルリマインダー（識別子 velstria.daily）。

enum DailyReminder {
    static let identifier = "velstria.daily"
    static let hour = 19
    static let minute = 0

    /// 通知文（言語は解決済みの ja / en。system は端末言語で解決する）。
    static func content(language: AppLanguage) -> (title: String, body: String) {
        switch Loc.resolve(language) {
        case .en: return ("VELSIA", "Daily missions have been refreshed")
        default: return ("VELSIA", "デイリーミッションが更新されました")
        }
    }

    static func trigger() -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
    }

    static func makeRequest(language: AppLanguage) -> UNNotificationRequest {
        let text = content(language: language)
        let c = UNMutableNotificationContent()
        c.title = text.title
        c.body = text.body
        c.sound = .default
        return UNNotificationRequest(identifier: identifier, content: c, trigger: trigger())
    }

    static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 許可を求める（拒否済みの場合はダイアログを出さず false）。
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// 既存の予約を置き換えて登録する。
    static func schedule(language: AppLanguage) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try await center.add(makeRequest(language: language))
    }

    /// 許可済みの場合のみ登録し直す（言語変更・設定アプリからの復帰時）。
    static func reschedule(language: AppLanguage) async {
        guard isAllowed(await authorizationStatus()) else { return }
        try? await schedule(language: language)
    }

    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    static func timeText() -> String { String(format: "%d:%02d", hour, minute) }
}

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var status: UNAuthorizationStatus?
    @State private var working = false
    /// 許可確認中に表示するスイッチの状態（確定するまでの見かけ上の値）。
    @State private var pendingOn: Bool?

    var body: some View {
        let enabled = app.profile.settings.notificationsEnabled
        let denied = status == .denied
        ScreenScaffold(title: L("通知", "Notifications"), showsCurrencies: false) {
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 10) {
                        SettingsSection(title: L("リマインダー", "Reminders"), symbol: "bell.badge.fill") {
                            SettingsToggleRow(title: L("デイリーリマインダー", "Daily Reminder"),
                                              detail: L("毎日 \(DailyReminder.timeText()) にデイリーミッションの更新をお知らせします。",
                                                        "Reminds you of refreshed daily missions every day at \(DailyReminder.timeText())."),
                                              symbol: "alarm.fill",
                                              isOn: Binding(get: { pendingOn ?? (enabled && !denied) },
                                                            set: { on in
                                                                pendingOn = on
                                                                Task { await setEnabled(on) }
                                                            }),
                                              identifier: "notifications_daily")
                            .disabled(working)
                            SettingsDivider()
                            statusLine
                        }
                        if denied {
                            deniedPanel
                        }
                    }
                    .frame(maxWidth: .infinity)
                    previewPanel
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private var statusLine: some View {
        let text: String
        let color: Color
        switch status {
        case .some(let s) where DailyReminder.isAllowed(s):
            text = L("通知の許可: 許可済み", "Permission: Allowed"); color = Theme.success
        case .some(.denied):
            text = L("通知の許可: 端末の設定でオフ", "Permission: Off in iOS Settings"); color = Theme.danger
        case .some(.notDetermined):
            text = L("通知の許可: 未設定（オンにすると確認が表示されます）", "Permission: Not set (you'll be asked when turning on)"); color = Theme.textSecondary
        default:
            text = L("通知の許可を確認しています…", "Checking permission…"); color = Theme.textSecondary
        }
        return Label(text, systemImage: "info.circle")
            .font(Theme.body(12))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .accessibilityIdentifier("notifications_status")
    }

    private var deniedPanel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label(L("通知がオフになっています", "Notifications are turned off"), systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.heading(14))
                    .foregroundStyle(Theme.gold)
                Text(L("VELSIA の通知は iOS の「設定」でオフになっています。リマインダーを受け取るには、設定アプリで通知を許可してください。",
                       "Notifications for VELSIA are disabled in iOS Settings. Allow notifications there to receive reminders."))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    Label(L("設定を開く", "Open Settings"), systemImage: "gearshape.fill")
                }
                .buttonStyle(LiveOpsTallButtonStyle(base: PrimaryButtonStyle()))
                .accessibilityIdentifier("notifications_open_settings")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var previewPanel: some View {
        let text = DailyReminder.content(language: Loc.current)
        return Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                LiveOpsSectionHeader(title: L("通知のプレビュー", "Preview"), symbol: "iphone.gen3")
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.cyan, Color(red: 0.35, green: 0.25, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 34)
                        .overlay(Text("V").font(.system(size: 18, weight: .black, design: .serif)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(text.title).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(DailyReminder.timeText()).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        }
                        Text(text.body).font(.system(size: 13))
                    }
                    .foregroundStyle(.white)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.14)))
                .accessibilityElement(children: .combine)
                Text(L("リマインダーは端末内で作成されるローカル通知です。サーバーからの送信や、通知に関するデータの収集は行いません。",
                       "Reminders are local notifications created on this device. Nothing is sent from a server and no notification data is collected."))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func refresh() async {
        let s = await DailyReminder.authorizationStatus()
        status = s
        // 許可済みでオンなら予約を最新の言語で登録し直す（設定アプリで再許可された場合も復旧する）
        if app.profile.settings.notificationsEnabled && DailyReminder.isAllowed(s) {
            try? await DailyReminder.schedule(language: Loc.current)
        }
    }

    private func setEnabled(_ on: Bool) async {
        guard !working else { return }
        working = true
        defer {
            working = false
            pendingOn = nil
        }
        if on {
            var granted = DailyReminder.isAllowed(await DailyReminder.authorizationStatus())
            if !granted { granted = await DailyReminder.requestAuthorization() }
            status = await DailyReminder.authorizationStatus()
            guard granted else {
                app.profile.settings.notificationsEnabled = false
                app.audio.play(.uiError)
                return
            }
            do {
                try await DailyReminder.schedule(language: Loc.current)
                app.profile.settings.notificationsEnabled = true
                app.audio.play(.uiConfirm)
                app.showToast(L("毎日 \(DailyReminder.timeText()) にお知らせします", "You'll be reminded daily at \(DailyReminder.timeText())"))
            } catch {
                app.profile.settings.notificationsEnabled = false
                app.audio.play(.uiError)
                app.showToast(L("通知を登録できませんでした", "Couldn't schedule the reminder"))
            }
        } else {
            DailyReminder.cancel()
            app.profile.settings.notificationsEnabled = false
            app.audio.play(.uiTap)
        }
    }
}
