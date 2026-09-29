import SwiftUI
import VelstriaCore

// 担当: ui-flow。UI007 ホーム。
// 上: プレイヤーカード・通貨・メール・お知らせ / 左: ライブオプス / 中央: ヒーロー展示 / 右: ランク・対戦開始 / 下: メニュー。

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var now = Date()

    var body: some View {
        ZStack {
            StarfieldBackground()
            HomeNebula()
            VStack(spacing: 8) {
                HomeTopBar(now: now)
                HStack(alignment: .center, spacing: 14) {
                    HomeLiveOpsColumn(now: now)
                        .frame(width: 196)
                    HomeHeroShowcase()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    HomeBattleColumn(now: now)
                        .frame(width: 214)
                }
                .frame(maxHeight: .infinity)
                HomeMenuBar()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            now = Date()
            app.audio.playMusic(.menu)
        }
        .fullScreenCover(isPresented: termsUpdateBinding) {
            TermsUpdateView().environment(app)
        }
    }

    /// 規約が改定されていたら再同意を求める（戦闘・対戦フロー表示中は出さない）。
    private var termsUpdateBinding: Binding<Bool> {
        Binding(
            get: {
                app.profile.onboardingCompleted
                    && app.profile.acceptedTermsVersion < FeatureFlags.currentTermsVersion
                    && app.activeBattle == nil
                    && !app.router.isMatchFlowPresented
            },
            set: { _ in }
        )
    }
}

// MARK: - 背景の星雲

private struct HomeNebula: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.45, green: 0.25, blue: 0.85).opacity(0.22), .clear],
                           center: .init(x: 0.5, y: 0.55), startRadius: 10, endRadius: 360)
            RadialGradient(colors: [Theme.gold.opacity(0.08), .clear],
                           center: .init(x: 0.5, y: 0.9), startRadius: 10, endRadius: 300)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - 上部バー

private struct HomeTopBar: View {
    let now: Date
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            Button {
                FlowFX.tap(app)
                app.router.push(.profile)
            } label: {
                playerCard
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home_profile")

            Spacer(minLength: 8)

            Button {
                FlowFX.tap(app)
                app.router.push(.currencyStore)
            } label: {
                HStack(spacing: 6) {
                    CurrencyBadge(kind: .coin, amount: app.profile.starlightCoin)
                    CurrencyBadge(kind: .gem, amount: app.profile.totalGem)
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.gold)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("通貨ストア、コイン \(app.profile.starlightCoin)、ジェム \(app.profile.totalGem)",
                                  "Currency store, \(app.profile.starlightCoin) coins, \(app.profile.totalGem) gems"))
            .accessibilityIdentifier("home_currency")

            FlowIconButton(symbol: "envelope.fill", label: L("メール", "Mail"),
                           badge: HomeBadges.unreadMail(app.profile, now: now), identifier: "home_mail") {
                FlowFX.tap(app)
                app.router.push(.mail)
            }
            FlowIconButton(symbol: "megaphone.fill", label: L("お知らせ", "Notices"),
                           badge: HomeBadges.unreadNotices(app.profile), identifier: "home_notices") {
                FlowFX.tap(app)
                app.router.push(.notices)
            }
        }
    }

    private var playerCard: some View {
        let p = app.profile
        return HStack(spacing: 10) {
            HeroPortraitView(heroID: p.avatarHeroID, size: 46, showsRole: false)
                .overlay(RoundedRectangle(cornerRadius: 46 * 0.2, style: .continuous).stroke(Theme.gold.opacity(0.8), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(p.displayName.isEmpty ? L("プレイヤー", "Player") : p.displayName)
                    .font(Theme.heading(15))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                AccountLevelBar(level: p.accountLevel, xp: p.accountXP, width: 84)
                RankInlineView(rank: p.rank, emblemSize: 16, font: Theme.body(11))
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .glass(cornerRadius: 30)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("プロフィール、\(p.displayName)、レベル \(p.accountLevel)、\(RankService.displayName(p.rank))",
                              "Profile, \(p.displayName), level \(p.accountLevel), \(RankService.displayName(p.rank))"))
    }
}

// MARK: - 左: ライブオプス

private struct HomeLiveOpsColumn: View {
    let now: Date
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.profile
        let claimable = HomeBadges.claimableMissions(p)
        let daily = LiveOpsService.dailyMissions(profile: p)
        let dailyDone = daily.filter { def in
            p.missions.daily.first { $0.id == def.id }.map { $0.claimed || $0.progress >= def.target } ?? false
        }.count
        let events = LiveOpsService.activeEvents(now: now)
        let passLevel = LiveOpsService.passLevel(xp: p.pass.xp)

        VStack(spacing: 8) {
            banner(symbol: "checklist", title: L("ミッション", "Missions"),
                   subtitle: claimable > 0 ? L("受取可能 \(claimable)", "\(claimable) ready to claim")
                                           : (daily.isEmpty ? L("本日のミッション", "Today's missions") : L("デイリー \(dailyDone)/\(daily.count)", "Daily \(dailyDone)/\(daily.count)")),
                   tint: Theme.success, badge: claimable, id: "home_missions", route: .missions)
            banner(symbol: "calendar.badge.clock", title: L("イベント", "Events"),
                   subtitle: events.isEmpty ? L("開催予定を確認", "See upcoming") : L("開催中 \(events.count)", "\(events.count) live"),
                   tint: Color(red: 1.0, green: 0.55, blue: 0.35), badge: 0, id: "home_events", route: .events)
            banner(symbol: "star.square.on.square.fill", title: L("スターパス", "Star Pass"),
                   subtitle: "Lv \(passLevel) / \(LiveOpsService.passMaxLevel)" + (p.pass.hasPremium ? " ★" : ""),
                   tint: Theme.gold, badge: 0, id: "home_starPass", route: .starPass,
                   progress: Double(p.pass.xp % LiveOpsService.passXPPerLevel) / Double(LiveOpsService.passXPPerLevel))
        }
    }

    private func banner(symbol: String, title: String, subtitle: String, tint: Color, badge: Int, id: String,
                        route: Route, progress: Double? = nil) -> some View {
        Button {
            FlowFX.tap(app)
            app.router.push(route)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(tint.opacity(0.16)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.heading(14))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let progress {
                        FlowProgressBar(value: progress, tint: tint, height: 4)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 58)
            .glass(cornerRadius: 14, tint: tint.opacity(0.7))
            .overlay(alignment: .topTrailing) { FlowCountBadge(count: badge).offset(x: 4, y: -4) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

// MARK: - 中央: ヒーロー展示

private struct HomeHeroShowcase: View {
    @Environment(AppModel.self) private var app

    private var heroID: String {
        if let id = app.profile.lastPickedHeroID, app.master.hero(id) != nil { return id }
        return app.profile.avatarHeroID
    }

    var body: some View {
        GeometryReader { geo in
            let portrait = max(70, min(150, geo.size.height - 78, geo.size.width * 0.5))
            let hero = app.master.hero(heroID)
            Button {
                FlowFX.tap(app)
                app.router.push(.heroDetail(heroID))
            } label: {
                VStack(spacing: 6) {
                    ZStack {
                        StarRingView(tint: Theme.cyan, accent: Theme.gold, speed: 0.05, starCount: 34, showsCore: false)
                            .frame(width: min(geo.size.width, portrait * 2.6), height: portrait * 0.95)
                            .offset(y: portrait * 0.36)
                        Ellipse()
                            .fill(RadialGradient(colors: [Theme.cyan.opacity(0.35), .clear], center: .center, startRadius: 2, endRadius: portrait * 0.7))
                            .frame(width: portrait * 1.6, height: portrait * 0.36)
                            .offset(y: portrait * 0.56)
                        HeroPortraitView(heroID: heroID, size: portrait)
                            .glowPulse(Color(hue: Theme.heroHue(heroID), saturation: 0.7, brightness: 1), radius: 22)
                    }
                    .frame(height: portrait * 1.12)
                    if let hero {
                        Text(MasterText.hero(hero))
                            .font(Theme.title(20))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .shadow(color: .black.opacity(0.6), radius: 4)
                        HStack(spacing: 8) {
                            RoleLabel(role: hero.role, size: 12)
                            if let skinID = app.profile.equippedSkins[heroID], let skin = app.master.cosmetic(skinID) {
                                Label(MasterText.cosmetic(skin), systemImage: "sparkles")
                                    .font(Theme.body(11))
                                    .foregroundStyle(Theme.rarityColor(skin.rarity))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("ヒーロー詳細: ", "Hero details: ") + (hero.map { MasterText.hero($0) } ?? heroID))
            .accessibilityIdentifier("home_showcase")
        }
    }
}

// MARK: - 右: ランクと対戦開始

private struct HomeBattleColumn: View {
    let now: Date
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.profile
        VStack(spacing: 10) {
            Button {
                FlowFX.tap(app)
                app.router.push(.rankOverview)
            } label: {
                HStack(spacing: 10) {
                    RankEmblemView(tier: p.rank.tier, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(RankService.displayName(p.rank))
                            .font(Theme.heading(14))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if p.rank.tier == .starRingSovereign {
                            Text("\(p.rank.points) pt").font(Theme.mono(11)).foregroundStyle(Theme.gold)
                        } else {
                            RankStarsView(stars: p.rank.stars, size: 11)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 56)
                .glass(cornerRadius: 14, tint: FlowText.tierColors(p.rank.tier)[0])
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home_rank")

            Button {
                FlowFX.confirm(app)
                MatchFlowIntent.present(nil, app: app)
            } label: {
                BattleButtonLabel()
            }
            .buttonStyle(BattleButtonStyle())
            .accessibilityLabel(L("対戦開始", "Battle"))
            .accessibilityIdentifier("home_play")

            HStack(spacing: 6) {
                Image(systemName: HomeBadges.firstWinAvailable(p, now: now) ? "sun.max.fill" : "checkmark.circle.fill")
                    .foregroundStyle(HomeBadges.firstWinAvailable(p, now: now) ? Theme.gold : Theme.success)
                Text(HomeBadges.firstWinAvailable(p, now: now)
                     ? L("本日の初勝利ボーナス +300", "First win of the day: +300")
                     : L("初勝利ボーナス獲得済み", "First-win bonus claimed"))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct BattleButtonLabel: View {
    var body: some View {
        ZStack {
            FourPointStar(innerRatio: 0.18)
                .fill(Color.white.opacity(0.22))
                .frame(width: 64, height: 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 14, y: -14)
                .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text(L("対戦開始", "BATTLE"))
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(Loc.isEnglish ? "5v5 vs AI" : "BATTLE · 5v5 対AI")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Color.black.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 86)
    }
}

/// 対戦開始ボタン（金の光沢 + 明滅する発光）。
private struct BattleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.90, blue: 0.55), Theme.gold, Color(red: 0.92, green: 0.55, blue: 0.20)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(LinearGradient(colors: [.white, .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .glowPulse(Theme.gold, radius: 20)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - 下: メニュー

private struct HomeMenuBar: View {
    @Environment(AppModel.self) private var app

    private struct Entry {
        let symbol: String
        let title: String
        let route: Route
        let id: String
    }

    private var entries: [Entry] {
        [
            Entry(symbol: "person.3.fill", title: L("ヒーロー", "Heroes"), route: .heroes, id: "home_heroes"),
            Entry(symbol: "bag.fill", title: L("装備", "Items"), route: .items, id: "home_items"),
            Entry(symbol: "seal.fill", title: L("ルーン", "Runes"), route: .runes, id: "home_runes"),
            Entry(symbol: "cart.fill", title: L("ストア", "Store"), route: .store, id: "home_store"),
            Entry(symbol: "chart.bar.xaxis", title: L("戦績", "Records"), route: .records, id: "home_records"),
            Entry(symbol: "play.rectangle.fill", title: L("リプレイ", "Replays"), route: .replays, id: "home_replays"),
            Entry(symbol: "eye.fill", title: L("観戦", "Spectate"), route: .spectateSetup, id: "home_spectateSetup"),
            Entry(symbol: "figure.run", title: L("練習場", "Practice"), route: .practiceSetup, id: "home_practiceSetup"),
            Entry(symbol: "gearshape.fill", title: L("設定", "Settings"), route: .settings, id: "home_settings"),
        ]
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(entries.indices, id: \.self) { i in
                let e = entries[i]
                Button {
                    FlowFX.tap(app)
                    app.router.push(e.route)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: e.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(i == 3 ? Theme.gold : Theme.cyan)
                            .frame(height: 22)
                        Text(e.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(MenuTileStyle())
                .accessibilityIdentifier(e.id)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .glass(cornerRadius: 18)
    }
}

private struct MenuTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
