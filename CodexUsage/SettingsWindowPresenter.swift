import AppKit
import SwiftUI

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

        prepareApplicationForWindow()
        activateApplication()
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()

        return settingsWindow
    }

    private func makeWindow() -> NSWindow {
        let settingsWindow = NSWindow(contentViewController: makeContentViewController())
        settingsWindow.title = "Codex 用量设置"
        settingsWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.setContentSize(NSSize(width: 780, height: 560))
        settingsWindow.minSize = NSSize(width: 740, height: 520)
        settingsWindow.center()
        return settingsWindow
    }
}
