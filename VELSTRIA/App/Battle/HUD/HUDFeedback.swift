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

/// 倒れている間の画面の彩度を落とす幕（操作部品の下。味方を追っている間は薄くして戦いを見やすく）。
struct HUDDeathBackdrop: View {
    let followingAlly: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(Color(white: 0.45)).blendMode(.saturation).opacity(followingAlly ? 0.35 : 0.8)
            Rectangle().fill(Color.black.opacity(followingAlly ? 0.06 : 0.22))
            RadialGradient(colors: [.clear, Color.black.opacity(0.45)], center: .center, startRadius: 160, endRadius: 560)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.3), value: followingAlly)
    }
}

/// 倒れている間の表示（コンパクト。操作部品より上に重ねる）:
/// - 上部中央: 「倒されました」・倒した相手・復活までの秒・ショップ
/// - ヒーローパネルの上: 味方の一覧（タップでその味方を追う。もう一度タップで自分へ）と「自動」（戦っている味方を自動で追う）
/// 敵は追えない（霧の向こうが見えてしまう。HUDModel.follow の方針）。復活すると自分の追従へ戻る。
struct HUDDeathOverlay: View {
    let model: HUDModel
    let layout: HUDLayout
    @AppStorage(HUDDeathSpectate.autoFollowKey) private var autoFollow = false
    /// 倒れた時の復活までの秒（自動の追従は倒された場面を少し見せてから始める）。
    @State private var deathStartRespawn: Double?
    /// この死亡中に味方を手で選んだ（自動の追従で上書きしない）。
    @State private var manualPick = false

    var body: some View {
        let hero = model.hero
        let allies = HUDDeathSpectate.allies(model)
        // 降参投票のカード（左下）が出ている間は、味方の一覧をその横へずらす（カードの下に味方が隠れないように）
        let vote = model.surrender != nil ? HUDSurrenderMetrics.frame(layout) : nil
        ZStack {
            card(hero)
                .frame(height: HUDDeathMetrics.cardHeight)
                .position(HUDDeathMetrics.cardCenter(layout))
            if !allies.isEmpty {
                strip(allies)
                    .position(HUDDeathMetrics.stripCenter(layout, allies: allies.count, avoiding: vote))
                    .animation(.easeInOut(duration: 0.3), value: vote == nil)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .onAppear {
            deathStartRespawn = hero.respawn
            manualPick = false
        }
        .onChange(of: Int(hero.respawn.rounded(.up))) { tickAuto(force: false) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud_death")
    }

    // MARK: 上部の表示

    private func card(_ hero: HUDHeroSnapshot) -> some View {
        let seconds = Int(hero.respawn.rounded(.up))
        return HStack(spacing: 8) {
            if let info = model.deathInfo { killerBadge(info) }
            VStack(alignment: .leading, spacing: 0) {
                Text(L("倒されました", "You Were Slain"))
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Text(L("復活まで", "Respawn in"))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Text("\(seconds)")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(LinearGradient(colors: [.white, Theme.cyan], startPoint: .top, endPoint: .bottom))
                .shadow(color: Theme.cyan.opacity(0.6), radius: 8)
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(duration: 0.3), value: seconds)
                .frame(minWidth: 34)
                .accessibilityHidden(true)
            Button { model.openShop() } label: {
                Image(systemName: "bag.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.gold))
                    .contentShape(Circle())
            }
            .buttonStyle(HUDPressStyle())
            .accessibilityLabel(L("ショップで準備", "Shop While Waiting"))
            .accessibilityIdentifier("death_shop")
        }
        .padding(.leading, 12)
        .padding(.trailing, 3)
        .padding(.vertical, 3)
        .hudGlass(cornerRadius: 25, tint: Theme.cyan.opacity(0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("倒されました。復活まで \(seconds) 秒", "You were slain. Respawn in \(seconds) seconds"))
    }

    private func killerBadge(_ info: HUDDeathInfo) -> some View {
        Group {
            if let k = info.killerHeroID {
                HeroPortraitView(heroID: k, size: 30, showsRole: false)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(info.killerTeam.map { Theme.teamColor($0, colorblind: model.settings.colorblindMode) } ?? .gray,
                                      lineWidth: 1.5))
                    .accessibilityLabel(L("倒した相手: \(MasterData.shared.hero(k).map { MasterText.hero($0) } ?? k)",
                                          "Slain by \(MasterData.shared.hero(k).map { MasterText.hero($0) } ?? k)"))
            } else if let kind = info.killerKind {
                Image(systemName: kind == .tower || kind == .core ? "building.columns.fill" : "person.3.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.45)))
                    .accessibilityLabel(L("倒した相手: \(HUDText.unitKind(kind))", "Slain by \(HUDText.unitKind(kind))"))
            }
        }
    }

    // MARK: 味方の一覧

    private func strip(_ allies: [HUDDeathAlly]) -> some View {
        HStack(spacing: HUDDeathMetrics.spacing) {
            ForEach(Array(allies.enumerated()), id: \.element.id) { k, ally in
                allyButton(ally, index: k)
            }
            autoButton
        }
        .padding(HUDDeathMetrics.padding)
        .hudGlass(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("味方を見る", "Watch an ally"))
    }

    private func allyButton(_ ally: HUDDeathAlly, index: Int) -> some View {
        let focused = model.cameraFollowID == ally.id
        let team = model.humanTeam ?? .blue
        let color = Theme.teamColor(team, colorblind: model.settings.colorblindMode)
        return Button { tap(ally.id) } label: {
            VStack(spacing: 2) {
                ZStack {
                    HeroPortraitView(heroID: ally.heroID, size: 34, showsRole: false)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .saturation(ally.isDead ? 0 : 1)
                    if ally.isDead {
                        Text("\(ally.respawn)")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 2)
                    }
                    if ally.isFighting {
                        // 戦闘中（色だけでなく交差した剣の形でも示す）
                        HUDCrossedSwords()
                            .fill(Theme.danger)
                            .frame(width: 11, height: 11)
                            .padding(2)
                            .background(Circle().fill(Color.black.opacity(0.75)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .offset(x: 3, y: -3)
                    }
                }
                .frame(width: 34, height: 34)
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(focused ? Color.white : color, lineWidth: focused ? 2.5 : 1.2))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.6))
                        Capsule().fill(ally.hpRatio < 0.3 ? HUDStyle.hpLow : HUDStyle.hp)
                            .frame(width: g.size.width * CGFloat(ally.isDead ? 0 : ally.hpRatio))
                    }
                }
                .frame(width: 34, height: 4)
            }
            .frame(width: HUDDeathMetrics.cell, height: HUDDeathMetrics.cell)
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(MasterData.shared.hero(ally.heroID).map { MasterText.hero($0) } ?? ally.heroID)
        .accessibilityValue(allyValue(ally))
        .accessibilityHint(focused ? L("タップで自分の位置へ戻る", "Tap to return to your position")
                                   : L("タップでこの味方を見る", "Tap to watch this ally"))
        .accessibilityAddTraits(focused ? .isSelected : [])
        .accessibilityIdentifier("death_ally_\(index)")
    }

    private func allyValue(_ ally: HUDDeathAlly) -> String {
        if ally.isDead { return L("倒れている、復活まで \(ally.respawn) 秒", "Down, respawn in \(ally.respawn) seconds") }
        let hp = Int((ally.hpRatio * 100).rounded())
        return ally.isFighting ? L("HP \(hp)%、戦闘中", "HP \(hp)%, fighting") : L("HP \(hp)%", "HP \(hp)%")
    }

    private var autoButton: some View {
        Button {
            autoFollow.toggle()
            manualPick = false
            model.selectionFeedback()
            if autoFollow { tickAuto(force: true) }
        } label: {
            VStack(spacing: 1) {
                Image(systemName: autoFollow ? "eye.fill" : "eye")
                    .font(.system(size: 15, weight: .bold))
                Text(L("自動", "AUTO"))
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(autoFollow ? Color.black : .white)
            .frame(width: HUDDeathMetrics.cell, height: HUDDeathMetrics.cell)
            .background(RoundedRectangle(cornerRadius: 9).fill(autoFollow ? Theme.gold : Color.white.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(L("戦っている味方を自動で見る", "Auto-watch fighting allies"))
        .accessibilityValue(autoFollow ? L("オン", "On") : L("オフ", "Off"))
        .accessibilityAddTraits(autoFollow ? .isSelected : [])
        .accessibilityIdentifier("death_auto")
    }

    // MARK: 操作

    /// 味方をタップ: その味方を追う（追っている味方をもう一度タップすると自分へ戻る）。この死亡中は自動で上書きしない。
    private func tap(_ id: EntityID) {
        manualPick = true
        if model.cameraFollowID == id, let me = model.controller.humanHeroID {
            model.follow(me)
        } else {
            model.follow(id)
        }
    }

    /// 自動の追従（復活までの秒が変わるたび = sim の 1 秒ごと。一時停止中は進まない）。
    private func tickAuto(force: Bool) {
        guard autoFollow, !manualPick, !model.isSpectating else { return }
        if !force, let start = deathStartRespawn, start - model.hero.respawn < HUDDeathSpectate.autoDelay { return }
        let c = model.controller
        guard let me = c.humanHeroID else { return }
        let current = model.cameraFollowID
        if let pick = HUDDeathSpectate.autoTarget(state: c.state, me: me, current: current) {
            if pick != current { model.follow(pick) }
        } else if current != nil {
            model.follow(me)
        }
    }
}

/// 死亡中の味方一覧の 1 人分。
struct HUDDeathAlly: Identifiable, Equatable {
    var id: EntityID
    var heroID: String
    var hpRatio: Double
    var isDead: Bool
    var respawn: Int
    var isFighting: Bool
}

/// 死亡中の表示の配置（HUD 座標）。
enum HUDDeathMetrics {
    /// 味方の一覧の 1 枠（タッチ領域 44pt）。
    static let cell: CGFloat = 44
    static let spacing: CGFloat = 4
    static let padding: CGFloat = 5
    static let cardHeight: CGFloat = 50

    /// 上部中央の表示: 上部のスコアの下。
    static func cardCenter(_ l: HUDLayout) -> CGPoint {
        CGPoint(x: l.width / 2, y: l.topEdge + 50 + cardHeight / 2)
    }

    /// 味方の一覧の大きさ（味方 n 人 + 自動）。
    static func stripSize(allies n: Int) -> CGSize {
        let cells = CGFloat(n + 1)
        return CGSize(width: cells * cell + (cells - 1) * spacing + padding * 2, height: cell + padding * 2)
    }

    /// 味方の一覧: ヒーローパネルのすぐ上（スティックとスキル群の間）。
    static func stripCenter(_ l: HUDLayout) -> CGPoint {
        let h = cell + padding * 2
        return CGPoint(x: l.heroPanelCenterX, y: l.bottomEdge - HUDRootMetrics.heroPanelHeight(l) - 6 - h / 2)
    }

    static func stripFrame(_ l: HUDLayout, allies n: Int) -> CGRect {
        let size = stripSize(allies: n)
        let c = stripCenter(l)
        return CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
    }

    /// 降参投票のカード（avoiding）と重なる時は、味方の一覧をカードの内側（画面中央側）の隣へずらす。
    /// 狭い画面ではスキル群の側へはみ出すが、倒れている間に使えないサモナースペルにだけ掛かる（単体テストで確認）。
    static func stripCenter(_ l: HUDLayout, allies n: Int, avoiding vote: CGRect?) -> CGPoint {
        let f = stripFrame(l, allies: n, avoiding: vote)
        return CGPoint(x: f.midX, y: f.midY)
    }

    static func stripFrame(_ l: HUDLayout, allies n: Int, avoiding vote: CGRect?) -> CGRect {
        var f = stripFrame(l, allies: n)
        guard let vote, f.intersects(vote.insetBy(dx: -voteGap, dy: 0)) else { return f }
        if l.leftHanded {
            f.origin.x = max(l.leadingEdge, min(f.minX, vote.minX - voteGap - f.width))
        } else {
            f.origin.x = min(l.trailingEdge - f.width, max(f.minX, vote.maxX + voteGap))
        }
        return f
    }

    /// 降参投票のカードとの間隔。
    static let voteGap: CGFloat = 6
}

/// 降参投票のカードの配置（ミニマップの下。左利き配置では右）。
enum HUDSurrenderMetrics {
    /// HUDSurrenderPanel の幅。
    static let width: CGFloat = 210
    /// 高さの見積もり（見出し・票・必要数・賛成/反対ボタン 44pt と余白。投票済みならボタンの分だけ低い）。
    static let maxHeight: CGFloat = 136

    static func center(_ l: HUDLayout) -> CGPoint {
        CGPoint(x: l.leftHanded ? l.minimapFrame.maxX - width / 2 - 5 : l.minimapFrame.minX + width / 2 + 5,
                y: l.minimapDockFrame.maxY + 70)
    }

    static func frame(_ l: HUDLayout) -> CGRect {
        let c = center(l)
        return CGRect(x: c.x - width / 2, y: c.y - maxHeight / 2, width: width, height: maxHeight)
    }
}

/// 死亡中の味方追従の判断（純関数。単体テスト対象）。
enum HUDDeathSpectate {
    /// 自動の追従の設定（端末に保存）。
    static let autoFollowKey = "hud.deathAutoFollow"
    /// 倒れてからこの秒数は自分が倒された場面を見せる（自動の追従はその後）。
    static let autoDelay: Double = 2
    /// 戦闘中とみなす: 最近の交戦・被弾（秒）と、近くの見えている敵ヒーローの距離（sim 単位）。
    static let fightWindow: Double = 3
    static let fightRadius: Double = 1400
    /// 別の戦いへ乗り換える点数差（今の味方の戦いより明らかに大きい）。
    static let switchMargin = 2

    /// 一覧に出す味方（生きている味方を先に。HUDModel.followableAllies の順）。
    @MainActor
    static func allies(_ model: HUDModel) -> [HUDDeathAlly] {
        let s = model.controller.state
        return model.followableAllies.compactMap { id -> HUDDeathAlly? in
            guard let i = s.index(of: id), let h = s.units[i].hero else { return nil }
            let u = s.units[i]
            return HUDDeathAlly(id: id, heroID: h.heroID, hpRatio: (u.hpRatio * 20).rounded() / 20, isDead: h.isDead,
                                respawn: Int(h.respawnTimer.rounded(.up)), isFighting: fightScore(s, index: i) > 0)
        }
    }

    /// 味方 i の戦いの大きさ（0 = 戦っていない。戦っていれば近くの両チームのヒーローの数 + 1）。
    /// 敵は味方のチームから見えているものだけ数える（霧の向こうの敵を手掛かりにしない）。
    static func fightScore(_ s: SimState, index i: Int) -> Int {
        let u = s.units[i]
        guard u.isAlive, u.hero?.isDead == false else { return 0 }
        let recent = s.time - u.lastCombatTime < fightWindow || s.time - u.lastDamagedTime < fightWindow
        guard recent else { return 0 }
        var enemies = 0, allies = 0
        let r2 = fightRadius * fightRadius
        for j in s.heroIndices where j != i {
            let o = s.units[j]
            guard o.isAlive, o.hero?.isDead == false, o.pos.distanceSquared(to: u.pos) <= r2 else { continue }
            if o.team == u.team {
                allies += 1
            } else if s.isVisible(j, to: u.team) {
                enemies += 1
            }
        }
        return enemies > 0 ? enemies + allies + 1 : 0
    }

    /// 自動で追う味方: 戦っている味方（今の味方が戦っていればそのまま。明らかに大きい戦いがあれば乗り換える）、
    /// 戦っている味方がいなければ今の味方、それも倒れていれば自分の倒れた場所に一番近い味方。誰もいなければ nil（自分へ）。
    static func autoTarget(state s: SimState, me: EntityID, current: EntityID?) -> EntityID? {
        guard let mi = s.index(of: me) else { return nil }
        let team = s.units[mi].team
        let origin = s.units[mi].pos
        let alive = s.heroIndices(team: team).filter {
            $0 != mi && s.units[$0].isAlive && s.units[$0].hero?.isDead == false
        }
        guard !alive.isEmpty else { return nil }
        let scored = alive.map { (index: $0, score: fightScore(s, index: $0)) }
        let currentIndex = current.flatMap { id in alive.first { s.units[$0].id == id } }
        let currentScore = currentIndex.map { fightScore(s, index: $0) } ?? 0
        let fighting = scored.filter { $0.score > 0 }
        if let ci = currentIndex, currentScore > 0 {
            if let bigger = fighting.max(by: { $0.score < $1.score || ($0.score == $1.score && $0.index > $1.index) }),
               bigger.score >= currentScore + switchMargin {
                return s.units[bigger.index].id
            }
            return s.units[ci].id
        }
        if !fighting.isEmpty {
            let pick = fighting.min {
                let a = s.units[$0.index].pos.distanceSquared(to: origin), b = s.units[$1.index].pos.distanceSquared(to: origin)
                return a != b ? a < b : $0.index < $1.index
            }
            return pick.map { s.units[$0.index].id }
        }
        if let ci = currentIndex { return s.units[ci].id }
        let nearest = alive.min {
            let a = s.units[$0].pos.distanceSquared(to: origin), b = s.units[$1].pos.distanceSquared(to: origin)
            return a != b ? a < b : $0 < $1
        }
        return nearest.map { s.units[$0].id }
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
                    voteButton(yes: true)
                    voteButton(yes: false)
                }
            }
        }
        .padding(10)
        .frame(width: HUDSurrenderMetrics.width)
        .hudGlass(cornerRadius: 12, tint: Theme.gold.opacity(0.6))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud_surrender")
    }

    private func voteButton(yes: Bool) -> some View {
        let color = yes ? Theme.success : Theme.danger
        return Button { model.voteSurrender(yes) } label: {
            Label(yes ? L("賛成", "Yes") : L("反対", "No"), systemImage: yes ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityIdentifier(yes ? "surrender_yes" : "surrender_no")
    }
}
