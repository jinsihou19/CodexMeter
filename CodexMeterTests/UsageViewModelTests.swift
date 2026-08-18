import AppKit
import ServiceManagement
import XCTest
@testable import CodexMeterShared

@MainActor
final class UsageViewModelTests: XCTestCase {
    /// 验证设置侧栏版本文案组合用户版本和构建号，并能在缺少构建号时安全回退。
    func testAppVersionDisplayFormatsBundleVersionAndBuild() {
        XCTAssertEqual(
            AppVersionDisplay.text(infoDictionary: [
                "CFBundleShortVersionString": "1.0.1",
                "CFBundleVersion": "2"
            ], language: .chineseSimplified),
            "版本 1.0.1 (2)"
        )
        XCTAssertEqual(
            AppVersionDisplay.text(
                infoDictionary: ["CFBundleShortVersionString": "1.0.1"],
                language: .chineseSimplified
            ),
            "版本 1.0.1"
        )
        XCTAssertEqual(
            AppVersionDisplay.text(
                infoDictionary: ["CFBundleShortVersionString": "1.0.1"],
                language: .english
            ),
            "Version 1.0.1"
        )
    }

    /// 验证设置页使用八个稳定入口和原生分组控件，并把高级内容并入 Codex。
    func testSettingsUsesSimplifiedNativeStructure() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent("CodexMeter/SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("List(selection:"))
        XCTAssertTrue(source.contains(".formStyle(.grouped)"))
        XCTAssertTrue(source.contains("DisclosureGroup(AppLocalization.string(\"更多选项\")"))
        XCTAssertTrue(source.contains("DisclosureGroup(AppLocalization.string(\"连接详情\")"))
        XCTAssertTrue(source.contains("case notifications"))
        XCTAssertTrue(source.contains("private var notificationsPane: some View"))
        XCTAssertTrue(source.contains("title: \"重置时播放彩带\""))
        XCTAssertTrue(source.contains("title: \"播放彩带\""))
        XCTAssertTrue(source.contains(".playUsageResetConfettiPreview"))
        XCTAssertTrue(source.contains("title: \"语言\""))
        XCTAssertTrue(source.contains("if showsCustomColorControls"))
        XCTAssertFalse(source.contains("ForEach(detectedMenuBarWindows"))
        XCTAssertFalse(source.contains("windowVisibilityBinding(window)"))
        XCTAssertFalse(source.contains("title: \"菜单栏内容\""))
        XCTAssertFalse(source.contains("title: \"显示 Codex 图标\""))
        XCTAssertFalse(source.contains("case advanced"))
        XCTAssertFalse(source.contains("private var header:"))
        XCTAssertFalse(source.contains("SettingsInfoRow(title: \"缓存文件\""))

        let activityToggle = try XCTUnwrap(source.range(of: "title: \"显示活动指示\""))
        let activityStyle = try XCTUnwrap(source.range(of: "title: \"活动样式\""))
        XCTAssertLessThan(activityToggle.lowerBound, activityStyle.lowerBound)
        XCTAssertTrue(source.contains("Section {\n                MenuBarLayoutEditor("))
        XCTAssertFalse(source.contains("Section(AppLocalization.string(\"布局\"))"))
        XCTAssertTrue(source.contains("if showsHookActivityLight"))

        let sidebarStart = try XCTUnwrap(source.range(of: "private var sidebar: some View"))
        let sidebarEnd = try XCTUnwrap(source.range(of: "private var sidebarSelection"))
        let sidebarSource = source[sidebarStart.lowerBound..<sidebarEnd.lowerBound]
        XCTAssertTrue(sidebarSource.contains("Image(nsImage: settingsApplicationIcon)"))
        XCTAssertTrue(sidebarSource.contains("Text(AppVersionDisplay.text())"))
        XCTAssertTrue(sidebarSource.contains("selectedPane = .about"))

        let menuBarStart = try XCTUnwrap(source.range(of: "private var menuBarPane: some View"))
        let widgetStart = try XCTUnwrap(source.range(of: "private var widgetPane: some View"))
        let popoverStart = try XCTUnwrap(source.range(of: "private var popoverPane: some View"))
        let codexStart = try XCTUnwrap(source.range(of: "private var codexPane: some View"))
        let codexEnd = try XCTUnwrap(source.range(of: "private var currentAppBehaviorSettings"))
        let menuBarSource = source[menuBarStart.lowerBound..<widgetStart.lowerBound]
        let widgetSource = source[widgetStart.lowerBound..<popoverStart.lowerBound]
        let popoverSource = source[popoverStart.lowerBound..<codexStart.lowerBound]
        let codexSource = source[codexStart.lowerBound..<codexEnd.lowerBound]

        XCTAssertFalse(menuBarSource.contains("title: \"工作日刻度线\""))
        XCTAssertFalse(menuBarSource.contains("title: \"恢复菜单栏默认\""))
        XCTAssertFalse(widgetSource.contains("title: \"恢复小组件默认\""))
        XCTAssertFalse(popoverSource.contains("title: \"恢复下拉面板默认\""))
        XCTAssertTrue(popoverSource.contains("title: \"工作日刻度线\""))
        XCTAssertTrue(popoverSource.contains("Text(AppLocalization.string(\"无\")).tag(0)"))
        XCTAssertTrue(codexSource.contains("Section(AppLocalization.string(\"连接\"))"))
        XCTAssertTrue(codexSource.contains("DisclosureGroup(AppLocalization.string(\"诊断与维护\")"))
        XCTAssertFalse(codexSource.contains("Section(\"目录\")"))
        XCTAssertFalse(codexSource.contains("Section(\"用量计算\")"))
        XCTAssertFalse(codexSource.contains("title: \"恢复菜单栏默认\""))
        XCTAssertFalse(codexSource.contains("title: \"恢复小组件默认\""))

        let customColors = try XCTUnwrap(source.range(of: "if showsCustomColorControls"))
        let moreOptions = try XCTUnwrap(source.range(of: "DisclosureGroup(AppLocalization.string(\"更多选项\")"))
        XCTAssertLessThan(customColors.lowerBound, moreOptions.lowerBound)
        XCTAssertFalse(codexSource.contains("title: \"恢复下拉面板默认\""))
    }

    /// 验证通知事件只在额度向下跨过阈值时触发，并优先把耗尽归为更明确的事件。
    func testUsageNotificationEventsTriggerOnlyWhenCrossingDownward() {
        let settings = UsageNotificationSettings(
            notifiesWhenDepleted: true,
            notifiesWhenLow: true,
            lowRemainingThreshold: 10
        )
        let previous = RateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: RateLimitWindow(usedPercent: 80, windowDurationMins: 300, resetsAt: 2_000),
            secondary: RateLimitWindow(usedPercent: 85, windowDurationMins: 10_080, resetsAt: 3_000),
            credits: nil,
            planType: nil,
            rateLimitReachedType: nil
        )
        let current = RateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: RateLimitWindow(usedPercent: 90, windowDurationMins: 300, resetsAt: 2_000),
            secondary: RateLimitWindow(usedPercent: 100, windowDurationMins: 10_080, resetsAt: 3_000),
            credits: nil,
            planType: nil,
            rateLimitReachedType: nil
        )

        XCTAssertEqual(
            UsageNotificationEventResolver.events(previous: previous, current: current, settings: settings),
            [
                .lowRemaining(windowTitle: "5 小时", remainingText: "10%"),
                .depleted(windowTitle: "7 天")
            ]
        )
        XCTAssertTrue(
            UsageNotificationEventResolver.events(previous: current, current: previous, settings: settings).isEmpty
        )
    }

    /// 验证检测基线可跨进程恢复，并且瞬时零用量不会吞掉随后确认的周重置。
    func testUsageResetCelebrationPersistsBaselineUntilBoundaryAdvances() {
        let suiteName = "UsageViewModelTests.ResetCelebration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let previous = RateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: RateLimitWindow(usedPercent: 62, windowDurationMins: 10_080, resetsAt: 2_000),
            secondary: nil,
            credits: nil,
            planType: nil,
            rateLimitReachedType: nil
        )
        let transientDrop = RateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: RateLimitWindow(usedPercent: 0, windowDurationMins: 10_080, resetsAt: 2_000),
            secondary: nil,
            credits: nil,
            planType: nil,
            rateLimitReachedType: nil
        )
        let reset = RateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: RateLimitWindow(usedPercent: 1, windowDurationMins: 10_080, resetsAt: 4_000),
            secondary: nil,
            credits: nil,
            planType: nil,
            rateLimitReachedType: nil
        )

        var detector = UsageResetCelebrationDetector(defaults: defaults)
        XCTAssertFalse(detector.process(previous, option: .weekly))
        detector = UsageResetCelebrationDetector(defaults: defaults)
        XCTAssertFalse(detector.process(transientDrop, option: .weekly))
        detector = UsageResetCelebrationDetector(defaults: defaults)
        XCTAssertTrue(detector.process(reset, option: .weekly))
        XCTAssertFalse(detector.process(reset, option: .weekly))
    }

    /// 验证语言偏好能覆盖下一次启动使用的 AppleLanguages，并能恢复跟随系统。
    func testAppLanguageAppliesAndClearsLaunchOverride() {
        let suiteName = "UsageViewModelTests.AppLanguage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppLanguage.english.apply(to: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["en"])
        defaults.set(AppLanguage.english.rawValue, forKey: AppLanguagePreferenceKeys.selectedLanguage)
        XCTAssertEqual(AppLocalization.string("通用", defaults: defaults), "General")

        AppLanguage.system.apply(to: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"])
        XCTAssertEqual(AppLocalization.string("通用", language: .english), "General")
        XCTAssertEqual(AppLocalization.string("正常", language: .english), "Normal")
        XCTAssertEqual(AppLocalization.string("CodexMeter 设置", language: .english), "CodexMeter Settings")
        XCTAssertEqual(AppLocalization.string("通用", language: .chineseSimplified), "通用")
    }

    /// 验证设置窗口提供独立“关于”页面，并在其中承载自动更新、手动检查与项目链接。
    func testSettingsIncludesAboutAndUpdateControls() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = projectRoot.appendingPathComponent("CodexMeter/SettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("case about"))
        XCTAssertTrue(source.contains("title: \"自动检查更新\""))
        XCTAssertTrue(source.contains("CheckForUpdatesView(updater: updater)"))
        XCTAssertTrue(source.contains("https://github.com/jinsihou19/CodexMeter"))

        let aboutStart = try XCTUnwrap(source.range(of: "private var aboutPane: some View"))
        let aboutEnd = try XCTUnwrap(source.range(of: "private var automaticallyChecksForUpdatesBinding"))
        let aboutSource = source[aboutStart.lowerBound..<aboutEnd.lowerBound]
        XCTAssertTrue(aboutSource.contains("ScrollView"))
        XCTAssertTrue(aboutSource.contains("SettingsToggleRow("))
        XCTAssertTrue(aboutSource.contains("subtitle: \"\""))
        XCTAssertFalse(aboutSource.contains("subtitle: automaticUpdateHelpText"))
        XCTAssertFalse(aboutSource.contains("Form {"))
    }

    /// 验证更新委托和通知查询不依赖 Swift 6.2 或新 SDK 的并发标注。
    func testConcurrencyBridgesRemainCompatibleWithXcode16() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsSource = try String(
            contentsOf: projectRoot.appendingPathComponent("CodexMeter/SettingsView.swift"),
            encoding: .utf8
        )
        let usageSource = try String(
            contentsOf: projectRoot.appendingPathComponent("CodexMeter/UsageViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settingsSource.contains("@preconcurrency SPUStandardUserDriverDelegate"))
        XCTAssertFalse(settingsSource.contains("@MainActor SPUStandardUserDriverDelegate"))
        XCTAssertTrue(usageSource.contains("center.getNotificationSettings"))
        XCTAssertTrue(usageSource.contains("@preconcurrency import UserNotifications"))
        XCTAssertFalse(usageSource.contains("await center.notificationSettings()"))
    }

    /// 验证发现新版后，下拉面板底部提供更新按钮，用户主动点击才唤起更新界面。
    func testMenuBarFooterIncludesDeferredUpdateButton() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("CodexMeter/MenuBarView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("if updater.isUpdateAvailable"))
        XCTAssertTrue(source.contains("updater.showAvailableUpdate()"))
        XCTAssertTrue(source.contains("Label(AppLocalization.string(\"更新\")"))
    }

    /// 验证本机看板重排项目与任务，并只保留三种口径的可悬停热力图。
    func testLocalUsageDashboardIncludesInteractivePages() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("CodexMeter/MenuBarView.swift"),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: projectRoot.appendingPathComponent("CodexMeter/SettingsView.swift"),
            encoding: .utf8
        )
        let appSource = try String(
            contentsOf: projectRoot.appendingPathComponent("CodexMeter/CodexMeterApp.swift"),
            encoding: .utf8
        )
        let widgetSource = try String(
            contentsOf: projectRoot.appendingPathComponent("CodexMeterWidget/CodexMeterWidget.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("SectionTitle(\"额度与用量\")"))
        XCTAssertTrue(source.contains("Label(AppLocalization.string(\"消耗与成本\"), systemImage: \"dollarsign.circle\")"))
        XCTAssertFalse(source.contains("Label(AppLocalization.string(\"本机\"), systemImage: \"internaldrive\")"))
        XCTAssertTrue(source.contains("Text(\"\\(AppLocalization.string(\"成本\")) \\(Self.currency(estimatedCostUSD))\")"))
        XCTAssertTrue(source.contains("estimatedCostUSD: estimatedCost(for: week)"))
        XCTAssertFalse(source.contains("LocalUsageDashboardPage"))
        XCTAssertTrue(source.contains("ForEach(LocalUsageHeatmapMode.allCases)"))
        XCTAssertTrue(source.contains("private struct LocalMenuUsageHeatmap"))
        XCTAssertFalse(source.contains("private struct LocalUsageTrendChart"))
        XCTAssertTrue(source.contains("let rowCount = 7"))
        XCTAssertTrue(source.contains(".fill(CodexMeterChartPalette.heatmapColor(value: colorBucket?.tokens ?? 0, maximum: maximum))"))
        XCTAssertTrue(source.contains("return column.map { $0 == nil ? nil : aggregate }"))
        XCTAssertTrue(source.contains(".onContinuousHover { phase in"))
        XCTAssertTrue(source.contains("projectRanking(maximum: maximum)"))
        XCTAssertTrue(source.contains("ForEach(Array(snapshot.taskBoard.items.prefix(6)))"))
        XCTAssertTrue(source.contains("Text(item.title)"))
        XCTAssertTrue(source.contains(".onHover { isInside in"))
        let diagnosticsGroup = try XCTUnwrap(
            settingsSource.range(of: "DisclosureGroup(AppLocalization.string(\"诊断与维护\"))")
        )
        let logAction = try XCTUnwrap(settingsSource.range(of: "openAppDiagnosticLog()"))
        XCTAssertLessThan(diagnosticsGroup.lowerBound, logAction.lowerBound)
        XCTAssertFalse(settingsSource.contains("Section(AppLocalization.string(\"诊断日志\"))"))
        XCTAssertTrue(appSource.contains("Task { await viewModel.refreshLocalCodexUsage() }"))
        XCTAssertTrue(widgetSource.contains("formatter.fetchedAt(usage.fetchedAt)"))
        XCTAssertTrue(widgetSource.contains("let time = formatter.fetchedAt(snapshot.fetchedAt)"))
        XCTAssertFalse(widgetSource.contains("snapshot.localCodexUsage?.fetchedAt ?? snapshot.fetchedAt"))
    }

    func testSettingsWindowPresenterCreatesAndReusesSettingsWindow() {
        var createdWindowCount = 0
        let presenter = SettingsWindowPresenter(
            makeContentViewController: {
                createdWindowCount += 1
                return NSViewController()
            },
            prepareApplicationForWindow: {},
            activateApplication: {}
        )

        let firstWindow = presenter.show()
        let secondWindow = presenter.show()
        defer {
            firstWindow.close()
        }

        XCTAssertIdentical(firstWindow, secondWindow)
        XCTAssertEqual(createdWindowCount, 1)
        XCTAssertTrue(firstWindow.isVisible)
        XCTAssertFalse(firstWindow.isReleasedWhenClosed)
    }

    func testSettingsWindowUsesExpandedResizableContentSize() {
        let presenter = SettingsWindowPresenter(
            makeContentViewController: {
                NSViewController()
            },
            prepareApplicationForWindow: {},
            activateApplication: {}
        )

        let window = presenter.show()
        defer {
            window.close()
        }

        XCTAssertGreaterThanOrEqual(window.frame.width, 760)
        XCTAssertGreaterThanOrEqual(window.frame.height, 540)
        XCTAssertTrue(window.styleMask.contains(.resizable))
    }

    func testSettingsWindowPresenterUnhidesBeforeActivatingApplication() {
        var events: [String] = []
        let presenter = SettingsWindowPresenter(
            makeContentViewController: {
                NSViewController()
            },
            prepareApplicationForWindow: {
                events.append("unhide")
            },
            activateApplication: {
                events.append("activate")
            }
        )

        let window = presenter.show()
        defer {
            window.close()
        }

        XCTAssertEqual(events, ["unhide", "activate"])
    }

    /// 验证设置页图标会遵循手动外观，并在自动模式下采用系统当前配色。
    func testSettingsAppearanceSelectsMatchingApplicationIcon() {
        XCTAssertEqual(SurfaceAppearanceMode.light.appIconResourceName(systemColorScheme: .dark), "SettingsAppIconLight")
        XCTAssertEqual(SurfaceAppearanceMode.dark.appIconResourceName(systemColorScheme: .light), "SettingsAppIconDark")
        XCTAssertEqual(SurfaceAppearanceMode.automatic.appIconResourceName(systemColorScheme: .dark), "SettingsAppIconDark")
        XCTAssertEqual(SurfaceAppearanceMode.automatic.appIconResourceName(systemColorScheme: .light), "SettingsAppIconLight")
    }

    func testSettingsWindowOpenerActivatesApplicationBeforeShowingSettings() async {
        var events: [String] = []
        let opener = SettingsWindowOpener(
            delayNanoseconds: 0,
            activateApplication: {
                events.append("activate")
            },
            showSettingsWindow: {
                events.append("showSettings")
            }
        )

        await opener.openAfterDelay()

        XCTAssertEqual(events, ["activate", "showSettings"])
    }

    func testSettingsWindowOpenerHandlesApplicationReopen() async {
        var showCount = 0
        let opener = SettingsWindowOpener(
            delayNanoseconds: 0,
            activateApplication: {},
            showSettingsWindow: {
                showCount += 1
            }
        )

        let shouldHandle = await opener.handleApplicationReopen()

        XCTAssertTrue(shouldHandle)
        XCTAssertEqual(showCount, 1)
    }

    func testLaunchAtLoginManagerRegistersAndUnregistersOnlyWhenStateChanges() throws {
        var status = SMAppService.Status.notRegistered
        var registerCount = 0
        var unregisterCount = 0
        let manager = LaunchAtLoginManager(
            statusProvider: { status },
            registerApp: {
                registerCount += 1
                status = .enabled
            },
            unregisterApp: {
                unregisterCount += 1
                status = .notRegistered
            }
        )

        try manager.setEnabled(true)
        try manager.setEnabled(true)
        try manager.setEnabled(false)

        XCTAssertEqual(registerCount, 1)
        XCTAssertEqual(unregisterCount, 1)
        XCTAssertFalse(manager.isEnabled)
    }

    func testAppBehaviorSettingsReadDefaultsAndInvalidRefreshCadence() {
        let suiteName = "CodexMeterTests.appBehavior.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(true, forKey: AppBehaviorPreferenceKeys.opensSettingsAtLaunch)
        defaults.set("bad-value", forKey: AppBehaviorPreferenceKeys.refreshCadence)

        let settings = AppBehaviorSettings(defaults: defaults)

        XCTAssertTrue(settings.opensSettingsAtLaunch)
        XCTAssertEqual(settings.refreshCadence, .seconds30)
        XCTAssertNil(UsageRefreshCadence.manual.intervalSeconds)
        XCTAssertEqual(UsageRefreshCadence.minutes5.intervalSeconds, 300)
    }

    func testWidgetAndPopoverSettingsNormalizeStoredValues() {
        let suiteName = "CodexMeterTests.displaySettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set("secondaryOnly", forKey: WidgetDisplayPreferenceKeys.contentMode)
        defaults.set("bad-appearance", forKey: SurfaceAppearancePreferenceKeys.appearanceMode)
        defaults.set(2.0, forKey: SurfaceAppearancePreferenceKeys.cardOpacity)
        defaults.set("bad-appearance", forKey: WidgetDisplayPreferenceKeys.appearanceMode)
        defaults.set(2.0, forKey: WidgetDisplayPreferenceKeys.cardOpacity)
        defaults.set(false, forKey: WidgetDisplayPreferenceKeys.showsResetTime)
        defaults.set(false, forKey: WidgetDisplayPreferenceKeys.showsPaceComparison)
        defaults.set(false, forKey: WidgetDisplayPreferenceKeys.showsLastSync)
        defaults.set(false, forKey: WidgetDisplayPreferenceKeys.showsPlanLabel)
        defaults.set("not-a-style", forKey: PopoverPreferenceKeys.resetTimeDisplayStyle)
        defaults.set(true, forKey: MenuBarPreferenceKeys.showsAdditionalLimits)
        defaults.set(false, forKey: PopoverPreferenceKeys.showsResetCredits)
        defaults.set(false, forKey: PopoverPreferenceKeys.showsLocalOverview)
        defaults.set(false, forKey: PopoverPreferenceKeys.showsLocalTrend)
        defaults.set(false, forKey: PopoverPreferenceKeys.showsLocalProjects)

        let widgetSettings = WidgetDisplaySettings(defaults: defaults)
        let surfaceSettings = SurfaceAppearanceSettings(defaults: defaults)
        let popoverSettings = PopoverDisplaySettings(defaults: defaults)

        XCTAssertEqual(widgetSettings.contentMode, .secondaryOnly)
        XCTAssertEqual(widgetSettings.appearanceMode, .automatic)
        XCTAssertEqual(widgetSettings.cardOpacity, WidgetDisplaySettings.cardOpacityRange.upperBound)
        XCTAssertEqual(surfaceSettings.appearanceMode, .automatic)
        XCTAssertEqual(surfaceSettings.cardOpacity, SurfaceAppearanceSettings.cardOpacityRange.upperBound)
        XCTAssertEqual(
            SurfaceAppearanceSettings(cardOpacity: 0.01).cardOpacity,
            SurfaceAppearanceSettings.cardOpacityRange.lowerBound
        )
        XCTAssertEqual(
            WidgetDisplaySettings(cardOpacity: 0.01).cardOpacity,
            WidgetDisplaySettings.cardOpacityRange.lowerBound
        )
        XCTAssertFalse(widgetSettings.showsResetTime)
        XCTAssertFalse(widgetSettings.showsPaceComparison)
        XCTAssertFalse(widgetSettings.showsLastSync)
        XCTAssertFalse(widgetSettings.showsPlanLabel)
        XCTAssertTrue(WidgetDisplaySettings().showsPaceComparison)
        XCTAssertEqual(popoverSettings.resetTimeDisplayStyle, .countdown)
        XCTAssertTrue(popoverSettings.showsAdditionalLimits)
        XCTAssertFalse(popoverSettings.showsResetCredits)
        XCTAssertFalse(popoverSettings.showsLocalOverview)
        XCTAssertFalse(popoverSettings.showsLocalTrend)
        XCTAssertFalse(popoverSettings.showsLocalProjects)
        XCTAssertFalse(popoverSettings.showsAnyLocalSection)
        XCTAssertTrue(PopoverDisplaySettings().showsResetCredits)
        XCTAssertFalse(PopoverDisplaySettings().showsTopInvocations)
        XCTAssertFalse(PopoverDisplaySettings().showsSyncDetails)
        XCTAssertFalse(PopoverDisplaySettings().showsLocalOverview)
        XCTAssertFalse(PopoverDisplaySettings().showsLocalTrend)
        XCTAssertFalse(PopoverDisplaySettings().showsLocalProjects)
        XCTAssertFalse(PopoverDisplaySettings().showsAnyLocalSection)
    }

    func testMenuBarDisplaySettingsDefaultToCompactReadableValues() {
        let settings = MenuBarDisplaySettings()

        XCTAssertEqual(settings.contentMode, .remainingWindows)
        XCTAssertEqual(settings.layoutDensity, .compact)
        XCTAssertEqual(settings.itemSpacing, 2)
        XCTAssertEqual(settings.rowSpacing, -1)
        XCTAssertEqual(settings.numberFontSize, 10)
        XCTAssertEqual(settings.numberFontWeight, .medium)
        XCTAssertEqual(settings.goodColorHex, "#1AB85C")
        XCTAssertEqual(settings.warningColorHex, "#F5931A")
        XCTAssertEqual(settings.dangerColorHex, "#F23838")
        XCTAssertFalse(settings.showsAdditionalLimits)
        XCTAssertFalse(settings.showsMenuBarIcon)
        XCTAssertTrue(settings.showsHookActivityLight)
        XCTAssertEqual(settings.hookActivityIndicatorStyle, .automatic)
        XCTAssertEqual(settings.statusItemWidth, 48)
        XCTAssertEqual(MenuBarDisplayPreset.matchingPreset(for: settings), .balanced)
    }

    func testPopoverFrameAlignsJustBelowStatusItemAnchor() {
        let popoverFrame = NSRect(x: 860, y: 410, width: 346, height: 479)
        let statusItemFrame = NSRect(x: 915, y: 952, width: 38, height: 22)

        let alignedFrame = MenuBarPopoverPositioning.alignedFrame(
            popoverFrame: popoverFrame,
            anchorScreenRect: statusItemFrame,
            verticalGap: 4
        )

        XCTAssertEqual(alignedFrame.maxY, statusItemFrame.minY - 4, accuracy: 0.001)
        XCTAssertEqual(alignedFrame.origin.x, popoverFrame.origin.x)
        XCTAssertEqual(alignedFrame.size, popoverFrame.size)
    }

    func testPopoverErrorMessageBelongsToScrollableContent() {
        XCTAssertEqual(MenuBarPopoverLayout.errorMessageRegion, .scrollContent)
    }

    func testDefaultCompactWidthFitsHundredPercentMenuBarLine() {
        let settings = MenuBarDisplaySettings()
        let font = NSFont.systemFont(ofSize: settings.numberFontSize, weight: .medium)
        let labelWidth = textWidth("5h", font: font)
        let valueWidth = textWidth("100%", font: font)
        let requiredWidth = ceil(labelWidth + settings.itemSpacing + valueWidth)

        XCTAssertGreaterThanOrEqual(settings.statusItemWidth, requiredWidth)
    }

    func testMenuBarDisplaySettingsReadFromUserDefaults() {
        let suiteName = "CodexMeterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(MenuBarLayoutDensity.normal.rawValue, forKey: MenuBarPreferenceKeys.layoutDensity)
        defaults.set(3.0, forKey: MenuBarPreferenceKeys.itemSpacing)
        defaults.set(1.0, forKey: MenuBarPreferenceKeys.rowSpacing)
        defaults.set(10.5, forKey: MenuBarPreferenceKeys.numberFontSize)
        defaults.set(MenuBarNumberFontWeight.regular.rawValue, forKey: MenuBarPreferenceKeys.numberFontWeight)
        defaults.set("#33aa77", forKey: MenuBarPreferenceKeys.goodColorHex)
        defaults.set("bad-value", forKey: MenuBarPreferenceKeys.warningColorHex)
        defaults.set("#CC2222", forKey: MenuBarPreferenceKeys.dangerColorHex)
        defaults.set(false, forKey: MenuBarPreferenceKeys.showsSecondaryWindow)
        defaults.set(false, forKey: MenuBarPreferenceKeys.showsPercentSymbol)
        defaults.set(true, forKey: MenuBarPreferenceKeys.showsAdditionalLimits)
        defaults.set(true, forKey: MenuBarPreferenceKeys.showsMenuBarIcon)
        defaults.set(false, forKey: MenuBarPreferenceKeys.showsHookActivityLight)
        defaults.set(HookActivityIndicatorStyle.signature.rawValue, forKey: MenuBarPreferenceKeys.hookActivityIndicatorStyle)

        let settings = MenuBarDisplaySettings(defaults: defaults)

        XCTAssertEqual(settings.layoutDensity, .normal)
        XCTAssertEqual(settings.itemSpacing, 3)
        XCTAssertEqual(settings.rowSpacing, 1)
        XCTAssertEqual(settings.numberFontSize, 10.5)
        XCTAssertEqual(settings.numberFontWeight, .regular)
        XCTAssertEqual(settings.goodColorHex, "#33AA77")
        XCTAssertEqual(settings.warningColorHex, "#F5931A")
        XCTAssertEqual(settings.dangerColorHex, "#CC2222")
        XCTAssertEqual(settings.statusItemWidth, 67)
        XCTAssertTrue(settings.showsPrimaryWindow)
        XCTAssertFalse(settings.showsSecondaryWindow)
        XCTAssertFalse(settings.showsPercentSymbol)
        XCTAssertTrue(settings.showsAdditionalLimits)
        XCTAssertTrue(settings.showsMenuBarIcon)
        XCTAssertFalse(settings.showsHookActivityLight)
        XCTAssertEqual(settings.hookActivityIndicatorStyle, .signature)
    }

    /// 验证 Antigravity 配置使用独立偏好，并在开启菜单栏展示后生成右侧两行摘要。
    func testGeminiModelsSettingsAddsIndependentMenuLine() {
        let suiteName = "CodexMeterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(true, forKey: GeminiModelsPreferenceKeys.isEnabled)
        defaults.set(GeminiModelOption.claudeAndGPTModels.rawValue, forKey: GeminiModelsPreferenceKeys.model)
        defaults.set(false, forKey: GeminiModelsPreferenceKeys.showsInPopover)
        defaults.set(true, forKey: GeminiModelsPreferenceKeys.showsInMenuBar)

        let geminiSettings = GeminiModelsSettings(defaults: defaults)
        let display = StatusLineDisplay.menuBarDisplay(
            snapshot: nil,
            settings: MenuBarDisplaySettings(),
            geminiSettings: geminiSettings
        )

        XCTAssertTrue(geminiSettings.isEnabled)
        XCTAssertEqual(geminiSettings.model, .claudeAndGPTModels)
        XCTAssertFalse(geminiSettings.showsInPopover)
        XCTAssertTrue(geminiSettings.showsInMenuBar)
        XCTAssertEqual(display.codexLines.count, 1)
        XCTAssertEqual(display.trailingGeminiLines.map(\.label), ["7d", "5h"])
        XCTAssertEqual(display.trailingGeminiLines.map(\.value), ["--", "--"])
    }

    /// 验证 Gemini 与 Claude/GPT 配额组的筛选不会把两个池混在一起。
    func testGeminiModelOptionMatchesQuotaGroups() {
        let geminiGroup = GeminiQuotaGroup(id: "gemini-models", title: "Gemini Models", windows: [])
        let claudeGroup = GeminiQuotaGroup(id: "claude-gpt-models", title: "Claude and GPT models", windows: [])

        XCTAssertTrue(GeminiModelOption.all.matches(group: geminiGroup))
        XCTAssertTrue(GeminiModelOption.all.matches(group: claudeGroup))
        XCTAssertTrue(GeminiModelOption.geminiModels.matches(group: geminiGroup))
        XCTAssertFalse(GeminiModelOption.geminiModels.matches(group: claudeGroup))
        XCTAssertFalse(GeminiModelOption.claudeAndGPTModels.matches(group: geminiGroup))
        XCTAssertTrue(GeminiModelOption.claudeAndGPTModels.matches(group: claudeGroup))
    }

    /// 验证 Antigravity 配额摘要能解析嵌套 remainingFraction、重置时间和账户套餐。
    func testGeminiQuotaSummaryParserReadsNestedRemainingAndIdentity() throws {
        let data = Data(#"""
        {
          "response": {
            "groups": [
              {
                "displayName": "Gemini Models",
                "buckets": [
                  {
                    "bucketId": "weekly",
                    "displayName": "Weekly Limit Remaining",
                    "remaining": { "remainingFraction": 0.75 },
                    "resetTime": "2026-08-20T12:00:00Z"
                  },
                  {
                    "bucketId": "five-hour",
                    "displayName": "Five Hour Limit Remaining",
                    "remainingFraction": 0.99
                  }
                ]
              }
            ]
          }
        }
        """#.utf8)

        let snapshot = try AntigravityGeminiResponseParser.parseQuotaSummary(
            data,
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
            source: .antigravityLocal
        )

        XCTAssertTrue(snapshot.hasUsableQuota)
        XCTAssertEqual(snapshot.groups.count, 1)
        XCTAssertEqual(snapshot.groups[0].id, "summary-0")
        XCTAssertEqual(snapshot.groups[0].windows.map(\.remainingPercent), [75, 99])
        XCTAssertEqual(snapshot.groups[0].windows[0].title, "Weekly Limit Remaining")
        XCTAssertNotNil(snapshot.groups[0].windows[0].resetsAt)

        let identity = AntigravityGeminiResponseParser.parseIdentity(Data(#"""
        {
          "userStatus": {
            "email": "pro@example.com",
            "userTier": { "preferredName": "Google AI Pro" }
          }
        }
        """#.utf8))
        XCTAssertEqual(identity.email, "pro@example.com")
        XCTAssertEqual(identity.plan, "Google AI Pro")
    }

    /// 验证 Antigravity 的标准周/五小时窗口能接入 Codex 共用的 Pace 计算输入。
    func testGeminiQuotaWindowAdaptsKnownPeriodsToRateLimitWindow() {
        let weekly = GeminiQuotaWindow(
            bucketId: "gemini-weekly",
            title: "Weekly Limit Remaining",
            remainingFraction: 0.42,
            resetsAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let fiveHour = GeminiQuotaWindow(
            bucketId: "gemini-5h",
            title: "Five Hour Limit Remaining",
            remainingFraction: 0.70
        )
        let unknown = GeminiQuotaWindow(
            bucketId: "custom",
            title: "Custom Limit Remaining",
            remainingFraction: 0.80
        )

        XCTAssertEqual(weekly.rateLimitWindow?.windowDurationMins, 10_080)
        XCTAssertEqual(weekly.rateLimitWindow?.remainingPercent, 42)
        XCTAssertEqual(weekly.rateLimitWindow?.resetsAt, 2_000_000_000)
        XCTAssertEqual(fiveHour.rateLimitWindow?.windowDurationMins, 300)
        XCTAssertNil(unknown.rateLimitWindow)
    }

    /// 验证 Antigravity 刷新结果独立合并进快照，并能驱动菜单栏右侧两行摘要显示真实比例。
    func testRefreshMergesGeminiSnapshotIntoUsageAndMenuLines() async throws {
        let geminiSnapshot = GeminiModelsSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
            source: .antigravityLocal,
            accountEmail: "pro@example.com",
            planName: "Google AI Pro",
            groups: [
                GeminiQuotaGroup(
                    id: "gemini-models",
                    title: "Gemini Models",
                    windows: [
                        GeminiQuotaWindow(
                            bucketId: "weekly",
                            title: "Weekly Limit Remaining",
                            remainingFraction: 0.42
                        )
                    ]
                )
            ]
        )
        let viewModel = UsageViewModel(
            client: StubRateLimitClient(snapshot: Self.emptyRateLimits()),
            store: UsageSnapshotStore(
                appGroupIdentifier: "",
                fallbackDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            reloadWidgetTimelines: {},
            refreshCadenceProvider: { .manual },
            geminiClient: StubGeminiClient(snapshot: geminiSnapshot),
            geminiSettingsProvider: {
                GeminiModelsSettings(
                    isEnabled: true,
                    model: .all,
                    showsInPopover: true,
                    showsInMenuBar: true
                )
            },
            localCodexUsageLoader: { nil }
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.snapshot?.geminiModels, geminiSnapshot)
        XCTAssertEqual(viewModel.geminiSnapshot, geminiSnapshot)
        let display = StatusLineDisplay.menuBarDisplay(
            viewModel: viewModel,
            settings: MenuBarDisplaySettings()
        )
        XCTAssertEqual(display.trailingGeminiLines.map(\.label), ["7d", "5h"])
        XCTAssertEqual(display.trailingGeminiLines.map(\.value), ["42%", "--"])
        XCTAssertEqual(display.trailingGeminiLines.first?.tone, .warning)
    }

    func testStatusBarWidthUsesPaceContentInsteadOfRemainingFallbackWhenIconShown() {
        let settings = MenuBarDisplaySettings(
            contentMode: .paceComparison,
            showsMenuBarIcon: true
        )
        let lines = [
            StatusLineDisplay(id: "pace-remaining", label: "", value: "49%", tone: .warning),
            StatusLineDisplay(id: "pace-delta", label: "", value: "-32%", tone: .good)
        ]

        let width = StatusBarDisplayMetrics.statusItemWidth(for: lines, settings: settings)
        let textWidth = lines
            .map { StatusBarDisplayMetrics.lineWidth(for: $0, settings: settings) }
            .max() ?? 0
        let expectedWidth = ceil(
            MenuBarDisplaySettings.menuBarIconWidth
                + MenuBarDisplaySettings.menuBarIconTextSpacing
                + textWidth
        )

        XCTAssertEqual(MenuBarDisplaySettings.menuBarIconTextSpacing, 2)
        XCTAssertEqual(width, expectedWidth, accuracy: 0.001)
        XCTAssertLessThan(width, settings.statusItemWidth)
    }

    /// 单行生成原生按钮标题，双行保留自定义排版。
    func testNativeStatusBarTitleOnlyHandlesSingleLine() {
        let singleLine = [StatusLineDisplay(id: "weekly", label: "7d", value: "97%", tone: .good)]
        let doubleLines = singleLine + [
            StatusLineDisplay(id: "session", label: "5h", value: "80%", tone: .good)
        ]

        XCTAssertEqual(NativeStatusBarTitle.text(for: singleLine), "7d 97%")
        XCTAssertNil(NativeStatusBarTitle.text(for: doubleLines))
        XCTAssertEqual(NativeStatusBarTitle.fontSize, 13)

        let attributedTitle = NativeStatusBarTitle.attributedText(
            for: singleLine[0],
            settings: MenuBarDisplaySettings(goodColorHex: "#12AB34"),
            font: NativeStatusBarTitle.font(settings: MenuBarDisplayPreset.balanced.settings)
        )
        XCTAssertEqual(attributedTitle.string, "7d 97%")
        XCTAssertEqual(
            attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            .labelColor
        )
        let valueColor = attributedTitle.attribute(
            .foregroundColor,
            at: attributedTitle.length - 1,
            effectiveRange: nil
        ) as? NSColor
        XCTAssertEqual(valueColor?.usingColorSpace(.sRGB)?.redComponent ?? 0, 18.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(valueColor?.usingColorSpace(.sRGB)?.greenComponent ?? 0, 171.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(valueColor?.usingColorSpace(.sRGB)?.blueComponent ?? 0, 52.0 / 255.0, accuracy: 0.001)

        let customSettings = MenuBarDisplaySettings(
            itemSpacing: 4,
            numberFontSize: 12,
            numberFontWeight: .semibold
        )
        let customFont = NativeStatusBarTitle.font(settings: customSettings)
        XCTAssertEqual(customFont.pointSize, 12)
        XCTAssertEqual(NativeStatusBarTitle.font(settings: MenuBarDisplayPreset.balanced.settings).pointSize, 13)
    }

    /// 验证从双行切到单行后保留系统自动宽度，不使用尚未布局完成的 cellSize 截断标题。
    func testNativeStatusBarKeepsVariableLengthAfterLineCountChanges() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("CodexMeter/CodexMeterApp.swift"),
            encoding: .utf8
        )
        let methodStart = try XCTUnwrap(source.range(of: "private func applyNativeStatusDisplay("))
        let methodEnd = try XCTUnwrap(
            source.range(of: "private func nativeStatusImage", range: methodStart.upperBound..<source.endIndex)
        )
        let methodSource = source[methodStart.lowerBound..<methodEnd.lowerBound]

        XCTAssertTrue(methodSource.contains("statusItem.length = NSStatusItem.variableLength"))
        XCTAssertFalse(methodSource.contains("statusItem.length = ceil"))
        XCTAssertFalse(methodSource.contains("cellSize.width"))
    }

    func testStatusBarWidthKeepsRemainingModeWiderThanPaceWhenLabelsAreShown() {
        let paceSettings = MenuBarDisplaySettings(
            contentMode: .paceComparison,
            showsMenuBarIcon: true
        )
        let remainingSettings = MenuBarDisplaySettings(
            contentMode: .remainingWindows,
            showsMenuBarIcon: true
        )
        let paceLines = [
            StatusLineDisplay(id: "pace-remaining", label: "", value: "49%", tone: .warning),
            StatusLineDisplay(id: "pace-delta", label: "", value: "-32%", tone: .good)
        ]
        let remainingLines = [
            StatusLineDisplay(id: "primary", label: "5h", value: "49%", tone: .warning),
            StatusLineDisplay(id: "secondary", label: "7d", value: "51%", tone: .warning)
        ]

        let paceWidth = StatusBarDisplayMetrics.statusItemWidth(for: paceLines, settings: paceSettings)
        let remainingWidth = StatusBarDisplayMetrics.statusItemWidth(for: remainingLines, settings: remainingSettings)

        XCTAssertGreaterThan(remainingWidth, paceWidth)
    }

    func testStatusBarWidthIncludesHookActivityIndicatorOnlyWhenVisible() {
        let settings = MenuBarDisplaySettings()
        let iconSettings = MenuBarDisplaySettings(showsMenuBarIcon: true)
        let lines = [
            StatusLineDisplay(id: "primary", label: "5h", value: "49%", tone: .warning),
            StatusLineDisplay(id: "secondary", label: "7d", value: "51%", tone: .warning)
        ]
        let snapshot = CodexHookActivitySnapshot(
            state: .running,
            sessionID: "session-1",
            turnID: "turn-1",
            eventName: "PreToolUse",
            toolName: "Bash",
            message: "准备运行 Bash",
            updatedAt: Date().timeIntervalSince1970
        )
        let activeDisplay = CodexHookActivityDisplay(snapshot: snapshot)
        let hiddenSettings = MenuBarDisplaySettings(showsHookActivityLight: false)

        let idleWidth = StatusBarDisplayMetrics.statusItemWidth(for: lines, settings: settings)
        let activeWidth = StatusBarDisplayMetrics.statusItemWidth(
            for: lines,
            settings: settings,
            activityDisplay: activeDisplay
        )
        let idleIconWidth = StatusBarDisplayMetrics.statusItemWidth(for: lines, settings: iconSettings)
        let activeIconWidth = StatusBarDisplayMetrics.statusItemWidth(
            for: lines,
            settings: iconSettings,
            activityDisplay: activeDisplay
        )
        let hiddenWidth = StatusBarDisplayMetrics.statusItemWidth(
            for: lines,
            settings: hiddenSettings,
            activityDisplay: activeDisplay
        )

        XCTAssertEqual(activeDisplay.statusItemWidth, 19)
        XCTAssertGreaterThan(activeWidth, idleWidth)
        XCTAssertEqual(
            activeIconWidth - idleIconWidth,
            activeDisplay.statusItemWidth - MenuBarDisplaySettings.menuBarIconStatusItemWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(hiddenWidth, idleWidth)
    }

    /// 验证活动图标迫使单行继续走 SwiftUI 时，宽度使用同一套单行字体而不会裁切末尾。
    func testSingleLineWithVisibleActivityUsesSwiftUITypographyWidth() {
        let settings = MenuBarDisplayPreset.balanced.settings
        let line = StatusLineDisplay(id: "weekly", label: "7d", value: "100%", tone: .good)
        let snapshot = CodexHookActivitySnapshot(
            state: .running,
            sessionID: "session-1",
            turnID: "turn-1",
            eventName: "PreToolUse",
            toolName: "Bash",
            message: "准备运行 Bash",
            updatedAt: Date().timeIntervalSince1970
        )
        let activityDisplay = CodexHookActivityDisplay(snapshot: snapshot)
        let textWidth = StatusBarDisplayMetrics.lineWidth(
            for: line,
            settings: settings,
            usesSingleLineTypography: true
        )

        XCTAssertEqual(
            StatusBarDisplayMetrics.statusItemWidth(
                for: [line],
                settings: settings,
                activityDisplay: activityDisplay
            ),
            ceil(activityDisplay.statusItemWidth + textWidth),
            accuracy: 0.001
        )
    }

    func testMenuBarDisplaySettingsDefaultInitializerIgnoresSharedDefaults() {
        let suiteName = "CodexMeterTests.shared.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(MenuBarLayoutDensity.normal.rawValue, forKey: MenuBarPreferenceKeys.layoutDensity)

        let defaultSettings = MenuBarDisplaySettings()
        let storedSettings = MenuBarDisplaySettings(defaults: defaults)

        XCTAssertEqual(defaultSettings.layoutDensity, .compact)
        XCTAssertEqual(storedSettings.layoutDensity, .normal)
    }

    /// 验证动态窗口选择支持 30 天时长，并始终拒绝隐藏最后一个已检测窗口。
    func testDynamicWindowVisibilityKeepsOneDetectedWindowVisible() {
        let available: Set<Int> = [300, 10_080, 43_200]
        var hidden: Set<Int> = []
        hidden = MenuBarDisplaySettings.updatingHiddenWindowDurationMins(
            hidden,
            duration: 300,
            isVisible: false,
            availableDurations: available
        )
        hidden = MenuBarDisplaySettings.updatingHiddenWindowDurationMins(
            hidden,
            duration: 10_080,
            isVisible: false,
            availableDurations: available
        )
        let refused = MenuBarDisplaySettings.updatingHiddenWindowDurationMins(
            hidden,
            duration: 43_200,
            isVisible: false,
            availableDurations: available
        )
        let settings = MenuBarDisplaySettings(hiddenWindowDurationMins: refused)

        XCTAssertEqual(refused, [300, 10_080])
        XCTAssertTrue(settings.showsQuotaWindow(
            RateLimitWindow(usedPercent: 0, windowDurationMins: 43_200, resetsAt: nil)
        ))
    }

    func testMenuBarDisplaySettingsMigratesStandardDefaultsToSharedDefaults() {
        let standardSuiteName = "CodexMeterTests.standard.\(UUID().uuidString)"
        let sharedSuiteName = "CodexMeterTests.shared.\(UUID().uuidString)"
        let standardDefaults = UserDefaults(suiteName: standardSuiteName)!
        let sharedDefaults = UserDefaults(suiteName: sharedSuiteName)!
        defer {
            standardDefaults.removePersistentDomain(forName: standardSuiteName)
            sharedDefaults.removePersistentDomain(forName: sharedSuiteName)
        }

        standardDefaults.set(MenuBarLayoutDensity.normal.rawValue, forKey: MenuBarPreferenceKeys.layoutDensity)
        standardDefaults.set("#00C853", forKey: MenuBarPreferenceKeys.goodColorHex)
        standardDefaults.set(false, forKey: MenuBarPreferenceKeys.showsSecondaryWindow)

        MenuBarDisplaySettings.migrateStandardDefaultsToSharedDefaults(
            standardDefaults: standardDefaults,
            sharedDefaults: sharedDefaults
        )

        XCTAssertEqual(sharedDefaults.string(forKey: MenuBarPreferenceKeys.layoutDensity), MenuBarLayoutDensity.normal.rawValue)
        XCTAssertEqual(sharedDefaults.string(forKey: MenuBarPreferenceKeys.goodColorHex), "#00C853")
        XCTAssertFalse(sharedDefaults.bool(forKey: MenuBarPreferenceKeys.showsSecondaryWindow))
    }

    func testMenuBarDisplaySettingsMigratesLegacyDefaultsToCurrentDefaults() {
        let suiteName = "CodexMeterTests.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(MenuBarContentMode.paceComparison.rawValue, forKey: MenuBarPreferenceKeys.contentMode)
        defaults.set(MenuBarLayoutDensity.compact.rawValue, forKey: MenuBarPreferenceKeys.layoutDensity)
        defaults.set(1.0, forKey: MenuBarPreferenceKeys.itemSpacing)
        defaults.set(-2.0, forKey: MenuBarPreferenceKeys.rowSpacing)
        defaults.set(9.0, forKey: MenuBarPreferenceKeys.numberFontSize)
        defaults.set(MenuBarNumberFontWeight.medium.rawValue, forKey: MenuBarPreferenceKeys.numberFontWeight)
        defaults.set(false, forKey: MenuBarPreferenceKeys.showsMenuBarIcon)

        MenuBarDisplaySettings.migrateLegacyDisplayDefaults(defaults: defaults)

        let settings = MenuBarDisplaySettings(defaults: defaults)
        XCTAssertEqual(settings.contentMode, .remainingWindows)
        XCTAssertEqual(settings.layoutDensity, .compact)
        XCTAssertEqual(settings.itemSpacing, 2)
        XCTAssertEqual(settings.rowSpacing, -1)
        XCTAssertEqual(settings.numberFontSize, 10)
        XCTAssertEqual(settings.numberFontWeight, .medium)
        XCTAssertFalse(settings.showsMenuBarIcon)
        XCTAssertTrue(settings.showsHookActivityLight)
        XCTAssertEqual(settings.hookActivityIndicatorStyle, .automatic)
        XCTAssertEqual(
            defaults.integer(forKey: MenuBarPreferenceKeys.displayDefaultsVersion),
            MenuBarDisplaySettings.currentDisplayDefaultsVersion
        )
    }

    /// 验证 v3 只迁移完整预设的字号，不覆盖用户手工调整的 11pt。
    func testMenuBarDisplaySettingsMigratesVersion3PresetFontWithoutChangingCustomFont() {
        let presetSuiteName = "CodexMeterTests.v3Preset.\(UUID().uuidString)"
        let customSuiteName = "CodexMeterTests.v3Custom.\(UUID().uuidString)"
        let presetDefaults = UserDefaults(suiteName: presetSuiteName)!
        let customDefaults = UserDefaults(suiteName: customSuiteName)!
        defer {
            presetDefaults.removePersistentDomain(forName: presetSuiteName)
            customDefaults.removePersistentDomain(forName: customSuiteName)
        }
        for defaults in [presetDefaults, customDefaults] {
            defaults.set(3, forKey: MenuBarPreferenceKeys.displayDefaultsVersion)
            defaults.set(MenuBarLayoutDensity.compact.rawValue, forKey: MenuBarPreferenceKeys.layoutDensity)
            defaults.set(11.0, forKey: MenuBarPreferenceKeys.numberFontSize)
            defaults.set(MenuBarNumberFontWeight.medium.rawValue, forKey: MenuBarPreferenceKeys.numberFontWeight)
            defaults.set(-1.0, forKey: MenuBarPreferenceKeys.rowSpacing)
        }
        presetDefaults.set(2.0, forKey: MenuBarPreferenceKeys.itemSpacing)
        customDefaults.set(4.0, forKey: MenuBarPreferenceKeys.itemSpacing)

        MenuBarDisplaySettings.migrateLegacyDisplayDefaults(defaults: presetDefaults)
        MenuBarDisplaySettings.migrateLegacyDisplayDefaults(defaults: customDefaults)

        XCTAssertEqual(presetDefaults.double(forKey: MenuBarPreferenceKeys.numberFontSize), 10)
        XCTAssertEqual(customDefaults.double(forKey: MenuBarPreferenceKeys.numberFontSize), 11)
    }

    func testMenuBarDisplaySettingsPostsImmediateChangeNotification() {
        let suiteName = "CodexMeterTests.shared.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let expectation = expectation(description: "menu bar display settings changed")
        let observer = NotificationCenter.default.addObserver(
            forName: .menuBarDisplaySettingsDidChange,
            object: defaults,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        MenuBarDisplaySettings.notifyDidChange(defaults: defaults)

        wait(for: [expectation], timeout: 1)
    }

    func testWidgetDisplayUsesMenuBarDisplaySettings() {
        let snapshot = UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(usedPercent: 45, windowDurationMins: 300, resetsAt: 1_779_949_290),
                secondary: RateLimitWindow(usedPercent: 45, windowDurationMins: 10_080, resetsAt: 1_780_392_047),
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            )
        )
        let settings = MenuBarDisplaySettings(
            warningColorHex: "#FFB000",
            showsSecondaryWindow: false,
            showsPercentSymbol: false
        )

        let display = CodexMeterWidgetDisplay(
            snapshot: snapshot,
            settings: settings,
            formatter: UsageFormatter(locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt),
            now: Date(timeIntervalSince1970: 1_779_940_000)
        )

        XCTAssertEqual(display.lines.map(\.title), ["5 小时"])
        XCTAssertEqual(display.lines.map(\.value), ["55"])
        XCTAssertEqual(display.lines.first?.resetText, "2 小时 34 分后")
        XCTAssertEqual(display.lines.first?.tone, .warning)
        XCTAssertEqual(settings.colorHex(for: display.lines.first?.tone ?? .unavailable), "#FFB000")

        let englishDisplay = CodexMeterWidgetDisplay(
            snapshot: snapshot,
            settings: settings,
            formatter: UsageFormatter(
                locale: Locale(identifier: "en_US_POSIX"),
                timeZone: .gmt,
                language: .english
            ),
            language: .english,
            now: Date(timeIntervalSince1970: 1_779_940_000)
        )
        XCTAssertEqual(englishDisplay.lines.map(\.title), ["5 Hours"])
        XCTAssertEqual(englishDisplay.lines.first?.resetText, "in 2h 34m")
    }

    func testWidgetDisplayCanOverrideMenuBarWindowSelectionAndHideResetTime() {
        let snapshot = UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(usedPercent: 45, windowDurationMins: 300, resetsAt: 1_779_949_290),
                secondary: RateLimitWindow(usedPercent: 12, windowDurationMins: 10_080, resetsAt: 1_780_392_047),
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            )
        )
        let menuBarSettings = MenuBarDisplaySettings(
            showsPrimaryWindow: true,
            showsSecondaryWindow: false
        )
        let widgetSettings = WidgetDisplaySettings(
            contentMode: .secondaryOnly,
            showsResetTime: false,
            showsPaceComparison: false,
            showsLastSync: false,
            showsPlanLabel: false
        )

        let display = CodexMeterWidgetDisplay(
            snapshot: snapshot,
            settings: menuBarSettings,
            widgetSettings: widgetSettings
        )

        XCTAssertEqual(display.lines.map(\.title), ["7 天"])
        XCTAssertEqual(display.lines.map(\.value), ["88%"])
        XCTAssertEqual(display.lines.map(\.resetText), [""])
        XCTAssertEqual(display.lines.map(\.paceStatusText), [""])
    }

    func testWidgetDisplayIncludesPaceComparisonForVisibleWindows() {
        let snapshot = UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(
                    usedPercent: 18,
                    windowDurationMins: 300,
                    resetsAt: nil,
                    resetAfterSeconds: 14_700
                ),
                secondary: RateLimitWindow(
                    usedPercent: 11,
                    windowDurationMins: 10_080,
                    resetsAt: nil,
                    resetAfterSeconds: 580_608
                ),
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            )
        )
        let display = CodexMeterWidgetDisplay(
            snapshot: snapshot,
            settings: MenuBarDisplaySettings(),
            widgetSettings: WidgetDisplaySettings(contentMode: .bothWindows),
            now: Date(timeIntervalSince1970: 1_779_940_000)
        )

        XCTAssertEqual(display.lines.map(\.title), ["5 小时", "7 天"])
        XCTAssertEqual(display.lines.map(\.value), ["82%", "89%"])
        XCTAssertEqual(display.lines.map(\.paceStatusText), ["节奏正常", "超额 5%"])
        XCTAssertEqual(display.lines.map(\.paceProjectionText), ["持续到重置", "预计 4天6小时后耗尽"])
        XCTAssertEqual(display.lines.map(\.paceTone), [.good, .warning])
    }

    func testMenuBarDisplayPresetAppliesReadableDefaults() {
        XCTAssertEqual(MenuBarDisplayPreset.compact.settings.numberFontSize, 10)
        XCTAssertEqual(MenuBarDisplayPreset.balanced.settings.numberFontSize, 10)
        let relaxed = MenuBarDisplayPreset.relaxed.settings

        XCTAssertEqual(relaxed.layoutDensity, .normal)
        XCTAssertGreaterThan(relaxed.statusItemWidth, MenuBarDisplaySettings().statusItemWidth)
        XCTAssertGreaterThan(relaxed.rowSpacing, MenuBarDisplaySettings().rowSpacing)
    }

    func testMenuBarDisplayPresetMatchesCurrentSettings() {
        XCTAssertEqual(MenuBarDisplayPreset.matchingPreset(for: MenuBarDisplayPreset.compact.settings), .compact)
        XCTAssertEqual(MenuBarDisplayPreset.matchingPreset(for: MenuBarDisplayPreset.balanced.settings), .balanced)
        XCTAssertEqual(MenuBarDisplayPreset.matchingPreset(for: MenuBarDisplayPreset.relaxed.settings), .relaxed)

        let custom = MenuBarDisplaySettings(
            layoutDensity: .normal,
            itemSpacing: 4,
            rowSpacing: 1,
            numberFontSize: 11,
            numberFontWeight: .regular
        )

        XCTAssertNil(MenuBarDisplayPreset.matchingPreset(for: custom))
    }

    /// 验证简化后的布局选择能映射现有预设，并把其他历史配置安全显示为自定义。
    func testMenuBarLayoutChoiceMapsExistingSettingsWithoutMigration() {
        XCTAssertEqual(MenuBarLayoutChoice.matching(settings: MenuBarDisplayPreset.compact.settings), .compact)
        XCTAssertEqual(MenuBarLayoutChoice.matching(settings: MenuBarDisplayPreset.balanced.settings), .standard)
        XCTAssertEqual(MenuBarLayoutChoice.matching(settings: MenuBarDisplayPreset.relaxed.settings), .custom)
        XCTAssertEqual(MenuBarLayoutChoice.compact.preset, .compact)
        XCTAssertEqual(MenuBarLayoutChoice.standard.preset, .balanced)
        XCTAssertNil(MenuBarLayoutChoice.custom.preset)
    }

    func testMenuBarColorPresetAppliesHighContrastColors() {
        let highContrast = MenuBarColorPreset.highContrast.colors

        XCTAssertEqual(highContrast.goodColorHex, "#00C853")
        XCTAssertEqual(highContrast.warningColorHex, "#FFB000")
        XCTAssertEqual(highContrast.dangerColorHex, "#FF3B30")
    }

    func testMenuBarColorPresetMatchesCurrentColors() {
        XCTAssertEqual(MenuBarColorPreset.matchingPreset(for: MenuBarColorPreset.standard.colors), .standard)
        XCTAssertEqual(MenuBarColorPreset.matchingPreset(for: MenuBarColorPreset.soft.colors), .soft)
        XCTAssertEqual(MenuBarColorPreset.matchingPreset(for: MenuBarColorPreset.highContrast.colors), .highContrast)
        XCTAssertNil(MenuBarColorPreset.matchingPreset(for: ("#111111", "#222222", "#333333")))
    }

    func testMenuBarDisplaySettingsDetectsDefaultValues() {
        XCTAssertTrue(MenuBarDisplaySettings().usesDefaultValues)

        XCTAssertFalse(
            MenuBarDisplaySettings(
                layoutDensity: .normal,
                itemSpacing: MenuBarDisplaySettings.defaultItemSpacing,
                rowSpacing: MenuBarDisplaySettings.defaultRowSpacing,
                numberFontSize: MenuBarDisplaySettings.defaultNumberFontSize,
                numberFontWeight: MenuBarDisplaySettings.defaultNumberFontWeight,
                showsHookActivityLight: false,
                hookActivityIndicatorStyle: .signature
            ).usesDefaultValues
        )
    }

    /// 验证设置窗口采用适合原生侧栏与分组表单的稳定尺寸。
    func testSettingsPanelLayoutUsesNativeWindowSizing() {
        XCTAssertEqual(SettingsPanelLayout.windowWidth, 880)
        XCTAssertEqual(SettingsPanelLayout.windowHeight, 620)
        XCTAssertEqual(SettingsPanelLayout.sidebarWidth, 190)
        XCTAssertEqual(SettingsPanelLayout.cardSpacing, 8)
    }

    func testCodexConfigurationInfoHidesAuthSnapshotAndRecentDetails() throws {
        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let authFile = codexHome.appendingPathComponent("auth.json")
        try """
        {"tokens":{"access_token":"secret-token-value"}}
        """.write(to: authFile, atomically: true, encoding: .utf8)
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = UsageSnapshotStore(appGroupIdentifier: "", fallbackDirectory: storeDirectory)

        let info = CodexConfigurationInfo.current(
            environment: ["CODEX_HOME": codexHome.path],
            store: store
        )

        XCTAssertEqual(info.endpoint, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(info.profileEndpoint, "https://chatgpt.com/backend-api/wham/profiles/me")
        XCTAssertEqual(info.codexHomePath, codexHome.path)
        XCTAssertTrue(info.authFileExists)
        XCTAssertEqual(info.displayRows.map(\.title), ["数据来源", "接口", "Profile", "CODEX_HOME", "登录信息"])
        let displayText = info.displayRows.map { "\($0.title) \($0.value)" }.joined(separator: "\n")
        XCTAssertFalse(displayText.contains("secret-token-value"))
        XCTAssertFalse(displayText.contains("auth.json"))
        XCTAssertFalse(displayText.contains(store.snapshotURL().path))
        XCTAssertFalse(displayText.contains("最近读取"))
        XCTAssertFalse(displayText.contains("App Group"))
    }

    /// 验证默认客户端类型时注入隔离存储，避免单元测试读取用户正在写入的真实快照。
    func testDefaultClientUsesDirectUsageClientOnly() {
        let viewModel = UsageViewModel(store: UsageSnapshotStore(
            appGroupIdentifier: "",
            fallbackDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        ))

        let client = Mirror(reflecting: viewModel).children.first { child in
            child.label == "client"
        }?.value

        XCTAssertTrue(client is DirectCodexUsageClient)
    }

    func testManualRefreshCadenceDoesNotStartBackgroundRefresh() async {
        let client = CountingRateLimitClient(snapshot: RateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: RateLimitWindow(usedPercent: 4, windowDurationMins: 300, resetsAt: nil),
            secondary: RateLimitWindow(usedPercent: 14, windowDurationMins: 10_080, resetsAt: nil),
            credits: nil,
            planType: nil,
            rateLimitReachedType: nil
        ))
        let viewModel = UsageViewModel(
            client: client,
            store: UsageSnapshotStore(
                appGroupIdentifier: "",
                fallbackDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            reloadWidgetTimelines: {},
            refreshCadenceProvider: { .manual }
        )

        viewModel.start()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(client.fetchCount, 0)

        await viewModel.refresh()

        XCTAssertEqual(client.fetchCount, 1)
    }

    /// 验证启动和弹窗同时请求时本机统计仅读一次，额度自动刷新不会再读 SQLite。
    func testAutomaticRefreshReadsLocalUsageOnlyOnceAtStartup() async {
        let localLoadCount = CallCounter()
        let client = CountingRateLimitClient(snapshot: Self.emptyRateLimits())
        let viewModel = UsageViewModel(
            client: client,
            store: UsageSnapshotStore(
                appGroupIdentifier: "",
                fallbackDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            reloadWidgetTimelines: {},
            refreshCadenceProvider: { .minutes5 },
            localCodexUsageLoader: {
                await localLoadCount.increment()
                try? await Task.sleep(nanoseconds: 50_000_000)
                return nil
            }
        )

        viewModel.start()
        async let popoverRefresh: Void = viewModel.refreshLocalCodexUsage()
        await popoverRefresh
        for _ in 0..<10 where client.fetchCount == 0 {
            await Task.yield()
        }

        let count = await localLoadCount.value
        XCTAssertEqual(client.fetchCount, 1)
        XCTAssertEqual(count, 1)
    }

    /// 验证重置卡开关快速关再开时，会按通知携带的状态触发一次强制刷新。
    func testResetCreditsToggleOffThenOnTriggersForcedRefresh() async {
        let visibility = LockedBoolean(true)
        let client = RecordingUsageSnapshotClient(snapshot: UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: nil,
                secondary: nil,
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            )
        ))
        let viewModel = UsageViewModel(
            client: client,
            store: UsageSnapshotStore(
                appGroupIdentifier: "",
                fallbackDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            reloadWidgetTimelines: {},
            refreshCadenceProvider: { .manual },
            resetCreditsVisibilityProvider: { visibility.value }
        )

        viewModel.start()
        NotificationCenter.default.post(
            name: .popoverDisplaySettingsDidChange,
            object: MenuBarDisplaySettings.sharedDefaults,
            userInfo: [PopoverPreferenceKeys.showsResetCredits: false]
        )
        NotificationCenter.default.post(
            name: .popoverDisplaySettingsDidChange,
            object: MenuBarDisplaySettings.sharedDefaults,
            userInfo: [PopoverPreferenceKeys.showsResetCredits: true]
        )
        for _ in 0..<10 where client.forceRefreshFlags.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(client.forceRefreshFlags, [true])
    }

    /// 验证重置卡打开通知连续到达且接口较慢时，也只触发一次强制刷新。
    func testDuplicateResetCreditsOnNotificationsOnlyForceRefreshOnce() async {
        let client = RecordingUsageSnapshotClient(
            snapshot: UsageSnapshot(
                fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
                rateLimits: RateLimitSnapshot(
                    limitId: "codex",
                    limitName: nil,
                    primary: nil,
                    secondary: nil,
                    credits: nil,
                    planType: nil,
                    rateLimitReachedType: nil
                )
            ),
            delayNanoseconds: 50_000_000
        )
        let viewModel = UsageViewModel(
            client: client,
            store: UsageSnapshotStore(
                appGroupIdentifier: "",
                fallbackDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            reloadWidgetTimelines: {},
            refreshCadenceProvider: { .manual },
            resetCreditsVisibilityProvider: { false }
        )

        viewModel.start()
        NotificationCenter.default.post(
            name: .popoverDisplaySettingsDidChange,
            object: MenuBarDisplaySettings.sharedDefaults,
            userInfo: [PopoverPreferenceKeys.showsResetCredits: true]
        )
        NotificationCenter.default.post(
            name: .popoverDisplaySettingsDidChange,
            object: MenuBarDisplaySettings.sharedDefaults,
            userInfo: [PopoverPreferenceKeys.showsResetCredits: true]
        )
        for _ in 0..<10 where client.forceRefreshFlags.isEmpty {
            await Task.yield()
        }
        try? await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(client.forceRefreshFlags, [true])
    }

    /// 验证重置卡开关保持开启时，普通设置变更不会额外强制刷新。
    func testResetCreditsToggleNotificationDoesNotRefreshWhenAlreadyOn() async {
        let client = RecordingUsageSnapshotClient(snapshot: UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: nil,
                secondary: nil,
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            )
        ))
        let viewModel = UsageViewModel(
            client: client,
            store: UsageSnapshotStore(
                appGroupIdentifier: "",
                fallbackDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            reloadWidgetTimelines: {},
            refreshCadenceProvider: { .manual },
            resetCreditsVisibilityProvider: { true }
        )

        viewModel.start()
        NotificationCenter.default.post(
            name: .popoverDisplaySettingsDidChange,
            object: MenuBarDisplaySettings.sharedDefaults
        )
        await Task.yield()

        XCTAssertEqual(client.forceRefreshFlags, [])
    }

    /// 验证打开下拉框时若当前快照没有重置卡，会主动绕过当天缓存补读一次。
    func testRefreshResetCreditsIfNeededForcesRefreshWhenVisibleSnapshotLacksCredits() async {
        let client = RecordingUsageSnapshotClient(snapshot: UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: nil,
                secondary: nil,
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            ),
            resetCredits: ResetCreditsSnapshot(availableCount: 2)
        ))
        let viewModel = UsageViewModel(
            client: client,
            store: UsageSnapshotStore(
                appGroupIdentifier: "",
                fallbackDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            reloadWidgetTimelines: {},
            refreshCadenceProvider: { .manual },
            resetCreditsVisibilityProvider: { true }
        )

        await viewModel.refreshResetCreditsIfNeeded()

        XCTAssertEqual(client.forceRefreshFlags, [true])
        XCTAssertEqual(viewModel.snapshot?.resetCredits?.availableCount, 2)
    }

    /// 验证本地缓存只有重置卡数量但没有到期明细时，打开下拉框会补读独立接口。
    func testRefreshResetCreditsIfNeededForcesRefreshWhenCachedCountLacksExpirationDetails() async throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = UsageSnapshotStore(appGroupIdentifier: "", fallbackDirectory: storeDirectory)
        try store.save(UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: nil,
                secondary: nil,
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            ),
            resetCredits: ResetCreditsSnapshot(availableCount: 1)
        ))
        let expiresAt = Date(timeIntervalSince1970: 1_782_554_400)
        let client = RecordingUsageSnapshotClient(snapshot: UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: nil,
                secondary: nil,
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            ),
            resetCredits: ResetCreditsSnapshot(
                availableCount: 1,
                credits: [ResetCreditSnapshot(grantedAt: nil, expiresAt: expiresAt, status: "available")]
            )
        ))
        let viewModel = UsageViewModel(
            client: client,
            store: store,
            reloadWidgetTimelines: {},
            refreshCadenceProvider: { .manual },
            resetCreditsVisibilityProvider: { true }
        )

        await viewModel.refreshResetCreditsIfNeeded()

        XCTAssertEqual(client.forceRefreshFlags, [true])
        XCTAssertEqual(viewModel.snapshot?.resetCredits?.credits.first?.expiresAt, expiresAt)
    }

    /// 验证用户手动刷新重置卡时，总是绕过当天缓存重新读取接口。
    func testRefreshResetCreditsAlwaysForcesResetCreditsRequest() async {
        let client = RecordingUsageSnapshotClient(snapshot: UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: nil,
                secondary: nil,
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            ),
            resetCredits: ResetCreditsSnapshot(availableCount: 3)
        ))
        let viewModel = UsageViewModel(
            client: client,
            store: UsageSnapshotStore(
                appGroupIdentifier: "",
                fallbackDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            reloadWidgetTimelines: {},
            refreshCadenceProvider: { .manual },
            resetCreditsVisibilityProvider: { true }
        )

        await viewModel.refreshResetCredits()

        XCTAssertEqual(client.forceRefreshFlags, [true])
        XCTAssertEqual(viewModel.snapshot?.resetCredits?.availableCount, 3)
    }

    /// 验证手动刷新模式下启动只读取本地缓存，也会主动刷新小组件时间线。
    func testStartReloadsWidgetTimelinesWhenCachedSnapshotExists() throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = UsageSnapshotStore(appGroupIdentifier: "", fallbackDirectory: storeDirectory)
        try store.save(UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(usedPercent: 4, windowDurationMins: 300, resetsAt: nil),
                secondary: RateLimitWindow(usedPercent: 14, windowDurationMins: 10_080, resetsAt: nil),
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            )
        ))
        var reloadCount = 0
        let viewModel = UsageViewModel(
            client: CountingRateLimitClient(snapshot: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: nil,
                secondary: nil,
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            )),
            store: store,
            reloadWidgetTimelines: {
                reloadCount += 1
            },
            refreshCadenceProvider: { .manual },
            localCodexUsageLoader: { nil }
        )

        viewModel.start()

        XCTAssertEqual(reloadCount, 1)
    }

    /// 验证启动时会独立发布本机统计，不需要触发网络额度刷新。
    func testStartPublishesLocalCodexUsageWithoutNetworkRefresh() async throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = UsageSnapshotStore(appGroupIdentifier: "", fallbackDirectory: storeDirectory)
        try store.save(UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_800_000),
            rateLimits: Self.emptyRateLimits()
        ))
        let client = CountingRateLimitClient(snapshot: Self.emptyRateLimits())
        let localSnapshot = Self.localUsageSnapshot()
        let viewModel = UsageViewModel(
            client: client,
            store: store,
            reloadWidgetTimelines: {},
            refreshCadenceProvider: { .manual },
            localCodexUsageLoader: { localSnapshot }
        )

        viewModel.start()
        for _ in 0..<10 where viewModel.snapshot?.localCodexUsage == nil {
            await Task.yield()
        }

        XCTAssertEqual(client.fetchCount, 0)
        XCTAssertEqual(viewModel.snapshot?.localCodexUsage?.todayTokens, 120)
        XCTAssertEqual(try store.load()?.localCodexUsage?.todayTokens, 120)
    }

    func testRefreshReloadsWidgetTimelinesAfterSavingSnapshot() async throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = UsageSnapshotStore(appGroupIdentifier: "", fallbackDirectory: storeDirectory)
        let client = StubRateLimitClient(
            snapshot: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(usedPercent: 4, windowDurationMins: 300, resetsAt: 1_779_967_655),
                secondary: RateLimitWindow(usedPercent: 14, windowDurationMins: 10_080, resetsAt: 1_780_392_048),
                credits: CreditsSnapshot(hasCredits: false, unlimited: false, balance: "0"),
                planType: "prolite",
                rateLimitReachedType: nil
            )
        )
        var reloadCount = 0
        let viewModel = UsageViewModel(
            client: client,
            store: store,
            reloadWidgetTimelines: {
                reloadCount += 1
            },
            localCodexUsageLoader: { nil }
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.menuBarTitle, "5h 96%\n7d 86%")
        XCTAssertEqual(viewModel.menuBarPrimaryTitle, "5h 96%")
        XCTAssertEqual(viewModel.menuBarSecondaryTitle, "7d 86%")
        XCTAssertEqual(viewModel.menuBarPrimaryLabel, "5h")
        XCTAssertEqual(viewModel.menuBarPrimaryValue, "96%")
        XCTAssertEqual(viewModel.menuBarSecondaryLabel, "7d")
        XCTAssertEqual(viewModel.menuBarSecondaryValue, "86%")
        XCTAssertEqual(viewModel.menuHeaderPrimaryText, "5 小时剩余 96%")
        XCTAssertEqual(viewModel.menuHeaderSecondaryText, "7 天剩余 86%")
        XCTAssertEqual(viewModel.menuBarPrimaryTone, .good)
        XCTAssertEqual(viewModel.menuBarSecondaryTone, .good)
        XCTAssertEqual(try store.load()?.rateLimits.limitId, "codex")
        XCTAssertEqual(reloadCount, 1)
    }

    /// 验证额度刷新会同时发布本机统计，并把无标题的汇总摘要保存给 Widget。
    func testRefreshPublishesAndSharesLocalCodexUsage() async throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = UsageSnapshotStore(appGroupIdentifier: "", fallbackDirectory: storeDirectory)
        let localSnapshot = Self.localUsageSnapshot()
        let viewModel = UsageViewModel(
            client: StubRateLimitClient(snapshot: Self.emptyRateLimits()),
            store: store,
            reloadWidgetTimelines: {},
            localCodexUsageLoader: { localSnapshot }
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.localCodexUsageFreshness, .current)
        XCTAssertEqual(viewModel.localCodexUsage?.summary.todayTokens, 120)
        XCTAssertEqual(viewModel.localCodexUsage?.taskBoard.items.first?.title, "仅内存任务")
        XCTAssertEqual(try store.load()?.localCodexUsage?.todayTokens, 120)
        let storedJSON = try String(contentsOf: store.snapshotURL(), encoding: .utf8)
        XCTAssertFalse(storedJSON.contains("仅内存任务"))
    }

    /// 验证本机用量高于云端时仍发布实际解析值，云端差异只用于诊断而不隐藏数据。
    func testRefreshPublishesLocalUsageWhenPublishedCloudDayIsLower() async throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = UsageSnapshotStore(appGroupIdentifier: "", fallbackDirectory: storeDirectory)
        let local = Self.localUsageSnapshot(dailyBucket: LocalCodexDailyUsageBucket(
            id: "2026-07-14",
            label: "07/14",
            tokens: 240
        ))
        let profile = CodexProfileStats(
            lifetimeTokens: nil,
            peakDailyTokens: nil,
            longestRunningTurnSeconds: nil,
            currentStreakDays: nil,
            longestStreakDays: nil,
            fastModeUsagePercentage: nil,
            mostUsedReasoningEffort: nil,
            mostUsedReasoningEffortPercentage: nil,
            totalThreads: nil,
            totalSkillsUsed: nil,
            uniqueSkillsUsed: nil,
            dailyUsageBuckets: [CodexTokenUsageBucket(startDate: "2026-07-14", tokens: 200)]
        )
        let client = RecordingUsageSnapshotClient(snapshot: UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_800_000),
            rateLimits: Self.emptyRateLimits(),
            profileStats: profile
        ))
        let viewModel = UsageViewModel(
            client: client,
            store: store,
            reloadWidgetTimelines: {},
            localCodexUsageLoader: { local }
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.localCodexUsage?.summary.dailyBuckets?.first?.tokens, 240)
        XCTAssertEqual(viewModel.snapshot?.localCodexUsage?.dailyBuckets?.first?.tokens, 240)
        XCTAssertEqual(try store.load()?.localCodexUsage?.dailyBuckets?.first?.tokens, 240)
    }

    /// 验证本机统计失败不会覆盖成功的网络快照或设置主错误信息。
    func testLocalCodexUsageFailureDoesNotAffectNetworkRefresh() async {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let viewModel = UsageViewModel(
            client: StubRateLimitClient(snapshot: Self.emptyRateLimits()),
            store: UsageSnapshotStore(appGroupIdentifier: "", fallbackDirectory: storeDirectory),
            reloadWidgetTimelines: {},
            localCodexUsageLoader: { nil }
        )

        await viewModel.refresh()

        XCTAssertNotNil(viewModel.snapshot)
        XCTAssertNil(viewModel.localCodexUsage)
        XCTAssertNil(viewModel.errorMessage)
    }

    /// 验证本机读取失败时继续展示并保存最近一次成功的统计。
    func testLocalCodexUsageFailureKeepsCachedLocalUsage() async throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = UsageSnapshotStore(appGroupIdentifier: "", fallbackDirectory: storeDirectory)
        try store.save(UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_800_000),
            rateLimits: Self.emptyRateLimits(),
            localCodexUsage: Self.localUsageSnapshot().summary
        ))
        let viewModel = UsageViewModel(
            client: StubRateLimitClient(snapshot: Self.emptyRateLimits()),
            store: store,
            reloadWidgetTimelines: {},
            localCodexUsageLoader: { nil }
        )

        XCTAssertEqual(viewModel.localCodexUsageFreshness, .cached)

        await viewModel.refreshLocalCodexUsage()

        XCTAssertEqual(viewModel.localCodexUsageFreshness, .failed)
        XCTAssertEqual(viewModel.localCodexUsage?.summary.todayTokens, 120)
        XCTAssertEqual(viewModel.localCodexUsage?.taskBoard.activeCount, 1)
        XCTAssertTrue(viewModel.localCodexUsage?.taskBoard.items.isEmpty == true)
        XCTAssertEqual(viewModel.snapshot?.localCodexUsage?.todayTokens, 120)
        XCTAssertEqual(try store.load()?.localCodexUsage?.todayTokens, 120)
    }

    /// 验证网络失败时仍会把本机统计合并到额度缓存并刷新本机 Widget。
    func testNetworkFailureStillPublishesLocalCodexUsage() async throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = UsageSnapshotStore(appGroupIdentifier: "", fallbackDirectory: storeDirectory)
        try store.save(UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_800_000),
            rateLimits: Self.emptyRateLimits()
        ))
        let localSnapshot = Self.localUsageSnapshot()
        var reloadCount = 0
        let viewModel = UsageViewModel(
            client: FailingRateLimitClient(),
            store: store,
            reloadWidgetTimelines: { reloadCount += 1 },
            localCodexUsageLoader: { localSnapshot }
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.localCodexUsage?.summary.todayTokens, 120)
        XCTAssertEqual(viewModel.snapshot?.localCodexUsage?.todayTokens, 120)
        XCTAssertEqual(try store.load()?.localCodexUsage?.todayTokens, 120)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(reloadCount, 1)
    }

    /// 构造不包含窗口数据的最小额度快照，供刷新协作测试复用。
    private static func emptyRateLimits() -> RateLimitSnapshot {
        RateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: nil,
            secondary: nil,
            credits: nil,
            planType: nil,
            rateLimitReachedType: nil
        )
    }

    /// 构造含任务标题的应用内快照，验证共享缓存只保存 summary。
    private static func localUsageSnapshot(
        dailyBucket: LocalCodexDailyUsageBucket? = nil
    ) -> LocalCodexUsageSnapshot {
        let task = LocalCodexTaskItem(
            id: "task",
            title: "仅内存任务",
            detail: nil,
            kind: .active,
            updatedAt: Date(timeIntervalSince1970: 1_800_000),
            tokens: 120
        )
        let summary = LocalCodexUsageSummary(
            fetchedAt: Date(timeIntervalSince1970: 1_800_000),
            todayTokens: 120,
            sevenDayTokens: 560,
            lifetimeTokens: 2_400,
            threadCount: 4,
            projects: [],
            taskCounts: LocalCodexTaskCounts(active: 1, pending: 0, scheduled: 0, done: 0),
            dailyBuckets: dailyBucket.map { [$0] }
        )
        return LocalCodexUsageSnapshot(summary: summary, taskBoard: LocalCodexTaskBoard(items: [task]))
    }

    func testMenuBarToneMovesTowardRedAsRemainingDrops() async {
        let viewModel = UsageViewModel(
            client: StubRateLimitClient(
                snapshot: RateLimitSnapshot(
                    limitId: "codex",
                    limitName: nil,
                    primary: RateLimitWindow(usedPercent: 82, windowDurationMins: 300, resetsAt: nil),
                    secondary: RateLimitWindow(usedPercent: 48, windowDurationMins: 10_080, resetsAt: nil),
                    credits: nil,
                    planType: nil,
                    rateLimitReachedType: nil
                )
            ),
            store: UsageSnapshotStore(appGroupIdentifier: "", fallbackDirectory: FileManager.default.temporaryDirectory),
            reloadWidgetTimelines: {}
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.menuBarPrimaryTone, .danger)
        XCTAssertEqual(viewModel.menuBarSecondaryTone, .warning)
    }

    func testMetricDisplayFormatsRemainingUsedAndDuration() {
        let display = UsageMetricDisplay(
            title: "5 小时",
            window: RateLimitWindow(usedPercent: 17.4, windowDurationMins: 300, resetsAt: nil)
        )

        XCTAssertEqual(display.remainingText, "83%")
        XCTAssertEqual(display.usedText, "已用 17%")
        XCTAssertEqual(display.windowDurationText, "窗口 5 小时")
    }

    func testMetricDisplayUsesPlaceholdersWithoutWindow() {
        let display = UsageMetricDisplay(title: "7 天", window: nil)

        XCTAssertEqual(display.remainingText, "--")
        XCTAssertEqual(display.usedText, "已用 --")
        XCTAssertEqual(display.windowDurationText, "窗口 --")
    }

    func testUsagePaceDisplayUsesPrimaryRemainingAndSecondaryPaceDelta() {
        let display = UsagePaceDisplay(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(usedPercent: 2, windowDurationMins: 300, resetsAt: 4_000),
                secondary: RateLimitWindow(usedPercent: 40, windowDurationMins: 100, resetsAt: 4_000),
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            ),
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(display?.valueText, "98% · -10%")
        XCTAssertEqual(display?.compactValueText, "98%·-10%")
        XCTAssertEqual(display?.detailText, "有余量 10% · 可持续到重置")
        XCTAssertEqual(display?.detailText(language: .english), "10% headroom · Lasts until reset")
        XCTAssertEqual(display?.tone, .good)
    }

    func testUsagePaceDisplayHidesWhenExpectedUsageIsTooEarlyInWindow() {
        let display = UsagePaceDisplay(
            percentWindow: RateLimitWindow(
                usedPercent: 10,
                windowDurationMins: 300,
                resetsAt: nil,
                resetAfterSeconds: 16_200
            ),
            paceWindow: RateLimitWindow(
                usedPercent: 6,
                windowDurationMins: 10_080,
                resetsAt: nil,
                resetAfterSeconds: 597_600
            )
        )

        XCTAssertNil(display)
    }

    func testPaceMenuFallsBackToRemainingLinesWhenWindowProgressIsTooEarly() async {
        let viewModel = UsageViewModel(
            client: StubRateLimitClient(
                snapshot: RateLimitSnapshot(
                    limitId: "codex",
                    limitName: nil,
                    primary: RateLimitWindow(
                        usedPercent: 10,
                        windowDurationMins: 300,
                        resetsAt: nil,
                        resetAfterSeconds: 16_200
                    ),
                    secondary: RateLimitWindow(
                        usedPercent: 6,
                        windowDurationMins: 10_080,
                        resetsAt: nil,
                        resetAfterSeconds: 597_600
                    ),
                    credits: nil,
                    planType: nil,
                    rateLimitReachedType: nil
                )
            ),
            store: UsageSnapshotStore(
                appGroupIdentifier: "",
                fallbackDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            reloadWidgetTimelines: {}
        )
        await viewModel.refresh()

        let lines = StatusLineDisplay.lines(
            snapshot: viewModel.snapshot,
            settings: MenuBarDisplaySettings(contentMode: .paceComparison),
            geminiSettings: GeminiModelsSettings()
        )

        XCTAssertEqual(lines.map(\.id), ["primary", "secondary"])
        XCTAssertEqual(lines.map(\.value), ["90%", "94%"])
    }

    /// 验证默认堆叠只是可编辑布局预设，移动项目后会自然变成自定义布局。
    func testMenuBarLayoutDefaultsToEditableStackedPreset() {
        let layout = MenuBarLayout.defaultStacked

        XCTAssertEqual(MenuBarLayoutPreset.matching(layout), .stacked)
        XCTAssertTrue(layout.containsIcon)
        XCTAssertEqual(
            layout.items,
            [
                [.icon],
                [.paceRemaining, .paceDelta],
                [.geminiIcon],
                [.geminiPaceRemaining, .geminiPaceDelta]
            ]
        )

        let moved = layout.moving(from: 1, inItem: 1, to: 0, inItem: 1)
        XCTAssertEqual(
            moved.items,
            [
                [.icon],
                [.paceDelta, .paceRemaining],
                [.geminiIcon],
                [.geminiPaceRemaining, .geminiPaceDelta]
            ]
        )
        XCTAssertEqual(MenuBarLayoutPreset.matching(moved), .custom)

        let reordered = layout.movingItem(from: 1, to: 0)
        XCTAssertEqual(
            reordered.items,
            [
                [.paceRemaining, .paceDelta],
                [.icon],
                [.geminiIcon],
                [.geminiPaceRemaining, .geminiPaceDelta]
            ]
        )
    }

    /// 验证垃圾桶删除整项、菜单删除内容和配置菜单拆分项目都保持布局约束。
    func testMenuBarLayoutSupportsItemRemovalAndDetaching() {
        let layout = MenuBarLayout(items: [
            [.icon],
            [.paceRemaining, .paceDelta],
            [.geminiIcon]
        ])

        XCTAssertEqual(
            layout.removingItem(at: 1).items,
            [[.icon], [.geminiIcon]]
        )
        XCTAssertEqual(
            layout.removing(at: 0, inItem: 1).items,
            [[.icon], [.paceDelta], [.geminiIcon]]
        )
        XCTAssertEqual(
            layout.detaching(at: 1, inItem: 1).items,
            [[.icon], [.paceRemaining], [.geminiIcon], [.paceDelta]]
        )

        let movedAcrossItems = layout.moving(from: 0, inItem: 1, to: 1, inItem: 2)
        XCTAssertEqual(
            movedAcrossItems.items,
            [[.icon], [.paceDelta], [.geminiIcon], [.paceRemaining]]
        )

        let stackAdded = MenuBarLayout(items: [[.icon]]).addingStack([.paceRemaining, .paceDelta])
        XCTAssertEqual(stackAdded.items, [[.icon], [.paceRemaining, .paceDelta]])
        XCTAssertEqual(
            MenuBarLayout(items: [[.icon]]).addingStack([.icon, .paceRemaining]).items,
            [[.icon]]
        )

        let emptyContainer = MenuBarLayout(items: [[.icon]]).addingEmptyContainer()
        XCTAssertEqual(emptyContainer.items, [[.icon], []])
        XCTAssertEqual(
            emptyContainer.replacingStackToken(.primary, at: 0, inItem: 1).items,
            [[.icon], [.primary, .stackPlaceholder]]
        )
        XCTAssertEqual(
            emptyContainer
                .replacingStackToken(.primary, at: 0, inItem: 1)
                .replacingStackToken(.paceDelta, at: 1, inItem: 1)
                .items,
            [[.icon], [.primary, .paceDelta]]
        )
        XCTAssertEqual(
            emptyContainer.replacingStackToken(.icon, at: 0, inItem: 1),
            emptyContainer
        )

        let configured = MenuBarLayout(items: [[.primary], []])
            .replacingStackToken(.primary, at: 0, inItem: 1)
        XCTAssertEqual(configured.items, [[.primary, .stackPlaceholder]])
    }

    /// 验证布局持久化会保持横向项目、去除重复额度项目，并强制图标独立。
    func testMenuBarLayoutStoreRoundTripsNormalizedLayout() {
        let suiteName = "CodexMeterTests.MenuBarLayout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let layout = MenuBarLayout(items: [
            [.icon, .primary, .primary, .separator],
            [.secondary, .paceDelta],
            [.paceDelta]
        ])
        MenuBarLayoutStore.save(layout, defaults: defaults)

        XCTAssertEqual(
            MenuBarLayoutStore.load(defaults: defaults).items,
            [
                [.icon],
                [.primary],
                [.secondary, .paceDelta],
                [.geminiIcon],
                [.geminiPaceRemaining, .geminiPaceDelta]
            ]
        )
    }

    /// 验证固定窗口项目按真实时长取值，避免接口交换 primary/secondary 后两个项目都显示 7d。
    func testMenuBarLayoutQuotaTokensUseActualWindowDuration() throws {
        let snapshot = UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(usedPercent: 48, windowDurationMins: 10_080, resetsAt: 1_780_392_047),
                secondary: RateLimitWindow(usedPercent: 12, windowDurationMins: 300, resetsAt: 1_779_949_290),
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            )
        )

        let settings = MenuBarDisplaySettings()
        let fiveHour = try XCTUnwrap(StatusLineDisplay.layoutLine(for: .primary, snapshot: snapshot, settings: settings))
        let weekly = try XCTUnwrap(StatusLineDisplay.layoutLine(for: .secondary, snapshot: snapshot, settings: settings))

        XCTAssertEqual(fiveHour.label, "5h")
        XCTAssertEqual(fiveHour.value, "88%")
        XCTAssertEqual(weekly.label, "7d")
        XCTAssertEqual(weekly.value, "52%")
    }

    /// 验证自定义布局能解析 Pace 的两条真实行，避免因 token 名称与展示行 ID 不同而被过滤。
    func testMenuBarLayoutPaceTokensResolveBothLines() throws {
        let now = Date(timeIntervalSince1970: 1_779_940_000)
        let snapshot = UsageSnapshot(
            fetchedAt: now,
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(
                    usedPercent: 40,
                    windowDurationMins: 300,
                    resetsAt: nil,
                    resetAfterSeconds: 9_000
                ),
                secondary: RateLimitWindow(
                    usedPercent: 20,
                    windowDurationMins: 10_080,
                    resetsAt: nil,
                    resetAfterSeconds: 500_000
                ),
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            )
        )

        let settings = MenuBarDisplaySettings()
        let remaining = try XCTUnwrap(
            StatusLineDisplay.layoutLine(for: .paceRemaining, snapshot: snapshot, settings: settings, now: now)
        )
        let delta = try XCTUnwrap(
            StatusLineDisplay.layoutLine(for: .paceDelta, snapshot: snapshot, settings: settings, now: now)
        )

        XCTAssertEqual(remaining.id, "pace-remaining")
        XCTAssertEqual(delta.id, "pace-delta")
        XCTAssertFalse(delta.value.isEmpty)
        XCTAssertTrue(delta.value.hasSuffix("%"))
    }

    /// 验证 Antigravity 的两个布局项目能解析真实内容，避免第二个提供商继续走固定尾部渲染。
    func testMenuBarLayoutGeminiTokensResolveBothLines() throws {
        let geminiSnapshot = GeminiModelsSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            source: .antigravityLocal,
            groups: [
                GeminiQuotaGroup(
                    id: "gemini-models",
                    title: "Gemini Models",
                    windows: [
                        GeminiQuotaWindow(
                            bucketId: "weekly",
                            title: "Weekly Limit Remaining",
                            remainingFraction: 0.30,
                            resetsAt: Date(timeIntervalSince1970: 1_800_000_000)
                        ),
                        GeminiQuotaWindow(
                            bucketId: "five-hour",
                            title: "Five Hour Limit Remaining",
                            remainingFraction: 0.80,
                            resetsAt: Date(timeIntervalSince1970: 1_800_000_000)
                        )
                    ]
                )
            ]
        )
        let settings = MenuBarDisplaySettings(contentMode: .remainingWindows)
        let geminiSettings = GeminiModelsSettings(
            isEnabled: true,
            model: .geminiModels,
            showsInPopover: true,
            showsInMenuBar: true
        )

        let weekly = try XCTUnwrap(
            StatusLineDisplay.layoutGeminiLine(
                for: .geminiSecondary,
                settings: settings,
                geminiSettings: geminiSettings,
                snapshot: geminiSnapshot
            )
        )
        let fiveHour = try XCTUnwrap(
            StatusLineDisplay.layoutGeminiLine(
                for: .geminiPrimary,
                settings: settings,
                geminiSettings: geminiSettings,
                snapshot: geminiSnapshot
            )
        )

        XCTAssertEqual(weekly.id, "gemini-secondary")
        XCTAssertEqual(weekly.value, "30%")
        XCTAssertEqual(fiveHour.id, "gemini-primary")
        XCTAssertEqual(fiveHour.value, "80%")
        XCTAssertEqual(
            [
                MenuBarLayoutToken.geminiIcon,
                .geminiPrimary,
                .geminiSecondary,
                .geminiPaceRemaining,
                .geminiPaceDelta
            ].map(\.title),
            ["图标", "5 小时", "7 天", "自动剩余", "预期偏差"]
        )
    }

    /// 验证关闭 Antigravity 后，自定义布局中的图标和所有配额项目都会从菜单栏消失。
    func testMenuBarLayoutDisplayRemovesGeminiTokensWhenDisabled() {
        let display = MenuBarLayoutDisplay(
            layout: MenuBarLayout(items: [
                [.icon],
                [.geminiIcon],
                [.geminiPrimary, .geminiPaceDelta]
            ]),
            snapshot: nil,
            settings: MenuBarDisplaySettings(),
            geminiSettings: GeminiModelsSettings(
                isEnabled: false,
                model: .all,
                showsInPopover: true,
                showsInMenuBar: true
            )
        )

        XCTAssertEqual(display.items, [[.icon]])
        XCTAssertTrue(display.trailingGeminiLines.isEmpty)
    }

    /// 验证自定义项目缺少实时数据时直接隐藏，不在菜单栏显示占位符。
    func testMenuBarLayoutDisplayHidesUnavailableItems() {
        let layout = MenuBarLayout(items: [[.icon], [.primary], [.paceRemaining, .paceDelta]])
        let display = MenuBarLayoutDisplay(
            layout: layout,
            snapshot: nil,
            settings: MenuBarDisplaySettings(),
            geminiSettings: GeminiModelsSettings()
        )

        XCTAssertEqual(display.items, [[.icon]])
        XCTAssertTrue(display.codexLines.isEmpty)
        XCTAssertTrue(display.trailingGeminiLines.isEmpty)
    }

    /// 验证只有 primary 周窗口时，菜单栏和跟随模式小组件仍按 7 天开关而不是返回顺序过滤。
    func testWindowVisibilityUsesDurationWhenWeeklyWindowIsPrimary() async throws {
        let viewModel = UsageViewModel(
            client: StubRateLimitClient(
                snapshot: RateLimitSnapshot(
                    limitId: "codex",
                    limitName: nil,
                    primary: RateLimitWindow(usedPercent: 48, windowDurationMins: 10_080, resetsAt: 2_000),
                    secondary: nil,
                    credits: nil,
                    planType: nil,
                    rateLimitReachedType: nil
                )
            ),
            store: UsageSnapshotStore(
                appGroupIdentifier: "",
                fallbackDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            ),
            reloadWidgetTimelines: {}
        )
        await viewModel.refresh()
        let snapshot = try XCTUnwrap(viewModel.snapshot)
        let weeklyOnly = MenuBarDisplaySettings(showsPrimaryWindow: false, showsSecondaryWindow: true)
        let sessionOnly = MenuBarDisplaySettings(showsPrimaryWindow: true, showsSecondaryWindow: false)

        XCTAssertEqual(
            StatusLineDisplay.lines(
                snapshot: snapshot,
                settings: weeklyOnly,
                geminiSettings: GeminiModelsSettings()
            ).map(\.label),
            ["7d"]
        )
        XCTAssertTrue(
            StatusLineDisplay.lines(
                snapshot: snapshot,
                settings: sessionOnly,
                geminiSettings: GeminiModelsSettings()
            ).isEmpty
        )
        XCTAssertEqual(CodexMeterWidgetDisplay(snapshot: snapshot, settings: weeklyOnly).lines.map(\.title), ["7 天"])
        XCTAssertTrue(CodexMeterWidgetDisplay(snapshot: snapshot, settings: sessionOnly).lines.isEmpty)
    }

    func testWindowPaceDisplaysIncludeFiveHourPaceAndHideEarlyWeeklyPace() {
        let displays = UsageWindowPaceDisplay.displays(
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(
                    usedPercent: 60,
                    windowDurationMins: 300,
                    resetsAt: nil,
                    resetAfterSeconds: 9_000
                ),
                secondary: RateLimitWindow(
                    usedPercent: 6,
                    windowDurationMins: 10_080,
                    resetsAt: nil,
                    resetAfterSeconds: 597_600
                ),
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            )
        )

        XCTAssertEqual(displays.map(\.id), ["primary"])
        XCTAssertEqual(displays.first?.title, "5 小时")
        XCTAssertEqual(displays.first?.display.valueText, "40% · +10%")
    }

    func testUsagePaceDisplayMarksFastUsageAsDeficit() {
        let display = UsagePaceDisplay(
            percentWindow: RateLimitWindow(usedPercent: 2, windowDurationMins: 300, resetsAt: 4_000),
            paceWindow: RateLimitWindow(
                usedPercent: 70,
                windowDurationMins: 100,
                resetsAt: 4_000
            ),
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(display?.valueText, "98% · +20%")
        XCTAssertEqual(display?.detailText, "用得偏快 20% · 预计 21分后用完")
        XCTAssertEqual(display?.tone, .danger)
    }

    func testUsagePaceDisplayUsesDepletedTextForImmediateExhaustion() {
        let display = UsagePaceDisplay(
            percentWindow: RateLimitWindow(usedPercent: 100, windowDurationMins: 300, resetsAt: 4_000),
            paceWindow: RateLimitWindow(
                usedPercent: 100,
                windowDurationMins: 100,
                resetsAt: 4_000
            ),
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(display?.valueText, "0% · +50%")
        XCTAssertEqual(display?.detailText, "用得偏快 50% · 额度已耗尽")
        XCTAssertEqual(display?.widgetProjectionText, "额度已耗尽")
    }

    /// 验证设置预览使用缓存中的 Antigravity 窗口，而不是把已存在的数据渲染成占位符。
    func testMenuBarDisplayRendersCachedAntigravityWindows() {
        let geminiSnapshot = GeminiModelsSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            source: .antigravityLocal,
            groups: [
                GeminiQuotaGroup(
                    id: "gemini-models",
                    title: "Gemini Models",
                    windows: [
                        GeminiQuotaWindow(
                            bucketId: "gemini-weekly",
                            title: "Weekly Limit Remaining",
                            remainingFraction: 0.78
                        ),
                        GeminiQuotaWindow(
                            bucketId: "gemini-5h",
                            title: "Five Hour Limit Remaining",
                            remainingFraction: 0.70
                        )
                    ]
                )
            ]
        )
        let display = StatusLineDisplay.menuBarDisplay(
            snapshot: UsageSnapshot(
                fetchedAt: geminiSnapshot.fetchedAt,
                rateLimits: Self.emptyRateLimits(),
                geminiModels: geminiSnapshot
            ),
            settings: MenuBarDisplaySettings(),
            geminiSettings: GeminiModelsSettings(
                isEnabled: true,
                showsInMenuBar: true
            ),
            geminiSnapshot: geminiSnapshot
        )

        XCTAssertEqual(display.trailingGeminiLines.map(\.label), ["7d", "5h"])
        XCTAssertEqual(display.trailingGeminiLines.map(\.value), ["78%", "70%"])
    }

    /// 验证 Antigravity 的预期消耗对比与 Codex 一样只输出一组两行数值。
    func testMenuBarDisplayUsesOneAntigravityPacePair() {
        let geminiSnapshot = GeminiModelsSnapshot(
            fetchedAt: Date(),
            source: .antigravityLocal,
            groups: [
                GeminiQuotaGroup(
                    id: "gemini-models",
                    title: "Gemini Models",
                    windows: [
                        GeminiQuotaWindow(
                            bucketId: "gemini-weekly",
                            title: "Weekly Limit Remaining",
                            remainingFraction: 0.78,
                            resetsAt: Date(timeIntervalSinceNow: 3_600)
                        ),
                        GeminiQuotaWindow(
                            bucketId: "gemini-5h",
                            title: "Five Hour Limit Remaining",
                            remainingFraction: 0.70,
                            resetsAt: Date(timeIntervalSinceNow: 3_600)
                        )
                    ]
                )
            ]
        )
        let display = StatusLineDisplay.menuBarDisplay(
            snapshot: UsageSnapshot(
                fetchedAt: geminiSnapshot.fetchedAt,
                rateLimits: Self.emptyRateLimits(),
                geminiModels: geminiSnapshot
            ),
            settings: MenuBarDisplaySettings(contentMode: .paceComparison),
            geminiSettings: GeminiModelsSettings(isEnabled: true, showsInMenuBar: true),
            geminiSnapshot: geminiSnapshot
        )

        XCTAssertEqual(display.trailingGeminiLines.count, 2)
        XCTAssertEqual(display.trailingGeminiLines.map(\.label), ["", ""])
        XCTAssertEqual(display.trailingGeminiLines.first?.value, "70%")
    }

    /// 验证 Antigravity 有 5 小时时，剩余百分比和预期消耗偏差都取 5h。
    func testMenuBarDisplayUsesFiveHourWindowForPace() {
        let now = Date()
        let geminiSnapshot = GeminiModelsSnapshot(
            fetchedAt: now,
            source: .antigravityLocal,
            groups: [
                GeminiQuotaGroup(
                    id: "gemini-models",
                    title: "Gemini Models",
                    windows: [
                        GeminiQuotaWindow(
                            bucketId: "gemini-weekly",
                            title: "Weekly Limit Remaining",
                            remainingFraction: 0.10,
                            resetsAt: now.addingTimeInterval(3_600)
                        ),
                        GeminiQuotaWindow(
                            bucketId: "gemini-5h",
                            title: "Five Hour Limit Remaining",
                            remainingFraction: 0.63,
                            resetsAt: now.addingTimeInterval(7_200)
                        )
                    ]
                ),
                GeminiQuotaGroup(
                    id: "claude-gpt-models",
                    title: "Claude and GPT models",
                    windows: [
                        GeminiQuotaWindow(
                            bucketId: "claude-weekly",
                            title: "Weekly Limit Remaining",
                            remainingFraction: 0.90,
                            resetsAt: now.addingTimeInterval(3_600)
                        )
                    ]
                )
            ]
        )
        let display = StatusLineDisplay.menuBarDisplay(
            snapshot: UsageSnapshot(
                fetchedAt: now,
                rateLimits: Self.emptyRateLimits(),
                geminiModels: geminiSnapshot
            ),
            settings: MenuBarDisplaySettings(contentMode: .paceComparison),
            geminiSettings: GeminiModelsSettings(isEnabled: true, showsInMenuBar: true),
            geminiSnapshot: geminiSnapshot
        )

        XCTAssertEqual(display.trailingGeminiLines.map(\.label), ["", ""])
        XCTAssertEqual(display.trailingGeminiLines.map(\.value), ["63%", "-23%"])
    }

    /// 验证 Antigravity 没有 5h 时，剩余百分比和预期消耗偏差回退到 7d。
    func testMenuBarDisplayFallsBackToWeeklyWindowForPace() {
        let now = Date()
        let geminiSnapshot = GeminiModelsSnapshot(
            fetchedAt: now,
            source: .antigravityLocal,
            groups: [
                GeminiQuotaGroup(
                    id: "gemini-models",
                    title: "Gemini Models",
                    windows: [
                        GeminiQuotaWindow(
                            bucketId: "gemini-weekly",
                            title: "Weekly Limit Remaining",
                            remainingFraction: 0.76,
                            resetsAt: now.addingTimeInterval(3 * 86_400)
                        )
                    ]
                )
            ]
        )
        let display = StatusLineDisplay.menuBarDisplay(
            snapshot: UsageSnapshot(
                fetchedAt: now,
                rateLimits: Self.emptyRateLimits(),
                geminiModels: geminiSnapshot
            ),
            settings: MenuBarDisplaySettings(
                contentMode: .paceComparison,
                weeklyProgressWorkDays: 7
            ),
            geminiSettings: GeminiModelsSettings(isEnabled: true, showsInMenuBar: true),
            geminiSnapshot: geminiSnapshot
        )

        XCTAssertEqual(display.trailingGeminiLines.map(\.value), ["76%", "-33%"])
    }

    /// Pace 缺少重置时间无法计算时，预览与真实菜单栏都应回退到实际可见窗口。
    func testStatusLinesFallBackToVisibleQuotaWhenPaceIsUnavailable() {
        let snapshot = UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: nil,
                secondary: RateLimitWindow(usedPercent: 2, windowDurationMins: 10_080, resetsAt: nil),
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            )
        )
        let settings = MenuBarDisplaySettings(contentMode: .paceComparison)

        XCTAssertEqual(
            StatusLineDisplay.lines(
                snapshot: snapshot,
                settings: settings,
                geminiSettings: GeminiModelsSettings()
            ),
            [StatusLineDisplay(id: "secondary", label: "7d", value: "98%", tone: .good)]
        )
    }
}

private final class LockedBoolean: @unchecked Sendable {
    private let lock = NSLock()
    private var protectedValue: Bool

    init(_ value: Bool) {
        self.protectedValue = value
    }

    var value: Bool {
        get {
            lock.withLock {
                protectedValue
            }
        }
        set {
            lock.withLock {
                protectedValue = newValue
            }
        }
    }
}

/// 串行记录异步闭包调用次数，避免并发测试直接捕获可变整数。
private actor CallCounter {
    private(set) var value = 0

    /// 记录一次调用。
    func increment() {
        value += 1
    }
}

private func textWidth(_ text: String, font: NSFont) -> CGFloat {
    (text as NSString).size(withAttributes: [.font: font]).width
}

private struct StubRateLimitClient: UsageRateLimitFetching {
    let snapshot: RateLimitSnapshot

    func fetchRateLimits() async throws -> RateLimitSnapshot {
        snapshot
    }
}

/// 用固定快照验证 Gemini 配额刷新与 UsageSnapshot 合并链路。
private struct StubGeminiClient: GeminiModelsUsageFetching {
    let snapshot: GeminiModelsSnapshot

    /// 返回预置 Gemini 快照，避免测试依赖本机 Antigravity 或 OAuth 状态。
    func fetchGeminiModels() async throws -> GeminiModelsSnapshot {
        snapshot
    }
}

/// 固定抛错的额度客户端，用于验证网络失败时的本机数据降级路径。
private struct FailingRateLimitClient: UsageRateLimitFetching {
    struct Failure: Error {}

    /// 模拟额度网络请求失败。
    func fetchRateLimits() async throws -> RateLimitSnapshot {
        throw Failure()
    }
}

private final class CountingRateLimitClient: UsageRateLimitFetching, @unchecked Sendable {
    private let snapshot: RateLimitSnapshot
    private let lock = NSLock()
    private var protectedFetchCount = 0

    init(snapshot: RateLimitSnapshot) {
        self.snapshot = snapshot
    }

    var fetchCount: Int {
        lock.withLock {
            protectedFetchCount
        }
    }

    func fetchRateLimits() async throws -> RateLimitSnapshot {
        lock.withLock {
            protectedFetchCount += 1
        }
        return snapshot
    }
}

private final class RecordingUsageSnapshotClient: UsageRateLimitFetching, @unchecked Sendable {
    private let snapshot: UsageSnapshot
    private let delayNanoseconds: UInt64
    private let lock = NSLock()
    private var protectedForceRefreshFlags: [Bool] = []

    init(snapshot: UsageSnapshot, delayNanoseconds: UInt64 = 0) {
        self.snapshot = snapshot
        self.delayNanoseconds = delayNanoseconds
    }

    var forceRefreshFlags: [Bool] {
        lock.withLock {
            protectedForceRefreshFlags
        }
    }

    func fetchRateLimits() async throws -> RateLimitSnapshot {
        snapshot.rateLimits
    }

    /// 记录调用方是否要求绕过重置卡每日缓存，避免测试依赖真实网络客户端。
    func fetchUsageSnapshot(forceRefreshResetCredits: Bool) async throws -> UsageSnapshot {
        lock.withLock {
            protectedForceRefreshFlags.append(forceRefreshResetCredits)
        }
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return snapshot
    }
}
