import SwiftUI

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

    @State private var selectedPane = Pane.display
    @State private var configurationInfo = CodexConfigurationInfo.current()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(alignment: .top, spacing: 0) {
                sidebar

                Divider()

                Group {
                    switch selectedPane {
                    case .display:
                        displayPane
                    case .codex:
                        codexPane
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 680, height: 430)
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
        .frame(width: 132)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var displayPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPreview(
                settings: currentSettings,
                primaryTone: .good,
                secondaryTone: .warning
            )

            HStack(alignment: .top, spacing: 18) {
                SettingsSection(title: "菜单栏") {
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
                .frame(minWidth: 278)

                VStack(alignment: .leading, spacing: 18) {
                    SettingsSection(title: "数字样式") {
                        Picker("数字字重", selection: $numberFontWeight) {
                            ForEach(MenuBarNumberFontWeight.allCases) { weight in
                                Text(weight.title).tag(weight.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)

                        ColorHexPicker(title: "充足", hex: $goodColorHex)
                        ColorHexPicker(title: "偏低", hex: $warningColorHex)
                        ColorHexPicker(title: "紧张", hex: $dangerColorHex)
                    }

                    Button {
                        resetDisplaySettings()
                    } label: {
                        Label("恢复默认", systemImage: "arrow.counterclockwise")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 188)
                .padding(.top, 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(22)
    }

    private var codexPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "读取配置") {
                ForEach(configurationInfo.displayRows) { row in
                    SettingsInfoRow(title: row.title, value: row.value)
                }
            }

            HStack {
                Button {
                    configurationInfo = CodexConfigurationInfo.current()
                } label: {
                    Label("重新读取", systemImage: "arrow.clockwise")
                }

                Spacer()
            }

            Spacer()
        }
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
            dangerColorHex: dangerColorHex
        )
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
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct SettingsPreview: View {
    let settings: MenuBarDisplaySettings
    let primaryTone: UsageRemainingTone
    let secondaryTone: UsageRemainingTone

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("菜单栏预览")
                    .font(.headline)
                Text("修改会立即应用到顶部菜单栏")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: settings.rowSpacing) {
                previewLine(label: "5h", value: "70%", tone: primaryTone)
                previewLine(label: "7d", value: "82%", tone: secondaryTone)
            }
            .frame(width: settings.statusItemWidth, height: 32)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.40, blue: 0.82),
                        Color(red: 0.08, green: 0.55, blue: 0.90)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func previewLine(label: String, value: String, tone: UsageRemainingTone) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: settings.itemSpacing) {
            Text(label)
                .foregroundStyle(.white)
            Text(value)
                .foregroundStyle(tone.statusBarColor(settings: settings))
        }
        .font(.system(size: settings.numberFontSize, weight: settings.numberFontWeight.fontWeight))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.78)
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
