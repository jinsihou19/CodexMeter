// 设置窗口宿主负责 AppKit 外观与窗口尺寸，具体页面和交互由 SwiftUI 管理。
import AppKit
import CodexMeterShared
import SwiftUI

extension SurfaceAppearanceMode {
    /// 把共享外观偏好转换为 AppKit 标准窗口外观。
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

/// 复用设置窗口，在活动监控切换大屏时保存与恢复其窗口位置和尺寸。
@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private var window: NSWindow?
    private var officeRestoreFrame: NSRect?
    private let makeContentViewController: @MainActor () -> NSViewController
    private let prepareApplicationForWindow: @MainActor () -> Void
    private let activateApplication: @MainActor () -> Void

    /// 注入窗口内容与激活行为；默认保留标准窗口宿主，由内容分层选择系统材质。
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

    /// 大屏模式将现有窗口扩大到所在屏幕的可用区域，退出时恢复进入前的边框。
    /// 系统全屏由 macOS 管理，设置页在这种情况下只切换内部布局。
    func setOfficeExpanded(_ expanded: Bool) {
        guard let window else { return }
        if expanded {
            guard officeRestoreFrame == nil, !window.styleMask.contains(.fullScreen), let screen = window.screen else { return }
            officeRestoreFrame = window.frame
            window.setFrame(screen.visibleFrame, display: true)
        } else if let restoreFrame = officeRestoreFrame {
            officeRestoreFrame = nil
            if !window.styleMask.contains(.fullScreen) {
                window.setFrame(restoreFrame, display: true)
            }
        }
    }

    /// 在设置变化后立即刷新窗口标题栏和 AppKit 控件，不等待窗口重新打开。
    func applyCurrentAppearance() {
        let mode = SurfaceAppearanceSettings(defaults: MenuBarDisplaySettings.sharedDefaults).appearanceMode
        window?.appearance = mode.appKitAppearance
        window?.title = AppLocalization.string("CodexMeter 设置")
    }

    /// 创建可复用的全尺寸标准窗口，透明标题栏与内容分层材质协作。
    private func makeWindow() -> NSWindow {
        let contentViewController = makeContentViewController()
        let settingsWindow = NSWindow(contentViewController: contentViewController)
        settingsWindow.title = AppLocalization.string("CodexMeter 设置")
        settingsWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        settingsWindow.titlebarAppearsTransparent = true
        settingsWindow.titleVisibility = .hidden
        settingsWindow.titlebarSeparatorStyle = .none
        settingsWindow.isMovableByWindowBackground = true
        settingsWindow.isOpaque = false
        settingsWindow.backgroundColor = .clear
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.setContentSize(NSSize(
            width: SettingsPanelLayout.windowWidth,
            height: SettingsPanelLayout.windowHeight
        ))
        settingsWindow.minSize = NSSize(width: 800, height: 560)
        settingsWindow.center()
        return settingsWindow
    }
}
