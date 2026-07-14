import AppKit
import Combine
import CodexMeterShared
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

/// 应用委托负责组装用量、雷达、菜单栏和设置窗口等长期存活对象。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewModel: UsageViewModel?
    private var radarStore: CodexRadarStore?
    private var statusBarController: StatusBarController?
    private let updater = AppUpdater.shared
    private let settingsWindowOpener = SettingsWindowOpener()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarDisplaySettings.migrateStandardDefaultsToSharedDefaults()
        MenuBarDisplaySettings.migrateLegacyDisplayDefaults()
        let viewModel = UsageViewModel()
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
        let lines = StatusLineDisplay.lines(viewModel: viewModel, settings: settings)
        let statusWidth = StatusBarDisplayMetrics.statusItemWidth(for: lines, settings: settings)
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
        button.toolTip = "CodexMeter"
        button.target = self
        button.action = #selector(togglePopover(_:))

        let settings = MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        let lines = StatusLineDisplay.lines(viewModel: viewModel, settings: settings)
        let statusWidth = StatusBarDisplayMetrics.statusItemWidth(for: lines, settings: settings)
        let label = PassthroughHostingView(rootView: StatusBarLabel(
            viewModel: viewModel,
            activityStore: activityStore,
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
        observeSettingsNotification(.codexRadarSettingsDidChange)
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
        let lines = StatusLineDisplay.lines(viewModel: viewModel, settings: settings)
        let activityDisplay = settings.showsHookActivityLight ? activityStore.display : CodexHookActivityDisplay(snapshot: nil)
        let statusWidth = StatusBarDisplayMetrics.statusItemWidth(
            for: lines,
            settings: settings,
            activityDisplay: activityDisplay
        )
        statusItem.length = statusWidth
        statusLabel?.rootView = StatusBarLabel(
            viewModel: viewModel,
            activityStore: activityStore,
            settings: settings,
            statusWidth: statusWidth
        )
    }

    private func makePopoverContentController() -> NSViewController {
        let controller = NSHostingController(
            rootView: MenuBarView(viewModel: viewModel, radarStore: radarStore) { [weak self] size in
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
        let activityDisplay = menuBarActivityDisplay
        return HStack(alignment: .center, spacing: 0) {
            if activityDisplay.isVisible {
                CodexActivityGlyph(
                    display: activityDisplay,
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

            if showsCodexIcon(activityDisplay: activityDisplay) {
                CodexMenuBarIcon()
                Color.clear
                    .frame(width: MenuBarDisplaySettings.menuBarIconTextSpacing)
            }

            VStack(alignment: .trailing, spacing: lineSpacing(settings: settings)) {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText(lines: lines, activityDisplay: activityDisplay)))
    }

    /// 设置关闭或 hook 回到空闲时，菜单栏活动指示完全不参与布局。
    private var menuBarActivityDisplay: CodexHookActivityDisplay {
        guard settings.showsHookActivityLight else {
            return CodexHookActivityDisplay(snapshot: nil)
        }
        return activityStore.display
    }

    /// 活动符号出现时复用 Codex 图标位置，避免菜单栏左侧同时展示两个识别图标。
    private func showsCodexIcon(activityDisplay: CodexHookActivityDisplay) -> Bool {
        settings.showsMenuBarIcon && !activityDisplay.isVisible
    }

    /// 所有两行菜单栏读数都使用同一行距设置，保证预设和滑块对 Pace 同样生效。
    private func lineSpacing(settings: MenuBarDisplaySettings) -> CGFloat {
        CGFloat(settings.rowSpacing)
    }

    /// 菜单栏字号完全跟随设置页，避免同一设置在不同显示模式下产生意外差异。
    private func fontSize(settings: MenuBarDisplaySettings) -> CGFloat {
        CGFloat(settings.numberFontSize)
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
        HStack(alignment: .firstTextBaseline, spacing: CGFloat(settings.itemSpacing)) {
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

    /// 组合菜单栏读数和可见 hook 状态，给 VoiceOver 一个完整但不啰嗦的说明。
    private func accessibilityText(
        lines: [StatusLineDisplay],
        activityDisplay: CodexHookActivityDisplay
    ) -> String {
        let quotaText = lines
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
