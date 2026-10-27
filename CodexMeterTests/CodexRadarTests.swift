import XCTest
@testable import CodexMeterShared

// 本文件验证降智雷达共享设置、刷新节奏和缓存往返。

/// 降智雷达共享模型测试，覆盖开关默认值、缓存落盘和工作时间刷新节奏。
final class CodexRadarTests: XCTestCase {
    /// 验证 GPT 与其他模型拆卡展示，其他模型可多选，折线图默认聚焦 Astra。
    func testCodexRadarSectionFiltersChartBySelectedFamilies() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent("CodexMeter/CodexRadarView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("CodexRadarModelSelection.latestGPTSeriesByFamily("))
        XCTAssertTrue(source.contains("case .radarInsights:\n            return nil"))
        XCTAssertTrue(source.contains("https://www.aiiq.org/charts/iq-bell-curve/"))
        XCTAssertTrue(source.contains("if let radarPageURL"))
        XCTAssertTrue(source.contains("from: displaySeries.filter { $0.model?.hasPrefix(\"gpt-\") == true }"))
        XCTAssertTrue(source.contains("let otherSeries = displaySeries.filter { $0.model?.hasPrefix(\"gpt-\") != true }"))
        XCTAssertTrue(source.contains("@State private var selectedModelFamilies: Set<String> = [\"Astra\"]"))
        XCTAssertTrue(source.contains("@State private var selectedOtherModelIDs: Set<String> = []"))
        XCTAssertTrue(source.contains("CodexRadarScoreGrid("))
        XCTAssertTrue(source.contains("runs: gptSeries.compactMap(\\.latest)"))
        XCTAssertTrue(source.contains("runs: selectedOtherSeries.compactMap(\\.latest)"))
        XCTAssertTrue(source.contains("grouping: .model"))
        XCTAssertTrue(source.contains("otherModelsHeader(availableModelIDs: otherModelIDs)"))
        XCTAssertTrue(source.contains("GridItem(.adaptive(minimum: 118)"))
        XCTAssertTrue(source.contains(".menuIndicator(.hidden)"))
        XCTAssertTrue(source.contains("codexRadar.selectedOtherModels.\\(settings.source.rawValue)"))
        XCTAssertTrue(source.contains("CodexRadarModelSelection.topModelIDs(from: otherSeries)"))
        XCTAssertTrue(source.contains("selectedModelFamilies.contains(CodexRadarScoreCardText.familyLabel(model: $0.model))"))
        XCTAssertTrue(source.contains("CodexRadarLineChart(series: chartSeries)"))
        XCTAssertTrue(source.contains("settings.source.supportsScoreHistory"))
        XCTAssertTrue(source.contains("chartSeries.contains(where: { !$0.recentDays.isEmpty })"))
        XCTAssertTrue(source.contains("onToggleGroup(group.id)"))
        XCTAssertTrue(source.contains(".instantHelp(cardHelpText(for: run))"))
        XCTAssertTrue(source.contains("hoverTooltip(date: hoveredPoint.date, score: hoveredPoint.score)"))
        XCTAssertTrue(source.contains("abs($0.score - score) < 0.001"))
        XCTAssertFalse(source.contains("private var legend"))
        XCTAssertFalse(source.contains(".help(cardHelpText(for: run))"))
        XCTAssertTrue(source.contains("guard scoreAxisBounds.contains(run.score)"))
        XCTAssertTrue(source.contains("CodexRadarScoreAxis.gridScores(in: scoreAxisBounds)"))
        XCTAssertTrue(source.contains("let clamped = min(max(score, scoreAxisBounds.lowerBound), scoreAxisBounds.upperBound)"))
        XCTAssertTrue(source.contains("value.split(separator: \"T\", maxSplits: 1).first"))
    }

    /// 验证折线图设置只在雷达开启后出现，且任何开关变化都会通知后台刷新。
    func testCodexRadarChartSettingIsConditionalAndRefreshesWhenEnabled() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("CodexMeter/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("if codexRadarEnabled {"))
        XCTAssertTrue(source.contains("title: \"数据源\""))
        XCTAssertTrue(source.contains("CodexRadarSource.allCases.map"))
        XCTAssertTrue(source.contains("currentCodexRadarSettings.source.supportsOtherModels"))
        XCTAssertTrue(source.contains("title: \"显示其他模型智商\""))
        XCTAssertTrue(source.contains("currentCodexRadarSettings.source.supportsScoreHistory"))
        XCTAssertTrue(source.contains("isOn: codexRadarScoreChartBinding"))
        XCTAssertTrue(source.contains(") { _ in\n            CodexRadarSettings.notifyDidChange()"))
    }

    /// 验证雷达曲线使用二十种适合深色背景的高区分度颜色。
    func testCodexRadarPaletteUsesTwentyDistinctColors() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let radarSource = try String(
            contentsOf: projectRoot.appendingPathComponent("CodexMeter/CodexRadarView.swift"),
            encoding: .utf8
        )
        let paletteSource = try String(
            contentsOf: projectRoot.appendingPathComponent("CodexMeterShared/MenuBarDisplaySettings.swift"),
            encoding: .utf8
        )
        let expectedColors = [
            "#3B82F6", "#F59E0B", "#14B8A6", "#F43F5E", "#8B5CF6",
            "#84CC16", "#06B6D4", "#F97316", "#D946EF", "#10B981",
            "#6366F1", "#EAB308", "#0EA5E9", "#EF4444", "#A855F7",
            "#22C55E", "#EC4899", "#38BDF8", "#FB923C", "#2DD4BF"
        ]

        XCTAssertEqual(Set(expectedColors).count, 20)
        for color in expectedColors {
            XCTAssertTrue(paletteSource.contains("\"\(color)\""))
        }
        XCTAssertTrue(radarSource.contains("CodexMeterChartPalette.seriesColor(index: index)"))
        XCTAssertTrue(paletteSource.contains("seriesHexColors[index % seriesHexColors.count]"))
    }

    /// 验证单点序列只画圆点，多点序列画线并标记全部时间点。
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
            .init(drawsLine: true, markerIndexes: [0, 1, 2, 3, 4])
        )
    }

    /// 验证纵轴覆盖实际最高和最低分，数据跨度超过 60 分时优先保留最高分段。
    func testCodexRadarScoreAxisUsesCompactDynamicBounds() {
        XCTAssertEqual(CodexRadarScoreAxis.upperBound(for: [92, 107.6]), 110)
        XCTAssertEqual(CodexRadarScoreAxis.bounds(for: [92, 107.6]), 90...110)
        XCTAssertEqual(CodexRadarScoreAxis.bounds(for: [70, 107.6]), 70...110)
        XCTAssertEqual(CodexRadarScoreAxis.upperBound(for: [110.1]), 120)
        XCTAssertEqual(CodexRadarScoreAxis.bounds(for: [110.1]), 110...120)
        XCTAssertEqual(CodexRadarScoreAxis.upperBound(for: [149.9]), 150)
        XCTAssertEqual(CodexRadarScoreAxis.bounds(for: [149.9]), 140...150)
        XCTAssertEqual(CodexRadarScoreAxis.bounds(for: [70, 140]), 80...140)
        XCTAssertEqual(CodexRadarScoreAxis.bounds(for: [70, 149.9]), 90...150)
        XCTAssertEqual(CodexRadarScoreAxis.upperBound(for: [151]), 150)
        XCTAssertEqual(CodexRadarScoreAxis.gridScores(in: 70...110), [70, 80, 90, 100, 110])
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
                makeRadarSeries(id: "sol-max", model: "gpt-5.6-sol", effort: "max"),
                makeRadarSeries(id: "sol-medium", model: "gpt-5.6-sol", effort: "medium"),
                makeRadarSeries(id: "sol-xhigh", model: "gpt-5.6-sol", effort: "xhigh")
            ]
        )

        XCTAssertEqual(
            modelIQ.displaySeries(limit: 7).map(\.id),
            ["sol-ultra", "sol-max", "sol-xhigh", "sol-high", "sol-medium", "sol-low", "terra-medium"]
        )
    }

    /// 验证模型矩阵保留 ultra 和 max 两个独立档位。
    func testCodexRadarScoreCardTextFormatsShortAndFullLabels() {
        XCTAssertEqual(
            CodexRadarScoreCardText.shortLabel(model: "gpt-5.6-sol", effort: "medium"),
            "Sol med"
        )
        XCTAssertEqual(CodexRadarScoreCardText.familyLabel(model: "gpt-5.6-terra"), "Terra")
        XCTAssertEqual(CodexRadarScoreCardText.familyLabel(model: "claude-opus-5"), "Claude")
        XCTAssertEqual(CodexRadarScoreCardText.familyLabel(model: "dsh-deepseek-v4-flash"), "Deepseek")
        XCTAssertEqual(CodexRadarScoreCardText.modelLabel(model: "claude-opus-5"), "Claude Opus 5")
        XCTAssertEqual(CodexRadarScoreCardText.modelLabel(model: "dsh-deepseek-v4-flash"), "DeepSeek V4 Flash · DSH")
        XCTAssertEqual(CodexRadarScoreCardText.effortLabel("xhigh"), "xhigh")
        XCTAssertEqual(CodexRadarScoreCardText.effortLabel("ultra"), "ultra")
        XCTAssertEqual(
            CodexRadarScoreCardText.fullLabel(model: "gpt-5.6-sol", effort: "ultra"),
            "GPT-5.6-Sol ultra"
        )
    }

    /// 验证其他模型默认只选各档位最高分排名前二的具体模型。
    func testCodexRadarOtherModelSelectionUsesTopTwoHighestScores() {
        let series = [
            makeRadarSeries(id: "opus-low", model: "claude-opus-5", effort: "low", score: 100),
            makeRadarSeries(id: "opus-high", model: "claude-opus-5", effort: "high", score: 130),
            makeRadarSeries(id: "fable", model: "fable-5", effort: nil, score: 136),
            makeRadarSeries(id: "gemini", model: "gemini-3.8-flash", effort: nil, score: 129)
        ]

        XCTAssertEqual(
            CodexRadarModelSelection.topModelIDs(from: series),
            Set(["fable-5", "claude-opus-5"])
        )
    }

    /// 验证同一 GPT 家族仅保留最高版本，并保留该版本的全部推理档位。
    func testCodexRadarGPTSelectionKeepsOnlyLatestVersionPerFamily() {
        let series = [
            makeRadarSeries(id: "sol-56-ultra", model: "gpt-5.6-sol", effort: "ultra"),
            makeRadarSeries(id: "sol-56-low", model: "gpt-5.6-sol", effort: "low"),
            makeRadarSeries(id: "sol-6-ultra", model: "gpt-6-sol", effort: "ultra"),
            makeRadarSeries(id: "sol-6-low", model: "gpt-6-sol", effort: "low"),
            makeRadarSeries(id: "terra-56", model: "gpt-5.6-terra", effort: "high")
        ]

        XCTAssertEqual(
            CodexRadarModelSelection.latestGPTSeriesByFamily(from: series).map(\.id),
            ["sol-6-ultra", "sol-6-low", "terra-56"]
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

    /// 验证单次请求读取 Terra 六档，按官网等权计分；零分、缺分和旧家族不混淆。
    func testDirectCodexRadarClientReadsThreeTaskScores() async throws {
        let transport = ThreeTaskTestTransport()
        let client = DirectCodexRadarClient { try await transport.respond(to: $0) }
        let snapshot = try await client.fetchRadarSnapshot(source: .codexRadar)
        let series = try XCTUnwrap(snapshot.modelIQ?.allSeries)
        let terra = series.filter { $0.model == "gpt-6.1-terra" }
        XCTAssertEqual(snapshot.source, .codexRadar)
        XCTAssertEqual(terra.count, 6)
        XCTAssertEqual(terra.first { $0.reasoningEffort == "ultra" }?.latest?.score, 132.5)
        XCTAssertEqual(try XCTUnwrap(terra.first { $0.reasoningEffort == "max" }?.latest?.score), 144.88709677419354, accuracy: 0.000001)
        XCTAssertEqual(series.first { $0.model == "gpt-6-luna" }?.latest?.score, 0)
        XCTAssertEqual(series.filter { $0.model == "gpt-6-luna" }.count, 1)
        XCTAssertFalse(series.contains { $0.model == "gpt-6-sol" || $0.model == "gpt-5.5" })
        XCTAssertTrue(series.allSatisfy { $0.recentDays.isEmpty && $0.latest?.coveredTasks == 3 })
        XCTAssertTrue(CodexRadarSource.allCases.allSatisfy { !$0.supportsScoreHistory })
        XCTAssertEqual(snapshot.modelIQ?.updatedAt, "2026-10-27T01:31:02.710353+00:00")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://codexradar.com/data/codex-three-task-results.json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")

        let missingTransport = ThreeTaskTestTransport(invalidField: "missing_latest")
        let missingSnapshot = try await DirectCodexRadarClient { try await missingTransport.respond(to: $0) }
            .fetchRadarSnapshot(source: .codexRadar)
        XCTAssertFalse(missingSnapshot.modelIQ?.allSeries.contains { $0.model?.hasSuffix("-sol") == true } == true)
    }

    /// 拒绝未知协议、重复档位、坏时间和异常分项，不能静默换算成可用成绩。
    func testThreeTaskRadarRejectsInvalidResponses() async throws {
        for field in ["schema", "protocol", "configurations", "task_count", "integrated_verified_at",
                      "duplicate_rows", "empty_rows", "score100", "score", "candy"] {
            let transport = ThreeTaskTestTransport(invalidField: field)
            let client = DirectCodexRadarClient { try await transport.respond(to: $0) }
            do {
                _ = try await client.fetchRadarSnapshot(source: .codexRadar)
                XCTFail("应拒绝异常字段 \(field)")
            } catch {
                guard case DirectCodexRadarClientError.invalidResponse = error else {
                    return XCTFail("\(field): \(error)")
                }
            }
        }
    }

    /// 限流只请求一次并报告失败，不重试或悄悄回退到旧基准。
    func testThreeTaskRadarStopsOnRateLimit() async throws {
        let transport = ThreeTaskTestTransport(statusCode: 429)
        let client = DirectCodexRadarClient { try await transport.respond(to: $0) }
        do {
            _ = try await client.fetchRadarSnapshot(source: .codexRadar)
            XCTFail("限流应返回错误")
        } catch {
            XCTAssertEqual(error as? DirectCodexRadarClientError, .httpStatus(429))
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }

    /// 三题接口变更或响应无效时，保留最近一次成功的同基准快照和落盘内容。
    @MainActor
    func testThreeTaskRadarFailurePreservesSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = ThreeTaskTestTransport()
        let snapshot = try await DirectCodexRadarClient { try await transport.respond(to: $0) }
            .fetchRadarSnapshot(source: .codexRadar)
        let cache = CodexRadarSnapshotStore(appGroupIdentifier: "", fallbackDirectory: directory)
        try cache.save(snapshot)
        let invalidTransport = ThreeTaskTestTransport(invalidField: "schema")
        let store = CodexRadarStore(
            client: DirectCodexRadarClient { try await invalidTransport.respond(to: $0) },
            store: cache, settingsProvider: { CodexRadarSettings(source: .codexRadar) }
        )
        await store.refresh()
        XCTAssertEqual(store.snapshot, snapshot)
        XCTAssertEqual(try cache.load(), snapshot)
        XCTAssertNotNil(store.errorMessage)
    }

    /// 手动与后台首轮均使用当前选中的来源，不额外请求其余供应商。
    @MainActor
    func testCodexRadarStoreRefreshesOnlySelectedSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let client = CountingCodexRadarClient()
        let store = CodexRadarStore(
            client: client,
            store: CodexRadarSnapshotStore(appGroupIdentifier: "", fallbackDirectory: directory),
            settingsProvider: { CodexRadarSettings(source: .aiIQ) }
        )
        store.start()
        for _ in 0..<100 where store.snapshot == nil {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        await store.refresh()
        XCTAssertEqual(client.fetchedSources, [.aiIQ, .aiIQ])
        XCTAssertEqual(store.snapshot?.source, .aiIQ)
    }

    /// 来源切换后旧请求即使报错也不能恢复旧缓存、污染错误信息或提前结束新来源的加载状态。
    @MainActor
    func testRadarSourceSwitchIgnoresStaleFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = CodexRadarSnapshotStore(appGroupIdentifier: "", fallbackDirectory: directory)
        try cache.save(CodexRadarSnapshot(
            fetchedAt: Date(), monitoredAt: nil, timezone: nil,
            prediction: nil, modelIQ: nil, source: .codexRadar
        ))
        let settings = RadarTestSettings()
        let client = SuspendedRadarClient()
        let store = CodexRadarStore(client: client, store: cache, settingsProvider: {
            CodexRadarSettings(source: settings.source)
        })
        let oldRefresh = Task { await store.refresh() }
        for _ in 0..<100 {
            if await client.requestCount == 1 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        settings.source = .aiIQ
        let newRefresh = Task { await store.refresh() }
        for _ in 0..<100 {
            if await client.requestCount == 2 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        await client.finish(source: .codexRadar, fails: true)
        await oldRefresh.value
        XCTAssertTrue(store.isRefreshing)
        XCTAssertNil(store.errorMessage)
        await client.finish(source: .aiIQ, fails: false)
        await newRefresh.value
        XCTAssertEqual(store.snapshot?.source, .aiIQ)
        XCTAssertEqual(try cache.load()?.source, .aiIQ)
        XCTAssertFalse(store.isRefreshing)
    }

    /// 新评分使用独立缓存文件；旧 IQ 和64题基准保留在磁盘，但不再加载。
    func testThreeTaskRadarCacheDoesNotLoadOlderScores() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for version in [1, 2] {
            let oldStore = CodexRadarSnapshotStore(
                appGroupIdentifier: "", fallbackDirectory: directory,
                fileName: "latest-codex-radar-v\(version).json"
            )
            try oldStore.save(CodexRadarSnapshot(
                fetchedAt: Date(), monitoredAt: nil, timezone: nil,
                prediction: nil, modelIQ: nil, source: .codexRadar
            ))
            XCTAssertNotNil(try oldStore.load())
        }
        let currentStore = CodexRadarSnapshotStore(appGroupIdentifier: "", fallbackDirectory: directory)
        XCTAssertNil(try currentStore.load())
    }

    /// 验证 Radar Insights 只提供当前综合分，不把推荐趋势拼成不完整历史。
    func testDirectCodexRadarClientReadsInsightsWithoutHistory() async throws {
        let body = """
        {
          "source_updated_at": "2026-09-12T16:37:23Z",
          "comprehensive_points": [
            {"model": "gpt-6-astra", "effort": "medium", "iq": 115.65, "samples": 201},
            {"model": "gpt-5.5", "effort": "high", "iq": 96.9, "samples": 210}
          ]
        }
        """
        let client = DirectCodexRadarClient(endpointURL: URL(string: "https://example.test/insights")!) { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (Data(body.utf8), response)
        }

        let snapshot = try await client.fetchRadarSnapshot(source: .radarInsights)

        XCTAssertEqual(snapshot.source, .radarInsights)
        XCTAssertEqual(snapshot.modelIQ?.primary.latest?.score, 115.65)
        XCTAssertEqual(snapshot.modelIQ?.primary.latest?.tasks, 201)
        XCTAssertTrue(snapshot.modelIQ?.primary.recentDays.isEmpty == true)
        XCTAssertFalse(snapshot.modelIQ?.allSeries.contains { $0.model == "gpt-5.5" } == true)
    }

    /// 验证 AI IQ 保留 OpenAI 和其他厂商各前六名，且不声明历史能力。
    func testDirectCodexRadarClientReadsTopSixModelsPerAIIQGroupWithoutHistory() async throws {
        let openAIModels = (1...7).map { rank in
            "{\"id\":\"gpt-test-\(rank)\",\"name\":\"GPT Test \(rank)\",\"provider\":\"OpenAI\",\"rank\":\(rank),\"iq\":\(141 - rank)}"
        }.joined(separator: ",")
        let otherModels = (1...7).map { rank in
            "{\"id\":\"claude-test-\(rank)\",\"name\":\"Claude Test \(rank)\",\"provider\":\"Anthropic\",\"rank\":\(rank + 20),\"iq\":\(131 - rank)}"
        }.joined(separator: ",")
        let body = "{\"updatedAt\":\"2026-09-14T19:57:30Z\",\"models\":[{\"id\":\"gpt-5.5\",\"name\":\"GPT-5.5\",\"provider\":\"OpenAI\",\"rank\":1,\"iq\":133},\(openAIModels),\(otherModels)]}"
        let client = DirectCodexRadarClient(endpointURL: URL(string: "https://example.test/models")!) { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (Data(body.utf8), response)
        }

        let snapshot = try await client.fetchRadarSnapshot(source: .aiIQ)

        XCTAssertEqual(snapshot.source, .aiIQ)
        XCTAssertEqual(snapshot.modelIQ?.allSeries.count, 12)
        XCTAssertEqual(snapshot.modelIQ?.primary.model, "gpt-test-1")
        XCTAssertTrue(snapshot.modelIQ?.allSeries.allSatisfy(\.recentDays.isEmpty) == true)
        XCTAssertFalse(snapshot.modelIQ?.allSeries.contains { $0.model == "gpt-5.5" } == true)
        XCTAssertEqual(snapshot.modelIQ?.allSeries.filter { $0.model?.hasPrefix("claude-") == true }.count, 6)
    }

    /// 验证雷达设置默认关闭，并能从共享 defaults 读取显式开启状态。
    func testCodexRadarSettingsDefaultToDisabledAndReadStoredValue() {
        let suiteName = "CodexMeterTests.codexRadarSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        XCTAssertTrue(CodexRadarSettings(defaults: defaults).isEnabled)
        XCTAssertEqual(CodexRadarSettings(defaults: defaults).source, .codexRadar)
        XCTAssertFalse(CodexRadarSettings(defaults: defaults).showsOtherModels)
        XCTAssertFalse(CodexRadarSettings(defaults: defaults).showsScoreChart)

        defaults.set(true, forKey: CodexRadarPreferenceKeys.isEnabled)
        defaults.set(CodexRadarSource.aiIQ.rawValue, forKey: CodexRadarPreferenceKeys.source)
        defaults.set(true, forKey: CodexRadarPreferenceKeys.showsOtherModels)
        defaults.set(false, forKey: CodexRadarPreferenceKeys.showsScoreChart)

        XCTAssertTrue(CodexRadarSettings(defaults: defaults).isEnabled)
        XCTAssertEqual(CodexRadarSettings(defaults: defaults).source, .aiIQ)
        XCTAssertTrue(CodexRadarSettings(defaults: defaults).showsOtherModels)
        XCTAssertFalse(CodexRadarSettings(defaults: defaults).showsScoreChart)
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
                updatedAt: "2026-06-24T15:00:00+08:00",
                quotaRadarUpdatedAt: "2026-06-23T14:55:28+08:00"
            ),
            source: .codexRadar
        )

        try store.save(snapshot)

        XCTAssertEqual(try store.load(), snapshot)
        XCTAssertEqual(store.snapshotURL().lastPathComponent, "latest-codex-radar-v3.json")
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
/// 构造指定模型、档位和分值的最小雷达序列，供排序与展示测试复用。
private func makeRadarSeries(
    id: String,
    model: String,
    effort: String?,
    score: Double = 100
) -> CodexRadarModelSeries {
    let run = CodexRadarIQRun(
        date: id,
        score: score,
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

/// 线程安全地记录请求次数与来源，验证关闭和定时任务不会访问其他数据源。
private final class CountingCodexRadarClient: CodexRadarFetching, @unchecked Sendable {
    private let queue = DispatchQueue(label: "CodexMeterTests.CountingCodexRadarClient")
    private var storedFetchCount = 0
    private var storedSources: [CodexRadarSource] = []

    var fetchCount: Int {
        queue.sync { storedFetchCount }
    }

    var fetchedSources: [CodexRadarSource] {
        queue.sync { storedSources }
    }

    /// 记录雷达请求次数并返回最小可用快照；测试只关心是否触发网络抽象。
    func fetchRadarSnapshot(source: CodexRadarSource) async throws -> CodexRadarSnapshot {
        queue.sync {
            storedFetchCount += 1
            storedSources.append(source)
        }
        return CodexRadarSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            monitoredAt: nil,
            timezone: nil,
            prediction: nil,
            modelIQ: nil,
            source: source
        )
    }
}

/// 三题 JSON 的内存传输；记录请求并注入边界错误，测试不依赖公网或站方改分。
private actor ThreeTaskTestTransport {
    private(set) var requests: [URLRequest] = []
    private let invalidField: String?
    private let statusCode: Int

    /// 仅改变指定边界字段或 HTTP 状态，正常样例包含官网 Terra 的真实计分输入。
    init(invalidField: String? = nil, statusCode: Int = 200) {
        self.invalidField = invalidField
        self.statusCode = statusCode
    }

    /// 返回旧版 Sol、最新 Sol/Terra、零分及缺分配置，验证筛选与一次请求即可更新。
    func respond(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = try XCTUnwrap(request.url)
        var rows: [[String: Any]] = [
            ["model": "gpt-6-sol", "effort": "max",
             "pompeii": ["score100": 80], "pelican": ["score": 80], "candy": ["correct": true]],
            ["model": "gpt-6.1-sol", "effort": "max",
             "pompeii": ["score100": 90], "pelican": ["score": 90], "candy": ["correct": true]]
        ]
        rows += ["ultra", "max", "xhigh", "high", "medium", "low"].map { effort in
            ["model": "gpt-6.1-terra", "effort": effort,
             "pompeii": ["score100": effort == "max" ? 96.7741935483871 : 75.0],
             "pelican": ["score": effort == "max" ? 93.0 : 90.0], "candy": ["correct": true]]
        }
        rows += [
            ["model": "gpt-6-luna", "effort": "low",
             "pompeii": ["score100": 0], "pelican": ["score": 0], "candy": ["correct": false]],
            ["model": "gpt-6-luna", "effort": "high",
             "pompeii": ["score100": NSNull()], "pelican": ["score": 0], "candy": ["correct": false]],
            ["model": "gpt-5.5", "effort": "max",
             "pompeii": ["score100": 100], "pelican": ["score": 100], "candy": ["correct": true]]
        ]
        switch invalidField {
        case "duplicate_rows": rows.append(rows[1])
        case "empty_rows": rows = []
        case "score100": rows[1]["pompeii"] = ["score100": -1]
        case "score": rows[1]["pelican"] = ["score": 101]
        case "candy": rows[1]["candy"] = ["correct": "unknown"]
        case "missing_latest": rows[1]["pompeii"] = ["score100": NSNull()]
        default: break
        }
        var body: [String: Any] = [
            "schema": "codex-three-task-results/1", "protocol": "codex-independent-three-v1",
            "configurations": rows.count, "task_count": 3,
            "integrated_verified_at": "2026-10-27T01:31:02.710353+00:00", "rows": rows
        ]
        if let invalidField {
            switch invalidField {
            case "schema", "protocol", "integrated_verified_at": body[invalidField] = "wrong"
            case "configurations": body[invalidField] = rows.count + 1
            case "task_count": body[invalidField] = 4
            default: break
            }
        }
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil))
        return (try JSONSerialization.data(withJSONObject: body), response)
    }
}

/// 测试专用主线程设置盒，允许安全地在异步请求期间切换来源。
@MainActor
private final class RadarTestSettings {
    var source: CodexRadarSource = .codexRadar
}

/// 显式控制请求完成顺序，验证旧来源迟到的失败不会干扰当前来源。
private actor SuspendedRadarClient: CodexRadarFetching {
    private var pending: [CodexRadarSource: CheckedContinuation<CodexRadarSnapshot, Error>] = [:]
    private(set) var requestCount = 0

    /// 挂起当前配置请求，直到测试明确完成该来源。
    func fetchRadarSnapshot(source: CodexRadarSource) async throws -> CodexRadarSnapshot {
        requestCount += 1
        return try await withCheckedThrowingContinuation { pending[source] = $0 }
    }

    /// 返回最小快照或模拟限流；没有待完成请求意味着测试编排错误。
    func finish(source: CodexRadarSource, fails: Bool) {
        guard let continuation = pending.removeValue(forKey: source) else {
            return XCTFail("不存在待完成请求 \(source)")
        }
        if fails {
            continuation.resume(throwing: DirectCodexRadarClientError.httpStatus(429))
        } else {
            continuation.resume(returning: CodexRadarSnapshot(
                fetchedAt: Date(), monitoredAt: nil, timezone: nil,
                prediction: nil, modelIQ: nil, source: source
            ))
        }
    }
}
