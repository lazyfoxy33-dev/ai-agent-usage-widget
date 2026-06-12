import Foundation
import XCTest
@testable import QuotaWidgetApp

final class UsageStoreTests: XCTestCase {
    func testAtomicWriteCanBeReadBack() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = UsageStore(containerURLProvider: { directory })
        let json = #"{"schema_version":1}"#

        try store.write(json)

        XCTAssertEqual(try store.read(), json)
    }
}
