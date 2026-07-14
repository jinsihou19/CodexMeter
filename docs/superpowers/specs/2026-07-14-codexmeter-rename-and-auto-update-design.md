# CodexMeter 全量改名与自动更新设计

## 目标

将项目的正式名称统一为 `CodexMeter`，重写 README 并使用现有截图介绍主要能力；同时接入 Sparkle 2，让桥接版本之后的发布能够自动检查、下载和安装更新。

本次改动必须保留旧版设置、缓存、Widget 配置和登录启动状态。当前已发布版本没有更新器，因此现有用户需要手动安装一次桥接版本；桥接完成后的版本才支持无感自动更新。

## 命名与兼容边界

以下名称改为 `CodexMeter`：

- Xcode 工程、scheme、target 和 Swift 模块名称。
- 源码目录、测试目录、Widget 目录及相关文件名。
- Swift 中以产品名命名的类型和符号。
- App、设置窗口、DMG 卷标、发布产物和文档中的用户可见名称。
- README、发布脚本和历史设计文档中的现行产品名称。
- 截图文件名及 README 图片引用。

以下旧标识必须保留，并在代码或工程配置中标明其兼容用途：

- 主应用 Bundle ID：`com.jinsihou.CodexUsage`。
- App Group：`group.com.jinsihou.CodexUsage`。
- Widget Bundle ID、Widget kind、UserDefaults key、缓存文件位置等已持久化标识。
- 桥接阶段的实际 App 包名和可执行文件名 `CodexUsage.app`，用于覆盖 `/Applications/CodexUsage.app`，避免产生两个应用。

主应用通过 `CFBundleDisplayName = CodexMeter` 对用户展示新名称。内部 target 和代码采用新名称，构建产物通过显式 `PRODUCT_NAME = CodexUsage` 保留兼容包名。以后若要彻底删除旧标识，需要单独设计有签名保障的数据与 Widget 迁移，不包含在本次范围内。

## 自动更新架构

使用 Sparkle 2 的标准更新控制器，不自研下载、校验、替换或提权逻辑。

- 通过 Swift Package Manager 引入 Sparkle 2。
- App 启动时创建并持有 `SPUStandardUpdaterController`，启用 Sparkle 默认的后台检查流程。
- 设置页“常规”区域提供“检查更新”按钮，并根据 Sparkle 状态决定按钮是否可用。
- `Info.plist` 配置更新源 `https://jinsihou19.github.io/CodexMeter/appcast.xml` 和 Sparkle EdDSA 公钥。
- 更新包和 appcast 使用 Sparkle 工具生成 EdDSA 签名；私钥保存在发布者的 macOS Keychain，不写入仓库。
- 更新源与安装包均使用 HTTPS。当前 ad-hoc 分发方式继续保留；Developer ID 签名和 Apple 公证作为后续公开分发增强，不阻塞本次小范围更新链路。

Sparkle 默认每天在后台检查一次。用户可从设置页主动检查；发现更新后使用 Sparkle 标准界面展示版本和安装操作。首版不定制更新窗口、不做灰度通道、不做增量更新。

## 发布流程

发布脚本调整为构建一个同时包含 `arm64` 和 `x86_64` 的 Universal App，并生成单一 DMG。这样 appcast 只需要维护一个更新包，不需要按架构拆分更新源。

发布流程如下：

1. 运行版本校验和测试。
2. 构建 Release Universal App，验证主应用二进制同时包含两个架构。
3. 使用现有 DMG 结构打包 App 和 `/Applications` 快捷方式。
4. 使用 Sparkle 工具对 DMG 签名并生成或更新 `appcast.xml`。
5. 默认脚本检查干净工作区和 GitHub CLI 登录后自动创建 GitHub Release；显式设置 `CODEX_PUBLISH_RELEASE=0` 时只输出本地产物。
6. Release 发布事件触发 GitHub Actions，把 Release 中已签名的 `appcast.xml` 自动部署到 GitHub Pages；首次发布由脚本通过 GitHub API 启用 Pages workflow 模式。
7. 全部本地构建、安装和所选发布流程成功后，才递增下一构建号。

EdDSA 私钥只留在本机 Keychain，GitHub Actions 仅部署 Release 中已经签名的 appcast，不接触签名密钥或重新构建 App。

## README 与图片

README 重写为中文项目首页，包含：

- 产品简介、系统要求和隐私说明。
- 菜单栏、下拉面板、重置卡、模型雷达、设置页与 Widget 能力。
- 使用现有弹窗、设置和 Widget 截图的分区介绍。
- 安装、自动更新、构建测试和发布说明。
- 明确首次桥接安装与后续自动更新的区别。

现有截图移动到 `docs/images/`，文件名统一使用 `codexmeter-` 前缀。宣传文章保留，但将现行产品名称和图片路径同步为新名称。

## 错误处理与安全

- Sparkle 负责网络失败、签名失败、权限不足和安装回滚提示。
- appcast 或更新包签名不匹配时必须拒绝安装，不提供绕过开关。
- 发布脚本缺少 Sparkle 工具、签名密钥、GitHub CLI 登录或目标文件已存在时立即失败。
- 私钥、认证令牌和真实用量响应不得进入 Git；现有用户工作区文件不在本次改动范围内。
- 更新失败不得推进工程构建号，也不得覆盖已有发布产物。

## 测试与验收

采用最小可运行检查覆盖新增逻辑和发布契约：

- 先扩展发布脚本测试，验证 Universal 架构、`CodexMeter` 产物命名、兼容 App 包名、appcast 地址和签名步骤；确认测试先失败，再实现脚本。
- 为更新按钮与控制器协作留下一个小型 XCTest，验证设置页触发标准更新检查且禁用状态正确。
- 运行完整 XCTest、Debug 构建和 Release Universal 构建。
- 安装到 `/Applications/CodexUsage.app` 后验证 Finder/界面显示 `CodexMeter`，旧设置和缓存仍可读取，Widget target 可构建。
- 验证主应用与 Widget 的版本号一致，主应用二进制包含 `arm64 x86_64`。
- 使用本地测试 appcast 或发布前测试源完成一次旧桥接构建到新构建的 Sparkle 更新演练。

## 不包含内容

- 不更换兼容 Bundle ID、App Group、Widget kind 或持久化 key。
- 不开发自定义更新下载器、安装器或更新 UI。
- 不增加多更新频道、灰度发布、增量包或强制更新。
- 不自动提交或推送源码；默认创建 GitHub Release 并配置 Pages，调用者可显式设置 `CODEX_PUBLISH_RELEASE=0` 跳过远程发布。
