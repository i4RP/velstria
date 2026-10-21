import SwiftUI
import VelstriaCore

/// 敵の確定済みピックから、その場でヒーローとスキルを確認する。
struct EnemyHeroPreviewButton<Label: View>: View {
    let heroID: String
    @ViewBuilder var label: () -> Label
    @Environment(AppModel.self) private var app
    @State private var showsPreview = false

    var body: some View {
        Button {
            FlowFX.tap(app)
            showsPreview = true
        } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(app.master.hero(heroID) == nil)
        .accessibilityHint(L("ヒーローとスキルの詳細を表示", "Show hero and skill details"))
        .popover(isPresented: $showsPreview, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            if let hero = app.master.hero(heroID) {
                EnemyHeroPreview(hero: hero)
                    .id(heroID)
                    .environment(app)
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(SkillShowcaseStyle.glass)
                    .preferredColorScheme(.dark)
            }
        }
        .onChange(of: heroID) { _, _ in showsPreview = false }
    }
}

/// 図鑑と同じアイコン・実戦値の説明を使う軽量な詳細カード。3D モデルはロードしない。
private struct EnemyHeroPreview: View {
    let hero: HeroDef
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSkillID: String?

    var body: some View {
        let skills = app.master.skills(forHero: hero.heroID).sorted { $0.slot.rawValue < $1.slot.rawValue }
        let selected = skills.first { $0.skillID == selectedSkillID } ?? skills.first
        VStack(alignment: .leading, spacing: 8) {
            header
            recommendedPosition
            HStack(spacing: 0) {
                ForEach(skills) { skill in
                    SkillIconButton(skill: skill, hero: hero, isSelected: selected?.skillID == skill.skillID,
                                    identifier: "flow_enemy_skill_\(skill.slot.rawValue)") {
                        FlowFX.tap(app)
                        selectedSkillID = skill.skillID
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 2)
            Rectangle().fill(Theme.cyan.opacity(0.45)).frame(height: 1)
            if let selected {
                skillDetail(selected)
                    .id(selected.skillID)
            }
        }
        .padding(12)
        .frame(width: 340, height: 320, alignment: .topLeading)
        .background(SkillShowcaseStyle.panelBackground())
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cyan.opacity(0.5)))
        .accessibilityIdentifier("flow_enemy_preview")
    }

    private var header: some View {
        let features = SkillTags.featureTags(hero: hero, master: app.master)
            .map { SkillTags.name(for: $0) }.joined(separator: " / ")
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 10) {
                HeroPortraitView(heroID: hero.heroID, size: 44, showsRole: false)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.cyan.opacity(0.7), lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 3) {
                    Text(MasterText.hero(hero))
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .accessibilityIdentifier("flow_enemy_hero_name")
                    RoleLabel(role: hero.role, size: 11)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    FlowFX.back(app)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("閉じる", "Close"))
                .accessibilityIdentifier("flow_enemy_preview_close")
            }
            if !features.isEmpty {
                Text(features)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var recommendedPosition: some View {
        let position = MatchFactory.defaultPosition(for: hero.role)
        return HStack(spacing: 6) {
            Text(L("おすすめ：", "Recommended:"))
            Text(FlowText.position(position))
            Spacer(minLength: 0)
            Image(systemName: FlowText.positionSymbol(position))
                .foregroundStyle(Theme.cyan)
        }
        .font(Theme.heading(12))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.cyan.opacity(0.16))
    }

    private func skillDetail(_ skill: SkillDef) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(MasterText.skill(skill))
                    .font(Theme.heading(15))
                    .foregroundStyle(Theme.cyan)
                    .accessibilityIdentifier("flow_enemy_skill_name")
                HStack(spacing: 5) {
                    Text(CollectionStyle.slotName(skill.slot))
                        .font(Theme.body(10))
                        .foregroundStyle(CollectionStyle.slotColor(skill.slot))
                    ForEach(SkillTags.tags(for: skill, hero: hero, master: app.master), id: \.self) { tag in
                        SkillTagChip(key: tag)
                    }
                }
                if skill.slot != .passive {
                    Text(SkillShowcaseText.statLine(cooldown: SkillMath.cooldown(skill, hero: hero, rank: 1),
                                                    cost: SkillMath.cost(skill, hero: hero, rank: 1),
                                                    resource: hero.resource))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(SkillShowcasePanel.styled(SkillMath.description(skill, hero: hero)))
                    .font(Theme.body(12))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("flow_enemy_skill_description")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
