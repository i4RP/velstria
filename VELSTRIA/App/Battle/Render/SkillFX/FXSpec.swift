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

/// 演出用の単位メッシュ（UV 付き）。
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

    func with(_ f: (inout FXMesh) -> Void) -> FXMesh {
        var c = self
        f(&c)
        return c
    }
}

// MARK: - 合図

enum FXElement: Hashable, Sendable {
    case emit(FXEmit)
    case mesh(FXMesh)
    /// 画面の揺れ（視点のヒーローが近い時だけ）。
    case shake(Float)
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

// MARK: - 1 スキルの演出

struct SkillFXRecipe: Sendable {
    var cast: [FXCue] = []
    var telegraph: [FXCue] = []
    var travel: [FXCue] = []
    var impact: [FXCue] = []
    var hit: [FXCue] = []

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
