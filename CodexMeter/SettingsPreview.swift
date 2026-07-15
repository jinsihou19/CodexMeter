import CodexMeterShared
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

            Text(AppLocalization.string(appearance.title))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, SettingsPanelLayout.previewChipVerticalPadding)
        .accessibilityLabel(
            "\(AppLocalization.string(appearance.title)), \(AppLocalization.string(appearance.summary))"
        )
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
        StatusLineDisplay.lines(snapshot: data.snapshot, settings: settings)
    }

    private var sampleWidth: CGFloat {
        StatusBarDisplayMetrics.statusItemWidth(for: previewLines, settings: settings)
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

    /// 预览直接使用当前真实字号，保证自定义控件和菜单栏显示一致。
    private var previewFontSize: Double {
        guard previewLines.count == 1 else { return settings.numberFontSize }
        return NativeStatusBarTitle.font(settings: settings).pointSize
    }

    private var previewFontWeight: Font.Weight {
        guard previewLines.count == 1,
              MenuBarLayoutChoice.matching(settings: settings) != .custom
        else {
            return settings.numberFontWeight.fontWeight
        }
        return .regular
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
        .font(.system(size: previewFontSize, weight: previewFontWeight).monospacedDigit())
        .fixedSize(horizontal: true, vertical: false)
        .lineLimit(1)
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
