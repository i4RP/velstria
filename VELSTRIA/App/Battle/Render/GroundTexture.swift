import CoreGraphics
import Foundation
import UIKit
import VelstriaCore

// 担当: battle-renderer。
// 地面テクスチャを CoreGraphics で手続き生成する（メインスレッド外で呼べる純関数）。
// 描画座標は sim 単位（y 上向き）。画像の上端 = sim y 最大。
// 草原/ジャングルの色むら → 草むら・障害物の足元 → 河川 → ボス穴 → レーン（土の道・浅瀬）→ 本拠点広場・泉 → 縁の陰影。

enum GroundTextureGenerator {
    static func makeImage(map: MapDefinition, size: Int, colorblind: Bool) -> CGImage? {
        let n = max(64, size)
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let S = CGFloat(n) / CGFloat(map.size)
        let W = CGFloat(map.size)
        ctx.scaleBy(x: S, y: S)
        ctx.interpolationQuality = .high
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let teams = TeamColors(colorblind: colorblind)
        var rng = RenderRNG(seed: 0x5E1_57A1)
        let full = CGRect(x: 0, y: 0, width: W, height: W)

        func fill(_ c: RGB, _ a: Double = 1) { ctx.setFillColor(c.cgColor(alpha: a)) }
        func stroke(_ c: RGB, _ a: Double = 1, width: CGFloat) {
            ctx.setStrokeColor(c.cgColor(alpha: a))
            ctx.setLineWidth(width)
        }
        func circle(_ p: Vec2, _ r: Double) -> CGRect {
            CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        }
        func lanePath(_ pts: [Vec2]) -> CGPath {
            let path = CGMutablePath()
            guard let first = pts.first else { return path }
            path.move(to: CGPoint(x: first.x, y: first.y))
            for p in pts.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
            return path
        }

        // 1. ジャングルの基調色 + 大きな色むら
        fill(RGB(0.21, 0.40, 0.21))
        ctx.fill(full)
        if let noise = noiseImage(size: 40, seed: 11, colors: [
            RGB(0.15, 0.33, 0.18), RGB(0.24, 0.45, 0.22), RGB(0.34, 0.50, 0.23), RGB(0.17, 0.38, 0.30),
        ]) {
            ctx.saveGState()
            ctx.setAlpha(0.65)
            ctx.draw(noise, in: full)
            ctx.restoreGState()
        }

        // 2. レーン沿い・本拠点周辺は明るい草原
        for pts in map.lanePaths {
            let path = lanePath(pts)
            for (w, a) in [(2800.0, 0.14), (2100.0, 0.16), (1500.0, 0.18)] {
                stroke(RGB(0.38, 0.60, 0.28), a, width: w)
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
        for team in Team.players {
            for (r, a) in [(2600.0, 0.18), (2100.0, 0.2)] {
                fill(RGB(0.40, 0.62, 0.30), a)
                ctx.fillEllipse(in: circle(map.core(team), r))
            }
        }
        if let noise = noiseImage(size: 150, seed: 23, colors: [
            RGB(0.20, 0.40, 0.20), RGB(0.30, 0.52, 0.25), RGB(0.40, 0.58, 0.27), RGB(0.22, 0.44, 0.30),
        ]) {
            ctx.saveGState()
            ctx.setAlpha(0.22)
            ctx.draw(noise, in: full)
            ctx.restoreGState()
        }

        // 3. 草の斑点（小さな草むら・花）
        let speckles = Int(Double(n) * Double(n) / 420)
        for _ in 0..<speckles {
            let p = Vec2(Double(rng.nextFloat()) * map.size, Double(rng.nextFloat()) * map.size)
            let r = Double(rng.range(18, 60))
            let k = rng.nextFloat()
            let c: RGB
            if k < 0.45 { c = RGB(0.14, 0.30, 0.16) } else if k < 0.85 { c = RGB(0.44, 0.66, 0.32) } else if k < 0.93 {
                c = RGB(0.62, 0.70, 0.34)
            } else { c = RGB(0.30, 0.52, 0.42) }
            fill(c, Double(rng.range(0.18, 0.4)))
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.7, width: r * 2, height: r * 1.4))
        }
        // 小さな花（ジャングルのみ、控えめ）
        for _ in 0..<(speckles / 14) {
            let p = Vec2(Double(rng.nextFloat()) * map.size, Double(rng.nextFloat()) * map.size)
            guard map.nearestLane(to: p).distance > 700, !map.isInRiver(p) else { continue }
            let c = rng.chance(0.5) ? RGB(0.95, 0.85, 0.45) : (rng.chance(0.5) ? RGB(0.96, 0.62, 0.76) : RGB(0.80, 0.90, 1.0))
            fill(c, 0.75)
            let r = Double(rng.range(10, 18))
            ctx.fillEllipse(in: circle(p, r))
        }

        // 4. 障害物・草むら・キャンプの足元
        for o in map.obstacles {
            switch o {
            case .rect(let r):
                for (e, a) in [(220.0, 0.25), (120.0, 0.45), (40.0, 0.5)] {
                    fill(RGB(0.12, 0.20, 0.13), a)
                    let rr = CGRect(x: r.minX - e, y: r.minY - e, width: r.width + e * 2, height: r.height + e * 2)
                    ctx.addPath(CGPath(roundedRect: rr, cornerWidth: e + 60, cornerHeight: e + 60, transform: nil))
                    ctx.fillPath()
                }
            case .circle(let c, let radius):
                for (e, a) in [(220.0, 0.25), (110.0, 0.45)] {
                    fill(RGB(0.12, 0.20, 0.13), a)
                    ctx.fillEllipse(in: circle(c, radius + e))
                }
            }
        }
        for b in map.brushes {
            let r = b.rect
            for (e, a) in [(90.0, 0.35), (30.0, 0.55)] {
                fill(RGB(0.10, 0.28, 0.14), a)
                let rr = CGRect(x: r.minX - e, y: r.minY - e, width: r.width + e * 2, height: r.height + e * 2)
                ctx.addPath(CGPath(roundedRect: rr, cornerWidth: 80, cornerHeight: 80, transform: nil))
                ctx.fillPath()
            }
        }
        for camp in map.camps where camp.kind == .small || camp.kind == .blueSentinel || camp.kind == .redSentinel {
            let big = camp.kind != .small
            fill(RGB(0.44, 0.40, 0.27), 0.35)
            ctx.fillEllipse(in: circle(camp.pos, big ? 520 : 420))
            fill(RGB(0.50, 0.44, 0.30), 0.35)
            ctx.fillEllipse(in: circle(camp.pos, big ? 380 : 300))
            if big {
                let glow = camp.kind == .blueSentinel ? RGB(0.40, 0.70, 1.0) : RGB(1.0, 0.48, 0.36)
                stroke(glow, 0.35, width: 26)
                ctx.strokeEllipse(in: circle(camp.pos, 430))
            }
        }

        // 5. 河川（左上 → 右下の対角帯）
        let riverA = CGPoint(x: -800, y: W + 800), riverB = CGPoint(x: W + 800, y: -800)
        let rw = CGFloat(map.riverWidth)
        let riverLayers: [(CGFloat, RGB, Double)] = [
            (rw + 420, RGB(0.36, 0.44, 0.28), 0.5),
            (rw + 250, RGB(0.66, 0.60, 0.43), 1),
            (rw + 110, RGB(0.33, 0.42, 0.37), 1),
            (rw, RGB(0.13, 0.36, 0.49), 1),
            (rw * 0.72, RGB(0.17, 0.44, 0.57), 0.85),
            (rw * 0.34, RGB(0.24, 0.53, 0.64), 0.55),
        ]
        for (w, c, a) in riverLayers {
            stroke(c, a, width: w)
            ctx.move(to: riverA)
            ctx.addLine(to: riverB)
            ctx.strokePath()
        }
        // さざ波と岸の小石
        let along = Vec2(1, -1).normalized, across = Vec2(1, 1).normalized
        for _ in 0..<(n / 3) {
            let t = Double(rng.range(-200, Float(map.size * 1.414) + 200))
            let o = Double(rng.range(-0.40, 0.40)) * map.riverWidth
            let c = Vec2(0, map.size) + along * t + across * o
            let len = Double(rng.range(90, 280))
            stroke(RGB(0.62, 0.86, 0.92), Double(rng.range(0.18, 0.42)), width: CGFloat(rng.range(10, 22)))
            ctx.move(to: CGPoint(x: c.x, y: c.y))
            let e = c + along * len
            ctx.addLine(to: CGPoint(x: e.x, y: e.y))
            ctx.strokePath()
        }
        for _ in 0..<(n / 2) {
            let t = Double(rng.range(0, Float(map.size * 1.414)))
            let side: Double = rng.chance(0.5) ? 1 : -1
            let o = side * (map.riverWidth / 2 + Double(rng.range(10, 130)))
            let c = Vec2(0, map.size) + along * t + across * o
            fill(rng.chance(0.5) ? RGB(0.55, 0.54, 0.52) : RGB(0.74, 0.70, 0.60), 0.8)
            let r = Double(rng.range(14, 34))
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.75, width: r * 2, height: r * 1.5))
        }

        // 6. ボスの巣（河川上の円形闘技場）
        for camp in map.camps where camp.kind == .astralWyrm || camp.kind == .ancientColossus {
            let rune = camp.kind == .astralWyrm ? RGB(0.72, 0.52, 1.0) : RGB(1.0, 0.82, 0.40)
            fill(RGB(0.30, 0.30, 0.34))
            ctx.fillEllipse(in: circle(camp.pos, 760))
            fill(RGB(0.46, 0.45, 0.47))
            ctx.fillEllipse(in: circle(camp.pos, 700))
            fill(RGB(0.24, 0.27, 0.32))
            ctx.fillEllipse(in: circle(camp.pos, 600))
            fill(camp.kind == .astralWyrm ? RGB(0.20, 0.18, 0.30) : RGB(0.30, 0.27, 0.22), 0.8)
            ctx.fillEllipse(in: circle(camp.pos, 540))
            stroke(RGB(0.52, 0.51, 0.54), 1, width: 22)
            for k in 0..<16 {
                let a = Double(k) / 16 * 2 * .pi
                let p0 = camp.pos + Vec2(cos(a), sin(a)) * 600, p1 = camp.pos + Vec2(cos(a), sin(a)) * 700
                ctx.move(to: CGPoint(x: p0.x, y: p0.y)); ctx.addLine(to: CGPoint(x: p1.x, y: p1.y))
            }
            ctx.strokePath()
            // 紋章の滲み（輪郭は MapScene の平面メッシュ）
            stroke(rune, 0.25, width: 90)
            ctx.strokeEllipse(in: circle(camp.pos, 470))
        }

        // 7. レーン（土の道）と浅瀬
        for pts in map.lanePaths {
            let path = lanePath(pts)
            let layers: [(CGFloat, RGB, Double)] = [
                (980, RGB(0.30, 0.34, 0.20), 0.30),
                (800, RGB(0.42, 0.34, 0.23), 0.9),
                (700, RGB(0.58, 0.47, 0.32), 1),
                (520, RGB(0.64, 0.53, 0.37), 0.8),
                (260, RGB(0.70, 0.60, 0.43), 0.45),
            ]
            for (w, c, a) in layers {
                stroke(c, a, width: w)
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
        // 道の小石・轍
        for pts in map.lanePaths {
            for k in 1..<pts.count {
                let a = pts[k - 1], b = pts[k]
                let len = a.distance(to: b)
                let dir = (b - a).normalized, nrm = dir.perpendicular
                let count = Int(len / 22)
                for _ in 0..<count {
                    let p = a + dir * Double(rng.range(0, Float(len))) + nrm * Double(rng.range(-320, 320))
                    let r = Double(rng.range(8, 26))
                    fill(rng.chance(0.6) ? RGB(0.46, 0.37, 0.25) : RGB(0.78, 0.70, 0.54), Double(rng.range(0.3, 0.7)))
                    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.7, width: r * 2, height: r * 1.4))
                }
                // 轍（うっすら 2 本）
                for side in [-140.0, 140.0] {
                    stroke(RGB(0.48, 0.38, 0.26), 0.25, width: 40)
                    let p0 = a + nrm * side, p1 = b + nrm * side
                    ctx.move(to: CGPoint(x: p0.x, y: p0.y)); ctx.addLine(to: CGPoint(x: p1.x, y: p1.y))
                    ctx.strokePath()
                }
            }
        }
        // 浅瀬: 河川帯でクリップして水色を重ね、飛び石を置く
        ctx.saveGState()
        ctx.setLineWidth(rw)
        ctx.move(to: riverA)
        ctx.addLine(to: riverB)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        for pts in map.lanePaths {
            stroke(RGB(0.20, 0.45, 0.55), 0.55, width: 720)
            ctx.addPath(lanePath(pts))
            ctx.strokePath()
        }
        ctx.restoreGState()
        for pts in map.lanePaths {
            for k in 1..<pts.count {
                let a = pts[k - 1], b = pts[k]
                let len = a.distance(to: b)
                let dir = (b - a).normalized, nrm = dir.perpendicular
                var t = 0.0
                while t < len {
                    let c = a + dir * t
                    if map.isInRiver(c) {
                        for lateral in [-170.0, 0, 170] {
                            let p = c + nrm * (lateral + Double(rng.range(-40, 40)))
                            fill(RGB(0.34, 0.38, 0.40), 0.9)
                            ctx.fillEllipse(in: CGRect(x: p.x - 52, y: p.y - 44, width: 104, height: 88))
                            fill(RGB(0.56, 0.58, 0.57), 0.9)
                            ctx.fillEllipse(in: CGRect(x: p.x - 40, y: p.y - 26, width: 80, height: 62))
                        }
                    }
                    t += 190
                }
            }
        }

        // 8. タワーの台座（周りに接地の陰り = 焼き込みの環境遮蔽。太陽の影が無い画質でも台座が地面に据わって見える）
        let aoColors = [CGColor(srgbRed: 0.03, green: 0.05, blue: 0.04, alpha: 0.5),
                        CGColor(srgbRed: 0.03, green: 0.05, blue: 0.04, alpha: 0.18),
                        CGColor(srgbRed: 0.03, green: 0.05, blue: 0.04, alpha: 0)] as CFArray
        let ao = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: aoColors, locations: [0, 0.4, 1])
        for t in map.towers where !t.isCore {
            if let ao {
                let c = CGPoint(x: t.pos.x, y: t.pos.y)
                ctx.drawRadialGradient(ao, startCenter: c, startRadius: 300, endCenter: c, endRadius: 470,
                                       options: [.drawsBeforeStartLocation])
            }
            fill(RGB(0.30, 0.28, 0.27), 0.6)
            ctx.fillEllipse(in: circle(t.pos, 330))
            fill(RGB(0.60, 0.58, 0.55))
            ctx.fillEllipse(in: circle(t.pos, 280))
        }

        // 9. 本拠点の広場と泉
        for team in Team.players {
            let core = map.core(team), fountain = map.fountain(team)
            let tc = teams.main(team)
            // 泉 → Core の石畳
            stroke(RGB(0.52, 0.51, 0.52), 1, width: 900)
            ctx.move(to: CGPoint(x: fountain.x, y: fountain.y))
            ctx.addLine(to: CGPoint(x: core.x, y: core.y))
            ctx.strokePath()
            // 泉（Core の広場と重なる部分は下の広場で覆い、広場の外側の三日月だけが見える）
            fill(RGB(0.32, 0.33, 0.40))
            ctx.fillEllipse(in: circle(fountain, 860))
            fill(RGB(0.52, 0.54, 0.62))
            ctx.fillEllipse(in: circle(fountain, 800))
            // 紋章の滲み（輪郭は MapScene の平面メッシュ）
            stroke(tc, 0.3, width: 120)
            ctx.strokeEllipse(in: circle(fountain, 720))
            // 石畳（MapScene の平面メッシュ、半径 4.65〜15.65 m）の下の目地色と、外周の細い縁。
            // 目地は一色にする: 下に泉の円盤やチーム色の線があると、細い目地から色が覗いて動くとちらつく。
            // 縁は細く留める（基部タワーは Core から 15.0〜15.6 m にあり、太い縁だと台座の陰りを横切る）
            fill(RGB(0.34, 0.33, 0.35))
            ctx.fillEllipse(in: circle(core, 1585))
            fill(RGB(0.36, 0.35, 0.37))
            ctx.fillEllipse(in: circle(core, 1575))
            fill(RGB(0.70, 0.69, 0.68))
            ctx.fillEllipse(in: circle(core, 450))
        }

        // 10. 縁の陰影
        let edge: CGFloat = 900
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
            CGColor(srgbRed: 0.03, green: 0.07, blue: 0.06, alpha: 0.55), CGColor(srgbRed: 0.03, green: 0.07, blue: 0.06, alpha: 0),
        ] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: edge, y: 0), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: W, y: 0), end: CGPoint(x: W - edge, y: 0), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: edge), options: [])
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: W), end: CGPoint(x: 0, y: W - edge), options: [])
        }
        return ctx.makeImage()
    }

    /// 小さな色むら画像（拡大描画で滑らかな斑になる）。
    static func noiseImage(size: Int, seed: UInt64, colors: [RGB]) -> CGImage? {
        guard !colors.isEmpty else { return nil }
        var rng = RenderRNG(seed: seed)
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            let a = colors[Int(rng.nextFloat() * Float(colors.count)) % colors.count]
            let b = colors[Int(rng.nextFloat() * Float(colors.count)) % colors.count]
            let c = a.mixed(b, Double(rng.nextFloat()))
            bytes[i * 4] = UInt8(max(0, min(255, c.r * 255)))
            bytes[i * 4 + 1] = UInt8(max(0, min(255, c.g * 255)))
            bytes[i * 4 + 2] = UInt8(max(0, min(255, c.b * 255)))
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// 地図外周（森の地面）用の小さなタイル。
    static func outerImage(size: Int = 256) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 0.10, green: 0.20, blue: 0.13, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        if let noise = noiseImage(size: 24, seed: 91, colors: [RGB(0.07, 0.16, 0.10), RGB(0.14, 0.26, 0.15), RGB(0.10, 0.22, 0.18)]) {
            ctx.interpolationQuality = .high
            ctx.draw(noise, in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        return ctx.makeImage()
    }
}

/// 生成済みの地面テクスチャ（CGImage）の共有キャッシュ。地図・一辺・色覚設定が同じなら試合をまたいで使い回す。
/// ロード画面（BattlePreload）が次の試合の分を先に作り始め、BattleRenderer は出来上がりを受け取るだけになる。
/// 同時に生成中のものは 1 つの Task を共有する（同じ画像を 2 回作らない）。保持は直近 capacity 件で、メモリ警告で手放す。
@MainActor
enum GroundTextureCache {
    struct Key: Hashable {
        let map: MapDefinition
        let size: Int
        let colorblind: Bool
    }

    /// 保持する画像の数（2048² で 16 MB / 1024² で 4 MB）。
    static let capacity = 1
    private static var images: [Key: CGImage] = [:]
    private static var order: [Key] = []
    private static var tasks: [Key: Task<CGImage?, Never>] = [:]
    private static var memoryObserver: NSObjectProtocol?
    /// 実際に生成した回数（テスト・計測用）。
    private(set) static var generatedCount = 0
    /// 直近の生成にかかった時間（ms。計測ログ用）。
    private(set) static var lastGenerateMs: Double?

    static func key(map: MapDefinition, size: Int, colorblind: Bool) -> Key {
        Key(map: map, size: max(64, size), colorblind: colorblind)
    }

    /// 生成済みなら返す（待たない）。
    static func cached(map: MapDefinition, size: Int, colorblind: Bool) -> CGImage? {
        images[key(map: map, size: size, colorblind: colorblind)]
    }

    /// 生成中か。
    static func isGenerating(map: MapDefinition, size: Int, colorblind: Bool) -> Bool {
        tasks[key(map: map, size: size, colorblind: colorblind)] != nil
    }

    /// 生成を先に始める（済み・生成中なら何もしない）。
    static func prefetch(map: MapDefinition, size: Int, colorblind: Bool) {
        let k = key(map: map, size: size, colorblind: colorblind)
        guard images[k] == nil else { return }
        _ = task(for: k)
    }

    /// 画像を得る（生成済みならすぐ、生成中ならその完了を待つ、無ければメインスレッド外で生成する）。
    static func image(map: MapDefinition, size: Int, colorblind: Bool) async -> CGImage? {
        let k = key(map: map, size: size, colorblind: colorblind)
        if let img = images[k] {
            touch(k)
            return img
        }
        return await task(for: k).value
    }

    /// メモリ警告を受けた（すべて手放す）。
    static func handleMemoryWarning() { evictAll() }

    /// すべて手放す（メモリ警告・テスト）。生成中のものは完了後にキャッシュへ入る。
    static func evictAll() {
        images.removeAll()
        order.removeAll()
    }

    private static func task(for k: Key) -> Task<CGImage?, Never> {
        if let t = tasks[k] { return t }
        observeMemoryWarnings()
        let t = Task { @MainActor () -> CGImage? in
            let start = CACurrentMediaTime()
            let img = await Task.detached(priority: .userInitiated) {
                GroundTextureGenerator.makeImage(map: k.map, size: k.size, colorblind: k.colorblind)
            }.value
            generatedCount += 1
            lastGenerateMs = (CACurrentMediaTime() - start) * 1000
            tasks[k] = nil
            if let img { store(img, for: k) }
            return img
        }
        tasks[k] = t
        return t
    }

    private static func store(_ img: CGImage, for k: Key) {
        images[k] = img
        touch(k)
        while order.count > capacity {
            let old = order.removeFirst()
            images[old] = nil
        }
    }

    private static func touch(_ k: Key) {
        order.removeAll { $0 == k }
        order.append(k)
    }

    private static func observeMemoryWarnings() {
        guard memoryObserver == nil else { return }
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { GroundTextureCache.handleMemoryWarning() }
        }
    }
}
