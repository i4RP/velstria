#!/usr/bin/env swift
// VELSTRIA アプリアイコン / 起動ロゴ生成スクリプト（CoreGraphics・外部依存なし）。
//
// usage（リポジトリの VELSTRIA/ で）:
//   swift tools/make_icon.swift            # アセットカタログへ書き出し
//   swift tools/make_icon.swift --preview /tmp/icon-preview   # 追加で確認用の縮小・角丸プレビューを出力
//
// 出力:
//   App/Resources/Assets.xcassets/AppIcon.appiconset/  AppIcon-1024.png（不透明・角丸なし）
//                                                      AppIcon-Dark-1024.png / AppIcon-Tinted-1024.png
//   App/Resources/Assets.xcassets/LaunchLogo.imageset/ LaunchLogo.png / @2x / @3x（透過）
//
// 乱数は固定シードの SplitMix64 なので、何度実行しても同じ画像になる。

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - 基本

/// デザイン座標は 1024×1024・y 下向き。出力解像度へは CTM で拡縮する。
let design: CGFloat = 1024

struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> CGFloat { CGFloat(Double(next() >> 11) / Double(1 << 53)) }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * unit() }
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [r, g, b, a])!
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
    var length: CGFloat { (x * x + y * y).squareRoot() }
    var normalized: CGPoint { self * (1 / length) }
    /// 右手系の法線（y 下向き座標で左側）。
    var perp: CGPoint { CGPoint(x: -y, y: x) }
}

/// 描画キャンバス。`scale` = 出力ピクセル / デザイン単位（影のぼかしはデバイス空間なので掛ける）。
struct Canvas {
    let ctx: CGContext
    let scale: CGFloat
    let pixels: Int

    init(pixels: Int, opaque: Bool) {
        let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: info)!
        self.pixels = pixels
        scale = CGFloat(pixels) / design
        ctx.translateBy(x: 0, y: CGFloat(pixels))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
    }

    func glow(_ blur: CGFloat, _ color: CGColor) {
        ctx.setShadow(offset: .zero, blur: blur * scale, color: color)
    }

    /// デバイス座標のグレースケール画像をアルファマスクにして `body` を描く。
    func masked(by mask: CGImage, _ body: () -> Void) {
        ctx.saveGState()
        let m = ctx.ctm
        ctx.concatenate(m.inverted())
        ctx.clip(to: CGRect(x: 0, y: 0, width: pixels, height: pixels), mask: mask)
        ctx.concatenate(m)
        body()
        ctx.restoreGState()
    }

    func image() -> CGImage { ctx.makeImage()! }
}

// MARK: - 背景（藍 → 紫の放射グラデーション + 星雲 + 星屑）

func drawBackground(_ c: Canvas) {
    let ctx = c.ctx
    let bg = gradient([
        (0.00, rgba(0.46, 0.22, 0.74)),
        (0.30, rgba(0.26, 0.12, 0.54)),
        (0.62, rgba(0.10, 0.06, 0.30)),
        (1.00, rgba(0.02, 0.02, 0.09)),
    ])
    ctx.drawRadialGradient(bg, startCenter: CGPoint(x: 512, y: 440), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 500), endRadius: 800,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // 星雲（スクリーン合成の淡い色だまり）
    ctx.saveGState()
    ctx.setBlendMode(.screen)
    let nebulae: [(CGPoint, CGFloat, CGColor)] = [
        (CGPoint(x: 250, y: 260), 360, rgba(0.70, 0.22, 0.78, 0.30)),
        (CGPoint(x: 820, y: 780), 380, rgba(0.16, 0.52, 0.92, 0.26)),
        (CGPoint(x: 820, y: 200), 260, rgba(0.36, 0.30, 0.95, 0.20)),
        (CGPoint(x: 180, y: 840), 280, rgba(0.30, 0.16, 0.70, 0.22)),
    ]
    for (p, r, col) in nebulae {
        let g = gradient([(0, col), (1, col.copy(alpha: 0)!)])
        ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
    }
    ctx.restoreGState()

    // 周辺減光
    let vignette = gradient([(0.0, rgba(0, 0, 0, 0)), (0.72, rgba(0, 0, 0, 0)), (1.0, rgba(0, 0, 0, 0.55))])
    ctx.drawRadialGradient(vignette, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 512), endRadius: 740, options: [.drawsAfterEndLocation])
}

/// シアン系の星屑。`count` で数を調整（ダーク版は控えめ）。
func drawStarDust(_ c: Canvas, seed: UInt64, count: Int) {
    let ctx = c.ctx
    var rng = SplitMix64(state: seed)
    for _ in 0..<count {
        let p = CGPoint(x: rng.range(20, 1004), y: rng.range(20, 1004))
        let r = rng.range(0.9, 3.4)
        let a = rng.range(0.35, 0.95)
        let warm = rng.unit() < 0.18
        let col = warm ? rgba(1.0, 0.90, 0.70, a) : rgba(rng.range(0.55, 0.85), rng.range(0.88, 1.0), 1.0, a)
        ctx.saveGState()
        if r > 2.4 { c.glow(10, col) }
        ctx.setFillColor(col)
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.restoreGState()
    }
    // 大きめのきらめき（4 芒星）
    let sparkles: [(CGPoint, CGFloat)] = [
        (CGPoint(x: 178, y: 214), 26), (CGPoint(x: 858, y: 318), 20), (CGPoint(x: 872, y: 862), 24),
        (CGPoint(x: 150, y: 690), 16), (CGPoint(x: 640, y: 120), 14), (CGPoint(x: 330, y: 905), 15),
    ]
    for (p, r) in sparkles {
        ctx.saveGState()
        c.glow(18, rgba(0.45, 0.90, 1.0, 0.9))
        ctx.setFillColor(rgba(0.80, 0.97, 1.0, 0.95))
        ctx.addPath(fourPointStar(center: p, rx: r * 0.55, ry: r, pinch: 0.10))
        ctx.fillPath()
        ctx.restoreGState()
    }
}

// MARK: - 紋章（星環・4 芒星・双刃の V）

/// 凹辺の 4 芒星。`pinch` が小さいほど鋭い。
func fourPointStar(center p: CGPoint, rx: CGFloat, ry: CGFloat, pinch: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let k = pinch
    path.move(to: CGPoint(x: p.x, y: p.y - ry))
    path.addQuadCurve(to: CGPoint(x: p.x + rx, y: p.y), control: CGPoint(x: p.x + rx * k, y: p.y - ry * k))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + ry), control: CGPoint(x: p.x + rx * k, y: p.y + ry * k))
    path.addQuadCurve(to: CGPoint(x: p.x - rx, y: p.y), control: CGPoint(x: p.x - rx * k, y: p.y + ry * k))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - ry), control: CGPoint(x: p.x - rx * k, y: p.y - ry * k))
    path.closeSubpath()
    return path
}

/// 星環（傾いた円環）。全周を刃の奥に描き、手前半分だけをマスク越しに刃の上へ重ねて前後関係を作る。
struct StarRing {
    let center = CGPoint(x: 512, y: 508)
    let angle: CGFloat = -0.21          // 約 -12°
    let tilt: CGFloat = 0.33            // 短径 / 長径
    let outer: CGFloat = 438
    let inner: CGFloat = 376

    var transform: CGAffineTransform {
        CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
    }

    func ellipse(_ r: CGFloat) -> CGRect { CGRect(x: -r, y: -r * tilt, width: r * 2, height: r * 2 * tilt) }

    /// 環帯（外楕円 − 内楕円）。
    var band: CGPath {
        let p = CGMutablePath()
        p.addEllipse(in: ellipse(outer))
        p.addEllipse(in: ellipse(inner))
        return p
    }

    /// 手前半分だけを通すマスク（環の局所 y で -6 → +40 にかけてぼかす）。
    /// 奥半分を刃の背後に全周描いた後、手前側だけをこのマスク越しに再描画すると継ぎ目が出ない。
    func frontMask(_ c: Canvas) -> CGImage {
        let gray = CGColorSpaceCreateDeviceGray()
        let m = CGContext(data: nil, width: c.pixels, height: c.pixels, bitsPerComponent: 8, bytesPerRow: 0,
                          space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        m.translateBy(x: 0, y: CGFloat(c.pixels))
        m.scaleBy(x: c.scale, y: -c.scale)
        m.concatenate(transform)
        let g = CGGradient(colorsSpace: gray, colors: [CGColor(gray: 0, alpha: 1), CGColor(gray: 1, alpha: 1)] as CFArray,
                           locations: [0, 1])!
        m.drawLinearGradient(g, start: CGPoint(x: 0, y: -6), end: CGPoint(x: 0, y: 40),
                             options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        return m.makeImage()!
    }

    func draw(_ c: Canvas) {
        let ctx = c.ctx
        ctx.saveGState()
        ctx.concatenate(transform)

        // 外光
        ctx.saveGState()
        c.glow(28, rgba(1.0, 0.72, 0.28, 0.75))
        ctx.addPath(band)
        ctx.setFillColor(rgba(0.95, 0.70, 0.30, 1))
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        // 金属のグラデーション（左右端を締め、中央を明るく）
        ctx.saveGState()
        ctx.addPath(band)
        ctx.clip(using: .evenOdd)
        let g = gradient([
            (0.00, rgba(0.62, 0.36, 0.10)),
            (0.22, rgba(0.96, 0.72, 0.30)),
            (0.50, rgba(1.00, 0.95, 0.72)),
            (0.78, rgba(0.96, 0.72, 0.30)),
            (1.00, rgba(0.62, 0.36, 0.10)),
        ])
        ctx.drawLinearGradient(g, start: CGPoint(x: -outer, y: 0), end: CGPoint(x: outer, y: 0), options: [])
        // 奥行きの陰影（奥 = 上側を暗く、手前 = 下側はそのまま）
        let depth = gradient([(0.0, rgba(0.10, 0.03, 0.12, 0.55)), (0.55, rgba(0.10, 0.03, 0.12, 0.12)),
                              (1.0, rgba(0, 0, 0, 0))])
        ctx.drawLinearGradient(depth, start: CGPoint(x: 0, y: -outer * tilt), end: CGPoint(x: 0, y: outer * tilt),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()

        // 刻線（内側の細い光のライン）
        ctx.saveGState()
        c.glow(8, rgba(1.0, 0.95, 0.75, 0.9))
        ctx.setStrokeColor(rgba(1.0, 0.97, 0.86, 0.8))
        ctx.setLineWidth(3.2)
        ctx.strokeEllipse(in: ellipse((outer + inner) / 2 + 6))
        ctx.restoreGState()

        ctx.restoreGState()
    }

    /// 環に沿った光の粒。
    func drawBeads(_ c: Canvas, seed: UInt64, front: Bool) {
        let ctx = c.ctx
        var rng = SplitMix64(state: seed)
        ctx.saveGState()
        ctx.concatenate(transform)
        for _ in 0..<46 {
            let t = rng.range(0, 2 * .pi)
            let rr = rng.range(inner - 30, outer + 42)
            let p = CGPoint(x: cos(t) * rr, y: sin(t) * rr * tilt)
            guard (p.y > 0) == front else { continue }
            let r = rng.range(1.4, 4.2)
            let cyan = rng.unit() < 0.55
            let col = cyan ? rgba(0.55, 0.95, 1.0, 0.95) : rgba(1.0, 0.93, 0.70, 0.95)
            ctx.saveGState()
            c.glow(12, col)
            ctx.setFillColor(col)
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }
}

/// 中央の大きな 4 芒星（金白色の発光）。
func drawCoreStar(_ c: Canvas) {
    let ctx = c.ctx
    let center = CGPoint(x: 512, y: 440)

    // 背後の後光
    let halo = gradient([
        (0.0, rgba(1.0, 0.92, 0.70, 0.85)), (0.25, rgba(1.0, 0.76, 0.36, 0.45)),
        (0.6, rgba(0.85, 0.45, 0.85, 0.12)), (1.0, rgba(0.6, 0.3, 0.9, 0)),
    ])
    ctx.drawRadialGradient(halo, startCenter: center, startRadius: 0, endCenter: center, endRadius: 250, options: [])

    // 斜めの副星（奥行き）
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: .pi / 4)
    c.glow(20, rgba(1.0, 0.80, 0.45, 0.8))
    ctx.setFillColor(rgba(1.0, 0.86, 0.55, 0.55))
    ctx.addPath(fourPointStar(center: .zero, rx: 92, ry: 92, pinch: 0.12))
    ctx.fillPath()
    ctx.restoreGState()

    // 主星
    let star = fourPointStar(center: center, rx: 158, ry: 238, pinch: 0.09)
    ctx.saveGState()
    c.glow(46, rgba(1.0, 0.80, 0.40, 1.0))
    ctx.addPath(star)
    ctx.setFillColor(rgba(1.0, 0.86, 0.50, 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(star)
    ctx.clip()
    let body = gradient([
        (0.00, rgba(1.0, 1.0, 0.97)), (0.18, rgba(1.0, 0.96, 0.80)),
        (0.55, rgba(1.0, 0.80, 0.40)), (1.00, rgba(0.90, 0.52, 0.16)),
    ])
    ctx.drawRadialGradient(body, startCenter: center, startRadius: 0, endCenter: center, endRadius: 238,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // 芯の白い輝き
    ctx.saveGState()
    c.glow(24, rgba(1, 1, 1, 1))
    ctx.setFillColor(rgba(1, 1, 1, 0.95))
    ctx.fillEllipse(in: CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32))
    ctx.restoreGState()
}

/// 1 本の剣（V の片腕）。`base` = 鍔の位置、`tip` = 切先。
func drawBlade(_ c: Canvas, base: CGPoint, tip: CGPoint, width w: CGFloat, mirrored: Bool) {
    let ctx = c.ctx
    let axis = tip - base
    let len = axis.length
    let d = axis.normalized
    let n = d.perp
    let shoulder = base + d * (len * 0.74)

    let edgeA = [base + n * (w * 0.5), shoulder + n * (w * 0.46), tip]
    let edgeB = [tip, shoulder - n * (w * 0.46), base - n * (w * 0.5)]
    let outline = CGMutablePath()
    outline.addLines(between: edgeA + edgeB)
    outline.closeSubpath()

    // 刃の外光（シアン）
    ctx.saveGState()
    c.glow(30, rgba(0.35, 0.85, 1.0, 0.85))
    ctx.addPath(outline)
    ctx.setFillColor(rgba(0.55, 0.80, 0.98, 1))
    ctx.fillPath()
    ctx.restoreGState()

    // 鎬で分けた 2 面（光の当たる面を明るく）
    let halfA = CGMutablePath()
    halfA.addLines(between: [base] + edgeA)
    halfA.closeSubpath()
    let halfB = CGMutablePath()
    halfB.addLines(between: [base] + edgeB.reversed())
    halfB.closeSubpath()
    let lit = mirrored ? halfB : halfA
    let shaded = mirrored ? halfA : halfB

    ctx.saveGState()
    ctx.addPath(lit)
    ctx.clip()
    let litG = gradient([(0, rgba(0.98, 0.99, 1.0)), (0.55, rgba(0.84, 0.92, 1.0)), (1, rgba(0.62, 0.86, 1.0))])
    ctx.drawLinearGradient(litG, start: base, end: tip, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shaded)
    ctx.clip()
    let shG = gradient([(0, rgba(0.52, 0.56, 0.80)), (0.6, rgba(0.36, 0.40, 0.70)), (1, rgba(0.30, 0.58, 0.86))])
    ctx.drawLinearGradient(shG, start: base, end: tip, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // 輪郭と鎬
    ctx.saveGState()
    ctx.setLineJoin(.miter)
    ctx.addPath(outline)
    ctx.setStrokeColor(rgba(0.90, 0.98, 1.0, 0.9))
    ctx.setLineWidth(2.5)
    ctx.strokePath()
    ctx.move(to: base + d * 6)
    ctx.addLine(to: tip - d * 10)
    ctx.setStrokeColor(rgba(1, 1, 1, 0.75))
    ctx.setLineWidth(2)
    ctx.strokePath()
    ctx.restoreGState()

    // 柄（グリップ + 柄頭）
    let gripLen: CGFloat = 74
    let guardThick: CGFloat = 26
    let gripStart = base - d * (guardThick * 0.5)
    let gripEnd = gripStart - d * gripLen
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.move(to: gripStart)
    ctx.addLine(to: gripEnd)
    ctx.setStrokeColor(rgba(0.20, 0.10, 0.36))
    ctx.setLineWidth(22)
    ctx.strokePath()
    // 金の巻き
    ctx.setLineCap(.butt)
    ctx.setStrokeColor(rgba(0.95, 0.72, 0.30))
    ctx.setLineWidth(4)
    for i in 1...3 {
        let p = gripStart - d * (gripLen * CGFloat(i) / 4)
        ctx.move(to: p + n * 11)
        ctx.addLine(to: p - n * 11)
    }
    ctx.strokePath()
    ctx.restoreGState()

    let pommel = gripEnd - d * 12
    ctx.saveGState()
    c.glow(14, rgba(1.0, 0.78, 0.35, 0.9))
    ctx.addPath(fourPointStar(center: pommel, rx: 17, ry: 17, pinch: 0.35))
    ctx.setFillColor(rgba(1.0, 0.85, 0.48))
    ctx.fillPath()
    ctx.restoreGState()

    // 鍔（左右が尖った金の鍔 + 中央の宝玉）
    let gw: CGFloat = 164
    let guardPoly = [
        base - d * (guardThick * 0.5) + n * (gw * 0.40),
        base + n * (gw * 0.5),
        base + d * (guardThick * 0.5) + n * (gw * 0.40),
        base + d * (guardThick * 0.5) - n * (gw * 0.40),
        base - n * (gw * 0.5),
        base - d * (guardThick * 0.5) - n * (gw * 0.40),
    ]
    let guardPath = CGMutablePath()
    guardPath.addLines(between: guardPoly)
    guardPath.closeSubpath()
    ctx.saveGState()
    c.glow(16, rgba(1.0, 0.70, 0.25, 0.8))
    ctx.addPath(guardPath)
    ctx.setFillColor(rgba(0.95, 0.70, 0.28))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(guardPath)
    ctx.clip()
    let gg = gradient([(0, rgba(1.0, 0.94, 0.70)), (0.5, rgba(0.98, 0.74, 0.30)), (1, rgba(0.66, 0.38, 0.10))])
    ctx.drawLinearGradient(gg, start: base - d * guardThick, end: base + d * guardThick, options: [])
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(guardPath)
    ctx.setStrokeColor(rgba(0.45, 0.24, 0.05, 0.9))
    ctx.setLineWidth(2)
    ctx.strokePath()
    let gem = CGRect(x: base.x - 11, y: base.y - 11, width: 22, height: 22)
    c.glow(12, rgba(0.40, 0.90, 1.0, 1))
    ctx.setFillColor(rgba(0.45, 0.92, 1.0))
    ctx.fillEllipse(in: gem)
    ctx.restoreGState()
}

/// 紋章全体。背景以外の全要素（アイコン・ダーク版・起動ロゴで共用）。
func drawEmblem(_ c: Canvas, beadsSeed: UInt64 = 7) {
    let ring = StarRing()
    // 奥: 環を全周描いてから星と刃を重ねる
    ring.draw(c)
    ring.drawBeads(c, seed: beadsSeed, front: false)
    drawCoreStar(c)
    let tip = CGPoint(x: 512, y: 836)
    drawBlade(c, base: CGPoint(x: 312, y: 286), tip: tip, width: 94, mirrored: false)
    drawBlade(c, base: CGPoint(x: 712, y: 286), tip: tip, width: 94, mirrored: true)
    // 切先の交点のきらめき
    c.ctx.saveGState()
    c.glow(22, rgba(0.55, 0.95, 1.0, 1))
    c.ctx.setFillColor(rgba(0.92, 1.0, 1.0))
    c.ctx.addPath(fourPointStar(center: CGPoint(x: 512, y: 830), rx: 22, ry: 40, pinch: 0.1))
    c.ctx.fillPath()
    c.ctx.restoreGState()
    // 手前: 環の下半分を刃の上に重ねる
    c.masked(by: ring.frontMask(c)) { ring.draw(c) }
    ring.drawBeads(c, seed: beadsSeed, front: true)
}

// MARK: - 変換・書き出し

/// 色付き外観用のグレースケール化（ガンマ空間の輝度。明るい部分ほどシステムの色が強く乗る）。
func grayscale(_ image: CGImage) -> CGImage {
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("PNG を作成できません: \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("PNG の書き出しに失敗: \(url.path)") }
    print("wrote \(url.path) (\(image.width)×\(image.height), alpha: \(image.alphaInfo != .noneSkipLast && image.alphaInfo != .none))")
}

func writeJSON(_ object: Any, to url: URL) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try! (String(data: data, encoding: .utf8)! + "\n").write(to: url, atomically: true, encoding: .utf8)
    print("wrote \(url.path)")
}

/// 確認用: iOS のアイコンマスクに近い角丸で切り抜き、`fill` の上に合成した縮小版（不透明）。
func maskedPreview(_ image: CGImage, pixels: Int, fill: CGColor = rgba(0, 0, 0)) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    ctx.setFillColor(rgba(0.92, 0.92, 0.95))
    ctx.fill(rect)
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerWidth: CGFloat(pixels) * 0.2237,
                       cornerHeight: CGFloat(pixels) * 0.2237, transform: nil))
    ctx.clip()
    ctx.setFillColor(fill)
    ctx.fill(rect)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: rect)
    return ctx.makeImage()!
}

/// 確認用: 透過画像を単色の上に合成（不透明）。
func flatten(_ image: CGImage, over fill: CGColor) -> CGImage {
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    ctx.setFillColor(fill)
    ctx.fill(rect)
    ctx.draw(image, in: rect)
    return ctx.makeImage()!
}

// MARK: - main

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("App/Resources/Assets.xcassets")
let iconSet = assets.appendingPathComponent("AppIcon.appiconset")
let launchSet = assets.appendingPathComponent("LaunchLogo.imageset")

// 1) App Store / ホーム画面アイコン（不透明）
let icon = Canvas(pixels: 1024, opaque: true)
drawBackground(icon)
drawStarDust(icon, seed: 2026, count: 170)
drawEmblem(icon)
let iconImage = icon.image()
writePNG(iconImage, to: iconSet.appendingPathComponent("AppIcon-1024.png"))

// 2) ダーク外観（背景はシステムが用意するので透過・星屑控えめ）
let dark = Canvas(pixels: 1024, opaque: false)
drawStarDust(dark, seed: 2027, count: 60)
drawEmblem(dark)
let darkImage = dark.image()
writePNG(darkImage, to: iconSet.appendingPathComponent("AppIcon-Dark-1024.png"))

// 3) 色付き外観（グレースケール・透過。色はシステムが付ける）
let tinted = Canvas(pixels: 1024, opaque: false)
drawEmblem(tinted)
let tintedImage = grayscale(tinted.image())
writePNG(tintedImage, to: iconSet.appendingPathComponent("AppIcon-Tinted-1024.png"))

writeJSON([
    "images": [
        ["filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
        ["appearances": [["appearance": "luminosity", "value": "dark"]],
         "filename": "AppIcon-Dark-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
        ["appearances": [["appearance": "luminosity", "value": "tinted"]],
         "filename": "AppIcon-Tinted-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
    ],
    "info": ["author": "xcode", "version": 1],
], to: iconSet.appendingPathComponent("Contents.json"))

// 4) 起動画面ロゴ（240pt 四方・透過）
let launchPoints = 240
var launchImages: [[String: String]] = []
var launchImage3x: CGImage?
for scale in 1...3 {
    let c = Canvas(pixels: launchPoints * scale, opaque: false)
    drawEmblem(c)
    let name = scale == 1 ? "LaunchLogo.png" : "LaunchLogo@\(scale)x.png"
    let img = c.image()
    if scale == 3 { launchImage3x = img }
    writePNG(img, to: launchSet.appendingPathComponent(name))
    launchImages.append(["filename": name, "idiom": "universal", "scale": "\(scale)x"])
}
writeJSON(["images": launchImages, "info": ["author": "xcode", "version": 1]],
          to: launchSet.appendingPathComponent("Contents.json"))

// 5) 任意: 確認用プレビュー
if let i = CommandLine.arguments.firstIndex(of: "--preview"), i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    for px in [1024, 180, 120, 60] {
        writePNG(maskedPreview(iconImage, pixels: px), to: dir.appendingPathComponent("icon-masked-\(px).png"))
    }
    // ダーク外観はシステムの暗い背景、色付き外観は黒背景の上で確認する
    writePNG(maskedPreview(darkImage, pixels: 512, fill: rgba(0.07, 0.07, 0.09)),
             to: dir.appendingPathComponent("icon-dark-512.png"))
    writePNG(maskedPreview(tintedImage, pixels: 512, fill: rgba(0, 0, 0)),
             to: dir.appendingPathComponent("icon-tinted-512.png"))
    if let launchImage3x {
        writePNG(flatten(launchImage3x, over: rgba(0.040, 0.050, 0.130)),
                 to: dir.appendingPathComponent("launch-logo-on-bg.png"))
    }
}
