import SwiftUI
import VelstriaCore

// 担当: battle-hud。ミニマップ（ドック）と全体マップの共通描画。
// ヒーローは顔アイコン（ポートレートの顔の辺りを円/ひし形に切り抜き、チーム色の縁。味方 = 円、敵 = ひし形で色覚に頼らない。
// 自分は白い縁 + 向きの矢印、残像は暗くした顔 + 点線の縁）。顔の画像は heroID ごとに 1 度だけ縮小してキャッシュする。
// クイックシグナルのピン（HUDSignalCenter が書き込む）は種類の色の広がるリングと、地点の上に立てた印（攻撃 = ×・撤退 = ▼・集合 = ◎）。

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
        // 顔の画像はここ（MainActor）で解決してから描画クロージャへ渡す
        let faces = HUDMinimapFaces.faces(for: buffer.heroes)
        Canvas { ctx, _ in
            _ = version
            drawFog(&ctx, buffer)
            drawViewport(&ctx, buffer)
            for camp in buffer.camps { drawCamp(&ctx, camp) }
            for structure in buffer.structures { drawStructure(&ctx, structure, colorblind: buffer.colorblind) }
            for dot in buffer.units { drawUnit(&ctx, dot, buffer) }
            for dot in buffer.heroes where dot.isHuman || dot.isFocus { drawSight(&ctx, dot) }
            // HUDModel appends the local player last so it stays visible in a crowded fight.
            var resolved: [String: GraphicsContext.ResolvedImage] = [:]
            for dot in buffer.heroes { drawHero(&ctx, dot, buffer, faces: faces, resolved: &resolved) }
            // シグナルのピンは最前面
            drawPings(&ctx, buffer)
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

    private func drawHero(_ ctx: inout GraphicsContext, _ dot: HUDMinimapBuffer.Dot, _ buffer: HUDMinimapBuffer,
                          faces: [String: Image], resolved: inout [String: GraphicsContext.ResolvedImage]) {
        let p = projection.point(dot.pos)
        let r = HUDMinimapFaces.radius(mapSize: projection.size, expanded: expanded) * (dot.isHuman ? 1.15 : 1)
        let enemy = buffer.viewerTeam.map { dot.team != $0 } ?? (dot.team == .red)
        let ghost = dot.alpha < 1
        let team = Theme.teamColor(dot.team, colorblind: buffer.colorblind)
        // 味方 = 円、敵 = ひし形（ひし形は円と同じ大きさに見えるよう外接半径を広げる）
        let k: CGFloat = enemy ? 1.3 : 1
        func badge(_ radius: CGFloat) -> Path {
            enemy ? HUDMinimapDrawing.diamond(p, radius * k) : HUDMinimapDrawing.circle(p, radius)
        }
        let rim: CGFloat = dot.isHuman ? 2.2 : (expanded ? 2 : 1.6)
        var c = ctx
        c.opacity = dot.alpha
        c.fill(badge(r + rim + 1), with: .color(.black.opacity(0.8)))
        let face = badge(r)
        if let id = dot.heroID, let image = faces[id] {
            let art = resolved[id] ?? c.resolve(image)
            resolved[id] = art
            var inner = c
            inner.clip(to: face)
            inner.draw(art, in: CGRect(x: p.x - r * k, y: p.y - r * k, width: r * k * 2, height: r * k * 2))
            // 残像は暗く（最後に見えた位置であることを点線の縁と合わせて示す）
            if ghost { inner.fill(face, with: .color(.black.opacity(0.45))) }
        } else {
            // アートの無いヒーローは色面 + 頭文字
            c.fill(face, with: .color(Color(hue: dot.hue, saturation: 0.52, brightness: ghost ? 0.3 : 0.47)))
            let initial = dot.heroID.flatMap { model.controller.ctx.master.hero($0) }.map { String($0.codeName.prefix(1)) } ?? "•"
            c.draw(Text(ghost ? "?" : initial)
                .font(.system(size: r * 1.35, weight: .black, design: .rounded))
                .foregroundStyle(.white), at: p)
        }
        // 縁: チーム色（自分は白）。残像は点線
        c.stroke(badge(r + rim / 2), with: .color(dot.isHuman ? .white : team),
                 style: StrokeStyle(lineWidth: rim, dash: ghost ? [2, 2] : []))
        guard dot.isHuman || dot.isFocus else { return }
        let outer = r + rim
        if !dot.isHuman {
            // 観戦の追従対象: 外側に白い輪
            ctx.stroke(badge(outer + 1.6), with: .color(.white), lineWidth: 1.4)
        }
        if let facing = dot.facing {
            let direction = CGVector(dx: CGFloat(facing.x), dy: CGFloat(-facing.y))
            let reach = outer * (enemy ? k : 1)
            let tip = CGPoint(x: p.x + direction.dx * (reach + 6.5), y: p.y + direction.dy * (reach + 6.5))
            let base = CGPoint(x: p.x + direction.dx * (reach + 1.2), y: p.y + direction.dy * (reach + 1.2))
            let half: CGFloat = expanded ? 4 : 3.2
            var arrow = Path()
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(x: base.x - direction.dy * half, y: base.y + direction.dx * half))
            arrow.addLine(to: CGPoint(x: base.x + direction.dy * half, y: base.y - direction.dx * half))
            arrow.closeSubpath()
            ctx.stroke(arrow, with: .color(.black.opacity(0.8)), lineWidth: 2)
            ctx.fill(arrow, with: .color(.white))
        }
    }

    /// クイックシグナルのピン（0.8 秒周期で広がるリング 2 重と、地点の上に立てた印。印の形でも種類が分かる）。
    private func drawPings(_ ctx: inout GraphicsContext, _ buffer: HUDMinimapBuffer) {
        guard !buffer.pings.isEmpty else { return }
        let unit = HUDMinimapFaces.radius(mapSize: projection.size, expanded: expanded)
        for ping in buffer.pings {
            let age = buffer.pingClock - ping.createdAt
            guard age >= 0, age < HUDSignalBoard.pingLifetime else { continue }
            let p = projection.point(ping.pos)
            let color = ping.kind.color
            let fade = min(1, (HUDSignalBoard.pingLifetime - age) / 0.4)
            for wave in 0..<2 {
                let a = age - Double(wave) * 0.4
                guard a >= 0 else { continue }
                let t = (a / 0.8).truncatingRemainder(dividingBy: 1)
                let rr = unit * (0.7 + 1.9 * CGFloat(t))
                ctx.stroke(HUDMinimapDrawing.circle(p, rr), with: .color(color.opacity((1 - t) * fade)), lineWidth: expanded ? 2.4 : 1.8)
            }
            HUDMinimapDrawing.pingPin(ctx, ping.kind, at: p, radius: unit * 0.78, color: color, opacity: fade)
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
    /// ピンの印（地点の上に立てる。顔アイコンを隠さないように）。中の記号は 攻撃 = ×、撤退 = ▼、集合 = ◎。
    static func pingPin(_ ctx: GraphicsContext, _ kind: HUDSignalKind, at p: CGPoint, radius r: CGFloat,
                        color: Color, opacity: Double) {
        var c = ctx
        c.opacity = opacity
        // 上端に近い地点では下に立てる
        let up = p.y - r * 3.4 >= 0
        let center = CGPoint(x: p.x, y: up ? p.y - r * 2.4 : p.y + r * 2.4)
        var pointer = Path()
        let baseY = center.y + (up ? r * 0.6 : -r * 0.6)
        pointer.move(to: CGPoint(x: center.x - r * 0.55, y: baseY))
        pointer.addLine(to: CGPoint(x: center.x + r * 0.55, y: baseY))
        pointer.addLine(to: CGPoint(x: p.x, y: p.y + (up ? -r * 0.5 : r * 0.5)))
        pointer.closeSubpath()
        c.fill(circle(center, r + 1.2), with: .color(.black.opacity(0.6)))
        c.fill(pointer, with: .color(color))
        c.fill(circle(center, r), with: .color(color))
        let ink = Color.black.opacity(0.8)
        switch kind {
        case .attack:
            var x = Path()
            let a = r * 0.45
            x.move(to: CGPoint(x: center.x - a, y: center.y - a))
            x.addLine(to: CGPoint(x: center.x + a, y: center.y + a))
            x.move(to: CGPoint(x: center.x + a, y: center.y - a))
            x.addLine(to: CGPoint(x: center.x - a, y: center.y + a))
            c.stroke(x, with: .color(ink), style: StrokeStyle(lineWidth: max(1.4, r * 0.28), lineCap: .round))
        case .retreat:
            var t = Path()
            t.move(to: CGPoint(x: center.x - r * 0.52, y: center.y - r * 0.32))
            t.addLine(to: CGPoint(x: center.x + r * 0.52, y: center.y - r * 0.32))
            t.addLine(to: CGPoint(x: center.x, y: center.y + r * 0.5))
            t.closeSubpath()
            c.fill(t, with: .color(ink))
        case .gather:
            let i = r * 0.22, o = r * 0.55
            c.fill(circle(center, i), with: .color(ink))
            c.stroke(circle(center, o), with: .color(ink), lineWidth: max(1, r * 0.18))
        }
    }

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

/// ミニマップの顔アイコン（ポートレートの顔の辺りを小さく切り抜いた画像を heroID ごとにキャッシュする）。
/// 元画像（640px）を 15Hz の描画で毎回縮小しないよう、最初に 1 度だけ縮小して SwiftUI の Image にしておく。
@MainActor
enum HUDMinimapFaces {
    /// 縮小後の一辺（px）。ミニマップ上の直径（≈ 15〜25pt）の 3 倍程度。
    static let pixelSize: CGFloat = 72
    private static var cache: [String: Image?] = [:]

    /// 顔アイコンの半径（地図の一辺に比例。自分は 1.15 倍）。
    nonisolated static func radius(mapSize: CGFloat, expanded: Bool) -> CGFloat {
        expanded ? max(9.5, mapSize * 0.036) : max(6.5, mapSize * 0.05)
    }

    /// アートの無い heroID は nil（色面 + 頭文字で代用）。
    static func face(_ heroID: String) -> Image? {
        if let hit = cache[heroID] { return hit }
        let img = PortraitArt.hero(heroID).map { Image(uiImage: thumbnail($0)) }
        cache[heroID] = img
        return img
    }

    /// 描画するヒーローの顔（heroID → 縮小済みの画像）。
    static func faces(for heroes: [HUDMinimapBuffer.Dot]) -> [String: Image] {
        var out: [String: Image] = [:]
        for d in heroes {
            guard let id = d.heroID, out[id] == nil, let img = face(id) else { continue }
            out[id] = img
        }
        return out
    }

    /// 顔の辺り（横 0.52・縦 0.36 を中心に一辺 0.6）を正方形に切り抜いて縮小する。
    static func thumbnail(_ src: UIImage) -> UIImage {
        let side = pixelSize
        let base = max(1, min(src.size.width, src.size.height))
        let k = side / (base * 0.6)
        let w = src.size.width * k, h = src.size.height * k
        let x = min(0, max(side - w, side / 2 - 0.52 * w))
        let y = min(0, max(side - h, side / 2 - 0.36 * h))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            src.draw(in: CGRect(x: x, y: y, width: w, height: h))
        }
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
