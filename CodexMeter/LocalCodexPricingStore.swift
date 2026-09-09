// 本文件维护 models.dev 的 OpenAI 价格缓存；不上传模型用量或会话数据。
import Foundation
import CoreFoundation

/// 冻结一次统计使用的价格目录；按首次观察到的变价日期保留旧单价，避免新价覆盖历史。
struct LocalCodexPricingCatalog: Codable, Equatable, Sendable {
    /// 保存完整价格行与本机观察到的生效日；空日期仅用于此前无内置价的新模型补价。
    struct Revision: Codable, Equatable, Sendable {
        let effectiveFrom: String
        let price: LocalCodexPricing.Price
    }

    var fetchedAt: Date?
    var revisions: [String: [Revision]] = [:]

    /// 优先使用适用于事件日期的远程版本；首次抓取前的已知模型仍使用内置历史价。
    func price(for model: String, on day: String) -> LocalCodexPricing.Price? {
        let key = Self.key(model)
        if let revision = revisions[key]?.last(where: { $0.effectiveFrom <= day }) {
            return revision.price
        }
        return LocalCodexPricing.price(for: key, on: day)
    }

    /// 精确匹配供应商和模型；仅去除标准快照日期，不推测未知家族或其他供应商的别名。
    static func key(_ model: String) -> String {
        let normalized = LocalCodexPricing.normalizedModel(model)
        let key = normalized.replacingOccurrences(of: "-\\d{4}-\\d{2}-\\d{2}$", with: "", options: .regularExpression)
        return key == "gpt-5.6" ? "gpt-5.6-sol" : key
    }

    /// 解析并合并可信价格；坏行不覆盖旧行，供应商缺失或没有有效价格时拒绝整份更新。
    mutating func merge(_ data: Data, now: Date, timeZone: TimeZone = .current) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let provider = root["openai"] as? [String: Any],
              let models = provider["models"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // 与用量的本地日历保持一致；测试可注入跨日时区。
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: now)
        var accepted = 0
        for id in models.keys.sorted() {
            let value = models[id]
            // 官方基础模型行优先于同目录中的日期快照，避免字典遍历顺序决定价格。
            if Self.key(id) != id && models[Self.key(id)] != nil { continue }
            guard let row = value as? [String: Any], let cost = row["cost"] as? [String: Any],
                  !id.contains("/"), let price = Self.decodePrice(cost, model: id) else { continue }
            accepted += 1
            let key = Self.key(id)
            guard revisions[key]?.last?.price != price else { continue }
            // 首次接入无法还原供应商过去的调价时间；已知模型保留内置历史价，新模型可补算旧记录。
            let effectiveFrom = revisions[key] == nil && LocalCodexPricing.price(for: key) == nil ? "" : day
            var history = revisions[key] ?? []
            if history.last?.effectiveFrom == effectiveFrom { history.removeLast() }
            history.append(Revision(effectiveFrom: effectiveFrom, price: price))
            revisions[key] = history
        }
        guard accepted > 0 else { throw URLError(.cannotParseResponse) }
        fetchedAt = now
    }

    /// 将每百万 token 单价转换为统一价格行；负数、非数值及不完整长上下文行拒绝使用。
    private static func decodePrice(_ cost: [String: Any], model: String) -> LocalCodexPricing.Price? {
        let fields = ["input", "output", "cache_read", "cache_write"]
        let legacyLong = cost["context_over_200k"] as? [String: Any]
        if cost["context_over_200k"] != nil && legacyLong == nil { return nil }
        var contextThreshold: Int?
        var contextRates: [String: Any]?
        if let tiers = cost["tiers"] as? [[String: Any]], !tiers.isEmpty {
            // 当前公式支持一个上下文阈值；多阶梯价格保持未知，不能静默套用第一档。
            guard tiers.count == 1, let tier = tiers[0]["tier"] as? [String: Any],
                  tier["type"] as? String == "context", let size = tier["size"] as? NSNumber,
                  CFGetTypeID(size) != CFBooleanGetTypeID(), size.doubleValue.isFinite,
                  size.doubleValue > 0, size.doubleValue <= Double(Int32.max),
                  size.doubleValue.rounded() == size.doubleValue else { return nil }
            contextThreshold = size.intValue
            contextRates = tiers[0]
        } else if cost["tiers"] != nil && !(cost["tiers"] is [[String: Any]]) {
            return nil
        }
        let long = contextRates ?? legacyLong
        for lane in [cost, long].compactMap({ $0 }) {
            for field in fields where lane[field] != nil {
                guard let number = lane[field] as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue >= 0 else { return nil }
            }
        }
        guard let input = (cost["input"] as? NSNumber)?.doubleValue,
              let output = (cost["output"] as? NSNumber)?.doubleValue else { return nil }
        let builtin = LocalCodexPricing.price(for: model)
        let cached = (cost["cache_read"] as? NSNumber)?.doubleValue
        let writes = (cost["cache_write"] as? NSNumber)?.doubleValue
        if let long, long["input"] == nil || long["output"] == nil { return nil }
        // 已核对模型的阈值以官方口径为准；外部目录没有长上下文行时，按既有倍率作用于新单价。
        let threshold = contextThreshold ?? builtin?.thresholdTokens ?? (long == nil ? nil : 200_000)
        let inputLong = (long?["input"] as? NSNumber)?.doubleValue
            ?? (builtin?.thresholdTokens == nil ? nil : input * 2)
        let outputLong = (long?["output"] as? NSNumber)?.doubleValue
            ?? (builtin?.thresholdTokens == nil ? nil : output * 1.5)
        return LocalCodexPricing.Price(
            inputPerMillion: input,
            cachedInputPerMillion: cached,
            outputPerMillion: output,
            thresholdTokens: threshold,
            inputAboveThreshold: inputLong,
            cachedInputAboveThreshold: (long?["cache_read"] as? NSNumber)?.doubleValue
                ?? (long == nil && threshold != nil ? cached.map { $0 * 2 } : nil),
            outputAboveThreshold: outputLong,
            cacheWritePerMillion: writes,
            cacheWriteAboveThreshold: (long?["cache_write"] as? NSNumber)?.doubleValue
                ?? (long == nil && threshold != nil ? writes.map { $0 * 2 } : nil),
            source: "models.dev"
        )
    }
}

/// 串行协调价格抓取与原子缓存；合并并发刷新，失败保留旧目录，测试通过闭包和临时路径隔离网络。
actor LocalCodexPricingStore {
    static let shared = LocalCodexPricingStore(
        cacheURL: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexMeter/model-pricing/models-dev-v1.json")
    )
    private let cacheURL: URL
    private let fetch: @Sendable () async throws -> Data
    private var catalog: LocalCodexPricingCatalog
    private var lastAttempt: Date?
    private var inFlight: Task<LocalCodexPricingCatalog, Never>?

    /// 恢复最后有效目录；文件损坏时使用空目录，首次统计会尝试重新获取。
    init(cacheURL: URL, fetch: @escaping @Sendable () async throws -> Data = { try await LocalCodexPricingStore.fetchCatalog() }) {
        self.cacheURL = cacheURL
        self.fetch = fetch
        self.catalog = (try? Data(contentsOf: cacheURL)).flatMap {
            try? JSONDecoder().decode(LocalCodexPricingCatalog.self, from: $0)
        } ?? LocalCodexPricingCatalog()
    }

    /// 返回可用目录；24 小时过期刷新，未知模型允许提前刷新，所有重试至少间隔 15 分钟。
    func snapshot(now: Date, retryUnknown: Bool = false) async -> LocalCodexPricingCatalog {
        if let inFlight { return await inFlight.value }
        let age = catalog.fetchedAt.map { now.timeIntervalSince($0) } ?? .infinity
        guard age >= 86_400 || (retryUnknown && age >= 900),
              lastAttempt.map({ now.timeIntervalSince($0) >= 900 }) ?? true else { return catalog }
        lastAttempt = now
        let task = Task { await self.refresh(now: now) }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    /// 完整校验、保存后才发布新目录；抓取或落盘失败均沿用旧结果，不清空有效缓存。
    private func refresh(now: Date) async -> LocalCodexPricingCatalog {
        do {
            let data = try await fetch()
            var updated = catalog
            try updated.merge(data, now: now)
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: cacheURL, options: .atomic)
            catalog = updated
        } catch {
            // 错误不携带响应正文；界面通过上次成功时间与过期标记明确展示降级。
        }
        return catalog
    }

    /// 仅下载公共价格目录；限制超时和响应大小，HTTP 错误不会被当作有效价格。
    static func fetchCatalog() async throws -> Data {
        var request = URLRequest(url: URL(string: "https://models.dev/api.json")!)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              data.count <= 25_000_000 else { throw URLError(.badServerResponse) }
        return data
    }
}
