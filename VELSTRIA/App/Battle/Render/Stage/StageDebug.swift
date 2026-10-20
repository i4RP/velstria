import Foundation
import QuartzCore
import VelstriaCore

// 担当: battle-renderer（ステージ）。見た目確認用の起動引数（DEBUG のみ。出荷ビルドには含めない）。
//   -stageLayoutReference        2026-10-17参照画像の俯角・画角・注視点で固定撮影
//   -stageShot IMG_6713          2026-10-19の各画像を通常のレンズで比較撮影
//   -stageReview                Documents/stage-review.txtの画像名で撮影地点を切り替える
//   -stageUnits                 unit-reference.json の姿勢・出現段階でユニットの寸法を比較（描画のみ）
//   -stageCam <x>,<y>[,<zoom>]   カメラを地図座標（m）の位置に固定する（例: -stageCam 37,83）
//   -stageTour                   カメラを名所（拠点・レーン・川・ボスの巣・ジャングル）へ 6 秒ごとに順に動かす
//   -stageFull                   -uiTesting でもステージを間引かない（StagePrep.lite を参照）
//   -stageSilent                 撮影中はオーディオエンジンを起動しない（シミュレータの音声 I/O に依存しない）
//   -stageClean                  HUD を非表示（頭上バーは残す）
//   -stagePitch <30...75>        比較撮影の俯角（旧48°画角・距離10mの角度だけ変える。通常プレイは参照ステージの組）
//   -stagePitReference           カメラに近い巣にタートルとヒーローを描画だけ配置する
//   -legacyStage                 2026-10-05 の旧ステージ素材で描く（StageArtSet.legacy。新旧の見比べ用）

enum StageDebug {
    #if DEBUG
    /// Review views use the shipping lens, with a stable hero for scale comparison.
    private static let initialReferenceView: StageReferenceLayout.View? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-stageShot"), i + 1 < args.count else { return nil }
        return StageReferenceLayout.views.first { $0.name == args[i + 1] }
    }()
    private nonisolated(unsafe) static var reviewName = ""
    private nonisolated(unsafe) static var reviewReadAt: CFTimeInterval = 0
    private struct UnitReference: Decodable {
        let kind: Int
        let ground: [Double]
        let facing: Double
    }
    private nonisolated(unsafe) static var unitReferences: [String: [UnitReference]] = [:]
    static var referenceView: StageReferenceLayout.View? {
        guard ProcessInfo.processInfo.arguments.contains("-stageReview") else { return initialReferenceView }
        let now = CACurrentMediaTime()
        if now - reviewReadAt > 0.25 {
            reviewReadAt = now
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("stage-review.txt")
            reviewName = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if ProcessInfo.processInfo.arguments.contains("-stageUnits"),
               let data = try? Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent("unit-reference.json")),
               let references = try? JSONDecoder().decode([String: [UnitReference]].self, from: data) {
                unitReferences = references
            }
        }
        return StageReferenceLayout.views.first { $0.name == reviewName } ?? initialReferenceView
    }
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
        if let view = referenceView { return [Float(view.focus.x / 100), Float(view.focus.y / 100), 1] }
        if args.contains("-stageLayoutReference") { return [61.03907433, 64.19554158, 17.629678531] }
        guard let i = args.firstIndex(of: "-stageCam"), i + 1 < args.count else { return nil }
        let v = args[i + 1].split(separator: ",").compactMap { Float($0) }
        return v.count >= 2 ? v : nil
    }()
    private static var fixed: SIMD2<Float>? { fixedArgs.map { SIMD2($0[0], $0[1]) } }

    /// -stageCam の 3 つ目の値（ズーム）。
    static var cameraZoom: Double? {
        if let view = referenceView { return Double(view.zoom) }
        return fixedArgs.flatMap { $0.count >= 3 ? Double($0[2]) : nil }
    }

    static func applyLayoutReference(to frame: inout RenderFrame) {
        if ProcessInfo.processInfo.arguments.contains("-stageLayoutReference") { frame.viewerTeam = nil }
        if let view = referenceView {
            frame.viewerTeam = nil
            if let hero = frame.state.units.indices.first(where: { frame.state.units[$0].kind == .hero }) {
                frame.state.units[hero].pos = view.hero
                frame.state.units[hero].prevPos = view.hero
                frame.state.units[hero].facing = .pi / 2
            }
            if ProcessInfo.processInfo.arguments.contains("-stageUnits") {
                applyUnitReference(to: &frame, view: view)
            }
        }
    }

    private static func groundPoint(_ pixel: [Double], view: StageReferenceLayout.View) -> Vec2 {
        let pitch = Double(StageReferenceLayout.pitchDegrees) * .pi / 180
        let focal = 315 / tan(Double(StageReferenceLayout.verticalFOV) * .pi / 360)
        let distance = Double(StageReferenceLayout.cameraDistance * view.zoom)
        let dy = (315 - pixel[1]) * distance / (focal * sin(pitch) - (315 - pixel[1]) * cos(pitch))
        return view.hero + Vec2((pixel[0] - 684) * (distance + dy * cos(pitch)) / focal * 100,
                               (Double(StageReferenceLayout.cameraLead) + dy) * 100)
    }

    /// Source creatures can be fighting, wandering, or already evolved. Only pose/type is staged;
    /// the shipping CreatureVisual / OverheadBar determines every rendered dimension.
    private static func applyUnitReference(to frame: inout RenderFrame, view: StageReferenceLayout.View) {
        if reviewName == "UNIT_TEAMS", let original = frame.state.units.first(where: { $0.kind == .hero }) {
            frame.state.nextEntityID = 9_100_000
            for (team, x) in [(Team.blue, 410.0), (.red, 950.0)] {
                var copy = original
                copy.team = team
                copy.pos = groundPoint([x, 385], view: view)
                copy.prevPos = copy.pos
                frame.state.addUnit(copy)
            }
        }
        guard let references = unitReferences[view.name] else { return }
        // Hide the original neutral population in this render snapshot. It remains alive in SimState.
        for i in frame.state.units.indices where frame.state.units[i].kind == .monster {
            frame.state.units[i].pos = Vec2(-100_000, -100_000)
            frame.state.units[i].prevPos = frame.state.units[i].pos
        }
        frame.state.nextEntityID = 9_000_000
        for (i, reference) in references.prefix(12).enumerated() {
            guard let kind = MonsterKind(rawValue: reference.kind), reference.ground.count == 2 else { continue }
            var unit = UnitFactory.makeMonster(kind: kind, campID: -1, pos: groundPoint(reference.ground, view: view))
            unit.facing = reference.facing * .pi / 180
            // Stable per-kind IDs prevent a pooled visual being reused for a different model.
            frame.state.nextEntityID = 9_000_000 + EntityID(kind.rawValue * 100 + i)
            frame.state.addUnit(unit)
        }
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
        if let view = referenceView { return SIMD2(Float(view.focus.x / 100), -Float(view.focus.y / 100)) }
        if let fixed { return SIMD2(fixed.x, -fixed.y) }
        guard tour else { return nil }
        let k = Int((CACurrentMediaTime() - start) / 6) % spots.count
        return SIMD2(spots[k].x, -spots[k].y)
    }
    #endif
}
