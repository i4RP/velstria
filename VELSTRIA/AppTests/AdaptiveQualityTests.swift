import XCTest
@testable import VELSTRIA
import VelstriaCore

// battle-renderer（性能）: 画質の自動調整（AdaptiveQuality）。フレーム時間・温度・低電力モードの列 → 期待する段の変化。
// ヒステリシス（下げるのは 3 秒、戻すのは 10 秒、変更間隔 4 秒、行ったり来たりで待ちが倍）と「ユーザー設定を超えない」を確かめる。

final class AdaptiveQualityTests: XCTestCase {
    private func user(_ q: GraphicsQuality, fps: Int = 60) -> RenderSettings {
        RenderSettings(quality: .preset(q), frameRate: fps, showDamageNumbers: true, colorblind: false)
    }

    /// 一定のフレームを seconds 秒分与え、起きた変化を返す。
    @discardableResult
    private func feed(_ g: inout AdaptiveQuality, seconds: Double, frame: Double, work: Double = 0.002) -> [AdaptiveQuality.Change] {
        var changes: [AdaptiveQuality.Change] = []
        var t = 0.0
        while t < seconds - 1e-9 {
            if let c = g.record(frameDt: frame, work: work) { changes.append(c) }
            t += frame
        }
        return changes
    }

    /// 変化が起きるまで同じフレームを与える（変化の直後で止める）。
    @discardableResult
    private func feedUntilChange(_ g: inout AdaptiveQuality, frame: Double, work: Double = 0.002,
                                 maxSeconds: Double = 30) -> AdaptiveQuality.Change? {
        var t = 0.0
        while t < maxSeconds {
            if let c = g.record(frameDt: frame, work: work) { return c }
            t += frame
        }
        return nil
    }

    private func assertNotAbove(_ o: AdaptiveQuality.Output, _ u: RenderSettings, file: StaticString = #filePath, line: UInt = #line) {
        let q = o.settings.quality, uq = u.quality
        XCTAssertEqual(q.level, uq.level, "段の名前（level）はユーザーの選択のまま", file: file, line: line)
        XCTAssertTrue(!q.shadows || uq.shadows, "影", file: file, line: line)
        XCTAssertTrue(!q.projectileTrails || uq.projectileTrails, "軌跡", file: file, line: line)
        XCTAssertTrue(!q.ambientParticles || uq.ambientParticles, "環境パーティクル", file: file, line: line)
        XCTAssertLessThanOrEqual(q.particleScale, uq.particleScale, file: file, line: line)
        XCTAssertLessThanOrEqual(q.maxEmitters, uq.maxEmitters, file: file, line: line)
        XCTAssertEqual(q.groundTextureSize, uq.groundTextureSize, file: file, line: line)
        XCTAssertEqual(q.fogTextureSize, uq.fogTextureSize, file: file, line: line)
        XCTAssertLessThanOrEqual(o.settings.frameRate, u.frameRate, file: file, line: line)
        XCTAssertEqual(o.settings.showDamageNumbers, u.showDamageNumbers, file: file, line: line)
        XCTAssertEqual(o.settings.colorblind, u.colorblind, file: file, line: line)
        let up = PostProcessSettings.preset(uq.level)
        XCTAssertTrue(!o.post.enabled || up.enabled, "後処理", file: file, line: line)
        XCTAssertLessThanOrEqual(o.post.bloomIntensity, up.bloomIntensity, file: file, line: line)
        XCTAssertLessThanOrEqual(o.post.bloomLevels, up.bloomLevels, file: file, line: line)
        XCTAssertLessThanOrEqual(o.renderScale, 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(o.renderScale, 0.75, file: file, line: line)
    }

    // MARK: 段と出力

    func testEveryStepStaysAtOrBelowUserSettings() {
        for q in GraphicsQuality.allCases {
            for fps in [30, 60] {
                for switchable in [false, true] {
                    let u = user(q, fps: fps)
                    for step in AdaptiveQuality.Step.allCases {
                        assertNotAbove(AdaptiveQuality.output(step, user: u, shadowSwitchable: switchable), u)
                    }
                    XCTAssertEqual(AdaptiveQuality.output(.full, user: u, shadowSwitchable: switchable).settings, u,
                                   "最上段はユーザー設定そのもの")
                }
            }
        }
    }

    func testStepsWithoutEffectAreSkipped() {
        // low は環境パーティクル・軌跡・後処理・影が元から無いので、その段は飛ばす
        let low = AdaptiveQuality.effectiveSteps(user: user(.low), shadowSwitchable: true)
        XCTAssertEqual(low, [.full, .fewerParticles, .scale88, .scale75, .fps30])
        // high で影の両状態を温めていなければ、影は切り替えない
        let high = AdaptiveQuality.effectiveSteps(user: user(.high), shadowSwitchable: false)
        XCTAssertFalse(high.contains(.noShadows))
        XCTAssertTrue(AdaptiveQuality.effectiveSteps(user: user(.high), shadowSwitchable: true).contains(.noShadows))
        // 30fps 設定では 30fps の段は変化がない
        XCTAssertFalse(AdaptiveQuality.effectiveSteps(user: user(.medium, fps: 30), shadowSwitchable: true).contains(.fps30))
        // medium は後処理 1 段 = 後処理なし（同じ出力が 2 段続かない）
        let mid = AdaptiveQuality.effectiveSteps(user: user(.medium), shadowSwitchable: true)
        XCTAssertTrue(mid.contains(.reducedPost))
        XCTAssertFalse(mid.contains(.noPost))
    }

    func testStepOrderDegradesCheapKnobsFirst() {
        let u = user(.high)
        let o1 = AdaptiveQuality.output(.noAmbient, user: u, shadowSwitchable: true)
        XCTAssertFalse(o1.settings.quality.ambientParticles)
        XCTAssertEqual(o1.settings.quality.particleScale, u.quality.particleScale)
        let o2 = AdaptiveQuality.output(.fewerParticles, user: u, shadowSwitchable: true)
        XCTAssertLessThan(o2.settings.quality.particleScale, u.quality.particleScale)
        XCTAssertLessThan(o2.settings.quality.maxEmitters, u.quality.maxEmitters)
        XCTAssertTrue(o2.settings.quality.projectileTrails)
        let o4 = AdaptiveQuality.output(.reducedPost, user: u, shadowSwitchable: true)
        XCTAssertEqual(o4.post, .preset(.medium), "後処理は 1 段ずつ")
        XCTAssertTrue(o4.settings.quality.shadows)
        let o6 = AdaptiveQuality.output(.noShadows, user: u, shadowSwitchable: true)
        XCTAssertFalse(o6.post.enabled)
        XCTAssertFalse(o6.settings.quality.shadows)
        XCTAssertEqual(o6.renderScale, 1)
        XCTAssertEqual(AdaptiveQuality.output(.scale88, user: u, shadowSwitchable: true).renderScale, 0.875)
        let last = AdaptiveQuality.output(.fps30, user: u, shadowSwitchable: true)
        XCTAssertEqual(last.renderScale, 0.75)
        XCTAssertEqual(last.settings.frameRate, 30)
    }

    // MARK: フレーム時間

    func testDowngradesAfterThreeSecondsOverBudget() {
        var g = AdaptiveQuality(user: user(.high), shadowSwitchable: true)
        // 1 回の重いフレーム（ヒッチ）は p95 に効かない
        XCTAssertNil(g.record(frameDt: 0.2, work: 0.05))
        XCTAssertTrue(feed(&g, seconds: 2.5, frame: 1.0 / 60).isEmpty)
        // 30 ms（目標の 1.8 倍）が続く → 3 秒で 1 段だけ下げる
        g.resetWindow()
        let changes = feed(&g, seconds: 3.6, frame: 0.030)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.from, .full)
        XCTAssertEqual(changes.first?.to, .noAmbient)
        if case .overBudget(let f, _)? = changes.first?.reason {
            XCTAssertEqual(f, 30, accuracy: 0.5)
        } else {
            XCTFail("理由は予算超過")
        }
        XCTAssertNotNil(changes.first)
        XCTAssertFalse(g.output.settings.quality.ambientParticles)
    }

    func testDowngradesOneStepAtATimeWithCooldown() {
        var g = AdaptiveQuality(user: user(.high), shadowSwitchable: true)
        let changes = feed(&g, seconds: 30, frame: 0.030)
        XCTAssertGreaterThanOrEqual(changes.count, 3)
        for k in 1..<changes.count {
            XCTAssertEqual(changes[k].from, changes[k - 1].to, "1 段ずつ")
            XCTAssertGreaterThanOrEqual(changes[k].time - changes[k - 1].time, g.config.cooldown - 0.05, "変更の間隔")
        }
        // 解像度より先に軽い項目から下げる
        XCTAssertEqual(Array(changes.prefix(3).map(\.to)), [.noAmbient, .fewerParticles, .noTrails])
        // 予算超過だけでは 30fps まで下げない（30fps は温度 .critical のときだけ）
        let all = feed(&g, seconds: 120, frame: 0.030)
        XCTAssertFalse(all.contains { $0.to == .fps30 })
        XCTAssertEqual(g.step, .scale75)
        XCTAssertEqual(g.output.settings.frameRate, 60)
    }

    func testMainThreadWorkOverBudgetAlsoDowngrades() {
        var g = AdaptiveQuality(user: user(.medium), shadowSwitchable: true)
        // 描画間隔は 60fps のままでも、処理時間が 13 ms（予算 11.7 ms 超）なら下げる
        let changes = feed(&g, seconds: 3.6, frame: 1.0 / 60, work: 0.013)
        XCTAssertEqual(changes.map(\.to), [.fewerParticles], "medium は環境パーティクルが元から無いので粒子量から")
    }

    func testNeutralZoneHoldsTheCurrentStep() {
        var g = AdaptiveQuality(user: user(.high), shadowSwitchable: true)
        feedUntilChange(&g, frame: 0.030)
        XCTAssertEqual(g.step, .noAmbient)
        // 19 ms: 予算超過（20.8 ms）でも余裕（18.3 ms 以下）でもない → 上げも下げもしない
        XCTAssertTrue(feed(&g, seconds: 60, frame: 0.019).isEmpty)
        XCTAssertEqual(g.step, .noAmbient)
    }

    func testUpgradesAfterTenSecondsOfHeadroom() {
        var g = AdaptiveQuality(user: user(.high), shadowSwitchable: true)
        XCTAssertEqual(feedUntilChange(&g, frame: 0.030)?.to, .noAmbient)
        XCTAssertTrue(feed(&g, seconds: 9.5, frame: 1.0 / 60).isEmpty, "余裕が 10 秒続くまでは戻さない")
        let up = feed(&g, seconds: 1.5, frame: 1.0 / 60)
        XCTAssertEqual(up.map(\.to), [.full])
        XCTAssertEqual(up.first?.reason, .headroom)
        XCTAssertEqual(g.output.settings, user(.high))
    }

    func testRevertedUpgradeDoublesTheWaitBeforeTheNextOne() {
        var g = AdaptiveQuality(user: user(.high), shadowSwitchable: true)
        feedUntilChange(&g, frame: 0.030)
        XCTAssertEqual(feedUntilChange(&g, frame: 1.0 / 60)?.to, .full)
        // 戻した直後にまた重くなる → 下げる。次に戻すまでの待ちは倍（20 秒）
        let down = feedUntilChange(&g, frame: 0.030)
        XCTAssertEqual(down?.to, .noAmbient)
        XCTAssertEqual(g.upAfter, 20, accuracy: 1e-9)
        XCTAssertTrue(feed(&g, seconds: 19.5, frame: 1.0 / 60).isEmpty, "10 秒では戻さない")
        XCTAssertEqual(feed(&g, seconds: 1.5, frame: 1.0 / 60).map(\.to), [.full])
        // 戻したまま落ち着いていれば、待ちは元へ近づく
        feed(&g, seconds: 25, frame: 1.0 / 60)
        XCTAssertEqual(g.upAfter, 10, accuracy: 1e-9)
    }

    func testThirtyFpsUserIsJudgedAgainstItsOwnTarget() {
        var g = AdaptiveQuality(user: user(.high, fps: 30), shadowSwitchable: true)
        XCTAssertTrue(feed(&g, seconds: 20, frame: 1.0 / 30).isEmpty, "30fps 設定で 33 ms は予算内")
        XCTAssertEqual(g.step, .full)
    }

    func testFrameTimeAdaptationCanBeDisabledForScreenshots() {
        var config = AdaptiveQuality.Config()
        config.adaptsToFrameTime = false
        var g = AdaptiveQuality(user: user(.high), shadowSwitchable: true, config: config)
        XCTAssertTrue(feed(&g, seconds: 30, frame: 0.05).isEmpty)
        XCTAssertEqual(g.step, .full)
        XCTAssertEqual(g.setThermal(.critical)?.to, .fps30, "温度の下限は守る")
    }

    func testResetWindowDiscardsPendingSamples() {
        var g = AdaptiveQuality(user: user(.high), shadowSwitchable: true)
        feed(&g, seconds: 2.5, frame: 0.030)
        g.resetWindow()
        XCTAssertTrue(feed(&g, seconds: 2.5, frame: 0.030).isEmpty, "一時停止をまたいだ超過は連続とみなさない")
    }

    // MARK: 温度・低電力モード

    func testThermalSeriousForcesAtLeastPostOff() throws {
        var g = AdaptiveQuality(user: user(.high), shadowSwitchable: true)
        let c = try XCTUnwrap(g.setThermal(.serious))
        XCTAssertEqual(c.to, .noPost)
        XCTAssertEqual(c.reason, .thermal(.serious))
        XCTAssertFalse(g.output.post.enabled)
        XCTAssertTrue(g.output.settings.quality.shadows, "影はまだ残す")
        // 下限より上には戻らない
        XCTAssertTrue(feed(&g, seconds: 60, frame: 1.0 / 60).isEmpty)
        XCTAssertEqual(g.step, .noPost)
        // 温度が戻っても即座には上げず、余裕が続いてから 1 段ずつ
        XCTAssertNil(g.setThermal(.nominal))
        XCTAssertEqual(g.step, .noPost)
        let ups = feed(&g, seconds: 12, frame: 1.0 / 60)
        XCTAssertEqual(ups.map(\.to), [.reducedPost])
    }

    func testThermalCriticalForcesTheLowestStep() throws {
        var g = AdaptiveQuality(user: user(.high), shadowSwitchable: true)
        let c = try XCTUnwrap(g.setThermal(.critical))
        XCTAssertEqual(c.to, .fps30)
        XCTAssertEqual(g.output.settings.frameRate, 30)
        XCTAssertEqual(g.output.renderScale, 0.75)
        XCTAssertFalse(g.output.settings.quality.shadows)
        XCTAssertFalse(g.output.post.enabled)
        assertNotAbove(g.output, user(.high))
        // 30fps 設定のユーザーなら、最低段は解像度 75%
        var g30 = AdaptiveQuality(user: user(.low, fps: 30), shadowSwitchable: true)
        XCTAssertEqual(g30.setThermal(.critical)?.to, .scale75)
    }

    func testCriticalAtStartAppliesImmediately() {
        let g = AdaptiveQuality(user: user(.medium), shadowSwitchable: false, thermal: .critical)
        XCTAssertEqual(g.step, g.steps.last)
        XCTAssertEqual(g.output.settings.frameRate, 30)
    }

    func testLowPowerModeFloor() throws {
        var g = AdaptiveQuality(user: user(.high), shadowSwitchable: true)
        let c = try XCTUnwrap(g.setLowPower(true))
        XCTAssertEqual(c.to, .reducedPost)
        XCTAssertEqual(g.output.post, .preset(.medium))
        XCTAssertFalse(g.output.settings.quality.projectileTrails)
        XCTAssertNil(g.setLowPower(true), "変化なし")
        XCTAssertNil(g.setLowPower(false), "解除しても即座には上げない")
    }

    // MARK: 設定の変更

    func testUserSettingsChangeKeepsTheStepAndNeverExceedsTheNewSettings() throws {
        var g = AdaptiveQuality(user: user(.high), shadowSwitchable: true)
        feed(&g, seconds: 12, frame: 0.030)
        XCTAssertEqual(g.step, .noTrails)
        // low へ変えた: low には軌跡の段が無いので、次に軽い段（解像度 87.5%）に合わせる
        _ = g.setUser(user(.low))
        XCTAssertEqual(g.step, .scale88)
        assertNotAbove(g.output, user(.low))
        // 影の切り替え可否が変わっても上限は守る
        _ = g.setShadowSwitchable(false)
        assertNotAbove(g.output, user(.low))
    }

    func testRandomSequencesNeverExceedUserSettings() {
        var rng = SplitMix64(seed: 42)
        for q in GraphicsQuality.allCases {
            let u = user(q)
            var g = AdaptiveQuality(user: u, shadowSwitchable: q == .high)
            for _ in 0..<6000 {
                let r = rng.nextDouble()
                let states: [ProcessInfo.ThermalState] = [.nominal, .fair, .serious, .critical]
                if r < 0.002 { _ = g.setThermal(states[Int(rng.nextDouble() * 4) % 4]) }
                if r > 0.998 { _ = g.setLowPower(rng.nextDouble() < 0.5) }
                let frame = rng.nextDouble() < 0.5 ? 1.0 / 60 : 0.016 + rng.nextDouble() * 0.03
                _ = g.record(frameDt: frame, work: rng.nextDouble() * 0.015)
                assertNotAbove(g.output, u)
                XCTAssertGreaterThanOrEqual(g.index, g.floorIndex, "温度・低電力の下限より上にいない")
            }
        }
    }
}
