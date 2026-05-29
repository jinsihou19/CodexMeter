import XCTest
@testable import CodexUsageShared

final class UsageModelsTests: XCTestCase {
    func testRemainingPercentClampsUsedPercentIntoDisplayRange() {
        XCTAssertEqual(RateLimitWindow(usedPercent: 17, windowDurationMins: 300, resetsAt: 1_779_949_290).remainingPercent, 83)
        XCTAssertEqual(RateLimitWindow(usedPercent: -20, windowDurationMins: nil, resetsAt: nil).remainingPercent, 100)
        XCTAssertEqual(RateLimitWindow(usedPercent: 140, windowDurationMins: nil, resetsAt: nil).remainingPercent, 0)
    }
}
