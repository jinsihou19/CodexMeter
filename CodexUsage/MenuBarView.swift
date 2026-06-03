import CodexUsageShared
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: UsageViewModel
    private let formatter = UsageFormatter()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            if let snapshot = viewModel.snapshot {
                usageContent(snapshot)
            } else {
                ContentUnavailableView("暂无用量数据", systemImage: "clock")
                    .frame(width: 280)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing)

                Button {
                    SettingsWindowPresenter.shared.show()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.statusSymbolName)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex 用量")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.menuHeaderPrimaryText)
                    Text(viewModel.menuHeaderSecondaryText)
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func usageContent(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 10) {
                UsageMetricCard(
                    display: UsageMetricDisplay(title: "5 小时窗口", window: snapshot.rateLimits.primary),
                    resetText: formatter.resetTime(epochSeconds: snapshot.rateLimits.primary?.resetsAt),
                    tone: tone(for: snapshot.rateLimits.primary)
                )
                UsageMetricCard(
                    display: UsageMetricDisplay(title: "7 天窗口", window: snapshot.rateLimits.secondary),
                    resetText: formatter.resetTime(epochSeconds: snapshot.rateLimits.secondary?.resetsAt),
                    tone: tone(for: snapshot.rateLimits.secondary)
                )
            }

            InfoRow(title: "套餐", value: snapshot.rateLimits.planType ?? "--")
            InfoRow(title: "用量桶", value: snapshot.rateLimits.displayName)
            InfoRow(title: "credits", value: formatter.creditsStatus(snapshot.rateLimits.credits))
            InfoRow(title: "限制状态", value: snapshot.rateLimits.rateLimitReachedType ?? "未触发")
            InfoRow(title: "最近同步", value: formatter.fetchedAt(snapshot.fetchedAt))
            if viewModel.isStale {
                Label("数据可能已过期", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tone(for window: RateLimitWindow?) -> UsageRemainingTone {
        guard let remainingPercent = window?.remainingPercent else {
            return .unavailable
        }
        if remainingPercent < 40 {
            return .danger
        }
        if remainingPercent < 70 {
            return .warning
        }
        return .good
    }
}

private struct UsageMetricCard: View {
    let display: UsageMetricDisplay
    let resetText: String
    let tone: UsageRemainingTone

    private let settings = MenuBarDisplaySettings()

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(display.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("重置 \(resetText)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(display.remainingText)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tone.statusBarColor(settings: settings))
                Text("剩余")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ProgressView(value: display.progressValue, total: 100)
                .tint(tone.statusBarColor(settings: settings))

            HStack {
                Text(display.usedText)
                Spacer()
                Text(display.windowDurationText)
            }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}
