import Foundation

public struct UsageFormatter: Sendable {
    private let localeIdentifier: String
    private let secondsFromGMT: Int
    private let language: AppLanguage

    public init(
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent,
        language: AppLanguage = .chineseSimplified
    ) {
        self.localeIdentifier = locale.identifier
        self.secondsFromGMT = timeZone.secondsFromGMT()
        self.language = language
    }

    public func resetTime(epochSeconds: Int?) -> String {
        guard let epochSeconds else {
            return "--"
        }

        return format(epochSeconds: epochSeconds, dateFormat: "yyyy-MM-dd HH:mm")
    }

    /// 计算用量窗口距离重置还剩多久；优先使用接口返回的相对秒数，避免本地时间漂移影响展示。
    public func resetRemainingText(window: RateLimitWindow?, now: Date = Date()) -> String {
        guard let seconds = resetRemainingSeconds(window: window, now: now) else {
            return "--"
        }
        if seconds <= 0 {
            return AppLocalization.string("已重置", language: language)
        }
        let duration = compactDuration(seconds: seconds)
        return AppLocalization.usesEnglish(language: language) ? "in \(duration)" : "\(duration)后"
    }

    /// 返回窗口重置倒计时秒数；无重置信息时返回 nil，已经到期时返回 0。
    public func resetRemainingSeconds(window: RateLimitWindow?, now: Date = Date()) -> Int? {
        guard let window else {
            return nil
        }
        if let resetAfterSeconds = window.resetAfterSeconds {
            return resetAfterSeconds
        }
        guard let resetsAt = window.resetsAt else {
            return nil
        }
        return max(0, Int((Double(resetsAt) - now.timeIntervalSince1970).rounded()))
    }

    public func widgetResetClock(epochSeconds: Int?) -> String {
        guard let epochSeconds else {
            return "--"
        }

        return format(epochSeconds: epochSeconds, dateFormat: "HH:mm")
    }

    public func widgetResetDate(epochSeconds: Int?) -> String {
        guard let epochSeconds else {
            return "--"
        }

        return format(
            epochSeconds: epochSeconds,
            dateFormat: AppLocalization.usesEnglish(language: language) ? "MMM d" : "M月d日"
        )
    }

    private func format(epochSeconds: Int, dateFormat: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.timeZone = TimeZone(secondsFromGMT: secondsFromGMT)
        formatter.dateFormat = dateFormat
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochSeconds)))
    }

    public func fetchedAt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.timeZone = TimeZone(secondsFromGMT: secondsFromGMT)
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    public func windowLabel(_ window: RateLimitWindow?) -> String {
        guard let window else {
            return "--"
        }
        return "\(window.remainingPercent)%"
    }

    public func creditsStatus(_ credits: CreditsSnapshot?) -> String {
        guard let credits else {
            return AppLocalization.usesEnglish(language: language) ? "No credits information" : "无 credits 信息"
        }
        if credits.unlimited {
            return AppLocalization.usesEnglish(language: language) ? "Unlimited credits" : "无限 credits"
        }
        if credits.hasCredits, let balance = credits.balance {
            return AppLocalization.usesEnglish(language: language) ? "Credits balance \(balance)" : "credits 余额 \(balance)"
        }
        if credits.hasCredits {
            return AppLocalization.usesEnglish(language: language) ? "Credits available" : "有 credits"
        }
        return AppLocalization.usesEnglish(language: language) ? "No credits" : "无 credits"
    }

    /// 将重置卡到期时间格式化为本地绝对时间；缺失时间用占位符，避免误报到期点。
    public func resetCreditExpiration(_ date: Date?) -> String {
        guard let date else {
            return "--"
        }
        return format(date: date, dateFormat: "yyyy-MM-dd HH:mm")
    }

    /// 把重置卡过期时间转成相对文案；过期卡直接提示已过期，避免显示负倒计时。
    public func resetCreditExpirationRemaining(_ date: Date?, now: Date = Date()) -> String {
        guard let date else {
            return "--"
        }
        let seconds = Int(date.timeIntervalSince(now).rounded())
        guard seconds > 0 else {
            return AppLocalization.string("已过期", language: language)
        }
        let duration = compactDuration(seconds: seconds)
        return AppLocalization.usesEnglish(language: language) ? "in \(duration)" : "\(duration)后"
    }

    public func tokenCount(_ tokens: Int64?) -> String {
        guard let tokens else {
            return "--"
        }

        let absoluteTokens = abs(tokens)
        if AppLocalization.usesEnglish(language: language) {
            if absoluteTokens >= 1_000_000_000 {
                return decimal(Double(tokens) / 1_000_000_000) + "B"
            }
            if absoluteTokens >= 1_000_000 {
                return decimal(Double(tokens) / 1_000_000) + "M"
            }
            if absoluteTokens >= 1_000 {
                return decimal(Double(tokens) / 1_000) + "K"
            }
            return "\(tokens)"
        }
        if absoluteTokens >= 100_000_000 {
            return decimal(Double(tokens) / 100_000_000) + "亿"
        }
        if absoluteTokens >= 10_000 {
            return decimal(Double(tokens) / 10_000) + "万"
        }
        return "\(tokens)"
    }

    public func compactDuration(seconds: Int?) -> String {
        guard let seconds, seconds >= 0 else {
            return "--"
        }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return AppLocalization.usesEnglish(language: language)
                ? "\(days)d \(hours)h"
                : "\(days) 天 \(hours) 小时"
        }
        if hours > 0 {
            return AppLocalization.usesEnglish(language: language)
                ? "\(hours)h \(minutes)m"
                : "\(hours) 小时 \(minutes) 分"
        }
        return AppLocalization.usesEnglish(language: language) ? "\(minutes)m" : "\(minutes) 分"
    }

    public func percent(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return "\(Int(value.rounded()))%"
    }

    public func reasoningEffort(_ effort: String?) -> String {
        guard let effort, !effort.isEmpty else {
            return "--"
        }
        switch effort.lowercased() {
        case "minimal":
            return AppLocalization.string("最小", language: language)
        case "low":
            return AppLocalization.string("低", language: language)
        case "medium":
            return AppLocalization.string("中", language: language)
        case "high":
            return AppLocalization.string("高", language: language)
        case "xhigh":
            return AppLocalization.string("超高", language: language)
        default:
            return effort
        }
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: localeIdentifier), arguments: [value])
            .replacingOccurrences(of: ".0", with: "")
    }

    /// 使用构造时捕获的地区和时区格式化日期，避免自动时区变化让同一快照前后显示不一致。
    private func format(date: Date, dateFormat: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.timeZone = TimeZone(secondsFromGMT: secondsFromGMT)
        formatter.dateFormat = dateFormat
        return formatter.string(from: date)
    }
}
