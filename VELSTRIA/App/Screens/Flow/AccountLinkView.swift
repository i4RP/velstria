import SwiftUI
import UniformTypeIdentifiers
import VelstriaCore

// 担当: ui-flow。UI005 アカウント連携（オフライン: 端末内データのバックアップと復元）。

struct AccountLinkView: View {
    @Environment(AppModel.self) private var app
    @State private var exportURL: URL?
    @State private var exportError = false
    @State private var importing = false
    @State private var pendingImport: Profile?
    @State private var importError: String?

    var body: some View {
        ScreenScaffold(title: L("アカウント・データ", "Account & Data")) {
            HStack(alignment: .top, spacing: 14) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        storagePanel
                        dataSummary
                    }
                    .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 12) {
                    backupPanel
                    restorePanel
                    Spacer(minLength: 0)
                }
                .frame(width: 300)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .task { prepareExport() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data], allowsMultipleSelection: false) { result in
            handleImport(result)
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
    }

    // MARK: 説明

    private var storagePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("データはこの端末に保存されています", "Your data lives on this device"), systemImage: "iphone")
                .font(Theme.heading(16))
                .foregroundStyle(Theme.textPrimary)
            Text(L("VELSIA はオフラインで動作し、オンラインアカウントやサーバーを使いません。プレイデータ（プロフィール・所持品・戦績・購入履歴）はこの iPhone の中にだけ保存されます。",
                   "VELSIA runs offline and doesn't use online accounts or servers. Your play data (profile, inventory, history and purchase records) is stored only on this iPhone."))
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            bullet("icloud.fill", L("端末のバックアップ（iCloud / Mac）にも含まれます。", "It's included in your device backups (iCloud / Mac)."))
            bullet("arrow.triangle.2.circlepath", L("機種変更の際は、下のバックアップファイルを新しい端末で読み込めます。", "When switching devices, restore the backup file below on the new device."))
            bullet("exclamationmark.triangle.fill", L("アプリを削除するとデータも削除されます。定期的なバックアップをおすすめします。", "Deleting the app deletes your data. Back up regularly."))
            bullet("cart.fill", L("購入済みのプレミアム商品は、ストアの「購入の復元」からも復元できます。", "Premium purchases can also be restored from Restore Purchases in the Store."))
        }
        .padding(14)
        .glass(cornerRadius: 16)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(Theme.body(12)).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.cyan)
        }
    }

    private var dataSummary: some View {
        let p = app.profile
        return VStack(alignment: .leading, spacing: 8) {
            FlowSectionTitle(title: L("現在のデータ", "Current Data"), symbol: "person.crop.square.fill")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                FlowStatCell(title: L("名前", "Name"), value: p.displayName.isEmpty ? "—" : p.displayName)
                FlowStatCell(title: L("レベル", "Level"), value: "\(p.accountLevel)")
                FlowStatCell(title: L("試合", "Matches"), value: "\(p.career.matches)")
                FlowStatCell(title: L("ヒーロー", "Heroes"), value: "\(p.ownedHeroIDs.count)")
            }
            Text(L("リプレイの録画ファイルはバックアップに含まれません。", "Replay recordings are not included in the backup."))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: バックアップ

    private var backupPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("バックアップ", "Back Up"), systemImage: "square.and.arrow.up.fill")
                .font(Theme.heading(15))
                .foregroundStyle(Theme.gold)
            Text(L("プロフィールを JSON ファイルとして書き出し、ファイル App や AirDrop で保存します。",
                   "Export your profile as a JSON file and save it with Files or AirDrop."))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let exportURL {
                ShareLink(item: exportURL, preview: SharePreview(L("VELSIA バックアップ", "VELSIA Backup"))) {
                    Label(L("バックアップを書き出す", "Export Backup"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("account_export")
            } else {
                Button {
                    prepareExport()
                } label: {
                    Label(exportError ? L("再試行", "Retry") : L("準備中…", "Preparing…"), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(minHeight: 44)
                .accessibilityIdentifier("account_export_retry")
            }
        }
        .padding(14)
        .glass(cornerRadius: 16, tint: Theme.gold.opacity(0.6))
    }

    private var restorePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("復元", "Restore"), systemImage: "square.and.arrow.down.fill")
                .font(Theme.heading(15))
                .foregroundStyle(Theme.cyan)
            Text(L("バックアップファイルを読み込みます。現在のデータは置き換えられます（この端末の年齢区分と購入の記録は保持されます）。",
                   "Load a backup file. Your current data will be replaced (this device's age group and purchase records are kept)."))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                FlowFX.tap(app)
                importing = true
            } label: {
                Label(L("ファイルから復元", "Restore from File"), systemImage: "folder.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(minHeight: 44)
            .accessibilityIdentifier("account_import")
        }
        .padding(14)
        .glass(cornerRadius: 16, tint: Theme.cyan.opacity(0.6))
    }

    // MARK: 処理

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
