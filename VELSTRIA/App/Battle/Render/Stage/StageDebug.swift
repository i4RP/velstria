import Foundation
import QuartzCore

// 担当: battle-renderer（ステージ）。見た目確認用の起動引数（DEBUG のみ。出荷ビルドには含めない）。
//   -stageCam <x>,<y>[,<zoom>]   カメラを地図座標（m）の位置に固定する（例: -stageCam 37,83）
//   -stageTour                   カメラを名所（拠点・レーン・川・ボスの巣・ジャングル）へ 6 秒ごとに順に動かす
//   -stageFull                   -uiTesting でもステージを間引かない（StagePrep.lite を参照）

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
        guard let i = args.firstIndex(of: "-stageCam"), i + 1 < args.count else { return nil }
        let v = args[i + 1].split(separator: ",").compactMap { Float($0) }
        return v.count >= 2 ? v : nil
    }()
    private static var fixed: SIMD2<Float>? { fixedArgs.map { SIMD2($0[0], $0[1]) } }

    /// -stageCam の 3 つ目の値（ズーム）。
    static var cameraZoom: Double? { fixedArgs.flatMap { $0.count >= 3 ? Double($0[2]) : nil } }

    static let tour = ProcessInfo.processInfo.arguments.contains("-stageTour")
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
