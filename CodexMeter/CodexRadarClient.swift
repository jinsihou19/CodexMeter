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
        do {
            switch source {
            case .codexRadar:
                return try await fetchRadarBench()
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

    /// 读取公开题库绑定，再以最多三个并发查询最新家族的各档位；任何请求失败都保留原快照。
    private func fetchRadarBench() async throws -> CodexRadarSnapshot {
        let bindingData = try await fetchData(from: endpointURL ?? CodexRadarSource.codexRadar.endpointURL)
        let binding = try JSONDecoder().decode(RadarBenchBinding.self, from: bindingData)
        guard binding.enabled, binding.productionReadVerified, binding.totalTasks > 0,
              !binding.modelEfforts.isEmpty,
              Set(binding.modelEfforts.map(\.id)).count == binding.modelEfforts.count else {
            throw DirectCodexRadarClientError.invalidResponse("雷达Bench题库绑定不可用")
        }
        let selections = CodexRadarModelSelection.latestGPTSeriesByFamily(
            from: binding.modelEfforts.filter { $0.model.hasPrefix("gpt-") && $0.model != "gpt-5.5" }
                .map { $0.series }
        )
        let fetchedAt = Date()
        var series: [CodexRadarModelSeries] = []
        for offset in stride(from: 0, to: selections.count, by: 3) {
            try Task.checkCancellation()
            let batch = Array(selections[offset..<min(offset + 3, selections.count)])
            let results = try await withThrowingTaskGroup(of: CodexRadarModelSeries?.self) { group in
                for selection in batch {
                    group.addTask {
                        var components = URLComponents(
                            url: endpointURL ?? URL(string: "https://codexradar.com/api/radar-bench-score")!,
                            resolvingAgainstBaseURL: false
                        )!
                        components.queryItems = [
                            URLQueryItem(name: "model", value: selection.model),
                            URLQueryItem(name: "effort", value: selection.reasoningEffort),
                            URLQueryItem(name: "view", value: "summary"),
                            URLQueryItem(name: "selection", value: "user-selected-v1")
                        ]
                        let data = try await fetchData(from: components.url!)
                        let summary = try JSONDecoder().decode(RadarBenchSummary.self, from: data)
                        return try summary.series(for: selection, binding: binding, fetchedAt: fetchedAt)
                    }
                }
                var results: [CodexRadarModelSeries] = []
                for try await result in group {
                    if let result { results.append(result) }
                }
                return results
            }
            series.append(contentsOf: results)
        }
        try Task.checkCancellation()
        // 请求完成顺序不稳定；按绑定顺序恢复，保证首屏和同分模型排序一致。
        let seriesByID = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        let orderedSeries = selections.compactMap { seriesByID[$0.id] }
        let latestGrade = orderedSeries.compactMap { $0.latest?.date }.compactMap { value in
            RadarBenchSummary.parseDate(value).map { (value, $0) }
        }.max { $0.1 < $1.1 }?.0
        return try makeSnapshot(
            source: .codexRadar,
            fetchedAt: fetchedAt,
            updatedAt: latestGrade,
            series: orderedSeries
        )
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
            return URL(string: "https://codexradar.com/data/radar-bench-binding.json")!
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

/// 官网公开题库绑定；以其当前模型档位和题集标识核对成绩，避免混入历史评测。
private struct RadarBenchBinding: Decodable, Sendable {
    let enabled: Bool
    let productionReadVerified: Bool
    let benchmark: String
    let taskSetSHA256: String
    let totalTasks: Int
    let modelEfforts: [Selection]

    enum CodingKeys: String, CodingKey {
        case enabled, benchmark
        case productionReadVerified = "production_read_verified"
        case taskSetSHA256 = "task_set_sha256"
        case totalTasks = "total_tasks"
        case modelEfforts = "model_efforts"
    }

    /// 绑定中的单个配置；复用已有家族版本筛选，不硬编码 GPT 版本与档位。
    struct Selection: Decodable, Sendable {
        let model: String
        let effort: String
        var id: String { "\(model)|\(effort)" }
        var series: CodexRadarModelSeries {
            CodexRadarModelSeries(
                id: id, label: "\(model) \(effort)", model: model,
                reasoningEffort: effort, latest: nil, recentDays: []
            )
        }
    }
}

/// RadarBench 满分 150 的公开聚合成绩；覆盖题数与通过题数分开，缺失分数不补零。
private struct RadarBenchSummary: Decodable {
    let benchmark: String
    let taskSetSHA256: String
    let scoreVersion: String
    let scoreMax: Double
    let model: String
    let effort: String
    let score: Double?
    let coverage: Int
    let requiredTasks: Int
    let scoreStatus: String
    let detailMetrics: DetailMetrics?
    let history: History?

    enum CodingKeys: String, CodingKey {
        case benchmark, model, effort, score, coverage, history
        case taskSetSHA256 = "task_set_sha256"
        case scoreVersion = "score_version"
        case scoreMax = "score_max"
        case requiredTasks = "required_tasks"
        case scoreStatus = "score_status"
        case detailMetrics = "detail_metrics"
    }

    /// 校验模型、题集与评分刻度，返回当前分数和最近三个 UTC 日的历史；缺分配置返回 nil。
    func series(
        for selection: CodexRadarModelSeries,
        binding: RadarBenchBinding,
        fetchedAt: Date
    ) throws -> CodexRadarModelSeries? {
        guard model == selection.model, effort == selection.reasoningEffort,
              benchmark == binding.benchmark, taskSetSHA256 == binding.taskSetSHA256,
              scoreVersion == "radar-bench-v2-150", scoreMax == 150,
              requiredTasks == binding.totalTasks, (0...requiredTasks).contains(coverage) else {
            throw DirectCodexRadarClientError.invalidResponse("雷达Bench成绩与题库绑定不一致")
        }
        guard let score else { return nil }
        guard score.isFinite, (0...150).contains(score), coverage > 0,
              scoreStatus == (coverage == requiredTasks ? "complete" : "provisional") else {
            throw DirectCodexRadarClientError.invalidResponse("雷达Bench分值或覆盖状态无效")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let cutoff = calendar.startOfDay(for: fetchedAt).addingTimeInterval(-2 * 24 * 60 * 60)
        var recentDays: [CodexRadarIQRun] = []
        if let history {
            guard history.model == model, history.effort == effort,
                  history.scoreVersion == scoreVersion, history.scoreMax == scoreMax,
                  history.timeZone == "UTC", history.bucket == "day" else {
                throw DirectCodexRadarClientError.invalidResponse("雷达Bench历史口径不一致")
            }
            for point in history.points.sorted(by: { $0.at < $1.at }) {
                guard let date = Self.parseDate(point.at), date >= cutoff, date <= fetchedAt else { continue }
                guard let historyScore = point.score else { continue }
                guard historyScore.isFinite, (0...150).contains(historyScore),
                      point.requiredTasks == requiredTasks, (1...requiredTasks).contains(point.coverage),
                      point.scoreStatus == (point.coverage == requiredTasks ? "complete" : "provisional") else {
                    throw DirectCodexRadarClientError.invalidResponse("雷达Bench历史分值无效")
                }
                recentDays.append(run(
                    score: historyScore, date: point.at, coverage: point.coverage, status: point.scoreStatus
                ))
            }
        }
        return CodexRadarModelSeries(
            id: selection.id, label: selection.label, model: model, reasoningEffort: effort,
            latest: run(score: score, date: detailMetrics?.latestGradedAt ?? "", coverage: coverage, status: scoreStatus),
            recentDays: Array(recentDays.suffix(3))
        )
    }

    /// 构造可展示记录；coverage 不是通过数，保留为独立字段供悬停说明。
    private func run(score: Double, date: String, coverage: Int, status: String) -> CodexRadarIQRun {
        CodexRadarIQRun(
            date: date, score: score, status: status, passed: nil, tasks: requiredTasks,
            invalid: nil, totalTokens: nil, wallTimeHuman: nil,
            model: model, reasoningEffort: effort, costUSD: nil, coveredTasks: coverage
        )
    }

    /// 兼容服务器返回的整秒与小数秒 ISO 时间，不能用抓取时间冒充判分时间。
    static func parseDate(_ value: String) -> Date? {
        (try? Date(value, strategy: .iso8601))
            ?? (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }

    /// 接口的最近真实判分时间；不使用 as_of 抓取时刻替代。
    struct DetailMetrics: Decodable {
        let latestGradedAt: String?
        enum CodingKeys: String, CodingKey { case latestGradedAt = "latest_graded_at" }
    }

    /// 服务端按 UTC 日归档的同口径历史；只保留三个自然日供迷你曲线展示。
    struct History: Decodable {
        let model: String
        let effort: String
        let scoreVersion: String
        let scoreMax: Double
        let timeZone: String
        let bucket: String
        let points: [Point]

        enum CodingKeys: String, CodingKey {
            case model, effort, bucket, points
            case scoreVersion = "score_version"
            case scoreMax = "score_max"
            case timeZone = "time_zone"
        }

        /// 单日快照允许缺分，但合法的零分与暂定成绩均有真实覆盖记录。
        struct Point: Decodable {
            let at: String
            let score: Double?
            let coverage: Int
            let requiredTasks: Int
            let scoreStatus: String

            enum CodingKeys: String, CodingKey {
                case at, score, coverage
                case requiredTasks = "required_tasks"
                case scoreStatus = "score_status"
            }
        }
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
