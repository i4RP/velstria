import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。構造物の合図（StructureCueEvent: 立ち上がり・損傷・倒壊・Core の崩壊）→ 既存の粒子・閃光・輪と効果音。
// 構造物の被弾（攻撃者に向いた側面の小さな火花と石の粉）もここ。
// - 画面付近（BattleWorld.nearCamera）の構造物だけ。粒子は VFXSystem のプール（重要でない扱い = 予算超過で省略）を使い、
//   新しい放出体・材質は作らない（輪・閃光の色はチームの明るい色 = 読み込み中に作り済みの色だけ）。
// - 大きな半透明を重ねない: 閃光は合図ごとに 1 つ・小さく、輪は Core の衝撃波だけ。短縮版の倒壊は粉塵を減らす。
// - 音: 画面付近の構造物だけ距離で弱めて鳴らし、0.6 秒に 3 つまで。地鳴りは試合開始で 1 回だけ（塔ごとに鳴らさない）。
//   2 倍速を超えると弱め、4 倍速を超えると鳴らさない（BattleAudioDirector と同じ考え）。シーク直後は合図自体が出ない。

/// 構造物の効果音の出口（BattleAudioDirector が開始時に AudioService へ繋ぐ。描画側は AppModel を持たないため）。
@MainActor
enum StructureAudio {
    static var sink: ((SFX, Double) -> Void)?
}

/// ヒーローのパッシブの音の出口（SkillFXDirector がパッシブの演出を出す時に呼ぶ。BattleAudioDirector が開始時に繋ぐ）。
/// 引数: ヒーローのユニット・ヒーロー ID。音量と左右は BattleAudioDirector が聞き手の位置から決める。
@MainActor
enum SkillFXAudio {
    static var passiveSink: ((EntityID, String) -> Void)?
}

@MainActor
final class StructureFXDirector {
    private let vfx: VFXSystem
    private let materials: RenderMaterials
    private var time: Float = 0
    private var recentSounds: [Float] = []
    private var riseRumblePlayed = false
    private var hitCount = 0
    /// 鳴らした音（テスト・確認用。直近 32 件）。
    private(set) var playedSounds: [SFX] = []
    /// 出した演出の合図（テスト・確認用。直近 64 件）。
    private(set) var playedCues: [TowerCue] = []

    /// 同時に鳴らす構造物の音の上限（soundWindow 秒あたり）。
    static let maxSoundsPerWindow = 3
    static let soundWindow: Float = 0.6
    /// 音が聞こえる距離（カメラの注視点から m）。
    static let hearing: Float = 30
    /// 石の粉・火花の色（加算で淡く光る灰色）。
    static let dustColor = UIColor(red: 0.74, green: 0.72, blue: 0.64, alpha: 1)
    /// 粉塵の煙（灰緑がかった石の粉。粒子の色は線形空間なので暗めに指定する。黒い煙にしない）。
    static let dustCloud = UIColor(red: 0.25, green: 0.24, blue: 0.2, alpha: 0.5)

    init(vfx: VFXSystem, materials: RenderMaterials) {
        self.vfx = vfx
        self.materials = materials
    }

    /// presentationEpoch の変化: 鳴らした音の記録を捨てる（地鳴りは試合で 1 回のまま）。
    func reset() {
        recentSounds.removeAll(keepingCapacity: true)
    }

    /// 合図 → 粒子・音。near = 画面付近か、listener = カメラの注視点（world x, z）、focus = 揺れの基準のヒーローの位置。
    /// 戻り値 = カメラの揺れ（近い時の着地・衝撃波だけ）。
    /// now = 描画の経過秒（BattleWorld.time。音の同時数の窓）。
    func play(_ events: [StructureCueEvent], now: Float, near: (SIMD3<Float>) -> Bool, listener: SIMD2<Float>,
              focus: SIMD3<Float>?, speed: Double) -> Float {
        time = now
        var shake: Float = 0
        for e in events {
            let close = near(e.position)
            if close || e.isCore { fx(e) }
            if let (sfx, base) = sound(e) {
                if e.cue == .riseStart {
                    // 地鳴りは試合開始で 1 回だけ（全ての塔が同時に立ち上がる）
                    guard !riseRumblePlayed else { continue }
                    riseRumblePlayed = true
                    emit(sfx, gain: base, speed: speed)
                } else if close || e.isCore {
                    let d = simd_distance(SIMD2(e.position.x, e.position.z), listener)
                    let g = base * Double(max(0, 1 - d / StructureFXDirector.hearing))
                    emit(sfx, gain: e.isCore ? max(g, base * 0.6) : g, speed: speed)
                }
            }
            if let focus {
                let d = simd_distance(SIMD2(focus.x, focus.z), SIMD2(e.position.x, e.position.z))
                switch e.cue {
                case .impact where d < 12: shake = max(shake, e.style == .full ? 0.3 : 0.18)
                case .crack where d < 10: shake = max(shake, 0.1)
                case .coreShockwave where d < 20: shake = max(shake, 0.45)
                case .coreArchesImpact where d < 16: shake = max(shake, 0.25)
                default: break
                }
            }
        }
        return shake
    }

    /// 構造物の被弾: 攻撃者に向いた側面に小さな火花（2 回に 1 回は石の粉も）。同時 2 つ・0.15 秒以内はまとめる（StructureVisual）。
    func hit(_ v: StructureVisual, attacker: SIMD3<Float>, time t: Float, near: Bool) {
        guard near, let p = v.hitPoint(toward: attacker, time: t) else { return }
        hitCount &+= 1
        vfx.spawn(.hitSpark, at: p, color: StructureFXDirector.dustColor, scale: 0.75, count: 6)
        if hitCount % 2 == 0 {
            vfx.spawn(.debris, at: p, color: .gray, scale: 0.3, count: 3)
        }
    }

    // MARK: 粒子

    private func fx(_ e: StructureCueEvent) {
        note(e.cue)
        let light = materials.teams.light(e.team)
        let team = light.uiColor
        let p = e.position
        let ground = SIMD3(p.x, 0.25, p.z)
        let full = e.style == .full
        switch e.cue {
        case .riseStart:
            // 基壇の継ぎ目から砂（紋様の点灯は材質の段階で出す）
            vfx.spawn(.smoke, at: p + SIMD3(0, 0.1, 0), color: StructureFXDirector.dustCloud, scale: 0.6)
        case .riseLock:
            vfx.spawn(.smoke, at: p, color: StructureFXDirector.dustCloud, scale: 0.35, count: 6)
            vfx.spawn(.hitSpark, at: p, color: StructureFXDirector.dustColor, scale: 0.6, count: 5)
        case .crystalIgnite:
            vfx.spawn(.magicHit, at: p, color: team, scale: 0.8)
            vfx.flash(at: p, color: light, radius: 0.9, duration: 0.3, alpha: 0.45)
        case .wisp:
            vfx.spawn(.death, at: p, color: team, scale: 0.55, count: 4)
        case .damaged:
            vfx.spawn(.debris, at: p, color: .gray, scale: 0.45, count: 6)
            vfx.spawn(.smoke, at: p, color: StructureFXDirector.dustCloud, scale: 0.4, count: 5)
        case .breakFlash:
            // 結晶の異常発光・破断箇所の粉塵（稼働光は材質で消える）
            vfx.flash(at: p, color: light, radius: full ? 1.3 : 0.9, duration: 0.25, alpha: 0.6)
            if full { vfx.spawn(.smoke, at: p - SIMD3(0, 1.2, 0), color: StructureFXDirector.dustCloud, scale: 0.5, count: 6) }
        case .crack:
            vfx.spawn(.debris, at: p, color: .gray, scale: 0.55, count: 8)
            vfx.spawn(.hitSpark, at: p, color: StructureFXDirector.dustColor, scale: 0.8, count: 8)
        case .toppleStart:
            vfx.spawn(.smoke, at: p, color: StructureFXDirector.dustCloud, scale: 0.55, count: 6)
        case .crystalShatter:
            // 割れた結晶からチームの魔力が小さく弾ける
            vfx.spawn(.magicHit, at: p, color: team, scale: full ? 1.3 : 0.9)
            if full { vfx.flash(at: p, color: light, radius: 0.9, duration: 0.25, alpha: 0.5) }
        case .separate:
            vfx.spawn(.debris, at: p, color: .gray, scale: 0.4, count: 5)
        case .crownImpact:
            vfx.spawn(.smoke, at: ground, color: StructureFXDirector.dustCloud, scale: 0.7, count: 6)
        case .impact:
            // 低く広がる粉塵と少しの破片（跳ね返りは無い）
            vfx.spawn(.smoke, at: ground, color: StructureFXDirector.dustCloud, scale: full ? 1.6 : 0.9, count: full ? 12 : 6)
            if full { vfx.spawn(.debris, at: ground, color: .gray, scale: 0.7, count: 10) }
        case .clearDebris:
            vfx.spawn(.smoke, at: ground, color: StructureFXDirector.dustCloud, scale: 0.5, count: 5)
        case .crystalFade:
            // 結晶片が光の粒になって消える
            vfx.spawn(.death, at: p, color: team, scale: 0.9, count: full ? 10 : 5)
        case .crumble:
            vfx.spawn(.smoke, at: ground, color: StructureFXDirector.dustCloud, scale: full ? 1.2 : 0.7, count: full ? 10 : 5)
        case .coreOverload:
            // 閃光の球は大結晶を包む大きさまで（台座に食い込むと台座全体が色の付いた円盤に見える）
            vfx.flash(at: p, color: light, radius: 1.5, duration: 0.45, alpha: 0.45)
            vfx.spawn(.magicHit, at: p, color: team, scale: 1.6, important: true)
        case .coreArchesFall:
            vfx.spawn(.smoke, at: p + SIMD3(0, 0.3, 0), color: StructureFXDirector.dustCloud, scale: 1.5, important: true)
        case .coreArchesImpact:
            vfx.spawn(.smoke, at: ground, color: StructureFXDirector.dustCloud, scale: 2.2, important: true)
            vfx.spawn(.debris, at: ground + SIMD3(0, 0.5, 0), color: .gray, scale: 1.3, important: true)
        case .coreImplode:
            vfx.flash(at: p, color: light, radius: 1.9, duration: 0.4, alpha: 0.6)
            vfx.spawn(.towerExplosion, at: p, color: team, scale: 1.3, important: true)
        case .coreShockwave:
            vfx.ring(at: SIMD3(p.x, 0, p.z), color: light, from: 2, to: 15, duration: 0.9, alpha: 0.8)
            vfx.spawn(.smoke, at: ground, color: StructureFXDirector.dustCloud, scale: 2.0, important: true)
        case .coreSettle:
            vfx.spawn(.smoke, at: ground, color: StructureFXDirector.dustCloud, scale: 1.2)
        }
    }

    // MARK: 音

    /// 合図 → 効果音と基本の音量（nil = 鳴らさない）。
    func sound(_ e: StructureCueEvent) -> (SFX, Double)? {
        switch e.cue {
        case .riseStart: return (.towerRise, 0.75)
        case .riseLock: return (.towerLock, 0.7)
        case .crack: return (.towerCrack, 0.8)
        case .toppleStart: return (.towerCollapse, 0.85)
        case .impact: return (.towerImpact, e.style == .full ? 0.9 : 0.6)
        case .crystalFade: return (.crystalFade, 0.6)
        case .coreOverload: return (.towerCrack, 1)
        case .coreArchesFall: return (.towerCollapse, 1)
        case .coreArchesImpact: return (.towerImpact, 0.9)
        case .coreImplode: return (.crystalFade, 1)
        case .coreShockwave: return (.towerImpact, 1)
        default: return nil
        }
    }

    private func emit(_ sfx: SFX, gain: Double, speed: Double) {
        guard gain > 0.05, speed <= BattleAudioDirector.dropAboveSpeed else { return }
        recentSounds.removeAll { time - $0 > StructureFXDirector.soundWindow }
        guard recentSounds.count < StructureFXDirector.maxSoundsPerWindow else { return }
        recentSounds.append(time)
        let g = speed > BattleAudioDirector.dampenAboveSpeed ? gain * BattleAudioDirector.dampenedGain : gain
        playedSounds.append(sfx)
        if playedSounds.count > 32 { playedSounds.removeFirst(playedSounds.count - 32) }
        StructureAudio.sink?(sfx, min(1, g))
    }

    private func note(_ cue: TowerCue) {
        playedCues.append(cue)
        if playedCues.count > 64 { playedCues.removeFirst(playedCues.count - 64) }
    }
}
