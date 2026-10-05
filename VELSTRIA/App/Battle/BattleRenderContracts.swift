import Foundation
import RealityKit
import SwiftUI
import VelstriaCore

// 担当: 統合（契約）。Wave 2 の描画担当間の境界。
//   battle-renderer : App/Battle/Render/*   （マップ・構造物・ミニオン・モンスター・投射物・ゾーン・VFX・霧・カメラ・HP バー）
//   hero-models     : App/Battle/Heroes/*   （24 ヒーローの手続き生成モデル・スキン・アニメーション・3D プレビュー）
//   battle-hud      : App/Battle/HUD/*, App/Battle/BattleContainerView.swift（操作・HUD・ショップ・スコアボード・チュートリアル・音）

/// sim 座標（ユニット）→ RealityKit ワールド座標（メートル）。地面は y = 0。
@inline(__always)
func worldPosition(_ p: Vec2, height: Float = 0) -> SIMD3<Float> {
    SIMD3<Float>(Float(p.x / Balance.unitsPerMeter), height, Float(-p.y / Balance.unitsPerMeter))
}

/// sim の向き（ラジアン、x 軸基準）→ Y 軸回転。モデルの正面は -Z を向いている前提。
@inline(__always)
func worldOrientation(facing: Double) -> simd_quatf {
    // sim (cos, sin) → world (x, -z)。-Z 正面のモデルを facing 方向へ回す。
    simd_quatf(angle: Float(facing - Double.pi / 2), axis: [0, 1, 0])
}

enum HeroAnimState: Equatable {
    case idle
    case run
    case attack
    case cast(SkillSlot)
    case channel
    case stunned
    case dead
    case victory
}

/// 武器の軌跡の 1 サンプル（ワールド座標・m、最後の update 時点の姿勢）。値型だけで、取得にヒープ確保は無い。
/// 描画側は毎フレーム読み、swing の間だけ根元 → 先端の帯を伸ばす（swing でない間も位置は有効 = 帯の始点に使える）。
struct HeroWeaponTrailSample: Equatable {
    struct Blade: Equatable {
        /// 握り（武器の原点）。籠手・爪は手のひら。
        var base: SIMD3<Float>
        /// 先端（刃先・穂先・槌頭・拳）。
        var tip: SIMD3<Float>
        /// この手が振っている: 再生中の通常攻撃・詠唱のうち近接のクリップ（武器・拳の振り。射撃・魔法・投擲・回避は除く）の
        /// 打撃の前 0.18 秒〜後 0.06 秒（クリップ時刻 = 再生速度に比例して縮む）で、クリップの打つ手（strikeHand）がこの手。
        /// クリップが無ければ手続きの通常攻撃（近接の型）の打撃区間。docs/HERO_MOTION.md「武器の軌跡・発射位置」。
        var swing: Bool
    }

    /// 右手の武器。
    var right: Blade
    /// 左手の刃（二刀の近接だけ: 硝子の短剣・花弁の双刃・夢の針・霧の刀 + 小太刀・三日月の短刀 + 月の灯籠）。それ以外は nil。
    var left: Blade?
}

/// ヒーローモデルの操作ハンドル。同梱 Hero_<id>.usdz（Tripo 生成・自動リグのスキンメッシュ）があればそれを、
/// 無ければ手続き生成モデルを返す（どちらも同じ手続きアニメーションで動く）。
@MainActor
protocol HeroModelHandle: AnyObject {
    /// シーンに追加するルート（足元が原点、正面 -Z）。身長はブループリントの拡縮（約 0.96〜1.12）を掛ける前で、
    /// スキンメッシュ ≒ 1.70 m（正規化の規約）、手続き ≒ 1.67 m。
    var root: Entity { get }
    /// 頭上 UI（HP バー等）を置く高さ（m）。
    var overheadHeight: Float { get }
    func setState(_ state: HeroAnimState)
    /// スキルの詠唱モーションの長さ（秒。詠唱状態をこの間保つ）。
    func castDuration(_ slot: SkillSlot) -> Float
    /// 手続きアニメーションを進める（毎フレーム）。
    func update(dt: Double, moveSpeed: Double)
    /// 通常攻撃を 1 回振る（シムの攻撃開始時に呼ぶ。windup = 発射・命中までの秒、interval = 次の攻撃までの秒）。
    /// モーションクリップのあるスキンメッシュは打撃の瞬間を windup 秒後に合わせる。攻撃状態でなければ攻撃状態へ移る。
    func playAttack(windup: Double, interval: Double)
    /// 遠隔の通常攻撃の発射位置（ワールド座標・m、最後の update 時点の姿勢 = クリップが動かす手・武器）。
    /// 武器の先端（杖・槍・銃口・掌の炎）。素手で副手に弓を持つヒーロー（H003）は弓の握り、体に付ける籠手・爪は手のひら。
    /// 左右に同じ武器（爪・拳・二刀）を持ち、再生中のクリップが左手で打つ時（hook_l 等）は左手の側。nil = 対応していない。
    func attackLaunchPoint() -> SIMD3<Float>?
    /// 武器の軌跡のサンプル（ワールド座標）。武器を持たないヒーロー・対応していないモデルは nil。
    func weaponTrailSample() -> HeroWeaponTrailSample?
}

extension HeroModelHandle {
    /// 既定は何もしない（手続きモデルは setState(.attack) の手続きの振りのまま）。
    func playAttack(windup: Double, interval: Double) {}
    /// 既定は無し（描画側は従来どおり頭上の高さなどから出す）。
    func attackLaunchPoint() -> SIMD3<Float>? { nil }
    func weaponTrailSample() -> HeroWeaponTrailSample? { nil }
}

/// 描画担当が使うヒーローモデルの生成口。hero-models が `HeroModelLibrary.makeModel` を実装する。
@MainActor
enum HeroModelFactory {
    static func make(heroID: String, skinID: String?, team: Team, master: MasterData) -> HeroModelHandle {
        HeroModelLibrary.makeModel(heroID: heroID, skinID: skinID, team: team, master: master)
    }
}
