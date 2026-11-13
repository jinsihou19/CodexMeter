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
        "PreModelRequest", "PostModelRequest", "PreCompact", "PostCompact", "Stop", "Interrupt", "SessionEnd"
    ]

    /// 消费 stdin 的单个事件；异常保持静默，不能因状态指示失败阻塞 Codex。
    static func run() {
        guard let payload = try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile())
            as? [String: Any] else { return }
        let override = ProcessInfo.processInfo.environment["CODEX_USAGE_ACTIVITY_FILE"]
        let url = override.map { URL(fileURLWithPath: $0) } ?? CodexHookActivityLocation.activityURL()
        try? record(payload: payload, at: url)
        if ["Stop", "SubagentStop"].contains(payload["hook_event_name"] as? String ?? "") {
            print("{\"continue\":true}")
        }
    }

    /// 只跟踪持久主会话的当前回合；结束记录保留一天以拒绝迟到事件，所有入口共用同一文件锁。
    static func record(payload: [String: Any], at url: URL, now: Date = Date()) throws {
        guard let event = payload["hook_event_name"] as? String, events.contains(event),
              let sessionID = payload["session_id"] as? String, !sessionID.isEmpty,
              let path = payload["transcript_path"] as? String,
              CodexActivityTranscript.isPersistentRoot(path: path, sessionID: sessionID)
        else { return }
        let turnID = payload["turn_id"] as? String
        guard ["SessionStart", "SessionEnd"].contains(event) || (turnID?.isEmpty == false) else { return }
        // 模型事件可能沿用父会话编号；子代理请求不能覆盖主会话的模型和当前动作。
        if ["PreModelRequest", "PostModelRequest"].contains(event),
           let agent = payload["agent_id"] as? String, agent != sessionID { return }
        let toolName = payload["tool_name"] as? String
        let toolID = payload["tool_use_id"] as? String
        let questionTool = ["request_user_input", "request_user_input_async"].contains(toolName?.components(separatedBy: ".").last ?? "")
        var state: CodexHookActivityState
        switch event {
        case "SessionStart": state = .idle
        case "UserPromptSubmit", "PreToolUse": state = .running
        case "PreModelRequest", "PostModelRequest": state = .thinking
        case "PermissionRequest": state = .waitingApproval
        case "PostToolUse": state = responseFailed(payload["tool_response"]) ? .failed : .thinking
        case "PreCompact", "PostCompact": state = .compacting
        case "Stop": state = .completed
        case "Interrupt", "SessionEnd": state = .idle
        default: return
        }
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
        var previousSnapshots = data.flatMap { try? decoder.decode(CodexHookActivityDocument.self, from: $0).sessions.values.map { $0 } } ?? []
        if previousSnapshots.isEmpty, let data, let previous = try? decoder.decode(CodexHookActivitySnapshot.self, from: data) {
            previousSnapshots = [previous]
        }
        var sessions: [String: CodexHookActivitySnapshot] = [:]
        for snapshot in previousSnapshots where now.timeIntervalSince1970 - snapshot.updatedAt < 86_400 {
            guard let key = snapshot.sessionID else { continue }
            if let existing = sessions[key], existing.updatedAt >= snapshot.updatedAt { continue }
            sessions[key] = snapshot
        }
        let previous = sessions[sessionID]
        let sameTurn = previous?.turnID == turnID
        let wasEnded = previous.map { ["Stop", "Interrupt", "SessionEnd"].contains($0.eventName) } ?? false
        if !["SessionStart", "SessionEnd"].contains(event) {
            // 异步提问可在本轮输出结束后继续等待，此时真实中断仍必须清除等待。
            if sameTurn && wasEnded && event != "Interrupt" { return }
            if event == "UserPromptSubmit" {
                // 全局 Hook 与项目桥接可能重复投递，不能把正在运行的同回合重新初始化。
                if sameTurn { return }
            } else if event != "Stop" && event != "Interrupt" {
                guard sameTurn, previous != nil else { return }
            } else if previous != nil && !sameTurn {
                return
            }
        }
        let retainsTurn = sameTurn || event == "SessionStart"
        var questions = retainsTurn ? CodexActivityTranscript.unansweredQuestions(previous?.pendingQuestionIDs ?? [], path: path) : []
        var approvalID = retainsTurn ? previous?.approvalToolID : nil
        var approvalName = retainsTurn ? previous?.approvalToolName : nil
        if event == "PermissionRequest" {
            approvalID = toolID
            approvalName = toolName
        }
        if event == "PreToolUse", questionTool, let toolID {
            let count = (payload["tool_input"] as? [String: Any])?["questions"] as? [Any]
            questions += (0..<(count?.count ?? 1)).map { "\(toolID):\($0)" }
        }
        if event == "PostToolUse" {
            if questionTool, let toolID,
               !(toolName?.hasSuffix("request_user_input_async") == true && acceptedQuestion(payload["tool_response"])) {
                questions.removeAll { $0.hasPrefix(toolID + ":") }
            }
            // 并行工具的结果不能关闭另一个待审批工具；缺少调用编号的旧事件按工具名配对。
            if approvalName != nil, toolName == approvalName, approvalID == nil || approvalID == toolID {
                approvalID = nil
                approvalName = nil
            }
        }
        if ["Interrupt", "SessionEnd"].contains(event) {
            questions = []
            approvalID = nil
            approvalName = nil
        } else if !questions.isEmpty || approvalName != nil {
            state = .waitingApproval
        }
        let failed = event == "PostToolUse" && responseFailed(payload["tool_response"])
            || event == "PostModelRequest" && payload["status"] as? String == "failed"
        var officePayload = payload
        if event == "SessionEnd" { officePayload["turn_id"] = previous?.turnID }
        guard let office = CodexOfficeHookReducer.apply(
            payload: officePayload, previous: previous?.office, newTurn: event == "UserPromptSubmit" && !sameTurn,
            state: state, failed: failed, now: now
        ) else { return }
        let activeTool = office.tools.last { $0.finishedAt == nil }
        if !["Stop", "Interrupt", "SessionStart", "SessionEnd"].contains(event),
           state != .waitingApproval, activeTool != nil { state = .running }
        if failed && activeTool == nil && state != .waitingApproval { state = .failed }
        // 恢复会话不能清除上一回合的结束标记，避免迟到工具事件重新激活已完成的同事。
        let preservesState = event == "SessionStart" && previous != nil
        sessions[sessionID] = CodexHookActivitySnapshot(
            state: preservesState ? (previous!.isFresh(now: now) ? previous!.state : .idle) : event == "Stop" && previous == nil ? .idle : state,
            sessionID: sessionID, turnID: ["SessionStart", "SessionEnd"].contains(event) ? previous?.turnID : turnID,
            eventName: preservesState ? previous!.eventName : event,
            toolName: activeTool?.name ?? (preservesState ? previous?.toolName : payload["tool_name"] as? String),
            message: nil, updatedAt: now.timeIntervalSince1970, transcriptPath: path,
            pendingQuestionIDs: questions.isEmpty ? nil : Array(Set(questions)).sorted(),
            approvalToolID: approvalID, approvalToolName: approvalName, office: office
        )
        try JSONEncoder().encode(CodexHookActivityDocument(sessions: sessions)).write(to: url, options: .atomic)
    }

    /// 异步提问的 accepted 只表示界面已接收，不能作为用户已经回答；兼容工具返回 JSON 文本。
    private static func acceptedQuestion(_ response: Any?) -> Bool {
        if let response = response as? [String: Any] { return response["accepted"] as? Bool == true }
        guard let text = response as? String, let data = text.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return response["accepted"] as? Bool == true
    }

    /// 只检查结构化失败字段，不把工具输出中的普通错误文案误判为回合失败。
    private static func responseFailed(_ response: Any?) -> Bool {
        if let code = CodexOfficeHookReducer.exitCode(response), code != 0 { return true }
        guard let response = response as? [String: Any] else { return false }
        if response["isError"] as? Bool == true || response["is_error"] as? Bool == true { return true }
        for key in ["status_code", "statusCode"] {
            if let code = response[key] as? Int, code >= 400 { return true }
        }
        if response["success"] as? Bool == false { return true }
        if let error = response["error"], !(error is NSNull),
           error as? Bool != false, error as? String != "" { return true }
        return responseFailed(response["result"] ?? response["response"] ?? response["structuredContent"])
    }
}

/// 限量读取身份、生命周期与工具返回元数据；临时会话和子代理不参与汇总，不保存会话正文。
enum CodexActivityTranscript {
    /// 每次最多前进四兆，只缓存调用编号和返回时间；长会话不会反复扫描全文或永远漏掉较早的返回。
    private struct ToolReturnScan {
        var offset: UInt64 = 0
        var skippingLargeLine = false
        var returns: [String: TimeInterval] = [:]
        var usedAt = Date()
    }
    @MainActor private static var toolReturnScans: [String: ToolReturnScan] = [:]

    /// 用实际返回记录补齐漏发的工具结束事件；仅读取调用编号和时间，不把工具输出复制进活动数据。
    @MainActor
    static func officeDetails(for snapshot: CodexHookActivitySnapshot) -> CodexOfficeActivityDetails? {
        guard var details = snapshot.office, let path = snapshot.transcriptPath else { return snapshot.office }
        // 旧记录曾用“未识别到失败”代表成功；缺少明确确认标记时按已返回展示，不能继续承诺成功。
        for index in details.tools.indices where details.tools[index].outcome == "succeeded" && details.tools[index].resultConfirmed != true {
            details.tools[index].outcome = "returned"
        }
        let pending = Set(details.tools.filter { $0.finishedAt == nil }.map(\.id))
        guard !pending.isEmpty, let handle = FileHandle(forReadingAtPath: path) else { return details }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return details }
        var scan = toolReturnScans[path] ?? ToolReturnScan()
        if scan.offset > size { scan = ToolReturnScan() }
        guard (try? handle.seek(toOffset: scan.offset)) != nil else { return details }
        // EOF 返回 nil 时仍要使用已确认的返回记录，否则下一次轮询会把已返回工具重新显示成运行中。
        let data = (try? handle.read(upToCount: 4_194_304)) ?? Data()
        var start = data.startIndex
        if scan.skippingLargeLine {
            if let newline = data.firstIndex(of: 10) { start = newline + 1; scan.skippingLargeLine = false }
            else { start = data.endIndex }
        }
        let end = data.lastIndex(of: 10).map { $0 + 1 } ?? start
        let complete = end > start ? data[start..<end] : Data()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let marker = Data("\"function_call_output\"".utf8)
        for line in complete.split(separator: 10) where line.range(of: marker) != nil {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "response_item",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "function_call_output",
                  let id = payload["call_id"] as? String,
                  let timestamp = object["timestamp"] as? String else { continue }
            let date: Date?
            if let fractional = formatter.date(from: timestamp) { date = fractional }
            else {
                let seconds = ISO8601DateFormatter()
                date = seconds.date(from: timestamp)
            }
            if let date { scan.returns[id] = date.timeIntervalSince1970 }
        }
        if end > start { scan.offset += UInt64(end) }
        else if data.count == 4_194_304 || scan.skippingLargeLine {
            scan.offset += UInt64(data.count)
            scan.skippingLargeLine = true
        } else { scan.offset += UInt64(start) }
        let recent = Set(scan.returns.sorted { $0.value > $1.value }.prefix(128).map(\.key))
        scan.returns = scan.returns.filter { pending.contains($0.key) || recent.contains($0.key) }
        scan.usedAt = Date()
        if toolReturnScans[path] == nil, toolReturnScans.count >= 64,
           let oldest = toolReturnScans.min(by: { $0.value.usedAt < $1.value.usedAt })?.key { toolReturnScans.removeValue(forKey: oldest) }
        toolReturnScans[path] = scan
        let returned = scan.returns.filter { pending.contains($0.key) }
        guard !returned.isEmpty else { return details }
        for index in details.tools.indices {
            guard details.tools[index].finishedAt == nil, let date = returned[details.tools[index].id] else { continue }
            details.tools[index].finishedAt = date
            // 有返回不等于成功；没有结构化 Hook 结果时保持结果未确认，也不增加失败计数。
            details.tools[index].outcome = "returned"
            details.tools[index].resultConfirmed = false
            let tool = details.tools[index]
            details.history.append(CodexOfficeActivityEvent(
                id: "transcript-tool:" + tool.id, event: "TranscriptToolReturn", turnID: snapshot.turnID,
                tool: tool.name, operation: tool.operation + " · 已返回", state: .thinking, date: date
            ))
        }
        details.history = Array(details.history.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.suffix(64))
        return details
    }

    /// 只解析尾部用户回复的结构化问题编号；部分回答只清除对应选项组，不保留问题或答案文本。
    static func unansweredQuestions(_ ids: [String], path: String) -> [String] {
        guard !ids.isEmpty, let handle = FileHandle(forReadingAtPath: path) else { return ids }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(),
              (try? handle.seek(toOffset: size > 65_536 ? size - 65_536 : 0)) != nil,
              let data = try? handle.read(upToCount: 65_536) else { return ids }
        var answered = Set<String>()
        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "response_item",
                  let payload = object["payload"] as? [String: Any], payload["role"] as? String == "user",
                  let content = payload["content"] as? [[String: Any]] else { continue }
            for part in content {
                guard let text = part["text"] as? String, text.hasPrefix("<send_user_message_question_reply>"),
                      let body = text.components(separatedBy: ">").dropFirst().joined(separator: ">").components(separatedBy: "</send_user_message_question_reply>").first,
                      let bytes = body.data(using: .utf8),
                      let replies = try? JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] else { continue }
                for reply in replies {
                    guard let key = (reply["questionItemId"] as? String)?.data(using: .utf8),
                          let parts = try? JSONSerialization.jsonObject(with: key) as? [Any], parts.count == 3,
                          let callID = parts[1] as? String, let index = parts[2] as? Int else { continue }
                    answered.insert("\(callID):\(index)")
                }
            }
        }
        return ids.filter { !answered.contains($0) }
    }

    /// 持久主会话必须有可读取且身份匹配的日志；缺失日志的 ephemeral 请求直接忽略。
    static func isPersistentRoot(path: String, sessionID: String) -> Bool {
        guard path.hasPrefix("/"), let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65_536),
              let firstLine = data.split(separator: 0x0A).first,
              let object = try? JSONSerialization.jsonObject(with: Data(firstLine)) as? [String: Any],
              object["type"] as? String == "session_meta",
              let metadata = object["payload"] as? [String: Any],
              metadata["id"] as? String == sessionID,
              metadata["source"] is String
        else { return false }
        return true
    }

    /// 尾部出现当前回合完成或中断时立即纠正状态；未知日志结构返回 nil，继续使用 Hook 和超时兜底。
    static func ending(for snapshot: CodexHookActivitySnapshot) -> (state: CodexHookActivityState, date: TimeInterval)? {
        guard let path = snapshot.transcriptPath, let turnID = snapshot.turnID,
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(),
              (try? handle.seek(toOffset: size > 65_536 ? size - 65_536 : 0)) != nil,
              let data = try? handle.read(upToCount: 65_536) else { return nil }
        for line in data.split(separator: 0x0A).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["turn_id"] as? String == turnID,
                  let type = payload["type"] as? String,
                  ["task_complete", "turn_aborted"].contains(type) else { continue }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = (object["timestamp"] as? String).flatMap(formatter.date(from:))?.timeIntervalSince1970
            return (type == "turn_aborted" ? .idle : .completed, date ?? snapshot.updatedAt)
        }
        return nil
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
