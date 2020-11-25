import XCTest
@testable import CoreDataManager

final class CoreDataManagerTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(CoreDataManager().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
