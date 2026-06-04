#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexUsage"
PROJECT_PATH="$ROOT_DIR/CodexUsage.xcodeproj"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$BUILD_DIR/Release/$APP_NAME.app"
INSTALLED_APP_PATH="/Applications/$APP_NAME.app"
DMG_ROOT="$BUILD_DIR/dmg-root"
REVISION="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)"
if [ -n "$(git -C "$ROOT_DIR" status --porcelain 2>/dev/null || true)" ]; then
  REVISION="$REVISION-dirty"
fi
DMG_PATH="$DIST_DIR/$APP_NAME-$REVISION.dmg"

mkdir -p "$DIST_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination "platform=macOS" \
  SYMROOT="$BUILD_DIR" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  build

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

pkill -x "$APP_NAME" 2>/dev/null || true
rsync -a --delete "$APP_PATH/" "$INSTALLED_APP_PATH/"
open -n "$INSTALLED_APP_PATH"

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

echo "Installed: $INSTALLED_APP_PATH"
echo "DMG: $DMG_PATH"
