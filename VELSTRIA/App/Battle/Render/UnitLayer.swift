import Foundation
import RealityKit
import VelstriaCore

// 担当: battle-renderer。units 配列 → 見た目の同期。ミニオン・モンスター・人形はキー別プールで再利用する。
// 列から消えたユニット（撃破で除去）は死亡演出の後にプールへ戻す。

@MainActor
final class UnitLayer {
    let root = Entity()
    private let materials: RenderMaterials
    private let meshes: UnitMeshLibrary
    private let structureMeshes = StructureMeshes()
    private let text: TextMeshCache
    private let master: MasterData

    private(set) var heroes: [EntityID: HeroVisual] = [:]
    private var heroList: [HeroVisual] = []
    private(set) var structures: [EntityID: StructureVisual] = [:]
    private var structureList: [StructureVisual] = []
    private var creatures: [EntityID: CreatureVisual] = [:]
    private var activeCreatures: [CreatureVisual] = []
    private var dying: [CreatureVisual] = []
    private var pools: [CreatureKey: [CreatureVisual]] = [:]
    private var stamp = 0
    private var selfHeroID: EntityID?

    init(materials: RenderMaterials, meshes: UnitMeshLibrary, text: TextMeshCache, master: MasterData) {
        self.materials = materials
        self.meshes = meshes
        self.text = text
        self.master = master
        root.name = "units"
        activeCreatures.reserveCapacity(128)
        dying.reserveCapacity(32)
    }

    var liveCount: Int { heroList.count + structureList.count + activeCreatures.count + dying.count }

    /// 事前生成（既定: 試合開始時のミニオン 1 波ぶん + 余裕。試合では BattleWorld のウォームアップが
    /// creaturePoolSizes の数まで作る）。
    func prewarm() {
        for team in Team.players {
            for (type, n) in [(MinionType.melee, 10), (.ranged, 10), (.siege, 3)] { prewarm(.minion(type, team), count: n) }
        }
    }

    /// key のプールが count 体になるまで作る（無効のまま。状態表示・HP バーも含めて全て作る）。
    func prewarm(_ key: CreatureKey, count: Int) {
        var have = pools[key]?.count ?? 0
        while have < count {
            recycle(make(key))
            have += 1
        }
    }

    /// プールに待機中の数（テスト・計測用）。
    func pooledCount(_ key: CreatureKey) -> Int { pools[key]?.count ?? 0 }

    /// 試合で必要になりうるクリーチャーの見た目の数（読み込み幕の裏で作り切る）。
    /// - ミニオン: 進軍が止まったレーンに波が溜まる・死亡演出（0.9 秒）の重なり・10:00 以降の近接 +1 を含む実測の最大
    ///   （観戦 8 試合・各 12〜21 分の headless 計測で近接 33・遠隔 34・攻城 6 / チーム）に余裕を足した数。
    /// - モンスター: 地図のキャンプ構成どおり（再出現は 60 秒以上後なので死亡演出と重ならない）。
    /// - 人形: 練習モードの配置数 + 1（撃破 → 4 秒後の再出現と死亡演出の重なり）。
    static func creaturePoolSizes(map: MapDefinition, dummySpots: Int) -> [(key: CreatureKey, count: Int)] {
        var out: [(key: CreatureKey, count: Int)] = []
        for team in Team.players {
            out.append((.minion(.melee, team), minionPool.melee))
            out.append((.minion(.ranged, team), minionPool.ranged))
            out.append((.minion(.siege, team), minionPool.siege))
        }
        var monsters: [MonsterKind: Int] = [:]
        for camp in map.camps {
            for m in SpawnSystem.campMembers(camp.kind) { monsters[m.kind, default: 0] += 1 }
        }
        for kind in monsters.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            out.append((.monster(kind), monsters[kind] ?? 0))
        }
        if dummySpots > 0 { out.append((.dummy, dummySpots + 1)) }
        return out
    }

    /// ミニオンのプール（チームあたり）。
    static let minionPool = (melee: 36, ranged: 36, siege: 8)

    // MARK: ウォームアップ（読み込み幕の裏）

    private var warmupSamples: [CreatureVisual] = []

    /// 各種類の見た目を 2 体ずつ（不透明と半透明）プールから借りて陳列し、状態表示も全て出す。
    func showWarmupSamples(slot: () -> SIMD3<Float>) {
        for key in pools.keys.sorted(by: { "\($0)" < "\($1)" }) {
            for opacity: Float in [1, 0.5] {
                guard var list = pools[key], let v = list.popLast() else { break }
                pools[key] = list
                v.showForWarmup(at: slot(), opacity: opacity)
                warmupSamples.append(v)
            }
        }
    }

    /// 陳列した見た目をプールへ戻す。
    func endWarmup() {
        for v in warmupSamples { recycle(v) }
        warmupSamples.removeAll()
    }

    /// 構造物のメッシュ（陳列用）。
    var structureMeshList: [MeshResource] { structureMeshes.builtMeshes }

    private func make(_ key: CreatureKey) -> CreatureVisual {
        AssetLedger.record(.entity, "creature \(key)")
        let v = CreatureVisual(key: key, meshes: meshes, materials: materials, text: text)
        v.root.isEnabled = false
        root.addChild(v.root)
        return v
    }

    private func take(_ key: CreatureKey) -> CreatureVisual {
        if var list = pools[key], let v = list.popLast() {
            pools[key] = list
            return v
        }
        return make(key)
    }

    private func recycle(_ v: CreatureVisual) {
        v.deactivate()
        pools[v.key, default: []].append(v)
    }

    func creature(_ id: EntityID) -> CreatureVisual? { creatures[id] }
    func hero(_ id: EntityID) -> HeroVisual? { heroes[id] }
    func structure(_ id: EntityID) -> StructureVisual? { structures[id] }

    /// 表示中のユニットの頭上高さ（VFX の位置合わせ）。
    func headHeight(_ id: EntityID) -> Float {
        if let h = heroes[id] { return h.handle.overheadHeight }
        if let c = creatures[id] { return c.headHeight }
        if let s = structures[id] { return s.muzzleHeight }
        return 1.2
    }

    // MARK: 同期

    func sync(_ f: RenderFrame) {
        stamp &+= 1
        let state = f.state
        let viewerHero = f.humanID.flatMap { state.index(of: $0) }
        let viewerPos = viewerHero.map { state.units[$0].pos }
        let focusWorld = f.focusID.flatMap { heroes[$0]?.root.position }
        for i in state.units.indices {
            let kind = state.units[i].kind
            let id = state.units[i].id
            switch kind {
            case .hero:
                let v: HeroVisual
                if let h = heroes[id] {
                    v = h
                } else {
                    v = HeroVisual(unit: state.units[i], isSelf: id == f.humanID, master: master, materials: materials,
                                   meshes: meshes, text: text)
                    heroes[id] = v
                    heroList.append(v)
                    root.addChild(v.root)
                }
                v.update(f, index: i, visible: f.isVisible(i))
            case .tower, .core:
                let v: StructureVisual
                if let s = structures[id] {
                    v = s
                } else {
                    v = StructureVisual(unit: state.units[i], meshes: structureMeshes, unitMeshes: meshes, materials: materials,
                                        text: text)
                    structures[id] = v
                    structureList.append(v)
                    root.addChild(v.root)
                }
                var showRange = false
                if let vp = viewerPos, let viewer = f.viewerTeam, state.units[i].team != viewer, state.units[i].isAlive,
                   let hi = viewerHero, state.units[hi].hero?.isDead == false {
                    let reach = (kind == .core ? Balance.coreRange : Balance.towerRange) + 350
                    showRange = vp.distanceSquared(to: state.units[i].pos) < reach * reach
                }
                let occluding = focusWorld.map { v.occludes($0) } ?? false
                v.update(f, index: i, showRange: showRange, occluding: occluding)
            case .minion, .monster, .dummy:
                let v: CreatureVisual
                if let c = creatures[id] {
                    v = c
                } else {
                    guard state.units[i].isAlive, let key = CreatureKey(state.units[i]) else { continue }
                    v = take(key)
                    v.activate(id: id, at: state.units[i].pos, facing: state.units[i].facing)
                    creatures[id] = v
                    activeCreatures.append(v)
                }
                v.lastSeen = stamp
                v.update(f, index: i, visible: f.isVisible(i) && state.units[i].isAlive)
            }
        }
        // 列から消えたクリーチャー → 死亡演出へ
        var k = 0
        while k < activeCreatures.count {
            let v = activeCreatures[k]
            if v.lastSeen != stamp {
                creatures[v.id] = nil
                activeCreatures.swapAt(k, activeCreatures.count - 1)
                activeCreatures.removeLast()
                if v.visibility > 0.05 {
                    v.beginDying()
                    dying.append(v)
                } else {
                    recycle(v)
                }
            } else {
                k += 1
            }
        }
        k = 0
        while k < dying.count {
            if dying[k].updateDying(dt: f.dt) {
                let v = dying[k]
                dying.swapAt(k, dying.count - 1)
                dying.removeLast()
                recycle(v)
            } else {
                k += 1
            }
        }
    }

    // MARK: イベント

    func noteAttack(sourceID: EntityID, time: Float) {
        if let c = creatures[sourceID] { c.beginAttack() } else if let h = heroes[sourceID] { h.noteAttack(time: time) }
    }

    func noteHit(targetID: EntityID) {
        creatures[targetID]?.hit()
    }

    func noteCast(heroID: EntityID, slot: SkillSlot, time: Float) {
        heroes[heroID]?.noteCast(slot, time: time)
    }

    /// 現在の見た目の world 位置（未表示なら nil）。
    func worldPositionOf(_ id: EntityID) -> SIMD3<Float>? {
        if let h = heroes[id] { return h.root.position }
        if let c = creatures[id] { return c.root.position }
        if let s = structures[id] { return s.root.position }
        return nil
    }

    func teardown() {
        root.removeFromParent()
        heroes.removeAll()
        heroList.removeAll()
        structures.removeAll()
        structureList.removeAll()
        creatures.removeAll()
        activeCreatures.removeAll()
        dying.removeAll()
        pools.removeAll()
    }
}
