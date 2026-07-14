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

    /// 验证设置页使用七个稳定入口和原生分组控件，并把高级内容并入 Codex。
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
        XCTAssertFalse(source.contains("case advanced"))
        XCTAssertFalse(source.contains("private var header:"))
        XCTAssertFalse(source.contains("SettingsInfoRow(title: \"缓存文件\""))

        let activityToggle = try XCTUnwrap(source.range(of: "title: \"显示活动指示\""))
        let activityStyle = try XCTUnwrap(source.range(of: "title: \"活动样式\""))
        let layoutSection = try XCTUnwrap(source.range(of: "Section(AppLocalization.string(\"布局\"))"))
        XCTAssertLessThan(activityToggle.lowerBound, activityStyle.lowerBound)
        XCTAssertLessThan(activityStyle.lowerBound, layoutSection.lowerBound)
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

        XCTAssertTrue(menuBarSource.contains("if contentMode == MenuBarContentMode.paceComparison.rawValue"))
        XCTAssertTrue(menuBarSource.contains("title: \"工作日刻度线\""))
        XCTAssertFalse(menuBarSource.contains("title: \"恢复菜单栏默认\""))
        XCTAssertFalse(widgetSource.contains("title: \"恢复小组件默认\""))
        XCTAssertFalse(popoverSource.contains("title: \"恢复下拉面板默认\""))
        XCTAssertTrue(codexSource.contains("Section(AppLocalization.string(\"连接\"))"))
        XCTAssertTrue(codexSource.contains("DisclosureGroup(AppLocalization.string(\"诊断与维护\")"))
        XCTAssertFalse(codexSource.contains("Section(\"目录\")"))
        XCTAssertFalse(codexSource.contains("Section(\"用量计算\")"))
        XCTAssertFalse(codexSource.contains("title: \"恢复菜单栏默认\""))
        XCTAssertFalse(codexSource.contains("title: \"恢复小组件默认\""))
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
                .lowRemaining(windowTitle: "5 小时", remainingPercent: 10),
                .depleted(windowTitle: "7 天")
            ]
        )
        XCTAssertTrue(
            UsageNotificationEventResolver.events(previous: current, current: previous, settings: settings).isEmpty
        )
    }

    /// 验证彩带只在用量回落且重置边界前移时触发，并遵守短窗口与周窗口选项。
    func testUsageResetCelebrationRequiresBoundaryAdvance() {
        let previous = RateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: RateLimitWindow(usedPercent: 62, windowDurationMins: 300, resetsAt: 2_000),
            secondary: RateLimitWindow(usedPercent: 48, windowDurationMins: 10_080, resetsAt: 3_000),
            credits: nil,
            planType: nil,
            rateLimitReachedType: nil
        )
        let reset = RateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: RateLimitWindow(usedPercent: 1, windowDurationMins: 300, resetsAt: 4_000),
            secondary: RateLimitWindow(usedPercent: 48, windowDurationMins: 10_080, resetsAt: 3_000),
            credits: nil,
            planType: nil,
            rateLimitReachedType: nil
        )
        let transientDrop = RateLimitSnapshot(
            limitId: "codex",
            limitName: nil,
            primary: RateLimitWindow(usedPercent: 0, windowDurationMins: 300, resetsAt: 2_000),
            secondary: previous.secondary,
            credits: nil,
            planType: nil,
            rateLimitReachedType: nil
        )

        XCTAssertTrue(
            UsageResetCelebrationResolver.shouldCelebrate(previous: previous, current: reset, option: .session)
        )
        XCTAssertFalse(
            UsageResetCelebrationResolver.shouldCelebrate(previous: previous, current: reset, option: .weekly)
        )
        XCTAssertFalse(
            UsageResetCelebrationResolver.shouldCelebrate(previous: previous, current: transientDrop, option: .both)
        )
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
        XCTAssertTrue(PopoverDisplaySettings().showsResetCredits)
    }

    func testMenuBarDisplaySettingsDefaultToCompactReadableValues() {
        let settings = MenuBarDisplaySettings()

        XCTAssertEqual(settings.contentMode, .remainingWindows)
        XCTAssertEqual(settings.layoutDensity, .compact)
        XCTAssertEqual(settings.itemSpacing, 2)
        XCTAssertEqual(settings.rowSpacing, -1)
        XCTAssertEqual(settings.numberFontSize, 9.5)
        XCTAssertEqual(settings.numberFontWeight, .medium)
        XCTAssertEqual(settings.goodColorHex, "#1AB85C")
        XCTAssertEqual(settings.warningColorHex, "#F5931A")
        XCTAssertEqual(settings.dangerColorHex, "#F23838")
        XCTAssertFalse(settings.showsAdditionalLimits)
        XCTAssertFalse(settings.showsMenuBarIcon)
        XCTAssertTrue(settings.showsHookActivityLight)
        XCTAssertEqual(settings.hookActivityIndicatorStyle, .automatic)
        XCTAssertEqual(settings.statusItemWidth, 42)
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
        XCTAssertEqual(settings.statusItemWidth, 61)
        XCTAssertTrue(settings.showsPrimaryWindow)
        XCTAssertFalse(settings.showsSecondaryWindow)
        XCTAssertFalse(settings.showsPercentSymbol)
        XCTAssertTrue(settings.showsAdditionalLimits)
        XCTAssertTrue(settings.showsMenuBarIcon)
        XCTAssertFalse(settings.showsHookActivityLight)
        XCTAssertEqual(settings.hookActivityIndicatorStyle, .signature)
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
        XCTAssertEqual(settings.numberFontSize, 9.5)
        XCTAssertEqual(settings.numberFontWeight, .medium)
        XCTAssertFalse(settings.showsMenuBarIcon)
        XCTAssertTrue(settings.showsHookActivityLight)
        XCTAssertEqual(settings.hookActivityIndicatorStyle, .automatic)
        XCTAssertEqual(
            defaults.integer(forKey: MenuBarPreferenceKeys.displayDefaultsVersion),
            MenuBarDisplaySettings.currentDisplayDefaultsVersion
        )
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
        XCTAssertEqual(SettingsPanelLayout.previewChipVerticalPadding, 9)
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
            refreshCadenceProvider: { .manual }
        )

        viewModel.start()

        XCTAssertEqual(reloadCount, 1)
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
            }
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
            viewModel: viewModel,
            settings: MenuBarDisplaySettings(contentMode: .paceComparison)
        )

        XCTAssertEqual(lines.map(\.id), ["primary", "secondary"])
        XCTAssertEqual(lines.map(\.value), ["90%", "94%"])
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

    func testSettingsPreviewShowsRealMenuBarBackdrops() {
        XCTAssertEqual(MenuBarPreviewAppearance.allCases.map(\.title), ["浅色", "深色", "半透明"])
    }

    func testSettingsPreviewDataUsesSnapshotValuesAndTones() {
        let snapshot = UsageSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_779_940_000),
            rateLimits: RateLimitSnapshot(
                limitId: "codex",
                limitName: nil,
                primary: RateLimitWindow(usedPercent: 15, windowDurationMins: 300, resetsAt: nil),
                secondary: RateLimitWindow(usedPercent: 63, windowDurationMins: 10_080, resetsAt: nil),
                credits: nil,
                planType: nil,
                rateLimitReachedType: nil
            )
        )

        let previewData = SettingsPreviewData(snapshot: snapshot)

        XCTAssertEqual(previewData.primaryValue, "85%")
        XCTAssertEqual(previewData.secondaryValue, "37%")
        XCTAssertEqual(previewData.primaryTone, .good)
        XCTAssertEqual(previewData.secondaryTone, .danger)
        XCTAssertEqual(previewData.paceRemainingValue, "--")
        XCTAssertEqual(previewData.paceDeltaValue, "--")
        XCTAssertEqual(previewData.paceRemainingTone, .unavailable)
    }

    func testSettingsPreviewDataFallsBackToReadablePlaceholders() {
        let previewData = SettingsPreviewData(snapshot: nil)

        XCTAssertEqual(previewData.primaryValue, "--")
        XCTAssertEqual(previewData.secondaryValue, "--")
        XCTAssertEqual(previewData.primaryTone, .unavailable)
        XCTAssertEqual(previewData.secondaryTone, .unavailable)
        XCTAssertEqual(previewData.paceRemainingValue, "--")
        XCTAssertEqual(previewData.paceDeltaValue, "--")
        XCTAssertEqual(previewData.paceRemainingTone, .unavailable)
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

private func textWidth(_ text: String, font: NSFont) -> CGFloat {
    (text as NSString).size(withAttributes: [.font: font]).width
}

private struct StubRateLimitClient: UsageRateLimitFetching {
    let snapshot: RateLimitSnapshot

    func fetchRateLimits() async throws -> RateLimitSnapshot {
        snapshot
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
