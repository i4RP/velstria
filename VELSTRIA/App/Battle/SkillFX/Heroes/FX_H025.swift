import Foundation
import VelstriaCore

// スキル演出: H025 月弦のルミナ（Ranger / 三日月の長弓・月光の矢・翠と白の外套）。
// 主題: 月光の弦と翠の矢。白い芯 × 翠緑（主）× 白銀（副）× 淡い月光の黄（差し色）。矢は扇状に分かれ、月の輪が地に刻まれる。
// フィリエル（H003・青緑の月光）とは逆に、森エルフらしい翠と、分裂・散開する「矢の筋」で見せる。
// ミヤ型のキット（docs/kits/Miya.md）に合わせた構成:
//   パッシブ 月環の導き      — 頭上に月が灯り、足元に月の輪が巡って翠の光が昇る（命中ごとに攻撃速度の段が積もる）
//   S1 月矢の連弾           — 自己強化。弓に月光が集まり、前へ三条の矢の筋が走る。効果中は弓の先に月の粒が流れ続ける
//                             （矢そのものは通常攻撃の弾なので、着弾の演出は無い）
//   S2 月蝕の矢             — 指定地点へ月蝕の矢。着弾前に月の輪が地に灯り、着弾で六条の小さな矢が等間隔に散る（鈍足）
//   奥義 隠れ月光           — 月影に紛れて姿を消す。月の輪が足元に咲き、翠の霞となって薄れ、疾風の筋が続く（2 秒）
// 寸法は固定値で持つ（S1・奥義の照準リングは「撃てる距離」の目安で、演出の大きさには使えない）。

enum FX_H025: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.96, 1.0, 0.97), primary: RGB(0.3, 0.92, 0.6),
                                   secondary: RGB(0.84, 0.98, 0.92), accent: RGB(1.0, 0.95, 0.55),
                                   dark: RGB(0.02, 0.1, 0.06))

    /// 弓を構えた左手の先（局所座標）。
    private static let bow: SIMD3<Float> = [-0.1, 1.35, 0.6]

    /// 扇状に走る月光の矢の筋（pivot から angle 度（+ = 左）の向きへ length m）。
    private static func volley(_ angle: Float, length: Float, _ tint: FXTint, at t: Float = 0,
                               from pivot: SIMD3<Float> = [0, 1.1, 0.3], life: Float = 0.4) -> FXCue {
        let a = angle * .pi / 180
        let d = length / 2
        return FXCue.mesh(FXMesh.ray(.arrow, length: length, width: 0.7, tint, life: life).with { $0.yaw = 90 + angle },
                          at: t, offset: pivot + SIMD3<Float>(-sin(a) * d, 0, cos(a) * d))
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.sprite(.moon, 0.6, .accent, life: 0.6, grow: 1.3, alpha: 0.95), .follow, offset: [0, 2.3, 0]),
                .emit(.flare(0.9, .core, life: 0.18, tex: .flare4), .follow, offset: [0, 2.3, 0]),
                .mesh(.halo(0.9, .primary, life: 0.8, spin: 160, tex: .ringDouble), .follow, offset: [0, 0.3, 0]),
                .mesh(.decal(.moon, 2.0, .secondary, life: 0.8, spin: 70, alpha: 0.7), .follow),
                .emit(.rising(12, radius: 0.5, .primary, speed: 1.8, life: 0.8), .follow),
            ]
            r.hit = []
        case .skill1:
            // 自己強化: 弓に月光が集まり、前へ三条の矢の筋が走る。月の輪が腰に巡り、効果中（4 秒）は弓の先に月の粒が流れる
            var cast: [FXCue] = [
                .emit(.gather(14, radius: 0.6, .primary, life: 0.2), offset: bow),
                .emit(.flare(1.1, .core, life: 0.16, tex: .flare4), at: 0.12, offset: bow),
                .mesh(.sprite(.moon, 0.6, .accent, life: 0.35, grow: 1.5, alpha: 0.9), at: 0.12, offset: bow),
                .mesh(.halo(0.9, .primary, life: 0.9, spin: -180, tex: .ringDouble), .follow, offset: [0, 0.9, 0]),
                .mesh(.decal(.moon, 1.6, .secondary, life: 0.7, spin: 90, alpha: 0.7)),
                .emit(.trail(.glow, .primary, rate: 30, life: 0.3, size: 0.3).with { $0.duration = 4 }, .follow, offset: bow),
            ]
            for (k, angle) in [-20, 0, 20].enumerated() {
                cast.append(volley(Float(angle), length: 2.2, k == 1 ? .core : .primary, at: 0.14, from: [0, 1.15, 0.5],
                                   life: 0.35))
            }
            r.cast = cast
        case .skill2:
            // 月蝕の矢: 弓を高く引いて空へ放ち、着弾点に月の輪が灯る（telegraph）→ 着弾で六条の小さな矢が散る（impact）→ 矢が走る（travel）
            let E: Float = max(1.0, s.radius)
            r.cast = [
                .emit(.gather(10, radius: 0.5, .primary, life: 0.16), offset: bow),
                .emit(.flare(1.2, .core, life: 0.16, tex: .flare4), at: 0.14, offset: bow),
                .mesh(.ray(.arrow, length: 2.4, width: 0.8, .core, life: 0.3, alpha: 0.95), at: 0.14, offset: [0, 1.5, 1.4]),
                .mesh(.sprite(.moon, 0.55, .accent, life: 0.3, grow: 1.6, alpha: 0.9), at: 0.14, offset: bow),
            ]
            r.telegraph = [
                .mesh(.decal(.moon, E * 2.0, .accent, life: 0.55, spin: 120, alpha: 0.6)),
                .mesh(.decal(.ringDouble, E * 2.2, .secondary, life: 0.55, spin: -80, alpha: 0.5)),
                .mesh(.sprite(.moon, 0.9, .accent, life: 0.5, grow: 0.6, alpha: 0.9), offset: [0, 2.6, 0]),
            ]
            var impact: [FXCue] = [
                .emit(.flare(1.5, .core, life: 0.18, tex: .flare6), offset: [0, 0.9, 0]),
                .mesh(.decal(.moon, E * 2.2, .primary, life: 0.9, spin: 90, alpha: 0.85)),
                .mesh(.decal(.ringDouble, E * 1.8, .secondary, life: 0.8, spin: -80, grow: 1.1, alpha: 0.8)),
                .mesh(.shockRing(E * 1.2, .accent, life: 0.4)),
                .mesh(.shockRing(E * 1.8, .primary, life: 0.55), at: 0.05),
                .emit(.rising(16, radius: 0.9, .primary, speed: 2.2, life: 0.8), at: 0.06, quality: 1),
            ]
            // 着弾点から六条（60° おき）に散る小さな矢
            for (k, angle) in [-150, -90, -30, 30, 90, 150].enumerated() {
                impact.append(volley(Float(angle), length: 2.2, k % 2 == 0 ? .core : .primary, at: 0.04 + Float(k) * 0.01,
                                     from: [0, 0.5, 0], life: 0.4))
            }
            r.impact = impact
            r.travel = [
                .mesh(.ray(.arrow, length: 1.1, width: 0.45, .core, life: 0.6, alpha: 0.95).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 0.8, -0.3]),
                .emit(.trail(.glow, .primary, rate: 40, life: 0.2, size: 0.25), .follow, offset: [0, 0.8, 0]),
            ]
            r.hit = [
                .emit(.sparks(8, speed: 5, .secondary, end: .primary), offset: [0, 1.0, 0]),
                // 鈍足の月の輪（追従）
                .mesh(.halo(0.5, .accent, life: 0.9, spin: 140, tex: .ring), .follow, offset: [0, 0.15, 0]),
            ]
        case .ultimate:
            // 隠れ月光: 月影に紛れる。足元に月の輪が咲き、翠の霞となって薄れ、2 秒のあいだ疾風の筋が尾を引く
            r.cast = [
                .emit(.bloom(1.6, .secondary, life: 0.35), offset: [0, 1.0, 0]),
                .emit(.smoke(10, radius: 0.5, life: 0.8, size: 0.8), quality: 1),
                // 背後の高い位置に月を掲げる（上方カメラで体を覆わないよう、小さめ・半透明）
                .mesh(.sprite(.moon, 1.4, .accent, life: 0.6, grow: 1.3, alpha: 0.75), offset: [0, 2.6, -0.8]),
                .mesh(.decal(.runeCircle, 3.0, .primary, life: 0.9, spin: 140, alpha: 0.7)),
                .mesh(.halo(1.0, .secondary, life: 0.7, spin: 200, tex: .ringDouble), offset: [0, 1.0, 0]),
                .mesh(.shockRing(2.0, .core, life: 0.4)),
                .emit(.flutter(.moon, 12, radius: 0.8, .accent, speed: 1.8, life: 1.0, size: 0.16), at: 0.05, offset: [0, 1.0, 0]),
                .emit(.rising(18, radius: 0.7, .primary, speed: 2.0, life: 0.9), at: 0.05, quality: 1),
                .emit(.trail(.glow, .secondary, rate: 24, life: 0.4, size: 0.4).with { $0.duration = 2 }, .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.streak, .primary, rate: 40, life: 0.3, size: 0.3).with {
                    $0.dir = .backward; $0.speed = 3; $0.duration = 2
                }, .follow, offset: [0, 0.9, 0], quality: 1),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 弓を軽く引いて月光を宿す（矢は放たない）
            m.draw(0.09, up: 0.05)
            m.release(0.05)
            m.hold(0.12)
        case .skill2:
            // 弓を高く構えて月蝕の矢を空へ放つ（ブリンクはしない）
            m.draw(0.12, up: 0.3)
            m.release(0.05)
            m.settle(0.1)
        case .ultimate:
            // 腰を落として外套を翻し、月影に紛れる
            m.brace(0.08, depth: 0.2)
            m.hold(0.14) { $0.glow = 1.8; $0.ring = 1.0 }
            m.settle(0.12)
        }
    }
}
