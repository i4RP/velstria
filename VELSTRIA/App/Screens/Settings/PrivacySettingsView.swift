import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI066 プライバシー（保存データの説明・ポリシー・全データ削除）。

struct PrivacySettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    /// 1 段目の確認（画面内）を表示中か。
    @State private var armed = false
    /// 2 段目の最終確認（アラート）。
    @State private var finalConfirm = false

    private static let deletePanelID = "privacy_delete_panel"

    var body: some View {
        ScreenScaffold(title: L("プライバシー", "Privacy"), showsCurrencies: false) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 10) {
                            storedPanel
                            notCollectedPanel
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 10) {
                            policyPanel
                            deletePanel
                                .id(Self.deletePanelID)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                }
                .onChange(of: armed) { _, isArmed in
                    // 確認欄が画面外に出ないよう、開いたら削除欄の下端まで送る
                    guard isArmed else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(Self.deletePanelID, anchor: .bottom) }
                }
            }
        }
        .alert(L("最終確認", "Final Confirmation"), isPresented: $finalConfirm) {
            Button(L("完全に削除する", "Delete Everything"), role: .destructive) { deleteAll() }
            Button(L("キャンセル", "Cancel"), role: .cancel) { armed = false }
        } message: {
            Text(L("この操作は取り消せません。本当にすべてのデータを削除しますか？", "This cannot be undone. Delete all data?"))
        }
    }

    private var storedPanel: some View {
        SettingsSection(title: L("この端末に保存されるデータ", "Data Stored on This Device"), symbol: "internaldrive.fill") {
            item("person.crop.circle.fill", L("プロフィール", "Profile"),
                 L("プレイヤー名・アカウントレベル・所持ヒーロー / コスメ・通貨", "Player name, account level, owned heroes / cosmetics, currencies"))
            item("list.bullet.rectangle.fill", L("戦績とリプレイ", "Match history & replays"),
                 L("最新 50 件の戦績と最新 \(ReplayLibrary.maxStored) 件のリプレイ", "Latest 50 matches and latest \(ReplayLibrary.maxStored) replays"))
            item("slider.horizontal.3", L("設定", "Settings"), L("操作・グラフィック・サウンド・言語など", "Controls, graphics, audio, language and more"))
            item("creditcard.fill", L("購入記録", "Purchase records"),
                 L("二重付与を防ぐための取引 ID・日時・付与数（支払い情報は保存しません）",
                   "Transaction IDs, dates and amounts granted to prevent double grants (no payment details)"))
        }
    }

    private var notCollectedPanel: some View {
        SettingsSection(title: L("送信・収集しないもの", "What We Don't Collect"), symbol: "hand.raised.fill") {
            item("location.slash.fill", L("トラッキングなし", "No tracking"),
                 L("他社のアプリやウェブサイトをまたいだ追跡は行いません。", "We never track you across other companies' apps or websites."))
            item("chart.bar.xaxis", L("分析データの送信なし", "No analytics sent"),
                 L("プレイ内容や端末情報を外部へ送信しません。", "Gameplay and device data are never sent anywhere."))
            item("wifi.slash", L("オフラインで完結", "Fully offline"),
                 L("アカウント登録やサーバー通信なしで遊べます。課金は Apple が処理します。",
                   "No sign-up or server connection. Purchases are processed by Apple."))
        }
    }

    private func item(_ symbol: String, _ title: String, _ detail: String) -> some View {
        SettingsRowLabel(title: title, detail: detail, symbol: symbol)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .accessibilityElement(children: .combine)
    }

    private var policyPanel: some View {
        SettingsSection(title: L("ポリシー", "Policies"), symbol: "doc.text.fill") {
            SettingsLinkRow(title: L("プライバシーポリシー", "Privacy Policy"), symbol: "lock.shield.fill", external: true,
                            identifier: "privacy_policy") {
                openURL(FeatureFlags.privacyPolicyURL)
            }
            SettingsDivider()
            SettingsLinkRow(title: L("利用規約", "Terms of Service"), symbol: "doc.plaintext.fill", external: true,
                            identifier: "privacy_terms") {
                openURL(FeatureFlags.termsURL)
            }
        }
    }

    private var deletePanel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label(L("全データを削除", "Delete All Data"), systemImage: "trash.fill")
                    .font(Theme.heading(15))
                    .foregroundStyle(Theme.danger)
                Text(L("プロフィール・所持品・通貨・戦績・リプレイ・設定をこの端末から完全に削除し、初回起動の状態に戻します。",
                       "Permanently removes your profile, items, currencies, match history, replays and settings from this device and returns to first launch."))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if app.profile.paidGem > 0 {
                    Label(L("購入した有償ジェム \(app.profile.paidGem.formatted()) 個も失われ、復元できません。",
                            "Your \(app.profile.paidGem.formatted()) purchased gems will also be lost and cannot be restored."),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if armed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("本当に削除しますか？ 削除したデータは元に戻せません。バックアップが必要な場合は先に「データ引き継ぎ」から書き出してください。",
                               "Are you sure? Deleted data cannot be recovered. Export a backup from Data Transfer first if needed."))
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button {
                                armed = false
                            } label: {
                                Text(L("やめる", "Cancel")).lineLimit(1)
                            }
                            .buttonStyle(LiveOpsTallButtonStyle(base: SecondaryButtonStyle()))
                            .accessibilityIdentifier("privacy_delete_cancel")
                            Button {
                                app.haptics.warning()
                                finalConfirm = true
                            } label: {
                                Text(L("削除に進む", "Continue")).lineLimit(1)
                            }
                            .buttonStyle(LiveOpsTallButtonStyle(base: PrimaryButtonStyle(color: Theme.danger)))
                            .accessibilityIdentifier("privacy_delete_continue")
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.danger.opacity(0.12)))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Button {
                        app.audio.play(.uiTap)
                        withAnimation(.easeOut(duration: 0.2)) { armed = true }
                    } label: {
                        Label(L("全データを削除", "Delete All Data"), systemImage: "trash")
                            .foregroundStyle(Theme.danger)
                            .lineLimit(1)
                    }
                    .buttonStyle(LiveOpsTallButtonStyle(base: SecondaryButtonStyle()))
                    .accessibilityIdentifier("privacy_delete_all")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.danger.opacity(0.4), lineWidth: 1))
    }

    private func deleteAll() {
        DailyReminder.cancel()
        app.persistence.deleteAll()
        app.profile = Profile()
        app.router.popToRoot()
        app.showToast(L("すべてのデータを削除しました", "All data deleted"))
    }
}
