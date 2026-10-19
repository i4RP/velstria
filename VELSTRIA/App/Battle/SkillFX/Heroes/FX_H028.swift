import Foundation
import VelstriaCore

// スキル演出: H028 断空のザイル（Assassin / 赤い刃縁の黒い長剣・鋼青の機甲・赤い visor。MLBB の Saber の Velstria 版）。
// 主題: 赤い手裏剣の剣と、青い残像・青紫の斬撃。白（桃がかった芯）× 深紅（主: 回る剣・剣撃の矢）× 水色（副: 突進の残像）×
// 青紫（差し色: 奥義の斬撃）× 濃紺（暗: 剣の地・矢の尾）。MLBB の画面収録（vid9、docs/vfx/H028.md）の色と形に寄せた。
// 上から見下ろすカメラで「赤い剣が 5 本 周りを回る → 殴るたびに 1 本ずつ赤い矢になって相手を貫く」「水色の残像を残して駆ける」
// 「打ち上げた相手を青紫の斬撃が三度断つ」が読めるよう、地面の陣は置かず、剣・残像・斬撃そのもので形を見せる。
// sim の実際の挙動（Systems/Kits/Kit_H028.swift の Tune）に合わせたタイミング:
//   パッシブ 空断の理      — ダメージを与えるたびに相手の防御を削る（最大 5 層・5 秒）。層が増えるたび（バッジの数が増えるたび）に
//                            visor が瞬き、胸の前に細い赤い斬線が光る（頻繁に出るので小さく短く。層そのものは相手の頭上の .mark）
//   スキル1 環剣（自己中心）— 0 秒: 剣を体の周りで一回し（赤い三日月の輪と淡い青の渦）。0.2 秒: 5 本の赤い手裏剣が術者から
//                            放射状に飛び出し、0.47 秒（pulseFirst）に術者から 3.85m の輪に着く。そこから 4.8 秒まで輪を回る
//                            （MLBB の画面収録で測った値: 5 本・毎秒 151° で時計回り・照準の円 4.45 = 剣の帯の外縁。弧の刃は帯 3.2〜4.45m に描く。
//                            メッシュの寿命は 4 秒までなので 2 組に分け、2 組目は 2.4 秒（毎秒 150° でちょうど 1 周）から同じ角度で継ぐ）。
//                            剣撃 1 本ごとに sim は輪の剣を 1 本使う（使った剣は戻らない）。スキル1 のバッジ（残りの本数）が減るたびに
//                            SkillFXDirector が回る刃を 1 本ずつ消す（FXMesh.group 1〜5 = spentGroups。5 → 4 → 等間隔の 3 本 → 2 → 1）。
//                            使い切ると効果がその場で終わり、刃も全部消える。
//                            hit（接触 0.48 秒ごと / 剣撃 = 通常攻撃・スキルの命中から 0.1 秒）: 術者の側から赤い剣（矢の形・濃紺の尾）が
//                            飛び込み、相手を貫いて反対側へ抜けて消える。貫いた瞬間に白桃の閃きと短い赤い斬線（1 発ごと）
//   スキル2 断空突進        — 3m を 0.2 秒（15m/s）で駆ける。通り道に水色の残像が並び、古いものから薄れる。
//                            突進は impact を再生しない（ゾーンを作らない）ので、終点の演出は cast の .follow に 0.2 秒遅れで置く。
//                            着いたら刃に赤い光が宿り、約 3 秒 赤いきらめき（次の通常攻撃が強化される間）
//   奥義 三連断空（対象指定）— 突進（17m/s、縁まで最大 5.45m。動画の 2 回は 2.4〜3.2m で 0.14〜0.19 秒。赤い残像と青紫の光条）→
//                            到着で打ち上げ 1.2 秒（相手を貫く青い光の柱）→ 到着の瞬間・0.39 秒・0.78 秒に 3 連撃（弱・弱・強）→
//                            到着から 1.0 秒で術者が動ける。impact（対象の位置）は 0.2 / 0.59 秒に青紫の三日月と交差する白い斬線、
//                            0.98 秒に 4 本の放射の斬線・縦横の大きな十字・青紫の爆ぜ・地面の X の傷。hit（1 撃ごと・正確な時刻）は白桃の閃き
// 光る部品（閃光・光の柱・斬撃の光・残像の帯）は加算（glowing）。回る剣・剣撃の矢・その尾・剣の一回しはアルファ合成（暗い地・赤が白く飛ばない）。
// SkillFXDirector は duration / count を読まない: 突進の長さで 3 連撃が最大 0.15 秒ほど前後する（hit は sim の時刻どおり）。

enum FX_H028: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.95, 0.99), primary: RGB(0.86, 0.13, 0.21),
                                   secondary: RGB(0.17, 0.64, 0.92), accent: RGB(0.45, 0.55, 1.0),
                                   dark: RGB(0.2, 0.19, 0.38))

    /// 回る剣・飛び出す手裏剣の赤（動画 f80 の剣の縁 #C21C32・中央値 #87263C の間）。
    private static let blade = FXTint.rgb(0.74, 0.12, 0.22)
    /// 発動の一回しの赤い三日月（動画 f63〜f65: #E7533D、明るい側 #FE6C5A）。
    private static let swing = FXTint.rgb(0.98, 0.36, 0.3)
    /// 一回しに巻く淡い青の渦（動画 f63〜f64: #648DCE〜#7DAAD3）。
    private static let frost = FXTint.rgb(0.49, 0.67, 0.83)
    /// 奥義の斬撃の青紫の明るい側（動画 f887: #C562FC）と、閃きの桃色（f888: #F4A3E9）。
    private static let violet = FXTint.rgb(0.77, 0.38, 0.99)
    private static let pink = FXTint.rgb(0.96, 0.64, 0.91)

    // MARK: - sim の時刻（Kit_H028.Tune と同じ値。sim の値を変えたらここも合わせる）

    /// スキル1: 剣が回る秒数（swordsDuration）。2 組に分けて継ぐ。
    private static let orbitTime: Float = 4.8
    private static let orbitHalf: Float = 2.4
    /// スキル1: 剣の帯の外縁（swordReach 445 = 4.45m。弧のメッシュは内径 0.72 なので帯 3.2〜4.45m に刃が寝る）と回る速さ
    /// （orbitSpeed 151°/秒の時計回り。2.4 秒でちょうど 1 周する 150°/秒。spin は上から見て反時計回りが正なので負）。
    private static let orbitReach: Float = 4.45
    private static let orbitSpin: Float = -150
    /// スキル1: 剣が輪に着く時刻（pulseFirst 0.47。動画: 指を離して 14 コマ）。
    private static let ringArrive: Float = 0.47
    /// スキル2: 突進の所要（dashRange 300 / dashSpeed 1500 = 0.2 秒）。
    private static let chargeTime: Float = 0.2
    /// 奥義: 到着（動画の 2 回の突進 2.4〜3.2m / 17m/s ≈ 0.14〜0.19 秒）→ 3 連撃（到着 + 0 / 0.39 / 0.78 秒。sim は 1 撃目を到着の次の tick）。
    private static let ultArrive: Float = 0.17
    private static let ultStrikes: [Float] = [0.2, 0.59, 0.98]

    // MARK: - 見た目の時刻（動画に合わせた値。sim には無い）

    /// スキル1: 手裏剣が術者から飛び出す時刻（動画: 指を離して 6 コマ = 0.2 秒、f68）。
    private static let swordsOut: Float = 0.2
    /// スキル1: 回る刃（組の付いた弧）が現れ始める時刻。飛び出した手裏剣が輪に着く ringArrive までに立ち上がる。
    private static let bladeStart: Float = 0.3

    // MARK: - 部品

    /// 周りを回る赤い剣（前方の半円の帯に菱形の刃を 1 本だけ描いた弧。帯ごと回すと刃が術者の周りを回る）。
    /// 刃は帯の中央・接線の向きに寝る（長さ ≈ 半径 × 0.92 = 61° の弧、幅 = 帯の 1.25m）。MLBB の手裏剣（1.2m の 4 枚刃、
    /// 深紅の縁・濃紺の地）は弧と既存の画像では作れないので、深紅の刃に濃紺の筋の模様を弧に沿って流し、回る刃の歯に見せる。
    private static func orbitBlade(_ r: Float, life: Float, spin: Float, fadeIn: Float, fadeOut: Float) -> FXMesh {
        FXMesh(shape: .arc, tex: .shard, tint: blade, alpha: 0.95, size: [r, 1, r], sizeEnd: [r, 1, r], ease: .linear,
               life: life, fadeIn: fadeIn, fadeOut: fadeOut, spin: spin)
            .flowing(.streaks, scroll: [-0.8, 0], tiling: 1.5, strength: 0.5, edge: .dark)
    }

    /// 回る剣の 5 本の角度（前方から、72° おき）。並びは剣を使ったときに消える順（FXMesh.group 1〜5 = spentGroups）。
    /// 先に消える 72° / 216° の 2 本は中画質以上（低画質は弧のプールが小さいので 0° / 144° / 288° の 3 本だけ = 残りが 3 本までは同じ見た目）。
    /// 5 → 4 → 3 本で等間隔の 3 本（0° / 144° / 288°）、そこから 144° / 288° → 288° と減る。
    private static let bladeAngles: [Float] = [72, 216, 0, 144, 288]
    /// 低画質でも出す刃（bladeAngles の添字がこれ以上）。
    private static let lowQualityFrom = 2

    /// 回る剣の 1 組（同じ輪の 5 本 = 72° おき。1 本ずつ別の合図にして FXMesh.group を付ける）。
    /// 1 組目は bladeStart（0.3 秒）から、0 秒に出ていたときと同じ位置（150°/秒 × 0.3 秒 = 45° 回した角度）で現れ、輪に着く 0.47 秒までに
    /// 立ち上がる。2 組目は 2.4 秒から元の角度で続ける（150°/秒で 2.4 秒 = 1 周なので継ぎ目が消える）。
    /// sim は剣撃 1 本ごとに輪の剣を 1 本使う（使った剣は戻らない）。スキル1 のバッジ（残りの本数）が減るたびに SkillFXDirector が
    /// その組の刃を消し、2 組目の予定の合図も取り消す（spentGroups）。使い切ると 5 本とも消える。
    private static func orbitSet(second: Bool) -> [FXCue] {
        let t: Float = second ? orbitHalf : bladeStart
        let life: Float = second ? orbitTime - orbitHalf : orbitHalf - bladeStart + 0.05
        let fadeIn: Float = second ? 0.01 : (ringArrive - bladeStart) / life
        let fadeOut: Float = second ? 0.9 : 0.97
        let turned: Float = second ? 0 : orbitSpin * bladeStart
        var cues: [FXCue] = []
        for (i, angle) in bladeAngles.enumerated() {
            let low = i >= lowQualityFrom
            let b = orbitBlade(orbitReach, life: life, spin: orbitSpin, fadeIn: fadeIn, fadeOut: fadeOut).with {
                $0.yaw = angle + turned
                $0.group = i + 1
            }
            cues.append(.mesh(b, at: t, .follow, offset: [0, 0.95, 0], quality: low ? 0 : 1))
        }
        return cues
    }

    // MARK: - 残りの剣（スキル1 のバッジ = 輪に残っている剣の本数）

    static var countedSlot: SkillSlot? { .skill1 }

    /// 残りが remaining 本のときに消えている刃の組（使った本数ぶん、bladeAngles の順に 1〜）。
    static func spentGroups(remaining: Int) -> [Int] {
        let spent = min(bladeAngles.count, max(0, bladeAngles.count - remaining))
        guard spent > 0 else { return [] }
        return Array(1...spent)
    }

    /// 対象を断つ細く長い斬線（光の筋の帯。angle = 前方からの向き（度））。加算。
    private static func cutLine(_ length: Float, width: Float, _ tint: FXTint, angle: Float, life: Float = 0.22,
                                alpha: Float = 1) -> FXMesh {
        FXMesh.ray(.slashLine, length: length, width: width, tint, life: life, alpha: alpha).with {
            $0.yaw = 90 + angle
            $0.size = [length * 0.6, 1, width * 0.5]
            $0.sizeEnd = [length, 1, width]
            $0.fadeIn = 0.02
            $0.fadeOut = 0.35
        }.glowing()
    }

    /// 体の高さに立つ残像（上へ細る炎の形の板を縦のままカメラへ向け、動かさずに置いていく）。突進の間だけ出す。
    private static func afterimages(_ tint: FXTint, rate: Float, life: Float, size: Float, duration: Float) -> FXEmit {
        FXEmit().with {
            $0.tex = .flame
            $0.tint = tint
            $0.tintEnd = .dark
            $0.rate = rate
            $0.duration = duration
            $0.life = life
            $0.lifeVar = 0.15
            $0.size = size
            $0.sizeVar = 0.1
            $0.grow = 0.85
            $0.dir = .up
            $0.speed = 0
            $0.speedVar = 0
            $0.orient = .upright
            $0.fade = .linearFadeOut
        }
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        switch slot {
        case .passive:
            // 防御ダウンの層が増えるたび: 赤い visor の瞬きと、胸の前を走る細い赤い斬線（小さく短く）
            r.cast = [
                .emit(.flare(0.8, .core, life: 0.14, tex: .flare4), .follow, offset: [0, 1.62, 0.12]),
                .mesh(.sprite(.slashLine, 1.1, .primary, life: 0.2, grow: 1.35, alpha: 0.9).glowing(), .follow,
                      offset: [0, 1.15, 0.25]),
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

    /// 剣を一回し → 0.2 秒で 5 本の赤い手裏剣が飛び出し → 0.47〜4.8 秒 術者から 3.85m の輪を回る。
    /// 命中のたびに赤い剣が術者の側から飛び込んで貫く（hit）。
    private static func swordsRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let out = swordsOut
        // 手裏剣が術者のそば（0.55m）から輪（3.85m）まで 0.27 秒で飛ぶ速さ。72° おきに出すと、輪に着く 0.47 秒の
        // 刃の位置（150°/秒 × 0.47 = 70.5° 回った位置）にほぼ重なる
        let flySpeed: Float = (3.85 - 0.55) / (ringArrive - out)
        r.cast = [
            // 指を離した瞬間の刃の閃き
            .emit(.flare(1.1, .core, life: 0.14, tex: .flare4), offset: [0.3, 1.2, 0.2]),
            // 剣を体の周りで一回し: 腰の高さの赤い三日月の輪（時計回りに 1 周）と、上体に巻く淡い青の渦
            .mesh(FXMesh.sweep(1.3, swing, from: 90, to: -270, life: 0.2).with { $0.fadeOut = 0.45 }, .follow,
                  offset: [0, 0.6, 0]),
            .mesh(FXMesh(shape: .disc, tex: .swirl, tint: frost, alpha: 0.6, size: [1.5, 1, 1.5], sizeEnd: [2.2, 1, 2.2],
                         ease: .out, life: 0.28, fadeIn: 0.05, fadeOut: 0.4, spin: -1100), .follow, offset: [0, 1.0, 0]),
            // 0.2 秒: 5 本の赤い手裏剣（回る星形の板）が術者から放射状に飛び出し、輪に着く手前で回る刃に入れ替わる
            .mesh(FXMesh(shape: .disc, tex: .star, tint: blade, alpha: 1, size: [1.0, 1, 1.0], sizeEnd: [1.2, 1, 1.2],
                         ease: .out, life: 0.29, fadeIn: 0.1, fadeOut: 0.8, spin: -900, advance: flySpeed),
                  at: out, .follow, offset: [0, 0.95, 0]).ringed(5, radius: 0.55),
        ]
        // 回る剣（2 組で 4.8 秒）
        r.cast += orbitSet(second: false)
        r.cast += orbitSet(second: true)
        // 自己中心なので発動と同時に再生される: 手裏剣と一緒に外へ散る赤い光条（剣の残像）
        r.impact = [
            .emit(FXEmit(tex: .streak, tint: .primary, tintEnd: .dark, count: 16, life: 0.3, size: 0.13, sizeVar: 0.3,
                         grow: 0.5, shape: .sphere(0.3), dir: .outward, speed: 9, speedVar: 0.25, drag: 2.5, stretch: 2.6,
                         fade: .linearFadeOut), at: out, offset: [0, 0.95, 0]),
        ]
        // 接触・剣撃の 1 発ごと: 術者の側から赤い剣（矢の形）と濃紺の尾が飛び込み、相手を貫いて反対側へ抜けて消える
        // （動画 f173〜f177: 赤 #D8222E〜#F04248 の矢と濃紺 #324979 の尾が 4 コマで抜ける）。貫いた瞬間に白桃の閃きと短い赤い斬線
        r.hit = [
            .mesh(FXMesh.ray(.arrow, length: 1.6, width: 0.55, .primary, life: 0.16).with {
                $0.size = [1.6, 1, 0.55]; $0.sizeEnd = [1.4, 1, 0.45]; $0.advance = 22; $0.fadeIn = 0.05; $0.fadeOut = 0.7
            }, offset: [0, 1.0, -1.6]),
            .mesh(FXMesh.ray(.streak, length: 2.4, width: 0.3, .dark, life: 0.18, alpha: 0.85).with {
                $0.size = [2.4, 1, 0.3]; $0.sizeEnd = [2.0, 1, 0.15]; $0.advance = 22; $0.fadeIn = 0.05; $0.fadeOut = 0.5
            }, offset: [0, 1.0, -3.4]),
            .emit(.sheet(.hitFlash, 1.4, .core, end: pink, life: 0.2), at: 0.07, offset: [0, 1.05, 0]),
            .emit(.sheet(.slashFade, 1.3, .primary, end: .dark, life: 0.22).with { $0.angle = -25; $0.angleVar = 30 },
                  at: 0.07, offset: [0, 1.0, 0]),
        ]
        r.hitPerHit = true
        return r
    }

    // MARK: - スキル2 断空突進

    /// 0.2 秒で駆け抜け、通り道に水色の残像を並べて残す（MLBB: 終点の斬撃は無い）。着いたら刃に赤い光が宿る（強化通常攻撃の間）。
    private static func chargeRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = min(s.range, 3.0)
        let T = chargeTime
        let hand: SIMD3<Float> = [0.4, 1.0, 0.35]
        r.cast = [
            // 踏み出しの白い閃き
            .emit(.flare(1.0, .core, life: 0.12), offset: [0, 1.0, 0.2]),
            // 通り道に並ぶ水色の残像（動画 f144〜f156: 体の高さの影が並び、古いものから 0.3〜0.45 秒で薄れる。#2BA4E5 / 中央値 #1F6F97）
            .emit(afterimages(.secondary, rate: 45, life: 0.42, size: 1.3, duration: T + 0.02), .follow, offset: [0, 0.7, 0]),
            // 残像の揺らぐ煙の筋（コマ送り）
            .emit(.trail(.glow, .secondary, rate: 30, life: 0.5, size: 1.1).with {
                $0.duration = T; $0.sheet = .darkWisp; $0.orient = .upright; $0.speed = 0; $0.grow = 1.1; $0.tintEnd = .accent
                $0.fade = .easeFadeOut
            }, .follow, offset: [0, 0.8, 0], quality: 1),
            // 残像をつなぐ淡い水色の帯（体の高さ。模様が揺らいで縁から欠けて消える）
            .mesh(.ray(.streak, length: L, width: 0.9, .secondary, life: 0.45, alpha: 0.55).glowing()
                .flowing(.noise, scroll: [-1.5, 0], tiling: 2, strength: 0.6, erosion: 0.45, edge: .core),
                  at: 0.03, .along(0.5), offset: [0, 0.8, 0]),
            // 着いた刃に赤い光が宿る（動画 f150〜f160・f542〜f546 の剣の赤い光 = 強化通常攻撃）
            .mesh(.sprite(.slashLine, 1.4, .primary, life: 0.3, grow: 1.15).glowing(), at: T, .follow, offset: hand),
            .emit(.flare(0.8, .primary, life: 0.18, tex: .flare4), at: T, .follow, offset: hand),
            // 強化通常攻撃の間（約 3 秒）: 刃の赤いきらめき 3 回と、刃から立つ赤い光の筋
            .mesh(.sprite(.flare4, 0.8, .primary, life: 0.25, grow: 1.4).glowing(), at: T + 0.3, .follow,
                  offset: [0.4, 1.1, 0.3]).repeated(3, every: 0.9),
            .emit(.trail(.streak, .primary, rate: 14, life: 0.35, size: 0.18).with {
                $0.duration = 3.0; $0.shape = .sphere(0.25); $0.dir = .up; $0.speed = 0.8; $0.stretch = 1.5; $0.tintEnd = .dark
            }, at: T, .follow, offset: hand),
        ]
        // 突進（dashStrike）は impact を再生しない（終点の演出は cast の .follow）。目視確認の実演（-skillDemo）だけが
        // impact・telegraph を出すので、既定演出で補われないよう小さく置く
        r.telegraph = [.mesh(.decal(.techCircle, 1.6, .secondary, life: 0.3, spin: 200, alpha: 0.5))]
        r.impact = [.shake(0.12)]
        // 通り道で斬られた敵: 突進の向きに走る水色の斬線・白い閃き・前へ散る火花
        r.hit = [
            .mesh(.ray(.slashLine, length: 2.0, width: 0.4, .secondary, life: 0.2).glowing(), offset: [0, 1.0, 0]),
            .emit(.sheet(.hitFlash, 1.3, .core, end: .secondary, life: 0.2), offset: [0, 1.0, 0]),
            .emit(.sparks(8, speed: 6, .core, end: .secondary).with { $0.dir = .forward; $0.spread = 40 }, offset: [0, 1.0, 0]),
        ]
        return r
    }

    // MARK: - 奥義 三連断空

    /// 突進 → 打ち上げ → 3 連撃（最後が強い十字）。impact は対象の位置（発動時）で再生される。
    /// MLBB（動画 f885〜f890・f247〜f251）: 駆け出す足元の赤い残像 → 相手を貫く青い光の柱と白桃の閃き → 青紫の三日月と白い斬線。
    /// 赤い爆ぜ（f888〜f890）は環剣の剣撃（スキル1 の hit）なので、ここでは出さない。3 撃目は情報の板に隠れて見えない（推定）。
    private static func sweepRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let a = ultArrive
        let t1 = ultStrikes[0], t2 = ultStrikes[1], t3 = ultStrikes[2]
        let y: Float = 1.4
        r.cast = [
            .emit(.flare(1.3, .core, life: 0.14, tex: .flare6), offset: [0, 1.0, 0.2]),
            // 突進（17m/s。動画の 2 回は 0.14〜0.19 秒）: 足元に赤い残像（f885: #972629〜#CB3E44）と、後ろへ流れる青紫の光条
            .emit(afterimages(.primary, rate: 60, life: 0.3, size: 1.2, duration: a), .follow, offset: [0, 0.65, 0]),
            .emit(.trail(.streak, .accent, rate: 80, life: 0.22, size: 0.4).with {
                $0.duration = a; $0.stretch = 3; $0.dir = .backward; $0.speed = 4; $0.tintEnd = violet
            }, .follow, offset: [0, 1.0, 0]),
        ]
        r.impact = [
            // 到着 → 打ち上げ（1.2 秒）: 相手を貫く青い光の柱（f886: #4158D5〜#738EFE。筋が上へ流れる）・白桃の閃き・昇る青紫の筋と輪
            .mesh(.pillar(0.45, height: 4.0, .accent, life: 0.32).glowing()
                .flowing(.streaks, scroll: [0, -3], tiling: 2, strength: 0.6, edge: .core), at: a),
            .emit(.sheet(.hitFlash, 2.4, .core, end: violet, life: 0.25), at: a, offset: [0, y, 0]),
            .emit(.rising(14, radius: 0.5, .accent, speed: 6, life: 0.5, size: 0.12, tex: .streak), at: a),
            .mesh(FXMesh.halo(0.7, violet, life: 0.5, spin: 300, tex: .ringDouble).with { $0.rise = 2.5 }.glowing(), at: a,
                  offset: [0, 0.2, 0]).repeated(2, every: 0.12),
            // 1 撃目（到着の瞬間）: 青紫の三日月（コマ送り + 光る弧）と、前方 ±30° の 2 本の白い斬線が対象で交差（f887〜f889）
            .emit(.sheet(.slashFade, 2.6, .accent, end: violet, life: 0.3).with { $0.angle = 30; $0.angleVar = 0 }, at: t1,
                  offset: [0, y, 0]),
            .mesh(.slash(1.4, .accent, from: 80, to: -80, tilt: 30, life: 0.26).glowing(), at: t1, offset: [0, y, 0]),
            .mesh(cutLine(3.4, width: 0.4, .core, angle: 30), at: t1, offset: [0, y, 0]).repeated(2, every: 0.03, yaw: -60),
            // 2 撃目: 逆に振る三日月と、向きを変えた 2 本（60° / 120°）
            .emit(.sheet(.slashFade, 2.6, violet, end: .accent, life: 0.3).with { $0.angle = -150; $0.angleVar = 0 }, at: t2,
                  offset: [0, y + 0.1, 0]),
            .mesh(.slash(1.4, violet, from: -80, to: 80, tilt: -30, life: 0.26).glowing(), at: t2, offset: [0, y + 0.1, 0]),
            .mesh(cutLine(3.4, width: 0.4, .core, angle: 60), at: t2, offset: [0, y + 0.1, 0]).repeated(2, every: 0.03, yaw: 60),
            .emit(.sparks(12, speed: 8, .core, end: .accent, gravity: 3), at: t1, offset: [0, y, 0]).repeated(2, every: t2 - t1),
            .shake(0.18, at: t1),
            .shake(0.18, at: t2),
            // 3 撃目（最も強い。推定）: 4 本の放射の白い斬線・縦と横の大きな十字・青紫の爆ぜ・広がる輪・地面に残る X の傷
            .mesh(cutLine(4.2, width: 0.6, .core, angle: 0, life: 0.26), at: t3, offset: [0, y + 0.2, 0])
                .repeated(4, every: 0.02, yaw: 45),
            .mesh(.slash(1.8, .core, from: 80, to: -80, tilt: 90, life: 0.28, tex: .slashThin).glowing(), at: t3,
                  offset: [0, y + 0.2, 0]),
            .mesh(.slash(2.0, .accent, from: 85, to: -85, life: 0.32).glowing(), at: t3 + 0.03, offset: [0, y, 0]),
            .emit(.sheet(.energyBurst, 3.2, .core, end: violet, life: 0.36), at: t3, offset: [0, y + 0.2, 0]),
            .emit(.sparks(22, speed: 10, .core, end: .accent, size: 0.12, life: 0.45, gravity: 4), at: t3, offset: [0, y, 0]),
            .mesh(.shockRing(2.4, .accent, life: 0.4).glowing(), at: t3),
            .mesh(.shockRing(3.0, violet, life: 0.55).glowing(), at: t3 + 0.06),
            .mesh(cutLine(3.2, width: 0.5, .accent, angle: 45, life: 0.9, alpha: 0.7), at: t3, offset: [0, 0.02, 0])
                .repeated(2, yaw: 90),
            .shake(0.5, at: t3),
        ]
        // 1 撃ごと（sim の時刻どおり）: 白桃の閃き（コマ送り）・青紫の細い斬撃・火花
        r.hit = [
            .emit(.sheet(.hitFlash, 1.6, .core, end: pink, life: 0.2), offset: [0, 1.3, 0]),
            .mesh(.sprite(.slashThin, 1.3, .accent, life: 0.14, grow: 1.2).glowing(), offset: [0, 1.3, 0]),
            .emit(.sparks(10, speed: 7, .core, end: violet, gravity: 2), offset: [0, 1.3, 0]),
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
            // 前傾で駆け（0.2 秒）、着いて前方へ振り抜く
            m.dash(0.04, lean: 0.55)
            m.hold(0.16) { $0.glow = 1.4 }
            m.slash(0.06, side: 1, power: 1.1)
            m.hold(0.08) { $0.glow = 1.8 }
            m.settle(0.08)
        case .ultimate:
            // 低く構えて駆け込み（0.17 秒）→ 着いた瞬間に右から（0.2 秒）・左から（0.59 秒）斬り返し → 頭上から縦に断つ（0.98 秒）
            // → 到着から 1.0 秒の硬直の間は構えたまま（clip.total = 1.24 + 戻り 0.35 = 1.59 秒。奥義の範囲 0.45〜1.7 秒）
            m.brace(0.03, depth: 0.12)
            m.dash(0.05, lean: 0.5)
            m.windup(0.06, side: 1, power: 1.0)
            m.slash(0.06, side: 1, power: 1.2)
            m.hold(0.23)
            m.windup(0.1, side: -1, power: 1.0)
            m.slash(0.06, side: -1, power: 1.2)
            m.hold(0.23)
            m.overhead(0.1)
            m.smash(0.06)
            m.hold(0.26) { $0.glow = 2.2 }
        }
    }
}
