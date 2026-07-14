import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowOpener {
    private let delayNanoseconds: UInt64
    private let activateApplication: @MainActor () -> Void
    private let showSettingsWindow: @MainActor () -> Void

    init(
        delayNanoseconds: UInt64 = 250_000_000,
        activateApplication: @escaping @MainActor () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
        },
        showSettingsWindow: @escaping @MainActor () -> Void = {
            SettingsWindowPresenter.shared.show()
        }
    ) {
        self.delayNanoseconds = delayNanoseconds
        self.activateApplication = activateApplication
        self.showSettingsWindow = showSettingsWindow
    }

    func open() {
        let delay = DispatchTimeInterval.nanoseconds(Int(delayNanoseconds))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                self?.showNow()
            }
        }
    }

    func openForApplicationReopen() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.showNow()
            }
        }
    }

    func openAfterDelay() async {
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        showNow()
    }

    func handleApplicationReopen() async -> Bool {
        showNow()
        return true
    }

    private func showNow() {
        activateApplication()
        showSettingsWindow()
    }
}

/// 管理 macOS 登录时启动注册；只封装主 app 服务，避免设置视图直接依赖 ServiceManagement。
@MainActor
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private let statusProvider: @MainActor () -> SMAppService.Status
    private let registerApp: @MainActor () throws -> Void
    private let unregisterApp: @MainActor () throws -> Void

    init(
        statusProvider: @escaping @MainActor () -> SMAppService.Status = {
            SMAppService.mainApp.status
        },
        registerApp: @escaping @MainActor () throws -> Void = {
            try SMAppService.mainApp.register()
        },
        unregisterApp: @escaping @MainActor () throws -> Void = {
            try SMAppService.mainApp.unregister()
        }
    ) {
        self.statusProvider = statusProvider
        self.registerApp = registerApp
        self.unregisterApp = unregisterApp
    }

    /// 返回当前是否已经注册为登录项；被系统限制或需要审批时按未启用展示，方便用户重试。
    var isEnabled: Bool {
        statusProvider() == .enabled
    }

    /// 切换登录项注册状态；重复设置同一状态时直接返回，避免无意义的系统调用。
    func setEnabled(_ enabled: Bool) throws {
        guard enabled != isEnabled else {
            return
        }
        if enabled {
            try registerApp()
        } else {
            try unregisterApp()
        }
    }
}
