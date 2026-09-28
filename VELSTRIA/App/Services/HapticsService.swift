import UIKit

// 担当: app-services
// 触覚フィードバック。ジェネレータは使い回し、発火後に prepare() して次回の遅延を抑える。
// 戦闘中の連打で振動が鳴りっぱなしにならないよう、直近 1 秒間の発火数を maxPerSecond（12）に制限する。

@MainActor
final class HapticsService {
    static let maxPerSecond = 12

    var enabled = true {
        didSet { if enabled && !oldValue { prepareAll() } }
    }

    /// 時刻の供給元（テストで差し替える）。
    var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// 実際に発火した回数・間引いた回数（テスト・デバッグ用）。
    private(set) var firedCount = 0
    private(set) var droppedCount = 0

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()
    /// 直近 1 秒間の発火時刻。
    private var recent: [TimeInterval] = []

    init() {
        prepareAll()
    }

    /// 全ジェネレータを準備状態にする（画面表示時などに呼ぶと初回の遅延が減る）。
    func prepareAll() {
        guard enabled else { return }
        light.prepare()
        medium.prepare()
        notification.prepare()
        selectionGenerator.prepare()
    }

    func tap() {
        guard admit() else { return }
        light.impactOccurred()
        light.prepare()
    }

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        impact(style, intensity: 1)
    }

    /// intensity: 0〜1。
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: Double) {
        guard admit() else { return }
        let g = generator(for: style)
        g.impactOccurred(intensity: CGFloat(min(1, max(0, intensity))))
        g.prepare()
    }

    func success() {
        notify(.success)
    }

    func warning() {
        notify(.warning)
    }

    func error() {
        notify(.error)
    }

    /// 選択の切り替え（ピッカー・タブ）。
    func selection() {
        guard admit() else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard admit() else { return }
        notification.notificationOccurred(type)
        notification.prepare()
    }

    private func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .light: return light
        case .medium: return medium
        case .heavy: return heavy
        case .rigid: return rigid
        case .soft: return soft
        @unknown default: return medium
        }
    }

    /// 有効かつレート上限内なら記録して true。
    private func admit() -> Bool {
        guard enabled else { return false }
        let now = clock()
        recent.removeAll { now - $0 >= 1 }
        guard recent.count < Self.maxPerSecond else {
            droppedCount += 1
            return false
        }
        recent.append(now)
        firedCount += 1
        return true
    }
}
