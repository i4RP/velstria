import Foundation
import VelstriaCore

// 担当: app-services（最小実装。デバウンス保存・バックアップ世代・破損時復旧・リプレイ上限管理を実装すること）

final class PersistenceService {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("Velstria", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: replaysDirectory, withIntermediateDirectories: true)
    }

    var profileURL: URL { directory.appendingPathComponent("profile.json") }
    var replaysDirectory: URL { directory.appendingPathComponent("replays", isDirectory: true) }

    func loadProfile() -> Profile? {
        guard let data = try? Data(contentsOf: profileURL) else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }

    /// 変更時に呼ばれる（短時間に連続しても 1 回にまとめること）。
    func scheduleSave(_ profile: Profile) {
        saveNow(profile)
    }

    func saveNow(_ profile: Profile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: profileURL, options: .atomic)
    }

    /// リプレイ保存。戻り値のメタを profile.replays に追加するのは呼び出し側（RewardService）。
    func saveReplay(_ replay: ReplayData, heroID: String?, won: Bool?, date: Date) -> ReplayMeta? {
        let meta = ReplayMeta(date: date, fileName: "\(UUID().uuidString).vreplay", mode: replay.config.mode,
                              heroID: heroID, won: won, duration: Double(replay.finalTick) * Balance.dt)
        guard let data = try? JSONEncoder().encode(replay) else { return nil }
        do {
            try data.write(to: replaysDirectory.appendingPathComponent(meta.fileName), options: .atomic)
            return meta
        } catch {
            return nil
        }
    }

    func loadReplay(_ meta: ReplayMeta) -> ReplayData? {
        guard let data = try? Data(contentsOf: replaysDirectory.appendingPathComponent(meta.fileName)) else { return nil }
        return try? JSONDecoder().decode(ReplayData.self, from: data)
    }

    func deleteReplay(_ meta: ReplayMeta) {
        try? FileManager.default.removeItem(at: replaysDirectory.appendingPathComponent(meta.fileName))
    }

    /// 全データ削除（プライバシー設定から）。
    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: replaysDirectory, withIntermediateDirectories: true)
    }
}
