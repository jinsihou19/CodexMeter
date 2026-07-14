import CodexMeterShared
import SwiftUI

struct DensitySettingRow: View {
    @Binding var layoutDensity: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsInlineTitle(title: "显示密度", detail: "切换菜单栏项目在紧凑和常规布局之间的显示节奏。")
            Picker("", selection: $layoutDensity) {
                ForEach(MenuBarLayoutDensity.allCases) { density in
                    Text(AppLocalization.string(density.title)).tag(density.rawValue)
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

struct SliderSettingRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsInlineTitle(title: title, detail: "\(title)的可调范围是 \(rangeText)，每次调整 \(stepText)。")
            Slider(value: clampedValue, in: range, step: step)
            Text(valueText)
                .font(.callout.monospacedDigit())
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

struct ColorHexPicker: View {
    let title: String
    @Binding var hex: String

    var body: some View {
        ColorPicker(selection: colorBinding, supportsOpacity: false) {
            SettingsInlineTitle(title: title, detail: "\(title)状态使用的强调色。")
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

/// 自定义设置控件左侧标题；详细范围由控件数值本身表达，避免每行重复说明按钮。
private struct SettingsInlineTitle: View {
    let title: String
    let detail: String

    var body: some View {
        Text(AppLocalization.string(title))
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .help(AppLocalization.string(detail))
        .frame(width: 118, alignment: .leading)
    }
}

private extension SliderSettingRow {
    var rangeText: String {
        "\(formatted(range.lowerBound))\(suffix) 到 \(formatted(range.upperBound))\(suffix)"
    }

    var stepText: String {
        "\(formatted(step))\(suffix)"
    }

    func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}

private extension ClosedRange where Bound == Double {
    func clamped(_ value: Double) -> Double {
        Swift.max(lowerBound, Swift.min(upperBound, value))
    }
}
