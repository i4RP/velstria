import SwiftUI
import VelstriaCore

// 担当: battle-hud（観戦）。情報パネル（右上ボタンの下。左利き配置では左）: 1 つずつ開く。
// - ヒーロー: 追従中のヒーローの詳細（HP / リソース・スキルのランクとクールダウン（必殺技も）・スペル・状態・装備・
//   Gold と装備の価値・K/D/A・CS・与ダメージ・被ダメージ・回復）。HUDModel.buildHeroCard（純粋関数）の出力を表示するだけ。
// - ゴールド推移: HUDGoldGraph
// - 出来事: 年表（キル・構造物・大型目標・全滅）を試合時間で新しい順に。タップでその少し前へシーク
//   （シークできない観戦席はカメラをその場面へ）
// 開いている間はキルフィードを隠す（同じ場所。出来事の一覧に全部ある）。

struct HUDSpectatorInfoPanel: View {
    let model: HUDModel
    let layout: HUDSpectatorLayout

    var body: some View {
        let current = model.spectator.panel
        let frame = layout.infoPanelFrame
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(HUDSpectatorState.Panel.allCases) { p in
                    tab(p, selected: p == current)
                }
                Spacer(minLength: 0)
                Button { if let current { model.toggleSpectatorPanel(current) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HUDPressStyle())
                .accessibilityLabel(L("パネルを閉じる", "Close panel"))
                .accessibilityIdentifier("spectate_panel_close")
            }
            .frame(height: 44)
            Group {
                switch current {
                case .hero?: HUDSpectatorHeroDetail(model: model)
                case .gold?: HUDGoldGraph(model: model)
                case .events?: HUDSpectatorEventLog(model: model)
                case nil: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .frame(width: frame.width, height: frame.height)
        .hudGlass(cornerRadius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spectate_info_panel")
    }

    private func tab(_ p: HUDSpectatorState.Panel, selected: Bool) -> some View {
        Button { if !selected { model.toggleSpectatorPanel(p) } } label: {
            Image(systemName: p.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(selected ? Color.black : .white.opacity(0.85))
                .frame(width: 34, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.gold : Color.white.opacity(0.08)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(p.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("spectate_tab_\(p.rawValue)")
    }
}

// MARK: - ヒーロー詳細

struct HUDSpectatorHeroDetail: View {
    let model: HUDModel

    var body: some View {
        if let card = model.spectator.heroCard {
            ScrollView(.vertical, showsIndicators: false) {
                content(card, colorblind: model.settings.colorblindMode)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("spectate_hero_detail")
        } else {
            Text(L("ヒーローを選ぶと詳細を表示します", "Select a hero to see details"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(HUDStyle.mutedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(_ card: HUDHeroCardSnapshot, colorblind: Bool) -> some View {
        let p = card.panel
        let h = p.hero
        let color = Theme.teamColor(card.team, colorblind: colorblind)
        let name = MasterData.shared.hero(h.heroID).map { MasterText.hero($0) } ?? h.heroID
        // 低い画面（パネルの中身が約 160pt）でもスクロールせずに見えるよう、各段を詰める
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                HUDPortraitLevel(heroID: h.heroID, level: h.level, xp: h.xpProgress, size: 38, pulse: 0)
                    .saturation(h.isDead ? 0 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: card.team == .blue ? "circle.fill" : "diamond.fill")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(color)
                        Text(name)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if card.isOwner {
                            Image(systemName: "star.fill").font(.system(size: 9, weight: .black)).foregroundStyle(Theme.gold)
                                .accessibilityLabel(L("記録した本人", "Recorded by you"))
                        }
                    }
                    HStack(spacing: 8) {
                        Text("\(card.kills) / \(card.deaths) / \(card.assists)")
                            .accessibilityLabel("K/D/A \(card.kills) / \(card.deaths) / \(card.assists)")
                        Text("CS \(card.creepScore)")
                        HStack(spacing: 2) {
                            HUDCoin(size: 10)
                            Text("\(h.gold)")
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L("所持 Gold \(h.gold)", "Gold \(h.gold)"))
                    }
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            if h.isDead {
                Text(L("倒れています（復活まで \(Int(h.respawn.rounded(.up))) 秒）", "Down (respawns in \(Int(h.respawn.rounded(.up)))s)"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.danger)
            } else {
                VStack(spacing: 3) {
                    HUDBar(value: p.vitals.hp, max: p.vitals.maxHP, shield: p.vitals.shield,
                           color: p.vitals.hpRatio < 0.3 ? HUDStyle.hpLow : HUDStyle.hp, height: 12, showsText: true)
                        .accessibilityElement()
                        .accessibilityLabel("HP")
                        .accessibilityValue("\(HUDStyle.number(p.vitals.hp)) / \(HUDStyle.number(p.vitals.maxHP))")
                    if p.vitals.maxResource > 0 {
                        HUDBar(value: p.vitals.resource, max: p.vitals.maxResource, shield: 0,
                               color: HUDStyle.resourceColor(p.vitals.resourceKind), height: 7, showsText: false)
                            .accessibilityElement()
                            .accessibilityLabel(p.vitals.resourceKind == .energy ? L("エナジー", "Energy") : L("マナ", "Mana"))
                            .accessibilityValue("\(HUDStyle.number(p.vitals.resource)) / \(HUDStyle.number(p.vitals.maxResource))")
                    }
                }
            }
            if let ch = h.channel {
                Label(HUDText.channelName(ch.kind), systemImage: ch.kind == .recall ? "house.fill" : "door.left.hand.open")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.cyan)
            }
            // スキル（必殺技も）とスペル
            HStack(spacing: 5) {
                ForEach(p.skills) { sk in
                    HUDSpectatorSkillIcon(skill: sk, role: h.role, resourceKind: p.vitals.resourceKind, diameter: 28)
                }
                Rectangle().fill(HUDStyle.rim).frame(width: 1, height: 24)
                ForEach(p.spells) { sp in
                    spell(sp)
                }
            }
            // 装備
            HStack(spacing: 3) {
                ForEach(0..<Balance.itemSlots, id: \.self) { k in
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.45))
                        if k < h.items.count, let item = MasterData.shared.item(h.items[k]) {
                            ItemIconView(item: item, size: 21)
                        }
                    }
                    .frame(width: 23, height: 23)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(k < h.items.count ? (MasterData.shared.item(h.items[k]).map { MasterText.item($0) } ?? "")
                                        : L("空きスロット", "Empty slot"))
                }
            }
            if !h.statuses.isEmpty {
                HUDStatusRow(statuses: h.statuses, size: 20)
            }
            // 成績
            HStack(spacing: 4) {
                stat(L("装備価値", "Net worth"), HUDStyle.thousands(Double(card.netWorth)), symbol: "bag.fill")
                stat(L("与ダメ", "Dealt"), HUDStyle.thousands(Double(card.damageDealt)), symbol: "flame.fill")
                stat(L("被ダメ", "Taken"), HUDStyle.thousands(Double(card.damageTaken)), symbol: "shield.fill")
                stat(L("回復", "Heal"), HUDStyle.thousands(Double(card.healing)), symbol: "cross.circle.fill")
            }
        }
    }

    private func spell(_ sp: HUDSpellSnapshot) -> some View {
        ZStack {
            if !sp.spellID.isEmpty { SpellIconView(spellID: sp.spellID, size: 24) }
            if sp.cooldown > 0 {
                Circle().fill(Color.black.opacity(0.6))
                Text(HUDStyle.cooldown(sp.cooldown))
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MasterData.shared.spell(sp.spellID).map { MasterText.spell($0) } ?? sp.spellID)
        .accessibilityValue(sp.cooldown > 0 ? L("残り \(HUDStyle.cooldown(sp.cooldown)) 秒", "\(HUDStyle.cooldown(sp.cooldown)) seconds left")
                            : L("使用可能", "Ready"))
    }

    private func stat(_ title: String, _ value: String, symbol: String) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 7, weight: .bold))
                Text(title).lineLimit(1).minimumScaleFactor(0.6)
            }
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(HUDStyle.mutedText)
            Text(value)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}

/// 観戦用のスキルの小さなアイコン（ランク・クールダウン・必殺技の準備。押せない）。
struct HUDSpectatorSkillIcon: View {
    let skill: HUDSkillSnapshot
    let role: Role
    let resourceKind: ResourceKind
    let diameter: CGFloat

    var body: some View {
        let isUlt = skill.slot == .ultimate
        let color = isUlt ? HUDStyle.violet : Theme.roleColor(role)
        ZStack {
            HUDAbilityFace(color: color, diameter: diameter, ultimate: isUlt)
            Image(systemName: HUDSymbols.skill(skill.archetype))
                .font(.system(size: diameter * 0.38, weight: .bold))
                .foregroundStyle(.white)
            if !skill.learned {
                Circle().fill(HUDStyle.surface.opacity(0.72))
                Image(systemName: "lock.fill").font(.system(size: diameter * 0.26, weight: .bold)).foregroundStyle(.white.opacity(0.8))
            } else if skill.cooldown > 0 {
                HUDCooldownPie(fraction: skill.cooldownFraction).fill(HUDStyle.surface.opacity(0.74))
                Text(HUDStyle.cooldown(skill.cooldown))
                    .font(.system(size: diameter * 0.32, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
            } else if isUlt {
                Circle().strokeBorder(Theme.gold, lineWidth: 2).padding(-2)
            }
            HUDRankPips(rank: skill.rank, maxRank: skill.slot.maxRank, diameter: diameter,
                        color: isUlt ? Theme.gold : HUDStyle.accent)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isUlt ? L("必殺技", "Ultimate") : CollectionStyle.slotName(skill.slot))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if !skill.learned { return L("未習得", "Not learned") }
        var parts = [L("ランク \(skill.rank)", "Rank \(skill.rank)")]
        parts.append(skill.cooldown > 0 ? L("残り \(HUDStyle.cooldown(skill.cooldown)) 秒", "\(HUDStyle.cooldown(skill.cooldown)) seconds left")
                     : L("使用可能", "Ready"))
        return parts.joined(separator: L("、", ", "))
    }
}

// MARK: - 出来事の一覧

struct HUDSpectatorEventLog: View {
    let model: HUDModel

    var body: some View {
        let entries = model.spectator.eventLog
        let cb = model.settings.colorblindMode
        let seekable = model.controller.isSeekable
        if entries.isEmpty {
            Text(L("まだ出来事はありません", "Nothing has happened yet"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(HUDStyle.mutedText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 3) {
                    ForEach(entries) { e in
                        row(e, colorblind: cb, seekable: seekable)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("spectate_event_log")
        }
    }

    private func row(_ e: HUDEventLogEntry, colorblind: Bool, seekable: Bool) -> some View {
        let color = e.team.map { Theme.teamColor($0, colorblind: colorblind) } ?? Theme.gold
        return Button { model.jumpToEvent(e) } label: {
            HStack(spacing: 6) {
                Text(HUDStyle.clock(Double(e.tick) * Balance.dt))
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(HUDStyle.mutedText)
                    .frame(width: 36, alignment: .leading)
                ZStack {
                    if let left = e.leftHeroID {
                        HeroPortraitView(heroID: left, size: 24, showsRole: false)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color, lineWidth: 1.2))
                    } else {
                        Image(systemName: e.symbol)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(color)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.4)))
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(e.title)
                        .font(.system(size: 11, weight: e.weight >= 0.7 ? .heavy : .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                    if let sub = e.subtitle {
                        Text(sub)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(HUDStyle.mutedText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
                if let right = e.rightHeroID {
                    HeroPortraitView(heroID: right, size: 22, showsRole: false)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .saturation(0.3)
                }
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(alignment: .leading) {
                // 有利になった側（色 + 形: ブルー = 丸、レッド = ひし形）
                Image(systemName: e.team == .red ? "diamond.fill" : (e.team == .blue ? "circle.fill" : "square.fill"))
                    .font(.system(size: 5, weight: .black))
                    .foregroundStyle(color)
                    .offset(x: -1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(HUDStyle.clock(Double(e.tick) * Balance.dt)) \(e.title)" + (e.subtitle.map { " \($0)" } ?? ""))
        .accessibilityHint(seekable ? L("タップでこの場面へ", "Tap to jump to this moment")
                                    : L("タップでカメラを向ける", "Tap to move the camera there"))
        .accessibilityIdentifier("spectate_event_\(e.id)")
    }
}
