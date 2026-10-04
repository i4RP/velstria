import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。頭上の HP バー（画面に平行なビルボード）。
// 深度テストなしで常に最前面に描き、描画順は ModelSortGroup で固定する（背景 → 遅延 → HP → シールド → 文字）。
// 1 m ≒ 36pt（cameraZoom = 1、iPhone 横画面）を目安に寸法を決める。

enum OverlayOrder {
    /// 地面デカール・頭上 UI の描画順グループ。半透明で深度を書かない地面の表示は全てこのグループに入れ、
    /// 前後関係を高さや距離ソートではなくこの順で固定する（グループ外の半透明物との順序は未定義のため）。
    static let group = ModelSortGroup(depthPass: nil)
    static let groundDetail: Int32 = -3
    static let water: Int32 = -2
    /// 霧より先に描く地面デカール（霧で覆われるべきもの: ミニオン・モンスターの接地影）。
    static let groundDecal: Int32 = -1
    static let fog: Int32 = 0
    static let zoneFill: Int32 = 1
    static let zoneEdge: Int32 = 2
    /// 選択リング（味方・敵）。
    static let ring: Int32 = 3
    /// 自ヒーローのリング（味方のリングと重なっても常に上: 同じ順だと重なりの色が入れ替わって見える）。
    static let selfRing: Int32 = 4
    /// ヒーローの丸影・チームリング・正面の矢印（1 つのエンティティ）。選択リングより上に描いて向きの矢印を隠さない。
    static let unitMarker: Int32 = 5
    /// 帰還・奥義の足元の輪（自分のリングより上）。
    static let castRing: Int32 = 6
    static let rangeRing: Int32 = 7
    static let vfxRing: Int32 = 8
    static let aim: Int32 = 9
    static let barBack: Int32 = 20
    static let barLag: Int32 = 21
    static let barFill: Int32 = 22
    static let barShield: Int32 = 23
    static let barFront: Int32 = 24
    static let barText: Int32 = 25

    static func apply(_ e: Entity, _ order: Int32) {
        e.components.set(ModelSortGroupComponent(group: group, order: order))
        // 地面の表示・頭上 UI は影を落とさない（影マップの薄い板が動くとちらつく）
        e.components.set(DynamicLightShadowComponent(castsShadow: false))
    }
}

/// 文字メッシュのキャッシュ（名前・レベル）。
@MainActor
final class TextMeshCache {
    struct Entry {
        let mesh: MeshResource
        /// 中央寄せ用の x オフセットと幅。
        let offsetX: Float
        let width: Float
        let offsetY: Float
    }

    private var cache: [String: Entry] = [:]

    func mesh(_ text: String, size: Float) -> Entry? {
        let key = "\(size)|\(text)"
        if let e = cache[key] { return e }
        let base = UIFont.systemFont(ofSize: CGFloat(size), weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: CGFloat(size)) } ?? base
        let mesh = MeshResource.generateText(text, extrusionDepth: 0.001, font: font, containerFrame: .zero,
                                             alignment: .center, lineBreakMode: .byTruncatingTail)
        let b = mesh.bounds
        let e = Entry(mesh: mesh, offsetX: -(b.min.x + b.max.x) / 2, width: b.max.x - b.min.x, offsetY: -(b.min.y + b.max.y) / 2)
        cache[key] = e
        return e
    }
}

@MainActor
final class OverheadBar {
    enum Style {
        case hero(isSelf: Bool, showResource: Bool)
        case minion
        case monster(boss: Bool)
        case structure(core: Bool)
    }

    let root = Entity()
    private let back: ModelEntity
    private let lag: ModelEntity
    private let fill: ModelEntity
    private let shield: ModelEntity
    private var resource: ModelEntity?
    private var levelText: ModelEntity?
    private var nameText: ModelEntity?
    private let width: Float
    private let height: Float
    private var shownHP: Float = -1
    private var lagHP: Float = 1
    private var lagHold: Float = 0
    private var shownShield: Float = -1
    private var shownResource: Float = -1
    private var shownLevel = -1
    private let text: TextMeshCache
    private let materials: RenderMaterials
    private var levelMaterial: UnlitMaterial

    init(style: Style, fillColor: RGB, materials: RenderMaterials, meshes: UnitMeshLibrary, text: TextMeshCache,
         name: String? = nil, resourceColor: RGB? = nil) {
        self.text = text
        self.materials = materials
        root.name = "bar"
        // 画面に平行なビルボード。カメラは回転しないので姿勢は一定（親は回転させない）。
        // BillboardComponent はワールド上方向を保つため、俯角 56° の画面端でバーが傾いて見える。
        root.orientation = CameraRig.orientation
        var w: Float, h: Float
        switch style {
        case .hero: w = 1.9; h = 0.22
        case .minion: w = 0.95; h = 0.11
        case .monster(let boss): w = boss ? 2.4 : 1.25; h = boss ? 0.2 : 0.13
        case .structure(let core): w = core ? 2.2 : 1.7; h = core ? 0.2 : 0.17
        }
        width = w
        height = h
        let quad = meshes.barQuad ?? MeshResource.generatePlane(width: 1, height: 1)
        let pad: Float = 0.035
        var totalH = h
        var showsResource = false
        if case .hero(_, let res) = style, res { totalH += 0.1; showsResource = true }

        back = ModelEntity(mesh: quad, materials: [materials.unlit(RGB(0.03, 0.04, 0.08), alpha: 0.88, depthTest: false)])
        back.position = [-w / 2 - pad, -(totalH - h) / 2, 0]
        back.scale = [w + pad * 2, totalH + pad * 2, 1]
        OverlayOrder.apply(back, OverlayOrder.barBack)
        root.addChild(back)

        lag = ModelEntity(mesh: quad, materials: [materials.unlit(RGB(1.0, 0.93, 0.78), alpha: 1, depthTest: false)])
        lag.position = [-w / 2, 0, 0]
        lag.scale = [w, h, 1]
        OverlayOrder.apply(lag, OverlayOrder.barLag)
        root.addChild(lag)

        fill = ModelEntity(mesh: quad, materials: [materials.unlit(fillColor, alpha: 1, depthTest: false)])
        fill.position = [-w / 2, 0, 0]
        fill.scale = [w, h, 1]
        OverlayOrder.apply(fill, OverlayOrder.barFill)
        root.addChild(fill)

        shield = ModelEntity(mesh: quad, materials: [materials.unlit(RGB(0.93, 0.95, 1.0), alpha: 1, depthTest: false)])
        shield.position = [w / 2, 0, 0]
        shield.scale = [0.0001, h, 1]
        shield.isEnabled = false
        OverlayOrder.apply(shield, OverlayOrder.barShield)
        root.addChild(shield)

        // 上端のハイライト（立体感）。数の多いミニオン等はドローコール節約のため省く
        if case .hero = style {
            let gloss = ModelEntity(mesh: quad, materials: [materials.unlit(RGB(1, 1, 1), alpha: 0.18, depthTest: false)])
            gloss.position = [-w / 2, h * 0.3, 0]
            gloss.scale = [w, h * 0.35, 1]
            OverlayOrder.apply(gloss, OverlayOrder.barFront)
            root.addChild(gloss)
        }

        if showsResource {
            let r = ModelEntity(mesh: quad, materials: [materials.unlit(resourceColor ?? RGB(0.35, 0.62, 1.0), alpha: 1, depthTest: false)])
            r.position = [-w / 2, -h / 2 - 0.065, 0]
            r.scale = [w, 0.07, 1]
            OverlayOrder.apply(r, OverlayOrder.barFill)
            root.addChild(r)
            resource = r
        }

        levelMaterial = materials.unlit(RGB(1, 0.94, 0.72), alpha: 1, depthTest: false)
        if case .hero(let isSelf, _) = style {
            // レベル章（左端）
            let badgeSize: Float = 0.4
            let badge = ModelEntity(mesh: quad, materials: [materials.unlit(RGB(0.03, 0.04, 0.08), alpha: 0.95, depthTest: false)])
            badge.position = [-w / 2 - pad - badgeSize, -(totalH - h) / 2, 0]
            badge.scale = [badgeSize, totalH + pad * 2 + 0.06, 1]
            OverlayOrder.apply(badge, OverlayOrder.barBack)
            root.addChild(badge)
            let edge = ModelEntity(mesh: quad, materials: [materials.unlit(isSelf ? TeamColors.gold : fillColor, alpha: 1,
                                                                            depthTest: false)])
            edge.position = [-w / 2 - pad - badgeSize, -(totalH - h) / 2 - (totalH + pad * 2 + 0.06) / 2 + 0.02, 0]
            edge.scale = [badgeSize, 0.04, 1]
            OverlayOrder.apply(edge, OverlayOrder.barFront)
            root.addChild(edge)
            let lt = ModelEntity()
            lt.position = [-w / 2 - pad - badgeSize / 2, -(totalH - h) / 2 + 0.01, 0.001]
            OverlayOrder.apply(lt, OverlayOrder.barText)
            root.addChild(lt)
            levelText = lt
            if let name, let e = text.mesh(name, size: 0.24) {
                let nt = ModelEntity(mesh: e.mesh, materials: [materials.unlit(isSelf ? RGB(1, 0.95, 0.78) : RGB(0.96, 0.97, 1.0),
                                                                             alpha: 1, depthTest: false)])
                let scale: Float = e.width > w + 0.3 ? (w + 0.3) / e.width : 1
                nt.scale = [scale, scale, 1]
                nt.position = [e.offsetX * scale - 0.2, h / 2 + 0.2 + e.offsetY * scale, 0.001]
                OverlayOrder.apply(nt, OverlayOrder.barText)
                root.addChild(nt)
                nameText = nt
            }
        }
    }

    /// この距離（m）で設計寸法どおりの大きさに見える。
    static let referenceDistance: Float = 11
    private var screenScale: Float = 1

    /// 画面上の大きさを一定に保つ（カメラからの距離に比例して拡縮。手前の構造物のバーが巨大化しない）。
    func keepScreenSize(camera: SIMD3<Float>) {
        let world = (root.parent?.position ?? .zero) + root.position
        let s = max(0.5, min(1.8, simd_distance(world, camera) / OverheadBar.referenceDistance))
        guard abs(s - screenScale) > 0.01 else { return }
        screenScale = s
        root.scale = SIMD3(repeating: s)
    }

    /// 表示中の値（テスト・デバッグ用）。
    var displayedHP: Float { shownHP }
    var displayedShield: Float { shownShield }
    var displayedLevel: Int { shownLevel }

    /// 値を反映する（変化時のみエンティティを更新）。hp/shield は最大 HP 比（shield は hp + shield ≤ 1 に収める）。
    func update(hp: Float, shield sh: Float, resource res: Float?, level: Int?, dt: Float) {
        let hpC = max(0, min(1, hp))
        let shC = max(0, min(1 - hpC, sh))
        if abs(hpC - shownHP) > 0.001 {
            if hpC < shownHP { lagHold = 0.35 }
            shownHP = hpC
            fill.scale.x = max(0.0001, width * hpC)
        }
        // 遅延バー（被弾直後に少し止まってから縮む）
        if lagHP < hpC {
            lagHP = hpC
            lag.scale.x = max(0.0001, width * lagHP)
        } else if lagHP > hpC + 0.001 {
            if lagHold > 0 {
                lagHold -= dt
            } else {
                lagHP = max(hpC, lagHP - dt * 0.9)
                lag.scale.x = max(0.0001, width * lagHP)
            }
        }
        if abs(shC - shownShield) > 0.001 {
            shownShield = shC
            shield.isEnabled = shC > 0.002
            shield.position.x = -width / 2 + width * hpC
            shield.scale.x = max(0.0001, width * shC)
        } else if shield.isEnabled {
            shield.position.x = -width / 2 + width * hpC
        }
        if let r = resource, let res {
            let v = max(0, min(1, res))
            if abs(v - shownResource) > 0.002 {
                shownResource = v
                r.scale.x = max(0.0001, width * v)
            }
        }
        if let level, level != shownLevel, let lt = levelText, let e = text.mesh("\(level)", size: 0.26) {
            shownLevel = level
            lt.components.set(ModelComponent(mesh: e.mesh, materials: [levelMaterial]))
            lt.position.x = -width / 2 - 0.035 - 0.2 + e.offsetX
            lt.position.y = -(resource != nil ? 0.05 : 0) + e.offsetY + 0.01
        }
    }

    /// 自分の HP バーとして色を変える（観戦の追従切替など）。
    func setFillColor(_ c: RGB) {
        fill.model?.materials = [materials.unlit(c, alpha: 1, depthTest: false)]
    }
}
