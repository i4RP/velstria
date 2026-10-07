import SwiftUI
import VelstriaCore

// 担当: home-chrome。UI007 ホーム（合成ルート）。
// 背景の戦場と中央のヒーローを全画面に敷き、その上にヘッダー（上）・左レール・右レール・フッター（下）を載せる。
// 各部の矩形は HomeMetrics（HomeLogic.swift）が画面サイズとセーフエリアから決める。

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var now = Date()
    @State private var entered = false
    @State private var railCollapsed = HomeDebug.startsRailCollapsed
    @State private var menuOpen = HomeDebug.startsMenuOpen
    /// ショーケースで選んでいるヒーロー（nil = 既定の選び方。画面内の状態だけでプロフィールには保存しない）。
    @State private var pickedHeroID: String? = HomeDebug.initialHeroID

    /// ホームが前面に見えているか。対戦・マジックチェスは fullScreenCover で開くのでホームは onDisappear にならない。
    /// 演出（TimelineView・繰り返しアニメ・3D）はこれが真の間だけ動かす。
    private var isFrontmost: Bool {
        app.router.path.isEmpty && !app.router.isMatchFlowPresented && app.activeBattle == nil
            && app.activeMagicChess == nil && scenePhase == .active
    }

    private var animates: Bool { isFrontmost && !reduceMotion }

    var body: some View {
        // 外側（セーフエリアを守る）でインセットを測り、内側（全画面）で配置する。
        // 全画面にした GeometryReader はインセットを 0 と報告するため。
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            GeometryReader { geo in
                content(HomeMetrics(size: geo.size, safeArea: insets))
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            now = Date()
            app.audio.playMusic(.menu)
            if reduceMotion {
                entered = true
            } else {
                withAnimation(.spring(duration: 0.8, bounce: 0.18).delay(0.05)) { entered = true }
            }
        }
        // イベントの残り時間などを前面にいる間だけ更新する
        .task(id: isFrontmost) {
            guard isFrontmost else { return }
            now = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
        .fullScreenCover(isPresented: termsUpdateBinding) {
            TermsUpdateView().environment(app)
        }
    }

    private func content(_ m: HomeMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            HomeBackdrop(metrics: m, heroID: showcaseHeroID, animated: animates)
            HomeShowcase(metrics: m, heroID: showcaseHeroID, isActive: isFrontmost,
                         animated: animates, entered: entered) { pickedHeroID = $0 }
            chrome(m)
            if menuOpen {
                HomeMenuDrawer(metrics: m) { route in
                    closeMenu()
                    if let route { app.router.push(route) }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .frame(width: m.size.width, height: m.size.height)
    }

    /// ショーケースに出すヒーロー。
    private var showcaseHeroID: String {
        if let id = pickedHeroID, app.master.hero(id) != nil { return id }
        return HomeShowcaseLogic.initialHero(lastPicked: app.profile.lastPickedHeroID, avatar: app.profile.avatarHeroID,
                                             isKnown: { app.master.hero($0) != nil })
    }

    @ViewBuilder
    private func chrome(_ m: HomeMetrics) -> some View {
        let hidden = !entered
        // ヘッダー（上から）
        Group {
            HomeBandBackground(side: .top).homePlaced(in: m.headerRect)
            HomeHeader(metrics: m, now: now, animated: animates) { openMenu() }
        }
        .offset(y: hidden ? -m.headerRect.maxY - 12 : 0)
        .opacity(hidden ? 0 : 1)

        // フッター（下から）
        Group {
            HomeBandBackground(side: .bottom).homePlaced(in: m.footerRect)
            HomeFooter(metrics: m)
        }
        .offset(y: hidden ? m.footerRect.height + 12 : 0)
        .opacity(hidden ? 0 : 1)

        // 左レール（左から）
        HomeLeftRail(metrics: m, now: now, animated: animates)
            .offset(x: hidden ? -m.leftRailRect.maxX - 12 : 0)
            .opacity(hidden ? 0 : 1)

        // 右レール（右から。畳むと取っ手だけ残る）
        HomeRightRail(metrics: m, collapsed: $railCollapsed, animated: animates)
            .offset(x: hidden ? m.railCollapseOffset + 30 : 0)
            .opacity(hidden ? 0 : 1)

        // START（右下。少し遅れて下から）
        HomeStartButton(metrics: m, now: now, animated: animates)
            .offset(y: hidden ? m.startRect.height + 30 : 0)
            .opacity(hidden ? 0 : 1)
    }

    private func openMenu() {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.1)) { menuOpen = true }
    }

    private func closeMenu() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { menuOpen = false }
    }

    /// 規約が改定されていたら再同意を求める（戦闘・対戦フロー表示中は出さない）。
    private var termsUpdateBinding: Binding<Bool> {
        Binding(
            get: {
                app.profile.onboardingCompleted
                    && app.profile.acceptedTermsVersion < FeatureFlags.currentTermsVersion
                    && app.activeBattle == nil
                    && !app.router.isMatchFlowPresented
            },
            set: { _ in }
        )
    }
}

/// 検証用の起動引数（DebugLaunch.swift 冒頭の一覧を参照。出荷ビルドでは DebugLaunch.args が空なので常に既定値）。
enum HomeDebug {
    static var startsRailCollapsed: Bool { DebugLaunch.value(after: "-homeRail") == "collapsed" }
    static var startsMenuOpen: Bool { DebugLaunch.args.contains("-homeMenu") }
    static var initialHeroID: String? { DebugLaunch.value(after: "-homeHero") }
    static var starts3D: Bool { DebugLaunch.args.contains("-home3D") }
}
