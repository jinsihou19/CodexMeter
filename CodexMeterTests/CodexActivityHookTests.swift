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

    /// 写入器只保留离散状态；同会话新回合覆盖旧回合，其他会话和旧版单快照仍兼容。
    func testNativeEventsReplaceSessionAndPreserveOtherSessions() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.json")
        let now = Date()
        let previous = snapshot(state: .running, session: "first", now: now)
        try JSONEncoder().encode(previous).write(to: url)
        try CodexActivityHook.record(payload: ["hook_event_name": "UserPromptSubmit", "session_id": "second"], at: url, now: now)
        try CodexActivityHook.record(payload: [
            "hook_event_name": "PostToolUse", "session_id": "first", "turn_id": "new-turn",
            "tool_response": ["result": ["exit_code": 1]], "prompt": "不可写入活动文件的正文"
        ], at: url, now: now)
        var document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
        XCTAssertEqual(document.sessions.count, 2)
        XCTAssertEqual(document.sessions["first"]?.state, .failed)
        XCTAssertEqual(document.sessions["first"]?.turnID, "new-turn")
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("不可写入"))
        for value: Any in [NSNull(), false, ""] {
            try CodexActivityHook.record(payload: [
                "hook_event_name": "PostToolUse", "session_id": "first", "tool_response": ["error": value]
            ], at: url, now: now)
            document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
            XCTAssertEqual(document.sessions["first"]?.state, .thinking)
        }
        try CodexActivityHook.record(payload: ["hook_event_name": "SessionStart", "session_id": "first"], at: url, now: now)
        document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
        XCTAssertEqual(document.sessions.count, 1)
        XCTAssertNotNil(document.sessions["second"])
    }

    /// 每个受支持生命周期都必须落入正确状态，未知事件不生成假活动。
    func testEventStatesAndExpiration() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.json")
        let states: [(String, CodexHookActivityState)] = [
            ("UserPromptSubmit", .running), ("PreToolUse", .running), ("PermissionRequest", .waitingApproval),
            ("PostToolUse", .thinking), ("PreCompact", .compacting), ("PostCompact", .compacting),
            ("SubagentStart", .running), ("SubagentStop", .succeeded), ("Stop", .completed)
        ]
        for (event, state) in states {
            try CodexActivityHook.record(payload: ["hook_event_name": event, "session_id": "session"], at: url)
            let document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
            XCTAssertEqual(document.sessions["session"]?.state, state, event)
        }
        let data = try Data(contentsOf: url)
        try CodexActivityHook.record(payload: ["hook_event_name": "Unsupported"], at: url)
        XCTAssertEqual(try Data(contentsOf: url), data)
        try CodexActivityHook.record(payload: ["hook_event_name": "PreToolUse", "session_id": "later"], at: url, now: Date().addingTimeInterval(61))
        let document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
        XCTAssertEqual(document.sessions.count, 1)
    }

    /// 多个 Hook 同时写入时不得因读取后覆盖而丢失其他会话。
    func testConcurrentEventsPreserveAllSessions() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.json")
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            try? CodexActivityHook.record(payload: ["hook_event_name": "PreToolUse", "session_id": "session-\(index)"], at: url)
        }
        let document = try JSONDecoder().decode(CodexHookActivityDocument.self, from: Data(contentsOf: url))
        XCTAssertEqual(document.sessions.count, 12)
    }

    /// 旧全局脚本仍在写入时应自动恢复显示，新旧同会话只计算一次，完成过期后保持隐藏。
    @MainActor
    func testStoreCombinesLegacyDirectoryWithoutResurrectingOldState() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = directory.appendingPathComponent("current.json")
        let legacy = directory.appendingPathComponent("legacy.json")
        let now = Date()
        try JSONEncoder().encode(snapshot(state: .running, session: "first", now: now)).write(to: legacy)
        let store = CodexHookActivityStore(activityURL: current, legacyActivityURL: legacy)
        store.refresh(now: now)
        XCTAssertEqual(store.display.state, .running)
        XCTAssertEqual(store.display.activeSessionCount, 1)
        try JSONEncoder().encode(snapshot(state: .completed, session: "first", now: now.addingTimeInterval(1))).write(to: current)
        store.refresh(now: now.addingTimeInterval(2))
        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertEqual(store.snapshots.first?.state, .completed)
        store.refresh(now: now.addingTimeInterval(7))
        XCTAssertTrue(store.snapshots.isEmpty)
    }

    /// 半写入保留上一帧，文件删除则立即清除，恢复后的 JSON 应重新加载。
    @MainActor
    func testStoreRecoversAfterPartialWriteAndFileRemoval() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("activity.json")
        let data = try JSONEncoder().encode(snapshot(state: .running, session: "first", now: Date()))
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
    }

    /// 为每个用例创建真实隔离目录，不接触用户的 Codex 配置和状态。
    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 提供可执行的最小替身以验证安装路径和 shell 参数，不启动真实应用。
    private func makeExecutable(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("Contents/MacOS/CodexMeter")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nprintf '%s' \"$1\"\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    /// 生成不含会话正文的状态快照，便于测试新旧文件按更新时间合并。
    private func snapshot(state: CodexHookActivityState, session: String, now: Date) -> CodexHookActivitySnapshot {
        CodexHookActivitySnapshot(state: state, sessionID: session, turnID: "turn", eventName: "test", toolName: nil, message: nil, updatedAt: now.timeIntervalSince1970)
    }
}
