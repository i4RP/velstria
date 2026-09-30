import XCTest
@testable import VELSTRIA
import VelstriaCore

@MainActor
final class HeroModelSkinTests: XCTestCase {
    private let master = MasterData.shared

    func testUnknownSkinFallsBackToDefault() {
        XCTAssertEqual(HeroSkins.resolve(heroID: "H001", skinID: nil, master: master), .standard)
        XCTAssertEqual(HeroSkins.resolve(heroID: "H001", skinID: "NOPE", master: master), .standard)
        // 他ヒーロー用のスキンは既定扱い
        if let other = HeroSkins.skins(for: "H007", master: master).first {
            XCTAssertEqual(HeroSkins.resolve(heroID: "H001", skinID: other.cosmeticID, master: master), .standard)
        }
        // スキン以外のコスメも既定扱い
        if let emote = master.cosmetics.first(where: { $0.type != .heroSkin }) {
            XCTAssertEqual(HeroSkins.resolve(heroID: "H001", skinID: emote.cosmeticID, master: master), .standard)
        }
    }

    func testSkinVariantsAndRarity() {
        for heroID in ["H001", "H007", "H013", "H019"] {
            let skins = HeroSkins.skins(for: heroID, master: master)
            XCTAssertFalse(skins.isEmpty, heroID)
            for (i, s) in skins.enumerated() {
                let info = HeroSkins.resolve(heroID: heroID, skinID: s.cosmeticID, master: master)
                XCTAssertEqual(info.variant, i + 1)
                XCTAssertEqual(info.rarity, s.rarity)
                let bp = HeroBlueprints.blueprint(heroID: heroID, role: nil)
                let base = HeroPalettes.palette(heroID: heroID, blueprint: bp, skin: .standard)
                let skinned = HeroPalettes.palette(heroID: heroID, blueprint: bp, skin: info)
                XCTAssertNotEqual(base.primary, skinned.primary, "\(heroID) \(s.cosmeticID) は配色が変わる")
                XCTAssertEqual(skinned.aura, info.isEpic)
                XCTAssertEqual(skinned.trimGlow > 0, info.isEpic)
            }
        }
    }

    func testDefaultPaletteUsesHeroHue() {
        for def in master.heroes {
            let bp = HeroBlueprints.blueprint(heroID: def.heroID, role: def.role)
            let p = HeroPalettes.palette(heroID: def.heroID, blueprint: bp, skin: .standard)
            XCTAssertEqual(p.primary.h, Theme.heroHue(def.heroID), accuracy: 0.0001)
            XCTAssertFalse(p.aura)
        }
    }

    func testSkinnedModelsBuild() {
        for c in master.cosmetics where c.type == .heroSkin {
            let model = HeroModelLibrary.makeHero(heroID: c.heroID, skinID: c.cosmeticID, team: .red, master: master,
                                                  options: .battle)
            XCTAssertEqual(model.skin.cosmeticID, c.cosmeticID)
            XCTAssertEqual(model.root.findEntity(named: "aura") != nil, c.rarity == .epic, c.cosmeticID)
            XCTAssertLessThanOrEqual(model.entityCount, 35)
        }
    }
}
