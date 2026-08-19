import AppKit
import Combine
import CodexMeterShared
import QuartzCore
import Sparkle
import SwiftUI

/// CodexMeter 的程序入口；沿用 AppKit 生命周期以承载菜单栏和设置窗口。
@main
enum CodexMeterMain {
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

/// 在每块屏幕上展示不抢焦点、可穿透点击的原生彩带粒子层。
@MainActor
final class ScreenConfettiOverlayController {
    private var panels: [NSPanel] = []
    private var dismissalTask: Task<Void, Never>?

    /// 按重置窗口类型播放彩带；已有动画尚未结束时忽略重复触发。
    func play(resetType: UsageResetCelebrationOption) {
        guard panels.isEmpty else { return }
        panels = NSScreen.screens.map { screen in
            let panel = ConfettiOverlayPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.contentView = ConfettiEmitterView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                resetType: resetType
            )
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            return panel
        }
        panels.forEach { $0.orderFrontRegardless() }
        let dismissalSeconds: Double = resetType == .weekly ? 5 : 3
        dismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(dismissalSeconds))
            self?.dismiss()
        }
    }

    /// 关闭所有屏幕上的覆盖层并释放粒子视图。
    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        panels.forEach {
            $0.orderOut(nil)
            $0.close()
        }
        panels.removeAll()
    }
}

/// 彩带覆盖面板永不成为主窗口，避免预览时打断键盘输入。
private final class ConfettiOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 使用 Core Animation 自带粒子发射器绘制彩带，不引入额外动画依赖。
private final class ConfettiEmitterView: NSView {
    private let emitter = CAEmitterLayer()
    private let resetType: UsageResetCelebrationOption

    /// 创建指定重置类型的透明粒子视图并立即准备短促喷发。
    init(frame frameRect: NSRect, resetType: UsageResetCelebrationOption) {
        self.resetType = resetType
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        configureEmitter()
    }

    /// 该视图只由代码创建，不支持归档恢复。
    required init?(coder: NSCoder) {
        nil
    }

    /// 屏幕尺寸变化时按窗口类型将彩带发射线定位到顶部中央或右上角。
    override func layout() {
        super.layout()
        emitter.frame = bounds
        let isWeekly = resetType == .weekly
        let sessionEmitterWidth = min(bounds.width, 420)
        emitter.emitterPosition = CGPoint(
            x: isWeekly ? bounds.midX : bounds.maxX - sessionEmitterWidth / 2,
            y: bounds.maxY + 8
        )
        emitter.emitterSize = CGSize(
            width: isWeekly ? bounds.width : sessionEmitterWidth,
            height: 1
        )
    }

    /// 按窗口类型配置喷发强度，粒子随后依靠重力自然飘落。
    private func configureEmitter() {
        emitter.emitterShape = .line
        emitter.emitterMode = .surface
        emitter.renderMode = .unordered
        let colors: [NSColor] = [
            NSColor.systemRed,
            .systemOrange,
            .systemYellow,
            .systemGreen,
            .systemBlue,
            .systemPurple
        ]
        emitter.emitterCells = colors.enumerated().map { index, color in
            let image = resetType == .weekly
                ? Self.particleImage
                : Self.sessionParticleImages[index % Self.sessionParticleImages.count]
            return Self.makeCell(color: color, resetType: resetType, image: image)
        }
        layer?.addSublayer(emitter)
        let emissionDuration: Double = resetType == .weekly ? 0.45 : 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + emissionDuration) { [weak emitter] in
            emitter?.birthRate = 0
        }
    }

    /// 为指定颜色、窗口类型和粒子形状创建彩带粒子。
    private static func makeCell(
        color: NSColor,
        resetType: UsageResetCelebrationOption,
        image: CGImage?
    ) -> CAEmitterCell {
        let isWeekly = resetType == .weekly
        let cell = CAEmitterCell()
        cell.contents = image
        cell.color = color.cgColor
        cell.birthRate = isWeekly ? 22 : 12
        cell.lifetime = isWeekly ? 4.5 : 2.3
        cell.lifetimeRange = isWeekly ? 0.8 : 0.5
        cell.velocity = isWeekly ? 170 : 120
        cell.velocityRange = isWeekly ? 90 : 55
        cell.emissionLongitude = -.pi / 2
        cell.emissionRange = .pi / 5
        cell.yAcceleration = -120
        cell.spin = isWeekly ? 4 : 2
        cell.spinRange = isWeekly ? 8 : 4
        cell.scale = isWeekly ? 0.7 : 0.5
        cell.scaleRange = isWeekly ? 0.35 : 0.22
        return cell
    }

    /// 生成可由粒子颜色着色的白色圆角矩形位图。
    private static let particleImage: CGImage? = {
        let image = NSImage(size: NSSize(width: 10, height: 18))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 10, height: 18), xRadius: 2, yRadius: 2).fill()
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }()

    /// 为 5 小时窗口提供交替使用的圆点和菱形粒子，避免沿用 7 天的矩形彩带。
    private static let sessionParticleImages: [CGImage?] = [
        makeSessionParticleImage(diamond: false),
        makeSessionParticleImage(diamond: true)
    ]

    /// 生成 5 小时窗口使用的圆点或菱形白色位图。
    private static func makeSessionParticleImage(diamond: Bool) -> CGImage? {
        let image = NSImage(size: NSSize(width: 12, height: 12))
        image.lockFocus()
        NSColor.white.setFill()
        if diamond {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 6, y: 0))
            path.line(to: NSPoint(x: 12, y: 6))
            path.line(to: NSPoint(x: 6, y: 12))
            path.line(to: NSPoint(x: 0, y: 6))
            path.close()
            path.fill()
        } else {
            NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 10, height: 10)).fill()
        }
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

/// 应用委托负责组装用量、雷达、菜单栏和设置窗口等长期存活对象。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: UsageViewModel?
    private var radarStore: CodexRadarStore?
    private var statusBarController: StatusBarController?
    private let confettiOverlayController = ScreenConfettiOverlayController()
    private lazy var usageNotificationController = UsageNotificationController { [weak self] resetType in
        self?.confettiOverlayController.play(resetType: resetType)
    }
    private let updater = AppUpdater.shared
    private let settingsWindowOpener = SettingsWindowOpener()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarDisplaySettings.migrateStandardDefaultsToSharedDefaults()
        MenuBarDisplaySettings.migrateLegacyDisplayDefaults()
        updater.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playConfettiPreview(_:)),
            name: .playUsageResetConfettiPreview,
            object: nil
        )
        let viewModel = UsageViewModel(processUsageNotifications: { [usageNotificationController] snapshot in
            usageNotificationController.process(snapshot)
        })
        usageNotificationController.seed(with: viewModel.snapshot)
        let radarStore = CodexRadarStore()
        self.viewModel = viewModel
        self.radarStore = radarStore
        statusBarController = StatusBarController(viewModel: viewModel, radarStore: radarStore)
        viewModel.start()
        radarStore.start()
        if AppBehaviorSettings(defaults: MenuBarDisplaySettings.sharedDefaults).opensSettingsAtLaunch {
            settingsWindowOpener.open()
        }
    }

    /// 响应设置页临时预览按钮，按上方选择播放对应彩带；无单一窗口时沿用 7 天样式。
    @objc private func playConfettiPreview(_ notification: Notification) {
        let resetType: UsageResetCelebrationOption
        switch notification.object as? UsageResetCelebrationOption {
        case .some(.session):
            resetType = .session
        default:
            resetType = .weekly
        }
        confettiOverlayController.play(resetType: resetType)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindowOpener.openForApplicationReopen()
        return true
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let viewModel: UsageViewModel
    private let radarStore: CodexRadarStore
    private let activityStore = CodexHookActivityStore()
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var statusLabel: PassthroughHostingView<StatusBarLabel>?
    private var nativeStatusButtonFont: NSFont?
    private var defaultsObservers: [NSObjectProtocol] = []
    private var usageObserver: AnyCancellable?
    private var activityObserver: AnyCancellable?
    private var preferredPopoverSize = MenuBarPopoverLayout.initialSize
    private var pendingPopoverSize: NSSize?
    private var pendingPopoverSizeWorkItem: DispatchWorkItem?
    private static let popoverResizeDebounceDelay = DispatchTimeInterval.milliseconds(80)

    init(viewModel: UsageViewModel, radarStore: CodexRadarStore) {
        self.viewModel = viewModel
        self.radarStore = radarStore
        let settings = MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        let layout = MenuBarLayoutStore.load()
        let display = MenuBarLayoutDisplay(
            layout: layout,
            snapshot: viewModel.snapshot,
            settings: settings,
            geminiSnapshot: viewModel.geminiSnapshot
        )
        let statusWidth = StatusBarDisplayMetrics.statusItemWidth(
            for: layout,
            display: display,
            settings: settings,
        )
        self.statusItem = NSStatusBar.system.statusItem(withLength: statusWidth)
        super.init()
        activityStore.start()
        configureStatusItem()
        configurePopover()
        observeSettings()
        observeUsageChanges()
        observeActivityChanges()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.title = ""
        button.image = nil
        button.cell?.wraps = false
        button.cell?.usesSingleLineMode = true
        button.cell?.lineBreakMode = .byClipping
        nativeStatusButtonFont = button.font
        button.toolTip = "CodexMeter"
        button.target = self
        button.action = #selector(togglePopover(_:))

        let settings = MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        let layout = MenuBarLayoutStore.load()
        let display = MenuBarLayoutDisplay(
            layout: layout,
            snapshot: viewModel.snapshot,
            settings: settings,
            geminiSnapshot: viewModel.geminiSnapshot
        )
        let statusWidth = StatusBarDisplayMetrics.statusItemWidth(
            for: layout,
            display: display,
            settings: settings,
        )
        let label = PassthroughHostingView(rootView: StatusBarLabel(
            viewModel: viewModel,
            activityStore: activityStore,
            settings: settings,
            statusWidth: statusWidth,
            layout: layout
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
        observeSettingsNotification(.codexRadarSettingsDidChange)
        applySettings()
    }

    /// 统一监听会影响菜单栏或弹窗内容的偏好通知，避免每个设置页分支各自刷新 AppKit 控件。
    private func observeSettingsNotification(_ name: Notification.Name) {
        let observer = NotificationCenter.default.addObserver(
            forName: name,
            // 通知名已经是应用专用，不再依赖 UserDefaults 实例身份过滤。
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
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

    private func observeActivityChanges() {
        activityObserver = activityStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.applyStatusDisplay()
            }
        }
    }

    private func applySettings() {
        let settings = MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        applyStatusDisplay(settings: settings)
        resetPopoverSizeAfterContentChange()
        popover.contentViewController = makePopoverContentController()
        popover.contentSize = preferredPopoverSize
        refreshPopoverSizeFromFittingContent(realign: popover.isShown)
        configurePopoverWindowAppearance()
    }

    /// 设置项会增减下拉内容模块；丢弃上一版高度，避免首次打开沿用旧布局留下大块空白。
    private func resetPopoverSizeAfterContentChange() {
        pendingPopoverSizeWorkItem?.cancel()
        pendingPopoverSizeWorkItem = nil
        pendingPopoverSize = nil
        preferredPopoverSize = MenuBarPopoverLayout.initialSize
    }

    private func applyStatusDisplay(settings: MenuBarDisplaySettings? = nil) {
        let settings = settings ?? MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        let layout = MenuBarLayoutStore.load()
        let display = MenuBarLayoutDisplay(
            layout: layout,
            snapshot: viewModel.snapshot,
            settings: settings,
            geminiSnapshot: viewModel.geminiSnapshot
        )
        let activityDisplay = settings.showsHookActivityLight ? activityStore.display : CodexHookActivityDisplay(snapshot: nil)
        let statusWidth = StatusBarDisplayMetrics.statusItemWidth(
            for: layout,
            display: display,
            settings: settings,
            activityDisplay: activityDisplay,
        )
        statusItem.length = statusWidth
        statusItem.button?.title = ""
        statusItem.button?.attributedTitle = NSAttributedString(string: "")
        statusItem.button?.image = nil
        statusLabel?.isHidden = false
        statusLabel?.rootView = StatusBarLabel(
            viewModel: viewModel,
            activityStore: activityStore,
            settings: settings,
            statusWidth: statusWidth,
            layout: layout
        )
    }

    /// 单行时直接使用系统状态按钮标题；活动图标优先，否则按设置显示 Codex 图标。
    private func applyNativeStatusDisplay(
        line: StatusLineDisplay,
        settings: MenuBarDisplaySettings
    ) {
        guard let button = statusItem.button else { return }
        statusLabel?.isHidden = true
        // 先解除双行的固定宽度，否则 AppKit 会在窄宽度下把单行标题提前换行。
        statusItem.length = NSStatusItem.variableLength
        let nativeFont = nativeStatusButtonFont ?? NSFont.systemFont(ofSize: NativeStatusBarTitle.fontSize)
        let resolvedFont = NativeStatusBarTitle.font(settings: settings, nativeFont: nativeFont)
        button.font = resolvedFont
        button.title = line.label.isEmpty ? line.value : "\(line.label) \(line.value)"
        button.attributedTitle = NativeStatusBarTitle.attributedText(
            for: line,
            settings: settings,
            font: resolvedFont
        )
        button.image = nativeStatusImage(settings: settings)
        button.imagePosition = button.image == nil ? .noImage : .imageLeft
        button.imageScaling = .scaleProportionallyDown
        button.invalidateIntrinsicContentSize()
    }

    /// 原生单行只负责空闲图标；活动状态统一交给 SwiftUI 动效组件。
    private func nativeStatusImage(settings: MenuBarDisplaySettings) -> NSImage? {
        guard settings.showsMenuBarIcon, let image = NSImage(named: "OpenAIStatusIcon")?.copy() as? NSImage else {
            return nil
        }
        image.size = NSSize(
            width: MenuBarDisplaySettings.menuBarIconWidth,
            height: MenuBarDisplaySettings.menuBarIconWidth
        )
        image.isTemplate = true
        return image
    }

    private func makePopoverContentController() -> NSViewController {
        let controller = NSHostingController(
            rootView: MenuBarView(
                viewModel: viewModel,
                radarStore: radarStore,
                updater: AppUpdater.shared
            ) { [weak self] size in
                self?.updatePopoverSize(for: size)
            }
        )
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
        let newSize = clampedPopoverSize(for: contentSize)
        let referenceSize = pendingPopoverSize ?? preferredPopoverSize
        guard abs(referenceSize.width - newSize.width) > 1
            || abs(referenceSize.height - newSize.height) > 1
        else {
            return
        }

        if !popover.isShown {
            applyPopoverSize(newSize, realign: false)
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

        applyPopoverSize(newSize, realign: true)
    }

    /// 从 NSHostingController 的当前适配尺寸主动同步高度，补上 SwiftUI Preference 首帧可能延后的空窗。
    private func refreshPopoverSizeFromFittingContent(realign: Bool) {
        guard let contentView = popover.contentViewController?.view else {
            return
        }
        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
        let fittingSize = contentView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else {
            return
        }
        let newSize = clampedPopoverSize(for: CGSize(
            width: MenuBarPopoverLayout.width,
            height: fittingSize.height
        ))
        guard abs(preferredPopoverSize.width - newSize.width) > 1
            || abs(preferredPopoverSize.height - newSize.height) > 1
        else {
            return
        }
        applyPopoverSize(newSize, realign: realign)
    }

    /// 统一裁剪弹窗尺寸，保证所有测量入口都遵守同一最小值和屏幕最大高度。
    private func clampedPopoverSize(for contentSize: CGSize) -> NSSize {
        let height = min(
            max(ceil(contentSize.height), MenuBarPopoverLayout.minimumHeight),
            maximumPopoverHeight
        )
        return NSSize(width: MenuBarPopoverLayout.width, height: height)
    }

    /// 立即应用弹窗尺寸；打开状态下按菜单栏按钮重新对齐，隐藏状态下只更新下一次打开的缓存。
    private func applyPopoverSize(_ newSize: NSSize, realign: Bool) {
        preferredPopoverSize = newSize
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            popover.contentSize = newSize
            popover.contentViewController?.preferredContentSize = newSize
            configurePopoverWindowAppearance()
            if realign, popover.isShown, let button = statusItem.button {
                alignPopoverWindow(to: button)
            }
        }
    }

    private var maximumPopoverHeight: CGFloat {
        let screenFrame = statusItem.button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let availableHeight = (screenFrame?.height ?? MenuBarPopoverLayout.maximumHeight) - 24
        return max(MenuBarPopoverLayout.minimumHeight, min(MenuBarPopoverLayout.maximumHeight, availableHeight))
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            refreshPopoverSizeFromFittingContent(realign: false)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            configurePopoverWindowAppearance()
            alignPopoverWindow(to: sender)
            activatePopoverWindow()
            Task { await viewModel.refreshLocalCodexUsage() }
            Task { await viewModel.refreshResetCreditsIfNeeded() }
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
    @ObservedObject var activityStore: CodexHookActivityStore
    let settings: MenuBarDisplaySettings
    let statusWidth: CGFloat
    let layout: MenuBarLayout
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
        let display = MenuBarLayoutDisplay(
            layout: layout,
            snapshot: viewModel.snapshot,
            settings: settings,
            geminiSnapshot: viewModel.geminiSnapshot
        )
        let lines = display.codexLines
        let trailingGeminiLines = display.trailingGeminiLines
        let activityDisplay = menuBarActivityDisplay
        return HStack(alignment: .center, spacing: 0) {
            if activityDisplay.isVisible && !layout.containsIcon {
                activityGlyph(activityDisplay)
            }

            HStack(alignment: .center, spacing: CGFloat(settings.itemSpacing)) {
                ForEach(Array(display.items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .trailing, spacing: lineSpacing(settings: settings)) {
                        ForEach(Array(item.enumerated()), id: \.offset) { _, resolvedItem in
                            layoutItemView(
                                resolvedItem,
                                activityDisplay: activityDisplay,
                                usesSingleLineTypography: item.count <= 1
                            )
                        }
                    }
                }
            }

            if !trailingGeminiLines.isEmpty {
                Color.clear
                    .frame(width: StatusBarDisplayMetrics.trailingProviderSeparatorSpacing)
                Image("AntigravityIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(
                        width: StatusBarDisplayMetrics.trailingGeminiIconWidth,
                        height: StatusBarDisplayMetrics.trailingGeminiIconWidth
                    )
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
                Color.clear
                    .frame(width: StatusBarDisplayMetrics.trailingGeminiIconTextSpacing)
                VStack(alignment: .trailing, spacing: lineSpacing(settings: settings)) {
                    ForEach(trailingGeminiLines) { line in
                        statusLine(
                            label: line.label,
                            value: line.value,
                            tone: line.tone,
                            usesUsageColor: line.usesUsageColor,
                            settings: settings,
                            usesSingleLineTypography: trailingGeminiLines.count == 1
                        )
                    }
                }
            }
        }
        .frame(width: statusWidth, height: settings.statusLabelHeight, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(accessibilityText(
                lines: lines,
                trailingGeminiLines: trailingGeminiLines,
                activityDisplay: activityDisplay
            ))
        )
    }

    /// 将自定义项目渲染为 SwiftUI；额度文字沿用原有颜色、字号和无障碍规则。
    @ViewBuilder
    private func layoutItemView(
        _ item: ResolvedMenuBarLayoutItem,
        activityDisplay: CodexHookActivityDisplay,
        usesSingleLineTypography: Bool
    ) -> some View {
        switch item {
        case .icon:
            if activityDisplay.isVisible {
                activityGlyph(activityDisplay)
            } else {
                CodexMenuBarIcon()
            }
        case .geminiIcon:
            Image("AntigravityIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(
                    width: StatusBarDisplayMetrics.trailingGeminiIconWidth,
                    height: StatusBarDisplayMetrics.trailingGeminiIconWidth
                )
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
        case let .line(line):
            statusLine(
                label: line.label,
                value: line.value,
                tone: line.tone,
                usesUsageColor: line.usesUsageColor,
                settings: settings,
                usesSingleLineTypography: usesSingleLineTypography
            )
        case let .usageBar(display):
            MenuBarUsageBarView(
                display: display,
                settings: settings,
                isDisabled: false
            )
        case .separator:
            Text("·")
                .foregroundStyle(.secondary)
                .font(.system(
                    size: statusFontSize(
                        settings: settings,
                        usesSingleLineTypography: usesSingleLineTypography
                    ),
                    weight: statusFontWeight(
                        settings: settings,
                        usesSingleLineTypography: usesSingleLineTypography
                    )
                ))
                .accessibilityHidden(true)
        case .space:
            Color.clear.frame(width: max(4, CGFloat(settings.itemSpacing)))
                .accessibilityHidden(true)
        }
    }

    /// 在布局缺少图标项目时仍保留活动态指示；有图标项目时由该项目复用位置。
    @ViewBuilder
    private func activityGlyph(_ display: CodexHookActivityDisplay) -> some View {
        CodexActivityGlyph(
            display: display,
            style: settings.hookActivityIndicatorStyle,
            size: 16
        )
            .frame(
                width: CodexHookActivityDisplay.menuBarIndicatorWidth,
                height: settings.statusLabelHeight,
                alignment: .center
            )
        Color.clear
            .frame(width: CodexHookActivityDisplay.menuBarIndicatorSpacing)
    }

    /// 设置关闭或 hook 回到空闲时，菜单栏活动指示完全不参与布局。
    private var menuBarActivityDisplay: CodexHookActivityDisplay {
        guard settings.showsHookActivityLight else {
            return CodexHookActivityDisplay(snapshot: nil)
        }
        return activityStore.display
    }

    /// 两行读数沿用行距设置但限制为紧凑值，避免项目高度超过真实菜单栏。
    private func lineSpacing(settings: MenuBarDisplaySettings) -> CGFloat {
        min(CGFloat(settings.rowSpacing), 0)
    }

    private func statusLine(
        label: String,
        value: String,
        tone: UsageRemainingTone,
        usesUsageColor: Bool,
        settings: MenuBarDisplaySettings,
        usesSingleLineTypography: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CGFloat(settings.itemSpacing)) {
            if !label.isEmpty {
                Text(label)
                    .foregroundStyle(.primary)
            }
            Text(value)
                .foregroundStyle(
                    usesUsageColor
                        ? tone.statusBarColor(settings: settings)
                        : Color.primary
                )
        }
        .font(.system(
            size: statusFontSize(settings: settings, usesSingleLineTypography: usesSingleLineTypography),
            weight: statusFontWeight(settings: settings, usesSingleLineTypography: usesSingleLineTypography)
        ).monospacedDigit())
        .fixedSize(horizontal: true, vertical: false)
        .lineLimit(1)
    }

    /// 单行活动态与空闲原生标题使用同一实际字号，双行继续读取双行设置。
    private func statusFontSize(settings: MenuBarDisplaySettings, usesSingleLineTypography: Bool) -> CGFloat {
        usesSingleLineTypography
            ? NativeStatusBarTitle.font(settings: settings).pointSize
            : min(CGFloat(settings.numberFontSize), 9)
    }

    /// 预设单行跟随系统 Regular，自定义单行和双行使用用户选择的字重。
    private func statusFontWeight(settings: MenuBarDisplaySettings, usesSingleLineTypography: Bool) -> Font.Weight {
        if usesSingleLineTypography, MenuBarLayoutChoice.matching(settings: settings) != .custom {
            return .regular
        }
        return settings.numberFontWeight.fontWeight
    }

    /// 组合菜单栏读数和可见 hook 状态，给 VoiceOver 一个完整但不啰嗦的说明。
    private func accessibilityText(
        lines: [StatusLineDisplay],
        trailingGeminiLines: [StatusLineDisplay],
        activityDisplay: CodexHookActivityDisplay
    ) -> String {
        let quotaText = (lines + trailingGeminiLines)
            .map { line in
                line.label.isEmpty ? line.value : "\(line.label) \(line.value)"
            }
            .joined(separator: "，")
        guard activityDisplay.isVisible else {
            return quotaText
        }
        return "\(quotaText)，\(activityDisplay.accessibilityText)"
    }
}

/// 菜单栏上的活动符号；优先使用系统 SF Symbol，并按 hook 状态映射到轻量动画。
private struct CodexActivityGlyph: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let display: CodexHookActivityDisplay
    let style: HookActivityIndicatorStyle
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
            let time = reduceMotion ? 0 : activityTime(for: timeline.date)
            ZStack(alignment: .center) {
                glyphBody(time: time, effect: glyphEffect, speedMultiplier: animationSpeedMultiplier)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }

    /// 根据状态选择刷新频率；低频状态避免在菜单栏里做无意义重绘。
    private var frameInterval: TimeInterval {
        if reduceMotion {
            return 1.0
        }
        let multiplier = animationSpeedMultiplier
        switch glyphEffect {
        case .running:
            return 1.0 / (30.0 * multiplier)
        case .thinking:
            return 1.0 / (24.0 * multiplier)
        case .needsConfirmation:
            return 1.0 / (30.0 * multiplier)
        case .idle, .completed:
            return 1.0 / 18.0
        }
    }

    /// 按 hook 状态选择对应的小型符号动效，避免在菜单栏里混用多个状态语言。
    @ViewBuilder private func glyphBody(
        time: TimeInterval,
        effect: CodexActivityGlyphEffect,
        speedMultiplier: Double
    ) -> some View {
        let color = glyphColor
        switch effect {
        case .idle:
            EmptyView()
        case .running:
            VariableColorSymbolGlyph(
                systemName: "target",
                size: size,
                color: color,
                speed: 1.15 * speedMultiplier,
                reduceMotion: reduceMotion
            )
        case .thinking:
            VerticalEllipsisGlyph(
                size: size,
                color: color,
                speed: 1.25 * speedMultiplier,
                reduceMotion: reduceMotion
            )
        case .needsConfirmation:
            VariableColorSymbolGlyph(
                systemName: "aqi.medium",
                size: size,
                color: color,
                speed: 1.35 * speedMultiplier,
                reduceMotion: reduceMotion
            )
        case .completed:
            CompletionCheckGlyph(size: size, reduceMotion: reduceMotion)
        }
    }

    /// 自动样式按状态切换动效；固定样式则始终使用用户选择的小符号，完成态保留绿色勾线。
    private var glyphEffect: CodexActivityGlyphEffect {
        if display.state == .succeeded || display.state == .completed {
            return .completed
        }
        switch style {
        case .automatic:
            return display.state.glyphEffect
        case .variableDots:
            return .thinking
        case .fanHead:
            return .running
        case .signature:
            return .needsConfirmation
        }
    }

    /// 活动符号颜色始终跟随 hook 状态，和状态灯语义保持一致。
    private var glyphColor: Color {
        switch display.state {
        case .idle:
            return .secondary
        case .thinking, .compacting:
            return .yellow
        case .running:
            return .green
        case .waitingApproval, .failed:
            return .red
        case .succeeded, .completed:
            return .green
        }
    }

    /// 活跃会话越多，状态符号的系统动效越快；封顶避免菜单栏小图标显得刺眼。
    private var animationSpeedMultiplier: Double {
        let extraSessions = max(0, display.activeSessionCount - 1)
        return 0.5 + min(Double(extraSessions) * 0.28, 1.12)
    }

    /// 动画从 hook 快照更新时间起算，让符号动效和 hook 事件触发同步。
    private func activityTime(for date: Date) -> TimeInterval {
        guard let snapshot = display.snapshot else {
            return date.timeIntervalSinceReferenceDate
        }
        return max(0, date.timeIntervalSince1970 - snapshot.updatedAt)
    }
}

/// 思考态使用系统 ellipsis 符号并旋转为竖向，通过 SF Symbols 的可变颜色表达处理进度。
private struct VerticalEllipsisGlyph: View {
    let size: CGFloat
    let color: Color
    let speed: Double
    let reduceMotion: Bool

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: size * 0.92, weight: .heavy, design: .rounded))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color)
            .symbolEffect(
                .variableColor.iterative.reversing,
                options: .repeating.speed(speed),
                isActive: !reduceMotion
            )
            .rotationEffect(.degrees(90))
            .shadow(color: color.opacity(0.18), radius: 1.2, y: 0)
            .frame(width: size, height: size)
    }
}

/// 运行和确认态都使用系统 SF Symbol 的可变颜色动画，避免小尺寸自绘图形造成辨识度下降。
private struct VariableColorSymbolGlyph: View {
    let systemName: String
    let size: CGFloat
    let color: Color
    let speed: Double
    let reduceMotion: Bool

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.98, weight: .heavy, design: .rounded))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color)
            .symbolEffect(
                .variableColor.iterative.reversing,
                options: .repeating.speed(speed),
                isActive: !reduceMotion
            )
            .shadow(color: color.opacity(0.18), radius: 1.2, y: 0)
            .frame(width: size, height: size)
    }
}

/// 完成态使用系统勾选符号，短暂显示后由状态 TTL 隐藏。
private struct CompletionCheckGlyph: View {
    let size: CGFloat
    let reduceMotion: Bool

    var body: some View {
        symbol
            .frame(width: size, height: size)
            .shadow(color: Color.green.opacity(0.24), radius: 1.5, y: 0)
    }

    /// macOS 14 保留完成图标本体，macOS 15 起再启用 indefinite bounce 动效以满足旧系统编译。
    @ViewBuilder private var symbol: some View {
        let image = Image(systemName: "checkmark.circle.fill")
            .font(.system(size: size * 0.96, weight: .heavy, design: .rounded))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.green)
        if #available(macOS 15.0, *) {
            image.symbolEffect(.bounce, options: .speed(1.25), isActive: !reduceMotion)
        } else {
            image
        }
    }
}

private enum CodexActivityGlyphEffect {
    case idle
    case running
    case thinking
    case needsConfirmation
    case completed
}

private extension CodexHookActivityState {
    var glyphEffect: CodexActivityGlyphEffect {
        switch self {
        case .idle:
            return .idle
        case .running:
            return .running
        case .thinking, .compacting:
            return .thinking
        case .waitingApproval, .failed:
            return .needsConfirmation
        case .succeeded, .completed:
            return .completed
        }
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
