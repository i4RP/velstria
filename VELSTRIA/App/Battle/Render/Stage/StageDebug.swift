import Foundation
import QuartzCore
import VelstriaCore

// 担当: battle-renderer（ステージ）。見た目確認用の起動引数（DEBUG のみ。出荷ビルドには含めない）。
//   -stageLayoutReference        2026-10-17参照画像の俯角・画角・注視点で固定撮影
//   -stageCam <x>,<y>[,<zoom>]   カメラを地図座標（m）の位置に固定する（例: -stageCam 37,83）
//   -stageTour                   カメラを名所（拠点・レーン・川・ボスの巣・ジャングル）へ 6 秒ごとに順に動かす
//   -stageFull                   -uiTesting でもステージを間引かない（StagePrep.lite を参照）
//   -stageSilent                 撮影中はオーディオエンジンを起動しない（シミュレータの音声 I/O に依存しない）
//   -stageClean                  HUD を非表示（頭上バーは残す）
//   -stagePitch <30...75>        比較撮影の俯角（既定のゲームカメラは 56 度）
//   -stagePitReference           カメラに近い巣にタートルとヒーローを描画だけ配置する
//   -legacyStage                 2026-10-05 の旧ステージ素材で描く（StageArtSet.legacy。新旧の見比べ用）

enum StageDebug {
    #if DEBUG
    static let spots: [SIMD2<Float>] = [
        [16, 18],   // 青の拠点
        [14, 60],   // 上レーン
        [42, 42],   // 中央レーン（青側）
        [60, 60],   // 中央の川
        [83, 37],   // ボスの巣（Astral Wyrm）
        [56, 30],   // 青側のジャングル
        [37, 83],   // ボスの巣（Ancient Colossus）
        [104, 104], // 赤の拠点
    ]

    private static let fixedArgs: [Float]? = {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-stageLayoutReference") { return [61.03907433, 64.19554158, 17.629678531] }
        guard let i = args.firstIndex(of: "-stageCam"), i + 1 < args.count else { return nil }
        let v = args[i + 1].split(separator: ",").compactMap { Float($0) }
        return v.count >= 2 ? v : nil
    }()
    private static var fixed: SIMD2<Float>? { fixedArgs.map { SIMD2($0[0], $0[1]) } }

    /// -stageCam の 3 つ目の値（ズーム）。
    static var cameraZoom: Double? { fixedArgs.flatMap { $0.count >= 3 ? Double($0[2]) : nil } }

    static func applyLayoutReference(to frame: inout RenderFrame) {
        if ProcessInfo.processInfo.arguments.contains("-stageLayoutReference") { frame.viewerTeam = nil }
    }

    static let tour = ProcessInfo.processInfo.arguments.contains("-stageTour")
    /// Screenshot-only size comparison; the actual simulation is not modified.
    static func applyPitReference(to frame: inout RenderFrame) {
        guard ProcessInfo.processInfo.arguments.contains("-stagePitReference"), let fixed else { return }
        let target = Vec2(Double(fixed.x) * 100, Double(fixed.y) * 100)
        guard let camp = MapDefinition.relayout.camps.filter({ $0.kind.isBoss })
            .min(by: { $0.pos.distance(to: target) < $1.pos.distance(to: target) }) else { return }
        let c = camp.pos
        var turtle = UnitFactory.makeMonster(kind: .astralWyrm, campID: -1, pos: c)
        turtle.facing = -.pi / 4
        frame.state.nextEntityID = 9_000_000 // Stable, disjoint ID; never reuse a live simulation unit's visual.
        frame.state.addUnit(turtle)
        if let hero = frame.state.units.indices.first(where: { frame.state.units[$0].kind == .hero }) {
            let at = c + Vec2(240, -270)
            frame.state.units[hero].pos = at
            frame.state.units[hero].prevPos = at
            frame.state.units[hero].facing = .pi / 2
        }
        frame.viewerTeam = nil
    }
    private static let start = CACurrentMediaTime()

    /// カメラの注視点（world の x, z）。指定が無ければ nil。
    static var cameraTarget: SIMD2<Float>? {
        if let fixed { return SIMD2(fixed.x, -fixed.y) }
        guard tour else { return nil }
        let k = Int((CACurrentMediaTime() - start) / 6) % spots.count
        return SIMD2(spots[k].x, -spots[k].y)
    }
    #endif
}
