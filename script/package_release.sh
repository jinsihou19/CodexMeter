#!/usr/bin/env bash
set -euo pipefail

# 本文件构建、签名并安装 CodexMeter，并默认创建 GitHub Release、启用 Pages；可显式关闭远程发布。

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexMeter"
SCHEME_NAME="CodexMeter"
# 兼容标识：旧安装路径和 Sparkle 更新都依赖该包名，不能随展示名称一起修改。
COMPATIBLE_PRODUCT_NAME="CodexUsage"
WIDGET_PROCESS_NAME="CodexMeterWidgetExtension"
PROJECT_PATH="$ROOT_DIR/CodexMeter.xcodeproj"
PROJECT_FILE="$PROJECT_PATH/project.pbxproj"
BUILD_DIR="$ROOT_DIR/build/universal"
DIST_DIR="$ROOT_DIR/dist"
APPCAST_WORK_DIR="$BUILD_DIR/appcast"
INSTALLED_APP_PATH="/Applications/$COMPATIBLE_PRODUCT_NAME.app"
GITHUB_REPOSITORY="jinsihou19/CodexMeter"
PUBLISH_RELEASE="${CODEX_PUBLISH_RELEASE:-1}"
INSTALL_LOCAL="${CODEX_INSTALL_LOCAL:-1}"
source "$ROOT_DIR/script/release_version.sh"

# Release 面向本机和小范围传包测试，保持纯 ad-hoc 签名，不依赖开发者证书或本机描述文件。
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
PROJECT_MARKETING_VERSION="$(release_read_project_setting "$PROJECT_FILE" MARKETING_VERSION)"
MARKETING_VERSION="${CODEX_RELEASE_VERSION:-$PROJECT_MARKETING_VERSION}"
BUILD_NUMBER="${CODEX_BUILD_NUMBER:-$(release_read_project_setting "$PROJECT_FILE" CURRENT_PROJECT_VERSION)}"
release_validate_marketing_version "$MARKETING_VERSION" || {
  echo "Invalid CODEX_RELEASE_VERSION: $MARKETING_VERSION" >&2
  exit 1
}
release_validate_build_number "$BUILD_NUMBER" || {
  echo "Invalid CURRENT_PROJECT_VERSION: $BUILD_NUMBER" >&2
  exit 1
}
if [[ "$PUBLISH_RELEASE" != "0" && "$PUBLISH_RELEASE" != "1" ]]; then
  echo "CODEX_PUBLISH_RELEASE must be 0 or 1" >&2
  exit 1
fi
if [[ "$INSTALL_LOCAL" != "0" && "$INSTALL_LOCAL" != "1" ]]; then
  echo "CODEX_INSTALL_LOCAL must be 0 or 1" >&2
  exit 1
fi

NEXT_BUILD_NUMBER="$(release_next_build_number "$BUILD_NUMBER")"
DMG_PATH="$DIST_DIR/$APP_NAME-$MARKETING_VERSION-$BUILD_NUMBER-universal.dmg"
APPCAST_PATH="$DIST_DIR/appcast.xml"
RELEASE_NOTES_PATH="$DIST_DIR/release-notes.md"
APP_PATH="$BUILD_DIR/Release/$COMPATIBLE_PRODUCT_NAME.app"
RELEASE_TAG="v$MARKETING_VERSION-$BUILD_NUMBER"
DOWNLOAD_URL_PREFIX="https://github.com/jinsihou19/CodexMeter/releases/download/$RELEASE_TAG/"

# 查找 Swift Package Manager 下载的 Sparkle 发布工具；允许调用方显式指定以适配自定义 DerivedData。
find_sparkle_bin_dir() {
  if [ -n "${SPARKLE_BIN_DIR:-}" ]; then
    printf '%s\n' "$SPARKLE_BIN_DIR"
    return
  fi
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -type f \
    -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' \
    -print \
    -quit \
    | xargs -I{} dirname "{}"
}

if [ -e "$DMG_PATH" ]; then
  echo "Release artifact already exists: $DMG_PATH" >&2
  exit 1
fi

# 对外发布必须来自干净且已提交的工作区，避免 Release 标签和实际二进制内容不一致。
if [ "$PUBLISH_RELEASE" = "1" ]; then
  if ! git -C "$ROOT_DIR" diff --quiet || ! git -C "$ROOT_DIR" diff --cached --quiet \
    || [ -n "$(git -C "$ROOT_DIR" ls-files --others --exclude-standard)" ]; then
    echo "Publishing requires a clean git worktree" >&2
    exit 1
  fi
  command -v gh >/dev/null || {
    echo "GitHub CLI is required for publishing" >&2
    exit 1
  }
  gh auth status >/dev/null
fi

rm -rf "$BUILD_DIR"
mkdir -p "$DIST_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  SYMROOT="$BUILD_DIR" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build

SPARKLE_BIN_DIR="$(find_sparkle_bin_dir)"
GENERATE_APPCAST="$SPARKLE_BIN_DIR/generate_appcast"
if [ ! -x "$GENERATE_APPCAST" ]; then
  echo "Sparkle generate_appcast not found after resolving Xcode packages" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

APP_ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/$COMPATIBLE_PRODUCT_NAME")"
for REQUIRED_ARCH in arm64 x86_64; do
  if [[ " $APP_ARCHS " != *" $REQUIRED_ARCH "* ]]; then
    echo "Missing $REQUIRED_ARCH in app binary: $APP_ARCHS" >&2
    exit 1
  fi
done

DMG_ROOT="$BUILD_DIR/dmg-root"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP_PATH" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

# 每次只发布一个完整 Universal 包；历史版本由 GitHub Releases 保存，不生成增量文件。
mkdir -p "$APPCAST_WORK_DIR"
cp "$DMG_PATH" "$APPCAST_WORK_DIR/"
APPCAST_ARGUMENTS=(
  --download-url-prefix "$DOWNLOAD_URL_PREFIX"
  --maximum-versions 1
  --maximum-deltas 0
  -o "$APPCAST_PATH"
  "$APPCAST_WORK_DIR"
)
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" --ed-key-file - "${APPCAST_ARGUMENTS[@]}"
else
  "$GENERATE_APPCAST" "${APPCAST_ARGUMENTS[@]}"
fi

# Sparkle 会用兼容 App 包目录生成频道标题；仅替换展示标题，保留已签名 enclosure 的全部属性。
perl -0pi -e 's{(<channel>\s*<title>)[^<]*(</title>)}{$1CodexMeter$2}' "$APPCAST_PATH"

# 使用上一个 Release 到当前提交的差异生成分类说明，直接提交也不会被遗漏。
PREVIOUS_RELEASE_TAG="$(gh release list --repo "$GITHUB_REPOSITORY" --limit 1 --json tagName --jq '.[0].tagName // empty')"
NOTES_REVISION_RANGE="HEAD"
if [ -n "$PREVIOUS_RELEASE_TAG" ] && git -C "$ROOT_DIR" rev-parse --verify "$PREVIOUS_RELEASE_TAG^{commit}" >/dev/null 2>&1; then
  NOTES_REVISION_RANGE="$PREVIOUS_RELEASE_TAG..HEAD"
fi
release_write_notes \
  "$ROOT_DIR" \
  "$NOTES_REVISION_RANGE" \
  "$RELEASE_NOTES_PATH" \
  "$PREVIOUS_RELEASE_TAG" \
  "$RELEASE_TAG" \
  "$GITHUB_REPOSITORY"

# WidgetKit 会保留 extension 进程；本机安装前一并结束，Actions runner 则跳过该步骤。
if [ "$INSTALL_LOCAL" = "1" ]; then
  pkill -x "$WIDGET_PROCESS_NAME" 2>/dev/null || true
  pkill -x "$COMPATIBLE_PRODUCT_NAME" 2>/dev/null || true
  rm -rf "$INSTALLED_APP_PATH"
  ditto "$APP_PATH" "$INSTALLED_APP_PATH"
  open -n "$INSTALLED_APP_PATH"
fi

# 发布模式创建唯一 Release；Actions 会在同一任务中继续部署 appcast 到 Pages。
if [ "$PUBLISH_RELEASE" = "1" ]; then
  gh release create "$RELEASE_TAG" \
    "$DMG_PATH" \
    "$APPCAST_PATH" \
    --repo "$GITHUB_REPOSITORY" \
    --target "$(git -C "$ROOT_DIR" rev-parse HEAD)" \
    --title "$APP_NAME $MARKETING_VERSION ($BUILD_NUMBER)" \
    --notes-file "$RELEASE_NOTES_PATH"
fi

# 全部构建、安装和所选发布流程成功后再推进工程版本，失败发布不会消耗构建号。
release_update_project_versions "$PROJECT_FILE" "$MARKETING_VERSION" "$NEXT_BUILD_NUMBER"

echo "Released locally: $MARKETING_VERSION ($BUILD_NUMBER)"
echo "Next build number: $NEXT_BUILD_NUMBER"
echo "DMG: $DMG_PATH"
echo "Appcast: $APPCAST_PATH"
if [ "$INSTALL_LOCAL" = "1" ]; then
  echo "Installed: $INSTALLED_APP_PATH"
fi
if [ "$PUBLISH_RELEASE" = "1" ]; then
  echo "GitHub Release: https://github.com/$GITHUB_REPOSITORY/releases/tag/$RELEASE_TAG"
fi
