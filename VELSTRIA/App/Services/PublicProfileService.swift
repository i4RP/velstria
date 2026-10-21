import Foundation
import Observation

// 担当: outgame（第3段）。公開の名刺の読み書き（relay の Directory）。型は PublicProfileModels.swift。
// TODO(第3段 relay 担当): 通信・キャッシュ・自分の名刺の送信を実装する（今は空の殻。画面の担当はこの形に合わせて作る）。

@MainActor
@Observable
final class PublicProfileService {
    /// 取ってきた名刺（フレンドコード → 名刺）。画面はこれを見る。
    private(set) var profiles: [String: PublicProfile] = [:]

    /// まとめて取る（100 件まで。新しいキャッシュがあれば通信しない。force で取り直す）。同意していない・オフラインなら何もしない。
    func load(_ codes: [String], force: Bool = false) async {}

    /// 自分の名刺を送る（オンラインに同意している時だけ。前に送った中身から変わった時だけ）。
    func publishOwn() async {}
}

@MainActor
@Observable
final class RankingService {
    /// 範囲ごとの直近のページ。
    private(set) var pages: [RankingScope: RankingPage] = [:]
    /// 読み込み中の範囲。
    private(set) var loading: Set<RankingScope> = []
    /// 直近の失敗（利用者向けの文。成功したら nil）。
    private(set) var lastError: String?

    /// 取る（新しいページがあれば通信しない。force で取り直す）。
    func load(_ scope: RankingScope, force: Bool = false) async {}
}
