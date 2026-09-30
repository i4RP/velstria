import SwiftUI
import VelstriaCore

// 担当: battle-hud。操作部品: 仮想スティック・攻撃ボタン・スキル/Ult・スペル・帰還・スキル習得「＋」・照準リング。
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

    var body: some View {
        let r = layout.joystickRadius
        let zone = mode == .floating ? layout.joystickZone
            : CGRect(x: layout.joystickRest.x - r * 1.5, y: layout.joystickRest.y - r * 1.5, width: r * 3, height: r * 3)
        let center = active ? base : layout.joystickRest
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
                    .fill(RadialGradient(colors: [Color.black.opacity(0.10), Color.black.opacity(0.42)],
                                         center: .center, startRadius: r * 0.2, endRadius: r))
                Circle()
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                ForEach(0..<4, id: \.self) { k in
                    Image(systemName: "chevron.right")
                        .font(.system(size: r * 0.2, weight: .heavy))
                        .foregroundStyle(.white.opacity(active ? 0.55 : 0.3))
                        .offset(x: r * 0.78)
                        .rotationEffect(.degrees(Double(k) * 90))
                }
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.95), Color(red: 0.62, green: 0.74, blue: 1.0).opacity(0.85)],
                                         center: .init(x: 0.4, y: 0.35), startRadius: 1, endRadius: layout.joystickKnob * 0.6))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                    .frame(width: layout.joystickKnob, height: layout.joystickKnob)
                    .shadow(color: Theme.cyan.opacity(active ? 0.7 : 0.2), radius: active ? 10 : 4)
                    .offset(x: knob.dx, y: knob.dy)
            }
            .frame(width: r * 2, height: r * 2)
            .opacity(active ? 1 : (mode == .floating ? 0.55 : 0.8))
            .position(center)
            .allowsHitTesting(false)
            if highlighted {
                HUDHighlightRing(diameter: r * 2 + 16).position(layout.joystickRest)
            }
        }
    }

    private func drag(zone: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(HUDSpace.name))
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
    let diameter: CGFloat
    let highlighted: Bool
    @State private var pressed = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.36, green: 0.30, blue: 0.22), Color(red: 0.10, green: 0.08, blue: 0.10)],
                                     center: .init(x: 0.4, y: 0.3), startRadius: 2, endRadius: diameter * 0.6))
            Circle()
                .strokeBorder(AngularGradient(colors: [Theme.gold, .white.opacity(0.9), Theme.gold.opacity(0.5), Theme.gold],
                                              center: .center), lineWidth: diameter * 0.06)
            Circle()
                .strokeBorder(Color.black.opacity(0.45), lineWidth: 1)
                .padding(diameter * 0.07)
            HUDCrossedSwords()
                .fill(LinearGradient(colors: [.white, Theme.gold], startPoint: .top, endPoint: .bottom))
                .frame(width: diameter * 0.5, height: diameter * 0.5)
                .shadow(color: Theme.gold.opacity(0.8), radius: pressed ? 8 : 3)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(pressed ? 0.92 : 1)
        .shadow(color: Theme.gold.opacity(pressed ? 0.6 : 0.25), radius: pressed ? 14 : 6)
        .animation(.spring(duration: 0.15), value: pressed)
        .overlay { if highlighted { HUDHighlightRing(diameter: diameter + 16) } }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        pressed = true
                        model.attackPressed()
                    }
                }
                .onEnded { _ in
                    pressed = false
                    model.attackReleased()
                }
        )
        .hudAccessibility(id: "hud_attack", label: L("通常攻撃", "Attack"),
                          value: L("長押しで攻撃を続ける", "Hold to keep attacking")) {
            model.attackPressed()
            model.attackReleased()
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

/// クールダウンの扇形（上から時計回りに残り時間の割合）。
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
    let highlighted: Bool

    var body: some View {
        let color = Theme.roleColor(role)
        let isUlt = snapshot.slot == .ultimate
        let dim = !snapshot.isReady
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.95), color.opacity(0.45), Color.black.opacity(0.85)],
                                     center: .init(x: 0.38, y: 0.3), startRadius: 1, endRadius: diameter * 0.62))
            Image(systemName: HUDSymbols.skill(snapshot.archetype))
                .font(.system(size: diameter * 0.40, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: color, radius: 4)
            Text(CollectionStyle.slotBadge(snapshot.slot))
                .font(.system(size: diameter * 0.17, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(diameter * 0.15)
            if dim {
                Circle().fill(Color.black.opacity(snapshot.learned ? 0.42 : 0.62))
            }
            if snapshot.cooldown > 0 {
                HUDCooldownPie(fraction: snapshot.cooldownFraction)
                    .fill(Color.black.opacity(0.55))
                    .animation(.linear(duration: 1.0 / 15.0), value: snapshot.cooldownFraction)
                Text(HUDStyle.cooldown(snapshot.cooldown))
                    .font(.system(size: diameter * 0.30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
            } else if snapshot.learned && !snapshot.affordable {
                Image(systemName: "drop.fill")
                    .font(.system(size: diameter * 0.2, weight: .bold))
                    .foregroundStyle(HUDStyle.mana)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(diameter * 0.12)
            } else if !snapshot.learned {
                Image(systemName: "lock.fill")
                    .font(.system(size: diameter * 0.22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            Circle()
                .strokeBorder(AngularGradient(colors: isUlt ? [Theme.gold, .white, Theme.gold.opacity(0.5), Theme.gold]
                                                            : [.white.opacity(0.85), color, .white.opacity(0.3), .white.opacity(0.85)],
                                              center: .center),
                              lineWidth: isUlt ? 3 : 2)
            if snapshot.isReady && isUlt {
                Circle().strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1).padding(-4)
            }
            HUDRankPips(rank: snapshot.rank, maxRank: snapshot.slot.maxRank, diameter: diameter, color: isUlt ? Theme.gold : Theme.cyan)
        }
        .frame(width: diameter, height: diameter)
        .saturation(dim && snapshot.cooldown <= 0 ? 0.35 : 1)
        .shadow(color: snapshot.isReady ? color.opacity(0.5) : .clear, radius: 6)
        .overlay { if highlighted { HUDHighlightRing(diameter: diameter + 16) } }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(HUDSpace.name))
                .onChanged { v in
                    model.abilityDragChanged(.skill(snapshot.slot), start: v.startLocation, location: v.location,
                                             buttonCenter: center)
                }
                .onEnded { v in model.abilityDragEnded(.skill(snapshot.slot), location: v.location) }
        )
        .hudAccessibility(id: Self.identifier(snapshot.slot), label: "\(CollectionStyle.slotName(snapshot.slot)) \(name)",
                          value: accessibilityValue) {
            model.abilityDragChanged(.skill(snapshot.slot), start: center, location: center, buttonCenter: center)
            model.abilityDragEnded(.skill(snapshot.slot), location: center)
        }
    }

    private var accessibilityValue: String {
        if !snapshot.learned { return L("未習得", "Not learned") }
        var parts = [L("ランク \(snapshot.rank)", "Rank \(snapshot.rank)")]
        if snapshot.cooldown > 0 { parts.append(L("残り \(HUDStyle.cooldown(snapshot.cooldown)) 秒", "\(HUDStyle.cooldown(snapshot.cooldown)) seconds left")) }
        else if snapshot.isReady { parts.append(L("使用可能", "Ready")) }
        return parts.joined(separator: "、")
    }

    static func identifier(_ slot: SkillSlot) -> String {
        switch slot {
        case .skill1: return "hud_skill1"
        case .skill2: return "hud_skill2"
        case .skill3: return "hud_skill3"
        case .ultimate, .passive: return "hud_ult"
        }
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
                    .offset(x: CGFloat(cos(angle * .pi / 180)) * diameter * 0.56,
                            y: CGFloat(sin(angle * .pi / 180)) * diameter * 0.56)
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

    var body: some View {
        let info = SpellInfo.of(snapshot.spellID)
        let ready = snapshot.castable && snapshot.cooldown <= 0
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [info.color.opacity(0.9), info.color.opacity(0.3), Color.black.opacity(0.85)],
                                     center: .init(x: 0.38, y: 0.3), startRadius: 1, endRadius: diameter * 0.62))
            Image(systemName: info.symbol)
                .font(.system(size: diameter * 0.40, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: info.color, radius: 3)
            if snapshot.cooldown > 0 {
                HUDCooldownPie(fraction: snapshot.cooldownFraction)
                    .fill(Color.black.opacity(0.6))
                    .animation(.linear(duration: 1.0 / 15.0), value: snapshot.cooldownFraction)
                Text(HUDStyle.cooldown(snapshot.cooldown))
                    .font(.system(size: diameter * 0.3, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
            } else if !ready {
                Circle().fill(Color.black.opacity(0.45))
            }
            Circle().strokeBorder(AngularGradient(colors: [.white.opacity(0.85), info.color, .white.opacity(0.3), .white.opacity(0.85)],
                                                  center: .center), lineWidth: 2)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: ready ? info.color.opacity(0.45) : .clear, radius: 5)
        .frame(width: max(44, diameter), height: max(44, diameter))
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(HUDSpace.name))
                .onChanged { v in
                    model.abilityDragChanged(.spell(snapshot.index), start: v.startLocation, location: v.location,
                                             buttonCenter: center)
                }
                .onEnded { v in model.abilityDragEnded(.spell(snapshot.index), location: v.location) }
        )
        .hudAccessibility(id: "hud_spell\(snapshot.index + 1)",
                          label: MasterData.shared.spell(snapshot.spellID).map { MasterText.spell($0) } ?? snapshot.spellID,
                          value: snapshot.cooldown > 0 ? L("残り \(HUDStyle.cooldown(snapshot.cooldown)) 秒", "\(HUDStyle.cooldown(snapshot.cooldown)) seconds left")
                                                       : L("使用可能", "Ready")) {
            model.abilityDragChanged(.spell(snapshot.index), start: center, location: center, buttonCenter: center)
            model.abilityDragEnded(.spell(snapshot.index), location: center)
        }
    }
}

struct HUDRecallButton: View {
    let model: HUDModel
    let diameter: CGFloat
    let channel: HUDChannel?
    let highlighted: Bool

    var body: some View {
        Button { model.recall() } label: {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.30, green: 0.45, blue: 0.95).opacity(0.9), Color.black.opacity(0.85)],
                                         center: .init(x: 0.4, y: 0.3), startRadius: 1, endRadius: diameter * 0.6))
                Image(systemName: "house.fill")
                    .font(.system(size: diameter * 0.38, weight: .bold))
                    .foregroundStyle(.white)
                if let ch = channel, ch.kind == .recall, ch.total > 0 {
                    Circle()
                        .trim(from: 0, to: 1 - ch.remaining / ch.total)
                        .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                        .animation(.linear(duration: 1.0 / 15.0), value: ch.remaining)
                }
                Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5)
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
    let model: HUDModel
    let slot: SkillSlot
    let diameter: CGFloat
    let highlighted: Bool
    @State private var bob = false

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
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .overlay { if highlighted { HUDHighlightRing(diameter: diameter + 16) } }
        .onAppear {
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
        case .skill3: return "hud_level_skill3"
        case .ultimate, .passive: return "hud_level_ult"
        }
    }
}

// MARK: - 右側クラスタ

struct HUDActionCluster: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let hero = model.hero
        let skills = model.skills
        let highlight = model.tutorial?.highlight
        let master = MasterData.shared
        ZStack {
            HUDAttackButton(model: model, diameter: layout.attackDiameter, highlighted: highlight == .attack)
                .position(layout.attackCenter)
            ForEach(skills) { sn in
                let d = sn.slot == .ultimate ? layout.ultDiameter : layout.skillDiameter
                let c = layout.skillCenter(sn.slot)
                HUDSkillButton(model: model, snapshot: sn, role: hero.role, diameter: d, center: c,
                               name: master.skill(sn.skillID).map { MasterText.skill($0) } ?? "",
                               highlighted: highlight == .skill1 && sn.slot == .skill1)
                    .position(c)
            }
            ForEach(model.spells) { sp in
                let c = layout.spellCenter(sp.index)
                HUDSpellButton(model: model, snapshot: sp, diameter: layout.spellDiameter, center: c)
                    .position(c)
            }
            HUDRecallButton(model: model, diameter: layout.recallDiameter, channel: hero.channel,
                            highlighted: highlight == .recall)
                .position(layout.recallCenter)
            ForEach(skills.filter(\.canLevel)) { sn in
                HUDLevelBadge(model: model, slot: sn.slot, diameter: layout.levelBadgeDiameter,
                              highlighted: highlight == .levelSkill1 && sn.slot == .skill1)
                    .position(layout.levelBadgeCenter(sn.slot))
            }
        }
        .opacity(hero.isDead ? 0.45 : 1)
        .animation(.spring(duration: 0.3), value: skills.map(\.canLevel))
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
