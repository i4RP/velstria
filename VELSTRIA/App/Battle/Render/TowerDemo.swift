#if DEBUG
import Foundation
import VelstriaCore

// 担当: battle-renderer。DEBUG 専用: 塔・Star Core の一生を 1 基で繰り返す（起動引数 -towerDemo <outer|inner|base|core>。
// 動画の撮影・見た目の確認用）。立ち上がり → 待機・攻撃（前隙の溜めと弾）・被弾 → 損傷 1 → 損傷 2 → 倒壊 → 瓦礫 → 整理 → 最初から。
// RenderShowcase と同じく描画フレームの SimState の写しだけを書き換える（sim には一切書き込まない）。
// 演出時刻はこの 1 基だけ差し替える（UnitLayer.demoClock）。他の塔・試合の進行はそのまま。
// 対象: 塔 = 青の mid レーンのその段の塔、core = 赤の Star Core。
// カメラ（-stageCam x,y[,zoom]。地図座標 m。tools/stage/stage_shots.sh の位置引数と同じ）:
// 塔の位置（地図座標）は外塔 (46.6, 49.9)・内塔 (33.9, 37.1)・基地塔 (24.0, 24.0)・赤の Core (107.5, 107.5)。
// 注視点を 1 m 北（y + 1）へずらすと塔の全体が HUD の上に収まる:
//   青の mid 外塔   46.6,51.0,0.8    例: tools/stage/stage_shots.sh <UDID> build/tower 46.6,51.0,0.8 -- -towerDemo outer
//   青の mid 内塔   33.9,38.1,0.8
//   青の mid 基地塔 24.0,25.0,0.8
//   赤の Star Core  107.5,108.5,1.0  例: tools/stage/stage_shots.sh <UDID> build/core 107.5,108.5,1.0 -- -towerDemo core
// 動画: xcrun simctl io <UDID> recordVideo build/tower.mov（-stageCam を付けて起動した後に録る）。
// -towerDemoAt <秒> を足すと演出時刻をその値に止める（姿勢は時刻だけで決まるので、その瞬間の姿を撮れる。粒子は出ない）。

@MainActor
final class TowerDemo {
    enum Target: String {
        case outer, inner, base, core
    }

    static var requested: Target? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-towerDemo") else { return nil }
        return i + 1 < args.count ? Target(rawValue: args[i + 1]) ?? .outer : .outer
    }

    /// -towerDemoAt <秒>: 演出時刻を止める値。
    static let heldTime: Double? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-towerDemoAt"), i + 1 < args.count else { return nil }
        return Double(args[i + 1])
    }()

    // 時刻表（演出時刻 = この 1 基の秒）
    /// 最初の暗転（沈んだ姿）。
    static let start: Double = -0.8
    /// 攻撃と被弾を始める（立ち上がりの後）。
    static let combatStart: Double = TowerTimeline.riseEnd + 0.6
    /// 損傷 1（HP 55%）・損傷 2（HP 25%）・破壊。
    static let damage1At: Double = 6.5
    static let damage2At: Double = 9.5
    static let deathAt: Double = 13.0
    /// 攻撃の周期・前隙・弾の飛ぶ秒。
    static let attackPeriod: Double = 1.2
    static let windup: Double = 0.45
    static let flight: Double = 0.35

    let target: Target
    private(set) var clock: Double = TowerDemo.start
    private(set) var towerID: EntityID?
    /// このフレームの被弾（攻撃者の world 位置）。BattleWorld が StructureFXDirector.hit へ渡す。
    private(set) var hits: [SIMD3<Float>] = []
    private var lastHit: Double = -10

    init(target: Target) {
        self.target = target
    }

    /// 1 周の長さ（倒壊の後、瓦礫の整理まで見せてから最初へ）。
    var period: Double { TowerDemo.deathAt + (target == .core ? CoreCollapse.settled + 3.0 : TowerTimeline.clearEnd + 1.6) }

    func apply(_ f: inout RenderFrame, units: UnitLayer) {
        if let held = TowerDemo.heldTime {
            clock = held
        } else {
            clock += Double(f.dt)
            if clock >= period {
                clock = TowerDemo.start
                lastHit = -10
            }
        }
        hits.removeAll(keepingCapacity: true)
        guard let i = targetIndex(f.state) else { return }
        let id = f.state.units[i].id
        towerID = id
        units.demoClock = (id, clock)
        let maxHP = f.state.units[i].stats.maxHP
        if clock < TowerDemo.deathAt {
            f.state.units[i].isAlive = true
            f.state.units[i].deathTime = nil
            let ratio = clock < TowerDemo.damage1At ? 1.0 : clock < TowerDemo.damage2At ? 0.55 : 0.25
            f.state.units[i].hp = maxHP * ratio
            f.state.units[i].windupRemaining = nil
            guard clock >= TowerDemo.combatStart else { return }
            // 攻撃: 前隙の間に紋様と結晶が明るくなり（sim と同じ windupRemaining）、終わりに弾が出る
            let k = (clock - TowerDemo.combatStart).truncatingRemainder(dividingBy: TowerDemo.attackPeriod)
            let total = CombatSystem.attackInterval(f.state.units[i].stats) * Balance.attackWindupRatio
            let attacker = f.state.units[i].pos + Vec2(420, -380)
            if k < TowerDemo.windup {
                f.state.units[i].windupRemaining = max(0.001, (1 - k / TowerDemo.windup) * total)
            } else if k < TowerDemo.windup + TowerDemo.flight {
                let u = (k - TowerDemo.windup) / TowerDemo.flight
                let from = f.state.units[i].pos
                let d = (attacker - from).normalized
                var p = Projectile(id: 900_301, ownerID: id, team: f.state.units[i].team, pos: Vec2.lerp(from, attacker, u),
                                   motion: .linear(direction: d, maxDistance: from.distance(to: attacker)),
                                   speed: from.distance(to: attacker) / TowerDemo.flight,
                                   payload: HitPayload(damage: 0, damageType: .physical, source: .tower), visual: "tower_shot")
                p.prevPos = p.pos
                f.state.projectiles.append(p)
            }
            // 被弾: 攻撃者（塔の南東）の側に 0.4 秒ごと
            if clock - lastHit >= 0.4 {
                lastHit = clock
                hits.append(worldPosition(attacker))
            }
        } else {
            f.state.units[i].isAlive = false
            f.state.units[i].hp = 0
            f.state.units[i].deathTime = TowerDemo.deathAt
            f.state.units[i].windupRemaining = nil
        }
    }

    private func targetIndex(_ s: SimState) -> Int? {
        if let towerID, let i = s.index(of: towerID) { return i }
        switch target {
        case .core:
            return s.units.indices.first { s.units[$0].kind == .core && s.units[$0].team == .red }
        case .outer, .inner, .base:
            let tier: TowerTier = target == .outer ? .outer : target == .inner ? .inner : .base
            return s.units.indices.first {
                s.units[$0].kind == .tower && s.units[$0].team == .blue && s.units[$0].tower?.lane == .mid
                    && s.units[$0].tower?.tier == tier
            }
        }
    }
}
#endif
