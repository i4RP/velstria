import Foundation
import VelstriaCore

// スキル演出: H026 紫電のエウリア（Arcanist / 細身の杖・周囲に浮く小さな雷球。MLBB の Eudora の Velstria 版）。
// 主題: 紫の稲妻。電光の白い芯 × 紫（主）× 水色の電光（副）× 淡い藤色（差し色）× 黒に近い夜（暗）。円い光の床ではなく、
// 「扇へ枝分かれして走る稲妻」「術者と敵を結ぶ雷の鎖」「稲光をまとう雷球」「天から落ちる縦の大雷と地を這う稲光」で形を見せる。
// 縦の稲妻は、円盤を横倒しにした板 2 枚を直交させる（どの向きから見ても読める）か、カメラを向く粒を 90° 回して描く。
// sim の実際の挙動（Systems/Kits/Kit_H026.swift の EuriaTuning）に合わせたタイミング:
//   パッシブ 超伝導          — 印そのものの合図はバッジを持たないので試合中は出ない（cast は目視確認の実演用）。
//                              アルティメットが超伝導の敵に当たると、その敵に追従するゾーン（半径 1.9m・0.5 秒後）が雷の炸裂を起こす。
//                              ゾーンの演出 ID がこのパッシブなので、この枠の telegraph = 0.5 秒の収束（足元の陣が絞られ、頭上で三度瞬く）、
//                              impact = 炸裂（縦の雷・地を這う 4 本の稲光・光るひび）
//   スキル1 分岐雷          — 前方の扇（射程 6.5m・半角 30°）へ即時（cast と impact を発動と同時に再生）。0.05 秒に中央の太い稲妻から
//                              ±13° / ±26° へ枝分かれして走り、枝の先がさらに分かれ、0.15 秒まで向きを変えて瞬き直す。
//                              被弾 1 回ごと（扇の初撃・雷の鎖の継続ダメージ 0.2 秒おき 4 回・1 秒後の終わりの一撃。hitPerHit）に、
//                              術者 → 被弾者の線上へ稲妻の筋を連ねて「雷の鎖」を描く（.along。画質 1 以上）
//   スキル2 雷球            — 対象を追う雷球（18 m/s。追尾弾は向きが決まらないので形は丸いものだけ）が稲光をまとって飛び、
//                              当たって弾ける（縦の雷・6 本の放射の稲光・焦げたひび）。当たった敵ごと（印済みなら周囲 2.6m にも広がる）に
//                              スタン 1 秒の電光のちらつきと頭上の輪、魔防ダウン 1.8 秒の足元の割れた六角の盾
//   アルティメット 九天雷鳴 — 0.2 秒: 杖を掲げて天へ稲妻を昇らせる。予告 0.8 秒（telegraph）: 地面が嵐の影に沈み、外側の陣（半径 3m）と
//                              中心の陣（半径 1.5m）が回り、陣の中を地を這う稲光が二度走る。0.8 秒（impact）: 中心へ縦の大雷（太細 2 組）と
//                              光の柱、外側の輪の上に 0.3 秒かけて雷の筋が降り、中心から外縁へ地を這う 5 本の稲光、焼け跡と光るひび
// SkillFXDirector は duration / count を読まない: 時刻は at（遅れ）で表す。

enum FX_H026: HeroFXSet {
    static let palette = FXPalette(core: RGB(0.97, 0.95, 1.0), primary: RGB(0.6, 0.32, 1.0),
                                   secondary: RGB(0.5, 0.85, 1.0), accent: RGB(0.88, 0.7, 1.0),
                                   dark: RGB(0.05, 0.02, 0.1))

    // MARK: - sim の時刻・寸法（Kit_H026.EuriaTuning と同じ値。sim を変えたらここも合わせる）

    /// 雷の炸裂の遅れ（burstDelay）・半径（burstRadius 190）。
    private static let burstDelay: Float = 0.5
    private static let burstRadius: Float = 1.9
    /// アルティメット: 予告（ultDelay）・中心の半径（ultCenterRadius 150）。
    private static let ultDelay: Float = 0.8
    private static let ultCenter: Float = 1.5
    /// スキル2: スタン・魔防ダウンの長さ。
    private static let stunTime: Float = 1.0
    private static let shredTime: Float = 1.8

    /// 杖の先（局所座標）。
    private static let tip: SIMD3<Float> = [0.2, 1.5, 0.8]
    /// 稲妻の枝の根元（杖の先のすこし手前）。
    private static let root: SIMD3<Float> = [0.2, 1.3, 0.8]

    // MARK: - 部品

    /// 地を這う・宙を走る稲妻の枝（pivot から angle 度（+ = 左）の向きへ length m）。flip で模様の向きを逆にする（瞬き直し）。
    private static func branch(_ angle: Float, length: Float, _ tint: FXTint, at t: Float = 0,
                               from pivot: SIMD3<Float>, life: Float = 0.26, width: Float = 0.8,
                               flip: Bool = false) -> FXCue {
        let a = angle * .pi / 180
        let d = length / 2
        let mid = pivot + SIMD3<Float>(-sin(a) * d, 0, cos(a) * d)
        let m = FXMesh.ray(.bolt, length: length, width: width, tint, life: life).with {
            $0.yaw = (flip ? 270 : 90) + angle
        }
        return .mesh(m, at: t, offset: mid)
    }

    /// 縦の稲妻（円盤を横倒しにした板。稲妻の模様が上下に走る）。中心が原点。repeated(2, yaw: 90) で直交の 2 枚にする。
    private static func bolt(height: Float, width: Float, _ tint: FXTint, life: Float, alpha: Float = 1) -> FXMesh {
        FXMesh(shape: .disc, tex: .bolt, tint: tint, alpha: alpha, size: [height, 1, width * 0.6],
               sizeEnd: [height, 1, width], ease: .out, life: life, fadeIn: 0.02, fadeOut: 0.35, yaw: 45, roll: 90)
    }

    /// 縦の稲光の粒（カメラを向く板を 90° 回して、稲妻の模様を上下にする）。
    private static func boltFlash(_ size: Float, _ tint: FXTint, count: Int = 1, life: Float = 0.18) -> FXEmit {
        FXEmit(tex: .bolt, tint: tint, tintEnd: .primary, count: count, life: life, lifeVar: 0.2, size: size,
               sizeVar: 0.15, grow: 1.0, angle: 90, angleVar: 12, fade: .linearFadeOut)
    }

    /// 雷球の電光（小さな玉のまわりに電弧が走る）。
    private static func spark(_ n: Int, radius: Float, speed: Float = 3) -> FXEmit {
        FXEmit.sparks(n, speed: speed, .core, end: .primary, size: 0.1, life: 0.3, gravity: 0).with {
            $0.shape = .sphere(radius)
        }
    }

    /// n 本の放射（半径 r の輪に並べて外向きに向ける）。start = 1 本目の向き（度、+ = 左）。
    private static func radial(_ m: FXMesh, _ n: Int, radius r: Float, start: Float = 0, at t: Float = 0,
                               height: Float = 0.12, quality: Int = 0) -> FXCue {
        let a = start * .pi / 180
        var c = FXCue.mesh(m.with { $0.yaw += start }, at: t, offset: [-sin(a) * r, height, cos(a) * r],
                           quality: quality)
        c.count = n
        c.stepYaw = 360 / Float(max(1, n))
        c.orbit = 0.0001
        return c
    }

    /// 小さな光（スキルのダメージが出ない段を既定の演出で補わせないための詰め物）。
    private static func glint(_ tint: FXTint) -> [FXCue] {
        [.emit(.flare(0.6, tint, life: 0.12), offset: [0, 1.0, 0])]
    }

    // MARK: - レシピ

    static func recipe(_ slot: SkillSlot, _ s: FXSkillInfo) -> SkillFXRecipe {
        switch slot {
        case .passive:
            return superconductor()
        case .skill1:
            return forkedLightning(s)
        case .skill2:
            return ballLightning()
        case .ultimate:
            return thundersWrath(s)
        }
    }

    // MARK: - パッシブ 超伝導（と雷の炸裂）

    private static func superconductor() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let B = burstRadius
        // 実演用の合図: 身の周りの雷球が弾けて縦の稲光が走り、紫の電弧の輪が巡る
        r.cast = [
            .emit(spark(12, radius: 0.6, speed: 2.5), .follow, offset: [0, 1.2, 0]),
            .emit(boltFlash(1.4, .secondary, count: 2), .follow, offset: [0, 1.2, 0]),
            .mesh(.halo(0.7, .primary, life: 0.6, spin: 480, tex: .ring), .follow, offset: [0, 1.0, 0]),
            .emit(.flare(0.9, .accent, life: 0.14), .follow, offset: [0, 1.6, 0]),
        ]
        // 雷の炸裂の予告（0.5 秒。超伝導の敵の位置が原点）: 足元の雷の陣が絞られ、電光が集まり、頭上で稲光が三度瞬く
        r.telegraph = [
            .mesh(FXMesh(shape: .disc, tex: .techCircle, tint: .secondary, alpha: 0.85, size: [B * 2, 1, B * 2],
                         sizeEnd: [1.2, 1, 1.2], ease: .in, life: burstDelay, fadeIn: 0.15, fadeOut: 0.85, spin: -300)),
            .emit(.gather(14, radius: 1.6, .secondary, life: burstDelay - 0.05), offset: [0, 0.8, 0]),
            .emit(boltFlash(1.0, .accent), offset: [0, 2.0, 0]).repeated(3, every: 0.16),
        ]
        // 炸裂: 縦の雷が敵へ落ち、地を這う 4 本の稲光と光るひびが半径 1.9m に走る
        r.impact = [
            .mesh(bolt(height: 7, width: 1.3, .core, life: 0.24), offset: [0, 3.5, 0]).repeated(2, yaw: 90),
            .emit(.flare(2.2, .core, life: 0.2, tex: .flare6), offset: [0, 0.9, 0]),
            .mesh(.shockRing(B, .secondary, life: 0.35, tex: .ring)),
            radial(FXMesh.ray(.bolt, length: B, width: 0.8, .primary, life: 0.25), 4, radius: B * 0.5, start: 45, at: 0.02),
            .mesh(.decal(.crack, B * 1.4, .secondary, life: 0.6, spin: 0, grow: 1.0, alpha: 0.8)),
            .emit(.sparks(18, speed: 8, .core, end: .primary, life: 0.35), offset: [0, 0.8, 0]),
            .shake(0.2),
        ]
        // 炸裂のダメージはアルティメット（skill(.ultimate)）として出るので、この枠の hit は再生されない
        r.hit = glint(.secondary)
        return r
    }

    // MARK: - スキル1 分岐雷

    /// 扇（射程 6.5m・半角 30°）へ即時に枝分かれする稲妻。被弾ごとに雷の鎖の筋（hitPerHit）。
    private static func forkedLightning(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let L = min(s.range, 7)
        let t: Float = 0.05
        let fork = root + SIMD3<Float>(0, 0, L * 0.45)
        let rim: SIMD3<Float> = [0, 0.9, L * 0.85]
        r.cast = [
            .emit(spark(10, radius: 0.25, speed: 2.5), offset: tip),
            .emit(.flare(1.4, .core, life: 0.14, tex: .flare6), at: t, offset: tip),
        ]
        r.impact = [
            // 中央の太い稲妻から左右へ枝分かれして走る
            branch(0, length: L, .core, at: t, from: root, life: 0.3, width: 1.1),
            branch(13, length: L * 0.88, .secondary, at: t + 0.02, from: root, width: 0.9),
            branch(-13, length: L * 0.88, .secondary, at: t + 0.02, from: root, width: 0.9),
            branch(26, length: L * 0.74, .primary, at: t + 0.04, from: root, width: 0.8),
            branch(-26, length: L * 0.74, .primary, at: t + 0.04, from: root, width: 0.8),
            // 中央の枝の中ほどから、さらに外へ分かれる
            branch(40, length: 2.0, .accent, at: t + 0.06, from: fork, life: 0.22, width: 0.6),
            branch(-40, length: 2.0, .accent, at: t + 0.06, from: fork, life: 0.22, width: 0.6),
            // ちらつき: 中央と左右の枝が逆の向きの模様で瞬き直す
            branch(4, length: L * 0.95, .secondary, at: t + 0.1, from: root, life: 0.18, width: 0.9, flip: true),
            branch(-18, length: L * 0.8, .core, at: t + 0.12, from: root, life: 0.16, width: 0.7, flip: true),
            branch(18, length: L * 0.8, .core, at: t + 0.14, from: root, life: 0.16, width: 0.7, flip: true),
            // 扇へ散る電光の粒・中央の筋に沿って弾ける光・扇の先で弾ける電光
            .emit(.fan(24, .primary, speed: 16, spread: 30, life: 0.32), at: t, offset: tip),
            .emit(.lineBurst(L * 0.45, count: 12, .secondary, life: 0.4, size: 0.2), at: t + 0.04,
                  offset: [0, 0.2, L * 0.5]),
            .emit(.sparks(14, speed: 5, .core, end: .secondary, size: 0.09, life: 0.3, gravity: 0).with {
                $0.shape = .box([L * 0.5, 0.3, 0.6])
            }, at: t + 0.06, offset: rim),
        ]
        // 被弾 1 回ごと（扇の初撃・鎖の継続ダメージ 4 回・終わりの一撃）: 術者 → 被弾者の線上（.along(0) = 術者、1 = 被弾者）に
        // 稲妻の筋を 4 本連ねて雷の鎖にし、被弾者の体を縦の稲光が走る。多くの敵に当たる扇の初撃もあるので、鎖の筋は画質 1 以上だけ
        r.hit = [
            .emit(boltFlash(1.4, .secondary), offset: [0, 1.1, 0]),
            .mesh(FXMesh.ray(.bolt, length: 2.2, width: 0.7, .core, life: 0.15).with { $0.yaw = 96 }, .along(0.15),
                  offset: [0, 1.25, 0], quality: 1),
            .mesh(FXMesh.ray(.bolt, length: 2.2, width: 0.7, .secondary, life: 0.15).with { $0.yaw = 84 }, at: 0.02,
                  .along(0.38), offset: [0, 1.2, 0], quality: 1),
            .mesh(FXMesh.ray(.bolt, length: 2.2, width: 0.7, .core, life: 0.15).with { $0.yaw = 270 }, at: 0.03,
                  .along(0.62), offset: [0, 1.2, 0], quality: 1),
            .mesh(FXMesh.ray(.bolt, length: 2.0, width: 0.6, .secondary, life: 0.14).with { $0.yaw = 92 }, at: 0.04,
                  .along(0.85), offset: [0, 1.15, 0], quality: 1),
            .emit(.sparks(8, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
        ]
        r.hitPerHit = true
        return r
    }

    // MARK: - スキル2 雷球

    /// 対象を追う雷球 → 当たって弾ける。被弾者ごとにスタン 1 秒と魔防ダウン 1.8 秒。
    private static func ballLightning() -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let hand: SIMD3<Float> = [0.3, 1.45, 0.55]
        let ball: SIMD3<Float> = [0, 1.15, 0]
        r.cast = [
            .emit(.gather(12, radius: 0.5, .secondary, life: 0.1), offset: hand),
            .emit(.flare(1.3, .core, life: 0.14, tex: .flare6), at: 0.02, offset: hand),
            .emit(boltFlash(1.0, .secondary, count: 2, life: 0.14), at: 0.02, offset: hand),
        ]
        // 雷球（追尾弾は向きが決まらないので、丸い芯・殻・回る輪と、ばらばらの向きの稲光だけ）
        r.travel = [
            .mesh(.orb(0.26, .core, life: 0.5, grow: 1.0, alpha: 0.95).with { $0.fadeOut = 0.85 }, .follow, offset: ball),
            .mesh(.orb(0.48, .secondary, life: 0.5, grow: 1.0, alpha: 0.4).with { $0.fadeOut = 0.85 }, .follow, offset: ball),
            .mesh(.halo(0.55, .primary, life: 0.5, spin: 520, tex: .ringDouble).with {
                $0.size = [0.55, 1, 0.55]
                $0.fadeOut = 0.85
            }, .follow, offset: ball),
            .emit(.trail(.bolt, .core, rate: 45, life: 0.12, size: 1.0).with {
                $0.angleVar = 180
                $0.grow = 1
                $0.tintEnd = .secondary
            }, .follow, offset: ball),
            .emit(.trail(.glow, .primary, rate: 60, life: 0.25, size: 0.6), .follow, offset: ball),
        ]
        // 当たって弾ける: 白い閃光・膨らんで消える電光の球・縦の雷・6 本の放射の稲光・焦げたひび
        r.impact = [
            .emit(.flare(2.4, .core, life: 0.2, tex: .flare6), offset: [0, 1.1, 0]),
            .mesh(.orb(0.5, .secondary, life: 0.3, grow: 2.8, alpha: 0.55), offset: [0, 1.0, 0]),
            .mesh(bolt(height: 3.4, width: 1.0, .core, life: 0.2), offset: [0, 1.7, 0]).repeated(2, yaw: 90),
            radial(FXMesh.ray(.bolt, length: 2.2, width: 0.8, .secondary, life: 0.26), 6, radius: 1.2, at: 0.02),
            .mesh(.decal(.crack, 2.8, .primary, life: 0.7, spin: 0, grow: 1.0, alpha: 0.75)),
            .mesh(.shockRing(1.4, .secondary, life: 0.3, tex: .ring)),
            .emit(.sparks(18, speed: 7, .core, end: .primary), offset: [0, 1.0, 0]),
            .shake(0.12),
        ]
        // 被弾者ごと: スタン 1 秒（体に電光が 4 回ちらつき、頭上を輪が回る）と、魔防ダウン 1.8 秒（足元の割れた六角の盾）
        r.hit = [
            .mesh(.sprite(.bolt, 1.1, .secondary, life: 0.14, grow: 1.1), .follow, offset: [0, 1.2, 0])
                .repeated(4, every: stunTime / 4),
            .mesh(.halo(0.45, .accent, life: stunTime, spin: 420, tex: .ringDouble), .follow, offset: [0, 2.05, 0]),
            .mesh(.decal(.hexShield, 1.3, .primary, life: shredTime, spin: 30, alpha: 0.55), .follow),
            .emit(boltFlash(1.6, .core), offset: [0, 1.0, 0]),
            .emit(.sparks(8, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
        ]
        return r
    }

    // MARK: - アルティメット 九天雷鳴

    /// 杖を掲げて天へ稲妻（0.2）→ 予告 0.8 秒（嵐の影・二重の陣・地を這う稲光）→ 0.8 秒に縦の大雷と外側に降る雷。
    private static func thundersWrath(_ s: FXSkillInfo) -> SkillFXRecipe {
        var r = SkillFXRecipe()
        let R = min(s.radius, 3.2)
        let C = ultCenter
        let land = ultDelay
        let high: SIMD3<Float> = [0.25, 2.5, 0.3]
        let sky = high + SIMD3<Float>(0, 2.3, 0)
        r.cast = [
            .emit(.gather(22, radius: 1.2, .secondary, life: 0.3), offset: high),
            .emit(.flare(2.0, .core, life: 0.24, tex: .flare6), at: 0.2, offset: high),
            // 杖の先から天へ稲妻が昇る（雷を呼ぶ）
            .mesh(bolt(height: 4.5, width: 1.0, .secondary, life: 0.22), at: 0.22, offset: sky).repeated(2, yaw: 90),
            .mesh(.halo(0.9, .primary, life: 0.9, spin: 420, tex: .ringDouble), offset: [0, 0.2, 0]),
        ]
        // 予告（0.8 秒。中心が原点）: 地面が嵐の影に沈み、外側の陣（半径 3m）と中心の陣（半径 1.5m）が逆に回り、
        // 陣の中を地を這う稲光が 0.3 秒・0.55 秒に走る
        r.telegraph = [
            .mesh(FXMesh(shape: .disc, tex: .glow, tint: .dark, alpha: 0.6, size: [R * 1.6, 1, R * 1.6],
                         sizeEnd: [R * 2.4, 1, R * 2.4], ease: .out, life: land + 0.15, fadeIn: 0.2, fadeOut: 0.8)),
            .mesh(.decal(.runeCircle, R * 2, .primary, life: land + 0.05, spin: 60, grow: 1.0, alpha: 0.6)),
            .mesh(.decal(.techCircle, C * 2, .secondary, life: land + 0.05, spin: -150, grow: 1.0, alpha: 0.85)),
            radial(FXMesh.ray(.bolt, length: 2.2, width: 0.7, .secondary, life: 0.16), 3, radius: C + 0.3, at: 0.3),
            radial(FXMesh.ray(.bolt, length: 2.0, width: 0.6, .accent, life: 0.16), 3, radius: C - 0.1, start: 60,
                   at: 0.55, quality: 1),
            .emit(.rising(18, radius: R * 0.8, .secondary, speed: 2.0, life: 0.7)),
            .emit(.gather(20, radius: R, .accent, life: 0.45), at: 0.35, offset: [0, 0.5, 0]),
        ]
        // 0.8 秒: 中心へ縦の大雷（太細 2 組の直交の板）と光の柱、外側の輪の上に雷の筋が降り、中心から外縁へ地を這う稲光、焼け跡
        r.impact = [
            .emit(.flare(3.4, .core, life: 0.3, tex: .flare6), offset: [0, 1.0, 0]),
            .mesh(bolt(height: 10, width: 2.0, .core, life: 0.3), offset: [0, 5.0, 0]).repeated(2, yaw: 90),
            .mesh(bolt(height: 9, width: 1.3, .secondary, life: 0.26).with { $0.yaw = 0 }, at: 0.06,
                  offset: [0.3, 4.5, -0.2]).repeated(2, yaw: 90),
            .mesh(.pillar(0.9, height: 8, .accent, life: 0.35)),
            .emit(boltFlash(3.2, .secondary, count: 7, life: 0.2).with {
                $0.emit = 0.3
                $0.shape = .ring(R * 0.75)
                $0.surface = true
            }, at: 0.04, offset: [0, 1.6, 0]),
            radial(FXMesh.ray(.bolt, length: R * 0.95, width: 1.0, .secondary, life: 0.32), 5, radius: R * 0.5, start: 18,
                   at: 0.02),
            .mesh(.decal(.crack, R * 1.7, .dark, life: 1.6, spin: 0, grow: 1.0, alpha: 0.85)),
            .mesh(.decal(.crack, R * 1.3, .secondary, life: 0.8, spin: 0, grow: 1.05, alpha: 0.9), at: 0.02),
            .mesh(.shockRing(C, .core, life: 0.28, tex: .ring)),
            .mesh(.shockRing(R, .primary, life: 0.45)),
            .emit(.sparks(34, speed: 10, .core, end: .primary, life: 0.45), offset: [0, 0.8, 0]),
            .emit(.rising(20, radius: R * 0.8, .secondary, speed: 3, life: 0.8), at: 0.12, quality: 1),
            .emit(.smoke(10, radius: R * 0.5, life: 1.2, size: 1.0), at: 0.05, quality: 1),
            .shake(0.6),
        ]
        // 大雷・雷の炸裂を受けた敵: 縦の稲光が体を貫き、電光が二度ちらつく
        r.hit = [
            .emit(.flare(1.2, .core, life: 0.15), offset: [0, 1.1, 0]),
            .emit(boltFlash(2.4, .core), offset: [0, 1.3, 0]),
            .mesh(.sprite(.bolt, 1.1, .secondary, life: 0.16, grow: 1.1), .follow, offset: [0, 1.2, 0])
                .repeated(2, every: 0.12),
            .emit(.sparks(10, speed: 5, .core, end: .primary), offset: [0, 1.0, 0]),
        ]
        return r
    }

    // MARK: - 詠唱モーション

    static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder) {
        switch slot {
        case .passive:
            break
        case .skill1:
            // 杖の先へ雷を寄せ（0.05 秒）、両手を前へ突き出して扇へ放つ
            m.gather(0.05)
            m.push(0.05)
            m.hold(0.16) { $0.glow = 2.0 }
        case .skill2:
            // 手元に雷球を溜め、片手で投げ放つ（雷球は発動と同時に飛ぶ）
            m.gather(0.06)
            m.throwCast(0.12)
            m.hold(0.06) { $0.glow = 1.6 }
            m.settle(0.1)
        case .ultimate:
            // 杖を天へ掲げて雷を呼び（0.2 秒で天へ稲妻）、0.8 秒の落雷に合わせて杖を地へ突き立てる
            m.raise(0.16, glow: 2.0)
            m.hold(0.54) { $0.ring = 1.4; $0.glow = 2.6 }
            m.plant(0.08)
            m.hold(0.16) { $0.glow = 2.2 }
        }
    }
}
