#if DEBUG
import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer（スキル演出の比較撮影）。起動引数 -fxCapture で、練習場の人形の南 4 m に自分のヒーローを北向きに置き、
// スキルを決まった順に実際の入力（castSkill）で撃って、発動からの決まった時刻の戦闘画面（ARView。SwiftUI の HUD と
// Effekseer の重ね描きは写らない）を画像に書き出す。CI のシミュレータ（.github/workflows/fx-capture.yml）で回し、
// MLBB の画面収録と見比べる（docs/vfx/）。撮影の間だけ、置き直し（controller.restore）でユニットの位置を戻す。sim の規則は変えない。
//
//   -fxCapture <s1,s2,ult|all>  撃つスキル（all = S1・S2・奥義。再使用の段は recasts の表の遅れで 2 回目を撃つ）
//   -fxCaptureTimes <秒,...>    発動からの撮影時刻（既定 FXCapture.defaultTimes）
//   -fxCaptureRings             スキルの前に、寸法が既知の地面の輪（半径 3 m・6 m の水色）を置いた画と置かない画を撮る（カメラの確認用）
//   -fxCaptureExit              書き出したらアプリを終える
// 出力: Documents/fxcapture/<hero>/<slot>[r]_<ms>.jpg（幅 1108 px。参考動画と同じ）と manifest.json（要求・実際の時刻、カメラ、
// 画質、撃つごとの予算の観測 SkillFXPlayer.budgetSnapshot。置き直しで集計は 0 に戻るので 1 回ずつの値）。
// 置き直し・輪のエンティティはこの撮影の間だけ作る（Debug の撮影専用。出荷ビルドには含まれない）。

@MainActor
final class FXCapture {
    static var isRequested: Bool { DebugLaunch.value(after: "-fxCapture") != nil }

    static let defaultTimes: [Double] = [0.0, 0.1, 0.2, 0.33, 0.5, 0.75, 1.0, 1.4, 2.0, 2.8]
    /// 再使用の段（2 回目）を撃つ遅れ（秒。段の演出を持つスキル）。
    static let recasts: [String: [SkillSlot: Double]] = [
        "H029": [.skill2: 0.85],
        "H032": [.skill2: 1.0],
        "H033": [.ultimate: 1.0],
    ]
    static let recastTimes: [Double] = [0.0, 0.1, 0.2, 0.33, 0.5, 0.75, 1.0, 1.4]
    static let imageWidth: CGFloat = 1108
    /// 人形からヒーローを置く距離（sim の単位）。
    static let standoff: Double = 400

    struct Shot: Codable {
        var file: String
        var slot: String
        /// 0 = 発動、1 = 再使用。
        var cast: Int
        var requested: Double
        var actual: Double
    }

    struct CameraInfo: Codable {
        var preset: String
        var pitch: Float
        var fov: Float
        var distance: Float
        var lead: Float
        var zoom: Double
        var aspect: Double
    }

    struct Manifest: Codable {
        var hero: String
        var device: String
        var quality: String
        var camera: CameraInfo
        var image: [Int]
        var shots: [Shot] = []
        /// スキルごとの予算の観測（置き直しから次の置き直しまで）。
        var budget: [String: SkillFXBudgetSnapshot] = [:]
        var notes: [String] = []
    }

    private enum Step {
        case waitLive
        case place(index: Int)
        case settle(index: Int, until: Double)
        case rings(phase: Int, until: Double)
        case cast(index: Int)
        case watch(index: Int, t0: Double, recastAt: Double?, recastT0: Double?, next: Int, nextRecast: Int)
        case finish
        case done
    }

    private let slots: [SkillSlot]
    private let times: [Double]
    private let wantsRings: Bool
    private var step: Step = .waitLive
    private var liveFrames = 0
    private var manifest: Manifest?
    private var ringEntities: [Entity] = []
    private var pendingWrites = 0
    private var finished = false
    private let dir: URL

    init() {
        let raw = DebugLaunch.value(after: "-fxCapture") ?? "all"
        let named: [String: SkillSlot] = ["s1": .skill1, "s2": .skill2, "ult": .ultimate]
        slots = raw == "all" ? [.skill1, .skill2, .ultimate] : raw.split(separator: ",").compactMap { named[String($0)] }
        times = DebugLaunch.value(after: "-fxCaptureTimes").map { $0.split(separator: ",").compactMap { Double($0) } }
            ?? FXCapture.defaultTimes
        wantsRings = DebugLaunch.args.contains("-fxCaptureRings")
        dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("fxcapture")
    }

    /// 毎フレーム（sim を進めて world.sync した後）。
    func tick(controller: BattleController, world: BattleWorld, arView: ARView, quality: RenderQuality) {
        let s = controller.state
        switch step {
        case .waitLive:
            guard controller.isPresentationReady, controller.humanIndex != nil else { return }
            liveFrames += 1
            guard liveFrames > 90 else { return }
            start(controller: controller, arView: arView, quality: quality)
            step = .place(index: 0)
        case .place(let k):
            guard k < slots.count else {
                let player = world.skillDirector.player
                note("FXPrograms ready=\(FXPrograms.isReady) failed=\(FXPrograms.failed) \(FXPrograms.failure ?? "")"
                     + " buildMs=\(FXPrograms.buildMs.map { String(Int($0)) } ?? "-") fallbacks=\(player.materials.fallbacks)"
                     + " sheetsMissing=\(player.sheets.missing.map(\.rawValue).sorted())")
                step = .finish
                return
            }
            guard place(controller: controller) else { note("人形が見つからない"); step = .finish; return }
            step = .settle(index: k, until: s.time + 1.6)
        case .settle(let k, let until):
            guard s.time >= until else { return }
            if wantsRings, k == 0, !ringsDone {
                addRings(world: world, controller: controller)
                step = .rings(phase: 0, until: s.time + 0.3)
            } else {
                step = .cast(index: k)
            }
        case .rings(let phase, let until):
            guard s.time >= until else { return }
            if phase == 0 {
                snap(arView, name: "rings", slot: "rings", cast: 0, requested: 0, actual: 0)
                removeRings()
                step = .rings(phase: 1, until: s.time + 0.3)
            } else {
                snap(arView, name: "norings", slot: "rings", cast: 0, requested: 0, actual: 0)
                ringsDone = true
                step = .cast(index: 0)
            }
        case .cast(let k):
            guard let foe = dummyID(controller) else { step = .finish; return }
            controller.send(.castSkill(slot: slots[k], target: .unit(foe)))
            let hero = manifest?.hero ?? ""
            let delay = FXCapture.recasts[hero]?[slots[k]]
            step = .watch(index: k, t0: s.time, recastAt: delay.map { s.time + $0 }, recastT0: nil, next: 0, nextRecast: 0)
        case .watch(let k, let t0, let recastAt, var recastT0, var next, var nextRecast):
            let name = FXCapture.slotName(slots[k])
            while next < times.count, s.time - t0 >= times[next] {
                snap(arView, name: "\(name)_\(Int((times[next] * 1000).rounded()))", slot: name, cast: 0,
                     requested: times[next], actual: s.time - t0)
                next += 1
            }
            if let at = recastAt, recastT0 == nil, s.time >= at, let foe = dummyID(controller) {
                controller.send(.castSkill(slot: slots[k], target: .unit(foe)))
                recastT0 = s.time
            }
            if let r0 = recastT0 {
                while nextRecast < FXCapture.recastTimes.count, s.time - r0 >= FXCapture.recastTimes[nextRecast] {
                    let t = FXCapture.recastTimes[nextRecast]
                    snap(arView, name: "\(name)r_\(Int((t * 1000).rounded()))", slot: name, cast: 1, requested: t, actual: s.time - r0)
                    nextRecast += 1
                }
            }
            let recastDone = recastAt == nil || nextRecast >= FXCapture.recastTimes.count
            if next >= times.count, recastDone {
                manifest?.budget[name] = world.skillDirector.player.budgetSnapshot()
                step = .place(index: k + 1)
            } else {
                step = .watch(index: k, t0: t0, recastAt: recastAt, recastT0: recastT0, next: next, nextRecast: nextRecast)
            }
        case .finish:
            step = .done
        case .done:
            // 画像を全て書き終えてから目録を書く（CI は目録ができたら集める）
            if !finished, pendingWrites == 0 {
                finished = true
                writeManifest()
                if DebugLaunch.args.contains("-fxCaptureExit") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
                }
            }
        }
    }

    private var ringsDone = false

    static func slotName(_ s: SkillSlot) -> String {
        switch s {
        case .passive: return "passive"
        case .skill1: return "s1"
        case .skill2: return "s2"
        case .ultimate: return "ult"
        }
    }

    // MARK: 準備

    private func start(controller: BattleController, arView: ARView, quality: RenderQuality) {
        let hero = controller.humanIndex.flatMap { controller.state.units[$0].hero?.heroID } ?? "?"
        let size = arView.bounds.size
        let aspect = size.height > 0 ? Double(size.width / size.height) : 0
        let width = Int(FXCapture.imageWidth)
        let height = aspect > 0 ? Int((Double(width) / aspect).rounded()) : 0
        let camera = CameraInfo(preset: DebugLaunch.value(after: "-cameraPreset") ?? "default",
                                pitch: CameraRig.pitchDegrees, fov: CameraRig.fovDegrees, distance: CameraRig.baseDistance,
                                lead: CameraRig.focusLead, zoom: controller.effectiveCameraZoom, aspect: aspect)
        manifest = Manifest(hero: hero, device: PerfRun.deviceModel, quality: "\(quality.level)", camera: camera,
                            image: [width, height])
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(hero))
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent(hero), withIntermediateDirectories: true)
    }

    private func dummyID(_ controller: BattleController) -> EntityID? {
        let s = controller.state
        guard let me = controller.humanIndex else { return nil }
        let p = s.units[me].pos
        return s.units.filter { $0.kind == .dummy && $0.isAlive }
            .min { $0.pos.distance(to: p) < $1.pos.distance(to: p) }?.id
    }

    /// 自分のヒーローを人形の南 standoff に北向きで置き直し、体力・資源を満たし、人形の体力も戻す。
    private func place(controller: BattleController) -> Bool {
        guard let me = controller.humanIndex, let foe = dummyID(controller) else { return false }
        var s = controller.state
        guard let fi = s.index(of: foe) else { return false }
        let spot = s.units[fi].pos + Vec2(0, -FXCapture.standoff)
        s.units[me].pos = spot
        s.units[me].prevPos = spot
        s.units[me].path.removeAll()
        s.units[me].moveIntent = .none
        s.units[me].facing = Double.pi / 2
        s.units[me].hp = s.units[me].stats.maxHP
        s.units[me].resource = s.units[me].stats.maxResource
        s.units[fi].hp = s.units[fi].stats.maxHP
        controller.restore(s)
        return true
    }

    // MARK: 寸法が既知の地面の輪

    private func addRings(world: BattleWorld, controller: BattleController) {
        guard let id = controller.humanHeroID, let p = world.units.worldPositionOf(id),
              let image = FXCapture.ringImage(), let tex = try? TextureResource(image: image, options: .init(semantic: .color))
        else { note("輪を作れない"); return }
        for r: Float in [3, 6] {
            var m = UnlitMaterial(applyPostProcessToneMap: false)
            m.color = .init(tint: UIColor(red: 0, green: 1, blue: 1, alpha: 1), texture: .init(tex))
            m.blending = .transparent(opacity: .init(floatLiteral: 1))
            m.writesDepth = false
            // 画像の輪は一辺の 0.48 倍の半径に描くので、板の一辺を 2r / 0.96 にすると輪の半径がちょうど r になる
            let side = 2 * r / 0.96
            let e = ModelEntity(mesh: .generatePlane(width: side, depth: side), materials: [m])
            e.position = SIMD3(p.x, 0.04, p.z)
            world.root.addChild(e)
            ringEntities.append(e)
        }
        note("輪: 足元 (\(p.x), \(p.z)) を中心に半径 3 m・6 m")
    }

    private func removeRings() {
        for e in ringEntities { e.removeFromParent() }
        ringEntities.removeAll()
    }

    /// 白い細い輪（半径 = 一辺の 0.48 倍、線の幅 = 一辺の 0.004 倍）の画像。
    static func ringImage() -> CGImage? {
        let n = 2048
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let s = CGFloat(n)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.setLineWidth(s * 0.004)
        let r = s * 0.48
        ctx.strokeEllipse(in: CGRect(x: s / 2 - r, y: s / 2 - r, width: 2 * r, height: 2 * r))
        return ctx.makeImage()
    }

    // MARK: 書き出し

    private func snap(_ arView: ARView, name: String, slot: String, cast: Int, requested: Double, actual: Double) {
        guard let hero = manifest?.hero else { return }
        let file = "\(name).jpg"
        manifest?.shots.append(Shot(file: file, slot: slot, cast: cast, requested: requested, actual: actual))
        let url = dir.appendingPathComponent(hero).appendingPathComponent(file)
        let width = FXCapture.imageWidth
        pendingWrites += 1
        arView.snapshot(saveToHDR: false) { image in
            Task { @MainActor [weak self] in
                self?.save(image, to: url, width: width, file: file)
            }
        }
    }

    private func save(_ image: UIImage?, to url: URL, width: CGFloat, file: String) {
        defer { pendingWrites -= 1 }
        guard let image, image.size.width > 0 else { note("撮れない: \(file)"); return }
        let size = CGSize(width: width, height: (width * image.size.height / image.size.width).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        try? small.jpegData(compressionQuality: 0.9)?.write(to: url, options: .atomic)
    }

    private func writeManifest() {
        guard let m = manifest else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(m) else { return }
        try? data.write(to: dir.appendingPathComponent(m.hero).appendingPathComponent("manifest.json"), options: .atomic)
        print("VELSTRIA_FX_CAPTURE \(m.hero) shots=\(m.shots.count)")
    }

    private func note(_ s: String) {
        manifest?.notes.append(s)
    }
}
#endif
