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
            }.padding(.horizontal, 10)
        }
    }
}


/// バトルスキルの選択（MLBB の「バトルスキル」のポップアップと同じ作り: 丸いアイコンを 4 × 3 に並べ、名前と副題を添え、
/// 選んでいる物は金の輪。右の欄に名前・副題・CD・説明と「OK」）。並びも MLBB と同じ。
/// 狩猟はジャングル担当だけが選べる（lane を渡したとき。ほかのレーンでは鍵を付ける）。
struct BattleSkillPicker: View {
    let current: String
    /// 担当レーン（nil = レーンの制限なし。ヒーロー詳細・既定のスキルの設定）。
    var lane: LanePosition? = nil
    var onEquip: (String) -> Void
    @Environment(AppModel.self) private var app
    @State private var picked: String?

    /// MLBB の並び（1 行目: 回復の泉・奮起・火炎弾・報復 / 2 行目: 狩猟・瞬間移動・執行・石化 / 3 行目: 疾走・守護・浄化・降臨）。
    static let order = ["BS16", "BS12", "BS14", "BS15", "BS05", "BS01", "BS11", "BS13", "BS06", "BS04", "BS02", "BS09"]

    var body: some View {
        let id = picked ?? current
        let spell = app.master.spell(id)
        let lock = lockReason(id)
        HStack(spacing: 14) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 10) {
                    ForEach(Self.order, id: \.self) { skill in
                        cell(skill, isPicked: skill == id)
                    }
                }.padding(6)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(spell.map { MasterText.spell($0) } ?? id).font(Celestial.title(20)).lineLimit(1).minimumScaleFactor(0.7)
                Text(SpellInfo.subtitle(id)).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                Text(L("CD：", "CD: ") + String(format: "%.1f", spell?.cooldownSec ?? 0))
                    .font(.system(size: 16, design: .serif))
                    .padding(.top, 6)
                ScrollView {
                    Text(SpellInfo.of(id).effect).font(Theme.body(13)).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let lock {
                    Label(lock, systemImage: "lock.fill").font(Theme.body(11)).foregroundStyle(Theme.gold)
                }
                Button {
                    guard lock == nil else { return }
                    app.haptics.tap()
                    onEquip(id)
                } label: {
                    Text("OK").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(lock != nil)
                .accessibilityIdentifier("battle_skill_confirm")
            }
            .padding(14)
            .frame(maxWidth: 190)
            .background(HomeChamfer(cut: 9).fill(Celestial.inkRaised.opacity(0.92)))
            .overlay(HomeChamfer(cut: 9).stroke(Celestial.ice.opacity(0.4), lineWidth: 0.6))
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private func cell(_ skill: String, isPicked: Bool) -> some View {
        let lock = lockReason(skill)
        return Button {
            picked = skill
            app.haptics.tap()
        } label: {
            VStack(spacing: 3) {
                SpellIconView(spellID: skill, size: 50)
                    .overlay(Circle()
                        .stroke(isPicked ? AnyShapeStyle(HomeStyle.goldGradient) : AnyShapeStyle(Celestial.ice.opacity(0.35)),
                                lineWidth: isPicked ? 3 : 1)
                        .padding(-3))
                    .shadow(color: isPicked ? Theme.gold.opacity(0.7) : .clear, radius: 6)
                    .opacity(lock == nil ? 1 : 0.55)
                    .overlay(alignment: .topTrailing) {
                        if lock != nil {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Circle().fill(Celestial.ink.opacity(0.9)))
                                .overlay(Circle().stroke(Celestial.ice.opacity(0.6), lineWidth: 0.6))
                                .offset(x: 6, y: -4)
                        }
                    }
                Text(FlowText.spellName(skill)).font(Celestial.heading(13)).lineLimit(1).minimumScaleFactor(0.7)
                Text(SpellInfo.subtitle(skill)).font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(FlowText.spellName(skill) + "、" + SpellInfo.subtitle(skill) + (lock.map { "、" + $0 } ?? ""))
        .accessibilityIdentifier("spell_\(skill)")
    }

    /// 選べない理由（アカウントのレベル、狩猟はジャングル以外）。選べるなら nil。
    private func lockReason(_ skill: String) -> String? {
        if let level = BattleSpell(rawValue: skill)?.unlockLevel, app.profile.accountLevel < level {
            return L("Lv\(level) で解放", "Unlocks at Lv \(level)")
        }
        if let lane, !SpellLoadoutRules.isAllowed(skill, lane: lane) {
            return L("ジャングル担当だけが使えます", "Jungle role only")
        }
        return nil
    }
}

extension SpellInfo {
    /// 副題（MLBB のバトルスキルの画面の 2 行目）。
    static func subtitle(_ id: String) -> String {
        switch id {
        case "BS16": return L("広範囲ヒール", "Area heal")
        case "BS12": return L("通常攻撃強化", "Basic attack boost")
        case "BS14": return L("攻防一体", "Offense & defense")
        case "BS15": return L("ダメージ反射", "Damage reflection")
        case "BS05": return L("ジャングル専用", "Jungle only")
        case "BS01": return L("機動性", "Mobility")
        case "BS11": return L("低HPキル", "Low-HP finisher")
        case "BS13": return L("範囲コントロール", "Area control")
        case "BS06": return L("持続的加速", "Sustained speed")
        case "BS04": return L("シールド", "Shield")
        case "BS02": return L("状態異常解除", "Remove debuffs")
        case "BS09": return L("テレポート", "Teleport")
        default: return ""
        }
    }
}
