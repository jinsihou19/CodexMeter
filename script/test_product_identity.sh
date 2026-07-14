#!/usr/bin/env bash
set -euo pipefail

# 本文件验证正式产品名已经统一，同时旧版持久化标识仍被保留以支持无损升级。

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
grep -Fq 'PRODUCT_MODULE_NAME = CodexMeter;' "$PROJECT_FILE"
grep -Fq 'PRODUCT_NAME = CodexUsage;' "$PROJECT_FILE"
grep -Fq 'group.com.jinsihou.CodexUsage' "$ROOT_DIR/CodexMeter/CodexMeter.entitlements"
grep -Fq 'https://github.com/sparkle-project/Sparkle' "$PROJECT_FILE"
grep -Fq '<key>SUFeedURL</key>' "$ROOT_DIR/CodexMeter/Info.plist"
grep -Fq '<string>https://jinsihou19.github.io/CodexMeter/appcast.xml</string>' "$ROOT_DIR/CodexMeter/Info.plist"
grep -Fq '<key>SUEnableAutomaticChecks</key>' "$ROOT_DIR/CodexMeter/Info.plist"
grep -Fq '<key>SUPublicEDKey</key>' "$ROOT_DIR/CodexMeter/Info.plist"
grep -Fq 'SPUStandardUpdaterController' "$ROOT_DIR/CodexMeter/SettingsView.swift"
grep -Fq 'CheckForUpdatesView' "$ROOT_DIR/CodexMeter/SettingsView.swift"

echo "Product identity tests passed"
