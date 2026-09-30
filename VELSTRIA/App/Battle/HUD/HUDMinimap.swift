import SwiftUI
import VelstriaCore

// 担当: battle-hud。ミニマップ（左上）。
// 静的な地形（外形・河川・レーン・壁・泉）は 1 度だけ描く Canvas、ユニット等は 15Hz で更新する Canvas に分ける。
// タップ/ドラッグで自由カメラ（controller.cameraMode = .free）、離すとヒーロー追従に戻る（観戦は自由カメラのまま）。

/// sim 座標 ↔ ミニマップ座標（画面の上 = sim +y）。
struct HUDMinimapProjection: Equatable {
    let size: CGFloat
    var mapSize: Double = Balance.mapSize

    func point(_ p: Vec2) -> CGPoint {
        CGPoint(x: CGFloat(p.x / mapSize) * size, y: CGFloat(1 - p.y / mapSize) * size)
    }

    func world(_ q: CGPoint) -> Vec2 {
        guard size > 0 else { return Vec2(mapSize / 2, mapSize / 2) }
        let x = min(1, max(0, Double(q.x / size))) * mapSize
        let y = (1 - min(1, max(0, Double(q.y / size)))) * mapSize
        return Vec2(x, y)
    }

    func length(_ units: Double) -> CGFloat { CGFloat(units / mapSize) * size }
}

/// ミニマップの描画データ（15Hz で HUDModel が書き換える。配列は容量を保ったまま再利用する）。
final class HUDMinimapBuffer {
    struct Dot {
        var pos: Vec2
        var team: Team
        var kind: UnitKind
        var hue: Double
        var isHuman: Bool
        var isFocus: Bool
        /// 1 = 現在見えている、< 1 = 最後に見えた位置の残像。
        var alpha: Double
    }

    struct Structure {
        var pos: Vec2
        var team: Team
        var alive: Bool
        var isCore: Bool
    }

    struct Camp {
        var pos: Vec2
        var alive: Bool
        var isBoss: Bool
    }

    var units: [Dot] = []
    var heroes: [Dot] = []
    var structures: [Structure] = []
    var camps: [Camp] = []
    var viewport: Rect2?
    var colorblind = false
    var viewerTeam: Team? = .blue
}

struct HUDMinimapView: View {
    let model: HUDModel
    let size: CGFloat

    var body: some View {
        let proj = HUDMinimapProjection(size: size)
        ZStack(alignment: .topLeading) {
            HUDMinimapTerrain(size: size)
            HUDMinimapUnits(model: model, projection: proj)
            HUDMinimapObjective(model: model, projection: proj)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LinearGradient(colors: [HUDStyle.rim, Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                              lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(0.5), radius: 6)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in model.minimapDragged(to: proj.world(v.location)) }
                .onEnded { _ in model.minimapReleased() }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("ミニマップ", "Minimap"))
        .accessibilityHint(L("タッチした場所をカメラで表示します", "Touch to look at that part of the map"))
        .accessibilityIdentifier("hud_minimap")
    }
}

/// 地形（変化しないので再描画されない）。
private struct HUDMinimapTerrain: View, Equatable {
    let size: CGFloat

    var body: some View {
        Canvas { ctx, sz in
            let proj = HUDMinimapProjection(size: sz.width)
            let map = MapDefinition.standard
            let full = CGRect(origin: .zero, size: sz)
            ctx.fill(Path(full), with: .linearGradient(
                Gradient(colors: [Color(red: 0.07, green: 0.12, blue: 0.13), Color(red: 0.05, green: 0.07, blue: 0.13)]),
                startPoint: .zero, endPoint: CGPoint(x: sz.width, y: sz.height)))
            // 河川（左上 → 右下の帯）
            var river = Path()
            river.move(to: proj.point(Vec2(0, map.size)))
            river.addLine(to: proj.point(Vec2(map.size, 0)))
            ctx.stroke(river, with: .color(Color(red: 0.20, green: 0.45, blue: 0.75).opacity(0.55)),
                       style: StrokeStyle(lineWidth: proj.length(map.riverWidth), lineCap: .butt))
            // ジャングルの壁
            for o in map.obstacles {
                switch o {
                case .rect(let r):
                    let a = proj.point(Vec2(r.minX, r.maxY)), b = proj.point(Vec2(r.maxX, r.minY))
                    ctx.fill(Path(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)),
                             with: .color(Color.black.opacity(0.45)))
                case .circle(let c, let r):
                    let p = proj.point(c), rr = proj.length(r)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)),
                             with: .color(Color.black.opacity(0.45)))
                }
            }
            // レーン
            for path in map.lanePaths {
                var lane = Path()
                for (k, p) in path.enumerated() {
                    if k == 0 { lane.move(to: proj.point(p)) } else { lane.addLine(to: proj.point(p)) }
                }
                ctx.stroke(lane, with: .color(Color(red: 0.85, green: 0.78, blue: 0.60).opacity(0.38)),
                           style: StrokeStyle(lineWidth: max(2, proj.length(420)), lineCap: .round, lineJoin: .round))
            }
            // 泉
            for team in Team.players {
                let p = proj.point(map.fountain(team)), r = proj.length(Balance.fountainRadius)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(Theme.teamColor(team).opacity(0.22)))
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

/// ユニット・構造物・キャンプ・視点枠（15Hz）。
private struct HUDMinimapUnits: View {
    let model: HUDModel
    let projection: HUDMinimapProjection

    var body: some View {
        let _ = model.minimapVersion
        let buffer = model.minimap
        Canvas { ctx, _ in
            let proj = projection
            let cb = buffer.colorblind
            let viewer = buffer.viewerTeam
            // キャンプ
            for c in buffer.camps where c.alive {
                let p = proj.point(c.pos)
                let r: CGFloat = c.isBoss ? 4.5 : 2.6
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(Theme.gold.opacity(c.isBoss ? 0.95 : 0.7)))
                if c.isBoss {
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r - 1.5, y: p.y - r - 1.5, width: r * 2 + 3, height: r * 2 + 3)),
                               with: .color(.white.opacity(0.6)), lineWidth: 1)
                }
            }
            // 構造物
            for s in buffer.structures {
                let p = proj.point(s.pos)
                let half: CGFloat = s.isCore ? 5 : 3.4
                let rect = CGRect(x: p.x - half, y: p.y - half, width: half * 2, height: half * 2)
                let color = Theme.teamColor(s.team, colorblind: cb)
                let shape: Path = s.isCore ? Self.diamond(p, half + 1) : Path(roundedRect: rect, cornerRadius: 1)
                if s.alive {
                    ctx.fill(shape, with: .color(color))
                    ctx.stroke(shape, with: .color(.white.opacity(0.75)), lineWidth: 0.8)
                } else {
                    ctx.fill(shape, with: .color(Color.black.opacity(0.55)))
                    ctx.stroke(shape, with: .color(color.opacity(0.45)), lineWidth: 0.8)
                }
            }
            // ミニオン・モンスター・人形
            for d in buffer.units {
                let p = proj.point(d.pos)
                let color = d.team == .neutral ? Theme.gold.opacity(0.9) : Theme.teamColor(d.team, colorblind: cb)
                let r: CGFloat = d.kind == .minion ? 1.7 : 2.2
                let enemy = viewer.map { d.team != $0 && d.team != .neutral } ?? (d.team == .red)
                let path = cb && enemy
                    ? Path(CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    : Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.fill(path, with: .color(color.opacity(d.alpha)))
            }
            // ヒーロー（人間は最前面・白枠）
            for d in buffer.heroes {
                let p = proj.point(d.pos)
                let r: CGFloat = d.isHuman ? 6 : 5
                let team = Theme.teamColor(d.team, colorblind: cb)
                let enemy = viewer.map { d.team != $0 } ?? (d.team == .red)
                let body: Path = cb && enemy ? Self.diamond(p, r + 1) : Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.fill(body, with: .color(Color(hue: d.hue, saturation: 0.55, brightness: 0.85).opacity(d.alpha)))
                ctx.stroke(body, with: .color(team.opacity(d.alpha)), lineWidth: 2)
                if d.isHuman || d.isFocus {
                    let ring: Path = cb && enemy ? Self.diamond(p, r + 3.5)
                        : Path(ellipseIn: CGRect(x: p.x - r - 2.2, y: p.y - r - 2.2, width: (r + 2.2) * 2, height: (r + 2.2) * 2))
                    ctx.stroke(ring, with: .color(.white), lineWidth: 1.4)
                }
            }
            // 視点枠
            if let v = buffer.viewport {
                let a = proj.point(Vec2(v.minX, v.maxY)), b = proj.point(Vec2(v.maxX, v.minY))
                let rect = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
                ctx.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(.white.opacity(0.85)), lineWidth: 1)
            }
        }
        .frame(width: projection.size, height: projection.size)
        .allowsHitTesting(false)
    }

    static func diamond(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addLine(to: CGPoint(x: c.x + r, y: c.y))
        p.addLine(to: CGPoint(x: c.x, y: c.y + r))
        p.addLine(to: CGPoint(x: c.x - r, y: c.y))
        p.closeSubpath()
        return p
    }
}

/// チュートリアルの目標地点（脈動リング）。
private struct HUDMinimapObjective: View {
    let model: HUDModel
    let projection: HUDMinimapProjection

    var body: some View {
        if let p = model.tutorialObjective {
            let q = projection.point(p)
            HUDHighlightRing(diameter: 18)
                .position(q)
                .frame(width: projection.size, height: projection.size)
        }
    }
}
