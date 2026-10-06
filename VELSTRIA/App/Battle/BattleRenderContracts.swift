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
}

/// 描画担当が使うヒーローモデルの生成口。hero-models が `HeroModelLibrary.makeModel` を実装する。
@MainActor
enum HeroModelFactory {
    static func make(heroID: String, skinID: String?, team: Team, master: MasterData) -> HeroModelHandle {
        HeroModelLibrary.makeModel(heroID: heroID, skinID: skinID, team: team, master: master)
    }
}
