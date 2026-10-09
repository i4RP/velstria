import RealityKit
import SwiftUI
import UIKit
import VelstriaCore

// 担当: battle-renderer（Wave 2）。
// RealityKit（ARView nonAR）で SimState を描画し、毎フレーム controller.frame(dt:) を呼んでループを駆動する。
// 画質・フレームレート・ダメージ数値の表示は AppModel のプロフィール設定から読む。

struct BattleSceneView: View {
    let controller: BattleController
    @Environment(AppModel.self) private var app

    var body: some View {
        BattleARViewRepresentable(controller: controller, settings: RenderSettings(app.profile.settings))
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// ARView のホスト。コーディネーター（BattleRenderer）が描画とループを所有する。
struct BattleARViewRepresentable: UIViewRepresentable {
    let controller: BattleController
    let settings: RenderSettings

    func makeCoordinator() -> BattleRenderer {
        BattleRenderer(controller: controller, settings: settings)
    }

    func makeUIView(context: Context) -> BattleRenderView {
        context.coordinator.makeView()
    }

    func updateUIView(_ uiView: BattleRenderView, context: Context) {
        context.coordinator.apply(settings: settings)
    }

    static func dismantleUIView(_ uiView: BattleRenderView, coordinator: BattleRenderer) {
        coordinator.teardown()
    }
}

/// 画面周辺をわずかに暗くする（視線を中央へ、四隅の HUD を読みやすく）。
final class VignetteView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        if let g = layer as? CAGradientLayer {
            g.type = .radial
            g.colors = [UIColor.clear.cgColor, UIColor(red: 0, green: 0.01, blue: 0.04, alpha: 0.32).cgColor]
            g.locations = [0.62, 1.0]
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1.08, y: 1.2)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// 読み込み幕（戦場の準備中に ARView を覆う）。下部に細い進捗バー・割合・いま行っている準備を出す
/// （ロード画面の進捗表示と同じ金色・等幅数字）。
final class LoadingCurtainView: UIView {
    private let track = UIView()
    private let fill = UIView()
    private let label = UILabel()
    private let percent = UILabel()
    /// 表示中の進み具合（0〜1。戻らない）。
    private(set) var progress: Double = 0
    private(set) var text = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.03, green: 0.04, blue: 0.10, alpha: 1)
        isUserInteractionEnabled = false
        let gold = UIColor(Theme.gold)
        track.backgroundColor = UIColor(white: 1, alpha: 0.12)
        track.layer.cornerRadius = 1.5
        track.clipsToBounds = true
        fill.backgroundColor = gold
        fill.layer.cornerRadius = 1.5
        track.addSubview(fill)
        let rounded = UIFont.systemFont(ofSize: 11, weight: .bold)
        label.font = rounded.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 11) } ?? rounded
        label.textColor = UIColor(Theme.textSecondary)
        label.lineBreakMode = .byTruncatingTail
        percent.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        percent.textColor = gold
        percent.textAlignment = .right
        percent.text = "0%"
        addSubview(track)
        addSubview(label)
        addSubview(percent)
        accessibilityIdentifier = "battle_loading_curtain"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func set(progress p: Double, label newText: String) {
        let v = max(progress, min(1, max(0, p)))
        let pct = Int((v * 100).rounded(.down))
        if pct != Int((progress * 100).rounded(.down)) || percent.text == nil { percent.text = "\(pct)%" }
        progress = v
        if newText != text {
            text = newText
            label.text = newText
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = min(300, max(160, bounds.width * 0.32))
        let bottom = bounds.height - max(safeAreaInsets.bottom, 14) - 26
        let x = (bounds.width - width) / 2
        track.frame = CGRect(x: x, y: bottom, width: width, height: 3)
        fill.frame = CGRect(x: 0, y: 0, width: width * CGFloat(progress), height: 3)
        percent.frame = CGRect(x: x + width - 56, y: bottom - 20, width: 56, height: 16)
        label.frame = CGRect(x: x, y: bottom - 20, width: width - 60, height: 16)
    }
}

/// ARView + UIKit オーバーレイ（周辺減光・戦闘数値・デバッグ表示・読み込み幕）。
final class BattleRenderView: UIView {
    let arView: ARView
    let vignette = VignetteView(frame: .zero)
    let combatText: CombatTextOverlay
    let curtain = LoadingCurtainView(frame: .zero)
    /// Effekseer の効果（3D 画面の上・暗い縁取りとダメージ数値の下）。Metal が使えない環境では nil。
    let effekseer: EffekseerOverlay? = EffekseerOverlay()
    #if DEBUG
    let debugOverlay = DebugStatsOverlay()
    #endif
    /// テスター用の性能モニター（PerfProbe）。使えないビルドでは nil。
    let perfLabel: PerfProbeLabel? = PerfProbe.isAvailable ? PerfProbeLabel() : nil

    init(arView: ARView) {
        self.arView = arView
        self.combatText = CombatTextOverlay(frame: .zero)
        super.init(frame: .zero)
        backgroundColor = .black
        addSubview(arView)
        effekseer?.attach(to: self)
        addSubview(vignette)
        addSubview(combatText)
        #if DEBUG
        addSubview(debugOverlay)
        #endif
        if let perfLabel { addSubview(perfLabel) }
        addSubview(curtain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        arView.frame = bounds
        effekseer?.layout(in: self, scale: arView.contentScaleFactor)
        vignette.frame = bounds
        combatText.frame = bounds
        curtain.frame = bounds
        #if DEBUG
        // ミニマップ（左上）の下に小さく
        let inset = safeAreaInsets
        debugOverlay.frame = CGRect(x: max(8, inset.left + 6), y: max(8, inset.top) + 176, width: 196, height: 30)
        #endif
        // ミニマップと「全体マップ」ボタンの下・ヒーローパネルの上の隙間
        if let perfLabel {
            perfLabel.frame = CGRect(x: max(8, safeAreaInsets.left + 6), y: max(8, safeAreaInsets.top) + 200, width: 250, height: 56)
            #if DEBUG
            debugOverlay.isHidden = !perfLabel.isHidden
            #endif
        }
    }

    /// 読み込み幕の進捗（0〜1）と、いま行っている準備の表示。
    func setLoading(progress: Double, label: String) {
        guard !curtain.isHidden else { return }
        curtain.set(progress: progress, label: label)
    }

    func liftCurtain() {
        UIView.animate(withDuration: 0.45, delay: 0.05, options: [.curveEaseOut]) {
            self.curtain.alpha = 0
        } completion: { _ in
            self.curtain.isHidden = true
        }
    }
}
