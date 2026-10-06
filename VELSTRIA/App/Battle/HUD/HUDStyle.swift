import SwiftUI
import VelstriaCore

// 担当: battle-hud。戦闘 HUD の共通スタイルと画面配置（横画面・左利き反転・Safe Area 対応）。

enum HUDStyle {
    static let surface = Color(red: 0.04, green: 0.08, blue: 0.17)
    static let glassTop = Color(red: 0.10, green: 0.17, blue: 0.29).opacity(0.94)
    static let glassBottom = surface.opacity(0.94)
    static let rim = Color(red: 0.61, green: 0.78, blue: 1.0).opacity(0.32)
    static let accent = Color(red: 0.38, green: 0.88, blue: 1.0)
    static let violet = Color(red: 0.66, green: 0.51, blue: 1.0)
    static let mutedText = Color(red: 0.69, green: 0.78, blue: 0.89)
    static let hp = Color(red: 0.64, green: 0.95, blue: 0.38)
    static let hpLow = Color(red: 1.0, green: 0.30, blue: 0.32)
    static let mana = Color(red: 0.32, green: 0.74, blue: 1.0)
    static let energy = Color(red: 1.0, green: 0.86, blue: 0.30)
    static let xp = violet
    static let shield = Color.white.opacity(0.88)

    static func number(_ v: Double) -> String { String(Int(max(0, v).rounded())) }

    /// mm:ss（1 時間以上は h:mm:ss）。
    static func clock(_ seconds: Double) -> String {
        let t = max(0, Int(seconds))
        if t >= 3600 { return String(format: "%d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60) }
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    /// mm:ss.s（0.1 秒単位。観戦・リプレイの再生位置）。
    static func preciseClock(_ seconds: Double) -> String {
        let tenths = max(0, Int((seconds * 10).rounded(.down)))
        let t = tenths / 10
        if t >= 3600 { return String(format: "%d:%02d:%02d.%d", t / 3600, (t / 60) % 60, t % 60, tenths % 10) }
        return String(format: "%02d:%02d.%d", t / 60, t % 60, tenths % 10)
    }

    /// 1000 単位の短い表記（12.3k）。
    static func thousands(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1000 { return String(format: "%.1fk", v / 1000) }
        return String(Int(v.rounded()))
    }

    /// クールダウン表示（10 秒未満は小数 1 桁）。
    static func cooldown(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f", max(0.1, v)) : String(Int(v.rounded(.up)))
    }

    static func resourceColor(_ kind: ResourceKind) -> Color { kind == .energy ? energy : mana }
}

/// 半透明ガラス調の面。
struct HUDGlass: ViewModifier {
    var cornerRadius: CGFloat = 12
    var tint: Color = HUDStyle.rim

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(colors: [HUDStyle.glassTop, HUDStyle.glassBottom], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [tint, tint.opacity(0.12)], startPoint: .top, endPoint: .bottom),
                                  lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 5, y: 3)
    }
}

extension View {
    func hudGlass(cornerRadius: CGFloat = 12, tint: Color = HUDStyle.rim) -> some View {
        modifier(HUDGlass(cornerRadius: cornerRadius, tint: tint))
    }

    /// タップ可能な HUD 部品の共通アクセシビリティ設定。
    func hudAccessibility(id: String, label: String, value: String? = nil, action: @escaping () -> Void) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(id)
            .accessibilityAction(.default, action)
    }
}

/// Gold の硬貨アイコン。
struct HUDCoin: View {
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 1.0, green: 0.90, blue: 0.55), Color(red: 0.85, green: 0.58, blue: 0.12)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().strokeBorder(Color(red: 0.55, green: 0.35, blue: 0.05).opacity(0.8), lineWidth: max(0.8, size * 0.08))
                .padding(size * 0.16)
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.38, weight: .black))
                .foregroundStyle(Color(red: 0.62, green: 0.40, blue: 0.06).opacity(0.85))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 上部の丸いアイコンボタン（44pt）。
struct HUDRoundButton: View {
    let symbol: String
    let label: String
    let identifier: String
    var size: CGFloat = 44
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.40, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(LinearGradient(colors: [HUDStyle.glassTop, HUDStyle.glassBottom],
                                                         startPoint: .top, endPoint: .bottom)))
                .overlay(Circle().strokeBorder(HUDStyle.rim, lineWidth: 1.2))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// 押下時に少し縮む。
struct HUDPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}

/// チュートリアルで操作を示す脈動リング。
struct HUDHighlightRing: View {
    var diameter: CGFloat
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .strokeBorder(Theme.gold, lineWidth: 3)
            .frame(width: diameter, height: diameter)
            .scaleEffect(on ? 1.18 : 0.96)
            .opacity(on ? 0.25 : 1)
            .shadow(color: Theme.gold.opacity(0.9), radius: 8)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - 配置

/// 画面サイズと Safe Area から各操作部品の位置を決める（座標は HUD 全面のローカル座標）。
/// 右手配置で計算し、左利き配置では x を左右反転する。
struct HUDLayout: Equatable {
    let size: CGSize
    let safe: EdgeInsets
    let leftHanded: Bool
    /// iPhone 16e 横（844×390）を 1.0 とする倍率。
    let scale: CGFloat

    init(size: CGSize, safe: EdgeInsets, leftHanded: Bool) {
        self.size = size
        self.safe = safe
        self.leftHanded = leftHanded
        let s = min(size.height / 390, size.width / 844)
        scale = min(1.18, max(0.84, s))
    }

    var width: CGFloat { size.width }
    var height: CGFloat { size.height }
    /// 左右の Safe Area（Dynamic Island / ノッチ側）。横画面では左右対称。
    var leadingEdge: CGFloat { max(safe.leading, 10) }
    var trailingEdge: CGFloat { size.width - max(safe.trailing, 10) }
    /// ホームインジケータの上端。
    var bottomEdge: CGFloat { size.height - max(safe.bottom, 8) }
    var topEdge: CGFloat { max(safe.top, 6) }

    /// 右手配置の x を現在の配置へ。
    func mx(_ x: CGFloat) -> CGFloat { leftHanded ? leadingEdge + trailingEdge - x : x }

    // MARK: 右側クラスタ（攻撃・スキル・スペル・帰還）

    var attackDiameter: CGFloat { 86 * scale }
    func attackDiameter(for slot: AttackButtonSlot) -> CGFloat {
        slot == .center ? attackDiameter : 54 * scale
    }
    var skillDiameter: CGFloat { 60 * scale }
    var ultDiameter: CGFloat { 66 * scale }
    var spellDiameter: CGFloat { 50 * scale }
    var recallDiameter: CGFloat { max(44, 46 * scale) }
    var levelBadgeDiameter: CGFloat { 30 * scale }

    private var attackCenterRight: CGPoint {
        CGPoint(x: trailingEdge - 8 * scale - attackDiameter / 2, y: bottomEdge - 121 * scale)
    }

    var attackCenter: CGPoint { mirrored(attackCenterRight) }

    /// 上下の優先攻撃ボタンは中央の大きなボタンと縦に並べる。
    func attackCenter(for slot: AttackButtonSlot) -> CGPoint {
        switch slot {
        case .top: return actionPoint(x: 0, y: -74)
        case .center: return attackCenter
        case .bottom: return actionPoint(x: 0, y: 74)
        }
    }

    /// 中央攻撃ボタンからの位置。スキル群は攻撃列の内側へ配置する。
    private func actionPoint(x: CGFloat, y: CGFloat) -> CGPoint {
        let c = attackCenterRight
        return mirrored(CGPoint(x: c.x + x * scale, y: c.y + y * scale))
    }

    private func mirrored(_ p: CGPoint) -> CGPoint { CGPoint(x: mx(p.x), y: p.y) }

    func skillCenter(_ slot: SkillSlot) -> CGPoint {
        switch slot {
        case .skill1: return actionPoint(x: -163, y: 76)
        case .skill2: return actionPoint(x: -93, y: 69)
        case .skill3: return actionPoint(x: -77, y: -3)
        case .ultimate, .passive: return actionPoint(x: -76, y: -72)
        }
    }

    func levelBadgeCenter(_ slot: SkillSlot) -> CGPoint {
        switch slot {
        case .skill1: return actionPoint(x: -210, y: 30)
        case .skill2: return actionPoint(x: -142, y: 19)
        case .skill3: return actionPoint(x: -138, y: -32)
        case .ultimate, .passive: return actionPoint(x: -123, y: -129)
        }
    }

    func spellCenter(_ index: Int) -> CGPoint {
        index == 0 ? actionPoint(x: -204, y: -26) : actionPoint(x: -181, y: -90)
    }

    var recallCenter: CGPoint { actionPoint(x: -218, y: 89) }

    /// 右側クラスタの内側（画面中央側）の端。
    var clusterInnerEdge: CGFloat {
        let r = recallCenter.x
        return leftHanded ? r + recallDiameter / 2 + 8 : r - recallDiameter / 2 - 8
    }

    // MARK: キャンセル領域（照準中のみ表示）

    var cancelRadius: CGFloat { 38 * scale }
    var cancelCenter: CGPoint {
        mirrored(CGPoint(x: trailingEdge - 64 * scale, y: topEdge + 58 * scale))
    }

    /// スキル照準の最大ドラッグ量（pt）。
    var aimDragRadius: CGFloat { 84 * scale }

    // MARK: スティック

    var joystickRadius: CGFloat { 58 * scale }
    var joystickKnob: CGFloat { 48 * scale }
    var joystickRest: CGPoint {
        mirrored(CGPoint(x: leadingEdge + 16 * scale + joystickRadius, y: bottomEdge - 24 * scale - joystickRadius))
    }

    /// フローティングスティックの受付領域。
    var joystickZone: CGRect {
        let top = minimapDockFrame.maxY + 8
        let panelNear = leftHanded ? size.width - (heroPanelCenterX + heroPanelWidth / 2) : heroPanelCenterX - heroPanelWidth / 2
        let w = max(140, min(size.width * 0.42, panelNear - 4))
        return CGRect(x: leftHanded ? size.width - w : 0, y: top, width: w, height: size.height - top)
    }

    /// 固定スティックも地図ボタンの下から入力を受ける。
    var fixedJoystickZone: CGRect {
        let reach = joystickRadius * 1.5
        let top = max(joystickRest.y - reach, minimapDockFrame.maxY + 8)
        return CGRect(x: joystickRest.x - reach, y: top, width: reach * 2,
                      height: max(0, joystickRest.y + reach - top))
    }

    // MARK: 上部

    var minimapSize: CGFloat { min(172, max(138, size.height * 0.38)) }
    var minimapFrame: CGRect {
        let x = leftHanded ? trailingEdge - minimapSize - 2 : leadingEdge + 2
        return CGRect(x: x, y: topEdge, width: minimapSize, height: minimapSize)
    }

    /// 地図と拡大ボタンをまとめた領域。移動スティックの入力領域から除外する。
    var minimapDockFrame: CGRect {
        CGRect(x: minimapFrame.minX, y: topEdge, width: minimapSize, height: minimapSize + 48)
    }

    var tacticalMapSize: CGFloat { min(340, max(180, bottomEdge - topEdge - 88)) }
    var tacticalLegendWidth: CGFloat { min(190, max(148, width * 0.22)) }
    var topInfoAlignment: Alignment { leftHanded ? .topLeading : .topTrailing }

    var topButtonSize: CGFloat { 44 }

    // MARK: 下部中央のヒーローパネル

    var heroPanelWidth: CGFloat { 290 * min(scale, 1.08) }

    /// スティックとスキル群の間の中央。
    var heroPanelCenterX: CGFloat {
        let joyEdge = leftHanded ? joystickRest.x - joystickRadius : joystickRest.x + joystickRadius
        let clusterEdge = clusterInnerEdge
        return (joyEdge + clusterEdge) / 2
    }

    // MARK: 上部中央（スコア）

    /// 上部中央のスコアカプセル（topEdge + 22 が中心）の下端（余白込み）。
    var scoreCapsuleBottom: CGFloat { topEdge + 22 + 24 * min(scale, 1.1) }
}

// MARK: - 観戦の配置

/// 観戦・リプレイの HUD の配置（下部ドック・情報パネル・目標タイマー・バナー・戦術マップ）。座標は HUD 全面のローカル座標。
///
/// 下部ドックは Safe Area の内側の幅いっぱいに置き、2 段にする:
/// - 上段（シークできる時）: 一時停止・速度・±10 秒・シークバー・次の見どころ（幅があれば ±30 秒とコマ送りも）
/// - 下段: ブルー 5 人 | 前後の切り替え・観戦メニュー（オンラインの観戦席は LIVE 表示）| レッド 5 人
/// 速度ボタン 5 つを並べる幅が無い画面（iPhone SE）は速度を 1 つの切り替えボタンにまとめ、選択肢は観戦メニューへ。
/// 情報パネル（ヒーロー詳細・ゴールド推移・出来事）は右上ボタンの下（左利き配置では左）に置く。
struct HUDSpectatorLayout: Equatable {
    let base: HUDLayout
    /// シークできる（オフラインの観戦・リプレイ）。上段に再生バーを出す。
    let seekable: Bool
    /// 1 段にまとめる（戦術マップを開いている間）。シークできる時は再生バーだけ、オンラインはヒーローだけ。
    var compact = false

    static let button: CGFloat = 44
    static let gap: CGFloat = 4
    static let padding: CGFloat = 6
    static let rowSpacing: CGFloat = 4
    static let heroSize = CGSize(width: 44, height: 48)
    static let heroSpacing: CGFloat = 3
    static let groupGap: CGFloat = 8
    static let timeLabelWidth: CGFloat = 50
    static let speedSpacing: CGFloat = 2
    /// シークバーの最小の長さ（これを切るなら速度ボタンを畳む）。
    static let minSeekBar: CGFloat = 150
    /// BattleController.spectatorSpeeds の数（単体テストで一致を確認する）。
    static let speedButtonCount = 5
    static let teamSize = 5

    init(base: HUDLayout, seekable: Bool, compact: Bool = false) {
        self.base = base
        self.seekable = seekable
        self.compact = compact
    }

    var usableWidth: CGFloat { base.trailingEdge - base.leadingEdge }
    var innerWidth: CGFloat { usableWidth - Self.padding * 2 }

    // MARK: 下段（ヒーロー）

    var teamGroupWidth: CGFloat {
        CGFloat(Self.teamSize) * Self.heroSize.width + CGFloat(Self.teamSize - 1) * Self.heroSpacing
    }

    /// 下段の中央（両チームの間）の幅。
    var heroCenterWidth: CGFloat { innerWidth - teamGroupWidth * 2 - Self.groupGap * 2 }

    /// 下段の中央に前後のヒーロー切り替えを置けるか（無ければ観戦メニューへ）。
    var showsPrevNext: Bool { heroCenterWidth >= Self.button * 3 + Self.gap * 2 }

    var showsHeroRow: Bool { !(compact && seekable) }

    // MARK: 上段（再生）

    var showsTransportRow: Bool { seekable }

    private var speedGroupInlineWidth: CGFloat {
        CGFloat(Self.speedButtonCount) * Self.button + CGFloat(Self.speedButtonCount - 1) * Self.speedSpacing
    }

    /// 上段の固定部分の幅（⏯・速度・−10・時刻・（バー）・終わり・+10・次の見どころ の 8 項目と 7 つの間隔）。
    private func transportFixedWidth(inlineSpeeds: Bool) -> CGFloat {
        let speeds = inlineSpeeds ? speedGroupInlineWidth : Self.button
        return Self.button + speeds + Self.button * 3 + Self.timeLabelWidth * 2 + Self.gap * 7
    }

    /// 速度ボタンを全部並べるか（狭い画面は 1 つの切り替えボタン）。
    var inlineSpeeds: Bool { innerWidth - transportFixedWidth(inlineSpeeds: true) >= Self.minSeekBar }

    private var baseSeekBar: CGFloat { innerWidth - transportFixedWidth(inlineSpeeds: inlineSpeeds) }

    /// コマ送りを上段に置けるか（無ければ観戦メニュー）。
    var inlineStep: Bool { baseSeekBar - (Self.button + Self.gap) >= Self.minSeekBar }

    /// ±30 秒を上段に置けるか。
    var inlineSkip30: Bool {
        inlineStep && baseSeekBar - (Self.button + Self.gap) * 3 >= Self.minSeekBar
    }

    /// シークバーの長さ（タッチ領域の幅）。
    var seekBarWidth: CGFloat {
        var w = baseSeekBar
        if inlineStep { w -= Self.button + Self.gap }
        if inlineSkip30 { w -= (Self.button + Self.gap) * 2 }
        return max(0, w)
    }

    // MARK: ドック全体

    var transportRowHeight: CGFloat { Self.button }
    var heroRowHeight: CGFloat { Self.heroSize.height }

    var dockHeight: CGFloat {
        let rows = (showsTransportRow ? transportRowHeight : 0) + (showsHeroRow ? heroRowHeight : 0)
        let spacing = showsTransportRow && showsHeroRow ? Self.rowSpacing : 0
        return rows + spacing + Self.padding * 2
    }

    var dockFrame: CGRect {
        CGRect(x: base.leadingEdge, y: base.bottomEdge - dockHeight, width: usableWidth, height: dockHeight)
    }

    var dockTop: CGFloat { dockFrame.minY }

    /// 上段（再生）の枠（HUD 座標）。
    var transportRowFrame: CGRect? {
        guard showsTransportRow else { return nil }
        return CGRect(x: dockFrame.minX + Self.padding, y: dockFrame.minY + Self.padding,
                      width: innerWidth, height: transportRowHeight)
    }

    /// 下段（ヒーロー）の枠。
    var heroRowFrame: CGRect? {
        guard showsHeroRow else { return nil }
        return CGRect(x: dockFrame.minX + Self.padding, y: dockFrame.maxY - Self.padding - heroRowHeight,
                      width: innerWidth, height: heroRowHeight)
    }

    // MARK: 上部中央

    /// 情報パネルを開いている時は、ミニマップとパネルの間の中央へ寄せる。
    func topCenterX(panelOpen: Bool) -> CGFloat {
        guard panelOpen else { return base.width / 2 }
        let map = base.minimapFrame
        let panel = infoPanelFrame
        return base.leftHanded ? (panel.maxX + map.minX) / 2 : (map.maxX + panel.minX) / 2
    }

    /// 上部中央の帯（ゴールド・目標タイマー）に使える幅（ミニマップ・情報パネルに掛からない）。
    func topCenterWidth(panelOpen: Bool) -> CGFloat {
        let map = base.minimapFrame
        if panelOpen {
            let panel = infoPanelFrame
            return max(0, (base.leftHanded ? map.minX - panel.maxX : panel.minX - map.maxX) - 12)
        }
        let mapInner = base.leftHanded ? base.width - map.minX : map.maxX
        return max(0, (base.width / 2 - mapInner - 6) * 2)
    }

    static let scorePillHeight: CGFloat = 26
    static let objectivesHeight: CGFloat = 22

    /// 両チームのゴールド（とゴールド差）の帯の中心。
    var scorePillCenterY: CGFloat { base.scoreCapsuleBottom + 4 + Self.scorePillHeight / 2 }
    /// 目標タイマーの帯の中心。
    var objectivesCenterY: CGFloat { scorePillCenterY + Self.scorePillHeight / 2 + 4 + Self.objectivesHeight / 2 }
    var objectivesBottom: CGFloat { objectivesCenterY + Self.objectivesHeight / 2 }

    /// 告知バナーの半分の高さ（見積もり。ポートレート 44pt × 倍率 + 縦の余白）。
    var bannerHalfHeight: CGFloat { 32 * min(base.scale, 1.1) }

    /// 告知バナーの中心（スコア・目標タイマーの帯と重ならない）。
    var bannerCenterY: CGFloat { max(base.height * 0.27, objectivesBottom + 6 + bannerHalfHeight) }

    // MARK: 情報パネル

    var infoPanelWidth: CGFloat { min(320, max(240, usableWidth * 0.36)) }

    /// 情報パネル（右上ボタンの下からドックの上まで）。
    var infoPanelFrame: CGRect {
        let top = base.topEdge + base.topButtonSize + 8
        let bottom = dockTop - 6
        let x = base.leftHanded ? base.leadingEdge : base.trailingEdge - infoPanelWidth
        return CGRect(x: x, y: top, width: infoPanelWidth, height: max(0, bottom - top))
    }

    // MARK: 観戦メニュー（引き出し）

    var drawerFrame: CGRect {
        let width = min(420, usableWidth - 20)
        let maxHeight = max(120, dockTop - base.topEdge - 10)
        return CGRect(x: base.width / 2 - width / 2, y: dockTop - 6 - maxHeight, width: width, height: maxHeight)
    }

    // MARK: シネマ表示

    /// HUD を隠している間に残す「戻す」ボタンの中心（右下。左利き配置では左下）。
    var cinematicRestoreCenter: CGPoint {
        CGPoint(x: base.mx(base.trailingEdge - Self.button / 2 - 4), y: base.bottomEdge - Self.button / 2 - 4)
    }

    // MARK: 戦術マップ（観戦）

    /// 戦術マップを開いている間のドック（1 段）の上端。
    var compactDockTop: CGFloat {
        HUDSpectatorLayout(base: base, seekable: seekable, compact: true).dockTop
    }

    /// 観戦者の戦術マップの大きさ（1 段のドックの上に収める）。
    var tacticalMapSize: CGFloat { min(340, max(150, compactDockTop - base.topEdge - 78 - 16)) }

    /// 観戦者の戦術マップのカードの中心。
    var tacticalMapCenter: CGPoint {
        CGPoint(x: (base.leadingEdge + base.trailingEdge) / 2, y: (base.topEdge + compactDockTop - 4) / 2)
    }

    // MARK: 再生終了のカード

    /// 再生終了のカード（ドックの上の空き）の中心。
    var endCardCenter: CGPoint {
        CGPoint(x: base.width / 2, y: (base.topEdge + dockTop) / 2)
    }
}
