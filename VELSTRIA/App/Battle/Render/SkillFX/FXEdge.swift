import Foundation

// 担当: battle-renderer（スキル演出）。演出の部品の「見える縁」と、板・形の大きさの比（画像の余白・形の内径の補正）。
// 判定の縁（sim の円・扇・線の幅）と演出の縁を合わせるための表（docs/vfx/RANGES.md「縁の決め方」）。
//
// 見える縁の決め方: 画像の不透明度の輪郭（円い模様は円周の平均、横長の模様は横の最大）が、その画像の最大の 1/3 以上に
// なる最も外の位置。細い輪（ring）の外の淡いにじみ（0.25）は縁に入れず、輪の線の外側が縁になる。
// 値は FXTextures.swift の描き方から計算した（線の幅は中心から ±半分）。AppTests/SkillFXRangeTests が実際の画像を
// 標本化して、表との差が 1 画素以内であることを確かめる（描き方を変えたら表も直す）。
//   円い模様の半径（板の一辺に対する比。板の端 = 0.5）:
//     ring       0.44 + 0.035 / 2 = 0.4575       ringDouble 0.44 + 0.03 / 2 = 0.455
//     shockwave  外縁 0.94 → 1.0（板の半分に対する比）を 1 → 0 で薄れる。1/3 は 0.98 → 0.49
//     runeCircle 0.47 + 0.012 / 2 = 0.476         techCircle 0.46 + 0.016 / 2 = 0.468
//     clockFace  0.46 + 0.018 / 2 = 0.469         hexShield  0.47 + 0.02 / 2 = 0.48
//     bubble     0.42 + 0.04 / 2 = 0.44           ripple     最も外の 0.47（不透明度 0.4 ≧ 1/3）+ 0.02 / 2 = 0.48
//     flameRing  tools/effekseer/textures_kit.py の画像を同じ測り方で測った 0.4785（舌の先 0.5）  thinRing 同じく 0.4805
//   横長の模様の半幅（板の縦に対する比。ray・鎖のように板を 90° 回して横を前へ向けたときの横幅）:
//     chain      輪の高さ 0.18 / 2 + 線 0.035 / 2 = 0.1075   streak 楕円の高さ 0.16 / 2 = 0.08
//     arrow      矢じり 0.11                                 slashLine 中央の光 0.12 × (1 − 0.33 / 0.9) = 0.076
//     thread     波 0.12 + 線 0.03 / 2 = 0.135
//     bolt       枝（不透明度 0.75）の先 0.227 + 線 0.008 / 2 = 0.231（決まった乱数の折れ線。主幹の振れは 0.168 + 0.03 = 0.198）
//     soundWave  弧の端 0.47 × sin 0.7 = 0.303 + 丸い線端 0.03 / 2 = 0.318
//     moon       三日月の上下の端（外の楕円 0.1〜0.9）= 0.4（鉤の頭のように板を回して横幅に使う）
//   帯（band・arc）の見える外縁: 形の外径 1（画像の下 v = 0 が外縁）。beam は下端が最も明るいので外径のまま。
//   弧（arc）は前方 ±90° の形だが、beam の横の明るさ pow(sin πu, 0.6) は端の 5% が 1/3 に届かないので、見える開きは ±81°。
//   円柱（cylinder・funnel・spire）・半球・球: 形の下端の半径（size.x）。
//   Blender の模型: 衝撃の輪（ringLip）は外縁の半径（size.x）。ほかの模型（三日月・竜巻・光の柱・渦の刃・炎の球・四芒星の盤・
//   岩板の輪）は範囲を示さない飾り。

enum FXEdge {
    /// 縁の閾値（画像の最大の不透明度に対する比）。
    static let threshold: Float = 1.0 / 3

    /// 地面に寝かせた円い模様の見える縁の半径 / 板の一辺。nil = 範囲を示さない模様（光・ひび・粒・形のある絵）。
    static func radial(_ t: FXTex) -> Float? {
        switch t {
        case .ring: return 0.4575
        case .ringDouble: return 0.455
        case .shockwave: return 0.49
        case .runeCircle: return 0.476
        case .techCircle: return 0.468
        case .clockFace: return 0.469
        case .hexShield: return 0.48
        case .bubble: return 0.44
        case .ripple: return 0.48
        // 炎の舌の輪（帯の外縁 0.45 から舌の先 0.5 まで。円周の平均が 1/3 になるのは 0.4785。舌の先はその 1.045 倍）
        case .flameRing: return 0.4785
        // 細い輪（線の中心 0.475・幅 0.005）
        case .thinRing: return 0.4805
        default: return nil
        }
    }

    /// 横長の模様の見える半幅 / 板の縦（画像の上下の端）。nil = 横長でない。
    static func linearHalfWidth(_ t: FXTex) -> Float? {
        switch t {
        case .chain: return 0.1075
        case .streak: return 0.08
        case .arrow: return 0.11
        case .slashLine: return 0.076
        case .thread: return 0.135
        case .bolt: return 0.231
        case .soundWave: return 0.318
        case .moon: return 0.4
        // 彗星の柔らかい光（Blender の fx_comet_glow。横は (1 − (d / 0.5)²)^1.07 の 1/3 = 0.402。256 px の画像を同じ測り方で測った値）
        case .cometGlow: return 0.402
        default: return nil
        }
    }

    /// 横長の模様の見える長さの半分 / 板の横（画像の左右の端。どれも板のほぼ全幅に描く）。
    static let linearHalfLength: Float = 0.49

    /// 横長の模様の見える左右の端（板の中心から、板の横に対する比）。三日月（moon）は外の楕円の左端 0.1 と、二つの楕円の
    /// 交わる先端 0.79（画像の座標）= −0.4〜+0.29。ほかは ±linearHalfLength。
    static func linearExtentX(_ t: FXTex) -> (lo: Float, hi: Float) {
        t == .moon ? (-0.4, 0.29) : (-linearHalfLength, linearHalfLength)
    }

    /// 帯（band）の内径 / 外径・弧（arc）の内径 / 外径（FXMeshes.swift）。
    static func shapeInner(_ s: FXShape) -> Float {
        switch s {
        case .band: return 0.8
        case .arc: return 0.72
        default: return 0
        }
    }

    /// 弧（arc）の見える半角（度）。形は前方 ±90°、beam の横の明るさは端の 5% が閾値に届かない（pow(sin πu, 0.6) < 1/3）。
    static let arcHalfSpan: Float = 90 * 0.9

    // MARK: - 地面の上の見える縁（上から見た輪郭）

    /// 上から見た部品の見える縁の輪郭（部品の局所座標の m: x = 右、y = 前。部品の位置が原点、向きの回転の前）。
    /// 範囲を示せる部品だけ（円い模様・横長の模様の板、帯・弧、円柱などの下端の輪）。それ以外（光・ひび・粒・立てた板の絵）は nil。
    /// size は今の大きさ（右・上・前）。points = 輪郭の標本の数。
    static func outline(_ m: FXMesh, size: SIMD3<Float>, points n: Int = 72) -> [SIMD2<Float>]? {
        switch m.shape {
        case .disc:
            guard let tex = m.tex else { return nil }
            if let k = radial(tex) { return ellipse(rx: k * size.x, ry: k * size.z, from: -180, to: 180, n) }
            if let k = linearHalfWidth(tex) {
                let x = linearExtentX(tex)
                return rect(x0: x.lo * size.x, x1: x.hi * size.x, hy: k * size.z, n)
            }
            return nil
        case .band, .cylinder, .funnel, .spire, .dome, .sphere:
            // 下端（地面）の輪。漏斗の下端は 0.35 倍、尖塔は 1 倍（FXMeshes.swift）
            let base: Float = m.shape == .funnel ? 0.35 : 1
            return ellipse(rx: base * size.x, ry: base * size.z, from: -180, to: 180, n)
        case .arc:
            return ellipse(rx: size.x, ry: size.z, from: -arcHalfSpan, to: arcHalfSpan, n)
        case .wall:
            // 前を向いて立つ板の足元の線（範囲の縁としては横幅だけ。円い模様なら縁の半径、横長なら長さの半分）
            guard let tex = m.tex else { return nil }
            let k = radial(tex) ?? (linearHalfWidth(tex) != nil ? linearHalfLength : nil)
            guard let k else { return nil }
            return [[-k * size.x, 0], [k * size.x, 0]]
        case .billboard:
            return nil
        case .ringLip:
            // Blender の衝撃の輪（外径 1 の外縁が見える縁。画像なしの単色）
            return ellipse(rx: size.x, ry: size.z, from: -180, to: 180, n)
        case .crescent, .twister, .pillar2, .bladeRing, .burstDome, .starCross, .shardRing:
            // Blender の模型の飾り（斬撃の三日月・竜巻・光の柱・渦の刃・炎の球・四芒星の盤・岩板）。範囲を示さない
            return nil
        }
    }

    /// 楕円の弧（前 = 0°、左 = +90°。from → to 度）。
    private static func ellipse(rx: Float, ry: Float, from a0: Float, to a1: Float, _ n: Int) -> [SIMD2<Float>] {
        let count = max(2, n)
        return (0..<count).map { i -> SIMD2<Float> in
            let progress = Float(i) / Float(count - 1)
            let degrees: Float = a0 + (a1 - a0) * progress
            let radians: Float = degrees * Float.pi / 180
            return SIMD2<Float>(-rx * sin(radians), ry * cos(radians))
        }
    }

    /// 長方形の周（横 x0〜x1、縦 ±hy）。
    private static func rect(x0: Float, x1: Float, hy: Float, _ n: Int) -> [SIMD2<Float>] {
        let side = max(1, n / 4)
        var out: [SIMD2<Float>] = []
        for i in 0..<side {
            let u = Float(i) / Float(side)
            let x = x0 + (x1 - x0) * u
            let y = -hy + 2 * hy * u
            out += [[x, hy], [x1, y], [x1 - (x1 - x0) * u, -hy], [x0, -y]]
        }
        return out
    }
}

// MARK: - 時刻ごとの大きさ・不透明度（SkillFXPlayer.apply と同じ式。範囲の検査も同じ式で測る）

extension FXMesh {
    /// 寿命に対する経過 t（0〜1）の大きさ（右・上・前）。
    func size(at t: Float) -> SIMD3<Float> {
        size + (sizeEnd - size) * ease.apply(t)
    }

    /// 寿命に対する経過 t（0〜1）の不透明度（alpha を掛けた値。fadeIn まで立ち上がり、fadeOut から 0 へ）。
    func opacity(at t: Float) -> Float {
        var a: Float = 1
        if t < fadeIn { a = t / max(0.001, fadeIn) }
        if t > fadeOut { a = min(a, 1 - (t - fadeOut) / max(0.001, 1 - fadeOut)) }
        return max(0, min(1, a * alpha))
    }

    /// 寿命に対する経過 t（0〜1）の向き（度。yaw → yawEnd の掃き + 回転速度）。
    func yawDegrees(at t: Float) -> Float {
        var y = yaw
        if let end = yawEnd { y = yaw + (end - yaw) * ease.apply(t) }
        return y + spin * t * life
    }
}
