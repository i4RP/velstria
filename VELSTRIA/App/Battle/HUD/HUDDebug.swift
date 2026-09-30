import SwiftUI
import VelstriaCore

// 担当: battle-hud。画面確認・UI テスト用の HUD 状態の再現（DEBUG ビルドかつ -uiTesting 起動時のみ有効）。
//   -hudState <shop|scoreboard|pause|aim|death|victory|defeat|spree|surrender|lowhp|recall|levelup>
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
        case "death": debugForceDeath = true
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
        default: break
        }
        refresh()
    }
}
#endif
