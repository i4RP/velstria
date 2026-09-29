import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI059 エモート（所持エモートを 4 枠に装備）。
// profile.equippedEmotes は空き枠を詰めた最大 4 要素で保存する（EmoteSlots 参照）。

struct EmoteLoadoutView: View {
    @Environment(AppModel.self) private var app
    @State private var slot = 0

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        let owned = CosmeticInfo.owned(.emote, profile: app.profile, master: app.master)
        let slots = EmoteSlots.pruned(app.profile.equippedEmotes, owned: app.profile.ownedCosmeticIDs)
        ScreenScaffold(title: L("エモート", "Emotes")) {
            HStack(alignment: .top, spacing: 14) {
                wheel(slots)
                    .frame(width: 250)
                VStack(alignment: .leading, spacing: 6) {
                    CollectionSectionTitle(title: L("所持エモート", "Owned Emotes"), symbol: "bubble.left.fill",
                                           trailing: "\(owned.count)")
                    if owned.isEmpty {
                        CollectionEmptyState(symbol: "bubble.left",
                                             title: L("エモートを所持していません", "You don't own any emotes"),
                                             message: L("ストアで入手すると、戦闘中に仲間へ気持ちを伝えられます。",
                                                        "Get emotes in the store to express yourself during matches."))
                        Button {
                            app.router.push(.store)
                        } label: {
                            Label(L("ストアへ", "Go to Store"), systemImage: "bag.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("emotes_go_store")
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(owned) { c in
                                    emoteCell(c, equippedSlot: slots.firstIndex(of: c.cosmeticID))
                                }
                            }
                            .padding(.bottom, 12)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            // 所持していないエモートが残っていれば外す（空配列はそのまま）
            let current = app.profile.equippedEmotes
            if !current.isEmpty {
                let pruned = EmoteSlots.pruned(current, owned: app.profile.ownedCosmeticIDs)
                if pruned != current { app.profile.equippedEmotes = pruned }
            }
        }
    }

    // MARK: 4 枠（戦闘中のホイール配置）

    private func wheel(_ slots: [String]) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Theme.panelStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: 176, height: 176)
                Circle()
                    .fill(RadialGradient(colors: [Theme.cyan.opacity(0.18), .clear], center: .center, startRadius: 4, endRadius: 90))
                    .frame(width: 176, height: 176)
                Image(systemName: "face.smiling")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.textSecondary)
                // 上・右・下・左
                ForEach(0..<EmoteSlots.count, id: \.self) { i in
                    let angle = -Double.pi / 2 + Double(i) * .pi / 2
                    slotButton(i, emoteID: EmoteSlots.emote(at: i, in: slots), slots: slots)
                        .offset(x: cos(angle) * 84, y: sin(angle) * 84)
                }
            }
            .frame(width: 240, height: 240)
            if EmoteSlots.emote(at: slot, in: slots) != nil {
                Button {
                    app.profile.equippedEmotes = EmoteSlots.clearing(slot: slot, in: slots)
                    app.haptics.tap()
                } label: {
                    Label(L("枠\(slot + 1)を空ける", "Clear slot \(slot + 1)"), systemImage: "xmark.circle")
                        .font(Theme.body(12))
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(minHeight: 44)
                .accessibilityIdentifier("emote_clear")
            } else {
                Text(L("枠を選んで、右のエモートをタップ", "Select a slot, then tap an emote"))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: 44)
            }
        }
    }

    private func slotButton(_ i: Int, emoteID: String?, slots: [String]) -> some View {
        let selected = slot == i
        let emote = emoteID.flatMap { app.master.cosmetic($0) }
        return Button {
            app.haptics.tap()
            // 空き枠は前から詰めて使うため、2 つ目以降の空き枠を選んでも最初の空き枠を選択する
            withAnimation(.spring(duration: 0.25)) { slot = min(i, slots.count) }
        } label: {
            ZStack {
                if let emote {
                    CosmeticPreviewView(cosmetic: emote, size: 62, animated: selected)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.panelStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .overlay(Image(systemName: "plus").foregroundStyle(Theme.textSecondary))
                        .frame(width: 62, height: 62)
                }
                Text("\(i + 1)")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(selected ? .black : Theme.textSecondary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(selected ? Theme.gold : Color.black.opacity(0.6)))
                    .offset(x: -26, y: -26)
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Theme.gold : Color.clear, lineWidth: 2.5).padding(-3))
            .scaleEffect(selected ? 1.06 : 1)
            .frame(width: 66, height: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("枠\(i + 1): ", "Slot \(i + 1): ") + (emote.map { MasterText.cosmetic($0) } ?? L("空き", "empty")))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("emote_slot_\(i)")
    }

    private func emoteCell(_ c: CosmeticDef, equippedSlot: Int?) -> some View {
        Button {
            assign(c)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    CosmeticPreviewView(cosmetic: c, size: 64, animated: false)
                    if let equippedSlot {
                        Text("\(equippedSlot + 1)")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Theme.gold))
                            .offset(x: 5, y: -5)
                    }
                }
                Text(MasterText.cosmetic(c))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 26)
                CollectionRarityTag(rarity: c.rarity).scaleEffect(0.85)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(equippedSlot != nil ? Theme.gold.opacity(0.1) : Color.white.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel(MasterText.cosmetic(c) + (equippedSlot.map { L("（枠\($0 + 1)）", " (slot \($0 + 1))") } ?? ""))
        .accessibilityIdentifier("emote_\(c.cosmeticID)")
    }

    private func assign(_ c: CosmeticDef) {
        let current = EmoteSlots.pruned(app.profile.equippedEmotes, owned: app.profile.ownedCosmeticIDs)
        let next = EmoteSlots.assigning(c.cosmeticID, slot: slot, in: current)
        app.haptics.tap()
        withAnimation(.spring(duration: 0.3)) {
            app.profile.equippedEmotes = next
            // 次の空き枠へ進む
            if let empty = EmoteSlots.firstEmptySlot(in: next) { slot = empty }
        }
    }
}
