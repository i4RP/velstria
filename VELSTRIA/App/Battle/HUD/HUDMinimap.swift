import SwiftUI
import VelstriaCore

/// Compact and tactical maps share world geometry, visibility and touch projection.
struct HUDMinimapView: View {
    let model: HUDModel
    let size: CGFloat
    var isExpanded = false
    @GestureState private var touching = false

    var body: some View {
        let map = model.controller.ctx.map
        let proj = HUDMinimapProjection(size: size, mapSize: map.size, inset: isExpanded ? 12 : 8)
        ZStack(alignment: .topLeading) {
            HUDMinimapTerrain(projection: proj, map: map, colorblind: model.settings.colorblindMode).equatable()
            HUDMinimapUnits(model: model, projection: proj, expanded: isExpanded)
            HUDMinimapObjective(model: model, projection: proj)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 18 : 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 18 : 14, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.65), HUDStyle.rim.opacity(0.7)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .updating($touching) { _, state, _ in state = true }
                .onChanged { value in model.minimapDragged(to: proj.world(value.location)) }
                .onEnded { _ in model.minimapReleased() }
        )
        .onChange(of: touching) { _, active in
            // A system interruption can cancel the drag without delivering onEnded.
            if !active { model.minimapReleased() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isExpanded ? L("戦術マップ", "Tactical map") : L("ミニマップ", "Minimap"))
        .accessibilityHint(L("触れた場所をカメラで確認。白い枠はカメラの範囲、点線は敵の最終目撃位置です。",
                             "Touch to look around. The white outline is the camera view; dashed markers are last-seen enemies."))
        .accessibilityIdentifier(isExpanded ? "hud_tactical_map" : "hud_minimap")
    }
}

/// Static terrain uses the battle definition, including impassable walls and brush.
private struct HUDMinimapTerrain: View, Equatable {
    let projection: HUDMinimapProjection
    let map: MapDefinition
    let colorblind: Bool

    var body: some View {
        Canvas { ctx, size in
            let proj = projection
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.06, green: 0.09, blue: 0.17)))
            let bounds = HUDMinimapDrawing.rect(Rect2(minX: 0, minY: 0, maxX: map.size, maxY: map.size), proj)
            ctx.fill(Path(bounds), with: .linearGradient(
                Gradient(colors: [Color(red: 0.17, green: 0.26, blue: 0.28), Color(red: 0.10, green: 0.17, blue: 0.24)]),
                startPoint: bounds.origin, endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)))
            ctx.clip(to: Path(bounds))
            var river = Path()
            river.move(to: proj.point(Vec2(0, map.size)))
            river.addLine(to: proj.point(Vec2(map.size, 0)))
            ctx.stroke(river, with: .color(Color(red: 0.24, green: 0.53, blue: 0.64)),
                       style: StrokeStyle(lineWidth: proj.length(map.riverWidth), lineCap: .butt))
            for points in map.lanePaths {
                let lane = HUDMinimapDrawing.polyline(points, proj)
                ctx.stroke(lane, with: .color(Color(red: 0.10, green: 0.15, blue: 0.21)),
                           style: StrokeStyle(lineWidth: proj.length(900), lineCap: .round, lineJoin: .round))
                ctx.stroke(lane, with: .color(Color(red: 0.59, green: 0.65, blue: 0.67)),
                           style: StrokeStyle(lineWidth: proj.length(650), lineCap: .round, lineJoin: .round))
                ctx.stroke(lane, with: .color(.white.opacity(0.12)),
                           style: StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round))
            }
            for obstacle in map.obstacles {
                let wall: Path
                switch obstacle {
                case .rect(let rect): wall = Path(HUDMinimapDrawing.rect(rect, proj))
                case .circle(let center, let radius): wall = HUDMinimapDrawing.circle(proj.point(center), proj.length(radius))
                }
                ctx.fill(wall, with: .color(Color(red: 0.06, green: 0.10, blue: 0.16)))
                ctx.stroke(wall, with: .color(Color(red: 0.38, green: 0.49, blue: 0.52).opacity(0.75)), lineWidth: 0.65)
            }
            for brush in map.brushes {
                let rect = HUDMinimapDrawing.rect(brush.rect, proj)
                ctx.fill(Path(rect), with: .color(Color(red: 0.29, green: 0.53, blue: 0.34)))
                ctx.stroke(Path(rect), with: .color(Color(red: 0.53, green: 0.77, blue: 0.44).opacity(0.8)), lineWidth: 0.5)
                // Texture distinguishes brush from open ground without relying on hue.
                var stripe = Path()
                stripe.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.2))
                stripe.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.2))
                ctx.stroke(stripe, with: .color(.white.opacity(0.3)), lineWidth: 0.6)
            }
            for team in Team.players {
                let p = proj.point(map.fountain(team)), r = proj.length(Balance.fountainRadius)
                let color = Theme.teamColor(team, colorblind: colorblind)
                let pool = HUDMinimapDrawing.circle(p, r)
                ctx.fill(pool, with: .color(color.opacity(0.26)))
                ctx.stroke(pool, with: .color(color.opacity(0.75)), lineWidth: 1)
                var cross = Path()
                let arm = max(1.5, r * 0.35)
                cross.move(to: CGPoint(x: p.x - arm, y: p.y))
                cross.addLine(to: CGPoint(x: p.x + arm, y: p.y))
                cross.move(to: CGPoint(x: p.x, y: p.y - arm))
                cross.addLine(to: CGPoint(x: p.x, y: p.y + arm))
                ctx.stroke(cross, with: .color(.white.opacity(0.8)), lineWidth: 1)
            }
            ctx.stroke(Path(bounds), with: .color(.white.opacity(0.16)), lineWidth: 1)
        }
        .frame(width: projection.size, height: projection.size)
        .allowsHitTesting(false)
    }
}

/// Dynamic data has its own canvas, leaving static terrain unchanged between HUD ticks.
private struct HUDMinimapUnits: View {
    let model: HUDModel
    let projection: HUDMinimapProjection
    let expanded: Bool

    var body: some View {
        let version = model.minimapVersion
        let buffer = model.minimap
        Canvas { ctx, _ in
            _ = version
            drawFog(&ctx, buffer)
            drawViewport(&ctx, buffer)
            for camp in buffer.camps { drawCamp(&ctx, camp) }
            for structure in buffer.structures { drawStructure(&ctx, structure, colorblind: buffer.colorblind) }
            for dot in buffer.units { drawUnit(&ctx, dot, buffer) }
            for dot in buffer.heroes where dot.isHuman || dot.isFocus { drawSight(&ctx, dot) }
            // HUDModel appends the local player last so it stays visible in a crowded fight.
            for dot in buffer.heroes { drawHero(&ctx, dot, buffer) }
        }
        .frame(width: projection.size, height: projection.size)
        .allowsHitTesting(false)
    }

    private func drawFog(_ ctx: inout GraphicsContext, _ buffer: HUDMinimapBuffer) {
        guard let team = buffer.viewerTeam else { return }
        let vision = buffer.vision
        guard vision.cols > 0, vision.rows > 0, vision.cells.count == vision.cols * vision.rows else { return }
        var shadow = Path()
        // Merge contiguous cells per row to avoid seams and thousands of individual draw calls.
        for row in 0..<vision.rows {
            var col = 0
            while col < vision.cols {
                if vision.cells[row * vision.cols + col] & team.visionBit != 0 { col += 1; continue }
                let start = col
                repeat { col += 1 } while col < vision.cols && vision.cells[row * vision.cols + col] & team.visionBit == 0
                let cell = Balance.visionCellSize
                let rect = Rect2(minX: Double(start) * cell, minY: Double(row) * cell,
                                 maxX: min(projection.mapSize, Double(col) * cell),
                                 maxY: min(projection.mapSize, Double(row + 1) * cell))
                shadow.addRect(HUDMinimapDrawing.rect(rect, projection))
            }
        }
        ctx.fill(shadow, with: .color(Color(red: 0.02, green: 0.04, blue: 0.12).opacity(0.48)))
    }

    private func drawViewport(_ ctx: inout GraphicsContext, _ buffer: HUDMinimapBuffer) {
        guard buffer.viewportPolygon.count >= 3 else { return }
        let path = HUDMinimapDrawing.polyline(buffer.viewportPolygon, projection, closed: true)
        ctx.fill(path, with: .color(.white.opacity(0.035)))
        ctx.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 2.6)
        ctx.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 1.1)
    }

    private func drawCamp(_ ctx: inout GraphicsContext, _ camp: HUDMinimapBuffer.Camp) {
        let p = projection.point(camp.pos)
        let r: CGFloat = camp.isBoss ? (expanded ? 7 : 4.6) : (expanded ? 3.4 : 2.3)
        let shape = camp.isBoss ? HUDMinimapDrawing.diamond(p, r + 1) : HUDMinimapDrawing.circle(p, r)
        let color: Color
        switch camp.kind {
        case .blueSentinel: color = Theme.cyan
        case .redSentinel: color = Color(red: 1, green: 0.60, blue: 0.32)
        default: color = Theme.gold
        }
        ctx.fill(shape, with: .color(Color(red: 0.08, green: 0.09, blue: 0.15)))
        if camp.alive {
            ctx.fill(shape, with: .color(color))
            ctx.stroke(shape, with: .color(.black.opacity(0.8)), lineWidth: 1.2)
            if camp.isBoss {
                ctx.stroke(HUDMinimapDrawing.diamond(p, r + 3), with: .color(color.opacity(0.5)), lineWidth: 1)
                let mark = camp.kind == .ancientColossus ? "◆" : "✦"
                ctx.draw(Text(mark).font(.system(size: r * 1.5, weight: .black)).foregroundStyle(Color.black.opacity(0.7)), at: p)
            }
        } else {
            ctx.stroke(shape, with: .color(color.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
        if expanded {
            var label = ""
            if camp.isBoss {
                label = camp.kind == .ancientColossus ? L("古環の巨像", "Colossus") : L("星喰竜", "Wyrm")
            }
            if let remaining = camp.respawnRemaining, remaining > 0 {
                let seconds = Int(remaining.rounded(.up))
                let timer = "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
                label += label.isEmpty ? timer : " · \(timer)"
            }
            if !label.isEmpty {
                drawLabel(&ctx, label, at: CGPoint(x: p.x, y: p.y + r + 7), color: color.opacity(0.85), fontSize: camp.isBoss ? 9 : 7)
            }
        }
    }

    private func drawStructure(_ ctx: inout GraphicsContext, _ structure: HUDMinimapBuffer.Structure, colorblind: Bool) {
        let p = projection.point(structure.pos)
        let r: CGFloat = structure.isCore ? (expanded ? 9 : 6) : (expanded ? 5.3 : 3.6)
        let color = Theme.teamColor(structure.team, colorblind: colorblind)
        let outline = HUDMinimapDrawing.circle(p, r + 1)
        let body = structure.isCore ? HUDMinimapDrawing.diamond(p, r) : HUDMinimapDrawing.circle(p, r - 0.7)
        ctx.fill(outline, with: .color(Color(red: 0.03, green: 0.05, blue: 0.10)))
        if structure.alive {
            ctx.fill(body, with: .color(color.opacity(structure.isCore ? 0.9 : 0.6)))
            ctx.stroke(outline, with: .color(color.opacity(0.24)), lineWidth: 1.6)
            var hp = Path()
            hp.addArc(center: p, radius: r + 1, startAngle: .degrees(-90),
                      endAngle: .degrees(-90 + 360 * min(1, max(0, structure.hpFraction))), clockwise: false)
            ctx.stroke(hp, with: .color(color), style: StrokeStyle(lineWidth: expanded ? 2.2 : 1.5, lineCap: .round))
            ctx.fill(HUDMinimapDrawing.circle(p, structure.isCore ? 1.5 : 0.8), with: .color(.white.opacity(0.9)))
        } else {
            ctx.stroke(body, with: .color(color.opacity(0.35)), lineWidth: 1)
            var slash = Path()
            slash.move(to: CGPoint(x: p.x - r * 0.7, y: p.y + r * 0.7))
            slash.addLine(to: CGPoint(x: p.x + r * 0.7, y: p.y - r * 0.7))
            ctx.stroke(slash, with: .color(.white.opacity(0.25)), lineWidth: 0.8)
        }
    }

    private func drawUnit(_ ctx: inout GraphicsContext, _ dot: HUDMinimapBuffer.Dot, _ buffer: HUDMinimapBuffer) {
        let p = projection.point(dot.pos)
        let r: CGFloat = expanded ? 2.2 : 1.5
        let enemy = buffer.viewerTeam.map { dot.team != $0 && dot.team != .neutral } ?? (dot.team == .red)
        let color = dot.team == .neutral ? Theme.gold : Theme.teamColor(dot.team, colorblind: buffer.colorblind)
        let shape = enemy ? HUDMinimapDrawing.diamond(p, r + 0.5) : HUDMinimapDrawing.circle(p, r)
        ctx.fill(shape, with: .color(color.opacity(dot.alpha)))
        ctx.stroke(shape, with: .color(.black.opacity(0.65)), lineWidth: 0.5)
    }

    private func drawSight(_ ctx: inout GraphicsContext, _ dot: HUDMinimapBuffer.Dot) {
        guard dot.visionRadius > 0, dot.alpha >= 1 else { return }
        let ring = HUDMinimapDrawing.circle(projection.point(dot.pos), projection.length(dot.visionRadius))
        ctx.stroke(ring, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 0.75, dash: [2, 3]))
    }

    private func drawHero(_ ctx: inout GraphicsContext, _ dot: HUDMinimapBuffer.Dot, _ buffer: HUDMinimapBuffer) {
        let p = projection.point(dot.pos)
        let r: CGFloat = (expanded ? 8.2 : 5.9) + (dot.isHuman ? 1 : 0)
        let enemy = buffer.viewerTeam.map { dot.team != $0 } ?? (dot.team == .red)
        let ghost = dot.alpha < 1
        let team = Theme.teamColor(dot.team, colorblind: buffer.colorblind)
        let body = enemy ? HUDMinimapDrawing.diamond(p, r + 0.6) : HUDMinimapDrawing.circle(p, r)
        let background = enemy ? HUDMinimapDrawing.diamond(p, r + 1.8) : HUDMinimapDrawing.circle(p, r + 1.3)
        ctx.fill(background, with: .color(.black.opacity(0.85 * dot.alpha)))
        ctx.fill(body, with: .color(Color(hue: dot.hue, saturation: 0.52, brightness: ghost ? 0.3 : 0.47).opacity(dot.alpha)))
        ctx.stroke(body, with: .color(team.opacity(ghost ? max(0.35, dot.alpha) : 1)),
                   style: StrokeStyle(lineWidth: 1.8, dash: ghost ? [2, 2] : []))
        let initial = dot.heroID.flatMap { model.controller.ctx.master.hero($0) }.map { String($0.codeName.prefix(1)) } ?? "•"
        ctx.draw(Text(ghost ? "?" : initial)
            .font(.system(size: r * 1.35, weight: .black, design: .rounded))
            .foregroundStyle(.white.opacity(ghost ? max(0.4, dot.alpha) : 1)), at: p)
        if dot.isHuman || dot.isFocus {
            let focus = enemy ? HUDMinimapDrawing.diamond(p, r + 3.3) : HUDMinimapDrawing.circle(p, r + 2.7)
            ctx.stroke(focus, with: .color(.white), lineWidth: 1.6)
            if let facing = dot.facing {
                let direction = CGVector(dx: CGFloat(facing.x), dy: CGFloat(-facing.y))
                let tip = CGPoint(x: p.x + direction.dx * (r + 8), y: p.y + direction.dy * (r + 8))
                let base = CGPoint(x: p.x + direction.dx * (r + 3.5), y: p.y + direction.dy * (r + 3.5))
                var arrow = Path()
                arrow.move(to: tip)
                arrow.addLine(to: CGPoint(x: base.x - direction.dy * 3, y: base.y + direction.dx * 3))
                arrow.addLine(to: CGPoint(x: base.x + direction.dy * 3, y: base.y - direction.dx * 3))
                arrow.closeSubpath()
                ctx.stroke(arrow, with: .color(.black.opacity(0.8)), lineWidth: 2)
                ctx.fill(arrow, with: .color(.white))
            }
        }
    }

    private func drawLabel(_ ctx: inout GraphicsContext, _ label: String, at point: CGPoint, color: Color, fontSize: CGFloat) {
        let text = Text(label).font(.system(size: fontSize, weight: .bold, design: .rounded)).monospacedDigit()
        var resolved = ctx.resolve(text)
        let measured = resolved.measure(in: CGSize(width: 80, height: 20))
        let rect = CGRect(x: point.x - measured.width / 2 - 3, y: point.y - measured.height / 2 - 1,
                          width: measured.width + 6, height: measured.height + 2)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Color.black.opacity(0.8)))
        resolved.shading = .color(color)
        ctx.draw(resolved, at: point)
    }
}

private enum HUDMinimapDrawing {
    static func rect(_ rect: Rect2, _ projection: HUDMinimapProjection) -> CGRect {
        let a = projection.point(Vec2(rect.minX, rect.maxY)), b = projection.point(Vec2(rect.maxX, rect.minY))
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    static func circle(_ point: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }

    static func diamond(_ center: CGPoint, _ radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.closeSubpath()
        return path
    }

    static func polyline(_ points: [Vec2], _ projection: HUDMinimapProjection, closed: Bool = false) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            if index == 0 { path.move(to: projection.point(point)) }
            else { path.addLine(to: projection.point(point)) }
        }
        if closed { path.closeSubpath() }
        return path
    }
}

private struct HUDMinimapObjective: View {
    let model: HUDModel
    let projection: HUDMinimapProjection

    var body: some View {
        if let point = model.tutorialObjective {
            HUDHighlightRing(diameter: 20)
                .position(projection.point(point))
                .frame(width: projection.size, height: projection.size)
                .allowsHitTesting(false)
        }
    }
}
