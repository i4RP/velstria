import SwiftUI
import VelstriaCore

// 担当: home-showcase。ホーム中央のヒーローの絵（HeroSplash）。人物マスク（HeroSplashMatte）があれば人物は通常合成、
// 絵の星雲は .screen で背景に重ねてオーラにする。マスクが無ければ縁をぼかした絵全体を通常合成する。
// animated が偽の間は呼吸などの動きを止める。

struct HomeHeroArt: View {
    let heroID: String
    let skinID: String?
    let size: CGSize
    let animated: Bool

    var body: some View {
        let glow = Color(hue: Theme.heroHue(heroID), saturation: 0.6, brightness: 1)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { timeline in
            let t = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            let breath = 1 + 0.009 * CGFloat(sin(t * 1.25))
            let shimmer = 0.85 + 0.15 * sin(t * 0.9)
            content(glow: glow, shimmer: shimmer)
                .scaleEffect(breath, anchor: .bottom)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(glow: Color, shimmer: Double) -> some View {
        if let art = HomeArt.splash(heroID: heroID, skinID: skinID) {
            let image = Image(uiImage: art).resizable().interpolation(.high)
            if let matte = HomeArt.matte(heroID: heroID, skinID: skinID) {
                let mask = Image(uiImage: matte).resizable().interpolation(.high).luminanceToAlpha()
                ZStack {
                    // 絵の星雲を戦場に重ねる（加算寄りの .screen、縁へ向かって消える）
                    image
                        .blendMode(.screen)
                        .opacity(0.5 * shimmer)
                        .mask(RadialGradient(colors: [.white, .white.opacity(0.4), .clear], center: UnitPoint(x: 0.5, y: 0.42),
                                             startRadius: 0, endRadius: size.width * 0.52))
                    // 人物の輪郭の発光
                    Rectangle()
                        .fill(glow)
                        .mask(mask)
                        .blur(radius: 14)
                        .opacity(0.75 * shimmer)
                        .blendMode(.plusLighter)
                    // 人物（下端と左右の端は溶かす）
                    image
                        .mask(mask)
                        .mask(edgeFade)
                }
            } else {
                image
                    .mask(RadialGradient(colors: [.white, .white, .clear], center: UnitPoint(x: 0.5, y: 0.4),
                                         startRadius: 0, endRadius: size.width * 0.56))
                    .mask(edgeFade)
            }
        } else {
            HeroPortraitView(heroID: heroID, size: size.width * 0.6, showsRole: false)
                .glowPulse(glow, radius: 20)
        }
    }

    /// 下端（フッターの手前）と左右の端を透明へ。
    private var edgeFade: some View {
        ZStack {
            LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.66), .init(color: .clear, location: 0.93)],
                           startPoint: .top, endPoint: .bottom)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.12),
                                             .init(color: .white, location: 0.88), .init(color: .clear, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
        }
    }
}
