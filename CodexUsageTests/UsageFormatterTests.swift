import XCTest
@testable import CodexUsageShared

final class UsageFormatterTests: XCTestCase {
    func testResetTimeUsesProvidedTimeZoneAndLocale() {
        let formatter = UsageFormatter(
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(formatter.resetTime(epochSeconds: 1_779_949_290), "2026-05-28 06:21")
    }

    func testNilResetTimeUsesDash() {
        let formatter = UsageFormatter(locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt)

        XCTAssertEqual(formatter.resetTime(epochSeconds: nil), "--")
    }

    func testWidgetResetTimeUsesClockForShortWindowAndDateForLongWindow() {
        let formatter = UsageFormatter(
            locale: Locale(identifier: "zh_CN"),
            timeZone: TimeZone(secondsFromGMT: 8 * 60 * 60)!
        )

        XCTAssertEqual(formatter.widgetResetClock(epochSeconds: 1_779_967_655), "19:27")
        XCTAssertEqual(formatter.widgetResetDate(epochSeconds: 1_780_392_047), "6月2日")
        XCTAssertEqual(formatter.widgetResetClock(epochSeconds: nil), "--")
        XCTAssertEqual(formatter.widgetResetDate(epochSeconds: nil), "--")
    }

    func testResetRemainingTextUsesResetAfterSecondsBeforeAbsoluteResetTime() {
        let formatter = UsageFormatter(locale: Locale(identifier: "zh_CN"), timeZone: .gmt)
        let now = Date(timeIntervalSince1970: 1_000)
        let window = RateLimitWindow(
            usedPercent: 40,
            windowDurationMins: 300,
            resetsAt: 99_999,
            resetAfterSeconds: 9_290
        )

        XCTAssertEqual(formatter.resetRemainingText(window: window, now: now), "2 小时 34 分后")
        XCTAssertEqual(formatter.resetRemainingText(window: nil, now: now), "--")
    }

    func testCreditsStatusCoversUnlimitedBalanceAndNoCredits() {
        let formatter = UsageFormatter(locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt)

        XCTAssertEqual(formatter.creditsStatus(CreditsSnapshot(hasCredits: true, unlimited: true, balance: nil)), "无限 credits")
        XCTAssertEqual(formatter.creditsStatus(CreditsSnapshot(hasCredits: true, unlimited: false, balance: "12.5")), "credits 余额 12.5")
        XCTAssertEqual(formatter.creditsStatus(CreditsSnapshot(hasCredits: false, unlimited: false, balance: "0")), "无 credits")
        XCTAssertEqual(formatter.creditsStatus(nil), "无 credits 信息")
    }
}
