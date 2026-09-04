#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="余核"
VERSION="${VERSION:-1.9.0}"
DIST="$ROOT/dist"
ZIP_NAME="Yuhe-${VERSION}-macos-arm64.zip"

bash "$ROOT/scripts/package.sh"

mkdir -p "$DIST"
rm -rf "$DIST/${APP_NAME}.app" "$DIST/$ZIP_NAME" "$DIST/安装说明.txt"

cp -R "$ROOT/${APP_NAME}.app" "$DIST/${APP_NAME}.app"
xattr -cr "$DIST/${APP_NAME}.app" 2>/dev/null || true
codesign --force --deep --sign - "$DIST/${APP_NAME}.app"

cat > "$DIST/安装说明.txt" << 'EOF'
余核 - 安装说明

这不是 dmg / pkg 安装器，而是一个可以直接拖进「应用程序」的 Mac 软件。

系统要求
- Apple 芯片 Mac（M1 / M2 / M3 / M4）
- macOS 14 Sonoma 或更新
- 暂不支持 Intel Mac

安装
1. 解压 zip
2. 把「余核.app」拖到「应用程序」文件夹
3. 第一次打开：不要双击。按住 Control 点图标 -> 打开 -> 打开
   （没有苹果开发者签名，系统会拦一次，这样点才能过）
4. 菜单栏出现六边形图标后，点开即可

第一次打不开时
- 系统设置 -> 隐私与安全性 -> 仍要打开
- 或在终端执行：
  xattr -cr /Applications/余核.app
  open /Applications/余核.app

额度从哪来（各用各的账号，不会带你的登录态）
- Cursor：本机 Cursor 已登录
- Codex：本机已执行过 codex login
- Grok：本机已 grok login，或自行准备账号
- DeepSeek：在设置里填自己的 API Key

卸载
把「应用程序」里的「余核」拖进废纸篓即可。
EOF

(
  cd "$DIST"
  zip -qry "$ZIP_NAME" "${APP_NAME}.app" "安装说明.txt"
)

echo "Dist: $DIST/$ZIP_NAME"
ls -lh "$DIST/$ZIP_NAME"
