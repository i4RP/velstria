import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI035 リプレイ一覧（再生・削除）。

enum ReplayLibrary {
    /// 端末に保持するリプレイの上限（超過分は保存時に古い順で削除される）。
    static let maxStored = 20

    enum LoadError: Error, Equatable {
        /// ファイルが見つからない・壊れている。
        case missing
        /// 記録時とシミュレーション版数が異なり再現できない。
        case incompatible
    }

    /// 新しい順。
    static func sorted(_ replays: [ReplayMeta]) -> [ReplayMeta] {
        replays.sorted { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }
    }

    /// リプレイに対応する戦績（K/D/A 表示用）。
    static func record(for meta: ReplayMeta, in profile: Profile) -> MatchRecord? {
        profile.matchHistory.first { $0.replayID == meta.id }
    }

    /// 再生用の起動パラメータを作る。
    static func launch(for meta: ReplayMeta, persistence: PersistenceService) -> Result<BattleLaunch, LoadError> {
        guard let data = persistence.loadReplay(meta) else { return .failure(.missing) }
        guard data.config.simVersion == MatchConfig.currentSimVersion else { return .failure(.incompatible) }
        return .success(BattleLaunch(config: data.config, replay: data))
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
}

struct ReplayListView: View {
    @Environment(AppModel.self) private var app
    @State private var pendingDelete: ReplayMeta?
    @State private var confirmDeleteAll = false
    @State private var failure: (meta: ReplayMeta, error: ReplayLibrary.LoadError)?

    var body: some View {
        let replays = ReplayLibrary.sorted(app.profile.replays)
        ScreenScaffold(title: L("リプレイ", "Replays")) {
            HStack(alignment: .top, spacing: 14) {
                infoPanel(count: replays.count)
                    .frame(width: 220)
                if replays.isEmpty {
                    Panel {
                        LiveOpsEmptyState(symbol: "film.stack",
                                          title: L("保存されたリプレイはありません", "No saved replays"),
                                          message: L("通常戦・ランク戦などの対戦を終えると、自動でリプレイが保存されます。",
                                                     "Replays are saved automatically when you finish a match."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(replays.enumerated()), id: \.element.id) { index, meta in
                                ReplayRow(meta: meta, record: ReplayLibrary.record(for: meta, in: app.profile), index: index,
                                          onPlay: { play(meta) },
                                          onDelete: { pendingDelete = meta })
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .confirmationDialog(L("このリプレイを削除しますか？", "Delete this replay?"),
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { meta in
            Button(L("削除", "Delete"), role: .destructive) { delete([meta]) }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: { _ in
            Text(L("削除したリプレイは元に戻せません。", "Deleted replays cannot be restored."))
        }
        .confirmationDialog(L("すべてのリプレイを削除しますか？", "Delete all replays?"), isPresented: $confirmDeleteAll,
                            titleVisibility: .visible) {
            Button(L("すべて削除", "Delete All"), role: .destructive) { delete(app.profile.replays) }
            Button(L("キャンセル", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("保存済みのリプレイ \(app.profile.replays.count) 件を削除します。", "This deletes \(app.profile.replays.count) saved replays."))
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
                Text(L("このリプレイは以前のバージョンで記録されたため、現在のバージョンでは再生できません。",
                       "This replay was recorded with an earlier version and can't be played in this version."))
            }
        }
    }

    private var failureTitle: String {
        switch failure?.error {
        case .incompatible: return L("再生できないリプレイ", "Incompatible replay")
        default: return L("リプレイを読み込めません", "Can't load replay")
        }
    }

    private func infoPanel(count: Int) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Panel(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    LiveOpsSectionHeader(title: L("保存数", "Saved"), symbol: "film.stack")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(count)")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                        Text("/ \(ReplayLibrary.maxStored)")
                            .font(Theme.heading(15))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("保存数 \(count) / \(ReplayLibrary.maxStored)", "\(count) of \(ReplayLibrary.maxStored) saved"))
                    LiveOpsProgressBar(fraction: Double(count) / Double(ReplayLibrary.maxStored),
                                       tint: count >= ReplayLibrary.maxStored ? Theme.gold : Theme.cyan)
                    Text(L("リプレイは最新 \(ReplayLibrary.maxStored) 件まで保存され、上限を超えると古いものから自動で削除されます。",
                           "Up to \(ReplayLibrary.maxStored) latest replays are kept; the oldest is removed automatically when the limit is exceeded."))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("リプレイはこの端末内にのみ保存されます。", "Replays are stored on this device only."))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if count > 0 {
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

    private func play(_ meta: ReplayMeta) {
        switch ReplayLibrary.launch(for: meta, persistence: app.persistence) {
        case .success(let launch):
            app.audio.play(.uiConfirm)
            app.startBattle(launch)
        case .failure(let error):
            app.audio.play(.uiError)
            failure = (meta, error)
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
}

private struct ReplayRow: View {
    let meta: ReplayMeta
    let record: MatchRecord?
    let index: Int
    let onPlay: () -> Void
    let onDelete: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let result = ReplayLibrary.resultText(meta.won, mode: meta.mode)
        let heroName = meta.heroID.flatMap { app.master.hero($0) }.map { MasterText.hero($0) }
        HStack(spacing: 12) {
            if let heroID = meta.heroID {
                HeroPortraitView(heroID: heroID, size: 48)
            } else {
                Image(systemName: LiveOpsFormat.modeSymbol(meta.mode))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.cyan)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cyan.opacity(0.12)))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(heroName ?? L("AI 対 AI", "AI vs AI"))
                        .font(Theme.heading(15))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .layoutPriority(1)
                    LiveOpsTag(text: LiveOpsFormat.modeName(meta.mode), symbol: LiveOpsFormat.modeSymbol(meta.mode), color: Theme.cyan)
                        .fixedSize()
                    if let record {
                        LiveOpsTag(text: LiveOpsFormat.difficultyName(record.difficulty), color: Theme.textSecondary)
                            .fixedSize()
                    }
                }
                HStack(spacing: 10) {
                    // 観戦は種別タグと同じ表記になるため、勝敗が無い場合は省く
                    if meta.won != nil || meta.mode != .spectate {
                        Label(result.text, systemImage: result.symbol)
                            .font(Theme.heading(12))
                            .foregroundStyle(result.color)
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
                Text(LiveOpsFormat.dateTime(meta.date))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: onPlay) {
                Label(L("再生", "Play"), systemImage: "play.fill").fixedSize()
            }
            .buttonStyle(LiveOpsCompactButtonStyle(color: Theme.cyan))
            .accessibilityIdentifier("replay_play_\(index)")
            .accessibilityLabel("\(L("再生", "Play")) \(heroName ?? LiveOpsFormat.modeName(meta.mode)) \(LiveOpsFormat.dateTime(meta.date))")
            LiveOpsIconButton(symbol: "trash", label: L("削除", "Delete"), tint: Theme.danger, identifier: "replay_delete_\(index)",
                              action: onDelete)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.panelStroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
