import Foundation

// 担当: core-combat（検証用。docs/vfx/RANGES.md）。1 つのスキルを練習場の配置（App の演出チェック・比較撮影と同じ:
// 人形の南 4 m に北向き）で実際の入力（castSkill）で撃ち、判定の形（HitShapeProbe）と、演出の段の合図になるイベント
// （発動・ゾーン・弾・ダメージ）と位置を時刻つきで集める。App の演出の範囲の検査（FXRangeAudit）と Core のテストが使う。
// sim の規則は変えない（置き直しは状態の書き換え、撃つのは通常の入力）。受け口は呼んでいる間だけ置き、元に戻す。

/// 1 つのスキルを撃って集めた判定の形とイベント（時刻は sim の秒）。
public struct HitShapeTrace: Sendable {
    public struct Sample: Hashable, Sendable {
        public var time: Double
        public var pos: Vec2
    }

    public struct Mark: Hashable, Sendable {
        public var time: Double
        public var event: SimEvent
    }

    public var heroID: String
    public var slot: SkillSlot
    public var casterID: EntityID
    /// 撃った先（人形・敵の英雄）。
    public var targetID: EntityID
    /// この術者の発動（skillCast。再使用の段も）。
    public var casts: [Mark] = []
    /// この術者の判定のうち、source が slot のスキルのもの。
    public var shapes: [HitShape] = []
    /// この術者のゾーンの発生・発動、弾の発射・命中、スキルのダメージ。
    public var events: [Mark] = []
    /// 術者・撃った先の位置（tick ごと）と、この術者の弾の位置（弾の ID ごと）。
    public var caster: [Sample] = []
    public var target: [Sample] = []
    public var projectiles: [EntityID: [Sample]] = [:]

    /// samples のうち、時刻 t に最も近い標本の位置（無ければ nil）。
    public static func position(_ samples: [Sample], at t: Double) -> Vec2? {
        guard !samples.isEmpty else { return nil }
        var best = samples[0]
        for s in samples where abs(s.time - t) < abs(best.time - t) { best = s }
        return best.pos
    }
}

public enum HitShapeScenario {
    /// 人形からヒーローを置く距離（App の FXCheckDriver.standoff と同じ 4 m）。
    public static let standoff = 400.0
    /// 英雄にだけ撃てるスキルの的（敵の英雄）を置く、ヒーローの前の距離（掴み・対象指定の射程に入る 1.5 m）。
    public static let foeDistance = 150.0
    /// 置き直してから撃つまで（sim の秒）。
    public static let settle = 0.3

    /// heroID の slot を撃つ。recastAfter 秒後に同じ入力（再使用の段）をもう一度送る。targetsHero = 敵の英雄へ撃つ
    /// （無ければ人形）。seconds 秒（最初の発動から）集める。設定・配置が作れなければ nil。
    public static func run(heroID: String, slot: SkillSlot, recastAfter: Double? = nil, targetsHero: Bool = false,
                           seconds: Double = 3, master: MasterData = .shared) -> HitShapeTrace? {
        guard master.hero(heroID) != nil else { return nil }
        // 練習場（クールダウン無し・ミニオン無し・Lv4・スキルは自動習得。App の演出チェックと同じ）+ 敵の英雄 1 体
        let options = PracticeOptions(noCooldowns: true, spawnMinions: false, spawnDummies: true, startLevel: 4)
        var config = MatchFactory.practiceMatch(humanHeroID: heroID, humanName: "Probe", options: options, seed: 1,
                                                master: master)
        let foeHero = heroID == "H029" ? "H034" : "H029"
        config.players.append(PlayerSlot(team: .red, heroID: foeHero, controller: .bot, position: .mid,
                                         displayName: "Foe", botDifficulty: .easy))
        let sim = Simulation(config: config, master: master, map: MapDefinition.map(for: config.mode))
        // 開始の処理（開始レベル・自動習得）を済ませる
        for _ in 0..<10 { sim.step() }
        var s = sim.state
        guard let me = s.units.firstIndex(where: { $0.kind == .hero && $0.hero?.controller == .human }) else {
            return nil
        }
        let p0 = s.units[me].pos
        guard let dummy = s.units.indices.filter({ s.units[$0].kind == .dummy && s.units[$0].isAlive })
            .min(by: { s.units[$0].pos.distance(to: p0) < s.units[$1].pos.distance(to: p0) }) else { return nil }
        let team = s.units[me].team
        guard let foe = s.units.firstIndex(where: { $0.kind == .hero && $0.team != team }) else { return nil }
        // 置き直し: 人形の南 standoff に北向き。敵の英雄はヒーローの前（人形との間）に南向きで立たせ、操作を人間扱いにする
        // （入力が無いので動かない）
        let spot = s.units[dummy].pos + Vec2(0, -standoff)
        place(&s, me, at: spot, facing: Double.pi / 2)
        let foeSpot = targetsHero ? spot + Vec2(0, foeDistance) : s.units[dummy].pos + Vec2(standoff, 0)
        place(&s, foe, at: foeSpot, facing: -Double.pi / 2)
        s.units[foe].hero?.controller = .human
        s.units[dummy].hp = s.units[dummy].stats.maxHP
        sim.restore(from: s)
        for _ in 0..<Int((settle / Balance.dt).rounded()) { sim.step() }

        let myID = sim.state.units[me].id
        let targetID = targetsHero ? sim.state.units[foe].id : sim.state.units[dummy].id
        var trace = HitShapeTrace(heroID: heroID, slot: slot, casterID: myID, targetID: targetID)
        final class Box { var shapes: [HitShape] = [] }
        let box = Box()
        let previous = HitShapeProbe.sink
        HitShapeProbe.sink = { shape in
            if shape.sourceID == myID, shape.source == .skill(slot) { box.shapes.append(shape) }
        }
        defer { HitShapeProbe.sink = previous }

        let command = HeroCommand(heroID: myID, command: .castSkill(slot: slot, target: .unit(targetID)))
        let t0 = sim.state.time
        var recastSent = recastAfter == nil
        var zones = Set<EntityID>()
        var shots = Set<EntityID>()
        let ticks = Int((seconds / Balance.dt).rounded())
        for k in 0...ticks {
            var commands: [HeroCommand] = []
            if k == 0 { commands.append(command) }
            if !recastSent, let r = recastAfter, sim.state.time + Balance.dt - t0 >= r {
                commands.append(command)
                recastSent = true
            }
            let events = sim.step(commands: commands)
            let st = sim.state
            let now = st.time
            for e in events {
                switch e {
                case .skillCast(let c) where c.casterID == myID:
                    trace.casts.append(.init(time: now, event: e))
                case .zoneCreated(let id, let owner, _, _, _, _, _, _, _) where owner == myID:
                    zones.insert(id)
                    trace.events.append(.init(time: now, event: e))
                case .zoneTriggered(let id, _, _) where zones.contains(id):
                    trace.events.append(.init(time: now, event: e))
                case .projectileLaunched(let id, let owner, _) where owner == myID:
                    shots.insert(id)
                    trace.events.append(.init(time: now, event: e))
                case .projectileHit(let id, _, _) where shots.contains(id):
                    trace.events.append(.init(time: now, event: e))
                case .damage(let d) where d.sourceID == myID && d.source == .skill(slot):
                    trace.events.append(.init(time: now, event: e))
                default:
                    break
                }
            }
            if let i = st.index(of: myID) { trace.caster.append(.init(time: now, pos: st.units[i].pos)) }
            if let i = st.index(of: targetID) { trace.target.append(.init(time: now, pos: st.units[i].pos)) }
            for p in st.projectiles where p.ownerID == myID {
                trace.projectiles[p.id, default: []].append(.init(time: now, pos: p.pos))
            }
            if st.phase == .ended { break }
        }
        trace.shapes = box.shapes
        return trace
    }

    private static func place(_ s: inout SimState, _ i: Int, at p: Vec2, facing: Double) {
        s.units[i].pos = p
        s.units[i].prevPos = p
        s.units[i].path.removeAll()
        s.units[i].moveIntent = .none
        s.units[i].facing = facing
        s.units[i].hp = s.units[i].stats.maxHP
        s.units[i].resource = s.units[i].stats.maxResource
    }
}
