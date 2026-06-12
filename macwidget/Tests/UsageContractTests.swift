import Foundation
import XCTest
@testable import QuotaWidgetApp

final class UsageContractTests: XCTestCase {
    func testDecodesLiveStaleAndFailedProviders() throws {
        let json = """
        {
          "schema_version": 1,
          "claude": {
            "ok": true, "live": true, "fetched_at": 100,
            "five_h": {"pct": 85, "resets_at": 200},
            "weekly": {"pct": 29, "resets_at": 300}
          },
          "codex": {
            "ok": true, "live": false, "fetched_at": 110, "as_of": 105,
            "five_h": {"pct": 88, "resets_at": 210, "stale": true},
            "weekly": {"pct": 37, "resets_at": 310, "stale": false}
          },
          "kimi": {"ok": false, "reason": "expired", "live": false}
        }
        """

        let payload = try UsagePayload.decode(Data(json.utf8))

        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertEqual(payload.claude.fiveH?.percentage, 85)
        XCTAssertTrue(payload.codex.fiveH?.stale == true)
        XCTAssertEqual(payload.kimi.reason, "expired")
    }

    func testProviderMessageMatchesSharedFailureLanguage() {
        let provider = UsageProvider(ok: false, reason: "rate_limited")
        XCTAssertEqual(
            ProviderPresentation.message(for: .claude, provider: provider),
            "请求受限 · 稍后自动重试"
        )
    }

    func testMediumWidgetUsesCompactRing() {
        XCTAssertLessThanOrEqual(WidgetLayout.mediumRingSize, 56)
    }
}
