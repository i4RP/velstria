import QuartzCore
import simd
import UIKit
import VelstriaCore

// 担当: battle-renderer。戦闘数値（ダメージ・回復・Gold）の UIKit オーバーレイ。
// CATextLayer をプールし、描画フレームのカメラを一度だけ読み、数値をまとめて投影する。

/// Battle camera uses vertical FOV and a unit-scale world anchor. Avoid querying RealityKit
/// for every label: those queries can synchronize with the render engine.
struct CombatTextProjection {
    let position: SIMD3<Float>
    let inverseOrientation: simd_quatf
    let viewport: CGSize
    let focalLength: Float
    let near: Float
    let far: Float

    init(position: SIMD3<Float>, orientation: simd_quatf, viewport: CGSize,
         verticalFOV: Float, near: Float = 1, far: Float = 160) {
        self.position = position
        inverseOrientation = orientation.inverse
        self.viewport = viewport
        focalLength = Float(viewport.height) / (2 * tan(verticalFOV * .pi / 360))
        self.near = near
        self.far = far
    }

    func project(_ world: SIMD3<Float>) -> CGPoint? {
        guard viewport.width > 0, viewport.height > 0, focalLength.isFinite else { return nil }
        let p = inverseOrientation.act(world - position)
        let depth = -p.z
        guard depth >= near, depth <= far else { return nil }
        let x = viewport.width / 2 + CGFloat(p.x * focalLength / depth)
        let y = viewport.height / 2 - CGFloat(p.y * focalLength / depth)
        // Keep partially visible labels at the border, but avoid offscreen layer updates.
        guard x.isFinite, y.isFinite, x >= -80, x <= viewport.width + 80,
              y >= -80, y <= viewport.height + 80 else { return nil }
        return CGPoint(x: x, y: y)
    }
}

enum CombatTextStyle: Equatable {
    /// 自分（追従ヒーロー）が与えたダメージ。
    case dealt(DamageType, crit: Bool)
    /// 自分が受けたダメージ。
    case taken
    case heal
    case gold
    case shield
}

final class CombatTextOverlay: UIView {
    private struct Entry {
        var layer: CATextLayer
        var world: SIMD3<Float> = .zero
        var age: Float = 0
        var life: Float = 1
        var drift: Float = 0
        var rise: Float = 1
        var popScale: CGFloat = 1
        var active = false
    }

    private var entries: [Entry] = []
    private var cursor = 0
    static let capacity = 40
    private let fontCache = FontCache()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        let scale = UIScreen.main.scale
        entries.reserveCapacity(Self.capacity)
        for _ in 0..<Self.capacity {
            let l = CATextLayer()
            l.contentsScale = scale
            l.alignmentMode = .center
            l.isHidden = true
            l.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "transform": NSNull(),
                         "contents": NSNull(), "hidden": NSNull(), "string": NSNull()]
            layer.addSublayer(l)
            entries.append(Entry(layer: l))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var activeCount: Int { entries.reduce(0) { $0 + ($1.active ? 1 : 0) } }

    func spawn(text: String, world: SIMD3<Float>, style: CombatTextStyle, seed: Int) {
        let (size, color, life, rise): (CGFloat, UIColor, Float, Float)
        switch style {
        case .dealt(let type, let crit):
            let base: UIColor
            switch type {
            case .physical: base = UIColor(red: 1.0, green: 0.93, blue: 0.82, alpha: 1)
            case .magic: base = UIColor(red: 0.78, green: 0.66, blue: 1.0, alpha: 1)
            case .trueDamage: base = .white
            }
            size = crit ? 27 : 19
            color = crit ? UIColor(red: 1.0, green: 0.78, blue: 0.25, alpha: 1) : base
            life = crit ? 1.05 : 0.85
            rise = crit ? 1.3 : 1.0
        case .taken:
            size = 18; color = UIColor(red: 1.0, green: 0.36, blue: 0.36, alpha: 1); life = 0.9; rise = 0.9
        case .heal:
            size = 18; color = UIColor(red: 0.45, green: 1.0, blue: 0.52, alpha: 1); life = 1.0; rise = 1.1
        case .gold:
            size = 17; color = UIColor(red: 1.0, green: 0.84, blue: 0.30, alpha: 1); life = 1.2; rise = 1.2
        case .shield:
            size = 16; color = UIColor(red: 0.85, green: 0.92, blue: 1.0, alpha: 1); life = 0.9; rise = 1.0
        }
        let i = nextSlot()
        var e = entries[i]
        let font = fontCache.font(size: size)
        let attr = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color.cgColor,
            .strokeColor: UIColor(white: 0.02, alpha: 0.9).cgColor,
            .strokeWidth: -4.5,
        ])
        let bounds = attr.boundingRect(with: CGSize(width: 400, height: 80), options: [.usesLineFragmentOrigin], context: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        e.layer.string = attr
        e.layer.bounds = CGRect(x: 0, y: 0, width: ceil(bounds.width) + 8, height: ceil(bounds.height) + 2)
        e.layer.opacity = 0
        e.layer.isHidden = false
        CATransaction.commit()
        e.world = world
        e.age = 0
        e.life = life
        e.rise = rise
        // 同時多発で重ならないよう左右に散らす
        e.drift = Float((seed &* 7919) % 7 - 3) * 0.12
        e.popScale = style == .dealt(.physical, crit: true) || style == .dealt(.magic, crit: true)
            || style == .dealt(.trueDamage, crit: true) ? 1.6 : 1.3
        e.active = true
        entries[i] = e
    }

    private func nextSlot() -> Int {
        for k in 0..<entries.count {
            let i = (cursor + k) % entries.count
            if !entries[i].active {
                cursor = (i + 1) % entries.count
                return i
            }
        }
        // 満杯なら最も古いもの（循環カーソル位置）を再利用
        let i = cursor
        cursor = (cursor + 1) % entries.count
        return i
    }

    /// 経過・投影を更新する（毎フレーム）。project が nil を返したら（画面外・背面）非表示。
    func update(dt: Float, project: (SIMD3<Float>) -> CGPoint?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for i in entries.indices where entries[i].active {
            entries[i].age += dt
            let e = entries[i]
            if e.age >= e.life {
                entries[i].active = false
                e.layer.isHidden = true
                continue
            }
            let t = e.age / e.life
            // 上昇は減速（ease-out）、横ずれは一定
            let rise = e.rise * (1 - (1 - t) * (1 - t))
            let p = e.world + SIMD3(e.drift * t * 2, rise, 0)
            guard let screen = project(p) else {
                e.layer.isHidden = true
                continue
            }
            e.layer.isHidden = false
            e.layer.position = screen
            let pop: CGFloat = e.age < 0.12 ? e.popScale - (e.popScale - 1) * CGFloat(e.age / 0.12) : 1
            e.layer.transform = CATransform3DMakeScale(pop, pop, 1)
            e.layer.opacity = t < 0.08 ? t / 0.08 : (t > 0.65 ? max(0, (1 - t) / 0.35) : 1)
        }
        CATransaction.commit()
    }

    func clear() {
        for i in entries.indices {
            entries[i].active = false
            entries[i].layer.isHidden = true
        }
    }

    /// 丸ゴシック太字の CTFont キャッシュ。
    private final class FontCache {
        private var fonts: [CGFloat: UIFont] = [:]

        func font(size: CGFloat) -> UIFont {
            if let f = fonts[size] { return f }
            let base = UIFont.systemFont(ofSize: size, weight: .heavy)
            let f = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
            fonts[size] = f
            return f
        }
    }
}

/// 数値の表示形式（戦闘数値）。
enum CombatTextFormat {
    static func damage(_ v: Double, crit: Bool) -> String {
        let n = Int(v.rounded())
        return crit ? "\(n)!" : "\(n)"
    }

    static func plus(_ v: Double) -> String { "+\(Int(v.rounded()))" }
}
