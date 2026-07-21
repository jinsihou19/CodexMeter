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

/// 降智雷达折线图布局规则；集中决定需要强调的数据点。
enum CodexRadarLineChartLayout {
    /// 单条曲线的绘制计划；区分是否连线以及需要强调的数据点。
    struct DrawingPlan: Equatable {
        let drawsLine: Bool
        let markerIndexes: [Int]
    }

    /// 返回曲线绘制计划；所有时间点都画圆点，便于精确悬停查看。
    static func drawingPlan(for pointCount: Int) -> DrawingPlan {
        guard pointCount > 0 else {
            return DrawingPlan(drawsLine: false, markerIndexes: [])
        }
        guard pointCount > 1 else {
            return DrawingPlan(drawsLine: false, markerIndexes: [0])
        }
        return DrawingPlan(drawsLine: true, markerIndexes: Array(0..<pointCount))
    }
}

/// 降智雷达纵轴规则；按实际分数范围生成整十刻度，最高分不超过 150。
enum CodexRadarScoreAxis {
    private static let standardLowerBound = 90.0
    private static let maximumUpperBound = 150.0
    private static let minimumLowerBound = 0.0
    private static let maximumSpan = 60.0
    private static let step = 10.0

    /// 返回覆盖分数的整十纵轴范围；跨度超过 60 时优先保留最高分向下的 60 分。
    static func bounds(for scores: [Double]) -> ClosedRange<Double> {
        guard let lowest = scores.min(), let highest = scores.max() else {
            return standardLowerBound...maximumUpperBound
        }
        let lowerBound = max((lowest / step).rounded(.down) * step, minimumLowerBound)
        let upperBound = upperBound(for: [highest])
        if upperBound - lowerBound > maximumSpan {
            return (upperBound - maximumSpan)...upperBound
        }
        if lowerBound < upperBound {
            return lowerBound...upperBound
        }
        if upperBound < maximumUpperBound {
            return lowerBound...(upperBound + step)
        }
        return max(lowerBound - step, minimumLowerBound)...upperBound
    }

    /// 返回覆盖最高分的整十纵轴上限，最大不超过 150。
    static func upperBound(for scores: [Double]) -> Double {
        let highest = scores.max() ?? standardLowerBound
        let rounded = (highest / step).rounded(.up) * step
        return min(max(rounded, standardLowerBound), maximumUpperBound)
    }

    /// 生成当前纵轴范围内的全部整十刻度。
    static func gridScores(in bounds: ClosedRange<Double>) -> [Double] {
        stride(from: bounds.lowerBound, through: bounds.upperBound, by: step).map { $0 }
    }
}

/// 降智雷达模型矩阵文案规则；统一卡片标签和悬停全称的模型格式。
enum CodexRadarScoreCardText {
    /// 提取模型家族名，供矩阵每行只展示一次。
    static func familyLabel(model: String?) -> String {
        normalizedModel(model, includesGPTPrefix: false)
            .split(separator: "-")
            .last
            .map(String.init) ?? "GPT"
    }

    /// 返回矩阵单元格的完整档位名；ultra 和 max 是独立档位。
    static func effortLabel(_ effort: String?) -> String {
        guard let effort, !effort.isEmpty else {
            return "--"
        }
        return fullEffort(effort)
    }

    /// 生成 `Sol max` 格式的矩阵标签，去掉重复的 GPT 和版本前缀。
    static func shortLabel(model: String?, effort: String?) -> String {
        let base = familyLabel(model: model)
        guard let effort, !effort.isEmpty else {
            return base
        }
        return "\(base) \(compactEffort(effort))"
    }

    /// 生成 `GPT-5.6-Sol ultra` 格式的完整名称，供悬停详情使用。
    static func fullLabel(model: String?, effort: String?) -> String {
        let base = normalizedModel(model, includesGPTPrefix: true)
        guard let effort, !effort.isEmpty else {
            return base
        }
        return "\(base) \(fullEffort(effort))"
    }

    /// 生成矩阵中的紧凑档位，medium 缩写为 med。
    private static func compactEffort(_ effort: String) -> String {
        switch effort.lowercased() {
        case "medium": return "med"
        default: return effort.lowercased()
        }
    }

    /// 悬停详情保留远端提供的完整推理档位名。
    private static func fullEffort(_ effort: String) -> String {
        effort.lowercased()
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
