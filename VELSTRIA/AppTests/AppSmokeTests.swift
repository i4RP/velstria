import XCTest
@testable import VELSTRIA
import VelstriaCore

final class AppSmokeTests: XCTestCase {
    func testProfileRoundTrip() throws {
        let p = Profile()
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Profile.self, from: data)
        XCTAssertEqual(p, back)
    }
}
