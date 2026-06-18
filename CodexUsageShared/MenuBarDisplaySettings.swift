import Foundation
import SwiftUI

public enum MenuBarPreferenceKeys {
    public static let displayDefaultsVersion = "menuBar.displayDefaultsVersion"
    public static let contentMode = "menuBar.contentMode"
    public static let layoutDensity = "menuBar.layoutDensity"
    public static let itemSpacing = "menuBar.itemSpacing"
    public static let rowSpacing = "menuBar.rowSpacing"
    public static let numberFontSize = "menuBar.numberFontSize"
    public static let numberFontWeight = "menuBar.numberFontWeight"
    public static let goodColorHex = "menuBar.goodColorHex"
    public static let warningColorHex = "menuBar.warningColorHex"
    public static let dangerColorHex = "menuBar.dangerColorHex"
    public static let showsPrimaryWindow = "menuBar.showsPrimaryWindow"
    public static let showsSecondaryWindow = "menuBar.showsSecondaryWindow"
    public static let showsPercentSymbol = "menuBar.showsPercentSymbol"
    public static let showsAdditionalLimits = "menuBar.showsAdditionalLimits"
    public static let showsMenuBarIcon = "menuBar.showsMenuBarIcon"

    public static let allKeys = [
        contentMode,
        layoutDensity,
        itemSpacing,
        rowSpacing,
        numberFontSize,
        numberFontWeight,
        goodColorHex,
        warningColorHex,
        dangerColorHex,
        showsPrimaryWindow,
        showsSecondaryWindow,
        showsPercentSymbol,
        showsAdditionalLimits,
        showsMenuBarIcon
    ]
}

public enum MenuBarContentMode: String, CaseIterable, Identifiable, Sendable {
    case paceComparison
    case remainingWindows

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .paceComparison:
            return "预期消耗对比"
        case .remainingWindows:
            return "剩余额度"
        }
    }
}

public enum UsageRemainingTone: Equatable, Sendable {
    case unavailable
    case good
    case warning
    case danger

    public init(remainingPercent: Int?) {
        guard let remainingPercent else {
            self = .unavailable
            return
        }
        if remainingPercent < 40 {
            self = .danger
        } else if remainingPercent < 70 {
            self = .warning
        } else {
            self = .good
        }
    }
}

public enum MenuBarNumberFontWeight: String, CaseIterable, Identifiable, Sendable {
    case regular
    case medium
    case semibold

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .regular:
            return "偏细"
        case .medium:
            return "适中"
        case .semibold:
            return "偏粗"
        }
    }

    public var fontWeight: Font.Weight {
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

public enum MenuBarLayoutDensity: String, CaseIterable, Identifiable, Sendable {
    case compact
    case normal

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .compact:
            return "紧凑"
        case .normal:
            return "正常"
        }
    }

    public var statusItemWidth: CGFloat {
        switch self {
        case .compact:
            return 42
        case .normal:
            return 44
        }
    }
}

public struct MenuBarDisplaySettings: Equatable, Sendable {
    public static let currentDisplayDefaultsVersion = 2
    public static let defaultContentMode = MenuBarContentMode.remainingWindows
    public static let defaultLayoutDensity = MenuBarLayoutDensity.compact
    public static let defaultItemSpacing = 2.0
    public static let defaultRowSpacing = -1.0
    public static let defaultNumberFontSize = 9.5
    public static let defaultNumberFontWeight = MenuBarNumberFontWeight.medium
    public static let defaultGoodColorHex = "#1AB85C"
    public static let defaultWarningColorHex = "#F5931A"
    public static let defaultDangerColorHex = "#F23838"
    public static let defaultShowsPrimaryWindow = true
    public static let defaultShowsSecondaryWindow = true
    public static let defaultShowsPercentSymbol = true
    public static let defaultShowsAdditionalLimits = false
    public static let defaultShowsMenuBarIcon = false
    public static let menuBarIconWidth: CGFloat = 15
    public static let menuBarIconTextSpacing: CGFloat = 2
    public static var menuBarIconStatusItemWidth: CGFloat {
        menuBarIconWidth + menuBarIconTextSpacing
    }
    public nonisolated(unsafe) static let sharedDefaults: UserDefaults = UserDefaults(
        suiteName: UsageSnapshotStore.defaultAppGroupIdentifier
    ) ?? .standard

    public let contentMode: MenuBarContentMode
    public let layoutDensity: MenuBarLayoutDensity
    public let itemSpacing: Double
    public let rowSpacing: Double
    public let numberFontSize: Double
    public let numberFontWeight: MenuBarNumberFontWeight
    public let goodColorHex: String
    public let warningColorHex: String
    public let dangerColorHex: String
    public let showsPrimaryWindow: Bool
    public let showsSecondaryWindow: Bool
    public let showsPercentSymbol: Bool
    public let showsAdditionalLimits: Bool
    public let showsMenuBarIcon: Bool

    public init(
        contentMode: MenuBarContentMode = Self.defaultContentMode,
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
        showsPercentSymbol: Bool = Self.defaultShowsPercentSymbol,
        showsAdditionalLimits: Bool = Self.defaultShowsAdditionalLimits,
        showsMenuBarIcon: Bool = Self.defaultShowsMenuBarIcon
    ) {
        self.contentMode = contentMode
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
        self.showsAdditionalLimits = showsAdditionalLimits
        self.showsMenuBarIcon = showsMenuBarIcon
    }

    public init(defaults: UserDefaults) {
        self.init(
            contentMode: MenuBarContentMode(
                rawValue: defaults.string(forKey: MenuBarPreferenceKeys.contentMode) ?? ""
            ) ?? Self.defaultContentMode,
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
                ?? Self.defaultShowsPercentSymbol,
            showsAdditionalLimits: defaults.object(forKey: MenuBarPreferenceKeys.showsAdditionalLimits) as? Bool
                ?? Self.defaultShowsAdditionalLimits,
            showsMenuBarIcon: defaults.object(forKey: MenuBarPreferenceKeys.showsMenuBarIcon) as? Bool
                ?? Self.defaultShowsMenuBarIcon
        )
    }

    /// 菜单栏占位只按内容真实需要增长；Pace 上下两行后复用剩余额度的紧凑宽度。
    public var statusItemWidth: CGFloat {
        layoutDensity.statusItemWidth + (showsMenuBarIcon ? Self.menuBarIconStatusItemWidth : 0)
    }

    public var statusLabelHeight: CGFloat {
        22
    }

    public var usesDefaultValues: Bool {
        self == MenuBarDisplaySettings()
    }

    public func colorHex(for tone: UsageRemainingTone) -> String {
        switch tone {
        case .unavailable:
            return Self.defaultGoodColorHex
        case .good:
            return goodColorHex
        case .warning:
            return warningColorHex
        case .danger:
            return dangerColorHex
        }
    }

    public func color(for tone: UsageRemainingTone) -> Color {
        switch tone {
        case .unavailable:
            return .secondary
        case .good, .warning, .danger:
            return Color(hexRGB: colorHex(for: tone))
        }
    }

    public static func migrateStandardDefaultsToSharedDefaults(
        standardDefaults: UserDefaults = .standard,
        sharedDefaults: UserDefaults = Self.sharedDefaults
    ) {
        for key in MenuBarPreferenceKeys.allKeys where sharedDefaults.object(forKey: key) == nil {
            if let value = standardDefaults.object(forKey: key) {
                sharedDefaults.set(value, forKey: key)
            }
        }
    }

    /// 将已经写入的旧默认值迁移到当前默认值，避免菜单栏和小组件继续读取旧版默认设置。
    public static func migrateLegacyDisplayDefaults(defaults: UserDefaults = Self.sharedDefaults) {
        guard defaults.integer(forKey: MenuBarPreferenceKeys.displayDefaultsVersion) < currentDisplayDefaultsVersion else {
            return
        }

        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.contentMode,
            legacyValue: MenuBarContentMode.paceComparison.rawValue,
            currentValue: defaultContentMode.rawValue
        )
        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.layoutDensity,
            legacyValue: MenuBarLayoutDensity.compact.rawValue,
            currentValue: defaultLayoutDensity.rawValue
        )
        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.itemSpacing,
            legacyValue: 1.0,
            currentValue: defaultItemSpacing
        )
        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.rowSpacing,
            legacyValue: -2.0,
            currentValue: defaultRowSpacing
        )
        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.numberFontSize,
            legacyValue: 9.0,
            currentValue: defaultNumberFontSize
        )
        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.numberFontWeight,
            legacyValue: MenuBarNumberFontWeight.medium.rawValue,
            currentValue: defaultNumberFontWeight.rawValue
        )
        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.showsMenuBarIcon,
            legacyValue: false,
            currentValue: defaultShowsMenuBarIcon
        )

        defaults.set(currentDisplayDefaultsVersion, forKey: MenuBarPreferenceKeys.displayDefaultsVersion)
        defaults.synchronize()
    }

    public static func notifyDidChange(defaults: UserDefaults = Self.sharedDefaults) {
        defaults.synchronize()
        NotificationCenter.default.post(name: .menuBarDisplaySettingsDidChange, object: defaults)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    }

    public static func normalizedColorHex(_ value: String, fallback: String) -> String {
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

    /// 只替换仍等于旧默认的字符串设置，保留用户主动改过的值。
    private static func replaceStoredValue(
        defaults: UserDefaults,
        key: String,
        legacyValue: String,
        currentValue: String
    ) {
        let storedValue = defaults.string(forKey: key)
        if storedValue == nil || storedValue == legacyValue {
            defaults.set(currentValue, forKey: key)
        }
    }

    /// 只替换仍等于旧默认的数值设置，保留用户主动改过的值。
    private static func replaceStoredValue(
        defaults: UserDefaults,
        key: String,
        legacyValue: Double,
        currentValue: Double
    ) {
        let storedValue = defaults.object(forKey: key) as? Double
        if storedValue == nil || storedValue == legacyValue {
            defaults.set(currentValue, forKey: key)
        }
    }

    /// 只替换仍等于旧默认的布尔设置，保留用户主动改过的值。
    private static func replaceStoredValue(
        defaults: UserDefaults,
        key: String,
        legacyValue: Bool,
        currentValue: Bool
    ) {
        let storedValue = defaults.object(forKey: key) as? Bool
        if storedValue == nil || storedValue == legacyValue {
            defaults.set(currentValue, forKey: key)
        }
    }
}

public extension Notification.Name {
    static let menuBarDisplaySettingsDidChange = Notification.Name("CodexUsage.menuBarDisplaySettingsDidChange")
}

public struct CodexUsageWidgetDisplay: Equatable, Sendable {
    public struct Line: Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let value: String
        public let resetText: String
        public let progressValue: Double
        public let tone: UsageRemainingTone
    }

    public let lines: [Line]

    public init(
        snapshot: UsageSnapshot,
        settings: MenuBarDisplaySettings,
        formatter: UsageFormatter = UsageFormatter(),
        now: Date = Date()
    ) {
        var lines: [Line] = []
        if settings.showsPrimaryWindow {
            lines.append(Self.line(
                id: "primary",
                title: "5 小时",
                window: snapshot.rateLimits.primary,
                resetText: formatter.resetRemainingText(window: snapshot.rateLimits.primary, now: now),
                settings: settings
            ))
        }
        if settings.showsSecondaryWindow {
            lines.append(Self.line(
                id: "secondary",
                title: "7 天",
                window: snapshot.rateLimits.secondary,
                resetText: formatter.resetRemainingText(window: snapshot.rateLimits.secondary, now: now),
                settings: settings
            ))
        }
        if lines.isEmpty {
            lines.append(Self.line(
                id: "primary",
                title: "5 小时",
                window: snapshot.rateLimits.primary,
                resetText: formatter.resetRemainingText(window: snapshot.rateLimits.primary, now: now),
                settings: settings
            ))
        }
        self.lines = lines
    }

    private static func line(
        id: String,
        title: String,
        window: RateLimitWindow?,
        resetText: String,
        settings: MenuBarDisplaySettings
    ) -> Line {
        let remainingPercent = window?.remainingPercent
        return Line(
            id: id,
            title: title,
            value: Self.value(for: remainingPercent, settings: settings),
            resetText: resetText,
            progressValue: Double(remainingPercent ?? 0),
            tone: UsageRemainingTone(remainingPercent: remainingPercent)
        )
    }

    private static func value(for remainingPercent: Int?, settings: MenuBarDisplaySettings) -> String {
        guard let remainingPercent else {
            return "--"
        }
        if settings.showsPercentSymbol {
            return "\(remainingPercent)%"
        }
        return "\(remainingPercent)"
    }
}

public extension Color {
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
}

public extension UsageRemainingTone {
    func statusBarColor(settings: MenuBarDisplaySettings) -> Color {
        settings.color(for: self)
    }
}
