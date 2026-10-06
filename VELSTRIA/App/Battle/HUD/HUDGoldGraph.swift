import SwiftUI
import VelstriaCore

// 担当: battle-hud（観戦）。ゴールド・経験値の差の推移（controller.displayTimeline.samples、10 秒毎）。
// 上半分 = ブルー有利、下半分 = レッド有利。ゴールド差は塗り、経験値差は破線。現在位置に縦線、まだ見ていない先は暗く。
// 巻き戻しても年表は分かっている所まで残る（リプレイに年表があれば試合の最後まで）。

struct HUDGoldGraph: View {
    let model: HUDModel

    var body: some View {
        let g = model.spectator.graph
        let tick = model.spectator.transport.displayTick
        let cb = model.settings.colorblindMode
        let blue = Theme.teamColor(.blue, colorblind: cb)
        let red = Theme.teamColor(.red, colorblind: cb)
        let current = HUDGoldGraphMath.value(at: tick, in: g.points)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                legend(L("ゴールド差", "Gold"), value: current?.gold, dashed: false, blue: blue, red: red)
                legend(L("経験値差", "XP"), value: current?.xp, dashed: true, blue: blue, red: red)
                Spacer(minLength: 0)
            }
            if g.points.count < 2 {
                Text(L("試合が進むと表示します", "Shown as the match progresses"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(HUDStyle.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HUDGoldGraphCanvas(graph: g, cursorTick: tick, blue: blue, red: red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Text("00:00")
                    Spacer()
                    Text(HUDStyle.clock(Double(g.endTick) * Balance.dt))
                }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(HUDStyle.mutedText)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("ゴールド・経験値の差の推移", "Gold and XP difference over time"))
        .accessibilityValue(accessibilityValue(current))
        .accessibilityIdentifier("spectate_gold_graph")
    }

    private func accessibilityValue(_ p: HUDGraphPoint?) -> String {
        guard let p else { return L("データなし", "No data") }
        func lead(_ v: Double) -> String {
            let n = Int(abs(v).rounded())
            if n == 0 { return L("互角", "even") }
            return L("\(HUDText.teamName(v > 0 ? .blue : .red)) が \(n) 有利", "\(HUDText.teamName(v > 0 ? .blue : .red)) ahead by \(n)")
        }
        return L("ゴールド \(lead(p.gold))、経験値 \(lead(p.xp))", "Gold \(lead(p.gold)), XP \(lead(p.xp))")
    }

    private func legend(_ title: String, value: Double?, dashed: Bool, blue: Color, red: Color) -> some View {
        let v = value ?? 0
        let lead: Team? = v > 0.5 ? .blue : (v < -0.5 ? .red : nil)
        let color = lead == .blue ? blue : (lead == .red ? red : Color.white.opacity(0.7))
        return HStack(spacing: 4) {
            Capsule()
                .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 2] : []))
                .frame(width: 14, height: 2)
            Text(title).foregroundStyle(HUDStyle.mutedText)
            if let lead {
                Image(systemName: lead == .blue ? "circle.fill" : "diamond.fill")
                    .font(.system(size: 6, weight: .black))
                    .foregroundStyle(color)
            }
            Text(value == nil ? "—" : (abs(v) < 0.5 ? "±0" : "+" + HUDStyle.thousands(abs(v))))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .font(.system(size: 10, weight: .heavy, design: .rounded))
    }
}

/// グラフの計算（純粋関数）。
enum HUDGoldGraphMath {
    /// 縦軸の範囲（0 を中心に上下対称。最小 1000）。
    static func range(_ points: [HUDGraphPoint]) -> Double {
        let m = points.reduce(0) { max($0, abs($1.gold), abs($1.xp)) }
        return max(1000, (m * 1.15 / 500).rounded(.up) * 500)
    }

    /// tick 以前で最も新しい点。
    static func value(at tick: Int, in points: [HUDGraphPoint]) -> HUDGraphPoint? {
        points.last { $0.tick <= tick } ?? points.first
    }

    static func point(_ p: HUDGraphPoint, value: Double, endTick: Int, range: Double, size: CGSize) -> CGPoint {
        let x = size.width * CGFloat(min(1, max(0, Double(p.tick) / Double(max(1, endTick)))))
        let y = size.height / 2 - size.height / 2 * CGFloat(min(1, max(-1, value / max(1, range))))
        return CGPoint(x: x, y: y)
    }
}

struct HUDGoldGraphCanvas: View {
    let graph: HUDGoldGraphSnapshot
    let cursorTick: Int
    let blue: Color
    let red: Color

    var body: some View {
        Canvas { ctx, size in
            let pts = graph.points
            let range = HUDGoldGraphMath.range(pts)
            let mid = size.height / 2
            // 背景: 上 = ブルー有利、下 = レッド有利
            ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: mid)), with: .color(blue.opacity(0.06)))
            ctx.fill(Path(CGRect(x: 0, y: mid, width: size.width, height: mid)), with: .color(red.opacity(0.06)))
            for frac in [-0.5, 0.5] {
                var grid = Path()
                let y = mid - mid * CGFloat(frac)
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 0.5)
            }
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: mid))
            zero.addLine(to: CGPoint(x: size.width, y: mid))
            ctx.stroke(zero, with: .color(.white.opacity(0.35)), lineWidth: 1)

            // ゴールド差（塗り。上下で色を分ける）
            var line = Path()
            var area = Path()
            for (k, p) in pts.enumerated() {
                let q = HUDGoldGraphMath.point(p, value: p.gold, endTick: graph.endTick, range: range, size: size)
                if k == 0 {
                    line.move(to: q)
                    area.move(to: CGPoint(x: q.x, y: mid))
                }
                line.addLine(to: q)
                area.addLine(to: q)
            }
            if let last = pts.last {
                let q = HUDGoldGraphMath.point(last, value: last.gold, endTick: graph.endTick, range: range, size: size)
                area.addLine(to: CGPoint(x: q.x, y: mid))
                area.closeSubpath()
            }
            var top = ctx
            top.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: mid)))
            top.fill(area, with: .color(blue.opacity(0.45)))
            var bottom = ctx
            bottom.clip(to: Path(CGRect(x: 0, y: mid, width: size.width, height: mid)))
            bottom.fill(area, with: .color(red.opacity(0.45)))
            ctx.stroke(line, with: .color(.white.opacity(0.9)), lineWidth: 1.5)

            // 経験値差（破線）
            var xp = Path()
            for (k, p) in pts.enumerated() {
                let q = HUDGoldGraphMath.point(p, value: p.xp, endTick: graph.endTick, range: range, size: size)
                if k == 0 { xp.move(to: q) } else { xp.addLine(to: q) }
            }
            ctx.stroke(xp, with: .color(HUDStyle.violet.opacity(0.9)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))

            // 現在位置（その先 = まだ見ていない所は暗く）
            let cx = size.width * CGFloat(min(1, max(0, Double(cursorTick) / Double(max(1, graph.endTick)))))
            if cx < size.width {
                ctx.fill(Path(CGRect(x: cx, y: 0, width: size.width - cx, height: size.height)), with: .color(.black.opacity(0.35)))
            }
            var cursor = Path()
            cursor.move(to: CGPoint(x: cx, y: 0))
            cursor.addLine(to: CGPoint(x: cx, y: size.height))
            ctx.stroke(cursor, with: .color(Theme.gold), lineWidth: 1.5)

            // 目盛りの値
            var label = ctx.resolve(Text("+" + HUDStyle.thousands(range)).font(.system(size: 8, weight: .bold, design: .rounded)))
            label.shading = .color(blue.opacity(0.8))
            ctx.draw(label, at: CGPoint(x: 2, y: 2), anchor: .topLeading)
            var low = ctx.resolve(Text("+" + HUDStyle.thousands(range)).font(.system(size: 8, weight: .bold, design: .rounded)))
            low.shading = .color(red.opacity(0.8))
            ctx.draw(low, at: CGPoint(x: 2, y: size.height - 2), anchor: .bottomLeading)
        }
        .allowsHitTesting(false)
    }
}
