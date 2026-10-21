import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI024 ランクのドラフト（MLBB の画面の作り。BAN は 2026-10-12 に廃止）。
// 順番は 青1 → 赤2 → 青2 → 赤2 → 青2 → 赤1。自分の手番の位置は試合ごとに変わり、味方の AI は自分の番に選ぶ。
// 上の中央に段階の文と大きな残り秒数、左に味方 5 人（国旗・ヒーロー・名前・レーン・スペル・交換の ⇆）、右に敵 5 人（名前は伏せる）、
// 下にチャット欄と「ヒーロー」「戦闘準備」のタブ。ピックが終わると 25 秒の最終調整（スキン・エンブレム・スペル・バトルプラン）。

struct DraftStep: View {
    @Bindable var model: MatchFlowModel
    @Environment(AppModel.self) private var app
    @State private var remaining = FlowTiming.pickSeconds
    @State private var aiHover: String?
    @State private var confirmLeave = false
    @State private var lane: LanePosition?
    @State private var tab: Tab = .heroes

    enum Tab: Hashable { case heroes, prep }

    /// 残りがこの秒数以下になったらヒーロー選択の曲を緊張の曲へ（MusicTrack.draftTense）。
    static let tenseSeconds = 10

    var body: some View {
        let draft = model.draft ?? DraftEngine(seed: model.seed, master: app.master)
        VStack(spacing: 6) {
            PickPhaseHeader(phase: phaseText(draft), seconds: remaining, urgent: remaining <= 5) {
                HStack(spacing: 10) {
                    FlowCloseButton(identifier: "flow_close") { confirmLeave = true }
                    // 先にピックする側（青 = 味方）の印
                    Text("1st")
                        .font(.system(size: 22, weight: .heavy, design: .serif))
                        .italic()
                        .foregroundStyle(Celestial.ice)
                        .shadow(color: Celestial.ice.opacity(0.7), radius: 4)
                        .accessibilityLabel(L("先手", "First pick"))
                }
            } trailing: {
                if model.adjusting {
                    Button { FlowFX.confirm(app); model.launch(app: app) } label: {
                        Label(L("準備完了", "Ready"), systemImage: "checkmark").fixedSize()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("flow_confirm")
                }
            }
            HStack(alignment: .top, spacing: 8) {
                DraftAllyColumn(model: model, draft: draft, hover: hover(for: .blue, draft), onSwap: requestSwap)
                    .frame(width: 186)
                center(draft)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                DraftEnemyColumn(draft: draft, hover: hover(for: .red, draft))
                    .frame(width: 150)
            }
            QuickChatBar(model: model)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .task(id: "\(draft.turnIndex)-\(draft.playerSlot)") { await runTurn() }
        .task(id: model.adjusting) { await runAdjust() }
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
        guard let t = d.currentTurn else {
            let lane = d.playerPick.map { FlowText.position($0.position) } ?? ""
            return L("試合はまもなく始まります。進む：", "The match is about to begin. Go: ") + lane
        }
        return t.team == .blue ? L("ヒーローPICK（味方）", "Hero Pick (Ally)") : L("ヒーローPICK（敵）", "Hero Pick (Enemy)")
    }

    private func hover(for team: Team, _ d: DraftEngine) -> String? {
        guard let t = d.currentTurn, t.team == team else { return nil }
        if t.isPlayer { return model.draftHover.flatMap { d.canPlayerSelect($0) ? $0 : nil } }
        return aiHover
    }

    @ViewBuilder private func center(_ d: DraftEngine) -> some View {
        VStack(spacing: 6) {
            if tab == .heroes && !d.isComplete {
                LaneFilterBar(selection: $lane, only: d.plannedLane(blueIndex: d.playerSlot))
                HeroPickerGrid(heroes: heroes, cell: { cell($0, d) }, onTap: { tap($0, d) })
                if !(d.currentTurn?.isPlayer ?? true) { chips(d) }
                lockBar(d)
            } else {
                LoadoutPanel(model: model) { EmptyView() }
            }
            CelestialTabs(options: [
                CelestialTab(value: Tab.heroes, title: L("ヒーロー", "Heroes"), symbol: nil, identifier: "flow_tab_heroes"),
                CelestialTab(value: Tab.prep, title: L("戦闘準備", "Prep"), symbol: nil, identifier: "flow_tab_prep"),
            ], selection: $tab, fills: false)
        }
    }

    private var heroes: [HeroDef] {
        app.master.heroes.filter { LaneFilterBar.matches($0, lane: lane) }
    }

    private func cell(_ h: HeroDef, _ d: DraftEngine) -> HeroGridCell {
        let picked = d.pickedHeroIDs.contains(h.heroID)
        // 自分の選択（自分の番の仮選択・手番の前の事前選択）と、今の番の AI の選択
        let hovered = (d.playerPick == nil && model.draftHover == h.heroID) || aiHover == h.heroID
        return HeroGridCell(hero: h, selected: hovered, locked: false,
                            unavailable: picked, unavailableLabel: picked ? "PICK" : nil, name: MasterText.heroPickName(h))
    }

    /// 他の人の番: 「まずは事前選択」「ピックを手伝うよ」（定型文。手伝うとピック順を入れ替える）。
    private func chips(_ d: DraftEngine) -> some View {
        HStack(spacing: 8) {
            chip(L("まずは事前選択", "Pre-select first"), id: "flow_chip_preselect", enabled: d.playerPick == nil) {
                say(L("まずは事前選択", "Pre-select first"))
            }
            chip(L("ピックを手伝うよ", "I'll help you pick"), id: "flow_chip_help", enabled: d.canOfferPickHelp) {
                offerPickHelp()
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ title: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Celestial.heading(12))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(RoundedRectangle(cornerRadius: 4).fill(Celestial.inkRaised.opacity(0.85)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Celestial.ice.opacity(0.45), lineWidth: 0.7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityIdentifier(id)
    }

    private func lockBar(_ d: DraftEngine) -> some View {
        let turn = d.currentTurn
        let playerTurn = turn?.isPlayer == true
        let candidate = model.draftHover.flatMap { d.canPlayerSelect($0) ? $0 : nil }
        return HStack(spacing: 8) {
            if let c = candidate, playerTurn, let h = app.master.hero(c) {
                HeroPortraitView(heroID: c, size: 34, showsRole: false)
                Text(MasterText.hero(h)).font(Celestial.heading(13)).foregroundStyle(Theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            } else if let t = turn, !t.isPlayer {
                // 他の人の番: 紋章と「○○ PICK中」
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.teamColor(t.team, colorblind: app.profile.settings.colorblindMode))
                Text(pickerName(t, d) + L(" PICK中", " picking"))
                    .font(Celestial.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("flow_draft_picking")
            } else {
                Text(L("ヒーローを選んでください", "Select a hero"))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                commit(candidate, timedOut: false)
            } label: {
                Label(L("ピック確定", "Lock In"), systemImage: "lock.fill")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.gold))
            .disabled(!playerTurn || candidate == nil)
            .opacity(playerTurn && candidate != nil ? 1 : 0.45)
            .accessibilityIdentifier("flow_lock")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 48)
        .glass(cornerRadius: 14)
    }

    // MARK: 操作

    /// 今の番の人の名前（味方は「味方 AI」、敵は伏せて「プレイヤーN」）。
    private func pickerName(_ t: DraftTurn, _ d: DraftEngine) -> String {
        if t.team == .blue { return L("味方 AI", "Ally AI") }
        let n = d.picks(for: .red).count + 1
        return L("プレイヤー\(n)", "Player \(n)")
    }

    private func tap(_ h: HeroDef, _ d: DraftEngine) {
        guard let turn = d.currentTurn, turn.isPlayer else {
            // 他の人の番: 事前選択（自分の番が来たら選んだ状態から始まる。MLBB と同じ）
            if d.canPlayerPreselect(h.heroID) {
                FlowFX.tap(app)
                withAnimation(.spring(duration: 0.25)) { model.draftHover = h.heroID }
            } else {
                app.haptics.tap()
            }
            return
        }
        if d.canPlayerSelect(h.heroID) {
            FlowFX.tap(app)
            withAnimation(.spring(duration: 0.25)) { model.draftHover = h.heroID }
        } else {
            FlowFX.error(app)
        }
    }

    /// 定型文をチャット欄に出す（自分の発言）。
    private func say(_ text: String) {
        FlowFX.tap(app)
        let me = app.profile.displayName.isEmpty ? L("あなた", "You") : app.profile.displayName
        model.chat.append(FlowChatLine(speaker: me, text: text, isMine: true))
    }

    /// 「ピックを手伝うよ」: 今の番の味方 AI とピック順を入れ替える（AI は受ける）。
    private func offerPickHelp() {
        guard var d = model.draft, d.canOfferPickHelp else { return }
        say(L("ピックを手伝うよ", "I'll help you pick"))
        d.swapPickOrderWithCurrent()
        model.aiPending = nil
        aiHover = nil
        withAnimation(.spring(duration: 0.3)) { model.draft = d }
        if let lane = d.plannedLane(blueIndex: d.playerSlot) { model.position = lane }
        app.showToast(L("ピック順を交換しました", "Positions have been swapped"))
    }

    /// 味方への交換の申請（選ぶ前ならレーン交換、両方が選んだ後ならヒーロー交換）。AI はロールで応じるかを決める。
    private func requestSwap(_ blueIndex: Int) {
        guard var d = model.draft else { return }
        let bothPicked = d.playerSlot < d.picks(for: .blue).count && blueIndex < d.picks(for: .blue).count
        let ok = bothPicked ? d.requestHeroSwap(blueIndex: blueIndex) : d.requestLaneSwap(blueIndex: blueIndex)
        if ok {
            FlowFX.confirm(app)
            withAnimation(.spring(duration: 0.3)) { model.draft = d }
            if let pick = d.playerPick {
                if bothPicked { model.selectHero(pick.heroID, profile: app.profile, master: app.master) }
                model.position = pick.position
            } else if let lane = d.plannedLane(blueIndex: d.playerSlot) {
                model.position = lane
            }
            app.showToast(bothPicked ? L("味方がヒーロー交換に応じました", "Your ally accepted the hero swap")
                                     : L("味方がレーン交換に応じました", "Your ally accepted the lane swap"))
        } else {
            FlowFX.error(app)
            app.showToast(L("味方に断られました", "Your ally declined"))
        }
    }

    /// 手番の進行（プレイヤーは持ち時間、AI は短い演出の後に確定）。
    private func runTurn() async {
        guard let draft = model.draft, let turn = draft.currentTurn else { return }
        if turn.isPlayer {
            remaining = FlowTiming.pickSeconds
            tab = .heroes
            app.haptics.impact(.medium)
            if model.draftHover.map({ !draft.canPlayerSelect($0) }) ?? true {
                model.draftHover = app.profile.lastPickedHeroID.flatMap { draft.canPlayerSelect($0) ? $0 : nil }
            }
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
                if (1...5).contains(remaining) { app.audio.play(.countdown) }
                // 残り時間が少なくなったら緊張を上げる（ドラフトの終わりまでそのまま）
                if remaining <= Self.tenseSeconds { app.audio.playMusic(.draftTense) }
            }
            guard let current = model.draft, current.turnIndex == draft.turnIndex else { return }
            var choice = model.draftHover.flatMap { current.canPlayerSelect($0) ? $0 : nil }
            if choice == nil {
                // 時間切れ: よく使うヒーローを優先して自動で選ぶ（MLBB と同じ）
                let favorites = DraftShowcase.favorites(app.profile, roster: current.heroIDs, limit: 10)
                choice = current.autoChoiceForPlayer(preferred: favorites + [app.profile.lastPickedHeroID].compactMap { $0 })
            }
            commit(choice, timedOut: true)
        } else {
            remaining = FlowTiming.pickSeconds
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

    /// 最終調整の 25 秒（0 で試合を始める）。
    private func runAdjust() async {
        guard model.adjusting else { return }
        tab = .prep
        remaining = FlowTiming.adjustSeconds
        while remaining > 0 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            remaining -= 1
            if (1...3).contains(remaining) { app.audio.play(.countdown) }
        }
        model.launch(app: app)
    }

    private func commit(_ heroID: String?, timedOut: Bool) {
        guard var d = model.draft, let turn = d.currentTurn else { return }
        var ok = d.commit(heroID)
        if !ok {
            // 無効な選択（競合など）は自動選択で確定する。
            let fallback = turn.isPlayer ? d.autoChoiceForPlayer(preferred: []) : d.aiChoice()
            ok = d.commit(fallback)
        }
        guard ok else { return }
        withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
            model.draft = d
            aiHover = nil
        }
        if turn.isPlayer || (model.draftHover.map { d.isTaken($0) } ?? false) { model.draftHover = nil }
        model.aiPending = nil
        if turn.isPlayer {
            app.haptics.impact(.heavy)
            if let pick = d.playerPick {
                model.selectHero(pick.heroID, profile: app.profile, master: app.master)
                model.position = pick.position
            }
            if timedOut {
                app.showToast(L("時間切れ: 自動でピックしました", "Time's up: auto-picked"))
            }
        }
        app.audio.play(.lockIn, gain: turn.isPlayer ? 1 : 0.6)
        if d.isComplete {
            app.audio.play(.announcement)
            model.beginAdjusting()
        }
    }
}

// MARK: - 味方の列（国旗・ヒーロー・名前・レーン・スペル・交換）

private struct DraftAllyColumn: View {
    @Bindable var model: MatchFlowModel
    let draft: DraftEngine
    let hover: String?
    let onSwap: (Int) -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { i in row(i) }
        }
        .padding(5)
        .glass(cornerRadius: 12, tint: Theme.teamColor(.blue, colorblind: app.profile.settings.colorblindMode).opacity(0.7))
    }

    @ViewBuilder private func row(_ i: Int) -> some View {
        let picks = draft.picks(for: .blue)
        let isMe = i == draft.playerSlot
        let active = draft.currentTurn?.team == .blue && picks.count == i
        let lane = i < picks.count ? picks[i].position : draft.plannedLane(blueIndex: i)
        // 四角に出すヒーロー: 選んだ物、今の番の仮選択、自分の事前選択（薄く）
        let shown: String? = i < picks.count ? picks[i].heroID : (active ? hover : (isMe ? model.draftHover : nil))
        HStack(spacing: 5) {
            CountryFlagBadge(code: app.profile.countryCode, size: 14)
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.45))
                if let shown {
                    HeroPortraitView(heroID: shown, size: 36, showsRole: false)
                        .opacity(i < picks.count ? 1 : 0.5)
                        .transition(.scale(scale: 1.5).combined(with: .opacity))
                } else if let lane {
                    // まだ選んでいない: 大きなレーンの四角（MLBB と同じ）
                    Image(systemName: FlowText.positionSymbol(lane))
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Celestial.ice)
                } else {
                    Image(systemName: "questionmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 36, height: 36)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(active ? Theme.gold : .clear, lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 2) {
                if i >= picks.count {
                    // まだ選んでいない: 得意ヒーロー 3 体（MLBB の選択画面と同じ）
                    HStack(spacing: 2) {
                        ForEach(favorites(i, lane: lane), id: \.self) { HeroPortraitView(heroID: $0, size: 14, showsRole: false) }
                    }
                } else if let lane {
                    Text(FlowText.position(lane)).font(Theme.body(9)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Text(isMe ? (app.profile.displayName.isEmpty ? L("あなた", "You") : app.profile.displayName) : L("味方 AI", "Ally AI"))
                    .font(Celestial.heading(11))
                    .foregroundStyle(isMe ? Color(red: 0.62, green: 0.92, blue: 1) : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            if isMe {
                SpellIconView(spellID: model.spells.first ?? "BS01", size: 18)
            } else if canSwap(i) {
                Button { onSwap(i) } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Celestial.ice)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Celestial.ink.opacity(0.8)))
                        .overlay(Circle().stroke(Celestial.ice.opacity(0.5), lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("交換を申請", "Request swap"))
                .accessibilityIdentifier("flow_swap_\(i)")
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 46)
        // 自分の行は水色に光る（MLBB と同じ）
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isMe ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.25, green: 0.70, blue: 0.95).opacity(0.45), .clear],
                                                      startPoint: .leading, endPoint: .trailing))
                       : AnyShapeStyle(Color.clear)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(isMe ? Color(red: 0.45, green: 0.88, blue: 1).opacity(0.8) : .clear, lineWidth: 1))
        .shadow(color: isMe ? Color(red: 0.4, green: 0.85, blue: 1).opacity(0.45) : .clear, radius: 6)
        .overlay(alignment: .trailing) {
            if isMe, let emote = model.myEmote { EmoteBubble(cosmeticID: emote, size: 40).offset(x: 34) }
        }
        .accessibilityElement(children: .combine)
    }

    /// 交換の申請ができるか（レーンを決めてある時。両方が選ぶ前はレーン、両方が選んだ後はヒーロー）。
    private func canSwap(_ i: Int) -> Bool {
        guard draft.plannedLane(blueIndex: i) != nil || draft.isComplete else { return false }
        let picks = draft.picks(for: .blue).count
        let mine = draft.playerSlot < picks, theirs = i < picks
        return mine == theirs
    }

    private func favorites(_ i: Int, lane: LanePosition?) -> [String] {
        if i == draft.playerSlot {
            let mine = DraftShowcase.favorites(app.profile, roster: draft.heroIDs)
            if !mine.isEmpty { return mine }
        }
        return DraftShowcase.aiFavorites(seed: model.seed, index: i, lane: lane ?? .mid, master: app.master)
    }
}

// MARK: - 敵の列（名前は伏せる）

private struct DraftEnemyColumn: View {
    let draft: DraftEngine
    let hover: String?
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { i in row(i) }
        }
        .padding(5)
        .glass(cornerRadius: 12, tint: Theme.teamColor(.red, colorblind: app.profile.settings.colorblindMode).opacity(0.7))
    }

    private func row(_ i: Int) -> some View {
        let picks = draft.picks(for: .red)
        let active = draft.currentTurn?.team == .red && picks.count == i
        return HStack(spacing: 5) {
            Spacer(minLength: 0)
            Text(L("プレイヤー\(i + 1)", "Player \(i + 1)"))
                .font(Celestial.heading(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06))
                if i < picks.count {
                    HeroPortraitView(heroID: picks[i].heroID, size: 32, showsRole: false)
                        .transition(.scale(scale: 1.5).combined(with: .opacity))
                } else if active, let hover {
                    HeroPortraitView(heroID: hover, size: 32, showsRole: false).opacity(0.5)
                }
            }
            .frame(width: 32, height: 32)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(active ? Theme.danger : .clear, lineWidth: 1.5))
        }
        .padding(.horizontal, 4)
        .frame(height: 46)
        .accessibilityElement(children: .combine)
    }
}
