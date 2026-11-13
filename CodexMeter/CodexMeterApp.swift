// 应用启动、菜单栏和原生窗口协调；各用量供应商保持独立状态与开关。
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
    /// Hook 调用只写入活动状态后退出；普通启动才创建菜单栏与窗口。
    static func main() {
        if CommandLine.arguments.dropFirst().first == CodexActivityHook.argument {
            CodexActivityHook.run()
            return
        }
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

    /// 启动各供应商独立状态源和菜单入口；Go 的开关与刷新失败不阻塞 Codex 启动。
    func applicationDidFinishLaunching(_ notification: Notification) {
        offerLegacyConfigurationMigration()
        updater.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playConfettiPreview(_:)),
            name: .playUsageResetConfettiPreview,
            object: nil
        )
        let viewModel = UsageViewModel(
            processUsageNotifications: { [usageNotificationController] snapshot in
                usageNotificationController.process(snapshot)
            },
            onGeminiDisabled: { [usageNotificationController] in
                usageNotificationController.disableAntigravity()
            }
        )
        usageNotificationController.seed(with: viewModel.snapshot)
        let radarStore = CodexRadarStore()
        self.viewModel = viewModel
        self.radarStore = radarStore
        statusBarController = StatusBarController(viewModel: viewModel, radarStore: radarStore)
        OpenCodeGoStore.shared.start()
        viewModel.start()
        radarStore.start()
        if AppBehaviorSettings(defaults: MenuBarDisplaySettings.sharedDefaults).opensSettingsAtLaunch {
            settingsWindowOpener.open()
        }
    }

    /// 启动时只询问是否迁移；只有点击“迁移配置”才允许转换、写入或清理旧偏好。
    private func offerLegacyConfigurationMigration() {
        let migration = CodexMeterConfigurationMigration()
        guard migration.shouldPrompt else { return }

        let language = migration.preferredLanguage
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = AppLocalization.string("检测到旧版配置", language: language)
        alert.informativeText = AppLocalization.string(
            "CodexMeter 检测到旧版 CodexUsage 的配置数据。是否迁移显示和偏好设置？缓存、授权和每日请求状态不会迁移。",
            language: language
        )
        alert.addButton(withTitle: AppLocalization.string("迁移配置", language: language))
        alert.addButton(withTitle: AppLocalization.string("暂不迁移", language: language))

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try migration.migrate()
            } catch {
                NSAlert(error: error).runModal()
            }
        } else {
            migration.skip()
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

/// 一份可见内容对应一组缓存帧；不把 Hook 时间戳和工具名纳入图片缓存，避免仅事件元数据变化时重复排版。
private struct StatusBarRenderKey: Equatable {
    let settings: MenuBarDisplaySettings
    let layout: MenuBarLayout
    let display: MenuBarLayoutDisplay
    let activityState: CodexHookActivityState
    let activityIsVisible: Bool
    let size: NSSize
    let scale: CGFloat
    let colorScheme: ColorScheme
    let animates: Bool
}

/// 协调用量状态与原生菜单栏按钮；内容变化时离屏排版，动画时只播放缓存图片。
@MainActor
final class StatusBarController: NSObject {
    private let viewModel: UsageViewModel
    private let radarStore: CodexRadarStore
    private let activityStore = CodexHookActivityStore()
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let statusAnimationLayer = CALayer()
    private var statusAppearanceObserver: NSKeyValueObservation?
    private var renderedStatusColorScheme: ColorScheme?
    private var renderedStatusKey: StatusBarRenderKey?
    private var statusAnimationFrames: [NSImage] = []
    private var statusAnimationSpeed: Double = 1
    private var nativeStatusButtonFont: NSFont?
    private var defaultsObservers: [NSObjectProtocol] = []
    private var openCodeGoObserver: AnyCancellable?
    private var usageObserver: AnyCancellable?
    private var activityObserver: AnyCancellable?
    private var preferredPopoverSize = MenuBarPopoverLayout.initialSize
    private var pendingPopoverSize: NSSize?
    private var pendingPopoverSizeWorkItem: DispatchWorkItem?
    private static let popoverResizeDebounceDelay = DispatchTimeInterval.milliseconds(80)

    /// 创建唯一菜单栏按钮并监听各供应商；初始宽度与后续更新采用相同布局解析。
    init(viewModel: UsageViewModel, radarStore: CodexRadarStore) {
        self.viewModel = viewModel
        self.radarStore = radarStore
        let settings = MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        let layout = MenuBarLayoutStore.load()
        let display = MenuBarLayoutDisplay(
            layout: layout,
            snapshot: viewModel.snapshot,
            settings: settings,
            geminiSnapshot: viewModel.geminiSnapshot,
            openCodeGoEnabled: OpenCodeGoStore.shared.isEnabled,
            openCodeGoSnapshot: OpenCodeGoStore.shared.snapshot
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

    /// 保持原生按钮作为唯一点击入口，并监听外观及辅助功能变化以重绘离屏布局。
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
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.wantsLayer = true
        button.layer?.addSublayer(statusAnimationLayer)
        statusAppearanceObserver = button.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, let button = self.statusItem.button else { return }
                let scheme: ColorScheme = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? .dark : .light
                // 设置原生图片也可能重复通知同一外观，只有明暗真正切换时才重新渲染。
                guard scheme != self.renderedStatusColorScheme else { return }
                self.applyStatusDisplay()
            }
        }
        defaultsObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyStatusDisplay() }
        })
    }

    /// 使用系统标准弹窗外观，让 macOS 26 自动提供与系统一致的 Liquid Glass。
    private func configurePopover() {
        popover.behavior = .transient
        popover.appearance = configuredPopoverAppearance
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

    /// 同时监听 Codex 与 Go，读数或开关改变时重新测量同一个菜单栏项目。
    private func observeUsageChanges() {
        openCodeGoObserver = OpenCodeGoStore.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyStatusDisplay() }
        }
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
        popover.appearance = configuredPopoverAppearance
        popover.contentViewController = makePopoverContentController()
        popover.contentSize = preferredPopoverSize
        refreshPopoverSizeFromFittingContent(realign: popover.isShown)
    }

    /// 设置项会增减下拉内容模块；丢弃上一版高度，避免首次打开沿用旧布局留下大块空白。
    private func resetPopoverSizeAfterContentChange() {
        pendingPopoverSizeWorkItem?.cancel()
        pendingPopoverSizeWorkItem = nil
        pendingPopoverSize = nil
        preferredPopoverSize = MenuBarPopoverLayout.initialSize
    }

    /// 按当前供应商快照离屏生成原生图片；不把 NSHostingView 挂在按钮上，阻断系统截图与布局的反馈循环。
    private func applyStatusDisplay(settings: MenuBarDisplaySettings? = nil) {
        guard let button = statusItem.button else { return }
        let settings = settings ?? MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        let layout = MenuBarLayoutStore.load()
        let display = MenuBarLayoutDisplay(
            layout: layout,
            snapshot: viewModel.snapshot,
            settings: settings,
            geminiSnapshot: viewModel.geminiSnapshot,
            openCodeGoEnabled: OpenCodeGoStore.shared.isEnabled,
            openCodeGoSnapshot: OpenCodeGoStore.shared.snapshot
        )
        let activityDisplay = settings.showsHookActivityLight ? activityStore.display : CodexHookActivityDisplay(snapshot: nil)
        let statusWidth = StatusBarDisplayMetrics.statusItemWidth(
            for: layout,
            display: display,
            settings: settings,
            activityDisplay: activityDisplay,
        )
        if statusItem.length != statusWidth {
            statusItem.length = statusWidth
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animates = activityDisplay.isVisible && !reduceMotion
            && activityDisplay.state != .completed && activityDisplay.state != .succeeded
        let statusView = StatusBarLabel(
            viewModel: viewModel,
            activityStore: activityStore,
            settings: settings,
            statusWidth: statusWidth,
            layout: layout
        )
        let colorScheme: ColorScheme = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark : .light
        renderedStatusColorScheme = colorScheme
        let size = NSSize(width: statusWidth, height: settings.statusLabelHeight)
        let scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let key = StatusBarRenderKey(
            settings: settings, layout: layout, display: display,
            activityState: activityDisplay.state, activityIsVisible: activityDisplay.isVisible,
            size: size, scale: scale, colorScheme: colorScheme, animates: animates
        )
        let framesChanged = renderedStatusKey != key
        if framesChanged {
            let values: [Double] = animates ? [0, 0.5, 1] : [1]
            let images = values.compactMap { value -> CGImage? in
                var frame = statusView
                frame.activityVariableValue = value
                let renderer = ImageRenderer(content: frame.environment(\.colorScheme, colorScheme))
                renderer.scale = scale
                return renderer.cgImage
            }
            guard images.count == values.count, let firstImage = images.first else { return }
            let frames = animates ? MenuBarAnimationFrames.make(keyframes: images, size: size)
                : [NSImage(cgImage: firstImage, size: size)]
            guard !frames.isEmpty else { return }
            statusAnimationFrames = frames
            renderedStatusKey = key
        }
        button.setAccessibilityLabel(statusView.accessibilityText(
            lines: display.codexLines,
            trailingGeminiLines: display.trailingGeminiLines,
            activityDisplay: activityDisplay
        ))
        let previousSpeed = statusAnimationSpeed
        statusAnimationSpeed = CodexActivityGlyph(
            display: activityDisplay, style: settings.hookActivityIndicatorStyle, size: 16
        ).animationSpeed
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        statusAnimationLayer.frame = CGRect(
            x: (button.bounds.width - size.width) / 2,
            y: (button.bounds.height - size.height) / 2,
            width: size.width, height: size.height
        )
        statusAnimationLayer.contentsScale = scale
        statusAnimationLayer.contents = statusAnimationFrames.last?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        CATransaction.commit()
        updateStatusAnimation(isActive: animates, contentChanged: framesChanged || previousSpeed != statusAnimationSpeed)
    }

    /// 由系统合成器播放缓存帧；只在内容或速度变化时重建动画，空闲和减少动态效果立即停止。
    private func updateStatusAnimation(isActive: Bool, contentChanged: Bool) {
        guard isActive else {
            statusAnimationLayer.removeAnimation(forKey: "activity")
            return
        }
        guard contentChanged || statusAnimationLayer.animation(forKey: "activity") == nil else { return }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = statusAnimationFrames.compactMap {
            $0.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        animation.duration = 1 / statusAnimationSpeed
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.calculationMode = .discrete
        statusAnimationLayer.add(animation, forKey: "activity")
    }

    /// 单行时直接使用系统状态按钮标题；活动图标优先，否则按设置显示 Codex 图标。
    private func applyNativeStatusDisplay(
        line: StatusLineDisplay,
        settings: MenuBarDisplaySettings
    ) {
        guard let button = statusItem.button else { return }
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
        let hostingController = NSHostingController(
            rootView: MenuBarView(
                viewModel: viewModel,
                radarStore: radarStore,
                updater: AppUpdater.shared,
                onSizeChange: { [weak self] size in
                    self?.updatePopoverSize(for: size)
                },
                onColorSchemeChange: { [weak self] colorScheme in
                    self?.applyPopoverColorScheme(colorScheme)
                }
            )
        )
        hostingController.preferredContentSize = preferredPopoverSize
        return hostingController
    }

    /// 返回设置指定的弹窗外观；浅色使用振动外观，避免 Aqua 在深色背景上增加不透明白膜。
    private var configuredPopoverAppearance: NSAppearance? {
        switch SurfaceAppearanceSettings(defaults: MenuBarDisplaySettings.sharedDefaults).appearanceMode {
        case .automatic:
            nil
        case .light:
            NSAppearance(named: .vibrantLight)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    /// 同步弹窗文字外观；玻璃统一保持 regular，避免 clear 造成过度透射。
    private func applyPopoverColorScheme(_ colorScheme: ColorScheme) {
        popover.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .vibrantLight
        )
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
            makePopoverWindowTransparent()
            alignPopoverWindow(to: sender)
            activatePopoverWindow()
            Task { await viewModel.refreshLocalCodexUsage() }
            Task { await viewModel.refreshResetCreditsIfNeeded() }
        }
    }

    /// 清除 NSPopover 自带的不透明窗口底色，避免它与内容中的玻璃层重复叠加。
    private func makePopoverWindowTransparent() {
        guard let popoverWindow = popover.contentViewController?.view.window else { return }
        popoverWindow.isOpaque = false
        popoverWindow.backgroundColor = .clear
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

    /// 在弹窗首帧前完成激活，避免系统材质从非活动态闪变到活动态。
    private func activatePopoverWindow() {
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }
}

/// 将统一布局渲染到唯一的菜单栏按钮；文字明暗跟随菜单栏自身外观，各供应商共用排版规则。
private struct StatusBarLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var openCodeGoStore = OpenCodeGoStore.shared
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var activityStore: CodexHookActivityStore
    let settings: MenuBarDisplaySettings
    let statusWidth: CGFloat
    let layout: MenuBarLayout
    var activityVariableValue: Double = 1
    var body: some View {
        content
    }

    /// 渲染已启用的布局项目，Go 和既有供应商共享同一按钮与字体规则。
    private var content: some View {
        let display = MenuBarLayoutDisplay(
            layout: layout,
            snapshot: viewModel.snapshot,
            settings: settings,
            geminiSnapshot: viewModel.geminiSnapshot,
            openCodeGoEnabled: openCodeGoStore.isEnabled,
            openCodeGoSnapshot: openCodeGoStore.snapshot
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
        case .openCodeGoIcon:
            Image("OpenCodeIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: StatusBarDisplayMetrics.trailingGeminiIconWidth, height: StatusBarDisplayMetrics.trailingGeminiIconWidth)
                .accessibilityLabel("OpenCode Go")
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
            size: 16,
            variableValue: activityVariableValue
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
                        ? tone.statusBarColor(settings: settings, colorScheme: colorScheme)
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
    fileprivate func accessibilityText(
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

/// 将 Hook 状态映射为菜单栏符号；活动动画统一交给限频组件，避免系统循环动画持续刷新整块状态栏。
private struct CodexActivityGlyph: View {
    // 离屏渲染没有窗口环境，直接读取系统偏好；控制器监听偏好变更后重绘。
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    let display: CodexHookActivityDisplay
    let style: HookActivityIndicatorStyle
    let size: CGFloat
    var variableValue: Double = 1

    /// 只在活动符号内推进动画；完成和减少动态效果时不保留刷新任务。
    var body: some View {
        ZStack(alignment: .center) {
            glyphBody(effect: glyphEffect)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// 按 hook 状态选择对应的小型符号动效，避免在菜单栏里混用多个状态语言。
    @ViewBuilder private func glyphBody(
        effect: CodexActivityGlyphEffect
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
                variableValue: variableValue
            )
        case .thinking:
            VariableColorSymbolGlyph(
                systemName: "ellipsis",
                size: size,
                color: color,
                variableValue: variableValue
            )
            .rotationEffect(.degrees(90))
        case .needsConfirmation:
            VariableColorSymbolGlyph(
                systemName: "aqi.medium",
                size: size,
                color: color,
                variableValue: variableValue
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
        case .none:
            return .idle
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

    /// 工作使用绿色动效，完成使用静止绿勾；等待和失败分别保留橙色与红色。
    private var glyphColor: Color {
        display.state.indicatorColorHex.map { Color(hexRGB: $0) } ?? .secondary
    }

    /// 活跃会话越多，状态符号的系统动效越快；封顶避免菜单栏小图标显得刺眼。
    fileprivate var animationSpeed: Double {
        let extraSessions = max(0, display.activeSessionCount - 1)
        let multiplier = 0.5 + min(Double(extraSessions) * 0.28, 1.12)
        switch glyphEffect {
        case .running: return 1.15 * multiplier
        case .thinking: return 1.25 * multiplier
        case .idle, .needsConfirmation, .completed: return 1.35 * multiplier
        }
    }
}

/// 渲染单帧系统符号；由原生菜单栏控制器推进进度，视图自身不创建持续运行的动画时钟。
private struct VariableColorSymbolGlyph: View {
    let systemName: String
    let size: CGFloat
    let color: Color
    let variableValue: Double

    /// 只渲染控制器要求的关键帧，不创建动画时钟或读取当前时间。
    var body: some View {
        assert((0...1).contains(variableValue))
        return Image(systemName: systemName, variableValue: variableValue)
            .font(.system(size: size * 0.98, weight: .heavy, design: .rounded))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.18), radius: 1.2, y: 0)
            .frame(width: size, height: size)
    }
}

/// 完成态使用静止的绿色勾选符号，三秒后隐藏；结束后不再播放持续工作式动画。
private struct CompletionCheckGlyph: View {
    let size: CGFloat
    let reduceMotion: Bool

    var body: some View {
        symbol
            .frame(width: size, height: size)
            .shadow(color: Color.green.opacity(0.24), radius: 1.5, y: 0)
    }

    /// 完成只作短暂确认，不播放循环弹跳，以免被误读为任务还在运行。
    @ViewBuilder private var symbol: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: size * 0.96, weight: .heavy, design: .rounded))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color(hexRGB: CodexHookActivityState.completed.indicatorColorHex ?? "#30D158"))
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
