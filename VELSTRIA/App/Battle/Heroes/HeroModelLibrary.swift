import Foundation
import RealityKit
import SwiftUI
import VelstriaCore

// 担当: hero-models（Wave 2）。現在は仮モデル（カプセル）。

@MainActor
enum HeroModelLibrary {
    static func makeModel(heroID: String, skinID: String?, team: Team, master: MasterData) -> HeroModelHandle {
        PlaceholderHeroModel(heroID: heroID, team: team)
    }
}

@MainActor
final class PlaceholderHeroModel: HeroModelHandle {
    let root = Entity()
    let overheadHeight: Float = 2.1

    init(heroID: String, team: Team) {
        let hue = Theme.heroHue(heroID)
        let color = UIColor(hue: hue, saturation: 0.7, brightness: 0.9, alpha: 1)
        let body = ModelEntity(mesh: .generateCylinder(height: 1.6, radius: 0.35),
                               materials: [SimpleMaterial(color: color, isMetallic: false)])
        body.position.y = 0.8
        root.addChild(body)
    }

    func setState(_ state: HeroAnimState) {}
    func update(dt: Double, moveSpeed: Double) {}
}

/// ヒーロー詳細画面などで使う 3D プレビュー（hero-models が実装）。
struct HeroPreview3DView: View {
    let heroID: String
    var skinID: String?

    var body: some View {
        HeroPortraitView(heroID: heroID, size: 220)
    }
}

/// 全ヒーローの 3D モデル一覧（起動引数 -heroGallery）。hero-models が実装。
struct HeroGalleryView: View {
    var body: some View {
        Text("Hero Gallery")
    }
}
