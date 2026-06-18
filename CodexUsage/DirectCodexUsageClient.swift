import CodexUsageShared
import Foundation

protocol UsageRateLimitFetching: Sendable {
    func fetchRateLimits() async throws -> RateLimitSnapshot
    func fetchUsageSnapshot() async throws -> UsageSnapshot
}

extension UsageRateLimitFetching {
    func fetchUsageSnapshot() async throws -> UsageSnapshot {
        let rateLimits = try await fetchRateLimits()
        return UsageSnapshot(fetchedAt: Date(), rateLimits: rateLimits)
    }
}

struct DirectCodexUsageClient: UsageRateLimitFetching {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    static let defaultEndpointURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let defaultProfileEndpointURL = URL(string: "https://chatgpt.com/backend-api/wham/profiles/me")!

    private let authFileURL: URL
    private let endpointURL: URL
    private let profileEndpointURL: URL
    private let timeoutSeconds: TimeInterval
    private let transport: Transport

    init(
        authFileURL: URL = Self.defaultAuthFileURL(),
        endpointURL: URL = Self.defaultEndpointURL,
        profileEndpointURL: URL = Self.defaultProfileEndpointURL,
        timeoutSeconds: TimeInterval = 45,
        transport: @escaping Transport = Self.urlSessionTransport
    ) {
        self.authFileURL = authFileURL
        self.endpointURL = endpointURL
        self.profileEndpointURL = profileEndpointURL
        self.timeoutSeconds = timeoutSeconds
        self.transport = transport
    }

    func fetchRateLimits() async throws -> RateLimitSnapshot {
        let accessToken = try loadAccessToken()
        return try await fetchRateLimits(accessToken: accessToken)
    }

    func fetchUsageSnapshot() async throws -> UsageSnapshot {
        let accessToken = try loadAccessToken()
        async let rateLimits = fetchRateLimits(accessToken: accessToken)
        async let profileStats = fetchProfileStatsIfAvailable(accessToken: accessToken)

        return UsageSnapshot(
            fetchedAt: Date(),
            rateLimits: try await rateLimits,
            profileStats: await profileStats
        )
    }

    private func fetchRateLimits(accessToken: String) async throws -> RateLimitSnapshot {
        let request = authenticatedRequest(url: endpointURL, accessToken: accessToken)

        do {
            let (data, response) = try await transport(request)
            guard (200..<300).contains(response.statusCode) else {
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw DirectCodexUsageClientError.httpStatus(response.statusCode, message)
            }
            return try JSONDecoder().decode(WhamUsageResponse.self, from: data).codexSnapshot
        } catch let error as DirectCodexUsageClientError {
            throw error
        } catch let error as DecodingError {
            throw DirectCodexUsageClientError.invalidResponse(error.localizedDescription)
        } catch {
            throw DirectCodexUsageClientError.network(error.localizedDescription)
        }
    }

    private func fetchProfileStatsIfAvailable(accessToken: String) async -> CodexProfileStats? {
        do {
            return try await fetchProfileStats(accessToken: accessToken)
        } catch {
            return nil
        }
    }

    private func fetchProfileStats(accessToken: String) async throws -> CodexProfileStats? {
        let request = authenticatedRequest(url: profileEndpointURL, accessToken: accessToken)

        do {
            let (data, response) = try await transport(request)
            guard (200..<300).contains(response.statusCode) else {
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw DirectCodexUsageClientError.httpStatus(response.statusCode, message)
            }
            return try JSONDecoder().decode(WhamProfileResponse.self, from: data).stats?.codexProfileStats
        } catch let error as DirectCodexUsageClientError {
            throw error
        } catch let error as DecodingError {
            throw DirectCodexUsageClientError.invalidResponse(error.localizedDescription)
        } catch {
            throw DirectCodexUsageClientError.network(error.localizedDescription)
        }
    }

    /// 构造 Codex API 请求，并显式绕过系统缓存，避免菜单栏显示旧的剩余额度。
    private func authenticatedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeoutSeconds
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("codex-usage-widget/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func loadAccessToken() throws -> String {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            throw DirectCodexUsageClientError.missingAuthFile
        }
        let data = try Data(contentsOf: authFileURL)
        let auth = try JSONDecoder().decode(CodexAuthFile.self, from: data)
        guard let token = auth.tokens?.accessToken, !token.isEmpty else {
            throw DirectCodexUsageClientError.missingAccessToken
        }
        return token
    }

    static func defaultAuthFileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let codexHome = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true).path
        return URL(fileURLWithPath: codexHome, isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)
    }

    private static func urlSessionTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DirectCodexUsageClientError.invalidHTTPResponse
        }
        return (data, httpResponse)
    }
}

enum DirectCodexUsageClientError: LocalizedError, Equatable {
    case missingAuthFile
    case missingAccessToken
    case invalidHTTPResponse
    case httpStatus(Int, String?)
    case invalidResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingAuthFile:
            return "找不到 Codex 登录信息。请先在 Codex 登录 ChatGPT。"
        case .missingAccessToken:
            return "Codex 登录信息里没有可用 access token。请重新登录 Codex。"
        case .invalidHTTPResponse:
            return "Codex 用量接口响应不可识别。"
        case .httpStatus(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Codex 用量接口返回 \(statusCode)：\(message)"
            }
            return "Codex 用量接口返回 \(statusCode)。"
        case .invalidResponse:
            return "Codex 用量响应格式不可识别。"
        case .network(let message):
            return "读取 Codex 用量网络失败：\(message)"
        }
    }
}

private struct CodexAuthFile: Decodable {
    let tokens: Tokens?

    struct Tokens: Decodable {
        let accessToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }
}

private struct WhamUsageResponse: Decodable {
    let planType: String?
    let rateLimit: WhamRateLimit?
    let additionalRateLimits: [WhamAdditionalRateLimit]?
    let credits: WhamCredits?
    let rateLimitReachedType: String?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
        case credits
        case rateLimitReachedType = "rate_limit_reached_type"
    }

    var codexSnapshot: RateLimitSnapshot {
        RateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: rateLimit?.primaryWindow?.rateLimitWindow,
            secondary: rateLimit?.secondaryWindow?.rateLimitWindow,
            additionalLimits: additionalRateLimits?.map(\.additionalRateLimitSnapshot) ?? [],
            credits: credits?.creditsSnapshot,
            planType: planType,
            rateLimitReachedType: rateLimitReachedType
        )
    }
}

private struct WhamRateLimit: Decodable {
    let primaryWindow: WhamWindow?
    let secondaryWindow: WhamWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct WhamWindow: Decodable {
    let usedPercent: Double
    let limitWindowSeconds: Int?
    let resetAfterSeconds: Int?
    let resetAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }

    var rateLimitWindow: RateLimitWindow {
        RateLimitWindow(
            usedPercent: usedPercent,
            windowDurationMins: limitWindowSeconds.map { $0 / 60 },
            resetsAt: resetAt,
            resetAfterSeconds: resetAfterSeconds
        )
    }
}

private struct WhamAdditionalRateLimit: Decodable {
    let limitName: String?
    let meteredFeature: String?
    let rateLimit: WhamRateLimit?

    enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case meteredFeature = "metered_feature"
        case rateLimit = "rate_limit"
    }

    var additionalRateLimitSnapshot: AdditionalRateLimitSnapshot {
        AdditionalRateLimitSnapshot(
            limitName: limitName,
            meteredFeature: meteredFeature,
            primary: rateLimit?.primaryWindow?.rateLimitWindow,
            secondary: rateLimit?.secondaryWindow?.rateLimitWindow
        )
    }
}

private struct WhamCredits: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }

    var creditsSnapshot: CreditsSnapshot {
        CreditsSnapshot(hasCredits: hasCredits, unlimited: unlimited, balance: balance)
    }
}

private struct WhamProfileResponse: Decodable {
    let stats: WhamProfileStats?
}

private struct WhamProfileStats: Decodable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSeconds: Int?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
    let fastModeUsagePercentage: Double?
    let mostUsedReasoningEffort: String?
    let mostUsedReasoningEffortPercentage: Double?
    let totalThreads: Int?
    let totalSkillsUsed: Int?
    let uniqueSkillsUsed: Int?
    let workspaceRank: Int?
    let workspaceTotalUserCount: Int?
    let dailyUsageBuckets: [WhamTokenUsageBucket]?
    let weeklyUsageBuckets: [WhamTokenUsageBucket]?
    let cumulativeDailyUsageBuckets: [WhamTokenUsageBucket]?
    let topInvocations: [WhamTopInvocation]?

    enum CodingKeys: String, CodingKey {
        case lifetimeTokens = "lifetime_tokens"
        case peakDailyTokens = "peak_daily_tokens"
        case longestRunningTurnSeconds = "longest_running_turn_sec"
        case currentStreakDays = "current_streak_days"
        case longestStreakDays = "longest_streak_days"
        case fastModeUsagePercentage = "fast_mode_usage_percentage"
        case mostUsedReasoningEffort = "most_used_reasoning_effort"
        case mostUsedReasoningEffortPercentage = "most_used_reasoning_effort_percentage"
        case totalThreads = "total_threads"
        case totalSkillsUsed = "total_skills_used"
        case uniqueSkillsUsed = "unique_skills_used"
        case workspaceRank = "workspace_rank"
        case workspaceTotalUserCount = "workspace_total_user_count"
        case dailyUsageBuckets = "daily_usage_buckets"
        case weeklyUsageBuckets = "weekly_usage_buckets"
        case cumulativeDailyUsageBuckets = "cumulative_daily_usage_buckets"
        case topInvocations = "top_invocations"
    }

    var codexProfileStats: CodexProfileStats {
        CodexProfileStats(
            lifetimeTokens: lifetimeTokens,
            peakDailyTokens: peakDailyTokens,
            longestRunningTurnSeconds: longestRunningTurnSeconds,
            currentStreakDays: currentStreakDays,
            longestStreakDays: longestStreakDays,
            fastModeUsagePercentage: fastModeUsagePercentage,
            mostUsedReasoningEffort: mostUsedReasoningEffort,
            mostUsedReasoningEffortPercentage: mostUsedReasoningEffortPercentage,
            totalThreads: totalThreads,
            totalSkillsUsed: totalSkillsUsed,
            uniqueSkillsUsed: uniqueSkillsUsed,
            workspaceRank: workspaceRank,
            workspaceTotalUserCount: workspaceTotalUserCount,
            dailyUsageBuckets: dailyUsageBuckets?.map(\.codexBucket) ?? [],
            weeklyUsageBuckets: weeklyUsageBuckets?.map(\.codexBucket) ?? [],
            cumulativeDailyUsageBuckets: cumulativeDailyUsageBuckets?.map(\.codexBucket) ?? [],
            topInvocations: topInvocations?.map(\.codexInvocation) ?? []
        )
    }
}

private struct WhamTokenUsageBucket: Decodable {
    let startDate: String
    let tokens: Int64

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case tokens
    }

    var codexBucket: CodexTokenUsageBucket {
        CodexTokenUsageBucket(startDate: startDate, tokens: tokens)
    }
}

private struct WhamTopInvocation: Decodable {
    let type: String
    let pluginId: String?
    let pluginName: String?
    let skillId: String?
    let skillName: String?
    let usageCount: Int

    enum CodingKeys: String, CodingKey {
        case type
        case pluginId = "plugin_id"
        case pluginName = "plugin_name"
        case skillId = "skill_id"
        case skillName = "skill_name"
        case usageCount = "usage_count"
    }

    var codexInvocation: CodexTopInvocation {
        CodexTopInvocation(
            type: type,
            pluginId: pluginId,
            pluginName: pluginName,
            skillId: skillId,
            skillName: skillName,
            usageCount: usageCount
        )
    }
}
