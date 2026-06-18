import CodexUsageShared
import SwiftUI

struct SettingsPreview: View {
    let settings: MenuBarDisplaySettings
    let data: SettingsPreviewData

    var body: some View {
        HStack(spacing: SettingsPanelLayout.cardSpacing) {
            ForEach(MenuBarPreviewAppearance.allCases) { appearance in
                MenuBarPreviewChip(
                    appearance: appearance,
                    settings: settings,
                    data: data
                )
            }
        }
    }
}

private struct MenuBarPreviewChip: View {
    let appearance: MenuBarPreviewAppearance
    let settings: MenuBarDisplaySettings
    let data: SettingsPreviewData

    var body: some View {
        VStack(spacing: SettingsPanelLayout.previewChipSpacing) {
            MenuBarPreviewSample(
                appearance: appearance,
                settings: settings,
                data: data
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

private struct MenuBarPreviewSample: View {
    let appearance: MenuBarPreviewAppearance
    let settings: MenuBarDisplaySettings
    let data: SettingsPreviewData

    var body: some View {
        HStack(spacing: settings.showsMenuBarIcon ? MenuBarDisplaySettings.menuBarIconTextSpacing : 0) {
            if settings.showsMenuBarIcon {
                Image("OpenAIStatusIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(
                        width: MenuBarDisplaySettings.menuBarIconWidth,
                        height: MenuBarDisplaySettings.menuBarIconWidth
                    )
                    .foregroundStyle(labelColor)
                    .accessibilityHidden(true)
            }

            VStack(alignment: textColumnAlignment, spacing: lineSpacing) {
                ForEach(previewLines) { line in
                    previewLine(label: line.label, value: line.value, tone: line.tone)
                }
            }
        }
        .frame(width: sampleWidth, height: settings.statusLabelHeight)
        .padding(.horizontal, 8)
        .padding(.vertical, SettingsPanelLayout.previewSampleVerticalPadding)
        .background(sampleBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var previewLines: [StatusLineDisplay] {
        if settings.contentMode == .paceComparison {
            return [
                StatusLineDisplay(
                    id: "pace-remaining",
                    label: "",
                    value: formattedValue(data.paceRemainingValue),
                    tone: data.paceRemainingTone
                ),
                StatusLineDisplay(
                    id: "pace-delta",
                    label: "",
                    value: data.paceDeltaValue,
                    tone: data.paceTone
                )
            ]
        }

        var lines: [StatusLineDisplay] = []
        if settings.showsPrimaryWindow {
            lines.append(StatusLineDisplay(
                id: "primary",
                label: "5h",
                value: formattedValue(data.primaryValue),
                tone: data.primaryTone
            ))
        }
        if settings.showsSecondaryWindow {
            lines.append(StatusLineDisplay(
                id: "secondary",
                label: "7d",
                value: formattedValue(data.secondaryValue),
                tone: data.secondaryTone
            ))
        }
        if lines.isEmpty {
            lines.append(StatusLineDisplay(
                id: "fallback-primary",
                label: "5h",
                value: formattedValue(data.primaryValue),
                tone: data.primaryTone
            ))
        }
        return lines
    }

    private var sampleWidth: CGFloat {
        StatusBarDisplayMetrics.statusItemWidth(for: previewLines, settings: settings)
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

    /// 设置页预览使用同一行距设置，确保 Pace 和剩余额度的预览都响应“两行行距”。
    private var lineSpacing: Double {
        settings.rowSpacing
    }

    /// 预览字号完全跟随设置页，确保预览和菜单栏真实显示一致。
    private var previewFontSize: Double {
        settings.numberFontSize
    }

    private var previewFontWeight: Font.Weight {
        settings.numberFontWeight.fontWeight
    }

    private var textColumnAlignment: HorizontalAlignment {
        settings.showsMenuBarIcon ? .trailing : .center
    }

    private func previewLine(label: String, value: String, tone: UsageRemainingTone) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: settings.itemSpacing) {
            if !label.isEmpty {
                Text(label)
                    .foregroundStyle(labelColor)
            }
            Text(value)
                .foregroundStyle(tone.statusBarColor(settings: settings))
        }
        .font(.system(size: previewFontSize, weight: previewFontWeight))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.78)
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
