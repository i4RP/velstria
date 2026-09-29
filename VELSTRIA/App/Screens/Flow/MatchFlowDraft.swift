import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI024 ランク戦ドラフト（BAN 2×2 → スネークピック B1 R1 R2 B2 B3 R3 R4 B4 B5 R5）。
// AI の手番は短い演出の後に確定。プレイヤーの手番は持ち時間があり、切れると仮選択（なければ自動）で確定する。

struct DraftStep: View {
    @Bindable var model: MatchFlowModel
    @Environment(AppModel.self) private var app
    @State private var remaining = 0
    @State private var turnLimit = 1
    @State private var aiHover: String?
    @State private var confirmLeave = false

    static let banSeconds = 20
    static let pickSeconds = 30

    var body: some View {
        let draft = model.draft ?? DraftEngine(seed: model.seed, ownedHeroIDs: app.profile.ownedHeroIDs, master: app.master)
        let colorblind = app.profile.settings.colorblindMode
        VStack(spacing: 8) {
            MatchFlowHeader(title: L("ランク戦ドラフト", "Ranked Draft"), subtitle: phaseText(draft),
                            backSymbol: "xmark", backID: "flow_close", onBack: { confirmLeave = true }) {
                turnIndicator(draft)
            }
            HStack(alignment: .top, spacing: 10) {
                DraftTeamColumn(team: .blue, draft: draft, hover: hover(for: .blue, draft), colorblind: colorblind)
                    .frame(width: 156)
                center(draft)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                DraftTeamColumn(team: .red, draft: draft, hover: hover(for: .red, draft), colorblind: colorblind)
                    .frame(width: 156)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .task(id: draft.turnIndex) { await runTurn() }
        .alert(L("ドラフトを抜けますか？", "Leave the draft?"), isPresented: $confirmLeave) {
            Button(L("抜ける", "Leave"), role: .destructive) {
                FlowFX.back(app)
                app.router.isMatchFlowPresented = false
            }
            Button(L("続ける", "Stay"), role: .cancel) {}
        } message: {
            Text(L("試合前なので、ランクへの影響はありません。", "The match hasn't started, so your rank is unaffected."))
        }
    }

    // MARK: 表示

    private func phaseText(_ d: DraftEngine) -> String {
        guard let t = d.currentTurn else { return L("ドラフト完了 · ロードアウトを確認", "Draft complete · Check your loadout") }
        return t.action == .ban ? L("BAN フェーズ（各チーム 2 体）", "Ban phase (2 per team)") : L("ピックフェーズ", "Pick phase")
    }

    private func turnText(_ d: DraftEngine) -> String {
        guard let t = d.currentTurn else { return L("完了", "Done") }
        switch (t.isPlayer, t.action, t.team) {
        case (true, .ban, _): return L("あなたの BAN", "Your ban")
        case (true, .pick, _): return L("あなたのピック", "Your pick")
        case (false, .ban, .blue): return L("味方 AI が BAN 中", "Ally AI banning")
        case (false, .ban, _): return L("敵チームが BAN 中", "Enemy banning")
        case (false, .pick, .blue): return L("味方 AI がピック中", "Ally AI picking")
        case (false, .pick, _): return L("敵チームがピック中", "Enemy picking")
        }
    }

    private func turnIndicator(_ d: DraftEngine) -> some View {
        let t = d.currentTurn
        return HStack(spacing: 10) {
            if let t {
                Text(t.action == .pick ? t.slotLabel : "BAN")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(t.action == .ban ? Theme.danger : Theme.teamColor(t.team)))
            }
            Text(turnText(d))
                .font(Theme.heading(14))
                .foregroundStyle(t?.isPlayer == true ? Theme.gold : Theme.textPrimary)
                .lineLimit(1)
            if t?.isPlayer == true {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(remaining) / CGFloat(max(1, turnLimit)))
                        .stroke(remaining <= 5 ? Theme.danger : Theme.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: remaining)
                    Text("\(remaining)")
                        .font(Theme.mono(15))
                        .foregroundStyle(remaining <= 5 ? Theme.danger : Theme.textPrimary)
                        .contentTransition(.numericText(countsDown: true))
                }
                .frame(width: 44, height: 44)
                .accessibilityElement()
                .accessibilityLabel(L("残り \(remaining) 秒", "\(remaining) seconds left"))
                .accessibilityIdentifier("flow_draft_timer")
            } else if t != nil {
                ProgressView().tint(Theme.textPrimary).frame(width: 44, height: 44)
            }
        }
    }

    private func hover(for team: Team, _ d: DraftEngine) -> String? {
        guard let t = d.currentTurn, t.team == team else { return nil }
        if t.isPlayer { return model.draftHover.flatMap { d.canPlayerSelect($0) ? $0 : nil } }
        return aiHover
    }

    @ViewBuilder private func center(_ d: DraftEngine) -> some View {
        if d.isComplete {
            LoadoutPanel(model: model) {
                Button(action: next) {
                    Label(L("出撃準備へ", "Continue"), systemImage: "chevron.right.2").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("flow_next")
            }
            .transition(.scale(scale: 0.95).combined(with: .opacity))
        } else {
            VStack(spacing: 6) {
                RoleFilterBar(selection: $model.roleFilter)
                HeroPickerGrid(heroes: heroes, cell: { cell($0, d) }, onTap: { tap($0, d) })
                lockBar(d)
            }
        }
    }

    private var heroes: [HeroDef] {
        app.master.heroes.filter { model.roleFilter == nil || $0.role == model.roleFilter }
    }

    private func cell(_ h: HeroDef, _ d: DraftEngine) -> HeroGridCell {
        let banned = d.bannedHeroIDs.contains(h.heroID)
        let picked = d.pickedHeroIDs.contains(h.heroID)
        let turn = d.currentTurn
        let unownedForPick = !app.owns(heroID: h.heroID) && turn?.action != .ban
        let hovered = (turn?.isPlayer == true && model.draftHover == h.heroID) || aiHover == h.heroID
        return HeroGridCell(hero: h, selected: hovered, locked: unownedForPick && !banned && !picked,
                            unavailable: banned || picked, unavailableLabel: banned ? "BAN" : (picked ? "PICK" : nil))
    }

    private func lockBar(_ d: DraftEngine) -> some View {
        let turn = d.currentTurn
        let playerTurn = turn?.isPlayer == true
        let candidate = model.draftHover.flatMap { d.canPlayerSelect($0) ? $0 : nil }
        let isBan = turn?.action == .ban
        return HStack(spacing: 8) {
            if let c = candidate, playerTurn, let h = app.master.hero(c) {
                HeroPortraitView(heroID: c, size: 34, showsRole: false)
                Text(MasterText.hero(h)).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text(playerTurn ? L("ヒーローを選んでください", "Select a hero") : L("相手の選択を待っています…", "Waiting for others…"))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if playerTurn && isBan {
                Button {
                    commit(nil, timedOut: false)
                } label: {
                    Text(L("BAN しない", "No ban")).lineLimit(1).fixedSize()
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("flow_skip_ban")
            }
            Button {
                commit(candidate, timedOut: false)
            } label: {
                Label(isBan ? L("BAN する", "Ban") : L("ピック確定", "Lock In"), systemImage: isBan ? "nosign" : "lock.fill")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(PrimaryButtonStyle(color: isBan ? Theme.danger : Theme.gold))
            .disabled(!playerTurn || candidate == nil)
            .opacity(playerTurn && candidate != nil ? 1 : 0.45)
            .accessibilityIdentifier("flow_lock")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 50)
        .glass(cornerRadius: 14)
    }

    // MARK: 操作

    private func tap(_ h: HeroDef, _ d: DraftEngine) {
        guard let turn = d.currentTurn, turn.isPlayer else {
            app.haptics.tap()
            return
        }
        if d.canPlayerSelect(h.heroID) {
            FlowFX.tap(app)
            withAnimation(.spring(duration: 0.25)) { model.draftHover = h.heroID }
        } else if d.isTaken(h.heroID) {
            FlowFX.error(app)
        } else {
            FlowFX.error(app)
            app.showToast(L("未所持のヒーローはピックできません", "You can only pick heroes you own"))
        }
    }

    /// 手番の進行（プレイヤーは持ち時間、AI は短い演出の後に確定）。
    private func runTurn() async {
        guard let draft = model.draft, let turn = draft.currentTurn else { return }
        if turn.isPlayer {
            let limit = turn.action == .ban ? Self.banSeconds : Self.pickSeconds
            turnLimit = limit
            remaining = limit
            if turn.action == .ban {
                model.draftHover = nil
            } else if model.draftHover.map({ !draft.canPlayerSelect($0) }) ?? true {
                model.draftHover = app.profile.lastPickedHeroID.flatMap { draft.canPlayerSelect($0) ? $0 : nil }
            }
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
                if (1...5).contains(remaining) { app.audio.play(.countdown) }
            }
            guard let current = model.draft, current.turnIndex == draft.turnIndex else { return }
            var choice = model.draftHover.flatMap { current.canPlayerSelect($0) ? $0 : nil }
            if choice == nil && turn.action == .pick {
                choice = current.autoChoiceForPlayer(preferred: [app.profile.lastPickedHeroID].compactMap { $0 })
            }
            commit(choice, timedOut: true)
        } else {
            remaining = 0
            let choice: String?
            if let pending = model.aiPending, pending.turnIndex == draft.turnIndex {
                choice = pending.heroID
            } else {
                var d = draft
                choice = d.aiChoice()
                model.draft = d
                model.aiPending = (draft.turnIndex, choice)
            }
            withAnimation(.easeInOut(duration: 0.2)) { aiHover = choice }
            try? await Task.sleep(for: .milliseconds(650 + (draft.turnIndex % 3) * 180))
            if Task.isCancelled { return }
            commit(choice, timedOut: false)
        }
    }

    private func commit(_ heroID: String?, timedOut: Bool) {
        guard var d = model.draft, let turn = d.currentTurn else { return }
        var ok = d.commit(heroID)
        if !ok {
            // 無効な選択（競合など）は BAN ならスキップ、ピックなら自動選択で確定する。
            if turn.action == .ban {
                ok = d.commit(nil)
            } else {
                let fallback = turn.isPlayer ? d.autoChoiceForPlayer(preferred: []) : d.aiChoice()
                ok = d.commit(fallback)
            }
        }
        guard ok else { return }
        withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
            model.draft = d
            aiHover = nil
        }
        model.draftHover = nil
        model.aiPending = nil
        if turn.isPlayer {
            app.haptics.impact(.heavy)
            if turn.action == .pick, let pick = d.playerPick {
                model.selectHero(pick.heroID, profile: app.profile, master: app.master)
                model.position = pick.position
            }
            if timedOut {
                app.showToast(turn.action == .ban ? L("時間切れ: BAN なしで進みます", "Time's up: no ban")
                                                  : L("時間切れ: 自動でピックしました", "Time's up: auto-picked"))
            }
        }
        app.audio.play(turn.action == .ban ? .uiConfirm : .skillCast)
        if d.isComplete { app.audio.play(.announcement) }
    }

    private func next() {
        FlowFX.confirm(app)
        model.config = model.buildConfig(profile: app.profile, master: app.master)
        model.step = .ready
    }
}

// MARK: - チーム列（BAN 2 枠 + ピック 5 枠）

private struct DraftTeamColumn: View {
    let team: Team
    let draft: DraftEngine
    let hover: String?
    let colorblind: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let color = Theme.teamColor(team, colorblind: colorblind)
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: FlowText.teamSymbol(team)).foregroundStyle(color).font(.system(size: 11))
                Text(team == .blue ? L("味方", "Allies") : L("敵", "Enemies"))
                    .font(Theme.heading(12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                ForEach(0..<DraftEngine.bansPerTeam, id: \.self) { i in banSlot(i) }
            }
            ForEach(0..<5, id: \.self) { i in pickSlot(i, color: color) }
        }
        .padding(6)
        .glass(cornerRadius: 14, tint: color.opacity(0.7))
    }

    private func isActiveBan(_ i: Int) -> Bool {
        guard let t = draft.currentTurn else { return false }
        return t.action == .ban && t.team == team && i == draft.bans(for: team).count
    }

    private func isActivePick(_ i: Int) -> Bool {
        guard let t = draft.currentTurn else { return false }
        return t.action == .pick && t.team == team && i == draft.picks(for: team).count
    }

    @ViewBuilder private func banSlot(_ i: Int) -> some View {
        let bans = draft.bans(for: team)
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Theme.danger.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            if i < bans.count {
                if let id = bans[i] {
                    HeroPortraitView(heroID: id, size: 28, showsRole: false)
                        .saturation(0)
                        .overlay(Image(systemName: "nosign").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.danger))
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("—").font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                }
            } else if isActiveBan(i) {
                if let hover {
                    HeroPortraitView(heroID: hover, size: 28, showsRole: false).opacity(0.6)
                }
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Theme.danger, lineWidth: 2)
                    .glowPulse(Theme.danger, radius: 6)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityElement()
        .accessibilityLabel(banLabel(i, bans))
    }

    private func banLabel(_ i: Int, _ bans: [String?]) -> String {
        guard i < bans.count else { return L("BAN 枠 \(i + 1)", "Ban slot \(i + 1)") }
        guard let id = bans[i] else { return L("BAN なし", "No ban") }
        return "BAN " + (app.master.hero(id).map { MasterText.hero($0) } ?? id)
    }

    @ViewBuilder private func pickSlot(_ i: Int, color: Color) -> some View {
        let picks = draft.picks(for: team)
        let label = (team == .blue ? "B" : "R") + "\(i + 1)"
        let active = isActivePick(i)
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 20)
            if i < picks.count {
                let p = picks[i]
                HeroPortraitView(heroID: p.heroID, size: 30)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.isPlayer ? L("あなた", "You") : (app.master.hero(p.heroID).map { MasterText.hero($0) } ?? p.heroID))
                        .font(Theme.heading(11))
                        .foregroundStyle(p.isPlayer ? Theme.gold : Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 2) {
                        Image(systemName: FlowText.positionSymbol(p.position)).font(.system(size: 8))
                        Text(FlowText.position(p.position)).lineLimit(1)
                    }
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textSecondary)
                }
            } else if active {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.08))
                    if let hover { HeroPortraitView(heroID: hover, size: 30, showsRole: false).opacity(0.55) }
                }
                .frame(width: 30, height: 30)
                Text(L("選択中…", "Picking…"))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.gold)
                    .phaseAnimator([0.4, 1.0]) { v, a in v.opacity(a) } animation: { _ in .easeInOut(duration: 0.6) }
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 30, height: 30)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(active ? color.opacity(0.22) : (i < picks.count && picks[i].isPlayer ? Theme.gold.opacity(0.12) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(active ? color : Color.clear, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
    }
}
