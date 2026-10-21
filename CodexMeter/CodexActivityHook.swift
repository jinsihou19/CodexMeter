// 内置 Codex 活动 Hook 与全局安装器；无需 Python、外部脚本或常驻后台服务。
import CodexMeterShared
import Darwin
import Foundation

/// 将生命周期事件写成共享快照；仅由命令行入口调用，不启动应用界面，也不保存会话正文。
enum CodexActivityHook {
    static let displayName = "CodexMeter 活动指示"
    static let argument = "--codexmeter-activity-hook"
    static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse",
        "PreCompact", "PostCompact", "SubagentStart", "SubagentStop", "Stop"
    ]

    /// 消费 stdin 的单个事件；异常保持静默，不能因状态指示失败阻塞 Codex。
    static func run() {
        guard let payload = try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile())
            as? [String: Any] else { return }
        try? record(payload: payload, at: CodexHookActivityLocation.activityURL())
        if ["Stop", "SubagentStop"].contains(payload["hook_event_name"] as? String ?? "") {
            print("{\"continue\":true}")
        }
    }

    /// 原子更新单个会话，按 TTL 清理旧状态；并发调用使用短时文件锁防止覆盖其他会话。
    static func record(payload: [String: Any], at url: URL, now: Date = Date()) throws {
        guard let event = payload["hook_event_name"] as? String, events.contains(event) else { return }
        let sessionID = payload["session_id"] as? String
        let state: CodexHookActivityState
        switch event {
        case "SessionStart": state = .idle
        case "UserPromptSubmit", "PreToolUse", "SubagentStart": state = .running
        case "PermissionRequest": state = .waitingApproval
        case "PostToolUse": state = responseFailed(payload["tool_response"]) ? .failed : .thinking
        case "PreCompact", "PostCompact": state = .compacting
        case "SubagentStop": state = .succeeded
        case "Stop": state = .completed
        default: return
        }
        let snapshot = CodexHookActivitySnapshot(
            state: state, sessionID: sessionID, turnID: payload["turn_id"] as? String,
            eventName: event, toolName: payload["tool_name"] as? String,
            message: nil, updatedAt: now.timeIntervalSince1970
        )
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { close(descriptor) }
        var locked = false
        for _ in 0..<40 {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { locked = true; break }
            usleep(5_000)
        }
        guard locked else { throw POSIXError(.EWOULDBLOCK) }
        defer { flock(descriptor, LOCK_UN) }

        let data = try? Data(contentsOf: url)
        let decoder = JSONDecoder()
        var sessions = data.flatMap { try? decoder.decode(CodexHookActivityDocument.self, from: $0).sessions } ?? [:]
        if sessions.isEmpty, let data, let previous = try? decoder.decode(CodexHookActivitySnapshot.self, from: data) {
            sessions[previous.sessionID ?? "global"] = previous
        }
        sessions = sessions.filter { _, previous in
            previous.isFresh(now: now) && previous.state != .idle && previous.sessionID != sessionID
        }
        if state != .idle { sessions[sessionID ?? "global"] = snapshot }
        try JSONEncoder().encode(CodexHookActivityDocument(sessions: sessions)).write(to: url, options: .atomic)
    }

    /// 只检查结构化失败字段，不把工具输出中的普通错误文案误判为回合失败。
    private static func responseFailed(_ response: Any?) -> Bool {
        guard let response = response as? [String: Any] else { return false }
        for key in ["exit_code", "exitCode", "status_code", "statusCode", "code"] {
            if let code = response[key] as? Int, code != 0 { return true }
        }
        if response["success"] as? Bool == false { return true }
        if let error = response["error"], !(error is NSNull),
           error as? Bool != false, error as? String != "" { return true }
        return responseFailed(response["result"] ?? response["response"])
    }
}

/// 将内置入口合并到用户级 hooks.json；只替换本应用的旧条目，信任仍交由 Codex 自身管理。
enum CodexActivityHookInstaller {
    /// 与认证文件采用相同的 CODEX_HOME 约定，保证全局配置覆盖当前用户的所有项目。
    static var configurationURL: URL {
        DirectCodexUsageClient.defaultAuthFileURL().deletingLastPathComponent().appendingPathComponent("hooks.json")
    }

    /// 只把指向当前可执行文件且覆盖全部生命周期的全局条目视为已安装；不把已安装当作已信任。
    static func isInstalled(
        at url: URL = configurationURL,
        executableURL: URL? = Bundle.main.executableURL
    ) -> Bool {
        guard let executableURL, FileManager.default.isExecutableFile(atPath: executableURL.path),
              let data = try? Data(contentsOf: url),
              let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = document["hooks"] as? [String: [[String: Any]]] else { return false }
        let expected = command(for: executableURL)
        return CodexActivityHook.events.allSatisfy { event in
            (hooks[event] ?? []).contains { group in
                let matcher = group["matcher"] as? String ?? ""
                guard matcher.isEmpty || matcher == "*", let handlers = group["hooks"] as? [[String: Any]] else { return false }
                return handlers.contains { $0["type"] as? String == "command" && $0["command"] as? String == expected }
            }
        }
    }

    /// 安装与检测复用同一条命令，路径中的引号和 shell 字符保持字面含义。
    private static func command(for executableURL: URL) -> String {
        "'" + executableURL.path.replacingOccurrences(of: "'", with: "'\"'\"'")
            + "' " + CodexActivityHook.argument
    }

    /// 验证现有配置后备份并原子保存；损坏的配置或不可执行的应用路径直接报错，不覆盖来源。
    @discardableResult
    static func install(
        at url: URL = configurationURL,
        executableURL: URL? = Bundle.main.executableURL
    ) throws -> URL {
        guard let executableURL, FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let existing = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        var document: [String: Any] = [:]
        if let existing {
            guard let object = try JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            document = object
        }
        if let hooks = document["hooks"], !(hooks is [String: Any]) { throw CocoaError(.fileReadCorruptFile) }
        var hooks = document["hooks"] as? [String: Any] ?? [:]
        let command = command(for: executableURL)
        // 先校验全部事件，避免遇到未知结构时部分清理用户配置。
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
            var retained: [[String: Any]] = []
            for var group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
                let remaining = handlers.filter { !isOwnedCommand($0["command"] as? String, configurationURL: url) }
                group["hooks"] = remaining
                if !remaining.isEmpty { retained.append(group) }
            }
            hooks[event] = retained
        }
        for event in CodexActivityHook.events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(["hooks": [[
                "type": "command", "command": command, "timeout": 2,
                "statusMessage": "\(CodexActivityHook.displayName) · \(event)"
            ]]])
            hooks[event] = groups
        }
        document["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = url.appendingPathExtension("codexmeter-backup")
        if let existing, !FileManager.default.fileExists(atPath: backup.path) {
            try existing.write(to: backup, options: .atomic)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 精确识别旧版标准脚本和本应用的原生入口，避免误删调用其他脚本的用户 Hook。
    private static func isOwnedCommand(_ command: String?, configurationURL: URL) -> Bool {
        guard let command else { return false }
        if command.hasSuffix("/Contents/MacOS/CodexMeter' " + CodexActivityHook.argument) { return true }
        let directory = configurationURL.deletingLastPathComponent().appendingPathComponent("hooks")
        for name in ["codex_usage_activity.py", "codex_activity.py"] {
            let path = directory.appendingPathComponent(name).path
            if command == "/usr/bin/python3 \"\(path)\"" { return true }
        }
        return false
    }
}
