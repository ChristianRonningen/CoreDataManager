import XCTest
@testable import CoreDataManager

final class CoreDataManagerTests: XCTestCase {
    func testInit() {
        
        CoreDataManager.configuration = CoreDataManagerConfiguration(persistentContainerName: "CoreDataManagerTestDataModel", migrationBlock: nil)
        
        
        XCTAssert(CoreDataManager.shared != nil, "Singleton")
    }

    static var allTests = [
        ("testInit", testInit),
    ]
}
