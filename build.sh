#!/bin/bash
# 编译并组装「V2A.app」
# 直连 Xcode 工具链，避免 /usr/bin/clang 的许可检查；模块缓存放在本目录，不污染系统临时目录。
set -euo pipefail
cd "$(dirname "$0")"

TC="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
APP="V2A.app"
# 链接时显式声明 SDK 版本：否则 LC_BUILD_VERSION 会记成 minos 的 14.0，
# 系统会把 App 当成旧 SDK 构建，退回旧版窗口控件（非 Liquid Glass）
SDK_VERSION="$(plutil -extract Version raw "$SDK/SDKSettings.json" 2>/dev/null || echo 27.0)"
if [ -L "$SDK" ]; then SDK="$(readlink -f "$SDK")"; fi

if [ ! -x "$TC/swiftc" ]; then
  echo "找不到 Swift 工具链：$TC/swiftc" >&2
  exit 1
fi

rm -rf build "$APP"
mkdir -p build/mcache .tmp

CLANG_MODULE_CACHE_PATH="$PWD/build/mcache" TMPDIR="$PWD/.tmp" \
"$TC/swiftc" \
  -O -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -sdk "$SDK" \
  -module-cache-path "$PWD/build/mcache" \
  Sources/*.swift \
  -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION" \
  -o "build/V2A"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
cp "build/V2A" "$APP/Contents/MacOS/V2A"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp assets/icon.png "$APP/Contents/Resources/AppIcon.png"
cp -l bin/ffmpeg bin/ffprobe "$APP/Contents/Resources/bin/" 2>/dev/null || cp bin/ffmpeg bin/ffprobe "$APP/Contents/Resources/bin/"
if [ -f bin/yt-dlp ]; then
  cp -l bin/yt-dlp "$APP/Contents/Resources/bin/" 2>/dev/null || cp bin/yt-dlp "$APP/Contents/Resources/bin/"
  chmod +x "$APP/Contents/Resources/bin/yt-dlp"
fi
chmod +x "$APP/Contents/MacOS/V2A" "$APP/Contents/Resources/bin/ffmpeg" "$APP/Contents/Resources/bin/ffprobe"

printf 'APPL????' > "$APP/Contents/PkgInfo"

# 在临时目录里签名：同步盘会给 bundle 打上 FinderInfo，codesign 会拒绝盖资源封印
STAGE="$(mktemp -d)/V2A.app"
cp -R "$APP" "$STAGE"
xattr -cr "$STAGE" 2>/dev/null || true
codesign --force --deep -s - "$STAGE" >/dev/null 2>&1 || true
xattr -cr "$STAGE" 2>/dev/null || true
rm -rf "$APP"
mv "$STAGE" "$APP"
rmdir "$(dirname "$STAGE")" 2>/dev/null || true

# cp -R 会打断硬链接，把 ffmpeg/ffprobe 重新链回 bin/（内容一致，不影响签名封印）
for tool in ffmpeg ffprobe yt-dlp; do
  if [ -f "bin/$tool" ] && [ -f "$APP/Contents/Resources/bin/$tool" ]; then
    rm -f "$APP/Contents/Resources/bin/$tool"
    cp -l "bin/$tool" "$APP/Contents/Resources/bin/$tool" 2>/dev/null \
      || cp "bin/$tool" "$APP/Contents/Resources/bin/$tool"
  fi
done

# 中间产物（模块缓存约 140MB）用完即清
rm -rf build .tmp

if [ "${1:-}" = "--install" ]; then
  ditto "$APP" "/Applications/$APP"
  rm -rf "$APP"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "/Applications/$APP" 2>/dev/null || true
  echo "✓ 已安装到 /Applications/${APP}（本地副本已清理）"
  du -sh "/Applications/$APP"
else
  echo "✓ 已生成 $APP"
  du -sh "$APP"
fi
