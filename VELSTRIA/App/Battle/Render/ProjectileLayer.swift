import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。投射物の見た目（visual ID 別）。見た目はスタイル別プールで再利用する。
//   basic_attack: ヒーローはヒーロー別の形（HeroFXProfiles: 矢・水球・雷の投げ槍・光輪など。芯・殻・軌跡はヒーローの
//                 色、薄い光暈だけチーム色にして敵味方を読み分ける）。表に無いヒーローは汎用のチーム色の光弾。
//                 ミニオンはチーム色の小さな光弾。
//   tower_shot: タワー/Core の大きな光球（落下軌道）
//   empowered_attack: 強化通常攻撃（金白の大弾 + 軌跡）
//   それ以外: EffectDef（Projectile/Trail は細長い光条、その他は光球）を effect の scale で拡大し、スキル演出のパレット（SkillFX）で着色
// ヒーローの追尾弾は発射位置（HeroModelHandle.attackLaunchPoint = 武器の先端・弓・手）から出し、発射位置と sim の位置の
// ずれは残り距離に比例して消す（着弾点では sim の位置に一致する）。

@MainActor
final class ProjectileLayer {
    let root = Entity()
    private let materials: RenderMaterials
    private let meshes: UnitMeshLibrary
    private let shotMeshes = HeroShotMeshes()
    private let master: MasterData
    private var quality: RenderQuality

    enum Style: Hashable {
        /// 汎用のヒーローの通常攻撃（演出表に遠隔の形が無いヒーロー）。
        case heroBolt(Team)
        /// ヒーロー別の通常攻撃（HeroFXProfile.shot の形・色。光暈はチーム色）。
        case heroShot(heroID: String, team: Team)
        case minionBolt(Team)
        case tower(Team)
        case empowered
        /// 色相（0〜1000）と細長いか。
        case skill(hue: Int, streak: Bool)
    }

    /// 粒子の軌跡の見た目。借りた放出体へ毎回すべての項目を書き戻す（前に付いていた弾の値を残さない）。
    struct TrailLook: Equatable {
        var color: RGB
        var alpha: Double = 1
        /// 粒子の大きさ（m）。
        var size: Float
        var life: Double = 0.3
        /// 1 秒あたりの放出数（高画質の基準。画質の倍率を掛ける）。
        var birth: Int = 70
        var endSize: Float = 0.1
        var acceleration: SIMD3<Float> = .zero
        var speed: Float = 0.05
        /// 加算（光）か、半透明の重ね（煙）か。
        var additive = true
    }

    @MainActor
    final class Visual {
        let style: Style
        let entity = Entity()
        let core: ModelEntity
        let halo: ModelEntity
        var id: EntityID = 0
        /// 撃ったユニット（着弾演出の重要度の判定）。
        var owner: EntityID = 0
        var lastSeen = 0
        var startHeight: Float = 1
        var endHeight: Float = 1
        var startDistance: Double = 1
        var color: RGB
        var baseScale: SIMD3<Float>
        /// スキル弾の演出倍率（EffectDef.scaleM）。同じスタイルでも演出ごとに違うので、プールから出す時に合わせ直す。
        var effectScale: Float = 0
        /// 軌跡を付けるスタイル（塔・強化・スキル弾・粒子の尾を持つヒーロー別の弾）。
        var wantsTrail = false
        var trailLook: TrailLook
        /// 表示中に借りている軌跡の放出体。
        var trail: Entity?
        var yaw: Float = 0
        /// ヒーロー別の弾の形（nil = 汎用）。
        var shot: HeroFXProfile.Shot?
        /// 揺らぐ部品（光球の殻・矢の炎）とその基準の拡縮。
        var shell: ModelEntity?
        var shellScale = SIMD3<Float>(repeating: 1)
        /// 明滅で core と交互に出す形（雷）。
        var alt: ModelEntity?
        /// 回す部品（光輪）。
        var spinner: Entity?
        /// 発射位置と sim の位置の水平のずれ（残り距離に比例して消す）。
        var launchOffset = SIMD3<Float>.zero

        init(style: Style, core: ModelEntity, halo: ModelEntity, color: RGB, baseScale: SIMD3<Float>) {
            self.style = style
            self.core = core
            self.halo = halo
            self.color = color
            self.baseScale = baseScale
            trailLook = TrailLook(color: color, size: 0.1)
        }
    }

    /// 着弾演出用: 表示中の投射物の位置・色・スタイル・撃ったユニット・進行方向（水平の単位ベクトル）。
    struct HitInfo {
        var pos: SIMD3<Float>
        var color: RGB
        var style: Style
        var owner: EntityID
        var forward: SIMD3<Float>
    }

    private var active: [EntityID: Visual] = [:]
    private var list: [Visual] = []
    private var pools: [Style: [Visual]] = [:]
    private var stamp = 0
    /// 軌跡の放出体を作るか（試合開始時の画質で決める。試合中に画質が下がったら放出だけ止める）。
    private let buildsTrails: Bool
    /// 軌跡の放出体のプール。弾の見た目とは別のエンティティで、表示中の弾の位置へ毎フレーム合わせる。
    /// 付けたままの粒子系は 1 つにつき約 1 MB を常に持つ（シミュレータ実測）ため、弾の見た目ごとには付けず、
    /// 同時に飛ぶ軌跡付きの弾の数だけ持つ。尽きた時はその弾だけ軌跡なし（作らない）。
    private var freeTrails: [Entity] = []
    private var trailsPrewarmed = false
    /// 軌跡の放出体の数。観戦 9 分・4 倍速の headless 計測で同時に飛ぶ軌跡付きの弾の最大は 9（塔・スキル弾）、
    /// ヒーロー別の通常攻撃の尾（矢・水球・火球・矢弾・深淵の球）を足した計測では 7、遠隔 10 人の編成で 5。
    /// 尾を持つ遠隔 5 人が集団戦で 2 発ずつ飛ばす分（+10）を見込む。
    static let trailPoolSize = 20
    /// ヒーロー別の通常攻撃の弾の見た目の数（ヒーロー 1 人の同時の最大: 飛行 約 0.4 秒 ÷ 攻撃間隔 0.4 秒〜 + 視界の出入り）。
    static let heroShotPool = 4
    /// 汎用のヒーロー弾（演出表に無い遠隔ヒーロー）の見た目の数（チームあたり）。
    static let heroBoltPool = 6
    /// 汎用のヒーロー弾の予備（演出表のある編成でも試合中に作らないための最小限）。
    static let heroBoltSpare = 2
    /// 軌跡が尽きて省いた回数（計測用）。
    private(set) var trailsSkipped = 0
    private var trailsInUse = 0
    /// 同時に使った軌跡の最大（計測用）。
    private(set) var peakTrails = 0
    /// ヒーロー別の弾を出した数（計測・テスト用）。
    private(set) var heroShotsShown = 0
    /// 発射位置から出したヒーローの弾の数（計測・テスト用）。
    private(set) var launchedFromWeapon = 0

    /// ヒーロー別の弾の光暈（チーム色）の不透明度。形と色はヒーロー別でも、敵味方は光暈で読める。
    static let heroHaloAlpha = 0.3

    init(materials: RenderMaterials, meshes: UnitMeshLibrary, master: MasterData, quality: RenderQuality) {
        self.materials = materials
        self.meshes = meshes
        self.master = master
        self.quality = quality
        buildsTrails = quality.projectileTrails
        root.name = "projectiles"
        list.reserveCapacity(64)
    }

    func apply(quality q: RenderQuality) { quality = q }

    // MARK: 事前生成

    /// スタイルのプールが count 個になるまで作る（無効のまま。軌跡の放出体も構築して付けておく）。
    func prewarm(_ style: Style, visual: String, count: Int) {
        var have = pools[style]?.count ?? 0
        while have < count {
            recycle(make(style, visual: visual))
            have += 1
        }
    }

    /// プールに待機中の数（テスト・計測用）。
    func pooledCount(_ style: Style) -> Int { pools[style]?.count ?? 0 }

    /// 軌跡の放出体を作る（中・高画質。無効のまま部品を付けておく）。
    func prewarmTrails() {
        trailsPrewarmed = true
        guard buildsTrails else { return }
        while freeTrails.count < ProjectileLayer.trailPoolSize { freeTrails.append(makeTrail()) }
    }

    var pooledTrailCount: Int { freeTrails.count }

    private func makeTrail() -> Entity {
        AssetLedger.record(.entity, "projectile trail")
        AssetLedger.record(.emitter, "projectile trail")
        var p = ParticleEmitterComponent()
        p.fieldSimulationSpace = .global
        p.emitterShape = .sphere
        p.emitterShapeSize = SIMD3(repeating: 0.05)
        p.speed = 0.05
        var m = p.mainEmitter
        m.birthRate = Float(quality.particles(70))
        m.lifeSpan = 0.3
        m.size = 0.2
        m.sizeMultiplierAtEndOfLifespan = 0.1
        m.blendMode = .additive
        m.opacityCurve = .linearFadeOut
        m.color = .constant(.single(.white))
        m.isLightingEnabled = false
        p.mainEmitter = m
        p.timing = .repeating(warmUp: nil, emit: .init(duration: 10), idle: nil)
        let e = Entity()
        e.name = "projectileTrail"
        e.components.set(p)
        e.isEnabled = false
        root.addChild(e)
        return e
    }

    /// 表示を始めた弾に軌跡を付ける（見た目の項目を全て書き戻して restart。構築しない）。
    /// force = ウォームアップの陳列（画質の自動調整で今は切っていても、後で戻せるよう粒子系を幕の裏で一度動かす）。
    private func attachTrail(_ v: Visual, force: Bool = false) {
        guard v.wantsTrail, quality.projectileTrails || force, v.trail == nil else { return }
        let t: Entity
        if let e = freeTrails.popLast() {
            t = e
        } else if !trailsPrewarmed && buildsTrails {
            t = makeTrail()
        } else {
            trailsSkipped += 1
            return
        }
        guard var pe = t.components[ParticleEmitterComponent.self] else { return }
        let look = v.trailLook
        pe.mainEmitter.color = .constant(.single(look.color.uiColor(alpha: look.alpha)))
        pe.mainEmitter.size = look.size
        pe.mainEmitter.lifeSpan = look.life
        pe.mainEmitter.birthRate = Float(quality.particles(look.birth))
        pe.mainEmitter.sizeMultiplierAtEndOfLifespan = look.endSize
        pe.mainEmitter.acceleration = look.acceleration
        pe.mainEmitter.blendMode = look.additive ? .additive : .alpha
        pe.speed = look.speed
        pe.isEmitting = true
        pe.restart()
        t.position = v.entity.position
        t.components.set(pe)
        t.isEnabled = true
        v.trail = t
        trailsInUse += 1
        peakTrails = max(peakTrails, trailsInUse)
    }

    private func detachTrail(_ v: Visual) {
        guard let t = v.trail else { return }
        v.trail = nil
        trailsInUse -= 1
        if var pe = t.components[ParticleEmitterComponent.self] {
            pe.isEmitting = false
            t.components.set(pe)
        }
        t.isEnabled = false
        freeTrails.append(t)
    }

    /// ヒーローの通常攻撃のスタイル（演出表に遠隔の形があればヒーロー別、無ければ汎用の光弾）。
    static func basicStyle(heroID: String, team: Team) -> Style {
        HeroFXProfiles.profile(heroID)?.shot != nil ? .heroShot(heroID: heroID, team: team) : .heroBolt(team)
    }

    /// 試合で出うる投射物の見た目と、同時に必要になりうる数。
    /// 通常攻撃・塔はチーム別（ヒーローの通常攻撃は遠隔のヒーロー別）、スキル弾は試合のヒーローのスキル定義
    /// （SkillCatalog の照準 + EffectDef）から求める。
    /// 数は観戦 8 試合の headless 計測の最大（ヒーロー弾 3 / チーム・ミニオン弾 18・塔 3・スキル弾 2 / スタイル）に余裕を足した値。
    static func plannedStyles(state: SimState, master: MasterData) -> [(style: Style, visual: String, count: Int)] {
        var out: [(style: Style, visual: String, count: Int)] = []
        var genericTeams = Set<Team>()
        for team in Team.players {
            out.append((.minionBolt(team), "basic_attack", 24))
            out.append((.tower(team), "tower_shot", 5))
        }
        out.append((.empowered, "empowered_attack", 4))
        var seen = Set<Style>()
        for u in state.units where u.kind == .hero {
            guard let h = u.hero else { continue }
            let team: Team = u.team == .red ? .red : .blue
            if h.isRanged {
                let style = basicStyle(heroID: h.heroID, team: team)
                if case .heroBolt = style {
                    genericTeams.insert(team)
                } else if seen.insert(style).inserted {
                    out.append((style, "basic_attack", heroShotPool))
                }
            }
            guard let def = master.hero(h.heroID) else { continue }
            let hue = Int(Theme.heroHue(h.heroID) * 1000)
            for slot in SkillSlot.actives {
                guard let sk = master.skill(hero: h.heroID, slot: slot) else { continue }
                let t = SkillCatalog.targeting(for: sk, hero: def)
                let type = master.effect(sk.effectID)?.effectType
                let streakByType = type == .projectile || type == .trail
                let style: Style
                switch t.archetype {
                case .lineSkillshot: style = .skill(hue: hue, streak: streakByType)
                case .piercingLine: style = .skill(hue: hue, streak: true)
                case .blinkEmpower:
                    // 強化通常攻撃の追加弾（演出 ID が無ければ empowered_attack）
                    if sk.effectID.isEmpty { continue }
                    style = .skill(hue: hue, streak: streakByType)
                default: continue
                }
                guard seen.insert(style).inserted else { continue }
                out.append((style, sk.effectID, 3))
            }
        }
        // 汎用のヒーロー弾: 演出表に無い遠隔ヒーローのチームは計測どおり、それ以外も予備を少し（作らずに済ませる安全策）
        for team in Team.players {
            out.append((.heroBolt(team), "basic_attack", genericTeams.contains(team) ? heroBoltPool : heroBoltSpare))
        }
        return out
    }

    // MARK: ウォームアップ（読み込み幕の裏）

    private var warmupShown: [Visual] = []

    /// プールの見た目を全て陳列し、軌跡の放出体も全て一度ずつ動かす（粒子系の初期化を幕の裏で済ませる）。
    /// 軌跡は先に見た目（色・加算 / 半透明）の違う弾へ 1 つずつ付けてから残りへ付ける（放出体が尽きても全ての見た目を一度は動かす）。
    func showWarmup(slot: () -> SIMD3<Float>) {
        var shown: [Visual] = []
        for style in pools.keys.sorted(by: { "\($0)" < "\($1)" }) {
            guard let l = pools.removeValue(forKey: style) else { continue }
            for v in l {
                v.entity.position = slot()
                v.entity.isEnabled = true
                shown.append(v)
            }
        }
        var looks: [TrailLook] = []
        for v in shown where v.wantsTrail && !looks.contains(v.trailLook) {
            looks.append(v.trailLook)
            attachTrail(v, force: true)
        }
        for v in shown { attachTrail(v, force: true) }
        warmupShown.append(contentsOf: shown)
    }

    /// 陳列した見た目をプールへ戻す。
    func endWarmup() {
        for v in warmupShown { recycle(v) }
        warmupShown.removeAll()
        trailsInUse = 0
        peakTrails = 0
        trailsSkipped = 0
        heroShotsShown = 0
        launchedFromWeapon = 0
    }

    var count: Int { list.count }

    /// Effekseer の効果を持つヒーローの弾は、旧来の見た目（核・光・軌跡）を出さない（位置・命中の追跡は続ける）。
    var suppressedHeroes: Set<String> = []
    /// suppressedHeroes のうち、スキルの弾（.skill・.empowered）の見た目を残すヒーロー（スキルを SkillFX に任せるキットのヒーロー。
    /// 通常攻撃の弾は Effekseer の効果があるので隠す）。
    var skillShotsKept: Set<String> = []

    /// 弾の旧来の見た目を隠すか。
    private func isSuppressed(_ style: Style, hero: String) -> Bool {
        guard suppressedHeroes.contains(hero) else { return false }
        switch style {
        case .skill, .empowered: return !skillShotsKept.contains(hero)
        default: return true
        }
    }

    /// presentationEpoch の変化（シーク・再同期）: 飛んでいる弾を全て（軌跡ごと）プールへ戻す。
    /// 弾は ID で引くので、残すと前の時刻の弾が新しい位置へ飛び移る。次の sync で今の状態の弾だけを出し直す。
    func resetForPresentationEpoch() {
        for v in list { recycle(v) }
        list.removeAll(keepingCapacity: true)
        active.removeAll(keepingCapacity: true)
    }

    /// 着弾演出用: 表示中の投射物の情報。
    func info(_ id: EntityID) -> HitInfo? {
        guard let v = active[id] else { return nil }
        return HitInfo(pos: v.entity.position, color: v.color, style: v.style, owner: v.owner,
                       forward: SIMD3(-sin(v.yaw), 0, -cos(v.yaw)))
    }

    func style(for p: Projectile, state: SimState) -> Style {
        let owner = state.unit(p.ownerID)
        let team: Team = p.team == .red ? .red : .blue
        switch p.visual {
        case "basic_attack":
            guard let owner, owner.kind == .hero else { return .minionBolt(team) }
            return Self.basicStyle(heroID: owner.hero?.heroID ?? "", team: team)
        case "tower_shot":
            return .tower(team)
        case "empowered_attack":
            return .empowered
        default:
            let type = master.effect(p.visual)?.effectType
            let hue = owner?.hero.map { Theme.heroHue($0.heroID) } ?? 0.55
            return .skill(hue: Int(hue * 1000), streak: type == .projectile || type == .trail || p.pierce)
        }
    }

    // MARK: 生成

    private func make(_ style: Style, visual: String) -> Visual {
        AssetLedger.record(.entity, "projectile \(style)")
        let color: RGB
        var coreScale: SIMD3<Float>
        var haloScale: Float
        switch style {
        case .heroShot(let heroID, let team):
            if let profile = HeroFXProfiles.profile(heroID), let shot = profile.shot {
                return makeHeroShot(profile, shot: shot, style: style, team: team)
            }
            color = materials.teams.light(team); coreScale = [0.09, 0.09, 0.42]; haloScale = 0.24
        case .heroBolt(let t):
            color = materials.teams.light(t); coreScale = [0.09, 0.09, 0.42]; haloScale = 0.24
        case .minionBolt(let t):
            color = materials.teams.light(t); coreScale = [0.07, 0.07, 0.26]; haloScale = 0.16
        case .tower(let t):
            color = materials.teams.light(t); coreScale = [0.26, 0.26, 0.26]; haloScale = 0.55
        case .empowered:
            color = RGB(1.0, 0.92, 0.62); coreScale = [0.14, 0.14, 0.6]; haloScale = 0.38
        case .skill(let hue, let streak):
            if let heroID = SkillFXCatalog.heroID(forEffect: visual) {
                // スキル演出のパレット（SkillFX の travel と色をそろえる）
                color = SkillFXCatalog.palette(heroID).primary
            } else {
                let c = UIColor(hue: CGFloat(hue) / 1000, saturation: 0.6, brightness: 1, alpha: 1)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getRed(&r, green: &g, blue: &b, alpha: &a)
                color = RGB(Double(r), Double(g), Double(b))
            }
            (coreScale, haloScale) = Self.skillScales(effectScale(visual), streak: streak)
        }
        let core = ModelEntity(mesh: meshes.unitSphere, materials: [materials.unlit(color.mixed(RGB(1, 1, 1), 0.55))])
        core.scale = coreScale
        let halo = ModelEntity(mesh: meshes.unitSphere, materials: [materials.unlit(color, alpha: 0.35)])
        halo.scale = Self.haloScale(haloScale, core: coreScale)
        let v = Visual(style: style, core: core, halo: halo, color: color, baseScale: coreScale)
        if case .skill = style { v.effectScale = effectScale(visual) }
        v.entity.addChild(core)
        v.entity.addChild(halo)
        // 軌跡（中・高画質、目立つ弾のみ。放出体は表示中だけ軌跡のプールから借りる）
        switch style {
        case .tower, .empowered, .skill: v.wantsTrail = buildsTrails
        default: v.wantsTrail = false
        }
        v.trailLook = TrailLook(color: color, size: haloScale * 0.55)
        root.addChild(v.entity)
        return v
    }

    /// ヒーロー別の弾。芯・殻・形はヒーローの色（主色と白寄せの芯色）、外側の薄い光暈だけチーム色。
    /// 大きさはヒーロー（身長 約 1.7 m）に対して 0.2〜0.9 m（上方 12 m のカメラで形が読める下限）。
    private func makeHeroShot(_ profile: HeroFXProfile, shot: HeroFXProfile.Shot, style: Style, team: Team) -> Visual {
        let sphere = meshes.unitSphere
        let coreMat = materials.unlit(profile.core)
        let glowMat = materials.unlit(profile.primary, alpha: 0.5)
        func model(_ mesh: MeshResource?, _ material: UnlitMaterial, _ scale: SIMD3<Float>,
                   at p: SIMD3<Float> = .zero) -> ModelEntity {
            let e = ModelEntity(mesh: mesh ?? sphere, materials: [material])
            e.scale = scale
            e.position = p
            return e
        }
        func uniform(_ k: Float) -> SIMD3<Float> { SIMD3(repeating: k) }
        let one = uniform(1)
        let core: ModelEntity
        var halo: SIMD3<Float>
        var shell: ModelEntity?
        var alt: ModelEntity?
        var spinner: Entity?
        var parts: [ModelEntity] = []
        switch shot {
        case .arrow:
            // 燃える矢: 矢の形 + 鏃の炎（揺らぐ）
            core = model(shotMeshes.arrow, coreMat, one)
            shell = model(sphere, glowMat, [0.065, 0.065, 0.11], at: [0, 0, -0.25])
            halo = [0.1, 0.1, 0.42]
        case .bolt:
            // 連弩の矢弾: 太く短い矢 + 鏃の光
            core = model(shotMeshes.arrow, coreMat, [1.6, 1.6, 0.68])
            shell = model(sphere, glowMat, [0.07, 0.07, 0.09], at: [0, 0, -0.18])
            halo = [0.11, 0.11, 0.32]
        case .waterOrb:
            // 水球: 白寄せの水色の芯 + 半透明の殻（揺れる）
            core = model(sphere, coreMat, uniform(0.085))
            shell = model(sphere, materials.unlit(profile.primary, alpha: 0.4), uniform(0.17))
            halo = uniform(0.25)
        case .fireOrb:
            // 火球: 黄寄りの芯 + 橙の殻（速く揺らぐ）
            core = model(sphere, materials.unlit(profile.primary.mixed(RGB(1, 0.92, 0.6), 0.55)), uniform(0.095))
            shell = model(sphere, materials.unlit(profile.primary, alpha: 0.55), uniform(0.17))
            halo = uniform(0.25)
        case .lightOrb:
            // 灯火の光球: 小さな白い芯 + 大きく柔らかい殻（ゆっくり脈打つ）
            core = model(sphere, materials.unlit(profile.primary.mixed(RGB(1, 1, 1), 0.7)), uniform(0.075))
            shell = model(sphere, materials.unlit(profile.primary, alpha: 0.32), uniform(0.2))
            halo = uniform(0.27)
        case .abyssOrb:
            // 深淵の球: 紫の芯 + 暗い殻（回りながら脈打つ）
            core = model(sphere, coreMat, uniform(0.085))
            shell = model(sphere, materials.unlit(profile.primary.scaled(0.3), alpha: 0.65), uniform(0.18))
            halo = uniform(0.26)
        case .lightning:
            // 雷の投げ槍: ジグザグの光条 A / B を交互に出し、細い光の筋を重ねる
            core = model(shotMeshes.lightningA, coreMat, one)
            alt = model(shotMeshes.lightningB, coreMat, uniform(0.001))
            parts.append(model(sphere, glowMat, [0.05, 0.05, 0.45]))
            halo = [0.09, 0.09, 0.5]
        case .tracer:
            // 曳光弾: 極細の長い芯 + 主色の筋
            core = model(sphere, coreMat, [0.022, 0.022, 0.7])
            parts.append(model(sphere, glowMat, [0.05, 0.05, 0.85]))
            halo = [0.08, 0.08, 0.55]
        case .scatter:
            // 散弾: 幅広の光弾 + 小粒 3
            core = model(sphere, coreMat, [0.2, 0.07, 0.14])
            for p: SIMD3<Float> in [[-0.16, 0.02, 0.05], [0.16, -0.02, 0.05], [0, 0.05, -0.12]] {
                parts.append(model(sphere, coreMat, uniform(0.05), at: p))
            }
            halo = [0.3, 0.13, 0.26]
        case .haloRing:
            // 光輪: 傾けて回す（玉の位置で回転が見える）
            let s = Entity()
            core = model(shotMeshes.haloRing, coreMat, one)
            s.addChild(core)
            spinner = s
            halo = uniform(0.26)
        case .clawCrescent:
            // 爪の三日月: 細い弧 3 本 + 一回り大きい主色の弧（下に重ねて縁を光らせる）
            core = model(shotMeshes.clawCrescent, coreMat, one)
            parts.append(model(shotMeshes.clawCrescent, glowMat, [1.12, 1, 1.12], at: [0, -0.01, 0.03]))
            halo = [0.32, 0.07, 0.2]
        }
        let haloEntity = model(sphere, materials.unlit(materials.teams.light(team), alpha: Self.heroHaloAlpha), halo)
        let v = Visual(style: style, core: core, halo: haloEntity, color: profile.primary, baseScale: core.scale)
        v.shot = shot
        v.shell = shell
        v.shellScale = shell?.scale ?? one
        v.alt = alt
        v.spinner = spinner
        v.entity.addChild(spinner ?? core)
        for e in [alt, shell].compactMap({ $0 }) + parts { v.entity.addChild(e) }
        v.entity.addChild(haloEntity)
        if let t = profile.shotTrail {
            v.wantsTrail = buildsTrails
            v.trailLook = Self.trailLook(t, profile: profile)
        }
        root.addChild(v.entity)
        return v
    }

    /// ヒーロー別の弾の粒子の尾。
    static func trailLook(_ t: HeroFXProfile.ShotTrail, profile: HeroFXProfile) -> TrailLook {
        let c = profile.primary
        switch t {
        case .embers:
            return TrailLook(color: c.mixed(RGB(1, 0.85, 0.5), 0.3), size: 0.07, life: 0.38, birth: 60, endSize: 0.2,
                             acceleration: [0, 0.9, 0], speed: 0.3)
        case .droplets:
            return TrailLook(color: c.mixed(RGB(1, 1, 1), 0.35), size: 0.06, life: 0.32, birth: 55, endSize: 0.5,
                             acceleration: [0, -6, 0], speed: 0.45)
        case .fire:
            return TrailLook(color: c, size: 0.17, life: 0.22, birth: 80, endSize: 0.15, acceleration: [0, 1.4, 0],
                             speed: 0.1)
        case .smoke:
            return TrailLook(color: c.scaled(0.22), alpha: 0.7, size: 0.15, life: 0.45, birth: 45, endSize: 1.7,
                             acceleration: [0, 0.5, 0], speed: 0.08, additive: false)
        case .streak:
            return TrailLook(color: c, size: 0.08, life: 0.14, birth: 70, endSize: 0.1, speed: 0.03)
        }
    }

    /// スキル弾の演出倍率（EffectDef.scaleM。未定義は 1.2）。
    private func effectScale(_ visual: String) -> Float {
        Float(master.effect(visual)?.scaleM ?? 1.2)
    }

    /// スキル弾の芯の拡大率と光暈の半径。
    static func skillScales(_ k: Float, streak: Bool) -> (core: SIMD3<Float>, halo: Float) {
        (streak ? [0.14 * k, 0.14 * k, 0.75 * k] : SIMD3(repeating: 0.22 * k), 0.36 * k)
    }

    private static func haloScale(_ halo: Float, core: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(halo, halo, max(halo, core.z * 0.8))
    }

    private func take(_ style: Style, visual: String) -> Visual {
        if var l = pools[style], let v = l.popLast() {
            pools[style] = l
            // スキル弾はスタイル（色・細長さ）が同じでも演出ごとに大きさが違う（例: Ranger のスキル 1 と奥義）
            if case .skill(_, let streak) = style {
                let k = effectScale(visual)
                if k != v.effectScale { resize(v, effectScale: k, streak: streak) }
            }
            return v
        }
        return make(style, visual: visual)
    }

    private func resize(_ v: Visual, effectScale k: Float, streak: Bool) {
        let (core, halo) = Self.skillScales(k, streak: streak)
        v.effectScale = k
        v.baseScale = core
        v.core.scale = core
        v.halo.scale = Self.haloScale(halo, core: core)
        v.trailLook.size = halo * 0.55
        if let t = v.trail, var p = t.components[ParticleEmitterComponent.self] {
            p.mainEmitter.size = v.trailLook.size
            t.components.set(p)
        }
    }

    /// 表示中の投射物の芯の拡大率（テスト用）。
    func coreScale(of id: EntityID) -> SIMD3<Float>? { active[id]?.core.scale }

    /// 表示中の投射物の位置（テスト用）。
    func position(of id: EntityID) -> SIMD3<Float>? { active[id]?.entity.position }

    private func recycle(_ v: Visual) {
        v.entity.isEnabled = false
        detachTrail(v)
        pools[v.style, default: []].append(v)
    }

    // MARK: 同期

    /// launchPoint = ヒーローの発射位置（ワールド、HeroModelHandle.attackLaunchPoint。nil なら従来の高さの規則）。
    func sync(_ f: RenderFrame, heightOf: (EntityID) -> Float,
              launchPoint: (EntityID) -> SIMD3<Float>? = { _ in nil }) {
        stamp &+= 1
        let state = f.state
        for k in state.projectiles.indices {
            let p = state.projectiles[k]
            if p.done { continue }
            // 視点チームから見えない位置の敵弾は描かない
            if let viewer = f.viewerTeam, p.team != viewer, !state.vision.isLit(p.pos, for: viewer) {
                if let v = active.removeValue(forKey: p.id) { detach(v) }
                continue
            }
            let v: Visual
            var isNew = false
            let pos = Vec2.lerp(p.prevPos, p.pos, Double(f.alpha))
            if let existing = active[p.id] {
                v = existing
            } else {
                v = take(style(for: p, state: state), visual: p.visual)
                v.id = p.id
                v.owner = p.ownerID
                v.launchOffset = .zero
                let owner = state.unit(p.ownerID)
                if let owner, owner.isStructure {
                    v.startHeight = owner.kind == .core ? 3.6 : 4.9
                } else {
                    v.startHeight = owner.map { heightOf($0.id) * 0.6 } ?? 1
                    // ヒーローの追尾弾は武器の先端・弓・手から出す（高さと水平のずれ。ずれは残り距離に比例して消す）
                    if owner?.kind == .hero, case .homing = p.motion, let lp = launchPoint(p.ownerID) {
                        let simWorld = worldPosition(pos)
                        let off = SIMD3<Float>(lp.x - simWorld.x, 0, lp.z - simWorld.z)
                        if simd_length(off) < 2.5, lp.y > 0.05, lp.y < 4 {
                            v.startHeight = lp.y
                            v.launchOffset = off
                            launchedFromWeapon += 1
                        }
                    }
                }
                v.endHeight = 1.0
                if case .homing(let tid) = p.motion, let t = state.unit(tid) {
                    v.startDistance = max(1, pos.distance(to: t.pos))
                    v.endHeight = t.isStructure ? 1.6 : heightOf(tid) * 0.5
                } else {
                    v.startDistance = 1
                    v.endHeight = v.startHeight
                }
                if v.shot != nil { heroShotsShown += 1 }
                active[p.id] = v
                list.append(v)
                v.entity.isEnabled = true
                isNew = true
            }
            v.lastSeen = stamp
            var h = v.startHeight
            var remaining: Float = 1
            if case .homing(let tid) = p.motion, let t = state.unit(tid) {
                remaining = Float(min(1, pos.distance(to: t.pos) / v.startDistance))
                h = v.endHeight + (v.startHeight - v.endHeight) * remaining
            }
            v.entity.position = worldPosition(pos, height: h) + v.launchOffset * remaining
            let d = p.pos - p.prevPos
            if d.lengthSquared > 1e-6 {
                v.yaw = Float(atan2(d.y, d.x)) - .pi / 2
            }
            v.entity.orientation = simd_quatf(angle: v.yaw, axis: [0, 1, 0])
            // 軌跡は弾の位置に合わせる（試合中に軌跡が切られた間 = 画質の自動調整では付けない）
            let suppressed = !suppressedHeroes.isEmpty && state.unit(p.ownerID)?.hero.map { isSuppressed(v.style, hero: $0.heroID) } == true
            if suppressed { v.entity.isEnabled = false }
            if isNew, !suppressed { attachTrail(v) }
            v.trail?.position = v.entity.position
            if case .tower = v.style {
                let s = 1 + sin(f.time * 30 + Float(p.id)) * 0.12
                v.core.scale = v.baseScale * s
            }
            if let shot = v.shot { animate(v, shot, time: f.time) }
        }
        var k = 0
        while k < list.count {
            let v = list[k]
            if v.lastSeen != stamp {
                if active[v.id] === v { active[v.id] = nil }
                list.swapAt(k, list.count - 1)
                list.removeLast()
                recycle(v)
            } else {
                k += 1
            }
        }
    }

    /// ヒーロー別の弾の動き（揺らぎ・明滅・回転。値の書き換えだけ）。
    private func animate(_ v: Visual, _ shot: HeroFXProfile.Shot, time t: Float) {
        let ph = Float(v.id % 97) * 0.37
        switch shot {
        case .arrow, .bolt:
            v.shell?.scale = v.shellScale * (1 + 0.25 * sin(t * 47 + ph))
        case .fireOrb:
            v.shell?.scale = v.shellScale * (1 + 0.14 * sin(t * 38 + ph) + 0.07 * sin(t * 61 + ph * 2))
            v.core.scale = v.baseScale * (1 + 0.1 * sin(t * 53 + ph))
        case .waterOrb:
            let w = 0.08 * sin(t * 17 + ph)
            v.shell?.scale = v.shellScale * SIMD3(1 + w, 1 - w, 1)
        case .lightOrb:
            v.shell?.scale = v.shellScale * (1 + 0.1 * sin(t * 9 + ph))
        case .abyssOrb:
            v.shell?.scale = v.shellScale * (1 + 0.08 * sin(t * 7 + ph))
            v.shell?.orientation = simd_quatf(angle: t * 3, axis: [0, 1, 0])
        case .lightning:
            // 1/30 秒ごとに A・B を入れ替え、進行方向の軸まわりに転がして明滅させる
            let frame = Int(t * 30) + Int(v.id % 1000)
            let showA = frame % 2 == 0
            let hidden = SIMD3<Float>(repeating: 0.001)
            v.core.scale = showA ? v.baseScale : hidden
            v.alt?.scale = showA ? hidden : v.baseScale
            let roll = simd_quatf(angle: Float((frame * 7919) % 360) * .pi / 180, axis: [0, 0, 1])
            v.core.orientation = roll
            v.alt?.orientation = roll
        case .haloRing:
            v.spinner?.orientation = simd_quatf(angle: 0.5, axis: [1, 0, 0]) * simd_quatf(angle: t * 12, axis: [0, 1, 0])
        case .tracer, .scatter, .clawCrescent:
            break
        }
    }

    private func detach(_ v: Visual) {
        if let k = list.firstIndex(where: { $0 === v }) {
            list.swapAt(k, list.count - 1)
            list.removeLast()
        }
        recycle(v)
    }

    func teardown() {
        root.removeFromParent()
        active.removeAll()
        list.removeAll()
        pools.removeAll()
    }
}
