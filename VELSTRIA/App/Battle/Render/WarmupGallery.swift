import Foundation
import RealityKit
import VelstriaCore

// 担当: battle-renderer。読み込み幕の裏でカメラの注視点に並べる「ウォームアップの陳列棚」。
//
// RealityKit はシェーダー・パイプラインを初めて描いた時に作り、メッシュも初めて描く時に GPU へ送る。画面外・無効の
// エンティティは描かれないので、プールに作っただけでは試合中の初回表示（0:30 のジャングル・初めてのフェード・
// 初めての粒子）でヒッチになる。そこで試合で使う全てのマテリアル（不透明・半透明・深度なし、OpacityComponent < 1 の
// 変種を含む）・メッシュ・粒子プリセット・ヒーローを注視点の周りに一度ずつ並べて描き、BattleWorld.finishWarmup で
// 片付ける。読み込み幕は ARView の上に被さった UIView なので、ARView はこの間も描画を続ける。
// 陳列は地面から浮かせて置く（地面付近の高さ規則 GroundLayer の対象外。幕が上がる前に消える）。

@MainActor
final class WarmupGallery {
    let root = Entity()
    /// OpacityComponent(0.5) を掛けた棚（不透明なマテリアルの半透明の変種を描く）。
    let faded = Entity()
    /// ヒーローの棚。フレーム毎に不透明と半透明（OpacityComponent 0.5）を交互に描く（1 人 1 体で両方の変種を作る）。
    let heroShelf = Entity()
    private var frame = 0
    /// 注視点（world）。
    let center: SIMD3<Float>
    private var slotIndex = 0
    private(set) var sampleCount = 0
    /// 陳列のヒーロー（詠唱の発光・足元の輪を出すため毎フレーム進める）。
    private var heroes: [HeroModelHandle] = []

    /// 陳列の範囲（注視点からの x・z の半幅 m）。カメラ（俯角 56°・距離 12.5 m・縦画角 48°）の視野に収まる大きさ。
    static let halfWidth: Float = 3.6
    static let halfDepth: Float = 1.8

    init(center: SIMD3<Float>) {
        self.center = center
        root.name = "warmupGallery"
        root.position = center
        faded.name = "warmupGalleryFaded"
        faded.components.set(OpacityComponent(opacity: 0.5))
        root.addChild(faded)
        heroShelf.name = "warmupGalleryHeroes"
        root.addChild(heroShelf)
    }

    /// 次の陳列位置（world）。注視点の周りの格子を巡回し、一巡ごとに高さを変える。
    func nextSlot() -> SIMD3<Float> {
        let k = slotIndex
        slotIndex += 1
        let cols = 13, rows = 7
        let x = Float(k % cols) / Float(cols - 1) * 2 * WarmupGallery.halfWidth - WarmupGallery.halfWidth
        let z = Float((k / cols) % rows) / Float(rows - 1) * 2 * WarmupGallery.halfDepth - WarmupGallery.halfDepth
        let y: Float = 0.4 + Float((k / (cols * rows)) % 4) * 0.45
        return center + SIMD3(x, y, z)
    }

    /// 陳列だけのモデルを置く（大きさは最長辺 size m にそろえる）。faded = 半透明の棚にも置く。
    func addModel(_ mesh: MeshResource, material: RealityKit.Material, size: Float = 0.5, faded alsoFaded: Bool) {
        let ext = mesh.bounds.extents
        let k = size / max(0.05, max(ext.x, max(ext.y, ext.z)))
        for parent in alsoFaded ? [root, faded] : [root] {
            AssetLedger.record(.entity, "warmup sample")
            let e = ModelEntity(mesh: mesh, materials: [material])
            e.scale = SIMD3(repeating: k)
            e.position = nextSlot() - center - mesh.bounds.center * k
            parent.addChild(e)
            sampleCount += 1
        }
    }

    /// ヒーローを詠唱の姿勢（発光の粒子・足元の輪あり）で置く。不透明と半透明はフレーム毎に交互（update）。
    func addHero(_ handle: HeroModelHandle) {
        AssetLedger.record(.entity, "warmup hero")
        handle.root.position = nextSlot() - center - SIMD3(0, 0.4, 0)
        heroShelf.addChild(handle.root)
        handle.setState(.cast(.ultimate))
        handle.update(dt: 0.35, moveSpeed: 0)
        heroes.append(handle)
        sampleCount += 1
    }

    /// ウォームアップ中のフレーム毎（BattleWorld.sync）。ヒーローの発光・輪を出し続け、不透明と半透明を交互に描く。
    func update(dt: Float) {
        for h in heroes { h.update(dt: Double(min(dt, 0.05)), moveSpeed: 0) }
        frame += 1
        if frame % 2 == 1 {
            heroShelf.components.set(OpacityComponent(opacity: 0.5))
        } else {
            heroShelf.components.remove(OpacityComponent.self)
        }
    }

    /// 片付ける（陳列だけのエンティティを外して解放する。プールから借りたものは各レイヤーが戻す）。
    func remove() {
        heroes.removeAll()
        root.removeFromParent()
        for c in Array(faded.children) { c.removeFromParent() }
        for c in Array(heroShelf.children) { c.removeFromParent() }
        for c in Array(root.children) where c !== faded && c !== heroShelf { c.removeFromParent() }
    }
}
