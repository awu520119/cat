#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/Qiaomi.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
PHOTOS_DIR="$RESOURCES_DIR/photos"
ACTIONS_DIR="$RESOURCES_DIR/actions"
MODULE_CACHE_DIR="$ROOT_DIR/.build/module-cache"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64|x86_64) ;;
  *) echo "Unsupported Mac architecture: $ARCH" >&2; exit 1 ;;
esac

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$PHOTOS_DIR" "$ACTIONS_DIR" "$MODULE_CACHE_DIR"

clang \
  -fobjc-arc \
  -fmodules \
  -fmodules-cache-path="$MODULE_CACHE_DIR" \
  -arch "$ARCH" \
  "$ROOT_DIR"/Sources/Qiaomi/*.m \
  -o "$MACOS_DIR/Qiaomi" \
  -framework Cocoa \
  -framework AVFoundation \
  -framework CoreImage \
  -framework CoreMedia \
  -framework CoreVideo \
  -framework ServiceManagement

cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

if [ -f "$ROOT_DIR/assets/icon/AppIcon.icns" ]; then
  cp "$ROOT_DIR/assets/icon/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

if [ -d "$ROOT_DIR/Resources/zh-Hans.lproj" ]; then
  mkdir -p "$RESOURCES_DIR/zh-Hans.lproj"
  cp "$ROOT_DIR"/Resources/zh-Hans.lproj/*.strings "$RESOURCES_DIR/zh-Hans.lproj/"
fi
if [ -d "$ROOT_DIR/Resources/en.lproj" ]; then
  mkdir -p "$RESOURCES_DIR/en.lproj"
  cp "$ROOT_DIR"/Resources/en.lproj/*.strings "$RESOURCES_DIR/en.lproj/"
fi

shopt -s nullglob nocaseglob
photo_files=(
  "$ROOT_DIR"/photos/*.jpg
  "$ROOT_DIR"/photos/*.jpeg
  "$ROOT_DIR"/photos/*.png
  "$ROOT_DIR"/photos/*.webp
  "$ROOT_DIR"/photos/*.heic
  "$ROOT_DIR"/photos/*.tiff
  "$ROOT_DIR"/photos/*.mp4
  "$ROOT_DIR"/photos/*.m4v
  "$ROOT_DIR"/photos/*.mov
)

if [ "${#photo_files[@]}" -gt 0 ]; then
  cp "${photo_files[@]}" "$PHOTOS_DIR/"
fi

action_files=(
  "$ROOT_DIR"/assets/actions/*.png
  "$ROOT_DIR"/assets/actions/*.webp
  "$ROOT_DIR"/assets/actions/*.jpg
  "$ROOT_DIR"/assets/actions/*.jpeg
)

if [ "${#action_files[@]}" -gt 0 ]; then
  cp "${action_files[@]}" "$ACTIONS_DIR/"
fi

chmod +x "$MACOS_DIR/Qiaomi"

echo "Built: $APP_DIR"
