import SwiftUI
import VelstriaCore

// 試合の外でエモートを出す部品（MLBB と同じく、パーティ・選択・ロード・リザルトで装備した 4 枠のエモートを出せる）。
// 押すと装備したエモートが並び、選ぶと onSend に ID を渡す。出した側はふきだし（EmoteBubble）を自分の枠の上に数秒出す。

/// エモートのボタン（装備が無ければボタンを出さない）。
struct EmoteMenuButton: View {
    let onSend: (String) -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let emotes = app.profile.equippedEmotes.compactMap { app.master.cosmetic($0) }
        if !emotes.isEmpty {
            Menu {
                ForEach(emotes) { c in
                    Button(MasterText.cosmetic(c)) {
                        FlowFX.tap(app)
                        onSend(c.cosmeticID)
                    }
                }
            } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 18))
                    .foregroundStyle(Celestial.ice)
                    .frame(width: 44, height: 36)
                    .background(HomeChamfer(cut: 6).fill(Celestial.ink.opacity(0.85)))
                    .overlay(HomeChamfer(cut: 6).stroke(Celestial.ice.opacity(0.5), lineWidth: 0.6))
            }
            .accessibilityLabel(L("エモート", "Emotes"))
            .accessibilityIdentifier("emote_menu")
        }
    }
}

/// エモートのふきだし（コスメの絵。出てから数秒で消すのは置く側）。
struct EmoteBubble: View {
    let cosmeticID: String
    var size: CGFloat = 44
    @Environment(AppModel.self) private var app

    var body: some View {
        if let c = app.master.cosmetic(cosmeticID) {
            CosmeticPreviewView(cosmetic: c, size: size)
                .shadow(color: .black.opacity(0.5), radius: 4)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
                .accessibilityLabel(MasterText.cosmetic(c))
                .accessibilityIdentifier("emote_bubble")
        }
    }
}

/// 出したエモートを数秒で消す（表示中のエモートの ID）。
@MainActor
enum EmoteTiming {
    static let seconds: Double = 2.5

    /// shown に id を入れ、数秒後に同じ id のままなら消す。
    static func show(_ id: String, in shown: Binding<String?>) {
        withAnimation(.spring(duration: 0.3, bounce: 0.4)) { shown.wrappedValue = id }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if shown.wrappedValue == id {
                withAnimation(.easeOut(duration: 0.25)) { shown.wrappedValue = nil }
            }
        }
    }
}
