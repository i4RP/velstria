import Foundation
import VelstriaCore

// スキル演出: H034 鎖鉤のゴルム（Support / 先に鉤のついた太い鎖・鉄の肩当てと胸当て・大柄。MLBB の Franco の Velstria 版）。
// 主題: 鉄の鎖と、燃える鉤。白い芯 × 炎の橙（主）× 熾火の赤（副）× 鋼の灰青（差し色 = 鎖と鉤の鉄）× 煤（暗）。
// MLBB の Franco の演出は橙の炎と鉄: 鉤は鋼、光は橙。上から見下ろすカメラで「鎖を引いて鉤が飛ぶ → 食い込んで手元へ引きずる」
// 「斧鉤を地に叩きつけて炎の亀裂が走る」「鎖で縛り上げて何度も叩き伏せる」が読めるよう、円い輪を主役にせず、
// 伸び縮みする鎖・放射の炎の亀裂・X 字に縛る鎖と交互の斬撃で見せる。
// sim の実際の挙動（Systems/Kits/Kit_H034.swift の Tune）に合わせたタイミング:
//   パッシブ 鉄鎖の執念    — 5 秒無被弾のあと闘気が 1 秒に 1 つたまる（バッジのスタックが増えるたび = 毎秒）: 鉤の手に橙の閃きと、
//                            足元に薄い炎の輪・舞い上がる火の粉（重なって「燃えたぎる」）。闘気はスキルのダメージが当たった時に消費する
//                            （sim: 鉤の命中・S2 の叩きつけ・奥義の 6 撃目。外れたら残る）。消費（バッジが 0 に戻る）が発動から 0.6 秒以内
//                            （S2・近い鉤）なら passiveRelease: 鉤から炎が噴き、鎖が 3 方向へはじける（大きさは消費した闘気の数に比例）。
//                            遠い鉤・奥義の消費は Director の窓（kitReleaseWindow）の外なので出ない
//   スキル1 鎖鉤           — 0.33 秒の振りかぶり（体をひねって鎖を回す）の後に、射程 8.23m・15.15m/s（最大 0.54 秒）の非貫通の鉤。
//                            鉤の頭（鋼の三日月 + 橙の光）と、手元 → 鉤まで伸びる鎖（travel。発射から）。鎖は 0.14 秒ずつの 4 本に分け、
//                            各本が鉤に追従しながら伸びる（命中・消滅で追従が切れると、残りの本は出ない）。
//                            命中点（impact）: 鉤が食い込む閃光・爪痕・手元へ飛ぶ火花。被弾者（hit）: その場で 0.45 秒張られた鎖の後、
//                            引き寄せ（0.25 秒）の間に縮む鎖・手元へ流れる光条・術者の手元の閃き・スタン（その場 + 引き寄せ + 着地 = 1.3 秒）の
//                            間に巻きつく鎖の輪
//   スキル2 鉄鎖旋         — 自身中心（半径 2.57m）。0.27 秒の振りかぶりで斧鉤を地に叩きつける（sim のダメージも 0.27 秒。hit はダメージの時刻）:
//                            暗い地割れ + 橙に燃える地割れ・6 方向へ走る炎の亀裂・立ちのぼる炎の舌・炎の壁・岩片。被弾者は燃える枷（70% 鈍足 1.5 秒）
//   アルティメット 狩猟鎖獄 — 対象指定（縁まで 1.88m。その場で拘束）→ 0.25 秒で掴みかかり、1.8 秒の拘束の間に 6 回殴る（0.25 + 0.32n 秒）。
//                            impact（対象の位置。発動の時に再生）: 掴んだ瞬間の閃光、X 字に縛る鎖 4 本と地から突き上がる鉄の鉤 4 本（拘束の間）、
//                            0.25〜1.53 秒の 5 撃は左右交互の三日月、1.85 秒の 6 撃目は頭上から叩き伏せる大きな一撃。
//                            hit（1 撃ごと・sim の時刻どおり）は短い閃光と血の火花
// 時刻と寸法は MLBB の画面収録で測った値（docs/kits/Franco.md「動画で測った値（2026-10-16）」）。SkillFXDirector は duration / count を読まない。

enum FX_H034: HeroFXSet {
    static let palette = FXPalette(core: RGB(1.0, 0.95, 0.82), primary: RGB(1.0, 0.55, 0.14),
                                   secondary: RGB(0.88, 0.22, 0.07), accent: RGB(0.72, 0.75, 0.82),
                                   dark: RGB(0.12, 0.06, 0.03))

    /// 土煙・岩片（乾いた土色のアルファ合成）。
    private static let dust = FXTint.rgb(0.45, 0.37, 0.28)
    /// 血の火花。
    private static let blood = FXTint.rgb(0.8, 0.06, 0.04)

    // MARK: - sim の時刻・寸法（Kit_H034.Tune と同じ値。sim の値を変えたらここも合わせる）

    /// スキル1: 振りかぶりの長さ（hookDelay。発動 → 鉤が飛び出す）、鉤の速さ（m/s）。
    private static let launch: Float = 0.33
    private static let hookSpeed: Float = 15.15
    /// 命中から引き寄せが始まるまで（hookHold）、引き寄せの所要（hookPull）、命中から動けない時間の合計（hookStun + hookLandStun）。
    private static let holdTime: Float = 0.45
    private static let pullTime: Float = 0.25
    private static let stunTotal: Float = 1.3
    /// 鎖の 1 本の長さ（秒）と本数（4 本 = 0.56 秒 ≧ 最大の飛行 8.23m / 15.15m/s ≈ 0.54 秒）。
    private static let chainPiece: Float = 0.14
    /// スキル2: 叩きつけの時刻（shockDelay。モーションの振り下ろし = sim のダメージ）。
    private static let slam: Float = 0.27
    /// アルティメット: 掴みかかり（ultDelay）、拘束（ultSuppress）、連撃の間隔（ultInterval）。
    private static let grab: Float = 0.25
    private static let suppress: Float = 1.8
    private static let strikeGap: Float = 0.32

    // MARK: - 部品

    /// 炎の舌（円周から上へ立ちのぼる）。
    private static func flames(_ n: Int, radius: Float) -> FXEmit {
        FXEmit(tex: .flame, tint: .core, tintEnd: .secondary, count: n, emit: 0.1, life: 0.5, size: 0.4, sizeVar: 0.4,
               grow: 0.6, shape: .ring(radius), surface: true, dir: .up, speed: 2.4, speedVar: 0.4, orient: .upright,
               fade: .gradualFadeInOut)
    }

    /// 地から突き上がる鉄の鉤（尖塔）。
    private static func hook(_ h: Float, life: Float) -> FXMesh {
        FXMesh(shape: .spire, tex: .shard, tint: .accent, alpha: 0.95, size: [0.45, 0.1, 0.45], sizeEnd: [0.35, h, 0.35],
               ease: .outBack, life: life, fadeIn: 0.02, fadeOut: 0.75)
    }

    /// 手元から鉤まで伸びる鎖の k 本目（travel。鉤に追従）。鉤は hookSpeed（m/s）なので、本の始まりの時刻 t0 の長さ 0.3 + v·t0 から
    /// chainPiece 秒で v·chainPiece だけ伸び、中心は毎秒 v/2 後ろへ退く = 前端は鉤（+0.15）、後端は手元に留まる。
    private static func chain(_ k: Int, width: Float, _ tint: FXTint, tex: FXTex = .chain, alpha: Float = 1,
                              y: Float) -> FXCue {
        let t0 = chainPiece * Float(k)
        let l0 = 0.3 + hookSpeed * t0
        let l1 = 0.3 + hookSpeed * (t0 + chainPiece)
        let m = FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [l0, 1, width], sizeEnd: [l1, 1, width],
                       ease: .linear, life: chainPiece, fadeIn: 0.01, fadeOut: 0.99, yaw: 90, advance: -hookSpeed / 2)
        return .mesh(m, at: t0, .follow, offset: [0, y, 0.15 - l0 / 2])
    }

    /// 引き寄せの間に被弾者から手元へ張る鎖（hit。被弾者に追従）。命中から holdTime 秒（その場で張られている間）は長さのまま、
    /// 引き寄せ（pullTime）の間に被弾者側の端を保ったまま length → 0.6m に縮む。
    private static func pullChain(_ length: Float, width: Float, _ tint: FXTint, tex: FXTex, alpha: Float = 1,
                                  y: Float) -> [FXCue] {
        let hold = FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [length, 1, width],
                          sizeEnd: [length, 1, width], ease: .linear, life: holdTime + 0.02, fadeIn: 0.05, fadeOut: 0.95,
                          yaw: 90)
        let life = pullTime + 0.02
        let m = FXMesh(shape: .disc, tex: tex, tint: tint, alpha: alpha, size: [length, 1, width], sizeEnd: [0.6, 1, width],
                       ease: .linear, life: life, fadeIn: 0.01, fadeOut: 0.7, yaw: 90, advance: (length - 0.6) / 2 / life)
        return [.mesh(hold, .follow, offset: [0, y, -length / 2]),
                .mesh(m, at: holdTime, .follow, offset: [0, y, -length / 2])]
    }

    /// 縛る鎖（対象を通る 1 本。拘束の間 残る）。
    private static func bindChain(_ length: Float) -> FXMesh {
        FXMesh(shape: .disc, tex: .chain, tint: .accent, alpha: 1, size: [length * 0.8, 1, 0.5], sizeEnd: [length, 1, 0.5],
               ease: .out, life: suppress, fadeIn: 0.03, fadeOut: 0.85, yaw: 90)
    }

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        switch slot {
        case .passive:
            // 闘気がたまるたび（毎秒）: 鉤の手の橙の閃き・足元の薄い炎の輪（1.1 秒。重なって燃えたぎる）・火の粉
            r.cast = [
                .emit(.flare(0.8, .primary, life: 0.14, tex: .flare4), .follow, offset: [0.4, 1.0, 0.3]),
                .mesh(.halo(0.85, .primary, life: 1.1, spin: 160, tex: .ringDouble, alpha: 0.45), .follow, offset: [0, 0.15, 0]),
                .emit(.embers(8, radius: 0.5, .primary, life: 1.0), .follow, offset: [0, 0.3, 0]),
            ]
            r.hit = []
        case .skill1:
            r = hookRecipe(s)
        case .skill2:
            r = shockRecipe(s)
        case .ultimate:
            r = huntRecipe(s)
        }
        return r
    }

    // MARK: - スキル1 鎖鉤

    private static func hookRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        // 体をひねって鎖を回し（振りかぶり 0.33 秒）、投げ放つ: 回る鎖の輪・腕の弧・手元の橙の閃き・前へ散る火花
        r.cast = [
            .mesh(.halo(0.7, .accent, life: launch, spin: 540, tex: .ringDouble, alpha: 0.7), .follow, offset: [0, 1.3, 0]),
            .mesh(.slash(0.9, .accent, from: 100, to: -40, life: 0.18, tex: .slashThin), at: launch - 0.12,
                  offset: [0, 1.2, 0.2]),
            .emit(.flare(1.0, .primary, life: 0.12), at: launch, offset: [0.35, 1.1, 0.6]),
            .emit(.sparks(8, speed: 4, .core, end: .primary).with { $0.dir = .forward; $0.spread = 30 }, at: launch,
                  offset: [0.35, 1.1, 0.6]),
        ]
        // 飛ぶ鉤（前方 = 進行方向）: 鋼の三日月の鉤（凸が前、爪が後ろ）・橙の光の芯・手元から伸びる鎖 4 本・後ろに残る光の筋
        r.travel = [
            .mesh(FXMesh(shape: .disc, tex: .moon, tint: .accent, alpha: 1, size: [0.9, 1, 0.9], sizeEnd: [0.9, 1, 0.9],
                         ease: .linear, life: 0.6, fadeIn: 0.02, fadeOut: 0.8, yaw: -90), .follow, offset: [0, 1.05, 0.15]),
            .mesh(.orb(0.22, .primary, life: 0.6, grow: 1.0, alpha: 0.9).with { $0.fadeOut = 0.8 }, .follow,
                  offset: [0, 1.05, 0.1]),
            chain(0, width: 0.5, .accent, y: 1.0),
            chain(1, width: 0.5, .accent, y: 1.0),
            chain(2, width: 0.5, .accent, y: 1.0),
            chain(3, width: 0.5, .accent, y: 1.0),
            .emit(.trail(.glow, .primary, rate: 110, life: 0.32, size: 0.3).with { $0.speed = 0; $0.tintEnd = .secondary },
                  .follow, offset: [0, 0.95, 0]),
            .emit(.trail(.streak, .core, rate: 40, life: 0.2, size: 0.15).with {
                $0.stretch = 2.5; $0.dir = .backward; $0.speed = 3; $0.tintEnd = .primary
            }, .follow, offset: [0, 1.05, 0], quality: 1),
        ]
        // 鉤が食い込む点: 閃光・鉤の爪痕・小さな輪・手元へ（引く向きへ）散る火花
        r.impact = [
            .emit(.flare(1.6, .core, life: 0.16, tex: .flare6), offset: [0, 1.0, 0]),
            .mesh(.decal(.claw, 1.4, .secondary, life: 0.5, spin: 0, alpha: 0.85), offset: [0, 0.02, 0]),
            .mesh(.shockRing(1.0, .primary, life: 0.25)),
            .emit(.sparks(14, speed: 6, .core, end: .primary).with { $0.dir = .backward; $0.spread = 50 }, offset: [0, 1.0, 0]),
            .shake(0.15),
        ]
        // 被弾者（その場 0.45 秒 → 引き寄せ 0.25 秒 → 着地のスタン 0.6 秒）: 張られてから縮む鎖（鋼 + 橙の光）・引き寄せの間に
        // 手元へ流れる光条・術者の手元の閃き（引き寄せの始まり）・スタンの間（1.3 秒）巻きつく鎖の輪
        var hit = pullChain(3.2, width: 0.5, .accent, tex: .chain, y: 1.0)
        hit += pullChain(3.2, width: 0.9, .primary, tex: .streak, alpha: 0.8, y: 0.95)
        let streaks = FXEmit(tex: .streak, tint: .primary, tintEnd: .core, count: 14, emit: pullTime, life: 0.3, size: 0.12,
                             sizeVar: 0.3, grow: 0.5, shape: .sphere(0.2), dir: .backward, speed: 14, speedVar: 0.15,
                             spread: 6, stretch: 2.4, fade: .linearFadeOut)
        hit += [
            .emit(streaks, at: holdTime, offset: [0, 1.0, 0]),
            .emit(.flare(1.1, .primary, life: 0.16), at: holdTime + 0.02, .along(0), offset: [0, 1.1, 0.4]),
            .mesh(.halo(0.55, .accent, life: stunTotal, spin: 220, tex: .ringDouble), .follow, offset: [0, 0.9, 0]),
            .mesh(.halo(0.45, .primary, life: stunTotal, spin: -160, tex: .ring, alpha: 0.7), .follow, offset: [0, 0.4, 0]),
            .emit(.sparks(8, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
        ]
        r.hit = hit
        return r
    }

    // MARK: - スキル2 鉄鎖旋

    /// 斧鉤を地に叩きつける（0.27 秒）。R = 範囲の半径（2.57m）。
    private static func shockRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 3.0)
        let S = slam
        // 振り上げた斧鉤に熱が集まる（振りかぶりの 0.27 秒）
        r.cast = [
            .emit(.gather(14, radius: 0.8, .primary, life: S), offset: [0.3, 1.8, 0.3]),
            .emit(.flare(1.0, .primary, life: 0.1, tex: .flare4), at: S - 0.1, offset: [0.3, 1.9, 0.2]),
        ]
        // 自己中心なので発動と同時に再生される（叩きつけは S 秒後）
        r.impact = [
            .emit(.flare(2.4, .core, life: 0.2, tex: .flare6), at: S, offset: [0, 0.6, 0.5]),
            // 暗い地割れと、橙に燃える地割れ
            .mesh(.decal(.crack, R * 2.0, .dark, life: 1.6, spin: 0, grow: 1.0, alpha: 0.9), at: S),
            .mesh(.decal(.crack, R * 1.6, .primary, life: 0.8, spin: 0, grow: 1.06, alpha: 0.95), at: S, offset: [0, 0, 0.1]),
            // 6 方向へ走る炎の亀裂（中心から縁まで）
            .mesh(.ray(.bolt, length: R * 0.85, width: 0.7, .primary, life: 0.5), at: S, offset: [0, 0.02, 0])
                .ringed(6, radius: R * 0.45, every: 0.01),
            .mesh(.shockRing(R, .primary, life: 0.4), at: S),
            .mesh(.burstWall(R * 0.75, height: 1.3, .secondary, life: 0.45), at: S + 0.02),
            .emit(.groundGlow(R * 0.8, .primary, life: 0.5), at: S, offset: [0, 0.05, 0]),
            // 立ちのぼる炎の舌・跳ね上がる岩片・土煙・残り火
            .emit(flames(18, radius: R * 0.55), at: S),
            .emit(.debris(16, speed: 7, dust), at: S, offset: [0, 0.1, 0]),
            .emit(.smoke(8, radius: R * 0.5, dust, life: 1.1, size: 1.0), at: S + 0.03, quality: 1),
            .emit(.embers(14, radius: R * 0.7, .primary, life: 1.2), at: S + 0.05, quality: 1),
            .shake(0.35, at: S),
        ]
        // 被弾者（sim のダメージ = 叩きつけの時刻に再生）: 閃光・火花・足元の燃える枷（70% 鈍足 1.5 秒）
        r.hit = [
            .emit(.flare(1.0, .core, life: 0.14), offset: [0, 1.0, 0]),
            .mesh(.halo(0.6, .secondary, life: 1.5, spin: 120, tex: .ringDouble, alpha: 0.8), .follow,
                  offset: [0, 0.15, 0]),
            .emit(.sparks(8, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
        ]
        return r
    }

    // MARK: - アルティメット 狩猟鎖獄

    /// 対象へ 0.25 秒で掴みかかり、鎖で縛って 1.8 秒の間に 6 回叩き伏せる（掴んだ瞬間から 0.32 秒おき）。impact は対象の位置
    /// （発動時）で再生される = 時刻は発動から。R = 対象の輪（1.5m）。
    private static func huntRecipe(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 1.8)
        let G = grab
        let gap = strikeGap
        r.cast = [
            // 吼えて掴みかかる（0.25 秒）: 鉤の手の閃き・蹴った土煙・足元の輪
            .emit(.flare(1.4, .primary, life: 0.16, tex: .flare6), offset: [0.35, 1.3, 0.4]),
            .emit(.smoke(6, radius: 0.5, dust, life: 0.7, size: 0.7).with { $0.dir = .backward; $0.speed = 2 },
                  offset: [0, 0.2, 0], quality: 1),
            .mesh(.shockRing(1.2, .secondary, life: G)),
            // 鎖が対象へ伸びる（術者 → 対象の中間。鋼の鎖 + 橙の光。掴むまで）
            .mesh(.ray(.chain, length: 2.0, width: 0.55, .accent, life: G + 0.05), .along(0.5), offset: [0, 1.0, 0]),
            .mesh(.ray(.streak, length: 2.0, width: 1.0, .primary, life: G + 0.05, alpha: 0.8), .along(0.5), offset: [0, 0.95, 0]),
        ]
        r.impact = [
            .emit(.flare(2.2, .core, life: 0.2, tex: .flare6), at: G, offset: [0, 1.0, 0]),
            // 縛り上げる: X 字に交差する鎖 4 本・地から突き上がる鉄の鉤 4 本・巻きつく鎖の輪・足元の熾火の輪・煤けた地割れ（拘束の 1.8 秒）
            .mesh(bindChain(2.8), at: G + 0.02, offset: [0, 0.7, 0]).repeated(4, every: 0.03, yaw: 45),
            .mesh(hook(1.6, life: 1.4), at: G + 0.04).ringed(4, radius: R * 0.75, every: 0.03),
            .mesh(.halo(0.6, .accent, life: suppress, spin: 220, tex: .ringDouble).with { $0.fadeOut = 0.85 }, at: G,
                  offset: [0, 1.1, 0]),
            .mesh(.halo(0.9, .secondary, life: suppress, spin: -90, tex: .ring, alpha: 0.7).with { $0.fadeOut = 0.85 }, at: G,
                  offset: [0, 0.1, 0]),
            .mesh(.decal(.crack, R * 2.4, .dark, life: 2.0, spin: 0, grow: 1.0, alpha: 0.85), at: G),
            .emit(.embers(16, radius: 0.7, .primary, life: 1.5), at: G + 0.05, quality: 1),
            // 1〜5 撃（0.25 / 0.57 / 0.89 / 1.21 / 1.53 秒）: 左右交互に振り下ろす三日月
            .mesh(.slash(1.2, .primary, from: 80, to: -80, tilt: 35, life: 0.22), at: G, offset: [0, 1.1, -0.2])
                .repeated(3, every: gap * 2),
            .mesh(.slash(1.2, .core, from: -80, to: 80, tilt: -35, life: 0.22, tex: .slashThin), at: G + gap,
                  offset: [0, 1.1, -0.2]).repeated(2, every: gap * 2),
            // 6 撃目（1.85 秒）: 頭上から叩き伏せる大きな一撃・炎の噴出・岩片
            .mesh(.slash(1.6, .core, from: 80, to: -80, tilt: 90, life: 0.28), at: G + gap * 5, offset: [0, 1.2, -0.2]),
            .mesh(.shockRing(R * 1.6, .primary, life: 0.4), at: G + gap * 5 + 0.02),
            .emit(.flare(2.6, .core, life: 0.24, tex: .flare6), at: G + gap * 5, offset: [0, 1.0, 0]),
            .emit(.debris(14, speed: 7, dust), at: G + gap * 5 + 0.02),
            .emit(flames(14, radius: 0.8), at: G + gap * 5 + 0.02),
            .shake(0.45, at: G + gap * 5 + 0.02),
        ]
        // 6 回の 1 撃ごと（sim の時刻どおり）: 短い閃光・血の火花・小さな揺れ
        r.hit = [
            .emit(.flare(1.1, .core, life: 0.12), offset: [0, 1.1, 0]),
            .emit(.sparks(10, speed: 6, blood, end: .secondary, gravity: 9), offset: [0, 1.0, 0]),
            .shake(0.1),
        ]
        r.hitPerHit = true
        return r
    }

    // MARK: - パッシブの解放

    /// 闘気を使い切った（スキルのダメージが当たって消費したのが、発動から 0.6 秒以内）ときの合図。released は消費した闘気の数（1...10）で、
    /// 大きさに比例する。
    static func passiveRelease(_ s: FXSkillInfo, released: Int) -> [FXCue]? {
        let k = Float(min(max(released, 1), 10)) / 10
        return [
            .emit(.flare(0.9 + 1.5 * k, .core, life: 0.2, tex: .flare6), .follow, offset: [0.35, 1.1, 0.3]),
            .mesh(.shockRing(0.8 + 1.0 * k, .primary, life: 0.35), .follow),
            .mesh(.ray(.chain, length: 1.6 + 1.6 * k, width: 0.45, .accent, life: 0.35), .follow, offset: [0, 1.0, 0])
                .repeated(3, every: 0.02, yaw: 60),
            .emit(flames(6 + Int(10 * k), radius: 0.5), .follow),
            .emit(.sparks(8 + Int(12 * k), speed: 5 + 3 * k, .core, end: .primary), .follow, offset: [0, 1.0, 0]),
        ]
    }

    // MARK: - 詠唱モーション

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 体をひねって鎖鉤を振りかぶり、0.33 秒で投げ放って構え直す（引き寄せは命中の 0.45 秒後で、モーションの後）
            m.chamber(0.14)
            m.hold(0.08) { $0.glow = 1.2; $0.torsoYaw = 0.5 }
            m.throwCast(0.14)    // 振り出し 0.22〜0.30 秒・投げ放ち 0.30〜0.36 秒（sim の鉤は 0.33 秒）
            m.hold(0.16) { $0.glow = 1.4 }
            m.chamber(0.12)
            m.hold(0.08)
        case .skill2:
            // 腰を落とし、斧鉤を頭上へ振り上げて地へ叩きつける（0.27 秒）
            m.brace(0.06, depth: 0.1)
            m.overhead(0.15)
            m.smash(0.06)
            m.hold(0.14) { $0.glow = 2.0; $0.hipsDrop = 0.2 }
            m.settle(0.14)
        case .ultimate:
            // 掴みかかって鎖で縛り、左右交互に叩き伏せる（撃は 0.25 秒から 0.32 秒おき。奥義のモーションの上限 1.7 秒に収めるため
            // 振りかぶりを短くし、5〜6 撃目は戻りの間に演出だけで見せる）
            m.brace(0.06, depth: 0.14)
            m.overhead(0.08)
            m.smash(0.06)
            m.overhead(0.14)
            m.smash(0.12)
            m.windup(0.14, side: 1, power: 1.1)
            m.slash(0.12, side: 1, power: 1.2)
            m.overhead(0.14)
            m.smash(0.12)
            m.windup(0.14, side: -1, power: 1.1)
            m.slash(0.12, side: -1, power: 1.2)
            m.settle(0.08)
        }
    }
}
