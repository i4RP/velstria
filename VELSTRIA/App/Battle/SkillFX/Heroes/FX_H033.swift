import Foundation
import VelstriaCore

// スキル演出: H033 紅牙のヴァルド（Assassin / 巨大な大剣・蝙蝠の翼風のマント・深紅と黒の鎧。MLBB の Alucard の Velstria 版）。
// 主題: 血の月と紅の大剣。白い芯 × 深紅（主）× 鮮血の朱（副）× 青白（差し色）× 黒に近い暗赤（暗）。
// 大剣の重い叩き割りと、血色の三日月、舞い散る蝙蝠の羽で見せる（断空のザイル H028 の細く鋭い光刃とは逆に、重く禍々しい紅）。
// sim の実際の挙動（Systems/Kits/Kit_H033.swift）に合わせた演出:
//   パッシブ 吸血の渇き（追撃）  — 頭上に血の月が灯り、蝙蝠の羽が身の周りを舞う（スキルのあとの追撃の準備 + 常時の吸血）。
//                                 追撃そのもの（次の通常攻撃の踏み込み）は専用のイベントが無いので、通常の攻撃の演出に任せる
//   S1 地割り（転がり + 叩きつけ） — 紅の尾を引いて着地点へ転がり（約 0.2 秒）、着地した瞬間に大剣を叩きつける。
//                                 sim は転がり終えた tick に着地点の円（半径 190）へ当てるので、叩きつけの演出は cast の
//                                 「着地点（target）」に 0.2 秒遅らせて出す（この archetype は着弾の合図を Director へ出さない）。鈍足 = 紅の足枷
//   S2 旋回斬（自分中心の円）     — その場で大剣を振り回す。円の斬線が二重に走り、衝撃の輪が広がる（照準なし。cast と impact が同じ場で出る）
//   奥義 核分裂波（吸収 → 衝撃波） — 1 回目: 着地点（target）の円で敵のエネルギーを吸い上げ（血の光が中心へ集まる・暗い紅の紋）、
//                                 術者の頭上に血の月。6 秒のクールダウン半減の間、月が残る。
//                                 2 回目（stage 1）: 向きへ貫通する紅の衝撃波（travel の三日月 + 尾）。当たった敵に斬線（impact / hit）
//                                 現在の SkillFXDirector は stage を見ないので、2 回目も cast の「target 側の紋」が波の終点に出る
//                                 （波の終点に血の月の紋を刻む演出として違和感が出ないよう、紋は暗い紅の薄いものにした）

enum FX_H033: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.94, 0.94), primary: RGB(0.82, 0.04, 0.14),
                                   secondary: RGB(1.0, 0.32, 0.4), accent: RGB(0.78, 0.86, 1.0),
                                   dark: RGB(0.1, 0.0, 0.04))

    /// 舞い散る蝙蝠の羽（暗い紅の羽根が散る）。
    private static func bats(_ n: Int, radius: Float, speed: Float = 3, life: Float = 0.9) -> FXEmit {
        FXEmit.flutter(.feather, n, radius: radius, .primary, speed: speed, life: life, size: 0.2).with {
            $0.tintEnd = .secondary; $0.gravity = 0.4
        }
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = s.radius
        switch slot {
        case .passive:
            r.cast = [
                .mesh(.sprite(.moon, 0.7, .primary, life: 0.6, grow: 1.3, alpha: 0.95), .follow, offset: [0, 2.3, 0]),
                .emit(.flare(0.9, .secondary, life: 0.18, tex: .flare4), .follow, offset: [0, 2.3, 0]),
                .mesh(.halo(0.9, .primary, life: 0.8, spin: 160, tex: .ringDouble), .follow, offset: [0, 0.3, 0]),
                .mesh(.decal(.moon, 2.0, .secondary, life: 0.8, spin: 70, alpha: 0.7), .follow),
                .emit(bats(6, radius: 0.7, speed: 1.0, life: 1.0), .follow, offset: [0, 1.2, 0]),
                .emit(.rising(10, radius: 0.5, .primary, speed: 1.8, life: 0.8), .follow),
            ]
            r.hit = []
        case .skill1:
            // 転がり出し（0 〜 0.2 秒）→ 着地点（target）への叩きつけ（0.2 秒）。着地点の円の半径 = R
            r.cast = [
                .emit(.trail(.streak, .primary, rate: 80, life: 0.3, size: 0.5).with {
                    $0.duration = 0.22; $0.stretch = 3; $0.dir = .backward; $0.speed = 3
                }, .follow, offset: [0, 0.6, 0]),
                .emit(bats(6, radius: 0.5, speed: 2.5, life: 0.7), offset: [0, 0.8, 0]),
                .emit(.smoke(5, radius: 0.5, life: 0.6, size: 0.6), offset: [0, 0.2, 0], quality: 1),
                // 叩きつけ（着地点）
                .emit(.flare(1.8, .core, life: 0.18, tex: .flare6), at: 0.2, .target, offset: [0, 0.7, 0]),
                .mesh(.slash(R * 0.95, .secondary, from: 75, to: -75, height: 0.7, life: 0.28), at: 0.19, .target,
                      offset: [0, 0.7, 0]),
                .mesh(.decal(.crack, R * 2.2, .primary, life: 1.0, spin: 0, grow: 1.0, alpha: 0.8), at: 0.2, .target),
                .mesh(.decal(.moon, R * 1.6, .secondary, life: 0.7, spin: 30, alpha: 0.7), at: 0.2, .target),
                .emit(.wave(R * 1.0, .primary, life: 0.5), at: 0.2, .target, offset: [0, 0.1, 0]),
                .emit(.fan(18, .primary, speed: R * 4, spread: 360, life: 0.4), at: 0.2, .target, offset: [0, 0.6, 0]),
                // 鈍足の紅い輪
                .mesh(.shockRing(R * 1.1, .accent, life: 0.4), at: 0.2, .target),
                .emit(.debris(8, speed: 5), at: 0.2, .target, offset: [0, 0.1, 0]),
                .shake(0.22, at: 0.2),
            ]
            r.hit = [
                .emit(.sparks(8, speed: 5, .secondary, end: .primary), offset: [0, 1.0, 0]),
                .mesh(.halo(0.6, .primary, life: 0.8, spin: 120, tex: .ring), .follow, offset: [0, 0.15, 0]),
            ]
        case .skill2:
            // 旋回斬: cast と impact が術者の足元で同時に出る（自分中心の円）。0.05 に右回り、0.14 に左回りの斬線
            r.cast = [
                .emit(.bloom(1.3, .primary, life: 0.3), offset: [0, 1.0, 0]),
                .emit(bats(10, radius: 0.6, speed: 2.5, life: 0.8), offset: [0, 1.0, 0]),
                .emit(.smoke(6, radius: 0.5, life: 0.7, size: 0.6), quality: 1),
            ]
            r.impact = [
                .emit(.flare(1.8, .core, life: 0.18, tex: .flare6), at: 0.04, offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.9, .core, from: 175, to: -175, height: 1.0, tilt: 14, life: 0.22, tex: .slashThin), at: 0.04,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.95, .primary, from: 175, to: -175, height: 1.0, tilt: 14, life: 0.32), at: 0.04,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(R * 0.9, .secondary, from: -175, to: 175, height: 1.1, tilt: -14, life: 0.28, tex: .slashThin),
                      at: 0.14, offset: [0, 1.1, 0]),
                .mesh(.decal(.moon, R * 1.8, .primary, life: 0.9, spin: -80, alpha: 0.75), at: 0.04),
                .mesh(.shockRing(R * 1.0, .secondary, life: 0.4), at: 0.06),
                .mesh(.shockRing(R * 1.3, .primary, life: 0.5), at: 0.14),
                .emit(.sparks(16, speed: 8, .secondary, end: .primary), at: 0.05, offset: [0, 0.9, 0]),
                .emit(bats(8, radius: R * 0.4, speed: 4, life: 0.7), at: 0.06, offset: [0, 1.0, 0], quality: 1),
                .shake(0.25, at: 0.05),
            ]
            r.hit = [
                .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
                .emit(.sparks(8, speed: 6, .secondary, end: .primary), offset: [0, 1.0, 0]),
            ]
        case .ultimate:
            // 吸収: 着地点（target）の紋へ血の光が集まり、術者の頭上に血の月が昇る。
            // 衝撃波（stage 1）: travel の三日月と尾、当たった敵への斬線（impact / hit）
            r.cast = [
                .emit(bats(14, radius: 0.7, speed: 3.5, life: 0.9), offset: [0, 1.0, 0]),
                .emit(.flare(1.8, .secondary, life: 0.2, tex: .flare6), offset: [0, 1.0, 0]),
                .mesh(.sprite(.moon, 1.8, .primary, life: 0.9, grow: 1.3, alpha: 0.8), .follow, offset: [0, 2.6, -0.4]),
                .mesh(.decal(.moon, 2.6, .primary, life: 0.5, spin: 240, alpha: 0.7)),
                // 吸収の円（target）
                .mesh(.decal(.moon, R * 2.0, .primary, life: 1.4, spin: -60, alpha: 0.6), .target),
                .mesh(.decal(.crack, R * 1.7, .secondary, life: 1.0, spin: 0, grow: 1.0, alpha: 0.5), at: 0.05, .target),
                .mesh(.shockRing(R * 1.6, .primary, life: 0.5), .target),
                .mesh(.halo(R * 0.5, .secondary, life: 1.0, spin: 120, tex: .ring), at: 0.05, .target, offset: [0, 0.2, 0]),
                // 血の光が円の中心へ集まる（吸収）
                .emit(.gather(28, radius: R * 0.9, .secondary, life: 0.6), at: 0.05, .target, offset: [0, 1.0, 0]),
                .emit(.rising(10, radius: R * 0.7, .primary, speed: 1.6, life: 0.8), at: 0.1, .target),
                .shake(0.25, at: 0.05),
            ]
            r.travel = [
                .mesh(.ray(.slashLine, length: 4.0, width: 2.0, .secondary, life: 1.1, alpha: 0.9).with { $0.fadeOut = 0.85 },
                      .follow, offset: [0, 0.9, -1.0]),
                .mesh(.sprite(.moon, 2.2, .primary, life: 1.1, grow: 1.0, alpha: 0.9).with { $0.fadeOut = 0.85 }, .follow,
                      offset: [0, 1.0, 0.2]),
                .emit(.trail(.glow, .primary, rate: 90, life: 0.35, size: 1.0), .follow, offset: [0, 1.0, 0]),
                .emit(.trail(.streak, .secondary, rate: 70, life: 0.3, size: 0.4).with {
                    $0.shape = .sphere(0.6); $0.stretch = 3; $0.dir = .backward; $0.speed = 4
                }, .follow, offset: [0, 1.0, 0], quality: 1),
            ]
            r.impact = [
                .emit(.flare(2.0, .core, life: 0.22, tex: .flare6), offset: [0, 1.0, 0]),
                .mesh(.slash(2.2, .core, from: 85, to: -85, height: 1.0, tilt: 30, life: 0.22, tex: .slashThin), at: 0.02,
                      offset: [0, 1.0, 0]),
                .mesh(.slash(2.3, .primary, from: 85, to: -85, height: 1.05, tilt: 30, life: 0.32), at: 0.02,
                      offset: [0, 1.05, 0]),
                .mesh(.slash(2.2, .secondary, from: -85, to: 85, height: 1.1, tilt: -30, life: 0.28, tex: .slashThin), at: 0.1,
                      offset: [0, 1.1, 0]),
                .mesh(.slash(2.6, .core, from: 80, to: -80, height: 1.2, tilt: 90, life: 0.3, tex: .slashThin), at: 0.16,
                      offset: [0, 1.2, 0]),
                .mesh(.decal(.crack, 2.8, .secondary, life: 1.0, spin: 0, grow: 1.0, alpha: 0.75), at: 0.16),
                .mesh(.shockRing(2.2, .secondary, life: 0.45), at: 0.16),
                .mesh(.shockRing(3.0, .primary, life: 0.65), at: 0.2),
                .emit(.sparks(18, speed: 8, .secondary, end: .primary), at: 0.04, offset: [0, 1.0, 0]).repeated(3, every: 0.1),
                // 流れた血の光（吸血）が術者へ戻る
                .emit(.gather(24, radius: 1.3, .secondary, life: 0.6), at: 0.2, offset: [0, 1.0, 0]),
                .shake(0.4, at: 0.16),
            ]
            r.hit = [
                .emit(.flare(1.1, .core, life: 0.14), offset: [0, 1.0, 0]),
                .emit(.sparks(10, speed: 6, .secondary, end: .primary), offset: [0, 1.0, 0]),
                // 鈍足・防御ダウンの紅い輪
                .mesh(.halo(0.6, .primary, life: 0.9, spin: 120, tex: .ring), .follow, offset: [0, 0.15, 0]),
            ]
        }
        return r
    }

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 低く転がり込み、大剣を頭上から叩きつける
            m.dash(0.08, lean: 0.6)
            m.leap(0.1, height: 0.35, forward: 0.5)
            m.overhead(0.08)
            m.smash(0.06)
            m.land(0.08, depth: 0.2)
            m.hold(0.08)
        case .skill2:
            // その場で大剣を振り回す（一回転）
            m.windup(0.06, side: 1, power: 1.2)
            m.spin(0.3, turns: 1)
            m.hold(0.06)
            m.settle(0.1)
        case .ultimate:
            // 大剣を地へ突き立てて構え、血の月を掲げる（吸収） → 同じ構えから向きへ振り抜く（衝撃波）
            m.brace(0.06, depth: 0.14)
            m.stomp(0.16)
            m.raise(0.2, glow: 1.6)
            m.hold(0.1)
            m.settle(0.1)
        }
    }
}
