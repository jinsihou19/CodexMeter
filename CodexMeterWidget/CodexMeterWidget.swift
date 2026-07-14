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
        .description("显示 Codex 5 小时与 7 天窗口的最近同步余量。")
        .supportedFamilies([.systemSmall, .systemMedium])
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
            resetCredits: ResetCreditsSnapshot(availableCount: 2)
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

struct CodexMeterWidgetView: View {
    let entry: CodexMeterEntry
    @Environment(\.widgetFamily) private var family
    private let formatter = UsageFormatter()
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
                Text("暂无数据")
                    .font(.title3.weight(.semibold))
                Text("打开菜单栏 App 后自动同步")
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
        return "\(resetCredits.availableCount)次重置"
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
        isSmallFamily ? display.resetText.replacingOccurrences(of: " ", with: "") : display.resetText
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
        isSmallFamily ? display.paceStatusText.replacingOccurrences(of: " ", with: "") : display.paceStatusText
    }

    /// 小号里用更短的预测文案，完整文案仍保留给中号小组件和弹窗。
    private var paceProjectionText: String {
        guard isSmallFamily else {
            return display.paceProjectionText
        }
        return display.paceProjectionText
            .replacingOccurrences(of: "预计 ", with: "预计")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "后耗尽", with: "耗尽")
    }
}
