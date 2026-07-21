import CodexMeterShared
import OSLog
import SwiftUI
import WidgetKit

struct CodexMeterWidget: Widget {
    // 兼容标识：已添加到桌面的旧 Widget 依赖该 kind，正式改名后仍不可修改。
    let kind = "CodexUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexMeterTimelineProvider()) { entry in
            CodexMeterWidgetView(entry: entry)
        }
        .configurationDisplayName("CodexMeter")
        .description(AppLocalization.string("显示 Codex 5 小时与 7 天窗口的最近同步余量。"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// 提供独立的本机统计桌面 Widget，读取主应用写入的隐私收敛摘要。
struct LocalCodexUsageWidget: Widget {
    let kind = "CodexLocalUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexMeterTimelineProvider()) { entry in
            LocalCodexUsageWidgetView(entry: entry)
        }
        .configurationDisplayName(AppLocalization.string("Codex 用量看板"))
        .description(AppLocalization.string("统一展示额度、Token、费用、项目和任务状态。"))
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct CodexMeterEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

struct CodexMeterTimelineProvider: TimelineProvider {
    private let store = UsageSnapshotStore()
    private let logger = Logger(subsystem: "com.jinsihou.CodexUsage", category: "Widget")

    func placeholder(in context: Context) -> CodexMeterEntry {
        CodexMeterEntry(date: Date(), snapshot: UsageSnapshot(
            fetchedAt: Date(),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(usedPercent: 17, windowDurationMins: 300, resetsAt: nil),
                secondary: RateLimitWindow(usedPercent: 11, windowDurationMins: 10_080, resetsAt: nil),
                credits: CreditsSnapshot(hasCredits: false, unlimited: false, balance: "0"),
                planType: "prolite",
                rateLimitReachedType: nil
            ),
            account: CodexAccountSnapshot(email: "codex@example.com", planType: "prolite"),
            resetCredits: ResetCreditsSnapshot(availableCount: 2),
            localCodexUsage: LocalCodexUsageSummary(
                fetchedAt: Date(),
                todayTokens: 128_000,
                sevenDayTokens: 860_000,
                lifetimeTokens: 4_200_000,
                threadCount: 42,
                projects: [
                    LocalCodexProjectUsage(id: "codex-meter", name: "CodexMeter", tokens: 420_000, threadCount: 8),
                    LocalCodexProjectUsage(id: "website", name: "Website", tokens: 260_000, threadCount: 5)
                ],
                taskCounts: LocalCodexTaskCounts(active: 1, pending: 3, scheduled: 2, done: 4),
                dailyBuckets: [
                    LocalCodexDailyUsageBucket(id: "1", label: "7/9", tokens: 82_000),
                    LocalCodexDailyUsageBucket(id: "2", label: "7/10", tokens: 146_000),
                    LocalCodexDailyUsageBucket(id: "3", label: "7/11", tokens: 104_000),
                    LocalCodexDailyUsageBucket(id: "4", label: "7/12", tokens: 238_000),
                    LocalCodexDailyUsageBucket(id: "5", label: "7/13", tokens: 164_000),
                    LocalCodexDailyUsageBucket(id: "6", label: "7/14", tokens: 94_000),
                    LocalCodexDailyUsageBucket(id: "7", label: "7/15", tokens: 128_000)
                ],
                monthCost: LocalCodexCostSummary(
                    inputTokens: 2_800_000,
                    cachedInputTokens: 1_900_000,
                    outputTokens: 620_000,
                    estimatedCostUSD: 24.68,
                    pricedSessionCount: 12,
                    sessionCount: 12
                )
            )
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexMeterEntry) -> Void) {
        completion(CodexMeterEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexMeterEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let entry = CodexMeterEntry(date: Date(), snapshot: snapshot)
        let retrySeconds: TimeInterval = snapshot == nil ? 60 : 15 * 60
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(retrySeconds))))
    }

    /// 读取共享快照并记录失败原因；WidgetKit 的空时间线会缓存，日志能帮助区分无文件、解码失败和沙箱问题。
    private func loadSnapshot() -> UsageSnapshot? {
        do {
            let snapshot = try store.load()
            if snapshot == nil {
                logger.info("Widget snapshot missing")
            }
            return snapshot
        } catch {
            logger.error("Widget snapshot load failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// 展示共享本机统计摘要；Widget 不接触 SQLite、完整路径或任务标题。
private struct LocalCodexUsageWidgetView: View {
    let entry: CodexMeterEntry
    @Environment(\.widgetFamily) private var family
    @AppStorage(AppLanguagePreferenceKeys.selectedLanguage, store: MenuBarDisplaySettings.sharedDefaults)
    private var selectedLanguage = AppLanguage.system.rawValue

    private var language: AppLanguage { AppLanguage(rawValue: selectedLanguage) ?? .system }
    private var formatter: UsageFormatter { UsageFormatter(language: language) }

    var body: some View {
        Group {
            if let usage = entry.snapshot?.localCodexUsage {
                content(usage)
            } else {
                ContentUnavailableView(
                    AppLocalization.string("暂无本机统计"),
                    systemImage: "externaldrive",
                    description: Text(AppLocalization.string("打开菜单栏 App 后自动同步"))
                )
            }
        }
        .containerBackground(for: .widget) {
            WidgetCardBackground(appearanceMode: .automatic, opacity: 1)
        }
    }

    /// 按 Medium、Large 和 Extra Large 的真实可用空间切换看板密度。
    @ViewBuilder
    private func content(_ usage: LocalCodexUsageSummary) -> some View {
        switch family {
        case .systemExtraLarge:
            extraLargeDashboard(usage)
        case .systemLarge:
            largeDashboard(usage)
        default:
            mediumDashboard(usage)
        }
    }

    /// 中号看板保留金额、核心 KPI、折线趋势和任务状态。
    private func mediumDashboard(_ usage: LocalCodexUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            dashboardHeader(usage)
            HStack(spacing: 8) {
                metric("今日", formatter.tokenCount(usage.todayTokens))
                metric("近 7 天", formatter.tokenCount(usage.sevenDayTokens))
                metric("累计", formatter.tokenCount(usage.lifetimeTokens))
                metric("线程", "\(usage.threadCount)")
            }
            HStack(alignment: .top, spacing: 10) {
                LocalSevenDayLineChart(buckets: recentBuckets(usage))
                    .frame(height: 42)
                taskDashboard(usage.taskCounts)
                    .frame(width: 112)
            }
            if let cost = usage.monthCost {
                tokenSplitBar(cost)
                    .frame(height: 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 大号看板在中号基础上增加 token 拆分、任务和项目相对排行。
    private func largeDashboard(_ usage: LocalCodexUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            dashboardHeader(usage)
            HStack(spacing: 8) {
                metricCard("今日", value: usage.todayTokens, systemName: "sun.max.fill")
                metricCard("近 7 天", value: usage.sevenDayTokens, systemName: "calendar")
                metricCard("累计", value: usage.lifetimeTokens, systemName: "sum")
            }
            VStack(alignment: .leading, spacing: 3) {
                panelTitle("近 7 日趋势", systemName: "chart.xyaxis.line")
                LocalSevenDayLineChart(buckets: recentBuckets(usage), showsLabels: true)
                    .frame(height: 62)
            }
            if let cost = usage.monthCost {
                tokenComposition(cost)
            }
            HStack(spacing: 12) {
                taskDashboard(usage.taskCounts)
                projectRanking(usage.projects, limit: 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 超大号看板组合双额度环、三张指标卡、价值进度、半年热力图和项目排行。
    private func extraLargeDashboard(_ usage: LocalCodexUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            dashboardHeader(usage)
            HStack(alignment: .center, spacing: 12) {
                LocalQuotaRings(snapshot: entry.snapshot)
                    .frame(width: 116, height: 116)
                HStack(spacing: 8) {
                    metricCard("今日", value: usage.todayTokens, systemName: "sun.max.fill")
                    metricCard("近 7 天", value: usage.sevenDayTokens, systemName: "calendar")
                    metricCard("累计", value: usage.lifetimeTokens, systemName: "sum")
                }
            }
            if let cost = usage.monthCost {
                valueProgress(cost)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    panelTitle("半年活跃", systemName: "calendar")
                    LocalUsageHeatmap(buckets: usage.dailyBuckets ?? [], fetchedAt: usage.fetchedAt)
                        .frame(height: 72)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 4) {
                    panelTitle("近 7 日趋势", systemName: "chart.xyaxis.line")
                    LocalSevenDayLineChart(buckets: recentBuckets(usage), showsLabels: true)
                        .frame(height: 72)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 5) {
                    taskDashboard(usage.taskCounts)
                    projectRanking(usage.projects, limit: 3)
                }
                .frame(width: 190)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 统一看板标题和本月 API 等效价值。
    private func dashboardHeader(_ usage: LocalCodexUsageSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label(AppLocalization.string("Codex 概览"), systemImage: "chart.bar.xaxis")
                .font(.headline)
            Spacer(minLength: 4)
            if let cost = usage.monthCost {
                Text("\(AppLocalization.string("本月估算"))  \(Self.currency(cost.estimatedCostUSD))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    /// 返回已补齐历史序列末七个自然日聚合点。
    private func recentBuckets(_ usage: LocalCodexUsageSummary) -> [LocalCodexDailyUsageBucket] {
        Array((usage.dailyBuckets ?? []).suffix(7))
    }

    /// 用 2x2 稳定网格展示今日四类任务计数。
    private func taskDashboard(_ counts: LocalCodexTaskCounts) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: family == .systemMedium ? 3 : 6) {
            GridRow {
                taskCount("进行中", counts.active, color: .green)
                taskCount("待处理", counts.pending, color: .orange)
            }
            GridRow {
                taskCount("定时", counts.scheduled, color: .blue)
                taskCount("完成", counts.done, color: .secondary)
            }
        }
    }

    /// 绘制未缓存输入、缓存输入和输出的比例条。
    private func tokenSplitBar(_ cost: LocalCodexCostSummary) -> some View {
        GeometryReader { geometry in
            let cached = min(cost.cachedInputTokens, cost.inputTokens)
            let uncached = max(0, cost.inputTokens - cached)
            let total = max(1, uncached + cached + cost.outputTokens)
            HStack(spacing: 0) {
                Rectangle().fill(CodexMeterChartPalette.tokenInput)
                    .frame(width: geometry.size.width * CGFloat(uncached) / CGFloat(total))
                Rectangle().fill(CodexMeterChartPalette.tokenCachedInput)
                    .frame(width: geometry.size.width * CGFloat(cached) / CGFloat(total))
                Rectangle().fill(CodexMeterChartPalette.tokenOutput)
                    .frame(width: geometry.size.width * CGFloat(cost.outputTokens) / CGFloat(total))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
        }
    }

    /// 展示 token 比例条及三类精确数值。
    private func tokenComposition(_ cost: LocalCodexCostSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            panelTitle("Token 构成", systemName: "chart.bar.fill")
            tokenSplitBar(cost).frame(height: 7)
            HStack(spacing: 12) {
                legend("输入", value: max(0, cost.inputTokens - cost.cachedInputTokens), color: CodexMeterChartPalette.tokenInput)
                legend("缓存输入", value: cost.cachedInputTokens, color: CodexMeterChartPalette.tokenCachedInput)
                legend("输出", value: cost.outputTokens, color: CodexMeterChartPalette.tokenOutput)
            }
        }
    }

    /// 使用对数刻度展示订阅价值节点和本月 API 等效估算。
    private func valueProgress(_ cost: LocalCodexCostSummary) -> some View {
        let maximum = 46_500.0
        let progress = min(1, log1p(cost.estimatedCostUSD) / log1p(maximum))
        return VStack(spacing: 3) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.09))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [CodexMeterChartPalette.primary, CodexMeterChartPalette.primaryStrong], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geometry.size.width * progress))
                }
            }
            .frame(height: 8)
            HStack {
                Text("$20")
                Spacer()
                Text("$100")
                Spacer()
                Text("$200")
                Spacer()
                Text("$46.5K")
            }
            .font(.system(size: 8, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
    }

    /// 展示近七天项目排行和对应 token。
    private func projectRanking(_ projects: [LocalCodexProjectUsage], limit: Int) -> some View {
        let maximum = max(1, projects.map(\.tokens).max() ?? 1)
        return VStack(alignment: .leading, spacing: 4) {
            panelTitle("项目排行", systemName: "folder.fill")
            ForEach(Array(Array(projects.prefix(limit)).enumerated()), id: \.element.id) { index, project in
                VStack(spacing: 2) {
                    HStack(spacing: 5) {
                        Text("\(index + 1)").foregroundStyle(.tertiary).frame(width: 10, alignment: .trailing)
                        Text(project.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(formatter.tokenCount(project.tokens)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(CodexMeterChartPalette.primary.opacity(0.72))
                                .frame(width: max(3, geometry.size.width * CGFloat(project.tokens) / CGFloat(maximum)))
                        }
                    }
                    .frame(height: 3)
                }
                .font(.caption2)
            }
        }
    }

    /// 生成大号看板的数字卡片。
    private func metricCard(_ title: String, value: Int64, systemName: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(AppLocalization.string(title), systemImage: systemName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(formatter.tokenCount(value))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 0.8))
    }

    /// 生成图表和排行区域的紧凑标题。
    private func panelTitle(_ title: String, systemName: String) -> some View {
        Label(AppLocalization.string(title), systemImage: systemName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// 生成 token 拆分图例。
    private func legend(_ title: String, value: Int64, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(AppLocalization.string(title)).foregroundStyle(.secondary)
            Text(formatter.tokenCount(value)).monospacedDigit()
        }
        .font(.caption2)
    }

    /// 格式化看板中的美元估算。
    private static func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    /// 生成本机统计顶部指标。
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(AppLocalization.string(title)).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 生成四类今日任务计数。
    private func taskCount(_ title: String, _ value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(AppLocalization.string(title)).lineLimit(1).minimumScaleFactor(0.72)
            }
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .font(.caption2)
        .frame(width: 52, alignment: .leading)
    }
}

/// 使用原生 Path 绘制最近七个自然日的 Token 趋势，避免为简单图表引入依赖。
private struct LocalSevenDayLineChart: View {
    let buckets: [LocalCodexDailyUsageBucket]
    var showsLabels = false

    /// 根据容器尺寸绘制网格、折线、节点和可选日期标签。
    var body: some View {
        GeometryReader { geometry in
            let values = Array(buckets.suffix(7))
            let chartHeight = max(1, geometry.size.height - (showsLabels ? 14 : 0))
            let maximum = max(1, values.map(\.tokens).max() ?? 1)
            let points = Self.points(
                values: values,
                width: geometry.size.width,
                height: chartHeight,
                maximum: maximum
            )

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        Divider().opacity(0.35)
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: chartHeight)

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(
                    CodexMeterChartPalette.primary,
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                )

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(CodexMeterChartPalette.primary)
                        .frame(width: 5, height: 5)
                        .position(point)
                }

                if showsLabels {
                    HStack(spacing: 0) {
                        ForEach(values) { bucket in
                            Text(bucket.label)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .font(.system(size: 7, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(height: 12)
                    .offset(y: chartHeight + 2)
                }
            }
        }
    }

    /// 将日用量归一化为容器坐标；全零序列仍保留稳定基线。
    private static func points(
        values: [LocalCodexDailyUsageBucket],
        width: CGFloat,
        height: CGFloat,
        maximum: Int64
    ) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let step = values.count > 1 ? width / CGFloat(values.count - 1) : 0
        return values.enumerated().map { index, bucket in
            let ratio = CGFloat(bucket.tokens) / CGFloat(maximum)
            return CGPoint(x: CGFloat(index) * step, y: max(2, (height - 4) * (1 - ratio) + 2))
        }
    }
}

/// 以双环展示短窗口和周窗口剩余额度，颜色与 Token 图表保持同一视觉语义。
private struct LocalQuotaRings: View {
    let snapshot: UsageSnapshot?

    private var windows: [RateLimitWindow] {
        guard let snapshot else { return [] }
        return [snapshot.rateLimits.primary, snapshot.rateLimits.secondary].compactMap { $0 }
    }

    private var shortWindow: RateLimitWindow? { windows.first { !$0.isWeeklyQuotaWindow } }
    private var weeklyWindow: RateLimitWindow? { windows.first { $0.isWeeklyQuotaWindow } }

    /// 叠放两层额度环，并在中心给出紧凑的剩余百分比。
    var body: some View {
        ZStack {
            ring(window: shortWindow, color: CodexMeterChartPalette.primary, lineWidth: 11)
                .padding(3)
            ring(window: weeklyWindow, color: CodexMeterChartPalette.secondary, lineWidth: 9)
                .padding(20)
            VStack(spacing: 1) {
                quotaLabel(shortWindow, fallback: "5h", color: CodexMeterChartPalette.primary)
                quotaLabel(weeklyWindow, fallback: "7d", color: CodexMeterChartPalette.secondary)
                Text(AppLocalization.string("剩余"))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 绘制单个额度环；缺失窗口时仅保留浅色轨道。
    private func ring(window: RateLimitWindow?, color: Color, lineWidth: CGFloat) -> some View {
        let progress = CGFloat(window?.remainingPercent ?? 0) / 100
        return ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    /// 生成环心中的窗口名称和剩余百分比。
    private func quotaLabel(_ window: RateLimitWindow?, fallback: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(window?.windowDurationMins == 300 ? "5h" : fallback).foregroundStyle(color)
            Text("\(window?.remainingPercent ?? 0)%")
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .monospacedDigit()
    }
}

/// 将最近 26 周日用量绘制为 GitHub 风格热力图，零用量日期保持低对比轨道色。
private struct LocalUsageHeatmap: View {
    let buckets: [LocalCodexDailyUsageBucket]
    let fetchedAt: Date

    /// 以 26 列、每列 7 天的稳定网格展示半年活跃强度。
    var body: some View {
        GeometryReader { geometry in
            let values = Self.paddedValues(buckets, fetchedAt: fetchedAt)
            let maximum = max(1, values.max() ?? 1)
            let spacing: CGFloat = 2
            let cellWidth = max(3, (geometry.size.width - spacing * 25) / 26)
            let cellHeight = max(3, (geometry.size.height - spacing * 6) / 7)

            HStack(spacing: spacing) {
                ForEach(0..<26, id: \.self) { column in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            let value = values[column * 7 + row]
                            RoundedRectangle(cornerRadius: min(2, cellWidth / 3))
                                .fill(CodexMeterChartPalette.heatmapColor(value: value, maximum: maximum))
                                .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
        }
        .accessibilityLabel(AppLocalization.string("半年活跃"))
    }

    /// 按周日开列对齐最近 26 周；兼容旧快照，并为本周尚未到来的日期补零。
    private static func paddedValues(
        _ buckets: [LocalCodexDailyUsageBucket],
        fetchedAt: Date,
        calendar: Calendar = .current
    ) -> [Int64] {
        let trailingDays = 7 - calendar.component(.weekday, from: fetchedAt)
        let historyCount = 182 - trailingDays
        let history = Array(buckets.suffix(historyCount)).map(\.tokens)
        let leading = Array(repeating: Int64(0), count: max(0, historyCount - history.count))
        let trailing = Array(repeating: Int64(0), count: trailingDays)
        return leading + history + trailing
    }

}

struct CodexMeterWidgetView: View {
    let entry: CodexMeterEntry
    @Environment(\.widgetFamily) private var family
    @AppStorage(AppLanguagePreferenceKeys.selectedLanguage, store: MenuBarDisplaySettings.sharedDefaults) private var selectedLanguage = AppLanguage.system.rawValue
    private var language: AppLanguage {
        AppLanguage(rawValue: selectedLanguage) ?? .system
    }
    private var formatter: UsageFormatter {
        UsageFormatter(language: language)
    }
    private var settings: MenuBarDisplaySettings {
        MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
    }
    private var widgetSettings: WidgetDisplaySettings {
        WidgetDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
    }
    private var appearanceSettings: SurfaceAppearanceSettings {
        SurfaceAppearanceSettings(defaults: MenuBarDisplaySettings.sharedDefaults)
    }

    var body: some View {
        themedContent
    }

    /// 根据小组件外观设置套用明暗模式和半透明卡片背景。
    @ViewBuilder private var themedContent: some View {
        let activeAppearance = appearanceSettings
        let baseContent = content
            .environment(\.locale, language.locale)
            .containerBackground(for: .widget) {
                WidgetCardBackground(appearanceMode: activeAppearance.appearanceMode, opacity: activeAppearance.cardOpacity)
            }
        if let colorScheme = activeAppearance.appearanceMode.colorScheme {
            baseContent.environment(\.colorScheme, colorScheme)
        } else {
            baseContent
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            HStack(spacing: 6) {
                Label("Codex", systemImage: "gauge.with.needle")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .layoutPriority(1)
                Spacer()
                if widgetSettings.showsPlanLabel, let snapshot = entry.snapshot {
                    WidgetAccountSummary(snapshot: snapshot, family: family)
                }
            }

            if let snapshot = entry.snapshot {
                let display = widgetDisplay(snapshot)
                snapshotContent(snapshot, display: display)
            } else {
                Spacer(minLength: 0)
                Text(AppLocalization.string("暂无数据", language: language))
                    .font(.title3.weight(.semibold))
                Text(AppLocalization.string("打开菜单栏 App 后自动同步", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var contentSpacing: CGFloat {
        family == .systemSmall ? 4 : 10
    }

    /// 小号小组件使用可伸缩布局填满卡片高度，避免内容贴顶后底部出现大块空白。
    @ViewBuilder private func snapshotContent(_ snapshot: UsageSnapshot, display: CodexMeterWidgetDisplay) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 0) {
                usageRows(display)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if widgetSettings.showsLastSync {
                    syncFooter(snapshot)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            usageRows(display)
            if widgetSettings.showsLastSync {
                syncFooter(snapshot)
            }
        }
    }

    /// 统一生成小组件展示模型，避免正文和页脚为了判断布局重复计算快照。
    private func widgetDisplay(_ snapshot: UsageSnapshot) -> CodexMeterWidgetDisplay {
        CodexMeterWidgetDisplay(
            snapshot: snapshot,
            settings: settings,
            widgetSettings: widgetSettings,
            formatter: formatter,
            language: language,
            now: entry.date
        )
    }

    /// 按当前 Widget 家族渲染窗口列表，小号把多条窗口记录拉开以填满固定卡片高度。
    private func usageRows(_ display: CodexMeterWidgetDisplay) -> some View {
        Group {
            if family == .systemSmall {
                let enumeratedLines = Array(display.lines.enumerated())
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(enumeratedLines, id: \.element.id) { index, line in
                        WidgetMetric(display: line, settings: settings, family: family)
                        if index < enumeratedLines.count - 1 {
                            Spacer(minLength: 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(display.lines) { line in
                        WidgetMetric(display: line, settings: settings, family: family)
                    }
                }
            }
        }
    }

    private func syncFooter(_ snapshot: UsageSnapshot) -> some View {
        Text(syncText(snapshot))
            .font(family == .systemSmall ? .caption2 : .caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, family == .systemSmall ? 2 : 6)
    }

    private func syncText(_ snapshot: UsageSnapshot) -> String {
        let time = formatter.fetchedAt(snapshot.fetchedAt)
        if AppLocalization.usesEnglish(language: language) {
            return family == .systemSmall ? "Synced \(time)" : "Last synced \(time)"
        }
        return family == .systemSmall ? "同步 \(time)" : "最近同步 \(time)"
    }
}

/// 小组件卡片背景，按当前明暗模式绘制半透明底色，避免桌面图案直接压低文字可读性。
private struct WidgetCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let appearanceMode: SurfaceAppearanceMode
    let opacity: Double

    var body: some View {
        Rectangle()
            .fill(backgroundColor.opacity(SurfaceAppearanceSettings.normalizedCardOpacity(opacity)))
    }

    private var backgroundColor: Color {
        effectiveColorScheme == .dark ? .black : .white
    }

    private var effectiveColorScheme: ColorScheme {
        appearanceMode.colorScheme ?? colorScheme
    }
}

/// 小组件头部右侧的套餐摘要，受“显示套餐标签”设置控制，避免额外增加配置复杂度。
private struct WidgetAccountSummary: View {
    let snapshot: UsageSnapshot
    let family: WidgetFamily

    var body: some View {
        if let summaryText {
            Text(summaryText)
                .font((family == .systemSmall ? Font.caption2 : Font.caption).weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(family == .systemSmall ? 0.72 : 0.82)
                .frame(maxWidth: family == .systemSmall ? 78 : 150, alignment: .trailing)
        }
    }

    /// 合并套餐倍率和可用重置次数，避免在小组件右上角展示邮箱造成视觉拥挤。
    private var summaryText: String? {
        let parts = [
            snapshot.accountPlanCompactDisplayText,
            resetCreditsText
        ].compactMap { $0 }
        guard !parts.isEmpty else {
            return nil
        }
        return parts.joined(separator: "·")
    }

    /// 使用重置卡接口返回的可用数量；接口不可用时不显示，避免把未知状态误报为 0 次。
    private var resetCreditsText: String? {
        guard let resetCredits = snapshot.resetCredits else {
            return nil
        }
        return AppLocalization.usesEnglish()
            ? "\(resetCredits.availableCount) resets"
            : "\(resetCredits.availableCount)次重置"
    }
}

/// 小组件单个窗口的额度块；中号完整展示，小号压缩长文案但保留进度和速度判断。
private struct WidgetMetric: View {
    let display: CodexMeterWidgetDisplay.Line
    let settings: MenuBarDisplaySettings
    let family: WidgetFamily

    private var isSmallFamily: Bool {
        family == .systemSmall
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isSmallFamily ? 3 : 5) {
            WidgetBalanceRow(display: display, settings: settings, family: family)

            if !display.paceStatusText.isEmpty {
                WidgetPaceRow(display: display, settings: settings, family: family)
            }

            WidgetUsageProgressBar(
                value: display.progressValue,
                color: display.tone.statusBarColor(settings: settings),
                family: family
            )
        }
    }
}

/// 小组件专用进度条，避开 WidgetKit 对系统 ProgressView 的重绘，保证全局颜色预设能稳定生效。
private struct WidgetUsageProgressBar: View {
    let value: Double
    let color: Color
    let family: WidgetFamily

    private var progress: CGFloat {
        CGFloat(min(max(value / 100, 0), 1))
    }

    private var height: CGFloat {
        family == .systemSmall ? 7 : 6
    }

    var body: some View {
        GeometryReader { proxy in
            let width = progress > 0 ? max(proxy.size.width * progress, height) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.34))
                Capsule()
                    .fill(color)
                    .frame(width: width)
            }
        }
        .frame(height: height)
        .widgetAccentable(false)
    }
}

/// 小组件的余额和重置文案统一放在进度条上方，减少每个窗口占用的垂直行数。
private struct WidgetBalanceRow: View {
    let display: CodexMeterWidgetDisplay.Line
    let settings: MenuBarDisplaySettings
    let family: WidgetFamily

    private var isSmallFamily: Bool {
        family == .systemSmall
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: isSmallFamily ? 6 : 8) {
            Text(display.title)
                .foregroundStyle(.secondary)
                .layoutPriority(2)
            Text(display.value)
                .font(.system(isSmallFamily ? .caption : .callout, design: .default)
                    .weight(settings.numberFontWeight.fontWeight))
                .monospacedDigit()
                .foregroundStyle(display.tone.statusBarColor(settings: settings))
                .widgetAccentable(false)
                .layoutPriority(3)
            Spacer(minLength: isSmallFamily ? 4 : 6)
            if !display.resetText.isEmpty {
                Text(resetText)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
                    .truncationMode(.tail)
            }
        }
        .font((isSmallFamily ? Font.caption : Font.callout).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(isSmallFamily ? 0.82 : 0.9)
    }

    /// 小号小组件去掉中文时间里的空格，避免同一信息被迫缩小到不可读。
    private var resetText: String {
        guard isSmallFamily, !AppLocalization.usesEnglish() else {
            return display.resetText
        }
        return display.resetText.replacingOccurrences(of: " ", with: "")
    }
}

/// 小组件里的速度辅助行，复用共享 Pace 展示模型，只负责压缩排版和着色。
private struct WidgetPaceRow: View {
    let display: CodexMeterWidgetDisplay.Line
    let settings: MenuBarDisplaySettings
    let family: WidgetFamily

    private var isSmallFamily: Bool {
        family == .systemSmall
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: isSmallFamily ? 4 : 6) {
            Text(paceStatusText)
                .foregroundStyle(display.paceTone.statusBarColor(settings: settings))
                .widgetAccentable(false)
                .layoutPriority(2)
            if !display.paceProjectionText.isEmpty {
                if !isSmallFamily {
                    Spacer(minLength: 4)
                }
                Text(paceProjectionText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
        }
        .font((isSmallFamily ? Font.caption : Font.callout).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(isSmallFamily ? 0.82 : 0.9)
    }

    /// 小号宽度优先展示判断结果，去掉空格让“超额 25%”不再被压成单字。
    private var paceStatusText: String {
        guard isSmallFamily, !AppLocalization.usesEnglish() else {
            return display.paceStatusText
        }
        return display.paceStatusText.replacingOccurrences(of: " ", with: "")
    }

    /// 小号里用更短的预测文案，完整文案仍保留给中号小组件和弹窗。
    private var paceProjectionText: String {
        guard isSmallFamily else {
            return display.paceProjectionText
        }
        guard !AppLocalization.usesEnglish() else {
            return display.paceProjectionText
        }
        return display.paceProjectionText
            .replacingOccurrences(of: "预计 ", with: "预计")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "后耗尽", with: "耗尽")
    }
}
