import AppKit
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
    @State private var stackRowTarget: MenuBarStackRowTarget?
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
            .dropDestination(for: String.self) { payloads, _ in
                guard let payload = payloads.first else { return false }
                return dropToEnd(payload)
            }
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
            let usesSingleLineTypography = layout.items.allSatisfy { item in
                !item.contains { $0.isStackPlaceholder }
                    && item.filter(shouldShowToken).count <= 1
            }
            VStack(alignment: .trailing, spacing: isStacked ? -2 : 0) {
                ForEach(
                    Array(layout.items[item].enumerated()).filter { shouldShowToken($0.element) },
                    id: \.offset
                ) { index, token in
                    tokenEditor(
                        token,
                        item: item,
                        index: index,
                        isStacked: !usesSingleLineTypography
                    )
                }
            }
            .frame(minHeight: MenuBarDisplaySettings().statusLabelHeight, alignment: .center)
            .contentShape(Rectangle())
            .draggable("item|\(item)") {
                itemDragPreview(item)
            }
            .dropDestination(for: String.self) { payloads, _ in
                guard let payload = payloads.first else { return false }
                return drop(payload, toItem: item, index: layout.items[item].count)
            }
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
            .draggable("item|\(item)") {
                itemDragPreview(item)
            }
            .dropDestination(for: String.self) { payloads, _ in
                guard let payload = payloads.first else { return false }
                return drop(payload, toItem: item, index: 0)
            }
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
        return liveTokenContent(token, isStacked: isStacked, isDisabled: isDisabled)
            .foregroundStyle(isDisabled ? Color.secondary.opacity(0.5) : Color.primary)
            .contentShape(Rectangle())
            .onTapGesture {
                menuTarget = target
            }
            .popover(item: editorMenuBinding(for: target), arrowEdge: .bottom) { target in
                editorMenu(for: target)
            }
        .draggable(dragPayload(item: item, index: index)) {
            itemDragPreview(item)
        }
        .dropDestination(for: String.self) { payloads, _ in
            guard let payload = payloads.first else { return false }
            return drop(payload, toItem: item, index: index)
        }
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
            VStack(alignment: .trailing, spacing: stacked ? -2 : 0) {
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
            .frame(minWidth: 280, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
            }
        } else if let index = target.index,
                  layout.items.indices.contains(target.item),
                  layout.items[target.item].indices.contains(index) {
            let token = layout.items[target.item][index]
            VStack(alignment: .leading, spacing: 2) {
                if layout.items[target.item].count > 1 {
                    stackConfiguration(item: target.item)
                    Divider()
                        .padding(.vertical, 2)
                }
                if !token.isProviderIcon {
                    Button("拆成独立项目") {
                        commit(layout.detaching(at: index, inItem: target.item))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                }
                Divider()
                    .padding(.vertical, 2)
                Button("删除此内容", role: .destructive) {
                    commit(layout.removing(at: index, inItem: target.item))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                Button("删除整个项目", role: .destructive) {
                    commit(layout.removingItem(at: target.item))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
            }
            .padding(8)
            .frame(minWidth: 280, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)
            }
        }
    }

    /// 返回容器可配置的非图标项目；图标始终作为独立菜单栏项目存在。
    private var stackConfigurationTokens: [MenuBarLayoutToken] {
        var tokens: [MenuBarLayoutToken] = [.primary, .secondary, .paceRemaining, .paceDelta]
        if geminiSettings.isEnabled {
            tokens += [.geminiPrimary, .geminiSecondary, .geminiPaceRemaining, .geminiPaceDelta]
        }
        return tokens
    }

    /// 显示堆叠容器的两行配置；选项菜单直接展示当前实时内容，不再显示抽象占位名称。
    @ViewBuilder
    private func stackConfiguration(item: Int) -> some View {
        stackRowMenu(item: item, row: 0)
        stackRowMenu(item: item, row: 1)
    }

    /// 绘制一行配置菜单；使用自定义弹出面板保持与添加菜单的材质和圆角一致。
    @ViewBuilder
    private func stackRowMenu(item: Int, row: Int) -> some View {
        let target = MenuBarStackRowTarget(item: item, row: row)
        Button {
            stackRowTarget = target
        } label: {
            if let token = stackRowToken(item: item, row: row) {
                menuLabel(title: "第 \(row + 1) 行 · \(AppLocalization.string(token.title))") {
                    menuTokenPreview(token)
                }
            } else {
                menuLabel(title: "第 \(row + 1) 行 · 空") {
                    Color.clear
                        .frame(width: 42, height: 22)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popover(item: stackRowPopoverBinding(for: target), arrowEdge: .bottom) { target in
            stackRowPicker(for: target)
        }
    }

    /// 返回堆叠容器指定行的真实内容；空行标记只用于维持容器，不显示给用户。
    private func stackRowToken(item: Int, row: Int) -> MenuBarLayoutToken? {
        guard layout.items.indices.contains(item), layout.items[item].indices.contains(row) else {
            return nil
        }
        let token = layout.items[item][row]
        return token.isStackPlaceholder ? nil : token
    }

    /// 绑定当前行的选择弹出层，避免多个行按钮共享一个原生 Menu 状态。
    private func stackRowPopoverBinding(
        for target: MenuBarStackRowTarget
    ) -> Binding<MenuBarStackRowTarget?> {
        Binding(
            get: {
                stackRowTarget == target ? target : nil
            },
            set: { updatedTarget in
                stackRowTarget = updatedTarget
            }
        )
    }

    /// 绘制行选择面板；选择后只关闭行面板，保留外层容器配置面板继续填写另一行。
    @ViewBuilder
    private func stackRowPicker(for target: MenuBarStackRowTarget) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button("清空") {
                commitStackRow(nil, target: target)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)

            Divider()
                .padding(.vertical, 2)

            ForEach(stackConfigurationTokens) { token in
                Button {
                    commitStackRow(token, target: target)
                } label: {
                    menuTokenLabel(token)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
            }
        }
        .padding(8)
        .frame(minWidth: 280, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
        }
    }

    /// 写入堆叠行并保留父级编辑菜单，确保第一行填完后第二行不会丢失。
    private func commitStackRow(
        _ token: MenuBarLayoutToken?,
        target: MenuBarStackRowTarget
    ) {
        let updated = layout.replacingStackToken(token, at: target.row, inItem: target.item).normalized
        guard updated != layout else {
            stackRowTarget = nil
            return
        }
        layout = updated
        stackRowTarget = nil
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
        if let line = liveLine(for: token) {
            HStack(spacing: CGFloat(settings.itemSpacing)) {
                if !line.label.isEmpty {
                    Text(line.label)
                }
                Text(line.value)
                    .foregroundStyle(
                        isDisabled
                            ? Color.secondary.opacity(0.5)
                            : line.tone.statusBarColor(settings: settings)
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
                Color.clear
                    .frame(width: max(4, CGFloat(settings.itemSpacing)))
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
        case .primary, .secondary, .paceRemaining, .paceDelta:
            return StatusLineDisplay.layoutLine(
                for: token,
                snapshot: snapshot,
                settings: settings
            )
        case .geminiPrimary, .geminiSecondary, .geminiPaceRemaining, .geminiPaceDelta,
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

    /// 加号打开原生分级菜单；菜单锚定在加号下方，避免使用独立 popover 造成居中漂移。
    private var addMenu: some View {
        Menu {
            Menu {
                ForEach([.icon, .primary, .secondary, .paceRemaining, .paceDelta] as [MenuBarLayoutToken]) {
                    addTokenButton($0)
                }
                addStackButton(tokens: [.paceRemaining, .paceDelta])
                addStackButton(tokens: [.primary, .secondary])
            } label: {
                menuLabel(title: "Codex") {
                    menuSystemImagePreview("circle.dashed")
                }
            }
            Menu {
                ForEach([
                    .geminiIcon,
                    .geminiPrimary,
                    .geminiSecondary,
                    .geminiPaceRemaining,
                    .geminiPaceDelta
                ] as [MenuBarLayoutToken]) {
                    addTokenButton($0)
                }
                addStackButton(tokens: [.geminiPaceRemaining, .geminiPaceDelta])
                addStackButton(tokens: [.geminiPrimary, .geminiSecondary])
            } label: {
                menuLabel(title: "Antigravity") {
                    menuSystemImagePreview("sparkles")
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
    private func addTokenButton(_ token: MenuBarLayoutToken) -> some View {
        Button {
            commit(layout.addingItem(token))
        } label: {
            menuTokenLabel(token)
        }
        .disabled(layout.addingItem(token) == layout)
    }

    /// 添加一个预先定义的堆叠容器；用户仍可在预览中拖动其中内容调整顺序。
    @ViewBuilder
    private func addStackButton(tokens: [MenuBarLayoutToken]) -> some View {
        Button {
            commit(layout.addingStack(tokens))
        } label: {
            menuLabel(
                title: tokens.map { AppLocalization.string($0.title) }.joined(separator: " + ")
            ) {
                menuStackPreview(tokens)
            }
        }
        .disabled(layout.addingStack(tokens) == layout)
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

    /// 绘制添加菜单中的固定宽度实时内容；它只承担“图标”区域，右侧文字由菜单项单独提供。
    @ViewBuilder
    private func menuTokenPreview(_ token: MenuBarLayoutToken) -> some View {
        Image(nsImage: menuTokenImage(token))
            .frame(width: 42, height: 22, alignment: .leading)
            .clipped()
    }

    /// 绘制一级菜单分类和空容器使用的固定系统图标槽位，避免原生 Label 与实时图像错列。
    @ViewBuilder
    private func menuSystemImagePreview(_ name: String) -> some View {
        Image(nsImage: menuSystemImage(named: name))
            .frame(width: 42, height: 22, alignment: .leading)
            .clipped()
    }

    /// 绘制“实时内容图标 + 右侧名称”的菜单项，避免原生 Menu 按完整内容重新放大布局。
    @ViewBuilder
    private func menuTokenLabel(_ token: MenuBarLayoutToken) -> some View {
        menuLabel(title: AppLocalization.string(token.title)) {
            menuTokenPreview(token)
        }
    }

    /// 使用原生 Label 的 title/icon 双列布局，避免自定义 HStack 被 NSMenu 拆成多行。
    @ViewBuilder
    private func menuLabel<Icon: View>(
        title: String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Label {
            Text(title)
        } icon: {
            icon()
        }
        .labelStyle(.titleAndIcon)
    }

    /// 绘制预设堆叠的双行实时图标；两行共享固定宽度，右侧仍显示预设名称。
    @ViewBuilder
    private func menuStackPreview(_ tokens: [MenuBarLayoutToken]) -> some View {
        Image(nsImage: menuStackImage(tokens))
            .frame(width: 42, height: 39, alignment: .leading)
            .clipped()
    }

    /// 把系统符号绘制到统一宽度的菜单图像中，确保所有一级菜单共享同一左边界。
    private func menuSystemImage(named name: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 42, height: 22))
        image.lockFocus()
        defer { image.unlockFocus() }
        drawMenuImage(named: name, in: imageBounds(width: 16, height: 16))
        return image
    }

    /// 将实时文字或系统图标绘制成 NSImage，让原生菜单把它当作真正的左侧 image，而不是可重排的文本视图。
    private func menuTokenImage(_ token: MenuBarLayoutToken) -> NSImage {
        let image = NSImage(size: NSSize(width: 42, height: 22))
        image.lockFocus()
        defer { image.unlockFocus() }

        if let line = liveLine(for: token),
           !line.value.isEmpty,
           line.value != "--" {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor(line.tone.statusBarColor(settings: settings))
            ]
            let text = NSAttributedString(string: line.value, attributes: attributes)
            let textSize = text.size()
            text.draw(
                at: NSPoint(
                    x: 0,
                    y: max(0, (22 - textSize.height) / 2)
                )
            )
            return image
        }

        switch token {
        case .icon:
            drawMenuImage(named: "OpenAIStatusIcon", in: imageBounds(width: 18, height: 18))
        case .geminiIcon:
            drawMenuImage(named: "sparkles", in: imageBounds(width: 16, height: 16))
        case .separator:
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            NSAttributedString(string: "·", attributes: attributes).draw(at: NSPoint(x: 2, y: 1))
        case .space:
            drawMenuImage(named: token.systemImageName, in: imageBounds(width: 16, height: 16))
        default:
            drawMenuImage(named: token.systemImageName, in: imageBounds(width: 16, height: 16))
        }
        return image
    }

    /// 将两个实时内容合并为一个双行菜单图标，避免堆叠预设被系统拆成多个菜单行。
    private func menuStackImage(_ tokens: [MenuBarLayoutToken]) -> NSImage {
        let image = NSImage(size: NSSize(width: 42, height: 39))
        image.lockFocus()
        defer { image.unlockFocus() }

        for (index, token) in tokens.prefix(2).enumerated() {
            let tokenImage = menuTokenImage(token)
            tokenImage.draw(
                in: NSRect(x: 0, y: CGFloat(17 - index * 17), width: 42, height: 22),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }
        return image
    }

    /// 返回菜单图标的固定绘制区域；所有来源统一从左侧对齐，防止图标在不同菜单项中漂移。
    private func imageBounds(width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(x: 0, y: (22 - height) / 2, width: width, height: height)
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
            .dropDestination(for: String.self) { payloads, _ in
                guard let payload = payloads.first else { return false }
                return delete(payload)
            }
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
            .dropDestination(for: String.self) { payloads, _ in
                guard let payload = payloads.first else { return false }
                return dropToEnd(payload)
            }
            .accessibilityHidden(true)
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
