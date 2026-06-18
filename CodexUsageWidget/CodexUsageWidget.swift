import CodexUsageShared
import SwiftUI
import WidgetKit

struct CodexUsageWidget: Widget {
    let kind = "CodexUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexUsageTimelineProvider()) { entry in
            CodexUsageWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Codex 用量")
        .description("显示 Codex 5 小时与 7 天窗口的最近同步余量。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CodexUsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

struct CodexUsageTimelineProvider: TimelineProvider {
    private let store = UsageSnapshotStore()

    func placeholder(in context: Context) -> CodexUsageEntry {
        CodexUsageEntry(date: Date(), snapshot: UsageSnapshot(
            fetchedAt: Date(),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(usedPercent: 17, windowDurationMins: 300, resetsAt: nil),
                secondary: RateLimitWindow(usedPercent: 11, windowDurationMins: 10_080, resetsAt: nil),
                credits: CreditsSnapshot(hasCredits: false, unlimited: false, balance: "0"),
                planType: "prolite",
                rateLimitReachedType: nil
            )
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexUsageEntry) -> Void) {
        completion(CodexUsageEntry(date: Date(), snapshot: try? store.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexUsageEntry>) -> Void) {
        let entry = CodexUsageEntry(date: Date(), snapshot: try? store.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct CodexUsageWidgetView: View {
    let entry: CodexUsageEntry
    @Environment(\.widgetFamily) private var family
    private let formatter = UsageFormatter()
    private var settings: MenuBarDisplaySettings {
        MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            HStack {
                Label("Codex", systemImage: "gauge.with.needle")
                    .font(.headline)
                Spacer()
                if let plan = entry.snapshot?.rateLimits.planType {
                    Text(plan)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let snapshot = entry.snapshot {
                usageRows(snapshot)
                syncFooter(snapshot)
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
        family == .systemSmall ? 6 : 10
    }

    private func usageRows(_ snapshot: UsageSnapshot) -> some View {
        let display = CodexUsageWidgetDisplay(
            snapshot: snapshot,
            settings: settings,
            formatter: formatter,
            now: entry.date
        )
        return VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            ForEach(display.lines) { line in
                WidgetMetric(display: line, settings: settings)
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
            .padding(.top, family == .systemSmall ? 0 : 6)
    }

    private func syncText(_ snapshot: UsageSnapshot) -> String {
        let time = formatter.fetchedAt(snapshot.fetchedAt)
        return family == .systemSmall ? "同步 \(time)" : "最近同步 \(time)"
    }
}

private struct WidgetMetric: View {
    let display: CodexUsageWidgetDisplay.Line
    let settings: MenuBarDisplaySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(display.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(display.value)
                    .font(.system(size: 13, weight: settings.numberFontWeight.fontWeight).monospacedDigit())
                    .foregroundStyle(display.tone.statusBarColor(settings: settings))
                Text(display.resetText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            ProgressView(value: display.progressValue, total: 100)
                .tint(display.tone.statusBarColor(settings: settings))
        }
    }
}
