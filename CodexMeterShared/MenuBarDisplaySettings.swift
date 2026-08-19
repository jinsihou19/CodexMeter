import Foundation
import SwiftUI

public enum MenuBarPreferenceKeys {
    public static let displayDefaultsVersion = "menuBar.displayDefaultsVersion"
    public static let contentMode = "menuBar.contentMode"
    public static let layoutDensity = "menuBar.layoutDensity"
    public static let itemSpacing = "menuBar.itemSpacing"
    public static let rowSpacing = "menuBar.rowSpacing"
    public static let numberFontSize = "menuBar.numberFontSize"
    public static let numberFontWeight = "menuBar.numberFontWeight"
    public static let goodColorHex = "menuBar.goodColorHex"
    public static let warningColorHex = "menuBar.warningColorHex"
    public static let dangerColorHex = "menuBar.dangerColorHex"
    public static let showsPrimaryWindow = "menuBar.showsPrimaryWindow"
    public static let showsSecondaryWindow = "menuBar.showsSecondaryWindow"
    public static let hiddenWindowDurationMins = "menuBar.hiddenWindowDurationMins"
    public static let showsPercentSymbol = "menuBar.showsPercentSymbol"
    public static let showsAdditionalLimits = "menuBar.showsAdditionalLimits"
    public static let showsMenuBarIcon = "menuBar.showsMenuBarIcon"
    public static let showsHookActivityLight = "menuBar.showsHookActivityLight"
    public static let hookActivityIndicatorStyle = "menuBar.hookActivityIndicatorStyle"
    public static let weeklyProgressWorkDays = "menuBar.weeklyProgressWorkDays"
    public static let layout = "menuBar.layout"

    public static let allKeys = [
        contentMode,
        layoutDensity,
        itemSpacing,
        rowSpacing,
        numberFontSize,
        numberFontWeight,
        goodColorHex,
        warningColorHex,
        dangerColorHex,
        showsPrimaryWindow,
        showsSecondaryWindow,
        hiddenWindowDurationMins,
        showsPercentSymbol,
        showsAdditionalLimits,
        showsMenuBarIcon,
        showsHookActivityLight,
        hookActivityIndicatorStyle,
        weeklyProgressWorkDays,
        layout
    ]
}

/// 菜单栏可编排的最小展示单元；布局只负责顺序和分行，字号、颜色等仍由现有设置控制。
public enum MenuBarLayoutToken: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case icon
    case primary
    case secondary
    case paceRemaining
    case paceDelta
    case fiveHourPaceRemaining
    case fiveHourPaceDelta
    case weeklyPaceRemaining
    case weeklyPaceDelta
    case provider
    case account
    case plan
    case usageBar
    case resetCountdown
    case resetTime
    case depletionETA
    case balance
    case todayCost
    case monthCost
    case geminiIcon
    case geminiPrimary
    case geminiSecondary
    case geminiPaceRemaining
    case geminiPaceDelta
    case geminiFiveHourPaceRemaining
    case geminiFiveHourPaceDelta
    case geminiWeeklyPaceRemaining
    case geminiWeeklyPaceDelta
    case geminiProvider
    case geminiAccount
    case geminiPlan
    case geminiUsageBar
    case geminiResetCountdown
    case geminiResetTime
    case geminiDepletionETA
    case geminiBalance
    case geminiTodayCost
    case geminiMonthCost
    // 旧版持久化布局仍可能写入这两个值；保留解码兼容，新增菜单不再展示它们。
    case geminiRemaining
    case geminiDelta
    case separator
    case space
    case stackPlaceholder

    public var id: String {
        rawValue
    }

    /// 返回设置页中展示的中文名称；外层可继续通过 AppLocalization 处理英文翻译。
    public var title: String {
        switch self {
        case .icon:
            return "图标"
        case .primary:
            return "5 小时"
        case .secondary:
            return "7 天"
        case .paceRemaining:
            return "自动剩余"
        case .paceDelta:
            return "预期偏差"
        case .fiveHourPaceRemaining:
            return "5 小时剩余"
        case .fiveHourPaceDelta:
            return "5 小时预期偏差"
        case .weeklyPaceRemaining:
            return "7 天剩余"
        case .weeklyPaceDelta:
            return "7 天预期偏差"
        case .provider, .geminiProvider:
            return "提供商名"
        case .account, .geminiAccount:
            return "账号"
        case .plan, .geminiPlan:
            return "套餐"
        case .usageBar, .geminiUsageBar:
            return "用量条"
        case .resetCountdown, .geminiResetCountdown:
            return "重置倒计时"
        case .resetTime, .geminiResetTime:
            return "重置时间"
        case .depletionETA, .geminiDepletionETA:
            return "预计耗尽"
        case .balance, .geminiBalance:
            return "余额"
        case .todayCost, .geminiTodayCost:
            return "今日费用"
        case .monthCost, .geminiMonthCost:
            return "月度费用"
        case .geminiIcon:
            return "图标"
        case .geminiPrimary, .geminiDelta:
            return "5 小时"
        case .geminiSecondary, .geminiRemaining:
            return "7 天"
        case .geminiPaceRemaining:
            return "自动剩余"
        case .geminiPaceDelta:
            return "预期偏差"
        case .geminiFiveHourPaceRemaining:
            return "5 小时剩余"
        case .geminiFiveHourPaceDelta:
            return "5 小时预期偏差"
        case .geminiWeeklyPaceRemaining:
            return "7 天剩余"
        case .geminiWeeklyPaceDelta:
            return "7 天预期偏差"
        case .separator:
            return "分隔点"
        case .space:
            return "空格"
        case .stackPlaceholder:
            return "空"
        }
    }

    /// 返回原生符号名称，供编辑器在不引入新图片资源的情况下保持视觉识别。
    public var systemImageName: String {
        switch self {
        case .icon:
            return "square.dashed"
        case .primary, .secondary:
            return "percent"
        case .paceRemaining:
            return "gauge.with.dots.needle.33percent"
        case .paceDelta:
            return "chart.line.uptrend.xyaxis"
        case .fiveHourPaceRemaining, .weeklyPaceRemaining:
            return "gauge.with.dots.needle.33percent"
        case .fiveHourPaceDelta, .weeklyPaceDelta:
            return "chart.line.uptrend.xyaxis"
        case .provider, .geminiProvider:
            return "building.2"
        case .account, .geminiAccount:
            return "person.crop.circle"
        case .plan, .geminiPlan:
            return "person.text.rectangle"
        case .usageBar, .geminiUsageBar:
            return "chart.bar.fill"
        case .resetCountdown, .geminiResetCountdown:
            return "timer"
        case .resetTime, .geminiResetTime:
            return "clock"
        case .depletionETA, .geminiDepletionETA:
            return "hourglass"
        case .balance, .geminiBalance:
            return "creditcard"
        case .todayCost, .geminiTodayCost:
            return "dollarsign.circle"
        case .monthCost, .geminiMonthCost:
            return "calendar"
        case .geminiIcon:
            return "sparkles"
        case .geminiPrimary, .geminiSecondary, .geminiPaceRemaining, .geminiPaceDelta,
             .geminiFiveHourPaceRemaining, .geminiFiveHourPaceDelta,
             .geminiWeeklyPaceRemaining, .geminiWeeklyPaceDelta,
             .geminiRemaining, .geminiDelta:
            return "percent"
        case .separator:
            return "circle"
        case .space:
            return "rectangle"
        case .stackPlaceholder:
            return "square.dashed"
        }
    }

    /// 只有装饰性项目允许重复；额度和图标项目重复会让状态栏失去明确语义。
    public var allowsDuplicates: Bool {
        self == .separator || self == .space || self == .stackPlaceholder
    }

    /// 图标项目必须独立成项；Codex 与 Antigravity 各自保留自己的图标位置。
    public var isProviderIcon: Bool {
        self == .icon || self == .geminiIcon
    }

    /// 标记堆叠容器尚未填满的行；它只存在于布局模型中，不参与菜单栏渲染。
    public var isStackPlaceholder: Bool {
        self == .stackPlaceholder
    }

    /// 判断项目是否属于 Antigravity，供布局解析决定是否启用旧的尾部兼容渲染。
    public var isGeminiToken: Bool {
        switch self {
        case .geminiIcon, .geminiPrimary, .geminiSecondary, .geminiPaceRemaining, .geminiPaceDelta,
             .geminiFiveHourPaceRemaining, .geminiFiveHourPaceDelta,
             .geminiWeeklyPaceRemaining, .geminiWeeklyPaceDelta,
             .geminiProvider, .geminiAccount, .geminiPlan, .geminiUsageBar,
             .geminiResetCountdown, .geminiResetTime, .geminiDepletionETA, .geminiBalance,
             .geminiTodayCost, .geminiMonthCost, .geminiRemaining, .geminiDelta:
            return true
        default:
            return false
        }
    }
}

/// 菜单栏布局的持久化模型；外层项目横向排列，项目内部最多上下堆叠两项。
public struct MenuBarLayout: Codable, Equatable, Sendable {
    public static let defaultStacked = MenuBarLayout(items: [
        [.icon],
        [.paceRemaining, .paceDelta],
        [.geminiIcon],
        [.geminiPaceRemaining, .geminiPaceDelta]
    ])

    public static let horizontal = MenuBarLayout(items: [
        [.icon],
        [.paceRemaining],
        [.paceDelta],
        [.geminiIcon],
        [.geminiPrimary],
        [.geminiSecondary],
        [.geminiPaceRemaining],
        [.geminiPaceDelta]
    ])

    /// 菜单栏中的横向项目；每个内层数组代表一个项目的上下堆叠内容。
    public var items: [[MenuBarLayoutToken]]

    /// 归一化外部或旧版本数据，确保图标独立、堆叠不超过两项且不会撑破状态栏。
    public init(items: [[MenuBarLayoutToken]]) {
        var seen: Set<MenuBarLayoutToken> = []
        var normalizedItems: [[MenuBarLayoutToken]] = []

        for item in items.prefix(12) {
            // 空数组是旧版本空容器；迁移成两个显式空槽，才能区分“第一行空、第二行有内容”。
            let isStackContainer = item.isEmpty || item.contains { $0.isStackPlaceholder }
            var stack: [MenuBarLayoutToken] = []
            let sourceTokens: [MenuBarLayoutToken]
            if item.isEmpty {
                sourceTokens = [.stackPlaceholder, .stackPlaceholder]
            } else if isStackContainer {
                var slots = Array(item.prefix(2))
                while slots.count < 2 {
                    slots.append(.stackPlaceholder)
                }
                sourceTokens = slots
            } else {
                sourceTokens = Array(item.prefix(2))
            }
            for token in sourceTokens {
                if token.isStackPlaceholder {
                    stack.append(token)
                    continue
                }
                if token.isProviderIcon {
                    guard seen.insert(token).inserted else { continue }
                    if !stack.isEmpty {
                        normalizedItems.append(stack)
                        stack.removeAll(keepingCapacity: true)
                    }
                    normalizedItems.append([token])
                    continue
                }
                guard token.allowsDuplicates || seen.insert(token).inserted else { continue }
                stack.append(token)
            }
            if isStackContainer {
                var slots = Array(stack.prefix(2))
                while slots.count < 2 {
                    slots.append(.stackPlaceholder)
                }
                normalizedItems.append(slots)
            } else if !stack.isEmpty {
                normalizedItems.append(stack)
            }
        }

        if normalizedItems.isEmpty {
            normalizedItems = [[.paceRemaining]]
        }
        self.items = normalizedItems
    }

    /// 堆叠预设是普通自定义布局的一种，设置页只需把它重新填入编辑器。
    public var isDefaultStacked: Bool {
        self == Self.defaultStacked
    }

    /// 读取布局中是否包含独立图标项目，供旧的“显示图标”快捷开关复用。
    public var containsIcon: Bool {
        items.flatMap { $0 }.contains(.icon)
    }

    /// 读取布局中是否包含 Antigravity 项目；旧布局没有该字段时由存储层补入默认项目。
    public var containsGeminiTokens: Bool {
        items.flatMap { $0 }.contains(where: \.isGeminiToken)
    }

    /// 返回安全副本，避免编辑器的临时数组绕过项目和堆叠约束。
    public var normalized: MenuBarLayout {
        MenuBarLayout(items: items)
    }

    /// 把项目堆叠到指定菜单栏项目；图标始终保持独立，不进入其他堆叠。
    public func adding(_ token: MenuBarLayoutToken, toItem item: Int) -> MenuBarLayout {
        guard items.indices.contains(item), !token.isProviderIcon,
              !token.isStackPlaceholder,
              hasOpenStackSlot(at: item),
              token.allowsDuplicates || !items.flatMap({ $0 }).contains(token)
        else {
            return self
        }
        var updated = items
        if updated[item].isEmpty {
            updated[item] = [token, .stackPlaceholder]
        } else if let placeholderIndex = updated[item].firstIndex(where: { $0.isStackPlaceholder }) {
            updated[item].insert(token, at: placeholderIndex)
        } else {
            updated[item].append(token)
        }
        return MenuBarLayout(items: updated)
    }

    /// 新建一个横向独立项目；图标也通过此入口加入，保证其不会被堆叠。
    public func addingItem(_ token: MenuBarLayoutToken) -> MenuBarLayout {
        guard items.count < 12,
              !token.isStackPlaceholder,
              token.allowsDuplicates || !items.flatMap({ $0 }).contains(token)
        else {
            return self
        }
        return MenuBarLayout(items: items + [[token]])
    }

    /// 新建一个预设堆叠项目；提供商图标不允许进入容器，避免破坏图标独立规则。
    public func addingStack(_ tokens: [MenuBarLayoutToken]) -> MenuBarLayout {
        guard items.count < 12,
              tokens.count > 1,
              tokens.count <= 2,
              tokens.allSatisfy({ !$0.isProviderIcon && !$0.isStackPlaceholder })
        else {
            return self
        }
        return MenuBarLayout(items: items + [tokens])
    }

    /// 新建没有内容的堆叠容器；两个空槽让拖入项目可以明确落到第二行。
    public func addingEmptyContainer() -> MenuBarLayout {
        guard items.count < 12 else { return self }
        return MenuBarLayout(items: items + [[.stackPlaceholder, .stackPlaceholder]])
    }

    /// 替换堆叠容器的某一行；图标仍由独立项目承载，清空最后一行会保留空容器。
    public func replacingStackToken(
        _ token: MenuBarLayoutToken?,
        at row: Int,
        inItem item: Int
    ) -> MenuBarLayout {
        guard items.indices.contains(item), (0..<2).contains(row) else { return self }
        var updated = items
        var targetItem = item
        var content = updated[item].filter { !$0.isStackPlaceholder }
        guard row <= content.count else {
            return self
        }

        if row < content.count {
            content.remove(at: row)
        }

        if let token {
            guard !token.isProviderIcon, !token.isStackPlaceholder else {
                return self
            }
            if !token.allowsDuplicates {
                if let source = updated.indices.first(where: { index in
                    index != item && updated[index].contains(token)
                }) {
                    updated[source].removeAll { $0 == token }
                    if updated[source].isEmpty {
                        updated.remove(at: source)
                        if source < targetItem {
                            targetItem -= 1
                        }
                    }
                }
                guard !content.contains(token) else {
                    return self
                }
            }
            guard updated.indices.contains(targetItem) else {
                return self
            }
            content.insert(token, at: min(row, content.count))
        }

        if content.count < 2 {
            content.append(.stackPlaceholder)
        }
        updated[targetItem] = content
        return MenuBarLayout(items: updated)
    }

    /// 替换独立项目唯一的一项内容；不会添加堆叠占位符，也不会改变项目的横向位置。
    public func replacingItemToken(
        _ token: MenuBarLayoutToken,
        inItem item: Int
    ) -> MenuBarLayout {
        guard items.indices.contains(item),
              items[item].count == 1,
              !items[item][0].isStackPlaceholder,
              !token.isStackPlaceholder
        else {
            return self
        }

        var updated = items
        var targetItem = item
        if !token.allowsDuplicates,
           let source = updated.indices.first(where: { index in
               index != item && updated[index].contains(token)
           }) {
            updated[source].removeAll { $0 == token }
            if updated[source].isEmpty {
                updated.remove(at: source)
                if source < targetItem {
                    targetItem -= 1
                }
            }
        }
        guard updated.indices.contains(targetItem),
              !updated.dropFirst(targetItem + 1).contains(where: { $0.contains(token) }) else {
            return self
        }
        updated[targetItem] = [token]
        return MenuBarLayout(items: updated)
    }

    /// 判断项目是否还有可填入的堆叠行，供拖放逻辑区分占位行和真实内容。
    private func hasOpenStackSlot(at item: Int) -> Bool {
        guard items.indices.contains(item) else { return false }
        return items[item].filter { !$0.isStackPlaceholder }.count < 2
    }

    /// 删除指定菜单栏项目中的一个堆叠项；空项目会被移除。
    public func removing(at index: Int, inItem item: Int) -> MenuBarLayout {
        guard items.indices.contains(item), items[item].indices.contains(index) else {
            return self
        }
        var updated = items
        updated[item].remove(at: index)
        updated.removeAll(where: \.isEmpty)
        return MenuBarLayout(items: updated)
    }

    /// 删除整个横向项目；最后一个项目会由布局初始化器保留最小可用内容。
    public func removingItem(at item: Int) -> MenuBarLayout {
        guard items.indices.contains(item) else { return self }
        var updated = items
        updated.remove(at: item)
        return MenuBarLayout(items: updated)
    }

    /// 将项目内的一个内容拆成新的横向项目，供单击菜单中的排列配置使用。
    public func detaching(at index: Int, inItem item: Int) -> MenuBarLayout {
        guard items.indices.contains(item), items[item].indices.contains(index) else {
            return self
        }
        var updated = items
        let token = updated[item].remove(at: index)
        updated.removeAll(where: \.isEmpty)
        updated.append([token])
        return MenuBarLayout(items: updated)
    }

    /// 把内容拖到堆叠容器中；普通独立项目之间不自动形成堆叠。
    public func moving(
        from sourceIndex: Int,
        inItem sourceItem: Int,
        to targetIndex: Int,
        inItem targetItem: Int
    ) -> MenuBarLayout {
        guard items.indices.contains(sourceItem), items.indices.contains(targetItem),
              items[sourceItem].indices.contains(sourceIndex)
        else {
            return self
        }
        let targetIsStackContainer = items[targetItem].isEmpty
            || items[targetItem].contains { $0.isStackPlaceholder }
        guard sourceItem == targetItem
            || (targetIsStackContainer && hasOpenStackSlot(at: targetItem))
        else {
            return self
        }
        var updated = items
        let targetWasEmptyContainer = updated[targetItem].isEmpty
            || updated[targetItem].contains { $0.isStackPlaceholder }
        let token = updated[sourceItem].remove(at: sourceIndex)
        if sourceItem != targetItem, targetWasEmptyContainer {
            // 两行都为空时优先第二行；否则填入第一个实际空槽。
            var slots = Array(updated[targetItem].prefix(2))
            while slots.count < 2 {
                slots.append(.stackPlaceholder)
            }
            let targetRow = slots.allSatisfy(\.isStackPlaceholder)
                ? 1
                : (slots.firstIndex(of: .stackPlaceholder) ?? min(max(targetIndex, 0), 1))
            slots[targetRow] = token
            updated[targetItem] = slots
        } else {
            var insertionIndex = min(max(targetIndex, 0), updated[targetItem].count)
            if sourceItem == targetItem, sourceIndex < insertionIndex {
                insertionIndex -= 1
            }
            updated[targetItem].insert(token, at: insertionIndex)
            if targetWasEmptyContainer,
               !updated[targetItem].contains(where: { $0.isStackPlaceholder }) {
                updated[targetItem].append(.stackPlaceholder)
            }
        }
        updated.removeAll(where: \.isEmpty)
        return MenuBarLayout(items: updated)
    }

    /// 调整横向项目顺序；项目内部的堆叠顺序不受影响。
    public func movingItem(from source: Int, to target: Int) -> MenuBarLayout {
        guard items.indices.contains(source), items.indices.contains(target), source != target else {
            return self
        }
        var updated = items
        let item = updated.remove(at: source)
        updated.insert(item, at: min(max(target, 0), updated.count))
        return MenuBarLayout(items: updated)
    }

    /// 为旧版只包含 Codex 项目的布局补入 Antigravity 默认项目，迁移后即可继续编辑第二个提供商。
    public var addingDefaultGeminiItems: MenuBarLayout {
        guard !containsGeminiTokens else { return self }
        return MenuBarLayout(items: items + [
            [.geminiIcon],
            [.geminiPaceRemaining, .geminiPaceDelta]
        ])
    }
}

/// 菜单栏项目的内置入口；“堆叠”与横向布局都最终落成同一份可编辑模型。
public enum MenuBarLayoutPreset: String, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case stacked
    case horizontal
    case custom

    public var id: String {
        rawValue
    }

    /// 返回设置页中展示的排列名称。
    public var title: String {
        switch self {
        case .stacked:
            return "堆叠（默认）"
        case .horizontal:
            return "横向"
        case .custom:
            return "自定义"
        }
    }

    /// 预设的说明只表达行为，不把它们和字号密度预设混为一谈。
    public var summary: String {
        switch self {
        case .stacked:
            return "Codex 与 Antigravity 各自显示图标和上下堆叠读数"
        case .horizontal:
            return "Codex 与 Antigravity 的项目分别横向排列"
        case .custom:
            return "按实际内容调整两个提供商的项目顺序和堆叠"
        }
    }

    /// 返回预设对应的布局；自定义项不覆盖用户当前编辑结果。
    public var layout: MenuBarLayout? {
        switch self {
        case .stacked:
            return .defaultStacked
        case .horizontal:
            return .horizontal
        case .custom:
            return nil
        }
    }

    /// 根据布局反推当前选择，让用户手动调整后自动切换到“自定义”。
    public static func matching(_ layout: MenuBarLayout) -> Self {
        if layout.isDefaultStacked { return .stacked }
        if layout == .horizontal { return .horizontal }
        return .custom
    }
}

/// 负责保存和读取菜单栏布局；无历史数据时直接返回默认堆叠，不另设模式开关。
public enum MenuBarLayoutStore {
    /// 从共享 UserDefaults 解码布局，损坏或缺失时回到可编辑的默认堆叠。
    public static func load(defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults) -> MenuBarLayout {
        guard let data = defaults.data(forKey: MenuBarPreferenceKeys.layout),
              let layout = try? JSONDecoder().decode(MenuBarLayout.self, from: data)
        else {
            return .defaultStacked
        }
        return layout.normalized.addingDefaultGeminiItems
    }

    /// 把布局写入共享 UserDefaults，并沿用现有菜单栏通知链立即刷新状态栏。
    public static func save(
        _ layout: MenuBarLayout,
        defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults
    ) {
        guard let data = try? JSONEncoder().encode(layout.normalized) else { return }
        defaults.set(data, forKey: MenuBarPreferenceKeys.layout)
        MenuBarDisplaySettings.notifyDidChange(defaults: defaults)
    }
}

public enum AppBehaviorPreferenceKeys {
    public static let opensSettingsAtLaunch = "app.opensSettingsAtLaunch"
    public static let refreshCadence = "usage.refreshCadence"

    public static let allKeys = [
        opensSettingsAtLaunch,
        refreshCadence
    ]
}

public enum AppLanguagePreferenceKeys {
    public static let selectedLanguage = "app.selectedLanguage"
}

/// Google AI Pro 的 Gemini 独立展示偏好；不与 Codex 的登录、额度和刷新配置共享。
public enum GeminiModelsPreferenceKeys {
    public static let isEnabled = "geminiModels.isEnabled"
    public static let model = "geminiModels.model"
    public static let showsInPopover = "geminiModels.showsInPopover"
    public static let showsInMenuBar = "geminiModels.showsInMenuBar"
}

/// 应用语言沿用系统语言代码；空值表示不覆盖 macOS 的语言选择。
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = ""
    case chineseSimplified = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public var locale: Locale {
        rawValue.isEmpty ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    public var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .chineseSimplified:
            return "简体中文"
        case .english:
            return "English"
        }
    }

    /// 写入下一次进程启动使用的语言覆盖；跟随系统时删除旧覆盖。
    public func apply(to defaults: UserDefaults = .standard) {
        if rawValue.isEmpty {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

/// Google AI Pro 可展示的模型配额组；对应 Antigravity 返回的 Gemini 与 Claude/GPT 两类额度池。
public enum GeminiModelOption: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case geminiModels = "gemini-models"
    case claudeAndGPTModels = "claude-gpt-models"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:
            return "全部模型"
        case .geminiModels:
            return "Gemini Models"
        case .claudeAndGPTModels:
            return "Claude and GPT models"
        }
    }

    /// 菜单栏空间有限时使用短标题；完整分组名仍在设置页和下拉面板中展示。
    public var compactTitle: String {
        switch self {
        case .all:
            return "All"
        case .geminiModels:
            return "Antigravity"
        case .claudeAndGPTModels:
            return "Claude/GPT"
        }
    }

    /// 判断配额组是否属于当前选择；组标识优先，标题用于兼容旧版响应。
    public func matches(group: GeminiQuotaGroup) -> Bool {
        let normalizedTitle = group.title.lowercased()
        switch self {
        case .all:
            return true
        case .geminiModels:
            return group.id == "gemini-models" || normalizedTitle.contains("gemini")
        case .claudeAndGPTModels:
            return group.id == "claude-gpt-models"
                || normalizedTitle.contains("claude")
                || normalizedTitle.contains("gpt")
        }
    }
}

/// 保存 Google AI Pro 的 Gemini 展示配置；配额读取由主 app 的 Antigravity 客户端独立完成。
public struct GeminiModelsSettings: Equatable, Sendable {
    public static let defaultIsEnabled = false
    public static let defaultModel = GeminiModelOption.all
    public static let defaultShowsInPopover = true
    public static let defaultShowsInMenuBar = false

    public let isEnabled: Bool
    public let model: GeminiModelOption
    public let showsInPopover: Bool
    public let showsInMenuBar: Bool

    public init(
        isEnabled: Bool = Self.defaultIsEnabled,
        model: GeminiModelOption = Self.defaultModel,
        showsInPopover: Bool = Self.defaultShowsInPopover,
        showsInMenuBar: Bool = Self.defaultShowsInMenuBar
    ) {
        self.isEnabled = isEnabled
        self.model = model
        self.showsInPopover = showsInPopover
        self.showsInMenuBar = showsInMenuBar
    }

    /// 从共享偏好读取并归一化模型组配置；旧版 Pro/Flash 值归入 Gemini Models。
    public init(defaults: UserDefaults) {
        let storedModel = defaults.string(forKey: GeminiModelsPreferenceKeys.model) ?? ""
        let model = GeminiModelOption(rawValue: storedModel)
            ?? (["gemini-pro", "gemini-flash"].contains(storedModel) ? .geminiModels : Self.defaultModel)
        self.init(
            isEnabled: defaults.object(forKey: GeminiModelsPreferenceKeys.isEnabled) as? Bool
                ?? Self.defaultIsEnabled,
            model: model,
            showsInPopover: defaults.object(forKey: GeminiModelsPreferenceKeys.showsInPopover) as? Bool
                ?? Self.defaultShowsInPopover,
            showsInMenuBar: defaults.object(forKey: GeminiModelsPreferenceKeys.showsInMenuBar) as? Bool
                ?? Self.defaultShowsInMenuBar
        )
    }

    /// 通知主 app 立即刷新 Gemini 配额；配置变更仍由菜单栏观察者负责重建界面。
    public static func notifyDidChange(defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults) {
        defaults.synchronize()
        NotificationCenter.default.post(name: .geminiModelsSettingsDidChange, object: defaults)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    }

    public var usesDefaultValues: Bool {
        self == GeminiModelsSettings()
    }
}

/// 为现有硬编码中文提供进程内英文映射；未翻译项安全回退到中文原文。
public enum AppLocalization {
    /// 判断当前偏好是否使用英文，供带数字插值的动态文案选择格式。
    public static func usesEnglish(
        language: AppLanguage? = nil,
        defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults
    ) -> Bool {
        let selected = language ?? AppLanguage(
            rawValue: defaults.string(forKey: AppLanguagePreferenceKeys.selectedLanguage) ?? ""
        ) ?? .system
        return selected == .english
            || selected == .system && Locale.preferredLanguages.first?.hasPrefix("en") == true
    }

    /// 按用户选择或系统首选语言返回文案；显式语言和偏好容器用于测试与预览。
    public static func string(
        _ key: String,
        language: AppLanguage? = nil,
        defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults
    ) -> String {
        usesEnglish(language: language, defaults: defaults) ? english[key] ?? key : key
    }

    private static let english: [String: String] = [
        "通用": "General",
        "Antigravity": "Antigravity",
        "Google AI Pro": "Google AI Pro",
        "Gemini Models": "Gemini Models",
        "启用 Antigravity": "Enable Antigravity",
        "以独立配置显示 Antigravity 模型配额。": "Show Antigravity model quota as an independent configuration.",
        "模型配额组": "Model Quota Group",
        "选择菜单和下拉面板展示的配额模型组。": "Choose the quota model group shown in the menu bar and popover.",
        "显示在下拉面板": "Show in Popover",
        "在下拉面板中展示 Antigravity 配额卡片。": "Show the Antigravity quota card in the popover.",
        "显示在菜单栏": "Show in Menu Bar",
        "在菜单栏中显示当前配额模型组。": "Show the selected quota model group in the menu bar.",
        "全部模型": "All Models",
        "Claude and GPT models": "Claude and GPT models",
        "独立配置": "Independent Configuration",
        "配额优先读取正在运行的 Antigravity，本地服务不可用时尝试已保存的 Google OAuth。": "Quotas are read from the running Antigravity local service first, then saved Google OAuth credentials.",
        "当前模型没有可用配额窗口。": "No quota window is available for the selected model.",
        "等待 Antigravity 配额刷新。": "Waiting for the Antigravity quota refresh.",
        "通知": "Notifications",
        "菜单栏": "Menu Bar",
        "下拉面板": "Popover",
        "小组件": "Widget",
        "关于": "About",
        "CodexMeter 设置": "CodexMeter Settings",
        "版本": "Version",
        "系统": "System",
        "语言": "Language",
        "更改后立即应用；部分系统文案在重新启动后生效。": "Applies immediately; some system text updates after restarting the app.",
        "登录时启动": "Launch at Login",
        "登录 macOS 后自动启动菜单栏用量组件。": "Launch the menu bar usage app automatically after signing in to macOS.",
        "刷新频率": "Refresh Frequency",
        "手动模式只在点击下拉面板里的刷新按钮时请求接口。": "Manual mode only requests usage when you click Refresh in the popover.",
        "界面外观": "Appearance",
        "自动会跟随系统；浅色和深色会强制所有浮层使用对应配色。": "Automatic follows the system; Light and Dark override all surfaces.",
        "外观": "Appearance",
        "状态颜色": "Status Colors",
        "选择三档余量状态的配色方案。": "Choose colors for the three remaining-quota states.",
        "自定义": "Custom",
        "更多选项": "More Options",
        "启动时打开设置": "Open Settings at Launch",
        "应用启动后自动显示设置窗口；关闭后仍可从菜单栏进入。": "Show Settings when the app launches; it remains available from the menu bar.",
        "卡片不透明度": "Card Opacity",
        "统一影响菜单栏下拉面板和小组件的卡片背景。": "Controls card backgrounds in the popover and widget.",
        "充足": "Healthy",
        "偏低": "Low",
        "紧张": "Critical",
        "用量提醒": "Usage Alerts",
        "额度耗尽提醒": "Quota Depleted",
        "Codex 或 Antigravity 的 5 小时或 7 天窗口剩余降至 0% 时发送系统通知。": "Notify when a Codex or Antigravity 5-hour or 7-day window reaches 0% remaining.",
        "低额度提醒": "Low Quota",
        "Codex 或 Antigravity 剩余额度首次降到设定阈值时发送一次系统通知。": "Notify once when Codex or Antigravity remaining quota first crosses the threshold.",
        "提醒阈值": "Alert Threshold",
        "额度恢复到阈值以上后，下一次下降会再次提醒。": "After quota recovers above the threshold, the next drop can alert again.",
        "庆祝": "Celebrations",
        "重置时播放彩带": "Confetti on Reset",
        "额度重置时播放全屏彩带。": "Play full-screen confetti when quota resets.",
        "关闭": "Off",
        "5 小时重置": "5-Hour Resets",
        "7 天重置": "7-Day Resets",
        "两者": "Both",
        "播放彩带": "Play Confetti",
        "临时入口：立即预览一次全屏彩带。": "Temporary: preview full-screen confetti now.",
        "预览": "Preview",
        "系统浅色菜单栏": "System Light Menu Bar",
        "深色或高对比背景": "Dark or High-Contrast Background",
        "桌面壁纸透出的半透明状态": "Translucent Desktop Background",
        "半透明": "Translucent",
        "显示内容": "Content",
        "菜单栏内容": "Menu Bar Content",
        "剩余额度：显示 7d/5h；预期消耗对比：5h 剩余% · 7d 消耗偏差，窗口独立交叉。": "Remaining quota shows 7d/5h; Expected Pace crosses 5h remaining % with 7d usage variance.",
        "工作日刻度线": "Workday Scale",
        "用于每周用量条刻度和节奏计算。": "Used for weekly scale marks and pace calculations.",
        "显示 5 小时窗口": "Show 5-Hour Window",
        "在菜单栏显示短窗口剩余额度；至少会保留一个窗口。": "Show the short-window quota; at least one window remains visible.",
        "显示 7 天窗口": "Show 7-Day Window",
        "在菜单栏显示周窗口剩余额度；至少会保留一个窗口。": "Show the weekly quota; at least one window remains visible.",
        "在菜单栏显示此窗口剩余额度；至少会保留一个窗口。": "Show this quota window; at least one window remains visible.",
        "显示 Codex 图标": "Show Codex Icon",
        "在数字左侧显示 Codex 图标，便于和其他菜单栏项目区分。": "Show the Codex icon before values for easier identification.",
        "显示活动指示": "Show Activity Indicator",
        "Codex 运行、思考、需确认或刚完成时显示状态符号；空闲时自动隐藏。": "Show a status symbol while Codex runs, thinks, waits, or completes; hide it when idle.",
        "活动样式": "Activity Style",
        "自动会按状态切换；固定样式会一直使用选中的系统符号。": "Automatic changes with status; a fixed style always uses the selected symbol.",
        "布局": "Layout",
        "布局模式": "Layout Mode",
        "紧凑和标准会应用稳定预设，自定义保留所有细调能力。": "Compact and Standard apply stable presets; Custom exposes fine tuning.",
        "显示百分号": "Show Percent Sign",
        "关闭后只显示数字，适合菜单栏空间很紧张时使用。": "Show only numbers when menu bar space is limited.",
        "数字字重": "Number Weight",
        "控制菜单栏读数的视觉重量。": "Control the visual weight of menu bar values.",
        "显示密度": "Display Density",
        "项目间距": "Item Spacing",
        "两行行距": "Row Spacing",
        "数字字号": "Number Size",
        "小组件内容": "Widget Content",
        "跟随菜单栏会复用菜单栏的 5 小时 / 7 天窗口选择。": "Follow Menu Bar reuses its 5-hour and 7-day window selection.",
        "显示重置时间": "Show Reset Time",
        "在每行额度旁显示距离窗口重置还有多久。": "Show the time remaining until reset beside each quota.",
        "显示预期消耗速度": "Show Expected Pace",
        "在每个窗口下显示节奏偏差，以及预计耗尽或持续到重置。": "Show pace variance and whether quota will last until reset.",
        "显示最近同步": "Show Last Sync",
        "在底部显示最近一次成功读取的时间。": "Show the latest successful sync time at the bottom.",
        "显示账户摘要": "Show Account Summary",
        "在标题栏右侧显示账户邮箱和可读套餐标签。": "Show the account email and plan label in the header.",
        "用量": "Usage",
        "显示用量速度": "Show Usage Pace",
        "展示当前用量相对预期节奏是偏快还是有余量。": "Show whether usage is ahead of or below the expected pace.",
        "显示额外额度": "Show Additional Limits",
        "显示 Codex Spark 等接口返回的额外 rate limit。": "Show additional rate limits such as Codex Spark.",
        "活动": "Activity",
        "半年活跃": "6-Month Activity",
        "Token 构成": "Token Mix",
        "剩余": "Remaining",
        "显示 Profile 概览": "Show Profile Overview",
        "展示累计 Token、峰值、最长任务和连续天数。": "Show lifetime tokens, peak usage, longest task, and streak.",
        "显示 Token 活动": "Show Token Activity",
        "展示每日、每周和累计 Token 活动柱状图。": "Show daily, weekly, and lifetime token activity charts.",
        "显示额度重置卡": "Show Reset Credits",
        "在额度与用量中显示可用重置卡数量和到期时间。": "Show available reset credits and expiry under quota and usage.",
        "Profiles": "Profiles",
        "本机消耗与成本": "Local Usage & Cost",
        "显示概览": "Show Overview",
        "展示本机 Token、费用构成和项目消耗排行。": "Show local tokens, cost mix, and project usage rankings.",
        "显示趋势": "Show Trends",
        "展示可切换每日、每周和累计口径的热力图。": "Show the heatmap with daily, weekly, and cumulative views.",
        "显示项目": "Show Projects",
        "展示任务分类、进度和最近任务。": "Show task categories, progress, and recent tasks.",
        "查看诊断日志": "View Diagnostic Log",
        "打开应用诊断日志。": "Open the application diagnostic log.",
        "打开日志目录": "Open Log Folder",
        "在 Finder 中打开应用日志目录。": "Open the application log folder in Finder.",
        "日志文件": "Log File",
        "洞察": "Insights",
        "显示活动洞察": "Show Activity Insights",
        "展示快速模式、推理强度、技能和会话统计。": "Show fast mode, reasoning effort, skills, and session statistics.",
        "显示最常用插件": "Show Top Plugins",
        "展示最近统计里最常用的插件或技能。": "Show the most-used plugins or skills from recent statistics.",
        "降智雷达": "Model Radar",
        "开启降智雷达": "Enable Model Radar",
        "读取 codexradar.com/current.json 并展示模型 IQ。": "Read codexradar.com/current.json and show model IQ.",
        "显示分值折线图": "Show Score Chart",
        "只绘制 IQ 90 及以上的历史分值。": "Plot historical scores with IQ 90 or higher.",
        "显示": "Display",
        "显示同步详情": "Show Sync Details",
        "展示限制状态和最近同步时间。": "Show limit status and the latest sync time.",
        "重置时间": "Reset Time",
        "倒计时适合快速扫读，具体时间适合规划任务开始时间。": "Countdowns scan quickly; clock times help plan task starts.",
        "连接": "Connection",
        "打开 Codex 目录": "Open Codex Folder",
        "在 Finder 中打开 Codex 配置目录。": "Open the Codex configuration folder in Finder.",
        "连接详情": "Connection Details",
        "读取方式": "Source",
        "数据来源": "Data Source",
        "接口": "API",
        "登录信息": "Sign-In Information",
        "已找到": "Found",
        "未找到": "Not Found",
        "CODEX_HOME/auth.json 或 ~/.codex/auth.json": "CODEX_HOME/auth.json or ~/.codex/auth.json",
        "诊断与维护": "Diagnostics & Maintenance",
        "打开缓存目录": "Open Cache Folder",
        "在 Finder 中打开快照缓存目录。": "Open the snapshot cache folder in Finder.",
        "打开状态目录": "Open Status Folder",
        "在 Finder 中打开 hook 活动状态目录。": "Open the hook activity status folder in Finder.",
        "状态文件": "Status File",
        "Hook 配置": "Hook Config",
        "Hook 脚本": "Hook Script",
        "清除最近同步缓存": "Clear Recent Sync Cache",
        "删除本地最新快照，下次刷新会重新保存。": "Delete the latest local snapshot; the next refresh saves a new one.",
        "最近同步缓存已清除。": "Recent sync cache cleared.",
        "清除失败：": "Failed to clear:",
        "更新": "Updates",
        "本机缓存": "Local cache",
        "本机读取失败": "Local read failed",
        "部分统计": "Partial data",
        "部分统计仅包含可解析数据": "Some metrics include only parsed data",
        "自动检查更新": "Automatically Check for Updates",
        "链接": "Links",
        "GitHub 项目主页": "GitHub Project",
        "版本发布记录": "Release Notes",
        "反馈问题": "Report an Issue",
        "打开关于": "Open About",
        "让 Codex 剩余额度、重置时间和使用节奏一眼可见。": "Keep Codex quota, reset times, and usage pace visible at a glance.",
        "已连接本机登录信息": "Connected to Local Sign-In",
        "未找到本机登录信息": "Local Sign-In Not Found",
        "重新读取 Codex 配置": "Reload Codex Configuration",
        "发现新版本": "New Version Available",
        "无": "None",
        "用于每周用量条刻度和节奏计算；选择无时不显示预期消耗。": "Used for weekly usage-bar scale and pace calculation; None hides expected usage.",
        "4 天": "4 Days",
        "5 天": "5 Days",
        "7 天": "7 Days",
        "立即检测": "Check Now",
        "跟随系统": "System",
        "简体中文": "Simplified Chinese",
        "预期消耗对比": "Expected Pace",
        "剩余额度": "Remaining Quota",
        "手动": "Manual",
        "30 秒": "30 Seconds",
        "1 分钟": "1 Minute",
        "5 分钟": "5 Minutes",
        "自动": "Automatic",
        "浅色": "Light",
        "深色": "Dark",
        "跟随菜单栏": "Follow Menu Bar",
        "5 小时 + 7 天": "5 Hours + 7 Days",
        "仅 5 小时": "5 Hours Only",
        "仅 7 天": "7 Days Only",
        "倒计时": "Countdown",
        "具体时间": "Clock Time",
        "紧凑": "Compact",
        "正常": "Normal",
        "标准": "Standard",
        "默认": "Default",
        "柔和": "Soft",
        "高对比": "High Contrast",
        "偏细": "Light",
        "适中": "Medium",
        "偏粗": "Bold",
        "竖向省略号": "Vertical Ellipsis",
        "目标指针": "Target Pointer",
        "空气波纹": "Air Ripple",
        "刷新": "Refresh",
        "设置": "Settings",
        "退出": "Quit",
        "安装 CodexMeter 新版本": "Install the New CodexMeter Version",
        "更新 CodexMeter": "Update CodexMeter",
        "额外额度": "Additional Limits",
        "暂无用量数据": "No Usage Data",
        "每日": "Daily",
        "每周": "Weekly",
        "累计": "Cumulative",
        "重置": "Resets",
        "用量进度": "Usage Progress",
        "用量速度": "Usage Pace",
        "绿色线：按当前时间进度推算的理论剩余位置；绿色表示实际用得比理论慢，有余量。": "Green line: expected remaining quota at the current time; usage is slower than expected.",
        "红色线：按当前时间进度推算的理论剩余位置；红色表示实际用得比理论快，可能提前耗尽。": "Red line: expected remaining quota at the current time; usage is faster and may run out early.",
        "额度重置卡": "Reset Credits",
        "暂无到期明细": "No Expiration Details",
        "正在读取重置卡...": "Loading Reset Credits...",
        "暂无重置卡信息": "No Reset Credit Information",
        "刷新额度重置卡": "Refresh Reset Credits",
        "累计 Token": "Lifetime Tokens",
        "峰值 Token": "Peak Tokens",
        "最长任务": "Longest Task",
        "连续天数": "Streak",
        "Token 活动": "Token Activity",
        "最近日": "Latest Day",
        "近 30 天": "Last 30 Days",
        "快速": "Fast",
        "推理": "Reasoning",
        "技能": "Skills",
        "技能次数": "Skill Uses",
        "会话": "Sessions",
        "最常用的插件": "Top Plugins",
        "限制": "Limit",
        "未触发": "Not Triggered",
        "同步": "Synced",
        "常态 90-110": "Normal 90–110",
        "暂无雷达数据": "No Radar Data",
        "打开 Codex Radar": "Open Codex Radar",
        "刷新降智雷达": "Refresh Model Radar",
        "降智雷达 IQ 曲线": "Model Radar IQ Chart",
        "可用": "Available",
        "已使用": "Used",
        "已过期": "Expired",
        "未知": "Unknown",
        "已重置": "Reset",
        "最小": "Minimal",
        "低": "Low",
        "中": "Medium",
        "高": "High",
        "超高": "Extra High",
        "显示 Codex 5 小时与 7 天窗口的最近同步余量。": "Show the latest synced Codex quota for the 5-hour and 7-day windows.",
        "暂无数据": "No Data",
        "打开菜单栏 App 后自动同步": "Open the menu bar app to sync automatically",
        "本机统计": "Local Insights",
        "本机看板": "Local Dashboard",
        "Codex 用量看板": "Codex Usage Dashboard",
        "Codex 概览": "Codex Overview",
        "统一展示额度、Token、费用、项目和任务状态。": "Show quota, tokens, cost, projects, and task status in one dashboard.",
        "额度与用量": "Quota & Usage",
        "额度": "Quota",
        "云端": "Cloud",
        "消耗与成本": "Usage & Cost",
        "成本": "Cost",
        "概览": "Overview",
        "趋势": "Trend",
        "项目": "Projects",
        "Token 趋势": "Token Trend",
        "30 天": "30 Days",
        "本机": "Local",
        "未缓存": "Uncached",
        "缓存率": "Cache Rate",
        "已归档": "Archived",
        "Codex 本机统计": "Codex Local Insights",
        "显示本机 Token、项目排行和今日任务计数。": "Show local tokens, project rankings, and today's task counts.",
        "暂无本机统计": "No Local Insights",
        "今日": "Today",
        "近 7 天": "Last 7 Days",
        "线程": "Threads",
        "项目 Top 5": "Top 5 Projects",
        "项目排行": "Top Projects",
        "近 7 日趋势": "7-Day Trend",
        "本月估算": "Month Estimate",
        "API 等效估算": "API-Rate Estimate",
        "输入": "Input",
        "缓存输入": "Cached",
        "输出": "Output",
        "进行中": "Active",
        "待处理": "Pending",
        "定时": "Scheduled",
        "完成": "Done"
    ]
}

public enum UsageNotificationPreferenceKeys {
    public static let notifiesWhenDepleted = "notifications.quotaDepleted"
    public static let notifiesWhenLow = "notifications.lowRemaining"
    public static let lowRemainingThreshold = "notifications.lowRemainingThreshold"
}

public enum UsageCelebrationPreferenceKeys {
    public static let resetOption = "celebrations.resetOption"
}

public extension Notification.Name {
    static let playUsageResetConfettiPreview = Notification.Name("CodexMeter.playUsageResetConfettiPreview")
}

/// 定义哪些额度窗口重置时播放彩带；默认关闭，避免应用升级后突然出现全屏效果。
public enum UsageResetCelebrationOption: String, CaseIterable, Identifiable, Sendable {
    case off
    case session
    case weekly
    case both

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "关闭"
        case .session: "5 小时重置"
        case .weekly: "7 天重置"
        case .both: "两者"
        }
    }

    public var celebratesSessionReset: Bool {
        self == .session || self == .both
    }

    public var celebratesWeeklyReset: Bool {
        self == .weekly || self == .both
    }
}

/// 保存系统通知偏好；默认关闭，只有用户主动开启后才请求通知权限。
public struct UsageNotificationSettings: Equatable, Sendable {
    public static let defaultNotifiesWhenDepleted = false
    public static let defaultNotifiesWhenLow = false
    public static let defaultLowRemainingThreshold = 10

    public let notifiesWhenDepleted: Bool
    public let notifiesWhenLow: Bool
    public let lowRemainingThreshold: Int

    public init(
        notifiesWhenDepleted: Bool = Self.defaultNotifiesWhenDepleted,
        notifiesWhenLow: Bool = Self.defaultNotifiesWhenLow,
        lowRemainingThreshold: Int = Self.defaultLowRemainingThreshold
    ) {
        self.notifiesWhenDepleted = notifiesWhenDepleted
        self.notifiesWhenLow = notifiesWhenLow
        self.lowRemainingThreshold = max(1, min(50, lowRemainingThreshold))
    }

    public init(defaults: UserDefaults) {
        self.init(
            notifiesWhenDepleted: defaults.object(forKey: UsageNotificationPreferenceKeys.notifiesWhenDepleted)
                as? Bool ?? Self.defaultNotifiesWhenDepleted,
            notifiesWhenLow: defaults.object(forKey: UsageNotificationPreferenceKeys.notifiesWhenLow)
                as? Bool ?? Self.defaultNotifiesWhenLow,
            lowRemainingThreshold: defaults.object(forKey: UsageNotificationPreferenceKeys.lowRemainingThreshold)
                as? Int ?? Self.defaultLowRemainingThreshold
        )
    }
}

public enum SurfaceAppearancePreferenceKeys {
    public static let appearanceMode = "surface.appearanceMode"
    public static let cardOpacity = "surface.cardOpacity"

    public static let allKeys = [
        appearanceMode,
        cardOpacity
    ]
}

public enum WidgetDisplayPreferenceKeys {
    public static let contentMode = "widget.contentMode"
    public static let appearanceMode = "widget.appearanceMode"
    public static let cardOpacity = "widget.cardOpacity"
    public static let showsResetTime = "widget.showsResetTime"
    public static let showsPaceComparison = "widget.showsPaceComparison"
    public static let showsLastSync = "widget.showsLastSync"
    public static let showsPlanLabel = "widget.showsPlanLabel"

    public static let allKeys = [
        contentMode,
        appearanceMode,
        cardOpacity,
        showsResetTime,
        showsPaceComparison,
        showsLastSync,
        showsPlanLabel
    ]
}

public enum PopoverPreferenceKeys {
    public static let showsPaceComparison = "popover.showsPaceComparison"
    public static let showsProfileOverview = "popover.showsProfileOverview"
    public static let showsTokenActivity = "popover.showsTokenActivity"
    public static let showsActivityInsights = "popover.showsActivityInsights"
    public static let showsTopInvocations = "popover.showsTopInvocations"
    public static let showsSyncDetails = "popover.showsSyncDetails"
    public static let showsAdditionalLimits = "popover.showsAdditionalLimits"
    public static let showsResetCredits = "popover.showsResetCredits"
    /// 保留旧总开关键仅用于升级迁移，新版本使用三个栏目开关。
    public static let showsLocalUsage = "popover.showsLocalUsage"
    public static let showsLocalOverview = "popover.showsLocalOverview"
    public static let showsLocalTrend = "popover.showsLocalTrend"
    public static let showsLocalProjects = "popover.showsLocalProjects"
    public static let resetTimeDisplayStyle = "popover.resetTimeDisplayStyle"

    public static let allKeys = [
        showsPaceComparison,
        showsProfileOverview,
        showsTokenActivity,
        showsActivityInsights,
        showsTopInvocations,
        showsSyncDetails,
        showsAdditionalLimits,
        showsResetCredits,
        showsLocalUsage,
        showsLocalOverview,
        showsLocalTrend,
        showsLocalProjects,
        resetTimeDisplayStyle
    ]
}

public enum MenuBarContentMode: String, CaseIterable, Identifiable, Sendable {
    case paceComparison
    case remainingWindows

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .paceComparison:
            return "预期消耗对比"
        case .remainingWindows:
            return "剩余额度"
        }
    }
}

/// 管理后台同步频率；nil 表示只允许用户手动刷新，避免隐式网络请求。
public enum UsageRefreshCadence: String, CaseIterable, Identifiable, Sendable {
    case manual
    case seconds30
    case minute1
    case minutes5

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .manual:
            return "手动"
        case .seconds30:
            return "30 秒"
        case .minute1:
            return "1 分钟"
        case .minutes5:
            return "5 分钟"
        }
    }

    public var intervalSeconds: TimeInterval? {
        switch self {
        case .manual:
            return nil
        case .seconds30:
            return 30
        case .minute1:
            return 60
        case .minutes5:
            return 300
        }
    }

    public var intervalNanoseconds: UInt64? {
        intervalSeconds.map { UInt64($0 * 1_000_000_000) }
    }
}

/// 控制小组件从共享快照中挑选哪些窗口和辅助文字。
public enum WidgetContentMode: String, CaseIterable, Identifiable, Sendable {
    case followsMenuBar
    case bothWindows
    case primaryOnly
    case secondaryOnly

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .followsMenuBar:
            return "跟随菜单栏"
        case .bothWindows:
            return "5 小时 + 7 天"
        case .primaryOnly:
            return "仅 5 小时"
        case .secondaryOnly:
            return "仅 7 天"
        }
    }
}

/// 控制菜单栏、弹窗和桌面小组件使用系统外观、强制浅色或强制深色。
public enum SurfaceAppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case light
    case dark

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .automatic:
            return "自动"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .automatic:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

public typealias WidgetAppearanceMode = SurfaceAppearanceMode

/// 控制弹窗和小组件里的重置时间文案；倒计时适合扫读，具体时间适合规划。
public enum ResetTimeDisplayStyle: String, CaseIterable, Identifiable, Sendable {
    case countdown
    case absolute

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .countdown:
            return "倒计时"
        case .absolute:
            return "具体时间"
        }
    }
}

public enum UsageRemainingTone: Equatable, Sendable {
    case unavailable
    case good
    case warning
    case danger

    public init(remainingPercent: Int?) {
        guard let remainingPercent else {
            self = .unavailable
            return
        }
        if remainingPercent < 40 {
            self = .danger
        } else if remainingPercent < 70 {
            self = .warning
        } else {
            self = .good
        }
    }
}

/// 保存所有可见浮层的外观设置；小组件旧 key 会作为兼容回退，随后由设置页归一化到新 key。
public struct SurfaceAppearanceSettings: Equatable, Sendable {
    public static let defaultAppearanceMode = SurfaceAppearanceMode.automatic
    public static let defaultCardOpacity = 0.78
    public static let cardOpacityRange = 0.2...0.9

    public let appearanceMode: SurfaceAppearanceMode
    public let cardOpacity: Double

    public init(
        appearanceMode: SurfaceAppearanceMode = Self.defaultAppearanceMode,
        cardOpacity: Double = Self.defaultCardOpacity
    ) {
        self.appearanceMode = appearanceMode
        self.cardOpacity = Self.normalizedCardOpacity(cardOpacity)
    }

    public init(defaults: UserDefaults) {
        let rawAppearance = defaults.string(forKey: SurfaceAppearancePreferenceKeys.appearanceMode)
            ?? defaults.string(forKey: WidgetDisplayPreferenceKeys.appearanceMode)
            ?? ""
        let opacity = defaults.object(forKey: SurfaceAppearancePreferenceKeys.cardOpacity) as? Double
            ?? defaults.object(forKey: WidgetDisplayPreferenceKeys.cardOpacity) as? Double
            ?? Self.defaultCardOpacity
        self.init(
            appearanceMode: SurfaceAppearanceMode(rawValue: rawAppearance) ?? Self.defaultAppearanceMode,
            cardOpacity: opacity
        )
    }

    public var usesDefaultValues: Bool {
        self == SurfaceAppearanceSettings()
    }

    /// 将卡片不透明度限制在可读范围内，避免完全透明或完全不透明破坏桌面层次。
    public static func normalizedCardOpacity(_ value: Double) -> Double {
        min(max(value, cardOpacityRange.lowerBound), cardOpacityRange.upperBound)
    }

    /// 通知菜单栏、弹窗和小组件重新读取外观设置。
    public static func notifyDidChange(defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults) {
        defaults.synchronize()
        NotificationCenter.default.post(name: .surfaceAppearanceSettingsDidChange, object: defaults)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    }
}

/// 保存 app 级行为设置，范围限于启动和后台刷新，不影响小组件快照格式。
public struct AppBehaviorSettings: Equatable, Sendable {
    public static let defaultOpensSettingsAtLaunch = false
    public static let defaultRefreshCadence = UsageRefreshCadence.seconds30

    public let opensSettingsAtLaunch: Bool
    public let refreshCadence: UsageRefreshCadence

    public init(
        opensSettingsAtLaunch: Bool = Self.defaultOpensSettingsAtLaunch,
        refreshCadence: UsageRefreshCadence = Self.defaultRefreshCadence
    ) {
        self.opensSettingsAtLaunch = opensSettingsAtLaunch
        self.refreshCadence = refreshCadence
    }

    public init(defaults: UserDefaults) {
        self.init(
            opensSettingsAtLaunch: defaults.object(forKey: AppBehaviorPreferenceKeys.opensSettingsAtLaunch) as? Bool
                ?? Self.defaultOpensSettingsAtLaunch,
            refreshCadence: UsageRefreshCadence(
                rawValue: defaults.string(forKey: AppBehaviorPreferenceKeys.refreshCadence) ?? ""
            ) ?? Self.defaultRefreshCadence
        )
    }

    public var usesDefaultValues: Bool {
        self == AppBehaviorSettings()
    }

    /// 通知主 app 重新套用启动与刷新相关设置，避免设置页和后台任务脱节。
    public static func notifyDidChange(defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults) {
        defaults.synchronize()
        NotificationCenter.default.post(name: .appBehaviorSettingsDidChange, object: defaults)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    }
}

/// 保存桌面小组件的全局显示偏好，供 app 设置页和 WidgetKit 扩展共同读取。
public struct WidgetDisplaySettings: Equatable, Sendable {
    public static let defaultContentMode = WidgetContentMode.followsMenuBar
    public static let defaultAppearanceMode = SurfaceAppearanceSettings.defaultAppearanceMode
    public static let defaultCardOpacity = SurfaceAppearanceSettings.defaultCardOpacity
    public static let cardOpacityRange = SurfaceAppearanceSettings.cardOpacityRange
    public static let defaultShowsResetTime = true
    public static let defaultShowsPaceComparison = true
    public static let defaultShowsLastSync = true
    public static let defaultShowsPlanLabel = true

    public let contentMode: WidgetContentMode
    public let appearanceMode: SurfaceAppearanceMode
    public let cardOpacity: Double
    public let showsResetTime: Bool
    public let showsPaceComparison: Bool
    public let showsLastSync: Bool
    public let showsPlanLabel: Bool

    public init(
        contentMode: WidgetContentMode = Self.defaultContentMode,
        appearanceMode: SurfaceAppearanceMode = Self.defaultAppearanceMode,
        cardOpacity: Double = Self.defaultCardOpacity,
        showsResetTime: Bool = Self.defaultShowsResetTime,
        showsPaceComparison: Bool = Self.defaultShowsPaceComparison,
        showsLastSync: Bool = Self.defaultShowsLastSync,
        showsPlanLabel: Bool = Self.defaultShowsPlanLabel
    ) {
        self.contentMode = contentMode
        self.appearanceMode = appearanceMode
        self.cardOpacity = SurfaceAppearanceSettings.normalizedCardOpacity(cardOpacity)
        self.showsResetTime = showsResetTime
        self.showsPaceComparison = showsPaceComparison
        self.showsLastSync = showsLastSync
        self.showsPlanLabel = showsPlanLabel
    }

    public init(defaults: UserDefaults) {
        self.init(
            contentMode: WidgetContentMode(
                rawValue: defaults.string(forKey: WidgetDisplayPreferenceKeys.contentMode) ?? ""
            ) ?? Self.defaultContentMode,
            appearanceMode: SurfaceAppearanceMode(
                rawValue: defaults.string(forKey: WidgetDisplayPreferenceKeys.appearanceMode) ?? ""
            ) ?? Self.defaultAppearanceMode,
            cardOpacity: defaults.object(forKey: WidgetDisplayPreferenceKeys.cardOpacity) as? Double
                ?? Self.defaultCardOpacity,
            showsResetTime: defaults.object(forKey: WidgetDisplayPreferenceKeys.showsResetTime) as? Bool
                ?? Self.defaultShowsResetTime,
            showsPaceComparison: defaults.object(forKey: WidgetDisplayPreferenceKeys.showsPaceComparison) as? Bool
                ?? Self.defaultShowsPaceComparison,
            showsLastSync: defaults.object(forKey: WidgetDisplayPreferenceKeys.showsLastSync) as? Bool
                ?? Self.defaultShowsLastSync,
            showsPlanLabel: defaults.object(forKey: WidgetDisplayPreferenceKeys.showsPlanLabel) as? Bool
                ?? Self.defaultShowsPlanLabel
        )
    }

    public var usesDefaultValues: Bool {
        self == WidgetDisplaySettings()
    }

    /// 将卡片不透明度限制在可读范围内，避免完全透明或完全不透明破坏桌面小组件层次。
    public static func normalizedCardOpacity(_ value: Double) -> Double {
        SurfaceAppearanceSettings.normalizedCardOpacity(value)
    }

    /// 通知 WidgetKit 相关界面重新读取全局小组件偏好。
    public static func notifyDidChange(defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults) {
        defaults.synchronize()
        NotificationCenter.default.post(name: .widgetDisplaySettingsDidChange, object: defaults)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    }
}

/// 保存菜单栏弹窗模块偏好；默认等价于旧版本弹窗能看到的内容。
public struct PopoverDisplaySettings: Equatable, Sendable {
    public static let defaultShowsPaceComparison = true
    public static let defaultShowsProfileOverview = true
    public static let defaultShowsTokenActivity = true
    public static let defaultShowsActivityInsights = true
    public static let defaultShowsTopInvocations = false
    public static let defaultShowsSyncDetails = false
    public static let defaultShowsAdditionalLimits = false
    public static let defaultShowsResetCredits = true
    public static let defaultShowsLocalOverview = false
    public static let defaultShowsLocalTrend = false
    public static let defaultShowsLocalProjects = false
    public static let defaultResetTimeDisplayStyle = ResetTimeDisplayStyle.countdown

    public let showsPaceComparison: Bool
    public let showsProfileOverview: Bool
    public let showsTokenActivity: Bool
    public let showsActivityInsights: Bool
    public let showsTopInvocations: Bool
    public let showsSyncDetails: Bool
    public let showsAdditionalLimits: Bool
    public let showsResetCredits: Bool
    public let showsLocalOverview: Bool
    public let showsLocalTrend: Bool
    public let showsLocalProjects: Bool
    public let resetTimeDisplayStyle: ResetTimeDisplayStyle

    public init(
        showsPaceComparison: Bool = Self.defaultShowsPaceComparison,
        showsProfileOverview: Bool = Self.defaultShowsProfileOverview,
        showsTokenActivity: Bool = Self.defaultShowsTokenActivity,
        showsActivityInsights: Bool = Self.defaultShowsActivityInsights,
        showsTopInvocations: Bool = Self.defaultShowsTopInvocations,
        showsSyncDetails: Bool = Self.defaultShowsSyncDetails,
        showsAdditionalLimits: Bool = Self.defaultShowsAdditionalLimits,
        showsResetCredits: Bool = Self.defaultShowsResetCredits,
        showsLocalOverview: Bool = Self.defaultShowsLocalOverview,
        showsLocalTrend: Bool = Self.defaultShowsLocalTrend,
        showsLocalProjects: Bool = Self.defaultShowsLocalProjects,
        resetTimeDisplayStyle: ResetTimeDisplayStyle = Self.defaultResetTimeDisplayStyle
    ) {
        self.showsPaceComparison = showsPaceComparison
        self.showsProfileOverview = showsProfileOverview
        self.showsTokenActivity = showsTokenActivity
        self.showsActivityInsights = showsActivityInsights
        self.showsTopInvocations = showsTopInvocations
        self.showsSyncDetails = showsSyncDetails
        self.showsAdditionalLimits = showsAdditionalLimits
        self.showsResetCredits = showsResetCredits
        self.showsLocalOverview = showsLocalOverview
        self.showsLocalTrend = showsLocalTrend
        self.showsLocalProjects = showsLocalProjects
        self.resetTimeDisplayStyle = resetTimeDisplayStyle
    }

    public init(defaults: UserDefaults) {
        let additionalLimits = defaults.object(forKey: PopoverPreferenceKeys.showsAdditionalLimits) as? Bool
            ?? defaults.object(forKey: MenuBarPreferenceKeys.showsAdditionalLimits) as? Bool
            ?? Self.defaultShowsAdditionalLimits
        self.init(
            showsPaceComparison: defaults.object(forKey: PopoverPreferenceKeys.showsPaceComparison) as? Bool
                ?? Self.defaultShowsPaceComparison,
            showsProfileOverview: defaults.object(forKey: PopoverPreferenceKeys.showsProfileOverview) as? Bool
                ?? Self.defaultShowsProfileOverview,
            showsTokenActivity: defaults.object(forKey: PopoverPreferenceKeys.showsTokenActivity) as? Bool
                ?? Self.defaultShowsTokenActivity,
            showsActivityInsights: defaults.object(forKey: PopoverPreferenceKeys.showsActivityInsights) as? Bool
                ?? Self.defaultShowsActivityInsights,
            showsTopInvocations: defaults.object(forKey: PopoverPreferenceKeys.showsTopInvocations) as? Bool
                ?? Self.defaultShowsTopInvocations,
            showsSyncDetails: defaults.object(forKey: PopoverPreferenceKeys.showsSyncDetails) as? Bool
                ?? Self.defaultShowsSyncDetails,
            showsAdditionalLimits: additionalLimits,
            showsResetCredits: defaults.object(forKey: PopoverPreferenceKeys.showsResetCredits) as? Bool
                ?? Self.defaultShowsResetCredits,
            showsLocalOverview: defaults.object(forKey: PopoverPreferenceKeys.showsLocalOverview) as? Bool
                ?? defaults.object(forKey: PopoverPreferenceKeys.showsLocalUsage) as? Bool
                ?? Self.defaultShowsLocalOverview,
            showsLocalTrend: defaults.object(forKey: PopoverPreferenceKeys.showsLocalTrend) as? Bool
                ?? defaults.object(forKey: PopoverPreferenceKeys.showsLocalUsage) as? Bool
                ?? Self.defaultShowsLocalTrend,
            showsLocalProjects: defaults.object(forKey: PopoverPreferenceKeys.showsLocalProjects) as? Bool
                ?? defaults.object(forKey: PopoverPreferenceKeys.showsLocalUsage) as? Bool
                ?? Self.defaultShowsLocalProjects,
            resetTimeDisplayStyle: ResetTimeDisplayStyle(
                rawValue: defaults.string(forKey: PopoverPreferenceKeys.resetTimeDisplayStyle) ?? ""
            ) ?? Self.defaultResetTimeDisplayStyle
        )
    }

    public var usesDefaultValues: Bool {
        self == PopoverDisplaySettings()
    }

    /// 判断本机卡片是否至少有一个栏目可见，全部关闭时不渲染空卡片。
    public var showsAnyLocalSection: Bool {
        showsLocalOverview || showsLocalTrend || showsLocalProjects
    }

    /// 通知菜单栏弹窗重新构建内容；可附带重置卡开关值，避免快速关开时后台只读到最终状态。
    public static func notifyDidChange(
        defaults: UserDefaults = MenuBarDisplaySettings.sharedDefaults,
        showsResetCredits: Bool? = nil
    ) {
        defaults.synchronize()
        let userInfo = showsResetCredits.map { [PopoverPreferenceKeys.showsResetCredits: $0] }
        NotificationCenter.default.post(name: .popoverDisplaySettingsDidChange, object: defaults, userInfo: userInfo)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    }
}

public enum MenuBarNumberFontWeight: String, CaseIterable, Identifiable, Sendable {
    case regular
    case medium
    case semibold

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .regular:
            return "偏细"
        case .medium:
            return "适中"
        case .semibold:
            return "偏粗"
        }
    }

    public var fontWeight: Font.Weight {
        switch self {
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        }
    }
}

/// 控制菜单栏 hook 活动指示的视觉语言；旧 rawValue 保留用于兼容已保存设置，实际显示改为系统 SF Symbol。
public enum HookActivityIndicatorStyle: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case variableDots
    case fanHead
    case signature

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .automatic:
            return "自动"
        case .variableDots:
            return "竖向省略号"
        case .fanHead:
            return "目标指针"
        case .signature:
            return "空气波纹"
        }
    }
}

public enum MenuBarLayoutDensity: String, CaseIterable, Identifiable, Sendable {
    case compact
    case normal

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .compact:
            return "紧凑"
        case .normal:
            return "正常"
        }
    }

    public var statusItemWidth: CGFloat {
        switch self {
        case .compact:
            return 48
        case .normal:
            return 50
        }
    }
}

public struct MenuBarDisplaySettings: Equatable, Sendable {
    public static let currentDisplayDefaultsVersion = 4
    public static let defaultContentMode = MenuBarContentMode.remainingWindows
    public static let defaultLayoutDensity = MenuBarLayoutDensity.compact
    public static let defaultItemSpacing = 2.0
    public static let defaultRowSpacing = -1.0
    public static let defaultNumberFontSize = 10.0
    public static let defaultNumberFontWeight = MenuBarNumberFontWeight.medium
    public static let defaultGoodColorHex = "#1AB85C"
    public static let defaultWarningColorHex = "#F5931A"
    public static let defaultDangerColorHex = "#F23838"
    public static let defaultShowsPrimaryWindow = true
    public static let defaultShowsSecondaryWindow = true
    public static let defaultShowsPercentSymbol = true
    public static let defaultShowsAdditionalLimits = false
    public static let defaultShowsMenuBarIcon = false
    public static let defaultShowsHookActivityLight = true
    public static let defaultHookActivityIndicatorStyle = HookActivityIndicatorStyle.automatic
    public static let defaultWeeklyProgressWorkDays = 5
    public static let menuBarIconWidth: CGFloat = 15
    public static let menuBarIconTextSpacing: CGFloat = 2
    public static var menuBarIconStatusItemWidth: CGFloat {
        menuBarIconWidth + menuBarIconTextSpacing
    }
    public nonisolated(unsafe) static let sharedDefaults: UserDefaults = UserDefaults(
        suiteName: UsageSnapshotStore.defaultAppGroupIdentifier
    ) ?? .standard

    public let contentMode: MenuBarContentMode
    public let layoutDensity: MenuBarLayoutDensity
    public let itemSpacing: Double
    public let rowSpacing: Double
    public let numberFontSize: Double
    public let numberFontWeight: MenuBarNumberFontWeight
    public let goodColorHex: String
    public let warningColorHex: String
    public let dangerColorHex: String
    public let showsPrimaryWindow: Bool
    public let showsSecondaryWindow: Bool
    public let hiddenWindowDurationMins: Set<Int>
    public let showsPercentSymbol: Bool
    public let showsAdditionalLimits: Bool
    public let showsMenuBarIcon: Bool
    public let showsHookActivityLight: Bool
    public let hookActivityIndicatorStyle: HookActivityIndicatorStyle
    public let weeklyProgressWorkDays: Int

    public init(
        contentMode: MenuBarContentMode = Self.defaultContentMode,
        layoutDensity: MenuBarLayoutDensity = Self.defaultLayoutDensity,
        itemSpacing: Double = Self.defaultItemSpacing,
        rowSpacing: Double = Self.defaultRowSpacing,
        numberFontSize: Double = Self.defaultNumberFontSize,
        numberFontWeight: MenuBarNumberFontWeight = Self.defaultNumberFontWeight,
        goodColorHex: String = Self.defaultGoodColorHex,
        warningColorHex: String = Self.defaultWarningColorHex,
        dangerColorHex: String = Self.defaultDangerColorHex,
        showsPrimaryWindow: Bool = Self.defaultShowsPrimaryWindow,
        showsSecondaryWindow: Bool = Self.defaultShowsSecondaryWindow,
        hiddenWindowDurationMins: Set<Int>? = nil,
        showsPercentSymbol: Bool = Self.defaultShowsPercentSymbol,
        showsAdditionalLimits: Bool = Self.defaultShowsAdditionalLimits,
        showsMenuBarIcon: Bool = Self.defaultShowsMenuBarIcon,
        showsHookActivityLight: Bool = Self.defaultShowsHookActivityLight,
        hookActivityIndicatorStyle: HookActivityIndicatorStyle = Self.defaultHookActivityIndicatorStyle,
        weeklyProgressWorkDays: Int = Self.defaultWeeklyProgressWorkDays
    ) {
        self.contentMode = contentMode
        self.layoutDensity = layoutDensity
        self.itemSpacing = Self.clamp(itemSpacing, min: 0, max: 8)
        self.rowSpacing = Self.clamp(rowSpacing, min: -5, max: 6)
        self.numberFontSize = Self.clamp(numberFontSize, min: 7, max: 13)
        self.numberFontWeight = numberFontWeight
        self.goodColorHex = Self.normalizedColorHex(goodColorHex, fallback: Self.defaultGoodColorHex)
        self.warningColorHex = Self.normalizedColorHex(warningColorHex, fallback: Self.defaultWarningColorHex)
        self.dangerColorHex = Self.normalizedColorHex(dangerColorHex, fallback: Self.defaultDangerColorHex)
        self.showsPrimaryWindow = showsPrimaryWindow || !showsSecondaryWindow
        self.showsSecondaryWindow = showsSecondaryWindow || !showsPrimaryWindow
        self.hiddenWindowDurationMins = hiddenWindowDurationMins ?? Self.legacyHiddenWindowDurationMins(
            showsPrimaryWindow: showsPrimaryWindow,
            showsSecondaryWindow: showsSecondaryWindow
        )
        self.showsPercentSymbol = showsPercentSymbol
        self.showsAdditionalLimits = showsAdditionalLimits
        self.showsMenuBarIcon = showsMenuBarIcon
        self.showsHookActivityLight = showsHookActivityLight
        self.hookActivityIndicatorStyle = hookActivityIndicatorStyle
        /// 0 是“无”选项；其余值仍限制在至少 2 个工作日的有效范围内。
        self.weeklyProgressWorkDays = weeklyProgressWorkDays == 0
            ? 0
            : Swift.max(2, Swift.min(7, weeklyProgressWorkDays))
    }

    public init(defaults: UserDefaults) {
        self.init(
            contentMode: MenuBarContentMode(
                rawValue: defaults.string(forKey: MenuBarPreferenceKeys.contentMode) ?? ""
            ) ?? Self.defaultContentMode,
            layoutDensity: MenuBarLayoutDensity(
                rawValue: defaults.string(forKey: MenuBarPreferenceKeys.layoutDensity) ?? ""
            ) ?? Self.defaultLayoutDensity,
            itemSpacing: defaults.object(forKey: MenuBarPreferenceKeys.itemSpacing) as? Double
                ?? Self.defaultItemSpacing,
            rowSpacing: defaults.object(forKey: MenuBarPreferenceKeys.rowSpacing) as? Double
                ?? Self.defaultRowSpacing,
            numberFontSize: defaults.object(forKey: MenuBarPreferenceKeys.numberFontSize) as? Double
                ?? Self.defaultNumberFontSize,
            numberFontWeight: MenuBarNumberFontWeight(
                rawValue: defaults.string(forKey: MenuBarPreferenceKeys.numberFontWeight) ?? ""
            ) ?? Self.defaultNumberFontWeight,
            goodColorHex: defaults.string(forKey: MenuBarPreferenceKeys.goodColorHex)
                ?? Self.defaultGoodColorHex,
            warningColorHex: defaults.string(forKey: MenuBarPreferenceKeys.warningColorHex)
                ?? Self.defaultWarningColorHex,
            dangerColorHex: defaults.string(forKey: MenuBarPreferenceKeys.dangerColorHex)
                ?? Self.defaultDangerColorHex,
            showsPrimaryWindow: defaults.object(forKey: MenuBarPreferenceKeys.showsPrimaryWindow) as? Bool
                ?? Self.defaultShowsPrimaryWindow,
            showsSecondaryWindow: defaults.object(forKey: MenuBarPreferenceKeys.showsSecondaryWindow) as? Bool
                ?? Self.defaultShowsSecondaryWindow,
            hiddenWindowDurationMins: Self.storedHiddenWindowDurationMins(defaults: defaults),
            showsPercentSymbol: defaults.object(forKey: MenuBarPreferenceKeys.showsPercentSymbol) as? Bool
                ?? Self.defaultShowsPercentSymbol,
            showsAdditionalLimits: defaults.object(forKey: MenuBarPreferenceKeys.showsAdditionalLimits) as? Bool
                ?? Self.defaultShowsAdditionalLimits,
            showsMenuBarIcon: defaults.object(forKey: MenuBarPreferenceKeys.showsMenuBarIcon) as? Bool
                ?? Self.defaultShowsMenuBarIcon,
            showsHookActivityLight: defaults.object(forKey: MenuBarPreferenceKeys.showsHookActivityLight) as? Bool
                ?? Self.defaultShowsHookActivityLight,
            hookActivityIndicatorStyle: HookActivityIndicatorStyle(
                rawValue: defaults.string(forKey: MenuBarPreferenceKeys.hookActivityIndicatorStyle) ?? ""
            ) ?? Self.defaultHookActivityIndicatorStyle,
            weeklyProgressWorkDays: defaults.object(forKey: MenuBarPreferenceKeys.weeklyProgressWorkDays) as? Int
                ?? Self.defaultWeeklyProgressWorkDays
        )
    }

    /// 菜单栏占位只按内容真实需要增长；Pace 上下两行后复用剩余额度的紧凑宽度。
    public var statusItemWidth: CGFloat {
        layoutDensity.statusItemWidth + (showsMenuBarIcon ? Self.menuBarIconStatusItemWidth : 0)
    }

    public var statusLabelHeight: CGFloat {
        22
    }

    public var usesDefaultValues: Bool {
        self == MenuBarDisplaySettings()
    }

    public func colorHex(for tone: UsageRemainingTone) -> String {
        switch tone {
        case .unavailable:
            return Self.defaultGoodColorHex
        case .good:
            return goodColorHex
        case .warning:
            return warningColorHex
        case .danger:
            return dangerColorHex
        }
    }

    /// 按窗口实际时长应用 5 小时与 7 天显示开关，兼容只有 primary 周窗口的账号。
    public func showsQuotaWindow(_ window: RateLimitWindow) -> Bool {
        guard let duration = window.windowDurationMins else { return true }
        return !hiddenWindowDurationMins.contains(duration)
    }

    /// 读取动态窗口偏好；新键不存在时把旧 5 小时与 7 天开关迁移为对应时长。
    public static func storedHiddenWindowDurationMins(defaults: UserDefaults) -> Set<Int>? {
        if let values = defaults.array(forKey: MenuBarPreferenceKeys.hiddenWindowDurationMins) {
            return Set(values.compactMap { ($0 as? NSNumber)?.intValue })
        }
        return nil
    }

    /// 应用单个窗口开关，并拒绝隐藏当前检测结果中的最后一个可见窗口。
    public static func updatingHiddenWindowDurationMins(
        _ hidden: Set<Int>,
        duration: Int,
        isVisible: Bool,
        availableDurations: Set<Int>
    ) -> Set<Int> {
        var updated = hidden
        if isVisible {
            updated.remove(duration)
        } else {
            let visibleDurations = availableDurations.subtracting(hidden)
            guard visibleDurations.count > 1 || !visibleDurations.contains(duration) else { return hidden }
            updated.insert(duration)
        }
        return updated
    }

    /// 把旧版固定窗口开关映射为对应标准时长，首次升级时保持既有选择。
    private static func legacyHiddenWindowDurationMins(
        showsPrimaryWindow: Bool,
        showsSecondaryWindow: Bool
    ) -> Set<Int> {
        var hidden: Set<Int> = []
        if !showsPrimaryWindow { hidden.insert(5 * 60) }
        if !showsSecondaryWindow { hidden.insert(7 * 24 * 60) }
        return hidden
    }

    public func color(for tone: UsageRemainingTone) -> Color {
        switch tone {
        case .unavailable:
            return .secondary
        case .good, .warning, .danger:
            return Color(hexRGB: colorHex(for: tone))
        }
    }

    public static func migrateStandardDefaultsToSharedDefaults(
        standardDefaults: UserDefaults = .standard,
        sharedDefaults: UserDefaults = Self.sharedDefaults
    ) {
        for key in MenuBarPreferenceKeys.allKeys where sharedDefaults.object(forKey: key) == nil {
            if let value = standardDefaults.object(forKey: key) {
                sharedDefaults.set(value, forKey: key)
            }
        }
    }

    /// 将已经写入的旧默认值迁移到当前默认值，避免菜单栏和小组件继续读取旧版默认设置。
    public static func migrateLegacyDisplayDefaults(defaults: UserDefaults = Self.sharedDefaults) {
        let storedVersion = defaults.integer(forKey: MenuBarPreferenceKeys.displayDefaultsVersion)
        guard storedVersion < currentDisplayDefaultsVersion else {
            return
        }

        migrateVersion3PresetFontSize(defaults: defaults, storedVersion: storedVersion)

        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.contentMode,
            legacyValue: MenuBarContentMode.paceComparison.rawValue,
            currentValue: defaultContentMode.rawValue
        )
        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.layoutDensity,
            legacyValue: MenuBarLayoutDensity.compact.rawValue,
            currentValue: defaultLayoutDensity.rawValue
        )
        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.itemSpacing,
            legacyValue: 1.0,
            currentValue: defaultItemSpacing
        )
        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.rowSpacing,
            legacyValue: -2.0,
            currentValue: defaultRowSpacing
        )
        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.numberFontSize,
            legacyValue: 9.0,
            currentValue: defaultNumberFontSize
        )
        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.numberFontSize,
            legacyValue: 9.5,
            currentValue: defaultNumberFontSize
        )
        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.numberFontWeight,
            legacyValue: MenuBarNumberFontWeight.medium.rawValue,
            currentValue: defaultNumberFontWeight.rawValue
        )
        replaceStoredValue(
            defaults: defaults,
            key: MenuBarPreferenceKeys.showsMenuBarIcon,
            legacyValue: false,
            currentValue: defaultShowsMenuBarIcon
        )
        if defaults.object(forKey: MenuBarPreferenceKeys.weeklyProgressWorkDays) == nil {
            defaults.set(defaultWeeklyProgressWorkDays, forKey: MenuBarPreferenceKeys.weeklyProgressWorkDays)
        }

        defaults.set(currentDisplayDefaultsVersion, forKey: MenuBarPreferenceKeys.displayDefaultsVersion)
        defaults.synchronize()
    }

    /// 只把 v3 的两档完整预设从 11pt 调整为 10pt，用户手工配置的 11pt 保持不变。
    private static func migrateVersion3PresetFontSize(defaults: UserDefaults, storedVersion: Int) {
        guard storedVersion == 3,
              defaults.string(forKey: MenuBarPreferenceKeys.layoutDensity) == MenuBarLayoutDensity.compact.rawValue,
              defaults.string(forKey: MenuBarPreferenceKeys.numberFontWeight) == MenuBarNumberFontWeight.medium.rawValue,
              (defaults.object(forKey: MenuBarPreferenceKeys.numberFontSize) as? NSNumber)?.doubleValue == 11
        else {
            return
        }
        let itemSpacing = (defaults.object(forKey: MenuBarPreferenceKeys.itemSpacing) as? NSNumber)?.doubleValue
        let rowSpacing = (defaults.object(forKey: MenuBarPreferenceKeys.rowSpacing) as? NSNumber)?.doubleValue
        guard (itemSpacing == 1 && rowSpacing == -2) || (itemSpacing == 2 && rowSpacing == -1) else { return }
        defaults.set(defaultNumberFontSize, forKey: MenuBarPreferenceKeys.numberFontSize)
    }

    public static func notifyDidChange(defaults: UserDefaults = Self.sharedDefaults) {
        defaults.synchronize()
        NotificationCenter.default.post(name: .menuBarDisplaySettingsDidChange, object: defaults)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
    }

    public static func normalizedColorHex(_ value: String, fallback: String) -> String {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let prefixed = candidate.hasPrefix("#") ? candidate : "#\(candidate)"
        let pattern = /^#[0-9A-F]{6}$/
        if prefixed.wholeMatch(of: pattern) != nil {
            return prefixed
        }
        return fallback
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    /// 只替换仍等于旧默认的字符串设置，保留用户主动改过的值。
    private static func replaceStoredValue(
        defaults: UserDefaults,
        key: String,
        legacyValue: String,
        currentValue: String
    ) {
        let storedValue = defaults.string(forKey: key)
        if storedValue == nil || storedValue == legacyValue {
            defaults.set(currentValue, forKey: key)
        }
    }

    /// 只替换仍等于旧默认的数值设置，保留用户主动改过的值。
    private static func replaceStoredValue(
        defaults: UserDefaults,
        key: String,
        legacyValue: Double,
        currentValue: Double
    ) {
        let storedValue = defaults.object(forKey: key) as? Double
        if storedValue == nil || storedValue == legacyValue {
            defaults.set(currentValue, forKey: key)
        }
    }

    /// 只替换仍等于旧默认的布尔设置，保留用户主动改过的值。
    private static func replaceStoredValue(
        defaults: UserDefaults,
        key: String,
        legacyValue: Bool,
        currentValue: Bool
    ) {
        let storedValue = defaults.object(forKey: key) as? Bool
        if storedValue == nil || storedValue == legacyValue {
            defaults.set(currentValue, forKey: key)
        }
    }
}

public extension Notification.Name {
    // 兼容标识：旧版观察者和共享偏好继续使用原通知名，正式改名后不可修改。
    static let menuBarDisplaySettingsDidChange = Notification.Name("CodexUsage.menuBarDisplaySettingsDidChange")
    static let appBehaviorSettingsDidChange = Notification.Name("CodexUsage.appBehaviorSettingsDidChange")
    static let surfaceAppearanceSettingsDidChange = Notification.Name("CodexUsage.surfaceAppearanceSettingsDidChange")
    static let widgetDisplaySettingsDidChange = Notification.Name("CodexUsage.widgetDisplaySettingsDidChange")
    static let popoverDisplaySettingsDidChange = Notification.Name("CodexUsage.popoverDisplaySettingsDidChange")
    static let codexRadarSettingsDidChange = Notification.Name("CodexUsage.codexRadarSettingsDidChange")
    static let geminiModelsSettingsDidChange = Notification.Name("CodexUsage.geminiModelsSettingsDidChange")
    static let usageSnapshotDidChange = Notification.Name("CodexUsage.usageSnapshotDidChange")
}

/// 统一封装预期消耗速度的展示模型，供菜单栏、弹窗和小组件共享同一套 Pace 判断。
public struct UsagePaceDisplay: Equatable, Sendable {
    public let remainingPercent: Int
    public let remainingPercentText: String
    public let deltaPercent: Int
    public let expectedUsedPercent: Int
    public let etaSeconds: TimeInterval?
    public let willLastToReset: Bool

    /// 从完整快照里选择适合菜单栏紧凑展示的百分比窗口和 Pace 窗口。
    public init?(rateLimits: RateLimitSnapshot?, now: Date = Date()) {
        let settings = MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
        self.init(
            percentWindow: rateLimits?.paceComparisonPercentWindow,
            paceWindow: rateLimits?.paceComparisonPaceWindow,
            now: now,
            weeklyProgressWorkDays: settings.weeklyProgressWorkDays
        )
    }

    /// 用指定窗口计算 Pace；窗口进度不足时返回 nil，避免刚重置后的误导性估算。
    public init?(
        percentWindow: RateLimitWindow?,
        paceWindow: RateLimitWindow?,
        now: Date = Date(),
        weeklyProgressWorkDays: Int? = nil
    ) {
        guard let percentWindow,
              let pace = paceWindow?.usagePace(now: now, weeklyProgressWorkDays: weeklyProgressWorkDays),
              pace.isDisplayable()
        else {
            return nil
        }
        self.remainingPercent = percentWindow.remainingPercent
        self.remainingPercentText = percentWindow.remainingPercentText
        self.deltaPercent = pace.roundedDeltaPercent
        self.expectedUsedPercent = pace.roundedExpectedUsedPercent
        self.etaSeconds = pace.etaSeconds
        self.willLastToReset = pace.willLastToReset
    }

    public var valueText: String {
        "\(remainingPercentText) · \(deltaText)"
    }

    public var compactValueText: String {
        "\(remainingPercentText)·\(deltaText)"
    }

    public var detailText: String {
        detailText(language: .chineseSimplified)
    }

    /// 按指定语言生成完整速度判断和预计耗尽文案。
    public func detailText(language: AppLanguage) -> String {
        let english = AppLocalization.usesEnglish(language: language)
        let leftText: String
        if deltaPercent == 0 {
            leftText = english ? "On pace" : "按正常节奏"
        } else if deltaPercent > 0 {
            leftText = english ? "Using \(deltaPercent)% faster" : "用得偏快 \(deltaPercent)%"
        } else {
            leftText = english ? "\(abs(deltaPercent))% headroom" : "有余量 \(abs(deltaPercent))%"
        }

        guard let rightText = rightText(language: language) else {
            return leftText
        }
        return "\(leftText) · \(rightText)"
    }

    public var widgetStatusText: String {
        widgetStatusText(language: .chineseSimplified)
    }

    /// 按指定语言生成小组件的短速度状态。
    public func widgetStatusText(language: AppLanguage) -> String {
        let english = AppLocalization.usesEnglish(language: language)
        if abs(deltaPercent) <= 2 {
            return english ? "On pace" : "节奏正常"
        }
        if deltaPercent > 0 {
            return english ? "\(deltaPercent)% over" : "超额 \(deltaPercent)%"
        }
        return english ? "\(abs(deltaPercent))% headroom" : "有余量 \(abs(deltaPercent))%"
    }

    public var widgetProjectionText: String? {
        widgetProjectionText(language: .chineseSimplified)
    }

    /// 按指定语言生成小组件的重置或耗尽预测。
    public func widgetProjectionText(language: AppLanguage) -> String? {
        let english = AppLocalization.usesEnglish(language: language)
        if willLastToReset {
            return english ? "Lasts until reset" : "持续到重置"
        }
        guard let etaSeconds else {
            return nil
        }
        let duration = Self.durationText(seconds: etaSeconds, language: language)
        if duration == (english ? "Now" : "现在") {
            return english ? "Quota depleted" : "额度已耗尽"
        }
        return english ? "Depletes in \(duration)" : "预计 \(duration)后耗尽"
    }

    /// 生成弹窗速度行右侧的预测文案。
    private func rightText(language: AppLanguage) -> String? {
        let english = AppLocalization.usesEnglish(language: language)
        if willLastToReset {
            return english ? "Lasts until reset" : "可持续到重置"
        }
        guard let etaSeconds else {
            return nil
        }
        let duration = Self.durationText(seconds: etaSeconds, language: language)
        if duration == (english ? "Now" : "现在") {
            return english ? "Quota depleted" : "额度已耗尽"
        }
        return english ? "Runs out in \(duration)" : "预计 \(duration)后用完"
    }

    public var deltaText: String {
        "\(deltaPercent >= 0 ? "+" : "")\(deltaPercent)%"
    }

    public var tone: UsageRemainingTone {
        if deltaPercent <= 2 {
            return .good
        }
        if deltaPercent <= 12 {
            return .warning
        }
        return .danger
    }

    /// 将 ETA 秒数压缩成适合菜单栏和小组件扫读的短文本。
    private static func durationText(seconds: TimeInterval, language: AppLanguage) -> String {
        let english = AppLocalization.usesEnglish(language: language)
        guard seconds > 60 else {
            return english ? "Now" : "现在"
        }

        let totalMinutes = max(1, Int((seconds / 60).rounded()))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0, hours > 0 {
            var parts = ["\(days)d", "\(hours)h"]
            if minutes > 0 {
                parts.append("\(minutes)m")
            }
            return parts.joined(separator: " ")
        }
        if days > 0 {
            return minutes > 0 ? "\(days)d \(minutes)m" : "\(days)d"
        }
        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}

/// 描述单个额度窗口的 Pace 展示，保证弹窗和小组件按同一阈值决定是否展示速度行。
public struct UsageWindowPaceDisplay: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let display: UsagePaceDisplay

    /// 构造单个额度窗口的 Pace 展示；窗口进度不足 3% 时不展示，避免刚重置后的偏差误导用户。
    public init?(
        id: String,
        title: String,
        window: RateLimitWindow?,
        now: Date = Date(),
        weeklyProgressWorkDays: Int? = nil
    ) {
        guard let display = UsagePaceDisplay(
            percentWindow: window,
            paceWindow: window,
            now: now,
            weeklyProgressWorkDays: weeklyProgressWorkDays
        ) else {
            return nil
        }
        self.id = id
        self.title = title
        self.display = display
    }

    /// 收集“用量速度”区域实际返回且达到展示阈值的窗口 Pace。
    public static func displays(
        rateLimits: RateLimitSnapshot,
        now: Date = Date(),
        weeklyProgressWorkDays: Int? = nil
    ) -> [UsageWindowPaceDisplay] {
        [
            UsageWindowPaceDisplay(
                id: "primary",
                title: rateLimits.primary?.durationLabel ?? "用量窗口",
                window: rateLimits.primary,
                now: now,
                weeklyProgressWorkDays: weeklyProgressWorkDays
            ),
            UsageWindowPaceDisplay(
                id: "secondary",
                title: rateLimits.secondary?.durationLabel ?? "用量窗口",
                window: rateLimits.secondary,
                now: now,
                weeklyProgressWorkDays: weeklyProgressWorkDays
            )
        ].compactMap { $0 }
    }
}

/// 生成标准周窗口的工作日分界百分比，供 7 天用量条和设置预览复用。
public func weeklyWorkdayMarkerPercents(workDays: Int?, windowDurationMins: Int?) -> [Double] {
    guard windowDurationMins == 10_080, let workDays, workDays >= 2, workDays <= 7 else {
        return []
    }
    return (1..<workDays).map { Double($0) * 100.0 / Double(workDays) }
}

/// 生成额度进度条的胶囊分界；0 不分段，5 小时按小时分段，周窗口沿用用户选择的工作日数量。
public func usageProgressSegmentPercents(workDays: Int?, windowDurationMins: Int?) -> [Double] {
    if let workDays, workDays == 0 {
        return []
    }
    if windowDurationMins == 300 {
        return [20, 40, 60, 80]
    }
    return weeklyWorkdayMarkerPercents(workDays: workDays, windowDurationMins: windowDurationMins)
}

private extension RateLimitSnapshot {
    var paceComparisonPercentWindow: RateLimitWindow? {
        primary ?? secondary
    }

    var paceComparisonPaceWindow: RateLimitWindow? {
        secondary ?? primary
    }
}

public struct CodexMeterWidgetDisplay: Equatable, Sendable {
    public struct Line: Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let value: String
        public let resetText: String
        public let paceStatusText: String
        public let paceProjectionText: String
        public let paceTone: UsageRemainingTone
        public let progressValue: Double
        public let progressSegmentCount: Int
        public let tone: UsageRemainingTone
    }

    public let lines: [Line]

    public init(
        snapshot: UsageSnapshot,
        settings: MenuBarDisplaySettings,
        widgetSettings: WidgetDisplaySettings = WidgetDisplaySettings(),
        formatter: UsageFormatter = UsageFormatter(),
        language: AppLanguage = .chineseSimplified,
        now: Date = Date()
    ) {
        var lines: [Line] = []
        if let primary = snapshot.rateLimits.primary,
           Self.showsWindow(primary, menuBarSettings: settings, widgetSettings: widgetSettings)
        {
            lines.append(Self.line(
                id: "primary",
                title: primary.localizedDurationLabel(language: language),
                window: primary,
                resetText: widgetSettings.showsResetTime
                    ? formatter.resetRemainingText(window: primary, now: now)
                    : "",
                paceDisplay: widgetSettings.showsPaceComparison
                    ? UsageWindowPaceDisplay(
                        id: "primary",
                        title: primary.localizedDurationLabel(language: language),
                        window: primary,
                        now: now,
                        weeklyProgressWorkDays: settings.weeklyProgressWorkDays
                    )?.display
                    : nil,
                settings: settings,
                language: language
            ))
        }
        if let secondary = snapshot.rateLimits.secondary,
           Self.showsWindow(secondary, menuBarSettings: settings, widgetSettings: widgetSettings)
        {
            lines.append(Self.line(
                id: "secondary",
                title: secondary.localizedDurationLabel(language: language),
                window: secondary,
                resetText: widgetSettings.showsResetTime
                    ? formatter.resetRemainingText(window: secondary, now: now)
                    : "",
                paceDisplay: widgetSettings.showsPaceComparison
                    ? UsageWindowPaceDisplay(
                        id: "secondary",
                        title: secondary.localizedDurationLabel(language: language),
                        window: secondary,
                        now: now,
                        weeklyProgressWorkDays: settings.weeklyProgressWorkDays
                    )?.display
                    : nil,
                settings: settings,
                language: language
            ))
        }
        self.lines = lines
    }

    /// 根据实际窗口时长和小组件模式判断是否显示，避免把 primary 固定解释为 5 小时。
    private static func showsWindow(
        _ window: RateLimitWindow,
        menuBarSettings: MenuBarDisplaySettings,
        widgetSettings: WidgetDisplaySettings
    ) -> Bool {
        switch widgetSettings.contentMode {
        case .followsMenuBar:
            return menuBarSettings.showsQuotaWindow(window)
        case .bothWindows:
            return true
        case .primaryOnly:
            return !window.isWeeklyQuotaWindow
        case .secondaryOnly:
            return window.isWeeklyQuotaWindow
        }
    }

    private static func line(
        id: String,
        title: String,
        window: RateLimitWindow?,
        resetText: String,
        paceDisplay: UsagePaceDisplay?,
        settings: MenuBarDisplaySettings,
        language: AppLanguage
    ) -> Line {
        let remainingPercent = window?.remainingPercent
        return Line(
            id: id,
            title: title,
            value: Self.value(for: window, settings: settings),
            resetText: resetText,
            paceStatusText: paceDisplay?.widgetStatusText(language: language) ?? "",
            paceProjectionText: paceDisplay?.widgetProjectionText(language: language) ?? "",
            paceTone: paceDisplay?.tone ?? .unavailable,
            progressValue: Double(remainingPercent ?? 0),
            progressSegmentCount: usageProgressSegmentPercents(
                workDays: settings.weeklyProgressWorkDays,
                windowDurationMins: window?.windowDurationMins
            ).count + 1,
            tone: UsageRemainingTone(remainingPercent: remainingPercent)
        )
    }

    private static func value(for window: RateLimitWindow?, settings: MenuBarDisplaySettings) -> String {
        guard let window else {
            return "--"
        }
        return settings.showsPercentSymbol
            ? window.remainingPercentText
            : String(window.remainingPercentText.dropLast())
    }
}

/// 定义下拉框和小组件共用的图表主题；连续数据以暖橙为主，分类数据使用高对比辅助色。
public enum CodexMeterChartPalette {
    public static let primary = Color(hexRGB: "#F59E0B")
    public static let primaryStrong = Color(hexRGB: "#D97706")
    public static let secondary = Color(hexRGB: "#F28C28")
    public static let tertiary = Color(hexRGB: "#EAB308")
    public static let tokenInput = primary
    public static let tokenCachedInput = Color(hexRGB: "#14B8A6")
    public static let tokenOutput = Color(hexRGB: "#A855F7")

    /// 根据用量强度生成单一主题色的热力图层级，避免连续数据混用色相造成视觉割裂。
    public static func heatmapColor(value: Int64, maximum: Int64) -> Color {
        guard value > 0 else { return Color.primary.opacity(0.07) }
        switch Double(value) / Double(max(1, maximum)) {
        case ..<0.2: return primary.opacity(0.28)
        case ..<0.45: return primary.opacity(0.5)
        case ..<0.75: return primary.opacity(0.7)
        default: return primary.opacity(0.92)
        }
    }

    /// 为雷达多序列折线提供深色背景下易区分的多色调色板，按索引循环复用。
    public static func seriesColor(index: Int) -> Color {
        let seriesHexColors = [
            "#3B82F6", "#F59E0B", "#14B8A6", "#F43F5E", "#8B5CF6",
            "#84CC16", "#06B6D4", "#F97316", "#D946EF", "#10B981",
            "#6366F1", "#EAB308", "#0EA5E9", "#EF4444", "#A855F7",
            "#22C55E", "#EC4899", "#38BDF8", "#FB923C", "#2DD4BF"
        ]
        return Color(hexRGB: seriesHexColors[index % seriesHexColors.count])
    }
}

public extension Color {
    init(hexRGB: String) {
        let normalized = MenuBarDisplaySettings.normalizedColorHex(
            hexRGB,
            fallback: MenuBarDisplaySettings.defaultGoodColorHex
        )
        let value = String(normalized.dropFirst())
        let scanner = Scanner(string: value)
        var hexNumber: UInt64 = 0
        scanner.scanHexInt64(&hexNumber)
        self.init(
            red: Double((hexNumber & 0xFF0000) >> 16) / 255,
            green: Double((hexNumber & 0x00FF00) >> 8) / 255,
            blue: Double(hexNumber & 0x0000FF) / 255
        )
    }
}

public extension UsageRemainingTone {
    func statusBarColor(settings: MenuBarDisplaySettings) -> Color {
        settings.color(for: self)
    }
}
