import SwiftUI
import VelstriaCore

// 担当: ui-collection。コスメ・商品の手続き生成プレビュー（3D アセット導入前の表示）。
// 種類毎: スキン = 描き下ろしポートレート（tools/portraits/）、帰還 = 渦巻くリング、出現 = 立ち上る光柱、
// キル演出 = 放射バースト、エモート = 記号入り吹き出し、フレーム = 装飾枠。

struct CosmeticPreviewView: View {
    let cosmetic: CosmeticDef
    var size: CGFloat = 96
    var animated = true
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if cosmetic.type == .heroSkin {
                SkinPortraitView(heroID: cosmetic.heroID, variant: CosmeticInfo.variant(of: cosmetic),
                                 rarity: cosmetic.rarity, size: size, cosmeticID: cosmetic.cosmeticID)
            } else {
                effectTile
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(MasterText.cosmetic(cosmetic))、\(CollectionStyle.cosmeticTypeName(cosmetic.type))")
    }

    private var effectTile: some View {
        let rarity = Theme.rarityColor(cosmetic.rarity)
        let ordinal = CosmeticInfo.ordinal(of: cosmetic, master: app.master)
        let style = CosmeticPaintStyle(
            type: cosmetic.type,
            primary: rarity,
            accent: Color(hue: (0.55 + 0.23 * Double(ordinal)).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 1),
            level: Rarity.allCases.firstIndex(of: cosmetic.rarity) ?? 0,
            variant: CosmeticInfo.variant(of: cosmetic),
            symbol: cosmetic.type == .emote ? CosmeticInfo.emoteSymbol(cosmetic, master: app.master) : nil)
        let shape = RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
        let running = animated && !reduceMotion
        return ZStack {
            shape.fill(RadialGradient(colors: [rarity.opacity(0.30), Color(red: 0.05, green: 0.05, blue: 0.13)],
                                      center: .center, startRadius: 2, endRadius: size * 0.75))
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !running)) { tl in
                let t = running ? tl.date.timeIntervalSinceReferenceDate : 0.9
                Canvas { ctx, sz in
                    CosmeticPainter.draw(style, in: &ctx, size: sz, time: t)
                }
            }
            .clipShape(shape)
            shape.strokeBorder(LinearGradient(colors: [rarity, rarity.opacity(0.35)], startPoint: .top, endPoint: .bottom),
                               lineWidth: max(1.5, size * 0.025))
        }
        .frame(width: size, height: size)
    }
}

/// 描画パラメータ。
struct CosmeticPaintStyle {
    var type: CosmeticType
    var primary: Color
    var accent: Color
    /// レアリティ段階 0〜3（粒子数・発光量）。
    var level: Int
    var variant: Int
    var symbol: String?
}

enum CosmeticPainter {
    static func draw(_ s: CosmeticPaintStyle, in ctx: inout GraphicsContext, size: CGSize, time t: Double) {
        switch s.type {
        case .recall: recall(s, &ctx, size, t)
        case .spawn: spawn(s, &ctx, size, t)
        case .killEffect: burst(s, &ctx, size, t)
        case .emote: emote(s, &ctx, size, t)
        case .avatarFrame: frame(s, &ctx, size, t)
        case .heroSkin: break
        }
    }

    /// 決定的な擬似乱数（0..<1）。
    static func hash(_ i: Int, _ salt: Int = 0) -> Double {
        var x = UInt64(truncatingIfNeeded: i &* 73_856_093 ^ salt &* 19_349_663) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x % 10_000) / 10_000
    }

    static func frac(_ v: Double) -> Double { v - floor(v) }

    // 帰還: 回転する複数の弧と、中心へ吸い込まれる粒子。
    private static func recall(_ s: CosmeticPaintStyle, _ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height * 0.52)
        let R = Double(min(size.width, size.height)) * 0.36
        // 足元の円
        let base = CGRect(x: c.x - R, y: c.y + R * 0.35, width: R * 2, height: R * 0.5)
        ctx.fill(Path(ellipseIn: base), with: .color(s.primary.opacity(0.18)))
        ctx.stroke(Path(ellipseIn: base), with: .color(s.primary.opacity(0.55)), lineWidth: 1.2)
        let arcs = 3 + s.variant
        for k in 0..<arcs {
            let dir: Double = k % 2 == 0 ? 1 : -1
            let start = t * (1.3 + 0.35 * Double(k)) * dir + Double(k) * 2 * .pi / Double(arcs)
            let sweep = 1.0 + 0.25 * Double(s.level)
            let r = R * (0.55 + 0.16 * Double(k))
            var p = Path()
            p.addArc(center: c, radius: r, startAngle: .radians(start), endAngle: .radians(start + sweep), clockwise: false)
            let col = k % 2 == 0 ? s.primary : s.accent
            ctx.stroke(p, with: .color(col.opacity(0.35)), style: StrokeStyle(lineWidth: R * 0.16, lineCap: .round))
            ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: R * 0.05, lineCap: .round))
        }
        let n = 8 + 4 * s.level
        for i in 0..<n {
            let ph = frac(t * 0.45 + hash(i))
            let a = t * 1.6 + Double(i) * 2 * .pi / Double(n)
            let r = R * (1.15 - ph)
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * 0.8)
            let d = 1.5 + 2.5 * (1 - ph)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - d / 2, y: pt.y - d / 2, width: d, height: d)),
                     with: .color(.white.opacity(0.4 + 0.6 * ph)))
        }
        // 中心の星
        let glow = R * (0.18 + 0.05 * sin(t * 4))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - glow, y: c.y - glow, width: glow * 2, height: glow * 2)),
                 with: .radialGradient(Gradient(colors: [.white, s.primary.opacity(0)]), center: c, startRadius: 0, endRadius: glow))
    }

    // 出現: 足元の魔法陣から立ち上る光柱と上昇粒子。
    private static func spawn(_ s: CosmeticPaintStyle, _ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = Double(size.width), h = Double(size.height)
        let baseY = h * 0.8
        let cx = w / 2
        let pulse = 0.5 + 0.5 * sin(t * 3)
        let beamW = w * (0.2 + 0.03 * pulse + 0.03 * Double(s.level))
        let beam = CGRect(x: cx - beamW / 2, y: 0, width: beamW, height: baseY)
        ctx.fill(Path(beam), with: .linearGradient(Gradient(colors: [s.primary.opacity(0), s.primary.opacity(0.75)]),
                                                   startPoint: CGPoint(x: cx, y: 0), endPoint: CGPoint(x: cx, y: baseY)))
        let core = CGRect(x: cx - beamW * 0.18, y: h * 0.05, width: beamW * 0.36, height: baseY - h * 0.05)
        ctx.fill(Path(core), with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.9)]),
                                                   startPoint: CGPoint(x: cx, y: h * 0.05), endPoint: CGPoint(x: cx, y: baseY)))
        // 魔法陣
        let ringW = w * 0.7
        let ring = CGRect(x: cx - ringW / 2, y: baseY - h * 0.08, width: ringW, height: h * 0.16)
        ctx.stroke(Path(ellipseIn: ring), with: .color(s.accent.opacity(0.9)), lineWidth: 1.6)
        ctx.stroke(Path(ellipseIn: ring.insetBy(dx: ringW * 0.12, dy: h * 0.02)), with: .color(s.primary.opacity(0.7)), lineWidth: 1)
        let marks = 6 + 2 * s.variant
        for i in 0..<marks {
            let a = t * 0.8 + Double(i) * 2 * .pi / Double(marks)
            let pt = CGPoint(x: cx + cos(a) * ringW * 0.42, y: baseY + sin(a) * h * 0.065)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.9)))
        }
        // 上昇粒子
        let n = 10 + 5 * s.level
        for i in 0..<n {
            let ph = frac(t * (0.35 + 0.2 * hash(i, 3)) + hash(i, 1))
            let x = cx + (hash(i, 2) - 0.5) * w * 0.55
            let y = baseY - ph * baseY * 0.95
            let d = 1.5 + 3 * (1 - ph)
            let col = i % 3 == 0 ? s.accent : Color.white
            ctx.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)), with: .color(col.opacity(1 - ph)))
        }
        if s.variant == 2 {
            // 稲妻
            var bolt = Path()
            let ph = frac(t * 0.7)
            bolt.move(to: CGPoint(x: cx, y: 0))
            for k in 1...6 {
                let y = baseY * Double(k) / 6
                bolt.addLine(to: CGPoint(x: cx + (hash(k, Int(t * 6)) - 0.5) * beamW, y: y))
            }
            ctx.stroke(bolt, with: .color(.white.opacity(0.8 * (1 - ph))), lineWidth: 1.5)
        }
    }

    // キル演出: 周期的な放射バースト（リング + 棘 + 破片）。
    private static func burst(_ s: CosmeticPaintStyle, _ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = Double(min(size.width, size.height)) * 0.44
        let ph = frac(t / 1.6)
        let ease = 1 - pow(1 - ph, 3)
        // 衝撃波
        let rr = R * ease * 1.1
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                   with: .color(s.primary.opacity(1 - ph)), lineWidth: 2 + 4 * (1 - ph))
        // 棘
        let spikes = 8 + 2 * s.level
        let offset = Double(s.variant) * .pi / Double(spikes)
        for i in 0..<spikes {
            let a = offset + Double(i) * 2 * .pi / Double(spikes)
            let len = R * (0.35 + 0.65 * ease) * (i % 2 == 0 ? 1 : 0.7)
            let r0 = R * 0.12
            let half = 0.09
            var p = Path()
            p.move(to: CGPoint(x: c.x + cos(a - half) * r0, y: c.y + sin(a - half) * r0))
            p.addLine(to: CGPoint(x: c.x + cos(a) * len, y: c.y + sin(a) * len))
            p.addLine(to: CGPoint(x: c.x + cos(a + half) * r0, y: c.y + sin(a + half) * r0))
            p.closeSubpath()
            let col = i % 2 == 0 ? s.primary : s.accent
            ctx.fill(p, with: .color(col.opacity(0.85 * (1 - ph * 0.7))))
        }
        // 破片
        let shards = 6 + 3 * s.level
        for i in 0..<shards {
            let a = hash(i, 5) * 2 * .pi
            let d = R * (0.2 + 0.9 * ease) * (0.6 + 0.4 * hash(i, 6))
            let pt = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
            let sz = 2 + 3 * (1 - ph)
            ctx.fill(Path(CGRect(x: pt.x - sz / 2, y: pt.y - sz / 2, width: sz, height: sz)), with: .color(.white.opacity(1 - ph)))
        }
        // 閃光
        let f = R * 0.3 * (1 - ph)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - f, y: c.y - f, width: f * 2, height: f * 2)), with: .color(.white.opacity(0.9)))
        // 中央の印（ドクロ代わりの星）
        var star = Path()
        let sr = R * 0.2
        for k in 0..<10 {
            let a = -Double.pi / 2 + Double(k) * .pi / 5
            let r = k % 2 == 0 ? sr : sr * 0.45
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if k == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
        }
        star.closeSubpath()
        ctx.fill(star, with: .color(s.accent.opacity(0.4 + 0.6 * ph)))
    }

    // エモート: 跳ねる吹き出しと記号。
    private static func emote(_ s: CosmeticPaintStyle, _ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = Double(size.width), h = Double(size.height)
        let bounce = sin(t * 3.2) * h * 0.03
        let bw = w * 0.66, bh = h * 0.48
        let rect = CGRect(x: (w - bw) / 2, y: h * 0.18 + bounce, width: bw, height: bh)
        var bubble = Path(roundedRect: rect, cornerRadius: bh * 0.32, style: .continuous)
        var tail = Path()
        tail.move(to: CGPoint(x: rect.minX + bw * 0.22, y: rect.maxY - 2))
        tail.addLine(to: CGPoint(x: rect.minX + bw * 0.12, y: rect.maxY + h * 0.14))
        tail.addLine(to: CGPoint(x: rect.minX + bw * 0.42, y: rect.maxY - 2))
        tail.closeSubpath()
        bubble.addPath(tail)
        ctx.fill(bubble, with: .linearGradient(Gradient(colors: [s.accent.opacity(0.95), s.primary.opacity(0.8)]),
                                               startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        ctx.stroke(bubble, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
        if let symbol = s.symbol {
            var img = ctx.resolve(Image(systemName: symbol))
            img.shading = .color(.white)
            let side = bh * 0.62
            let scale = 1 + 0.06 * sin(t * 6)
            ctx.draw(img, in: CGRect(x: rect.midX - side * scale / 2, y: rect.midY - side * scale / 2,
                                     width: side * scale, height: side * scale))
        }
        // 周囲のきらめき
        let n = 2 + s.level
        for i in 0..<n {
            let ph = frac(t * 0.6 + Double(i) / Double(n))
            let a = -Double.pi / 4 + Double(i) * 0.9
            let d = w * (0.36 + 0.12 * ph)
            let pt = CGPoint(x: w / 2 + cos(a) * d, y: h * 0.42 + sin(a) * d * 0.7)
            let sz = 3 + 3 * (1 - ph)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - sz / 2, y: pt.y - sz / 2, width: sz, height: sz)),
                     with: .color(.white.opacity(1 - ph)))
        }
    }

    // フレーム: 多重枠・角の宝石・枠を走る光。
    private static func frame(_ s: CosmeticPaintStyle, _ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = Double(size.width), h = Double(size.height)
        let outer = CGRect(x: w * 0.12, y: h * 0.12, width: w * 0.76, height: h * 0.76)
        let shapePath: (CGRect) -> Path = { r in
            switch s.variant {
            case 1: return Path(ellipseIn: r)
            case 2: return CollectionChamferShape(chamfer: 0.24).path(in: r)
            default: return Path(roundedRect: r, cornerRadius: r.width * 0.18, style: .continuous)
            }
        }
        // 中の人影
        var person = ctx.resolve(Image(systemName: "person.fill"))
        person.shading = .color(.white.opacity(0.28))
        let ps = outer.width * 0.5
        ctx.draw(person, in: CGRect(x: outer.midX - ps / 2, y: outer.midY - ps / 2 + outer.height * 0.05, width: ps, height: ps))
        let outerPath = shapePath(outer)
        ctx.stroke(outerPath, with: .linearGradient(Gradient(colors: [s.primary, s.accent, s.primary]),
                                                    startPoint: CGPoint(x: outer.minX, y: outer.minY),
                                                    endPoint: CGPoint(x: outer.maxX, y: outer.maxY)),
                   lineWidth: w * 0.05)
        ctx.stroke(shapePath(outer.insetBy(dx: w * 0.06, dy: h * 0.06)), with: .color(s.primary.opacity(0.6)), lineWidth: 1)
        // 枠を走る光
        let head = frac(t * 0.22)
        let seg = outerPath.trimmedPath(from: head, to: min(1, head + 0.14))
        ctx.stroke(seg, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: w * 0.03, lineCap: .round))
        if head + 0.14 > 1 {
            ctx.stroke(outerPath.trimmedPath(from: 0, to: head + 0.14 - 1), with: .color(.white.opacity(0.95)),
                       style: StrokeStyle(lineWidth: w * 0.03, lineCap: .round))
        }
        // 角の宝石
        let gem = w * (0.07 + 0.01 * Double(s.level))
        let corners = [CGPoint(x: outer.minX, y: outer.minY), CGPoint(x: outer.maxX, y: outer.minY),
                       CGPoint(x: outer.minX, y: outer.maxY), CGPoint(x: outer.maxX, y: outer.maxY)]
        for (i, p) in corners.enumerated() {
            let g = gem * (1 + 0.12 * sin(t * 3 + Double(i)))
            var d = Path()
            d.move(to: CGPoint(x: p.x, y: p.y - g))
            d.addLine(to: CGPoint(x: p.x + g, y: p.y))
            d.addLine(to: CGPoint(x: p.x, y: p.y + g))
            d.addLine(to: CGPoint(x: p.x - g, y: p.y))
            d.closeSubpath()
            ctx.fill(d, with: .color(s.accent))
            ctx.stroke(d, with: .color(.white.opacity(0.9)), lineWidth: 1)
        }
        // 上位レアリティは頂部の紋章
        if s.level >= 2 {
            var crest = ctx.resolve(Image(systemName: s.level >= 3 ? "crown.fill" : "star.fill"))
            crest.shading = .color(s.primary)
            let cs = w * 0.16
            ctx.draw(crest, in: CGRect(x: w / 2 - cs / 2, y: outer.minY - cs * 0.75, width: cs, height: cs))
        }
    }
}

/// スキンのプレビュー（スキンの描き下ろしアート + レアリティ枠。アートが無ければヒーローポートレートを色替え）。
struct SkinPortraitView: View {
    let heroID: String
    let variant: Int
    let rarity: Rarity
    var size: CGFloat = 96
    var cosmeticID: String?

    static func hueShift(_ variant: Int) -> Double {
        [150, 230, 60][((variant % 3) + 3) % 3]
    }

    var body: some View {
        let rc = Theme.rarityColor(rarity)
        let shape = RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
        ZStack {
            if let art = cosmeticID.flatMap({ PortraitArt.skin($0) }) {
                Image(uiImage: art)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(shape)
            } else {
                recolored(shape)
            }
            shape.strokeBorder(LinearGradient(colors: [rc, rc.opacity(0.45), rc], startPoint: .topLeading, endPoint: .bottomTrailing),
                               lineWidth: max(2, size * 0.045))
            Text(["I", "II", "III", "IV", "V"][min(4, max(0, variant))])
                .font(.system(size: max(8, size * 0.12), weight: .black, design: .serif))
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, size * 0.05)
                .background(Capsule().fill(rc))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(size * 0.07)
        }
        .frame(width: size, height: size)
        .shadow(color: rc.opacity(0.45), radius: size * 0.06)
    }

    /// アートの無いスキン: ヒーローポートレートの色替え + バリエーション毎の模様。
    private func recolored(_ shape: RoundedRectangle) -> some View {
        ZStack {
            HeroPortraitView(heroID: heroID, size: size, showsRole: false)
                .hueRotation(.degrees(Self.hueShift(variant)))
                .saturation(1.15)
            Canvas { ctx, sz in
                switch variant % 3 {
                case 0:
                    // 光沢の斜線
                    for i in 0..<4 {
                        var p = Path()
                        let x = sz.width * (0.1 + 0.28 * Double(i))
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x - sz.width * 0.35, y: sz.height))
                        ctx.stroke(p, with: .color(.white.opacity(i % 2 == 0 ? 0.16 : 0.08)), lineWidth: sz.width * 0.06)
                    }
                case 1:
                    // 星屑
                    for i in 0..<18 {
                        let x = CosmeticPainter.hash(i, 11) * sz.width
                        let y = CosmeticPainter.hash(i, 12) * sz.height
                        let d = 1 + CosmeticPainter.hash(i, 13) * 2.5
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(.white.opacity(0.7)))
                    }
                default:
                    // 同心円
                    for i in 1...4 {
                        let r = sz.width * 0.16 * Double(i)
                        ctx.stroke(Path(ellipseIn: CGRect(x: sz.width / 2 - r, y: sz.height * 0.45 - r, width: r * 2, height: r * 2)),
                                   with: .color(.white.opacity(0.12)), lineWidth: 1.2)
                    }
                }
            }
            .clipShape(shape)
            .allowsHitTesting(false)
        }
    }
}

/// バンドルのプレビュー（中身があれば重ねて表示、無ければ紋章）。
struct BundlePreviewView: View {
    let item: StoreItemDef
    var size: CGFloat = 96
    var animated = false
    @Environment(AppModel.self) private var app

    var body: some View {
        let contents = EconomyService.bundleContents(item.grantID, master: app.master).compactMap { app.master.cosmetic($0) }
        ZStack {
            if contents.isEmpty {
                emblem
            } else {
                let shown = Array(contents.prefix(3))
                ForEach(Array(shown.enumerated()), id: \.offset) { i, c in
                    let mid = Double(shown.count - 1) / 2
                    CosmeticPreviewView(cosmetic: c, size: size * 0.62, animated: animated)
                        .rotationEffect(.degrees((Double(i) - mid) * 12))
                        .offset(x: (Double(i) - mid) * size * 0.2, y: abs(Double(i) - mid) * size * 0.05)
                        .zIndex(Double(i) == mid ? 1 : 0)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(MasterText.storeItem(item))
    }

    private var emblem: some View {
        let n = Int(item.grantID.suffix(2)) ?? 1
        let hue = (0.08 + 0.137 * Double(n)).truncatingRemainder(dividingBy: 1)
        let c = Color(hue: hue, saturation: 0.6, brightness: 1)
        return ZStack {
            CollectionPolygonShape(sides: 6)
                .fill(RadialGradient(colors: [c.opacity(0.9), Color(hue: hue, saturation: 0.8, brightness: 0.25)],
                                     center: .init(x: 0.4, y: 0.35), startRadius: 2, endRadius: size * 0.6))
            CollectionPolygonShape(sides: 6)
                .stroke(LinearGradient(colors: [Theme.gold, c], startPoint: .top, endPoint: .bottom), lineWidth: size * 0.04)
            Circle()
                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .padding(size * 0.16)
            Image(systemName: "gift.fill")
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [.white, Theme.gold], startPoint: .top, endPoint: .bottom))
                .shadow(color: c, radius: 6)
            Text(String(format: "%02d", n))
                .font(.system(size: size * 0.11, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .offset(y: size * 0.3)
        }
    }
}

/// 任意の商品のプレビュー。
struct StoreItemPreview: View {
    let item: StoreItemDef
    var size: CGFloat = 96
    var animated = true
    @Environment(AppModel.self) private var app

    var body: some View {
        switch item.type {
        case .cosmetic:
            if let c = app.master.cosmetic(item.grantID) {
                CosmeticPreviewView(cosmetic: c, size: size, animated: animated)
            } else {
                BundlePreviewView(item: item, size: size, animated: animated)
            }
        case .heroUnlock:
            if animated {
                HeroAuraPortrait(heroID: item.grantID, size: size * 0.6,
                                 color: app.master.hero(item.grantID).map { Theme.roleColor($0.role) } ?? Theme.cyan)
                    .frame(width: size, height: size)
            } else {
                HeroPortraitView(heroID: item.grantID, size: size)
            }
        case .bundle:
            BundlePreviewView(item: item, size: size, animated: animated)
        }
    }
}

/// レアリティ表示。
struct CollectionRarityTag: View {
    let rarity: Rarity

    var body: some View {
        let c = Theme.rarityColor(rarity)
        HStack(spacing: 3) {
            Image(systemName: "diamond.fill").font(.system(size: 8, weight: .bold))
            Text(CollectionStyle.rarityName(rarity)).font(Theme.body(11))
        }
        .foregroundStyle(c)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(c.opacity(0.16)))
        .overlay(Capsule().stroke(c.opacity(0.5), lineWidth: 0.8))
        .accessibilityLabel(L("レアリティ \(CollectionStyle.rarityName(rarity))", "Rarity \(CollectionStyle.rarityName(rarity))"))
    }
}

/// 価格表示（通貨アイコン + 数値）。
struct PriceTag: View {
    let currency: Currency
    let amount: Int
    var size: CGFloat = 13
    var insufficient = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: CollectionStyle.currencySymbol(currency))
                .font(.system(size: size * 0.9, weight: .bold))
                .foregroundStyle(CollectionStyle.currencyColor(currency))
            Text(amount.formatted())
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(insufficient ? Theme.danger : Theme.textPrimary)
        }
        .accessibilityElement()
        .accessibilityLabel("\(amount.formatted()) \(CollectionStyle.currencyName(currency))")
    }
}
