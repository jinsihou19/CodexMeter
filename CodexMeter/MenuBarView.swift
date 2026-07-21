import AppKit
import CodexMeterShared
import SwiftUI

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

/// 定义本机热力图的聚合口径，三种模式共享同一份逐日本机数据。
private enum LocalUsageHeatmapMode: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case cumulative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "每日"
        case .weekly: "每周"
        case .cumulative: "累计"
        }
    }
}

/// 从共享偏好解析当前应用语言，供下拉面板中的独立子视图复用。
private func currentAppLanguage() -> AppLanguage {
    AppLanguage(
        rawValue: MenuBarDisplaySettings.sharedDefaults.string(
            forKey: AppLanguagePreferenceKeys.selectedLanguage
        ) ?? ""
    ) ?? .system
}

struct MenuBarView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var radarStore: CodexRadarStore
    @ObservedObject var updater: AppUpdater
    let onSizeChange: ((CGSize) -> Void)?
    @State private var activityMode = TokenActivityMode.daily
    @State private var measuredScrollContentHeight: CGFloat = 0
    // 重建后首帧先使用安全的可滚动容器，避免未完成测量的长内容溢出弹窗。
    @State private var usesScrollableContent = true
    @State private var activePaceHelpText: String?
    @AppStorage(AppLanguagePreferenceKeys.selectedLanguage, store: MenuBarDisplaySettings.sharedDefaults) private var selectedLanguage = AppLanguage.system.rawValue
    private var formatter: UsageFormatter {
        UsageFormatter(language: currentAppLanguage())
    }
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
        radarStore: CodexRadarStore,
        updater: AppUpdater = .shared,
        onSizeChange: ((CGSize) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.radarStore = radarStore
        self.updater = updater
        self.onSizeChange = onSizeChange
    }

    var body: some View {
        themedBody
    }

    /// 将弹窗内容包在全局外观层中，确保设置页的明暗和透明度立即影响下拉框。
    @ViewBuilder private var themedBody: some View {
        let activeAppearance = appearanceSettings
        let language = AppLanguage(rawValue: selectedLanguage) ?? .system
        let baseContent = contentBody
            .environment(\.locale, language.locale)
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
        VStack(alignment: .leading, spacing: 6) {
            header

            Divider()

            contentArea
                .onPreferenceChange(MenuBarScrollContentHeightPreferenceKey.self) { height in
                    updateMeasuredScrollContentHeight(height)
                }

            Divider()

            HStack {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label(AppLocalization.string("刷新"), systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing)

                Button {
                    SettingsWindowPresenter.shared.show()
                } label: {
                    Label(AppLocalization.string("设置"), systemImage: "gearshape")
                }

                Spacer()

                if updater.isUpdateAvailable {
                    Button {
                        updater.showAvailableUpdate()
                    } label: {
                        Label(AppLocalization.string("更新"), systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .help(updater.availableVersion.map {
                        AppLocalization.usesEnglish()
                            ? "Install CodexMeter \($0)"
                            : "安装 CodexMeter \($0)"
                    } ?? AppLocalization.string("安装 CodexMeter 新版本"))
                    .accessibilityLabel(AppLocalization.string("更新 CodexMeter"))
                }

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label(AppLocalization.string("退出"), systemImage: "power")
                }
            }
        }
        .padding(.horizontal, MenuBarPopoverLayout.horizontalPadding)
        .padding(.top, MenuBarPopoverLayout.topPadding)
        .padding(.bottom, MenuBarPopoverLayout.bottomPadding)
        .frame(width: MenuBarPopoverLayout.width, alignment: .topLeading)
        // 让 AppKit 宿主按真实内容高度收缩，避免较高的初始 popover 把内容向下居中。
        .fixedSize(horizontal: false, vertical: true)
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
            Text("CodexMeter")
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
            ScrollView(.vertical, showsIndicators: false) {
                scrollContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
            let hasPreviousMeasurement = measuredScrollContentHeight > 0
            if abs(measuredScrollContentHeight - roundedHeight) > 0.5 {
                measuredScrollContentHeight = roundedHeight
            }

            let maximumHeight = MenuBarPopoverLayout.maximumScrollableContentHeight
            let hysteresis = MenuBarPopoverLayout.scrollOverflowHysteresis
            let shouldUseScrollableContent = hasPreviousMeasurement
                ? (usesScrollableContent
                    ? roundedHeight > maximumHeight - hysteresis
                    : roundedHeight > maximumHeight + hysteresis)
                : roundedHeight > maximumHeight
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
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle("额度与用量")
                Spacer()
                sourceBadge("额度", source: "云端", color: .blue)
            }

            QuotaSummaryGrid(
                snapshot: snapshot.rateLimits,
                formatter: formatter,
                settings: settings,
                showsPaceComparison: activePopoverSettings.showsPaceComparison,
                resetTimeDisplayStyle: activePopoverSettings.resetTimeDisplayStyle,
                onPaceMarkerHoverChange: updateActivePaceHelpText
            )

            if activePopoverSettings.showsResetCredits {
                ResetCreditsSection(
                    snapshot: snapshot.resetCredits,
                    isRefreshing: viewModel.isRefreshing,
                    formatter: formatter,
                    onRefresh: {
                        Task { await viewModel.refreshResetCredits() }
                    }
                )
            }

            CodexRadarSection(
                store: radarStore,
                settings: CodexRadarSettings(defaults: MenuBarDisplaySettings.sharedDefaults)
            )

            if activePopoverSettings.showsAnyLocalSection, let localCodexUsage = viewModel.localCodexUsage {
                LocalCodexUsageSection(
                    snapshot: localCodexUsage,
                    formatter: formatter,
                    settings: activePopoverSettings
                )
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

    /// 生成不抢占主指标的来源标签，明确额度与消耗的不同口径。
    private func sourceBadge(_ metric: String, source: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(AppLocalization.string(metric)) · \(AppLocalization.string(source))")
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var scrollContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let snapshot = viewModel.snapshot {
                usageContent(snapshot)
            } else {
                ContentUnavailableView(AppLocalization.string("暂无用量数据"), systemImage: "clock")
                    .frame(width: 320)
                    .padding(.vertical, 24)
            }

            if viewModel.snapshot == nil {
                CodexRadarSection(
                    store: radarStore,
                    settings: CodexRadarSettings(defaults: MenuBarDisplaySettings.sharedDefaults)
                )
                if popoverSettings.showsAnyLocalSection, let localCodexUsage = viewModel.localCodexUsage {
                    LocalCodexUsageSection(
                        snapshot: localCodexUsage,
                        formatter: formatter,
                        settings: popoverSettings
                    )
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
    let showsPaceComparison: Bool
    let resetTimeDisplayStyle: ResetTimeDisplayStyle
    let onPaceMarkerHoverChange: (String?, Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let primary = snapshot.primary {
                quotaCard(id: "primary", window: primary)
            }
            if let secondary = snapshot.secondary {
                quotaCard(id: "secondary", window: secondary)
            }
        }
    }

    /// 用接口的实际时长生成额度卡，避免把主次窗口误当成固定的 5 小时和 7 天。
    private func quotaCard(id: String, window: RateLimitWindow) -> some View {
        let title = window.localizedDurationLabel(language: currentAppLanguage())
        return QuotaSummaryCard(
            title: title,
            display: UsageMetricDisplay(title: title, window: window, language: currentAppLanguage()),
            resetText: resetText(for: window),
            paceDisplay: paceDisplay(id: id, title: title, window: window),
            tone: UsageRemainingTone(remainingPercent: window.remainingPercent),
            settings: settings,
            workdayMarkers: weeklyWorkdayMarkerPercents(
                workDays: settings.weeklyProgressWorkDays,
                windowDurationMins: window.windowDurationMins
            ),
            paceMarker: paceMarker(for: window),
            onPaceMarkerHoverChange: updateActivePaceHelpText
        )
    }

    /// 为额度卡片生成内嵌 Pace 文案；关闭用量速度时只保留基础余量信息。
    private func paceDisplay(id: String, title: String, window: RateLimitWindow?) -> UsagePaceDisplay? {
        guard showsPaceComparison else {
            return nil
        }
        return UsageWindowPaceDisplay(
            id: id,
            title: title,
            window: window,
            weeklyProgressWorkDays: settings.weeklyProgressWorkDays
        )?.display
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
            helpText: AppLocalization.string(
                pace.deltaPercent <= 0
                    ? "绿色线：按当前时间进度推算的理论剩余位置；绿色表示实际用得比理论慢，有余量。"
                    : "红色线：按当前时间进度推算的理论剩余位置；红色表示实际用得比理论快，可能提前耗尽。"
            )
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
    let paceDisplay: UsagePaceDisplay?
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

            paceDetailRow

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
                Text(usedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 4)
                Text("\(AppLocalization.string("重置")) \(resetText)")
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

    /// 将共享用量文案压缩为卡片底部短标签，并按当前语言切换前缀。
    private var usedText: String {
        if AppLocalization.usesEnglish() {
            return display.usedText
        }
        return display.usedText.replacingOccurrences(of: "已用 ", with: "用 ")
    }

    /// 在剩余额度下方展示完整 Pace 说明，让“有余量/偏快”和持续时间保持在同一行可读。
    @ViewBuilder private var paceDetailRow: some View {
        if let paceDisplay {
            Text(paceDisplay.detailText(language: currentAppLanguage()))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(paceDisplay.tone.statusBarColor(settings: settings))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .help(paceDisplay.detailText(language: currentAppLanguage()))
        }
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

/// 菜单卡片进度条用单个 Canvas 绘制轨道、填充和内嵌刻度线。
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
            .accessibilityLabel(AppLocalization.string("用量进度"))
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

    /// 刻度线保持像素对齐和窄线，只占进度条中间一段高度。
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

    /// 绿色/红色节奏标记先挖出一条窄槽，再在中心绘制醒目的节奏线。
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
        Text(AppLocalization.string(title))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// 在菜单弹窗展示只读本机 token、项目排行和今日任务，不承担数据读取职责。
private struct LocalCodexUsageSection: View {
    let snapshot: LocalCodexUsageSnapshot
    let formatter: UsageFormatter
    let settings: PopoverDisplaySettings
    @State private var heatmapMode = LocalUsageHeatmapMode.daily

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(AppLocalization.string("消耗与成本"), systemImage: "dollarsign.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let cost = snapshot.summary.monthCost {
                HStack(spacing: 4) {
                    Text(AppLocalization.string("本月估算"))
                        .foregroundStyle(.secondary)
                    Text(Self.currency(cost.estimatedCostUSD))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Spacer()
                    Text(AppLocalization.string("API 等效估算"))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption2)
            }

            if settings.showsLocalOverview {
                subsectionTitle("概览")
                overview
            }
            if settings.showsLocalOverview && (settings.showsLocalTrend || settings.showsLocalProjects) {
                Divider()
            }
            if settings.showsLocalTrend {
                trend
            }
            if settings.showsLocalTrend && settings.showsLocalProjects {
                Divider()
            }
            if settings.showsLocalProjects {
                subsectionTitle("项目")
                projects
            }
        }
        .menuSectionCard(padding: 6)
    }

    /// 生成纵向栏目的紧凑标题，和趋势标题保持同一视觉层级。
    private func subsectionTitle(_ title: String) -> some View {
        Text(AppLocalization.string(title))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// 展示最常用的 Token、费用构成和项目消耗排行。
    private var overview: some View {
        let maximum = max(1, snapshot.summary.projects.map(\.tokens).max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                metric("今日", snapshot.summary.todayTokens)
                metric("近 7 天", snapshot.summary.sevenDayTokens)
                metric("累计", snapshot.summary.lifetimeTokens)
                metric("线程", Int64(snapshot.summary.threadCount))
            }

            if let cost = snapshot.summary.monthCost {
                VStack(alignment: .leading, spacing: 5) {
                    tokenComposition(cost)
                    HStack(spacing: 10) {
                        costMetric("未缓存", max(0, cost.inputTokens - cost.cachedInputTokens), color: CodexMeterChartPalette.tokenInput)
                        costMetric("缓存输入", cost.cachedInputTokens, color: CodexMeterChartPalette.tokenCachedInput)
                        costMetric("输出", cost.outputTokens, color: CodexMeterChartPalette.tokenOutput)
                        Spacer(minLength: 0)
                        Text("\(AppLocalization.string("缓存率")) \(percent(cost.cachedInputTokens, of: cost.inputTokens))")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            }

            Divider()
            projectRanking(maximum: maximum)
        }
    }

    /// 仅用热力图展示半年 Token 活动，并允许切换逐日、逐周和累计口径。
    private var trend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppLocalization.string("趋势"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $heatmapMode) {
                    ForEach(LocalUsageHeatmapMode.allCases) { mode in
                        Text(AppLocalization.string(mode.title)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            LocalMenuUsageHeatmap(
                buckets: snapshot.summary.dailyBuckets ?? [],
                fetchedAt: snapshot.summary.fetchedAt,
                mode: heatmapMode,
                formatter: formatter
            )
            .frame(height: 82)
        }
    }

    /// 展示今日任务分类与具体条目，让项目页承接任务完成情况。
    private var projects: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                taskCount("进行中", snapshot.taskBoard.activeCount, color: .green)
                taskCount("待处理", snapshot.taskBoard.pendingCount, color: .orange)
                taskCount("定时", snapshot.taskBoard.scheduledCount, color: .blue)
                taskCount("已归档", snapshot.taskBoard.doneCount, color: .secondary)
            }
            ForEach(Array(snapshot.taskBoard.items.prefix(6))) { item in
                HStack(spacing: 6) {
                    Image(systemName: symbol(for: item.kind))
                        .frame(width: 12)
                        .foregroundStyle(color(for: item.kind))
                    Text(item.title)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let detail = item.detail {
                        Text(detail)
                            .lineLimit(1)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
            }
        }
    }

    /// 绘制项目排行条，供概览页快速比较近七天项目消耗。
    private func projectRanking(maximum: Int64) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(snapshot.summary.projects.enumerated()), id: \.element.id) { index, project in
                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .foregroundStyle(.tertiary)
                            .frame(width: 12, alignment: .trailing)
                        Text(project.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(project.threadCount) \(AppLocalization.string("线程"))")
                            .foregroundStyle(.tertiary)
                        Text(formatter.tokenCount(project.tokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(CodexMeterChartPalette.primary.opacity(0.72))
                                .frame(width: max(3, geometry.size.width * CGFloat(project.tokens) / CGFloat(maximum)))
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }

    /// 绘制本月未缓存输入、缓存输入和输出的比例条。
    private func tokenComposition(_ cost: LocalCodexCostSummary) -> some View {
        let uncached = max(0, cost.inputTokens - cost.cachedInputTokens)
        let total = max(1, uncached + cost.cachedInputTokens + cost.outputTokens)
        return GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle().fill(CodexMeterChartPalette.tokenInput)
                    .frame(width: geometry.size.width * CGFloat(uncached) / CGFloat(total))
                Rectangle().fill(CodexMeterChartPalette.tokenCachedInput)
                    .frame(width: geometry.size.width * CGFloat(cost.cachedInputTokens) / CGFloat(total))
                Rectangle().fill(CodexMeterChartPalette.tokenOutput)
                    .frame(width: geometry.size.width * CGFloat(cost.outputTokens) / CGFloat(total))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .help("\(AppLocalization.string("未缓存")) \(formatter.tokenCount(uncached)) · \(AppLocalization.string("缓存输入")) \(formatter.tokenCount(cost.cachedInputTokens)) · \(AppLocalization.string("输出")) \(formatter.tokenCount(cost.outputTokens))")
        }
        .frame(height: 7)
    }

    /// 计算紧凑百分比，分母为零时保持稳定零值。
    private func percent(_ value: Int64, of total: Int64) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int((Double(value) / Double(total) * 100).rounded()))%"
    }

    /// 生成费用拆分的紧凑 token 指标，颜色与上方构成条保持对应。
    private func costMetric(_ title: String, _ value: Int64, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(AppLocalization.string(title)).foregroundStyle(.secondary)
            Text(formatter.tokenCount(value)).monospacedDigit()
        }
        .font(.caption2)
    }

    /// 把美元估算格式化为看板短文本。
    private static func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    /// 生成固定宽度的顶部指标，线程数沿用紧凑数字格式。
    private func metric(_ title: String, _ value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(AppLocalization.string(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatter.tokenCount(value))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 生成任务分类数量标签，颜色只用于快速扫读。
    private func taskCount(_ title: String, _ value: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(AppLocalization.string(title)) \(value)")
                .lineLimit(1)
        }
        .font(.caption2)
    }

    /// 返回任务分类对应的系统图标。
    private func symbol(for kind: LocalCodexTaskKind) -> String {
        switch kind {
        case .active: "play.circle.fill"
        case .pending: "circle"
        case .scheduled: "clock"
        case .done: "checkmark.circle.fill"
        }
    }

    /// 返回任务分类对应的提示色。
    private func color(for kind: LocalCodexTaskKind) -> Color {
        switch kind {
        case .active: .green
        case .pending: .orange
        case .scheduled: .blue
        case .done: .secondary
        }
    }
}

/// 在下拉框内展示可悬停的 26 周热力图，并按选择改变聚合口径。
private struct LocalMenuUsageHeatmap: View {
    let buckets: [LocalCodexDailyUsageBucket]
    let fetchedAt: Date
    let mode: LocalUsageHeatmapMode
    let formatter: UsageFormatter
    @State private var hoveredBucketID: String?

    var body: some View {
        let colorValues = paddedBuckets()
        let detailValues = displayedBuckets(from: colorValues)
        let maximum = max(1, colorValues.compactMap { $0?.tokens }.max() ?? 1)
        let activeBucket = detailValues.compactMap(\.self).first { $0.id == hoveredBucketID }
            ?? detailValues.compactMap(\.self).last

        VStack(alignment: .leading, spacing: 4) {
            if let activeBucket {
                HStack(spacing: 6) {
                    Text(activeBucket.label).foregroundStyle(.secondary)
                    Text(formatter.tokenCount(activeBucket.tokens)).fontWeight(.semibold)
                    Spacer(minLength: 8)
                    if let estimatedCostUSD = activeBucket.estimatedCostUSD {
                        Text("\(AppLocalization.string("成本")) \(Self.currency(estimatedCostUSD))")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2.monospacedDigit())
            }

            GeometryReader { geometry in
                let spacing: CGFloat = 2
                let cellWidth = max(3, (geometry.size.width - spacing * 25) / 26)
                let rowCount = 7
                let cellHeight = max(3, (geometry.size.height - spacing * CGFloat(rowCount - 1)) / CGFloat(rowCount))
                HStack(spacing: spacing) {
                    ForEach(0..<26, id: \.self) { column in
                        VStack(spacing: spacing) {
                            ForEach(0..<rowCount, id: \.self) { row in
                                let index = column * rowCount + row
                                let colorBucket = colorValues[index]
                                let detailBucket = detailValues[index]
                                RoundedRectangle(cornerRadius: min(2, cellWidth / 3))
                                    .fill(CodexMeterChartPalette.heatmapColor(value: colorBucket?.tokens ?? 0, maximum: maximum))
                                    .overlay {
                                        if detailBucket?.id == activeBucket?.id {
                                            RoundedRectangle(cornerRadius: min(2, cellWidth / 3))
                                                .stroke(Color.primary.opacity(0.75), lineWidth: 1)
                                        }
                                    }
                                    .frame(width: cellWidth, height: cellHeight)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location):
                        let column = min(25, max(0, Int(location.x / (cellWidth + spacing))))
                        let row = min(6, max(0, Int(location.y / (cellHeight + spacing))))
                        hoveredBucketID = detailValues[column * rowCount + row]?.id
                    case .ended:
                        hoveredBucketID = nil
                    }
                }
            }
        }
    }

    /// 生成交互详情数据；颜色仍由原始逐日数据决定，模式切换不会改变热力图外观。
    private func displayedBuckets(
        from daily: [LocalCodexDailyUsageBucket?]
    ) -> [LocalCodexDailyUsageBucket?] {
        switch mode {
        case .daily:
            return daily
        case .weekly:
            return stride(from: 0, to: daily.count, by: 7).flatMap { start -> [LocalCodexDailyUsageBucket?] in
                let column = daily[start..<min(start + 7, daily.count)]
                let week = column.compactMap(\.self)
                guard let first = week.first, let last = week.last else {
                    return Array(repeating: nil, count: column.count)
                }
                let aggregate = LocalCodexDailyUsageBucket(
                    id: "week-\(first.id)",
                    label: "\(first.label)–\(last.label)",
                    tokens: week.reduce(0) { $0 + $1.tokens },
                    estimatedCostUSD: estimatedCost(for: week)
                )
                return column.map { $0 == nil ? nil : aggregate }
            }
        case .cumulative:
            var total: Int64 = 0
            var totalCost = 0.0
            var hasEstimatedCost = false
            return daily.map { bucket in
                guard let bucket else { return nil }
                total += bucket.tokens
                if let estimatedCostUSD = bucket.estimatedCostUSD {
                    totalCost += estimatedCostUSD
                    hasEstimatedCost = true
                }
                return LocalCodexDailyUsageBucket(
                    id: "cumulative-\(bucket.id)",
                    label: bucket.label,
                    tokens: total,
                    estimatedCostUSD: hasEstimatedCost ? totalCost : nil
                )
            }
        }
    }

    /// 汇总一个周列中已识别模型的 API 等效成本；没有可定价记录时不显示误导性的零金额。
    private func estimatedCost(for buckets: [LocalCodexDailyUsageBucket]) -> Double? {
        let costs = buckets.compactMap(\.estimatedCostUSD)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    /// 把热力图选中时段的 API 等效金额格式化为紧凑美元文本。
    private static func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    /// 按当前星期对齐 26 周，并用 nil 表示未来日期。
    private func paddedBuckets(calendar: Calendar = .current) -> [LocalCodexDailyUsageBucket?] {
        let trailingDays = 7 - calendar.component(.weekday, from: fetchedAt)
        let historyCount = 182 - trailingDays
        let history = Array(buckets.suffix(historyCount)).map(Optional.some)
        let leading = Array<LocalCodexDailyUsageBucket?>(repeating: nil, count: max(0, historyCount - history.count))
        let trailing = Array<LocalCodexDailyUsageBucket?>(repeating: nil, count: trailingDays)
        return leading + history + trailing
    }

}

private struct PaceComparisonSection: View {
    let displays: [UsageWindowPaceDisplay]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(AppLocalization.string("用量速度"), systemImage: "speedometer")
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
            Text(display.display.detailText(language: currentAppLanguage()))
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
        HStack(spacing: 8) {
            if let primary = limit.primary {
                quotaCard(window: primary)
            }
            if let secondary = limit.secondary {
                quotaCard(window: secondary)
            }
        }
    }

    /// 按额外额度的实际窗口时长生成卡片，并跳过接口未返回的窗口。
    private func quotaCard(window: RateLimitWindow) -> some View {
        let title = "\(displayName) \(window.localizedDurationLabel(language: currentAppLanguage()))"
        return QuotaSummaryCard(
            title: title,
            display: UsageMetricDisplay(title: title, window: window, language: currentAppLanguage()),
            resetText: resetText(for: window),
            paceDisplay: nil,
            tone: UsageRemainingTone(remainingPercent: window.remainingPercent),
            settings: settings,
            workdayMarkers: weeklyWorkdayMarkerPercents(
                workDays: settings.weeklyProgressWorkDays,
                windowDurationMins: window.windowDurationMins
            ),
            paceMarker: paceMarker(for: window),
            onPaceMarkerHoverChange: updateActivePaceHelpText
        )
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
            helpText: AppLocalization.string(
                pace.deltaPercent <= 0
                    ? "绿色线：按当前时间进度推算的理论剩余位置；绿色表示实际用得比理论慢，有余量。"
                    : "红色线：按当前时间进度推算的理论剩余位置；红色表示实际用得比理论快，可能提前耗尽。"
            )
        )
    }

    /// 额外额度同样把节奏线说明放在卡片组下方，避免被后续内容覆盖。
    private func updateActivePaceHelpText(_ text: String?, _ isHovered: Bool) {
        onPaceMarkerHoverChange(text, isHovered)
    }
}

/// 额度重置卡模块只展示接口返回的可用张数和到期时间，避免和常规用量窗口语义混淆。
private struct ResetCreditsSection: View {
    let snapshot: ResetCreditsSnapshot?
    let isRefreshing: Bool
    let formatter: UsageFormatter
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(AppLocalization.string("额度重置卡"), systemImage: "creditcard")
                    .foregroundStyle(.secondary)
                Spacer()
                if let snapshot {
                    Text(availableCountText(snapshot.availableCount))
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                if isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                }
                resetCreditsRefreshButton
            }
            .font(.caption2)

            if let snapshot {
                if snapshot.creditsSortedByExpiration.isEmpty {
                    Text(AppLocalization.string("暂无到期明细"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(snapshot.creditsSortedByExpiration.enumerated()), id: \.offset) { index, credit in
                        ResetCreditRow(index: index + 1, credit: credit, formatter: formatter)
                    }
                }
            } else {
                Text(AppLocalization.string(isRefreshing ? "正在读取重置卡..." : "暂无重置卡信息"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuSectionCard(padding: 8)
    }

    /// 重置卡专用手动刷新按钮，和底部普通刷新分离以便明确绕过重置卡每日缓存。
    private var resetCreditsRefreshButton: some View {
        Button {
            onRefresh()
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
        .imageScale(.small)
        .disabled(isRefreshing)
        .help(AppLocalization.string("刷新额度重置卡"))
        .accessibilityLabel(AppLocalization.string("刷新额度重置卡"))
    }

    /// 格式化可用重置卡数量，英文不沿用中文量词。
    private func availableCountText(_ count: Int) -> String {
        AppLocalization.usesEnglish() ? "\(count) available" : "\(count) 张可用"
    }
}

/// 单张重置卡的到期行；同时展示绝对时间和相对剩余时间，方便快速判断哪张先过期。
private struct ResetCreditRow: View {
    let index: Int
    let credit: ResetCreditSnapshot
    let formatter: UsageFormatter

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("#\(index)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
            Text(credit.localizedStatus(language: currentAppLanguage()))
                .font(.caption2.weight(.medium))
                .foregroundStyle(statusColor)
                .frame(width: 42, alignment: .leading)
            Text(formatter.resetCreditExpiration(credit.expiresAt))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(formatter.resetCreditExpirationRemaining(credit.expiresAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    private var statusColor: Color {
        switch credit.status.lowercased() {
        case "available", "active":
            return .green
        case "expired":
            return .secondary
        case "used", "consumed":
            return .orange
        default:
            return .secondary
        }
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
        let current = stats.currentStreakDays.map {
            AppLocalization.usesEnglish() ? "\($0) days" : "\($0) 天"
        } ?? "--"
        let longest = stats.longestStreakDays.map {
            AppLocalization.usesEnglish() ? "\($0) days longest" : "\($0) 天最长"
        }
        return [current, longest].compactMap(\.self).joined(separator: " · ")
    }
}

private struct ProfileMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(AppLocalization.string(title))
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(AppLocalization.string("Token 活动"))
                    .font(.caption.weight(.semibold))
                Spacer()
                Picker("", selection: $activityMode) {
                    ForEach(TokenActivityMode.allCases) { mode in
                        Text(AppLocalization.string(mode.title)).tag(mode)
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
        .padding(5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TokenActivitySummary: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(AppLocalization.string(title))
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

        VStack(alignment: .leading, spacing: 3) {
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
                        .fill(CodexMeterChartPalette.primary.opacity(isActive ? 0.95 : 0.34 + (0.44 * ratio)))
                        .overlay(alignment: .top) {
                            if isActive {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .stroke(CodexMeterChartPalette.primary, lineWidth: 1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    .frame(height: max(3, CGFloat(ratio) * 32))
                        .contentShape(Rectangle())
                        .onHover { isInside in
                            hoveredBucketID = isInside ? bucket.id : nil
                        }
                        .accessibilityLabel("\(bucket.startDate) \(bucket.tokens) tokens")
                }
            }
            .frame(height: 34, alignment: .bottom)
        }
        .frame(height: 48, alignment: .bottom)
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
                    Text(
                        AppLocalization.usesEnglish()
                            ? "\(invocation.usageCount) uses"
                            : "\(invocation.usageCount) 次"
                    )
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
            Text(AppLocalization.string(title))
                .foregroundStyle(.secondary)
            Text(AppLocalization.string(value))
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
            Text(AppLocalization.string(title))
                .foregroundStyle(.secondary)
            Spacer()
            Text(AppLocalization.string(value))
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
