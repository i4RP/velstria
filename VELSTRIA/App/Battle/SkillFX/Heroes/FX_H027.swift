import Foundation
import VelstriaCore

// スキル演出: H027 竜槍のジャルド（Duelist / 竜の意匠の長槍・銀青の鎧・赤い房飾り。MLBB の Zilong の Velstria 版）。
// 主題: 銀青の竜槍。白銀の芯 × 銀青（主）× 白（副）× 赤の房（差し色）。鋭い突きの線と、地から突き上がる竜牙・天へ昇る竜の渦。
// sim の実際の挙動（Systems/Kits/Kit_H027.swift）に合わせた演出:
//   パッシブ 竜の三連突き     — 竜気をまとう銀の鱗（竜気が増えるたび = パッシブのバッジが増えるたびに再生される）。
//                              三連突き自体は通常攻撃の 3 連続ヒット（0.13 秒おき。ヒット演出は通常攻撃のダメージごとに出る）
//   S1 槍の跳ね上げ（対象指定）— 低く構えた槍で掬い上げ、敵を頭上へ跳ね上げて術者の背後へ放り投げる
//                                （打ち上げ 0.8 秒。背後 1.7 m に 0.7 秒後に着地 → 着地の衝撃）
//   S2 竜牙の踏み込み（対象指定の突進）— 銀の尾を引いて踏み込み（約 0.2 秒）、到着の瞬間に槍を突き込む。
//                                竜牙が突き上がり、鎧の鱗が砕けて防御が落ちる（防御ダウン 2 秒）
//   奥義 至高の武人（自己強化 7.5 秒）— 足元に竜の紋、銀青の渦が立ち昇り咆哮。強化の間は風を切る銀の線と光が追従する
// SkillCastEvent の shape / duration / count: S1 = lockOn・0.8（打ち上げ）、S2 = lockOn・突進の秒数、奥義 = selfRing・7.5・2（三連突きの必要回数）。
// 再使用の段（stage）は Zilong に無いので使わない。

enum FX_H027: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.97, 0.99, 1.0), primary: RGB(0.5, 0.72, 1.0),
                                   secondary: RGB(0.84, 0.92, 1.0), accent: RGB(1.0, 0.32, 0.28),
                                   dark: RGB(0.04, 0.07, 0.16))

    /// 突き上がる竜牙（地から伸びる半透明の尖塔）。
    private static func fang(_ h: Float, life: Float = 0.8) -> FXMesh {
        FXMesh(shape: .spire, tex: .shard, tint: .secondary, alpha: 0.85, size: [0.5, 0.1, 0.5], sizeEnd: [0.42, h, 0.42],
               ease: .outBack, life: life, fadeIn: 0.02, fadeOut: 0.6)
    }

    /// 槍の突きの線（前方へ走る細い光条。x は左右のずらし、y は高さ、z0 は線の始まりの前後位置）。
    private static func lance(_ length: Float, _ tint: FXTint, at t: Float, x: Float = 0, y: Float = 1.0,
                              z0: Float = 0.3) -> FXCue {
        FXCue.mesh(FXMesh.ray(.streak, length: length, width: 0.55, tint, life: 0.22), at: t,
                   offset: [x, y, length / 2 + z0])
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        // 奥義の radius（3.5 m）はボットが「近くに敵が居る」と数える目安なので、演出の大きさは 2 m に抑える
        let R = slot == .ultimate ? min(s.radius, 2.0) : s.radius
        let L = s.range
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.dome(1.1, .primary, life: 0.8, tex: .hexShield, alpha: 0.45), .follow, offset: [0, 0.1, 0]),
                .emit(.flutter(.shard, 10, radius: 0.6, .secondary, speed: 1.6, life: 0.8, size: 0.14), .follow,
                      offset: [0, 1.1, 0]),
                .mesh(.halo(0.8, .secondary, life: 0.6, spin: 200, tex: .ringDouble), .follow, offset: [0, 0.9, 0]),
                .emit(.flare(0.9, .accent, life: 0.16), .follow, offset: [0, 1.2, 0]),
            ]
            r.hit = []
        case .skill1:
            // 槍の跳ね上げ: 低い構え（0.05）→ 掬い上げ → 敵が頭上を越えて背後へ（着地は 0.7 秒後、術者の背後 1.7 m）
            r.cast = [
                .emit(.gather(10, radius: 0.6, .primary, life: 0.12), offset: [0.2, 0.7, 0.6]),
                .emit(.flare(1.0, .core, life: 0.12), at: 0.05, offset: [0, 0.6, 0.9]),
            ]
            r.impact = [
                // 低い突き上げの線と、掬い上げる三日月
                lance(L * 0.9, .core, at: 0.04, y: 0.6),
                .mesh(.slash(R * 1.1, .primary, from: 95, to: -95, height: 0.8, tilt: -35, life: 0.26), at: 0.05,
                      offset: [0, 0.8, 0.3]),
                // 跳ね上げられた敵の軌跡（前 → 頭上 → 背後）
                .emit(.flare(1.3, .core, life: 0.18), at: 0.06, offset: [0, 0.7, L * 0.8]),
                .emit(.flare(1.1, .secondary, life: 0.2), at: 0.2, offset: [0, 2.2, L * 0.3]),
                .emit(.flare(1.3, .core, life: 0.2), at: 0.34, offset: [0, 2.1, -0.4]),
                .emit(.flare(1.0, .secondary, life: 0.2), at: 0.5, offset: [0, 1.0, -1.3]),
                .mesh(.pillar(0.35, height: 3.0, .secondary, life: 0.45), at: 0.05, offset: [0, 0, L * 0.8]),
                .emit(.sparks(12, speed: 6, .accent, end: .primary), at: 0.06, offset: [0, 1.0, L * 0.8]),
                // 背後への着地
                .mesh(.shockRing(R * 0.9, .primary, life: 0.4), at: 0.7, offset: [0, 0, -1.7]),
                .emit(.wave(R * 1.1, .secondary, life: 0.4), at: 0.7, offset: [0, 0.1, -1.7]),
                .emit(.debris(8, speed: 5), at: 0.7, offset: [0, 0, -1.7]),
                .shake(0.2, at: 0.7),
            ]
            r.hit = [
                // 打ち上げ（0.8 秒）: 頭上に銀の輪
                .emit(.flare(0.9, .core, life: 0.14), offset: [0, 1.1, 0]),
                .mesh(.halo(0.45, .secondary, life: 0.8, spin: 320), offset: [0, 1.5, 0]),
                .emit(.sparks(8, speed: 5, .secondary, end: .primary), offset: [0, 1.0, 0]),
            ]
        case .skill2:
            // 竜牙の踏み込み: 銀の尾を引いて駆け（約 0.2 秒）、到着の瞬間（0.19 秒）に突き込む。impact は対象の足元で再生される
            r.cast = [
                .emit(.bloom(1.2, .primary, life: 0.3), offset: [0, 1.0, 0]),
                .emit(.trail(.streak, .secondary, rate: 80, life: 0.3, size: 0.5).with {
                    $0.duration = 0.25; $0.stretch = 3; $0.dir = .backward; $0.speed = 3
                }, .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.glow, .primary, rate: 60, life: 0.35, size: 0.5).with { $0.duration = 0.25 }, .follow,
                      offset: [0, 1.0, 0]),
            ]
            r.impact = [
                // 手前から対象へ突き込む光条と閃光
                lance(2.2, .core, at: 0.17, y: 1.0, z0: -1.2),
                .emit(.flare(1.8, .core, life: 0.18, tex: .flare6), at: 0.19, offset: [0, 1.0, -0.1]),
                // 地から突き上がる竜牙
                .mesh(fang(2.2), at: 0.2).ringed(5, radius: R * 0.45, every: 0.03),
                .mesh(.decal(.crack, R * 2.0, .primary, life: 1.0, spin: 0, grow: 1.0, alpha: 0.7), at: 0.2),
                .mesh(.shockRing(R * 1.2, .secondary, life: 0.4), at: 0.2),
                .emit(.wave(R * 1.3, .primary, life: 0.5), at: 0.2, offset: [0, 0.1, 0]),
                // 防御ダウン: 砕けた鱗が散る
                .emit(.flutter(.shard, 10, radius: 0.5, .accent, speed: 3.5, life: 0.7, size: 0.14), at: 0.2,
                      offset: [0, 1.0, 0]),
                .emit(.sparks(14, speed: 7, .accent, end: .primary), at: 0.2, offset: [0, 0.8, 0]),
                .shake(0.2, at: 0.2),
            ]
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
                // 防御ダウン 2 秒: 足元に割れた紋
                .mesh(.decal(.crack, 1.5, .accent, life: 1.6, spin: 0, grow: 1.0, alpha: 0.7)),
                .emit(.rising(8, radius: 0.4, .secondary, speed: 3, life: 0.5), quality: 1),
            ]
        case .ultimate:
            // 至高の武人: 足元に竜の紋 → 銀青の渦が立ち昇り咆哮。7.5 秒の強化の間は風を切る線と光が術者に追従する
            r.cast = [
                .emit(.gather(20, radius: 1.2, .primary, life: 0.3), offset: [0, 1.0, 0]),
                .mesh(.decal(.runeCircle, R * 1.6, .secondary, life: 0.7, spin: 200, alpha: 0.7)),
                .mesh(.halo(0.9, .accent, life: 0.9, spin: 260, tex: .ringDouble), .follow, offset: [0, 0.9, 0]),
                // 強化の間（7.5 秒）追従: 後方へ流れる銀の線（移動速度）と、立ちのぼる光（攻撃速度）
                .emit(.trail(.streak, .secondary, rate: 22, life: 0.45, size: 0.4).with {
                    $0.duration = 7.5; $0.stretch = 3; $0.dir = .backward; $0.speed = 4
                }, .follow, offset: [0, 0.9, -0.2], quality: 1),
                .emit(.trail(.twinkle, .accent, rate: 10, life: 0.8, size: 0.14).with {
                    $0.duration = 7.5; $0.dir = .up; $0.speed = 1.2
                }, .follow, offset: [0, 0.3, 0], quality: 1),
            ]
            r.impact = [
                .mesh(.tornado(R * 0.6, height: 4.0, .primary, life: 0.9, spin: 540), at: 0.05),
                .mesh(.tornado(R * 0.45, height: 3.4, .secondary, life: 0.8, spin: -720), at: 0.08),
                .emit(.vortex(24, radius: R * 0.6, .secondary, life: 0.9, speed: 4), at: 0.05, quality: 1),
                // 竜の咆哮
                .emit(.flare(2.6, .core, life: 0.26, tex: .flare6), at: 0.12, offset: [0, 1.3, 0]),
                .mesh(.pillar(R * 0.4, height: 5.5, .secondary, life: 0.7), at: 0.12),
                .mesh(.shockRing(R * 1.4, .core, life: 0.4), at: 0.12),
                .mesh(.shockRing(R * 1.9, .accent, life: 0.6), at: 0.18),
                .mesh(.decal(.runeCircle, R * 2.4, .primary, life: 1.3, spin: 70, alpha: 0.8), at: 0.05),
                .emit(.sparks(16, speed: 7, .accent, end: .primary), at: 0.12, offset: [0, 1.0, 0]),
                .shake(0.4, at: 0.12),
            ]
            r.hit = []
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 低く構え、槍を切り上げて敵を放り投げる
            m.brace(0.05, depth: 0.15)
            m.uppercut(0.12)
            m.hold(0.12)
            m.settle(0.1)
        case .skill2:
            // 前傾で駆け、踏み込みざまに槍を突き込む
            m.dash(0.06, lean: 0.55)
            m.lunge(0.06, distance: 0.5, lean: 0.3)
            m.thrust(0.05)
            m.hold(0.1)
            m.settle(0.1)
        case .ultimate:
            // 低く構え、槍を回して高く掲げ、咆哮する（自己強化なので踏み込みも跳躍もしない）
            m.brace(0.06, depth: 0.2)
            m.spin(0.2, turns: 1)
            m.uppercut(0.1)
            m.hold(0.18) { $0.glow = 2.0; $0.ring = 1.2 }
            m.settle(0.12)
        }
    }
}
