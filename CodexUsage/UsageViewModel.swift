import CodexUsageShared
import Foundation
import OSLog
import WidgetKit

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private let client: any UsageRateLimitFetching
    private let store: UsageSnapshotStore
    private let reloadWidgetTimelines: () -> Void
    private let logger = Logger(subsystem: "com.jinsihou.CodexUsage", category: "Usage")
    private var refreshTask: Task<Void, Never>?

    init(
        client: any UsageRateLimitFetching = DirectCodexUsageClient(),
        store: UsageSnapshotStore = UsageSnapshotStore(),
        reloadWidgetTimelines: @escaping () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
        }
    ) {
        self.client = client
        self.store = store
        self.reloadWidgetTimelines = reloadWidgetTimelines
        self.snapshot = try? store.load()
    }

    deinit {
        refreshTask?.cancel()
    }

    var menuBarTitle: String {
        "\(menuBarPrimaryTitle)\n\(menuBarSecondaryTitle)"
    }

    var menuBarPrimaryTitle: String {
        "\(menuBarPrimaryLabel) \(menuBarPrimaryValue)"
    }

    var menuBarSecondaryTitle: String {
        "\(menuBarSecondaryLabel) \(menuBarSecondaryValue)"
    }

    var menuBarPrimaryLabel: String {
        "5h"
    }

    var menuBarPrimaryValue: String {
        guard let rateLimits = snapshot?.rateLimits else {
            return "--"
        }
        return rateLimits.primary?.remainingPercentText ?? "--"
    }

    var menuBarSecondaryLabel: String {
        "7d"
    }

    var menuBarSecondaryValue: String {
        guard let rateLimits = snapshot?.rateLimits else {
            return "--"
        }
        return rateLimits.secondary?.remainingPercentText ?? "--"
    }

    var menuBarPrimaryTone: UsageRemainingTone {
        Self.tone(for: snapshot?.rateLimits.primary?.remainingPercent)
    }

    var menuBarSecondaryTone: UsageRemainingTone {
        Self.tone(for: snapshot?.rateLimits.secondary?.remainingPercent)
    }

    var menuHeaderPrimaryText: String {
        guard let rateLimits = snapshot?.rateLimits else {
            return "5 小时剩余 --"
        }
        return "5 小时剩余 \(rateLimits.primary?.remainingPercentText ?? "--")"
    }

    var menuHeaderSecondaryText: String {
        guard let rateLimits = snapshot?.rateLimits else {
            return "7 天剩余 --"
        }
        return "7 天剩余 \(rateLimits.secondary?.remainingPercentText ?? "--")"
    }

    var statusSymbolName: String {
        if errorMessage != nil {
            return "exclamationmark.triangle"
        }
        if isRefreshing {
            return "arrow.triangle.2.circlepath"
        }
        return "gauge.with.needle"
    }

    var planType: String {
        snapshot?.rateLimits.planType ?? "--"
    }

    var isStale: Bool {
        guard let snapshot else {
            return false
        }
        return Date().timeIntervalSince(snapshot.fetchedAt) > 120
    }

    func start() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task { [self] in
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await refresh()
            }
        }
    }

    func refresh() async {
        logger.info("Refresh started")
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let rateLimits = try await client.fetchRateLimits()
            let updatedSnapshot = UsageSnapshot(fetchedAt: Date(), rateLimits: rateLimits)
            try store.save(updatedSnapshot)
            snapshot = updatedSnapshot
            errorMessage = nil
            logger.info("Refresh saved snapshot")
            reloadWidgetTimelines()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            logger.error("Refresh failed: \(self.errorMessage ?? "unknown", privacy: .public)")
            if snapshot == nil {
                snapshot = try? store.load()
            }
        }
    }

    private static func tone(for remainingPercent: Int?) -> UsageRemainingTone {
        UsageRemainingTone(remainingPercent: remainingPercent)
    }
}

private extension RateLimitWindow {
    var remainingPercentText: String {
        "\(remainingPercent)%"
    }
}
