import AppKit
import CodexMeterShared
import SwiftUI
import UniformTypeIdentifiers

/// 预览区域统一使用移动语义，避免系统把拖放显示成带加号的复制操作。
private struct MenuBarDropDelegate: DropDelegate {
    let onDrop: ([NSItemProvider]) -> Bool

    /// 告诉系统拖动目标是移动而不是复制，从源头去掉拖放预览上的加号。
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    /// 接收文本拖放数据，并交给预览编辑器按目标区域处理。
    func performDrop(info: DropInfo) -> Bool {
        onDrop(info.itemProviders(for: [.text]))
    }
}

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

/// 记录当前操作菜单对应的布局项目；弹出菜单绑定到具体内容而不是编辑器根视图。
private struct MenuBarEditorTarget: Identifiable, Equatable {
    let item: Int
    let index: Int?

    var id: String {
        "\(item)-\(index.map(String.init) ?? "container")"
    }
}

/// 记录堆叠容器正在编辑的行；行选择器沿用内容操作菜单的弹出定位。
private struct MenuBarStackRowTarget: Identifiable, Equatable {
    let item: Int
    let row: Int

    var id: String {
        "\(item)-\(row)"
    }
}

/// 菜单栏项目编辑器；预览本身就是可拖动的菜单栏，点击内容通过弹出菜单进行配置。
struct MenuBarLayoutEditor: View {
    @Binding var layout: MenuBarLayout
    let onChange: (MenuBarLayout) -> Void
    let settings: MenuBarDisplaySettings
    let snapshot: UsageSnapshot?
    let geminiSettings: GeminiModelsSettings
    let geminiSnapshot: GeminiModelsSnapshot?
    @State private var menuTarget: MenuBarEditorTarget?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: CGFloat(settings.itemSpacing)) {
                    ForEach(visibleItemIndices, id: \.self) { item in
                        itemEditor(item)
                    }
                    trailingDropZone
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: MenuBarDisplaySettings().statusLabelHeight, alignment: .leading)
            addMenu
            trashDropTarget
        }
        .frame(minHeight: settings.statusLabelHeight + 16, alignment: .center)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.92), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
        )
    }

    /// 绘制一个与真实菜单栏同结构的横向项目；单击内容打开操作菜单，拖动内容调整布局。
    @ViewBuilder
    private func itemEditor(_ item: Int) -> some View {
        let visibleTokens = layout.items[item].filter(shouldShowToken)
        if visibleTokens.isEmpty {
            emptyStackEditor(item)
        } else {
            let isStacked = layout.items[item].contains { $0.isStackPlaceholder }
                || visibleTokens.count > 1
            VStack(alignment: .trailing, spacing: isStacked ? min(CGFloat(settings.rowSpacing), 0) : 0) {
                ForEach(
                    Array(layout.items[item].enumerated()).filter { shouldShowToken($0.element) },
                    id: \.offset
                ) { index, token in
                    tokenEditor(
                        token,
                        item: item,
                        index: index,
                        isStacked: isStacked
                    )
                }
            }
            .frame(minHeight: MenuBarDisplaySettings().statusLabelHeight, alignment: .center)
            .contentShape(Rectangle())
            .onDrag {
                NSItemProvider(object: NSString(string: "item|\(item)"))
            } preview: {
                itemDragPreview(item)
            }
            .onDrop(
                of: [.text],
                delegate: MenuBarDropDelegate { providers in
                    handleDrop(providers) { payload in
                        drop(payload, toItem: item, index: layout.items[item].count)
                    }
                }
            )
            .help("拖动堆叠项目可整体移动；同一项目内拖动内容调整上下顺序")
        }
    }

    /// 绘制没有内容的堆叠容器；它只显示容器图标，不塞入任何占位项目。
    private func emptyStackEditor(_ item: Int) -> some View {
        let target = MenuBarEditorTarget(item: item, index: nil)
        return Image(systemName: "square.stack.3d.up")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: MenuBarDisplaySettings().statusLabelHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                menuTarget = target
            }
            .popover(item: editorMenuBinding(for: target), arrowEdge: .bottom) { target in
                editorMenu(for: target)
            }
            .onDrag {
                NSItemProvider(object: NSString(string: "item|\(item)"))
            } preview: {
                itemDragPreview(item)
            }
            .onDrop(
                of: [.text],
                delegate: MenuBarDropDelegate { providers in
                    handleDrop(providers) { payload in
                        drop(payload, toItem: item, index: 0)
                    }
                }
            )
            .help("空堆叠容器；点击配置第一行和第二行")
    }

    /// 预览始终保留持久化布局内容；关闭 Antigravity 时由内容层置灰提示真实菜单不会显示。
    private func shouldShowToken(_ token: MenuBarLayoutToken) -> Bool {
        !token.isStackPlaceholder
    }

    /// 判断某个预览内容是否因 Antigravity 关闭而处于禁用状态。
    private func isDisabledToken(_ token: MenuBarLayoutToken) -> Bool {
        token.isGeminiToken && !geminiSettings.isEnabled
    }

    /// 返回布局中的全部横向项目，让关闭的 Antigravity 项目仍能在编辑器中定位和调整。
    private var visibleItemIndices: [Int] {
        layout.items.indices.filter { item in
            layout.items[item].isEmpty
                || layout.items[item].contains { $0.isStackPlaceholder }
                || layout.items[item].contains(where: shouldShowToken)
        }
    }

    /// 绘制单个可拖动内容；操作菜单绑定在内容自身，拖拽手势不再被原生 Menu 控件吞掉。
    private func tokenEditor(
        _ token: MenuBarLayoutToken,
        item: Int,
        index: Int,
        isStacked: Bool
    ) -> some View {
        let target = MenuBarEditorTarget(item: item, index: index)
        let isDisabled = isDisabledToken(token)
        let dragSource = isStacked ? dragPayload(item: item, index: index) : "item|\(item)"
        return liveTokenContent(token, isStacked: isStacked, isDisabled: isDisabled)
            .foregroundStyle(isDisabled ? Color.secondary.opacity(0.5) : Color.primary)
            .contentShape(Rectangle())
            .onTapGesture {
                menuTarget = target
            }
            .popover(item: editorMenuBinding(for: target), arrowEdge: .bottom) { target in
                editorMenu(for: target)
            }
            .onDrag {
                NSItemProvider(object: NSString(string: dragSource))
            } preview: {
                itemDragPreview(item)
            }
            .onDrop(
                of: [.text],
                delegate: MenuBarDropDelegate { providers in
                    handleDrop(providers) { payload in
                        drop(payload, toItem: item, index: index)
                    }
                }
            )
    }

    /// 绘制拖拽浮层；无论拖动堆叠中的哪一行，都展示该横向项目的完整内容。
    @ViewBuilder
    private func itemDragPreview(_ item: Int) -> some View {
        let stacked = isStackItem(item)
        let tokens = layout.items[item].filter(shouldShowToken)
        if tokens.isEmpty {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: MenuBarDisplaySettings().statusLabelHeight)
        } else {
            VStack(alignment: .trailing, spacing: stacked ? min(CGFloat(settings.rowSpacing), 0) : 0) {
                ForEach(
                    Array(layout.items[item].enumerated()).filter { shouldShowToken($0.element) },
                    id: \.offset
                ) { _, token in
                    let isDisabled = isDisabledToken(token)
                    liveTokenContent(
                        token,
                        isStacked: stacked,
                        isDisabled: isDisabled
                    )
                    .foregroundStyle(isDisabled ? Color.secondary.opacity(0.5) : Color.primary)
                }
            }
            .frame(minHeight: MenuBarDisplaySettings().statusLabelHeight, alignment: .center)
        }
    }

    /// 绑定当前内容的弹出菜单；只有匹配的内容响应同一个状态，确保箭头出现在点击位置。
    private func editorMenuBinding(for target: MenuBarEditorTarget) -> Binding<MenuBarEditorTarget?> {
        Binding(
            get: {
                menuTarget == target ? target : nil
            },
            set: { updatedTarget in
                menuTarget = updatedTarget
            }
        )
    }

    /// 显示单击内容后的紧凑操作菜单；按钮尺寸接近系统下拉菜单且不参与拖拽命中。
    @ViewBuilder
    private func editorMenu(for target: MenuBarEditorTarget) -> some View {
        if target.index == nil, layout.items.indices.contains(target.item) {
            VStack(alignment: .leading, spacing: 4) {
                stackConfiguration(item: target.item)
                Divider()
                    .padding(.vertical, 2)
                deleteItemButton(target.item)
            }
            .padding(8)
            .fixedSize(horizontal: true, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
            }
        } else if target.index != nil,
                  layout.items.indices.contains(target.item),
                  layout.items[target.item].indices.contains(target.index!) {
            let isStackedItem = isStackItem(target.item)
            VStack(alignment: .leading, spacing: 2) {
                if isStackedItem {
                    stackConfiguration(item: target.item)
                } else {
                    stackRowMenu(item: target.item, row: 0, showsRowLabel: false)
                }
                if isStackedItem {
                    Divider()
                        .padding(.vertical, 2)
                    Button("拆成独立项目") {
                        commit(layout.detaching(at: target.index!, inItem: target.item))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                }
                if isStackedItem {
                    Divider()
                        .padding(.vertical, 2)
                }
                Button("删除", role: .destructive) {
                    commit(layout.removingItem(at: target.item))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
            }
            .padding(8)
            .fixedSize(horizontal: true, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
            }
        }
    }

    /// 返回所有可配置内容；即使供应商开关关闭，也保留图标和内容的配置入口。
    private var stackConfigurationTokens: [MenuBarLayoutToken] {
        [
            .icon, .primary, .secondary, .paceRemaining, .paceDelta,
            .fiveHourPaceRemaining, .fiveHourPaceDelta, .weeklyPaceRemaining, .weeklyPaceDelta,
            .provider, .account, .plan, .usageBar,
            .resetCountdown, .resetTime, .depletionETA, .balance, .todayCost, .monthCost,
            .geminiIcon, .geminiPrimary, .geminiSecondary, .geminiPaceRemaining, .geminiPaceDelta,
            .geminiFiveHourPaceRemaining, .geminiFiveHourPaceDelta,
            .geminiWeeklyPaceRemaining, .geminiWeeklyPaceDelta,
            .geminiProvider, .geminiAccount, .geminiPlan, .geminiUsageBar,
            .geminiResetCountdown, .geminiResetTime, .geminiDepletionETA,
            .geminiBalance, .geminiTodayCost, .geminiMonthCost
        ]
    }

    /// 按供应商拆分堆叠行可选项目；二级菜单内不再重复显示供应商名称。
    private var codexStackConfigurationTokens: [MenuBarLayoutToken] {
        stackConfigurationTokens.filter { !$0.isGeminiToken }
    }

    /// 返回 Antigravity 项目；关闭供应商时仍允许预先配置，预览层负责置灰提示。
    private var geminiStackConfigurationTokens: [MenuBarLayoutToken] {
        stackConfigurationTokens.filter(\.isGeminiToken)
    }

    /// 显示堆叠容器的两行配置；选项菜单直接展示当前实时内容，不再显示抽象占位名称。
    @ViewBuilder
    private func stackConfiguration(item: Int) -> some View {
        stackRowMenu(item: item, row: 0)
        stackRowMenu(item: item, row: 1)
    }

    /// 绘制一行配置菜单；沿用添加菜单的原生层级样式，并保留当前行的真实内容。
    @ViewBuilder
    private func stackRowMenu(item: Int, row: Int, showsRowLabel: Bool = true) -> some View {
        let target = MenuBarStackRowTarget(item: item, row: row)
        Menu {
            stackRowPicker(for: target)
        } label: {
            HStack(spacing: 8) {
                Group {
                    if let token = stackRowToken(item: item, row: row) {
                        Text(showsRowLabel ? "第 \(row + 1) 行 · \(providerTokenTitle(token))" : providerTokenTitle(token))
                            .foregroundStyle(isDisabledToken(token) ? Color.secondary : Color.primary)
                    } else {
                        Text(showsRowLabel ? "第 \(row + 1) 行 · 空" : "空")
                    }
                }
                .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 28)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
    }

    /// 返回堆叠容器指定行的真实内容；空行标记只用于维持容器，不显示给用户。
    private func stackRowToken(item: Int, row: Int) -> MenuBarLayoutToken? {
        guard layout.items.indices.contains(item), layout.items[item].indices.contains(row) else {
            return nil
        }
        let token = layout.items[item][row]
        return token.isStackPlaceholder ? nil : token
    }

    /// 为堆叠行补充供应商名称，避免 Codex 与 Antigravity 的同名额度项目混淆。
    private func providerTokenTitle(_ token: MenuBarLayoutToken) -> String {
        if token == .separator || token == .space {
            return AppLocalization.string(token.title)
        }
        let provider = token.isGeminiToken ? "Antigravity" : "Codex"
        return "\(provider) \(AppLocalization.string(token.title))"
    }

    /// 生成行选择菜单；复用添加菜单的原生多级 Menu，避免两套弹出样式和定位逻辑。
    @ViewBuilder
    private func stackRowPicker(for target: MenuBarStackRowTarget) -> some View {
        Button("清空") {
            commitStackRow(nil, target: target)
        }
        Divider()
        stackProviderMenu(title: "Codex", iconToken: .icon, tokens: codexStackConfigurationTokens, target: target)
        stackProviderMenu(
            title: "Antigravity",
            iconToken: .geminiIcon,
            tokens: geminiStackConfigurationTokens,
            target: target
        )
    }

    /// 绘制供应商一级菜单及其项目二级菜单；沿用添加菜单的原生层级行为。
    @ViewBuilder
    private func stackProviderMenu(
        title: String,
        iconToken: MenuBarLayoutToken,
        tokens: [MenuBarLayoutToken],
        target: MenuBarStackRowTarget
    ) -> some View {
        let previewWidth = menuTokenPreviewColumnWidth(for: tokens)
        if !tokens.isEmpty {
            Menu {
                ForEach(tokens) { token in
                    Button {
                        commitStackRow(token, target: target)
                    } label: {
                        menuTokenLabel(token, previewWidth: previewWidth)
                    }
                }
            } label: {
                menuLabel(title: title) {
                    menuTokenPreview(iconToken)
                }
            }
        }
    }

    /// 写入堆叠行并保留父级编辑菜单，确保第一行填完后第二行不会丢失。
    private func commitStackRow(
        _ token: MenuBarLayoutToken?,
        target: MenuBarStackRowTarget
    ) {
        let updated: MenuBarLayout
        let isContainer = layout.items.indices.contains(target.item)
            && (layout.items[target.item].isEmpty || isStackItem(target.item))
        if isContainer {
            updated = layout.replacingStackToken(token, at: target.row, inItem: target.item).normalized
        } else if let token {
            updated = layout.replacingItemToken(token, inItem: target.item).normalized
        } else {
            updated = layout.removingItem(at: target.item).normalized
        }
        guard updated != layout else {
            return
        }
        layout = updated
        onChange(updated)
    }

    /// 生成弹出菜单中的“删除整个项目”动作，避免空容器和有内容容器出现两套删除逻辑。
    @ViewBuilder
    private func deleteItemButton(_ item: Int) -> some View {
        Button("删除整个项目", role: .destructive) {
            commit(layout.removingItem(at: item))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
    }

    /// 根据当前缓存快照绘制菜单栏内容；禁用的 Antigravity 仍显示缓存读数，但由调用方置灰。
    @ViewBuilder
    private func liveTokenContent(
        _ token: MenuBarLayoutToken,
        isStacked: Bool,
        isDisabled: Bool = false
    ) -> some View {
        if let bar = liveUsageBar(for: token) {
            MenuBarUsageBarView(
                display: bar,
                settings: settings,
                isDisabled: isDisabled
            )
        } else if let line = liveLine(for: token) {
            HStack(spacing: CGFloat(settings.itemSpacing)) {
                if !line.label.isEmpty {
                    Text(line.label)
                }
                Text(line.value)
                    .foregroundStyle(
                        isDisabled
                            ? Color.secondary.opacity(0.5)
                            : line.usesUsageColor
                                ? line.tone.statusBarColor(settings: settings)
                                : Color.primary
                    )
            }
            .foregroundStyle(isDisabled ? Color.secondary.opacity(0.5) : Color.primary)
            .font(.system(
                size: isStacked
                    ? min(CGFloat(settings.numberFontSize), 9)
                    : NativeStatusBarTitle.font(settings: settings).pointSize,
                weight: isStacked || MenuBarLayoutChoice.matching(settings: settings) == .custom
                    ? settings.numberFontWeight.fontWeight
                    : .regular
            ).monospacedDigit())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
        } else {
            switch token {
            case .icon:
                Image("OpenAIStatusIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: MenuBarDisplaySettings.menuBarIconWidth, height: MenuBarDisplaySettings.menuBarIconWidth)
                    .clipped()
            case .geminiIcon:
                Image(systemName: "sparkles")
                    .font(.system(size: StatusBarDisplayMetrics.trailingGeminiIconWidth - 2, weight: .semibold))
                    .frame(
                        width: StatusBarDisplayMetrics.trailingGeminiIconWidth,
                        height: StatusBarDisplayMetrics.trailingGeminiIconWidth
                    )
                    .clipped()
            case .separator:
                Text("·")
                    .font(.system(
                        size: isStacked ? min(CGFloat(settings.numberFontSize), 9) : NativeStatusBarTitle.font(settings: settings).pointSize,
                        weight: isStacked || MenuBarLayoutChoice.matching(settings: settings) == .custom
                            ? settings.numberFontWeight.fontWeight
                            : .regular
                    ))
            case .space:
                // 设置页用轮廓图标标记空格；真实菜单仍由 ResolvedMenuBarLayoutItem.space 保持纯间距。
                Image(systemName: token.systemImageName)
                    .font(.system(size: isStacked ? 9 : 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: isStacked ? 12 : 16, height: MenuBarDisplaySettings().statusLabelHeight)
            case .stackPlaceholder:
                Color.clear
                    .frame(width: 0, height: 0)
            default:
                Image(systemName: token.systemImageName)
                    .font(.system(size: isStacked ? 9 : 11, weight: .medium))
            }
        }
    }

    /// 解析编辑器中某个项目对应的 Codex 或 Antigravity 实时读数。
    private func liveLine(for token: MenuBarLayoutToken) -> StatusLineDisplay? {
        switch token {
        case .primary, .secondary, .paceRemaining, .paceDelta,
             .fiveHourPaceRemaining, .fiveHourPaceDelta,
             .weeklyPaceRemaining, .weeklyPaceDelta,
             .provider, .account, .plan, .resetCountdown, .resetTime, .depletionETA,
             .balance, .todayCost, .monthCost:
            return StatusLineDisplay.layoutLine(
                for: token,
                snapshot: snapshot,
                settings: settings
            )
        case .geminiPrimary, .geminiSecondary, .geminiPaceRemaining, .geminiPaceDelta,
             .geminiFiveHourPaceRemaining, .geminiFiveHourPaceDelta,
             .geminiWeeklyPaceRemaining, .geminiWeeklyPaceDelta,
             .geminiProvider, .geminiAccount, .geminiPlan,
             .geminiResetCountdown, .geminiResetTime, .geminiDepletionETA,
             .geminiBalance, .geminiTodayCost, .geminiMonthCost,
             .geminiRemaining, .geminiDelta:
            // 仅为设置页恢复关闭前的缓存读数；真实菜单仍由 MenuBarLayoutDisplay 过滤。
            let previewSettings = geminiSettings.isEnabled
                ? geminiSettings
                : GeminiModelsSettings(
                    isEnabled: true,
                    model: geminiSettings.model,
                    showsInPopover: geminiSettings.showsInPopover,
                    showsInMenuBar: true
                )
            return StatusLineDisplay.layoutGeminiLine(
                for: token,
                settings: settings,
                geminiSettings: previewSettings,
                snapshot: geminiSnapshot
            )
        default:
            return nil
        }
    }

    /// 解析编辑器中两个供应商的分段用量条，确保预览和真实菜单共用同一份比例。
    private func liveUsageBar(for token: MenuBarLayoutToken) -> MenuBarUsageBarDisplay? {
        switch token {
        case .usageBar:
            return StatusLineDisplay.layoutUsageBar(for: token, snapshot: snapshot)
        case .geminiUsageBar:
            let previewSettings = geminiSettings.isEnabled
                ? geminiSettings
                : GeminiModelsSettings(
                    isEnabled: true,
                    model: geminiSettings.model,
                    showsInPopover: geminiSettings.showsInPopover,
                    showsInMenuBar: true
                )
            return StatusLineDisplay.layoutGeminiUsageBar(
                for: token,
                geminiSettings: previewSettings,
                snapshot: geminiSnapshot
            )
        default:
            return nil
        }
    }

    /// 加号打开原生分级菜单；菜单锚定在加号下方，避免使用独立 popover 造成居中漂移。
    private var addMenu: some View {
        let codexTokens: [MenuBarLayoutToken] = [
            .icon, .primary, .secondary, .paceRemaining, .paceDelta,
            .fiveHourPaceDelta,
            .weeklyPaceDelta,
            .provider, .account, .plan, .usageBar,
            .resetCountdown, .resetTime, .depletionETA, .balance, .todayCost, .monthCost
        ]
        let geminiTokens: [MenuBarLayoutToken] = [
            .geminiIcon,
            .geminiPrimary,
            .geminiSecondary,
            .geminiPaceRemaining,
            .geminiPaceDelta,
            .geminiFiveHourPaceDelta,
            .geminiWeeklyPaceDelta,
            .geminiProvider,
            .geminiAccount,
            .geminiPlan,
            .geminiUsageBar,
            .geminiResetCountdown,
            .geminiResetTime,
            .geminiDepletionETA,
            .geminiBalance,
            .geminiTodayCost,
            .geminiMonthCost
        ]
        let codexPreviewWidth = menuTokenPreviewColumnWidth(for: codexTokens)
        let geminiPreviewWidth = menuTokenPreviewColumnWidth(for: geminiTokens)

        return Menu {
            Menu {
                ForEach(codexTokens) {
                    addTokenButton($0, previewWidth: codexPreviewWidth)
                }
                addStackButton(tokens: [.paceRemaining, .paceDelta], previewWidth: codexPreviewWidth)
                addStackButton(tokens: [.primary, .secondary], previewWidth: codexPreviewWidth)
                addStackButton(
                    tokens: [.fiveHourPaceRemaining, .fiveHourPaceDelta],
                    previewWidth: codexPreviewWidth
                )
                addStackButton(
                    tokens: [.weeklyPaceRemaining, .weeklyPaceDelta],
                    previewWidth: codexPreviewWidth
                )
            } label: {
                menuLabel(title: "Codex") {
                    menuTokenPreview(.icon)
                }
            }
            Menu {
                ForEach(geminiTokens) {
                    addTokenButton($0, previewWidth: geminiPreviewWidth)
                }
                addStackButton(
                    tokens: [.geminiPaceRemaining, .geminiPaceDelta],
                    previewWidth: geminiPreviewWidth
                )
                addStackButton(
                    tokens: [.geminiPrimary, .geminiSecondary],
                    previewWidth: geminiPreviewWidth
                )
                addStackButton(
                    tokens: [.geminiFiveHourPaceRemaining, .geminiFiveHourPaceDelta],
                    previewWidth: geminiPreviewWidth
                )
                addStackButton(
                    tokens: [.geminiWeeklyPaceRemaining, .geminiWeeklyPaceDelta],
                    previewWidth: geminiPreviewWidth
                )
            } label: {
                menuLabel(title: "Antigravity") {
                    menuTokenPreview(.geminiIcon)
                }
            }
            addTokenButton(.space)
            addTokenButton(.separator)
            addEmptyStackButton
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("添加菜单栏内容")
    }

    /// 添加一个独立内容；重复内容由布局模型拒绝，菜单中同步呈现禁用状态。
    @ViewBuilder
    private func addTokenButton(
        _ token: MenuBarLayoutToken,
        previewWidth: CGFloat? = nil
    ) -> some View {
        Button {
            commit(layout.addingItem(token))
        } label: {
            menuTokenLabel(token, previewWidth: previewWidth)
        }
        .disabled(layout.addingItem(token) == layout)
    }

    /// 添加一个预先定义的堆叠容器；组合项目只保留一次窗口名称，避免菜单标题重复。
    @ViewBuilder
    private func addStackButton(
        tokens: [MenuBarLayoutToken],
        previewWidth: CGFloat? = nil
    ) -> some View {
        Button {
            commit(layout.addingStack(tokens))
        } label: {
            menuLabel(title: stackTitle(for: tokens)) {
                menuStackPreview(tokens, previewWidth: previewWidth)
            }
        }
        .disabled(layout.addingStack(tokens) == layout)
    }

    /// 生成预设堆叠的菜单标题；同一窗口的预期偏差不再重复写窗口名称。
    private func stackTitle(for tokens: [MenuBarLayoutToken]) -> String {
        var titleParts = tokens.map { AppLocalization.string($0.title) }
        switch tokens {
        case [.fiveHourPaceRemaining, .fiveHourPaceDelta],
             [.geminiFiveHourPaceRemaining, .geminiFiveHourPaceDelta],
             [.weeklyPaceRemaining, .weeklyPaceDelta],
             [.geminiWeeklyPaceRemaining, .geminiWeeklyPaceDelta]:
            titleParts[1] = AppLocalization.string(MenuBarLayoutToken.paceDelta.title)
        default:
            break
        }
        return titleParts.joined(separator: " + ")
    }

    /// 在一级添加菜单中创建空容器；容器本身不预置任何内容。
    @ViewBuilder
    private var addEmptyStackButton: some View {
        Button {
            commit(layout.addingEmptyContainer())
        } label: {
            menuLabel(title: "堆叠容器") {
                menuSystemImagePreview("square.stack.3d.up")
            }
        }
        .disabled(layout.addingEmptyContainer() == layout)
    }

    /// 绘制添加菜单中的实时内容；按内容自然撑开，但不超过左侧预览列上限。
    @ViewBuilder
    private func menuTokenPreview(
        _ token: MenuBarLayoutToken,
        previewWidth: CGFloat? = nil
    ) -> some View {
        let image = menuTokenImage(token, previewWidth: previewWidth)
        Image(nsImage: image)
            .frame(width: image.size.width, height: 22, alignment: .leading)
    }

    /// 绘制空容器的系统图标；槽位与其他菜单图标保持相同自然宽度。
    @ViewBuilder
    private func menuSystemImagePreview(_ name: String) -> some View {
        Image(nsImage: menuSystemImage(named: name))
            .frame(width: 18, height: 22, alignment: .leading)
            .clipped()
    }

    /// 绘制“实时内容图标 + 右侧名称”的菜单项，避免原生 Menu 按完整内容重新放大布局。
    @ViewBuilder
    private func menuTokenLabel(
        _ token: MenuBarLayoutToken,
        previewWidth: CGFloat? = nil
    ) -> some View {
        menuLabel(title: AppLocalization.string(token.title)) {
            menuTokenPreview(token, previewWidth: previewWidth)
        }
    }

    /// 使用原生 Label 的 title/icon 双列布局；显式锁定系统菜单字体和行高，避免首次测量后尺寸漂移。
    @ViewBuilder
    private func menuLabel<Icon: View>(
        title: String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Label {
            Text(title)
                .font(Font(NSFont.menuFont(ofSize: 0)))
                .lineLimit(1)
                .frame(height: 22, alignment: .center)
        } icon: {
            icon()
                .frame(height: 22, alignment: .center)
        }
        .labelStyle(.titleAndIcon)
        .frame(minHeight: 22, alignment: .center)
    }

    /// 绘制预设堆叠的双行实时内容；两行取最大实际宽度，避免其中一行被裁切。
    @ViewBuilder
    private func menuStackPreview(
        _ tokens: [MenuBarLayoutToken],
        previewWidth: CGFloat? = nil
    ) -> some View {
        let image = menuStackImage(tokens, previewWidth: previewWidth)
        Image(nsImage: image)
            .frame(width: image.size.width, height: 22, alignment: .leading)
    }

    /// 把系统符号绘制到自然宽度的菜单图像中，避免空容器把标题额外推远。
    private func menuSystemImage(named name: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 22))
        image.lockFocus()
        defer { image.unlockFocus() }
        drawMenuImage(named: name, in: imageBounds(width: 16, height: 16))
        return image
    }

    /// 计算左侧实时内容的自然宽度；内容不足时不补空白，超出 60pt 时由绘制层省略。
    private func menuTokenPreviewWidth(for token: MenuBarLayoutToken) -> CGFloat {
        let naturalWidth: CGFloat
        if let line = liveLine(for: token), !line.value.isEmpty, line.value != "--" {
            let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
            naturalWidth = ceil((line.value as NSString).size(withAttributes: [.font: font]).width) + 2
        } else if liveUsageBar(for: token) != nil {
            naturalWidth = 18
        } else {
            switch token {
            case .icon:
                naturalWidth = 18
            case .geminiIcon:
                naturalWidth = 16
            case .separator:
                // 分隔点虽只有一个字符，也要占用与其他一级菜单图标相同的槽位。
                naturalWidth = 18
            default:
                naturalWidth = 16
            }
        }
        return min(naturalWidth, 60)
    }

    /// 计算同一层菜单的统一左列宽度；按该层最长内容取值，并受 60pt 上限约束。
    private func menuTokenPreviewColumnWidth(for tokens: [MenuBarLayoutToken]) -> CGFloat {
        tokens.map { menuTokenPreviewWidth(for: $0) }.max() ?? 16
    }

    /// 将实时文字或系统图标绘制到固定宽度的 NSImage，超长内容统一尾部省略。
    private func menuTokenImage(
        _ token: MenuBarLayoutToken,
        previewWidth: CGFloat? = nil,
        height: CGFloat = 22,
        fontSize: CGFloat = 12
    ) -> NSImage {
        let imageWidth = previewWidth ?? menuTokenPreviewWidth(for: token)
        let image = NSImage(size: NSSize(width: imageWidth, height: height))
        image.lockFocus()
        defer { image.unlockFocus() }

        if let usageBar = liveUsageBar(for: token) {
            let diameter = max(1, min(18, image.size.height - 2))
            drawMenuUsageBar(
                usageBar,
                in: NSRect(
                    x: 0,
                    y: (image.size.height - diameter) / 2,
                    width: diameter,
                    height: diameter
                )
            )
            return image
        }

        if let line = liveLine(for: token),
           !line.value.isEmpty,
           line.value != "--" {
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: line.usesUsageColor
                    ? NSColor(line.tone.statusBarColor(settings: settings))
                    : NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
            let text = NSAttributedString(string: line.value, attributes: attributes)
            let textHeight = min(image.size.height, ceil(text.size().height))
            let textRect = NSRect(
                x: 0,
                y: max(0, floor((image.size.height - textHeight) / 2)),
                width: image.size.width,
                height: textHeight
            )
            text.draw(
                with: textRect,
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
            )
            return image
        }

        switch token {
        case .icon:
            let iconSize = max(1, min(18, image.size.height - 2))
            drawMenuImage(
                named: "OpenAIStatusIcon",
                in: imageBounds(width: iconSize, height: iconSize, containerHeight: image.size.height)
            )
        case .geminiIcon:
            let iconSize = max(1, min(16, image.size.height - 2))
            drawMenuImage(
                named: "sparkles",
                in: imageBounds(width: iconSize, height: iconSize, containerHeight: image.size.height)
            )
        case .separator:
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            let separator = NSAttributedString(string: "·", attributes: attributes)
            let separatorSize = separator.size()
            separator.draw(
                at: NSPoint(
                    x: max(0, (image.size.width - separatorSize.width) / 2),
                    y: max(0, (image.size.height - separatorSize.height) / 2)
                )
            )
        case .space:
            let iconSize = max(1, min(16, image.size.height - 2))
            drawMenuImage(
                named: token.systemImageName,
                in: imageBounds(width: iconSize, height: iconSize, containerHeight: image.size.height)
            )
        default:
            let iconSize = max(1, min(16, image.size.height - 2))
            drawMenuImage(
                named: token.systemImageName,
                in: imageBounds(width: iconSize, height: iconSize, containerHeight: image.size.height)
            )
        }
        return image
    }

    /// 将实时窗口剩余比例绘制成添加菜单左侧的饼图或双层环形图，保持与菜单栏预览一致。
    private func drawMenuUsageBar(
        _ display: MenuBarUsageBarDisplay,
        in rect: NSRect
    ) {
        let windows = Array(display.windows.prefix(2))
        guard !windows.isEmpty else { return }
        let diameter = min(rect.width, rect.height)
        let circleRect = NSRect(
            x: rect.midX - diameter / 2,
            y: rect.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        let center = NSPoint(x: circleRect.midX, y: circleRect.midY)
        if windows.count == 1, let window = windows.first {
            drawUsagePie(window, in: circleRect, center: center)
        } else if let first = windows.first, let second = windows.dropFirst().first {
            drawUsageRing(first, center: center, radius: diameter / 2 - 1.2, lineWidth: 2.3)
            drawUsageRing(second, center: center, radius: diameter / 2 - 4.2, lineWidth: 2.1)
        }
    }

    /// 绘制单窗口饼图；底色保留状态色的低透明度以标识 0% 窗口。
    private func drawUsagePie(
        _ window: MenuBarUsageWindowDisplay,
        in rect: NSRect,
        center: NSPoint
    ) {
        let color = NSColor(window.tone.statusBarColor(settings: settings))
        color.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: rect).fill()

        let fraction = CGFloat(max(0, min(100, window.remainingPercent))) / 100
        if fraction >= 0.999 {
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
        } else if fraction > 0 {
            let wedge = NSBezierPath()
            wedge.move(to: center)
            wedge.appendArc(
                withCenter: center,
                radius: rect.width / 2,
                startAngle: 90,
                endAngle: 90 - 360 * fraction,
                clockwise: true
            )
            wedge.close()
            color.setFill()
            wedge.fill()
        }

        let border = NSBezierPath(ovalIn: rect)
        NSColor.separatorColor.setStroke()
        border.lineWidth = 1
        border.stroke()
    }

    /// 绘制双窗口中的一层环形图；每一层单独使用对应窗口的状态色。
    private func drawUsageRing(
        _ window: MenuBarUsageWindowDisplay,
        center: NSPoint,
        radius: CGFloat,
        lineWidth: CGFloat
    ) {
        let color = NSColor(window.tone.statusBarColor(settings: settings))
        let track = NSBezierPath()
        track.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 360,
            clockwise: false
        )
        track.lineWidth = lineWidth
        color.withAlphaComponent(0.22).setStroke()
        track.stroke()

        let fraction = CGFloat(max(0, min(100, window.remainingPercent))) / 100
        guard fraction > 0 else { return }
        let progress = NSBezierPath()
        progress.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - 360 * fraction,
            clockwise: true
        )
        progress.lineWidth = lineWidth
        color.setStroke()
        progress.stroke()
    }

    /// 将两个实时内容合并为一个双行菜单图标，避免堆叠预设被系统拆成多个菜单行。
    private func menuStackImage(
        _ tokens: [MenuBarLayoutToken],
        previewWidth: CGFloat? = nil
    ) -> NSImage {
        let compactLineHeight: CGFloat = 10
        let tokenImages = tokens.prefix(2).map {
            menuTokenImage(
                $0,
                previewWidth: previewWidth,
                height: compactLineHeight,
                fontSize: 9
            )
        }
        let imageWidth = max(42, tokenImages.map(\.size.width).max() ?? 42)
        let image = NSImage(size: NSSize(width: imageWidth, height: 22))
        image.lockFocus()
        defer { image.unlockFocus() }

        for (index, tokenImage) in tokenImages.enumerated() {
            tokenImage.draw(
                in: NSRect(
                    x: 0,
                    y: image.size.height - compactLineHeight * CGFloat(index + 1),
                    width: tokenImage.size.width,
                    height: tokenImage.size.height
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }
        return image
    }

    /// 返回菜单图标的固定绘制区域；所有来源统一从左侧对齐，防止图标在不同菜单项中漂移。
    private func imageBounds(
        width: CGFloat,
        height: CGFloat,
        containerHeight: CGFloat = 22
    ) -> NSRect {
        NSRect(x: 0, y: (containerHeight - height) / 2, width: width, height: height)
    }

    /// 绘制资源或 SF Symbol；缺少资源时保持空白，不让菜单布局因占位文本改变尺寸。
    private func drawMenuImage(named name: String, in rect: NSRect) {
        guard let image = NSImage(named: name)
            ?? NSImage(systemSymbolName: name, accessibilityDescription: nil)
        else { return }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.labelColor.setFill()
        rect.fill(using: .sourceAtop)
    }

    /// 垃圾桶只接受拖放，不响应单击，避免拖动排序时误删项目。
    private var trashDropTarget: some View {
        Image(systemName: "trash")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .onDrop(
                of: [.text],
                delegate: MenuBarDropDelegate { providers in
                    handleDrop(providers, action: delete)
                }
            )
            .accessibilityLabel("拖到此处删除")
            .help("将内容拖到此处删除")
    }

    /// 用短字符串编码拖放来源，避免为了编辑器引入额外的 Transferable 类型。
    private func dragPayload(item: Int, index: Int) -> String {
        "token|\(item)|\(index)"
    }

    /// 判断布局项目是否为堆叠容器；空行标记也必须整体移动和删除。
    private func isStackItem(_ item: Int) -> Bool {
        guard layout.items.indices.contains(item) else { return false }
        let tokens = layout.items[item].filter { !$0.isStackPlaceholder }
        return tokens.count > 1 || layout.items[item].contains { $0.isStackPlaceholder }
    }

    /// 处理项目整体排序以及把一个内容拖入另一项目形成堆叠。
    private func drop(_ payload: String, toItem item: Int, index: Int) -> Bool {
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false)
        let updated: MenuBarLayout?
        if parts.first == "item", parts.count == 2 {
            if let sourceItem = Int(parts[1]),
               sourceItem != item,
               layout.items.indices.contains(sourceItem),
               layout.items.indices.contains(item),
               !isStackItem(sourceItem),
               layout.items[item].isEmpty || layout.items[item].contains(where: { $0.isStackPlaceholder }),
               let sourceIndex = layout.items[sourceItem].firstIndex(where: { !$0.isStackPlaceholder }) {
                let targetIndex = layout.items[item].firstIndex(of: .stackPlaceholder)
                    ?? layout.items[item].count
                return commit(
                    layout.moving(
                        from: sourceIndex,
                        inItem: sourceItem,
                        to: targetIndex,
                        inItem: item
                    )
                )
            }
            return dropItem(payload, at: item)
        } else if parts.first == "token",
                  parts.count == 3,
                  let sourceItem = Int(parts[1]),
                  let sourceIndex = Int(parts[2]) {
            if sourceItem != item,
               layout.items.indices.contains(sourceItem),
               layout.items.indices.contains(item),
               isStackItem(sourceItem) {
                return dropItem("item|\(sourceItem)", at: item)
            }
            updated = layout.moving(from: sourceIndex, inItem: sourceItem, to: index, inItem: item)
        } else {
            updated = nil
        }
        guard let updated else { return false }
        return commit(updated)
    }

    /// 末尾保留无视觉占位的宽拖放区，让项目可以拖到右侧空白处成为最后一项。
    private var trailingDropZone: some View {
        Color.clear
            .frame(minWidth: 160, maxWidth: .infinity, minHeight: MenuBarDisplaySettings().statusLabelHeight)
            .contentShape(Rectangle())
            .onDrop(
                of: [.text],
                delegate: MenuBarDropDelegate { providers in
                    handleDrop(providers, action: dropToEnd)
                }
            )
            .accessibilityHidden(true)
    }

    /// 从系统拖放提供者异步读取布局载荷，并在主线程提交一次布局变更。
    private func handleDrop(
        _ providers: [NSItemProvider],
        action: @escaping @MainActor @Sendable (String) -> Bool
    ) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let object = object as? NSString else { return }
            let payload = String(object)
            Task { @MainActor in
                _ = action(payload)
            }
        }
        return true
    }

    /// 处理拖到垃圾桶的项目或内容，并统一通过布局模型删除。
    private func delete(_ payload: String) -> Bool {
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false)
        if parts.first == "item",
           parts.count == 2,
           let item = Int(parts[1]) {
            return commit(layout.removingItem(at: item))
        }
        if parts.first == "token",
           parts.count == 3,
           let item = Int(parts[1]),
           let index = Int(parts[2]) {
            if isStackItem(item) {
                return commit(layout.removingItem(at: item))
            }
            return commit(layout.removing(at: index, inItem: item))
        }
        return false
    }

    /// 处理拖到空白区域的项目或内容；整项移动到末尾，内容则拆成末尾的独立项目。
    private func dropToEnd(_ payload: String) -> Bool {
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false)
        if parts.first == "item", parts.count == 2 {
            return dropItem(payload, at: layout.items.count)
        }
        if parts.first == "token",
           parts.count == 3,
           let item = Int(parts[1]),
           let index = Int(parts[2]) {
            if isStackItem(item) {
                return dropItem("item|\(item)", at: layout.items.count)
            }
            return commit(layout.detaching(at: index, inItem: item))
        }
        return false
    }

    /// 将整项插入指定落点；源项目位于落点左侧时需扣除移除自身造成的索引偏移。
    private func dropItem(_ payload: String, at position: Int) -> Bool {
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.first == "item",
              parts.count == 2,
              let source = Int(parts[1]) else {
            return false
        }

        let target = source < position ? position - 1 : position
        return commit(layout.movingItem(from: source, to: target))
    }

    /// 统一更新绑定和 UserDefaults，状态栏通过现有通知链立即重建。
    @discardableResult
    private func commit(_ updated: MenuBarLayout) -> Bool {
        let normalized = updated.normalized
        guard normalized != layout else { return false }
        layout = normalized
        menuTarget = nil
        onChange(normalized)
        return true
    }

}
