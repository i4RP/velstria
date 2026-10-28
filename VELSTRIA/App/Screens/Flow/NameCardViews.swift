import SwiftUI
import VelstriaCore

// 担当: outgame（第3段）。他の人の名刺（MLBB 2.2.16 の横長のカード）。公開の名刺（PublicProfile。relay の Directory）から作る。
// 上辺にハイライトの帯といいねの数、左に名前・状態（最終ログイン）・段位章・得意ヒーロー 3 体、左下に ID カード
// （「今シーズン - ランク戦」「全シーズン - 全ての試合」の輪。点で切り替え）、右に立ち絵、右端にフレンド追加。
// チャット・ギフトは Velstria に無いので出さない。自分の名刺はプロフィール（ProfileViews）。

/// ランクの位置の表示（ティア名・段位・星。ミシックは段階名と星の累計）。
enum PublicRankText {
    static func tier(_ r: PublicRank) -> RankTier { RankTier(rawValue: r.tier) ?? .warrior }

    static func name(_ r: PublicRank) -> String {
        let t = tier(r)
        if t == .mythic { return RankService.mythicName(stars: r.stars) }
        return "\(RankService.tierName(t)) \(RankService.roman(max(1, r.division)))"
    }

    /// 星の表示（ミシックは累計、それ以外は段位の中の星）。
    static func stars(_ r: PublicRank) -> String { "★\(r.stars)" }
}

/// 「最終ログイン 5 時間前」の文（MLBB のフレンド一覧・名刺）。5 分以内はオンライン。
enum LastSeenText {
    static func text(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let s = max(0, now.timeIntervalSince(date))
        if s < 300 { return L("オンライン", "Online") }
        if s < 3600 { return L("最終ログイン \(Int(s / 60)) 分前", "Last online \(Int(s / 60))m ago") }
        if s < 86_400 { return L("最終ログイン \(Int(s / 3600)) 時間前", "Last online \(Int(s / 3600))h ago") }
        return L("最終ログイン \(Int(s / 86_400)) 日前", "Last online \(Int(s / 86_400))d ago")
    }
}

struct PublicNameCardView: View {
    let profile: PublicProfile
    @Environment(AppModel.self) private var app
    @Environment(\.worldPanelDismiss) private var dismiss
    @State private var page = 0

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width - 24, 720)
            let h = min(geo.size.height - 24, w * 0.52)
            ZStack {
                Color.black.opacity(0.001)
                if geo.size.width < 600 {
                    ScrollView {
                        VStack(spacing: 12) {
                            left
                            HStack {
                                roundButton("person.badge.plus", L("フレンド追加", "Add friend"), id: "namecard_add_friend", enabled: canRequest) {
                                    FlowFX.confirm(app)
                                    _ = app.friends.requestFriend(code: profile.code)
                                }
                                Spacer()
                                roundButton("xmark", L("閉じる", "Close"), id: "namecard_close", enabled: true) { dismiss() }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .worldShellCard(selected: true)
                    }
                } else {
                    card
                        .frame(width: w, height: h)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
        }
        .background(Color.clear)
        .presentationBackground(.clear)
        .accessibilityIdentifier("namecard")
    }

    private var card: some View {
        ZStack {
            HomeChamfer(cut: 16)
                .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.34, blue: 0.63), Celestial.inkRaised], startPoint: .topLeading, endPoint: .bottomTrailing))
            HStack(spacing: 0) {
                left
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                art
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                buttons
                    .padding(.trailing, 10)
            }
            HomeChamfer(cut: 16)
                .stroke(LinearGradient(colors: [HomeStyle.goldLight, Theme.gold.opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            highlightBand
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .clipShape(HomeChamfer(cut: 16))
    }

    /// 上辺: ハイライトの帯といいねの数（いいねは Velstria では数えていないので 0）。
    private var highlightBand: some View {
        HStack(spacing: 6) {
            Spacer()
            Image(systemName: "hand.thumbsup.fill").font(.system(size: 11))
            Text("0").font(Theme.mono(11))
        }
        .foregroundStyle(HomeStyle.goldLight)
        .padding(.horizontal, 14)
        .frame(height: 20)
        .background(LinearGradient(colors: [.clear, Theme.gold.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing))
    }

    /// 左: 名前・ID・国・状態・段位章・得意ヒーロー 3 体・ID カード。
    private var left: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer().frame(height: 12)
            HStack(spacing: 8) {
                HeroPortraitView(heroID: profile.avatar ?? HeroRoster.defaultHeroID, size: 44, showsRole: false)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .topLeading) { CountryFlagBadge(code: profile.country, size: 14).offset(x: -4, y: -4) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(PlayerNameRules.shown(profile.name))
                        .font(Celestial.title(17))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("ID: \(FriendCode.display(profile.code))  ·  Lv \(profile.level)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textSecondary)
                    if let seen = LastSeenText.text(profile.lastSeen) {
                        Text(seen).font(Theme.body(10)).foregroundStyle(seen == L("オンライン", "Online") ? Theme.success : Theme.textSecondary)
                    }
                }
            }
            HStack(spacing: 8) {
                RankCrest(tier: PublicRankText.tier(profile.rank), size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(PublicRankText.name(profile.rank)).font(Celestial.heading(12)).foregroundStyle(Theme.textPrimary)
                    Text(PublicRankText.stars(profile.rank)).font(Theme.mono(10)).foregroundStyle(HomeStyle.goldLight)
                }
                Spacer(minLength: 4)
                // 得意ヒーロー 3 体
                ForEach(profile.heroes, id: \.heroID) { h in
                    HeroPortraitView(heroID: h.heroID, size: 30, showsRole: false, face: true)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.gold.opacity(0.6), lineWidth: 1))
                }
            }
            Spacer(minLength: 0)
            idCard
        }
    }

    /// ID カード: 今シーズンのランク戦 / 全シーズンの全ての試合（点で切り替え）。MVP の数は公開していないので勝率と試合数。
    private var idCard: some View {
        let seasonGames = profile.seasonWins + profile.seasonLosses
        let pages: [(title: String, wins: Int, games: Int)] = [
            (L("今シーズン - ランク戦", "This Season - Ranked"), profile.seasonWins, seasonGames),
            (L("全シーズン - 全ての試合", "All Seasons - All Matches"), profile.wins, profile.matches),
        ]
        let p = pages[min(page, pages.count - 1)]
        return VStack(alignment: .leading, spacing: 4) {
            Text(p.title).font(Celestial.heading(11)).foregroundStyle(Theme.textPrimary)
            HStack(spacing: 14) {
                ring(value: p.games > 0 ? Double(p.wins) / Double(p.games) : 0,
                     text: p.games > 0 ? String(format: "%.1f%%", Double(p.wins) / Double(p.games) * 100) : "—",
                     title: L("勝率", "Win rate"), tint: HomeStyle.goldLight)
                ring(value: min(1, Double(p.games) / 100), text: "\(p.games)", title: L("試合数", "Matches"), tint: Color(red: 0.85, green: 0.45, blue: 0.95))
            }
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { i in
                    Button { withAnimation { page = i } } label: {
                        Circle().fill(i == page ? Theme.textPrimary : Theme.textSecondary.opacity(0.4)).frame(width: 7, height: 7)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pages[i].title)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
    }

    private func ring(value: Double, text: String, title: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 4)
                Circle().trim(from: 0, to: CGFloat(min(1, max(0, value))))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(text).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .padding(4)
            }
            .frame(width: 50, height: 50)
            Text(title).font(Theme.body(9)).foregroundStyle(Theme.textSecondary)
        }
    }

    /// 右: 立ち絵（アイコンのヒーローのカード絵）。
    @ViewBuilder private var art: some View {
        let hero = profile.avatar ?? HeroRoster.defaultHeroID
        if let image = PortraitArt.card(hero) ?? PortraitArt.hero(hero) {
            Image(uiImage: image).resizable().scaledToFill()
                .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .leading, endPoint: .trailing))
        } else {
            Color.clear
        }
    }

    /// 右端: フレンド追加・閉じる（チャット・ギフトは出さない）。
    private var buttons: some View {
        VStack(spacing: 12) {
            Spacer()
            roundButton("person.badge.plus", L("フレンド追加", "Add friend"), id: "namecard_add_friend",
                        enabled: canRequest) {
                FlowFX.confirm(app)
                _ = app.friends.requestFriend(code: profile.code)
            }
            roundButton("xmark", L("閉じる", "Close"), id: "namecard_close", enabled: true) {
                FlowFX.back(app)
                dismiss()
            }
            Spacer()
        }
    }

    /// フレンド追加できるか（自分・フレンド・申請済み・ブロック中は出さない）。
    private var canRequest: Bool {
        profile.code != app.profile.friendCode && app.friends.friend(code: profile.code) == nil
            && !app.friends.hasOutgoingRequest(to: profile.code) && !app.friends.isBlocked(profile.code)
    }

    private func roundButton(_ symbol: String, _ label: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color(red: 0.15, green: 0.30, blue: 0.55).opacity(0.85)))
                .overlay(Circle().stroke(Celestial.ice.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}
