// 公司监控的采集、隐私、状态归约和稳定工位测试；全部写入独立临时目录。
import AppKit
import CodexMeterShared
import SceneKit
import simd
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

    /// 海岛的三人演示采用独立演员和动作节奏，切回普通演示与实时数据时重新取样。
    @MainActor
    func testIslandDemoRestartsWhenChangingThemes() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        try fixture.record("UserPromptSubmit", seconds: 0)
        let original = try Data(contentsOf: fixture.activityURL)
        let store = fixture.store()
        store.setDemo(true, island: true)
        XCTAssertEqual(store.employees.map(\.appearance), [0, 1, 3])
        XCTAssertEqual(store.employees.map(\.status), [.working, .thinking, .idle])
        store.refresh(now: Date().addingTimeInterval(7))
        XCTAssertEqual(store.employees.map(\.status), [.thinking, .idle, .idle])
        store.setDemo(true)
        XCTAssertEqual(store.employees.count, 6)
        store.setDemo(false)
        XCTAssertEqual(store.employees.map(\.id), ["session"])
        XCTAssertEqual(try Data(contentsOf: fixture.activityURL), original)
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

    /// 相同项目名的不同目录分别设立部门，新同事加入不会改变原来的部门与工位。
    @MainActor
    func testStableSeatAssignmentsAcrossProjectsAndStatusChanges() {
        let first = person("b", path: "/one/Client")
        let second = person("c", path: "/two/Client")
        var book = CodexOfficeSeatBook()
        book.assign([first, second])
        let firstRoom = CodexOfficeSeatBook.Room(project: first.projectPath, index: 0)
        let secondRoom = CodexOfficeSeatBook.Room(project: second.projectPath, index: 0)
        let room = book.rooms[firstRoom]
        let seat = book.seats[first.projectPath]?[first.id]
        var resting = first
        resting.status = .idle
        book.assign([person("a", path: first.projectPath), resting, second, person("d", path: "/another/project")])
        XCTAssertEqual(book.rooms[firstRoom], room)
        XCTAssertEqual(book.seats[first.projectPath]?[first.id], seat)
        XCTAssertNotEqual(book.rooms[firstRoom], book.rooms[secondRoom])
        let replacement = person("replacement", path: first.projectPath)
        let remaining = book.seats[first.projectPath]?["a"]
        book.assign([person("a", path: first.projectPath), replacement])
        XCTAssertEqual(book.seats[first.projectPath]?[replacement.id], seat)
        XCTAssertEqual(book.seats[first.projectPath]?["a"], remaining)
        XCTAssertNil(book.seats[first.projectPath]?[first.id])
        XCTAssertNil(book.rooms[secondRoom])
    }

    /// 使用真实 SceneKit 视口回归切换数据源后的取景，演示不得继承真实公司的空楼层。
    @MainActor
    func testSceneReframesWhenSwitchingFromLiveToDemo() {
        let director = CodexOfficeScene()
        let view = OfficeCanvasView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        view.scene = director.scene
        director.view = view
        let live = (0..<24).map { person("live-\($0)", path: "/project-\($0 / 4)") }
        director.update(employees: live, selected: nil, isNight: false, paused: true, cameraRequest: 0, reduceMotion: true, isDemo: false)
        let liveScale = director.camera.camera!.orthographicScale
        let demo = (0..<2).map { person("demo-\($0)", path: "demo/project") }
        director.update(employees: demo, selected: nil, isNight: false, paused: true, cameraRequest: 1, reduceMotion: true, isDemo: true)
        let demoScale = director.camera.camera!.orthographicScale
        XCTAssertTrue(demoScale.isFinite)
        XCTAssertGreaterThan(demoScale, 0)
        XCTAssertLessThan(demoScale, liveScale)
        view.scene = nil
    }

    /// 首次从空场景载入真实会话必须重取全景，重复全景不能因上一帧缩放而越调越远。
    @MainActor
    func testSceneFramesFirstPopulationAndRepeatedOverviewIsStable() {
        let director = CodexOfficeScene()
        let view = OfficeCanvasView(frame: NSRect(x: 0, y: 0, width: 1080, height: 540))
        view.scene = director.scene
        director.view = view
        director.update(employees: [], selected: nil, isNight: false, paused: true, cameraRequest: 0, reduceMotion: true, isDemo: false)
        let emptyScale = director.camera.camera!.orthographicScale
        let live = (0..<32).map { person("live-\($0)", path: "/project-\($0 / 4)") }
        director.update(employees: live, selected: nil, isNight: false, paused: true, cameraRequest: 0, reduceMotion: true, isDemo: false)
        let liveScale = director.camera.camera!.orthographicScale
        XCTAssertGreaterThan(liveScale, emptyScale)
        director.camera.camera?.orthographicScale = 5
        director.resetCamera()
        XCTAssertEqual(director.camera.camera!.orthographicScale, liveScale, accuracy: 0.0001)
        director.resetCamera()
        XCTAssertEqual(director.camera.camera!.orthographicScale, liveScale, accuracy: 0.0001)
        view.scene = nil
    }

    /// 已经离开工位又收到新状态时，必须从当前路径段继续走，经过门口才能换房间。
    func testWalkRouteKeepsDoorwayWhenRetargeting() {
        let door = CGPoint(x: 0, y: 5)
        let aisle = CGPoint(x: -1.3, y: 5)
        let desk = CGPoint(x: -5, y: 5)
        let otherDoor = CGPoint(x: 0, y: 12)
        let otherDesk = CGPoint(x: 3, y: 12)
        let current = CGPoint(x: -3, y: 5)
        let exit = [desk, aisle, door, CGPoint(x: 0, y: -1), CGPoint(x: -2, y: -1)]
        XCTAssertEqual(OfficeWalkRoute.itinerary(from: current, leaving: exit, entering: [otherDoor, otherDesk]),
                       [current, aisle, door, otherDoor, otherDesk])
        XCTAssertEqual(OfficeWalkRoute.itinerary(from: current, leaving: [door, aisle, desk], entering: [otherDoor, otherDesk]),
                       [current, aisle, door, otherDoor, otherDesk])
    }

    /// SceneKit 推进动作时人物从休息区连续行走；别人返回工位不会让仍在休息的人重新排位。
    @MainActor
    func testSceneWalksBetweenLocationsWithoutMovingRestingCoworkers() throws {
        let director = CodexOfficeScene()
        var first = person("first", path: "/project")
        var second = person("second", path: "/project")
        first.status = .idle
        second.status = .idle
        director.update(employees: [first, second], selected: nil, isNight: false, paused: false, cameraRequest: 0, reduceMotion: false, isDemo: true)
        let people = try XCTUnwrap(director.scene.rootNode.childNode(withName: "office-people", recursively: false))
        let walker = try XCTUnwrap(people.childNode(withName: "employee:first", recursively: false))
        let coworker = try XCTUnwrap(people.childNode(withName: "employee:second", recursively: false))
        let start = walker.position
        let coworkerPosition = coworker.position
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = director.scene
        renderer.pointOfView = director.camera
        renderer.isPlaying = true
        let viewport = CGSize(width: 320, height: 200)
        _ = renderer.snapshot(atTime: 1, with: viewport, antialiasingMode: .none)
        first.status = .working
        director.update(employees: [first, second], selected: nil, isNight: false, paused: false, cameraRequest: 0, reduceMotion: false, isDemo: true)
        XCTAssertEqual(walker.position.z, start.z, accuracy: 0.001)
        _ = renderer.snapshot(atTime: 1.05, with: viewport, antialiasingMode: .none)
        _ = renderer.snapshot(atTime: 1.2, with: viewport, antialiasingMode: .none)
        XCTAssertGreaterThan(walker.presentation.position.z, start.z)
        XCTAssertLessThan(walker.presentation.position.z - start.z, 1.0)
        XCTAssertEqual(coworker.position.x, coworkerPosition.x, accuracy: 0.001)
        XCTAssertEqual(coworker.position.z, coworkerPosition.z, accuracy: 0.001)
    }

    /// 验证前台座位、横竖工位的朝向和办公椅轮距。入座点要与椅心重合，脚轮须贴地且位于状态环内。
    @MainActor
    func testOfficeSeatsRestingCoworkersAtReceptionAndClustersDesks() throws {
        let director = CodexOfficeScene()
        let workers = (0..<6).map { person("worker-\($0)", path: "/project") }
        let resting = (0..<7).map { index in
            var employee = person("resting-\(index)", path: "/project")
            employee.status = .idle
            return employee
        }
        director.update(employees: workers + resting, selected: nil, isNight: false, paused: true,
                        cameraRequest: 0, reduceMotion: true, isDemo: true)

        let root = director.scene.rootNode
        let building = try XCTUnwrap(root.childNode(withName: "office-building", recursively: false))
        let reception = try XCTUnwrap(building.childNode(withName: "office-reception", recursively: true))
        let sofas = reception.childNodes.filter { $0.name == "office-sofa" }
            .sorted { $0.worldPosition.z < $1.worldPosition.z }
        XCTAssertEqual(sofas.count, 2)
        XCTAssertNotNil(reception.childNode(withName: "office-tool-room", recursively: false))
        let people = try XCTUnwrap(root.childNode(withName: "office-people", recursively: false))
        for (row, sofa) in sofas.enumerated() {
            var cushionPositions = Set<CGFloat>()
            for employee in resting.dropFirst(row * 3).prefix(3) {
                let actor = try XCTUnwrap(people.childNode(withName: "employee:" + employee.id, recursively: false))
                let seat = sofa.convertPosition(actor.worldPosition, from: nil)
                XCTAssertEqual(seat.z, 0, accuracy: 0.001)
                XCTAssertLessThan(abs(seat.x), 1.8)
                XCTAssertTrue(cushionPositions.insert(seat.x).inserted)
                XCTAssertEqual(simd_dot(actor.simdWorldFront, sofa.simdWorldFront), 1, accuracy: 0.001)
            }
        }
        let overflow = try XCTUnwrap(people.childNode(withName: "employee:resting-6", recursively: false))
        XCTAssertLessThan(overflow.worldPosition.z, OfficeBuilding.entrance.y)

        let room = try XCTUnwrap(building.childNode(withName: "office-room", recursively: false))
        let desks = try workers.map {
            try XCTUnwrap(room.childNode(withName: "employee:" + $0.id, recursively: false))
        }
        for (first, second) in [(0, 2), (3, 4)] {
            XCTAssertEqual(desks[first].position.x, desks[second].position.x, accuracy: 0.001)
            XCTAssertGreaterThan(abs(desks[first].position.z - desks[second].position.z), 1)
            XCTAssertLessThan(abs(desks[first].position.z - desks[second].position.z), 1.2)
            XCTAssertEqual(simd_dot(desks[first].simdWorldFront, desks[second].simdWorldFront), -1, accuracy: 0.001)
        }
        for index in [1, 5] {
            XCTAssertEqual(simd_dot(desks[0].simdWorldFront, desks[index].simdWorldFront), 0, accuracy: 0.001)
            XCTAssertLessThan(desks[index].position.x, desks[0].position.x)
        }
        let rug = try XCTUnwrap(room.childNode(withName: "office-room-rug", recursively: false))
        let rugTop = rug.worldPosition.y + (try XCTUnwrap(rug.geometry as? SCNBox)).height / 2
        for (employee, desk) in zip(workers, desks) {
            let actor = try XCTUnwrap(people.childNode(withName: "employee:" + employee.id, recursively: false))
            let chair = try XCTUnwrap(desk.childNode(withName: "office-task-chair", recursively: false))
            XCTAssertEqual(chair.worldPosition.x, actor.worldPosition.x, accuracy: 0.001)
            XCTAssertEqual(chair.worldPosition.z, actor.worldPosition.z, accuracy: 0.001)
            let casters = chair.childNodes.flatMap(\.childNodes).filter { $0.name == "office-chair-caster" }
            XCTAssertEqual(casters.count, 5)
            for caster in casters {
                let wheel = try XCTUnwrap(caster.geometry as? SCNCylinder)
                let position = chair.convertPosition(caster.worldPosition, from: nil)
                XCTAssertEqual(caster.worldPosition.y - wheel.radius, rugTop, accuracy: 0.003)
                XCTAssertLessThan(hypot(position.x, position.z) + wheel.radius, 0.42)
            }
            let towardsDesk = simd_normalize(desk.simdWorldPosition - actor.simdWorldPosition)
            XCTAssertEqual(simd_dot(-actor.simdWorldFront, towardsDesk), 1, accuracy: 0.001)
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

    /// 低人数时始终有两间房，只为在岗的人摆桌。换主题不能影响取景和沙发位置。
    @MainActor
    func testOfficeBuildsOnlyOccupiedDesksAndChangesThemeInPlace() throws {
        let director = CodexOfficeScene()
        let canvas = OfficeCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))
        canvas.scene = director.scene
        director.view = canvas
        var worker = person("worker", path: "/working")
        var resting = person("resting", path: "/break")
        resting.status = .idle
        let history = (0..<20).map { index in
            var past = person("history-\(index)", path: "/past-\(index)")
            past.isOnSite = false
            return past
        }
        director.update(employees: history + [worker, resting], selected: nil, isNight: false, paused: false, cameraRequest: 0, reduceMotion: true, isDemo: false)
        let building = try XCTUnwrap(director.scene.rootNode.childNode(withName: "office-building", recursively: false))
        let people = try XCTUnwrap(director.scene.rootNode.childNode(withName: "office-people", recursively: false))
        XCTAssertEqual(building.childNodes.filter { $0.name == "office-room" }.count, 2)
        XCTAssertNotNil(building.childNode(withName: "employee:worker", recursively: true))
        XCTAssertNil(building.childNode(withName: "employee:resting", recursively: true))
        XCTAssertEqual(people.childNodes.count, 2)
        let rest = try XCTUnwrap(people.childNode(withName: "employee:resting", recursively: false))
        let place = rest.simdWorldPosition
        let fit = try XCTUnwrap(director.camera.camera).orthographicScale
        let light = director.scene.background.contents as? NSColor
        director.update(employees: history + [worker, resting], selected: nil, isNight: true, paused: false, cameraRequest: 0, reduceMotion: true, isDemo: false)
        XCTAssertNotEqual(director.scene.background.contents as? NSColor, light)
        XCTAssertEqual(rest.simdWorldPosition, place)
        XCTAssertEqual(director.camera.camera?.orthographicScale, fit)

        worker.isOnSite = false
        director.update(employees: history + [worker, resting], selected: nil, isNight: true, paused: false, cameraRequest: 0, reduceMotion: true, isDemo: false)
        XCTAssertEqual(building.childNodes.filter { $0.name == "office-room" }.count, 2)
        XCTAssertNil(building.childNode(withName: "employee:worker", recursively: true))
        XCTAssertEqual(people.childNodes.count, 1)
        XCTAssertEqual(rest.simdWorldPosition, place)
        XCTAssertEqual(try XCTUnwrap(director.camera.camera).orthographicScale, fit, accuracy: 0.0001)
    }

    /// 空岛仍有布景，实际会话按状态进入工位和长椅。切换外观时保持位置、镜头和暂停状态。
    @MainActor
    func testIslandSeatsOnSiteSessionsAndKeepsFramingAcrossAppearance() throws {
        let director = CodexOfficeScene(isIsland: true)
        let canvas = OfficeCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))
        canvas.scene = director.scene
        director.view = canvas
        director.update(employees: [], selected: nil, isNight: false, paused: false, cameraRequest: 0, reduceMotion: true, isDemo: false)
        let building = try XCTUnwrap(director.scene.rootNode.childNode(withName: "office-building", recursively: false))
        let people = try XCTUnwrap(director.scene.rootNode.childNode(withName: "office-people", recursively: false))
        let sails = try XCTUnwrap(building.childNode(withName: "island-windmill-sails", recursively: true))
        XCTAssertNotNil(sails.action(forKey: "island-breeze"))
        let water = try XCTUnwrap(building.childNode(withName: "island-water", recursively: true))
        XCTAssertNotNil(water.action(forKey: "island-current"))
        XCTAssertNil(building.childNode(withName: "island-workstation", recursively: true))
        XCTAssertTrue(people.childNodes.isEmpty)
        XCTAssertFalse(canvas.isPlaying)
        XCTAssertTrue(director.scene.isPaused)
        XCTAssertEqual(canvas.preferredFramesPerSecond, 60)

        let worker = person("island-worker", path: "/working")
        var resting = person("island-resting", path: "/break")
        resting.status = .idle
        var history = person("island-history", path: "/past")
        history.isOnSite = false
        director.update(employees: [worker, resting, history], selected: nil, isNight: false, paused: false,
                        cameraRequest: 0, reduceMotion: true, isDemo: false)
        XCTAssertEqual(building.childNodes.filter { $0.name?.hasPrefix("employee:") == true }.count, 1)
        XCTAssertEqual(people.childNodes.count, 2)
        let rest = try XCTUnwrap(people.childNode(withName: "employee:island-resting", recursively: false))
        let place = rest.simdWorldPosition
        let bench = try XCTUnwrap(OfficeIslandLayout.restDestination(for: 0).route.last)
        XCTAssertEqual(place.x, Float(bench.x), accuracy: 0.001)
        XCTAssertEqual(place.z, Float(bench.y), accuracy: 0.001)
        let fit = try XCTUnwrap(director.camera.camera?.orthographicScale)
        let day = director.scene.background.contents as? NSColor
        director.update(employees: [worker, resting, history], selected: nil, isNight: true, paused: false,
                        cameraRequest: 0, reduceMotion: true, isDemo: false)
        XCTAssertNotEqual(director.scene.background.contents as? NSColor, day)
        XCTAssertEqual(rest.simdWorldPosition, place)
        XCTAssertEqual(director.camera.camera?.orthographicScale, fit)
        XCTAssertEqual(CodexOfficeSceneStyle(rawValue: "island"), .island)

        var another = person("island-sitting", path: "/another")
        another.status = .idle
        director.update(employees: [worker, resting, another], selected: nil, isNight: true, paused: false,
                        cameraRequest: 0, reduceMotion: true, isDemo: false)
        let originalBadge = try XCTUnwrap(rest.childNode(withName: "island-status-badge", recursively: false))
        let second = try XCTUnwrap(people.childNode(withName: "employee:island-sitting", recursively: false))
        let raisedBadge = try XCTUnwrap(second.childNode(withName: "island-status-badge", recursively: false))
        let retainedDesk = try XCTUnwrap(building.childNode(withName: "employee:island-worker", recursively: false))
        let extraWorker = person("island-extra", path: "/new")
        director.update(employees: [worker, resting, another, extraWorker], selected: resting.id, isNight: true, paused: false,
                        cameraRequest: 0, reduceMotion: true, isDemo: false)
        XCTAssertTrue(retainedDesk === building.childNode(withName: "employee:island-worker", recursively: false))
        // 选中前排名牌后绕岛旋转，按屏幕投影的距离检查高度差。
        for yaw: CGFloat in [-.pi / 2, 0, .pi / 2, .pi] {
            director.camera.position = SCNVector3(27 * sin(yaw), 17.61, 27 * cos(yaw))
            director.camera.look(at: SCNVector3(0, 0.81, 0))
            canvas.onCameraChanged?()
            let gap = simd_dot(director.camera.simdWorldUp, raisedBadge.simdWorldPosition - originalBadge.simdWorldPosition)
            XCTAssertGreaterThan(gap, 0.62)
        }
    }

    /// 超出首间工坊后沿主路扩建，全部会话都有席位，收回空工坊后岸线恢复。
    @MainActor
    func testIslandExpandsForMoreThanSixWorkers() throws {
        let director = CodexOfficeScene(isIsland: true)
        let people = (0..<7).map { person("island-\($0)", path: "/project-\($0)") }
        director.update(employees: people, selected: nil, isNight: false, paused: true, cameraRequest: 0, reduceMotion: true, isDemo: false)
        let building = try XCTUnwrap(director.scene.rootNode.childNode(withName: "office-building", recursively: false))
        let site = try XCTUnwrap(building.childNodes.first)
        XCTAssertEqual(site.childNodes.filter { $0.name == "island-workshop" }.count, 2)
        XCTAssertEqual(building.childNodes.filter { $0.name?.hasPrefix("employee:") == true }.count, 7)
        director.update(employees: Array(people.prefix(1)), selected: nil, isNight: false, paused: true,
                        cameraRequest: 0, reduceMotion: true, isDemo: false)
        XCTAssertEqual(site.childNodes.filter { $0.name == "island-workshop" }.count, 1)
        XCTAssertEqual(building.childNodes.filter { $0.name?.hasPrefix("employee:") == true }.count, 1)
    }

    /// 对向经过主路时使用不同侧的步行点，转入工坊前仍经过原路口。
    func testIslandSpineSeparatesOpposingWalks() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 0, y: 4)
        let turning = CGPoint(x: -2, y: 4)
        let outgoing = OfficeIslandLayout.walkingLanes(on: [start, end, turning])
        let incoming = OfficeIslandLayout.walkingLanes(on: [end, start])
        XCTAssertEqual(outgoing.suffix(2), [end, turning])
        XCTAssertGreaterThan(outgoing[1].x - incoming[1].x, 0.8)
    }

    /// 大项目占用多间房时会扩建；只剩后排的两位同事时，他们的工位与楼层一起收回首排。
    @MainActor
    func testOfficeCompactsRearWorkstationsIntoTwoRooms() throws {
        let director = CodexOfficeScene()
        let view = OfficeCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))
        view.scene = director.scene
        director.view = view
        let team = (0..<13).map { person(String(format: "worker-%02d", $0), path: "/alpha") }
        let other = person("other", path: "/beta")
        let last = person("last", path: "/gamma")
        let tail = try XCTUnwrap(team.last)
        director.update(employees: team + [other, last], selected: nil, isNight: false, paused: true,
                        cameraRequest: 0, reduceMotion: true, isDemo: false)

        let building = try XCTUnwrap(director.scene.rootNode.childNode(withName: "office-building", recursively: false))
        let expandedScale = try XCTUnwrap(director.camera.camera).orthographicScale
        let rearDesk = try XCTUnwrap(building.childNode(withName: "employee:" + tail.id, recursively: true))
        let lastDesk = try XCTUnwrap(building.childNode(withName: "employee:" + last.id, recursively: true))
        let rearZ = rearDesk.worldPosition.z
        let lastZ = lastDesk.worldPosition.z
        XCTAssertEqual(building.childNodes.filter { $0.name == "office-room" }.count, 5)

        director.update(employees: [tail, last], selected: nil, isNight: false, paused: true,
                        cameraRequest: 0, reduceMotion: true, isDemo: false)

        XCTAssertEqual(building.childNodes.filter { $0.name == "office-room" }.count, 2)
        XCTAssertLessThan(try XCTUnwrap(director.camera.camera).orthographicScale, expandedScale)
        XCTAssertLessThan(try XCTUnwrap(building.childNode(withName: "employee:" + tail.id, recursively: true)).worldPosition.z, rearZ)
        XCTAssertLessThan(try XCTUnwrap(building.childNode(withName: "employee:" + last.id, recursively: true)).worldPosition.z, lastZ)
        XCTAssertNil(building.childNode(withName: "employee:" + other.id, recursively: true))
    }

    /// 紧凑布局的后墙必须闭合，两侧外墙跨过前台接缝，工具间后面只用一道共享隔断。
    @MainActor
    func testOfficeExteriorClosesPerimeterAndSharesToolPartition() throws {
        let director = CodexOfficeScene()
        director.update(employees: [], selected: nil, isNight: true, paused: true,
                        cameraRequest: 0, reduceMotion: true, isDemo: false)
        let building = try XCTUnwrap(director.scene.rootNode.childNode(withName: "office-building", recursively: false))
        let facade = try XCTUnwrap(building.childNode(withName: "office-facade", recursively: true))
        let exteriorSills = facade.childNodes.filter { $0.name == "office-wall-sill" }
        let rear = try XCTUnwrap(exteriorSills.first { ($0.geometry as? SCNBox)?.width ?? 0 > 19 })
        let rearShape = try XCTUnwrap(rear.geometry as? SCNBox)
        let sides = exteriorSills.filter { ($0.geometry as? SCNBox)?.length ?? 0 > 15 }
        XCTAssertEqual(sides.count, 2)
        for side in sides {
            let shape = try XCTUnwrap(side.geometry as? SCNBox)
            XCTAssertLessThan(side.position.z - shape.length / 2, OfficeBuilding.firstRoomStart)
            XCTAssertEqual(side.position.z + shape.length / 2, rear.position.z + rearShape.length / 2, accuracy: 0.001)
            XCTAssertEqual(abs(side.position.x) - shape.width / 2, rearShape.width / 2, accuracy: 0.001)
        }

        let lobbyDividers = building.childNodes.filter {
            $0.name == "office-wall-sill" && abs($0.position.z - OfficeBuilding.firstRoomStart) < 0.001
        }
        XCTAssertEqual(lobbyDividers.count, 2)
        let toolRoom = try XCTUnwrap(building.childNode(withName: "office-tool-room", recursively: true))
        let crossWalls = toolRoom.childNodes.filter {
            guard $0.name == "office-wall-sill", let shape = $0.geometry as? SCNBox else { return false }
            return shape.width > shape.length
        }
        XCTAssertEqual(crossWalls.count, 1)
    }

    /// 聚焦扩建后的首排时，地台仍须完整落在近远裁剪面内。近景只淡出前方窗框，复位后恢复外墙。
    @MainActor
    func testOfficeCloseUpKeepsYardInsideClipPlanes() throws {
        let director = CodexOfficeScene()
        let canvas = OfficeCanvasView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))
        canvas.scene = director.scene
        director.view = canvas
        let employees = (0..<6).map { person("worker-\($0)", path: "/project-\($0)") }
        director.update(employees: employees, selected: nil, isNight: false, paused: true,
                        cameraRequest: 0, reduceMotion: true, isDemo: false)
        let facade = try XCTUnwrap(director.scene.rootNode.childNode(withName: "office-facade", recursively: true))
        let panels = facade.childNodes.filter { $0.name == "office-facade-upper" }
        let bases = facade.childNodes.filter { $0.name == "office-wall-sill" }
        XCTAssertEqual(panels.count, 4)
        XCTAssertTrue(panels.allSatisfy { $0.opacity == 1 })

        director.update(employees: employees, selected: employees[0].id, isNight: false, paused: true,
                        cameraRequest: 0, reduceMotion: true, isDemo: false)
        let camera = director.camera
        let lens = try XCTUnwrap(camera.camera)
        XCTAssertLessThan(lens.orthographicScale, canvas.overviewScale)
        let yard = try XCTUnwrap(director.scene.rootNode.childNode(withName: "office-garden", recursively: true))
        let bounds = yard.boundingBox
        for x in [bounds.min.x, bounds.max.x] {
            for y in [bounds.min.y, bounds.max.y] {
                for z in [bounds.min.z, bounds.max.z] {
                    let corner = yard.convertPosition(SCNVector3(x, y, z), to: nil)
                    let distance = simd_dot(SIMD3<Float>(corner) - camera.simdWorldPosition, camera.simdWorldFront)
                    XCTAssertGreaterThan(Double(distance), lens.zNear)
                    XCTAssertLessThan(Double(distance), lens.zFar)
                }
            }
        }
        XCTAssertEqual(panels.filter { $0.opacity < 0.5 }.count, 2)
        XCTAssertTrue(bases.allSatisfy { $0.opacity == 1 })
        director.resetCamera()
        XCTAssertTrue(panels.allSatisfy { $0.opacity == 1 })
    }

    /// 模拟 AppKit 的机械滚轮输入，验证视野缩放且镜头不发生平移。
    @MainActor
    func testOfficeWheelZoomChangesOnlyOrthographicScale() throws {
        let director = CodexOfficeScene()
        let canvas = OfficeCanvasView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        canvas.scene = director.scene
        director.view = canvas
        director.resetCamera()
        let camera = try XCTUnwrap(director.camera.camera)
        let start = director.camera.position
        let scale = camera.orthographicScale
        let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0))
        wheel.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 3)
        wheel.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 3)
        wheel.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 3)
        let event = try XCTUnwrap(NSEvent(cgEvent: wheel))
        XCTAssertGreaterThan(event.scrollingDeltaY, 0)
        canvas.scrollWheel(with: event)
        XCTAssertLessThan(camera.orthographicScale, scale)
        XCTAssertEqual(director.camera.position.x, start.x, accuracy: 0.001)
        XCTAssertEqual(director.camera.position.y, start.y, accuracy: 0.001)
        XCTAssertEqual(director.camera.position.z, start.z, accuracy: 0.001)
    }

    /// 使用真实画布验证平移、旋转和单击。多次右键斜拖保持固定俯角、缩放和竖直方向。
    @MainActor
    func testOfficeMouseButtonsPanOrbitAndSelectIndependently() throws {
        let director = CodexOfficeScene()
        let canvas = OfficeCanvasView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        canvas.scene = director.scene
        director.view = canvas
        director.resetCamera()
        var clicks: [CGPoint] = []
        canvas.onClick = { clicks.append($0) }
        let camera = director.camera
        let lens = try XCTUnwrap(camera.camera)
        let start = camera.simdWorldPosition
        let forward = camera.simdWorldFront
        let zoom = lens.orthographicScale
        let pivot = canvas.orbitTarget

        /// 创建画布本地的鼠标事件，测试不向系统发送输入。
        func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [],
                                            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                            clickCount: 1, pressure: 1))
        }

        canvas.mouseDown(with: try mouse(.leftMouseDown, 240, 180))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, 290, 200))
        canvas.mouseUp(with: try mouse(.leftMouseUp, 290, 200))
        let panned = camera.simdWorldPosition
        let movedPivot = canvas.orbitTarget
        XCTAssertGreaterThan(simd_distance(panned, start), 1)
        XCTAssertEqual(simd_distance(camera.simdWorldFront, forward), 0, accuracy: 0.0001)
        XCTAssertEqual(simd_distance(panned - start, movedPivot - pivot), 0, accuracy: 0.0001)

        canvas.rightMouseDown(with: try mouse(.rightMouseDown, 240, 180))
        canvas.rightMouseDragged(with: try mouse(.rightMouseDragged, 290, 200))
        XCTAssertGreaterThan(simd_distance(camera.simdWorldFront, forward), 0.01)
        let beforeVerticalDrag = camera.simdWorldPosition
        canvas.rightMouseDragged(with: try mouse(.rightMouseDragged, 290, 390))
        XCTAssertEqual(simd_distance(camera.simdWorldPosition, beforeVerticalDrag), 0, accuracy: 0.0001)
        for (x, y): (CGFloat, CGFloat) in [(360, 270), (500, 80), (720, 390), (970, 160)] {
            canvas.rightMouseDragged(with: try mouse(.rightMouseDragged, x, y))
            XCTAssertEqual(camera.simdWorldFront.y, forward.y, accuracy: 0.0001)
            XCTAssertEqual(camera.simdWorldRight.y, 0, accuracy: 0.0001)
        }
        canvas.rightMouseUp(with: try mouse(.rightMouseUp, 970, 160))
        XCTAssertEqual(canvas.orbitTarget, movedPivot)
        XCTAssertEqual(simd_distance(camera.simdWorldPosition, movedPivot), simd_distance(panned, movedPivot), accuracy: 0.001)
        XCTAssertEqual(lens.orthographicScale, zoom)
        director.resetCamera()
        XCTAssertEqual(camera.simdWorldRight.y, 0, accuracy: 0.0001)
        XCTAssertTrue(clicks.isEmpty)

        canvas.mouseDown(with: try mouse(.leftMouseDown, 240, 180))
        canvas.mouseUp(with: try mouse(.leftMouseUp, 240, 180))
        XCTAssertEqual(clicks.count, 1)
    }

    /// 邮局满员时可定位名册中的会话，其他在场人员保留工位和各自的造型。
    func testPixelPostOfficePrioritizesSelectedWithoutMovingOtherActors() throws {
        var people = (0..<10).map { person("staff-\($0)", path: "/project") }
        people[0].status = .waiting
        people[9].isOnSite = false
        let first = OfficeIllustratedLayout(employees: people, selected: nil)
        XCTAssertEqual(first.actors.count, OfficeIllustratedLayout.capacity)
        XCTAssertEqual(Set(first.postOfficeAppearances.values).count, first.actors.count)
        XCTAssertNil(first.slots[people[8].id])
        XCTAssertNil(first.slots[people[9].id])
        let second = OfficeIllustratedLayout(employees: people, selected: people[8].id, previousSlots: first.slots,
                                             previousPostOfficeAppearances: first.postOfficeAppearances)
        XCTAssertNotNil(second.slots[people[8].id])
        XCTAssertEqual(first.slots[people[0].id], second.slots[people[0].id])
        XCTAssertEqual(Set(second.postOfficeAppearances.values).count, second.actors.count)
        for (id, appearance) in first.postOfficeAppearances where second.slots[id] != nil {
            XCTAssertEqual(second.postOfficeAppearances[id], appearance)
        }

        let before = try XCTUnwrap(second.actors.first { $0.employee.id == people[0].id })
        people[0].status = .idle
        let third = OfficeIllustratedLayout(employees: people, selected: people[0].id, previousSlots: second.slots,
                                            previousPostOfficeAppearances: second.postOfficeAppearances)
        let after = try XCTUnwrap(third.actors.first { $0.employee.id == people[0].id })
        XCTAssertEqual(before.slot, after.slot)
        XCTAssertEqual(third.postOfficeAppearances[people[0].id], second.postOfficeAppearances[people[0].id])
        XCTAssertNotEqual(before.point, after.point)
        let route = OfficeIllustratedLayout.walk(from: before.point, to: after.point)
        XCTAssertEqual(route.sample(0).point, before.point)
        XCTAssertEqual(route.sample(1).point.x, after.point.x, accuracy: 0.001)
        XCTAssertEqual(route.sample(1).point.y, after.point.y, accuracy: 0.001)
        let doorway = (0...200).map { route.sample(CGFloat($0) / 200).point }.filter { abs($0.x - 753) < 7 }
        XCTAssertFalse(doorway.isEmpty)
        XCTAssertTrue(doorway.allSatisfy { (332...360).contains($0.y) })
    }

    /// 满员时逐一往返茶水间，检查传送带、桌椅、正门台阶及停着的同事。
    func testPixelPostOfficeWalksPastFurnitureAndStationaryActors() throws {
        var people = (0..<8).map { person("staff-\($0)", path: "/post") }
        let working = OfficeIllustratedLayout(employees: people, selected: nil)
        for index in people.indices { people[index].status = .idle }
        let resting = OfficeIllustratedLayout(employees: people, selected: nil, previousSlots: working.slots)
        let work = working.actors.map(\.point)
        let tea = resting.actors.map(\.point)
        let furniture = [
            CGRect(x: 291, y: 290, width: 170, height: 44),
            CGRect(x: 425, y: 374, width: 140, height: 19),
            CGRect(x: 813, y: 282, width: 53, height: 68),
            CGRect(x: 894, y: 244, width: 59, height: 122)
        ]
        for pattern in [0, 0b01010101, 0b10101010, 0b11111111] {
            for slot in work.indices {
                let occupied = work.indices.filter { $0 != slot }.map { pattern & (1 << $0) == 0 ? work[$0] : tea[$0] }
                for (from, to) in [(work[slot], tea[slot]), (tea[slot], work[slot])] {
                    let route = OfficeIllustratedLayout.walk(from: from, to: to, avoiding: occupied)
                    XCTAssertEqual(route.sample(1).point.x, to.x, accuracy: 0.01)
                    XCTAssertEqual(route.sample(1).point.y, to.y, accuracy: 0.01)
                    let samples = (0...180).map { route.sample(CGFloat($0) / 180).point }
                    XCTAssertTrue(samples.contains { (742...761).contains($0.x) && (332...360).contains($0.y) })
                    XCTAssertFalse(samples.contains { point in furniture.contains { $0.contains(point) } })
                    XCTAssertFalse(samples.contains { point in
                        occupied.contains { abs($0.x - point.x) < 33 && abs($0.y - point.y) < 25 }
                    })
                }
            }
        }
    }

    /// 八人同时在场时，两个相向的人都能穿过茶水间门洞并踩完四帧步态。
    @MainActor
    func testPixelPostOfficeOpposingWalksKeepBodyClearance() throws {
        let people = (0..<8).map { person("clerk-\($0)", path: "/post") }
        let original = OfficeIllustratedLayout(employees: people, selected: nil)
        let canvas = OfficeIllustratedCanvas(frame: CGRect(origin: .zero, size: OfficeIllustratedLayout.size))
        let clock = Date(timeIntervalSinceReferenceDate: 1000)

        /// 复用画布的状态更新入口，以可控时钟推进换岗。
        func scene(_ employees: [CodexOfficeEmployee]) -> CodexOfficeIllustratedScene {
            CodexOfficeIllustratedScene(employees: employees, selected: nil,
                                        night: false, animated: true, isDemo: true, action: nil, onSelect: { _ in })
        }

        canvas.apply(scene(people), now: clock)
        var before = people
        before[7].status = .idle
        canvas.apply(scene(before), now: clock.addingTimeInterval(1))
        canvas.apply(scene(before), now: clock.addingTimeInterval(8))
        var after = people
        after[3].status = .idle
        let next = scene(after)
        let layout = OfficeIllustratedLayout(employees: after, selected: nil, previousSlots: original.slots)
        let travelers = try [3, 7].map { index in
            try XCTUnwrap(layout.actors.first { $0.employee.id == people[index].id })
        }
        let departure = clock.addingTimeInterval(10)
        var steps = [Set<Int>(), Set<Int>()]
        var collisions = [Int]()
        for tick in 0...600 {
            let time = departure.addingTimeInterval(Double(tick) / 60)
            if tick.isMultiple(of: 6) { canvas.apply(next, now: time) }
            let poses = travelers.map { canvas.pose(for: $0, now: time) }
            let dx = abs(poses[0].point.x - poses[1].point.x)
            let dy = abs(poses[0].point.y - poses[1].point.y)
            if dx < 31 && dy < 23 { collisions.append(tick) }
            for (index, pose) in poses.enumerated() where pose.walking { steps[index].insert(pose.frame) }
        }
        XCTAssertTrue(collisions.isEmpty, "相向行走时人物在这些帧叠到一起：\(collisions)")
        XCTAssertEqual(steps, [Set(2...5), Set(2...5)])
        for actor in travelers {
            let pose = canvas.pose(for: actor, now: departure.addingTimeInterval(10))
            XCTAssertFalse(pose.walking)
            XCTAssertEqual(pose.point.x, actor.point.x, accuracy: 0.01)
            XCTAssertEqual(pose.point.y, actor.point.y, accuracy: 3.01)
        }
    }

    /// 固定地图在窄窗和宽窗完整适配，使用同一坐标命中人物，拖动也不会误选。
    @MainActor
    func testPixelPostOfficeFitsViewportAndSelectsWithoutDragging() throws {
        let employee = person("actor", path: "/work")
        let map = OfficeIllustratedLayout(employees: [employee], selected: nil)
        let actor = try XCTUnwrap(map.actors.first)
        for viewport in [CGSize(width: 550, height: 310), CGSize(width: 1000, height: 350)] {
            let bounds = CGRect(origin: .zero, size: viewport)
            let canvas = OfficeIllustratedCanvas(frame: bounds)
            var sessions: [String?] = []
            canvas.apply(CodexOfficeIllustratedScene(employees: [employee], selected: nil,
                                                     night: false, animated: false, isDemo: false, action: nil,
                                                     onSelect: { sessions.append($0) }))
            let frame = OfficeIllustratedLayout.mapFrame(in: bounds)
            let scene = OfficeIllustratedLayout.size
            XCTAssertEqual(frame.width / frame.height, scene.width / scene.height, accuracy: 0.001)
            XCTAssertLessThanOrEqual(frame.width, bounds.width + 0.001)
            XCTAssertLessThanOrEqual(frame.height, bounds.height + 0.001)

            /// 发送视图局部事件，避免向系统窗口注入输入。
            func mouse(_ kind: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: kind, location: canvas.convert(point, to: nil),
                                                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                                eventNumber: 0, clickCount: 1, pressure: 1))
            }

            let actorCenter = CGPoint(x: frame.minX + actor.point.x * frame.width / scene.width,
                                      y: frame.minY + (actor.point.y - 30) * frame.height / scene.height)
            canvas.mouseDown(with: try mouse(.leftMouseDown, actorCenter))
            let dragEnd = CGPoint(x: actorCenter.x + 60, y: actorCenter.y + 20)
            canvas.mouseUp(with: try mouse(.leftMouseUp, dragEnd))
            XCTAssertTrue(sessions.isEmpty)
            canvas.mouseDown(with: try mouse(.leftMouseDown, actorCenter))
            canvas.mouseUp(with: try mouse(.leftMouseUp, actorCenter))
            XCTAssertEqual(sessions, [employee.id])
        }
    }

    /// 没有新事件时，理信和环顾仍随时间变化；暂停和减少动态效果时两者稳定。
    func testPixelPostOfficeAnimatesUnchangedSessionsAndRespectsPause() throws {
        let sorting = person("first", path: "/work")
        var thinking = person("second", path: "/work")
        thinking.status = .thinking
        let layout = OfficeIllustratedLayout(employees: [sorting, thinking], selected: nil)
        let clerk = try XCTUnwrap(layout.actors.first { $0.employee.id == sorting.id })
        let thinker = try XCTUnwrap(layout.actors.first { $0.employee.id == thinking.id })
        XCTAssertNotEqual(clerk.pose(at: 0.2, animated: true).frame, clerk.pose(at: 1.4, animated: true).frame)
        XCTAssertFalse(thinker.pose(at: 0.2, animated: true).walking)
        XCTAssertNotEqual(thinker.pose(at: 0.2, animated: true), thinker.pose(at: 1.4, animated: true))
        for actor in layout.actors {
            XCTAssertEqual(actor.pose(at: 0.2, animated: false), actor.pose(at: 1.4, animated: false))
            XCTAssertEqual(actor.pose(at: 0.2, animated: false).point, actor.point)
        }
    }

    /// 使用 Hook 和日志校正产生真实事件结构，验证旧事件、暂停积压和重复更新都不会触发飞行。
    @MainActor
    func testToolTrafficUsesOnlyNewHookAndTranscriptEvents() throws {
        let fixture = try OfficeFixture()
        defer { fixture.clean() }
        let store = fixture.store()
        var traffic = OfficeToolTraffic()
        try fixture.record("UserPromptSubmit", seconds: 0)
        try fixture.record("PreToolUse", call: "first", seconds: 0.25)
        let baseline = fixture.now.addingTimeInterval(0.5)
        store.refresh(now: baseline)
        XCTAssertTrue(traffic.observe(store.employees, now: baseline, animated: true).isEmpty)
        try fixture.record("PreToolUse", call: "second", seconds: 1)
        let requestTime = fixture.now.addingTimeInterval(1.1)
        store.refresh(now: requestTime)
        let outbound = traffic.observe(store.employees, now: requestTime, animated: true)
        XCTAssertEqual(outbound.map(\.employeeID), ["session"])
        XCTAssertEqual(outbound.map(\.returning), [false])
        XCTAssertTrue(traffic.observe(store.employees, now: requestTime, animated: true).isEmpty)

        try fixture.appendReturn("second", seconds: 2)
        let returnedAt = fixture.now.addingTimeInterval(2.1)
        store.refresh(now: returnedAt)
        let inbound = traffic.observe(store.employees, now: returnedAt, animated: true)
        XCTAssertEqual(inbound.map(\.returning), [true])
        XCTAssertEqual(inbound.map(\.failed), [false])
        try fixture.record("PostToolUse", call: "first", seconds: 3)
        let pausedAt = fixture.now.addingTimeInterval(3.1)
        store.refresh(now: pausedAt)
        XCTAssertTrue(traffic.observe(store.employees, now: pausedAt, animated: false).isEmpty)
        XCTAssertTrue(traffic.observe(store.employees, now: pausedAt, animated: true).isEmpty)
    }

    /// 场景布局测试只需要明确的身份与项目，不读取用户机器上的真实会话。
    private func person(_ id: String, path: String) -> CodexOfficeEmployee {
        CodexOfficeEmployee(id: id, projectPath: path, project: "Client", name: id, task: "test", status: .working, tool: nil, updatedAt: Date(), signalExpired: false, isDemo: true)
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
