import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI039 スキル詳細（左: ヒーロー情報とスキルアイコン列 / 右: スキル名・タグ・説明・レベル表）。
// 部品は SkillShowcaseViews.swift（ヒーロー詳細のスキルタブと同じ見た目）。計算は SkillShowcaseLogic.swift。

struct SkillDetailView: View {
    let skillID: String
    @Environment(AppModel.self) private var app
    @State private var currentID: String?

    var body: some View {
        let id = currentID ?? skillID
        ScreenScaffold(title: L("スキル詳細", "Skill Details")) {
            if let skill = app.master.skill(id), let hero = app.master.hero(skill.heroID) {
                content(skill: skill, hero: hero)
            } else {
                CollectionEmptyState(symbol: "questionmark.circle", title: L("スキルが見つかりません", "Skill not found"))
            }
        }
    }

    private func content(skill: SkillDef, hero: HeroDef) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 同じヒーローの他スキルへの切り替えは、左のスキルアイコン列で行う
            HeroInfoPanel(hero: hero, selectedSkillID: skill.skillID, skillIDPrefix: "skilldetail_switch_",
                          shows3DPreview: false,
                          onSelectSkill: { currentID = $0.skillID })
            SkillShowcasePanel(skill: skill, hero: hero)
                .id(skill.skillID)
                .transition(.opacity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.2), value: skill.skillID)
    }
}

// MARK: - アーキタイプ図（アニメーション）

/// スキル形状の俯瞰図。術者は左（自身中心系は中央）、敵 = 赤、味方 = 緑。
struct SkillShapeDiagram: View {
    let archetype: SkillArchetype
    let range: Double
    let radius: Double
    var color: Color = Theme.cyan
    var cc: CrowdControl = .none
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let cycle = 2.4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            let t = reduceMotion ? Self.cycle * 0.62 : tl.date.timeIntervalSinceReferenceDate
            let phase = (t / Self.cycle).truncatingRemainder(dividingBy: 1)
            Canvas { ctx, size in
                var scene = SkillDiagramScene(ctx: ctx, size: size, archetype: archetype, range: range, radius: radius,
                                              color: color, phase: phase, time: t, showsCC: cc != .none)
                scene.draw()
            }
        }
        .background(
            LinearGradient(colors: [Color(red: 0.06, green: 0.10, blue: 0.16), Color(red: 0.04, green: 0.05, blue: 0.10)],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}

struct SkillDiagramScene {
    var ctx: GraphicsContext
    let size: CGSize
    let archetype: SkillArchetype
    let range: Double
    let radius: Double
    let color: Color
    let phase: Double
    let time: Double
    let showsCC: Bool

    private let enemy = Color(red: 1.0, green: 0.36, blue: 0.40)
    private let ally = Color(red: 0.36, green: 0.92, blue: 0.62)

    /// 図に収める最大距離（ワールド単位）。
    private var extent: Double {
        let r = max(radius, 60)
        switch archetype {
        case .passive: return 400
        case .cone: return max(range, 200)
        case .lineSkillshot: return max(range, 300)
        case .piercingLine: return max(range, 800)
        case .dashStrike: return max(range, 200) + 100 + r
        case .blinkEmpower: return 350 + 300
        case .groundAoE, .healZone: return max(range, 200) + r
        case .selfAoE, .multiStrike: return r * 1.3
        case .leapSlam: return max(range, 200) + 200 + r * 1.4
        case .teamHeal: return max(1500, range)
        case .targetedBlink: return max(range, 300) + 100
        }
    }

    private var isCentered: Bool {
        [.selfAoE, .multiStrike, .teamHeal, .passive].contains(archetype)
    }

    private var origin: CGPoint {
        isCentered ? CGPoint(x: size.width / 2, y: size.height / 2) : CGPoint(x: size.width * 0.14, y: size.height / 2)
    }

    /// ワールド距離 → 画面距離。
    private var scale: Double {
        let usable = isCentered ? Double(min(size.width, size.height)) * 0.44 : Double(size.width) * 0.78
        return usable / extent
    }

    private func pt(_ dx: Double, _ dy: Double = 0) -> CGPoint {
        CGPoint(x: origin.x + dx * scale, y: origin.y + dy * scale)
    }

    private func ease(_ x: Double) -> Double { 1 - pow(1 - min(max(x, 0), 1), 3) }
    private func seg(_ a: Double, _ b: Double) -> Double { min(max((phase - a) / (b - a), 0), 1) }

    mutating func draw() {
        grid()
        switch archetype {
        case .passive: passive()
        case .cone: cone()
        case .lineSkillshot: skillshot(piercing: false)
        case .piercingLine: skillshot(piercing: true)
        case .dashStrike: dash(leap: false)
        case .leapSlam: dash(leap: true)
        case .blinkEmpower: blink()
        case .groundAoE: groundAoE(heal: false)
        case .healZone: groundAoE(heal: true)
        case .selfAoE: selfAoE()
        case .multiStrike: multiStrike()
        case .teamHeal: teamHeal()
        case .targetedBlink: targetedBlink()
        }
    }

    // 背景グリッドと射程円
    private mutating func grid() {
        let step = 24.0
        var g = Path()
        var x = 0.0
        while x < Double(size.width) { g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: size.height)); x += step }
        var y = 0.0
        while y < Double(size.height) { g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y)); y += step }
        ctx.stroke(g, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
        if archetype != .passive && range > 0 && !isCentered {
            let r = range * scale
            ctx.stroke(Path(ellipseIn: CGRect(x: origin.x - r, y: origin.y - r, width: r * 2, height: r * 2)),
                       with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }

    private mutating func unit(_ p: CGPoint, _ c: Color, hit: Bool = false, size s: Double = 6) {
        let r = hit ? s * 1.35 : s
        if hit {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 2, y: p.y - r * 2, width: r * 4, height: r * 4)), with: .color(c.opacity(0.3)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(c))
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.8)), lineWidth: 1)
        if hit && showsCC && c == enemy {
            // CC を示す回転する星
            for k in 0..<3 {
                let a = time * 5 + Double(k) * 2 * .pi / 3
                let q = CGPoint(x: p.x + cos(a) * r * 1.6, y: p.y - r * 1.8 + sin(a) * r * 0.5)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 1.8, y: q.y - 1.8, width: 3.6, height: 3.6)), with: .color(Theme.gold))
            }
        }
    }

    private mutating func caster(_ p: CGPoint? = nil, alpha: Double = 1) {
        let c = p ?? origin
        let r = 8.0
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.8, y: c.y - r * 1.8, width: r * 3.6, height: r * 3.6)),
                 with: .color(color.opacity(0.18 * alpha)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Theme.cyan.opacity(alpha)))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(alpha)), lineWidth: 1.5)
    }

    private mutating func circle(_ c: CGPoint, _ r: Double, fill: Color, stroke: Color, dash: Bool = false) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(fill))
        ctx.stroke(Path(ellipseIn: rect), with: .color(stroke), style: StrokeStyle(lineWidth: 1.5, dash: dash ? [5, 4] : []))
    }

    private mutating func passive() {
        caster()
        for k in 0..<3 {
            let r = (22 + Double(k) * 14) * (1 + 0.06 * sin(time * 2 + Double(k)))
            var p = Path()
            let start = time * (k % 2 == 0 ? 0.8 : -0.8) + Double(k)
            p.addArc(center: origin, radius: r, startAngle: .radians(start), endAngle: .radians(start + 4.2), clockwise: false)
            ctx.stroke(p, with: .color(color.opacity(0.8 - 0.2 * Double(k))), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        for k in 0..<6 {
            let a = time * 1.2 + Double(k) * .pi / 3
            let q = CGPoint(x: origin.x + cos(a) * 58, y: origin.y + sin(a) * 58)
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - 2.5, y: q.y - 2.5, width: 5, height: 5)), with: .color(.white.opacity(0.8)))
        }
    }

    private mutating func cone() {
        let r = max(range, 200) * scale
        let sweep = ease(seg(0.1, 0.45))
        let fade = 1 - seg(0.7, 1)
        var wedge = Path()
        wedge.move(to: origin)
        wedge.addArc(center: origin, radius: r * sweep, startAngle: .degrees(-45), endAngle: .degrees(45), clockwise: false)
        wedge.closeSubpath()
        ctx.fill(wedge, with: .color(color.opacity(0.35 * fade)))
        ctx.stroke(wedge, with: .color(color.opacity(fade)), lineWidth: 1.5)
        let targets = [pt(max(range, 200) * 0.55, -max(range, 200) * 0.2), pt(max(range, 200) * 0.8, max(range, 200) * 0.25),
                       pt(max(range, 200) * 0.6, max(range, 200) * 0.75)]
        for (i, p) in targets.enumerated() {
            let inside = i < 2
            unit(p, enemy, hit: inside && sweep > 0.95 && fade > 0.1)
        }
        caster()
    }

    private mutating func skillshot(piercing: Bool) {
        let len = (piercing ? max(range, 800) : max(range, 300))
        let width = max(radius, 60) * (piercing ? 1.0 : 0.5) * scale
        let lane = CGRect(x: origin.x, y: origin.y - width / 2, width: len * scale, height: width)
        ctx.fill(Path(lane), with: .color(color.opacity(0.10)))
        ctx.stroke(Path(lane), with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        let enemies = piercing ? [0.35, 0.6, 0.85] : [0.55, 0.85]
        let travel = ease(seg(0.05, 0.75))
        let stopAt = piercing ? 1.0 : enemies[0]
        let head = min(travel, stopAt)
        for (i, e) in enemies.enumerated() {
            let offset = i % 2 == 0 ? 0.0 : width * 0.15
            let p = CGPoint(x: origin.x + len * e * scale, y: origin.y + offset)
            let isHit = head >= e - 0.01 && (piercing || i == 0)
            unit(p, enemy, hit: isHit && phase < 0.95)
        }
        if phase < 0.9 {
            let tip = CGPoint(x: origin.x + len * head * scale, y: origin.y)
            let tail = CGPoint(x: origin.x + len * max(0, head - 0.18) * scale, y: origin.y)
            var p = Path()
            p.move(to: tail)
            p.addLine(to: tip)
            ctx.stroke(p, with: .linearGradient(Gradient(colors: [color.opacity(0), color]), startPoint: tail, endPoint: tip),
                       style: StrokeStyle(lineWidth: max(4, width * 0.6), lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 4, y: tip.y - 4, width: 8, height: 8)), with: .color(.white))
        }
        caster()
    }

    private mutating func dash(leap: Bool) {
        let dist = max(range, 200) + (leap ? 200 : 100)
        let aoe = max(radius, 60) * (leap ? 1.4 : 1.0) * scale
        let landing = pt(dist)
        let move = ease(seg(0.05, 0.45))
        let blast = seg(0.45, 0.8)
        var path = Path()
        path.move(to: origin)
        if leap {
            path.addQuadCurve(to: landing, control: CGPoint(x: (origin.x + landing.x) / 2, y: origin.y - 60))
        } else {
            path.addLine(to: landing)
        }
        ctx.stroke(path, with: .color(color.opacity(0.4)), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        circle(landing, aoe, fill: color.opacity(0.08 + 0.3 * (1 - blast) * (blast > 0 ? 1 : 0)), stroke: color.opacity(0.7), dash: blast == 0)
        if blast > 0 {
            let r = aoe * ease(blast)
            ctx.stroke(Path(ellipseIn: CGRect(x: landing.x - r, y: landing.y - r, width: r * 2, height: r * 2)),
                       with: .color(.white.opacity(1 - blast)), lineWidth: 3)
        }
        unit(CGPoint(x: landing.x + aoe * 0.4, y: landing.y - aoe * 0.3), enemy, hit: blast > 0 && blast < 1)
        unit(CGPoint(x: landing.x - aoe * 0.2, y: landing.y + aoe * 0.5), enemy, hit: blast > 0 && blast < 1)
        // 術者の移動
        let cx = origin.x + (landing.x - origin.x) * move
        let lift = leap ? -60 * 4 * move * (1 - move) : 0
        if leap && move > 0 && move < 1 {
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 8, y: origin.y - 3, width: 16, height: 6)), with: .color(.black.opacity(0.4)))
        }
        caster(CGPoint(x: cx, y: origin.y + lift))
    }

    private mutating func blink() {
        let to = pt(350)
        let appear = seg(0.15, 0.3)
        let strike = seg(0.45, 0.75)
        let target = pt(350 + 220)
        // 残像
        caster(origin, alpha: 1 - appear * 0.8)
        for k in 0..<6 {
            let a = Double(k) * .pi / 3 + time * 3
            let q = CGPoint(x: to.x + cos(a) * 14 * appear, y: to.y + sin(a) * 14 * appear)
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - 2, y: q.y - 2, width: 4, height: 4)), with: .color(color.opacity(appear)))
        }
        if appear > 0 {
            var p = Path()
            p.move(to: origin)
            p.addLine(to: to)
            ctx.stroke(p, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
            caster(to, alpha: appear)
        }
        if strike > 0 && strike < 1 {
            var p = Path()
            p.move(to: to)
            p.addLine(to: CGPoint(x: to.x + (target.x - to.x) * ease(strike), y: to.y))
            ctx.stroke(p, with: .color(Theme.gold), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        unit(target, enemy, hit: strike >= 0.95 && phase < 0.95)
    }

    private mutating func groundAoE(heal: Bool) {
        let center = pt(max(range, 200) * 0.75)
        let r = max(radius, 60) * scale
        let tele = seg(0.05, 0.45)
        let boom = seg(0.45, 0.85)
        let tint = heal ? ally : color
        circle(center, r, fill: tint.opacity(0.06), stroke: tint.opacity(0.6), dash: true)
        if boom == 0 {
            let rr = r * tele
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)), with: .color(tint.opacity(0.22)))
        } else {
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                     with: .color(tint.opacity(0.4 * (1 - boom))))
            let rr = r * (1 + 0.3 * boom)
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)),
                       with: .color(.white.opacity(1 - boom)), lineWidth: 2.5)
        }
        let active = boom > 0 && boom < 1
        unit(CGPoint(x: center.x + r * 0.35, y: center.y - r * 0.3), enemy, hit: active)
        unit(CGPoint(x: center.x + r * 1.5, y: center.y + r * 0.4), enemy)
        if heal {
            let a = CGPoint(x: center.x - r * 0.4, y: center.y + r * 0.35)
            unit(a, ally, hit: active)
            if active {
                for k in 0..<4 {
                    let yy = a.y - 10 - 26 * frac(time * 0.9 + Double(k) * 0.25)
                    plus(CGPoint(x: a.x - 12 + Double(k) * 8, y: yy), alpha: 1 - frac(time * 0.9 + Double(k) * 0.25))
                }
            }
        }
        caster()
    }

    private mutating func selfAoE() {
        let r = max(radius, 60) * scale
        let wave = seg(0.1, 0.5)
        circle(origin, r, fill: color.opacity(0.07), stroke: color.opacity(0.5), dash: true)
        if wave > 0 {
            let rr = r * ease(wave)
            ctx.fill(Path(ellipseIn: CGRect(x: origin.x - rr, y: origin.y - rr, width: rr * 2, height: rr * 2)),
                     with: .color(color.opacity(0.3 * (1 - seg(0.5, 0.9)))))
        }
        unit(CGPoint(x: origin.x + r * 0.6, y: origin.y - r * 0.3), enemy, hit: wave >= 0.6 && phase < 0.9)
        unit(CGPoint(x: origin.x - r * 0.5, y: origin.y + r * 0.45), enemy, hit: wave >= 0.6 && phase < 0.9)
        unit(CGPoint(x: origin.x + r * 1.25, y: origin.y + r * 0.2), enemy)
        caster()
        shield(origin, strength: seg(0.3, 0.5) * (1 - seg(0.85, 1)))
    }

    private mutating func multiStrike() {
        let r = max(radius, 60) * scale
        circle(origin, r, fill: color.opacity(0.07), stroke: color.opacity(0.5), dash: true)
        let targets = [CGPoint(x: origin.x + r * 0.7, y: origin.y - r * 0.2), CGPoint(x: origin.x - r * 0.3, y: origin.y - r * 0.6),
                       CGPoint(x: origin.x + r * 0.1, y: origin.y + r * 0.7)]
        for (i, p) in targets.enumerated() {
            let s = seg(0.1 + Double(i) * 0.2, 0.25 + Double(i) * 0.2)
            let hit = s > 0 && s < 1
            if hit {
                var slash = Path()
                slash.move(to: CGPoint(x: p.x - 12, y: p.y - 12))
                slash.addLine(to: CGPoint(x: p.x + 12, y: p.y + 12))
                ctx.stroke(slash, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                var line = Path()
                line.move(to: origin)
                line.addLine(to: p)
                ctx.stroke(line, with: .color(color.opacity(0.6)), lineWidth: 1.5)
            }
            unit(p, enemy, hit: hit)
        }
        caster()
        shield(origin, strength: seg(0.05, 0.15) * (1 - seg(0.8, 0.95)))
    }

    private mutating func teamHeal() {
        let big = max(1500, range) * scale
        circle(origin, big, fill: ally.opacity(0.05), stroke: ally.opacity(0.45), dash: true)
        let pulse = seg(0.1, 0.6)
        if pulse > 0 && pulse < 1 {
            let rr = big * ease(pulse)
            ctx.stroke(Path(ellipseIn: CGRect(x: origin.x - rr, y: origin.y - rr, width: rr * 2, height: rr * 2)),
                       with: .color(ally.opacity(1 - pulse)), lineWidth: 3)
        }
        let allies = [CGPoint(x: origin.x - big * 0.55, y: origin.y - big * 0.35), CGPoint(x: origin.x + big * 0.45, y: origin.y + big * 0.5),
                      CGPoint(x: origin.x - big * 0.2, y: origin.y + big * 0.7)]
        for a in allies {
            let d = hypot(a.x - origin.x, a.y - origin.y) / big
            let healed = pulse >= d
            unit(a, ally, hit: healed && phase < 0.9)
            if healed && phase < 0.9 { plus(CGPoint(x: a.x, y: a.y - 16), alpha: 1 - seg(0.6, 0.9)) }
        }
        let near = max(radius, 60) * scale * 1.2
        unit(CGPoint(x: origin.x + near, y: origin.y - near * 0.4), enemy, hit: pulse > 0.2 && phase < 0.9)
        caster()
    }

    private mutating func targetedBlink() {
        let target = pt(max(range, 300) * 0.85, -20)
        let jump = seg(0.2, 0.32)
        let execute = seg(0.4, 0.8)
        var link = Path()
        link.move(to: origin)
        link.addLine(to: target)
        ctx.stroke(link, with: .color(enemy.opacity(0.4 * (1 - jump))), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
        // 照準マーク
        let m = 16 * (1 + 0.1 * sin(time * 6))
        ctx.stroke(Path(ellipseIn: CGRect(x: target.x - m, y: target.y - m, width: m * 2, height: m * 2)),
                   with: .color(enemy.opacity(0.8)), lineWidth: 1.5)
        unit(target, enemy, hit: execute > 0 && execute < 1)
        if execute > 0 && execute < 1 {
            for k in 0..<2 {
                var x = Path()
                let o = 14.0
                x.move(to: CGPoint(x: target.x - o, y: target.y + (k == 0 ? -o : o)))
                x.addLine(to: CGPoint(x: target.x + o, y: target.y + (k == 0 ? o : -o)))
                ctx.stroke(x, with: .color(Theme.gold.opacity(1 - execute)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        let pos = jump >= 1 ? CGPoint(x: target.x - 18, y: target.y + 4) : origin
        caster(pos, alpha: jump > 0 && jump < 1 ? 0.3 : 1)
    }

    private mutating func shield(_ c: CGPoint, strength: Double) {
        guard strength > 0 else { return }
        let r = 16.0
        var hex = Path()
        for k in 0..<6 {
            let a = Double(k) * .pi / 3 + time
            let q = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if k == 0 { hex.move(to: q) } else { hex.addLine(to: q) }
        }
        hex.closeSubpath()
        ctx.stroke(hex, with: .color(Theme.gold.opacity(strength)), lineWidth: 2)
    }

    private mutating func plus(_ c: CGPoint, alpha: Double) {
        var p = Path()
        p.move(to: CGPoint(x: c.x - 4, y: c.y))
        p.addLine(to: CGPoint(x: c.x + 4, y: c.y))
        p.move(to: CGPoint(x: c.x, y: c.y - 4))
        p.addLine(to: CGPoint(x: c.x, y: c.y + 4))
        ctx.stroke(p, with: .color(ally.opacity(max(0, alpha))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private func frac(_ v: Double) -> Double { v - floor(v) }
}
