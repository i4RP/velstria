import SwiftUI
import VelstriaCore

// 担当: battle-hud。戦闘中のフィードバック表示:
// 告知バナー・キルフィード・トースト・死亡オーバーレイ・詠唱バー・レベルアップ表示・低 HP のビネット・降参投票。

// MARK: - 告知バナー

struct HUDBannerView: View {
    let banner: HUDBanner?
    let colorblind: Bool
    let scale: CGFloat

    var body: some View {
        ZStack {
            if let b = banner {
                card(b)
                    .id(b.id)
                    .transition(.asymmetric(insertion: .scale(scale: 0.55).combined(with: .opacity),
                                            removal: .opacity.combined(with: .scale(scale: 1.08))))
            }
        }
        .animation(.spring(duration: 0.38, bounce: 0.35), value: banner?.id)
        .allowsHitTesting(false)
    }

    private func toneColor(_ t: HUDBanner.Tone) -> Color {
        switch t {
        case .ally: return Theme.teamColor(.blue, colorblind: colorblind)
        case .enemy: return Theme.teamColor(.red, colorblind: colorblind)
        case .neutral: return Color(red: 0.62, green: 0.52, blue: 1.0)
        case .epic: return Theme.gold
        }
    }

    private func card(_ b: HUDBanner) -> some View {
        let color = toneColor(b.tone)
        return HStack(spacing: 12 * scale) {
            if let left = b.leftHeroID {
                portrait(left, color: color)
            } else {
                Image(systemName: b.symbol)
                    .font(.system(size: 24 * scale, weight: .black))
                    .foregroundStyle(LinearGradient(colors: [.white, color], startPoint: .top, endPoint: .bottom))
                    .shadow(color: color, radius: 6)
            }
            VStack(spacing: 1) {
                Text(b.title)
                    .font(.system(size: (b.tone == .epic ? 30 : 25) * scale, weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(LinearGradient(colors: [.white, color.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: color.opacity(0.9), radius: 8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let sub = b.subtitle {
                    Text(sub)
                        .font(.system(size: 12 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            if let right = b.rightHeroID {
                portrait(right, color: .white.opacity(0.6))
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 26 * scale, weight: .black))
                            .foregroundStyle(Theme.danger)
                            .shadow(color: .black, radius: 2)
                    )
                    .saturation(0.3)
            }
        }
        .padding(.horizontal, 40 * scale)
        .padding(.vertical, 8 * scale)
        .background(
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: color.opacity(0.42), location: 0.25),
                                   .init(color: Color.black.opacity(0.6), location: 0.5),
                                   .init(color: color.opacity(0.42), location: 0.75), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        )
        .overlay(alignment: .top) { edge(color) }
        .overlay(alignment: .bottom) { edge(color) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([b.title, b.subtitle].compactMap { $0 }.joined(separator: " "))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func edge(_ color: Color) -> some View {
        LinearGradient(colors: [.clear, color, .clear], startPoint: .leading, endPoint: .trailing)
            .frame(height: 1.5)
    }

    private func portrait(_ heroID: String, color: Color) -> some View {
        HeroPortraitView(heroID: heroID, size: 44 * scale, showsRole: false)
            .clipShape(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous).strokeBorder(color, lineWidth: 2))
    }
}

// MARK: - キルフィード（右側）

struct HUDKillFeed: View {
    let entries: [HUDKillFeedEntry]
    let colorblind: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            ForEach(entries) { e in
                row(e)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: entries.map(\.id))
        .allowsHitTesting(false)
    }

    private func row(_ e: HUDKillFeedEntry) -> some View {
        let killerColor = e.killerTeam.map { Theme.teamColor($0, colorblind: colorblind) } ?? Color.gray
        let victimColor = Theme.teamColor(e.victimTeam, colorblind: colorblind)
        return HStack(spacing: 4) {
            if let k = e.killerHeroID {
                HeroPortraitView(heroID: k, size: 22, showsRole: false)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(killerColor, lineWidth: 1.5))
            } else {
                // 処刑（タワー・ミニオン等によるキル）
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.gray.opacity(0.5)))
            }
            HStack(spacing: 1) {
                HUDCrossedSwords()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 13, height: 13)
                if e.assists > 0 {
                    Text("+\(e.assists)")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            HeroPortraitView(heroID: e.victimHeroID, size: 22, showsRole: false)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(victimColor, lineWidth: 1.5))
                .saturation(0.35)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(LinearGradient(colors: [killerColor.opacity(e.involvesHuman ? 0.55 : 0.32), Color.black.opacity(0.55)],
                                          startPoint: .leading, endPoint: .trailing))
        )
        .overlay(Capsule().strokeBorder(e.involvesHuman ? Theme.gold.opacity(0.9) : Color.white.opacity(0.15), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(e))
    }

    private func accessibilityText(_ e: HUDKillFeedEntry) -> String {
        let victim = MasterData.shared.hero(e.victimHeroID).map { MasterText.hero($0) } ?? e.victimHeroID
        if let k = e.killerHeroID, let def = MasterData.shared.hero(k) {
            return L("\(MasterText.hero(def)) が \(victim) を撃破", "\(MasterText.hero(def)) slew \(victim)")
        }
        return L("\(victim) が処刑された", "\(victim) was executed")
    }
}

// MARK: - トースト

struct HUDToastView: View {
    let toast: HUDToast?

    var body: some View {
        ZStack {
            if let t = toast {
                Label(t.text, systemImage: t.symbol)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(t.isError ? Theme.danger.opacity(0.85) : Color.black.opacity(0.75)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .id(t.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("hud_toast")
            }
        }
        .animation(.spring(duration: 0.25), value: toast?.id)
        .allowsHitTesting(false)
    }
}

// MARK: - 死亡オーバーレイ

struct HUDDeathOverlay: View {
    let model: HUDModel
    let scale: CGFloat

    var body: some View {
        let hero = model.hero
        ZStack {
            // 彩度を落とした暗幕（3D 描画の上に重ねる。操作は下の HUD へ通す）
            ZStack {
                Rectangle().fill(Color(white: 0.45)).blendMode(.saturation).opacity(0.9)
                Rectangle().fill(Color.black.opacity(0.32))
                RadialGradient(colors: [.clear, Color.black.opacity(0.55)], center: .center, startRadius: 120, endRadius: 520)
            }
            .allowsHitTesting(false)
            VStack(spacing: 6 * scale) {
                Text(L("倒されました", "You Were Slain"))
                    .font(.system(size: 20 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                if let info = model.deathInfo {
                    killerLine(info)
                }
                Text("\(Int(hero.respawn.rounded(.up)))")
                    .font(.system(size: 64 * scale, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: [.white, Theme.cyan], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Theme.cyan.opacity(0.7), radius: 12)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.spring(duration: 0.3), value: Int(hero.respawn.rounded(.up)))
                Text(L("秒後に復活", "seconds to respawn"))
                    .font(.system(size: 12 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                Button { model.openShop() } label: {
                    Label(L("ショップで準備", "Shop While Waiting"), systemImage: "bag.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
                .accessibilityIdentifier("death_shop")
            }
            .padding(.bottom, 60 * scale)
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud_death")
    }

    private func killerLine(_ info: HUDDeathInfo) -> some View {
        HStack(spacing: 6) {
            if let k = info.killerHeroID {
                HeroPortraitView(heroID: k, size: 26, showsRole: false)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(MasterData.shared.hero(k).map { MasterText.hero($0) } ?? k)
            } else if let kind = info.killerKind {
                Image(systemName: kind == .tower || kind == .core ? "building.columns.fill" : "person.3.fill")
                Text(HUDText.unitKind(kind))
            }
        }
        .font(.system(size: 13 * scale, weight: .bold, design: .rounded))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.45)))
    }
}

// MARK: - 詠唱バー（帰還・転移）

struct HUDChannelBar: View {
    let channel: HUDChannel?
    let width: CGFloat

    var body: some View {
        ZStack {
            if let ch = channel, ch.total > 0 {
                VStack(spacing: 3) {
                    HStack {
                        Image(systemName: ch.kind == .recall ? "house.fill" : "door.left.hand.open")
                        Text(HUDText.channelName(ch.kind))
                        Spacer()
                        Text(String(format: "%.1f", max(0, ch.remaining)))
                            .monospacedDigit()
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.6))
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.cyan, Color(red: 0.4, green: 0.5, blue: 1)],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: g.size.width * CGFloat(1 - ch.remaining / ch.total))
                                .animation(.linear(duration: 1.0 / 15.0), value: ch.remaining)
                        }
                    }
                    .frame(height: 7)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: width)
                .hudGlass(cornerRadius: 10, tint: Theme.cyan.opacity(0.6))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(HUDText.channelName(ch.kind))
                .accessibilityIdentifier("hud_channel")
            }
        }
        .animation(.easeOut(duration: 0.2), value: channel == nil)
        .allowsHitTesting(false)
    }
}

// MARK: - レベルアップ表示

struct HUDLevelUpText: View {
    let pulse: Int
    let level: Int
    @State private var visible = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if visible {
                VStack(spacing: -2) {
                    Text(L("レベルアップ", "LEVEL UP"))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .italic()
                    Text("\(level)")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                }
                .foregroundStyle(LinearGradient(colors: [.white, Theme.gold], startPoint: .top, endPoint: .bottom))
                .shadow(color: Theme.gold.opacity(0.9), radius: 10)
                .transition(.asymmetric(insertion: .scale(scale: 0.5).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
            }
        }
        .onChange(of: pulse) {
            withAnimation(.spring(duration: 0.35, bounce: 0.4)) { visible = true }
            hideTask?.cancel()
            hideTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.3))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.4)) { visible = false }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 低 HP のビネット

struct HUDLowHealthVignette: View {
    let active: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if active {
                RadialGradient(colors: [.clear, .clear, Theme.danger.opacity(0.55)], center: .center,
                               startRadius: 60, endRadius: 520)
                    .opacity(pulse ? 1 : 0.55)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
                    }
                    .onDisappear { pulse = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: active)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 降参投票（UI031）

struct HUDSurrenderPanel: View {
    let model: HUDModel
    let snapshot: HUDSurrenderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "flag.fill").foregroundStyle(Theme.gold)
                Text(L("降参投票", "Surrender Vote"))
                Spacer(minLength: 8)
                if let passed = snapshot.passed {
                    Text(passed ? L("成立", "Passed") : L("否決", "Failed"))
                        .foregroundStyle(passed ? Theme.success : Theme.danger)
                } else {
                    Text("\(snapshot.secondsLeft)s").monospacedDigit().foregroundStyle(.white.opacity(0.8))
                }
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            HStack(spacing: 4) {
                ForEach(0..<max(1, snapshot.total), id: \.self) { k in
                    let state: Bool? = k < snapshot.yes ? true : (k < snapshot.yes + snapshot.no ? false : nil)
                    ZStack {
                        Circle().fill(state == true ? Theme.success : (state == false ? Theme.danger : Color.white.opacity(0.15)))
                        Image(systemName: state == true ? "checkmark" : (state == false ? "xmark" : "ellipsis"))
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 20, height: 20)
                }
            }
            Text(L("\(snapshot.needed) 票の賛成で成立", "\(snapshot.needed) yes votes needed"))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            if snapshot.passed == nil && snapshot.myVote == nil {
                HStack(spacing: 8) {
                    Button { model.voteSurrender(true) } label: {
                        Label(L("賛成", "Yes"), systemImage: "hand.thumbsup.fill")
                            .frame(minWidth: 70, minHeight: 36)
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.success))
                    .accessibilityIdentifier("surrender_yes")
                    Button { model.voteSurrender(false) } label: {
                        Label(L("反対", "No"), systemImage: "hand.thumbsdown.fill")
                            .frame(minWidth: 70, minHeight: 36)
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.danger))
                    .accessibilityIdentifier("surrender_no")
                }
            }
        }
        .padding(10)
        .frame(width: 210)
        .hudGlass(cornerRadius: 12, tint: Theme.gold.opacity(0.6))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud_surrender")
    }
}
