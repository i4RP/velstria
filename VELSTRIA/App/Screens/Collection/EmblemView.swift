import SwiftUI
import VelstriaCore

// 担当: ui-collection。エンブレム（MLBB のエンブレム画面を写したもの。旧 UI043 ルーンの置き換え。docs/EMBLEMS.md）。
// 上に 7 つのセットのタブ（記号 + Lv。強化・解放できるセットに緑の上向きの矢印）と無料のエンブレム宝箱（残り時間）、
// 左にセット名とリング（右上 = 1 段目・左 = 2 段目・下 = コアの天賦）、右にステータス。
// リングの左下: 強化の費用（セットの記号「欠片+マジックダスト/必要な量」）と「アップグレード」、最大なら「MAX」、未解放なら「解放」。
// ステータスは次のレベルで変わる値に「→」、次のキーレベルの「コア属性大幅アップ」、解放レベル未満の段に鍵と「Lv○で解放」。
// 天賦の枠を押すとその段の天賦の一覧（装備中に ✓）と、名前・橙の小見出し・説明・「装備」/「装備中」。
// 左上の 🔍 はエンブレムステータス（現在/最大レベル）と天賦の説明、右下のボタンは一括設定（ヒーローを選んで付ける）。
// 天賦は組み換え自由（どのセットにもどの天賦でも付けられる。段は合わせる。付け替えに費用は無い）。

struct EmblemView: View {
    @Environment(AppModel.self) private var app
    /// 天賦を選んでいる段（nil = ステータスを表示）。
    @State private var pickingTier: EmblemTier?
    /// 一覧で選んで説明を見ている天賦。
    @State private var preview: EmblemTalentID?
    @State private var showsBulk = false
    @State private var showsDetail = false
    /// 宝箱を開けた時の受取ポップアップ。
    @State private var reward: RewardClaimContent?

    private var current: EmblemSetID { EmblemMath.selectedSet(app.profile) }

    var body: some View {
        let set = current
        let page = EmblemMath.page(set, profile: app.profile)
        let unlocked = EmblemMath.isUnlocked(set, profile: app.profile)
        ScreenScaffold(title: L("エンブレム", "Emblems")) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    setTabs
                    chestButton
                }
                HStack(alignment: .top, spacing: 12) {
                    ringPanel(set: set, page: page, unlocked: unlocked)
                        .frame(width: 330)
                    if let tier = pickingTier, unlocked {
                        pickerPanel(tier: tier, page: page)
                    } else {
                        statusPanel(set: set, page: page, unlocked: unlocked)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .animation(.easeInOut(duration: 0.2), value: pickingTier)
        }
        .rewardClaimPopup($reward)
        .onAppear(perform: refreshChest)
        .sheet(isPresented: $showsBulk) {
            EmblemBulkApplySheet(set: set).environment(app)
        }
        .sheet(isPresented: $showsDetail) {
            EmblemDetailSheet(page: page).environment(app)
        }
    }

    // MARK: セットのタブ

    private var setTabs: some View {
        HStack(spacing: 6) {
            ForEach(EmblemSetID.allCases, id: \.self) { set in
                setTab(set)
            }
        }
    }

    private func setTab(_ set: EmblemSetID) -> some View {
        let selected = current == set
        let color = EmblemStyle.color(set)
        let unlocked = EmblemMath.isUnlocked(set, profile: app.profile)
        let level = EmblemMath.level(set, profile: app.profile)
        // 強化か解放ができる（MLBB のタブの緑の上向きの矢印）
        let improvable = EmblemService.canImprove(set, profile: app.profile)
        let state = unlocked ? "Lv\(level)" : L("未解放", "Locked")
        return Button {
            guard !selected else { return }
            app.haptics.tap()
            app.profile.selectedEmblemSet = set.rawValue
            pickingTier = nil
            preview = nil
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(color.opacity(selected ? 0.35 : 0.18))
                    Circle().stroke(color.opacity(selected ? 1 : 0.5), lineWidth: 1.2)
                    Image(systemName: unlocked ? EmblemStyle.setSymbol(set) : "lock.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(unlocked ? color : Theme.textSecondary)
                }
                .frame(width: 32, height: 32)
                .overlay(alignment: .topTrailing) {
                    if improvable {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Theme.success)
                            .background(Circle().fill(Color.black.opacity(0.7)))
                            .offset(x: 4, y: -4)
                            .accessibilityHidden(true)
                    }
                }
                Text(state)
                    .font(Theme.mono(12))
                    .foregroundStyle(unlocked ? Theme.success : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? color.opacity(0.16) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? color : Theme.panelStroke.opacity(0.6), lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(EmblemMath.setName(set)) \(state)" + (improvable ? L("、強化できます", ", can be upgraded") : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("emblem_tab_\(set.rawValue)")
    }

    // MARK: 無料のエンブレム宝箱

    /// 宝箱のボタン（貯まった回数のバッジ。貯まっていなければ次の 1 回までの残り時間）。
    private var chestButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let charges = EmblemService.chestCharges(app.profile, now: now)
            let remaining = EmblemService.chestSecondsUntilNext(app.profile, now: now)
            let detail = charges > 0 ? L("受け取る", "Open") : (remaining.map(EmblemService.countdownText) ?? "")
            Button {
                openChest()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: EmblemStyle.chestSymbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(charges > 0 ? Theme.gold : Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .overlay(alignment: .topTrailing) { FlowCountBadge(count: charges).offset(x: 9, y: -9) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L("宝箱", "Chest"))
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(detail)
                            .font(Theme.mono(10))
                            .foregroundStyle(charges > 0 ? Theme.success : Theme.textSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.horizontal, 8)
                .frame(minWidth: 92, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(charges > 0 ? 0.10 : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(charges > 0 ? Theme.gold : Theme.panelStroke.opacity(0.6), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(charges == 0)
            .accessibilityLabel(L("無料のエンブレム宝箱", "Free Emblem Chest") + "、" + detail)
            .accessibilityIdentifier("emblem_chest")
        }
    }

    /// 貯まった分を保存に残す（数え始めの時刻を残す。開いた時）。
    private func refreshChest() {
        var p = app.profile
        EmblemService.refreshChest(profile: &p, now: Date())
        if p != app.profile { app.profile = p }
    }

    private func openChest() {
        var p = app.profile
        guard let granted = EmblemService.openChest(profile: &p, now: Date()) else {
            app.haptics.warning()
            return
        }
        app.profile = p
        app.haptics.success()
        reward = RewardClaimContent(title: L("無料のエンブレム宝箱", "Free Emblem Chest"), attachments: granted)
    }

    // MARK: リング（セット名・天賦 3 枠・🔍・強化 / MAX / 解放・一括設定）

    /// リングは空いた大きさに合わせて縮め（横画面の iPhone は中身の高さが 230pt 前後。縦に積むと画面より高くなり、
    /// 上の「戻る」の行が画面の外へ押し出されていた）、レベル・🔍・強化・一括設定はリングの四隅に重ねる（MLBB と同じ配置）。
    private func ringPanel(set: EmblemSetID, page: EmblemLoadout, unlocked: Bool) -> some View {
        let color = EmblemStyle.color(set)
        let maxed = EmblemMath.isMaxLevel(set, profile: app.profile)
        return Panel(padding: 12) {
            GeometryReader { geo in
                ring(set: set, page: page, unlocked: unlocked, color: color)
                    .scaleEffect(min(1, geo.size.height / 250, geo.size.width / 280))
                    .position(x: geo.size.width / 2 + 8, y: geo.size.height / 2 + 4)
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lv\(page.level)")
                        .font(Theme.title(24))
                        .foregroundStyle(Theme.gold)
                        .accessibilityIdentifier("emblem_level")
                    Text(EmblemMath.setName(set))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: 140, alignment: .leading)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    app.haptics.tap()
                    showsDetail = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.cyan)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("エンブレムステータス", "Emblem Details"))
                .accessibilityIdentifier("emblem_detail")
            }
            .overlay(alignment: .bottomLeading) {
                upgradeArea(set: set, unlocked: unlocked, maxed: maxed)
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    app.haptics.tap()
                    showsBulk = true
                } label: {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(color.opacity(0.35)))
                        .overlay(Circle().stroke(color, lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                .disabled(!unlocked)
                .accessibilityLabel(L("一括設定", "Apply to Heroes"))
                .accessibilityIdentifier("emblem_bulk")
            }
        }
    }

    /// リングと天賦の 3 枠（右上 = 1 段目・左 = 2 段目・下 = コア）。等倍で幅 210・高さ 211 ほど。
    private func ring(set: EmblemSetID, page: EmblemLoadout, unlocked: Bool, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(LinearGradient(colors: [color.opacity(0.9), Theme.cyan.opacity(0.5)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                .frame(width: 170, height: 170)
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.25), .clear], center: .center, startRadius: 4, endRadius: 85))
                .frame(width: 160, height: 160)
            Image(systemName: unlocked ? EmblemStyle.setSymbol(set) : "lock.fill")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(color.opacity(0.35))
            slot(.tier1, page: page, unlocked: unlocked).offset(x: 62, y: -62)
            slot(.tier2, page: page, unlocked: unlocked).offset(x: -86, y: 0)
            slot(.core, page: page, unlocked: unlocked).offset(x: 30, y: 82)
        }
    }

    /// リングの下の強化（費用の行と「アップグレード」）・「MAX」・「解放」（マジックダストの費用）。
    @ViewBuilder
    private func upgradeArea(set: EmblemSetID, unlocked: Bool, maxed: Bool) -> some View {
        if !unlocked {
            let can = EmblemService.canUnlock(set, profile: app.profile)
            Button {
                unlock(set)
            } label: {
                HStack(spacing: 4) {
                    Text(L("解放", "Unlock"))
                        .font(Theme.heading(13))
                    Image(systemName: EmblemStyle.dustSymbol)
                        .font(.system(size: 11, weight: .bold))
                    Text(EmblemMath.amountText(EmblemEconomy.unlockCost))
                        .font(Theme.mono(12))
                }
                .lineLimit(1)
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.cyan))
            .disabled(!can)
            .opacity(can ? 1 : 0.5)
            .accessibilityLabel(L("マジックダスト \(EmblemEconomy.unlockCost) で解放", "Unlock for \(EmblemEconomy.unlockCost) Magic Dust"))
            .accessibilityIdentifier("emblem_unlock")
        } else if maxed {
            Text("MAX")
                .font(Theme.heading(15))
                .foregroundStyle(Theme.gold)
                .accessibilityIdentifier("emblem_level_state")
        } else if let q = EmblemService.upgradeQuote(set, profile: app.profile) {
            // 費用の下にボタン（横に並べるとリング下のコアの枠に重なる）
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Image(systemName: set == .common ? EmblemStyle.dustSymbol : EmblemStyle.setSymbol(set))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(set == .common ? EmblemStyle.dustColor : EmblemStyle.color(set))
                    Text(EmblemMath.costText(q, set: set))
                        .font(Theme.mono(12))
                        .foregroundStyle(q.affordable ? Theme.textPrimary : Theme.danger)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("emblem_upgrade_cost")
                Button {
                    upgrade(set)
                } label: {
                    Text(L("アップグレード", "Upgrade"))
                        .font(Theme.heading(13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.success))
                .disabled(!q.affordable)
                .opacity(q.affordable ? 1 : 0.5)
                .accessibilityIdentifier("emblem_upgrade")
            }
        }
    }

    private func unlock(_ set: EmblemSetID) {
        var p = app.profile
        guard EmblemService.unlock(set, profile: &p) else {
            app.haptics.error()
            return
        }
        app.profile = p
        app.haptics.success()
        app.showToast(L("\(EmblemMath.setName(set))を解放しました", "Unlocked \(EmblemMath.setName(set))"))
    }

    private func upgrade(_ set: EmblemSetID) {
        var p = app.profile
        guard EmblemService.upgrade(set, profile: &p) else {
            app.haptics.error()
            return
        }
        app.profile = p
        app.haptics.success()
        let lv = EmblemMath.level(set, profile: p)
        if EmblemProgression.isKeyLevel(lv) {
            app.showToast(L("Lv\(lv) コア属性大幅アップ！", "Lv\(lv): core stat boosted!"))
        }
    }

    /// 天賦の枠（押すとその段の一覧。右下に入れ替えの印。解放レベル未満の段は鍵と「Lv○」）。
    private func slot(_ tier: EmblemTier, page: EmblemLoadout, unlocked: Bool) -> some View {
        let id = page.talent(tier)
        let selected = pickingTier == tier
        let open = EmblemProgression.isTierUnlocked(tier, level: page.level)
        let color = EmblemStyle.talentColor(id)
        let size: CGFloat = tier == .core ? 70 : 60
        return Button {
            guard unlocked else { return }
            app.haptics.tap()
            if selected {
                pickingTier = nil
                preview = nil
            } else {
                pickingTier = tier
                preview = id
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle().fill(Color.black.opacity(0.55))
                    Circle().stroke(selected ? Theme.gold : color.opacity(open ? 0.7 : 0.3), lineWidth: selected ? 3 : 2)
                    Image(systemName: EmblemStyle.talentSymbol(id))
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(color)
                        .opacity(open ? 1 : 0.25)
                    if !open {
                        VStack(spacing: 1) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Lv\(EmblemProgression.unlockLevel(tier))")
                                .font(Theme.mono(10))
                        }
                        .foregroundStyle(Theme.textPrimary)
                    }
                }
                .frame(width: size, height: size)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Theme.cyan.opacity(0.6)))
                    .offset(x: 2, y: 2)
                    .opacity(open ? 1 : 0)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(EmblemMath.tierLabel(tier))：\(EmblemMath.talentName(id))" + (open ? "" : "、" + EmblemMath.tierLockText(tier)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("emblem_slot_\(tier.rawValue)")
    }

    // MARK: ステータス

    private func statusPanel(set: EmblemSetID, page: EmblemLoadout, unlocked: Bool) -> some View {
        let def = EmblemCatalog.set(set)
        let color = EmblemStyle.color(set)
        return Panel(padding: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        SectionTitle(title: L("ステータス", "Stats"), symbol: "chart.bar.fill")
                        walletBadges(set: set)
                    }
                    ForEach(Array(def.attributes.enumerated()), id: \.offset) { _, a in
                        attributeRow(a, level: page.level, color: color, showsNext: unlocked)
                    }
                    // 次のキーレベル（「Lv30 コア属性大幅アップ 適応貫通」）
                    if unlocked, let key = EmblemMath.nextKeyLevelText(set, level: page.level) {
                        Label(key, systemImage: "arrow.up.circle.fill")
                            .font(Theme.body(12))
                            .foregroundStyle(EmblemStyle.keyLevelColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .accessibilityIdentifier("emblem_next_key")
                    }
                    SectionTitle(title: L("天賦", "Talents"), symbol: "sparkles")
                    ForEach(EmblemTier.allCases, id: \.self) { tier in
                        talentRow(tier, page: page)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// ステータスの 1 行（次のレベルで変わる値に「+1.20% → +1.30%」）。
    private func attributeRow(_ a: EmblemAttribute, level: Int, color: Color, showsNext: Bool) -> some View {
        let next = showsNext ? EmblemMath.nextValueText(a, level: level) : nil
        return HStack(spacing: 10) {
            Image(systemName: EmblemStyle.attributeSymbol(a.kind))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(EmblemMath.attributeName(a.kind))
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 5) {
                    Text(EmblemMath.attributeValue(a, level: level))
                        .font(Theme.mono(14))
                        .foregroundStyle(Theme.textPrimary)
                    if let next {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.success)
                        Text(next)
                            .font(Theme.mono(14))
                            .foregroundStyle(Theme.success)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// 天賦の 1 行（解放レベル未満の段は鍵と「Lv○で解放」）。
    private func talentRow(_ tier: EmblemTier, page: EmblemLoadout) -> some View {
        let id = page.talent(tier)
        let open = EmblemProgression.isTierUnlocked(tier, level: page.level)
        return HStack(spacing: 8) {
            Image(systemName: open ? EmblemStyle.talentSymbol(id) : "lock.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(open ? EmblemStyle.talentColor(id) : Theme.textSecondary)
                .frame(width: 22)
            Text("\(EmblemMath.tierLabel(tier))：\(EmblemMath.talentName(id))")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if !open {
                Text(EmblemMath.tierLockText(tier))
                    .font(Theme.body(11))
                    .foregroundStyle(EmblemStyle.keyLevelColor)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// マジックダストと、このセットの欠片（通常共通は欠片を使わない）。
    private func walletBadges(set: EmblemSetID) -> some View {
        HStack(spacing: 6) {
            walletBadge(symbol: EmblemStyle.dustSymbol, tint: EmblemStyle.dustColor, amount: app.profile.magicDust,
                        label: L("マジックダスト", "Magic Dust"), identifier: "emblem_dust")
            if set != .common {
                walletBadge(symbol: EmblemStyle.setSymbol(set), tint: EmblemStyle.color(set),
                            amount: EmblemService.fragments(set, profile: app.profile),
                            label: L("エンブレムの欠片", "Emblem Fragments"), identifier: "emblem_fragments")
            }
        }
    }

    private func walletBadge(symbol: String, tint: Color, amount: Int, label: String, identifier: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(EmblemMath.amountText(amount))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(amount)")
        .accessibilityIdentifier(identifier)
    }

    // MARK: 天賦の一覧

    private func pickerPanel(tier: EmblemTier, page: EmblemLoadout) -> some View {
        let options = EmblemCatalog.talents(tier: tier)
        let shown = preview.flatMap { $0.tier == tier ? $0 : nil } ?? page.talent(tier)
        let open = EmblemProgression.isTierUnlocked(tier, level: page.level)
        let columns = Array(repeating: GridItem(.fixed(58), spacing: 10), count: 3)
        return Panel(padding: 12) {
            HStack(alignment: .top, spacing: 12) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(options) { t in
                            talentOption(t.id, equipped: page.talent(tier) == t.id, shown: shown == t.id)
                                .opacity(open ? 1 : 0.6)
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.hidden)
                .frame(width: 210)
                talentDetail(shown, equipped: page.talent(tier) == shown, open: open)
            }
        }
    }

    private func talentOption(_ id: EmblemTalentID, equipped: Bool, shown: Bool) -> some View {
        let color = EmblemStyle.talentColor(id)
        return Button {
            app.haptics.selection()
            preview = id
        } label: {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle().fill(Color.black.opacity(0.5))
                    Circle().stroke(shown ? Theme.gold : color.opacity(0.45), lineWidth: shown ? 2.5 : 1.2)
                    Image(systemName: EmblemStyle.talentSymbol(id))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(color)
                }
                .frame(width: 54, height: 54)
                if equipped {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.success)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
            }
            .frame(minWidth: 54, minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(EmblemMath.talentName(id))\(equipped ? L("（装備中）", " (equipped)") : "")")
        .accessibilityAddTraits(shown ? .isSelected : [])
        .accessibilityIdentifier("emblem_talent_\(id.rawValue)")
    }

    private func talentDetail(_ id: EmblemTalentID, equipped: Bool, open: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(EmblemMath.talentName(id))
                    .font(Theme.heading(16))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 4)
                Button {
                    app.haptics.tap()
                    pickingTier = nil
                    preview = nil
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.cyan)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("戻る", "Back"))
                .accessibilityIdentifier("emblem_picker_back")
            }
            Rectangle().fill(Theme.panelStroke).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let sub = EmblemMath.talentSubtitle(id) {
                        Text(sub)
                            .font(Theme.body(13))
                            .foregroundStyle(EmblemStyle.keyLevelColor)
                    }
                    Text(EmblemMath.talentDescription(id))
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            Rectangle().fill(Theme.panelStroke).frame(height: 1)
            HStack {
                Spacer()
                if !open {
                    // 解放レベル未満の段（MLBB は「期間限定で全天賦解放」の間だけ全部付けられる）
                    Label(EmblemMath.tierLockText(id.tier), systemImage: "lock.fill")
                        .font(Theme.heading(14))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("emblem_tier_locked")
                } else if equipped {
                    Text(L("装備中", "Equipped"))
                        .font(Theme.heading(14))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("emblem_equipped")
                } else {
                    Button {
                        equip(id)
                    } label: {
                        Text(L("装備", "Equip"))
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.cyan))
                    .accessibilityIdentifier("emblem_equip")
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func equip(_ id: EmblemTalentID) {
        var p = app.profile
        EmblemMath.equip(id, set: current, profile: &p)
        app.profile = p
        app.haptics.success()
    }
}

// MARK: - 一括設定

/// MLBB の「一括設定」: ロールのタブと全選択で、このセットと天賦を付けるヒーローを選ぶ。
struct EmblemBulkApplySheet: View {
    let set: EmblemSetID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var filter: EmblemHeroFilter = .all
    @State private var selected: Set<String> = []
    @State private var prepared = false

    var body: some View {
        let heroes = EmblemMath.bulkCandidates(filter: filter, profile: app.profile, master: app.master)
        let columns = [GridItem(.adaptive(minimum: 72, maximum: 90), spacing: 10)]
        return ZStack {
            CelestialBackdrop()
            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    Text(L("一括設定", "Apply to Heroes"))
                        .font(Theme.title(20))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    FlowCloseButton(identifier: "emblem_bulk_close") { dismiss() }
                }
                HStack(spacing: 6) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(EmblemMath.bulkFilters(profile: app.profile, master: app.master)) { f in
                                CollectionFilterChip(title: f.title, isSelected: filter == f) {
                                    app.haptics.tap()
                                    filter = f
                                }
                                .accessibilityIdentifier("emblem_bulk_filter_\(f.rawValue)")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    Button {
                        app.haptics.tap()
                        let ids = Set(heroes.map(\.heroID))
                        if ids.isSubset(of: selected) {
                            selected.subtract(ids)
                        } else {
                            selected.formUnion(ids)
                        }
                    } label: {
                        Label(L("全選択", "Select All"), systemImage: "checkmark.square")
                            .lineLimit(1)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("emblem_bulk_all")
                }
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(heroes) { h in
                            heroCell(h)
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.hidden)
                Text(L("エンブレムを適用するヒーローを選んでください", "Choose the heroes to apply this emblem to"))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    apply()
                } label: {
                    Text("OK").frame(minWidth: 120)
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.cyan))
                .disabled(selected.isEmpty)
                .accessibilityIdentifier("emblem_bulk_ok")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !prepared else { return }
            prepared = true
            selected = EmblemMath.heroesUsing(EmblemMath.page(set, profile: app.profile), profile: app.profile)
        }
    }

    private func heroCell(_ h: HeroDef) -> some View {
        let on = selected.contains(h.heroID)
        return Button {
            app.haptics.selection()
            if on { selected.remove(h.heroID) } else { selected.insert(h.heroID) }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                HeroPortraitView(heroID: h.heroID, size: 64, showsRole: false)
                    .opacity(on ? 1 : 0.75)
                    .overlay(Circle().stroke(on ? Theme.gold : Color.clear, lineWidth: 2.5))
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.success)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
            }
            .frame(minWidth: 64, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MasterText.hero(h))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("emblem_bulk_hero_\(h.heroID)")
    }

    private func apply() {
        var p = app.profile
        let n = EmblemMath.apply(set: set, to: selected.sorted(), profile: &p)
        app.profile = p
        app.haptics.success()
        app.showToast(L("\(n) 体のヒーローにエンブレムを適用しました", "Applied the emblem to \(n) heroes"))
        dismiss()
    }
}

// MARK: - 🔍 エンブレムステータス

/// 🔍 の画面: 「エンブレムステータス：現在/最大レベル」（セットの 3 つの能力値）と「エンブレム天賦：」（付けている 3 つの説明）。
struct EmblemDetailSheet: View {
    let page: EmblemLoadout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let def = EmblemCatalog.set(page.set)
        let color = EmblemStyle.color(page.set)
        return ZStack {
            CelestialBackdrop()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: EmblemStyle.setSymbol(page.set)).foregroundStyle(color)
                    Text("\(EmblemMath.setName(page.set))  Lv\(page.level)")
                        .font(Theme.title(18))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    FlowCloseButton(identifier: "emblem_detail_close") { dismiss() }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("エンブレムステータス：現在/最大レベル", "Emblem stats: current / max level"))
                            .font(Theme.heading(14))
                            .foregroundStyle(Theme.gold)
                        ForEach(Array(def.attributes.enumerated()), id: \.offset) { _, a in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(EmblemMath.attributeName(a.kind))
                                        .font(Theme.body(13))
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text(EmblemMath.currentMaxText(a, level: page.level))
                                        .font(Theme.mono(13))
                                        .foregroundStyle(Theme.textPrimary)
                                }
                                // 用語説明（混合・適応の意味。日本語クライアントの文）
                                if let g = EmblemMath.attributeGlossary(a.kind) {
                                    Text(g)
                                        .font(Theme.body(10))
                                        .foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text(L("エンブレム天賦：", "Emblem talents:"))
                            .font(Theme.heading(14))
                            .foregroundStyle(Theme.gold)
                            .padding(.top, 4)
                        ForEach(EmblemTier.allCases, id: \.self) { tier in
                            let id = page.talent(tier)
                            // 解放レベル未満の段は試合で働かない（「Lv○で解放」）
                            let open = EmblemProgression.isTierUnlocked(tier, level: page.level)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(EmblemMath.tierLabel(tier))：\(EmblemMath.talentName(id))"
                                     + (open ? "" : "（\(EmblemMath.tierLockText(tier))）"))
                                    .font(Theme.heading(13))
                                    .foregroundStyle(open ? EmblemStyle.talentColor(id) : Theme.textSecondary)
                                Text(EmblemMath.talentDescription(id))
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .preferredColorScheme(.dark)
    }
}

/// エンブレム 1 式の小さな表示（セットの記号 + 天賦 3 つの記号と名前）。ヒーロー詳細のバトルプラン・出撃準備で使う。
struct EmblemLoadoutBadge: View {
    let emblem: EmblemLoadout
    var compact = false

    var body: some View {
        let color = EmblemStyle.color(emblem.set)
        HStack(spacing: 6) {
            Image(systemName: EmblemStyle.setSymbol(emblem.set))
                .font(.system(size: compact ? 11 : 13, weight: .bold))
                .foregroundStyle(color)
                .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
                .background(Circle().fill(color.opacity(0.18)))
                .overlay(Circle().stroke(color.opacity(0.7), lineWidth: 1))
            ForEach(emblem.talents, id: \.self) { t in
                HStack(spacing: 3) {
                    Image(systemName: EmblemStyle.talentSymbol(t))
                        .font(.system(size: compact ? 9 : 11, weight: .bold))
                        .foregroundStyle(EmblemStyle.talentColor(t))
                    Text(EmblemMath.talentName(t))
                        .font(Theme.body(compact ? 9 : 11))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EmblemMath.summary(emblem))
    }
}
