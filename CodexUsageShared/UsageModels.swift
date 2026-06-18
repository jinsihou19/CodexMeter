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

    public func usagePace(now: Date = Date()) -> UsagePace? {
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
        let expectedUsedPercent = (elapsedSeconds / durationSeconds) * 100
        let actualUsedPercent = min(max(usedPercent, 0), 100)
        guard elapsedSeconds > 0 || actualUsedPercent == 0 else {
            return nil
        }

        let deltaPercent = actualUsedPercent - expectedUsedPercent
        var etaSeconds: TimeInterval?
        var willLastToReset = false

        if actualUsedPercent >= 100 {
            etaSeconds = 0
        } else if elapsedSeconds > 0, actualUsedPercent > 0 {
            let usageRate = actualUsedPercent / elapsedSeconds
            let remainingUsagePercent = 100 - actualUsedPercent
            let candidateEtaSeconds = remainingUsagePercent / usageRate
            if candidateEtaSeconds >= remainingSeconds {
                willLastToReset = true
            } else {
                etaSeconds = candidateEtaSeconds
            }
        } else if elapsedSeconds > 0 {
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
}

public struct UsagePace: Equatable, Sendable {
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
    public let profileStats: CodexProfileStats?

    public init(
        fetchedAt: Date,
        rateLimits: RateLimitSnapshot,
        profileStats: CodexProfileStats? = nil
    ) {
        self.fetchedAt = fetchedAt
        self.rateLimits = rateLimits
        self.profileStats = profileStats
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
