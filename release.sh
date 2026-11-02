#!/bin/bash
# 一条命令发版：改版本号 → 构建 → 打包 → 提交打 tag → 建 GitHub Release 并上传附件
#
#   ./release.sh 1.1.0              # 正式发布
#   ./release.sh 1.1.0 --dry-run    # 只构建打包，不推送
#
# 需要 GitHub Token（repo 权限），二选一：
#   export GH_TOKEN=ghp_xxx
#   echo ghp_xxx > .gh_token        # 已在 .gitignore 里
set -euo pipefail
cd "$(dirname "$0")"

REPO="Molank/v2a"
VERSION="${1:-}"
DRY_RUN=0
[ "${2:-}" = "--dry-run" ] && DRY_RUN=1

if [ -z "$VERSION" ]; then
  echo "用法: ./release.sh <版本号> [--dry-run]" >&2
  exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "版本号格式应为 1.2 或 1.2.3" >&2
  exit 1
fi

TOKEN="${GH_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f .gh_token ]; then
  TOKEN="$(tr -d '[:space:]' < .gh_token)"
fi
if [ -z "$TOKEN" ] && [ "$DRY_RUN" -eq 0 ]; then
  echo "缺少 GitHub Token：export GH_TOKEN=… 或写入 .gh_token" >&2
  exit 1
fi

echo "▸ 版本号写入 Info.plist：$VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist

echo "▸ 构建并安装"
./build.sh --install | tail -2

mkdir -p dist
ZIP="dist/V2A-$VERSION.zip"
rm -f "$ZIP"
echo "▸ 打包 $ZIP"
ditto -c -k --sequesterRsrc --keepParent "/Applications/V2A.app" "$ZIP"
du -h "$ZIP" | awk '{print "  " $1}'

DMG="dist/V2A-$VERSION.dmg"
echo "▸ 生成安装镜像 $DMG"
./make_dmg.sh "/Applications/V2A.app" "$VERSION" | tail -1 || { echo "DMG 生成失败" >&2; exit 1; }

if [ "$DRY_RUN" -eq 1 ]; then
  echo "▸ dry-run：跳过提交与发布"
  exit 0
fi

echo "▸ 提交并推送"
git add -A
if ! git diff --cached --quiet; then
  git commit -q -m "release: v$VERSION"
fi
git tag -f "v$VERSION" >/dev/null

AUTH=$(printf 'x-access-token:%s' "$TOKEN" | base64)
git -c http.extraheader="AUTHORIZATION: Basic $AUTH" push -q origin main
git -c http.extraheader="AUTHORIZATION: Basic $AUTH" push -q --force origin "v$VERSION"

echo "▸ 创建 Release"
cat > /tmp/v2a_release.json <<EOF
{
  "tag_name": "v$VERSION",
  "name": "V2A $VERSION",
  "draft": false,
  "prerelease": false,
  "target_commitish": "main",
  "body": "## V2A $VERSION\n\n### 安装\n1. 打开 \`V2A-$VERSION.dmg\`\n2. 把左边的 **V2A** 拖到右边的 **Applications** 文件夹\n3. 从「应用程序」启动\n\n也可以下载 \`V2A-$VERSION.zip\` 手动解压。\n\n首次打开若提示「无法验证开发者」，右键 App → 打开，或执行：\n\n\`\`\`bash\nxattr -dr com.apple.quarantine /Applications/V2A.app\n\`\`\`\n"
}
EOF

code=$(curl -s -o /tmp/v2a_release_resp.json -w "%{http_code}" -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases" \
  --data @/tmp/v2a_release.json)
if [ "$code" != "201" ]; then
  echo "创建 Release 失败（HTTP $code）：" >&2
  python3 -c "import json;d=json.load(open('/tmp/v2a_release_resp.json'));print(d.get('message'))" >&2 || true
  exit 1
fi
RELEASE_ID=$(python3 -c "import json;print(json.load(open('/tmp/v2a_release_resp.json'))['id'])")
PAGE=$(python3 -c "import json;print(json.load(open('/tmp/v2a_release_resp.json'))['html_url'])")

upload_asset() {
  local file="$1" type="$2"
  echo "▸ 上传 $(basename "$file")（$(du -m "$file" | cut -f1) MB）"
  local code
  code=$(curl -s -o /tmp/v2a_asset_resp.json -w "%{http_code}" -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: $type" \
    --data-binary "@$file" \
    "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=$(basename "$file")")
  if [ "$code" != "201" ]; then
    echo "上传 $(basename "$file") 失败（HTTP $code）" >&2
    exit 1
  fi
}

upload_asset "$DMG" "application/x-apple-diskimage"
upload_asset "$ZIP" "application/zip"

echo ""
echo "✓ 发布完成：$PAGE"
echo "  下载地址：https://github.com/$REPO/releases/download/v$VERSION/$(basename "$ZIP")"
