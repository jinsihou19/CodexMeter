import CodexUsageShared
import Foundation

protocol UsageRateLimitFetching: Sendable {
    func fetchRateLimits() async throws -> RateLimitSnapshot
}

struct DirectCodexUsageClient: UsageRateLimitFetching {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    static let defaultEndpointURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private let authFileURL: URL
    private let endpointURL: URL
    private let timeoutSeconds: TimeInterval
    private let transport: Transport

    init(
        authFileURL: URL = Self.defaultAuthFileURL(),
        endpointURL: URL = Self.defaultEndpointURL,
        timeoutSeconds: TimeInterval = 45,
        transport: @escaping Transport = Self.urlSessionTransport
    ) {
        self.authFileURL = authFileURL
        self.endpointURL = endpointURL
        self.timeoutSeconds = timeoutSeconds
        self.transport = transport
    }

    func fetchRateLimits() async throws -> RateLimitSnapshot {
        let accessToken = try loadAccessToken()
        var request = URLRequest(url: endpointURL, timeoutInterval: timeoutSeconds)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-usage-widget/1.0", forHTTPHeaderField: "User-Agent")

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
    let credits: WhamCredits?
    let rateLimitReachedType: String?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
        case rateLimitReachedType = "rate_limit_reached_type"
    }

    var codexSnapshot: RateLimitSnapshot {
        RateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: rateLimit?.primaryWindow?.rateLimitWindow,
            secondary: rateLimit?.secondaryWindow?.rateLimitWindow,
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
    let resetAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }

    var rateLimitWindow: RateLimitWindow {
        RateLimitWindow(
            usedPercent: usedPercent,
            windowDurationMins: limitWindowSeconds.map { $0 / 60 },
            resetsAt: resetAt
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
