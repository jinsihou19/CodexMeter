import AppKit
import Combine
import CodexMeterShared
@preconcurrency import Sparkle
import SwiftUI
import WidgetKit

/// 统一管理静默检测和用户主动安装；定时检测只更新应用内提示，不主动弹出窗口。
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, @MainActor SPUStandardUserDriverDelegate {
    static let shared = AppUpdater()

    @Published private(set) var isUpdateAvailable = false
    @Published private(set) var availableVersion: String?

    lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: self
    )

    private override init() {
        super.init()
    }

    /// 在应用启动时创建更新控制器，后续检测周期由系统更新组件管理。
    func start() {
        _ = controller
    }

    /// 用户点击应用内更新按钮后，才把已发现的更新带到前台。
    func showAvailableUpdate() {
        controller.updater.checkForUpdates()
    }

    /// 记录可安装版本，驱动下拉面板底部出现更新按钮。
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        isUpdateAvailable = true
        availableVersion = item.displayVersionString
    }

    /// 没有可用更新时清除旧提示，避免升级完成后继续显示按钮。
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        isUpdateAvailable = false
        availableVersion = nil
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    /// 定时检测由 CodexMeter 自己显示轻量按钮，禁止标准更新窗口抢占用户注意力。
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    /// Sparkle 把定时发现的版本交给应用后，只更新状态，不展示任何窗口。
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !state.userInitiated else {
            return
        }
        isUpdateAvailable = true
        availableVersion = update.displayVersionString
    }
}

/// 把 Sparkle 的 KVO 检查状态桥接给 SwiftUI，避免更新进行中仍可重复触发。
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    /// 订阅指定更新器的可检查状态；更新器必须由应用级控制器长期持有。
    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

/// 设置页的立即检测入口；只有用户主动操作时才允许出现更新窗口。
struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    /// 绑定应用共享更新器，确保按钮状态和后台更新周期一致。
    init(updater: SPUUpdater) {
        self.updater = updater
        viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button(AppLocalization.string("立即检测"), action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

/// CodexMeter 设置窗口根视图，负责把启动、菜单栏项目、下拉面板、小组件和 Codex 状态分组呈现。
struct SettingsView: View {
    /// 设置侧边栏页面枚举；保持稳定 rawValue，方便未来接入 SceneStorage 或深链。
    private enum Pane: String, CaseIterable, Identifiable {
        case general
        case notifications
        case menuBar
        case popover
        case widget
        case codex
        case about

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .general:
                return "通用"
            case .notifications:
                return "通知"
            case .menuBar:
                return "菜单栏"
            case .popover:
                return "下拉面板"
            case .widget:
                return "小组件"
            case .codex:
                return "Codex"
            case .about:
                return "关于"
            }
        }

        var symbolName: String {
            switch self {
            case .general:
                return "gearshape"
            case .notifications:
                return "bell"
            case .menuBar:
                return "menubar.rectangle"
            case .popover:
                return "macwindow.on.rectangle"
            case .widget:
                return "rectangle.grid.2x2"
            case .codex:
                return "doc.text.magnifyingglass"
            case .about:
                return "info.circle"
            }
        }
    }

    @AppStorage(AppBehaviorPreferenceKeys.opensSettingsAtLaunch, store: MenuBarDisplaySettings.sharedDefaults) private var opensSettingsAtLaunch = AppBehaviorSettings.defaultOpensSettingsAtLaunch
    @AppStorage(AppBehaviorPreferenceKeys.refreshCadence, store: MenuBarDisplaySettings.sharedDefaults) private var refreshCadence = AppBehaviorSettings.defaultRefreshCadence.rawValue
    @AppStorage(AppLanguagePreferenceKeys.selectedLanguage, store: MenuBarDisplaySettings.sharedDefaults) private var selectedLanguage = AppLanguage.system.rawValue
    @AppStorage(UsageNotificationPreferenceKeys.notifiesWhenDepleted, store: MenuBarDisplaySettings.sharedDefaults) private var notifiesWhenDepleted = UsageNotificationSettings.defaultNotifiesWhenDepleted
    @AppStorage(UsageNotificationPreferenceKeys.notifiesWhenLow, store: MenuBarDisplaySettings.sharedDefaults) private var notifiesWhenLow = UsageNotificationSettings.defaultNotifiesWhenLow
    @AppStorage(UsageNotificationPreferenceKeys.lowRemainingThreshold, store: MenuBarDisplaySettings.sharedDefaults) private var lowRemainingThreshold = UsageNotificationSettings.defaultLowRemainingThreshold
    @AppStorage(UsageCelebrationPreferenceKeys.resetOption, store: MenuBarDisplaySettings.sharedDefaults) private var resetCelebrationOption = UsageResetCelebrationOption.off.rawValue
    @AppStorage(CodexRadarPreferenceKeys.isEnabled, store: MenuBarDisplaySettings.sharedDefaults) private var codexRadarEnabled = CodexRadarSettings.defaultIsEnabled
    @AppStorage(CodexRadarPreferenceKeys.showsScoreChart, store: MenuBarDisplaySettings.sharedDefaults) private var codexRadarShowsScoreChart = CodexRadarSettings.defaultShowsScoreChart
    @AppStorage(SurfaceAppearancePreferenceKeys.appearanceMode, store: MenuBarDisplaySettings.sharedDefaults) private var surfaceAppearanceMode = SurfaceAppearanceSettings.defaultAppearanceMode.rawValue
    @AppStorage(SurfaceAppearancePreferenceKeys.cardOpacity, store: MenuBarDisplaySettings.sharedDefaults) private var surfaceCardOpacity = SurfaceAppearanceSettings.defaultCardOpacity

    @AppStorage(MenuBarPreferenceKeys.contentMode, store: MenuBarDisplaySettings.sharedDefaults) private var contentMode = MenuBarDisplaySettings.defaultContentMode.rawValue
    @AppStorage(MenuBarPreferenceKeys.layoutDensity, store: MenuBarDisplaySettings.sharedDefaults) private var layoutDensity = MenuBarDisplaySettings.defaultLayoutDensity.rawValue
    @AppStorage(MenuBarPreferenceKeys.itemSpacing, store: MenuBarDisplaySettings.sharedDefaults) private var itemSpacing = MenuBarDisplaySettings.defaultItemSpacing
    @AppStorage(MenuBarPreferenceKeys.rowSpacing, store: MenuBarDisplaySettings.sharedDefaults) private var rowSpacing = MenuBarDisplaySettings.defaultRowSpacing
    @AppStorage(MenuBarPreferenceKeys.numberFontSize, store: MenuBarDisplaySettings.sharedDefaults) private var numberFontSize = MenuBarDisplaySettings.defaultNumberFontSize
    @AppStorage(MenuBarPreferenceKeys.numberFontWeight, store: MenuBarDisplaySettings.sharedDefaults) private var numberFontWeight = MenuBarDisplaySettings.defaultNumberFontWeight.rawValue
    @AppStorage(MenuBarPreferenceKeys.goodColorHex, store: MenuBarDisplaySettings.sharedDefaults) private var goodColorHex = MenuBarDisplaySettings.defaultGoodColorHex
    @AppStorage(MenuBarPreferenceKeys.warningColorHex, store: MenuBarDisplaySettings.sharedDefaults) private var warningColorHex = MenuBarDisplaySettings.defaultWarningColorHex
    @AppStorage(MenuBarPreferenceKeys.dangerColorHex, store: MenuBarDisplaySettings.sharedDefaults) private var dangerColorHex = MenuBarDisplaySettings.defaultDangerColorHex
    @AppStorage(MenuBarPreferenceKeys.showsPrimaryWindow, store: MenuBarDisplaySettings.sharedDefaults) private var showsPrimaryWindow = MenuBarDisplaySettings.defaultShowsPrimaryWindow
    @AppStorage(MenuBarPreferenceKeys.showsSecondaryWindow, store: MenuBarDisplaySettings.sharedDefaults) private var showsSecondaryWindow = MenuBarDisplaySettings.defaultShowsSecondaryWindow
    @AppStorage(MenuBarPreferenceKeys.showsPercentSymbol, store: MenuBarDisplaySettings.sharedDefaults) private var showsPercentSymbol = MenuBarDisplaySettings.defaultShowsPercentSymbol
    @AppStorage(MenuBarPreferenceKeys.showsMenuBarIcon, store: MenuBarDisplaySettings.sharedDefaults) private var showsMenuBarIcon = MenuBarDisplaySettings.defaultShowsMenuBarIcon
    @AppStorage(MenuBarPreferenceKeys.showsHookActivityLight, store: MenuBarDisplaySettings.sharedDefaults) private var showsHookActivityLight = MenuBarDisplaySettings.defaultShowsHookActivityLight
    @AppStorage(MenuBarPreferenceKeys.hookActivityIndicatorStyle, store: MenuBarDisplaySettings.sharedDefaults) private var hookActivityIndicatorStyle = MenuBarDisplaySettings.defaultHookActivityIndicatorStyle.rawValue
    @AppStorage(MenuBarPreferenceKeys.weeklyProgressWorkDays, store: MenuBarDisplaySettings.sharedDefaults) private var weeklyProgressWorkDays = MenuBarDisplaySettings.defaultWeeklyProgressWorkDays

    @AppStorage(WidgetDisplayPreferenceKeys.contentMode, store: MenuBarDisplaySettings.sharedDefaults) private var widgetContentMode = WidgetDisplaySettings.defaultContentMode.rawValue
    @AppStorage(WidgetDisplayPreferenceKeys.showsResetTime, store: MenuBarDisplaySettings.sharedDefaults) private var widgetShowsResetTime = WidgetDisplaySettings.defaultShowsResetTime
    @AppStorage(WidgetDisplayPreferenceKeys.showsPaceComparison, store: MenuBarDisplaySettings.sharedDefaults) private var widgetShowsPaceComparison = WidgetDisplaySettings.defaultShowsPaceComparison
    @AppStorage(WidgetDisplayPreferenceKeys.showsLastSync, store: MenuBarDisplaySettings.sharedDefaults) private var widgetShowsLastSync = WidgetDisplaySettings.defaultShowsLastSync
    @AppStorage(WidgetDisplayPreferenceKeys.showsPlanLabel, store: MenuBarDisplaySettings.sharedDefaults) private var widgetShowsPlanLabel = WidgetDisplaySettings.defaultShowsPlanLabel

    @AppStorage(PopoverPreferenceKeys.showsPaceComparison, store: MenuBarDisplaySettings.sharedDefaults) private var popoverShowsPaceComparison = PopoverDisplaySettings.defaultShowsPaceComparison
    @AppStorage(PopoverPreferenceKeys.showsProfileOverview, store: MenuBarDisplaySettings.sharedDefaults) private var popoverShowsProfileOverview = PopoverDisplaySettings.defaultShowsProfileOverview
    @AppStorage(PopoverPreferenceKeys.showsTokenActivity, store: MenuBarDisplaySettings.sharedDefaults) private var popoverShowsTokenActivity = PopoverDisplaySettings.defaultShowsTokenActivity
    @AppStorage(PopoverPreferenceKeys.showsActivityInsights, store: MenuBarDisplaySettings.sharedDefaults) private var popoverShowsActivityInsights = PopoverDisplaySettings.defaultShowsActivityInsights
    @AppStorage(PopoverPreferenceKeys.showsTopInvocations, store: MenuBarDisplaySettings.sharedDefaults) private var popoverShowsTopInvocations = PopoverDisplaySettings.defaultShowsTopInvocations
    @AppStorage(PopoverPreferenceKeys.showsSyncDetails, store: MenuBarDisplaySettings.sharedDefaults) private var popoverShowsSyncDetails = PopoverDisplaySettings.defaultShowsSyncDetails
    @AppStorage(PopoverPreferenceKeys.showsAdditionalLimits, store: MenuBarDisplaySettings.sharedDefaults) private var popoverShowsAdditionalLimits = PopoverDisplaySettings.defaultShowsAdditionalLimits
    @AppStorage(PopoverPreferenceKeys.showsResetCredits, store: MenuBarDisplaySettings.sharedDefaults) private var popoverShowsResetCredits = PopoverDisplaySettings.defaultShowsResetCredits
    @AppStorage(PopoverPreferenceKeys.resetTimeDisplayStyle, store: MenuBarDisplaySettings.sharedDefaults) private var popoverResetTimeDisplayStyle = PopoverDisplaySettings.defaultResetTimeDisplayStyle.rawValue

    @State private var selectedPane = Pane.general
    @State private var configurationInfo = CodexConfigurationInfo.current()
    @State private var previewSnapshot: UsageSnapshot?
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?
    @State private var cacheActionMessage: String?
    @State private var menuBarLayoutChoice = MenuBarLayoutChoice.custom
    @Environment(\.colorScheme) private var systemColorScheme
    private let hookActivityURL = CodexHookActivityLocation.activityURL()

    /// 使用应用级 Sparkle 控制器，确保设置页关闭后后台检查仍继续工作。
    private var updater: SPUUpdater {
        AppUpdater.shared.controller.updater
    }

    var body: some View {
        themedContent
    }

    /// 强制浅色或深色时覆盖设置页的 SwiftUI 环境，自动模式继续沿用系统外观。
    @ViewBuilder private var themedContent: some View {
        let mode = currentSurfaceAppearanceSettings.appearanceMode
        let language = AppLanguage(rawValue: selectedLanguage) ?? .system
        let baseContent = content.environment(\.locale, language.locale)
        if let colorScheme = mode.colorScheme {
            baseContent.environment(\.colorScheme, colorScheme)
        } else {
            baseContent
        }
    }

    /// 当前选择直接参与视图渲染，确保切换语言时侧栏和窗口标题同步刷新。
    private var activeLanguage: AppLanguage {
        AppLanguage(rawValue: selectedLanguage) ?? .system
    }

    /// 翻译设置页直接展示的文案，避免依赖偏好存储的再次读取。
    private func localized(_ key: String) -> String {
        AppLocalization.string(key, language: activeLanguage)
    }

    /// 使用原生侧栏和分组表单承载六个稳定入口；只重组呈现，不改变设置存储与通知路径。
    private var content: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            contentPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(
            minWidth: 800,
            idealWidth: SettingsPanelLayout.windowWidth,
            minHeight: 560,
            idealHeight: SettingsPanelLayout.windowHeight
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            normalizeStoredSettings()
            updateLaunchAtLoginState()
            configurationInfo = CodexConfigurationInfo.current()
            loadPreviewSnapshot()
            menuBarLayoutChoice = MenuBarLayoutChoice.matching(settings: currentSettings)
        }
        .onChange(of: selectedLanguage) { _, _ in
            NSApp.keyWindow?.title = localized("CodexMeter 设置")
        }
    }

    /// 从普通图片资源读取当前明暗模式图标，避免非默认 App Icon Set 被构建缓存替换。
    private var settingsApplicationIcon: NSImage {
        let mode = currentSurfaceAppearanceSettings.appearanceMode
        let resourceName = mode.appIconResourceName(systemColorScheme: systemColorScheme)
        return NSImage(named: NSImage.Name(resourceName)) ?? NSApplication.shared.applicationIconImage
    }

    /// 原生侧栏展示六个稳定入口，底部版本入口始终可见并可跳转到关于页。
    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: sidebarSelection) {
                ForEach(Pane.allCases) { pane in
                    Label {
                        Text(localized(pane.title))
                    } icon: {
                        Image(systemName: pane.symbolName)
                    }
                        .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()

            Button {
                selectedPane = .about
            } label: {
                HStack(spacing: 9) {
                    Image(nsImage: settingsApplicationIcon)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(AppVersionDisplay.text())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .help(localized("打开关于"))
        }
        .frame(width: SettingsPanelLayout.sidebarWidth)
    }

    /// List 使用可空选择以支持系统侧栏语义，清空选择时仍保留当前页面。
    private var sidebarSelection: Binding<Pane?> {
        Binding(
            get: { selectedPane },
            set: { pane in
                if let pane {
                    selectedPane = pane
                }
            }
        )
    }

    @ViewBuilder
    private var contentPane: some View {
        switch selectedPane {
        case .general:
            generalPane
        case .notifications:
            notificationsPane
        case .menuBar:
            menuBarPane
        case .popover:
            popoverPane
        case .widget:
            widgetPane
        case .codex:
            codexPane
        case .about:
            aboutPane
        }
    }

    /// 通用页集中系统行为与全局外观，低频微调收进原生折叠组。
    private var generalPane: some View {
        Form {
            Section(AppLocalization.string("系统")) {
                SettingsPickerRow(
                    title: "语言",
                    subtitle: "更改后立即应用；部分系统文案在重新启动后生效。",
                    selection: appLanguageBinding,
                    options: AppLanguage.allCases.map { ($0.rawValue, $0.title) }
                )
                SettingsToggleRow(
                    title: "登录时启动",
                    subtitle: "登录 macOS 后自动启动菜单栏用量组件。",
                    isOn: launchAtLoginBinding
                )

                if let launchAtLoginError {
                    Label(launchAtLoginError, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                SettingsPickerRow(
                    title: "刷新频率",
                    subtitle: "手动模式只在点击下拉面板里的刷新按钮时请求接口。",
                    selection: appBehaviorBinding($refreshCadence, key: AppBehaviorPreferenceKeys.refreshCadence),
                    options: UsageRefreshCadence.allCases.map { ($0.rawValue, $0.title) }
                )
                SettingsPickerRow(
                    title: "界面外观",
                    subtitle: "自动会跟随系统；浅色和深色会强制所有浮层使用对应配色。",
                    selection: surfaceAppearanceBinding(
                        $surfaceAppearanceMode,
                        key: SurfaceAppearancePreferenceKeys.appearanceMode
                    ),
                    options: SurfaceAppearanceMode.allCases.map { ($0.rawValue, $0.title) }
                )
            }

            Section(AppLocalization.string("外观")) {
                SettingsPreferenceRow(title: "状态颜色", subtitle: "选择三档余量状态的配色方案。") {
                    Picker("", selection: colorPresetBinding) {
                        ForEach(MenuBarColorPreset.allCases) { preset in
                            Text(AppLocalization.string(preset.title)).tag(Optional(preset))
                        }
                        Text(AppLocalization.string("自定义")).tag(Optional<MenuBarColorPreset>.none)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                DisclosureGroup(AppLocalization.string("更多选项")) {
                    SettingsToggleRow(
                        title: "启动时打开设置",
                        subtitle: "应用启动后自动显示设置窗口；关闭后仍可从菜单栏进入。",
                        isOn: appBehaviorBinding(
                            $opensSettingsAtLaunch,
                            key: AppBehaviorPreferenceKeys.opensSettingsAtLaunch
                        )
                    )

                    SettingsPreferenceRow(
                        title: "卡片不透明度",
                        subtitle: "统一影响菜单栏下拉面板和小组件的卡片背景。"
                    ) {
                        HStack(spacing: 10) {
                            Slider(
                                value: surfaceAppearanceBinding(
                                    $surfaceCardOpacity,
                                    key: SurfaceAppearancePreferenceKeys.cardOpacity
                                ),
                                in: SurfaceAppearanceSettings.cardOpacityRange,
                                step: 0.05
                            )
                            Text("\(Int((surfaceCardOpacity * 100).rounded()))%")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                        .frame(width: 180)
                    }

                    ColorHexPicker(title: "充足", hex: menuBarBinding($goodColorHex, key: MenuBarPreferenceKeys.goodColorHex))
                    ColorHexPicker(title: "偏低", hex: menuBarBinding($warningColorHex, key: MenuBarPreferenceKeys.warningColorHex))
                    ColorHexPicker(title: "紧张", hex: menuBarBinding($dangerColorHex, key: MenuBarPreferenceKeys.dangerColorHex))
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// 通知页只提供已有用量快照可以可靠判断的提醒，避免展示无实际交付能力的开关。
    private var notificationsPane: some View {
        Form {
            Section(AppLocalization.string("用量提醒")) {
                SettingsToggleRow(
                    title: "额度耗尽提醒",
                    subtitle: "5 小时或 7 天窗口剩余降至 0% 时发送系统通知。",
                    isOn: usageNotificationBinding(
                        $notifiesWhenDepleted,
                        key: UsageNotificationPreferenceKeys.notifiesWhenDepleted
                    )
                )
                SettingsToggleRow(
                    title: "低额度提醒",
                    subtitle: "剩余额度首次降到设定阈值时发送一次系统通知。",
                    isOn: usageNotificationBinding(
                        $notifiesWhenLow,
                        key: UsageNotificationPreferenceKeys.notifiesWhenLow
                    )
                )
                if notifiesWhenLow {
                    SettingsPreferenceRow(title: "提醒阈值", subtitle: "额度恢复到阈值以上后，下一次下降会再次提醒。") {
                        Picker("", selection: $lowRemainingThreshold) {
                            Text("5%").tag(5)
                            Text("10%").tag(10)
                            Text("15%").tag(15)
                            Text("20%").tag(20)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            }

            Section(AppLocalization.string("庆祝")) {
                SettingsPickerRow(
                    title: "重置时播放彩带",
                    subtitle: "额度重置时播放全屏彩带。",
                    selection: $resetCelebrationOption,
                    options: UsageResetCelebrationOption.allCases.map { ($0.rawValue, $0.title) }
                )
                SettingsActionRow(
                    title: "播放彩带",
                    subtitle: "临时入口：立即预览一次全屏彩带。",
                    systemImage: "party.popper"
                ) {
                    NotificationCenter.default.post(name: .playUsageResetConfettiPreview, object: nil)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// 关于页以紧凑分组展示产品身份、更新开关和官方项目入口。
    private var aboutPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Image(nsImage: settingsApplicationIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("CodexMeter")
                            .font(.title2.weight(.bold))
                        Text(AppVersionDisplay.text())
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(AppLocalization.string("让 Codex 剩余额度、重置时间和使用节奏一眼可见。"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox(AppLocalization.string("更新")) {
                    VStack(spacing: 10) {
                        SettingsToggleRow(
                            title: "自动检查更新",
                            subtitle: "",
                            isOn: automaticallyChecksForUpdatesBinding
                        )

                        Divider()

                        HStack(spacing: 12) {
                            Text(updateStatusText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            CheckForUpdatesView(updater: updater)
                        }
                    }
                    .padding(4)
                }

                GroupBox(AppLocalization.string("链接")) {
                    VStack(spacing: 8) {
                        Link(destination: URL(string: "https://github.com/jinsihou19/CodexMeter")!) {
                            Label(AppLocalization.string("GitHub 项目主页"), systemImage: "chevron.left.forwardslash.chevron.right")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Link(destination: URL(string: "https://github.com/jinsihou19/CodexMeter/releases")!) {
                            Label(AppLocalization.string("版本发布记录"), systemImage: "shippingbox")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Divider()

                        Link(destination: URL(string: "https://github.com/jinsihou19/CodexMeter/issues")!) {
                            Label(AppLocalization.string("反馈问题"), systemImage: "exclamationmark.bubble")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(4)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// 把 Sparkle 的自动检查设置直接桥接到开关，沿用其持久化和更新周期管理。
    private var automaticallyChecksForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        )
    }

    /// 关于页只展示当前状态或新版版本号，不暴露更新实现细节。
    private var updateStatusText: String {
        if let version = AppUpdater.shared.availableVersion {
            return "\(AppLocalization.string("发现新版本")) \(version)"
        }
        return AppVersionDisplay.text()
    }

    /// 菜单栏页保留预览与常用内容，只有自定义布局才展开逐项排版控件。
    private var menuBarPane: some View {
        Form {
            Section(AppLocalization.string("预览")) {
                SettingsPreview(
                    settings: currentSettings,
                    data: SettingsPreviewData(snapshot: previewSnapshot)
                )
            }

            Section(AppLocalization.string("显示内容")) {
                SettingsPreferenceRow(title: "菜单栏内容", subtitle: "选择显示剩余额度或相对预期的用量节奏。") {
                    Picker("", selection: menuBarBinding($contentMode, key: MenuBarPreferenceKeys.contentMode)) {
                        ForEach(MenuBarContentMode.allCases) { mode in
                            Text(AppLocalization.string(mode.title)).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                if contentMode == MenuBarContentMode.paceComparison.rawValue {
                    SettingsPreferenceRow(title: "工作日刻度线", subtitle: "用于每周用量条刻度和节奏计算。") {
                        Picker(
                            "",
                            selection: menuBarBinding(
                                $weeklyProgressWorkDays,
                                key: MenuBarPreferenceKeys.weeklyProgressWorkDays
                            )
                        ) {
                            Text(AppLocalization.string("4 天")).tag(4)
                            Text(AppLocalization.string("5 天")).tag(5)
                            Text(AppLocalization.string("7 天")).tag(7)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                SettingsToggleRow(
                    title: "显示 5 小时窗口",
                    subtitle: "在菜单栏显示短窗口剩余额度；至少会保留一个窗口。",
                    isOn: primaryWindowBinding
                )
                SettingsToggleRow(
                    title: "显示 7 天窗口",
                    subtitle: "在菜单栏显示周窗口剩余额度；至少会保留一个窗口。",
                    isOn: secondaryWindowBinding
                )
                SettingsToggleRow(
                    title: "显示 Codex 图标",
                    subtitle: "在数字左侧显示 Codex 图标，便于和其他菜单栏项目区分。",
                    isOn: menuBarBinding($showsMenuBarIcon, key: MenuBarPreferenceKeys.showsMenuBarIcon)
                )
                SettingsToggleRow(
                    title: "显示活动指示",
                    subtitle: "Codex 运行、思考、需确认或刚完成时显示状态符号；空闲时自动隐藏。",
                    isOn: menuBarBinding($showsHookActivityLight, key: MenuBarPreferenceKeys.showsHookActivityLight)
                )
                if showsHookActivityLight {
                    SettingsPickerRow(
                        title: "活动样式",
                        subtitle: "自动会按状态切换；固定样式会一直使用选中的系统符号。",
                        selection: menuBarBinding(
                            $hookActivityIndicatorStyle,
                            key: MenuBarPreferenceKeys.hookActivityIndicatorStyle
                        ),
                        options: HookActivityIndicatorStyle.allCases.map { ($0.rawValue, $0.title) }
                    )
                }
            }

            Section(AppLocalization.string("布局")) {
                SettingsPreferenceRow(title: "布局模式", subtitle: "紧凑和标准会应用稳定预设，自定义保留所有细调能力。") {
                    Picker("", selection: menuBarLayoutChoiceBinding) {
                        ForEach(MenuBarLayoutChoice.allCases) { choice in
                            Text(AppLocalization.string(choice.title)).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                if menuBarLayoutChoice == .custom {
                    SettingsToggleRow(
                        title: "显示百分号",
                        subtitle: "关闭后只显示数字，适合菜单栏空间很紧张时使用。",
                        isOn: menuBarBinding($showsPercentSymbol, key: MenuBarPreferenceKeys.showsPercentSymbol)
                    )
                    DensitySettingRow(layoutDensity: menuBarBinding($layoutDensity, key: MenuBarPreferenceKeys.layoutDensity))
                    SliderSettingRow(
                        title: "项目间距",
                        value: menuBarBinding($itemSpacing, key: MenuBarPreferenceKeys.itemSpacing),
                        range: 0...8,
                        step: 0.5,
                        suffix: "pt"
                    )
                    SliderSettingRow(
                        title: "两行行距",
                        value: menuBarBinding($rowSpacing, key: MenuBarPreferenceKeys.rowSpacing),
                        range: -5...6,
                        step: 0.5,
                        suffix: "pt"
                    )
                    SliderSettingRow(
                        title: "数字字号",
                        value: menuBarBinding($numberFontSize, key: MenuBarPreferenceKeys.numberFontSize),
                        range: 7...13,
                        step: 0.5,
                        suffix: "pt"
                    )
                    SettingsPreferenceRow(title: "数字字重", subtitle: "控制菜单栏读数的视觉重量。") {
                        Picker("", selection: menuBarBinding($numberFontWeight, key: MenuBarPreferenceKeys.numberFontWeight)) {
                            ForEach(MenuBarNumberFontWeight.allCases) { weight in
                                Text(AppLocalization.string(weight.title)).tag(weight.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }
            }

        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// 小组件页只展示用户可配置项，不暴露时间线与缓存文件等实现信息。
    private var widgetPane: some View {
        Form {
            Section(AppLocalization.string("小组件内容")) {
                SettingsPickerRow(
                    title: "显示内容",
                    subtitle: "跟随菜单栏会复用菜单栏的 5 小时 / 7 天窗口选择。",
                    selection: widgetBinding($widgetContentMode, key: WidgetDisplayPreferenceKeys.contentMode),
                    options: WidgetContentMode.allCases.map { ($0.rawValue, $0.title) }
                )
                SettingsToggleRow(
                    title: "显示重置时间",
                    subtitle: "在每行额度旁显示距离窗口重置还有多久。",
                    isOn: widgetBinding($widgetShowsResetTime, key: WidgetDisplayPreferenceKeys.showsResetTime)
                )
                SettingsToggleRow(
                    title: "显示预期消耗速度",
                    subtitle: "在每个窗口下显示节奏偏差，以及预计耗尽或持续到重置。",
                    isOn: widgetBinding($widgetShowsPaceComparison, key: WidgetDisplayPreferenceKeys.showsPaceComparison)
                )
                SettingsToggleRow(
                    title: "显示最近同步",
                    subtitle: "在底部显示最近一次成功读取的时间。",
                    isOn: widgetBinding($widgetShowsLastSync, key: WidgetDisplayPreferenceKeys.showsLastSync)
                )
                SettingsToggleRow(
                    title: "显示账户摘要",
                    subtitle: "在标题栏右侧显示账户邮箱和可读套餐标签。",
                    isOn: widgetBinding($widgetShowsPlanLabel, key: WidgetDisplayPreferenceKeys.showsPlanLabel)
                )
            }

        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// 下拉面板页按用量、活动、洞察、雷达和显示分组，保留全部现有模块开关。
    private var popoverPane: some View {
        Form {
            Section(AppLocalization.string("用量")) {
                SettingsToggleRow(
                    title: "显示用量速度",
                    subtitle: "展示当前用量相对预期节奏是偏快还是有余量。",
                    isOn: popoverBinding(
                        $popoverShowsPaceComparison,
                        key: PopoverPreferenceKeys.showsPaceComparison
                    )
                )
                SettingsToggleRow(
                    title: "显示额外额度",
                    subtitle: "显示 Codex Spark 等接口返回的额外 rate limit。",
                    isOn: popoverBinding(
                        $popoverShowsAdditionalLimits,
                        key: PopoverPreferenceKeys.showsAdditionalLimits
                    )
                )
            }

            Section(AppLocalization.string("活动")) {
                SettingsToggleRow(
                    title: "显示 Profile 概览",
                    subtitle: "展示累计 Token、峰值、最长任务和连续天数。",
                    isOn: popoverBinding(
                        $popoverShowsProfileOverview,
                        key: PopoverPreferenceKeys.showsProfileOverview
                    )
                )
                SettingsToggleRow(
                    title: "显示 Token 活动",
                    subtitle: "展示每日、每周和累计 Token 活动柱状图。",
                    isOn: popoverBinding($popoverShowsTokenActivity, key: PopoverPreferenceKeys.showsTokenActivity)
                )
                SettingsToggleRow(
                    title: "显示额度重置卡",
                    subtitle: "在 Token 活动下方显示可用重置卡数量和到期时间。",
                    isOn: popoverResetCreditsBinding
                )
            }

            Section(AppLocalization.string("洞察")) {
                SettingsToggleRow(
                    title: "显示活动洞察",
                    subtitle: "展示快速模式、推理强度、技能和会话统计。",
                    isOn: popoverBinding(
                        $popoverShowsActivityInsights,
                        key: PopoverPreferenceKeys.showsActivityInsights
                    )
                )
                SettingsToggleRow(
                    title: "显示最常用插件",
                    subtitle: "展示最近统计里最常用的插件或技能。",
                    isOn: popoverBinding($popoverShowsTopInvocations, key: PopoverPreferenceKeys.showsTopInvocations)
                )
            }

            Section(AppLocalization.string("降智雷达")) {
                SettingsToggleRow(
                    title: "开启降智雷达",
                    subtitle: "读取 codexradar.com/current.json 并展示模型 IQ。",
                    isOn: codexRadarBinding($codexRadarEnabled, key: CodexRadarPreferenceKeys.isEnabled)
                )
                if codexRadarEnabled {
                    SettingsToggleRow(
                        title: "显示分值折线图",
                        subtitle: "只绘制 IQ 90 及以上的历史分值。",
                        isOn: codexRadarScoreChartBinding
                    )
                }
            }

            Section(AppLocalization.string("显示")) {
                SettingsToggleRow(
                    title: "显示同步详情",
                    subtitle: "展示限制状态和最近同步时间。",
                    isOn: popoverBinding($popoverShowsSyncDetails, key: PopoverPreferenceKeys.showsSyncDetails)
                )
                SettingsPickerRow(
                    title: "重置时间",
                    subtitle: "倒计时适合快速扫读，具体时间适合规划任务开始时间。",
                    selection: popoverBinding(
                        $popoverResetTimeDisplayStyle,
                        key: PopoverPreferenceKeys.resetTimeDisplayStyle
                    ),
                    options: ResetTimeDisplayStyle.allCases.map { ($0.rawValue, $0.title) }
                )
            }

        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// Codex 页只展示提供商状态与连接入口，低频路径和缓存操作统一折叠到诊断区。
    private var codexPane: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image("OpenAIStatusIcon")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Codex")
                            .font(.title3.weight(.semibold))
                        Label(
                            AppLocalization.string(
                                configurationInfo.authFileExists ? "已连接本机登录信息" : "未找到本机登录信息"
                            ),
                            systemImage: configurationInfo.authFileExists
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(configurationInfo.authFileExists ? .green : .orange)
                    }

                    Spacer(minLength: 12)

                    Button {
                        configurationInfo = CodexConfigurationInfo.current()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(AppLocalization.string("重新读取 Codex 配置"))
                }
            }

            Section(AppLocalization.string("连接")) {
                SettingsCompactActionButton(
                    title: "打开 Codex 目录",
                    subtitle: "在 Finder 中打开 Codex 配置目录。",
                    systemImage: "folder"
                ) {
                    openCodexDirectory()
                }

                DisclosureGroup(AppLocalization.string("连接详情")) {
                    ForEach(configurationInfo.displayRows) { row in
                        SettingsInfoRow(title: row.title, value: row.value)
                    }
                    SettingsInfoRow(title: "读取方式", value: "CODEX_HOME/auth.json 或 ~/.codex/auth.json")
                }
            }

            Section {
                DisclosureGroup(AppLocalization.string("诊断与维护")) {
                    HStack(spacing: SettingsPanelLayout.cardSpacing) {
                        SettingsCompactActionButton(
                            title: "打开缓存目录",
                            subtitle: "在 Finder 中打开快照缓存目录。",
                            systemImage: "externaldrive"
                        ) {
                            openCacheDirectory()
                        }

                        SettingsCompactActionButton(
                            title: "打开状态目录",
                            subtitle: "在 Finder 中打开 hook 活动状态目录。",
                            systemImage: "point.3.connected.trianglepath.dotted"
                        ) {
                            openActivityDirectory()
                        }
                    }

                    SettingsInfoRow(title: "状态文件", value: hookActivityURL.path)
                    SettingsInfoRow(title: "Hook 配置", value: ".codex/hooks.json")
                    SettingsInfoRow(title: "Hook 脚本", value: ".codex/hooks/codex_activity.py")

                    SettingsActionRow(
                        title: "清除最近同步缓存",
                        subtitle: "删除本地最新快照，下次刷新会重新保存。",
                        systemImage: "trash"
                    ) {
                        clearSnapshotCache()
                    }

                    if let cacheActionMessage {
                        Text(cacheActionMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var currentAppBehaviorSettings: AppBehaviorSettings {
        AppBehaviorSettings(
            opensSettingsAtLaunch: opensSettingsAtLaunch,
            refreshCadence: UsageRefreshCadence(rawValue: refreshCadence) ?? .seconds30
        )
    }

    private var currentSurfaceAppearanceSettings: SurfaceAppearanceSettings {
        SurfaceAppearanceSettings(
            appearanceMode: SurfaceAppearanceMode(rawValue: surfaceAppearanceMode)
                ?? SurfaceAppearanceSettings.defaultAppearanceMode,
            cardOpacity: surfaceCardOpacity
        )
    }

    private var currentCodexRadarSettings: CodexRadarSettings {
        CodexRadarSettings(
            isEnabled: codexRadarEnabled,
            showsScoreChart: codexRadarShowsScoreChart
        )
    }

    private var currentSettings: MenuBarDisplaySettings {
        MenuBarDisplaySettings(
            contentMode: MenuBarContentMode(rawValue: contentMode) ?? MenuBarDisplaySettings.defaultContentMode,
            layoutDensity: MenuBarLayoutDensity(rawValue: layoutDensity) ?? .compact,
            itemSpacing: itemSpacing,
            rowSpacing: rowSpacing,
            numberFontSize: numberFontSize,
            numberFontWeight: MenuBarNumberFontWeight(rawValue: numberFontWeight) ?? .medium,
            goodColorHex: goodColorHex,
            warningColorHex: warningColorHex,
            dangerColorHex: dangerColorHex,
            showsPrimaryWindow: showsPrimaryWindow,
            showsSecondaryWindow: showsSecondaryWindow,
            showsPercentSymbol: showsPercentSymbol,
            showsAdditionalLimits: MenuBarDisplaySettings.defaultShowsAdditionalLimits,
            showsMenuBarIcon: showsMenuBarIcon,
            showsHookActivityLight: showsHookActivityLight,
            hookActivityIndicatorStyle: HookActivityIndicatorStyle(rawValue: hookActivityIndicatorStyle)
                ?? MenuBarDisplaySettings.defaultHookActivityIndicatorStyle,
            weeklyProgressWorkDays: weeklyProgressWorkDays
        )
    }

    private var currentWidgetSettings: WidgetDisplaySettings {
        WidgetDisplaySettings(
            contentMode: WidgetContentMode(rawValue: widgetContentMode) ?? WidgetDisplaySettings.defaultContentMode,
            showsResetTime: widgetShowsResetTime,
            showsPaceComparison: widgetShowsPaceComparison,
            showsLastSync: widgetShowsLastSync,
            showsPlanLabel: widgetShowsPlanLabel
        )
    }

    private var currentPopoverSettings: PopoverDisplaySettings {
        PopoverDisplaySettings(
            showsPaceComparison: popoverShowsPaceComparison,
            showsProfileOverview: popoverShowsProfileOverview,
            showsTokenActivity: popoverShowsTokenActivity,
            showsActivityInsights: popoverShowsActivityInsights,
            showsTopInvocations: popoverShowsTopInvocations,
            showsSyncDetails: popoverShowsSyncDetails,
            showsAdditionalLimits: popoverShowsAdditionalLimits,
            showsResetCredits: popoverShowsResetCredits,
            resetTimeDisplayStyle: ResetTimeDisplayStyle(rawValue: popoverResetTimeDisplayStyle) ?? .countdown
        )
    }

    private var selectedColorPreset: MenuBarColorPreset? {
        MenuBarColorPreset.matchingPreset(
            for: (
                goodColorHex: currentSettings.goodColorHex,
                warningColorHex: currentSettings.warningColorHex,
                dangerColorHex: currentSettings.dangerColorHex
            )
        )
    }

    /// 颜色菜单允许显示历史自定义配色；选择预设时沿用原有批量写入与刷新路径。
    private var colorPresetBinding: Binding<MenuBarColorPreset?> {
        Binding(
            get: { selectedColorPreset },
            set: { preset in
                if let preset {
                    applyColorPreset(preset)
                }
            }
        )
    }

    /// 布局模式只负责应用两档公开预设；选择自定义时保留当前字段并展开细调控件。
    private var menuBarLayoutChoiceBinding: Binding<MenuBarLayoutChoice> {
        Binding(
            get: { menuBarLayoutChoice },
            set: { choice in
                menuBarLayoutChoice = choice
                if let preset = choice.preset {
                    applyDisplayPreset(preset)
                }
            }
        )
    }

    /// 语言选择写入共享偏好、更新下次启动覆盖，并立即刷新桌面小组件时间线。
    private var appLanguageBinding: Binding<String> {
        storedBinding($selectedLanguage, key: AppLanguagePreferenceKeys.selectedLanguage) { rawValue in
            (AppLanguage(rawValue: rawValue) ?? .system).apply()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// 开启通知时才向系统请求权限；关闭开关只更新偏好，不重复触发授权流程。
    private func usageNotificationBinding(_ binding: Binding<Bool>, key: String) -> Binding<Bool> {
        storedBinding(binding, key: key) { isEnabled in
            if isEnabled {
                UsageNotificationController.requestAuthorization()
            }
        }
    }

    /// 包装设置控件的写入路径，点击后立即落到共享 defaults，再通知外层界面重读。
    private func storedBinding<Value>(
        _ binding: Binding<Value>,
        key: String,
        didSet: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                binding.wrappedValue = newValue
                MenuBarDisplaySettings.sharedDefaults.set(newValue, forKey: key)
                didSet(newValue)
            }
        )
    }

    /// App 行为设置影响启动和后台刷新任务，写入后要唤醒 UsageViewModel。
    private func appBehaviorBinding<Value>(_ binding: Binding<Value>, key: String) -> Binding<Value> {
        storedBinding(binding, key: key) { _ in
            AppBehaviorSettings.notifyDidChange()
        }
    }

    /// 全局外观会同时影响菜单栏、下拉面板和小组件。
    private func surfaceAppearanceBinding<Value>(_ binding: Binding<Value>, key: String) -> Binding<Value> {
        storedBinding(binding, key: key) { _ in
            SurfaceAppearanceSettings.notifyDidChange()
            SettingsWindowPresenter.shared.applyCurrentAppearance()
            WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
        }
    }

    /// 菜单栏设置被小组件的“跟随菜单栏”模式复用，因此也刷新 WidgetKit 时间线。
    private func menuBarBinding<Value>(_ binding: Binding<Value>, key: String) -> Binding<Value> {
        storedBinding(binding, key: key) { _ in
            notifyMenuBarDisplaySettingsDidChange()
        }
    }

    /// 小组件设置写入后立刻刷新时间线，避免等待系统下一次拉取。
    private func widgetBinding<Value>(_ binding: Binding<Value>, key: String) -> Binding<Value> {
        storedBinding(binding, key: key) { _ in
            notifyWidgetDisplaySettingsDidChange()
        }
    }

    /// 下拉面板模块开关写入后立刻重建 popover 内容。
    private func popoverBinding<Value>(_ binding: Binding<Value>, key: String) -> Binding<Value> {
        storedBinding(binding, key: key) { _ in
            PopoverDisplaySettings.notifyDidChange()
        }
    }

    /// 重置卡开关需要把新状态带给 UsageViewModel，用来决定是否绕过当天缓存。
    private var popoverResetCreditsBinding: Binding<Bool> {
        storedBinding(
            $popoverShowsResetCredits,
            key: PopoverPreferenceKeys.showsResetCredits
        ) { newValue in
            PopoverDisplaySettings.notifyDidChange(showsResetCredits: newValue)
        }
    }

    /// 降智雷达开关影响独立的后台 store，通知后由 store 自己决定是否拉取。
    private func codexRadarBinding<Value>(_ binding: Binding<Value>, key: String) -> Binding<Value> {
        storedBinding(binding, key: key) { _ in
            CodexRadarSettings.notifyDidChange()
        }
    }

    /// 折线图开关发生任何变化时都立即通知 Store 刷新雷达数据。
    private var codexRadarScoreChartBinding: Binding<Bool> {
        storedBinding(
            $codexRadarShowsScoreChart,
            key: CodexRadarPreferenceKeys.showsScoreChart
        ) { _ in
            CodexRadarSettings.notifyDidChange()
        }
    }

    /// 统一发送菜单栏设置变更通知，并同步依赖菜单栏偏好的小组件。
    private func notifyMenuBarDisplaySettingsDidChange() {
        MenuBarDisplaySettings.notifyDidChange()
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
    }

    /// 统一发送小组件设置变更通知，并要求 WidgetKit 马上重建时间线。
    private func notifyWidgetDisplaySettingsDidChange() {
        WidgetDisplaySettings.notifyDidChange()
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginEnabled },
            set: { newValue in
                do {
                    try LaunchAtLoginManager.shared.setEnabled(newValue)
                    launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
                    launchAtLoginError = error.localizedDescription
                }
            }
        )
    }

    private var primaryWindowBinding: Binding<Bool> {
        Binding(
            get: { showsPrimaryWindow },
            set: { newValue in
                showsPrimaryWindow = newValue
                if !newValue && !showsSecondaryWindow {
                    showsSecondaryWindow = true
                }
                MenuBarDisplaySettings.sharedDefaults.set(showsPrimaryWindow, forKey: MenuBarPreferenceKeys.showsPrimaryWindow)
                MenuBarDisplaySettings.sharedDefaults.set(showsSecondaryWindow, forKey: MenuBarPreferenceKeys.showsSecondaryWindow)
                notifyMenuBarDisplaySettingsDidChange()
            }
        )
    }

    private var secondaryWindowBinding: Binding<Bool> {
        Binding(
            get: { showsSecondaryWindow },
            set: { newValue in
                showsSecondaryWindow = newValue
                if !newValue && !showsPrimaryWindow {
                    showsPrimaryWindow = true
                }
                MenuBarDisplaySettings.sharedDefaults.set(showsPrimaryWindow, forKey: MenuBarPreferenceKeys.showsPrimaryWindow)
                MenuBarDisplaySettings.sharedDefaults.set(showsSecondaryWindow, forKey: MenuBarPreferenceKeys.showsSecondaryWindow)
                notifyMenuBarDisplaySettingsDidChange()
            }
        )
    }

    /// 应用菜单栏快速预设，只覆盖排版相关字段，保留用户对内容和颜色的选择。
    private func applyDisplayPreset(_ preset: MenuBarDisplayPreset) {
        let settings = preset.settings
        layoutDensity = settings.layoutDensity.rawValue
        itemSpacing = settings.itemSpacing
        rowSpacing = settings.rowSpacing
        numberFontSize = settings.numberFontSize
        numberFontWeight = settings.numberFontWeight.rawValue
        notifyMenuBarDisplaySettingsDidChange()
    }

    /// 应用全局颜色预设，只覆盖三档余量颜色，菜单栏项目、下拉面板和小组件会共同读取。
    private func applyColorPreset(_ preset: MenuBarColorPreset) {
        let colors = preset.colors
        goodColorHex = colors.goodColorHex
        warningColorHex = colors.warningColorHex
        dangerColorHex = colors.dangerColorHex
        notifyMenuBarDisplaySettingsDidChange()
    }

    /// 读取本地快照用于菜单栏预览；失败时保留占位数据，不阻塞设置窗口。
    private func loadPreviewSnapshot() {
        previewSnapshot = try? UsageSnapshotStore().load()
    }

    /// 用模型初始化器归一化所有 rawValue 设置，避免旧值或手工写入导致 UI 处于未知状态。
    private func normalizeStoredSettings() {
        let appBehavior = currentAppBehaviorSettings
        opensSettingsAtLaunch = appBehavior.opensSettingsAtLaunch
        refreshCadence = appBehavior.refreshCadence.rawValue
        selectedLanguage = (AppLanguage(rawValue: selectedLanguage) ?? .system).rawValue
        let notificationSettings = UsageNotificationSettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        notifiesWhenDepleted = notificationSettings.notifiesWhenDepleted
        notifiesWhenLow = notificationSettings.notifiesWhenLow
        lowRemainingThreshold = notificationSettings.lowRemainingThreshold
        let codexRadarSettings = CodexRadarSettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        codexRadarEnabled = codexRadarSettings.isEnabled
        codexRadarShowsScoreChart = codexRadarSettings.showsScoreChart

        let surfaceAppearance = SurfaceAppearanceSettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        surfaceAppearanceMode = surfaceAppearance.appearanceMode.rawValue
        surfaceCardOpacity = surfaceAppearance.cardOpacity

        let settings = currentSettings
        contentMode = settings.contentMode.rawValue
        layoutDensity = settings.layoutDensity.rawValue
        itemSpacing = settings.itemSpacing
        rowSpacing = settings.rowSpacing
        numberFontSize = settings.numberFontSize
        numberFontWeight = settings.numberFontWeight.rawValue
        goodColorHex = settings.goodColorHex
        warningColorHex = settings.warningColorHex
        dangerColorHex = settings.dangerColorHex
        showsPrimaryWindow = settings.showsPrimaryWindow
        showsSecondaryWindow = settings.showsSecondaryWindow
        showsPercentSymbol = settings.showsPercentSymbol
        showsMenuBarIcon = settings.showsMenuBarIcon
        showsHookActivityLight = settings.showsHookActivityLight
        hookActivityIndicatorStyle = settings.hookActivityIndicatorStyle.rawValue
        weeklyProgressWorkDays = settings.weeklyProgressWorkDays

        let widgetSettings = currentWidgetSettings
        widgetContentMode = widgetSettings.contentMode.rawValue
        widgetShowsResetTime = widgetSettings.showsResetTime
        widgetShowsPaceComparison = widgetSettings.showsPaceComparison
        widgetShowsLastSync = widgetSettings.showsLastSync
        widgetShowsPlanLabel = widgetSettings.showsPlanLabel

        let popoverSettings = PopoverDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        popoverShowsPaceComparison = popoverSettings.showsPaceComparison
        popoverShowsProfileOverview = popoverSettings.showsProfileOverview
        popoverShowsTokenActivity = popoverSettings.showsTokenActivity
        popoverShowsActivityInsights = popoverSettings.showsActivityInsights
        popoverShowsTopInvocations = popoverSettings.showsTopInvocations
        popoverShowsSyncDetails = popoverSettings.showsSyncDetails
        popoverShowsAdditionalLimits = popoverSettings.showsAdditionalLimits
        popoverShowsResetCredits = popoverSettings.showsResetCredits
        popoverResetTimeDisplayStyle = popoverSettings.resetTimeDisplayStyle.rawValue
    }

    /// 刷新登录项开关状态；系统可能在设置窗口外改变注册状态。
    private func updateLaunchAtLoginState() {
        launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
    }

    /// 在 Finder 中打开 Codex 配置目录，便于用户确认 auth.json 是否存在。
    private func openCodexDirectory() {
        openDirectory(URL(fileURLWithPath: configurationInfo.codexHomePath, isDirectory: true))
    }

    /// 在 Finder 中打开快照缓存目录，便于用户定位 widget 读取的最新数据。
    private func openCacheDirectory() {
        openDirectory(UsageSnapshotStore().snapshotURL().deletingLastPathComponent())
    }

    /// 在 Finder 中打开 hook 活动状态目录，便于确认脚本是否正在写入 JSON。
    private func openActivityDirectory() {
        openDirectory(hookActivityURL.deletingLastPathComponent())
    }

    /// 删除最近同步快照并刷新小组件，让“暂无数据”状态立即可见。
    private func clearSnapshotCache() {
        do {
            try UsageSnapshotStore().deleteSnapshot()
            previewSnapshot = nil
            cacheActionMessage = localized("最近同步缓存已清除。")
            WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
        } catch {
            cacheActionMessage = "\(localized("清除失败：")) \(error.localizedDescription)"
        }
    }

    /// 打开目录前确保目录存在；创建失败时交给 NSWorkspace 安静忽略，避免设置页崩溃。
    private func openDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
