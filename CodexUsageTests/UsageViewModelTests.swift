import AppKit
import XCTest
@testable import CodexUsageShared

@MainActor
final class UsageViewModelTests: XCTestCase {
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

    func testMenuBarDisplaySettingsDefaultToCompactReadableValues() {
        let settings = MenuBarDisplaySettings()

        XCTAssertEqual(settings.layoutDensity, .compact)
        XCTAssertEqual(settings.itemSpacing, 1)
        XCTAssertEqual(settings.rowSpacing, -2)
        XCTAssertEqual(settings.numberFontSize, 9)
        XCTAssertEqual(settings.numberFontWeight, .medium)
        XCTAssertEqual(settings.goodColorHex, "#1AB85C")
        XCTAssertEqual(settings.warningColorHex, "#F5931A")
        XCTAssertEqual(settings.dangerColorHex, "#F23838")
        XCTAssertEqual(settings.statusItemWidth, 38)
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

    func testDefaultCompactWidthFitsHundredPercentMenuBarLine() {
        let settings = MenuBarDisplaySettings()
        let font = NSFont.systemFont(ofSize: settings.numberFontSize, weight: .medium)
        let labelWidth = textWidth("5h", font: font)
        let valueWidth = textWidth("100%", font: font)
        let requiredWidth = ceil(labelWidth + settings.itemSpacing + valueWidth)

        XCTAssertGreaterThanOrEqual(settings.statusItemWidth, requiredWidth)
    }

    func testMenuBarDisplaySettingsReadFromUserDefaults() {
        let suiteName = "CodexUsageTests.\(UUID().uuidString)"
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

        let settings = MenuBarDisplaySettings(defaults: defaults)

        XCTAssertEqual(settings.layoutDensity, .normal)
        XCTAssertEqual(settings.itemSpacing, 3)
        XCTAssertEqual(settings.rowSpacing, 1)
        XCTAssertEqual(settings.numberFontSize, 10.5)
        XCTAssertEqual(settings.numberFontWeight, .regular)
        XCTAssertEqual(settings.goodColorHex, "#33AA77")
        XCTAssertEqual(settings.warningColorHex, "#F5931A")
        XCTAssertEqual(settings.dangerColorHex, "#CC2222")
        XCTAssertEqual(settings.statusItemWidth, 40)
        XCTAssertTrue(settings.showsPrimaryWindow)
        XCTAssertFalse(settings.showsSecondaryWindow)
        XCTAssertFalse(settings.showsPercentSymbol)
    }

    func testMenuBarDisplayPresetAppliesReadableDefaults() {
        let relaxed = MenuBarDisplayPreset.relaxed.settings

        XCTAssertEqual(relaxed.layoutDensity, .normal)
        XCTAssertGreaterThan(relaxed.statusItemWidth, MenuBarDisplaySettings().statusItemWidth)
        XCTAssertGreaterThan(relaxed.rowSpacing, MenuBarDisplaySettings().rowSpacing)
    }

    func testMenuBarColorPresetAppliesHighContrastColors() {
        let highContrast = MenuBarColorPreset.highContrast.colors

        XCTAssertEqual(highContrast.goodColorHex, "#00C853")
        XCTAssertEqual(highContrast.warningColorHex, "#FFB000")
        XCTAssertEqual(highContrast.dangerColorHex, "#FF3B30")
    }

    func testSettingsPanelLayoutUsesSingleAlignedColumn() {
        XCTAssertTrue(SettingsPanelLayout.usesSingleContentColumn)
        XCTAssertFalse(SettingsPanelLayout.usesTrailingFooterAction)
        XCTAssertEqual(SettingsPanelLayout.previewAppearanceColumns, 3)
        XCTAssertEqual(SettingsPanelLayout.displayPresetColumns, 3)
        XCTAssertEqual(SettingsPanelLayout.colorPresetColumns, 3)
        XCTAssertEqual(SettingsPanelLayout.sectionSpacing, 12)
        XCTAssertEqual(SettingsPanelLayout.sectionContentPadding, 12)
        XCTAssertEqual(SettingsPanelLayout.cardSpacing, 8)
        XCTAssertFalse(SettingsPanelLayout.previewUsesContentFrame)
        XCTAssertEqual(SettingsPanelLayout.previewChipVerticalPadding, 9)
        XCTAssertEqual(SettingsPanelLayout.presetCardMinimumHeight, 74)
        XCTAssertEqual(SettingsPanelLayout.contentMaxWidth, 720)
        XCTAssertEqual(SettingsPanelLayout.sidebarWidth, 148)
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
        XCTAssertEqual(info.codexHomePath, codexHome.path)
        XCTAssertTrue(info.authFileExists)
        XCTAssertEqual(info.displayRows.map(\.title), ["数据来源", "接口", "CODEX_HOME", "登录信息"])
        let displayText = info.displayRows.map { "\($0.title) \($0.value)" }.joined(separator: "\n")
        XCTAssertFalse(displayText.contains("secret-token-value"))
        XCTAssertFalse(displayText.contains("auth.json"))
        XCTAssertFalse(displayText.contains(store.snapshotURL().path))
        XCTAssertFalse(displayText.contains("最近读取"))
        XCTAssertFalse(displayText.contains("App Group"))
    }

    func testDefaultClientUsesDirectUsageClientOnly() {
        let viewModel = UsageViewModel()

        let client = Mirror(reflecting: viewModel).children.first { child in
            child.label == "client"
        }?.value

        XCTAssertTrue(client is DirectCodexUsageClient)
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

    func testSettingsPreviewShowsRealMenuBarBackdrops() {
        XCTAssertEqual(MenuBarPreviewAppearance.allCases.map(\.title), ["浅色", "深色", "半透明"])
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
