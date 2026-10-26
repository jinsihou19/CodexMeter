// Codex 页面只读仪表盘：复用共享快照和价格目录，不扫描日志或重新计算历史账单。
import CodexMeterShared
import SwiftUI

/// 将账单、额度、价格与两种来源的用量放入设置 Form，持续跟随共享快照更新。
struct CodexDashboardSections: View {
    let snapshot: UsageSnapshot?
    let displaySettings: MenuBarDisplaySettings
    @State private var activityMode = TokenActivityMode.daily
    @State private var heatmapMode = LocalUsageHeatmapMode.daily
    @State private var showsBillingDetails = false

    /// 与下拉面板使用同一格式器，并跟随应用语言。
    private var formatter: UsageFormatter { UsageFormatter(language: currentAppLanguage()) }

    /// 页面固定展示核心统计，不读取下拉面板的栏目隐藏设置。
    var body: some View {
        Section(dashboardText("账单估算", "Estimated bill")) {
            billing
        }
        Section(AppLocalization.string("额度与用量")) {
            if let snapshot, snapshot.rateLimits.primary != nil || snapshot.rateLimits.secondary != nil {
                QuotaSummaryGrid(
                    snapshot: snapshot.rateLimits, formatter: formatter, settings: displaySettings,
                    showsPaceComparison: true, resetTimeDisplayStyle: .countdown,
                    onPaceMarkerHoverChange: { _, _ in }
                )
                syncLabel(snapshot.fetchedAt, source: dashboardText("官方额度", "Official quota"))
            } else {
                emptyState(dashboardText("尚无官方额度数据，登录 Codex 后等待同步。", "No quota data yet. Sign in to Codex and wait for sync."))
            }
        }
        Section(dashboardText("本地用量", "Local usage")) {
            if let summary = snapshot?.localCodexUsage {
                localUsage(summary)
            } else {
                emptyState(dashboardText("尚无本地用量，首次读取历史日志可能需要一些时间。", "No local usage yet. The first history scan can take a while."))
            }
        }
        Section(dashboardText("云端用量", "Cloud usage")) {
            if let stats = snapshot?.profileStats {
                ProfileStatsSection(
                    stats: stats, activityMode: $activityMode, formatter: formatter,
                    popoverSettings: PopoverDisplaySettings(showsActivityInsights: false)
                )
                Text(dashboardText("官方账户统计可能包含本机活动，与本地用量分别展示，不相加。云端明细可能延迟。", "Account statistics may include local activity. The two sources are shown separately and are not added together. Cloud details may be delayed."))
                    .font(.caption).foregroundStyle(.secondary)
                if let snapshot { syncLabel(snapshot.fetchedAt, source: dashboardText("云端同步", "Cloud sync")) }
            } else {
                emptyState(dashboardText("尚无云端用量数据；本地账单估算仍可独立查看。", "Cloud usage is not available yet. Local cost estimates remain independent."))
            }
        }
        Section {
            // 低频参考信息放在两种用量之后，并保持默认收起。
            DisclosureGroup(dashboardText("当前模型价格", "Current model prices")) {
                CodexModelPricesView()
            }
        }
    }

    /// 核心金额下只保留一行口径和完整性状态，详细原因按需展开；未知金额仍显示占位符。
    private var billing: some View {
        let local = snapshot?.localCodexUsage
        let hasPartialData = local?.hasIncompleteUsage == true || local?.pricingStatus?.unpricedModels.isEmpty == false
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dashboardText("月度估算", "Monthly estimate"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(currency(snapshot?.localCodexUsage?.monthCost?.estimatedCostUSD))
                        .font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                Spacer(minLength: 0)
                metric(dashboardText("今日估算", "Today's estimate"), value: currency(Self.todayCost(snapshot?.localCodexUsage)), valueFont: .system(size: 26, weight: .semibold, design: .rounded))
                if let cost = snapshot?.localCodexUsage?.monthCost {
                    metric(dashboardText("当月已计价会话", "Priced sessions this month"), value: "\(cost.pricedSessionCount) / \(cost.sessionCount)", valueFont: .system(size: 26, weight: .semibold, design: .rounded))
                }
            }
            HStack(spacing: 6) {
                if let local {
                    Text(local.fetchedAt, format: .dateTime.year().month())
                    Text("·")
                }
                Text(dashboardText("API 等效 · USD", "API equivalent · USD"))
                Spacer(minLength: 8)
                Button {
                    showsBillingDetails.toggle()
                } label: {
                    Label(
                        hasPartialData ? dashboardText("部分数据", "Partial data") : dashboardText("估算说明", "Estimate details"),
                        systemImage: hasPartialData ? "exclamationmark.triangle" : "info.circle"
                    )
                    .foregroundStyle(hasPartialData ? Color.orange : Color.secondary)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(dashboardText("查看估算口径与数据完整性", "View estimation method and data coverage"))
                .popover(isPresented: $showsBillingDetails, arrowEdge: .bottom) {
                    billingDetails
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// 计价口径和历史缺失项集中在说明浮层，避免常驻多行，同时保留不完整数据的解释。
    private var billingDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dashboardText("估算说明", "Estimate details")).font(.headline)
            Text(dashboardText("按本机日志中的模型、Token 与服务档位估算，不代表订阅实际账单；未记录档位时按 Standard 计价。", "Estimated from models, tokens and service tiers in local logs, not your subscription invoice. Missing tiers use Standard pricing."))
                .foregroundStyle(.secondary)
            if snapshot?.localCodexUsage?.monthCost == nil {
                emptyState(dashboardText("暂无可用费用明细，缺失金额显示为 —。", "No priced usage is available yet. Missing amounts are shown as —."))
            }
            if snapshot?.localCodexUsage?.hasIncompleteUsage == true {
                Label(AppLocalization.string("部分统计仅包含可解析数据"), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let status = snapshot?.localCodexUsage?.pricingStatus, !status.unpricedModels.isEmpty {
                Text(dashboardText("历史记录未计价模型：", "Unpriced models in history: ") + status.unpricedModels.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            if let local = snapshot?.localCodexUsage { syncLabel(local.fetchedAt, source: dashboardText("本机日志", "Local logs")) }
        }
        .font(.callout)
        .textSelection(.enabled)
        .frame(width: 320, alignment: .leading)
        .padding(16)
    }

    /// 仅匹配本地日历的今天，避免跨日时把缓存中的昨天费用显示为今天；缺日保留未知。
    static func todayCost(_ summary: LocalCodexUsageSummary?, now: Date = Date(), timeZone: TimeZone = .current) -> Double? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: now)
        return summary?.dailyBuckets?.first(where: { $0.id == day })?.estimatedCostUSD
    }

    /// 本地 Token、成本构成和热力图都读取同一份汇总，保持与菜单栏的统计口径一致。
    private func localUsage(_ summary: LocalCodexUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                metric(AppLocalization.string("今日"), value: formatter.tokenCount(summary.todayTokens))
                metric(AppLocalization.string("近 7 天"), value: formatter.tokenCount(summary.sevenDayTokens))
                metric(AppLocalization.string("累计"), value: formatter.tokenCount(summary.lifetimeTokens))
                metric(AppLocalization.string("线程"), value: "\(summary.threadCount)")
            }
            if let cost = summary.monthCost {
                Divider()
                Text(dashboardText("本月 Token 构成", "Monthly token breakdown")).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    metric(AppLocalization.string("未缓存"), value: formatter.tokenCount(cost.inputTokens - cost.cachedInputTokens))
                    metric(AppLocalization.string("缓存输入"), value: formatter.tokenCount(cost.cachedInputTokens))
                    metric(AppLocalization.string("输出"), value: formatter.tokenCount(cost.outputTokens))
                }
            }
            Divider()
            HStack {
                Text(dashboardText("本地活动", "Local activity")).font(.caption.weight(.semibold))
                Spacer()
                Picker(AppLocalization.string("趋势"), selection: $heatmapMode) {
                    ForEach(LocalUsageHeatmapMode.allCases) { mode in
                        Text(AppLocalization.string(mode.title)).tag(mode)
                    }
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 180)
            }
            LocalMenuUsageHeatmap(buckets: summary.dailyBuckets ?? [], fetchedAt: summary.fetchedAt, mode: heatmapMode, formatter: formatter, weekCount: 52)
            syncLabel(summary.fetchedAt, source: dashboardText("本机日志", "Local logs"))
        }
        .padding(.vertical, 4)
    }

    /// 摘要默认沿用用量字号；账单可提高数值层级，辅助功能仍读出完整文本。
    private func metric(_ title: String, value: String, valueFont: Font = .title3.weight(.semibold)) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(valueFont).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// 显示每个来源自己的同步时间，让缓存数据和实时值可区分。
    private func syncLabel(_ date: Date, source: String) -> some View {
        Text("\(source) · \(formatter.fetchedAt(date))")
            .font(.caption).foregroundStyle(.secondary)
    }

    /// 空状态不填造示例数据，也不把未返回的用量当成零。
    private func emptyState(_ message: String) -> some View {
        Text(message).font(.callout).foregroundStyle(.secondary)
    }

    /// 账单金额统一保留两位小数；未知金额保留占位符。
    private func currency(_ value: Double?) -> String {
        value.map { $0.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) } ?? "—"
    }
}

/// 当前单价表直接使用计价目录；仅选择标准/长上下文字段，不复制计费公式或改写历史版本。
struct CodexModelPricesView: View {
    @State private var catalog = LocalCodexPricingCatalog()
    @State private var longContext = false
    private let models = ["gpt-6.1-sol", "gpt-6-astra", "gpt-6-sol", "gpt-6-luna", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]

    /// 展示当前 Codex 模型和目录中的其他 GPT 价格，远程读取失败时继续显示内置或缓存单价。
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(dashboardText("Standard · 每百万 Token / USD", "Standard · USD per million tokens"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker(dashboardText("上下文价格", "Context pricing"), selection: $longContext) {
                    Text(dashboardText("标准上下文", "Standard context")).tag(false)
                    Text(dashboardText("长上下文", "Long context")).tag(true)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 220)
            }
            priceTable(models)
            DisclosureGroup(dashboardText("更多模型", "More models")) {
                priceTable(catalog.revisions.keys.filter { $0.hasPrefix("gpt-5") && !models.contains($0) }.sorted())
                    .padding(.top, 8)
            }
            Text(dashboardText("长上下文按每个模型的单次输入阈值计价，阈值标在模型下方；— 表示目录未提供该项价格。", "Long-context rates apply above each model's input threshold, shown below its name. — means the catalog has no rate for that item."))
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup(dashboardText("服务档位与计价说明", "Service tiers and pricing notes")) {
                Text(dashboardText("GPT-6 系列：Fast 为 Standard 的 2 倍，Flex / Batch 为 0.5 倍。GPT-6.1 Sol 与 GPT-6 Astra 的 Ultrafast 为 6 倍。长上下文与档位倍率叠加。历史费用使用对应日期的价格，不能直接用当前单价反推。", "GPT-6: Fast is 2× Standard; Flex / Batch is 0.5×. Ultrafast is 6× for GPT-6.1 Sol and GPT-6 Astra. Tier multipliers also apply to long-context rates. Historical costs use dated prices, not necessarily today's rates."))
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            }
            HStack {
                if let date = catalog.fetchedAt {
                    Text("models.dev · \(date.formatted(date: .abbreviated, time: .shortened))")
                    if Date().timeIntervalSince(date) >= 86_400 {
                        Text(dashboardText("缓存价格", "Cached prices")).foregroundStyle(.orange)
                    }
                } else {
                    Text(dashboardText("内置价格 · 尚未同步远程目录", "Built-in prices · catalog not synced yet"))
                }
                Spacer()
                Link(dashboardText("OpenAI 官方价格 ↗", "OpenAI pricing ↗"), destination: URL(string: "https://developers.openai.com/api/docs/pricing")!)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .task { catalog = await LocalCodexPricingStore.shared.snapshot(now: Date()) }
    }

    /// 使用明确的表头与逐行来源；价格缺失时显示破折号，绝不补零。
    private func priceTable(_ names: [String]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
            GridRow {
                Text(dashboardText("模型", "Model")).frame(maxWidth: .infinity, alignment: .leading)
                Text(AppLocalization.string("输入"))
                Text(AppLocalization.string("缓存输入"))
                Text(AppLocalization.string("输出"))
            }
            .font(.caption).foregroundStyle(.secondary)
            ForEach(names, id: \.self) { model in
                let row = CodexModelPriceRow(model: model, catalog: catalog, longContext: longContext)
                GridRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model).font(.callout.weight(.medium))
                        Text(row.source + (longContext ? " · > \(row.threshold.map(String.init) ?? "—") Token" : ""))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(rate(row.input)).gridColumnAlignment(.trailing)
                    Text(rate(row.cached)).gridColumnAlignment(.trailing)
                    Text(rate(row.output)).gridColumnAlignment(.trailing)
                }
                .monospacedDigit()
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// 单价保留最多四位小数，避免 Luna 等低价模型被账单的两位精度四舍五入为零。
    private func rate(_ value: Double?) -> String {
        value.map { "$" + $0.formatted(.number.locale(Locale(identifier: "en_US")).precision(.fractionLength(2...4))) } ?? "—"
    }
}

/// 价格表的一行只做字段选择；可独立验证远程修订、长上下文与未知价格的展示语义。
struct CodexModelPriceRow {
    let input: Double?
    let cached: Double?
    let output: Double?
    let threshold: Int?
    let source: String

    /// 默认取本地当前日期的价格；长上下文缺失时保持未知，不退回低价档。
    init(model: String, catalog: LocalCodexPricingCatalog, longContext: Bool, day: String? = nil) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let price = catalog.price(for: model, on: day ?? formatter.string(from: Date()))
        input = longContext ? price?.inputAboveThreshold : price?.inputPerMillion
        cached = longContext ? price?.cachedInputAboveThreshold : price?.cachedInputPerMillion
        output = longContext ? price?.outputAboveThreshold : price?.outputPerMillion
        threshold = price?.thresholdTokens
        source = price.map { AppLocalization.string($0.source) } ?? dashboardText("暂无价格", "No price")
    }
}

/// 页面新增文案跟随应用语言；不改变既有共享翻译键。
private func dashboardText(_ chinese: String, _ english: String) -> String {
    AppLocalization.usesEnglish() ? english : chinese
}
