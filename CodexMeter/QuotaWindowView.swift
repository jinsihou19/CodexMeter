// 供应商额度卡共用的主题、分段进度条和预期消耗绘制；主程序与设置预览使用同一实现。
import CodexMeterShared
import SwiftUI

/// 从共享偏好解析当前应用语言，供下拉面板中的独立子视图复用。
func currentAppLanguage() -> AppLanguage {
    AppLanguage(
        rawValue: MenuBarDisplaySettings.sharedDefaults.string(
            forKey: AppLanguagePreferenceKeys.selectedLanguage
        ) ?? ""
    ) ?? .system
}

/// 主弹窗与 Antigravity 设置页共用的额度卡；只展示真实快照，复用窗口的主题色和预期消耗。
struct GeminiModelsSection: View {
    let geminiSettings: GeminiModelsSettings
    let displaySettings: MenuBarDisplaySettings
    let showsPaceComparison: Bool
    let snapshot: GeminiModelsSnapshot?
    let errorMessage: String?
    let formatter: UsageFormatter
    let resetTimeDisplayStyle: ResetTimeDisplayStyle
    let onPaceMarkerHoverChange: (String?, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label {
                    Text(AppLocalization.string("Antigravity"))
                } icon: {
                    Image("AntigravityIcon")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let accountEmail = snapshot?.accountEmail, !accountEmail.isEmpty {
                    Text(accountEmail)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            if let snapshot {
                ForEach(visibleGroups(snapshot)) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                        ForEach(group.windows) { window in
                            geminiWindow(window)
                        }
                    }
                }
                if visibleGroups(snapshot).isEmpty {
                    Text(AppLocalization.string("当前模型没有可用配额窗口。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage, !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(AppLocalization.string("等待 Antigravity 配额刷新。"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .popoverCardSurface(opacity: 0.46)
    }

    /// 按选择的配额组过滤窗口；摘要接口只有总 Gemini 组时仍保留真实返回的数据。
    private func visibleGroups(_ snapshot: GeminiModelsSnapshot) -> [GeminiQuotaGroup] {
        switch geminiSettings.model {
        case .all:
            return snapshot.groups
        default:
            return snapshot.groups.filter { geminiSettings.model.matches(group: $0) }
        }
    }

    /// 将 Antigravity 的真实字段交给共用窗口视图，保留未知周期和重置描述的回退。
    private func geminiWindow(_ window: GeminiQuotaWindow) -> some View {
        ProviderQuotaWindowView(
            id: window.id,
            title: window.title,
            window: window.rateLimitWindow,
            remainingPercent: window.remainingPercent,
            remainingPercentText: window.remainingPercentText,
            displaySettings: displaySettings,
            showsPaceComparison: showsPaceComparison,
            resetText: resetText(for: window, rateLimitWindow: window.rateLimitWindow),
            onPaceMarkerHoverChange: onPaceMarkerHoverChange
        )
    }

    /// 按当前弹窗时间样式显示窗口重置时间；旧接口只有描述时保留原始文案。
    private func resetText(for window: GeminiQuotaWindow, rateLimitWindow: RateLimitWindow?) -> String? {
        switch resetTimeDisplayStyle {
        case .countdown:
            if rateLimitWindow?.resetsAt != nil {
                return formatter.resetRemainingText(window: rateLimitWindow)
            }
        case .absolute:
            if rateLimitWindow?.resetsAt != nil {
                return formatter.resetTime(epochSeconds: rateLimitWindow?.resetsAt)
            }
        }
        guard let resetDescription = window.resetDescription, !resetDescription.isEmpty else {
            return nil
        }
        return resetDescription
    }
}

/// Antigravity 与 OpenCode Go 共用的额度窗口，统一主题色、分段刻度、用量速度和理论节奏提示。
/// 未知周期仍显示真实剩余值，但不会生成预期消耗；悬浮说明交由弹窗根视图管理。
struct ProviderQuotaWindowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let id: String
    let title: String
    let window: RateLimitWindow?
    let remainingPercent: Int?
    let remainingPercentText: String?
    let displaySettings: MenuBarDisplaySettings
    let showsPaceComparison: Bool
    let resetText: String?
    let onPaceMarkerHoverChange: (String?, Bool) -> Void

    /// 复用成熟供应商的绘制路径，颜色和消耗计算始终读取调用方当前设置。
    var body: some View {
        let tone = UsageRemainingTone(remainingPercent: remainingPercent)
        let paceDisplay = showsPaceComparison
            ? UsageWindowPaceDisplay(
                id: id,
                title: title,
                window: window,
                weeklyProgressWorkDays: displaySettings.weeklyProgressWorkDays
            )?.display
            : nil
        let paceMarker = paceMarker(for: window)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(remainingPercentText ?? "--")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tone.popoverColor(settings: displaySettings, colorScheme: colorScheme))
            }

            WorkdayMarkedProgressView(
                value: Double(remainingPercent ?? 0),
                tint: tone.popoverColor(settings: displaySettings, colorScheme: colorScheme),
                markers: usageProgressSegmentPercents(
                    workDays: displaySettings.weeklyProgressWorkDays,
                    windowDurationMins: window?.windowDurationMins
                ),
                paceMarker: paceMarker,
                onPaceMarkerHoverChange: { isHovered in
                    onPaceMarkerHoverChange(paceMarker?.helpText, isHovered)
                }
            )

            // 重置与消耗提示共用进度条下方一行，避免每个窗口为速度说明额外增高。
            if resetText != nil || paceDisplay != nil {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let resetText {
                        Text("\(AppLocalization.string("重置")) \(resetText)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    Spacer(minLength: 0)
                    if let paceDisplay {
                        Text(paceDisplay.detailText(language: currentAppLanguage()))
                            .fontWeight(.semibold)
                            .foregroundStyle(paceDisplay.tone.popoverColor(settings: displaySettings, colorScheme: colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .help(paceDisplay.detailText(language: currentAppLanguage()))
                    }
                }
                .font(.caption2)
            }
        }
    }

    /// 生成和 Codex 相同的理论节奏标记，并沿用当前工作日刻度配置。
    private func paceMarker(for window: RateLimitWindow?) -> ProgressPaceMarker? {
        guard let pace = window?.usagePace(weeklyProgressWorkDays: displaySettings.weeklyProgressWorkDays),
              pace.isDisplayable(),
              abs(pace.roundedDeltaPercent) > 2
        else {
            return nil
        }
        return ProgressPaceMarker(
            percent: 100 - pace.expectedUsedPercent,
            color: pace.deltaPercent <= 0 ? .green : .red,
            helpText: AppLocalization.string(
                pace.deltaPercent <= 0
                    ? "绿色线：按当前时间进度推算的理论剩余位置；绿色表示实际用得比理论慢，有余量。"
                    : "红色线：按当前时间进度推算的理论剩余位置；红色表示实际用得比理论快，可能提前耗尽。"
            )
        )
    }
}

/// 用量条上的理论节奏标记：绿色表示当前用量慢于预期，红色表示快于预期。
struct ProgressPaceMarker {
    let percent: Double
    let color: Color
    let helpText: String
}

/// 菜单卡片进度条用单个 Canvas 绘制轨道、填充和内嵌刻度线。
struct WorkdayMarkedProgressView: View {
    let value: Double
    let tint: Color
    let markers: [Double]
    let paceMarker: ProgressPaceMarker?
    let onPaceMarkerHoverChange: (Bool) -> Void
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        progressBody
            .overlay {
                GeometryReader { proxy in
                    if let paceMarker {
                        paceMarkerOverlay(marker: paceMarker, size: proxy.size)
                    }
                }
                .allowsHitTesting(paceMarker != nil)
            }
    }

    private var progressBody: some View {
        Canvas { context, size in
            drawProgress(context: &context, size: size)
        }
            .frame(height: 6)
            .accessibilityLabel(AppLocalization.string("用量进度"))
            .accessibilityValue("\(Int(min(max(value, 0), 100)))%")
    }

    /// 只在理论节奏线附近建立悬浮热区，避免鼠标经过整条进度条时频繁弹出说明。
    @ViewBuilder
    private func paceMarkerOverlay(marker: ProgressPaceMarker, size: CGSize) -> some View {
        let x = size.width * Self.clampedPercent(marker.percent) / 100
        Color.clear
            .frame(width: Self.paceMarkerHitWidth, height: Self.paceMarkerHitHeight)
            .contentShape(Rectangle())
            .position(x: x, y: size.height / 2)
            .onHover { isHovered in
                onPaceMarkerHoverChange(isHovered)
            }
    }

    /// 绘制完整进度条；让 body 只负责组合 tooltip，避免悬浮提示逻辑和绘制逻辑混在一起。
    private func drawProgress(context: inout GraphicsContext, size: CGSize) {
        let scale = max(displayScale, 1)
        let rect = CGRect(origin: .zero, size: size)
        let cornerRadius = size.height / 2
        let cornerSize = CGSize(width: cornerRadius, height: cornerRadius)
        let clampedValue = min(max(value, 0), 100)
        let fillWidth = size.width * clampedValue / 100

        context.clip(to: Path(rect))

        let trackPath = segmentPath(size: size, scale: scale)
        context.fill(trackPath, with: .color(Color.primary.opacity(0.10)))

        if fillWidth > 0 {
            let fillRect = CGRect(
                x: 0,
                y: 0,
                width: min(fillWidth, size.width),
                height: size.height
            )
            let fillPath = Path { path in
                path.addRoundedRect(in: fillRect, cornerSize: cornerSize)
            }
            context.drawLayer { layer in
                layer.clip(to: trackPath)
                layer.fill(fillPath, with: .color(tint))
            }
        }

        if let paceMarker {
            let x = size.width * Self.clampedPercent(paceMarker.percent) / 100
            let stripes = Self.paceMarkerPaths(x: x, size: size, scale: scale)
            context.blendMode = .destinationOut
            context.fill(stripes.punch, with: .color(.white.opacity(0.9)))
            context.blendMode = .normal
            context.fill(stripes.center, with: .color(paceMarker.color))
        }
    }

    /// 按工作日分界生成独立胶囊轨道；没有分界时回退为单个完整胶囊。
    private func segmentPath(size: CGSize, scale rawScale: CGFloat) -> Path {
        let scale = max(rawScale, 1)
        let gap: CGFloat = 2
        let markerBoundaries = markers.map(Self.clampedPercent).filter({ $0 > 0 && $0 < 100 }).sorted()
        let boundaries = [0] + markerBoundaries + [100]
        let align: (CGFloat) -> CGFloat = { value in
            (value * scale).rounded() / scale
        }
        return Path { path in
            for index in 0..<(boundaries.count - 1) {
                let start = align(
                    size.width * boundaries[index] / 100 + (index == 0 ? 0 : gap / 2)
                )
                let end = align(
                    size.width * boundaries[index + 1] / 100
                        - (index == boundaries.count - 2 ? 0 : gap / 2)
                )
                guard end > start else { continue }
                let segmentRect = CGRect(x: start, y: 0, width: end - start, height: size.height)
                path.addRoundedRect(
                    in: segmentRect,
                    cornerSize: CGSize(width: size.height / 2, height: size.height / 2)
                )
            }
        }
    }

    private static func clampedPercent(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    private static let paceMarkerHitWidth: CGFloat = 24
    private static let paceMarkerHitHeight: CGFloat = 22

    /// 绿色/红色节奏标记先挖出一条窄槽，再在中心绘制醒目的节奏线。
    private static func paceMarkerPaths(
        x: CGFloat,
        size: CGSize,
        scale rawScale: CGFloat
    ) -> (punch: Path, center: Path) {
        let scale = max(rawScale, 1)
        let align: (CGFloat) -> CGFloat = { value in
            (value * scale).rounded() / scale
        }
        let stripeWidth: CGFloat = 2
        let punchWidth = stripeWidth * 3
        let extendedHeight = size.height * 3
        let y = align(-size.height)
        let height = align(extendedHeight)
        let punchRect = CGRect(
            x: align(x - punchWidth / 2),
            y: y,
            width: punchWidth,
            height: height
        )
        let centerRect = CGRect(
            x: align(x - stripeWidth / 2),
            y: y,
            width: stripeWidth,
            height: height
        )
        return (
            Path { path in path.addRect(punchRect) },
            Path { path in path.addRect(centerRect) }
        )
    }
}

extension View {
    /// 在浅色主题中使用系统玻璃材质，深色主题保持现有卡片对比度。
    func popoverCardSurface(opacity: Double) -> some View {
        modifier(PopoverCardSurfaceModifier(opacity: opacity))
    }

    /// 为弹窗区块统一添加内边距和卡片材质。
    func menuSectionCard(padding: CGFloat) -> some View {
        self
            .padding(padding)
            .popoverCardSurface(opacity: 0.46)
    }
}

/// 统一菜单卡片的中性分隔样式，玻璃只由弹窗根层绘制一次。
struct PopoverCardSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let opacity: Double

    /// 浅色卡片只加中性暗部边界，避免多层白色覆盖吞掉背景透射。
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return content
            .background(
                colorScheme == .light
                    ? Color.black.opacity(opacity * 0.05)
                    : Color.black.opacity(opacity * 0.12),
                in: shape
            )
            .overlay(
                shape.stroke(
                    colorScheme == .light ? .black.opacity(0.08) : .white.opacity(0.14),
                    lineWidth: 0.5
                )
            )
    }
}
