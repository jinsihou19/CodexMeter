#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexUsage"
WIDGET_PROCESS_NAME="CodexUsageWidgetExtension"
PROJECT_PATH="$ROOT_DIR/CodexUsage.xcodeproj"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
INSTALLED_APP_PATH="/Applications/$APP_NAME.app"
# Release 面向本机和小范围传包测试，保持纯 ad-hoc 签名，不依赖开发者证书或本机描述文件。
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
REVISION="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)"
if [ -n "$(git -C "$ROOT_DIR" status --porcelain 2>/dev/null || true)" ]; then
  REVISION="$REVISION-dirty"
fi
PACKAGE_TARGETS=(
  "arm64:arm64"
  "intel:x86_64"
)
LOCAL_PACKAGE_NAME="intel"
if [ "$(uname -m)" = "arm64" ]; then
  LOCAL_PACKAGE_NAME="arm64"
fi

mkdir -p "$DIST_DIR"

for PACKAGE_TARGET in "${PACKAGE_TARGETS[@]}"; do
  PACKAGE_NAME="${PACKAGE_TARGET%%:*}"
  PACKAGE_ARCH="${PACKAGE_TARGET##*:}"
  PACKAGE_BUILD_DIR="$BUILD_DIR/$PACKAGE_NAME"
  APP_PATH="$PACKAGE_BUILD_DIR/Release/$APP_NAME.app"
  DMG_ROOT="$PACKAGE_BUILD_DIR/dmg-root"
  DMG_PATH="$DIST_DIR/$APP_NAME-$REVISION-$PACKAGE_NAME.dmg"

  rm -rf "$PACKAGE_BUILD_DIR"

  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    SYMROOT="$PACKAGE_BUILD_DIR" \
    ARCHS="$PACKAGE_ARCH" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGN_ENTITLEMENTS="" \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    build

  codesign --verify --deep --strict --verbose=2 "$APP_PATH"

  APP_ARCHS="$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")"
  if [ "$APP_ARCHS" != "$PACKAGE_ARCH" ]; then
    echo "Unexpected $PACKAGE_NAME archs: $APP_ARCHS" >&2
    exit 1
  fi

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

  echo "DMG ($PACKAGE_NAME/$PACKAGE_ARCH): $DMG_PATH"
done

# WidgetKit 会保留 extension 进程；安装新版前一并结束，避免桌面继续使用旧时间线代码。
pkill -x "$WIDGET_PROCESS_NAME" 2>/dev/null || true
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$INSTALLED_APP_PATH"
ditto "$BUILD_DIR/$LOCAL_PACKAGE_NAME/Release/$APP_NAME.app" "$INSTALLED_APP_PATH"
open -n "$INSTALLED_APP_PATH"

echo "Installed ($LOCAL_PACKAGE_NAME): $INSTALLED_APP_PATH"
