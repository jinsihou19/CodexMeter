import XCTest
@testable import CodexUsageShared

// 本文件验证降智雷达共享设置、刷新节奏和缓存往返。

/// 降智雷达共享模型测试，覆盖开关默认值、缓存落盘和工作时间刷新节奏。
final class CodexRadarTests: XCTestCase {
    /// 验证分数卡列数会把全部项目均分到最多两行，五项时形成三列两行。
    func testCodexRadarScoreGridUsesAtMostTwoRows() {
        XCTAssertEqual(CodexRadarScoreGridLayout.columnCount(for: 0), 1)
        XCTAssertEqual(CodexRadarScoreGridLayout.columnCount(for: 1), 1)
        XCTAssertEqual(CodexRadarScoreGridLayout.columnCount(for: 4), 2)
        XCTAssertEqual(CodexRadarScoreGridLayout.columnCount(for: 5), 3)
        XCTAssertEqual(CodexRadarScoreGridLayout.columnCount(for: 8), 4)
    }

    /// 验证图例最多使用三列，六项时形成清晰的三列两行布局。
    func testCodexRadarLegendUsesAtMostThreeColumns() {
        XCTAssertEqual(CodexRadarLineChartLayout.legendColumnCount(for: 0), 1)
        XCTAssertEqual(CodexRadarLineChartLayout.legendColumnCount(for: 1), 1)
        XCTAssertEqual(CodexRadarLineChartLayout.legendColumnCount(for: 3), 3)
        XCTAssertEqual(CodexRadarLineChartLayout.legendColumnCount(for: 6), 3)
    }

    /// 验证顶部卡片和下方图表共用排序后最多六项的展示序列。
    func testCodexRadarSectionUsesOneLimitedDisplaySeries() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent("CodexUsage/CodexRadarView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("let displaySeries = modelIQ.displaySeries(limit: 6)"))
        XCTAssertTrue(source.contains("CodexRadarScoreGrid(runs: displaySeries.compactMap(\\.latest))"))
        XCTAssertTrue(source.contains("CodexRadarLineChart(series: displaySeries)"))
        XCTAssertTrue(source.contains(".instantHelp(cardHelpText(for: run))"))
        XCTAssertTrue(source.contains(".instantHelp(seriesHelpText(for: item))"))
        XCTAssertFalse(source.contains(".help(cardHelpText(for: run))"))
    }

    /// 验证最多六条雷达曲线拥有六种互不重复的图例颜色。
    func testCodexRadarPaletteProvidesSixDistinctSeriesColors() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent("CodexUsage/CodexRadarView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let expectedColors = ["#2F6ED3", "#0E9F6E", "#D98200", "#D9293A", "#8B5CF6", "#0891B2"]

        XCTAssertEqual(Set(expectedColors).count, 6)
        for color in expectedColors {
            XCTAssertTrue(source.contains("\"\(color)\""))
        }
        XCTAssertTrue(source.contains("seriesHexColors[index % seriesHexColors.count]"))
    }

    /// 验证单点序列只画圆点，多点序列画线并同时标记首尾端点。
    func testCodexRadarLineChartCreatesSinglePointAndLineDrawingPlans() {
        XCTAssertEqual(
            CodexRadarLineChartLayout.drawingPlan(for: 0),
            .init(drawsLine: false, markerIndexes: [])
        )
        XCTAssertEqual(
            CodexRadarLineChartLayout.drawingPlan(for: 1),
            .init(drawsLine: false, markerIndexes: [0])
        )
        XCTAssertEqual(
            CodexRadarLineChartLayout.drawingPlan(for: 5),
            .init(drawsLine: true, markerIndexes: [0, 4])
        )
    }

    /// 验证模型族和推理档位按预设能力排序，并在排序后只保留前六项。
    func testCodexRadarDisplaySeriesSortsByModelAndEffortThenLimitsToSix() {
        let modelIQ = CodexRadarModelIQ(
            primary: makeRadarSeries(id: "luna-medium", model: "gpt-5.6-luna", effort: "medium"),
            comparisons: [
                makeRadarSeries(id: "terra-medium", model: "gpt-5.6-terra", effort: "medium"),
                makeRadarSeries(id: "sol-low", model: "gpt-5.6-sol", effort: "low"),
                makeRadarSeries(id: "sol-high", model: "gpt-5.6-sol", effort: "high"),
                makeRadarSeries(id: "sol-ultra", model: "gpt-5.6-sol", effort: "ultra"),
                makeRadarSeries(id: "sol-medium", model: "gpt-5.6-sol", effort: "medium"),
                makeRadarSeries(id: "sol-xhigh", model: "gpt-5.6-sol", effort: "xhigh")
            ]
        )

        XCTAssertEqual(
            modelIQ.displaySeries(limit: 6).map(\.id),
            ["sol-ultra", "sol-xhigh", "sol-high", "sol-medium", "sol-low", "terra-medium"]
        )
    }

    /// 验证紧凑标签使用后缀首字母，悬停全称保留完整模型和推理档位。
    func testCodexRadarScoreCardTextFormatsShortAndFullLabels() {
        XCTAssertEqual(
            CodexRadarScoreCardText.shortLabel(model: "gpt-5.6-sol", effort: "ultra"),
            "5.6-Sol-u"
        )
        XCTAssertEqual(
            CodexRadarScoreCardText.fullLabel(model: "gpt-5.6-sol", effort: "ultra"),
            "GPT-5.6-Sol ultra"
        )
    }

    /// 验证降智雷达模块关闭时，后台 Store 启动也不会访问外部雷达接口。
    @MainActor
    func testCodexRadarStoreDoesNotFetchWhenModuleHidden() async throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("CodexRadarTests-\(UUID().uuidString)", isDirectory: true)
        let client = CountingCodexRadarClient()
        let store = CodexRadarStore(
            client: client,
            store: CodexRadarSnapshotStore(appGroupIdentifier: "", fallbackDirectory: directory),
            settingsProvider: { CodexRadarSettings(isEnabled: false) },
            nowProvider: { Date(timeIntervalSince1970: 1_779_940_000) }
        )

        store.start()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(client.fetchCount, 0)
    }

    /// 验证 current.json 的模型 IQ 更新时间来自 model_iq.quota_radar.updated_at，而不是顶层 monitored_at。
    func testDirectCodexRadarClientReadsModelIQQuotaRadarUpdatedAt() async throws {
        let body = """
        {
          "monitored_at": "2026-06-24T04:52:00.084111+08:00",
          "timezone": "Asia/Shanghai",
          "model_iq": {
            "quota_radar": {
              "updated_at": "2026-06-24T04:55:00.084111+08:00"
            },
            "latest": {
              "date": "2026-06-24",
              "score": 125,
              "status": "green",
              "passed": 10,
              "tasks": 12,
              "model": "gpt-5.5",
              "reasoning_effort": "xhigh"
            },
            "recent_days": [{
              "date": "2026-06-24",
              "score": 125,
              "status": "green",
              "passed": 10,
              "tasks": 12,
              "model": "gpt-5.5",
              "reasoning_effort": "xhigh"
            }],
            "comparisons": {}
          }
        }
        """
        let client = DirectCodexRadarClient(
            endpointURL: URL(string: "https://example.test/current.json")!
        ) { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (Data(body.utf8), response)
        }

        let snapshot = try await client.fetchRadarSnapshot()

        XCTAssertEqual(snapshot.monitoredAt, "2026-06-24T04:52:00.084111+08:00")
        XCTAssertEqual(snapshot.modelIQ?.quotaRadarUpdatedAt, "2026-06-24T04:55:00.084111+08:00")
    }

    /// 验证雷达设置默认关闭，并能从共享 defaults 读取显式开启状态。
    func testCodexRadarSettingsDefaultToDisabledAndReadStoredValue() {
        let suiteName = "CodexUsageTests.codexRadarSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertFalse(CodexRadarSettings(defaults: defaults).isEnabled)

        defaults.set(true, forKey: CodexRadarPreferenceKeys.isEnabled)

        XCTAssertTrue(CodexRadarSettings(defaults: defaults).isEnabled)
    }

    /// 验证工作日白天使用一小时节奏，夜间和周末回落到四小时节奏。
    func testCodexRadarRefreshPolicyUsesWorkingAndOffHourIntervals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let workingDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 23,
            hour: 10
        )))
        let eveningDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 23,
            hour: 20
        )))
        let weekendDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 6,
            day: 27,
            hour: 10
        )))

        XCTAssertTrue(CodexRadarRefreshPolicy.isWorkingTime(date: workingDate, calendar: calendar))
        XCTAssertEqual(
            CodexRadarRefreshPolicy.intervalSeconds(for: workingDate, calendar: calendar),
            60 * 60
        )
        XCTAssertFalse(CodexRadarRefreshPolicy.isWorkingTime(date: eveningDate, calendar: calendar))
        XCTAssertFalse(CodexRadarRefreshPolicy.isWorkingTime(date: weekendDate, calendar: calendar))
        XCTAssertEqual(
            CodexRadarRefreshPolicy.intervalSeconds(for: weekendDate, calendar: calendar),
            4 * 60 * 60
        )
    }

    /// 验证雷达快照能在独立缓存文件中往返，避免和用量快照互相覆盖。
    func testCodexRadarSnapshotStoreRoundTripsSnapshot() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("CodexRadarTests-\(UUID().uuidString)", isDirectory: true)
        let store = CodexRadarSnapshotStore(appGroupIdentifier: "", fallbackDirectory: directory)
        let snapshot = CodexRadarSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            monitoredAt: "2026-06-23T08:51:28.710622+08:00",
            timezone: "Asia/Shanghai",
            prediction: CodexRadarPrediction(
                level: "medium_low",
                probability24h: 0.13,
                probability48h: 0.30,
                expectedWindow: "未来 24-48 小时",
                summary: "低概率",
                updatedAt: "2026-06-23T08:51:28+08:00"
            ),
            modelIQ: CodexRadarModelIQ(
                primary: CodexRadarModelSeries(
                    id: "primary",
                    label: "GPT-5.5 xhigh",
                    model: "gpt-5.5",
                    reasoningEffort: "xhigh",
                    latest: CodexRadarIQRun(
                        date: "2026-06-23",
                        score: 125,
                        status: "green",
                        passed: 10,
                        tasks: 12,
                        invalid: 0,
                        totalTokens: 41_602_755,
                        wallTimeHuman: "46分钟",
                        model: "gpt-5.5",
                        reasoningEffort: "xhigh",
                        costUSD: 40.21
                    ),
                    recentDays: []
                ),
                comparisons: [],
                quotaRadarUpdatedAt: "2026-06-23T14:55:28+08:00"
            )
        )

        try store.save(snapshot)

        XCTAssertEqual(try store.load(), snapshot)
        XCTAssertEqual(store.snapshotURL().lastPathComponent, "latest-codex-radar-v1.json")
    }

    /// 验证雷达缓存遇到不可用 App Group 时仍能回退写入，避免首次拉取成功却无法落盘。
    func testCodexRadarSnapshotStoreFallsBackWhenAppGroupUnavailable() throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("CodexRadarTests-\(UUID().uuidString)", isDirectory: true)
        let store = CodexRadarSnapshotStore(
            appGroupIdentifier: "group.invalid.CodexRadarTests",
            fallbackDirectory: directory
        )
        let snapshot = CodexRadarSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            monitoredAt: "2026-06-24T09:00:00+08:00",
            timezone: "Asia/Shanghai",
            prediction: nil,
            modelIQ: nil
        )

        try store.save(snapshot)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.snapshotURL().path))
        XCTAssertEqual(try store.load(), snapshot)
    }
}

/// 构造用于排序测试的最小模型序列，避免无关运行指标掩盖排序意图。
private func makeRadarSeries(id: String, model: String, effort: String) -> CodexRadarModelSeries {
    let run = CodexRadarIQRun(
        date: id,
        score: 100,
        status: "green",
        passed: 1,
        tasks: 1,
        invalid: nil,
        totalTokens: nil,
        wallTimeHuman: nil,
        model: model,
        reasoningEffort: effort,
        costUSD: nil
    )
    return CodexRadarModelSeries(
        id: id,
        label: id,
        model: model,
        reasoningEffort: effort,
        latest: run,
        recentDays: [run]
    )
}

private final class CountingCodexRadarClient: CodexRadarFetching, @unchecked Sendable {
    private let queue = DispatchQueue(label: "CodexUsageTests.CountingCodexRadarClient")
    private var storedFetchCount = 0

    var fetchCount: Int {
        queue.sync { storedFetchCount }
    }

    /// 记录雷达请求次数并返回最小可用快照；测试只关心是否触发网络抽象。
    func fetchRadarSnapshot() async throws -> CodexRadarSnapshot {
        queue.sync {
            storedFetchCount += 1
        }
        return CodexRadarSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            monitoredAt: nil,
            timezone: nil,
            prediction: nil,
            modelIQ: nil
        )
    }
}
