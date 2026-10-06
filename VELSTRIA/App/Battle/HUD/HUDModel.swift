import SwiftUI
import VelstriaCore

// 担当: battle-hud。HUD の状態の中心。
// - controller.hudTick（15Hz）毎に SimState を読み、変化したスナップショットだけを更新する
// - SimEvent を購読して告知・キルフィード・死亡・購入結果・降参投票・試合終了・チュートリアルを進める
// - 操作（スティック・攻撃・スキル照準・購入など）を HeroCommand に変換して controller へ送る

/// 照準中のボタン周りのリング表示（タッチ毎に変わるので HUDModel とは別に観測させる）。
@Observable
@MainActor
final class HUDAimVisual {
    var active = false
    /// 照準を始めたボタンの中心（HUD 座標）。
    var center: CGPoint = .zero
    var drag: CGVector = .zero
    var maxDrag: CGFloat = 84
    var cancelling = false
    var isUltimate = false
}

@Observable
@MainActor
final class HUDModel {
    enum AimSource: Equatable {
        case skill(SkillSlot)
        case spell(Int)
    }

    private struct AimSession {
        var source: AimSource
        var targeting: SkillTargeting
        var spellID: String?
        var start: CGPoint
        var drag: CGVector = .zero
        var ready: Bool
        var aiming: Bool
        var cancelling = false
    }

    private struct Ghost {
        var id: EntityID
        var pos: Vec2
        var team: Team
        var hue: Double
        var heroID: String
        var seenAt: Double
    }

    private struct CampObservation {
        var respawnAt: Double?
    }

    private struct QuickBuyKey: Equatable {
        var gold: Int
        var items: [String]
        var enabled: Bool
    }

    // MARK: 参照

    @ObservationIgnored let controller: BattleController
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var onFinish: ((BattleOutcome) -> Void)?
    @ObservationIgnored let minimap = HUDMinimapBuffer()
    @ObservationIgnored let aimVisual = HUDAimVisual()
    /// ビューが更新する配置（キャンセル領域・照準リングの大きさ）。
    @ObservationIgnored var layout: HUDLayout?

    // MARK: 表示状態（観測）

    private(set) var settings = GameSettings()
    /// 最後にコントローラへ反映した設定のカメラ倍率（設定が変わった時だけ書き戻し、観戦者のピンチ・自動カメラの倍率を潰さない）。
    @ObservationIgnored private var appliedZoomSetting: Double?
    private(set) var top = HUDTopSnapshot()
    private(set) var hero = HUDHeroSnapshot()
    private(set) var vitals = HUDVitals()
    private(set) var skills: [HUDSkillSnapshot] = SkillSlot.actives.map { HUDSkillSnapshot(slot: $0) }
    private(set) var spells: [HUDSpellSnapshot] = [HUDSpellSnapshot(index: 0), HUDSpellSnapshot(index: 1)]
    private(set) var quickBuyItemID: String?
    private(set) var shop = HUDShopState()
    private(set) var minimapVersion = 0
    private(set) var isTacticalMapOpen = false
    private(set) var spectate = HUDSpectateSnapshot()
    private(set) var scoreboard = HUDScoreboardSnapshot()
    private(set) var surrender: HUDSurrenderSnapshot?
    private(set) var canProposeSurrender = false
    private(set) var surrenderAvailableIn: Int?
    private(set) var tutorial: TutorialDirector?
    private(set) var tutorialObjective: Vec2?
    private(set) var banner: HUDBanner?
    private(set) var killFeed: [HUDKillFeedEntry] = []
    private(set) var toast: HUDToast?
    private(set) var levelUpPulse = 0
    private(set) var lastLevelUp = 1
    private(set) var deathInfo: HUDDeathInfo?
    private(set) var endPhase: HUDEndPhase?
    private(set) var isAiming = false
    private(set) var spectatorPaused = false
    private(set) var cameraFollowID: EntityID?
    /// 最初の更新が終わり、描画側の読み込み幕が上がった（それまで HUD は表示せず、操作も受け付けない）。
    var isReady: Bool { hasRefreshed && controller.isPresentationReady }
    private var hasRefreshed = false

    var panel: HUDPanel?
    /// ショップ: nil = おすすめタブ。
    var shopCategory: ItemCategory?
    var shopSelectedItemID: String?
    var shopSelectedSlot: Int?
    var confirmingLeave = false

    // MARK: 入力状態（非観測）

    @ObservationIgnored private var subscription: UUID?
    @ObservationIgnored private(set) var started = false
    @ObservationIgnored private(set) var finished = false
    @ObservationIgnored private var attackTask: Task<Void, Never>?
    @ObservationIgnored private(set) var attackHeld = false
    @ObservationIgnored private var heldAttackButton: AttackButtonSlot?
    @ObservationIgnored private var lastActionAt: TimeInterval = 0
    @ObservationIgnored private var joystickActive = false
    @ObservationIgnored private var joystickVector: CGVector = .zero
    @ObservationIgnored private var lastSentMove: Vec2 = .zero
    @ObservationIgnored private var aimSession: AimSession?
    @ObservationIgnored private var bannerQueue: [HUDBanner] = []
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var endTask: Task<Void, Never>?
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var quickBuyKey: QuickBuyKey?
    @ObservationIgnored private var shopKey: QuickBuyKey?
    @ObservationIgnored private var ghosts: [Ghost] = []
    @ObservationIgnored private var lastMinimapTime: Double = 0
    @ObservationIgnored private var campObservations: [Int: CampObservation] = [:]
    @ObservationIgnored private var surrenderResultUntil: TimeInterval = 0
    @ObservationIgnored private var lastSurrenderTally: (yes: Int, no: Int, needed: Int)?
    @ObservationIgnored private var targetingCache: [SkillTargeting?] = [nil, nil, nil, nil, nil]
    @ObservationIgnored private var lastErrorFeedback: TimeInterval = 0
    /// 画面確認用の状態の再現（HUDDebug から DEBUG ビルドでのみ設定される）。
    @ObservationIgnored var debugForceDeath = false
    @ObservationIgnored var debugForceSurrender = false
    @ObservationIgnored var debugForceLowHP = false

    static let attackRepeatInterval: Duration = .milliseconds(250)
    static let killFeedLifetime: TimeInterval = 7
    static let killFeedMax = 4
    static let bannerDuration: Double = 2.4
    static let endBannerDuration: Double = 2.6
    static let ghostLifetime: Double = 3
    /// 攻撃・スキルの直後はスティックの再送を待つ（前隙を潰さない）。
    static let moveResendDelay: TimeInterval = 0.45

    init(controller: BattleController) {
        self.controller = controller
    }

    var isSpectating: Bool { controller.isSpectating }
    var isTutorial: Bool { controller.launch.config.mode == .tutorial }
    var mode: MatchMode { controller.launch.config.mode }
    var humanTeam: Team? { controller.localTeam }
    /// 操作を受け付けるか。
    var canControl: Bool { !isSpectating && !isTacticalMapOpen && endPhase == nil && !finished && !(tutorial?.isComplete ?? false) }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: 開始・終了

    func start(app: AppModel, onFinish: @escaping (BattleOutcome) -> Void) {
        guard !started else { return }
        started = true
        self.app = app
        self.onFinish = onFinish
        #if DEBUG
        HUDDebug.applySettings(app)
        #endif
        settings = app.profile.settings
        minimap.viewerTeam = controller.viewerTeam
        if isTutorial { tutorial = TutorialDirector() }
        subscription = controller.subscribe { [weak self] events in
            self?.handle(events)
        }
        if let id = controller.humanHeroID, let def = controller.ctx.master.hero(controller.state.unit(id)?.hero?.heroID ?? "") {
            for slot in SkillSlot.actives {
                if let sk = controller.ctx.master.skill(hero: def.heroID, slot: slot) {
                    targetingCache[slot.rawValue] = SkillCatalog.targeting(for: sk, hero: def)
                }
            }
        }
        if isSpectating, case .followUnit(let id) = controller.cameraMode { cameraFollowID = id }
        refresh()
        hasRefreshed = true
        #if DEBUG
        HUDDebug.apply(self)
        #endif
    }

    func stop() {
        setTacticalMap(open: false)
        if let subscription { controller.unsubscribe(subscription) }
        subscription = nil
        attackReleased()
        bannerTask?.cancel()
        toastTask?.cancel()
        endTask?.cancel()
        controller.aim = nil
    }

    /// 設定変更（ポーズメニューのクイック設定など）を反映する。
    func syncSettings() {
        guard let app else { return }
        let s = app.profile.settings
        if s != settings {
            settings = s
            quickBuyKey = nil
        }
        if appliedZoomSetting != s.cameraZoom {
            appliedZoomSetting = s.cameraZoom
            if controller.cameraZoom != s.cameraZoom { controller.cameraZoom = s.cameraZoom }
        }
    }

    func updateSetting<T: Equatable>(_ keyPath: WritableKeyPath<GameSettings, T>, _ value: T) {
        guard let app, app.profile.settings[keyPath: keyPath] != value else { return }
        app.profile.settings[keyPath: keyPath] = value
        syncSettings()
    }

    // MARK: 15Hz 更新

    func refresh() {
        guard started else { return }
        let s = controller.state
        let ctx = controller.ctx
        let t = now
        syncSettings()

        refreshTop(s)
        if let hi = controller.humanIndex {
            refreshHero(s, ctx, hi, time: t)
        }
        if tutorial?.isComplete == true { setTacticalMap(open: false) }
        refreshMinimap(s, ctx)
        if isSpectating { refreshSpectate(s) }
        if panel == .scoreboard { refreshScoreboard(s) }
        if panel == .shop { refreshShop(s, ctx, force: false) }
        refreshSurrender(s, ctx, time: t)
        expireFeed(time: t)
        if aimSession?.aiming == true { updateAimIndicator() }
        if controller.isEnded && endPhase == nil && !finished, let reason = s.endReason, reason != .aborted {
            beginEnd(winner: s.winner, reason: reason)
        }
    }

    private func refreshTop(_ s: SimState) {
        var top = HUDTopSnapshot()
        top.blueKills = s.teams[Team.blue.rawValue].kills
        top.redKills = s.teams[Team.red.rawValue].kills
        top.blueTowers = s.teams[Team.blue.rawValue].towersDestroyed
        top.redTowers = s.teams[Team.red.rawValue].towersDestroyed
        top.seconds = Int(s.time)
        if let hi = controller.humanIndex, let h = s.units[hi].hero {
            top.kills = h.score.kills
            top.deaths = h.score.deaths
            top.assists = h.score.assists
            top.creepScore = h.score.creepScore
        }
        if top != self.top { self.top = top }
    }

    /// ヒーローパネルの表示値を作る（純粋関数: 任意のユニット添字。副作用なし）。
    /// プレイヤーの HUD（refreshHero）と観戦のヒーロー詳細（buildHeroCard）が共用する。
    /// targeting はスキル枠ごとの照準のキャッシュ（SkillSlot.rawValue 添字。無ければマスターから作る）。
    static func buildHeroPanel(_ s: SimState, _ ctx: SimContext, index hi: Int, targeting: [SkillTargeting?] = [],
                               canLevel: (SkillSlot) -> Bool = { _ in true }) -> HUDHeroPanelBuild? {
        guard s.units.indices.contains(hi) else { return nil }
        let u = s.units[hi]
        guard let h = u.hero else { return nil }
        var b = HUDHeroPanelBuild()
        var snap = HUDHeroSnapshot()
        snap.heroID = h.heroID
        snap.role = h.role
        snap.level = h.level
        snap.xpProgress = (HeroGrowth.levelProgress(h) * 50).rounded() / 50
        var v = HUDVitals()
        v.hp = u.hp.rounded()
        v.maxHP = u.stats.maxHP.rounded()
        v.shield = u.totalShield.rounded()
        v.resource = u.resource.rounded()
        v.maxResource = u.stats.maxResource.rounded()
        v.resourceKind = h.resourceKind
        b.vitals = v
        snap.gold = Int(h.gold)
        snap.items = h.items
        snap.isDead = h.isDead
        snap.respawn = (h.respawnTimer * 10).rounded(.up) / 10
        snap.skillPoints = h.skillPoints
        if let ch = h.channel {
            snap.channel = HUDChannel(kind: ch.kind, remaining: (ch.remaining * 20).rounded() / 20, total: ch.total)
        }
        snap.statuses = statusIcons(u)
        b.hero = snap

        // スキル
        let def = ctx.master.hero(h.heroID)
        for (k, slot) in SkillSlot.actives.enumerated() {
            guard let sk = ctx.master.skill(hero: h.heroID, slot: slot) else { continue }
            var sn = HUDSkillSnapshot(slot: slot)
            sn.skillID = sk.skillID
            let cached = targeting.indices.contains(slot.rawValue) ? targeting[slot.rawValue] : nil
            let t = cached ?? def.map { SkillCatalog.targeting(for: sk, hero: $0) }
                ?? SkillTargeting(archetype: .groundAoE, aim: .point, range: sk.range, radius: sk.radius)
            sn.targeting = t
            sn.archetype = t.archetype
            sn.rank = h.rank(slot)
            let cd = h.cooldown(slot)
            sn.cooldown = cd > 0 ? (cd * 10).rounded(.up) / 10 : 0
            sn.cooldownTotal = SkillSystem.cooldown(for: sk, rank: max(1, sn.rank), cdr: u.stats.cooldownReduction)
            sn.cost = SkillSystem.cost(for: sk, resource: h.resourceKind)
            sn.castable = SkillSystem.canCast(s, ctx, heroIndex: hi, slot: slot)
            sn.affordable = u.resource + 0.5 >= sn.cost
            sn.silenced = u.has(.silence)
            sn.canLevel = SkillLeveling.canLevel(h, slot: slot) && canLevel(slot)
            b.skills[k] = sn
        }

        // スペル
        for k in 0..<min(2, h.spells.count) {
            var sp = HUDSpellSnapshot(index: k)
            sp.spellID = h.spells[k]
            let cd = k < h.spellCooldowns.count ? h.spellCooldowns[k] : 0
            sp.cooldown = cd > 0 ? (cd * 10).rounded(.up) / 10 : 0
            sp.cooldownTotal = ctx.master.spell(sp.spellID)?.cooldownSec ?? 60
            sp.castable = SpellSystem.canCast(s, ctx, heroIndex: hi, spellIndex: k)
            b.spells[k] = sp
        }
        return b
    }

    /// 観戦: 任意のヒーローの詳細（純粋関数）。ownerID はリプレイの持ち主（強調表示）。
    static func buildHeroCard(_ s: SimState, _ ctx: SimContext, index hi: Int, ownerID: EntityID?) -> HUDHeroCardSnapshot? {
        guard let panel = buildHeroPanel(s, ctx, index: hi, canLevel: { _ in false }), let h = s.units[hi].hero else { return nil }
        let u = s.units[hi]
        var card = HUDHeroCardSnapshot(id: u.id, team: u.team)
        card.isOwner = ownerID == u.id
        card.panel = panel
        card.kills = h.score.kills
        card.deaths = h.score.deaths
        card.assists = h.score.assists
        card.creepScore = h.score.creepScore
        card.netWorth = netWorth(h)
        card.damageDealt = Int(h.score.damageToHeroes.rounded())
        card.damageTaken = Int(h.score.damageTaken.rounded())
        card.healing = Int((h.score.healingDone + h.score.shieldingDone).rounded())
        card.towerDamage = Int(h.score.towerDamage.rounded())
        return card
    }

    /// 所持 Gold + 装備に使った Gold（観戦者のスコアボード・ヒーロー詳細）。
    static func netWorth(_ h: HeroData) -> Int {
        Int((h.gold + h.itemInvested.reduce(0, +)).rounded())
    }

    private func refreshHero(_ s: SimState, _ ctx: SimContext, _ hi: Int, time: TimeInterval) {
        let u = s.units[hi]
        guard let h = u.hero,
              var b = Self.buildHeroPanel(s, ctx, index: hi, targeting: targetingCache,
                                          canLevel: { self.tutorialAllowsLevel($0) }) else { return }
        if debugForceLowHP { b.vitals.hp = (b.vitals.maxHP * 0.22).rounded() }
        if b.vitals != vitals { vitals = b.vitals }
        var snap = b.hero
        if debugForceDeath {
            snap.isDead = true
            snap.respawn = 12.4
            if deathInfo == nil {
                deathInfo = HUDDeathInfo(killerHeroID: "H005", killerKind: .hero, killerTeam: .red)
            }
        }
        if snap != hero { hero = snap }
        if b.skills != skills { skills = b.skills }
        if b.spells != spells { spells = b.spells }

        // おすすめ購入（Gold・所持品が変わった時だけ計算）
        let key = QuickBuyKey(gold: Int(h.gold), items: h.items, enabled: settings.showRecommendedItems)
        if key != quickBuyKey {
            quickBuyKey = key
            let pick = HUDShopLogic.quickBuy(hero: h, ctx: ctx, customBuild: customBuild(for: h.heroID),
                                             enabled: settings.showRecommendedItems || isTutorial)
            if pick != quickBuyItemID { quickBuyItemID = pick }
        }

        if !h.isDead && !debugForceDeath && deathInfo != nil { deathInfo = nil }

        // チュートリアル
        if var tut = tutorial {
            tut.observe(heroPosition: u.pos, alive: u.isAlive && !h.isDead, skill1Rank: h.rank(.skill1))
            if tut != tutorial { tutorial = tut }
            let objective = tut.objective(map: ctx.map, dummySpots: s.world.dummySpots)
            if objective != tutorialObjective { tutorialObjective = objective }
        }

        // スティックを押したまま攻撃・スキルで止まった場合は移動を再開する
        if joystickActive, lastSentMove != .zero, !attackHeld, u.isAlive, !h.isDead,
           time - lastActionAt > Self.moveResendDelay {
            var moving = false
            if case .direction = u.moveIntent { moving = true }
            if !moving { sendMove(lastSentMove, raw: joystickVector, force: true) }
        }
    }

    /// 状態アイコン（同じ種類はまとめる。弱体を先に、最大 6 個）。
    static func statusIcons(_ u: VelstriaCore.Unit) -> [HUDStatusIcon] {
        var icons: [HUDStatusIcon] = []
        for st in u.statuses where st.remaining > 0 {
            // 練習用人形の常時可視化などの長時間の内部状態は出さない
            if st.kind == .revealed && st.duration >= 30 { continue }
            let rem = (st.remaining * 10).rounded(.up) / 10
            if let k = icons.firstIndex(where: { $0.kind == st.kind }) {
                if rem > icons[k].remaining {
                    icons[k].remaining = rem
                    icons[k].duration = st.duration
                }
            } else {
                icons.append(HUDStatusIcon(id: st.kind.rawValue, kind: st.kind, remaining: rem, duration: st.duration,
                                           isBuff: HUDSymbols.isBuff(st.kind)))
            }
        }
        icons.sort { a, b in
            if a.isBuff != b.isBuff { return !a.isBuff }
            return a.kind.rawValue < b.kind.rawValue
        }
        return Array(icons.prefix(6))
    }

    private func customBuild(for heroID: String) -> [String]? {
        guard let build = app?.profile.customBuilds[heroID], !build.isEmpty else { return nil }
        return build
    }

    private func tutorialAllowsLevel(_ slot: SkillSlot) -> Bool {
        guard let tutorial, !tutorial.isComplete else { return true }
        // 習得手順ではスキル1 だけを示す（別のスキルに振って詰まらないように）
        if tutorial.step.rawValue <= TutorialStep.learnSkill.rawValue { return slot == .skill1 && tutorial.step == .learnSkill }
        return true
    }

    // MARK: ショップ

    private func refreshShop(_ s: SimState, _ ctx: SimContext, force: Bool) {
        guard let hi = controller.humanIndex, let h = s.units[hi].hero else { return }
        let key = QuickBuyKey(gold: Int(h.gold), items: h.items, enabled: true)
        guard force || key != shopKey else { return }
        shopKey = key
        let st = HUDShopLogic.state(hero: h, ctx: ctx, customBuild: customBuild(for: h.heroID))
        if st != shop { shop = st }
        if shopSelectedItemID == nil { shopSelectedItemID = st.next ?? st.path.first(where: { !$0.owned })?.itemID }
        if let slot = shopSelectedSlot, slot >= h.items.count { shopSelectedSlot = nil }
    }

    // MARK: ミニマップ

    func refreshMinimap(_ s: SimState, _ ctx: SimContext) {
        let viewer = controller.viewerTeam
        // リプレイは記録した本人を「自分」として強調する。注目の輪は追従中のユニット（自動カメラ・一時停止中の切り替えも即座に）
        let humanID = controller.humanHeroID ?? controller.ownerHeroID
        let focusID = isSpectating ? controller.presentationFocusID : cameraFollowID
        if s.time < lastMinimapTime || minimap.viewerTeam != viewer {
            ghosts.removeAll(keepingCapacity: true)
            campObservations.removeAll(keepingCapacity: true)
        }
        lastMinimapTime = s.time
        minimap.units.removeAll(keepingCapacity: true)
        minimap.heroes.removeAll(keepingCapacity: true)
        minimap.structures.removeAll(keepingCapacity: true)
        minimap.camps.removeAll(keepingCapacity: true)
        minimap.colorblind = settings.colorblindMode
        minimap.viewerTeam = viewer
        minimap.mapSize = ctx.map.size
        minimap.vision = s.vision
        var humanDot: HUDMinimapBuffer.Dot?
        for i in s.units.indices {
            let u = s.units[i]
            let displayedPosition = Vec2.lerp(u.prevPos, u.pos, Double(Float(controller.interpolationAlpha)))
            switch u.kind {
            case .tower, .core:
                minimap.structures.append(.init(pos: u.pos, team: u.team, alive: u.isAlive, isCore: u.kind == .core,
                                                hpFraction: min(1, max(0, u.hp / max(1, u.stats.maxHP)))))
            case .hero:
                guard let h = u.hero else { continue }
                let visible = viewer.map { s.isVisible(i, to: $0) } ?? true
                let hue = Theme.heroHue(h.heroID)
                if !u.isAlive || h.isDead {
                    ghosts.removeAll { $0.id == u.id }
                    continue
                }
                if visible {
                    let dot = HUDMinimapBuffer.Dot(pos: displayedPosition, team: u.team, kind: .hero, hue: hue,
                                                   isHuman: u.id == humanID, isFocus: u.id == focusID, alpha: 1,
                                                   heroID: h.heroID, facing: Vec2.fromAngle(u.facing),
                                                   visionRadius: u.stats.sightRange > 0 ? u.stats.sightRange : Balance.heroSight)
                    if dot.isHuman { humanDot = dot } else { minimap.heroes.append(dot) }
                    if let viewer, u.team != viewer {
                        if let k = ghosts.firstIndex(where: { $0.id == u.id }) {
                            ghosts[k].pos = displayedPosition
                            ghosts[k].seenAt = s.time
                        } else {
                            ghosts.append(Ghost(id: u.id, pos: displayedPosition, team: u.team, hue: hue,
                                                heroID: h.heroID, seenAt: s.time))
                        }
                    }
                } else if let k = ghosts.firstIndex(where: { $0.id == u.id }) {
                    let age = s.time - ghosts[k].seenAt
                    if age <= Self.ghostLifetime {
                        let g = ghosts[k]
                        minimap.heroes.append(.init(pos: g.pos, team: g.team, kind: .hero, hue: g.hue, isHuman: false,
                                                    isFocus: false, alpha: max(0.2, 0.55 * (1 - age / Self.ghostLifetime)),
                                                    heroID: g.heroID))
                    } else {
                        ghosts.remove(at: k)
                    }
                }
            case .minion, .monster, .dummy:
                guard u.isAlive else { continue }
                let visible = viewer.map { s.isVisible(i, to: $0) } ?? true
                guard visible else { continue }
                minimap.units.append(.init(pos: displayedPosition, team: u.team, kind: u.kind, hue: 0, isHuman: false,
                                           isFocus: false, alpha: 1))
            }
        }
        if let humanDot { minimap.heroes.append(humanDot) }
        let camps = ctx.map.camps
        for (k, camp) in camps.enumerated() {
            let isBoss = camp.kind == .astralWyrm || camp.kind == .ancientColossus
            let observed = viewer.map { s.vision.isLit(camp.pos, for: $0) } ?? true
            var known = campObservations[k] ?? CampObservation(respawnAt: camp.firstSpawn)
            if isBoss || observed {
                known.respawnAt = k < s.world.campRespawnAt.count ? s.world.campRespawnAt[k] : camp.firstSpawn
            } else if let at = known.respawnAt, at <= s.time {
                // An unseen ordinary camp retains its last-known status; hidden clears must not leak.
                known.respawnAt = nil
            }
            campObservations[k] = known
            let nextSpawn = known.respawnAt
            let alive = nextSpawn == nil
            minimap.camps.append(.init(pos: camp.pos, alive: alive,
                                       isBoss: isBoss,
                                       kind: camp.kind, respawnRemaining: nextSpawn.map { max(0, $0 - s.time) }))
        }
        refreshMinimapCamera()
        minimapVersion &+= 1
    }

    /// Called by the camera clock as well as simulation refreshes, including paused spectators.
    func refreshMinimapCamera() {
        let projection = HUDMinimapProjection(size: 1, mapSize: controller.ctx.map.size)
        let polygon = projection.clippedPolygon(controller.renderedCameraViewport)
        guard polygon != minimap.viewportPolygon else { return }
        minimap.viewportPolygon = polygon
        minimapVersion &+= 1
    }

    func minimapDragged(to p: Vec2) {
        guard p.x.isFinite, p.y.isFinite else { return }
        let mapSize = controller.ctx.map.size
        controller.cameraMode = .free(Vec2(min(mapSize, max(0, p.x)), min(mapSize, max(0, p.y))))
        if isSpectating { cameraFollowID = nil }
    }

    func minimapReleased() {
        guard !isSpectating else { return }
        // 死亡中に味方を見ていたなら、その味方へ戻る
        if let ally = cameraFollowID, canFollowAsPlayer(ally) {
            controller.cameraMode = .followUnit(ally)
        } else {
            cameraFollowID = nil
            controller.cameraMode = .followHero
        }
    }

    func setTacticalMap(open: Bool) {
        guard open != isTacticalMapOpen else { return }
        if open {
            guard endPhase == nil, !finished, tutorial?.isComplete != true else { return }
            closePanel()
            cancelAim()
            attackReleased()
            joystickEnded()
            isTacticalMapOpen = true
        } else {
            isTacticalMapOpen = false
            minimapReleased()
        }
    }

    // MARK: 観戦

    /// 観戦者だけが使う状態（情報パネル・観戦メニュー・シネマ表示・再生バーなど）。
    @ObservationIgnored let spectator = HUDSpectatorState()

    private func refreshSpectate(_ s: SimState) {
        var snap = HUDSpectateSnapshot()
        let owner = controller.ownerHeroID
        for team in Team.players {
            for i in s.heroIndices(team: team) {
                let u = s.units[i]
                guard let h = u.hero else { continue }
                let ult = h.rank(.ultimate) > 0 && h.cooldown(.ultimate) <= 0 && !h.isDead
                snap.heroes.append(HUDSpectateHero(id: u.id, heroID: h.heroID, team: team, level: h.level,
                                                   hpRatio: (u.hpRatio * 40).rounded() / 40, isDead: h.isDead,
                                                   respawn: h.respawnTimer.rounded(.up), ultReady: ult,
                                                   isOwner: u.id == owner))
            }
        }
        let blue = EconomyRewards.teamGoldEarned(s, team: .blue)
        let red = EconomyRewards.teamGoldEarned(s, team: .red)
        snap.blueGold = Int(blue / 100) * 100
        snap.redGold = Int(red / 100) * 100
        snap.goldDiff = Int(((blue - red) / 100).rounded()) * 100
        // 再生位置は spectator.transport（15Hz で変わる値をヒーローの並びと分けて観測させる）
        if snap != spectate { spectate = snap }
        spectator.refresh(controller: controller, state: s, camps: minimap.camps, paused: spectatorPaused)
    }

    /// カメラの追従先・観戦者の視界が変わった（自動カメラ・ヒーロー切り替え・ミニマップ）。
    /// 一時停止中は 15Hz の更新が止まるので、注目の輪・ミニマップ・ヒーロー詳細をここで作り直す。
    func cameraModeChanged() {
        guard started, isSpectating, controller.seekingToTick == nil else { return }
        if controller.isPaused || controller.isEnded { refresh() }
    }

    /// シークが始まった・終わった（シーク中は 15Hz の更新が止まるので、再生バーの「移動中」をここで出す）。
    func seekStateChanged() {
        guard started, isSpectating else { return }
        spectator.refresh(controller: controller, state: controller.state, camps: minimap.camps, paused: spectatorPaused)
    }

    // MARK: 観戦の操作（再生・視界・パネル）

    /// シークバー・出来事の一覧から（オフラインの観戦・リプレイ）。終わった後に戻ると再生を再開する。
    func spectatorSeek(toTick tick: Int) {
        guard isSpectating, controller.isSeekable else { return }
        reopenAfterEndForSeek()
        controller.requestSeek(toTick: tick)
        seekStateChanged()
        app?.haptics.selection()
    }

    /// ±秒のシーク（−10 / +10 / −30 / +30）。
    func spectatorSkip(seconds: Double) {
        guard isSpectating, controller.isSeekable else { return }
        if seconds < 0 { reopenAfterEndForSeek() }
        controller.seek(bySeconds: seconds)
        seekStateChanged()
        app?.haptics.selection()
    }

    /// 最初から見る（終わった後の「もう一度見る」も）。
    func spectatorRestart() {
        spectatorSeek(toTick: 0)
    }

    /// 次の見どころ（大きな出来事の少し前）へ。
    func spectatorNextFight() {
        guard let target = spectator.transport.nextFightTick else { return }
        spectatorSeek(toTick: target)
    }

    /// 一時停止中のコマ送り（1 tick）。
    func spectatorStep() {
        guard isSpectating, controller.isSeekable else { return }
        if !controller.isPaused {
            spectatorPaused = true
            controller.isPaused = true
        }
        controller.stepTicks(1)
        app?.haptics.selection()
    }

    /// 再生 / 一時停止（終わっていれば最初から）。
    func spectatorPlayPause() {
        if spectator.transport.isEnded && controller.isSeekable {
            spectatorRestart()
        } else {
            toggleSpectatorPause()
        }
    }

    /// 速度を順に切り替える（狭い画面の 1 ボタン）。
    func cycleSpectatorSpeed() {
        let speeds = BattleController.spectatorSpeeds
        let i = speeds.firstIndex(of: controller.speed) ?? 0
        setSpeed(speeds[(i + 1) % speeds.count])
    }

    /// 観戦者の視界（nil = 全体、.blue / .red = そのチームの視界）。
    func setSpectatorVision(_ team: Team?) {
        guard isSpectating, controller.spectatorVision != team else { return }
        controller.spectatorVision = team
        // ミニマップの霧・最後に見えた位置を作り直す（一時停止中も）
        refreshMinimap(controller.state, controller.ctx)
        app?.haptics.selection()
    }

    /// 自動カメラのオン/オフ。
    func toggleSpectatorDirector() {
        guard isSpectating else { return }
        controller.spectatorDirectorEnabled.toggle()
        app?.haptics.selection()
    }

    /// シネマ表示（HUD を隠して映像だけ。戻すボタンだけ残す）。
    func setCinematic(_ on: Bool) {
        guard isSpectating, spectator.isCinematic != on else { return }
        if on {
            spectator.isDrawerOpen = false
            setTacticalMap(open: false)
        }
        spectator.isCinematic = on
        app?.haptics.selection()
    }

    /// 情報パネルを開く/閉じる（同じパネルなら閉じる）。
    func toggleSpectatorPanel(_ p: HUDSpectatorState.Panel) {
        guard isSpectating else { return }
        spectator.panel = spectator.panel == p ? nil : p
        spectator.invalidatePanels()
        app?.audio.play(.uiTap)
        refreshSpectatorPanels()
    }

    func toggleSpectatorDrawer() {
        guard isSpectating else { return }
        spectator.isDrawerOpen.toggle()
        app?.audio.play(spectator.isDrawerOpen ? .uiTap : .uiBack)
    }

    func toggleObjectiveTimers() {
        guard isSpectating else { return }
        spectator.showsObjectives.toggle()
        refreshSpectatorPanels()
    }

    /// 観戦: ヒーローを選ぶ（追従中をもう一度選ぶとヒーロー詳細を開閉する）。
    func spectatorSelectHero(_ id: EntityID) {
        guard isSpectating else { return }
        if spectator.focusID == id && cameraFollowID == id {
            toggleSpectatorPanel(.hero)
            return
        }
        follow(id)
        if spectator.panel == .hero { refreshSpectatorPanels() }
    }

    /// 前 / 次のヒーローへ（ブルー 1〜5 → レッド 1〜5 の順。倒れているヒーローは飛ばす）。
    func followAdjacentHero(_ step: Int) {
        guard isSpectating,
              let id = HUDSpectatorState.adjacentHero(from: spectator.focusID ?? spectator.lastFocusID, step: step,
                                                      heroes: spectate.heroes) else { return }
        follow(id)
    }

    /// 自由カメラから最後に追従していたヒーローへ戻る。
    func refollowLastHero() {
        guard isSpectating else { return }
        if let id = spectator.lastFocusID ?? spectate.heroes.first?.id { follow(id) }
    }

    /// 出来事の一覧から: シークできればその少し前へ、できなければ（オンラインの観戦席）カメラを向ける。
    func jumpToEvent(_ e: HUDEventLogEntry) {
        guard isSpectating else { return }
        if controller.isSeekable {
            spectatorSeek(toTick: max(0, e.tick - 90))
            if let id = e.focusID { follow(id) }
        } else if let id = e.focusID, controller.state.unit(id)?.hero?.isDead == false {
            follow(id)
        } else if let pos = e.pos {
            minimapDragged(to: pos)
        }
    }

    /// 情報パネル・目標タイマーを今すぐ作り直す（開いた直後・一時停止中）。
    private func refreshSpectatorPanels() {
        guard started, isSpectating, controller.seekingToTick == nil else { return }
        spectator.refresh(controller: controller, state: controller.state, camps: minimap.camps, paused: spectatorPaused)
    }

    /// 試合が終わった後にシークで戻る: 終了演出を閉じ、BGM と一時停止の状態を戻す（以後は試合中と同じ）。
    private func reopenAfterEndForSeek() {
        guard endPhase != nil, !finished else { return }
        endTask?.cancel()
        endTask = nil
        endPhase = nil
        controller.isPaused = spectatorPaused
        app?.audio.playMusic(.battle)
    }

    /// 追従先を変える。観戦者は誰でも、プレイヤーは自分が死亡中に味方のヒーローだけ（敵を追うと霧の向こうが見えてしまう）。
    /// 自分のヒーロー（または不可な対象）を指定したら自分の追従に戻る。
    func follow(_ id: EntityID) {
        if isSpectating {
            cameraFollowID = id
            controller.cameraMode = .followUnit(id)
        } else if canFollowAsPlayer(id) {
            cameraFollowID = id
            controller.cameraMode = .followUnit(id)
        } else {
            cameraFollowID = nil
            controller.cameraMode = .followHero
        }
        app?.haptics.selection()
    }

    /// プレイヤーが（死亡中に）追従してよい味方のヒーローか。
    func canFollowAsPlayer(_ id: EntityID) -> Bool {
        guard !isSpectating, let hi = controller.humanIndex, let me = controller.state.units[hi].hero, me.isDead,
              id != controller.humanHeroID, let u = controller.state.unit(id), u.kind == .hero,
              u.team == controller.localTeam else { return false }
        return true
    }

    /// 死亡中に追従できる味方（ポジション順）。生きている味方を先に。
    var followableAllies: [EntityID] {
        guard !isSpectating, let team = controller.localTeam else { return [] }
        let s = controller.state
        let allies = s.heroIndices(team: team).filter { s.units[$0].id != controller.humanHeroID }
        let alive = allies.filter { s.units[$0].hero?.isDead == false }
        let dead = allies.filter { s.units[$0].hero?.isDead != false }
        return (alive + dead).map { s.units[$0].id }
    }

    func setSpeed(_ speed: Double) {
        controller.speed = speed
        app?.haptics.selection()
    }

    func toggleSpectatorPause() {
        guard endPhase == nil, !controller.isOnline else { return }
        spectatorPaused.toggle()
        controller.isPaused = spectatorPaused
        app?.haptics.selection()
        refreshSpectatorPanels()
    }

    // MARK: スコアボード

    private func refreshScoreboard(_ s: SimState) {
        var snap = HUDScoreboardSnapshot()
        snap.blueKills = s.teams[Team.blue.rawValue].kills
        snap.redKills = s.teams[Team.red.rawValue].kills
        snap.blueTowers = s.teams[Team.blue.rawValue].towersDestroyed
        snap.redTowers = s.teams[Team.red.rawValue].towersDestroyed
        snap.blueWyrms = s.teams[Team.blue.rawValue].wyrmKills
        snap.redWyrms = s.teams[Team.red.rawValue].wyrmKills
        snap.blueColossi = s.teams[Team.blue.rawValue].colossusKills
        snap.redColossi = s.teams[Team.red.rawValue].colossusKills
        snap.blueObjectives = snap.blueWyrms + snap.blueColossi
        snap.redObjectives = snap.redWyrms + snap.redColossi
        snap.seconds = Int(s.time)
        let ally = humanTeam
        // 強調するのは自分だけ（オンラインでは人間が複数いる）。リプレイは記録した本人
        let me = controller.humanHeroID ?? controller.ownerHeroID
        let focus = isSpectating ? controller.presentationFocusID : nil
        for team in Team.players {
            var rows: [HUDScoreRow] = []
            for i in s.heroIndices(team: team) {
                let u = s.units[i]
                guard let h = u.hero else { continue }
                let showCooldowns = ally == nil || ally == team
                var row = HUDScoreRow(id: u.id, heroID: h.heroID, name: h.displayName, team: team,
                                      isHuman: u.id == me, level: h.level, kills: h.score.kills,
                                      deaths: h.score.deaths, assists: h.score.assists, creepScore: h.score.creepScore,
                                      items: h.items, spells: h.spells,
                                      spellCooldowns: showCooldowns ? h.spellCooldowns.map { $0.rounded(.up) } : nil,
                                      isDead: h.isDead, respawn: h.respawnTimer.rounded(.up))
                if isSpectating {
                    // 観戦者だけの列（プレイヤーに相手の所持 Gold は見せない）
                    row.netWorth = Self.netWorth(h) / 100 * 100
                    row.damage = Int(h.score.damageToHeroes / 100) * 100
                    row.isFocus = u.id == focus
                }
                rows.append(row)
            }
            if team == .blue { snap.blue = rows } else { snap.red = rows }
        }
        if snap != scoreboard { scoreboard = snap }
    }

    /// 観戦: スコアボードの行をタップ → そのヒーローを追従してスコアボードを閉じる。
    func scoreboardRowTapped(_ id: EntityID) {
        guard isSpectating else { return }
        follow(id)
        closePanel()
    }

    // MARK: 降参（UI031）

    private func refreshSurrender(_ s: SimState, _ ctx: SimContext, time: TimeInterval) {
        if debugForceSurrender {
            let snap = HUDSurrenderSnapshot(yes: 2, no: 1, needed: 3, total: 5, secondsLeft: 11, myVote: nil, passed: nil)
            if surrender != snap { surrender = snap }
            return
        }
        guard !isSpectating, MatchFlowSystem.surrenderEnabled(ctx), let team = humanTeam else { return }
        let can = MatchFlowSystem.canProposeSurrender(s, ctx, team: team)
        if can != canProposeSurrender { canProposeSurrender = can }
        let wait: Int? = can || s.surrender.isVoting(team) ? nil
            : Int((s.surrender.nextAllowed[team.rawValue] - s.time).rounded(.up))
        if wait != surrenderAvailableIn { surrenderAvailableIn = wait }

        if s.surrender.isVoting(team) {
            let tally = MatchFlowSystem.tally(s, team: team)
            let deadline = s.surrender.voteDeadline[team.rawValue] ?? s.time
            var snap = HUDSurrenderSnapshot()
            snap.yes = tally.yes
            snap.no = tally.no
            snap.needed = tally.needed
            snap.total = tally.yes + tally.no + tally.pending
            snap.secondsLeft = max(0, Int((deadline - s.time).rounded(.up)))
            snap.myVote = controller.humanIndex.flatMap { s.units[$0].hero?.surrenderVote }
            if snap != surrender { surrender = snap }
        } else if var snap = surrender {
            if snap.passed == nil {
                // 投票終了（最後の集計イベントで結果を表示）
                let final = lastSurrenderTally
                snap.yes = final?.yes ?? snap.yes
                snap.no = final.map { $0.no } ?? (snap.total - snap.yes)
                snap.passed = snap.yes >= snap.needed
                snap.secondsLeft = 0
                surrender = snap
                surrenderResultUntil = time + 3
            } else if time > surrenderResultUntil {
                surrender = nil
                lastSurrenderTally = nil
            }
        }
    }

    func proposeSurrender() {
        guard canProposeSurrender else { return }
        resume()
        controller.send(.surrenderVote(yes: true))
        app?.audio.play(.uiConfirm)
    }

    func voteSurrender(_ yes: Bool) {
        controller.send(.surrenderVote(yes: yes))
        app?.audio.play(.uiTap)
        app?.haptics.selection()
    }

    // MARK: イベント

    func handle(_ events: [SimEvent]) {
        let humanID = controller.humanHeroID
        var dummyIDs: [EntityID] = []
        if tutorial != nil { dummyIDs = controller.sim.state.world.dummyIDs.compactMap { $0 } }
        for e in events {
            switch e {
            case .announcement(let a):
                if let b = makeBanner(a) { enqueueBanner(b) }
            case .heroKilled(let k):
                addKillFeed(k, humanID: humanID)
            case .unitDied(let unitID, .hero, _, let killerID, _):
                if unitID == humanID {
                    let killer = controller.sim.state.unit(killerID)
                    deathInfo = HUDDeathInfo(killerHeroID: killer?.hero?.heroID, killerKind: killer?.kind,
                                             killerTeam: killer?.team)
                    cancelAim()
                }
            case .levelUp(let heroID, let level):
                if heroID == humanID {
                    lastLevelUp = level
                    levelUpPulse &+= 1
                }
            case .purchaseFailed(let heroID, _, let reason):
                if heroID == humanID {
                    showToast(HUDText.purchaseFailure(reason), symbol: "exclamationmark.circle.fill", isError: true)
                }
            case .itemPurchased(let heroID, let itemID):
                if heroID == humanID {
                    if let item = controller.ctx.master.item(itemID) {
                        showToast(L("\(MasterText.item(item)) を購入", "Bought \(MasterText.item(item))"),
                                  symbol: "bag.fill", isError: false)
                    }
                    quickBuyKey = nil
                }
            case .itemSold(let heroID, let itemID, let refund):
                if heroID == humanID {
                    shopSelectedSlot = nil
                    if let item = controller.ctx.master.item(itemID) {
                        showToast(L("\(MasterText.item(item)) を売却 +\(Int(refund)) Gold",
                                    "Sold \(MasterText.item(item)) +\(Int(refund)) gold"),
                                  symbol: "cart.fill", isError: false)
                    }
                    quickBuyKey = nil
                }
            case .surrenderVote(let team, let yes, let no, let needed):
                if team == humanTeam { lastSurrenderTally = (yes, no, needed) }
            case .respawned(let heroID, _):
                if heroID == humanID {
                    deathInfo = nil
                    // 復活したら味方の追従をやめて自分に戻る
                    if !isSpectating, cameraFollowID != nil {
                        cameraFollowID = nil
                        controller.cameraMode = .followHero
                    }
                }
            case .matchEnded(let winner, let reason):
                if reason != .aborted { beginEnd(winner: winner, reason: reason) }
            default:
                break
            }
            if var tut = tutorial, let humanID {
                let previousStep = tut.step
                tut.handle(e, humanID: humanID, dummyIDs: dummyIDs)
                if previousStep.rawValue < TutorialStep.destroyTower.rawValue,
                   tut.step.rawValue >= TutorialStep.destroyTower.rawValue {
                    controller.send(.removeTutorialDummies)
                }
                if tut != tutorial { tutorial = tut }
            }
        }
    }

    private func makeID() -> Int {
        nextID &+= 1
        return nextID
    }

    private func heroID(_ id: EntityID?) -> String? { controller.sim.state.unit(id)?.hero?.heroID }

    private func isAlly(_ team: Team) -> Bool { humanTeam.map { $0 == team } ?? (team == .blue) }

    func makeBanner(_ a: Announcement) -> HUDBanner? {
        let viewer = humanTeam
        func tone(for team: Team) -> HUDBanner.Tone {
            guard let viewer else { return team == .blue ? .ally : .enemy }
            return team == viewer ? .ally : .enemy
        }
        func killerTone(_ id: EntityID) -> HUDBanner.Tone {
            tone(for: controller.sim.state.unit(id)?.team ?? .neutral)
        }
        switch a {
        case .matchStart:
            return HUDBanner(id: makeID(), tone: .neutral, title: L("戦闘開始", "Battle Start"),
                             subtitle: isTutorial || mode == .practice ? nil : L("敵の Star Core を破壊せよ", "Destroy the enemy Star Core"),
                             symbol: "flag.fill", priority: 1)
        case .minionsSpawned:
            return HUDBanner(id: makeID(), tone: .neutral, title: L("ミニオン出撃", "Minions Have Spawned"), subtitle: nil,
                             symbol: "person.3.fill", priority: 0)
        case .firstBlood(let killerID, let victimID):
            return HUDBanner(id: makeID(), tone: killerTone(killerID), title: L("ファーストブラッド", "First Blood"),
                             subtitle: nil, symbol: "drop.fill", leftHeroID: heroID(killerID), rightHeroID: heroID(victimID),
                             priority: 5)
        case .multiKill(let killerID, let count):
            let titles = [L("ダブルキル", "Double Kill"), L("トリプルキル", "Triple Kill"),
                          L("クアドラキル", "Quadra Kill"), L("ペンタキル", "PENTAKILL")]
            let title = titles[min(titles.count - 1, max(0, count - 2))]
            return HUDBanner(id: makeID(), tone: count >= 4 ? .epic : killerTone(killerID), title: title, subtitle: nil,
                             symbol: "bolt.fill", leftHeroID: heroID(killerID), priority: 5 + count)
        case .killingSpree(let killerID, let streak):
            let title: String
            switch streak {
            case ..<5: title = L("キリングスプリー", "Killing Spree")
            case 5..<8: title = L("ランページ", "Rampage")
            default: title = L("レジェンダリー", "Legendary")
            }
            return HUDBanner(id: makeID(), tone: killerTone(killerID), title: title,
                             subtitle: L("\(streak) 連続キル", "\(streak) kills in a row"), symbol: "flame.fill",
                             leftHeroID: heroID(killerID), priority: 4)
        case .shutdown(let killerID, let victimID):
            return HUDBanner(id: makeID(), tone: killerTone(killerID), title: L("シャットダウン", "Shutdown"),
                             subtitle: L("連続キルを阻止", "Streak ended"), symbol: "xmark.octagon.fill",
                             leftHeroID: heroID(killerID), rightHeroID: heroID(victimID), priority: 6)
        case .ace(let team):
            let ally = viewer.map { $0 == team } ?? true
            return HUDBanner(id: makeID(), tone: tone(for: team),
                             title: viewer == nil ? L("\(HUDText.teamName(team)) がエース", "\(HUDText.teamName(team)) Ace")
                                 : (ally ? L("エース！", "Ace!") : L("味方が全滅", "Your Team Was Aced")),
                             subtitle: nil, symbol: "crown.fill", priority: 8)
        case .towerDestroyed(let team, let lane, let tier):
            let lost = viewer.map { $0 == team } ?? false
            let title = viewer == nil ? L("\(HUDText.teamName(team)) のタワーが破壊", "\(HUDText.teamName(team)) Tower Destroyed")
                : (lost ? L("味方のタワーが破壊された", "Your Tower Was Destroyed") : L("敵のタワーを破壊", "Enemy Tower Destroyed"))
            return HUDBanner(id: makeID(), tone: tone(for: team.opponent), title: title,
                             subtitle: "\(HUDText.laneName(lane)) · \(HUDText.tierName(tier))",
                             symbol: "building.columns.fill", priority: 3)
        case .coreVulnerable(let team):
            let mine = viewer.map { $0 == team } ?? false
            let title = viewer == nil ? L("\(HUDText.teamName(team)) の Star Core が無防備", "\(HUDText.teamName(team)) Star Core Exposed")
                : (mine ? L("Star Core が無防備に！", "Your Star Core Is Exposed!") : L("敵の Star Core が無防備", "Enemy Star Core Exposed"))
            return HUDBanner(id: makeID(), tone: tone(for: team.opponent), title: title, subtitle: nil,
                             symbol: "exclamationmark.triangle.fill", priority: 7)
        case .wyrmSpawned:
            return HUDBanner(id: makeID(), tone: .neutral, title: L("星喰竜が出現", "The Astral Wyrm Has Spawned"),
                             subtitle: nil, symbol: "hurricane", priority: 2)
        case .colossusSpawned:
            return HUDBanner(id: makeID(), tone: .neutral, title: L("古環の巨像が出現", "The Ancient Colossus Has Awakened"),
                             subtitle: nil, symbol: "crown.fill", priority: 2)
        case .wyrmSlain(let team):
            let title = viewer == nil ? L("\(HUDText.teamName(team)) が星喰竜を討伐", "\(HUDText.teamName(team)) Slew the Wyrm")
                : (isAlly(team) ? L("星喰竜を討伐", "Astral Wyrm Slain") : L("敵が星喰竜を討伐", "Enemy Slew the Astral Wyrm"))
            return HUDBanner(id: makeID(), tone: tone(for: team), title: title,
                             subtitle: L("竜の加護: 与ダメージ +10%", "Wyrm Blessing: +10% damage"), symbol: "hurricane", priority: 4)
        case .colossusSlain(let team):
            let title = viewer == nil ? L("\(HUDText.teamName(team)) が古環の巨像を討伐", "\(HUDText.teamName(team)) Slew the Colossus")
                : (isAlly(team) ? L("古環の巨像を討伐", "Ancient Colossus Slain") : L("敵が古環の巨像を討伐", "Enemy Slew the Colossus"))
            return HUDBanner(id: makeID(), tone: tone(for: team), title: title,
                             subtitle: L("巨像の加護: 与ダメージ +15%・帰還短縮", "Colossus Blessing: +15% damage, faster recall"),
                             symbol: "crown.fill", priority: 5)
        case .surrenderPassed(let team):
            return HUDBanner(id: makeID(), tone: tone(for: team.opponent),
                             title: viewer.map { $0 == team } ?? false ? L("降参が成立", "Surrender Accepted")
                                 : L("\(HUDText.teamName(team)) が降参", "\(HUDText.teamName(team)) Surrendered"),
                             subtitle: nil, symbol: "flag.fill", priority: 9)
        case .victory:
            return nil
        }
    }

    private func enqueueBanner(_ b: HUDBanner) {
        guard endPhase == nil else { return }
        var b = b
        b.gameTime = controller.state.time
        if banner == nil {
            showBanner(b)
            return
        }
        bannerQueue.append(b)
        if bannerQueue.count > 3, let k = bannerQueue.indices.min(by: { bannerQueue[$0].priority < bannerQueue[$1].priority }) {
            bannerQueue.remove(at: k)
        }
    }

    /// 告知の表示時間は試合時間で数える（早送りでは速く流れる。ただし読める最短の実時間は保つ）。
    /// 試合時間が戻った（シーク）・止まったまま（一時停止・配信待ち）でも出しっぱなしにしない。
    static func bannerExpired(wall: Double, game: Double, duration: Double) -> Bool {
        if game < 0 { return true }
        if wall >= duration * 3 { return true }
        return wall >= min(duration, bannerMinimumWall) && game >= duration
    }

    /// 早送り中でも告知を読める最短の実時間（秒）。
    static let bannerMinimumWall: Double = 1.1
    /// キューで待つ間にこれより古くなった告知（試合時間の秒）は出さない（早送りで溜まった昔の告知）。
    static let bannerStaleAfter: Double = 8

    private func showBanner(_ b: HUDBanner) {
        banner = b
        bannerTask?.cancel()
        let duration = bannerQueue.isEmpty ? Self.bannerDuration : Self.bannerDuration * 0.7
        bannerTask = Task { @MainActor [weak self] in
            guard let start = self?.now, let startGame = self?.controller.state.time else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                if Self.bannerExpired(wall: self.now - start, game: self.controller.state.time - startGame,
                                      duration: duration) { break }
            }
            guard !Task.isCancelled, let self else { return }
            let gameNow = self.controller.state.time
            self.bannerQueue.removeAll { gameNow - $0.gameTime > Self.bannerStaleAfter || $0.gameTime > gameNow + 0.01 }
            if self.bannerQueue.isEmpty {
                self.banner = nil
            } else {
                self.showBanner(self.bannerQueue.removeFirst())
            }
        }
    }

    /// キルフィードの最大件数（観戦者は早送りで重なるので少し多め）。
    var killFeedLimit: Int { isSpectating ? Self.killFeedMax + 1 : Self.killFeedMax }
    /// 早送り中でもキルフィードを読める最短の実時間（秒）。
    static let killFeedMinimumWall: TimeInterval = 2.5

    private func addKillFeed(_ k: HeroKillEvent, humanID: EntityID?) {
        let s = controller.sim.state
        guard let victim = s.unit(k.victimID), let vh = victim.hero else { return }
        let killer = s.unit(k.killerID)
        let involves = humanID.map { k.victimID == $0 || k.killerID == $0 || k.assistIDs.contains($0) } ?? false
        let entry = HUDKillFeedEntry(id: makeID(), killerHeroID: killer?.hero?.heroID, killerTeam: killer?.team,
                                     victimHeroID: vh.heroID, victimTeam: victim.team, assists: k.assistIDs.count,
                                     involvesHuman: involves, createdAt: now, gameTime: s.time)
        var feed = killFeed
        feed.append(entry)
        if feed.count > killFeedLimit { feed.removeFirst(feed.count - killFeedLimit) }
        killFeed = feed
    }

    /// キルフィードの期限: 試合時間で killFeedLifetime 秒（早送りでは速く流れ、一時停止中は残る）。
    /// ただし実時間で killFeedMinimumWall 秒は読めるように残す。巻き戻した先より後の項目は捨てる。
    static func feedEntryExpired(_ e: HUDKillFeedEntry, wall: TimeInterval, game: Double) -> Bool {
        if e.gameTime > game + 0.01 { return true }
        return game - e.gameTime > killFeedLifetime && wall - e.createdAt > killFeedMinimumWall
    }

    private func expireFeed(time: TimeInterval) {
        let game = controller.state.time
        if killFeed.contains(where: { Self.feedEntryExpired($0, wall: time, game: game) }) {
            killFeed.removeAll { Self.feedEntryExpired($0, wall: time, game: game) }
        }
    }

    func showToast(_ text: String, symbol: String, isError: Bool) {
        let t = HUDToast(id: makeID(), text: text, symbol: symbol, isError: isError, createdAt: now)
        toast = t
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled, let self, self.toast?.id == t.id else { return }
            self.toast = nil
        }
    }

    // MARK: 試合終了

    /// 画面確認用: チュートリアルの進行状態を差し替える。
    func debugSetTutorial(_ t: TutorialDirector) {
        guard tutorial != nil else { return }
        tutorial = t
    }

    /// 画面確認用: 試合終了の演出だけを出す。
    func debugEnd(winner: Team?) {
        beginEnd(winner: winner, reason: .coreDestroyed)
    }

    private func beginEnd(winner: Team?, reason: EndReason) {
        guard endPhase == nil, !finished else { return }
        setTacticalMap(open: false)
        let kind: HUDMatchResultKind
        if isSpectating {
            kind = winner.map { .teamWin($0) } ?? .draw
        } else if let winner {
            kind = winner == humanTeam ? .victory : .defeat
        } else {
            kind = .draw
        }
        panel = nil
        confirmingLeave = false
        cancelAim()
        attackReleased()
        joystickEnded()
        bannerQueue.removeAll()
        banner = nil
        controller.isPaused = false
        endPhase = .banner(kind, reason)
        app?.audio.stopMusic()
        endTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.endBannerDuration))
            guard !Task.isCancelled, let self, case .banner(let k, let r)? = self.endPhase else { return }
            self.endPhase = .prompt(k, r)
        }
    }

    /// リザルトへ（試合終了後の「続ける」）。
    func continueAfterEnd() {
        app?.audio.play(.uiConfirm)
        finish(abandoned: false)
    }

    /// チュートリアル完了カードの「終了」。
    func finishTutorial() {
        app?.audio.play(.uiConfirm)
        finish(abandoned: true)
    }

    /// 途中退出（確認後）。
    func leave() {
        app?.audio.play(.uiBack)
        finish(abandoned: true)
    }

    private func finish(abandoned: Bool) {
        guard !finished else { return }
        setTacticalMap(open: false)
        finished = true
        panel = nil
        confirmingLeave = false
        cancelAim()
        attackReleased()
        controller.isPaused = false
        let outcome = controller.makeOutcome(abandoned: abandoned)
        if let app {
            app.audio.stopMusic()
            // 練習場・チュートリアルの退出はリザルトを経由せずホームへ戻る
            if abandoned && (mode == .practice || mode == .tutorial) { app.audio.playMusic(.menu) }
        }
        onFinish?(outcome)
    }

    // MARK: パネル

    func openPanel(_ p: HUDPanel) {
        guard endPhase == nil, !finished else { return }
        setTacticalMap(open: false)
        app?.audio.play(.uiTap)
        if p == .shop { tutorial?.noteShopOpened() }
        panel = p
        if p == .pause {
            if !controller.isEnded { controller.isPaused = true }
        } else if p == .scoreboard {
            refreshScoreboard(controller.state)
        } else if p == .shop {
            refreshShop(controller.state, controller.ctx, force: true)
        }
        if p != .shop { cancelAim() }
    }

    func openShop(slot: Int? = nil) {
        shopSelectedSlot = slot
        if let slot, slot < hero.items.count { shopSelectedItemID = hero.items[slot] }
        openPanel(.shop)
    }

    func closePanel() {
        guard let p = panel else { return }
        app?.audio.play(.uiBack)
        panel = nil
        confirmingLeave = false
        if p == .pause && !spectatorPaused { controller.isPaused = false }
    }

    func resume() {
        panel = nil
        confirmingLeave = false
        if !spectatorPaused { controller.isPaused = false }
    }

    /// 観戦の「退出」: ポーズメニューを開いて退出の確認を出す。
    func requestLeave() {
        openPanel(.pause)
        confirmingLeave = true
    }

    /// 外部（バックグラウンド移行）で一時停止された。
    func externallyPaused() {
        setTacticalMap(open: false)
        guard endPhase == nil, !finished, panel != .pause, !spectatorPaused else { return }
        cancelAim()
        attackReleased()
        panel = .pause
    }

    func selectionFeedback() {
        app?.haptics.selection()
    }

    // MARK: 購入

    func buy(_ itemID: String) {
        guard !isSpectating, !finished else { return }
        controller.send(.buyItem(itemID: itemID))
        app?.haptics.tap()
    }

    func sell(slot: Int) {
        guard !isSpectating, !finished else { return }
        controller.send(.sellItem(slotIndex: slot))
        app?.haptics.tap()
    }

    // MARK: 操作

    func joystickChanged(_ vector: CGVector, radius: CGFloat) {
        guard canControl else { return }
        joystickActive = true
        joystickVector = vector
        let len = (vector.dx * vector.dx + vector.dy * vector.dy).squareRoot()
        let dir: Vec2 = len < radius * HUDJoystickMath.deadZone ? .zero : HUDAim.simDirection(vector)
        sendMove(dir, raw: vector, force: false)
    }

    func joystickEnded() {
        let wasActive = joystickActive
        joystickActive = false
        joystickVector = .zero
        if wasActive || lastSentMove != .zero { sendMove(.zero, raw: .zero, force: false) }
    }

    private func sendMove(_ dir: Vec2, raw: CGVector, force: Bool) {
        if !force && !HUDJoystickMath.shouldSend(new: dir, last: lastSentMove) { return }
        controller.joystick(dir == .zero ? .zero : raw)
        lastSentMove = dir
    }

    func attackPressed(button: AttackButtonSlot = .center) {
        guard canControl, !controller.isPaused, !hero.isDead else { return }
        syncSettings()
        heldAttackButton = button
        attackHeld = true
        sendAttack()
        attackTask?.cancel()
        attackTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.attackRepeatInterval)
                guard !Task.isCancelled, let self, self.attackHeld else { return }
                self.sendAttack()
            }
        }
    }

    func attackReleased(button: AttackButtonSlot? = nil) {
        // 別の攻撃ボタンへ押し替えた後、前の指を離しても新しい長押しを止めない。
        if let button, heldAttackButton != button { return }
        heldAttackButton = nil
        attackHeld = false
        attackTask?.cancel()
        attackTask = nil
    }

    private func sendAttack() {
        guard canControl, !controller.isPaused, !hero.isDead, let button = heldAttackButton else { return }
        controller.send(.attackNearest(priority: settings.attackPriority(for: button)))
        lastActionAt = now
    }

    func recall() {
        guard canControl, !hero.isDead, hero.channel == nil else { return }
        controller.send(.recall)
        lastActionAt = now
        app?.haptics.tap()
    }

    func levelSkill(_ slot: SkillSlot) {
        guard canControl else { return }
        controller.send(.levelSkill(slot: slot))
        app?.audio.play(.uiConfirm)
        app?.haptics.impact(.light)
    }

    func quickBuy() {
        guard let id = quickBuyItemID else { return }
        buy(id)
    }

    // MARK: スキル・スペルの照準

    /// ボタン上のドラッグ（HUD 座標）。
    func abilityDragChanged(_ source: AimSource, start: CGPoint, location: CGPoint, buttonCenter: CGPoint) {
        guard canControl else { return }
        if aimSession == nil {
            guard let session = beginSession(source, start: start) else { return }
            aimSession = session
            if session.aiming { showAim(center: buttonCenter, source: source) }
        }
        guard var session = aimSession, session.source == source else { return }
        let drag = CGVector(dx: location.x - session.start.x, dy: location.y - session.start.y)
        session.drag = drag
        let len = (drag.dx * drag.dx + drag.dy * drag.dy).squareRoot()
        if !session.aiming && session.ready && len > HUDAim.tapThreshold {
            session.aiming = true
            showAim(center: buttonCenter, source: source)
        }
        if session.aiming, let layout {
            let cancelling = HUDAim.isInCancelZone(location, center: layout.cancelCenter, radius: layout.cancelRadius)
            if cancelling != session.cancelling {
                session.cancelling = cancelling
                if cancelling { app?.haptics.selection() }
            }
            let maxDrag = layout.aimDragRadius
            let clamped = HUDJoystickMath.clamp(drag, radius: maxDrag)
            aimVisual.drag = clamped
            aimVisual.cancelling = cancelling
        }
        aimSession = session
        if session.aiming { updateAimIndicator() }
    }

    func abilityDragEnded(_ source: AimSource, location: CGPoint) {
        guard let session = aimSession, session.source == source else { return }
        aimSession = nil
        hideAim()
        guard canControl else { return }
        guard session.ready else {
            abilityUnavailableFeedback(source)
            return
        }
        if session.aiming && session.cancelling {
            app?.audio.play(.uiBack)
            return
        }
        let target: SkillTarget
        if session.aiming {
            target = castTarget(for: session)
        } else {
            target = smartTarget(for: session)
        }
        switch source {
        case .skill(let slot):
            controller.send(.castSkill(slot: slot, target: target))
            if var tut = tutorial {
                tut.noteSkillCommand(slot: slot, castable: true)
                if tut != tutorial { tutorial = tut }
            }
        case .spell(let index):
            controller.send(.castSpell(index: index, target: target))
        }
        lastActionAt = now
    }

    /// ジェスチャーが取り消された（onEnded が来ない）場合の後始末。onEnded の後に呼ばれても何もしない。
    func abilityDragCancelled(_ source: AimSource) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let session = self.aimSession, session.source == source else { return }
            self.aimSession = nil
            self.hideAim()
        }
    }

    private func beginSession(_ source: AimSource, start: CGPoint) -> AimSession? {
        let manual = settings.skillCastMode == .manual
        switch source {
        case .skill(let slot):
            guard let sn = skills.first(where: { $0.slot == slot }) else { return nil }
            let ready = sn.isReady && !hero.isDead
            return AimSession(source: source, targeting: sn.targeting, spellID: nil, start: start, ready: ready,
                              aiming: manual && ready)
        case .spell(let index):
            guard index < spells.count else { return nil }
            let sp = spells[index]
            let targeting = HUDSpellAim.targeting(spellID: sp.spellID)
                ?? SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: 0)
            let ready = sp.castable && sp.cooldown <= 0 && !hero.isDead
            return AimSession(source: source, targeting: targeting, spellID: sp.spellID, start: start, ready: ready,
                              aiming: manual && ready && targeting.aim != .none)
        }
    }

    /// タップ（スマート発動）の対象。帰還門だけは前線のタワーを自動で選ぶ。
    private func smartTarget(for session: AimSession) -> SkillTarget {
        guard session.spellID == HUDSpellAim.teleportID, let hi = controller.humanIndex else { return .none }
        let s = controller.sim.state
        return .point(HUDSpellAim.teleportDestination(state: s, team: s.units[hi].team, origin: s.units[hi].pos,
                                                      drag: .zero, fountain: controller.ctx.map.fountain(s.units[hi].team)))
    }

    private func castTarget(for session: AimSession) -> SkillTarget {
        guard let hi = controller.humanIndex else { return .none }
        let s = controller.sim.state
        let u = s.units[hi]
        let maxDrag = layout?.aimDragRadius ?? 84
        if session.spellID == HUDSpellAim.teleportID {
            return .point(HUDSpellAim.teleportDestination(state: s, team: u.team, origin: u.pos, drag: session.drag,
                                                          fountain: controller.ctx.map.fountain(u.team)))
        }
        let aimPoint = HUDAim.aimPoint(origin: u.pos, drag: session.drag, maxDrag: maxDrag, targeting: session.targeting,
                                       facing: u.facing)
        if let spellID = session.spellID {
            return HUDSpellAim.castTarget(spellID: spellID, targeting: session.targeting, origin: u.pos, aimPoint: aimPoint,
                                          drag: session.drag, facing: u.facing, state: s, team: u.team)
        }
        return HUDAim.castTarget(targeting: session.targeting, origin: u.pos, aimPoint: aimPoint, drag: session.drag,
                                 facing: u.facing, state: s, team: u.team, casterID: u.id)
    }

    private func updateAimIndicator() {
        guard let session = aimSession, session.aiming, let hi = controller.humanIndex else {
            controller.aim = nil
            return
        }
        let s = controller.sim.state
        let u = s.units[hi]
        let maxDrag = layout?.aimDragRadius ?? 84
        let target: Vec2
        if session.spellID == HUDSpellAim.teleportID {
            target = HUDSpellAim.teleportDestination(state: s, team: u.team, origin: u.pos, drag: session.drag,
                                                     fountain: controller.ctx.map.fountain(u.team))
        } else {
            target = HUDAim.aimPoint(origin: u.pos, drag: session.drag, maxDrag: maxDrag, targeting: session.targeting,
                                     facing: u.facing)
        }
        let kind: AimIndicator.Kind
        switch session.source {
        case .skill(let slot): kind = .skill(slot)
        case .spell(let index): kind = .spell(index)
        }
        controller.aim = AimIndicator(kind: kind, targeting: session.targeting, origin: u.pos, target: target,
                                      isCancelling: session.cancelling)
    }

    private func showAim(center: CGPoint, source: AimSource) {
        aimVisual.center = center
        aimVisual.drag = .zero
        aimVisual.cancelling = false
        aimVisual.maxDrag = layout?.aimDragRadius ?? 84
        aimVisual.isUltimate = source == .skill(.ultimate)
        aimVisual.active = true
        if !isAiming { isAiming = true }
        app?.haptics.selection()
    }

    private func hideAim() {
        aimVisual.active = false
        aimVisual.cancelling = false
        if isAiming { isAiming = false }
        controller.aim = nil
    }

    func cancelAim() {
        aimSession = nil
        hideAim()
    }

    private func abilityUnavailableFeedback(_ source: AimSource) {
        let t = now
        guard t - lastErrorFeedback > 0.6 else { return }
        lastErrorFeedback = t
        app?.haptics.impact(.soft, intensity: 0.6)
        let message: String
        switch source {
        case .skill(let slot):
            guard let sn = skills.first(where: { $0.slot == slot }) else { return }
            if hero.isDead {
                message = L("倒れている間は使えません", "Unavailable while dead")
            } else if !sn.learned {
                message = L("未習得のスキルです", "Skill not learned yet")
            } else if sn.cooldown > 0 {
                message = L("クールダウン中", "On cooldown")
            } else if sn.silenced {
                message = L("沈黙中はスキルを使えません", "Silenced")
            } else if !sn.affordable {
                message = vitals.resourceKind == .energy ? L("エナジーが足りません", "Not enough energy")
                    : L("マナが足りません", "Not enough mana")
            } else {
                message = L("今は使えません", "Can't cast right now")
            }
        case .spell(let index):
            message = index < spells.count && spells[index].cooldown > 0 ? L("クールダウン中", "On cooldown")
                : L("今は使えません", "Can't cast right now")
        }
        showToast(message, symbol: "exclamationmark.circle.fill", isError: true)
    }
}

/// スティックの計算（純粋関数。単体テスト対象）。
enum HUDJoystickMath {
    /// 半径に対する不感帯の比率。
    static let deadZone: CGFloat = 0.18
    /// この角度未満の変化は送らない。
    static let minAngleChange: Double = 4 * .pi / 180

    /// 方向の変化が送る価値のあるものか（停止 ⇄ 移動、または一定角度以上の変化）。
    static func shouldSend(new: Vec2, last: Vec2) -> Bool {
        let newZero = new == .zero, lastZero = last == .zero
        if newZero || lastZero { return newZero != lastZero }
        return new.dot(last) < cos(minAngleChange)
    }

    static func clamp(_ v: CGVector, radius: CGFloat) -> CGVector {
        let len = (v.dx * v.dx + v.dy * v.dy).squareRoot()
        guard len > radius, len > 0 else { return v }
        return CGVector(dx: v.dx / len * radius, dy: v.dy / len * radius)
    }
}
