// 本文件验证本机 Codex SQLite 汇总、任务分类和失败降级行为。

import XCTest
@testable import CodexMeterShared

final class LocalCodexUsageReaderTests: XCTestCase {
    /// 验证注入的 SQLite 行会生成 token 汇总、项目排行和四类今日任务。
    func testReaderBuildsUsageAndTaskBoard() async throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-28T12:00:00Z"))
        let databaseURL = try temporaryFile(named: "state_5.sqlite", contents: Data())
        let automationURL = try temporaryFile(
            named: "automation.toml",
            contents: Data("name = \"晨间检查\"\nstatus = \"ACTIVE\"\nrrule = \"FREQ=DAILY\"\n".utf8)
        )
        let sessionURL = try temporaryFile(
            named: "rollout-test.jsonl",
            contents: Data("""
            {"timestamp":"2025-01-01T02:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900000,"cached_input_tokens":360000,"output_tokens":90000},"last_token_usage":{"input_tokens":900000,"cached_input_tokens":360000,"output_tokens":90000}}}}
            {"timestamp":"2026-07-28T02:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000000,"cached_input_tokens":400000,"output_tokens":100000},"last_token_usage":{"input_tokens":100000,"cached_input_tokens":40000,"output_tokens":10000}}}}
            """.utf8)
        )
        let sessionIndexURL = try temporaryFile(
            named: "session_index.jsonl",
            contents: Data("{\"id\":\"active\",\"thread_name\":\"侧边栏会话名称\"}\n".utf8)
        )
        let reader = LocalCodexUsageReader(
            now: { now },
            databaseURL: databaseURL,
            sessionIndexURL: sessionIndexURL,
            automationFiles: [automationURL],
            diagnostics: testDiagnosticLog(),
            query: { _, sql in
                if sql.contains("AS threadCount") {
                    return Self.json([["threadCount": 4, "lastUpdatedAt": 1_799_900]])
                }
                if sql.contains("AS rolloutPath") {
                    return Self.json([
                        ["threadID": "usage", "rolloutPath": sessionURL.path, "cwd": "/Users/test/Beta", "model": "gpt-5.5", "tokensUsed": 1_100_000]
                    ])
                }
                if sql.contains("archived = 0") {
                    return Self.json([
                        ["id": "active", "title": "正在实现", "preview": "", "cwd": "/Users/test/Beta", "tokens": 300, "updatedAt": now.timeIntervalSince1970 - 60],
                        ["id": "pending", "title": "", "preview": "待处理预览", "cwd": "", "tokens": 50, "updatedAt": now.timeIntervalSince1970 - 10_800]
                    ])
                }
                if sql.contains("archived = 1") {
                    return Self.json([
                        ["id": "done", "title": "已经完成", "preview": "", "cwd": "/Users/test/Alpha", "tokens": 80, "updatedAt": now.timeIntervalSince1970 - 120]
                    ])
                }
                return nil
            }
        )

        let loadedSnapshot = await reader.load()
        let snapshot = try XCTUnwrap(loadedSnapshot)

        XCTAssertEqual(snapshot.summary.todayTokens, 110_000)
        XCTAssertEqual(snapshot.summary.sevenDayTokens, 110_000)
        XCTAssertEqual(snapshot.summary.lifetimeTokens, 1_100_000)
        XCTAssertEqual(snapshot.summary.threadCount, 4)
        XCTAssertEqual(snapshot.summary.projects.map(\.name), ["Beta"])
        XCTAssertEqual(snapshot.summary.projects.first?.tokens, 110_000)
        XCTAssertEqual(snapshot.summary.dailyBuckets?.count, 190)
        XCTAssertEqual(snapshot.summary.dailyBuckets?.first(where: { $0.id == "2026-07-28" })?.tokens, 110_000)
        XCTAssertEqual(snapshot.summary.dailyBuckets?.first(where: { $0.id == "2025-01-01" })?.tokens, nil)
        XCTAssertEqual(snapshot.summary.dailyBuckets?.last?.tokens, 110_000)
        XCTAssertEqual(snapshot.summary.monthCost?.inputTokens, 100_000)
        XCTAssertEqual(snapshot.summary.monthCost?.cachedInputTokens, 40_000)
        XCTAssertEqual(snapshot.summary.monthCost?.outputTokens, 10_000)
        XCTAssertEqual(snapshot.summary.monthCost?.estimatedCostUSD ?? 0, 0.62, accuracy: 0.001)
        XCTAssertEqual(snapshot.taskBoard.activeCount, 1)
        XCTAssertEqual(snapshot.taskBoard.pendingCount, 1)
        XCTAssertEqual(snapshot.taskBoard.scheduledCount, 1)
        XCTAssertEqual(snapshot.taskBoard.doneCount, 1)
        XCTAssertEqual(snapshot.taskBoard.items.first(where: { $0.kind == .active })?.title, "侧边栏会话名称")
        XCTAssertEqual(snapshot.taskBoard.items.first(where: { $0.kind == .pending })?.title, "待处理预览")

        let handle = try FileHandle(forWritingTo: sessionURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("""

        {"timestamp":"2026-07-28T03:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1020000,"cached_input_tokens":408000,"output_tokens":102000},"last_token_usage":{"input_tokens":20000,"cached_input_tokens":8000,"output_tokens":2000}}}}
        """.utf8))

        let refreshed = await reader.load()
        let refreshedSnapshot = try XCTUnwrap(refreshed)
        XCTAssertEqual(refreshedSnapshot.summary.todayTokens, 132_000)
        XCTAssertEqual(refreshedSnapshot.summary.sevenDayTokens, 132_000)
        XCTAssertEqual(refreshedSnapshot.summary.lifetimeTokens, 1_122_000)
    }

    /// 验证数据库不存在或 sqlite3 查询失败时返回 nil，并留下可供设置页查看的诊断记录。
    func testReaderReturnsNilAndLogsWhyDatabaseIsUnavailable() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("CodexMeter.log")
        let diagnostics = AppDiagnosticLog(fileURL: logURL)
        let missingReader = LocalCodexUsageReader(
            now: Date.init,
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString)/state_5.sqlite"),
            automationFiles: [],
            diagnostics: diagnostics,
            query: { _, _ in XCTFail("数据库缺失时不应执行查询"); return nil }
        )
        let missingSnapshot = await missingReader.load()
        XCTAssertNil(missingSnapshot)
        XCTAssertTrue(try String(contentsOf: logURL, encoding: .utf8).contains("Codex 状态库不存在"))

        let databaseURL = try? temporaryFile(named: "state_5.sqlite", contents: Data())
        let failedReader = LocalCodexUsageReader(
            now: Date.init,
            databaseURL: databaseURL,
            automationFiles: [],
            diagnostics: diagnostics,
            query: { _, _ in nil }
        )
        let failedSnapshot = await failedReader.load()
        XCTAssertNil(failedSnapshot)
        let logContents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(logContents.contains("[本机统计]"))
        XCTAssertTrue(logContents.contains("总览查询失败"))
        XCTAssertTrue(logContents.contains("未生成可用快照"))
    }

    /// 验证 sqlite3 对零行查询返回空输出时，读取器仍生成有效统计而不是误判失败。
    func testReaderAcceptsEmptySQLiteJSONOutput() async throws {
        let databaseURL = try temporaryFile(named: "state_5.sqlite", contents: Data())
        let reader = LocalCodexUsageReader(
            now: { Date(timeIntervalSince1970: 1_800_000) },
            databaseURL: databaseURL,
            automationFiles: [],
            diagnostics: testDiagnosticLog(),
            query: { _, sql in
                if sql.contains("AS threadCount") {
                    return Self.json([["threadCount": 1, "lastUpdatedAt": 1_800_000]])
                }
                if sql.contains("AS rolloutPath") {
                    return Self.json([])
                }
                if sql.contains("archived = 0") {
                    return Self.json([])
                }
                if sql.contains("archived = 1") {
                    return Data()
                }
                return Data()
            }
        )

        let loadedSnapshot = await reader.load()
        let snapshot = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(snapshot.summary.todayTokens, 0)
        XCTAssertEqual(snapshot.taskBoard.doneCount, 0)
    }

    /// 验证有累计用量但 rollout 缺少事件时不输出猜测值，避免旧缓存继续展示虚假的时间段统计。
    func testReaderRejectsIncompleteRolloutUsage() async throws {
        let databaseURL = try temporaryFile(named: "state_5.sqlite", contents: Data())
        let sessionURL = try temporaryFile(
            named: "rollout-incomplete.jsonl",
            contents: Data("{\"type\":\"session_meta\"}\n".utf8)
        )
        let diagnostics = testDiagnosticLog()
        let reader = LocalCodexUsageReader(
            databaseURL: databaseURL,
            automationFiles: [],
            diagnostics: diagnostics,
            query: { _, sql in
                if sql.contains("AS threadCount") {
                    return Self.json([["threadCount": 1, "lastUpdatedAt": 1_800_000]])
                }
                if sql.contains("AS rolloutPath") {
                    return Self.json([[
                        "threadID": "incomplete",
                        "rolloutPath": sessionURL.path,
                        "cwd": "/Users/test/Beta",
                        "model": "gpt-5.5",
                        "tokensUsed": 100
                    ]])
                }
                return Self.json([])
            }
        )

        let snapshot = await reader.load()
        XCTAssertNil(snapshot)
        let log = try String(contentsOf: diagnostics.fileURL, encoding: .utf8)
        XCTAssertTrue(log.contains("已隐藏本机统计"))
    }

    /// 验证累计未增长事件只计算一次，并从 fork 子会话中剔除与父会话相同的归一化前缀。
    func testReaderNormalizesSnapshotsAndDeduplicatesForkPrefix() async throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-28T12:00:00Z"))
        let databaseURL = try temporaryFile(named: "state_5.sqlite", contents: Data())
        let parentURL = try temporaryFile(
            named: "rollout-parent.jsonl",
            contents: Data("""
            {"timestamp":"2026-07-28T01:00:00Z","type":"session_meta","payload":{"id":"parent"}}
            {"timestamp":"2026-07-28T01:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":10,"reasoning_output_tokens":2,"total_tokens":110},"last_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":10,"reasoning_output_tokens":2,"total_tokens":110}}}}
            {"timestamp":"2026-07-28T01:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":250,"cached_input_tokens":200,"output_tokens":20,"reasoning_output_tokens":4,"total_tokens":270},"last_token_usage":{"input_tokens":150,"cached_input_tokens":120,"output_tokens":10,"reasoning_output_tokens":2,"total_tokens":160}}}}
            {"timestamp":"2026-07-28T01:03:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":250,"cached_input_tokens":200,"output_tokens":20,"reasoning_output_tokens":4,"total_tokens":270},"last_token_usage":{"input_tokens":150,"cached_input_tokens":120,"output_tokens":10,"reasoning_output_tokens":2,"total_tokens":160}}}}
            """.utf8)
        )
        let childURL = try temporaryFile(
            named: "rollout-child.jsonl",
            contents: Data("""
            {"timestamp":"2026-07-28T02:00:00Z","type":"session_meta","payload":{"id":"child","forked_from_id":"parent"}}
            {"timestamp":"2026-07-28T02:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":10,"reasoning_output_tokens":2,"total_tokens":110},"last_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":10,"reasoning_output_tokens":2,"total_tokens":110}}}}
            {"timestamp":"2026-07-28T02:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":250,"cached_input_tokens":200,"output_tokens":20,"reasoning_output_tokens":4,"total_tokens":270},"last_token_usage":{"input_tokens":150,"cached_input_tokens":120,"output_tokens":10,"reasoning_output_tokens":2,"total_tokens":160}}}}
            {"timestamp":"2026-07-28T02:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":250,"cached_input_tokens":200,"output_tokens":20,"reasoning_output_tokens":4,"total_tokens":270},"last_token_usage":{"input_tokens":150,"cached_input_tokens":120,"output_tokens":10,"reasoning_output_tokens":2,"total_tokens":160}}}}
            {"timestamp":"2026-07-28T02:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":220,"output_tokens":30,"reasoning_output_tokens":6,"total_tokens":330},"last_token_usage":{"input_tokens":50,"cached_input_tokens":20,"output_tokens":10,"reasoning_output_tokens":2,"total_tokens":60}}}}
            """.utf8)
        )
        let reader = LocalCodexUsageReader(
            now: { now },
            databaseURL: databaseURL,
            automationFiles: [],
            diagnostics: testDiagnosticLog(),
            query: { _, sql in
                if sql.contains("AS threadCount") {
                    return Self.json([["threadCount": 2, "lastUpdatedAt": now.timeIntervalSince1970]])
                }
                if sql.contains("AS rolloutPath") {
                    return Self.json([
                        ["threadID": "parent", "rolloutPath": parentURL.path, "cwd": "/Users/test/Fork", "model": "gpt-5.5", "tokensUsed": 270],
                        ["threadID": "child", "rolloutPath": childURL.path, "cwd": "/Users/test/Fork", "model": "gpt-5.5", "tokensUsed": 330]
                    ])
                }
                return Self.json([])
            }
        )

        let loadedSnapshot = await reader.load()
        let snapshot = try XCTUnwrap(loadedSnapshot)

        XCTAssertEqual(snapshot.summary.todayTokens, 330)
        XCTAssertEqual(snapshot.summary.sevenDayTokens, 330)
        XCTAssertEqual(snapshot.summary.lifetimeTokens, 330)
        XCTAssertEqual(snapshot.summary.projects.first?.tokens, 330)
        XCTAssertEqual(snapshot.summary.monthCost?.inputTokens, 300)
        XCTAssertEqual(snapshot.summary.monthCost?.cachedInputTokens, 220)
        XCTAssertEqual(snapshot.summary.monthCost?.outputTokens, 30)
    }

    /// 验证 fork 父会话不可用时拒绝展示无法去重的估算值。
    func testReaderRejectsForkWhenParentIsMissing() async throws {
        let databaseURL = try temporaryFile(named: "state_5.sqlite", contents: Data())
        let childURL = try temporaryFile(
            named: "rollout-child.jsonl",
            contents: Data("""
            {"timestamp":"2026-07-28T02:00:00Z","type":"session_meta","payload":{"id":"child","forked_from_id":"missing-parent"}}
            {"timestamp":"2026-07-28T02:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":10,"total_tokens":110},"last_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":10,"total_tokens":110}}}}
            """.utf8)
        )
        let diagnostics = testDiagnosticLog()
        let reader = LocalCodexUsageReader(
            databaseURL: databaseURL,
            automationFiles: [],
            diagnostics: diagnostics,
            query: { _, sql in
                if sql.contains("AS threadCount") {
                    return Self.json([["threadCount": 1, "lastUpdatedAt": 1_800_000]])
                }
                if sql.contains("AS rolloutPath") {
                    return Self.json([[
                        "threadID": "child",
                        "rolloutPath": childURL.path,
                        "cwd": "/Users/test/Fork",
                        "model": "gpt-5.5",
                        "tokensUsed": 110
                    ]])
                }
                return Self.json([])
            }
        )

        let snapshot = await reader.load()
        XCTAssertNil(snapshot)
        XCTAssertTrue(try String(contentsOf: diagnostics.fileURL, encoding: .utf8).contains("fork 父会话缺失"))
    }

    /// 验证两代 sqlite3 CLI 的 CANTOPEN 形式都会触发一次重试，其他错误不重试。
    func testSQLiteCantOpenErrorsAreRetryable() {
        XCTAssertTrue(LocalCodexUsageReader.shouldRetrySQLite(
            terminationStatus: 1,
            errorText: "Parse error: unable to open database file (14)"
        ))
        XCTAssertTrue(LocalCodexUsageReader.shouldRetrySQLite(
            terminationStatus: 14,
            errorText: "Error: in prepare, unable to open database file (14)"
        ))
        XCTAssertFalse(LocalCodexUsageReader.shouldRetrySQLite(
            terminationStatus: 1,
            errorText: "no such table: threads"
        ))
    }

    /// 创建测试文件并返回路径，目录由系统临时目录托管。
    private func temporaryFile(named name: String, contents: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    /// 为每个测试隔离诊断文件，避免测试记录混入用户实际日志。
    private func testDiagnosticLog() -> AppDiagnosticLog {
        AppDiagnosticLog(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("CodexMeter.log")
        )
    }

    /// 把字典数组编码成 sqlite3 -json 相同形态的数据。
    private static func json(_ rows: [[String: Any]]) -> Data? {
        try? JSONSerialization.data(withJSONObject: rows)
    }
}
