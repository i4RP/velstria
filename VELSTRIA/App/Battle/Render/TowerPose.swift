import Foundation
import simd
import VelstriaCore

// 担当: battle-renderer。塔・Star Core の部品の姿勢と一度きりの合図（純粋関数。時刻表は TowerTimeline）。
// 姿勢は「演出時刻 − きっかけの時刻（試合開始 0・unit.deathTime）」と HP の割合・攻撃の前隙だけで決める
// （前のフレームの値を積み上げない）。シーク・再同期・一時停止・リプレイ・同じイベントの重複でも、同じ時刻なら同じ姿勢。
// 一度きりの演出・音（TowerCue）は前回と今回の評価の間に入った合図だけを返す。シークの後は呼び出し側が前回の時刻を
// 今に合わせるので、飛ばした区間の合図は出ない。
//
// 座標は塔の局所（原点 = 足元の中心、+y が上、-z が北 = カメラの奥）。部品の行列は「静止時の形 → 今の位置」。
// 部品は全て塔の原点を共有する（USDZ の子メッシュ。tools/structures/tower_parts.py）ので、行列は部品の静止時の形に
// そのまま掛ける。破片（結晶片・小破片）の行列は原点に置いた形を今の位置へ動かす。

/// 部品（USDZ の子メッシュ名）。
enum TowerPart: String, CaseIterable, Sendable {
    /// 固定の基壇（最後まで残る）。
    case plinth = "part_plinth"
    /// 中央支柱の下半（破壊後は折れた根元として残る）。
    case lower = "part_lower"
    /// 中央支柱の上半＋外装（破壊で奥へ倒れる）。Core では石柱と弧。
    case upper = "part_upper"
    /// 頂部構造（立ち上がりの最後に収まる。破壊で分かれて落ちる）。
    case crown = "part_crown"
    /// 魔力コア（浮遊・脈動。破壊で割れて失活）。
    case crystal = "part_crystal"
}

/// 部品の外接箱（塔の局所座標）。
struct PartBox: Equatable, Sendable {
    var min: SIMD3<Float>
    var max: SIMD3<Float>

    var center: SIMD3<Float> { (min + max) / 2 }
    var extents: SIMD3<Float> { max - min }
    /// 水平の太さ（x・z の小さい方）。
    var width: Float { Swift.min(extents.x, extents.z) }

    var corners: [SIMD3<Float>] {
        [SIMD3(min.x, min.y, min.z), SIMD3(max.x, min.y, min.z), SIMD3(min.x, max.y, min.z), SIMD3(max.x, max.y, min.z),
         SIMD3(min.x, min.y, max.z), SIMD3(max.x, min.y, max.z), SIMD3(min.x, max.y, max.z), SIMD3(max.x, max.y, max.z)]
    }

    func offset(_ v: SIMD3<Float>) -> PartBox { PartBox(min: min + v, max: max + v) }
}

/// 倒壊の版。同時に倒れる塔が上限（TowerTimeline.maxConcurrentCollapses）を超えた分は、粉塵と破片を減らした短縮版。
enum CollapseStyle: Sendable, Equatable {
    case full
    case short
}

/// 姿勢を求めるための寸法（部品の外接箱から決める。従来のモデル・手続きメッシュは同じ形の近似値）。
struct TowerGeometry: Equatable, Sendable {
    var isCore: Bool
    /// 基壇（nil = 基壇を含む 1 つのメッシュの従来の塔。地面から立ち上がる）。
    var plinth: PartBox?
    /// 折れて残る根元（nil = 無し）。
    var lower: PartBox?
    /// 倒れる上部（Core は石柱と弧）。
    var upper: PartBox
    /// 頂部（nil = 上部と一体）。
    var crown: PartBox?
    /// 結晶（静止時の位置）。
    var crystal: PartBox
    /// 基壇の上面（立ち上がりで部品をここより下へ沈める）。
    var plinthTop: Float
    /// 破断線の高さ（上部が倒れる時の支点）。
    var breakY: Float
    /// 破断線での支柱の半径（支点 = 倒れる側の縁）。Core は石柱の環の半径。
    var breakRadius: Float
    /// 待機中に結晶を静止時の位置から持ち上げる高さ（浮いて見せる。複数部品の Core は大結晶の下端が祭壇の約 5 cm 上
    /// なので持ち上げてから揺らす）。
    var crystalLift: Float = 0
    /// 待機中の結晶の上下の揺れ幅（m）。
    var crystalBob: Float = 0.07
    /// 倒れる向きの北からの振れ（rad。個体ごとに北西か北東）。見下ろすカメラでは真北へ倒れた上部が画面の縦に伸びて
    /// 「まだ立っている塔」に見えるので斜めに倒す。脇に飾り（内塔の控え壁の弧）がある塔は北寄りにして突き抜けを避ける。
    var toppleYaw: ClosedRange<Float> = 0.75...1.0

    /// 上部の高さ ÷ 太さ（倒れ方を決める）。
    var upperAspect: Float { upper.extents.y / Swift.max(0.01, (upper.extents.x + upper.extents.z) / 2) }

    /// 倒れ切った角度。細長い上部はほぼ横倒し、背の低い幅広の上部（内塔の胴）は少し傾いたまま落ちる
    /// （90° 倒すと幅の分だけ高い壁になって立ってしまう）。
    var toppleMax: Float {
        let k = Swift.min(1, Swift.max(0, (upperAspect - 0.65) / 0.75))
        return 0.5 + (TowerPose.toppleMaxAngle - 0.5) * k * k * (3 - 2 * k)
    }

    /// 上部が倒れずに根元の中へ崩れ落ちる（高さが太さの 0.65 倍未満 = 基地塔の天守。幅のある塊を根元から外へ
    /// 落とすには根元の幅以上に飛ばす必要があり、重さが出ない）。頂部は外れて倒れる側へ落ちる。
    /// 崩れ落ちた上部は整理でも消さず、折れた根元の一部として残す。
    var cavesIn: Bool { plinth != nil && upperAspect < 0.65 }

    /// 全体の上端（立ち上がりで沈める深さの基準）。
    var top: Float { Swift.max(upper.max.y, crown?.max.y ?? 0, crystal.max.y) }

    /// 被弾の火花を出す半径（塔の側面）。
    var hitRadius: Float { isCore ? Swift.max(1.2, breakRadius * 0.55) : Swift.max(0.5, breakRadius * 1.05) }

    /// 部品の外接箱から（新しい複数部品のモデル）。塔は 5 部品、Core は基壇・上部・結晶が要る。
    static func rig(isCore: Bool, boxes: [TowerPart: PartBox]) -> TowerGeometry? {
        guard let plinth = boxes[.plinth], let upper = boxes[.upper], let crystal = boxes[.crystal] else { return nil }
        if isCore {
            let ring = Swift.max(upper.extents.x, upper.extents.z) / 2
            return TowerGeometry(isCore: true, plinth: plinth, lower: nil, upper: upper, crown: nil, crystal: crystal,
                                 plinthTop: plinth.max.y, breakY: plinth.max.y, breakRadius: Swift.max(1, ring * 0.85),
                                 crystalLift: 0.2, crystalBob: 0.12)
        }
        guard let lower = boxes[.lower] else { return nil }
        let crown = boxes[.crown]
        // 基壇の上面: 根元が基壇の上に載っている（地面より上から始まる）なら根元の下端。基壇の外接箱は控え壁の弧・角の柱
        // などの飾りで高くなる（内塔は 3 m）ので、それより下で部品を沈めると基壇の上に出てしまう
        let top = lower.min.y > 0.05 ? Swift.min(plinth.max.y, lower.min.y) : plinth.max.y
        return TowerGeometry(isCore: false, plinth: plinth, lower: lower, upper: upper, crown: crown, crystal: crystal,
                             plinthTop: top, breakY: Swift.max(lower.max.y, upper.min.y),
                             breakRadius: Swift.max(0.25, lower.width / 2 * 0.9))
    }

    /// 手続きメッシュの塔（StructureMeshes: 台座・柱・結晶。根元は柱の内側の短い円錐台）。
    static let proceduralTower = TowerGeometry(
        isCore: false,
        plinth: PartBox(min: [-1.55, 0, -1.55], max: [1.55, 0.66, 1.55]),
        lower: PartBox(min: [-0.62, 0, -0.62], max: [0.62, 1.25, 0.62]),
        upper: PartBox(min: [-0.78, 0.66, -0.78], max: [0.78, 4.8, 0.78]),
        crown: nil,
        crystal: PartBox(min: [-0.46, 4.33, -0.46], max: [0.46, 5.78, 0.46]),
        plinthTop: 0.66, breakY: 1.25, breakRadius: 0.6)

    /// 従来の生成モデルの塔（台座ごと 1 つのメッシュ）。地面から立ち上がり、足元から倒れる。
    static func legacyTower(body: PartBox, crystal: PartBox) -> TowerGeometry {
        TowerGeometry(isCore: false, plinth: nil, lower: nil, upper: body, crown: nil, crystal: crystal,
                      plinthTop: 0, breakY: body.min.y + 0.45, breakRadius: Swift.max(0.4, body.width * 0.36))
    }

    /// 従来の Core（台座 + 回る環 + 大結晶）。環を「上部」として扱う。
    static func legacyCore(base: PartBox, rings: PartBox, crystal: PartBox) -> TowerGeometry {
        TowerGeometry(isCore: true, plinth: base, lower: nil, upper: rings, crown: nil, crystal: crystal,
                      plinthTop: Swift.min(base.max.y, 1.3), breakY: Swift.min(base.max.y, 1.3),
                      breakRadius: Swift.max(2.2, base.width * 0.4), crystalBob: 0.16)
    }
}

/// 一度きりの演出・音の合図。
enum TowerCue: Equatable, Sendable {
    // 立ち上がり（試合開始から）
    /// 基壇の紋様の点灯・継ぎ目の砂（地鳴りは試合で 1 回だけ）。
    case riseStart
    /// 頂部が収まってロックする（小さな砂・金属音）。
    case riseLock
    /// 結晶の点灯。
    case crystalIgnite
    // 生きている間
    /// 損傷 2 段階の魔力漏れ（チーム色の細い光）。
    case wisp
    /// 損傷の段階が上がった（ひび・欠け）。描画側が HP の閾値をまたいだ時に出す（時刻表には無い）。
    case damaged
    // 塔の倒壊（deathTime から）
    case breakFlash, crack, toppleStart, crystalShatter, separate, crownImpact, impact, clearDebris, crystalFade, crumble
    // Core の崩壊（deathTime から）
    case coreOverload, coreArchesFall, coreArchesImpact, coreImplode, coreShockwave, coreSettle
}

/// 合図と、その時刻（演出時刻）・位置（塔の局所）。
struct TowerCueEvent: Equatable, Sendable {
    var cue: TowerCue
    var time: Double
    var position: SIMD3<Float>
}

/// 姿勢を求める入力（全て値。同じ入力なら同じ姿勢）。
struct TowerPoseInput {
    var geometry: TowerGeometry
    /// 演出時刻（RenderFrame.presentationTime。試合終了後も進む）。
    var time: Double
    /// 破壊の時刻（nil = 生きている）。
    var deathTime: Double?
    var hpRatio: Double = 1
    /// 攻撃の前隙の進み（0〜1。前隙中でなければ 0）。
    var charge: Float = 0
    /// 損傷の傾き（ラジアン）。nil = 損傷の段階どおり（描画側は閾値をまたいだ時に少しずつ寄せた値を渡す）。
    var lean: Float?
    var style: CollapseStyle = .full
    /// 個体差（倒れる向きの揺らぎ・破片の飛び方）。
    var seed: UInt64 = 0
}

/// 1 時刻の姿勢。
struct TowerPose: Equatable {
    struct Piece: Equatable {
        var matrix = matrix_identity_float4x4
        var visible = true
        var opacity: Float = 1
    }

    enum Phase: Int, Sendable {
        case rising, idle, breaking, toppling, settling, rubble, clearing, cleared
    }

    var plinth = Piece()
    var lower = Piece()
    var upper = Piece()
    var crown = Piece()
    var crystal = Piece()
    /// 基壇の紋様の明るさ（0 = 消灯、1 = 通常、1 超 = 明るい）。
    var plinthGlow: Float = 1
    /// 支柱・頂部の紋様の明るさ。
    var bodyGlow: Float = 1
    /// 結晶の明るさ。
    var crystalGlow: Float = 1
    /// 破損した石の材質（紋様の消えた暗い石）へ替える。
    var ruined = false
    /// 結晶片（倒壊後だけ。数は TowerPose.shardCount）。
    var shards: [Piece] = []
    /// 小破片（倒壊後だけ。数は TowerPose.debrisCount）。
    var debris: [Piece] = []
    /// Core の光の柱の強さ（0 = 出さない）。
    var column: Float = 0
    var phase: Phase = .idle
}

/// 倒壊の時刻（deathTime からの秒）。通常版は TowerTimeline、短縮版は全体を縮めて瓦礫を早く片付ける。
struct CollapseTimes: Equatable, Sendable {
    var flash: Double
    var crack: Double
    var topple: Double
    var impact: Double
    var hold: Double
    var clear: Double

    static let full = CollapseTimes(flash: TowerTimeline.breakFlashEnd, crack: TowerTimeline.crackEnd,
                                    topple: TowerTimeline.toppleEnd, impact: TowerTimeline.impactEnd,
                                    hold: TowerTimeline.rubbleHoldEnd, clear: TowerTimeline.clearEnd)
    static let short = CollapseTimes(flash: 0.15, crack: 0.35, topple: 1.0, impact: 1.5, hold: 2.6, clear: 3.8)

    static func of(_ s: CollapseStyle) -> CollapseTimes { s == .full ? .full : .short }

    /// 結晶が割れる（上部が傾き始めて少し後）。
    var shatter: Double { crack + (topple - crack) * 0.35 }
    /// 頂部が上部から外れる（通常版だけ）。
    var separate: Double { crack + (topple - crack) * 0.55 }
    /// 整理の区間: 小破片 → 結晶片 → 大きな石の順。
    var debrisClear: (Double, Double) { (hold, hold + (clear - hold) * 0.4) }
    var shardClear: (Double, Double) { (hold + (clear - hold) * 0.25, hold + (clear - hold) * 0.65) }
    var chunkClear: (Double, Double) { (hold + (clear - hold) * 0.4, clear) }
}

/// Core の崩壊の時刻（deathTime からの秒。終幕のカメラ TowerTimeline.finale* と揃える）。
enum CoreCollapse {
    /// 結晶の過負荷（ゲームカメラのまま寄る区間）。
    static let overloadEnd = TowerTimeline.finalePushEnd
    /// 石柱・弧が外へ崩れて着地する。
    static let archesLand: Double = 1.6
    /// 大結晶が縮んで割れる（光の柱が立つ）。
    static let implodeStart: Double = 2.0
    static let implodeEnd: Double = 2.4
    /// 地面の衝撃波。
    static let shockwave: Double = 2.45
    /// 光の柱が消え終わる。
    static let columnEnd: Double = 3.8
    /// 落ち着いた（砂の合図）。
    static let settleCue: Double = 3.6
    /// これ以降は瓦礫のまま。
    static let settled = TowerTimeline.finaleOrbitEnd
}

extension TowerPose {
    /// 結晶片の数（塔の通常版・短縮版 / Core）。
    static func shardCount(core: Bool, style: CollapseStyle) -> Int { core ? 6 : (style == .full ? 4 : 2) }
    /// 小破片の数（上限 TowerTimeline.maxSmallDebris）。短縮版は出さない。
    static func debrisCount(core: Bool, style: CollapseStyle) -> Int {
        min(TowerTimeline.maxSmallDebris, core ? 12 : (style == .full ? 8 : 0))
    }
    /// 描画側が作っておく破片のエンティティ数（通常版の最大）。
    static func shardCapacity(core: Bool) -> Int { shardCount(core: core, style: .full) }
    static func debrisCapacity(core: Bool) -> Int { debrisCount(core: core, style: .full) }

    /// 損傷の段階ごとの上部の傾き（ラジアン）。
    static func leanAngle(stage: Int) -> Float { stage >= 2 ? 0.075 : stage == 1 ? 0.035 : 0 }

    /// 倒れ切った角度（ほぼ横倒し）。
    static let toppleMaxAngle: Float = 1.48
    /// 立ち上がりの最後に頂部が浮いている高さ・ひねり（ここから降りてロックする）。
    static let crownLift: Float = 0.32
    static let crownTwist: Float = 0.6
    /// 落下の重力（実際より重く、速く落ちる）。
    static let gravity: Float = 15

    /// 立ち上がりで部品を沈める深さ（浮いた頂部も含めて全て基壇の上面より下 = 基壇と地面に隠れる）。
    /// 上部の下端が基壇の上面より低い（Core の石柱は祭壇より低い外周の段に立つ）なら、その下端より下まで沈める。
    static func riseDepth(_ g: TowerGeometry) -> Float {
        max(0, g.top - min(g.plinthTop, g.upper.min.y)) + 0.08 + (g.crown != nil ? crownLift : 0)
    }

    // MARK: 評価

    static func evaluate(_ input: TowerPoseInput) -> TowerPose {
        if let d = input.deathTime {
            return input.geometry.isCore ? destroyedCore(input, e: max(0, input.time - d), deathTime: d)
                                         : destroyedTower(input, e: max(0, input.time - d), deathTime: d)
        }
        return alive(input)
    }

    /// 静止した無傷の姿（立ち上がりの終わり・損傷なし・攻撃なし）。結晶の揺れは含む。
    static func intact(_ g: TowerGeometry, time: Double = TowerTimeline.riseEnd, seed: UInt64 = 0) -> TowerPose {
        alive(TowerPoseInput(geometry: g, time: time, deathTime: nil, seed: seed))
    }

    // MARK: 生きている間（立ち上がり → 待機・攻撃・損傷）

    private static func alive(_ input: TowerPoseInput) -> TowerPose {
        let g = input.geometry
        let t = input.time
        var p = TowerPose()
        p.phase = t < TowerTimeline.riseEnd ? .rising : .idle
        // 立ち上がり: 支柱（根元・上部・頂部・結晶）を基壇の中から重く持ち上げる（伸び縮み・跳ね返りなし）
        let rise = riseOffset(t, depth: riseDepth(g))
        // 頂部は支柱が上がり切った後、浮いた位置からひねりを戻しながら降りてロックする
        let lockU = Float(clamp01((t - TowerTimeline.risePillarEnd) / (lockTime - TowerTimeline.risePillarEnd)))
        let crownLiftNow = crownLift * (1 - smooth(lockU))
        let twist = crownTwist * (1 - smooth(lockU))
        // 損傷の傾き（上部・頂部・結晶。支点は破断線の奥側の縁）
        let stage = TowerTimeline.damageStage(hpRatio: input.hpRatio)
        let lean = g.isCore ? 0 : (input.lean ?? leanAngle(stage: stage))
        let leanM = g.isCore ? matrix_identity_float4x4 : toppleRotation(g, seed: input.seed, angle: lean)
        let lift = translation([0, rise, 0])
        p.plinth.matrix = matrix_identity_float4x4
        p.lower.matrix = lift
        p.upper.matrix = lift * leanM
        if let crown = g.crown {
            let c = crown.center
            p.crown.matrix = lift * translation([0, crownLiftNow, 0]) * leanM * rotationY(twist, about: c)
        } else {
            p.crown.visible = false
        }
        // 結晶: 点灯までは暗いまま上がり、点灯後に上下の揺れと脈動（石の本体は揺れない）
        let ph = Float(hash(input.seed, 7)) * 6.283
        let ignite = smooth(Float(clamp01((t - TowerTimeline.riseLockEnd) / (TowerTimeline.riseEnd - TowerTimeline.riseLockEnd))))
        let tf = Float(t.truncatingRemainder(dividingBy: 3600))
        let bob = (g.crystalLift + (g.isCore ? sin(tf * 1.1 + ph) : sin(tf * 1.6 + ph)) * g.crystalBob) * ignite
        let spin = tf * (g.isCore ? 0.3 : 0.5)
        let charge = max(0, min(1, input.charge))
        let pulse = 1 + (0.025 * sin(tf * 2.3 + ph)) * ignite + 0.06 * charge
        let c = g.crystal.center
        p.crystal.matrix = lift * translation([0, bob, 0]) * leanM * translation(c) * rotationY(spin) * scale(pulse)
            * translation(-c)
        // 明るさ: 基壇の紋様 → 支柱を下から上へ → 結晶の点灯（短い山の後に通常へ）
        p.plinthGlow = riseGlow(t, start: 0, end: TowerTimeline.riseGlowEnd, peak: 1.7, settle: 0.9)
        p.bodyGlow = Float(clamp01((t - (lockTime - 0.1)) / 0.45)).smoothed * 0.97 + 0.03
        p.crystalGlow = crystalIgnition(t)
        // 損傷: 1 = 結晶が暗く、2 = さらに暗く明滅
        switch stage {
        case 1:
            p.crystalGlow *= 0.7
            p.bodyGlow *= 0.8
        case 2:
            p.crystalGlow *= hash(input.seed, Int(floor(t * 7))) < 0.3 ? 0.35 : 0.65
            p.bodyGlow *= 0.65
            p.plinthGlow *= 0.85
        default:
            break
        }
        // 攻撃の前隙: 紋様と結晶が明るくなってから弾が出る（発射の時刻は sim のまま）
        p.crystalGlow += 1.6 * charge
        p.bodyGlow += 0.7 * charge
        p.plinthGlow += 0.4 * charge
        return p
    }

    /// 頂部がロックする時刻（合図もこの時刻）。
    static let lockTime: Double = TowerTimeline.riseLockEnd - 0.05

    /// 支柱の高さのずれ（0 = 静止位置、負 = 沈んでいる）。
    static func riseOffset(_ t: Double, depth: Float) -> Float {
        let u = Float(clamp01((t - TowerTimeline.riseGlowEnd) / (TowerTimeline.risePillarEnd - TowerTimeline.riseGlowEnd)))
        return -depth * (1 - smoother(u))
    }

    private static func riseGlow(_ t: Double, start: Double, end: Double, peak: Float, settle: Double) -> Float {
        if t <= start { return 0 }
        if t < end { return peak * smooth(Float((t - start) / (end - start))) }
        let k = Float(clamp01((t - end) / max(0.01, settle - end)))
        return peak + (1 - peak) * smooth(k)
    }

    /// 結晶の点灯（立ち上がりの最後の 0.5 秒）: 暗い → 短い山（2.8）→ 通常（1）。
    static func crystalIgnition(_ t: Double) -> Float {
        let off: Float = 0.03
        if t < TowerTimeline.riseLockEnd { return off }
        if t >= TowerTimeline.riseEnd { return 1 }
        let k = Float((t - TowerTimeline.riseLockEnd) / (TowerTimeline.riseEnd - TowerTimeline.riseLockEnd))
        let base = off + (1 - off) * smooth(min(1, k / 0.2))
        let bump = k < 0.25 ? smooth(k / 0.25) : 1 - smooth((k - 0.25) / 0.75)
        return base + 1.8 * bump
    }

    // MARK: 塔の倒壊

    private static func destroyedTower(_ input: TowerPoseInput, e: Double, deathTime: Double) -> TowerPose {
        let g = input.geometry
        let T = CollapseTimes.of(input.style)
        let seed = input.seed
        var p = TowerPose()
        p.phase = e < T.crack ? .breaking : e < T.topple ? .toppling : e < T.impact ? .settling
            : e < T.hold ? .rubble : e < T.clear ? .clearing : .cleared
        // 基壇: 破断の衝撃で少し沈み、整理の間にさらに下がって破損基壇になる。紋様は最初の 0.1 秒で消える。
        // 根元（と根元へ崩れ落ちた上部）は基壇に載っているので一緒に下がる（基壇との間に隙間を作らない）
        let joltU = smooth(Float(clamp01((e - T.flash) / 0.12)))
        let lowered = smooth(Float(clamp01((e - T.hold) / (T.clear - T.hold))))
        let sink = translation([0, -0.03 * joltU - 0.12 * lowered, 0])
        p.plinth.matrix = sink
        p.lower.matrix = sink
        p.plinthGlow = e < 0.1 ? 1.7 : 0
        p.bodyGlow = e < 0.1 ? 1.4 : 0
        p.ruined = e >= T.flash
        if e >= T.clear {
            // 整理の後は破損基壇と根元だけ（毎フレームの計算もここまで）。根元へ崩れ落ちた上部は折れた根元の一部として残す
            // （切り口の平らな蓋だけが残ると箱に見える）
            p.upper.visible = g.cavesIn
            if g.cavesIn { p.upper.matrix = translation([0, -0.12 * lowered, 0]) * upperMatrix(g, e: T.topple, times: T, seed: seed) }
            p.crown.visible = false
            p.crystal.visible = false
            p.crystalGlow = 0
            return p
        }
        // 上部・頂部
        let upperM = upperMatrix(g, e: e, times: T, seed: seed)
        if g.plinth == nil && e >= T.topple {
            // 従来の 1 つのメッシュの塔は倒れ切った時には地面の下
            p.upper.visible = false
            p.crown.visible = false
        } else {
            p.upper.matrix = g.cavesIn ? translation([0, -0.12 * lowered, 0]) * upperM
                : clearChunk(upperM, box: g.upper, e: e, window: T.chunkClear)
            if let crown = g.crown {
                p.crown.matrix = clearChunk(crownMatrix(g, e: e, times: T, style: input.style, seed: seed), box: crown, e: e,
                                            window: T.chunkClear)
            } else {
                p.crown.visible = false
            }
        }
        // 結晶: 上部に付いたまま異常発光して震え、傾き始めて少しで割れる
        if e < T.shatter {
            p.crystal.matrix = crystalMatrixWhileBreaking(g, e: e, deathTime: deathTime, times: T, style: input.style, seed: seed)
            p.crystalGlow = e < T.flash ? 1 + 1.8 * smooth(Float(min(1, e / 0.08)))
                : (hash(seed, Int(floor(e * 14)) + 50) < 0.4 ? 1.7 : 2.8)
        } else {
            p.crystal.visible = false
            p.crystalGlow = 0
        }
        // 結晶片（割れて飛び、地面で止まる。整理で光の粒になって消える）
        if e >= T.shatter {
            let origin = shatterOrigin(g, deathTime: deathTime, times: T, style: input.style, seed: seed)
            let n = shardCount(core: false, style: input.style)
            p.shards.reserveCapacity(n)
            for k in 0..<n {
                var piece = ballistic(k: k, n: n, origin: origin, tau: e - T.shatter, seed: seed &+ 101,
                                      speed: (1.1, 2.2), up: (2.0, 3.0), floor: 0.1, spin: 9, size: 1)
                let w = T.shardClear
                let u = Float(clamp01((e - w.0) / (w.1 - w.0)))
                piece.opacity = 1 - smooth(u)
                piece.visible = e < w.1
                if u > 0 { piece.matrix = piece.matrix * scale(1 - 0.4 * smooth(u)) }
                p.shards.append(piece)
            }
        }
        // 小破片: 半分は破断線から（亀裂の区間）、半分は着地点から（着地の衝撃）。跳ね返らずに止まる
        let nd = debrisCount(core: false, style: input.style)
        if nd > 0 && e >= T.flash {
            let breakPoint = toppleFrame(g, seed: seed).pivot
            let landing = impactPoint(g, times: T, seed: seed)
            p.debris.reserveCapacity(nd)
            for k in 0..<nd {
                let first = k < nd / 2
                let launch = first ? T.flash + 0.06 * Double(k) : T.topple + 0.04 * Double(k - nd / 2)
                let size = 0.6 + 0.5 * Float(hash(seed &+ 211, k))
                guard e >= launch else {
                    p.debris.append(Piece(matrix: matrix_identity_float4x4, visible: false, opacity: 1))
                    continue
                }
                let a = Float(k) / Float(nd) * 6.283 + Float(hash(seed &+ 223, k)) * 0.8
                let from = first ? breakPoint + SIMD3(cos(a) * 0.3, 0, sin(a) * 0.3) : landing + SIMD3(cos(a) * 0.6, 0.3, sin(a) * 0.6)
                var piece = ballistic(k: k, n: nd, origin: from, tau: e - launch, seed: seed &+ 307,
                                      speed: first ? (0.6, 1.4) : (0.9, 1.9), up: first ? (0.6, 1.6) : (1.2, 2.2),
                                      floor: 0.08 * size, spin: 8, size: size)
                let w = T.debrisClear
                let u = Float(clamp01((e - w.0) / (w.1 - w.0)))
                if u > 0 {
                    // 少し縮みながら地面へ沈む（一度に消さない）
                    piece.matrix = translation([0, -0.3 * size * smooth(u), 0]) * piece.matrix * scale(1 - 0.3 * smooth(u))
                }
                piece.visible = e < w.1
                p.debris.append(piece)
            }
        }
        return p
    }

    /// 倒れる向き（奥 = 北 -z から個体ごとに北西か北東へ TowerGeometry.toppleYaw）・回転軸・支点（破断線の倒れる側の縁）。
    /// 真北へ倒すと、見下ろすカメラ（56°）では倒れた上部が画面の縦に伸びて「まだ立っている塔」に見えるので斜めにずらす。
    static func toppleFrame(_ g: TowerGeometry, seed: UInt64) -> (dir: SIMD3<Float>, axis: SIMD3<Float>, pivot: SIMD3<Float>) {
        let side: Float = hash(seed, 2) < 0.5 ? -1 : 1
        let y = g.toppleYaw
        let a = side * (y.lowerBound + (y.upperBound - y.lowerBound) * Float(hash(seed, 1)))
        let dir = SIMD3<Float>(sin(a), 0, -cos(a))
        let axis = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), dir))
        return (dir, axis, SIMD3(0, g.breakY, 0) + dir * g.breakRadius)
    }

    /// 支点まわりに倒す回転（angle > 0 で上端が dir の側へ）。
    static func toppleRotation(_ g: TowerGeometry, seed: UInt64, angle: Float) -> simd_float4x4 {
        let f = toppleFrame(g, seed: seed)
        return rotation(simd_quatf(angle: angle, axis: f.axis), about: f.pivot)
    }

    /// 倒壊中の上部の傾き（ラジアン）。亀裂で少し傾き、倒れ始めると重さで加速する。
    static func toppleAngle(_ g: TowerGeometry, e: Double, times T: CollapseTimes) -> Float {
        let lean = leanAngle(stage: 2) + 0.03 * smooth(Float(clamp01((e - T.flash) / 0.12)))
        guard e > T.crack else { return lean }
        let u = Float(clamp01((e - T.crack) / (T.topple - T.crack)))
        return lean + (g.toppleMax - lean) * u * u
    }

    /// 倒れ切った時に上部が地面に載るまで下げる量（外接箱の角で測り、角の分だけ少し埋める）。
    static func landingDrop(_ g: TowerGeometry, seed: UInt64) -> Float {
        let r = toppleRotation(g, seed: seed, angle: g.toppleMax)
        var lowest = Float.greatestFiniteMagnitude
        for c in g.upper.corners { lowest = min(lowest, transform(r, c).y) }
        return max(0, lowest + 0.2 * g.upper.width)
    }

    /// 倒れた上部が根元の縁から外へ滑り出る距離（m）。倒れ切った上部の外接箱が、根元の外接箱より倒れる側の外に
    /// 出るまで（根元に寄りかかった・めり込んだ姿にしない）。最低 0.35 m。
    static func landingSlide(_ g: TowerGeometry, seed: UInt64) -> Float {
        let f = toppleFrame(g, seed: seed)
        let r = toppleRotation(g, seed: seed, angle: g.toppleMax)
        var near = Float.greatestFiniteMagnitude
        for c in g.upper.corners {
            let p = transform(r, c)
            near = min(near, p.x * f.dir.x + p.z * f.dir.z)
        }
        var reach: Float = 0
        for c in (g.lower ?? g.upper).corners { reach = max(reach, c.x * f.dir.x + c.z * f.dir.z) }
        return max(0.35, reach + 0.1 - near)
    }

    static func upperMatrix(_ g: TowerGeometry, e: Double, times T: CollapseTimes, seed: UInt64) -> simd_float4x4 {
        var theta = toppleAngle(g, e: e, times: T)
        let joltU = smooth(Float(clamp01((e - T.flash) / 0.12)))
        var drop = 0.07 * joltU
        var slide = SIMD3<Float>(repeating: 0)
        if g.plinth == nil {
            // 基壇ごと 1 つのメッシュ（従来のモデル）: 横倒しにすると底面が見えるので、少し奥へ傾きながら地面へ崩れ沈む
            theta = leanAngle(stage: 2) + 0.03 * joltU
            if e > T.crack {
                let u = Float(clamp01((e - T.crack) / (T.topple - T.crack)))
                theta += 0.22 * u
                drop += (g.upper.max.y + 0.3) * u * u
            }
        } else if g.cavesIn {
            // 背の低い幅広の上部: 少し奥へ傾きながら根元の中へ半分ほど崩れ落ち、傾いた上半分が瓦礫として残る
            // （根元の壁が沈んだ下半分を隠す）。整理の後も折れた根元の一部として残る
            theta = leanAngle(stage: 2) + 0.03 * joltU
            if e > T.crack {
                let u = Float(clamp01((e - T.crack) / (T.topple - T.crack)))
                theta += 0.12 * u
                drop += (g.upper.extents.y * 0.55 - drop) * u * u
            }
        } else if e > T.crack {
            let u = Float(clamp01((e - T.crack) / (T.topple - T.crack)))
            let k = Float(clamp01(Double((u - 0.35) / 0.65)))
            drop += (landingDrop(g, seed: seed) - drop) * k * k
            // 落ちながら根元の縁から外へ滑り出る（根元に寄りかかった姿に見えないよう、着地点を根元から離す）
            slide = toppleFrame(g, seed: seed).dir * (landingSlide(g, seed: seed) * k * k)
        }
        // 亀裂の区間は破断線で小さく震える（次第に収まる）
        var jitter = SIMD3<Float>(repeating: 0)
        if e > T.flash && e < T.crack {
            let amp = 0.014 * (1 - Float((e - T.flash) / (T.crack - T.flash)))
            let n = Int(floor(e * 40))
            jitter = SIMD3(Float(hash(seed &+ 31, n)) - 0.5, 0, Float(hash(seed &+ 37, n)) - 0.5) * 2 * amp
        }
        return translation(jitter + slide + SIMD3(0, -drop, 0)) * toppleRotation(g, seed: seed, angle: theta)
    }

    /// 頂部: 外れるまでは上部と一体。外れた後は勢いのまま回りながら落ち、地面で止まる（通常版だけ）。
    static func crownMatrix(_ g: TowerGeometry, e: Double, times T: CollapseTimes, style: CollapseStyle,
                            seed: UInt64) -> simd_float4x4 {
        guard style == .full, let crown = g.crown, e > T.separate else { return upperMatrix(g, e: e, times: T, seed: seed) }
        let fall = crownFall(g, crown: crown, times: T, seed: seed)
        let tau = Float(min(e - T.separate, Double(fall.land)))
        let pos = fall.start + fall.velocity * tau + SIMD3(0, -0.5 * gravity * tau * tau, 0)
        let frame = toppleFrame(g, seed: seed)
        let spin = simd_float4x4(simd_quatf(angle: fall.omega * tau, axis: frame.axis))
        return translation(pos) * spin * fall.rotation * translation(-crown.center)
    }

    /// 頂部が外れる瞬間の位置・速度・向きと、地面に着くまでの秒。
    /// 外れた頂部は倒れた上部の先の半ばの脇（北寄りの側）へ転がり落ちる（上部に重なって隠れない）。
    /// 着地の向きは外れた時の傾きからさらに倒れた姿（背の高い頂部は 1.05〜1.45 rad、平たい頂部は 0.3〜0.4 rad）で、
    /// 外接箱の角が少し地面に埋まる高さで止まる。
    private static func crownFall(_ g: TowerGeometry, crown: PartBox, times T: CollapseTimes, seed: UInt64)
        -> (start: SIMD3<Float>, velocity: SIMD3<Float>, rotation: simd_float4x4, omega: Float, land: Float) {
        let frame = toppleFrame(g, seed: seed)
        let ms = upperMatrix(g, e: T.separate, times: T, seed: seed)
        let c = crown.center
        let start = transform(ms, c)
        var rot = ms
        rot.columns.3 = SIMD4(0, 0, 0, 1)
        // 着地の向き（背の高い頂部は横倒し、平たい頂部 = 内塔の光輪・基地塔の胸壁は少し傾いた程度。立った壁にしない）と、
        // その向きで外接箱の下端が地面から少し埋まる中心の高さ
        let tall = min(1, max(0, (crown.extents.y / max(0.01, (crown.extents.x + crown.extents.z) / 2) - 0.6) / 0.4))
        let turn: Float = (0.3 + 0.75 * tall) + (0.1 + 0.3 * tall) * Float(hash(seed &+ 71, 0))
        let final = simd_float4x4(simd_quatf(angle: turn, axis: frame.axis)) * rot
        var low: Float = 0
        for k in crown.corners { low = min(low, transform(final, k - c).y) }
        let floor = max(0.1, -low - 0.12 * crown.width)
        // 着地点: 倒れ切った上部の外接箱の、倒れる向きの先の半ば・脇の外（上部が根元へ崩れ落ちる塔は根元の先）
        var side = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), frame.dir))
        if side.z > 0 { side = -side }
        let half = max(crown.extents.x, crown.extents.z) * 0.4
        let target: SIMD3<Float>
        if g.cavesIn {
            var reach: Float = 0
            for k in (g.lower ?? g.upper).corners { reach = max(reach, k.x * frame.dir.x + k.z * frame.dir.z) }
            target = frame.dir * (reach + half + 0.15) + side * 0.3
        } else {
            let landed = upperMatrix(g, e: T.topple, times: T, seed: seed)
            var far: Float = -.greatestFiniteMagnitude, near: Float = .greatestFiniteMagnitude, wide: Float = 0
            for k in g.upper.corners {
                let p = transform(landed, k)
                let along = p.x * frame.dir.x + p.z * frame.dir.z
                far = max(far, along)
                near = min(near, along)
                wide = max(wide, p.x * side.x + p.z * side.z)
            }
            target = frame.dir * (near + (far - near) * 0.7) + side * (wide + half + 0.1)
        }
        let vy: Float = 0.8
        let land = landingTime(y0: start.y - floor, vy: vy)
        var v = SIMD3<Float>((target.x - start.x) / land, vy, (target.z - start.z) / land)
        // 横の勢いの上限（飛びすぎない）
        let hl = simd_length(SIMD2(v.x, v.z))
        if hl > 5 {
            v.x *= 5 / hl
            v.z *= 5 / hl
        }
        return (start, v, rot, turn / land, land)
    }

    /// 高さ y0（着地面からの高さ）・上向きの速度 vy で投げた物が着地面に着くまでの秒。
    static func landingTime(y0: Float, vy: Float) -> Float {
        let y = max(0, y0)
        return (vy + (vy * vy + 2 * gravity * y).squareRoot()) / gravity
    }

    /// 上部の着地点（地面上の中心）。
    static func impactPoint(_ g: TowerGeometry, times T: CollapseTimes, seed: UInt64) -> SIMD3<Float> {
        let p = transform(upperMatrix(g, e: T.topple, times: T, seed: seed), g.upper.center)
        return SIMD3(p.x, 0, p.z)
    }

    /// 頂部の着地の時刻（deathTime から。通常版の頂部がある時だけ）。
    static func crownLandTime(_ g: TowerGeometry, times T: CollapseTimes, seed: UInt64) -> Double? {
        guard let crown = g.crown else { return nil }
        return T.separate + Double(crownFall(g, crown: crown, times: T, seed: seed).land)
    }

    /// 大きな石の整理: 少し縮みながら地面へ沈み切る（全体を一様に薄くしない・急に縮めない）。
    private static func clearChunk(_ m: simd_float4x4, box: PartBox, e: Double, window w: (Double, Double)) -> simd_float4x4 {
        let u = Float(clamp01((e - w.0) / (w.1 - w.0)))
        guard u > 0 else { return m }
        let c = transform(m, box.center)
        let depth = max(box.extents.x, box.extents.y, box.extents.z) * 0.75
        let k = u * u * (3 - 2 * u)
        return translation([0, -depth * k, 0]) * translation(c) * scale(1 - 0.15 * k) * translation(-c) * m
    }

    private static func crystalHost(_ g: TowerGeometry, e: Double, times T: CollapseTimes, style: CollapseStyle,
                                    seed: UInt64) -> simd_float4x4 {
        g.crown != nil ? crownMatrix(g, e: e, times: T, style: style, seed: seed) : upperMatrix(g, e: e, times: T, seed: seed)
    }

    private static func crystalMatrixWhileBreaking(_ g: TowerGeometry, e: Double, deathTime: Double, times T: CollapseTimes,
                                                   style: CollapseStyle, seed: UInt64) -> simd_float4x4 {
        let n = Int(floor(e * 30))
        let amp: Float = e < T.flash ? 0.02 : 0.035
        let j = SIMD3(Float(hash(seed &+ 41, n)) - 0.5, Float(hash(seed &+ 43, n)) - 0.5, Float(hash(seed &+ 47, n)) - 0.5)
            * 2 * amp
        let c = g.crystal.center
        let spin = Float(deathTime.truncatingRemainder(dividingBy: 3600)) * 0.5
        return translation(j) * crystalHost(g, e: e, times: T, style: style, seed: seed) * translation(c) * rotationY(spin)
            * translation(-c)
    }

    /// 結晶が割れる位置（その瞬間の結晶の中心）。
    static func shatterOrigin(_ g: TowerGeometry, deathTime: Double, times T: CollapseTimes, style: CollapseStyle,
                              seed: UInt64) -> SIMD3<Float> {
        transform(crystalHost(g, e: T.shatter, times: T, style: style, seed: seed), g.crystal.center)
    }

    // MARK: Core の崩壊

    private static func destroyedCore(_ input: TowerPoseInput, e: Double, deathTime: Double) -> TowerPose {
        let g = input.geometry
        let seed = input.seed
        var p = TowerPose()
        p.phase = e < CoreCollapse.overloadEnd ? .breaking : e < CoreCollapse.archesLand ? .toppling
            : e < CoreCollapse.settled ? .settling : .rubble
        let flick = hash(seed, Int(floor(e * 12)) + 90) < 0.45
        // 基壇の紋様: 過負荷で明滅 → 結晶が割れると消える
        p.plinthGlow = e < CoreCollapse.overloadEnd ? (flick ? 1.7 : 2.8) : e < CoreCollapse.implodeStart ? (flick ? 0.65 : 1.0) : 0
        p.ruined = e >= CoreCollapse.implodeEnd
        // 石柱・弧（上部）: 過負荷で小さく震え、外へ広がりながら崩れ落ちる
        var upper = matrix_identity_float4x4
        if e < CoreCollapse.overloadEnd {
            let n = Int(floor(e * 40))
            let amp: Float = 0.012 * Float(e / CoreCollapse.overloadEnd)
            upper = translation(SIMD3(Float(hash(seed &+ 51, n)) - 0.5, 0, Float(hash(seed &+ 53, n)) - 0.5) * 2 * amp)
        } else {
            let u = Float(clamp01((e - CoreCollapse.overloadEnd) / (CoreCollapse.archesLand - CoreCollapse.overloadEnd)))
            let sink = (g.upper.max.y - g.plinthTop) * 0.72 * u * u
            let spread = 1 + 0.18 * u * u
            upper = translation([0, -sink, 0]) * scale([spread, 1, spread])
        }
        p.upper.matrix = upper
        p.bodyGlow = e < CoreCollapse.overloadEnd ? 2.0 * (1 - Float(e / CoreCollapse.overloadEnd)) : 0
        p.crown.visible = false
        p.lower.visible = g.lower != nil
        // 大結晶: 過負荷（明るく速く回り震える）→ 少し浮き上がる → 縮んで割れる（光の柱）→ 消える
        let c = g.crystal.center
        if e < CoreCollapse.implodeEnd {
            let n = Int(floor(e * 30))
            let amp: Float = 0.03 + 0.05 * Float(min(1, e / CoreCollapse.implodeStart))
            let j = SIMD3(Float(hash(seed &+ 61, n)) - 0.5, Float(hash(seed &+ 63, n)) - 0.5, Float(hash(seed &+ 67, n)) - 0.5)
                * 2 * amp
            let lift = g.crystalLift
                + 0.5 * smooth(Float(clamp01((e - CoreCollapse.overloadEnd) / (CoreCollapse.implodeStart - CoreCollapse.overloadEnd))))
            let base = Float(deathTime.truncatingRemainder(dividingBy: 3600)) * 0.3
            let spin = base + Float(e * e) * 1.6
            let ku = Float(clamp01((e - CoreCollapse.implodeStart) / (CoreCollapse.implodeEnd - CoreCollapse.implodeStart)))
            let s = 1 - 0.88 * ku * ku
            p.crystal.matrix = translation(j + SIMD3(0, lift, 0)) * translation(c) * rotationY(spin) * scale(s) * translation(-c)
            p.crystalGlow = e < CoreCollapse.overloadEnd ? 1 + 1.8 * smooth(Float(e / 0.15)).clamped01 : (flick ? 2.2 : 2.8)
        } else {
            p.crystal.visible = false
            p.crystalGlow = 0
        }
        // 光の柱（割れる瞬間に立ち、細って消える）
        if e >= CoreCollapse.implodeStart && e < CoreCollapse.columnEnd {
            let up = smooth(Float(clamp01((e - CoreCollapse.implodeStart) / 0.25)))
            let down = 1 - smooth(Float(clamp01((e - 2.8) / (CoreCollapse.columnEnd - 2.8))))
            p.column = up * down
        }
        // 結晶片（割れた瞬間に外へ飛び、地面で止まる）
        if e >= CoreCollapse.implodeEnd {
            let origin = c + SIMD3(0, 0.5, 0)
            let n = shardCount(core: true, style: .full)
            p.shards.reserveCapacity(n)
            for k in 0..<n {
                p.shards.append(ballistic(k: k, n: n, origin: origin, tau: e - CoreCollapse.implodeEnd, seed: seed &+ 401,
                                          speed: (2.4, 3.8), up: (3.0, 4.2), floor: 0.15, spin: 7, size: 1.6))
            }
        }
        // 石柱の欠片（外へ崩れる）
        let nd = debrisCount(core: true, style: .full)
        if e >= CoreCollapse.overloadEnd + 0.15 {
            p.debris.reserveCapacity(nd)
            for k in 0..<nd {
                let launch = CoreCollapse.overloadEnd + 0.15 + 0.05 * Double(k)
                let size = 1.0 + 0.6 * Float(hash(seed &+ 503, k))
                guard e >= launch else {
                    p.debris.append(Piece(matrix: matrix_identity_float4x4, visible: false, opacity: 1))
                    continue
                }
                let a = Float(k) / Float(nd) * 6.283 + Float(hash(seed &+ 509, k)) * 0.4
                let from = SIMD3(cos(a) * g.breakRadius, g.plinthTop + 0.6 + Float(hash(seed &+ 521, k)) * 1.0, -sin(a) * g.breakRadius)
                p.debris.append(ballistic(k: k, n: nd, origin: from, tau: e - launch, seed: seed &+ 601, speed: (1.6, 3.0),
                                          up: (1.4, 2.6), floor: 0.1 * size, spin: 6, size: size, outward: a))
            }
        }
        return p
    }

    // MARK: 破片の放物運動（跳ね返らずに着地で止まる）

    /// k 番目の破片: origin から外向き（角度は k で均等 + 揺らぎ）に投げ、重力で落ちて着地したら止まる。回転も着地で止まる。
    private static func ballistic(k: Int, n: Int, origin: SIMD3<Float>, tau: Double, seed: UInt64, speed: (Float, Float),
                                  up: (Float, Float), floor: Float, spin: Float, size: Float, outward: Float? = nil) -> Piece {
        let a = outward ?? (Float(k) / Float(max(1, n)) * 6.283 + Float(hash(seed, k)) * 0.9)
        let hs = speed.0 + (speed.1 - speed.0) * Float(hash(seed &+ 1, k))
        let vy = up.0 + (up.1 - up.0) * Float(hash(seed &+ 2, k))
        let v = SIMD3<Float>(cos(a) * hs, vy, -sin(a) * hs)
        let land = landingTime(y0: origin.y - floor, vy: vy)
        let t = min(Float(max(0, tau)), land)
        var pos = origin + v * t + SIMD3(0, -0.5 * gravity * t * t, 0)
        pos.y = max(pos.y, floor)
        let axis = simd_normalize(SIMD3(Float(hash(seed &+ 3, k)) - 0.5, Float(hash(seed &+ 4, k)) - 0.5, Float(hash(seed &+ 5, k)) + 0.1))
        let rest = Float(hash(seed &+ 6, k)) * 6.283
        let m = translation(pos) * simd_float4x4(simd_quatf(angle: rest + spin * t, axis: axis)) * scale(size)
        return Piece(matrix: m, visible: true, opacity: 1)
    }

    // MARK: 合図

    /// prev < 時刻 ≤ now に入った合図（時刻順）。prev >= now なら空。
    static func cues(_ input: TowerPoseInput, from prev: Double, to now: Double) -> [TowerCueEvent] {
        guard now > prev else { return [] }
        let g = input.geometry
        var out: [TowerCueEvent] = []
        func add(_ cue: TowerCue, _ t: Double, _ p: SIMD3<Float>) {
            if t > prev && t <= now { out.append(TowerCueEvent(cue: cue, time: t, position: p)) }
        }
        let alive = input.deathTime == nil
        // 立ち上がり（壊れた後には出さない）
        if prev < TowerTimeline.riseEnd {
            let before = { (t: Double) in input.deathTime.map { t < $0 } ?? true }
            if before(0.05) { add(.riseStart, 0.05, [0, g.plinthTop, 0]) }
            if before(lockTime) { add(.riseLock, lockTime, g.crown?.center ?? [0, g.upper.max.y, 0]) }
            if before(TowerTimeline.riseLockEnd + 0.05) { add(.crystalIgnite, TowerTimeline.riseLockEnd + 0.05, g.crystal.center) }
        }
        // 損傷 2 段階の魔力漏れ（一定間隔。個体ごとにずらす）
        if !g.isCore && TowerTimeline.damageStage(hpRatio: input.hpRatio) >= 2 {
            let period = 2.9
            let ph = hash(input.seed, 13) * period
            var k = floor((prev - ph) / period) + 1
            while true {
                let t = ph + k * period
                if t > now { break }
                if t >= TowerTimeline.riseEnd && (input.deathTime.map { t < $0 } ?? true) {
                    add(.wisp, t, g.crystal.center - SIMD3(0, 0.3, 0))
                }
                k += 1
            }
        }
        guard !alive, let d = input.deathTime else { return out }
        if g.isCore {
            let c = g.crystal.center
            add(.coreOverload, d, c)
            add(.coreArchesFall, d + CoreCollapse.overloadEnd, [0, g.plinthTop, 0])
            add(.coreArchesImpact, d + CoreCollapse.archesLand, [0, 0, 0])
            add(.coreImplode, d + CoreCollapse.implodeStart, c + SIMD3(0, 0.5, 0))
            add(.coreShockwave, d + CoreCollapse.shockwave, [0, 0, 0])
            add(.coreSettle, d + CoreCollapse.settleCue, [0, 0, 0])
            if out.count > 1 { out.sort { $0.time < $1.time } }
            return out
        }
        let T = CollapseTimes.of(input.style)
        let seed = input.seed
        // 時刻が窓に入る合図だけ位置を求める（位置の計算は姿勢の評価と同じ式）
        func inWindow(_ t: Double) -> Bool { t > prev && t <= now }
        let breakPoint = toppleFrame(g, seed: seed).pivot
        if inWindow(d) {
            let lean = toppleRotation(g, seed: seed, angle: leanAngle(stage: 2))
            add(.breakFlash, d, transform(lean, g.crystal.center))
        }
        if input.style == .full {
            add(.crack, d + T.flash + 0.05, breakPoint)
            add(.toppleStart, d + T.crack, breakPoint + SIMD3(0, 0.6, 0))
        }
        if inWindow(d + T.shatter) {
            add(.crystalShatter, d + T.shatter, shatterOrigin(g, deathTime: d, times: T, style: input.style, seed: seed))
        }
        if input.style == .full, let crown = g.crown {
            if inWindow(d + T.separate) {
                add(.separate, d + T.separate, transform(upperMatrix(g, e: T.separate, times: T, seed: seed), crown.center))
            }
            if let land = crownLandTime(g, times: T, seed: seed), inWindow(d + land) {
                let p = transform(crownMatrix(g, e: land, times: T, style: .full, seed: seed), crown.center)
                add(.crownImpact, d + land, SIMD3(p.x, 0, p.z))
            }
        }
        if inWindow(d + T.topple) { add(.impact, d + T.topple, impactPoint(g, times: T, seed: seed)) }
        if input.style == .full { add(.clearDebris, d + T.debrisClear.0, breakPoint * SIMD3(1, 0, 1)) }
        if inWindow(d + T.shardClear.0) {
            add(.crystalFade, d + T.shardClear.0, impactPoint(g, times: T, seed: seed) + SIMD3(0, 0.3, 0))
        }
        if inWindow(d + T.chunkClear.0) { add(.crumble, d + T.chunkClear.0, impactPoint(g, times: T, seed: seed)) }
        if out.count > 1 { out.sort { $0.time < $1.time } }
        return out
    }

    /// 同時に倒れる塔の数の上限: 自分より先に倒れ始めて（同時刻は ID の小さい方が先）、まだ着地していない塔が
    /// 上限以上なら短縮版。破壊の時刻だけで決まるので、途中から見ても同じ版になる。
    static func collapseStyle(id: EntityID, deathTime d: Double, others: [(deathTime: Double, id: EntityID)]) -> CollapseStyle {
        var earlier = 0
        for o in others where o.id != id {
            let before = o.deathTime < d || (o.deathTime == d && o.id < id)
            if before && d - o.deathTime < CollapseTimes.full.topple { earlier += 1 }
        }
        return earlier >= TowerTimeline.maxConcurrentCollapses ? .short : .full
    }

    // MARK: 数学

    static func hash(_ seed: UInt64, _ k: Int) -> Double {
        var x = seed &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(bitPattern: Int64(k)) &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 30
        x = x &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 27
        x = x &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x >> 11) / Double(1 << 53)
    }

    static func clamp01(_ x: Double) -> Double { x < 0 ? 0 : x > 1 ? 1 : x }
    static func smooth(_ x: Float) -> Float { let u = min(1, max(0, x)); return u * u * (3 - 2 * u) }
    static func smoother(_ x: Float) -> Float { let u = min(1, max(0, x)); return u * u * u * (u * (u * 6 - 15) + 10) }

    static func translation(_ v: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(v.x, v.y, v.z, 1)
        return m
    }

    static func scale(_ k: Float) -> simd_float4x4 { scale(SIMD3(repeating: k)) }
    static func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(s.x, s.y, s.z, 1))
    }

    static func rotationY(_ a: Float, about c: SIMD3<Float>? = nil) -> simd_float4x4 {
        let r = simd_float4x4(simd_quatf(angle: a, axis: [0, 1, 0]))
        guard let c else { return r }
        return translation(c) * r * translation(-c)
    }

    static func rotation(_ q: simd_quatf, about p: SIMD3<Float>) -> simd_float4x4 {
        translation(p) * simd_float4x4(q) * translation(-p)
    }

    static func transform(_ m: simd_float4x4, _ p: SIMD3<Float>) -> SIMD3<Float> {
        let v = m * SIMD4(p, 1)
        return SIMD3(v.x, v.y, v.z)
    }
}

private extension Float {
    var smoothed: Float { TowerPose.smooth(self) }
    var clamped01: Float { Swift.min(1, Swift.max(0, self)) }
}
