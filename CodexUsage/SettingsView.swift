import CodexUsageShared
import SwiftUI

enum SettingsPanelLayout {
    static let sidebarWidth: CGFloat = 148
    static let contentMaxWidth: CGFloat = 720
    static let usesSingleContentColumn = true
    static let usesTrailingFooterAction = false
    static let previewAppearanceColumns = 3
    static let displayPresetColumns = 3
    static let colorPresetColumns = 3
    static let sectionSpacing: CGFloat = 12
    static let sectionHeaderSpacing: CGFloat = 7
    static let sectionContentSpacing: CGFloat = 8
    static let sectionContentPadding: CGFloat = 12
    static let cardSpacing: CGFloat = 8
    static let previewUsesContentFrame = false
    static let previewChipSpacing: CGFloat = 6
    static let previewChipVerticalPadding: CGFloat = 9
    static let previewSampleVerticalPadding: CGFloat = 5
    static let presetCardMinimumHeight: CGFloat = 74
    static let presetCardVerticalPadding: CGFloat = 9
}

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

    @AppStorage(MenuBarPreferenceKeys.layoutDensity) private var layoutDensity = MenuBarDisplaySettings.defaultLayoutDensity.rawValue
    @AppStorage(MenuBarPreferenceKeys.itemSpacing) private var itemSpacing = MenuBarDisplaySettings.defaultItemSpacing
    @AppStorage(MenuBarPreferenceKeys.rowSpacing) private var rowSpacing = MenuBarDisplaySettings.defaultRowSpacing
    @AppStorage(MenuBarPreferenceKeys.numberFontSize) private var numberFontSize = MenuBarDisplaySettings.defaultNumberFontSize
    @AppStorage(MenuBarPreferenceKeys.numberFontWeight) private var numberFontWeight = MenuBarDisplaySettings.defaultNumberFontWeight.rawValue
    @AppStorage(MenuBarPreferenceKeys.goodColorHex) private var goodColorHex = MenuBarDisplaySettings.defaultGoodColorHex
    @AppStorage(MenuBarPreferenceKeys.warningColorHex) private var warningColorHex = MenuBarDisplaySettings.defaultWarningColorHex
    @AppStorage(MenuBarPreferenceKeys.dangerColorHex) private var dangerColorHex = MenuBarDisplaySettings.defaultDangerColorHex
    @AppStorage(MenuBarPreferenceKeys.showsPrimaryWindow) private var showsPrimaryWindow = MenuBarDisplaySettings.defaultShowsPrimaryWindow
    @AppStorage(MenuBarPreferenceKeys.showsSecondaryWindow) private var showsSecondaryWindow = MenuBarDisplaySettings.defaultShowsSecondaryWindow
    @AppStorage(MenuBarPreferenceKeys.showsPercentSymbol) private var showsPercentSymbol = MenuBarDisplaySettings.defaultShowsPercentSymbol

    @State private var selectedPane = Pane.display
    @State private var configurationInfo = CodexConfigurationInfo.current()

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
        VStack(alignment: .leading, spacing: SettingsPanelLayout.sectionSpacing) {
            SettingsSection(
                title: "菜单栏预览",
                subtitle: "浅色、深色和半透明背景下的实际读数",
                isContentFramed: SettingsPanelLayout.previewUsesContentFrame
            ) {
                SettingsPreview(
                    settings: currentSettings,
                    primaryTone: .good,
                    secondaryTone: .warning
                )
            }

            SettingsSection(title: "快速预设", subtitle: "一键调整间距、字号和字重") {
                HStack(spacing: SettingsPanelLayout.cardSpacing) {
                    ForEach(MenuBarDisplayPreset.allCases) { preset in
                        SettingsPresetCard(
                            title: preset.title,
                            subtitle: preset.summary,
                            systemImage: preset.symbolName
                        ) {
                            applyDisplayPreset(preset)
                        }
                    }
                }
            }

            SettingsSection(title: "显示内容", subtitle: "控制菜单栏里出现的读数") {
                Toggle("显示 5 小时窗口", isOn: primaryWindowBinding)
                Toggle("显示 7 天窗口", isOn: secondaryWindowBinding)
                Toggle("显示百分号", isOn: $showsPercentSymbol)
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
                            systemImage: preset.symbolName
                        ) {
                            applyColorPreset(preset)
                        }
                    }
                }

                ColorHexPicker(title: "充足", hex: $goodColorHex)
                ColorHexPicker(title: "偏低", hex: $warningColorHex)
                ColorHexPicker(title: "紧张", hex: $dangerColorHex)
            }

            SettingsActionRow(
                title: "恢复默认",
                subtitle: "还原菜单栏显示、排版和颜色",
                systemImage: "arrow.counterclockwise"
            ) {
                resetDisplaySettings()
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
            showsPercentSymbol: showsPercentSymbol
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
    }

    private func normalizeStoredSettings() {
        let settings = currentSettings
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
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let isContentFramed: Bool
    let content: Content

    init(
        title: String,
        subtitle: String?,
        isContentFramed: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isContentFramed = isContentFramed
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsPanelLayout.sectionHeaderSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            contentContainer
        }
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: SettingsPanelLayout.sectionContentSpacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var contentContainer: some View {
        if isContentFramed {
            contentStack
                .padding(SettingsPanelLayout.sectionContentPadding)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            contentStack
        }
    }
}

private struct SettingsPreview: View {
    let settings: MenuBarDisplaySettings
    let primaryTone: UsageRemainingTone
    let secondaryTone: UsageRemainingTone

    var body: some View {
        HStack(spacing: SettingsPanelLayout.cardSpacing) {
            ForEach(MenuBarPreviewAppearance.allCases) { appearance in
                MenuBarPreviewChip(
                    appearance: appearance,
                    settings: settings,
                    primaryTone: primaryTone,
                    secondaryTone: secondaryTone
                )
            }
        }
    }
}

private struct MenuBarPreviewChip: View {
    let appearance: MenuBarPreviewAppearance
    let settings: MenuBarDisplaySettings
    let primaryTone: UsageRemainingTone
    let secondaryTone: UsageRemainingTone

    var body: some View {
        VStack(spacing: SettingsPanelLayout.previewChipSpacing) {
            MenuBarPreviewSample(
                appearance: appearance,
                settings: settings,
                primaryTone: primaryTone,
                secondaryTone: secondaryTone
            )

            Text(appearance.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, SettingsPanelLayout.previewChipVerticalPadding)
        .accessibilityLabel("\(appearance.title)，\(appearance.summary)")
    }
}

private struct SettingsPresetCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.tint)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }
            }
            .frame(maxWidth: .infinity, minHeight: SettingsPanelLayout.presetCardMinimumHeight)
            .padding(.horizontal, 8)
            .padding(.vertical, SettingsPanelLayout.presetCardVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityLabel("\(title)，\(subtitle)")
    }
}

private struct SettingsActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(SettingsPanelLayout.sectionContentSpacing)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private extension MenuBarPreviewAppearance {
    var summary: String {
        switch self {
        case .light:
            return "系统浅色菜单栏"
        case .dark:
            return "深色或高对比背景"
        case .translucent:
            return "桌面壁纸透出的半透明状态"
        }
    }
}

private struct MenuBarPreviewSample: View {
    let appearance: MenuBarPreviewAppearance
    let settings: MenuBarDisplaySettings
    let primaryTone: UsageRemainingTone
    let secondaryTone: UsageRemainingTone

    var body: some View {
        VStack(spacing: settings.rowSpacing) {
            ForEach(previewLines) { line in
                previewLine(label: line.label, value: line.value, tone: line.tone)
            }
        }
        .frame(width: settings.statusItemWidth, height: settings.statusLabelHeight)
        .padding(.horizontal, 8)
        .padding(.vertical, SettingsPanelLayout.previewSampleVerticalPadding)
        .background(sampleBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var previewLines: [SettingsPreviewLine] {
        var lines: [SettingsPreviewLine] = []
        if settings.showsPrimaryWindow {
            lines.append(SettingsPreviewLine(label: "5h", value: formattedValue("70%"), tone: primaryTone))
        }
        if settings.showsSecondaryWindow {
            lines.append(SettingsPreviewLine(label: "7d", value: formattedValue("82%"), tone: secondaryTone))
        }
        if lines.isEmpty {
            lines.append(SettingsPreviewLine(label: "5h", value: formattedValue("70%"), tone: primaryTone))
        }
        return lines
    }

    private func formattedValue(_ value: String) -> String {
        guard !settings.showsPercentSymbol, value.hasSuffix("%") else {
            return value
        }
        return String(value.dropLast())
    }

    private var sampleBackground: some View {
        ZStack {
            switch appearance {
            case .light:
                Color(nsColor: .windowBackgroundColor)
            case .dark:
                Color(red: 0.10, green: 0.10, blue: 0.11)
            case .translucent:
                Color(nsColor: .windowBackgroundColor).opacity(0.56)
                Color.accentColor.opacity(0.08)
            }
        }
    }

    private var borderColor: Color {
        switch appearance {
        case .light:
            return Color.primary.opacity(0.14)
        case .dark:
            return Color.white.opacity(0.18)
        case .translucent:
            return Color.primary.opacity(0.10)
        }
    }

    private var labelColor: Color {
        switch appearance {
        case .dark:
            return .white
        case .light, .translucent:
            return .primary
        }
    }

    private func previewLine(label: String, value: String, tone: UsageRemainingTone) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: settings.itemSpacing) {
            Text(label)
                .foregroundStyle(labelColor)
            Text(value)
                .foregroundStyle(tone.statusBarColor(settings: settings))
        }
        .font(.system(size: settings.numberFontSize, weight: settings.numberFontWeight.fontWeight))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
}

private struct SettingsPreviewLine: Identifiable {
    let label: String
    let value: String
    let tone: UsageRemainingTone

    var id: String {
        label
    }
}

private struct DensitySettingRow: View {
    @Binding var layoutDensity: String

    var body: some View {
        HStack(spacing: 12) {
            Text("显示密度")
                .frame(width: 74, alignment: .leading)
            Picker("", selection: $layoutDensity) {
                ForEach(MenuBarLayoutDensity.allCases) { density in
                    Text(density.title).tag(density.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 156)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SliderSettingRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 74, alignment: .leading)
            Slider(value: clampedValue, in: range, step: step)
            Text(valueText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueText: String {
        let displayValue = range.clamped(value)
        return "\(displayValue.formatted(.number.precision(.fractionLength(displayValue.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1))))\(suffix)"
    }

    private var clampedValue: Binding<Double> {
        Binding(
            get: {
                range.clamped(value)
            },
            set: { newValue in
                value = range.clamped(newValue)
            }
        )
    }
}

private struct ColorHexPicker: View {
    let title: String
    @Binding var hex: String

    var body: some View {
        ColorPicker(selection: colorBinding, supportsOpacity: false) {
            Text(title)
                .frame(width: 74, alignment: .leading)
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                Color(hexRGB: hex)
            },
            set: { newValue in
                hex = newValue.hexRGB ?? hex
            }
        )
    }
}

private struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsSidebarButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private extension ClosedRange where Bound == Double {
    func clamped(_ value: Double) -> Double {
        Swift.max(lowerBound, Swift.min(upperBound, value))
    }
}
