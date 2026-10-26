// OpenCode Go 独立设置和额度卡；菜单栏项目由统一布局编辑器管理。
import CodexMeterShared
import SwiftUI

/// 设置页管理 Go 启用和卡片显示并保留额度预览；手动凭据在底部折叠且不回显密钥。
struct OpenCodeGoSettingsView: View {
    @ObservedObject var store = OpenCodeGoStore.shared
    @State private var apiKey = ""
    @State private var message: String?
    @State private var showsAPIKeyHelp = false

    /// 显示开关仅控制下拉面板；预览仍可见，手动 Key 默认折叠供按需配置。
    var body: some View {
        Form {
            Section {
                Toggle("启用 OpenCode Go", isOn: $store.isEnabled)
                SettingsToggleRow(
                    title: "显示在下拉面板",
                    subtitle: "在下拉面板中展示 OpenCode Go 额度卡片。",
                    isOn: $store.showsInPopover
                )
            }
            if store.isEnabled {
                Section {
                    OpenCodeGoSection(
                        store: store,
                        displaySettings: MenuBarDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults),
                        popoverSettings: PopoverDisplaySettings(defaults: MenuBarDisplaySettings.sharedDefaults)
                    )
                }
            }
            Section {
                DisclosureGroup {
                    Text("默认自动读取本机凭据，仅在无法自动读取或需要覆盖时手动配置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("输入 OpenCode Go API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("保存到钥匙串") { save(apiKey) }
                            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("恢复自动读取") { save("") }
                    }
                    if let message { Text(message).font(.caption).textSelection(.enabled) }
                    Link("打开 OpenCode Go 控制台", destination: URL(string: "https://opencode.ai/console")!)
                } label: {
                    HStack(spacing: 6) {
                        Text("API Key（按需配置）")
                        Button { showsAPIKeyHelp = true } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("API Key 读取说明")
                        // 显式响应悬停，避免分组标题里的系统 help 不触发或长时间等待。
                        .onHover { showsAPIKeyHelp = $0 }
                        .popover(isPresented: $showsAPIKeyHelp, arrowEdge: .bottom) {
                            Text("默认读取 OPENCODE_API_KEY 或本机 OpenCode 的 opencode-go 登录凭据。手动保存的 Key 优先，仅保存在系统钥匙串。")
                                .font(.callout)
                                .frame(width: 320, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// 保留失败时的输入便于重试；保存成功立即清空输入框中的密钥。
    private func save(_ key: String) {
        do {
            try store.saveKey(key)
            apiKey = ""
            message = key.isEmpty ? "已恢复自动读取。" : "API Key 已保存到系统钥匙串。"
        } catch {
            message = error.localizedDescription
        }
    }
}

/// 主弹窗与设置页共用的 Go 额度卡；复用 Antigravity 的窗口样式，错误与旧数据同时显示。
struct OpenCodeGoSection: View {
    @ObservedObject var store = OpenCodeGoStore.shared
    let displaySettings: MenuBarDisplaySettings
    let popoverSettings: PopoverDisplaySettings
    var onPaceMarkerHoverChange: (String?, Bool) -> Void = { _, _ in }

    /// 仅在启用时占用布局，所有窗口都保留接口提供的独立重置时间。
    var body: some View {
        if store.isEnabled {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label {
                        Text("OpenCode Go")
                    } icon: {
                        Image("OpenCodeIcon")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Spacer()
                    // 同步时间紧邻刷新入口，减少卡片底部占用，同时保留失败时的旧数据标识。
                    if let snapshot = store.snapshot {
                        HStack(spacing: 4) {
                            Text(store.errorMessage == nil ? "最近同步" : "上次成功同步")
                            Text(snapshot.fetchedAt, style: .time)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Button { Task { await store.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.isRefreshing)
                    .help("刷新 OpenCode Go 额度")
                    .accessibilityLabel("刷新 OpenCode Go 额度")
                }
                if let snapshot = store.snapshot {
                    ForEach(snapshot.windows) { window in
                        ProviderQuotaWindowView(
                            id: window.id,
                            title: AppLocalization.string(window.title),
                            window: window.quota,
                            remainingPercent: window.quota.remainingPercent,
                            remainingPercentText: window.quota.remainingPercentText,
                            displaySettings: displaySettings,
                            showsPaceComparison: popoverSettings.showsPaceComparison,
                            resetText: resetText(for: window.quota),
                            onPaceMarkerHoverChange: onPaceMarkerHoverChange
                        )
                    }
                } else if store.errorMessage == nil {
                    Text(store.isRefreshing ? "正在读取额度…" : "点击刷新以读取 OpenCode Go 额度。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .popoverCardSurface(opacity: 0.46)
        }
    }

    /// 与 Antigravity 共用重置时间偏好，接口缺失重置时间时不显示占位值。
    private func resetText(for window: RateLimitWindow) -> String? {
        guard window.resetsAt != nil else { return nil }
        let formatter = UsageFormatter(language: currentAppLanguage())
        switch popoverSettings.resetTimeDisplayStyle {
        case .countdown: return formatter.resetRemainingText(window: window)
        case .absolute: return formatter.resetTime(epochSeconds: window.resetsAt)
        }
    }

}
