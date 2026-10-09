import SwiftUI
import VelstriaCore

// 担当: battle-hud。操作部品: 仮想スティック・攻撃ボタン・スキル/Ult・スペル・帰還・スキル習得「＋」・照準リング。
// スキルの種別タグ（ボタンの下、下が詰まる内側の列は画面中央側）、スペル名（帰還・攻撃と同じくボタン内の絵柄の下）、
// クールダウンは暗くした絵柄 + 金色の進捗弧 + 秒数。死亡中は絵柄が見えたまま暗くし、秒数は読めるまま進める。
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
                    .fill(RadialGradient(colors: [HUDStyle.surface.opacity(0.1), HUDStyle.surface.opacity(0.64)],
                                         center: .center, startRadius: r * 0.2, endRadius: r))
                Circle()
                    .strokeBorder(active ? HUDStyle.accent.opacity(0.8) : Color.white.opacity(0.3), lineWidth: 2)
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    .padding(r * 0.2)
                ForEach(0..<4, id: \.self) { k in
                    Image(systemName: "chevron.right")
                        .font(.system(size: r * 0.2, weight: .heavy))
                        .foregroundStyle(.white.opacity(active ? 0.55 : 0.3))
                        .offset(x: r * 0.78)
                        .rotationEffect(.degrees(Double(k) * 90))
                }
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.96), HUDStyle.accent.opacity(0.78)],
                                         center: .init(x: 0.4, y: 0.35), startRadius: 1, endRadius: layout.joystickKnob * 0.6))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                    .overlay {
                        Circle().strokeBorder(HUDStyle.surface.opacity(0.2), lineWidth: 1)
                            .padding(layout.joystickKnob * 0.16)
                    }
                    .frame(width: layout.joystickKnob, height: layout.joystickKnob)
                    .shadow(color: HUDStyle.accent.opacity(active ? 0.45 : 0.1), radius: active ? 8 : 3)
                    .offset(x: knob.dx, y: knob.dy)
            }
            .frame(width: r * 2, height: r * 2)
            .opacity((active ? 1 : (mode == .floating ? 0.58 : 0.82)) * (dead ? HUDDeadStyle.stickOpacity : 1))
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
                        // 画面端でもスティック全体が収まるように
                        let x = min(max(v.startLocation.x, zone.minX + r * 0.8), zone.maxX - r * 0.8)
                        let y = min(max(v.startLocation.y, zone.minY + r * 0.8), layout.height - r * 0.8)
                        base = CGPoint(x: x, y: y)
                    } else {
                        base = layout.joystickRest
                    }
                }
                var d = CGVector(dx: v.location.x - base.x, dy: v.location.y - base.y)
                let len = (d.dx * d.dx + d.dy * d.dy).squareRoot()
                if mode == .floating && len > r * 1.35 {
                    // 指が大きく離れたら土台を引き寄せる
                    let pull = (len - r * 1.35) / len
                    base = CGPoint(x: base.x + d.dx * pull, y: base.y + d.dy * pull)
                    d = CGVector(dx: v.location.x - base.x, dy: v.location.y - base.y)
                }
                let clamped = HUDJoystickMath.clamp(d, radius: r)
                knob = clamped
                model.joystickChanged(clamped, radius: r)
            }
            .onEnded { _ in
                active = false
                withAnimation(.spring(duration: 0.2)) { knob = .zero }
                model.joystickEnded()
            }
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
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.89, blue: 0.51), Color(red: 0.94, green: 0.61, blue: 0.18)],
                                     center: .init(x: 0.4, y: 0.3), startRadius: 2, endRadius: diameter * 0.6))
            Circle()
                .strokeBorder(HUDStyle.surface.opacity(0.85), lineWidth: diameter * 0.065)
            Circle()
                .strokeBorder(Color.white.opacity(0.86), lineWidth: 2)
                .padding(diameter * 0.065)
            VStack(spacing: 1) {
                Image(systemName: SettingsText.attackPrioritySymbol(model.settings.attackPriority(for: slot)))
                    .font(.system(size: diameter * 0.38, weight: .bold))
                    .frame(width: diameter * 0.43, height: diameter * 0.43)
                if slot == .center {
                    Text(L("攻撃", "ATTACK"))
                        .font(.system(size: diameter * 0.1, weight: .black, design: .rounded))
                }
            }
            .foregroundStyle(HUDStyle.surface)
        }
        .frame(width: diameter, height: diameter)
        .hudDeadDim(dead)
        .scaleEffect(pressed ? 0.92 : 1)
        .shadow(color: Theme.gold.opacity(dead ? 0 : (pressed ? 0.6 : 0.18)), radius: pressed ? 12 : 5)
        .animation(.spring(duration: 0.15), value: pressed)
        .overlay { if highlighted { HUDHighlightRing(diameter: diameter + 16) } }
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
            .fill(LinearGradient(colors: [color.opacity(0.76), HUDStyle.surface],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Circle()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.16), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(diameter * 0.1)
            }
            .overlay {
                Circle().strokeBorder(ultimate ? Theme.gold : color.opacity(0.9), lineWidth: ultimate ? 3 : 2)
            }
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8).padding(4)
            }
    }
}

/// クールダウンの進捗弧（ボタンの縁に沿って、上から時計回りに経過した分を金色で描く）。
struct HUDCooldownArc: View {
    /// 残り時間の割合（1 = 使った直後、0 = 使用可能）。
    let fraction: Double
    let diameter: CGFloat

    static func lineWidth(_ diameter: CGFloat) -> CGFloat { max(2.5, diameter * 0.065) }

    var body: some View {
        let w = Self.lineWidth(diameter)
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.5), lineWidth: w)
            Circle()
                .trim(from: 0, to: min(1, max(0, 1 - fraction)))
                .stroke(LinearGradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.66), Theme.gold,
                                                Color(red: 0.86, green: 0.58, blue: 0.16)],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: w, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.gold.opacity(0.55), radius: 2.5)
                .animation(.linear(duration: 1.0 / 15.0), value: fraction)
        }
        .padding(w / 2)
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// クールダウン中の表示: 暗くした絵柄 + 金色の進捗弧 + 残り秒数。
struct HUDCooldownOverlay: View {
    let cooldown: Double
    let fraction: Double
    let diameter: CGFloat
    /// 秒数の文字サイズ（ボタン直径に対する割合）。
    var fontRatio: CGFloat = 0.32
    /// 秒数の縦位置（ボタン内に名前がある時は絵柄の位置に合わせて上へ）。
    var numberOffset: CGFloat = 0

    /// 絵柄を暗くする幕の濃さ。
    static let shade: Double = 0.42

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(Self.shade))
            HUDCooldownArc(fraction: fraction, diameter: diameter)
            Text(HUDStyle.cooldown(cooldown))
                .font(.system(size: diameter * fontRatio, weight: .black, design: .rounded))
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
        let color = isUlt ? HUDStyle.violet : Theme.roleColor(role)
        let dim = !snapshot.isReady
        // 再使用の窓が開いている間は CD・コストを見ない（秒数の幕を出さず、窓の輪を出す）
        let cooling = snapshot.cooldown > 0 && !snapshot.recasting
        ZStack {
            // 絵柄（使えない時・死亡中はこの層だけを暗くし、上に重ねる秒数とバッジは読めるままにする）
            ZStack {
                HUDAbilityFace(color: color, diameter: diameter, ultimate: isUlt)
                Image(systemName: HUDSymbols.skill(snapshot.archetype))
                    .font(.system(size: diameter * 0.37, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(y: snapshot.isReady && isUlt ? -diameter * 0.05 : 0)
                // クールダウン中は HUDCooldownOverlay が暗くする（二重に暗くしない）
                if dim && !cooling && !dead {
                    Circle().fill(HUDStyle.surface.opacity(snapshot.learned ? 0.46 : 0.72))
                }
            }
            .saturation(dim && !cooling && !dead ? 0.35 : 1)
            .hudDeadDim(dead)
            if cooling {
                HUDCooldownOverlay(cooldown: snapshot.cooldown, fraction: snapshot.cooldownFraction, diameter: diameter,
                                   fontRatio: 0.34)
            } else if snapshot.learned && !snapshot.affordable && !snapshot.recasting {
                Image(systemName: "drop.fill")
                    .font(.system(size: diameter * 0.2, weight: .bold))
                    .foregroundStyle(HUDStyle.resourceColor(model.vitals.resourceKind))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(diameter * 0.12)
            } else if !snapshot.learned {
                Image(systemName: "lock.fill")
                    .font(.system(size: diameter * 0.22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            } else if snapshot.silenced {
                Image(systemName: "nosign")
                    .font(.system(size: diameter * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(isUlt ? L("必殺", "ULT") : CollectionStyle.slotBadge(snapshot.slot))
                .font(.system(size: diameter * 0.13, weight: .black, design: .rounded))
                .foregroundStyle(isUlt ? HUDStyle.surface : .white)
                .padding(.horizontal, diameter * 0.09)
                .padding(.vertical, 2)
                .background(Capsule().fill(isUlt ? Theme.gold : HUDStyle.surface))
                .overlay(Capsule().strokeBorder(isUlt ? Color.white.opacity(0.6) : color.opacity(0.7), lineWidth: 0.8))
                .opacity(dead ? 0.85 : 1)
                .offset(y: -diameter * 0.36)
            if let info = snapshot.recast {
                HUDRecastRing(info: info, diameter: diameter, color: isUlt ? Theme.gold : Theme.cyan)
            }
            if snapshot.isReady && isUlt && !snapshot.recasting {
                Text(L("使用可能", "READY"))
                    .font(.system(size: diameter * 0.105, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.gold)
                    .offset(y: diameter * 0.27)
                Circle().strokeBorder(Theme.gold.opacity(0.45), lineWidth: 1).padding(-3)
            }
            HUDRankPips(rank: snapshot.rank, maxRank: snapshot.slot.maxRank, diameter: diameter, color: isUlt ? Theme.gold : HUDStyle.accent)
                .opacity(dead ? 0.8 : 1)
            // キット層のバッジ（スタック・形態・タイマー）。右上の角（枠番号・種別タグ・習得バッジと重ならない位置）
            if let badge = snapshot.badge {
                HUDKitBadgeChip(badge: badge, size: diameter * 0.3, tint: isUlt ? Theme.gold : Theme.cyan)
                    .offset(x: diameter * 0.34, y: -diameter * 0.34)
                    .opacity(dead ? 0.8 : 1)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: snapshot.isReady ? (isUlt ? Theme.gold : color).opacity(snapshot.recasting ? 0.6 : 0.3) : .clear,
                radius: isUlt ? 7 : 4)
        .scaleEffect(touching ? 0.95 : 1)
        .animation(.easeOut(duration: 0.12), value: touching)
        .overlay { if highlighted { HUDHighlightRing(diameter: diameter + 16) } }
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
            Circle().strokeBorder(color.opacity(0.3), lineWidth: 2)
            Circle()
                .trim(from: 0, to: info.fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(1.75)
        }
        .shadow(color: color.opacity(0.85), radius: 6)
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

/// ランクの目盛り（ボタン下側の弧）。
struct HUDRankPips: View {
    let rank: Int
    let maxRank: Int
    let diameter: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            ForEach(0..<maxRank, id: \.self) { k in
                let spread = 13.0
                let angle = 90 + (Double(k) - Double(maxRank - 1) / 2) * spread
                Capsule()
                    .fill(k < rank ? color : Color.black.opacity(0.6))
                    .overlay(Capsule().stroke(Color.white.opacity(k < rank ? 0.8 : 0.35), lineWidth: 0.5))
                    .frame(width: diameter * 0.12, height: diameter * 0.06)
                    .rotationEffect(.degrees(angle - 90))
                    .offset(x: CGFloat(cos(angle * .pi / 180)) * diameter * 0.45,
                            y: CGFloat(sin(angle * .pi / 180)) * diameter * 0.45)
            }
        }
        .allowsHitTesting(false)
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
            // 絵柄 + 名前（帰還・攻撃ボタンと同じく、ボタン内の絵柄の下に短い名前）
            ZStack {
                HUDAbilityFace(color: info.color, diameter: diameter)
                VStack(spacing: HUDSpellLabel.spacing(diameter)) {
                    Image(systemName: info.symbol)
                        .font(.system(size: diameter * HUDSpellLabel.iconRatio, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: info.color, radius: 3)
                        .frame(height: diameter * HUDSpellLabel.iconRatio * 1.1)
                    HUDSpellLabel(text: name, diameter: diameter)
                }
                .offset(y: HUDSpellLabel.stackOffset(diameter))
                if !ready && snapshot.cooldown <= 0 && !dead {
                    Circle().fill(Color.black.opacity(0.45))
                }
            }
            .hudDeadDim(dead)
            if snapshot.cooldown > 0 {
                HUDCooldownOverlay(cooldown: snapshot.cooldown, fraction: snapshot.cooldownFraction, diameter: diameter,
                                   fontRatio: 0.3, numberOffset: HUDSpellLabel.iconCenterOffset(diameter))
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: ready ? info.color.opacity(0.2) : .clear, radius: 4)
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

/// スペルボタン内の名前（帰還の「帰還」と同じ流儀: 絵柄の下に太い丸文字）。
struct HUDSpellLabel: View {
    let text: String
    let diameter: CGFloat

    static let iconRatio: CGFloat = 0.34
    /// 帰還ボタンの「帰還」と同じ大きさ。
    static let fontRatio: CGFloat = 0.15
    /// 名前の最大幅（ボタン直径に対する割合）。名前の段の高さでの円の幅に収まる。
    static let maxWidthRatio: CGFloat = 0.76

    static func spacing(_ d: CGFloat) -> CGFloat { max(0.5, d * 0.01) }
    static func fontSize(_ d: CGFloat) -> CGFloat { d * fontRatio }
    static func font(_ d: CGFloat) -> Font { .system(size: fontSize(d), weight: .black, design: .rounded) }
    /// 絵柄 + 名前の段の高さ（文字の行の高さは文字サイズの 1.2 倍で見積もる）。
    static func stackHeight(_ d: CGFloat) -> CGFloat { d * iconRatio * 1.1 + spacing(d) + fontSize(d) * 1.2 }
    /// 段全体を少し上へ（名前がランクの目盛りの無いボタンの下側に収まるように中央に置く）。
    static func stackOffset(_ d: CGFloat) -> CGFloat { -d * 0.02 }
    /// 絵柄の中心（ボタン中心からの縦位置）。クールダウンの秒数をここに重ねる。
    static func iconCenterOffset(_ d: CGFloat) -> CGFloat {
        stackOffset(d) - stackHeight(d) / 2 + d * iconRatio * 1.1 / 2
    }

    var body: some View {
        Text(text)
            .font(Self.font(diameter))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.9), radius: 1, y: 0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: diameter * Self.maxWidthRatio)
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
                    Circle()
                        .fill(LinearGradient(colors: [HUDStyle.glassTop, HUDStyle.glassBottom],
                                             startPoint: .top, endPoint: .bottom))
                    VStack(spacing: 1) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: diameter * 0.37, weight: .bold))
                        Text(L("帰還", "BASE"))
                            .font(.system(size: diameter * 0.15, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(HUDStyle.accent)
                    Circle().strokeBorder(HUDStyle.rim, lineWidth: 1.5)
                }
                .hudDeadDim(dead)
                if let ch = channel, ch.kind == .recall, ch.total > 0 {
                    Circle()
                        .trim(from: 0, to: 1 - ch.remaining / ch.total)
                        .stroke(HUDStyle.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                        .animation(.linear(duration: 1.0 / 15.0), value: ch.remaining)
                }
            }
            .frame(width: diameter, height: diameter)
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
    @State private var bob = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { model.levelSkill(slot) } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.gold, Color(red: 0.85, green: 0.55, blue: 0.15)], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5))
                    .frame(width: diameter, height: diameter)
                    .shadow(color: Theme.gold.opacity(0.9), radius: 6)
                Image(systemName: "plus")
                    .font(.system(size: diameter * 0.52, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.8))
            }
            .offset(y: bob ? -2 : 2)
            .frame(width: Self.touchDiameter, height: Self.touchDiameter)
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .overlay { if highlighted { HUDHighlightRing(diameter: diameter + 16) } }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { bob = true }
        }
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

/// スキルボタンの種別タグ（「必殺」・枠番号のバッジと同じ流儀の小さなカプセル。タップを奪わない）。
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
            .background(Capsule().fill(HUDStyle.surface.opacity(0.8)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.65), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    static func font(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }

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
    var controlLabelFontSize: CGFloat { 9 * scale }

    /// 習得バッジ（「＋」）が描かれる範囲の半径（上下 2pt の揺れを含む）。
    var levelBadgeReach: CGFloat { levelBadgeDiameter / 2 + 2 }

    /// スキルの種別タグの中心。下に隙間のあるスキル1・2 はボタンの真下（ランクの目盛りの外）。
    /// 攻撃列の内側の列（必殺技）は真下が詰まっている（必殺技 → スキル2 約 12pt）ため、
    /// 画面中央側（右手配置は左、左利きは右）の、周りの習得バッジ・スペルの間の高さへ置く。
    func skillLabelCenter(_ slot: SkillSlot, size: CGSize) -> CGPoint {
        let c = skillCenter(slot)
        let r = (slot == .ultimate ? ultDiameter : skillDiameter) / 2
        switch slot {
        case .ultimate:
            // 必殺技の習得バッジの下端とスキル2 の習得バッジの上端の中間
            let y = (levelBadgeCenter(.ultimate).y + levelBadgeReach + levelBadgeCenter(.skill2).y - levelBadgeReach) / 2
            return innerSideLabelCenter(c, radius: r, y: y, size: size)
        case .skill1, .skill2, .passive:
            return CGPoint(x: c.x, y: c.y + r + 1 + size.height / 2)
        }
    }

    /// ボタンの画面中央側で、ラベルの縦の範囲でのボタンの縁から 2.5pt 離れた位置。
    private func innerSideLabelCenter(_ c: CGPoint, radius r: CGFloat, y: CGFloat, size: CGSize) -> CGPoint {
        let top = y - size.height / 2, bottom = y + size.height / 2
        let dy = (top...bottom).contains(c.y) ? 0 : min(abs(top - c.y), abs(bottom - c.y))
        let halfChord = (max(0, r * r - dy * dy)).squareRoot()
        let dx = halfChord + 2.5 + size.width / 2
        return CGPoint(x: c.x + (leftHanded ? dx : -dx), y: y)
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
            if let tip = model.skillTip {
                HUDSkillTipCard(tip: tip, role: hero.role, layout: layout)
                    .position(layout.skillTipCenter)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: dead)
        .animation(.spring(duration: 0.3), value: skills.map(\.canLevel))
        .animation(.easeOut(duration: 0.15), value: model.skillTip)
    }
}

// MARK: - スキルの説明（長押し）

extension HUDLayout {
    var skillTipWidth: CGFloat { 250 * scale }

    /// 説明カードの中心。操作する指に隠れないよう、スキル列の上（画面の端寄り）へ置く。
    var skillTipCenter: CGPoint {
        let x = leftHanded ? leadingEdge + skillTipWidth / 2 : trailingEdge - skillTipWidth / 2
        return CGPoint(x: x, y: attackCenter.y - 150 * scale)
    }
}

/// 押している間だけ出る、少し透けたスキルの説明（試合の邪魔にならないよう、タップは奪わない）。
struct HUDSkillTipCard: View {
    let tip: HUDSkillTip
    let role: Role
    let layout: HUDLayout

    var body: some View {
        let tint = tip.slot == .ultimate ? Theme.gold : Theme.roleColor(role)
        let corner = 10 * layout.scale
        VStack(alignment: .leading, spacing: 3 * layout.scale) {
            Text(tip.name)
                .font(.system(size: 12 * layout.scale, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
            Text(tip.text)
                .font(.system(size: 10.5 * layout.scale, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .shadow(color: .black.opacity(0.8), radius: 1, y: 0.5)
        .padding(.horizontal, 9 * layout.scale)
        .padding(.vertical, 7 * layout.scale)
        .frame(width: layout.skillTipWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: corner).fill(HUDStyle.surface.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(tint.opacity(0.45), lineWidth: 0.8))
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
