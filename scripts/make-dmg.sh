#!/usr/bin/env bash
set -euo pipefail

# 打包 Qiaomi.app 为 DMG（含 Applications 快捷方式），输出到项目根目录。
# 用法: ./scripts/make-dmg.sh [版本号, 默认读取 Info.plist]

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/Qiaomi.app"

if [ ! -d "$APP_DIR" ]; then
  echo "Missing app bundle: run ./scripts/build.sh first." >&2
  exit 1
fi

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")"
fi

DMG_NAME="Qiaomi-${VERSION}.dmg"
STAGE_DIR="$ROOT_DIR/.build/dmg"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

cp -R "$APP_DIR" "$STAGE_DIR/Qiaomi.app"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$ROOT_DIR/$DMG_NAME"
hdiutil create \
  -volname "Qiaomi" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$ROOT_DIR/$DMG_NAME"

echo "Generated: $ROOT_DIR/$DMG_NAME"
