import Foundation
import VelstriaCore

// スキル演出: H017 深淵鎖のモルド（Support / 深淵の香炉灯、身にまとう深淵の鎖）。
// 主題: 深淵の鎖。紫（主）× 黒い深淵（暗）× 藍（副）× 淡い藤色の香煙（差し色・癒し）。重く・不気味に・しかし味方には温かく。
//   パッシブ 深鎖           — 味方を癒すと、その身を巻いた鎖がほどけて藤色の光となって昇る
//   S1 Mord式・一閃         — 鉤付きの深淵の鎖を投げる（直線）。命中点に深淵の穴が開き、鎖が噴き出して縛る（根止め）
//   S2 星環シフト           — 足元の深淵の穴へ沈み、転移先の穴から鎖を払って現れる
//   S3 境界制圧             — 香炉を振って香煙の聖域を張る。鎖の輪が地を巡り、味方を癒して敵の足を重くする（鈍足）
//   奥義 深淵拘束            — 深淵の門を開く。八本の鎖が四方へ奔り、二重の鎖の輪が回って敵を縛り（気絶）、味方を守り癒す

enum FX_H017: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.96, 0.88, 1.0), primary: RGB(0.7, 0.28, 1.0),
                                   secondary: RGB(0.42, 0.36, 1.0), accent: RGB(0.9, 0.72, 1.0),
                                   dark: RGB(0.08, 0.02, 0.12))

    /// 香炉（振りかざした右手の先。局所座標）。
    private static let censer: SIMD3<Float> = [0.35, 1.35, 0.55]
    /// 香煙（淡い藤色のアルファ合成の煙）。
    private static let incense = FXTint.rgb(0.78, 0.62, 0.95)

    /// 前方へ伸びる鎖の帯（鎖の画像は横長なので 90° 回して前へ向ける）。length = 長さ、width = 太さ。
    private static func chainLine(_ length: Float, width: Float, _ tint: FXTint = .primary, life: Float = 0.5,
                                  alpha: Float = 0.95) -> FXMesh {
        FXMesh(shape: .disc, tex: .chain, tint: tint, alpha: alpha, size: [length * 0.4, 1, width],
               sizeEnd: [length, 1, width], ease: .out, life: life, fadeIn: 0.04, fadeOut: 0.55, yaw: 90)
    }

    /// 締まる鎖の輪（根止め・気絶の拘束）。
    private static func chainRing(_ radius: Float, _ tint: FXTint = .primary, life: Float = 0.9,
                                  spin: Float = 220) -> FXMesh {
        FXMesh.halo(radius, tint, life: life, spin: spin, tex: .chain).with {
            $0.size = [radius * 1.6, 1, radius * 1.6]
            $0.sizeEnd = [radius, 1, radius]
            $0.ease = .out
        }
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            // 原点は癒された味方
            r.cast = [
                .mesh(FXMesh.halo(0.7, .primary, life: 0.8, spin: 260, tex: .chain).with {
                    $0.size = [0.55, 1, 0.55]; $0.sizeEnd = [1.0, 1, 1.0]; $0.rise = 0.8
                }, .follow, offset: [0, 0.5, 0]),
                .mesh(.decal(.swirl, 1.6, .dark, life: 0.7, spin: -200, alpha: 0.55), .follow),
                .emit(.flare(0.9, .accent, life: 0.2), .follow, offset: [0, 1.1, 0]),
                .emit(.rising(16, radius: 0.55, .accent, speed: 2.4, life: 0.9), .follow),
                .emit(.motes(8, radius: 0.5, .primary, life: 1.0), .follow, offset: [0, 1.2, 0], quality: 1),
            ]
            r.hit = []
        case .skill1:
            // 香炉を振りかぶって鎖を投げる（0.14 秒）
            r.cast = [
                .emit(.flare(1.1, .primary, life: 0.16), at: 0.13, offset: censer),
                .emit(.smoke(5, radius: 0.25, incense, life: 0.9, size: 0.5), at: 0.13, offset: censer, quality: 1),
                .mesh(chainLine(2.2, width: 0.45, .primary, life: 0.25), at: 0.13, offset: [0.2, 1.1, 1.3]),
            ]
            r.travel = [
                .emit(.trail(.glowHard, .primary, rate: 90, life: 0.12, size: 0.5), .follow, offset: [0, 1.0, 0]),
                // 引きずる鎖
                .emit(.trail(.chain, .primary, rate: 40, life: 0.3, size: 0.6).with {
                    $0.orient = .ground; $0.angle = 90; $0.grow = 1; $0.speed = 0; $0.tintEnd = .secondary
                }, .follow, offset: [0, 0.9, 0]),
                .emit(.trail(.smoke, .dark, rate: 24, life: 0.5, size: 0.4).with {
                    $0.additive = false; $0.grow = 1.8; $0.fade = .gradualFadeInOut
                }, .follow, offset: [0, 0.9, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(1.4, .primary, life: 0.18), offset: [0, 0.9, 0]),
                .mesh(.decal(.swirl, R * 2.2, .dark, life: 1.2, spin: -160, grow: 1.05, alpha: 0.8)),
                .mesh(.decal(.ringDouble, R * 2.0, .primary, life: 0.9, spin: 90, alpha: 0.75)),
                // 穴から噴き出す鎖
                .mesh(chainLine(R * 1.2, width: 0.4, .primary, life: 0.7)).ringed(5, radius: R * 0.55, every: 0.02),
                .mesh(chainRing(R * 0.6, .secondary, life: 0.9), at: 0.08, offset: [0, 0.4, 0]),
                .emit(.smoke(8, radius: R * 0.5, .dark, life: 1.0, size: 0.7), quality: 1),
                .emit(.sparks(14, speed: 5, .accent, end: .primary, gravity: 2), offset: [0, 0.5, 0]),
                .shake(0.12),
            ]
            r.hit = [
                .mesh(chainRing(0.55, .primary, life: 1.1, spin: 260), .follow, offset: [0, 0.3, 0]),
                .mesh(chainRing(0.45, .secondary, life: 1.0, spin: -300), .follow, offset: [0, 0.95, 0]),
                .emit(.flare(0.8, .primary, life: 0.15), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            // 深淵の穴へ沈む（転移元）→ 転移先の穴から現れる
            r.cast = [
                .mesh(.decal(.swirl, 2.2, .dark, life: 0.8, spin: -360, grow: 0.6, alpha: 0.85)),
                .mesh(.decal(.ringDouble, 1.9, .primary, life: 0.6, spin: 200, grow: 0.7, alpha: 0.7)),
                .emit(.gather(16, radius: 1.0, .primary, life: 0.35), offset: [0, 0.3, 0]),
                .emit(.smoke(8, radius: 0.4, .dark, life: 0.8, size: 0.7)),
            ]
            r.impact = [
                .emit(.flare(1.4, .primary, life: 0.2), offset: [0, 1.0, 0]),
                .mesh(.decal(.swirl, R * 2.4, .dark, life: 0.9, spin: 300, grow: 1.1, alpha: 0.85)),
                .mesh(.shockRing(R * 1.4, .primary, life: 0.4)),
                .mesh(.pillar(0.4, height: 3.2, .primary, life: 0.45, alpha: 0.75)),
                // 鎖を払う
                .mesh(chainLine(1.6, width: 0.4, .secondary, life: 0.45).with { $0.advance = 1.5 })
                    .ringed(3, radius: 0.6, every: 0.03),
                .emit(.vortex(18, radius: 0.6, .primary, life: 0.6, speed: 3)),
                .emit(.smoke(8, radius: 0.5, .dark, life: 1.0, size: 0.8), quality: 1),
                .shake(0.1),
            ]
        case .skill3:
            // 香炉を振って香煙の聖域（0.12 秒）
            r.cast = [
                .emit(.flare(1.1, .accent, life: 0.18), at: 0.11, offset: censer),
                .emit(.smoke(6, radius: 0.3, incense, life: 1.0, size: 0.6), at: 0.11, offset: censer),
            ]
            r.telegraph = [
                .mesh(chainRing(R, .primary, life: 0.65, spin: 90), offset: [0, 0.05, 0]),
                .mesh(.decal(.swirl, R * 2.2, .primary, life: 0.65, spin: 120, grow: 1.0, alpha: 0.55)),
                .emit(.smoke(8, radius: R * 0.8, incense, life: 0.9, size: 0.7).with { $0.speed = 0.2 }),
            ]
            r.impact = [
                .emit(.groundGlow(R * 1.1, .primary, life: 0.7)),
                .mesh(.decal(.runeCircle, R * 2.3, .accent, life: 1.3, spin: -30, alpha: 0.8)),
                .mesh(chainRing(R * 0.95, .primary, life: 1.3, spin: 70), offset: [0, 0.1, 0]),
                .mesh(.halo(R * 0.7, .accent, life: 1.0, spin: -140, tex: .ring, alpha: 0.7), at: 0.05, offset: [0, 0.8, 0]),
                .mesh(.pillar(R * 0.5, height: 2.6, .accent, life: 0.8, alpha: 0.45)),
                .emit(.vortex(18, radius: R * 0.85, .accent, life: 1.1, tex: .twinkle, speed: 2)),
                .emit(.smoke(12, radius: R * 0.8, incense, life: 1.5, size: 0.9).with { $0.speed = 0.4; $0.vortex = 2 },
                      quality: 1),
                .emit(.rising(20, radius: R * 0.8, .core, speed: 2.2, life: 1.0), at: 0.1),
            ]
            r.hit = [
                .mesh(chainRing(0.5, .secondary, life: 0.9), .follow, offset: [0, 0.2, 0]),
            ]
        case .ultimate:
            // 深淵の門: 片手を天へ（0.1 秒）、足元に門が開き鎖が四方へ奔る
            r.cast = [
                .emit(.gather(20, radius: 1.4, .primary, life: 0.12), offset: [0, 1.2, 0]),
                .emit(.flare(1.6, .accent, life: 0.22, tex: .flare6), at: 0.09, offset: [0.2, 2.3, 0]),
            ]
            r.impact = [
                .emit(.flare(2.4, .primary, life: 0.25, tex: .flare6), at: 0.1, offset: [0, 1.1, 0]),
                .mesh(.decal(.swirl, R * 2.7, .dark, life: 1.8, spin: -90, grow: 1.05, alpha: 0.9), at: 0.08),
                .mesh(.decal(.runeCircle, R * 2.5, .primary, life: 1.6, spin: 45, grow: 1.05, alpha: 0.9), at: 0.1),
                // 四方へ奔る八本の鎖
                .mesh(chainLine(R * 1.3, width: 0.5, .primary, life: 0.8).with { $0.advance = 2.2 }, at: 0.1)
                    .ringed(8, radius: R * 0.55, every: 0.015),
                // 二重の鎖の輪（拘束）
                .mesh(chainRing(R, .primary, life: 1.4, spin: 140), at: 0.12, offset: [0, 0.5, 0]),
                .mesh(chainRing(R * 0.6, .secondary, life: 1.3, spin: -200), at: 0.16, offset: [0, 1.4, 0]),
                .mesh(.pillar(0.7, height: 6, .primary, life: 0.7, alpha: 0.7), at: 0.1),
                .mesh(.pillar(0.3, height: 7, .core, life: 0.5), at: 0.1),
                .mesh(.shockRing(R * 1.6, .primary, life: 0.5), at: 0.1),
                .mesh(.shockRing(R * 2.4, .secondary, life: 0.7), at: 0.16),
                .emit(.vortex(30, radius: R * 0.9, .primary, life: 1.0, speed: 3.5), at: 0.1),
                .emit(.smoke(14, radius: R * 0.8, .dark, life: 1.6, size: 1.1), at: 0.1, quality: 1),
                .emit(.rising(30, radius: R * 1.1, .accent, speed: 3, life: 1.2), at: 0.2),
                .emit(.sparks(24, speed: 8, .accent, end: .primary, gravity: 2), at: 0.1, offset: [0, 0.8, 0]),
                .shake(0.6, at: 0.1),
            ]
            r.hit = [
                // 気絶: 頭上に回る鎖の冠
                .mesh(chainRing(0.4, .primary, life: 1.0, spin: 420), .follow, offset: [0, 2.05, 0]),
                .emit(.flutter(.twinkle, 6, radius: 0.35, .accent, speed: 0.5, life: 0.9, size: 0.14).with {
                    $0.gravity = 0; $0.vortex = 6
                }, .follow, offset: [0, 2.05, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 香炉を大きく振りかぶり、鎖を投げ放つ
            m.throwCast(0.14)
            m.hold(0.14) { $0.glow = 1.3 }
        case .skill2:
            // 深淵の穴から沈んだ姿勢で現れ（半透明）、伸び上がって両腕で鎖を払う
            m.key(0.04, .snap) { p in
                p.hipsDrop = 0.32
                p.torsoPitch = 0.45
                p.opacity = 0.35
            }
            m.key(0.08, .out) { p in
                p.hipsDrop = 0
                p.torsoPitch = 0
                p.opacity = 1
            }
            m.roar(0.08)
            m.hold(0.1)
        case .skill3:
            // 香炉を手元で一回しして前へ掲げ、香煙を流す
            m.twirl(0.06, turns: 1)
            m.push(0.06, high: 0.25)
            m.hold(0.2) { $0.glow = 1.6; $0.ring = 0.8 }
        case .ultimate:
            // 片手を天へ、片手を地へ。門を開き、膝をついて深淵を抑える
            m.command(0.1)
            m.hold(0.24) { p in
                p.glow = 2.0
                p.ring = 1.4
                p.wings = 1.4
            }
            m.kneel(0.1)
            m.hold(0.14) { $0.glow = 1.8 }
        }
    }
}
