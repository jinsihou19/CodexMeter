import AppKit
import CodexUsageShared
import Foundation
import SwiftUI

enum MenuBarPreferenceKeys {
    static let layoutDensity = "menuBar.layoutDensity"
    static let itemSpacing = "menuBar.itemSpacing"
    static let rowSpacing = "menuBar.rowSpacing"
    static let numberFontSize = "menuBar.numberFontSize"
    static let numberFontWeight = "menuBar.numberFontWeight"
    static let goodColorHex = "menuBar.goodColorHex"
    static let warningColorHex = "menuBar.warningColorHex"
    static let dangerColorHex = "menuBar.dangerColorHex"
    static let showsPrimaryWindow = "menuBar.showsPrimaryWindow"
    static let showsSecondaryWindow = "menuBar.showsSecondaryWindow"
    static let showsPercentSymbol = "menuBar.showsPercentSymbol"
}

enum MenuBarNumberFontWeight: String, CaseIterable, Identifiable {
    case regular
    case medium
    case semibold

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .regular:
            return "偏细"
        case .medium:
            return "适中"
        case .semibold:
            return "偏粗"
        }
    }

    var fontWeight: Font.Weight {
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

enum MenuBarLayoutDensity: String, CaseIterable, Identifiable {
    case compact
    case normal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .compact:
            return "紧凑"
        case .normal:
            return "正常"
        }
    }

    var statusItemWidth: CGFloat {
        switch self {
        case .compact:
            return 38
        case .normal:
            return 40
        }
    }
}

struct MenuBarDisplaySettings: Equatable {
    static let defaultLayoutDensity = MenuBarLayoutDensity.compact
    static let defaultItemSpacing = 1.0
    static let defaultRowSpacing = -2.0
    static let defaultNumberFontSize = 9.0
    static let defaultNumberFontWeight = MenuBarNumberFontWeight.medium
    static let defaultGoodColorHex = "#1AB85C"
    static let defaultWarningColorHex = "#F5931A"
    static let defaultDangerColorHex = "#F23838"
    static let defaultShowsPrimaryWindow = true
    static let defaultShowsSecondaryWindow = true
    static let defaultShowsPercentSymbol = true

    let layoutDensity: MenuBarLayoutDensity
    let itemSpacing: Double
    let rowSpacing: Double
    let numberFontSize: Double
    let numberFontWeight: MenuBarNumberFontWeight
    let goodColorHex: String
    let warningColorHex: String
    let dangerColorHex: String
    let showsPrimaryWindow: Bool
    let showsSecondaryWindow: Bool
    let showsPercentSymbol: Bool

    init(
        layoutDensity: MenuBarLayoutDensity = Self.defaultLayoutDensity,
        itemSpacing: Double = Self.defaultItemSpacing,
        rowSpacing: Double = Self.defaultRowSpacing,
        numberFontSize: Double = Self.defaultNumberFontSize,
        numberFontWeight: MenuBarNumberFontWeight = Self.defaultNumberFontWeight,
        goodColorHex: String = Self.defaultGoodColorHex,
        warningColorHex: String = Self.defaultWarningColorHex,
        dangerColorHex: String = Self.defaultDangerColorHex,
        showsPrimaryWindow: Bool = Self.defaultShowsPrimaryWindow,
        showsSecondaryWindow: Bool = Self.defaultShowsSecondaryWindow,
        showsPercentSymbol: Bool = Self.defaultShowsPercentSymbol
    ) {
        self.layoutDensity = layoutDensity
        self.itemSpacing = Self.clamp(itemSpacing, min: 0, max: 8)
        self.rowSpacing = Self.clamp(rowSpacing, min: -5, max: 6)
        self.numberFontSize = Self.clamp(numberFontSize, min: 7, max: 13)
        self.numberFontWeight = numberFontWeight
        self.goodColorHex = Self.normalizedColorHex(goodColorHex, fallback: Self.defaultGoodColorHex)
        self.warningColorHex = Self.normalizedColorHex(warningColorHex, fallback: Self.defaultWarningColorHex)
        self.dangerColorHex = Self.normalizedColorHex(dangerColorHex, fallback: Self.defaultDangerColorHex)
        self.showsPrimaryWindow = showsPrimaryWindow || !showsSecondaryWindow
        self.showsSecondaryWindow = showsSecondaryWindow || !showsPrimaryWindow
        self.showsPercentSymbol = showsPercentSymbol
    }

    init(defaults: UserDefaults = .standard) {
        self.init(
            layoutDensity: MenuBarLayoutDensity(
                rawValue: defaults.string(forKey: MenuBarPreferenceKeys.layoutDensity) ?? ""
            ) ?? Self.defaultLayoutDensity,
            itemSpacing: defaults.object(forKey: MenuBarPreferenceKeys.itemSpacing) as? Double
                ?? Self.defaultItemSpacing,
            rowSpacing: defaults.object(forKey: MenuBarPreferenceKeys.rowSpacing) as? Double
                ?? Self.defaultRowSpacing,
            numberFontSize: defaults.object(forKey: MenuBarPreferenceKeys.numberFontSize) as? Double
                ?? Self.defaultNumberFontSize,
            numberFontWeight: MenuBarNumberFontWeight(
                rawValue: defaults.string(forKey: MenuBarPreferenceKeys.numberFontWeight) ?? ""
            ) ?? Self.defaultNumberFontWeight,
            goodColorHex: defaults.string(forKey: MenuBarPreferenceKeys.goodColorHex)
                ?? Self.defaultGoodColorHex,
            warningColorHex: defaults.string(forKey: MenuBarPreferenceKeys.warningColorHex)
                ?? Self.defaultWarningColorHex,
            dangerColorHex: defaults.string(forKey: MenuBarPreferenceKeys.dangerColorHex)
                ?? Self.defaultDangerColorHex,
            showsPrimaryWindow: defaults.object(forKey: MenuBarPreferenceKeys.showsPrimaryWindow) as? Bool
                ?? Self.defaultShowsPrimaryWindow,
            showsSecondaryWindow: defaults.object(forKey: MenuBarPreferenceKeys.showsSecondaryWindow) as? Bool
                ?? Self.defaultShowsSecondaryWindow,
            showsPercentSymbol: defaults.object(forKey: MenuBarPreferenceKeys.showsPercentSymbol) as? Bool
                ?? Self.defaultShowsPercentSymbol
        )
    }

    var statusItemWidth: CGFloat {
        layoutDensity.statusItemWidth
    }

    var statusLabelHeight: CGFloat {
        22
    }

    func color(for tone: UsageRemainingTone) -> Color {
        switch tone {
        case .unavailable:
            return Color(nsColor: .secondaryLabelColor)
        case .good:
            return Color(hexRGB: goodColorHex)
        case .warning:
            return Color(hexRGB: warningColorHex)
        case .danger:
            return Color(hexRGB: dangerColorHex)
        }
    }

    static func normalizedColorHex(_ value: String, fallback: String) -> String {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let prefixed = candidate.hasPrefix("#") ? candidate : "#\(candidate)"
        let pattern = /^#[0-9A-F]{6}$/
        if prefixed.wholeMatch(of: pattern) != nil {
            return prefixed
        }
        return fallback
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}

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
                numberFontSize: 9,
                numberFontWeight: .medium
            )
        case .balanced:
            return MenuBarDisplaySettings(
                layoutDensity: .normal,
                itemSpacing: 2,
                rowSpacing: -1,
                numberFontSize: 9.5,
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

    var remainingText: String {
        window.map { "\($0.remainingPercent)%" } ?? "--"
    }

    var usedText: String {
        window.map { "已用 \(Int($0.usedPercent.rounded()))%" } ?? "已用 --"
    }

    var windowDurationText: String {
        guard let minutes = window?.windowDurationMins else {
            return "窗口 --"
        }
        if minutes % 1_440 == 0 {
            return "窗口 \(minutes / 1_440) 天"
        }
        if minutes % 60 == 0 {
            return "窗口 \(minutes / 60) 小时"
        }
        return "窗口 \(minutes) 分钟"
    }

    var progressValue: Double {
        Double(window?.remainingPercent ?? 0)
    }
}

extension UsageRemainingTone {
    func statusBarColor(settings: MenuBarDisplaySettings) -> Color {
        settings.color(for: self)
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
    let codexHomePath: String
    let authFileExists: Bool

    var displayRows: [Row] {
        [
            Row(title: "数据来源", value: dataSource),
            Row(title: "接口", value: endpoint),
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
            codexHomePath: authFileURL.deletingLastPathComponent().path,
            authFileExists: FileManager.default.fileExists(atPath: authFileURL.path)
        )
    }
}

extension Color {
    init(hexRGB: String) {
        let normalized = MenuBarDisplaySettings.normalizedColorHex(
            hexRGB,
            fallback: MenuBarDisplaySettings.defaultGoodColorHex
        )
        let value = String(normalized.dropFirst())
        let scanner = Scanner(string: value)
        var hexNumber: UInt64 = 0
        scanner.scanHexInt64(&hexNumber)
        self.init(
            red: Double((hexNumber & 0xFF0000) >> 16) / 255,
            green: Double((hexNumber & 0x00FF00) >> 8) / 255,
            blue: Double(hexNumber & 0x0000FF) / 255
        )
    }

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
