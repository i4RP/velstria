import SwiftUI
import VelstriaCore

extension HUDLayout {
    /// ショップ脇のクイック購入。描画と透明な44ptタッチ領域で共通の座標を使う。
    var quickBuyFrame: CGRect {
        CGRect(x: leftHanded ? shopFrame.maxX + 2 : shopFrame.minX - 46,
               y: shopFrame.midY + 22, width: 44, height: 44)
    }
}

// ショップの入口と小さなクイック購入。数値・装備・状態の詳細はショップへ集約する。
// HUDModel の既存 15 Hz スナップショットだけを観測し、戦闘入力・購入コマンドは従来のまま。
struct HUDCompactEconomy: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let frame = layout.shopFrame
        ZStack {
            HUDShopButton(model: model, gold: model.hero.gold, width: frame.width,
                          beckon: model.hero.isDead, highlighted: model.tutorial?.highlight == .shop)
                .position(x: frame.midX, y: frame.midY)
            if let itemID = model.quickBuyItemID {
                HUDQuickBuyButton(model: model, itemID: itemID, size: 28 * min(layout.scale, 1.1),
                                  highlighted: model.tutorial?.step == .buyItem)
                    .position(x: layout.quickBuyFrame.midX, y: layout.quickBuyFrame.midY)
                    .transition(.opacity)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .animation(.easeOut(duration: 0.18), value: model.quickBuyItemID)
    }
}

/// HP・リソースのバー（毎 tick 変わる値だけを観測する）。
/// 死亡中は HP を空にして数値の代わりに「復活待ち」、リソースは数値を隠して薄く。
struct HUDVitalsBars: View {
    let model: HUDModel
    let scale: CGFloat
    var dead = false
    var hpHeight: CGFloat? = nil
    var resourceHeight: CGFloat? = nil

    /// 死亡中の HP バーの表示。
    static var respawningCaption: String { L("復活待ち", "Respawning") }

    var body: some View {
        let v = model.vitals
        VStack(alignment: .leading, spacing: 3 * scale) {
            HUDBar(value: dead ? 0 : v.hp, max: v.maxHP, shield: dead ? 0 : v.shield,
                   color: v.hpRatio < 0.3 ? HUDStyle.hpLow : HUDStyle.hp, height: hpHeight ?? 17 * scale, showsText: true,
                   caption: dead ? Self.respawningCaption : nil)
                .accessibilityElement()
                .accessibilityLabel(L("HP", "HP"))
                .accessibilityValue(dead ? Self.respawningCaption : "\(HUDStyle.number(v.hp)) / \(HUDStyle.number(v.maxHP))")
                .accessibilityIdentifier("hud_hp")
            if v.maxResource > 0 {
                HUDBar(value: v.resource, max: v.maxResource, shield: 0,
                       color: HUDStyle.resourceColor(v.resourceKind), height: resourceHeight ?? 10 * scale, showsText: !dead)
                    .opacity(dead ? 0.45 : 1)
                    .accessibilityElement()
                    .accessibilityLabel(v.resourceKind == .energy ? L("エナジー", "Energy") : L("マナ", "Mana"))
                    .accessibilityValue("\(HUDStyle.number(v.resource)) / \(HUDStyle.number(v.maxResource))")
            }
        }
        .animation(.easeInOut(duration: 0.3), value: dead)
    }
}

/// ポートレートとレベル（XP の円環）。死亡中は顔を白黒にして暗くする。
struct HUDPortraitLevel: View, Equatable {
    let heroID: String
    let level: Int
    let xp: Double
    let size: CGFloat
    let pulse: Int
    var dead = false

    var body: some View {
        ZStack {
            Circle()
                .fill(HUDStyle.surface)
            Circle()
                .stroke(HUDStyle.violet.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(1, max(0, xp)))
                .stroke(HUDStyle.xp, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: xp)
            if !heroID.isEmpty {
                HeroPortraitView(heroID: heroID, size: size - 10, showsRole: false)
                    .clipShape(Circle())
                    .saturation(dead ? 0 : 1)
                    .brightness(dead ? -0.12 : 0)
                    .overlay(Circle().fill(Color.black.opacity(dead ? 0.28 : 0)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                    .animation(.easeInOut(duration: 0.3), value: dead)
            }
            Text("\(level)")
                .font(.system(size: size * 0.24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: size * 0.40, height: size * 0.40)
                .background(Circle().fill(HUDStyle.violet))
                .overlay(Circle().strokeBorder(HUDStyle.surface, lineWidth: 2))
                .offset(x: size * 0.36, y: size * 0.36)
            HUDLevelUpFlash(trigger: pulse, size: size)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("レベル \(level)", "Level \(level)"))
        .accessibilityValue(dead ? HUDVitalsBars.respawningCaption : "")
    }
}

/// レベルアップ時に光る輪。
struct HUDLevelUpFlash: View {
    let trigger: Int
    let size: CGFloat
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .strokeBorder(Theme.gold, lineWidth: 3)
            .frame(width: size, height: size)
            .scaleEffect(shown ? 1.8 : 1)
            .opacity(shown ? 0 : (trigger > 0 ? 1 : 0))
            .onChange(of: trigger) {
                guard !reduceMotion else { shown = true; return }
                shown = false
                withAnimation(.easeOut(duration: 0.8)) { shown = true }
            }
            .allowsHitTesting(false)
    }
}

/// 数値付きのバー（シールドは白く延長して表示）。caption があれば数値の代わりに表示する。
struct HUDBar: View, Equatable {
    let value: Double
    let max: Double
    let shield: Double
    let color: Color
    let height: CGFloat
    let showsText: Bool
    var caption: String? = nil

    var body: some View {
        GeometryReader { g in
            let total = Swift.max(max, value + shield, 1)
            let vw = g.size.width * CGFloat(Swift.max(0, value) / total)
            let sw = g.size.width * CGFloat(Swift.max(0, shield) / total)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.black.opacity(0.48))
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(colors: [color, color.opacity(0.84)], startPoint: .top, endPoint: .bottom))
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
                if let caption {
                    Text(caption)
                        .font(.system(size: Swift.max(8, height * 0.66), weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black, radius: 1, y: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                } else if showsText {
                    Text(shield > 0.5 ? "\(HUDStyle.number(value)) +\(HUDStyle.number(shield)) / \(HUDStyle.number(max))"
                                      : "\(HUDStyle.number(value)) / \(HUDStyle.number(max))")
                        .font(.system(size: Swift.max(8, height * 0.62), weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 1, y: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(Color.black.opacity(0.52)))
                        .frame(maxWidth: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
        }
        .frame(height: height)
    }
}

/// 状態アイコン（弱体は赤枠・強化は緑枠、残り時間の円弧と秒数）。
struct HUDStatusRow: View, Equatable {
    let statuses: [HUDStatusIcon]
    let size: CGFloat
    /// パッシブのバッジ（キット層。スタック・タイマー）。状態アイコンの先頭に金色で出す。
    var passive: KitBadge?

    var body: some View {
        HStack(spacing: 3) {
            if let p = passive {
                let text = HUDKitDisplay.text(p)
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.black.opacity(0.6))
                    Image(systemName: "seal.fill")
                        .font(.system(size: size * 0.52, weight: .bold))
                        .foregroundStyle(Theme.gold)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .trim(from: 0, to: HUDKitDisplay.fraction(p))
                        .stroke(Theme.gold, lineWidth: 1.5)
                    if !text.isEmpty {
                        Text(text)
                            .font(.system(size: size * 0.4, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 1)
                            .offset(x: size * 0.3, y: size * 0.36)
                    }
                }
                .frame(width: size, height: size)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("パッシブ", "Passive"))
                .accessibilityValue(text)
            }
            ForEach(statuses) { st in
                let color = HUDSymbols.statusColor(st.kind, tag: st.tag, isBuff: st.isBuff)
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.black.opacity(0.6))
                    Image(systemName: HUDSymbols.status(st.kind, tag: st.tag))
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
                .accessibilityLabel(HUDSymbols.statusName(st.kind, tag: st.tag, isBuff: st.isBuff))
                .accessibilityValue(L("残り \(Int(st.remaining.rounded(.up))) 秒", "\(Int(st.remaining.rounded(.up))) seconds left"))
            }
        }
    }
}

/// 所持 Gold とショップの入口。見た目は薄い 32pt、タッチ領域は 44pt。
struct HUDShopButton: View {
    let model: HUDModel
    let gold: Int
    let width: CGFloat
    var beckon = false
    let highlighted: Bool

    var body: some View {
        Button { model.openShop() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("G")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(gold)")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(HUDStyle.shopGold)
            .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
            .padding(.horizontal, 6)
            .frame(width: width, height: 32 * min(1.1, max(0.85, width / 62)))
            .background(HUDShopOutline().fill(HUDStyle.surface.opacity(0.35)))
            .overlay(HUDShopOutline().stroke(HUDStyle.shopGold.opacity(beckon ? 0.9 : 0.6), lineWidth: 0.8))
            .frame(width: max(44, width), height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .overlay { if highlighted { HUDHighlightRing(diameter: width + 12) } }
        .accessibilityLabel(L("ショップ", "Shop"))
        .accessibilityValue("\(gold) Gold")
        .accessibilityHint(beckon ? HUDShopBeckon.hint : L("装備とステータスを確認", "View equipment and hero details"))
        .accessibilityIdentifier("hud_shop")
    }
}

/// 参考のショップ枠と同様、右上・左下を控えめに切り落とす。
private struct HUDShopOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let corner = min(6, rect.height / 4)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + corner))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - corner))
            path.closeSubpath()
        }
    }
}

extension HUDStyle {
    static let shopGold = Color(red: 0.91, green: 0.77, blue: 0.41)
}

/// 復活待ちのショップ案内。継続的な脈動は使わず細い枠だけを明るくする。
enum HUDShopBeckon {
    static var hint: String { L("復活までに装備を購入できます", "Buy items while you wait to respawn") }
}

/// 所持金の隣のワンタップ購入。常設カード・脈動をやめ、小さな装備アイコンを使う。
struct HUDQuickBuyButton: View {
    let model: HUDModel
    let itemID: String
    let size: CGFloat
    let highlighted: Bool

    var body: some View {
        Button { model.quickBuy() } label: {
            ZStack(alignment: .bottomTrailing) {
                if let item = MasterData.shared.item(itemID) {
                    ItemIconView(item: item, size: size)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(HUDStyle.shopGold.opacity(0.65), lineWidth: 0.7))
                }
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(HUDStyle.shopGold)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(HUDStyle.surface.opacity(0.85)))
                    .overlay(Circle().strokeBorder(HUDStyle.shopGold.opacity(0.5), lineWidth: 0.6))
                    .offset(x: 3, y: 3)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .overlay { if highlighted { HUDHighlightRing(diameter: size + 14) } }
        .accessibilityLabel(L("おすすめ装備を購入: \(MasterData.shared.item(itemID).map { MasterText.item($0) } ?? itemID)",
                              "Buy recommended: \(MasterData.shared.item(itemID).map { MasterText.item($0) } ?? itemID)"))
        .accessibilityIdentifier("hud_quick_buy")
    }
}
