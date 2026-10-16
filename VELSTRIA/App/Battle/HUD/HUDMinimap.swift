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
        let proj = HUDMinimapProjection(size: size, mapSize: map.size, inset: isExpanded ? 12 : 2)
        ZStack(alignment: .topLeading) {
            HUDMinimapTerrain(projection: proj, map: map, colorblind: model.settings.colorblindMode).equatable()
            HUDMinimapUnits(model: model, projection: proj, expanded: isExpanded)
            HUDMinimapObjective(model: model, projection: proj)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 12 : 3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 12 : 3, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.36), HUDStyle.rim.opacity(0.22)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
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
            let P = HUDMinimapPalette.self
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(P.frame))
            let bounds = HUDMinimapDrawing.rect(Rect2(minX: 0, minY: 0, maxX: map.size, maxY: map.size), proj)
            ctx.fill(Path(bounds), with: .color(P.ground))
            ctx.clip(to: Path(bounds))
            if case .polygon(let points)? = map.river {
                ctx.fill(HUDMinimapDrawing.polyline(points, proj, closed: true), with: .color(P.river))
            } else {
                var river = Path()
                river.move(to: proj.point(Vec2(0, map.size)))
                river.addLine(to: proj.point(Vec2(map.size, 0)))
                ctx.stroke(river, with: .color(P.river),
                           style: StrokeStyle(lineWidth: proj.length(map.riverWidth), lineCap: .butt))
            }
            for (k, brush) in map.brushes.enumerated() {
                guard map.bushMask != nil else {
                    ctx.fill(Path(HUDMinimapDrawing.rect(brush.rect, proj)), with: .color(P.brush))
                    continue
                }
                var shape = Path()
                for r in map.brushRects(k, step: 3) { shape.addRect(HUDMinimapDrawing.rect(r, proj)) }
                ctx.fill(shape, with: .color(P.brush))
            }
            for obstacle in map.obstacles {
                let wall: Path
                switch obstacle {
                case .rect(let rect): wall = Path(HUDMinimapDrawing.rect(rect, proj))
                case .circle(let center, let radius): wall = HUDMinimapDrawing.circle(proj.point(center), proj.length(radius))
                case .polygon(let points): wall = HUDMinimapDrawing.polyline(points, proj, closed: true)
                }
                ctx.fill(wall, with: .color(P.wall))
            }
            for points in map.lanePaths {
                let lane = HUDMinimapDrawing.polyline(points, proj)
                ctx.stroke(lane, with: .color(P.laneEdge),
                           style: StrokeStyle(lineWidth: proj.length(760), lineCap: .round, lineJoin: .round))
                ctx.stroke(lane, with: .color(P.lane),
                           style: StrokeStyle(lineWidth: proj.length(640), lineCap: .round, lineJoin: .round))
            }
            // 本拠: 角を中心にした 4 分の 1 円（青は左下・赤は右上）。道の上に重ねて半透明で塗る
            for team in Team.players {
                let corner = team == .blue ? Vec2(0, 0) : Vec2(map.size, map.size)
                let reach = map.core(team).distance(to: corner) + 1500
                let c = proj.point(corner), r = proj.length(reach)
                let disc = HUDMinimapDrawing.circle(c, r)
                let tint = P.base(team, colorblind: colorblind)
                ctx.fill(disc, with: .radialGradient(Gradient(colors: [tint.opacity(0.95), tint.opacity(0.78)]),
                                                     center: c, startRadius: 0, endRadius: r))
                ctx.stroke(disc, with: .color(.black.opacity(0.18)), lineWidth: 1)
            }
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
        ctx.fill(shadow, with: .color(Color(red: 0.02, green: 0.04, blue: 0.12).opacity(0.22)))
    }

    private func drawViewport(_ ctx: inout GraphicsContext, _ buffer: HUDMinimapBuffer) {
        guard buffer.viewportPolygon.count >= 3 else { return }
        let path = HUDMinimapDrawing.polyline(buffer.viewportPolygon, projection, closed: true)
        ctx.stroke(path, with: .color(.white.opacity(0.55)), lineWidth: 0.8)
    }

    private func drawCamp(_ ctx: inout GraphicsContext, _ camp: HUDMinimapBuffer.Camp) {
        let P = HUDMinimapPalette.self
        let p = projection.point(camp.pos)
        let unit = projection.size
        let ink = Color.black.opacity(0.55)
        var labelOffset: CGFloat = 4
        var labelColor = Color.white
        switch camp.kind {
        case .astralWyrm?, .ancientColossus?:
            // ロード（左上）・タートル（右下）: 青緑の巣の円に紫の記号
            let pit = unit * (expanded ? 0.06 : 0.072)
            ctx.fill(HUDMinimapDrawing.circle(p, pit), with: .color(P.pit.opacity(camp.alive ? 0.9 : 0.45)))
            ctx.stroke(HUDMinimapDrawing.circle(p, pit), with: .color(P.pitRim.opacity(camp.alive ? 0.8 : 0.3)), lineWidth: 1)
            let r = pit * 0.72
            // 未出現・討伐後も紫のまま薄くする（場所が常に分かるように）
            let color = P.boss.opacity(camp.alive ? 1 : 0.5)
            if camp.kind == .ancientColossus {
                let icon = HUDMinimapIcons.shape(HUDMinimapIcons.lord, at: p, radius: r)
                ctx.fill(icon, with: .color(color))
                ctx.stroke(icon, with: .color(ink), lineWidth: 0.8)
            } else {
                let turtle = HUDMinimapIcons.turtle(at: p, radius: r)
                ctx.fill(turtle.body, with: .color(color))
                ctx.stroke(turtle.body, with: .color(ink), lineWidth: 0.8)
                ctx.stroke(turtle.pattern, with: .color(.black.opacity(0.4)), lineWidth: 0.7)
            }
            labelOffset = pit + 6
            labelColor = P.pitRim
        case .blueSentinel?, .redSentinel?:
            let r = unit * (expanded ? 0.026 : 0.034)
            let icon = HUDMinimapIcons.shape(HUDMinimapIcons.sentinel, at: p, radius: r)
            ctx.fill(icon, with: .color(P.boss.opacity(camp.alive ? 1 : 0.4)))
            ctx.stroke(icon, with: .color(ink), lineWidth: 0.7)
            labelOffset = r + 5
        default:
            let r = max(1.8, unit * (expanded ? 0.011 : 0.015))
            let color: Color
            let shape: Path
            switch camp.kind {
            case .mossWanderer?: color = P.wanderer; shape = HUDMinimapDrawing.diamond(p, r * 1.25)
            case .treasureCrab?: color = P.crab; shape = HUDMinimapDrawing.circle(p, r)
            default: color = P.camp; shape = HUDMinimapDrawing.circle(p, r)
            }
            if camp.alive {
                ctx.fill(shape, with: .color(color))
                ctx.stroke(shape, with: .color(ink), lineWidth: 0.6)
            } else {
                ctx.stroke(shape, with: .color(color.opacity(0.45)), style: StrokeStyle(lineWidth: 0.8, dash: [1.5, 1.5]))
            }
            labelOffset = r + 5
            labelColor = color
        }
        if expanded {
            var label = ""
            if camp.isBoss {
                label = camp.kind == .ancientColossus ? L("ロード", "Lord") : L("タートル", "Turtle")
            }
            if let remaining = camp.respawnRemaining, remaining > 0 {
                let seconds = Int(remaining.rounded(.up))
                let timer = "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
                label += label.isEmpty ? timer : " · \(timer)"
            }
            if !label.isEmpty {
                drawLabel(&ctx, label, at: CGPoint(x: p.x, y: p.y + labelOffset), color: labelColor.opacity(0.9),
                          fontSize: camp.isBoss ? 9 : 7)
            }
        }
    }

    private func drawStructure(_ ctx: inout GraphicsContext, _ structure: HUDMinimapBuffer.Structure, colorblind: Bool) {
        let P = HUDMinimapPalette.self
        let p = projection.point(structure.pos)
        let unit = projection.size
        let r = structure.isCore ? unit * (expanded ? 0.042 : 0.056) : max(4, unit * (expanded ? 0.026 : 0.034))
        let icon = HUDMinimapIcons.shape(structure.isCore ? HUDMinimapIcons.crystal : HUDMinimapIcons.turret, at: p, radius: r)
        guard structure.alive else {
            ctx.fill(icon, with: .color(P.dead.opacity(0.55)))
            ctx.stroke(icon, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
            return
        }
        // 序盤の盾付きの塔は金色。それ以外はチーム色
        let color = structure.shielded ? P.shielded : P.structure(structure.team, colorblind: colorblind)
        ctx.fill(icon, with: .color(color))
        ctx.stroke(icon, with: .color(.black.opacity(0.55)), lineWidth: 0.8)
        // 削れた分だけ下から暗くする（体力の目安。アイコンの形は崩さない）
        let lost = 1 - min(1, max(0, structure.hpFraction))
        if lost > 0.02 {
            var c = ctx
            c.clip(to: icon)
            c.fill(Path(CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2 * CGFloat(lost))),
                   with: .color(.black.opacity(0.45)))
        }
    }

    private func drawUnit(_ ctx: inout GraphicsContext, _ dot: HUDMinimapBuffer.Dot, _ buffer: HUDMinimapBuffer) {
        let p = projection.point(dot.pos)
        let r: CGFloat = expanded ? 2.2 : 1.5
        let color = dot.team == .neutral ? Theme.gold : HUDMinimapPalette.structure(dot.team, colorblind: buffer.colorblind)
        let shape = HUDMinimapDrawing.diamond(p, r + 0.3)
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
        let ghost = dot.alpha < 1
        let team = HUDMinimapPalette.heroRim(dot.team, colorblind: buffer.colorblind)
        // 顔は円で切り抜き、縁の色でチームを示す（自分は緑）
        let k: CGFloat = 1
        func badge(_ radius: CGFloat) -> Path { HUDMinimapDrawing.circle(p, radius) }
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
        c.stroke(badge(r + rim / 2), with: .color(dot.isHuman ? HUDMinimapPalette.selfRim : team),
                 style: StrokeStyle(lineWidth: rim, dash: ghost ? [2, 2] : []))
        guard dot.isHuman || dot.isFocus else { return }
        let outer = r + rim
        if !dot.isHuman {
            // 観戦の追従対象: 外側に白い輪
            ctx.stroke(badge(outer + 1.6), with: .color(.white), lineWidth: 1.4)
        }
        if let facing = dot.facing {
            // 向き: 顔の外側に白い線の三角（中は抜く）
            let direction = CGVector(dx: CGFloat(facing.x), dy: CGFloat(-facing.y))
            let tip = CGPoint(x: p.x + direction.dx * (outer + 7), y: p.y + direction.dy * (outer + 7))
            let base = CGPoint(x: p.x + direction.dx * (outer + 1.5), y: p.y + direction.dy * (outer + 1.5))
            let half: CGFloat = expanded ? 4.4 : 3.6
            var arrow = Path()
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(x: base.x - direction.dy * half, y: base.y + direction.dx * half))
            arrow.addLine(to: CGPoint(x: base.x + direction.dy * half, y: base.y - direction.dx * half))
            arrow.closeSubpath()
            ctx.stroke(arrow, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
            ctx.stroke(arrow, with: .color(.white), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
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

/// ミニマップの配色（MLBB の灰青の地図に寄せる）。
enum HUDMinimapPalette {
    static let frame = Color(red: 0.30, green: 0.34, blue: 0.38).opacity(0.92)
    static let ground = Color(red: 0.40, green: 0.45, blue: 0.49)
    static let river = Color(red: 0.43, green: 0.48, blue: 0.53)
    static let brush = Color(red: 0.30, green: 0.34, blue: 0.38)
    static let wall = Color(red: 0.17, green: 0.19, blue: 0.22)
    static let lane = Color(red: 0.62, green: 0.66, blue: 0.69)
    static let laneEdge = Color(red: 0.50, green: 0.55, blue: 0.59)
    static let pit = Color(red: 0.19, green: 0.55, blue: 0.60)
    static let pitRim = Color(red: 0.42, green: 0.80, blue: 0.84)
    static let boss = Color(red: 0.80, green: 0.35, blue: 0.84)
    static let dead = Color(red: 0.42, green: 0.45, blue: 0.48)
    static let shielded = Color(red: 0.96, green: 0.80, blue: 0.38)
    static let camp = Color(red: 0.45, green: 0.80, blue: 0.36)
    static let crab = Color(red: 0.98, green: 0.62, blue: 0.22)
    static let wanderer = Color(red: 0.40, green: 0.82, blue: 0.90)
    static let selfRim = Color(red: 0.42, green: 0.90, blue: 0.42)

    static func base(_ team: Team, colorblind: Bool) -> Color {
        switch team {
        case .red: return colorblind ? Color(red: 0.62, green: 0.40, blue: 0.14) : Color(red: 0.58, green: 0.20, blue: 0.24)
        default: return Color(red: 0.20, green: 0.38, blue: 0.66)
        }
    }

    static func structure(_ team: Team, colorblind: Bool) -> Color {
        switch team {
        case .red: return colorblind ? Color(red: 1.0, green: 0.62, blue: 0.15) : Color(red: 0.92, green: 0.38, blue: 0.42)
        case .blue: return Color(red: 0.56, green: 0.76, blue: 0.96)
        case .neutral: return Theme.gold
        }
    }

    static func heroRim(_ team: Team, colorblind: Bool) -> Color {
        team == .red ? structure(.red, colorblind: colorblind) : Color(red: 0.34, green: 0.62, blue: 1.0)
    }
}
