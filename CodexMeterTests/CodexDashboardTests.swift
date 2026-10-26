// 验证页面价格、账单日期与活动图月份刻度，覆盖跨日和跨年边界。
import CodexMeterShared
import XCTest

/// 仅验证新增的展示分支，不复制日志汇总与计价器的既有测试。
final class CodexDashboardTests: XCTestCase {
    /// 跨年月份落在包含月初的周列，当前周未发生的月份不提前出现。
    @MainActor
    func testHeatmapMonthMarkersAlignAcrossYearAndExcludeFutureMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let january = calendar.date(from: DateComponents(year: 2026, month: 1, day: 6))!
        let markers = LocalMenuUsageHeatmap.monthMarkers(endingAt: january, weekCount: 26, calendar: calendar)
        XCTAssertEqual(markers.map(\.column), [0, 2, 7, 11, 15, 20, 24])
        XCTAssertEqual(markers.map { calendar.component(.month, from: $0.date) }, [7, 8, 9, 10, 11, 12, 1])
        let april = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29))!
        let annual = LocalMenuUsageHeatmap.monthMarkers(endingAt: january, weekCount: 52, calendar: calendar)
        XCTAssertEqual(annual.map { calendar.component(.month, from: $0.date) }, Array(1...12) + [1])
        XCTAssertEqual(annual.first?.column, 0)
        XCTAssertEqual(annual.last?.column, 50)
        let beforeMay = LocalMenuUsageHeatmap.monthMarkers(endingAt: april, weekCount: 52, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: beforeMay.last!.date), 4)
        XCTAssertTrue(beforeMay.allSatisfy { $0.column < 52 && $0.date <= april })
    }

    /// 长上下文必须选取完整阶梯行，并保留低价模型的小数精度。
    func testPriceRowsUseCatalogTiersAndPreserveUnknownRates() {
        let catalog = LocalCodexPricingCatalog()
        let standard = CodexModelPriceRow(model: "gpt-6.1-sol", catalog: catalog, longContext: false, day: "2026-10-23")
        XCTAssertEqual(standard.input, 2)
        XCTAssertEqual(standard.cached, 0.1)
        XCTAssertEqual(standard.output, 10)
        let long = CodexModelPriceRow(model: "gpt-6.1-sol", catalog: catalog, longContext: true, day: "2026-10-23")
        XCTAssertEqual(long.input, 4)
        XCTAssertEqual(long.cached, 0.2)
        XCTAssertEqual(long.output, 15)
        XCTAssertEqual(long.threshold, 272_000)
        let luna = CodexModelPriceRow(model: "gpt-6-luna", catalog: catalog, longContext: false, day: "2026-10-23")
        XCTAssertEqual(luna.cached, 0.01)
        let unknown = CodexModelPriceRow(model: "unknown-model", catalog: catalog, longContext: false, day: "2026-10-23")
        XCTAssertNil(unknown.input)
        XCTAssertNil(unknown.cached)
        XCTAssertNil(unknown.output)
        let noTier = CodexModelPriceRow(model: "gpt-5.3-codex", catalog: catalog, longContext: true, day: "2026-10-23")
        XCTAssertNil(noTier.input)
        XCTAssertNil(noTier.output)
    }

    /// 页面必须与账本使用同一天的目录修订，不能直接取未来价格或强制内置价。
    func testPriceRowsRespectEffectiveDates() {
        let futurePrice = LocalCodexPricing.Price(
            inputPerMillion: 3, cachedInputPerMillion: nil, outputPerMillion: 12,
            thresholdTokens: nil, inputAboveThreshold: nil,
            cachedInputAboveThreshold: nil, outputAboveThreshold: nil, source: "models.dev"
        )
        let catalog = LocalCodexPricingCatalog(revisions: [
            "gpt-6.1-sol": [.init(effectiveFrom: "2026-10-24", price: futurePrice)]
        ])
        let before = CodexModelPriceRow(model: "gpt-6.1-sol", catalog: catalog, longContext: false, day: "2026-10-23")
        XCTAssertEqual(before.input, 2)
        let after = CodexModelPriceRow(model: "gpt-6.1-sol", catalog: catalog, longContext: false, day: "2026-10-24")
        XCTAssertEqual(after.input, 3)
        XCTAssertNil(after.cached)
        XCTAssertEqual(after.source, "models.dev")
    }

    /// 亚洲时区的午夜边界按本地日期查找；没有今天的记录时保持未知而非显示昨天或零。
    @MainActor
    func testTodayCostUsesLocalCalendarAndDoesNotReusePreviousDay() {
        let now = Date(timeIntervalSince1970: 1_792_684_800) // 2026-10-22 16:00 UTC，即台北 10 月 23 日。
        let summary = LocalCodexUsageSummary(
            fetchedAt: now, todayTokens: 1, sevenDayTokens: 1, lifetimeTokens: 1,
            threadCount: 1, projects: [], taskCounts: .init(active: 0, pending: 0, scheduled: 0, done: 0),
            dailyBuckets: [
                .init(id: "2026-10-23", label: "10/23", tokens: 1, estimatedCostUSD: 3),
                .init(id: "2026-10-22", label: "10/22", tokens: 1, estimatedCostUSD: 5)
            ]
        )
        XCTAssertEqual(CodexDashboardSections.todayCost(summary, now: now, timeZone: TimeZone(secondsFromGMT: 28_800)!), 3)
        XCTAssertEqual(CodexDashboardSections.todayCost(summary, now: now, timeZone: TimeZone(secondsFromGMT: 0)!), 5)
        XCTAssertNil(CodexDashboardSections.todayCost(summary, now: now.addingTimeInterval(86_400), timeZone: TimeZone(secondsFromGMT: 28_800)!))
        XCTAssertNil(CodexDashboardSections.todayCost(nil, now: now))
    }
}
