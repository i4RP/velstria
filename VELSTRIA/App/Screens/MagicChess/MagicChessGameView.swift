import SwiftUI
import VelstriaCore

// 担当: ui（マジックチェス）。盤面画面（全画面カバー）。ショップ→戦闘再生→精算→次ラウンド→結果。

struct MagicChessGameView: View {
    @Environment(AppModel.self) private var app
    let launch: MagicChessLaunch

    @State private var controller: MagicChessController?
    @State private var stage: Stage = .shop
    @State private var playToken = 0
    @State private var rewardGranted = false

    enum Stage { case shop, playing, aftermath, result }

    var body: some View {
        ZStack {
            StarfieldBackground().ignoresSafeArea()
            if let controller {
                content(controller)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { if controller == nil { controller = MagicChessController(config: launch.config) } }
        .task(id: playToken) {
            guard stage == .playing, let controller else { return }
            while controller.advanceFrame() {
                try? await Task.sleep(for: .milliseconds(55))
                if Task.isCancelled { return }
            }
            if controller.phase == .gameOver || !(controller.human?.alive ?? true) {
                stage = .result
            } else {
                stage = .aftermath
            }
        }
    }

    @ViewBuilder
    private func content(_ c: MagicChessController) -> some View {
        VStack(spacing: 8) {
            topBar(c)
            switch stage {
            case .shop: shopStage(c)
            case .playing: playingStage(c)
            case .aftermath: aftermathStage(c)
            case .result: MagicChessResultView(controller: c, onClose: close)
            }
        }
    }

    // MARK: トップバー

    private func topBar(_ c: MagicChessController) -> some View {
        HStack(spacing: 10) {
            Button { close() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary).frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain).accessibilityIdentifier("mc_close")
            stat(symbol: "flag.checkered", text: L("R\(c.round)", "R\(c.round)"), tint: Theme.textPrimary)
            stat(symbol: "heart.fill", text: "\(c.human?.hp ?? 0)", tint: .red)
            stat(symbol: "star.circle.fill", text: "\(c.human?.gold ?? 0)", tint: Theme.gold)
            stat(symbol: "person.3.fill", text: L("残 \(c.state.aliveCount)", "\(c.state.aliveCount) left"), tint: Theme.cyan)
            Spacer(minLength: 0)
            synergyStrip(c)
        }
    }

    private func stat(symbol: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
            Text(text).font(Theme.mono(13)).foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 8).frame(height: 32)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func synergyStrip(_ c: MagicChessController) -> some View {
        HStack(spacing: 5) {
            ForEach(c.synergies) { s in
                HStack(spacing: 3) {
                    Image(systemName: Theme.roleSymbol(s.role)).font(.system(size: 10, weight: .bold))
                    Text("\(s.count)").font(.system(size: 11, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(s.tier > 0 ? Color.black.opacity(0.85) : Theme.textSecondary)
                .padding(.horizontal, 7).frame(height: 26)
                .background(Capsule().fill(s.tier > 0 ? Theme.roleColor(s.role) : Color.white.opacity(0.06)))
                .accessibilityLabel("\(MasterText.role(s.role)) \(s.count)")
            }
        }
    }

    // MARK: ショップ

    private func shopStage(_ c: MagicChessController) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Panel(padding: 8) { MCBoardGrid(controller: c) }
                    .frame(maxWidth: .infinity)
                controlColumn(c).frame(width: 150)
            }
            .frame(maxHeight: .infinity)
            benchRow(c)
            if c.selected != nil { selectionBar(c) }
            shopRow(c)
        }
    }

    private func controlColumn(_ c: MagicChessController) -> some View {
        VStack(spacing: 8) {
            Text(L("盤面 \(c.human?.boardCount ?? 0)/\(c.boardCapacity)", "Board \(c.human?.boardCount ?? 0)/\(c.boardCapacity)"))
                .font(Theme.heading(13)).foregroundStyle(Theme.textPrimary)
            Button { app.haptics.tap(); c.autoArrange() } label: {
                Label(L("おまかせ配置", "Auto Arrange"), systemImage: "wand.and.stars")
                    .font(Theme.body(12)).frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            .accessibilityIdentifier("mc_autoarrange")
            Spacer(minLength: 0)
            Button {
                app.audio.play(.uiConfirm); app.haptics.tap()
                c.startCombat(); stage = .playing; playToken += 1
            } label: {
                VStack(spacing: 0) {
                    Text(L("戦闘", "FIGHT")).font(.system(size: 18, weight: .black, design: .rounded))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(PrimaryButtonStyle())
            .glowPulse(Theme.gold, radius: 10)
            .accessibilityIdentifier("mc_fight")
        }
    }

    private func benchRow(_ c: MagicChessController) -> some View {
        let bench = c.human?.bench ?? []
        return Panel(padding: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if bench.isEmpty {
                        Text(L("ベンチ", "Bench")).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                            .frame(height: 50)
                    }
                    ForEach(bench) { unit in
                        MCUnitChip(heroID: unit.heroID, star: unit.star, size: 34,
                                   selected: c.selected == unit.instanceID)
                            .onTapGesture {
                                app.haptics.tap()
                                c.selected = (c.selected == unit.instanceID) ? nil : unit.instanceID
                            }
                            .accessibilityIdentifier("mc_bench_\(unit.instanceID)")
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func selectionBar(_ c: MagicChessController) -> some View {
        let id = c.selected!
        let onBench = c.isOnBench(id)
        let name = c.unit(id).flatMap { app.master.hero($0.heroID) }.map { MasterText.hero($0) } ?? ""
        return HStack(spacing: 8) {
            Text(name)
                .font(Theme.heading(13)).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Spacer(minLength: 0)
            if !onBench {
                Button { app.haptics.tap(); c.toBench(id); c.selected = nil } label: {
                    Label(L("ベンチへ", "To Bench"), systemImage: "tray.and.arrow.down.fill").font(Theme.body(12))
                }.buttonStyle(.plain).foregroundStyle(Theme.cyan)
            }
            Button { app.audio.play(.uiTap); app.haptics.tap(); c.sell(id) } label: {
                Label(L("売却", "Sell"), systemImage: "dollarsign.circle.fill").font(Theme.body(12))
            }.buttonStyle(.plain).foregroundStyle(Theme.gold)
            .accessibilityIdentifier("mc_sell")
        }
        .padding(.horizontal, 10).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }

    private func shopRow(_ c: MagicChessController) -> some View {
        let shop = c.human?.shop ?? []
        return HStack(spacing: 8) {
            Button { app.audio.play(.uiTap); app.haptics.tap(); c.reroll() } label: {
                VStack(spacing: 1) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 16, weight: .bold))
                    Text("\(MagicChessData.rerollCost)").font(.system(size: 10, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Theme.cyan).frame(width: 52, height: 58)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain).accessibilityIdentifier("mc_reroll")
            ForEach(shop) { s in
                Button {
                    app.audio.play(.uiTap); app.haptics.tap(); c.buy(slot: s.slot)
                } label: {
                    VStack(spacing: 2) {
                        MCUnitChip(heroID: s.heroID, size: 32, dimmed: s.sold)
                        HStack(spacing: 2) {
                            Image(systemName: "star.circle.fill").font(.system(size: 9)).foregroundStyle(Theme.gold)
                            Text("\(s.cost)").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(s.sold ? 0.02 : 0.06)))
                }
                .buttonStyle(.plain).disabled(s.sold)
                .accessibilityIdentifier("mc_shop_\(s.slot)")
            }
        }
    }

    // MARK: 戦闘再生

    private func playingStage(_ c: MagicChessController) -> some View {
        VStack(spacing: 6) {
            if let frame = c.currentFrame {
                MCCombatField(frame: frame).frame(maxHeight: .infinity)
            } else {
                Text(L("戦闘中…", "Fighting…")).foregroundStyle(Theme.textSecondary).frame(maxHeight: .infinity)
            }
            Button { skipPlayback(c) } label: {
                Label(L("スキップ", "Skip"), systemImage: "forward.end.fill").font(Theme.body(12))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            .accessibilityIdentifier("mc_skip")
        }
    }

    private func skipPlayback(_ c: MagicChessController) {
        c.frameIndex = max(0, c.frameCount - 1)
        if c.phase == .gameOver || !(c.human?.alive ?? true) { stage = .result } else { stage = .aftermath }
    }

    // MARK: 精算

    private func aftermathStage(_ c: MagicChessController) -> some View {
        let human = c.human
        let dmg = human?.lastDamageTaken ?? 0
        return VStack(spacing: 14) {
            Spacer()
            Image(systemName: dmg > 0 ? "xmark.shield.fill" : "checkmark.seal.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(dmg > 0 ? Color.red : Theme.success)
            Text(dmg > 0 ? L("ラウンド敗北", "Round Lost") : L("ラウンド勝利", "Round Won"))
                .font(Theme.title(24)).foregroundStyle(Theme.textPrimary)
            if dmg > 0 {
                Text(L("HP -\(dmg)", "HP -\(dmg)")).font(Theme.heading(16)).foregroundStyle(.red)
            }
            standings(c)
            Spacer()
            Button { c.nextRound(); stage = .shop } label: {
                Label(L("次のラウンドへ", "Next Round"), systemImage: "chevron.right.2")
                    .frame(maxWidth: 280, minHeight: 50)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("mc_next_round")
            Spacer()
        }
    }

    private func standings(_ c: MagicChessController) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(c.state.standings.prefix(8).enumerated()), id: \.element.id) { i, p in
                HStack(spacing: 8) {
                    Text("\(i + 1)").font(Theme.mono(12)).foregroundStyle(Theme.gold).frame(width: 20)
                    Text(p.displayName).font(Theme.body(12))
                        .foregroundStyle(p.isHuman ? Theme.gold : Theme.textPrimary).lineLimit(1)
                    Spacer(minLength: 0)
                    if p.alive {
                        Label("\(p.hp)", systemImage: "heart.fill").font(Theme.body(11)).foregroundStyle(.red)
                    } else {
                        Text(MagicChessFormat.placement(p.placement ?? 0)).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: 320)
            }
        }
        .padding(10)
        .glass(cornerRadius: 12)
    }

    private func close() {
        grantRewardIfNeeded()
        app.audio.play(.uiBack)
        app.dismissMagicChess()
    }

    private func grantRewardIfNeeded() {
        guard !rewardGranted, let c = controller, let human = c.human else { return }
        // 脱落していれば placement、生存中（途中終了）は現在の順位で概算。
        let placement = human.placement ?? max(1, c.state.aliveCount)
        rewardGranted = true
        var p = app.profile
        MagicChessRewardService.apply(placement: placement, participants: c.state.config.participantCount, to: &p)
        app.profile = p
    }
}
