import AppKit
import CodexMeterShared
import Foundation
import SwiftUI

enum MenuBarDisplayPreset: String, CaseIterable, Identifiable {
    case compact
    case balanced
    case relaxed

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .compact:
            return "紧凑"
        case .balanced:
            return "平衡"
        case .relaxed:
            return "宽松"
        }
    }

    var summary: String {
        switch self {
        case .compact:
            return "最小占位，适合菜单栏空间紧张"
        case .balanced:
            return "稍微放松间距，兼顾占位和可读性"
        case .relaxed:
            return "更大字号和行距，优先保证可读"
        }
    }

    var symbolName: String {
        switch self {
        case .compact:
            return "rectangle.compress.vertical"
        case .balanced:
            return "rectangle.split.2x1"
        case .relaxed:
            return "rectangle.expand.vertical"
        }
    }

    var settings: MenuBarDisplaySettings {
        switch self {
        case .compact:
            return MenuBarDisplaySettings(
                layoutDensity: .compact,
                itemSpacing: 1,
                rowSpacing: -2,
                numberFontSize: 10,
                numberFontWeight: .medium
            )
        case .balanced:
            return MenuBarDisplaySettings(
                layoutDensity: .compact,
                itemSpacing: 2,
                rowSpacing: -1,
                numberFontSize: 10,
                numberFontWeight: .medium
            )
        case .relaxed:
            return MenuBarDisplaySettings(
                layoutDensity: .normal,
                itemSpacing: 3,
                rowSpacing: 0,
                numberFontSize: 10.5,
                numberFontWeight: .semibold
            )
        }
    }

    static func matchingPreset(for settings: MenuBarDisplaySettings) -> MenuBarDisplayPreset? {
        allCases.first { preset in
            let presetSettings = preset.settings
            return settings.layoutDensity == presetSettings.layoutDensity
                && settings.itemSpacing == presetSettings.itemSpacing
                && settings.rowSpacing == presetSettings.rowSpacing
                && settings.numberFontSize == presetSettings.numberFontSize
                && settings.numberFontWeight == presetSettings.numberFontWeight
        }
    }
}

/// 把多个排版字段收敛成常用布局选择；无法匹配两档公开预设时保留为自定义，不改写历史配置。
enum MenuBarLayoutChoice: String, CaseIterable, Identifiable {
    case compact
    case standard
    case custom

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .compact:
            return "紧凑"
        case .standard:
            return "标准"
        case .custom:
            return "自定义"
        }
    }

    var preset: MenuBarDisplayPreset? {
        switch self {
        case .compact:
            return .compact
        case .standard:
            return .balanced
        case .custom:
            return nil
        }
    }

    /// 将当前排版字段映射到公开布局；宽松预设与任意微调值都按自定义展示以保留原值。
    static func matching(settings: MenuBarDisplaySettings) -> Self {
        switch MenuBarDisplayPreset.matchingPreset(for: settings) {
        case .compact:
            return .compact
        case .balanced:
            return .standard
        case .relaxed, .none:
            return .custom
        }
    }
}

enum MenuBarColorPreset: String, CaseIterable, Identifiable {
    case standard
    case soft
    case highContrast

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .standard:
            return "默认"
        case .soft:
            return "柔和"
        case .highContrast:
            return "高对比"
        }
    }

    var summary: String {
        switch self {
        case .standard:
            return "沿用当前绿色、橙色和红色"
        case .soft:
            return "降低饱和度，更适合浅色窗口"
        case .highContrast:
            return "提升区分度，适合远距离扫读"
        }
    }

    var symbolName: String {
        switch self {
        case .standard:
            return "circle.grid.3x3"
        case .soft:
            return "paintpalette"
        case .highContrast:
            return "circle.lefthalf.filled"
        }
    }

    var colors: (goodColorHex: String, warningColorHex: String, dangerColorHex: String) {
        switch self {
        case .standard:
            return (
                MenuBarDisplaySettings.defaultGoodColorHex,
                MenuBarDisplaySettings.defaultWarningColorHex,
                MenuBarDisplaySettings.defaultDangerColorHex
            )
        case .soft:
            return ("#32D583", "#FDB022", "#F97066")
        case .highContrast:
            return ("#00C853", "#FFB000", "#FF3B30")
        }
    }

    static func matchingPreset(
        for colors: (goodColorHex: String, warningColorHex: String, dangerColorHex: String)
    ) -> MenuBarColorPreset? {
        let normalizedColors = (
            goodColorHex: MenuBarDisplaySettings.normalizedColorHex(
                colors.goodColorHex,
                fallback: MenuBarDisplaySettings.defaultGoodColorHex
            ),
            warningColorHex: MenuBarDisplaySettings.normalizedColorHex(
                colors.warningColorHex,
                fallback: MenuBarDisplaySettings.defaultWarningColorHex
            ),
            dangerColorHex: MenuBarDisplaySettings.normalizedColorHex(
                colors.dangerColorHex,
                fallback: MenuBarDisplaySettings.defaultDangerColorHex
            )
        )

        return allCases.first { preset in
            let presetColors = preset.colors
            return normalizedColors.goodColorHex == presetColors.goodColorHex
                && normalizedColors.warningColorHex == presetColors.warningColorHex
                && normalizedColors.dangerColorHex == presetColors.dangerColorHex
        }
    }
}

enum MenuBarPopoverPositioning {
    static let defaultVerticalGap: CGFloat = 4

    static func alignedFrame(
        popoverFrame: NSRect,
        anchorScreenRect: NSRect,
        verticalGap: CGFloat = defaultVerticalGap
    ) -> NSRect {
        var alignedFrame = popoverFrame
        alignedFrame.origin.y += anchorScreenRect.minY - verticalGap - popoverFrame.maxY
        return alignedFrame
    }
}

struct UsageMetricDisplay: Equatable {
    let title: String
    let window: RateLimitWindow?
    var language: AppLanguage = .chineseSimplified

    var remainingText: String {
        window?.remainingPercentText ?? "--"
    }

    var usedText: String {
        if AppLocalization.usesEnglish(language: language) {
            return window.map { "Used \(Int($0.usedPercent.rounded()))%" } ?? "Used --"
        }
        return window.map { "已用 \(Int($0.usedPercent.rounded()))%" } ?? "已用 --"
    }

    var windowDurationText: String {
        let english = AppLocalization.usesEnglish(language: language)
        guard let minutes = window?.windowDurationMins else {
            return english ? "Window --" : "窗口 --"
        }
        if minutes % 1_440 == 0 {
            return english ? "Window \(minutes / 1_440) days" : "窗口 \(minutes / 1_440) 天"
        }
        if minutes % 60 == 0 {
            return english ? "Window \(minutes / 60) hours" : "窗口 \(minutes / 60) 小时"
        }
        return english ? "Window \(minutes) minutes" : "窗口 \(minutes) 分钟"
    }

    var progressValue: Double {
        Double(window?.remainingPercent ?? 0)
    }
}

/// 描述菜单栏的横向组合；Codex 与 Antigravity 各自保留自己的纵向读数。
struct MenuBarStatusDisplay: Equatable {
    let codexLines: [StatusLineDisplay]
    let trailingGeminiLines: [StatusLineDisplay]

    var allLines: [StatusLineDisplay] {
        codexLines + trailingGeminiLines
    }
}

/// 描述一个用量窗口的圆形指标数据；颜色继续沿用额度状态，不改变原有阈值。
struct MenuBarUsageWindowDisplay: Equatable {
    let label: String
    let remainingPercent: Int
    let tone: UsageRemainingTone
}

/// 菜单栏紧凑用量指标的数据；单窗口绘制饼图，双窗口绘制两层环形图。
struct MenuBarUsageBarDisplay: Equatable {
    let windows: [MenuBarUsageWindowDisplay]

    /// 保留单窗口初始化，兼容已有调用方和测试数据。
    init(remainingPercent: Int, tone: UsageRemainingTone) {
        self.windows = [MenuBarUsageWindowDisplay(
            label: "用量",
            remainingPercent: remainingPercent,
            tone: tone
        )]
    }

    /// 限制最多两个窗口，避免未来接口返回额外窗口时破坏菜单栏尺寸。
    init(windows: [MenuBarUsageWindowDisplay]) {
        self.windows = Array(windows.prefix(2))
    }

    /// 返回首个窗口的剩余量，兼容旧调用方的单值读取。
    var remainingPercent: Int {
        windows.first?.remainingPercent ?? 0
    }

    /// 返回首个窗口的状态色，兼容旧调用方的单值读取。
    var tone: UsageRemainingTone {
        windows.first?.tone ?? .unavailable
    }
}

/// 绘制单窗口剩余额度的扇形，百分比只控制图形面积，不参与额度计算。
private struct UsagePieSlice: Shape {
    let progress: CGFloat

    /// 将剩余比例转换为从正上方开始的圆形扇区路径。
    func path(in rect: CGRect) -> Path {
        let value = max(0, min(1, progress))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        guard value > 0 else { return Path() }
        if value >= 0.999 {
            return Path(ellipseIn: rect)
        }

        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * Double(value)),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// 绘制与真实菜单栏共用的圆形用量指标，设置预览和状态栏保持同一尺寸。
struct MenuBarUsageBarView: View {
    nonisolated static let width: CGFloat = 18
    static let height: CGFloat = 18

    let display: MenuBarUsageBarDisplay
    let settings: MenuBarDisplaySettings
    let isDisabled: Bool

    /// 根据窗口数量选择饼图或双层环形图，并把禁用状态统一压低对比度。
    var body: some View {
        indicator
            .frame(width: Self.width, height: Self.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityText))
    }

    /// 绘制单窗口饼图或 5 小时、7 天双窗口环形图。
    @ViewBuilder
    private var indicator: some View {
        if display.windows.count == 1, let window = display.windows.first {
            pieIndicator(window)
        } else if display.windows.count >= 2,
                  let first = display.windows.first,
                  let second = display.windows.dropFirst().first {
            ZStack {
                ringIndicator(first, diameter: Self.width, lineWidth: 2.3)
                ringIndicator(second, diameter: Self.width - 6, lineWidth: 2.1)
            }
        } else {
            EmptyView()
        }
    }

    /// 绘制单窗口饼图；低额度时保留淡色底环，避免 0% 看起来像数据缺失。
    private func pieIndicator(_ window: MenuBarUsageWindowDisplay) -> some View {
        let color = indicatorColor(for: window)
        let fraction = normalizedFraction(window.remainingPercent)
        return ZStack {
            Circle()
                .fill(color.opacity(0.22))
            UsagePieSlice(progress: fraction)
                .fill(color)
            Circle()
                .stroke(Color.primary.opacity(isDisabled ? 0.16 : 0.42), lineWidth: 1)
        }
    }

    /// 绘制单个窗口环形图；外环与内环分别代表传入的两个窗口。
    private func ringIndicator(
        _ window: MenuBarUsageWindowDisplay,
        diameter: CGFloat,
        lineWidth: CGFloat
    ) -> some View {
        let color = indicatorColor(for: window)
        let fraction = normalizedFraction(window.remainingPercent)
        return ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    /// 将百分比限制到图形可接受的 0 到 1 范围。
    private func normalizedFraction(_ percent: Int) -> CGFloat {
        CGFloat(max(0, min(100, percent))) / 100
    }

    /// 根据窗口状态取色；关闭的 Antigravity 只降低对比度，不改变窗口结构。
    private func indicatorColor(for window: MenuBarUsageWindowDisplay) -> Color {
        isDisabled
            ? Color.secondary.opacity(0.42)
            : window.tone.statusBarColor(settings: settings)
    }

    /// 生成辅助功能文本，让两个窗口的含义在图形模式下仍然可读。
    private var accessibilityText: String {
        let values = display.windows.map { "\($0.label) \($0.remainingPercent)%" }
        return values.isEmpty ? "用量" : "用量 \(values.joined(separator: "，"))"
    }
}

struct StatusLineDisplay: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let tone: UsageRemainingTone

    /// 只有额度和 Pace 数值使用状态色；身份、时间、费用等辅助信息保持系统默认色。
    var usesUsageColor: Bool {
        switch id {
        case "primary", "secondary", "weekly", "session", "pace-remaining", "pace-delta",
             "fiveHourPaceRemaining", "fiveHourPaceDelta", "weeklyPaceRemaining", "weeklyPaceDelta",
             "gemini-primary", "gemini-secondary", "gemini-pace-remaining",
             "gemini-pace-delta", "gemini-pace-fallback", "gemini-weekly", "gemini-five-hour",
             "geminiFiveHourPaceRemaining", "geminiFiveHourPaceDelta",
             "geminiWeeklyPaceRemaining", "geminiWeeklyPaceDelta":
            return true
        default:
            return false
        }
    }

    /// 根据当前设置生成菜单栏组合；Antigravity 不参与 Codex 主体的纵向行数计算。
    @MainActor
    static func menuBarDisplay(
        viewModel: UsageViewModel,
        settings: MenuBarDisplaySettings
    ) -> MenuBarStatusDisplay {
        menuBarDisplay(
            snapshot: viewModel.snapshot,
            settings: settings,
            geminiSnapshot: viewModel.geminiSnapshot
        )
    }

    /// 保留旧的扁平接口，供设置预览和历史测试继续读取所有展示行。
    @MainActor
    static func lines(viewModel: UsageViewModel, settings: MenuBarDisplaySettings) -> [StatusLineDisplay] {
        menuBarDisplay(viewModel: viewModel, settings: settings).allLines
    }

    /// 统一生成 Codex 主体和 Antigravity 右侧摘要；可注入配置供预览和测试使用。
    static func menuBarDisplay(
        snapshot: UsageSnapshot?,
        settings: MenuBarDisplaySettings,
        geminiSettings: GeminiModelsSettings? = nil,
        geminiSnapshot: GeminiModelsSnapshot? = nil
    ) -> MenuBarStatusDisplay {
        let geminiSettings = geminiSettings ?? GeminiModelsSettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        let codexLines = codexLines(snapshot: snapshot, settings: settings)
        return MenuBarStatusDisplay(
            codexLines: codexLines,
            trailingGeminiLines: geminiLines(
                displaySettings: settings,
                geminiSettings: geminiSettings,
                snapshot: geminiSnapshot
            )
        )
    }

    /// 保留历史调用方需要的扁平行列表；真正菜单栏布局使用 menuBarDisplay 的横向组合。
    static func lines(
        snapshot: UsageSnapshot?,
        settings: MenuBarDisplaySettings,
        geminiSettings: GeminiModelsSettings? = nil,
        geminiSnapshot: GeminiModelsSnapshot? = nil
    ) -> [StatusLineDisplay] {
        menuBarDisplay(
            snapshot: snapshot,
            settings: settings,
            geminiSettings: geminiSettings,
            geminiSnapshot: geminiSnapshot
        ).allLines
    }

    /// 根据 Codex 内容模式生成纵向主体行；Antigravity 由外层作为右侧两行渲染。
    private static func codexLines(
        snapshot: UsageSnapshot?,
        settings: MenuBarDisplaySettings
    ) -> [StatusLineDisplay] {
        if settings.contentMode == .paceComparison,
           let paceDisplay = UsagePaceDisplay(rateLimits: snapshot?.rateLimits) {
            return paceLines(paceDisplay: paceDisplay, settings: settings)
        }

        var lines: [StatusLineDisplay] = []
        if let primary = snapshot?.rateLimits.primary, settings.showsQuotaWindow(primary) {
            lines.append(StatusLineDisplay(
                id: "primary",
                label: primary.compactDurationLabel,
                value: formattedValue(primary.remainingPercentText, settings: settings),
                tone: UsageRemainingTone(remainingPercent: primary.remainingPercent)
            ))
        }
        if let secondary = snapshot?.rateLimits.secondary, settings.showsQuotaWindow(secondary) {
            lines.append(StatusLineDisplay(
                id: "secondary",
                label: secondary.compactDurationLabel,
                value: formattedValue(secondary.remainingPercentText, settings: settings),
                tone: UsageRemainingTone(remainingPercent: secondary.remainingPercent)
            ))
        }
        if lines.isEmpty, snapshot == nil {
            lines.append(StatusLineDisplay(
                id: "fallback-primary",
                label: "quota",
                value: "--",
                tone: .unavailable
            ))
        }
        return lines
    }

    /// Pace 模式只显示百分比和预期消耗偏差，不套用剩余额度的标签宽度。
    static func paceLines(paceDisplay: UsagePaceDisplay, settings: MenuBarDisplaySettings) -> [StatusLineDisplay] {
        [
            StatusLineDisplay(
                id: "pace-remaining",
                label: "",
                value: formattedValue(paceDisplay.remainingPercentText, settings: settings),
                tone: UsageRemainingTone(remainingPercent: paceDisplay.remainingPercent)
            ),
            StatusLineDisplay(
                id: "pace-delta",
                label: "",
                value: paceDisplay.deltaText,
                tone: paceDisplay.tone
            )
        ]
    }

    /// 把启用的 Antigravity 配额组渲染成菜单栏摘要；Pace 模式与 Codex 一样只显示一组两行数值。
    static func geminiLines(
        displaySettings: MenuBarDisplaySettings,
        geminiSettings: GeminiModelsSettings,
        snapshot: GeminiModelsSnapshot?
    ) -> [StatusLineDisplay] {
        guard geminiSettings.isEnabled, geminiSettings.showsInMenuBar else {
            return []
        }
        let windows = constrainedGeminiWindows(geminiSettings: geminiSettings, snapshot: snapshot)
        let weeklyWindow = windows.weekly
        let fiveHourWindow = windows.fiveHour

        if displaySettings.contentMode == .paceComparison {
            // Antigravity 有 5h 时，剩余百分比和预期消耗偏差都取 5h；没有 5h 才回退到 7d。
            let paceSourceWindow = fiveHourWindow ?? weeklyWindow
            if let paceDisplay = UsagePaceDisplay(
                percentWindow: paceSourceWindow?.rateLimitWindow,
                paceWindow: paceSourceWindow?.rateLimitWindow,
                weeklyProgressWorkDays: displaySettings.weeklyProgressWorkDays
            ) {
                return paceLines(paceDisplay: paceDisplay, settings: displaySettings).map { line in
                    StatusLineDisplay(
                        id: "gemini-\(line.id)",
                        label: line.label,
                        value: line.value,
                        tone: line.tone
                    )
                }
            }

            let fallbackWindow = paceSourceWindow
            return [StatusLineDisplay(
                id: "gemini-pace-fallback",
                label: "",
                value: fallbackWindow?.remainingPercentText.map {
                    formattedValue($0, settings: displaySettings)
                } ?? "--",
                tone: UsageRemainingTone(remainingPercent: fallbackWindow?.remainingPercent)
            )]
        }

        return [("weekly", "7d"), ("five-hour", "5h")].map { horizon, label in
            let window = horizon == "weekly" ? weeklyWindow : fiveHourWindow
            let value = window?.remainingPercentText.map {
                    formattedValue($0, settings: displaySettings)
                } ?? "--"
            return StatusLineDisplay(
                id: "gemini-\(horizon)",
                label: label,
                value: value,
                tone: UsageRemainingTone(remainingPercent: window?.remainingPercent)
            )
        }
    }

    /// 按周期选择 Antigravity 最紧张的窗口，供摘要和自定义布局共用同一数据来源。
    private static func constrainedGeminiWindows(
        geminiSettings: GeminiModelsSettings,
        snapshot: GeminiModelsSnapshot?
    ) -> (weekly: GeminiQuotaWindow?, fiveHour: GeminiQuotaWindow?) {
        guard geminiSettings.isEnabled, geminiSettings.showsInMenuBar else {
            return (nil, nil)
        }
        let groups = snapshot?.groups.filter { geminiSettings.model.matches(group: $0) } ?? []
        let candidates = groups.flatMap { group in
            group.windows
                .filter { !$0.disabled }
                .map { (groupID: group.id, window: $0) }
        }

        /// 按周期取最紧张的可用窗口；全部模型模式下会跳过已耗尽组，所有组耗尽时才显示 0%。
        func mostConstrainedWindow(for horizon: String) -> GeminiQuotaWindow? {
            let horizonCandidates = candidates.filter { horizonKey(for: $0.window) == horizon }
            let availableCandidates: [(groupID: String, window: GeminiQuotaWindow)]
            if geminiSettings.model == .all {
                availableCandidates = horizonCandidates.filter { ($0.window.remainingPercent ?? 0) > 0 }
            } else {
                availableCandidates = horizonCandidates
            }
            let candidatesToRank = availableCandidates.isEmpty ? horizonCandidates : availableCandidates
            return candidatesToRank
                .min { lhs, rhs in
                    let lhsRemaining = lhs.window.remainingPercent ?? 101
                    let rhsRemaining = rhs.window.remainingPercent ?? 101
                    if lhsRemaining != rhsRemaining {
                        return lhsRemaining < rhsRemaining
                    }
                    return "\(lhs.groupID)-\(lhs.window.bucketId)" < "\(rhs.groupID)-\(rhs.window.bucketId)"
                }
                .map { $0.window }
        }

        return (
            weekly: mostConstrainedWindow(for: "weekly"),
            fiveHour: mostConstrainedWindow(for: "five-hour")
        )
    }

    /// 将 Antigravity 接口返回的窗口名称归一为菜单栏使用的短周期键。
    private static func horizonKey(for window: GeminiQuotaWindow) -> String {
        let text = "\(window.bucketId) \(window.title)".lowercased()
        if text.contains("week") || text.contains("7d") {
            return "weekly"
        }
        if text.contains("five") || text.contains("5h") || text.contains("hour") {
            return "five-hour"
        }
        return window.bucketId.lowercased()
    }

    /// 统一处理隐藏百分号的设置，避免宽度计算和真实文字展示不一致。
    static func formattedValue(_ value: String, settings: MenuBarDisplaySettings) -> String {
        guard !settings.showsPercentSymbol, value.hasSuffix("%") else {
            return value
        }
        return String(value.dropLast())
    }
}

extension StatusLineDisplay {
    /// 按自定义布局项目解析 Codex 行；布局项目不再依赖菜单栏内容模式的行顺序。
    static func layoutLine(
        for token: MenuBarLayoutToken,
        snapshot: UsageSnapshot?,
        settings: MenuBarDisplaySettings,
        now: Date = Date()
    ) -> StatusLineDisplay? {
        switch token {
        case .primary:
            return quotaLayoutLine(
                id: "primary",
                window: quotaWindow(snapshot: snapshot, durationMins: 5 * 60),
                settings: settings
            )
        case .secondary:
            return quotaLayoutLine(
                id: "secondary",
                window: quotaWindow(snapshot: snapshot, durationMins: 7 * 24 * 60),
                settings: settings
            )
        case .paceRemaining, .paceDelta:
            guard let paceDisplay = UsagePaceDisplay(rateLimits: snapshot?.rateLimits, now: now) else {
                // Pace 刚重置或进度不足时仍保留主窗口的真实剩余量，只隐藏无法计算的偏差。
                guard token == .paceRemaining,
                      let window = snapshot?.rateLimits.primary ?? snapshot?.rateLimits.secondary else {
                    return nil
                }
                return StatusLineDisplay(
                    id: "pace-remaining",
                    label: "",
                    value: formattedValue(window.remainingPercentText, settings: settings),
                    tone: UsageRemainingTone(remainingPercent: window.remainingPercent)
                )
            }
            let paceLines = Self.paceLines(paceDisplay: paceDisplay, settings: settings)
            let paceLineID = token == .paceRemaining ? "pace-remaining" : "pace-delta"
            guard let line = paceLines.first(where: { $0.id == paceLineID }) else {
                return nil
            }
            return line
        case .fiveHourPaceRemaining, .fiveHourPaceDelta:
            return windowPaceLayoutLine(
                for: token,
                window: quotaWindow(snapshot: snapshot, durationMins: 5 * 60),
                settings: settings,
                now: now
            )
        case .weeklyPaceRemaining, .weeklyPaceDelta:
            return windowPaceLayoutLine(
                for: token,
                window: quotaWindow(snapshot: snapshot, durationMins: 7 * 24 * 60),
                settings: settings,
                now: now
            )
        case .provider, .account, .plan, .resetCountdown, .resetTime, .depletionETA,
             .balance, .todayCost, .monthCost:
            return codexAdditionalLine(
                for: token,
                snapshot: snapshot,
                settings: settings,
                now: now
            )
        case .usageBar:
            return nil
        case .icon, .geminiIcon,
             .geminiPrimary, .geminiSecondary, .geminiPaceRemaining, .geminiPaceDelta,
             .geminiFiveHourPaceRemaining, .geminiFiveHourPaceDelta,
             .geminiWeeklyPaceRemaining, .geminiWeeklyPaceDelta,
             .geminiProvider, .geminiAccount, .geminiPlan, .geminiUsageBar,
             .geminiResetCountdown, .geminiResetTime, .geminiDepletionETA, .geminiBalance,
             .geminiTodayCost, .geminiMonthCost,
             .geminiRemaining, .geminiDelta,
             .separator, .space, .stackPlaceholder:
            return nil
        }
    }

    /// 按布局项目解析 Antigravity 的固定窗口或 Pace 读数，缺少数据时直接隐藏而不是填入占位符。
    static func layoutGeminiLine(
        for token: MenuBarLayoutToken,
        settings: MenuBarDisplaySettings,
        geminiSettings: GeminiModelsSettings,
        snapshot: GeminiModelsSnapshot?
    ) -> StatusLineDisplay? {
        let windows = constrainedGeminiWindows(geminiSettings: geminiSettings, snapshot: snapshot)
        switch token {
        case .geminiProvider, .geminiAccount, .geminiPlan, .geminiResetCountdown, .geminiResetTime,
             .geminiDepletionETA, .geminiBalance, .geminiTodayCost, .geminiMonthCost:
            return geminiAdditionalLine(
                for: token,
                settings: settings,
                geminiSettings: geminiSettings,
                snapshot: snapshot,
                windows: windows
            )
        case .geminiUsageBar:
            return nil
        case .geminiPrimary, .geminiDelta:
            return geminiQuotaLayoutLine(
                id: "gemini-primary",
                window: windows.fiveHour,
                settings: settings
            )
        case .geminiSecondary, .geminiRemaining:
            return geminiQuotaLayoutLine(
                id: "gemini-secondary",
                window: windows.weekly,
                settings: settings
            )
        case .geminiPaceRemaining, .geminiPaceDelta:
            let sourceWindow = windows.fiveHour ?? windows.weekly
            if let paceWindow = sourceWindow?.rateLimitWindow,
               let paceDisplay = UsagePaceDisplay(
                   percentWindow: paceWindow,
                   paceWindow: paceWindow,
                   weeklyProgressWorkDays: settings.weeklyProgressWorkDays
               ) {
                let paceLineID = token == .geminiPaceRemaining ? "pace-remaining" : "pace-delta"
                return paceLines(paceDisplay: paceDisplay, settings: settings)
                    .first(where: { $0.id == paceLineID })
            }

            // Antigravity 的窗口刚重置时，自动剩余仍显示主窗口数值，避免预览和菜单栏整项变空。
            guard token == .geminiPaceRemaining,
                  let sourceWindow,
                  let remainingPercent = sourceWindow.remainingPercent,
                  let remainingPercentText = sourceWindow.remainingPercentText else {
                return nil
            }
            return StatusLineDisplay(
                id: "pace-remaining",
                label: "",
                value: formattedValue(remainingPercentText, settings: settings),
                tone: UsageRemainingTone(remainingPercent: remainingPercent)
            )
        case .geminiFiveHourPaceRemaining, .geminiFiveHourPaceDelta:
            return windowPaceLayoutLine(
                for: token,
                window: windows.fiveHour?.rateLimitWindow,
                settings: settings,
                now: Date()
            )
        case .geminiWeeklyPaceRemaining, .geminiWeeklyPaceDelta:
            return windowPaceLayoutLine(
                for: token,
                window: windows.weekly?.rateLimitWindow,
                settings: settings,
                now: Date()
            )
        default:
            return nil
        }
    }

    /// 解析 Codex 的身份、重置、预测、余额和本机费用项目；缺少可信数据时直接隐藏项目。
    private static func codexAdditionalLine(
        for token: MenuBarLayoutToken,
        snapshot: UsageSnapshot?,
        settings: MenuBarDisplaySettings,
        now: Date
    ) -> StatusLineDisplay? {
        let window = snapshot?.rateLimits.primary ?? snapshot?.rateLimits.secondary
        let formatter = menuBarFormatter
        switch token {
        case .provider:
            return textLine(id: "provider", value: "Codex")
        case .account:
            return textLine(id: "account", value: snapshot?.accountEmail)
        case .plan:
            return textLine(id: "plan", value: snapshot?.accountPlanDisplayText)
        case .resetCountdown:
            guard formatter.resetRemainingSeconds(window: window, now: now) != nil else { return nil }
            return textLine(id: "reset-countdown", value: formatter.resetRemainingText(window: window, now: now))
        case .resetTime:
            guard let resetsAt = window?.resetsAt else { return nil }
            return textLine(id: "reset-time", value: formatter.resetTime(epochSeconds: resetsAt, now: now))
        case .depletionETA:
            guard let rateLimits = snapshot?.rateLimits,
                  let pace = UsagePaceDisplay(
                      percentWindow: rateLimits.primary ?? rateLimits.secondary,
                      paceWindow: rateLimits.secondary ?? rateLimits.primary,
                      now: now,
                      weeklyProgressWorkDays: settings.weeklyProgressWorkDays
                  ) else {
                return nil
            }
            return textLine(id: "depletion-eta", value: pace.widgetProjectionText)
        case .balance:
            guard let credits = snapshot?.rateLimits.credits else { return nil }
            if credits.unlimited {
                return textLine(id: "balance", value: "无限")
            }
            guard credits.hasCredits else { return nil }
            return textLine(id: "balance", value: credits.balance)
        case .todayCost:
            return estimatedCostLine(
                id: "today-cost",
                value: snapshot?.localCodexUsage?.dailyBuckets?.last?.estimatedCostUSD
            )
        case .monthCost:
            return estimatedCostLine(
                id: "month-cost",
                value: snapshot?.localCodexUsage?.monthCost?.estimatedCostUSD
            )
        default:
            return nil
        }
    }

    /// 解析 Antigravity 的身份和窗口项目；当前没有余额与费用接口时保持不可见。
    private static func geminiAdditionalLine(
        for token: MenuBarLayoutToken,
        settings: MenuBarDisplaySettings,
        geminiSettings: GeminiModelsSettings,
        snapshot: GeminiModelsSnapshot?,
        windows: (weekly: GeminiQuotaWindow?, fiveHour: GeminiQuotaWindow?)
    ) -> StatusLineDisplay? {
        guard geminiSettings.isEnabled, geminiSettings.showsInMenuBar else { return nil }
        let sourceWindow = windows.fiveHour ?? windows.weekly
        let formatter = menuBarFormatter
        switch token {
        case .geminiProvider:
            return textLine(id: "gemini-provider", value: "Antigravity")
        case .geminiAccount:
            return textLine(id: "gemini-account", value: snapshot?.accountEmail)
        case .geminiPlan:
            return textLine(id: "gemini-plan", value: snapshot?.planName)
        case .geminiResetCountdown:
            guard let rateLimitWindow = sourceWindow?.rateLimitWindow,
                  formatter.resetRemainingSeconds(window: rateLimitWindow) != nil else {
                return nil
            }
            return textLine(
                id: "gemini-reset-countdown",
                value: formatter.resetRemainingText(window: rateLimitWindow)
            )
        case .geminiResetTime:
            guard let resetsAt = sourceWindow?.resetsAt else { return nil }
            return textLine(
                id: "gemini-reset-time",
                value: formatter.resetTime(epochSeconds: Int(resetsAt.timeIntervalSince1970))
            )
        case .geminiDepletionETA:
            guard let rateLimitWindow = sourceWindow?.rateLimitWindow,
                  let pace = UsagePaceDisplay(
                      percentWindow: rateLimitWindow,
                      paceWindow: rateLimitWindow,
                      weeklyProgressWorkDays: settings.weeklyProgressWorkDays
                  ) else {
                return nil
            }
            return textLine(id: "gemini-depletion-eta", value: pace.widgetProjectionText)
        case .geminiBalance, .geminiTodayCost, .geminiMonthCost:
            return nil
        default:
            return nil
        }
    }

    /// 将纯文本项目统一转换为无标签状态行，避免没有数据时写入占位符。
    private static func textLine(id: String, value: String?) -> StatusLineDisplay? {
        guard let value, !value.isEmpty, value != "--" else { return nil }
        return StatusLineDisplay(id: id, label: "", value: value, tone: .good)
    }

    /// 生成本机日志推算的 API 等效金额；具体是否为账单金额由项目名称和设置上下文说明。
    private static func estimatedCostLine(id: String, value: Double?) -> StatusLineDisplay? {
        guard let value else { return nil }
        return textLine(id: id, value: String(format: "$%.2f", value))
    }

    /// 统一读取菜单栏语言，让重置时间和预计耗尽文案与应用偏好一致。
    private static var menuBarFormatter: UsageFormatter {
        let rawLanguage = MenuBarDisplaySettings.sharedDefaults.string(
            forKey: AppLanguagePreferenceKeys.selectedLanguage
        ) ?? ""
        return UsageFormatter(language: AppLanguage(rawValue: rawLanguage) ?? .system)
    }

    /// 解析 Codex 用量指标；存在 5 小时和 7 天窗口时同时返回两个窗口。
    static func layoutUsageBar(
        for token: MenuBarLayoutToken,
        snapshot: UsageSnapshot?
    ) -> MenuBarUsageBarDisplay? {
        guard token == .usageBar else {
            return nil
        }
        let windows = [snapshot?.rateLimits.primary, snapshot?.rateLimits.secondary].compactMap {
            window -> MenuBarUsageWindowDisplay? in
            guard let window else { return nil }
            return MenuBarUsageWindowDisplay(
                label: window.compactDurationLabel,
                remainingPercent: window.remainingPercent,
                tone: UsageRemainingTone(remainingPercent: window.remainingPercent)
            )
        }
        guard !windows.isEmpty else { return nil }
        return MenuBarUsageBarDisplay(windows: windows)
    }

    /// 解析 Antigravity 用量指标；同时存在 5 小时和 7 天窗口时绘制双层环形图。
    static func layoutGeminiUsageBar(
        for token: MenuBarLayoutToken,
        geminiSettings: GeminiModelsSettings,
        snapshot: GeminiModelsSnapshot?
    ) -> MenuBarUsageBarDisplay? {
        guard token == .geminiUsageBar,
              geminiSettings.isEnabled,
              geminiSettings.showsInMenuBar else {
            return nil
        }
        let windows = constrainedGeminiWindows(geminiSettings: geminiSettings, snapshot: snapshot)
        let indicators = [
            (label: "5h", window: windows.fiveHour),
            (label: "7d", window: windows.weekly)
        ].compactMap { entry -> MenuBarUsageWindowDisplay? in
            guard let remainingPercent = entry.window?.remainingPercent else { return nil }
            return MenuBarUsageWindowDisplay(
                label: entry.label,
                remainingPercent: remainingPercent,
                tone: UsageRemainingTone(remainingPercent: remainingPercent)
            )
        }
        guard !indicators.isEmpty else {
            return nil
        }
        return MenuBarUsageBarDisplay(windows: indicators)
    }

    /// 将 Antigravity 固定周期窗口转换成布局可直接显示的实际读数。
    private static func geminiQuotaLayoutLine(
        id: String,
        window: GeminiQuotaWindow?,
        settings: MenuBarDisplaySettings
    ) -> StatusLineDisplay? {
        guard let window,
              let remainingPercent = window.remainingPercent,
              let remainingPercentText = window.remainingPercentText else {
            return nil
        }
        return StatusLineDisplay(
            id: id,
            label: window.rateLimitWindow?.compactDurationLabel ?? "",
            value: formattedValue(remainingPercentText, settings: settings),
            tone: UsageRemainingTone(remainingPercent: remainingPercent)
        )
    }

    /// 按实际窗口时长解析固定的 5 小时或 7 天项目，避免 API 调换 primary/secondary 后重复显示 7d。
    private static func quotaWindow(snapshot: UsageSnapshot?, durationMins: Int) -> RateLimitWindow? {
        [snapshot?.rateLimits.primary, snapshot?.rateLimits.secondary]
            .compactMap { $0 }
            .first { $0.windowDurationMins == durationMins }
    }

    /// 为固定窗口项目保留真实标签；没有当前数据时直接隐藏，避免菜单栏出现占位符。
    private static func quotaLayoutLine(
        id: String,
        window: RateLimitWindow?,
        settings: MenuBarDisplaySettings
    ) -> StatusLineDisplay? {
        guard let window else { return nil }
        return StatusLineDisplay(
            id: id,
            label: window.compactDurationLabel,
            value: formattedValue(window.remainingPercentText, settings: settings),
            tone: UsageRemainingTone(remainingPercent: window.remainingPercent)
        )
    }

    /// 按指定 5 小时或 7 天窗口计算独立 Pace；进度不足时只保留自动剩余，避免误导性的偏差值。
    private static func windowPaceLayoutLine(
        for token: MenuBarLayoutToken,
        window: RateLimitWindow?,
        settings: MenuBarDisplaySettings,
        now: Date
    ) -> StatusLineDisplay? {
        let showsRemaining: Bool
        switch token {
        case .fiveHourPaceRemaining, .weeklyPaceRemaining,
             .geminiFiveHourPaceRemaining, .geminiWeeklyPaceRemaining:
            showsRemaining = true
        case .fiveHourPaceDelta, .weeklyPaceDelta,
             .geminiFiveHourPaceDelta, .geminiWeeklyPaceDelta:
            showsRemaining = false
        default:
            return nil
        }

        guard let window else {
            return nil
        }
        if let paceDisplay = UsageWindowPaceDisplay(
            id: token.rawValue,
            title: window.durationLabel,
            window: window,
            now: now,
            weeklyProgressWorkDays: settings.weeklyProgressWorkDays
        )?.display {
            return StatusLineDisplay(
                id: token.rawValue,
                label: "",
                value: formattedValue(
                    showsRemaining ? paceDisplay.remainingPercentText : paceDisplay.deltaText,
                    settings: settings
                ),
                tone: showsRemaining
                    ? UsageRemainingTone(remainingPercent: paceDisplay.remainingPercent)
                    : paceDisplay.tone
            )
        }

        guard showsRemaining else {
            return nil
        }
        return StatusLineDisplay(
            id: token.rawValue,
            label: "",
            value: formattedValue(window.remainingPercentText, settings: settings),
            tone: UsageRemainingTone(remainingPercent: window.remainingPercent)
        )
    }
}

/// 自定义布局解析后的最小项目；状态栏和设置页预览共用同一份结果。
enum ResolvedMenuBarLayoutItem: Equatable {
    case icon
    case geminiIcon
    case line(StatusLineDisplay)
    case usageBar(MenuBarUsageBarDisplay)
    case separator
    case space
}

/// 将持久化布局绑定到当前快照和 Gemini 尾部数据；外层数组横向排列，内层数组纵向堆叠。
struct MenuBarLayoutDisplay: Equatable {
    let items: [[ResolvedMenuBarLayoutItem]]
    let trailingGeminiLines: [StatusLineDisplay]

    /// 在每个菜单栏项目中解析额度内容，保证状态栏和预览使用相同的堆叠语义。
    init(
        layout: MenuBarLayout,
        snapshot: UsageSnapshot?,
        settings: MenuBarDisplaySettings,
        geminiSettings: GeminiModelsSettings? = nil,
        geminiSnapshot: GeminiModelsSnapshot? = nil
    ) {
        let resolvedGeminiSettings = geminiSettings
            ?? GeminiModelsSettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        let visibleLayout = resolvedGeminiSettings.isEnabled
            ? layout.items
            : layout.items.map { item in
                item.filter { !$0.isGeminiToken }
            }
        items = visibleLayout.compactMap { item in
            let resolvedItems: [ResolvedMenuBarLayoutItem] = item.compactMap { token -> ResolvedMenuBarLayoutItem? in
                switch token {
                case .icon:
                    return .icon
                case .geminiIcon:
                    return .geminiIcon
                case .separator:
                    return .separator
                case .space:
                    return .space
                case .stackPlaceholder:
                    return nil
                case .primary, .secondary, .paceRemaining, .paceDelta,
                     .fiveHourPaceRemaining, .fiveHourPaceDelta,
                     .weeklyPaceRemaining, .weeklyPaceDelta:
                    return StatusLineDisplay.layoutLine(
                        for: token,
                        snapshot: snapshot,
                        settings: settings
                    ).map(ResolvedMenuBarLayoutItem.line)
                case .provider, .account, .plan, .resetCountdown, .resetTime, .depletionETA,
                     .balance, .todayCost, .monthCost:
                    return StatusLineDisplay.layoutLine(
                        for: token,
                        snapshot: snapshot,
                        settings: settings
                    ).map(ResolvedMenuBarLayoutItem.line)
                case .usageBar:
                    return StatusLineDisplay.layoutUsageBar(
                        for: token,
                        snapshot: snapshot
                    ).map(ResolvedMenuBarLayoutItem.usageBar)
                case .geminiPrimary, .geminiSecondary, .geminiPaceRemaining, .geminiPaceDelta,
                     .geminiFiveHourPaceRemaining, .geminiFiveHourPaceDelta,
                     .geminiWeeklyPaceRemaining, .geminiWeeklyPaceDelta,
                     .geminiProvider, .geminiAccount, .geminiPlan,
                     .geminiResetCountdown, .geminiResetTime, .geminiDepletionETA,
                     .geminiBalance, .geminiTodayCost, .geminiMonthCost,
                     .geminiRemaining, .geminiDelta:
                    return StatusLineDisplay.layoutGeminiLine(
                        for: token,
                        settings: settings,
                        geminiSettings: resolvedGeminiSettings,
                        snapshot: geminiSnapshot
                    ).map(ResolvedMenuBarLayoutItem.line)
                case .geminiUsageBar:
                    return StatusLineDisplay.layoutGeminiUsageBar(
                        for: token,
                        geminiSettings: resolvedGeminiSettings,
                        snapshot: geminiSnapshot
                    ).map(ResolvedMenuBarLayoutItem.usageBar)
                }
            }
            return resolvedItems.isEmpty ? nil : resolvedItems
        }
        // 自定义布局完全控制菜单栏内容，未放入布局的 Antigravity 项目不再从旧模式回退显示。
        trailingGeminiLines = []
    }

    /// 返回布局中的所有额度项目，供宽度和无障碍文字计算使用。
    var codexLines: [StatusLineDisplay] {
        items.flatMap { item in
            item.compactMap { resolvedItem in
                guard case let .line(line) = resolvedItem else { return nil }
                return line
            }
        }
    }
}

/// 单行菜单栏交给 NSStatusBarButton 原生标题渲染，使用 13pt Regular 系统排版。
enum NativeStatusBarTitle {
    static let fontSize = NSFont.systemFontSize

    /// 只有一行时返回原生标题；双行仍由 SwiftUI 负责排版。
    static func text(for lines: [StatusLineDisplay]) -> String? {
        guard let line = lines.only else { return nil }
        return line.label.isEmpty ? line.value : "\(line.label) \(line.value)"
    }

    /// 保留原生状态栏字体，仅对数值片段应用用户的状态颜色。
    static func attributedText(
        for line: StatusLineDisplay,
        settings: MenuBarDisplaySettings,
        font: NSFont
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if !line.label.isEmpty {
            result.append(NSAttributedString(
                string: "\(line.label) ",
                attributes: [.font: font, .foregroundColor: NSColor.labelColor]
            ))
        }
        let valueColor = line.usesUsageColor
            ? NSColor(settings.color(for: line.tone))
            : NSColor.labelColor
        result.append(NSAttributedString(
            string: line.value,
            attributes: [.font: font, .foregroundColor: valueColor]
        ))
        return result
    }

    /// 稳定预设跟随 NSStatusBarButton 的原生字体；自定义布局才应用用户调整的字号和字重。
    static func font(
        settings: MenuBarDisplaySettings,
        nativeFont: NSFont = NSFont.systemFont(ofSize: fontSize)
    ) -> NSFont {
        guard MenuBarLayoutChoice.matching(settings: settings) == .custom else {
            return nativeFont
        }
        return NSFont.systemFont(
            ofSize: settings.numberFontSize,
            weight: settings.numberFontWeight.nsFontWeight
        )
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}

enum StatusBarDisplayMetrics {
    static let trailingProviderSeparatorSpacing: CGFloat = 8
    static let trailingGeminiIconWidth: CGFloat = 13
    static let trailingGeminiIconTextSpacing: CGFloat = 3

    /// 按 Codex 主体和 Antigravity 右侧两行摘要的真实宽度计算菜单栏项目宽度。
    static func statusItemWidth(
        for lines: [StatusLineDisplay],
        settings: MenuBarDisplaySettings,
        activityDisplay: CodexHookActivityDisplay = CodexHookActivityDisplay(snapshot: nil),
        trailingLines: [StatusLineDisplay] = []
    ) -> CGFloat {
        if trailingLines.isEmpty, !activityDisplay.isVisible, let title = NativeStatusBarTitle.text(for: lines) {
            let textWidth = textWidth(title, font: NativeStatusBarTitle.font(settings: settings))
            let iconWidth = showsCodexIcon(settings: settings, activityDisplay: activityDisplay)
                ? MenuBarDisplaySettings.menuBarIconWidth + MenuBarDisplaySettings.menuBarIconTextSpacing
                : 0
            let activityWidth = settings.showsHookActivityLight ? activityDisplay.statusItemWidth : 0
            return ceil(textWidth + iconWidth + activityWidth)
        }
        let usesSingleLineTypography = lines.count == 1
        let mainTextWidth = lines
            .map {
                lineWidth(
                    for: $0,
                    settings: settings,
                    usesSingleLineTypography: usesSingleLineTypography
                )
            }
            .max() ?? minimumTextWidth(settings: settings)
        let trailingTextWidth = trailingLines.isEmpty
            ? 0
            : trailingProviderSeparatorSpacing
                + trailingGeminiIconWidth
                + trailingGeminiIconTextSpacing
                + (trailingLines
                    .map { lineWidth(for: $0, settings: settings) }
                    .max() ?? 0)
        let iconWidth = showsCodexIcon(settings: settings, activityDisplay: activityDisplay)
            ? MenuBarDisplaySettings.menuBarIconWidth + MenuBarDisplaySettings.menuBarIconTextSpacing
            : 0
        let activityWidth = settings.showsHookActivityLight ? activityDisplay.statusItemWidth : 0
        let densityPadding: CGFloat = settings.layoutDensity == .normal ? 2 : 0

        return max(
            ceil(activityWidth + iconWidth + mainTextWidth + trailingTextWidth + densityPadding),
            minimumStatusItemWidth(settings: settings, activityDisplay: activityDisplay)
        )
    }

    /// 按横向项目和项目内堆叠内容测量状态栏，图标与分隔项目参与同一套间距计算。
    static func statusItemWidth(
        for layout: MenuBarLayout,
        display: MenuBarLayoutDisplay,
        settings: MenuBarDisplaySettings,
        activityDisplay: CodexHookActivityDisplay = CodexHookActivityDisplay(snapshot: nil)
    ) -> CGFloat {
        let itemWidths = display.items.map { item in
            let usesSingleLineTypography = item.count <= 1
            return item.map { itemWidth(
                for: $0,
                settings: settings,
                activityDisplay: activityDisplay,
                usesSingleLineTypography: usesSingleLineTypography
            ) }.max() ?? 0
        }
        let itemSpacing = CGFloat(max(0, itemWidths.count - 1)) * CGFloat(settings.itemSpacing)
        let mainTextWidth = itemWidths.reduce(0, +) + itemSpacing
        let prefixActivityWidth = activityDisplay.isVisible && !layout.containsIcon
            ? activityDisplay.statusItemWidth
            : 0
        let trailingTextWidth = display.trailingGeminiLines.isEmpty
            ? 0
            : trailingProviderSeparatorSpacing
                + trailingGeminiIconWidth
                + trailingGeminiIconTextSpacing
                + (display.trailingGeminiLines
                    .map { lineWidth(for: $0, settings: settings) }
                    .max() ?? 0)
        let densityPadding: CGFloat = settings.layoutDensity == .normal ? 2 : 0
        let minimumWidth = max(18, prefixActivityWidth)
        return max(
            ceil(mainTextWidth + prefixActivityWidth + trailingTextWidth + densityPadding),
            minimumWidth
        )
    }

    /// 返回单个解析项目的实际宽度；额度文字沿用已有的等宽数字测量规则。
    private static func itemWidth(
        for item: ResolvedMenuBarLayoutItem,
        settings: MenuBarDisplaySettings,
        activityDisplay: CodexHookActivityDisplay,
        usesSingleLineTypography: Bool
    ) -> CGFloat {
        switch item {
        case .icon:
            return activityDisplay.isVisible
                ? activityDisplay.statusItemWidth
                : MenuBarDisplaySettings.menuBarIconWidth
        case .geminiIcon:
            return trailingGeminiIconWidth
        case let .line(line):
            return lineWidth(
                for: line,
                settings: settings,
                usesSingleLineTypography: usesSingleLineTypography
            )
        case .usageBar:
            return MenuBarUsageBarView.width
        case .separator:
            return textWidth("·", font: layoutFont(settings: settings, usesSingleLineTypography: usesSingleLineTypography))
        case .space:
            return max(4, CGFloat(settings.itemSpacing))
        }
    }

    /// 统一分隔点和额度项目的字体测量，避免自定义布局宽度与 SwiftUI 字体不一致。
    private static func layoutFont(
        settings: MenuBarDisplaySettings,
        usesSingleLineTypography: Bool
    ) -> NSFont {
        let fontSize = usesSingleLineTypography
            ? NativeStatusBarTitle.font(settings: settings).pointSize
            : min(settings.numberFontSize, 9)
        let fontWeight = usesSingleLineTypography
            && MenuBarLayoutChoice.matching(settings: settings) != .custom
            ? NSFont.Weight.regular
            : settings.numberFontWeight.nsFontWeight
        return NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: fontWeight)
    }

    /// 根据标签和值分别测量单行宽度，只有剩余额度模式会因为 label 额外变宽。
    static func lineWidth(
        for line: StatusLineDisplay,
        settings: MenuBarDisplaySettings,
        usesSingleLineTypography: Bool = false
    ) -> CGFloat {
        let fontSize = usesSingleLineTypography
            ? NativeStatusBarTitle.font(settings: settings).pointSize
            : min(settings.numberFontSize, 9)
        let fontWeight = usesSingleLineTypography
            && MenuBarLayoutChoice.matching(settings: settings) != .custom
            ? NSFont.Weight.regular
            : settings.numberFontWeight.nsFontWeight
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: fontSize,
            weight: fontWeight
        )
        let valueWidth = textWidth(line.value, font: font)
        guard !line.label.isEmpty else {
            return valueWidth
        }
        return textWidth(line.label, font: font) + CGFloat(settings.itemSpacing) + valueWidth
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func minimumTextWidth(settings: MenuBarDisplaySettings) -> CGFloat {
        settings.contentMode == .paceComparison ? 18 : 24
    }

    private static func minimumStatusItemWidth(
        settings: MenuBarDisplaySettings,
        activityDisplay: CodexHookActivityDisplay
    ) -> CGFloat {
        let iconWidth = showsCodexIcon(settings: settings, activityDisplay: activityDisplay)
            ? MenuBarDisplaySettings.menuBarIconWidth + MenuBarDisplaySettings.menuBarIconTextSpacing
            : 0
        let activityWidth = settings.showsHookActivityLight ? activityDisplay.statusItemWidth : 0
        return activityWidth + iconWidth + minimumTextWidth(settings: settings)
    }

    /// 活动符号显示时替代 Codex 图标；宽度计算和实际 SwiftUI 渲染保持同一套互斥规则。
    private static func showsCodexIcon(
        settings: MenuBarDisplaySettings,
        activityDisplay: CodexHookActivityDisplay
    ) -> Bool {
        settings.showsMenuBarIcon && !activityDisplay.isVisible
    }
}

private extension MenuBarNumberFontWeight {
    var nsFontWeight: NSFont.Weight {
        switch self {
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        }
    }
}

struct CodexConfigurationInfo: Equatable {
    struct Row: Equatable, Identifiable {
        let title: String
        let value: String

        var id: String {
            title
        }
    }

    let dataSource: String
    let endpoint: String
    let profileEndpoint: String
    let codexHomePath: String
    let authFileExists: Bool

    var displayRows: [Row] {
        [
            Row(title: "数据来源", value: dataSource),
            Row(title: "接口", value: endpoint),
            Row(title: "Profile", value: profileEndpoint),
            Row(title: "CODEX_HOME", value: codexHomePath),
            Row(title: "登录信息", value: authFileExists ? "已找到" : "未找到")
        ]
    }

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        store: UsageSnapshotStore = UsageSnapshotStore()
    ) -> CodexConfigurationInfo {
        let authFileURL = DirectCodexUsageClient.defaultAuthFileURL(environment: environment)

        return CodexConfigurationInfo(
            dataSource: "ChatGPT Codex usage",
            endpoint: DirectCodexUsageClient.defaultEndpointURL.absoluteString,
            profileEndpoint: DirectCodexUsageClient.defaultProfileEndpointURL.absoluteString,
            codexHomePath: authFileURL.deletingLastPathComponent().path,
            authFileExists: FileManager.default.fileExists(atPath: authFileURL.path)
        )
    }
}

extension Color {
    var hexRGB: String? {
        guard let color = NSColor(self).usingColorSpace(.deviceRGB) else {
            return nil
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}
