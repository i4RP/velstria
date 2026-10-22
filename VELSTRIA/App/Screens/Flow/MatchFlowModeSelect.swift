import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI021 モード選択（MLBB 2.2.16 の作り。docs/OUTGAME_GAP.md 2 章・「委員会の調べ」）。
// 左半分はロビーのキービジュアルのまま、右半分に菱形のタイルを斜めに組む: ランキング（いちばん大きい金。段位名の帯・段位章・星）・
// マッチング（大きい青）・乱闘・アーケード・宣伝の枠（GO! マジックチェス）・ライジング（赤い点と札）・AI対戦とカスタム。右上に「ルームIDを入力」。
// 選んだモードはロビーの大ボタンの文字になる（Profile.lastMatchMode）。タイルの位置は MLBB の画面（右半分 960 × 864）から取った。

/// モード選択のタイル。
enum MatchModeCategory: String, CaseIterable, Identifiable {
    case ranked, classic, brawl, arcade, magicChess, rising, vsAI

    var id: String { rawValue }

    /// 日本語クライアントの表記（ランキング・マッチング・乱闘・アーケード・マジックチェス・ライジング・AI対戦とカスタム）。
    var title: String {
        switch self {
        case .ranked: return L("ランキング", "Ranked")
        case .classic: return L("マッチング", "Classic")
        case .brawl: return L("乱闘", "Brawl")
        case .arcade: return L("アーケード", "Arcade")
        case .magicChess: return L("マジックチェス", "Magic Chess")
        case .rising: return L("ライジング", "Rising")
        case .vsAI: return L("AI対戦とカスタム", "VS AI & Custom")
        }
    }

    var symbol: String {
        switch self {
        case .ranked: return "crown.fill"
        case .classic: return "flag.2.crossed.fill"
        case .brawl: return "burst.fill"
        case .arcade: return "gamecontroller.fill"
        case .magicChess: return "square.grid.3x3.fill"
        case .rising: return "chart.line.uptrend.xyaxis"
        case .vsAI: return "cpu"
        }
    }

    /// タイルの識別子（UI テスト）。
    var identifier: String {
        switch self {
        case .ranked: return "flow_mode_ranked"
        case .classic: return "flow_mode_standard"
        case .brawl: return "flow_mode_brawl"
        case .arcade: return "flow_mode_arcade"
        case .magicChess: return "flow_mode_magicChess"
        case .rising: return "flow_mode_rising"
        case .vsAI: return "flow_mode_vsAI"
        }
    }

    /// 菱形の中心と半径（中心から角まで）。下書き ModeTileLayout.canvas の上の値。
    var spot: (center: CGPoint, radius: CGFloat) {
        switch self {
        case .brawl: return (CGPoint(x: 437, y: 205), 135)
        case .magicChess: return (CGPoint(x: 285, y: 345), 135)
        case .arcade: return (CGPoint(x: 135, y: 510), 135)
        case .ranked: return (CGPoint(x: 440, y: 650), 255)
        case .classic: return (CGPoint(x: 700, y: 415), 235)
        case .rising: return (CGPoint(x: 805, y: 655), 80)
        case .vsAI: return (CGPoint(x: 710, y: 745), 80)
        }
    }

    /// AI対戦とカスタムの中身（押すとフローを閉じて各画面へ）。
    var destinations: [MatchModeDestination] {
        switch self {
        case .vsAI:
            return [MatchModeDestination(route: .customSetup, title: L("カスタム", "Custom"), symbol: "slider.horizontal.3", id: "flow_mode_custom"),
                    MatchModeDestination(route: .practiceSetup, title: L("練習場", "Practice"), symbol: "figure.run", id: "flow_mode_practice"),
                    MatchModeDestination(route: .tutorialMenu, title: L("チュートリアル", "Tutorial"), symbol: "graduationcap.fill", id: "flow_mode_tutorial")]
        default:
            return []
        }
    }

    /// ロビーの大ボタンに出す名前（Profile.lastMatchMode の値から）。
    static func playTitle(_ raw: String?) -> String? {
        raw.flatMap(MatchModeCategory.init(rawValue:))?.title
    }
}

/// タイルの中のボタン（id はアクセシビリティの識別子も兼ねる）。
struct MatchModeDestination: Identifiable, Equatable {
    let route: Route
    let title: String
    let symbol: String
    let id: String
}

/// タイルの下書きの大きさ（MLBB の画面の右半分）。
enum ModeTileLayout {
    static let canvas = CGSize(width: 960, height: 864)
    /// 「ルームIDを入力」の位置。
    static let roomID = CGPoint(x: 690, y: 48)
    /// 左のキービジュアルの幅（画面の幅に対する割合）。
    static let artFraction: CGFloat = 0.40

    /// 右の枠に収める倍率。
    static func scale(for area: CGSize) -> CGFloat {
        max(0.1, min(area.width / canvas.width, area.height / canvas.height))
    }

    /// ミシックの星の次の区切り（25 で H、50 で G、100 で I。I から上は無い）。
    static func mythicNext(_ stars: Int) -> Int? {
        [25, 50, 100].first { stars < $0 }
    }
}

/// 菱形（正方形を 45 度回した形）。
struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

struct MatchModeStep: View {
    @Bindable var model: MatchFlowModel
    @Environment(AppModel.self) private var app
    @State private var showsVSAI = false

    var body: some View {
        GeometryReader { geo in
            let artWidth = geo.size.width * ModeTileLayout.artFraction
            let area = CGSize(width: geo.size.width - artWidth, height: geo.size.height)
            let scale = ModeTileLayout.scale(for: area)
            ZStack(alignment: .topLeading) {
                ModeSelectArt()
                    .frame(width: artWidth + 80, height: geo.size.height)
                    .allowsHitTesting(false)
                tileCanvas
                    .frame(width: ModeTileLayout.canvas.width, height: ModeTileLayout.canvas.height)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: ModeTileLayout.canvas.width * scale, height: ModeTileLayout.canvas.height * scale, alignment: .topLeading)
                    .offset(x: artWidth + max(0, area.width - ModeTileLayout.canvas.width * scale) / 2,
                            y: max(0, area.height - ModeTileLayout.canvas.height * scale) / 2)
                backButton
                    .padding(.leading, 14)
                    .padding(.top, 8)
                difficultyRow
                    .frame(width: max(200, artWidth - 24), alignment: .leading)
                    .padding(.leading, 14)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 10)
            }
        }
    }

    // MARK: タイル

    private var tileCanvas: some View {
        ZStack(alignment: .topLeading) {
            ForEach(MatchModeCategory.allCases) { c in
                tile(c)
                    .frame(width: c.spot.radius * 2, height: c.spot.radius * 2)
                    .position(c.spot.center)
            }
            label(MatchModeCategory.rising.title, at: CGPoint(x: 868, y: 742), size: 30)
            label(MatchModeCategory.vsAI.title, at: CGPoint(x: 710, y: 846), size: 30)
            roomIDButton
                .position(ModeTileLayout.roomID)
        }
    }

    private func tile(_ c: MatchModeCategory) -> some View {
        Button { start(c) } label: {
            ZStack {
                DiamondShape().fill(fill(c))
                DiamondShape().stroke(stroke(c), lineWidth: c == .ranked || c == .classic ? 5 : 3)
                DiamondShape().stroke(Color.white.opacity(0.18), lineWidth: 1.5).padding(10)
                content(c)
            }
            .shadow(color: (c == .ranked ? Theme.gold : Celestial.ice).opacity(c == .ranked ? 0.5 : 0.25), radius: c == .ranked ? 18 : 8)
            .contentShape(DiamondShape())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if c == .rising && !RisingService.isComplete(app.profile.rising) {
                Circle().fill(Color.red).frame(width: 22, height: 22)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .offset(x: -36, y: 36)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(c.identifier)
        .popover(isPresented: c == .vsAI ? $showsVSAI : .constant(false)) {
            vsAIMenu.presentationCompactAdaptation(.popover)
        }
    }

    private func fill(_ c: MatchModeCategory) -> LinearGradient {
        switch c {
        case .ranked:
            return LinearGradient(colors: [Color(red: 0.98, green: 0.84, blue: 0.47), Color(red: 0.62, green: 0.43, blue: 0.13),
                                           Color(red: 0.33, green: 0.21, blue: 0.05)], startPoint: .topTrailing, endPoint: .bottomLeading)
        case .classic:
            return LinearGradient(colors: [Color(red: 0.42, green: 0.66, blue: 0.98), Color(red: 0.12, green: 0.30, blue: 0.62),
                                           Color(red: 0.04, green: 0.12, blue: 0.30)], startPoint: .topTrailing, endPoint: .bottomLeading)
        case .rising:
            return LinearGradient(colors: [Color(red: 0.78, green: 0.20, blue: 0.40), Celestial.inkRaised], startPoint: .top, endPoint: .bottom)
        case .magicChess:
            return LinearGradient(colors: [Color(red: 0.42, green: 0.30, blue: 0.70), Celestial.inkRaised], startPoint: .top, endPoint: .bottom)
        default:
            return LinearGradient(colors: [Color(red: 0.20, green: 0.32, blue: 0.52), Celestial.inkRaised], startPoint: .top, endPoint: .bottom)
        }
    }

    private func stroke(_ c: MatchModeCategory) -> Color {
        switch c {
        case .ranked: return HomeStyle.goldLight
        case .classic: return Color(red: 0.70, green: 0.88, blue: 1)
        default: return Celestial.ice.opacity(0.75)
        }
    }

    @ViewBuilder
    private func content(_ c: MatchModeCategory) -> some View {
        switch c {
        case .ranked: rankedContent
        case .classic:
            VStack(spacing: 8) {
                Image(systemName: c.symbol).font(.system(size: 78, weight: .light)).foregroundStyle(.white.opacity(0.9))
                    .shadow(color: Celestial.ice, radius: 14)
                Text(c.title).font(Celestial.title(44)).foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 4)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            // 菱形の幅の広い中ほどに収める（上下の角に寄ると文字がはみ出す）
            .frame(width: 280)
            .offset(y: 14)
        case .magicChess:
            VStack(spacing: 2) {
                Text("GO!").font(.system(size: 54, weight: .black, design: .rounded)).italic()
                    .foregroundStyle(LinearGradient(colors: [HomeStyle.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.6), radius: 3)
                Text(c.title).font(Celestial.heading(20)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(width: 150)
            .offset(y: 4)
        case .rising, .vsAI:
            Image(systemName: c.symbol).font(.system(size: 52, weight: .regular)).foregroundStyle(.white)
                .shadow(color: Celestial.ice.opacity(0.8), radius: 6)
        default:
            VStack(spacing: 6) {
                Image(systemName: c.symbol).font(.system(size: 52, weight: .light)).foregroundStyle(.white.opacity(0.9))
                    .shadow(color: Celestial.ice.opacity(0.8), radius: 8)
                Text(c.title).font(Celestial.title(30)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                    .shadow(color: .black.opacity(0.6), radius: 3)
            }
            .frame(width: 160)
            .offset(y: 8)
        }
    }

    /// ランキング: 題名・段位名の帯・大きな段位章・星（ミシックは紫の星と「36/50」）。
    private var rankedContent: some View {
        let rank = app.profile.rank
        return VStack(spacing: 8) {
            Text(MatchModeCategory.ranked.title)
                .font(Celestial.title(50))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.55), radius: 4)
            Text(RankService.shortName(rank) + (rank.tier == .mythic ? "" : " " + RankService.roman(rank.division)))
                .font(Celestial.heading(34))
                .foregroundStyle(.white)
                .padding(.horizontal, 36)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.32)))
            RankCrest(tier: rank.tier, size: 150)
            if rank.tier == .mythic {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill").foregroundStyle(Color(red: 0.86, green: 0.55, blue: 1))
                    Text(ModeTileLayout.mythicNext(rank.stars).map { "\(rank.stars)/\($0)" } ?? "\(rank.stars)")
                        .foregroundStyle(.white)
                }
                .font(.system(size: 36, weight: .bold, design: .rounded))
            } else {
                RankStarsView(stars: rank.stars, maxStars: RankService.maxStars(rank.tier), size: 28)
            }
        }
        // 菱形の幅の広い中ほどに収める（題名が上の角へ寄ると隣のタイルへはみ出す）
        .frame(width: 330)
        .offset(y: 24)
    }

    private func label(_ text: String, at point: CGPoint, size: CGFloat) -> some View {
        Text(text)
            .font(Celestial.heading(size))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.7), radius: 3)
            .fixedSize()
            .position(point)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 右上: 「ルームIDを入力」（オンラインの部屋コードで入る）。
    private var roomIDButton: some View {
        Button {
            openMode(.onlineLobby)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "house.circle.fill").font(.system(size: 40))
                Text(L("ルームIDを入力", "Enter Room ID")).font(Celestial.heading(30))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.28)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("flow_mode_roomID")
    }

    /// AI対戦とカスタムの中身（カスタム・練習場・チュートリアル）。
    private var vsAIMenu: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(MatchModeCategory.vsAI.title)
                .font(Celestial.heading(13))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
            ForEach(MatchModeCategory.vsAI.destinations) { d in
                Button {
                    showsVSAI = false
                    openMode(d.route)
                } label: {
                    Label(d.title, systemImage: d.symbol)
                        .font(Theme.heading(14))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 200, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(d.id)
            }
        }
        .padding(.bottom, 6)
        .presentationBackground(Celestial.ink)
    }

    // MARK: 左

    private var backButton: some View {
        Button(action: close) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(HomeStyle.goldLight)
                .frame(width: 48, height: 44)
                .background(HomeChamfer(cut: 9).fill(Celestial.ink.opacity(0.7)))
                .overlay(HomeChamfer(cut: 9).stroke(Celestial.ice.opacity(0.5), lineWidth: 0.7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("戻る", "Back"))
        .accessibilityIdentifier("flow_close")
    }

    /// 敵 AI の強さ（マッチング・乱闘。ランキングは自分のランクで決まる）。MLBB には無い Velstria の設定なので左下に小さく。
    private var difficultyRow: some View {
        HStack(spacing: 6) {
            Text(L("AI の強さ", "AI"))
                .font(Celestial.heading(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize()
            ForEach(Difficulty.allCases, id: \.self) { d in
                let selected = model.difficulty == d
                Button {
                    FlowFX.tap(app)
                    withAnimation(.spring(duration: 0.25)) { model.difficulty = d }
                } label: {
                    Text(FlowText.difficulty(d))
                        .font(Celestial.heading(12))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selected ? Color(red: 0.16, green: 0.10, blue: 0.03) : Theme.textPrimary)
                        .frame(maxWidth: 76, minHeight: 36)
                        .background(HomeChamfer(cut: 6).fill(selected ? AnyShapeStyle(LinearGradient(colors: [HomeStyle.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom))
                                                                      : AnyShapeStyle(Celestial.ink.opacity(0.8))))
                        .overlay(HomeChamfer(cut: 6).stroke(selected ? HomeStyle.goldLight : Celestial.ice.opacity(0.4), lineWidth: selected ? 1 : 0.6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(FlowText.difficulty(d))
                .accessibilityHint(Self.difficultyDetail(d))
                .accessibilityIdentifier("flow_difficulty_\(d.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(6)
        .background(HomeChamfer(cut: 8).fill(Celestial.ink.opacity(0.7)))
    }

    /// 難易度ごとの AI の特徴（DESIGN §10）。
    static func difficultyDetail(_ d: Difficulty) -> String {
        switch d {
        case .easy: return L("反応 0.6 秒・命中率 控えめ。はじめての方に。", "0.6s reactions, loose aim. Great for beginners.")
        case .normal: return L("反応 0.35 秒・標準的な立ち回り。", "0.35s reactions, standard play.")
        case .hard: return L("反応 0.15 秒・高い精度で集団行動をとる。", "0.15s reactions, precise aim and group tactics.")
        }
    }

    // MARK: 操作

    private func close() {
        FlowFX.back(app)
        app.router.isMatchFlowPresented = false
    }

    private func start(_ c: MatchModeCategory) {
        switch c {
        case .ranked: remember(c); FlowFX.confirm(app); model.chooseMode(.ranked)
        case .classic: remember(c); FlowFX.confirm(app); model.chooseMode(.standard)
        case .brawl: remember(c); FlowFX.confirm(app); model.chooseMode(.brawl)
        case .magicChess: remember(c); openMode(.magicChess)
        case .rising: remember(c); openMode(.rising)
        // Velstria には期間限定の変則モードが無いので、期間限定の中身があるイベントの画面を開く（docs/OUTGAME_GAP.md 2 章）
        case .arcade: openMode(.events)
        case .vsAI: FlowFX.tap(app); showsVSAI = true
        }
    }

    /// 選んだモードをロビーの大ボタンの文字にする（MLBB と同じ）。
    private func remember(_ c: MatchModeCategory) {
        guard app.profile.lastMatchMode != c.rawValue else { return }
        var p = app.profile
        p.lastMatchMode = c.rawValue
        app.profile = p
    }

    /// フローを閉じて各モードの画面へ。
    private func openMode(_ route: Route) {
        FlowFX.tap(app)
        app.router.isMatchFlowPresented = false
        app.router.push(route)
    }
}

/// 左半分: ロビーのキービジュアル（MLBB のモード選択も左はロビーの絵のまま）。右へ向かって背景に溶かす。
private struct ModeSelectArt: View {
    var body: some View {
        GeometryReader { geo in
            let kv = HomeLobbySlot.keyVisual
            let scale = geo.size.height / kv.height
            Image("CelestialLobby").resizable()
                .frame(width: HomeLayout.board.width * scale, height: HomeLayout.board.height * scale)
                .offset(x: -(kv.midX * scale - geo.size.width * 0.45), y: -kv.minY * scale)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .clipped()
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.72),
                                     .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        .accessibilityHidden(true)
    }
}
