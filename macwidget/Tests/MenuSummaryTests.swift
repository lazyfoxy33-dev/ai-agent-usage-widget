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
                trend: ProviderPresentation.balanceTrendLine(burnRate, currency: "CNY"),
                daysLeft: 12,
                cached: false
            )
        )
    }

    func testInsufficientHistoryShowsACaveatInsteadOfADaysLeft() {
        // The estimator refuses below six hours of samples and says why.
        let deepseek = UsageProvider(
            ok: true,
            kind: "balance",
            live: true,
            balance: BalanceInfo(amount: 19.34, currency: "CNY", available: true, label: "Balance"),
            burnRate: BurnRateInfo(
                amountPerDay: nil, windowDays: nil, estimatedDaysLeft: nil,
                confidence: "none", reason: "insufficient_history"
            )
        )

        let rows = MenuSummary.rows(from: payload(deepseek: deepseek), order: [.deepseek])

        XCTAssertEqual(
            rows.first?.metric,
            .balance(
                amount: "¥19.34",
                trend: ProviderPresentation.insufficientHistoryText,
                daysLeft: nil,
                cached: false
            )
        )
    }

    func testShortRecentWindowStillShowsItsAverage() {
        // Seven hours of samples: low confidence, but a real recent average — the
        // whole point of averaging the trailing window instead of a week-old point.
        let burnRate = BurnRateInfo(
            amountPerDay: 24, windowDays: 0, estimatedDaysLeft: 4, confidence: "low", reason: nil
        )
        let deepseek = UsageProvider(
            ok: true,
            kind: "balance",
            live: true,
            balance: BalanceInfo(amount: 103, currency: "CNY", available: true, label: "Balance"),
            burnRate: burnRate
        )

        let rows = MenuSummary.rows(from: payload(deepseek: deepseek), order: [.deepseek])

        XCTAssertEqual(
            rows.first?.metric,
            .balance(
                amount: "¥103.00",
                trend: ProviderPresentation.balanceTrendLine(burnRate, currency: "CNY"),
                daysLeft: 4,
                cached: false
            )
        )
    }

    func testNoSpendEstimateShowsNoTrendLine() {
        let deepseek = UsageProvider(
            ok: true,
            kind: "balance",
            live: true,
            balance: BalanceInfo(amount: 19.34, currency: "CNY", available: true, label: "Balance"),
            burnRate: BurnRateInfo(
                amountPerDay: nil, windowDays: nil, estimatedDaysLeft: nil,
                confidence: "none", reason: "no_recent_spend"
            )
        )

        let rows = MenuSummary.rows(from: payload(deepseek: deepseek), order: [.deepseek])

        XCTAssertEqual(
            rows.first?.metric,
            .balance(amount: "¥19.34", trend: nil, daysLeft: nil, cached: false)
        )
    }

    func testTrendUsabilityFollowsTheEstimator() {
        func burnRate(days: Int?, confidence: String, reason: String? = nil) -> BurnRateInfo {
            BurnRateInfo(
                amountPerDay: 1, windowDays: 0, estimatedDaysLeft: days,
                confidence: confidence, reason: reason
            )
        }

        XCTAssertTrue(ProviderPresentation.isTrendUsable(burnRate(days: 4, confidence: "low")))
        XCTAssertTrue(ProviderPresentation.isTrendUsable(burnRate(days: 30, confidence: "medium")))
        XCTAssertFalse(ProviderPresentation.isTrendUsable(burnRate(days: nil, confidence: "none")))
        XCTAssertTrue(ProviderPresentation.isTrendUsable(burnRate(days: 0, confidence: "medium")),
                      "less than a day left is a real signal")
        XCTAssertFalse(ProviderPresentation.isTrendUsable(nil))
        XCTAssertTrue(
            ProviderPresentation.awaitsHistory(burnRate(days: nil, confidence: "none", reason: "insufficient_history"))
        )
        XCTAssertFalse(
            ProviderPresentation.awaitsHistory(burnRate(days: nil, confidence: "none", reason: "no_recent_spend"))
        )
        XCTAssertFalse(ProviderPresentation.awaitsHistory(burnRate(days: 4, confidence: "low")))
    }

    func testDailyRateIsTheSharedUnitAcrossWindows() {
        func burnRate(_ perDay: Double, _ window: Int) -> BurnRateInfo {
            BurnRateInfo(
                amountPerDay: perDay, windowDays: window, estimatedDaysLeft: 10,
                confidence: "low", reason: nil
            )
        }

        // 同一种格式，无论数据来自日、周还是月。
        let cny = ProviderPresentation.balanceDailyRate(burnRate(7.46, 1), currency: "CNY")
        let usd = ProviderPresentation.balanceDailyRate(burnRate(0.45, 30), currency: "USD")

        XCTAssertEqual(cny, ProviderPresentation.balanceDailyRate(burnRate(7.46, 1), currency: "CNY"))
        XCTAssertNotNil(cny)
        XCTAssertNotNil(usd)
        XCTAssertTrue(cny?.contains("7.46") == true, cny ?? "")
        XCTAssertTrue(usd?.contains("0.45") == true, usd ?? "")
        XCTAssertNil(
            ProviderPresentation.balanceDailyRate(
                BurnRateInfo(amountPerDay: nil, windowDays: nil, estimatedDaysLeft: nil,
                             confidence: "none", reason: "insufficient_history"),
                currency: "CNY"
            ),
            "样本不足时没有日均"
        )
    }

    func testTrendLineCombinesDailyRateAndDaysLeft() {
        let burnRate = BurnRateInfo(
            amountPerDay: 7.46, windowDays: 1, estimatedDaysLeft: 13, confidence: "medium", reason: nil
        )

        let line = ProviderPresentation.balanceTrendLine(burnRate, currency: "CNY")

        XCTAssertEqual(
            line,
            [
                ProviderPresentation.balanceDailyRate(burnRate, currency: "CNY")!,
                ProviderPresentation.balanceTrend(burnRate),
            ].joined(separator: " · ")
        )
    }

    func testTrendLineIsTheCaveatAloneWhenHistoryIsShort() {
        let burnRate = BurnRateInfo(
            amountPerDay: nil, windowDays: nil, estimatedDaysLeft: nil,
            confidence: "none", reason: "insufficient_history"
        )

        XCTAssertEqual(
            ProviderPresentation.balanceTrendLine(burnRate, currency: "CNY"),
            ProviderPresentation.insufficientHistoryText
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

    func testLessThanADayIsReportedNotHidden() {
        // Assert through the shared wording: the test host's language decides the
        // exact string (CI runs in English, this Mac in Chinese).
        let burnRate = BurnRateInfo(
            amountPerDay: 18.8, windowDays: 1, estimatedDaysLeft: 0, confidence: "low", reason: nil
        )

        let text = ProviderPresentation.balanceTrend(burnRate)

        XCTAssertEqual(text, ProviderPresentation.lessThanADayText)
        XCTAssertFalse(text.contains("0"), "an exhausted allowance is not quoted as zero days")
    }

    func testTrendShowsOnlyTheDaysNotTheWindow() {
        // 简单口径：日均 + 天数，窗口与置信度不进文案。
        let burnRate = BurnRateInfo(
            amountPerDay: 5, windowDays: 30, estimatedDaysLeft: 3, confidence: "low", reason: nil
        )

        let text = ProviderPresentation.balanceTrend(burnRate)

        XCTAssertTrue(text.contains("3"), text)
        XCTAssertFalse(text.contains("30"), "the window is not quoted: \(text)")
        XCTAssertFalse(text.contains("近"), "no window label: \(text)")
    }
}
