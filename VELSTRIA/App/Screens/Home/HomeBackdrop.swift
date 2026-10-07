import SwiftUI
import VelstriaCore

// 担当: home-showcase。ホームの背景「星環の戦場」: 背景アート（HomeBackdrop）のゆっくりしたドリフト、星の明滅、
// 漂う火の粉と星屑、クロームの文字を読ませるためのスクリム。アートが無いときは手続きの星空と星環で代用する。
// animated が偽（ホームが前面でない・視差効果を減らす）の間はすべて止まる。

struct HomeBackdrop: View {
    let metrics: HomeMetrics
    let heroID: String
    let animated: Bool

    /// 背景アート上の星（星環の中心）の位置（画像に対する比率）。tools/portraits/home_backdrop.md の構図。
    static let starAnchor = CGPoint(x: 0.5, y: 0.33)

    var body: some View {
        let size = metrics.size
        ZStack {
            HomeStyle.ink
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { timeline in
                let t = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
                ZStack {
                    art(size: size, time: t)
                    HomeParticles(size: size, time: t)
                }
            }
            scrims(size: size)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: アート

    @ViewBuilder
    private func art(size: CGSize, time t: Double) -> some View {
        if let image = HomeArt.backdrop {
            let fill = Self.aspectFillRect(image: image.size, in: size)
            // 少し大きく敷いて、ゆっくり漂わせる（端が見えない範囲で）
            let scale: CGFloat = 1.06
            let dx = CGFloat(sin(t * 0.045)) * size.width * 0.012
            let dy = CGFloat(cos(t * 0.037)) * size.height * 0.008
            let star = CGPoint(x: fill.minX + fill.width * Self.starAnchor.x, y: fill.minY + fill.height * Self.starAnchor.y)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fill.width, height: fill.height)
                    .position(x: fill.midX, y: fill.midY)
                starPulse(at: star, size: size, time: t)
            }
            .scaleEffect(scale, anchor: UnitPoint(x: star.x / max(1, size.width), y: star.y / max(1, size.height)))
            .offset(x: dx, y: dy)
        } else {
            ZStack {
                StarfieldBackground()
                StarRingView(tint: Theme.cyan, accent: Theme.gold, speed: 0.02, starCount: 40, tilt: -8, showsCore: true)
                    .frame(width: size.width * 0.7, height: size.height * 0.8)
                    .position(x: size.width / 2, y: size.height * 0.36)
            }
        }
    }

    /// 星環の中心の星の明滅（加算の光だまり + 十字の光条）。
    private func starPulse(at p: CGPoint, size: CGSize, time t: Double) -> some View {
        let pulse = 0.75 + 0.25 * sin(t * 1.7)
        let r = size.height * 0.16
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.55 * pulse), Theme.cyan.opacity(0.25 * pulse), .clear],
                                     center: .center, startRadius: 0, endRadius: r))
                .frame(width: r * 2, height: r * 2)
            Capsule()
                .fill(LinearGradient(colors: [.clear, Color.white.opacity(0.5 * pulse), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: r * 3.2 * pulse, height: 1.5)
            Capsule()
                .fill(LinearGradient(colors: [.clear, Color.white.opacity(0.45 * pulse), .clear], startPoint: .top, endPoint: .bottom))
                .frame(width: 1.5, height: r * 2.4 * pulse)
        }
        .position(p)
        .blendMode(.plusLighter)
    }

    // MARK: スクリム

    /// ヘッダー・フッター・左右レールの文字が背景に負けないよう、周辺を暗くする。中央はヒーローのために明るく残す。
    private func scrims(size: CGSize) -> some View {
        let m = metrics
        let hue = Theme.heroHue(heroID)
        let center = CGPoint(x: m.centerRect.midX / max(1, size.width), y: 0.45)
        return ZStack {
            // ヒーロー固有色の淡いオーラ
            RadialGradient(colors: [Color(hue: hue, saturation: 0.65, brightness: 1).opacity(0.22), .clear],
                           center: UnitPoint(x: center.x, y: center.y), startRadius: 4, endRadius: size.height * 0.75)
                .blendMode(.plusLighter)
            LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .clear, location: 0.24)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [.init(color: .black.opacity(0.72), location: 0), .init(color: .clear, location: 0.34)],
                           startPoint: .bottom, endPoint: .top)
            LinearGradient(stops: [.init(color: .black.opacity(0.5), location: 0), .init(color: .clear, location: 0.3)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .clear, location: 0.34)],
                           startPoint: .trailing, endPoint: .leading)
        }
    }

    /// 画像を領域いっぱいに（はみ出しを切って）置いたときの矩形。
    static func aspectFillRect(image: CGSize, in area: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return CGRect(origin: .zero, size: area) }
        let scale = max(area.width / image.width, area.height / image.height)
        let w = image.width * scale
        let h = image.height * scale
        return CGRect(x: (area.width - w) / 2, y: (area.height - h) / 2, width: w, height: h)
    }
}

// MARK: - 粒子

/// 漂う火の粉と星屑（加算合成）。左は青い結晶の光、右は赤い炎の火の粉、中央は金と白の星屑。
/// 位置は時刻だけから決める（状態を持たないので、止めても再開しても破綻しない）。
private struct HomeParticles: View {
    let size: CGSize
    let time: Double

    static let count = 54

    var body: some View {
        Canvas { ctx, size in
            ctx.blendMode = .plusLighter
            var rng = SplitMix64(seed: 0x5E15_1A)
            for i in 0..<Self.count {
                let x0 = rng.nextDouble()
                let phase0 = rng.nextDouble()
                let life = 7 + rng.nextDouble() * 7
                let sway = 0.01 + rng.nextDouble() * 0.025
                let radius = 0.6 + rng.nextDouble() * 1.6
                let rise = 0.45 + rng.nextDouble() * 0.55
                let p = (time / life + phase0).truncatingRemainder(dividingBy: 1)
                let x = (x0 + sin(time * 0.6 + Double(i)) * sway) * size.width
                let y = size.height * (1.04 - p * rise)
                let alpha = sin(p * .pi) * (0.35 + 0.5 * rng.nextDouble())
                let color: Color = x0 < 0.3 ? Theme.cyan : (x0 > 0.72 ? HomeStyle.ember : (i % 3 == 0 ? Theme.gold : .white))
                let r = CGFloat(radius)
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -r * 1.5, dy: -r * 1.5)), with: .color(color.opacity(alpha * 0.25)))
                ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
