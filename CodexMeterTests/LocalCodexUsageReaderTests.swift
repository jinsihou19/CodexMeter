// 本文件验证本机 Codex SQLite 汇总、任务分类和失败降级行为。

import XCTest
@testable import CodexMeterShared

final class LocalCodexUsageReaderTests: XCTestCase {
    /// 验证注入的 SQLite 行会生成 token 汇总、项目排行和四类今日任务。
    func testReaderBuildsUsageAndTaskBoard() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000)
        let databaseURL = try temporaryFile(named: "state_5.sqlite", contents: Data())
        let automationURL = try temporaryFile(
            named: "automation.toml",
            contents: Data("name = \"晨间检查\"\nstatus = \"ACTIVE\"\nrrule = \"FREQ=DAILY\"\n".utf8)
        )
        let sessionURL = try temporaryFile(
            named: "rollout-test.jsonl",
            contents: Data("""
            {"timestamp":"1970-01-21T20:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000000,"cached_input_tokens":400000,"output_tokens":100000}}}}
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
            query: { _, sql in
                if sql.contains("AS lifetimeTokens") {
                    return Self.json([["todayTokens": 120, "sevenDayTokens": 560, "lifetimeTokens": 2_400, "threadCount": 4, "lastUpdatedAt": 1_799_900]])
                }
                if sql.contains("GROUP BY cwd") {
                    return Self.json([
                        ["cwd": "", "tokens": 100, "threadCount": 1, "lastActiveAt": 1_799_700],
                        ["cwd": "/Users/test/Beta", "tokens": 900, "threadCount": 2, "lastActiveAt": 1_799_800],
                        ["cwd": "/Users/test/Alpha", "tokens": 400, "threadCount": 1, "lastActiveAt": 1_799_600]
                    ])
                }
                if sql.contains("GROUP BY day") {
                    return Self.json([
                        ["day": "1970-01-20", "tokens": 200],
                        ["day": "1970-01-21", "tokens": 360]
                    ])
                }
                if sql.contains("rollout_path") {
                    return Self.json([
                        ["rolloutPath": sessionURL.path, "model": "gpt-5.5"]
                    ])
                }
                if sql.contains("archived = 0") {
                    return Self.json([
                        ["id": "active", "title": "正在实现", "preview": "", "cwd": "/Users/test/Beta", "tokens": 300, "updatedAt": 1_799_000],
                        ["id": "pending", "title": "", "preview": "待处理预览", "cwd": "", "tokens": 50, "updatedAt": 1_780_000]
                    ])
                }
                if sql.contains("archived = 1") {
                    return Self.json([
                        ["id": "done", "title": "已经完成", "preview": "", "cwd": "/Users/test/Alpha", "tokens": 80, "updatedAt": 1_790_000]
                    ])
                }
                return nil
            }
        )

        let loadedSnapshot = await reader.load()
        let snapshot = try XCTUnwrap(loadedSnapshot)

        XCTAssertEqual(snapshot.summary.todayTokens, 120)
        XCTAssertEqual(snapshot.summary.sevenDayTokens, 560)
        XCTAssertEqual(snapshot.summary.lifetimeTokens, 2_400)
        XCTAssertEqual(snapshot.summary.threadCount, 4)
        XCTAssertEqual(snapshot.summary.projects.map(\.name), ["Beta", "Alpha", "未归类"])
        XCTAssertEqual(snapshot.summary.dailyBuckets?.count, 190)
        XCTAssertEqual(snapshot.summary.dailyBuckets?.first(where: { $0.id == "1970-01-20" })?.tokens, 200)
        XCTAssertEqual(snapshot.summary.dailyBuckets?.first(where: { $0.id == "1970-01-21" })?.tokens, 360)
        XCTAssertEqual(snapshot.summary.dailyBuckets?.first(where: { $0.id == "1970-01-21" })?.estimatedCostUSD ?? 0, 6.2 * 360 / 560, accuracy: 0.001)
        XCTAssertEqual(snapshot.summary.dailyBuckets?.last?.tokens, 0)
        XCTAssertEqual(snapshot.summary.monthCost?.inputTokens, 1_000_000)
        XCTAssertEqual(snapshot.summary.monthCost?.cachedInputTokens, 400_000)
        XCTAssertEqual(snapshot.summary.monthCost?.outputTokens, 100_000)
        XCTAssertEqual(snapshot.summary.monthCost?.estimatedCostUSD ?? 0, 6.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.taskBoard.activeCount, 1)
        XCTAssertEqual(snapshot.taskBoard.pendingCount, 1)
        XCTAssertEqual(snapshot.taskBoard.scheduledCount, 1)
        XCTAssertEqual(snapshot.taskBoard.doneCount, 1)
        XCTAssertEqual(snapshot.taskBoard.items.first(where: { $0.kind == .active })?.title, "侧边栏会话名称")
        XCTAssertEqual(snapshot.taskBoard.items.first(where: { $0.kind == .pending })?.title, "待处理预览")
    }

    /// 验证数据库不存在或 sqlite3 查询失败时静默返回 nil。
    func testReaderReturnsNilWhenDatabaseIsUnavailable() async {
        let missingReader = LocalCodexUsageReader(
            now: Date.init,
            databaseURL: URL(fileURLWithPath: "/tmp/\(UUID().uuidString)/state_5.sqlite"),
            automationFiles: [],
            query: { _, _ in XCTFail("数据库缺失时不应执行查询"); return nil }
        )
        let missingSnapshot = await missingReader.load()
        XCTAssertNil(missingSnapshot)

        let databaseURL = try? temporaryFile(named: "state_5.sqlite", contents: Data())
        let failedReader = LocalCodexUsageReader(
            now: Date.init,
            databaseURL: databaseURL,
            automationFiles: [],
            query: { _, _ in nil }
        )
        let failedSnapshot = await failedReader.load()
        XCTAssertNil(failedSnapshot)
    }

    /// 验证 sqlite3 对零行查询返回空输出时，读取器仍生成有效统计而不是误判失败。
    func testReaderAcceptsEmptySQLiteJSONOutput() async throws {
        let databaseURL = try temporaryFile(named: "state_5.sqlite", contents: Data())
        let reader = LocalCodexUsageReader(
            now: { Date(timeIntervalSince1970: 1_800_000) },
            databaseURL: databaseURL,
            automationFiles: [],
            query: { _, sql in
                if sql.contains("AS lifetimeTokens") {
                    return Self.json([["todayTokens": 10, "sevenDayTokens": 20, "lifetimeTokens": 30, "threadCount": 1, "lastUpdatedAt": 1_800_000]])
                }
                if sql.contains("GROUP BY cwd") {
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
        XCTAssertEqual(snapshot.summary.todayTokens, 10)
        XCTAssertEqual(snapshot.taskBoard.doneCount, 0)
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

    /// 把字典数组编码成 sqlite3 -json 相同形态的数据。
    private static func json(_ rows: [[String: Any]]) -> Data? {
        try? JSONSerialization.data(withJSONObject: rows)
    }
}
