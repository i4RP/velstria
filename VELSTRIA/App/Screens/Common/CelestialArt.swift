import SwiftUI
import VelstriaCore

// 試合の外の共通の絵（採用案 Celestial Saber の画風: 銀青の地に金の縁、細い線、四芒星）。画像ではなくベクターで描く
// （どの大きさでもにじまず、アプリの容量も増えない）。ランクの紋章（RankCrest。RankEmblemView が使う）と通貨のアイコン（CurrencyIcon）。

// MARK: - 通貨

/// 通貨のアイコン。コイン（StarlightCoin）= 四芒星を刻んだ金貨、ジェム（AstralGem）= 氷青の多面体（有償は紫）。
struct CurrencyIcon: View {
    enum Kind { case coin, gem, paidGem }
    let kind: Kind
    var size: CGFloat = 16

    var body: some View {
        Group {
            switch kind {
            case .coin: coin
            case .gem: gem(light: Color(red: 0.85, green: 0.96, blue: 1), mid: Color(red: 0.42, green: 0.80, blue: 1),
                           deep: Color(red: 0.10, green: 0.36, blue: 0.80))
            case .paidGem: gem(light: Color(red: 0.94, green: 0.86, blue: 1), mid: Color(red: 0.72, green: 0.52, blue: 1),
                               deep: Color(red: 0.36, green: 0.16, blue: 0.72))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var coin: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [HomeStyle.goldLight, Theme.gold, HomeStyle.goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().inset(by: size * 0.13).stroke(HomeStyle.goldDeep.opacity(0.85), lineWidth: max(0.6, size * 0.06))
            CelestialSparkle()
                .fill(LinearGradient(colors: [.white, HomeStyle.goldLight], startPoint: .top, endPoint: .bottom))
                .padding(size * 0.26)
            Circle().trim(from: 0.55, to: 0.75).stroke(.white.opacity(0.75), lineWidth: max(0.5, size * 0.05))
                .padding(size * 0.06)
        }
    }

    private func gem(light: Color, mid: Color, deep: Color) -> some View {
        ZStack {
            GemShape().fill(LinearGradient(colors: [light, mid, deep], startPoint: .top, endPoint: .bottom))
            GemFacets().stroke(.white.opacity(0.55), lineWidth: max(0.4, size * 0.03))
            GemShape().stroke(.white.opacity(0.85), lineWidth: max(0.5, size * 0.045))
        }
        .shadow(color: mid.opacity(0.6), radius: size * 0.08)
    }
}

/// 四芒星（採用案の飾り）。
struct CelestialSparkle: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let pts = [CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
        var p = Path()
        p.move(to: pts[0])
        for i in 1...4 { p.addQuadCurve(to: pts[i % 4], control: c) }
        p.closeSubpath()
        return p
    }
}

/// ジェムの外形（平らな上面・肩・下の尖り）。
private struct GemShape: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        var p = Path()
        p.move(to: pt(0.22, 0.18))
        p.addLine(to: pt(0.78, 0.18))
        p.addLine(to: pt(0.98, 0.40))
        p.addLine(to: pt(0.50, 0.96))
        p.addLine(to: pt(0.02, 0.40))
        p.closeSubpath()
        return p
    }
}

/// ジェムの面の線。
private struct GemFacets: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        var p = Path()
        p.move(to: pt(0.02, 0.40)); p.addLine(to: pt(0.98, 0.40))
        p.move(to: pt(0.22, 0.18)); p.addLine(to: pt(0.34, 0.40)); p.addLine(to: pt(0.50, 0.18)); p.addLine(to: pt(0.66, 0.40)); p.addLine(to: pt(0.78, 0.18))
        p.move(to: pt(0.34, 0.40)); p.addLine(to: pt(0.50, 0.96)); p.addLine(to: pt(0.66, 0.40))
        return p
    }
}

// MARK: - ランクの紋章

/// ランクの紋章。盾の地の色がティア、上のティアほど翼・冠・光輪が増える（ウォリアー → ミシック）。
struct RankCrest: View {
    let tier: RankTier
    var size: CGFloat = 40

    private struct Style {
        var top: Color
        var bottom: Color
        var rim: Color
        /// 翼の段（0 = 無し、1 = 小さな翼、2 = 大きな翼）。
        var wings: Int
        var crown: Bool
        var rays: Bool
    }

    private var style: Style {
        switch tier {
        case .warrior: return Style(top: Color(red: 0.82, green: 0.58, blue: 0.38), bottom: Color(red: 0.42, green: 0.25, blue: 0.14),
                                    rim: Color(red: 0.96, green: 0.80, blue: 0.62), wings: 0, crown: false, rays: false)
        case .elite: return Style(top: Color(red: 0.88, green: 0.92, blue: 0.97), bottom: Color(red: 0.42, green: 0.50, blue: 0.62),
                                  rim: .white, wings: 1, crown: false, rays: false)
        case .master: return Style(top: Color(red: 1.0, green: 0.88, blue: 0.52), bottom: Color(red: 0.72, green: 0.46, blue: 0.12),
                                   rim: HomeStyle.goldLight, wings: 1, crown: false, rays: false)
        case .grandmaster: return Style(top: Color(red: 0.80, green: 0.66, blue: 1.0), bottom: Color(red: 0.34, green: 0.20, blue: 0.68),
                                        rim: Color(red: 0.92, green: 0.88, blue: 1.0), wings: 2, crown: false, rays: false)
        case .epic: return Style(top: Color(red: 0.60, green: 0.92, blue: 1.0), bottom: Color(red: 0.10, green: 0.38, blue: 0.74),
                                 rim: .white, wings: 2, crown: true, rays: false)
        case .legend: return Style(top: Color(red: 1.0, green: 0.62, blue: 0.48), bottom: Color(red: 0.58, green: 0.10, blue: 0.18),
                                   rim: HomeStyle.goldLight, wings: 2, crown: true, rays: false)
        case .mythic: return Style(top: Color(red: 0.80, green: 0.90, blue: 1.0), bottom: Color(red: 0.22, green: 0.34, blue: 0.88),
                                   rim: HomeStyle.goldLight, wings: 2, crown: true, rays: true)
        }
    }

    var body: some View {
        let s = style
        let line = max(0.6, size * 0.035)
        ZStack {
            if s.rays {
                CrestRays().fill(RadialGradient(colors: [HomeStyle.goldLight.opacity(0.9), Theme.gold.opacity(0)], center: .center,
                                                startRadius: 0, endRadius: size * 0.5))
            }
            if s.wings > 0 {
                CrestWings(span: s.wings == 2 ? 1 : 0.72)
                    .fill(LinearGradient(colors: [.white, Color(red: 0.70, green: 0.84, blue: 1.0)], startPoint: .top, endPoint: .bottom))
                CrestWings(span: s.wings == 2 ? 1 : 0.72).stroke(s.rim.opacity(0.9), lineWidth: line * 0.6)
            }
            CrestShield().fill(LinearGradient(colors: [s.top, s.bottom], startPoint: .top, endPoint: .bottom))
            CrestShield().inset(by: size * 0.07).stroke(.white.opacity(0.4), lineWidth: line * 0.7)
            CrestShield().stroke(LinearGradient(colors: [s.rim, s.rim.opacity(0.55)], startPoint: .top, endPoint: .bottom), lineWidth: line)
            CelestialSparkle()
                .fill(LinearGradient(colors: [.white, s.rim], startPoint: .top, endPoint: .bottom))
                .frame(width: size * (0.22 + 0.03 * CGFloat(tier.rawValue)), height: size * (0.26 + 0.03 * CGFloat(tier.rawValue)))
                .offset(y: size * 0.03)
                .shadow(color: .white.opacity(0.6), radius: size * 0.04)
            if s.crown {
                CrestCrown().fill(LinearGradient(colors: [HomeStyle.goldLight, HomeStyle.goldDeep], startPoint: .top, endPoint: .bottom))
                CrestCrown().stroke(.white.opacity(0.7), lineWidth: line * 0.5)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: s.bottom.opacity(0.55), radius: size * 0.12)
        .accessibilityLabel(RankService.tierName(tier))
    }
}

/// 盾（上辺の中央が少し高い、下が尖る）。
private struct CrestShield: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        var p = Path()
        p.move(to: pt(0.26, 0.20))
        p.addLine(to: pt(0.50, 0.15))
        p.addLine(to: pt(0.74, 0.20))
        p.addLine(to: pt(0.74, 0.54))
        p.addQuadCurve(to: pt(0.50, 0.92), control: pt(0.74, 0.80))
        p.addQuadCurve(to: pt(0.26, 0.54), control: pt(0.26, 0.80))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> CrestShield {
        var s = self
        s.insetAmount += amount
        return s
    }
}

/// 左右の翼（羽根 3 枚。span で広がりを変える）。
private struct CrestWings: Shape {
    var span: CGFloat = 1

    func path(in r: CGRect) -> Path {
        var p = Path()
        for side in [-1.0, 1.0] {
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                // x は盾の中心からの距離（0 = 中心、0.5 = 端）
                CGPoint(x: r.midX + CGFloat(side) * r.width * x, y: r.minY + r.height * y)
            }
            let reach = 0.24 + 0.24 * span
            p.move(to: pt(0.22, 0.30))
            p.addLine(to: pt(reach, 0.18))
            p.addLine(to: pt(reach - 0.07, 0.32))
            p.addLine(to: pt(reach + 0.01, 0.36))
            p.addLine(to: pt(reach - 0.09, 0.47))
            p.addLine(to: pt(reach - 0.04, 0.52))
            p.addLine(to: pt(0.22, 0.60))
            p.closeSubpath()
        }
        return p
    }
}

/// 冠（3 つの尖り）。
private struct CrestCrown: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        var p = Path()
        p.move(to: pt(0.34, 0.17))
        p.addLine(to: pt(0.32, 0.05))
        p.addLine(to: pt(0.42, 0.11))
        p.addLine(to: pt(0.50, 0.01))
        p.addLine(to: pt(0.58, 0.11))
        p.addLine(to: pt(0.68, 0.05))
        p.addLine(to: pt(0.66, 0.17))
        p.addLine(to: pt(0.50, 0.14))
        p.closeSubpath()
        return p
    }
}

/// 光輪（12 本の細い光。ミシック）。
private struct CrestRays: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let outer = min(r.width, r.height) * 0.5
        var p = Path()
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi
            let w = 0.08
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + outer * CGFloat(cos(a - w)), y: c.y + outer * CGFloat(sin(a - w))))
            p.addLine(to: CGPoint(x: c.x + outer * CGFloat(cos(a + w)), y: c.y + outer * CGFloat(sin(a + w))))
            p.closeSubpath()
        }
        return p
    }
}
