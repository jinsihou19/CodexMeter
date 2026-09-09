// 本文件提供本机用量的内置历史单价；远程目录通过独立缓存补充当前价格。
import Foundation

/// 保存已核对的 OpenAI 模型历史价格；未知模型拒绝猜价。
enum LocalCodexPricing {
    /// 描述每百万 token 的美元单价，可选保存长上下文价格。
    struct Price: Codable, Equatable, Sendable {
        let inputPerMillion: Double
        let cachedInputPerMillion: Double?
        let outputPerMillion: Double
        let thresholdTokens: Int?
        let inputAboveThreshold: Double?
        let cachedInputAboveThreshold: Double?
        let outputAboveThreshold: Double?
        var cacheWritePerMillion: Double? = nil
        var cacheWriteAboveThreshold: Double? = nil
        var source: String = "内置价格"
    }

    /// 为已知模型提供按生效日区分的 OpenAI 官方价；未知模型不猜测费用。
    static func price(for model: String, on day: String? = nil) -> Price? {
        let normalized = LocalCodexPricingCatalog.key(model)
        let usesReducedGPT56Price = (day ?? "9999-12-31") >= "2026-07-30"
        if normalized == "gpt-6-astra" {
            return price(input: 10, cachedInput: 1, output: 50, longContextMultiplier: (2, 2, 1.5))
        }
        if normalized == "gpt-5.6" || normalized.hasPrefix("gpt-5.6-sol") {
            // 官方 2026-08-21 调价：https://openai.com/index/gpt-5-6/
            return (day ?? "9999-12-31") >= "2026-08-21"
                ? price(input: 4, cachedInput: 0.4, output: 20, longContextMultiplier: (2, 2, 1.5))
                : price(input: 5, cachedInput: 0.5, output: 30, longContextMultiplier: (2, 2, 1.5))
        }
        if normalized == "gpt-5.6-terra" || normalized.hasPrefix("gpt-5.6-terra-") {
            return usesReducedGPT56Price
                ? price(input: 2, cachedInput: 0.2, output: 12, longContextMultiplier: (2, 2, 1.5))
                : price(input: 2.5, cachedInput: 0.25, output: 15, longContextMultiplier: (2, 2, 1.5))
        }
        if normalized == "gpt-5.6-luna" || normalized.hasPrefix("gpt-5.6-luna-") {
            return usesReducedGPT56Price
                ? price(input: 0.2, cachedInput: 0.02, output: 1.2, longContextMultiplier: (2, 2, 1.5))
                : price(input: 1, cachedInput: 0.1, output: 6, longContextMultiplier: (2, 2, 1.5))
        }
        let table: [(String, Double, Double, Double)] = [
            ("gpt-5.5-pro", 30, 30, 180),
            ("gpt-5.5", 5, 0.5, 30),
            ("gpt-5.4-mini", 0.75, 0.075, 4.5),
            ("gpt-5.4-nano", 0.2, 0.02, 1.25),
            ("gpt-5.4-pro", 30, 30, 180),
            ("gpt-5.4", 2.5, 0.25, 15),
            ("gpt-5.3-codex", 1.75, 0.175, 14),
            ("gpt-5.2-codex", 1.75, 0.175, 14),
            ("gpt-5.2", 1.75, 0.175, 14),
            ("gpt-5.1", 1.25, 0.125, 10),
            ("gpt-5-codex", 1.25, 0.125, 10),
            ("gpt-5", 1.25, 0.125, 10)
        ]
        guard let match = table.first(where: { normalized == $0.0 || normalized.hasPrefix($0.0 + "-") }) else {
            return nil
        }
        return price(input: match.1, cachedInput: match.2, output: match.3)
    }

    /// 构建标准或长上下文价格；GPT-5.6 的阈值为单次输入 272K token。
    private static func price(
        input: Double,
        cachedInput: Double,
        output: Double,
        longContextMultiplier: (input: Double, cachedInput: Double, output: Double)? = nil
    ) -> Price {
        Price(
            inputPerMillion: input,
            cachedInputPerMillion: cachedInput,
            outputPerMillion: output,
            thresholdTokens: longContextMultiplier == nil ? nil : 272_000,
            inputAboveThreshold: longContextMultiplier.map { input * $0.input },
            cachedInputAboveThreshold: longContextMultiplier.map { cachedInput * $0.cachedInput },
            outputAboveThreshold: longContextMultiplier.map { output * $0.output },
            cacheWritePerMillion: longContextMultiplier.map { _ in input * 1.25 },
            cacheWriteAboveThreshold: longContextMultiplier.map { input * $0.input * 1.25 }
        )
    }

    /// 去除 provider 前缀并统一大小写，保留模型版本信息供稳定匹配。
    static func normalizedModel(_ raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.hasPrefix("openai/") ? String(lowered.dropFirst("openai/".count)) : lowered
    }

}
