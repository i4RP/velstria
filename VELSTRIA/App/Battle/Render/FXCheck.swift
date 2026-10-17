#if DEBUG || TESTER_TOOLS
import ReplayKit
import SwiftUI
import UIKit
import VelstriaCore

// 担当: battle-renderer。内部ビルドの「演出チェック」（設定 > テスター用）。選んだヒーロー（既定 H025〜H034）ごとに練習場を開き、
// FXCapture と同じ配置・間隔で S1 → S2 → 奥義（再使用の段も）を自動で撃つ。英雄にだけ撃てるスキルは敵の Bot の英雄へ撃つ。
// 全体を ReplayKit で録画し、最後に共有シートを出す（実機の録画で演出を確かめる）。判定・数値は変えない
// （置き直しは controller.restore、撃つのは通常の入力 controller.send。sim の規則はそのまま）。
// 途中で自分で試合を抜けると、そこで録画を止めて共有する（中止）。

/// 演出チェックの進行（試合をまたぐ。AppModel の戦闘の開始・終了に合わせて次のヒーローへ）。
@MainActor
final class FXCheckSession {
    static let shared = FXCheckSession()
    /// 既定で撃つヒーロー（MLBB の画面収録に合わせた 10 体）。
    nonisolated static let defaultHeroes = (25...34).map { String(format: "H%03d", $0) }
    /// 選んだヒーローを覚える（UserDefaults。カンマ区切り）。
    nonisolated static let heroesKey = "fxCheckHeroes"

    private(set) var heroes: [String] = []
    private(set) var index = 0
    private(set) var isRunning = false
    /// 今の演出チェックの試合のヒーロー（この試合の描画だけ FXCheckDriver を作る）。
    private(set) var currentHero: String?
    /// 今の試合を撃ち終えた（自分で抜けた時は false のまま = 中止）。
    private var driverDone = false
    private var leaveRequested = false
    private let recorder = FXCheckRecorder()

    func start(heroes list: [String], app: AppModel) {
        guard !isRunning, !list.isEmpty, app.activeBattle == nil else { return }
        heroes = list
        index = 0
        isRunning = true
        // 録画を断られても撃つところまでは進める（共有は無し）
        recorder.start { [weak self, weak app] in
            guard let self, let app else { return }
            self.launch(app: app)
        }
    }

    /// 試合の設定: 練習場（クールダウン無し・ミニオン無し・Lv4・スキルは自動習得。CI の撮影と同じ）+ 敵の Bot の英雄 1 体
    /// （英雄にだけ撃てるスキルの的。置き直す時に動かないようにする）。
    static func config(heroID: String, app: AppModel) -> MatchConfig {
        let options = PracticeOptions(noCooldowns: true, spawnMinions: false, spawnDummies: true, startLevel: 4)
        var config = PracticeSetup.config(heroID: heroID, options: options, profile: app.profile,
                                          seed: PracticeSetup.newSeed(), master: app.master)
        if let i = config.players.firstIndex(where: { $0.controller == .human }) {
            config.players[i].autoLevelSkills = true
        }
        let foe = heroID == "H029" ? "H034" : "H029"
        config.players.append(PlayerSlot(team: .red, heroID: foe, controller: .bot, position: .mid,
                                         displayName: "FX Check", botDifficulty: .easy))
        return config
    }

    /// この試合の描画で使う撃ち手（演出チェックの試合でなければ nil）。
    func driver(for controller: BattleController) -> FXCheckDriver? {
        guard isRunning, let hero = currentHero, let i = controller.humanIndex,
              controller.state.units[i].hero?.heroID == hero else { return nil }
        return FXCheckDriver(heroID: hero)
    }

    /// 撃ち終えた（FXCheckDriver）。HUDModel が次の更新で試合を抜ける。
    func driverFinished() {
        driverDone = true
        leaveRequested = true
    }

    /// HUDModel.refresh（15 Hz）から。抜けるべきなら true（1 回だけ）。
    func consumeLeave() -> Bool {
        guard leaveRequested else { return false }
        leaveRequested = false
        return true
    }

    /// AppModel.dismissBattle から。演出チェックの試合が閉じたら次のヒーローへ。最後・中止なら録画を止めて共有する。
    func battleDismissed(app: AppModel) {
        guard isRunning, currentHero != nil else { return }
        currentHero = nil
        let completed = driverDone
        index += 1
        guard completed, index < heroes.count else { return finish() }
        // 全画面の表示が閉じ切ってから次を開く
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak app] in
            guard let self, let app else { return }
            self.launch(app: app)
        }
    }

    private func launch(app: AppModel) {
        guard isRunning else { return }
        guard index < heroes.count, app.master.hero(heroes[index]) != nil else { return finish() }
        currentHero = heroes[index]
        driverDone = false
        leaveRequested = false
        app.startBattle(BattleLaunch(config: FXCheckSession.config(heroID: heroes[index], app: app)))
    }

    private func finish() {
        isRunning = false
        currentHero = nil
        recorder.stopAndShare()
    }
}

/// 1 試合ぶんの撃ち手（BattleRenderer が毎フレーム呼ぶ）。FXCapture と同じ配置（人形の南 4 m、北向き）と間隔
/// （置き直してから 1.6 秒待って撃ち、2.8 秒見る。再使用の段は決まった遅れで 2 回目）。
@MainActor
final class FXCheckDriver {
    nonisolated static let slots: [SkillSlot] = [.skill1, .skill2, .ultimate]
    /// 人形からヒーローを置く距離（sim の単位）。
    nonisolated static let standoff: Double = 400
    /// 敵の英雄の位置（人形からの sim の単位。人形の東 1.2 m）。
    nonisolated static let foeOffset = Vec2(120, 0)
    /// 再使用の段（2 回目）を撃つ遅れ（秒。段の演出を持つスキル）。FXCapture と共通。
    nonisolated static let recasts: [String: [SkillSlot: Double]] = [
        "H029": [.skill2: 0.85],
        "H032": [.skill2: 1.0],
        "H033": [.ultimate: 1.0],
    ]
    /// 英雄にだけ撃てるスキル（練習場の人形は的にならない）。敵の Bot の英雄へ撃つ。
    nonisolated static let heroOnly: [String: Set<SkillSlot>] = [
        "H027": [.skill1],
        "H028": [.ultimate],
        "H034": [.ultimate],
    ]
    nonisolated static let settleSeconds: Double = 1.6
    nonisolated static let watchSeconds: Double = 2.8
    /// 再使用の段を撃ってから見る長さ（秒）。
    nonisolated static let recastWatchSeconds: Double = 1.4

    private enum Step {
        case waitLive
        case place(index: Int)
        case settle(index: Int, until: Double)
        case cast(index: Int)
        case watch(index: Int, until: Double, recastAt: Double?)
        case done
    }

    let heroID: String
    private var step: Step = .waitLive
    private var liveFrames = 0

    init(heroID: String) {
        self.heroID = heroID
    }

    func tick(controller: BattleController) {
        let s = controller.state
        switch step {
        case .waitLive:
            guard controller.isPresentationReady, controller.humanIndex != nil else { return }
            liveFrames += 1
            guard liveFrames > 90 else { return }
            step = .place(index: 0)
        case .place(let k):
            guard k < FXCheckDriver.slots.count, place(controller: controller) else { return end() }
            step = .settle(index: k, until: s.time + FXCheckDriver.settleSeconds)
        case .settle(let k, let until):
            guard s.time >= until else { return }
            step = .cast(index: k)
        case .cast(let k):
            let slot = FXCheckDriver.slots[k]
            // 英雄にだけ撃てるスキルは、敵の英雄を射程に入る前（HitShapeScenario と同じ 1.5 m）へ呼ぶ（掴み・対象指定の射程が短い）
            if FXCheckDriver.heroOnly[heroID]?.contains(slot) == true { bringFoe(controller: controller) }
            guard let target = target(for: slot, controller: controller) else {
                step = .place(index: k + 1)
                return
            }
            controller.send(.castSkill(slot: slot, target: .unit(target)))
            let recastAt = FXCheckDriver.recasts[heroID]?[slot].map { s.time + $0 }
            let until = s.time + max(FXCheckDriver.watchSeconds,
                                     recastAt.map { $0 - s.time + FXCheckDriver.recastWatchSeconds } ?? 0)
            step = .watch(index: k, until: until, recastAt: recastAt)
        case .watch(let k, let until, let recastAt):
            if let at = recastAt, s.time >= at {
                if let target = target(for: FXCheckDriver.slots[k], controller: controller) {
                    controller.send(.castSkill(slot: FXCheckDriver.slots[k], target: .unit(target)))
                }
                step = .watch(index: k, until: until, recastAt: nil)
                return
            }
            guard s.time >= until else { return }
            step = .place(index: k + 1)
        case .done:
            break
        }
    }

    private func end() {
        if case .done = step { return }
        step = .done
        FXCheckSession.shared.driverFinished()
    }

    private func target(for slot: SkillSlot, controller: BattleController) -> EntityID? {
        if FXCheckDriver.heroOnly[heroID]?.contains(slot) == true { return foeHeroID(controller) }
        return dummyID(controller)
    }

    private func dummyID(_ controller: BattleController) -> EntityID? {
        let s = controller.state
        guard let me = controller.humanIndex else { return nil }
        let p = s.units[me].pos
        return s.units.filter { $0.kind == .dummy && $0.isAlive }
            .min { $0.pos.distance(to: p) < $1.pos.distance(to: p) }?.id
    }

    private func foeHeroID(_ controller: BattleController) -> EntityID? {
        let s = controller.state
        guard let me = controller.humanIndex else { return nil }
        let team = s.units[me].team
        return s.units.first { $0.kind == .hero && $0.team != team && $0.isAlive }?.id
    }

    /// 敵の英雄を自分のヒーローの前 HitShapeScenario.foeDistance に置き直す（英雄にだけ撃てるスキルの直前）。
    private func bringFoe(controller: BattleController) {
        guard let me = controller.humanIndex else { return }
        var s = controller.state
        let team = s.units[me].team
        guard let hi = s.units.firstIndex(where: { $0.kind == .hero && $0.team != team }) else { return }
        let at = s.units[me].pos + Vec2.fromAngle(s.units[me].facing) * HitShapeScenario.foeDistance
        s.units[hi].pos = at
        s.units[hi].prevPos = at
        s.units[hi].path.removeAll()
        s.units[hi].moveIntent = .none
        controller.restore(s)
    }

    /// 自分のヒーローを人形の南 standoff に北向きで置き直し、体力・資源を満たす。人形の体力も戻す。
    /// 敵の英雄は人形の東に南向きで置き、体力を満たして人間の操作扱いにする（Bot の判断で動かない。入力が無いので立っているだけ）。
    private func place(controller: BattleController) -> Bool {
        guard let me = controller.humanIndex, let foe = dummyID(controller) else { return false }
        var s = controller.state
        guard let fi = s.index(of: foe) else { return false }
        let spot = s.units[fi].pos + Vec2(0, -FXCheckDriver.standoff)
        s.units[me].pos = spot
        s.units[me].prevPos = spot
        s.units[me].path.removeAll()
        s.units[me].moveIntent = .none
        s.units[me].facing = Double.pi / 2
        s.units[me].hp = s.units[me].stats.maxHP
        s.units[me].resource = s.units[me].stats.maxResource
        s.units[fi].hp = s.units[fi].stats.maxHP
        let team = s.units[me].team
        if let hi = s.units.firstIndex(where: { $0.kind == .hero && $0.team != team }) {
            let at = s.units[fi].pos + FXCheckDriver.foeOffset
            s.units[hi].pos = at
            s.units[hi].prevPos = at
            s.units[hi].path.removeAll()
            s.units[hi].moveIntent = .none
            s.units[hi].facing = -Double.pi / 2
            s.units[hi].hp = s.units[hi].stats.maxHP
            s.units[hi].hero?.controller = .human
        }
        controller.restore(s)
        return true
    }
}

/// ReplayKit の録画（演出チェックの全体）と、終わった後の共有シート。
@MainActor
final class FXCheckRecorder {
    private var recording = false

    /// 録画を始めてから next を呼ぶ（断られた・使えない時も呼ぶ）。
    func start(_ next: @escaping @MainActor () -> Void) {
        let r = RPScreenRecorder.shared()
        guard r.isAvailable else { return next() }
        r.isMicrophoneEnabled = false
        r.startRecording { [weak self] error in
            Task { @MainActor in
                self?.recording = error == nil
                next()
            }
        }
    }

    func stopAndShare() {
        guard recording else { return }
        recording = false
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VELSTRIA-FXCheck-\(AppVersionInfo.build)-\(f.string(from: Date())).mp4")
        try? FileManager.default.removeItem(at: url)
        RPScreenRecorder.shared().stopRecording(withOutput: url) { error in
            Task { @MainActor in
                guard error == nil else { return }
                FXCheckRecorder.share(url)
            }
        }
    }

    static func share(_ url: URL) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
        while let p = top.presentedViewController { top = p }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        vc.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        top.present(vc, animated: true)
    }
}

/// 設定 > テスター用 の「演出チェック」（撃つヒーローを選んで始める）。
struct FXCheckSettingsRow: View {
    @Environment(AppModel.self) private var app
    @AppStorage(FXCheckSession.heroesKey) private var stored = FXCheckSession.defaultHeroes.joined(separator: ",")

    private var selected: Set<String> { Set(stored.split(separator: ",").map(String.init)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("演出チェック", "FX check")).font(Theme.body(13))
            Text(L("練習場で選んだヒーローの S1 → S2 → 奥義を自動で撃ち、画面を録画して共有します",
                   "Casts S1 → S2 → Ult for the selected heroes in practice, records the screen and shares it"))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                ForEach(app.master.heroes, id: \.heroID) { h in
                    let on = selected.contains(h.heroID)
                    Button {
                        toggle(h.heroID)
                    } label: {
                        Text(h.heroID)
                            .font(Theme.body(10))
                            .frame(maxWidth: .infinity, minHeight: 22)
                            .background(on ? Theme.cyan.opacity(0.35) : Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tester_fxcheck_\(h.heroID)")
                }
            }
            HStack(spacing: 8) {
                Button {
                    let list = app.master.heroes.map(\.heroID).filter { selected.contains($0) }
                    app.audio.play(.uiConfirm)
                    FXCheckSession.shared.start(heroes: list, app: app)
                } label: {
                    Text(L("始める（録画あり）", "Start (records)")).lineLimit(1)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(selected.isEmpty)
                .accessibilityIdentifier("tester_fxcheck_start")
                Button {
                    stored = FXCheckSession.defaultHeroes.joined(separator: ",")
                } label: {
                    Text(L("既定に戻す", "Reset")).lineLimit(1)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func toggle(_ id: String) {
        var s = selected
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        stored = app.master.heroes.map(\.heroID).filter { s.contains($0) }.joined(separator: ",")
    }
}
#endif
