import CoreGraphics
import Foundation
import os
import VelstriaCore

// 担当: battle-renderer（ステージ）。ステージの CPU 側の準備（素材の読み込み・配置・配合マップ）を背景スレッドで行い、
// MapScene（main actor）が受け取る。BattleRenderer.startLoading が読み込み中に prepare を呼んでおき、
// MapScene.init が take で取り出す（無ければその場で作る）。

/// 1 試合分のステージの CPU 側データ。
enum StagePlan: @unchecked Sendable {
    case procedural(ProceduralStagePlan)
    case canyon(CanyonStagePlan)
}

struct ProceduralStagePlan: @unchecked Sendable {
    let assets: StageAssets
    let maps: StageSplat.Maps
    let layout: StageLayoutResult
    let quality: RenderQuality
}

enum StagePrep {
    private static let lock = NSLock()
    /// 取っておく計画は 1 つだけ（頂点の配列は数十 MB になる。読み込みを途中でやめた試合の分を溜めない）。
    nonisolated(unsafe) private static var ready: (key: String, plan: StagePlan)?

    private static func key(_ map: MapDefinition, _ q: RenderQuality, _ set: StageArtSet) -> String {
        "\(map.stageID ?? "procedural")-\(map.hashValue)-\(map.size)-\(map.obstacles.count)-\(map.brushes.count)-\(q.level.rawValue)-\(q.decorationDensity)-\(lite)-\(set.rawValue)"
    }

    /// 計画を作って取っておく（背景スレッドから呼ぶ）。作れたら true（素材やシェーダーが欠けていれば false）。
    @discardableResult
    static func prepare(map: MapDefinition, quality: RenderQuality, set: StageArtSet = .current) -> Bool {
        let k = key(map, quality, set)
        lock.lock()
        let has = ready?.key == k
        lock.unlock()
        if has { return true }
        guard let plan = make(map: map, quality: quality, set: set) else { return false }
        lock.lock()
        ready = (k, plan)
        lock.unlock()
        return true
    }

    /// 取っておいた計画を取り出す（取り出した後は保持しない）。無ければその場で作る。
    static func take(map: MapDefinition, quality: RenderQuality, set: StageArtSet = .current) -> StagePlan? {
        let k = key(map, quality, set)
        lock.lock()
        let plan = ready?.key == k ? ready?.plan : nil
        ready = nil
        lock.unlock()
        return plan ?? make(map: map, quality: quality, set: set)
    }

    nonisolated(unsafe) private static var inflight: (key: String, task: Task<Bool, Never>)?

    /// 背景で準備を始める（ロード画面から。準備済み・準備中なら何もしない）。
    static func prefetch(map: MapDefinition, quality: RenderQuality, set: StageArtSet = .current) {
        _ = task(map: map, quality: quality, set: set)
    }

    /// 準備が終わるまで待つ（準備中ならその完了、無ければ背景で作る）。作れたら true。
    static func ready(map: MapDefinition, quality: RenderQuality, set: StageArtSet = .current) async -> Bool {
        await task(map: map, quality: quality, set: set).value
    }

    private static func task(map: MapDefinition, quality: RenderQuality, set: StageArtSet) -> Task<Bool, Never> {
        let k = key(map, quality, set)
        lock.lock()
        defer { lock.unlock() }
        if ready?.key == k { return Task { true } }
        if let f = inflight, f.key == k { return f.task }
        let t = Task.detached(priority: .userInitiated) { () -> Bool in
            let ok = prepare(map: map, quality: quality, set: set)
            lock.lock()
            if inflight?.key == k { inflight = nil }
            lock.unlock()
            return ok
        }
        inflight = (k, t)
        return t
    }

    /// 取っておいた計画を捨てる（読み込みを途中でやめたとき）。
    static func discard() {
        lock.lock()
        ready = nil
        lock.unlock()
    }

    static let log = Logger(subsystem: "com.bitcoinpay.velstria", category: "stage")

    /// テスト（DEBUG の -uiTesting の UI テストと、単体テストのホスト）では小物を減らして軽くする。CI のシミュレータは遅く、
    /// UI テストが HUD を待つ時間・単体テストの所要時間に響く（配置の規則と面数は StageTests が本来の密度で直接確かめる）。
    /// 見た目の確認で -uiTesting を使うときは -stageFull で通常どおりにする。
    static var lite: Bool {
        #if DEBUG
        let p = ProcessInfo.processInfo
        if p.arguments.contains("-stageFull") { return false }
        return DebugLaunch.isUITesting || p.environment["XCTestConfigurationFilePath"] != nil
        #else
        return false
        #endif
    }

    static func make(map: MapDefinition, quality: RenderQuality, set: StageArtSet = .current) -> StagePlan? {
        if map.stageID == "canyon" {
            return CanyonStagePlan.load(map: map, quality: quality).map(StagePlan.canyon)
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        guard let assets = StageAssets.load(set: set) else {
            log.error("stage assets unavailable; falling back to procedural terrain")
            return nil
        }
        let t1 = CFAbsoluteTimeGetCurrent()
        let lite = lite
        let density = lite ? min(0.3, quality.decorationDensity) : quality.decorationDensity
        let layout = StageLayout.build(map: map, props: assets.props, density: density, level: lite ? .low : quality.level,
                                       lite: lite, sanctuary: assets.sanctuary, fieldProps: assets.fieldProps)
        let t2 = CFAbsoluteTimeGetCurrent()
        guard let maps = StageSplat.make(map: map, shades: layout.shades, controlSize: lite ? 512 : 1024,
                                         auxSize: lite ? 256 : 512, set: set) else { return nil }
        let t3 = CFAbsoluteTimeGetCurrent()
        let brushTris = layout.brushes.reduce(0) { $0 + $1.triangleCount }
        log.notice("""
            stage prep (\(set.rawValue)): assets \(Int((t1 - t0) * 1000))ms layout \(Int((t2 - t1) * 1000))ms splat \(Int((t3 - t2) * 1000))ms \
            tris chunks \(layout.chunks.triangleCount) brushes \(brushTris) \
            props \(layout.counts.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: " "))
            """)
        return .procedural(ProceduralStagePlan(assets: assets, maps: maps, layout: layout, quality: quality))
    }
}
