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
}
