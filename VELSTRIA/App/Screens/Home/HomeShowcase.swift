import SwiftUI
import VelstriaCore

// 担当: home-showcase。ホーム中央のヒーロー展示（MAIN CHARACTER CONTAINER）。
// - 大きなヒーローアート（HeroSplash）。人物マスク（HeroSplashMatte）があれば人物は通常合成、絵の星雲は .screen で
//   背景の戦場に重ねてオーラにする。マスクが無ければ縁をぼかした絵全体を通常合成する。
// - 左右の矢印・横スワイプで所持ヒーローを巡回（画面内の状態だけ）、ネームプレートでヒーロー詳細へ、3D 表示の切替。
// - isActive（ホームが前面）が偽の間は 3D ビューを階層から外し、animated が偽の間は呼吸などの動きを止める。

struct HomeShowcase: View {
    let metrics: HomeMetrics
    let heroID: String
    let railCollapsed: Bool
    let isActive: Bool
    let animated: Bool
    let entered: Bool
    let onPick: (String) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shows3D = HomeDebug.starts3D
    /// 直前の切替の向き（+1 = 次へ、-1 = 前へ）。入ってくる絵の滑り込む向きに使う。
    @State private var direction = 1

    private var skinID: String? { app.profile.equippedSkins[heroID] }

    private var roster: [String] {
        HomeShowcaseLogic.roster(owned: app.profile.ownedHeroIDs, masterOrder: app.master.heroes.map(\.heroID))
    }

    var body: some View {
        let m = metrics
        let region = m.centerRect(railCollapsed: railCollapsed)
        let artRect = Self.artRect(metrics: m, region: region)
        ZStack(alignment: .topLeading) {
            if shows3D && isActive {
                HeroPreview3DView(heroID: heroID, skinID: skinID)
                    .homePlaced(in: region.insetBy(dx: 30, dy: 0).offsetBy(dx: 0, dy: -6))
                    .transition(.opacity)
            } else {
                HomeHeroArt(heroID: heroID, skinID: skinID, size: artRect.size, animated: animated)
                    .homePlaced(in: artRect)
                    .allowsHitTesting(false)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(x: CGFloat(direction) * 70).combined(with: .opacity),
                        removal: .offset(x: CGFloat(-direction) * 40).combined(with: .opacity)))
                    .id(heroID + (skinID ?? ""))
                swipeArea.homePlaced(in: region)
            }
            controls(region: region)
        }
        .opacity(entered ? 1 : 0)
        .scaleEffect(entered ? 1 : 1.04, anchor: UnitPoint(x: region.midX / max(1, m.size.width), y: 0.6))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: shows3D)
    }

    /// 絵の矩形（正方形）。画面の高さいっぱいを目安に、中央領域より一回り大きく（左右はレールの下へ溶ける）。
    /// 顔（絵の上 25〜45%）がヘッダーに隠れないよう、上端はヘッダーの下端より少しだけ上に置く。
    static func artRect(metrics m: HomeMetrics, region: CGRect) -> CGRect {
        let side = min(m.size.height * 1.02, region.width * 1.55)
        let top = m.headerRect.maxY - side * 0.07
        return CGRect(x: region.midX - side / 2, y: top, width: side, height: side)
    }

    // MARK: 操作

    private var swipeArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { v in
                        guard abs(v.translation.width) > 50, abs(v.translation.width) > abs(v.translation.height) else { return }
                        step(v.translation.width < 0 ? 1 : -1)
                    }
            )
            .accessibilityHidden(true)
    }

    private func step(_ s: Int) {
        let next = HomeShowcaseLogic.neighbor(of: heroID, in: roster, step: s)
        guard next != heroID else { return }
        FlowFX.tap(app)
        direction = s
        withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.12)) { onPick(next) }
    }

    @ViewBuilder
    private func controls(region: CGRect) -> some View {
        let canCycle = roster.count > 1
        let arrowY = region.minY + region.height * 0.46
        if canCycle {
            arrow(symbol: "chevron.left", label: L("前のヒーロー", "Previous hero"), id: "home_showcase_prev") { step(-1) }
                .position(x: region.minX + 24, y: arrowY)
            arrow(symbol: "chevron.right", label: L("次のヒーロー", "Next hero"), id: "home_showcase_next") { step(1) }
                .position(x: region.maxX - 24, y: arrowY)
        }
        toggle3D
            .position(x: region.maxX - 26, y: region.minY + 24)
        HomeHeroNameplate(heroID: heroID, skinID: skinID, animated: animated)
            .frame(maxWidth: min(region.width - 20, 300))
            .position(x: region.midX, y: region.maxY - 27)
    }

    private func arrow(symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .shadow(color: Theme.cyan, radius: 4)
                .frame(width: 30, height: 30)
                .background(HomeDiamond().fill(HomeStyle.ink.opacity(0.65)).frame(width: 36, height: 36))
                .overlay(HomeDiamond().stroke(Theme.cyan.opacity(0.8), lineWidth: 1).frame(width: 36, height: 36))
                .frame(width: HomeMetrics.minTapSize, height: HomeMetrics.minTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.88))
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var toggle3D: some View {
        Button {
            FlowFX.tap(app)
            shows3D.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: shows3D ? "photo.fill" : "cube.transparent.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(shows3D ? "2D" : "3D")
                    .font(HomeFont.tech(12))
            }
            .foregroundStyle(shows3D ? HomeStyle.onGold : .white)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(HomeChamfer(cut: 6, corners: .all).fill(shows3D ? AnyShapeStyle(HomeStyle.goldGradient) : AnyShapeStyle(HomeStyle.ink.opacity(0.65))))
            .overlay(HomeChamfer(cut: 6, corners: .all).stroke(Theme.gold.opacity(0.8), lineWidth: 1))
            .frame(minWidth: HomeMetrics.minTapSize, minHeight: HomeMetrics.minTapSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.9))
        .accessibilityLabel(shows3D ? L("イラスト表示に切り替え", "Show illustration") : L("3D 表示に切り替え", "Show 3D model"))
        .accessibilityIdentifier("home_showcase_3d")
    }
}

// MARK: - アート

/// ヒーローの絵の合成（オーラ + 輪郭の発光 + 人物）。呼吸の拡縮は animated の間だけ。
private struct HomeHeroArt: View {
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

// MARK: - ネームプレート

/// ヒーロー名（Cinzel / 明朝）・ロール・装備スキン。押すとヒーロー詳細へ。
private struct HomeHeroNameplate: View {
    let heroID: String
    let skinID: String?
    let animated: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let hero = app.master.hero(heroID)
        let name = hero.map { MasterText.hero($0) } ?? heroID
        let glow = Color(hue: Theme.heroHue(heroID), saturation: 0.6, brightness: 1)
        Button {
            FlowFX.tap(app)
            app.router.push(.heroDetail(heroID))
        } label: {
            VStack(spacing: 2) {
                Text(name)
                    .font(HomeFont.display(19))
                    .foregroundStyle(LinearGradient(colors: [.white, HomeStyle.goldLight], startPoint: .top, endPoint: .bottom))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .shadow(color: glow.opacity(0.9), radius: 6)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                HStack(spacing: 8) {
                    if let role = hero?.role { RoleLabel(role: role, size: 11) }
                    if let skinID, let skin = app.master.cosmetic(skinID) {
                        Label(MasterText.cosmetic(skin), systemImage: "sparkles")
                            .font(HomeFont.label(10.5))
                            .foregroundStyle(Theme.rarityColor(skin.rarity))
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.cyan)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .background {
                // 両端へ消える暗い当て板 + 上下の細い金線
                LinearGradient(colors: [.clear, HomeStyle.ink.opacity(0.78), HomeStyle.ink.opacity(0.78), .clear],
                               startPoint: .leading, endPoint: .trailing)
            }
            .overlay(alignment: .top) { fadeLine }
            .overlay(alignment: .bottom) { fadeLine }
            .frame(minHeight: HomeMetrics.minTapSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomePressStyle(scale: 0.97))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("ヒーロー詳細: ", "Hero details: ") + name)
        .accessibilityIdentifier("home_showcase")
    }

    private var fadeLine: some View {
        LinearGradient(colors: [.clear, Theme.gold.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(height: 1)
    }
}
