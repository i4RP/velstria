import SwiftUI
import VelstriaCore

// 担当: battle-hud（signals）。クイックシグナル（攻撃・撤退・集合・クイックチャット）:
// - シグナル列は情報側の端（右手配置は右、左利きは左。K/D/A 等の情報列と同じ側）で、情報列の直下の 1 行。
//   折りたたみ時は端のボタン 1 個、展開時はその内側へ チャット・集合・撤退・攻撃 を並べる
//   （端の縦の余白は上の攻撃ボタン・必殺技・習得バッジまで 50〜100pt しかないため横に並べる。
//   5 つ並べると習得バッジのタップ領域にかかる狭い画面（iPhone 13 mini）では 3 つ + 下の行に 2 つ）
// - キルフィードはシグナル列と右側クラスタ（スペル・習得バッジ）より内側（スコアの下）に置く（killFeedSideReserve）
// - 送信: メッセージ（最大 4 件・6 秒。ミニマップの下で、移動スティックの待機位置の円にかからない行数だけ新しいものを出す）、
//   ミニマップのピン（広がるリング + 印）、効果音と触覚。連打防止 2 秒
// - 味方ボットの定型返信（ピンに最も近い生存中の味方 1 人が約 1 秒後に「了解！」等）は表示だけ。
//   オフライン対 AI のためシミュレーションには何も送らない（ボットの行動・決定論・リプレイに影響しない）
// - チャットボタンで定型文のメニュー（タップで送信、外側のタップで閉じる）。チュートリアルでは出さない
// 15Hz の更新（refresh）はメッセージ・ピンが残っている間だけ働き、変化した時だけ観測値を書き換える。

// MARK: - 種類と文言

/// シグナルの種類（ミニマップのピン・メッセージの色と記号）。
enum HUDSignalKind: String, CaseIterable, Hashable {
    case attack, retreat, gather

    var text: String {
        switch self {
        case .attack: return L("攻撃！", "Attack!")
        case .retreat: return L("撤退！", "Retreat!")
        case .gather: return L("集合！", "Group up!")
        }
    }

    /// VoiceOver のボタン名。
    var buttonLabel: String {
        switch self {
        case .attack: return L("攻撃のシグナル", "Signal: attack")
        case .retreat: return L("撤退のシグナル", "Signal: retreat")
        case .gather: return L("集合のシグナル", "Signal: group up")
        }
    }

    /// 色だけに頼らないよう、ボタン・メッセージは記号、ミニマップのピンは中心の印の形でも区別する。
    var color: Color {
        switch self {
        case .attack: return Color(red: 1.0, green: 0.66, blue: 0.22)
        case .retreat: return Color(red: 1.0, green: 0.42, blue: 0.60)
        case .gather: return Color(red: 0.38, green: 0.92, blue: 0.56)
        }
    }
}

/// クイックチャットの定型文。
enum HUDQuickChat: String, CaseIterable, Hashable {
    case nice, thanks, careful, missing, defendTower, takeBoss

    var text: String {
        switch self {
        case .nice: return L("いいね！", "Nice!")
        case .thanks: return L("ありがとう！", "Thanks!")
        case .careful: return L("気をつけて！", "Careful!")
        case .missing: return L("敵が見えない（ミア）", "Enemy missing!")
        case .defendTower: return L("タワーを守ろう", "Defend the tower")
        case .takeBoss: return L("ボスを狙おう", "Let's take the boss")
        }
    }

    var symbol: String {
        switch self {
        case .nice: return "hand.thumbsup.fill"
        case .thanks: return "heart.fill"
        case .careful: return "exclamationmark.triangle.fill"
        case .missing: return "eye.slash.fill"
        case .defendTower: return "building.columns.fill"
        case .takeBoss: return "crown.fill"
        }
    }
}

/// 送れるもの（シグナル 3 種と定型文）。
enum HUDSignal: Hashable {
    case signal(HUDSignalKind)
    case chat(HUDQuickChat)
}

/// メッセージ 1 件（自分の送信・味方ボットの返信）。
struct HUDSignalMessage: Identifiable, Equatable {
    enum Icon: Equatable {
        case signal(HUDSignalKind)
        case chat(HUDQuickChat)
        /// 味方の返信（了解の印 + 元のシグナルの色）。
        case reply(HUDSignalKind)

        var color: Color {
            switch self {
            case .signal(let k), .reply(let k): return k.color
            case .chat: return Theme.cyan
            }
        }
    }

    var id: Int
    var icon: Icon
    /// 「あなた」または味方のヒーロー名。
    var sender: String
    var isHuman: Bool
    var text: String
    /// HUD の時計（systemUptime）。
    var createdAt: TimeInterval
}

/// 返信の候補（自分以外の味方ヒーロー）。
struct HUDSignalAlly: Equatable {
    var id: EntityID
    var name: String
    var pos: Vec2
    var alive: Bool
}

/// 届く前の味方の返信。
struct HUDSignalReply: Equatable {
    var allyID: EntityID
    var sender: String
    var kind: HUDSignalKind
    var text: String
    var dueAt: TimeInterval
}

// MARK: - 状態（純粋な値型）

/// シグナルの状態（クールダウン・メッセージ・ピン・返信待ち）。時刻は引数で受ける（単体テスト対象）。
struct HUDSignalBoard: Equatable {
    /// 連打防止（シグナル・定型文の共通）。
    static let cooldown: TimeInterval = 2
    static let messageLifetime: TimeInterval = 6
    static let maxMessages = 4
    static let pingLifetime: TimeInterval = 2.4
    static let maxPings = 4

    /// 古い順。
    private(set) var messages: [HUDSignalMessage] = []
    private(set) var pings: [HUDMinimapBuffer.Ping] = []
    private(set) var replies: [HUDSignalReply] = []
    /// 次に送れる時刻。
    private(set) var readyAt: TimeInterval = -.infinity
    /// 送信の通し番号（返信の文言・間合いの選択に使う）。
    private(set) var sequence = 0
    private var nextID = 0

    /// 表示するもの・届く前の返信が無い。
    var isIdle: Bool { messages.isEmpty && pings.isEmpty && replies.isEmpty }

    func canSend(now: TimeInterval) -> Bool { now >= readyAt }

    /// 送信する（クールダウン中は何もせず false）。pos はピンの位置（nil ならピン無し）。
    @discardableResult
    mutating func send(_ signal: HUDSignal, sender: String, at pos: Vec2?, allies: [HUDSignalAlly],
                       now: TimeInterval) -> Bool {
        guard canSend(now: now) else { return false }
        readyAt = now + Self.cooldown
        sequence += 1
        switch signal {
        case .signal(let kind):
            post(.signal(kind), sender: sender, isHuman: true, text: kind.text, now: now)
            if let pos {
                pings.append(HUDMinimapBuffer.Ping(pos: pos, kind: kind, createdAt: now))
                if pings.count > Self.maxPings { pings.removeFirst(pings.count - Self.maxPings) }
            }
            if let ally = Self.replier(allies, near: pos) {
                replies.append(HUDSignalReply(allyID: ally.id, sender: ally.name, kind: kind,
                                              text: Self.replyText(kind, sequence: sequence),
                                              dueAt: now + Self.replyDelay(sequence: sequence)))
            }
        case .chat(let phrase):
            // 定型文には返信しない（ピンも無し）
            post(.chat(phrase), sender: sender, isHuman: true, text: phrase.text, now: now)
        }
        return true
    }

    /// 返信の配達と期限切れの削除。戻り値は届いた返信の数。
    @discardableResult
    mutating func update(now: TimeInterval) -> Int {
        var delivered = 0
        while let k = replies.indices.min(by: { replies[$0].dueAt < replies[$1].dueAt }), replies[k].dueAt <= now {
            let r = replies.remove(at: k)
            post(.reply(r.kind), sender: r.sender, isHuman: false, text: r.text, now: now)
            delivered += 1
        }
        if messages.contains(where: { now - $0.createdAt >= Self.messageLifetime }) {
            messages.removeAll { now - $0.createdAt >= Self.messageLifetime }
        }
        if pings.contains(where: { now - $0.createdAt >= Self.pingLifetime }) {
            pings.removeAll { now - $0.createdAt >= Self.pingLifetime }
        }
        return delivered
    }

    private mutating func post(_ icon: HUDSignalMessage.Icon, sender: String, isHuman: Bool, text: String,
                               now: TimeInterval) {
        nextID &+= 1
        messages.append(HUDSignalMessage(id: nextID, icon: icon, sender: sender, isHuman: isHuman, text: text,
                                         createdAt: now))
        if messages.count > Self.maxMessages { messages.removeFirst(messages.count - Self.maxMessages) }
    }

    // MARK: 味方の返信（決定的: 同じ入力なら同じ味方・文言・間合い）

    /// 返信する味方: 生存中でピンに最も近い 1 人（同じ距離なら ID の小さい方。ピンが無ければ ID の小さい方）。
    static func replier(_ allies: [HUDSignalAlly], near pos: Vec2?) -> HUDSignalAlly? {
        allies.filter(\.alive).min { a, b in
            let da = pos.map { a.pos.distanceSquared(to: $0) } ?? 0
            let db = pos.map { b.pos.distanceSquared(to: $0) } ?? 0
            return da != db ? da < db : a.id < b.id
        }
    }

    static func replyText(_ kind: HUDSignalKind, sequence: Int) -> String {
        let alt = sequence % 2 == 0
        switch kind {
        case .attack: return alt ? L("任せて！", "Leave it to me!") : L("了解！", "On it!")
        case .retreat: return alt ? L("引こう！", "Backing off!") : L("了解、引く！", "Falling back!")
        case .gather: return alt ? L("すぐ行く！", "Coming!") : L("向かう！", "On my way!")
        }
    }

    /// 1.0 / 1.2 / 0.8 秒を順に使う（毎回同じ間合いだと機械的に見えるため）。
    static func replyDelay(sequence: Int) -> TimeInterval {
        [0.8, 1.0, 1.2][sequence % 3]
    }
}

// MARK: - HUD 側の窓口

@Observable
@MainActor
final class HUDSignalCenter {
    /// 表示中のメッセージ（古い順。最大 4 件）。
    private(set) var messages: [HUDSignalMessage] = []
    /// シグナル列を展開しているか（試合中だけ。保存しない）。
    private(set) var isExpanded = true
    private(set) var chatMenuOpen = false
    /// 連打防止の待ち（ボタンを暗くする）。
    private(set) var coolingDown = false

    @ObservationIgnored private(set) var board = HUDSignalBoard()

    /// 15Hz（HUDModel.refresh から。ミニマップの更新の後）。
    func refresh(model: HUDModel, now: TimeInterval) {
        if chatMenuOpen && (model.panel != nil || model.deathRecapOpen || model.isAiming || !model.canControl) {
            chatMenuOpen = false
        }
        if coolingDown && board.canSend(now: now) { coolingDown = false }
        let buffer = model.minimap
        guard !board.isIdle || !buffer.pings.isEmpty else { return }
        if board.update(now: now) > 0 {
            model.appModel?.audio.play(.uiTap, gain: 0.6)
        }
        publish(buffer, now: now)
    }

    /// 試合を出る時。
    func stop() {
        board = HUDSignalBoard()
        messages = []
        chatMenuOpen = false
        coolingDown = false
    }

    /// シグナル・定型文を送る（表示と効果音だけ。シミュレーションには送らない）。
    func send(_ signal: HUDSignal, model: HUDModel, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard model.canControl, !model.isTutorial else { return }
        chatMenuOpen = false
        guard board.canSend(now: now) else {
            model.appModel?.haptics.impact(.soft, intensity: 0.5)
            return
        }
        // ピンはカメラの注視点（死亡中・ミニマップでカメラを動かしている時はそこ）
        let pos = model.cameraCenter(model.controller.state)
        board.send(signal, sender: L("あなた", "You"), at: pos, allies: Self.allies(model), now: now)
        coolingDown = true
        publish(model.minimap, now: now)
        model.appModel?.audio.play(.uiConfirm)
        model.appModel?.haptics.impact(.light)
    }

    func toggleExpanded(model: HUDModel) {
        isExpanded.toggle()
        if !isExpanded { chatMenuOpen = false }
        model.appModel?.audio.play(.uiTap)
        model.appModel?.haptics.selection()
    }

    func toggleChatMenu(model: HUDModel) {
        guard model.canControl, !model.isTutorial else { return }
        chatMenuOpen.toggle()
        model.appModel?.audio.play(chatMenuOpen ? .uiTap : .uiBack)
        model.appModel?.haptics.selection()
    }

    func closeChatMenu() {
        chatMenuOpen = false
    }

    private func publish(_ buffer: HUDMinimapBuffer, now: TimeInterval) {
        if board.messages != messages { messages = board.messages }
        buffer.pings = board.pings
        buffer.pingClock = now
    }

    /// 返信の送り主の名前。正式名は二つ名が付いて長く（「Mirea, Tidecaller」「城門の誓衛アルデン」）、
    /// メッセージの欄（17 Pro で約 131pt）では返信の文言ごと「…」で切れるので、短い名前にする
    /// （英語はカンマより前の「Mirea」、日本語は末尾のカタカナの「アルデン」。取り出せなければ正式名）。
    static func senderName(_ def: HeroDef) -> String {
        let full = MasterText.hero(def)
        let short: Substring
        if Loc.isEnglish {
            guard let comma = full.firstIndex(of: ",") else { return full }
            short = full[..<comma]
        } else {
            let katakana: ClosedRange<Unicode.Scalar> = "\u{30A0}"..."\u{30FF}"
            let tail = full.reversed().prefix { $0.unicodeScalars.allSatisfy(katakana.contains) }
            short = Substring(String(tail.reversed()))
        }
        let name = short.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? full : name
    }

    /// 返信の候補（自分以外の味方。生死は上部の味方列と同じ値を使う）。
    static func allies(_ model: HUDModel) -> [HUDSignalAlly] {
        guard let team = model.humanTeam else { return [] }
        let s = model.controller.state
        let master = model.controller.ctx.master
        let me = model.controller.humanHeroID
        let shown = model.allies
        return s.heroIndices(team: team).compactMap { i in
            let u = s.units[i]
            guard u.id != me, let h = u.hero else { return nil }
            let dead = shown.first(where: { $0.id == u.id })?.isDead ?? h.isDead
            let name = master.hero(h.heroID).map { senderName($0) } ?? h.displayName
            return HUDSignalAlly(id: u.id, name: name, pos: u.pos, alive: u.isAlive && !dead)
        }
    }
}

// MARK: - 表示

/// 情報側の端のシグナル列・クイックチャットのメニュー・メッセージ（操作中のみ。チュートリアルでは出さない）。
/// 全画面の座標で配置する。空き領域はタップを奪わない（メニューを開いている間だけ外側のタップで閉じる）。
struct HUDSignalLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        ZStack {
            if !model.isTutorial {
                HUDSignalMenuCatcher(center: model.signals)
                HUDSignalMessageList(model: model, center: model.signals, layout: layout)
                HUDSignalTray(model: model, center: model.signals, layout: layout)
                HUDSignalChatMenu(model: model, center: model.signals, layout: layout)
            }
        }
        .frame(width: layout.width, height: layout.height)
    }
}

/// メニューの外側のタップで閉じる（開いている間だけ置く。それ以外はタップを奪わない）。
private struct HUDSignalMenuCatcher: View {
    let center: HUDSignalCenter

    var body: some View {
        if center.chatMenuOpen {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { center.closeChatMenu() }
                .accessibilityHidden(true)
        }
    }
}

/// シグナル列（照準中はキャンセル領域と重なるので隠す）。
private struct HUDSignalTray: View {
    let model: HUDModel
    let center: HUDSignalCenter
    let layout: HUDLayout

    var body: some View {
        let expanded = center.isExpanded
        let hidden = model.isAiming
        let toggle = layout.signalSlotFrame(.toggle)
        ZStack {
            if expanded {
                ForEach(HUDSignalSlot.tray, id: \.self) { slot in
                    let f = layout.signalSlotFrame(slot)
                    button(slot)
                        .position(x: f.midX, y: f.midY)
                        .transition(.opacity.combined(with: .offset(x: toggle.midX - f.midX, y: toggle.midY - f.midY)))
                }
            }
            toggleButton(expanded: expanded)
                .position(x: toggle.midX, y: toggle.midY)
        }
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
        .animation(.spring(duration: 0.3, bounce: 0.15), value: expanded)
        .animation(.easeOut(duration: 0.15), value: hidden)
    }

    @ViewBuilder
    private func button(_ slot: HUDSignalSlot) -> some View {
        let size = layout.signalButtonSize
        let dimmed = center.coolingDown
        switch slot {
        case .attack, .retreat, .gather:
            let kind = slot.kind ?? .attack
            HUDSignalButton(size: size, hit: layout.signalHitSize, tint: kind.color, dimmed: dimmed,
                            label: kind.buttonLabel, identifier: "hud_signal_\(kind.rawValue)") {
                center.send(.signal(kind), model: model)
            } icon: {
                HUDSignalGlyph(icon: .signal(kind), size: size * 0.5)
            }
        case .chat:
            HUDSignalButton(size: size, hit: layout.signalHitSize, tint: Theme.cyan, dimmed: dimmed,
                            highlighted: center.chatMenuOpen, label: L("クイックチャット", "Quick chat"),
                            identifier: "hud_signal_chat") {
                center.toggleChatMenu(model: model)
            } icon: {
                Image(systemName: "ellipsis.bubble.fill")
                    .font(.system(size: size * 0.44, weight: .bold))
            }
        case .toggle:
            EmptyView()
        }
    }

    private func toggleButton(expanded: Bool) -> some View {
        let size = layout.signalButtonSize
        // 端へたたむ向き（右手配置 = 右、左利き = 左）
        let toEdge = layout.leftHanded ? "chevron.left" : "chevron.right"
        let fromEdge = layout.leftHanded ? "chevron.right" : "chevron.left"
        return HUDSignalButton(size: size, hit: layout.signalHitSize, tint: .white, dimmed: false,
                               label: expanded ? L("シグナルをたたむ", "Hide signals") : L("シグナルを表示", "Show signals"),
                               identifier: "hud_signal_toggle") {
            center.toggleExpanded(model: model)
        } icon: {
            if expanded {
                Image(systemName: toEdge)
                    .font(.system(size: size * 0.38, weight: .heavy))
            } else {
                // たたんだ状態: 「‹」+ メガホン（ここにシグナルがあると分かるように）
                HStack(spacing: 0) {
                    if !layout.leftHanded {
                        Image(systemName: fromEdge).font(.system(size: size * 0.24, weight: .heavy))
                    }
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: size * 0.36, weight: .bold))
                        .scaleEffect(x: layout.leftHanded ? -1 : 1, y: 1)
                    if layout.leftHanded {
                        Image(systemName: fromEdge).font(.system(size: size * 0.24, weight: .heavy))
                    }
                }
            }
        }
    }
}

/// 列の丸ボタン（見た目は小さめ、タップ領域は 44pt の正方形）。
private struct HUDSignalButton<Icon: View>: View {
    let size: CGFloat
    let hit: CGFloat
    let tint: Color
    let dimmed: Bool
    var highlighted = false
    let label: String
    let identifier: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [highlighted ? tint.opacity(0.45) : HUDStyle.glassTop, HUDStyle.glassBottom],
                                         startPoint: .top, endPoint: .bottom))
                Circle()
                    .strokeBorder(LinearGradient(colors: [tint.opacity(highlighted ? 1 : 0.7), tint.opacity(0.15)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
                icon()
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.5), radius: 3)
                    .opacity(dimmed ? 0.4 : 1)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
            .frame(width: hit, height: hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// シグナル・定型文の記号（攻撃は攻撃ボタンと同じ交差した剣）。色は呼び出し側の foregroundStyle。
struct HUDSignalGlyph: View {
    let icon: HUDSignalMessage.Icon
    let size: CGFloat

    var body: some View {
        switch icon {
        case .signal(.attack):
            HUDCrossedSwords()
                .frame(width: size * 1.05, height: size * 1.05)
        case .signal(.retreat):
            // 背を向けて走る（左向き）
            Image(systemName: "figure.run")
                .font(.system(size: size * 0.9, weight: .bold))
                .scaleEffect(x: -1, y: 1)
        case .signal(.gather):
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: size * 0.82, weight: .heavy))
        case .chat(let phrase):
            Image(systemName: phrase.symbol)
                .font(.system(size: size * 0.78, weight: .bold))
        case .reply:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.8, weight: .black))
        }
    }
}

/// クイックチャットの定型文メニュー（シグナル列の下、情報側の端にそろえる）。
private struct HUDSignalChatMenu: View {
    let model: HUDModel
    let center: HUDSignalCenter
    let layout: HUDLayout

    var body: some View {
        let open = center.chatMenuOpen
        ZStack {
            if open {
                let f = layout.signalChatMenuFrame
                menu
                    .frame(width: f.width, height: f.height)
                    .position(x: f.midX, y: f.midY)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .animation(.spring(duration: 0.22), value: open)
        // ショップ・ポーズ等のパネルやデス情報を開いたら閉じる（ポーズ中は 15Hz の更新が止まるため、ここでも見る）
        .onChange(of: model.panel) { _, p in if p != nil { center.closeChatMenu() } }
        .onChange(of: model.deathRecapOpen) { _, on in if on { center.closeChatMenu() } }
    }

    private var menu: some View {
        let phrases = HUDQuickChat.allCases
        let dimmed = center.coolingDown
        return VStack(spacing: HUDLayout.signalChatSpacing) {
            ForEach(0..<(phrases.count + 1) / 2, id: \.self) { row in
                HStack(spacing: HUDLayout.signalChatSpacing) {
                    ForEach(phrases[(row * 2)..<min(phrases.count, row * 2 + 2)], id: \.self) { p in
                        item(p, dimmed: dimmed)
                    }
                }
            }
        }
        .padding(HUDLayout.signalChatPadding)
        .hudGlass(cornerRadius: 14, tint: Theme.cyan.opacity(0.6))
        .shadow(color: .black.opacity(0.5), radius: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud_chat_menu")
    }

    private func item(_ p: HUDQuickChat, dimmed: Bool) -> some View {
        Button { center.send(.chat(p), model: model) } label: {
            HStack(spacing: 6) {
                Image(systemName: p.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.cyan)
                    .frame(width: 16)
                Text(p.text)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .opacity(dimmed ? 0.45 : 1)
            .padding(.horizontal, 10)
            .frame(width: HUDLayout.signalChatItemSize.width, height: HUDLayout.signalChatItemSize.height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(p.text)
        .accessibilityIdentifier("hud_chat_\(p.rawValue)")
    }
}

/// メッセージの欄（ミニマップの下。タップを奪わない）。
private struct HUDSignalMessageList: View {
    let model: HUDModel
    let center: HUDSignalCenter
    let layout: HUDLayout

    var body: some View {
        let f = layout.signalMessageFrame
        // ミニマップの側の端にそろえる（右手配置 = 左、左利き = 右）
        let trailing = layout.leftHanded
        // ミニマップの下は降参投票の欄と重なるため、投票中は隠す
        let hidden = model.surrender != nil
        let colorblind = model.settings.colorblindMode
        // 移動スティックの待機位置の円にかからない行数だけ（新しいもの）を出す
        let messages = Array(center.messages.suffix(layout.signalMessageRows))
        VStack(alignment: trailing ? .trailing : .leading, spacing: layout.signalMessageSpacing) {
            ForEach(messages) { m in
                HUDSignalMessageRow(message: m, colorblind: colorblind, height: layout.signalMessageRowHeight)
                    .transition(.move(edge: trailing ? .trailing : .leading).combined(with: .opacity))
            }
        }
        .frame(width: f.width, height: f.height, alignment: trailing ? .topTrailing : .topLeading)
        .position(x: f.midX, y: f.midY)
        .opacity(hidden ? 0 : 1)
        .animation(.spring(duration: 0.3), value: messages.map(\.id))
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud_signal_messages")
    }
}

private struct HUDSignalMessageRow: View {
    let message: HUDSignalMessage
    let colorblind: Bool
    let height: CGFloat

    var body: some View {
        let tint = message.icon.color
        HStack(spacing: 4) {
            ZStack {
                Circle().fill(tint)
                HUDSignalGlyph(icon: message.icon, size: height * 0.5)
                    .foregroundStyle(Color.black.opacity(0.78))
            }
            .frame(width: height - 3, height: height - 3)
            Text(message.sender)
                .foregroundStyle(message.isHuman ? Theme.gold : Theme.teamColor(.blue, colorblind: colorblind))
            Text(message.text)
                .foregroundStyle(.white)
        }
        .font(.system(size: height * 0.66, weight: .bold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .shadow(color: .black.opacity(0.6), radius: 1, y: 0.5)
        .padding(.leading, 1.5)
        .padding(.trailing, 8)
        .frame(height: height)
        .background(
            // 明るい地面の上でも読めるよう暗い地に、記号の側だけ種類の色を差す
            Capsule().fill(Color.black.opacity(0.62))
                .overlay(Capsule().fill(LinearGradient(stops: [.init(color: tint.opacity(0.38), location: 0),
                                                               .init(color: tint.opacity(0), location: 0.45)],
                                                       startPoint: .leading, endPoint: .trailing)))
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(message.sender) \(message.text)")
    }
}

// MARK: - 配置

/// シグナル列の枠（情報側の端から内側へ 折りたたみ・チャット・集合・撤退・攻撃）。
enum HUDSignalSlot: Int, CaseIterable {
    case toggle, chat, gather, retreat, attack

    /// 展開時だけ出るボタン。
    static let tray: [HUDSignalSlot] = [.attack, .retreat, .gather, .chat]

    var kind: HUDSignalKind? {
        switch self {
        case .attack: return .attack
        case .retreat: return .retreat
        case .gather: return .gather
        case .toggle, .chat: return nil
        }
    }
}

extension HUDLayout {
    /// シグナルのボタンの見た目の直径（タップ領域は signalHitSize の正方形）。
    var signalButtonSize: CGFloat { min(36, 32 * scale) }
    var signalHitSize: CGFloat { 44 }

    /// シグナル列の 1 行目の上端（情報側の上の列 = topEdge + 44 の直下）。
    var signalRowTop: CGFloat { topEdge + topButtonSize }

    /// 1 行に並べる数。5 つ並べると操作部品（習得バッジのタップ領域）にかかる狭い画面では 3 つにして残りを下の行へ。
    var signalTrayColumns: Int {
        let all = HUDSignalSlot.allCases.count
        return (0..<all).allSatisfy { signalAvoidsControls(signalCell(row: 0, column: $0)) } ? all : 3
    }

    /// 枠のタップ領域（情報側の端から 44pt ずつ内側へ。行があふれたら下の行の端から）。
    func signalSlotFrame(_ slot: HUDSignalSlot) -> CGRect {
        let columns = signalTrayColumns
        return signalCell(row: slot.rawValue / columns, column: slot.rawValue % columns)
    }

    private func signalCell(row: Int, column: Int) -> CGRect {
        let s = signalHitSize
        let x = leftHanded ? leadingEdge + CGFloat(column) * s : trailingEdge - CGFloat(column + 1) * s
        return CGRect(x: x, y: signalRowTop + CGFloat(row) * s, width: s, height: s)
    }

    /// 展開時の列全体。
    var signalTrayFrame: CGRect {
        HUDSignalSlot.allCases.reduce(signalSlotFrame(.toggle)) { $0.union(signalSlotFrame($1)) }
    }

    /// 右側クラスタの操作部品（攻撃ボタン 3 つ・スキル・必殺技・スペル・帰還）の円。
    var signalControlDiscs: [(center: CGPoint, radius: CGFloat)] {
        var out = AttackButtonSlot.allCases.map { (center: attackCenter(for: $0), radius: attackDiameter(for: $0) / 2) }
        for slot in SkillSlot.actives {
            out.append((skillCenter(slot), (slot == .ultimate ? ultDiameter : skillDiameter) / 2))
        }
        out.append((spellCenter(0), spellDiameter / 2))
        out.append((spellCenter(1), spellDiameter / 2))
        out.append((recallCenter, recallDiameter / 2))
        return out
    }

    /// 習得バッジのタップ領域（HUDLevelBadge.touchDiameter = 44 の正方形。スキルポイントがある時だけ出る）。
    var signalLevelBadgeRects: [CGRect] {
        SkillSlot.actives.map { slot in
            let c = levelBadgeCenter(slot)
            return CGRect(x: c.x - 22, y: c.y - 22, width: 44, height: 44)
        }
    }

    /// 矩形が操作部品の円・習得バッジのタップ領域から margin 以上離れているか。
    func signalAvoidsControls(_ r: CGRect, margin: CGFloat = 2) -> Bool {
        for d in signalControlDiscs {
            let dx = max(r.minX - d.center.x, 0, d.center.x - r.maxX)
            let dy = max(r.minY - d.center.y, 0, d.center.y - r.maxY)
            if dx * dx + dy * dy < (d.radius + margin) * (d.radius + margin) { return false }
        }
        return !signalLevelBadgeRects.contains { $0.insetBy(dx: -margin, dy: -margin).intersects(r) }
    }

    // MARK: キルフィード

    /// キルフィードの見積もり（最大 4 行 × 26pt + 行間 3。幅は 2 桁アシストの行で約 96pt）。
    static let killFeedEstimate = CGSize(width: 96, height: 4 * 26 + 3 * 3)

    /// キルフィードの上端（情報列の下）。
    var killFeedTop: CGFloat { topEdge + 52 }

    /// キルフィードの情報側（右手配置は右端、左利きは左端）に空ける幅。
    /// 端の側はシグナル列に加えて、4 行のキルフィードの高さに上の攻撃ボタン・必殺技・習得バッジ・スペルがかかるため、
    /// それらより内側（スコアの下）まで空ける。
    var killFeedSideReserve: CGFloat {
        let band = killFeedTop...(killFeedTop + Self.killFeedEstimate.height)
        // 端からの距離（右手配置は trailingEdge − 内側の x、左利きは内側の x − leadingEdge）
        func depth(_ innerX: CGFloat) -> CGFloat { leftHanded ? innerX - leadingEdge : trailingEdge - innerX }
        var reserve = signalTrayFrame.width + 6
        for d in signalControlDiscs where d.center.y - d.radius <= band.upperBound && d.center.y + d.radius >= band.lowerBound {
            reserve = max(reserve, depth(leftHanded ? d.center.x + d.radius : d.center.x - d.radius) + 4)
        }
        for r in signalLevelBadgeRects where r.minY <= band.upperBound && r.maxY >= band.lowerBound {
            reserve = max(reserve, depth(leftHanded ? r.maxX : r.minX) + 4)
        }
        return reserve
    }

    // MARK: クイックチャットのメニュー

    static let signalChatItemSize = CGSize(width: 132, height: 44)
    static let signalChatSpacing: CGFloat = 6
    static let signalChatPadding: CGFloat = 8

    /// シグナル列の下（情報側の端にそろえる）。2 列 × 3 行。
    var signalChatMenuFrame: CGRect {
        let rows = CGFloat((HUDQuickChat.allCases.count + 1) / 2)
        let item = Self.signalChatItemSize
        let w = item.width * 2 + Self.signalChatSpacing + Self.signalChatPadding * 2
        let h = item.height * rows + Self.signalChatSpacing * (rows - 1) + Self.signalChatPadding * 2
        let tray = signalTrayFrame
        return CGRect(x: leftHanded ? tray.minX : tray.maxX - w, y: tray.maxY + 4, width: w, height: h)
    }

    // MARK: メッセージ

    var signalMessageRowHeight: CGFloat { 16 * min(scale, 1.1) }
    var signalMessageSpacing: CGFloat { 2 }

    /// メッセージの欄に出す行数（最大 4。最低 1）。欄の下端を移動スティックの待機位置の円の上端より上に収める
    /// （主な端末ではミニマップドックと円の間が 1〜2 行分しかない）。
    var signalMessageRows: Int {
        let top = minimapDockFrame.maxY + 4
        let bottom = joystickRest.y - joystickRadius - 2
        let fit = Int(((bottom - top + signalMessageSpacing) / (signalMessageRowHeight + signalMessageSpacing)).rounded(.down))
        return min(HUDSignalBoard.maxMessages, max(1, fit))
    }

    /// メッセージの欄（signalMessageRows 行）。ミニマップ（と全体マップのボタン）の下、ミニマップの側の端にそろえる。
    /// 幅は下部のヒーローパネル（と上の状態アイコン列）にかからない分まで。
    var signalMessageFrame: CGRect {
        let n = CGFloat(signalMessageRows)
        let h = signalMessageRowHeight * n + signalMessageSpacing * (n - 1)
        let dock = minimapDockFrame
        let panelNear = leftHanded ? heroPanelCenterX + heroPanelWidth / 2 : heroPanelCenterX - heroPanelWidth / 2
        let room = leftHanded ? dock.maxX - panelNear - 6 : panelNear - 6 - dock.minX
        let w = min(200 * min(scale, 1.1), room)
        return CGRect(x: leftHanded ? dock.maxX - w : dock.minX, y: dock.maxY + 4, width: w, height: h)
    }
}
