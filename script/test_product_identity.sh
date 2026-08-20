#!/usr/bin/env bash
set -euo pipefail

# 本文件验证应用、Widget 和共享模块统一使用 CodexMeter 身份标识。

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/CodexMeter.xcodeproj/project.pbxproj"
SCHEME_FILE="$ROOT_DIR/CodexMeter.xcodeproj/xcshareddata/xcschemes/CodexMeter.xcscheme"

test -d "$ROOT_DIR/CodexMeter.xcodeproj"
test -f "$ROOT_DIR/CodexMeter.xcodeproj/xcshareddata/xcschemes/CodexMeter.xcscheme"
test -d "$ROOT_DIR/CodexMeter"
test -d "$ROOT_DIR/CodexMeterShared"
test -d "$ROOT_DIR/CodexMeterTests"
test -d "$ROOT_DIR/CodexMeterWidget"
grep -Fq '# CodexMeter' "$ROOT_DIR/README.md"
grep -Fq '<string>CodexMeter</string>' "$ROOT_DIR/CodexMeter/Info.plist"
grep -Fq 'PRODUCT_BUNDLE_IDENTIFIER = com.jinsihou.CodexMeter;' "$PROJECT_FILE"
grep -Fq 'PRODUCT_MODULE_NAME = CodexMeter;' "$PROJECT_FILE"
grep -Fq 'PRODUCT_NAME = CodexMeter;' "$PROJECT_FILE"
grep -Fq 'BuildableName = "CodexMeter.app"' "$SCHEME_FILE"
grep -Fq 'group.com.jinsihou.CodexMeter' "$ROOT_DIR/CodexMeter/CodexMeter.entitlements"
grep -Fq 'PRODUCT_BUNDLE_IDENTIFIER = com.jinsihou.CodexMeter.WidgetExtension;' "$PROJECT_FILE"
grep -Fq 'https://github.com/sparkle-project/Sparkle' "$PROJECT_FILE"
grep -Fq '<key>SUFeedURL</key>' "$ROOT_DIR/CodexMeter/Info.plist"
grep -Fq '<string>https://jinsihou19.github.io/CodexMeter/appcast.xml</string>' "$ROOT_DIR/CodexMeter/Info.plist"
grep -Fq '<key>SUEnableAutomaticChecks</key>' "$ROOT_DIR/CodexMeter/Info.plist"
grep -Fq '<key>SUPublicEDKey</key>' "$ROOT_DIR/CodexMeter/Info.plist"
grep -Fq 'SPUStandardUpdaterController' "$ROOT_DIR/CodexMeter/SettingsView.swift"
grep -Fq 'CheckForUpdatesView' "$ROOT_DIR/CodexMeter/SettingsView.swift"

if rg -n --hidden -g '!.git' -g '!build' -g '!dist' -g '!.gitnexus' \
  -g '!script/test_product_identity.sh' -g '!CodexMeterShared/MenuBarDisplaySettings.swift' \
  -g '!CodexMeter/CodexMeterApp.swift' \
  'CodexUsage\.app|com\.jinsihou\.CodexUsage|group\.com\.jinsihou\.CodexUsage|CodexUsageWidget"|CodexUsageShared|CodexUsageTests|CodexUsage\.WidgetExtension|Application Support/CodexUsage' \
  "$ROOT_DIR" >/dev/null; then
  echo "Legacy CodexUsage identity remains" >&2
  exit 1
fi

echo "Product identity tests passed"
