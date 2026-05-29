import Foundation

public struct RateLimitSnapshot: Codable, Equatable, Sendable {
    public let limitId: String?
    public let limitName: String?
    public let primary: RateLimitWindow?
    public let secondary: RateLimitWindow?
    public let credits: CreditsSnapshot?
    public let planType: String?
    public let rateLimitReachedType: String?

    public init(
        limitId: String?,
        limitName: String?,
        primary: RateLimitWindow?,
        secondary: RateLimitWindow?,
        credits: CreditsSnapshot?,
        planType: String?,
        rateLimitReachedType: String?
    ) {
        self.limitId = limitId
        self.limitName = limitName
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.planType = planType
        self.rateLimitReachedType = rateLimitReachedType
    }

    public var displayName: String {
        limitName ?? limitId ?? "Codex"
    }
}

public struct RateLimitWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Int?

    public init(usedPercent: Double, windowDurationMins: Int?, resetsAt: Int?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Int {
        let clampedUsage = min(max(usedPercent, 0), 100)
        return Int((100 - clampedUsage).rounded())
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

    public init(fetchedAt: Date, rateLimits: RateLimitSnapshot) {
        self.fetchedAt = fetchedAt
        self.rateLimits = rateLimits
    }
}

