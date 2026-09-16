import AppKit
import CodexMeterShared

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

/// 雷达模型筛选规则；负责 GPT 家族版本去重和其他模型的默认选择。
enum CodexRadarModelSelection {
    /// 每个 GPT 家族只保留版本号最高的模型，同时保留该版本的全部推理档位。
    static func latestGPTSeriesByFamily(from series: [CodexRadarModelSeries]) -> [CodexRadarModelSeries] {
        var latestModels: [String: (model: String, version: [Int])] = [:]
        for item in series {
            guard let model = item.model else { continue }
            let family = CodexRadarScoreCardText.familyLabel(model: model)
            let version = gptVersionComponents(model)
            if let current = latestModels[family],
               compare(version, to: current.version) != .orderedDescending {
                continue
            }
            latestModels[family] = (model, version)
        }
        return series.filter { item in
            guard let model = item.model else { return false }
            let family = CodexRadarScoreCardText.familyLabel(model: model)
            return latestModels[family]?.model == model
        }
    }

    /// 返回分值最高的若干模型 ID；同分时按 ID 排序，保证结果稳定。
    static func topModelIDs(from series: [CodexRadarModelSeries], limit: Int = 2) -> Set<String> {
        var highestScores: [String: Double] = [:]
        for item in series {
            guard let model = item.model, let score = item.latest?.score else { continue }
            highestScores[model] = max(highestScores[model] ?? -.infinity, score)
        }
        return Set(highestScores
            .sorted { left, right in
                left.value == right.value ? left.key < right.key : left.value > right.value
            }
            .prefix(max(limit, 0))
            .map(\.key))
    }

    /// 从 `gpt-5.6-sol` 形式中提取 `[5, 6]`，未知片段按零处理。
    private static func gptVersionComponents(_ model: String) -> [Int] {
        let components = model.lowercased().split(separator: "-")
        guard components.count >= 3, components.first == "gpt" else { return [] }
        return components[1].split(separator: ".").map { Int($0) ?? 0 }
    }

    /// 比较长度不一的版本号，缺失的小版本按零补齐。
    private static func compare(_ left: [Int], to right: [Int]) -> ComparisonResult {
        for index in 0..<max(left.count, right.count) {
            let leftPart = index < left.count ? left[index] : 0
            let rightPart = index < right.count ? right[index] : 0
            if leftPart != rightPart {
                return leftPart > rightPart ? .orderedDescending : .orderedAscending
            }
        }
        return .orderedSame
    }
}

/// 降智雷达模型矩阵文案规则；统一卡片标签和悬停全称的模型格式。
enum CodexRadarScoreCardText {
    /// 提取模型家族名，供矩阵每行只展示一次。
    static func familyLabel(model: String?) -> String {
        let raw = model ?? "gpt"
        let components = raw.split(separator: "-").map(String.init)
        if raw.lowercased().hasPrefix("gpt-") {
            return normalizedModel(model, includesGPTPrefix: false)
                .split(separator: "-")
                .last
                .map(String.init) ?? "GPT"
        }
        let familyIndex = components.first?.lowercased() == "dsh" ? 1 : 0
        guard components.indices.contains(familyIndex) else {
            return raw
        }
        return components[familyIndex].capitalized
    }

    /// 将非 GPT 的远端模型标识转为适合下拉框和卡片展示的可读名称。
    static func modelLabel(model: String?) -> String {
        let components = (model ?? "Model")
            .split(separator: "-")
            .map(String.init)
        let isDSH = components.first?.lowercased() == "dsh"
        let visibleComponents = isDSH
            ? components.dropFirst()
            : components[...]
        let name = visibleComponents.map { component in
            switch component.lowercased() {
            case "deepseek": return "DeepSeek"
            case "glm", "hy4", "k3", "v4": return component.uppercased()
            default: return component.prefix(1).uppercased() + component.dropFirst()
            }
        }.joined(separator: " ")
        return isDSH ? "\(name) · DSH" : name
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
