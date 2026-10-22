import Foundation
import os
import RealityKit
import UIKit
import VelstriaCore

// 担当: hero-models。同梱 USDZ（Tripo 生成・自動リグのスキンメッシュ）のヒーローを、手続きアニメーション（HeroAnimator → HeroPose）で動かす。
// モーションクリップ（HeroMotionClips.json・HeroMotionSets）があれば、区間回転に重ねてから骨を置く（docs/HERO_MOTION.md）。
// アセット規約: App/Resources/Heroes/Hero_<heroID>.usdz（スキン別 Hero_<heroID>_<cosmeticID>.usdz）、武器 Prop_<WeaponKind/OffhandKind>.usdz。
// テンプレートは URL ごとに 1 度だけ読み込み、インスタンスは clone(recursive:) で作る（メッシュ・テクスチャは共有）。

private let heroAssetLog = Logger(subsystem: "com.bitcoinpay.velstria", category: "HeroAssets")

// MARK: - アセット

/// 同梱アセットの検索と読み込み済みテンプレートのキャッシュ。
@MainActor
enum HeroAssetLibrary {
    private static var urlCache: [String: URL?] = [:]
    private static var heroTemplates: [URL: SkinnedHeroTemplate?] = [:]
    private static var propTemplates: [String: HeroPropTemplate?] = [:]
    /// 進行中の非同期読み込み。
    private static var heroLoads: [URL: Task<SkinnedHeroTemplate?, Never>] = [:]
    private static var propLoads: [String: Task<HeroPropTemplate?, Never>] = [:]
    /// USDZ を実際に読み込んだ回数（キャッシュの確認用）。
    private(set) static var loadCount = 0
    /// 名前 → 同梱 USDZ の URL（テストで差し替える）。
    static var resolver: (String) -> URL? = { Bundle.main.url(forResource: $0, withExtension: "usdz") }

    /// バンドル直下の <name>.usdz。
    static func bundledURL(_ name: String) -> URL? {
        if let cached = urlCache[name] { return cached }
        let url = resolver(name)
        urlCache[name] = url
        return url
    }

    /// ヒーロー本体のテンプレート。読めない・必須の骨が無い・規約違反の場合は nil（理由は 1 度だけ記録）。
    static func heroTemplate(_ url: URL) -> SkinnedHeroTemplate? {
        if let cached = heroTemplates[url] { return cached }
        let start = CFAbsoluteTimeGetCurrent()
        loadCount += 1
        var template: SkinnedHeroTemplate?
        do {
            let entity = try Entity.load(contentsOf: url)
            template = SkinnedHeroTemplate(url: url, entity: entity)
        } catch {
            heroAssetLog.error("\(url.lastPathComponent, privacy: .public): 読み込み失敗 \(error.localizedDescription, privacy: .public)")
        }
        heroTemplates[url] = .some(template)
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        heroAssetLog.info("\(url.lastPathComponent, privacy: .public): \(String(format: "%.1f", ms), privacy: .public) ms")
        return template
    }

    /// 非同期版: USDZ の読み込み・パースはメインスレッドの外で進み、テンプレート化とキャッシュ登録だけをメインで行う。
    /// 同じ URL の読み込みが進行中なら、その結果を待つ（二重に読まない）。
    static func loadHeroTemplate(_ url: URL) async -> SkinnedHeroTemplate? {
        if let cached = heroTemplates[url] { return cached }
        if let task = heroLoads[url] { return await task.value }
        let task = Task { @MainActor () -> SkinnedHeroTemplate? in
            let start = CFAbsoluteTimeGetCurrent()
            // スキンメッシュが使うモーションクリップ（〜1 MB の JSON）も、USDZ と並行してメインスレッドの外で読む（読み込み済みなら何もしない）
            async let motionClips: Void = HeroMotionClips.preloadAsync()
            loadCount += 1
            var template: SkinnedHeroTemplate?
            do {
                template = SkinnedHeroTemplate(url: url, entity: try await Entity(contentsOf: url))
            } catch {
                heroAssetLog.error("\(url.lastPathComponent, privacy: .public): 読み込み失敗 \(error.localizedDescription, privacy: .public)")
            }
            await motionClips
            // 待っている間に同期版が読み終えていれば、そちらを使う
            if let done = heroTemplates[url] { return done }
            heroTemplates[url] = .some(template)
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            heroAssetLog.info("\(url.lastPathComponent, privacy: .public): 非同期 \(String(format: "%.1f", ms), privacy: .public) ms")
            return template
        }
        heroLoads[url] = task
        let template = await task.value
        heroLoads[url] = nil
        return template
    }

    /// 非同期版の武器・副手テンプレート（Prop_<kind>.usdz）。
    static func loadPropTemplate(_ kind: String) async -> HeroPropTemplate? {
        if let cached = propTemplates[kind] { return cached }
        guard kind != "none", let url = bundledURL("Prop_\(kind)") else { return propTemplate(kind) }
        if let task = propLoads[kind] { return await task.value }
        let task = Task { @MainActor () -> HeroPropTemplate? in
            loadCount += 1
            var template: HeroPropTemplate?
            do {
                template = HeroPropTemplate(entity: try await Entity(contentsOf: url))
            } catch {
                heroAssetLog.error("Prop_\(kind, privacy: .public): 読み込み失敗 \(error.localizedDescription, privacy: .public)")
            }
            if let done = propTemplates[kind] { return done }
            propTemplates[kind] = .some(template)
            return template
        }
        propLoads[kind] = task
        let template = await task.value
        propLoads[kind] = nil
        return template
    }

    /// 武器・副手のテンプレート（Prop_<kind>.usdz）。無ければ nil（手続きメッシュを使う）。
    static func propTemplate(_ kind: String) -> HeroPropTemplate? {
        if let cached = propTemplates[kind] { return cached }
        var template: HeroPropTemplate?
        if kind != "none", let url = bundledURL("Prop_\(kind)") {
            loadCount += 1
            do {
                template = HeroPropTemplate(entity: try Entity.load(contentsOf: url))
            } catch {
                heroAssetLog.error("Prop_\(kind, privacy: .public): 読み込み失敗 \(error.localizedDescription, privacy: .public)")
            }
        }
        propTemplates[kind] = .some(template)
        return template
    }

    /// 読み込み済みのテンプレートを捨てる（keep にあるものと、失敗の記録は残す）。
    /// 生成済みのインスタンスはメッシュ・テクスチャを自分で参照しているので影響しない。
    static func purge(keepingHeroes keep: Set<URL>, props keepProps: Set<String>) {
        for (url, t) in heroTemplates where t != nil && !keep.contains(url) { heroTemplates[url] = nil }
        for (kind, t) in propTemplates where t != nil && !keepProps.contains(kind) { propTemplates[kind] = nil }
    }

    /// テスト用: Prop テンプレートを差し込む（nil で差し込みを外し、次回は同梱を探し直す）。
    static func setPropTemplateForTesting(_ kind: String, _ template: HeroPropTemplate?) {
        propTemplates[kind] = template.map { .some($0) }
    }

    /// テスト用: 検索・テンプレートのキャッシュと resolver を初期状態へ戻す。
    static func resetForTesting() {
        resolver = { Bundle.main.url(forResource: $0, withExtension: "usdz") }
        urlCache = [:]
        heroTemplates = [:]
        propTemplates = [:]
        heroLoads = [:]
        propLoads = [:]
    }

    /// メッシュの三角形数。
    static func triangleCount(_ mesh: MeshResource) -> Int {
        mesh.contents.models.reduce(0) { n, m in n + m.parts.reduce(0) { $0 + ($1.triangleIndices?.count ?? 0) / 3 } }
    }

    static func triangleCount(_ e: Entity) -> Int {
        var n = e.components[ModelComponent.self].map { triangleCount($0.mesh) } ?? 0
        for c in e.children { n += triangleCount(c) }
        return n
    }

    /// ルートから子の添字をたどる。
    static func entity(at path: [Int], in root: Entity) -> Entity? {
        var e = root
        for i in path {
            guard i < e.children.count else { return nil }
            e = e.children[i]
        }
        return e
    }

    /// 骨付きメッシュを持つ ModelEntity までの添字の列（すべて、深さ優先順）。
    static func skinnedPaths(in e: Entity) -> [[Int]] {
        var out: [[Int]] = []
        if e is ModelEntity, let m = e.components[ModelComponent.self], !m.mesh.contents.skeletons.isEmpty { out.append([]) }
        for (i, c) in e.children.enumerated() {
            out += skinnedPaths(in: c).map { [i] + $0 }
        }
        return out
    }

    /// 専用アセットの無いスキンの色味（既定は無し）。パレットの基調色を薄く掛ける。
    static func skinTint(_ p: HeroPalette, variant: Int) -> UIColor? {
        guard variant != 0 else { return nil }
        return HSB(p.primary.h, p.primary.s * 0.35, 0.72 + 0.28 * p.primary.b).uiColor
    }
}

/// 読み込み済みのヒーロー本体（骨対応・レスト姿勢・寸法を含む）。
@MainActor
final class SkinnedHeroTemplate {
    let url: URL
    let entity: Entity
    /// 骨付きメッシュ（同じ骨・同じ配置。先頭が代表）。
    let skinnedPaths: [[Int]]
    var skinnedPath: [Int] { skinnedPaths[0] }
    let rig: HeroSkeletonRig
    /// バインド姿勢の範囲（ヒーロー空間）。
    let bounds: BoundingBox
    let triangleCount: Int
    /// 最後の背骨の高さでの背中の表面（背骨からの +Z 距離）。翼の取り付けに使う。
    let backDepth: Float?
    /// 頭の中心・半径・後頭部（中心からの +Z 距離）。光輪の大きさと位置に使う（ヒーロー空間・レスト）。
    let headCenter: V3
    let headRadius: Float
    let headBack: Float
    /// 骨付きメッシュごとのマテリアル。
    let baseMaterials: [[RealityKit.Material]]
    /// 色味（RGBA）ごとに共有する塗り分け済みマテリアル。
    private var tinted: [String: [[RealityKit.Material]]] = [:]

    init?(url: URL, entity: Entity) {
        let name = url.lastPathComponent
        let paths = HeroAssetLibrary.skinnedPaths(in: entity)
        let skinnedEntities = paths.compactMap { HeroAssetLibrary.entity(at: $0, in: entity) as? ModelEntity }
        guard let first = skinnedEntities.first, skinnedEntities.count == paths.count,
              skinnedEntities.allSatisfy({ $0.model != nil }) else {
            heroAssetLog.error("\(name, privacy: .public): 骨付きメッシュが無い")
            return nil
        }
        let toHeroMatrix = first.transformMatrix(relativeTo: entity)
        // 複数のスキンメッシュは同じ姿勢を書くので、骨の並びと配置が一致すること
        for e in skinnedEntities.dropFirst() {
            let m = e.transformMatrix(relativeTo: entity)
            let sameNames = e.jointNames == first.jointNames
            let samePlace = (0..<4).allSatisfy { simd_distance(m[$0], toHeroMatrix[$0]) < 1e-4 }
            guard sameNames && samePlace else {
                heroAssetLog.error("\(name, privacy: .public): 骨・配置の異なるスキンメッシュが複数ある → 手続きモデル")
                return nil
            }
        }
        let toHero = Transform(matrix: toHeroMatrix)
        var missing: [HeroJointRole] = []
        guard let rig = HeroSkeletonRig(jointNames: first.jointNames, restLocal: first.jointTransforms,
                                        entityToHero: toHero, missing: &missing) else {
            let list = missing.map(\.rawValue).joined(separator: ",")
            heroAssetLog.error("\(name, privacy: .public): 必須の骨が無い [\(list, privacy: .public)] → 手続きモデル")
            return nil
        }
        // 規約（正面 -Z・右手 +X）に反する骨は鏡像・逆向きに動くので手続きモデルへ戻す
        if let reason = Self.contractViolation(rig) {
            heroAssetLog.error("\(name, privacy: .public): \(reason, privacy: .public) → 手続きモデル")
            return nil
        }
        self.url = url
        self.entity = entity
        skinnedPaths = paths
        self.rig = rig
        let models = skinnedEntities.compactMap(\.model)
        baseMaterials = models.map(\.materials)
        triangleCount = models.reduce(0) { $0 + HeroAssetLibrary.triangleCount($1.mesh) }

        let m = toHero.matrix
        func hero(_ v: V3) -> V3 {
            let p = m * SIMD4<Float>(v, 1)
            return V3(p.x, p.y, p.z)
        }
        var hb = BoundingBox.empty
        for model in models {
            let b = model.mesh.bounds
            for i in 0..<8 {
                let c = V3(i & 1 == 0 ? b.min.x : b.max.x, i & 2 == 0 ? b.min.y : b.max.y, i & 4 == 0 ? b.min.z : b.max.z)
                hb = hb.union(hero(c))
            }
        }
        bounds = hb

        // 背中の表面: 最後の背骨の高さ付近・中心付近の頂点で最も後ろ（+Z）
        // 頭: 頭の骨から頂点までの上半分を頭とみなし、その高さの頂点で幅と後頭部を測る
        let spine = rig.restPosition[rig.upperSpine]
        let hj = rig.restPosition[rig.index[.head]!]
        let halfH = max(0.04, (hb.max.y - hj.y) * 0.5)
        let hc = V3(hj.x, hj.y + halfH, hj.z)
        var back: Float = -.infinity
        var halfW: Float = 0, hBack: Float = -.infinity
        for model in models {
            for mm in model.mesh.contents.models {
                for part in mm.parts {
                    for v in part.positions.elements {
                        let p = hero(v)
                        if abs(p.y - spine.y) < 0.08 && abs(p.x - spine.x) < 0.12 { back = max(back, p.z - spine.z) }
                        if abs(p.y - hc.y) < halfH * 0.6 && abs(p.x - hc.x) < halfH * 1.5 {
                            halfW = max(halfW, abs(p.x - hc.x))
                            hBack = max(hBack, p.z - hc.z)
                        }
                    }
                }
            }
        }
        backDepth = back.isFinite && back > 0 ? back : nil
        headCenter = hc
        headRadius = max(halfH, halfW)
        headBack = hBack.isFinite && hBack > 0 ? hBack : max(halfH, halfW)
    }

    /// 規約（正面 -Z・右手 +X）に反していれば理由。左右の入れ替わったリグ・後ろ向きのリグを弾く。
    static func contractViolation(_ rig: HeroSkeletonRig) -> String? {
        let rp = rig.restPosition
        if let r = rig.index[.armR], let l = rig.index[.armL], rp[r].x <= rp[l].x {
            return "右腕が +X 側に無い（鏡像リグ）"
        }
        var toeDZ: Float = 0, toeCount = 0
        for (foot, toe) in [(HeroJointRole.footL, HeroJointRole.toeL), (.footR, .toeR)] {
            if let f = rig.index[foot], let t = rig.index[toe] {
                toeDZ += rp[t].z - rp[f].z
                toeCount += 1
            }
        }
        if toeCount > 0, toeDZ >= 0 { return "つま先が -Z を向いていない（逆向き）" }
        return nil
    }

    /// 本体のマテリアル（骨付きメッシュごと。tint 指定時は色味ごとに共有）。
    func materials(tint: UIColor?) -> [[RealityKit.Material]] {
        guard let tint else { return baseMaterials }
        var tr: CGFloat = 1, tg: CGFloat = 1, tb: CGFloat = 1, ta: CGFloat = 1
        tint.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        let key = String(format: "%.4f,%.4f,%.4f,%.4f", tr, tg, tb, ta)
        if let m = tinted[key] { return m }
        let list = baseMaterials.map { mats in
            mats.map { mat -> RealityKit.Material in
                guard var pbr = mat as? PhysicallyBasedMaterial else { return mat }
                var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
                pbr.baseColor.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
                pbr.baseColor.tint = UIColor(red: r * tr, green: g * tg, blue: b * tb, alpha: a)
                return pbr
            }
        }
        tinted[key] = list
        return list
    }
}

/// 読み込み済みの武器・副手。正規化（tools/blender/normalize_prop.py）で手続きメッシュ（HeroGear.swift）と同じ座標にしてある:
/// 握りが原点・+Y へ伸びる・長さ 1 m。刃物・杖は薄い向きが ±X（刃先 -Z）、銃は上面 +Z、弓は弦 +Z（YZ 平面）。
/// 面が ±Z の副手（assets.json の yaw）: gateShield・hideShield・harpBow は面が -Z、mechCrossbow は上面 +Z で弓が ±X、
/// grimoire は表紙が -X。手続き側で組んだ後に掛けた回転（盾の ry(0.4)・弓の ry(0.6)）だけを実行時に足す（propFit）。
@MainActor
final class HeroPropTemplate {
    let entity: Entity
    /// 範囲（ルート自身の変換を含む = 親の座標）。
    let bounds: BoundingBox
    /// Y 方向の長さ（手続きメッシュの長さへ合わせる拡縮に使う）。
    var length: Float { bounds.extents.y }
    let triangleCount: Int

    init?(entity: Entity) {
        // 親の無いエンティティの relativeTo: nil はルート自身の変換を含む
        let b = entity.visualBounds(recursive: true, relativeTo: nil, excludeInactive: false)
        let len = b.max.y - b.min.y
        guard len.isFinite, len > 1e-4 else { return nil }
        self.entity = entity
        bounds = b
        triangleCount = HeroAssetLibrary.triangleCount(entity)
    }
}

// MARK: - モデル

/// スキンメッシュのヒーロー。root → body（死亡フェード）→ motion（全身の移動・傾き）→ 読み込んだ本体 + 装備。
/// 装備・翼・浮遊物は motion 直下に置き、毎フレーム骨の位置へ合わせる（手続きの背中装備は本体に含まれるので出さない）。
@MainActor
final class SkinnedHeroModel: HeroDisplayModel {
    /// 前腕の籠手・爪は本体アセット（Tripo の本体プロンプト・assets.json H007 / H022）に含めるので、
    /// 手続きメッシュも Prop も付けない（castGlow の親・前腕追従のため空の entity は残す）。
    static let bodyWornGear: Set<String> = ["\(WeaponKind.stoneFist)", "\(WeaponKind.azureClaw)"]
    /// 吊り輪を握って下げる副手（灯籠）。構え・振りの武器角に関係なく、胴の向きのまま真下へ吊るす
    /// （双剣の構えの武器角 -1.05 を灯籠に掛けると、火袋が前へ水平に突き出して浮いて見える）。
    static let hangingGear: Set<String> = ["\(OffhandKind.moonLantern)"]

    /// スキンメッシュのヒーローの装備だけに掛ける表示倍率（設計図の weaponScale / offhandScale に掛ける。手続きモデルは従来どおり）。
    /// 手続きの寸法は 2 頭身寄りの手続きモデル向けで、人の体格のスキンメッシュには大きすぎるもの:
    /// 弩（Prop の弓は手続きの 1.7 倍の幅 1.0 m）、月弓・光の弓（全長 1.27 m で下の弓先が足元に立つ）。
    /// entity の拡縮なので、先端（weaponTip / offhandTip）・軌跡・発射位置も同じ比で縮む。
    static func gearScale(_ kind: String) -> Float {
        switch kind {
        case "\(WeaponKind.mechCrossbow)": return 0.78
        case "\(OffhandKind.ashBow)", "\(OffhandKind.lightBow)": return 0.84
        default: return 1
        }
    }

    let root = Entity()
    let overheadHeight: Float
    let heroID: String
    let skin: HeroSkinInfo
    private(set) var entityCount = 0
    let triangleCount: Int
    var isSkinned: Bool { true }

    private let body = Entity()
    private let motion = Entity()
    /// 骨付きメッシュ（jointTransforms を書く）。先頭が代表。
    let skinnedEntities: [ModelEntity]
    var skinnedEntity: ModelEntity { skinnedEntities[0] }
    let weapon: ModelEntity
    let offhand: ModelEntity
    private let bowstring: [ModelEntity]
    private let wingL: ModelEntity?
    private let wingR: ModelEntity?
    private let flag: ModelEntity?
    let float: ModelEntity?
    private var effects: HeroEffects
    /// 次の通常攻撃が強い間の武器の先の光（setEmpoweredReady。0 = 消す）。
    private var empoweredGlow: Float = 0

    private var poser: HeroSkeletonPoser
    private let handR: Int
    private let handL: Int
    private let stringIndexR: Int?
    private let stringMiddleR: Int?
    private let headJoint: Int
    private let upperSpine: Int
    private let wingDepth: Float
    private let haloOffset: V3
    /// 光輪の拡縮（スキンの頭 / 手続きの頭）。
    let haloScale: Float
    /// 腰の沈み（手続きの脚の長さ基準の m）をスキンの脚の長さへ伸ばす比。
    private let hipsDropScale: Float
    /// クリップの腰のずれ（脚の長さ単位）→ m。レストの腰の高さ - 左右の足首の高さの平均（docs/HERO_MOTION.md の L）。
    let clipLegLength: Float
    private let floatMotion: FloatMotion
    private let floatAnchor: V3
    private let weaponFollowsArm: Bool
    private let offhandFollowsArm: Bool
    private let offhandHangs: Bool
    /// 状態のクリップ（待機など）を重ねている度合い（0〜1、切り替えで武器角が跳ねないよう時間で寄せる）。
    private var stateClipHold: Float = 0
    private var lastApplyTime: Float = 0
    private let weaponPoints: HeroWeaponPoints
    private var animator: HeroAnimator
    /// 歩幅の基準にする腰から足首までの長さ（m）。テストで手続きモデルと skinned モデルの走りの位相を揃えるのに使う。
    var legLength: Float {
        get { animator.legLength }
        set { animator.legLength = newValue }
    }

    init?(heroID: String, skin: HeroSkinInfo, blueprint bp: HeroBlueprint, template: SkinnedHeroTemplate, tintBody: Bool,
          meshes ms: HeroMeshSet, materials: [RealityKit.Material], palette: HeroPalette, team: Team,
          options: HeroModelOptions, defaultRunSpeed: Float) {
        let clone = template.entity.clone(recursive: true)
        let skinned = template.skinnedPaths.compactMap { HeroAssetLibrary.entity(at: $0, in: clone) as? ModelEntity }
        guard !skinned.isEmpty, skinned.count == template.skinnedPaths.count else { return nil }
        let rig = template.rig
        let rp = rig.restPosition
        let hm = ms.metrics
        self.heroID = heroID
        self.skin = skin
        skinnedEntities = skinned
        poser = HeroSkeletonPoser(rig: rig)
        handR = rig.index[.handR]!
        handL = rig.index[.handL]!
        stringIndexR = rig.jointNames.firstIndex { HeroJointRole.normalize($0) == "righthandindex3" }
        stringMiddleR = rig.jointNames.firstIndex { HeroJointRole.normalize($0) == "righthandmiddle3" }
        headJoint = rig.index[.head]!
        upperSpine = rig.upperSpine

        // hipsDrop（m）は手続きの脚の長さ（腿 + 脛、足首 y = 0）が前提。スキンの脚の長さとの比で伸ばし、膝・足を手続きと同じ高さへ着ける
        let legs: [Float] = [(HeroJointRole.upLegL, HeroJointRole.footL), (.upLegR, .footR)].compactMap { a, b in
            guard let i = rig.index[a], let j = rig.index[b] else { return nil }
            let d = rp[i].y - rp[j].y
            return d > 1e-3 ? d : nil
        }
        let skinLeg = legs.isEmpty ? rp[rig.index[.upLegL]!].y // 規約で足元は y = 0
            : legs.reduce(0, +) / Float(legs.count)
        hipsDropScale = min(2.5, max(0.5, skinLeg / (hm.thigh + hm.shin)))
        let hipsY = rp[rig.index[.hips]!].y
        let feetY: [Float] = [HeroJointRole.footL, .footR].compactMap { rig.index[$0].map { rp[$0].y } }
        // 足首が無ければ足元（規約で y = 0）
        let footY = feetY.isEmpty ? 0 : feetY.reduce(0, +) / Float(feetY.count)
        clipLegLength = max(0.1, hipsY - footY)

        // 光輪: 手続きの頭の中心からのずれを、スキンの頭の大きさ・後頭部へ写す
        let k = template.headRadius / hm.headR
        let rel = ms.floatAnchor - V3(0, hm.torsoLen + hm.headY, 0)
        haloScale = k
        haloOffset = (template.headCenter - rp[headJoint])
            + V3(0, rel.y * k, template.headBack + max(0, rel.z - hm.headR) * k)
        // 周回・浮遊の高さ: 手続きの腰・肩の高さ → スキンの腰・肩の高さへ一次変換
        let procHips = hm.hipY, procShoulder = hm.hipY + 0.03 + hm.shoulderY
        let skinHips = rp[rig.index[.hips]!].y
        let skinShoulder = (rp[rig.index[.armL]!].y + rp[rig.index[.armR]!].y) * 0.5
        let ay = (skinShoulder - skinHips) / max(0.05, procShoulder - procHips)
        var anchor = V3(ms.floatAnchor.x, skinShoulder + (ms.floatAnchor.y - procShoulder) * ay, ms.floatAnchor.z)
        // 潮の水球（H004）は大きく（半径 0.12 + 輪 0.17）、頭の高さで回ると正面のカメラ（詳細・ギャラリー）で顔の前を通って隠す。
        // 人の体格のスキンでは胸の高さで回す（手続きの 2 頭身では 1.15 m が頭の横）
        if bp.float == .waterOrb { anchor.y = min(anchor.y, skinShoulder - 0.12) }
        floatAnchor = anchor
        floatMotion = ms.floatMotion

        wingDepth = template.backDepth ?? ms.wingAnchor.z
        weaponFollowsArm = bp.weaponFollowsArm
        offhandFollowsArm = bp.offhand == .stoneFist || bp.offhand == .azureClaw
        offhandHangs = Self.hangingGear.contains("\(bp.offhand)")
        // 武器・副手のエンティティは手続きの武器座標のまま（Prop は propFit の中）なので、手続きの先端がそのまま使える
        weaponPoints = HeroWeaponPoints(blueprint: bp, meshes: ms)
        overheadHeight = (template.bounds.max.y + 0.38) * bp.scale

        if tintBody, let tint = HeroAssetLibrary.skinTint(palette, variant: skin.variant) {
            let mats = template.materials(tint: tint)
            for (e, m) in zip(skinned, mats) { e.model?.materials = m }
        }

        var tris = template.triangleCount
        func part(_ mesh: MeshResource?, _ name: String) -> ModelEntity {
            let e = ModelEntity()
            e.name = name
            if let mesh {
                e.components.set(ModelComponent(mesh: mesh, materials: materials))
                tris += HeroAssetLibrary.triangleCount(mesh)
            }
            return e
        }
        /// Prop_<kind>.usdz があれば手続きメッシュと同じ長さ・向き・置き方で使う。体に付ける籠手・爪は何も付けない。
        func gear(_ kind: String, _ mesh: MeshResource?, _ name: String) -> ModelEntity {
            if Self.bodyWornGear.contains(kind) { return part(nil, name) }
            guard let mesh, let prop = HeroAssetLibrary.propTemplate(kind) else { return part(mesh, name) }
            let e = ModelEntity()
            e.name = name
            // 合わせ込みは中間の entity に持たせ、Prop のルート自身の変換は残す
            let fit = Entity()
            fit.name = "propFit"
            fit.transform = Self.propFit(kind, prop: prop.bounds, procedural: mesh.bounds)
            fit.addChild(prop.entity.clone(recursive: true))
            e.addChild(fit)
            tris += prop.triangleCount
            return e
        }
        weapon = gear("\(bp.weapon)", ms.weapon, "weapon")
        if heroID == "H025", let unstrung = ms.offhandUnstrung, let string = ms.bowstringSegment {
            offhand = part(unstrung, "offhand")
            bowstring = [part(string, "bowstring.upper"), part(string, "bowstring.lower")]
            for segment in bowstring {
                AssetLedger.record(.entity, segment.name)
                offhand.addChild(segment)
            }
        } else {
            offhand = gear("\(bp.offhand)", ms.offhand, "offhand")
            bowstring = []
        }
        wingL = ms.wingL.map { part($0, "wingL") }
        wingR = ms.wingR.map { part($0, "wingR") }
        flag = ms.flag.map { part($0, "flag") }
        float = ms.float.map { part($0, "float") }
        triangleCount = tris

        root.name = "hero.\(heroID)"
        root.addChild(body)
        body.addChild(motion)
        motion.scale = V3(repeating: bp.scale)
        clone.name = "skinnedBody"
        motion.addChild(clone)
        motion.addChild(weapon)
        motion.addChild(offhand)
        weapon.scale = V3(repeating: bp.weaponScale * Self.gearScale("\(bp.weapon)"))
        offhand.scale = V3(repeating: bp.offhandScale * Self.gearScale("\(bp.offhand)"))
        if let wingL, let wingR {
            motion.addChild(wingL)
            motion.addChild(wingR)
        }
        if let flag {
            weapon.addChild(flag)
            flag.position = ms.flagAnchor
        }
        if let float {
            motion.addChild(float)
            float.position = floatAnchor
            if case .halo = ms.floatMotion { float.scale = V3(repeating: haloScale) }
        }
        effects = HeroEffects(body: body, glowParent: weapon, weaponTip: ms.weaponTip, palette: palette, team: team,
                              options: options)

        // クリップの割り当て（ライブラリに無い名前は落とし、何も残らなければ手続きのみ）。
        // ライブラリは戦闘ならロード中に読み込み済み（loadHeroTemplate が並行して HeroMotionClips.preloadAsync を待つ）、
        // プレビュー・テストはここで同期に読む
        let motionSet = HeroMotionSets.set(heroID: heroID)
        animator = HeroAnimator(profile: HeroMotionProfile(blueprint: bp, metrics: ms.metrics, heroID: heroID),
                                defaultRunSpeed: defaultRunSpeed,
                                motion: motionSet.flatMap { HeroMotionBinding(set: $0, library: HeroMotionClips.library(heroID: heroID)) })
        animator.legLength = skinLeg * bp.scale
        // 足の接地（全身のモーション）: スキンの腰・腿の付け根・膝・足首の待機の位置から
        if let uR = rig.index[.upLegR].map({ rp[$0] }), let uL = rig.index[.upLegL].map({ rp[$0] }),
           let kR = rig.index[.legR].map({ rp[$0] }), let kL = rig.index[.legL].map({ rp[$0] }),
           let fR = rig.index[.footR].map({ rp[$0] }), let fL = rig.index[.footL].map({ rp[$0] }) {
            let hipsRest = rp[rig.index[.hips]!]
            let s = bp.scale
            animator.legRig = HeroLegRig(hips: hipsRest * s, socketR: (uR - hipsRest) * s, socketL: (uL - hipsRest) * s,
                                         thighR: simd_distance(uR, kR) * s, shinR: simd_distance(kR, fR) * s,
                                         thighL: simd_distance(uL, kL) * s, shinL: simd_distance(kL, fL) * s,
                                         dropScale: hipsDropScale * s, rest: animator.profile.rest)
        }
        if let hip = rig.index[.upLegL], let knee = rig.index[.legL], let foot = rig.index[.footL] {
            let thigh = simd_length(rp[hip] - rp[knee])
            let shin = simd_length(rp[knee] - rp[foot])
            animator.gaitThighRatio = thigh / max(0.001, thigh + shin)
        }
        entityCount = HeroEffects.countEntities(root)
        apply(animator.current, time: 0)
    }

    /// 正規化 Prop（HeroPropTemplate の規約）を手続きメッシュの武器座標へ合わせる変換。
    /// 長さ（Y）を揃え、手続き側で組んだ後の回転（propMount の yaw）と置き方（center）を足す。
    /// 横の広い向き（X / Z）が手続きと食い違う時だけ 90° 回す（yaw を掛けずに正規化した古い Prop の予備。yaw 済みなら一致する）。
    static func propFit(_ kind: String, prop: BoundingBox, procedural: BoundingBox) -> Transform {
        let s = procedural.extents.y / max(1e-4, prop.extents.y)
        let mount = HeroGearBuilder.propMount(kind)
        /// 横の広い向き（0 = X, 2 = Z）。ほぼ同じ幅なら決めない。
        func wide(_ b: BoundingBox) -> Int? {
            let e = b.extents
            if e.x > e.z * 1.25 { return 0 }
            if e.z > e.x * 1.25 { return 2 }
            return nil
        }
        var turn = qIdentity
        if let a = wide(prop), let b = wide(procedural), a != b { turn = ry(mount.turn * .pi / 2) }
        let rot = ry(mount.yaw) * turn
        let t = mount.center ? procedural.center - rot.act(prop.center * s) : .zero
        return Transform(scale: V3(repeating: s), rotation: rot, translation: t)
    }

    // MARK: HeroModelHandle

    var state: HeroAnimState { animator.state }

    func setState(_ state: HeroAnimState) {
        let wasDead = animator.state == .dead
        animator.setState(state)
        if wasDead && state != .dead {
            // 復活: 即座に不透明へ戻す
            effects.setOpacity(1, body: body)
        }
    }

    func castDuration(_ slot: SkillSlot) -> Float { animator.castDuration(slot) }
    func castDuration(_ slot: SkillSlot, stage: Int) -> Float { animator.castDuration(slot, stage: stage) }
    func castRestarts(_ slot: SkillSlot, stage: Int) -> Bool { animator.castRestarts(slot, stage: stage) }
    func playCast(_ slot: SkillSlot, stage: Int) { animator.playCast(slot, stage: stage) }
    func playCastHit(_ slot: SkillSlot) -> Float? { animator.playCastHit(slot) }

    func update(dt: Double, moveSpeed: Double) {
        let pose = animator.advance(dt: Float(dt), moveSpeed: HeroModelLibrary.metersPerSecond(moveSpeed))
        apply(pose, time: animator.time)
    }

    func playAttack(windup: Double, interval: Double) {
        let wasDead = animator.state == .dead
        animator.playAttack(windup: Float(windup), interval: Float(interval))
        if HeroMotionClips.dedicatedHeroes.contains(heroID) { animator.awaitAttackRelease() }
        if wasDead { effects.setOpacity(1, body: body) }
    }

    func synchronizeAttackRelease() {
        if HeroMotionClips.dedicatedHeroes.contains(heroID) { animator.synchronizeAttackRelease() }
    }

    func playAttack(windup: Double, interval: Double, empowered: Bool) {
        let wasDead = animator.state == .dead
        animator.playAttack(windup: Float(windup), interval: Float(interval), empowered: empowered)
        if HeroMotionClips.dedicatedHeroes.contains(heroID) { animator.awaitAttackRelease() }
        if wasDead { effects.setOpacity(1, body: body) }
    }

    func setEmpoweredReady(_ ready: Bool) { empoweredGlow = ready ? HeroEffects.empoweredGlow : 0 }

    func attackLaunchPoint() -> SIMD3<Float>? {
        weaponPoints.launchPosition(weapon: weapon, offhand: offhand, strikeHand: animator.strikeHand)
    }

    func weaponTrailSample() -> HeroWeaponTrailSample? {
        weaponPoints.trailSample(weapon: weapon, offhand: offhand, swing: animator.weaponSwing)
    }

    /// クリップの割り当てを差し替える（テスト・ギャラリー用。nil = 手続きのみ）。
    func useMotion(_ set: HeroMotionSet?, library: HeroMotionLibrary) {
        animator.setMotion(set.flatMap { HeroMotionBinding(set: $0, library: library) })
    }

    // MARK: 検査用

    var rig: HeroSkeletonRig { poser.rig }
    /// 重ねているクリップの層（テスト用）。
    var clipLayer: HeroClipLayer { animator.clips }
    /// 脚の長さの比（hipsDrop の伸び率）。
    var legScale: Float { hipsDropScale }
    /// 足の接地の脚の寸法（テスト用）。
    var legRig: HeroLegRig? { animator.legRig }
    /// 今の手続きの姿勢（クリップを重ねる前。テスト用）。
    var currentPose: HeroPose { animator.current }

    /// 任意の姿勢を適用する（テスト用）。手続きの姿勢そのものを見るため、再生中のクリップは重ねない。
    func applyPose(_ p: HeroPose, time: Float = 0) {
        apply(p, time: time, clips: false)
    }

    /// 骨の現在位置（ヒーロー空間 = motion のローカル）。
    func jointPosition(_ role: HeroJointRole) -> V3? {
        poser.jointPosition(role)
    }

    // MARK: 適用

    private func apply(_ p: HeroPose, time t: Float, clips: Bool = true) {
        // クリップが下半身を動かす分だけ、手続きの全身の傾き・浮き沈み・腰の沈みを止める（倒れ方・跳ね方はクリップの腰が持つ）
        let wl = clips ? animator.clipLowerWeight : 0, wu = clips ? animator.clipUpperWeight : 0
        let k = 1 - wl
        motion.position = p.offset * k
        motion.orientation = ry(p.yaw) * rx(-p.pitch * k) * rz(p.roll * k)
        let qp = HeroSegmentRotations(p)
        var q = qp
        var root = V3.zero
        if clips { animator.overlay(into: &q, hipsOffset: &root) }
        poser.solve(q, hipsDrop: p.hipsDrop * hipsDropScale * k, hipsOffset: root * clipLegLength)
        for e in skinnedEntities { e.jointTransforms = poser.local }

        // 武器は手首から握りの分だけ前腕の向きへずらし、向きは手続きモデルと同じ（胴基準の絶対角）。
        // クリップが腕を動かしている間は手の区間に持たせ、重みで手続きと混ぜる。向きは割り当ての grip（振る武器）か、
        // grip が nil なら手続きの武器角をクリップの胴に対して保つ（杖・槍・銃・弓・盾。手首の向きで寝かせない）。
        // 手続きの weaponR(followsArm: false) = 胴 · ry(腕の yaw) · rx(武器角) なので、胴だけクリップのものに替える
        let rig = poser.rig
        let gripR = V3(0, -rig.gripR, 0), gripL = V3(0, -rig.gripL, 0)
        let handPosR = poser.position[handR], handPosL = poser.position[handL]
        // 状態のクリップ（腕を下ろした待機など）の間は、割り当ての待機の武器角（idleWeaponR / L）へ寄せる
        let dtHold = min(0.1, max(0, t - lastApplyTime))
        lastApplyTime = t
        let stateClip: Float = clips && wu > 0 && animator.clips.role == .state ? 1 : 0
        stateClipHold += (stateClip - stateClipHold) * min(1, dtHold * 8)
        if wu > 0, let m = animator.motion {
            let k = stateClipHold
            let angR = m.idleWeaponR.map { p.weaponR + ($0 - p.weaponR) * k } ?? p.weaponR
            let angL = m.idleWeaponL.map { p.weaponL + ($0 - p.weaponL) * k } ?? p.weaponL
            let heldR = m.weaponGrip.map { q.handR * $0 } ?? q.torso * ry(p.armR.yaw) * rx(angR)
            // 握りから武器の芯までのずれ（武器の軸。H030 の星砲は掌を砲身の上に乗せる）
            let heldPosR = handPosR + q.handR.act(gripR) + heldR.act(m.weaponOffset)
            weapon.position = simd_mix(handPosR + q.foreArmR.act(gripR), heldPosR, V3(repeating: wu))
            weapon.orientation = weaponFollowsArm ? q.handR : simd_slerp(qp.weaponR(p, followsArm: false), heldR, wu)
            offhand.position = simd_mix(handPosL + q.foreArmL.act(gripL), handPosL + q.handL.act(gripL), V3(repeating: wu))
            let heldL = m.offhandGrip.map { q.handL * $0 } ?? q.torso * ry(-p.armL.yaw) * rx(angL)
            offhand.orientation = offhandFollowsArm ? q.handL : simd_slerp(qp.weaponL(p, followsArm: false), heldL, wu)
        } else {
            weapon.position = handPosR + q.foreArmR.act(gripR)
            weapon.orientation = q.weaponR(p, followsArm: weaponFollowsArm)
            offhand.position = handPosL + q.foreArmL.act(gripL)
            offhand.orientation = q.weaponL(p, followsArm: offhandFollowsArm)
        }
        if !bowstring.isEmpty {
            let top = HeroGearBuilder.crescentStringTop, bottom = HeroGearBuilder.crescentStringBottom
            let resting = (top + bottom) * 0.5
            let pull: V3
            if let index = stringIndexR, let middle = stringMiddleR {
                pull = (poser.position[index] + poser.position[middle]) * 0.5
            } else if let middle = stringMiddleR {
                pull = poser.position[middle]
            } else { pull = handPosR + q.handR.act(gripR) }
            let localPull = offhand.convert(position: pull, from: motion)
            let contact = clips ? animator.clips.bowstringContact : 0
            let nock = resting + (localPull - resting) * contact
            for i in 0..<2 {
                let end = i == 0 ? top : bottom
                let delta = end - nock
                let length = max(0.0001, simd_length(delta))
                let segment = bowstring[i]
                segment.position = (end + nock) * 0.5
                segment.orientation = rotationFromY(to: delta)
                segment.scale = V3(1, length, 1)
            }
        }
        if offhandHangs {
            // 胴の正面の水平成分だけを残して真下へ吊るす（体が傾いても火袋は鉛直）
            let f = q.torso.act(V3(0, 0, -1))
            offhand.orientation = abs(f.x) + abs(f.z) > 1e-4 ? ry(atan2(-f.x, -f.z)) : qIdentity
        }
        if let wingL, let wingR {
            let sp = min(1.3, max(0, p.wings))
            let flap = 0.06 * sin(t * 2.4)
            let base = poser.position[upperSpine]
            wingR.position = base + q.torso.act(V3(0.08, 0, wingDepth))
            wingL.position = base + q.torso.act(V3(-0.08, 0, wingDepth))
            wingR.orientation = q.torso * ry(-(1 - sp) * 1.1) * rz(sp * 0.35 - 0.12 + flap)
            wingL.orientation = q.torso * ry((1 - sp) * 1.1) * rz(-(sp * 0.35 - 0.12 + flap))
        }
        flag?.orientation = ry(0.28 * sin(t * 5.3) + 0.12 * sin(t * 8.7))
        if let float {
            switch floatMotion {
            case .none:
                break
            case .orbit(let sp):
                float.orientation = ry(t * sp)
                float.position = floatAnchor + V3(0, 0.05 * sin(t * 1.6), 0)
            case .halo(let sp):
                // 光輪は頭の骨に付け、胴の傾きに合わせる（大きさ・揺れはスキンの頭に合わせて縮める）
                float.orientation = q.torso * rz(t * sp)
                float.position = poser.position[headJoint]
                    + q.torso.act(haloOffset + V3(0, 0.02 * haloScale * sin(t * 1.3), 0))
            case .hover(let sp):
                float.orientation = ry(t * sp) * rz(0.15 * sin(t * 0.9))
                float.position = floatAnchor + V3(0, 0.06 * sin(t * 1.4), 0)
            }
        }
        // 次の通常攻撃が強い間は武器の先の光を灯す（姿勢の光を下から支える。詠唱・打撃の光はそのまま上に乗る）
        var lit = p
        if empoweredGlow > 0, animator.state != .dead { lit.glow = max(lit.glow, empoweredGlow) }
        effects.apply(lit, time: t, dead: animator.state == .dead, body: body)
    }
}
