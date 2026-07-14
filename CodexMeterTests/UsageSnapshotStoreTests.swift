import XCTest
@testable import CodexMeterShared

final class UsageSnapshotStoreTests: XCTestCase {
    func testSnapshotRoundTripsThroughFallbackDirectory() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("CodexMeterTests-\(UUID().uuidString)", isDirectory: true)
        let store = UsageSnapshotStore(appGroupIdentifier: "", fallbackDirectory: directory)
        let snapshot = UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(usedPercent: 17, windowDurationMins: 300, resetsAt: 1_779_949_290),
                secondary: RateLimitWindow(usedPercent: 11, windowDurationMins: 10_080, resetsAt: 1_780_392_047),
                credits: CreditsSnapshot(hasCredits: false, unlimited: false, balance: "0"),
                planType: "prolite",
                rateLimitReachedType: nil
            ),
            account: CodexAccountSnapshot(email: "user@example.com", planType: "prolite")
        )

        try store.save(snapshot)

        XCTAssertEqual(try store.load(), snapshot)
    }

    func testDefaultCacheFileAvoidsLegacySnapshotName() {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("CodexMeterTests-\(UUID().uuidString)", isDirectory: true)
        let store = UsageSnapshotStore(appGroupIdentifier: "", fallbackDirectory: directory)

        XCTAssertEqual(store.snapshotURL().lastPathComponent, "latest-snapshot-v3.json")
    }

    /// 验证 App Group 在测试或异常签名环境不可用时，仍会落回显式缓存目录完成保存。
    func testUnavailableAppGroupFallsBackToProvidedDirectory() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("CodexMeterTests-\(UUID().uuidString)", isDirectory: true)
        let store = UsageSnapshotStore(
            appGroupIdentifier: "group.invalid.CodexMeterTests",
            fallbackDirectory: directory
        )
        let snapshot = UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(usedPercent: 17, windowDurationMins: 300, resetsAt: 1_779_949_290),
                secondary: RateLimitWindow(usedPercent: 11, windowDurationMins: 10_080, resetsAt: 1_780_392_047),
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            )
        )

        try store.save(snapshot)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.snapshotURL().path))
        XCTAssertEqual(try store.load(), snapshot)
    }

    func testDeleteSnapshotRemovesCachedSnapshotAndIgnoresMissingFile() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("CodexMeterTests-\(UUID().uuidString)", isDirectory: true)
        let store = UsageSnapshotStore(appGroupIdentifier: "", fallbackDirectory: directory)
        let snapshot = UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(usedPercent: 17, windowDurationMins: 300, resetsAt: 1_779_949_290),
                secondary: RateLimitWindow(usedPercent: 11, windowDurationMins: 10_080, resetsAt: 1_780_392_047),
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            )
        )
        try store.save(snapshot)

        try store.deleteSnapshot()
        try store.deleteSnapshot()

        XCTAssertNil(try store.load())
    }
}
