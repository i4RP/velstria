import SwiftUI
import VelstriaCore

// 担当: battle-hud。下部中央のヒーローパネル:
// ポートレート + レベル（XP リング）、HP（シールド）/ リソースのバーと数値、状態アイコン（残り時間）、
// Gold とショップボタン（UI028）、おすすめ装備のクイック購入（脈動）、装備枠（タップでショップの売却へ）。

struct HUDHeroPanel: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let hero = model.hero
        let s = min(layout.scale, 1.08)
        VStack(alignment: .leading, spacing: 3 * s) {
            HStack(spacing: 7 * s) {
                HUDPortraitLevel(heroID: hero.heroID, level: hero.level, xp: hero.xpProgress, size: 46 * s,
                                 pulse: model.levelUpPulse)
                HUDVitalsBars(model: model, scale: s)
            }
            HStack(spacing: 4 * s) {
                HUDItemSlots(model: model, items: hero.items, slot: 31 * s)
                HUDShopButton(model: model, gold: hero.gold, width: 60 * s,
                              highlighted: model.tutorial?.highlight == .shop)
            }
        }
        .padding(.horizontal, 8 * s)
        .padding(.top, 6 * s)
        .padding(.bottom, 2 * s)
        .frame(width: layout.heroPanelWidth)
        .hudGlass(cornerRadius: 14)
        .overlay(alignment: .topLeading) {
            HUDStatusRow(statuses: hero.statuses, size: 22 * s)
                .offset(x: 4 * s, y: -26 * s)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            if let itemID = model.quickBuyItemID {
                HUDQuickBuyButton(model: model, itemID: itemID, size: 38 * s,
                                  highlighted: model.tutorial?.step == .buyItem)
                    .offset(x: 2 * s, y: -46 * s)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.quickBuyItemID)
    }
}

/// HP・リソースのバー（毎 tick 変わる値だけを観測する）。
struct HUDVitalsBars: View {
    let model: HUDModel
    let scale: CGFloat

    var body: some View {
        let v = model.vitals
        VStack(alignment: .leading, spacing: 4 * scale) {
            HUDBar(value: v.hp, max: v.maxHP, shield: v.shield,
                   color: v.hpRatio < 0.3 ? HUDStyle.hpLow : HUDStyle.hp, height: 15 * scale, showsText: true)
                .accessibilityElement()
                .accessibilityLabel(L("HP", "HP"))
                .accessibilityValue("\(HUDStyle.number(v.hp)) / \(HUDStyle.number(v.maxHP))")
                .accessibilityIdentifier("hud_hp")
            if v.maxResource > 0 {
                HUDBar(value: v.resource, max: v.maxResource, shield: 0,
                       color: HUDStyle.resourceColor(v.resourceKind), height: 11 * scale, showsText: true)
                    .accessibilityElement()
                    .accessibilityLabel(v.resourceKind == .energy ? L("エナジー", "Energy") : L("マナ", "Mana"))
                    .accessibilityValue("\(HUDStyle.number(v.resource)) / \(HUDStyle.number(v.maxResource))")
            }
        }
    }
}

/// ポートレートとレベル（XP の円環）。
struct HUDPortraitLevel: View, Equatable {
    let heroID: String
    let level: Int
    let xp: Double
    let size: CGFloat
    let pulse: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.5), lineWidth: 4)
            Circle()
                .trim(from: 0, to: xp)
                .stroke(HUDStyle.xp, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: xp)
            if !heroID.isEmpty {
                HeroPortraitView(heroID: heroID, size: size - 10, showsRole: false)
                    .clipShape(Circle())
            }
            Text("\(level)")
                .font(.system(size: size * 0.24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: size * 0.40, height: size * 0.40)
                .background(Circle().fill(Color(red: 0.12, green: 0.10, blue: 0.28)))
                .overlay(Circle().strokeBorder(HUDStyle.xp, lineWidth: 1.2))
                .offset(x: size * 0.36, y: size * 0.36)
            HUDLevelUpFlash(trigger: pulse, size: size)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("レベル \(level)", "Level \(level)"))
    }
}

/// レベルアップ時に光る輪。
struct HUDLevelUpFlash: View {
    let trigger: Int
    let size: CGFloat
    @State private var shown = false

    var body: some View {
        Circle()
            .strokeBorder(Theme.gold, lineWidth: 3)
            .frame(width: size, height: size)
            .scaleEffect(shown ? 1.8 : 1)
            .opacity(shown ? 0 : (trigger > 0 ? 1 : 0))
            .onChange(of: trigger) {
                shown = false
                withAnimation(.easeOut(duration: 0.8)) { shown = true }
            }
            .allowsHitTesting(false)
    }
}

/// 数値付きのバー（シールドは白く延長して表示）。
struct HUDBar: View, Equatable {
    let value: Double
    let max: Double
    let shield: Double
    let color: Color
    let height: CGFloat
    let showsText: Bool

    var body: some View {
        GeometryReader { g in
            let total = Swift.max(max, value + shield, 1)
            let vw = g.size.width * CGFloat(Swift.max(0, value) / total)
            let sw = g.size.width * CGFloat(Swift.max(0, shield) / total)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.55))
                Capsule()
                    .fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    .frame(width: vw)
                    .animation(.easeOut(duration: 0.15), value: vw)
                if sw > 0.5 {
                    Rectangle()
                        .fill(HUDStyle.shield)
                        .frame(width: sw)
                        .offset(x: vw)
                }
                // 目盛り（HP 100 毎の細線は多すぎるので 1/4 刻み）
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { k in
                        Rectangle().fill(Color.clear).frame(maxWidth: .infinity)
                        if k < 3 { Rectangle().fill(Color.black.opacity(0.35)).frame(width: 1) }
                    }
                }
                if showsText {
                    Text(shield > 0.5 ? "\(HUDStyle.number(value)) +\(HUDStyle.number(shield)) / \(HUDStyle.number(max))"
                                      : "\(HUDStyle.number(value)) / \(HUDStyle.number(max))")
                        .font(.system(size: Swift.max(8, height * 0.68), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 1)
                        .frame(maxWidth: .infinity)
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8))
        }
        .frame(height: height)
    }
}

/// 状態アイコン（弱体は赤枠・強化は緑枠、残り時間の円弧と秒数）。
struct HUDStatusRow: View, Equatable {
    let statuses: [HUDStatusIcon]
    let size: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            ForEach(statuses) { st in
                let color = HUDSymbols.statusColor(st.kind)
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.black.opacity(0.6))
                    Image(systemName: HUDSymbols.status(st.kind))
                        .font(.system(size: size * 0.52, weight: .bold))
                        .foregroundStyle(color)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .trim(from: 0, to: st.fraction)
                        .stroke(color, lineWidth: 1.5)
                    if st.remaining < 10 {
                        Text(String(format: st.remaining < 3 ? "%.1f" : "%.0f", st.remaining))
                            .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 1)
                            .offset(x: size * 0.3, y: size * 0.36)
                    }
                }
                .frame(width: size, height: size)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(HUDSymbols.statusName(st.kind))
                .accessibilityValue(L("残り \(Int(st.remaining.rounded(.up))) 秒", "\(Int(st.remaining.rounded(.up))) seconds left"))
            }
        }
    }
}

/// 装備 6 枠（タップでショップの売却を開く）。タップ領域は縦 44pt。
struct HUDItemSlots: View {
    let model: HUDModel
    let items: [String]
    let slot: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<Balance.itemSlots, id: \.self) { k in
                Button { model.openShop(slot: k < items.count ? k : nil) } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.5))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8))
                        if k < items.count, let item = MasterData.shared.item(items[k]) {
                            ItemIconView(item: item, size: slot - 2)
                        }
                    }
                    .frame(width: slot, height: slot)
                    .frame(width: slot + 3, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HUDPressStyle())
                .accessibilityLabel(k < items.count ? (MasterData.shared.item(items[k]).map { MasterText.item($0) } ?? "")
                                                    : L("空きスロット", "Empty slot"))
                .accessibilityIdentifier("hud_item_\(k + 1)")
            }
        }
        .frame(height: 44)
    }
}

struct HUDShopButton: View {
    let model: HUDModel
    let gold: Int
    let width: CGFloat
    let highlighted: Bool

    var body: some View {
        Button { model.openShop() } label: {
            HStack(spacing: 3) {
                Image(systemName: "bag.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.white, Theme.gold], startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .bottomTrailing) { HUDCoin(size: 9).offset(x: 3, y: 2) }
                Text("\(gold)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 5)
            .frame(width: width, height: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.32, green: 0.24, blue: 0.08), Color.black.opacity(0.7)],
                                     startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.gold.opacity(0.8), lineWidth: 1.2))
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .overlay { if highlighted { HUDHighlightRing(diameter: width + 12) } }
        .accessibilityLabel(L("ショップ", "Shop"))
        .accessibilityValue("\(gold) Gold")
        .accessibilityIdentifier("hud_shop")
    }
}

/// おすすめ装備のワンタップ購入（脈動）。
struct HUDQuickBuyButton: View {
    let model: HUDModel
    let itemID: String
    let size: CGFloat
    let highlighted: Bool
    @State private var pulse = false

    var body: some View {
        Button { model.quickBuy() } label: {
            ZStack(alignment: .bottom) {
                if let item = MasterData.shared.item(itemID) {
                    ItemIconView(item: item, size: size)
                }
                Text(L("購入", "BUY"))
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.gold))
                    .offset(y: 7)
            }
            .frame(width: max(44, size), height: max(44, size))
            .scaleEffect(pulse ? 1.07 : 0.97)
            .shadow(color: Theme.gold.opacity(pulse ? 0.9 : 0.3), radius: pulse ? 10 : 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .overlay { if highlighted { HUDHighlightRing(diameter: size + 18) } }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel(L("おすすめ装備を購入: \(MasterData.shared.item(itemID).map { MasterText.item($0) } ?? itemID)",
                              "Buy recommended: \(MasterData.shared.item(itemID).map { MasterText.item($0) } ?? itemID)"))
        .accessibilityIdentifier("hud_quick_buy")
    }
}
