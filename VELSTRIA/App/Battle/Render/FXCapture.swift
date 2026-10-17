#if DEBUG
import Foundation
import Metal
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer（スキル演出の比較撮影）。起動引数 -fxCapture で、練習場の人形の南 4 m に自分のヒーローを北向きに置き、
// スキルを決まった順に実際の入力（castSkill）で撃って、発動からの決まった時刻に sim・演出・粒子を止め、CI がシミュレータの
// 画面（HUD を含む）を撮る（/tmp/velstria-fxcap の合図。合図が無ければ ARView の画で代える）。CI のシミュレータ（.github/workflows/fx-capture.yml）で回し、
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
    /// 再使用の段（2 回目）を撃つ遅れ（秒。段の演出を持つスキル）。内部ビルドの演出チェックと共通。
    static let recasts = FXCheckDriver.recasts
    static let recastTimes: [Double] = [0.0, 0.1, 0.2, 0.33, 0.5, 0.75, 1.0, 1.4]
    static let imageWidth: CGFloat = 1108
    /// 人形からヒーローを置く距離（sim の単位）。内部ビルドの演出チェックと共通。
    static let standoff = FXCheckDriver.standoff

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
        case probe(index: Int, until: Double)
        case finish
        case done
    }

    private let slots: [SkillSlot]
    private let times: [Double]
    private let wantsRings: Bool
    /// -fxCaptureProbe: スキルの代わりに、部品の種類を 1 つずつ足して撮る（描画の切り分け用）。
    private let wantsProbe: Bool
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
        wantsProbe = DebugLaunch.args.contains("-fxCaptureProbe")
        dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("fxcapture")
    }

    /// 画面の撮影の合図（シミュレータのアプリはホストの /tmp を読み書きできる）。撮る時刻に止めて request に名前を書き、
    /// CI（tools/fx_capture/run_ci.sh）が `simctl io screenshot` で画面を撮って done を置いたら再開する。
    static let handshake = "/tmp/velstria-fxcap"
    /// 合図が返らない（手元で CI の手順なしに動かした）時は ARView の画で代える。
    static let handshakeTimeout: Double = 40

    /// 撮影のために止めている（BattleRenderer は sim・描画の同期を進めず、tick だけ呼ぶ）。
    private(set) var isFrozen = false
    /// 撮る間に粒子も止める（-fxCaptureMovingParticles で止めない。粒子が CI のシミュレータで映るかの切り分け）。
    private let freezesParticles = !DebugLaunch.args.contains("-fxCaptureMovingParticles")
    private var frozenAt: Double = 0
    private var frozenName = ""

    /// 毎フレーム（sim を進めて world.sync した後。止めている間も呼ばれる）。
    func tick(controller: BattleController, world: BattleWorld, arView: ARView, quality: RenderQuality) {
        if isFrozen {
            pollShot(world: world, arView: arView)
            return
        }
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
                     + " sealed=\(!player.materials.createsShaded)"
                     + " sheetsMissing=\(player.sheets.missing.map(\.rawValue).sorted())")
                step = .finish
                return
            }
            guard place(controller: controller) else { note("人形が見つからない"); step = .finish; return }
            step = wantsProbe ? .probe(index: 0, until: s.time + 1.6) : .settle(index: k, until: s.time + 1.6)
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
            switch phase {
            case 0:
                step = .rings(phase: 1, until: s.time)
                shoot(world: world, name: "rings", slot: "rings", cast: 0, requested: 0, actual: 0)
            case 1:
                removeRings()
                step = .rings(phase: 2, until: s.time + 0.3)
            default:
                ringsDone = true
                step = .cast(index: 0)
                shoot(world: world, name: "norings", slot: "rings", cast: 0, requested: 0, actual: 0)
            }
        case .cast(let k):
            guard let foe = dummyID(controller) else { step = .finish; return }
            controller.send(.castSkill(slot: slots[k], target: .unit(foe)))
            let hero = manifest?.hero ?? ""
            let delay = FXCapture.recasts[hero]?[slots[k]]
            step = .watch(index: k, t0: s.time, recastAt: delay.map { s.time + $0 }, recastT0: nil, next: 0, nextRecast: 0)
        case .watch(let k, let t0, let recastAt, var recastT0, var next, var nextRecast):
            let name = FXCapture.slotName(slots[k])
            if let at = recastAt, recastT0 == nil, s.time >= at, let foe = dummyID(controller) {
                controller.send(.castSkill(slot: slots[k], target: .unit(foe)))
                recastT0 = s.time
            }
            // 1 回の tick で撮るのは 1 枚（撮る間は止める）
            var shot: (name: String, cast: Int, requested: Double, actual: Double)?
            if next < times.count, s.time - t0 >= times[next] {
                shot = ("\(name)_\(Int((times[next] * 1000).rounded()))", 0, times[next], s.time - t0)
                next += 1
            } else if let r0 = recastT0, nextRecast < FXCapture.recastTimes.count, s.time - r0 >= FXCapture.recastTimes[nextRecast] {
                let t = FXCapture.recastTimes[nextRecast]
                shot = ("\(name)r_\(Int((t * 1000).rounded()))", 1, t, s.time - r0)
                nextRecast += 1
            }
            let recastDone = recastAt == nil || nextRecast >= FXCapture.recastTimes.count
            if shot == nil, next >= times.count, recastDone {
                manifest?.budget[name] = world.skillDirector.player.budgetSnapshot()
                step = .place(index: k + 1)
            } else {
                step = .watch(index: k, t0: t0, recastAt: recastAt, recastT0: recastT0, next: next, nextRecast: nextRecast)
            }
            if let shot {
                shoot(world: world, name: shot.name, slot: name, cast: shot.cast, requested: shot.requested, actual: shot.actual)
            }
        case .probe(let k, let until):
            guard s.time >= until else { return }
            guard let id = controller.humanHeroID, let p = world.units.worldPositionOf(id),
                  let name = probeStep(k, world: world, at: p) else {
                step = .finish
                return
            }
            step = .probe(index: k + 1, until: s.time + 0.4)
            shoot(world: world, name: "probe\(k + 1)_\(name)", slot: "probe", cast: 0, requested: Double(k), actual: Double(k))
        case .finish:
            step = .done
        case .done:
            // 画像を全て書き終えてから目録を書く（CI は目録ができたら集める）
            if !finished, pendingWrites == 0 {
                finished = true
                selfTestEffekseerPost()
                writeManifest()
                if DebugLaunch.args.contains("-fxCaptureExit") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
                }
            }
        }
    }

    /// 撮る: 止めて（sim・演出の時刻・粒子）、CI に画面の撮影を頼む。
    private func shoot(world: BattleWorld, name: String, slot: String, cast: Int, requested: Double, actual: Double) {
        guard let hero = manifest?.hero else { return }
        manifest?.shots.append(Shot(file: "\(name).jpg", slot: slot, cast: cast, requested: requested, actual: actual))
        isFrozen = true
        frozenAt = CACurrentMediaTime()
        frozenName = "\(hero)/\(name)"
        if freezesParticles { world.skillDirector.player.freezeParticles(true) }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: FXCapture.handshake, withIntermediateDirectories: true)
        try? fm.removeItem(atPath: FXCapture.handshake + "/done")
        try? "\(hero)/\(name)".write(toFile: FXCapture.handshake + "/request", atomically: true, encoding: .utf8)
    }

    /// 止めている間: done が置かれたら再開する。時間切れなら ARView の画で代えて再開する。
    private func pollShot(world: BattleWorld, arView: ARView) {
        let fm = FileManager.default
        let done = FXCapture.handshake + "/done"
        if fm.fileExists(atPath: done) {
            // done には撮った画の名前が書いてある。前の画の遅れた done は捨てて待ち続ける
            let token = (try? String(contentsOfFile: done, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            try? fm.removeItem(atPath: done)
            guard token == frozenName else { return }
        } else if CACurrentMediaTime() - frozenAt > FXCapture.handshakeTimeout {
            try? fm.removeItem(atPath: FXCapture.handshake + "/request")
            note("画面の撮影の合図が返らない: \(frozenName)（ARView の画で代えた）")
            snapView(arView, name: String(frozenName.split(separator: "/").last ?? ""))
        } else {
            return
        }
        if freezesParticles { world.skillDirector.player.freezeParticles(false) }
        isFrozen = false
    }

    private var ringsDone = false

    // MARK: 描画の切り分け（-fxCaptureProbe）

    /// 部品の種類を 1 つずつ足す（寿命 6 秒。ヒーローの北（画面の中央の上。HUD・岩に隠れない）に並べ、足すたびに撮る）。局所の座標は 右・上・前（前 = 北）。
    /// 従来の粒子・輪を先に、演出のシェーダー・単色のテスト用シェーダー（fxDebugSurface）・コマ送りの順。nil = 終わり。
    private func probeStep(_ k: Int, world: BattleWorld, at p: SIMD3<Float>) -> String? {
        let player = world.skillDirector.player
        let palette = FXPalette.from(RGB(1, 0.6, 0.2))
        let ctx = SkillFXPlayer.Context(palette: palette, origin: p, caster: p, target: p + [0, 0, -3], forward: [0, 0, -1])
        func disc(_ tex: FXTex, _ tint: FXTint) -> FXMesh {
            FXMesh(shape: .disc, tex: tex, tint: tint, size: [1.6, 1, 1.6], sizeEnd: [1.6, 1, 1.6], life: 6, fadeIn: 0.01, fadeOut: 0.97)
        }
        func worldPos(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { SIMD3(p.x + x, y, p.z - z) }
        func place(_ mesh: MeshResource?, _ material: (any Material)?, _ x: Float, _ z: Float, scale: Float = 1.6) {
            guard let mesh, let material else { note("probe: 作れない（\(k)）"); return }
            let e = ModelEntity(mesh: mesh, materials: [material])
            e.position = worldPos(x, GroundLayer.skillDecal, z)
            e.scale = SIMD3(repeating: scale)
            OverlayOrder.apply(e, OverlayOrder.skillDecal)
            root(world).addChild(e)
        }
        switch k {
        case 0:
            player.play([.emit(FXEmit.flare(1.6, .primary, life: 6).with { $0.fade = .constant }, offset: [-3, 1, 1.4])], ctx)
            return "legacyParticle"
        case 1:
            player.play([.mesh(disc(.ring, .white), offset: [-1, 0, 1.4])], ctx)
            return "legacyDisc"
        case 2:
            place(player.meshes.mesh(.disc), debugMaterial(), 1, 1.4)
            return "debugShaderFXDisc"
        case 3:
            place(MeshResource.generatePlane(width: 1, depth: 1), debugMaterial(), 3, 1.4)
            return "debugShaderPlane"
        case 4:
            player.play([.mesh(disc(.glow, .primary).flowing(.noise, scroll: [0.2, 0.2], strength: 0.8, edge: .core),
                               offset: [-3, 0, 3.0])], ctx)
            return "flowAlphaDisc"
        case 5:
            player.play([.mesh(disc(.glow, .primary).glowing(), offset: [-1, 0, 3.0])], ctx)
            return "addDisc"
        case 6:
            place(MeshResource.generatePlane(width: 1, depth: 1),
                  player.materials.material(for: disc(.glow, .primary).glowing(), palette: palette), 1, 3.0)
            return "addOnPlane"
        case 7:
            player.sheets.prewarm([.fireBurst])
            player.play([.emit(FXEmit.sheet(.fireBurst, 2, .primary, life: 6).with { $0.sheetFPS = 3; $0.fade = .constant },
                               offset: [3, 1, 3.0])], ctx)
            return "sheetParticle"
        case 8:
            player.play([.mesh(disc(.ring, .secondary), offset: [0, 0, 4.6])], ctx)
            return "legacyDiscAfter"
        default:
            return nil
        }
    }

    private var debugCached: CustomMaterial?

    /// 単色のテスト用シェーダーの材質（Program を使わない同期の作り方。fxDebugSurface・unlit・不透明・マゼンタ）。
    private func debugMaterial() -> CustomMaterial? {
        if let debugCached { return debugCached }
        guard let lib = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary() else { note("probe: default.metallib が無い"); return nil }
        do {
            var m = try CustomMaterial(surfaceShader: .init(named: "fxDebugSurface", in: lib), geometryModifier: nil, lightingModel: .unlit)
            m.baseColor = .init(tint: UIColor(red: 1, green: 0, blue: 1, alpha: 1), texture: nil)
            m.faceCulling = .none
            debugCached = m
            return m
        } catch {
            note("probe: fxDebugSurface を作れない: \(error)")
            return nil
        }
    }

    private func root(_ world: BattleWorld) -> Entity { world.skillDirector.player.root }

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
            e.position = SIMD3(p.x, GroundLayer.aim, p.z)
            OverlayOrder.apply(e, OverlayOrder.skillDecal)
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

    /// ARView の画（画面の撮影の代わり。HUD・Effekseer の重ね描きが写らない。撮影の CI ではスキルの粒子・半透明の部品も
    /// 写らなかった（2026-10-17 の fxcap-h029v1）ので、画面の撮影が使えない時だけ）。
    private func snapView(_ arView: ARView, name: String) {
        guard let hero = manifest?.hero else { return }
        let file = "\(name).jpg"
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

    /// Effekseer を後処理の中で描く経路の自己診断（シミュレータは RealityKit の後処理を呼ばないので、黒い画と一様な深度で試す）。
    /// 結果は目録の notes と、遠い深度の画 efkpost.png（このヒーローの .efk を全部その場で再生した 8 コマ目）。
    private func selfTestEffekseerPost() {
        guard let hero = manifest?.hero, let folder = Bundle.main.url(forResource: EffekseerOverlay.bundleFolder, withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        let names = files.filter { $0.pathExtension == "efk" && $0.lastPathComponent.hasPrefix(hero + "_") }
            .map { $0.deletingPathExtension().lastPathComponent }.sorted()
        let r = EffekseerPostPass.selfTest(effects: names, saveTo: dir.appendingPathComponent(hero).appendingPathComponent("efkpost.png"))
        note(r.summary + " effects=\(names.count)")
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
