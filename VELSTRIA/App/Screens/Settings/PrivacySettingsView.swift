import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI066 プライバシー（保存データの説明・ポリシー・全データ削除）。
// オンライン機能（FeatureFlags.lanMatch）: 同意の状態と取り消し、中継サーバーの受信箱とクラウドのランクの削除、ブロックしたプレイヤーの一覧と解除
// （ガイドライン 1.2 / 5.1.1(v)）。全データの削除では、中継サーバーの受信箱とランクも先に消す（通信できなければ、端末だけ消すかを選べる）。

struct PrivacySettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    /// 1 段目の確認（画面内）を表示中か。
    @State private var armed = false
    /// 2 段目の最終確認（アラート）。
    @State private var finalConfirm = false
    /// オンライン機能をやめる確認。
    @State private var confirmsRevoke = false
    /// 中継サーバーの受信箱を消す確認。
    @State private var confirmsErase = false
    /// 中継サーバーの受信箱を消している（通信中）。
    @State private var erasing = false
    /// 全データの削除の途中で、中継サーバーの受信箱を消せなかった。
    @State private var deleteEraseFailed = false

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
                            if FeatureFlags.lanMatch { onlinePanel }
                            deletePanel
                                .id(Self.deletePanelID)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 10)
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
        .alert(L("フレンドサーバーのデータを削除できませんでした", "Couldn't Delete Friend Server Data"), isPresented: $deleteEraseFailed) {
            Button(L("もう一度試す", "Try Again")) { deleteAll() }
            Button(L("端末のデータだけ削除", "Delete Device Data Only"), role: .destructive) { finishDeleteAll() }
            Button(L("キャンセル", "Cancel"), role: .cancel) { armed = false }
        } message: {
            Text(L("通信できる場所で、もう一度お試しください。端末のデータだけを削除した場合、フレンドサーバーの受信箱は最後の接続から 1 年で自動的に削除されます。預けたランクは残ることがあります。",
                   "Please try again with a connection. If you delete only device data, your inbox on the friend server is deleted automatically one year after your last connection. Your rank stored there may remain."))
        }
        .confirmationDialog(L("フレンドサーバーのデータを削除しますか？", "Delete your data on the friend server?"), isPresented: $confirmsErase,
                            titleVisibility: .visible) {
            Button(L("削除する", "Delete"), role: .destructive) { eraseServerData() }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("フレンドサーバーからあなたの受信箱（鍵のハッシュ・最後に接続した日時・預かり中のフレンド申請）と預けたランクを削除し、オンライン機能をやめます。フレンドの一覧と送った申請も消え、次にオンラインを使うときは新しいフレンドコードになります。",
                   "This deletes your inbox on the friend server (hashed key, last connection time and held friend requests) and the rank stored there, and turns off online features. Your friends list and sent requests are also cleared, and you get a new friend code next time you go online."))
        }
        .confirmationDialog(L("オンライン機能をやめますか？", "Stop using online features?"), isPresented: $confirmsRevoke,
                            titleVisibility: .visible) {
            Button(L("やめる", "Stop"), role: .destructive) {
                app.revokeOnlineRules()
                app.showToast(L("オンライン機能をやめました", "Online features turned off"))
            }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("部屋を出て、フレンドサーバーへの接続を止めます。フレンドの一覧はこの端末に残り、次にオンラインを開くとルールへの同意から再開できます。フレンドサーバーのデータも消すには「フレンドサーバーのデータを削除」を使ってください。",
                   "You leave any room and stop connecting to the friend server. Your friends list stays on this device; open Online again to re-accept the rules. To also delete your data on the friend server, use \"Delete Friend Server Data\"."))
        }
    }

    private var storedPanel: some View {
        SettingsSection(title: L("この端末に保存されるデータ", "Data Stored on This Device"), symbol: "internaldrive.fill") {
            item("person.crop.circle.fill", L("プロフィール", "Profile"),
                 L("プレイヤー名・アカウントレベル・所持ヒーロー / コスメ・通貨", "Player name, account level, owned heroes / cosmetics, currencies"))
            item("list.bullet.rectangle.fill", L("戦績とリプレイ", "Match history & replays"),
                 L("最新 50 件の戦績と最新 \(PersistenceService.maxReplays) 件のリプレイ（観戦の記録を含む。お気に入りは別に最大 \(PersistenceService.maxFavoriteReplays) 件）。リプレイの共有は、あなたが共有シートで送った時だけ行われます",
                   "Latest 50 matches and latest \(PersistenceService.maxReplays) replays (including spectated matches; up to \(PersistenceService.maxFavoriteReplays) more favorites). Replays leave the device only when you share them"))
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
                 L("プレイ内容や端末情報を、分析・広告のために外部へ送信しません", "Gameplay and device data are never sent anywhere for analytics or ads")
                    + (FeatureFlags.lanMatch ? L("（オンライン機能で相手やフレンドへ届くデータは下記）。", " (data that online features send to other players is described below).")
                                             : L("。", ".")))
            item("wifi.slash", L("アカウント登録なし", "No sign-up"),
                 L("アカウント登録なしで遊べます。ひとりで遊ぶモードはサーバーと通信しません", "Play without signing up. Single-player modes never talk to a server")
                    + (FeatureFlags.lanMatch ? L("（オンライン機能は、ルールに同意して使い始めた時だけ通信します。同意した後は、ランク戦の結果も中継サーバーへ送ります）。課金は Apple が処理します。",
                                                 " (online features connect only after you accept the online rules; after that, ranked results are also sent to the relay server). Purchases are processed by Apple.")
                                             : L("。課金は Apple が処理します。", ". Purchases are processed by Apple.")))
            if FeatureFlags.lanMatch {
                item("globe.asia.australia.fill", L("オンライン機能（同意した場合のみ）", "Online features (only after you agree)"), OnlineRelayConfig.privacyNote)
            }
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
            if FeatureFlags.lanMatch {
                SettingsDivider()
                SettingsLinkRow(title: L("コミュニティガイドライン", "Community Guidelines"), symbol: "person.3.sequence.fill", external: true,
                                identifier: "privacy_guidelines") {
                    openURL(FeatureFlags.communityGuidelinesURL)
                }
                SettingsDivider()
                SettingsLinkRow(title: L("通報とブロック", "Reporting and Blocking"), symbol: "exclamationmark.shield.fill", external: true,
                                identifier: "privacy_safety") {
                    openURL(FeatureFlags.safetyURL)
                }
            }
            SettingsDivider()
            SettingsLinkRow(title: L("データの削除とプライバシーの選択", "Data Deletion & Privacy Choices"), symbol: "person.badge.key.fill",
                            external: true, identifier: "privacy_choices") {
                openURL(FeatureFlags.privacyChoicesURL)
            }
            SettingsDivider()
            SettingsLinkRow(title: L("外部送信について", "External Transmission"), symbol: "arrow.up.forward.app.fill",
                            external: true, identifier: "privacy_external") {
                openURL(FeatureFlags.externalTransmissionURL)
            }
            SettingsDivider()
            SettingsLinkRow(title: L("規約・法的表示の一覧", "All Legal Documents"), symbol: "building.columns.fill", external: true,
                            identifier: "privacy_legal") {
                openURL(FeatureFlags.legalIndexURL)
            }
        }
    }

    // MARK: オンライン機能

    private var onlinePanel: some View {
        SettingsSection(title: L("オンライン機能", "Online Features"), symbol: "antenna.radiowaves.left.and.right") {
            switch app.onlineAccess {
            case .available:
                item("checkmark.seal.fill", L("利用中", "On"),
                     L("オンラインのルールに同意済みです。アプリを開いている間、フレンドの申請・招待を受け取るためにフレンドサーバーへ接続します。ランクもフレンドサーバーに預けます。",
                       "You accepted the online rules. While the app is open, it connects to the friend server to receive friend requests and invites. Your rank is also stored on the friend server."))
                Button {
                    app.audio.play(.uiTap)
                    confirmsRevoke = true
                } label: {
                    Label(L("オンライン機能をやめる", "Stop Using Online Features"), systemImage: "wifi.slash")
                        .lineLimit(1)
                }
                .buttonStyle(LiveOpsTallButtonStyle(base: SecondaryButtonStyle()))
                .accessibilityIdentifier("privacy_online_revoke")
            case .needsConsent:
                item("circle.dashed", L("未使用", "Off"),
                     L("ホームの「オンライン」を開くと、ルールへの同意の画面が出ます。同意するまでフレンドサーバーへは接続しません。",
                       "Open Online from Home to review and accept the rules. Until then, the app never connects to the friend server."))
            case .ageRestricted, .disabled:
                item("person.crop.circle.badge.exclamationmark", L("利用できません", "Unavailable"), OnlineAccess.ageRestrictedMessage)
            }
            if app.friends.hasServerData {
                SettingsDivider()
                item("externaldrive.badge.xmark", L("フレンドサーバーのデータ", "Friend Server Data"),
                     L("フレンドサーバーには、あなたのフレンドコードの受信箱（鍵のハッシュ・最後に接続した日時）と、預かり中のフレンド申請（受け付けから 14 日）、ランク（段位・星・勝敗数）があります。受信箱は最後の接続から 1 年で自動的に削除されます。",
                       "The friend server holds your friend code's inbox (a hashed key and your last connection time), friend requests held for you (up to 14 days) and your rank (tier, stars, wins and losses). The inbox is deleted automatically one year after your last connection."))
                Button {
                    app.audio.play(.uiTap)
                    confirmsErase = true
                } label: {
                    HStack(spacing: 6) {
                        if erasing { ProgressView().controlSize(.small) }
                        Label(L("フレンドサーバーのデータを削除", "Delete Friend Server Data"), systemImage: "trash")
                            .foregroundStyle(Theme.danger)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(LiveOpsTallButtonStyle(base: SecondaryButtonStyle()))
                .disabled(erasing)
                .accessibilityIdentifier("privacy_server_erase")
            }
            SettingsDivider()
            blockedList
        }
    }

    @ViewBuilder
    private var blockedList: some View {
        let blocked = app.profile.blockedPlayers
        VStack(alignment: .leading, spacing: 4) {
            Text(L("ブロックしたプレイヤー（\(blocked.count)）", "Blocked Players (\(blocked.count))"))
                .font(Theme.heading(13))
                .foregroundStyle(Theme.textPrimary)
            if blocked.isEmpty {
                Text(L("いません。オンラインの画面の「…」からブロックできます。", "None. Block players from the \"…\" menu in online screens."))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(blocked.reversed())) { b in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(FriendNames.display(b.name)).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Text(FriendCode.display(b.code)).font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 4)
                        Button {
                            app.audio.play(.uiTap)
                            app.friends.unblock(code: b.code)
                            app.showToast(L("ブロックを解除しました", "Unblocked"))
                        } label: {
                            Text(L("解除", "Unblock"))
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.cyan)
                                .frame(minWidth: 52, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("\(FriendNames.display(b.name)) のブロックを解除", "Unblock \(FriendNames.display(b.name))"))
                        .accessibilityIdentifier("privacy_unblock_\(b.code)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                if FeatureFlags.lanMatch, app.friends.hasServerData {
                    Text(L("フレンドサーバーにあるあなたの受信箱（鍵のハッシュ・最後に接続した日時・預かり中のフレンド申請）とランクも、先に削除します（通信が必要です）。ほかのプレイヤーの受信箱に預かられているあなたのフレンド申請は、受け付けから 14 日で自動的に削除されます。",
                           "Your inbox on the friend server (hashed key, last connection time and held friend requests) and your rank stored there are deleted first (requires a connection). Friend requests you sent that are held in other players' inboxes are deleted automatically 14 days after they were sent."))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("privacy_server_data_note")
                }
                if erasing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L("フレンドサーバーのデータを削除しています…", "Deleting friend server data…"))
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
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
                            .disabled(erasing)
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
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Theme.danger.opacity(0.4), lineWidth: 1))
    }

    /// 全データの削除: 中継サーバーの受信箱とクラウドのランクを先に消してから（繋いだ・預けたことがある時だけ）、端末のデータを消す。
    private func deleteAll() {
        app.prepareForDataDeletion()
        guard FeatureFlags.lanMatch, app.friends.hasServerData else {
            finishDeleteAll()
            return
        }
        erasing = true
        app.friends.eraseServerData { ok in
            erasing = false
            if ok {
                finishDeleteAll()
            } else {
                deleteEraseFailed = true
            }
        }
    }

    private func finishDeleteAll() {
        DailyReminder.cancel()
        app.prepareForDataDeletion()
        app.persistence.deleteAll()
        app.profile = Profile()
        app.router.popToRoot()
        app.showToast(L("すべてのデータを削除しました", "All data deleted"))
    }

    /// オンライン機能をやめて、中継サーバーの受信箱を消す。
    private func eraseServerData() {
        erasing = true
        app.revokeOnlineRulesAndEraseServerData { ok in
            erasing = false
            app.showToast(ok
                ? L("フレンドサーバーのデータを削除し、オンライン機能をやめました", "Deleted your friend server data and turned off online features")
                : L("フレンドサーバーのデータを削除できませんでした。通信できる場所でもう一度お試しください", "Couldn't delete your friend server data. Please try again with a connection"))
        }
    }
}
