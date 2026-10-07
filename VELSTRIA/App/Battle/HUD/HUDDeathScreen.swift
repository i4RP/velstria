import SwiftUI
import VelstriaCore

// 担当: battle-hud（death）。倒されてから復活するまでの画面:
// 死亡中の色調（カラーのまま少し落ち着かせる）、復活カウントの赤い翼型エンブレム（下部パネルの中央の上。
// 上に「デス情報を見る」、タップで開く）、デス情報パネル（とどめ・アシスト・直近 10 秒の被ダメージ内訳）と、
// その元になる被ダメージの記録（HUDDamageLog）。
// 15Hz で変わる復活秒数はエンブレムとパネル見出しの小さなビューだけが読む。
// 全体マップを開いている間はタップと VoiceOver を全体マップへ譲る。エンブレムは HUD の不透明度の設定に従う。

// MARK: - 被ダメージの記録

/// 自分が受けたダメージの直近の記録（倒された時にデス情報へまとめる）。
/// 同じユニット・同じ種類の連続ヒット（泉・継続ダメージは毎 tick 届く）は 0.25 秒刻みでまとめ、件数にも上限を設ける。
@MainActor
struct HUDDamageLog {
    /// 集計する秒数（倒される直前の何秒を見るか）。
    static let window: Double = 10
    /// 記録の上限（長い交戦でも肥大しない）。
    static let capacity = 384
    /// パネルに出すユニットの上限。
    static let maxSources = 5
    /// 連続ヒットをまとめる時間の刻み（秒）。
    static let bucketSeconds: Double = 0.25

    private struct Entry {
        var sourceID: EntityID?
        var targetID: EntityID
        var source: DamageSource
        var type: DamageType
        var amount: Double
        var time: Double
        var bucket: Int
    }

    /// ダメージを与えたユニットの表示情報。
    private struct Origin {
        var heroID: String?
        var kind: UnitKind?
        var team: Team?
        var name: String
    }

    /// 集計中の 1 ユニット分。
    private struct Tally {
        var key: EntityID
        var sourceID: EntityID?
        var total = 0.0
        var physical = 0.0
        var magic = 0.0
        var trueDamage = 0.0
        /// 内訳 id → 元の DamageSource と量。
        var parts: [String: (source: DamageSource, amount: Double)] = [:]
    }

    /// 時刻順。
    private var entries: [Entry] = []
    /// 最後に受けたダメージ（とどめの推定。連続ヒットをまとめても最後の 1 発の発生源が分かるように別に持つ）。
    private var lastHit: (sourceID: EntityID?, source: DamageSource)?

    /// 保持している記録の件数（テスト用）。
    var entryCount: Int { entries.count }

    /// 最後に受けたダメージが敵の泉（発生源の無い確定ダメージ）か。泉で倒されると unitDied の killerID が nil になるので、
    /// その時のとどめの推定に使う。
    var lastHitIsFountain: Bool { lastHit.map { $0.sourceID == nil && $0.source == .fountain } ?? false }

    mutating func record(_ e: DamageEvent, time: Double) {
        guard e.amount > 0, e.amount.isFinite else { return }
        lastHit = (e.sourceID, e.source)
        let bucket = Int((time / Self.bucketSeconds).rounded(.down))
        defer { prune(now: time) }
        // 直近の数件に同じユニット・種類・時間刻みがあれば足し込む
        for k in entries.indices.reversed().prefix(6) where entries[k].bucket == bucket {
            let x = entries[k]
            if x.sourceID == e.sourceID && x.source == e.source && x.type == e.damageType && x.targetID == e.targetID {
                entries[k].amount += e.amount
                return
            }
        }
        entries.append(Entry(sourceID: e.sourceID, targetID: e.targetID, source: e.source, type: e.damageType,
                             amount: e.amount, time: time, bucket: bucket))
    }

    mutating func reset() {
        entries.removeAll(keepingCapacity: true)
        lastHit = nil
    }

    /// 直近 window 秒の被ダメージをユニットごとにまとめる（量の多い順に最大 5 体。とどめのユニットは必ず含める）。
    /// killerID が nil（泉など発生源の無いダメージでとどめ）の時は、最後の 1 発の発生源の行をとどめにする。
    func recap(state: SimState, ctx: SimContext, killerID: EntityID?, time: Double) -> HUDDeathRecap {
        let victimTeam = entries.last.flatMap { state.unit($0.targetID)?.team }
        let killerKey = killerID ?? lastHit.flatMap { $0.sourceID == nil ? Self.environmentKey($0.source) : nil }
        return summarize(killerKey: killerKey, time: time, ctx: ctx, victimTeam: victimTeam) { id in
            guard let u = state.unit(id) else { return nil }
            return Origin(heroID: u.hero?.heroID, kind: u.kind, team: u.team, name: HUDModel.unitName(u, ctx))
        }
    }

    /// 画面確認用（-hudState death / deathinfo）: とどめのヒーロー（通常攻撃・スキル1・必殺技・継続ダメージ）、
    /// アシストのヒーロー、タワー、ミニオンから合計 4000 前後を受けた想定。
    static func debugSample(killerHeroID: String, assistHeroID: String, ctx: SimContext) -> HUDDeathRecap {
        let me: EntityID = 90_000, killer: EntityID = 90_001, assist: EntityID = 90_002
        let tower: EntityID = 90_003, minion: EntityID = 90_004
        func skillType(_ heroID: String, _ slot: SkillSlot) -> DamageType {
            ctx.master.skill(hero: heroID, slot: slot)?.damageType ?? .magic
        }
        func hit(_ t: Double, _ src: EntityID, _ amount: Double, _ type: DamageType,
                 _ source: DamageSource) -> (time: Double, event: DamageEvent) {
            (t, DamageEvent(sourceID: src, targetID: me, amount: amount, absorbed: 0, damageType: type, source: source,
                            isCrit: false, pos: .zero))
        }
        let hits = [
            hit(0.4, minion, 38, .physical, .minion), hit(1.3, minion, 41, .physical, .minion),
            hit(2.2, minion, 36, .physical, .minion), hit(3.1, minion, 39, .physical, .minion),
            hit(1.8, tower, 296, .physical, .tower), hit(3.0, tower, 338, .physical, .tower),
            hit(3.6, assist, 205, .physical, .basicAttack),
            hit(4.4, assist, 486, skillType(assistHeroID, .skill2), .skill(.skill2)),
            hit(5.1, assist, 212, .physical, .basicAttack),
            hit(5.9, killer, 642, skillType(killerHeroID, .skill1), .skill(.skill1)),
            hit(6.5, killer, 168, .physical, .basicAttack), hit(7.0, killer, 45, .trueDamage, .dot),
            hit(7.4, killer, 175, .physical, .basicAttack), hit(8.0, killer, 45, .trueDamage, .dot),
            hit(8.6, killer, 1060, skillType(killerHeroID, .ultimate), .skill(.ultimate)),
            hit(9.0, killer, 45, .trueDamage, .dot), hit(9.6, killer, 171, .physical, .basicAttack),
        ]
        var log = HUDDamageLog()
        for h in hits.sorted(by: { $0.time < $1.time }) { log.record(h.event, time: h.time) }
        func heroName(_ id: String) -> String { ctx.master.hero(id).map { MasterText.hero($0) } ?? id }
        let origins: [EntityID: Origin] = [
            killer: Origin(heroID: killerHeroID, kind: .hero, team: .red, name: heroName(killerHeroID)),
            assist: Origin(heroID: assistHeroID, kind: .hero, team: .red, name: heroName(assistHeroID)),
            tower: Origin(heroID: nil, kind: .tower, team: .red, name: HUDText.unitKind(.tower)),
            minion: Origin(heroID: nil, kind: .minion, team: .red, name: HUDText.unitKind(.minion)),
        ]
        return log.summarize(killerKey: killer, time: 10, ctx: ctx, victimTeam: .blue) { origins[$0] }
    }

    // MARK: 集計

    private mutating func prune(now: Double) {
        let cutoff = now - Self.window
        if let first = entries.first, first.time < cutoff {
            entries.removeFirst(entries.firstIndex { $0.time >= cutoff } ?? entries.count)
        }
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    /// killerKey: とどめの行の key（ユニットの EntityID、発生源の無いダメージは environmentKey）。
    private func summarize(killerKey: EntityID?, time: Double, ctx: SimContext, victimTeam: Team?,
                           lookup: (EntityID) -> Origin?) -> HUDDeathRecap {
        var tallies: [Tally] = []
        var slotByKey: [EntityID: Int] = [:]
        let cutoff = time - Self.window
        for e in entries where e.time >= cutoff && e.time <= time + 1e-6 {
            let key = e.sourceID ?? Self.environmentKey(e.source)
            let i: Int
            if let k = slotByKey[key] {
                i = k
            } else {
                i = tallies.count
                slotByKey[key] = i
                tallies.append(Tally(key: key, sourceID: e.sourceID))
            }
            tallies[i].total += e.amount
            switch e.type {
            case .physical: tallies[i].physical += e.amount
            case .magic: tallies[i].magic += e.amount
            case .trueDamage: tallies[i].trueDamage += e.amount
            }
            tallies[i].parts[Self.partID(e.source), default: (e.source, 0)].amount += e.amount
        }

        var sources: [HUDDeathRecap.Source] = tallies.map { t in
            // ユニットが既に消えている（倒されたミニオン等）・発生源が無い（泉）時はダメージの種類から推定する
            let lead = t.parts.values.max { $0.amount < $1.amount }?.source ?? .basicAttack
            let origin = t.sourceID.flatMap(lookup) ?? Self.inferredOrigin(lead, victimTeam: victimTeam)
            let parts = t.parts.values
                .map { Self.part(for: $0.source, heroID: origin.heroID, ctx: ctx, amount: $0.amount) }
                .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : Self.partRank($0.id) < Self.partRank($1.id) }
            return HUDDeathRecap.Source(id: t.key, heroID: origin.heroID, kind: origin.kind, team: origin.team,
                                        name: origin.name, total: t.total, physical: t.physical, magic: t.magic,
                                        trueDamage: t.trueDamage, parts: parts,
                                        isKiller: killerKey != nil && t.key == killerKey)
        }
        sources.sort { $0.total != $1.total ? $0.total > $1.total : $0.id < $1.id }
        var shown = Array(sources.prefix(Self.maxSources))
        if let k = sources.firstIndex(where: \.isKiller), k >= Self.maxSources {
            // とどめは量に関係なく載せる（最後の枠と入れ替える。量の多い順は保たれる）
            shown[Self.maxSources - 1] = sources[k]
        }

        var recap = HUDDeathRecap(window: Self.window)
        for t in tallies {
            recap.total += t.total
            recap.physical += t.physical
            recap.magic += t.magic
            recap.trueDamage += t.trueDamage
        }
        recap.sources = shown
        return recap
    }

    /// 発生源の無いダメージ（泉など）をまとめる仮の ID（実在の EntityID は 1 以上）。
    static func environmentKey(_ s: DamageSource) -> EntityID {
        switch s {
        case .fountain: return -1
        case .tower: return -2
        case .minion: return -3
        case .monster: return -4
        default: return -5
        }
    }

    /// ダメージの種類 → 与えたユニットの種類の推定（泉は nil）。
    static func inferredKind(_ s: DamageSource) -> UnitKind? {
        switch s {
        case .tower: return .tower
        case .minion: return .minion
        case .monster: return .monster
        case .fountain: return nil
        case .basicAttack, .skill, .spell, .item, .dot, .passive: return .hero
        }
    }

    private static func inferredOrigin(_ s: DamageSource, victimTeam: Team?) -> Origin {
        let kind = inferredKind(s)
        let team: Team? = s == .monster ? .neutral : victimTeam?.opponent
        return Origin(heroID: nil, kind: kind, team: team, name: kind.map(HUDText.unitKind) ?? L("泉", "Fountain"))
    }

    // MARK: 内訳

    static func partID(_ s: DamageSource) -> String {
        switch s {
        case .basicAttack: return "basic"
        case .skill(let slot):
            switch slot {
            case .skill1: return "skill1"
            case .skill2: return "skill2"
            case .skill3: return "skill3"
            case .ultimate: return "ultimate"
            case .passive: return "passive"
            }
        case .passive: return "passive"
        case .spell: return "spell"
        case .item: return "item"
        case .dot: return "dot"
        case .tower: return "tower"
        case .minion: return "minion"
        case .monster: return "monster"
        case .fountain: return "fountain"
        }
    }

    /// 同量の時の並び（大技を先に）。
    private static let partOrder = ["ultimate", "skill1", "skill2", "skill3", "passive", "basic", "spell", "item", "dot",
                                    "tower", "minion", "monster", "fountain"]

    private static func partRank(_ id: String) -> Int { partOrder.firstIndex(of: id) ?? partOrder.count }

    /// 内訳 1 行の表示（スキルはヒーローのスキル名とアーキタイプのアイコン。ヒーロー不明なら枠の名前）。
    static func part(for s: DamageSource, heroID: String?, ctx: SimContext, amount: Double) -> HUDDeathRecap.Part {
        let id = partID(s)
        func make(_ label: String, _ symbol: String) -> HUDDeathRecap.Part {
            HUDDeathRecap.Part(id: id, label: label, symbol: symbol, amount: amount)
        }
        switch s {
        case .skill(let slot): return skillPart(slot: slot, heroID: heroID, ctx: ctx, make: make)
        case .passive: return skillPart(slot: .passive, heroID: heroID, ctx: ctx, make: make)
        case .basicAttack: return make(L("通常攻撃", "Basic attack"), "figure.fencing")
        case .spell: return make(L("スペル", "Spell"), "wand.and.stars")
        case .item: return make(L("装備効果", "Item effect"), "cube.fill")
        case .dot: return make(L("継続ダメージ", "Damage over time"), "flame")
        case .tower: return make(L("タワー攻撃", "Tower shot"), "building.columns.fill")
        case .minion: return make(L("ミニオン攻撃", "Minion attack"), "person.3.fill")
        case .monster: return make(L("モンスター攻撃", "Monster attack"), "pawprint.fill")
        case .fountain: return make(L("泉の守り", "Fountain"), "drop.fill")
        }
    }

    private static func skillPart(slot: SkillSlot, heroID: String?, ctx: SimContext,
                                  make: (String, String) -> HUDDeathRecap.Part) -> HUDDeathRecap.Part {
        let fallback: (label: String, symbol: String)
        switch slot {
        case .skill1: fallback = (L("スキル1", "Skill 1"), "1.circle.fill")
        case .skill2: fallback = (L("スキル2", "Skill 2"), "2.circle.fill")
        case .skill3: fallback = (L("スキル3", "Skill 3"), "3.circle.fill")
        case .ultimate: fallback = (L("必殺技", "Ultimate"), "star.fill")
        case .passive: fallback = (L("パッシブ", "Passive"), "seal.fill")
        }
        guard let heroID, let sk = ctx.master.skill(hero: heroID, slot: slot) else {
            return make(fallback.label, fallback.symbol)
        }
        let symbol = ctx.master.hero(heroID).map { HUDSymbols.skill(SkillCatalog.targeting(for: sk, hero: $0).archetype) }
        return make(MasterText.skill(sk), symbol ?? fallback.symbol)
    }
}

// MARK: - 色と書式

enum HUDDeathStyle {
    /// エンブレムの縁（明るい赤）と、残り 3 秒以下の縁。
    static let rim = Color(red: 0.98, green: 0.22, blue: 0.18)
    static let rimUrgent = Color(red: 1.0, green: 0.36, blue: 0.28)
    static let wingTop = Color(red: 0.42, green: 0.03, blue: 0.04).opacity(0.30)
    static let wingBottom = Color(red: 0.70, green: 0.06, blue: 0.05).opacity(0.88)
    static let killerTag = Color(red: 0.86, green: 0.15, blue: 0.15)

    static let physical = Color(red: 1.0, green: 0.58, blue: 0.22)
    static let magic = Color(red: 0.56, green: 0.48, blue: 1.0)
    static let trueDamage = Color(white: 0.94)

    static let damageTypes: [DamageType] = [.physical, .magic, .trueDamage]

    static func typeColor(_ t: DamageType) -> Color {
        switch t {
        case .physical: return physical
        case .magic: return magic
        case .trueDamage: return trueDamage
        }
    }

    /// 凡例の形（色覚サポート: 色だけに頼らない）。
    static func typeMarker(_ t: DamageType) -> String {
        switch t {
        case .physical: return "square.fill"
        case .magic: return "circle.fill"
        case .trueDamage: return "diamond.fill"
        }
    }

    static func typeName(_ t: DamageType) -> String {
        switch t {
        case .physical: return L("物理", "Physical")
        case .magic: return L("魔法", "Magic")
        case .trueDamage: return L("確定", "True")
        }
    }

    /// 種類のアイコン（nil = 泉）。
    static func unitSymbol(_ kind: UnitKind?) -> String {
        switch kind {
        case .hero?: return "person.fill"
        case .minion?: return "person.3.fill"
        case .tower?, .core?: return "building.columns.fill"
        case .monster?: return "pawprint.fill"
        case .dummy?: return "figure.stand"
        case nil: return "drop.fill"
        }
    }

    /// 3 桁区切りの整数（表示言語に関係なく "3,962"）。
    static func amount(_ v: Double) -> String {
        Int(max(0, v).rounded()).formatted(.number.locale(Locale(identifier: "en_US")))
    }

    static func percent(_ part: Double, of total: Double) -> String {
        total > 0 ? "\(Int((part / total * 100).rounded()))%" : "0%"
    }
}

// MARK: - 配置

extension HUDLayout {
    /// エンブレムの基準の高さ（16e で 52pt = ラベル 14pt + 翼 38pt）。
    static let deathEmblemBaseHeight: CGFloat = 52

    /// 復活カウントのエンブレムの大きさ（「デス情報を見る」のラベルを含むタップ領域）。
    /// 参考画面の比率で幅は画面の約 19%、翼の高さは画面の約 1 割。
    var deathEmblemSize: CGSize {
        CGSize(width: (width * 0.19).rounded(), height: max(44, Self.deathEmblemBaseHeight * min(scale, 1.1)))
    }

    /// エンブレムの中心: 下部パネルの中央の上、味方の追従一覧（HUDDeathMetrics.stripFrame。味方の数に関わらず高さ一定）のさらに上。
    /// 状態アイコン列（パネル左上 26pt 上）・おすすめ購入（パネル右上）とは横に離れ、スペル・帰還・攻撃列（3 つ）・
    /// ミニマップドック（全体マップボタン込み）・スティックの受付領域にもかからない（左利きの反転でも同じ）。
    /// 詠唱バーと同じ高さになるが、死亡中は詠唱しない。
    var deathEmblemCenter: CGPoint {
        let bottom = HUDDeathMetrics.stripFrame(self, allies: 4).minY - 4
        return CGPoint(x: heroPanelCenterX, y: bottom - deathEmblemSize.height / 2)
    }

    /// デス情報パネルの大きさ（16e の高さ 390 にも収まる）。
    var deathRecapSize: CGSize {
        let s = min(scale, 1.08)
        return CGSize(width: min(600 * s, trailingEdge - leadingEdge - 40),
                      height: min(330 * s, bottomEdge - topEdge - 16))
    }
}

// MARK: - 死亡中の色調

/// 死亡中の色調（3D 描画の上、操作部品の下）。
struct HUDDeathTintLayer: View {
    let model: HUDModel

    var body: some View {
        // 味方を追っている間は戦いが見やすいよう、さらに薄くする
        HUDDeathTint(active: model.hero.isDead, followingAlly: model.cameraFollowID != nil)
    }
}

/// カラーのまま彩度と明るさを少し落とし、四隅だけ薄く暗くする（操作は下の HUD へ通す）。
struct HUDDeathTint: View {
    let active: Bool
    var followingAlly = false

    var body: some View {
        ZStack {
            if active {
                ZStack {
                    Rectangle().fill(Color(white: 0.5)).blendMode(.saturation).opacity(followingAlly ? 0.12 : 0.28)
                    Rectangle().fill(Color.black.opacity(followingAlly ? 0.03 : 0.10))
                    EllipticalGradient(stops: [.init(color: .clear, location: 0.6),
                                               .init(color: .black.opacity(0.32), location: 1)],
                                       center: .center, startRadiusFraction: 0, endRadiusFraction: 0.74)
                }
                .transition(.opacity)
            }
        }
        // 0.6 秒でフェードイン、復活で 0.4 秒フェードアウト
        .animation(active ? .easeOut(duration: 0.6) : .easeIn(duration: 0.4), value: active)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 復活カウントとデス情報

/// 復活カウントのエンブレムとデス情報パネル（操作部品の上）。
struct HUDDeathInfoLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        // 全体マップ（この上に重なる）を開いている間はタップと VoiceOver を譲る
        let mapOpen = model.isTacticalMapOpen
        ZStack {
            HUDDeathEmblemLayer(model: model, layout: layout)
                .opacity(model.settings.hudOpacity)
            HUDDeathRecapLayer(model: model, layout: layout)
        }
        .frame(width: layout.width, height: layout.height)
        .allowsHitTesting(!mapOpen)
        .accessibilityHidden(mapOpen)
    }
}

/// エンブレムの配置（復活秒数を読む。エンブレム本体は秒が変わった時だけ描き直す）。
private struct HUDDeathEmblemLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let hero = model.hero
        ZStack {
            if hero.isDead {
                HUDDeathEmblem(model: model, seconds: max(0, Int(hero.respawn.rounded(.up))), size: layout.deathEmblemSize)
                    .equatable()
                    .position(layout.deathEmblemCenter)
                    .transition(.opacity)
            }
        }
        .frame(width: layout.width, height: layout.height)
        .animation(.easeOut(duration: 0.3), value: hero.isDead)
    }
}

/// デス情報パネル（暗幕のタップで閉じる）。
private struct HUDDeathRecapLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let open = model.deathRecapOpen
        ZStack {
            if open {
                Color.black.opacity(0.45)
                    .contentShape(Rectangle())
                    .onTapGesture { model.closeDeathRecap() }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                HUDDeathRecapPanel(model: model, info: model.deathInfo, colorblind: model.settings.colorblindMode,
                                   size: layout.deathRecapSize, scale: min(layout.scale, 1.08))
                    .equatable()
                    .position(x: layout.width / 2, y: (layout.topEdge + layout.bottomEdge) / 2)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .frame(width: layout.width, height: layout.height)
        .animation(.spring(duration: 0.3), value: open)
    }
}

// MARK: - エンブレム

/// 復活カウントのエンブレム: 中央の台座から左右へ先細りの赤い翼、中に秒数、上に「デス情報を見る ›」。
/// 出現時は翼が中央から広がり、残り 3 秒以下は秒が変わるたびに数字が脈動し縁が明るくなる。
struct HUDDeathEmblem: View, Equatable {
    let model: HUDModel
    let seconds: Int
    let size: CGSize
    @State private var spread = false

    static func == (a: Self, b: Self) -> Bool { a.seconds == b.seconds && a.size == b.size }

    var body: some View {
        let s = size.height / HUDLayout.deathEmblemBaseHeight
        let labelHeight = 14 * s
        let wingHeight = size.height - labelHeight
        let urgent = seconds <= 3
        Button { model.openDeathRecap() } label: {
            VStack(spacing: 0) {
                label(s)
                    .frame(height: labelHeight)
                ZStack {
                    HUDDeathWings(width: size.width, height: wingHeight, scale: s, urgent: urgent, beat: seconds)
                        .scaleEffect(x: spread ? 1 : 0.12, y: spread ? 1 : 0.6)
                        .opacity(spread ? 1 : 0)
                    number(s, urgent: urgent)
                        .offset(y: -wingHeight * 0.08)
                }
                .frame(width: size.width, height: wingHeight)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.2)) { spread = true }
        }
        // 名前は見えている文字（「デス情報を見る」）にそろえる（音声コントロールで見たまま言えば押せる）。
        // 毎秒変わる復活秒数は値へ
        .hudAccessibility(id: "hud_death", label: L("デス情報を見る", "View death recap"),
                          value: L("復活まで \(seconds) 秒", "Respawn in \(seconds) seconds")) {
            model.openDeathRecap()
        }
        .accessibilityInputLabels([L("デス情報を見る", "View death recap"), L("デス情報", "Death recap")])
    }

    private func label(_ s: CGFloat) -> some View {
        HStack(spacing: 2 * s) {
            Text(L("デス情報を見る", "View death recap"))
            Image(systemName: "chevron.right")
                .font(.system(size: 7.5 * s, weight: .heavy))
        }
        .font(.system(size: 10.5 * s, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.86))
        .shadow(color: .black.opacity(0.9), radius: 1.5)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func number(_ s: CGFloat, urgent: Bool) -> some View {
        Text("\(seconds)")
            .font(.system(size: 18.5 * s, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(LinearGradient(colors: [.white, Color(red: 1, green: 0.86, blue: 0.84)],
                                            startPoint: .top, endPoint: .bottom))
            .shadow(color: Color(red: 0.45, green: 0, blue: 0).opacity(0.95), radius: 2 * s)
            .contentTransition(.numericText(countsDown: true))
            .animation(.spring(duration: 0.3), value: seconds)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: seconds) { content, k in
                content.scaleEffect(urgent ? k : 1)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.3, duration: 0.12)
                    SpringKeyframe(1, duration: 0.5, spring: .bouncy)
                }
            }
    }
}

/// エンブレムの翼（塗り・縁・羽の筋・下中央の菱形）。
private struct HUDDeathWings: View {
    let width: CGFloat
    let height: CGFloat
    let scale: CGFloat
    let urgent: Bool
    /// 秒が変わるたびに縁を光らせる（残り 3 秒以下）。
    let beat: Int

    var body: some View {
        let s = scale
        let rim = urgent ? HUDDeathStyle.rimUrgent : HUDDeathStyle.rim
        ZStack {
            HUDDeathWingShape(part: .body)
                .fill(LinearGradient(colors: [HUDDeathStyle.wingTop, HUDDeathStyle.wingBottom],
                                     startPoint: .top, endPoint: .bottom))
                // 翼端へ向かって薄く
                .mask(LinearGradient(stops: [.init(color: .black.opacity(0.3), location: 0),
                                             .init(color: .black, location: 0.34), .init(color: .black, location: 0.66),
                                             .init(color: .black.opacity(0.3), location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
            HUDDeathWingShape(part: .ribs)
                .stroke(rim.opacity(urgent ? 0.75 : 0.55), style: StrokeStyle(lineWidth: 0.8 * s, lineCap: .round))
            HUDDeathWingShape(part: .lowerEdge)
                .stroke(rim, style: StrokeStyle(lineWidth: (urgent ? 2 : 1.4) * s, lineCap: .round, lineJoin: .round))
                .keyframeAnimator(initialValue: CGFloat(0), trigger: beat) { content, glow in
                    content.shadow(color: rim.opacity(urgent ? 0.85 + 0.15 * Double(glow) : 0.7),
                                   radius: (urgent ? 5 + 5 * glow : 3) * s)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(1, duration: 0.1)
                        CubicKeyframe(0, duration: 0.6)
                    }
                }
            HUDDeathDiamond()
                .fill(Color(red: 0.30, green: 0.02, blue: 0.03).opacity(0.55))
                .overlay(HUDDeathDiamond().stroke(rim, lineWidth: 1.1 * s))
                .frame(width: 7 * s, height: 8 * s)
                .position(x: width / 2, y: height - 3 * s)
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 翼型（中央の台座から左右へ先細り。下辺は翼端から落ちて中央で尖る）。座標は枠に対する割合。
struct HUDDeathWingShape: Shape {
    enum Part { case body, lowerEdge, ribs }
    var part: Part

    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        switch part {
        case .body:
            path.move(to: p(0, 0.16))
            addUpper(&path, p)
            addLower(&path, p, reversed: true)
            path.closeSubpath()
        case .lowerEdge:
            path.move(to: p(0, 0.16))
            addLower(&path, p, reversed: false)
        case .ribs:
            // 左右の翼に 2 本ずつ、上辺から下辺へ流れる羽の筋
            for mirror in [false, true] {
                func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { p(mirror ? 1 - x : x, y) }
                path.move(to: q(0.05, 0.07))
                path.addQuadCurve(to: q(0.26, 0.60), control: q(0.19, 0.12))
                path.move(to: q(0.14, 0.0))
                path.addQuadCurve(to: q(0.34, 0.68), control: q(0.27, 0.06))
            }
        }
        return path
    }

    /// 左の翼端 → 台座の上辺 → 右の翼端。
    private func addUpper(_ path: inout Path, _ p: (CGFloat, CGFloat) -> CGPoint) {
        path.addQuadCurve(to: p(0.30, 0.02), control: p(0.14, 0.02))
        path.addLine(to: p(0.70, 0.02))
        path.addQuadCurve(to: p(1, 0.16), control: p(0.86, 0.02))
    }

    /// 下辺（reversed = 右の翼端から左へ）。
    private func addLower(_ path: inout Path, _ p: (CGFloat, CGFloat) -> CGPoint, reversed: Bool) {
        if reversed {
            path.addQuadCurve(to: p(0.60, 0.74), control: p(0.84, 0.66))
            path.addQuadCurve(to: p(0.5, 1), control: p(0.54, 0.78))
            path.addQuadCurve(to: p(0.40, 0.74), control: p(0.46, 0.78))
            path.addQuadCurve(to: p(0, 0.16), control: p(0.16, 0.66))
        } else {
            path.addQuadCurve(to: p(0.40, 0.74), control: p(0.16, 0.66))
            path.addQuadCurve(to: p(0.5, 1), control: p(0.46, 0.78))
            path.addQuadCurve(to: p(0.60, 0.74), control: p(0.54, 0.78))
            path.addQuadCurve(to: p(1, 0.16), control: p(0.84, 0.66))
        }
    }
}

/// 下中央の小さな菱形。
struct HUDDeathDiamond: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

// MARK: - デス情報パネル

/// デス情報パネル: 見出し（復活まで N 秒・閉じる）、左にとどめとアシスト、右に直近の被ダメージ内訳。
struct HUDDeathRecapPanel: View, Equatable {
    let model: HUDModel
    let info: HUDDeathInfo?
    let colorblind: Bool
    let size: CGSize
    let scale: CGFloat

    static func == (a: Self, b: Self) -> Bool {
        a.info == b.info && a.colorblind == b.colorblind && a.size == b.size && a.scale == b.scale
    }

    var body: some View {
        let s = scale
        VStack(spacing: 0) {
            header(s)
            Rectangle()
                .fill(LinearGradient(colors: [.clear, HUDDeathStyle.rim.opacity(0.7), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
            HStack(alignment: .top, spacing: 12 * s) {
                killerColumn(s)
                    .frame(width: 128 * s)
                Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1)
                damageColumn(s)
            }
            .padding(.horizontal, 14 * s)
            .padding(.top, 8 * s)
            .padding(.bottom, 8 * s)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(RadialGradient(colors: [HUDDeathStyle.killerTag.opacity(0.18), .clear], center: .topLeading,
                                     startRadius: 10, endRadius: 320))
        )
        .hudGlass(cornerRadius: 16, tint: HUDDeathStyle.rim.opacity(0.75))
        // 下の HUD が透けないよう暗く敷く（影は図形だけに付ける。ビュー全体の影は毎フレームの合成が重い）
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.03, green: 0.02, blue: 0.06).opacity(0.82))
                .shadow(color: .black.opacity(0.5), radius: 16)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud_death_recap")
    }

    // MARK: 見出し

    private func header(_ s: CGFloat) -> some View {
        HStack(spacing: 10 * s) {
            Image(systemName: "heart.slash.fill")
                .font(.system(size: 15 * s, weight: .bold))
                .foregroundStyle(HUDDeathStyle.rim)
                .accessibilityHidden(true)
            Text(L("デス情報", "Death Recap"))
                .font(.system(size: 17 * s, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            HUDDeathRespawnBadge(model: model, scale: s)
            Spacer(minLength: 8)
            Button { model.closeDeathRecap() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13 * s, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 30 * s, height: 30 * s)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HUDPressStyle())
            .accessibilityLabel(L("閉じる", "Close"))
            .accessibilityIdentifier("death_recap_close")
        }
        .padding(.leading, 16 * s)
        .padding(.trailing, 6 * s)
        .frame(height: max(44, 44 * s))
    }

    // MARK: とどめ・アシスト

    private var killerColor: Color {
        info?.killerTeam.map { Theme.teamColor($0, colorblind: colorblind) } ?? Color.gray
    }

    private var killerName: String {
        if let name = info?.killerName { return name }
        if let id = info?.killerHeroID { return MasterData.shared.hero(id).map { MasterText.hero($0) } ?? id }
        if let kind = info?.killerKind { return HUDText.unitKind(kind) }
        if info?.killerIsFountain == true { return L("泉", "Fountain") }
        return L("不明", "Unknown")
    }

    /// ヒーロー以外のとどめのアイコン（泉は内訳の行と同じ drop.fill）。
    private var killerSymbol: String {
        if info?.killerIsFountain == true { return HUDDeathStyle.unitSymbol(nil) }
        return info?.killerKind.map { HUDDeathStyle.unitSymbol($0) } ?? "questionmark"
    }

    private func killerColumn(_ s: CGFloat) -> some View {
        let color = killerColor
        let assists = info?.assistHeroIDs ?? []
        return VStack(spacing: 6 * s) {
            HUDDeathUnitIcon(heroID: info?.killerHeroID, symbol: killerSymbol, color: color, size: 62 * s)
                .shadow(color: color.opacity(0.5), radius: 6)
                .overlay(alignment: .bottom) {
                    HUDDeathKillerTag(scale: s * 1.1)
                        .offset(y: 8 * s)
                }
                .padding(.bottom, 6 * s)
            Text(killerName)
                .font(.system(size: 13 * s, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let team = info?.killerTeam, team != .neutral {
                Text(HUDText.teamName(team))
                    .font(.system(size: 10 * s, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
                .padding(.vertical, 2 * s)
            Text(L("アシスト", "Assists"))
                .font(.system(size: 10.5 * s, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
            if assists.isEmpty {
                Text(L("なし", "None"))
                    .font(.system(size: 11 * s, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                HStack(spacing: 4 * s) {
                    ForEach(Array(assists.prefix(4).enumerated()), id: \.offset) { _, id in
                        HUDDeathUnitIcon(heroID: id, symbol: "person.fill", color: color.opacity(0.85), size: 27 * s)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(killerAccessibility(assists))
    }

    private func killerAccessibility(_ assists: [String]) -> String {
        let names = assists.map { id in MasterData.shared.hero(id).map { MasterText.hero($0) } ?? id }
        let assistText = names.isEmpty ? L("アシストなし", "No assists") : L("アシスト: ", "Assists: ") + names.joined(separator: ", ")
        return L("とどめ: \(killerName)。", "Killed by \(killerName). ") + assistText
    }

    // MARK: 被ダメージ

    private func damageColumn(_ s: CGFloat) -> some View {
        let recap = info?.recap ?? HUDDeathRecap()
        let window = Int(recap.window.rounded())
        let maxTotal = recap.sources.map(\.total).max() ?? 0
        return VStack(alignment: .leading, spacing: 4 * s) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("直近 \(window) 秒の被ダメージ", "Damage taken (last \(window)s)"))
                    .font(.system(size: 12 * s, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 6)
                Text(HUDDeathStyle.amount(recap.total))
                    .font(.system(size: 19 * s, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .accessibilityElement(children: .combine)
            HUDDeathTypeBar(physical: recap.physical, magic: recap.magic, trueDamage: recap.trueDamage,
                            fill: recap.total > 0 ? 1 : 0, height: 9 * s)
            legend(recap, s)
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
            if recap.sources.isEmpty {
                Text(L("記録なし", "No damage recorded"))
                    .font(.system(size: 13 * s, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 3 * s) {
                        ForEach(recap.sources) { src in
                            // 行は縮めない（収まらない時はスクロール）
                            HUDDeathSourceRow(source: src, maxTotal: maxTotal, colorblind: colorblind, scale: s)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func legend(_ recap: HUDDeathRecap, _ s: CGFloat) -> some View {
        HStack(spacing: 12 * s) {
            ForEach(HUDDeathStyle.damageTypes, id: \.self) { t in
                let v = t == .physical ? recap.physical : (t == .magic ? recap.magic : recap.trueDamage)
                HStack(spacing: 3 * s) {
                    Image(systemName: HUDDeathStyle.typeMarker(t))
                        .font(.system(size: 7 * s, weight: .black))
                        .foregroundStyle(HUDDeathStyle.typeColor(t))
                    Text(HUDDeathStyle.typeName(t))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(HUDDeathStyle.percent(v, of: recap.total))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(HUDDeathStyle.typeName(t)) \(HUDDeathStyle.amount(v))")
            }
        }
        .font(.system(size: 10.5 * s, weight: .bold, design: .rounded))
    }
}

/// 見出しの「復活まで N 秒」（復活秒数を読む小さなビュー）。
private struct HUDDeathRespawnBadge: View {
    let model: HUDModel
    let scale: CGFloat

    var body: some View {
        let n = max(0, Int(model.hero.respawn.rounded(.up)))
        HStack(spacing: 4 * scale) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 10 * scale, weight: .black))
            Text(L("復活まで \(n) 秒", "Respawn in \(n)s"))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(duration: 0.3), value: n)
        }
        .font(.system(size: 12 * scale, weight: .bold, design: .rounded))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 9 * scale)
        .padding(.vertical, 3 * scale)
        .background(Capsule().fill(HUDDeathStyle.killerTag.opacity(0.32)))
        .overlay(Capsule().strokeBorder(HUDDeathStyle.rim.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("復活まで \(n) 秒", "Respawn in \(n) seconds"))
    }
}

/// 赤い「とどめ」タグ。
private struct HUDDeathKillerTag: View {
    let scale: CGFloat

    var body: some View {
        Text(L("とどめ", "KILLER"))
            .font(.system(size: 9 * scale, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5 * scale)
            .padding(.vertical, 1.5 * scale)
            .background(Capsule().fill(HUDDeathStyle.killerTag))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.8))
    }
}

/// ヒーローは顔、それ以外は種類のアイコン（チーム色の枠）。
private struct HUDDeathUnitIcon: View {
    let heroID: String?
    let symbol: String
    let color: Color
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        ZStack {
            if let heroID {
                HeroPortraitView(heroID: heroID, size: size, showsRole: false)
                    .clipShape(shape)
            } else {
                shape.fill(LinearGradient(colors: [color.opacity(0.5), Color.black.opacity(0.65)],
                                          startPoint: .top, endPoint: .bottom))
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(color, lineWidth: max(1.2, size * 0.045)))
        .accessibilityHidden(true)
    }
}

/// ダメージを与えたユニット 1 行: アイコン・名前（とどめ）・最大値比のバー・量・内訳。
private struct HUDDeathSourceRow: View {
    let source: HUDDeathRecap.Source
    let maxTotal: Double
    let colorblind: Bool
    let scale: CGFloat

    var body: some View {
        let s = scale
        let color = source.team.map { Theme.teamColor($0, colorblind: colorblind) } ?? Color.gray
        HStack(spacing: 8 * s) {
            HUDDeathUnitIcon(heroID: source.heroID, symbol: HUDDeathStyle.unitSymbol(source.kind), color: color, size: 28 * s)
            VStack(alignment: .leading, spacing: 2 * s) {
                HStack(spacing: 6 * s) {
                    HStack(spacing: 4 * s) {
                        Text(source.name)
                            .font(.system(size: 12 * s, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if source.isKiller { HUDDeathKillerTag(scale: s) }
                    }
                    .frame(width: 150 * s, alignment: .leading)
                    HUDDeathTypeBar(physical: source.physical, magic: source.magic, trueDamage: source.trueDamage,
                                    fill: maxTotal > 0 ? source.total / maxTotal : 0, height: 6 * s)
                    Text(HUDDeathStyle.amount(source.total))
                        .font(.system(size: 13 * s, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(minWidth: 40 * s, alignment: .trailing)
                }
                // 縮小はしない（アイコンの高さで行ごとに文字の大きさが揃わなくなる）
                partsText(s)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 2.5 * s)
        .padding(.horizontal, 6 * s)
        .background(
            RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                .fill(source.isKiller ? HUDDeathStyle.killerTag.opacity(0.18) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8 * s, style: .continuous)
                .strokeBorder(source.isKiller ? HUDDeathStyle.rim.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// 「アイコン 名前 量 · …」の小さな文字列（多い順に 3 つまで）。
    private func partsText(_ s: CGFloat) -> some View {
        let parts = source.parts.prefix(3)
        let text = parts.enumerated().reduce(Text(verbatim: "")) { acc, item in
            let p = item.element
            let sep = item.offset == 0 ? "" : "  ·  "
            return Text("\(acc)\(sep)\(Image(systemName: p.symbol)) \(p.label) \(HUDDeathStyle.amount(p.amount))")
        }
        return text
            .font(.system(size: 9.5 * s, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.62))
    }

    private var accessibilityText: String {
        var t = "\(source.name) \(HUDDeathStyle.amount(source.total))"
        if source.isKiller { t += L("（とどめ）", " (killer)") }
        let parts = source.parts.map { "\($0.label) \(HUDDeathStyle.amount($0.amount))" }
        return parts.isEmpty ? t : t + ": " + parts.joined(separator: ", ")
    }
}

/// 物理（橙）・魔法（紫青）・確定（白）の積み上げバー。fill = 枠の幅に対する割合（最大値比）。
struct HUDDeathTypeBar: View, Equatable {
    let physical: Double
    let magic: Double
    let trueDamage: Double
    let fill: Double
    let height: CGFloat

    var body: some View {
        GeometryReader { g in
            let total = physical + magic + trueDamage
            let w = g.size.width * CGFloat(min(1, max(0, fill)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.5))
                if total > 0 && w > 0.5 {
                    HStack(spacing: 0) {
                        segment(HUDDeathStyle.physical, w * CGFloat(physical / total))
                        segment(HUDDeathStyle.magic, w * CGFloat(magic / total))
                        segment(HUDDeathStyle.trueDamage, w * CGFloat(trueDamage / total))
                    }
                    .frame(width: w, alignment: .leading)
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func segment(_ c: Color, _ w: CGFloat) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [c, c.opacity(0.72)], startPoint: .top, endPoint: .bottom))
            .frame(width: max(0, w))
            // 種類の境目（色覚サポート: 色だけに頼らない）
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.black.opacity(0.5)).frame(width: w > 2 ? 1 : 0)
            }
    }
}
