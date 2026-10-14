import SwiftUI
import VelstriaCore

struct SpellLoadoutView: View {
    @Environment(AppModel.self) private var app
    @State private var heroID: String?
    var body: some View {
        ScreenScaffold(title: L("バトルスキル", "Battle Skills")) {
            VStack(spacing: 8) {
                Picker(L("ヒーロー", "Hero"), selection: $heroID) {
                    Text(L("既定", "Default")).tag(String?.none)
                    ForEach(app.master.heroes.filter { app.owns(heroID: $0.heroID) }) { hero in
                        Text(MasterText.hero(hero)).tag(Optional(hero.heroID))
                    }
                }.pickerStyle(.menu)
                BattleSkillPicker(current: SpellLoadoutRules.effective(heroID: heroID, profile: app.profile)[0]) { id in
                    let value = [id, SpellLoadoutRules.fixedSpellID]
                    if let heroID { app.profile.heroSpells[heroID] = value }
                    else { app.profile.defaultSpells = value }
                    app.showToast(L("バトルスキルを設定しました", "Battle skill equipped"))
                }
            }.padding(.horizontal, 20)
        }
    }
}

struct BattleSkillPicker: View {
    let current: String
    var onEquip: (String) -> Void
    @Environment(AppModel.self) private var app
    @State private var selected: String?
    private let order = ["BS16", "BS12", "BS14", "BS15", "BS05", "BS01", "BS11", "BS13", "BS06", "BS04", "BS02", "BS09"]
    var body: some View {
        let id = selected ?? current
        let spell = app.master.spell(id)
        let unlocked = SpellLoadoutRules.isUnlocked(id, level: app.profile.accountLevel)
        HStack(spacing: 18) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(order, id: \.self) { skill in
                        let level = BattleSpell(rawValue: skill)?.unlockLevel ?? 1
                        Button { selected = skill; app.haptics.tap() } label: {
                            VStack(spacing: 4) {
                                SpellIconView(spellID: skill, size: 48)
                                    .overlay(Circle().stroke(skill == id ? Theme.gold : Theme.cyan.opacity(0.4), lineWidth: 2).padding(-3))
                                    .opacity(app.profile.accountLevel >= level ? 1 : 0.45)
                                Text(FlowText.spellName(skill)).font(Theme.heading(12)).lineLimit(1).minimumScaleFactor(0.7)
                                Text(app.profile.accountLevel < level ? "Lv\(level) " + L("解放", "Unlock") : (skill == current ? L("装備中", "Equipped") : " "))
                                    .font(Theme.body(9)).foregroundStyle(Theme.textSecondary)
                            }.frame(maxWidth: .infinity).padding(2)
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("spell_\(skill)")
                    }
                }.padding(5)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(spell.map { MasterText.spell($0) } ?? id).font(Theme.heading(21))
                Text("CD : \(Int(spell?.cooldownSec ?? 0)).0").font(Theme.mono(16)).foregroundStyle(Theme.cyan)
                ScrollView { Text(SpellInfo.of(id).effect).font(Theme.body(13)).frame(maxWidth: .infinity, alignment: .leading) }
                Text(L("リコール・回復は全ヒーロー共通。追加で1つ装備できます。", "Recall and Recovery are always available. Equip one extra battle skill."))
                    .font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
                Button {
                    guard unlocked else { return }
                    app.haptics.tap(); onEquip(id)
                } label: {
                    Text(unlocked ? L("OK", "OK") : "Lv\(BattleSpell(rawValue: id)?.unlockLevel ?? 1) " + L("で解放", "to unlock"))
                        .frame(maxWidth: .infinity)
                }.buttonStyle(PrimaryButtonStyle()).disabled(!unlocked)
                    .accessibilityIdentifier("battle_skill_confirm")
            }.padding(16).frame(width: 225).background(Theme.panel.opacity(0.8))
        }.foregroundStyle(Theme.textPrimary)
    }
}
