import Combine
import CodexUsageShared
import Foundation
import OSLog

// 本文件负责降智雷达后台生命周期：监听开关、定时刷新、缓存和错误状态。

/// 降智雷达后台状态源；负责按设置启停、按工作时间节奏拉取并持久化快照。
@MainActor
final class CodexRadarStore: ObservableObject {
    @Published private(set) var snapshot: CodexRadarSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private let client: any CodexRadarFetching
    private let store: CodexRadarSnapshotStore
    private let settingsProvider: @MainActor @Sendable () -> CodexRadarSettings
    private let nowProvider: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.jinsihou.CodexUsage", category: "CodexRadar")
    private var refreshTask: Task<Void, Never>?
    private var hasStartedRefreshLoop = false
    private var settingsObserver: NSObjectProtocol?

    init(
        client: any CodexRadarFetching = DirectCodexRadarClient(),
        store: CodexRadarSnapshotStore = CodexRadarSnapshotStore(),
        settingsProvider: @escaping @MainActor @Sendable () -> CodexRadarSettings = {
            CodexRadarSettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        },
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.store = store
        self.settingsProvider = settingsProvider
        self.nowProvider = nowProvider
        self.snapshot = try? store.load()
    }

    deinit {
        refreshTask?.cancel()
    }

    /// 启动设置监听和后台循环；多次调用不会重复注册观察者。
    func start() {
        guard !hasStartedRefreshLoop else {
            return
        }
        hasStartedRefreshLoop = true
        observeSettings()
        applySettings()
    }

    /// 手动刷新雷达数据；即使后台开关关闭，用户点击区块刷新时也允许读取一次。
    func refresh() async {
        logger.info("Codex radar refresh started")
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let updatedSnapshot = try await client.fetchRadarSnapshot()
            try store.save(updatedSnapshot)
            snapshot = updatedSnapshot
            errorMessage = nil
            logger.info("Codex radar snapshot saved")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            logger.error("Codex radar refresh failed: \(self.errorMessage ?? "unknown", privacy: .public)")
            if snapshot == nil {
                snapshot = try? store.load()
            }
        }
    }

    /// 监听降智雷达设置变化，避免设置窗口和后台任务节奏脱节。
    private func observeSettings() {
        guard settingsObserver == nil else {
            return
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .codexRadarSettingsDidChange,
            object: MenuBarDisplaySettings.sharedDefaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applySettings()
            }
        }
    }

    /// 根据当前开关重建后台任务；关闭时保留最近快照用于下次打开快速展示。
    private func applySettings() {
        refreshTask?.cancel()
        refreshTask = nil

        guard settingsProvider().isEnabled else {
            return
        }

        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.refresh()
            while !Task.isCancelled {
                let interval = CodexRadarRefreshPolicy.intervalSeconds(for: self.nowProvider())
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else {
                    return
                }
                await self.refresh()
            }
        }
    }
}
