import SwiftUI
import UniformTypeIdentifiers
import VelstriaCore

// 担当: ui-flow / outgame。UI005 アカウント設定（MLBB 2.2.16 のアカウント設定の作り: 中央に連携の行、右に ID・アカウント設定スコア・切替）。
// - VELSIA アカウント: アカウント ID（= フレンドコード）とパスワード、クラウド保存（AccountCenter・relay の CloudAccount）
// - サードパーティアカウント: Game Center（本人確認の署名で連携。別の端末で同じ Game Center ならログインできる）
// - データのバックアップ: ファイルへの書き出しと復元（オフラインでも使える。前からの機能）
// MLBB の TikTok・Facebook・WhatsApp・メール・2 段階認証・テストサーバーは Velstria に無いので出さない。

struct AccountPane: View {
    @Environment(AppModel.self) private var app
    @State private var exportURL: URL?
    @State private var exportError = false
    @State private var importing = false
    @State private var pendingImport: Profile?
    @State private var importError: String?
    @State private var sheet: AccountSheet?
    /// 取り出したアカウント（切り替えの確認待ち）。
    @State private var downloaded: CloudAccountDownload?
    @State private var pendingSwitch: PendingSwitch?
    @State private var confirmUnlink = false
    @State private var confirmErase = false
    @State private var gameCenterTaken = false
    @State private var showsHelp = false

    enum AccountSheet: String, Identifiable {
        case password, login
        var id: String { rawValue }
    }

    struct PendingSwitch: Identifiable {
        let id = UUID()
        var profile: Profile
        var info: CloudAccountInfo
    }

    private var account: AccountCenter { app.account }
    private var allowed: Bool { app.syncsCloudRank }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 12) {
                leftColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                rightColumn
                    .frame(width: min(250, geo.size.width * 0.34))
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .task {
            prepareExport()
            await account.refresh()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data], allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .sheet(item: $sheet, onDismiss: takeDownloaded) { s in
            switch s {
            case .password:
                AccountPasswordSheet().environment(app)
            case .login:
                AccountLoginSheet { downloaded = $0 }.environment(app)
            }
        }
        .alert(L("データを置き換えますか？", "Replace Your Data?"), isPresented: Binding(
            get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })
        ) {
            Button(L("置き換える", "Replace"), role: .destructive) { applyImport() }
            Button(L("キャンセル", "Cancel"), role: .cancel) { pendingImport = nil }
        } message: {
            Text(importMessage)
        }
        .alert(L("復元できませんでした", "Couldn't Restore"), isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert(L("このアカウントに切り替えますか？", "Switch to This Account?"), isPresented: Binding(
            get: { pendingSwitch != nil }, set: { if !$0 { pendingSwitch = nil } })
        ) {
            Button(L("切り替える", "Switch"), role: .destructive) { applySwitch() }
            Button(L("キャンセル", "Cancel"), role: .cancel) { pendingSwitch = nil }
        } message: {
            Text(switchMessage)
        }
        .alert(L("Game Center の連携を解除しますか？", "Unlink Game Center?"), isPresented: $confirmUnlink) {
            Button(L("解除する", "Unlink"), role: .destructive) { Task { await unlinkGameCenter() } }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(app.profile.account.hasPassword
                 ? L("解除しても、アカウント ID とパスワードでログインできます。", "You can still log in with your account ID and password.")
                 : L("パスワードが無いので、解除するとほかの端末でこのアカウントにログインできなくなります。", "Without a password, you won't be able to log in to this account on other devices."))
        }
        .alert(L("この Game Center は別のアカウントに連携されています", "This Game Center Is Linked to Another Account"), isPresented: $gameCenterTaken) {
            Button(L("そのアカウントに切り替える", "Switch to That Account")) { Task { await loginWithGameCenter() } }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("連携しているアカウントに切り替えられます（今の端末のデータは置き換えられます）。", "You can switch to the linked account (this device's data will be replaced)."))
        }
        .alert(L("アカウントを削除しますか？", "Delete Your Account?"), isPresented: $confirmErase) {
            Button(L("削除する", "Delete"), role: .destructive) { Task { await eraseAccount() } }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("サーバーに預けたデータ・パスワード・Game Center の連携を削除します。ほかの端末からこのアカウントにログインできなくなります。この端末のデータは残ります。",
                   "Deletes the data stored on our server, your password and your Game Center link. You won't be able to log in to this account from other devices. Data on this device is kept."))
        }
        .alert(L("アカウントについて", "About Accounts"), isPresented: $showsHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(L("アカウント ID はフレンドコードです。パスワードか Game Center を設定すると、機種変更やアプリの入れ直しの後も「アカウント切替」で今のデータに戻せます。設定した後は、試合の後とアプリを閉じた時にクラウドへ自動で保存します（10 分に 1 回まで）。",
                   "Your account ID is your friend code. Set a password or link Game Center to get your data back with Switch Account after changing devices or reinstalling. After that, your data is saved to the cloud automatically after matches and when you close the app (at most every 10 minutes)."))
        }
    }

    // MARK: 中央の列

    private var leftColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                if !allowed { consentNotice }
                if account.unsupported { unsupportedNotice }
                sectionHeader(L("VELSIAアカウント", "VELSIA Account"), help: true)
                row(icon: AnyView(VelsiaMark()), title: L("パスワード", "Password"), value: passwordValue,
                    valueActive: app.profile.account.hasPassword, id: "account_password", enabled: allowed) {
                    sheet = .password
                }
                row(icon: AnyView(symbolIcon("icloud.fill")), title: L("クラウド保存", "Cloud Save"), value: saveValue,
                    valueActive: app.profile.account.lastCloudSave != nil, id: "account_cloud_save", enabled: allowed) {
                    Task { await saveNow() }
                }
                sectionHeader(L("サードパーティアカウント", "Third-Party Accounts"))
                row(icon: AnyView(GameCenterMark(size: 30)), title: "Game Center", value: gameCenterValue,
                    valueActive: app.profile.account.gameCenterAlias != nil, id: "account_gamecenter", enabled: allowed) {
                    if app.profile.account.gameCenterAlias != nil { confirmUnlink = true } else { Task { await linkGameCenter() } }
                }
                sectionHeader(L("データのバックアップ", "Backup File"))
                exportRow
                row(icon: AnyView(symbolIcon("folder.fill")), title: L("ファイルから復元", "Restore from File"),
                    value: L("タップして選ぶ", "Tap to choose"), valueActive: false, id: "account_import", enabled: true) {
                    FlowFX.tap(app)
                    importing = true
                }
                Text(L("バックアップのファイルにはリプレイの録画は入りません（リプレイ画面の共有で 1 件ずつ書き出せます）。購入済みのプレミアム商品は、ストアの「購入の復元」からも戻せます。",
                       "Backup files don't include replay recordings (export them one by one with Share on the Replays screen). Premium purchases can also be restored from Restore Purchases in the Store."))
                    .font(.system(size: 10))
                    .foregroundStyle(HubStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(.bottom, 8)
        }
    }

    private var consentNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe").font(.system(size: 18)).foregroundStyle(HubStyle.accent)
            Text(app.onlineAccess == .ageRestricted
                 ? OnlineAccess.ageRestrictedMessage
                 : L("パスワード・Game Center・クラウド保存は、オンライン機能のルールに同意すると使えます。ファイルのバックアップはいつでも使えます。",
                     "Password, Game Center and Cloud Save need the online rules. Backup files always work."))
                .font(.system(size: 11))
                .foregroundStyle(HubStyle.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if app.onlineAccess == .needsConsent {
                Button(L("同意へ", "Agree")) {
                    FlowFX.tap(app)
                    app.router.push(.onlineLobby)
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.cyan))
                .accessibilityIdentifier("account_consent")
            }
        }
        .padding(10)
        .background(HubPanel())
    }

    private var unsupportedNotice: some View {
        Label(L("サーバーの更新待ちのため、アカウントはまだ使えません（ファイルのバックアップは使えます）。",
                "The server hasn't been updated yet, so accounts aren't available (backup files still work)."),
              systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundStyle(HubStyle.gold)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HubPanel())
    }

    private func sectionHeader(_ title: String, help: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(HubStyle.text)
            if help {
                Button {
                    showsHelp = true
                } label: {
                    Image(systemName: "questionmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(HubStyle.text)
                        .frame(width: 22, height: 22)
                        .background(DiamondShape().fill(Color.white.opacity(0.14)))
                        .frame(width: 34, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("説明", "Help"))
                .accessibilityIdentifier("account_help")
            }
        }
        .padding(.top, 6)
    }

    /// 連携の 1 行（MLBB: 青灰の帯に、左にアイコンと名前、右に連携先か「タップして連携」）。
    private func row(icon: AnyView, title: String, value: String, valueActive: Bool, id: String, enabled: Bool,
                     action: @escaping () -> Void) -> some View {
        Button {
            guard enabled, account.busy == nil else { return }
            action()
        } label: {
            rowLabel(icon: icon, title: title, value: value, valueActive: valueActive, busy: busyRow(id))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityIdentifier(id)
    }

    private func rowLabel(icon: AnyView, title: String, value: String, valueActive: Bool, busy: Bool) -> some View {
        HStack(spacing: 10) {
            icon.frame(width: 32, height: 32)
            Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(HubStyle.text).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            if busy {
                ProgressView().tint(.white)
            } else {
                Text(value)
                    .font(.system(size: valueActive ? 14 : 13, weight: valueActive ? .semibold : .regular))
                    .foregroundStyle(valueActive ? Color.white : HubStyle.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(Rectangle().fill(HubStyle.row))
        .overlay(Rectangle().stroke(HubStyle.stroke, lineWidth: 0.6))
        .contentShape(Rectangle())
    }

    private func busyRow(_ id: String) -> Bool {
        switch (account.busy, id) {
        case (.password?, "account_password"), (.save?, "account_cloud_save"), (.gameCenter?, "account_gamecenter"): return true
        default: return false
        }
    }

    private func symbolIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(LinearGradient(colors: [Color(red: 0.36, green: 0.62, blue: 0.95), Color(red: 0.16, green: 0.32, blue: 0.62)],
                                                     startPoint: .top, endPoint: .bottom)))
    }

    private var exportRow: some View {
        Group {
            if let exportURL {
                ShareLink(item: exportURL, preview: SharePreview(L("VELSIA バックアップ", "VELSIA Backup"))) {
                    rowLabel(icon: AnyView(symbolIcon("square.and.arrow.up")), title: L("ファイルに書き出す", "Export to File"),
                             value: L("タップして書き出す", "Tap to export"), valueActive: false, busy: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account_export")
            } else {
                Button {
                    prepareExport()
                } label: {
                    rowLabel(icon: AnyView(symbolIcon("arrow.clockwise")), title: L("ファイルに書き出す", "Export to File"),
                             value: exportError ? L("再試行", "Retry") : L("準備中…", "Preparing…"), valueActive: false, busy: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account_export_retry")
            }
        }
    }

    private var passwordValue: String {
        app.profile.account.hasPassword ? L("設定済み", "Set") : L("タップして設定", "Tap to set")
    }

    private var saveValue: String {
        guard let d = app.profile.account.lastCloudSave else { return L("タップして保存", "Tap to save") }
        return L("\(FlowText.date(d)) に保存", "Saved \(FlowText.date(d))")
    }

    private var gameCenterValue: String {
        app.profile.account.gameCenterAlias ?? L("タップして連携", "Tap to link")
    }

    // MARK: 右の列（ID・スコア・切替）

    private var rightColumn: some View {
        let p = app.profile
        let score = AccountScore.of(p.account, online: allowed)
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                GameCenterMark(size: 40)
                    .opacity(p.account.gameCenterAlias != nil ? 1 : 0.45)
                Text(L("アカウントID：", "Account ID: ") + (p.inboxRegistered || allowed ? FriendCode.display(p.friendCode) : "—"))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(HubStyle.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("account_id")
                AccountScoreGauge(value: score.value)
                    .frame(width: 88, height: 88)
                HStack(spacing: 4) {
                    Text(L("アカウント設定スコア", "Account Score")).font(.system(size: 12, weight: .semibold)).foregroundStyle(HubStyle.accent)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Button { showsHelp = true } label: {
                        Image(systemName: "questionmark.circle").font(.system(size: 13)).foregroundStyle(HubStyle.dim)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("説明", "Help"))
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(AccountScore.Item.allCases, id: \.self) { item in
                        checkItem(item, done: !score.missing.contains(item))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                plateButton(L("アカウント切替", "Switch Account"), id: "account_switch", enabled: allowed) {
                    sheet = .login
                }
                if allowed && (p.account.isRecoverable || p.account.lastCloudSave != nil) {
                    plateButton(L("アカウントを削除", "Delete Account"), id: "account_delete", enabled: true, danger: true) {
                        confirmErase = true
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func checkItem(_ item: AccountScore.Item, done: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                DiamondShape()
                    .fill(done ? Theme.success.opacity(0.85) : Color.white.opacity(0.18))
                    .frame(width: 16, height: 16)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundStyle(.black)
                        .frame(width: 16, height: 16)
                } else {
                    Circle().fill(Color.red).frame(width: 7, height: 7).offset(x: 3, y: -3)
                }
            }
            Text(item.title)
                .font(.system(size: 12))
                .foregroundStyle(done ? HubStyle.text : HubStyle.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title + (done ? L(" 済み", " done") : L(" まだ", " not yet")))
    }

    private func plateButton(_ title: String, id: String, enabled: Bool, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            guard enabled, account.busy == nil else { return }
            FlowFX.tap(app)
            action()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(danger ? Color(red: 1, green: 0.78, blue: 0.78) : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Rectangle().fill(LinearGradient(colors: danger
                                                            ? [Color(red: 0.45, green: 0.18, blue: 0.24), Color(red: 0.28, green: 0.10, blue: 0.16)]
                                                            : [Color(red: 0.30, green: 0.52, blue: 0.88), Color(red: 0.16, green: 0.30, blue: 0.62)],
                                                            startPoint: .top, endPoint: .bottom)))
                .overlay(Rectangle().stroke(danger ? Color(red: 1, green: 0.6, blue: 0.6).opacity(0.5) : HubStyle.accent.opacity(0.7), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityIdentifier(id)
    }

    // MARK: 操作

    private func saveNow() async {
        FlowFX.tap(app)
        switch await account.saveNow() {
        case .success:
            FlowFX.confirm(app)
            app.showToast(L("クラウドに保存しました", "Saved to the cloud"))
        case .failure(let f):
            FlowFX.error(app)
            app.showToast(f.message)
        }
    }

    private func linkGameCenter() async {
        FlowFX.tap(app)
        switch await account.linkGameCenter() {
        case .success:
            FlowFX.reward(app)
            app.showToast(L("Game Center と連携しました", "Linked with Game Center"))
        case .failure(.api(.gameCenterTaken)):
            FlowFX.error(app)
            gameCenterTaken = true
        case .failure(let f):
            FlowFX.error(app)
            app.showToast(f.message)
        }
    }

    private func unlinkGameCenter() async {
        switch await account.unlinkGameCenter() {
        case .success:
            FlowFX.confirm(app)
            app.showToast(L("Game Center の連携を解除しました", "Unlinked Game Center"))
        case .failure(let f):
            FlowFX.error(app)
            app.showToast(f.message)
        }
    }

    private func loginWithGameCenter() async {
        switch await account.downloadWithGameCenter() {
        case .success(let d):
            downloaded = d
            takeDownloaded()
        case .failure(let f):
            FlowFX.error(app)
            app.showToast(f.message)
        }
    }

    private func eraseAccount() async {
        switch await account.erase() {
        case .success:
            FlowFX.confirm(app)
            app.showToast(L("アカウントを削除しました", "Account deleted"))
        case .failure(let f):
            FlowFX.error(app)
            app.showToast(f.message)
        }
    }

    /// 取り出したアカウントを読んで、切り替えの確認を出す（シートを閉じ終わってから）。
    private func takeDownloaded() {
        guard let d = downloaded else { return }
        downloaded = nil
        do {
            let profile = try app.persistence.importProfile(from: d.json)
            pendingSwitch = PendingSwitch(profile: profile, info: d.info)
        } catch {
            FlowFX.error(app)
            app.showToast(L("アカウントのデータを読めませんでした（アプリを最新にしてください）", "Couldn't read the account data (update the app)"))
        }
    }

    private var switchMessage: String {
        guard let s = pendingSwitch else { return "" }
        let p = s.profile
        let name = p.displayName.isEmpty ? "—" : p.displayName
        let saved = s.info.savedDate.map { FlowText.date($0) } ?? "—"
        let warning = app.profile.account.isRecoverable
            ? L("今のアカウントには、パスワードか Game Center でいつでも戻れます。", "You can return to your current account with its password or Game Center.")
            : L("今のアカウントにはパスワードも Game Center も無いため、切り替えると今のデータには戻れません。", "Your current account has no password or Game Center, so you can't come back to your current data.")
        return L("ID \(FriendCode.display(p.friendCode))・\(name)（Lv.\(p.accountLevel)・\(p.career.matches) 試合）\nクラウドに保存した日時: \(saved)\nこの端末のデータはこのアカウントのデータに置き換わります。\(warning)",
                 "ID \(FriendCode.display(p.friendCode)) · \(name) (Lv.\(p.accountLevel), \(p.career.matches) matches)\nSaved to the cloud: \(saved)\nThis device's data will be replaced with this account's data. \(warning)")
    }

    private func applySwitch() {
        guard let s = pendingSwitch else { return }
        pendingSwitch = nil
        account.switchTo(s.profile, info: s.info)
        FlowFX.reward(app)
        app.showToast(L("アカウントを切り替えました", "Switched accounts"))
        prepareExport()
    }

    // MARK: ファイルのバックアップ

    /// 共有用の一時ファイルを最新のプロフィールで作り直す。
    private func prepareExport() {
        guard let data = app.persistence.exportProfileData(app.profile) else {
            exportURL = nil
            exportError = true
            return
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("VelstriaBackup", isDirectory: true)
        let url = dir.appendingPathComponent("VELSIA-backup-\(f.string(from: Date())).json")
        do {
            try? FileManager.default.removeItem(at: dir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            exportURL = url
            exportError = false
        } catch {
            exportURL = nil
            exportError = true
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                pendingImport = try app.persistence.importProfile(from: data)
            } catch {
                FlowFX.error(app)
                importError = L("VELSIA のバックアップファイルではないか、ファイルが壊れています。", "This isn't a VELSIA backup, or the file is damaged.")
            }
        }
    }

    private var importMessage: String {
        guard let p = pendingImport else { return "" }
        let name = p.displayName.isEmpty ? "—" : p.displayName
        return L("バックアップ: \(name)（Lv.\(p.accountLevel)・\(p.career.matches) 試合・ヒーロー \(p.ownedHeroIDs.count) 体）\n現在のデータは上書きされ、元に戻せません。この端末の年齢区分と購入の記録は引き継がれます。有償 AstralGem とスターパス プレミアムは購入の記録で確認できる分だけ復元されます。",
                 "Backup: \(name) (Lv.\(p.accountLevel), \(p.career.matches) matches, \(p.ownedHeroIDs.count) heroes)\nYour current data will be overwritten. This can't be undone. This device's age group and purchase records are kept. Paid AstralGem and Star Pass Premium are restored only as far as the purchase records support.")
    }

    private func applyImport() {
        guard let imported = pendingImport else { return }
        pendingImport = nil
        let p = BackupRestore.merged(imported: imported, current: app.profile)
        app.profile = p
        app.persistence.saveNow(p)
        FlowFX.reward(app)
        app.showToast(L("データを復元しました", "Data restored"))
        prepareExport()
        // 購入済みのプレミアム・当月の課金額を App Store 側の記録で確認し直す
        Task {
            await app.storeKit.refreshEntitlements()
            await app.storeKit.syncMonthlySpendFromHistory()
        }
    }
}

extension AccountScore.Item {
    var title: String {
        switch self {
        case .password: return L("パスワード", "Password")
        case .gameCenter: return L("Game Center 連携", "Game Center link")
        case .cloudSave: return L("7 日以内のクラウド保存", "Cloud save within 7 days")
        }
    }
}

// MARK: - パスワードの設定

private struct AccountPasswordSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private var issue: AccountPassword.Issue? { AccountPassword.validate(password, confirm: confirm) }

    var body: some View {
        ZStack {
            HubBackdrop()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(app.profile.account.hasPassword ? L("パスワードの変更", "Change Password") : L("パスワードの設定", "Set a Password"))
                        .font(Celestial.heading(18))
                        .foregroundStyle(HubStyle.text)
                    Spacer()
                    FlowCloseButton(identifier: "account_password_close") { dismiss() }
                }
                Text(L("ほかの端末の「アカウント切替」で、アカウント ID（\(FriendCode.display(app.profile.friendCode))）とこのパスワードを入れるとログインできます。\(AccountPassword.minLength)〜\(AccountPassword.maxLength) 文字。パスワードはサーバーにも保存しません（照合用の値だけを送ります）。",
                       "On another device, use Switch Account with your account ID (\(FriendCode.display(app.profile.friendCode))) and this password. \(AccountPassword.minLength)–\(AccountPassword.maxLength) characters. Your password isn't stored on our server (only a value to check it is sent)."))
                    .font(.system(size: 12))
                    .foregroundStyle(HubStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
                field(L("パスワード", "Password"), text: $password, id: "account_password_field")
                    .focused($focused)
                field(L("パスワード（確認）", "Confirm password"), text: $confirm, id: "account_password_confirm")
                if let error {
                    Text(error).font(.system(size: 12)).foregroundStyle(Theme.danger)
                } else if !password.isEmpty, let issue {
                    Text(AccountPassword.message(issue)).font(.system(size: 12)).foregroundStyle(Theme.danger)
                }
                HStack {
                    Spacer()
                    Button(L("キャンセル", "Cancel")) { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button {
                        Task { await submit() }
                    } label: {
                        if app.account.busy == .password {
                            ProgressView().tint(.black).frame(minWidth: 80)
                        } else {
                            Text(L("設定する", "Set Password"))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(issue != nil || app.account.busy != nil)
                    .opacity(issue == nil ? 1 : 0.5)
                    .accessibilityIdentifier("account_password_submit")
                }
            }
            .padding(18)
            .frame(maxWidth: 520)
            .background(HubPanel(fill: HubStyle.panelDeep))
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
    }

    private func field(_ title: String, text: Binding<String>, id: String) -> some View {
        SecureField(title, text: text)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .textContentType(.newPassword)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Rectangle().fill(Color.black.opacity(0.35)))
            .overlay(Rectangle().stroke(HubStyle.stroke, lineWidth: 1))
            .accessibilityIdentifier(id)
    }

    private func submit() async {
        error = nil
        switch await app.account.setPassword(password) {
        case .success:
            FlowFX.reward(app)
            app.showToast(L("パスワードを設定し、データをクラウドに保存しました", "Password set and data saved to the cloud"))
            dismiss()
        case .failure(let f):
            FlowFX.error(app)
            error = f.message
        }
    }
}

// MARK: - アカウント切替（ログイン）

private struct AccountLoginSheet: View {
    /// 取り出せたアカウント（切り替えの確認は呼び出し側がシートを閉じた後に出す）。
    let onDownloaded: (CloudAccountDownload) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var idText = ""
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        ZStack {
            HubBackdrop()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("アカウント切替", "Switch Account")).font(Celestial.heading(18)).foregroundStyle(HubStyle.text)
                    Spacer()
                    FlowCloseButton(identifier: "account_login_close") { dismiss() }
                }
                Text(L("切り替えたいアカウントの ID（フレンドコード）とパスワードを入れるか、連携した Game Center でログインします。この端末のデータは、切り替える前に確認します。",
                       "Enter the account ID (friend code) and password, or log in with the linked Game Center. You'll confirm before this device's data is replaced."))
                    .font(.system(size: 12))
                    .foregroundStyle(HubStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    TextField(L("アカウント ID（8 文字）", "Account ID (8 characters)"), text: $idText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .modifier(LoginFieldStyle())
                        .accessibilityIdentifier("account_login_id")
                    SecureField(L("パスワード", "Password"), text: $password)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .modifier(LoginFieldStyle())
                        .accessibilityIdentifier("account_login_password")
                }
                if let error {
                    Text(error).font(.system(size: 12)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button {
                        Task { await loginGameCenter() }
                    } label: {
                        HStack(spacing: 6) {
                            GameCenterMark(size: 20)
                            Text(L("Game Center でログイン", "Log In with Game Center")).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(app.account.busy != nil)
                    .accessibilityIdentifier("account_login_gamecenter")
                    Spacer()
                    Button {
                        Task { await login() }
                    } label: {
                        if app.account.busy == .login {
                            ProgressView().tint(.black).frame(minWidth: 80)
                        } else {
                            Text(L("ログイン", "Log In"))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(idText.isEmpty || password.isEmpty || app.account.busy != nil)
                    .opacity(idText.isEmpty || password.isEmpty ? 0.5 : 1)
                    .accessibilityIdentifier("account_login_submit")
                }
            }
            .padding(18)
            .frame(maxWidth: 560)
            .background(HubPanel(fill: HubStyle.panelDeep))
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .preferredColorScheme(.dark)
    }

    private func login() async {
        error = nil
        let code: String
        switch FriendCode.parse(idText) {
        case .success(let c): code = c
        case .failure(let e):
            error = e.message
            return
        }
        switch await app.account.download(code: code, password: password) {
        case .success(let d):
            onDownloaded(d)
            dismiss()
        case .failure(let f):
            FlowFX.error(app)
            error = f.message
        }
    }

    private func loginGameCenter() async {
        error = nil
        switch await app.account.downloadWithGameCenter() {
        case .success(let d):
            onDownloaded(d)
            dismiss()
        case .failure(let f):
            FlowFX.error(app)
            error = f.message
        }
    }
}

private struct LoginFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Rectangle().fill(Color.black.opacity(0.35)))
            .overlay(Rectangle().stroke(HubStyle.stroke, lineWidth: 1))
    }
}

// MARK: - 絵

/// アカウント設定スコアの輪（MLBB: 橙の弧と中央の数）。
struct AccountScoreGauge: View {
    let value: Int

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(min(100, max(0, value))) / 100)
                .stroke(LinearGradient(colors: [Color(red: 1.0, green: 0.78, blue: 0.35), Color(red: 0.98, green: 0.52, blue: 0.18)],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(value)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.32))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("アカウント設定スコア \(value)", "Account score \(value)"))
        .accessibilityIdentifier("account_score")
    }
}

/// Game Center の印（4 色の泡を重ねた角丸の白い板。Apple の画像は使わずに描く）。
struct GameCenterMark: View {
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(Color.white)
            ZStack {
                Circle().fill(Color(red: 0.98, green: 0.36, blue: 0.62)).frame(width: size * 0.44).offset(x: -size * 0.12, y: -size * 0.1)
                Circle().fill(Color(red: 0.42, green: 0.80, blue: 0.98)).frame(width: size * 0.40).offset(x: size * 0.13, y: -size * 0.12)
                Circle().fill(Color(red: 0.58, green: 0.86, blue: 0.40)).frame(width: size * 0.38).offset(x: size * 0.12, y: size * 0.13)
                Circle().fill(Color(red: 0.99, green: 0.80, blue: 0.30)).frame(width: size * 0.36).offset(x: -size * 0.12, y: size * 0.13)
            }
            .blendMode(.multiply)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .accessibilityHidden(true)
    }
}

/// VELSIA の印（MLBB の Moonton の丸い印の位置。金の渦の代わりに星）。
struct VelsiaMark: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 0.98, green: 0.82, blue: 0.40), Color(red: 0.86, green: 0.48, blue: 0.10)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.2).padding(3)
            Image(systemName: "sparkle").font(.system(size: 15, weight: .bold)).foregroundStyle(Color(red: 0.12, green: 0.24, blue: 0.52))
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}
