#if DEBUG || SCREENSHOTS
import Combine
import Foundation
import RealityKit
import simd
import SwiftUI
import UIKit
import VelstriaCore

/// Isolated, one-hero review of the shipping mesh, animation and first-person shader.
/// The host captures the displayed drawable; ARView.snapshot can omit transparent surfaces.
struct FirstPersonVisibilityReviewView: UIViewRepresentable {
    func makeCoordinator() -> FirstPersonVisibilityReviewDriver { .init() }
    func makeUIView(context: Context) -> ARView { context.coordinator.makeView() }
    func updateUIView(_ uiView: ARView, context: Context) {}
    static func dismantleUIView(_ uiView: ARView, coordinator: FirstPersonVisibilityReviewDriver) {
        coordinator.subscription?.cancel()
    }
}

@MainActor
final class FirstPersonVisibilityReviewDriver {
    var subscription: Cancellable?
    private weak var view: ARView?
    private let anchor = AnchorEntity(world: .zero)
    private let body = Entity()
    private let camera = PerspectiveCamera()
    private var model: (any HeroDisplayModel)?
    private var visibility: FirstPersonVisibility?
    private let heroID = DebugLaunch.value(after: "-fpsVisibilityHero") ?? "H001"
    private let sampleHz = min(60, max(1, Double(DebugLaunch.value(after: "-fpsVisibilityHz") ?? "10") ?? 10))
    private let handshake = URL(fileURLWithPath: DebugLaunch.value(after: "-fpsVisibilityHandshake")
                                ?? "/tmp/velstria-fpsvisibility", isDirectory: true)
    private var output: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fpsvisibility/\(heroID)", isDirectory: true)
    }

    private struct Scenario {
        var name: String
        var state: HeroAnimState
        var duration: Double
        var speed: Double = 0
        var slot: SkillSlot? = nil
        var stage = 0
        var attack = false
        var empowered = false
        var hit = false
        var pitch: Float = 0
    }
    private var scenarios: [Scenario] = []
    private var scenarioIndex = -1
    private var sample = 0
    private var elapsed: Double = 0
    private var didRelease = false
    private var didHit = false
    private var warmFrames = 60
    private var settleFrames = 0
    private var pending: [String: Any]?
    private var awaiting: [String: Any]?
    private var awaitingSince = Date()
    private var nextID = 0
    private var records: [[String: Any]] = []
    private var worstCoverage: Double = -1
    private var finished = false

    func makeView() -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        self.view = view
        view.environment.background = .color(.black)
        view.renderOptions.formUnion([.disableMotionBlur, .disableDepthOfField])
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "fps_visibility_review"
        try? FileManager.default.createDirectory(at: handshake, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        guard let definition = MasterData.shared.hero(heroID) else {
            fail("Unknown hero: \(heroID)")
            return view
        }
        let hero = HeroModelLibrary.makeHero(heroID: heroID, skinID: nil, team: .neutral, master: .shared,
                                             options: .init(teamMarker: false, shadow: false, aura: false))
        hero.prepareFirstPerson()
        hero.setFirstPerson(true)
        body.addChild(hero.root)
        body.components.set(OpacityComponent(opacity: HeroVisual.firstPersonOpacity))
        anchor.addChild(body)
        model = hero
        visibility = FirstPersonVisibility(root: body)
        camera.camera = PerspectiveCameraComponent(near: CameraRig.firstPersonNear, far: 160,
            fieldOfViewInDegrees: CameraRig.firstPersonFOV, fieldOfViewOrientation: .vertical)
        anchor.addChild(camera)
        let sun = DirectionalLight()
        sun.light.intensity = 3400
        sun.light.color = UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
        sun.look(at: .zero, from: [-0.55, 1, -0.45], relativeTo: nil)
        anchor.addChild(sun)
        let fill = DirectionalLight()
        fill.light.intensity = 900
        fill.light.color = UIColor(red: 0.62, green: 0.74, blue: 1, alpha: 1)
        fill.look(at: .zero, from: [0.6, 0.8, 0.7], relativeTo: nil)
        anchor.addChild(fill)
        view.scene.addAnchor(anchor)
        makeScenarios(hero: hero, runSpeed: definition.moveSpeed / Balance.unitsPerMeter)
        for name in ["fps.review.anchor", "fps.review.body", "fps.review.camera", "fps.review.sun", "fps.review.fill"] {
            AssetLedger.record(.entity, name)
        }
        hero.update(dt: 0, moveSpeed: 0)
        setCamera(pitch: 0)
        visibility?.update(enabled: true, pitch: 0, mask: true)
        subscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in self?.tick() }
        return view
    }

    private func makeScenarios(hero: any HeroDisplayModel, runSpeed: Double) {
        let bp = HeroBlueprints.blueprint(heroID: heroID, role: MasterData.shared.hero(heroID)?.role)
        let metrics = HeroModelLibrary.meshSet(heroID: heroID, blueprint: bp).metrics
        let profile = HeroMotionProfile(blueprint: bp, metrics: metrics, heroID: heroID)
        let motion = HeroMotionSets.set(heroID: heroID)
        let library = HeroMotionClips.library(heroID: heroID)
        func clipDuration(_ name: String?) -> Float {
            guard let name, let index = library.index(of: name) else { return 0 }
            return library.clips[index].duration
        }
        scenarios = [
            Scenario(name: "idle", state: .idle,
                     duration: Double(max(profile.idle?.gesturePeriod ?? 4, clipDuration(motion?.idle)))),
            Scenario(name: "walk", state: .run, duration: 3, speed: 1.2),
            Scenario(name: "run", state: .run, duration: 3, speed: runSpeed),
        ]
        let interval = Double(max(0.8, profile.attack.total, profile.attackMotions.map(\.total).max() ?? 0))
        let attacks = max(2, max(profile.attackMotions.count, motion?.attacks.count ?? 0))
        for variant in 0..<attacks {
            scenarios.append(Scenario(name: "attack_\(variant)", state: .attack, duration: interval + 0.2, attack: true))
        }
        scenarios.append(Scenario(name: "passive_empowered", state: .attack,
                                  duration: Double(max(Float(interval), profile.empoweredAttack?.total ?? 0)) + 0.2,
                                  attack: true, empowered: true))
        for (index, slot) in SkillSlot.actives.enumerated() {
            let stages = max(profile.recasts[index].count, motion?.stageCasts[index] == nil ? 0 : 1)
            for stage in 0...stages {
                let label = ["skill1", "skill2", "ultimate"][index] + (stage == 0 ? "" : "_recast\(stage)")
                scenarios.append(Scenario(name: label, state: .cast(slot),
                                          duration: Double(hero.castDuration(slot, stage: stage)) + 0.3,
                                          slot: slot, stage: stage))
            }
            let hitDuration = max(profile.hitFollowUps[index]?.total ?? 0, clipDuration(motion?.castHits[index]))
            if hitDuration > 0 {
                scenarios.append(Scenario(name: ["skill1", "skill2", "ultimate"][index] + "_hit",
                                          state: .cast(slot), duration: Double(hero.castDuration(slot)) + Double(hitDuration) + 0.3,
                                          slot: slot, hit: true))
            }
        }
        scenarios.append(Scenario(name: "look_down", state: .idle, duration: 0,
                                  pitch: -80 * .pi / 180))
    }

    private func tick() {
        guard !finished, model != nil, let visibility else { return }
        if warmFrames > 0 {
            warmFrames -= 1
            if warmFrames == 0 {
                guard visibility.isReady, visibility.unsupportedMaterialCount == 0, visibility.preparedModelCount > 0 else {
                    fail("First-person shader unavailable or unsupported materials")
                    return
                }
                beginNextScenario()
            }
            return
        }
        if let request = awaiting {
            let done = handshake.appendingPathComponent("done.json")
            if let data = try? Data(contentsOf: done),
               let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               response["id"] as? Int == request["id"] as? Int {
                try? FileManager.default.removeItem(at: done)
                awaiting = nil
                if let error = response["error"] as? String { fail(error); return }
                if request["kind"] as? String == "mask" {
                    guard let coverage = response["coverage"] as? Double, coverage.isFinite else {
                        fail("Missing finite pixel occupancy from capture host")
                        return
                    }
                    var result = request
                    result["coverage"] = coverage
                    result["occupiedPixels"] = response["occupiedPixels"]
                    result["totalPixels"] = response["totalPixels"]
                    records.append(result)
                    if coverage > worstCoverage {
                        worstCoverage = coverage
                        queueCapture(kind: "color")
                        return
                    }
                }
                advanceSample()
            } else if Date().timeIntervalSince(awaitingSince) > 90 {
                fail("Capture host did not acknowledge sample")
            }
            return
        }
        if settleFrames > 0 { settleFrames -= 1; return }
        if var request = pending, let view, let window = view.window {
            let rect = view.convert(view.bounds, to: window)
            request["viewport"] = [Double(rect.minX / window.bounds.width), Double(rect.minY / window.bounds.height),
                                   Double(rect.width / window.bounds.width), Double(rect.height / window.bounds.height)]
            request["shaderReady"] = visibility.isReady
            request["preparedModels"] = visibility.preparedModelCount
            request["unsupportedMaterials"] = visibility.unsupportedMaterialCount
            write(request, to: handshake.appendingPathComponent("request.json"))
            awaiting = request
            awaitingSince = Date()
            pending = nil
        }
    }

    private func beginNextScenario() {
        scenarioIndex += 1
        guard scenarioIndex < scenarios.count else { finish(); return }
        guard let model else { return }
        let scenario = scenarios[scenarioIndex]
        model.setState(.idle)
        model.update(dt: 1, moveSpeed: 0)
        model.root.position = .zero
        sample = 0
        elapsed = 0
        didRelease = false
        didHit = false
        worstCoverage = -1
        if scenario.attack {
            // Procedural HeroModel uses the protocol's no-op playAttack; its state still drives the swing.
            model.setState(.attack)
            model.playAttack(windup: 0.25, interval: max(0.5, scenario.duration - 0.2), empowered: scenario.empowered)
        } else if let slot = scenario.slot {
            model.playCast(slot, stage: scenario.stage)
        } else {
            model.setState(scenario.state)
        }
        model.update(dt: 0, moveSpeed: scenario.speed * Balance.unitsPerMeter)
        queueCapture(kind: "mask")
    }

    private func advanceSample() {
        guard let model else { return }
        let scenario = scenarios[scenarioIndex]
        guard elapsed < scenario.duration - 0.0001 else { beginNextScenario(); return }
        sample += 1
        let target = min(scenario.duration, Double(sample) / sampleHz)
        while elapsed < target - 0.000001 {
            let dt = min(1.0 / 60, target - elapsed)
            elapsed += dt
            model.root.position.z = -Float(scenario.speed * elapsed)
            model.update(dt: dt, moveSpeed: scenario.speed * Balance.unitsPerMeter)
            if scenario.attack, !didRelease, elapsed >= 0.25 {
                model.synchronizeAttackRelease()
                didRelease = true
            }
            if scenario.hit, !didHit, let slot = scenario.slot, elapsed >= Double(model.castDuration(slot)) * 0.5 {
                _ = model.playCastHit(slot)
                didHit = true
            }
        }
        queueCapture(kind: "mask")
    }

    private func setCamera(pitch: Float) {
        guard let model else { return }
        camera.position = model.root.convert(position: model.firstPersonEyeOffset, to: nil)
        camera.orientation = simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    private func queueCapture(kind: String) {
        let scenario = scenarios[scenarioIndex]
        guard let opacity = body.components[OpacityComponent.self]?.opacity,
              opacity.isFinite, abs(opacity - 0.5) < 0.0001 else {
            fail("Displayed self-model does not have the required 0.5 opacity component")
            return
        }
        let mask = kind == "mask"
        setCamera(pitch: scenario.pitch)
        visibility?.update(enabled: true, pitch: scenario.pitch, mask: mask)
        view?.environment.background = .color(mask ? .black : UIColor(red: 0.18, green: 0.24, blue: 0.27, alpha: 1))
        nextID += 1
        pending = ["id": nextID, "hero": heroID, "scenario": scenario.name, "kind": kind,
                   "sample": sample, "time": elapsed, "pitch": Double(scenario.pitch),
                   "opacity": Double(opacity), "fov": Double(CameraRig.firstPersonFOV),
                   "near": Double(CameraRig.firstPersonNear), "sampleHz": sampleHz,
                   "skinned": model?.isSkinned ?? false, "modelState": String(describing: model?.state)]
        settleFrames = 4
    }

    private func write(_ value: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func fail(_ reason: String) {
        finished = true
        write(["hero": heroID, "completed": false, "error": reason], to: output.appendingPathComponent("manifest.json"))
        write(["hero": heroID, "completed": false, "error": reason], to: handshake.appendingPathComponent("finished.json"))
    }

    private func finish() {
        for scenario in scenarios where scenario.slot != nil {
            guard records.contains(where: { $0["scenario"] as? String == scenario.name }) else {
                fail("Cast scenario produced no captured poses: \(scenario.name)")
                return
            }
        }
        for slot in SkillSlot.actives {
            guard scenarios.contains(where: { $0.slot == slot && $0.stage == 0 }) else {
                fail("Missing active skill scenario: \(slot.masterName)")
                return
            }
        }
        finished = true
        let forward = records.filter { ($0["pitch"] as? Double ?? -1) == 0 }
        let maximum = forward.compactMap { $0["coverage"] as? Double }.max() ?? 1
        let manifest: [String: Any] = ["hero": heroID, "completed": true, "sampleHz": sampleHz, "schemaVersion": 2,
            "currentPlayableRoster": MasterData.shared.heroes.map(\.heroID).sorted(),
            "allHeroRoster": MasterData.shared.allHeroes.map(\.heroID).sorted(),
            "integrationHz": 60, "opacity": records.first?["opacity"] ?? 0, "forwardLimit": 0.1,
            "forwardMaximum": maximum, "passedForwardLimit": maximum < 0.1,
            "scenarios": scenarios.map(\.name), "samples": records,
            "environment": "iPhone simulator, isolated RealityKit drawable; not physical-device evidence",
            "metric": "Any nonblack self-mesh pixel counts in full, including 50% transparent pixels; no alpha weighting"]
        write(manifest, to: output.appendingPathComponent("manifest.json"))
        write(["hero": heroID, "completed": true], to: handshake.appendingPathComponent("finished.json"))
    }
}
#endif
