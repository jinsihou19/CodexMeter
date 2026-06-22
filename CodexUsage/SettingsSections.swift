import CodexUsageShared
import SwiftUI

struct SettingsResetActionState: Equatable {
    let isVisible: Bool
    let isEnabled: Bool

    init(settings: MenuBarDisplaySettings) {
        self.isVisible = true
        self.isEnabled = !Self.usesMenuBarDefaultValues(settings)
    }

    /// 菜单栏重置只判断菜单栏专属项；颜色已提升为全局外观，不再影响该按钮状态。
    private static func usesMenuBarDefaultValues(_ settings: MenuBarDisplaySettings) -> Bool {
        let defaults = MenuBarDisplaySettings()
        return settings.contentMode == defaults.contentMode
            && settings.layoutDensity == defaults.layoutDensity
            && settings.itemSpacing == defaults.itemSpacing
            && settings.rowSpacing == defaults.rowSpacing
            && settings.numberFontSize == defaults.numberFontSize
            && settings.numberFontWeight == defaults.numberFontWeight
            && settings.showsPrimaryWindow == defaults.showsPrimaryWindow
            && settings.showsSecondaryWindow == defaults.showsSecondaryWindow
            && settings.showsPercentSymbol == defaults.showsPercentSymbol
            && settings.showsAdditionalLimits == defaults.showsAdditionalLimits
            && settings.showsMenuBarIcon == defaults.showsMenuBarIcon
    }
}

struct SettingsSection<Content: View>: View {
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

struct SettingsActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

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
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
        .padding(SettingsPanelLayout.sectionContentSpacing)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct SettingsInfoRow: View {
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

/// 设置页通用偏好行，左侧解释业务含义，右侧承载开关、菜单或按钮等控件。
struct SettingsPreferenceRow<Control: View>: View {
    let title: String
    let subtitle: String
    let control: Control

    init(
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            control
                .frame(maxWidth: 240, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 带说明文案的开关行，用于需要解释影响范围的设置项。
struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsPreferenceRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// 字符串 rawValue picker 行，适合和 @AppStorage 直接绑定，避免设置页重复转换枚举。
struct SettingsPickerRow: View {
    let title: String
    let subtitle: String
    @Binding var selection: String
    let options: [(value: String, title: String)]

    var body: some View {
        SettingsPreferenceRow(title: title, subtitle: subtitle) {
            Picker("", selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 180)
        }
    }
}

struct SettingsSidebarButtonStyle: ButtonStyle {
    let isSelected: Bool

    /// 让整行设置侧栏按钮都参与点击命中，而不是只命中文字和图标。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
