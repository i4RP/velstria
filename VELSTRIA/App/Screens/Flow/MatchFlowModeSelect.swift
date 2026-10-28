import SwiftUI
import VelstriaCore

// 対戦モードはパーティと同じ青いカードで、固定ワールド枠の中に表示する。
// 選んだモードはロビーの大ボタンの文字になる（Profile.lastMatchMode）。

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
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                backButton
                Text(L("対戦モード", "Match Mode"))
                    .font(Theme.heading(18)).foregroundStyle(Theme.gold)
                Spacer(minLength: 0)
                Button { openMode(.onlineLobby) } label: {
                    Label(L("パーティ", "Party"), systemImage: "person.2.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("flow_mode_roomID")
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 10)], spacing: 12) {
                    ForEach(MatchModeCategory.allCases) { category in
                        modeCard(category)
                    }
                }
                .padding(.top, 7)
                .padding(.bottom, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            difficultyRow
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .overlay {
            if showsVSAI {
                ZStack {
                    Theme.panel.opacity(0.6).onTapGesture { showsVSAI = false }
                    VStack(spacing: 8) {
                        HStack {
                            Text(MatchModeCategory.vsAI.title).font(Theme.heading(16)).foregroundStyle(Theme.gold)
                            Spacer()
                            Button { showsVSAI = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                                .buttonStyle(.plain)
                        }
                        ForEach(MatchModeCategory.vsAI.destinations) { destination in
                            Button {
                                showsVSAI = false
                                openMode(destination.route)
                            } label: {
                                Label(destination.title, systemImage: destination.symbol).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier(destination.id)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 360)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.cyan.opacity(0.6)))
                    .padding(16)
                }
            }
        }
    }

    private func modeCard(_ category: MatchModeCategory) -> some View {
        Button { start(category) } label: {
            VStack(spacing: 10) {
                Image(systemName: category.symbol)
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(category == .ranked ? Theme.gold : Theme.cyan)
                    .frame(height: 34)
                Text(category.title)
                    .font(Theme.heading(15))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if category == .ranked {
                    Text(RankService.shortName(app.profile.rank))
                        .font(Theme.body(10)).foregroundStyle(Theme.gold)
                } else {
                    Text(category == .classic ? L("5 対 5", "5 vs 5") : L("選択する", "Select"))
                        .font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 102)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.12, green: 0.34, blue: 0.63).opacity(0.58)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(category == .ranked ? Theme.gold.opacity(0.8) : Theme.cyan.opacity(0.5)))
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.cyan.opacity(0.8)).frame(height: 2)
                DiamondShape().fill(Theme.cyan).frame(width: 11, height: 15).offset(y: -6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(category.identifier)
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
