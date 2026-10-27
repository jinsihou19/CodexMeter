import CodexMeterShared
import Foundation

// 本文件负责从用户选择的雷达数据源拉取模型分值，并映射为共享雷达快照。

/// 降智雷达抓取协议；后台 Store 传入当前数据源，测试可注入固定快照。
protocol CodexRadarFetching: Sendable {
    func fetchRadarSnapshot(source: CodexRadarSource) async throws -> CodexRadarSnapshot
}

/// 降智雷达网络客户端；读取所选公开来源，将独立评分口径交给各自解码器校验。
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
        do {
            switch source {
            case .codexRadar:
                let data = try await fetchData(from: endpointURL ?? source.endpointURL)
                return try JSONDecoder().decode(CodexThreeTaskResponse.self, from: data)
                    .snapshot(fetchedAt: Date())
            case .radarInsights:
                let data = try await fetchData(from: endpointURL ?? source.endpointURL)
                return try JSONDecoder().decode(CodexRadarInsightsResponse.self, from: data)
                    .snapshot(fetchedAt: Date())
            case .aiIQ:
                let data = try await fetchData(from: endpointURL ?? source.endpointURL)
                return try JSONDecoder().decode(AIIQResponse.self, from: data)
                    .snapshot(fetchedAt: Date())
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as DirectCodexRadarClientError {
            throw error
        } catch let error as DecodingError {
            throw DirectCodexRadarClientError.invalidResponse(error.localizedDescription)
        } catch {
            throw DirectCodexRadarClientError.network(error.localizedDescription)
        }
    }

    /// 共用只读请求配置；仅接受成功 HTTP 响应，不对失败或空数据制造替代成绩。
    private func fetchData(from url: URL) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeoutSeconds
        )
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("codex-usage-widget/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else {
            throw DirectCodexRadarClientError.httpStatus(response.statusCode)
        }
        return data
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
            return URL(string: "https://codexradar.com/data/codex-three-task-results.json")!
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

/// 官网三题批次快照；仅按已发布的等权规则计算总分，不沿用 RadarBench 的历史。
private struct CodexThreeTaskResponse: Decodable {
    let schema: String
    let protocolVersion: String
    let configurations: Int
    let taskCount: Int
    let integratedVerifiedAt: String
    let rows: [Row]

    enum CodingKeys: String, CodingKey {
        case schema, configurations, rows
        case protocolVersion = "protocol"
        case taskCount = "task_count"
        case integratedVerifiedAt = "integrated_verified_at"
    }

    /// 校验批次身份、重复档位和数据时间；仅保留完整三题成绩与各 GPT 家族最新版。
    func snapshot(fetchedAt: Date) throws -> CodexRadarSnapshot {
        let verifiedAt = (try? Date(integratedVerifiedAt, strategy: .iso8601))
            ?? (try? Date(integratedVerifiedAt, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        guard schema == "codex-three-task-results/1", protocolVersion == "codex-independent-three-v1",
              taskCount == 3, configurations == rows.count, !rows.isEmpty,
              Set(rows.map(\.id)).count == rows.count, verifiedAt != nil else {
            throw DirectCodexRadarClientError.invalidResponse("三题雷达批次不可识别")
        }
        let series = try rows.filter { $0.model.hasPrefix("gpt-") && $0.model != "gpt-5.5" }
            .map { try $0.series(date: integratedVerifiedAt) }
        return try makeSnapshot(
            source: .codexRadar, fetchedAt: fetchedAt, updatedAt: integratedVerifiedAt,
            series: CodexRadarModelSelection.latestGPTSeriesByFamily(from: series).filter { $0.latest != nil }
        )
    }

    /// 单个模型档位的三个原始分项；缺分保留为空，糖果答错则保留为有效零分。
    struct Row: Decodable {
        let model: String
        let effort: String
        let pompeii: Pompeii
        let pelican: Pelican
        let candy: Candy
        var id: String { "\(model)|\(effort)" }

        /// 三题各占50分；缺分时保留模型身份防止回退旧版本，越界数值使本次刷新失败。
        func series(date: String) throws -> CodexRadarModelSeries {
            guard !effort.isEmpty,
                  pompeii.score100.map({ $0.isFinite && (0...100).contains($0) }) ?? true,
                  pelican.score.map({ $0.isFinite && (0...100).contains($0) }) ?? true else {
                throw DirectCodexRadarClientError.invalidResponse("三题雷达分项无效")
            }
            let run: CodexRadarIQRun?
            if let pompeiiScore = pompeii.score100, let pelicanScore = pelican.score,
               let correct = candy.correct {
                let score = (pompeiiScore + pelicanScore) / 2 + (correct ? 50 : 0)
                run = CodexRadarIQRun(
                    date: date, score: score, status: "complete", passed: nil, tasks: 3,
                    invalid: nil, totalTokens: nil, wallTimeHuman: nil,
                    model: model, reasoningEffort: effort, costUSD: nil, coveredTasks: 3
                )
            } else {
                run = nil
            }
            return CodexRadarModelSeries(
                id: id, label: "\(model) \(effort)", model: model, reasoningEffort: effort,
                latest: run, recentDays: []
            )
        }
    }

    /// 庞贝原始百分制分数；不会把缺失或未完成成绩补零。
    struct Pompeii: Decodable { let score100: Double? }
    /// 鹈鹕原评审百分制分数；沿用站方对各模型发布的评审结果。
    struct Pelican: Decodable { let score: Double? }
    /// 糖果分项只有对错，nil 表示尚无可计入总分的结论。
    struct Candy: Decodable { let correct: Bool? }
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
