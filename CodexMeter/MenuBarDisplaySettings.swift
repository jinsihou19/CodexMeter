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

enum MenuBarPreviewAppearance: CaseIterable, Identifiable {
    case light
    case dark
    case translucent

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        case .translucent:
            return "半透明"
        }
    }
}

struct UsageMetricDisplay: Equatable {
    let title: String
    let window: RateLimitWindow?
    var language: AppLanguage = .chineseSimplified

    var remainingText: String {
        window.map { "\($0.remainingPercent)%" } ?? "--"
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

struct SettingsPreviewData: Equatable {
    let snapshot: UsageSnapshot?
    let primaryValue: String
    let secondaryValue: String
    let primaryTone: UsageRemainingTone
    let secondaryTone: UsageRemainingTone
    let paceValue: String
    let compactPaceValue: String
    let paceRemainingValue: String
    let paceDeltaValue: String
    let paceRemainingTone: UsageRemainingTone
    let paceTone: UsageRemainingTone

    init(snapshot: UsageSnapshot?) {
        self.snapshot = snapshot
        self.primaryValue = Self.value(for: snapshot?.rateLimits.primary)
        self.secondaryValue = Self.value(for: snapshot?.rateLimits.secondary)
        self.primaryTone = Self.tone(for: snapshot?.rateLimits.primary?.remainingPercent)
        self.secondaryTone = Self.tone(for: snapshot?.rateLimits.secondary?.remainingPercent)
        let paceDisplay = UsagePaceDisplay(rateLimits: snapshot?.rateLimits)
        self.paceValue = paceDisplay?.valueText ?? "-- · --"
        self.compactPaceValue = paceDisplay?.compactValueText ?? "--·--"
        self.paceRemainingValue = paceDisplay.map { "\($0.remainingPercent)%" } ?? "--"
        self.paceDeltaValue = paceDisplay?.deltaText ?? "--"
        self.paceRemainingTone = Self.tone(for: paceDisplay?.remainingPercent)
        self.paceTone = paceDisplay?.tone ?? .unavailable
    }

    private static func value(for window: RateLimitWindow?) -> String {
        window.map { "\($0.remainingPercent)%" } ?? "--"
    }

    private static func tone(for remainingPercent: Int?) -> UsageRemainingTone {
        guard let remainingPercent else {
            return .unavailable
        }
        if remainingPercent < 40 {
            return .danger
        }
        if remainingPercent < 70 {
            return .warning
        }
        return .good
    }
}

struct StatusLineDisplay: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let tone: UsageRemainingTone

    /// 根据当前设置和快照生成菜单栏两行内容；Pace 和剩余额度各自走自己的展示模型。
    @MainActor
    static func lines(viewModel: UsageViewModel, settings: MenuBarDisplaySettings) -> [StatusLineDisplay] {
        lines(snapshot: viewModel.snapshot, settings: settings)
    }

    /// 统一生成真实菜单栏与设置预览的内容；Pace 无法计算时回退到当前可见额度窗口。
    static func lines(snapshot: UsageSnapshot?, settings: MenuBarDisplaySettings) -> [StatusLineDisplay] {
        if settings.contentMode == .paceComparison,
           let paceDisplay = UsagePaceDisplay(rateLimits: snapshot?.rateLimits) {
            return paceLines(paceDisplay: paceDisplay, settings: settings)
        }

        var lines: [StatusLineDisplay] = []
        if let primary = snapshot?.rateLimits.primary, settings.showsQuotaWindow(primary) {
            lines.append(StatusLineDisplay(
                id: "primary",
                label: primary.compactDurationLabel,
                value: formattedValue("\(primary.remainingPercent)%", settings: settings),
                tone: UsageRemainingTone(remainingPercent: primary.remainingPercent)
            ))
        }
        if let secondary = snapshot?.rateLimits.secondary, settings.showsQuotaWindow(secondary) {
            lines.append(StatusLineDisplay(
                id: "secondary",
                label: secondary.compactDurationLabel,
                value: formattedValue("\(secondary.remainingPercent)%", settings: settings),
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
                value: formattedValue("\(paceDisplay.remainingPercent)%", settings: settings),
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

    /// 统一处理隐藏百分号的设置，避免宽度计算和真实文字展示不一致。
    static func formattedValue(_ value: String, settings: MenuBarDisplaySettings) -> String {
        guard !settings.showsPercentSymbol, value.hasSuffix("%") else {
            return value
        }
        return String(value.dropLast())
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
    /// 按当前两行文字真实宽度计算菜单栏项目宽度，避免 Pace 和剩余额度共用同一块空白。
    static func statusItemWidth(
        for lines: [StatusLineDisplay],
        settings: MenuBarDisplaySettings,
        activityDisplay: CodexHookActivityDisplay = CodexHookActivityDisplay(snapshot: nil)
    ) -> CGFloat {
        if let title = NativeStatusBarTitle.text(for: lines) {
            let textWidth = textWidth(title, font: NativeStatusBarTitle.font(settings: settings))
            let iconWidth = showsCodexIcon(settings: settings, activityDisplay: activityDisplay)
                ? MenuBarDisplaySettings.menuBarIconWidth + MenuBarDisplaySettings.menuBarIconTextSpacing
                : 0
            let activityWidth = settings.showsHookActivityLight ? activityDisplay.statusItemWidth : 0
            return ceil(textWidth + iconWidth + activityWidth)
        }
        let textWidth = lines
            .map { lineWidth(for: $0, settings: settings) }
            .max() ?? minimumTextWidth(settings: settings)
        let iconWidth = showsCodexIcon(settings: settings, activityDisplay: activityDisplay)
            ? MenuBarDisplaySettings.menuBarIconWidth + MenuBarDisplaySettings.menuBarIconTextSpacing
            : 0
        let activityWidth = settings.showsHookActivityLight ? activityDisplay.statusItemWidth : 0
        let densityPadding: CGFloat = settings.layoutDensity == .normal ? 2 : 0

        return max(
            ceil(activityWidth + iconWidth + textWidth + densityPadding),
            minimumStatusItemWidth(settings: settings, activityDisplay: activityDisplay)
        )
    }

    /// 根据标签和值分别测量单行宽度，只有剩余额度模式会因为 label 额外变宽。
    static func lineWidth(
        for line: StatusLineDisplay,
        settings: MenuBarDisplaySettings
    ) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: settings.numberFontSize,
            weight: settings.numberFontWeight.nsFontWeight
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
