import SwiftUI
import VelstriaCore

/// 起動直後の画面も、オンラインの待機室も同じパーティカードを使う。
struct HomeView: View {
    var onInvite: (() -> Void)? = nil
    var onStart: (() -> Void)? = nil

    var body: some View {
        PartyLobbyView(onInvite: onInvite, onStart: onStart)
    }
}

enum HomeDebug {
    static var startsFriendsCollapsed: Bool { false }
    static var startsMenuOpen: Bool { DebugLaunch.args.contains("-homeMenu") }
}
