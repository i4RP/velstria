import SwiftUI
import VelstriaCore

// 担当: battle-hud（観戦）。観戦者だけが使う HUD の状態（HUDModel が所有する）。
// - 操作状態: 開いている情報パネル・観戦メニュー（引き出し）・シネマ表示・シークバーのドラッグ中の位置など
// - 15Hz で作る観戦用スナップショット: 再生バー・シークバーの印・追従中ヒーローの詳細・目標タイマー・出来事・ゴールド推移
// sim には何も書かない（表示専用）。値が変わった時だけ代入し、観測しているビューだけを作り直す。
// 年表は controller から毎回読む（巻き戻すと timeline は現在の tick で切れ、displayTimeline は分かっている先まで残る）。
// 再生バーの網掛けは controller.seekReadyTick（すぐにシークできる所）、右端は年表の分かっている所。

@Observable
@MainActor
final class HUDSpectatorState {
    /// 情報パネル（右上ボタンの下。1 つずつ）。
    enum Panel: String, CaseIterable, Identifiable {
        /// 追従中のヒーローの詳細。
        case hero
        /// ゴールド・経験値の差の推移。
        case gold
        /// 出来事の一覧（タップでその時刻へ）。
        case events

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .hero: return "person.crop.square.fill"
            case .gold: return "chart.xyaxis.line"
            case .events: return "list.bullet"
            }
        }

        var title: String {
            switch self {
            case .hero: return L("ヒーロー", "Hero")
            case .gold: return L("ゴールド推移", "Gold Graph")
            case .events: return L("出来事", "Events")
            }
        }

        /// タイル用の短い名前。
        var shortTitle: String {
            switch self {
            case .hero: return L("ヒーロー", "Hero")
            case .gold: return L("推移", "Graph")
            case .events: return L("出来事", "Events")
            }
        }
    }

    // MARK: 操作状態

    var panel: Panel?
    var isDrawerOpen = false
    /// HUD を隠して映像だけを見る（戻すボタンだけ残す）。
    var isCinematic = false
    var showsObjectives = true
    /// シークバーをドラッグ中の位置（tick）。nil = ドラッグしていない。
    var dragPreviewTick: Int?

    // MARK: スナップショット（HUDModel.refresh から）

    private(set) var transport = HUDTransportSnapshot()
    private(set) var markers: [HUDTimelineMarker] = []
    private(set) var heroCard: HUDHeroCardSnapshot?
    private(set) var objectives: [HUDObjectiveTimer] = []
    private(set) var eventLog: [HUDEventLogEntry] = []
    private(set) var graph = HUDGoldGraphSnapshot()
    /// カメラが追従している（注目している）ヒーロー。自動カメラ・ミニマップ・ヒーロー切り替えのどれで変わっても追う。
    private(set) var focusID: EntityID?
    /// 最後に追従したヒーロー（自由カメラから「追従に戻る」）。
    @ObservationIgnored private(set) var lastFocusID: EntityID?
    /// カメラが自由（ミニマップ・パン操作）。
    private(set) var isFreeCamera = false

    @ObservationIgnored private var markerKey: (count: Int, last: Int) = (-1, -1)
    @ObservationIgnored private var eventKey: (count: Int, epoch: Int) = (-1, -1)
    @ObservationIgnored private var graphKey: (count: Int, last: Int, end: Int) = (-1, -1, -1)

    /// 「次の見どころ」: これ以上の重要度の出来事（キル・構造物・大型目標・全滅）。
    static let fightMinWeight = 0.45
    /// 「次の見どころ」へ飛ぶ時に、出来事の何 tick 前から見せるか（5 秒）。
    static let fightLeadIn = 150
    /// 出来事の一覧の最大件数。
    static let eventLogLimit = 80

    // MARK: 更新

    /// 15Hz の更新（HUDModel.refresh → refreshSpectate）。
    func refresh(controller c: BattleController, state s: SimState, camps: [HUDMinimapBuffer.Camp], paused: Bool) {
        let display = c.displayTimeline

        // 追従先（自動カメラ・自由カメラも含めて controller.cameraMode から読む）
        var focus: EntityID?
        var free = false
        switch c.cameraMode {
        case .followUnit(let id): focus = id
        case .framing(let ids): focus = ids.first
        case .free: free = true
        case .followHero: break
        }
        if focus != focusID { focusID = focus }
        if let focus { lastFocusID = focus }
        if free != isFreeCamera { isFreeCamera = free }

        // 再生バー
        var next: Int?
        if c.isSeekable, c.seekingToTick == nil {
            next = Self.nextFightTick(after: s.tick, in: display)
        }
        let t = Self.transport(tick: s.tick, finalTick: c.replayFinalTick, coveredTick: display.coveredTick,
                               readyTick: c.seekReadyTick,
                               upperBound: c.seekUpperBound, seekingTo: c.seekingToTick, paused: paused, speed: c.speed,
                               ended: c.isEnded, seekable: c.isSeekable, liveWatcher: c.isSpectating && c.isOnline,
                               delaySeconds: c.onlineSpectatorDelaySeconds, watchers: c.onlineSpectatorCount,
                               nextFightTick: next)
        if t != transport { transport = t }

        // シークバーの印（出来事が増えた時だけ作り直す）
        if c.isSeekable {
            let key = (display.events.count, display.events.last?.tick ?? -1)
            if key != markerKey {
                markerKey = key
                let m = Self.markers(from: display)
                if m != markers { markers = m }
            }
        }

        // 目標タイマー
        let objs = showsObjectives ? Self.objectives(camps: camps, state: s) : []
        if objs != objectives { objectives = objs }

        // 情報パネル（開いている物だけ作る）
        switch panel {
        case .hero?:
            let id = focus ?? lastFocusID
            let card = id.flatMap { s.index(of: $0) }.flatMap {
                HUDModel.buildHeroCard(s, c.ctx, index: $0, ownerID: c.ownerHeroID)
            }
            if card != heroCard { heroCard = card }
        case .events?:
            // 鍵は今の tick までの出来事の数（二分探索）。今の tick で切った年表の複製は、鍵が変わった時だけ作る
            let key = (Self.eventCount(in: c.knownTimeline, atOrBefore: s.tick), c.presentationEpoch)
            if key != eventKey {
                eventKey = key
                let log = Self.eventLog(from: c.timeline, state: s)
                if log != eventLog { eventLog = log }
            }
        case .gold?:
            let key = (display.samples.count, display.samples.last?.tick ?? -1, t.endTick)
            if key != graphKey {
                graphKey = key
                let g = Self.graph(from: display, endTick: t.endTick)
                if g != graph { graph = g }
            }
        case nil:
            break
        }
    }

    /// パネルを開いた時に作り直させる。
    func invalidatePanels() {
        eventKey = (-1, -1)
        graphKey = (-1, -1, -1)
    }

    // MARK: 純粋関数（単体テスト対象）

    /// 再生バーの状態。coveredTick = 年表が分かっている所（観戦の右端）、readyTick = すぐにシークできる所（網掛け。
    /// 省略時は coveredTick）。年表が保存されたリプレイは最初から最後まで分かっているが、網掛けは状態のある所までにする。
    static func transport(tick: Int, finalTick: Int?, coveredTick: Int, readyTick: Int? = nil, upperBound: Int, seekingTo: Int?,
                          paused: Bool, speed: Double, ended: Bool, seekable: Bool, liveWatcher: Bool,
                          delaySeconds: Double?, watchers: Int, nextFightTick: Int?) -> HUDTransportSnapshot {
        var t = HUDTransportSnapshot()
        t.tick = tick
        // 右端: リプレイは最終 tick。観戦は分かっている所（一度見た所・先に計算した所）か現在位置の先の方
        let end = finalTick ?? max(coveredTick, tick, seekingTo ?? 0)
        t.endTick = max(1, end)
        t.coveredTick = min(t.endTick, max(0, readyTick ?? coveredTick))
        t.upperBound = max(1, upperBound)
        t.isEndKnown = finalTick != nil
        t.seekingTo = seekingTo
        t.isPaused = paused
        t.speed = speed
        t.isEnded = ended
        t.isSeekable = seekable
        t.isLiveWatcher = liveWatcher
        t.delaySeconds = liveWatcher ? delaySeconds : nil
        t.watchers = watchers
        t.nextFightTick = nextFightTick
        return t
    }

    /// tick 以前の出来事の数（年表の events は tick 昇順なので二分探索。年表を複製しない）。
    static func eventCount(in timeline: ReplayTimeline, atOrBefore tick: Int) -> Int {
        let events = timeline.events
        var lo = 0
        var hi = events.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if events[mid].tick <= tick { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// バー上の位置（0〜1）→ tick（0〜endTick に丸める）。
    static func tick(atFraction f: Double, endTick: Int) -> Int {
        let clamped = min(1, max(0, f.isFinite ? f : 0))
        return Int((clamped * Double(max(1, endTick))).rounded())
    }

    /// 次の見どころの開始 tick（出来事の少し前から。現在位置より先だけ）。
    static func nextFightTick(after tick: Int, in timeline: ReplayTimeline) -> Int? {
        guard let e = timeline.nextEvent(after: tick + fightLeadIn, minWeight: fightMinWeight) else { return nil }
        return max(tick + 1, e.tick - fightLeadIn)
    }

    /// シークバーの印（キル・構造物・大型目標・全滅・終了）。
    static func markers(from timeline: ReplayTimeline) -> [HUDTimelineMarker] {
        timeline.events.map { e in
            let kind: HUDTimelineMarker.Kind
            switch e.kind {
            case .kill: kind = .kill
            case .structure: kind = .structure
            case .objective: kind = .objective
            case .ace: kind = .ace
            case .matchEnd: kind = .end
            }
            return HUDTimelineMarker(tick: e.tick, kind: kind, team: e.creditedTeam, weight: e.weight)
        }
    }

    /// 目標タイマー（星喰竜・古環の巨像の出現まで / 出現中、チームの加護の残り）。
    static func objectives(camps: [HUDMinimapBuffer.Camp], state s: SimState) -> [HUDObjectiveTimer] {
        var out: [HUDObjectiveTimer] = []
        for camp in camps {
            let kind: HUDObjectiveTimer.Kind
            switch camp.kind {
            case .astralWyrm?: kind = .wyrm
            case .ancientColossus?: kind = .colossus
            default: continue
            }
            let seconds: Int? = camp.alive ? nil : camp.respawnRemaining.map { Int(max(0, $0).rounded(.up)) }
            // 出現時刻が分からない（霧の中で倒された）ものは出さない
            if !camp.alive && seconds == nil { continue }
            out.append(HUDObjectiveTimer(kind: kind, team: nil, seconds: seconds))
        }
        for (status, kind) in [(StatusKind.wyrmBlessing, HUDObjectiveTimer.Kind.wyrmBlessing),
                               (.colossusBlessing, .colossusBlessing)] {
            for team in Team.players {
                var best: Double = 0
                for i in s.heroIndices(team: team) {
                    for st in s.units[i].statuses where st.kind == status { best = max(best, st.remaining) }
                }
                if best > 0 { out.append(HUDObjectiveTimer(kind: kind, team: team, seconds: Int(best.rounded(.up)))) }
            }
        }
        return out
    }

    /// 出来事の一覧（新しい順・最大 eventLogLimit 件）。
    static func eventLog(from timeline: ReplayTimeline, state s: SimState) -> [HUDEventLogEntry] {
        func heroID(_ id: EntityID?) -> String? { s.unit(id)?.hero?.heroID }
        func heroName(_ id: EntityID?) -> String? {
            heroID(id).map { hid in MasterData.shared.hero(hid).map { MasterText.hero($0) } ?? hid }
        }
        var out: [HUDEventLogEntry] = []
        for (k, e) in timeline.events.enumerated().reversed() {
            var entry = HUDEventLogEntry(id: k, tick: e.tick, title: "", symbol: "circle.fill", team: e.creditedTeam,
                                         weight: e.weight, pos: e.pos)
            switch e.kind {
            case .kill(let victim, let killer, let assists, _, let firstBlood, let multi, let shutdown):
                let v = heroName(victim) ?? "?"
                if let k = heroName(killer) {
                    entry.title = L("\(k) が \(v) を撃破", "\(k) slew \(v)")
                } else {
                    entry.title = L("\(v) が処刑された", "\(v) was executed")
                }
                var tags: [String] = []
                if firstBlood { tags.append(L("ファーストブラッド", "First Blood")) }
                if multi >= 2 {
                    let names = [L("ダブルキル", "Double Kill"), L("トリプルキル", "Triple Kill"),
                                 L("クアドラキル", "Quadra Kill"), L("ペンタキル", "Pentakill")]
                    tags.append(names[min(names.count - 1, multi - 2)])
                }
                if shutdown { tags.append(L("シャットダウン", "Shutdown")) }
                if !assists.isEmpty { tags.append(L("アシスト \(assists.count)", "\(assists.count) assists")) }
                entry.subtitle = tags.isEmpty ? nil : tags.joined(separator: " · ")
                entry.symbol = "bolt.fill"
                entry.leftHeroID = heroID(killer)
                entry.rightHeroID = heroID(victim)
                entry.focusID = s.unit(killer)?.kind == .hero ? killer : victim
            case .structure(let team, let kind, let lane, let tier, _):
                if kind == .core {
                    entry.title = L("\(HUDText.teamName(team)) の Star Core が破壊", "\(HUDText.teamName(team)) Star Core destroyed")
                } else {
                    entry.title = L("\(HUDText.teamName(team)) のタワーが破壊", "\(HUDText.teamName(team)) tower destroyed")
                    entry.subtitle = tier.map { "\(HUDText.laneName(lane)) · \(HUDText.tierName($0))" } ?? HUDText.laneName(lane)
                }
                entry.symbol = "building.columns.fill"
            case .objective(let kind, let team, let killer):
                let name: String
                switch kind {
                case .astralWyrm: name = L("星喰竜", "Astral Wyrm"); entry.symbol = "hurricane"
                case .ancientColossus: name = L("古環の巨像", "Ancient Colossus"); entry.symbol = "crown.fill"
                case .blueSentinel: name = L("蒼晶の番人", "Azure Sentinel"); entry.symbol = "drop.fill"
                case .redSentinel: name = L("紅焔の番人", "Crimson Sentinel"); entry.symbol = "flame.circle.fill"
                case .campLarge, .campSmall: name = L("中立モンスター", "Jungle camp"); entry.symbol = "diamond.fill"
                }
                entry.title = L("\(HUDText.teamName(team)) が\(name)を討伐", "\(HUDText.teamName(team)) took the \(name)")
                entry.leftHeroID = heroID(killer)
                entry.focusID = s.unit(killer)?.kind == .hero ? killer : nil
            case .ace(let team):
                entry.title = L("\(HUDText.teamName(team)) がエース", "\(HUDText.teamName(team)) Ace")
                entry.symbol = "crown.fill"
            case .matchEnd(let winner, let reason):
                if let winner {
                    entry.title = L("\(HUDText.teamName(winner)) の勝利", "\(HUDText.teamName(winner)) wins")
                } else {
                    entry.title = L("試合終了", "Match over")
                }
                entry.subtitle = HUDText.endReason(reason)
                entry.symbol = "flag.fill"
            }
            out.append(entry)
            if out.count >= eventLogLimit { break }
        }
        return out
    }

    /// ゴールド・経験値の差の推移（ブルーから見た差）。
    static func graph(from timeline: ReplayTimeline, endTick: Int) -> HUDGoldGraphSnapshot {
        var g = HUDGoldGraphSnapshot()
        g.points = timeline.samples.map { HUDGraphPoint(tick: $0.tick, gold: $0.goldDiff, xp: $0.xpDiff) }
        g.endTick = max(1, endTick, timeline.samples.last?.tick ?? 0)
        return g
    }

    /// ヒーローの並び（ブルー 1〜5、レッド 1〜5）で step 個先のヒーロー（倒れているヒーローは飛ばす。全員倒れていれば順に）。
    static func adjacentHero(from current: EntityID?, step: Int, heroes: [HUDSpectateHero]) -> EntityID? {
        guard !heroes.isEmpty, step != 0 else { return nil }
        let n = heroes.count
        let start = current.flatMap { id in heroes.firstIndex { $0.id == id } } ?? (step > 0 ? -1 : 0)
        let dir = step > 0 ? 1 : -1
        for k in 1...n {
            let i = ((start + dir * k) % n + n) % n
            if !heroes[i].isDead { return heroes[i].id }
        }
        let i = ((start + dir) % n + n) % n
        return heroes[i].id
    }

    /// 速度の識別子（UI テストの spectate_speed_2x など）。
    static func speedLabel(_ speed: Double) -> String {
        speed == speed.rounded() ? "\(Int(speed))" : String(format: "%g", speed)
    }
}
