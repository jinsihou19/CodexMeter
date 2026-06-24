import Foundation

public struct RateLimitSnapshot: Codable, Equatable, Sendable {
    public let limitId: String?
    public let limitName: String?
    public let primary: RateLimitWindow?
    public let secondary: RateLimitWindow?
    public let additionalLimits: [AdditionalRateLimitSnapshot]
    public let credits: CreditsSnapshot?
    public let planType: String?
    public let rateLimitReachedType: String?

    public init(
        limitId: String?,
        limitName: String?,
        primary: RateLimitWindow?,
        secondary: RateLimitWindow?,
        additionalLimits: [AdditionalRateLimitSnapshot] = [],
        credits: CreditsSnapshot?,
        planType: String?,
        rateLimitReachedType: String?
    ) {
        self.limitId = limitId
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
        self.additionalLimits = additionalLimits
        self.credits = credits
        self.planType = planType
        self.rateLimitReachedType = rateLimitReachedType
    }

    enum CodingKeys: String, CodingKey {
        case limitId
        case limitName
        case primary
        case secondary
        case additionalLimits
        case credits
        case planType
        case rateLimitReachedType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.limitId = try container.decodeIfPresent(String.self, forKey: .limitId)
        self.limitName = try container.decodeIfPresent(String.self, forKey: .limitName)
        self.primary = try container.decodeIfPresent(RateLimitWindow.self, forKey: .primary)
        self.secondary = try container.decodeIfPresent(RateLimitWindow.self, forKey: .secondary)
        self.additionalLimits = try container.decodeIfPresent(
            [AdditionalRateLimitSnapshot].self,
            forKey: .additionalLimits
        ) ?? []
        self.credits = try container.decodeIfPresent(CreditsSnapshot.self, forKey: .credits)
        self.planType = try container.decodeIfPresent(String.self, forKey: .planType)
        self.rateLimitReachedType = try container.decodeIfPresent(String.self, forKey: .rateLimitReachedType)
    }

    public var displayName: String {
        limitName ?? limitId ?? "Codex"
    }
}

public struct AdditionalRateLimitSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let limitName: String?
    public let meteredFeature: String?
    public let primary: RateLimitWindow?
    public let secondary: RateLimitWindow?

    public init(
        limitName: String?,
        meteredFeature: String?,
        primary: RateLimitWindow?,
        secondary: RateLimitWindow?
    ) {
        self.limitName = limitName
        self.meteredFeature = meteredFeature
        self.primary = primary
        self.secondary = secondary
    }

    public var id: String {
        limitName ?? meteredFeature ?? "additional"
    }

    public var displayName: String {
        limitName ?? meteredFeature ?? "额外额度"
    }
}

public struct RateLimitWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Int?
    public let resetAfterSeconds: Int?

    public init(
        usedPercent: Double,
        windowDurationMins: Int?,
        resetsAt: Int?,
        resetAfterSeconds: Int? = nil
    ) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
        self.resetAfterSeconds = resetAfterSeconds
    }

    public var remainingPercent: Int {
        let clampedUsage = min(max(usedPercent, 0), 100)
        return Int((100 - clampedUsage).rounded())
    }

    public var usedPercentRounded: Int {
        Int(min(max(usedPercent, 0), 100).rounded())
    }

    /// 计算窗口的理论消耗进度；周窗口可按工作日切分，避免周末时间稀释工作日用量节奏。
    public func usagePace(now: Date = Date(), weeklyProgressWorkDays: Int? = nil, calendar: Calendar = .current) -> UsagePace? {
        guard let windowDurationMins, windowDurationMins > 0 else {
            return nil
        }

        let durationSeconds = Double(windowDurationMins * 60)
        let remainingSeconds: Double
        if let resetAfterSeconds {
            remainingSeconds = Double(resetAfterSeconds)
        } else if let resetsAt {
            remainingSeconds = Double(resetsAt) - now.timeIntervalSince1970
        } else {
            return nil
        }

        guard remainingSeconds > 0, remainingSeconds <= durationSeconds else {
            return nil
        }

        let elapsedSeconds = durationSeconds - remainingSeconds
        let workdayProgress = Self.weeklyWorkdayProgress(
            now: now,
            durationSeconds: durationSeconds,
            remainingSeconds: remainingSeconds,
            workDays: weeklyProgressWorkDays,
            calendar: calendar
        )
        let expectedUsedPercent = workdayProgress?.expectedUsedPercent ?? (elapsedSeconds / durationSeconds) * 100
        let actualUsedPercent = min(max(usedPercent, 0), 100)
        guard elapsedSeconds > 0 || actualUsedPercent == 0 else {
            return nil
        }

        let deltaPercent = actualUsedPercent - expectedUsedPercent
        var etaSeconds: TimeInterval?
        var willLastToReset = false

        let paceElapsedSeconds = workdayProgress?.elapsedSeconds ?? elapsedSeconds
        if actualUsedPercent >= 100 {
            etaSeconds = 0
        } else if paceElapsedSeconds > 0, actualUsedPercent > 0 {
            let usageRate = actualUsedPercent / paceElapsedSeconds
            let remainingUsagePercent = 100 - actualUsedPercent
            let candidateEtaSeconds = remainingUsagePercent / usageRate
            let effectiveRemainingSeconds = workdayProgress?.remainingSeconds ?? remainingSeconds
            if candidateEtaSeconds >= effectiveRemainingSeconds {
                willLastToReset = true
            } else if let workDays = workdayProgress?.workDays {
                etaSeconds = Self.wallClockInterval(
                    from: now,
                    consumingWorkSeconds: candidateEtaSeconds,
                    resetAfterSeconds: remainingSeconds,
                    workDays: workDays,
                    calendar: calendar
                )
            } else {
                etaSeconds = candidateEtaSeconds
            }
        } else if paceElapsedSeconds > 0 {
            willLastToReset = true
        }

        return UsagePace(
            deltaPercent: deltaPercent,
            expectedUsedPercent: expectedUsedPercent,
            actualUsedPercent: actualUsedPercent,
            etaSeconds: etaSeconds,
            willLastToReset: willLastToReset
        )
    }

    public func paceDeltaPercent(now: Date = Date()) -> Int? {
        usagePace(now: now).map { Int($0.deltaPercent.rounded()) }
    }

    private struct WorkdayProgress {
        let workDays: Int
        let totalSeconds: TimeInterval
        let elapsedSeconds: TimeInterval
        let remainingSeconds: TimeInterval

        var expectedUsedPercent: Double {
            min(max((elapsedSeconds / totalSeconds) * 100, 0), 100)
        }
    }

    /// 只对标准 7 天窗口启用工作日进度；其他窗口继续使用线性时间进度。
    private static func weeklyWorkdayProgress(
        now: Date,
        durationSeconds: TimeInterval,
        remainingSeconds: TimeInterval,
        workDays: Int?,
        calendar: Calendar
    ) -> WorkdayProgress? {
        guard let workDays, workDays >= 2, workDays < 7, Int(durationSeconds) == 10_080 * 60 else {
            return nil
        }

        let resetsAt = now.addingTimeInterval(remainingSeconds)
        let windowStart = resetsAt.addingTimeInterval(-durationSeconds)
        var totalWorkSeconds: TimeInterval = 0
        var elapsedWorkSeconds: TimeInterval = 0
        var remainingWorkSeconds: TimeInterval = 0
        var cursor = windowStart

        while cursor < resetsAt {
            guard let nextDay = nextDayBoundary(after: cursor, calendar: calendar), nextDay > cursor else {
                return nil
            }
            let sliceEnd = min(nextDay, resetsAt)
            if isWorkday(cursor, calendar: calendar, workDays: workDays) {
                let sliceDuration = sliceEnd.timeIntervalSince(cursor)
                totalWorkSeconds += sliceDuration
                if now > cursor {
                    elapsedWorkSeconds += min(now, sliceEnd).timeIntervalSince(cursor)
                }
                if now < sliceEnd {
                    remainingWorkSeconds += sliceEnd.timeIntervalSince(max(now, cursor))
                }
            }
            cursor = sliceEnd
        }

        guard totalWorkSeconds > 0 else {
            return nil
        }
        return WorkdayProgress(
            workDays: workDays,
            totalSeconds: totalWorkSeconds,
            elapsedSeconds: elapsedWorkSeconds,
            remainingSeconds: remainingWorkSeconds
        )
    }

    /// 把剩余可工作秒数换算回自然时间，保证 ETA 会跨过非工作日空档。
    private static func wallClockInterval(
        from now: Date,
        consumingWorkSeconds requiredWorkSeconds: TimeInterval,
        resetAfterSeconds: TimeInterval,
        workDays: Int,
        calendar: Calendar
    ) -> TimeInterval? {
        guard requiredWorkSeconds > 0 else {
            return 0
        }

        let resetsAt = now.addingTimeInterval(resetAfterSeconds)
        var remaining = requiredWorkSeconds
        var cursor = now
        while cursor < resetsAt {
            guard let nextDay = nextDayBoundary(after: cursor, calendar: calendar), nextDay > cursor else {
                return nil
            }
            let sliceEnd = min(nextDay, resetsAt)
            if isWorkday(cursor, calendar: calendar, workDays: workDays) {
                let available = sliceEnd.timeIntervalSince(cursor)
                if remaining <= available {
                    return cursor.addingTimeInterval(remaining).timeIntervalSince(now)
                }
                remaining -= available
            }
            cursor = sliceEnd
        }
        return nil
    }

    /// 按本地日界切片，避免窗口重置时间不是零点时把整天归类错位。
    private static func nextDayBoundary(after date: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
    }

    /// 使用 ISO 周序号判定工作日，1...workDays 分别对应周一到配置的最后工作日。
    private static func isWorkday(_ date: Date, calendar: Calendar, workDays: Int) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let isoWeekday = weekday == 1 ? 7 : weekday - 1
        return isoWeekday <= workDays
    }
}

public struct UsagePace: Equatable, Sendable {
    public static let minimumDisplayExpectedUsedPercent = 3.0

    public let deltaPercent: Double
    public let expectedUsedPercent: Double
    public let actualUsedPercent: Double
    public let etaSeconds: TimeInterval?
    public let willLastToReset: Bool

    public init(
        deltaPercent: Double,
        expectedUsedPercent: Double,
        actualUsedPercent: Double,
        etaSeconds: TimeInterval?,
        willLastToReset: Bool
    ) {
        self.deltaPercent = deltaPercent
        self.expectedUsedPercent = expectedUsedPercent
        self.actualUsedPercent = actualUsedPercent
        self.etaSeconds = etaSeconds
        self.willLastToReset = willLastToReset
    }

    public var roundedDeltaPercent: Int {
        Int(deltaPercent.rounded())
    }

    public var roundedActualUsedPercent: Int {
        Int(actualUsedPercent.rounded())
    }

    public var roundedExpectedUsedPercent: Int {
        Int(expectedUsedPercent.rounded())
    }

    /// 判断当前窗口进度是否足够用于展示 Pace，避免刚重置时少量用量造成夸张偏差。
    public func isDisplayable(
        minimumExpectedUsedPercent: Double = UsagePace.minimumDisplayExpectedUsedPercent
    ) -> Bool {
        expectedUsedPercent >= minimumExpectedUsedPercent
    }
}

public struct CreditsSnapshot: Codable, Equatable, Sendable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?

    public init(hasCredits: Bool, unlimited: Bool, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let fetchedAt: Date
    public let rateLimits: RateLimitSnapshot
    public let account: CodexAccountSnapshot?
    public let profileStats: CodexProfileStats?
    public let resetCredits: ResetCreditsSnapshot?

    public init(
        fetchedAt: Date,
        rateLimits: RateLimitSnapshot,
        account: CodexAccountSnapshot? = nil,
        profileStats: CodexProfileStats? = nil,
        resetCredits: ResetCreditsSnapshot? = nil
    ) {
        self.fetchedAt = fetchedAt
        self.rateLimits = rateLimits
        self.account = account
        self.profileStats = profileStats
        self.resetCredits = resetCredits
    }

    public var accountEmail: String? {
        account?.email
    }

    public var accountPlanType: String? {
        account?.planType ?? rateLimits.planType
    }

    public var accountPlanDisplayText: String? {
        CodexPlanFormatter.displayName(for: accountPlanType)
    }

    public var accountPlanCompactDisplayText: String? {
        CodexPlanFormatter.compactDisplayName(for: accountPlanType)
    }
}

/// 保存额度重置卡接口的展示快照；只记录数量、状态和时间，不保存任何认证材料。
public struct ResetCreditsSnapshot: Codable, Equatable, Sendable {
    public let availableCount: Int
    public let credits: [ResetCreditSnapshot]

    public init(availableCount: Int, credits: [ResetCreditSnapshot] = []) {
        self.availableCount = max(0, availableCount)
        self.credits = credits
    }

    public var hasDisplayableContent: Bool {
        availableCount > 0 || !credits.isEmpty
    }

    /// 按到期时间升序排列，未知到期时间放在最后，方便优先看到最需要关注的卡。
    public var creditsSortedByExpiration: [ResetCreditSnapshot] {
        credits.sorted { lhs, rhs in
            switch (lhs.expiresAt, rhs.expiresAt) {
            case let (left?, right?):
                return left < right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs.status < rhs.status
            }
        }
    }
}

/// 描述单张额度重置卡的生命周期；状态字段保持接口原文，展示层再做本地化。
public struct ResetCreditSnapshot: Codable, Equatable, Sendable {
    public let grantedAt: Date?
    public let expiresAt: Date?
    public let status: String

    public init(grantedAt: Date?, expiresAt: Date?, status: String) {
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.status = Self.normalizedStatus(status)
    }

    public var localizedStatus: String {
        switch status.lowercased() {
        case "available", "active":
            return "可用"
        case "used", "consumed":
            return "已使用"
        case "expired":
            return "已过期"
        default:
            return status.isEmpty ? "未知" : status
        }
    }

    /// 归一化状态字段；空值保留为未知，避免 UI 展示空白标签。
    private static func normalizedStatus(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }
}

/// 保存来自本机 Codex 登录态的账户身份摘要；只包含可展示字段，不保存 token 或认证材料。
public struct CodexAccountSnapshot: Codable, Equatable, Sendable {
    public let email: String?
    public let planType: String?

    public init(email: String?, planType: String?) {
        self.email = Self.normalizedEmail(email)
        self.planType = Self.normalizedField(planType)
    }

    public var isEmpty: Bool {
        email == nil && planType == nil
    }

    /// 归一化邮箱字段，避免空白字符串写入缓存或展示在弹窗头部。
    private static func normalizedEmail(_ value: String?) -> String? {
        normalizedField(value)?.lowercased()
    }

    /// 归一化账户字段；空字符串代表未知，不参与快照。
    private static func normalizedField(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

/// 将 Codex API 的内部套餐标识转成适合 UI 展示的短标签。
public enum CodexPlanFormatter {
    /// 返回可读套餐名称；未知标识会做轻量清洗，避免把 snake_case 原样显示给用户。
    public static func displayName(for rawPlanType: String?) -> String? {
        guard let rawPlanType = rawPlanType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPlanType.isEmpty
        else {
            return nil
        }

        switch normalizedKey(rawPlanType) {
        case "prolite":
            return "Pro 5x"
        case "pro":
            return "Pro 20x"
        case "plus":
            return "Plus"
        case "team":
            return "Team"
        case "enterprise":
            return "Enterprise"
        case "free":
            return "Free"
        default:
            return cleanedDisplayName(rawPlanType)
        }
    }

    /// 返回适合狭窄界面的套餐短标签；已知 Pro 档位去掉重复品牌前缀，保留倍率信息。
    public static func compactDisplayName(for rawPlanType: String?) -> String? {
        guard let displayName = displayName(for: rawPlanType) else {
            return nil
        }
        return compactDisplayName(from: displayName)
    }

    /// 统一内部标识的大小写和分隔符，方便兼容 prolite / pro_lite / pro-lite。
    private static func normalizedKey(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    /// 压缩已经本地化过的套餐名称；未知套餐保持原文，避免误删用户需要识别的企业标签。
    private static func compactDisplayName(from displayName: String) -> String {
        if displayName.hasPrefix("Pro ") {
            return String(displayName.dropFirst("Pro ".count))
        }
        return displayName
    }

    /// 将未知套餐标识拆词首字母大写，作为比原始字段更友好的兜底展示。
    private static func cleanedDisplayName(_ value: String) -> String {
        let words = value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                let lowercased = word.lowercased()
                return lowercased.prefix(1).uppercased() + String(lowercased.dropFirst())
            }
        return words.isEmpty ? value : words.joined(separator: " ")
    }
}

public struct CodexProfileStats: Codable, Equatable, Sendable {
    public let lifetimeTokens: Int64?
    public let peakDailyTokens: Int64?
    public let longestRunningTurnSeconds: Int?
    public let currentStreakDays: Int?
    public let longestStreakDays: Int?
    public let fastModeUsagePercentage: Double?
    public let mostUsedReasoningEffort: String?
    public let mostUsedReasoningEffortPercentage: Double?
    public let totalThreads: Int?
    public let totalSkillsUsed: Int?
    public let uniqueSkillsUsed: Int?
    public let workspaceRank: Int?
    public let workspaceTotalUserCount: Int?
    public let dailyUsageBuckets: [CodexTokenUsageBucket]
    public let weeklyUsageBuckets: [CodexTokenUsageBucket]
    public let cumulativeDailyUsageBuckets: [CodexTokenUsageBucket]
    public let topInvocations: [CodexTopInvocation]

    public init(
        lifetimeTokens: Int64?,
        peakDailyTokens: Int64?,
        longestRunningTurnSeconds: Int?,
        currentStreakDays: Int?,
        longestStreakDays: Int?,
        fastModeUsagePercentage: Double?,
        mostUsedReasoningEffort: String?,
        mostUsedReasoningEffortPercentage: Double?,
        totalThreads: Int?,
        totalSkillsUsed: Int?,
        uniqueSkillsUsed: Int?,
        workspaceRank: Int? = nil,
        workspaceTotalUserCount: Int? = nil,
        dailyUsageBuckets: [CodexTokenUsageBucket] = [],
        weeklyUsageBuckets: [CodexTokenUsageBucket] = [],
        cumulativeDailyUsageBuckets: [CodexTokenUsageBucket] = [],
        topInvocations: [CodexTopInvocation] = []
    ) {
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.longestRunningTurnSeconds = longestRunningTurnSeconds
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
        self.fastModeUsagePercentage = fastModeUsagePercentage
        self.mostUsedReasoningEffort = mostUsedReasoningEffort
        self.mostUsedReasoningEffortPercentage = mostUsedReasoningEffortPercentage
        self.totalThreads = totalThreads
        self.totalSkillsUsed = totalSkillsUsed
        self.uniqueSkillsUsed = uniqueSkillsUsed
        self.workspaceRank = workspaceRank
        self.workspaceTotalUserCount = workspaceTotalUserCount
        self.dailyUsageBuckets = dailyUsageBuckets
        self.weeklyUsageBuckets = weeklyUsageBuckets
        self.cumulativeDailyUsageBuckets = cumulativeDailyUsageBuckets
        self.topInvocations = topInvocations
    }

    public var latestDailyTokens: Int64? {
        dailyUsageBuckets.last?.tokens
    }

    public var recentDailyTokens: Int64 {
        dailyUsageBuckets.reduce(Int64(0)) { $0 + $1.tokens }
    }
}

public struct CodexTokenUsageBucket: Codable, Equatable, Identifiable, Sendable {
    public let startDate: String
    public let tokens: Int64

    public init(startDate: String, tokens: Int64) {
        self.startDate = startDate
        self.tokens = tokens
    }

    public var id: String {
        startDate
    }
}

public struct CodexTopInvocation: Codable, Equatable, Identifiable, Sendable {
    public let type: String
    public let pluginId: String?
    public let pluginName: String?
    public let skillId: String?
    public let skillName: String?
    public let usageCount: Int

    public init(
        type: String,
        pluginId: String?,
        pluginName: String?,
        skillId: String?,
        skillName: String?,
        usageCount: Int
    ) {
        self.type = type
        self.pluginId = pluginId
        self.pluginName = pluginName
        self.skillId = skillId
        self.skillName = skillName
        self.usageCount = usageCount
    }

    public var id: String {
        "\(type)-\(displayName)"
    }

    public var displayName: String {
        pluginName ?? skillName ?? pluginId ?? skillId ?? type
    }
}
