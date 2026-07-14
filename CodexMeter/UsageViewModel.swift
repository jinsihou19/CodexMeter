import CodexMeterShared
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
    private let refreshCadenceProvider: @MainActor @Sendable () -> UsageRefreshCadence
    private let resetCreditsVisibilityProvider: @MainActor @Sendable () -> Bool
    private let logger = Logger(subsystem: "com.jinsihou.CodexUsage", category: "Usage")
    private var refreshTask: Task<Void, Never>?
    private var hasStartedRefreshLoop = false
    private var appBehaviorObserver: NSObjectProtocol?
    private var popoverDisplayObserver: NSObjectProtocol?
    private var lastShowsResetCredits: Bool

    init(
        client: any UsageRateLimitFetching = DirectCodexUsageClient(),
        store: UsageSnapshotStore = UsageSnapshotStore(),
        reloadWidgetTimelines: @escaping () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
        },
        refreshCadenceProvider: @escaping @MainActor @Sendable () -> UsageRefreshCadence = {
            AppBehaviorSettings(defaults: MenuBarDisplaySettings.sharedDefaults).refreshCadence
        },
        resetCreditsVisibilityProvider: @escaping @MainActor @Sendable () -> Bool = {
            PopoverDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults).showsResetCredits
        }
    ) {
        self.client = client
        self.store = store
        self.reloadWidgetTimelines = reloadWidgetTimelines
        self.refreshCadenceProvider = refreshCadenceProvider
        self.resetCreditsVisibilityProvider = resetCreditsVisibilityProvider
        self.lastShowsResetCredits = resetCreditsVisibilityProvider()
        self.snapshot = try? store.load()
    }

    deinit {
        refreshTask?.cancel()
    }

    var menuBarTitle: String {
        [snapshot?.rateLimits.primary, snapshot?.rateLimits.secondary]
            .compactMap { $0 }
            .map { "\($0.compactDurationLabel) \($0.remainingPercentText)" }
            .joined(separator: "\n")
    }

    var menuBarPrimaryTitle: String {
        "\(menuBarPrimaryLabel) \(menuBarPrimaryValue)"
    }

    var menuBarSecondaryTitle: String {
        "\(menuBarSecondaryLabel) \(menuBarSecondaryValue)"
    }

    var menuBarPrimaryLabel: String {
        snapshot?.rateLimits.primary?.compactDurationLabel ?? "quota"
    }

    var menuBarPrimaryValue: String {
        guard let rateLimits = snapshot?.rateLimits else {
            return "--"
        }
        return rateLimits.primary?.remainingPercentText ?? "--"
    }

    var menuBarSecondaryLabel: String {
        snapshot?.rateLimits.secondary?.compactDurationLabel ?? "quota"
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
        guard let window = snapshot?.rateLimits.primary else {
            return "用量窗口剩余 --"
        }
        return "\(window.durationLabel)剩余 \(window.remainingPercentText)"
    }

    var menuHeaderSecondaryText: String {
        guard let window = snapshot?.rateLimits.secondary else {
            return "用量窗口剩余 --"
        }
        return "\(window.durationLabel)剩余 \(window.remainingPercentText)"
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
        guard !hasStartedRefreshLoop else {
            return
        }

        hasStartedRefreshLoop = true
        observeAppBehaviorSettings()
        observePopoverDisplaySettings()
        applyRefreshCadence()
        // 本地已有缓存时也要唤醒 WidgetKit，避免上一次空时间线继续显示“暂无数据”。
        if snapshot != nil {
            reloadWidgetTimelines()
        }
    }

    func refresh() async {
        await refresh(forceRefreshResetCredits: false)
    }

    /// 用户主动刷新重置卡时绕过每日缓存，确保测试机上已经发放的卡能被立刻补读出来。
    func refreshResetCredits() async {
        await refresh(forceRefreshResetCredits: true)
    }

    /// 下拉框打开时补齐重置卡数据；只有数量但缺少到期明细时，也绕过当天缓存重读一次。
    func refreshResetCreditsIfNeeded() async {
        let resetCredits = snapshot?.resetCredits
        let needsResetCreditsRefresh = resetCredits == nil
            || (resetCredits?.availableCount ?? 0) > 0 && resetCredits?.credits.isEmpty == true
        guard resetCreditsVisibilityProvider(), needsResetCreditsRefresh else {
            return
        }
        await refresh(forceRefreshResetCredits: true)
    }

    /// 刷新用量快照；只有重置卡模块从关到开时才绕过当天缓存，保留常规轮询的每日限频。
    private func refresh(forceRefreshResetCredits: Bool) async {
        logger.info("Refresh started")
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let updatedSnapshot = try await client.fetchUsageSnapshot(forceRefreshResetCredits: forceRefreshResetCredits)
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
                // 网络刷新失败但本地缓存可用时，同步恢复小组件显示。
                if snapshot != nil {
                    reloadWidgetTimelines()
                }
            }
        }
    }

    private static func tone(for remainingPercent: Int?) -> UsageRemainingTone {
        UsageRemainingTone(remainingPercent: remainingPercent)
    }

    /// 监听设置页里刷新频率的变化；只关心本 app 的偏好通知，避免 UserDefaults 全局噪声反复重启任务。
    private func observeAppBehaviorSettings() {
        guard appBehaviorObserver == nil else {
            return
        }
        appBehaviorObserver = NotificationCenter.default.addObserver(
            forName: .appBehaviorSettingsDidChange,
            object: MenuBarDisplaySettings.sharedDefaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyRefreshCadence()
            }
        }
    }

    /// 监听下拉面板模块开关；重置卡从隐藏恢复显示时，立即补一次真实接口请求。
    private func observePopoverDisplaySettings() {
        guard popoverDisplayObserver == nil else {
            return
        }
        lastShowsResetCredits = resetCreditsVisibilityProvider()
        popoverDisplayObserver = NotificationCenter.default.addObserver(
            forName: .popoverDisplaySettingsDidChange,
            object: MenuBarDisplaySettings.sharedDefaults,
            queue: .main
        ) { [weak self] notification in
            let notifiedShowsResetCredits = notification.userInfo?[PopoverPreferenceKeys.showsResetCredits] as? Bool
            Task { @MainActor in
                guard let self else {
                    return
                }
                let showsResetCredits = notifiedShowsResetCredits ?? self.resetCreditsVisibilityProvider()
                let previousShowsResetCredits = self.lastShowsResetCredits
                self.lastShowsResetCredits = showsResetCredits
                guard showsResetCredits, !previousShowsResetCredits else {
                    return
                }
                await self.refresh(forceRefreshResetCredits: true)
            }
        }
    }

    /// 按当前刷新频率重建后台任务；手动模式不做启动同步，也不保留定时循环。
    private func applyRefreshCadence() {
        refreshTask?.cancel()
        refreshTask = nil

        guard let intervalNanoseconds = refreshCadenceProvider().intervalNanoseconds else {
            return
        }

        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
                guard !Task.isCancelled else {
                    return
                }
                await self.refresh()
            }
        }
    }
}

private extension RateLimitWindow {
    var remainingPercentText: String {
        "\(remainingPercent)%"
    }
}
