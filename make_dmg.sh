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
# Finder 偶尔要过一会儿才认出新挂载的磁盘，先轮询
for i in $(seq 1 20); do
  if osascript -e "tell application \"Finder\" to exists disk \"$VOLNAME\"" 2>/dev/null | grep -q true; then break; fi
  sleep 0.5
done

layout() {
osascript <<AS

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
}

ok=0
for attempt in 1 2 3; do
  layout >/dev/null 2>&1 || true
  sync
  sleep 1
  if [ -f "$MOUNT/.DS_Store" ]; then ok=1; break; fi
  echo "  Finder 没写入布局，重试 ($attempt/3)"
  sleep 1
done

if [ "$ok" -ne 1 ]; then
  echo "✗ 安装窗口布局失败：.DS_Store 未生成" >&2
  exit 1
fi

hdiutil detach "$MOUNT" -quiet
MOUNT=""

echo "▸ 压缩"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" -quiet
echo "✓ 生成 ${OUT}（$(du -h "$OUT" | cut -f1)）"
