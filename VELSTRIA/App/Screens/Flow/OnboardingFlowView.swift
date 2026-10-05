import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI001 起動 → UI002 年齢確認 → UI003 規約 → UI004 プレイヤー名 → UI006 初回準備 → チュートリアル案内。
// 途中で終了しても、保存済みの項目は飛ばして未完了のステップから再開する。

struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var app
    @State private var step: OnboardingStep = .splash

    var body: some View {
        ZStack {
            StarfieldBackground()
            content
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            if step != .splash {
                VStack {
                    OnboardingStepHeader(step: step)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.55, bounce: 0.12), value: step)
        .onAppear { app.audio.playMusic(.menu) }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .splash: OnboardingSplashStep { advance() }
        case .age: OnboardingAgeStep { advance() }
        case .terms:
            TermsAgreementView(isUpdate: false) { advance() }
                .padding(.top, 58)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        case .name: OnboardingNameStep { advance() }
        case .prepare: OnboardingPrepareStep { advance() }
        case .tutorial: OnboardingTutorialStep()
        }
    }

    /// 保存済みの内容から次の未完了ステップへ。
    private func advance() {
        FlowFX.confirm(app)
        step = OnboardingStep.firstPending(for: app.profile)
    }
}

// MARK: - 進捗ヘッダ

private struct OnboardingStepHeader: View {
    let step: OnboardingStep

    private func title(_ s: OnboardingStep) -> String {
        switch s {
        case .splash: return ""
        case .age: return L("年齢確認", "Age")
        case .terms: return L("利用規約", "Terms")
        case .name: return L("プレイヤー名", "Name")
        case .prepare: return L("初回準備", "Setup")
        case .tutorial: return L("チュートリアル", "Tutorial")
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("STEP \(step.stepNumber)/\(OnboardingStep.countedSteps)")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.gold)
            ForEach(OnboardingStep.allCases.filter { $0 != .splash }, id: \.self) { s in
                HStack(spacing: 5) {
                    Circle()
                        .fill(s <= step ? Theme.gold : Color.white.opacity(0.2))
                        .frame(width: 8, height: 8)
                    Text(title(s))
                        .font(Theme.body(11))
                        .foregroundStyle(s == step ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("ステップ \(step.stepNumber) / \(OnboardingStep.countedSteps)、\(title(step))",
                              "Step \(step.stepNumber) of \(OnboardingStep.countedSteps), \(title(step))"))
    }
}

// MARK: - UI001 起動

private struct OnboardingSplashStep: View {
    let onStart: () -> Void
    @State private var appeared = false

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    var body: some View {
        GeometryReader { geo in
            Button(action: onStart) {
                ZStack {
                    Color.clear.contentShape(Rectangle())
                    VStack(spacing: 22) {
                        VelstriaLogoView(scale: min(1.1, geo.size.width / 640, geo.size.height / 300))
                            .scaleEffect(appeared ? 1 : 0.82)
                            .opacity(appeared ? 1 : 0)
                            .blur(radius: appeared ? 0 : 8)
                        Text(L("タップしてスタート", "TAP TO START"))
                            .font(Theme.heading(16))
                            .tracking(4)
                            .foregroundStyle(Theme.textPrimary)
                            .phaseAnimator([0.35, 1.0]) { v, a in v.opacity(appeared ? a : 0) } animation: { _ in .easeInOut(duration: 1.1) }
                    }
                    VStack {
                        Spacer()
                        HStack {
                            Text("© 2026 VELSIA")
                            Spacer()
                            Text("v\(version)")
                        }
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("タップしてスタート", "Tap to start"))
            .accessibilityIdentifier("onb_start")
        }
        .onAppear {
            withAnimation(.spring(duration: 1.2, bounce: 0.2)) { appeared = true }
        }
    }
}

// MARK: - UI002 年齢確認

private struct OnboardingAgeStep: View {
    let onNext: () -> Void
    @Environment(AppModel.self) private var app
    @State private var selection: AgeBracket?

    static func label(_ a: AgeBracket) -> String {
        switch a {
        case .under13: return L("13歳未満", "Under 13")
        case .age13to15: return L("13〜15歳", "13–15")
        case .age16to19: return L("16〜19歳", "16–19")
        case .adult: return L("20歳以上", "20 or older")
        }
    }

    static func limitText(_ a: AgeBracket) -> String {
        guard let limit = a.monthlySpendLimitJPY else { return L("購入上限なし", "No monthly limit") }
        return L("月 \(limit.formatted()) 円まで", "Up to ¥\(limit.formatted()) / month")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("年齢の確認", "Confirm Your Age"))
                    .font(Theme.title(26))
                    .foregroundStyle(Theme.textPrimary)
                Text(L("ゲーム内通貨の購入上限を設定するため、あなたの年齢区分を選んでください。",
                       "Choose your age group so we can apply the right monthly purchase limit."))
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    limitRow(L("15歳以下", "15 and under"), L("月 5,000 円まで", "¥5,000 / month"))
                    limitRow(L("16〜19歳", "16–19"), L("月 10,000 円まで", "¥10,000 / month"))
                    limitRow(L("20歳以上", "20 and over"), L("上限なし", "No limit"))
                }
                .padding(12)
                .glass(cornerRadius: 12)
                Label(L("未成年の方は、保護者の同意を得てから購入してください。", "If you are a minor, get a parent's permission before purchasing."),
                      systemImage: "person.2.fill")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.cyan)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 320)

            VStack(spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(AgeBracket.allCases) { a in
                        Button {
                            FlowFX.tap(app)
                            withAnimation(.spring(duration: 0.3)) { selection = a }
                        } label: {
                            ageCard(a)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("onb_age_\(a.rawValue)")
                        .accessibilityAddTraits(selection == a ? .isSelected : [])
                    }
                }
                Button {
                    guard let selection else { return }
                    app.profile.ageBracket = selection
                    onNext()
                } label: {
                    Text(L("決定", "Confirm")).frame(minWidth: 180)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selection == nil)
                .opacity(selection == nil ? 0.5 : 1)
                .accessibilityIdentifier("onb_age_next")
            }
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { selection = app.profile.ageBracket }
    }

    private func limitRow(_ age: String, _ limit: String) -> some View {
        HStack {
            Text(age).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(limit).font(Theme.mono(12)).foregroundStyle(Theme.gold)
        }
    }

    private func ageCard(_ a: AgeBracket) -> some View {
        let selected = selection == a
        return HStack(spacing: 10) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(selected ? Theme.gold : Theme.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.label(a))
                    .font(Theme.heading(17))
                    .foregroundStyle(Theme.textPrimary)
                Text(Self.limitText(a))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 66)
        .glass(cornerRadius: 14, tint: selected ? Theme.gold : Theme.panelStroke, highlighted: selected)
        .scaleEffect(selected ? 1.02 : 1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - UI003 利用規約（初回・改定時の再同意で共用）

struct TermsAgreementView: View {
    var isUpdate: Bool
    let onAccept: () -> Void
    @Environment(AppModel.self) private var app
    @State private var agreed = false

    private struct Section: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let body: String
    }

    private var sections: [Section] {
        [
            Section(id: 0, symbol: "gamecontroller.fill", title: L("サービス内容", "The Service"),
                    body: L("VELSIA は端末内で完結するオフラインの 5v5 対戦ゲームです。味方と敵はすべて AI が操作します。インターネット接続は不要です。",
                            "VELSIA is an offline 5v5 game that runs entirely on your device. All allies and enemies are controlled by AI. No internet connection is required.")),
            Section(id: 1, symbol: "diamond.fill", title: L("有償アイテム", "Paid Items"),
                    body: L("AstralGem はスキンなどの見た目アイテム（コスメ）に使えます。ヒーローはプレイで貯まる StarlightCoin で解放します。戦闘能力を高める商品は販売しません。年齢区分に応じた月間購入上限があり、返金は Apple の規約に従います。有償・無償の Gem は区別して管理し、無償分から先に消費します。",
                            "AstralGems are used for cosmetics. Heroes are unlocked with StarlightCoins earned by playing. We never sell combat power. Monthly limits apply by age group, and refunds follow Apple's policies. Paid and free Gems are tracked separately; free Gems are spent first.")),
            Section(id: 2, symbol: "lock.shield.fill", title: L("データの取り扱い", "Your Data"),
                    body: L("プレイデータはこの端末内にのみ保存され、外部のサーバーへ送信されません。広告や行動追跡は行いません。お問い合わせの際は、あなたが送信したメールの内容のみを受け取ります。",
                            "Your play data is stored only on this device and is never sent to external servers. There is no advertising or tracking. When you contact support, we only receive the email you choose to send.")),
            Section(id: 3, symbol: "hand.raised.fill", title: L("禁止事項", "Prohibited Conduct"),
                    body: L("アプリの改ざん、不正な手段による通貨やアイテムの取得、公序良俗に反するプレイヤー名の使用を禁止します。",
                            "Tampering with the app, obtaining currency or items by illegitimate means, and offensive player names are prohibited.")),
            Section(id: 4, symbol: "externaldrive.fill", title: L("バックアップ", "Backups"),
                    body: L("端末の故障や削除でデータが失われることがあります。「アカウント連携」画面からバックアップファイルを作成できます。",
                            "Data may be lost if your device is damaged or the app is deleted. You can create a backup file from the Account & Data screen.")),
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections) { s in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(s.title, systemImage: s.symbol)
                                .font(Theme.heading(15))
                                .foregroundStyle(Theme.gold)
                            Text(s.body)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textPrimary.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(L("規約バージョン \(FeatureFlags.currentTermsVersion)", "Terms version \(FeatureFlags.currentTermsVersion)"))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .glass(cornerRadius: 16)
            .accessibilityIdentifier("onb_terms_scroll")

            VStack(alignment: .leading, spacing: 10) {
                Text(isUpdate ? L("利用規約の更新", "Updated Terms") : L("利用規約", "Terms of Service"))
                    .font(Theme.title(24))
                    .foregroundStyle(Theme.textPrimary)
                Text(isUpdate
                     ? L("利用規約が更新されました。内容を確認し、同意のうえでご利用ください。", "Our terms have been updated. Please review and accept them to continue.")
                     : L("ご利用の前に、要約と全文をご確認ください。", "Please review the summary and the full documents before playing."))
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: FeatureFlags.termsURL) {
                    linkRow(L("利用規約（全文）", "Terms of Service (full)"), symbol: "doc.text.fill")
                }
                .accessibilityIdentifier("onb_terms_link")
                Link(destination: FeatureFlags.privacyPolicyURL) {
                    linkRow(L("プライバシーポリシー", "Privacy Policy"), symbol: "hand.raised.square.fill")
                }
                .accessibilityIdentifier("onb_privacy_link")
                Button {
                    FlowFX.tap(app)
                    withAnimation(.spring(duration: 0.25)) { agreed.toggle() }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: agreed ? "checkmark.square.fill" : "square")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(agreed ? Theme.gold : Theme.textSecondary)
                        Text(L("利用規約とプライバシーポリシーに同意します", "I agree to the Terms of Service and Privacy Policy"))
                            .font(Theme.heading(13))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(agreed ? .isSelected : [])
                .accessibilityIdentifier("onb_terms_accept")
                Spacer(minLength: 4)
                Button {
                    app.profile.acceptedTermsVersion = FeatureFlags.currentTermsVersion
                    onAccept()
                } label: {
                    Text(L("同意して進む", "Accept & Continue")).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!agreed)
                .opacity(agreed ? 1 : 0.5)
                .accessibilityIdentifier("onb_terms_next")
            }
            .frame(width: 290)
        }
    }

    private func linkRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Theme.cyan)
            Text(title).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Image(systemName: "arrow.up.right.square").foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .glass(cornerRadius: 10)
    }
}

/// 規約改定時の再同意（ホームから全画面で表示）。
struct TermsUpdateView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            StarfieldBackground()
            TermsAgreementView(isUpdate: true) {
                FlowFX.confirm(app)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - UI004 プレイヤー名

private struct OnboardingNameStep: View {
    let onNext: () -> Void
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var suggestionSeed: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)
    @FocusState private var focused: Bool

    private var issue: PlayerNameRules.Issue? { PlayerNameRules.validate(name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("プレイヤー名を決めましょう", "Choose Your Player Name"))
                .font(Theme.title(26))
                .foregroundStyle(Theme.textPrimary)
            Text(L("\(PlayerNameRules.minLength)〜\(PlayerNameRules.maxLength) 文字。あとからプロフィールで変更できます。",
                   "\(PlayerNameRules.minLength)–\(PlayerNameRules.maxLength) characters. You can change it later in your profile."))
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "person.fill").foregroundStyle(Theme.cyan)
                    TextField(L("プレイヤー名", "Player name"), text: $name)
                        .font(Theme.heading(18))
                        .foregroundStyle(Theme.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit(submit)
                        .accessibilityIdentifier("onb_name_field")
                    Text("\(PlayerNameRules.normalized(name).count)/\(PlayerNameRules.maxLength)")
                        .font(Theme.mono(12))
                        .foregroundStyle(issue == .tooLong ? Theme.danger : Theme.textSecondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .glass(cornerRadius: 14, tint: focused ? Theme.cyan : Theme.panelStroke, highlighted: focused)

                Button {
                    FlowFX.tap(app)
                    suggestionSeed &+= 0x9E37_79B9_7F4A_7C15
                    name = PlayerNameRules.suggestion(seed: suggestionSeed, english: Loc.isEnglish)
                } label: {
                    Image(systemName: "dice.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.gold)
                        .frame(width: 52, height: 52)
                        .glass(cornerRadius: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("名前の候補", "Suggest a name"))
                .accessibilityIdentifier("onb_name_random")

                Button(action: submit) {
                    Text(L("決定", "Confirm")).frame(minWidth: 110)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(issue != nil)
                .opacity(issue == nil ? 1 : 0.5)
                .accessibilityIdentifier("onb_name_next")
            }
            Group {
                if let issue, !name.isEmpty {
                    Label(PlayerNameRules.message(issue), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                } else {
                    Label(L("名前は他のプレイヤーに公開されません（オフライン）。", "Your name stays on this device (offline)."),
                          systemImage: "lock.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .font(Theme.body(12))
            Spacer()
        }
        .frame(maxWidth: 640, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            name = app.profile.displayName
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                focused = true
            }
        }
    }

    private func submit() {
        guard issue == nil else {
            FlowFX.error(app)
            return
        }
        focused = false
        app.profile.displayName = PlayerNameRules.normalized(name)
        onNext()
    }
}

// MARK: - UI006 初回準備

private struct OnboardingPrepareStep: View {
    let onFinish: () -> Void
    @Environment(AppModel.self) private var app
    @State private var progress: Double = 0
    @State private var phaseText = ""
    @State private var finished = false
    @State private var tipIndex = Int(Date().timeIntervalSince1970) % max(1, FlowTips.all.count)

    var body: some View {
        VStack(spacing: 14) {
            Text(L("初回準備", "First-time Setup"))
                .font(Theme.title(26))
                .foregroundStyle(Theme.textPrimary)
            ZStack {
                StarRingView(speed: 0.2)
                    .frame(width: 300, height: 90)
                if finished {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(Theme.success)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            VStack(spacing: 6) {
                HStack {
                    Text(phaseText)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.opacity)
                    Spacer()
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.gold)
                        .monospacedDigit()
                }
                FlowProgressBar(value: progress, tint: Theme.gold, height: 10)
            }
            .frame(maxWidth: 520)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("onb_prepare_progress")

            TipCard(tip: FlowTips.all[tipIndex % FlowTips.all.count])
                .frame(maxWidth: 520)
                .id(tipIndex)
                .transition(.opacity)

            Label(L("通信は行いません。すべて端末内で準備します。", "No download needed — everything is prepared on your device."),
                  systemImage: "wifi.slash")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await run() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.6))
                withAnimation(.easeInOut(duration: 0.4)) { tipIndex += 1 }
            }
        }
    }

    /// 実処理（マスター走査 → テキスト → 1 秒のヘッドレス試合 → 保存）と表示の進行。
    private func run() async {
        let master = app.master
        phaseText = L("マスターデータを読み込み中…", "Loading master data…")
        _ = FlowWarmUp.touchMasterData(master)
        await ramp(to: 0.25, duration: 0.5)

        phaseText = L("表示テキストを準備中…", "Preparing text…")
        _ = FlowWarmUp.warmTexts(master)
        await ramp(to: 0.4, duration: 0.35)

        phaseText = L("戦場を構築中…", "Building the battlefield…")
        let work = Task.detached(priority: .userInitiated) { FlowWarmUp.runSimulationWarmUp() }
        await ramp(to: 0.85, duration: 1.2)
        _ = await work.value
        if Task.isCancelled { return }

        phaseText = L("セーブデータを作成中…", "Creating save data…")
        app.profile.firstResourcePrepared = true
        app.persistence.saveNow(app.profile)
        await ramp(to: 1.0, duration: 0.35)

        phaseText = L("準備完了", "Ready")
        withAnimation(.spring(duration: 0.4)) { finished = true }
        app.audio.play(.reward)
        try? await Task.sleep(for: .milliseconds(700))
        if Task.isCancelled { return }
        onFinish()
    }

    private func ramp(to target: Double, duration: Double) async {
        let from = progress
        let steps = max(1, Int(duration * 30))
        for i in 1...steps {
            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(33))
            let t = Double(i) / Double(steps)
            progress = from + (target - from) * (1 - pow(1 - t, 2))
        }
        progress = target
    }
}

// MARK: - チュートリアル案内

private struct OnboardingTutorialStep: View {
    @Environment(AppModel.self) private var app
    @State private var heroID = "H002"

    private var candidates: [HeroDef] {
        let starters = ["H001", "H002", "H003", "H004", "H005", "H006"]
        let owned = starters.filter { app.owns(heroID: $0) }
        let ids = owned.isEmpty ? Array(app.profile.ownedHeroIDs.prefix(6)) : owned
        return ids.compactMap { app.master.hero($0) }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("チュートリアルに挑戦", "Try the Tutorial"))
                    .font(Theme.title(26))
                    .foregroundStyle(Theme.textPrimary)
                Text(L("5 分ほどで基本操作を覚えられます。", "Learn the basics in about 5 minutes."))
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 6) {
                    bullet("figure.walk", L("移動と通常攻撃", "Moving and basic attacks"))
                    bullet("sparkles", L("スキルとバトルスペル", "Skills and battle spells"))
                    bullet("building.columns.fill", L("ミニオンとタワー", "Minions and towers"))
                    bullet("house.fill", L("帰還と回復", "Recalling and healing"))
                }
                .padding(12)
                .glass(cornerRadius: 12)
                HStack(spacing: 12) {
                    Button(action: start) {
                        Label(L("チュートリアルを始める", "Start Tutorial"), systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("onb_tutorial_start")
                    Button(action: skip) {
                        Text(L("スキップ", "Skip"))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onb_tutorial_skip")
                }
                Text(L("あとからホームの「練習場」やチュートリアルメニューでも遊べます。", "You can play it later from Practice or the Tutorial menu."))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 360)

            VStack(alignment: .leading, spacing: 8) {
                FlowSectionTitle(title: L("使用するヒーロー", "Choose a Hero"), symbol: "person.fill")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 8), count: 3), spacing: 8) {
                    ForEach(candidates) { h in
                        Button {
                            FlowFX.tap(app)
                            heroID = h.heroID
                        } label: {
                            HeroGridCell(hero: h, selected: heroID == h.heroID, size: 60)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("onb_tutorial_hero_\(h.heroID)")
                    }
                }
                if let h = app.master.hero(heroID) {
                    HStack(spacing: 6) {
                        RoleLabel(role: h.role)
                        Text("·").foregroundStyle(Theme.textSecondary)
                        Text(L("操作難度", "Difficulty")).font(Theme.body(11)).foregroundStyle(Theme.textSecondary)
                        HStack(spacing: 1) {
                            ForEach(0..<5, id: \.self) { i in
                                Image(systemName: i < h.difficulty ? "star.fill" : "star")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.gold)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .glass(cornerRadius: 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !candidates.contains(where: { $0.heroID == heroID }), let first = candidates.first { heroID = first.heroID }
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(Theme.body(13))
            .foregroundStyle(Theme.textPrimary)
    }

    private func start() {
        FlowFX.confirm(app)
        var p = app.profile
        p.onboardingCompleted = true
        p.lastPickedHeroID = heroID
        app.profile = p
        let name = p.displayName.isEmpty ? "Player" : p.displayName
        let seed = UInt64(Date().timeIntervalSince1970 * 1000)
        let config = MatchFactory.practiceMatch(humanHeroID: heroID, humanName: name, options: PracticeOptions(),
                                                tutorial: true, seed: seed, master: app.master)
        app.startBattle(BattleLaunch(config: config))
    }

    private func skip() {
        FlowFX.tap(app)
        app.profile.onboardingCompleted = true
        app.showToast(L("ようこそ、\(app.profile.displayName) さん！", "Welcome, \(app.profile.displayName)!"))
    }
}

// MARK: - ヒント（初回準備・ロード画面で共用）

struct FlowTip: Equatable {
    let symbol: String
    let ja: String
    let en: String
    var text: String { L(ja, en) }
}

enum FlowTips {
    static let all: [FlowTip] = [
        FlowTip(symbol: "hand.tap.fill", ja: "スキルボタンはタップで自動照準、ドラッグで手動照準。", en: "Tap a skill to auto-aim, or drag to aim it yourself."),
        FlowTip(symbol: "building.columns.fill", ja: "タワーは味方ミニオンと一緒に攻めましょう。ミニオンがいないとダメージが半減します。", en: "Attack towers with your minions — without them your tower damage is halved."),
        FlowTip(symbol: "flame.fill", ja: "星喰竜は 2:00 に出現。倒すとチーム全員にゴールドと与ダメージ強化。", en: "The Astral Wyrm spawns at 2:00 and grants your whole team gold and bonus damage."),
        FlowTip(symbol: "house.fill", ja: "HP が減ったら帰還（6 秒）で泉に戻って回復しましょう。", en: "Low on HP? Recall (6s) to heal at your fountain."),
        FlowTip(symbol: "leaf.fill", ja: "草むらの中にいると、近くにいない敵からは見えません。", en: "Hide in brush — enemies can't see you unless they're close."),
        FlowTip(symbol: "dollarsign.circle.fill", ja: "ミニオンやモンスターはラストヒットした人だけがゴールドを得ます。", en: "Only the last hit on minions and monsters earns gold."),
        FlowTip(symbol: "figure.stand", ja: "古環の巨像は 8:00 に出現。加護中は帰還が 2 秒になります。", en: "The Ancient Colossus spawns at 8:00. Its blessing shortens Recall to 2s."),
        FlowTip(symbol: "shield.lefthalf.filled", ja: "外塔は開始から 4 分間、受けるダメージが 40% 減少します。", en: "Outer towers take 40% less damage for the first 4 minutes."),
        FlowTip(symbol: "pawprint.fill", ja: "ジャングル担当はバトルスペル「狩猟印」を忘れずに。", en: "Jungling? Don't forget the Hunter's Mark battle spell."),
        FlowTip(symbol: "flag.fill", ja: "降参は 8:00 以降に提案できます。", en: "You can propose a surrender after 8:00."),
        FlowTip(symbol: "play.rectangle.fill", ja: "試合のリプレイは戦績画面から再生できます。", en: "Watch replays of your matches from Match History."),
        FlowTip(symbol: "sun.max.fill", ja: "毎日最初の勝利で初勝利ボーナス 300 コインを獲得できます。", en: "Your first win each day earns a 300-coin bonus."),
    ]

    /// シードから開始位置を決める（ロード毎に違うヒントを出す）。
    static func startIndex(seed: UInt64) -> Int {
        var rng = SplitMix64(seed: seed ^ 0x7195)
        return rng.nextInt(in: 0...(all.count - 1))
    }
}

struct TipCard: View {
    let tip: FlowTip

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tip.symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.cyan)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("TIPS")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold)
                Text(tip.text)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glass(cornerRadius: 12)
        .accessibilityElement(children: .combine)
    }
}
