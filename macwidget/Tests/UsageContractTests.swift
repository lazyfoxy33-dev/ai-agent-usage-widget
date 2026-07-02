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
          "kimi": {"ok": false, "reason": "expired", "live": false},
          "deepseek": {
            "ok": true, "kind": "balance", "live": true, "fetched_at": 120,
            "balance": {"amount": 110.0, "currency": "CNY", "available": true, "label": "Balance"},
            "burn_rate": {"amount_per_day": 3.2, "window_days": 7, "estimated_days_left": 34, "confidence": "medium"}
          },
          "siliconflow": {
            "ok": true, "kind": "balance", "live": false, "reason": "stale",
            "balance": {"amount": 88.88, "currency": "CNY", "available": true, "label": "Balance"},
            "burn_rate": {"confidence": "none", "reason": "insufficient_history"}
          },
          "openrouter": {"ok": false, "kind": "balance", "reason": "no_data", "live": false}
        }
        """

        let payload = try UsagePayload.decode(Data(json.utf8))

        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertEqual(payload.claude.fiveH?.percentage, 85)
        XCTAssertTrue(payload.codex.fiveH?.stale == true)
        XCTAssertEqual(payload.kimi.reason, "expired")
        XCTAssertEqual(payload.deepseek.balance?.amount, 110.0)
        XCTAssertEqual(payload.deepseek.burnRate?.estimatedDaysLeft, 34)
        XCTAssertEqual(payload.siliconflow.burnRate?.confidence, "none")
        XCTAssertEqual(payload.openrouter.reason, "no_data")
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

    func testBalancePresentationFormatting() {
        let balance = BalanceInfo(amount: 24.58, currency: "USD", available: true, label: "Balance")
        let burn = BurnRateInfo(
            amountPerDay: 1.0,
            windowDays: 7,
            estimatedDaysLeft: 24,
            confidence: "medium",
            reason: nil
        )
        XCTAssertEqual(ProviderPresentation.balanceAmount(balance), "$24.58")
        XCTAssertFalse(ProviderPresentation.balanceTrend(burn).isEmpty)
    }
}
