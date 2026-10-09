import Foundation
import RealityKit
import UIKit
import VelstriaCore

// 担当: battle-renderer。読み込み幕の裏の準備（BattleWorld.makeWarmupPlan）と片付け（finishWarmup）。
//
// AAA の作り方と同じく「試合で使う可能性のあるものは、幕が上がる前にすべて一度作って一度描く」:
// 1. 作る: クリーチャー（ミニオン・モンスター・人形）・投射物・ゾーン・状態表示・放出体・輪/閃光の各プールを
//    試合の最大数まで、メッシュ（ゾーン・照準の射程リングの半径ごと）・文字（レベル・名前）・単色マテリアル（全色）も全て。
// 2. 描く: WarmupGallery をカメラの注視点に開き、全マテリアル（半透明の変種込み）・全メッシュ・全粒子プリセット・
//    全ヒーローを一度ずつ描いてパイプラインと GPU 転送を済ませる。
// 3. 片付ける: finishWarmup で借りたものをプールへ戻し、陳列を外す（BattleRenderer が幕を上げる直前に呼ぶ）。
// 重い段（heavy）は 1 フレームに 1 つ実行される（Perf/WarmupPlan.swift）。プレイ中（幕の後）は何も作らない
// （AssetLedger の live が 0。RenderWarmupTests で試合を進めて検査する）。

extension BattleWorld {
    /// 1 段で作るクリーチャーの見た目の数（1 体 ≒ 18 エンティティ）。
    static let creaturesPerStep = 12
    /// ゾーンの見た目のプール（同時表示の実測最大 6 + 余裕）。
    static let zonePoolSize = 12

    /// 読み込み幕の裏で行う準備（Perf/WarmupPlan.swift）。BattleRenderer が順に実行し、
    /// 陳列を数フレーム描いてから finishWarmup → 幕を上げる。
    func makeWarmupPlan() -> [WarmupStep] {
        var steps: [WarmupStep] = []
        // ヒーロー・構造物（最初の同期で作られるもの）を先に作る。名前の文字・バーのマテリアルもここで出来る
        steps.append(WarmupStep("units", heavy: true) { [weak self] in self?.warmUnits() })
        steps.append(WarmupStep("meshes.common") { [weak self] in
            guard let self else { return }
            self.meshes.prewarmCommon()
            _ = self.meshes.centeredQuad
            _ = self.materials.contactShadow
        })
        // クリーチャーのプール（種類ごと・12 体ずつ）
        let dummySpots = controller.state.world.dummySpots.count
        for (key, count) in UnitLayer.creaturePoolSizes(map: controller.ctx.map, dummySpots: dummySpots) {
            var made = 0
            while made < count {
                let target = min(count, made + BattleWorld.creaturesPerStep)
                steps.append(WarmupStep("creatures \(key) \(target)/\(count)", heavy: true) { [weak self] in
                    self?.units.prewarm(key, count: target)
                })
                made = target
            }
        }
        steps.append(WarmupStep("projectiles", heavy: true) { [weak self] in
            guard let self else { return }
            for p in ProjectileLayer.plannedStyles(state: self.controller.state, master: self.controller.ctx.master) {
                self.projectiles.prewarm(p.style, visual: p.visual, count: p.count)
            }
            self.projectiles.prewarmTrails()
        })
        steps.append(WarmupStep("zones+aim") { [weak self] in
            guard let self else { return }
            let master = self.controller.ctx.master
            self.zones.prewarm(count: BattleWorld.zonePoolSize,
                               radii: ZoneLayer.plannedRadii(state: self.controller.state, master: master))
            self.aim.prewarm(ranges: AimLayer.plannedRanges(state: self.controller.state, humanID: self.controller.humanHeroID,
                                                            master: master))
        })
        steps.append(WarmupStep("text", heavy: true) { [weak self] in
            guard let self else { return }
            self.text.prewarm(names: self.controller.state.units.compactMap { $0.hero?.displayName })
        })
        steps.append(WarmupStep("materials") { [weak self] in
            guard let self else { return }
            self.materials.prewarmUnlit(self.plannedUnlitMaterials())
        })
        steps.append(WarmupStep("vfx.emitters", heavy: true) { [weak self] in
            guard let self else { return }
            self.vfx.prewarmEmitters()
        })
        steps.append(WarmupStep("vfx.meshFX") { [weak self] in self?.vfx.prewarmMeshFX() })
        steps.append(WarmupStep("skillfx", heavy: true) { [weak self] in
            guard let self else { return }
            self.skillDirector.prewarm(heroIDs: self.controller.state.units.compactMap { $0.hero?.heroID })
        })
        // 陳列（作ったものを全て一度描く）
        steps.append(WarmupStep("gallery.shelf", heavy: true) { [weak self] in self?.openGalleryShelf() })
        steps.append(WarmupStep("gallery.units", heavy: true) { [weak self] in
            guard let self, let g = self.gallery else { return }
            self.units.showWarmupSamples(slot: g.nextSlot)
            self.units.showWarmupTrails(slot: g.nextSlot)
            self.zones.showWarmup(radii: ZoneLayer.plannedRadii(state: self.controller.state, master: self.controller.ctx.master),
                                  slot: g.nextSlot)
            self.projectiles.showWarmup(slot: g.nextSlot)
        })
        for team in Team.players {
            steps.append(WarmupStep("gallery.heroes \(team)", heavy: true) { [weak self] in self?.showGalleryHeroes(team) })
        }
        steps.append(WarmupStep("gallery.effects", heavy: true) { [weak self] in self?.fireGalleryEffects() })
        return steps
    }

    /// ウォームアップの終わり（BattleRenderer が幕を上げる直前に呼ぶ）。陳列を片付け、借りたものをプールへ戻す。
    func finishWarmup() {
        guard let g = gallery else { return }
        gallery = nil
        // 陳列のために点けた環境パーティクルを現在の画質（自動調整後）に戻す
        ambient.apply(quality: settings.quality)
        vfx.clear()
        skillDirector.clear()
        units.endWarmup()
        projectiles.endWarmup()
        zones.endWarmup()
        g.remove()
    }

    var isWarmupGalleryOpen: Bool { gallery != nil }

    /// 全体視点で始まる観戦: 霧の板を透明なまま幕の裏で描いておく（試合中に視点チームを選んだ時に、霧のマテリアルの
    /// 準備で詰まらないように）。幕が上がったら BattleWorld.syncFogVision が隠す。
    func prepareSpectatorFog() {
        guard controller.isSpectating, controller.viewerTeam == nil, let fog else { return }
        fog.beginWarmupDisplay()
    }

    // MARK: 作る

    /// ヒーロー・構造物の見た目を作る（最初の同期と同じ処理。何度呼んでも同じ）。
    private func warmUnits() {
        let state = controller.state
        let focus = controller.presentationFocusID
        var f = RenderFrame(state: state, alpha: Float(controller.interpolationAlpha), dt: 0, time: 0,
                            viewerTeam: controller.viewerTeam, humanID: controller.humanHeroID, focusID: focus,
                            ended: state.phase == .ended, winner: state.winner)
        let (t, _) = cameraFocus()
        f.camera = SIMD3(t.x, 10, t.y + 7)
        units.sync(f)
    }

    /// 試合で使う単色マテリアル（輪・閃光・状態表示の色。プール・バー・ゾーン・照準は各レイヤーの事前生成で作る）。
    func plannedUnlitMaterials() -> [(color: RGB, alpha: Double, depthTest: Bool)] {
        var rings: [RGB] = [FXRings.white, FXRings.heroDeath, FXRings.levelUp, FXRings.skillDefault, FXRings.heal,
                            FXRings.haste]
        var flashes: [RGB] = [FXRings.white, FXRings.smite]
        for team in Team.players {
            rings.append(materials.teams.light(team))
            flashes.append(materials.teams.light(team))
        }
        rings += ZoneLayer.colors
        for heroID in Set(controller.state.units.compactMap { $0.hero?.heroID }).sorted() {
            let c = BattleWorld.ringRGB(heroFXColor(heroID))
            rings.append(c)
            flashes.append(c)
            // ヒーロー別の通常攻撃の着弾・発射の輪と閃光（HeroAttackFX）
            if let profile = HeroFXProfiles.profile(heroID) {
                let m = HeroAttackFX.meshColors(profile)
                rings += m.rings
                flashes += m.flashes
            }
        }
        var out = rings.map { (color: $0, alpha: VFXSystem.ringAlpha, depthTest: true) }
        out += flashes.map { (color: $0, alpha: VFXSystem.flashAlpha, depthTest: true) }
        out.append((StatusIndicators.bubbleColor, StatusIndicators.bubbleAlpha, true))
        out.append((StatusIndicators.teleportColor, StatusIndicators.recallAlpha, true))
        for team in Team.players { out.append((materials.teams.light(team), StatusIndicators.recallAlpha, true)) }
        // キット層の状態表示（氷の殻・氷の誇りの輪・頭上のマークの記号。記号は所有者のヒーローごとの色）
        out.append((StatusIndicators.iceColor, StatusIndicators.iceGlassAlpha, true))
        out.append((StatusIndicators.iceColor, StatusIndicators.iceReadyAlpha, true))
        out.append((KitStatusVisuals.markColor(heroID: ""), 1, true))
        for heroID in Set(controller.state.units.compactMap { $0.hero?.heroID }).sorted() {
            out.append((KitStatusVisuals.markColor(heroID: heroID), 1, true))
        }
        return out
    }

    // MARK: 描く

    /// 陳列を注視点に開き、全マテリアル・全メッシュ・文字を並べる。
    private func openGalleryShelf() {
        if gallery != nil { return }
        let (t, _) = cameraFocus()
        let g = WarmupGallery(center: SIMD3(t.x, 0, t.y))
        gallery = g
        galleryTick = controller.state.tick
        root.addChild(g.root)
        let quad = meshes.centeredQuad ?? meshes.unitSphere
        // パレットのマテリアル（不透明と半透明の変種）・接地影
        g.addModel(meshes.unitSphere, material: materials.lit, faded: true)
        g.addModel(meshes.unitSphere, material: materials.glow, faded: true)
        if let cs = materials.contactShadow { g.addModel(cs.mesh, material: cs.material, faded: true) }
        // 単色マテリアル全て（不透明・半透明・深度なし。OpacityComponent の変種も）
        for m in materials.builtUnlit { g.addModel(quad, material: m, size: 0.25, faded: true) }
        // メッシュ全て（GPU への転送を幕の裏で済ませる）
        for m in meshes.builtMeshes { g.addModel(m, material: materials.lit, faded: false) }
        for m in units.structureMeshList { g.addModel(m, material: materials.glow, faded: false) }
        let textMaterial = materials.unlit(RGB(1, 0.94, 0.72), alpha: 1, depthTest: false)
        for m in text.builtMeshes { g.addModel(m, material: textMaterial, size: 0.3, faded: false) }
        // スキル演出の材質（画像 × 色）全てと形全て
        let fx = skillDirector.player
        if let disc = fx.meshes.mesh(.disc) {
            for m in fx.materials.built { g.addModel(disc, material: m, size: 0.25, faded: true) }
        }
        if let m = fx.materials.built.first {
            for mesh in fx.meshes.built { g.addModel(mesh, material: m, size: 0.25, faded: true) }
        }
    }

    /// 試合の全ヒーローを並べる（スキン・発光の粒子・足元の輪を含む。不透明と半透明はフレーム毎に交互）。
    private func showGalleryHeroes(_ team: Team) {
        guard let g = gallery else { return }
        let master = controller.ctx.master
        for u in controller.state.units where u.kind == .hero && u.team == team {
            guard let h = u.hero else { continue }
            g.addHero(HeroModelFactory.make(heroID: h.heroID, skinID: h.skinID, team: u.team, master: master))
        }
    }

    /// 全ての放出体（種類・数の上限によらず）・輪・閃光を一度ずつ再生する。
    private func fireGalleryEffects() {
        guard let g = gallery else { return }
        // 環境パーティクルは画質の自動調整で切っていても一度動かす（戻した時に粒子系を作らない）
        if ambient.emitterCount > 0 { ambient.root.isEnabled = true }
        let colors = plannedUnlitMaterials()
        let rings = colors.filter { $0.alpha == VFXSystem.ringAlpha }.map(\.color)
        let flashes = colors.filter { $0.alpha == VFXSystem.flashAlpha }.map(\.color)
        skillDirector.player.fireWarmup(around: g.center, spread: WarmupGallery.halfWidth)
        vfx.fireWarmup(around: g.center, spread: WarmupGallery.halfWidth, ringColors: Array(rings.prefix(18)),
                       flashColors: Array(flashes.prefix(12)))
    }
}
