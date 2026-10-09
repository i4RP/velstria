import XCTest
@testable import VELSTRIA
import VelstriaCore

// 内部テスト用の全ヒーロー解放（TesterAccess）。本物のコードはリポジトリに無いので、検証はハッシュとの突き合わせの形だけを試す。
final class TesterAccessTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "TesterAccessTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testNormalizeIgnoresCaseHyphensAndSpaces() {
        XCTAssertEqual(TesterAccess.normalize(" ab-c d\n"), "ABCD")
        XCTAssertEqual(TesterAccess.digest(of: "abc"), TesterAccess.digest(of: "A-B-C"))
    }

    func testDigestIsSHA256Hex() {
        // SHA-256("ABC")
        XCTAssertEqual(TesterAccess.digest(of: "abc"), "b5d4045c3f466fa91fe2cc6abe79232a1a57cdf104f7a26e716e0a1e2789df78")
    }

    func testRedeemAcceptsOnlyTheMatchingCode() {
        let d = freshDefaults()
        let expected = TesterAccess.digest(of: "TEST1-CODE2")
        XCTAssertFalse(TesterAccess.redeem("wrong", expectedDigest: expected, defaults: d))
        XCTAssertFalse(TesterAccess.isUnlocked(defaults: d))
        XCTAssertTrue(TesterAccess.redeem("test1-code2", expectedDigest: expected, defaults: d))
        XCTAssertTrue(TesterAccess.isUnlocked(defaults: d))
        TesterAccess.clear(defaults: d)
        XCTAssertFalse(TesterAccess.isUnlocked(defaults: d))
    }

    func testRealDigestRejectsGuessesAndEmpty() {
        XCTAssertFalse(TesterAccess.isValid(""))
        XCTAssertFalse(TesterAccess.isValid("00000-00000-00000-00000"))
        XCTAssertEqual(TesterAccess.codeDigest.count, 64)
    }

    func testGrantAddsEveryHeroKeepsOrderAndIsIdempotent() {
        let master = MasterData.shared
        var p = Profile()
        let before = p.ownedHeroIDs
        XCTAssertTrue(TesterAccess.grantAllHeroes(to: &p, master: master))
        XCTAssertEqual(Array(p.ownedHeroIDs.prefix(before.count)), before)
        XCTAssertEqual(Set(p.ownedHeroIDs), Set(master.heroes.map(\.heroID)))
        XCTAssertEqual(p.ownedHeroIDs.count, master.heroes.count)
        XCTAssertFalse(TesterAccess.grantAllHeroes(to: &p, master: master))
    }

    func testApplyIfUnlockedOnlyWhenFlagged() {
        let d = freshDefaults()
        let master = MasterData.shared
        var p = Profile()
        TesterAccess.applyIfUnlocked(to: &p, master: master, defaults: d)
        XCTAssertEqual(p.ownedHeroIDs.count, 6)
        d.set(true, forKey: TesterAccess.flagKey)
        TesterAccess.applyIfUnlocked(to: &p, master: master, defaults: d)
        XCTAssertEqual(p.ownedHeroIDs.count, master.heroes.count)
    }
}
