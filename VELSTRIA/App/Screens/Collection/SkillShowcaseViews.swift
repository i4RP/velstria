import SwiftUI
import VelstriaCore

// 担当: ui-collection。ヒーロー詳細・スキル詳細の共通部品（Mobile Legends 風: 左 = ヒーロー情報とスキルアイコン列、右 = スキル詳細）。
// 計算は SkillShowcaseLogic.swift（純粋・テスト済み）。ここは見た目だけ。

enum SkillShowcaseStyle {
    static func color(_ rgb: SkillRGB) -> Color {
        Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// 説明文の強調色。物理 = 赤、魔法 = 紫、確定 = 白、キーワード = 金、係数 = オレンジ、回復 = 緑。
    static func color(for role: SkillTextSegment.Role) -> Color {
        switch role {
        case .plain: return Theme.textPrimary.opacity(0.92)
        case .physical: return Color(red: 1.0, green: 0.32, blue: 0.30)
        case .magic: return Color(red: 0.72, green: 0.60, blue: 1.0)
        case .trueDamage: return Color.white
        case .keyword: return Theme.gold
        case .coefficient: return Color(red: 1.0, green: 0.62, blue: 0.20)
        case .heal: return Theme.success
        }
    }

    static func color(for kind: SkillCoefficient.Kind) -> Color {
        switch kind {
        case .damageAttack: return Color(red: 1.0, green: 0.62, blue: 0.40)
        case .damagePower: return Color(red: 0.72, green: 0.60, blue: 1.0)
        case .healAttack, .healPower: return Theme.success
        }
    }

    /// 暗い紺のガラス調パネルの地色。
    static let glass = Color(red: 0.04, green: 0.07, blue: 0.16)

    /// 左パネルの幅。
    static let infoPanelWidth: CGFloat = 262

    static func panelBackground(_ tint: Color = Theme.cyan) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.20), glass.opacity(0.92)], startPoint: .top, endPoint: .bottom))
    }
}

/// スキルのタグ（範囲技・減速 など。色はタグの種類で決まる）。
struct SkillTagChip: View {
    let key: String

    var body: some View {
        let style = SkillTags.style(for: key)
        Text(style.name)
            .font(Theme.body(11))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(SkillShowcaseStyle.color(style.rgb)))
            .accessibilityIdentifier("skilltag_\(key)")
    }
}

/// スキルの丸いアイコン（既存の HUD のスキル記号を使う）。下に主タグの名前。選択中は金の輪。
struct SkillIconButton: View {
    let skill: SkillDef
    let hero: HeroDef
    let isSelected: Bool
    let identifier: String
    let action: () -> Void
    @Environment(AppModel.self) private var app

    private static let diameter: CGFloat = 44

    var body: some View {
        let targeting = SkillCatalog.targeting(for: skill, hero: hero)
        let isUlt = skill.slot == .ultimate
        let color: Color = skill.slot == .passive ? CollectionStyle.slotColor(.passive)
            : (isUlt ? HUDStyle.violet : Theme.roleColor(hero.role))
        let caption = SkillTags.caption(for: SkillTags.tags(for: skill, hero: hero, master: app.master))
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    HUDAbilityFace(color: color, diameter: Self.diameter, ultimate: isUlt)
                    Image(systemName: HUDSymbols.skill(targeting.archetype))
                        .font(.system(size: Self.diameter * 0.4, weight: .bold))
                        .foregroundStyle(Color.white)
                    if isSelected {
                        Circle().strokeBorder(Theme.gold, lineWidth: 3).padding(-3)
                    }
                }
                .frame(width: Self.diameter, height: Self.diameter)
                .scaleEffect(isSelected ? 1.06 : 1)
                .shadow(color: isSelected ? Theme.gold.opacity(0.6) : .clear, radius: 6)
                Text(caption.isEmpty ? " " : caption)
                    .font(Theme.body(10))
                    .foregroundStyle(isSelected ? Theme.gold : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(minWidth: 48, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MasterText.skill(skill))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

/// 評価バー 4 本（生存能力・攻撃能力・コントロール効果・難易度）。
struct HeroRatingBars: View {
    let ratings: HeroRatings

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            bar(key: "survivability", label: L("生存能力", "Durability"), value: ratings.survivability)
            bar(key: "offense", label: L("攻撃能力", "Offense"), value: ratings.offense)
            bar(key: "control", label: L("コントロール効果", "Crowd Control"), value: ratings.control)
            bar(key: "difficulty", label: L("難易度", "Difficulty"), value: ratings.difficulty)
        }
    }

    private func bar(key: String, label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textPrimary.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.cyan.opacity(0.7), Theme.cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, geo.size.width * min(1, max(0, value))))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((min(1, max(0, value)) * 100).rounded()))%")
        .accessibilityIdentifier("herodetail_rating_\(key)")
    }
}

// MARK: - 左パネル

/// 左のパネル（幅 `SkillShowcaseStyle.infoPanelWidth`）: ヒーロー名・ロール・評価バー・スキルアイコン列・操作ボタン。
/// 3D プレビューは名前の右隣（ヒーロー詳細のみ。スキル詳細は小さなポートレート）。
struct HeroInfoPanel: View {
    let hero: HeroDef
    /// 選択中のスキル（nil = どれも選ばない）。
    var selectedSkillID: String?
    /// スキルアイコンのアクセシビリティ ID の接頭辞（`<接頭辞><skillID>`）。
    var skillIDPrefix: String
    var shows3DPreview = true
    /// 非 nil のときだけ「解放」ボタンを出す（ヒーロー詳細）。
    var pendingSKU: Binding<String?>?
    let onSelectSkill: (SkillDef) -> Void
    /// 非 nil のときだけ下の丸いショートカット（スキン・ビルド・伝記）を出す。
    var onQuickTab: ((HeroDetailTab) -> Void)?
    @Environment(AppModel.self) private var app

    var body: some View {
        let owned = app.owns(heroID: hero.heroID)
        let skills = app.master.skills(forHero: hero.heroID).sorted { $0.slot.rawValue < $1.slot.rawValue }
        let roleColor = Theme.roleColor(hero.role)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header(owned: owned)
                if !owned, let pendingSKU, let item = StoreCatalog.unlockItem(heroID: hero.heroID, master: app.master) {
                    unlockButton(item: item, pendingSKU: pendingSKU)
                }
                HeroRatingBars(ratings: HeroRatingMath.ratings(for: hero, master: app.master))
                HStack(spacing: 0) {
                    ForEach(skills) { skill in
                        SkillIconButton(skill: skill, hero: hero, isSelected: skill.skillID == selectedSkillID,
                                        identifier: skillIDPrefix + skill.skillID) {
                            app.haptics.tap()
                            onSelectSkill(skill)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                actionRow
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .frame(width: SkillShowcaseStyle.infoPanelWidth)
        .frame(maxHeight: .infinity)
        .background(SkillShowcaseStyle.panelBackground(roleColor))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(roleColor.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // 名前・ロール（左）と 3D プレビュー（右）
    private func header(owned: Bool) -> some View {
        let roleColor = Theme.roleColor(hero.role)
        let sub = SkillTags.featureTags(hero: hero, master: app.master).map { SkillTags.name(for: $0) }
            .joined(separator: "/")
        return HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: Theme.roleSymbol(hero.role))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(roleColor)
                        .padding(.top, 3)
                    Text(MasterText.hero(hero))
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Rectangle()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
                HStack(spacing: 4) {
                    Text(MasterText.role(hero.role))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "tag.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(roleColor)
                }
                if !sub.isEmpty {
                    Text(sub)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if owned {
                    Label(L("所持済み", "Owned"), systemImage: "checkmark.seal.fill")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.success)
                }
            }
            Spacer(minLength: 0)
            if shows3DPreview {
                // 装備中のスキンで表示する 3D プレビュー（横ドラッグで回転）
                HeroPreview3DView(heroID: hero.heroID, skinID: app.profile.equippedSkins[hero.heroID])
                    .frame(width: 112, height: 110)
            } else {
                HeroPortraitView(heroID: hero.heroID, size: 64, showsRole: false)
            }
        }
    }

    private func unlockButton(item: StoreItemDef, pendingSKU: Binding<String?>) -> some View {
        Button {
            app.haptics.tap()
            pendingSKU.wrappedValue = item.sku
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "lock.open.fill")
                Text(L("解放", "Unlock"))
                Image(systemName: CollectionStyle.currencySymbol(item.currency))
                    .font(.system(size: 12, weight: .bold))
                Text(EconomyService.price(of: item).formatted())
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .buttonStyle(PrimaryButtonStyle())
        .frame(minHeight: 44)
        .accessibilityIdentifier("herodetail_unlock")
    }

    // 「練習場で試す」（元の「ヒーローの試練」の位置）と丸いショートカット
    private var actionRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Button {
                startPractice()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "figure.fencing")
                    Text(L("練習場で試す", "Try in Practice"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .font(Theme.body(12))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.46, blue: 0.82), Color(red: 0.14, green: 0.28, blue: 0.56)],
                                         startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Theme.cyan.opacity(0.55), lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("herodetail_practice")
            if let onQuickTab {
                quickButton(.skins, symbol: "paintpalette.fill", title: L("スキン", "Skins"), action: onQuickTab)
                quickButton(.build, symbol: "shippingbox.fill", title: L("ビルド", "Build"), action: onQuickTab)
                quickButton(.overview, symbol: "book.fill", title: L("伝記", "Lore"), action: onQuickTab)
            }
        }
    }

    private func quickButton(_ tab: HeroDetailTab, symbol: String, title: String,
                             action: @escaping (HeroDetailTab) -> Void) -> some View {
        Button {
            app.haptics.tap()
            action(tab)
        } label: {
            VStack(spacing: 1) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.10)))
                    .overlay(Circle().stroke(Theme.panelStroke, lineWidth: 1))
                Text(title)
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 38, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("herodetail_quick_\(tab.rawValue)")
    }

    private func startPractice() {
        app.haptics.impact()
        let name = app.profile.displayName.isEmpty ? "Player" : app.profile.displayName
        let config = MatchFactory.practiceMatch(humanHeroID: hero.heroID, humanName: name, options: PracticeOptions(),
                                                seed: UInt64.random(in: 1...UInt64.max))
        app.startBattle(BattleLaunch(config: config))
    }
}

// MARK: - 右パネル（スキル詳細）

/// スキル名・タグ・CD/コスト・説明・係数・レベル表。ランクの見出しをタップすると、その Lv の CD/コストを上の行に出す。
/// 呼び出し側で `.id(skill.skillID)` を付けること（スキルを替えたときに選択ランクを戻す）。
struct SkillShowcasePanel: View {
    let skill: SkillDef
    let hero: HeroDef
    @Environment(AppModel.self) private var app
    @State private var rank = 1
    /// フルモード = レベル表まで出す。ライトモード = 説明だけ。
    @AppStorage("skill_detail_full_mode") private var fullMode = true

    private static let labelWidth: CGFloat = 92

    var body: some View {
        let targeting = SkillCatalog.targeting(for: skill, hero: hero)
        let isPassive = skill.slot == .passive
        let tags = SkillTags.tags(for: skill, hero: hero, master: app.master)
        let table = SkillLevelTable.build(skill: skill, hero: hero)
        let figures = SkillMath.figures(skill, hero: hero, archetype: targeting.archetype)
        let r = table.ranks.isEmpty ? 1 : min(max(1, rank), table.ranks.count)
        VStack(spacing: 4) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    header(targeting: targeting, tags: tags, rank: r, isPassive: isPassive)
                    divider
                    Text(SkillShowcasePanel.styled(SkillMath.description(skill, hero: hero)))
                        .font(Theme.body(13))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("skilldetail_description")
                    if isPassive {
                        passiveInfo
                    } else {
                        coefficientLine(figures: figures)
                        if fullMode {
                            divider
                            levelTable(table, selectedRank: r)
                            notes(targeting: targeting)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
            if !isPassive { modeToggle }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SkillShowcaseStyle.glass.opacity(0.86)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.panelStroke, lineWidth: 1))
    }

    // MARK: ヘッダ

    private func header(targeting: SkillTargeting, tags: [String], rank: Int, isPassive: Bool) -> some View {
        let n = SkillMath.numbers(skill, hero: hero, rank: rank)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(CollectionStyle.slotName(skill.slot))
                    .font(Theme.body(10))
                    .foregroundStyle(CollectionStyle.slotColor(skill.slot))
                Text(MasterText.skill(skill))
                    .font(.system(size: 21, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    ForEach(tags, id: \.self) { SkillTagChip(key: $0) }
                }
                Group {
                    if isPassive {
                        Text(L("常時発動", "Always on"))
                    } else {
                        Text(SkillShowcaseText.statLine(cooldown: SkillMath.cooldown(skill, hero: hero, rank: rank),
                                                        cost: SkillMath.cost(skill, hero: hero, rank: rank),
                                                        resource: hero.resource))
                    }
                }
                .font(Theme.body(12))
                .foregroundStyle(Theme.textPrimary.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("skilldetail_statline")
            }
            Spacer(minLength: 4)
            // スキルの動き（元の「スキル動画」の枠）
            SkillShapeDiagram(archetype: targeting.archetype, range: targeting.range, radius: targeting.radius,
                              color: skill.slot == .ultimate ? Theme.gold : CollectionStyle.damageTypeColor(skill.damageType),
                              cc: n.cc)
                .frame(width: 112, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.panelStroke, lineWidth: 1))
                .accessibilityLabel(L("\(CollectionStyle.archetypeName(targeting.archetype)) の範囲図",
                                      "\(CollectionStyle.archetypeName(targeting.archetype)) shape diagram"))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Theme.panelStroke, Theme.panelStroke.opacity(0.15)], startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
    }

    /// 説明文を強調色の AttributedString にする。
    static func styled(_ text: String) -> AttributedString {
        var out = AttributedString()
        for seg in SkillDescriptionStyler.segments(text) {
            var piece = AttributedString(seg.text)
            piece.foregroundColor = SkillShowcaseStyle.color(for: seg.role)
            out.append(piece)
        }
        return out
    }

    // MARK: 係数・パッシブ

    @ViewBuilder
    private func coefficientLine(figures: [SkillMath.Figure]) -> some View {
        let parts = SkillCoefficient.parts(scaling: SkillMath.scaling(skill, hero: hero), figures: figures)
        if !parts.isEmpty {
            Text(Self.coefficientText(parts))
                .font(Theme.mono(12))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("skilldetail_scaling")
        }
    }

    static func coefficientText(_ parts: [SkillCoefficient]) -> AttributedString {
        var out = AttributedString(L("係数 ", "Scaling "))
        out.foregroundColor = Theme.textSecondary
        for p in parts {
            var piece = AttributedString("(\(p.text)) ")
            piece.foregroundColor = SkillShowcaseStyle.color(for: p.kind)
            out.append(piece)
        }
        return out
    }

    @ViewBuilder
    private var passiveInfo: some View {
        HStack(spacing: 6) {
            CollectionRoleTag(role: hero.role)
            // 固有係数はロール別の汎用パッシブの式（キットのパッシブには使わない）
            if !HeroKits.hasKit(hero.heroID) {
                CollectionInfoTag(text: L("固有係数 ×\(CollectionStyle.number(SkillMath.passiveCoefficient(heroNumber: hero.number), digits: 2))",
                                          "Hero factor ×\(CollectionStyle.number(SkillMath.passiveCoefficient(heroNumber: hero.number), digits: 2))"),
                                  symbol: "function", color: Theme.gold)
            }
        }
    }

    // MARK: レベル表

    private func levelTable(_ table: SkillLevelTable, selectedRank: Int) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.labelWidth, height: 1)
                ForEach(table.ranks, id: \.self) { r in
                    Button {
                        app.haptics.tap()
                        rank = r
                    } label: {
                        Text(SkillShowcaseText.rankTitle(r))
                            .font(Theme.body(12))
                            .foregroundStyle(r == selectedRank ? Theme.gold : Theme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(r == selectedRank ? .isSelected : [])
                    .accessibilityIdentifier("skilldetail_rank_\(r)")
                }
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { i, row in
                HStack(spacing: 0) {
                    Text(row.title)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.leading, 6)
                        .frame(width: Self.labelWidth, alignment: .leading)
                    ForEach(Array(row.values.enumerated()), id: \.offset) { j, value in
                        Text(value)
                            .font(Theme.mono(13))
                            .foregroundStyle(j + 1 == selectedRank ? Theme.gold : Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(i % 2 == 0 ? 0.10 : 0)))
            }
        }
    }

    /// 表に出ない効果（割合ダメージ・自身のシールドなど）・CC の詳細・習得レベルの補足。
    @ViewBuilder
    private func notes(targeting: SkillTargeting) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            noteText(aimLine(targeting: targeting))
            if let note = rankNote(targeting: targeting) { noteText(note) }
            if !HeroKits.hasKit(hero.heroID), skill.cc != .none {
                noteText("\(CollectionStyle.ccName(skill.cc)): \(SkillMath.ccDetail(skill.cc, isUltimate: skill.slot == .ultimate))")
            }
            noteText(L("係数はスロット倍率・アーキタイプ補正込み。CD 短縮は最大 \(Int(Balance.maxCooldownReduction * 100))% まで適用",
                       "Ratios include slot and archetype multipliers. Cooldown reduction caps at \(Int(Balance.maxCooldownReduction * 100))%"))
            if skill.slot == .ultimate {
                noteText(L("アルティメットは Lv \(Balance.ultimateUnlockLevels.map(String.init).joined(separator: "/")) で習得可能",
                           "Ultimate ranks unlock at Lv \(Balance.ultimateUnlockLevels.map(String.init).joined(separator: "/"))"))
            }
        }
    }

    /// 照準の形・射程・効果半径（キットは照準の形の名前、それ以外はアーキタイプの名前）。
    private func aimLine(targeting: SkillTargeting) -> String {
        let shape = HeroKits.hasKit(hero.heroID)
            ? (SkillMath.shapeName(targeting.shape) ?? CollectionStyle.archetypeName(targeting.archetype))
            : CollectionStyle.archetypeName(targeting.archetype)
        let range = CollectionStyle.number(targeting.range, digits: 0)
        let radius = CollectionStyle.number(targeting.radius, digits: 0)
        let allies = targeting.targetsAllies ? L("　味方対象", "  Targets allies") : ""
        return L("\(shape)　射程 \(range)　効果半径 \(radius)\(allies)", "\(shape)  Range \(range)  Radius \(radius)\(allies)")
    }

    private func noteText(_ s: String) -> some View {
        Text(s)
            .font(Theme.body(10))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func rankNote(targeting: SkillTargeting) -> String? {
        // 汎用アーキタイプの補足（割合ダメージ・自身のシールドなど）はキットには当てはまらない
        guard !HeroKits.hasKit(hero.heroID) else { return nil }
        let n = SkillMath.numbers(skill, hero: hero, rank: 1)
        let pct = { (v: Double) in CollectionStyle.number(v * 100, digits: 1) }
        switch targeting.archetype {
        case .targetedBlink:
            return L("＋ 対象の失った HP の \(pct(n.missingHealthRatio))%", "+ \(pct(n.missingHealthRatio))% of the target's missing HP")
        case .selfAoE:
            return L("自身に最大 HP の \(pct(Balance.Skills.selfShieldMaxHPRatio))% のシールド（\(CollectionStyle.seconds(n.shieldDuration))）",
                     "Self shield: \(pct(Balance.Skills.selfShieldMaxHPRatio))% of max HP (\(CollectionStyle.seconds(n.shieldDuration)))")
        case .multiStrike:
            return L("ダメージは「回数×1 撃」。自身の被ダメージ −\(pct(n.damageReduction))%（\(CollectionStyle.seconds(n.damageReductionDuration))）",
                     "Damage is hits × per-hit damage. Self damage taken −\(pct(n.damageReduction))% (\(CollectionStyle.seconds(n.damageReductionDuration)))")
        case .blinkEmpower:
            return L("ブリンク後 \(CollectionStyle.seconds(Balance.Skills.empowerDuration)) 以内の次の通常攻撃に上乗せ",
                     "Added to your next basic attack within \(CollectionStyle.seconds(Balance.Skills.empowerDuration)) of blinking")
        case .teamHeal, .healZone:
            return L("回復・シールドは味方 1 体あたり", "Heal and shield are per ally")
        default:
            return nil
        }
    }

    // MARK: ライト / フル

    private var modeToggle: some View {
        HStack(spacing: 0) {
            Spacer()
            modeButton(title: L("ライトモード", "Light"), full: false)
            modeButton(title: L("フルモード", "Full"), full: true)
        }
    }

    private func modeButton(title: String, full: Bool) -> some View {
        let selected = fullMode == full
        return Button {
            app.haptics.tap()
            fullMode = full
        } label: {
            Text(title)
                .font(Theme.body(12))
                .foregroundStyle(selected ? Color.white : Theme.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Rectangle().fill(selected ? Color(red: 0.25, green: 0.45, blue: 0.85) : Color.clear))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(full ? "skilldetail_mode_full" : "skilldetail_mode_light")
    }
}
