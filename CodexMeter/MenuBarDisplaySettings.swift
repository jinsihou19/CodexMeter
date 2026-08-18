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

struct StatusLineDisplay: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let tone: UsageRemainingTone

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

        /// 按周期取剩余量最少的窗口；全部模型模式仍可从多个配额组中选出一个统一来源。
        func mostConstrainedWindow(for horizon: String) -> GeminiQuotaWindow? {
            candidates
                .filter { horizonKey(for: $0.window) == horizon }
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
                return nil
            }
            let paceLines = Self.paceLines(paceDisplay: paceDisplay, settings: settings)
            let paceLineID = token == .paceRemaining ? "pace-remaining" : "pace-delta"
            guard let line = paceLines.first(where: { $0.id == paceLineID }) else {
                return nil
            }
            return line
        case .icon, .geminiIcon,
             .geminiPrimary, .geminiSecondary, .geminiPaceRemaining, .geminiPaceDelta,
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
            guard let paceWindow = sourceWindow?.rateLimitWindow,
                  let paceDisplay = UsagePaceDisplay(
                      percentWindow: paceWindow,
                      paceWindow: paceWindow,
                      weeklyProgressWorkDays: settings.weeklyProgressWorkDays
                  ) else {
                return nil
            }
            let paceLineID = token == .geminiPaceRemaining ? "pace-remaining" : "pace-delta"
            return paceLines(paceDisplay: paceDisplay, settings: settings)
                .first(where: { $0.id == paceLineID })
        default:
            return nil
        }
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
}

/// 自定义布局解析后的最小项目；状态栏和设置页预览共用同一份结果。
enum ResolvedMenuBarLayoutItem: Equatable {
    case icon
    case geminiIcon
    case line(StatusLineDisplay)
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
                case .primary, .secondary, .paceRemaining, .paceDelta:
                    return StatusLineDisplay.layoutLine(
                        for: token,
                        snapshot: snapshot,
                        settings: settings
                    ).map(ResolvedMenuBarLayoutItem.line)
                case .geminiPrimary, .geminiSecondary, .geminiPaceRemaining, .geminiPaceDelta,
                     .geminiRemaining, .geminiDelta:
                    return StatusLineDisplay.layoutGeminiLine(
                        for: token,
                        settings: settings,
                        geminiSettings: resolvedGeminiSettings,
                        snapshot: geminiSnapshot
                    ).map(ResolvedMenuBarLayoutItem.line)
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
        let valueColor = line.tone == .unavailable
            ? NSColor.secondaryLabelColor
            : NSColor(settings.color(for: line.tone))
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
        let usesSingleLineTypography = layout.items.allSatisfy { $0.count <= 1 }
        let itemWidths = display.items.map { item in
            item.map { itemWidth(
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
