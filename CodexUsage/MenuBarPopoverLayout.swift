import AppKit

/// 下拉弹窗的布局约束集合；只存放跨 AppKit 宿主和 SwiftUI 内容共享的尺寸规则。
enum MenuBarPopoverLayout {
    static let width: CGFloat = 380
    static let horizontalPadding: CGFloat = 12
    static let topPadding: CGFloat = 4
    static let bottomPadding: CGFloat = 8
    static let minimumHeight: CGFloat = 220
    static let maximumHeight: CGFloat = 820
    static let maximumScrollableContentHeight: CGFloat = 720
    static let paceMarkerTooltipTopOffset: CGFloat = 112
    static let scrollOverflowHysteresis: CGFloat = 28
    static let initialSize = NSSize(width: width, height: 680)
    /// 错误文案归入滚动主体，避免长错误把底部固定操作栏挤出弹窗可见区域。
    static let errorMessageRegion = MenuBarPopoverContentRegion.scrollContent

    /// 计算内部内容宽度，保证测量副本和真实内容使用同一水平约束。
    static var contentWidth: CGFloat {
        width - horizontalPadding * 2
    }
}

/// 标记弹窗内容属于滚动主体还是固定底部区，避免错误态把底部操作按钮挤出窗口。
enum MenuBarPopoverContentRegion: Equatable {
    case scrollContent
    case footer
}

/// 降智雷达分数卡布局规则；按项目数量计算最多两行所需的等宽列数。
enum CodexRadarScoreGridLayout {
    /// 返回容纳全部项目且不超过两行的列数；空列表返回一列以安全构造网格。
    static func columnCount(for itemCount: Int) -> Int {
        max(1, (itemCount + 1) / 2)
    }
}

/// 降智雷达折线图布局规则；集中决定需要强调的数据点。
enum CodexRadarLineChartLayout {
    /// 单条曲线的绘制计划；区分是否连线以及需要强调的数据点。
    struct DrawingPlan: Equatable {
        let drawsLine: Bool
        let markerIndexes: [Int]
    }

    /// 返回曲线绘制计划；单点只画圆点，多点画线并强调首尾。
    static func drawingPlan(for pointCount: Int) -> DrawingPlan {
        guard pointCount > 0 else {
            return DrawingPlan(drawsLine: false, markerIndexes: [])
        }
        guard pointCount > 1 else {
            return DrawingPlan(drawsLine: false, markerIndexes: [0])
        }
        return DrawingPlan(drawsLine: true, markerIndexes: [0, pointCount - 1])
    }

    /// 返回图例列数；最多三列，六项时自然形成两行。
    static func legendColumnCount(for itemCount: Int) -> Int {
        min(max(itemCount, 1), 3)
    }
}

/// 降智雷达卡片与图例文案规则；统一紧凑标签和悬停全称的模型格式。
enum CodexRadarScoreCardText {
    /// 生成 `5.6-Sol-u` 格式的紧凑标签；推理档位只保留首字母。
    static func shortLabel(model: String?, effort: String?) -> String {
        let base = normalizedModel(model, includesGPTPrefix: false)
        guard let suffix = effort?.lowercased().first else {
            return base
        }
        return "\(base)-\(suffix)"
    }

    /// 生成 `GPT-5.6-Sol ultra` 格式的完整名称，供悬停详情使用。
    static func fullLabel(model: String?, effort: String?) -> String {
        let base = normalizedModel(model, includesGPTPrefix: true)
        guard let effort, !effort.isEmpty else {
            return base
        }
        return "\(base) \(effort.lowercased())"
    }

    /// 规范远端模型名的大小写和 GPT 前缀，未知格式保留可读兜底。
    private static func normalizedModel(_ model: String?, includesGPTPrefix: Bool) -> String {
        let raw = model ?? "GPT"
        let withoutPrefix = raw.replacingOccurrences(of: "gpt-", with: "", options: .caseInsensitive)
        let components = withoutPrefix.split(separator: "-").map(String.init)
        let normalized: String
        if components.count >= 2, let family = components.last {
            normalized = components.dropLast().joined(separator: "-") + "-" + family.capitalized
        } else {
            normalized = withoutPrefix
        }
        return includesGPTPrefix ? "GPT-\(normalized)" : normalized
    }
}
