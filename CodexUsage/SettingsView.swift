import AppKit
import CodexUsageShared
import SwiftUI
import WidgetKit

/// CodexUsage 设置窗口根视图，负责把启动、菜单栏项目、下拉面板、小组件和 Codex 状态分组呈现。
struct SettingsView: View {
    /// 设置侧边栏页面枚举；保持稳定 rawValue，方便未来接入 SceneStorage 或深链。
    private enum Pane: String, CaseIterable, Identifiable {
        case general
        case menuBar
        case popover
        case widget
        case codex
        case advanced

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .general:
                return "常规"
            case .menuBar:
                return "菜单栏项目"
            case .popover:
                return "下拉面板"
            case .widget:
                return "小组件"
            case .codex:
                return "Codex"
            case .advanced:
                return "高级"
            }
        }

        var symbolName: String {
            switch self {
            case .general:
                return "gearshape"
            case .menuBar:
                return "menubar.rectangle"
            case .popover:
                return "macwindow.on.rectangle"
            case .widget:
                return "rectangle.grid.2x2"
            case .codex:
                return "doc.text.magnifyingglass"
            case .advanced:
                return "slider.horizontal.3"
            }
        }
    }

    @AppStorage(AppBehaviorPreferenceKeys.opensSettingsAtLaunch, store: MenuBarDisplaySettings.sharedDefaults) private var opensSettingsAtLaunch = AppBehaviorSettings.defaultOpensSettingsAtLaunch
    @AppStorage(AppBehaviorPreferenceKeys.refreshCadence, store: MenuBarDisplaySettings.sharedDefaults) private var refreshCadence = AppBehaviorSettings.defaultRefreshCadence.rawValue
    @AppStorage(CodexRadarPreferenceKeys.isEnabled, store: MenuBarDisplaySettings.sharedDefaults) private var codexRadarEnabled = CodexRadarSettings.defaultIsEnabled
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
    private let hookActivityURL = CodexHookActivityLocation.activityURL()

    private static let expectedUsageComparisonHelp = """
    预期对比会用「已过窗口时间 / 总窗口时间」算出理论已用比例，再和实际已用比例比较：
    +5%：实际用量比预期多 5%，用得偏快，可能提前耗尽。
    -10%：实际用量比预期少 10%，还有余量。
    0% 或接近 0：基本按正常节奏使用。

    菜单栏选择「预期消耗对比」时：
    7 天窗口的理论已用达到 3% 以后，第一行显示 5 小时剩余额度，第二行显示 7 天预期偏差。
    低于 3% 时隐藏预期偏差，改为显示剩余额度，避免刚重置后少量用量造成夸张读数。

    下拉面板里的「用量速度」会分别计算 5 小时和 7 天窗口。
    每个窗口都要理论已用达到 3% 才显示；低于 3% 的窗口会暂时隐藏。
    详情会在能估算时显示「预计多久后用完」或「可持续到重置」。
    """

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(alignment: .top, spacing: 0) {
                sidebar

                Divider()

                ScrollView {
                    contentPane
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 820, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            selectedPane = .general
            normalizeStoredSettings()
            updateLaunchAtLoginState()
            configurationInfo = CodexConfigurationInfo.current()
            loadPreviewSnapshot()
        }
        .onChange(of: currentSettings) { _, _ in
            MenuBarDisplaySettings.notifyDidChange()
            WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
        }
        .onChange(of: currentAppBehaviorSettings) { _, _ in
            AppBehaviorSettings.notifyDidChange()
        }
        .onChange(of: currentCodexRadarSettings) { _, _ in
            CodexRadarSettings.notifyDidChange()
        }
        .onChange(of: currentSurfaceAppearanceSettings) { _, _ in
            SurfaceAppearanceSettings.notifyDidChange()
            WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
        }
        .onChange(of: currentWidgetSettings) { _, _ in
            WidgetDisplaySettings.notifyDidChange()
            WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
        }
        .onChange(of: currentPopoverSettings) { _, settings in
            PopoverDisplaySettings.notifyDidChange(showsResetCredits: settings.showsResetCredits)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex 用量")
                    .font(.headline.weight(.semibold))
            }

            Spacer()

            if let previewSnapshot {
                SettingsAccountSummary(snapshot: previewSnapshot)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Pane.allCases) { pane in
                Button {
                    selectedPane = pane
                } label: {
                    Label(pane.title, systemImage: pane.symbolName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .buttonStyle(SettingsSidebarButtonStyle(isSelected: selectedPane == pane))
            }

            Spacer()
        }
        .padding(14)
        .frame(width: SettingsPanelLayout.sidebarWidth)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    @ViewBuilder
    private var contentPane: some View {
        switch selectedPane {
        case .general:
            generalPane
        case .menuBar:
            menuBarPane
        case .popover:
            popoverPane
        case .widget:
            widgetPane
        case .codex:
            codexPane
        case .advanced:
            advancedPane
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: SettingsPanelLayout.sectionSpacing) {
            SettingsSection(title: "启动", subtitle: "控制应用什么时候主动出现") {
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

                SettingsToggleRow(
                    title: "启动时打开设置",
                    subtitle: "应用启动后自动显示设置窗口；关闭后仍可从菜单栏进入。",
                    isOn: $opensSettingsAtLaunch
                )
            }

            SettingsSection(title: "同步", subtitle: "控制后台读取 Codex 用量的节奏") {
                SettingsPickerRow(
                    title: "刷新频率",
                    subtitle: "手动模式只在点击下拉面板里的刷新按钮时请求接口。",
                    selection: $refreshCadence,
                    options: UsageRefreshCadence.allCases.map { ($0.rawValue, $0.title) }
                )
            }

            SettingsSection(title: "界面外观", subtitle: "统一控制菜单栏项目、下拉面板和桌面小组件") {
                SettingsPickerRow(
                    title: "外观",
                    subtitle: "自动会跟随系统；浅色和深色会强制所有浮层使用对应配色。",
                    selection: $surfaceAppearanceMode,
                    options: SurfaceAppearanceMode.allCases.map { ($0.rawValue, $0.title) }
                )
                SettingsPreferenceRow(
                    title: "卡片不透明度",
                    subtitle: "限制在 20% 到 90%，保留背景通透感但不让内容失去对比。"
                ) {
                    HStack(spacing: 10) {
                        Slider(
                            value: $surfaceCardOpacity,
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

                HStack(spacing: SettingsPanelLayout.cardSpacing) {
                    ForEach(MenuBarColorPreset.allCases) { preset in
                        SettingsPresetCard(
                            title: preset.title,
                            subtitle: preset.summary,
                            systemImage: preset.symbolName,
                            isSelected: selectedColorPreset == preset
                        ) {
                            applyColorPreset(preset)
                        }
                    }
                }

                ColorHexPicker(title: "充足", hex: $goodColorHex)
                ColorHexPicker(title: "偏低", hex: $warningColorHex)
                ColorHexPicker(title: "紧张", hex: $dangerColorHex)
            }
        }
        .settingsContentFrame()
    }

    private var menuBarPane: some View {
        let resetActionState = SettingsResetActionState(settings: currentSettings)

        return VStack(alignment: .leading, spacing: SettingsPanelLayout.sectionSpacing) {
            SettingsSection(
                title: "菜单栏预览",
                subtitle: "浅色、深色和半透明背景下的实际读数",
                isContentFramed: SettingsPanelLayout.previewUsesContentFrame
            ) {
                SettingsPreview(
                    settings: currentSettings,
                    data: SettingsPreviewData(snapshot: previewSnapshot)
                )
            }

            SettingsSection(title: "快速预设", subtitle: "一键调整间距、字号和字重") {
                HStack(spacing: SettingsPanelLayout.cardSpacing) {
                    ForEach(MenuBarDisplayPreset.allCases) { preset in
                        SettingsPresetCard(
                            title: preset.title,
                            subtitle: preset.summary,
                            systemImage: preset.symbolName,
                            isSelected: selectedDisplayPreset == preset
                        ) {
                            applyDisplayPreset(preset)
                        }
                    }
                }
            }

            SettingsSection(title: "显示内容", subtitle: "控制菜单栏里出现的读数") {
                SettingsPreferenceRow(
                    title: "菜单栏内容",
                    subtitle: Self.expectedUsageComparisonHelp
                ) {
                    Picker("", selection: $contentMode) {
                        ForEach(MenuBarContentMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
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
                    title: "显示百分号",
                    subtitle: "关闭后只显示数字，适合菜单栏空间很紧张时使用。",
                    isOn: $showsPercentSymbol
                )
                SettingsToggleRow(
                    title: "显示 Codex 图标",
                    subtitle: "在数字左侧显示 Codex 图标，便于和其他菜单栏项目区分。",
                    isOn: $showsMenuBarIcon
                )
                SettingsToggleRow(
                    title: "显示活动指示",
                    subtitle: "Codex 运行、思考、需确认或刚完成时，在额度数字旁显示小型符号动效；空闲时自动隐藏。",
                    isOn: $showsHookActivityLight
                )
                SettingsPickerRow(
                    title: "活动样式",
                    subtitle: "自动会按状态切换；固定样式会一直使用选中的系统符号，颜色跟随状态。",
                    selection: $hookActivityIndicatorStyle,
                    options: HookActivityIndicatorStyle.allCases.map { ($0.rawValue, $0.title) }
                )
                SettingsPreferenceRow(
                    title: "工作日刻度线",
                    subtitle: "设置用于每周用量条刻度和进度计算的工作日。"
                ) {
                    Picker("", selection: $weeklyProgressWorkDays) {
                        Text("4 天").tag(4)
                        Text("5 天").tag(5)
                        Text("7 天").tag(7)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            SettingsSection(title: "排版", subtitle: "细调菜单栏占位和文字节奏") {
                DensitySettingRow(layoutDensity: $layoutDensity)
                SliderSettingRow(title: "项目间距", value: $itemSpacing, range: 0...8, step: 0.5, suffix: "pt")
                SliderSettingRow(title: "两行行距", value: $rowSpacing, range: -5...6, step: 0.5, suffix: "pt")
                SliderSettingRow(title: "数字字号", value: $numberFontSize, range: 7...13, step: 0.5, suffix: "pt")
            }

            SettingsSection(title: "文字样式", subtitle: "调整菜单栏数字的视觉重量") {
                SettingsPreferenceRow(
                    title: "数字字重",
                    subtitle: "控制菜单栏读数的视觉重量。"
                ) {
                    Picker("", selection: $numberFontWeight) {
                        ForEach(MenuBarNumberFontWeight.allCases) { weight in
                            Text(weight.title).tag(weight.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            if resetActionState.isVisible {
                SettingsActionRow(
                    title: "恢复菜单栏默认",
                    subtitle: "还原菜单栏显示、排版和字重",
                    systemImage: "arrow.counterclockwise",
                    isEnabled: resetActionState.isEnabled
                ) {
                    resetDisplaySettings()
                }
            }
        }
        .settingsContentFrame()
    }

    private var widgetPane: some View {
        VStack(alignment: .leading, spacing: SettingsPanelLayout.sectionSpacing) {
            SettingsSection(title: "小组件内容", subtitle: "这些选项会影响所有 CodexUsage 桌面小组件") {
                SettingsPickerRow(
                    title: "显示内容",
                    subtitle: "跟随菜单栏会复用菜单栏的 5 小时 / 7 天窗口选择。",
                    selection: $widgetContentMode,
                    options: WidgetContentMode.allCases.map { ($0.rawValue, $0.title) }
                )
                SettingsToggleRow(
                    title: "显示重置时间",
                    subtitle: "在每行额度旁显示距离窗口重置还有多久。",
                    isOn: $widgetShowsResetTime
                )
                SettingsToggleRow(
                    title: "显示预期消耗速度",
                    subtitle: "在每个窗口下显示节奏偏差，以及预计耗尽或持续到重置。",
                    isOn: $widgetShowsPaceComparison
                )
                SettingsToggleRow(
                    title: "显示最近同步",
                    subtitle: "在底部显示最近一次成功读取的时间。",
                    isOn: $widgetShowsLastSync
                )
                SettingsToggleRow(
                    title: "显示账户摘要",
                    subtitle: "在标题栏右侧显示账户邮箱和可读套餐标签。",
                    isOn: $widgetShowsPlanLabel
                )
            }

            SettingsSection(title: "刷新", subtitle: "小组件读取最近一次保存的快照") {
                SettingsInfoRow(title: "时间线", value: "设置变化后自动刷新")
                SettingsInfoRow(title: "缓存文件", value: UsageSnapshotStore().snapshotURL().lastPathComponent)
            }
        }
        .settingsContentFrame()
    }

    private var popoverPane: some View {
        VStack(alignment: .leading, spacing: SettingsPanelLayout.sectionSpacing) {
            SettingsSection(title: "下拉面板内容", subtitle: "选择点击菜单栏项目后出现的模块") {
                SettingsCompactToggleRow(
                    title: "显示用量速度",
                    detail: "展示当前用量相对预期节奏是偏快还是有余量。",
                    systemImage: "speedometer",
                    isOn: $popoverShowsPaceComparison
                )
                SettingsCompactToggleRow(
                    title: "显示额外额度",
                    detail: "显示 Codex Spark 等接口返回的额外 rate limit。",
                    systemImage: "plus.circle",
                    isOn: $popoverShowsAdditionalLimits
                )
                SettingsCompactToggleRow(
                    title: "显示 Profile 概览",
                    detail: "展示累计 Token、峰值、最长任务和连续天数。",
                    systemImage: "person.text.rectangle",
                    isOn: $popoverShowsProfileOverview
                )
                SettingsCompactToggleRow(
                    title: "显示 Token 活动",
                    detail: "展示每日、每周和累计 Token 活动柱状图。",
                    systemImage: "chart.bar",
                    isOn: $popoverShowsTokenActivity
                )
                SettingsCompactToggleRow(
                    title: "显示额度重置卡",
                    detail: "在 Token 活动下方显示可用重置卡数量和到期时间。",
                    systemImage: "creditcard",
                    isOn: $popoverShowsResetCredits
                )
                SettingsCompactToggleRow(
                    title: "显示活动洞察",
                    detail: "展示快速模式、推理强度、技能和会话统计。",
                    systemImage: "lightbulb",
                    isOn: $popoverShowsActivityInsights
                )
                SettingsCompactToggleRow(
                    title: "显示最常用插件",
                    detail: "展示最近统计里最常用的插件或技能。",
                    systemImage: "puzzlepiece",
                    isOn: $popoverShowsTopInvocations
                )
                SettingsCompactToggleRow(
                    title: "显示同步详情",
                    detail: "展示限制状态和最近同步时间。",
                    systemImage: "arrow.triangle.2.circlepath",
                    isOn: $popoverShowsSyncDetails
                )
                SettingsCompactToggleRow(
                    title: "开启降智雷达",
                    detail: "读取 codexradar.com/current.json 并在下拉面板绘制 IQ 曲线；工作日 09:00-18:00 每小时拉取一次，其余时间每 4 小时一次。",
                    systemImage: "waveform.path.ecg",
                    isOn: $codexRadarEnabled
                )
            }

            SettingsSection(title: "时间显示", subtitle: "控制下拉面板里的窗口重置文案") {
                SettingsPickerRow(
                    title: "重置时间",
                    subtitle: "倒计时适合快速扫读，具体时间适合规划任务开始时间。",
                    selection: $popoverResetTimeDisplayStyle,
                    options: ResetTimeDisplayStyle.allCases.map { ($0.rawValue, $0.title) }
                )
            }
        }
        .settingsContentFrame()
    }

    private var codexPane: some View {
        VStack(alignment: .leading, spacing: SettingsPanelLayout.sectionSpacing) {
            SettingsSection(title: "连接状态", subtitle: "本机 Codex 登录信息和接口") {
                Label(
                    configurationInfo.authFileExists ? "已找到 Codex 登录信息" : "未找到 Codex 登录信息",
                    systemImage: configurationInfo.authFileExists ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(configurationInfo.authFileExists ? .green : .orange)

                ForEach(configurationInfo.displayRows) { row in
                    SettingsInfoRow(title: row.title, value: row.value)
                }
            }

            SettingsSection(title: "数据来源", subtitle: "本 app 只使用本机 Codex 登录文件和 ChatGPT Codex usage 接口") {
                SettingsInfoRow(title: "读取方式", value: "CODEX_HOME/auth.json 或 ~/.codex/auth.json")
                SettingsInfoRow(title: "刷新频率", value: currentAppBehaviorSettings.refreshCadence.title)
                SettingsInfoRow(title: "小组件", value: "保存成功后自动刷新时间线")
            }

            SettingsSection(title: "Hook 活动指示", subtitle: "Codex 生命周期事件会驱动菜单栏符号动效") {
                SettingsInfoRow(title: "状态文件", value: hookActivityURL.path)
                SettingsInfoRow(title: "Hook 配置", value: ".codex/hooks.json")
                SettingsInfoRow(title: "Hook 脚本", value: ".codex/hooks/codex_activity.py")
            }

            SettingsSection(title: "操作", subtitle: "快速定位配置和缓存", isContentFramed: false) {
                HStack(spacing: SettingsPanelLayout.cardSpacing) {
                    SettingsCompactActionButton(
                        title: "重新读取",
                        subtitle: "重新读取本机 Codex 配置状态。",
                        systemImage: "arrow.clockwise"
                    ) {
                        configurationInfo = CodexConfigurationInfo.current()
                    }

                    SettingsCompactActionButton(
                        title: "打开 Codex 目录",
                        subtitle: "在 Finder 中打开 Codex 配置目录。",
                        systemImage: "folder"
                    ) {
                        openCodexDirectory()
                    }

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
            }
        }
        .settingsContentFrame()
    }

    private var advancedPane: some View {
        VStack(alignment: .leading, spacing: SettingsPanelLayout.sectionSpacing) {
            SettingsSection(title: "维护", subtitle: "清理本地快照或恢复显示偏好", isContentFramed: false) {
                HStack(spacing: SettingsPanelLayout.cardSpacing) {
                    SettingsCompactActionButton(
                        title: "清除最近同步缓存",
                        subtitle: "删除小组件和菜单栏启动时读取的最新快照，下次刷新会重新保存。",
                        systemImage: "trash"
                    ) {
                        clearSnapshotCache()
                    }

                    SettingsCompactActionButton(
                        title: "恢复小组件默认",
                        subtitle: "还原小组件显示内容、同步时间和套餐标签。",
                        systemImage: "rectangle.grid.2x2"
                    ) {
                        resetWidgetSettings()
                    }

                    SettingsCompactActionButton(
                        title: "恢复下拉面板默认",
                        subtitle: "还原下拉面板模块开关和重置时间样式。",
                        systemImage: "macwindow.on.rectangle"
                    ) {
                        resetPopoverSettings()
                    }
                }

                if let cacheActionMessage {
                    Text(cacheActionMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .settingsContentFrame()
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
        CodexRadarSettings(isEnabled: codexRadarEnabled)
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

    private var selectedDisplayPreset: MenuBarDisplayPreset? {
        MenuBarDisplayPreset.matchingPreset(for: currentSettings)
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
    }

    /// 应用全局颜色预设，只覆盖三档余量颜色，菜单栏项目、下拉面板和小组件会共同读取。
    private func applyColorPreset(_ preset: MenuBarColorPreset) {
        let colors = preset.colors
        goodColorHex = colors.goodColorHex
        warningColorHex = colors.warningColorHex
        dangerColorHex = colors.dangerColorHex
        MenuBarDisplaySettings.notifyDidChange()
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
    }

    /// 恢复菜单栏显示默认值，范围限定在状态栏读数本身，不重置全局颜色。
    private func resetDisplaySettings() {
        contentMode = MenuBarDisplaySettings.defaultContentMode.rawValue
        layoutDensity = MenuBarDisplaySettings.defaultLayoutDensity.rawValue
        itemSpacing = MenuBarDisplaySettings.defaultItemSpacing
        rowSpacing = MenuBarDisplaySettings.defaultRowSpacing
        numberFontSize = MenuBarDisplaySettings.defaultNumberFontSize
        numberFontWeight = MenuBarDisplaySettings.defaultNumberFontWeight.rawValue
        showsPrimaryWindow = MenuBarDisplaySettings.defaultShowsPrimaryWindow
        showsSecondaryWindow = MenuBarDisplaySettings.defaultShowsSecondaryWindow
        showsPercentSymbol = MenuBarDisplaySettings.defaultShowsPercentSymbol
        showsMenuBarIcon = MenuBarDisplaySettings.defaultShowsMenuBarIcon
        showsHookActivityLight = MenuBarDisplaySettings.defaultShowsHookActivityLight
        hookActivityIndicatorStyle = MenuBarDisplaySettings.defaultHookActivityIndicatorStyle.rawValue
        weeklyProgressWorkDays = MenuBarDisplaySettings.defaultWeeklyProgressWorkDays
    }

    /// 恢复所有小组件全局偏好，并立刻刷新 WidgetKit 时间线。
    private func resetWidgetSettings() {
        widgetContentMode = WidgetDisplaySettings.defaultContentMode.rawValue
        widgetShowsResetTime = WidgetDisplaySettings.defaultShowsResetTime
        widgetShowsPaceComparison = WidgetDisplaySettings.defaultShowsPaceComparison
        widgetShowsLastSync = WidgetDisplaySettings.defaultShowsLastSync
        widgetShowsPlanLabel = WidgetDisplaySettings.defaultShowsPlanLabel
        WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
    }

    /// 恢复下拉面板模块开关，保持额外额度默认关闭以避免面板过长。
    private func resetPopoverSettings() {
        popoverShowsPaceComparison = PopoverDisplaySettings.defaultShowsPaceComparison
        popoverShowsProfileOverview = PopoverDisplaySettings.defaultShowsProfileOverview
        popoverShowsTokenActivity = PopoverDisplaySettings.defaultShowsTokenActivity
        popoverShowsActivityInsights = PopoverDisplaySettings.defaultShowsActivityInsights
        popoverShowsTopInvocations = PopoverDisplaySettings.defaultShowsTopInvocations
        popoverShowsSyncDetails = PopoverDisplaySettings.defaultShowsSyncDetails
        popoverShowsAdditionalLimits = PopoverDisplaySettings.defaultShowsAdditionalLimits
        popoverShowsResetCredits = PopoverDisplaySettings.defaultShowsResetCredits
        popoverResetTimeDisplayStyle = PopoverDisplaySettings.defaultResetTimeDisplayStyle.rawValue
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
        codexRadarEnabled = CodexRadarSettings(defaults: MenuBarDisplaySettings.sharedDefaults).isEnabled

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
            cacheActionMessage = "最近同步缓存已清除。"
            WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
        } catch {
            cacheActionMessage = "清除失败：\(error.localizedDescription)"
        }
    }

    /// 打开目录前确保目录存在；创建失败时交给 NSWorkspace 安静忽略，避免设置页崩溃。
    private func openDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

/// 设置窗口头部右侧的账户摘要，复用最近同步快照里的邮箱和套餐标签，不主动读取认证文件。
private struct SettingsAccountSummary: View {
    let snapshot: UsageSnapshot

    private var hasDisplayableAccount: Bool {
        snapshot.accountEmail != nil || snapshot.accountPlanDisplayText != nil
    }

    var body: some View {
        if hasDisplayableAccount {
            VStack(alignment: .trailing, spacing: 3) {
                if let email = snapshot.accountEmail {
                    Text(email)
                        .font(.callout.weight(.semibold))
                }

                if let plan = snapshot.accountPlanDisplayText {
                    Text(plan)
                        .font(.callout.weight(.semibold))
                }
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: 260, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("账户信息")
        }
    }
}

private extension View {
    /// 统一设置页正文宽度和内边距，保证六个分类在同一阅读节奏下切换。
    func settingsContentFrame() -> some View {
        self
            .frame(maxWidth: SettingsPanelLayout.contentMaxWidth, alignment: .leading)
            .padding(22)
    }
}
