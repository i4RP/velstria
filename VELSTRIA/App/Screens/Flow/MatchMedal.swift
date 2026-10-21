import SwiftUI
import VelstriaCore

// 担当: ui-flow。試合の勲章（MLBB の試合後の勲章）。評価点（0〜16。RankService.matchRating）・勝敗・チーム内で評価点が最高か から決める。
// MLBB 2.2.16 の条件（docs/OUTGAME_GAP.md 6-2。委員会 2026-10-21: 日本語 UI の配信 YouTube kp3LaYXxMfI・esports.gg の勲章の解説）:
// - 銅 3.0〜3.4 / 銀 3.5〜7.0 / 金 7.1〜10.0 / ウルトラ勲章 10.1 以上（英語版の Supreme。紫に光る）
// - MVP = 勝ったチームで評価点が最高（評価点を問わない。10.1 以上ならウルトラ MVP）
// - 敗北MVP = 負けたチームで評価点が最高
// - 未確認: 3.0 未満（勲章なしとする）
// 評価点は 0.1 刻みで表示するので、表示と同じ桁（10 倍の整数）で比べる。絵は画像を同梱せずベクターで描く（MatchMedalView）。

/// 試合のメダル。
enum MatchMedal: String, CaseIterable, Hashable, Sendable {
    case bronze, silver, gold, supreme, mvp, supremeMVP, mvpLoss

    /// しきい値（評価点 × 10）。
    enum Threshold {
        static let bronze = 30
        static let silver = 35
        static let gold = 71
        static let supreme = 101
    }

    /// 評価点・勝敗・チーム内で評価点が最高か（同点は MVP スコアの並びで先の 1 人）からメダルを決める。3.0 未満は nil。
    static func award(rating: Double, won: Bool, isTeamBest: Bool) -> MatchMedal? {
        guard rating.isFinite else { return nil }
        let tenths = Int((min(max(rating, 0), 100) * 10).rounded())
        if isTeamBest { return won ? (tenths >= Threshold.supreme ? .supremeMVP : .mvp) : .mvpLoss }
        if tenths >= Threshold.supreme { return .supreme }
        if tenths >= Threshold.gold { return .gold }
        if tenths >= Threshold.silver { return .silver }
        if tenths >= Threshold.bronze { return .bronze }
        return nil
    }

    /// メダルを出すモードか（試合ではない練習場・チュートリアルと、オートバトラーには出さない）。
    static func isAwarded(in mode: MatchMode) -> Bool {
        switch mode {
        case .practice, .tutorial, .magicChess: return false
        default: return true
        }
    }

    /// 試合の全員の評価点とメダル（entityID ごと）。
    /// チーム内の最高 = MVP スコアの並び（同点は ID の小さい方。ScoreSystem と同じ）の先頭。評価点は MVP スコアが大きいほど高い。
    /// 勝敗が付かなかった試合（時間切れ・中断）は MVP も敗北 MVP も出さない。
    static func results(in summary: MatchSummary) -> [EntityID: MatchMedalResult] {
        var out: [EntityID: MatchMedalResult] = [:]
        guard isAwarded(in: summary.mode) else {
            for p in summary.players { out[p.entityID] = MatchMedalResult() }
            return out
        }
        let teamBest = Set(Team.allCases.compactMap { summary.players(of: $0).first?.entityID })
        for p in summary.players {
            let rating = RankService.matchRating(p, in: summary)
            let won = summary.winner != nil && summary.winner == p.team
            let best = summary.winner != nil && teamBest.contains(p.entityID)
            out[p.entityID] = MatchMedalResult(rating: rating, medal: award(rating: rating, won: won, isTeamBest: best))
        }
        return out
    }

    /// 1 人の評価点とメダル。
    static func result(for player: PlayerSummary, in summary: MatchSummary) -> MatchMedalResult {
        results(in: summary)[player.entityID] ?? MatchMedalResult()
    }

    // MARK: 表示

    /// 名前（日本語版の呼び名。リザルトの「ウルトラ勲章ボーナス」「敗北チームのMVP」と同じ）。
    var name: String {
        switch self {
        case .bronze: return L("銅勲章", "Bronze Medal")
        case .silver: return L("銀勲章", "Silver Medal")
        case .gold: return L("金勲章", "Gold Medal")
        case .supreme: return L("ウルトラ勲章", "Supreme Medal")
        case .mvp: return "MVP"
        case .supremeMVP: return L("ウルトラMVP", "Supreme MVP")
        case .mvpLoss: return L("敗北MVP", "MVP Loss")
        }
    }

    /// 取る条件（リザルトの凡例）。
    var condition: String {
        let bronze = Self.text(Threshold.bronze), silver = Self.text(Threshold.silver), gold = Self.text(Threshold.gold)
        let supreme = Self.text(Threshold.supreme)
        let bronzeTop = Self.text(Threshold.silver - 1), silverTop = Self.text(Threshold.gold - 1), goldTop = Self.text(Threshold.supreme - 1)
        switch self {
        case .bronze: return L("評価 \(bronze)〜\(bronzeTop)", "Rating \(bronze)–\(bronzeTop)")
        case .silver: return L("評価 \(silver)〜\(silverTop)", "Rating \(silver)–\(silverTop)")
        case .gold: return L("評価 \(gold)〜\(goldTop)", "Rating \(gold)–\(goldTop)")
        case .supreme: return L("評価 \(supreme) 以上", "Rating \(supreme)+")
        case .mvp: return L("勝利チームで評価が最高", "Top rating on the winning team")
        case .supremeMVP: return L("勝利チームで評価が最高かつ \(supreme) 以上", "Top rating on the winning team, \(supreme)+")
        case .mvpLoss: return L("敗北チームで評価が最高", "Top rating on the losing team")
        }
    }

    /// MVP の 3 種（王冠を描く）。
    var isMVP: Bool { self == .mvp || self == .supremeMVP || self == .mvpLoss }
    /// 勝ったチームの MVP。
    var isWinnerMVP: Bool { self == .mvp || self == .supremeMVP }

    /// 名前の文字色。
    var tint: Color {
        switch self {
        case .bronze: return Color(red: 0.93, green: 0.64, blue: 0.42)
        case .silver: return Color(red: 0.84, green: 0.89, blue: 0.97)
        case .gold, .mvp: return Theme.gold
        case .supreme, .supremeMVP: return Color(red: 0.80, green: 0.64, blue: 1.0)
        case .mvpLoss: return Color(red: 0.64, green: 0.80, blue: 1.0)
        }
    }

    /// しきい値（評価点 × 10）を "6.6" の形に。
    static func text(_ tenths: Int) -> String { String(format: "%.1f", Double(tenths) / 10) }
}

/// 1 人の評価点（0〜16。メダルを出さないモードは nil）とメダル（3.0 未満は nil）。
struct MatchMedalResult: Equatable, Sendable {
    var rating: Double?
    var medal: MatchMedal?

    /// 表示用の評価点（"12.3"。評価しないモードは "—"）。
    var ratingText: String { rating.map { String(format: "%.1f", $0) } ?? "—" }
}

// MARK: - 絵

/// メダル（ベクター）。銅・銀・金 = 四芒星の円盤と月桂樹、シュプリーム = 紫に光る円盤、MVP = 王冠と光の筋（勝ちは金・
/// シュプリーム MVP は紫・敗北 MVP は銀青）。nil はメダルなし（点線の輪）。リザルトの各画面で共通に使う。
struct MatchMedalView: View {
    let medal: MatchMedal?
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            if let medal {
                MedalArt(medal: medal, size: size)
            } else {
                Circle()
                    .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: max(0.6, size * 0.04), dash: [max(1.5, size * 0.08)]))
                    .padding(size * 0.2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(medal?.name ?? L("勲章なし", "No medal"))
    }
}

/// メダルの配色。
private struct MedalPalette {
    var light: Color
    var mid: Color
    var deep: Color
    var rim: Color
    var glow: Color
    var leafLight: Color
    var leafDeep: Color
    /// リボンの文字。
    var ink: Color

    init(_ medal: MatchMedal) {
        let goldLeafLight = Color(red: 1.0, green: 0.88, blue: 0.55)
        let goldLeafDeep = Color(red: 0.70, green: 0.45, blue: 0.12)
        let silverLeafLight = Color(red: 0.90, green: 0.94, blue: 0.99)
        let silverLeafDeep = Color(red: 0.48, green: 0.54, blue: 0.64)
        switch medal {
        case .bronze:
            light = Color(red: 0.98, green: 0.80, blue: 0.62)
            mid = Color(red: 0.82, green: 0.52, blue: 0.30)
            deep = Color(red: 0.46, green: 0.24, blue: 0.11)
            rim = Color(red: 1.0, green: 0.86, blue: 0.70)
            glow = Color(red: 0.82, green: 0.52, blue: 0.30)
            leafLight = Color(red: 0.92, green: 0.66, blue: 0.44)
            leafDeep = Color(red: 0.52, green: 0.30, blue: 0.14)
            ink = Color(red: 0.30, green: 0.14, blue: 0.04)
        case .silver:
            light = Color(red: 0.98, green: 0.99, blue: 1.0)
            mid = Color(red: 0.76, green: 0.82, blue: 0.90)
            deep = Color(red: 0.38, green: 0.44, blue: 0.55)
            rim = .white
            glow = Color(red: 0.80, green: 0.88, blue: 1.0)
            leafLight = silverLeafLight
            leafDeep = silverLeafDeep
            ink = Color(red: 0.16, green: 0.20, blue: 0.28)
        case .gold, .mvp:
            light = HomeStyle.goldLight
            mid = Theme.gold
            deep = HomeStyle.goldDeep
            rim = HomeStyle.goldLight
            glow = Theme.gold
            leafLight = goldLeafLight
            leafDeep = goldLeafDeep
            ink = Color(red: 0.28, green: 0.16, blue: 0.02)
        case .supreme, .supremeMVP:
            let crowned = medal == .supremeMVP
            light = Color(red: 0.94, green: 0.86, blue: 1.0)
            mid = HomeStyle.violet
            deep = Color(red: 0.28, green: 0.12, blue: 0.60)
            rim = crowned ? HomeStyle.goldLight : Color(red: 0.96, green: 0.90, blue: 1.0)
            glow = HomeStyle.violet
            leafLight = crowned ? goldLeafLight : Color(red: 0.86, green: 0.74, blue: 1.0)
            leafDeep = crowned ? goldLeafDeep : Color(red: 0.42, green: 0.22, blue: 0.78)
            ink = Color(red: 0.18, green: 0.06, blue: 0.36)
        case .mvpLoss:
            light = Color(red: 0.88, green: 0.94, blue: 1.0)
            mid = Color(red: 0.52, green: 0.68, blue: 0.92)
            deep = Color(red: 0.18, green: 0.28, blue: 0.56)
            rim = Color(red: 0.90, green: 0.95, blue: 1.0)
            glow = Color(red: 0.52, green: 0.68, blue: 0.92)
            leafLight = silverLeafLight
            leafDeep = silverLeafDeep
            ink = Color(red: 0.08, green: 0.14, blue: 0.32)
        }
    }
}

private struct MedalArt: View {
    let medal: MatchMedal
    let size: CGFloat

    private var hasRays: Bool { medal.isMVP || medal == .supreme }
    private var glows: Bool { medal == .supreme || medal == .supremeMVP }

    var body: some View {
        let s = MedalPalette(medal)
        let disc = size * 0.70
        let line = max(0.6, size * 0.035)
        ZStack {
            if hasRays {
                MedalRays()
                    .fill(RadialGradient(colors: [s.glow.opacity(0.9), s.glow.opacity(0)], center: .center,
                                         startRadius: size * 0.18, endRadius: size * 0.5))
            }
            MedalLaurel()
                .fill(LinearGradient(colors: [s.leafLight, s.leafDeep], startPoint: .top, endPoint: .bottom))
            Circle()
                .fill(LinearGradient(colors: [s.light, s.mid, s.deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: disc, height: disc)
            Circle()
                .strokeBorder(LinearGradient(colors: [s.rim, s.deep], startPoint: .top, endPoint: .bottom), lineWidth: line)
                .frame(width: disc, height: disc)
            Circle()
                .stroke(Color.white.opacity(0.45), lineWidth: max(0.4, size * 0.018))
                .frame(width: disc * 0.78, height: disc * 0.78)
            emblem(s)
            Circle()
                .trim(from: 0.58, to: 0.78)
                .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: max(0.5, size * 0.025), lineCap: .round))
                .frame(width: disc * 0.88, height: disc * 0.88)
            if medal.isMVP && size >= 56 {
                ribbon(s)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: s.glow.opacity(glows ? 0.85 : 0.35), radius: size * (glows ? 0.14 : 0.06))
    }

    @ViewBuilder
    private func emblem(_ s: MedalPalette) -> some View {
        if medal.isMVP {
            MedalCrown()
                .fill(LinearGradient(colors: [.white, s.rim], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.34, height: size * 0.25)
                .offset(y: -size * 0.02)
                .shadow(color: s.deep.opacity(0.6), radius: size * 0.02)
        } else {
            CelestialSparkle()
                .fill(LinearGradient(colors: [.white, s.rim], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.30, height: size * 0.34)
                .shadow(color: .white.opacity(0.5), radius: size * 0.03)
        }
    }

    /// 大きな MVP のメダルの下に掛ける「MVP」の帯。
    private func ribbon(_ s: MedalPalette) -> some View {
        let shape = HomeChamfer(cut: size * 0.04, corners: .all)
        return Text("MVP")
            .font(.system(size: size * 0.13, weight: .black, design: .serif))
            .foregroundStyle(s.ink)
            .padding(.horizontal, size * 0.08)
            .padding(.vertical, size * 0.012)
            .background(shape.fill(LinearGradient(colors: [s.light, s.rim], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.stroke(Color.white.opacity(0.8), lineWidth: max(0.5, size * 0.01)))
            .offset(y: size * 0.36)
    }
}

/// 月桂樹（円盤の下半分を左右から囲む葉）。
private struct MedalLaurel: Shape {
    var leavesPerSide = 6

    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let radius = min(r.width, r.height) / 2
        let orbit = radius * 0.80
        let length = radius * 0.30
        let width = radius * 0.13
        let leaf = Path(ellipseIn: CGRect(x: -length / 2, y: -width / 2, width: length, height: width))
        var p = Path()
        for side in [-1.0, 1.0] {
            for i in 0..<leavesPerSide {
                let t = Double(i) / Double(max(1, leavesPerSide - 1))
                // 左の枝は下（100°）から左上（215°）へ。右は左右反転（画面の座標は y が下向き）
                let degrees = 100 + 115 * t
                let angle = (side < 0 ? degrees : 180 - degrees) * Double.pi / 180
                let point = CGPoint(x: c.x + CGFloat(cos(angle)) * orbit, y: c.y + CGFloat(sin(angle)) * orbit)
                // 枝の進む向き（円の接線）に沿わせ、少し外へ開く
                let heading = angle + (side < 0 ? Double.pi / 2 : -Double.pi / 2) - side * 0.45
                let transform = CGAffineTransform(translationX: point.x, y: point.y).rotated(by: CGFloat(heading))
                p.addPath(leaf, transform: transform)
            }
        }
        return p
    }
}

/// 王冠（MVP）。
private struct MedalCrown: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        var p = Path()
        p.move(to: pt(0.12, 0.80))
        p.addLine(to: pt(0.02, 0.22))
        p.addLine(to: pt(0.30, 0.50))
        p.addLine(to: pt(0.50, 0.04))
        p.addLine(to: pt(0.70, 0.50))
        p.addLine(to: pt(0.98, 0.22))
        p.addLine(to: pt(0.88, 0.80))
        p.closeSubpath()
        p.addRect(CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.86, width: r.width * 0.76, height: r.height * 0.14))
        return p
    }
}

/// 光の筋（MVP・シュプリーム）。
private struct MedalRays: Shape {
    var count = 16

    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let outer = min(r.width, r.height) * 0.5
        var p = Path()
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * Double.pi
            let w = 0.07
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + outer * CGFloat(cos(a - w)), y: c.y + outer * CGFloat(sin(a - w))))
            p.addLine(to: CGPoint(x: c.x + outer * CGFloat(cos(a + w)), y: c.y + outer * CGFloat(sin(a + w))))
            p.closeSubpath()
        }
        return p
    }
}
