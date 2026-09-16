import CodexMeterShared
import Foundation

// 本文件负责从用户选择的雷达数据源拉取模型分值，并映射为共享雷达快照。

/// 降智雷达抓取协议；后台 Store 传入当前数据源，测试可注入固定快照。
protocol CodexRadarFetching: Sendable {
    func fetchRadarSnapshot(source: CodexRadarSource) async throws -> CodexRadarSnapshot
}

/// 降智雷达网络客户端；复用同一套传输和错误处理适配三个公开 JSON 数据源。
struct DirectCodexRadarClient: CodexRadarFetching {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let endpointURL: URL?
    private let timeoutSeconds: TimeInterval
    private let transport: Transport

    init(
        endpointURL: URL? = nil,
        timeoutSeconds: TimeInterval = 30,
        transport: @escaping Transport = Self.urlSessionTransport
    ) {
        self.endpointURL = endpointURL
        self.timeoutSeconds = timeoutSeconds
        self.transport = transport
    }

    /// 拉取指定来源并解码雷达快照；HTTP、网络和 JSON 错误统一转为可展示错误。
    func fetchRadarSnapshot(source: CodexRadarSource) async throws -> CodexRadarSnapshot {
        var request = URLRequest(
            url: endpointURL ?? source.endpointURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeoutSeconds
        )
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("codex-usage-widget/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await transport(request)
            guard (200..<300).contains(response.statusCode) else {
                throw DirectCodexRadarClientError.httpStatus(response.statusCode)
            }
            let fetchedAt = Date()
            switch source {
            case .codexRadar:
                return try JSONDecoder().decode(CodexRadarEfficiencyResponse.self, from: data)
                    .snapshot(fetchedAt: fetchedAt)
            case .radarInsights:
                return try JSONDecoder().decode(CodexRadarInsightsResponse.self, from: data)
                    .snapshot(fetchedAt: fetchedAt)
            case .aiIQ:
                return try JSONDecoder().decode(AIIQResponse.self, from: data)
                    .snapshot(fetchedAt: fetchedAt)
            }
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

private extension CodexRadarSource {
    /// 返回各来源当前公开的只读 JSON 地址。
    var endpointURL: URL {
        switch self {
        case .codexRadar:
            return URL(string: "https://codexradar.com/data/intelligence-efficiency.json")!
        case .radarInsights:
            return URL(string: "https://codexradar.com/api/radar-insights")!
        case .aiIQ:
            return URL(string: "https://www.aiiq.org/api/models")!
        }
    }
}

/// 将来源序列包装为现有共享模型；空响应视为格式错误，避免覆盖可用缓存。
private func makeSnapshot(
    source: CodexRadarSource,
    fetchedAt: Date,
    updatedAt: String?,
    series: [CodexRadarModelSeries]
) throws -> CodexRadarSnapshot {
    let visibleSeries = series.filter { $0.model != "gpt-5.5" }
    guard let primary = visibleSeries.first else {
        throw DirectCodexRadarClientError.invalidResponse("没有可展示的模型分值")
    }
    return CodexRadarSnapshot(
        fetchedAt: fetchedAt,
        monitoredAt: updatedAt,
        timezone: nil,
        prediction: nil,
        modelIQ: CodexRadarModelIQ(
            primary: primary,
            comparisons: Array(visibleSeries.dropFirst()),
            updatedAt: updatedAt
        ),
        source: source
    )
}

/// Codex Radar 软件工程效能响应；当前分值和完整历史共用同一个公开文件。
private struct CodexRadarEfficiencyResponse: Decodable {
    let sourceUpdatedAt: String?
    let points: [Point]
    let history: [History]

    enum CodingKeys: String, CodingKey {
        case sourceUpdatedAt = "source_updated_at"
        case points
        case history
    }

    /// 仅保留 Codex 中的 GPT 模型，并把每个模型档位的历史快照合并到同一序列。
    func snapshot(fetchedAt: Date) throws -> CodexRadarSnapshot {
        let currentPoints = points.filter(\.isRadarModel)
        let dateFormatter = ISO8601DateFormatter()
        let latestHistoryDate = history.compactMap { dateFormatter.date(from: $0.at) }.max()
        let historyCutoff = latestHistoryDate?.addingTimeInterval(-3 * 24 * 60 * 60)
        let recentHistory = history.filter { item in
            guard let historyCutoff, let date = dateFormatter.date(from: item.at) else {
                return false
            }
            return date >= historyCutoff
        }
        var historyByID: [String: [CodexRadarIQRun]] = [:]
        for item in recentHistory {
            for point in item.points where point.isRadarModel {
                historyByID[point.id, default: []].append(point.run(date: item.at))
            }
        }
        let series = currentPoints.map { point in
            CodexRadarModelSeries(
                id: point.id,
                label: point.label,
                model: point.model,
                reasoningEffort: point.effort,
                latest: point.run(date: point.latestGradedAt ?? sourceUpdatedAt ?? ""),
                recentDays: historyByID[point.id] ?? []
            )
        }
        return try makeSnapshot(
            source: .codexRadar,
            fetchedAt: fetchedAt,
            updatedAt: sourceUpdatedAt,
            series: series
        )
    }

    /// 单个模型档位的效能分值；数值字段使用 Double 兼容上游的整数和小数 JSON。
    struct Point: Decodable {
        let model: String
        let effort: String
        let harness: String?
        let iq: Double
        let passed: Double?
        let validTasks: Double?
        let averagePriceUSD: Double?
        let averageTotalTokens: Double?
        let latestGradedAt: String?

        enum CodingKeys: String, CodingKey {
            case model, effort, harness, iq, passed
            case validTasks = "valid_tasks"
            case averagePriceUSD = "average_price_usd"
            case averageTotalTokens = "average_total_tokens"
            case latestGradedAt = "latest_graded_at"
        }

        var id: String { "\(model)|\(effort)" }
        var label: String { "\(model) \(effort)" }
        var isRadarModel: Bool { harness == nil || harness == "codex" || harness == "dsh" }

        /// 把当前点或历史点转换为 UI 已使用的运行记录。
        func run(date: String) -> CodexRadarIQRun {
            CodexRadarIQRun(
                date: date,
                score: iq,
                status: nil,
                passed: passed.map(Int.init),
                tasks: validTasks.map(Int.init),
                invalid: nil,
                totalTokens: averageTotalTokens.map(Int.init),
                wallTimeHuman: nil,
                model: model,
                reasoningEffort: effort,
                costUSD: averagePriceUSD
            )
        }
    }

    struct History: Decodable {
        let at: String
        let points: [Point]
    }
}

/// Radar Insights 综合智能响应；只使用完整模型矩阵，不把推荐子集误当作历史序列。
private struct CodexRadarInsightsResponse: Decodable {
    let sourceUpdatedAt: String?
    let comprehensivePoints: [Point]

    enum CodingKeys: String, CodingKey {
        case sourceUpdatedAt = "source_updated_at"
        case comprehensivePoints = "comprehensive_points"
    }

    /// 将综合智能当前分值映射为无历史的模型序列。
    func snapshot(fetchedAt: Date) throws -> CodexRadarSnapshot {
        let series = comprehensivePoints.filter { $0.model.hasPrefix("gpt-") }.map { point in
            let run = CodexRadarIQRun(
                date: sourceUpdatedAt ?? "",
                score: point.iq,
                status: nil,
                passed: nil,
                tasks: point.samples.map(Int.init),
                invalid: nil,
                totalTokens: nil,
                wallTimeHuman: nil,
                model: point.model,
                reasoningEffort: point.effort,
                costUSD: nil
            )
            return CodexRadarModelSeries(
                id: "\(point.model)|\(point.effort)",
                label: "\(point.model) \(point.effort)",
                model: point.model,
                reasoningEffort: point.effort,
                latest: run,
                recentDays: []
            )
        }
        return try makeSnapshot(
            source: .radarInsights,
            fetchedAt: fetchedAt,
            updatedAt: sourceUpdatedAt,
            series: series
        )
    }

    struct Point: Decodable {
        let model: String
        let effort: String
        let iq: Double
        let samples: Double?
    }
}

/// AI IQ 公共模型响应；菜单只展示有分值的 OpenAI 前六名，保持下拉面板紧凑。
private struct AIIQResponse: Decodable {
    let updatedAt: String?
    let models: [Model]

    /// 将 OpenAI 和其他厂商各前六名映射为无历史序列，避免面板过长。
    func snapshot(fetchedAt: Date) throws -> CodexRadarSnapshot {
        let rankedModels = models
            .filter { $0.iq != nil && $0.id != "gpt-5.5" }
            .sorted { ($0.rank ?? .max) < ($1.rank ?? .max) }
        let visibleModels = Array(rankedModels.filter { $0.provider == "OpenAI" }.prefix(6))
            + Array(rankedModels.filter { $0.provider != "OpenAI" }.prefix(6))
        let series = visibleModels
            .compactMap { model -> CodexRadarModelSeries? in
                guard let iq = model.iq else { return nil }
                let run = CodexRadarIQRun(
                    date: updatedAt ?? "",
                    score: iq,
                    status: nil,
                    passed: nil,
                    tasks: nil,
                    invalid: nil,
                    totalTokens: nil,
                    wallTimeHuman: nil,
                    model: model.id,
                    reasoningEffort: nil,
                    costUSD: nil
                )
                return CodexRadarModelSeries(
                    id: model.id,
                    label: model.name,
                    model: model.id,
                    reasoningEffort: nil,
                    latest: run,
                    recentDays: []
                )
            }
        return try makeSnapshot(
            source: .aiIQ,
            fetchedAt: fetchedAt,
            updatedAt: updatedAt,
            series: Array(series)
        )
    }

    struct Model: Decodable {
        let id: String
        let name: String
        let provider: String
        let rank: Int?
        let iq: Double?
    }
}
