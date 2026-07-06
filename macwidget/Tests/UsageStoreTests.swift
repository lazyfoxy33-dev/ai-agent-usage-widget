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

    func testWritesCodexActiveRefreshConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = AppConfigStore(baseDirectory: directory)

        try store.writeCodexActiveRefresh(enabled: true, intervalSeconds: 1800)
        let data = try Data(contentsOf: store.configURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["codex_active_refresh"] as? Bool, true)
        XCTAssertEqual(json?["codex_refresh_interval_seconds"] as? Int, 1800)
    }

    func testWriteCodexActiveRefreshPreservesUnrelatedKeys() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = AppConfigStore(baseDirectory: directory)
        let existing: [String: Any] = [
            "existing_key": "preserve",
            "schema_version": 42,
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existing)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try existingData.write(to: store.configURL)

        try store.writeCodexActiveRefresh(enabled: false, intervalSeconds: 60)
        let data = try Data(contentsOf: store.configURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["codex_active_refresh"] as? Bool, false)
        XCTAssertEqual(json?["codex_refresh_interval_seconds"] as? Int, 60)
        XCTAssertEqual(json?["existing_key"] as? String, "preserve")
        XCTAssertEqual(json?["schema_version"] as? Int, 42)
    }

    func testSharedStateStatusReportsMissingContainer() {
        let store = UsageStore(containerURLProvider: { nil })

        let status = store.status()

        XCTAssertFalse(status.available)
        XCTAssertEqual(status.reason, .missingContainer)
        XCTAssertNil(status.usagePath)
    }

    func testSharedStateStatusReportsUsageFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = UsageStore(containerURLProvider: { directory })
        try store.write("{\"schema_version\":1}")

        let status = store.status()

        XCTAssertTrue(status.available)
        XCTAssertTrue(status.usagePath?.hasSuffix("Library/Application Support/usage.json") ?? false)
        XCTAssertNotNil(status.modifiedAt)

        try? FileManager.default.removeItem(at: directory)
    }
}
