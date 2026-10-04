import Foundation
import os

// 担当: battle-renderer（性能）。戦闘の「プレイ中にアセットを作らない」規律を数値で検査する台帳。
//
// AAA タイトルの作り方と同じく、メッシュ・マテリアル・テクスチャ・エンティティ・粒子放出体は読み込み幕の裏で
// 作り切り、幕が上がった後（live）は使い回すだけにする。各キャッシュの「初回生成」の箇所が record を呼び、
// live 中に記録されたものはヒッチ（初回のメッシュ生成・シェーダーのコンパイル）の候補として PerfRun とテストに出る。
// 記録は件数の加算だけ（ラベルは live 中の先頭 64 件だけ評価する）なので、出荷ビルドでも常に有効。

enum AssetLedger {
    enum Kind: String, CaseIterable, Codable, Sendable {
        /// MeshResource の生成（MeshBuilder・generateText 以外の generate*）。
        case mesh
        /// MeshResource.generateText（CoreText の分割・テッセレーション）。
        case textMesh
        /// マテリアルの生成（キャッシュの初回）。
        case material
        /// TextureResource の生成・更新。
        case texture
        /// プール・表示物のエンティティ生成。
        case entity
        /// ParticleEmitterComponent の構築。
        case emitter
    }

    enum Phase: String, Codable, Sendable {
        /// 戦闘外（メニュー・ヒーロー詳細など）。
        case idle
        /// 読み込み幕の裏（ここでの生成は想定どおり）。
        case loading
        /// 幕が上がった後（ここでの生成は戦闘中のヒッチ候補）。
        case live
    }

    struct Snapshot: Codable, Sendable, Equatable {
        var phase: Phase
        var loading: [String: Int]
        var live: [String: Int]
        /// live 中の生成の先頭 64 件（"kind: ラベル @ 経過秒"）。
        var liveSamples: [String]
        var liveTotal: Int { live.values.reduce(0, +) }
    }

    private struct State {
        var phase: Phase = .idle
        var loading: [Kind: Int] = [:]
        var live: [Kind: Int] = [:]
        var liveSamples: [String] = []
        var liveStart: Double = 0
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    static let maxSamples = 64

    /// 読み込み開始（件数を 0 に戻す）。
    static func beginLoading() {
        state.withLock { $0 = State(phase: .loading) }
    }

    /// 幕が上がった（ここから先の生成は live として数える）。
    static func beginLive() {
        let now = ProcessInfo.processInfo.systemUptime
        state.withLock {
            $0.phase = .live
            $0.liveStart = now
        }
    }

    /// 戦闘を抜けた。
    static func end() {
        state.withLock { $0.phase = .idle }
    }

    /// 生成を 1 件記録する。label は live 中の先頭 maxSamples 件だけ評価する。
    static func record(_ kind: Kind, _ label: @autoclosure () -> String) {
        let needsLabel = state.withLock { s -> Bool in
            switch s.phase {
            case .idle: return false
            case .loading:
                s.loading[kind, default: 0] += 1
                return false
            case .live:
                s.live[kind, default: 0] += 1
                return s.liveSamples.count < maxSamples
            }
        }
        guard needsLabel else { return }
        let text = label()
        let now = ProcessInfo.processInfo.systemUptime
        state.withLock { s in
            guard s.liveSamples.count < maxSamples else { return }
            s.liveSamples.append(String(format: "%@: %@ @ %.1fs", kind.rawValue, text, now - s.liveStart))
        }
    }

    static func snapshot() -> Snapshot {
        state.withLock { s in
            Snapshot(phase: s.phase,
                     loading: Dictionary(uniqueKeysWithValues: s.loading.map { ($0.key.rawValue, $0.value) }),
                     live: Dictionary(uniqueKeysWithValues: s.live.map { ($0.key.rawValue, $0.value) }),
                     liveSamples: s.liveSamples)
        }
    }
}
