import SwiftUI
import UniformTypeIdentifiers
import VelstriaCore

// 担当: ui-liveops。UI035 リプレイ一覧（再生・お気に入り・名前・共有・取り込み・詳細・削除）。
// - 保存数の上限は PersistenceService.maxReplays（唯一の定義）。お気に入りは上限の対象外（別枠 maxFavoriteReplays）。
// - 読み込み・復号はメインスレッドの外（読み込み中は全体に待機表示を重ね、二重に開始しない）。
// - 再生できるかはメタの版数で先に判定して行を薄くする。版数の無い旧版のメタは、開いた時にファイルから補う。
// - 書き出しは各行のメニューと詳細の共有ボタン（.vreplay）。取り込みはファイル選択（と他のアプリからの「開く」）。

enum ReplayLibrary {
    enum LoadError: Error, Equatable {
        /// ファイルが見つからない・壊れている。
        case missing
        /// 記録時とシミュレーション版数（または形式）が異なり再現できない。
        case incompatible
    }

    /// 一覧の絞り込み（出どころ・お気に入り）。
    enum Filter: String, Hashable, CaseIterable {
        case all, favorites, mine, spectate, online, imported

        var title: String {
            switch self {
            case .all: return L("すべて", "All")
            case .favorites: return L("お気に入り", "Favorites")
            case .mine: return L("自分の試合", "My Matches")
            case .spectate: return L("AI 観戦", "AI Matches")
            case .online: return L("オンライン", "Online")
            case .imported: return L("取り込み", "Imported")
            }
        }

        var symbol: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .favorites: return "star.fill"
            case .mine: return "person.fill"
            case .spectate: return "eye.fill"
            case .online: return "antenna.radiowaves.left.and.right"
            case .imported: return "square.and.arrow.down"
            }
        }

        func matches(_ meta: ReplayMeta) -> Bool {
            switch self {
            case .all: return true
            case .favorites: return meta.isFavorite
            case .mine: return meta.source == .standard || meta.source == .custom
            case .spectate: return meta.source == .spectate
            case .online: return meta.source == .online
            case .imported: return meta.source == .imported
            }
        }
    }

    /// 再生できるか（メタから分かる範囲）。
    enum Compatibility: Equatable {
        case playable, incompatible
        /// 旧版のメタで版数が写っていない（ファイルを開くまで分からない）。
        case unknown
    }

    /// 新しい順。
    static func sorted(_ replays: [ReplayMeta]) -> [ReplayMeta] {
        replays.sorted { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }
    }

    /// 絞り込み（mode が nil なら全モード）→ 新しい順。
    static func filtered(_ replays: [ReplayMeta], filter: Filter, mode: MatchMode?) -> [ReplayMeta] {
        sorted(replays.filter { filter.matches($0) && (mode == nil || $0.mode == mode) })
    }

    /// 一覧にあるモード（絞り込みメニューの候補。並びは固定）。
    static func modes(in replays: [ReplayMeta]) -> [MatchMode] {
        let order: [MatchMode] = [.standard, .ranked, .brawl, .custom, .online, .spectate]
        return order.filter { m in replays.contains { $0.mode == m } }
    }

    /// 上限の対象（お気に入り以外）の数。
    static func regularCount(_ replays: [ReplayMeta]) -> Int { replays.filter { !$0.isFavorite }.count }

    /// リプレイに対応する戦績（K/D/A 表示用）。
    static func record(for meta: ReplayMeta, in profile: Profile) -> MatchRecord? {
        profile.matchHistory.first { $0.replayID == meta.id }
    }

    static func compatibility(_ meta: ReplayMeta) -> Compatibility {
        switch meta.isPlayable {
        case true?: return .playable
        case false?: return .incompatible
        case nil: return .unknown
        }
    }

    /// リプレイ再生の観戦の初期設定（リプレイは自動カメラを既定で切る。BattleLaunch.spectatorOptions の既定に任せる）。
    static func playbackOptions(profile: Profile) -> SpectatorOptions {
        SpectatorOptions()
    }

    /// 再生用の起動パラメータを作る（読み込み済みのリプレイ。再生できる版か ReplayData.isPlayable で判定）。
    static func launch(replay: ReplayData, ownerSeat: Int?, options: SpectatorOptions = SpectatorOptions())
        -> Result<BattleLaunch, LoadError> {
        guard replay.isPlayable else { return .failure(.incompatible) }
        let seat = ownerSeat.flatMap { replay.config.players.indices.contains($0) ? $0 : nil }
            ?? ReplayArchiveService.ownerSeat(of: replay)
        return .success(BattleLaunch(config: replay.config, replay: replay, replayOwnerSeat: seat, spectatorOptions: options))
    }

    /// 保存済みのリプレイから再生用の起動パラメータを作る（同期。読み込み・復号を伴うのでテスト・メインスレッド外用）。
    static func launch(for meta: ReplayMeta, persistence: PersistenceService,
                       options: SpectatorOptions = SpectatorOptions()) -> Result<BattleLaunch, LoadError> {
        guard let data = persistence.loadReplay(meta) else { return .failure(.missing) }
        return launch(replay: data, ownerSeat: meta.ownerSeat, options: options)
    }

    /// 保存済みのリプレイをメインスレッドの外で読み込み、再生用の起動パラメータを作る。
    static func loadLaunch(for meta: ReplayMeta, persistence: PersistenceService,
                           options: SpectatorOptions = SpectatorOptions()) async -> Result<BattleLaunch, LoadError> {
        guard let data = await persistence.loadReplayAsync(meta) else { return .failure(.missing) }
        return launch(replay: data, ownerSeat: meta.ownerSeat, options: options)
    }

    /// プロフィールからリプレイを取り除く（戦績側の参照も外す）。ファイル削除は呼び出し側。
    static func remove(_ meta: ReplayMeta, from profile: inout Profile) {
        profile.replays.removeAll { $0.id == meta.id }
        for i in profile.matchHistory.indices where profile.matchHistory[i].replayID == meta.id {
            profile.matchHistory[i].replayID = nil
        }
    }

    static func resultText(_ won: Bool?, mode: MatchMode) -> (text: String, color: Color, symbol: String) {
        switch won {
        case .some(true): return (L("勝利", "Victory"), Theme.success, "checkmark.seal.fill")
        case .some(false): return (L("敗北", "Defeat"), Theme.danger, "xmark.seal.fill")
        case .none:
            return mode == .spectate ? (L("観戦", "Spectated"), Theme.cyan, "eye.fill")
                                     : (L("記録なし", "No result"), Theme.textSecondary, "minus.circle")
        }
    }

    /// 一覧・詳細の見出し（付けた名前 > 持ち主のヒーロー > 出どころ）。
    static func title(for meta: ReplayMeta, master: MasterData) -> String {
        if let name = meta.name, !name.isEmpty { return name }
        if let heroID = meta.heroID, let def = master.hero(heroID) { return MasterText.hero(def) }
        switch meta.source {
        case .online: return L("オンライン対戦", "Online Match")
        case .imported: return L("共有されたリプレイ", "Shared Replay")
        default: return L("AI 対 AI", "AI vs AI")
        }
    }

    static func sourceTag(_ source: ReplaySource) -> (text: String, symbol: String)? {
        switch source {
        case .standard, .spectate: return nil
        case .custom: return (L("カスタム", "Custom"), "slider.horizontal.3")
        case .online: return (L("オンライン", "Online"), "antenna.radiowaves.left.and.right")
        case .imported: return (L("取り込み", "Imported"), "square.and.arrow.down")
        }
    }

    /// マップ名（mode から導出）。
    static func mapName(_ mode: MatchMode) -> String { LoadingScreenView.mapName(mode) }

    /// 勝利チームの表記（色だけに頼らず名前で）。
    static func winnerText(_ winner: Team?) -> String? {
        guard let winner, winner != .neutral else { return nil }
        return L("\(LiveOpsFormat.teamName(winner))の勝利", "\(LiveOpsFormat.teamName(winner)) won")
    }

    static func storageText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct ReplayListView: View {
    @Environment(AppModel.self) private var app
    @State private var filter: ReplayLibrary.Filter = .all
    @State private var modeFilter: MatchMode?
    @State private var pendingDelete: ReplayMeta?
    @State private var confirmDeleteAll = false
    @State private var failure: (meta: ReplayMeta, error: ReplayLibrary.LoadError)?
    @State private var detail: ReplayMeta?
    /// 詳細から選んだ操作（シートが閉じ終わってから行う。閉じる途中に確認・入力の表示を重ねると出ないことがある）。
    @State private var pendingDetailAction: DetailAction?
    @State private var renaming: ReplayMeta?
    @State private var renameText = ""
    @State private var loadingID: UUID?
    @State private var importing = false
    @State private var showsImporter = false
    @State private var importError: ReplayArchiveService.ImportError?
    @State private var storageBytes: Int64?

    var body: some View {
        let all = app.profile.replays
        let replays = ReplayLibrary.filtered(all, filter: filter, mode: modeFilter)
        ScreenScaffold(title: L("リプレイ", "Replays")) {
            HStack(alignment: .top, spacing: 12) {
                infoPanel(all)
                    .frame(width: 196)
                VStack(spacing: 8) {
                    filterBar(all)
                    if replays.isEmpty {
                        Panel {
                            emptyState(all)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 8) {
                                ForEach(Array(replays.enumerated()), id: \.element.id) { index, meta in
                                    ReplayRow(meta: meta, record: ReplayLibrary.record(for: meta, in: app.profile), index: index,
                                              isLoading: loadingID == meta.id,
                                              onPlay: { play(meta) },
                                              onDetail: { detail = meta },
                                              onFavorite: { toggleFavorite(meta) },
                                              onRename: { beginRename(meta) },
                                              onDelete: { pendingDelete = meta })
                                }
                            }
                            .padding(.bottom, 8)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .overlay { if loadingID != nil || importing { loadingOverlay } }
        .allowsHitTesting(loadingID == nil && !importing)
        .sheet(item: $detail, onDismiss: runPendingDetailAction) { meta in
            ReplayDetailSheet(metaID: meta.id,
                              onPlay: { m in pendingDetailAction = .play(m); detail = nil },
                              onRename: { m in pendingDetailAction = .rename(m); detail = nil },
                              onDelete: { m in pendingDetailAction = .delete(m); detail = nil })
                .environment(app)
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.velsiaReplay], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { importFile(url) }
        }
        .alert(L("リプレイの名前", "Replay Name"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(L("名前", "Name"), text: $renameText)
                .accessibilityIdentifier("replay_rename_field")
            Button(L("保存", "Save")) { commitRename() }
            Button(L("キャンセル", "Cancel"), role: .cancel) { renaming = nil }
        } message: {
            Text(L("空にすると自動の名前に戻ります（\(ReplayArchiveService.maxNameLength) 文字まで）。",
                   "Leave empty to use the automatic name (up to \(ReplayArchiveService.maxNameLength) characters)."))
        }
        .confirmationDialog(L("このリプレイを削除しますか？", "Delete this replay?"),
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { meta in
            Button(L("削除", "Delete"), role: .destructive) { delete([meta]) }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: { meta in
            Text(meta.isFavorite ? L("お気に入りのリプレイです。削除したリプレイは元に戻せません。", "This is a favorite. Deleted replays cannot be restored.")
                                 : L("削除したリプレイは元に戻せません。", "Deleted replays cannot be restored."))
        }
        .confirmationDialog(L("すべてのリプレイを削除しますか？", "Delete all replays?"), isPresented: $confirmDeleteAll,
                            titleVisibility: .visible) {
            Button(L("すべて削除", "Delete All"), role: .destructive) { delete(app.profile.replays) }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("お気に入りを含む保存済みのリプレイ \(app.profile.replays.count) 件を削除します。",
                   "This deletes all \(app.profile.replays.count) saved replays, including favorites."))
        }
        .alert(failureTitle, isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }), presenting: failure) { f in
            Button(L("削除", "Delete"), role: .destructive) { delete([f.meta]) }
            Button(L("閉じる", "Close"), role: .cancel) {}
        } message: { f in
            switch f.error {
            case .missing:
                Text(L("リプレイファイルが見つからないか破損しています。一覧から削除しますか？",
                       "The replay file is missing or damaged. Remove it from the list?"))
            case .incompatible:
                Text(L("このリプレイは別のバージョンで記録されたため、現在のバージョンでは再生できません。",
                       "This replay was recorded with a different version and can't be played in this version."))
            }
        }
        .alert(L("取り込めませんでした", "Couldn't Import"),
               isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } }), presenting: importError) { _ in
            Button(L("閉じる", "Close"), role: .cancel) {}
        } message: { e in
            Text(e.message)
        }
        .task(id: app.profile.replays.map(\.fileName)) {
            await refreshDerivedInfo()
        }
    }

    private var failureTitle: String {
        switch failure?.error {
        case .incompatible: return L("再生できないリプレイ", "Incompatible replay")
        default: return L("リプレイを読み込めません", "Can't load replay")
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView().tint(Theme.gold).controlSize(.large)
                Text(importing ? L("取り込み中…", "Importing…") : L("リプレイを読み込み中…", "Loading replay…"))
                    .font(Theme.heading(14))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.panelStroke))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("replays_loading")
        }
        .transition(.opacity)
    }

    // MARK: 左パネル

    private func infoPanel(_ all: [ReplayMeta]) -> some View {
        let regular = ReplayLibrary.regularCount(all)
        let favorites = all.count - regular
        let cap = PersistenceService.maxReplays
        return ScrollView(.vertical, showsIndicators: false) {
            Panel(padding: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    LiveOpsSectionHeader(title: L("保存数", "Saved"), symbol: "film.stack")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(regular)")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                        Text("/ \(cap)")
                            .font(Theme.heading(15))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 2)
                        Label("\(favorites)", systemImage: "star.fill")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.gold)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("保存数 \(regular) / \(cap)、お気に入り \(favorites)", "\(regular) of \(cap) saved, \(favorites) favorites"))
                    LiveOpsProgressBar(fraction: Double(regular) / Double(cap), tint: regular >= cap ? Theme.gold : Theme.cyan)
                    if let storageBytes {
                        Label(L("使用容量 \(ReplayLibrary.storageText(storageBytes))", "Storage \(ReplayLibrary.storageText(storageBytes))"),
                              systemImage: "internaldrive")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("replays_storage")
                    }
                    Text(L("最新 \(cap) 件まで保存し、超えると古いものから自動で削除します。お気に入り（★）は削除されません（\(PersistenceService.maxFavoriteReplays) 件まで）。",
                           "The latest \(cap) are kept; older ones are removed automatically. Favorites (★) are never removed (up to \(PersistenceService.maxFavoriteReplays))."))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("リプレイはこの端末内に保存されます。共有はあなたが選んだ時だけ行われます。",
                           "Replays stay on this device unless you share them."))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        FlowFX.tap(app)
                        showsImporter = true
                    } label: {
                        Label(L("ファイルから取り込む", "Import File"), systemImage: "square.and.arrow.down")
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 24)
                    }
                    .buttonStyle(LiveOpsTallButtonStyle(base: SecondaryButtonStyle()))
                    .accessibilityIdentifier("replays_import")
                    if !all.isEmpty {
                        Button(role: .destructive) {
                            confirmDeleteAll = true
                        } label: {
                            Label(L("すべて削除", "Delete All"), systemImage: "trash")
                                .foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity, minHeight: 24)
                        }
                        .buttonStyle(LiveOpsTallButtonStyle(base: SecondaryButtonStyle()))
                        .accessibilityIdentifier("replays_delete_all")
                    }
                }
            }
        }
    }

    // MARK: 絞り込み

    private func filterBar(_ all: [ReplayMeta]) -> some View {
        let modes = ReplayLibrary.modes(in: all)
        return HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ReplayLibrary.Filter.allCases, id: \.self) { f in
                        filterChip(f, count: all.filter { f.matches($0) }.count)
                    }
                }
            }
            if modes.count > 1 {
                Menu {
                    Button {
                        modeFilter = nil
                    } label: {
                        Label(L("すべてのモード", "All Modes"), systemImage: modeFilter == nil ? "checkmark" : "square.grid.2x2")
                    }
                    ForEach(modes, id: \.self) { m in
                        Button {
                            modeFilter = m
                        } label: {
                            Label(LiveOpsFormat.modeName(m), systemImage: modeFilter == m ? "checkmark" : LiveOpsFormat.modeSymbol(m))
                        }
                    }
                } label: {
                    Image(systemName: modeFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(modeFilter == nil ? Theme.textPrimary : Theme.gold)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                        .overlay(Circle().stroke(Theme.panelStroke, lineWidth: 1))
                }
                .accessibilityLabel(L("モードで絞り込む", "Filter by mode") + (modeFilter.map { "、" + LiveOpsFormat.modeName($0) } ?? ""))
                .accessibilityIdentifier("replays_mode_filter")
            }
        }
    }

    private func filterChip(_ f: ReplayLibrary.Filter, count: Int) -> some View {
        let selected = filter == f
        return Button {
            app.audio.play(.uiTap)
            filter = f
        } label: {
            HStack(spacing: 4) {
                Image(systemName: f.symbol)
                Text(f.title).lineLimit(1)
                if f != .all {
                    Text("\(count)").font(Theme.mono(11)).opacity(0.8)
                }
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Capsule().fill(selected ? AnyShapeStyle(f == .favorites ? Theme.gold : Theme.cyan)
                                                : AnyShapeStyle(Color.white.opacity(0.08))))
            .overlay(Capsule().stroke(selected ? Color.white.opacity(0.5) : Theme.panelStroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(f.title) \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("replays_filter_\(f.rawValue)")
    }

    @ViewBuilder
    private func emptyState(_ all: [ReplayMeta]) -> some View {
        if all.isEmpty {
            LiveOpsEmptyState(symbol: "film.stack",
                              title: L("保存されたリプレイはありません", "No saved replays"),
                              message: L("対戦や AI 同士の観戦を最後まで終えると、自動でリプレイが保存されます。共有された .vreplay ファイルも取り込めます。",
                                         "Replays are saved automatically when a match or AI spectate finishes. You can also import shared .vreplay files."))
        } else {
            LiveOpsEmptyState(symbol: "line.3.horizontal.decrease.circle",
                              title: L("該当するリプレイはありません", "No matching replays"),
                              message: L("絞り込みを変えてください。", "Try a different filter."))
        }
    }

    // MARK: 操作

    private func play(_ meta: ReplayMeta) {
        guard loadingID == nil else { return }
        loadingID = meta.id
        let options = ReplayLibrary.playbackOptions(profile: app.profile)
        Task { @MainActor in
            let result = await ReplayLibrary.loadLaunch(for: meta, persistence: app.persistence, options: options)
            loadingID = nil
            switch result {
            case .success(let launch):
                app.audio.play(.uiConfirm)
                app.startBattle(launch)
            case .failure(let error):
                app.audio.play(.uiError)
                failure = (meta, error)
                if error == .incompatible { await refreshDerivedInfo() }
            }
        }
    }

    /// 詳細シートから選んだ操作。
    private enum DetailAction {
        case play(ReplayMeta), rename(ReplayMeta), delete(ReplayMeta)
    }

    private func runPendingDetailAction() {
        guard let action = pendingDetailAction else { return }
        pendingDetailAction = nil
        switch action {
        case .play(let meta): play(meta)
        case .rename(let meta): beginRename(meta)
        case .delete(let meta): pendingDelete = meta
        }
    }

    private func toggleFavorite(_ meta: ReplayMeta) {
        var p = app.profile
        switch ReplayArchiveService.toggleFavorite(id: meta.id, profile: &p, persistence: app.persistence) {
        case .changed(let on):
            app.profile = p
            app.haptics.tap()
            app.showToast(on ? L("お気に入りに追加しました（自動で削除されません）", "Added to favorites (won't be removed automatically)")
                             : L("お気に入りから外しました", "Removed from favorites"))
        case .limitReached:
            FlowFX.error(app)
            app.showToast(L("お気に入りは \(PersistenceService.maxFavoriteReplays) 件までです", "Up to \(PersistenceService.maxFavoriteReplays) favorites"))
        case .notFound:
            break
        }
    }

    private func beginRename(_ meta: ReplayMeta) {
        renameText = meta.name ?? ""
        renaming = meta
    }

    private func commitRename() {
        guard let meta = renaming else { return }
        renaming = nil
        var p = app.profile
        ReplayArchiveService.rename(id: meta.id, to: renameText, profile: &p)
        app.profile = p
        app.haptics.tap()
    }

    private func importFile(_ url: URL) {
        guard !importing else { return }
        importing = true
        Task { @MainActor in
            let result = await ReplayArchiveService.importReplay(from: url, app: app)
            importing = false
            switch result {
            case .success:
                FlowFX.confirm(app)
                filter = .all
                modeFilter = nil
                app.showToast(L("リプレイを取り込みました", "Replay imported"))
            case .failure(let e):
                FlowFX.error(app)
                importError = e
            }
        }
    }

    private func delete(_ metas: [ReplayMeta]) {
        guard !metas.isEmpty else { return }
        var p = app.profile
        for meta in metas {
            app.persistence.deleteReplay(meta)
            ReplayLibrary.remove(meta, from: &p)
        }
        app.profile = p
        app.haptics.tap()
        app.showToast(metas.count == 1 ? L("リプレイを削除しました", "Replay deleted")
                                       : L("\(metas.count) 件のリプレイを削除しました", "Deleted \(metas.count) replays"))
    }

    /// 旧版のメタの版数の補完と使用容量（どちらもメインスレッドの外）。
    private func refreshDerivedInfo() async {
        let updates = await ReplayArchiveService.backfillAsync(app.profile.replays, persistence: app.persistence)
        if !updates.isEmpty {
            var p = app.profile
            ReplayArchiveService.applyBackfill(updates, to: &p)
            app.profile = p
        }
        storageBytes = await app.persistence.replayStorageBytesAsync()
    }
}

private struct ReplayRow: View {
    let meta: ReplayMeta
    let record: MatchRecord?
    let index: Int
    let isLoading: Bool
    let onPlay: () -> Void
    let onDetail: () -> Void
    let onFavorite: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let compat = ReplayLibrary.compatibility(meta)
        let unplayable = compat == .incompatible
        let title = ReplayLibrary.title(for: meta, master: app.master)
        HStack(spacing: 10) {
            Button(action: onDetail) {
                HStack(spacing: 10) {
                    leading
                    info(title: title, unplayable: unplayable)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title)、\(LiveOpsFormat.modeName(meta.mode))、\(LiveOpsFormat.dateTime(meta.date))"
                                + (unplayable ? L("、再生できません", ", can't be played") : ""))
            .accessibilityHint(L("詳細を開く", "Opens details"))
            .accessibilityIdentifier("replay_row_\(index)")
            favoriteButton
            if unplayable {
                Image(systemName: "nosign")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(L("再生できません", "Can't be played"))
                    .accessibilityIdentifier("replay_play_\(index)")
            } else {
                // 狭い画面でも見出しを削らないよう、再生は丸いアイコンのボタン（44pt）
                Button(action: onPlay) {
                    Group {
                        if isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "play.fill").font(.system(size: 18, weight: .heavy))
                        }
                    }
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(LinearGradient(colors: [Theme.cyan, Theme.cyan.opacity(0.75)], startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                    .shadow(color: Theme.cyan.opacity(0.4), radius: 5)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("replay_play_\(index)")
                .accessibilityLabel("\(L("再生", "Play")) \(title) \(LiveOpsFormat.dateTime(meta.date))")
            }
            moreMenu
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(unplayable ? 0.025 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(meta.isFavorite ? Theme.gold.opacity(0.55) : Theme.panelStroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var leading: some View {
        if let heroID = meta.heroID {
            HeroPortraitView(heroID: heroID, size: 44)
        } else {
            Image(systemName: meta.source == .imported ? "square.and.arrow.down" : LiveOpsFormat.modeSymbol(meta.mode))
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.cyan)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cyan.opacity(0.12)))
        }
    }

    private func info(title: String, unplayable: Bool) -> some View {
        let result = ReplayLibrary.resultText(meta.won, mode: meta.mode)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(Theme.heading(14))
                    .foregroundStyle(unplayable ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
                LiveOpsTag(text: LiveOpsFormat.modeName(meta.mode), symbol: LiveOpsFormat.modeSymbol(meta.mode), color: Theme.cyan)
                    .fixedSize()
                if let tag = ReplayLibrary.sourceTag(meta.source) {
                    LiveOpsTag(text: tag.text, symbol: tag.symbol, color: Theme.textSecondary)
                        .fixedSize()
                }
            }
            HStack(spacing: 8) {
                if meta.won != nil {
                    Label(result.text, systemImage: result.symbol)
                        .font(Theme.heading(12))
                        .foregroundStyle(result.color)
                } else if let w = ReplayLibrary.winnerText(meta.winner) {
                    Label(w, systemImage: LiveOpsFormat.teamSymbol(meta.winner ?? .blue))
                        .font(Theme.heading(12))
                        .foregroundStyle(Theme.teamColor(meta.winner ?? .blue, colorblind: app.profile.settings.colorblindMode))
                }
                Label(LiveOpsFormat.duration(meta.duration), systemImage: "timer")
                if let record {
                    Text("\(record.kills) / \(record.deaths) / \(record.assists)")
                        .accessibilityLabel(L("キル \(record.kills) デス \(record.deaths) アシスト \(record.assists)",
                                              "Kills \(record.kills) deaths \(record.deaths) assists \(record.assists)"))
                }
            }
            .font(Theme.mono(12))
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
            .lineLimit(1)
            HStack(spacing: 6) {
                Text(LiveOpsFormat.dateTime(meta.date))
                if unplayable {
                    Text(L("別バージョンのため再生不可", "Other version · can't play"))
                        .foregroundStyle(Theme.danger)
                        .accessibilityIdentifier("replay_incompatible_\(index)")
                }
            }
            .font(Theme.body(11))
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private var favoriteButton: some View {
        Button(action: onFavorite) {
            Image(systemName: meta.isFavorite ? "star.fill" : "star")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(meta.isFavorite ? Theme.gold : Theme.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(meta.isFavorite ? L("お気に入りから外す", "Remove from favorites") : L("お気に入りに追加", "Add to favorites"))
        .accessibilityAddTraits(meta.isFavorite ? .isSelected : [])
        .accessibilityIdentifier("replay_favorite_\(index)")
    }

    private var moreMenu: some View {
        Menu {
            Button(action: onDetail) { Label(L("詳細", "Details"), systemImage: "info.circle") }
            Button(action: onRename) { Label(L("名前を変更", "Rename"), systemImage: "pencil") }
            if let item = ReplayShareItem(meta: meta, persistence: app.persistence) {
                ShareLink(item: item, preview: SharePreview(ReplayLibrary.title(for: meta, master: app.master),
                                                            image: Image(systemName: "play.rectangle.fill"))) {
                    Label(L("共有（書き出し）", "Share (Export)"), systemImage: "square.and.arrow.up")
                }
            }
            Button(role: .destructive, action: onDelete) { Label(L("削除", "Delete"), systemImage: "trash") }
                .accessibilityIdentifier("replay_delete_\(index)")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .overlay(Circle().stroke(Theme.panelStroke, lineWidth: 1))
                .contentShape(Circle())
        }
        .accessibilityLabel(L("その他の操作", "More actions"))
        .accessibilityIdentifier("replay_more_\(index)")
    }
}

// MARK: - 詳細

/// リプレイの詳細（成績表・試合の情報・操作）。成績は戦績の記録か、無ければファイルから読む（メインスレッドの外）。
struct ReplayDetailSheet: View {
    let metaID: UUID
    let onPlay: (ReplayMeta) -> Void
    let onRename: (ReplayMeta) -> Void
    let onDelete: (ReplayMeta) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: ReplayData?
    @State private var loadFailed = false

    private var meta: ReplayMeta? { app.profile.replays.first { $0.id == metaID } }

    var body: some View {
        ZStack {
            StarfieldBackground()
            if let meta {
                VStack(spacing: 10) {
                    header(meta)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            facts(meta)
                            if let summary = ReplayLibrary.record(for: meta, in: app.profile)?.summary ?? loaded?.summary {
                                MatchScoreTable(summary: summary)
                            } else if loadFailed {
                                FlowEmptyState(symbol: "exclamationmark.triangle",
                                               title: L("リプレイを読み込めません", "Can't load replay"),
                                               message: L("ファイルが見つからないか破損しています。", "The file is missing or damaged."))
                            } else if loaded == nil {
                                ProgressView().tint(Theme.gold).frame(maxWidth: .infinity, minHeight: 120)
                            } else {
                                FlowEmptyState(symbol: "tablecells", title: L("成績の記録はありません", "No score data"),
                                               message: L("このリプレイには結果が記録されていません。", "This replay has no recorded result."))
                            }
                        }
                        .padding(.bottom, 10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .task(id: meta.fileName) {
                    guard ReplayLibrary.record(for: meta, in: app.profile)?.summary == nil else { return }
                    loaded = await app.persistence.loadReplayAsync(meta)
                    loadFailed = loaded == nil
                }
            } else {
                // 削除などで一覧から消えた
                Color.clear.onAppear { dismiss() }
            }
            ToastOverlay()
        }
        .preferredColorScheme(.dark)
    }

    private func header(_ meta: ReplayMeta) -> some View {
        let unplayable = ReplayLibrary.compatibility(meta) == .incompatible
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ReplayLibrary.title(for: meta, master: app.master))
                    .font(Theme.title(20))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(LiveOpsFormat.modeName(meta.mode)) · \(ReplayLibrary.mapName(meta.mode)) · \(LiveOpsFormat.duration(meta.duration))")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            LiveOpsIconButton(symbol: meta.isFavorite ? "star.fill" : "star",
                              label: meta.isFavorite ? L("お気に入りから外す", "Remove from favorites") : L("お気に入りに追加", "Add to favorites"),
                              tint: meta.isFavorite ? Theme.gold : Theme.textPrimary, identifier: "replay_detail_favorite") {
                toggleFavorite(meta)
            }
            LiveOpsIconButton(symbol: "pencil", label: L("名前を変更", "Rename"), identifier: "replay_detail_rename") {
                onRename(meta)
            }
            if let item = ReplayShareItem(meta: meta, persistence: app.persistence) {
                ShareLink(item: item, preview: SharePreview(ReplayLibrary.title(for: meta, master: app.master),
                                                            image: Image(systemName: "play.rectangle.fill"))) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                        .overlay(Circle().stroke(Theme.panelStroke, lineWidth: 1))
                }
                .accessibilityLabel(L("共有（書き出し）", "Share (Export)"))
                .accessibilityIdentifier("replay_detail_share")
            }
            LiveOpsIconButton(symbol: "trash", label: L("削除", "Delete"), tint: Theme.danger, identifier: "replay_detail_delete") {
                onDelete(meta)
            }
            Button {
                FlowFX.confirm(app)
                onPlay(meta)
            } label: {
                Label(L("再生", "Play"), systemImage: "play.fill").fixedSize()
            }
            .buttonStyle(LiveOpsCompactButtonStyle(color: Theme.cyan))
            .disabled(unplayable)
            .opacity(unplayable ? 0.45 : 1)
            .accessibilityIdentifier("replay_detail_play")
            FlowCloseButton(identifier: "replay_detail_close") { dismiss() }
        }
    }

    /// 試合の情報（日時・勝敗・シード・版数・持ち主・年表の件数）。
    private func facts(_ meta: ReplayMeta) -> some View {
        let compat = ReplayLibrary.compatibility(meta)
        let timeline = loaded?.timeline
        return LiveOpsFlowLayout(spacing: 6, lineSpacing: 6) {
            fact("calendar", LiveOpsFormat.dateTime(meta.date))
            if let w = ReplayLibrary.winnerText(meta.winner ?? loaded?.summary?.winner) {
                fact(LiveOpsFormat.teamSymbol(meta.winner ?? loaded?.summary?.winner ?? .blue), w, tint: Theme.gold)
            }
            if let seed = meta.seed ?? loaded?.config.seed {
                fact("number", L("シード \(SpectateSetup.seedLabel(seed))", "Seed \(SpectateSetup.seedLabel(seed))"))
            }
            if let owner = meta.ownerSeat, let heroID = meta.heroIDs?[safe: owner] ?? meta.heroID,
               let def = app.master.hero(heroID) {
                fact("person.fill", L("視点: \(MasterText.hero(def))", "Owner: \(MasterText.hero(def))"))
            }
            if let timeline {
                let kills = timeline.events.filter { if case .kill = $0.kind { return true } else { return false } }.count
                let towers = timeline.events.filter { if case .structure = $0.kind { return true } else { return false } }.count
                fact("scope", L("キル \(kills)", "\(kills) kills"))
                fact("building.columns.fill", L("建物 \(towers)", "\(towers) structures"))
            }
            switch compat {
            case .playable:
                fact("checkmark.circle.fill", L("このバージョンで再生できます", "Playable in this version"), tint: Theme.success)
            case .incompatible:
                fact("nosign", L("別のバージョンで記録されたため再生できません", "Recorded with another version; can't be played"), tint: Theme.danger)
            case .unknown:
                fact("questionmark.circle", L("版数を確認中", "Checking version"))
            }
        }
    }

    private func fact(_ symbol: String, _ text: String, tint: Color = Theme.textSecondary) -> some View {
        Label(text, systemImage: symbol)
            .font(Theme.body(12))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Theme.panelStroke, lineWidth: 0.5))
    }

    private func toggleFavorite(_ meta: ReplayMeta) {
        var p = app.profile
        switch ReplayArchiveService.toggleFavorite(id: meta.id, profile: &p, persistence: app.persistence) {
        case .changed:
            app.profile = p
            app.haptics.tap()
        case .limitReached:
            FlowFX.error(app)
            app.showToast(L("お気に入りは \(PersistenceService.maxFavoriteReplays) 件までです", "Up to \(PersistenceService.maxFavoriteReplays) favorites"))
        case .notFound:
            break
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
