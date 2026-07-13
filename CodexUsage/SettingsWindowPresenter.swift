import AppKit
import CodexUsageShared
import SwiftUI

extension SurfaceAppearanceMode {
    /// 把共享外观偏好转换为 AppKit 窗口外观；自动模式返回 nil 以继续跟随系统。
    var appKitAppearance: NSAppearance? {
        switch self {
        case .automatic:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }

    /// 根据强制外观或系统当前配色选择设置页左上角的配套应用图标资源。
    func appIconResourceName(systemColorScheme: ColorScheme) -> String {
        switch colorScheme ?? systemColorScheme {
        case .dark:
            return "SettingsAppIconDark"
        default:
            return "SettingsAppIconLight"
        }
    }
}

@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private var window: NSWindow?
    private let makeContentViewController: @MainActor () -> NSViewController
    private let prepareApplicationForWindow: @MainActor () -> Void
    private let activateApplication: @MainActor () -> Void

    init(
        makeContentViewController: @escaping @MainActor () -> NSViewController = {
            NSHostingController(rootView: SettingsView())
        },
        prepareApplicationForWindow: @escaping @MainActor () -> Void = {
            NSApp.setActivationPolicy(.accessory)
            NSApp.unhide(nil)
        },
        activateApplication: @escaping @MainActor () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
        }
    ) {
        self.makeContentViewController = makeContentViewController
        self.prepareApplicationForWindow = prepareApplicationForWindow
        self.activateApplication = activateApplication
    }

    @discardableResult
    func show() -> NSWindow {
        let settingsWindow = window ?? makeWindow()
        window = settingsWindow
        applyCurrentAppearance()

        prepareApplicationForWindow()
        activateApplication()
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()

        return settingsWindow
    }

    /// 在设置变化后立即刷新窗口标题栏和 AppKit 控件，不等待窗口重新打开。
    func applyCurrentAppearance() {
        let mode = SurfaceAppearanceSettings(defaults: MenuBarDisplaySettings.sharedDefaults).appearanceMode
        window?.appearance = mode.appKitAppearance
    }

    private func makeWindow() -> NSWindow {
        let settingsWindow = NSWindow(contentViewController: makeContentViewController())
        settingsWindow.title = "Codex 用量设置"
        settingsWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.setContentSize(NSSize(width: 820, height: 600))
        settingsWindow.minSize = NSSize(width: 780, height: 560)
        settingsWindow.center()
        return settingsWindow
    }
}
