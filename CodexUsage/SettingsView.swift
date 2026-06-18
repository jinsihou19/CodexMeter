import CodexUsageShared
import SwiftUI
import WidgetKit

struct SettingsView: View {
    private enum Pane: String, CaseIterable, Identifiable {
        case display
        case codex

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .display:
                return "显示"
            case .codex:
                return "Codex"
            }
        }

        var symbolName: String {
            switch self {
            case .display:
                return "menubar.rectangle"
            case .codex:
                return "doc.text.magnifyingglass"
            }
        }
    }

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
    @AppStorage(MenuBarPreferenceKeys.showsAdditionalLimits, store: MenuBarDisplaySettings.sharedDefaults) private var showsAdditionalLimits = MenuBarDisplaySettings.defaultShowsAdditionalLimits
    @AppStorage(MenuBarPreferenceKeys.showsMenuBarIcon, store: MenuBarDisplaySettings.sharedDefaults) private var showsMenuBarIcon = MenuBarDisplaySettings.defaultShowsMenuBarIcon

    @State private var selectedPane = Pane.display
    @State private var configurationInfo = CodexConfigurationInfo.current()
    @State private var previewSnapshot: UsageSnapshot?

    private static let expectedUsageComparisonHelp = """
    预期对比会结合当前周期还剩多久，告诉你现在的使用速度是否合理：
    +5%：实际用量比预期多 5%，用得偏快，可能提前耗尽。
    -10%：实际用量比预期少 10%，还有余量。
    0% 或接近 0：基本按正常节奏使用。

    例如一周额度已经过了 50% 的时间，理论上大概应该用到 50%。如果实际已经用了 70%，就会显示大约 +20%，详情里会说类似 20% 亏损，并在能估算时显示「预计多久后用完」或「可持续到重置」。
    """

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(alignment: .top, spacing: 0) {
                sidebar

                Divider()

                ScrollView {
                    switch selectedPane {
                    case .display:
                        displayPane
                    case .codex:
                        codexPane
                    }
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 780, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            selectedPane = .display
            normalizeStoredSettings()
            configurationInfo = CodexConfigurationInfo.current()
            loadPreviewSnapshot()
        }
        .onChange(of: currentSettings) { _, _ in
            MenuBarDisplaySettings.notifyDidChange()
            WidgetCenter.shared.reloadTimelines(ofKind: "CodexUsageWidget")
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
                    .font(.title3.weight(.semibold))
                Text("菜单栏显示与读取状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
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
                .buttonStyle(SettingsSidebarButtonStyle(isSelected: selectedPane == pane))
            }

            Spacer()
        }
        .padding(14)
        .frame(width: SettingsPanelLayout.sidebarWidth)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var displayPane: some View {
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
                HStack(spacing: 12) {
                    HStack(spacing: 5) {
                        Text("菜单栏内容")
                        QuickHelpIcon(text: Self.expectedUsageComparisonHelp)
                    }
                    .frame(width: 98, alignment: .leading)

                    Picker("", selection: $contentMode) {
                        ForEach(MenuBarContentMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("显示 5 小时窗口", isOn: primaryWindowBinding)
                Toggle("显示 7 天窗口", isOn: secondaryWindowBinding)
                Toggle("显示百分号", isOn: $showsPercentSymbol)
                Toggle("显示 Codex 图标", isOn: $showsMenuBarIcon)
                Toggle("显示额外额度", isOn: $showsAdditionalLimits)
            }

            SettingsSection(title: "排版", subtitle: "细调菜单栏占位和文字节奏") {
                DensitySettingRow(layoutDensity: $layoutDensity)
                SliderSettingRow(
                    title: "项目间距",
                    value: $itemSpacing,
                    range: 0...8,
                    step: 0.5,
                    suffix: "pt"
                )
                SliderSettingRow(
                    title: "两行行距",
                    value: $rowSpacing,
                    range: -5...6,
                    step: 0.5,
                    suffix: "pt"
                )
                SliderSettingRow(
                    title: "数字字号",
                    value: $numberFontSize,
                    range: 7...13,
                    step: 0.5,
                    suffix: "pt"
                )
            }

            SettingsSection(title: "数字样式", subtitle: "调整颜色强度和字重") {
                Picker("数字字重", selection: $numberFontWeight) {
                    ForEach(MenuBarNumberFontWeight.allCases) { weight in
                        Text(weight.title).tag(weight.rawValue)
                    }
                }
                .pickerStyle(.segmented)

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

            if resetActionState.isVisible {
                SettingsActionRow(
                    title: "恢复默认",
                    subtitle: "还原菜单栏显示、排版和颜色",
                    systemImage: "arrow.counterclockwise",
                    isEnabled: resetActionState.isEnabled
                ) {
                    resetDisplaySettings()
                }
            }
        }
        .frame(maxWidth: SettingsPanelLayout.contentMaxWidth, alignment: .leading)
        .padding(22)
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

            SettingsSection(title: "同步与缓存", subtitle: "小组件读取最近一次成功同步的数据") {
                SettingsInfoRow(title: "刷新频率", value: "约 30 秒")
                SettingsInfoRow(title: "缓存文件", value: UsageSnapshotStore().snapshotURL().lastPathComponent)
                SettingsInfoRow(title: "小组件", value: "保存成功后自动刷新时间线")
            }

            HStack {
                Button {
                    configurationInfo = CodexConfigurationInfo.current()
                } label: {
                    Label("重新读取", systemImage: "arrow.clockwise")
                }

                Spacer()
            }
        }
        .frame(maxWidth: SettingsPanelLayout.contentMaxWidth, alignment: .leading)
        .padding(22)
    }

    private var currentSettings: MenuBarDisplaySettings {
        MenuBarDisplaySettings(
            contentMode: MenuBarContentMode(rawValue: contentMode) ?? .paceComparison,
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
            showsAdditionalLimits: showsAdditionalLimits,
            showsMenuBarIcon: showsMenuBarIcon
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

    private func applyDisplayPreset(_ preset: MenuBarDisplayPreset) {
        let settings = preset.settings
        layoutDensity = settings.layoutDensity.rawValue
        itemSpacing = settings.itemSpacing
        rowSpacing = settings.rowSpacing
        numberFontSize = settings.numberFontSize
        numberFontWeight = settings.numberFontWeight.rawValue
    }

    private func applyColorPreset(_ preset: MenuBarColorPreset) {
        let colors = preset.colors
        goodColorHex = colors.goodColorHex
        warningColorHex = colors.warningColorHex
        dangerColorHex = colors.dangerColorHex
    }

    private func resetDisplaySettings() {
        contentMode = MenuBarDisplaySettings.defaultContentMode.rawValue
        layoutDensity = MenuBarDisplaySettings.defaultLayoutDensity.rawValue
        itemSpacing = MenuBarDisplaySettings.defaultItemSpacing
        rowSpacing = MenuBarDisplaySettings.defaultRowSpacing
        numberFontSize = MenuBarDisplaySettings.defaultNumberFontSize
        numberFontWeight = MenuBarDisplaySettings.defaultNumberFontWeight.rawValue
        goodColorHex = MenuBarDisplaySettings.defaultGoodColorHex
        warningColorHex = MenuBarDisplaySettings.defaultWarningColorHex
        dangerColorHex = MenuBarDisplaySettings.defaultDangerColorHex
        showsPrimaryWindow = MenuBarDisplaySettings.defaultShowsPrimaryWindow
        showsSecondaryWindow = MenuBarDisplaySettings.defaultShowsSecondaryWindow
        showsPercentSymbol = MenuBarDisplaySettings.defaultShowsPercentSymbol
        showsAdditionalLimits = MenuBarDisplaySettings.defaultShowsAdditionalLimits
        showsMenuBarIcon = MenuBarDisplaySettings.defaultShowsMenuBarIcon
    }

    private func loadPreviewSnapshot() {
        previewSnapshot = try? UsageSnapshotStore().load()
    }

    private func normalizeStoredSettings() {
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
        showsAdditionalLimits = settings.showsAdditionalLimits
        showsMenuBarIcon = settings.showsMenuBarIcon
    }
}

/// 轻量悬停帮助图标，用自定义 popover 替代系统 tooltip，避免系统延迟影响设置说明的可读性。
private struct QuickHelpIcon: View {
    let text: String
    @State private var isShowing = false

    var body: some View {
        Image(systemName: "questionmark.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onHover { hovering in
                isShowing = hovering
            }
            .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 330, alignment: .leading)
                    .padding(10)
            }
            .accessibilityLabel("预期消耗对比说明")
    }
}
