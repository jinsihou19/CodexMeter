import CodexMeterShared
import SwiftUI

struct SettingsResetActionState: Equatable {
    let isVisible: Bool
    let isEnabled: Bool

    init(settings: MenuBarDisplaySettings) {
        self.isVisible = true
        self.isEnabled = !Self.usesMenuBarDefaultValues(settings)
    }

    /// 菜单栏重置只判断菜单栏专属项；活动颜色由状态决定，不参与用户设置。
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
            && settings.showsHookActivityLight == defaults.showsHookActivityLight
            && settings.hookActivityIndicatorStyle == defaults.hookActivityIndicatorStyle
            && settings.weeklyProgressWorkDays == defaults.weeklyProgressWorkDays
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
            Text(title)
                .font(.subheadline.weight(.semibold))
                .help(subtitle ?? "")
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
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(.tint)

                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                SettingsHelpButton(text: subtitle, accessibilityLabel: "\(title)说明")

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
        .help(subtitle)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// 横向操作组使用的紧凑按钮，只保留图标和动作名称，说明文案通过悬停提示提供。
struct SettingsCompactActionButton: View {
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
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 18)

                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .allowsTightening(true)
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
        .help(subtitle)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 34)
        .background(Color.primary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 设置页通用偏好行，左侧显示单行标题，右侧承载开关、菜单或按钮等控件。
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
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                SettingsHelpButton(text: subtitle, accessibilityLabel: "\(title)说明")
            }

            Spacer(minLength: 12)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                control
            }
            .frame(width: SettingsPanelLayout.preferenceControlWidth)
        }
        .help(subtitle)
        .frame(minHeight: 28)
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
                .controlSize(.small)
        }
    }
}

/// 设置页通用说明按钮，把长业务说明收进弹层，避免偏好列表正文被辅助文案淹没。
struct SettingsHelpButton: View {
    let text: String
    let accessibilityLabel: String

    @State private var isShowing = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onTapGesture {
                isShowing.toggle()
            }
            .help(accessibilityLabel)
            .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 340, alignment: .leading)
                    .padding(10)
            }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }
}

/// 紧凑模块开关行，把解释收进说明按钮，并沿用普通偏好行的行高节奏。
struct SettingsCompactToggleRow: View {
    let title: String
    let detail: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            SettingsHelpButton(text: detail, accessibilityLabel: "\(title)说明")

            Spacer(minLength: 8)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(minHeight: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
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
