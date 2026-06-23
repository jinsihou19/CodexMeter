import AppKit
import CodexUsageShared
import SwiftUI

enum MenuBarPopoverLayout {
    static let width: CGFloat = 380
    static let horizontalPadding: CGFloat = 12
    static let minimumHeight: CGFloat = 220
    static let maximumHeight: CGFloat = 660
    static let maximumScrollableContentHeight: CGFloat = 520
    static let paceMarkerTooltipTopOffset: CGFloat = 112
    static let scrollOverflowHysteresis: CGFloat = 28
    static let initialSize = NSSize(width: width, height: 560)

    static var contentWidth: CGFloat {
        width - horizontalPadding * 2
    }
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
    @State private var measuredScrollContentHeight: CGFloat = 0
    @State private var usesScrollableContent = false
    @State private var activePaceHelpText: String?
    private let formatter = UsageFormatter()
    private var settings: MenuBarDisplaySettings {
        MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
    }
    private var popoverSettings: PopoverDisplaySettings {
        PopoverDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
    }
    private var appearanceSettings: SurfaceAppearanceSettings {
        SurfaceAppearanceSettings(defaults: MenuBarDisplaySettings.sharedDefaults)
    }

    init(
        viewModel: UsageViewModel,
        onSizeChange: ((CGSize) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onSizeChange = onSizeChange
    }

    var body: some View {
        themedBody
    }

    /// 将弹窗内容包在全局外观层中，确保设置页的明暗和透明度立即影响下拉框。
    @ViewBuilder private var themedBody: some View {
        let activeAppearance = appearanceSettings
        let baseContent = contentBody
            .background(
                PopoverSurfaceBackground(
                    appearanceMode: activeAppearance.appearanceMode,
                    opacity: activeAppearance.cardOpacity
                )
            )
        if let colorScheme = activeAppearance.appearanceMode.colorScheme {
            baseContent.environment(\.colorScheme, colorScheme)
        } else {
            baseContent
        }
    }

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Divider()

            contentArea
                .onPreferenceChange(MenuBarScrollContentHeightPreferenceKey.self) { height in
                    updateMeasuredScrollContentHeight(height)
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
        .padding(MenuBarPopoverLayout.horizontalPadding)
        .frame(width: MenuBarPopoverLayout.width)
        .overlay(alignment: .topLeading) {
            if let activePaceHelpText {
                PaceMarkerHelpBubble(text: activePaceHelpText)
                    .frame(width: MenuBarPopoverLayout.contentWidth, alignment: .leading)
                    .offset(
                        x: MenuBarPopoverLayout.horizontalPadding,
                        y: MenuBarPopoverLayout.paceMarkerTooltipTopOffset
                    )
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
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
            if let snapshot = viewModel.snapshot {
                MenuBarAccountSummary(snapshot: snapshot)
            }
        }
    }

    @ViewBuilder private var contentArea: some View {
        visibleContentArea
            .background(alignment: .topLeading) {
                measuredScrollContent
            }
    }

    @ViewBuilder private var visibleContentArea: some View {
        if usesScrollableContent {
            ScrollView {
                scrollContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .frame(height: MenuBarPopoverLayout.maximumScrollableContentHeight)
        } else {
            scrollContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 使用不参与布局的隐藏副本测量真实内容高度，避免 ScrollView 视口高度反向污染测量值。
    private var measuredScrollContent: some View {
        scrollContent
            .frame(width: MenuBarPopoverLayout.contentWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MenuBarScrollContentHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            )
    }

    /// 更新内容高度并带滞后地切换滚动状态，防止高度接近阈值时在滚动/非滚动之间抖动。
    private func updateMeasuredScrollContentHeight(_ height: CGFloat) {
        guard height > 0 else {
            return
        }
        let roundedHeight = ceil(height)
        DispatchQueue.main.async {
            if abs(measuredScrollContentHeight - roundedHeight) > 0.5 {
                measuredScrollContentHeight = roundedHeight
            }

            let maximumHeight = MenuBarPopoverLayout.maximumScrollableContentHeight
            let hysteresis = MenuBarPopoverLayout.scrollOverflowHysteresis
            let shouldUseScrollableContent = usesScrollableContent
                ? roundedHeight > maximumHeight - hysteresis
                : roundedHeight > maximumHeight + hysteresis
            guard shouldUseScrollableContent != usesScrollableContent else {
                return
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                usesScrollableContent = shouldUseScrollableContent
            }
        }
    }

    private func usageContent(_ snapshot: UsageSnapshot) -> some View {
        let activePopoverSettings = popoverSettings
        return VStack(alignment: .leading, spacing: 8) {
            QuotaSummaryGrid(
                snapshot: snapshot.rateLimits,
                formatter: formatter,
                settings: settings,
                resetTimeDisplayStyle: activePopoverSettings.resetTimeDisplayStyle,
                onPaceMarkerHoverChange: updateActivePaceHelpText
            )

            let paceDisplays = UsageWindowPaceDisplay.displays(
                rateLimits: snapshot.rateLimits,
                weeklyProgressWorkDays: settings.weeklyProgressWorkDays
            )
            if activePopoverSettings.showsPaceComparison, !paceDisplays.isEmpty {
                PaceComparisonSection(displays: paceDisplays)
            }

            if activePopoverSettings.showsAdditionalLimits, !snapshot.rateLimits.additionalLimits.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("额外额度")
                    ForEach(snapshot.rateLimits.additionalLimits) { limit in
                        AdditionalRateLimitView(
                            limit: limit,
                            formatter: formatter,
                            settings: settings,
                            resetTimeDisplayStyle: activePopoverSettings.resetTimeDisplayStyle,
                            onPaceMarkerHoverChange: updateActivePaceHelpText
                        )
                    }
                }
            }

            if let profileStats = snapshot.profileStats, activePopoverSettings.showsAnyProfileSection {
                ProfileStatsSection(
                    stats: profileStats,
                    activityMode: $activityMode,
                    formatter: formatter,
                    popoverSettings: activePopoverSettings
                )
            }

            if activePopoverSettings.showsSyncDetails {
                SnapshotDetailsSection(snapshot: snapshot, formatter: formatter)
            }
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

    /// 统一由弹窗根视图管理理论节奏线说明，避免局部 tooltip 改变卡片布局或内容高度测量。
    private func updateActivePaceHelpText(_ text: String?, _ isHovered: Bool) {
        withAnimation(.easeOut(duration: 0.08)) {
            if isHovered {
                activePaceHelpText = text
            } else if activePaceHelpText == text {
                activePaceHelpText = nil
            }
        }
    }

    private func tone(for window: RateLimitWindow?) -> UsageRemainingTone {
        UsageRemainingTone(remainingPercent: window?.remainingPercent)
    }
}

/// 下拉弹窗的全局背景层，按用户选择的外观和透明度绘制，不依赖 NSWindow 默认底色。
private struct PopoverSurfaceBackground: View {
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

/// 菜单栏弹窗头部右侧的账户摘要，只展示邮箱和套餐，不读取本地认证文件。
private struct MenuBarAccountSummary: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let email = snapshot.accountEmail {
                Text(email)
                    .font(.callout.weight(.medium))
            }
            if let plan = snapshot.accountPlanDisplayText {
                Text(plan)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: 210, alignment: .trailing)
    }
}

private struct QuotaSummaryGrid: View {
    let snapshot: RateLimitSnapshot
    let formatter: UsageFormatter
    let settings: MenuBarDisplaySettings
    let resetTimeDisplayStyle: ResetTimeDisplayStyle
    let onPaceMarkerHoverChange: (String?, Bool) -> Void

    var body: some View {
        let primaryPaceMarker = paceMarker(for: snapshot.primary)
        let secondaryPaceMarker = paceMarker(for: snapshot.secondary)
        HStack(spacing: 8) {
            QuotaSummaryCard(
                title: "5 小时",
                display: UsageMetricDisplay(title: "5 小时", window: snapshot.primary),
                resetText: resetText(for: snapshot.primary),
                tone: UsageRemainingTone(remainingPercent: snapshot.primary?.remainingPercent),
                settings: settings,
                workdayMarkers: [],
                paceMarker: primaryPaceMarker,
                onPaceMarkerHoverChange: updateActivePaceHelpText
            )
            QuotaSummaryCard(
                title: "7 天",
                display: UsageMetricDisplay(title: "7 天", window: snapshot.secondary),
                resetText: resetText(for: snapshot.secondary),
                tone: UsageRemainingTone(remainingPercent: snapshot.secondary?.remainingPercent),
                settings: settings,
                workdayMarkers: weeklyWorkdayMarkerPercents(
                    workDays: settings.weeklyProgressWorkDays,
                    windowDurationMins: snapshot.secondary?.windowDurationMins
                ),
                paceMarker: secondaryPaceMarker,
                onPaceMarkerHoverChange: updateActivePaceHelpText
            )
        }
    }

    /// 根据弹窗时间样式格式化窗口重置文案。
    private func resetText(for window: RateLimitWindow?) -> String {
        switch resetTimeDisplayStyle {
        case .countdown:
            return formatter.resetRemainingText(window: window)
        case .absolute:
            return formatter.resetTime(epochSeconds: window?.resetsAt)
        }
    }

    /// 绿色/红色标记表示按当前时间推进后的理论剩余位置，和灰色工作日刻度分开表达。
    private func paceMarker(for window: RateLimitWindow?) -> ProgressPaceMarker? {
        guard let pace = window?.usagePace(weeklyProgressWorkDays: settings.weeklyProgressWorkDays),
              pace.isDisplayable(),
              abs(pace.roundedDeltaPercent) > 2
        else {
            return nil
        }
        return ProgressPaceMarker(
            percent: 100 - pace.expectedUsedPercent,
            color: pace.deltaPercent <= 0 ? .green : .red,
            helpText: pace.deltaPercent <= 0
                ? "绿色线：按当前时间进度推算的理论剩余位置；绿色表示实际用得比理论慢，有余量。"
                : "红色线：按当前时间进度推算的理论剩余位置；红色表示实际用得比理论快，可能提前耗尽。"
        )
    }

    /// 统一由弹窗根视图管理理论节奏线说明，避免局部 tooltip 改变卡片布局或内容高度测量。
    private func updateActivePaceHelpText(_ text: String?, _ isHovered: Bool) {
        onPaceMarkerHoverChange(text, isHovered)
    }
}

/// 用量条上的理论节奏标记：绿色表示当前用量慢于预期，红色表示快于预期。
private struct ProgressPaceMarker {
    let percent: Double
    let color: Color
    let helpText: String
}

private struct QuotaSummaryCard: View {
    let title: String
    let display: UsageMetricDisplay
    let resetText: String
    let tone: UsageRemainingTone
    let settings: MenuBarDisplaySettings
    let workdayMarkers: [Double]
    let paceMarker: ProgressPaceMarker?
    let onPaceMarkerHoverChange: (String?, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer()
                Text(display.remainingText)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tone.statusBarColor(settings: settings))
            }

            WorkdayMarkedProgressView(
                value: display.progressValue,
                tint: tone.statusBarColor(settings: settings),
                markers: workdayMarkers,
                paceMarker: paceMarker,
                onPaceMarkerHoverChange: { isHovered in
                    onPaceMarkerHoverChange(paceMarker?.helpText, isHovered)
                }
            )

            HStack(spacing: 4) {
                Text(display.usedText.replacingOccurrences(of: "已用 ", with: "用 "))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 4)
                Text("重置 \(resetText)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// 理论节奏线的快速说明气泡，只作为根视图悬浮层展示，不参与额度卡片布局。
private struct PaceMarkerHelpBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
            .allowsHitTesting(false)
    }
}

/// 参考 CodexBar 的菜单卡片进度条，用单个 Canvas 绘制轨道、填充和内嵌刻度线。
private struct WorkdayMarkedProgressView: View {
    let value: Double
    let tint: Color
    let markers: [Double]
    let paceMarker: ProgressPaceMarker?
    let onPaceMarkerHoverChange: (Bool) -> Void
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        progressBody
            .overlay {
                GeometryReader { proxy in
                    if let paceMarker {
                        paceMarkerOverlay(marker: paceMarker, size: proxy.size)
                    }
                }
                .allowsHitTesting(paceMarker != nil)
            }
    }

    private var progressBody: some View {
        Canvas { context, size in
            drawProgress(context: &context, size: size)
        }
            .frame(height: 6)
            .accessibilityLabel("用量进度")
            .accessibilityValue("\(Int(min(max(value, 0), 100)))%")
    }

    /// 只在理论节奏线附近建立悬浮热区，避免鼠标经过整条进度条时频繁弹出说明。
    @ViewBuilder
    private func paceMarkerOverlay(marker: ProgressPaceMarker, size: CGSize) -> some View {
        let x = size.width * Self.clampedPercent(marker.percent) / 100
        Color.clear
            .frame(width: Self.paceMarkerHitWidth, height: Self.paceMarkerHitHeight)
            .contentShape(Rectangle())
            .position(x: x, y: size.height / 2)
            .onHover { isHovered in
                onPaceMarkerHoverChange(isHovered)
            }
    }

    /// 绘制完整进度条；让 body 只负责组合 tooltip，避免悬浮提示逻辑和绘制逻辑混在一起。
    private func drawProgress(context: inout GraphicsContext, size: CGSize) {
        let scale = max(displayScale, 1)
        let rect = CGRect(origin: .zero, size: size)
        let cornerRadius = size.height / 2
        let cornerSize = CGSize(width: cornerRadius, height: cornerRadius)
        let clampedValue = min(max(value, 0), 100)
        let fillWidth = size.width * clampedValue / 100

        context.clip(to: Path(rect))

        let trackPath = Path { path in
            path.addRoundedRect(in: rect, cornerSize: cornerSize)
        }
        context.fill(trackPath, with: .color(Color.primary.opacity(0.10)))

        if fillWidth > 0 {
            let fillRect = CGRect(
                x: 0,
                y: 0,
                width: min(fillWidth, size.width),
                height: size.height
            )
            let fillPath = Path { path in
                path.addRoundedRect(in: fillRect, cornerSize: cornerSize)
            }
            context.fill(fillPath, with: .color(tint))
        }

        for marker in markers.map(Self.clampedPercent).filter({ $0 > 0 && $0 < 100 }) {
            let x = size.width * marker / 100
            let markerRect = Self.markerRect(x: x, size: size, scale: scale)
            let markerPath = Path { path in
                path.addRoundedRect(
                    in: markerRect,
                    cornerSize: CGSize(width: markerRect.width / 2, height: markerRect.width / 2)
                )
            }
            context.fill(markerPath, with: .color(Color.primary.opacity(0.54)))
        }

        if let paceMarker {
            let x = size.width * Self.clampedPercent(paceMarker.percent) / 100
            let stripes = Self.paceMarkerPaths(x: x, size: size, scale: scale)
            context.blendMode = .destinationOut
            context.fill(stripes.punch, with: .color(.white.opacity(0.9)))
            context.blendMode = .normal
            context.fill(stripes.center, with: .color(paceMarker.color))
        }
    }

    /// 与 CodexBar 的刻度线保持一致：像素对齐、窄线、只占进度条中间一段高度。
    private static func markerRect(x: CGFloat, size: CGSize, scale rawScale: CGFloat) -> CGRect {
        let scale = max(rawScale, 1)
        let width = max(1 / scale, 1)
        let height = min(size.height, max(1 / scale, size.height * 0.72))
        let align: (CGFloat) -> CGFloat = { value in
            (value * scale).rounded() / scale
        }
        return CGRect(
            x: align(x - width / 2),
            y: align((size.height - height) / 2),
            width: width,
            height: align(height)
        )
    }

    private static func clampedPercent(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    private static let paceMarkerHitWidth: CGFloat = 24
    private static let paceMarkerHitHeight: CGFloat = 22

    /// 绿色/红色节奏标记仿照 CodexBar：先挖出一条窄槽，再在中心绘制醒目的节奏线。
    private static func paceMarkerPaths(
        x: CGFloat,
        size: CGSize,
        scale rawScale: CGFloat
    ) -> (punch: Path, center: Path) {
        let scale = max(rawScale, 1)
        let align: (CGFloat) -> CGFloat = { value in
            (value * scale).rounded() / scale
        }
        let stripeWidth: CGFloat = 2
        let punchWidth = stripeWidth * 3
        let extendedHeight = size.height * 3
        let y = align(-size.height)
        let height = align(extendedHeight)
        let punchRect = CGRect(
            x: align(x - punchWidth / 2),
            y: y,
            width: punchWidth,
            height: height
        )
        let centerRect = CGRect(
            x: align(x - stripeWidth / 2),
            y: y,
            width: stripeWidth,
            height: height
        )
        return (
            Path { path in path.addRect(punchRect) },
            Path { path in path.addRect(centerRect) }
        )
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

private struct PaceComparisonSection: View {
    let displays: [UsageWindowPaceDisplay]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("用量速度", systemImage: "speedometer")
                .foregroundStyle(.secondary)
            ForEach(displays) { paceDisplay in
                PaceComparisonLine(display: paceDisplay)
            }
        }
        .font(.caption2)
        .menuSectionCard(padding: 8)
    }
}

private struct PaceComparisonLine: View {
    let display: UsageWindowPaceDisplay

    private var settings: MenuBarDisplaySettings {
        MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(display.title)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Text(display.display.valueText)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(display.display.tone.statusBarColor(settings: settings))
            Spacer(minLength: 6)
            Text(display.display.detailText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AdditionalRateLimitView: View {
    let limit: AdditionalRateLimitSnapshot
    let formatter: UsageFormatter
    let settings: MenuBarDisplaySettings
    let resetTimeDisplayStyle: ResetTimeDisplayStyle
    let onPaceMarkerHoverChange: (String?, Bool) -> Void

    var body: some View {
        let primaryPaceMarker = paceMarker(for: limit.primary)
        let secondaryPaceMarker = paceMarker(for: limit.secondary)
        HStack(spacing: 8) {
            QuotaSummaryCard(
                title: "\(displayName) 5 小时",
                display: UsageMetricDisplay(title: "\(displayName) 5 小时", window: limit.primary),
                resetText: resetText(for: limit.primary),
                tone: UsageRemainingTone(remainingPercent: limit.primary?.remainingPercent),
                settings: settings,
                workdayMarkers: [],
                paceMarker: primaryPaceMarker,
                onPaceMarkerHoverChange: updateActivePaceHelpText
            )
            QuotaSummaryCard(
                title: "\(displayName) 7 天",
                display: UsageMetricDisplay(title: "\(displayName) 7 天", window: limit.secondary),
                resetText: resetText(for: limit.secondary),
                tone: UsageRemainingTone(remainingPercent: limit.secondary?.remainingPercent),
                settings: settings,
                workdayMarkers: weeklyWorkdayMarkerPercents(
                    workDays: settings.weeklyProgressWorkDays,
                    windowDurationMins: limit.secondary?.windowDurationMins
                ),
                paceMarker: secondaryPaceMarker,
                onPaceMarkerHoverChange: updateActivePaceHelpText
            )
        }
    }

    private var displayName: String {
        limit.displayName
            .replacingOccurrences(of: "GPT-5.3-", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }

    /// 根据弹窗时间样式格式化额外额度的重置文案。
    private func resetText(for window: RateLimitWindow?) -> String {
        switch resetTimeDisplayStyle {
        case .countdown:
            return formatter.resetRemainingText(window: window)
        case .absolute:
            return formatter.resetTime(epochSeconds: window?.resetsAt)
        }
    }

    /// 额外额度也按同一语义展示理论节奏线，避免主额度和额外额度的进度条含义不一致。
    private func paceMarker(for window: RateLimitWindow?) -> ProgressPaceMarker? {
        guard let pace = window?.usagePace(weeklyProgressWorkDays: settings.weeklyProgressWorkDays),
              pace.isDisplayable(),
              abs(pace.roundedDeltaPercent) > 2
        else {
            return nil
        }
        return ProgressPaceMarker(
            percent: 100 - pace.expectedUsedPercent,
            color: pace.deltaPercent <= 0 ? .green : .red,
            helpText: pace.deltaPercent <= 0
                ? "绿色线：按当前时间进度推算的理论剩余位置；绿色表示实际用得比理论慢，有余量。"
                : "红色线：按当前时间进度推算的理论剩余位置；红色表示实际用得比理论快，可能提前耗尽。"
        )
    }

    /// 额外额度同样把节奏线说明放在卡片组下方，避免被后续内容覆盖。
    private func updateActivePaceHelpText(_ text: String?, _ isHovered: Bool) {
        onPaceMarkerHoverChange(text, isHovered)
    }
}

private struct ProfileStatsSection: View {
    let stats: CodexProfileStats
    @Binding var activityMode: TokenActivityMode
    let formatter: UsageFormatter
    let popoverSettings: PopoverDisplaySettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Profile")

            if popoverSettings.showsProfileOverview {
                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 6) {
                    ProfileMetric(title: "累计 Token", value: formatter.tokenCount(stats.lifetimeTokens))
                    ProfileMetric(title: "峰值 Token", value: formatter.tokenCount(stats.peakDailyTokens))
                    ProfileMetric(title: "最长任务", value: formatter.compactDuration(seconds: stats.longestRunningTurnSeconds))
                    ProfileMetric(title: "连续天数", value: streakText)
                }
                .menuSectionCard(padding: 8)
            }

            if popoverSettings.showsTokenActivity {
                TokenActivitySection(
                    stats: stats,
                    activityMode: $activityMode,
                    formatter: formatter
                )
            }

            if popoverSettings.showsActivityInsights {
                ActivityInsightsSection(stats: stats, formatter: formatter)
            }

            if popoverSettings.showsTopInvocations, !stats.topInvocations.isEmpty {
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

private extension PopoverDisplaySettings {
    /// Profile 数据分成多个模块显示；全部关闭时整块 Profile 区域都隐藏。
    var showsAnyProfileSection: Bool {
        showsProfileOverview || showsTokenActivity || showsActivityInsights || showsTopInvocations
    }
}
