import SwiftUI
import VelstriaCore

// 担当: battle-hud。画面確認・UI テスト用の HUD 状態の再現（DEBUG ビルドかつ -uiTesting 起動時のみ有効）。
//   -hudState <shop|scoreboard|pause|aim|death|deathinfo|signals|chatmenu|victory|defeat|spree|surrender|lowhp|recall|levelup|tutoriallearn|tutorialdone>
//   （signals: 2.5 秒ごとにシグナルを送り、キルフィードへキルを足し続ける。メッセージ・味方の返信・ピン・キルフィードの重なりの確認用。
//    chatmenu: キルフィードを足し続けながらクイックチャットのメニューを開いておく）
//   -hudLeftHanded / -hudColorblind / -hudManualCast / -hudFixedStick

#if DEBUG
@MainActor
enum HUDDebug {
    static var args: [String] { ProcessInfo.processInfo.arguments }
    static var isEnabled: Bool { args.contains("-uiTesting") }

    static var state: String? {
        guard isEnabled, let i = args.firstIndex(of: "-hudState"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// 設定の上書き（起動直後に 1 度だけ）。
    static func applySettings(_ app: AppModel) {
        guard isEnabled else { return }
        var s = app.profile.settings
        if args.contains("-hudLeftHanded") { s.leftHandedLayout = true }
        if args.contains("-hudColorblind") { s.colorblindMode = true }
        if args.contains("-hudManualCast") { s.skillCastMode = .manual }
        if args.contains("-hudFixedStick") { s.joystickMode = .fixed }
        if s != app.profile.settings { app.profile.settings = s }
    }

    static func apply(_ model: HUDModel) {
        guard let state else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            model.debugApply(state)
        }
    }
}

extension HUDModel {
    func debugApply(_ state: String) {
        switch state {
        case "shop": openShop()
        case "scoreboard": openPanel(.scoreboard)
        case "pause": openPanel(.pause)
        case "aim":
            if let layout {
                let c = layout.skillCenter(.skill1)
                abilityDragChanged(.skill(.skill1), start: c, location: c, buttonCenter: c)
                abilityDragChanged(.skill(.skill1), start: c,
                                   location: CGPoint(x: c.x - 50, y: c.y - 55), buttonCenter: c)
            }
        case "death":
            debugForceDeath = true
            debugForceAllyDeaths = true
        case "deathinfo":
            debugForceDeath = true
            debugForceAllyDeaths = true
            refresh()
            openDeathRecap()
        case "signals":
            debugSignalLoop(chatMenu: false)
        case "chatmenu":
            debugSignalLoop(chatMenu: true)
        case "victory", "defeat":
            debugEnd(winner: state == "victory" ? .blue : .red)
        case "spree":
            if let id = controller.humanHeroID {
                handle([.announcement(.killingSpree(killerID: id, streak: 5))])
            }
        case "surrender": debugForceSurrender = true
        case "lowhp": debugForceLowHP = true
        case "recall": recall()
        case "levelup":
            if let id = controller.humanHeroID { handle([.levelUp(heroID: id, level: 2)]) }
        case "tutorialdone":
            guard let id = controller.humanHeroID else { break }
            debugCompleteTutorial(humanID: id, through: .recall)
        case "tutoriallearn":
            guard let id = controller.humanHeroID else { break }
            debugCompleteTutorial(humanID: id, through: .attackDummy)
        default: break
        }
        refresh()
    }

    /// 2.5 秒ごとにシグナル（攻撃・集合・撤退・定型文の順）を送り、味方が敵ヒーローを倒したキルをキルフィードへ足す。
    /// メッセージ（6 秒）とキルフィード（7 秒）が常に数件ずつ出ている状態を撮影するためのもの。
    private func debugSignalLoop(chatMenu: Bool) {
        Task { @MainActor [weak self] in
            for k in 0..<240 {
                guard let model = self, model.endPhase == nil else { return }
                model.debugSignalTick(k, chatMenu: chatMenu)
                try? await Task.sleep(for: .seconds(2.5))
            }
        }
    }

    private func debugSignalTick(_ k: Int, chatMenu: Bool) {
        if chatMenu {
            if !signals.chatMenuOpen { signals.toggleChatMenu(model: self) }
        } else {
            let kinds: [HUDSignal] = [.signal(.attack), .signal(.gather), .signal(.retreat), .chat(HUDQuickChat.allCases[0])]
            signals.send(kinds[k % kinds.count], model: self)
        }
        let s = controller.sim.state
        guard let team = humanTeam else { return }
        let mine = s.heroIndices(team: team).map { s.units[$0].id }
        let theirs = s.heroIndices(team: team == .blue ? .red : .blue).map { s.units[$0].id }
        guard !mine.isEmpty, !theirs.isEmpty else { return }
        let killer = mine[k % mine.count]
        let assists = Array(mine.filter { $0 != killer }.prefix(k % 3))
        handle([.heroKilled(HeroKillEvent(victimID: theirs[k % theirs.count], killerID: killer, assistIDs: assists,
                                          bounty: 0, isFirstBlood: false, multiKill: 1, killerStreak: 1, isShutdown: false))])
    }

    /// チュートリアルの手順を last まで合成イベントで満たす。
    private func debugCompleteTutorial(humanID id: EntityID, through last: TutorialStep) {
        let dummy: EntityID = -1
        func hit() -> SimEvent {
            .damage(DamageEvent(sourceID: id, targetID: dummy, amount: 1, absorbed: 0, damageType: .physical,
                                source: .basicAttack, isCrit: false, pos: .zero))
        }
        var t = TutorialDirector()
        var p = Vec2(0, 0)
        for _ in 0...7 {
            t.observe(heroPosition: p, alive: true, skill1Rank: 0)
            p = p + Vec2(100, 0)
        }
        for _ in 0..<TutorialDirector.dummyHitGoal { t.handle(hit(), humanID: id, dummyIDs: [dummy]) }
        if last == .attackDummy {
            debugSetTutorial(t)
            return
        }
        t.handle(.skillLeveled(heroID: id, slot: .skill1, rank: 1), humanID: id, dummyIDs: [])
        t.noteSkillCommand(slot: .skill1, castable: true)
        t.noteShopOpened()
        t.handle(.itemPurchased(heroID: id, itemID: "EQ133"), humanID: id, dummyIDs: [])
        t.handle(.structureDestroyed(unitID: 0, kind: .tower, team: .red, lane: .mid, tier: .outer, killerID: id),
                 humanID: id, dummyIDs: [])
        t.handle(.channelCompleted(heroID: id, kind: .recall, destination: .zero), humanID: id, dummyIDs: [])
        debugSetTutorial(t)
    }
}
#endif
