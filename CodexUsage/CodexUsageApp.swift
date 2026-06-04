import AppKit
import CodexUsageShared
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
        MenuBarDisplaySettings.migrateStandardDefaultsToSharedDefaults()
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
    private var statusLabel: PassthroughHostingView<StatusBarLabel>?
    private var defaultsObservers: [NSObjectProtocol] = []

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(
            withLength: MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults).statusItemWidth
        )
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

        let label = PassthroughHostingView(rootView: StatusBarLabel(
            viewModel: viewModel,
            settings: MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        ))
        statusLabel = label
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
        popover.contentSize = NSSize(width: 320, height: 455)
        popover.contentViewController = NSHostingController(rootView: MenuBarView(viewModel: viewModel))
    }

    private func observeSettings() {
        let observer = NotificationCenter.default.addObserver(
            forName: .menuBarDisplaySettingsDidChange,
            object: MenuBarDisplaySettings.sharedDefaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applySettings()
            }
        }
        defaultsObservers.append(observer)
        applySettings()
    }

    private func applySettings() {
        let settings = MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        statusItem.length = settings.statusItemWidth
        statusLabel?.rootView = StatusBarLabel(viewModel: viewModel, settings: settings)
        popover.contentViewController = NSHostingController(rootView: MenuBarView(viewModel: viewModel))
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            alignPopoverWindow(to: sender)
            activatePopoverWindow()
        }
    }

    private func alignPopoverWindow(to sender: NSStatusBarButton) {
        guard
            let popoverWindow = popover.contentViewController?.view.window,
            let senderWindow = sender.window
        else {
            return
        }

        let anchorRect = senderWindow.convertToScreen(sender.convert(sender.bounds, to: nil))
        let alignedFrame = MenuBarPopoverPositioning.alignedFrame(
            popoverFrame: popoverWindow.frame,
            anchorScreenRect: anchorRect
        )
        popoverWindow.setFrame(alignedFrame, display: true)
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
    let settings: MenuBarDisplaySettings

    var body: some View {
        let lines = statusLines(settings: settings)
        VStack(spacing: settings.rowSpacing) {
            ForEach(lines) { line in
                statusLine(
                    label: line.label,
                    value: line.value,
                    tone: line.tone,
                    settings: settings
                )
            }
        }
        .frame(width: settings.statusItemWidth, height: settings.statusLabelHeight, alignment: .center)
        .accessibilityLabel(Text(lines.map { "\($0.label) \($0.value)" }.joined(separator: ", ")))
    }

    private func statusLines(settings: MenuBarDisplaySettings) -> [StatusLineDisplay] {
        var lines: [StatusLineDisplay] = []
        if settings.showsPrimaryWindow {
            lines.append(StatusLineDisplay(
                label: viewModel.menuBarPrimaryLabel,
                value: formattedValue(viewModel.menuBarPrimaryValue, settings: settings),
                tone: viewModel.menuBarPrimaryTone
            ))
        }
        if settings.showsSecondaryWindow {
            lines.append(StatusLineDisplay(
                label: viewModel.menuBarSecondaryLabel,
                value: formattedValue(viewModel.menuBarSecondaryValue, settings: settings),
                tone: viewModel.menuBarSecondaryTone
            ))
        }
        if lines.isEmpty {
            lines.append(StatusLineDisplay(
                label: viewModel.menuBarPrimaryLabel,
                value: formattedValue(viewModel.menuBarPrimaryValue, settings: settings),
                tone: viewModel.menuBarPrimaryTone
            ))
        }
        return lines
    }

    private func formattedValue(_ value: String, settings: MenuBarDisplaySettings) -> String {
        guard !settings.showsPercentSymbol, value.hasSuffix("%") else {
            return value
        }
        return String(value.dropLast())
    }

    private func statusLine(
        label: String,
        value: String,
        tone: UsageRemainingTone,
        settings: MenuBarDisplaySettings
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: settings.itemSpacing) {
            Text(label)
                .foregroundStyle(.primary)
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

private struct StatusLineDisplay: Identifiable {
    let label: String
    let value: String
    let tone: UsageRemainingTone

    var id: String {
        label
    }
}

private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
