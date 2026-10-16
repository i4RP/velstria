import Foundation
import os
import RealityKit
import VelstriaCore

// 担当: battle-renderer。中立モンスターの動く生成モデル（tools/structures/creature_bake.py で作る Creature_<id>.usdz）。
// USDZ はスキン付きメッシュと動作 1 本（idle / walk / attack / hit を並べたタイムライン）。区間は Creature_<id>.json。
// 読み込みは StructureAssets と一緒に試合の準備中に 1 度だけ。試合中は template を複製して区間の AnimationResource を再生する。
// 読めない種類は nil（CreatureVisual は StructureAssets の静止モデル → 手続きメッシュの順に戻る）。

private let creatureAssetLog = Logger(subsystem: "com.bitcoinpay.velstria", category: "CreatureAssets")

@MainActor
enum CreatureAssets {
    enum Kind: String, CaseIterable, Sendable {
        case turtle = "monster_turtle"
        case lord = "monster_lord"
        case red = "monster_red"
        case purple = "monster_purple"
        case whelp = "monster_whelp"
        case wanderer = "monster_wanderer"
        case golem = "monster_golem"
        case beetle = "monster_beetle"
        case grub = "monster_grub"
        case crab = "monster_crab"
        case crablet = "monster_crablet"
        case lizard = "monster_lizard"

        var fileName: String { "Creature_\(rawValue)" }

        static func of(_ k: MonsterKind) -> Kind? {
            switch k {
            case .astralWyrm: return .turtle
            case .ancientColossus: return .lord
            case .redSentinel: return .red
            case .blueSentinel: return .purple
            case .azureWhelp: return .whelp
            case .mossWanderer: return .wanderer
            case .magmaGolem: return .golem
            case .emberBeetle: return .beetle
            case .emberGrub: return .grub
            case .treasureCrab: return .crab
            case .crablet: return .crablet
            case .hornLizard: return .lizard
            default: return nil
            }
        }

        /// 三角形の上限（docs/BATTLE_PERFORMANCE.md。ボス以外はキャンプごとに数体出る）。
        var triangleBudget: Int {
            switch self {
            case .turtle, .lord: return 6000
            case .red, .purple, .golem, .beetle, .crab, .lizard: return 5000
            case .whelp, .wanderer, .grub, .crablet: return 2800
            }
        }
    }

    enum Clip: String, CaseIterable, Sendable {
        case idle, walk, attack, hit
        var loops: Bool { self == .idle || self == .walk }
    }

    @MainActor
    final class Model {
        let kind: Kind
        let template: Entity
        /// 動作を持つエンティティの template からの子の番号の並び（複製で同じ位置を引く）。
        let animPath: [Int]
        let clips: [Clip: AnimationResource]
        let durations: [Clip: Float]

        init(kind: Kind, template: Entity, animPath: [Int], clips: [Clip: AnimationResource], durations: [Clip: Float]) {
            self.kind = kind
            self.template = template
            self.animPath = animPath
            self.clips = clips
            self.durations = durations
        }

        /// 表示用の複製と、動作を再生するエンティティ。
        func makeInstance() -> (root: Entity, animTarget: Entity) {
            AssetLedger.record(.entity, "creature model \(kind.rawValue)")
            let e = template.clone(recursive: true)
            var t = e
            for i in animPath where i < t.children.count { t = t.children[i] }
            return (e, t)
        }
    }

    private struct ClipFile: Decodable {
        let fps: Double
        let clips: [String: [Double]]
    }

    private static var models: [Kind: Model] = [:]
    private static var attempted = false
    static var isEnabled: Bool { StructureAssets.isEnabled && !ProcessInfo.processInfo.arguments.contains("-staticCreatures") }

    static func model(_ k: MonsterKind) -> Model? {
        guard isEnabled, let kind = Kind.of(k) else { return nil }
        return models[kind]
    }

    static var loadedModels: [Model] { Kind.allCases.compactMap { models[$0] } }

    /// StructureAssets.loadAll から呼ぶ（1 度だけ）。
    static func loadAll() async {
        guard isEnabled, !attempted else { return }
        attempted = true
        for kind in Kind.allCases where models[kind] == nil {
            if let m = await load(kind) { models[kind] = m }
        }
        creatureAssetLog.info("loaded \(models.count, privacy: .public)/\(Kind.allCases.count, privacy: .public)")
    }

    private static func load(_ kind: Kind) async -> Model? {
        guard let url = StructureAssets.resolver(kind.fileName, "usdz"),
              let jurl = StructureAssets.resolver(kind.fileName, "json"),
              let data = try? Data(contentsOf: jurl),
              let file = try? JSONDecoder().decode(ClipFile.self, from: data) else { return nil }
        do {
            let root = try await Entity(contentsOf: url)
            var tris = 0
            visit(root) { e in
                guard var mc = e.components[ModelComponent.self] else { return }
                tris += HeroAssetLibrary.triangleCount(mc.mesh)
                mc.materials = mc.materials.map { m in
                    guard var pbr = m as? PhysicallyBasedMaterial else { return m }
                    pbr.roughness = .init(floatLiteral: 0.7)
                    pbr.metallic = .init(floatLiteral: 0)
                    pbr.specular = .init(floatLiteral: 0.3)
                    pbr.emissiveIntensity = StructureAssets.emissiveIntensity
                    return pbr
                }
                e.components.set(mc)
            }
            if tris > kind.triangleBudget {
                creatureAssetLog.error("\(kind.fileName, privacy: .public): \(tris) 三角形（上限 \(kind.triangleBudget)）")
                return nil
            }
            guard let (owner, path) = animationOwner(root, path: []), let anim = owner.availableAnimations.first else {
                creatureAssetLog.error("\(kind.fileName, privacy: .public): 動作が無い")
                return nil
            }
            var clips: [Clip: AnimationResource] = [:]
            var durations: [Clip: Float] = [:]
            let frame = 1 / max(1, file.fps)
            for clip in Clip.allCases {
                guard let r = file.clips[clip.rawValue], r.count == 2 else { continue }
                let view = AnimationView(source: anim.definition, name: clip.rawValue, bindTarget: nil, blendLayer: 0,
                                         repeatMode: clip.loops ? .repeat : .none, fillMode: [],
                                         trimStart: r[0], trimEnd: r[1] + frame, trimDuration: nil,
                                         offset: 0, delay: 0, speed: 1)
                clips[clip] = try AnimationResource.generate(with: view)
                durations[clip] = Float(r[1] + frame - r[0])
            }
            guard clips[.idle] != nil else { return nil }
            AssetLedger.record(.mesh, kind.fileName)
            return Model(kind: kind, template: root, animPath: path, clips: clips, durations: durations)
        } catch {
            creatureAssetLog.error("\(kind.fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func resetForTesting() {
        models = [:]
        attempted = false
    }

    private static func visit(_ e: Entity, _ f: (Entity) -> Void) {
        f(e)
        for c in e.children { visit(c, f) }
    }

    private static func animationOwner(_ e: Entity, path: [Int]) -> (Entity, [Int])? {
        if !e.availableAnimations.isEmpty { return (e, path) }
        for (i, c) in e.children.enumerated() {
            if let r = animationOwner(c, path: path + [i]) { return r }
        }
        return nil
    }
}

/// 1 体分の動作の再生（待機・歩行は繰り返し、攻撃・被弾は 1 回流して戻る）。
@MainActor
final class CreatureAnimator {
    let model: CreatureAssets.Model
    let target: Entity
    private var current: CreatureAssets.Clip?
    private var controller: AnimationPlaybackController?
    private var oneShotLeft: Float = 0
    private var paused = false

    init(model: CreatureAssets.Model, target: Entity) {
        self.model = model
        self.target = target
    }

    /// 攻撃・被弾を流す（attack は最大 1.3 s に収まる速さ）。被弾は攻撃中なら流さない。
    func trigger(_ clip: CreatureAssets.Clip) {
        if clip == .hit, current == .attack, oneShotLeft > 0 { return }
        let d = model.durations[clip] ?? 0.5
        let speed: Float = clip == .attack ? max(1, d / 1.3) : 1
        play(clip, speed: speed, force: true)
        oneShotLeft = d / speed
    }

    func update(dt: Float, moving: Bool, visible: Bool) {
        if !visible {
            if !paused { controller?.pause(); paused = true }
            return
        }
        if paused { controller?.resume(); paused = false }
        if oneShotLeft > 0 {
            oneShotLeft -= dt
            if oneShotLeft > 0 { return }
        }
        play(moving && model.clips[.walk] != nil ? .walk : .idle, speed: 1, force: false)
    }

    func reset() {
        controller?.stop()
        controller = nil
        current = nil
        oneShotLeft = 0
        paused = false
    }

    private func play(_ clip: CreatureAssets.Clip, speed: Float, force: Bool) {
        guard force || clip != current, let res = model.clips[clip] else { return }
        controller = target.playAnimation(res, transitionDuration: 0.15, startsPaused: false)
        controller?.speed = speed
        current = clip
    }
}
