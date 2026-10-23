import Foundation
import RealityKit
import VelstriaCore

/// 同じスキルを連続で押しても、押すたびに先頭から再生する。
struct HeroSkillPreviewRequest: Equatable {
    let skillID: String
    let id = UUID()
}

/// 展示中の 1 体だけに、戦闘と同じモーション・演出を再生する。
/// タイマーや戦闘シミュレーションは作らず、HeroStageDriver の更新に乗せる。
@MainActor
final class HeroSkillPreviewPlayback {
    let player = SkillFXPlayer(quality: .preset(.medium))
    private let model: any HeroDisplayModel
    private let master = MasterData.shared
    private let palette: FXPalette
    private var recipes: [SkillSlot: SkillFXRecipe] = [:]
    private var elapsed: Float = 0
    private var motionEnd: Float = 0
    private var impactAt: Float?
    private var slot: SkillSlot?
    private var target = SIMD3<Float>.zero
    private var projectile = false
    private var materialsReady = false
    private(set) var isPlaying = false
    /// 長いバフも展示ではここで打ち切る。連打では前の予約と粒子を先に消す。
    static let duration: Float = 4

    init(model: any HeroDisplayModel, parent: Entity) {
        self.model = model
        palette = SkillFXCatalog.palette(model.heroID)
        if FXPrograms.prewarmsOnThisDevice { FXPrograms.prewarm() }
        for slot in SkillSlot.allCases {
            recipes[slot] = SkillFXCatalog.recipe(heroID: model.heroID, slot: slot, master: master)
        }
        player.prewarm(recipes: SkillSlot.allCases.compactMap { slot in
            recipes[slot].map { (palette, $0) }
        })
        player.root.position = model.root.position
        player.root.isEnabled = false
        parent.addChild(player.root)
        // 座標は展示台のローカル。親の回転でヒーローと演出を一緒に回す。
        player.resolve = { [weak self] follow in
            guard let self else { return nil }
            switch follow {
            case .unit: return .zero
            case .projectile:
                guard self.projectile else { return nil }
                let progress = min(1, max(0, (self.elapsed - 0.12) / 0.45))
                return self.target * progress
            }
        }
    }

    func play(_ request: HeroSkillPreviewRequest) {
        guard let skill = master.skill(request.skillID), skill.heroID == model.heroID,
              let recipe = recipes[skill.slot] else { return }
        stop()
        elapsed = 0
        slot = skill.slot
        isPlaying = true
        player.root.isEnabled = true
        let info = SkillFXCatalog.info(heroID: model.heroID, slot: skill.slot, master: master)
        // 広い攻撃も台座付近で見られるよう水平範囲を縮める。手元の光の高さは保つ。
        let scale = min(1, max(0.25, 1.3 / info.radius))
        player.root.scale = [scale, 1, scale]
        switch info.archetype {
        case .passive, .selfAoE, .multiStrike, .teamHeal: target = .zero
        default: target = [0, 0, -min(info.range, 0.9 / scale)]
        }
        if skill.slot == .passive {
            // パッシブは詠唱ではなく通常攻撃と発動の演出で見せる。
            model.playAttack(windup: 0.2, interval: 0.8, empowered: true)
            motionEnd = 0.8
            impactAt = 0.2
        } else {
            model.playCast(skill.slot, stage: 0)
            motionEnd = model.castDuration(skill.slot) + 0.15
        }

        let caster = context(origin: .zero, follow: .unit(1))
        let impact = context(origin: target)
        player.play(recipe.cast, caster)
        switch info.archetype {
        case .passive:
            break
        case .cone, .selfAoE, .teamHeal:
            player.play(recipe.impact, caster)
        case .blinkEmpower, .targetedBlink:
            impactAt = 0.2
            play(recipe.impact, at: 0.2, context: impact)
        case .lineSkillshot, .piercingLine:
            projectile = true
            impactAt = 0.57
            play(recipe.travel, at: 0.12, context: context(origin: .zero, follow: .projectile(2)))
            play(recipe.impact, at: 0.57, context: impact)
        case .dashStrike, .leapSlam, .groundAoE, .healZone:
            let delay: Float = info.archetype == .dashStrike ? 0.25 : (info.archetype == .leapSlam ? 0.34 : 0.6)
            impactAt = delay
            player.play(recipe.telegraph, impact)
            play(recipe.impact, at: delay, context: impact)
        case .multiStrike:
            for i in 0..<3 {
                var hit = caster
                hit.variant = i
                play(recipe.impact, at: Float(i) * 0.3, context: hit)
            }
        }
    }

    private func context(origin: SIMD3<Float>, follow: SkillFXPlayer.Follow? = nil) -> SkillFXPlayer.Context {
        SkillFXPlayer.Context(palette: palette, origin: origin, caster: .zero, target: target,
                              forward: [0, 0, -1], follow: follow,
                              source: slot.map { SkillFXPlayer.Source(heroID: model.heroID, slot: $0, stage: 0) })
    }

    private func play(_ cues: [FXCue], at delay: Float, context: SkillFXPlayer.Context) {
        player.play(cues.map { cue in
            var cue = cue
            cue.at += delay
            return cue
        }, context)
    }

    func update(dt: Float) {
        if !materialsReady { materialsReady = player.prewarmShaded() }
        guard isPlaying else { return }
        elapsed += dt
        if let impactAt, elapsed >= impactAt, let slot {
            if slot == .passive {
                model.synchronizeAttackRelease()
            } else if let recovery = model.playCastHit(slot) {
                motionEnd = max(motionEnd, elapsed + recovery)
            }
            self.impactAt = nil
        }
        if elapsed >= motionEnd { model.setState(.idle) }
        player.update(dt: dt)
        if elapsed >= Self.duration { stop() }
    }

    func stop() {
        player.clear()
        player.root.isEnabled = false
        if isPlaying { model.setState(.idle) }
        isPlaying = false
        slot = nil
        impactAt = nil
        projectile = false
    }
}
