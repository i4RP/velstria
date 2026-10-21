import SwiftUI
import VelstriaCore

// 担当: ui-flow。対戦フローのレーン選択・マッチング・承認（MLBB 2.2.16 の作り。docs/OUTGAME_GAP.md「委員会の調べ」）。
// レーン選択: 縦長のカード 6 枚（Expレーン／ジャングル／ミドルレーン／ローム／ゴールドレーン／フレックスプロ）から 2〜5 本。
//   人の足りないレーン（AI 戦なので試合ごとに 1 つ）に「必要なレーン」の吹き出し。必要なレーンだけは 1 本で確定できる。
// マッチング: 上端の中央に赤橙の札「推定所要時間 00:09 ✕」と大きな経過時間。見つかると「マッチング成功」。
// 承認: 中央の逆三角の水晶に残り秒（30 から）と緑の「n/10」、左右に 5 枚ずつの札（承認した人から顔に）。黄色の「スタート」→
//   「他のプレイヤー待ち」。0 秒まで承認しなければロビー（モード選択）へ。承認の後「現在のレーン：○○」を少し出してからピックへ。
// 相手は今のところ AI なので、待ちも承認も数秒。音と振動は今ある物（matchFound・countdown・success）を鳴らす。

// MARK: - レーン選択

/// レーン選択の規則（MLBB: 2〜5 本。必要なレーンは 1 本で確定。フレックスプロはどのレーンでも）。
enum LaneSelectRules {
    /// MLBB の並び（Exp・ジャングル・ミドル・ローム・ゴールド）。
    static let order: [LanePosition] = [.top, .jungle, .mid, .support, .carry]

    /// 人の足りないレーン（AI 戦なので試合のシードで 1 つ選ぶ）。
    static func neededLane(seed: UInt64) -> LanePosition {
        order[Int(seed % UInt64(order.count))]
    }

    /// 確定できるか。
    static func canConfirm(lanes: [LanePosition], flex: Bool, needed: LanePosition) -> Bool {
        flex || lanes.count >= 2 || lanes == [needed]
    }

    /// 保存の形（"flex" か、レーンの番号の並び "0,2"）。
    static func encode(lanes: [LanePosition], flex: Bool) -> String {
        flex ? "flex" : lanes.map { String($0.rawValue) }.joined(separator: ",")
    }

    static func decode(_ s: String) -> (lanes: [LanePosition], flex: Bool) {
        if s == "flex" || s.isEmpty { return ([], true) }
        var out: [LanePosition] = []
        for part in s.split(separator: ",") {
            if let n = Int(part), let lane = LanePosition(rawValue: n), !out.contains(lane) { out.append(lane) }
        }
        return out.isEmpty ? ([], true) : (out, false)
    }
}

struct LaneSelectStep: View {
    @Bindable var model: MatchFlowModel
    @Environment(AppModel.self) private var app
    /// 前回選んだレーン（LaneSelectRules.encode の形）。
    @AppStorage("outgame.laneChoices") private var saved = "flex"
    @State private var lanes: [LanePosition] = []
    @State private var flex = true
    @State private var loaded = false

    private var needed: LanePosition { LaneSelectRules.neededLane(seed: model.seed) }
    private var canConfirm: Bool { LaneSelectRules.canConfirm(lanes: lanes, flex: flex, needed: needed) }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Text(L("レーンを選択", "Choose Lanes"))
                    .font(Celestial.title(21))
                    .foregroundStyle(Theme.textPrimary)
                HStack {
                    backButton
                    Spacer()
                    Text(FlowText.mode(model.kind == .ranked ? .ranked : .standard))
                        .font(Celestial.heading(13))
                        .foregroundStyle(HomeStyle.goldLight)
                }
            }
            HStack(spacing: 10) {
                ForEach(LaneSelectRules.order, id: \.self) { laneCard($0) }
                flexCard
            }
            .padding(.top, 26)
            .frame(maxHeight: .infinity)
            Text(L("推定所要時間 00:\(String(format: "%02d", model.matchWaitSeconds + 10))",
                   "Estimated time 00:\(String(format: "%02d", model.matchWaitSeconds + 10))"))
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 12) {
                Text(canConfirm ? summary : L("レーンを 2 つ以上選んでください（必要なレーンは 1 つで OK）",
                                              "Pick at least 2 lanes (the needed lane alone is fine)"))
                    .font(Celestial.heading(12))
                    .foregroundStyle(canConfirm ? Celestial.ice : Theme.danger)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: startMatching) {
                    Text("OK")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(Color(red: 0.25, green: 0.15, blue: 0.03))
                        .frame(width: 190, height: 42)
                        .background(HomeChamfer(cut: 8).fill(LinearGradient(colors: [HomeStyle.goldLight, Theme.gold], startPoint: .top, endPoint: .bottom)))
                        .overlay(HomeChamfer(cut: 8).stroke(Color.white.opacity(0.7), lineWidth: 1))
                        .opacity(canConfirm ? 1 : 0.45)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canConfirm)
                .accessibilityLabel("OK")
                .accessibilityIdentifier("flow_lane_start")
                Spacer().frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let s = LaneSelectRules.decode(saved)
            lanes = s.lanes
            flex = s.flex
        }
    }

    private var summary: String {
        if flex { return L("フレックスプロ（どのレーンでも）", "Flex Pro (any lane)") }
        return lanes.map(FlowText.position).joined(separator: " · ")
    }

    private var backButton: some View {
        Button(action: back) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(HomeStyle.goldLight)
                .frame(width: 48, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("戻る", "Back"))
        .accessibilityIdentifier("flow_back")
    }

    private func laneCard(_ lane: LanePosition) -> some View {
        let selected = !flex && lanes.contains(lane)
        return Button { tapLane(lane) } label: {
            card(symbol: FlowText.positionSymbol(lane), title: FlowText.position(lane), selected: selected, gold: false)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if lane == needed {
                VStack(spacing: 1) {
                    Text(L("必要なレーン", "Needed"))
                        .font(Celestial.heading(11))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.08, green: 0.22, blue: 0.42)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Celestial.ice.opacity(0.8), lineWidth: 1))
                .offset(y: -24)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(FlowText.position(lane) + (lane == needed ? L("、必要なレーン", ", needed") : ""))
        .accessibilityIdentifier("flow_lane_\(lane.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var flexCard: some View {
        Button {
            FlowFX.tap(app)
            withAnimation(.spring(duration: 0.25)) {
                flex.toggle()
                if flex { lanes = [] }
            }
        } label: {
            card(symbol: "square.grid.2x2.fill", title: L("フレックスプロ", "Flex Pro"), selected: flex, gold: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("flow_lane_any")
        .accessibilityAddTraits(flex ? .isSelected : [])
    }

    /// 縦長のカード（選ぶと水色の枠と ✓）。
    private func card(symbol: String, title: String, selected: Bool, gold: Bool) -> some View {
        let tint = gold ? HomeStyle.goldLight : Celestial.ice
        return VStack(spacing: 8) {
            Spacer(minLength: 4)
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 54, height: 54)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
            Text(title)
                .font(Celestial.heading(13))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            Image(systemName: selected ? "checkmark.diamond.fill" : "diamond")
                .font(.system(size: 20))
                .foregroundStyle(selected ? Color(red: 0.55, green: 0.90, blue: 1) : Theme.textSecondary.opacity(0.5))
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.10, green: 0.24, blue: 0.40).opacity(selected ? 0.85 : 0.55)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(selected ? Color(red: 0.45, green: 0.85, blue: 1) : Celestial.ice.opacity(0.25),
                                                          lineWidth: selected ? 2.5 : 1))
        .shadow(color: selected ? Color(red: 0.4, green: 0.8, blue: 1).opacity(0.6) : .clear, radius: 8)
        .contentShape(Rectangle())
    }

    /// レーンを足す・外す（フレックスプロは外れる。5 本まで）。
    private func tapLane(_ lane: LanePosition) {
        FlowFX.tap(app)
        withAnimation(.spring(duration: 0.25)) {
            if flex {
                flex = false
                lanes = [lane]
            } else if let i = lanes.firstIndex(of: lane) {
                lanes.remove(at: i)
            } else if lanes.count < 5 {
                lanes.append(lane)
            }
        }
    }

    private func back() {
        FlowFX.back(app)
        model.step = .mode
    }

    private func startMatching() {
        guard canConfirm else { return }
        FlowFX.confirm(app)
        saved = LaneSelectRules.encode(lanes: lanes, flex: flex)
        model.lanePrimary = flex ? nil : lanes.first
        model.laneSecondary = flex ? nil : lanes.dropFirst().first
        model.step = .matching
    }
}

// MARK: - マッチング・承認

extension MatchFlowModel {
    /// AI 戦の待ち（秒）。シードで 2〜4 秒。
    var matchWaitSeconds: Int { 2 + Int(seed % 3) }
}

struct MatchingStep: View {
    @Bindable var model: MatchFlowModel
    @Environment(AppModel.self) private var app
    @State private var elapsed = 0
    @State private var found = false
    @State private var accepted = false
    /// 承認した人数（自分を含む。10 で全員）。
    @State private var acceptedCount = 0
    @State private var deadline = MatchingStep.acceptSeconds
    /// 承認の後の「現在のレーン」の表示。
    @State private var announcing = false

    /// 承認の締め切り（秒。MLBB は 30 から減る）。
    static let acceptSeconds = 30
    /// 「現在のレーン」を出しておく時間（秒）。
    static let laneAnnounceSeconds = 3.0

    var body: some View {
        ZStack {
            if announcing {
                laneAnnouncement
            } else if found {
                acceptPanel
            } else {
                searchingPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await run() }
    }

    private var modeForTitle: MatchMode {
        switch model.kind {
        case .ranked: return .ranked
        case .brawl: return .brawl
        case .standard: return .standard
        }
    }

    // MARK: マッチング中

    private var searchingPanel: some View {
        VStack(spacing: 14) {
            // 上端の中央: 赤橙の札「推定所要時間 00:09 ✕」と大きな経過時間
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "house.fill").font(.system(size: 13)).foregroundStyle(.white.opacity(0.9))
                    Text(L("推定所要時間 00:\(String(format: "%02d", model.matchWaitSeconds + 6))",
                           "Est. 00:\(String(format: "%02d", model.matchWaitSeconds + 6))"))
                        .font(Celestial.heading(13))
                        .foregroundStyle(.white)
                    Button(action: cancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("キャンセル", "Cancel"))
                    .accessibilityIdentifier("flow_match_cancel")
                }
                Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("flow_match_elapsed")
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 6)
            .background(HomeChamfer(cut: 12).fill(LinearGradient(colors: [Color(red: 0.95, green: 0.45, blue: 0.20), Color(red: 0.80, green: 0.16, blue: 0.10)],
                                                                 startPoint: .top, endPoint: .bottom)))
            .overlay(HomeChamfer(cut: 12).stroke(HomeStyle.goldLight, lineWidth: 1.5))
            .shadow(color: Color.red.opacity(0.4), radius: 10)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
        }
        .overlay {
            VStack(spacing: 8) {
                Text(FlowText.mode(modeForTitle))
                    .font(Celestial.title(30))
                    .foregroundStyle(Theme.textPrimary)
                if model.kind != .brawl {
                    Text(laneLine).font(Celestial.heading(13)).foregroundStyle(Celestial.ice)
                }
                ProgressView().tint(Celestial.ice).padding(.top, 4)
            }
        }
    }

    private var laneLine: String {
        guard let p = model.lanePrimary else { return L("フレックスプロ", "Flex Pro") }
        return FlowText.position(p) + (model.laneSecondary.map { " · " + FlowText.position($0) } ?? "")
    }

    // MARK: 承認

    private var acceptPanel: some View {
        VStack(spacing: 10) {
            Text(L("マッチング成功", "Match Found"))
                .font(Celestial.title(22))
                .foregroundStyle(HomeStyle.goldLight)
                .shadow(color: Theme.gold.opacity(0.6), radius: 6)
            HStack(spacing: 18) {
                tags(range: 0..<5)
                crystal
                tags(range: 5..<10)
            }
            .frame(maxHeight: .infinity)
            Button(action: accept) {
                Text(accepted ? L("他のプレイヤー待ち", "Waiting for others") : L("スタート", "Start"))
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(accepted ? Theme.textPrimary : Color(red: 0.30, green: 0.18, blue: 0.02))
                    .frame(width: 230, height: 46)
                    .background(HomeChamfer(cut: 10).fill(accepted ? AnyShapeStyle(Color(red: 0.32, green: 0.30, blue: 0.16))
                                                                   : AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.93, blue: 0.45), Color(red: 0.96, green: 0.76, blue: 0.16)],
                                                                                                  startPoint: .top, endPoint: .bottom))))
                    .overlay(HomeChamfer(cut: 10).stroke(HomeStyle.goldLight, lineWidth: 1.2))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(accepted)
            .accessibilityLabel(L("スタート", "Start"))
            .accessibilityIdentifier("flow_match_accept")
        }
        .padding(.vertical, 12)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    /// 中央の逆三角の水晶（残り秒と緑の n/10）。
    private var crystal: some View {
        ZStack {
            AcceptCrystalShape()
                .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.55, blue: 0.62), Color(red: 0.06, green: 0.20, blue: 0.32)],
                                     startPoint: .top, endPoint: .bottom))
            AcceptCrystalShape()
                .stroke(LinearGradient(colors: [Color(red: 0.55, green: 0.95, blue: 1), Celestial.ice.opacity(0.5)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 3)
            VStack(spacing: 2) {
                Text("\(deadline)")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(deadline <= 5 ? Theme.danger : .white)
                    .contentTransition(.numericText(countsDown: true))
                (Text("\(acceptedCount)").foregroundStyle(Theme.success) + Text("/10").foregroundStyle(.white))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .offset(y: -18)
        }
        .frame(width: 150, height: 210)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("残り \(deadline) 秒、承認 \(acceptedCount)/10", "\(deadline) seconds left, \(acceptedCount) of 10 accepted"))
    }

    /// 左右の札（承認した人から顔に変わる。自分は左の先頭）。
    private func tags(range: Range<Int>) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(range), id: \.self) { i in
                let on = i < acceptedCount
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.45))
                    if on && i == 0, let art = PortraitArt.hero(app.profile.avatarHeroID) {
                        Image(uiImage: art).resizable().scaledToFill()
                    } else {
                        Image(systemName: on ? "person.fill" : "questionmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(on ? Theme.success : Theme.textSecondary.opacity(0.6))
                    }
                }
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? Theme.success : Celestial.ice.opacity(0.3), lineWidth: on ? 1.5 : 0.8))
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: 現在のレーン

    private var laneAnnouncement: some View {
        VStack(spacing: 10) {
            Image(systemName: assignedLane.map(FlowText.positionSymbol) ?? "square.grid.2x2.fill")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(Celestial.ice)
                .shadow(color: Celestial.ice, radius: 10)
            Text(L("現在のレーン：", "Current lane: ") + (assignedLane.map(FlowText.position) ?? L("フレックスプロ", "Flex Pro")))
                .font(Celestial.title(24))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("flow_lane_announce")
        }
        .transition(.opacity)
    }

    /// 割り当てられたレーン（ランキングはドラフトの割り当て、ほかは選んだ最初のレーン）。
    private var assignedLane: LanePosition? {
        if model.kind == .ranked, let draft = model.draft { return draft.plannedLane(blueIndex: draft.playerSlot) }
        return model.lanePrimary
    }

    // MARK: 進行

    /// 待ち → 成立（音と振動）→ 承認の締め切りの数え下げ（AI は数秒で承認する）。
    private func run() async {
        elapsed = 0
        while !found {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            elapsed += 1
            if elapsed >= model.matchWaitSeconds {
                withAnimation(.spring(duration: 0.4)) { found = true }
                app.audio.play(.matchFound)
                app.haptics.success()
            }
        }
        deadline = Self.acceptSeconds
        var aiAccepted = 0
        while deadline > 0 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled || announcing { return }
            deadline -= 1
            // AI（9 人）は 1 秒ごとに 3〜4 人ずつ承認する（3 秒で揃う）
            if aiAccepted < 9 {
                aiAccepted = min(9, aiAccepted + 3 + Int((model.seed >> UInt64(deadline % 8)) % 2))
                withAnimation(.easeOut(duration: 0.2)) { acceptedCount = aiAccepted + (accepted ? 1 : 0) }
            }
            if accepted && aiAccepted >= 9 {
                await finish()
                return
            }
            if !accepted && (1...3).contains(deadline) { app.audio.play(.countdown) }
        }
        guard !accepted else { return }
        // 締め切りまでに承認しなかった: マッチングを取り消してモードの選択へ（MLBB では信用スコアが減る）
        app.showToast(L("承認しなかったため、マッチングを取り消しました", "You didn't accept, so matchmaking was cancelled"))
        model.step = .mode
    }

    private func accept() {
        guard !accepted else { return }
        FlowFX.confirm(app)
        withAnimation(.easeInOut(duration: 0.2)) {
            accepted = true
            acceptedCount += 1
        }
        if acceptedCount >= 10 {
            Task { @MainActor in await finish() }
        }
    }

    /// 全員が承認: 「現在のレーン」を少し出してからピックへ。
    private func finish() async {
        guard !announcing else { return }
        app.haptics.impact(.medium)
        // ランキングはドラフトを先に作って、割り当てのレーンを出す
        if model.kind == .ranked && model.draft == nil {
            model.draft = DraftEngine(seed: model.seed, playerSlot: model.draftSlot, playerLane: model.lanePrimary)
        }
        withAnimation(.easeInOut(duration: 0.3)) { announcing = true }
        try? await Task.sleep(for: .seconds(Self.laneAnnounceSeconds))
        model.beginPicking(profile: app.profile)
    }

    private func cancel() {
        FlowFX.back(app)
        model.step = .mode
    }
}

/// 承認の水晶（上が広く、下へ尖る逆三角）。
struct AcceptCrystalShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.16))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.16))
        p.closeSubpath()
        return p
    }
}
