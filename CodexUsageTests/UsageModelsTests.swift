import XCTest
@testable import CodexUsageShared

final class UsageModelsTests: XCTestCase {
    func testRemainingPercentClampsUsedPercentIntoDisplayRange() {
        XCTAssertEqual(RateLimitWindow(usedPercent: 17, windowDurationMins: 300, resetsAt: 1_779_949_290).remainingPercent, 83)
        XCTAssertEqual(RateLimitWindow(usedPercent: -20, windowDurationMins: nil, resetsAt: nil).remainingPercent, 100)
        XCTAssertEqual(RateLimitWindow(usedPercent: 140, windowDurationMins: nil, resetsAt: nil).remainingPercent, 0)
    }

    func testUsagePaceComparesUsedPercentAgainstElapsedWindowProgress() {
        let now = Date(timeIntervalSince1970: 1_000)
        let window = RateLimitWindow(
            usedPercent: 70,
            windowDurationMins: 100,
            resetsAt: 4_000
        )

        let pace = window.usagePace(now: now)

        XCTAssertEqual(pace?.roundedExpectedUsedPercent, 50)
        XCTAssertEqual(pace?.roundedActualUsedPercent, 70)
        XCTAssertEqual(pace?.roundedDeltaPercent, 20)
        XCTAssertEqual(window.paceDeltaPercent(now: now), 20)
        XCTAssertFalse(pace?.willLastToReset ?? true)
        XCTAssertEqual(pace?.etaSeconds ?? 0, 1286, accuracy: 1)
    }

    func testUsagePaceNegativeDeltaMeansUsageIsInReserve() {
        let now = Date(timeIntervalSince1970: 1_000)
        let window = RateLimitWindow(
            usedPercent: 40,
            windowDurationMins: 100,
            resetsAt: 4_000
        )

        let pace = window.usagePace(now: now)

        XCTAssertEqual(pace?.roundedExpectedUsedPercent, 50)
        XCTAssertEqual(pace?.roundedActualUsedPercent, 40)
        XCTAssertEqual(pace?.roundedDeltaPercent, -10)
        XCTAssertTrue(pace?.willLastToReset ?? false)
        XCTAssertNil(pace?.etaSeconds)
    }

    func testWeeklyUsagePaceCanUseConfiguredWorkDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 3,
            hour: 0
        )))
        let resetsAt = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 8,
            hour: 0
        )))
        let window = RateLimitWindow(
            usedPercent: 50,
            windowDurationMins: 10_080,
            resetsAt: Int(resetsAt.timeIntervalSince1970)
        )

        let pace = window.usagePace(now: now, weeklyProgressWorkDays: 5, calendar: calendar)

        XCTAssertEqual(pace?.roundedExpectedUsedPercent, 40)
        XCTAssertEqual(pace?.roundedDeltaPercent, 10)
        XCTAssertEqual(pace?.etaSeconds ?? 0, 2 * 24 * 60 * 60, accuracy: 1)
    }

    func testWeeklyWorkdayMarkerPercentsUseWorkdayBoundaries() {
        XCTAssertEqual(
            weeklyWorkdayMarkerPercents(workDays: 5, windowDurationMins: 10_080),
            [20, 40, 60, 80]
        )
        XCTAssertEqual(weeklyWorkdayMarkerPercents(workDays: 7, windowDurationMins: 10_080), [
            100.0 / 7.0,
            200.0 / 7.0,
            300.0 / 7.0,
            400.0 / 7.0,
            500.0 / 7.0,
            600.0 / 7.0
        ])
        XCTAssertEqual(weeklyWorkdayMarkerPercents(workDays: 5, windowDurationMins: 300), [])
    }

    func testUsagePaceDisplayabilityRequiresEnoughElapsedWindowProgress() throws {
        let justResetWindow = RateLimitWindow(
            usedPercent: 12,
            windowDurationMins: 10_080,
            resetsAt: nil,
            resetAfterSeconds: 597_600
        )
        let establishedWindow = RateLimitWindow(
            usedPercent: 12,
            windowDurationMins: 10_080,
            resetsAt: nil,
            resetAfterSeconds: 580_000
        )

        let justResetPace = try XCTUnwrap(justResetWindow.usagePace())
        let establishedPace = try XCTUnwrap(establishedWindow.usagePace())

        XCTAssertLessThan(justResetPace.expectedUsedPercent, UsagePace.minimumDisplayExpectedUsedPercent)
        XCTAssertFalse(justResetPace.isDisplayable())
        XCTAssertTrue(establishedPace.isDisplayable())
    }

    func testUsageSnapshotAccountSummaryFallsBackToRateLimitPlan() {
        let snapshot = UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: nil,
                secondary: nil,
                credits: nil,
                planType: "prolite",
                rateLimitReachedType: nil
            ),
            account: CodexAccountSnapshot(email: "USER@example.COM ", planType: nil)
        )

        XCTAssertEqual(snapshot.accountEmail, "user@example.com")
        XCTAssertEqual(snapshot.accountPlanType, "prolite")
        XCTAssertEqual(snapshot.accountPlanDisplayText, "Pro 5x")
    }

    func testCodexPlanFormatterCleansKnownAndUnknownPlanNames() {
        XCTAssertEqual(CodexPlanFormatter.displayName(for: "prolite"), "Pro 5x")
        XCTAssertEqual(CodexPlanFormatter.displayName(for: "pro"), "Pro 20x")
        XCTAssertEqual(CodexPlanFormatter.displayName(for: "enterprise_workspace"), "Enterprise Workspace")
        XCTAssertNil(CodexPlanFormatter.displayName(for: "  "))
    }
}
