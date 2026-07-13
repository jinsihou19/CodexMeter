#!/usr/bin/env bash
set -euo pipefail

# 本文件验证发布版本工具的读取、校验、递增和工程配置同步行为。

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/release_version.sh"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
PROJECT_FILE="$TEMP_DIR/project.pbxproj"
PACKAGE_SCRIPT="$ROOT_DIR/script/package_release.sh"
ACTUAL_PROJECT_FILE="$ROOT_DIR/CodexUsage.xcodeproj/project.pbxproj"

cat > "$PROJECT_FILE" <<'EOF'
CURRENT_PROJECT_VERSION = 2;
MARKETING_VERSION = 1.1.0;
CURRENT_PROJECT_VERSION = 2;
MARKETING_VERSION = 1.1.0;
CURRENT_PROJECT_VERSION = 2;
MARKETING_VERSION = 1.1.0;
CURRENT_PROJECT_VERSION = 2;
MARKETING_VERSION = 1.1.0;
EOF

# 比较实际值和期望值，失败时输出清晰的测试上下文。
assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [ "$expected" != "$actual" ]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

# 验证发布脚本包含关键版本契约，避免后续重构绕过唯一版本保护。
assert_script_contains() {
  local pattern="$1"
  local message="$2"
  if ! grep -Fq "$pattern" "$PACKAGE_SCRIPT"; then
    echo "$message: missing '$pattern'" >&2
    exit 1
  fi
}

assert_equal "1.1.0" "$(release_read_project_setting "$PROJECT_FILE" MARKETING_VERSION)" "读取语义版本"
assert_equal "2" "$(release_read_project_setting "$PROJECT_FILE" CURRENT_PROJECT_VERSION)" "读取构建号"
assert_equal "3" "$(release_next_build_number 2)" "递增构建号"

release_validate_marketing_version "2.0.1"
if release_validate_marketing_version "2.0"; then
  echo "两段版本号不应通过校验" >&2
  exit 1
fi
if release_validate_build_number "0"; then
  echo "构建号 0 不应通过校验" >&2
  exit 1
fi

release_update_project_versions "$PROJECT_FILE" "2.0.0" "8"
assert_equal "2.0.0" "$(release_read_project_setting "$PROJECT_FILE" MARKETING_VERSION)" "更新语义版本"
assert_equal "8" "$(release_read_project_setting "$PROJECT_FILE" CURRENT_PROJECT_VERSION)" "更新构建号"

assert_script_contains 'DMG_PATH="$DIST_DIR/$APP_NAME-$MARKETING_VERSION-$BUILD_NUMBER-$PACKAGE_NAME.dmg"' "产物唯一命名"
assert_script_contains 'CURRENT_PROJECT_VERSION="$BUILD_NUMBER"' "构建号注入"
assert_script_contains 'MARKETING_VERSION="$MARKETING_VERSION"' "语义版本注入"
assert_script_contains 'if [ -e "$DMG_PATH" ]; then' "禁止覆盖旧产物"
assert_script_contains 'release_update_project_versions "$PROJECT_FILE" "$MARKETING_VERSION" "$NEXT_BUILD_NUMBER"' "发布后推进版本"
assert_equal "1.0.3" "$(release_read_project_setting "$ACTUAL_PROJECT_FILE" MARKETING_VERSION)" "工程语义版本"
assert_equal "7" "$(release_read_project_setting "$ACTUAL_PROJECT_FILE" CURRENT_PROJECT_VERSION)" "工程构建号"

echo "Release version tests passed"
