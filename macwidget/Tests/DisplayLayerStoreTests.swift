import Foundation
import XCTest
@testable import QuotaWidgetApp

final class DisplayLayerStoreTests: XCTestCase {
    func testUbersichtDestinationCandidatesIncludeBothUnicodeForms() {
        let home = URL(fileURLWithPath: "/tmp/home", isDirectory: true)
        let candidates = DisplayLayerStore.ubersichtWidgetDirectories(homeDirectory: home)
            .map(\.path)

        XCTAssertTrue(candidates.contains("/tmp/home/Library/Application Support/Übersicht/widgets"))
        XCTAssertTrue(candidates.contains("/tmp/home/Library/Application Support/Übersicht/widgets"))
    }

    func testDisplayStatusDetectsInstalledUbersichtWidget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let widget = root
            .appendingPathComponent("Library/Application Support/Übersicht/widgets/usage-widget", isDirectory: true)
        try FileManager.default.createDirectory(at: widget, withIntermediateDirectories: true)
        try "marker".write(to: widget.appendingPathComponent("index.jsx"), atomically: true, encoding: .utf8)

        let store = DisplayLayerStore(
            homeDirectory: root,
            applicationsDirectory: root.appendingPathComponent("Applications", isDirectory: true),
            processList: { [] }
        )

        let status = store.status(for: .ubersicht)

        XCTAssertEqual(status.layer, .ubersicht)
        XCTAssertTrue(status.installed)
        XCTAssertFalse(status.running)

        try? FileManager.default.removeItem(at: root)
    }
}
