import Foundation
import VelstriaCore

// スキル演出: H028 断空のザイル（Assassin / 淡い青の光刃の長剣・光る visor・濃紺の軽装甲。MLBB の Saber の Velstria 版）。
// 主題: 空間を断つ光刃。白い芯 × シアン（主）× 淡い青（副）× 青紫（差し色。環剣の渦）× 濃紺（暗）。
// 上から見下ろすカメラで「光の剣が周りを回る → 当てた相手へ飛ぶ」「光の尾で駆け抜けて斬る」「打ち上げた相手を光の線が三度断つ」
// が読めるよう、円い輪を主役にせず、回る刃・通り道の斬線・交差する斬線で形を見せる。
// sim の実際の挙動（Systems/Kits/Kit_H028.swift の Tune）に合わせたタイミング:
//   パッシブ 空断の理      — ダメージを与えるたびに相手の防御を削る（最大 5 層・5 秒）。層が増えるたび（バッジの数が増えるたび）に
//                            visor が瞬き、胸の前に細い斬線が光る（頻繁に出るので小さく短く。層そのものは相手の頭上の .mark）
//   スキル1 環剣（自己中心）— 0 秒: 剣を掲げて 5 本の光剣が放射状に飛び出す。0〜5 秒: 光剣が周りを回る（内側 3 本・外側 2 本、
//                            メッシュの寿命は 4 秒までなので 2.5 秒ずつ 2 組。回る速さは 2.5 秒でちょうど周期が揃う値にして継ぎ目を消す）。
//                            hit（接触 0.5 秒ごと / 剣撃 = 通常攻撃・スキルの命中から 0.12 秒）: 術者の側から光剣が飛び込んで刺さる（1 発ごと）
//   スキル2 断空突進        — 3.5m を約 0.19 秒（18m/s）で駆ける。通り道に光の筋、終点（照準点）で前方の一閃。
//                            突進は impact を再生しない（ゾーンを作らない）ので、終点の演出は cast の .target に 0.19 秒遅れで置く。
//                            着いたあと約 3 秒、刃のきらめきと光の粒（次の通常攻撃が強化される間）
//   奥義 三連断空（対象指定）— 突進（≦0.19 秒）→ 到着で打ち上げ 1.2 秒 → 到着から 0.2 / 0.6 / 1.0 秒に 3 連撃（弱・弱・強）。
//                            impact（対象の位置）は照準の陣が締まり → 光の柱と昇る輪（打ち上げ）→ 0.35 / 0.75 秒に交差する斬線 2 本と
//                            三日月 → 1.15 秒に 4 本の放射の斬線・縦横の大きな十字・地面の X の傷。hit（1 撃ごと・正確な時刻）は短い閃光
// SkillFXDirector は duration / count を読まない: 突進の長さで 3 連撃が最大 0.1 秒ほど前後する（hit は sim の時刻どおり）。

enum FX_H028: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.93, 1.0, 1.0), primary: RGB(0.2, 0.84, 1.0),
                                   secondary: RGB(0.58, 0.78, 1.0), accent: RGB(0.52, 0.42, 1.0),
                                   dark: RGB(0.02, 0.04, 0.14))

    // MARK: - sim の時刻（Kit_H028.Tune と同じ値。sim の値を変えたらここも合わせる）

    /// スキル1: 剣が回る秒数（swordsDuration）。2 組に分けて継ぐ。
    private static let orbitTime: Float = 5.0
    private static let orbitHalf: Float = 2.5
    /// スキル2: 突進の所要（dashRange 350 / dashSpeed 1800 ≈ 0.19 秒）。
    private static let chargeTime: Float = 0.19
    /// 奥義: 到着（≦0.19 秒）→ 3 連撃（到着 + 0.2 / 0.6 / 1.0 秒）。突進の平均の長さで置いた時刻。
    private static let ultArrive: Float = 0.18
    private static let ultStrikes: [Float] = [0.35, 0.75, 1.15]

    // MARK: - 部品

    /// 周りを回る光剣（前方の半円の帯に菱形の刃を 1 本だけ描いた弧。帯ごと回すと刃が術者の周りを回る）。
    /// 刃は帯の中央・接線の向きに寝る（長さ ≈ 半径 × 1.07、幅 ≈ 半径 × 0.26）。
    private static func orbitBlade(_ r: Float, _ tint: FXTint, life: Float, spin: Float, alpha: Float,
                                   fadeIn: Float, fadeOut: Float) -> FXMesh {
        FXMesh(shape: .arc, tex: .shard, tint: tint, alpha: alpha, size: [r, 1, r], sizeEnd: [r, 1, r], ease: .linear,
               life: life, fadeIn: fadeIn, fadeOut: fadeOut, spin: spin)
    }

    /// 回る光剣の 1 組（内側 3 本 + 外側 2 本）。second = 2 組目（前の組の終わりと同じ角度から続ける）。
    /// 内側は 432°/秒（2.5 秒で 3 回転 = 3 回対称の位置に戻る）、外側は 288°/秒（2 回転）。
    private static func orbitSet(at t: Float, second: Bool) -> [FXCue] {
        let life: Float = second ? orbitTime - orbitHalf : orbitHalf + 0.05
        let fadeIn: Float = second ? 0.01 : 0.04
        let fadeOut: Float = second ? 0.9 : 0.97
        return [
            .mesh(orbitBlade(1.15, .core, life: life, spin: 432, alpha: 1, fadeIn: fadeIn, fadeOut: fadeOut), at: t,
                  .follow, offset: [0, 0.95, 0]).repeated(3, yaw: 120),
            // 外側の 2 本（中画質以上。低画質は弧のプールが小さいので内側の 3 本だけ）
            .mesh(orbitBlade(1.65, .primary, life: life, spin: 288, alpha: 0.95, fadeIn: fadeIn, fadeOut: fadeOut)
                .with { $0.yaw = 60 }, at: t, .follow, offset: [0, 1.25, 0], quality: 1).repeated(2, yaw: 180),
        ]
    }

    /// 対象を断つ細く長い斬線（光の筋の帯。angle = 前方からの向き（度））。
    private static func cutLine(_ length: Float, width: Float, _ tint: FXTint, angle: Float, life: Float = 0.22,
                                alpha: Float = 1) -> FXMesh {
        FXMesh.ray(.slashLine, length: length, width: width, tint, life: life, alpha: alpha).with {
            $0.yaw = 90 + angle
            $0.size = [length * 0.6, 1, width * 0.5]
            $0.sizeEnd = [length, 1, width]
            $0.fadeIn = 0.02
            $0.fadeOut = 0.35
        }
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        switch slot {
        case .passive:
            // 防御ダウンの層が増えるたび: visor の瞬きと、胸の前を走る細い斬線（小さく短く）
            r.cast = [
                .emit(.flare(0.8, .core, life: 0.14, tex: .flare4), .follow, offset: [0, 1.62, 0.12]),
                .mesh(.sprite(.slashLine, 1.1, .primary, life: 0.2, grow: 1.35, alpha: 0.9), .follow, offset: [0, 1.15, 0.25]),
                .emit(.sparks(6, speed: 3, .core, end: .primary, life: 0.25, gravity: 0), .follow, offset: [0, 1.1, 0.2]),
            ]
            r.hit = []
        case .skill1:
            r = swordsRecipe(s)
        case .skill2:
            r = chargeRecipe(s)
        case .ultimate:
            r = sweepRecipe(s)
        }
        return r
    }

    // MARK: - スキル1 環剣

    /// 5 本の光剣が飛び出して 5 秒間 周りを回る。命中のたびに光剣が術者の側から飛び込む（hit）。
    private static func swordsRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 2.6)
        r.cast = [
            // 掲げた剣の閃きと、放射状に飛び出す光剣の筋
            .emit(.flare(1.4, .core, life: 0.18, tex: .flare6), offset: [0, 1.1, 0]),
            .emit(FXEmit(tex: .streak, tint: .core, tintEnd: .primary, count: 20, life: 0.28, size: 0.13, sizeVar: 0.3,
                         grow: 0.5, shape: .sphere(0.25), dir: .outward, speed: 7, speedVar: 0.25, drag: 2.0, stretch: 2.6,
                         fade: .linearFadeOut), offset: [0, 1.0, 0]),
            // 回る光剣（2 組で 5 秒）と、内側の軌道に残るきらめき
            .emit(.trail(.twinkle, .secondary, rate: 22, life: 0.45, size: 0.1).with {
                $0.duration = orbitTime; $0.shape = .ring(1.1); $0.surface = true; $0.speed = 0.3; $0.tintEnd = .accent
            }, .follow, offset: [0, 0.95, 0], quality: 1),
        ]
        r.cast += orbitSet(at: 0, second: false)
        r.cast += orbitSet(at: orbitHalf, second: true)
        // 自己中心なので発動と同時に再生される: 足元の機巧の陣（剣を呼ぶ）と、剣が飛び出す白い輪
        r.impact = [
            .mesh(.decal(.techCircle, R * 1.6, .accent, life: 0.7, spin: 140, alpha: 0.55)),
            .mesh(.shockRing(1.3, .core, life: 0.28, tex: .ring)),
            .emit(.motes(10, radius: 1.0, .secondary, life: 0.7), offset: [0, 0.9, 0]),
        ]
        // 接触・剣撃の 1 発ごと: 術者の側から光剣（矢の形の光）が飛び込み、刺さった瞬間に細い斬撃
        r.hit = [
            .mesh(FXMesh.ray(.arrow, length: 1.2, width: 0.42, .core, life: 0.14).with {
                $0.size = [1.2, 1, 0.42]; $0.sizeEnd = [1.0, 1, 0.42]; $0.advance = 10; $0.fadeIn = 0.05; $0.fadeOut = 0.75
            }, offset: [0, 1.0, -1.5]),
            .mesh(.sprite(.slashThin, 1.0, .primary, life: 0.16, grow: 1.25), at: 0.1, offset: [0, 1.05, 0]),
            .emit(.sparks(8, speed: 5, .core, end: .primary).with { $0.dir = .forward; $0.spread = 50 }, at: 0.1,
                  offset: [0, 1.0, 0]),
        ]
        r.hitPerHit = true
        return r
    }

    // MARK: - スキル2 断空突進

    /// 光の尾を引いて約 0.19 秒で駆け抜け、終点で前方へ一閃。着いたあと刃に光が宿る（強化通常攻撃の間）。
    private static func chargeRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = min(s.range, 3.5)
        let T = chargeTime
        r.cast = [
            // 踏み出しの閃きと、後ろへ残る光の残像・蹴った土煙
            .emit(.flare(1.2, .core, life: 0.14), offset: [0, 1.0, 0.2]),
            .mesh(FXMesh.ray(.streak, length: 1.8, width: 1.1, .secondary, life: 0.35, alpha: 0.8), offset: [0, 1.0, -0.4]),
            .emit(.smoke(5, radius: 0.4, .rgb(0.55, 0.6, 0.7), life: 0.6, size: 0.6).with { $0.dir = .backward; $0.speed = 2 },
                  offset: [0, 0.2, 0], quality: 1),
            // 突進の間の光の尾（後ろへ流れる光条 + 柔らかい光）
            .emit(.trail(.streak, .primary, rate: 90, life: 0.28, size: 0.5).with {
                $0.duration = T; $0.stretch = 3; $0.dir = .backward; $0.speed = 3; $0.tintEnd = .accent
            }, .follow, offset: [0, 1.0, 0]),
            .emit(.trail(.glow, .secondary, rate: 50, life: 0.3, size: 0.45).with { $0.duration = T }, .follow,
                  offset: [0, 1.0, 0]),
            // 通り道に焼き付く光の筋と、白い斬線（術者 → 終点の中間）
            .mesh(.ray(.streak, length: L * 0.9, width: 1.1, .primary, life: 0.42), at: 0.03, .along(0.5),
                  offset: [0, 0.95, 0]),
            .mesh(.ray(.slashLine, length: L * 0.85, width: 0.35, .core, life: 0.3), at: 0.06, .along(0.5), offset: [0, 1.0, 0]),
            // 終点: 前方へ振り抜く一閃（白い芯 + シアンの三日月）と閃光・前へ散る火花
            .mesh(.slash(1.5, .core, from: 75, to: -75, life: 0.2, tex: .slashThin), at: T, .target, offset: [0, 1.0, 0.2]),
            .mesh(.slash(1.6, .primary, from: 75, to: -75, life: 0.28), at: T, .target, offset: [0, 1.0, 0.15]),
            .emit(.flare(1.4, .core, life: 0.16, tex: .flare6), at: T, .target, offset: [0, 1.0, 0.3]),
            .emit(.fan(14, .primary, speed: 7, spread: 30, life: 0.3), at: T, .target, offset: [0, 1.0, 0.2]),
            // 強化通常攻撃の間（約 3 秒）: 刃のきらめき 3 回と、身を包む光の粒
            .mesh(.sprite(.flare4, 0.9, .core, life: 0.25, grow: 1.4), at: T + 0.25, .follow, offset: [0.35, 1.1, 0.25])
                .repeated(3, every: 0.9),
            .emit(.trail(.twinkle, .core, rate: 14, life: 0.5, size: 0.12).with {
                $0.duration = 3.0; $0.shape = .sphere(0.45); $0.dir = .up; $0.speed = 0.8; $0.tintEnd = .primary
            }, at: T, .follow, offset: [0, 1.0, 0]),
        ]
        // 突進（dashStrike）は impact を再生しない（終点の演出は cast の .target）。目視確認の実演（-skillDemo）だけが
        // impact・telegraph を出すので、既定演出で補われないよう小さく置く
        r.telegraph = [.mesh(.decal(.techCircle, 1.6, .secondary, life: 0.3, spin: 200, alpha: 0.5))]
        r.impact = [.shake(0.12)]
        // 通り道で斬られた敵: 突進の向きに走る白い斬線・閃光・前へ散る火花
        r.hit = [
            .mesh(.ray(.slashLine, length: 2.2, width: 0.45, .core, life: 0.22), offset: [0, 1.0, 0]),
            .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
            .emit(.sparks(10, speed: 6, .core, end: .primary).with { $0.dir = .forward; $0.spread = 40 }, offset: [0, 1.0, 0]),
        ]
        return r
    }

    // MARK: - 奥義 三連断空

    /// 空間を断って突進 → 打ち上げ → 3 連撃（最後が強い十字）。impact は対象の位置（発動時）で再生される。
    private static func sweepRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let t1 = ultStrikes[0], t2 = ultStrikes[1], t3 = ultStrikes[2]
        let y: Float = 1.4
        r.cast = [
            .emit(.flare(1.6, .core, life: 0.18, tex: .flare6), offset: [0, 1.0, 0.2]),
            .emit(.sparks(12, speed: 5, .core, end: .accent, gravity: 0).with { $0.shape = .sphere(0.5) }, offset: [0, 1.0, 0]),
            // 突進の光の尾（≦0.19 秒）と、術者 → 対象を断つ白い線（空間を断つ）
            .emit(.trail(.streak, .primary, rate: 90, life: 0.25, size: 0.45).with {
                $0.duration = 0.2; $0.stretch = 3; $0.dir = .backward; $0.speed = 4
            }, .follow, offset: [0, 1.0, 0]),
            .mesh(.ray(.slashLine, length: 2.6, width: 0.55, .core, life: 0.3), at: 0.02, .along(0.5), offset: [0, 1.1, 0]),
        ]
        r.impact = [
            // 照準の陣が対象へ締まる（ロックオン）
            .mesh(FXMesh(shape: .disc, tex: .techCircle, tint: .secondary, alpha: 0.8, size: [3.2, 1, 3.2],
                         sizeEnd: [1.4, 1, 1.4], ease: .in, life: 0.3, fadeIn: 0.1, fadeOut: 0.7, spin: 300)),
            // 到着 → 打ち上げ（1.2 秒）: 光の柱・昇る輪 3 つ・地を這う白い輪・昇る光条・土煙
            .emit(.flare(2.0, .core, life: 0.2, tex: .flare6), at: ultArrive, offset: [0, 1.1, 0]),
            .mesh(.pillar(0.55, height: 4.5, .primary, life: 0.55), at: 0.2),
            .mesh(.shockRing(1.4, .core, life: 0.3, tex: .ring), at: 0.2),
            .mesh(.halo(0.7, .accent, life: 0.6, spin: 300, tex: .ringDouble).with { $0.rise = 2.5 }, at: 0.2,
                  offset: [0, 0.2, 0]).repeated(3, every: 0.1),
            .emit(.rising(16, radius: 0.6, .secondary, speed: 6, life: 0.6, size: 0.12, tex: .streak), at: 0.2),
            .emit(.smoke(6, radius: 0.6, .rgb(0.55, 0.6, 0.7), life: 0.8, size: 0.7), at: 0.2, quality: 1),
            // 1 撃目: 前方 ±30° の 2 本の斬線が対象で交差し、右肩下がりの三日月
            .mesh(cutLine(3.6, width: 0.5, .core, angle: 30), at: t1, offset: [0, y, 0]).repeated(2, every: 0.03, yaw: -60),
            .mesh(.slash(1.3, .primary, from: 80, to: -80, tilt: 30, life: 0.26), at: t1, offset: [0, y, 0]),
            // 2 撃目: 向きを変えた 2 本（60° / 120°）と、逆に振る三日月
            .mesh(cutLine(3.6, width: 0.5, .core, angle: 60), at: t2, offset: [0, y + 0.1, 0]).repeated(2, every: 0.03, yaw: 60),
            .mesh(.slash(1.3, .secondary, from: -80, to: 80, tilt: -30, life: 0.26), at: t2, offset: [0, y + 0.1, 0]),
            .emit(.sparks(14, speed: 8, .core, end: .accent, gravity: 3), at: t1, offset: [0, y, 0]).repeated(2, every: t2 - t1),
            .shake(0.18, at: t1),
            .shake(0.18, at: t2),
            // 3 撃目（最も強い）: 4 本の放射の斬線・縦と横の大きな十字・閃光・広がる輪・地面に残る X の傷
            .mesh(cutLine(4.4, width: 0.7, .core, angle: 0, life: 0.26), at: t3, offset: [0, y + 0.2, 0])
                .repeated(4, every: 0.02, yaw: 45),
            .mesh(.slash(1.8, .core, from: 80, to: -80, tilt: 90, life: 0.28, tex: .slashThin), at: t3, offset: [0, y + 0.2, 0]),
            .mesh(.slash(2.0, .primary, from: 85, to: -85, life: 0.32), at: t3 + 0.03, offset: [0, y, 0]),
            .emit(.flare(2.8, .core, life: 0.26, tex: .flare6), at: t3, offset: [0, y + 0.2, 0]),
            .emit(.sparks(24, speed: 10, .core, end: .accent, size: 0.12, life: 0.45, gravity: 4), at: t3, offset: [0, y, 0]),
            .mesh(.shockRing(2.4, .primary, life: 0.4), at: t3),
            .mesh(.shockRing(3.2, .accent, life: 0.6), at: t3 + 0.06),
            .mesh(cutLine(3.4, width: 0.6, .secondary, angle: 45, life: 1.0, alpha: 0.8), at: t3, offset: [0, 0.02, 0])
                .repeated(2, yaw: 90),
            .shake(0.5, at: t3),
        ]
        // 1 撃ごと（sim の時刻どおり）: 白い閃光・細い斬撃・火花
        r.hit = [
            .emit(.flare(1.2, .core, life: 0.12), offset: [0, 1.3, 0]),
            .mesh(.sprite(.slashThin, 1.3, .core, life: 0.14, grow: 1.2), offset: [0, 1.3, 0]),
            .emit(.sparks(10, speed: 7, .core, end: .secondary, gravity: 2), offset: [0, 1.3, 0]),
        ]
        r.hitPerHit = true
        return r
    }

    // MARK: - 詠唱モーション

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 剣を構えて手元で回し、光剣を周りへ放つ
            m.windup(0.06, side: 1, power: 0.6)
            m.twirl(0.18, turns: 1)
            m.hold(0.12) { $0.glow = 1.8 }
        case .skill2:
            // 前傾で駆け（0.19 秒）、着いて前方へ振り抜く
            m.dash(0.04, lean: 0.55)
            m.hold(0.14) { $0.glow = 1.4 }
            m.slash(0.06, side: 1, power: 1.1)
            m.hold(0.08) { $0.glow = 1.8 }
            m.settle(0.08)
        case .ultimate:
            // 低く構えて駆け込み → 右から（0.35 秒）・左から（0.75 秒）斬り返し → 頭上から縦に断つ（1.15 秒）
            m.brace(0.04, depth: 0.12)
            m.dash(0.05, lean: 0.5)
            m.hold(0.1)
            m.windup(0.1, side: 1, power: 1.0)
            m.slash(0.06, side: 1, power: 1.2)
            m.hold(0.24)
            m.windup(0.1, side: -1, power: 1.0)
            m.slash(0.06, side: -1, power: 1.2)
            m.hold(0.22)
            m.overhead(0.1)
            m.smash(0.08)
            m.hold(0.12) { $0.glow = 2.2 }
        }
    }
}
