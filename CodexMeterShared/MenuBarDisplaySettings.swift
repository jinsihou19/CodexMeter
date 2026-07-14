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

public enum AppLanguagePreferenceKeys {
    public static let selectedLanguage = "app.selectedLanguage"
}

/// 应用语言沿用系统语言代码；空值表示不覆盖 macOS 的语言选择。
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = ""
    case chineseSimplified = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public var locale: Locale {
        rawValue.isEmpty ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    public var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .chineseSimplified:
            return "简体中文"
        case .english:
            return "English"
        }
    }

    /// 写入下一次进程启动使用的语言覆盖；跟随系统时删除旧覆盖。
    public func apply(to defaults: UserDefaults = .standard) {
        if rawValue.isEmpty {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

/// 为现有硬编码中文提供进程内英文映射；未翻译项安全回退到中文原文。
public enum AppLocalization {
    /// 判断当前偏好是否使用英文，供带数字插值的动态文案选择格式。
    public static func usesEnglish(
        language: AppLanguage? = nil,
        defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults
    ) -> Bool {
        let selected = language ?? AppLanguage(
            rawValue: defaults.string(forKey: AppLanguagePreferenceKeys.selectedLanguage) ?? ""
        ) ?? .system
        return selected == .english
            || selected == .system && Locale.preferredLanguages.first?.hasPrefix("en") == true
    }

    /// 按用户选择或系统首选语言返回文案；显式语言和偏好容器用于测试与预览。
    public static func string(
        _ key: String,
        language: AppLanguage? = nil,
        defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults
    ) -> String {
        usesEnglish(language: language, defaults: defaults) ? english[key] ?? key : key
    }

    private static let english: [String: String] = [
        "通用": "General",
        "通知": "Notifications",
        "菜单栏": "Menu Bar",
        "下拉面板": "Popover",
        "小组件": "Widget",
        "关于": "About",
        "CodexMeter 设置": "CodexMeter Settings",
        "版本": "Version",
        "系统": "System",
        "语言": "Language",
        "更改后立即应用；部分系统文案在重新启动后生效。": "Applies immediately; some system text updates after restarting the app.",
        "登录时启动": "Launch at Login",
        "登录 macOS 后自动启动菜单栏用量组件。": "Launch the menu bar usage app automatically after signing in to macOS.",
        "刷新频率": "Refresh Frequency",
        "手动模式只在点击下拉面板里的刷新按钮时请求接口。": "Manual mode only requests usage when you click Refresh in the popover.",
        "界面外观": "Appearance",
        "自动会跟随系统；浅色和深色会强制所有浮层使用对应配色。": "Automatic follows the system; Light and Dark override all surfaces.",
        "外观": "Appearance",
        "状态颜色": "Status Colors",
        "选择三档余量状态的配色方案。": "Choose colors for the three remaining-quota states.",
        "自定义": "Custom",
        "更多选项": "More Options",
        "启动时打开设置": "Open Settings at Launch",
        "应用启动后自动显示设置窗口；关闭后仍可从菜单栏进入。": "Show Settings when the app launches; it remains available from the menu bar.",
        "卡片不透明度": "Card Opacity",
        "统一影响菜单栏下拉面板和小组件的卡片背景。": "Controls card backgrounds in the popover and widget.",
        "充足": "Healthy",
        "偏低": "Low",
        "紧张": "Critical",
        "用量提醒": "Usage Alerts",
        "额度耗尽提醒": "Quota Depleted",
        "5 小时或 7 天窗口剩余降至 0% 时发送系统通知。": "Notify when the 5-hour or 7-day window reaches 0% remaining.",
        "低额度提醒": "Low Quota",
        "剩余额度首次降到设定阈值时发送一次系统通知。": "Notify once when remaining quota first crosses the threshold.",
        "提醒阈值": "Alert Threshold",
        "额度恢复到阈值以上后，下一次下降会再次提醒。": "After quota recovers above the threshold, the next drop can alert again.",
        "庆祝": "Celebrations",
        "重置时播放彩带": "Confetti on Reset",
        "额度重置时播放全屏彩带。": "Play full-screen confetti when quota resets.",
        "关闭": "Off",
        "5 小时重置": "5-Hour Resets",
        "7 天重置": "7-Day Resets",
        "两者": "Both",
        "播放彩带": "Play Confetti",
        "临时入口：立即预览一次全屏彩带。": "Temporary: preview full-screen confetti now.",
        "预览": "Preview",
        "系统浅色菜单栏": "System Light Menu Bar",
        "深色或高对比背景": "Dark or High-Contrast Background",
        "桌面壁纸透出的半透明状态": "Translucent Desktop Background",
        "半透明": "Translucent",
        "显示内容": "Content",
        "菜单栏内容": "Menu Bar Content",
        "选择显示剩余额度或相对预期的用量节奏。": "Show remaining quota or usage pace against expectations.",
        "工作日刻度线": "Workday Scale",
        "用于每周用量条刻度和节奏计算。": "Used for weekly scale marks and pace calculations.",
        "显示 5 小时窗口": "Show 5-Hour Window",
        "在菜单栏显示短窗口剩余额度；至少会保留一个窗口。": "Show the short-window quota; at least one window remains visible.",
        "显示 7 天窗口": "Show 7-Day Window",
        "在菜单栏显示周窗口剩余额度；至少会保留一个窗口。": "Show the weekly quota; at least one window remains visible.",
        "显示 Codex 图标": "Show Codex Icon",
        "在数字左侧显示 Codex 图标，便于和其他菜单栏项目区分。": "Show the Codex icon before values for easier identification.",
        "显示活动指示": "Show Activity Indicator",
        "Codex 运行、思考、需确认或刚完成时显示状态符号；空闲时自动隐藏。": "Show a status symbol while Codex runs, thinks, waits, or completes; hide it when idle.",
        "活动样式": "Activity Style",
        "自动会按状态切换；固定样式会一直使用选中的系统符号。": "Automatic changes with status; a fixed style always uses the selected symbol.",
        "布局": "Layout",
        "布局模式": "Layout Mode",
        "紧凑和标准会应用稳定预设，自定义保留所有细调能力。": "Compact and Standard apply stable presets; Custom exposes fine tuning.",
        "显示百分号": "Show Percent Sign",
        "关闭后只显示数字，适合菜单栏空间很紧张时使用。": "Show only numbers when menu bar space is limited.",
        "数字字重": "Number Weight",
        "控制菜单栏读数的视觉重量。": "Control the visual weight of menu bar values.",
        "显示密度": "Display Density",
        "项目间距": "Item Spacing",
        "两行行距": "Row Spacing",
        "数字字号": "Number Size",
        "小组件内容": "Widget Content",
        "跟随菜单栏会复用菜单栏的 5 小时 / 7 天窗口选择。": "Follow Menu Bar reuses its 5-hour and 7-day window selection.",
        "显示重置时间": "Show Reset Time",
        "在每行额度旁显示距离窗口重置还有多久。": "Show the time remaining until reset beside each quota.",
        "显示预期消耗速度": "Show Expected Pace",
        "在每个窗口下显示节奏偏差，以及预计耗尽或持续到重置。": "Show pace variance and whether quota will last until reset.",
        "显示最近同步": "Show Last Sync",
        "在底部显示最近一次成功读取的时间。": "Show the latest successful sync time at the bottom.",
        "显示账户摘要": "Show Account Summary",
        "在标题栏右侧显示账户邮箱和可读套餐标签。": "Show the account email and plan label in the header.",
        "用量": "Usage",
        "显示用量速度": "Show Usage Pace",
        "展示当前用量相对预期节奏是偏快还是有余量。": "Show whether usage is ahead of or below the expected pace.",
        "显示额外额度": "Show Additional Limits",
        "显示 Codex Spark 等接口返回的额外 rate limit。": "Show additional rate limits such as Codex Spark.",
        "活动": "Activity",
        "显示 Profile 概览": "Show Profile Overview",
        "展示累计 Token、峰值、最长任务和连续天数。": "Show lifetime tokens, peak usage, longest task, and streak.",
        "显示 Token 活动": "Show Token Activity",
        "展示每日、每周和累计 Token 活动柱状图。": "Show daily, weekly, and lifetime token activity charts.",
        "显示额度重置卡": "Show Reset Credits",
        "在 Token 活动下方显示可用重置卡数量和到期时间。": "Show available reset credits and expiry below token activity.",
        "洞察": "Insights",
        "显示活动洞察": "Show Activity Insights",
        "展示快速模式、推理强度、技能和会话统计。": "Show fast mode, reasoning effort, skills, and session statistics.",
        "显示最常用插件": "Show Top Plugins",
        "展示最近统计里最常用的插件或技能。": "Show the most-used plugins or skills from recent statistics.",
        "降智雷达": "Model Radar",
        "开启降智雷达": "Enable Model Radar",
        "读取 codexradar.com/current.json 并展示模型 IQ。": "Read codexradar.com/current.json and show model IQ.",
        "显示分值折线图": "Show Score Chart",
        "只绘制 IQ 90 及以上的历史分值。": "Plot historical scores with IQ 90 or higher.",
        "显示": "Display",
        "显示同步详情": "Show Sync Details",
        "展示限制状态和最近同步时间。": "Show limit status and the latest sync time.",
        "重置时间": "Reset Time",
        "倒计时适合快速扫读，具体时间适合规划任务开始时间。": "Countdowns scan quickly; clock times help plan task starts.",
        "连接": "Connection",
        "打开 Codex 目录": "Open Codex Folder",
        "在 Finder 中打开 Codex 配置目录。": "Open the Codex configuration folder in Finder.",
        "连接详情": "Connection Details",
        "读取方式": "Source",
        "数据来源": "Data Source",
        "接口": "API",
        "登录信息": "Sign-In Information",
        "已找到": "Found",
        "未找到": "Not Found",
        "CODEX_HOME/auth.json 或 ~/.codex/auth.json": "CODEX_HOME/auth.json or ~/.codex/auth.json",
        "诊断与维护": "Diagnostics & Maintenance",
        "打开缓存目录": "Open Cache Folder",
        "在 Finder 中打开快照缓存目录。": "Open the snapshot cache folder in Finder.",
        "打开状态目录": "Open Status Folder",
        "在 Finder 中打开 hook 活动状态目录。": "Open the hook activity status folder in Finder.",
        "状态文件": "Status File",
        "Hook 配置": "Hook Config",
        "Hook 脚本": "Hook Script",
        "清除最近同步缓存": "Clear Recent Sync Cache",
        "删除本地最新快照，下次刷新会重新保存。": "Delete the latest local snapshot; the next refresh saves a new one.",
        "最近同步缓存已清除。": "Recent sync cache cleared.",
        "清除失败：": "Failed to clear:",
        "更新": "Updates",
        "自动检查更新": "Automatically Check for Updates",
        "链接": "Links",
        "GitHub 项目主页": "GitHub Project",
        "版本发布记录": "Release Notes",
        "反馈问题": "Report an Issue",
        "打开关于": "Open About",
        "让 Codex 剩余额度、重置时间和使用节奏一眼可见。": "Keep Codex quota, reset times, and usage pace visible at a glance.",
        "已连接本机登录信息": "Connected to Local Sign-In",
        "未找到本机登录信息": "Local Sign-In Not Found",
        "重新读取 Codex 配置": "Reload Codex Configuration",
        "发现新版本": "New Version Available",
        "4 天": "4 Days",
        "5 天": "5 Days",
        "7 天": "7 Days",
        "立即检测": "Check Now",
        "跟随系统": "System",
        "简体中文": "Simplified Chinese",
        "预期消耗对比": "Expected Pace",
        "剩余额度": "Remaining Quota",
        "手动": "Manual",
        "30 秒": "30 Seconds",
        "1 分钟": "1 Minute",
        "5 分钟": "5 Minutes",
        "自动": "Automatic",
        "浅色": "Light",
        "深色": "Dark",
        "跟随菜单栏": "Follow Menu Bar",
        "5 小时 + 7 天": "5 Hours + 7 Days",
        "仅 5 小时": "5 Hours Only",
        "仅 7 天": "7 Days Only",
        "倒计时": "Countdown",
        "具体时间": "Clock Time",
        "紧凑": "Compact",
        "正常": "Normal",
        "标准": "Standard",
        "默认": "Default",
        "柔和": "Soft",
        "高对比": "High Contrast",
        "偏细": "Light",
        "适中": "Medium",
        "偏粗": "Bold",
        "竖向省略号": "Vertical Ellipsis",
        "目标指针": "Target Pointer",
        "空气波纹": "Air Ripple",
        "刷新": "Refresh",
        "设置": "Settings",
        "退出": "Quit",
        "安装 CodexMeter 新版本": "Install the New CodexMeter Version",
        "更新 CodexMeter": "Update CodexMeter",
        "额外额度": "Additional Limits",
        "暂无用量数据": "No Usage Data",
        "每日": "Daily",
        "每周": "Weekly",
        "累计": "Cumulative",
        "重置": "Resets",
        "用量进度": "Usage Progress",
        "用量速度": "Usage Pace",
        "绿色线：按当前时间进度推算的理论剩余位置；绿色表示实际用得比理论慢，有余量。": "Green line: expected remaining quota at the current time; usage is slower than expected.",
        "红色线：按当前时间进度推算的理论剩余位置；红色表示实际用得比理论快，可能提前耗尽。": "Red line: expected remaining quota at the current time; usage is faster and may run out early.",
        "额度重置卡": "Reset Credits",
        "暂无到期明细": "No Expiration Details",
        "正在读取重置卡...": "Loading Reset Credits...",
        "暂无重置卡信息": "No Reset Credit Information",
        "刷新额度重置卡": "Refresh Reset Credits",
        "累计 Token": "Lifetime Tokens",
        "峰值 Token": "Peak Tokens",
        "最长任务": "Longest Task",
        "连续天数": "Streak",
        "Token 活动": "Token Activity",
        "最近日": "Latest Day",
        "近 30 天": "Last 30 Days",
        "快速": "Fast",
        "推理": "Reasoning",
        "技能": "Skills",
        "技能次数": "Skill Uses",
        "会话": "Sessions",
        "最常用的插件": "Top Plugins",
        "限制": "Limit",
        "未触发": "Not Triggered",
        "同步": "Synced",
        "常态 90-110": "Normal 90–110",
        "暂无雷达数据": "No Radar Data",
        "打开 Codex Radar": "Open Codex Radar",
        "刷新降智雷达": "Refresh Model Radar",
        "降智雷达 IQ 曲线": "Model Radar IQ Chart",
        "可用": "Available",
        "已使用": "Used",
        "已过期": "Expired",
        "未知": "Unknown",
        "已重置": "Reset",
        "最小": "Minimal",
        "低": "Low",
        "中": "Medium",
        "高": "High",
        "超高": "Extra High",
        "显示 Codex 5 小时与 7 天窗口的最近同步余量。": "Show the latest synced Codex quota for the 5-hour and 7-day windows.",
        "暂无数据": "No Data",
        "打开菜单栏 App 后自动同步": "Open the menu bar app to sync automatically"
    ]
}

public enum UsageNotificationPreferenceKeys {
    public static let notifiesWhenDepleted = "notifications.quotaDepleted"
    public static let notifiesWhenLow = "notifications.lowRemaining"
    public static let lowRemainingThreshold = "notifications.lowRemainingThreshold"
}

public enum UsageCelebrationPreferenceKeys {
    public static let resetOption = "celebrations.resetOption"
}

public extension Notification.Name {
    static let playUsageResetConfettiPreview = Notification.Name("CodexMeter.playUsageResetConfettiPreview")
}

/// 定义哪些额度窗口重置时播放彩带；默认关闭，避免应用升级后突然出现全屏效果。
public enum UsageResetCelebrationOption: String, CaseIterable, Identifiable, Sendable {
    case off
    case session
    case weekly
    case both

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "关闭"
        case .session: "5 小时重置"
        case .weekly: "7 天重置"
        case .both: "两者"
        }
    }

    public var celebratesSessionReset: Bool {
        self == .session || self == .both
    }

    public var celebratesWeeklyReset: Bool {
        self == .weekly || self == .both
    }
}

/// 保存系统通知偏好；默认关闭，只有用户主动开启后才请求通知权限。
public struct UsageNotificationSettings: Equatable, Sendable {
    public static let defaultNotifiesWhenDepleted = false
    public static let defaultNotifiesWhenLow = false
    public static let defaultLowRemainingThreshold = 10

    public let notifiesWhenDepleted: Bool
    public let notifiesWhenLow: Bool
    public let lowRemainingThreshold: Int

    public init(
        notifiesWhenDepleted: Bool = Self.defaultNotifiesWhenDepleted,
        notifiesWhenLow: Bool = Self.defaultNotifiesWhenLow,
        lowRemainingThreshold: Int = Self.defaultLowRemainingThreshold
    ) {
        self.notifiesWhenDepleted = notifiesWhenDepleted
        self.notifiesWhenLow = notifiesWhenLow
        self.lowRemainingThreshold = max(1, min(50, lowRemainingThreshold))
    }

    public init(defaults: UserDefaults) {
        self.init(
            notifiesWhenDepleted: defaults.object(forKey: UsageNotificationPreferenceKeys.notifiesWhenDepleted)
                as? Bool ?? Self.defaultNotifiesWhenDepleted,
            notifiesWhenLow: defaults.object(forKey: UsageNotificationPreferenceKeys.notifiesWhenLow)
                as? Bool ?? Self.defaultNotifiesWhenLow,
            lowRemainingThreshold: defaults.object(forKey: UsageNotificationPreferenceKeys.lowRemainingThreshold)
                as? Int ?? Self.defaultLowRemainingThreshold
        )
    }
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
    public static let showsResetCredits = "popover.showsResetCredits"
    public static let resetTimeDisplayStyle = "popover.resetTimeDisplayStyle"

    public static let allKeys = [
        showsPaceComparison,
        showsProfileOverview,
        showsTokenActivity,
        showsActivityInsights,
        showsTopInvocations,
        showsSyncDetails,
        showsAdditionalLimits,
        showsResetCredits,
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
    public static let defaultShowsResetCredits = true
    public static let defaultResetTimeDisplayStyle = ResetTimeDisplayStyle.countdown

    public let showsPaceComparison: Bool
    public let showsProfileOverview: Bool
    public let showsTokenActivity: Bool
    public let showsActivityInsights: Bool
    public let showsTopInvocations: Bool
    public let showsSyncDetails: Bool
    public let showsAdditionalLimits: Bool
    public let showsResetCredits: Bool
    public let resetTimeDisplayStyle: ResetTimeDisplayStyle

    public init(
        showsPaceComparison: Bool = Self.defaultShowsPaceComparison,
        showsProfileOverview: Bool = Self.defaultShowsProfileOverview,
        showsTokenActivity: Bool = Self.defaultShowsTokenActivity,
        showsActivityInsights: Bool = Self.defaultShowsActivityInsights,
        showsTopInvocations: Bool = Self.defaultShowsTopInvocations,
        showsSyncDetails: Bool = Self.defaultShowsSyncDetails,
        showsAdditionalLimits: Bool = Self.defaultShowsAdditionalLimits,
        showsResetCredits: Bool = Self.defaultShowsResetCredits,
        resetTimeDisplayStyle: ResetTimeDisplayStyle = Self.defaultResetTimeDisplayStyle
    ) {
        self.showsPaceComparison = showsPaceComparison
        self.showsProfileOverview = showsProfileOverview
        self.showsTokenActivity = showsTokenActivity
        self.showsActivityInsights = showsActivityInsights
        self.showsTopInvocations = showsTopInvocations
        self.showsSyncDetails = showsSyncDetails
        self.showsAdditionalLimits = showsAdditionalLimits
        self.showsResetCredits = showsResetCredits
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
            showsResetCredits: defaults.object(forKey: PopoverPreferenceKeys.showsResetCredits) as? Bool
                ?? Self.defaultShowsResetCredits,
            resetTimeDisplayStyle: ResetTimeDisplayStyle(
                rawValue: defaults.string(forKey: PopoverPreferenceKeys.resetTimeDisplayStyle) ?? ""
            ) ?? Self.defaultResetTimeDisplayStyle
        )
    }

    public var usesDefaultValues: Bool {
        self == PopoverDisplaySettings()
    }

    /// 通知菜单栏弹窗重新构建内容；可附带重置卡开关值，避免快速关开时后台只读到最终状态。
    public static func notifyDidChange(
        defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults,
        showsResetCredits: Bool? = nil
    ) {
        defaults.synchronize()
        let userInfo = showsResetCredits.map { [PopoverPreferenceKeys.showsResetCredits: $0] }
        NotificationCenter.default.post(name: .popoverDisplaySettingsDidChange, object: defaults, userInfo: userInfo)
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
            return "目标指针"
        case .signature:
            return "空气波纹"
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
    // 兼容标识：旧版观察者和共享偏好继续使用原通知名，正式改名后不可修改。
    static let menuBarDisplaySettingsDidChange = Notification.Name("CodexUsage.menuBarDisplaySettingsDidChange")
    static let appBehaviorSettingsDidChange = Notification.Name("CodexUsage.appBehaviorSettingsDidChange")
    static let surfaceAppearanceSettingsDidChange = Notification.Name("CodexUsage.surfaceAppearanceSettingsDidChange")
    static let widgetDisplaySettingsDidChange = Notification.Name("CodexUsage.widgetDisplaySettingsDidChange")
    static let popoverDisplaySettingsDidChange = Notification.Name("CodexUsage.popoverDisplaySettingsDidChange")
    static let codexRadarSettingsDidChange = Notification.Name("CodexUsage.codexRadarSettingsDidChange")
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
        detailText(language: .chineseSimplified)
    }

    /// 按指定语言生成完整速度判断和预计耗尽文案。
    public func detailText(language: AppLanguage) -> String {
        let english = AppLocalization.usesEnglish(language: language)
        let leftText: String
        if deltaPercent == 0 {
            leftText = english ? "On pace" : "按正常节奏"
        } else if deltaPercent > 0 {
            leftText = english ? "Using \(deltaPercent)% faster" : "用得偏快 \(deltaPercent)%"
        } else {
            leftText = english ? "\(abs(deltaPercent))% headroom" : "有余量 \(abs(deltaPercent))%"
        }

        guard let rightText = rightText(language: language) else {
            return leftText
        }
        return "\(leftText) · \(rightText)"
    }

    public var widgetStatusText: String {
        widgetStatusText(language: .chineseSimplified)
    }

    /// 按指定语言生成小组件的短速度状态。
    public func widgetStatusText(language: AppLanguage) -> String {
        let english = AppLocalization.usesEnglish(language: language)
        if abs(deltaPercent) <= 2 {
            return english ? "On pace" : "节奏正常"
        }
        if deltaPercent > 0 {
            return english ? "\(deltaPercent)% over" : "超额 \(deltaPercent)%"
        }
        return english ? "\(abs(deltaPercent))% headroom" : "有余量 \(abs(deltaPercent))%"
    }

    public var widgetProjectionText: String? {
        widgetProjectionText(language: .chineseSimplified)
    }

    /// 按指定语言生成小组件的重置或耗尽预测。
    public func widgetProjectionText(language: AppLanguage) -> String? {
        let english = AppLocalization.usesEnglish(language: language)
        if willLastToReset {
            return english ? "Lasts until reset" : "持续到重置"
        }
        guard let etaSeconds else {
            return nil
        }
        let duration = Self.durationText(seconds: etaSeconds, language: language)
        if duration == (english ? "Now" : "现在") {
            return english ? "Quota depleted" : "额度已耗尽"
        }
        return english ? "Depletes in \(duration)" : "预计 \(duration)后耗尽"
    }

    /// 生成弹窗速度行右侧的预测文案。
    private func rightText(language: AppLanguage) -> String? {
        let english = AppLocalization.usesEnglish(language: language)
        if willLastToReset {
            return english ? "Lasts until reset" : "可持续到重置"
        }
        guard let etaSeconds else {
            return nil
        }
        let duration = Self.durationText(seconds: etaSeconds, language: language)
        if duration == (english ? "Now" : "现在") {
            return english ? "Quota depleted" : "额度已耗尽"
        }
        return english ? "Runs out in \(duration)" : "预计 \(duration)后用完"
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

    /// 将 ETA 秒数压缩成适合菜单栏和小组件扫读的短文本。
    private static func durationText(seconds: TimeInterval, language: AppLanguage) -> String {
        let english = AppLocalization.usesEnglish(language: language)
        guard seconds > 60 else {
            return english ? "Now" : "现在"
        }

        let totalMinutes = max(1, Int((seconds / 60).rounded()))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0, hours > 0 {
            return english ? "\(days)d \(hours)h" : "\(days)天\(hours)小时"
        }
        if days > 0 {
            return english ? "\(days)d" : "\(days)天"
        }
        if hours > 0, minutes > 0 {
            return english ? "\(hours)h \(minutes)m" : "\(hours)小时\(minutes)分"
        }
        if hours > 0 {
            return english ? "\(hours)h" : "\(hours)小时"
        }
        return english ? "\(minutes)m" : "\(minutes)分"
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

    /// 收集“用量速度”区域实际返回且达到展示阈值的窗口 Pace。
    public static func displays(
        rateLimits: RateLimitSnapshot,
        now: Date = Date(),
        weeklyProgressWorkDays: Int? = nil
    ) -> [UsageWindowPaceDisplay] {
        [
            UsageWindowPaceDisplay(
                id: "primary",
                title: rateLimits.primary?.durationLabel ?? "用量窗口",
                window: rateLimits.primary,
                now: now,
                weeklyProgressWorkDays: weeklyProgressWorkDays
            ),
            UsageWindowPaceDisplay(
                id: "secondary",
                title: rateLimits.secondary?.durationLabel ?? "用量窗口",
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

public struct CodexMeterWidgetDisplay: Equatable, Sendable {
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
        language: AppLanguage = .chineseSimplified,
        now: Date = Date()
    ) {
        var lines: [Line] = []
        let windows = Self.visibleWindows(menuBarSettings: settings, widgetSettings: widgetSettings)
        if windows.showsPrimary, let primary = snapshot.rateLimits.primary {
            lines.append(Self.line(
                id: "primary",
                title: primary.localizedDurationLabel(language: language),
                window: primary,
                resetText: widgetSettings.showsResetTime
                    ? formatter.resetRemainingText(window: primary, now: now)
                    : "",
                paceDisplay: widgetSettings.showsPaceComparison
                    ? UsageWindowPaceDisplay(
                        id: "primary",
                        title: primary.localizedDurationLabel(language: language),
                        window: primary,
                        now: now,
                        weeklyProgressWorkDays: settings.weeklyProgressWorkDays
                    )?.display
                    : nil,
                settings: settings,
                language: language
            ))
        }
        if windows.showsSecondary, let secondary = snapshot.rateLimits.secondary {
            lines.append(Self.line(
                id: "secondary",
                title: secondary.localizedDurationLabel(language: language),
                window: secondary,
                resetText: widgetSettings.showsResetTime
                    ? formatter.resetRemainingText(window: secondary, now: now)
                    : "",
                paceDisplay: widgetSettings.showsPaceComparison
                    ? UsageWindowPaceDisplay(
                        id: "secondary",
                        title: secondary.localizedDurationLabel(language: language),
                        window: secondary,
                        now: now,
                        weeklyProgressWorkDays: settings.weeklyProgressWorkDays
                    )?.display
                    : nil,
                settings: settings,
                language: language
            ))
        }
        if lines.isEmpty, let fallback = snapshot.rateLimits.primary ?? snapshot.rateLimits.secondary {
            lines.append(Self.line(
                id: "fallback",
                title: fallback.localizedDurationLabel(language: language),
                window: fallback,
                resetText: widgetSettings.showsResetTime
                    ? formatter.resetRemainingText(window: fallback, now: now)
                    : "",
                paceDisplay: widgetSettings.showsPaceComparison
                    ? UsageWindowPaceDisplay(
                        id: "fallback",
                        title: fallback.localizedDurationLabel(language: language),
                        window: fallback,
                        now: now,
                        weeklyProgressWorkDays: settings.weeklyProgressWorkDays
                    )?.display
                    : nil,
                settings: settings,
                language: language
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
        settings: MenuBarDisplaySettings,
        language: AppLanguage
    ) -> Line {
        let remainingPercent = window?.remainingPercent
        return Line(
            id: id,
            title: title,
            value: Self.value(for: remainingPercent, settings: settings),
            resetText: resetText,
            paceStatusText: paceDisplay?.widgetStatusText(language: language) ?? "",
            paceProjectionText: paceDisplay?.widgetProjectionText(language: language) ?? "",
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
