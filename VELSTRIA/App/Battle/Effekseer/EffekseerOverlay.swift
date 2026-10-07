import QuartzCore
import RealityKit
import UIKit

// 担当: Effekseer の効果を戦闘画面（RealityKit の ARView）の上に重ねて描く。
// 効果ファイル（.efk）は VELSTRIA/Effects/Effekseer/ を「フォルダ参照」としてバンドルへ入れる（相対パスのテクスチャを読むため）。
// 作り方は docs/EFFEKSEER.md、ゲーム内の再生は EffekseerDirector。

final class EffekseerOverlay {
    let runtime: EfkRuntime
    /// 同梱のフォルダ名（バンドル直下）。
    static let bundleFolder = "Effekseer"
    /// 読み込み済みの効果名（拡張子なしのファイル名）。
    private(set) var effectNames: Set<String> = []
    private(set) var isLoaded = false

    /// Metal が使えない環境では nil（効果は出さない。ゲームは普通に動く）。
    init?() {
        guard let runtime = EfkRuntime() else { return nil }
        self.runtime = runtime
        runtime.layer.contentsGravity = .resize
        runtime.layer.isOpaque = false
    }

    /// 同梱フォルダの .efk をすべて読み込む（戦闘の準備中に 1 回。読み込みは小さい）。
    /// heroes を渡すと、そのヒーローの効果（H003_*.efk）と、ヒーロー名を持たない共通の効果だけ読む。
    func loadBundledEffects(heroes: Set<String>? = nil, bundle: Bundle = .main) {
        isLoaded = true
        guard let dir = bundle.url(forResource: Self.bundleFolder, withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "efk" {
            let name = url.deletingPathExtension().lastPathComponent
            if let heroes, name.count > 5, name.hasPrefix("H"), !heroes.contains(String(name.prefix(4))) { continue }
            if runtime.loadEffectNamed(name, path: url.path, magnification: 1) { effectNames.insert(name) }
        }
    }

    func attach(to host: UIView) {
        host.layer.addSublayer(runtime.layer)
        layout(in: host)
    }

    /// ホストの大きさ・解像度へ合わせる。
    func layout(in host: UIView, scale: CGFloat? = nil) {
        let s = scale ?? host.window?.screen.scale ?? host.traitCollection.displayScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        runtime.layer.frame = host.bounds
        runtime.layer.contentsScale = s
        CATransaction.commit()
    }

    @discardableResult
    func play(_ name: String, at p: SIMD3<Float>, yaw: Float = 0, scale: Float = 1, speed: Float = 1) -> Int32 {
        runtime.playNamed(name, position: p, yaw: yaw, scale: scale, speed: speed)
    }

    /// 1 フレーム進めて描く（dt = 0 で止める）。
    func render(camera: Entity, host: UIView, dt: Double) {
        let scale = runtime.layer.contentsScale
        let size = CGSize(width: host.bounds.width * scale, height: host.bounds.height * scale)
        runtime.render(withCameraWorld: camera.transformMatrix(relativeTo: nil),
                       verticalFOV: CameraRig.fovDegrees * .pi / 180, near: 1.0, far: 160,
                       deltaSeconds: dt, drawableSize: size)
    }
}

#if DEBUG
/// 効果の確認用: 再生を止めたまま、/tmp/efk-advance というファイルが置かれるたびに step フレームずつ進める
/// （tools/effekseer/preview.sh が 1 コマごとにファイルを置いてスクリーンショットを撮る）。frames を過ぎたら最初から。
struct EffekseerDemo {
    static let trigger = "/tmp/efk-advance"
    private var played: Double = 0
    private var started = false
    private var index = 0

    /// names はカンマ区切り。1 つ撮り終えると（frames を過ぎると）次の効果へ。
    mutating func advance(dt: Double, fx: EffekseerOverlay, names: String, at p: SIMD3<Float>, yaw: Float, ahead: Float,
                          frames: Double, step: Double) -> Double {
        guard FileManager.default.fileExists(atPath: Self.trigger) else { return 0 }
        try? FileManager.default.removeItem(atPath: Self.trigger)
        let list = names.split(separator: ",").map(String.init)
        guard !list.isEmpty else { return 0 }
        if !started || played >= frames {
            if started { index += 1 }
            started = true
            fx.runtime.stopAll()
            let forward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
            fx.play(list[index % list.count], at: p + forward * ahead, yaw: yaw)
            played = 0
            return 0
        }
        played += step
        return step / 60
    }
}
#endif
