import AppKit
import SwiftUI

@main
enum CodexUsageMain {
    @MainActor private static var appDelegate: AppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        application.delegate = delegate
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: UsageViewModel?
    private var statusBarController: StatusBarController?
    private let settingsWindowOpener = SettingsWindowOpener()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewModel = UsageViewModel()
        self.viewModel = viewModel
        statusBarController = StatusBarController(viewModel: viewModel)
        viewModel.start()
        settingsWindowOpener.open()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindowOpener.openForApplicationReopen()
        return true
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let viewModel: UsageViewModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var defaultsObserver: NSObjectProtocol?

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: MenuBarDisplaySettings().statusItemWidth)
        super.init()
        configureStatusItem()
        configurePopover()
        observeSettings()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.title = ""
        button.image = nil
        button.toolTip = "Codex 用量"
        button.target = self
        button.action = #selector(togglePopover(_:))

        let label = PassthroughHostingView(rootView: StatusBarLabel(viewModel: viewModel))
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.heightAnchor.constraint(equalToConstant: MenuBarDisplaySettings().statusLabelHeight)
        ])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 520)
        popover.contentViewController = NSHostingController(rootView: MenuBarView(viewModel: viewModel))
    }

    private func observeSettings() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applySettings()
            }
        }
        applySettings()
    }

    private func applySettings() {
        statusItem.length = MenuBarDisplaySettings(defaults: .standard).statusItemWidth
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            activatePopoverWindow()
        }
    }

    private func activatePopoverWindow() {
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.popover.contentViewController?.view.window?.makeKey()
        }
    }
}

private struct StatusBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage(MenuBarPreferenceKeys.layoutDensity) private var layoutDensity = MenuBarDisplaySettings.defaultLayoutDensity.rawValue
    @AppStorage(MenuBarPreferenceKeys.itemSpacing) private var itemSpacing = MenuBarDisplaySettings.defaultItemSpacing
    @AppStorage(MenuBarPreferenceKeys.rowSpacing) private var rowSpacing = MenuBarDisplaySettings.defaultRowSpacing
    @AppStorage(MenuBarPreferenceKeys.numberFontSize) private var numberFontSize = MenuBarDisplaySettings.defaultNumberFontSize
    @AppStorage(MenuBarPreferenceKeys.numberFontWeight) private var numberFontWeight = MenuBarDisplaySettings.defaultNumberFontWeight.rawValue
    @AppStorage(MenuBarPreferenceKeys.goodColorHex) private var goodColorHex = MenuBarDisplaySettings.defaultGoodColorHex
    @AppStorage(MenuBarPreferenceKeys.warningColorHex) private var warningColorHex = MenuBarDisplaySettings.defaultWarningColorHex
    @AppStorage(MenuBarPreferenceKeys.dangerColorHex) private var dangerColorHex = MenuBarDisplaySettings.defaultDangerColorHex

    var body: some View {
        let settings = currentSettings
        VStack(spacing: settings.rowSpacing) {
            statusLine(
                label: viewModel.menuBarPrimaryLabel,
                value: viewModel.menuBarPrimaryValue,
                tone: viewModel.menuBarPrimaryTone,
                settings: settings
            )
            statusLine(
                label: viewModel.menuBarSecondaryLabel,
                value: viewModel.menuBarSecondaryValue,
                tone: viewModel.menuBarSecondaryTone,
                settings: settings
            )
        }
        .frame(width: settings.statusItemWidth, height: settings.statusLabelHeight, alignment: .center)
        .accessibilityLabel(Text("\(viewModel.menuBarPrimaryTitle), \(viewModel.menuBarSecondaryTitle)"))
    }

    private var currentSettings: MenuBarDisplaySettings {
        MenuBarDisplaySettings(
            layoutDensity: MenuBarLayoutDensity(rawValue: layoutDensity) ?? .compact,
            itemSpacing: itemSpacing,
            rowSpacing: rowSpacing,
            numberFontSize: numberFontSize,
            numberFontWeight: MenuBarNumberFontWeight(rawValue: numberFontWeight) ?? .medium,
            goodColorHex: goodColorHex,
            warningColorHex: warningColorHex,
            dangerColorHex: dangerColorHex
        )
    }

    private func statusLine(
        label: String,
        value: String,
        tone: UsageRemainingTone,
        settings: MenuBarDisplaySettings
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: settings.itemSpacing) {
            Text(label)
                .foregroundStyle(.white)
            Text(value)
                .foregroundStyle(tone.statusBarColor(settings: settings))
        }
        .font(.system(size: settings.numberFontSize, weight: settings.numberFontWeight.fontWeight))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
