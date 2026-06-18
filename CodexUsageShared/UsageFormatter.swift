import Foundation

public struct UsageFormatter: Sendable {
    private let localeIdentifier: String
    private let secondsFromGMT: Int

    public init(locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) {
        self.localeIdentifier = locale.identifier
        self.secondsFromGMT = timeZone.secondsFromGMT()
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
            return "已重置"
        }
        return "\(compactDuration(seconds: seconds))后"
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

        return format(epochSeconds: epochSeconds, dateFormat: "M月d日")
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
            return "无 credits 信息"
        }
        if credits.unlimited {
            return "无限 credits"
        }
        if credits.hasCredits, let balance = credits.balance {
            return "credits 余额 \(balance)"
        }
        if credits.hasCredits {
            return "有 credits"
        }
        return "无 credits"
    }

    public func tokenCount(_ tokens: Int64?) -> String {
        guard let tokens else {
            return "--"
        }

        let absoluteTokens = abs(tokens)
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
            return "\(days) 天 \(hours) 小时"
        }
        if hours > 0 {
            return "\(hours) 小时 \(minutes) 分"
        }
        return "\(minutes) 分"
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
            return "最小"
        case "low":
            return "低"
        case "medium":
            return "中"
        case "high":
            return "高"
        case "xhigh":
            return "超高"
        default:
            return effort
        }
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: localeIdentifier), arguments: [value])
            .replacingOccurrences(of: ".0", with: "")
    }
}
