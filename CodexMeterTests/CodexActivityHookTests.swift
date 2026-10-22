// 验证全局 Hook 配置合并、原生事件写入和新旧活动目录兼容，全部使用临时目录。
import CodexMeterShared
import XCTest

/// 覆盖安装器与事件处理的真实文件边界，防止配置损坏和并发会话状态丢失。
final class CodexActivityHookTests: XCTestCase {
    /// 安装必须保留其他 Hook 与分组属性，修复旧条目且重复安装不累积。
    func testInstallationPreservesOtherHooksAndBacksUpOriginal() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("hooks.json")
        let legacy = "/usr/bin/python3 \"\(directory.path)/hooks/codex_usage_activity.py\""
        let original = try JSONSerialization.data(withJSONObject: [
            "description": "用户配置",
            "hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [
                ["type": "command", "command": "echo keep"],
                ["type": "command", "command": legacy]
            ]]]]
        ])
        try original.write(to: url)
        let executable = try makeExecutable(in: directory)
        try CodexActivityHookInstaller.install(at: url, executableURL: executable)
        let installed = try Data(contentsOf: url)
        try CodexActivityHookInstaller.install(at: url, executableURL: executable)
        XCTAssertEqual(try Data(contentsOf: url), installed)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("codexmeter-backup")), original)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: installed) as? [String: Any])
        XCTAssertEqual(document["description"] as? String, "用户配置")
        let hooks = try XCTUnwrap(document["hooks"] as? [String: [[String: Any]]])
        let groups = try XCTUnwrap(hooks["PreToolUse"])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0]["matcher"] as? String, "Bash")
        let retained = try XCTUnwrap(groups[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(retained[0]["command"] as? String, "echo keep")
        XCTAssertEqual(hooks.count, CodexActivityHook.events.count)
        for event in CodexActivityHook.events {
            let handlers = try XCTUnwrap(hooks[event]?.last?["hooks"] as? [[String: Any]])
            XCTAssertEqual(handlers.first?["statusMessage"] as? String, "CodexMeter 活动指示 · \(event)")
        }
    }

    /// 只有当前 App 的全部事件都配置为全局匹配时才算安装完成，残缺配置仍需安装。
    func testInstallationDetectionRequiresCompleteConfigurationForCurrentApplication() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("hooks.json")
        let executable = try makeExecutable(in: directory)
        XCTAssertFalse(CodexActivityHookInstaller.isInstalled(at: url, executableURL: executable))
        try CodexActivityHookInstaller.install(at: url, executableURL: executable)
        XCTAssertTrue(CodexActivityHookInstaller.isInstalled(at: url, executableURL: executable))
        XCTAssertFalse(CodexActivityHookInstaller.isInstalled(at: url, executableURL: directory.appendingPathComponent("missing")))
        let other = try makeExecutable(in: directory.appendingPathComponent("Other.app"))
        XCTAssertFalse(CodexActivityHookInstaller.isInstalled(at: url, executableURL: other))
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var hooks = try XCTUnwrap(document["hooks"] as? [String: [[String: Any]]])
        var groups = try XCTUnwrap(hooks["PreToolUse"])
        groups[0]["matcher"] = "Bash"
        hooks["PreToolUse"] = groups
        document["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: document).write(to: url)
        XCTAssertFalse(CodexActivityHookInstaller.isInstalled(at: url, executableURL: executable))
        try CodexActivityHookInstaller.install(at: url, executableURL: executable)
        XCTAssertTrue(CodexActivityHookInstaller.isInstalled(at: url, executableURL: executable))
        hooks.removeValue(forKey: "Stop")
        document["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: document).write(to: url)
        XCTAssertFalse(CodexActivityHookInstaller.isInstalled(at: url, executableURL: executable))
        try Data("{".utf8).write(to: url)
        XCTAssertFalse(CodexActivityHookInstaller.isInstalled(at: url, executableURL: executable))
    }

    /// “无”必须压过旧版开启标志，已保存的其他样式则保留；读取默认值不会安装 Hook。
    func testActivityStyleNoneAndStoredStyles() throws {
        XCTAssertEqual(HookActivityIndicatorStyle.allCases.first, HookActivityIndicatorStyle.none)
        XCTAssertFalse(MenuBarDisplaySettings(hookActivityIndicatorStyle: .none).showsHookActivityLight)
        let suiteName = "CodexMeterTests.activity-style.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        XCTAssertFalse(MenuBarDisplaySettings(defaults: defaults).showsHookActivityLight)
        defaults.set(HookActivityIndicatorStyle.signature.rawValue, forKey: MenuBarPreferenceKeys.hookActivityIndicatorStyle)
        XCTAssertTrue(MenuBarDisplaySettings(defaults: defaults).showsHookActivityLight)
        XCTAssertEqual(MenuBarDisplaySettings(defaults: defaults).hookActivityIndicatorStyle, .signature)
        defaults.set(false, forKey: MenuBarPreferenceKeys.showsHookActivityLight)
        XCTAssertFalse(MenuBarDisplaySettings(defaults: defaults).showsHookActivityLight)
        defaults.set(true, forKey: MenuBarPreferenceKeys.showsHookActivityLight)
        defaults.set(HookActivityIndicatorStyle.none.rawValue, forKey: MenuBarPreferenceKeys.hookActivityIndicatorStyle)
        XCTAssertFalse(MenuBarDisplaySettings(defaults: defaults).showsHookActivityLight)
    }

    /// 遇到损坏 JSON 或不认识的嵌套结构必须拒绝覆盖，保留用户原文件。
    func testInstallationRejectsMalformedConfiguration() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("hooks.json")
        let executable = try makeExecutable(in: directory)
        for text in ["{", "[]", "{\"hooks\":[]}", "{\"hooks\":{\"Stop\":{}}}", "{\"hooks\":{\"Stop\":[{}]}}"] {
            let data = Data(text.utf8)
            try data.write(to: url)
            XCTAssertThrowsError(try CodexActivityHookInstaller.install(at: url, executableURL: executable))
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("codexmeter-backup").path))
    }

    /// 安装路径里的空格、引号和 shell 特殊字符必须原样传给系统，不能被展开执行。
    func testInstalledCommandQuotesApplicationPath() throws {
        let directory = temporaryDirectory().appendingPathComponent("App ' $value `literal`.app")
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let executable = try makeExecutable(in: directory)
        let url = directory.appendingPathComponent("hooks.json")
        try CodexActivityHookInstaller.install(at: url, executableURL: executable)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let hooks = try XCTUnwrap(document["hooks"] as? [String: [[String: Any]]])
        let handlers = try XCTUnwrap(hooks["Stop"]?.first?["hooks"] as? [[String: Any]])
        let command = try XCTUnwrap(handlers.first?["command"] as? String)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), CodexActivityHook.argument)
    }

    /// 新回合替换同会话旧状态，其他会话保留；工具正文不会写入轻量快照。
    func testNativeEventsReplaceSessionAndPreserveOtherSessions() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.json")
        let first = try transcript(in: directory, session: "first")
        let second = try transcript(in: directory, session: "second")
        try CodexActivityHook.record(payload: payload("UserPromptSubmit", session: "first", path: first), at: url)
        try CodexActivityHook.record(payload: payload("UserPromptSubmit", session: "second", path: second), at: url)
        try CodexActivityHook.record(payload: payload("UserPromptSubmit", session: "first", turn: "new-turn", path: first), at: url)
        var failed = payload("PostToolUse", session: "first", turn: "new-turn", path: first)
        failed["tool_response"] = ["result": ["exit_code": 1]]
        failed["prompt"] = "不可写入活动文件的正文"
        try CodexActivityHook.record(payload: failed, at: url)
        var document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
        XCTAssertEqual(document.sessions.count, 2)
        XCTAssertEqual(document.sessions["first"]?.state, .failed)
        XCTAssertEqual(document.sessions["first"]?.turnID, "new-turn")
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("不可写入"))
        for value: Any in [NSNull(), false, ""] {
            var event = payload("PostToolUse", session: "first", turn: "new-turn", path: first)
            event["tool_response"] = ["error": value]
            try CodexActivityHook.record(payload: event, at: url)
            document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
            XCTAssertEqual(document.sessions["first"]?.state, .thinking)
        }
        let before = try Data(contentsOf: url)
        for event in ["SessionStart", "SubagentStart", "SubagentStop", "Unsupported"] {
            try CodexActivityHook.record(payload: payload(event, session: "first", path: first), at: url)
            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }

    /// 完成回合即使已过展示时间，也不能被同回合迟到事件重新点亮；下一回合仍可正常启动。
    func testEventStatesAndExpiration() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.json")
        let path = try transcript(in: directory, session: "session")
        let now = Date()
        let states: [(String, CodexHookActivityState)] = [
            ("UserPromptSubmit", .running), ("PreToolUse", .running), ("PermissionRequest", .waitingApproval),
            ("PostToolUse", .thinking), ("PreCompact", .compacting), ("PostCompact", .compacting), ("Stop", .completed)
        ]
        for (event, state) in states {
            try CodexActivityHook.record(payload: payload(event, path: path), at: url, now: now)
            let document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
            XCTAssertEqual(document.sessions["session"]?.state, state, event)
        }
        let completed = try Data(contentsOf: url)
        for event in ["PreToolUse", "PostToolUse", "UserPromptSubmit", "Stop"] {
            try CodexActivityHook.record(payload: payload(event, path: path), at: url, now: now.addingTimeInterval(120))
            XCTAssertEqual(try Data(contentsOf: url), completed)
        }
        try CodexActivityHook.record(payload: payload("UserPromptSubmit", turn: "new-turn", path: path), at: url, now: now.addingTimeInterval(121))
        try CodexActivityHook.record(payload: payload("Stop", path: path), at: url, now: now.addingTimeInterval(122))
        let document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
        XCTAssertEqual(document.sessions["session"]?.turnID, "new-turn")
        XCTAssertEqual(document.sessions["session"]?.state, .running)
    }

    /// 中断和会话关闭直接清空可见状态，之后到达的同回合工具事件不得恢复活动。
    @MainActor
    func testInterruptAndSessionEndClearActivityImmediately() throws {
        for event in ["Interrupt", "SessionEnd"] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("activity.json")
            let path = try transcript(in: directory, session: "session")
            try CodexActivityHook.record(payload: payload("UserPromptSubmit", path: path), at: url)
            var end = payload(event, path: path)
            if event == "SessionEnd" { end.removeValue(forKey: "turn_id") }
            try CodexActivityHook.record(payload: end, at: url)
            try CodexActivityHook.record(payload: payload("PreToolUse", path: path), at: url)
            let store = CodexHookActivityStore(activityURL: url, legacyActivityURL: nil)
            store.refresh()
            XCTAssertFalse(store.display.isVisible)
            let document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
            XCTAssertEqual(document.sessions["session"]?.eventName, event)
        }
    }

    /// 缺日志的临时会话、错误身份和子代理日志不能触发菜单栏；孤立工具事件也不能凭空启动回合。
    func testEphemeralSubagentAndOrphanEventsAreIgnored() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.json")
        let path = try transcript(in: directory, session: "session")
        let child = try transcript(in: directory, session: "child", source: ["subagent": ["thread_spawn": ["parent_thread_id": "session"]]])
        let events: [[String: Any]] = [
            ["hook_event_name": "UserPromptSubmit", "session_id": "session", "turn_id": "turn"],
            payload("UserPromptSubmit", path: directory.appendingPathComponent("missing")),
            payload("UserPromptSubmit", session: "mismatch", path: path),
            payload("UserPromptSubmit", session: "child", path: child),
            payload("PreToolUse", path: path)
        ]
        for event in events {
            try CodexActivityHook.record(payload: event, at: url)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    /// 全局 Hook 和项目桥接同时投递也不能丢失其他会话，重复提交不能覆盖回合中的等待状态。
    func testConcurrentEventsPreserveAllSessions() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.json")
        let paths = try (0..<12).map { try transcript(in: directory, session: "session-\($0)") }
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            try? CodexActivityHook.record(payload: [
                "hook_event_name": "UserPromptSubmit", "session_id": "session-\(index)",
                "turn_id": "turn", "transcript_path": paths[index].path
            ], at: url)
        }
        var document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
        XCTAssertEqual(document.sessions.count, 12)
        try CodexActivityHook.record(payload: payload("PermissionRequest", session: "session-0", path: paths[0]), at: url)
        try CodexActivityHook.record(payload: payload("UserPromptSubmit", session: "session-0", path: paths[0]), at: url)
        document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
        XCTAssertEqual(document.sessions["session-0"]?.state, .waitingApproval)
    }

    /// 身份有效的旧文件仍可合并；完成过期后不能复活另一目录里的旧运行态。
    @MainActor
    func testStoreCombinesLegacyDirectoryWithoutResurrectingOldState() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = directory.appendingPathComponent("current.json")
        let legacy = directory.appendingPathComponent("legacy.json")
        let path = try transcript(in: directory, session: "first")
        let now = Date()
        try JSONEncoder().encode(snapshot(state: .running, session: "first", now: now, path: path)).write(to: legacy)
        let store = CodexHookActivityStore(activityURL: current, legacyActivityURL: legacy)
        store.refresh(now: now)
        XCTAssertEqual(store.display.state, .running)
        XCTAssertEqual(store.display.activeSessionCount, 1)
        try JSONEncoder().encode(snapshot(state: .completed, session: "first", now: now.addingTimeInterval(1), path: path)).write(to: current)
        store.refresh(now: now.addingTimeInterval(2))
        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertEqual(store.snapshots.first?.state, .completed)
        store.refresh(now: now.addingTimeInterval(5))
        XCTAssertTrue(store.snapshots.isEmpty)
        try JSONEncoder().encode(snapshot(state: .running, session: "first", now: now, path: path)).write(to: current)
        let unidentified = CodexHookActivitySnapshot(
            state: .thinking, sessionID: "first", turnID: "turn", eventName: "PostToolUse",
            toolName: nil, message: nil, updatedAt: now.addingTimeInterval(1).timeIntervalSince1970
        )
        try JSONEncoder().encode(unidentified).write(to: legacy)
        store.refresh(now: now.addingTimeInterval(2))
        XCTAssertEqual(store.display.state, .running)
    }

    /// 半写入保留上一帧，文件删除则清除；只有有身份的持久会话能从恢复的文件中重新加载。
    @MainActor
    func testStoreRecoversAfterPartialWriteAndFileRemoval() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.json")
        let path = try transcript(in: directory, session: "first")
        let data = try JSONEncoder().encode(snapshot(state: .running, session: "first", now: Date(), path: path))
        try data.write(to: url)
        let store = CodexHookActivityStore(activityURL: url, legacyActivityURL: nil)
        store.refresh()
        try Data("{".utf8).write(to: url)
        store.refresh()
        XCTAssertEqual(store.snapshots.count, 1)
        try FileManager.default.removeItem(at: url)
        store.refresh()
        XCTAssertTrue(store.snapshots.isEmpty)
        try data.write(to: url)
        store.refresh()
        XCTAssertEqual(store.snapshots.count, 1)
        let legacy = CodexHookActivitySnapshot(state: .running, sessionID: "first", turnID: "turn", eventName: "PreToolUse", toolName: nil, message: nil, updatedAt: Date().timeIntervalSince1970)
        try JSONEncoder().encode(legacy).write(to: url)
        store.refresh()
        XCTAssertTrue(store.snapshots.isEmpty)
    }

    /// 完成 Hook 缺失时读取尾部结束事件；完成时间取真实事件时间，刷新不能让绿色不断续期。
    @MainActor
    func testTranscriptCompletionAndInterruptionOverrideStaleHook() throws {
        for event in ["task_complete", "turn_aborted"] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("activity.json")
            let path = try transcript(in: directory, session: "session")
            let now = Date()
            try CodexActivityHook.record(payload: payload("UserPromptSubmit", path: path), at: url, now: now)
            let store = CodexHookActivityStore(activityURL: url, legacyActivityURL: nil)
            store.refresh(now: now)
            XCTAssertEqual(store.display.state, .running)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let line = try JSONSerialization.data(withJSONObject: [
                "type": "event_msg", "timestamp": formatter.string(from: now.addingTimeInterval(1)),
                "payload": ["type": event, "turn_id": "turn"]
            ])
            let handle = try FileHandle(forWritingTo: path)
            try handle.seekToEnd()
            // 大工具输出不能掩盖末尾生命周期，也不能要求轮询整个日志。
            try handle.write(contentsOf: Data(("{\"output\":\"" + String(repeating: "x", count: 100_000) + "\"}\n").utf8))
            try handle.write(contentsOf: line + Data([0x0A]))
            try handle.close()
            try CodexActivityHook.record(payload: payload("PreToolUse", path: path), at: url, now: now.addingTimeInterval(2))
            store.refresh(now: now.addingTimeInterval(2))
            XCTAssertEqual(store.display.state, event == "task_complete" ? .completed : .idle)
            store.refresh(now: now.addingTimeInterval(5))
            XCTAssertFalse(store.display.isVisible)
        }
    }

    /// 颜色必须表达工作、等待、失败和完成四种独立含义，空闲无颜色且完成只显示三秒。
    func testActivityColorsAndCompletionDuration() {
        XCTAssertNil(CodexHookActivityState.idle.indicatorColorHex)
        for state: CodexHookActivityState in [.running, .thinking, .compacting] {
            XCTAssertEqual(state.indicatorColorHex, "#30D158")
        }
        XCTAssertEqual(CodexHookActivityState.waitingApproval.indicatorColorHex, "#FF9F0A")
        XCTAssertEqual(CodexHookActivityState.failed.indicatorColorHex, "#FF453A")
        XCTAssertEqual(CodexHookActivityState.completed.indicatorColorHex, "#30D158")
        XCTAssertEqual(CodexHookActivityState.completed.expirationInterval, 3)
    }

    /// 异步提问的接收回执、其他工具和回合结束都不能盖过待回复状态；长时间等待仍显示橙色。
    @MainActor
    func testAsyncQuestionsStayWaitingUntilEveryQuestionIsAnswered() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.json")
        let path = try transcript(in: directory, session: "session")
        let now = Date()
        try CodexActivityHook.record(payload: payload("UserPromptSubmit", path: path), at: url, now: now)
        var question = payload("PreToolUse", path: path)
        question["tool_name"] = "request_user_input_async"
        question["tool_use_id"] = "call_question"
        question["tool_input"] = ["questions": [["title": "不可持久化的问题一"], ["title": "不可持久化的问题二"]]]
        try CodexActivityHook.record(payload: question, at: url, now: now)
        question["hook_event_name"] = "PostToolUse"
        question["tool_response"] = "{\"accepted\":true}"
        try CodexActivityHook.record(payload: question, at: url, now: now)
        for event in ["PreToolUse", "PostToolUse", "Stop"] {
            var background = payload(event, path: path)
            background["tool_name"] = "Bash"
            background["tool_use_id"] = "background"
            try CodexActivityHook.record(payload: background, at: url, now: now)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try appendTranscript(["type": "event_msg", "timestamp": formatter.string(from: now),
                              "payload": ["type": "task_complete", "turn_id": "turn"]], to: path)
        let store = CodexHookActivityStore(activityURL: url, legacyActivityURL: nil)
        store.refresh(now: now.addingTimeInterval(120))
        XCTAssertEqual(store.display.state, .waitingApproval)
        XCTAssertEqual(store.display.state.indicatorColorHex, "#FF9F0A")
        XCTAssertEqual(store.snapshots.first?.pendingQuestionIDs?.count, 2)
        try appendQuestionReply(callID: "call_question", index: 0, to: path)
        store.refresh(now: now.addingTimeInterval(121))
        XCTAssertEqual(store.display.state, .waitingApproval)
        XCTAssertEqual(store.snapshots.first?.pendingQuestionIDs, ["call_question:1"])
        try appendQuestionReply(callID: "another_call", index: 1, to: path)
        store.refresh(now: now.addingTimeInterval(122))
        XCTAssertEqual(store.display.state, .waitingApproval)
        try appendQuestionReply(callID: "call_question", index: 1, to: path)
        store.refresh(now: now.addingTimeInterval(123))
        XCTAssertFalse(store.display.isVisible)
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("不可持久化"))
    }

    /// 同步提问收到工具结果就恢复工作；异步提问失败或未被接收也不能留下永久等待。
    func testSynchronousAndRejectedQuestionsResumeAfterTheirOwnResult() throws {
        for (tool, response): (String, Any) in [
            ("functions.request_user_input", ["answers": [:]]),
            ("request_user_input_async", ["accepted": false]),
            ("request_user_input_async", ["error": "不可持久化的失败正文"])
        ] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("activity.json")
            let path = try transcript(in: directory, session: "session")
            try CodexActivityHook.record(payload: payload("UserPromptSubmit", path: path), at: url)
            var question = payload("PreToolUse", path: path)
            question["tool_name"] = tool
            question["tool_use_id"] = "call_question"
            try CodexActivityHook.record(payload: question, at: url)
            var document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
            XCTAssertEqual(document.sessions["session"]?.state, .waitingApproval)
            question["hook_event_name"] = "PostToolUse"
            question["tool_response"] = response
            try CodexActivityHook.record(payload: question, at: url)
            document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
            XCTAssertEqual(document.sessions["session"]?.state, (response as? [String: Any])?["error"] == nil ? .thinking : .failed)
            XCTAssertNil(document.sessions["session"]?.pendingQuestionIDs)
        }
    }

    /// 等待某个工具审批时，其他并行调用即使同名也不能使橙色提前消失。
    @MainActor
    func testApprovalWaitSurvivesUnrelatedToolsAndClearsOnMatchingResult() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.json")
        let path = try transcript(in: directory, session: "session")
        let now = Date()
        try CodexActivityHook.record(payload: payload("UserPromptSubmit", path: path), at: url, now: now)
        var approval = payload("PermissionRequest", path: path)
        approval["tool_name"] = "Bash"
        approval["tool_use_id"] = "approved_call"
        try CodexActivityHook.record(payload: approval, at: url, now: now)
        for event in ["PreToolUse", "PostToolUse"] {
            var background = payload(event, path: path)
            background["tool_name"] = "Bash"
            background["tool_use_id"] = "unrelated_call"
            try CodexActivityHook.record(payload: background, at: url, now: now)
        }
        let store = CodexHookActivityStore(activityURL: url, legacyActivityURL: nil)
        store.refresh(now: now.addingTimeInterval(120))
        XCTAssertEqual(store.display.state, .waitingApproval)
        approval["hook_event_name"] = "PostToolUse"
        try CodexActivityHook.record(payload: approval, at: url, now: now.addingTimeInterval(121))
        store.refresh(now: now.addingTimeInterval(121))
        XCTAssertEqual(store.display.state, .thinking)
        XCTAssertNil(store.snapshots.first?.approvalToolName)
    }

    /// 人工回答在同一回合到达后，后续工具不再继承待回复状态；中断和新回合也会清理等待。
    @MainActor
    func testQuestionReplyAndInterruptionClearWaiting() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.json")
        let path = try transcript(in: directory, session: "session")
        try CodexActivityHook.record(payload: payload("UserPromptSubmit", path: path), at: url)
        var question = payload("PreToolUse", path: path)
        question["tool_name"] = "request_user_input_async"
        question["tool_use_id"] = "call_question"
        try CodexActivityHook.record(payload: question, at: url)
        try appendQuestionReply(callID: "call_question", index: 0, to: path)
        try CodexActivityHook.record(payload: payload("PreToolUse", path: path), at: url)
        let store = CodexHookActivityStore(activityURL: url, legacyActivityURL: nil)
        store.refresh()
        XCTAssertEqual(store.display.state, .running)
        XCTAssertNil(store.snapshots.first?.pendingQuestionIDs)
        question["tool_use_id"] = "second_question"
        try CodexActivityHook.record(payload: question, at: url)
        try CodexActivityHook.record(payload: payload("Stop", path: path), at: url)
        try CodexActivityHook.record(payload: payload("Interrupt", path: path), at: url)
        store.refresh()
        XCTAssertFalse(store.display.isVisible)
        try CodexActivityHook.record(payload: payload("UserPromptSubmit", turn: "new_turn", path: path), at: url)
        store.refresh()
        XCTAssertEqual(store.display.state, .running)
        XCTAssertNil(store.snapshots.first?.pendingQuestionIDs)
    }

    /// 写入实际 Codex 使用的异步回复结构，只以调用编号和问题索引关联。
    private func appendQuestionReply(callID: String, index: Int, to path: URL) throws {
        let key = try JSONSerialization.data(withJSONObject: ["request_user_input_async", callID, index])
        let replies = try JSONSerialization.data(withJSONObject: [["questionItemId": String(decoding: key, as: UTF8.self)]])
        try appendTranscript(["type": "response_item", "payload": [
            "type": "message", "role": "user", "content": [[
                "type": "input_text", "text": "<send_user_message_question_reply>\n" + String(decoding: replies, as: UTF8.self) + "\n</send_user_message_question_reply>"
            ]]
        ]], to: path)
    }

    /// 模拟日志的追加写入，不修改头部身份，也不接触用户真实会话。
    private func appendTranscript(_ object: [String: Any], to path: URL) throws {
        let handle = try FileHandle(forWritingTo: path)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: JSONSerialization.data(withJSONObject: object) + Data([0x0A]))
    }

    /// 为每个用例创建真实隔离目录，不接触用户配置。
    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 提供可执行替身，只验证路径和参数，不启动真实应用。
    private func makeExecutable(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("Contents/MacOS/CodexMeter")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nprintf '%s' \"$1\"\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    /// 构造最小持久日志头；source 对象用于覆盖子代理排除分支。
    private func transcript(in directory: URL, session: String, source: Any = "vscode") throws -> URL {
        let path = directory.appendingPathComponent(session + ".jsonl")
        let header = try JSONSerialization.data(withJSONObject: ["type": "session_meta", "payload": ["id": session, "source": source]])
        try (header + Data([0x0A])).write(to: path)
        return path
    }

    /// 每个生命周期都携带同一持久身份和回合 ID，不伪造正文。
    private func payload(_ event: String, session: String = "session", turn: String = "turn", path: URL) -> [String: Any] {
        ["hook_event_name": event, "session_id": session, "turn_id": turn, "transcript_path": path.path]
    }

    /// 生成有可核对身份的快照，测试新旧文件合并。
    private func snapshot(state: CodexHookActivityState, session: String, now: Date, path: URL) -> CodexHookActivitySnapshot {
        CodexHookActivitySnapshot(state: state, sessionID: session, turnID: "turn", eventName: "test", toolName: nil, message: nil, updatedAt: now.timeIntervalSince1970, transcriptPath: path.path)
    }
}
