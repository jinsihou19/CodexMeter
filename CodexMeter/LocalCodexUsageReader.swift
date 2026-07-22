// 本文件负责只读本机 Codex SQLite 与 automation 配置，并生成菜单和 Widget 所需的统计。

import CodexMeterShared
import Foundation

/// 把应用运行诊断写入统一文本文件，供设置页直接打开排查；日志不记录会话正文。
final class AppDiagnosticLog: @unchecked Sendable {
    static let shared = AppDiagnosticLog()

    let fileURL: URL
    private let lock = NSLock()
    private let maximumFileSize: UInt64 = 1_048_576

    var directoryURL: URL {
        fileURL.deletingLastPathComponent()
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    /// 记录正常运行阶段；分类用于区分本机统计等不同模块。
    func info(_ message: String, category: String = "应用") {
        append(level: "INFO", category: category, message: message)
    }

    /// 记录允许降级的异常，不中断应用其他功能。
    func warning(_ message: String, category: String = "应用") {
        append(level: "WARN", category: category, message: message)
    }

    /// 记录导致功能无法完成的错误。
    func error(_ message: String, category: String = "应用") {
        append(level: "ERROR", category: category, message: message)
    }

    /// 确保日志文件存在，供设置页在尚无记录时也能正常打开。
    func prepareFile() {
        lock.lock()
        defer { lock.unlock() }
        try? prepareFileLocked()
    }

    /// 串行追加单行日志；超过 1 MB 时直接从新文件开始，避免长期轮询无限占用磁盘。
    private func append(level: String, category: String, message: String) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try prepareFileLocked()
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if (attributes[.size] as? NSNumber)?.uint64Value ?? 0 >= maximumFileSize {
                try Data().write(to: fileURL, options: .atomic)
            }
            let cleanMessage = message.replacingOccurrences(of: "\n", with: " ")
            let cleanCategory = category.replacingOccurrences(of: "\n", with: " ")
            let line = "[\(Self.timestamp())] [\(level)] [\(cleanCategory)] \(cleanMessage)\n"
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            // 日志自身失败不能影响额度刷新或本机统计读取。
        }
    }

    /// 创建日志目录和空文件，不覆盖已有诊断记录。
    private func prepareFileLocked() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try Data().write(to: fileURL, options: .atomic)
        }
    }

    /// 返回用户级 Application Support 下的稳定日志位置。
    private static func defaultFileURL() -> URL {
        if Bundle.main.bundleURL.pathExtension == "xctest"
            || Bundle.main.bundleIdentifier?.localizedCaseInsensitiveContains("xctest") == true
        {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("CodexMeterTests", isDirectory: true)
                .appendingPathComponent("CodexMeter.log")
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("CodexMeter", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("CodexMeter.log")
    }

    /// 生成带时区的稳定时间戳，方便跨电脑比对刷新时点。
    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

/// 描述应用内存中的完整本机统计；任务标题不会写入共享快照。
struct LocalCodexUsageSnapshot: Sendable {
    let summary: LocalCodexUsageSummary
    let taskBoard: LocalCodexTaskBoard
}

/// 定义今日任务的展示分类。
enum LocalCodexTaskKind: String, Sendable {
    case active
    case pending
    case scheduled
    case done
}

/// 描述一条仅在应用内存展示的本机任务。
struct LocalCodexTaskItem: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String?
    let kind: LocalCodexTaskKind
    let updatedAt: Date
    let tokens: Int64
}

/// 保存今日任务条目并提供四类计数。
struct LocalCodexTaskBoard: Sendable {
    let items: [LocalCodexTaskItem]

    var activeCount: Int { count(.active) }
    var pendingCount: Int { count(.pending) }
    var scheduledCount: Int { count(.scheduled) }
    var doneCount: Int { count(.done) }

    /// 返回指定分类的任务数量。
    private func count(_ kind: LocalCodexTaskKind) -> Int {
        items.lazy.filter { $0.kind == kind }.count
    }
}

/// 使用系统 sqlite3 只读汇总 Codex 状态库；任一读取失败都返回 nil，不影响网络额度刷新。
struct LocalCodexUsageReader: Sendable {
    typealias Query = @Sendable (URL, String) -> Data?
    private static let diagnosticCategory = "本机统计"

    private let now: @Sendable () -> Date
    private let databaseURL: URL?
    private let sessionIndexURL: URL?
    private let automationFiles: [URL]
    private let diagnostics: AppDiagnosticLog
    private let query: Query

    init(
        now: @escaping @Sendable () -> Date = Date.init,
        databaseURL: URL? = nil,
        sessionIndexURL: URL? = nil,
        automationFiles: [URL]? = nil,
        diagnostics: AppDiagnosticLog = .shared,
        query: @escaping Query = LocalCodexUsageReader.runQuery
    ) {
        self.now = now
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL()
        self.sessionIndexURL = sessionIndexURL
            ?? (databaseURL?.deletingLastPathComponent().appendingPathComponent("session_index.jsonl"))
            ?? Self.defaultSessionIndexURL()
        self.automationFiles = automationFiles ?? Self.defaultAutomationFiles()
        self.diagnostics = diagnostics
        self.query = query
    }

    /// 在后台读取统计；数据库缺失、schema 不兼容或 sqlite3 执行失败时返回 nil。
    func load() async -> LocalCodexUsageSnapshot? {
        diagnostics.info(
            "开始读取本机统计；应用版本=\(Self.applicationVersionDescription())",
            category: Self.diagnosticCategory
        )
        let pricingCatalog = LocalCodexPricingCatalog.loadCached()
        Task.detached(priority: .background) {
            await LocalCodexPricingCatalog.refreshIfNeeded()
        }
        let snapshot = await Task.detached(priority: .utility) {
            loadSynchronously(pricingCatalog: pricingCatalog)
        }.value
        if snapshot == nil {
            diagnostics.error("本机统计读取结束：未生成可用快照", category: Self.diagnosticCategory)
        }
        return snapshot
    }

    /// 执行聚合查询并组装内存快照；动态价格缺失时使用内置官方价格兜底。
    private func loadSynchronously(pricingCatalog: LocalCodexPricingCatalog?) -> LocalCodexUsageSnapshot? {
        guard let databaseURL else {
            let candidates = Self.databaseCandidates().map(\.path).joined(separator: "；")
            diagnostics.error("未找到 Codex 状态库；已检查=\(candidates)", category: Self.diagnosticCategory)
            return nil
        }
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            diagnostics.error("Codex 状态库不存在；路径=\(databaseURL.path)", category: Self.diagnosticCategory)
            return nil
        }
        guard FileManager.default.isReadableFile(atPath: databaseURL.path) else {
            diagnostics.error("Codex 状态库不可读；请检查文件权限；路径=\(databaseURL.path)", category: Self.diagnosticCategory)
            return nil
        }
        diagnostics.info("使用 Codex 状态库；路径=\(databaseURL.path)", category: Self.diagnosticCategory)
        let fetchedAt = now()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: fetchedAt)
        let sevenDayStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let historyStart = calendar.date(byAdding: .day, value: -189, to: todayStart) ?? sevenDayStart
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: fetchedAt)) ?? todayStart
        let activeStart = fetchedAt.addingTimeInterval(-2 * 60 * 60)
        let sessionTitles = sessionTitlesByThreadID()

        guard let totals: [TotalsRow] = rows(
            for: totalsSQL(todayStart: todayStart, sevenDayStart: sevenDayStart),
            databaseURL: databaseURL,
            context: "总览"
        ) else { return nil }
        guard let total = totals.first else {
            diagnostics.error("总览查询未返回聚合行；数据库 schema 可能不兼容", category: Self.diagnosticCategory)
            return nil
        }
        guard let projectRows: [ProjectRow] = rows(
            for: projectsSQL(sevenDayStart: sevenDayStart),
            databaseURL: databaseURL,
            context: "项目"
        ) else { return nil }
        guard let openRows: [TaskRow] = rows(
            for: openTasksSQL(todayStart: todayStart),
            databaseURL: databaseURL,
            context: "未归档任务"
        ) else { return nil }
        guard let doneRows: [TaskRow] = rows(
            for: doneTasksSQL(todayStart: todayStart),
            databaseURL: databaseURL,
            context: "已归档任务"
        ) else { return nil }

        let mappedProjects = projectRows.map { Self.projectUsage(from: $0) }
        let sortedProjects = mappedProjects.sorted { left, right in
            if left.tokens == right.tokens { return left.name < right.name }
            return left.tokens > right.tokens
        }
        let projects = Array(sortedProjects.prefix(5))
        let openTasks = openRows.map { row in
            task(
                from: row,
                kind: Date(timeIntervalSince1970: row.updatedAt) >= activeStart ? .active : .pending,
                sessionTitles: sessionTitles
            )
        }
        let completedTasks = doneRows.map { task(from: $0, kind: .done, sessionTitles: sessionTitles) }
        let threadTasks = openTasks + completedTasks
        let taskBoard = LocalCodexTaskBoard(items: Self.sortedTasks(threadTasks + automationTasks()))
        let dailyRows: [DailyUsageRow] = rows(
            for: dailyUsageSQL(historyStart: historyStart),
            databaseURL: databaseURL,
            context: "每日趋势"
        ) ?? []
        let monthSources: [MonthSessionRow] = rows(
            for: monthSessionsSQL(monthStart: monthStart),
            databaseURL: databaseURL,
            context: "本月会话"
        ) ?? []
        let monthCost = Self.monthCost(sources: monthSources, catalog: pricingCatalog)
        let summary = LocalCodexUsageSummary(
            fetchedAt: fetchedAt,
            todayTokens: total.todayTokens,
            sevenDayTokens: total.sevenDayTokens,
            lifetimeTokens: total.lifetimeTokens,
            threadCount: total.threadCount,
            projects: projects,
            taskCounts: LocalCodexTaskCounts(
                active: taskBoard.activeCount,
                pending: taskBoard.pendingCount,
                scheduled: taskBoard.scheduledCount,
                done: taskBoard.doneCount
            ),
            dailyBuckets: Self.dailyBuckets(
                from: dailyRows,
                monthCost: monthCost,
                monthStart: monthStart,
                endingAt: todayStart,
                calendar: calendar
            ),
            monthCost: monthCost
        )
        diagnostics.info(
            "本机统计读取成功；线程=\(total.threadCount)；项目=\(projects.count)；日聚合=\(dailyRows.count)；本月会话=\(monthSources.count)",
            category: Self.diagnosticCategory
        )
        return LocalCodexUsageSnapshot(summary: summary, taskBoard: taskBoard)
    }

    /// 将稀疏 SQLite 日聚合补成连续 190 天，并按本月 Token 权重分摊已有的 API 等效成本。
    private static func dailyBuckets(
        from rows: [DailyUsageRow],
        monthCost: LocalCodexCostSummary?,
        monthStart: Date,
        endingAt endDate: Date,
        calendar: Calendar
    ) -> [LocalCodexDailyUsageBucket] {
        let tokensByDay = Dictionary(uniqueKeysWithValues: rows.map { ($0.day, $0.tokens) })
        let identifierFormatter = DateFormatter()
        identifierFormatter.calendar = calendar
        identifierFormatter.locale = Locale(identifier: "en_US_POSIX")
        identifierFormatter.timeZone = calendar.timeZone
        identifierFormatter.dateFormat = "yyyy-MM-dd"
        let monthStartIdentifier = identifierFormatter.string(from: monthStart)
        let monthTokens = rows
            .filter { $0.day >= monthStartIdentifier }
            .reduce(Int64(0)) { $0 + $1.tokens }
        let hasEstimatedCost = (monthCost?.pricedSessionCount ?? 0) > 0
        let costPerToken = (monthCost?.estimatedCostUSD ?? 0) / Double(max(1, monthTokens))
        let labelFormatter = DateFormatter()
        labelFormatter.calendar = calendar
        labelFormatter.locale = Locale(identifier: "en_US_POSIX")
        labelFormatter.timeZone = calendar.timeZone
        labelFormatter.dateFormat = "MM/dd"

        return (0..<190).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - 189, to: endDate) else { return nil }
            let identifier = identifierFormatter.string(from: date)
            let tokens = tokensByDay[identifier] ?? 0
            return LocalCodexDailyUsageBucket(
                id: identifier,
                label: labelFormatter.string(from: date),
                tokens: tokens,
                estimatedCostUSD: identifier >= monthStartIdentifier && tokens > 0 && hasEstimatedCost
                    ? Double(tokens) * costPerToken
                    : nil
            )
        }
    }

    /// 读取本月 session 末尾的累计 token，按模型价格计算 API 等效价值。
    private static func monthCost(
        sources: [MonthSessionRow],
        catalog: LocalCodexPricingCatalog?
    ) -> LocalCodexCostSummary? {
        var input: Int64 = 0
        var cached: Int64 = 0
        var output: Int64 = 0
        var estimatedCost = 0.0
        var pricedCount = 0
        var seenPaths = Set<String>()

        for source in sources where seenPaths.insert(source.rolloutPath).inserted {
            guard let tokens = latestTokenUsage(at: URL(fileURLWithPath: source.rolloutPath)) else { continue }
            input += tokens.input
            cached += tokens.cachedInput
            output += tokens.output
            if let price = catalog?.price(for: source.model) ?? LocalCodexPricingCatalog.fallbackPrice(for: source.model) {
                estimatedCost += Self.estimatedCost(for: tokens, price: price)
                pricedCount += 1
            }
        }

        guard input > 0 || cached > 0 || output > 0 else { return nil }
        return LocalCodexCostSummary(
            inputTokens: input,
            cachedInputTokens: cached,
            outputTokens: output,
            estimatedCostUSD: estimatedCost,
            pricedSessionCount: pricedCount,
            sessionCount: seenPaths.count
        )
    }

    /// 从 JSONL 文件末尾向前查找最后一条累计 token 事件，最多读取 4 MB。
    private static func latestTokenUsage(at url: URL) -> SessionTokenUsage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        let readSize = min(fileSize, 4 * 1_024 * 1_024)
        guard readSize > 0, (try? handle.seek(toOffset: fileSize - readSize)) != nil,
              let data = try? handle.read(upToCount: Int(readSize))
        else { return nil }
        for line in data.split(separator: 0x0A).reversed() where String(decoding: line, as: UTF8.self).contains("\"token_count\"") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let usage = info["total_token_usage"] as? [String: Any]
            else { continue }
            return SessionTokenUsage(
                input: int64(usage["input_tokens"]),
                cachedInput: int64(usage["cached_input_tokens"]),
                output: int64(usage["output_tokens"])
            )
        }
        return nil
    }

    /// 按标准单价计算某次 token 增量的 API 等效金额；累计事件无法可靠判定长上下文阈值。
    private static func estimatedCost(
        for tokens: SessionTokenUsage,
        price: LocalCodexPricingCatalog.Price
    ) -> Double {
        let billableCached = min(tokens.cachedInput, tokens.input)
        let uncached = max(0, tokens.input - billableCached)
        return Double(uncached) / 1_000_000 * price.inputPerMillion
            + Double(billableCached) / 1_000_000 * price.cachedInputPerMillion
            + Double(tokens.output) / 1_000_000 * price.outputPerMillion
    }

    /// 将 JSON 数字安全转换为非负 Int64。
    private static func int64(_ value: Any?) -> Int64 {
        max(0, (value as? NSNumber)?.int64Value ?? 0)
    }

    /// 解码 sqlite3 的 JSON 行；上下文只用于日志标识，不写入查询结果或会话正文。
    private func rows<Row: Decodable>(for sql: String, databaseURL: URL, context: String) -> [Row]? {
        guard let data = query(databaseURL, sql) else {
            diagnostics.error("\(context)查询失败；数据库=\(databaseURL.path)", category: Self.diagnosticCategory)
            return nil
        }
        // sqlite3 -json 在查询零行时输出空字节；这是合法空集合，不应让整份统计失败。
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }) {
            return []
        }
        do {
            return try JSONDecoder().decode([Row].self, from: data)
        } catch {
            diagnostics.error("\(context)结果解析失败；错误=\(error.localizedDescription)", category: Self.diagnosticCategory)
            return nil
        }
    }

    /// 将 SQLite 项目行收敛为不包含完整路径的共享摘要。
    private static func projectUsage(from row: ProjectRow) -> LocalCodexProjectUsage {
        let path = row.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = path.isEmpty ? "未归类" : URL(fileURLWithPath: path).lastPathComponent
        let displayName = name.isEmpty ? "未归类" : name
        return LocalCodexProjectUsage(
            id: "\(displayName):\(row.tokens):\(row.threadCount)",
            name: displayName,
            tokens: row.tokens,
            threadCount: row.threadCount
        )
    }

    /// 将线程行转换为菜单任务，优先使用侧边栏标题索引，再回退 SQLite 标题和 preview。
    private func task(
        from row: TaskRow,
        kind: LocalCodexTaskKind,
        sessionTitles: [String: String]
    ) -> LocalCodexTaskItem {
        let indexedTitle = sessionTitles[row.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = row.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        let cwd = row.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        return LocalCodexTaskItem(
            id: row.id,
            title: indexedTitle.isEmpty ? (title.isEmpty ? preview : title) : indexedTitle,
            detail: cwd.isEmpty ? nil : URL(fileURLWithPath: cwd).lastPathComponent,
            kind: kind,
            updatedAt: Date(timeIntervalSince1970: row.updatedAt),
            tokens: max(0, row.tokens)
        )
    }

    /// 逐行解析会话索引；重复 id 以后写入的标题为准，与 Codex 侧边栏保持一致。
    private func sessionTitlesByThreadID() -> [String: String] {
        guard let sessionIndexURL else { return [:] }
        let data: Data
        do {
            data = try Data(contentsOf: sessionIndexURL)
        } catch {
            diagnostics.warning("会话名称索引读取失败；路径=\(sessionIndexURL.path)；错误=\(error.localizedDescription)", category: Self.diagnosticCategory)
            return [:]
        }
        let decoder = JSONDecoder()
        var titles: [String: String] = [:]
        for line in data.split(separator: 0x0A) {
            guard let row = try? decoder.decode(SessionIndexRow.self, from: Data(line)),
                  !row.threadName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            titles[row.id] = row.threadName
        }
        return titles
    }

    /// 解析 ACTIVE automation 的简单键值，复杂 TOML 语法留给 Codex 自身处理。
    private func automationTasks() -> [LocalCodexTaskItem] {
        automationFiles.compactMap { url in
            let contents: String
            do {
                contents = try String(contentsOf: url, encoding: .utf8)
            } catch {
                diagnostics.warning("自动化配置读取失败；路径=\(url.path)；错误=\(error.localizedDescription)", category: Self.diagnosticCategory)
                return nil
            }
            let values = Self.simpleKeyValues(contents)
            guard values["status"]?.uppercased() == "ACTIVE" else {
                return nil
            }
            let title = values["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now()
            return LocalCodexTaskItem(
                id: "automation:\(url.deletingLastPathComponent().lastPathComponent)",
                title: title?.isEmpty == false ? title! : url.deletingLastPathComponent().lastPathComponent,
                detail: values["rrule"] ?? values["schedule"],
                kind: .scheduled,
                updatedAt: modifiedAt,
                tokens: 0
            )
        }
    }

    /// 仅解析 automation.toml 需要的顶层 key=value，忽略注释和未知字段。
    private static func simpleKeyValues(_ contents: String) -> [String: String] {
        contents.split(whereSeparator: \.isNewline).reduce(into: [:]) { result, line in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1]
                .split(separator: "#", maxSplits: 1).first.map(String.init)?
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'")) ?? ""
            if !key.isEmpty { result[key] = value }
        }
    }

    /// 按进行中、待处理、定时、完成排序，同类任务按更新时间倒序。
    private static func sortedTasks(_ tasks: [LocalCodexTaskItem]) -> [LocalCodexTaskItem] {
        let order: [LocalCodexTaskKind: Int] = [.active: 0, .pending: 1, .scheduled: 2, .done: 3]
        return tasks.sorted {
            let left = order[$0.kind, default: 4]
            let right = order[$1.kind, default: 4]
            return left == right ? $0.updatedAt > $1.updatedAt : left < right
        }
    }

    /// 定位 CODEX_HOME 或默认 ~/.codex 下当前使用的状态库。
    private static func defaultDatabaseURL() -> URL? {
        databaseCandidates().first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 返回当前支持的状态库候选路径，日志沿用同一列表避免诊断与实际读取不一致。
    private static func databaseCandidates() -> [URL] {
        let home = codexHomeURL()
        return [
            home.appendingPathComponent("state_5.sqlite"),
            home.appendingPathComponent("sqlite/state_5.sqlite")
        ]
    }

    /// 定位 Codex 侧边栏使用的会话名称索引。
    private static func defaultSessionIndexURL() -> URL {
        codexHomeURL().appendingPathComponent("session_index.jsonl")
    }

    /// 枚举 automations 的直接子目录配置文件，避免递归扫描无关内容。
    private static func defaultAutomationFiles() -> [URL] {
        let directory = codexHomeURL().appendingPathComponent("automations", isDirectory: true)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return children.map { $0.appendingPathComponent("automation.toml") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 返回环境变量指定的 Codex 根目录，未设置时使用用户主目录。
    private static func codexHomeURL() -> URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    /// 使用系统 sqlite3 的只读 JSON 输出执行查询，失败时不抛出到刷新链路。
    private static func runQuery(databaseURL: URL, sql: String) -> Data? {
        let executable = ["/usr/bin/sqlite3", "/opt/homebrew/bin/sqlite3", "/usr/local/bin/sqlite3"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let executable else {
            AppDiagnosticLog.shared.error("未找到可执行的 sqlite3", category: Self.diagnosticCategory)
            return nil
        }

        for attempt in 0...1 {
            do {
                let result = try runQueryAttempt(executable: executable, databaseURL: databaseURL, sql: sql)
                guard result.terminationStatus != 0 else { return result.data }
                if attempt == 0,
                   shouldRetrySQLite(
                       terminationStatus: result.terminationStatus,
                       errorText: result.errorText
                   ) {
                    AppDiagnosticLog.shared.warning(
                        "sqlite3 暂时无法打开状态库；200毫秒后重试",
                        category: Self.diagnosticCategory
                    )
                    Thread.sleep(forTimeInterval: 0.2)
                    continue
                }
                AppDiagnosticLog.shared.error(
                    "sqlite3 执行失败；状态=\(result.terminationStatus)；错误=\(result.errorText.isEmpty ? "无详细信息" : result.errorText)",
                    category: Self.diagnosticCategory
                )
                return nil
            } catch {
                AppDiagnosticLog.shared.error(
                    "sqlite3 启动失败；错误=\(error.localizedDescription)",
                    category: Self.diagnosticCategory
                )
                return nil
            }
        }
        return nil
    }

    /// 执行单次 sqlite3 子进程，把退出状态和错误文本交给上层判断是否重试。
    private static func runQueryAttempt(
        executable: String,
        databaseURL: URL,
        sql: String
    ) throws -> (data: Data, terminationStatus: Int32, errorText: String) {
        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-readonly", "-json", databaseURL.path, sql]
        process.standardOutput = output
        process.standardError = errorOutput
        try process.run()
        // 必须在 wait 前读取 stdout：会话路径查询可能超过 Pipe 缓冲区，否则 sqlite3 与父进程会互相等待。
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errorText = String(decoding: errorOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (data, process.terminationStatus, errorText)
    }

    /// 两代 sqlite3 CLI 分别使用状态 1 和 14 报告 CANTOPEN，统一按错误码或文本识别。
    static func shouldRetrySQLite(terminationStatus: Int32, errorText: String) -> Bool {
        terminationStatus == 14
            || errorText.localizedCaseInsensitiveContains("unable to open database file")
    }

    /// 返回日志所需的应用展示版本和构建号，字段缺失时使用问号占位。
    private static func applicationVersionDescription() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// 生成累计、今日和近七天 token 汇总查询。
    private func totalsSQL(todayStart: Date, sevenDayStart: Date) -> String {
        let today = Int64(todayStart.timeIntervalSince1970)
        let sevenDay = Int64(sevenDayStart.timeIntervalSince1970)
        return """
        SELECT COALESCE(SUM(CASE WHEN updated_at >= \(today) OR recency_at >= \(today) THEN tokens_used ELSE 0 END), 0) AS todayTokens,
               COALESCE(SUM(CASE WHEN updated_at >= \(sevenDay) OR recency_at >= \(sevenDay) THEN tokens_used ELSE 0 END), 0) AS sevenDayTokens,
               COALESCE(SUM(tokens_used), 0) AS lifetimeTokens,
               COUNT(*) AS threadCount,
               COALESCE(MAX(CASE WHEN COALESCE(recency_at, 0) > updated_at THEN recency_at ELSE updated_at END), 0) AS lastUpdatedAt
        FROM threads;
        """
    }

    /// 生成近七天项目 Top 5 查询。
    private func projectsSQL(sevenDayStart: Date) -> String {
        let start = Int64(sevenDayStart.timeIntervalSince1970)
        return """
        SELECT COALESCE(cwd, '') AS cwd, COALESCE(SUM(tokens_used), 0) AS tokens, COUNT(*) AS threadCount,
               COALESCE(MAX(CASE WHEN COALESCE(recency_at, 0) > updated_at THEN recency_at ELSE updated_at END), 0) AS lastActiveAt
        FROM threads
        WHERE updated_at >= \(start) OR recency_at >= \(start)
        GROUP BY cwd ORDER BY tokens DESC LIMIT 5;
        """
    }

    /// 按线程最近活动日生成近半年趋势，普通看板只取末七天。
    private func dailyUsageSQL(historyStart: Date) -> String {
        let start = Int64(historyStart.timeIntervalSince1970)
        return """
        SELECT strftime('%Y-%m-%d', datetime(
                   CASE WHEN COALESCE(recency_at, 0) > updated_at THEN recency_at ELSE updated_at END,
                   'unixepoch', 'localtime')) AS day,
               COALESCE(SUM(tokens_used), 0) AS tokens
        FROM threads
        WHERE updated_at >= \(start) OR recency_at >= \(start)
        GROUP BY day ORDER BY day;
        """
    }

    /// 只枚举本月新建线程的日志路径，避免在高频刷新时全量扫描历史归档。
    private func monthSessionsSQL(monthStart: Date) -> String {
        let start = Int64(monthStart.timeIntervalSince1970)
        return """
        SELECT rollout_path AS rolloutPath, COALESCE(model, '') AS model
        FROM threads
        WHERE created_at >= \(start) AND rollout_path IS NOT NULL AND rollout_path <> '';
        """
    }

    /// 生成今日未归档任务查询，分类阈值在 Swift 层统一处理。
    private func openTasksSQL(todayStart: Date) -> String {
        let start = Int64(todayStart.timeIntervalSince1970)
        return """
        SELECT id, COALESCE(title, '') AS title, COALESCE(preview, '') AS preview, COALESCE(cwd, '') AS cwd,
               COALESCE(tokens_used, 0) AS tokens,
               CASE WHEN COALESCE(recency_at, 0) > updated_at THEN recency_at ELSE updated_at END AS updatedAt
        FROM threads
        WHERE archived = 0 AND (updated_at >= \(start) OR recency_at >= \(start) OR created_at >= \(start))
          AND (COALESCE(title, '') <> '' OR COALESCE(preview, '') <> '')
        ORDER BY updatedAt DESC LIMIT 20;
        """
    }

    /// 生成今日已归档任务查询。
    private func doneTasksSQL(todayStart: Date) -> String {
        let start = Int64(todayStart.timeIntervalSince1970)
        return """
        SELECT id, COALESCE(title, '') AS title, COALESCE(preview, '') AS preview, COALESCE(cwd, '') AS cwd,
               COALESCE(tokens_used, 0) AS tokens, COALESCE(archived_at, updated_at) AS updatedAt
        FROM threads
        WHERE archived = 1 AND COALESCE(archived_at, updated_at) >= \(start)
          AND (COALESCE(title, '') <> '' OR COALESCE(preview, '') <> '')
        ORDER BY updatedAt DESC LIMIT 20;
        """
    }
}

/// sqlite3 汇总行。
private struct TotalsRow: Decodable {
    let todayTokens: Int64
    let sevenDayTokens: Int64
    let lifetimeTokens: Int64
    let threadCount: Int
    let lastUpdatedAt: TimeInterval
}

/// sqlite3 项目聚合行。
private struct ProjectRow: Decodable {
    let cwd: String
    let tokens: Int64
    let threadCount: Int
    let lastActiveAt: TimeInterval
}

/// sqlite3 今日任务行。
private struct TaskRow: Decodable {
    let id: String
    let title: String
    let preview: String
    let cwd: String
    let tokens: Int64
    let updatedAt: TimeInterval
}

/// session_index.jsonl 中的会话名称行。
private struct SessionIndexRow: Decodable {
    let id: String
    let threadName: String

    enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
    }
}

/// sqlite3 每日 token 聚合行。
private struct DailyUsageRow: Decodable {
    let day: String
    let tokens: Int64
}

/// sqlite3 本月 session 日志索引行。
private struct MonthSessionRow: Decodable {
    let rolloutPath: String
    let model: String
}

/// 描述单个 session 最新累计 token 拆分。
private struct SessionTokenUsage {
    let input: Int64
    let cachedInput: Int64
    let output: Int64
}

/// 保存 models.dev 的 OpenAI 模型价格快照，并在网络不可用时提供小型内置兜底表。
private struct LocalCodexPricingCatalog: Codable, Sendable {
    /// 描述每百万 token 的美元单价，可选保存长上下文价格。
    struct Price: Codable, Sendable {
        let inputPerMillion: Double
        let cachedInputPerMillion: Double
        let outputPerMillion: Double
        let thresholdTokens: Int?
        let inputAboveThreshold: Double?
        let cachedInputAboveThreshold: Double?
        let outputAboveThreshold: Double?
    }

    private struct CacheArtifact: Codable {
        let fetchedAt: Date
        let catalog: LocalCodexPricingCatalog
    }

    let prices: [String: Price]

    /// 按日志模型名归一化查价，优先精确匹配，再兼容日期后缀。
    func price(for model: String) -> Price? {
        let normalized = Self.normalizedModel(model)
        if let exact = prices[normalized] { return exact }
        return prices.keys
            .filter { normalized.hasPrefix($0 + "-") || normalized.contains($0) }
            .sorted { $0.count > $1.count }
            .compactMap { prices[$0] }
            .first
    }

    /// 读取 24 小时内的本地价格缓存，过期数据仍可作为本次刷新的兜底。
    static func loadCached() -> LocalCodexPricingCatalog? {
        guard let data = try? Data(contentsOf: cacheURL()),
              let artifact = try? JSONDecoder().decode(CacheArtifact.self, from: data)
        else { return nil }
        return artifact.catalog
    }

    /// 缓存超过 24 小时时从 models.dev 刷新；任何失败都静默保留旧数据。
    static func refreshIfNeeded(now: Date = Date()) async {
        let url = cacheURL()
        if let data = try? Data(contentsOf: url),
           let artifact = try? JSONDecoder().decode(CacheArtifact.self, from: data),
           now.timeIntervalSince(artifact.fetchedAt) < 24 * 60 * 60 {
            return
        }
        guard let endpoint = URL(string: "https://models.dev/api.json"),
              let (data, response) = try? await URLSession.shared.data(from: endpoint),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
              let catalog = parseModelsDev(data), !catalog.prices.isEmpty
        else { return }

        let artifact = CacheArtifact(fetchedAt: now, catalog: catalog)
        guard let encoded = try? JSONEncoder().encode(artifact) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoded.write(to: url, options: .atomic)
    }

    /// 解析 models.dev 顶层 provider 映射，只保留 OpenAI 中具备输入和输出价的模型。
    private static func parseModelsDev(_ data: Data) -> LocalCodexPricingCatalog? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let providers = root["providers"] as? [String: Any] ?? root
        guard let openAI = providers.first(where: { $0.key.lowercased() == "openai" })?.value as? [String: Any],
              let models = openAI["models"] as? [String: Any]
        else { return nil }

        var prices: [String: Price] = [:]
        for (mapKey, rawModel) in models {
            guard let model = rawModel as? [String: Any],
                  let cost = model["cost"] as? [String: Any],
                  let input = number(cost["input"]),
                  let output = number(cost["output"])
            else { continue }
            let id = (model["id"] as? String) ?? mapKey
            let longContext = cost["context_over_200k"] as? [String: Any]
            prices[normalizedModel(id)] = Price(
                inputPerMillion: input,
                cachedInputPerMillion: number(cost["cache_read"]) ?? input,
                outputPerMillion: output,
                thresholdTokens: longContext == nil ? nil : 200_000,
                inputAboveThreshold: number(longContext?["input"]),
                cachedInputAboveThreshold: number(longContext?["cache_read"]),
                outputAboveThreshold: number(longContext?["output"])
            )
        }
        return LocalCodexPricingCatalog(prices: prices)
    }

    /// 为首次启动和断网场景提供已知 OpenAI 标准价；未知模型不猜测费用。
    static func fallbackPrice(for model: String) -> Price? {
        let normalized = normalizedModel(model)
        let table: [(String, Double, Double, Double)] = [
            ("gpt-5.5-pro", 30, 30, 180),
            ("gpt-5.5", 5, 0.5, 30),
            ("gpt-5.4-mini", 0.75, 0.075, 4.5),
            ("gpt-5.4-nano", 0.2, 0.02, 1.25),
            ("gpt-5.4-pro", 30, 30, 180),
            ("gpt-5.4", 2.5, 0.25, 15),
            ("gpt-5.3-codex", 1.75, 0.175, 14),
            ("gpt-5.2-codex", 1.75, 0.175, 14),
            ("gpt-5.2", 1.75, 0.175, 14),
            ("gpt-5.1", 1.25, 0.125, 10),
            ("gpt-5-codex", 1.25, 0.125, 10),
            ("gpt-5", 1.25, 0.125, 10)
        ]
        guard let match = table.first(where: { normalized == $0.0 || normalized.hasPrefix($0.0 + "-") }) else {
            return nil
        }
        return Price(
            inputPerMillion: match.1,
            cachedInputPerMillion: match.2,
            outputPerMillion: match.3,
            thresholdTokens: nil,
            inputAboveThreshold: nil,
            cachedInputAboveThreshold: nil,
            outputAboveThreshold: nil
        )
    }

    /// 去除 provider 前缀并统一大小写，保留模型版本信息供稳定匹配。
    private static func normalizedModel(_ raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.hasPrefix("openai/") ? String(lowered.dropFirst("openai/".count)) : lowered
    }

    /// 返回 models.dev 价格缓存路径，不与 Widget 共享原始目录。
    private static func cacheURL() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("CodexUsage/model-pricing/models-dev-v1.json")
    }

    /// 将 JSON 价格字段转换为 Double。
    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
