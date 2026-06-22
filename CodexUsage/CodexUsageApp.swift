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
        if AppBehaviorSettings(defaults: MenuBarDisplaySettings.sharedDefaults).opensSettingsAtLaunch {
            settingsWindowOpener.open()
        }
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
    private var pendingPopoverSize: NSSize?
    private var pendingPopoverSizeWorkItem: DispatchWorkItem?
    private static let popoverResizeDebounceDelay = DispatchTimeInterval.milliseconds(80)

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
        observeSettingsNotification(.menuBarDisplaySettingsDidChange)
        observeSettingsNotification(.popoverDisplaySettingsDidChange)
        observeSettingsNotification(.widgetDisplaySettingsDidChange)
        observeSettingsNotification(.surfaceAppearanceSettingsDidChange)
        applySettings()
    }

    /// 统一监听会影响菜单栏或弹窗内容的偏好通知，避免每个设置页分支各自刷新 AppKit 控件。
    private func observeSettingsNotification(_ name: Notification.Name) {
        let observer = NotificationCenter.default.addObserver(
            forName: name,
            object: MenuBarDisplaySettings.sharedDefaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applySettings()
            }
        }
        defaultsObservers.append(observer)
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
        pendingPopoverSizeWorkItem?.cancel()
        pendingPopoverSizeWorkItem = nil
        pendingPopoverSize = nil
        popover.contentViewController = makePopoverContentController()
        popover.contentSize = preferredPopoverSize
        configurePopoverWindowAppearance()
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
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        controller.preferredContentSize = preferredPopoverSize
        return controller
    }

    /// 清掉 AppKit 宿主窗口的默认不透明底色，让 SwiftUI 半透明弹窗背景真正透出桌面内容。
    private func configurePopoverWindowAppearance() {
        guard let popoverWindow = popover.contentViewController?.view.window else {
            return
        }
        popoverWindow.isOpaque = false
        popoverWindow.backgroundColor = .clear
        popoverWindow.contentView?.wantsLayer = true
        popoverWindow.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// 接收 SwiftUI 内容实测尺寸，先裁剪到屏幕可用范围，再合并连续变化以避免弹窗抖动。
    private func updatePopoverSize(for contentSize: CGSize) {
        let height = min(
            max(ceil(contentSize.height), MenuBarPopoverLayout.minimumHeight),
            maximumPopoverHeight
        )
        let newSize = NSSize(width: MenuBarPopoverLayout.width, height: height)
        let referenceSize = pendingPopoverSize ?? preferredPopoverSize
        guard abs(referenceSize.width - newSize.width) > 1
            || abs(referenceSize.height - newSize.height) > 1
        else {
            return
        }

        pendingPopoverSize = newSize
        pendingPopoverSizeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.applyPendingPopoverSize()
            }
        }
        pendingPopoverSizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.popoverResizeDebounceDelay, execute: workItem)
    }

    /// 真正应用已稳定的弹窗尺寸；关闭隐式动画，避免系统窗口和 SwiftUI 布局互相追逐。
    private func applyPendingPopoverSize() {
        guard let newSize = pendingPopoverSize else {
            return
        }
        pendingPopoverSize = nil
        pendingPopoverSizeWorkItem = nil
        guard abs(preferredPopoverSize.width - newSize.width) > 1
            || abs(preferredPopoverSize.height - newSize.height) > 1
        else {
            return
        }

        preferredPopoverSize = newSize
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            popover.contentSize = newSize
            popover.contentViewController?.preferredContentSize = newSize
            configurePopoverWindowAppearance()
            if popover.isShown, let button = statusItem.button {
                alignPopoverWindow(to: button)
            }
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
            configurePopoverWindowAppearance()
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
    private var appearanceSettings: SurfaceAppearanceSettings {
        SurfaceAppearanceSettings(defaults: MenuBarDisplaySettings.sharedDefaults)
    }

    var body: some View {
        themedContent
    }

    /// 菜单栏标签跟随全局外观设置，保证浅色/深色强制模式能覆盖系统当前主题。
    @ViewBuilder private var themedContent: some View {
        let activeAppearance = appearanceSettings
        let baseContent = content
        if let colorScheme = activeAppearance.appearanceMode.colorScheme {
            baseContent.environment(\.colorScheme, colorScheme)
        } else {
            baseContent
        }
    }

    private var content: some View {
        let lines = StatusLineDisplay.lines(viewModel: viewModel, settings: settings)
        return HStack(spacing: settings.showsMenuBarIcon ? MenuBarDisplaySettings.menuBarIconTextSpacing : 0) {
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
