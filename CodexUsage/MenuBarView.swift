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

                SettingsLink {
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
            InfoRow(title: "套餐", value: snapshot.rateLimits.planType ?? "--")
            InfoRow(title: "用量桶", value: snapshot.rateLimits.displayName)
            MetricRow(
                title: "5 小时窗口",
                window: snapshot.rateLimits.primary,
                resetText: formatter.resetTime(epochSeconds: snapshot.rateLimits.primary?.resetsAt)
            )
            MetricRow(
                title: "7 天窗口",
                window: snapshot.rateLimits.secondary,
                resetText: formatter.resetTime(epochSeconds: snapshot.rateLimits.secondary?.resetsAt)
            )
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
}

private struct MetricRow: View {
    let title: String
    let window: RateLimitWindow?
    let resetText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(window.map { "剩余 \($0.remainingPercent)%" } ?? "剩余 --")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            ProgressView(value: Double(window?.remainingPercent ?? 0), total: 100)
            HStack {
                Text(window.map { "已用 \(Int($0.usedPercent.rounded()))%" } ?? "已用 --")
                Spacer()
                Text(windowDurationText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("重置 \(resetText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var windowDurationText: String {
        guard let minutes = window?.windowDurationMins else {
            return "窗口 --"
        }
        if minutes % 1_440 == 0 {
            return "窗口 \(minutes / 1_440) 天"
        }
        if minutes % 60 == 0 {
            return "窗口 \(minutes / 60) 小时"
        }
        return "窗口 \(minutes) 分钟"
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
