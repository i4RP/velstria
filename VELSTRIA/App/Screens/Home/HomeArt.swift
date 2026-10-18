import SwiftUI
import UIKit

// 担当: home-showcase。ホーム中央のヒーローアートの読み込み（Assets.xcassets の HeroSplash / HeroSplashMatte）。
// 生成元は tools/portraits/splash.py（ヒーローアートと人物マスク）。背景の HomeBackdrop は HomeView が Image で直接読む
// （生成の手順は tools/portraits/home_backdrop.md）。無ければ nil を返し、呼び出し側は描き下ろしのポートレート（PortraitArt）で代用する。

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

    @MainActor private static func image(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        let img = UIImage(named: name)
        cache[name] = img
        return img
    }
}
