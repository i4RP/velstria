import SwiftUI
import VelstriaCore

// 担当: ui-collection。UI044 スペル（既定 2 枠 + ヒーロー別の上書き）。

struct SpellLoadoutView: View {
    @Environment(AppModel.self) private var app
    /// nil = 既定のスペル、それ以外 = そのヒーロー専用。
    @State private var heroID: String?
    @State private var slot = 0

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8)]

    var body: some View {
        let current = SpellLoadoutRules.effective(heroID: heroID, profile: app.profile)
        ScreenScaffold(title: L("バトルスペル", "Battle Spells")) {
            VStack(spacing: 6) {
                scopeBar
                HStack(alignment: .top, spacing: 12) {
                    ScrollView {
                        slotsPanel(current)
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: 212)
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(app.master.spells) { spell in
                                spellCard(spell, current: current)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: 対象（既定 / ヒーロー別）

    private var scopeBar: some View {
        let owned = app.master.heroes.filter { app.owns(heroID: $0.heroID) }
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                CollectionFilterChip(title: L("既定", "Default"), symbol: "star.fill", color: Theme.gold, isSelected: heroID == nil) {
                    heroID = nil
                }
                .accessibilityIdentifier("spells_scope_default")
                Rectangle().fill(Theme.panelStroke).frame(width: 1, height: 26)
                ForEach(owned) { h in
                    let selected = heroID == h.heroID
                    Button {
                        app.haptics.tap()
                        heroID = h.heroID
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            HeroPortraitView(heroID: h.heroID, size: 36, showsRole: false)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.gold : Color.clear, lineWidth: 2.5))
                                .opacity(selected || heroID == nil ? 1 : 0.6)
                            if app.profile.heroSpells[h.heroID] != nil {
                                Circle().fill(Theme.gold).frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(Color.black, lineWidth: 1))
                                    .offset(x: 2, y: 2)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(MasterText.hero(h) + (app.profile.heroSpells[h.heroID] != nil ? L("（専用設定あり）", " (custom)") : ""))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("spells_scope_\(h.heroID)")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: 2 枠

    private func slotsPanel(_ current: [String]) -> some View {
        let hero = heroID.flatMap { app.master.hero($0) }
        let hasOverride = heroID.map { app.profile.heroSpells[$0] != nil } ?? false
        return VStack(alignment: .leading, spacing: 8) {
            Text(hero.map { MasterText.hero($0) } ?? L("既定のスペル", "Default Spells"))
                .font(Theme.heading(14))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(hero == nil ? L("専用設定の無いヒーローで使用されます", "Used by heroes without a custom setup")
                 : (hasOverride ? L("このヒーロー専用の設定です", "Custom setup for this hero")
                    : L("既定を使用中。変更するとこのヒーロー専用になります", "Using defaults. Changes create a custom setup")))
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ForEach(0..<SpellLoadoutRules.slotCount, id: \.self) { i in
                    slotButton(i, spellID: i < current.count ? current[i] : "")
                }
            }
            Text(L("枠を選んでから右のスペルをタップ", "Pick a slot, then tap a spell"))
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
            if let heroID, hasOverride {
                Button {
                    app.profile.heroSpells[heroID] = nil
                    app.haptics.tap()
                    app.showToast(L("既定のスペルに戻しました", "Reverted to default spells"))
                } label: {
                    Label(L("既定に戻す", "Use Defaults"), systemImage: "arrow.counterclockwise")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(minHeight: 44)
                .accessibilityIdentifier("spells_reset_hero")
            }
            // ジャングル担当になり得るロール（DESIGN §10: Assassin / Duelist）には狩猟印を案内する
            if let hero, hero.role == .assassin || hero.role == .duelist, !current.contains(BuildRules.smiteSpellID) {
                let smite = BuildRules.smiteName(master: app.master)
                Label(L("ジャングル担当なら「\(smite)」が必要です（ジャングル装備の購入条件）",
                        "Junglers need \(smite) (required to buy Jungle items)"), systemImage: "lightbulb.fill")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.panelStroke, lineWidth: 1))
        .padding(.bottom, 12)
    }

    private func slotButton(_ i: Int, spellID: String) -> some View {
        let selected = slot == i
        let spell = app.master.spell(spellID)
        return Button {
            app.haptics.tap()
            slot = i
        } label: {
            VStack(spacing: 4) {
                SpellIconView(spellID: spellID, size: 48)
                    .overlay(Circle().stroke(selected ? Theme.gold : Color.clear, lineWidth: 2.5).padding(-4))
                    .scaleEffect(selected ? 1.04 : 1)
                    .padding(.vertical, 5)
                Text(spell.map { MasterText.spell($0) } ?? "—")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(L("スペル\(i + 1)", "Spell \(i + 1)"))
                    .font(Theme.mono(9))
                    .foregroundStyle(selected ? Theme.gold : Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.gold.opacity(0.12) : Color.white.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: selected)
        .accessibilityLabel(L("枠\(i + 1): ", "Slot \(i + 1): ") + (spell.map { MasterText.spell($0) } ?? ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("spell_slot_\(i)")
    }

    // MARK: スペル一覧

    private func spellCard(_ spell: SpellDef, current: [String]) -> some View {
        let info = SpellInfo.of(spell.spellID)
        let equippedSlot = current.firstIndex(of: spell.spellID)
        return Button {
            assign(spell.spellID)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    SpellIconView(spellID: spell.spellID, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(MasterText.spell(spell))
                            .font(Theme.heading(13))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 3) {
                            Image(systemName: "timer").font(.system(size: 9, weight: .bold))
                            Text(CollectionStyle.seconds(spell.cooldownSec)).font(Theme.mono(10))
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if let equippedSlot {
                        Text("\(equippedSlot + 1)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Theme.gold))
                    }
                }
                Text(info.effect)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textPrimary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let tip = info.tip {
                    Text(tip)
                        .font(Theme.body(9))
                        .foregroundStyle(info.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(equippedSlot != nil ? info.color.opacity(0.12) : Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(equippedSlot != nil ? info.color.opacity(0.8) : Theme.panelStroke.opacity(0.5), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(CollectionPressStyle())
        .accessibilityLabel("\(MasterText.spell(spell))、\(info.effect)")
        .accessibilityAddTraits(equippedSlot != nil ? .isSelected : [])
        .accessibilityIdentifier("spell_\(spell.spellID)")
    }

    private func assign(_ spellID: String) {
        let base = SpellLoadoutRules.effective(heroID: heroID, profile: app.profile)
        let next = SpellLoadoutRules.assigning(spellID, slot: slot, in: base)
        guard next != base else { return }
        withAnimation(.spring(duration: 0.3)) {
            if let heroID {
                app.profile.heroSpells[heroID] = next
            } else {
                app.profile.defaultSpells = next
            }
            slot = (slot + 1) % SpellLoadoutRules.slotCount
        }
        app.haptics.tap()
    }
}
