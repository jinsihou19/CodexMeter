// 详细活动的事件归约与摘要白名单；运行在原 Hook 的文件锁内，不启动 UI 或外部进程。
import CodexMeterShared
import Foundation

/// 将真实 Hook 事件归并为可追溯的公司活动；所有工具输入都先转换成不含正文的操作摘要。
enum CodexOfficeHookReducer {
    /// 按回合和调用编号去重、配对并行工具；未知起点不猜耗时，历史始终限制为六十四条。
    static func apply(
        payload: [String: Any], previous: CodexOfficeActivityDetails?,
        newTurn: Bool, state: CodexHookActivityState, failed: Bool, now: Date
    ) -> CodexOfficeActivityDetails? {
        var details = previous ?? CodexOfficeActivityDetails()
        let event = payload["hook_event_name"] as? String ?? ""
        let turn = payload["turn_id"] as? String
        let tool = (payload["tool_name"] as? String).map { String($0.prefix(160)) }
        let call = payload["tool_use_id"] as? String
        let date = now.timeIntervalSince1970
        let hasStableID = call != nil || ["UserPromptSubmit", "Stop", "Interrupt", "SessionEnd"].contains(event)
        let eventID = hasStableID ? [turn ?? "", event, call ?? ""].joined(separator: ":") : UUID().uuidString
        guard !details.history.contains(where: { $0.id == eventID }) else { return nil }
        if let cwd = payload["cwd"] as? String, cwd.hasPrefix("/") { details.cwd = String(cwd.prefix(4096)) }
        if let model = payload["model"] as? String { details.model = String(model.prefix(120)) }
        if let mode = payload["permission_mode"] as? String { details.permissionMode = String(mode.prefix(40)) }
        if newTurn {
            details.turnStartedAt = date
            details.turnFinishedAt = nil
            details.toolCalls = 0
            details.failedTools = 0
            details.modelRequests = 0
            details.latestTokenUsage = nil
            details.tools = []
        }
        let operation = operation(payload)
        if event == "PreModelRequest" { details.modelRequests += 1 }
        if event == "PostModelRequest", let usage = payload["token_usage"] as? [String: Any] {
            var counts: [String: Int] = [:]
            for key in ["input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens", "total_tokens"] {
                if let value = usage[key] as? Int, value >= 0 { counts[key] = value }
            }
            details.latestTokenUsage = counts.isEmpty ? nil : counts
        }
        if ["PreToolUse", "PostToolUse"].contains(event), let tool {
            let matching = details.tools.filter { $0.name == tool && $0.finishedAt == nil }
            let key = call ?? (event == "PostToolUse" && matching.count == 1 ? matching.first?.id : nil) ?? UUID().uuidString
            if event == "PreToolUse", details.tools.contains(where: { $0.id == key && $0.finishedAt != nil }) {
                return nil // 结果先到时，不让迟到的开始事件重新点亮该工具。
            }
            if !details.tools.contains(where: { $0.id == key }) {
                details.toolCalls += 1
                details.tools.append(CodexOfficeToolActivity(id: key, name: tool, operation: operation, startedAt: event == "PreToolUse" ? date : nil))
            }
            if event == "PostToolUse", let index = details.tools.firstIndex(where: { $0.id == key }), details.tools[index].finishedAt == nil {
                details.tools[index].finishedAt = date
                let success = confirmedSuccess(payload["tool_response"])
                details.tools[index].outcome = failed ? "failed" : success ? "succeeded" : "returned"
                details.tools[index].resultConfirmed = failed || success
                details.tools[index].exitCode = exitCode(payload["tool_response"])
                if failed { details.failedTools += 1 }
            }
        }
        if ["Stop", "Interrupt", "SessionEnd"].contains(event) {
            details.turnFinishedAt = date
            if event == "Stop" { details.completedTurns += 1 }
            for index in details.tools.indices where details.tools[index].finishedAt == nil {
                details.tools[index].finishedAt = date
                details.tools[index].outcome = event == "Stop" ? "unknown" : "interrupted"
            }
        }
        details.history.append(CodexOfficeActivityEvent(id: eventID, event: event, turnID: turn, tool: tool, operation: operation, state: failed ? .failed : state, date: date))
        details.history = Array(details.history.suffix(64))
        // 已结束工具保留最近三十二个；未结束工具单独保留，不能被快速调用挤掉并行状态。
        details.tools = Array(details.tools.filter { $0.finishedAt != nil }.suffix(32)) + details.tools.filter { $0.finishedAt == nil }
        return details
    }

    /// 只有明确的成功字段才能确认成功；普通文字或缺失失败字段只代表工具已返回。
    private static func confirmedSuccess(_ response: Any?) -> Bool {
        if let code = exitCode(response) { return code == 0 }
        guard let object = response as? [String: Any] else { return false }
        for key in ["exit_code", "exitCode"] {
            if let code = object[key] as? Int { return code == 0 }
        }
        if object["success"] as? Bool == true || object["isError"] as? Bool == false || object["is_error"] as? Bool == false { return true }
        return confirmedSuccess(object["result"] ?? object["response"] ?? object["structuredContent"])
    }

    /// 只接受结构化执行元数据；Bash 的普通输出即使长得像返回头或 JSON，也不能被当成退出状态。
    static func exitCode(_ response: Any?) -> Int? {
        if let object = response as? [String: Any] {
            for key in ["exit_code", "exitCode"] { if let code = object[key] as? Int { return code } }
            for key in ["metadata", "result", "response", "structuredContent"] {
                if let code = exitCode(object[key]) { return code }
            }
        }
        return nil
    }

    /// 仅提取操作类型、已知命令名和文件名；不记录任意 Shell 参数、搜索词、问题、URL 或补丁正文。
    static func operation(_ payload: [String: Any]) -> String {
        let event = payload["hook_event_name"] as? String ?? ""
        let name = payload["tool_name"] as? String ?? ""
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        if !name.isEmpty {
            let short = name.components(separatedBy: ".").last ?? name
            if ["Bash", "exec_command", "shell_command", "shell"].contains(short) {
                let command = input["command"] as? String ?? input["cmd"] as? String ?? ""
                let tokens = command.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                let known = Set(["git", "rg", "find", "cat", "sed", "ls", "xcodebuild", "swift", "npm", "pnpm", "node", "python", "python3", "pytest", "cargo", "go", "make", "curl"])
                if let executable = tokens.prefix(5).first(where: { known.contains(URL(fileURLWithPath: $0).lastPathComponent) }) {
                    let program = URL(fileURLWithPath: executable).lastPathComponent
                    if ["rg", "find"].contains(program) { return "搜索项目文件 · " + program }
                    if ["cat", "sed", "ls"].contains(program) { return "查看项目文件 · " + program }
                    return "运行命令 · " + program
                }
                return "运行终端任务"
            }
            if short == "apply_patch" || short == "Edit" || short == "Write" {
                let command = input["command"] as? String ?? input["patch"] as? String ?? ""
                // 补丁只取文件声明；正文、命令替换和文件内容不会进入活动文件。
                let paths = command.components(separatedBy: .newlines).compactMap { line -> String? in
                    for prefix in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] where line.hasPrefix(prefix) {
                        return URL(fileURLWithPath: String(line.dropFirst(prefix.count))).lastPathComponent
                    }
                    return nil
                }
                return paths.isEmpty ? "修改项目文件" : "修改文件 · " + String(paths.prefix(3).joined(separator: "、").prefix(160))
            }
            if short.contains("request_user_input") { return "等待你的回复" }
            if short.contains("search") || short.contains("web") { return "检索资料 · " + String(short.prefix(80)) }
            if short.contains("read") || short.contains("view") {
                let path = input["path"] as? String ?? input["file_path"] as? String
                return path.map { "查看文件 · " + String(URL(fileURLWithPath: $0).lastPathComponent.prefix(100)) } ?? "查看资料 · " + String(short.prefix(80))
            }
            return "调用工具 · " + String(short.prefix(100))
        }
        switch event {
        case "SessionStart": return "来到办公室"
        case "SessionEnd": return "离开办公室"
        case "UserPromptSubmit": return "开始新一轮工作"
        case "PreModelRequest": return "正在思考下一步"
        case "PostModelRequest": return payload["status"] as? String == "failed" ? "本次模型请求未成功" : "完成一次思考"
        case "PreCompact", "PostCompact": return "整理会话上下文"
        case "Stop": return "完成本轮工作"
        case "Interrupt": return "工作已暂停"
        default: return "更新工作状态"
        }
    }
}
