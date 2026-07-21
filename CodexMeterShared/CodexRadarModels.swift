import Foundation

// 本文件定义降智雷达的共享偏好、刷新策略和可持久化数据模型。

/// 降智雷达偏好键，集中定义 UserDefaults 名称，避免设置页和后台任务写散字符串。
public enum CodexRadarPreferenceKeys {
    public static let isEnabled = "codexRadar.isEnabled"
    public static let showsScoreChart = "codexRadar.showsScoreChart"

    public static let allKeys = [
        isEnabled,
        showsScoreChart
    ]
}

/// 降智雷达开关设置；只控制外部雷达接口读取，不影响本机 Codex 用量同步。
public struct CodexRadarSettings: Equatable, Sendable {
    public static let defaultIsEnabled = true
    public static let defaultShowsScoreChart = false

    public let isEnabled: Bool
    public let showsScoreChart: Bool

    public init(
        isEnabled: Bool = Self.defaultIsEnabled,
        showsScoreChart: Bool = Self.defaultShowsScoreChart
    ) {
        self.isEnabled = isEnabled
        self.showsScoreChart = showsScoreChart
    }

    public init(defaults: UserDefaults) {
        self.init(
            isEnabled: defaults.object(forKey: CodexRadarPreferenceKeys.isEnabled) as? Bool
                ?? Self.defaultIsEnabled,
            showsScoreChart: defaults.object(forKey: CodexRadarPreferenceKeys.showsScoreChart) as? Bool
                ?? Self.defaultShowsScoreChart
        )
    }

    /// 通知主 App 重建雷达后台任务，确保设置开关即时生效。
    public static func notifyDidChange(defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults) {
        defaults.synchronize()
        NotificationCenter.default.post(name: .codexRadarSettingsDidChange, object: defaults)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    }
}

/// 降智雷达刷新策略；工作时间每小时，非工作时间每四小时。
public enum CodexRadarRefreshPolicy {
    public static let workingHourIntervalSeconds: TimeInterval = 60 * 60
    public static let offHourIntervalSeconds: TimeInterval = 4 * 60 * 60
    public static let workdayStartHour = 9
    public static let workdayEndHour = 18

    /// 判断给定时间是否处于本地周一至周五 09:00-18:00 的工作时间窗口。
    public static func isWorkingTime(date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let isoWeekday = weekday == 1 ? 7 : weekday - 1
        return isoWeekday <= 5 && hour >= workdayStartHour && hour < workdayEndHour
    }

    /// 返回当前时间对应的拉取间隔秒数；后台循环每次睡眠前都会重新计算。
    public static func intervalSeconds(for date: Date, calendar: Calendar = .current) -> TimeInterval {
        isWorkingTime(date: date, calendar: calendar)
            ? workingHourIntervalSeconds
            : offHourIntervalSeconds
    }
}

/// 降智雷达的一次可持久化快照；保存远端监测时间、模型智商和预测摘要。
public struct CodexRadarSnapshot: Codable, Equatable, Sendable {
    public let fetchedAt: Date
    public let monitoredAt: String?
    public let timezone: String?
    public let prediction: CodexRadarPrediction?
    public let modelIQ: CodexRadarModelIQ?

    public init(
        fetchedAt: Date,
        monitoredAt: String?,
        timezone: String?,
        prediction: CodexRadarPrediction?,
        modelIQ: CodexRadarModelIQ?
    ) {
        self.fetchedAt = fetchedAt
        self.monitoredAt = monitoredAt
        self.timezone = timezone
        self.prediction = prediction
        self.modelIQ = modelIQ
    }
}

/// 降智雷达的 reset 概率摘要；当前 UI 只展示核心概率和简短结论。
public struct CodexRadarPrediction: Codable, Equatable, Sendable {
    public let level: String?
    public let probability24h: Double?
    public let probability48h: Double?
    public let expectedWindow: String?
    public let summary: String?
    public let updatedAt: String?

    public init(
        level: String?,
        probability24h: Double?,
        probability48h: Double?,
        expectedWindow: String?,
        summary: String?,
        updatedAt: String?
    ) {
        self.level = level
        self.probability24h = probability24h
        self.probability48h = probability48h
        self.expectedWindow = expectedWindow
        self.summary = summary
        self.updatedAt = updatedAt
    }
}

/// 降智雷达的模型 IQ 区域；主模型和对照模型统一整理成 series 方便画折线。
public struct CodexRadarModelIQ: Codable, Equatable, Sendable {
    public let primary: CodexRadarModelSeries
    public let comparisons: [CodexRadarModelSeries]
    public let updatedAt: String?
    public let quotaRadarUpdatedAt: String?

    public init(
        primary: CodexRadarModelSeries,
        comparisons: [CodexRadarModelSeries],
        updatedAt: String? = nil,
        quotaRadarUpdatedAt: String? = nil
    ) {
        self.primary = primary
        self.comparisons = comparisons
        self.updatedAt = updatedAt
        self.quotaRadarUpdatedAt = quotaRadarUpdatedAt
    }

    public var allSeries: [CodexRadarModelSeries] {
        [primary] + comparisons
    }

    public var latestRuns: [CodexRadarIQRun] {
        allSeries.compactMap(\.latest)
    }

    /// 按预设模型能力和推理档位稳定排序，并返回界面允许展示的前若干项。
    public func displaySeries(limit: Int = 6) -> [CodexRadarModelSeries] {
        allSeries.enumerated()
            .sorted { left, right in
                let leftRank = Self.displayRank(for: left.element)
                let rightRank = Self.displayRank(for: right.element)
                if leftRank.model != rightRank.model {
                    return leftRank.model < rightRank.model
                }
                if leftRank.effort != rightRank.effort {
                    return leftRank.effort < rightRank.effort
                }
                return left.offset < right.offset
            }
            .prefix(max(limit, 0))
            .map(\.element)
    }

    /// 返回模型族和推理档位的显示优先级；未知值放在已知值之后。
    private static func displayRank(for series: CodexRadarModelSeries) -> (model: Int, effort: Int) {
        let family = series.model?
            .lowercased()
            .split(separator: "-")
            .last
            .map(String.init)
        let modelRank: Int
        switch family {
        case "sol": modelRank = 0
        case "terra": modelRank = 1
        case "luna": modelRank = 2
        default: modelRank = 3
        }

        let effortRank: Int
        switch series.reasoningEffort?.lowercased() {
        case "ultra": effortRank = 0
        case "max": effortRank = 1
        case "xhigh": effortRank = 2
        case "high": effortRank = 3
        case "medium": effortRank = 4
        case "low": effortRank = 5
        default: effortRank = 6
        }
        return (modelRank, effortRank)
    }
}

/// 图表中的单条模型曲线；id 保留远端 comparison key，label 用于展示。
public struct CodexRadarModelSeries: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let model: String?
    public let reasoningEffort: String?
    public let latest: CodexRadarIQRun?
    public let recentDays: [CodexRadarIQRun]

    public init(
        id: String,
        label: String,
        model: String?,
        reasoningEffort: String?,
        latest: CodexRadarIQRun?,
        recentDays: [CodexRadarIQRun]
    ) {
        self.id = id
        self.label = label
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.latest = latest
        self.recentDays = recentDays
    }
}

/// 单次模型 IQ 跑分结果；字段保持宽松可选，兼容雷达源后续增减指标。
public struct CodexRadarIQRun: Codable, Equatable, Identifiable, Sendable {
    public let date: String
    public let score: Double
    public let status: String?
    public let passed: Int?
    public let tasks: Int?
    public let invalid: Int?
    public let totalTokens: Int?
    public let wallTimeHuman: String?
    public let model: String?
    public let reasoningEffort: String?
    public let costUSD: Double?

    public init(
        date: String,
        score: Double,
        status: String?,
        passed: Int?,
        tasks: Int?,
        invalid: Int?,
        totalTokens: Int?,
        wallTimeHuman: String?,
        model: String?,
        reasoningEffort: String?,
        costUSD: Double?
    ) {
        self.date = date
        self.score = score
        self.status = status
        self.passed = passed
        self.tasks = tasks
        self.invalid = invalid
        self.totalTokens = totalTokens
        self.wallTimeHuman = wallTimeHuman
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.costUSD = costUSD
    }

    public var id: String {
        "\(date)-\(model ?? "model")-\(reasoningEffort ?? "effort")"
    }
}
