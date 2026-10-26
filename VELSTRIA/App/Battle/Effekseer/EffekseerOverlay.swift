import QuartzCore
import RealityKit
import UIKit

// 担当: Effekseer の効果を戦闘画面（RealityKit の ARView）に描く。実機の中・高画質は後処理の中（PostProcessor: 3D に隠れる・
// ブルームが掛かる・歪み）、シミュレータ・低画質・後処理の準備前は ARView の上に重ねる（docs/EFFEKSEER.md「描画の 2 つの経路」）。
// 効果ファイル（.efk）は VELSTRIA/Effects/Effekseer/ を「フォルダ参照」としてバンドルへ入れる（相対パスのテクスチャを読むため）。
// 作り方は docs/EFFEKSEER.md、ゲーム内の再生は EffekseerDirector。

final class EffekseerOverlay {
    let runtime: EfkRuntime
    /// 同梱のフォルダ名（バンドル直下）。
    static let bundleFolder = "Effekseer"
    /// キットのヒーローの段に重ねる効果（FXEfk）のフォルダ（bundleFolder の中。テクスチャは ../Texture/）。
    static let kitFolder = "Kit"
    /// 読み込み済みの効果名（拡張子なしのファイル名）。段の効果（EffekseerDirector の名前の規則）だけ。
    private(set) var effectNames: Set<String> = []
    /// 読み込み済みの重ねる効果の名前（FXEfk.name。ランタイムには kitKey(name) で登録する）。
    private(set) var kitEffectNames: Set<String> = []

    /// 重ねる効果のランタイムでの名前（段の効果と名前が重ならないように）。
    static func kitKey(_ name: String) -> String { kitFolder + "/" + name }
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
        // キットのヒーローの段に重ねる効果（<ヒーロー ID>_*.efk。試合のヒーローの分だけ）
        let kit = dir.appendingPathComponent(Self.kitFolder)
        for url in (try? FileManager.default.contentsOfDirectory(at: kit, includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == "efk" {
            let name = url.deletingPathExtension().lastPathComponent
            if let heroes, !heroes.contains(String(name.prefix(4))) { continue }
            if runtime.loadEffectNamed(Self.kitKey(name), path: url.path, magnification: 1) { kitEffectNames.insert(name) }
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

    /// 再生する。onTop = 3D の上に描く（後処理の中でも 3D に隠れない）。旧来の .efk（重ね描きの頃に作った。命中の閃きが体の中ほど）は
    /// 既定の true のまま。3D に隠れてよい効果（地面の跡・3D の中に立つ柱）は false（docs/EFFEKSEER.md「描画の 2 つの経路」）。
    @discardableResult
    func play(_ name: String, at p: SIMD3<Float>, yaw: Float = 0, scale: Float = 1, speed: Float = 1, onTop: Bool = true) -> Int32 {
        let h = runtime.playNamed(name, position: p, yaw: yaw, scale: scale, speed: speed)
        if h >= 0, onTop { runtime.setOnTop(true, handle: h) }
        return h
    }

    /// 1 フレーム進めて描く（dt = 0 で止める）。inPostProcess = true の時は進めるだけで、描くのは後処理（PostProcessor）。
    /// 重ねのレイヤーは後処理へ切り替えた時に空にして隠し、戻した時に見せる（EfkRuntime.drawsInPostProcess）。
    func render(camera: PerspectiveCamera, host: UIView, dt: Double, inPostProcess: Bool = false) {
        runtime.drawsInPostProcess = inPostProcess
        if inPostProcess {
            runtime.advance(cameraWorld: camera.transformMatrix(relativeTo: nil), deltaSeconds: dt)
            return
        }
        let scale = runtime.layer.contentsScale
        let size = CGSize(width: host.bounds.width * scale, height: host.bounds.height * scale)
        runtime.render(withCameraWorld: camera.transformMatrix(relativeTo: nil),
                       verticalFOV: camera.camera.fieldOfViewInDegrees * .pi / 180,
                       near: camera.camera.near, far: camera.camera.far,
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
