import Foundation
import RealityKit
import VelstriaCore

// 担当: battle-renderer（スキル演出）。スキル固有演出の記述（データ）。再生は SkillFXPlayer。
//
// 1 つのスキルの演出（SkillFXRecipe）は段（phase）ごとの「合図」（FXCue）の並び:
//   cast      発動の瞬間（術者の足元が原点。前方 = 術者 → 照準）
//   telegraph 予告ゾーンが置かれた瞬間（ゾーンの中心が原点。発動までの溜め）
//   travel    投射物に付いて飛ぶ（投射物が原点。前方 = 進行方向。継続放出は着弾・消滅で止まる）
//   impact    発動・着弾・着地（中心が原点。前方 = 術者 → 中心）
//   hit       スキルで傷を負った相手ごと（被弾者が原点。前方 = 術者 → 被弾者）
// 合図の位置は原点からの局所座標（x = 右、y = 上、z = 前）で書く。
// 色はヒーローのパレットの役割（FXTint）で書く。材質・粒子画像は試合開始前に全て作る（SkillFXPlayer.prewarm）。

// MARK: - 色

/// 色の役割。
enum FXTint: Hashable, Sendable {
    /// 白に近い芯の色（パレットの core）。
    case core
    case primary
    case secondary
    case accent
    /// 暗い色（煙・亀裂・影。アルファ合成で使う）。
    case dark
    case white
    case rgb(Double, Double, Double)
}

/// ヒーローの演出パレット。
struct FXPalette: Sendable {
    var core: RGB
    var primary: RGB
    var secondary: RGB
    var accent: RGB
    var dark: RGB

    func rgb(_ t: FXTint) -> RGB {
        switch t {
        case .core: return core
        case .primary: return primary
        case .secondary: return secondary
        case .accent: return accent
        case .dark: return dark
        case .white: return RGB(1, 1, 1)
        case .rgb(let r, let g, let b): return RGB(r, g, b)
        }
    }

    /// 単色から作る既定のパレット。
    static func from(_ c: RGB) -> FXPalette {
        FXPalette(core: c.mixed(RGB(1, 1, 1), 0.75), primary: c, secondary: c.mixed(RGB(1, 1, 1), 0.35),
                  accent: c.mixed(RGB(1, 0.85, 0.4), 0.5), dark: c.mixed(RGB(0, 0, 0), 0.8))
    }
}

// MARK: - 基準位置

enum FXAnchor: Hashable, Sendable {
    /// 段の原点（cast = 発動時の術者の足元、impact = 中心、hit = 被弾者の足元、travel = 投射物）。固定。
    case origin
    /// 段の主体に追従（cast = 術者、hit = 被弾者、travel = 投射物。impact・telegraph では origin と同じ）。
    case follow
    /// 照準点（cast の照準・着地点。impact・telegraph では中心）。
    case target
    /// 術者 → 照準点の線上（0 = 術者、1 = 照準点）。
    case along(Float)
}

// MARK: - 粒子

/// 粒子の放出形状（大きさは m）。
enum FXEmitShape: Hashable, Sendable {
    case point
    /// 球（半径）。
    case sphere(Float)
    /// 地面の円盤（半径）。
    case disc(Float)
    /// 円周（半径。地面の輪の上から出る）。
    case ring(Float)
    /// 直方体（右・上・前の幅）。
    case box(SIMD3<Float>)
    /// 前方への線（長さ。原点から前へ）。
    case line(Float)
}

/// 粒子の飛ぶ向き。
enum FXEmitDirection: Hashable, Sendable {
    /// 放出形状の法線（外向き）。
    case outward
    case up
    case down
    case forward
    case backward
    /// 局所座標の向き（右・上・前）。
    case local(SIMD3<Float>)
}

/// 粒子の板の向き。
enum FXOrient: Hashable, Sendable {
    /// 常にカメラを向く。
    case billboard
    /// 縦軸を保ったままカメラを向く（炎・光柱）。
    case upright
    /// 地面に寝かせる（衝撃波・魔法陣。画像の上 = 前方）。
    case ground
    /// 前方を向いて立てる（前方へ放つ斬撃・盾面）。
    case facing
}

/// 粒子の一斉放出・継続放出（ParticleEmitterComponent の全項目をここから書く）。
struct FXEmit: Hashable, Sendable {
    var tex: FXTex = .glow
    var tint: FXTint = .primary
    /// 寿命の終わりの色（nil = 変化なし）。
    var tintEnd: FXTint?
    /// 粒子数（emit = 0 なら一斉、> 0 ならその秒数で放出）。画質で減らす。
    var count: Int = 12
    /// 放出時間（秒）。0 = 一斉放出。
    var emit: Float = 0
    /// 継続放出（毎秒の数）。> 0 の時は止めるまで出し続ける（travel・follow 用。count・emit は無視）。
    var rate: Float = 0
    /// 継続放出の長さ（秒。0 = 主体が消えるまで）。
    var duration: Float = 0
    var life: Float = 0.5
    /// 寿命のばらつき（比）。
    var lifeVar: Float = 0.2
    var size: Float = 0.2
    /// 大きさのばらつき（比）。
    var sizeVar: Float = 0.3
    /// 寿命の終わりの大きさの倍率。
    var grow: Float = 1
    var shape: FXEmitShape = .point
    /// 形状の表面から出す（false = 内部から）。
    var surface = false
    var dir: FXEmitDirection = .outward
    var speed: Float = 0
    /// 速さのばらつき（比）。
    var speedVar: Float = 0.3
    /// 放出の広がり（度）。
    var spread: Float = 0
    /// 重力（下向きの加速度、m/s²。負なら上昇）。
    var gravity: Float = 0
    /// 減衰。
    var drag: Float = 0
    var orient: FXOrient = .billboard
    /// 板の回転（度）・ばらつき（度）・回転速度（度/秒）。
    var angle: Float = 0
    var angleVar: Float = 0
    var spin: Float = 0
    var spinVar: Float = 0
    /// 速度方向への伸び（光条）。
    var stretch: Float = 0
    var fade: ParticleEmitterComponent.ParticleEmitter.OpacityCurve = .quickFadeInOut
    /// 加算合成（光）。false = アルファ合成（煙・岩片）。
    var additive = true
    /// 乱流・渦・中心への引力。
    var noise: Float = 0
    var vortex: Float = 0
    var attract: Float = 0
    /// 継続放出の長さ（duration）を発動のイベントの長さ（SkillCastEvent.duration）から取る（rate > 0 のときだけ。
    /// イベントの長さが 0 なら書いた duration のまま。上限は FXCue.castDurationLimit）。cast・発動と同時の impact だけで効く。
    var durationFromCast = false
    /// コマ送りの画像（nil = tex の 1 枚絵）。1 回で消える画像は粒子の寿命で全コマを流す（sheetFPS 0 のとき）。
    var sheet: FXSheet?
    /// コマ数 / 秒（0 = 1 回の画像は 16 コマ ÷ 寿命、繰り返す画像は FXSheet.loopFPS）。
    var sheetFPS: Float = 0
    /// 繰り返す画像の始まりのコマを粒子ごとにばらす。
    var sheetRandomStart = false

    /// 回収までの秒数。
    var span: Float {
        if rate > 0 { return duration > 0 ? duration + life * (1 + lifeVar) : .infinity }
        return emit + life * (1 + lifeVar) + 0.1
    }

    func with(_ f: (inout FXEmit) -> Void) -> FXEmit {
        var c = self
        f(&c)
        return c
    }
}

// MARK: - メッシュ

/// メッシュの合成。
enum FXBlend: String, Hashable, Sendable {
    /// 画像のアルファ × 色（煙・影・地割れ・盾面・予告の塗り）。
    case alpha
    /// 色を足す（光・閃光・光の柱・衝撃波の縁）。明るさは FXMaterialLibrary.addLevels 段階で落とす（フェード）。
    case add
}

/// 形の中を流れる模様（FXShaders.metal の custom_parameter / metallic_scale / emissive_color）。
struct FXFlow: Hashable, Sendable {
    var pattern: FXFlowTex = .noise
    /// 流れる速さ（UV / 秒。x = 横（弧・円周に沿う）、y = 縦（画像の下 → 上は負））。
    var scroll: SIMD2<Float> = [0, -1]
    /// 模様の繰り返しの数。
    var tiling: Float = 2
    /// 模様の強さ（0〜1。主の色 → 明るい所の色への混ぜ方と明るさの揺らぎ）。
    var strength: Float = 0.7
    /// 縁の欠け（0 = 無し、1 = 強い。形の薄い所ほど模様の暗い所から欠ける）。
    var erosion: Float = 0
    /// 模様の明るい所の色。
    var edge: FXTint = .core
}

/// 溶けて消える（ディゾルブ）。寿命の比 from から 1 へ、模様（FXMesh.flow の模様、無ければ pattern）の暗い所から消え、
/// 消える縁が edge の色で光る。進み具合は再生器がメッシュの頂点の色（1 体ごと）へ毎フレーム書く（材質は 1 つ）。
struct FXDissolve: Hashable, Sendable {
    /// 溶け始め（寿命に対する比）。
    var from: Float = 0.45
    /// 模様（flow が無いときだけ使う）と繰り返しの数。
    var pattern: FXFlowTex = .noise
    var tiling: Float = 2
    /// 消える縁の光の色（flow があれば flow.edge が優先）。
    var edge: FXTint = .core
    /// 縁の光の幅（模様の値の幅。0 = 光らない）。
    var width: Float = 0.1
}

/// 演出用の単位メッシュ（UV 付き）。前半は手続きで作る形、後半（isModel）は Blender で作った模型
/// （tools/vfx_assets/blender/fx_meshes.py → App/Resources/FX/Meshes/fxm_<名前>.bin）。模型は試合のレシピが使うものだけプールする。
enum FXShape: String, CaseIterable, Hashable, Sendable {
    /// 地面の板（1×1、画像の上 = 前）。
    case disc
    /// 縦の板（幅 1 × 高さ 1、下端が原点、前を向く。両面）。
    case wall
    /// 常にカメラを向く板（1×1、中心が原点）。
    case billboard
    /// 上下の開いた円柱（半径 1・高さ 1、下端が原点。画像の下 = 根元）。
    case cylinder
    /// 上へ広がる漏斗（下の半径 0.35・上の半径 1、高さ 1）。
    case funnel
    /// 上へ細る尖塔（下の半径 1・上の半径 0.08、高さ 1）。
    case spire
    /// 半球（半径 1。画像の下 = 赤道）。
    case dome
    /// 球（半径 1）。
    case sphere
    /// 水平の半円の帯（内径 0.72・外径 1、前方の 180°。画像の下 = 外縁、横 = 弧に沿う）。
    case arc
    /// 水平の輪の帯（内径 0.8・外径 1、全周）。
    case band
    // 模型（Blender。どれも単位の大きさ、前 = -Z。UV の約束は fx_meshes.py の冒頭）
    /// 三日月の帯（前を中心に ±100°・外径 1）。u = 弧に沿う（0 = 右端 → 1 = 左端 = 振り終わり。頭が太い）、v = 内縁 0 → 外縁 1。
    case crescent
    /// 衝撃の輪（内径 0.55 → 外径 1、外縁が 0.1 持ち上がる）。u = 円周（4 周）、v = 内縁 0 → 外縁 1。
    case ringLip
    /// 竜巻（3 本の螺旋の帯。下の半径 0.25 → 上 1、高さ 1）。u = 帯に沿う（下 → 上）、v = 帯の幅。
    case twister
    /// 光の柱（入れ子の 2 枚の円柱。内: 半径 0.42・高さ 1、外: 半径 1・高さ 0.72、上へ細る）。v = 根元 0 → 先 1。
    case pillar2
    /// 渦の刃の輪（地面に寝かせた 16 枚の勾玉形の刃、半径 0.55〜1）。u = 刃に沿う（尾 0 → 頭 1）、v = 刃の幅。
    case bladeRing
    /// 爆ぜる炎の半球（半径 1。上と外へ炎の舌が尖る）。u = 経度、v = 赤道 0 → 頂 1。
    case burstDome
    /// 四芒星の盤（厚み 0.05 の 4 本の長い腕・長さ 1 と短い 4 本）。上面の UV = 平面の投影（中心 0.5、半径 1 = 0.5）。
    case starCross
    /// 割れて浮く岩板の輪（10 枚の角張った板、半径 0.35〜1、厚み 0.06）。上面の UV = 平面の投影。
    case shardRing

    /// Blender の模型（バンドルの fxm_<名前>.bin を読む）か。
    var isModel: Bool {
        switch self {
        case .crescent, .ringLip, .twister, .pillar2, .bladeRing, .burstDome, .starCross, .shardRing: return true
        default: return false
        }
    }

    /// 模型のバンドルの名前（拡張子 .bin）。
    var modelResource: String? { isModel ? "fxm_\(rawValue)" : nil }
}

/// イージング。
enum FXEase: Hashable, Sendable {
    case linear
    /// 速く始まり減速（爆発・展開）。
    case out
    /// ゆっくり始まり加速（収束・落下）。
    case `in`
    case inOut
    /// 行き過ぎて戻る（叩きつけ・出現）。
    case outBack

    func apply(_ t: Float) -> Float {
        let x = min(1, max(0, t))
        switch self {
        case .linear: return x
        case .out: return 1 - (1 - x) * (1 - x) * (1 - x)
        case .in: return x * x * x
        case .inOut: return x * x * (3 - 2 * x)
        case .outBack:
            let c1: Float = 1.9, c3 = c1 + 1
            return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
        }
    }
}

/// メッシュの層（拡縮・回転・不透明度を時間で動かす）。
struct FXMesh: Hashable, Sendable {
    var shape: FXShape
    /// 画像（nil = 単色）。
    var tex: FXTex?
    var tint: FXTint = .primary
    /// 最大の不透明度。
    var alpha: Float = 1
    /// 開始・終了の大きさ（右・上・前）。
    var size: SIMD3<Float> = [1, 1, 1]
    var sizeEnd: SIMD3<Float> = [1, 1, 1]
    var ease: FXEase = .out
    var life: Float = 0.5
    /// 現れる時間（寿命に対する比）と消え始め（比）。
    var fadeIn: Float = 0.08
    var fadeOut: Float = 0.45
    /// 前方からの向き（度、上から見て反時計回り）・終わりの向き（掃く動き）。
    var yaw: Float = 0
    var yawEnd: Float?
    /// 前後の傾き（度、+ = 前へ倒す）・左右の傾き（度）。
    var pitch: Float = 0
    var roll: Float = 0
    /// 縦軸まわりの回転速度（度/秒）。
    var spin: Float = 0
    /// 上昇速度（m/s）。
    var rise: Float = 0
    /// 前方への移動速度（m/s）。
    var advance: Float = 0
    /// 寿命（life）を発動のイベントの長さ（SkillCastEvent.duration）から取る（イベントの長さが 0 なら書いた life のまま。
    /// 上限は FXCue.castDurationLimit。fadeIn・fadeOut は寿命に対する比なので一緒に伸びる）。cast・発動と同時の impact だけで効く。
    var durationFromCast = false
    /// 途中で消せる組の番号（0 = なし）。sim の数が減ったときに、追従しているこの組のメッシュと予定の合図を短く消す
    /// （SkillFXPlayer.cut。H028 の環剣の刃 1 本ごとに 1〜5）。消すときに寿命を縮めるので、大きさが変わらないメッシュに使う。
    var group = 0
    /// 合成（既定はアルファ合成。加算は光る部品だけに使う: 重なるほど明るく、明るい地面では白く飛ぶ）。
    var blend: FXBlend = .alpha
    /// 形の中を流れる模様（nil = 模様なし）。
    var flow: FXFlow?
    /// コマ送りの画像（nil = tex の 1 枚絵）。寿命の間に全コマを 1 回流す（繰り返す画像は sheetFPS か FXSheet.loopFPS で回す）。
    /// コマは再生器が頂点の色へ書き、シェーダーが画像の格子から切り出す。加算・模様の材質（Program）が無いときは tex の 1 枚絵で出す。
    var sheet: FXSheet?
    /// コマ / 秒（0 = 1 回の画像は寿命で全コマ、繰り返す画像は FXSheet.loopFPS）。
    var sheetFPS: Float = 0
    /// 溶けて消える（nil = 無し。fadeOut の不透明度の落とし方とは別に効く）。
    var dissolve: FXDissolve?
    /// 上昇の重力（m/s²。rise の上向きの速さに下向きの加速度を掛ける = 放物線。破片・打ち上げ。0 = 等速）。
    var gravity: Float = 0
    /// 画面の歪み（衝撃波の屈折。後処理）の強さ（画面の高さに対するずれの最大。0 = 無し、0.004〜0.015 が目安）。
    /// 輪の縁（disc は size の半分、輪・帯の模型は size）で背景を膨らませる。後処理の無い環境（シミュレータ・低画質）では出ない。
    var refract: Float = 0

    func with(_ f: (inout FXMesh) -> Void) -> FXMesh {
        var c = self
        f(&c)
        return c
    }
}

// MARK: - 帯（リボン・軌跡）

/// 動く点の後ろに伸びる帯（突進の尾・武器の振りの軌跡）。頭が path に沿って duration 秒動き、通った所が life 秒で尾から消える。
/// 帯の画像の UV: u = 尾 0 → 頭 1（古さの逆。三日月の模型・swoosh・blade の画像と同じ向き）、v = 幅（0 = 内側・下 → 1 = 外側・上）。帯は試合の読み込みで作った LowLevelMesh の
/// プール（SkillFXPlayer.ribbonCapacity）で、毎フレーム頂点だけを書き換える。
struct FXRibbon: Hashable, Sendable {
    enum Path: Hashable, Sendable {
        /// 合図の基準（.follow なら追従の主体、ほかは置いた位置）+ offset に付いて動く（突進の尾。幅は upright で上下、そうでなければ水平）。
        case follow
        /// 原点のまわりの弧を頭が掃く（振りの軌跡）。radius = 頭の半径（m）、from → to = 向き（度、前 = 0・+ = 左）、
        /// height = 弧の中心の高さ（m）、roll = 弧の面の傾き（度。0 = 水平、90 = 前と上の縦の面で from → to は下 → 上）。
        /// 幅は半径の向き（外縁 = radius、内縁 = radius − width）。
        case arc(radius: Float, from: Float, to: Float, height: Float, roll: Float)
    }

    var path: Path = .follow
    /// 頭が動く時間（秒）。
    var duration: Float = 0.3
    /// 通った所が消えるまでの秒数（帯の長さ）。
    var life: Float = 0.25
    /// 帯の幅（m）と、尾での幅の倍率。
    var width: Float = 0.6
    var tailWidth: Float = 0.4
    /// follow の帯を縦に立てる（幅が上下）。false = 地面と平行（幅が進む向きの横）。
    var upright = true
    /// 頭の動き（arc の掃き方）。
    var ease: FXEase = .out
    var tex: FXTex? = .blade
    var tint: FXTint = .primary
    var alpha: Float = 1
    var blend: FXBlend = .add
    var flow: FXFlow?

    /// 回収までの秒数。
    var span: Float { duration + life + 0.05 }

    func with(_ f: (inout FXRibbon) -> Void) -> FXRibbon {
        var c = self
        f(&c)
        return c
    }

    /// 材質を引くための見た目（形は使わない）。
    var look: FXMesh {
        FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, life: max(0.05, span)).with {
            $0.blend = blend
            $0.flow = flow
        }
    }
}

// MARK: - 合図

enum FXElement: Hashable, Sendable {
    case emit(FXEmit)
    case mesh(FXMesh)
    /// 画面の揺れ（視点のヒーローが近い時だけ）。
    case shake(Float)
    /// 動く点の後ろに伸びる帯（FXRibbon）。
    case ribbon(FXRibbon)
    /// Effekseer の効果を重ねる（見せ場。sim と連動する部品は emit / mesh のまま）。
    case efk(FXEfk)
}

/// 段の合図として重ねる Effekseer の効果（Effects/Effekseer/Kit/<name>.efk。試合のヒーローの分だけ読み込み幕の裏で読む）。
/// 位置・時刻・追従は他の合図と同じ（at・anchor・offset）。向きは段の前方（効果は前 = -Z で作る）。
/// 描くのは EffekseerDirector（実機の中・高画質は後処理の中、シミュレータ・低画質は重ね描き）。
struct FXEfk: Hashable, Sendable {
    /// 効果の名前（拡張子なし。<ヒーロー ID>_<名前>。例 H034_s2_slam）。
    var name: String
    /// 一様な倍率と再生速度。
    var scale: Float = 1
    var speed: Float = 1
    /// 3D の上に描く（体に重ねる命中の閃きなど）。false = 3D に隠れる（地面の跡・柱・輪。後処理の中だけ効く）。
    var onTop = false
    /// anchor が follow の時に追う長さ（秒）。過ぎたら止める。
    var followFor: Float = 3
}

struct FXCue: Hashable, Sendable {
    /// 段の開始からの遅れ（秒）。
    var at: Float = 0
    var anchor: FXAnchor = .origin
    /// 原点からの位置（右・上・前、m）。
    var offset: SIMD3<Float> = .zero
    var element: FXElement
    /// 繰り返し（回数・間隔・回ごとの向きの加算（度）・回ごとの位置の加算）。
    var count: Int = 1
    var every: Float = 0
    var stepYaw: Float = 0
    var stepOffset: SIMD3<Float> = .zero
    /// 位置を前方からこの角度（度）回してから置く（輪状に並べる時、stepYaw と組み合わせる）。
    var orbit: Float = 0
    /// この画質以上でだけ出す（0 = 低、1 = 中、2 = 高）。
    var minQuality: Int = 0

    static func emit(_ e: FXEmit, at: Float = 0, _ anchor: FXAnchor = .origin, offset: SIMD3<Float> = .zero,
                     quality: Int = 0) -> FXCue {
        FXCue(at: at, anchor: anchor, offset: offset, element: .emit(e), minQuality: quality)
    }

    static func mesh(_ m: FXMesh, at: Float = 0, _ anchor: FXAnchor = .origin, offset: SIMD3<Float> = .zero,
                     quality: Int = 0) -> FXCue {
        FXCue(at: at, anchor: anchor, offset: offset, element: .mesh(m), minQuality: quality)
    }

    static func shake(_ k: Float, at: Float = 0) -> FXCue {
        FXCue(at: at, element: .shake(k))
    }

    /// Effekseer の効果を重ねる（FXEfk）。
    static func efk(_ name: String, at: Float = 0, _ anchor: FXAnchor = .origin, offset: SIMD3<Float> = .zero,
                    scale: Float = 1, speed: Float = 1, onTop: Bool = false, quality: Int = 0) -> FXCue {
        FXCue(at: at, anchor: anchor, offset: offset,
              element: .efk(FXEfk(name: name, scale: scale, speed: speed, onTop: onTop)), minQuality: quality)
    }

    static func ribbon(_ r: FXRibbon, at: Float = 0, _ anchor: FXAnchor = .origin, offset: SIMD3<Float> = .zero,
                       quality: Int = 0) -> FXCue {
        FXCue(at: at, anchor: anchor, offset: offset, element: .ribbon(r), minQuality: quality)
    }

    /// n 回繰り返す（every 秒ごと、向きを yaw 度ずつ回し、位置を step ずつずらす）。
    func repeated(_ n: Int, every: Float = 0, yaw: Float = 0, step: SIMD3<Float> = .zero) -> FXCue {
        var c = self
        c.count = n
        c.every = every
        c.stepYaw = yaw
        c.stepOffset = step
        return c
    }

    /// n 個を原点の周りの輪に並べる（半径 r、向きも外向きに回す）。
    func ringed(_ n: Int, radius r: Float, every: Float = 0) -> FXCue {
        var c = self
        c.count = n
        c.every = every
        c.stepYaw = 360 / Float(max(1, n))
        c.offset.z += r
        c.orbit = 0.0001
        return c
    }
}

// MARK: - 発動の長さ（SkillCastEvent.duration）

extension FXCue {
    /// 発動のイベントから取る長さの上限（秒）。予算の検査（メッシュの寿命 4 秒など）は書いた値にかかるので、上書きはここで抑える。
    static let castDurationLimit: Float = 10
    /// 上書きの下限（秒。極端に短い値で一瞬で消えないように）。
    static let castDurationFloor: Float = 0.2

    /// 発動のイベントの長さ（秒）→ 上書きに使う長さ。0 以下・有限でない値は nil（= 書いた値のまま）。
    static func castDuration(_ seconds: Double) -> Float? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        return min(castDurationLimit, max(castDurationFloor, Float(seconds)))
    }

    /// 長さを発動のイベントから取る合図か（durationFromCast の継続放出・メッシュ）。
    var usesCastDuration: Bool {
        switch element {
        case .emit(let e): return e.durationFromCast && e.rate > 0
        case .mesh(let m): return m.durationFromCast
        case .shake, .ribbon, .efk: return false
        }
    }

    /// durationFromCast の要素の長さを d 秒にする（継続放出の duration・メッシュの life）。それ以外はそのまま。
    func withCastDuration(_ d: Float) -> FXCue {
        guard usesCastDuration else { return self }
        var c = self
        switch element {
        case .emit(var e):
            e.duration = d
            c.element = .emit(e)
        case .mesh(var m):
            m.life = d
            c.element = .mesh(m)
        case .shake, .ribbon, .efk:
            break
        }
        return c
    }

    /// 合図の並びに発動の長さを当てる（seconds = SkillCastEvent.duration。0 なら書いた値のまま）。
    static func applyingCastDuration(_ cues: [FXCue], seconds: Double) -> [FXCue] {
        guard let d = castDuration(seconds), cues.contains(where: { $0.usesCastDuration }) else { return cues }
        return cues.map { $0.withCastDuration(d) }
    }
}

// MARK: - 1 スキルの演出

struct SkillFXRecipe: Sendable {
    var cast: [FXCue] = []
    var telegraph: [FXCue] = []
    var travel: [FXCue] = []
    var impact: [FXCue] = []
    var hit: [FXCue] = []
    /// hit を被弾 1 回ごとに再生するか。既定（false）では、キットのヒーローの多段ヒットのスキル（連続ダメージ・複数の波）は
    /// 同じ相手へ hit を 0.9 秒に 1 回だけ再生する（SkillFXDirector.hitInterval）。1 発ごとに出したい短い演出だけ true。
    var hitPerHit = false
    /// 空の段を FXGeneric（アーキタイプ別の既定演出）で補うか。false = 空の段は何も出さない（MLBB で光らない振りかぶりなど）。
    /// 再使用の段の演出が共通の演出（stage 0）で補われるのはこれと別（SkillFXCatalog.merged）。
    var fillsEmptyPhases = true

    var all: [FXCue] { cast + telegraph + travel + impact + hit }
    var isEmpty: Bool { cast.isEmpty && telegraph.isEmpty && travel.isEmpty && impact.isEmpty && hit.isEmpty }
}

/// レシピを書く時に使えるスキルの寸法（マスターデータから。m）。
struct FXSkillInfo: Sendable {
    var heroID: String
    var slot: SkillSlot
    var archetype: SkillArchetype
    /// 効果半径（m）。
    var radius: Float
    /// 射程（m）。
    var range: Float
}
