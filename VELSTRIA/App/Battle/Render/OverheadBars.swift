import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。頭上の HP バー（画面に平行なビルボード）。
// 壁・地形の深度を読み、パネル内の描画順は固定する（背景 → 遅延 → HP → シールド → 文字）。
// FPS は近くに見えているメッシュの頭上だけ。レベル章と陣営色の HP を小さく保つ。

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
    /// スキル演出の地面の模様（演出の輪より上、照準より下）。
    static let skillDecal: Int32 = 9
    static let aim: Int32 = 10
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

    /// 作成済みの文字メッシュ（ウォームアップの陳列用）。
    var builtMeshes: [MeshResource] { cache.keys.sorted().compactMap { cache[$0]?.mesh } }

    /// レベル表示（1〜最大レベル）と名前を作っておく（読み込み幕の裏。レベルアップの瞬間の CoreText 分割をなくす）。
    func prewarm(names: [String]) {
        for level in 1...Balance.maxLevel { _ = mesh("\(level)", size: OverheadBar.levelTextSize) }
        for name in names { _ = mesh(name, size: OverheadBar.nameTextSize) }
    }

    func mesh(_ text: String, size: Float) -> Entry? {
        let key = "\(size)|\(text)"
        if let e = cache[key] { return e }
        let base = UIFont.systemFont(ofSize: CGFloat(size), weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: CGFloat(size)) } ?? base
        AssetLedger.record(.textMesh, "\"\(text)\" size \(size)")
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
        case monster(boss: Bool, sentinel: Bool = false)
        case structure(core: Bool)
    }

    let root = Entity()
    private let back: ModelEntity
    private let lag: ModelEntity
    private let fill: ModelEntity
    private let shield: ModelEntity
    private var resource: ModelEntity?
    private var levelText: ModelEntity?
    private var executeMark: ModelEntity?
    func setExecutable(_ value: Bool) { executeMark?.isEnabled = value }
    private var nameText: ModelEntity?
    /// 草むらで隠れている印（ヒーローのみ。HP バーの右端。setConcealed で切り替える）。
    private var concealIcon: ModelEntity?
    /// HP の区切り目盛り（ヒーローのみ。MLBB のように一定量ごとの細い線。最大 tickPool 本を使い回す）。
    private var ticks: [ModelEntity] = []
    private var tickMaxHP: Float = -1
    private let width: Float
    private let height: Float
    /// 左のレベル章を含む全体をキャラの上に寄せる（HP部分の中心は少し右）。
    private let horizontalOffset: Float
    private var shownHP: Float = -1
    private var lagHP: Float = 1
    private var lagHold: Float = 0
    private var shownShield: Float = -1
    private var shownResource: Float = -1
    private var shownLevel = -1
    private let text: TextMeshCache
    private let materials: RenderMaterials
    private var levelMaterial: UnlitMaterial
    private var occlusionTick: Int?
    private var occlusionFrom = Vec2.zero
    private var occlusionTo = Vec2.zero
    private var wallVisible = false

    init(style: Style, fillColor: RGB, materials: RenderMaterials, meshes: UnitMeshLibrary, text: TextMeshCache,
         name: String? = nil, resourceColor: RGB? = nil) {
        self.text = text
        self.materials = materials
        if case .hero = style { horizontalOffset = 0.2 } else { horizontalOffset = 0 }
        root.name = "bar"
        root.position.x = horizontalOffset
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-stageLayoutReference") {
            root.components.set(OpacityComponent(opacity: 0))
        }
        #endif
        // 画面に平行なビルボード（親は回転させない）。FPS の見回しにも描画中の姿勢で追従する。
        root.orientation = Self.cameraOrientation
        var w: Float, h: Float
        switch style {
        case .hero: w = 1.65; h = 0.17
        case .minion: w = 0.88; h = 0.11
        case .monster(let boss, let sentinel):
            w = boss ? 3.1 : (sentinel ? 2.2 : 1.8)
            h = boss ? 0.18 : (sentinel ? 0.12 : 0.09)
        case .structure(let core): w = core ? 2.2 : 1.7; h = core ? 0.2 : 0.17
        }
        width = w
        height = h
        let quad = meshes.barQuad ?? MeshResource.generatePlane(width: 1, height: 1)
        let pad: Float = 0.035
        var totalH = h
        var showsResource = false
        if case .hero(_, let res) = style, res { totalH += 0.1; showsResource = true }

        back = ModelEntity(mesh: quad, materials: [materials.overhead(RGB(0.03, 0.04, 0.08), alpha: 0.94)])
        back.position = [-w / 2 - pad, -(totalH - h) / 2, 0]
        back.scale = [w + pad * 2, totalH + pad * 2, 1]
        OverlayOrder.apply(back, OverlayOrder.barBack)
        root.addChild(back)

        lag = ModelEntity(mesh: quad, materials: [materials.overhead(RGB(1.0, 0.93, 0.78))])
        lag.position = [-w / 2, 0, 0]
        lag.scale = [w, h, 1]
        OverlayOrder.apply(lag, OverlayOrder.barLag)
        root.addChild(lag)

        fill = ModelEntity(mesh: quad, materials: [materials.overhead(fillColor)])
        fill.position = [-w / 2, 0, 0]
        fill.scale = [w, h, 1]
        OverlayOrder.apply(fill, OverlayOrder.barFill)
        root.addChild(fill)

        shield = ModelEntity(mesh: quad, materials: [materials.overhead(RGB(0.93, 0.95, 1.0))])
        shield.position = [w / 2, 0, 0]
        shield.scale = [0.0001, h, 1]
        shield.isEnabled = false
        OverlayOrder.apply(shield, OverlayOrder.barShield)
        root.addChild(shield)

        // 上端のハイライト（立体感）。数の多いミニオン等はドローコール節約のため省く
        if case .hero = style {
            let gloss = ModelEntity(mesh: quad, materials: [materials.overhead(RGB(1, 1, 1), alpha: 0.18)])
            gloss.position = [-w / 2, h * 0.3, 0]
            gloss.scale = [w, h * 0.35, 1]
            OverlayOrder.apply(gloss, OverlayOrder.barFront)
            root.addChild(gloss)
        }

        if showsResource {
            let r = ModelEntity(mesh: quad, materials: [materials.overhead(resourceColor ?? RGB(0.35, 0.62, 1.0))])
            r.position = [-w / 2, -h / 2 - 0.065, 0]
            r.scale = [w, 0.07, 1]
            OverlayOrder.apply(r, OverlayOrder.barFill)
            root.addChild(r)
            resource = r
        }

        levelMaterial = materials.overhead(RGB(1, 0.97, 0.9))
        if case .hero(let isSelf, _) = style {
            // レベルの丸い章（左端。MLBB のように縁取りの丸の中に数字。バーの端に少し重ねる）
            let disc = meshes.barDisc ?? quad
            let badgeD: Float = 0.46
            let badgeX = -w / 2 - pad - 0.2
            let badgeY = -(totalH - h) / 2
            let rim = ModelEntity(mesh: disc, materials: [materials.overhead(isSelf ? TeamColors.gold : fillColor)])
            rim.position = [badgeX, badgeY, 0]
            rim.scale = [badgeD + 0.06, badgeD + 0.06, 1]
            OverlayOrder.apply(rim, OverlayOrder.barBack)
            root.addChild(rim)
            let badge = ModelEntity(mesh: disc, materials: [materials.overhead(RGB(0.03, 0.04, 0.08))])
            badge.position = [badgeX, badgeY, 0]
            badge.scale = [badgeD, badgeD, 1]
            OverlayOrder.apply(badge, OverlayOrder.barLag)
            root.addChild(badge)
            // HP の区切り目盛り（使う本数は最大 HP で決まる。update で並べ直す）
            let tickMaterial = materials.overhead(RGB(0.02, 0.03, 0.05), alpha: 0.7)
            for _ in 0..<OverheadBar.tickPool {
                let t = ModelEntity(mesh: quad, materials: [tickMaterial])
                t.scale = [0.022, h, 1]
                t.isEnabled = false
                OverlayOrder.apply(t, OverlayOrder.barFront)
                root.addChild(t)
                ticks.append(t)
            }
            let lt = ModelEntity()
            lt.position = [badgeX, badgeY + 0.01, 0.001]
            OverlayOrder.apply(lt, OverlayOrder.barText)
            root.addChild(lt)
            levelText = lt
            let mark = ModelEntity(mesh: quad, materials: [materials.overhead(RGB(1, 0.12, 0.12))])
            mark.position = [badgeX, badgeY, 0.004]
            mark.scale = [0.62, 0.05, 1]
            mark.orientation = simd_quatf(angle: .pi / 4, axis: [0, 0, 1])
            mark.isEnabled = false
            OverlayOrder.apply(mark, OverlayOrder.barText + 1)
            root.addChild(mark)
            executeMark = mark
            if let name, let e = text.mesh(name, size: OverheadBar.nameTextSize) {
                let nt = ModelEntity(mesh: e.mesh, materials: [materials.overhead(isSelf ? RGB(1, 0.95, 0.78) : RGB(0.96, 0.97, 1.0))])
                let scale: Float = e.width > w + 0.3 ? (w + 0.3) / e.width : 1
                nt.scale = [scale, scale, 1]
                nt.position = [e.offsetX * scale, h / 2 + 0.2 + e.offsetY * scale, 0.001]
                OverlayOrder.apply(nt, OverlayOrder.barText)
                root.addChild(nt)
                nameText = nt
            }
            if let eye = materials.concealEye {
                var material = eye.material
                material.readsDepth = true
                let e = ModelEntity(mesh: eye.mesh, materials: [material])
                e.position = [w / 2 + pad + 0.26, badgeY, 0.002]
                e.scale = [OverheadBar.concealIconSize, OverheadBar.concealIconSize, 1]
                e.isEnabled = false
                OverlayOrder.apply(e, OverlayOrder.barText)
                root.addChild(e)
                concealIcon = e
            }
        }
    }

    /// 草むらで隠れている印の直径（m。レベルの章と同じくらい）。
    static let concealIconSize: Float = 0.46

    /// 草むらで隠れている印を出すか。
    func setConcealed(_ on: Bool) {
        guard let e = concealIcon, e.isEnabled != on else { return }
        e.isEnabled = on
    }

    var isConcealIconShown: Bool { concealIcon?.isEnabled == true }

    /// HP の区切り目盛りの最大本数（ヒーロー 1 人あたりのエンティティ数の上限）。
    static let tickPool = 6

    /// 区切り目盛りの間隔（HP）。500 から始め、本数が tickPool を超えないよう 500 単位で広げる。
    static func tickStep(maxHP: Float) -> Float {
        let units = max(1, (maxHP / (Float(tickPool + 1) * 500)).rounded(.up))
        return 500 * units
    }

    /// 区切り目盛りの位置（最大 HP 比 0〜1。端と重なる目盛りは出さない）。
    static func tickFractions(maxHP: Float) -> [Float] {
        guard maxHP > 1 else { return [] }
        let step = tickStep(maxHP: maxHP)
        var out: [Float] = []
        var v = step
        while v < maxHP - step * 0.25, out.count < tickPool {
            out.append(v / maxHP)
            v += step
        }
        return out
    }

    /// レベル・名前の文字の大きさ（TextMeshCache のキー。事前生成と同じ値を使う）。
    static let levelTextSize: Float = 0.26
    static let nameTextSize: Float = 0.24
    /// バーの色（マテリアルの事前生成に使う）。
    static let monsterFill = RGB(0.96, 0.72, 0.24)
    static let dummyFill = RGB(0.95, 0.4, 0.4)

    /// この距離（m）で設計寸法どおりの大きさに見える。
    static let referenceDistance: Float = 19.8
    static let firstPersonMaxDistance: Float = 18
    /// 拡縮の上限（プレイヤーの倍率範囲。画面上端の遠いバーはこれ以上大きくしない）。
    static let maxScreenScale: Float = 1.8
    /// 観戦者が大きく引いた時に上限を広げる倍率（BattleWorld がカメラの実際の倍率から毎フレーム設定する。
    /// プレイヤーの倍率範囲では 1 で従来どおり）。
    static var zoomScale: Float = 1
    /// 描画中のカメラ姿勢。見回してもバーの向きと深度の計算を同じ視線に合わせる。
    static var cameraOrientation: simd_quatf = CameraRig.orientation
    /// 目の前の対象にも一定の画面寸法を保つため、FPS では従来の最小倍率を使わない。
    static var firstPerson = false
    /// 演出のカメラ（Star Core の終幕の低い視点・引きの構図）の間は隠す（画面に平行な板はゲームカメラの向き専用）。
    /// BattleRenderer が毎フレーム設定し、試合を出る時に戻す。
    static var cinematicHidden = false
    private var screenScale: Float = 1

    /// カメラの倍率 → 上限の広げ方。引くほどバーも少しずつ小さく見えるよう、倍率の平方根で広げる
    /// （2.5 倍で上限 ×1.34: 画面中央のバーは設計寸法の約 85%、地図全体を見渡しても読める大きさ）。
    static func zoomScale(forZoom zoom: Double) -> Float {
        guard zoom.isFinite else { return 1 }
        return Float(max(1, zoom / CameraRig.playerZoomRange.upperBound).squareRoot())
    }

    /// 距離 → 拡縮（純関数。テスト用）。
    static func screenScale(distance: Float, zoomScale k: Float) -> Float {
        max(0.5, min(maxScreenScale * max(1, k), distance / referenceDistance))
    }

    static func firstPersonScreenScale(distance: Float) -> Float {
        guard distance > 0 else { return 0.0001 }
        return max(0.001, min(maxScreenScale, distance / referenceDistance))
    }

    /// 透視投影の深度。直線距離を使うと画面端のバーだけ大きくなる。
    static func viewDepth(world: SIMD3<Float>, camera: SIMD3<Float>) -> Float {
        simd_dot(world - camera, cameraOrientation.act(SIMD3(0, 0, -1)))
    }

    /// 光軸方向の深度に比例して拡縮し、画面上の大きさを一定に保つ。
    func keepScreenSize(camera: SIMD3<Float>, projection: CombatTextProjection? = nil) {
        root.orientation = Self.cameraOrientation
        // 一人称では名前を重ねず、レベルと HP・陣営を一列に収める。
        nameText?.isEnabled = !Self.firstPerson
        let world = (root.parent?.position ?? .zero) + root.position
        let depth = Self.viewDepth(world: world, camera: camera)
        var s = OverheadBar.cinematicHidden ? 0.0001
            : (Self.firstPerson ? Self.firstPersonScreenScale(distance: depth)
                : Self.screenScale(distance: depth, zoomScale: Self.zoomScale))
        if Self.firstPerson, let projection, projection.focalLength > 0 {
            let referenceFocal = Float(projection.viewport.height) / (2 * tan(CameraRig.fovDegrees * .pi / 360))
            s *= referenceFocal / projection.focalLength
        }
        guard abs(s - screenScale) > (Self.firstPerson ? 0.0001 : 0.01) else { return }
        screenScale = s
        root.scale = SIMD3(repeating: s)
        root.position.x = horizontalOffset * s
    }

    /// 描画と同じ投影を使う。霧・死亡はフェードを待たず即座にバーを消す。
    /// 壁は既存 NavGrid の正確な輪郭を再利用し、候補だけを視界更新と同じ 10 Hz で調べる。
    func updateVisibility(_ frame: RenderFrame, index i: Int, bodyHeight: Float, meshVisible: Bool) {
        let unit = frame.state.units[i]
        let foot = worldPosition(frame.interpolated(i))
        guard meshVisible, unit.isAlive, unit.hero?.isDead != true, frame.isVisible(i), frame.needsDetail(i),
              unit.id != frame.firstPersonID, !Self.cinematicHidden else {
            root.isEnabled = false
            occlusionTick = nil
            return
        }
        if frame.firstPersonID != nil,
           simd_distance_squared(foot, frame.camera) > Self.firstPersonMaxDistance * Self.firstPersonMaxDistance {
            root.isEnabled = false
            occlusionTick = nil
            return
        }
        if let projection = frame.overheadProjection {
            let upperBody = foot + SIMD3(0, max(0.2, bodyHeight) * 0.7, 0)
            let head = foot + SIMD3(0, max(0.2, bodyHeight), 0)
            let viewport = CGRect(origin: .zero, size: projection.viewport)
            func onscreen(_ point: SIMD3<Float>) -> Bool {
                projection.project(point).map { viewport.contains($0) } ?? false
            }
            guard onscreen(upperBody) || onscreen(head) else {
                root.isEnabled = false
                occlusionTick = nil
                return
            }
        }
        if frame.firstPersonID != nil, let navigation = frame.overheadNavigation {
            let from = Vec2(Double(frame.camera.x) * Balance.unitsPerMeter,
                            -Double(frame.camera.z) * Balance.unitsPerMeter)
            let to = frame.interpolated(i)
            let tick = frame.state.tick / Balance.visionUpdateEveryTicks
            let moved = from != occlusionFrom || to != occlusionTo
            if occlusionTick == nil || (moved && (tick != occlusionTick || frame.dt == 0)) {
                wallVisible = navigation.hasLineOfSight(from: from, to: to)
                occlusionTick = tick
                occlusionFrom = from
                occlusionTo = to
            }
            root.isEnabled = wallVisible
        } else {
            root.isEnabled = true
            occlusionTick = nil
        }
    }

    /// 表示中の値（テスト・デバッグ用）。
    var displayedHP: Float { shownHP }
    var displayedShield: Float { shownShield }
    var displayedLevel: Int { shownLevel }

    /// 値を反映する（変化時のみエンティティを更新）。hp/shield は最大 HP 比（shield は hp + shield ≤ 1 に収める）。
    /// maxHP を渡すとヒーローの区切り目盛りを並べ直す（最大 HP が変わった時だけ）。
    func update(hp: Float, shield sh: Float, resource res: Float?, level: Int?, dt: Float, maxHP: Float? = nil) {
        if let maxHP, !ticks.isEmpty, abs(maxHP - tickMaxHP) > 0.5 {
            tickMaxHP = maxHP
            let fractions = OverheadBar.tickFractions(maxHP: maxHP)
            for (k, t) in ticks.enumerated() {
                if k < fractions.count {
                    t.position = [-width / 2 + width * fractions[k] - 0.011, 0, 0]
                    t.isEnabled = true
                } else {
                    t.isEnabled = false
                }
            }
        }
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
        if let level, level != shownLevel, let lt = levelText, let e = text.mesh("\(level)", size: OverheadBar.levelTextSize) {
            shownLevel = level
            lt.components.set(ModelComponent(mesh: e.mesh, materials: [levelMaterial]))
            lt.position.x = -width / 2 - 0.035 - 0.2 + e.offsetX
            lt.position.y = -(resource != nil ? 0.05 : 0) + e.offsetY + 0.01
        }
    }

    /// 自分の HP バーとして色を変える（観戦の追従切替など）。
    func setFillColor(_ c: RGB) {
        fill.model?.materials = [materials.overhead(c)]
    }
}
