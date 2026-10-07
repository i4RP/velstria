import SwiftUI
import UIKit

// 担当: home-showcase。ホーム画面のラスターアートの読み込み（Assets.xcassets の HeroSplash / HeroSplashMatte / HomeBackdrop）。
// 生成元は tools/portraits/splash.py（ヒーローアートと人物マスク）と tools/portraits/home_backdrop.md（背景）。
// どれも無ければ nil を返し、呼び出し側は描き下ろしのポートレート（PortraitArt）や手続きの背景で代用する。

enum HomeArt {
    @MainActor private static var cache: [String: UIImage?] = [:]

    /// ショーケースのヒーローアート（1024px）。装備中のスキンがあればスキンの絵、無ければヒーローの絵、
    /// それも無ければ 640px のポートレート。
    @MainActor static func splash(heroID: String, skinID: String?) -> UIImage? {
        if let skinID, let img = image("HeroSplash/\(skinID)") ?? PortraitArt.skin(skinID) { return img }
        return image("HeroSplash/\(heroID)") ?? PortraitArt.hero(heroID)
    }

    /// splash と同じ絵の人物マスク（白 = 人物）。絵とマスクの組を取り違えないよう、絵を決めたのと同じ規則で探す。
    @MainActor static func matte(heroID: String, skinID: String?) -> UIImage? {
        if let skinID, image("HeroSplash/\(skinID)") != nil || PortraitArt.skin(skinID) != nil {
            return image("HeroSplashMatte/\(skinID)")
        }
        return image("HeroSplashMatte/\(heroID)")
    }

    /// 戦場の背景。
    @MainActor static var backdrop: UIImage? { image("HomeBackdrop") }

    /// 手続きの背景で闘技場の床に使う石畳（ステージの素材を流用）。
    @MainActor static var floorTile: UIImage? {
        let key = "StageTile_paving"
        if let hit = cache[key] { return hit }
        let img = Bundle.main.url(forResource: key, withExtension: "jpg").flatMap { UIImage(contentsOfFile: $0.path) }
        cache[key] = img
        return img
    }

    @MainActor private static func image(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        let img = UIImage(named: name)
        cache[name] = img
        return img
    }
}
