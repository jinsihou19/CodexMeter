import CodexMeterShared
import SwiftUI

/// 维护操作行直接展示名称与后果，避免破坏性或恢复动作只依赖悬停说明。
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string(title))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(AppLocalization.string(subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
        .help(AppLocalization.string(subtitle))
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

                Text(AppLocalization.string(title))
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
        .help(AppLocalization.string(subtitle))
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
            Text(AppLocalization.string(title))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(AppLocalization.string(value))
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 设置页通用偏好行，左侧直接展示标题和简短说明，右侧承载系统控件。
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
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.string(title))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                if !subtitle.isEmpty {
                    Text(AppLocalization.string(subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                control
            }
            .frame(width: SettingsPanelLayout.preferenceControlWidth)
        }
        .help(AppLocalization.string(subtitle))
        .frame(minHeight: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 设置开关沿用统一的右对齐样式；说明为空时只展示紧凑标题行。
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
                    Text(AppLocalization.string(option.title)).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}
