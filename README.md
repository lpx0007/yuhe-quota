# 余核 · Quota HUD

macOS 顶部状态栏小工具。一个六边形图标，点开后查看 Cursor / Codex / DeepSeek / Grok 额度。

## 发给别人

第一次把 zip 发给对方即可。之后在设置里点「检查 / 安装」自动更新，不必每次再发安装包。

```bash
VERSION=2.0.0 bash scripts/release.sh
```

产物：`dist/Yuhe-2.0.0-macos-arm64.zip`  
更新源：GitHub Releases（免费、公开仓库）。

对方：解压 → 拖进「应用程序」→ **Control + 点图标 → 打开**（没有苹果开发者签名，双击会被拦）。
仅 Apple 芯片 + macOS 14+。对方用自己的 Cursor / Codex / Grok / DeepSeek 登录，不会带上你的 Key。

## 运行

```bash
bash scripts/package.sh
open "余核.app"
```

调试拉数：

```bash
swift run Yuhe --status
```
