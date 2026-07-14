# 降智雷达分数卡双行布局实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按模型与推理档位排序后统一展示最多六项，使用可读短名和悬停详情，并保证单点 IQ 数据可见。

**Architecture:** 使用 `MenuBarPopoverLayout.swift` 中可测试的纯布局规则计算网格列数和曲线端点索引。分数卡只接收最新结果的前六项，曲线绘制首、末两个端点圆点并保持中间点无标记。

**Tech Stack:** Swift 5、SwiftUI、XCTest、Xcode 16、macOS 14+

## Global Constraints

- 分数卡最多展示六项，六项时按 `3 + 3` 排列。
- 分数卡区域最多两行；五项时为第一行三项、第二行两项。
- 每条至少两个数据点的曲线绘制首、末端点，不绘制中间点圆点。
- 模型按 `Sol → Terra → Luna`，族内按 `ultra → xhigh → high → medium → low` 排序。
- 卡片和图例使用 `5.6-Sol-u` 格式，卡片悬停显示完整名称、分数、通过数和任务数。
- 图例使用三列两行网格，卡片和图例均使用无延迟的自定义悬停浮层。
- 不引入横向滚动、新交互或第三方依赖。
- 全部新增函数和测试方法包含中文职责注释。
- 未经用户明确要求，不创建 Git 提交。

---

### Task 1: 用纯计算约束双行布局

**Files:**
- Modify: `CodexMeter/MenuBarPopoverLayout.swift`
- Test: `CodexMeterTests/CodexRadarTests.swift`

**Interfaces:**
- Consumes: 分数卡数量 `Int`。
- Produces: `CodexRadarScoreGridLayout.columnCount(for:) -> Int`，返回能够把非空项目排进最多两行的列数；空数组返回一列供 SwiftUI 安全构造空网格。

- [ ] **Step 1: 写失败测试**

在 `CodexRadarTests` 中加入：

```swift
/// 验证分数卡列数会把全部项目均分到最多两行，五项时形成三列两行。
func testCodexRadarScoreGridUsesAtMostTwoRows() {
    XCTAssertEqual(CodexRadarScoreGridLayout.columnCount(for: 0), 1)
    XCTAssertEqual(CodexRadarScoreGridLayout.columnCount(for: 1), 1)
    XCTAssertEqual(CodexRadarScoreGridLayout.columnCount(for: 4), 2)
    XCTAssertEqual(CodexRadarScoreGridLayout.columnCount(for: 5), 3)
    XCTAssertEqual(CodexRadarScoreGridLayout.columnCount(for: 8), 4)
}
```

- [ ] **Step 2: 运行定向测试并确认失败原因**

Run:

```bash
rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:CodexMeterTests/CodexRadarTests/testCodexRadarScoreGridUsesAtMostTwoRows
```

Expected: 编译失败，提示找不到 `CodexRadarScoreGridLayout`。

- [ ] **Step 3: 添加最小列数计算实现**

在 `MenuBarPopoverLayout.swift` 中加入：

```swift
/// 降智雷达分数卡布局规则；按项目数量计算最多两行所需的等宽列数。
enum CodexRadarScoreGridLayout {
    /// 返回容纳全部项目且不超过两行的列数；空列表返回一列以安全构造网格。
    static func columnCount(for itemCount: Int) -> Int {
        max(1, (itemCount + 1) / 2)
    }
}
```

- [ ] **Step 4: 运行定向测试并确认通过**

Run: 与 Step 2 相同。

Expected: `testCodexRadarScoreGridUsesAtMostTwoRows` 通过，测试进程退出码为 0。

### Task 2: 限制分数卡最多展示六项

**Files:**
- Modify: `CodexMeter/CodexRadarView.swift:20,97-166`
- Test: `CodexMeterTests/CodexRadarTests.swift`

**Interfaces:**
- Consumes: `modelIQ.latestRuns` 全部项目，以及 Task 1 的 `CodexRadarScoreGridLayout.columnCount(for:)`。
- Produces: 最多六项、两行的等宽 `LazyVGrid`；六项时形成 `3 + 3`。

- [ ] **Step 1: 写静态回归测试并确认当前实现失败**

在 `CodexRadarTests` 中加入读取源码的测试，明确“不截取数据”这一界面契约：

```swift
/// 验证雷达区域最多把六项最新分数传入网格，避免卡片再次挤满弹窗。
func testCodexRadarSectionLimitsLatestRunsToSix() throws {
    let testFileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = testFileURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = projectRoot.appendingPathComponent("CodexMeter/CodexRadarView.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    XCTAssertTrue(source.contains("CodexRadarScoreGrid(runs: Array(modelIQ.latestRuns.prefix(6)))"))
}
```

Run:

```bash
rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:CodexMeterTests/CodexRadarTests/testCodexRadarSectionLimitsLatestRunsToSix
```

Expected: 断言失败，因为源码尚未限制为 `prefix(6)`。

- [ ] **Step 2: 替换数据截取与单行布局**

将调用改为：

```swift
CodexRadarScoreGrid(runs: Array(modelIQ.latestRuns.prefix(6)))
```

将 `CodexRadarScoreGrid.body` 改为：

```swift
var body: some View {
    let columnCount = CodexRadarScoreGridLayout.columnCount(for: runs.count)
    let columns = Array(
        repeating: GridItem(.flexible(minimum: 0), spacing: 4),
        count: columnCount
    )

    LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
        ForEach(runs) { run in
            scoreCard(for: run)
        }
    }
}
```

把原有 `ForEach` 内卡片视图原样提取为带中文注释的 `scoreCard(for:)` 私有方法，返回 `some View`；不改变颜色、边框、内容和最小高度。

- [ ] **Step 3: 运行两个定向测试**

Run:

```bash
rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:CodexMeterTests/CodexRadarTests/testCodexRadarScoreGridUsesAtMostTwoRows -only-testing:CodexMeterTests/CodexRadarTests/testCodexRadarSectionLimitsLatestRunsToSix
```

Expected: 两个测试均通过，测试进程退出码为 0。

### Task 3: 绘制曲线首尾端点

**Files:**
- Modify: `CodexMeter/MenuBarPopoverLayout.swift`
- Modify: `CodexMeter/CodexRadarView.swift:247-265`
- Test: `CodexMeterTests/CodexRadarTests.swift`

**Interfaces:**
- Produces: `CodexRadarLineChartLayout.drawingPlan(for:)`；单点计划不画线但包含索引 `[0]`，多点计划画线并包含首尾索引。

- [ ] **Step 1: 写失败测试**

```swift
/// 验证曲线标记同时覆盖首尾端点，且单点序列不会重复绘制。
func testCodexRadarLineChartCreatesSinglePointAndLineDrawingPlans() {
    XCTAssertEqual(CodexRadarLineChartLayout.drawingPlan(for: 0), .init(drawsLine: false, markerIndexes: []))
    XCTAssertEqual(CodexRadarLineChartLayout.drawingPlan(for: 1), .init(drawsLine: false, markerIndexes: [0]))
    XCTAssertEqual(CodexRadarLineChartLayout.drawingPlan(for: 5), .init(drawsLine: true, markerIndexes: [0, 4]))
}
```

- [ ] **Step 2: 运行定向测试并确认因类型不存在而失败**

```bash
rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:CodexMeterTests/CodexRadarTests/testCodexRadarLineChartCreatesSinglePointAndLineDrawingPlans
```

- [ ] **Step 3: 添加最小端点索引规则并用于绘制**

```swift
/// 降智雷达折线图布局规则；集中决定需要强调的数据点。
enum CodexRadarLineChartLayout {
    struct DrawingPlan: Equatable {
        let drawsLine: Bool
        let markerIndexes: [Int]
    }

    /// 返回曲线绘制计划；单点只画圆点，多点画线并强调首尾。
    static func drawingPlan(for pointCount: Int) -> DrawingPlan {
        guard pointCount > 0 else { return DrawingPlan(drawsLine: false, markerIndexes: []) }
        guard pointCount > 1 else { return DrawingPlan(drawsLine: false, markerIndexes: [0]) }
        return DrawingPlan(drawsLine: true, markerIndexes: [0, pointCount - 1])
    }
}
```

在 `drawSeries` 中遍历这些索引并绘制与现有末点相同的 6pt 圆点。

- [ ] **Step 4: 运行定向测试并确认通过**

Run: 与 Step 2 相同。

Expected: 测试通过，退出码为 0。

### Task 4: 统一排序、限量和展示文案

**Files:**
- Modify: `CodexMeterShared/CodexRadarModels.swift`
- Modify: `CodexMeter/CodexRadarView.swift`
- Modify: `CodexMeter/MenuBarPopoverLayout.swift`
- Test: `CodexMeterTests/CodexRadarTests.swift`

**Interfaces:**
- Produces: `CodexRadarModelIQ.displaySeries(limit:)`，按模型族和推理档位稳定排序后取前六项。
- Produces: `CodexRadarScoreCardText.shortLabel(model:effort:)` 与 `fullLabel(model:effort:)`。

- [ ] **Step 1: 先写排序、限量和文案失败测试**

测试乱序的七条序列，期望 ID 顺序为 `sol-ultra, sol-xhigh, sol-high, sol-medium, sol-low, terra-medium`，并验证短名 `5.6-Sol-u` 和全称 `GPT-5.6-Sol ultra`。

- [ ] **Step 2: 运行定向测试确认失败**

```bash
rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:CodexMeterTests/CodexRadarTests
```

- [ ] **Step 3: 实现稳定排序与文案，并让上下共用 displaySeries**

模型族 rank 为 `sol: 0, terra: 1, luna: 2, other: 3`；推理 rank 为 `ultra: 0, xhigh: 1, high: 2, medium: 3, low: 4, other: 5`。相同 rank 使用原始 offset 保持稳定。

- [ ] **Step 4: 运行雷达测试确认通过**

Run: 与 Step 2 相同。

### Task 5: 完整验证与本地安装

**Files:**
- Verify: `CodexMeter/CodexRadarView.swift`
- Verify: `CodexMeterTests/CodexRadarTests.swift`
- Verify: `docs/superpowers/specs/2026-07-10-radar-score-grid-two-row-design.md`

**Interfaces:**
- Consumes: Task 1 和 Task 2 的已测试实现。
- Produces: 可构建、可安装的 Debug 应用与人工视觉检查结果。

- [ ] **Step 1: 运行完整测试**

```bash
rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`，退出码为 0。

- [ ] **Step 2: 运行 Debug 构建**

```bash
rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`，退出码为 0。

- [ ] **Step 3: 定位构建产物、安装并启动**

先用 `xcodebuild -showBuildSettings` 获取 `TARGET_BUILD_DIR` 和 `FULL_PRODUCT_NAME`，退出已运行的 CodexMeter，将构建产物复制到 `/Applications/CodexMeter.app`，再使用 `open -a /Applications/CodexMeter.app` 启动。复制前仅移除该应用自身的旧安装，不操作其他文件。

- [ ] **Step 4: 视觉与变更检查**

打开菜单栏弹窗，确认五张分数卡按 `3 + 2` 显示、文字可辨认、图表和底部状态未错位。运行：

```bash
rtk git diff --check
rtk git status --short
```

Expected: `git diff --check` 无输出且退出码为 0；状态只包含用户原有改动、设计/计划文档和本次源码/测试改动，不包含意外生成文件。
