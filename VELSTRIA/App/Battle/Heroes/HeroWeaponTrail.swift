import Foundation
import RealityKit

// 担当: hero-models。武器の軌跡（HeroWeaponTrailSample）と遠隔の通常攻撃の発射位置（HeroModelHandle.attackLaunchPoint）。
// 点は武器・副手エンティティのローカル（= 手続きメッシュの武器座標: 握りが原点・+Y へ伸びる）で持ち、毎回その時の
// エンティティの変換でワールドへ移す。Prop_<kind>.usdz は propFit で同じ座標へ合わせてあり、weaponScale / offhandScale は
// エンティティ自身の拡縮に入っているので、手続き・スキンメッシュ・Prop のどれでも同じ点がそのまま使える。
// 取得は値型と Entity.convert だけで、毎フレーム呼んでもヒープ確保をしない。

/// 1 ヒーロー分の軌跡・発射の点（生成時に設計図とメッシュ一式から 1 度だけ作る）。
struct HeroWeaponPoints {
    /// 右手武器の先端（weapon ローカル）。nil = 素手（副手の弓だけで戦う H003）で軌跡を出さない。
    let rightTip: V3?
    /// 左手の刃の先端（offhand ローカル）。二刀の近接だけ（dualBlades）。
    let leftTip: V3?
    /// 通常攻撃の発射位置（launchFromOffhand なら offhand、でなければ weapon のローカル）。
    let launchPoint: V3
    let launchFromOffhand: Bool
    /// 左手で打つクリップ（hook_l 等）の発射位置（offhand ローカル）。左右に同じ種類の武器（爪・拳・二刀）の時だけ。
    let leftLaunchPoint: V3?

    /// 左手の軌跡を出す副手。二刀の短剣・小太刀に加え、三日月の短刀と組む月の灯籠（左手で打つ二刀の振りを灯りの筋で見せる）。
    static let dualBlades: Set<OffhandKind> = [.glassDagger, .petalBlade, .dreamNeedle, .shortBlade, .moonLantern]
    /// 体に付ける籠手・爪（発射・軌跡の根元は手のひら = 武器エンティティの原点）。
    static let bodyWorn: Set<WeaponKind> = [.stoneFist, .azureClaw]

    init(blueprint bp: HeroBlueprint, weaponTip: V3, offhandTip: V3?) {
        rightTip = bp.weapon == .none ? nil : weaponTip
        leftTip = Self.dualBlades.contains(bp.offhand) ? offhandTip : nil
        if bp.weapon == .none, let offhandTip {
            // 副手の弓だけ（H003）: 弓の握り = 矢を番える位置から放つ
            launchPoint = offhandTip
            launchFromOffhand = true
            leftLaunchPoint = nil
        } else if Self.bodyWorn.contains(bp.weapon) {
            // 籠手・爪は本体メッシュの一部で先端の長さが分からないので、手のひらから放つ
            launchPoint = .zero
            launchFromOffhand = false
            leftLaunchPoint = bp.offhand == .stoneFist || bp.offhand == .azureClaw ? .zero : nil
        } else {
            // 杖・槍・銃口・掌の炎（handFlame の weaponTip は炎の中心）
            launchPoint = weaponTip
            launchFromOffhand = false
            leftLaunchPoint = leftTip
        }
    }

    init(blueprint bp: HeroBlueprint, meshes ms: HeroMeshSet) {
        self.init(blueprint: bp, weaponTip: ms.weaponTip, offhandTip: ms.offhandTip)
    }

    /// 発射位置（ワールド座標）。strikeHand は再生中の振りで打つ手（左なら左手の側を使える時だけ左）。
    @MainActor
    func launchPosition(weapon: Entity, offhand: Entity, strikeHand: HeroStrikeHand) -> SIMD3<Float> {
        if launchFromOffhand { return offhand.convert(position: launchPoint, to: nil) }
        if strikeHand == .left, let p = leftLaunchPoint { return offhand.convert(position: p, to: nil) }
        return weapon.convert(position: launchPoint, to: nil)
    }

    /// 軌跡のサンプル（ワールド座標）。右手に武器が無ければ nil。
    @MainActor
    func trailSample(weapon: Entity, offhand: Entity, swing: (right: Bool, left: Bool)) -> HeroWeaponTrailSample? {
        guard let rightTip else { return nil }
        var s = HeroWeaponTrailSample(right: .init(base: weapon.convert(position: .zero, to: nil),
                                                   tip: weapon.convert(position: rightTip, to: nil), swing: swing.right),
                                      left: nil)
        if let leftTip {
            s.left = .init(base: offhand.convert(position: .zero, to: nil), tip: offhand.convert(position: leftTip, to: nil),
                           swing: swing.left)
        }
        return s
    }
}
