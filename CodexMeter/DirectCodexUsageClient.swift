import CodexMeterShared
import Foundation

protocol UsageRateLimitFetching: Sendable {
    func fetchRateLimits() async throws -> RateLimitSnapshot
    func fetchUsageSnapshot(forceRefreshResetCredits: Bool) async throws -> UsageSnapshot
}

extension UsageRateLimitFetching {
    func fetchUsageSnapshot() async throws -> UsageSnapshot {
        try await fetchUsageSnapshot(forceRefreshResetCredits: false)
    }

    /// 默认快照实现只读取基础额度；不支持重置卡的测试桩可忽略强制刷新语义。
    func fetchUsageSnapshot(forceRefreshResetCredits: Bool) async throws -> UsageSnapshot {
        let rateLimits = try await fetchRateLimits()
        return UsageSnapshot(fetchedAt: Date(), rateLimits: rateLimits)
    }
}

struct DirectCodexUsageClient: UsageRateLimitFetching {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    static let defaultEndpointURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let defaultProfileEndpointURL = URL(string: "https://chatgpt.com/backend-api/wham/profiles/me")!
    static let defaultResetCreditsEndpointURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!

    private let authFileURL: URL
    private let endpointURL: URL
    private let profileEndpointURL: URL
    private let resetCreditsEndpointURL: URL
    private let timeoutSeconds: TimeInterval
    private let transport: Transport
    private let resetCreditsCache: any ResetCreditsDailyCaching
    private let currentDate: @Sendable () -> Date
    private let showsResetCreditsProvider: @Sendable () -> Bool

    init(
        authFileURL: URL = Self.defaultAuthFileURL(),
        endpointURL: URL = Self.defaultEndpointURL,
        profileEndpointURL: URL = Self.defaultProfileEndpointURL,
        resetCreditsEndpointURL: URL = Self.defaultResetCreditsEndpointURL,
        timeoutSeconds: TimeInterval = 45,
        transport: @escaping Transport = Self.urlSessionTransport,
        resetCreditsCache: any ResetCreditsDailyCaching = UserDefaultsResetCreditsDailyCache(),
        currentDate: @escaping @Sendable () -> Date = { Date() },
        showsResetCreditsProvider: @escaping @Sendable () -> Bool = {
            PopoverDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults).showsResetCredits
        }
    ) {
        self.authFileURL = authFileURL
        self.endpointURL = endpointURL
        self.profileEndpointURL = profileEndpointURL
        self.resetCreditsEndpointURL = resetCreditsEndpointURL
        self.timeoutSeconds = timeoutSeconds
        self.transport = transport
        self.resetCreditsCache = resetCreditsCache
        self.currentDate = currentDate
        self.showsResetCreditsProvider = showsResetCreditsProvider
    }

    func fetchRateLimits() async throws -> RateLimitSnapshot {
        let authContext = try loadAuthContext()
        return try await fetchRateLimits(accessToken: authContext.accessToken)
    }

    /// 刷新完整用量快照；仅在强制刷新时绕过内联重置卡数量去读取独立明细。
    /// 基础用量、认证或解析失败会抛错；资料统计和重置卡明细失败只降级，不阻断主快照。
    func fetchUsageSnapshot(forceRefreshResetCredits: Bool = false) async throws -> UsageSnapshot {
        let authContext = try loadAuthContext()
        async let usageResponse = fetchUsageResponse(accessToken: authContext.accessToken)
        async let profileStats = fetchProfileStatsIfAvailable(accessToken: authContext.accessToken)
        let fetchedUsageResponse = try await usageResponse
        let fetchedRateLimits = fetchedUsageResponse.codexSnapshot
        let inlineResetCredits = fetchedUsageResponse.resetCredits?.resetCreditsSnapshot
        let resetCredits = await fetchResetCreditsIfAvailable(
            accessToken: authContext.accessToken,
            accountID: authContext.accountID,
            forceRefresh: forceRefreshResetCredits,
            fallbackSnapshot: inlineResetCredits
        )
        let account = CodexAccountSnapshot(
            email: authContext.accountEmail,
            planType: authContext.planType ?? fetchedRateLimits.planType
        )

        return UsageSnapshot(
            fetchedAt: Date(),
            rateLimits: fetchedRateLimits,
            account: account.isEmpty ? nil : account,
            profileStats: await profileStats,
            resetCredits: resetCredits
        )
    }

    private func fetchRateLimits(accessToken: String) async throws -> RateLimitSnapshot {
        try await fetchUsageResponse(accessToken: accessToken).codexSnapshot
    }

    /// 请求 Codex 用量接口并保留原始响应；accessToken 必须来自本机 auth.json。
    /// 返回值同时承载基础额度和内联重置卡数量；HTTP、网络或解码失败会转为客户端错误。
    private func fetchUsageResponse(accessToken: String) async throws -> WhamUsageResponse {
        let request = authenticatedRequest(url: endpointURL, accessToken: accessToken)

        do {
            let (data, response) = try await transport(request)
            guard (200..<300).contains(response.statusCode) else {
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw DirectCodexUsageClientError.httpStatus(response.statusCode, message)
            }
            return try JSONDecoder().decode(WhamUsageResponse.self, from: data)
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

    /// 尝试读取额度重置卡明细；fallbackSnapshot 来自用量响应，只含可用张数。
    /// 非强制刷新优先复用当天缓存；独立接口失败时返回 fallbackSnapshot，避免影响基础额度展示。
    private func fetchResetCreditsIfAvailable(
        accessToken: String,
        accountID: String?,
        forceRefresh: Bool,
        fallbackSnapshot: ResetCreditsSnapshot? = nil
    ) async -> ResetCreditsSnapshot? {
        guard showsResetCreditsProvider() else {
            return nil
        }

        let now = currentDate()
        if !forceRefresh, let cachedAttempt = resetCreditsCache.loadAttempt(accountID: accountID, now: now) {
            return cachedAttempt.snapshot ?? fallbackSnapshot
        }
        if !forceRefresh, let fallbackSnapshot {
            return fallbackSnapshot
        }

        do {
            let snapshot = try await fetchResetCredits(accessToken: accessToken, accountID: accountID)
            resetCreditsCache.saveAttempt(.init(snapshot: snapshot), accountID: accountID, now: now)
            return snapshot
        } catch {
            resetCreditsCache.saveAttempt(.init(snapshot: fallbackSnapshot), accountID: accountID, now: now)
            return fallbackSnapshot
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

    /// 请求额度重置卡接口，并把接口返回的可用数量和每张卡生命周期转成共享快照。
    private func fetchResetCredits(accessToken: String, accountID: String?) async throws -> ResetCreditsSnapshot {
        let request = resetCreditsRequest(
            url: resetCreditsEndpointURL,
            accessToken: accessToken,
            accountID: accountID
        )

        do {
            let (data, response) = try await transport(request)
            guard (200..<300).contains(response.statusCode) else {
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw DirectCodexUsageClientError.httpStatus(response.statusCode, message)
            }
            return try JSONDecoder().decode(WhamResetCreditsResponse.self, from: data).resetCreditsSnapshot
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

    /// 构造额度重置卡请求；该接口需要 Codex beta 和账户头，账户缺失时仍保留 token 请求以兼容接口兜底。
    private func resetCreditsRequest(url: URL, accessToken: String, accountID: String?) -> URLRequest {
        var request = authenticatedRequest(url: url, accessToken: accessToken)
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        return request
    }

    /// 从本机 Codex auth.json 读取 API token 和可展示账户摘要；不会把 token 写入快照。
    private func loadAuthContext() throws -> CodexAuthContext {
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            throw DirectCodexUsageClientError.missingAuthFile
        }
        let data = try Data(contentsOf: authFileURL)
        let auth = try JSONDecoder().decode(CodexAuthFile.self, from: data)
        guard let token = auth.tokens?.accessToken, !token.isEmpty else {
            throw DirectCodexUsageClientError.missingAccessToken
        }
        return CodexAuthContext(
            accessToken: token,
            accountID: auth.tokens?.accountID,
            accountEmail: Self.accountEmail(fromIDToken: auth.tokens?.idToken),
            planType: Self.planType(fromIDToken: auth.tokens?.idToken)
        )
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

    /// 从 Codex id_token 的 JWT payload 中读取邮箱，兼容 OpenAI 自定义 profile 命名空间。
    private static func accountEmail(fromIDToken idToken: String?) -> String? {
        let payload = jwtPayload(idToken)
        let profile = payload?["https://api.openai.com/profile"] as? [String: Any]
        return normalizedField((payload?["email"] as? String) ?? (profile?["email"] as? String))?.lowercased()
    }

    /// 从 Codex id_token 的 JWT payload 中读取套餐标识，作为用量接口 plan_type 的补充来源。
    private static func planType(fromIDToken idToken: String?) -> String? {
        let payload = jwtPayload(idToken)
        let auth = payload?["https://api.openai.com/auth"] as? [String: Any]
        return normalizedField((auth?["chatgpt_plan_type"] as? String) ?? (payload?["chatgpt_plan_type"] as? String))
    }

    /// 解码 JWT payload；签名校验由 Codex 登录态负责，这里只读取本地已保存的展示字段。
    private static func jwtPayload(_ idToken: String?) -> [String: Any]? {
        guard let payloadPart = idToken?.split(separator: ".").dropFirst().first else {
            return nil
        }
        var base64 = String(payloadPart)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingLength = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: paddingLength))
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return payload
    }

    /// 归一化 auth payload 字段；空字符串视为未知，避免污染账户摘要。
    private static func normalizedField(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

/// 描述当天额度重置卡接口是否已经尝试过；snapshot 为空表示当天请求失败但仍需限频。
struct ResetCreditsDailyAttempt: Sendable {
    let snapshot: ResetCreditsSnapshot?
}

/// 管理额度重置卡接口的每日请求缓存；只负责节流和快照复用，不参与网络请求和展示格式化。
protocol ResetCreditsDailyCaching: Sendable {
    /// 读取指定账户当天的请求尝试；返回 nil 表示当天还没有请求过，非 nil 表示应跳过网络请求。
    func loadAttempt(accountID: String?, now: Date) -> ResetCreditsDailyAttempt?

    /// 保存指定账户当天的请求尝试；失败请求也会保存空快照，避免刷新循环反复打接口。
    func saveAttempt(_ attempt: ResetCreditsDailyAttempt, accountID: String?, now: Date)
}

/// 使用共享 UserDefaults 持久化重置卡每日请求状态，保证应用重启后同一天也不会重复请求。
final class UserDefaultsResetCreditsDailyCache: ResetCreditsDailyCaching, @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()

    init(
        defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults,
        storageKey: String = "usage.resetCredits.dailyAttempt"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    /// 读取当天缓存；账户或自然日不匹配时视为未请求，避免串用其他登录态的重置卡信息。
    func loadAttempt(accountID: String?, now: Date) -> ResetCreditsDailyAttempt? {
        lock.lock()
        defer { lock.unlock() }

        guard let data = defaults.data(forKey: storageKey),
              let storedAttempt = try? JSONDecoder().decode(StoredResetCreditsDailyAttempt.self, from: data),
              storedAttempt.accountID == normalizedAccountID(accountID),
              storedAttempt.dayKey == dayKey(for: now)
        else {
            return nil
        }
        return ResetCreditsDailyAttempt(snapshot: storedAttempt.snapshot)
    }

    /// 写入当天缓存；编码失败时清理旧值，避免损坏数据让客户端长期误判为已请求。
    func saveAttempt(_ attempt: ResetCreditsDailyAttempt, accountID: String?, now: Date) {
        lock.lock()
        defer { lock.unlock() }

        let storedAttempt = StoredResetCreditsDailyAttempt(
            accountID: normalizedAccountID(accountID),
            dayKey: dayKey(for: now),
            snapshot: attempt.snapshot
        )
        guard let data = try? JSONEncoder().encode(storedAttempt) else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    /// 把账户标识中的空白值统一成 nil，保证未登录账户和空字符串使用同一缓存分支。
    private func normalizedAccountID(_ accountID: String?) -> String? {
        guard let accountID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines), !accountID.isEmpty else {
            return nil
        }
        return accountID
    }

    /// 按用户本地自然日生成缓存键；需求是每天请求一次，跨时区时跟随系统当前日历语义。
    private func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return [
            components.year.map(String.init) ?? "0000",
            String(format: "%02d", components.month ?? 0),
            String(format: "%02d", components.day ?? 0)
        ].joined(separator: "-")
    }
}

/// UserDefaults 中保存的重置卡每日请求状态；和运行时协议拆开，便于后续迁移存储格式。
private struct StoredResetCreditsDailyAttempt: Codable {
    let accountID: String?
    let dayKey: String
    let snapshot: ResetCreditsSnapshot?
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
        let accountID: String?
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountID = "account_id"
            case idToken = "id_token"
        }
    }
}

/// auth.json 的安全读取结果；只把 access token 留在内存里，展示字段才会进入缓存。
private struct CodexAuthContext {
    let accessToken: String
    let accountID: String?
    let accountEmail: String?
    let planType: String?
}

private struct WhamUsageResponse: Decodable {
    let planType: String?
    let rateLimit: WhamRateLimit?
    let additionalRateLimits: [WhamAdditionalRateLimit]?
    let credits: WhamCredits?
    let rateLimitReachedType: WhamRateLimitReachedType?
    let resetCredits: WhamResetCreditsResponse?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
        case credits
        case rateLimitReachedType = "rate_limit_reached_type"
        case resetCredits = "rate_limit_reset_credits"
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
            rateLimitReachedType: rateLimitReachedType?.value
        )
    }
}

/// 兼容限制命中原因的新旧响应形状；旧接口可能给字符串，新接口会给带 type/details 的对象。
private struct WhamRateLimitReachedType: Decodable {
    let value: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case details
    }

    /// 从字符串或对象中提取稳定的限制类型；未知形状视为缺失，不能影响基础用量解析。
    init(from decoder: Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        if let stringValue = try? singleValueContainer.decode(String.self) {
            self.value = Self.normalized(stringValue)
            return
        }
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            let type = try container.decodeFlexibleStringIfPresent(forKey: .type)
            let details = try container.decodeFlexibleStringIfPresent(forKey: .details)
            self.value = Self.normalized(type ?? details)
            return
        }
        self.value = nil
    }

    /// 归一化后端返回的展示字段；空白值不进入共享快照。
    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct WhamRateLimit: Decodable {
    let primaryWindow: WhamWindow?
    let secondaryWindow: WhamWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    /// 兼容整个 rate_limit 被压成裸 0 的响应；此时两个窗口均视为缺失。
    init(from decoder: Decoder) throws {
        if let _ = try? decoder.singleValueContainer().decode(Double.self) {
            self.primaryWindow = nil
            self.secondaryWindow = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.primaryWindow = try container.decodeIfPresent(WhamWindow.self, forKey: .primaryWindow)
        self.secondaryWindow = try container.decodeIfPresent(WhamWindow.self, forKey: .secondaryWindow)
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

    /// 宽容解析 Codex 用量窗口；接口在归零边界可能省略、字符串化数值，或把整个窗口压成裸 0。
    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer().decode(Double.self) {
            self.usedPercent = singleValue
            self.limitWindowSeconds = nil
            self.resetAfterSeconds = nil
            self.resetAt = nil
            return
        }
        if let singleValue = try? decoder.singleValueContainer().decode(String.self),
           let usedPercent = Double(singleValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.usedPercent = usedPercent
            self.limitWindowSeconds = nil
            self.resetAfterSeconds = nil
            self.resetAt = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.usedPercent = try container.decodeFlexibleDoubleIfPresent(forKey: .usedPercent) ?? 0
        self.limitWindowSeconds = try container.decodeFlexibleIntIfPresent(forKey: .limitWindowSeconds)
        self.resetAfterSeconds = try container.decodeFlexibleIntIfPresent(forKey: .resetAfterSeconds)
        self.resetAt = try container.decodeFlexibleIntIfPresent(forKey: .resetAt)
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

private extension KeyedDecodingContainer {
    /// 解码可能由数字或字符串承载的小数字段；空字符串视为缺失，保留上层兜底语义。
    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let doubleValue = try? decode(Double.self, forKey: key) {
            return doubleValue
        }
        if let stringValue = (try? decode(String.self, forKey: key))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stringValue.isEmpty {
            return Double(stringValue)
        }
        return nil
    }

    /// 解码可能由数字或字符串承载的整数字段；无法转成整数时交给调用方当作缺失字段。
    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let intValue = try? decode(Int.self, forKey: key) {
            return intValue
        }
        if let doubleValue = try? decode(Double.self, forKey: key) {
            return Int(doubleValue)
        }
        if let stringValue = (try? decode(String.self, forKey: key))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stringValue.isEmpty {
            return Int(stringValue) ?? Double(stringValue).map(Int.init)
        }
        return nil
    }

    /// 解码可能由字符串或数字承载的展示字段；数字 0 保持为 "0"，避免归零响应打断整体解析。
    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let stringValue = try? decode(String.self, forKey: key) {
            return stringValue
        }
        if let intValue = try? decode(Int.self, forKey: key) {
            return String(intValue)
        }
        if let doubleValue = try? decode(Double.self, forKey: key) {
            return doubleValue.rounded() == doubleValue ? String(Int(doubleValue)) : String(doubleValue)
        }
        return nil
    }

    /// 解码接口里可能用 ISO8601 字符串或 Unix 时间戳表示的时间字段。
    func decodeFlexibleDateIfPresent(forKey key: Key) throws -> Date? {
        if let intValue = try? decode(Int.self, forKey: key) {
            return Date(timeIntervalSince1970: TimeInterval(intValue))
        }
        if let doubleValue = try? decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: doubleValue)
        }
        guard let stringValue = (try? decode(String.self, forKey: key))?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !stringValue.isEmpty
        else {
            return nil
        }
        if let doubleValue = Double(stringValue) {
            return Date(timeIntervalSince1970: doubleValue)
        }
        return Self.codexISO8601DateFormatter(includesFractionalSeconds: true).date(from: stringValue)
            ?? Self.codexISO8601DateFormatter(includesFractionalSeconds: false).date(from: stringValue)
    }

    /// Codex 后端时间字段使用 UTC ISO8601，带小数秒和不带小数秒都需要兼容。
    private static func codexISO8601DateFormatter(includesFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = includesFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
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

    /// 兼容余额为数字 0 或整个 credits 被压成裸 0 的响应。
    init(from decoder: Decoder) throws {
        if let _ = try? decoder.singleValueContainer().decode(Double.self) {
            self.hasCredits = false
            self.unlimited = false
            self.balance = "0"
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hasCredits = try container.decode(Bool.self, forKey: .hasCredits)
        self.unlimited = try container.decode(Bool.self, forKey: .unlimited)
        self.balance = try container.decodeFlexibleStringIfPresent(forKey: .balance)
    }

    var creditsSnapshot: CreditsSnapshot {
        CreditsSnapshot(hasCredits: hasCredits, unlimited: unlimited, balance: balance)
    }
}

private struct WhamResetCreditsResponse: Decodable {
    let availableCount: Int
    let credits: [WhamResetCredit]?

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
        case credits
    }

    /// 宽容解析可用张数；如果接口临时省略数量，则用明细数量兜底。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.credits = try container.decodeIfPresent([WhamResetCredit].self, forKey: .credits)
        self.availableCount = try container.decodeFlexibleIntIfPresent(forKey: .availableCount) ?? credits?.count ?? 0
    }

    var resetCreditsSnapshot: ResetCreditsSnapshot {
        ResetCreditsSnapshot(
            availableCount: availableCount,
            credits: credits?.map(\.resetCreditSnapshot) ?? []
        )
    }
}

private struct WhamResetCredit: Decodable {
    let grantedAt: Date?
    let expiresAt: Date?
    let status: String

    enum CodingKeys: String, CodingKey {
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
        case status
    }

    /// 宽容解析单张重置卡；状态缺失时显示为未知，时间缺失时仍保留卡片行。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.grantedAt = try container.decodeFlexibleDateIfPresent(forKey: .grantedAt)
        self.expiresAt = try container.decodeFlexibleDateIfPresent(forKey: .expiresAt)
        self.status = (try container.decodeIfPresent(String.self, forKey: .status)) ?? "unknown"
    }

    var resetCreditSnapshot: ResetCreditSnapshot {
        ResetCreditSnapshot(grantedAt: grantedAt, expiresAt: expiresAt, status: status)
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

/// 定义 Gemini Models 的独立读取能力；失败时不影响 Codex 用量客户端。
protocol GeminiModelsUsageFetching: Sendable {
    /// 读取本地 Antigravity 配额，必要时使用已保存的 Google OAuth 凭据兜底。
    func fetchGeminiModels() async throws -> GeminiModelsSnapshot
}

/// 读取 Antigravity 本地语言服务和 Google OAuth 配额；协议字段来自 CodexBar 的公开实现路径。
struct AntigravityGeminiModelsClient: GeminiModelsUsageFetching, Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    typealias ProcessList = @Sendable () throws -> String
    typealias ListeningPorts = @Sendable (Int) throws -> [Int]

    private let timeoutSeconds: TimeInterval
    private let transport: Transport
    private let processList: ProcessList
    private let listeningPorts: ListeningPorts
    private let homeDirectory: URL
    private let environment: [String: String]
    private let currentDate: @Sendable () -> Date

    init(
        timeoutSeconds: TimeInterval = 8,
        transport: @escaping Transport = Self.urlSessionTransport,
        processList: @escaping ProcessList = Self.defaultProcessList,
        listeningPorts: @escaping ListeningPorts = Self.defaultListeningPorts,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.transport = transport
        self.processList = processList
        self.listeningPorts = listeningPorts
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.currentDate = currentDate
    }

    /// 优先探测正在运行的 Antigravity；本地服务不可用时再读取保存的 OAuth 文件。
    func fetchGeminiModels() async throws -> GeminiModelsSnapshot {
        do {
            return try await fetchLocalSnapshot()
        } catch let localError {
            do {
                return try await fetchOAuthSnapshot()
            } catch let oauthError as GeminiModelsUsageClientError {
                let action: String
                if case .credentialsUnavailable = oauthError {
                    action = "请在终端运行 gemini 完成认证。"
                } else {
                    action = "请检查 Gemini 的登录状态和 OAuth 配置。"
                }
                throw GeminiModelsUsageClientError.notAvailable(
                    "未读取到 Antigravity 配额（"
                        + localError.localizedDescription
                        + "），也没有可用的 Google OAuth 兜底。"
                        + action
                )
            } catch {
                throw GeminiModelsUsageClientError.notAvailable(
                    "未读取到 Antigravity 配额（"
                        + localError.localizedDescription
                        + "），也没有可用的 Google OAuth 兜底。请检查 Gemini 的登录状态和 OAuth 配置。"
                )
            }
        }
    }

    /// 遍历 Antigravity 语言服务进程和监听端口，避免依赖固定端口或 UI 抓取。
    private func fetchLocalSnapshot() async throws -> GeminiModelsSnapshot {
        let processes: [LocalAntigravityProcess]
        do {
            processes = try Self.parseProcessList(processList())
        } catch let error as GeminiModelsUsageClientError {
            throw error
        } catch {
            throw GeminiModelsUsageClientError.notAvailable("无法检测 Antigravity 语言服务。")
        }
        guard !processes.isEmpty else {
            throw GeminiModelsUsageClientError.notAvailable("未检测到正在运行的 Antigravity。")
        }

        var lastError: Error?
        for process in processes {
            let ports: [Int]
            do {
                ports = try listeningPorts(process.pid)
            } catch {
                lastError = error
                continue
            }
            for endpoint in Self.endpoints(for: process, ports: ports) {
                do {
                    return try await fetchLocalSnapshot(endpoint: endpoint)
                } catch {
                    lastError = error
                }
            }
        }
        throw lastError ?? GeminiModelsUsageClientError.notAvailable("Antigravity 尚未准备好配额服务。")
    }

    /// 按 CodexBar 的优先级尝试额度摘要、用户状态和模型配置三个本地接口。
    private func fetchLocalSnapshot(endpoint: LocalAntigravityEndpoint) async throws -> GeminiModelsSnapshot {
        _ = try? await sendLocalRequest(
            path: Self.getUnleashPath,
            body: Self.unleashBody(),
            endpoint: endpoint
        )

        if let summaryData = try? await sendLocalRequest(
            path: Self.quotaSummaryPath,
            body: ["forceRefresh": true],
            endpoint: endpoint
        ), let summary = try? AntigravityGeminiResponseParser.parseQuotaSummary(
            summaryData,
            fetchedAt: currentDate(),
            source: .antigravityLocal
        ), summary.hasUsableQuota {
            let identity: (email: String?, plan: String?)?
            if let statusData = try? await sendLocalRequest(
                path: Self.getUserStatusPath,
                body: Self.defaultRequestBody(),
                endpoint: endpoint
            ) {
                identity = AntigravityGeminiResponseParser.parseIdentity(statusData)
            } else {
                identity = nil
            }
            return summary.withIdentity(identity)
        }

        if let statusData = try? await sendLocalRequest(
            path: Self.getUserStatusPath,
                body: Self.defaultRequestBody(),
            endpoint: endpoint
        ), let status = try? AntigravityGeminiResponseParser.parseUserStatus(
            statusData,
            fetchedAt: currentDate(),
            source: .antigravityLocal
        ), status.hasUsableQuota {
            return status
        }

        let modelData = try await sendLocalRequest(
            path: Self.commandModelConfigPath,
            body: Self.defaultRequestBody(),
            endpoint: endpoint
        )
        return try AntigravityGeminiResponseParser.parseUserStatus(
            modelData,
            fetchedAt: currentDate(),
            source: .antigravityLocal
        )
    }

    /// 从 CodexBar 兼容路径加载 OAuth；只读取现有 token，不把认证材料写入用量快照。
    private func fetchOAuthSnapshot() async throws -> GeminiModelsSnapshot {
        let credentials = try loadOAuthCredentials()
        guard let accessToken = credentials.accessToken, !accessToken.isEmpty else {
            throw GeminiModelsUsageClientError.credentialsUnavailable
        }

        let codeAssistData = try await sendOAuthRequest(
            path: Self.loadCodeAssistPath,
            accessToken: accessToken,
            body: ["metadata": [
                "ideType": "ANTIGRAVITY",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI"
            ]]
        )
        let projectID = credentials.projectID
            ?? AntigravityGeminiResponseParser.string(
                in: codeAssistData,
                keys: ["cloudaicompanionProject", "projectId", "project_id"]
            )

        let modelsData = try await sendOAuthRequest(
            path: Self.fetchAvailableModelsPath,
            accessToken: accessToken,
            body: projectID.map { ["project": $0] } ?? [:]
        )
        let groups = try AntigravityGeminiResponseParser.parseRemoteModels(
            modelsData,
            fetchedAt: currentDate(),
            source: .googleOAuth
        )
        guard groups.hasUsableQuota else {
            throw GeminiModelsUsageClientError.invalidResponse("Google OAuth 未返回可用 Antigravity 配额。")
        }

        let planName = AntigravityGeminiResponseParser.string(
            in: codeAssistData,
            keys: ["planType", "planName", "preferredName", "displayName"]
        )
        return GeminiModelsSnapshot(
            fetchedAt: currentDate(),
            source: .googleOAuth,
            accountEmail: credentials.email,
            planName: planName,
            groups: groups.groups
        )
    }

    /// 发送本地语言服务请求，并只接受成功的 HTTP 响应。
    private func sendLocalRequest(
        path: String,
        body: [String: Any],
        endpoint: LocalAntigravityEndpoint
    ) async throws -> Data {
        let endpointString = endpoint.scheme + "://127.0.0.1:" + String(endpoint.port) + path
        guard let url = URL(string: endpointString) else {
            throw GeminiModelsUsageClientError.invalidResponse("本地服务地址无效。")
        }
        var request = try Self.makeJSONRequest(url: url, body: body, timeout: timeoutSeconds)
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        if endpoint.requiresCSRFToken {
            request.setValue(endpoint.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        }
        return try await send(request)
    }

    /// 发送 Cloud Code OAuth 请求；Bearer token 只存在于内存中的请求头。
    private func sendOAuthRequest(
        path: String,
        accessToken: String,
        body: [String: Any]
    ) async throws -> Data {
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:\(path)") else {
            throw GeminiModelsUsageClientError.invalidResponse("Google 配置地址无效。")
        }
        var request = try Self.makeJSONRequest(url: url, body: body, timeout: timeoutSeconds)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
        return try await send(request)
    }

    /// 统一处理传输、HTTP 状态和响应体，避免本地和远端分支产生不同错误语义。
    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await transport(request)
            guard (200..<300).contains(response.statusCode) else {
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(240)
                throw GeminiModelsUsageClientError.httpStatus(response.statusCode, String(message ?? ""))
            }
            return data
        } catch let error as GeminiModelsUsageClientError {
            throw error
        } catch {
            throw GeminiModelsUsageClientError.network(error.localizedDescription)
        }
    }

    /// 读取兼容 CodexBar 的环境变量和本地 OAuth 文件，按优先级返回第一个有效文件。
    private func loadOAuthCredentials() throws -> AntigravityOAuthCredentials {
        if let value = environment["ANTIGRAVITY_OAUTH_CREDENTIALS_JSON"],
           let data = value.data(using: .utf8),
           let credentials = try? JSONDecoder().decode(AntigravityOAuthCredentials.self, from: data) {
            return credentials
        }

        let urls = [
            homeDirectory
                .appendingPathComponent(".codexbar", isDirectory: true)
                .appendingPathComponent("antigravity", isDirectory: true)
                .appendingPathComponent("oauth_creds.json"),
            homeDirectory
                .appendingPathComponent(".gemini", isDirectory: true)
                .appendingPathComponent("oauth_creds.json")
        ]
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AntigravityOAuthCredentials.self, from: data)
        }
        throw GeminiModelsUsageClientError.credentialsUnavailable
    }

    /// 构造 JSON POST 请求；请求体由调用方传入并在发送前完成序列化。
    private static func makeJSONRequest(url: URL, body: [String: Any], timeout: TimeInterval) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    /// 通过带本地主机证书例外的 URLSession 访问 Antigravity 语言服务。
    private static func urlSessionTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval
        configuration.waitsForConnectivity = false
        let delegate = AntigravityLocalhostSessionDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiModelsUsageClientError.invalidResponse("服务响应不是 HTTP。")
        }
        return (data, httpResponse)
    }

    /// 读取进程列表；仅把 PID 和命令行交给解析器，不输出命令行中的认证参数。
    private static func defaultProcessList() throws -> String {
        try runProcess(binary: "/bin/ps", arguments: ["-ax", "-o", "pid=,command="])
    }

    /// 使用 lsof 找到指定 Antigravity 进程监听的 TCP 端口。
    private static func defaultListeningPorts(pid: Int) throws -> [Int] {
        let binary = ["/usr/sbin/lsof", "/usr/bin/lsof"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        guard let binary else {
            throw GeminiModelsUsageClientError.notAvailable("系统缺少 lsof，无法探测 Antigravity 端口。")
        }
        let output = try runProcess(
            binary: binary,
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", String(pid)]
        )
        let pattern = try NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#)
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        var ports = Set<Int>()
        pattern.enumerateMatches(in: output, range: range) { match, _, _ in
            guard let match,
                  let portRange = Range(match.range(at: 1), in: output),
                  let port = Int(output[portRange]) else { return }
            ports.insert(port)
        }
        guard !ports.isEmpty else {
            throw GeminiModelsUsageClientError.notAvailable("Antigravity 尚未暴露语言服务端口。")
        }
        return ports.sorted()
    }

    /// 执行短生命周期的系统命令；这里只用于 ps/lsof，失败时不把 stderr 写入快照。
    private static func runProcess(binary: String, arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: error, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw GeminiModelsUsageClientError.notAvailable(message ?? "系统进程执行失败。")
        }
        return String(data: output, encoding: .utf8) ?? ""
    }

    private static let getUserStatusPath = "/exa.language_server_pb.LanguageServerService/GetUserStatus"
    private static let commandModelConfigPath = "/exa.language_server_pb.LanguageServerService/GetCommandModelConfigs"
    private static let quotaSummaryPath = "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"
    private static let getUnleashPath = "/exa.language_server_pb.LanguageServerService/GetUnleashData"
    private static let loadCodeAssistPath = "loadCodeAssist"
    private static let fetchAvailableModelsPath = "fetchAvailableModels"

    private static func defaultRequestBody() -> [String: Any] {
        [
            "metadata": [
                "ideName": "antigravity",
                "extensionName": "antigravity",
                "ideVersion": "unknown",
                "locale": "en"
            ]
        ]
    }

    private static func unleashBody() -> [String: Any] {
        [
            "context": [
                "properties": [
                    "devMode": "false",
                    "extensionVersion": "unknown",
                    "hasAnthropicModelAccess": "true",
                    "ide": "antigravity",
                    "ideVersion": "unknown",
                    "installationId": "codexmeter",
                    "language": "UNSPECIFIED",
                    "os": "macos",
                    "requestedModelId": "MODEL_UNSPECIFIED"
                ]
            ]
        ]
    }
}

/// 描述本地语言服务进程启动参数；CSRF token 只在内存中用于本次回环请求。
private struct LocalAntigravityProcess: Sendable {
    let pid: Int
    let csrfToken: String
    let extensionPort: Int?
    let extensionServerCSRFToken: String?
}

/// 描述一次本地 HTTP/HTTPS 请求目标及其认证方式。
private struct LocalAntigravityEndpoint: Hashable, Sendable {
    let scheme: String
    let port: Int
    let csrfToken: String
    let requiresCSRFToken: Bool
}

/// 提供 Antigravity 本地和远端请求的用户可读错误，避免吞掉设置页可诊断信息。
enum GeminiModelsUsageClientError: LocalizedError, Equatable {
    case credentialsUnavailable
    case notAvailable(String)
    case httpStatus(Int, String)
    case invalidResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .credentialsUnavailable:
            return "没有可用的 Google OAuth 登录信息。"
        case .notAvailable(let message):
            return message
        case .httpStatus(let statusCode, let message):
            return message.isEmpty
                ? "Antigravity 配额接口返回 " + String(statusCode) + "。"
                : "Antigravity 配额接口返回 " + String(statusCode) + "：" + message
        case .invalidResponse(let message):
            return "Antigravity 配额响应格式不可识别：" + message
        case .network(let message):
            return "读取 Antigravity 配额网络失败：" + message
        }
    }
}

/// 解析 CodexBar 使用的 Antigravity 配额摘要、用户状态和 Cloud Code 模型响应。
enum AntigravityGeminiResponseParser {
    /// 解析 RetrieveUserQuotaSummary，并兼容 response、summary 和根节点三种包装层级。
    static func parseQuotaSummary(
        _ data: Data,
        fetchedAt: Date,
        source: GeminiModelsUsageSource
    ) throws -> GeminiModelsSnapshot {
        let root = try jsonDictionary(data)
        let payload = payloadDictionary(root)
        let groups = parseGroups(payload["groups"], prefix: "summary")
        guard !groups.isEmpty else {
            throw GeminiModelsUsageClientError.invalidResponse("缺少 quota groups。")
        }
        return GeminiModelsSnapshot(fetchedAt: fetchedAt, source: source, groups: groups)
    }

    /// 解析 GetUserStatus 或 GetCommandModelConfigs 的模型级 quotaInfo。
    static func parseUserStatus(
        _ data: Data,
        fetchedAt: Date,
        source: GeminiModelsUsageSource
    ) throws -> GeminiModelsSnapshot {
        let root = try jsonDictionary(data)
        let status = dictionary(named: "userStatus", in: root) ?? root
        let configs = (dictionary(named: "cascadeModelConfigData", in: status)?["clientModelConfigs"] as? [Any])
            ?? (root["clientModelConfigs"] as? [Any])
            ?? []
        let groups = parseModelConfigs(configs)
        guard !groups.isEmpty else {
            throw GeminiModelsUsageClientError.invalidResponse("缺少 clientModelConfigs。")
        }
        let identity = parseIdentity(root)
        return GeminiModelsSnapshot(
            fetchedAt: fetchedAt,
            source: source,
            accountEmail: identity.email,
            planName: identity.plan,
            groups: groups
        )
    }

    /// 解析远端 fetchAvailableModels；若服务只返回 buckets，则由模型桶分组逻辑兼容。
    static func parseRemoteModels(
        _ data: Data,
        fetchedAt: Date,
        source: GeminiModelsUsageSource
    ) throws -> GeminiModelsSnapshot {
        let root = try jsonDictionary(data)
        let payload = payloadDictionary(root)
        if let models = payload["models"] as? [String: Any] {
            let windows = models.compactMap { modelID, value -> GeminiQuotaWindow? in
                guard let model = value as? [String: Any] else {
                    return nil
                }
                let quota = dictionary(named: "quotaInfo", in: model) ?? model
                return quotaWindow(
                    id: modelID,
                    title: string(in: model, keys: ["displayName", "label"]) ?? modelID,
                    payload: quota
                )
            }
            let groups = modelGroups(windows: windows)
            if !groups.isEmpty {
                return GeminiModelsSnapshot(fetchedAt: fetchedAt, source: source, groups: groups)
            }
        }

        let buckets = (payload["buckets"] as? [Any] ?? []).compactMap { value -> GeminiQuotaWindow? in
            guard let bucket = value as? [String: Any],
                  let modelID = string(in: bucket, keys: ["modelId", "model_id", "id"]) else {
                return nil
            }
            return quotaWindow(id: modelID, title: modelID, payload: bucket)
        }
        let groups = modelGroups(windows: buckets)
        guard !groups.isEmpty else {
            throw GeminiModelsUsageClientError.invalidResponse("远端未返回模型 quotaInfo。")
        }
        return GeminiModelsSnapshot(fetchedAt: fetchedAt, source: source, groups: groups)
    }

    /// 从用户状态响应中提取账户邮箱和套餐名；身份缺失不影响额度解析。
    static func parseIdentity(_ data: Data) -> (email: String?, plan: String?) {
        guard let root = try? jsonDictionary(data) else {
            return (nil, nil)
        }
        return parseIdentity(root)
    }

    /// 在任意 JSON 字典中按候选字段读取非空字符串，兼容 snake_case 和 camelCase。
    static func string(in data: Data, keys: [String]) -> String? {
        guard let root = try? jsonDictionary(data) else {
            return nil
        }
        return string(in: root, keys: keys)
    }

    /// 将 Gemini 配额快照补上用户状态中的账户信息。
    static func withIdentity(
        _ snapshot: GeminiModelsSnapshot,
        identity: (email: String?, plan: String?)?
    ) -> GeminiModelsSnapshot {
        guard let identity else {
            return snapshot
        }
        return GeminiModelsSnapshot(
            fetchedAt: snapshot.fetchedAt,
            source: snapshot.source,
            accountEmail: identity.email,
            planName: identity.plan,
            groups: snapshot.groups
        )
    }

    /// 读取任意 JSON 的字典根节点，统一转成可宽容解析的 Foundation 值。
    private static func jsonDictionary(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiModelsUsageClientError.invalidResponse("根节点不是 JSON 对象。")
        }
        return root
    }

    /// 选择接口响应中的实际 payload，兼容内部 API 的不同包装字段。
    private static func payloadDictionary(_ root: [String: Any]) -> [String: Any] {
        for key in ["response", "summary", "data"] {
            if let value = root[key] as? [String: Any] {
                if value["groups"] != nil || value["models"] != nil || value["buckets"] != nil {
                    return value
                }
            }
        }
        return root
    }

    /// 解析 quota summary 的分组和窗口，并忽略没有 bucket 的空分组。
    private static func parseGroups(_ value: Any?, prefix: String) -> [GeminiQuotaGroup] {
        guard let values = value as? [Any] else {
            return []
        }
        return values.enumerated().compactMap { index, value in
            guard let group = value as? [String: Any] else {
                return nil
            }
            let title = string(in: group, keys: ["displayName", "name", "title"]) ?? "Gemini Models"
            let buckets = (group["buckets"] as? [Any] ?? group["windows"] as? [Any] ?? [])
                .enumerated()
                .compactMap { bucketIndex, value -> GeminiQuotaWindow? in
                    guard let bucket = value as? [String: Any],
                          let bucketID = string(in: bucket, keys: ["bucketId", "bucket_id", "id"]) else {
                        return nil
                    }
                    return quotaWindow(
                        id: bucketID,
                        title: string(in: bucket, keys: ["displayName", "name", "title"]) ?? bucketID,
                        payload: bucket,
                        fallbackIndex: bucketIndex
                    )
                }
            guard !buckets.isEmpty else {
                return nil
            }
            return GeminiQuotaGroup(
                id: string(in: group, keys: ["id", "groupId", "group_id"]) ?? "\(prefix)-\(index)",
                title: title,
                description: string(in: group, keys: ["description"]),
                windows: buckets
            )
        }
    }

    /// 把模型级窗口按 Gemini 与 Claude/GPT 族分组，保持旧接口也能显示在独立卡片中。
    private static func modelGroups(windows: [GeminiQuotaWindow]) -> [GeminiQuotaGroup] {
        let grouped = Dictionary(grouping: windows) { window in
            let value = window.title.lowercased()
            return value.contains("claude") || value.contains("gpt") ? "claude" : "gemini"
        }
        return [
            grouped["gemini"].map {
                GeminiQuotaGroup(id: "gemini-models", title: "Gemini Models", windows: $0)
            },
            grouped["claude"].map {
                GeminiQuotaGroup(id: "claude-gpt-models", title: "Claude and GPT models", windows: $0)
            }
        ].compactMap { $0 }
    }

    /// 解析 Antigravity 用户状态中的 clientModelConfigs。
    private static func parseModelConfigs(_ configs: [Any]) -> [GeminiQuotaGroup] {
        let windows = configs.compactMap { value -> GeminiQuotaWindow? in
            guard let config = value as? [String: Any],
                  let quota = dictionary(named: "quotaInfo", in: config) else {
                return nil
            }
            let modelID = string(in: config, keys: ["modelId", "model_id"])
                ?? string(in: dictionary(named: "modelOrAlias", in: config) ?? [:], keys: ["model"])
                ?? UUID().uuidString
            return quotaWindow(
                id: modelID,
                title: string(in: config, keys: ["label", "displayName", "name"]) ?? modelID,
                payload: quota
            )
        }
        return modelGroups(windows: windows)
    }

    /// 把单个 quotaInfo 转成共享窗口，兼容嵌套 remaining 和多种时间格式。
    private static func quotaWindow(
        id: String,
        title: String,
        payload: [String: Any],
        fallbackIndex: Int = 0
    ) -> GeminiQuotaWindow {
        let remainingPayload = dictionary(named: "remaining", in: payload)
        let remaining = number(in: payload, keys: ["remainingFraction", "remaining_fraction"])
            ?? remainingPayload.flatMap { number(in: $0, keys: ["remainingFraction", "remaining_fraction", "value"]) }
        let bucketID = id.isEmpty ? "quota-" + String(fallbackIndex) : id
        return GeminiQuotaWindow(
            bucketId: bucketID,
            title: title,
            remainingFraction: remaining,
            resetsAt: date(in: payload, keys: ["resetTime", "reset_time"]),
            resetDescription: string(in: payload, keys: ["resetDescription", "description"]),
            disabled: bool(in: payload, keys: ["disabled", "isDisabled"]) ?? false
        )
    }

    /// 从字典树中查找名为 key 的第一个对象。
    private static func dictionary(named key: String, in value: Any) -> [String: Any]? {
        if let object = value as? [String: Any] {
            if let result = object[key] as? [String: Any] {
                return result
            }
            for child in object.values {
                if let result = dictionary(named: key, in: child) {
                    return result
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let result = dictionary(named: key, in: child) {
                    return result
                }
            }
        }
        return nil
    }

    /// 读取用户身份字段，优先使用实际 tier 名称再回退 planInfo。
    private static func parseIdentity(_ root: [String: Any]) -> (email: String?, plan: String?) {
        let status = dictionary(named: "userStatus", in: root) ?? root
        let email = string(in: status, keys: ["email", "accountEmail", "account_email"])
        let userTier = dictionary(named: "userTier", in: status)
        let planInfo = dictionary(named: "planInfo", in: status)
        let plan = string(in: userTier ?? [:], keys: ["preferredName", "name", "displayName"])
            ?? string(in: planInfo ?? [:], keys: ["preferredName", "displayName", "planName", "productName"])
            ?? string(in: status, keys: ["planName", "planType", "plan"])
        return (email, plan)
    }

    /// 读取字典中的非空字符串，避免把 API 的空值直接展示给用户。
    private static func string(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        for value in dictionary.values {
            if let nested = value as? [String: Any], let result = string(in: nested, keys: keys) {
                return result
            }
        }
        return nil
    }

    /// 读取 JSON 数字；NSNumber 兼容 API 返回的整数和小数。
    private static func number(in dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dictionary[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = dictionary[key] as? String, let number = Double(value) {
                return number
            }
        }
        return nil
    }

    /// 读取 JSON 布尔值。
    private static func bool(in dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }
        }
        return nil
    }

    /// 解析 ISO8601、秒时间戳和 protobuf timestamp 对象。
    private static func date(in dictionary: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let number = value as? NSNumber {
                let seconds = number.doubleValue > 100_000_000_000
                    ? number.doubleValue / 1_000
                    : number.doubleValue
                return Date(timeIntervalSince1970: seconds)
            }
            if let value = value as? String {
                if let seconds = Double(value) {
                    return Date(timeIntervalSince1970: seconds > 100_000_000_000 ? seconds / 1_000 : seconds)
                }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = formatter.date(from: value) {
                    return parsed
                }
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: value)
            }
            if let timestamp = value as? [String: Any],
               let seconds = number(in: timestamp, keys: ["seconds", "value"]) {
                return Date(timeIntervalSince1970: seconds)
            }
        }
        return nil
    }
}

private extension GeminiModelsSnapshot {
    /// 以新身份创建快照；仅供本地摘要请求合并 GetUserStatus 结果。
    func withIdentity(_ identity: (email: String?, plan: String?)?) -> GeminiModelsSnapshot {
        AntigravityGeminiResponseParser.withIdentity(self, identity: identity)
    }
}

/// 兼容 CodexBar 的 Antigravity OAuth 文件字段；支持 snake_case 和 camelCase。
private struct AntigravityOAuthCredentials: Decodable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let expiryDateMilliseconds: Double?
    let email: String?
    let projectID: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken)
            ?? container.decodeIfPresent(String.self, forKey: .accessTokenCamel)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
            ?? container.decodeIfPresent(String.self, forKey: .refreshTokenCamel)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
            ?? container.decodeIfPresent(String.self, forKey: .projectIDCamel)
        if let milliseconds = try container.decodeIfPresent(Double.self, forKey: .expiryDate) {
            expiryDateMilliseconds = milliseconds
        } else if let milliseconds = try container.decodeIfPresent(Int.self, forKey: .expiryDate) {
            expiryDateMilliseconds = Double(milliseconds)
        } else if let seconds = try container.decodeIfPresent(Double.self, forKey: .expiresAt) {
            expiryDateMilliseconds = seconds < 100_000_000_000 ? seconds * 1_000 : seconds
        } else if let seconds = try container.decodeIfPresent(Int.self, forKey: .expiresAt) {
            let value = Double(seconds)
            expiryDateMilliseconds = value < 100_000_000_000 ? value * 1_000 : value
        } else {
            expiryDateMilliseconds = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accessTokenCamel = "accessToken"
        case refreshToken = "refresh_token"
        case refreshTokenCamel = "refreshToken"
        case expiryDate = "expiry_date"
        case expiresAt
        case email
        case projectID = "project_id"
        case projectIDCamel = "projectId"
    }
}

/// 只接受本地主机的自签名证书，远端 HTTPS 仍交给系统默认信任链处理。
private final class AntigravityLocalhostSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    /// 处理 session 级 TLS challenge；仅限 127.0.0.1/localhost。
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(challengeResult(challenge).0, challengeResult(challenge).1)
    }

    /// 处理 task 级 TLS challenge；仅限 127.0.0.1/localhost。
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(challengeResult(challenge).0, challengeResult(challenge).1)
    }

    /// 返回本地主机证书例外结果；其他主机使用系统默认处理。
    private func challengeResult(_ challenge: URLAuthenticationChallenge) -> (
        URLSession.AuthChallengeDisposition,
        URLCredential?
    ) {
        let protectionSpace = challenge.protectionSpace
        guard protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              ["127.0.0.1", "localhost"].contains(protectionSpace.host.lowercased()),
              let trust = protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}

private extension AntigravityGeminiModelsClient {
    /// 从 ps 输出筛选 Antigravity language_server，并提取本次请求需要的启动参数。
    static func parseProcessList(_ output: String) throws -> [LocalAntigravityProcess] {
        var processes: [LocalAntigravityProcess] = []
        for line in output.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int(parts[0]) else { continue }
            let command = String(parts[1])
            let lower = command.lowercased()
            let isLanguageServer = lower.contains("language_server") || lower.contains("language-server")
            let isAntigravity = lower.contains("antigravity.app")
                || lower.contains("override_ide_name antigravity")
                || lower.contains("--app_data_dir antigravity")
                || lower.contains("/antigravity/")
            guard isLanguageServer, isAntigravity,
                  let csrfToken = extractFlag("--csrf_token", from: command) else {
                continue
            }
            processes.append(LocalAntigravityProcess(
                pid: pid,
                csrfToken: csrfToken,
                extensionPort: extractFlag("--extension_server_port", from: command).flatMap(Int.init),
                extensionServerCSRFToken: extractFlag("--extension_server_csrf_token", from: command)
            ))
        }
        guard !processes.isEmpty else {
            throw GeminiModelsUsageClientError.notAvailable("未检测到带 CSRF token 的 Antigravity language_server。")
        }
        return processes
    }

    /// 生成语言服务和扩展服务的 HTTP/HTTPS 候选端点，并去除重复目标。
    static func endpoints(
        for process: LocalAntigravityProcess,
        ports: [Int]
    ) -> [LocalAntigravityEndpoint] {
        var endpoints: [LocalAntigravityEndpoint] = []
        func append(_ endpoint: LocalAntigravityEndpoint) {
            guard !endpoints.contains(endpoint) else { return }
            endpoints.append(endpoint)
        }

        if let extensionPort = process.extensionPort {
            let csrfTokens = [process.extensionServerCSRFToken, process.csrfToken].compactMap { $0 }
            for csrfToken in csrfTokens where !endpoints.contains(where: {
                $0.scheme == "http" && $0.port == extensionPort && $0.csrfToken == csrfToken
            }) {
                append(LocalAntigravityEndpoint(
                    scheme: "http",
                    port: extensionPort,
                    csrfToken: csrfToken,
                    requiresCSRFToken: true
                ))
            }
        }
        for port in ports {
            append(LocalAntigravityEndpoint(
                scheme: "https",
                port: port,
                csrfToken: process.csrfToken,
                requiresCSRFToken: true
            ))
            append(LocalAntigravityEndpoint(
                scheme: "http",
                port: port,
                csrfToken: process.csrfToken,
                requiresCSRFToken: true
            ))
        }
        return endpoints
    }

    /// 从命令行读取形如 `--flag value` 或 `--flag=value` 的参数。
    static func extractFlag(_ flag: String, from command: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "\(NSRegularExpression.escapedPattern(for: flag))[=\\s]+([^\\s]+)",
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(command.startIndex..<command.endIndex, in: command)
        guard let match = regex.firstMatch(in: command, range: range),
              let valueRange = Range(match.range(at: 1), in: command) else {
            return nil
        }
        return String(command[valueRange])
    }
}
