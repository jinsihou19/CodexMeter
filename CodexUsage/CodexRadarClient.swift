import CodexUsageShared
import Foundation

// 本文件负责从 codexradar.com 拉取 current.json，并映射为共享雷达快照。

/// 降智雷达抓取协议；后台 Store 只依赖抽象，便于测试注入固定快照。
protocol CodexRadarFetching: Sendable {
    func fetchRadarSnapshot() async throws -> CodexRadarSnapshot
}

/// 直接读取 codexradar.com/current.json 的网络客户端，只解码 UI 需要的雷达字段。
struct DirectCodexRadarClient: CodexRadarFetching {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static let defaultEndpointURL = URL(string: "https://codexradar.com/current.json")!

    private let endpointURL: URL
    private let timeoutSeconds: TimeInterval
    private let transport: Transport

    init(
        endpointURL: URL = Self.defaultEndpointURL,
        timeoutSeconds: TimeInterval = 30,
        transport: @escaping Transport = Self.urlSessionTransport
    ) {
        self.endpointURL = endpointURL
        self.timeoutSeconds = timeoutSeconds
        self.transport = transport
    }

    /// 拉取并解码雷达快照；HTTP、网络和 JSON 错误会归一成可展示的本地化错误。
    func fetchRadarSnapshot() async throws -> CodexRadarSnapshot {
        var request = URLRequest(url: endpointURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutSeconds)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("codex-usage-widget/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await transport(request)
            guard (200..<300).contains(response.statusCode) else {
                throw DirectCodexRadarClientError.httpStatus(response.statusCode)
            }
            return try JSONDecoder().decode(CodexRadarResponse.self, from: data).snapshot(fetchedAt: Date())
        } catch let error as DirectCodexRadarClientError {
            throw error
        } catch let error as DecodingError {
            throw DirectCodexRadarClientError.invalidResponse(error.localizedDescription)
        } catch {
            throw DirectCodexRadarClientError.network(error.localizedDescription)
        }
    }

    /// 使用系统 URLSession 执行请求，并确认拿到 HTTP 响应对象。
    private static func urlSessionTransport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DirectCodexRadarClientError.invalidHTTPResponse
        }
        return (data, httpResponse)
    }
}

/// 降智雷达客户端错误；错误文案面向下拉面板直接展示。
enum DirectCodexRadarClientError: LocalizedError, Equatable {
    case invalidHTTPResponse
    case httpStatus(Int)
    case invalidResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "降智雷达响应不可识别。"
        case .httpStatus(let statusCode):
            return "降智雷达返回 \(statusCode)。"
        case .invalidResponse:
            return "降智雷达数据格式不可识别。"
        case .network(let message):
            return "读取降智雷达失败：\(message)"
        }
    }
}

/// current.json 顶层 DTO；只保留雷达图表和预测区需要的字段。
private struct CodexRadarResponse: Decodable {
    let monitoredAt: String?
    let timezone: String?
    let prediction: Prediction?
    let modelIQ: ModelIQ?

    enum CodingKeys: String, CodingKey {
        case monitoredAt = "monitored_at"
        case timezone
        case prediction
        case modelIQ = "model_iq"
    }

    /// 把远端 DTO 转成共享快照模型，隔离任意 comparison key 的排序细节。
    func snapshot(fetchedAt: Date) -> CodexRadarSnapshot {
        CodexRadarSnapshot(
            fetchedAt: fetchedAt,
            monitoredAt: monitoredAt,
            timezone: timezone,
            prediction: prediction?.model,
            modelIQ: modelIQ?.model
        )
    }

    struct Prediction: Decodable {
        let level: String?
        let probability24h: Double?
        let probability48h: Double?
        let expectedWindow: String?
        let summary: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case level
            case probability24h = "probability_24h"
            case probability48h = "probability_48h"
            case expectedWindow = "expected_window"
            case summary
            case updatedAt = "updated_at"
        }

        var model: CodexRadarPrediction {
            CodexRadarPrediction(
                level: level,
                probability24h: probability24h,
                probability48h: probability48h,
                expectedWindow: expectedWindow,
                summary: summary,
                updatedAt: updatedAt
            )
        }
    }

    struct ModelIQ: Decodable {
        let latest: Run?
        let recentDays: [Run]?
        let comparisons: [String: Series]?
        let quotaRadar: QuotaRadar?

        enum CodingKeys: String, CodingKey {
            case latest
            case recentDays = "recent_days"
            case comparisons
            case quotaRadar = "quota_radar"
        }

        var model: CodexRadarModelIQ {
            let primaryLabel = Self.primaryLabel(latest: latest)
            let primary = CodexRadarModelSeries(
                id: "primary",
                label: primaryLabel,
                model: latest?.model,
                reasoningEffort: latest?.reasoningEffort,
                latest: latest?.snapshot,
                recentDays: recentDays?.compactMap(\.snapshot) ?? []
            )
            let comparisonModels = (comparisons ?? [:])
                .map { key, series in series.model(id: key) }
                .sorted { left, right in left.sortPriority < right.sortPriority }
            return CodexRadarModelIQ(
                primary: primary,
                comparisons: comparisonModels,
                quotaRadarUpdatedAt: quotaRadar?.updatedAt
            )
        }

        /// 为主曲线生成和远端页面一致的短标签。
        private static func primaryLabel(latest: Run?) -> String {
            let model = latest?.model?.uppercased() ?? "GPT"
            let effort = latest?.reasoningEffort ?? "xhigh"
            return "\(model) \(effort)"
        }

        /// 模型 IQ 区域内的配额雷达元信息；更新时间用于 UI 底部展示数据源的新鲜度。
        struct QuotaRadar: Decodable {
            let updatedAt: String?

            enum CodingKeys: String, CodingKey {
                case updatedAt = "updated_at"
            }
        }
    }

    struct Series: Decodable {
        let label: String?
        let modelName: String?
        let reasoningEffort: String?
        let latest: Run?
        let recentDays: [Run]?

        enum CodingKeys: String, CodingKey {
            case label
            case modelName = "model"
            case reasoningEffort = "reasoning_effort"
            case latest
            case recentDays = "recent_days"
        }

        /// 将任意 comparison key 包装进稳定的图表序列。
        func model(id: String) -> CodexRadarModelSeries {
            CodexRadarModelSeries(
                id: id,
                label: label ?? "\(modelName ?? "GPT") \(reasoningEffort ?? "")",
                model: modelName,
                reasoningEffort: reasoningEffort,
                latest: latest?.snapshot,
                recentDays: recentDays?.compactMap(\.snapshot) ?? []
            )
        }
    }

    struct Run: Decodable {
        let date: String?
        let score: Double?
        let status: String?
        let passed: Int?
        let tasks: Int?
        let invalid: Int?
        let totalTokens: Int?
        let wallTimeHuman: String?
        let model: String?
        let reasoningEffort: String?
        let costUSD: Double?

        enum CodingKeys: String, CodingKey {
            case date
            case score
            case status
            case passed
            case tasks
            case invalid
            case totalTokens = "total_tokens"
            case wallTimeHuman = "wall_time_human"
            case model
            case reasoningEffort = "reasoning_effort"
            case costUSD = "cost_usd"
        }

        var snapshot: CodexRadarIQRun? {
            guard let date, let score else {
                return nil
            }
            return CodexRadarIQRun(
                date: date,
                score: score,
                status: status,
                passed: passed,
                tasks: tasks,
                invalid: invalid,
                totalTokens: totalTokens,
                wallTimeHuman: wallTimeHuman,
                model: model,
                reasoningEffort: reasoningEffort,
                costUSD: costUSD
            )
        }
    }
}

private extension CodexRadarModelSeries {
    /// 排序优先级让主图例尽量贴近 codexradar 页面展示顺序。
    var sortPriority: Int {
        switch id {
        case "gpt_55_high":
            return 10
        case "gpt_55_medium":
            return 20
        case "gpt_54_xhigh":
            return 30
        default:
            return 100
        }
    }
}
