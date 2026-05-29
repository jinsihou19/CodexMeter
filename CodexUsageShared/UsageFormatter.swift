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
}
