import Foundation
import simd
import VelstriaCore

// 担当: battle-renderer（カメラ）。Star Core の終幕のカメラ（TowerTimeline の終幕の時刻表、docs/STAGE_REDESIGN.md の E）。
// Core が壊れた = 決着。両チーム・観戦者・リプレイ・オンラインの全員の画面で同じ流れを見せる:
//   0〜0.6 秒   ゲームカメラの向きのまま Core へ寄る（最初だけ小さく揺らす。HUD はこの間に消える）
//   0.6〜4.0 秒 聖域の階段の近くの低い位置へ切り替え、結晶を見上げながらゆっくり回り込む
//   4.0〜5.2 秒 引きの落ち着いた構図へ（Core を右寄せ、左を空ける）。5.2 秒で勝敗のバナー → リザルト
// 姿勢は「演出時刻 − Core の deathTime」の純関数（積み上げない）なので、一時停止・倍速・重複でも同じ画になる。
// 方位（どちらから撮るか）は地図の定義（Core・塔・泉・壁・草むら・参道のランタン）から決め、カメラが地図の外・壁・塔・
// 台座に入らず、塔や壁で Core が隠れない向きを選ぶ（ステージは南から北を見る前提で作られているので、北を向く撮り方を優先）。
// 引きの構図の左の空き（勝敗のバナーの場所）に近くの塔・泉が入る向きは避ける。決着の時刻のヒーローの位置（sim は止まるので
// 終幕の間は動かない）も見て、手前のヒーローで結晶が隠れにくい向きにする（全員の画面で同じ状態から決めるので同じ画になる）。
// 地図だけで決まる検査（候補 72 通り）は読み込み中に作り、決着の瞬間はヒーローの分の点数付けだけを行う。
// 視差を減らす設定（UIAccessibility.isReduceMotionEnabled）では寄り・回り込み・揺れをやめ、静止した画の切り替えだけにする。
// 決定論: sim は読むだけ。終幕の状態は SimState にもリプレイにも入らない。

/// カメラの姿勢（位置と向き。ロールなし）。
struct CameraPose: Equatable {
    var position: SIMD3<Float>
    /// 左へ向く角（world の y 軸まわり、ラジアン。0 = 北（-z）を向く）。
    var yaw: Float
    /// 見上げる角（ラジアン。負 = 見下ろす。ゲームカメラは -56°）。
    var pitch: Float

    var orientation: simd_quatf {
        simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    /// 視線の向き（カメラの -z）。
    var forward: SIMD3<Float> {
        SIMD3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }

    /// 向き d を見る yaw・pitch。
    static func angles(toward d: SIMD3<Float>) -> (yaw: Float, pitch: Float) {
        (atan2(-d.x, -d.z), atan2(d.y, simd_length(SIMD2(d.x, d.z))))
    }

    /// p から target を見る姿勢。
    static func looking(from p: SIMD3<Float>, at target: SIMD3<Float>) -> CameraPose {
        let a = angles(toward: target - p)
        return CameraPose(position: p, yaw: a.yaw, pitch: a.pitch)
    }

    /// p から見た target が画面の screen（正規化: x = -1 左 … 1 右、y = -1 下 … 1 上）に映る姿勢（ロールなし）。
    static func framing(_ target: SIMD3<Float>, at screen: SIMD2<Float>, from p: SIMD3<Float>, aspect: Float,
                        fovDegrees: Float = CameraRig.fovDegrees) -> CameraPose {
        let t = tan(fovDegrees * .pi / 360)
        // カメラから見た target の向き（カメラの座標）
        let local = simd_normalize(SIMD3(screen.x * t * aspect, screen.y * t, -1))
        let d = simd_normalize(target - p)
        // pitch: x 軸まわりの回転の後の高さの成分が d.y に一致する（local.y·cos p − local.z·sin p = d.y）
        let r = simd_length(SIMD2(local.y, local.z))
        let phase = atan2(local.y, -local.z)
        let pitch = asin(max(-1, min(1, d.y / max(1e-5, r)))) - phase
        // yaw: 水平の向きの差（yaw の回転は水平の向きの角に足される）
        let z = local.y * sin(pitch) + local.z * cos(pitch)
        let heading = { (x: Float, z: Float) in atan2(-x, -z) }
        let yaw = heading(d.x, d.z) - heading(local.x, z)
        return CameraPose(position: p, yaw: wrapAngle(yaw), pitch: pitch)
    }

    /// 世界の点が映る画面の位置（正規化: x = -1 左 … 1 右、y = -1 下 … 1 上）。カメラの後ろは nil。
    func screen(of p: SIMD3<Float>, aspect: Float, fovDegrees: Float = CameraRig.fovDegrees) -> SIMD2<Float>? {
        let local = orientation.inverse.act(p - position)
        guard local.z < -0.01 else { return nil }
        let t = tan(fovDegrees * .pi / 360)
        return SIMD2(local.x / (-local.z * t * aspect), local.y / (-local.z * t))
    }

    /// 2 つの姿勢の間（位置は直線、向きは角度で補間する: ロールが出ない）。
    static func mix(_ a: CameraPose, _ b: CameraPose, _ k: Float) -> CameraPose {
        CameraPose(position: a.position + (b.position - a.position) * k,
                   yaw: a.yaw + wrapAngle(b.yaw - a.yaw) * k, pitch: a.pitch + (b.pitch - a.pitch) * k)
    }

    static func wrapAngle(_ a: Float) -> Float {
        var x = a.truncatingRemainder(dividingBy: 2 * .pi)
        if x > .pi { x -= 2 * .pi }
        if x <= -.pi { x += 2 * .pi }
        return x
    }
}

/// 終幕の判定（描画・HUD が同じ規則を使う）。
enum CoreFinale {
    /// 試合を決めた（壊れた）Core のチームと壊れた時刻。Core の破壊で終わった試合だけ（降参・時間切れ・中断は nil）。
    static func destroyedCore(in s: SimState) -> (team: Team, deathTime: Double)? {
        guard s.phase == .ended, s.endReason == .coreDestroyed, let winner = s.winner else { return nil }
        let team = winner.opponent
        guard let u = s.units.first(where: { $0.kind == .core && $0.team == team && !$0.isAlive }) else { return nil }
        return (team, u.deathTime ?? s.time)
    }

    /// 終幕のきっかけ（Core の破壊で試合が終わった通知）。通知を受けずに終わった状態になった時（シーク・再同期・途中から
    /// 観戦）は終幕を流さず、カメラは引きの構図、HUD はバナーから始める。
    static func isTrigger(_ e: SimEvent) -> Bool {
        if case .matchEnded(_, .coreDestroyed) = e { return true }
        return false
    }

    /// 終幕の始まりから勝敗のバナーまでの残り（秒）。Core の破壊の通知を受けた時点の状態から求める。
    static func remainingUntilResult(_ s: SimState) -> Double? {
        guard let core = destroyedCore(in: s) else { return nil }
        return max(0, TowerTimeline.finaleResult - max(0, s.time - core.deathTime))
    }
}

/// Star Core の終幕の撮り方（1 試合 1 回、終幕の開始時に作る値型。pose(at:game:) が毎フレームの姿勢）。
struct CoreFinaleShot: Equatable {
    /// Core の中心（world。地面の高さ）。
    let core: SIMD3<Float>
    /// 引きの構図のカメラの方位（Core から見たカメラの水平の向き。0 = 南（+z）、π/2 = 東（+x））。
    let azimuth: Float
    /// 回り込みの向き（+1 = 方位が増える向きに回って azimuth に着く）。
    let sweep: Float
    let reducedMotion: Bool
    /// 画面の縦横比（引きの構図の右寄せに使う）。
    let aspect: Float

    // MARK: 寸法（Core の台座は直径約 7 m・高さ約 1.2 m、結晶は 3.6〜5 m に浮く）

    /// 寄りの終わり: ゲームカメラの向きのまま Core の中ほど（pushLook の高さ）をこの距離で見る。
    static let pushDistance: Float = 10
    static let pushLook: Float = 2.2
    /// 寄りの始めにゲームカメラの注視点が Core からこれより遠ければ、Core を中心にしたゲームカメラから寄る
    /// （地図を横切って流さない。画面の外で壊れた Core へ切り替わる）。
    static let pushCutDistance: Float = 18
    /// 低い視点: 半径（m）と高さ（回り込みの始め → 終わり）、見上げる点の高さ（結晶の下端と台座の両方を収める）。
    static let lowRadius: (start: Float, end: Float) = (7.8, 6.9)
    static let lowHeight: (start: Float, end: Float) = (1.8, 2.3)
    static let lowLook: Float = 3.0
    /// 回り込む角（0.6 秒の切り替えから引きの構図に着く 5.2 秒まで。大半は 4.0 秒までに回る）。
    static let orbitArc: Float = 50 * .pi / 180
    /// 引きの構図: 半径・高さ、構図の基準点（台座と結晶の間）の高さと画面の位置（右寄せ・中央よりやや下）。
    static let wideRadius: Float = 11.5
    static let wideHeight: Float = 8.6
    static let wideAnchor: Float = 2.6
    static let wideScreen = SIMD2<Float>(0.3, -0.06)
    /// 最初の揺れ（m）と長さ（秒）。
    static let shakeAmplitude: Float = 0.08
    static let shakeEnd: Double = 0.4
    /// カメラを置ける場所: 地図の縁・壁・草むらからの余白、塔・泉・ランタンからの距離、台座からの距離（m）。
    static let mapMargin: Float = 1.5
    static let wallMargin: Float = 1.5
    static let towerClearance: Float = 4.5
    static let fountainClearance: Float = 5
    static let lanternClearance: Float = 1.3
    static let platformClearance: Float = 6

    init(core: SIMD3<Float>, azimuth: Float, sweep: Float, reducedMotion: Bool, aspect: Float) {
        self.core = core
        self.azimuth = azimuth
        self.sweep = sweep
        self.reducedMotion = reducedMotion
        self.aspect = aspect.isFinite && aspect > 0.2 ? aspect : CameraRig.designAspect
    }

    /// 方位の候補（地図だけで決まる部分。読み込み中に作っておく: candidates）と決着の時刻のヒーローの位置（world x・z）から作る。
    init(team: Team, map: MapDefinition, candidates: [Candidate]? = nil, heroes: [SIMD2<Float>] = [], reducedMotion: Bool,
         aspect: Float) {
        let core = worldPosition(map.core(team))
        let list = candidates ?? CoreFinaleShot.candidates(core: core, map: map)
        let a = CoreFinaleShot.choose(from: list, core: core, heroes: heroes)
        self.init(core: core, azimuth: a.azimuth, sweep: a.sweep, reducedMotion: reducedMotion, aspect: aspect)
    }

    // MARK: 姿勢

    /// 終幕の t 秒目の姿勢。game = いまのゲームカメラ（揺れなし。寄りの起点）。t ≥ finaleSettleEnd は引きの構図で止まる。
    func pose(at t: Double, game: CameraPose) -> CameraPose {
        let push = TowerTimeline.finalePushEnd, orbitEnd = TowerTimeline.finaleOrbitEnd
        if reducedMotion {
            // 動きを減らす: 寄り・回り込み・揺れをせず、静止した画を切り替える
            if t < push { return game }
            if t < orbitEnd { return lowPose(azimuth: azimuth - sweep * CoreFinaleShot.orbitArc * 0.5, progress: 0.5) }
            return widePose
        }
        if t < push { return pushPose(at: t, game: game) }
        if t < orbitEnd { return orbitPose(at: t) }
        if t < TowerTimeline.finaleSettleEnd { return settlePose(at: t) }
        return widePose
    }

    /// 頭上のバー（ゲームカメラの向き専用の板）を隠すか: 低い視点に切り替える少し前から（バーの大きさは描画同期の中で
    /// 前のフレームの値で決まるので、切り替えの 1 フレーム目に傾いた板が映らないよう早めに隠す）。
    func hidesOverheadBars(at t: Double) -> Bool { t >= TowerTimeline.finalePushEnd - 0.1 }

    /// 影を描く範囲の中心（world x・z）と範囲の倍率（BattleRenderer.followSun）。p = いま描いている終幕の姿勢。
    func shadowFrame(for p: CameraPose) -> (center: SIMD2<Float>, scale: Float) {
        // Core の少し奥（視線の先）を中心に、引きの構図まで映る地面を広めに覆う
        let f = SIMD2(p.forward.x, p.forward.z)
        let n = simd_length(f) > 1e-3 ? simd_normalize(f) : SIMD2(0, -1)
        return (SIMD2(core.x, core.z) + n * 5, 1.5)
    }

    /// 0〜0.6 秒: ゲームカメラの向きのまま Core の中ほどへ寄る（イーズインアウト）。最初だけ小さく揺らす。
    private func pushPose(at t: Double, game: CameraPose) -> CameraPose {
        let start = pushStart(game: game)
        let end = CameraPose(position: core + SIMD3(0, CoreFinaleShot.pushLook, 0) - start.forward * CoreFinaleShot.pushDistance,
                             yaw: start.yaw, pitch: start.pitch)
        let u = Float(max(0, min(1, t / TowerTimeline.finalePushEnd)))
        var p = CameraPose.mix(start, end, u * u * (3 - 2 * u))
        p.position += shake(at: t)
        return p
    }

    /// 寄りの起点: いまのゲームカメラ。注視点が Core から遠ければ、同じ向き・距離で Core を見るゲームカメラ（切り替え）。
    private func pushStart(game: CameraPose) -> CameraPose {
        let f = game.forward
        guard f.y < -0.05 else { return gameCentered(game: game, distance: CameraRig.baseDistance) }
        let s = -game.position.y / f.y
        let focus = game.position + f * s
        if simd_distance(SIMD2(focus.x, focus.z), SIMD2(core.x, core.z)) <= CoreFinaleShot.pushCutDistance { return game }
        return gameCentered(game: game, distance: simd_distance(game.position, focus))
    }

    private func gameCentered(game: CameraPose, distance d: Float) -> CameraPose {
        let pitch = game.forward.y < -0.05 ? game.pitch : -CameraRig.pitchDegrees * .pi / 180
        let f = CameraPose(position: .zero, yaw: game.yaw, pitch: pitch).forward
        return CameraPose(position: core - f * d, yaw: game.yaw, pitch: pitch)
    }

    /// 最初の小さな揺れ（時刻の関数。0.4 秒で消える）。
    private func shake(at t: Double) -> SIMD3<Float> {
        guard t < CoreFinaleShot.shakeEnd else { return .zero }
        let k = Float(1 - t / CoreFinaleShot.shakeEnd)
        let a = CoreFinaleShot.shakeAmplitude * k * k
        let x = Float(t)
        let sx = sin(x * 37) * 0.6 + sin(x * 61 + 1.3) * 0.4
        let sy = sin(x * 43 + 2.1) * 0.6 + sin(x * 71 + 0.4) * 0.4
        return SIMD3(sx, sy * 0.6, sy * 0.3) * a
    }

    /// 回り込みの方位（0.6 秒から 5.2 秒まで 1 本の曲線: 切り替えの直後が一番速く、引きの構図で止まる）。
    func orbitAzimuth(at t: Double) -> Float {
        let span = TowerTimeline.finaleSettleEnd - TowerTimeline.finalePushEnd
        let v = Float(max(0, min(1, (t - TowerTimeline.finalePushEnd) / span)))
        return azimuth - sweep * CoreFinaleShot.orbitArc * pow(1 - v, 1.35)
    }

    /// 0.6〜4.0 秒: 階段の近くの低い位置から結晶を見上げ、ゆっくり回り込む（少しずつ寄って上がる）。
    private func orbitPose(at t: Double) -> CameraPose {
        let span = TowerTimeline.finaleOrbitEnd - TowerTimeline.finalePushEnd
        let u = Float(max(0, min(1, (t - TowerTimeline.finalePushEnd) / span)))
        return lowPose(azimuth: orbitAzimuth(at: t), progress: u)
    }

    private func lowPose(azimuth a: Float, progress u: Float) -> CameraPose {
        let r = CoreFinaleShot.lowRadius.start + (CoreFinaleShot.lowRadius.end - CoreFinaleShot.lowRadius.start) * u
        let h = CoreFinaleShot.lowHeight.start + (CoreFinaleShot.lowHeight.end - CoreFinaleShot.lowHeight.start) * u
        return CameraPose.looking(from: position(azimuth: a, radius: r, height: h), at: core + SIMD3(0, CoreFinaleShot.lowLook, 0))
    }

    /// 4.0〜5.2 秒: 回り込みを続けながら引いて上がり、構図（Core を右寄せ）へ向きを移す。
    private func settlePose(at t: Double) -> CameraPose {
        let span = TowerTimeline.finaleSettleEnd - TowerTimeline.finaleOrbitEnd
        let v = Float(max(0, min(1, (t - TowerTimeline.finaleOrbitEnd) / span)))
        let w = v * v * (3 - 2 * v)
        let r = CoreFinaleShot.lowRadius.end + (CoreFinaleShot.wideRadius - CoreFinaleShot.lowRadius.end) * w
        let h = CoreFinaleShot.lowHeight.end + (CoreFinaleShot.wideHeight - CoreFinaleShot.lowHeight.end) * w
        let p = position(azimuth: orbitAzimuth(at: t), radius: r, height: h)
        let low = CameraPose.looking(from: p, at: core + SIMD3(0, CoreFinaleShot.lowLook, 0))
        let wide = composed(from: p)
        return CameraPose(position: p, yaw: low.yaw + CameraPose.wrapAngle(wide.yaw - low.yaw) * w,
                          pitch: low.pitch + (wide.pitch - low.pitch) * w)
    }

    /// 5.2 秒以降: 引きの落ち着いた構図（Core を右寄せ、左を空ける）。
    var widePose: CameraPose {
        composed(from: position(azimuth: azimuth, radius: CoreFinaleShot.wideRadius, height: CoreFinaleShot.wideHeight))
    }

    private func composed(from p: SIMD3<Float>) -> CameraPose {
        CameraPose.framing(core + SIMD3(0, CoreFinaleShot.wideAnchor, 0), at: CoreFinaleShot.wideScreen, from: p, aspect: aspect)
    }

    func position(azimuth a: Float, radius r: Float, height h: Float) -> SIMD3<Float> {
        core + SIMD3(sin(a) * r, h, cos(a) * r)
    }

    // MARK: 方位の選択

    /// 低い視点・引きの構図のカメラが通る位置（水平。回り込みの全区間を 0.1 秒ごと）。
    static func samplePositions(core: SIMD3<Float>, azimuth: Float, sweep: Float) -> [SIMD3<Float>] {
        let shot = CoreFinaleShot(core: core, azimuth: azimuth, sweep: sweep, reducedMotion: false, aspect: CameraRig.designAspect)
        let still = CoreFinaleShot(core: core, azimuth: azimuth, sweep: sweep, reducedMotion: true, aspect: CameraRig.designAspect)
        let game = CameraPose(position: core + SIMD3(0, 10, 7), yaw: 0, pitch: -CameraRig.pitchDegrees * .pi / 180)
        var out: [SIMD3<Float>] = []
        var t = TowerTimeline.finalePushEnd
        while t <= TowerTimeline.finaleSettleEnd + 1e-6 {
            out.append(shot.pose(at: t, game: game).position)
            t += 0.1
        }
        out.append(still.pose(at: TowerTimeline.finalePushEnd, game: game).position)
        return out
    }

    /// 手前のヒーローで隠れる重み（隠れている時間の割合 × 人数あたり。北を向く好みの角度 rad と比べる）。
    static let heroOcclusionWeight: Float = 1.5

    /// 方位の候補 1 つ（地図だけで決まる: カメラが通る位置と、置けない位置・隠れる視線の数）。
    struct Candidate: Equatable {
        var azimuth: Float
        var sweep: Float
        var samples: [SIMD3<Float>]
        var problems: Int
        /// 引きの構図の左（バナーを置く空き）に映る近くの塔・泉の数。
        var leftClutter = 0
    }

    /// 引きの構図の左の空きに塔・泉が映る重み（1 つあたり。北を向く好みの角度 rad と比べる）。
    static let leftClutterWeight: Float = 1.6
    /// 左の空き（正規化した画面の x・y の範囲）と、そこに映ると邪魔になる距離（Core から m。遠くの塔は小さいので数えない）。
    static let leftSpace: (x: ClosedRange<Float>, y: ClosedRange<Float>) = (-0.95 ... -0.1, -0.7 ... 0.7)
    static let clutterReach: Float = 25

    /// 方位の候補（10° 刻み・回り込みの向き 2 通り）。地図の検査は決着の瞬間には重いので、BattleRenderer は読み込み中に作っておく。
    static func candidates(core: SIMD3<Float>, map: MapDefinition) -> [Candidate] {
        let site = Site(map: map, core: core)
        var out: [Candidate] = []
        out.reserveCapacity(72)
        for k in 0..<36 {
            let a = CameraPose.wrapAngle(Float(k) * 10 * .pi / 180)
            for sweep: Float in [1, -1] {
                let samples = samplePositions(core: core, azimuth: a, sweep: sweep)
                let wide = CoreFinaleShot(core: core, azimuth: a, sweep: sweep, reducedMotion: false, aspect: CameraRig.designAspect)
                    .widePose
                out.append(Candidate(azimuth: a, sweep: sweep, samples: samples, problems: violations(samples: samples, site: site),
                                     leftClutter: site.leftClutter(in: wide)))
            }
        }
        return out
    }

    /// 候補のうち、置けない位置・隠れる視線が無く、北を向く撮り方に近いもの。引きの構図の左の空き（バナーの場所）に塔・泉が
    /// 映る向き・手前のヒーローで結晶が隠れる向きは避ける（地図の制約より優先しない）。全部に問題があれば問題の数が最も少ないもの。
    static func choose(from candidates: [Candidate], core: SIMD3<Float>, heroes: [SIMD2<Float>] = [])
        -> (azimuth: Float, sweep: Float) {
        let core2 = SIMD2(core.x, core.z)
        let near = heroes.filter { simd_distance($0, core2) < lowRadius.start + 3 }
        var best: (cost: Float, azimuth: Float, sweep: Float)?
        for c in candidates {
            let blocked = heroOcclusion(core: core2, samples: c.samples, heroes: near)
            // 北を向く（カメラが Core の南）ほど良い。引きの構図の左は空ける。同じなら東回り
            let cost = Float(c.problems) * 100 + blocked * heroOcclusionWeight + Float(c.leftClutter) * leftClutterWeight
                + abs(c.azimuth) + (c.sweep > 0 ? 0 : 0.01)
            if best == nil || cost < best!.cost { best = (cost, c.azimuth, c.sweep) }
        }
        return best.map { ($0.azimuth, $0.sweep) } ?? (0, 1)
    }

    /// カメラ → Core の視線の近く（1.3 m 以内）・カメラのすぐ近く（2.5 m 以内）に立つヒーローの数の、区間を通した平均
    /// （決着の瞬間に 72 通り計算するので、位置は 1 つおき = 0.2 秒ごとに見る）。
    static func heroOcclusion(core: SIMD2<Float>, samples: [SIMD3<Float>], heroes: [SIMD2<Float>]) -> Float {
        // Core の中心から 2.5 m の内側（台座の上）は結晶より低いので数えない
        let heroes = heroes.filter { simd_distance($0, core) > 2.5 }
        guard !heroes.isEmpty, !samples.isEmpty else { return 0 }
        var total = 0, n = 0
        for i in stride(from: 0, to: samples.count, by: 2) {
            n += 1
            let q = SIMD2(samples[i].x, samples[i].z)
            let seg = core - q
            let len2 = max(1e-4, simd_length_squared(seg))
            for h in heroes {
                let k = max(0, min(1, simd_dot(h - q, seg) / len2))
                if simd_distance(h, q + seg * k) < 1.3 || simd_distance(h, q) < 2.5 { total += 1 }
            }
        }
        return Float(total) / Float(max(1, n))
    }

    /// 置けない位置・隠れる視線の数（0 = 問題なし）。
    static func violations(core: SIMD3<Float>, azimuth: Float, sweep: Float, map: MapDefinition) -> Int {
        violations(samples: samplePositions(core: core, azimuth: azimuth, sweep: sweep), site: Site(map: map, core: core))
    }

    private static func violations(samples: [SIMD3<Float>], site: Site) -> Int {
        var count = 0
        for p in samples {
            let q = SIMD2(p.x, p.z)
            if !site.isPlaceable(q) { count += 1 }
            if site.isOccluded(from: q) { count += 1 }
        }
        return count
    }

    /// Core の周り（カメラが届く範囲）の地図: 壁・草むら（sim の座標）、塔・泉・参道のランタン（world x・z と避ける距離）。
    /// 範囲の外は見ないので、方位の候補 72 通り × 位置 48 か所の検査が地図全体の大きさに比例しない。
    struct Site {
        let core: SIMD2<Float>
        let mapMeters: Float
        let walls: [Obstacle]
        let brushes: [Rect2]
        let points: [(SIMD2<Float>, Float)]

        /// カメラが届く距離（引きの構図の半径 + 余白、m）。
        static let reach: Float = wideRadius + 4

        init(map: MapDefinition, core: SIMD3<Float>) {
            let c = SIMD2(core.x, core.z)
            self.core = c
            mapMeters = Float(map.size / Balance.unitsPerMeter)
            let center = CoreFinaleShot.sim(c)
            let r = Double(Site.reach) * Balance.unitsPerMeter
            walls = map.obstacles.filter { $0.signedDistance(to: center) < r }
            brushes = map.brushes.map(\.rect).filter { b in
                let dx = max(b.minX - center.x, 0, center.x - b.maxX), dy = max(b.minY - center.y, 0, center.y - b.maxY)
                return dx * dx + dy * dy < r * r
            }
            var out: [(SIMD2<Float>, Float)] = []
            func w(_ v: Vec2) -> SIMD2<Float> { SIMD2(Float(v.x / Balance.unitsPerMeter), Float(-v.y / Balance.unitsPerMeter)) }
            func add(_ p: SIMD2<Float>, _ clearance: Float) {
                if simd_distance(p, c) < Site.reach + clearance { out.append((p, clearance)) }
            }
            for t in map.towers {
                let p = w(t.pos)
                if simd_distance(p, c) < 0.5 { continue }
                add(p, towerClearance)
            }
            for team in Team.players {
                let f = map.fountain(team), k = map.core(team)
                add(w(f), fountainClearance)
                // 泉 → Core の参道の吊りランタン（MapScene の配置と同じ: 30%・62% の位置の両脇 5.6 m）
                let along = (k - f).normalized, side = along.perpendicular
                for t in [0.3, 0.62] {
                    for s in [-1.0, 1.0] { add(w(f + (k - f) * t + side * (560 * s)), lanternClearance) }
                }
            }
            points = out
        }

        /// 引きの構図の左の空きに映る近くの塔・泉の数（高さの中ほどで見る）。
        func leftClutter(in wide: CameraPose) -> Int {
            var n = 0
            for (o, r) in points where r > lanternClearance && simd_distance(o, core) < CoreFinaleShot.clutterReach {
                guard let q = wide.screen(of: SIMD3(o.x, 2.5, o.y), aspect: CameraRig.designAspect) else { continue }
                if CoreFinaleShot.leftSpace.x.contains(q.x) && CoreFinaleShot.leftSpace.y.contains(q.y) { n += 1 }
            }
            return n
        }

        /// カメラを置ける場所か（地図の中・壁と草むらの外・塔や泉やランタンから離れている・台座の外）。
        func isPlaceable(_ q: SIMD2<Float>) -> Bool {
            let m = mapMargin, M = mapMeters
            guard q.x >= m, q.x <= M - m, q.y <= -m, q.y >= -(M - m) else { return false }
            if simd_distance(q, core) < platformClearance { return false }
            let p = CoreFinaleShot.sim(q)
            let wall = Double(wallMargin) * Balance.unitsPerMeter
            if walls.contains(where: { $0.contains(p, inflatedBy: wall) }) { return false }
            // 草むら（背の低い茂み）の中・1 m 以内
            if brushes.contains(where: { $0.expanded(by: 100).contains(p) }) { return false }
            for (o, r) in points where simd_distance(q, o) < r { return false }
            return true
        }

        /// カメラから Core までの視線が壁・塔・泉で遮られるか（台座の内側は見ない）。
        func isOccluded(from q: SIMD2<Float>) -> Bool {
            let length = simd_distance(q, core)
            let open = length - 4
            guard open > 0 else { return false }
            let dir = (core - q) / max(1e-3, length)
            var s: Float = 0
            while s <= open {
                let p = q + dir * s
                let sp = CoreFinaleShot.sim(p)
                if walls.contains(where: { $0.contains(sp) }) { return true }
                // ランタン（細い柱）は視線を遮らない
                for (o, r) in points where r > lanternClearance && simd_distance(p, o) < r * 0.5 { return true }
                s += 0.5
            }
            return false
        }
    }

    fileprivate static func sim(_ q: SIMD2<Float>) -> Vec2 {
        Vec2(Double(q.x) * Balance.unitsPerMeter, -Double(q.y) * Balance.unitsPerMeter)
    }
}

/// 試合 1 回分の終幕の進み（BattleRenderer が持つ）。
struct CoreFinaleRun: Equatable {
    /// 壊れた Core のチーム。
    var team: Team
    var shot: CoreFinaleShot
    var deathTime: Double
    /// 通知を受けずに終わった状態になった（シーク・再同期・途中から観戦）: 終幕を流さず引きの構図から。
    var skipped: Bool
    /// 終幕を始めた時のカメラモード（リザルトの後に観戦者が戦術マップ・追従先でカメラを動かしたらゲームカメラへ返す）。
    var cameraMode: CameraMode
    /// ゲームカメラへ返した。
    var released = false

    /// 終幕の経過秒（presentationTime = RenderFrame.presentationTime。試合終了後も実時間で進む）。
    func elapsed(presentationTime: Double) -> Double {
        skipped ? .infinity : max(0, presentationTime - deathTime)
    }
}
