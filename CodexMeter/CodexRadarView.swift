import CodexMeterShared
import SwiftUI

// 本文件负责下拉面板中的降智雷达可视化，包括分数卡、IQ 折线和同步状态。

/// 下拉面板里的降智雷达区块；展示最新 IQ 分数、历史折线和拉取状态。
struct CodexRadarSection: View {
    @ObservedObject var store: CodexRadarStore
    let settings: CodexRadarSettings

    /// 降智雷达详情页入口；弹窗里只放外链图标，完整说明交给网页承载。
    private static let radarPageURL = URL(string: "https://codexradar.com/")!

    var body: some View {
        if settings.isEnabled {
            VStack(alignment: .leading, spacing: 4) {
                header

                if let snapshot = store.snapshot, let modelIQ = snapshot.modelIQ {
                    let displaySeries = modelIQ.displaySeries(limit: modelIQ.allSeries.count)
                    CodexRadarScoreGrid(runs: displaySeries.compactMap(\.latest))
                    if settings.showsScoreChart {
                        CodexRadarLineChart(series: displaySeries)
                    }
                    footer(snapshot: snapshot)
                } else if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    ContentUnavailableView(AppLocalization.string("暂无雷达数据"), systemImage: "waveform.path.ecg")
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
            Label(AppLocalization.string("降智雷达"), systemImage: "brain.head.profile")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
            }
            Link(destination: Self.radarPageURL) {
                Image(systemName: "arrow.up.right")
            }
            .buttonStyle(.plain)
            .imageScale(.small)
            .help(AppLocalization.string("打开 Codex Radar"))
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .imageScale(.small)
            .disabled(store.isRefreshing)
            .help(AppLocalization.string("刷新降智雷达"))
        }
    }

    /// 生成底部同步文案；模型 IQ 更新时间优先，缺失时回退到本地抓取时间。
    private func footer(snapshot: CodexRadarSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(AppLocalization.string("常态 90-110"))
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
            return AppLocalization.usesEnglish() ? "Model IQ updated \(updatedAt)" : "模型IQ更新 \(updatedAt)"
        }
        let time = CodexRadarDateFormatter.shortTime(snapshot.fetchedAt)
        return AppLocalization.usesEnglish() ? "Fetched \(time)" : "抓取 \(time)"
    }
}

/// 最新模型矩阵，用最多两行的紧凑卡片展示模型和 IQ。
private struct CodexRadarScoreGrid: View {
    let runs: [CodexRadarIQRun]

    /// 矩阵中的单个模型家族，runs 保留上游的档位排序。
    private struct ModelFamily: Identifiable {
        let id: String
        let runs: [CodexRadarIQRun]
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(modelFamilies) { family in
                HStack(spacing: 4) {
                    Text(family.id)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .leading)

                    ForEach(family.runs) { run in
                        scoreCell(for: run)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 19, alignment: .leading)
            }
        }
    }

    /// 按首次出现顺序聚合模型家族，避免矩阵重复显示家族名。
    private var modelFamilies: [ModelFamily] {
        var familyOrder: [String] = []
        var groupedRuns: [String: [CodexRadarIQRun]] = [:]
        for run in runs {
            let family = CodexRadarScoreCardText.familyLabel(model: run.model)
            if groupedRuns[family] == nil {
                familyOrder.append(family)
            }
            groupedRuns[family, default: []].append(run)
        }
        return familyOrder.map { ModelFamily(id: $0, runs: groupedRuns[$0] ?? []) }
    }

    /// 构造档位单元格；通过数等次要信息只在悬停详情中展示。
    private func scoreCell(for run: CodexRadarIQRun) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(CodexRadarScoreCardText.effortLabel(run.reasoningEffort))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(CodexRadarNumberFormatter.compactScore(run.score))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color(for: run))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, minHeight: 18)
        .contentShape(Rectangle())
        .instantHelp(cardHelpText(for: run))
    }

    /// 生成卡片悬停详情，完整展示模型名、分数和任务通过情况。
    private func cardHelpText(for run: CodexRadarIQRun) -> String {
        CodexRadarDetailFormatter.text(for: run)
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
    @State private var hoveredPoint: HoveredPoint?

    /// 记录当前命中的日期和画布坐标，用于就近摆放聚合提示。
    private struct HoveredPoint: Equatable {
        let date: String
        let score: Double
        let location: CGPoint
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                drawChart(context: &context, size: size)
            }
            .accessibilityLabel(AppLocalization.string("降智雷达 IQ 曲线"))

            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoveredPoint = nearestPoint(to: location, size: proxy.size)
                        case .ended:
                            hoveredPoint = nil
                        }
                    }
            }

            if let hoveredPoint {
                hoverTooltip(date: hoveredPoint.date, score: hoveredPoint.score)
                    .fixedSize()
                    .position(tooltipPosition(for: hoveredPoint, chartWidth: MenuBarPopoverLayout.contentWidth - 10))
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 116)
    }

    /// 画坐标、常态区间和每条模型曲线。
    private func drawChart(context: inout GraphicsContext, size: CGSize) {
        let plotRect = plotRect(for: size)
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
        for score in [90.0, 110.0, 130.0, 150.0] {
            let y = pixelAligned(yPosition(score: score, rect: rect))
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(path, with: .color(.primary.opacity(score == 110 ? 0.22 : 0.11)), lineWidth: 1)
            let label = Text("\(Int(score))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            context.draw(label, at: CGPoint(x: 12, y: y), anchor: .leading)
        }
    }

    /// 绘制单条模型曲线和每个时间节点。
    private func drawSeries(
        _ item: CodexRadarModelSeries,
        index: Int,
        context: inout GraphicsContext,
        rect: CGRect
    ) {
        let color = CodexRadarPalette.seriesColor(index: index)
        for segment in visibleSegments(for: item) {
            let points = points(for: segment, rect: rect)
            let drawingPlan = CodexRadarLineChartLayout.drawingPlan(for: points.count)
            if drawingPlan.drawsLine {
                context.stroke(
                    smoothedPath(points: points),
                    with: .color(color.opacity(index == 0 ? 0.95 : 0.72)),
                    lineWidth: index == 0 ? 3 : 2
                )
            }
            for markerIndex in drawingPlan.markerIndexes {
                let point = points[markerIndex]
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
                    with: .color(color)
                )
            }
        }
    }

    /// 在横轴底部标出首、中、末日期，弥补迷你曲线缺少时间参照的问题。
    private func drawXAxisLabels(context: inout GraphicsContext, rect: CGRect) {
        let dates = allDates
        guard !dates.isEmpty else {
            return
        }
        let indexes = Array(Set([0, dates.count / 2, dates.count - 1])).sorted()
        let denominator = max(dates.count - 1, 1)
        for index in indexes {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(denominator)
            let label = Text(CodexRadarDateFormatter.axisLabel(dates[index]))
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

    /// 把远端日期映射到所有曲线共用的时间轴。
    private func points(for runs: [CodexRadarIQRun], rect: CGRect) -> [CGPoint] {
        let dates = allDates
        guard !runs.isEmpty, !dates.isEmpty else {
            return []
        }
        let denominator = max(dates.count - 1, 1)
        return runs.compactMap { run in
            guard let offset = dates.firstIndex(of: run.date) else {
                return nil
            }
            return CGPoint(
                x: rect.minX + rect.width * CGFloat(offset) / CGFloat(denominator),
                y: yPosition(score: run.score, rect: rect)
            )
        }
    }

    /// 把 IQ 90 及以上的连续跑分分段，低分日期会真正断开曲线。
    private func visibleSegments(for item: CodexRadarModelSeries) -> [[CodexRadarIQRun]] {
        item.recentDays.reduce(into: [[CodexRadarIQRun]]()) { segments, run in
            guard run.score >= 90 else {
                if segments.last?.isEmpty == false {
                    segments.append([])
                }
                return
            }
            if segments.isEmpty {
                segments.append([])
            }
            segments[segments.count - 1].append(run)
        }.filter { !$0.isEmpty }
    }

    /// 合并所有曲线的日期，保证同一时间的多个模型落在同一竖线。
    private var allDates: [String] {
        Array(Set(series.flatMap { $0.recentDays.map(\.date) })).sorted()
    }

    /// 只在鼠标距离数据点 10 像素内时命中，避免整条曲线都弹出提示。
    private func nearestPoint(to location: CGPoint, size: CGSize) -> HoveredPoint? {
        let rect = plotRect(for: size)
        let candidates = series.flatMap { item in
            let runs = item.recentDays.filter { $0.score >= 90 }
            return zip(runs, points(for: runs, rect: rect)).map { ($0.0.date, $0.0.score, $0.1) }
        }
        return candidates
            .map { (date: $0.0, score: $0.1, point: $0.2, distance: hypot($0.2.x - location.x, $0.2.y - location.y)) }
            .filter { $0.distance <= 10 }
            .min { $0.distance < $1.distance }
            .map { HoveredPoint(date: $0.date, score: $0.score, location: $0.point) }
    }

    /// 只聚合同一时间且同一 IQ 坐标的模型，不合并同时间的其他高度。
    private func hoverTooltip(date: String, score: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                if let run = item.recentDays.first(where: { $0.date == date && abs($0.score - score) < 0.001 }) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(CodexRadarPalette.seriesColor(index: index))
                            .frame(width: 7, height: 7)
                        Text("\(CodexRadarScoreCardText.shortLabel(model: item.model, effort: item.reasoningEffort)) · IQ \(CodexRadarNumberFormatter.compactScore(run.score))")
                    }
                }
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.35)))
    }

    /// 让提示框靠近数据点且不超出图表左右边界。
    private func tooltipPosition(for hoveredPoint: HoveredPoint, chartWidth: CGFloat) -> CGPoint {
        CGPoint(x: min(max(hoveredPoint.location.x, 80), chartWidth - 80), y: max(28, hoveredPoint.location.y - 30))
    }

    /// 统一画布绘制与悬停命中的实际坐标区域。
    private func plotRect(for size: CGSize) -> CGRect {
        CGRect(x: 28, y: 4, width: max(size.width - 34, 1), height: max(size.height - 20, 1))
    }

    /// 将 IQ 分数夹到 90-150 的可视范围，突出高分模型之间的差异。
    private func yPosition(score: Double, rect: CGRect) -> CGFloat {
        let clamped = min(max(score, 90), 150)
        let ratio = (clamped - 90) / 60
        return rect.maxY - rect.height * CGFloat(ratio)
    }

    /// 像素对齐水平线，减少低分辨率显示器上的模糊。
    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        return (value * scale).rounded() / scale
    }

}

/// 雷达颜色表；集中管理状态色和曲线色，避免卡片和图例各自漂移。
private enum CodexRadarPalette {
    /// 最多十二条曲线使用互不重复的高对比颜色，顺序与数据点和悬停提示保持一致。
    private static let seriesHexColors = [
        "#2F6ED3", // 蓝
        "#0E9F6E", // 绿
        "#D98200", // 橙
        "#D9293A", // 红
        "#8B5CF6", // 紫
        "#0891B2", // 青
        "#C026D3", // 紫红
        "#65A30D", // 黄绿
        "#E11D74", // 玫红
        "#4F46E5", // 靛蓝
        "#0F766E", // 蓝绿
        "#A16207"  // 琥珀
    ]

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
        Color(hexRGB: seriesHexColors[index % seriesHexColors.count])
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

/// 雷达悬停详情格式化工具；卡片和图例共享相同的完整信息层级。
private enum CodexRadarDetailFormatter {
    /// 生成完整模型名、分数和任务通过情况的多行说明。
    static func text(for run: CodexRadarIQRun) -> String {
        var details = [
            CodexRadarScoreCardText.fullLabel(model: run.model, effort: run.reasoningEffort),
            AppLocalization.usesEnglish()
                ? "Score \(CodexRadarNumberFormatter.compactScore(run.score))"
                : "分数 \(CodexRadarNumberFormatter.compactScore(run.score))"
        ]
        if let passed = run.passed, let tasks = run.tasks {
            details.append(AppLocalization.usesEnglish() ? "Passed \(passed)/\(tasks)" : "通过 \(passed)/\(tasks)")
        }
        return details.joined(separator: "\n")
    }
}

/// 即时悬停浮层；替代系统 help 的固定等待时间，并保持内容不参与原布局测量。
private struct CodexRadarInstantHelpModifier: ViewModifier {
    let text: String
    @State private var isPresented = false

    /// 鼠标进入时立即呈现浮层，离开时立即关闭，并禁用状态切换动画延迟。
    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    isPresented = hovering
                }
            }
            .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                Text(text)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .padding(8)
                    .fixedSize(horizontal: true, vertical: true)
            }
    }
}

private extension View {
    /// 为雷达卡片和图例附加无系统等待时间的悬停详情。
    func instantHelp(_ text: String) -> some View {
        modifier(CodexRadarInstantHelpModifier(text: text))
    }
}

/// 雷达时间格式化工具；支持远端 ISO 字符串和本地 Date 两种来源。
private enum CodexRadarDateFormatter {
    /// 创建跟随应用语言的日期时间格式器，避免静态缓存锁定首次语言。
    private static func displayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        let english = AppLocalization.usesEnglish()
        formatter.locale = Locale(identifier: english ? "en_US_POSIX" : "zh_Hans_CN")
        formatter.dateFormat = english ? "MMM d, HH:mm" : "M月d日 HH:mm"
        return formatter
    }

    /// 创建只显示时间的格式器，地区设置与当前应用语言保持一致。
    private static func timeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLocalization.usesEnglish() ? "en_US_POSIX" : "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    /// 将 ISO 时间压缩成中文短日期；解析失败时返回 nil 交给调用方回退。
    static func shortDateTime(_ value: String) -> String? {
        parseISODate(value).map { displayFormatter().string(from: $0) }
    }

    /// 格式化本地抓取时间，适合没有远端 monitored_at 时兜底。
    static func shortTime(_ value: Date) -> String {
        timeFormatter().string(from: value)
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
            suffix = AppLocalization.usesEnglish() ? " AM" : "早"
        } else if parts.dropFirst(3).first == "pm" {
            suffix = AppLocalization.usesEnglish() ? " PM" : "晚"
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
