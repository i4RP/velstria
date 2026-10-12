import SwiftUI
import VelstriaCore

// 担当: battle-hud。操作部品: 仮想スティック・攻撃ボタン・スキル/Ult・スペル・帰還・スキル習得「＋」・照準リング。
// 薄い円形の操作部品と、その下の小さなラベル。クールダウンは放射状の幕 + 進捗弧 + 秒数。
// 死亡中は絵柄が見えたまま暗くし、秒数は読めるまま進める。
// ジェスチャーは HUD 全面の座標空間（HUDSpace.name）で受け、HUDLayout の座標と一致させる。

// MARK: - 仮想スティック

struct HUDJoystick: View {
    let model: HUDModel
    let layout: HUDLayout
    let mode: JoystickMode
    let highlighted: Bool

    @State private var active = false
    @State private var base: CGPoint = .zero
    @State private var knob: CGVector = .zero
    /// ジェスチャーが取り消された（onEnded が呼ばれない）場合も確実に止めるため。
    @GestureState private var touching = false

    var body: some View {
        let r = layout.joystickRadius
        let zone = mode == .floating ? layout.joystickZone : layout.fixedJoystickZone
        let center = active ? base : layout.joystickRest
        // 死亡中は操作できないので薄く
        let dead = model.hero.isDead
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .frame(width: zone.width, height: zone.height)
                .position(x: zone.midX, y: zone.midY)
                .gesture(drag(zone: zone))
                .hudAccessibility(id: "hud_joystick", label: L("移動スティック", "Movement stick"),
                                  value: L("ドラッグで移動", "Drag to move")) {}
            ZStack {
                Circle()
                    .fill(HUDStyle.accent.opacity(active ? 0.17 : 0.10))
                Circle()
                    .strokeBorder(HUDStyle.accent.opacity(active ? 0.65 : 0.27), lineWidth: 0.8)
                ForEach(0..<4, id: \.self) { k in
                    Image(systemName: "chevron.right")
                        .font(.system(size: r * 0.14, weight: .semibold))
                        .foregroundStyle(HUDStyle.accent.opacity(active ? 0.65 : 0.35))
                        .offset(x: r * 0.78)
                        .rotationEffect(.degrees(Double(k) * 90))
                }
                Circle()
                    .fill(HUDStyle.accent.opacity(active ? 0.30 : 0.17))
                    .overlay(Circle().strokeBorder(HUDStyle.accent.opacity(active ? 0.85 : 0.58), lineWidth: 1.5))
                    .overlay {
                        Image(systemName: "sparkle")
                            .font(.system(size: layout.joystickKnob * 0.4, weight: .medium))
                            .foregroundStyle(HUDStyle.accent.opacity(0.9))
                    }
                    .frame(width: layout.joystickKnob, height: layout.joystickKnob)
                    .shadow(color: HUDStyle.accent.opacity(active ? 0.18 : 0), radius: 3)
                    .offset(x: knob.dx, y: knob.dy)
            }
            .frame(width: r * 2, height: r * 2)
            .opacity(dead ? HUDDeadStyle.stickOpacity : 1)
            .animation(.easeInOut(duration: 0.3), value: dead)
            .position(center)
            .allowsHitTesting(false)
            if highlighted {
                HUDHighlightRing(diameter: r * 2 + 16).position(layout.joystickRest)
            }
        }
        .onChange(of: touching) { _, now in
            guard !now, active else { return }
            active = false
            knob = .zero
            model.joystickEnded()
        }
    }

    private func drag(zone: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(HUDSpace.name))
            .updating($touching) { _, state, _ in state = true }
            .onChanged { v in
                let r = layout.joystickRadius
                if !active {
                    active = true
                    if mode == .floating {
                        base = floatingBase(v.startLocation, in: zone, radius: r)
                    } else {
                        base = layout.joystickRest
                    }
                }
                var d = CGVector(dx: v.location.x - base.x, dy: v.location.y - base.y)
                let len = (d.dx * d.dx + d.dy * d.dy).squareRoot()
                if mode == .floating && len > r * 1.35 {
                    // 指が大きく離れたら土台を引き寄せる
                    let pull = (len - r * 1.35) / len
                    base = floatingBase(CGPoint(x: base.x + d.dx * pull, y: base.y + d.dy * pull), in: zone, radius: r)
                    d = CGVector(dx: v.location.x - base.x, dy: v.location.y - base.y)
                }
                let clamped = HUDJoystickMath.clamp(d, radius: r)
                // 入力の半径・移動量は維持し、描画だけをリングの内側へ収める。
                let visualTravel = max(0, r - layout.joystickKnob / 2 - 1) / r
                knob = CGVector(dx: clamped.dx * visualTravel, dy: clamped.dy * visualTravel)
                model.joystickChanged(clamped, radius: r)
            }
            .onEnded { _ in
                active = false
                withAnimation(.spring(duration: 0.2)) { knob = .zero }
                model.joystickEnded()
            }
    }

    /// 可動式でも実際の入力中心と表示中心を一致させ、ノッチ・下端・他の操作領域へ侵入しない。
    private func floatingBase(_ point: CGPoint, in zone: CGRect, radius: CGFloat) -> CGPoint {
        let left = max(zone.minX, layout.leadingEdge) + radius
        let right = max(left, min(zone.maxX, layout.trailingEdge) - radius)
        let top = max(zone.minY, layout.topEdge) + radius
        let bottom = max(top, min(zone.maxY, layout.bottomEdge) - radius)
        return CGPoint(x: min(max(point.x, left), right), y: min(max(point.y, top), bottom))
    }
}

// MARK: - 攻撃ボタン

struct HUDAttackButton: View {
    let model: HUDModel
    let slot: AttackButtonSlot
    let diameter: CGFloat
    /// 死亡中は絵柄を暗くする（押しても何も起きない）。
    var dead = false
    let highlighted: Bool
    @State private var pressed = false
    @GestureState private var touching = false

    var body: some View {
        let priority = model.settings.attackPriority(for: slot)
        let main = slot == .center
        ZStack {
            if main {
                HUDCrystalShape().fill(LinearGradient(colors: [HUDStyle.accent.opacity(0.6), HUDStyle.crystalDeep.opacity(0.5), HUDStyle.surface.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(HUDCrystalShape().stroke(HUDStyle.accent, lineWidth: 1.2))
                HUDCrystalFacet().fill(HUDStyle.crystalLight.opacity(0.25))
            } else {
                Circle().fill(HUDStyle.surface.opacity(0.24))
                    .overlay(Circle().strokeBorder(HUDStyle.accent.opacity(0.4), lineWidth: 0.7))
            }
            HUDAttackGlyph(icon: HUDAttackIcon.main(slot: slot, priority: priority),
                           size: diameter * (main ? 0.69 : 0.46),
                           color: main ? .white : HUDStyle.accent)
                .foregroundStyle(HUDStyle.accent.opacity(0.9))
                .shadow(color: HUDStyle.accent.opacity(main ? 0.28 : 0.12), radius: 2)
            if let badge = HUDAttackIcon.badge(slot: slot, priority: priority) {
                Image(systemName: badge)
                    .font(.system(size: diameter * 0.11, weight: .semibold))
                    .foregroundStyle(HUDStyle.accent.opacity(0.9))
                    .frame(width: diameter * 0.2, height: diameter * 0.2)
                    .background(Circle().fill(HUDStyle.surface.opacity(0.72)))
                    .overlay(Circle().strokeBorder(HUDStyle.accent.opacity(0.45), lineWidth: 0.6))
                    .offset(x: diameter * 0.3, y: diameter * 0.3)
                    .accessibilityHidden(true)
            }
            if pressed { Circle().fill(HUDStyle.accent.opacity(0.17)) }
        }
        .frame(width: diameter, height: diameter)
        .hudDeadDim(dead)
        .scaleEffect(pressed ? 0.96 : 1)
        .shadow(color: HUDStyle.accent.opacity(dead ? 0 : (pressed ? 0.24 : 0.08)), radius: 3)
        .animation(.spring(duration: 0.15), value: pressed)
        .overlay { if highlighted { HUDHighlightRing(diameter: diameter + 16) } }
        .frame(width: max(44, diameter), height: max(44, diameter))
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($touching) { _, state, _ in state = true }
                .onChanged { _ in
                    if !pressed {
                        pressed = true
                        model.attackPressed(button: slot)
                    }
                }
                .onEnded { _ in
                    pressed = false
                    model.attackReleased(button: slot)
                }
        )
        .onChange(of: touching) { _, now in
            guard !now, pressed else { return }
            pressed = false
            model.attackReleased(button: slot)
        }
        .onDisappear {
            pressed = false
            model.attackReleased(button: slot)
        }
        .hudAccessibility(id: slot == .center ? "hud_attack" : "hud_attack_\(slot.rawValue)",
                          label: "\(SettingsText.attackButtonSlot(slot)): \(SettingsText.attackPriority(model.settings.attackPriority(for: slot)))",
                          value: SettingsText.attackPriorityDetail(model.settings.attackPriority(for: slot))
                            + " " + L("長押しで攻撃を続ける", "Hold to keep attacking")) {
            model.attackPressed(button: slot)
            model.attackReleased(button: slot)
        }
    }
}

/// 攻撃ボタンの絵柄の種類。中央は剣、上下は優先対象（タワーは専用の形、それ以外は SF Symbols）。
enum HUDAttackIcon: Equatable {
    case swords
    case tower
    case symbol(String)

    /// ボタンの主な絵柄。中央は優先対象に関わらず剣（優先対象は badge で示す）。
    static func main(slot: AttackButtonSlot, priority: TargetPriority) -> HUDAttackIcon {
        if slot == .center { return .swords }
        return priority == .structuresFirst ? .tower : .symbol(SettingsText.attackPrioritySymbol(priority))
    }

    /// 中央ボタンの優先対象が既定以外の時だけ出す、小さな記号（SF Symbols の名前）。
    static func badge(slot: AttackButtonSlot, priority: TargetPriority) -> String? {
        guard slot == .center, priority != GameSettings().attackPriority else { return nil }
        return SettingsText.attackPrioritySymbol(priority)
    }
}

/// 攻撃ボタンの絵柄を size 四方に描く。シンボルの色は呼び出し側の foregroundStyle、形（剣・タワー）は color。
struct HUDAttackGlyph: View {
    let icon: HUDAttackIcon
    let size: CGFloat
    var color: Color = HUDStyle.surface

    var body: some View {
        ZStack {
            switch icon {
            case .swords:
                HUDCrossedSwords()
                    .fill(color)
                    .frame(width: size, height: size)
            case .tower:
                HUDTowerShape()
                    .fill(color, style: FillStyle(eoFill: true))
                    .frame(width: size * 0.92, height: size * 0.92)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.88, weight: .bold))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 防御タワー（胸壁・塔身・土台。扉と窓は偶奇塗りで抜く: 各部分は重ならずに隣り合う）。
struct HUDTowerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func r(_ x: CGFloat, _ y: CGFloat, _ cw: CGFloat, _ ch: CGFloat) -> CGRect {
            CGRect(x: rect.minX + w * x, y: rect.minY + h * y, width: w * cw, height: h * ch)
        }
        var p = Path()
        // 胸壁（3 つ）
        for x in [CGFloat(0.16), 0.41, 0.66] { p.addRect(r(x, 0.06, 0.18, 0.18)) }
        // 張り出し
        p.addRect(r(0.16, 0.24, 0.68, 0.12))
        // 塔身（下へ少し広がる）
        p.move(to: CGPoint(x: rect.minX + w * 0.24, y: rect.minY + h * 0.36))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.76, y: rect.minY + h * 0.36))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.82, y: rect.minY + h * 0.90))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.18, y: rect.minY + h * 0.90))
        p.closeSubpath()
        // 土台
        p.addRect(r(0.10, 0.90, 0.80, 0.08))
        // 窓と扉（塔身の内側 = 偶奇塗りで抜ける）
        p.addRect(r(0.46, 0.46, 0.08, 0.14))
        p.addRect(r(0.42, 0.66, 0.16, 0.24))
        return p
    }
}

/// 交差した 2 本の剣（攻撃ボタンのアイコン）。
struct HUDCrossedSwords: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        func blade(_ flip: Bool) -> Path {
            var b = Path()
            // 刃（先端が上）
            b.move(to: CGPoint(x: w * 0.5, y: 0))
            b.addLine(to: CGPoint(x: w * 0.56, y: h * 0.10))
            b.addLine(to: CGPoint(x: w * 0.56, y: h * 0.66))
            b.addLine(to: CGPoint(x: w * 0.44, y: h * 0.66))
            b.addLine(to: CGPoint(x: w * 0.44, y: h * 0.10))
            b.closeSubpath()
            // 鍔
            b.addRoundedRect(in: CGRect(x: w * 0.32, y: h * 0.66, width: w * 0.36, height: h * 0.07),
                             cornerSize: CGSize(width: w * 0.03, height: w * 0.03))
            // 柄
            b.addRect(CGRect(x: w * 0.465, y: h * 0.73, width: w * 0.07, height: h * 0.17))
            b.addEllipse(in: CGRect(x: w * 0.44, y: h * 0.89, width: w * 0.12, height: w * 0.12))
            let angle: CGFloat = flip ? -.pi / 4 : .pi / 4
            let t = CGAffineTransform(translationX: w / 2, y: h / 2).rotated(by: angle).translatedBy(x: -w / 2, y: -h / 2)
            return b.applying(t)
        }
        p.addPath(blade(false))
        p.addPath(blade(true))
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// 通常攻撃ボタンのクリスタルの枠（斜めに傾けた、角を落としたひし形）。
struct HUDCrystalShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + w * x, y: rect.minY + h * y) }
        var path = Path()
        path.move(to: p(0.56, 0.02))
        path.addLine(to: p(0.86, 0.22))
        path.addLine(to: p(0.98, 0.52))
        path.addLine(to: p(0.74, 0.92))
        path.addLine(to: p(0.42, 0.98))
        path.addLine(to: p(0.12, 0.76))
        path.addLine(to: p(0.02, 0.44))
        path.addLine(to: p(0.26, 0.08))
        path.closeSubpath()
        return path
    }
}

/// クリスタルの左上の面（光の反射）。
struct HUDCrystalFacet: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + w * x, y: rect.minY + h * y) }
        var path = Path()
        path.move(to: p(0.26, 0.08))
        path.addLine(to: p(0.56, 0.02))
        path.addLine(to: p(0.50, 0.30))
        path.addLine(to: p(0.10, 0.48))
        path.addLine(to: p(0.02, 0.44))
        path.closeSubpath()
        return path
    }
}

// MARK: - スキル・スペル

/// 死亡中の操作部品の見た目（参考画面: 絵柄は見えたまま暗く、クールダウンの秒数は読める）。
enum HUDDeadStyle {
    static let saturation: Double = 0.3
    static let brightness: Double = -0.17
    static let opacity: Double = 0.88
    /// 操作できないスティックは薄く。
    static let stickOpacity: Double = 0.45
}

extension View {
    /// 死亡中の操作部品: 絵柄は見えたまま、彩度と明度を落として少し透かす（重ねる秒数・ラベルには掛けない）。
    func hudDeadDim(_ dead: Bool) -> some View {
        self
            .saturation(dead ? HUDDeadStyle.saturation : 1)
            .brightness(dead ? HUDDeadStyle.brightness : 0)
            .opacity(dead ? HUDDeadStyle.opacity : 1)
    }
}

/// スキルとバトルスペルの共通ベース。色は役割、輪郭は使用状態を表す。
struct HUDAbilityFace: View {
    let color: Color
    let diameter: CGFloat
    var ultimate = false

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.27).opacity(0.88), HUDStyle.surface.opacity(0.78)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Circle()
                    .fill(LinearGradient(colors: [color.opacity(0.20), .clear],
                                         startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                Circle().strokeBorder(color.opacity(0.65), lineWidth: 0.8)
            }
            .overlay {
                Circle().trim(from: 0.54, to: 0.85)
                    .stroke(Color.white.opacity(0.38), lineWidth: 0.8)
                    .padding(2)
            }
    }
}

/// 外周の短い目盛り（MLBB のスキルボタンの縁）。
struct HUDTickRing: Shape {
    let count: Int
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for k in 0..<max(1, count) {
            let a = CGFloat(k) / CGFloat(max(1, count)) * 2 * .pi
            let dx = cos(a), dy = sin(a)
            p.move(to: CGPoint(x: c.x + dx * r, y: c.y + dy * r))
            p.addLine(to: CGPoint(x: c.x + dx * (r - length), y: c.y + dy * (r - length)))
        }
        return p
    }
}

/// クールダウンの進捗弧（細いシアンの縁で経過を示す）。
struct HUDCooldownArc: View {
    /// 残り時間の割合（1 = 使った直後、0 = 使用可能）。
    let fraction: Double
    let diameter: CGFloat

    static func lineWidth(_ diameter: CGFloat) -> CGFloat { max(1, diameter * 0.022) }

    var body: some View {
        let w = Self.lineWidth(diameter)
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.5), lineWidth: w)
            Circle()
                .trim(from: 0, to: min(1, max(0, 1 - fraction)))
                .stroke(HUDStyle.accent.opacity(0.8), style: StrokeStyle(lineWidth: w, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1.0 / 15.0), value: fraction)
        }
        .padding(w / 2)
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// クールダウン中の表示: 絵柄が透ける放射状の幕 + 細い進捗弧 + 残り秒数。
struct HUDCooldownOverlay: View {
    let cooldown: Double
    let fraction: Double
    let diameter: CGFloat
    /// 秒数の文字サイズ（ボタン直径に対する割合）。
    var fontRatio: CGFloat = 0.32
    /// 秒数の縦位置（ボタン内に名前がある時は絵柄の位置に合わせて上へ）。
    var numberOffset: CGFloat = 0

    /// 絵柄を暗くする幕の濃さ。
    static let shade: Double = 0.54

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.18))
            HUDCooldownPie(fraction: fraction)
                .fill(Color.black.opacity(Self.shade))
                .animation(.linear(duration: 1.0 / 15.0), value: fraction)
            HUDCooldownArc(fraction: fraction, diameter: diameter)
            Text(HUDStyle.cooldown(cooldown))
                .font(.system(size: diameter * fontRatio, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: .black, radius: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .offset(y: numberOffset)
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// クールダウンの扇形（上から時計回りに残り時間の割合。観戦のヒーロー詳細で使う）。
struct HUDCooldownPie: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard fraction > 0.001 else { return p }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        p.move(to: c)
        p.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * min(1, fraction)),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct HUDSkillButton: View {
    let model: HUDModel
    let snapshot: HUDSkillSnapshot
    let role: Role
    let diameter: CGFloat
    let center: CGPoint
    let name: String
    /// ボタン下の種別タグ（VoiceOver ではヒントとして読む）。
    var tag = ""
    /// 死亡中は絵柄だけを暗くし、クールダウンの秒数は読めるまま進める。
    var dead = false
    let highlighted: Bool
    @GestureState private var touching = false

    var body: some View {
        let isUlt = snapshot.slot == .ultimate
        let color = isUlt ? HUDStyle.violet : HUDStyle.accent
        let dim = !snapshot.isReady
        // 再使用の窓が開いている間は CD・コストを見ない（秒数の幕を出さず、窓の輪を出す）
        let cooling = snapshot.cooldown > 0 && !snapshot.recasting
        ZStack {
            // 絵柄（使えない時・死亡中はこの層だけを暗くし、上に重ねる秒数とバッジは読めるままにする）
            ZStack {
                HUDAbilityFace(color: color, diameter: diameter, ultimate: isUlt)
                Image(systemName: HUDSymbols.skill(snapshot.archetype))
                    .font(.system(size: diameter * 0.40, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [Color.white.opacity(0.95), HUDStyle.violet.opacity(0.85)],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: color.opacity(0.2), radius: 2)
                // クールダウン中は HUDCooldownOverlay が暗くする（二重に暗くしない）
                if dim && !cooling && !dead {
                    Circle().fill(HUDStyle.surface.opacity(snapshot.learned ? 0.48 : 0.57))
                }
            }
            .saturation(dim && !cooling && !dead ? 0.35 : 1)
            .hudDeadDim(dead)
            .padding(diameter * 0.09)
            if cooling {
                HUDCooldownOverlay(cooldown: snapshot.cooldown, fraction: snapshot.cooldownFraction, diameter: diameter * 0.82,
                                   fontRatio: 0.34)
            } else if snapshot.learned && !snapshot.affordable && !snapshot.recasting {
                Image(systemName: "drop.fill")
                    .font(.system(size: diameter * 0.2, weight: .bold))
                    .foregroundStyle(HUDStyle.resourceColor(model.vitals.resourceKind))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(diameter * 0.12)
            } else if !snapshot.learned && !snapshot.canLevel {
                Image(systemName: "lock.fill")
                    .font(.system(size: diameter * 0.22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            } else if snapshot.silenced {
                Image(systemName: "nosign")
                    .font(.system(size: diameter * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
            if let info = snapshot.recast {
                HUDRecastRing(info: info, diameter: diameter * 0.82, color: HUDStyle.accent)
            }
            if snapshot.isReady && isUlt && !snapshot.recasting {
                Circle().strokeBorder(HUDStyle.violet.opacity(0.45), lineWidth: 0.8).padding(2)
            }
            HUDRankPips(rank: snapshot.rank, maxRank: snapshot.slot.maxRank, diameter: diameter, color: HUDStyle.accent)
            Text(String(snapshot.slot.rawValue))
                .font(.system(size: diameter * Self.badgeFontRatio, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: diameter * Self.badgeDiameterRatio, height: diameter * Self.badgeDiameterRatio)
                .background(Circle().fill(HUDStyle.surface))
                .overlay(Circle().stroke(HUDStyle.accent, lineWidth: 1.2))
                .offset(x: diameter * Self.badgeOffsetRatio, y: diameter * Self.badgeOffsetRatio)
                .allowsHitTesting(false)
            // キット層のバッジ（スタック・形態・タイマー）。右上の角（枠番号・種別タグ・習得バッジと重ならない位置）
            if let badge = snapshot.badge {
                HUDKitBadgeChip(badge: badge, size: diameter * 0.3, tint: color)
                    .offset(x: diameter * 0.34, y: -diameter * 0.34)
                    .opacity(dead ? 0.8 : 1)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: snapshot.isReady ? color.opacity(snapshot.recasting ? 0.25 : 0.1) : .clear, radius: 2)
        .scaleEffect(touching ? 0.95 : 1)
        .animation(.easeOut(duration: 0.12), value: touching)
        .overlay { if highlighted { HUDHighlightRing(diameter: diameter + 16) } }
        .frame(width: max(44, diameter), height: max(44, diameter))
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(HUDSpace.name))
                .updating($touching) { _, state, _ in state = true }
                .onChanged { v in
                    model.abilityDragChanged(.skill(snapshot.slot), start: v.startLocation, location: v.location,
                                             buttonCenter: center)
                }
                .onEnded { v in model.abilityDragEnded(.skill(snapshot.slot), location: v.location) }
        )
        .onChange(of: touching) { _, now in
            if !now { model.abilityDragCancelled(.skill(snapshot.slot)) }
        }
        .hudAccessibility(id: Self.identifier(snapshot.slot), label: "\(CollectionStyle.slotName(snapshot.slot)) \(name)",
                          value: accessibilityValue) {
            model.abilityDragChanged(.skill(snapshot.slot), start: center, location: center, buttonCenter: center)
            model.abilityDragEnded(.skill(snapshot.slot), location: center)
        }
        .accessibilityHint(tag)
    }

    /// 固定番号バッジ。右下へ重ね、ボタンの矩形内に収める。
    static let badgeFontRatio: CGFloat = 0.23
    static let badgeOffsetRatio: CGFloat = 0.32
    static let badgeDiameterRatio: CGFloat = 0.32

    private var accessibilityValue: String {
        if !snapshot.learned { return L("未習得", "Not learned") }
        var parts = [L("ランク \(snapshot.rank)", "Rank \(snapshot.rank)")]
        if snapshot.recasting && snapshot.isReady { parts.append(L("再使用できます", "Recast available")) }
        else if snapshot.cooldown > 0 { parts.append(L("残り \(HUDStyle.cooldown(snapshot.cooldown)) 秒", "\(HUDStyle.cooldown(snapshot.cooldown)) seconds left")) }
        else if snapshot.silenced { parts.append(L("沈黙中", "Silenced")) }
        else if !snapshot.affordable { parts.append(L("リソース不足", "Not enough resource")) }
        else if snapshot.isReady { parts.append(L("使用可能", "Ready")) }
        else { parts.append(L("使用できません", "Unavailable")) }
        return parts.joined(separator: "、")
    }

    static func identifier(_ slot: SkillSlot) -> String {
        switch slot {
        case .skill1: return "hud_skill1"
        case .skill2: return "hud_skill2"
        case .ultimate, .passive: return "hud_ult"
        }
    }
}

/// 再使用の窓（キット層）: ボタンの縁を回る残り時間の輪と光。窓が閉じるまで輪が減っていく。
struct HUDRecastRing: View {
    let info: RecastInfo
    let diameter: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            Circle().strokeBorder(color.opacity(0.3), lineWidth: 1)
            Circle()
                .trim(from: 0, to: info.fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(0.75)
        }
        .shadow(color: color.opacity(0.3), radius: 2)
        .frame(width: diameter, height: diameter)
        .animation(.linear(duration: 1.0 / 15.0), value: info.remaining)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// スキルボタンの小さなバッジ（キット層。スタックの数・形態・タイマーの残り秒を輪と数字で示す）。
struct HUDKitBadgeChip: View, Equatable {
    let badge: KitBadge
    let size: CGFloat
    let tint: Color

    var body: some View {
        let text = HUDKitDisplay.text(badge)
        ZStack {
            Circle().fill(HUDStyle.surface.opacity(0.9))
            Circle().stroke(tint.opacity(0.35), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: HUDKitDisplay.fraction(badge))
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if text.isEmpty {
                // 個数を持たない状態（準備できた・形態）は点だけ
                Circle().fill(tint).frame(width: size * 0.34, height: size * 0.34)
            } else {
                Text(text)
                    .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 右下の番号用の隙間を除き、時計回りに1区画1段階を表示する。
struct HUDRankPips: View {
    let rank: Int
    let maxRank: Int
    let diameter: CGFloat
    let color: Color
    @State private var flashingFrom = Int.max
    var body: some View {
        ZStack {
            ForEach(0..<max(0, maxRank), id: \.self) { k in
                let step = 300.0 / Double(max(1, maxRank))
                let start = 75.0 + Double(k) * step
                HUDRankSegment(start: start + 2, end: start + step - 2)
                    .fill(k < rank ? color : Color(red: 0.10, green: 0.24, blue: 0.36))
                    .overlay(HUDRankSegment(start: start + 2, end: start + step - 2)
                        .stroke(HUDStyle.crystalLight.opacity(k < rank ? 0.85 : 0.42), lineWidth: 0.65))
                    .brightness(k >= flashingFrom && k < rank ? 0.4 : 0)
            }
        }
        .frame(width: diameter, height: diameter)
        .onChange(of: rank) { old, new in
            if new > old { flashingFrom = old }
        }
        .task(id: rank) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { flashingFrom = Int.max }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct HUDRankSegment: Shape {
    let start: Double
    let end: Double
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) * 0.49
        var p = Path()
        p.addArc(center: c, radius: r, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        p.addArc(center: c, radius: r * 0.86, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        p.closeSubpath()
        return p
    }
}

struct HUDSpellButton: View {
    let model: HUDModel
    let snapshot: HUDSpellSnapshot
    let diameter: CGFloat
    let center: CGPoint
    var dead = false
    @GestureState private var touching = false

    var body: some View {
        let info = SpellInfo.of(snapshot.spellID)
        let ready = snapshot.castable && snapshot.cooldown <= 0
        let name = HUDSkillTag.spellLabel(snapshot.spellID)
        ZStack {
            // 名前を絵柄の下へ逃がし、円の中は操作と状態だけに使う。
            ZStack {
                HUDAbilityFace(color: info.color, diameter: diameter)
                if let art = PortraitArt.spell(snapshot.spellID) {
                    Image(uiImage: art)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: diameter - 3, height: diameter - 3)
                        .clipShape(Circle())
                } else {
                    Circle().fill(info.color.opacity(0.12)).padding(3)
                    Image(systemName: info.symbol)
                        .font(.system(size: diameter * 0.43, weight: .medium))
                        .foregroundStyle(LinearGradient(colors: [.white, info.color],
                                                        startPoint: .top, endPoint: .bottom))
                        .shadow(color: info.color.opacity(0.35), radius: 2)
                }
                if !ready && snapshot.cooldown <= 0 && !dead {
                    Circle().fill(Color.black.opacity(0.45))
                }
            }
            .hudDeadDim(dead)
            if snapshot.cooldown > 0 {
                HUDCooldownOverlay(cooldown: snapshot.cooldown, fraction: snapshot.cooldownFraction, diameter: diameter,
                                   fontRatio: 0.3)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay {
            HUDSpellLabel(text: name, diameter: diameter)
                .offset(y: HUDSpellLabel.labelCenterOffset(diameter))
                .allowsHitTesting(false)
        }
        .shadow(color: ready ? info.color.opacity(0.1) : .clear, radius: 2)
        .scaleEffect(touching ? 0.95 : 1)
        .animation(.easeOut(duration: 0.12), value: touching)
        .frame(width: max(44, diameter), height: max(44, diameter))
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(HUDSpace.name))
                .updating($touching) { _, state, _ in state = true }
                .onChanged { v in
                    model.abilityDragChanged(.spell(snapshot.index), start: v.startLocation, location: v.location,
                                             buttonCenter: center)
                }
                .onEnded { v in model.abilityDragEnded(.spell(snapshot.index), location: v.location) }
        )
        .onChange(of: touching) { _, now in
            if !now { model.abilityDragCancelled(.spell(snapshot.index)) }
        }
        .hudAccessibility(id: "hud_spell\(snapshot.index + 1)",
                          label: MasterData.shared.spell(snapshot.spellID).map { MasterText.spell($0) } ?? snapshot.spellID,
                          value: snapshot.cooldown > 0 ? L("残り \(HUDStyle.cooldown(snapshot.cooldown)) 秒", "\(HUDStyle.cooldown(snapshot.cooldown)) seconds left")
                                                       : (ready ? L("使用可能", "Ready") : L("使用できません", "Unavailable"))) {
            model.abilityDragChanged(.spell(snapshot.index), start: center, location: center, buttonCenter: center)
            model.abilityDragEnded(.spell(snapshot.index), location: center)
        }
    }
}

/// 補助操作の名前。ボタン中心を動かさず、その真下に小さく添える。
struct HUDSpellLabel: View {
    let text: String
    let diameter: CGFloat

    /// 帰還ボタンの「帰還」と同じ大きさ。
    static let fontRatio: CGFloat = 0.20
    /// 隣の補助ボタンに触れない範囲で、名前は円より少し広く使う。
    static let maxWidthRatio: CGFloat = 1.35

    static func fontSize(_ d: CGFloat) -> CGFloat { max(8, d * fontRatio) }
    static func font(_ d: CGFloat) -> Font { .system(size: fontSize(d), weight: .medium) }
    static func labelCenterOffset(_ d: CGFloat) -> CGFloat { d / 2 + 2 + fontSize(d) * 0.6 }

    var body: some View {
        Text(text)
            .font(Self.font(diameter))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.9), radius: 1, y: 0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: diameter * Self.maxWidthRatio)
            .accessibilityHidden(true)
    }
}

struct HUDRecallButton: View {
    let model: HUDModel
    let diameter: CGFloat
    let channel: HUDChannel?
    var dead = false
    let highlighted: Bool

    var body: some View {
        Button { model.recall() } label: {
            ZStack {
                ZStack {
                    HUDAbilityFace(color: HUDStyle.accent, diameter: diameter)
                    Ellipse()
                        .stroke(HUDStyle.accent.opacity(0.9), lineWidth: 1.2)
                        .frame(width: diameter * 0.56, height: diameter * 0.20)
                        .offset(y: diameter * 0.22)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(LinearGradient(colors: [.white, HUDStyle.accent.opacity(0.12)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: diameter * 0.11, height: diameter * 0.57)
                        .offset(y: -diameter * 0.02)
                    Image(systemName: "sparkle")
                        .font(.system(size: diameter * 0.34, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                        .offset(y: -diameter * 0.08)
                }
                .hudDeadDim(dead)
                if let ch = channel, ch.kind == .recall, ch.total > 0 {
                    Circle()
                        .trim(from: 0, to: 1 - ch.remaining / ch.total)
                        .stroke(HUDStyle.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                        .animation(.linear(duration: 1.0 / 15.0), value: ch.remaining)
                }
            }
            .frame(width: diameter, height: diameter)
            .overlay {
                HUDSpellLabel(text: L("帰還", "Recall"), diameter: diameter)
                    .offset(y: HUDSpellLabel.labelCenterOffset(diameter))
                    .allowsHitTesting(false)
            }
            .frame(width: max(44, diameter), height: max(44, diameter))
            .contentShape(Circle())
        }
        .buttonStyle(HUDPressStyle())
        .overlay { if highlighted { HUDHighlightRing(diameter: diameter + 14) } }
        .accessibilityLabel(L("帰還", "Recall"))
        .accessibilityIdentifier("hud_recall")
    }
}

struct HUDLevelBadge: View {
    static let touchDiameter: CGFloat = 44
    let model: HUDModel
    let slot: SkillSlot
    let diameter: CGFloat
    let highlighted: Bool

    var body: some View {
        Button { model.levelSkill(slot) } label: {
            ZStack {
                Circle()
                    .fill(HUDStyle.surface.opacity(0.65))
                    .overlay(Circle().strokeBorder(Theme.gold.opacity(0.75), lineWidth: 0.8))
                    .frame(width: diameter, height: diameter)
                Image(systemName: "plus")
                    .font(.system(size: diameter * 0.52, weight: .semibold))
                    .foregroundStyle(Theme.gold)
            }
            .frame(width: Self.touchDiameter, height: Self.touchDiameter)
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .overlay { if highlighted { HUDHighlightRing(diameter: diameter + 16) } }
        .accessibilityLabel(L("\(CollectionStyle.slotName(slot)) を習得", "Level up \(CollectionStyle.slotName(slot))"))
        .accessibilityIdentifier(Self.identifier(slot))
        .transition(.scale.combined(with: .opacity))
    }

    static func identifier(_ slot: SkillSlot) -> String {
        switch slot {
        case .skill1: return "hud_level_skill1"
        case .skill2: return "hud_level_skill2"
        case .ultimate, .passive: return "hud_level_ult"
        }
    }
}

// MARK: - ボタン下のラベル（スキルの種別タグ）とスペル名

/// スキルボタンの短い種別タグ（参考画面の「範囲技」「妨害」「加速」）。
/// 挙動はアーキタイプ（スロット × 近接/遠隔 × ロールで決まる。SkillCatalog.targeting）で、CC はマスターの値で判断する
/// （effectID・エフェクト種別はスロット毎の演出の区別でしかないため使わない）。
/// 優先順位: 回復 > 移動（突進・跳躍・移動技・処刑）> 防御・連撃 > 妨害（スタン・拘束・ノックバック）> 減速 > 形（範囲技・直線技・貫通）。
/// 使い道が変わる効果（味方を回復する・自分が動く・身を守る）を CC より先に示し、CC の無い攻撃技だけを形で示す。
/// 今のアーキタイプに移動速度を上げるスキルは無いため「加速」は使わない（加速陣などのスペルは名前で示す）。
/// 必殺技もボタン上の「必殺」バッジ（枠）とは別に、同じ流儀で種別を示す。
enum HUDSkillTag: String, CaseIterable {
    case heal
    case dash
    case leap
    case blink
    case execute
    case guardSelf
    case flurry
    case control
    case slow
    case area
    case line
    case pierce
    case passive

    static func tag(for skill: SkillDef?, archetype: SkillArchetype) -> HUDSkillTag {
        switch archetype {
        case .passive: return .passive
        case .healZone, .teamHeal: return .heal
        case .dashStrike: return .dash
        case .leapSlam: return .leap
        case .blinkEmpower: return .blink
        // 失った HP に応じた追加ダメージ（とどめ用）
        case .targetedBlink: return .execute
        // 自身にシールド
        case .selfAoE: return .guardSelf
        // 連続攻撃 + 被ダメージ軽減
        case .multiStrike: return .flurry
        case .cone, .lineSkillshot, .piercingLine, .groundAoE:
            switch skill?.cc ?? .none {
            case .stun, .root, .knockback: return .control
            case .slow: return .slow
            case .none:
                switch archetype {
                case .lineSkillshot: return .line
                case .piercingLine: return .pierce
                default: return .area
                }
            }
        }
    }

    static func label(for skill: SkillDef?, archetype: SkillArchetype) -> String {
        tag(for: skill, archetype: archetype).label
    }

    var label: String {
        switch self {
        case .heal: return L("回復", "Heal")
        case .dash: return L("突進", "Dash")
        case .leap: return L("跳躍", "Leap")
        // 英語はスペル「Blink」（瞬歩）と紛らわしいので Mobility
        case .blink: return L("移動技", "Mobility")
        case .execute: return L("処刑", "Execute")
        case .guardSelf: return L("防御", "Guard")
        case .flurry: return L("連撃", "Flurry")
        case .control: return L("妨害", "Control")
        case .slow: return L("減速", "Slow")
        case .area: return L("範囲技", "AoE")
        case .line: return L("直線技", "Line")
        case .pierce: return L("貫通", "Pierce")
        case .passive: return L("パッシブ", "Passive")
        }
    }

    /// ラベルの最大文字数（日本語 / 英語）。スペル名もこれに収める。
    static let maxLengthJa = 4
    static let maxLengthEn = 8

    /// スペルボタン内の名前（長ければ短縮: 英語は先頭の語 "Healing Wave" → "Healing"、それでも長ければ切り詰め）。
    static func spellLabel(_ spellID: String) -> String {
        let name = MasterData.shared.spell(spellID).map { MasterText.spell($0) } ?? spellID
        return shortened(name, maxLength: Loc.isEnglish ? maxLengthEn : maxLengthJa)
    }

    static func shortened(_ name: String, maxLength: Int) -> String {
        guard name.count > maxLength else { return name }
        if let first = name.split(separator: " ").first, first.count >= 3, first.count <= maxLength {
            return String(first)
        }
        return String(name.prefix(max(1, maxLength - 1))) + "…"
    }
}

/// スキルボタンの種別ラベル。背景カードを作らず、文字の影で地面から分離する。
struct HUDControlLabel: View, Equatable {
    let text: String
    let fontSize: CGFloat
    /// 縁取りの色（役割の色。必殺技は金）。
    let tint: Color

    var body: some View {
        let size = Self.estimatedSize(text, fontSize: fontSize)
        Text(text)
            .font(Self.font(fontSize))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .shadow(color: .black.opacity(0.85), radius: 0.8, y: 0.5)
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    static func font(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }

    /// 左右の余白（カプセルの内側）。
    static let horizontalPadding: CGFloat = 3

    /// 文字の幅の見積もり（全角 1em・英大文字 0.8em・その他の半角 0.66em + 影の分）。実際の描画幅以上になる（テストで確認）。
    static func estimatedTextWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        var em: CGFloat = 0
        for ch in text {
            if !ch.isASCII { em += 1 } else if ch.isUppercase { em += 0.8 } else { em += 0.66 }
        }
        return ceil(em * fontSize) + 2
    }

    /// カプセルの大きさ（描画もこの大きさで行うので、配置と重なりテストの矩形と一致する）。
    static func estimatedSize(_ text: String, fontSize: CGFloat) -> CGSize {
        CGSize(width: estimatedTextWidth(text, fontSize: fontSize) + horizontalPadding * 2, height: ceil(fontSize * 1.3))
    }
}

extension HUDLayout {
    /// 種別タグの文字サイズ。
    var controlLabelFontSize: CGFloat { max(8, 8 * scale) }

    /// 習得バッジ（「＋」）の描画半径に 2pt の余白を足した範囲。
    var levelBadgeReach: CGFloat { levelBadgeDiameter / 2 + 2 }

    /// 扇形に並べた各スキルの真下へ添える。
    func skillLabelCenter(_ slot: SkillSlot, size: CGSize) -> CGPoint {
        let c = skillCenter(slot)
        let r = (slot == .ultimate ? ultDiameter : skillDiameter) / 2
        return CGPoint(x: c.x, y: c.y + r + 2 + size.height / 2)
    }
}

// MARK: - 右側クラスタ

struct HUDActionCluster: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let hero = model.hero
        // 死亡中も部品は暗くするだけ（全体の不透明度は下げない）。クールダウンは進み、秒数は読める
        let dead = hero.isDead
        let skills = model.skills
        let highlight = model.tutorial?.highlight
        let attackHighlight: AttackButtonSlot = model.tutorial?.step == .destroyTower
            ? AttackButtonSlot.allCases.first(where: { model.settings.attackPriority(for: $0) == .structuresFirst }) ?? .center
            : .center
        let master = MasterData.shared
        let fs = layout.controlLabelFontSize
        ZStack {
            ForEach(AttackButtonSlot.allCases) { slot in
                HUDAttackButton(model: model, slot: slot, diameter: layout.attackDiameter(for: slot), dead: dead,
                                highlighted: highlight == .attack && slot == attackHighlight)
                    .position(layout.attackCenter(for: slot))
            }
            ForEach(skills) { sn in
                let d = sn.slot == .ultimate ? layout.ultDiameter : layout.skillDiameter
                let c = layout.skillCenter(sn.slot)
                let def = master.skill(sn.skillID)
                let tag = HUDSkillTag.label(for: def, archetype: sn.archetype)
                HUDSkillButton(model: model, snapshot: sn, role: hero.role, diameter: d, center: c,
                               name: def.map { MasterText.skill($0) } ?? "", tag: tag, dead: dead,
                               highlighted: highlight == .skill1 && sn.slot == .skill1)
                    .position(c)
                HUDControlLabel(text: tag, fontSize: fs, tint: sn.slot == .ultimate ? Theme.gold : Theme.roleColor(hero.role))
                    .position(layout.skillLabelCenter(sn.slot, size: HUDControlLabel.estimatedSize(tag, fontSize: fs)))
            }
            ForEach(model.spells) { sp in
                let c = layout.spellCenter(sp.index)
                HUDSpellButton(model: model, snapshot: sp, diameter: layout.spellDiameter, center: c, dead: dead)
                    .position(c)
            }
            HUDItemActiveButtons(model: model, layout: layout, dead: dead)
            HUDRecallButton(model: model, diameter: layout.recallDiameter, channel: hero.channel, dead: dead,
                            highlighted: highlight == .recall)
                .position(layout.recallCenter)
            ForEach(skills.filter(\.canLevel)) { sn in
                HUDLevelBadge(model: model, slot: sn.slot, diameter: layout.levelBadgeDiameter,
                              highlighted: highlight == .levelSkill1 && sn.slot == .skill1)
                    .position(layout.levelBadgeCenter(sn.slot))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: dead)
        .animation(.spring(duration: 0.3), value: skills.map(\.canLevel))
    }
}

// MARK: - スキルの説明（長押し）

extension HUDLayout {
    /// 説明カードと他の部品の間に空ける余白。
    static let skillTipGap: CGFloat = 6

    var skillTipMaxWidth: CGFloat { 280 * scale }
    /// 文字は 11pt 未満にしない（背景はほぼ不透明な紺）。
    var skillTipBodyFontSize: CGFloat { max(11, 11 * scale) }
    var skillTipTitleFontSize: CGFloat { max(13, 13 * scale) }
    var skillTipPadding: CGSize { CGSize(width: 9 * scale, height: 7 * scale) }
    var skillTipSpacing: CGFloat { 3 * scale }

    /// 説明カードの枠（カードはこの枠の上端に寄せて描く。内容が短ければ下は空く）。
    /// 右下のクラスタ（攻撃・スキル・スペル・習得バッジ）とその上のシグナル列・クイックチャットのメニューの内側、
    /// ミニマップ横の縦列の外側の、上部の帯（スコア・味方列）の下からヒーローパネル・降参投票の欄の上までの空きに収める:
    ///   x: 右手配置  [縦列の右端 + 6, 帯にかかる操作部品の左端 − 6]（左利きは左右反転）。幅は skillTipMaxWidth まで、クラスタ側に寄せる
    ///   y: [max(スコア, 味方列の下端) + 6, min(ヒーローパネルの上端, 降参投票の上端) − 6]
    /// 帯にかかる操作部品 = 攻撃ボタン・スキル・スペル・帰還の円と習得バッジのタップ領域、クイックチャットのメニュー。
    /// キルフィード（同じ空きに出る）だけは、カードを出している間は隠す（HUDKillFeedRule）。
    var skillTipFrame: CGRect {
        let gap = Self.skillTipGap
        let top = max(scoreFrame.maxY, allyStripFrame.maxY) + gap
        let bottom = min(bottomEdge - HUDRootMetrics.heroPanelHeight(self) - gap,
                         HUDSurrenderMetrics.frame(self).minY - gap)
        var obstacles = signalControlDiscs.map {
            CGRect(x: $0.center.x - $0.radius, y: $0.center.y - $0.radius, width: $0.radius * 2, height: $0.radius * 2)
        }
        obstacles += signalLevelBadgeRects
        obstacles.append(signalChatMenuFrame)
        let band = obstacles.filter { $0.maxY > top && $0.minY < bottom }
        let minX: CGFloat, maxX: CGFloat
        if leftHanded {
            minX = (band.map(\.maxX).max() ?? leadingEdge) + gap
            maxX = utilityColumnFrame.minX - gap
        } else {
            minX = utilityColumnFrame.maxX + gap
            maxX = (band.map(\.minX).min() ?? trailingEdge) - gap
        }
        let width = min(skillTipMaxWidth, max(0, maxX - minX))
        return CGRect(x: leftHanded ? minX : maxX - width, y: top, width: width, height: max(0, bottom - top))
    }

    /// 説明文の行数の上限（枠の高さに収まる行数。行の高さは文字サイズの 1.3 倍で見積もる）。
    var skillTipBodyLineLimit: Int {
        let usable = skillTipFrame.height - skillTipPadding.height * 2 - skillTipTitleFontSize * 1.3 - skillTipSpacing
        return max(3, Int((usable / (skillTipBodyFontSize * 1.3)).rounded(.down)))
    }
}

/// キルフィードを隠す条件（照準中・長押しの説明を出している間・観戦の情報パネルを開いている間・中央の告知に譲る間）。
enum HUDKillFeedRule {
    static func isHidden(aiming: Bool, tipShown: Bool, covered: Bool, yieldsToCenter: Bool) -> Bool {
        aiming || tipShown || covered || yieldsToCenter
    }
}

/// 押している間だけ出る、スキルの説明（ほぼ不透明な紺の地。タップは奪わない）。
/// 配置は HUDLayout.skillTipFrame、重ねる順は BattleHUDView の HUDSkillTipLayer（操作部品・シグナルより上）。
struct HUDSkillTipCard: View {
    let tip: HUDSkillTip
    let role: Role
    let layout: HUDLayout

    var body: some View {
        let tint = tip.slot == .ultimate ? Theme.gold : Theme.roleColor(role)
        let corner = 10 * layout.scale
        let pad = layout.skillTipPadding
        VStack(alignment: .leading, spacing: layout.skillTipSpacing) {
            Text(tip.name)
                .font(.system(size: layout.skillTipTitleFontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(tip.text)
                .font(.system(size: layout.skillTipBodyFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(layout.skillTipBodyLineLimit)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, pad.width)
        .padding(.vertical, pad.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(HUDStyle.surface.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(tint.opacity(0.75), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 照準リングとキャンセル領域

struct HUDAimOverlay: View {
    let visual: HUDAimVisual
    let layout: HUDLayout

    var body: some View {
        if visual.active {
            ZStack {
                // キャンセル領域
                ZStack {
                    Circle()
                        .fill(visual.cancelling ? Theme.danger.opacity(0.85) : Color.black.opacity(0.55))
                    Circle()
                        .strokeBorder(visual.cancelling ? Color.white : Theme.danger.opacity(0.9), lineWidth: 2)
                    VStack(spacing: 1) {
                        Image(systemName: "xmark")
                            .font(.system(size: layout.cancelRadius * 0.55, weight: .heavy))
                        Text(L("キャンセル", "Cancel"))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: layout.cancelRadius * 2, height: layout.cancelRadius * 2)
                .scaleEffect(visual.cancelling ? 1.12 : 1)
                .animation(.spring(duration: 0.2), value: visual.cancelling)
                .position(layout.cancelCenter)
                // 照準リング
                let ring = visual.maxDrag * 2
                let tint = visual.cancelling ? Theme.danger : (visual.isUltimate ? Theme.gold : Theme.cyan)
                Circle()
                    .fill(tint.opacity(0.10))
                    .overlay(Circle().strokeBorder(tint.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    .frame(width: ring, height: ring)
                    .position(visual.center)
                Circle()
                    .fill(RadialGradient(colors: [.white, tint.opacity(0.9)], center: .center, startRadius: 1, endRadius: 18))
                    .frame(width: 30, height: 30)
                    .shadow(color: tint, radius: 8)
                    .position(x: visual.center.x + visual.drag.dx, y: visual.center.y + visual.drag.dy)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}
