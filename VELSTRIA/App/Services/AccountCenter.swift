import Foundation

// 担当: outgame。アカウントの操作（プロフィール > アカウント の画面と、試合の後・アプリを閉じた時の自動保存）。
// 通信は CloudAccountAPI、端末の写しは Profile.account。使えるのはオンライン機能のルールに同意した 13 歳以上だけ（AppModel.syncsCloudRank）。

@Observable
@MainActor
final class AccountCenter {
    enum Busy: Equatable { case password, save, gameCenter, login, erase }

    enum Failure: Error, Equatable {
        case api(CloudAccountAPI.Failure)
        case gameCenter(GameCenterAuth.Failure)
        /// オンライン機能のルールに同意していない（または 13 歳未満）。
        case notAllowed
        /// プロフィールを預ける形にできなかった・取り出した物を読めなかった。
        case unreadable

        var message: String {
            switch self {
            case .api(let f): return f.message
            case .gameCenter(let f): return f.message
            case .notAllowed: return L("オンライン機能のルールに同意すると使えます", "Agree to the online rules to use this")
            case .unreadable: return L("データを読み書きできませんでした", "Couldn't read or write the data")
            }
        }
    }

    /// 通信中の操作（画面の待ち表示。同時に 1 つだけ）。
    private(set) var busy: Busy?
    /// 中継の最新の状態（まだ取れていなければ nil）。
    private(set) var info: CloudAccountInfo?
    /// 中継がまだアカウントに対応していない（古い版。404 not_found）。
    private(set) var unsupported = false
    @ObservationIgnored private var refreshing = false

    @ObservationIgnored weak var host: AppModel?
    /// 通信の送り手（テストは差し替える）。
    @ObservationIgnored var transport: CloudAccountAPI.Transport = FriendInboxEraser.urlSession
    @ObservationIgnored private var lastAutoSave: Date?
    /// 自動保存の間隔（試合が続いても 10 分に 1 回まで）。
    static let autoSaveInterval: TimeInterval = 10 * 60

    var isAllowed: Bool { host?.syncsCloudRank ?? false }

    private var identity: (code: String, key: String)? {
        guard let p = host?.profile, FriendCode.isValid(p.friendCode), FriendInboxKey.isValid(p.inboxKey) else { return nil }
        return (p.friendCode, p.inboxKey)
    }

    // MARK: 状態

    /// 中継の状態を取り直す（画面を開いた時・起動時）。
    /// 画面の操作は止めない（busy にしない）。取り直しは同時に 1 つだけ。
    func refresh() async {
        guard isAllowed, let id = identity, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        switch await CloudAccountAPI.status(code: id.code, key: id.key, transport: transport) {
        case .success(let i): adopt(i, code: id.code)
        case .failure(.unsupported): unsupported = true
        case .failure: break
        }
    }

    /// 中継の状態を端末の写しへ（待っている間に別のアカウントへ変わっていたら何もしない）。
    private func adopt(_ i: CloudAccountInfo, code: String) {
        guard let host, host.profile.friendCode == code else { return }
        info = i
        unsupported = false
        var a = host.profile.account
        a.hasPassword = i.password
        if !i.gameCenter {
            a.gameCenterAlias = nil
        } else if a.gameCenterAlias == nil {
            a.gameCenterAlias = GameCenterAuth.current?.alias ?? "Game Center"
        }
        a.lastCloudSave = i.savedDate
        var p = host.profile
        p.account = a
        // 中継にこのコードのデータができた（全データの削除で中継のアカウントも消す。FriendHub.hasServerData）
        p.inboxRegistered = true
        if p != host.profile { host.profile = p }
    }

    // MARK: パスワード・クラウド保存

    /// パスワードを設定し、続けて今のデータを預ける（別の端末でログインできるように）。
    func setPassword(_ password: String) async -> Result<Void, Failure> {
        guard isAllowed, let id = identity else { return .failure(.notAllowed) }
        guard let verifier = AccountPassword.verifier(code: id.code, password: password) else { return .failure(.unreadable) }
        busy = .password
        defer { busy = nil }
        switch await CloudAccountAPI.setPassword(code: id.code, key: id.key, verifier: verifier, transport: transport) {
        case .success(let i):
            adopt(i, code: id.code)
            return await upload(id)
        case .failure(let f):
            return .failure(.api(f))
        }
    }

    /// 今すぐ預ける。
    @discardableResult
    func saveNow() async -> Result<Void, Failure> {
        guard isAllowed, let id = identity else { return .failure(.notAllowed) }
        guard busy == nil else { return .success(()) }
        busy = .save
        defer { busy = nil }
        return await upload(id)
    }

    private func upload(_ id: (code: String, key: String)) async -> Result<Void, Failure> {
        guard let host else { return .failure(.notAllowed) }
        let now = Date()
        var snapshot = host.profile
        snapshot.account.lastCloudSave = now
        guard let json = try? PersistenceService.makeEncoder().encode(snapshot),
              let data = CloudProfileCodec.encode(json: json) else { return .failure(.unreadable) }
        lastAutoSave = now
        switch await CloudAccountAPI.save(code: id.code, key: id.key, data: data, savedAt: now, transport: transport) {
        case .success(let i):
            adopt(i, code: id.code)
            return .success(())
        case .failure(let f):
            if f == .unsupported { unsupported = true }
            return .failure(.api(f))
        }
    }

    /// 自動保存（試合の後・アプリを閉じた時）: ほかの端末で取り出せるアカウント（パスワードか Game Center がある）だけ、10 分に 1 回まで。
    func autoSave(now: Date = Date()) {
        guard isAllowed, let host, host.profile.account.isRecoverable, busy == nil, let id = identity else { return }
        if let last = lastAutoSave, now.timeIntervalSince(last) < Self.autoSaveInterval { return }
        lastAutoSave = now
        Task { _ = await upload(id) }
    }

    // MARK: Game Center

    /// Game Center にサインインして、このアカウントに連携する（続けて今のデータを預ける）。
    func linkGameCenter() async -> Result<Void, Failure> {
        guard isAllowed, let id = identity else { return .failure(.notAllowed) }
        busy = .gameCenter
        defer { busy = nil }
        let player: GameCenterAuth.Player
        switch await GameCenterAuth.authenticate() {
        case .success(let p): player = p
        case .failure(let f): return .failure(.gameCenter(f))
        }
        let proof: GameCenterProof
        switch await GameCenterAuth.proof() {
        case .success(let p): proof = p
        case .failure(let f): return .failure(.gameCenter(f))
        }
        switch await CloudAccountAPI.linkGameCenter(code: id.code, key: id.key, proof: proof, transport: transport) {
        case .success(let i):
            if host?.profile.friendCode == id.code { host?.profile.account.gameCenterAlias = player.alias }
            adopt(i, code: id.code)
            return await upload(id)
        case .failure(let f):
            return .failure(.api(f))
        }
    }

    func unlinkGameCenter() async -> Result<Void, Failure> {
        guard isAllowed, let id = identity else { return .failure(.notAllowed) }
        busy = .gameCenter
        defer { busy = nil }
        switch await CloudAccountAPI.unlinkGameCenter(code: id.code, key: id.key, transport: transport) {
        case .success(let i):
            if host?.profile.friendCode == id.code { host?.profile.account.gameCenterAlias = nil }
            adopt(i, code: id.code)
            return .success(())
        case .failure(let f):
            return .failure(.api(f))
        }
    }

    // MARK: アカウント切替

    /// アカウント ID + パスワードで、別のアカウントのデータを取り出す（まだ切り替えない）。
    func download(code: String, password: String) async -> Result<CloudAccountDownload, Failure> {
        guard isAllowed else { return .failure(.notAllowed) }
        busy = .login
        defer { busy = nil }
        return await CloudAccountAPI.login(code: code, password: password, transport: transport).mapError { Failure.api($0) }
    }

    /// Game Center で、連携したアカウントのデータを取り出す（まだ切り替えない）。
    func downloadWithGameCenter() async -> Result<CloudAccountDownload, Failure> {
        guard isAllowed else { return .failure(.notAllowed) }
        busy = .login
        defer { busy = nil }
        if case .failure(let f) = await GameCenterAuth.authenticate() { return .failure(.gameCenter(f)) }
        switch await GameCenterAuth.proof() {
        case .success(let proof):
            return await CloudAccountAPI.loginGameCenter(proof: proof, transport: transport).mapError { Failure.api($0) }
        case .failure(let f):
            return .failure(.gameCenter(f))
        }
    }

    /// 取り出したアカウントに切り替える（端末の年齢区分と購入の記録は引き継ぐ。BackupRestore.merged）。
    func switchTo(_ imported: Profile, info: CloudAccountInfo) {
        guard let host else { return }
        host.prepareForAccountSwitch()
        var p = BackupRestore.merged(imported: imported, current: host.profile)
        p.account.hasPassword = info.password
        p.account.lastCloudSave = info.savedDate
        if info.gameCenter {
            if p.account.gameCenterAlias == nil { p.account.gameCenterAlias = GameCenterAuth.current?.alias ?? "Game Center" }
        } else {
            p.account.gameCenterAlias = nil
        }
        p.inboxRegistered = true
        host.profile = p
        host.persistence.saveNow(p)
        self.info = info
        lastAutoSave = Date()
        host.afterAccountSwitch()
    }

    /// アカウントを消す（中継の預かったデータ・パスワード・Game Center の連携。端末のデータは残る）。
    func erase() async -> Result<Void, Failure> {
        guard let id = identity else { return .failure(.notAllowed) }
        busy = .erase
        defer { busy = nil }
        guard await CloudAccountAPI.erase(code: id.code, key: id.key, transport: transport) else { return .failure(.api(.offline)) }
        if host?.profile.friendCode == id.code { host?.profile.account = AccountLinkState() }
        info = nil
        return .success(())
    }
}
