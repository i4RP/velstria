import Foundation
import VelstriaCore

// 担当: battle-renderer（観戦）。自動カメラ（見どころを自動で追う）と、観戦カメラの操作の受け渡し。
// - SpectatorCameraLink: HUD の指の操作（パン・ピンチ・ダブルタップ）と描画側（BattleWorld・自動カメラ）を
//   controller ごとに 1 つの窓口でつなぐ（どちらも controller だけを知っている）。
// - CameraDirector: 描画専用の購読者。SimEvent（キル・全滅・構造物・目標・奥義）を「見どころ」として覚え、
//   SimState（集団戦・低 HP の追走・ボス戦・攻城）と合わせて点数を付け、画（単独の追従 / 複数を収める framing）を選ぶ。
//   画の切替は sim の時間で決める（最短の長さ・ヒステリシス・割り込み）ので、倍速でも慌ただしくならない。
//   視点チームが選ばれていれば、そのチームに見えているものだけを映す。手動でカメラを動かすとしばらく控える
//   （控える時間は再生している間だけ減る。一時停止・シーク中は止まった時間として数えない）。
// - 倍率: 自動カメラは観戦者が倍率を決めていない間だけ followZoom を書く。観戦者が決めた倍率（ピンチ・一時停止メニューの
//   「カメラ距離」）が優先で、画を変えても書き戻さない。メニューで変えた倍率から自動カメラが倍率を取り戻すのは、観戦者が
//   自動カメラをオンにし直した時と、ダブルタップで自動カメラへ戻した時（ダブルタップは倍率も既定へ戻す操作）だけ。
// - 点数付け（DirectorMoments / DirectorScoring）と画の選択（DirectorPolicy）は純粋な値型で、単体テストできる。
// 決定論: sim の状態は読むだけ。自動カメラの状態は SimState にもリプレイにも入らない。

// MARK: - 見どころ（出来事の記憶）

/// 覚えておく出来事（時間とともに減衰する点数）。
struct DirectorMoment: Equatable {
    enum Kind: Equatable {
        case kill
        case ace
        case structure
        case objective
        case ultimate
    }

    var kind: Kind
    /// sim の時刻（秒）。
    var time: Double
    var pos: Vec2
    /// 主役（キルした・奥義を撃ったヒーロー。いなければ nil）。
    var subject: EntityID?
    var weight: Double
    /// 半減期（秒）。
    var halfLife: Double
    /// この出来事を知っているチーム（Team.visionBit の集合: その場所が見えていた・自チームのユニットが関わった）。
    var seenBy: UInt8
}

/// 出来事の記憶（純粋な値型）。キル・多重キル・全滅・構造物・目標（ボス）・奥義。
struct DirectorMoments: Equatable {
    static let capacity = 48
    /// 主役でなくても、この距離（sim 単位）以内のヒーローは見どころの点数を分けてもらう。
    static let reach: Double = 1500

    private(set) var items: [DirectorMoment] = []

    mutating func reset() { items.removeAll() }

    /// 1 step 分のイベントを覚える（state = その step 直後の状態）。
    mutating func record(_ events: [SimEvent], state s: SimState) {
        for e in events {
            switch e {
            case .heroKilled(let k):
                guard let victim = s.unit(k.victimID) else { continue }
                let killer = s.unit(k.killerID)
                var w = 45.0
                if k.isFirstBlood { w += 15 }
                if k.multiKill >= 2 { w += 22 * Double(k.multiKill - 1) }
                if k.isShutdown { w += 10 }
                add(.kill, time: s.time, pos: victim.pos, subject: killer?.kind == .hero ? k.killerID : nil, weight: w,
                    halfLife: 3, state: s, teams: [victim.team, killer?.team])
            case .announcement(.ace(let team)):
                // 全滅の場所 = 直前のキルの場所（無ければ全滅させた側のヒーローの重心）
                let pos = items.last(where: { $0.kind == .kill })?.pos ?? centroid(of: team, in: s)
                guard let pos else { continue }
                add(.ace, time: s.time, pos: pos, subject: nil, weight: 40, halfLife: 4, state: s, teams: [team, team.opponent])
            case .structureDestroyed(let id, let kind, let team, _, _, let killerID):
                guard let u = s.unit(id) else { continue }
                let killer = s.unit(killerID)
                // 構造物は両チームから常に見えている
                add(.structure, time: s.time, pos: u.pos, subject: killer?.kind == .hero ? killerID : nil,
                    weight: kind == .core ? 80 : 35, halfLife: 3, state: s, teams: [team, team.opponent])
            case .objectiveTaken(let kind, let team, let killerID):
                let killer = s.unit(killerID)
                guard let pos = killer?.pos ?? centroid(of: team, in: s) else { continue }
                let boss = kind == .astralWyrm || kind == .ancientColossus
                add(.objective, time: s.time, pos: pos, subject: killer?.kind == .hero ? killerID : nil,
                    weight: boss ? 50 : 12, halfLife: 3, state: s, teams: [team])
            case .skillCast(let c) where c.slot == .ultimate:
                add(.ultimate, time: s.time, pos: c.origin, subject: c.casterID, weight: 28, halfLife: 2, state: s,
                    teams: [s.unit(c.casterID)?.team])
            default:
                break
            }
        }
        prune(now: s.time)
    }

    /// 古い記憶（半減期の 4 倍を過ぎた）と、巻き戻した後の「未来の」記憶を捨てる。
    mutating func prune(now: Double) {
        items.removeAll { now - $0.time > $0.halfLife * 4 || $0.time > now + 1e-6 }
    }

    /// ヒーロー（id、位置 pos）が今受け取る見どころの点数。vision があればそのチームが知っている出来事だけ。
    func interest(subject id: EntityID, at pos: Vec2, now: Double, vision: Team?) -> Double {
        var total = 0.0
        for m in items {
            if let vision, m.seenBy & vision.visionBit == 0 { continue }
            let age = now - m.time
            guard age >= 0 else { continue }
            let decay = pow(0.5, age / m.halfLife)
            if m.subject == id {
                total += m.weight * decay
            } else if m.pos.distanceSquared(to: pos) <= Self.reach * Self.reach {
                total += m.weight * decay * 0.6
            }
        }
        return total
    }

    private mutating func add(_ kind: DirectorMoment.Kind, time: Double, pos: Vec2, subject: EntityID?, weight: Double,
                              halfLife: Double, state s: SimState, teams: [Team?]) {
        var seen: UInt8 = 0
        for team in Team.players where s.vision.isLit(pos, for: team) { seen |= team.visionBit }
        for team in teams { if let team { seen |= team.visionBit } }
        items.append(DirectorMoment(kind: kind, time: time, pos: pos, subject: subject, weight: weight, halfLife: halfLife,
                                    seenBy: seen))
        if items.count > Self.capacity { items.removeFirst(items.count - Self.capacity) }
    }

    private func centroid(of team: Team, in s: SimState) -> Vec2? {
        let heroes = s.heroIndices(team: team).filter { s.units[$0].isAlive && s.units[$0].hero?.isDead == false }
        guard !heroes.isEmpty else { return nil }
        return heroes.reduce(Vec2.zero) { $0 + s.units[$1].pos } / Double(heroes.count)
    }
}

// MARK: - 点数付け

/// 画の候補（主役 1 人 + 一緒に収めるヒーロー）。
struct DirectorCandidate: Equatable {
    var subject: EntityID
    /// 一緒に収める近くのヒーロー（ID 昇順。主役を含まない。空なら単独の追従）。
    var others: [EntityID]
    var score: Double
    /// 見どころの中心（sim 座標）。
    var center: Vec2
    /// 交戦中（近くに敵ヒーローがいて、最近戦っている）。
    var isFight: Bool

    /// この画のカメラモード（複数なら framing。先頭が主役）。
    var cameraMode: CameraMode { others.isEmpty ? .followUnit(subject) : .framing([subject] + others) }
}

/// 見どころの点数付け（純関数）。生きていて視点チームから見えているヒーローごとに 1 つの候補を作る。
enum DirectorScoring {
    /// 交戦とみなす敵味方の距離（sim 単位）。
    static let fightRadius: Double = 1300
    /// この秒数以内に交戦・被弾していれば戦闘中。
    static let combatWindow: Double = 2.5
    static let bossRadius: Double = 1700
    static let towerRadius: Double = 1100
    /// 主役と一緒に収める最大人数。
    static let maxFramed = 5

    /// 候補（点数の高い順。同点はユニットの添字順）。
    static func candidates(state s: SimState, moments: DirectorMoments, vision: Team?) -> [DirectorCandidate] {
        let now = s.time
        var heroes: [Int] = []
        var bosses: [Int] = []
        var towers: [Int] = []
        for i in s.units.indices {
            let u = s.units[i]
            guard u.isAlive else { continue }
            switch u.kind {
            case .hero:
                guard u.hero?.isDead == false else { continue }
                if let vision, !s.isVisible(i, to: vision) { continue }
                heroes.append(i)
            case .monster:
                guard let kind = u.monster?.kind, kind == .astralWyrm || kind == .ancientColossus else { continue }
                if let vision, !s.isVisible(i, to: vision) { continue }
                bosses.append(i)
            case .tower, .core:
                towers.append(i)
            default:
                continue
            }
        }
        let fightR2 = fightRadius * fightRadius
        var out: [(index: Int, candidate: DirectorCandidate)] = []
        out.reserveCapacity(heroes.count)
        for i in heroes {
            let u = s.units[i]
            var enemies: [Int] = []
            var allies: [Int] = []
            for j in heroes where j != i {
                guard s.units[j].pos.distanceSquared(to: u.pos) <= fightR2 else { continue }
                if s.units[j].team == u.team { allies.append(j) } else { enemies.append(j) }
            }
            let involved = [i] + enemies
            let fighting = !enemies.isEmpty && involved.contains {
                now - s.units[$0].lastCombatTime < combatWindow || now - s.units[$0].lastDamagedTime < 2
            }
            // 何も無くても少しだけ（レベルの高いヒーローを優先）
            var score = 1 + Double(u.hero?.level ?? 1) * 0.1
            if !enemies.isEmpty {
                let n = Double(enemies.count + allies.count + 1)
                if fighting {
                    score += 14 * n
                    if n >= 6 { score += 30 }   // 集団戦
                    let lowest = involved.map { s.units[$0].hpRatio }.min() ?? 1
                    score += (1 - lowest) * 30   // 誰かが倒れそう
                    if u.hpRatio < 0.3 { score += 15 }   // 追われている・逃げている
                } else {
                    score += 4 * n   // にらみ合い
                }
            }
            for b in bosses where s.units[b].pos.distanceSquared(to: u.pos) <= bossRadius * bossRadius {
                if now - s.units[b].lastDamagedTime < 3 { score += enemies.isEmpty ? 35 : 55 }   // ボス戦（奪い合いは更に）
            }
            for t in towers where s.units[t].team != u.team && s.units[t].pos.distanceSquared(to: u.pos) <= towerRadius * towerRadius {
                if now - s.units[t].lastDamagedTime < 2.5 { score += 12 + (1 - s.units[t].hpRatio) * 15 }   // 攻城
            }
            score += moments.interest(subject: u.id, at: u.pos, now: now, vision: vision)

            var others: [Int] = []
            if !enemies.isEmpty {
                others = (enemies + allies).sorted {
                    let a = s.units[$0].pos.distanceSquared(to: u.pos), b = s.units[$1].pos.distanceSquared(to: u.pos)
                    return a != b ? a < b : $0 < $1
                }
                others = Array(others.prefix(maxFramed))
            }
            let members = [i] + others
            let center = members.reduce(Vec2.zero) { $0 + s.units[$1].pos } / Double(members.count)
            let ids = others.map { s.units[$0].id }.sorted()
            out.append((i, DirectorCandidate(subject: u.id, others: ids, score: score, center: center, isFight: fighting)))
        }
        out.sort { $0.candidate.score != $1.candidate.score ? $0.candidate.score > $1.candidate.score : $0.index < $1.index }
        return out.map(\.candidate)
    }
}

// MARK: - 画の選択

/// 画の切替の規則（純粋な値型。時刻は sim の秒）。
/// - 最短の長さ（minShot）までは、大きな見どころ（interruptScore 以上で今の画の interruptRatio 倍）でだけ割り込む。
/// - 以後は今の画より明らかに良い（switchRatio 倍 + switchBias）時に切り替える（ヒステリシス）。
/// - 静かな画が rotateAfter 続いたら別のヒーローへ回す。主役が倒れた・霧に入ったら lostHold だけ見せて次へ。
/// - いちばんの見どころが今の画の中にいる（同じ戦い）なら主役は変えず、収める顔ぶれだけ更新する。
struct DirectorPolicy: Equatable {
    struct Config: Equatable {
        var minShot: Double = 4
        var interruptScore: Double = 75
        var interruptRatio: Double = 1.6
        var interruptGap: Double = 1.5
        var switchRatio: Double = 1.3
        var switchBias: Double = 10
        var rotateAfter: Double = 14
        var quietScore: Double = 18
        /// 主役が倒れた場面を見せる長さ（BattleWorld.deathHoldSeconds より短く: 描画側の代わりの味方へ移る前に次の画へ）。
        var lostHold: Double = 2
    }

    enum Decision: Equatable {
        /// 今の画のまま（カメラモードも同じ）。
        case keep
        /// 同じ画で、収める顔ぶれが変わった。
        case update(DirectorCandidate)
        /// 新しい画（主役が変わる）。
        case cut(DirectorCandidate)
    }

    var config = Config()
    private(set) var current: DirectorCandidate?
    private(set) var shotStart: Double = 0
    private(set) var lastSwitch: Double = -.infinity
    private var lostAt: Double?

    mutating func reset() {
        current = nil
        shotStart = 0
        lastSwitch = -.infinity
        lostAt = nil
    }

    /// candidates は点数の高い順（DirectorScoring.candidates）。
    mutating func decide(_ candidates: [DirectorCandidate], now: Double) -> Decision {
        guard let best = candidates.first else {
            // 映せるヒーローがいない（全員倒れている・見えない）: 今の画のまま
            return .keep
        }
        guard let cur = current else { return begin(best, now: now) }
        guard let live = candidates.first(where: { $0.subject == cur.subject }) else {
            // 主役が倒れた・霧に入った: 少しだけ見せてから次へ（撃破の瞬間を見せる）
            let lost = lostAt ?? now
            lostAt = lost
            return now - lost >= config.lostHold ? begin(best, now: now) : .keep
        }
        lostAt = nil
        let elapsed = now - shotStart
        // 静かな画が長く続いた: 別のヒーロー（今の画に入っていない中で一番の候補）へ回す
        let rotation = elapsed >= config.rotateAfter && live.score < config.quietScore
            ? candidates.first(where: { $0.subject != cur.subject && !live.others.contains($0.subject) }) : nil
        // 同じ戦い: 主役はそのまま
        if best.subject == cur.subject || live.others.contains(best.subject) {
            if let rotation { return begin(rotation, now: now) }
            return refresh(live)
        }
        if elapsed < config.minShot {
            if best.score >= config.interruptScore, best.score > live.score * config.interruptRatio,
               now - lastSwitch >= config.interruptGap {
                return begin(best, now: now)
            }
            return refresh(live)
        }
        if best.score > live.score * config.switchRatio + config.switchBias { return begin(best, now: now) }
        if let rotation { return begin(rotation, now: now) }
        return refresh(live)
    }

    private mutating func begin(_ c: DirectorCandidate, now: Double) -> Decision {
        current = c
        shotStart = now
        lastSwitch = now
        lostAt = nil
        return .cut(c)
    }

    private mutating func refresh(_ live: DirectorCandidate) -> Decision {
        let before = current?.cameraMode
        current = live
        return live.cameraMode == before ? .keep : .update(live)
    }
}

// MARK: - 自動カメラ

/// 自動カメラ（観戦中で controller.spectatorDirectorEnabled の間だけ動く）。BattleWorld が作って毎フレーム update する。
/// 出力は controller.cameraMode（.followUnit / .framing）。framing の距離は BattleWorld が対象から逆算する。
@MainActor
final class CameraDirector {
    let controller: BattleController
    let link: SpectatorCameraLink
    private(set) var moments = DirectorMoments()
    private(set) var policy = DirectorPolicy()
    private var token: UUID?
    private var epoch: Int
    /// 自動カメラが最後に書いたカメラモード（これと違っていたら手動で動かされた）。
    private var written: CameraMode?
    /// 前のフレームで見たカメラモード（控えている間に観戦者が続けて動かしたら、控えを延ばす）。
    private var observedMode: CameraMode?
    /// 自動カメラが書いた倍率（観戦者がピンチで変えていたら書かない）。
    private var writtenZoom: Double?
    /// 観戦者が一時停止メニューで倍率を決めた（オンにし直す・ダブルタップで戻すまで倍率を書かない）。
    private(set) var zoomYielded = false
    private var suspendedUntil: TimeInterval = 0
    /// 前の update の実時間と、その時に止まっていた（一時停止・シーク中）か。止まっていた間は控えの残りを減らさない。
    private var lastUpdateClock: TimeInterval?
    private var wasFrozen = false
    private var lastEvaluation: Double = -.infinity
    private var wasActive = false
    private var forceEvaluation = true
    /// 実時間（手動操作の後に控える時間は実時間で数える。倍速でも同じ長さ）。テストで差し替える。
    var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    /// 手動でカメラを動かした後、自動カメラが控える時間（再生している間の実時間の秒。一時停止・シーク中は数えない）。
    static let manualSuspendSeconds: TimeInterval = 10
    /// 画を選び直す間隔（sim の秒）。
    static let evaluationInterval: Double = 0.25
    /// 自動カメラの単独の追従の倍率（プレイヤーの既定より少し引いて周りの状況も見せる）。
    /// 観戦者がピンチで決めた倍率は上書きしない。framing は対象から逆算し、これより寄らない。
    static let followZoom: Double = 1.2

    init(controller: BattleController, link: SpectatorCameraLink) {
        self.controller = controller
        self.link = link
        epoch = controller.presentationEpoch
        link.director = self
    }

    var isActive: Bool { controller.isSpectating && controller.spectatorDirectorEnabled }
    /// 手動操作の後で控えている。
    var isSuspended: Bool { clock() < suspendedUntil }

    func start() {
        guard token == nil else { return }
        token = controller.subscribe { [weak self] events in self?.observe(events) }
    }

    func stop() {
        if let token { controller.unsubscribe(token) }
        token = nil
        if link.director === self { link.director = nil }
    }

    /// 1 step 分のイベント（購読）。オフの間も覚えておく（オンにした直後から見どころが分かる）。
    func observe(_ events: [SimEvent]) {
        guard controller.isSpectating else { return }
        moments.record(events, state: controller.state)
    }

    /// 手動のカメラ操作（パン・ピンチ・追従先の選択・ミニマップ）。しばらく控える（続けて操作すると延びる）。
    func noteManualCameraInput() {
        suspendedUntil = clock() + Self.manualSuspendSeconds
        written = nil
    }

    /// 観戦者が一時停止メニューで倍率を変えた（HUD が倍率の上書きを外した後に呼ぶ）。設定の倍率を優先し、
    /// オンにし直す・ダブルタップで戻すまで自動カメラの倍率を書かない（画を変えるたびに 1.2 へ戻さない）。
    func yieldZoom() {
        zoomYielded = true
        writtenZoom = nil
    }

    /// 控えをやめてすぐ自動カメラに戻す（ダブルタップ）。今の画をもう一度映す。倍率も自動カメラへ返す。
    func resume() {
        suspendedUntil = 0
        written = nil
        zoomYielded = false
        forceEvaluation = true
        if let shot = policy.current { apply(shot.cameraMode) }
    }

    /// 毎フレーム（BattleWorld.updateCamera から。一時停止中も呼ばれるが、sim の時間が進まないので画は変えない）。
    func update() {
        freezeSuspensionWhilePaused()
        let active = isActive
        defer { wasActive = active }
        guard active else {
            if wasActive {
                // オフになった: framing は自動カメラだけが作る画（手動では作れない）。残すと、オフにした後も集団戦の全員を
                // 収めようと動き・引き続けるので、主役の追従に替える
                if case .framing(let ids) = controller.cameraMode, let first = ids.first {
                    controller.cameraMode = .followUnit(first)
                }
                // オフになった（観戦者が切り替えた）: 自動カメラが書いた倍率を外して、設定の倍率へ戻す
                // （残すと一時停止メニューの倍率が効かないまま。観戦者がピンチで決めた倍率はそのまま）
                if let z = writtenZoom, controller.cameraZoomOverride == z { controller.cameraZoomOverride = nil }
                writtenZoom = nil
            }
            written = nil
            observedMode = nil
            return
        }
        if !wasActive {
            // オンになった（観戦の開始・観戦者が切り替えた）: 控えなしですぐ選ぶ。倍率も自動カメラへ返す
            suspendedUntil = 0
            written = nil
            zoomYielded = false
            forceEvaluation = true
            policy.reset()
        }
        if controller.presentationEpoch != epoch {
            // シーク・再同期: 覚えていた出来事と画は別の時間のものなので捨てる
            epoch = controller.presentationEpoch
            moments.reset()
            policy.reset()
            written = nil
            forceEvaluation = true
            lastEvaluation = -.infinity
        }
        guard controller.seekingToTick == nil, !controller.isEnded else { return }
        // 自動カメラが書いたモードと違う = 観戦者が追従先・ミニマップ・パンで動かした。控えている間も、前のフレームから
        // 変わっていれば（別のヒーローを選び直した・ミニマップを動かし続けている）控えを延ばす
        let mode = controller.cameraMode
        if let w = written, mode != w {
            noteManualCameraInput()
        } else if written == nil, let seen = observedMode, mode != seen {
            noteManualCameraInput()
        }
        observedMode = mode
        guard !isSuspended else { return }
        let now = controller.state.time
        guard forceEvaluation || now - lastEvaluation >= Self.evaluationInterval || now < lastEvaluation else { return }
        forceEvaluation = false
        lastEvaluation = now
        policy.config = Self.config(speed: controller.speed)
        let candidates = DirectorScoring.candidates(state: controller.state, moments: moments, vision: controller.spectatorVision)
        switch policy.decide(candidates, now: now) {
        case .keep:
            // 控えが明けた: 手動で動かしたカメラを今の画へ戻す
            if written == nil, let shot = policy.current { apply(shot.cameraMode) }
        case .update(let c), .cut(let c):
            apply(c.cameraMode)
        }
    }

    /// 一時停止・シーク中（HUD では止まった時間）は、控えの期限をその分だけ先へ送る（明けた直後に奪い返さない）。
    /// 止まった・動き出した境目のフレームも止まっていた側に数える（一時停止中に描画の間隔が空いても取りこぼさない）。
    private func freezeSuspensionWhilePaused() {
        let now = clock()
        let frozen = controller.isPaused || controller.seekingToTick != nil
        if let last = lastUpdateClock, frozen || wasFrozen, suspendedUntil > last {
            suspendedUntil += max(0, now - last)
        }
        lastUpdateClock = now
        wasFrozen = frozen
    }

    /// 再生速度に合わせた切替の規則。sim の時間で決めるが、倍速で画が目まぐるしく変わらないよう、
    /// 実時間でも最短 1.2 秒・倒れた主役は 0.8 秒・割り込みの間隔は 0.6 秒を下回らないようにする。
    static func config(speed: Double) -> DirectorPolicy.Config {
        var c = DirectorPolicy.Config()
        let k = max(1, speed.isFinite ? speed : 1)
        c.minShot = max(c.minShot, 1.2 * k)
        c.lostHold = max(c.lostHold, 0.8 * k)
        c.interruptGap = max(c.interruptGap, 0.6 * k)
        c.rotateAfter = max(c.rotateAfter, c.minShot * 2)
        return c
    }

    private func apply(_ mode: CameraMode) {
        if controller.cameraMode != mode { controller.cameraMode = mode }
        written = mode
        guard !zoomYielded else { return }
        let zoom = controller.cameraZoomOverride
        if zoom == nil || zoom == writtenZoom {
            controller.cameraZoomOverride = Self.followZoom
            writtenZoom = Self.followZoom
        }
    }
}

// MARK: - 観戦カメラの窓口

/// 観戦カメラの操作の窓口（controller ごとに 1 つ）。HUD の指の操作（HUDSpectatorGestures）と描画側
/// （BattleWorld・CameraDirector）が controller だけを手掛かりに同じものを取り出す。値は毎フレーム書き換わるので非監視。
@MainActor
final class SpectatorCameraLink {
    private(set) weak var controller: BattleController?
    /// 自動カメラ（観戦中のみ。BattleWorld が作る）。
    weak var director: CameraDirector?
    /// 指で自由カメラを動かしている（描画はばねを掛けずに注視点を合わせる）。
    var isPanning = false
    /// ピンチ中（距離もほぼ即座に合わせる）。
    var isPinching = false
    /// いま描いている注視点（sim 座標）と倍率（BattleWorld が毎フレーム書く。パン・ピンチの起点）。
    var renderedFocus: Vec2?
    var renderedZoom: Double = 1
    /// 自由カメラにする前に追っていたユニット（ダブルタップで戻る先）。
    var lastFollowedID: EntityID?

    init(controller: BattleController) {
        self.controller = controller
    }

    /// 手動のカメラ操作を自動カメラへ知らせる（しばらく控える）。
    func noteManualCameraInput() {
        director?.noteManualCameraInput()
    }

    /// 観戦者が一時停止メニューで倍率を変えた（HUDModel.syncSettings）。自動カメラは倍率を書き戻さない。
    func noteZoomSettingChanged() {
        director?.yieldZoom()
    }

    /// 自動カメラが手綱を握っている（有効で、手動操作の後で控えていない）。
    var isDirectorDriving: Bool {
        guard let director else { return false }
        return director.isActive && !director.isSuspended
    }

    /// 自動カメラが有効なら控えをやめてすぐ戻す。戻したら true。
    @discardableResult
    func resumeDirector() -> Bool {
        guard let director, director.isActive else { return false }
        director.resume()
        return true
    }

    private final class WeakLink {
        weak var link: SpectatorCameraLink?
        init(_ link: SpectatorCameraLink) { self.link = link }
    }

    private static var registry: [ObjectIdentifier: WeakLink] = [:]

    /// controller の窓口（描画側が持っている間は同じもの。無ければ作る）。
    static func link(for controller: BattleController) -> SpectatorCameraLink {
        let key = ObjectIdentifier(controller)
        if let existing = registry[key]?.link, existing.controller === controller { return existing }
        registry = registry.filter { $0.value.link?.controller != nil }
        let link = SpectatorCameraLink(controller: controller)
        registry[key] = WeakLink(link)
        return link
    }
}
