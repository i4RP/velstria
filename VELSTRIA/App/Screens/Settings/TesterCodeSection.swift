import SwiftUI
import VelstriaCore

// 担当: 統合。設定画面の「テスター用コード」欄（内部テスト用ビルドだけ。TesterAccess 参照）。

struct TesterCodeSection: View {
    @Environment(AppModel.self) private var app
    @State private var code = ""
    @State private var unlocked = TesterAccess.isUnlocked()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("テスター用コード", "Tester code"))
                .font(Theme.heading(14))
                .foregroundStyle(Theme.textSecondary)
            if unlocked {
                Text(L("全ヒーローを解放済みです（この端末のみ）", "All heroes unlocked (this device only)"))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.cyan)
                    .accessibilityIdentifier("tester_unlocked")
            } else {
                HStack(spacing: 10) {
                    TextField(L("コードを入力", "Enter code"), text: $code)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("tester_code_field")
                    Button {
                        redeem()
                    } label: {
                        Text(L("適用", "Apply")).lineLimit(1)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("tester_code_apply")
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }

    private func redeem() {
        if TesterAccess.redeem(code) {
            TesterAccess.grantAllHeroes(to: &app.profile, master: app.master)
            unlocked = true
            code = ""
            app.audio.play(.uiConfirm)
            app.showToast(L("全ヒーローを解放しました", "All heroes unlocked"))
        } else {
            app.audio.play(.uiTap)
            app.showToast(L("コードが正しくありません", "Invalid code"))
        }
    }
}
