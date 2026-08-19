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
    private let fallbackCounts: LocalCodexTaskCounts?

    var activeCount: Int { fallbackCounts?.active ?? count(.active) }
    var pendingCount: Int { fallbackCounts?.pending ?? count(.pending) }
    var scheduledCount: Int { fallbackCounts?.scheduled ?? count(.scheduled) }
    var doneCount: Int { fallbackCounts?.done ?? count(.done) }

    /// 使用实时任务条目计数；仅恢复共享缓存时才传入不含标题的汇总计数。
    init(items: [LocalCodexTaskItem], fallbackCounts: LocalCodexTaskCounts? = nil) {
        self.items = items
        self.fallbackCounts = fallbackCounts
    }

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
    private let usageCacheURL: URL
    private let query: Query

    init(
        now: @escaping @Sendable () -> Date = Date.init,
        databaseURL: URL? = nil,
        sessionIndexURL: URL? = nil,
        automationFiles: [URL]? = nil,
        diagnostics: AppDiagnosticLog = .shared,
        usageCacheURL: URL? = nil,
        query: @escaping Query = LocalCodexUsageReader.runQuery
    ) {
        self.now = now
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL()
        self.sessionIndexURL = sessionIndexURL
            ?? (databaseURL?.deletingLastPathComponent().appendingPathComponent("session_index.jsonl"))
            ?? Self.defaultSessionIndexURL()
        self.automationFiles = automationFiles ?? Self.defaultAutomationFiles()
        self.diagnostics = diagnostics
        self.usageCacheURL = usageCacheURL
            ?? diagnostics.directoryURL.appendingPathComponent("LocalUsageCache.json")
        self.query = query
    }

    /// 在后台读取统计；数据库缺失、schema 不兼容或 sqlite3 执行失败时返回 nil。
    func load() async -> LocalCodexUsageSnapshot? {
        diagnostics.info(
            "开始读取本机统计；应用版本=\(Self.applicationVersionDescription())",
            category: Self.diagnosticCategory
        )
        let snapshot = await Task.detached(priority: .utility) {
            loadSynchronously()
        }.value
        if snapshot == nil {
            diagnostics.error("本机统计读取结束：未生成可用快照", category: Self.diagnosticCategory)
        }
        return snapshot
    }

    /// 执行聚合查询并组装内存快照；价格仅使用带生效日的内置官方口径。
    private func loadSynchronously() -> LocalCodexUsageSnapshot? {
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
            for: totalsSQL(),
            databaseURL: databaseURL,
            context: "总览"
        ) else { return nil }
        guard let total = totals.first else {
            diagnostics.error("总览查询未返回聚合行；数据库 schema 可能不兼容", category: Self.diagnosticCategory)
            return nil
        }
        guard let usageSources: [UsageSourceRow] = rows(
            for: usageSourcesSQL(),
            databaseURL: databaseURL,
            context: "用量事件索引"
        ) else { return nil }
        let usage = aggregateUsage(
            sources: usageSources,
            historyStart: historyStart,
            sevenDayStart: sevenDayStart,
            todayStart: todayStart,
            monthStart: monthStart,
            calendar: calendar
        )
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

        let mappedProjects = usage.projects.map { Self.projectUsage(from: $0) }
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
        let summary = LocalCodexUsageSummary(
            fetchedAt: fetchedAt,
            todayTokens: usage.todayTokens,
            sevenDayTokens: usage.sevenDayTokens,
            lifetimeTokens: usage.lifetimeTokens,
            threadCount: total.threadCount,
            projects: projects,
            taskCounts: LocalCodexTaskCounts(
                active: taskBoard.activeCount,
                pending: taskBoard.pendingCount,
                scheduled: taskBoard.scheduledCount,
                done: taskBoard.doneCount
            ),
            dailyBuckets: Self.dailyBuckets(
                from: usage.dailyRows,
                endingAt: todayStart,
                calendar: calendar
            ),
            monthCost: usage.monthCost,
            hasIncompleteUsage: usage.hasIncompleteUsage ? true : nil
        )
        diagnostics.info(
            "本机统计读取成功；线程=\(total.threadCount)；项目=\(projects.count)；日聚合=\(usage.dailyRows.count)；事件会话=\(usageSources.count)",
            category: Self.diagnosticCategory
        )
        return LocalCodexUsageSnapshot(summary: summary, taskBoard: taskBoard)
    }

    /// 将稀疏事件日聚合补成连续 190 天；费用只展示已完整识别模型价格的日期。
    private static func dailyBuckets(
        from rows: [DailyUsageRow],
        endingAt endDate: Date,
        calendar: Calendar
    ) -> [LocalCodexDailyUsageBucket] {
        let rowsByDay = Dictionary(uniqueKeysWithValues: rows.map { ($0.day, $0) })
        let identifierFormatter = DateFormatter()
        identifierFormatter.calendar = calendar
        identifierFormatter.locale = Locale(identifier: "en_US_POSIX")
        identifierFormatter.timeZone = calendar.timeZone
        identifierFormatter.dateFormat = "yyyy-MM-dd"
        let labelFormatter = DateFormatter()
        labelFormatter.calendar = calendar
        labelFormatter.locale = Locale(identifier: "en_US_POSIX")
        labelFormatter.timeZone = calendar.timeZone
        labelFormatter.dateFormat = "MM/dd"

        return (0..<190).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - 189, to: endDate) else { return nil }
            let identifier = identifierFormatter.string(from: date)
            let row = rowsByDay[identifier]
            return LocalCodexDailyUsageBucket(
                id: identifier,
                label: labelFormatter.string(from: date),
                tokens: row?.tokens ?? 0,
                estimatedCostUSD: row?.estimatedCostUSD
            )
        }
    }

    /// 从 rollout 增量事件统一生成时间段、项目和费用统计；无法解析的日志跳过后继续输出可用数据。
    private func aggregateUsage(
        sources: [UsageSourceRow],
        historyStart: Date,
        sevenDayStart: Date,
        todayStart: Date,
        monthStart: Date,
        calendar: Calendar
    ) -> LocalUsageAggregation {
        let dayFormatter = Self.dayFormatter(calendar: calendar)
        let historyDay = dayFormatter.string(from: historyStart)
        let sevenDay = dayFormatter.string(from: sevenDayStart)
        let today = dayFormatter.string(from: todayStart)
        let monthDay = dayFormatter.string(from: monthStart)
        var cache = loadUsageCache(timeZoneIdentifier: calendar.timeZone.identifier)
        let sourcePaths = Set(sources.map(\.rolloutPath))
        cache.sessions = cache.sessions.filter { sourcePaths.contains($0.key) }
        var sourcesByThreadID: [String: UsageSourceRow] = [:]
        var forkParentIDByPath: [String: String] = [:]
        for source in sources {
            sourcesByThreadID[source.threadID] = source
            if let parentID = Self.forkParentID(at: URL(fileURLWithPath: source.rolloutPath)) {
                forkParentIDByPath[source.rolloutPath] = parentID
            }
        }
        let missingForkParents = forkParentIDByPath.values.filter { sourcesByThreadID[$0] == nil }
        if !missingForkParents.isEmpty {
            diagnostics.warning(
                "fork 父会话缺失，按子会话原始事件继续统计；缺失父会话=\(Set(missingForkParents).count)",
                category: Self.diagnosticCategory
            )
        }
        let availableForkParentIDByPath = forkParentIDByPath.filter { sourcesByThreadID[$0.value] != nil }
        let forkEventPaths = Set(
            availableForkParentIDByPath.flatMap { childPath, parentID in
                [childPath, sourcesByThreadID[parentID]!.rolloutPath]
            }
        )
        var incompletePaths: [String] = []
        var sqliteLifetimeFallbackPaths = Set<String>()

        for source in sources {
            let url = URL(fileURLWithPath: source.rolloutPath)
            guard let entry = Self.updatedUsageCacheEntry(
                at: url,
                previous: cache.sessions[source.rolloutPath],
                collectEvents: forkEventPaths.contains(source.rolloutPath),
                historyDay: historyDay,
                dayFormatter: dayFormatter
            ) else {
                if source.tokensUsed > 0 {
                    incompletePaths.append(source.rolloutPath)
                    sqliteLifetimeFallbackPaths.insert(source.rolloutPath)
                }
                continue
            }
            cache.sessions[source.rolloutPath] = entry
            if source.tokensUsed > 0, entry.latestTotal == nil {
                incompletePaths.append(source.rolloutPath)
                sqliteLifetimeFallbackPaths.insert(source.rolloutPath)
            }
        }
        saveUsageCache(cache)
        if !incompletePaths.isEmpty {
            diagnostics.warning(
                "rollout 用量事件不完整，按可解析事件继续统计；缺失会话=\(incompletePaths.count)",
                category: Self.diagnosticCategory
            )
        }
        let incompleteForkPaths = sqliteLifetimeFallbackPaths.intersection(forkParentIDByPath.keys)
        if !incompleteForkPaths.isEmpty {
            diagnostics.warning(
                "fork rollout 不完整，累计仅采用已解析事件；会话=\(incompleteForkPaths.count)",
                category: Self.diagnosticCategory
            )
        }
        let forkExclusions = Self.forkExclusions(
            parentIDByChildPath: availableForkParentIDByPath,
            sourcesByThreadID: sourcesByThreadID,
            cache: cache
        )

        var daily: [String: SessionTokenUsage] = [:]
        var dailyCosts: [String: Double] = [:]
        var unpricedDays = Set<String>()
        var projects: [String: ProjectAccumulator] = [:]
        var pricedMonthUsage = SessionTokenUsage.zero
        var monthCost = 0.0
        var monthSessionCount = 0
        var pricedMonthSessionCount = 0
        var lifetimeTokens: Int64 = 0

        for source in sources {
            let entry = cache.sessions[source.rolloutPath]
            let exclusion = forkExclusions[source.rolloutPath] ?? .zero
            // SQLite 只有会话总量，没有逐日拆分；rollout 不完整时只兜底累计值，时间趋势仍使用可解析事件。
            if sqliteLifetimeFallbackPaths.contains(source.rolloutPath) {
                if incompleteForkPaths.contains(source.rolloutPath) {
                    lifetimeTokens += entry?.lifetimeUsage.subtracting(exclusion.lifetimeUsage).total ?? 0
                } else {
                    lifetimeTokens += source.tokensUsed
                }
            } else if let entry {
                lifetimeTokens += entry.lifetimeUsage.subtracting(exclusion.lifetimeUsage).total
            }
            guard let entry else { continue }
            var sourceSevenDayUsage = SessionTokenUsage.zero
            var sourceMonthUsage = SessionTokenUsage.zero
            var sourceMonthPricedUsage = SessionTokenUsage.zero
            var sourceMonthCost = 0.0
            var sourceMonthFullyPriced = true
            for event in entry.recentEvents where event.sequence >= exclusion.prefixLength {
                guard let day = event.day, day >= historyDay, day <= today else { continue }
                daily[day, default: .zero].add(event.usage)
                let model = event.model ?? source.model
                let price = LocalCodexPricing.price(for: model, on: day)
                if let price {
                    let cost = Self.estimatedCost(for: event.usage, price: price)
                    dailyCosts[day, default: 0] += cost
                    if day >= monthDay {
                        sourceMonthCost += cost
                        sourceMonthPricedUsage.add(event.usage)
                    }
                } else if event.usage.total > 0 {
                    unpricedDays.insert(day)
                    if day >= monthDay { sourceMonthFullyPriced = false }
                }
                if day >= sevenDay { sourceSevenDayUsage.add(event.usage) }
                if day >= monthDay { sourceMonthUsage.add(event.usage) }
            }
            if sourceSevenDayUsage.total > 0 {
                projects[source.cwd, default: .init()].add(
                    tokens: sourceSevenDayUsage.total,
                    threadID: source.rolloutPath
                )
            }
            if sourceMonthUsage.total > 0 {
                monthSessionCount += 1
                if sourceMonthFullyPriced {
                    pricedMonthSessionCount += 1
                }
                if sourceMonthPricedUsage.total > 0 {
                    pricedMonthUsage.add(sourceMonthPricedUsage)
                    monthCost += sourceMonthCost
                }
            }
        }

        let dailyRows = daily.map { day, usage in
            DailyUsageRow(
                day: day,
                tokens: usage.total,
                estimatedCostUSD: unpricedDays.contains(day) ? nil : dailyCosts[day]
            )
        }.sorted { $0.day < $1.day }
        let projectRows = projects.map { cwd, value in
            ProjectRow(cwd: cwd, tokens: value.tokens, threadCount: value.threadIDs.count)
        }
        let trustedMonthCost = monthSessionCount > 0 && pricedMonthUsage.total > 0
            ? LocalCodexCostSummary(
                inputTokens: pricedMonthUsage.input,
                cachedInputTokens: pricedMonthUsage.cachedInput,
                outputTokens: pricedMonthUsage.output,
                estimatedCostUSD: monthCost,
                pricedSessionCount: pricedMonthSessionCount,
                sessionCount: monthSessionCount
            )
            : nil
        return LocalUsageAggregation(
            todayTokens: daily[today]?.total ?? 0,
            sevenDayTokens: daily
                .filter { $0.key >= sevenDay && $0.key <= today }
                .reduce(Int64(0)) { $0 + $1.value.total },
            lifetimeTokens: lifetimeTokens,
            projects: projectRows,
            dailyRows: dailyRows,
            monthCost: trustedMonthCost,
            hasIncompleteUsage: !incompletePaths.isEmpty
                || (monthSessionCount > 0 && pricedMonthSessionCount < monthSessionCount)
        )
    }

    /// 读取增量缓存；损坏或时区变化时从空缓存重建，避免沿用错误日期边界。
    private func loadUsageCache(timeZoneIdentifier: String) -> LocalUsageCache {
        guard let data = try? Data(contentsOf: usageCacheURL),
              let cache = try? JSONDecoder().decode(LocalUsageCache.self, from: data),
              cache.version == LocalUsageCache.currentVersion,
              cache.timeZoneIdentifier == timeZoneIdentifier
        else { return LocalUsageCache(timeZoneIdentifier: timeZoneIdentifier) }
        return cache
    }

    /// 原子保存已验证到文件末尾的缓存；保存失败只影响下次扫描性能，不改变本次统计结果。
    private func saveUsageCache(_ cache: LocalUsageCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        do {
            try FileManager.default.createDirectory(
                at: usageCacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: usageCacheURL, options: .atomic)
        } catch {
            diagnostics.warning("本机用量缓存保存失败；错误=\(error.localizedDescription)", category: Self.diagnosticCategory)
        }
    }

    /// 从上次完整换行偏移继续解析 JSONL；文件被截断时自动重建该会话缓存。
    private static func updatedUsageCacheEntry(
        at url: URL,
        previous: SessionUsageCache?,
        collectEvents: Bool,
        historyDay: String,
        dayFormatter: DateFormatter
    ) -> SessionUsageCache? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd() else { return nil }
        var entry = previous ?? SessionUsageCache(collectsEvents: collectEvents)
        if collectEvents, !entry.collectsEvents {
            entry = SessionUsageCache(collectsEvents: true)
        }
        // ponytail: Codex rollout 当前为追加写；若未来支持同路径原地改写，应增加文件标识并强制重建缓存。
        if entry.readOffset > fileSize { entry = SessionUsageCache(collectsEvents: collectEvents) }
        guard entry.readOffset < fileSize else {
            entry.recentEvents = entry.recentEvents.filter { $0.day.map { $0 >= historyDay } == true }
            return entry
        }
        guard (try? handle.seek(toOffset: entry.readOffset)) != nil else { return nil }

        let fractionalTimestampFormatter = ISO8601DateFormatter()
        fractionalTimestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestampFormatter = ISO8601DateFormatter()
        var pending = Data()
        var committedOffset = entry.readOffset
        while let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            pending.append(chunk)
            var lineStart = pending.startIndex
            while lineStart < pending.endIndex,
                  let newline = pending[lineStart...].firstIndex(of: 0x0A)
            {
                if newline > lineStart {
                    let line = pending[lineStart..<newline]
                    let prefix = String(decoding: line.prefix(512), as: UTF8.self)
                    if prefix.contains("\"token_count\"") || prefix.contains("\"turn_context\"") {
                        parseUsageLine(
                            Data(line),
                            entry: &entry,
                            historyDay: historyDay,
                            dayFormatter: dayFormatter,
                            fractionalTimestampFormatter: fractionalTimestampFormatter,
                            timestampFormatter: timestampFormatter
                        )
                    }
                }
                committedOffset += UInt64(pending.distance(from: lineStart, to: newline) + 1)
                lineStart = pending.index(after: newline)
            }
            if lineStart > pending.startIndex { pending.removeSubrange(..<lineStart) }
        }
        if !pending.isEmpty, (try? JSONSerialization.jsonObject(with: pending)) != nil {
            parseUsageLine(
                pending,
                entry: &entry,
                historyDay: historyDay,
                dayFormatter: dayFormatter,
                fractionalTimestampFormatter: fractionalTimestampFormatter,
                timestampFormatter: timestampFormatter
            )
            committedOffset += UInt64(pending.count)
        }
        entry.readOffset = committedOffset
        entry.recentEvents = entry.recentEvents.filter { $0.day.map { $0 >= historyDay } == true }
        return entry
    }

    /// 解析模型上下文和 token_count；每个增量绑定当时模型，避免用线程最终模型回填历史费用。
    private static func parseUsageLine(
        _ data: Data,
        entry: inout SessionUsageCache,
        historyDay: String,
        dayFormatter: DateFormatter,
        fractionalTimestampFormatter: ISO8601DateFormatter,
        timestampFormatter: ISO8601DateFormatter
    ) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any]
        else { return }
        if object["type"] as? String == "turn_context" {
            entry.activeModel = (payload["model"] as? String).flatMap(normalizedModelName)
            return
        }
        guard object["type"] as? String == "event_msg",
              let timestamp = object["timestamp"] as? String,
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any]
        else { return }
        let cumulative = (info["total_token_usage"] as? [String: Any]).map(SessionTokenSample.init(json:))
        let lastUsage = (info["last_token_usage"] as? [String: Any]).map(SessionTokenSample.init(json:))
        let identity = SessionTokenEventIdentity(cumulative: cumulative, lastUsage: lastUsage)
        guard let delta = normalizedDelta(
            cumulative: cumulative,
            lastUsage: lastUsage,
            latestTotal: &entry.latestTotal
        ) else { return }
        entry.lifetimeUsage.add(delta)
        let date = fractionalTimestampFormatter.date(from: timestamp) ?? timestampFormatter.date(from: timestamp)
        let day = date.map(dayFormatter.string(from:))
        let event = SessionUsageEvent(
            identity: identity,
            day: day,
            model: entry.activeModel,
            usage: delta,
            sequence: entry.nextEventSequence
        )
        entry.nextEventSequence += 1
        if entry.collectsEvents {
            entry.events.append(event)
        }
        if day.map({ $0 >= historyDay }) == true { entry.recentEvents.append(event) }
    }

    /// 清理日志模型名中的空白；空值保留为 nil，后续才能明确回退到 SQLite 线程模型。
    private static func normalizedModelName(_ raw: String) -> String? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    /// 按累计高水位生成可信增量；计数器重置时保留新周期首个事件，累计未增长时拒绝 last_token_usage。
    private static func normalizedDelta(
        cumulative: SessionTokenSample?,
        lastUsage: SessionTokenSample?,
        latestTotal: inout SessionTokenUsage?
    ) -> SessionTokenUsage? {
        let lastDelta = lastUsage.flatMap { sample in
            sample.hasNegativeValue ? nil : sample.snapshot().nonzero
        }
        guard let cumulative, !cumulative.hasNegativeValue else { return lastDelta }

        guard let previous = latestTotal else {
            let current = cumulative.snapshot()
            latestTotal = current
            return lastDelta ?? current.nonzero
        }
        if cumulative.isConfirmedReset(comparedWith: previous) {
            let current = cumulative.snapshot()
            latestTotal = current
            return lastDelta ?? current.nonzero
        }

        let observed = cumulative.snapshot(missingFrom: previous)
        let highWater = previous.componentwiseMaximum(with: observed)
        let fallback = highWater.increment(after: previous)
        latestTotal = highWater
        guard !fallback.isZero else { return nil }
        return lastDelta ?? fallback
    }

    /// 从 rollout 首个 session_meta 读取父会话；兼容直接 fork 字段和旧版子任务 source 结构。
    private static func forkParentID(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var pending = Data()
        let maximumHeaderBytes = 8 * 1_024 * 1_024
        while pending.count < maximumHeaderBytes,
              let chunk = try? handle.read(upToCount: 65_536),
              !chunk.isEmpty
        {
            pending.append(chunk)
            guard let newline = pending.firstIndex(of: 0x0A) else { continue }
            let line = pending[..<newline]
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["type"] as? String == "session_meta",
                  let payload = object["payload"] as? [String: Any]
            else { return nil }
            if let directParentID = payload["forked_from_id"] as? String, !directParentID.isEmpty {
                return directParentID
            }
            let source = payload["source"] as? [String: Any]
            let subagent = source?["subagent"] as? [String: Any]
            let spawn = subagent?["thread_spawn"] as? [String: Any]
            return (spawn?["parent_thread_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        // ponytail: session_meta 超过 8 MB 时按非 fork 处理；出现真实样本后再改成无上限流式解码。
        return nil
    }

    /// 在归一化事件序列上匹配子会话继承前缀，并返回需要排除的分日与累计用量。
    private static func forkExclusions(
        parentIDByChildPath: [String: String],
        sourcesByThreadID: [String: UsageSourceRow],
        cache: LocalUsageCache
    ) -> [String: SessionUsageExclusion] {
        var result: [String: SessionUsageExclusion] = [:]
        for (childPath, parentID) in parentIDByChildPath {
            guard let parentPath = sourcesByThreadID[parentID]?.rolloutPath,
                  let child = cache.sessions[childPath], child.collectsEvents,
                  let parent = cache.sessions[parentPath], parent.collectsEvents
            else { continue }
            let prefixLength = inheritedPrefixLength(child: child.events, parent: parent.events)
            guard prefixLength > 0 else { continue }
            var exclusion = SessionUsageExclusion(prefixLength: prefixLength)
            for event in child.events.prefix(prefixLength) {
                exclusion.lifetimeUsage.add(event.usage)
            }
            result[childPath] = exclusion
        }
        return result
    }

    /// 返回子会话开头与父会话任一连续片段的最长匹配长度，兼容旧版只复制父会话尾段的子任务日志。
    private static func inheritedPrefixLength(
        child: [SessionUsageEvent],
        parent: [SessionUsageEvent]
    ) -> Int {
        guard let firstChildEvent = child.first else { return 0 }
        var longest = 0
        for parentStart in parent.indices where parent[parentStart].identity == firstChildEvent.identity {
            var length = 0
            while length < child.count,
                  parentStart + length < parent.count,
                  child[length].identity == parent[parentStart + length].identity
            {
                length += 1
            }
            longest = max(longest, length)
        }
        return longest
    }

    /// 创建跟随当前日历时区的稳定日期键格式器。
    private static func dayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// 按事件级单价计算 API 等效金额；输入超阈值时整个请求使用长上下文价格。
    private static func estimatedCost(
        for tokens: SessionTokenUsage,
        price: LocalCodexPricing.Price
    ) -> Double {
        let billableCached = min(tokens.cachedInput, tokens.input)
        let uncached = max(0, tokens.input - billableCached)
        let usesLongContextPrice = price.thresholdTokens.map { tokens.input > $0 } == true
        let inputPrice = usesLongContextPrice ? price.inputAboveThreshold ?? price.inputPerMillion : price.inputPerMillion
        let cachedPrice = usesLongContextPrice
            ? price.cachedInputAboveThreshold ?? price.cachedInputPerMillion
            : price.cachedInputPerMillion
        let outputPrice = usesLongContextPrice ? price.outputAboveThreshold ?? price.outputPerMillion : price.outputPerMillion
        return Double(uncached) / 1_000_000 * inputPrice
            + Double(billableCached) / 1_000_000 * cachedPrice
            + Double(tokens.output) / 1_000_000 * outputPrice
    }

    /// 将 JSON 数字安全转换为非负 Int64。
    fileprivate static func int64(_ value: Any?) -> Int64 {
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

    /// 生成不带时间归属的累计 token 与线程总览查询。
    private func totalsSQL() -> String {
        return """
        SELECT COUNT(*) AS threadCount,
               COALESCE(MAX(CASE WHEN COALESCE(recency_at, 0) > updated_at THEN recency_at ELSE updated_at END), 0) AS lastUpdatedAt
        FROM threads;
        """
    }

    /// 枚举全部 rollout；缓存保留全量有效累计，同时只持久化近半年的日聚合。
    private func usageSourcesSQL() -> String {
        return """
        SELECT id AS threadID, rollout_path AS rolloutPath, COALESCE(cwd, '') AS cwd, COALESCE(model, '') AS model,
               COALESCE(tokens_used, 0) AS tokensUsed
        FROM threads
        WHERE rollout_path IS NOT NULL AND rollout_path <> '';
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
    let threadCount: Int
    let lastUpdatedAt: TimeInterval
}

/// sqlite3 项目聚合行。
private struct ProjectRow: Decodable {
    let cwd: String
    let tokens: Int64
    let threadCount: Int
}

/// SQLite 中供 rollout 增量聚合使用的线程索引。
private struct UsageSourceRow: Decodable {
    let threadID: String
    let rolloutPath: String
    let cwd: String
    let model: String
    let tokensUsed: Int64
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

/// rollout 事件生成的每日 token 与可信费用聚合。
private struct DailyUsageRow {
    let day: String
    let tokens: Int64
    let estimatedCostUSD: Double?
}

/// 保留 token_count 原始可选计数，用于识别负值、累计重置和 fork 事件身份。
private struct SessionTokenSample: Codable, Equatable, Sendable {
    let input: Int64?
    let cachedInput: Int64?
    let output: Int64?
    let reasoningOutput: Int64?
    let totalTokens: Int64?

    var hasNegativeValue: Bool {
        [input, cachedInput, output, reasoningOutput, totalTokens]
            .compactMap { $0 }
            .contains { $0 < 0 }
    }

    /// 从 JSON 保留字段缺失与负值语义，归一化层再决定是否接受该样本。
    init(json: [String: Any]) {
        input = (json["input_tokens"] as? NSNumber)?.int64Value
        cachedInput = (json["cached_input_tokens"] as? NSNumber)?.int64Value
        output = (json["output_tokens"] as? NSNumber)?.int64Value
        reasoningOutput = (json["reasoning_output_tokens"] as? NSNumber)?.int64Value
        totalTokens = (json["total_tokens"] as? NSNumber)?.int64Value
    }

    /// 将缺失字段沿用上一高水位，并把已验证样本转换成聚合所需的三类 Token。
    func snapshot(missingFrom previous: SessionTokenUsage = .zero) -> SessionTokenUsage {
        SessionTokenUsage(
            input: input ?? previous.input,
            cachedInput: cachedInput ?? previous.cachedInput,
            output: output ?? previous.output,
            reasoningOutput: reasoningOutput ?? previous.reasoningOutput,
            reportedTotal: totalTokens ?? previous.reportedTotal
        )
    }

    /// 只有规范总量和主输入计数同时下降时才确认重置，避免缓存分类调整误触发新周期。
    func isConfirmedReset(comparedWith previous: SessionTokenUsage) -> Bool {
        guard let totalTokens, let input else { return false }
        return totalTokens >= 0
            && input >= 0
            && totalTokens < previous.reportedTotal
            && input < previous.input
    }
}

/// 使用原始累计与单次计数组成 fork 前缀事件身份；时间戳不参与继承判断。
private struct SessionTokenEventIdentity: Codable, Equatable, Sendable {
    let cumulative: SessionTokenSample?
    let lastUsage: SessionTokenSample?
}

/// 保存需要参与 fork 去重的归一化事件；只为 fork 子会话及其父会话持久化。
private struct SessionUsageEvent: Codable, Sendable {
    let identity: SessionTokenEventIdentity
    let day: String?
    let model: String?
    let usage: SessionTokenUsage
    let sequence: Int
}

/// 描述单个事件或时间段的 token 拆分；总量优先采用事件规范字段，旧日志缺失时回退为输入加输出。
private struct SessionTokenUsage: Codable, Sendable {
    let input: Int64
    let cachedInput: Int64
    let output: Int64
    let reasoningOutput: Int64
    let reportedTotal: Int64

    static let zero = SessionTokenUsage(
        input: 0,
        cachedInput: 0,
        output: 0,
        reasoningOutput: 0,
        reportedTotal: 0
    )

    var total: Int64 { reportedTotal > 0 ? reportedTotal : input + output }
    var isZero: Bool {
        input == 0
            && cachedInput == 0
            && output == 0
            && reasoningOutput == 0
            && reportedTotal == 0
    }
    var nonzero: SessionTokenUsage? { isZero ? nil : self }

    init(
        input: Int64,
        cachedInput: Int64,
        output: Int64,
        reasoningOutput: Int64 = 0,
        reportedTotal: Int64? = nil
    ) {
        self.input = max(0, input)
        self.cachedInput = max(0, cachedInput)
        self.output = max(0, output)
        self.reasoningOutput = max(0, reasoningOutput)
        self.reportedTotal = max(0, reportedTotal ?? input + output)
    }

    /// 累加另一个事件增量。
    mutating func add(_ other: SessionTokenUsage) {
        self = SessionTokenUsage(
            input: input + other.input,
            cachedInput: cachedInput + other.cachedInput,
            output: output + other.output,
            reasoningOutput: reasoningOutput + other.reasoningOutput,
            reportedTotal: reportedTotal + other.reportedTotal
        )
    }

    /// 逐字段保留累计最大值，防止临时回退后的恢复量再次被统计。
    func componentwiseMaximum(with other: SessionTokenUsage) -> SessionTokenUsage {
        SessionTokenUsage(
            input: max(input, other.input),
            cachedInput: max(cachedInput, other.cachedInput),
            output: max(output, other.output),
            reasoningOutput: max(reasoningOutput, other.reasoningOutput),
            reportedTotal: max(reportedTotal, other.reportedTotal)
        )
    }

    /// 扣除已验证的 fork 继承用量；异常越界时按零收敛，避免生成负统计。
    func subtracting(_ other: SessionTokenUsage) -> SessionTokenUsage {
        SessionTokenUsage(
            input: max(0, input - other.input),
            cachedInput: max(0, cachedInput - other.cachedInput),
            output: max(0, output - other.output),
            reasoningOutput: max(0, reasoningOutput - other.reasoningOutput),
            reportedTotal: max(0, reportedTotal - other.reportedTotal)
        )
    }

    /// 旧日志缺少 last_token_usage 时，以相邻累计值差作为兼容增量。
    func increment(after previous: SessionTokenUsage?) -> SessionTokenUsage {
        guard let previous, total >= previous.total else { return self }
        return SessionTokenUsage(
            input: max(0, input - previous.input),
            cachedInput: max(0, cachedInput - previous.cachedInput),
            output: max(0, output - previous.output),
            reasoningOutput: max(0, reasoningOutput - previous.reasoningOutput),
            reportedTotal: max(0, reportedTotal - previous.reportedTotal)
        )
    }
}

/// 单个 rollout 的增量扫描进度和近半年事件，避免每次刷新重读大型历史日志。
private struct SessionUsageCache: Codable, Sendable {
    var readOffset: UInt64 = 0
    var latestTotal: SessionTokenUsage?
    var lifetimeUsage = SessionTokenUsage.zero
    var activeModel: String?
    var nextEventSequence = 0
    var recentEvents: [SessionUsageEvent] = []
    var collectsEvents: Bool
    var events: [SessionUsageEvent] = []

    /// 新缓存只为 fork 关系保存全量事件；普通会话仅保留近半年计价事件。
    init(collectsEvents: Bool = false) {
        self.collectsEvents = collectsEvents
    }
}

/// 所有 rollout 的持久化增量缓存；时区改变时必须整体重建日期键。
private struct LocalUsageCache: Codable, Sendable {
    static let currentVersion = 5

    var version = currentVersion
    let timeZoneIdentifier: String
    var sessions: [String: SessionUsageCache] = [:]
}

/// 汇总一个 fork 子会话应排除的继承用量，供累计、分日、项目和费用共用同一口径。
private struct SessionUsageExclusion {
    static let zero = SessionUsageExclusion(prefixLength: 0)

    let prefixLength: Int
    var lifetimeUsage = SessionTokenUsage.zero
}

/// 项目近七天用量的内部累加器，线程集合避免重复路径被多算。
private struct ProjectAccumulator {
    var tokens: Int64 = 0
    var threadIDs = Set<String>()

    /// 累加单个线程在时间窗内的用量。
    mutating func add(tokens: Int64, threadID: String) {
        self.tokens += tokens
        threadIDs.insert(threadID)
    }
}

/// rollout 事件完成完整性校验后交给摘要层的统一结果。
private struct LocalUsageAggregation {
    let todayTokens: Int64
    let sevenDayTokens: Int64
    let lifetimeTokens: Int64
    let projects: [ProjectRow]
    let dailyRows: [DailyUsageRow]
    let monthCost: LocalCodexCostSummary?
    let hasIncompleteUsage: Bool
}

/// 保存已核对的 OpenAI 模型历史价格；未知模型拒绝猜价。
private enum LocalCodexPricing {
    /// 描述每百万 token 的美元单价，可选保存长上下文价格。
    struct Price: Sendable {
        let inputPerMillion: Double
        let cachedInputPerMillion: Double
        let outputPerMillion: Double
        let thresholdTokens: Int?
        let inputAboveThreshold: Double?
        let cachedInputAboveThreshold: Double?
        let outputAboveThreshold: Double?
    }

    /// 为已知模型提供按生效日区分的 OpenAI 官方价；未知模型不猜测费用。
    static func price(for model: String, on day: String? = nil) -> Price? {
        let normalized = normalizedModel(model)
        let usesReducedGPT56Price = (day ?? "9999-12-31") >= "2026-07-30"
        if normalized == "gpt-5.6" || normalized.hasPrefix("gpt-5.6-sol") {
            return price(input: 5, cachedInput: 0.5, output: 30, longContextMultiplier: (2, 2, 1.5))
        }
        if normalized == "gpt-5.6-terra" || normalized.hasPrefix("gpt-5.6-terra-") {
            return usesReducedGPT56Price
                ? price(input: 2, cachedInput: 0.2, output: 12, longContextMultiplier: (2, 2, 1.5))
                : price(input: 2.5, cachedInput: 0.25, output: 15, longContextMultiplier: (2, 2, 1.5))
        }
        if normalized == "gpt-5.6-luna" || normalized.hasPrefix("gpt-5.6-luna-") {
            return usesReducedGPT56Price
                ? price(input: 0.2, cachedInput: 0.02, output: 1.2, longContextMultiplier: (2, 2, 1.5))
                : price(input: 1, cachedInput: 0.1, output: 6, longContextMultiplier: (2, 2, 1.5))
        }
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
        return price(input: match.1, cachedInput: match.2, output: match.3)
    }

    /// 构建标准或长上下文价格；GPT-5.6 的阈值为单次输入 272K token。
    private static func price(
        input: Double,
        cachedInput: Double,
        output: Double,
        longContextMultiplier: (input: Double, cachedInput: Double, output: Double)? = nil
    ) -> Price {
        Price(
            inputPerMillion: input,
            cachedInputPerMillion: cachedInput,
            outputPerMillion: output,
            thresholdTokens: longContextMultiplier == nil ? nil : 272_000,
            inputAboveThreshold: longContextMultiplier.map { input * $0.input },
            cachedInputAboveThreshold: longContextMultiplier.map { cachedInput * $0.cachedInput },
            outputAboveThreshold: longContextMultiplier.map { output * $0.output }
        )
    }

    /// 去除 provider 前缀并统一大小写，保留模型版本信息供稳定匹配。
    private static func normalizedModel(_ raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.hasPrefix("openai/") ? String(lowered.dropFirst("openai/".count)) : lowered
    }

}
