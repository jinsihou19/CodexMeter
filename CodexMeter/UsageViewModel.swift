import CodexMeterShared
import Foundation
import OSLog
@preconcurrency import UserNotifications
import WidgetKit

/// 描述一次需要交付给系统通知中心的额度变化。
enum UsageNotificationEvent: Equatable, Sendable {
    case depleted(windowTitle: String)
    case lowRemaining(windowTitle: String, remainingPercent: Int)
}

/// 只在额度向下跨过边界时生成事件，避免每次轮询重复通知。
enum UsageNotificationEventResolver {
    /// 比较相邻快照并返回需要发送的通知；额度恢复或边界内波动不会重复触发。
    static func events(
        previous: RateLimitSnapshot,
        current: RateLimitSnapshot,
        settings: UsageNotificationSettings
    ) -> [UsageNotificationEvent] {
        let windows = [
            (previous.primary, current.primary),
            (previous.secondary, current.secondary)
        ]

        return windows.compactMap { previousWindow, currentWindow in
            guard let previousWindow, let currentWindow else {
                return nil
            }
            let previousRemaining = previousWindow.remainingPercent
            let currentRemaining = currentWindow.remainingPercent
            guard currentRemaining < previousRemaining else {
                return nil
            }
            if settings.notifiesWhenDepleted, previousRemaining > 0, currentRemaining == 0 {
                return .depleted(windowTitle: currentWindow.durationLabel)
            }
            if settings.notifiesWhenLow,
               previousRemaining > settings.lowRemainingThreshold,
               currentRemaining <= settings.lowRemainingThreshold
            {
                return .lowRemaining(
                    windowTitle: currentWindow.durationLabel,
                    remainingPercent: currentRemaining
                )
            }
            return nil
        }
    }
}

/// 持久化额度重置检测基线，使睡眠和应用重启后的首次刷新仍能识别真实重置。
struct UsageResetCelebrationDetector {
    private struct State: Codable {
        let wasAboveThreshold: Bool
        let resetBoundary: Int?
    }

    private enum ResetKind: String {
        case session
        case weekly
    }

    private static let defaultsKey = "celebrations.resetDetectorStates.v1"
    private static let threshold = 1.0

    private let defaults: UserDefaults
    private var states: [String: State]

    /// 从偏好存储恢复检测基线；损坏或旧格式数据按空状态处理，避免影响正常刷新。
    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: State].self, from: data)
        {
            self.states = decoded
        } else {
            self.states = [:]
        }
    }

    /// 仅在缺少持久化状态时用缓存快照建立基线，避免启动时覆盖更可靠的跨进程记录。
    mutating func seed(with rateLimits: RateLimitSnapshot?) {
        guard let rateLimits else { return }
        var changed = false
        for (kind, window) in observations(in: rateLimits) where states[kind.rawValue] == nil {
            states[kind.rawValue] = State(
                wasAboveThreshold: window.usedPercent > Self.threshold,
                resetBoundary: window.resetsAt
            )
            changed = true
        }
        if changed {
            persist()
        }
    }

    /// 更新持久化检测状态，并在用量跨过阈值且重置边界前移时返回是否应播放彩带。
    mutating func process(_ rateLimits: RateLimitSnapshot, option: UsageResetCelebrationOption) -> Bool {
        var shouldCelebrate = false
        for (kind, window) in observations(in: rateLimits) {
            let key = kind.rawValue
            let previous = states[key]
            let isAboveThreshold = window.usedPercent > Self.threshold
            let boundaryAdvanced = previous?.resetBoundary.flatMap { previousBoundary in
                window.resetsAt.map { $0 > previousBoundary }
            } ?? false
            let crossedBelowThreshold = previous?.wasAboveThreshold == true && !isAboveThreshold
            let suppressedCrossing = crossedBelowThreshold && !boundaryAdvanced

            if crossedBelowThreshold, boundaryAdvanced, includes(kind, in: option) {
                shouldCelebrate = true
            }
            states[key] = State(
                wasAboveThreshold: suppressedCrossing ? true : isAboveThreshold,
                resetBoundary: boundaryAdvanced ? window.resetsAt : previous?.resetBoundary ?? window.resetsAt
            )
        }
        persist()
        return shouldCelebrate
    }

    /// 按接口实际窗口时长区分会话与周额度，兼容只有 primary 周窗口的账号。
    private func observations(in rateLimits: RateLimitSnapshot) -> [(ResetKind, RateLimitWindow)] {
        [rateLimits.primary, rateLimits.secondary].compactMap { window in
            guard let window else { return nil }
            let kind: ResetKind = window.isWeeklyQuotaWindow ? .weekly : .session
            return (kind, window)
        }
    }

    /// 判断当前用户选项是否包含指定重置类型。
    private func includes(_ kind: ResetKind, in option: UsageResetCelebrationOption) -> Bool {
        switch kind {
        case .session:
            option.celebratesSessionReset
        case .weekly:
            option.celebratesWeeklyReset
        }
    }

    /// 将小型检测状态写入共享偏好，供下次启动和唤醒后的刷新继续使用。
    private func persist() {
        guard let data = try? JSONEncoder().encode(states) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// 把用量边界事件交给 macOS 通知中心；权限请求只由用户主动开启设置时触发。
@MainActor
final class UsageNotificationController {
    private var previousRateLimits: RateLimitSnapshot?
    private var resetCelebrationDetector: UsageResetCelebrationDetector
    private let playConfetti: () -> Void

    /// 注入彩带播放动作，使重置判断保持可测试且不依赖窗口实现。
    init(
        defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults,
        playConfetti: @escaping () -> Void = {}
    ) {
        self.resetCelebrationDetector = UsageResetCelebrationDetector(defaults: defaults)
        self.playConfetti = playConfetti
    }

    /// 用已有缓存建立比较基线，避免应用启动后的第一次刷新被误判为额度下降。
    func seed(with snapshot: UsageSnapshot?) {
        previousRateLimits = snapshot?.rateLimits
        resetCelebrationDetector.seed(with: snapshot?.rateLimits)
    }

    /// 处理新快照并异步投递系统通知；无跨界事件时不访问通知中心。
    func process(_ snapshot: UsageSnapshot) {
        let current = snapshot.rateLimits
        defer { previousRateLimits = current }
        let celebrationOption = UsageResetCelebrationOption(
            rawValue: MenuBarDisplaySettings.sharedDefaults.string(
                forKey: UsageCelebrationPreferenceKeys.resetOption
            ) ?? ""
        ) ?? .off
        if resetCelebrationDetector.process(current, option: celebrationOption) {
            playConfetti()
        }
        guard let previousRateLimits else {
            return
        }
        let settings = UsageNotificationSettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        let events = UsageNotificationEventResolver.events(
            previous: previousRateLimits,
            current: current,
            settings: settings
        )
        guard !events.isEmpty else {
            return
        }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let authorization = settings.authorizationStatus
            guard authorization == .authorized || authorization == .provisional else {
                return
            }
            for event in events {
                let content = UNMutableNotificationContent()
                switch event {
                case let .depleted(windowTitle):
                    content.title = "Codex 额度已耗尽"
                    content.body = "\(windowTitle)窗口已无剩余额度。"
                case let .lowRemaining(windowTitle, remainingPercent):
                    content.title = "Codex 额度偏低"
                    content.body = "\(windowTitle)窗口剩余 \(remainingPercent)%。"
                }
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: "CodexMeter.usage.\(UUID().uuidString)",
                    content: content,
                    trigger: nil
                )
                center.add(request, withCompletionHandler: nil)
            }
        }
    }

    /// 用户开启任一提醒时请求 alert 与 sound 权限，拒绝后不反复弹窗。
    static func requestAuthorization() {
        Task {
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

}

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
    private let processUsageNotifications: @MainActor @Sendable (UsageSnapshot) -> Void
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
            DispatchQueue.global(qos: .utility).async {
                WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
            }
        },
        refreshCadenceProvider: @escaping @MainActor @Sendable () -> UsageRefreshCadence = {
            AppBehaviorSettings(defaults: MenuBarDisplaySettings.sharedDefaults).refreshCadence
        },
        resetCreditsVisibilityProvider: @escaping @MainActor @Sendable () -> Bool = {
            PopoverDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults).showsResetCredits
        },
        processUsageNotifications: @escaping @MainActor @Sendable (UsageSnapshot) -> Void = { _ in }
    ) {
        self.client = client
        self.store = store
        self.reloadWidgetTimelines = reloadWidgetTimelines
        self.refreshCadenceProvider = refreshCadenceProvider
        self.resetCreditsVisibilityProvider = resetCreditsVisibilityProvider
        self.processUsageNotifications = processUsageNotifications
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
            processUsageNotifications(updatedSnapshot)
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
