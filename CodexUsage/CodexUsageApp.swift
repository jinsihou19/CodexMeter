import AppKit
import Combine
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
        MenuBarDisplaySettings.migrateLegacyDisplayDefaults()
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
    private var usageObserver: AnyCancellable?
    private var preferredPopoverSize = MenuBarPopoverLayout.initialSize

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        let initialSettings = MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        let initialLines = StatusLineDisplay.lines(viewModel: viewModel, settings: initialSettings)
        self.statusItem = NSStatusBar.system.statusItem(
            withLength: StatusBarDisplayMetrics.statusItemWidth(for: initialLines, settings: initialSettings)
        )
        super.init()
        configureStatusItem()
        configurePopover()
        observeSettings()
        observeUsageChanges()
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

        let settings = MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        let lines = StatusLineDisplay.lines(viewModel: viewModel, settings: settings)
        let statusWidth = StatusBarDisplayMetrics.statusItemWidth(for: lines, settings: settings)
        let label = PassthroughHostingView(rootView: StatusBarLabel(
            viewModel: viewModel,
            settings: settings,
            statusWidth: statusWidth
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
        popover.contentSize = preferredPopoverSize
        popover.contentViewController = makePopoverContentController()
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

    private func observeUsageChanges() {
        usageObserver = viewModel.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.applyStatusDisplay()
            }
        }
    }

    private func applySettings() {
        let settings = MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        applyStatusDisplay(settings: settings)
        popover.contentViewController = makePopoverContentController()
        popover.contentSize = preferredPopoverSize
    }

    private func applyStatusDisplay(settings: MenuBarDisplaySettings? = nil) {
        let settings = settings ?? MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        let lines = StatusLineDisplay.lines(viewModel: viewModel, settings: settings)
        let statusWidth = StatusBarDisplayMetrics.statusItemWidth(for: lines, settings: settings)
        statusItem.length = statusWidth
        statusLabel?.rootView = StatusBarLabel(viewModel: viewModel, settings: settings, statusWidth: statusWidth)
    }

    private func makePopoverContentController() -> NSViewController {
        let controller = NSHostingController(rootView: MenuBarView(viewModel: viewModel) { [weak self] size in
            self?.updatePopoverSize(for: size)
        })
        controller.preferredContentSize = preferredPopoverSize
        return controller
    }

    private func updatePopoverSize(for contentSize: CGSize) {
        let height = min(
            max(ceil(contentSize.height), MenuBarPopoverLayout.minimumHeight),
            maximumPopoverHeight
        )
        let newSize = NSSize(width: MenuBarPopoverLayout.width, height: height)
        guard abs(preferredPopoverSize.width - newSize.width) > 0.5
            || abs(preferredPopoverSize.height - newSize.height) > 0.5
        else {
            return
        }

        preferredPopoverSize = newSize
        popover.contentSize = newSize
        popover.contentViewController?.preferredContentSize = newSize
        if popover.isShown, let button = statusItem.button {
            alignPopoverWindow(to: button)
        }
    }

    private var maximumPopoverHeight: CGFloat {
        let screenFrame = statusItem.button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let availableHeight = (screenFrame?.height ?? MenuBarPopoverLayout.maximumHeight) - 64
        return max(MenuBarPopoverLayout.minimumHeight, min(MenuBarPopoverLayout.maximumHeight, availableHeight))
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
    let statusWidth: CGFloat

    var body: some View {
        let lines = StatusLineDisplay.lines(viewModel: viewModel, settings: settings)
        HStack(spacing: settings.showsMenuBarIcon ? MenuBarDisplaySettings.menuBarIconTextSpacing : 0) {
            if settings.showsMenuBarIcon {
                CodexMenuBarIcon()
            }

            VStack(alignment: textColumnAlignment, spacing: lineSpacing(settings: settings)) {
                ForEach(lines) { line in
                    statusLine(
                        label: line.label,
                        value: line.value,
                        tone: line.tone,
                        settings: settings
                    )
                }
            }
        }
        .frame(width: statusWidth, height: settings.statusLabelHeight, alignment: .center)
        .accessibilityLabel(Text(lines.map { "\($0.label) \($0.value)" }.joined(separator: ", ")))
    }

    /// 所有两行菜单栏读数都使用同一行距设置，保证预设和滑块对 Pace 同样生效。
    private func lineSpacing(settings: MenuBarDisplaySettings) -> Double {
        settings.rowSpacing
    }

    private var textColumnAlignment: HorizontalAlignment {
        settings.showsMenuBarIcon ? .trailing : .center
    }

    /// 菜单栏字号完全跟随设置页，避免同一设置在不同显示模式下产生意外差异。
    private func fontSize(settings: MenuBarDisplaySettings) -> Double {
        settings.numberFontSize
    }

    private func fontWeight(settings: MenuBarDisplaySettings) -> Font.Weight {
        settings.numberFontWeight.fontWeight
    }

    private func statusLine(
        label: String,
        value: String,
        tone: UsageRemainingTone,
        settings: MenuBarDisplaySettings
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: settings.itemSpacing) {
            if !label.isEmpty {
                Text(label)
                    .foregroundStyle(.primary)
            }
            Text(value)
                .foregroundStyle(tone.statusBarColor(settings: settings))
        }
        .font(.system(size: fontSize(settings: settings), weight: fontWeight(settings: settings)))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }
}

/// 菜单栏可选 Codex/OpenAI 图标，只参与视觉识别，不影响点击区域或可访问读数。
private struct CodexMenuBarIcon: View {
    var body: some View {
        Image("OpenAIStatusIcon")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: MenuBarDisplaySettings.menuBarIconWidth, height: MenuBarDisplaySettings.menuBarIconWidth)
            .foregroundStyle(.primary)
            .accessibilityHidden(true)
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
