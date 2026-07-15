# CodexMeter Settings Panel Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the settings window with a native macOS sidebar and grouped forms while preserving every existing preference and moving maintenance controls into Codex.

**Architecture:** Keep `SettingsView` as the owner of all existing `@AppStorage` bindings and notification paths. Replace only its navigation and pane composition, introduce one small value type for compact/standard/custom menu bar layout selection, and reuse the current reset/action methods.

**Tech Stack:** Swift 6, SwiftUI for macOS, AppKit window presentation, XCTest, Xcode build system.

## Global Constraints

- Preserve all existing preference keys, stored values, notifications, update behavior, usage calculation, networking, and Hook behavior.
- Use native SwiftUI controls before custom settings chrome; add no dependencies.
- All new or materially changed files and functions require Chinese comments explaining responsibility and constraints.
- Do not commit changes without explicit user confirmation.
- After code changes, run tests, install the built app, launch it, and inspect the real settings window.

---

### Task 1: Add the simplified menu bar layout selector

**Files:**
- Modify: `CodexMeter/MenuBarDisplaySettings.swift`
- Test: `CodexMeterTests/UsageViewModelTests.swift`

**Interfaces:**
- Consumes: `MenuBarDisplayPreset.compact.settings`, `MenuBarDisplayPreset.balanced.settings`, `MenuBarDisplayPreset.matchingPreset(for:)`.
- Produces: `MenuBarLayoutChoice` with `.compact`, `.standard`, `.custom`, `matching(settings:)`, and optional `preset`.

- [ ] **Step 1: Add the failing layout-choice test**

```swift
/// 验证简化后的布局选择能映射现有预设，并把其他历史配置安全显示为自定义。
func testMenuBarLayoutChoiceMapsExistingSettingsWithoutMigration() {
    XCTAssertEqual(MenuBarLayoutChoice.matching(settings: MenuBarDisplayPreset.compact.settings), .compact)
    XCTAssertEqual(MenuBarLayoutChoice.matching(settings: MenuBarDisplayPreset.balanced.settings), .standard)
    XCTAssertEqual(MenuBarLayoutChoice.matching(settings: MenuBarDisplayPreset.relaxed.settings), .custom)
    XCTAssertEqual(MenuBarLayoutChoice.compact.preset, .compact)
    XCTAssertEqual(MenuBarLayoutChoice.standard.preset, .balanced)
    XCTAssertNil(MenuBarLayoutChoice.custom.preset)
}
```

- [ ] **Step 2: Run the focused test and verify it fails because the type is absent**

Run:

```bash
rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:CodexMeterTests/UsageViewModelTests/testMenuBarLayoutChoiceMapsExistingSettingsWithoutMigration
```

Expected: compilation fails with `cannot find 'MenuBarLayoutChoice' in scope`.

- [ ] **Step 3: Implement the minimum mapping type**

```swift
/// 把多个排版字段收敛成常用布局选择；无法匹配两档公开预设时保留为自定义，不改写历史配置。
enum MenuBarLayoutChoice: String, CaseIterable, Identifiable {
    case compact
    case standard
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "紧凑"
        case .standard: "标准"
        case .custom: "自定义"
        }
    }

    var preset: MenuBarDisplayPreset? {
        switch self {
        case .compact: .compact
        case .standard: .balanced
        case .custom: nil
        }
    }

    static func matching(settings: MenuBarDisplaySettings) -> Self {
        switch MenuBarDisplayPreset.matchingPreset(for: settings) {
        case .compact: .compact
        case .balanced: .standard
        case .relaxed, .none: .custom
        }
    }
}
```

- [ ] **Step 4: Re-run the focused test**

Expected: the focused test passes.

### Task 2: Replace custom settings chrome with native navigation and grouped forms

**Files:**
- Modify: `CodexMeter/SettingsView.swift`
- Modify: `CodexMeter/SettingsSections.swift`
- Modify: `CodexMeter/SettingsPanelLayout.swift`
- Modify: `CodexMeter/SettingsWindowPresenter.swift`
- Test: `CodexMeterTests/UsageViewModelTests.swift`

**Interfaces:**
- Consumes: all existing bindings and action methods in `SettingsView`, plus `MenuBarLayoutChoice` from Task 1.
- Produces: six-pane sidebar, grouped forms, disclosure groups, and 880 × 620 window sizing.

- [ ] **Step 1: Replace the obsolete sidebar-version source test with a structural test**

```swift
/// 验证设置页使用六个稳定入口和原生分组控件，并把高级内容并入 Codex。
func testSettingsUsesSimplifiedNativeStructure() throws {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(
        contentsOf: projectRoot.appendingPathComponent("CodexMeter/SettingsView.swift"),
        encoding: .utf8
    )

    XCTAssertTrue(source.contains("List(selection:"))
    XCTAssertTrue(source.contains(".formStyle(.grouped)"))
    XCTAssertTrue(source.contains("DisclosureGroup(\"更多选项\""))
    XCTAssertTrue(source.contains("DisclosureGroup(\"连接详情\""))
    XCTAssertFalse(source.contains("case advanced"))
    XCTAssertFalse(source.contains("private var header:"))
    XCTAssertFalse(source.contains("缓存文件"))
}
```

- [ ] **Step 2: Run the focused structural test and verify it fails against the old layout**

Run the same `xcodebuild` command with `-only-testing:CodexMeterTests/UsageViewModelTests/testSettingsUsesSimplifiedNativeStructure`.

Expected: assertions for native structure fail.

- [ ] **Step 3: Rebuild the root layout**

Replace the fixed header/button sidebar/scroll view with a native selection list and content form:

```swift
private var content: some View {
    HStack(spacing: 0) {
        List(selection: $selectedPane) {
            ForEach(Pane.allCases) { pane in
                Label(pane.title, systemImage: pane.symbolName).tag(pane)
            }
        }
        .listStyle(.sidebar)
        .frame(width: SettingsPanelLayout.sidebarWidth)

        Divider()
        contentPane.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 800, idealWidth: 880, minHeight: 560, idealHeight: 620)
}
```

Remove `.advanced`, rename “常规” to “通用”, and use `Form { Section { ... } header: { Text(...) } }` for every pane.

- [ ] **Step 4: Reorganize pane content without changing bindings**

Implement the approved locations exactly:

- General: system and appearance sections; `DisclosureGroup("更多选项")` contains launch-open, opacity, and three custom colors.
- Menu bar: preview, common content, layout choice; custom controls appear only when `MenuBarLayoutChoice.matching(settings:) == .custom`.
- Popover: usage, activity, insights, radar, and display sections; retain all toggles.
- Widget: retain the five editable rows and remove read-only timeline/cache rows.
- Codex: connection, actions, `DisclosureGroup("连接详情")`, workday calculation, and all maintenance/reset actions.
- About: identity, update controls, and links.

Use this binding for the simplified layout picker:

```swift
private var menuBarLayoutChoiceBinding: Binding<MenuBarLayoutChoice> {
    Binding(
        get: { MenuBarLayoutChoice.matching(settings: currentSettings) },
        set: { choice in
            guard let preset = choice.preset else { return }
            applyDisplayPreset(preset)
        }
    )
}
```

- [ ] **Step 5: Simplify shared row styling**

Update preference rows so titles and useful subtitles are inline, remove the ubiquitous info popover from normal rows, and keep help text through native secondary text and `.help`. Delete custom settings components only when no call sites remain.

- [ ] **Step 6: Update window dimensions**

Set `SettingsPanelLayout.sidebarWidth = 190`, content ideal size to 880 × 620, and `SettingsWindowPresenter` content size to 880 × 620 with minimum 800 × 560.

- [ ] **Step 7: Run the focused structural and window tests**

Run:

```bash
rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO \
  -only-testing:CodexMeterTests/UsageViewModelTests/testSettingsUsesSimplifiedNativeStructure \
  -only-testing:CodexMeterTests/UsageViewModelTests/testSettingsWindowUsesExpandedResizableContentSize
```

Expected: both tests pass.

### Task 3: Verify, install, and inspect the real app

**Files:**
- Modify only if verification reveals a defect in files already listed above.

**Interfaces:**
- Consumes: completed settings UI and existing packaging script.
- Produces: passing test/build evidence and a freshly installed running app.

- [ ] **Step 1: Run formatting and static diff checks**

Run `rtk git diff --check` and inspect `rtk git diff --stat`.

Expected: no whitespace errors and only scoped files changed in addition to pre-existing user work.

- [ ] **Step 2: Run the full test suite**

```bash
rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass.

- [ ] **Step 3: Build the app**

```bash
rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Install and launch the fresh build**

Read `TARGET_BUILD_DIR` and `FULL_PRODUCT_NAME` from `xcodebuild -showBuildSettings`, stop only the running CodexMeter/CodexUsage process, replace `/Applications/CodexUsage.app` with that build product, and launch it with `open -n /Applications/CodexUsage.app`.

Expected: `/Applications/CodexUsage.app` runs and displays as CodexMeter.

- [ ] **Step 5: Inspect the settings window**

Open settings, capture the real window, and verify six sidebar entries, grouped forms, disclosure behavior, conditional custom layout controls, dark/light appearance, and Codex maintenance actions.

- [ ] **Step 6: Report without committing**

Summarize changed files, tests, installation result, and any deliberately retained compatibility behavior. Do not stage or commit.
