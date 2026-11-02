#!/bin/bash
# 生成带安装引导窗口的 DMG：左边 V2A.app，右边 Applications 文件夹别名
#
#   ./make_dmg.sh [App 路径] [版本号]
#
# 默认从 /Applications/V2A.app 取，版本号读 Info.plist。
set -euo pipefail
cd "$(dirname "$0")"

APP="${1:-/Applications/V2A.app}"
VERSION="${2:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
VOLNAME="V2A"
OUT="dist/V2A-$VERSION.dmg"

if [ ! -d "$APP" ]; then
  echo "找不到 $APP" >&2
  exit 1
fi
mkdir -p dist
rm -f "$OUT"

STAGE="$(mktemp -d)"
RW="$(mktemp -d)/V2A-rw.dmg"
MOUNT=""
cleanup() {
  if [ -n "$MOUNT" ]; then hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; fi
  rm -rf "$STAGE" "$(dirname "$RW")"
}
trap cleanup EXIT

echo "▸ 准备安装窗口内容"
ditto "$APP" "$STAGE/V2A.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$STAGE/.background"
cp assets/dmg/background.png "$STAGE/.background/background.png"

echo "▸ 创建可写镜像"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW" -quiet
MOUNT="$(hdiutil attach "$RW" -nobrowse -readwrite | tail -1 | awk -F'\t' '{print $NF}')"
echo "  挂载于 $MOUNT"

echo "▸ 设置窗口布局"
osascript <<AS || echo "  ⚠️ AppleScript 布局失败，将使用默认窗口（不影响拖拽安装）"
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 200, 740, 580}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.png"
    set position of item "V2A.app" of container window to {140, 182}
    set position of item "Applications" of container window to {400, 182}
    update without registering applications
    delay 1
    close
  end tell
end tell
AS

# 让 Finder 把布局写进 .DS_Store
sync
sleep 1
hdiutil detach "$MOUNT" -quiet
MOUNT=""

echo "▸ 压缩"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" -quiet
echo "✓ 生成 ${OUT}（$(du -h "$OUT" | cut -f1)）"
