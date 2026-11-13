// 公司活动的数据层：复用 Hook，限量读取身份、标题与结束元数据，演示数据始终留在内存。
import Combine
import CodexMeterShared
import Foundation

/// 人物的工作阶段；工具完成不等于回合完成，失去活动信号时回到休息而不是永久工作。
enum CodexOfficeStatus: String, CaseIterable {
    case working, thinking, waiting, completed, failed, idle

    /// 将已校正生命周期的 Hook 状态转换为办公室动作。
    init(_ state: CodexHookActivityState) {
        switch state {
        case .running: self = .working
        case .thinking, .compacting: self = .thinking
        case .waitingApproval: self = .waiting
        case .succeeded, .completed: self = .completed
        case .failed: self = .failed
        case .idle: self = .idle
        }
    }

    var title: String {
        switch self {
        case .working: return officeText("工作中", "Working")
        case .thinking: return officeText("思考中", "Thinking")
        case .waiting: return officeText("等你确认", "Needs you")
        case .completed: return officeText("完成啦", "Finished")
        case .failed: return officeText("遇到问题", "Tool issue")
        case .idle: return officeText("休息中", "On a break")
        }
    }

    var symbol: String {
        switch self {
        case .working: return "keyboard"
        case .thinking: return "ellipsis.bubble"
        case .waiting: return "hand.raised.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle: return "cup.and.saucer.fill"
        }
    }
}

/// 一个持久主会话对应一个同事；工作目录与标题只在本机页面使用，不进入共享 Widget 快照。
struct CodexOfficeEmployee: Equatable, Identifiable {
    let id: String
    let projectPath: String
    let project: String
    var name: String
    let task: String
    var status: CodexOfficeStatus
    let tool: String?
    var updatedAt: Date
    let signalExpired: Bool
    let isDemo: Bool
    var turnID: String? = nil
    var details: CodexOfficeActivityDetails? = nil
    var eventName = ""
    var waitingReason: String? = nil
    var isOnSite = true

    var appearance: Int { Int(Self.stableHash(id) % 6) }

    /// 名册仍可显示离场同事；过期信号与休息使用不同文案。
    var statusTitle: String {
        if eventName == "SessionEnd" { return officeText("已离开", "Left the office") }
        if signalExpired { return officeText("暂无新信号", "No recent signal") }
        return isOnSite ? status.title : officeText("暂无近期活动", "No recent activity")
    }
    var operation: String {
        if status == .waiting { return waitingReason ?? officeText("等待你的确认或回复", "Waiting for your confirmation or reply") }
        if eventName == "SessionEnd" { return officeText("会话已结束", "Session ended") }
        return details?.tools.last(where: { $0.finishedAt == nil })?.operation
            ?? details?.history.last?.operation ?? statusTitle
    }

    /// 只限制三维场景里的出席。明确休息在五分钟内可见，过期信号不推断为休息。
    func appearsOnSite(at now: Date) -> Bool {
        guard eventName != "SessionEnd", !signalExpired else { return false }
        return isDemo || status != .idle || now.timeIntervalSince(updatedAt) <= 300
    }

    /// 固定哈希使衣服与默认姓名在重启后保持一致，不使用每次启动都会变化的 Swift 哈希。
    static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    /// 两字昵称适合场景名牌，保留小镇原有的取名风格。
    private static let shortNames = [
        "阿栈", "小满", "木木", "可可", "橙子", "阿蓝", "小麦", "豆豆", "栗子", "阿简", "小乔", "北北",
        "白露", "阿沐", "南星", "小葵", "柚子", "小禾", "松果", "阿遥", "七喜", "小棠", "米粒", "云朵",
        "白桃", "青柠", "糯米", "山茶", "竹青", "小桥", "砂糖", "海盐", "薄荷", "阿衡", "阿辞", "星野",
        "朝露", "小川", "秋叶", "望舒", "月白", "阿宁", "小墨", "椿芽", "微雨", "甜橙", "麦芽", "杏仁",
        "阿鹿", "清和", "小舟", "初晴", "浅草", "云舒", "小灯", "桐桐", "江月", "石榴", "白梨", "青团",
        "晚风", "小芽", "阿杉", "团团", "梨涡", "星芒", "时雨", "雀儿", "杏子", "阿辰", "小竹", "冬青",
        "南枝", "阿芒", "桂圆", "绒绒"
    ]

    /// 短昵称用完后继续分配适合名牌的三字姓名。
    private static let fullNames = ["林", "许", "沈", "周", "宋", "陈", "顾", "叶", "唐", "苏", "陆", "江", "梁", "程", "孟", "温"].flatMap { surname in
        ["知夏", "言溪", "可舟", "安然", "子衿", "念青", "沐晴", "清越", "知远", "映南", "若溪", "初霁",
         "听澜", "晓棠", "书宁", "怀瑾", "舒言", "寻月", "星遥", "静禾", "文竹", "景行", "知微", "一诺"].map { surname + $0 }
    }

    /// 用会话编号固定选名起点，把首个空闲名字加入占用集合后返回；候选耗尽时按顺序给出称呼。
    static func defaultName(for id: String, reserving occupied: inout Set<String>) -> String {
        let hash = stableHash(id)
        for candidates in [shortNames, fullNames] {
            let start = Int(hash % UInt64(candidates.count))
            for offset in candidates.indices {
                let name = candidates[(start + offset) % candidates.count]
                if occupied.insert(name).inserted { return name }
            }
        }
        var number = 1
        while true {
            let name = officeText("同事 \(number)", "Colleague \(number)")
            if occupied.insert(name).inserted { return name }
            number += 1
        }
    }
}

/// 活动墙展示 Hook 最近六十个结构化事件，不保存工具参数或输出。
struct CodexOfficeEvent: Identifiable, Equatable {
    let id: String
    let employeeID: String
    let name: String
    let status: CodexOfficeStatus
    let tool: String?
    let date: Date
    let operation: String
}

/// 小镇页面独立轮询 Hook 活动，合并会话档案、分配名册昵称并生成活动记录；关闭页面后停止轮询。
@MainActor
final class CodexOfficeStore: ObservableObject {
    @Published private(set) var employees: [CodexOfficeEmployee] = []
    @Published private(set) var events: [CodexOfficeEvent] = []
    @Published private(set) var isDemo = false
    @Published private(set) var hookInstalled = false
    @Published private(set) var installationMessage: String?

    /// 自动分配只记录当前实时名册，和用户保存的昵称独立。
    private static let assignedNamesKey = "office.assignedNames"

    private let activity: CodexHookActivityStore
    private let indexURL: URL?
    private let defaults: UserDefaults
    private var timer: Timer?
    private var identities: [String: (id: String, path: String)] = [:]
    private var titles: [String: String] = [:]
    private var indexModifiedAt: Date?
    private var demoStartedAt = Date()
    private var islandDemo = false
    private var lastHookCheck = Date.distantPast

    /// 可注入临时文件与偏好存储进行真实事件测试；生产环境遵循现有 CODEX_HOME 约定。
    init(
        activity: CodexHookActivityStore? = nil,
        indexURL: URL? = DirectCodexUsageClient.defaultAuthFileURL().deletingLastPathComponent().appendingPathComponent("session_index.jsonl"),
        defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults
    ) {
        self.activity = activity ?? CodexHookActivityStore()
        self.indexURL = indexURL
        self.defaults = defaults
    }

    /// 视图显示期间每秒读取；与菜单的 common runloop 保持一致，拖拽时仍能更新。
    func start() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // 停用页面时，可能已有一次定时回调排在主线程队列中。
                guard let self, self.timer != nil else { return }
                self.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 页面退出时释放唯一的轮询任务，演示也使用同一时钟。
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 切换数据来源或演示布置时重新建立基线，演示事件只在内存中流转。
    func setDemo(_ enabled: Bool, island: Bool = false) {
        let useIslandDemo = enabled && island
        guard enabled != isDemo || useIslandDemo != islandDemo else { return }
        islandDemo = useIslandDemo
        isDemo = enabled
        demoStartedAt = Date()
        events = []
        refresh()
    }

    /// 手动接入复用原安装器的备份和合并机制；信任仍由 Codex 的 Hook 审核页面管理。
    func installHook() {
        do {
            try CodexActivityHookInstaller.install()
            hookInstalled = CodexActivityHookInstaller.isInstalled()
            installationMessage = officeText("已安装。请在 Codex 中检查并信任活动 Hook，然后开始一个新回合。", "Installed. Review and trust the activity hooks in Codex, then start a new turn.")
        } catch {
            installationMessage = officeText("安装未完成，请检查 Codex 配置的访问权限后重试。", "Installation failed. Check access to your Codex configuration and try again.")
        }
    }

    /// 只保存用户主动设置的昵称；空名称恢复稳定默认值，不改变 Codex 会话标题。
    func rename(_ id: String, to name: String) {
        let value = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        let key = "office.nickname." + id
        if value.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(value, forKey: key) }
        refresh()
    }

    /// 按指定时间合并会话身份和状态，跳过身份无法验证的记录；发布前统一名册与活动记录的昵称。
    func refresh(now: Date = Date()) {
        if now.timeIntervalSince(lastHookCheck) >= 5 {
            hookInstalled = CodexActivityHookInstaller.isInstalled()
            lastHookCheck = now
        }
        let next: [CodexOfficeEmployee]
        if isDemo {
            next = demoEmployees(now: now)
        } else {
            activity.refresh(now: now)
            loadTitles()
            let active = Dictionary(activity.snapshots.compactMap { snapshot in
                snapshot.sessionID.map { ($0, snapshot) }
            }, uniquingKeysWith: { _, last in last })
            next = activity.recentSnapshots.compactMap { snapshot in
                guard let id = snapshot.sessionID, let path = snapshot.transcriptPath,
                      let identity = identity(at: path, sessionID: id) else { return nil }
                // 结束 Hook 可能漏发；日志已确认结束时，档案中的工具也不能继续显示运行或猜测成功。
                let ending = snapshot.office?.turnFinishedAt == nil && !["Stop", "Interrupt", "SessionEnd"].contains(snapshot.eventName)
                    ? CodexActivityTranscript.ending(for: snapshot) : nil
                let recentEnding = ending.flatMap { now.timeIntervalSince1970 - $0.date <= 3 ? $0.state : nil }
                let state = active[id]?.state ?? recentEnding ?? .idle
                var details = active[id]?.office ?? CodexActivityTranscript.officeDetails(for: snapshot)
                if let ending, var corrected = details, corrected.turnFinishedAt == nil {
                    corrected.turnFinishedAt = ending.date
                    for index in corrected.tools.indices where corrected.tools[index].finishedAt == nil {
                        corrected.tools[index].finishedAt = ending.date
                        corrected.tools[index].outcome = ending.state == .idle ? "interrupted" : "unknown"
                    }
                    if ending.state == .completed { corrected.completedTurns += 1 }
                    corrected.history.append(CodexOfficeActivityEvent(id: "transcript:\(snapshot.turnID ?? "")", event: "TranscriptEnd", turnID: snapshot.turnID, tool: nil, operation: ending.state == .idle ? "日志确认工作已暂停" : "日志确认本轮已完成", state: ending.state, date: ending.date))
                    corrected.history = Array(corrected.history.suffix(64))
                    details = corrected
                }
                let workspace = snapshot.office?.cwd ?? identity.path
                let projectURL = URL(fileURLWithPath: workspace)
                return CodexOfficeEmployee(
                    id: id, projectPath: workspace, project: projectURL.lastPathComponent,
                    name: "",
                    task: titles[id] ?? officeText("Codex 会话", "Codex session"),
                    status: CodexOfficeStatus(state), tool: active[id]?.toolName,
                    updatedAt: ending.map { Date(timeIntervalSince1970: $0.date) } ?? active[id]?.updatedAtDate
                        ?? Date(timeIntervalSince1970: max(snapshot.updatedAt, details?.tools.filter { $0.outcome == "returned" }.compactMap(\.finishedAt).max() ?? snapshot.updatedAt)),
                    signalExpired: ending == nil && active[id] == nil && !snapshot.isFresh(now: now) && ![.idle, .completed, .succeeded].contains(snapshot.state),
                    isDemo: false, turnID: snapshot.turnID, details: details,
                    eventName: ending.map { $0.state == .idle ? "Interrupt" : "Stop" } ?? snapshot.eventName,
                    waitingReason: active[id]?.pendingQuestionIDs?.isEmpty == false
                        ? officeText("有 \(active[id]?.pendingQuestionIDs?.count ?? 0) 个问题等待你的回复", "\(active[id]?.pendingQuestionIDs?.count ?? 0) questions await your reply")
                        : active[id]?.approvalToolName.map { officeText("等待批准工具：", "Awaiting tool approval: ") + $0 }
                )
            }.sorted { $0.id < $1.id }
            let retainedPaths = Set(activity.recentSnapshots.compactMap(\.transcriptPath))
            identities = identities.filter { retainedPaths.contains($0.key) }
        }
        var roster = next.map { employee in
            var person = employee
            person.isOnSite = person.appearsOnSite(at: now)
            return person
        }
        assignNames(to: &roster)
        let history = roster.flatMap { person -> [CodexOfficeEvent] in
            if let details = person.details {
                return details.history.map { event in
                    CodexOfficeEvent(id: person.id + ":" + event.id, employeeID: person.id, name: person.name,
                                     status: CodexOfficeStatus(event.state), tool: event.tool,
                                     date: Date(timeIntervalSince1970: event.date), operation: event.operation)
                }
            }
            return [CodexOfficeEvent(id: person.id + ":" + person.status.rawValue, employeeID: person.id,
                                    name: person.name, status: person.status, tool: person.tool,
                                    date: person.updatedAt, operation: person.status.title)]
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        let visibleHistory = Array(history.prefix(60))
        if events != visibleHistory { events = visibleHistory }
        if employees != roster { employees = roster }
    }

    /// 为待发布名册分配昵称。手动取名优先，先锁定仍可用的旧名，再为新会话或发生冲突的会话补位。
    private func assignNames(to roster: inout [CodexOfficeEmployee]) {
        let customNames = Dictionary(uniqueKeysWithValues: roster.compactMap { person -> (String, String)? in
            guard let name = defaults.string(forKey: "office.nickname." + person.id), !name.isEmpty else { return nil }
            return (person.id, name)
        })
        var occupied = Set(customNames.values)
        let previousNames = isDemo ? [:] : (defaults.dictionary(forKey: Self.assignedNamesKey) as? [String: String] ?? [:])
        var assignedNames: [String: String] = [:]
        for person in roster where customNames[person.id] == nil {
            let preferredName = person.isDemo ? person.name : previousNames[person.id]
            if let preferredName, occupied.insert(preferredName).inserted {
                assignedNames[person.id] = preferredName
            }
        }
        for index in roster.indices {
            let id = roster[index].id
            if let customName = customNames[id] {
                roster[index].name = customName
                continue
            }
            let name = assignedNames[id] ?? CodexOfficeEmployee.defaultName(for: id, reserving: &occupied)
            roster[index].name = name
            assignedNames[id] = name
        }
        if !isDemo, assignedNames != previousNames {
            defaults.set(assignedNames, forKey: Self.assignedNamesKey)
        }
    }

    /// 日志头只读取一次；缺少持久主会话身份、ID 不匹配或非绝对工作目录时拒绝生成同事。
    private func identity(at path: String, sessionID: String) -> (id: String, path: String)? {
        if let cached = identities[path] { return cached.id == sessionID ? cached : nil }
        guard path.hasPrefix("/"), let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65_536), let line = data.split(separator: 10).first,
              let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              object["type"] as? String == "session_meta", let payload = object["payload"] as? [String: Any],
              payload["id"] as? String == sessionID, payload["source"] is String,
              let cwd = payload["cwd"] as? String, cwd.hasPrefix("/") else { return nil }
        let result = (id: sessionID, path: URL(fileURLWithPath: cwd).standardizedFileURL.path)
        identities[path] = result
        return result
    }

    /// 标题索引只在修改后读取末尾一兆；大文件之外的旧标题回退为会话名，不扫描历史正文。
    private func loadTitles() {
        guard let indexURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: indexURL.path),
              let modified = attributes[.modificationDate] as? Date, modified != indexModifiedAt,
              let handle = try? FileHandle(forReadingFrom: indexURL) else { return }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(),
              (try? handle.seek(toOffset: size > 1_048_576 ? size - 1_048_576 : 0)) != nil,
              let data = try? handle.read(upToCount: 1_048_576) else { return }
        var next: [String: String] = [:]
        for line in data.split(separator: 10) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = object["id"] as? String, let title = object["thread_name"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            next[id] = String(title.prefix(180))
        }
        titles = next
        indexModifiedAt = modified
    }

    /// 按时间推进演示状态。海岛使用三位演员，其他场景使用六位；预设昵称交由名册统一分配。
    private func demoEmployees(now: Date) -> [CodexOfficeEmployee] {
        let cadence: TimeInterval = islandDemo ? 6 : 8
        let tick = max(0, Int(now.timeIntervalSince(demoStartedAt) / cadence))
        let changedAt = demoStartedAt.addingTimeInterval(Double(tick) * cadence)
        let statuses = CodexOfficeStatus.allCases
        let projects = ["产品研发", "设计工作室", "质量保障"]
        let tasks = ["给用量 App 装修新办公室", "打磨交互细节", "把测试跑到全绿", "整理下一轮工作计划", "等待你的好主意", "检查最后一处边界"]
        let islandRoster = [1, 0, 2]
        let islandIDs = ["island-demo-3", "island-demo-8", "island-demo-6"]
        let islandPoses: [[CodexOfficeStatus]] = [
            [.working, .thinking, .idle], [.thinking, .idle, .idle], [.working, .working, .idle],
            [.completed, .waiting, .idle], [.idle, .failed, .working]
        ]
        return (islandDemo ? islandRoster : Array(0..<6)).enumerated().map { slot, index in
            let id = islandDemo ? islandIDs[slot] : "demo-\(index)"
            let status = islandDemo ? islandPoses[tick % islandPoses.count][slot] : statuses[(index + tick) % statuses.count]
            var details = CodexOfficeActivityDetails()
            details.model = "Codex · DEMO"
            details.turnStartedAt = demoStartedAt.addingTimeInterval(-Double(30 + index * 12)).timeIntervalSince1970
            details.toolCalls = 3 + index
            details.failedTools = status == .failed ? 1 : 0
            details.modelRequests = 2 + index
            details.completedTurns = index
            if [.completed, .idle].contains(status) { details.turnFinishedAt = changedAt.timeIntervalSince1970 }
            let state: CodexHookActivityState
            let event: String
            switch status {
            case .working: (state, event) = (.running, "PreToolUse")
            case .thinking: (state, event) = (.thinking, "PostToolUse")
            case .waiting: (state, event) = (.waitingApproval, "PermissionRequest")
            case .completed: (state, event) = (.completed, "Stop")
            case .failed: (state, event) = (.failed, "PostToolUse")
            case .idle: (state, event) = (.idle, "DEMO")
            }
            let tool = ["PreToolUse", "PostToolUse"].contains(event) ? "exec_command" : nil
            let operation = tool == nil ? tasks[index] : officeText("运行命令 · swift test", "Run command · swift test")
            let time = changedAt.timeIntervalSince1970
            details.history = [CodexOfficeActivityEvent(id: "\(id)-\(tick)", event: event, turnID: "demo-turn",
                                                         tool: tool, operation: operation, state: state, date: time)]
            if let tool {
                details.tools = [CodexOfficeToolActivity(id: "demo-tool-\(index)", name: tool, operation: operation,
                    startedAt: status == .working ? time : time - cadence, finishedAt: status == .working ? nil : time,
                    outcome: status == .working ? "running" : status == .failed ? "failed" : "succeeded")]
            }
            return CodexOfficeEmployee(
                id: id, projectPath: "demo/\(index / 2)", project: projects[index / 2],
                name: ["阿栈", "小满", "木木", "可可", "橙子", "阿蓝"][index],
                task: tasks[index], status: status,
                tool: status == .working ? tool : nil,
                updatedAt: changedAt, signalExpired: false, isDemo: true,
                turnID: "demo-turn", details: details
            )
        }
    }
}

/// 新页面的中英文文案遵循应用现有语言设置。
func officeText(_ chinese: String, _ english: String) -> String {
    AppLocalization.usesEnglish() ? english : chinese
}
