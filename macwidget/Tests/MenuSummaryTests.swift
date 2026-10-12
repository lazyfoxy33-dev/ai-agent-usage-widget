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

    func testLinesFollowTheConfiguredOrder() {
        let lines = MenuSummary.lines(
            from: payload(),
            order: [.openrouter, .kimi, .deepseek]
        )

        XCTAssertEqual(lines.map(\.id), ["openrouter", "kimi", "deepseek"])
        XCTAssertEqual(lines.first?.title, "OpenRouter · \(ProviderPresentation.message(for: .openrouter, provider: payload().openrouter))")
    }

    func testQuotaLineShowsRemainingShare() {
        let claude = UsageProvider(
            ok: true,
            kind: "quota",
            fiveH: UsageWindow(percentage: 47),
            weekly: UsageWindow(percentage: 91)
        )

        let lines = MenuSummary.lines(from: payload(claude: claude), order: [.claude])

        XCTAssertEqual(lines.first?.title, "Claude · 5H 剩 53% · 周 剩 9%")
    }

    func testSingleWindowQuotaLine() {
        let claude = UsageProvider(ok: true, kind: "quota", fiveH: UsageWindow(percentage: 100))

        XCTAssertEqual(
            MenuSummary.lines(from: payload(claude: claude), order: [.claude]).first?.title,
            "Claude · 5H 剩 0%"
        )
    }

    func testStaleQuotaLineIsMarkedCached() {
        let claude = UsageProvider(
            ok: true,
            reason: "stale",
            kind: "quota",
            live: false,
            fiveH: UsageWindow(percentage: 20)
        )

        let title = MenuSummary.lines(from: payload(claude: claude), order: [.claude]).first?.title

        XCTAssertEqual(title, "Claude · 5H 剩 80% · \(ProviderPresentation.cachedMessage())")
    }

    func testBalanceLineShowsAmountAndTrend() {
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

        let title = MenuSummary.lines(from: payload(deepseek: deepseek), order: [.deepseek]).first?.title

        XCTAssertEqual(title, "DeepSeek · ¥108.00 · \(ProviderPresentation.balanceTrend(burnRate))")
        XCTAssertTrue(title?.contains("¥108.00") == true)
    }

    func testStaleBalanceShowsCachedMarkerInsteadOfTrend() {
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

        let title = MenuSummary.lines(from: payload(deepseek: deepseek), order: [.deepseek]).first?.title

        XCTAssertEqual(title, "DeepSeek · ¥8.50 · \(ProviderPresentation.cachedBalanceMessage())")
    }

    func testMissingPayloadShowsWaitingText() {
        let lines = MenuSummary.lines(from: nil, order: [.claude, .deepseek])

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].title, "Claude · \(MenuSummary.waitingText)")
        XCTAssertEqual(lines[1].title, "DeepSeek · \(MenuSummary.waitingText)")
    }

    func testTrendOmitsASubDayWindow() {
        let burnRate = BurnRateInfo(
            amountPerDay: 5, windowDays: 0, estimatedDaysLeft: 3, confidence: "low", reason: nil
        )

        let text = ProviderPresentation.balanceTrend(burnRate)

        XCTAssertFalse(text.contains("0 日"), text)
        XCTAssertTrue(text.contains("3"), text)
    }

    func testRemainingIsClampedAndRounded() {
        XCTAssertEqual(MenuSummary.remaining(UsageWindow(percentage: 47.4)), 53)
        XCTAssertEqual(MenuSummary.remaining(UsageWindow(percentage: -20)), 100)
        XCTAssertEqual(MenuSummary.remaining(UsageWindow(percentage: 140)), 0)
    }
}
