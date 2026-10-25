#if DEBUG || SCREENSHOTS
import Foundation
import Combine
import RealityKit
import SwiftUI
import UIKit
import VelstriaCore

/// Fixed-input comparison stage. This uses the shipping model/player, battle lens
/// and battle lights; it is a labelled review stage, not a simulated battle.
struct HeroQualityReviewView: UIViewRepresentable {
    func makeCoordinator() -> HeroQualityReviewDriver { HeroQualityReviewDriver() }
    func makeUIView(context: Context) -> ARView { context.coordinator.makeView() }
    func updateUIView(_ uiView: ARView, context: Context) {}
    static func dismantleUIView(_ view: ARView, coordinator: HeroQualityReviewDriver) { coordinator.subscription?.cancel() }
}

@MainActor
final class HeroQualityReviewDriver {
    var subscription: Cancellable?
    private let anchor = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private let caption = UILabel()
    private var model: (any HeroDisplayModel)?
    private var time: Float = 0
    private var warmed: Float = 0
    private var ready = false
    private var started = false
    private var finished = false
    private var action = -1
    private var releaseAt: Float?
    private var castHitAt: Float?
    private var yaw: Float = .pi * 0.75
    private let close = DebugLaunch.args.contains("-heroReviewClose")
    private let heroID: String = {
        let args = DebugLaunch.args
        if let i = args.firstIndex(of: "-heroReviewHero"), args.indices.contains(i + 1), args[i + 1] == "H028" { return "H028" }
        return "H025"
    }()
    private var dir: URL { URL(fileURLWithPath: "/tmp/velstria-\(heroID.lowercased())-review", isDirectory: true) }
    static let duration: Float = 38

    func makeView() -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(UIColor(red: 0.17, green: 0.22, blue: 0.20, alpha: 1))
        view.renderOptions.insert(.disableMotionBlur)
        view.renderOptions.insert(.disableDepthOfField)
        let hero = HeroModelLibrary.makeHero(heroID: heroID, skinID: nil, team: .neutral,
                                            master: .shared, options: .init(teamMarker: false, shadow: true, aura: false))
        model = hero
        anchor.addChild(hero.root)
        camera.camera = PerspectiveCameraComponent(near: 0.1, far: 100,
            fieldOfViewInDegrees: CameraRig.fovDegrees)
        camera.orientation = CameraRig.orientation
        anchor.addChild(camera)

        let sun = DirectionalLight()
        sun.light.intensity = 3400
        sun.light.color = UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
        sun.look(at: .zero, from: [-0.55, 1, -0.45], relativeTo: nil)
        sun.shadow = .init(shadowProjection: .fixed(zNear: 0.1, zFar: 100, orthographicScale: 20), depthBias: 1.6)
        sun.position = [0, 25, 0]
        anchor.addChild(sun)
        let fill = DirectionalLight()
        fill.light.intensity = 900
        fill.light.color = UIColor(red: 0.62, green: 0.74, blue: 1, alpha: 1)
        fill.look(at: .zero, from: [0.6, 0.8, 0.7], relativeTo: nil)
        anchor.addChild(fill)

        // A single merged grid, in metres, makes foot sliding visible.
        var grid = HeroMeshBuilder()
        for x in -25..<25 {
            for z in -35..<20 {
                grid.add(MeshTemplates.cube, trs(V3(Float(x) + 0.5, -0.012, Float(z) + 0.5), qIdentity,
                                               V3(1, 0.02, 1)), (x + z) % 2 == 0 ? .primary : .secondary)
            }
        }
        var floorA = PhysicallyBasedMaterial()
        floorA.baseColor = .init(tint: UIColor(red: 0.28, green: 0.34, blue: 0.29, alpha: 1))
        floorA.roughness = 0.95
        var floorB = floorA
        floorB.baseColor = .init(tint: UIColor(red: 0.25, green: 0.31, blue: 0.27, alpha: 1))
        var mats = [RealityKit.Material](repeating: floorA, count: HeroMat.allCases.count)
        mats[Int(HeroMat.secondary.rawValue)] = floorB
        if let mesh = grid.makeMesh(name: "hero.review.grid") {
            anchor.addChild(ModelEntity(mesh: mesh, materials: mats))
        }
        for name in ["hero.review.anchor", "hero.review.camera", "hero.review.sun", "hero.review.fill", "hero.review.floor"] {
            AssetLedger.record(.entity, name)
        }
        view.scene.addAnchor(anchor)
        caption.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        caption.textColor = .white
        caption.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        caption.numberOfLines = 3
        caption.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(caption)
        NSLayoutConstraint.activate([
            caption.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            caption.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        subscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(Float(event.deltaTime))
        }
        tick(0)
        return view
    }

    private func write(_ name: String, _ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    private func tick(_ delta: Float) {
        guard let model, !finished else { return }
        let dt = min(max(0, delta), 1 / 15)
        warmed += dt
        if warmed > 3, !ready {
            ready = true
            write("ready.json", ["sequence": 1, "heroID": heroID, "duration": Self.duration, "close": close,
                "pitch": CameraRig.pitchDegrees, "fov": CameraRig.fovDegrees, "distance": CameraRig.baseDistance,
                "triangles": model.triangleCount, "entities": model.entityCount,
                "note": "RealityKit review stage; battle lens and lights. Not gameplay or physical-device FPS."])
        }
        if ready, !started, FileManager.default.fileExists(atPath: dir.appendingPathComponent("go").path) { started = true }
        if started { time += dt }
        let t = time
        var speed: Float = 0
        var position = V3.zero
        var facing: Float = .pi * 0.75
        var label = "IDLE"
        if t >= 2, t < 7 {
            let u = t - 2
            let travel: Float
            if u < 0.4 { speed = 3.375 * u / 0.4; travel = 3.375 * u * u / 0.8 }
            else if u < 4 { speed = 3.375; travel = 3.375 * (u - 0.2) }
            else { let v = u - 4; speed = 3.375 * (1 - v); travel = 3.375 * (3.8 + v - v * v / 2) }
            position = ry(facing).act(V3(0, 0, -travel))
            label = u < 0.4 ? "START" : (u < 4 ? "RUN 3.375 m/s" : "STOP")
        } else if t >= 7, t < 14 {
            let u = min(4, max(0, t - 8))
            let angle = u * .pi / 2
            position = V3(2.15 * sin(angle), 0, 2.15 * (cos(angle) - 1))
            facing = angle - .pi / 2
            speed = t >= 8 && t < 12 ? 3.375 : 0
            label = speed > 0 ? "TURN / REVERSE" : "SETTLE"
        } else if heroID == "H028", t >= 23, t < 25 {
            position = ry(facing).act(V3(0, 0, -3 * min(1, (t - 23) / 0.2)))
            speed = t < 23.2 ? 15 : 0
        } else if heroID == "H028", t >= 26, t < 29 {
            position = ry(facing).act(V3(0, 0, -3 * min(1, (t - 26) / 0.18)))
            speed = t < 26.18 ? 17 : 0
            label = "ULT / 3 STRIKES / LAND"
        } else if t >= 26, t < 29 {
            speed = t < 28 ? 3.375 : 3.375 * (29 - t)
            position = ry(facing).act(V3(0, 0, -3.375 * (min(2, t - 26) + max(0, t - 28) - pow(max(0, t - 28), 2) / 2)))
            label = "ULT + MOVE / STOP"
        }
        // Position is a pure function of review time, not accumulated frame motion.
        // Cuts between sections are intentional and identical in every recording.
        model.root.position = position
        yaw = approachAngle(yaw, facing, rate: 13, dt: dt)
        model.root.orientation = ry(yaw)
        let distance = CameraRig.baseDistance * (close ? 0.38 : 1)
        camera.position = position + CameraRig.offset(distance: distance) + V3(0, 0, -CameraRig.focusLead)

        var event = -1
        if t >= 14 && t < 20 { event = 100 + Int((t - 14) / (t < 17 ? 1 : 0.5)); label = t < 17 ? "ATTACK" : "FAST ATTACK" }
        else if t >= 20 && t < 22 { event = 1; label = "S1" }
        else if t >= 23 && t < 25 { event = 2; label = "S2" }
        else if t >= 26 && t < 27 { event = 3 }
        else if t >= 30 && t < 31 { event = 4; label = "HIT" }
        else if t >= 31 && t < 32 { event = 5; label = "HIT RECOVERY" }
        else if t >= 33 { event = 6; label = "DEATH / HOLD" }
        if event != action {
            action = event
            if event >= 100 {
                model.playAttack(windup: 0.3, interval: t < 17 ? 1 : 0.5)
                releaseAt = t + 0.3
            } else {
                switch event {
                case 1: model.playCast(.skill1, stage: 0)
                case 2: model.playCast(.skill2, stage: 0)
                case 3:
                    model.playCast(.ultimate, stage: 0)
                    if heroID == "H028" { castHitAt = t + 0.18 }
                case 4, 5: model.reactToHit(direction: [0, 0, 1], strength: 0.8)
                case 6: model.setState(.dead)
                default: model.setState(speed > 0.2 ? .run : .idle)
                }
            }
        }
        if event < 0 { model.setState(speed > 0.2 ? .run : .idle) }
        if let releaseAt, t >= releaseAt { model.synchronizeAttackRelease(); self.releaseAt = nil }
        if let castHitAt, t >= castHitAt { model.playCastHit(.ultimate); self.castHitAt = nil }
        model.update(dt: started ? Double(dt) : 0, moveSpeed: Double(speed) * Balance.unitsPerMeter)
        caption.text = String(format: " %@ · %@ · %.2fs \n %@ \n RealityKit review stage · fixed battle lights ",
                              heroID, close ? "DETAIL" : "BATTLE CAMERA 1×", t, label)
        if t >= Self.duration {
            finished = true
            write("done.json", ["elapsed": t, "sequence": 1, "completed": true])
        }
    }
}
#endif
