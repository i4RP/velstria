import SwiftUI
import VelstriaCore

// 担当: battle-hud。UI030 ポーズメニュー: 再開・クイック設定（BGM/SFX 音量・ダメージ数値・カメラ距離）・
// 降参（UI031、通常戦/ランク戦で 8:00 以降）・退出（確認つき。通常戦/ランク戦は敗北扱いの警告）。
// 開いている間は controller.isPaused = true（オフラインなので全体が止まる）。

struct HUDPauseMenu: View {
    let model: HUDModel

    var body: some View {
        let settings = model.settings
        let ranked = model.mode == .standard || model.mode == .ranked || model.mode == .online
        HStack(alignment: .top, spacing: 14) {
            // 左: 操作
            VStack(alignment: .leading, spacing: 10) {
                Text(model.controller.isOnline ? (model.isSpectating ? L("観戦メニュー", "Spectator Menu") : L("メニュー", "Menu"))
                     : (model.isSpectating ? L("観戦を一時停止中", "Spectating Paused") : L("一時停止中", "Paused")))
                    .font(Theme.title(22))
                    .foregroundStyle(.white)
                Text(modeName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.gold)
                if model.controller.isOnline {
                    Text(L("オンライン対戦中は試合は止まりません", "The match keeps running while this menu is open"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Button { model.resume() } label: {
                    Label(L("再開", "Resume"), systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("pause_resume")
                if ranked && !model.isSpectating {
                    surrenderButton
                }
                Spacer(minLength: 0)
                Button { model.confirmingLeave = true } label: {
                    Label(L("退出", "Leave Match"), systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("pause_leave")
            }
            .frame(width: 220)
            // 右: クイック設定
            VStack(alignment: .leading, spacing: 8) {
                Text(L("クイック設定", "Quick Settings"))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                sliderRow(L("BGM 音量", "Music Volume"), symbol: "music.note", value: settings.bgmVolume, range: 0...1,
                          format: { "\(Int(($0 * 100).rounded()))%" }, id: "pause_bgm") { model.updateSetting(\.bgmVolume, $0) }
                sliderRow(L("効果音量", "Sound Effects"), symbol: "speaker.wave.2.fill", value: settings.sfxVolume, range: 0...1,
                          format: { "\(Int(($0 * 100).rounded()))%" }, id: "pause_sfx") { model.updateSetting(\.sfxVolume, $0) }
                sliderRow(L("カメラ距離", "Camera Distance"), symbol: "camera.metering.center.weighted",
                          value: settings.cameraZoom, range: 0.8...1.3, format: { String(format: "×%.2f", $0) },
                          id: "pause_camera") { model.updateSetting(\.cameraZoom, ($0 * 20).rounded() / 20) }
                Toggle(isOn: Binding(get: { settings.showDamageNumbers },
                                     set: { model.updateSetting(\.showDamageNumbers, $0) })) {
                    Label(L("ダメージ数値", "Damage Numbers"), systemImage: "textformat.123")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .tint(Theme.gold)
                .frame(minHeight: 44)
                .accessibilityIdentifier("pause_damage_numbers")
            }
            .frame(width: 280)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.09, green: 0.10, blue: 0.22).opacity(0.97),
                                              Color(red: 0.03, green: 0.03, blue: 0.09).opacity(0.97)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.gold.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.7), radius: 24)
        .overlay {
            if model.confirmingLeave {
                leaveConfirm
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: model.confirmingLeave)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pause_menu")
    }

    private var modeName: String {
        // リプレイは記録時の設定（通常戦・ランク戦など）のまま起動するので、モードより先に判定する
        if model.controller.isReplay { return L("リプレイ", "Replay") }
        switch model.mode {
        case .standard: return L("通常戦", "Standard Match")
        case .ranked: return L("ランク戦", "Ranked Match")
        case .practice: return L("練習場", "Practice")
        case .tutorial: return L("チュートリアル", "Tutorial")
        case .spectate: return L("観戦", "Spectate")
        case .brawl: return L("乱闘", "Brawl")
        case .custom: return L("カスタム", "Custom Match")
        case .magicChess: return L("マジックチェス", "Magic Chess")
        case .online: return L("オンライン対戦", "Online Match")
        }
    }

    private var surrenderButton: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button { model.proposeSurrender() } label: {
                Label(L("降参を提案", "Propose Surrender"), systemImage: "flag.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!model.canProposeSurrender)
            .opacity(model.canProposeSurrender ? 1 : 0.5)
            .accessibilityIdentifier("pause_surrender")
            if !model.canProposeSurrender {
                Text(surrenderHint)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var surrenderHint: String {
        if model.surrender != nil { return L("投票中です", "A vote is in progress") }
        if let wait = model.surrenderAvailableIn, wait > 0 {
            return L("あと \(HUDStyle.clock(Double(wait))) で提案できます", "Available in \(HUDStyle.clock(Double(wait)))")
        }
        return L("8:00 以降に提案できます", "Available after 8:00")
    }

    private func sliderRow(_ title: String, symbol: String, value: Double, range: ClosedRange<Double>,
                           format: @escaping (Double) -> String, id: String,
                           set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(Theme.gold)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            Slider(value: Binding(get: { value }, set: set), in: range)
                .tint(Theme.gold)
                .accessibilityLabel(title)
                .accessibilityIdentifier(id)
        }
    }

    private var leaveConfirm: some View {
        let countsAsLoss = (model.mode == .standard || model.mode == .ranked) && !model.isSpectating
        return VStack(spacing: 12) {
            Image(systemName: countsAsLoss ? "exclamationmark.triangle.fill" : "rectangle.portrait.and.arrow.right")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(countsAsLoss ? Theme.danger : Theme.gold)
            Text(L("試合から退出しますか？", "Leave the match?"))
                .font(Theme.heading(18))
                .foregroundStyle(.white)
            Text(countsAsLoss ? L("途中で退出すると敗北として記録され、報酬は獲得できません。", "Leaving now counts as a loss and grants no rewards.")
                              : L("進行状況は保存されません。", "Your progress in this session won't be kept."))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button { model.confirmingLeave = false } label: {
                    Text(L("キャンセル", "Cancel")).frame(minWidth: 110)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("leave_cancel")
                Button { model.leave() } label: {
                    Text(countsAsLoss ? L("退出（敗北）", "Leave (Loss)") : L("退出", "Leave")).frame(minWidth: 110)
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.danger))
                .accessibilityIdentifier("leave_confirm")
            }
        }
        .padding(22)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(red: 0.06, green: 0.06, blue: 0.14)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.danger.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.8), radius: 20)
    }
}
