import SwiftUI
import VelstriaCore

// 担当: battle-hud。観戦・リプレイの操作（controller.isSpectating）。配置は HUDSpectatorLayout（端末幅・Safe Area・左利き）。
// 下部ドック:
// - 上段（オフラインの観戦・リプレイ = シークできる時）: 再生バー（HUDReplayTransport）
// - 下段: 両チーム 5 人ずつのヒーロー（タップで追従、追従中をもう一度タップで詳細。左右のスワイプで前後のヒーロー）、
//   中央に前後の切り替え・観戦メニュー（オンラインの観戦席は LIVE と遅延の表示。一時停止・速度・シークは効かないので出さない）
// 観戦メニュー（引き出し）: 視界（全体 / ブルー / レッド）・自動カメラ・シネマ表示・情報パネル・目標タイマー・狭い画面で畳んだ操作。
// 上部: 両チームのゴールドとゴールド差・目標タイマー。シネマ表示では HUD を隠し、戻すボタンだけを残す。

/// 下部ドック（観戦の操作）。
struct HUDSpectateDock: View {
    let model: HUDModel
    let layout: HUDSpectatorLayout

    var body: some View {
        VStack(spacing: HUDSpectatorLayout.rowSpacing) {
            if layout.showsTransportRow {
                HUDReplayTransport(model: model, layout: layout)
                    .frame(width: layout.innerWidth, height: layout.transportRowHeight)
            }
            if layout.showsHeroRow {
                HUDSpectateHeroRow(model: model, layout: layout)
                    .frame(width: layout.innerWidth, height: layout.heroRowHeight)
            }
        }
        .padding(HUDSpectatorLayout.padding)
        .frame(width: layout.dockFrame.width, height: layout.dockFrame.height)
        .hudGlass(cornerRadius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spectate_dock")
    }
}

/// 下段: ブルー 5 人 | 中央の操作 | レッド 5 人。
struct HUDSpectateHeroRow: View {
    let model: HUDModel
    let layout: HUDSpectatorLayout

    var body: some View {
        let snap = model.spectate
        let cb = model.settings.colorblindMode
        HStack(spacing: HUDSpectatorLayout.groupGap) {
            team(snap.heroes.filter { $0.team == .blue }, colorblind: cb)
            HUDSpectateCenterControls(model: model, layout: layout)
                .frame(maxWidth: .infinity)
            team(snap.heroes.filter { $0.team == .red }, colorblind: cb)
        }
        // 左右のスワイプで前後のヒーローへ（ボタンのタップとは別に受ける）
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    guard abs(v.translation.width) > 40, abs(v.translation.width) > abs(v.translation.height) else { return }
                    model.followAdjacentHero(v.translation.width < 0 ? 1 : -1)
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: L("次のヒーロー", "Next hero")) { model.followAdjacentHero(1) }
        .accessibilityAction(named: L("前のヒーロー", "Previous hero")) { model.followAdjacentHero(-1) }
    }

    private func team(_ heroes: [HUDSpectateHero], colorblind: Bool) -> some View {
        HStack(spacing: HUDSpectatorLayout.heroSpacing) {
            ForEach(heroes) { h in
                HUDSpectateHeroButton(model: model, hero: h, colorblind: colorblind)
            }
        }
        .frame(width: layout.teamGroupWidth, alignment: .center)
    }
}

/// 1 人分のボタン（ポートレート・レベル・HP・復活までの秒・必殺技の準備・持ち主）。44 × 48pt。
struct HUDSpectateHeroButton: View {
    let model: HUDModel
    let hero: HUDSpectateHero
    let colorblind: Bool

    var body: some View {
        let h = hero
        let focused = model.spectator.focusID == h.id
        let color = Theme.teamColor(h.team, colorblind: colorblind)
        Button { model.spectatorSelectHero(h.id) } label: {
            VStack(spacing: 3) {
                ZStack {
                    HeroPortraitView(heroID: h.heroID, size: 38, showsRole: false)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .saturation(h.isDead ? 0 : 1)
                        .opacity(h.isDead ? 0.75 : 1)
                    if h.isDead {
                        Text("\(Int(h.respawn))")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 2)
                    }
                    Text("\(h.level)")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(Color.black.opacity(0.8)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    // チームの形（色に頼らない: ブルー = 丸、レッド = ひし形）
                    Image(systemName: h.team == .blue ? "circle.fill" : "diamond.fill")
                        .font(.system(size: 6, weight: .black))
                        .foregroundStyle(color)
                        .padding(2)
                        .background(Circle().fill(Color.black.opacity(0.7)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    if h.ultReady {
                        Circle()
                            .fill(HUDStyle.violet)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                            .frame(width: 8, height: 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(1)
                            .accessibilityHidden(true)
                    }
                    if h.isOwner {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(Theme.gold)
                            .shadow(color: .black, radius: 1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(2)
                    }
                }
                .frame(width: 38, height: 38)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? Color.white : (h.isOwner ? Theme.gold : color),
                                  lineWidth: focused ? 2.5 : (h.isOwner ? 2 : 1.2)))
                .shadow(color: focused ? Color.white.opacity(0.6) : .clear, radius: 4)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.6))
                        Capsule().fill(h.hpRatio < 0.3 ? HUDStyle.hpLow : HUDStyle.hp)
                            .frame(width: g.size.width * CGFloat(h.isDead ? 0 : h.hpRatio))
                    }
                }
                .frame(width: 38, height: 4)
            }
            .frame(width: HUDSpectatorLayout.heroSize.width, height: HUDSpectatorLayout.heroSize.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(focused ? L("もう一度タップで詳細", "Tap again for details") : L("タップで追従", "Tap to follow"))
        .accessibilityAddTraits(focused ? .isSelected : [])
        .accessibilityIdentifier("spectate_hero_\(h.id)")
    }

    private var accessibilityName: String {
        let name = MasterData.shared.hero(hero.heroID).map { MasterText.hero($0) } ?? hero.heroID
        let team = HUDText.teamName(hero.team)
        return hero.isOwner ? L("\(team) \(name)（記録した本人）", "\(team) \(name) (recorded by you)") : "\(team) \(name)"
    }

    private var accessibilityValue: String {
        var parts = [L("レベル \(hero.level)", "Level \(hero.level)")]
        if hero.isDead {
            parts.append(L("復活まで \(Int(hero.respawn)) 秒", "Respawns in \(Int(hero.respawn)) s"))
        } else {
            parts.append("HP \(Int((hero.hpRatio * 100).rounded()))%")
        }
        if hero.ultReady { parts.append(L("必殺技 使用可能", "Ultimate ready")) }
        return parts.joined(separator: L("、", ", "))
    }
}

/// 下段の中央: 前後のヒーロー・観戦メニュー（自由カメラ中は「追従に戻る」）。オンラインの観戦席は LIVE 表示。
struct HUDSpectateCenterControls: View {
    let model: HUDModel
    let layout: HUDSpectatorLayout

    var body: some View {
        let t = model.spectator.transport
        let free = model.spectator.isFreeCamera
        HStack(spacing: HUDSpectatorLayout.gap) {
            if t.isLiveWatcher {
                HUDLiveBadge(delay: t.delaySeconds, watchers: t.watchers)
                    .frame(maxWidth: .infinity)
            } else if free {
                Button { model.refollowLastHero() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "scope").font(.system(size: 13, weight: .bold))
                        Text(L("追従に戻る", "Re-follow"))
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(Theme.cyan))
                    .contentShape(Capsule())
                }
                .buttonStyle(HUDPressStyle())
                .accessibilityLabel(L("自由カメラ中。ヒーローの追従に戻る", "Free camera. Return to following the hero"))
                .accessibilityIdentifier("spectate_refollow")
            } else if layout.showsPrevNext {
                HUDSpectateIconButton(symbol: "chevron.left", label: L("前のヒーロー", "Previous hero"),
                                      identifier: "spectate_prev_hero") { model.followAdjacentHero(-1) }
            }
            HUDSpectateIconButton(symbol: model.spectator.isDrawerOpen ? "xmark" : "slider.horizontal.3",
                                  label: L("観戦メニュー", "Spectator menu"), identifier: "spectate_menu",
                                  selected: model.spectator.isDrawerOpen) {
                model.toggleSpectatorDrawer()
            }
            if !t.isLiveWatcher && !free && layout.showsPrevNext {
                HUDSpectateIconButton(symbol: "chevron.right", label: L("次のヒーロー", "Next hero"),
                                      identifier: "spectate_next_hero") { model.followAdjacentHero(1) }
            }
        }
    }
}

/// オンラインの観戦席: LIVE と配信の遅延・観戦者数。
struct HUDLiveBadge: View {
    let delay: Double?
    let watchers: Int

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(Theme.danger).frame(width: 7, height: 7)
                Text("LIVE")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(1)
            }
            HStack(spacing: 6) {
                if let delay, delay > 0 {
                    Text(L("\(Int(delay.rounded())) 秒遅れ", "\(Int(delay.rounded()))s delay"))
                }
                if watchers > 0 {
                    Label("\(watchers)", systemImage: "eye.fill").labelStyle(.titleAndIcon)
                }
            }
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(HUDStyle.mutedText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(minWidth: 60, minHeight: 44)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().strokeBorder(Theme.danger.opacity(0.7), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("spectate_live")
    }

    private var accessibilityText: String {
        var s = L("ライブ観戦", "Watching live")
        if let delay, delay > 0 { s += L("、\(Int(delay.rounded())) 秒遅れ", ", \(Int(delay.rounded())) second delay") }
        if watchers > 0 { s += L("、観戦者 \(watchers) 人", ", \(watchers) watching") }
        return s
    }
}

/// 観戦の丸いボタン（44pt）。
struct HUDSpectateIconButton: View {
    let symbol: String
    let label: String
    let identifier: String
    var selected = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(selected ? Color.black : .white)
                .frame(width: HUDSpectatorLayout.button, height: HUDSpectatorLayout.button)
                .background(Circle().fill(selected ? Theme.gold : Color.white.opacity(0.1)))
                .contentShape(Circle())
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(HUDPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// 観戦中の両チームのゴールドとゴールド差（上部中央の下）。
struct HUDSpectateScore: View {
    let model: HUDModel

    var body: some View {
        let snap = model.spectate
        let cb = model.settings.colorblindMode
        let blue = Theme.teamColor(.blue, colorblind: cb)
        let red = Theme.teamColor(.red, colorblind: cb)
        // タワー数は上のスコアカプセルにあるので、ここはゴールドと差だけ（パネルを開いた狭い隙間にも収める）
        HStack(spacing: 10) {
            side(gold: snap.blueGold, symbol: "circle.fill", color: blue)
            diff(snap.goldDiff, blue: blue, red: red)
            side(gold: snap.redGold, symbol: "diamond.fill", color: red)
        }
        .padding(.horizontal, 12)
        .frame(height: HUDSpectatorLayout.scorePillHeight)
        .hudGlass(cornerRadius: 13)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(snap))
        .accessibilityIdentifier("spectate_score")
    }

    private func accessibilityText(_ snap: HUDSpectateSnapshot) -> String {
        let lead = snap.goldDiff == 0 ? L("互角", "even")
            : L("\(HUDText.teamName(snap.goldDiff > 0 ? .blue : .red)) が \(abs(snap.goldDiff)) 有利",
                "\(HUDText.teamName(snap.goldDiff > 0 ? .blue : .red)) ahead by \(abs(snap.goldDiff))")
        return L("ゴールド ブルー \(snap.blueGold) レッド \(snap.redGold)、\(lead)",
                 "Gold Blue \(snap.blueGold) Red \(snap.redGold), \(lead)")
    }

    /// ゴールド差（有利な側の色と形: ブルー = 丸、レッド = ひし形。互角は灰色）。
    private func diff(_ value: Int, blue: Color, red: Color) -> some View {
        let lead: Team? = value > 0 ? .blue : (value < 0 ? .red : nil)
        let color = lead == .blue ? blue : (lead == .red ? red : Color.white.opacity(0.6))
        return HStack(spacing: 2) {
            if let lead {
                Image(systemName: lead == .blue ? "circle.fill" : "diamond.fill")
                    .font(.system(size: 6, weight: .black))
                Image(systemName: lead == .blue ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill")
                    .font(.system(size: 7, weight: .black))
            }
            Text(value == 0 ? "±0" : "+" + HUDStyle.thousands(Double(abs(value))))
        }
        .font(.system(size: 11, weight: .black, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(color)
        .frame(minWidth: 46)
    }

    private func side(gold: Int, symbol: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 6, weight: .black)).foregroundStyle(color)
            HUDCoin(size: 11)
            Text(String(format: "%.1fk", Double(gold) / 1000)).foregroundStyle(color)
        }
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .monospacedDigit()
    }
}

/// 目標タイマーの帯（星喰竜・古環の巨像の出現まで / 出現中、チームの加護の残り）。
struct HUDObjectiveStrip: View {
    let model: HUDModel
    let maxWidth: CGFloat

    var body: some View {
        let timers = model.spectator.objectives
        let cb = model.settings.colorblindMode
        if !timers.isEmpty {
            HStack(spacing: 4) {
                ForEach(timers) { t in chip(t, colorblind: cb) }
            }
            .frame(maxWidth: maxWidth)
            .fixedSize(horizontal: false, vertical: true)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("spectate_objectives")
        }
    }

    private func chip(_ t: HUDObjectiveTimer, colorblind: Bool) -> some View {
        let symbol: String
        let name: String
        switch t.kind {
        case .wyrm: symbol = "hurricane"; name = L("星喰竜", "Wyrm")
        case .colossus: symbol = "crown.fill"; name = L("巨像", "Colossus")
        case .wyrmBlessing: symbol = "hurricane"; name = L("竜の加護", "Wyrm buff")
        case .colossusBlessing: symbol = "crown.fill"; name = L("巨像の加護", "Colossus buff")
        }
        let tint = t.team.map { Theme.teamColor($0, colorblind: colorblind) } ?? Theme.gold
        let value = t.seconds.map { HUDStyle.clock(Double($0)) } ?? L("出現中", "UP")
        return HStack(spacing: 3) {
            if let team = t.team {
                Image(systemName: team == .blue ? "circle.fill" : "diamond.fill")
                    .font(.system(size: 5, weight: .black))
                    .foregroundStyle(tint)
            }
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
            Text(name).foregroundStyle(.white.opacity(0.85))
            Text(value)
                .monospacedDigit()
                .foregroundStyle(t.seconds == nil ? Theme.success : .white)
        }
        .font(.system(size: 10, weight: .heavy, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 7)
        .frame(height: HUDSpectatorLayout.objectivesHeight)
        .background(Capsule().fill(Color.black.opacity(0.5)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.55), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t.seconds == nil ? L("\(name) 出現中", "\(name) is up")
                            : L("\(name) 残り \(t.seconds ?? 0) 秒", "\(name) \(t.seconds ?? 0) seconds"))
    }
}

/// 観戦メニュー（引き出し）: 視界・カメラ・情報パネル・畳んだ再生操作を、アイコンと短い名前のタイル（44pt）で並べる。
/// 低い画面でも収まるように見出しは付けず、行ごとにまとめる（収まらなければスクロール）。
struct HUDSpectatorDrawer: View {
    let model: HUDModel
    let layout: HUDSpectatorLayout

    static let tileSize = CGSize(width: 62, height: 44)

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView(.vertical) { content }
                .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(.white)
        .frame(width: layout.drawerFrame.width)
        .frame(maxHeight: layout.drawerFrame.height)
        .hudGlass(cornerRadius: 18, tint: HUDStyle.accent.opacity(0.55))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("観戦メニュー", "Spectator menu"))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { model.toggleSpectatorDrawer() }
        .accessibilityIdentifier("spectate_menu_panel")
    }

    private var content: some View {
        let t = model.spectator.transport
        let c = model.controller
        let cb = model.settings.colorblindMode
        return VStack(alignment: .leading, spacing: 6) {
            // 視界・カメラ・閉じる
            HUDFlowRow(spacing: 4) {
                visionTile(nil, title: L("全体", "All"), symbol: "eye", tint: .white, id: "spectate_vision_all")
                visionTile(.blue, title: HUDText.teamName(.blue), symbol: "circle.fill",
                           tint: Theme.teamColor(.blue, colorblind: cb), id: "spectate_vision_blue")
                visionTile(.red, title: HUDText.teamName(.red), symbol: "diamond.fill",
                           tint: Theme.teamColor(.red, colorblind: cb), id: "spectate_vision_red")
                tile(L("自動カメラ", "Auto cam"), symbol: "video.fill", selected: c.spectatorDirectorEnabled,
                     label: L("自動カメラ", "Auto camera"), id: "spectate_director") { model.toggleSpectatorDirector() }
                tile(L("HUD 非表示", "Hide HUD"), symbol: "eye.slash.fill", selected: false,
                     label: L("HUD を隠す", "Hide HUD"), id: "spectate_cinematic") { model.setCinematic(true) }
                tile(L("閉じる", "Close"), symbol: "xmark", selected: false, label: L("観戦メニューを閉じる", "Close menu"),
                     id: "spectate_menu_close") { model.toggleSpectatorDrawer() }
            }
            // 情報パネル・目標タイマー（狭い画面は前後のヒーローもここ）
            HUDFlowRow(spacing: 4) {
                ForEach(HUDSpectatorState.Panel.allCases) { p in
                    tile(p.shortTitle, symbol: p.symbol, selected: model.spectator.panel == p, label: p.title,
                         id: "spectate_panel_\(p.rawValue)") { model.toggleSpectatorPanel(p) }
                }
                tile(L("タイマー", "Timers"), symbol: "timer", selected: model.spectator.showsObjectives,
                     label: L("目標タイマー", "Objective timers"), id: "spectate_objectives_toggle") { model.toggleObjectiveTimers() }
                // 下段の中央に置けない時（狭い画面・オンラインの観戦席は LIVE 表示が場所を使う）はここに出す
                if !layout.showsPrevNext || t.isLiveWatcher {
                    tile(L("前", "Prev"), symbol: "chevron.left", selected: false, label: L("前のヒーロー", "Previous hero"),
                         id: "spectate_prev_hero") { model.followAdjacentHero(-1) }
                    tile(L("次", "Next"), symbol: "chevron.right", selected: false, label: L("次のヒーロー", "Next hero"),
                         id: "spectate_next_hero") { model.followAdjacentHero(1) }
                }
            }
            if t.isSeekable {
                // 再生（下部ドックに入らなかった物）
                HUDFlowRow(spacing: 4) {
                    tile(L("最初から", "Restart"), symbol: "arrow.counterclockwise", selected: false,
                         label: L("最初から見る", "Restart"), id: "spectate_restart") { model.spectatorRestart() }
                    if !layout.inlineSkip30 {
                        tile(L("30秒戻る", "−30s"), symbol: "gobackward.30", selected: false, label: L("30 秒戻る", "Back 30 seconds"),
                             id: "spectate_back30", enabled: t.displayTick > 0) { model.spectatorSkip(seconds: -30) }
                        tile(L("30秒進む", "+30s"), symbol: "goforward.30", selected: false, label: L("30 秒進む", "Forward 30 seconds"),
                             id: "spectate_fwd30", enabled: !t.isEnded && t.displayTick < t.upperBound) {
                            model.spectatorSkip(seconds: 30)
                        }
                    }
                    if !layout.inlineStep {
                        tile(L("コマ送り", "Step"), symbol: "forward.frame.fill", selected: false, label: L("コマ送り", "Step forward"),
                             id: "spectate_step", enabled: t.isPaused && !t.isEnded) { model.spectatorStep() }
                    }
                }
                if !layout.inlineSpeeds {
                    HUDFlowRow(spacing: 4) {
                        ForEach(BattleController.spectatorSpeeds, id: \.self) { speed in
                            HUDSpeedButton(model: model, speed: speed)
                        }
                    }
                }
            }
        }
        .padding(10)
    }

    private func visionTile(_ team: Team?, title: String, symbol: String, tint: Color, id: String) -> some View {
        let selected = model.controller.spectatorVision == team
        return tile(title, symbol: symbol, selected: selected, label: L("視界: \(title)", "Vision: \(title)"), id: id,
                    tint: tint) { model.setSpectatorVision(team) }
    }

    /// アイコンと短い名前のタイル（62 × 44pt）。
    private func tile(_ title: String, symbol: String, selected: Bool, label: String, id: String, enabled: Bool = true,
                      tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(selected ? Color.black : tint)
                Text(title)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(selected ? Color.black : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 3)
            .frame(width: Self.tileSize.width, height: Self.tileSize.height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Theme.gold : Color.white.opacity(0.1)))
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(HUDPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// 折り返して並べる（観戦メニューのボタン群）。
struct HUDFlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

/// シネマ表示中に残す小さな「HUD を戻す」ボタン。
struct HUDCinematicRestoreButton: View {
    let model: HUDModel

    var body: some View {
        Button { model.setCinematic(false) } label: {
            Image(systemName: "eye.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(HUDPressStyle())
        .opacity(0.7)
        .accessibilityLabel(L("HUD を表示", "Show HUD"))
        .accessibilityIdentifier("spectate_cinematic_restore")
    }
}
