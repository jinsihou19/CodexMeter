import AppKit
import CodexUsageShared
import SwiftUI

enum MenuBarPopoverLayout {
    static let width: CGFloat = 380
    static let minimumHeight: CGFloat = 220
    static let maximumHeight: CGFloat = 660
    static let maximumScrollableContentHeight: CGFloat = 520
    static let initialScrollableContentHeight: CGFloat = 430
    static let initialSize = NSSize(width: width, height: 560)
}

private enum TokenActivityMode: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case cumulative

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .daily:
            return "每日"
        case .weekly:
            return "每周"
        case .cumulative:
            return "累计"
        }
    }

    func buckets(from stats: CodexProfileStats) -> [CodexTokenUsageBucket] {
        switch self {
        case .daily:
            return stats.dailyUsageBuckets
        case .weekly:
            return stats.weeklyUsageBuckets
        case .cumulative:
            return stats.cumulativeDailyUsageBuckets
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var viewModel: UsageViewModel
    let onSizeChange: ((CGSize) -> Void)?
    @State private var activityMode = TokenActivityMode.daily
    @State private var measuredScrollContentHeight = MenuBarPopoverLayout.initialScrollableContentHeight
    private let formatter = UsageFormatter()
    private var settings: MenuBarDisplaySettings {
        MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
    }

    init(viewModel: UsageViewModel, onSizeChange: ((CGSize) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onSizeChange = onSizeChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Divider()

            ScrollView {
                scrollContent
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: MenuBarScrollContentHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
            }
            .scrollIndicators(.hidden)
            .frame(height: scrollContentViewportHeight)
            .onPreferenceChange(MenuBarScrollContentHeightPreferenceKey.self) { height in
                guard height > 0, abs(measuredScrollContentHeight - height) > 0.5 else {
                    return
                }
                DispatchQueue.main.async {
                    guard abs(measuredScrollContentHeight - height) > 0.5 else {
                        return
                    }
                    measuredScrollContentHeight = height
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing)

                Button {
                    SettingsWindowPresenter.shared.show()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                }
            }
        }
        .padding(12)
        .frame(width: MenuBarPopoverLayout.width)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: MenuBarSizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(MenuBarSizePreferenceKey.self) { size in
            guard size.width > 0, size.height > 0 else {
                return
            }
            // 延后到下一轮主线程再调整 AppKit popover，避免 SwiftUI 正在布局时重入布局。
            DispatchQueue.main.async {
                onSizeChange?(size)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.statusSymbolName)
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
            Text("Codex 用量")
                .font(.headline)
            Spacer()
            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func usageContent(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            QuotaSummaryGrid(snapshot: snapshot.rateLimits, formatter: formatter, settings: settings)

            if let paceDisplay = UsagePaceDisplay(rateLimits: snapshot.rateLimits) {
                PaceComparisonRow(display: paceDisplay)
            }

            if settings.showsAdditionalLimits, !snapshot.rateLimits.additionalLimits.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("额外额度")
                    ForEach(snapshot.rateLimits.additionalLimits) { limit in
                        AdditionalRateLimitView(limit: limit, formatter: formatter, settings: settings)
                    }
                }
            }

            if let profileStats = snapshot.profileStats {
                ProfileStatsSection(
                    stats: profileStats,
                    activityMode: $activityMode,
                    formatter: formatter
                )
            }

            SnapshotDetailsSection(snapshot: snapshot, formatter: formatter)
        }
    }

    @ViewBuilder private var scrollContent: some View {
        if let snapshot = viewModel.snapshot {
            usageContent(snapshot)
        } else {
            ContentUnavailableView("暂无用量数据", systemImage: "clock")
                .frame(width: 320)
                .padding(.vertical, 24)
        }
    }

    private var scrollContentViewportHeight: CGFloat {
        min(measuredScrollContentHeight, MenuBarPopoverLayout.maximumScrollableContentHeight)
    }

    private func tone(for window: RateLimitWindow?) -> UsageRemainingTone {
        UsageRemainingTone(remainingPercent: window?.remainingPercent)
    }
}

private struct QuotaSummaryGrid: View {
    let snapshot: RateLimitSnapshot
    let formatter: UsageFormatter
    let settings: MenuBarDisplaySettings

    var body: some View {
        HStack(spacing: 8) {
            QuotaSummaryCard(
                title: "5 小时",
                display: UsageMetricDisplay(title: "5 小时", window: snapshot.primary),
                resetText: formatter.resetRemainingText(window: snapshot.primary),
                tone: UsageRemainingTone(remainingPercent: snapshot.primary?.remainingPercent),
                settings: settings
            )
            QuotaSummaryCard(
                title: "7 天",
                display: UsageMetricDisplay(title: "7 天", window: snapshot.secondary),
                resetText: formatter.resetRemainingText(window: snapshot.secondary),
                tone: UsageRemainingTone(remainingPercent: snapshot.secondary?.remainingPercent),
                settings: settings
            )
        }
    }
}

private struct QuotaSummaryCard: View {
    let title: String
    let display: UsageMetricDisplay
    let resetText: String
    let tone: UsageRemainingTone
    let settings: MenuBarDisplaySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(display.remainingText)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tone.statusBarColor(settings: settings))
            }

            ProgressView(value: display.progressValue, total: 100)
                .tint(tone.statusBarColor(settings: settings))

            HStack(spacing: 4) {
                Text(display.usedText.replacingOccurrences(of: "已用 ", with: "用 "))
                Spacer(minLength: 4)
                Text("重置 \(resetText)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct UsageMetricCard: View {
    let display: UsageMetricDisplay
    let resetText: String
    let tone: UsageRemainingTone
    let settings: MenuBarDisplaySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(display.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("重置 \(resetText)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(display.remainingText)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tone.statusBarColor(settings: settings))
                Text("剩余")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ProgressView(value: display.progressValue, total: 100)
                .tint(tone.statusBarColor(settings: settings))

            HStack {
                Text(display.usedText)
                Spacer()
                Text(display.windowDurationText)
            }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct PaceComparisonRow: View {
    let display: UsagePaceDisplay

    var body: some View {
        HStack(spacing: 8) {
            Label("用量速度", systemImage: "speedometer")
                .foregroundStyle(.secondary)
            Spacer()
            Text(display.valueText)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(display.tone.statusBarColor(settings: MenuBarDisplaySettings(
                    defaults: MenuBarDisplaySettings.sharedDefaults
                )))
            Text(display.detailText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .font(.caption2)
        .menuSectionCard(padding: 8)
    }
}

private struct AdditionalRateLimitView: View {
    let limit: AdditionalRateLimitSnapshot
    let formatter: UsageFormatter
    let settings: MenuBarDisplaySettings

    var body: some View {
        VStack(spacing: 8) {
            UsageMetricCard(
                display: UsageMetricDisplay(title: "\(displayName) 5 小时", window: limit.primary),
                resetText: formatter.resetRemainingText(window: limit.primary),
                tone: UsageRemainingTone(remainingPercent: limit.primary?.remainingPercent),
                settings: settings
            )
            UsageMetricCard(
                display: UsageMetricDisplay(title: "\(displayName) 7 天", window: limit.secondary),
                resetText: formatter.resetRemainingText(window: limit.secondary),
                tone: UsageRemainingTone(remainingPercent: limit.secondary?.remainingPercent),
                settings: settings
            )
        }
    }

    private var displayName: String {
        limit.displayName
            .replacingOccurrences(of: "GPT-5.3-", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }
}

private struct ProfileStatsSection: View {
    let stats: CodexProfileStats
    @Binding var activityMode: TokenActivityMode
    let formatter: UsageFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Profile")

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 6) {
                ProfileMetric(title: "累计 Token", value: formatter.tokenCount(stats.lifetimeTokens))
                ProfileMetric(title: "峰值 Token", value: formatter.tokenCount(stats.peakDailyTokens))
                ProfileMetric(title: "最长任务", value: formatter.compactDuration(seconds: stats.longestRunningTurnSeconds))
                ProfileMetric(title: "连续天数", value: streakText)
            }
            .menuSectionCard(padding: 8)

            TokenActivitySection(
                stats: stats,
                activityMode: $activityMode,
                formatter: formatter
            )

            ActivityInsightsSection(stats: stats, formatter: formatter)

            if !stats.topInvocations.isEmpty {
                TopInvocationsSection(invocations: Array(stats.topInvocations.prefix(3)))
            }
        }
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]
    }

    private var streakText: String {
        let current = stats.currentStreakDays.map { "\($0) 天" } ?? "--"
        let longest = stats.longestStreakDays.map { "\($0) 天最长" }
        return [current, longest].compactMap(\.self).joined(separator: " · ")
    }
}

private struct ProfileMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TokenActivitySection: View {
    let stats: CodexProfileStats
    @Binding var activityMode: TokenActivityMode
    let formatter: UsageFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Token 活动")
                    .font(.caption.weight(.semibold))
                Spacer()
                Picker("", selection: $activityMode) {
                    ForEach(TokenActivityMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 132)
            }

            HStack(alignment: .firstTextBaseline) {
                TokenActivitySummary(title: "最近日", value: formatter.tokenCount(stats.latestDailyTokens))
                Spacer()
                TokenActivitySummary(title: "近 30 天", value: formatter.tokenCount(stats.recentDailyTokens))
            }

            TokenActivityChart(buckets: activityMode.buckets(from: stats), formatter: formatter)
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TokenActivitySummary: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}

private struct TokenActivityChart: View {
    let buckets: [CodexTokenUsageBucket]
    let formatter: UsageFormatter
    @State private var hoveredBucketID: String?

    var body: some View {
        let visibleBuckets = Array(buckets.suffix(32))
        let maximumTokens = max(visibleBuckets.map(\.tokens).max() ?? 0, 1)
        let activeBucket = visibleBuckets.first { $0.id == hoveredBucketID } ?? visibleBuckets.last

        VStack(alignment: .leading, spacing: 4) {
            if let activeBucket {
                HStack(spacing: 6) {
                    Text(activeBucket.startDate)
                        .foregroundStyle(.secondary)
                    Text(formatter.tokenCount(activeBucket.tokens))
                        .fontWeight(.semibold)
                }
                .font(.caption2.monospacedDigit())
            }

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(visibleBuckets) { bucket in
                    let ratio = Double(bucket.tokens) / Double(maximumTokens)
                    let isActive = activeBucket?.id == bucket.id
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.orange.opacity(isActive ? 0.95 : 0.34 + (0.44 * ratio)))
                        .overlay(alignment: .top) {
                            if isActive {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .stroke(Color.orange, lineWidth: 1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    .frame(height: max(3, CGFloat(ratio) * 42))
                        .contentShape(Rectangle())
                        .onHover { isInside in
                            hoveredBucketID = isInside ? bucket.id : nil
                        }
                        .accessibilityLabel("\(bucket.startDate) \(bucket.tokens) tokens")
                }
            }
            .frame(height: 44, alignment: .bottom)
        }
        .frame(height: 60, alignment: .bottom)
    }
}

private struct ActivityInsightsSection: View {
    let stats: CodexProfileStats
    let formatter: UsageFormatter

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            DetailChip(title: "快速", value: formatter.percent(stats.fastModeUsagePercentage))
            DetailChip(title: "推理", value: reasoningText)
            DetailChip(title: "技能", value: countText(stats.uniqueSkillsUsed))
            DetailChip(title: "技能次数", value: countText(stats.totalSkillsUsed))
            DetailChip(title: "会话", value: countText(stats.totalThreads))
        }
        .menuSectionCard(padding: 8)
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]
    }

    private var reasoningText: String {
        let effort = formatter.reasoningEffort(stats.mostUsedReasoningEffort)
        let percentage = formatter.percent(stats.mostUsedReasoningEffortPercentage)
        if effort == "--" {
            return percentage
        }
        if percentage == "--" {
            return effort
        }
        return "\(effort) · \(percentage)"
    }

    private func countText(_ value: Int?) -> String {
        value.map(String.init) ?? "--"
    }
}

private struct TopInvocationsSection: View {
    let invocations: [CodexTopInvocation]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("最常用的插件")
            ForEach(invocations) { invocation in
                HStack(spacing: 8) {
                    Image(systemName: invocation.type == "plugin" ? "puzzlepiece.extension" : "shippingbox")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(invocation.displayName)
                        .lineLimit(1)
                    Spacer()
                    Text("\(invocation.usageCount) 次")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
            }
        }
        .menuSectionCard(padding: 8)
    }
}

private struct SnapshotDetailsSection: View {
    let snapshot: UsageSnapshot
    let formatter: UsageFormatter

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            DetailChip(title: "限制", value: snapshot.rateLimits.rateLimitReachedType ?? "未触发")
            DetailChip(title: "同步", value: formatter.fetchedAt(snapshot.fetchedAt))
        }
        .menuSectionCard(padding: 8)
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]
    }
}

private struct DetailChip: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

private struct MenuBarScrollContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MenuBarSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let nextValue = nextValue()
        if nextValue.width > 0, nextValue.height > 0 {
            value = nextValue
        }
    }
}

private extension View {
    func menuSectionCard(padding: CGFloat) -> some View {
        self
            .padding(padding)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.46))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
