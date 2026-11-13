// 公司监控的采集、隐私、状态归约和稳定工位测试；全部写入独立临时目录。
import CodexMeterShared
import XCTest

/// 通过原生 Hook 写入到页面读取的完整链路验证详细信息，不把演示通过当成真实接入通过。
final class CodexOfficeTests: XCTestCase {
    /// 并行工具单独配对计时，重复或迟到事件不能覆盖另一个工具的运行状态。
    func testParallelToolsPairDurationsAndDeduplicateLateEvents() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        try fixture.record("UserPromptSubmit", seconds: 0)
        try fixture.record("PreToolUse", call: "a", seconds: 1)
        try fixture.record("PreToolUse", call: "b", seconds: 2)
        try fixture.record("PostToolUse", call: "a", seconds: 3)
        XCTAssertEqual(try fixture.snapshot().state, .running)
        try fixture.record("PostToolUse", call: "b", seconds: 5, extra: ["tool_response": ["exit_code": 1]])
        let snapshot = try fixture.snapshot()
        let office = try XCTUnwrap(snapshot.office)
        XCTAssertEqual(office.toolCalls, 2)
        XCTAssertEqual(office.failedTools, 1)
        XCTAssertEqual(office.tools.first(where: { $0.id == "a" })?.duration, 2)
        XCTAssertEqual(office.tools.first(where: { $0.id == "b" })?.duration, 3)
        XCTAssertEqual(office.history.count, 5)
        try fixture.record("PreToolUse", call: "b", seconds: 6)
        try fixture.record("PostToolUse", call: "b", seconds: 7)
        XCTAssertEqual(try fixture.snapshot(), snapshot)
    }

    /// 一秒内的完整工具活动保存在 Hook 历史中，页面轮询也能读取全部事件；超长历史有界。
    @MainActor
    func testBurstHistorySurvivesPollingAndIsBounded() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        try fixture.record("UserPromptSubmit", seconds: 0)
        for index in 0..<80 {
            try fixture.record("PreToolUse", call: "call-\(index)", seconds: Double(index) / 1000)
            try fixture.record("PostToolUse", call: "call-\(index)", seconds: Double(index) / 1000 + 0.0001)
        }
        let office = try XCTUnwrap(fixture.snapshot().office)
        XCTAssertEqual(office.history.count, 64)
        XCTAssertEqual(office.tools.count, 32)
        XCTAssertEqual(office.toolCalls, 80)
        let store = fixture.store()
        store.refresh(now: fixture.now.addingTimeInterval(1))
        XCTAssertEqual(store.events.count, 60)
        XCTAssertTrue(store.events.contains { $0.operation.contains("运行命令") })
        XCTAssertEqual(store.employees.first?.details?.toolCalls, 80)
    }

    /// 白名单摘要保留操作类型、文件名与模型计数，原始命令参数、提示词和输出不会落盘。
    func testDetailedCollectionExcludesRawContentAndCapturesModelMetadata() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        let secret = "secret-content-must-never-be-stored"
        try fixture.record("UserPromptSubmit", seconds: 0, extra: ["prompt": secret, "model": "test-model", "permission_mode": "default"])
        try fixture.record("PreModelRequest", seconds: 1, extra: ["model": "test-model"])
        try fixture.record("PostModelRequest", seconds: 2, extra: ["token_usage": ["total_tokens": 123, "input_tokens": 100, "arbitrary": 999], "status": "completed"])
        try fixture.record("PreToolUse", call: "curl", seconds: 3, extra: ["tool_input": ["cmd": "curl -H Authorization:\(secret) https://private.example/\(secret)"]])
        try fixture.record("PostToolUse", call: "curl", seconds: 4, extra: ["tool_response": ["output": secret]])
        try fixture.record("PreToolUse", call: "edit", seconds: 5, extra: ["tool_name": "apply_patch", "tool_input": ["command": "*** Begin Patch\n*** Update File: /workspace/App.swift\n+\(secret)\n*** End Patch"]])
        try fixture.record("Stop", seconds: 6)
        let snapshot = try fixture.snapshot()
        let office = try XCTUnwrap(snapshot.office)
        XCTAssertEqual(office.model, "test-model")
        XCTAssertEqual(office.cwd, fixture.directory.path)
        XCTAssertEqual(office.modelRequests, 1)
        XCTAssertEqual(office.latestTokenUsage, ["total_tokens": 123, "input_tokens": 100])
        XCTAssertEqual(office.turnFinishedAt! - office.turnStartedAt!, 6)
        XCTAssertEqual(office.completedTurns, 1)
        XCTAssertTrue(office.history.contains { $0.operation == "修改文件 · App.swift" })
        XCTAssertFalse(try String(contentsOf: fixture.activityURL, encoding: .utf8).contains(secret))
        XCTAssertEqual(office.tools.last?.outcome, "unknown")
        XCTAssertNil(office.tools.last?.duration)
    }

    /// 会话开始可以入职；恢复窗口不得清除待回答问题，结束标记仍能拒绝迟到工具。
    func testSessionStartResumeAndTerminalGuards() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        try fixture.record("SessionStart", seconds: 0, withoutTurn: true)
        XCTAssertEqual(try fixture.snapshot().state, .idle)
        try fixture.record("UserPromptSubmit", seconds: 1)
        try fixture.record("PreToolUse", call: "question", seconds: 2, extra: ["tool_name": "request_user_input_async", "tool_input": ["questions": [["title": "test"]]]])
        try fixture.record("SessionStart", seconds: 3, withoutTurn: true)
        XCTAssertEqual(try fixture.snapshot().pendingQuestionIDs, ["question:0"])
        XCTAssertEqual(try fixture.snapshot().state, .waitingApproval)
        try fixture.record("Interrupt", seconds: 4)
        try fixture.record("SessionStart", seconds: 5, withoutTurn: true)
        let ended = try fixture.snapshot()
        try fixture.record("PreToolUse", call: "late", seconds: 6)
        XCTAssertEqual(try fixture.snapshot(), ended)
    }

    /// 超时只停止动作，保留已观察到的同事和详细资料；一天后才离开名册。
    @MainActor
    func testOfficeRetentionAndExpiredSignals() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        try fixture.record("UserPromptSubmit", seconds: 0, extra: ["model": "test-model"])
        let store = fixture.store()
        store.refresh(now: fixture.now.addingTimeInterval(61))
        XCTAssertEqual(store.employees.count, 1)
        XCTAssertEqual(store.employees.first?.status, .idle)
        XCTAssertTrue(store.employees.first?.signalExpired == true)
        XCTAssertEqual(store.employees.first?.details?.model, "test-model")
        store.refresh(now: fixture.now.addingTimeInterval(86_401))
        XCTAssertTrue(store.employees.isEmpty)
    }

    /// 演示切换和昵称操作不得修改真实状态文件，退出演示立即恢复真实身份。
    @MainActor
    func testDemoIsolationAndStableNicknames() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        try fixture.record("UserPromptSubmit", seconds: 0)
        let original = try Data(contentsOf: fixture.activityURL)
        let store = fixture.store()
        store.refresh(now: fixture.now)
        store.rename("session", to: "  新同事  ")
        XCTAssertEqual(store.employees.first?.name, "新同事")
        store.setDemo(true)
        XCTAssertEqual(store.employees.count, 6)
        XCTAssertTrue(store.employees.allSatisfy(\.isDemo))
        store.refresh(now: Date().addingTimeInterval(12))
        XCTAssertEqual(try Data(contentsOf: fixture.activityURL), original)
        store.setDemo(false)
        XCTAssertEqual(store.employees.map(\.id), ["session"])
        XCTAssertEqual(store.employees.first?.name, "新同事")
    }

    /// 默认昵称覆盖多人名册，新增会话和重开页面不抢占旧名，手动取名优先于自动分配。
    @MainActor
    func testDefaultNicknamesAreUniqueAndKeepExistingAssignments() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }

        /// 给每个会话独立的持久身份，复用真实 Hook 生成活动记录。
        func record(_ id: String, seconds: Double) throws {
            let transcript = fixture.directory.appendingPathComponent(id + ".jsonl")
            let metadata: [String: Any] = ["type": "session_meta", "payload": ["id": id, "source": "cli", "cwd": fixture.directory.path]]
            try JSONSerialization.data(withJSONObject: metadata).write(to: transcript)
            try fixture.record("UserPromptSubmit", seconds: seconds, extra: ["session_id": id, "transcript_path": transcript.path])
        }

        let ids = (0..<80).map { "session-\($0)" }
        for id in ids { try record(id, seconds: 0) }
        let store = fixture.store()
        store.refresh(now: fixture.now)
        let initial = Dictionary(uniqueKeysWithValues: store.employees.map { ($0.id, $0.name) })
        XCTAssertEqual(Set(initial.values).count, ids.count)
        XCTAssertTrue(initial.values.allSatisfy { (2...3).contains($0.count) })
        XCTAssertTrue(initial.values.contains { $0.count == 3 })

        // 新会话与第一位同事的取名起点相同，且按 ID 排在他前面。
        let newcomer = "newcomer-55"
        try record(newcomer, seconds: 1)
        let reopened = fixture.store()
        reopened.refresh(now: fixture.now.addingTimeInterval(1))
        let updated = Dictionary(uniqueKeysWithValues: reopened.employees.map { ($0.id, $0.name) })
        XCTAssertEqual(Set(updated.values).count, ids.count + 1)
        for (id, name) in initial { XCTAssertEqual(updated[id], name) }

        let name = try XCTUnwrap(initial[ids[0]])
        reopened.rename(newcomer, to: name)
        let renamed = Dictionary(uniqueKeysWithValues: reopened.employees.map { ($0.id, $0.name) })
        XCTAssertEqual(renamed[newcomer], name)
        XCTAssertNotEqual(renamed[ids[0]], name)
        XCTAssertEqual(Set(renamed.values).count, ids.count + 1)
        XCTAssertTrue(reopened.events.allSatisfy { renamed[$0.employeeID] == $0.name })

        reopened.rename(newcomer, to: " ")
        let reset = Dictionary(uniqueKeysWithValues: reopened.employees.map { ($0.id, $0.name) })
        XCTAssertEqual(reset[ids[0]], renamed[ids[0]])
        XCTAssertEqual(Set(reset.values).count, ids.count + 1)
    }

    /// 旧版快照仍可解码，缺少详细资料时不得伪造调用次数或模型。
    func testOldSnapshotsDecodeWithoutOfficeDetails() throws {
        let snapshot = CodexHookActivitySnapshot(state: .running, sessionID: "old", turnID: "turn", eventName: "PreToolUse", toolName: "Bash", message: nil, updatedAt: 1)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        object.removeValue(forKey: "office")
        let decoded = try JSONDecoder().decode(CodexHookActivitySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.office)
    }

    /// MCP 的结构化失败与嵌套执行元数据均能识别，子代理模型事件不能污染父会话。
    func testMCPFailuresAndChildModelEvents() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        try fixture.record("UserPromptSubmit", seconds: 0, extra: ["model": "root-model"])
        try fixture.record("PreModelRequest", seconds: 1, extra: ["agent_id": "child", "model": "child-model"])
        XCTAssertEqual(try fixture.snapshot().office?.model, "root-model")
        XCTAssertEqual(try fixture.snapshot().office?.modelRequests, 0)
        try fixture.record("PreToolUse", call: "mcp", seconds: 2)
        try fixture.record("PostToolUse", call: "mcp", seconds: 3, extra: ["tool_response": ["isError": true]])
        XCTAssertEqual(try fixture.snapshot().state, .failed)
        try fixture.record("PreToolUse", call: "json", seconds: 4)
        try fixture.record("PostToolUse", call: "json", seconds: 5, extra: ["tool_response": ["metadata": ["exit_code": 2]]])
        XCTAssertEqual(try fixture.snapshot().office?.failedTools, 2)
    }

    /// 没有失败标记不等于成功，普通文本与空结果只能确认工具返回。
    func testToolSuccessRequiresAnExplicitResult() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        try fixture.record("UserPromptSubmit", seconds: 0)
        let cases: [(Any, String)] = [
            (["exit_code": 0], "succeeded"), (["success": true], "succeeded"),
            (["isError": false], "succeeded"), (["isError": true], "failed"),
            ("ordinary output", "returned"), (NSNull(), "returned")
        ]
        for (index, item) in cases.enumerated() {
            let call = "result-\(index)"
            try fixture.record("PreToolUse", call: call, seconds: Double(index * 2 + 1))
            try fixture.record("PostToolUse", call: call, seconds: Double(index * 2 + 2), extra: ["tool_response": item.0])
            XCTAssertEqual(try fixture.snapshot().office?.tools.first(where: { $0.id == call })?.outcome, item.1)
        }
    }

    /// 普通输出中的返回头与 JSON 不代表退出状态，只接受原生执行器的结构化元数据。
    func testNativeExecutionResultHeadersAndMetadata() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        try fixture.record("UserPromptSubmit", seconds: 0)
        let results: [(Any, Int?)] = [
            ("Chunk ID: qa\nWall time: 0.1 seconds\nProcess exited with code 1\nFinal output:\n", nil),
            (["content": [["type": "text", "text": "Wall time: 0.1 seconds\nExit code: 2\nOutput:\n"]]], nil),
            (["metadata": ["exit_code": 3]], 3),
            (["exit_code": 0, "output": "Exit code: 9"], 0),
            ("{\"exit_code\":0}", nil)
        ]
        for (index, item) in results.enumerated() {
            let call = "native-\(index)"
            try fixture.record("PreToolUse", call: call, seconds: Double(index * 2 + 1))
            try fixture.record("PostToolUse", call: call, seconds: Double(index * 2 + 2), extra: ["tool_response": item.0])
            let tool = try XCTUnwrap(fixture.snapshot().office?.tools.first(where: { $0.id == call }))
            XCTAssertEqual(tool.exitCode, item.1)
            XCTAssertEqual(tool.outcome, item.1.map { $0 == 0 ? "succeeded" : "failed" } ?? "returned")
        }
        XCTAssertNil(CodexOfficeHookReducer.exitCode("ordinary output\nExit code: 9"))
    }

    /// 缺少调用编号的兼容事件可连续执行同名工具，不能被误认为迟到的第一次调用。
    func testLegacyToolsWithoutCallIDsCanRepeat() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        try fixture.record("UserPromptSubmit", seconds: 0)
        for index in 0..<2 {
            try fixture.record("PreToolUse", seconds: Double(index * 2 + 1), extra: ["tool_name": "Bash"])
            try fixture.record("PostToolUse", seconds: Double(index * 2 + 2), extra: ["tool_name": "Bash"])
        }
        XCTAssertEqual(try fixture.snapshot().office?.toolCalls, 2)
        XCTAssertEqual(try fixture.snapshot().state, .thinking)
    }

    /// 结束 Hook 丢失时以日志校正档案，超过短超时后也不重新变成运行或信号未知。
    @MainActor
    func testTranscriptCompletionResolvesMissingToolResult() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        try fixture.record("UserPromptSubmit", seconds: 0)
        try fixture.record("PreToolUse", call: "missing-result", seconds: 1)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let event: [String: Any] = ["type": "event_msg", "timestamp": formatter.string(from: fixture.now.addingTimeInterval(2)), "payload": ["type": "task_complete", "turn_id": "turn"]]
        let handle = try FileHandle(forWritingTo: fixture.transcriptURL)
        try handle.seekToEnd()
        var data = try JSONSerialization.data(withJSONObject: event)
        data.append(10)
        try handle.write(contentsOf: data)
        try handle.close()
        let store = fixture.store()
        store.refresh(now: fixture.now.addingTimeInterval(4))
        XCTAssertEqual(store.employees.first?.status, .completed)
        XCTAssertEqual(store.employees.first?.details?.tools.first?.outcome, "unknown")
        XCTAssertNil(store.employees.first?.details?.tools.first?.duration)
        store.refresh(now: fixture.now.addingTimeInterval(120))
        XCTAssertEqual(store.employees.first?.status, .idle)
        XCTAssertEqual(store.employees.first?.signalExpired, false)
        XCTAssertTrue(store.events.contains { $0.operation == "日志确认本轮已完成" })
    }

    /// 真实返回可以补齐漏发的 PostToolUse，并行中未返回的调用仍须保持工作状态。
    @MainActor
    func testTranscriptReturnsResolveMissingHooksWithoutAssumingSuccess() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        try fixture.record("UserPromptSubmit", seconds: 0)
        try fixture.record("PreToolUse", call: "first", seconds: 1)
        try fixture.record("PreToolUse", call: "second", seconds: 2)
        try fixture.appendReturn("first", seconds: 3)
        let store = fixture.store()
        store.refresh(now: fixture.now.addingTimeInterval(4))
        XCTAssertEqual(store.employees.first?.status, .working)
        XCTAssertEqual(store.employees.first?.details?.tools.first(where: { $0.id == "first" })?.outcome, "returned")
        XCTAssertNil(store.employees.first?.details?.tools.first(where: { $0.id == "second" })?.finishedAt)
        try fixture.appendReturn("second", seconds: 5)
        let original = try Data(contentsOf: fixture.activityURL)
        store.refresh(now: fixture.now.addingTimeInterval(6))
        XCTAssertEqual(store.employees.first?.status, .thinking)
        XCTAssertEqual(store.employees.first?.details?.tools.map(\.outcome), ["returned", "returned"])
        let tools = try XCTUnwrap(store.employees.first?.details?.tools)
        XCTAssertEqual(try XCTUnwrap(tools[0].duration), 2, accuracy: 0.002)
        XCTAssertEqual(try XCTUnwrap(tools[1].duration), 3, accuracy: 0.002)
        XCTAssertEqual(store.employees.first?.details?.toolCalls, 2)
        XCTAssertEqual(store.employees.first?.details?.failedTools, 0)
        XCTAssertFalse(store.events.contains { $0.operation.contains("不可保留的工具输出") })
        XCTAssertEqual(try Data(contentsOf: fixture.activityURL), original)
    }

    /// 长工具运行超过原状态 TTL 后刚返回，不能把新收到的返回误报为信号失效。
    @MainActor
    func testLongRunningToolReturnRefreshesTheObservedActivityTime() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        try fixture.record("UserPromptSubmit", seconds: 0)
        try fixture.record("PreToolUse", call: "long", seconds: 1)
        try fixture.appendReturn("long", seconds: 121)
        let store = fixture.store()
        store.refresh(now: fixture.now.addingTimeInterval(123))
        XCTAssertEqual(store.employees.first?.status, .thinking)
        XCTAssertEqual(store.employees.first?.signalExpired, false)
        XCTAssertEqual(try XCTUnwrap(store.employees.first).updatedAt.timeIntervalSince1970, fixture.now.timeIntervalSince1970 + 121, accuracy: 0.002)
    }

    /// 长日志中的旧返回不会因只读尾部而漏掉，超大无关记录也不能阻断后续工具校正。
    @MainActor
    func testToolReturnScanAdvancesAcrossLargeUnrelatedRecords() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        try fixture.record("UserPromptSubmit", seconds: 0)
        try fixture.record("PreToolUse", call: "earlier", seconds: 1)
        try fixture.appendReturn("earlier", seconds: 2)
        let handle = try FileHandle(forWritingTo: fixture.transcriptURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(("{\"type\":\"padding\",\"payload\":\"" + String(repeating: "x", count: 5_000_000) + "\"}\n").utf8))
        try handle.close()
        try fixture.record("PreToolUse", call: "later", seconds: 3)
        try fixture.appendReturn("later", seconds: 4)
        let store = fixture.store()
        for _ in 0..<6 { store.refresh(now: fixture.now.addingTimeInterval(5)) }
        XCTAssertEqual(store.employees.first?.details?.tools.map(\.outcome), ["returned", "returned"])
        XCTAssertEqual(store.employees.first?.status, .thinking)
    }

    /// 同步提问和审批在工具返回后结束等待；异步提问仅 accepted 时仍应等用户回复。
    @MainActor
    func testRecoveredToolReturnsRespectQuestionAndApprovalBoundaries() throws {
        for tool in ["request_user_input", "request_user_input_async", "Bash"] {
            let fixture = try OfficeFixture()
            defer { fixture.clean() }
            try fixture.record("UserPromptSubmit", seconds: 0)
            try fixture.record("PreToolUse", call: "question", seconds: 1, extra: ["tool_name": tool])
            if tool == "Bash" {
                try fixture.record("PermissionRequest", call: "question", seconds: 2, extra: ["tool_name": tool])
            }
            try fixture.appendReturn("question", seconds: 3)
            let store = fixture.store()
            store.refresh(now: fixture.now.addingTimeInterval(4))
            XCTAssertEqual(store.employees.first?.status, tool == "request_user_input_async" ? .waiting : .thinking, tool)
        }
    }

    /// 空闲超时会退出三维场景，名册仍保留真实会话与退出原因。
    @MainActor
    func testIdleSessionLeavesSceneAndStaysInRoster() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        let store = fixture.store()
        try fixture.record("SessionStart", seconds: 0)
        store.refresh(now: fixture.now.addingTimeInterval(299))
        XCTAssertEqual(store.employees.first?.status, .idle)
        XCTAssertEqual(store.employees.first?.isOnSite, true)
        store.refresh(now: fixture.now.addingTimeInterval(301))
        XCTAssertEqual(store.employees.map(\.id), ["session"])
        XCTAssertEqual(store.employees.first?.isOnSite, false)
        try fixture.record("SessionEnd", seconds: 302)
        store.refresh(now: fixture.now.addingTimeInterval(303))
        XCTAssertEqual(store.employees.first?.eventName, "SessionEnd")
        XCTAssertEqual(store.employees.first?.isOnSite, false)
    }

}

/// 创建真实主会话日志头与独立活动文件，复用生产事件处理入口而非手造详细结果。
private struct OfficeFixture {
    let directory: URL
    let activityURL: URL
    let transcriptURL: URL
    let now = Date()
    let suite: String
    let defaults: UserDefaults

    /// 所有会话与偏好都隔离在随机测试目录中，失败也可清理。
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-office-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        activityURL = directory.appendingPathComponent("activity.json")
        transcriptURL = directory.appendingPathComponent("rollout.jsonl")
        suite = "CodexOfficeTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        let metadata: [String: Any] = ["type": "session_meta", "payload": ["id": "session", "source": "cli", "cwd": directory.path]]
        var data = try JSONSerialization.data(withJSONObject: metadata)
        data.append(10)
        try data.write(to: transcriptURL)
    }

    /// 生成具有可信主会话身份的事件，允许测试覆盖必要的可选字段与事件顺序。
    func record(_ event: String, call: String? = nil, seconds: Double, extra: [String: Any] = [:], withoutTurn: Bool = false) throws {
        var payload: [String: Any] = ["hook_event_name": event, "session_id": "session", "transcript_path": transcriptURL.path, "cwd": directory.path]
        if !withoutTurn { payload["turn_id"] = "turn" }
        if let call { payload["tool_use_id"] = call; payload["tool_name"] = "exec_command"; payload["tool_input"] = ["cmd": "swift test"] }
        payload.merge(extra) { _, new in new }
        try CodexActivityHook.record(payload: payload, at: activityURL, now: now.addingTimeInterval(seconds))
    }

    /// 解码最终落盘状态，以文件格式而不是内部实现作为测试边界。
    func snapshot() throws -> CodexHookActivitySnapshot {
        try XCTUnwrap(JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: activityURL)).sessions["session"])
    }

    /// 模拟真实日志的工具返回，只让生产读取器提取编号和时间，正文不得流入展示数据。
    func appendReturn(_ id: String, seconds: TimeInterval) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let event: [String: Any] = ["type": "response_item", "timestamp": formatter.string(from: now.addingTimeInterval(seconds)), "payload": ["type": "function_call_output", "call_id": id, "output": [["type": "input_text", "text": "不可保留的工具输出"]]]]
        var data = try JSONSerialization.data(withJSONObject: event)
        data.append(10)
        let handle = try FileHandle(forWritingTo: transcriptURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    /// 页面读取生产读取器，仅将文件路径、标题来源和偏好替换成测试隔离值。
    @MainActor
    func store() -> CodexOfficeStore {
        CodexOfficeStore(activity: CodexHookActivityStore(activityURL: activityURL, legacyActivityURL: nil), indexURL: nil, defaults: defaults)
    }

    /// 清理测试文件与昵称，避免重复运行累积本机数据。
    func clean() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
    }
}
