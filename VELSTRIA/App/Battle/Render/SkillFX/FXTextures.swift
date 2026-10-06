import CoreGraphics
import Foundation
import RealityKit

// 担当: battle-renderer（スキル演出）。スキル演出で使う手続きテクスチャ（白地 + アルファ。色は粒子・材質の色で付ける）。
// どれも CoreGraphics で描き、読み込み幕の裏で一度だけ TextureResource にする（AssetLedger の .texture）。
// 向きの規約: 「横長」の模様（光条・稲妻・斬撃・鎖）は +X 方向へ伸びる。斬撃の弧は中心が画像の中心、
// 弧は上半分（+Y 側 = 画像の上）に描く。地面に寝かせた時、画像の上 = 前方（向きの角度 0）。

enum FXTex: String, CaseIterable, Hashable, Sendable {
    /// 柔らかい光（ガウス状）。
    case glow
    /// 芯の強い光（白い芯 + 速い減衰）。
    case glowHard
    /// 4 本の光条の閃光（レンズフレア）。
    case flare4
    /// 6 本の光条の閃光。
    case flare6
    /// 小さなきらめき（4 方向の細い光条）。
    case twinkle
    /// 細い輪（衝撃波の縁）。
    case ring
    /// 太い衝撃波（外縁が明るく内側へ薄れる）。
    case shockwave
    /// 二重の輪。
    case ringDouble
    /// 斬撃の三日月（上半分の弧、外縁が鋭く明るい）。
    case slash
    /// 細い斬撃の弧。
    case slashThin
    /// 一文字の斬線（横長、中央が明るい）。
    case slashLine
    /// 魔法陣（二重の輪・刻み・六芒星）。
    case runeCircle
    /// 機巧の陣（歯車の輪・目盛り）。
    case techCircle
    /// 時計の盤面（目盛り・針）。
    case clockFace
    /// 六角格子の盾面。
    case hexShield
    /// 光の筋（横長。伸ばす粒子・光線）。
    case streak
    /// 稲妻（横長のジグザグ）。
    case bolt
    /// 縦の光柱（下が明るく上へ薄れる。円柱の側面）。
    case beam
    /// 地割れ（放射状の亀裂、アルファ）。
    case crack
    /// 爪痕（3 本の平行な裂け目）。
    case claw
    /// 鎖（横長、輪の連なり）。
    case chain
    /// 結晶片（菱形）。
    case shard
    /// 花弁。
    case petal
    /// 羽根。
    case feather
    /// 炎の舌（上へ伸びる）。
    case flame
    /// 煙（柔らかい不規則な塊、アルファ）。
    case smoke
    /// 岩片（角ばった塊）。
    case rock
    /// 三日月。
    case moon
    /// 五芒星。
    case star
    /// 泡（輪 + ハイライト）。
    case bubble
    /// 波紋（同心円）。
    case ripple
    /// 風の渦（渦巻きの弧）。
    case swirl
    /// 音の波（同心の弧、+X 方向へ広がる）。
    case soundWave
    /// 糸（横長の波打つ線）。
    case thread
    /// 砂粒（細かい点の集まり）。
    case sand
    /// 光の矢（横長、矢じり付き）。
    case arrow
    /// 音符。
    case note

    /// 一辺の画素数（地面に大きく敷くものは高解像度）。
    var size: Int {
        switch self {
        case .runeCircle, .techCircle, .clockFace, .crack, .shockwave, .slash, .hexShield: return 256
        default: return 128
        }
    }
}

/// スキル演出のテクスチャ一式（試合ごとに 1 つ。読み込み幕の裏で全て作る）。
@MainActor
final class FXTextureLibrary {
    private var cache: [FXTex: TextureResource] = [:]
    private var glowCache: [FXTex: TextureResource] = [:]

    /// アルファ合成用（白 + アルファ。メッシュの材質・アルファ合成の粒子）。
    func texture(_ t: FXTex) -> TextureResource? {
        if let r = cache[t] { return r }
        guard let img = FXTextureLibrary.image(t) else { return nil }
        AssetLedger.record(.texture, "fx \(t.rawValue)")
        guard let r = try? TextureResource(image: img, options: .init(semantic: .color)) else { return nil }
        cache[t] = r
        return r
    }

    /// 加算合成の粒子用（輝度 = アルファ、不透明）。RealityKit の加算の粒子は画像のアルファで弱めず色をそのまま足すため、
    /// アルファの減衰を色へ焼き込んだ版を使う（白 + アルファの画像だと透明部分まで白く塗られ、硬い円盤に見える）。
    func glowTexture(_ t: FXTex) -> TextureResource? {
        if let r = glowCache[t] { return r }
        guard let img = FXTextureLibrary.image(t), let lum = FXTextureLibrary.luminance(img) else { return nil }
        AssetLedger.record(.texture, "fx glow \(t.rawValue)")
        guard let r = try? TextureResource(image: lum, options: .init(semantic: .color)) else { return nil }
        glowCache[t] = r
        return r
    }

    func prewarm(_ list: some Sequence<FXTex>) {
        for t in list {
            _ = texture(t)
            _ = glowTexture(t)
        }
    }

    var builtCount: Int { cache.count + glowCache.count }

    /// アルファを輝度へ焼き込んだ不透明の画像。
    static func luminance(_ img: CGImage) -> CGImage? {
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        for k in stride(from: 0, to: buf.count, by: 4) {
            // 乗算済みの白なので RGB はすでにアルファ倍。アルファだけ不透明にする
            let a = buf[k + 3]
            buf[k] = a; buf[k + 1] = a; buf[k + 2] = a
            buf[k + 3] = 255
        }
        return ctx.makeImage()
    }

    // MARK: 描画

    static func image(_ t: FXTex) -> CGImage? {
        let n = t.size
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let s = CGFloat(n)
        // CoreGraphics は左下原点。上 = +Y を「画像の上」にそろえる
        draw(t, ctx, s)
        return ctx.makeImage()
    }

    private static let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private static func white(_ a: CGFloat) -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: a) }

    private static func radial(_ ctx: CGContext, center c: CGPoint, radius r: CGFloat, stops: [(CGFloat, CGFloat)]) {
        let colors = stops.map { white($0.1) } as CFArray
        let locs = stops.map { $0.0 }
        guard let g = CGGradient(colorsSpace: space, colors: colors, locations: locs) else { return }
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
    }

    /// 決まった乱数（テクスチャを毎回同じにする）。
    private struct Rand {
        var s: UInt64
        mutating func next() -> CGFloat {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((s >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
        }
    }

    private static func draw(_ t: FXTex, _ ctx: CGContext, _ s: CGFloat) {
        let c = CGPoint(x: s / 2, y: s / 2)
        var rng = Rand(s: UInt64(t.rawValue.hashValueStable))
        switch t {
        case .glow:
            radial(ctx, center: c, radius: s / 2, stops: [(0, 1), (0.25, 0.55), (0.55, 0.16), (1, 0)])
        case .glowHard:
            radial(ctx, center: c, radius: s / 2, stops: [(0, 1), (0.12, 0.95), (0.3, 0.35), (0.6, 0.08), (1, 0)])
        case .flare4, .flare6, .twinkle:
            let rays = t == .flare6 ? 6 : 4
            let core: CGFloat = t == .twinkle ? 0.12 : 0.16
            radial(ctx, center: c, radius: s * 0.5, stops: [(0, 0.35), (0.3, 0.08), (1, 0)])
            radial(ctx, center: c, radius: s * core, stops: [(0, 1), (0.35, 0.7), (1, 0)])
            let width: CGFloat = t == .twinkle ? 0.022 : 0.03
            for k in 0..<rays {
                let a = CGFloat(k) * .pi * 2 / CGFloat(rays)
                ray(ctx, c, angle: a, length: s * 0.49, width: s * width)
            }
            if t != .twinkle {
                for k in 0..<rays {
                    let a = (CGFloat(k) + 0.5) * .pi * 2 / CGFloat(rays)
                    ray(ctx, c, angle: a, length: s * 0.22, width: s * 0.02, alpha: 0.5)
                }
            }
        case .ring:
            ringStroke(ctx, c, radius: s * 0.44, width: s * 0.035, glow: s * 0.03)
        case .shockwave:
            // 外縁が鋭く明るく、内側へ長く薄れる
            let colors = [white(0), white(0), white(0.18), white(0.55), white(1), white(0)] as CFArray
            let locs: [CGFloat] = [0, 0.45, 0.7, 0.86, 0.94, 1]
            if let g = CGGradient(colorsSpace: space, colors: colors, locations: locs) {
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: s / 2, options: [])
            }
        case .ringDouble:
            ringStroke(ctx, c, radius: s * 0.44, width: s * 0.03, glow: s * 0.025)
            ringStroke(ctx, c, radius: s * 0.33, width: s * 0.018, glow: s * 0.015, alpha: 0.7)
        case .slash, .slashThin:
            // 上半分の三日月: 外側の弧が明るく、内側の弧へ向けて薄れる。両端は細く尖る
            let thin = t == .slashThin
            let outer = s * 0.47
            let thickness = s * (thin ? 0.07 : 0.2)
            let steps = 72
            for i in 0..<steps {
                let u = CGFloat(i) / CGFloat(steps - 1)
                let a = .pi * (0.04 + 0.92 * u)
                // 端で細く、中央で太い（やや前寄りが最も太い = 振り抜きの勢い）
                let profile = pow(sin(.pi * u), 0.7) * (0.75 + 0.25 * u)
                let w = thickness * profile
                let p0 = CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer)
                let p1 = CGPoint(x: c.x + cos(a) * (outer - w), y: c.y + sin(a) * (outer - w))
                let colors = [white(0.95 * profile + 0.05), white(0.4 * profile), white(0)] as CFArray
                if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.35, 1]) {
                    ctx.saveGState()
                    ctx.setLineCap(.round)
                    ctx.setLineWidth(max(1, w))
                    ctx.move(to: CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2))
                    ctx.addLine(to: CGPoint(x: (p0.x + p1.x) / 2 + 0.01, y: (p0.y + p1.y) / 2))
                    ctx.replacePathWithStrokedPath()
                    ctx.clip()
                    ctx.drawLinearGradient(g, start: p0, end: p1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                    ctx.restoreGState()
                }
            }
            // 外縁の白い刃線
            ctx.setStrokeColor(white(1))
            ctx.setLineCap(.round)
            for i in 0..<(steps - 1) {
                let u = CGFloat(i) / CGFloat(steps - 1)
                let a0 = .pi * (0.04 + 0.92 * u)
                let a1 = .pi * (0.04 + 0.92 * (u + 1 / CGFloat(steps - 1)))
                ctx.setLineWidth(max(1, s * (thin ? 0.008 : 0.014) * pow(sin(.pi * u), 0.5)))
                ctx.move(to: CGPoint(x: c.x + cos(a0) * outer, y: c.y + sin(a0) * outer))
                ctx.addLine(to: CGPoint(x: c.x + cos(a1) * outer, y: c.y + sin(a1) * outer))
                ctx.strokePath()
            }
        case .slashLine:
            ray(ctx, c, angle: 0, length: s * 0.49, width: s * 0.07)
            ray(ctx, c, angle: .pi, length: s * 0.49, width: s * 0.07)
            radial(ctx, center: c, radius: s * 0.12, stops: [(0, 0.9), (1, 0)])
        case .runeCircle:
            ringStroke(ctx, c, radius: s * 0.47, width: s * 0.012, glow: s * 0.01)
            ringStroke(ctx, c, radius: s * 0.42, width: s * 0.02, glow: s * 0.014)
            ringStroke(ctx, c, radius: s * 0.27, width: s * 0.012, glow: s * 0.01, alpha: 0.85)
            // 刻み（ルーン帯）
            ctx.setStrokeColor(white(0.95))
            for k in 0..<48 {
                let a = CGFloat(k) * .pi * 2 / 48
                let long = k % 4 == 0
                let r0 = s * 0.43 + s * 0.01, r1 = s * (long ? 0.465 : 0.452)
                ctx.setLineWidth(s * (long ? 0.008 : 0.004))
                ctx.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
                ctx.addLine(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
                ctx.strokePath()
            }
            // 六芒星
            ctx.setLineWidth(s * 0.009)
            ctx.setStrokeColor(white(0.9))
            for tri in 0..<2 {
                for k in 0..<3 {
                    let a0 = CGFloat(k) * .pi * 2 / 3 + CGFloat(tri) * .pi / 3 + .pi / 2
                    let a1 = CGFloat(k + 1) * .pi * 2 / 3 + CGFloat(tri) * .pi / 3 + .pi / 2
                    ctx.move(to: CGPoint(x: c.x + cos(a0) * s * 0.4, y: c.y + sin(a0) * s * 0.4))
                    ctx.addLine(to: CGPoint(x: c.x + cos(a1) * s * 0.4, y: c.y + sin(a1) * s * 0.4))
                }
            }
            ctx.strokePath()
            // 小円の節点
            for k in 0..<6 {
                let a = CGFloat(k) * .pi / 3 + .pi / 2
                let p = CGPoint(x: c.x + cos(a) * s * 0.4, y: c.y + sin(a) * s * 0.4)
                ringStroke(ctx, p, radius: s * 0.03, width: s * 0.007, glow: 0)
            }
            radial(ctx, center: c, radius: s * 0.2, stops: [(0, 0.35), (1, 0)])
        case .techCircle:
            ringStroke(ctx, c, radius: s * 0.46, width: s * 0.016, glow: s * 0.01)
            ringStroke(ctx, c, radius: s * 0.3, width: s * 0.03, glow: s * 0.01, alpha: 0.8)
            // 歯車の歯
            ctx.setFillColor(white(0.9))
            for k in 0..<24 {
                let a = CGFloat(k) * .pi * 2 / 24
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.rotate(by: a)
                ctx.fill(CGRect(x: s * 0.31, y: -s * 0.018, width: s * 0.05, height: s * 0.036))
                ctx.restoreGState()
            }
            // 目盛りと区切りの弧
            ctx.setStrokeColor(white(0.85))
            for k in 0..<12 {
                let a0 = CGFloat(k) * .pi / 6 + 0.08, a1 = CGFloat(k + 1) * .pi / 6 - 0.08
                ctx.setLineWidth(s * 0.012)
                ctx.addArc(center: c, radius: s * 0.4, startAngle: a0, endAngle: a1, clockwise: false)
                ctx.strokePath()
            }
            ringStroke(ctx, c, radius: s * 0.12, width: s * 0.02, glow: s * 0.01)
        case .clockFace:
            ringStroke(ctx, c, radius: s * 0.46, width: s * 0.018, glow: s * 0.012)
            ringStroke(ctx, c, radius: s * 0.4, width: s * 0.008, glow: 0, alpha: 0.7)
            ctx.setStrokeColor(white(1))
            for k in 0..<60 {
                let a = CGFloat(k) * .pi * 2 / 60
                let major = k % 5 == 0
                ctx.setLineWidth(s * (major ? 0.014 : 0.005))
                let r0 = s * (major ? 0.36 : 0.385), r1 = s * 0.405
                ctx.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
                ctx.addLine(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
                ctx.strokePath()
            }
            ctx.setLineCap(.round)
            ctx.setLineWidth(s * 0.02)
            ctx.move(to: c); ctx.addLine(to: CGPoint(x: c.x, y: c.y + s * 0.3)); ctx.strokePath()
            ctx.setLineWidth(s * 0.028)
            ctx.move(to: c); ctx.addLine(to: CGPoint(x: c.x + s * 0.2, y: c.y - s * 0.06)); ctx.strokePath()
            radial(ctx, center: c, radius: s * 0.05, stops: [(0, 1), (1, 0)])
        case .hexShield:
            let r = s * 0.075
            let h = r * sqrt(3)
            ctx.setStrokeColor(white(0.9))
            ctx.setLineWidth(s * 0.008)
            var row = 0
            var y = -h
            while y < s + h {
                var x: CGFloat = row % 2 == 0 ? 0 : r * 1.5
                while x < s + r * 2 {
                    let d = hypot(x - c.x, y - c.y) / (s / 2)
                    if d < 0.98 {
                        ctx.setStrokeColor(white(0.35 + 0.65 * d * d))
                        hexagon(ctx, CGPoint(x: x, y: y), r * 0.92)
                    }
                    x += r * 3
                }
                y += h / 2
                row += 1
            }
            ringStroke(ctx, c, radius: s * 0.47, width: s * 0.02, glow: s * 0.015)
        case .streak:
            let colors = [white(0), white(0.5), white(1), white(0.5), white(0)] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.3, 0.55, 0.85, 1]) {
                ctx.saveGState()
                ctx.addEllipse(in: CGRect(x: 0, y: s * 0.42, width: s, height: s * 0.16))
                ctx.clip()
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: c.y), end: CGPoint(x: s, y: c.y), options: [])
                ctx.restoreGState()
            }
            radial(ctx, center: CGPoint(x: s * 0.6, y: c.y), radius: s * 0.1, stops: [(0, 0.8), (1, 0)])
        case .bolt:
            // 主幹 + 枝
            var pts: [CGPoint] = []
            let segs = 12
            for i in 0...segs {
                let x = s * 0.02 + s * 0.96 * CGFloat(i) / CGFloat(segs)
                let off = (i == 0 || i == segs) ? 0 : (rng.next() - 0.5) * s * 0.34
                pts.append(CGPoint(x: x, y: c.y + off))
            }
            polyline(ctx, pts, width: s * 0.06, alpha: 0.35)
            polyline(ctx, pts, width: s * 0.025, alpha: 0.8)
            polyline(ctx, pts, width: s * 0.01, alpha: 1)
            for b in 0..<3 {
                let i = 3 + b * 3
                var q = [pts[i]]
                var p = pts[i]
                for _ in 0..<3 {
                    p = CGPoint(x: p.x + s * 0.06, y: p.y + (rng.next() - 0.3) * s * 0.12 * (b % 2 == 0 ? 1 : -1))
                    q.append(p)
                }
                polyline(ctx, q, width: s * 0.008, alpha: 0.75)
            }
        case .beam:
            // 縦: 下（画像の下）が明るく上へ薄れる。横は中央が明るい
            for xi in 0..<Int(s) {
                let u = (CGFloat(xi) + 0.5) / s
                let edge = pow(sin(.pi * u), 0.6)
                let colors = [white(edge), white(0.5 * edge), white(0)] as CFArray
                if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 1]) {
                    ctx.saveGState()
                    ctx.clip(to: CGRect(x: CGFloat(xi), y: 0, width: 1, height: s))
                    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: s), options: [])
                    ctx.restoreGState()
                }
            }
        case .crack:
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for k in 0..<9 {
                var a = CGFloat(k) * .pi * 2 / 9 + (rng.next() - 0.5) * 0.4
                var p = c
                var w = s * 0.03
                var pts = [p]
                let n = 7
                for _ in 0..<n {
                    a += (rng.next() - 0.5) * 0.7
                    let len = s * (0.045 + rng.next() * 0.03)
                    p = CGPoint(x: p.x + cos(a) * len, y: p.y + sin(a) * len)
                    pts.append(p)
                }
                for i in 0..<(pts.count - 1) {
                    ctx.setStrokeColor(white(1 - CGFloat(i) / CGFloat(n) * 0.6))
                    ctx.setLineWidth(max(1, w))
                    ctx.move(to: pts[i]); ctx.addLine(to: pts[i + 1]); ctx.strokePath()
                    w *= 0.78
                }
            }
            radial(ctx, center: c, radius: s * 0.14, stops: [(0, 0.9), (1, 0)])
        case .claw:
            ctx.setLineCap(.round)
            for k in -1...1 {
                let x0 = c.x + CGFloat(k) * s * 0.17
                let steps = 30
                for i in 0..<steps {
                    let u = CGFloat(i) / CGFloat(steps)
                    let u1 = CGFloat(i + 1) / CGFloat(steps)
                    let w = s * 0.06 * pow(sin(.pi * u), 0.8)
                    ctx.setStrokeColor(white(0.95))
                    ctx.setLineWidth(max(1, w))
                    let bend: (CGFloat) -> CGFloat = { v in s * 0.06 * sin(.pi * v) }
                    ctx.move(to: CGPoint(x: x0 + bend(u), y: s * (0.08 + 0.84 * u)))
                    ctx.addLine(to: CGPoint(x: x0 + bend(u1), y: s * (0.08 + 0.84 * u1)))
                    ctx.strokePath()
                }
            }
        case .chain:
            ctx.setStrokeColor(white(1))
            ctx.setLineWidth(s * 0.035)
            let links = 5
            let lw = s / CGFloat(links)
            for i in 0..<links {
                let x = CGFloat(i) * lw
                if i % 2 == 0 {
                    ctx.strokeEllipse(in: CGRect(x: x + lw * 0.05, y: c.y - s * 0.09, width: lw * 1.1, height: s * 0.18))
                } else {
                    ctx.setLineWidth(s * 0.05)
                    ctx.move(to: CGPoint(x: x - lw * 0.05, y: c.y)); ctx.addLine(to: CGPoint(x: x + lw * 1.15, y: c.y))
                    ctx.strokePath()
                    ctx.setLineWidth(s * 0.035)
                }
            }
        case .shard:
            ctx.setFillColor(white(0.95))
            ctx.move(to: CGPoint(x: c.x, y: s * 0.97))
            ctx.addLine(to: CGPoint(x: s * 0.68, y: c.y + s * 0.05))
            ctx.addLine(to: CGPoint(x: c.x, y: s * 0.03))
            ctx.addLine(to: CGPoint(x: s * 0.34, y: c.y - s * 0.08))
            ctx.closePath()
            ctx.fillPath()
            ctx.setFillColor(white(0.55))
            ctx.move(to: CGPoint(x: c.x, y: s * 0.97))
            ctx.addLine(to: CGPoint(x: s * 0.68, y: c.y + s * 0.05))
            ctx.addLine(to: CGPoint(x: c.x, y: c.y))
            ctx.closePath()
            ctx.fillPath()
        case .petal:
            ctx.setFillColor(white(0.95))
            ctx.move(to: CGPoint(x: c.x, y: s * 0.04))
            ctx.addCurve(to: CGPoint(x: c.x, y: s * 0.96), control1: CGPoint(x: s * 0.98, y: s * 0.3),
                         control2: CGPoint(x: s * 0.72, y: s * 0.9))
            ctx.addCurve(to: CGPoint(x: c.x, y: s * 0.04), control1: CGPoint(x: s * 0.28, y: s * 0.9),
                         control2: CGPoint(x: s * 0.02, y: s * 0.3))
            ctx.fillPath()
            radial(ctx, center: CGPoint(x: c.x, y: s * 0.3), radius: s * 0.25, stops: [(0, 0.5), (1, 0)])
        case .feather:
            ctx.setFillColor(white(0.9))
            ctx.move(to: CGPoint(x: c.x, y: s * 0.98))
            ctx.addCurve(to: CGPoint(x: c.x, y: s * 0.05), control1: CGPoint(x: s * 0.82, y: s * 0.7),
                         control2: CGPoint(x: s * 0.66, y: s * 0.2))
            ctx.addCurve(to: CGPoint(x: c.x, y: s * 0.98), control1: CGPoint(x: s * 0.34, y: s * 0.2),
                         control2: CGPoint(x: s * 0.18, y: s * 0.7))
            ctx.fillPath()
            ctx.setStrokeColor(white(1))
            ctx.setLineWidth(s * 0.02)
            ctx.move(to: CGPoint(x: c.x, y: s * 0.02)); ctx.addLine(to: CGPoint(x: c.x, y: s * 0.96)); ctx.strokePath()
        case .flame:
            for layer in 0..<3 {
                let k = 1 - CGFloat(layer) * 0.28
                ctx.setFillColor(white(0.35 + CGFloat(layer) * 0.3))
                ctx.move(to: CGPoint(x: c.x, y: s * (0.06 + 0.9 * k)))
                ctx.addCurve(to: CGPoint(x: c.x, y: s * 0.06), control1: CGPoint(x: c.x + s * 0.42 * k, y: s * 0.5 * k),
                             control2: CGPoint(x: c.x + s * 0.3 * k, y: s * 0.06))
                ctx.addCurve(to: CGPoint(x: c.x, y: s * (0.06 + 0.9 * k)), control1: CGPoint(x: c.x - s * 0.3 * k, y: s * 0.06),
                             control2: CGPoint(x: c.x - s * 0.42 * k, y: s * 0.5 * k))
                ctx.fillPath()
            }
        case .smoke:
            for _ in 0..<14 {
                let p = CGPoint(x: c.x + (rng.next() - 0.5) * s * 0.4, y: c.y + (rng.next() - 0.5) * s * 0.4)
                radial(ctx, center: p, radius: s * (0.16 + rng.next() * 0.14), stops: [(0, 0.38), (0.6, 0.14), (1, 0)])
            }
        case .rock:
            ctx.setFillColor(white(1))
            let n = 7
            for i in 0..<n {
                let a = CGFloat(i) * .pi * 2 / CGFloat(n) + rng.next() * 0.3
                let r = s * (0.3 + rng.next() * 0.17)
                let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
            }
            ctx.closePath()
            ctx.fillPath()
            ctx.setFillColor(white(0.7))
            ctx.fill(CGRect(x: c.x - s * 0.05, y: c.y, width: s * 0.25, height: s * 0.2))
        case .moon:
            ctx.setFillColor(white(1))
            ctx.fillEllipse(in: CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8))
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: CGRect(x: s * 0.3, y: s * 0.2, width: s * 0.72, height: s * 0.72))
            ctx.setBlendMode(.normal)
        case .star:
            ctx.setFillColor(white(1))
            for i in 0..<10 {
                let a = CGFloat(i) * .pi / 5 + .pi / 2
                let r = s * (i % 2 == 0 ? 0.47 : 0.19)
                let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
            }
            ctx.closePath()
            ctx.fillPath()
        case .bubble:
            ringStroke(ctx, c, radius: s * 0.42, width: s * 0.04, glow: s * 0.03)
            radial(ctx, center: CGPoint(x: s * 0.36, y: s * 0.64), radius: s * 0.12, stops: [(0, 1), (1, 0)])
        case .ripple:
            for k in 0..<4 {
                ringStroke(ctx, c, radius: s * (0.14 + 0.11 * CGFloat(k)), width: s * 0.02, glow: s * 0.012,
                           alpha: 1 - CGFloat(k) * 0.2)
            }
        case .swirl:
            ctx.setLineCap(.round)
            for arm in 0..<3 {
                let base = CGFloat(arm) * .pi * 2 / 3
                let steps = 40
                for i in 0..<steps {
                    let u = CGFloat(i) / CGFloat(steps)
                    let u1 = CGFloat(i + 1) / CGFloat(steps)
                    let r0 = s * (0.06 + 0.4 * u), r1 = s * (0.06 + 0.4 * u1)
                    let a0 = base + u * 2.6, a1 = base + u1 * 2.6
                    ctx.setStrokeColor(white(1 - u * 0.7))
                    ctx.setLineWidth(s * 0.035 * (1 - u * 0.6))
                    ctx.move(to: CGPoint(x: c.x + cos(a0) * r0, y: c.y + sin(a0) * r0))
                    ctx.addLine(to: CGPoint(x: c.x + cos(a1) * r1, y: c.y + sin(a1) * r1))
                    ctx.strokePath()
                }
            }
        case .soundWave:
            ctx.setLineCap(.round)
            for k in 0..<4 {
                let r = s * (0.14 + 0.11 * CGFloat(k))
                ctx.setStrokeColor(white(1 - CGFloat(k) * 0.18))
                ctx.setLineWidth(s * 0.03)
                ctx.addArc(center: CGPoint(x: s * 0.06, y: c.y), radius: r, startAngle: -0.7, endAngle: 0.7, clockwise: false)
                ctx.strokePath()
            }
        case .thread:
            ctx.setLineCap(.round)
            for k in 0..<2 {
                var pts: [CGPoint] = []
                for i in 0...40 {
                    let u = CGFloat(i) / 40
                    pts.append(CGPoint(x: s * u, y: c.y + sin(u * .pi * 4 + CGFloat(k) * 1.6) * s * 0.12))
                }
                polyline(ctx, pts, width: s * 0.03, alpha: 0.4)
                polyline(ctx, pts, width: s * 0.012, alpha: 1)
            }
        case .sand:
            ctx.setFillColor(white(1))
            for _ in 0..<70 {
                let a = rng.next() * .pi * 2
                let r = pow(rng.next(), 0.7) * s * 0.45
                let d = s * (0.01 + rng.next() * 0.025)
                ctx.fillEllipse(in: CGRect(x: c.x + cos(a) * r - d / 2, y: c.y + sin(a) * r - d / 2, width: d, height: d))
            }
        case .arrow:
            ray(ctx, CGPoint(x: s * 0.72, y: c.y), angle: .pi, length: s * 0.7, width: s * 0.05)
            ctx.setFillColor(white(1))
            ctx.move(to: CGPoint(x: s * 0.98, y: c.y))
            ctx.addLine(to: CGPoint(x: s * 0.7, y: c.y + s * 0.11))
            ctx.addLine(to: CGPoint(x: s * 0.76, y: c.y))
            ctx.addLine(to: CGPoint(x: s * 0.7, y: c.y - s * 0.11))
            ctx.closePath()
            ctx.fillPath()
            radial(ctx, center: CGPoint(x: s * 0.82, y: c.y), radius: s * 0.16, stops: [(0, 0.7), (1, 0)])
        case .note:
            ctx.setFillColor(white(1))
            ctx.fillEllipse(in: CGRect(x: s * 0.2, y: s * 0.12, width: s * 0.3, height: s * 0.22))
            ctx.fill(CGRect(x: s * 0.44, y: s * 0.22, width: s * 0.06, height: s * 0.62))
            ctx.move(to: CGPoint(x: s * 0.5, y: s * 0.84))
            ctx.addCurve(to: CGPoint(x: s * 0.78, y: s * 0.5), control1: CGPoint(x: s * 0.7, y: s * 0.8),
                         control2: CGPoint(x: s * 0.82, y: s * 0.66))
            ctx.addLine(to: CGPoint(x: s * 0.5, y: s * 0.72))
            ctx.closePath()
            ctx.fillPath()
        }
    }

    // MARK: 部品

    private static func ray(_ ctx: CGContext, _ c: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat, alpha: CGFloat = 1) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: angle)
        ctx.move(to: CGPoint(x: 0, y: -width / 2))
        ctx.addLine(to: CGPoint(x: length, y: 0))
        ctx.addLine(to: CGPoint(x: 0, y: width / 2))
        ctx.closePath()
        ctx.clip()
        let colors = [white(alpha), white(alpha * 0.4), white(0)] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.4, 1]) {
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: length, y: 0), options: [])
        }
        ctx.restoreGState()
    }

    private static func ringStroke(_ ctx: CGContext, _ c: CGPoint, radius r: CGFloat, width w: CGFloat, glow g: CGFloat,
                                   alpha: CGFloat = 1) {
        if g > 0 {
            ctx.setStrokeColor(white(alpha * 0.25))
            ctx.setLineWidth(w + g * 2)
            ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        ctx.setStrokeColor(white(alpha))
        ctx.setLineWidth(w)
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private static func hexagon(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
        for i in 0...6 {
            let a = CGFloat(i) * .pi / 3
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
        }
        ctx.strokePath()
    }

    private static func polyline(_ ctx: CGContext, _ pts: [CGPoint], width: CGFloat, alpha: CGFloat) {
        guard let first = pts.first else { return }
        ctx.setStrokeColor(white(alpha))
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: first)
        for p in pts.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
    }
}

private extension String {
    /// 実行ごとに変わらないハッシュ（Swift の hashValue は起動ごとに変わる）。
    var hashValueStable: Int {
        var h: UInt64 = 1469598103934665603
        for b in utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Int(truncatingIfNeeded: h & 0x7FFF_FFFF)
    }
}
