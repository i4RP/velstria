import Foundation
import QuartzCore
import RealityKit
import VelstriaCore

// 担当: battle-renderer（性能）。試合の前に「作れるものは先に作る」入口（ロード画面・戦闘画面の生成時に呼ぶ）。
//
// - 地面テクスチャ（CoreGraphics。GroundTextureCache が試合をまたいで使い回す）
// - マテリアルのシェーダー（iOS 18 の PhysicallyBasedMaterial.Program / UnlitMaterial.Program を非同期に作る）
// - 後処理（ブルーム・色調整）の Metal パイプライン（PostProcessShaderCache）
// いずれも何度呼んでもよく、生成中・生成済みなら何もしない。重い処理はメインスレッドの外で行う（RealityKit のエンジン起動だけはメインスレッド）。

@MainActor
enum BattlePreload {
    /// 次の試合の準備を裏で始める（ロード画面の開始時）。
    static func begin(settings: GameSettings, map: MapDefinition = .standard) {
        begin(render: BattleRenderer.effectiveUserSettings(RenderSettings(settings)), map: map)
    }

    static func begin(render: RenderSettings, map: MapDefinition) {
        GroundTextureCache.prefetch(map: map, size: render.quality.groundTextureSize, colorblind: render.colorblind)
        MaterialPrograms.prewarm()
        if PostProcessSettings.preset(render.quality.level).enabled { PostProcessShaderCache.prewarm() }
    }
}

/// 戦闘で使うマテリアルの種類（ブレンド方式）ごとのシェーダープログラム。
/// RenderMaterials はトーンマップなしの Unlit と PBR を、不透明・半透明（.transparent）の両方で使う。
/// Program の生成でシェーダーがコンパイルされ、RealityKit のシェーダーキャッシュに載る（以後の同じ種類のマテリアルは待たない）。
/// 頂点の形式・影・粒子などの組み合わせは Program では表せないため、それらは幕の裏で実際に描いて温める（WarmupScheduler）。
@MainActor
enum MaterialPrograms {
    private(set) static var pbrOpaque: PhysicallyBasedMaterial.Program?
    private(set) static var pbrTransparent: PhysicallyBasedMaterial.Program?
    private(set) static var unlitOpaque: UnlitMaterial.Program?
    private(set) static var unlitTransparent: UnlitMaterial.Program?
    private static var task: Task<Void, Never>?
    /// 生成にかかった時間（ms。計測ログ用）。
    private(set) static var buildMs: Double?

    static var isReady: Bool {
        pbrOpaque != nil && pbrTransparent != nil && unlitOpaque != nil && unlitTransparent != nil
    }

    /// 生成を始める（済み・生成中なら何もしない）。
    static func prewarm() {
        guard task == nil, !isReady else { return }
        ensureEngineOnMain()
        let start = CACurrentMediaTime()
        task = Task { @MainActor in
            let programs = await build()
            pbrOpaque = programs.0
            pbrTransparent = programs.1
            unlitOpaque = programs.2
            unlitTransparent = programs.3
            buildMs = (CACurrentMediaTime() - start) * 1000
            task = nil
        }
    }

    private static var engineStarted = false

    /// RealityKit のエンジン（共有の AssetManager）はメインスレッドでしか初期化できない。Program の init は
    /// 背景で走るため、エンジンがまだ無いと背景で初期化しようとして dispatch_assert_queue で落ちる。
    /// 先にメインスレッドでエンジンを起こしておく（試合の描画でいずれ必ず払う初期化を少し前へ寄せるだけ）。
    private static func ensureEngineOnMain() {
        guard !engineStarted else { return }
        engineStarted = true
        // Entity() だけではエンジン（共有のサービス）が作られない。アセットを 1 つ作るとメインスレッドで初期化される
        AssetLedger.record(.mesh, "RealityKit engine start (tiny plane)")
        _ = MeshResource.generatePlane(width: 0.01, depth: 0.01)
    }

    /// 4 種類を並行して作る（Program の init はメインアクターに縛られない async）。
    private nonisolated static func build() async -> (PhysicallyBasedMaterial.Program, PhysicallyBasedMaterial.Program,
                                                          UnlitMaterial.Program, UnlitMaterial.Program) {
        async let a = PhysicallyBasedMaterial.Program(descriptor: pbrDescriptor(nil))
        async let b = PhysicallyBasedMaterial.Program(descriptor: pbrDescriptor(.alpha))
        async let c = UnlitMaterial.Program(descriptor: unlitDescriptor(nil))
        async let d = UnlitMaterial.Program(descriptor: unlitDescriptor(.alpha))
        return await (a, b, c, d)
    }

    nonisolated static func pbrDescriptor(_ blend: MaterialParameterTypes.BlendMode?) -> PhysicallyBasedMaterial.Program.Descriptor {
        var d = PhysicallyBasedMaterial.Program.Descriptor()
        d.blendMode = blend
        return d
    }

    nonisolated static func unlitDescriptor(_ blend: MaterialParameterTypes.BlendMode?) -> UnlitMaterial.Program.Descriptor {
        var d = UnlitMaterial.Program.Descriptor()
        // RenderMaterials の Unlit はすべて applyPostProcessToneMap: false
        d.applyPostProcessToneMap = false
        d.blendMode = blend
        return d
    }

    /// 生成が終わるまで待つ（テスト用）。
    static func waitUntilReady() async {
        prewarm()
        while !isReady {
            if let task { await task.value } else { try? await Task.sleep(for: .milliseconds(5)) }
        }
    }
}
