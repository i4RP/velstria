import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI055 スターパス（無料 30 段階 + プレミアムトラック）。

enum StarPassCellState: Equatable {
    /// この段に報酬が無い。
    case none
    /// レベル未到達。
    case locked
    /// 到達済みだがプレミアム未購入。
    case premiumLocked
    case claimable
    case claimed
}

struct StarPassSlot: Equatable {
    var level: Int
    var premium: Bool
}

enum StarPassTrack {
    static func level(_ profile: Profile) -> Int { LiveOpsService.passLevel(xp: profile.pass.xp) }

    /// 現在レベル内の XP 進捗（最大レベルでは満タン表示）。
    static func levelProgress(xp: Int) -> (current: Int, needed: Int) {
        let per = LiveOpsService.passXPPerLevel
        let level = LiveOpsService.passLevel(xp: xp)
        if level >= LiveOpsService.passMaxLevel { return (per, per) }
        return (min(per, max(0, xp - level * per)), per)
    }

    static func state(_ reward: PassReward, premium: Bool, profile: Profile) -> StarPassCellState {
        guard (premium ? reward.premium : reward.free) != nil else { return .none }
        let claimedList = premium ? profile.pass.claimedPremium : profile.pass.claimedFree
        if claimedList.contains(reward.level) { return .claimed }
        if reward.level > level(profile) { return .locked }
        if premium && !profile.pass.hasPremium { return .premiumLocked }
        return .claimable
    }

    /// 今すぐ受け取れる枠（レベル昇順、同レベルは無料 → プレミアム）。
    static func claimableSlots(_ rewards: [PassReward], profile: Profile) -> [StarPassSlot] {
        var slots: [StarPassSlot] = []
        for r in rewards.sorted(by: { $0.level < $1.level }) {
            if state(r, premium: false, profile: profile) == .claimable { slots.append(StarPassSlot(level: r.level, premium: false)) }
            if state(r, premium: true, profile: profile) == .claimable { slots.append(StarPassSlot(level: r.level, premium: true)) }
        }
        return slots
    }

    /// 表示開始位置（最初の受取可能段、無ければ次のレベル）。
    static func focusLevel(_ rewards: [PassReward], profile: Profile) -> Int {
        if let first = claimableSlots(rewards, profile: profile).first { return first.level }
        return min(LiveOpsService.passMaxLevel, level(profile) + 1)
    }

    static func seasonName(_ seasonID: String) -> String {
        if let n = Int(seasonID.drop { !$0.isNumber }) { return L("シーズン \(n)", "Season \(n)") }
        return seasonID
    }

    static let premiumTint = Color(red: 0.80, green: 0.55, blue: 1.0)
}

// MARK: - UI055

struct StarPassView: View {
    @Environment(AppModel.self) private var app
    @State private var reward: RewardClaimContent?
    @State private var purchasing = false
    @State private var showsPremiumInfo = false
    @State private var alert: PurchaseAlert?

    enum PurchaseAlert: Identifiable {
        case limit
        case failed(String)
        var id: String {
            switch self {
            case .limit: return "limit"
            case .failed(let m): return "failed-\(m)"
            }
        }
    }

    var body: some View {
        let rewards = LiveOpsService.passRewards().sorted { $0.level < $1.level }
        ScreenScaffold(title: L("スターパス", "Star Pass")) {
            VStack(spacing: 10) {
                summary(rewards)
                if rewards.isEmpty {
                    Panel {
                        LiveOpsEmptyState(symbol: "star.slash",
                                          title: L("報酬トラックを準備中です", "Reward track unavailable"),
                                          message: L("スターパスの報酬情報を読み込めませんでした。アプリを再起動してもう一度お試しください。",
                                                     "Star Pass rewards could not be loaded. Please restart the app and try again."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    track(rewards)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .rewardClaimPopup($reward)
        .alert(alertTitle, isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }), presenting: alert) { _ in
            Button(L("OK", "OK"), role: .cancel) {}
        } message: { a in
            switch a {
            case .limit:
                Text(L("年齢区分に応じた月間の購入上限を超えるため購入できません。来月以降にお試しください。",
                       "This purchase exceeds the monthly spending limit for your age group. Please try again next month."))
            case .failed(let message):
                Text(message)
            }
        }
    }

    private var alertTitle: String {
        switch alert {
        case .limit: return L("今月の購入上限に達しています", "Monthly limit reached")
        case .failed, .none: return L("購入できませんでした", "Purchase failed")
        }
    }

    // MARK: 概要

    private func summary(_ rewards: [PassReward]) -> some View {
        let pass = app.profile.pass
        let level = StarPassTrack.level(app.profile)
        let progress = StarPassTrack.levelProgress(xp: pass.xp)
        let claimable = StarPassTrack.claimableSlots(rewards, profile: app.profile)
        return Panel(padding: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Image(systemName: "seal.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(LinearGradient(colors: [Theme.gold, Theme.gold.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    VStack(spacing: -2) {
                        Text("Lv").font(.system(size: 10, weight: .heavy, design: .rounded))
                        Text("\(level)").font(.system(size: 20, weight: .black, design: .rounded)).monospacedDigit()
                    }
                    .foregroundStyle(Color.black.opacity(0.8))
                }
                .frame(width: 58, height: 58)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("パスレベル \(level)", "Pass level \(level)"))

                VStack(alignment: .leading, spacing: 5) {
                    Text(L("\(StarPassTrack.seasonName(pass.seasonID)) スターパス", "\(StarPassTrack.seasonName(pass.seasonID)) Star Pass"))
                        .font(Theme.heading(15))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    LiveOpsProgressBar(fraction: Double(progress.current) / Double(max(1, progress.needed)), tint: Theme.gold)
                        .frame(maxWidth: 220)
                    Text(level >= LiveOpsService.passMaxLevel ? L("最大レベル到達", "Max level reached")
                                                              : L("\(progress.current.formatted()) / \(progress.needed.formatted()) XP · 対戦とミッションで獲得",
                                                                  "\(progress.current.formatted()) / \(progress.needed.formatted()) XP · from matches & missions"))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                if !claimable.isEmpty {
                    Button {
                        claim(claimable)
                    } label: {
                        Label(L("一括受取 \(claimable.count)", "Claim \(claimable.count)"), systemImage: "gift.fill")
                            .fixedSize()
                    }
                    .buttonStyle(LiveOpsCompactButtonStyle(color: Theme.cyan))
                    .accessibilityIdentifier("starpass_claim_all")
                }
                premiumControl
            }
        }
    }

    @ViewBuilder
    private var premiumControl: some View {
        HStack(spacing: 6) {
            if app.profile.pass.hasPremium {
                LiveOpsTag(text: L("プレミアム有効", "Premium Active"), symbol: "crown.fill", color: Theme.gold)
                    .accessibilityIdentifier("starpass_premium_active")
            } else {
                Button {
                    buyPremium()
                } label: {
                    HStack(spacing: 6) {
                        if purchasing {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "crown.fill")
                        }
                        Text(L("プレミアム", "Premium"))
                        Text(app.storeKit.displayPrice(for: StoreKitService.premiumPassProductID))
                            .font(Theme.mono(13))
                    }
                    .fixedSize()
                }
                .buttonStyle(LiveOpsCompactButtonStyle(color: StarPassTrack.premiumTint))
                .disabled(purchasing || !FeatureFlags.inAppPurchases)
                .accessibilityLabel(L("プレミアムトラックを購入 \(app.storeKit.displayPrice(for: StoreKitService.premiumPassProductID))",
                                      "Buy Premium Track \(app.storeKit.displayPrice(for: StoreKitService.premiumPassProductID))"))
                .accessibilityIdentifier("starpass_buy_premium")
            }
            LiveOpsIconButton(symbol: "info.circle", label: L("プレミアムについて", "About Premium"), identifier: "starpass_premium_info") {
                showsPremiumInfo = true
            }
            .popover(isPresented: $showsPremiumInfo) {
                premiumInfo
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(Theme.bgTop)
            }
        }
    }

    private var premiumInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("プレミアムトラック", "Premium Track"), systemImage: "crown.fill")
                .font(Theme.heading(15))
                .foregroundStyle(Theme.gold)
            Text(L("購入すると、\(StarPassTrack.seasonName(app.profile.pass.seasonID)) のプレミアムトラックが解放され、到達済みの段を含むすべての段でプレミアム報酬（コスメ・ジェムなど）を受け取れます。",
                   "Unlocks the \(StarPassTrack.seasonName(app.profile.pass.seasonID)) premium track: claim premium rewards (cosmetics, gems and more) on every level, including ones already reached."))
            Text(L("報酬は見た目と通貨のみで、対戦での強さには影響しません。", "Rewards are cosmetic or currency only and never affect battle power."))
            if let remaining = app.storeKit.monthlyLimitRemaining(profile: app.profile) {
                Text(L("今月の購入可能残額: ¥\(remaining.formatted())", "Remaining monthly limit: ¥\(remaining.formatted())"))
                    .foregroundStyle(Theme.cyan)
            }
            Button {
                showsPremiumInfo = false
                app.router.push(.restorePurchases)
            } label: {
                Label(L("購入を復元", "Restore Purchases"), systemImage: "arrow.clockwise")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("starpass_restore")
        }
        .font(Theme.body(13))
        .foregroundStyle(Theme.textPrimary)
        .padding(16)
        .frame(width: 320)
    }

    // MARK: トラック

    private func track(_ rewards: [PassReward]) -> some View {
        let focus = StarPassTrack.focusLevel(rewards, profile: app.profile)
        let level = StarPassTrack.level(app.profile)
        // 画面の高さに合わせてマスの大きさを決める（16e〜Pro Max で 2 段が収まるように）
        return GeometryReader { geo in
            let side = StarPassCell.side(forAvailableHeight: geo.size.height)
            Panel(padding: 10) {
                HStack(spacing: 8) {
                    VStack(spacing: 8) {
                        Color.clear.frame(height: 28)
                        rowLabel(L("無料", "Free"), symbol: "gift.fill", tint: Theme.cyan, side: side)
                        rowLabel(L("プレミアム", "Premium"), symbol: "crown.fill", tint: Theme.gold, side: side)
                    }
                    .frame(width: 74)
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 0) {
                                ForEach(rewards, id: \.level) { r in
                                    column(r, reached: r.level <= level, side: side)
                                        .id(r.level)
                                }
                            }
                            .padding(.trailing, 12)
                        }
                        .onAppear {
                            proxy.scrollTo(focus, anchor: .center)
                        }
                    }
                }
                .frame(height: 28 + 16 + side * 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func rowLabel(_ title: String, symbol: String, tint: Color, side: CGFloat) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 74, height: side)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.10)))
        .accessibilityAddTraits(.isHeader)
    }

    private func column(_ r: PassReward, reached: Bool, side: CGFloat) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Rectangle()
                    .fill(reached ? Theme.gold.opacity(0.8) : Color.white.opacity(0.15))
                    .frame(height: 4)
                Text("\(r.level)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(reached ? Color.black.opacity(0.85) : Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(reached ? Theme.gold : Theme.panel))
                    .overlay(Circle().stroke(reached ? Color.white.opacity(0.6) : Theme.panelStroke, lineWidth: 1))
            }
            .frame(height: 28)
            .accessibilityHidden(true)
            StarPassCell(level: r.level, attachment: r.free, premium: false, side: side,
                         state: StarPassTrack.state(r, premium: false, profile: app.profile)) { tap(r, premium: false) }
            StarPassCell(level: r.level, attachment: r.premium, premium: true, side: side,
                         state: StarPassTrack.state(r, premium: true, profile: app.profile)) { tap(r, premium: true) }
        }
        .frame(width: side + 10)
    }

    // MARK: 操作

    private func tap(_ r: PassReward, premium: Bool) {
        let state = StarPassTrack.state(r, premium: premium, profile: app.profile)
        let attachment = premium ? r.premium : r.free
        let name = attachment.map { RewardClaimText.name($0) } ?? ""
        switch state {
        case .claimable:
            claim([StarPassSlot(level: r.level, premium: premium)])
        case .locked:
            app.audio.play(.uiTap)
            app.showToast(L("Lv \(r.level) で解放: \(name)", "Unlocks at Lv \(r.level): \(name)"))
        case .premiumLocked:
            app.audio.play(.uiTap)
            app.showToast(L("プレミアム解放で受け取れます: \(name)", "Go Premium to claim: \(name)"))
        case .claimed:
            app.showToast(L("受取済み: \(name)", "Already claimed: \(name)"))
        case .none:
            break
        }
    }

    private func claim(_ slots: [StarPassSlot]) {
        var p = app.profile
        var granted: [MailAttachment] = []
        for slot in slots {
            if let a = LiveOpsService.claimPass(level: slot.level, premium: slot.premium, profile: &p) {
                granted.append(a)
            }
        }
        guard !granted.isEmpty else {
            app.audio.play(.uiError)
            app.showToast(L("受け取れる報酬がありません", "Nothing to claim"))
            return
        }
        app.profile = p
        guard !RewardClaimText.merged(granted).isEmpty else {
            app.showToast(L("受け取りました", "Claimed"))
            return
        }
        let subtitle = slots.count == 1 ? L("スターパス Lv \(slots[0].level)", "Star Pass Lv \(slots[0].level)") : L("スターパス", "Star Pass")
        reward = RewardClaimContent(subtitle: subtitle, attachments: granted)
    }

    private func buyPremium() {
        guard !purchasing else { return }
        purchasing = true
        app.audio.play(.uiConfirm)
        Task {
            let result = await app.storeKit.purchasePremiumPass()
            purchasing = false
            switch result {
            case .success:
                app.audio.play(.purchase)
                app.haptics.success()
                app.showToast(L("プレミアムトラックが解放されました", "Premium track unlocked"))
            case .pending:
                app.showToast(L("購入は承認待ちです。承認後に反映されます。", "Purchase pending approval. It will apply once approved."))
            case .cancelled:
                break
            case .limitExceeded:
                app.audio.play(.uiError)
                alert = .limit
            case .failed(let message):
                app.audio.play(.uiError)
                alert = .failed(message)
            }
        }
    }
}

/// トラックの 1 マス。
private struct StarPassCell: View {
    /// パネル内余白 20・レベル行 28・行間 16 を除いた高さを 2 段で分ける（66〜100pt）。
    static func side(forAvailableHeight h: CGFloat) -> CGFloat {
        min(100, max(66, ((h - 20 - 28 - 16) / 2).rounded(.down)))
    }

    let level: Int
    let attachment: MailAttachment?
    let premium: Bool
    let side: CGFloat
    let state: StarPassCellState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(premium ? AnyShapeStyle(LinearGradient(colors: [StarPassTrack.premiumTint.opacity(0.28), Theme.gold.opacity(0.10)],
                                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(Color.white.opacity(0.06)))
                if let attachment {
                    VStack(spacing: 3) {
                        RewardClaimIcon(attachment: attachment, size: side * 0.46)
                        Text(RewardClaimText.chipText(attachment))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 4)
                    }
                    .opacity(state == .locked || state == .premiumLocked ? 0.55 : 1)
                } else {
                    Image(systemName: "minus").foregroundStyle(Theme.textSecondary.opacity(0.5))
                }
                stateOverlay
            }
            .frame(width: side, height: side)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(state == .claimable ? Theme.gold : Theme.panelStroke, lineWidth: state == .claimable ? 2 : 1)
            )
            .shadow(color: state == .claimable ? Theme.gold.opacity(0.55) : .clear, radius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state == .none)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("starpass_\(premium ? "premium" : "free")_\(level)")
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch state {
        case .claimed:
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.5))
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.success)
            }
        case .locked:
            corner("lock.fill", tint: Theme.textSecondary)
        case .premiumLocked:
            corner("crown.fill", tint: Theme.gold)
        case .claimable:
            Text(L("受取", "Claim"))
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.gold))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(4)
        case .none:
            EmptyView()
        }
    }

    private func corner(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .padding(4)
            .background(Circle().fill(Color.black.opacity(0.55)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(4)
    }

    private var accessibilityText: String {
        let track = premium ? L("プレミアム", "Premium") : L("無料", "Free")
        let name = attachment.map { RewardClaimText.name($0) } ?? L("報酬なし", "No reward")
        let status: String
        switch state {
        case .none: status = ""
        case .locked: status = L("未到達", "Locked")
        case .premiumLocked: status = L("プレミアム限定", "Premium only")
        case .claimable: status = L("受け取り可能", "Claimable")
        case .claimed: status = L("受取済み", "Claimed")
        }
        return "Lv \(level) \(track): \(name) \(status)"
    }
}
