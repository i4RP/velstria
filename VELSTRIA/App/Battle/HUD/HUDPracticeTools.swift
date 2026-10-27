import SwiftUI
import VelstriaCore

/// 練習場だけの操作。既存の 15 Hz HUD スナップショットを使い、ポップオーバー中も試合を進める。
struct HUDPracticeToolsButton: View {
    let model: HUDModel
    @State private var isPresented = false

    var body: some View {
        if model.mode == .practice, !model.isSpectating, !model.controller.isOnline {
            Button {
                model.cancelAim()
                isPresented = true
            } label: {
                Label(L("練習設定", "Practice"), systemImage: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.45), in: Capsule())
                    .frame(width: 90, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HUDPressStyle())
            .disabled(!model.canControl)
            .accessibilityIdentifier("hud_practice")
            .popover(isPresented: $isPresented) {
                tools
                    .presentationCompactAdaptation(.popover)
                    .preferredColorScheme(.dark)
            }
        }
    }

    private var tools: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L("練習設定", "Practice Tools")).font(Theme.title(18))
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark").frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(L("閉じる", "Close"))
                    .accessibilityIdentifier("practice_close")
                }
                HStack(spacing: 8) {
                    action("−", id: "practice_level_down", disabled: model.hero.level <= 1) {
                        send(.setLevel(model.hero.level - 1))
                    }
                    Text("Lv \(model.hero.level)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit().frame(maxWidth: .infinity)
                        .accessibilityIdentifier("practice_level")
                    action("+", id: "practice_level_up", disabled: model.hero.level >= Balance.maxLevel) {
                        send(.setLevel(model.hero.level + 1))
                    }
                    action(L("最大", "Max"), id: "practice_level_max", disabled: model.hero.level >= Balance.maxLevel) {
                        send(.setLevel(Balance.maxLevel))
                    }
                }
                HStack {
                    action(L("Lv 1 に戻す", "Reset to Lv 1"), id: "practice_level_reset", disabled: model.hero.level == 1) {
                        send(.setLevel(1))
                    }
                    Text(L("下げるとスキルを振り直せます", "Lowering resets skill allocation"))
                        .font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
                }
                HStack {
                    Text(L("スキル残り \(model.hero.skillPoints) pt", "Skill points: \(model.hero.skillPoints)"))
                        .font(Theme.body(11))
                    Spacer()
                    action(L("振り直し", "Reset"), id: "practice_skills_reset") { send(.resetSkills) }
                    action(L("自動配分", "Allocate"), id: "practice_skills_learn", disabled: model.hero.skillPoints == 0) {
                        send(.learnSkills)
                    }
                }
                Divider()
                HStack {
                    Text(L("装備 \(model.hero.items.count)/\(Balance.itemSlots)", "Items \(model.hero.items.count)/\(Balance.itemSlots)"))
                        .font(Theme.body(11))
                    Spacer()
                    action(L("全解除", "Clear"), id: "practice_items_clear", disabled: model.hero.items.isEmpty) {
                        send(.clearItems)
                    }
                    action(L("ショップ", "Shop"), id: "practice_shop") {
                        isPresented = false
                        model.openShop()
                    }
                }
                if model.controller.launch.config.practice?.infiniteGold == true {
                    Text(L("ゴールド無限 · 売却・全解除で何度でも装備を試せます", "Unlimited gold · Sell or clear items to try another build"))
                        .font(Theme.body(10)).foregroundStyle(Theme.gold)
                } else {
                    action(L("ゴールド補充（99,999）", "Refill gold (99,999)"), id: "practice_gold") {
                        send(.refillGold)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 330, height: 310)
        .background(Theme.bgTop)
        .accessibilityIdentifier("practice_tools")
    }

    private func send(_ command: PracticeCommand) {
        guard model.mode == .practice, model.canControl, !model.controller.isOnline else { return }
        model.controller.send(.practice(command))
        model.selectionFeedback()
    }

    private func action(_ title: String, id: String, disabled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(Theme.body(11))
            .buttonStyle(.bordered)
            .tint(Theme.cyan)
            .disabled(disabled)
            .accessibilityIdentifier(id)
    }
}
