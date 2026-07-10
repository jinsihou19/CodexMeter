# 发布版本号实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让每次发布拥有唯一、可读且可追踪的版本号。

**Architecture:** 把版本读取、校验和工程更新抽到可测试的 shell 工具中。发布脚本使用工程当前语义版本与构建号命名并构建双架构产物，成功后递增工程构建号。

**Tech Stack:** Bash、Xcode build settings、XCTest

## Global Constraints

- 语义版本必须是 `MAJOR.MINOR.PATCH`。
- 构建号必须是正整数且每次成功发布后递增。
- 主应用与 Widget 版本保持一致。
- 不覆盖已有 DMG。
- 不自动提交。

### Task 1: 可测试版本工具

- [ ] 先写 shell 失败测试，覆盖读取唯一设置、格式校验、递增和工程更新。
- [ ] 确认测试因 `script/release_version.sh` 不存在而失败。
- [ ] 实现最小版本工具并确认测试通过。

### Task 2: 发布脚本集成

- [ ] 把 DMG 命名改为语义版本、构建号和架构。
- [ ] 构建时显式传入两个版本设置。
- [ ] 发布前拒绝覆盖已存在的同版本产物。
- [ ] 全部成功后同步语义版本并递增工程构建号。

### Task 3: 工程版本与验证

- [ ] 把主应用和 Widget 的 Debug/Release 统一设为 `1.0.1 (2)`。
- [ ] 在设置侧栏底部显示从 Bundle 读取的完整版本。
- [ ] 运行版本工具测试、完整 XCTest、Debug 与 Release 构建设置检查。
- [ ] 安装并启动应用，确认 Info.plist 版本为 `1.1.0 (2)`。
