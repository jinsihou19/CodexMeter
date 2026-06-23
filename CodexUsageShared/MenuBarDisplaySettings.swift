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
    public static let showsHookActivityLight = "menuBar.showsHookActivityLight"
    public static let hookActivityIndicatorStyle = "menuBar.hookActivityIndicatorStyle"
    public static let weeklyProgressWorkDays = "menuBar.weeklyProgressWorkDays"

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
        showsMenuBarIcon,
        showsHookActivityLight,
        hookActivityIndicatorStyle,
        weeklyProgressWorkDays
    ]
}

public enum AppBehaviorPreferenceKeys {
    public static let opensSettingsAtLaunch = "app.opensSettingsAtLaunch"
    public static let refreshCadence = "usage.refreshCadence"

    public static let allKeys = [
        opensSettingsAtLaunch,
        refreshCadence
    ]
}

public enum SurfaceAppearancePreferenceKeys {
    public static let appearanceMode = "surface.appearanceMode"
    public static let cardOpacity = "surface.cardOpacity"

    public static let allKeys = [
        appearanceMode,
        cardOpacity
    ]
}

public enum WidgetDisplayPreferenceKeys {
    public static let contentMode = "widget.contentMode"
    public static let appearanceMode = "widget.appearanceMode"
    public static let cardOpacity = "widget.cardOpacity"
    public static let showsResetTime = "widget.showsResetTime"
    public static let showsPaceComparison = "widget.showsPaceComparison"
    public static let showsLastSync = "widget.showsLastSync"
    public static let showsPlanLabel = "widget.showsPlanLabel"

    public static let allKeys = [
        contentMode,
        appearanceMode,
        cardOpacity,
        showsResetTime,
        showsPaceComparison,
        showsLastSync,
        showsPlanLabel
    ]
}

public enum PopoverPreferenceKeys {
    public static let showsPaceComparison = "popover.showsPaceComparison"
    public static let showsProfileOverview = "popover.showsProfileOverview"
    public static let showsTokenActivity = "popover.showsTokenActivity"
    public static let showsActivityInsights = "popover.showsActivityInsights"
    public static let showsTopInvocations = "popover.showsTopInvocations"
    public static let showsSyncDetails = "popover.showsSyncDetails"
    public static let showsAdditionalLimits = "popover.showsAdditionalLimits"
    public static let resetTimeDisplayStyle = "popover.resetTimeDisplayStyle"

    public static let allKeys = [
        showsPaceComparison,
        showsProfileOverview,
        showsTokenActivity,
        showsActivityInsights,
        showsTopInvocations,
        showsSyncDetails,
        showsAdditionalLimits,
        resetTimeDisplayStyle
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

/// 管理后台同步频率；nil 表示只允许用户手动刷新，避免隐式网络请求。
public enum UsageRefreshCadence: String, CaseIterable, Identifiable, Sendable {
    case manual
    case seconds30
    case minute1
    case minutes5

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .manual:
            return "手动"
        case .seconds30:
            return "30 秒"
        case .minute1:
            return "1 分钟"
        case .minutes5:
            return "5 分钟"
        }
    }

    public var intervalSeconds: TimeInterval? {
        switch self {
        case .manual:
            return nil
        case .seconds30:
            return 30
        case .minute1:
            return 60
        case .minutes5:
            return 300
        }
    }

    public var intervalNanoseconds: UInt64? {
        intervalSeconds.map { UInt64($0 * 1_000_000_000) }
    }
}

/// 控制小组件从共享快照中挑选哪些窗口和辅助文字。
public enum WidgetContentMode: String, CaseIterable, Identifiable, Sendable {
    case followsMenuBar
    case bothWindows
    case primaryOnly
    case secondaryOnly

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .followsMenuBar:
            return "跟随菜单栏"
        case .bothWindows:
            return "5 小时 + 7 天"
        case .primaryOnly:
            return "仅 5 小时"
        case .secondaryOnly:
            return "仅 7 天"
        }
    }
}

/// 控制菜单栏、弹窗和桌面小组件使用系统外观、强制浅色或强制深色。
public enum SurfaceAppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case light
    case dark

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .automatic:
            return "自动"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .automatic:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

public typealias WidgetAppearanceMode = SurfaceAppearanceMode

/// 控制弹窗和小组件里的重置时间文案；倒计时适合扫读，具体时间适合规划。
public enum ResetTimeDisplayStyle: String, CaseIterable, Identifiable, Sendable {
    case countdown
    case absolute

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .countdown:
            return "倒计时"
        case .absolute:
            return "具体时间"
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

/// 保存所有可见浮层的外观设置；小组件旧 key 会作为兼容回退，随后由设置页归一化到新 key。
public struct SurfaceAppearanceSettings: Equatable, Sendable {
    public static let defaultAppearanceMode = SurfaceAppearanceMode.automatic
    public static let defaultCardOpacity = 0.78
    public static let cardOpacityRange = 0.2...0.9

    public let appearanceMode: SurfaceAppearanceMode
    public let cardOpacity: Double

    public init(
        appearanceMode: SurfaceAppearanceMode = Self.defaultAppearanceMode,
        cardOpacity: Double = Self.defaultCardOpacity
    ) {
        self.appearanceMode = appearanceMode
        self.cardOpacity = Self.normalizedCardOpacity(cardOpacity)
    }

    public init(defaults: UserDefaults) {
        let rawAppearance = defaults.string(forKey: SurfaceAppearancePreferenceKeys.appearanceMode)
            ?? defaults.string(forKey: WidgetDisplayPreferenceKeys.appearanceMode)
            ?? ""
        let opacity = defaults.object(forKey: SurfaceAppearancePreferenceKeys.cardOpacity) as? Double
            ?? defaults.object(forKey: WidgetDisplayPreferenceKeys.cardOpacity) as? Double
            ?? Self.defaultCardOpacity
        self.init(
            appearanceMode: SurfaceAppearanceMode(rawValue: rawAppearance) ?? Self.defaultAppearanceMode,
            cardOpacity: opacity
        )
    }

    public var usesDefaultValues: Bool {
        self == SurfaceAppearanceSettings()
    }

    /// 将卡片不透明度限制在可读范围内，避免完全透明或完全不透明破坏桌面层次。
    public static func normalizedCardOpacity(_ value: Double) -> Double {
        min(max(value, cardOpacityRange.lowerBound), cardOpacityRange.upperBound)
    }

    /// 通知菜单栏、弹窗和小组件重新读取外观设置。
    public static func notifyDidChange(defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults) {
        defaults.synchronize()
        NotificationCenter.default.post(name: .surfaceAppearanceSettingsDidChange, object: defaults)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    }
}

/// 保存 app 级行为设置，范围限于启动和后台刷新，不影响小组件快照格式。
public struct AppBehaviorSettings: Equatable, Sendable {
    public static let defaultOpensSettingsAtLaunch = false
    public static let defaultRefreshCadence = UsageRefreshCadence.seconds30

    public let opensSettingsAtLaunch: Bool
    public let refreshCadence: UsageRefreshCadence

    public init(
        opensSettingsAtLaunch: Bool = Self.defaultOpensSettingsAtLaunch,
        refreshCadence: UsageRefreshCadence = Self.defaultRefreshCadence
    ) {
        self.opensSettingsAtLaunch = opensSettingsAtLaunch
        self.refreshCadence = refreshCadence
    }

    public init(defaults: UserDefaults) {
        self.init(
            opensSettingsAtLaunch: defaults.object(forKey: AppBehaviorPreferenceKeys.opensSettingsAtLaunch) as? Bool
                ?? Self.defaultOpensSettingsAtLaunch,
            refreshCadence: UsageRefreshCadence(
                rawValue: defaults.string(forKey: AppBehaviorPreferenceKeys.refreshCadence) ?? ""
            ) ?? Self.defaultRefreshCadence
        )
    }

    public var usesDefaultValues: Bool {
        self == AppBehaviorSettings()
    }

    /// 通知主 app 重新套用启动与刷新相关设置，避免设置页和后台任务脱节。
    public static func notifyDidChange(defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults) {
        defaults.synchronize()
        NotificationCenter.default.post(name: .appBehaviorSettingsDidChange, object: defaults)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    }
}

/// 保存桌面小组件的全局显示偏好，供 app 设置页和 WidgetKit 扩展共同读取。
public struct WidgetDisplaySettings: Equatable, Sendable {
    public static let defaultContentMode = WidgetContentMode.followsMenuBar
    public static let defaultAppearanceMode = SurfaceAppearanceSettings.defaultAppearanceMode
    public static let defaultCardOpacity = SurfaceAppearanceSettings.defaultCardOpacity
    public static let cardOpacityRange = SurfaceAppearanceSettings.cardOpacityRange
    public static let defaultShowsResetTime = true
    public static let defaultShowsPaceComparison = true
    public static let defaultShowsLastSync = true
    public static let defaultShowsPlanLabel = true

    public let contentMode: WidgetContentMode
    public let appearanceMode: SurfaceAppearanceMode
    public let cardOpacity: Double
    public let showsResetTime: Bool
    public let showsPaceComparison: Bool
    public let showsLastSync: Bool
    public let showsPlanLabel: Bool

    public init(
        contentMode: WidgetContentMode = Self.defaultContentMode,
        appearanceMode: SurfaceAppearanceMode = Self.defaultAppearanceMode,
        cardOpacity: Double = Self.defaultCardOpacity,
        showsResetTime: Bool = Self.defaultShowsResetTime,
        showsPaceComparison: Bool = Self.defaultShowsPaceComparison,
        showsLastSync: Bool = Self.defaultShowsLastSync,
        showsPlanLabel: Bool = Self.defaultShowsPlanLabel
    ) {
        self.contentMode = contentMode
        self.appearanceMode = appearanceMode
        self.cardOpacity = SurfaceAppearanceSettings.normalizedCardOpacity(cardOpacity)
        self.showsResetTime = showsResetTime
        self.showsPaceComparison = showsPaceComparison
        self.showsLastSync = showsLastSync
        self.showsPlanLabel = showsPlanLabel
    }

    public init(defaults: UserDefaults) {
        self.init(
            contentMode: WidgetContentMode(
                rawValue: defaults.string(forKey: WidgetDisplayPreferenceKeys.contentMode) ?? ""
            ) ?? Self.defaultContentMode,
            appearanceMode: SurfaceAppearanceMode(
                rawValue: defaults.string(forKey: WidgetDisplayPreferenceKeys.appearanceMode) ?? ""
            ) ?? Self.defaultAppearanceMode,
            cardOpacity: defaults.object(forKey: WidgetDisplayPreferenceKeys.cardOpacity) as? Double
                ?? Self.defaultCardOpacity,
            showsResetTime: defaults.object(forKey: WidgetDisplayPreferenceKeys.showsResetTime) as? Bool
                ?? Self.defaultShowsResetTime,
            showsPaceComparison: defaults.object(forKey: WidgetDisplayPreferenceKeys.showsPaceComparison) as? Bool
                ?? Self.defaultShowsPaceComparison,
            showsLastSync: defaults.object(forKey: WidgetDisplayPreferenceKeys.showsLastSync) as? Bool
                ?? Self.defaultShowsLastSync,
            showsPlanLabel: defaults.object(forKey: WidgetDisplayPreferenceKeys.showsPlanLabel) as? Bool
                ?? Self.defaultShowsPlanLabel
        )
    }

    public var usesDefaultValues: Bool {
        self == WidgetDisplaySettings()
    }

    /// 将卡片不透明度限制在可读范围内，避免完全透明或完全不透明破坏桌面小组件层次。
    public static func normalizedCardOpacity(_ value: Double) -> Double {
        SurfaceAppearanceSettings.normalizedCardOpacity(value)
    }

    /// 通知 WidgetKit 相关界面重新读取全局小组件偏好。
    public static func notifyDidChange(defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults) {
        defaults.synchronize()
        NotificationCenter.default.post(name: .widgetDisplaySettingsDidChange, object: defaults)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    }
}

/// 保存菜单栏弹窗模块偏好；默认等价于旧版本弹窗能看到的内容。
public struct PopoverDisplaySettings: Equatable, Sendable {
    public static let defaultShowsPaceComparison = true
    public static let defaultShowsProfileOverview = true
    public static let defaultShowsTokenActivity = true
    public static let defaultShowsActivityInsights = true
    public static let defaultShowsTopInvocations = true
    public static let defaultShowsSyncDetails = true
    public static let defaultShowsAdditionalLimits = false
    public static let defaultResetTimeDisplayStyle = ResetTimeDisplayStyle.countdown

    public let showsPaceComparison: Bool
    public let showsProfileOverview: Bool
    public let showsTokenActivity: Bool
    public let showsActivityInsights: Bool
    public let showsTopInvocations: Bool
    public let showsSyncDetails: Bool
    public let showsAdditionalLimits: Bool
    public let resetTimeDisplayStyle: ResetTimeDisplayStyle

    public init(
        showsPaceComparison: Bool = Self.defaultShowsPaceComparison,
        showsProfileOverview: Bool = Self.defaultShowsProfileOverview,
        showsTokenActivity: Bool = Self.defaultShowsTokenActivity,
        showsActivityInsights: Bool = Self.defaultShowsActivityInsights,
        showsTopInvocations: Bool = Self.defaultShowsTopInvocations,
        showsSyncDetails: Bool = Self.defaultShowsSyncDetails,
        showsAdditionalLimits: Bool = Self.defaultShowsAdditionalLimits,
        resetTimeDisplayStyle: ResetTimeDisplayStyle = Self.defaultResetTimeDisplayStyle
    ) {
        self.showsPaceComparison = showsPaceComparison
        self.showsProfileOverview = showsProfileOverview
        self.showsTokenActivity = showsTokenActivity
        self.showsActivityInsights = showsActivityInsights
        self.showsTopInvocations = showsTopInvocations
        self.showsSyncDetails = showsSyncDetails
        self.showsAdditionalLimits = showsAdditionalLimits
        self.resetTimeDisplayStyle = resetTimeDisplayStyle
    }

    public init(defaults: UserDefaults) {
        let additionalLimits = defaults.object(forKey: PopoverPreferenceKeys.showsAdditionalLimits) as? Bool
            ?? defaults.object(forKey: MenuBarPreferenceKeys.showsAdditionalLimits) as? Bool
            ?? Self.defaultShowsAdditionalLimits
        self.init(
            showsPaceComparison: defaults.object(forKey: PopoverPreferenceKeys.showsPaceComparison) as? Bool
                ?? Self.defaultShowsPaceComparison,
            showsProfileOverview: defaults.object(forKey: PopoverPreferenceKeys.showsProfileOverview) as? Bool
                ?? Self.defaultShowsProfileOverview,
            showsTokenActivity: defaults.object(forKey: PopoverPreferenceKeys.showsTokenActivity) as? Bool
                ?? Self.defaultShowsTokenActivity,
            showsActivityInsights: defaults.object(forKey: PopoverPreferenceKeys.showsActivityInsights) as? Bool
                ?? Self.defaultShowsActivityInsights,
            showsTopInvocations: defaults.object(forKey: PopoverPreferenceKeys.showsTopInvocations) as? Bool
                ?? Self.defaultShowsTopInvocations,
            showsSyncDetails: defaults.object(forKey: PopoverPreferenceKeys.showsSyncDetails) as? Bool
                ?? Self.defaultShowsSyncDetails,
            showsAdditionalLimits: additionalLimits,
            resetTimeDisplayStyle: ResetTimeDisplayStyle(
                rawValue: defaults.string(forKey: PopoverPreferenceKeys.resetTimeDisplayStyle) ?? ""
            ) ?? Self.defaultResetTimeDisplayStyle
        )
    }

    public var usesDefaultValues: Bool {
        self == PopoverDisplaySettings()
    }

    /// 通知菜单栏弹窗重新构建内容，保证模块开关能即时反映在已打开的弹窗中。
    public static func notifyDidChange(defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults) {
        defaults.synchronize()
        NotificationCenter.default.post(name: .popoverDisplaySettingsDidChange, object: defaults)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
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

/// 控制菜单栏 hook 活动指示的视觉语言；旧 rawValue 保留用于兼容已保存设置，实际显示改为系统 SF Symbol。
public enum HookActivityIndicatorStyle: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case variableDots
    case fanHead
    case signature

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .automatic:
            return "自动"
        case .variableDots:
            return "竖向省略号"
        case .fanHead:
            return "target"
        case .signature:
            return "aqi.medium"
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
    public static let defaultShowsHookActivityLight = true
    public static let defaultHookActivityIndicatorStyle = HookActivityIndicatorStyle.automatic
    public static let defaultWeeklyProgressWorkDays = 5
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
    public let showsHookActivityLight: Bool
    public let hookActivityIndicatorStyle: HookActivityIndicatorStyle
    public let weeklyProgressWorkDays: Int

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
        showsMenuBarIcon: Bool = Self.defaultShowsMenuBarIcon,
        showsHookActivityLight: Bool = Self.defaultShowsHookActivityLight,
        hookActivityIndicatorStyle: HookActivityIndicatorStyle = Self.defaultHookActivityIndicatorStyle,
        weeklyProgressWorkDays: Int = Self.defaultWeeklyProgressWorkDays
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
        self.showsHookActivityLight = showsHookActivityLight
        self.hookActivityIndicatorStyle = hookActivityIndicatorStyle
        self.weeklyProgressWorkDays = Swift.max(2, Swift.min(7, weeklyProgressWorkDays))
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
                ?? Self.defaultShowsMenuBarIcon,
            showsHookActivityLight: defaults.object(forKey: MenuBarPreferenceKeys.showsHookActivityLight) as? Bool
                ?? Self.defaultShowsHookActivityLight,
            hookActivityIndicatorStyle: HookActivityIndicatorStyle(
                rawValue: defaults.string(forKey: MenuBarPreferenceKeys.hookActivityIndicatorStyle) ?? ""
            ) ?? Self.defaultHookActivityIndicatorStyle,
            weeklyProgressWorkDays: defaults.object(forKey: MenuBarPreferenceKeys.weeklyProgressWorkDays) as? Int
                ?? Self.defaultWeeklyProgressWorkDays
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
        if defaults.object(forKey: MenuBarPreferenceKeys.weeklyProgressWorkDays) == nil {
            defaults.set(defaultWeeklyProgressWorkDays, forKey: MenuBarPreferenceKeys.weeklyProgressWorkDays)
        }

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
    static let appBehaviorSettingsDidChange = Notification.Name("CodexUsage.appBehaviorSettingsDidChange")
    static let surfaceAppearanceSettingsDidChange = Notification.Name("CodexUsage.surfaceAppearanceSettingsDidChange")
    static let widgetDisplaySettingsDidChange = Notification.Name("CodexUsage.widgetDisplaySettingsDidChange")
    static let popoverDisplaySettingsDidChange = Notification.Name("CodexUsage.popoverDisplaySettingsDidChange")
}

/// 统一封装预期消耗速度的展示模型，供菜单栏、弹窗和小组件共享同一套 Pace 判断。
public struct UsagePaceDisplay: Equatable, Sendable {
    public let remainingPercent: Int
    public let deltaPercent: Int
    public let expectedUsedPercent: Int
    public let etaSeconds: TimeInterval?
    public let willLastToReset: Bool

    /// 从完整快照里选择适合菜单栏紧凑展示的百分比窗口和 Pace 窗口。
    public init?(rateLimits: RateLimitSnapshot?, now: Date = Date()) {
        let settings = MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        self.init(
            percentWindow: rateLimits?.paceComparisonPercentWindow,
            paceWindow: rateLimits?.paceComparisonPaceWindow,
            now: now,
            weeklyProgressWorkDays: settings.weeklyProgressWorkDays
        )
    }

    /// 用指定窗口计算 Pace；窗口进度不足时返回 nil，避免刚重置后的误导性估算。
    public init?(
        percentWindow: RateLimitWindow?,
        paceWindow: RateLimitWindow?,
        now: Date = Date(),
        weeklyProgressWorkDays: Int? = nil
    ) {
        guard let percentWindow,
              let pace = paceWindow?.usagePace(now: now, weeklyProgressWorkDays: weeklyProgressWorkDays),
              pace.isDisplayable()
        else {
            return nil
        }
        self.remainingPercent = percentWindow.remainingPercent
        self.deltaPercent = pace.roundedDeltaPercent
        self.expectedUsedPercent = pace.roundedExpectedUsedPercent
        self.etaSeconds = pace.etaSeconds
        self.willLastToReset = pace.willLastToReset
    }

    public var valueText: String {
        "\(remainingPercent)% · \(deltaText)"
    }

    public var compactValueText: String {
        "\(remainingPercent)%·\(deltaText)"
    }

    public var detailText: String {
        let leftText: String
        if deltaPercent == 0 {
            leftText = "按正常节奏"
        } else if deltaPercent > 0 {
            leftText = "用得偏快 \(deltaPercent)%"
        } else {
            leftText = "有余量 \(abs(deltaPercent))%"
        }

        guard let rightText else {
            return leftText
        }
        return "\(leftText) · \(rightText)"
    }

    public var widgetStatusText: String {
        if abs(deltaPercent) <= 2 {
            return "节奏正常"
        }
        if deltaPercent > 0 {
            return "超额 \(deltaPercent)%"
        }
        return "有余量 \(abs(deltaPercent))%"
    }

    public var widgetProjectionText: String? {
        if willLastToReset {
            return "持续到重置"
        }
        guard let etaSeconds else {
            return nil
        }
        let duration = Self.durationText(seconds: etaSeconds)
        if duration == "现在" {
            return "额度已耗尽"
        }
        return "预计 \(duration)后耗尽"
    }

    private var rightText: String? {
        if willLastToReset {
            return "可持续到重置"
        }
        guard let etaSeconds else {
            return nil
        }
        let duration = Self.durationText(seconds: etaSeconds)
        if duration == "现在" {
            return "额度已耗尽"
        }
        return "预计 \(duration)后用完"
    }

    public var deltaText: String {
        "\(deltaPercent >= 0 ? "+" : "")\(deltaPercent)%"
    }

    public var tone: UsageRemainingTone {
        if deltaPercent <= 2 {
            return .good
        }
        if deltaPercent <= 12 {
            return .warning
        }
        return .danger
    }

    /// 将 ETA 秒数压缩成适合菜单栏和小组件扫读的中文短文本。
    private static func durationText(seconds: TimeInterval) -> String {
        guard seconds > 60 else {
            return "现在"
        }

        let totalMinutes = max(1, Int((seconds / 60).rounded()))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0, hours > 0 {
            return "\(days)天\(hours)小时"
        }
        if days > 0 {
            return "\(days)天"
        }
        if hours > 0, minutes > 0 {
            return "\(hours)小时\(minutes)分"
        }
        if hours > 0 {
            return "\(hours)小时"
        }
        return "\(minutes)分"
    }
}

/// 描述单个额度窗口的 Pace 展示，保证弹窗和小组件按同一阈值决定是否展示速度行。
public struct UsageWindowPaceDisplay: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let display: UsagePaceDisplay

    /// 构造单个额度窗口的 Pace 展示；窗口进度不足 3% 时不展示，避免刚重置后的偏差误导用户。
    public init?(
        id: String,
        title: String,
        window: RateLimitWindow?,
        now: Date = Date(),
        weeklyProgressWorkDays: Int? = nil
    ) {
        guard let display = UsagePaceDisplay(
            percentWindow: window,
            paceWindow: window,
            now: now,
            weeklyProgressWorkDays: weeklyProgressWorkDays
        ) else {
            return nil
        }
        self.id = id
        self.title = title
        self.display = display
    }

    /// 收集“用量速度”区域可展示的窗口 Pace，当前包含 5 小时和 7 天两个窗口。
    public static func displays(
        rateLimits: RateLimitSnapshot,
        now: Date = Date(),
        weeklyProgressWorkDays: Int? = nil
    ) -> [UsageWindowPaceDisplay] {
        [
            UsageWindowPaceDisplay(
                id: "primary",
                title: "5 小时",
                window: rateLimits.primary,
                now: now,
                weeklyProgressWorkDays: weeklyProgressWorkDays
            ),
            UsageWindowPaceDisplay(
                id: "secondary",
                title: "7 天",
                window: rateLimits.secondary,
                now: now,
                weeklyProgressWorkDays: weeklyProgressWorkDays
            )
        ].compactMap { $0 }
    }
}

/// 生成标准周窗口的工作日分界百分比，供 7 天用量条和设置预览复用。
public func weeklyWorkdayMarkerPercents(workDays: Int?, windowDurationMins: Int?) -> [Double] {
    guard windowDurationMins == 10_080, let workDays, workDays >= 2, workDays <= 7 else {
        return []
    }
    return (1..<workDays).map { Double($0) * 100.0 / Double(workDays) }
}

private extension RateLimitSnapshot {
    var paceComparisonPercentWindow: RateLimitWindow? {
        primary ?? secondary
    }

    var paceComparisonPaceWindow: RateLimitWindow? {
        secondary ?? primary
    }
}

public struct CodexUsageWidgetDisplay: Equatable, Sendable {
    public struct Line: Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let value: String
        public let resetText: String
        public let paceStatusText: String
        public let paceProjectionText: String
        public let paceTone: UsageRemainingTone
        public let progressValue: Double
        public let tone: UsageRemainingTone
    }

    public let lines: [Line]

    public init(
        snapshot: UsageSnapshot,
        settings: MenuBarDisplaySettings,
        widgetSettings: WidgetDisplaySettings = WidgetDisplaySettings(),
        formatter: UsageFormatter = UsageFormatter(),
        now: Date = Date()
    ) {
        var lines: [Line] = []
        let windows = Self.visibleWindows(menuBarSettings: settings, widgetSettings: widgetSettings)
        if windows.showsPrimary {
            lines.append(Self.line(
                id: "primary",
                title: "5 小时",
                window: snapshot.rateLimits.primary,
                resetText: widgetSettings.showsResetTime
                    ? formatter.resetRemainingText(window: snapshot.rateLimits.primary, now: now)
                    : "",
                paceDisplay: widgetSettings.showsPaceComparison
                    ? UsageWindowPaceDisplay(
                        id: "primary",
                        title: "5 小时",
                        window: snapshot.rateLimits.primary,
                        now: now,
                        weeklyProgressWorkDays: settings.weeklyProgressWorkDays
                    )?.display
                    : nil,
                settings: settings
            ))
        }
        if windows.showsSecondary {
            lines.append(Self.line(
                id: "secondary",
                title: "7 天",
                window: snapshot.rateLimits.secondary,
                resetText: widgetSettings.showsResetTime
                    ? formatter.resetRemainingText(window: snapshot.rateLimits.secondary, now: now)
                    : "",
                paceDisplay: widgetSettings.showsPaceComparison
                    ? UsageWindowPaceDisplay(
                        id: "secondary",
                        title: "7 天",
                        window: snapshot.rateLimits.secondary,
                        now: now,
                        weeklyProgressWorkDays: settings.weeklyProgressWorkDays
                    )?.display
                    : nil,
                settings: settings
            ))
        }
        if lines.isEmpty {
            lines.append(Self.line(
                id: "primary",
                title: "5 小时",
                window: snapshot.rateLimits.primary,
                resetText: widgetSettings.showsResetTime
                    ? formatter.resetRemainingText(window: snapshot.rateLimits.primary, now: now)
                    : "",
                paceDisplay: widgetSettings.showsPaceComparison
                    ? UsageWindowPaceDisplay(
                        id: "primary",
                        title: "5 小时",
                        window: snapshot.rateLimits.primary,
                        now: now,
                        weeklyProgressWorkDays: settings.weeklyProgressWorkDays
                    )?.display
                    : nil,
                settings: settings
            ))
        }
        self.lines = lines
    }

    /// 根据小组件专属配置决定可见窗口；跟随菜单栏时复用旧行为。
    private static func visibleWindows(
        menuBarSettings: MenuBarDisplaySettings,
        widgetSettings: WidgetDisplaySettings
    ) -> (showsPrimary: Bool, showsSecondary: Bool) {
        switch widgetSettings.contentMode {
        case .followsMenuBar:
            return (menuBarSettings.showsPrimaryWindow, menuBarSettings.showsSecondaryWindow)
        case .bothWindows:
            return (true, true)
        case .primaryOnly:
            return (true, false)
        case .secondaryOnly:
            return (false, true)
        }
    }

    private static func line(
        id: String,
        title: String,
        window: RateLimitWindow?,
        resetText: String,
        paceDisplay: UsagePaceDisplay?,
        settings: MenuBarDisplaySettings
    ) -> Line {
        let remainingPercent = window?.remainingPercent
        return Line(
            id: id,
            title: title,
            value: Self.value(for: remainingPercent, settings: settings),
            resetText: resetText,
            paceStatusText: paceDisplay?.widgetStatusText ?? "",
            paceProjectionText: paceDisplay?.widgetProjectionText ?? "",
            paceTone: paceDisplay?.tone ?? .unavailable,
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
