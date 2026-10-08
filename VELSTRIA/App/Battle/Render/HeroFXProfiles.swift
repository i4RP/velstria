import Foundation
import VelstriaCore

// 担当: battle-renderer。ヒーロー別の通常攻撃の演出表（近接の武器の軌跡・着弾・遠隔の投射物・発射炎・発射位置）。
//
// 色はヒーローの造形設計（HeroBlueprints）の glow を主色、accent を副色にする。Theme.heroHue（UI の基調色）は使わない:
// 基調色は衣装の色で、武器・魔法の光（炎・水・雷）と合わないヒーローが多い（例: 水の杖のミレアの基調色は橙）。
// 投射物は形・芯・軌跡をヒーロー別にし、敵味方の読み分けはチーム色の薄い光暈で残す（ProjectileLayer）。
// 表に無いヒーロー（H001〜H034 以外）は nil = 従来の汎用演出（チーム色の光弾・火花）。

struct HeroFXProfile: Equatable {
    /// 近接の武器の軌跡（WeaponTrail）。
    struct Trail: Equatable {
        /// 帯の内端・外端（握り → 先端を 0 → 1 とした比。1 を超えると先端より外まで伸ばす）。
        var inner: Float
        var outer: Float
        /// 帯の 1 点が消えるまでの秒（長いほど長く尾を引く）。
        var life: Float
        var look: TrailLook
        /// 帯の最大の不透明度（明るい色でもブルームで白飛びしない程度）。
        var opacity: Float
    }

    /// 軌跡のテクスチャの型（濃淡の分布）。
    enum TrailLook: CaseIterable {
        /// 刃: 先端寄りがくっきり明るく、根元へ抜ける。
        case blade
        /// 細い: 先端付近の細い帯だけ（細剣・針）。
        case thin
        /// 柔らかい: 幅広く縁がぼける（霧・風・花弁）。
        case soft
        /// 重い: 幅広く濃い（槌・棍棒・拳）。
        case heavy
    }

    /// 着弾（近接の打撃・遠隔の命中）の演出の型。
    enum Impact: CaseIterable {
        /// 刃の火花（振りの向きへ扇状）。
        case slash
        /// 突きの火花（細く前へ）。
        case pierce
        /// 星のきらめき。
        case sparkle
        /// 鈍器（燃えさし + 地面の小さな輪）。
        case blunt
        /// 重い鈍器（燃えさし + 大きな輪 + 破片）。
        case heavyBlunt
        /// 突風の輪（地面の輪 + 細い火花）。
        case gust
        /// 水しぶき。
        case splash
        /// 燃えさしの弾け。
        case embers
        /// 炎の弾け（燃えさし + 閃光）。
        case fireBurst
        /// 電撃（伸びる火花 + 閃光）。
        case electric
        /// 金属・砂の火花。
        case sparks
        /// 環の閃光（閃光 + 地面の輪）。
        case ringFlash
        /// 柔らかい光の弾け。
        case softBurst
        /// 深淵の弾け。
        case abyssBurst
    }

    /// 遠隔の通常攻撃の投射物の形（ProjectileLayer）。
    enum Shot: CaseIterable {
        case arrow, bolt, waterOrb, fireOrb, lightOrb, abyssOrb, lightning, tracer, scatter, haloRing, clawCrescent
    }

    /// 投射物の粒子の軌跡（ProjectileLayer の軌跡のプールから借りる）。
    enum ShotTrail: CaseIterable {
        /// 舞い上がる火の粉。
        case embers
        /// 落ちる水滴。
        case droplets
        /// 炎。
        case fire
        /// 暗い煙（半透明の重ね。加算だと暗い色が見えない）。
        case smoke
        /// 短い光の筋。
        case streak
    }

    /// 遠隔の発射の瞬間の演出（発射位置に出す）。
    enum Muzzle: CaseIterable {
        case none
        /// 弓: 小さな閃光。
        case bow
        /// 杖・詠唱: 小さな閃光。
        case cast
        /// 掌の炎: 炎の閃光 + 前へ吹く粒子。
        case flame
        /// 連弩: 機械の閃光 + 前へ吹く火花。
        case mech
        /// 大筒: 大きな閃光 + 前へ吹く粒子。
        case blast
        /// 長銃: 小さな閃光 + 前へ吹く煙っぽい粒子。
        case rifle
        /// 爪: 小さな閃光。
        case claw
        /// 雷槍: 閃光 + 火花。
        case spark
    }

    /// 発射位置の出所（HeroModelHandle.attackLaunchPoint の規則の記録。描画側は handle の点をそのまま使う）。
    enum Launch: CaseIterable {
        /// 右手武器の先端（杖・槍・銃口・掌の炎）。
        case weaponTip
        /// 副手の弓の握り（H003）。
        case bow
        /// 手のひら（体に付ける籠手・爪。左手で打つクリップなら左手）。
        case hands
    }

    let heroID: String
    /// 主色（blueprint.glow）。
    let primary: RGB
    /// 副色（blueprint.accent）。
    let secondary: RGB
    /// 近接の武器の軌跡（遠隔は nil）。
    let trail: Trail?
    let impact: Impact
    /// 遠隔の投射物（近接は nil）。
    let shot: Shot?
    let shotTrail: ShotTrail?
    let muzzle: Muzzle
    let launch: Launch

    var isRanged: Bool { shot != nil }

    /// 芯の色（主色を白へ寄せる。ブルームの閾値 0.6 を超える明るさ）。
    var core: RGB { primary.mixed(RGB(1, 1, 1), 0.5) }
}

enum HeroFXProfiles {
    /// heroID の演出表。表に無いヒーローは nil（従来の汎用演出）。
    static func profile(_ heroID: String) -> HeroFXProfile? { table[heroID] }

    /// ヒーローの演出の主色（blueprint.glow。表に無いヒーローもロールから近い設計図の glow）。
    /// スキル演出・瞬間移動などヒーロー色の演出は全てこれを使う。
    static func primaryColor(heroID: String, role: Role? = nil) -> RGB {
        if let p = table[heroID] { return p.primary }
        return rgb(HeroBlueprints.blueprint(heroID: heroID, role: role).glow)
    }

    /// HSB（色相 0〜1 の循環）→ sRGB。
    static func rgb(_ c: HSB) -> RGB {
        let h = (c.h - floor(c.h)) * 6
        let s = min(1, max(0, c.s)), v = min(1, max(0, c.b))
        let f = h - floor(h)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch Int(h) % 6 {
        case 0: return RGB(v, t, p)
        case 1: return RGB(q, v, p)
        case 2: return RGB(p, v, t)
        case 3: return RGB(p, q, v)
        case 4: return RGB(t, p, v)
        default: return RGB(v, p, q)
        }
    }

    // MARK: 表

    private typealias T = HeroFXProfile.Trail

    /// 近接の軌跡の型（幅 = inner〜outer、長さ = life）。ヒーロー身長 約 1.7 m に対して武器の長さ 0.2〜1.4 m。
    private enum Trails {
        /// 広刃剣: 刃の外 3/4、やや長め。
        static let broadsword = T(inner: 0.28, outer: 1.06, life: 0.16, look: .blade, opacity: 0.85)
        /// 細剣の突き: 先端付近の細い帯。
        static let rapier = T(inner: 0.5, outer: 1.06, life: 0.13, look: .thin, opacity: 0.85)
        /// 三日月の短刀（左手は灯籠の火袋の光の筋）: 短い。
        static let crescent = T(inner: 0.3, outer: 1.12, life: 0.12, look: .blade, opacity: 0.8)
        /// 籠手: 拳の周りの短く太い帯（拳は短いので握り → 拳の外まで広げる）。
        static let fist = T(inner: -0.4, outer: 1.7, life: 0.1, look: .heavy, opacity: 0.6)
        /// 旗槍の突き: 穂先寄りの風の帯。
        static let banner = T(inner: 0.5, outer: 1.06, life: 0.18, look: .soft, opacity: 0.75)
        /// 硝子の短剣（二刀交互）: 短く鋭い。
        static let glassDagger = T(inner: 0.2, outer: 1.15, life: 0.12, look: .blade, opacity: 0.8)
        /// 骨の棍棒: 短く重い。
        static let club = T(inner: 0.42, outer: 1.06, life: 0.14, look: .heavy, opacity: 0.8)
        /// 霧の刀 + 小太刀: 長く柔らかい霧。
        static let mist = T(inner: 0.15, outer: 1.1, life: 0.24, look: .soft, opacity: 0.7)
        /// 花弁の双刃。
        static let petal = T(inner: 0.25, outer: 1.12, life: 0.16, look: .soft, opacity: 0.8)
        /// 攻城槌: 槌頭の重い熱の帯、長め。
        static let hammer = T(inner: 0.45, outer: 1.1, life: 0.2, look: .heavy, opacity: 0.85)
        /// 光矢の刃。
        static let lightBlade = T(inner: 0.3, outer: 1.06, life: 0.14, look: .blade, opacity: 0.85)
        /// 夢の針（二刀）: 細い糸。
        static let needle = T(inner: 0.35, outer: 1.1, life: 0.15, look: .thin, opacity: 0.8)
        /// 竜牙の長槍: 穂先寄りの鋭い突きの帯。
        static let dragonSpear = T(inner: 0.55, outer: 1.06, life: 0.16, look: .blade, opacity: 0.85)
        /// 光刃の長剣: 刃全体に長く尾を引く光の帯。
        static let photonBlade = T(inner: 0.2, outer: 1.08, life: 0.2, look: .blade, opacity: 0.85)
        /// 聖槌: 槌頭の重い光の帯。
        static let holyMaul = T(inner: 0.4, outer: 1.12, life: 0.18, look: .heavy, opacity: 0.8)
        /// 拳剣: 拳の先から伸びる刃の短く鋭い帯。
        static let fistBlade = T(inner: 0.25, outer: 1.1, life: 0.14, look: .blade, opacity: 0.85)
        /// 血の大剣: 長い刃に重く尾を引く帯。
        static let greatsword = T(inner: 0.25, outer: 1.08, life: 0.22, look: .heavy, opacity: 0.85)
        /// 鎖鉤: 鎖の長さいっぱいに流れる柔らかい帯。
        static let hookChain = T(inner: 0.15, outer: 1.1, life: 0.22, look: .soft, opacity: 0.75)
    }

    private struct Spec {
        var trail: T?
        var impact: HeroFXProfile.Impact
        var shot: HeroFXProfile.Shot?
        var shotTrail: HeroFXProfile.ShotTrail?
        var muzzle: HeroFXProfile.Muzzle
        var launch: HeroFXProfile.Launch
    }

    /// ヒーロー別の型（色は設計図から）。M = 近接（射程 150）、R = 遠隔（射程 550）。
    private static let specs: [String: Spec] = [
        // M アルデン: 金の聖なる斬撃の帯、重い斬撃の火花
        "H001": Spec(trail: Trails.broadsword, impact: .slash, muzzle: .none, launch: .weaponTip),
        // M リラ: 水色の星明かりの細い帯、星のきらめきの突き
        "H002": Spec(trail: Trails.rapier, impact: .sparkle, muzzle: .none, launch: .weaponTip),
        // R フィリエル（月弓）: 副手の弓から月光の矢（光の筋の尾）、月光のきらめき
        "H003": Spec(impact: .sparkle, shot: .arrow, shotTrail: .streak, muzzle: .bow, launch: .bow),
        // R ミレア: 水の球（水色の芯 + 半透明の殻）と水滴の尾、水しぶき
        "H004": Spec(impact: .splash, shot: .waterOrb, shotTrail: .droplets, muzzle: .cast, launch: .weaponTip),
        // R ヴォス: 紫の雷の投げ槍（細長く明滅）、電撃の火花
        "H005": Spec(impact: .electric, shot: .lightning, muzzle: .spark, launch: .weaponTip),
        // M セレン: 淡い月金の短い三日月の帯（左手は灯籠の光）、小さな三日月の火花
        "H006": Spec(trail: Trails.crescent, impact: .slash, muzzle: .none, launch: .weaponTip),
        // M ガルク: 溶岩の拳（燃えさし + 地面の小さな輪）、短い拳の帯
        "H007": Spec(trail: Trails.fist, impact: .blunt, muzzle: .none, launch: .hands),
        // M ニア: 青緑の風の帯（旗槍の突き）、突風の輪
        "H008": Spec(trail: Trails.banner, impact: .gust, muzzle: .none, launch: .weaponTip),
        // R オリン: 琥珀の矢弾（短い尾）、機械の発射炎、金属の火花
        "H009": Spec(impact: .sparks, shot: .bolt, shotTrail: .streak, muzzle: .mech, launch: .weaponTip),
        // R テッサ: 掌の炎から火球（橙の芯が揺らぐ・炎の尾）、炎の弾け
        "H010": Spec(impact: .fireBurst, shot: .fireOrb, shotTrail: .fire, muzzle: .flame, launch: .weaponTip),
        // R ルーク: 水色の灯火の光球、柔らかい水色の弾け
        "H011": Spec(impact: .softBurst, shot: .lightOrb, muzzle: .cast, launch: .weaponTip),
        // M エリネ: 淡い水色の硝子の帯（左右交互）、破片の火花
        "H012": Spec(trail: Trails.glassDagger, impact: .slash, muzzle: .none, launch: .weaponTip),
        // M ダガン: 赤い荒々しい打撃（土埃の輪 + 赤い火花）、短く重い帯
        "H013": Spec(trail: Trails.club, impact: .blunt, muzzle: .none, launch: .weaponTip),
        // M シオ: 淡い青の霧の帯（長く柔らかい）、霧の斬撃の火花
        "H014": Spec(trail: Trails.mist, impact: .slash, muzzle: .none, launch: .weaponTip),
        // R ヴァルカ: 大きな金の発射炎 + 散弾（小粒 3 + 幅広の光弾）、金の火花
        "H015": Spec(impact: .sparks, shot: .scatter, muzzle: .blast, launch: .weaponTip),
        // R イリス: 白金の回る光輪、環の閃光
        "H016": Spec(impact: .ringFlash, shot: .haloRing, muzzle: .cast, launch: .weaponTip),
        // R モルド: 紫の深淵の球と暗い煙の尾、紫の弾け
        "H017": Spec(impact: .abyssBurst, shot: .abyssOrb, shotTrail: .smoke, muzzle: .cast, launch: .weaponTip),
        // M セリア: 桃色の花弁の帯、花弁の弾け
        "H018": Spec(trail: Trails.petal, impact: .sparkle, muzzle: .none, launch: .weaponTip),
        // M ブラム: 橙の熱の重い帯（両手の大槌）、地面の輪と破片を伴う大きな打撃
        "H019": Spec(trail: Trails.hammer, impact: .heavyBlunt, muzzle: .none, launch: .weaponTip),
        // M ユナ: 金の光の帯、金の突きの火花
        "H020": Spec(trail: Trails.lightBlade, impact: .pierce, muzzle: .none, launch: .weaponTip),
        // R キロス: 砂金の曳光弾（細長い筋）、小さな銃口の煙と閃光、金の火花
        "H021": Spec(impact: .sparks, shot: .tracer, muzzle: .rifle, launch: .weaponTip),
        // R レア: 手から蒼い爪の三日月（細い弧 3 本）、蒼い斬撃
        "H022": Spec(impact: .slash, shot: .clawCrescent, muzzle: .claw, launch: .hands),
        // R トレン: 青白い雷の投げ槍、電撃
        "H023": Spec(impact: .electric, shot: .lightning, muzzle: .spark, launch: .weaponTip),
        // M ノア: 紫の夢の糸の細い帯、小さな紫のきらめき
        "H024": Spec(trail: Trails.needle, impact: .sparkle, muzzle: .none, launch: .weaponTip),
        // R ルミナ: 副手の三日月の長弓から月光の矢（光の筋の尾）、柔らかい月光の弾け
        "H025": Spec(impact: .softBurst, shot: .arrow, shotTrail: .streak, muzzle: .bow, launch: .bow),
        // R エウリア: 雷杖の先から電光の光球（光の筋の尾）、電撃
        "H026": Spec(impact: .electric, shot: .lightOrb, shotTrail: .streak, muzzle: .spark, launch: .weaponTip),
        // M ジャルド: 銀青の竜槍の突きの帯、突きの火花
        "H027": Spec(trail: Trails.dragonSpear, impact: .pierce, muzzle: .none, launch: .weaponTip),
        // M ザイル: シアンの光刃の長い帯、刃の火花
        "H028": Spec(trail: Trails.photonBlade, impact: .slash, muzzle: .none, launch: .weaponTip),
        // M ボルグ: 金白の聖槌の重い帯、地面の輪と破片を伴う大きな打撃
        "H029": Spec(trail: Trails.holyMaul, impact: .heavyBlunt, muzzle: .none, launch: .weaponTip),
        // R ライナ: 星砲の砲口から桃の光弾（光の筋の尾）、大きな発射炎、炎の弾け
        "H030": Spec(impact: .fireBurst, shot: .lightOrb, shotTrail: .streak, muzzle: .blast, launch: .weaponTip),
        // R オーリア: 氷の杖の先から氷青の水球（光の筋の尾）、氷のきらめき
        "H031": Spec(impact: .sparkle, shot: .waterOrb, shotTrail: .streak, muzzle: .cast, launch: .weaponTip),
        // M ディアス: 赤い拳剣の短く鋭い帯、赤い燃えさしの弾け
        "H032": Spec(trail: Trails.fistBlade, impact: .embers, muzzle: .none, launch: .weaponTip),
        // M ヴァルド: 深紅の大剣の重い帯、刃の火花
        "H033": Spec(trail: Trails.greatsword, impact: .slash, muzzle: .none, launch: .weaponTip),
        // M ゴルム: 錆びた赤の鎖鉤の柔らかい長い帯、鈍い打撃（燃えさし + 地面の小さな輪）
        "H034": Spec(trail: Trails.hookChain, impact: .blunt, muzzle: .none, launch: .weaponTip),
    ]

    private static let table: [String: HeroFXProfile] = {
        var out: [String: HeroFXProfile] = [:]
        for (id, s) in specs {
            let bp = HeroBlueprints.blueprint(heroID: id, role: nil)
            out[id] = HeroFXProfile(heroID: id, primary: rgb(bp.glow), secondary: rgb(bp.accent), trail: s.trail,
                                    impact: s.impact, shot: s.shot, shotTrail: s.shotTrail, muzzle: s.muzzle,
                                    launch: s.launch)
        }
        return out
    }()

    /// 表のヒーロー ID（テスト用）。
    static var heroIDs: [String] { table.keys.sorted() }
}
