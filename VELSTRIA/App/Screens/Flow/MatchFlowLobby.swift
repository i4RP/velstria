import SwiftUI
import VelstriaCore

// 担当: ui-flow。対戦フローのレーン選択とマッチング（MLBB の手順）。
// レーン選択（2025-06 から）: マッチングの前に主と副のレーン（または全部）を選ぶ。ドラフトのポジションの割り当てに使う。
// マッチング: 経過時間・予想時間・キャンセル →「マッチ成立」で「入場」を押す（締め切りまでに押さなければ取り消し）。
// 相手は今のところ AI なので、待ちは数秒。音と振動は今ある物（matchFound・success）を鳴らす。

// MARK: - レーン選択

struct LaneSelectStep: View {
    @Bindable var model: MatchFlowModel
    @Environment(AppModel.self) private var app
    /// 前回選んだレーン（-1 = 全部 / なし）。
    @AppStorage("outgame.lanePrimary") private var savedPrimary = -1
    @AppStorage("outgame.laneSecondary") private var savedSecondary = -1

    var body: some View {
        VStack(spacing: 10) {
            MatchFlowHeader(title: L("レーンを選ぶ", "Choose Lanes"), subtitle: FlowText.mode(model.kind == .ranked ? .ranked : .standard),
                            backSymbol: "chevron.left", backID: "flow_back", onBack: back) { EmptyView() }
            Text(L("主のレーンをタップし、続けてもう 1 つタップすると副のレーンになります。", "Tap your main lane, then tap another for your second lane."))
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                ForEach(LanePosition.allCases, id: \.self) { laneCard($0) }
                anyCard
            }
            .frame(maxHeight: .infinity)
            HStack {
                Text(summary).font(Celestial.heading(13)).foregroundStyle(Celestial.ice).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Button(action: startMatching) {
                    Label(L("マッチング開始", "Find Match"), systemImage: "magnifyingglass")
                        .frame(minWidth: 200)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("flow_lane_start")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .onAppear {
            if model.lanePrimary == nil, let p = LanePosition(rawValue: savedPrimary) {
                model.lanePrimary = p
                model.laneSecondary = LanePosition(rawValue: savedSecondary).flatMap { $0 == p ? nil : $0 }
            }
        }
    }

    private var summary: String {
        guard let p = model.lanePrimary else { return L("全部（どのレーンでも）", "Any lane") }
        let main = L("主: ", "Main: ") + FlowText.position(p)
        guard let s = model.laneSecondary else { return main }
        return main + " · " + L("副: ", "Second: ") + FlowText.position(s)
    }

    private func laneCard(_ lane: LanePosition) -> some View {
        let isMain = model.lanePrimary == lane
        let isSecond = model.laneSecondary == lane
        let tint = isMain ? Theme.gold : (isSecond ? Celestial.ice : Theme.textSecondary)
        return Button { tapLane(lane) } label: {
            VStack(spacing: 6) {
                Image(systemName: FlowText.positionSymbol(lane))
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(tint)
                Text(FlowText.position(lane)).font(Celestial.heading(14)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(MatchFactory.preferredRoles(for: lane).map { MasterText.role($0) }.joined(separator: "・"))
                    .font(Theme.body(10)).foregroundStyle(Theme.textSecondary).lineLimit(2).minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                if isMain || isSecond {
                    Text(isMain ? L("主", "Main") : L("副", "Second"))
                        .font(.system(size: 12, weight: .heavy, design: .serif))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glass(cornerRadius: 14, tint: tint.opacity(0.85), highlighted: isMain)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(FlowText.position(lane) + (isMain ? L("、主", ", main") : isSecond ? L("、副", ", second") : ""))
        .accessibilityIdentifier("flow_lane_\(lane.rawValue)")
        .accessibilityAddTraits(isMain || isSecond ? .isSelected : [])
    }

    private var anyCard: some View {
        let selected = model.lanePrimary == nil
        return Button {
            FlowFX.tap(app)
            model.lanePrimary = nil
            model.laneSecondary = nil
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "square.grid.2x2").font(.system(size: 30, weight: .light))
                    .foregroundStyle(selected ? Theme.gold : Theme.textSecondary)
                Text(L("全部", "Any")).font(Celestial.heading(14)).foregroundStyle(Theme.textPrimary)
                Text(L("空いたレーン", "Any open lane")).font(Theme.body(10)).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glass(cornerRadius: 14, tint: (selected ? Theme.gold : Theme.textSecondary).opacity(0.85), highlighted: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("flow_lane_any")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 主が無ければ主に、主と同じなら外す、主があれば副（副と同じなら副を外す）。
    private func tapLane(_ lane: LanePosition) {
        FlowFX.tap(app)
        withAnimation(.spring(duration: 0.25)) {
            if model.lanePrimary == nil {
                model.lanePrimary = lane
            } else if model.lanePrimary == lane {
                model.lanePrimary = model.laneSecondary
                model.laneSecondary = nil
            } else if model.laneSecondary == lane {
                model.laneSecondary = nil
            } else {
                model.laneSecondary = lane
            }
        }
    }

    private func back() {
        FlowFX.back(app)
        model.step = .mode
    }

    private func startMatching() {
        FlowFX.confirm(app)
        savedPrimary = model.lanePrimary?.rawValue ?? -1
        savedSecondary = model.laneSecondary?.rawValue ?? -1
        model.step = .matching
    }
}

// MARK: - マッチング

struct MatchingStep: View {
    @Bindable var model: MatchFlowModel
    @Environment(AppModel.self) private var app
    @State private var elapsed = 0
    @State private var found = false
    @State private var accepted = false
    @State private var deadline = MatchingStep.acceptSeconds

    /// 「入場」の締め切り（秒）。
    static let acceptSeconds = 10
    /// AI 戦の待ち（秒）。シードで 2〜4 秒。
    var waitSeconds: Int { 2 + Int(model.seed % 3) }

    var body: some View {
        VStack(spacing: 12) {
            MatchFlowHeader(title: found ? L("マッチ成立", "Match Found") : L("マッチング中", "Matchmaking"),
                            subtitle: FlowText.mode(modeForTitle), backSymbol: "xmark", backID: "flow_match_cancel",
                            onBack: cancel) { EmptyView() }
            Spacer(minLength: 0)
            if found { acceptPanel } else { searchingPanel }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .task { await run() }
    }

    private var modeForTitle: MatchMode {
        switch model.kind {
        case .ranked: return .ranked
        case .brawl: return .brawl
        case .standard: return .standard
        }
    }

    private var searchingPanel: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Celestial.ice.opacity(0.2), lineWidth: 3)
                Circle().trim(from: 0, to: 0.25).stroke(Celestial.ice, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(Double(elapsed) * 90))
                    .animation(.linear(duration: 1), value: elapsed)
                Text(String(format: "%d:%02d", elapsed / 60, elapsed % 60))
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityIdentifier("flow_match_elapsed")
            }
            .frame(width: 120, height: 120)
            Text(L("予想 0:0\(waitSeconds)", "Estimated 0:0\(waitSeconds)"))
                .font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
            if model.kind != .brawl {
                Text(laneLine).font(Celestial.heading(12)).foregroundStyle(Celestial.ice)
            }
            Button(action: cancel) {
                Text(L("キャンセル", "Cancel")).frame(minWidth: 160)
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.top, 6)
        }
    }

    private var laneLine: String {
        guard let p = model.lanePrimary else { return L("レーン: 全部", "Lane: Any") }
        return L("レーン: ", "Lane: ") + FlowText.position(p) + (model.laneSecondary.map { " / " + FlowText.position($0) } ?? "")
    }

    private var acceptPanel: some View {
        VStack(spacing: 12) {
            Text(accepted ? L("ほかのプレイヤーの入場を待っています…", "Waiting for other players…")
                          : L("試合が見つかりました", "A match has been found"))
                .font(Celestial.heading(15))
                .foregroundStyle(Theme.textPrimary)
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(deadline) / CGFloat(Self.acceptSeconds))
                    .stroke(deadline <= 3 ? Theme.danger : Theme.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: deadline)
                Text("\(deadline)").font(.system(size: 28, weight: .regular, design: .serif)).monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 84, height: 84)
            Button(action: accept) {
                Text(L("入場", "Accept")).font(.system(size: 22, weight: .semibold, design: .serif)).frame(minWidth: 220)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(accepted)
            .accessibilityIdentifier("flow_match_accept")
        }
        .padding(20)
        .glass(cornerRadius: 18, tint: Theme.gold.opacity(0.9), highlighted: true)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    /// 待ち → 成立（音と振動）→ 入場の締め切りの数え下げ。
    private func run() async {
        elapsed = 0
        while !found {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            elapsed += 1
            if elapsed >= waitSeconds {
                withAnimation(.spring(duration: 0.4)) { found = true }
                app.audio.play(.matchFound)
                app.haptics.success()
            }
        }
        deadline = Self.acceptSeconds
        while deadline > 0 && !accepted {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled || accepted { return }
            deadline -= 1
            if (1...3).contains(deadline) { app.audio.play(.countdown) }
        }
        guard !accepted else { return }
        // 締め切りまでに入場しなかった: マッチングを取り消してモードの選択へ（MLBB では信用スコアが減る）
        app.showToast(L("入場しなかったため、マッチングを取り消しました", "You didn't accept, so matchmaking was cancelled"))
        model.step = .mode
    }

    private func accept() {
        guard !accepted else { return }
        FlowFX.confirm(app)
        withAnimation(.easeInOut(duration: 0.2)) { accepted = true }
        Task { @MainActor in
            // AI の入場を少し待ってから（全員が入場した体）
            try? await Task.sleep(for: .milliseconds(900))
            app.haptics.impact(.medium)
            model.beginPicking(profile: app.profile)
        }
    }

    private func cancel() {
        FlowFX.back(app)
        model.step = .mode
    }
}
