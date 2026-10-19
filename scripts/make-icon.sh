#!/usr/bin/env bash
set -euo pipefail

# 从动作素材生成 AppIcon.icns（暖奶油渐变背景 + 俏咪卡片主体）。
# 依赖: ImageMagick (magick) + iconutil（系统自带）

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_DIR="$ROOT_DIR/assets/icon"
WORK_DIR="$ROOT_DIR/.build/icon"

mkdir -p "$ICON_DIR" "$WORK_DIR"

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick is required: install magick first." >&2
  exit 1
fi

SOURCE="$ROOT_DIR/assets/actions/qiaomi-action-idle.png"
if [ ! -f "$SOURCE" ]; then
  echo "Missing source asset: $SOURCE" >&2
  exit 1
fi

magick -size 1024x1024 gradient:'#FFF6EA'-'#FFDCB0' "$WORK_DIR/bg.png"

magick "$WORK_DIR/bg.png" "$SOURCE" \
  -resize 880x880 \
  -gravity center \
  -composite \
  "$WORK_DIR/icon-1024.png"

rm -rf "$WORK_DIR/AppIcon.iconset"
mkdir -p "$WORK_DIR/AppIcon.iconset"

magick "$WORK_DIR/icon-1024.png" -resize 16x16  "$WORK_DIR/AppIcon.iconset/icon_16x16.png"
magick "$WORK_DIR/icon-1024.png" -resize 32x32  "$WORK_DIR/AppIcon.iconset/icon_16x16@2x.png"
magick "$WORK_DIR/icon-1024.png" -resize 32x32  "$WORK_DIR/AppIcon.iconset/icon_32x32.png"
magick "$WORK_DIR/icon-1024.png" -resize 64x64  "$WORK_DIR/AppIcon.iconset/icon_32x32@2x.png"
magick "$WORK_DIR/icon-1024.png" -resize 128x128 "$WORK_DIR/AppIcon.iconset/icon_128x128.png"
magick "$WORK_DIR/icon-1024.png" -resize 256x256 "$WORK_DIR/AppIcon.iconset/icon_128x128@2x.png"
magick "$WORK_DIR/icon-1024.png" -resize 256x256 "$WORK_DIR/AppIcon.iconset/icon_256x256.png"
magick "$WORK_DIR/icon-1024.png" -resize 512x512 "$WORK_DIR/AppIcon.iconset/icon_256x256@2x.png"
magick "$WORK_DIR/icon-1024.png" -resize 512x512 "$WORK_DIR/AppIcon.iconset/icon_512x512.png"
magick "$WORK_DIR/icon-1024.png" -resize 1024x1024 "$WORK_DIR/AppIcon.iconset/icon_512x512@2x.png"

iconutil -c icns "$WORK_DIR/AppIcon.iconset" -o "$ICON_DIR/AppIcon.icns"
cp "$WORK_DIR/icon-1024.png" "$ICON_DIR/AppIcon-1024.png"

echo "Generated: $ICON_DIR/AppIcon.icns"
