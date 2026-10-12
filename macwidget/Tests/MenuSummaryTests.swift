import Foundation
import XCTest
@testable import QuotaWidgetApp

final class MenuSummaryTests: XCTestCase {
    private func payload(
        claude: UsageProvider = UsageProvider(ok: false, reason: "no_data", kind: "quota"),
        deepseek: UsageProvider = UsageProvider(ok: false, reason: "no_data", kind: "balance")
    ) -> UsagePayload {
        UsagePayload(
            schemaVersion: 1,
            claude: claude,
            codex: UsageProvider(ok: false, reason: "no_data", kind: "quota"),
            kimi: UsageProvider(ok: false, reason: "no_data", kind: "quota"),
            deepseek: deepseek,
            siliconflow: UsageProvider(ok: false, reason: "login_required", kind: "balance"),
            openrouter: UsageProvider(ok: false, reason: "no_data", kind: "balance")
        )
    }

    private func quotaProvider(fiveH: Double?, weekly: Double?, stale: Bool = false) -> UsageProvider {
        UsageProvider(
            ok: true,
            reason: stale ? "stale" : nil,
            kind: "quota",
            live: !stale,
            fiveH: fiveH.map { UsageWindow(percentage: $0) },
            weekly: weekly.map { UsageWindow(percentage: $0) }
        )
    }

    func testRowsFollowTheConfiguredOrder() {
        let rows = MenuSummary.rows(from: payload(), order: [.openrouter, .kimi, .deepseek])

        XCTAssertEqual(rows.map(\.id), [.openrouter, .kimi, .deepseek])
        XCTAssertEqual(rows.map(\.name), ["OpenRouter", "Kimi Code", "DeepSeek"])
    }

    func testQuotaMetricCarriesRemainingShares() {
        let rows = MenuSummary.rows(
            from: payload(claude: quotaProvider(fiveH: 47, weekly: 91)),
            order: [.claude]
        )

        XCTAssertEqual(rows.first?.metric, .quota(fiveH: 53, weekly: 9, cached: false))
    }

    func testSingleWindowQuotaMetric() {
        let rows = MenuSummary.rows(
            from: payload(claude: quotaProvider(fiveH: 100, weekly: nil)),
            order: [.claude]
        )

        XCTAssertEqual(rows.first?.metric, .quota(fiveH: 0, weekly: nil, cached: false))
    }

    func testCachedQuotaIsFlagged() {
        let rows = MenuSummary.rows(
            from: payload(claude: quotaProvider(fiveH: 20, weekly: nil, stale: true)),
            order: [.claude]
        )

        XCTAssertEqual(rows.first?.metric, .quota(fiveH: 80, weekly: nil, cached: true))
        XCTAssertEqual(rows.first?.isCached, true)
    }

    func testBalanceMetricCarriesAmountTrendAndDays() {
        let burnRate = BurnRateInfo(
            amountPerDay: 3.0,
            windowDays: 7,
            estimatedDaysLeft: 12,
            confidence: "medium",
            reason: nil
        )
        let deepseek = UsageProvider(
            ok: true,
            kind: "balance",
            live: true,
            balance: BalanceInfo(amount: 108, currency: "CNY", available: true, label: "Balance"),
            burnRate: burnRate
        )

        let rows = MenuSummary.rows(from: payload(deepseek: deepseek), order: [.deepseek])

        XCTAssertEqual(
            rows.first?.metric,
            .balance(
                amount: "¥108.00",
                trend: ProviderPresentation.balanceTrend(burnRate),
                daysLeft: 12,
                cached: false
            )
        )
    }

    func testStaleBalanceShowsTheCachedMessageInsteadOfTheTrend() {
        let deepseek = UsageProvider(
            ok: true,
            reason: "stale",
            kind: "balance",
            live: false,
            balance: BalanceInfo(amount: 8.5, currency: "CNY", available: true, label: "Balance"),
            burnRate: BurnRateInfo(
                amountPerDay: 1, windowDays: 7, estimatedDaysLeft: 8, confidence: "low", reason: nil
            )
        )

        let rows = MenuSummary.rows(from: payload(deepseek: deepseek), order: [.deepseek])

        XCTAssertEqual(
            rows.first?.metric,
            .balance(
                amount: "¥8.50",
                trend: ProviderPresentation.cachedBalanceMessage(),
                daysLeft: nil,
                cached: true
            )
        )
    }

    func testUnavailableRowsCarryTheLocalisedReason() {
        let rows = MenuSummary.rows(from: payload(), order: [.claude, .siliconflow])

        XCTAssertEqual(
            rows[0].metric,
            .unavailable(ProviderPresentation.message(for: .claude, provider: payload().claude))
        )
        XCTAssertEqual(
            rows[1].metric,
            .unavailable(ProviderPresentation.message(for: .siliconflow, provider: payload().siliconflow))
        )
        XCTAssertFalse(rows[0].isAvailable)
    }

    func testMissingPayloadShowsWaitingRows() {
        let rows = MenuSummary.rows(from: nil, order: [.claude, .deepseek])

        XCTAssertEqual(rows.map(\.metric), [
            .unavailable(MenuSummary.waitingText),
            .unavailable(MenuSummary.waitingText),
        ])
        XCTAssertEqual(MenuSummary.connectedCount(from: nil), 0)
    }

    func testConnectedCountCountsProvidersWithFigures() {
        let connected = payload(
            claude: quotaProvider(fiveH: 10, weekly: nil),
            deepseek: UsageProvider(
                ok: true,
                kind: "balance",
                balance: BalanceInfo(amount: 1, currency: "CNY", available: true, label: "Balance")
            )
        )

        XCTAssertEqual(MenuSummary.connectedCount(from: connected), 2)
        XCTAssertEqual(MenuSummary.connectedCount(from: payload()), 0)
    }

    func testRemainingIsClampedAndRounded() {
        XCTAssertEqual(MenuSummary.remaining(UsageWindow(percentage: 47.4)), 53)
        XCTAssertEqual(MenuSummary.remaining(UsageWindow(percentage: -20)), 100)
        XCTAssertEqual(MenuSummary.remaining(UsageWindow(percentage: 140)), 0)
    }

    func testTrendOmitsASubDayWindow() {
        let burnRate = BurnRateInfo(
            amountPerDay: 5, windowDays: 0, estimatedDaysLeft: 3, confidence: "low", reason: nil
        )

        let text = ProviderPresentation.balanceTrend(burnRate)

        XCTAssertFalse(text.contains("0 日"), text)
        XCTAssertTrue(text.contains("3"), text)
    }
}
