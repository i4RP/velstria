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

/// ARView + UIKit オーバーレイ（周辺減光・戦闘数値・デバッグ表示・読み込み幕）。
final class BattleRenderView: UIView {
    let arView: ARView
    let vignette = VignetteView(frame: .zero)
    let combatText: CombatTextOverlay
    let curtain = UIView()
    #if DEBUG
    let debugOverlay = DebugStatsOverlay()
    #endif

    init(arView: ARView) {
        self.arView = arView
        self.combatText = CombatTextOverlay(frame: .zero)
        super.init(frame: .zero)
        backgroundColor = .black
        addSubview(arView)
        addSubview(vignette)
        addSubview(combatText)
        #if DEBUG
        addSubview(debugOverlay)
        #endif
        curtain.backgroundColor = UIColor(red: 0.03, green: 0.04, blue: 0.10, alpha: 1)
        curtain.isUserInteractionEnabled = false
        addSubview(curtain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        arView.frame = bounds
        vignette.frame = bounds
        combatText.frame = bounds
        curtain.frame = bounds
        #if DEBUG
        // ミニマップ（左上）の下に小さく
        let inset = safeAreaInsets
        debugOverlay.frame = CGRect(x: max(8, inset.left + 6), y: max(8, inset.top) + 176, width: 150, height: 30)
        #endif
    }

    func liftCurtain() {
        UIView.animate(withDuration: 0.45, delay: 0.05, options: [.curveEaseOut]) {
            self.curtain.alpha = 0
        } completion: { _ in
            self.curtain.isHidden = true
        }
    }
}
