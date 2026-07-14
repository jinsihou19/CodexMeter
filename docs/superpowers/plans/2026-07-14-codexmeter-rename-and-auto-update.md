# CodexMeter Rename And Auto Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保留旧版持久化标识和用户数据的前提下，将产品统一命名为 CodexMeter，并通过 Sparkle 2、Universal DMG 和 GitHub 托管源提供自动更新。

**Architecture:** 工程和源码采用新名称，但主应用 Bundle ID、App Group、Widget kind、偏好 key 以及桥接期 App 包名保持旧值。Sparkle 标准控制器负责更新生命周期，发布脚本只构建一个 Universal DMG，并用 Sparkle 自带工具生成 EdDSA 签名和 appcast。

**Tech Stack:** Swift 6、AppKit、SwiftUI、WidgetKit、XCTest、Shell、Sparkle 2、GitHub Releases、GitHub Pages。

## Global Constraints

- 最低系统版本保持 macOS 14.0。
- 正式名称统一写作 `CodexMeter`，不使用 `Codex Meter`。
- 必须保留 `com.jinsihou.CodexUsage`、`group.com.jinsihou.CodexUsage`、现有 Widget kind、偏好 key 和缓存路径。
- 桥接期产物继续安装到 `/Applications/CodexUsage.app`，通过 `CFBundleDisplayName` 显示 `CodexMeter`。
- 更新源固定为 `https://jinsihou19.github.io/CodexMeter/appcast.xml`。
- 更新包必须通过 Sparkle EdDSA 校验，私钥只保存在本机 Keychain。
- 不新增自定义更新器、更新 UI、频道、灰度或增量发布逻辑。
- 所有新增或明显调整的文件、类和关键方法使用中文注释。
- 不修改用户已有的 `.gitignore` 变更，不自动提交或推送源码；默认创建 GitHub Release 并启用 Pages，可显式设置 `CODEX_PUBLISH_RELEASE=0` 跳过远程发布。

---

### Task 1: 建立全量改名的可执行契约

**Files:**
- Create: `script/test_product_identity.sh`
- Modify: `script/test_release_version.sh`

**Interfaces:**
- Consumes: 当前工程目录与 `project.pbxproj`。
- Produces: 可重复验证新产品名和旧兼容标识的 Shell 检查。

- [ ] **Step 1: 写失败的产品标识测试**

创建 `script/test_product_identity.sh`，检查新工程、scheme、源码目录、README 标题和 `CFBundleDisplayName` 存在，同时检查旧 Bundle ID、App Group 和兼容包名仍存在。对旧名称的扫描只允许命中明确列出的兼容标识和历史迁移说明。

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/CodexMeter.xcodeproj/project.pbxproj"

test -d "$ROOT_DIR/CodexMeter.xcodeproj"
test -f "$ROOT_DIR/CodexMeter.xcodeproj/xcshareddata/xcschemes/CodexMeter.xcscheme"
test -d "$ROOT_DIR/CodexMeter"
test -d "$ROOT_DIR/CodexMeterShared"
test -d "$ROOT_DIR/CodexMeterTests"
test -d "$ROOT_DIR/CodexMeterWidget"
grep -Fq '# CodexMeter' "$ROOT_DIR/README.md"
grep -Fq '<string>CodexMeter</string>' "$ROOT_DIR/CodexMeter/Info.plist"
grep -Fq 'PRODUCT_BUNDLE_IDENTIFIER = com.jinsihou.CodexUsage;' "$PROJECT_FILE"
grep -Fq 'PRODUCT_NAME = CodexUsage;' "$PROJECT_FILE"
grep -Fq 'group.com.jinsihou.CodexUsage' "$ROOT_DIR/CodexMeter/CodexMeter.entitlements"

echo "Product identity tests passed"
```

- [ ] **Step 2: 运行测试并确认因旧路径失败**

Run: `rtk bash script/test_product_identity.sh`

Expected: FAIL，缺少 `CodexMeter.xcodeproj`。

- [ ] **Step 3: 扩展发布契约测试**

将 `script/test_release_version.sh` 的实际工程路径改为 `CodexMeter.xcodeproj/project.pbxproj`，并断言发布脚本包含：

```bash
assert_script_contains 'PRODUCT_NAME="$COMPATIBLE_PRODUCT_NAME"' "保留兼容 App 包名"
assert_script_contains 'ARCHS="arm64 x86_64"' "构建 Universal App"
assert_script_contains 'APP_ARCHS="$(lipo -archs' "验证 Universal 架构"
assert_script_contains 'generate_appcast' "生成 Sparkle appcast"
assert_script_contains 'https://github.com/jinsihou19/CodexMeter/releases/download/' "GitHub Release 下载前缀"
```

- [ ] **Step 4: 保存检查点，不提交**

Run: `rtk git diff --check -- script/test_product_identity.sh script/test_release_version.sh`

Expected: exit 0。

### Task 2: 重命名工程、模块、目录与用户可见名称

**Files:**
- Rename: `CodexUsage.xcodeproj` → `CodexMeter.xcodeproj`
- Rename: `CodexUsage` → `CodexMeter`
- Rename: `CodexUsageShared` → `CodexMeterShared`
- Rename: `CodexUsageTests` → `CodexMeterTests`
- Rename: `CodexUsageWidget` → `CodexMeterWidget`
- Rename: filenames and scheme entries containing `CodexUsage` to `CodexMeter`
- Modify: `CodexMeter.xcodeproj/project.pbxproj`
- Modify: all Swift imports and product-named Swift symbols
- Modify: `CodexMeter/Info.plist`
- Modify: `CodexMeterWidget/Info.plist`

**Interfaces:**
- Consumes: Task 1 product identity checks。
- Produces: 可由 `CodexMeter` scheme 构建的工程；持久化标识保持兼容。

- [ ] **Step 1: 移动工程和源码路径**

使用文件移动保留历史，并把以下文件改名：

```text
CodexUsageApp.swift             → CodexMeterApp.swift
CodexUsage.entitlements        → CodexMeter.entitlements
CodexUsageWidget.swift         → CodexMeterWidget.swift
CodexUsageWidgetBundle.swift   → CodexMeterWidgetBundle.swift
CodexUsageWidget.entitlements  → CodexMeterWidget.entitlements
CodexUsage.xcscheme            → CodexMeter.xcscheme
```

- [ ] **Step 2: 更新 Xcode 工程引用**

将 PBX project、group、target、module、test target 和 scheme 名改为 `CodexMeter*`。主应用配置必须显式保留：

```text
PRODUCT_BUNDLE_IDENTIFIER = com.jinsihou.CodexUsage;
PRODUCT_NAME = CodexUsage;
INFOPLIST_KEY_CFBundleDisplayName = CodexMeter;
```

Shared、Tests 和 Widget 的 Bundle ID 保持原值，目录和模块名改为 `CodexMeter*`。所有 `import CodexUsageShared` 改为 `import CodexMeterShared`。

- [ ] **Step 3: 更新 Swift 产品符号和界面文案**

至少完成以下符号迁移：

```swift
CodexUsageMain              → CodexMeterMain
CodexUsageWidget            → CodexMeterWidget
CodexUsageWidgetBundle      → CodexMeterWidgetBundle
```

设置标题、页头和菜单提示统一使用 `CodexMeter` 或自然中文描述；旧 Widget kind、偏好 key 和缓存路径不改。

- [ ] **Step 4: 运行产品标识测试**

Run: `rtk bash script/test_product_identity.sh`

Expected: `Product identity tests passed`。

- [ ] **Step 5: 构建改名后的基线工程**

Run: `rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`

Expected: `BUILD SUCCEEDED`。

### Task 3: 接入 Sparkle 标准更新器

**Files:**
- Modify: `CodexMeter.xcodeproj/project.pbxproj`
- Modify: `CodexMeter/Info.plist`
- Modify: `CodexMeter/CodexMeterApp.swift`
- Modify: `CodexMeter/SettingsView.swift`
- Test: `script/test_product_identity.sh`

**Interfaces:**
- Consumes: Sparkle package product `Sparkle`、固定 feed URL 和 Keychain 中的 EdDSA 私钥。
- Produces: `SPUStandardUpdaterController` 生命周期及设置页 `CheckForUpdatesView`。

- [ ] **Step 1: 先扩展失败的静态集成测试**

向 `script/test_product_identity.sh` 增加：

```bash
grep -Fq 'https://github.com/sparkle-project/Sparkle' "$PROJECT_FILE"
grep -Fq '<key>SUFeedURL</key>' "$ROOT_DIR/CodexMeter/Info.plist"
grep -Fq '<string>https://jinsihou19.github.io/CodexMeter/appcast.xml</string>' "$ROOT_DIR/CodexMeter/Info.plist"
grep -Fq '<key>SUPublicEDKey</key>' "$ROOT_DIR/CodexMeter/Info.plist"
grep -Fq 'SPUStandardUpdaterController' "$ROOT_DIR/CodexMeter/CodexMeterApp.swift"
grep -Fq 'CheckForUpdatesView' "$ROOT_DIR/CodexMeter/SettingsView.swift"
```

- [ ] **Step 2: 运行测试并确认因 Sparkle 未接入失败**

Run: `rtk bash script/test_product_identity.sh`

Expected: FAIL，缺少 Sparkle package URL 或 `SUFeedURL`。

- [ ] **Step 3: 添加 Sparkle 2 包依赖**

在 PBX project 增加 `XCRemoteSwiftPackageReference`，URL 为 `https://github.com/sparkle-project/Sparkle`，使用 2.x 的 up-to-next-major 规则，并将 `Sparkle` product 链接到主应用 target。不要链接到 Shared、Tests 或 Widget target。

- [ ] **Step 4: 生成 EdDSA 密钥并配置 Info.plist**

先解析依赖，再从 Xcode 的 SourcePackages artifact 运行 `generate_keys`。把输出的公钥写入：

```xml
<key>CFBundleDisplayName</key>
<string>CodexMeter</string>
<key>SUFeedURL</key>
<string>https://jinsihou19.github.io/CodexMeter/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>生成的 Base64 公钥</string>
```

私钥只保留在 Keychain，不写文件。

- [ ] **Step 5: 使用 Sparkle 原生控制器和 SwiftUI 检查按钮**

在 `CodexMeterApp.swift` 中导入 Sparkle，并让 `AppDelegate` 持有：

```swift
/// 管理标准 Sparkle 更新流程；生命周期与应用委托一致，避免控制器被提前释放。
private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
)
```

通过设置窗口 presenter 的现有构造闭包把 `updaterController.updater` 传给 `SettingsView`，并在“常规”页加入：

```swift
SettingsSection(title: "更新", subtitle: "自动检查并安全安装 CodexMeter 新版本") {
    CheckForUpdatesView(updater: updater)
}
```

不自建 ObservableObject、下载器或按钮状态逻辑，直接使用 Sparkle 的 KVO 适配视图。

- [ ] **Step 6: 运行静态检查和完整 XCTest**

Run: `rtk bash script/test_product_identity.sh`

Expected: `Product identity tests passed`。

Run: `rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`

Expected: `TEST SUCCEEDED`。

### Task 4: 改造 Universal DMG、GitHub Release 和 Pages 发布流程

**Files:**
- Modify: `script/package_release.sh`
- Modify: `script/test_release_version.sh`
- Create: `.github/workflows/publish-appcast.yml`

**Interfaces:**
- Consumes: Sparkle artifact 的 `generate_appcast`、Keychain EdDSA 私钥、Task 2 的兼容 App 包名。
- Produces: `dist/CodexMeter-<version>-<build>-universal.dmg`、`dist/appcast.xml`，以及可选 GitHub Release 和 Pages 部署。

- [ ] **Step 1: 运行扩展后的发布测试并确认失败**

Run: `rtk bash script/test_release_version.sh`

Expected: FAIL，缺少 Universal 或 `generate_appcast` 发布契约。

- [ ] **Step 2: 将发布脚本收敛为单一 Universal 构建**

使用以下固定名称：

```bash
APP_NAME="CodexMeter"
SCHEME_NAME="CodexMeter"
COMPATIBLE_PRODUCT_NAME="CodexUsage"
PROJECT_PATH="$ROOT_DIR/CodexMeter.xcodeproj"
DMG_PATH="$DIST_DIR/$APP_NAME-$MARKETING_VERSION-$BUILD_NUMBER-universal.dmg"
APP_PATH="$BUILD_DIR/Release/$COMPATIBLE_PRODUCT_NAME.app"
```

`xcodebuild` 传入 Universal 架构设置；兼容包名由主 target 自身的 `PRODUCT_NAME = CodexUsage` 保证，不能通过命令行全局覆盖，否则 Widget 和共享框架会产生同名模块：

```bash
ARCHS="arm64 x86_64"
ONLY_ACTIVE_ARCH=NO
```

读取 `lipo -archs` 后分别确认包含 `arm64` 与 `x86_64`，不依赖输出顺序。

- [ ] **Step 3: 增加 Sparkle 工具发现和 appcast 生成**

支持 `SPARKLE_BIN_DIR` 显式覆盖；否则在 DerivedData 的 SourcePackages artifact 中查找。缺少 `generate_appcast` 时退出。把 DMG 复制到临时 appcast 目录后运行：

```bash
"$SPARKLE_BIN_DIR/generate_appcast" \
  --download-url-prefix "https://github.com/jinsihou19/CodexMeter/releases/download/v$MARKETING_VERSION/" \
  "$APPCAST_WORK_DIR"
```

生成失败时不得安装 App 或推进构建号。

- [ ] **Step 4: 增加显式远程发布与 Pages 工作流**

默认要求工作区干净且 `gh auth status` 成功，通过 GitHub API 启用 Pages workflow 模式，再用 `gh release create` 上传 DMG 与 appcast；设置 `CODEX_PUBLISH_RELEASE=0` 时只执行本地流程。`.github/workflows/publish-appcast.yml` 监听 Release published 事件并使用官方 Pages actions 部署 appcast。

- [ ] **Step 5: 运行发布脚本测试**

Run: `rtk bash script/test_release_version.sh`

Expected: `Release version tests passed`。

- [ ] **Step 6: 执行 Shell 语法检查**

Run: `rtk bash -n script/package_release.sh script/release_version.sh script/test_release_version.sh script/test_product_identity.sh`

Expected: exit 0。

### Task 5: 重写 README、整理截图并同步文档名称

**Files:**
- Rewrite: `README.md`
- Move: `kms-release-assets/codexusage-*.png` → `docs/images/codexmeter-*.png`
- Rename: `kms-release-assets/Codex 额度强迫症有救了：剩余用量、重置卡和降智雷达一眼看清.md` → `kms-release-assets/CodexMeter：剩余用量、重置卡和降智雷达一眼看清.md`
- Modify: all Markdown files containing current product-name references

**Interfaces:**
- Consumes: GitHub repository `jinsihou19/CodexMeter`、Task 4 产物名和 feed URL。
- Produces: 可直接作为 GitHub 首页使用的中文 README。

- [ ] **Step 1: 移动截图并更新名称**

使用：

```text
docs/images/codexmeter-popover.png
docs/images/codexmeter-popover-cropped.png
docs/images/codexmeter-settings.png
docs/images/codexmeter-widget.png
```

- [ ] **Step 2: 重写 README**

README 必须包含：产品简介、截图、功能、安装与桥接说明、自动更新、隐私、系统要求、构建测试和发布命令。图片使用相对路径，例如：

```markdown
![CodexMeter 下拉面板](docs/images/codexmeter-popover.png)
```

- [ ] **Step 3: 同步历史文档与宣传文章**

把现行工程名、命令、路径和产品标题改为 `CodexMeter`。旧兼容标识只在迁移说明中保留，并明确标注“兼容标识，请勿修改”。

- [ ] **Step 4: 验证 Markdown 图片和旧名称残留**

Run: `rtk rg -n 'CodexUsage|Codex Usage|Codex 用量|codexusage' README.md docs kms-release-assets`

Expected: 仅设计文档中的兼容标识和迁移说明命中。

Run: `rtk bash script/test_product_identity.sh`

Expected: `Product identity tests passed`。

### Task 6: 完整验证、安装与交付检查

**Files:**
- Modify only if verification exposes an in-scope defect.

**Interfaces:**
- Consumes: Tasks 1–5 全部成果。
- Produces: 已测试、已安装且可发布的桥接版本工作区。

- [ ] **Step 1: 运行全部脚本测试**

Run: `rtk bash script/test_product_identity.sh && rtk bash script/test_release_version.sh`

Expected: 两组测试均通过。

- [ ] **Step 2: 运行完整 XCTest**

Run: `rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`

Expected: `TEST SUCCEEDED`，0 failures。

- [ ] **Step 3: 运行 Debug 构建**

Run: `rtk xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Expected: `BUILD SUCCEEDED`。

- [ ] **Step 4: 运行 Release Universal 打包并安装**

Run: `rtk bash script/package_release.sh`

Expected: 生成 `CodexMeter-<version>-<build>-universal.dmg` 和 `dist/appcast.xml`，安装 `/Applications/CodexUsage.app` 并启动，随后推进下一构建号。

- [ ] **Step 5: 验证安装包身份与架构**

Run:

```bash
rtk defaults read /Applications/CodexUsage.app/Contents/Info CFBundleDisplayName
rtk defaults read /Applications/CodexUsage.app/Contents/Info CFBundleIdentifier
rtk lipo -archs /Applications/CodexUsage.app/Contents/MacOS/CodexUsage
```

Expected: 分别为 `CodexMeter`、`com.jinsihou.CodexUsage`、同时包含 `arm64 x86_64`。

- [ ] **Step 6: 检查差异和敏感文件**

Run: `rtk git diff --check && rtk git status --short`

Expected: 无空白错误；`.codex/real-usage-response.json`、私钥和认证令牌不在待提交文件中；用户原有 `.gitignore` 改动保持不变。

- [ ] **Step 7: 汇报结果，不提交**

列出改动、测试、安装结果、仍需用户手动完成的 GitHub Release 上传与 Pages 启用步骤。除非用户另行授权，不执行 `git add`、`git commit`、`git push` 或 GitHub 外部写操作。
