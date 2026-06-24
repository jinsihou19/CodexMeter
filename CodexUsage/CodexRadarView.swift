import CodexUsageShared
import SwiftUI

// 本文件负责下拉面板中的降智雷达可视化，包括分数卡、IQ 折线和同步状态。

/// 下拉面板里的降智雷达区块；展示最新 IQ 分数、历史折线和拉取状态。
struct CodexRadarSection: View {
    @ObservedObject var store: CodexRadarStore
    let settings: CodexRadarSettings

    var body: some View {
        if settings.isEnabled {
            VStack(alignment: .leading, spacing: 4) {
                header

                if let snapshot = store.snapshot, let modelIQ = snapshot.modelIQ {
                    CodexRadarScoreGrid(runs: Array(modelIQ.latestRuns.prefix(4)))
                    CodexRadarLineChart(series: modelIQ.allSeries)
                    footer(snapshot: snapshot)
                } else if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    ContentUnavailableView("暂无雷达数据", systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity, minHeight: 92)
                }

                if let errorMessage = store.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.46))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("降智雷达", systemImage: "brain.head.profile")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .imageScale(.small)
            .disabled(store.isRefreshing)
            .help("刷新降智雷达")
        }
    }

    /// 生成底部同步文案；模型 IQ 更新时间优先，缺失时回退到本地抓取时间。
    private func footer(snapshot: CodexRadarSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("常态 90-110")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(syncText(snapshot: snapshot))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .font(.caption2)
    }

    /// 格式化同步时间，避免把 ISO 字符串原样塞进紧凑弹窗。
    private func syncText(snapshot: CodexRadarSnapshot) -> String {
        if let updatedAt = snapshot.modelIQ?.quotaRadarUpdatedAt.flatMap(CodexRadarDateFormatter.shortDateTime) {
            return "模型IQ更新 \(updatedAt)"
        }
        return "抓取 \(CodexRadarDateFormatter.shortTime(snapshot.fetchedAt))"
    }
}

/// 最新模型分数条，用一行紧凑 chip 展示模型、分数和通过数，避免雷达头部过于醒目。
private struct CodexRadarScoreGrid: View {
    let runs: [CodexRadarIQRun]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(runs) { run in
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(shortLabel(for: run))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                    Text(CodexRadarNumberFormatter.compactScore(run.score))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(color(for: run))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    if let passed = run.passed, let tasks = run.tasks {
                        Text("\(passed)/\(tasks)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                    }
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .center)
                .background(color(for: run).opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(color(for: run).opacity(0.28), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    /// 生成适合单行 chip 的短标签，压缩 GPT 前缀和推理强度但保留区分度。
    private func shortLabel(for run: CodexRadarIQRun) -> String {
        let model = (run.model ?? "GPT")
            .replacingOccurrences(of: "gpt-", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "GPT-", with: "")
        guard let effort = run.reasoningEffort, !effort.isEmpty else {
            return model
        }
        return "\(model)\(shortEffort(effort))"
    }

    /// 把推理强度缩成 chip 能承载的后缀。
    private func shortEffort(_ value: String) -> String {
        switch value.lowercased() {
        case "xhigh":
            return "xh"
        case "high":
            return "h"
        case "medium":
            return "m"
        default:
            return value
        }
    }

    /// 根据雷达状态映射颜色，缺失状态时用分数兜底。
    private func color(for run: CodexRadarIQRun) -> Color {
        CodexRadarPalette.color(status: run.status, score: run.score)
    }
}

/// IQ 折线图；使用 Canvas 自绘以避免引入 Charts 依赖和额外系统版本约束。
private struct CodexRadarLineChart: View {
    let series: [CodexRadarModelSeries]
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Canvas { context, size in
                drawChart(context: &context, size: size)
            }
            .frame(height: 86)
            .accessibilityLabel("降智雷达 IQ 曲线")

            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 9) {
            ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(CodexRadarPalette.seriesColor(index: index))
                        .frame(width: 14, height: 3)
                    Text(shortLabel(item.label))
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 画坐标、常态区间和每条模型曲线。
    private func drawChart(context: inout GraphicsContext, size: CGSize) {
        let plotRect = CGRect(x: 28, y: 4, width: max(size.width - 34, 1), height: max(size.height - 20, 1))
        drawNormalBand(context: &context, rect: plotRect)
        drawGrid(context: &context, rect: plotRect)
        drawXAxisLabels(context: &context, rect: plotRect)

        for (index, item) in series.enumerated() {
            drawSeries(item, index: index, context: &context, rect: plotRect)
        }
    }

    /// 绘制 90-110 常态区间背景。
    private func drawNormalBand(context: inout GraphicsContext, rect: CGRect) {
        let yTop = yPosition(score: 110, rect: rect)
        let yBottom = yPosition(score: 90, rect: rect)
        let band = CGRect(x: rect.minX, y: yTop, width: rect.width, height: yBottom - yTop)
        context.fill(Path(roundedRect: band, cornerRadius: 6), with: .color(.primary.opacity(0.045)))
    }

    /// 绘制轻量网格和关键刻度，保持菜单弹窗可扫读。
    private func drawGrid(context: inout GraphicsContext, rect: CGRect) {
        for score in [60.0, 80.0, 100.0, 120.0] {
            let y = pixelAligned(yPosition(score: score, rect: rect))
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(path, with: .color(.primary.opacity(score == 100 ? 0.22 : 0.11)), lineWidth: 1)
            let label = Text("\(Int(score))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            context.draw(label, at: CGPoint(x: 12, y: y), anchor: .leading)
        }
    }

    /// 绘制单条模型曲线和端点圆点。
    private func drawSeries(
        _ item: CodexRadarModelSeries,
        index: Int,
        context: inout GraphicsContext,
        rect: CGRect
    ) {
        let points = points(for: item, rect: rect)
        guard points.count >= 2 else {
            return
        }
        var path = Path()
        path = smoothedPath(points: points)
        let color = CodexRadarPalette.seriesColor(index: index)
        context.stroke(path, with: .color(color.opacity(index == 0 ? 0.95 : 0.72)), lineWidth: index == 0 ? 3 : 2)

        if let lastPoint = points.last {
            context.fill(Path(ellipseIn: CGRect(x: lastPoint.x - 3, y: lastPoint.y - 3, width: 6, height: 6)), with: .color(color))
        }
    }

    /// 在横轴底部标出首、中、末日期，弥补迷你曲线缺少时间参照的问题。
    private func drawXAxisLabels(context: inout GraphicsContext, rect: CGRect) {
        guard let runs = series.first?.recentDays, !runs.isEmpty else {
            return
        }
        let indexes = Array(Set([0, runs.count / 2, runs.count - 1])).sorted()
        let denominator = max(runs.count - 1, 1)
        for index in indexes {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(denominator)
            let label = Text(CodexRadarDateFormatter.axisLabel(runs[index].date))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            context.draw(label, at: CGPoint(x: x, y: rect.maxY + 11), anchor: .center)
        }
    }

    /// 用 Catmull-Rom 转贝塞尔曲线，让折线保留数据点走势但视觉更圆润。
    private func smoothedPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let firstPoint = points.first else {
            return path
        }
        path.move(to: firstPoint)
        guard points.count > 2 else {
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            return path
        }

        for index in 0..<(points.count - 1) {
            let previous = points[max(index - 1, 0)]
            let current = points[index]
            let next = points[index + 1]
            let afterNext = points[min(index + 2, points.count - 1)]
            let control1 = CGPoint(
                x: current.x + (next.x - previous.x) / 6,
                y: current.y + (next.y - previous.y) / 6
            )
            let control2 = CGPoint(
                x: next.x - (afterNext.x - current.x) / 6,
                y: next.y - (afterNext.y - current.y) / 6
            )
            path.addCurve(to: next, control1: control1, control2: control2)
        }
        return path
    }

    /// 把远端日期序列等距映射到图表区域。
    private func points(for item: CodexRadarModelSeries, rect: CGRect) -> [CGPoint] {
        let runs = item.recentDays
        guard !runs.isEmpty else {
            return []
        }
        let denominator = max(runs.count - 1, 1)
        return runs.enumerated().map { offset, run in
            CGPoint(
                x: rect.minX + rect.width * CGFloat(offset) / CGFloat(denominator),
                y: yPosition(score: run.score, rect: rect)
            )
        }
    }

    /// 将 IQ 分数夹到 45-130 的可视范围，避免异常值把图挤扁。
    private func yPosition(score: Double, rect: CGRect) -> CGFloat {
        let clamped = min(max(score, 45), 130)
        let ratio = (clamped - 45) / 85
        return rect.maxY - rect.height * CGFloat(ratio)
    }

    /// 像素对齐水平线，减少低分辨率显示器上的模糊。
    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        return (value * scale).rounded() / scale
    }

    /// 图例用更紧凑的模型名，适合 380pt 弹窗宽度。
    private func shortLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "GPT-", with: "")
            .replacingOccurrences(of: "xhigh", with: "xh")
            .replacingOccurrences(of: "medium", with: "m")
            .replacingOccurrences(of: " ", with: "-")
    }
}

/// 雷达颜色表；集中管理状态色和曲线色，避免卡片和图例各自漂移。
private enum CodexRadarPalette {
    static func color(status: String?, score: Double) -> Color {
        switch status {
        case "green":
            return Color(hexRGB: "#2F6ED3")
        case "yellow":
            return Color(hexRGB: "#D98200")
        case "red":
            return Color(hexRGB: "#D9293A")
        default:
            if score >= 100 {
                return Color(hexRGB: "#2F6ED3")
            }
            if score >= 80 {
                return Color(hexRGB: "#D98200")
            }
            return Color(hexRGB: "#D9293A")
        }
    }

    static func seriesColor(index: Int) -> Color {
        let colors = ["#2F6ED3", "#0E9F6E", "#D98200", "#D9293A"]
        return Color(hexRGB: colors[index % colors.count])
    }
}

/// 雷达数字格式化工具，避免散落的 String(format:) 影响 UI 统一性。
private enum CodexRadarNumberFormatter {
    static func score(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func compactScore(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// 雷达时间格式化工具；支持远端 ISO 字符串和本地 Date 两种来源。
private enum CodexRadarDateFormatter {
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// 将 ISO 时间压缩成中文短日期；解析失败时返回 nil 交给调用方回退。
    static func shortDateTime(_ value: String) -> String? {
        parseISODate(value).map { displayFormatter.string(from: $0) }
    }

    /// 格式化本地抓取时间，适合没有远端 monitored_at 时兜底。
    static func shortTime(_ value: Date) -> String {
        timeFormatter.string(from: value)
    }

    /// 把雷达日期压成横轴标签；am/pm 后缀保留为早/晚，帮助区分同一天多次跑分。
    static func axisLabel(_ value: String) -> String {
        let parts = value.split(separator: "-").map(String.init)
        guard parts.count >= 3,
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return value
        }
        let suffix: String
        if parts.dropFirst(3).first == "am" {
            suffix = "早"
        } else if parts.dropFirst(3).first == "pm" {
            suffix = "晚"
        } else {
            suffix = ""
        }
        return "\(month).\(day)\(suffix)"
    }

    /// 解析带或不带小数秒的 ISO8601 字符串。
    private static func parseISODate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        return plainFormatter.date(from: value)
    }
}
