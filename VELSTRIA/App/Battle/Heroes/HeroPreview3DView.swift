import Foundation
import RealityKit
import SwiftUI
import UIKit
import VelstriaCore

// 担当: hero-models。3D プレビュー（ヒーロー詳細・ホーム用）と、ギャラリー用の複数体ステージ。

/// ヒーロー詳細画面などで使う 3D プレビュー。台座の上でゆっくり回転し、横ドラッグで回せる。背景は透明。
/// 視差効果を減らす（Reduce Motion）が有効な時は自動回転しない（ドラッグでは回せる）。
struct HeroPreview3DView: View {
    let heroID: String
    var skinID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HeroStageView(config: HeroStageConfig(slots: [HeroStageSlot(heroID: heroID, skinID: skinID)],
                                              pedestal: true, autoRotate: !reduceMotion))
            .accessibilityElement()
            .accessibilityLabel(MasterData.shared.hero(heroID).map { MasterText.hero($0) } ?? heroID)
            .accessibilityIdentifier("hero_preview_3d")
    }
}

// MARK: - ステージ

struct HeroStageSlot: Equatable {
    var heroID: String
    var skinID: String?
}

enum HeroStageCamera: Equatable {
    /// 正面やや上からの展示用。
    case showcase
    /// 戦闘カメラに近い見下ろし（小さく表示して視認性を確認する）。
    case battle
}

struct HeroStageConfig: Equatable {
    var slots: [HeroStageSlot]
    var team: Team = .neutral
    var state: HeroAnimState = .idle
    var camera: HeroStageCamera = .showcase
    var pedestal = false
    var autoRotate = false
    /// 走行状態のときの速度（sim ユニット/秒）。
    var runSpeed: Double = 330
    /// 指定すると、その秒数だけ進めた姿勢で静止する（スクリーンショット用）。
    var freezeAt: Double?
    /// 戦闘カメラ時に頭上 UI 位置の目印を出す。
    var showOverheadMarker = false
    /// 台の初期回転（ラジアン、0 = 正面）。
    var yaw: Float = 0
}

/// RealityView の中身を保持する（フレーム更新・ドラッグ回転）。
@MainActor
final class HeroStageDriver {
    /// SwiftUI の再評価で何度も生成されうるため、エンティティは RealityView の make で初めて作る。
    private(set) lazy var world: Entity = {
        let w = Entity()
        w.addChild(turntable)
        w.addChild(camera)
        HeroStageDriver.addLights(to: w)
        return w
    }()
    private lazy var turntable = Entity()
    private lazy var camera = PerspectiveCamera()
    private(set) var models: [HeroModel] = []
    private var slotRoots: [Entity] = []
    var subscription: EventSubscription?
    var config: HeroStageConfig?
    var aspect: Float = 1.6
    var dragYaw: Float = 0
    var dragBaseYaw: Float = 0
    var isDragging = false
    /// 縦方向のドラッグ（スクロール）と判定した間は回転させない。
    var isDragIgnored = false
    /// 画面に表示されている間だけ進める（NavigationStack で奥へ遷移している間は止め、戻ったら再開する）。
    /// フレーム更新の購読は RealityView の make でしか作れないため、非表示でも解除せずこのフラグで止める。
    var isActive = true
    /// 非表示から戻った直後などの大きな dt で姿勢が飛ばないようにする上限（秒）。
    static let maxTickDelta: Double = 1.0 / 15.0
    private var autoYaw: Float = 0
    private var swayTime: Float = 0
    /// 並べた内容の最上端（m）。カメラの収まりに使う。
    private var contentTop: Float = 2.0
    private var frozen = false

    func apply(_ c: HeroStageConfig) {
        if config?.slots != c.slots || config?.team != c.team || config?.pedestal != c.pedestal
            || config?.freezeAt != c.freezeAt || config?.showOverheadMarker != c.showOverheadMarker {
            rebuild(c)
        } else if config?.state != c.state {
            for m in models { m.setState(c.state) }
        }
        config = c
        layout()
    }

    private func rebuild(_ c: HeroStageConfig) {
        for r in slotRoots { r.removeFromParent() }
        slotRoots.removeAll()
        models.removeAll()
        let master = MasterData.shared
        let options = HeroModelOptions(teamMarker: c.team != .neutral, shadow: !c.pedestal, colorblind: false, aura: true)
        for slot in c.slots {
            let holder = Entity()
            let model = HeroModelLibrary.makeHero(heroID: slot.heroID, skinID: slot.skinID, team: c.team,
                                                  master: master, options: options)
            holder.addChild(model.root)
            if c.pedestal {
                let p = HeroStageDriver.makePedestal(glow: HSB(Theme.heroHue(slot.heroID), 0.6, 1))
                holder.addChild(p)
                model.root.position.y = HeroStageDriver.pedestalHeight
            }
            if c.showOverheadMarker {
                let mk = ModelEntity(mesh: .generateBox(size: [0.6, 0.05, 0.02], cornerRadius: 0.01),
                                     materials: [UnlitMaterial(color: .systemGreen)])
                mk.position = [0, model.overheadHeight, 0]
                holder.addChild(mk)
            }
            model.setState(c.state)
            turntable.addChild(holder)
            slotRoots.append(holder)
            models.append(model)
        }
        contentTop = 2.0
        for h in slotRoots {
            let b = h.visualBounds(recursive: true, relativeTo: h, excludeInactive: false)
            if b.max.y.isFinite { contentTop = max(contentTop, min(3.2, b.max.y)) }
        }
        frozen = false
        if let f = c.freezeAt {
            let steps = max(1, Int(f / (1.0 / 60.0)))
            let speed = c.state == .run ? c.runSpeed : 0
            for _ in 0..<steps { for m in models { m.update(dt: f / Double(steps), moveSpeed: speed) } }
            frozen = true
        }
    }

    /// 横一列に並べ、カメラを合わせる。
    func layout() {
        guard let c = config else { return }
        let n = max(1, slotRoots.count)
        let spacing: Float = c.camera == .battle ? 1.7 : (c.pedestal ? 1.9 : 1.55)
        for (i, r) in slotRoots.enumerated() {
            r.position = [(Float(i) - Float(n - 1) / 2) * spacing, 0, 0]
        }
        let fovV: Float = c.camera == .battle ? 30 : 30
        camera.camera.fieldOfViewInDegrees = fovV
        let halfV = tan(fovV * .pi / 360)
        let halfH = halfV * max(0.3, aspect)
        let width = Float(n) * spacing
        switch c.camera {
        case .showcase:
            // 武器・浮遊物まで含めた全身が上下に余白を持って収まる距離
            let height = contentTop * 1.12 + 0.45
            let distW = (width / 2 + 0.3) / halfH
            let distH = (height / 2) / halfV
            let d = max(distW, distH) * 1.03
            let target = V3(0, contentTop * 0.5, 0)
            camera.look(at: target, from: target + V3(0, d * 0.12, d), relativeTo: nil)
        case .battle:
            // 戦闘カメラ相当（約 56° 見下ろし・遠景）
            let d: Float = max(15, (width / 2) / halfH * 1.05)
            let pitch: Float = 56 * .pi / 180
            let target = V3(0, 0.6, 0)
            camera.look(at: target, from: target + V3(0, sin(pitch) * d, cos(pitch) * d), relativeTo: nil)
        }
    }

    func tick(_ rawDelta: Double) {
        guard isActive, let c = config else { return }
        let dt = min(max(0, rawDelta), HeroStageDriver.maxTickDelta)
        if c.autoRotate && !isDragging {
            // 正面を中心にゆっくり左右へ回る（顔が見えている時間を長く）
            swayTime += Float(dt)
            autoYaw = 0.75 * sin(swayTime * 0.33)
        }
        // 各ヒーローをその場で回す（-Z 正面のモデルを +Z 側のカメラへ向けるため π を足す）
        let yaw = ry(.pi + c.yaw + autoYaw + dragYaw)
        for r in slotRoots { r.orientation = yaw }
        guard !frozen else { return }
        let speed = c.state == .run ? c.runSpeed : 0
        for m in models { m.update(dt: dt, moveSpeed: speed) }
    }

    // MARK: 照明・台座

    static let pedestalHeight: Float = 0.16

    private static func addLights(to world: Entity) {
        let key = DirectionalLight()
        key.light.color = UIColor(red: 1.0, green: 0.95, blue: 0.88, alpha: 1)
        key.light.intensity = 3200
        key.look(at: .zero, from: [-2.2, 4.0, 3.2], relativeTo: nil)
        world.addChild(key)

        let fill = DirectionalLight()
        fill.light.color = UIColor(red: 0.7, green: 0.8, blue: 1.0, alpha: 1)
        fill.light.intensity = 1300
        fill.look(at: .zero, from: [3.0, 1.2, 2.4], relativeTo: nil)
        world.addChild(fill)

        let rim = DirectionalLight()
        rim.light.color = UIColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 1)
        rim.light.intensity = 2600
        rim.look(at: .zero, from: [0.8, 2.6, -3.5], relativeTo: nil)
        world.addChild(rim)

        let under = DirectionalLight()
        under.light.color = UIColor(red: 0.6, green: 0.55, blue: 1.0, alpha: 1)
        under.light.intensity = 450
        under.look(at: [0, 1, 0], from: [0, -2, 2], relativeTo: nil)
        world.addChild(under)
    }

    private static var pedestalMeshes: MeshResource?
    private static let floorGlowMesh = MeshResource.generatePlane(width: 2.8, depth: 2.8)

    static func makePedestal(glow: HSB) -> Entity {
        let mesh: MeshResource
        if let m = pedestalMeshes {
            mesh = m
        } else {
            var b = HeroMeshBuilder()
            let top = pedestalHeight
            b.lathe([V2(0.72, 0.0), V2(0.74, 0.03), V2(0.7, top - 0.03), V2(0.66, top), V2(0.0, top)], .zero, .primary,
                    segments: 40, capBottom: true)
            b.add(MeshTemplate.torus(minor: 0.02, segments: 48, sides: 6), trs(V3(0, top - 0.01, 0), qIdentity, V3(0.66, 0.66, 0.66)),
                  .glow)
            b.add(MeshTemplate.annulus(inner: 0.46, outer: 0.5, segments: 48, dashes: 16, dashFill: 0.5),
                  trs(V3(0, top + 0.002, 0)), .glow)
            mesh = b.makeMesh(name: "hero.pedestal") ?? MeshResource.generateCylinder(height: top, radius: 0.7)
            pedestalMeshes = mesh
        }
        var base = PhysicallyBasedMaterial()
        base.baseColor = .init(tint: UIColor(red: 0.12, green: 0.13, blue: 0.24, alpha: 1))
        base.roughness = .init(floatLiteral: 0.35)
        base.metallic = .init(floatLiteral: 0.6)
        base.emissiveColor = .init(color: UIColor(red: 0.12, green: 0.14, blue: 0.3, alpha: 1))
        base.emissiveIntensity = 0.4
        var materials = [RealityKit.Material](repeating: base, count: HeroMat.allCases.count)
        materials[Int(HeroMat.glow.rawValue)] = HeroMaterialLibrary.unlit(glow, opacity: 1)
        let pedestal = ModelEntity(mesh: mesh, materials: materials)
        // 足元の柔らかな光だまり
        let floor = ModelEntity(mesh: floorGlowMesh, materials: [HeroMaterialLibrary.glowSprite(glow)])
        floor.position.y = 0.004
        pedestal.addChild(floor)
        return pedestal
    }
}

/// 1 体または複数体のヒーローを並べる RealityView。
struct HeroStageView: View {
    let config: HeroStageConfig
    @State private var driver = HeroStageDriver()

    var body: some View {
        GeometryReader { geo in
            RealityView { content in
                content.camera = .virtual
                content.add(driver.world)
                driver.aspect = Float(geo.size.width / max(1, geo.size.height))
                driver.apply(config)
                driver.tick(0)
                driver.subscription?.cancel()
                driver.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak driver] e in
                    driver?.tick(e.deltaTime)
                }
            } update: { _ in
                driver.aspect = Float(geo.size.width / max(1, geo.size.height))
                driver.apply(config)
            }
            // 縦スクロールの中に置かれても縦のドラッグはスクロールに譲る（横ドラッグだけで回す）
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        if !driver.isDragging && !driver.isDragIgnored {
                            if abs(v.translation.width) > abs(v.translation.height) {
                                driver.isDragging = true
                                driver.dragBaseYaw = driver.dragYaw
                            } else {
                                driver.isDragIgnored = true
                            }
                        }
                        guard driver.isDragging else { return }
                        driver.dragYaw = driver.dragBaseYaw + Float(v.translation.width) * 0.012
                    }
                    .onEnded { _ in
                        driver.isDragging = false
                        driver.isDragIgnored = false
                    }
            )
        }
        // 購読は解除しない（make は再実行されないため、解除すると戻った後に止まったままになる）。
        // 非表示の間は tick を止め、RealityView が破棄されれば購読もシーンと一緒に無効になる。
        .onAppear { driver.isActive = true }
        .onDisappear { driver.isActive = false }
    }
}
