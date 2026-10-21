import SwiftUI
import VelstriaCore

// 担当: ui-flow。ヒーロー選択とドラフトに共通の部品（MLBB の選択画面の作り）:
// 上の中央の段階の文と大きな残り秒数・レーン別のヒーローのタブ・定型文のチャット欄。

/// 選択の持ち時間（MLBB と同じ形: ピックの持ち時間と、ピックの後の最終調整）。
enum FlowTiming {
    static let pickSeconds = 30
    static let adjustSeconds = 25
}

/// 上の中央: 段階の文（「ヒーローPICK（敵）」「試合はまもなく始まります。進む：ローム」）と大きな残り秒数。
struct PickPhaseHeader<Leading: View, Trailing: View>: View {
    let phase: String
    /// 残り秒数（nil = 出さない）。
    let seconds: Int?
    var urgent = false
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Text(phase)
                    .font(Celestial.heading(15))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let seconds {
                    Text("\(seconds)")
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .monospacedDigit()
                        .foregroundStyle(urgent ? Theme.danger : HomeStyle.goldLight)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.linear(duration: 0.3), value: seconds)
                        .accessibilityLabel(L("残り \(seconds) 秒", "\(seconds) seconds left"))
                        .accessibilityIdentifier("flow_draft_timer")
                }
            }
            .padding(.horizontal, 120)
            HStack {
                leading()
                Spacer()
                trailing()
            }
        }
        .frame(minHeight: 50)
    }
}

/// ヒーロー一覧のレーン別のタブ（「全部」つき。MLBB と同じ）。レーンに合うロールのヒーローだけを出す。
struct LaneFilterBar: View {
    @Binding var selection: LanePosition?
    @Environment(AppModel.self) private var app

    var body: some View {
        CelestialTabs(options: [CelestialTab<LanePosition?>(value: nil, title: L("すべてのレーン", "All Lanes"), symbol: nil, identifier: "flow_lanetab_all")]
                        + LanePosition.allCases.map {
                            CelestialTab<LanePosition?>(value: $0, title: FlowText.position($0), symbol: nil, identifier: "flow_lanetab_\($0.rawValue)")
                        },
                      selection: $selection, fills: false, onChange: { _ in app.audio.play(.uiTab) })
    }

    /// タブの絞り込み。
    static func matches(_ hero: HeroDef, lane: LanePosition?) -> Bool {
        guard let lane else { return true }
        return MatchFactory.preferredRoles(for: lane).contains(hero.role)
    }
}

/// 定型文のボタン（押すと一覧。自由入力は無い）。オンラインでは番号だけを送る。
struct QuickChatMenu: View {
    var identifier = "flow_quickchat"
    let onSend: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(QuickChat.phrases.indices, id: \.self) { i in
                Button(QuickChat.text(i)) { onSend(i) }
            }
        } label: {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 18))
                .foregroundStyle(Celestial.ice)
                .frame(width: 44, height: 36)
                .background(HomeChamfer(cut: 6).fill(Celestial.ink.opacity(0.85)))
                .overlay(HomeChamfer(cut: 6).stroke(Celestial.ice.opacity(0.5), lineWidth: 0.6))
        }
        .accessibilityLabel(L("クイックチャット", "Quick chat"))
        .accessibilityIdentifier(identifier)
    }
}

/// 最新の発言 2 行（自分は金、味方は緑）。
struct QuickChatLines: View {
    let lines: [FlowChatLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(lines.suffix(2)) { line in
                (Text(line.speaker + "：").foregroundStyle(line.isMine ? Theme.gold : Theme.success)
                    + Text(line.text).foregroundStyle(Theme.textPrimary))
                    .font(Theme.body(12))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: lines.count)
    }
}

/// 下のチャット欄: 最新の発言と、定型文を送るボタン（自由入力は無い）。味方の AI が返事をする。
struct QuickChatBar: View {
    @Bindable var model: MatchFlowModel
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            QuickChatMenu { send($0) }
            EmoteMenuButton { id in EmoteTiming.show(id, in: $model.myEmote) }
            QuickChatLines(lines: model.chat)
        }
        .frame(height: 38)
    }

    /// 定型文を送る。オフラインの AI 戦では、味方の AI の 1 人が少し後に返事をする。
    private func send(_ index: Int) {
        FlowFX.tap(app)
        let me = app.profile.displayName.isEmpty ? L("あなた", "You") : app.profile.displayName
        model.chat.append(FlowChatLine(speaker: me, text: QuickChat.text(index), isMine: true))
        guard let reply = QuickChat.aiReply(to: index) else { return }
        let speaker = L("味方 AI", "Ally AI")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            model.chat.append(FlowChatLine(speaker: speaker, text: reply, isMine: false))
        }
    }
}
